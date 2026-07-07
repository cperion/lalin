-- lalin.syntax_v2.stmt
-- Statement parser producing LalinTree ASDL directly.
-- Loop statements (for/range) produce intermediate tables that get lowered
-- in the pipeline; everything else is direct schema_v2.

local Ast = require("lalin.syntax_v2.ast")
local Expr = require("lalin.syntax_v2.expr")
local Type = require("lalin.syntax_v2.type")

-- Load schema_v2 types
require("lalin.schema_v2")
local Tree = package.loaded["lalin.schema_v2.tree"]
local Core = package.loaded["lalin.schema_v2.core"]
local Bind = package.loaded["lalin.schema_v2.bind"]
local Ty = package.loaded["lalin.schema_v2.type"]

local Stmt = {}

local function name_ref(n)
  return Tree.ExprRef(Tree.ExprSurface, Bind.ValueRefName(n))
end

local function block_label(n)
  return Tree.BlockLabel(n)
end

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
      local key
      local value
      if lex:peek().kind == "name" and lex:peek(1).value == "=" then
        key = lex:next().value
        lex:expect("=")
        value = Expr.parse(lex, ctx)
      elseif lex:peek().kind == "name" and (lex:peek(1).value == "," or lex:peek(1).value == ")") then
        local name = lex:next()
        key = name.value
        value = name_ref(name.value)
      else
        value = Expr.parse(lex, ctx)
      end
      fields[#fields + 1] = { key = key, value = value }
    until not lex:next_if(",")
    lex:expect(")")
  end
  return fields
end

local function jump_args_from_payload(payload)
  local out = {}
  for _, f in ipairs(payload or {}) do
    out[#out + 1] = Tree.JumpArg(f.key or "", f.value)
  end
  return out
end

-- Helpers for for-loop lowering (plain tables, not Ast.node)
local function positional(value) return { value = value } end
local function keyed(key, value) return { key = key, value = value } end
local function number_lit(value)
  return Tree.ExprLit(Tree.ExprSurface, Core.LitInt(tostring(value)))
end
local function string_lit(value)
  local raw = string.format("%q", tostring(value))
  return Tree.ExprLit(Tree.ExprSurface, Core.LitString(raw))
end

local function synthetic_record(fields)
  -- Returns a plain table mimicking the old Record AST for for_to_loop consumption
  local rec = { tag = "Record", fields = {} }
  for i, f in ipairs(fields) do rec.fields[i] = f end
  return rec
end

local function parse_range_domain(lex, ctx)
  local start = Expr.parse(lex, ctx)
  lex:expect("..")
  local stop = Expr.parse(lex, ctx)
  local step = nil
  if lex:next_if("..") then
    step = Expr.parse(lex, ctx)
  end
  local fields = { positional(start), positional(stop) }
  if step ~= nil then fields[#fields + 1] = positional(step) end
  return synthetic_record(fields)
end

local function parse_range_domain_list(lex, ctx)
  local items = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat
      items[#items + 1] = positional(parse_range_domain(lex, ctx))
    until not lex:next_if(",")
    lex:expect(")")
  end
  return synthetic_record(items)
end

local function parse_boundary_value(lex)
  if lex:peek().kind == "string" then
    return Expr.parse(lex, {})
  end
  return string_lit(lex:expect_name("window boundary").value)
end

local function parse_window_domain(lex, ctx)
  local axes = {}
  local before = number_lit(0)
  local after = number_lit(0)
  local boundary = string_lit("reject")
  lex:expect("(")
  axes[#axes + 1] = positional(parse_range_domain(lex, ctx))
  while lex:next_if(",") do
    local key = lex:expect_name("window option").value
    lex:expect("=")
    if key == "before" then
      before = Expr.parse(lex, ctx)
    elseif key == "after" then
      after = Expr.parse(lex, ctx)
    elseif key == "boundary" then
      boundary = parse_boundary_value(lex)
    else
      lex:error_at(lex.last, "unknown window option `" .. tostring(key) .. "`")
    end
  end
  lex:expect(")")
  local window = synthetic_record({ positional(before), positional(after), keyed("boundary", boundary) })
  return synthetic_record({
    keyed("axes", synthetic_record(axes)),
    keyed("windows", synthetic_record({ positional(window) })),
  })
end

local function parse_loop_domain(lex, ctx)
  if lex:next_if("tiled") then
    lex:expect("grid")
    local axes = parse_range_domain_list(lex, ctx)
    lex:expect("by")
    local tiles = {}
    repeat
      tiles[#tiles + 1] = Expr.parse(lex, ctx)
    until not lex:next_if(",")
    return "tiled_nd", { synthetic_record({
      keyed("axes", axes),
      keyed("tiles", synthetic_record((function()
        local out = {}
        for i, tile in ipairs(tiles) do out[i] = positional(tile) end
        return out
      end)())),
    }) }
  elseif lex:next_if("grid") then
    return "range_nd", { synthetic_record({ keyed("axes", parse_range_domain_list(lex, ctx)) }) }
  elseif lex:next_if("window") then
    return "window_nd", { parse_window_domain(lex, ctx) }
  end
  return "range", { parse_range_domain(lex, ctx) }
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

  if t.value == "[" then
    local raw, open, close = Ast.consume_balanced_from_open(lex)
    local refs = Ast.extract_refs(raw)
    Ast.add_refs(ctx, refs)
    return Ast.host_eval(raw, refs, Ast.origin(lex, open, close, "parsed:host_eval"), "stmts")

  elseif t.value == "requires" then
    local start = lex:next()
    local exprs = parse_expr_list_until_no_comma(lex, ctx)
    -- Return intermediate; contracts are extracted by decl parser
    return {
      tag = "StmtRequires",
      exprs = exprs,
      origin = Ast.origin(lex, start, lex.last, "parsed:requires"),
      is_requires = true,
    }

  elseif t.value == "return" then
    local start = lex:next()
    local values = {}
    local nxt = lex:peek().value
    if nxt ~= "end" and nxt ~= "else" and nxt ~= "elseif" and nxt ~= ";" and nxt ~= "," and lex:peek().kind ~= "eof" then
      values = parse_expr_list_until_no_comma(lex, ctx)
    end
    if #values == 0 then
      return Tree.StmtReturnVoid(Tree.StmtSurface)
    elseif #values == 1 then
      return Tree.StmtReturnValue(Tree.StmtSurface, values[1])
    else
      lex:error_at(start, "return accepts at most one value")
    end

  elseif t.value == "if" then
    local start = lex:next()
    local cond = Expr.parse(lex, ctx)
    lex:expect("then")
    local then_body = Stmt.parse_block(lex, ctx, { "elseif", "else", "end" })
    local else_body = {}
    while lex:next_if("elseif") do
      local ec = Expr.parse(lex, ctx)
      lex:expect("then")
      local eb = Stmt.parse_block(lex, ctx, { "elseif", "else", "end" })
      else_body = { Tree.StmtIf(Tree.StmtSurface, ec, eb, else_body) }
    end
    if lex:next_if("else") then
      else_body = Stmt.parse_block(lex, ctx, { "end" })
    end
    lex:expect("end")
    return Tree.StmtIf(Tree.StmtSurface, cond, then_body, else_body)

  elseif t.value == "switch" then
    local start = lex:next()
    local value = Expr.parse(lex, ctx)
    lex:expect("do")
    lex:skip_separators()
    local arms = {}
    local variant_arms = {}
    local default_body = nil
    while not lex:at_eof() and lex:peek().value ~= "end" do
      if lex:peek().value == "case" then
        local ctok = lex:next()
        local key = Expr.parse(lex, ctx)
        lex:expect("then")
        local body = Stmt.parse_block(lex, ctx, { "case", "default", "end" })
        arms[#arms + 1] = Tree.SwitchStmtArm(Stmt.switch_key(key), body)
      elseif lex:peek().value == "default" then
        lex:next()
        lex:expect("then")
        default_body = Stmt.parse_block(lex, ctx, { "end" })
      else
        lex:error_at(lex:peek(), "expected `case`, `default`, or `end` in switch")
      end
      lex:skip_separators()
    end
    lex:expect("end")
    return Tree.StmtSwitch(Tree.StmtSurface, value, arms, variant_arms, default_body or {})

  elseif t.value == "for" then
    lex:error_at(t, "source loops use `loop`, not `for`")

  elseif t.value == "loop" then
    local start = lex:next()
    local indexes = { lex:expect_name("loop index").value }
    while lex:next_if(",") do
      indexes[#indexes + 1] = lex:expect_name("loop index").value
    end
    local index = indexes[1]
    lex:expect("in")
    local producer, args = parse_loop_domain(lex, ctx)
    lex:expect("do")
    local body = Stmt.parse_block(lex, ctx, { "end" })
    lex:expect("end")
    -- Return intermediate for for_to_loop lowering
    return {
      tag = "StmtForRange",
      index = index,
      indexes = indexes,
      producer = producer,
      args = args,
      result_type = nil,
      body = body,
      origin = Ast.origin(lex, start, lex.last, "parsed:loop"),
    }

  elseif t.value == "fold" then
    local start = lex:next()
    local name = lex:expect_name("fold accumulator").value
    local ty = Type.parse(lex, ctx)
    lex:expect("=")
    local init = Expr.parse(lex, ctx)
    lex:expect("by")
    local by = lex:expect_name("fold reducer").value
    lex:expect("step")
    local step = Expr.parse(lex, ctx)
    return {
      tag = "StmtFold",
      name = name,
      type = ty,
      init = init,
      by = by,
      step = step,
      origin = Ast.origin(lex, start, lex.last, "parsed:fold"),
    }

  elseif t.value == "scan" then
    local start = lex:next()
    local name = lex:expect_name("scan accumulator").value
    local ty = Type.parse(lex, ctx)
    lex:expect("=")
    local init = Expr.parse(lex, ctx)
    lex:expect("by")
    local by = lex:expect_name("scan reducer").value
    local axis = nil
    if lex:next_if("axis") then
      lex:error_at(lex.last, "scan axis uses `over`, not `axis`")
    end
    if lex:next_if("over") then
      if lex:peek().kind == "name" then
        axis = lex:next().value
      else
        axis = Expr.parse(lex, ctx)
      end
    end
    lex:expect("step")
    local step = Expr.parse(lex, ctx)
    lex:expect("into")
    local into = Expr.parse(lex, ctx)
    return {
      tag = "StmtScan",
      name = name,
      type = ty,
      init = init,
      by = by,
      axis = axis,
      step = step,
      into = into,
      origin = Ast.origin(lex, start, lex.last, "parsed:scan"),
    }
  elseif t.value == "let" or t.value == "var" then
    local start = lex:next()
    local mutable = start.value == "var"
    local name_tok = lex:expect_name("local name")
    local ty = Type.parse(lex, ctx)
    local init = nil
    if lex:next_if("=") then init = Expr.parse(lex, ctx) end
    -- Return intermediate: type is HostEval, resolved during lowering
    return {
      tag = mutable and "StmtVar" or "StmtLet",
      name = name_tok.value,
      type = ty,
      init = init,
      origin = Ast.origin(lex, start, lex.last, "parsed:local"),
    }

  elseif t.value == "jump" then
    local start = lex:next()
    local target = lex:expect_name("jump target").value
    local payload = {}
    if lex:peek().value == "(" then payload = parse_named_payload(lex, ctx) end
    return Tree.StmtJump(Tree.StmtSurface, block_label(target), jump_args_from_payload(payload))

  elseif t.value == "emit" or t.value == "call" then
    local start = lex:next()
    local first = lex:expect_name("region name")
    local callee_path = { first.value }
    local callee = name_ref(first.value)
    while lex:next_if(".") do
      local part = lex:expect_name("qualified region name")
      callee_path[#callee_path + 1] = part.value
      callee = Tree.ExprDot(Tree.ExprSurface, callee, part.value)
    end
    lex:expect("(")
    local data_args, cont_wiring = {}, {}
    if not lex:next_if(")") then
      repeat
        if lex:peek().value == ";" then break end
        data_args[#data_args + 1] = Expr.parse(lex, ctx)
      until not lex:next_if(",") or lex:peek().value == ";"
      if lex:next_if(";") then
        repeat
          local cname = lex:expect_name("continuation name").value
          local target = cname
          if lex:next_if("=") then
            target = lex:expect_name("continuation block").value
          end
          local payload = {}
          if lex:peek().value == "(" then payload = parse_named_payload(lex, ctx) end
          cont_wiring[#cont_wiring + 1] = { name = cname, target = target, payload = payload }
        until not lex:next_if(",")
      end
      lex:expect(")")
    end
    if start.value == "call" then
      return Tree.StmtRegionCall(
        Tree.StmtSurface,
        "lln.call.",
        Tree.RegionInvokeTarget(Stmt._region_path(callee_path)),
        data_args,
        Stmt._region_wiring(cont_wiring)
      )
    else
      return Tree.StmtRegionEmit(
        Tree.StmtSurface,
        "lln.emit.",
        Tree.RegionInvokeTarget(Stmt._region_path(callee_path)),
        data_args,
        Stmt._region_wiring(cont_wiring)
      )
    end

  elseif t.value == "yield" then
    local start = lex:next()
    local values = {}
    local nxt = lex:peek().value
    if nxt ~= "end" and nxt ~= "else" and nxt ~= "elseif" and nxt ~= ";" and nxt ~= "," and lex:peek().kind ~= "eof" then
      values = parse_expr_list_until_no_comma(lex, ctx)
    end
    if #values == 0 then
      return Tree.StmtYieldVoid(Tree.StmtSurface)
    else
      return Tree.StmtYieldValue(Tree.StmtSurface, values[1])
    end

  else
    -- Expression statement or assignment
    local start = lex:peek()
    local left = Expr.parse(lex, ctx)
    local op = lex:peek().value
    if op == "=" or op == "+=" or op == "-=" or op == "*=" or op == "/=" then
      local optok = lex:next()
      local value = Expr.parse(lex, ctx)
      if op == "=" then
        return Tree.StmtSet(Tree.StmtSurface, Expr.to_place(left), value)
      else
        lex:error_at(optok, "compound assignment " .. tostring(op) .. " is not yet supported")
      end
    end
    return Tree.StmtExpr(Tree.StmtSurface, left)
  end
end

--- Build a Core.Path from name parts.
function Stmt._region_path(parts)
  local names = {}
  for i, p in ipairs(parts or {}) do names[i] = Core.Name(p) end
  return Core.Path(names)
end

--- Build region cont wiring.
function Stmt._region_wiring(items)
  local out = {}
  for i, wire in ipairs(items or {}) do
    out[i] = Tree.RegionContWire(wire.name,
      Tree.RegionWireBlock(block_label(wire.target), jump_args_from_payload(wire.payload)))
  end
  return out
end

--- Convert a parsed switch case key to a SwitchKey.
function Stmt.switch_key(expr)
  local asdl = require("lalin.asdl")
  local cls = asdl.classof(expr)
  if cls == Tree.ExprLit then
    local litcls = asdl.classof(expr.value)
    if litcls == Core.LitInt then return Tree.SwitchKeyInt(expr.value.raw) end
    if litcls == Core.LitBool then return Tree.SwitchKeyBool(expr.value.value) end
    if litcls == Core.LitString then return Tree.SwitchKeyExpr(expr) end
  elseif cls == Tree.ExprRef then
    local rcls = asdl.classof(expr.ref)
    if rcls == Bind.ValueRefName then return Tree.SwitchKeyName(expr.ref.name) end
  end
  return Tree.SwitchKeyExpr(expr)
end

return Stmt
