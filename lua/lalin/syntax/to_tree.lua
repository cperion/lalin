-- lalin.syntax.to_tree
-- Converts parsed-channel AST nodes to LalinTree ASDL.
-- This is the seam that bridges parsed syntax capture into the existing
-- typecheck/lower/codegen pipeline.
--
-- Usage: local to_tree = require("lalin.syntax.to_tree")(T)
-- where T is a projected ASDL context with LalinTree/LalinCore/LalinBind/LalinType.

local llbl = require("llbl")
local asdl = require("lalin.asdl")

local function bind_context(T)
  assert(T and T.LalinCore and T.LalinTree and T.LalinType and T.LalinBind,
    "lalin.syntax.to_tree(T) expects a projected Lalin schema context")
  local C, Ty, B, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree

  local ToTree = {}
  local TypeValue = require("lalin.syntax.type_value")(T)
  local adapter = require("lalin.syntax.role_adapter")(T)
  local stmt_list_tag = {}

  local function stmt_list(items)
    return { [stmt_list_tag] = true, items = items or {} }
  end

  local function is_stmt_list(value)
    return type(value) == "table" and value[stmt_list_tag] == true
  end

  adapter.stmt_list = function(_, items) return stmt_list(items) end
  adapter.is_stmt_list = function(_, value) return is_stmt_list(value) end
  adapter:set_lowering(ToTree)
  ToTree.role_adapter = adapter

  local region_invoke_counter = 0

  local binop_map = {
    add = C.BinAdd, sub = C.BinSub, mul = C.BinMul, div = C.BinDiv,
    mod = C.BinRem,
    bor = C.BinBitOr, bxor = C.BinBitXor, band = C.BinBitAnd,
    shl = C.BinShl, shr = C.BinLShr,
  }

  local cmpop_map = {
    eq = C.CmpEq, ne = C.CmpNe,
    lt = C.CmpLt, le = C.CmpLe,
    gt = C.CmpGt, ge = C.CmpGe,
  }

  local unop_map = {
    neg = C.UnaryNeg,
    ["not"] = C.UnaryNot,
    len = C.UnaryLen,
  }

  local function numeric_literal(raw)
    raw = tostring(raw or "0")
    if raw:find("[%.eE]") then return C.LitFloat(raw) end
    return C.LitInt(raw)
  end

  local function path_from_parts(parts)
    local out = {}
    for i, part in ipairs(parts or {}) do out[i] = C.Name(part) end
    return C.Path(out)
  end

  local function region_target(parsed)
    if parsed.callee_path ~= nil then
      return Tr.RegionInvokeTarget(path_from_parts(parsed.callee_path))
    end
    error("parsed_to_tree: region invocation requires a callee path", 2)
  end

  local function region_wiring(items)
    local out = {}
    for i, wire in ipairs(items or {}) do
      out[i] = Tr.RegionContWire(wire.name, Tr.RegionWireBlock(Tr.BlockLabel(wire.target)))
    end
    return out
  end

  local function next_region_invoke_id(kind)
    region_invoke_counter = region_invoke_counter + 1
    return "lln." .. tostring(kind) .. "." .. tostring(region_invoke_counter)
  end

  --- Convert a parsed AST expression node to a LalinTree.Expr.
  function ToTree.expr(parsed)
    if not parsed then return nil end
    if type(parsed) ~= "table" then
      return ToTree.literal(parsed)
    end
    local cls = asdl.classof(parsed)
    if cls then return parsed end -- already ASDL
    if llbl.is(parsed, "HostEval") then return adapter:expr(parsed) end

    local tag = parsed.tag
    if tag == "Literal" then
      if parsed.kind == "number" then
        return Tr.ExprLit(Tr.ExprSurface, numeric_literal(parsed.source or parsed.value or "0"))
      elseif parsed.kind == "boolean" then
        return Tr.ExprLit(Tr.ExprSurface, C.LitBool(parsed.value))
      elseif parsed.kind == "string" then
        return Tr.ExprLit(Tr.ExprSurface, C.LitString(parsed.value or parsed.source or ""))
      elseif parsed.kind == "nil" then
        return Tr.ExprLit(Tr.ExprSurface, C.LitNil)
      end

    elseif tag == "Name" then
      return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(parsed.name))

    elseif tag == "BinOp" then
      -- and/or are logic operators, not binary arithmetic
      if parsed.op == "and" then
        return Tr.ExprLogic(Tr.ExprSurface, C.LogicAnd, ToTree.expr(parsed.left), ToTree.expr(parsed.right))
      elseif parsed.op == "or" then
        return Tr.ExprLogic(Tr.ExprSurface, C.LogicOr, ToTree.expr(parsed.left), ToTree.expr(parsed.right))
      end
      local op = binop_map[parsed.op]
      if op then
        return Tr.ExprBinary(Tr.ExprSurface, op, ToTree.expr(parsed.left), ToTree.expr(parsed.right))
      end

    elseif tag == "Cmp" then
      local op = cmpop_map[parsed.op]
      if op then
        return Tr.ExprCompare(Tr.ExprSurface, op, ToTree.expr(parsed.left), ToTree.expr(parsed.right))
      end

    elseif tag == "UnOp" then
      local op = unop_map[parsed.op]
      if op then
        return Tr.ExprUnary(Tr.ExprSurface, op, ToTree.expr(parsed.value))
      end

    elseif tag == "Call" then
      local args = {}
      for i, a in ipairs(parsed.args or {}) do
        args[i] = ToTree.expr(a)
      end
      return Tr.ExprCall(Tr.ExprSurface, ToTree.expr(parsed.callee), args)

    elseif tag == "Index" then
      return Tr.ExprIndex(Tr.ExprSurface,
        Tr.IndexBaseExpr(ToTree.expr(parsed.base)),
        ToTree.expr(parsed.index))

    elseif tag == "Field" then
      return Tr.ExprDot(Tr.ExprSurface, ToTree.expr(parsed.base), parsed.name)

    elseif tag == "Record" then
      local fields = parsed.fields or {}
      local has_named, has_positional = false, false
      for _, f in ipairs(fields) do
        if f.key ~= nil then has_named = true else has_positional = true end
      end
      if has_named and has_positional then
        error("parsed_to_tree: record literals cannot mix named and positional fields", 2)
      end
      if has_named then
        local inits = {}
        for i, f in ipairs(fields) do
          inits[i] = Tr.FieldInit(f.key, ToTree.expr(f.value), 0)
        end
        return Tr.ExprAgg(Tr.ExprSurface, Ty.TScalar(C.ScalarVoid), inits)
      end
      local elems = {}
      for i, f in ipairs(fields) do elems[i] = ToTree.expr(f.value) end
      return Tr.ExprArray(Tr.ExprSurface, Ty.TScalar(C.ScalarVoid), elems)

    elseif tag == "Paren" then
      return ToTree.expr(parsed.value)

    elseif tag == "HostEscape" then
      return adapter:expr(parsed)

    elseif tag == "Cast" then
      local ty = ToTree.parsed_type(parsed.ty)
      local value = ToTree.expr(parsed.value)
      local cast_op = parsed.cast == "machine" and C.MachineCast or C.SurfaceCast
      return Tr.ExprCast(Tr.ExprSurface, cast_op, ty, value)

    elseif tag == "SizeOf" then
      local ty = ToTree.parsed_type(parsed.ty)
      return Tr.ExprSizeOf(Tr.ExprSurface, ty)

    elseif tag == "Hole" then
      -- LLBL hole: placeholder for curried argument.
      -- At the expression level this becomes a null ref — the typechecker
      -- or normalizer decides how to fill/curry it.
      return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName("__hole__"))

    elseif tag == "Spread" then
      -- LLBL spread: _(fragment).  The fragment is the expression result
      -- that gets spliced.  Return the fragment directly.
      return ToTree.expr(parsed.fragment)
    end

    error("parsed_to_tree: unsupported expression tag " .. tostring(tag) .. " in " .. tostring(parsed.name or ""), 2)
  end

  -- Convert a parsed type node to LalinType.Type. Public parsed type positions
  -- are always host escapes: `[i32]`, `[ptr [i32]]`, `[some_lua_type]`.
  function ToTree.parsed_type(ptype)
    if not ptype then return Ty.TScalar(C.ScalarVoid) end
    local cls = asdl.classof(ptype)
    if cls then return ptype end
    if llbl.is(ptype, "HostEval") or ptype.tag == "HostEscape" then
      return adapter:type(ptype)
    end
    error("parsed_to_tree: unsupported parsed type tag " .. tostring(ptype.tag) .. "; type positions use `[ ... ]`", 2)
  end

  --- Convert a plain Lua value to a LalinTree expression literal.
  function ToTree.literal(v)
    if v == nil then
      return Tr.ExprLit(Tr.ExprSurface, C.LitNil)
    elseif type(v) == "number" then
      if v == v and v % 1 == 0 then
        return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(v)))
      end
      return Tr.ExprLit(Tr.ExprSurface, C.LitFloat(tostring(v)))
    elseif type(v) == "boolean" then
      return Tr.ExprLit(Tr.ExprSurface, C.LitBool(v))
    elseif type(v) == "string" then
      return Tr.ExprLit(Tr.ExprSurface, C.LitString(v))
    end
    error("cannot convert to tree literal: " .. tostring(v), 2)
  end

  --- Convert a parsed expression to a LalinTree Place.
  function ToTree.place(parsed)
    if type(parsed) ~= "table" then
      error("parsed_to_tree: expected table for place, got " .. type(parsed), 2)
    end
    local cls = asdl.classof(parsed)
    if cls then return parsed end
    if llbl.is(parsed, "HostEval") then return adapter:place(parsed) end

    local tag = parsed.tag
    if tag == "Name" then
      return Tr.PlaceRef(Tr.PlaceSurface, B.ValueRefName(parsed.name))
    elseif tag == "Index" then
      return Tr.PlaceIndex(Tr.PlaceSurface,
        Tr.IndexBaseExpr(ToTree.expr(parsed.base)),
        ToTree.expr(parsed.index))
    elseif tag == "Field" then
      return Tr.PlaceDot(Tr.PlaceSurface, ToTree.place(parsed.base), parsed.name)
    elseif tag == "Paren" then
      return ToTree.place(parsed.value)
    elseif tag == "HostEscape" then
      return adapter:place(parsed)
    end
    error("parsed_to_tree: unsupported place tag " .. tostring(tag), 2)
  end

  function ToTree.stmt_splice(value)
    return adapter:stmt(value)
  end

  --- Convert a parsed statement node to a LalinTree.Stmt.
  function ToTree.stmt(parsed)
    if type(parsed) ~= "table" then
      return Tr.StmtExpr(Tr.StmtSurface, ToTree.expr(parsed))
    end
    local cls = asdl.classof(parsed)
    if cls then return parsed end
    if llbl.is(parsed, "HostEval") then return adapter:stmt(parsed) end

    local tag = parsed.tag
    if tag == "StmtAssign" then
      if parsed.op == "=" then
        return Tr.StmtSet(Tr.StmtSurface, ToTree.place(parsed.place), ToTree.expr(parsed.value))
      end

    elseif tag == "StmtReturn" then
      if #(parsed.values or {}) == 1 then
        return Tr.StmtReturnValue(Tr.StmtSurface, ToTree.expr(parsed.values[1]))
      elseif #(parsed.values or {}) == 0 then
        return Tr.StmtReturnVoid(Tr.StmtSurface)
      end

    elseif tag == "StmtLet" then
      local let_ty = parsed.type and ToTree.parsed_type(parsed.type) or Ty.TScalar(C.ScalarVoid)
      return Tr.StmtLet(Tr.StmtSurface,
        B.Binding(C.Id("parsed." .. parsed.name), parsed.name, let_ty, B.BindingRoleLocalValue),
        parsed.init and ToTree.expr(parsed.init) or ToTree.literal(0))

    elseif tag == "StmtVar" then
      local var_ty = parsed.type and ToTree.parsed_type(parsed.type) or Ty.TScalar(C.ScalarVoid)
      return Tr.StmtVar(Tr.StmtSurface,
        B.Binding(C.Id("parsed." .. parsed.name), parsed.name, var_ty, B.BindingRoleLocalValue),
        parsed.init and ToTree.expr(parsed.init) or ToTree.literal(0))

    elseif tag == "StmtExpr" then
      if parsed.expr and (llbl.is(parsed.expr, "HostEval") or parsed.expr.tag == "HostEscape") then
        return ToTree.stmt_splice(parsed.expr)
      end
      return Tr.StmtExpr(Tr.StmtSurface, ToTree.expr(parsed.expr))

    elseif tag == "StmtIf" then
      local then_body = ToTree.stmts(parsed.then_body or {})
      local else_body = parsed.else_body and ToTree.stmts(parsed.else_body) or {}
      for _, elseif_block in ipairs(parsed.elseif_blocks or {}) do
        local inner_body = ToTree.stmts(elseif_block.body or {})
        else_body = {
          Tr.StmtIf(Tr.StmtSurface, ToTree.expr(elseif_block.cond), inner_body, else_body),
        }
      end
      return Tr.StmtIf(Tr.StmtSurface, ToTree.expr(parsed.cond), then_body, else_body)

    elseif tag == "StmtRequires" then
      local all = {}
      for _, e in ipairs(parsed.exprs or {}) do
        all[#all + 1] = Tr.StmtAssert(Tr.StmtSurface, ToTree.expr(e))
      end
      if #all == 1 then return all[1] end
      local cond = all[1]
      for i = 2, #all do
        cond = Tr.StmtIf(Tr.StmtSurface, Tr.ExprLit(Tr.ExprSurface, C.LitBool(true)), { all[i] }, {})
      end
      return cond

    elseif tag == "StmtForRange" then
      local loop_lower = require("lalin.syntax.for_to_loop")(T)
      return loop_lower.lower(parsed)

    elseif tag == "StmtJump" then
      local payload = {}
      for _, f in ipairs(parsed.payload or {}) do
        payload[#payload + 1] = Tr.JumpArg(f.key or "", ToTree.expr(f.value))
      end
      return Tr.StmtJump(Tr.StmtSurface, Tr.BlockLabel(parsed.target), payload)

    elseif tag == "StmtEmit" then
      local args = {}
      for i, arg in ipairs(parsed.data_args or {}) do args[i] = ToTree.expr(arg) end
      return Tr.StmtRegionEmit(Tr.StmtSurface, next_region_invoke_id("emit"), region_target(parsed), args, region_wiring(parsed.cont_wiring))

    elseif tag == "StmtCall" then
      local args = {}
      for i, arg in ipairs(parsed.data_args or {}) do args[i] = ToTree.expr(arg) end
      return Tr.StmtRegionCall(Tr.StmtSurface, next_region_invoke_id("call"), region_target(parsed), args, region_wiring(parsed.cont_wiring))

    elseif tag == "StmtFragment" then
      return stmt_list(ToTree.stmts(parsed.body))

    elseif tag == "StmtFold" or tag == "StmtScan" then
      error("parsed_to_tree: " .. tostring(tag) .. " may only appear directly inside a parsed loop", 2)
    end

    error("parsed_to_tree: unsupported statement tag " .. tostring(tag), 2)
  end

  function ToTree.decls(value) return adapter:decls(value) end
  function ToTree.decl(value) return adapter:decl(value) end
  function ToTree.product_fields(value) return adapter:product_fields(value) end
  function ToTree.variants(value) return adapter:variants(value) end
  function ToTree.conts(value) return adapter:conts(value) end

  --- Convert an array of parsed statement nodes.
  function ToTree.stmts(list)
    local out = {}
    for _, s in ipairs(list or {}) do
      local converted = ToTree.stmt(s)
      if is_stmt_list(converted) then
        for _, item in ipairs(converted.items) do out[#out + 1] = item end
      else
        out[#out + 1] = converted
      end
    end
    return out
  end

  return ToTree
end

return bind_context
