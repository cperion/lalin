-- lalin.syntax_v2.expr
-- Expression parser producing LalinTree ASDL directly.

local Pratt = require("llbl.syntax.pratt")
local Roles = require("lalin.syntax_v2.roles")
local Ast = require("lalin.syntax_v2.ast")
local Type = require("lalin.syntax_v2.type")

-- Load schema_v2 types
require("lalin.schema_v2")
local Tree = package.loaded["lalin.schema_v2.tree"]
local Core = package.loaded["lalin.schema_v2.core"]
local Bind = package.loaded["lalin.schema_v2.bind"]
local Ty = package.loaded["lalin.schema_v2.type"]

local Expr = {}

local parser

local function decode_lua_string(raw, lex, tok)
  local loader = loadstring or load
  local fn, err = loader("return " .. tostring(raw), lex and lex.name or "=(lalin string literal)")
  if not fn then
    if lex then lex:error_at(tok, "invalid string literal: " .. tostring(err)) end
    error(err, 0)
  end
  local ok, value = pcall(fn)
  if not ok or type(value) ~= "string" then
    if lex then lex:error_at(tok, "invalid string literal") end
    error("invalid string literal", 0)
  end
  return value
end

local function name_ref(n)
  return Tree.ExprRef(Tree.ExprSurface, Bind.ValueRefName(n))
end

local binop_map = {
  add = Core.BinAdd, sub = Core.BinSub, mul = Core.BinMul, div = Core.BinDiv,
  mod = Core.BinRem, idiv = Core.BinDiv,
  bor = Core.BinBitOr, bxor = Core.BinBitXor, band = Core.BinBitAnd,
  shl = Core.BinShl, shr = Core.BinLShr, pow = Core.BinMul,
  ["or"] = "logic_or", ["and"] = "logic_and",
}

local function binop(name)
  return function(op, left, right, ctx)
    if name == "or" then
      return Tree.ExprLogic(Tree.ExprSurface, Core.LogicOr, left, right)
    elseif name == "and" then
      return Tree.ExprLogic(Tree.ExprSurface, Core.LogicAnd, left, right)
    end
    local o = binop_map[name or op.value]
    if not o then lex_error(ctx.lex, op, "unknown binary operator: " .. tostring(name or op.value)) end
    return Tree.ExprBinary(Tree.ExprSurface, o, left, right)
  end
end

local cmpop_map = {
  eq = Core.CmpEq, ne = Core.CmpNe,
  lt = Core.CmpLt, le = Core.CmpLe,
  gt = Core.CmpGt, ge = Core.CmpGe,
}

local function cmpop(name)
  return function(op, left, right, ctx)
    local o = cmpop_map[name or op.value]
    if not o then lex_error(ctx.lex, op, "unknown comparison operator: " .. tostring(name or op.value)) end
    return Tree.ExprCompare(Tree.ExprSurface, o, left, right)
  end
end

local unop_map = {
  neg = Core.UnaryNeg,
  ["not"] = Core.UnaryNot,
}

local function unop(name)
  return function(op, rhs, ctx)
    if name == "len" then
      return Tree.ExprLen(Tree.ExprSurface, rhs)
    elseif name == "addr" then
      -- place-based; addr-of expects a Place, not an Expr
      local place = Expr.to_place(rhs)
      return Tree.ExprAddrOf(Tree.ExprSurface, place)
    elseif name == "deref" then
      return Tree.ExprDeref(Tree.ExprSurface, rhs)
    end
    local o = unop_map[name or op.value]
    if not o then
      ctx.lex:error_at(op, "unknown unary operator: " .. tostring(name or op.value))
    end
    return Tree.ExprUnary(Tree.ExprSurface, o, rhs)
  end
end

function Expr.to_place(expr)
  -- If expr is already an ExprRef, ExprDot, or ExprIndex, construct a Place.
  -- Otherwise return the expr itself (for deref-style place access).
  local cls = require("lalin.asdl").classof(expr)
  if cls == Tree.ExprRef then
    return Tree.PlaceRef(Tree.PlaceSurface, expr.ref)
  elseif cls == Tree.ExprDot then
    return Tree.PlaceDot(Tree.PlaceSurface, Expr.to_place(expr.base), expr.name)
  elseif cls == Tree.ExprIndex then
    return Tree.PlaceIndex(Tree.PlaceSurface, expr.base, expr.index)
  elseif cls == Tree.ExprDeref then
    return Tree.PlaceDeref(Tree.PlaceSurface, expr.value)
  end
  return expr
end

