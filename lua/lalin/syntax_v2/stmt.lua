-- lalin.syntax_v2.stmt
-- Statement parser producing LalinTree ASDL directly.
-- Loop statements (for/range) produce intermediate tables that get lowered
-- in the pipeline; everything else is direct schema_v2.

local Ast = require("lalin.syntax_v2.ast")
local Roles = require("lalin.syntax_v2.roles")
local Expr = require("lalin.syntax_v2.expr")
local Type = require("lalin.syntax_v2.type")

-- Load schema_v2 types
require("lalin.schema_v2")
local Tree = package.loaded["lalin.schema_v2.tree"]
local Core = package.loaded["lalin.schema_v2.core"]
local Bind = package.loaded["lalin.schema_v2.bind"]
local Ty = package.loaded["lalin.schema_v2.type"]
local P  = package.loaded["lalin.schema_v2.parse"]
local asdl = require("lalin.asdl")

local Stmt = {}

local function name_ref(n)
  return Tree.ExprRef(Tree.ExprSurface, Bind.ValueRefName(n))
end

local function stmt_known(stmt)
  if stmt == nil then return nil end
  return P.StmtKnown(stmt)
end

-- Unwrap ParsedStmt[] → LalinTree.Stmt[] for use in StmtIf etc.
local function unwrap_stmts(parsed_stmts)
  local out = {}
  for _, ps in ipairs(parsed_stmts or {}) do
    if asdl.classof(ps) == P.StmtKnown then
      out[#out + 1] = ps.stmt
    else
      -- StmtLetParsed etc. pass through for later lowering
      out[#out + 1] = ps
    end
  end
  return out
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

-- Contract surface keywords are recognized at the parse boundary into
-- typed ParsedContract leaves (mirroring the loop-reducer keyword pattern);
-- the leaves own FuncContract construction.
local unary_contract_constructors = {
  readonly = P.ParsedContractReadonly,
  writeonly = P.ParsedContractWriteonly,
  noalias = P.ParsedContractNoAlias,
  invalidate = P.ParsedContractInvalidate,
  preserve = P.ParsedContractPreserve,
}
local binary_contract_constructors = {
  bounds = P.ParsedContractBounds,
  disjoint = P.ParsedContractDisjoint,
  same_len = P.ParsedContractSameLen,
}

local function parse_contract_args_group(lex, ctx)
  lex:expect("(")
  local args = {}
  if not lex:next_if(")") then
    repeat
      args[#args + 1] = Expr.parse(lex, ctx)
    until not lex:next_if(",")
    lex:expect(")")
  end
  return args
end

local function parse_contract_call(lex, ctx)
  local name_tok = lex:expect_name("contract name")
  local name = name_tok.value
  local first = parse_contract_args_group(lex, ctx)
  if lex:peek().value == "(" then
    local second = parse_contract_args_group(lex, ctx)
    local ctor = binary_contract_constructors[name]
    if ctor == nil then
      lex:error_at(name_tok, "contract `" .. name .. "` is unary and takes a single argument, not `(...)(...)`")
    end
    if #first ~= 1 or #second ~= 1 then
      lex:error_at(name_tok, "binary contract `" .. name .. "` expects exactly one argument in each group, e.g. bounds(base)(len)")
    end
    return ctor(first[1], second[1])
  end
  local ctor = unary_contract_constructors[name]
  if ctor == nil then
    lex:error_at(name_tok, "contract `" .. name .. "` is curried and expects two argument groups, e.g. bounds(base)(len)")
  end
  if #first ~= 1 then
    lex:error_at(name_tok, "unary contract `" .. name .. "` expects exactly one argument")
  end
  return ctor(first[1])
end

local function parse_contracts(lex, ctx)
  local contracts = { parse_contract_call(lex, ctx) }
  while lex:next_if(",") do
    contracts[#contracts + 1] = parse_contract_call(lex, ctx)
  end
  return contracts
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

local function number_lit(value)
  return Tree.ExprLit(Tree.ExprSurface, Core.LitInt(tostring(value)))
end

local function parse_range_axis(lex, ctx)
  local start = Expr.parse(lex, ctx)
  lex:expect("..")
  local stop = Expr.parse(lex, ctx)
  local step = number_lit(1)
  if lex:next_if("..") then step = Expr.parse(lex, ctx) end
  return P.ParsedLoopAxis(start, stop, step)
end

local function parse_range_axes(lex, ctx)
  local axes = {}
  lex:expect("(")
  if not lex:next_if(")") then
    repeat axes[#axes + 1] = parse_range_axis(lex, ctx) until not lex:next_if(",")
    lex:expect(")")
  end
  return axes
end

local boundary_by_name = {
  reject = Tree.ControlWindowReject,
  clamp = Tree.ControlWindowClamp,
  wrap = Tree.ControlWindowWrap,
  zero = Tree.ControlWindowZero,
}

local function parse_boundary(lex)
  local tok = lex:next()
  local name = tostring(tok.value or ""):gsub('^"', ""):gsub('"$', "")
  local boundary = boundary_by_name[name]
  if boundary == nil then
    lex:error_at(tok, "window boundary must be reject, clamp, wrap, or zero")
  end
  return boundary
end

local function parse_window_domain(lex, ctx)
  local before, after = number_lit(0), number_lit(0)
  local boundary = Tree.ControlWindowReject
  lex:expect("(")
  local axis = parse_range_axis(lex, ctx)
  while lex:next_if(",") do
    local key = lex:expect_name("window option").value
    lex:expect("=")
    if key == "before" then before = Expr.parse(lex, ctx)
    elseif key == "after" then after = Expr.parse(lex, ctx)
    elseif key == "boundary" then boundary = parse_boundary(lex)
    else lex:error_at(lex.last, "unknown window option `" .. tostring(key) .. "`") end
  end
  lex:expect(")")
  return P.ParsedLoopWindowND(
    { axis }, { P.ParsedWindowAxis(before, after, boundary) })
end

local function parse_loop_domain(lex, ctx)
  if lex:next_if("tiled") then
    lex:expect("grid")
    local axes = parse_range_axes(lex, ctx)
    lex:expect("by")
    local tiles = {}
    repeat tiles[#tiles + 1] = Expr.parse(lex, ctx) until not lex:next_if(",")
    return P.ParsedLoopTiledND(axes, tiles)
  elseif lex:next_if("grid") then
    return P.ParsedLoopRangeND(parse_range_axes(lex, ctx))
  elseif lex:next_if("window") then
    return parse_window_domain(lex, ctx)
  end
  return P.ParsedLoopRangeND({ parse_range_axis(lex, ctx) })
end

local reducer_by_name = {
  add = P.ParsedLoopAdd, mul = P.ParsedLoopMul,
  band = P.ParsedLoopBitAnd, ["and"] = P.ParsedLoopBitAnd,
  bor = P.ParsedLoopBitOr, ["or"] = P.ParsedLoopBitOr,
  bxor = P.ParsedLoopBitXor, xor = P.ParsedLoopBitXor,
  min = P.ParsedLoopMin, max = P.ParsedLoopMax,
}

local function parse_reducer(lex)
  local tok = lex:expect_name("loop reducer")
  local reducer = reducer_by_name[tok.value]
  if reducer == nil then
    lex:error_at(tok, "loop reducer must be add, mul, band, bor, bxor, min, or max")
  end
  return reducer
end

function P.ParsedStmt:parsed_loop_body_contribution()
  return P.ParsedLoopBodyStmt(self)
end
function P.StmtFoldParsed:parsed_loop_body_contribution()
  return P.ParsedLoopBodySink(P.ParsedLoopFoldSink(
    self.name, self.ty, self.init, self.reducer, self.step))
end
function P.StmtScanParsed:parsed_loop_body_contribution()
  return P.ParsedLoopBodySink(P.ParsedLoopScanSink(
    self.name, self.ty, self.init, self.reducer, self.axis, self.step, self.into))
end

function P.ParsedLoopBodyStmt:parsed_loop_collect(body, sink)
  body[#body + 1] = self.stmt
  return sink
end
function P.ParsedLoopBodySink:parsed_loop_collect(_body, sink)
  return sink:parsed_loop_accept_sink(self.sink)
end
function P.ParsedLoopSink:parsed_loop_accept_sink(_sink)
  error("parsed loop accepts only one fold or scan sink", 2)
end
function P.ParsedLoopNoSink:parsed_loop_accept_sink(sink)
  return sink
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
    local event = Ast.host_eval(raw, refs,
      Ast.origin(lex, open, close, "parsed:host_eval"), "stmts")
    return P.ParsedStmtGroup(Roles.adapt(ctx, "stmts", event))

  elseif t.value == "requires" then
    lex:next()
    -- Contracts are recognized into typed ParsedContract leaves here; the
    -- decl parser and region assembly consume the typed values directly.
    return P.StmtRequiresParsed(parse_contracts(lex, ctx))

  elseif t.value == "return" then
    local start = lex:next()
    local values = {}
    local nxt = lex:peek().value
    if nxt ~= "end" and nxt ~= "else" and nxt ~= "elseif" and nxt ~= ";" and nxt ~= "," and lex:peek().kind ~= "eof" then
      values = parse_expr_list_until_no_comma(lex, ctx)
    end
    if #values == 0 then
      return stmt_known(Tree.StmtReturnVoid(Tree.StmtSurface))
    elseif #values == 1 then
      return stmt_known(Tree.StmtReturnValue(Tree.StmtSurface, values[1]))
    else
      lex:error_at(start, "return accepts at most one value")
    end

  elseif t.value == "if" then
    local start = lex:next()
    local cond = Expr.parse(lex, ctx)
    lex:expect("then")
    local then_body = unwrap_stmts(Stmt.parse_block(lex, ctx, { "elseif", "else", "end" }))
  local else_body = {}
  while lex:next_if("elseif") do
    local ec = Expr.parse(lex, ctx)
    lex:expect("then")
    local eb = unwrap_stmts(Stmt.parse_block(lex, ctx, { "elseif", "else", "end" }))
    else_body = { Tree.StmtIf(Tree.StmtSurface, ec, eb, else_body) }
  end
  if lex:next_if("else") then
    else_body = unwrap_stmts(Stmt.parse_block(lex, ctx, { "end" }))
    end
    lex:expect("end")
    return stmt_known(Tree.StmtIf(Tree.StmtSurface, cond, then_body, else_body))

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
        local body = unwrap_stmts(Stmt.parse_block(lex, ctx, { "case", "default", "end" }))
        arms[#arms + 1] = Tree.SwitchStmtArm(Stmt.switch_key(key), body)
      elseif lex:peek().value == "default" then
        lex:next()
        lex:expect("then")
        default_body = unwrap_stmts(Stmt.parse_block(lex, ctx, { "end" }))
      else
        lex:error_at(lex:peek(), "expected `case`, `default`, or `end` in switch")
      end
      lex:skip_separators()
    end
    lex:expect("end")
    return stmt_known(Tree.StmtSwitch(Tree.StmtSurface, value, arms, variant_arms, default_body or {}))

  elseif t.value == "for" then
    lex:error_at(t, "source loops use `loop`, not `for`")

  elseif t.value == "loop" then
    local start = lex:next()
    local indexes = { lex:expect_name("loop index").value }
    while lex:next_if(",") do
      indexes[#indexes + 1] = lex:expect_name("loop index").value
    end
    lex:expect("in")
    local domain = parse_loop_domain(lex, ctx)
    lex:expect("do")
    local parsed_body = Stmt.parse_block(lex, ctx, { "end" })
    lex:expect("end")
    local body, sink = {}, P.ParsedLoopNoSink
    for i = 1, #parsed_body do
      sink = parsed_body[i]:parsed_loop_body_contribution():parsed_loop_collect(body, sink)
    end
    local loop_id = "parsed.loop." .. tostring(start.line or 0)
      .. "." .. tostring(start.col or 0)
    return P.StmtLoopParsed(loop_id, indexes, domain, body, sink)

  elseif t.value == "fold" then
    lex:next()
    local name = lex:expect_name("fold accumulator").value
    local ty = Type.parse(lex, ctx)
    lex:expect("=")
    local init = Expr.parse(lex, ctx)
    lex:expect("by")
    local reducer = parse_reducer(lex)
    lex:expect("step")
    return P.StmtFoldParsed(name, ty, init, reducer, Expr.parse(lex, ctx))

  elseif t.value == "scan" then
    lex:next()
    local name = lex:expect_name("scan accumulator").value
    local ty = Type.parse(lex, ctx)
    lex:expect("=")
    local init = Expr.parse(lex, ctx)
    lex:expect("by")
    local reducer = parse_reducer(lex)
    local axis = P.ParsedLoopScanAxisDefault
    if lex:next_if("axis") then
      lex:error_at(lex.last, "scan axis uses `over`, not `axis`")
    end
    if lex:next_if("over") then
      if lex:peek().kind == "name" then
        axis = P.ParsedLoopScanAxisName(lex:next().value)
      else
        axis = P.ParsedLoopScanAxisExpr(Expr.parse(lex, ctx))
      end
    end
    lex:expect("step")
    local step = Expr.parse(lex, ctx)
    lex:expect("into")
    return P.StmtScanParsed(name, ty, init, reducer, axis, step, Expr.parse(lex, ctx))
  elseif t.value == "let" or t.value == "var" then
    local start = lex:next()
    local mutable = start.value == "var"
    local name_tok = lex:expect_name("local name")
    local ty = Type.parse(lex, ctx)
    local init = nil
    if lex:next_if("=") then init = Expr.parse(lex, ctx) end
    -- Return intermediate: type is HostEval, resolved during lowering
    local default_init = Tree.ExprLit(Tree.ExprSurface, Core.LitInt("0"))
    if mutable then
      return P.StmtVarParsed(name_tok.value, ty, init or default_init)
    else
      return P.StmtLetParsed(name_tok.value, ty, init or default_init)
    end

  elseif t.value == "jump" then
    local start = lex:next()
    local target = lex:expect_name("jump target").value
    local payload = {}
    if lex:peek().value == "(" then payload = parse_named_payload(lex, ctx) end
    return stmt_known(Tree.StmtJump(Tree.StmtSurface, block_label(target), jump_args_from_payload(payload)))

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
    -- Deterministic source-site invoke IDs: the keyword token's source
    -- offset is unique per parse site and stable across parses of the
    -- same document, so expanded block label prefixes never collide.
    local invoke_id = "lln." .. tostring(start.value) .. "." .. tostring(start.start)
    if start.value == "call" then
      return stmt_known(Tree.StmtRegionCall(
        Tree.StmtSurface,
        invoke_id,
        Tree.RegionInvokeTarget(Stmt._region_path(callee_path)),
        data_args,
        Stmt._region_wiring(cont_wiring)
      ))
    else
      return stmt_known(Tree.StmtRegionEmit(
        Tree.StmtSurface,
        invoke_id,
        Tree.RegionInvokeTarget(Stmt._region_path(callee_path)),
        data_args,
        Stmt._region_wiring(cont_wiring)
      ))
    end

  elseif t.value == "yield" then
    local start = lex:next()
    local values = {}
    local nxt = lex:peek().value
    if nxt ~= "end" and nxt ~= "else" and nxt ~= "elseif" and nxt ~= ";" and nxt ~= "," and lex:peek().kind ~= "eof" then
      values = parse_expr_list_until_no_comma(lex, ctx)
    end
    if #values == 0 then
      return stmt_known(Tree.StmtYieldVoid(Tree.StmtSurface))
    else
      return stmt_known(Tree.StmtYieldValue(Tree.StmtSurface, values[1]))
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
        return stmt_known(Tree.StmtSet(Tree.StmtSurface, Expr.to_place(left), value))
      else
        lex:error_at(optok, "compound assignment " .. tostring(op) .. " is not yet supported")
      end
    end
    return stmt_known(Tree.StmtExpr(Tree.StmtSurface, left))
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
