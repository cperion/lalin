-- lalin.syntax.stmt

local Ast = require("lalin.syntax.ast")
local Expr = require("lalin.syntax.expr")
local Type = require("lalin.syntax.type")

local Stmt = {}

local function stop_set(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

local function parse_expr_list_until_no_comma(lex, ctx)
  local items = {}
  items[#items + 1] = Expr.parse(lex, ctx)
  while lex:next_if(",") do
    items[#items + 1] = Expr.parse(lex, ctx)
  end
  return items
end

local function parse_named_payload(lex, ctx)
  local fields = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      local mark = lex:mark()
      local key
      if lex:peek().kind == "name" and lex:peek(1).value == "=" then
        key = lex:next().value
        lex:expect("=")
      else
        lex:restore(mark)
      end
      fields[#fields + 1] = { key = key, value = Expr.parse(lex, ctx) }
    until not lex:next_if(",")
    lex:expect(")")
  end
  return fields
end

function Stmt.parse_block(lex, ctx, stops)
  stops = stop_set(stops or { "end" })
  local items = {}
  lex:skip_separators()
  while not lex:at_eof() and not stops[lex:peek().value] do
    items[#items + 1] = Stmt.parse(lex, ctx)
    lex:skip_separators()
  end
  return items
end

function Stmt.parse(lex, ctx)
  ctx.lex = lex
  local t = lex:peek()

  if t.value == "requires" then
    local start = lex:next()
    local exprs = parse_expr_list_until_no_comma(lex, ctx)
    return Ast.node("StmtRequires", { exprs = exprs }, Ast.origin(lex, start, lex.last, "parsed:requires"))

  elseif t.value == "return" then
    local start = lex:next()
    local values = {}
    local nxt = lex:peek().value
    if nxt ~= "end" and nxt ~= "else" and nxt ~= "elseif" and nxt ~= ";" and nxt ~= "," and lex:peek().kind ~= "eof" then
      values = parse_expr_list_until_no_comma(lex, ctx)
    end
    return Ast.node("StmtReturn", { values = values }, Ast.origin(lex, start, lex.last or start, "parsed:return"))

  elseif t.value == "if" then
    local start = lex:next()
    local cond = Expr.parse(lex, ctx)
    lex:expect("then")
    local then_body = Stmt.parse_block(lex, ctx, { "elseif", "else", "end" })
    local elseif_blocks = {}
    while lex:next_if("elseif") do
      local etok = lex.last
      local ec = Expr.parse(lex, ctx)
      lex:expect("then")
      elseif_blocks[#elseif_blocks + 1] = Ast.node("ElseIf", {
        cond = ec,
        body = Stmt.parse_block(lex, ctx, { "elseif", "else", "end" }),
      }, Ast.origin(lex, etok, lex.last, "parsed:elseif"))
    end
    local else_body = nil
    if lex:next_if("else") then
      else_body = Stmt.parse_block(lex, ctx, { "end" })
    end
    lex:expect("end")
    return Ast.node("StmtIf", { cond = cond, then_body = then_body, elseif_blocks = elseif_blocks, else_body = else_body }, Ast.origin(lex, start, lex.last, "parsed:if"))

  elseif t.value == "for" then
    local start = lex:next()
    local index = lex:expect_name("loop index").value
    lex:expect("in")
    local producer = lex:expect_name("loop producer")
    if producer.value ~= "range" and producer.value ~= "range_nd" and producer.value ~= "window_nd" and producer.value ~= "tiled_nd" then
      lex:error_at(producer, "expected Lalin loop producer range/range_nd/window_nd/tiled_nd")
    end
    local args = {}
    if lex:next_if("(") then
      if not lex:next_if(")") then
        repeat args[#args + 1] = Expr.parse(lex, ctx) until not lex:next_if(",")
        lex:expect(")")
      end
    elseif lex:peek().value == "{" then
      args[#args + 1] = Expr.parse(lex, ctx)
    else
      lex:error_at(lex:peek(), "expected loop producer arguments")
    end
    lex:expect("do")
    local body = Stmt.parse_block(lex, ctx, { "end" })
    lex:expect("end")
    return Ast.node("StmtForRange", { index = index, producer = producer.value, args = args, body = body }, Ast.origin(lex, start, lex.last, "parsed:for_range"))

  elseif t.value == "let" or t.value == "var" then
    local start = lex:next()
    local mutable = start.value == "var"
    local name = lex:expect_name("local name")
    lex:expect(":")
    local ty = Type.parse(lex, ctx)
    local init = nil
    if lex:next_if("=") then init = Expr.parse(lex, ctx) end
    return Ast.node(mutable and "StmtVar" or "StmtLet", { name = name.value, type = ty, init = init }, Ast.origin(lex, start, lex.last, "parsed:local"))

  elseif t.value == "jump" then
    local start = lex:next()
    local target = lex:expect_name("jump target").value
    local payload = {}
    if lex:peek().value == "(" then payload = parse_named_payload(lex, ctx) end
    return Ast.node("StmtJump", { target = target, payload = payload }, Ast.origin(lex, start, lex.last, "parsed:jump"))

  elseif t.value == "emit" then
    local start = lex:next()
    local callee = Expr.parse(lex, ctx)
    local handlers = nil
    if lex:peek().value == "{" then handlers = Expr.parse(lex, ctx) end
    return Ast.node("StmtEmit", { callee = callee, handlers = handlers }, Ast.origin(lex, start, lex.last, "parsed:emit"))

  else
    local start = lex:peek()
    local left = Expr.parse(lex, ctx)
    local op = lex:peek().value
    if op == "=" or op == "+=" or op == "-=" or op == "*=" or op == "/=" then
      local optok = lex:next()
      local value = Expr.parse(lex, ctx)
      return Ast.node("StmtAssign", { op = op, place = left, value = value }, Ast.origin(lex, start, lex.last, "parsed:assign"))
    end
    return Ast.node("StmtExpr", { expr = left }, Ast.origin(lex, start, lex.last or start, "parsed:stmt"))
  end
end

return Stmt