local function parse_expr_list(lex, ctx, close)
  local items = {}
  if lex:next_if(close) then return items end
  repeat
    items[#items + 1] = Expr.parse(lex, ctx)
  until not lex:next_if(",")
  lex:expect(close)
  return items
end

local function parse_record_after_open(lex, ctx, start)
  local fields = {}
  if not lex:next_if("}") then
    repeat
      local key
      local mark = lex:mark()
      if lex:peek().kind == "name" and lex:peek(1).value == "=" then
        key = lex:next().value
        lex:expect("=")
      else
        lex:restore(mark)
      end
      fields[#fields + 1] = { key = key, value = Expr.parse(lex, ctx) }
    until not lex:next_if(",")
    lex:expect("}")
  end
  return fields, start
end

local function record_expr(fields, start, lex)
  local has_named, has_positional = false, false
  for _, f in ipairs(fields) do
    if f.key ~= nil then has_named = true else has_positional = true end
  end
  if has_named and has_positional then
    lex:error_at(start, "record literals cannot mix named and positional fields")
  end
  if has_named then
    local inits = {}
    for i, f in ipairs(fields) do
      inits[i] = Tree.FieldInit(f.key, f.value, 0)
    end
    return Tree.ExprAgg(Tree.ExprSurface, Ty.TScalar(Core.ScalarVoid), inits)
  end
  local elems = {}
  for i, f in ipairs(fields) do elems[i] = f.value end
  return Tree.ExprArray(Tree.ExprSurface, Ty.TScalar(Core.ScalarVoid), elems)
end

local function path_parts_from_expr(expr)
  local asdl = require("lalin.asdl")
  local cls = asdl.classof(expr)
  if cls == Tree.ExprRef then
    local r = expr.ref
    local rcls = asdl.classof(r)
    if rcls == Bind.ValueRefName then return { r.name } end
    return nil
  elseif cls == Tree.ExprDot then
    local base = path_parts_from_expr(expr.base)
    if base == nil then return nil end
    base[#base + 1] = expr.name
    return base
  end
  return nil
end

local function type_ref_from_constructor_expr(expr)
  local parts = path_parts_from_expr(expr)
  if parts == nil or #parts == 0 then
    error("syntax_v2: struct constructor callee must be a struct name or qualified struct path", 2)
  end
  local path_parts = {}
  for i, part in ipairs(parts) do path_parts[i] = Core.Name(part) end
  return Ty.TNamed(Ty.TypeRefPath(Core.Path(path_parts)))
end

local function struct_ctor(callee, fields, start, lex)
  local inits = {}
  for i, f in ipairs(fields) do
    if f.key == nil then
      lex:error_at(start, "struct constructors require named fields")
    end
    inits[i] = Tree.FieldInit(f.key, f.value, 0)
  end
  return Tree.ExprAgg(Tree.ExprSurface, type_ref_from_constructor_expr(callee), inits)
end


local function atom(lex, ctx)
  ctx.lex = lex
  local t = lex:peek()
  if t.kind == "number" then
    lex:next()
    local raw = t.raw
    local lit = raw:find("[%.eE]") and Core.LitFloat(raw) or Core.LitInt(raw)
    return Tree.ExprLit(Tree.ExprSurface, lit)
  elseif t.kind == "string" then
    lex:next()
    return Tree.ExprLit(Tree.ExprSurface, Core.LitString(decode_lua_string(t.raw, lex, t)))
  elseif t.kind == "name" then
    lex:next()
    if t.value == "true" or t.value == "false" then
      return Tree.ExprLit(Tree.ExprSurface, Core.LitBool(t.value == "true"))
    elseif t.value == "nil" then
      return Tree.ExprLit(Tree.ExprSurface, Core.LitNil)
    elseif t.value == "as" then
      -- as [type] (expr)  — type conversion
      local ty = Type.parse(lex, ctx)
      lex:expect("(")
      local value = Expr.parse(lex, ctx)
      lex:expect(")")
      return Tree.ExprCast(Tree.ExprSurface, Core.SurfaceCast, ty, value)
    elseif t.value == "sizeof" then
      -- sizeof [type]  — type size query
      return Tree.ExprSizeOf(Tree.ExprSurface, Type.parse(lex, ctx))
    elseif t.value == "alignof" then
      return Tree.ExprAlignOf(Tree.ExprSurface, Type.parse(lex, ctx))
    elseif t.value == "_" then
      -- LLBL-owned sentinel.
      if lex:peek().value == "(" then
        lex:next() -- consume (
        local fragment = Expr.parse(lex, ctx)
        lex:expect(")")
        return fragment -- Spread
      end
      return Tree.ExprRef(Tree.ExprSurface, Bind.ValueRefName("__hole__"))
    end
    -- Variant constructor: Type::Variant(args...)
    if lex:next_if("::") then
      local variant = lex:expect_name("variant constructor name")
      lex:expect("(")
      local args = parse_expr_list(lex, ctx, ")")
      return Tree.ExprCtor(Tree.ExprSurface, t.value, variant.value, args)
    end
    return name_ref(t.value)
  elseif t.value == "(" then
    local start = lex:next()
    local e = Expr.parse(lex, ctx)
    lex:expect(")")
    return e -- Paren: unwrap
  elseif t.value == "[" then
    local raw, open, close = Ast.consume_balanced_from_open(lex)
    local refs = Ast.extract_refs(raw)
    Ast.add_refs(ctx, refs)
    local event = Ast.host_eval(raw, refs,
      Ast.origin(lex, open, close, "parsed:host_eval"), "expr")
    return Roles.adapt(ctx, "expr", event)
  elseif t.value == "{" then
    local start = lex:expect("{")
    local fields = parse_record_after_open(lex, ctx, start)
    return record_expr(fields, start, lex)
  else
    lex:error_at(t, "expected expression atom, got `" .. tostring(t.value) .. "`")
  end
end

parser = Pratt.new {
  atom = atom,
  prefix = {
    ["-"] = { bp = 80, emit = unop("neg") },
    ["not"] = { bp = 80, emit = unop("not") },
    ["#"] = { bp = 80, emit = unop("len") },
    ["&"] = { bp = 80, emit = unop("addr") },
    ["*"] = { bp = 80, emit = unop("deref") },
  },
  postfix = {
    ["("] = { bp = 100, emit = function(op, left, lex, ctx)
      local args = parse_expr_list(lex, ctx, ")")
      return Tree.ExprCall(Tree.ExprSurface, left, args)
    end },
    ["["] = { bp = 100, emit = function(op, left, lex, ctx)
      local index = Expr.parse(lex, ctx)
      lex:expect("]")
      return Tree.ExprIndex(Tree.ExprSurface, Tree.IndexBaseExpr(left), index)
    end },
    ["."] = { bp = 100, emit = function(op, left, lex, ctx)
      local name = lex:expect_name("field name")
      return Tree.ExprDot(Tree.ExprSurface, left, name.value)
    end },
    [":"] = { bp = 98, emit = function(op, left, lex, ctx)
      local name = lex:expect_name("method name")
      lex:expect("(")
      local args = parse_expr_list(lex, ctx, ")")
      -- Method call: receiver becomes first argument
      local all_args = { left }
      for i, a in ipairs(args) do all_args[#all_args + 1] = a end
      return Tree.ExprCall(Tree.ExprSurface, name_ref(name.value), all_args)
    end },
    ["{"] = { bp = 100, emit = function(op, left, lex, ctx)
      if left.origin and op.line and left.origin.end_line and op.line > left.origin.end_line then
        lex:error_at(op, "struct constructor braces must stay on the same line as the struct name")
      end
      local fields = parse_record_after_open(lex, ctx, op)
      return struct_ctor(left, fields, op, lex)
    end },
  },
  infix = {
    ["or"]  = { bp = 10, emit = binop("or") },
    ["and"] = { bp = 20, emit = binop("and") },
    ["=="] = { bp = 30, emit = cmpop("eq") },
    ["~="] = { bp = 30, emit = cmpop("ne") },
    ["<"]  = { bp = 30, emit = cmpop("lt") },
    ["<="] = { bp = 30, emit = cmpop("le") },
    [">"]  = { bp = 30, emit = cmpop("gt") },
    [">="] = { bp = 30, emit = cmpop("ge") },
    ["|"] = { bp = 35, emit = binop("bor") },
    ["~"] = { bp = 36, emit = binop("bxor") },
    ["&"] = { bp = 37, emit = binop("band") },
    ["<<"] = { bp = 40, emit = binop("shl") },
    [">>"] = { bp = 40, emit = binop("shr") },
    ["+"] = { bp = 50, emit = binop("add") },
    ["-"] = { bp = 50, emit = binop("sub") },
    ["*"] = { bp = 60, emit = binop("mul") },
    ["/"] = { bp = 60, emit = binop("div") },
    ["//"] = { bp = 60, emit = binop("idiv") },
    ["%"] = { bp = 60, emit = binop("mod") },
    ["^"] = { bp = 90, right_assoc = true, emit = binop("pow") },
  }
}

function Expr.parse(lex, ctx, min_bp)
  ctx = ctx or {}
  ctx.lex = lex
  return parser:parse(lex, ctx, min_bp or 0)
end

function Expr.parse_list(lex, ctx, close)
  return parse_expr_list(lex, ctx, close)
end

return Expr
