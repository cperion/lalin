-- lalin.syntax.to_tree
-- Converts parsed-channel AST nodes to LalinTree ASDL.
-- This is the seam that bridges parsed syntax capture into the existing
-- typecheck/lower/codegen pipeline.
--
-- Usage: local to_tree = require("lalin.syntax.to_tree")(T)
-- where T is a pvm context with LalinTree/LalinCore/LalinBind/LalinType.

local pvm = require("lalin.pvm")

local function bind_context(T)
  -- Project the context if not already done.  Idempotent check:
  if not T.LalinCore then
    require("lalin.schema_projection")(T)
  end
  local C, Ty, B, Tr = T.LalinCore, T.LalinType, T.LalinBind, T.LalinTree

  local ToTree = {}

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

  --- Convert a parsed AST expression node to a LalinTree.Expr.
  function ToTree.expr(parsed)
    if not parsed then return nil end
    if type(parsed) ~= "table" then
      return ToTree.literal(parsed)
    end
    local cls = pvm.classof(parsed)
    if cls then return parsed end -- already ASDL

    local tag = parsed.tag
    if tag == "Literal" then
      if parsed.kind == "number" then
        local raw = tostring(parsed.value or parsed.source or "0")
        return Tr.ExprLit(Tr.ExprSurface, C.LitInt(raw))
      elseif parsed.kind == "boolean" then
        return Tr.ExprLit(Tr.ExprSurface, C.LitBool(parsed.value))
      elseif parsed.kind == "string" then
        return Tr.ExprLit(Tr.ExprSurface, C.LitString(parsed.source or ""))
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

    elseif tag == "Paren" then
      return ToTree.expr(parsed.value)

    elseif tag == "HostEscape" then
      if parsed.resolved then
        return ToTree.literal(parsed.value)
      end
      return Tr.ExprLit(Tr.ExprSurface, C.LitNil)

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

  -- Convert a parsed type node to LalinType.Type
  local scalars = {
    void = C.ScalarVoid, bool = C.ScalarBool,
    i8 = C.ScalarI8, i16 = C.ScalarI16,
    i32 = C.ScalarI32, i64 = C.ScalarI64,
    u8 = C.ScalarU8, u16 = C.ScalarU16,
    u32 = C.ScalarU32, u64 = C.ScalarU64,
    f32 = C.ScalarF32, f64 = C.ScalarF64,
    index = C.ScalarIndex, rawptr = C.ScalarRawPtr,
  }
  local type_ctors = {
    ptr = function(args)
      return Ty.TPtr(args[1] or Ty.TScalar(C.ScalarVoid))
    end,
    array = function(args)
      return Ty.TArray(Ty.ArrayLenStatic(0), args[1] or Ty.TScalar(C.ScalarVoid))
    end,
  }
  function ToTree.parsed_type(ptype)
    if not ptype then return Ty.TScalar(C.ScalarVoid) end
    if ptype.tag == "TypeName" then
      if scalars[ptype.name] then
        return Ty.TScalar(scalars[ptype.name])
      end
      return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(ptype.name) })))
    elseif ptype.tag == "TypeApply" then
      local ctor = type_ctors[ptype.name]
      if ctor then
        local args = {}
        for i, a in ipairs(ptype.args or {}) do
          args[i] = ToTree.parsed_type(a)
        end
        return ctor(args)
      end
      return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(ptype.name) })))
    end
    return Ty.TScalar(C.ScalarVoid)
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
    local cls = pvm.classof(parsed)
    if cls then return parsed end

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
    end
    error("parsed_to_tree: unsupported place tag " .. tostring(tag), 2)
  end

  --- Convert a parsed statement node to a LalinTree.Stmt.
  function ToTree.stmt(parsed)
    if type(parsed) ~= "table" then
      return Tr.StmtExpr(Tr.StmtSurface, ToTree.expr(parsed))
    end
    local cls = pvm.classof(parsed)
    if cls then return parsed end

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
        B.Binding(C.Id("parsed." .. parsed.name), parsed.name, let_ty, B.BindingClassLocalValue),
        parsed.init and ToTree.expr(parsed.init) or ToTree.literal(0))

    elseif tag == "StmtVar" then
      local var_ty = parsed.type and ToTree.parsed_type(parsed.type) or Ty.TScalar(C.ScalarVoid)
      return Tr.StmtVar(Tr.StmtSurface,
        B.Binding(C.Id("parsed." .. parsed.name), parsed.name, var_ty, B.BindingClassLocalValue),
        parsed.init and ToTree.expr(parsed.init) or ToTree.literal(0))

    elseif tag == "StmtExpr" then
      return Tr.StmtExpr(Tr.StmtSurface, ToTree.expr(parsed.expr))

    elseif tag == "StmtIf" then
      local then_body = {}
      for i, s in ipairs(parsed.then_body or {}) do
        then_body[i] = ToTree.stmt(s)
      end
      local else_body = {}
      if parsed.else_body then
        for i, s in ipairs(parsed.else_body) do
          else_body[i] = ToTree.stmt(s)
        end
      end
      for _, elseif_block in ipairs(parsed.elseif_blocks or {}) do
        local inner_body = {}
        for i, s in ipairs(elseif_block.body or {}) do
          inner_body[i] = ToTree.stmt(s)
        end
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
      return Tr.StmtExpr(Tr.StmtSurface, ToTree.expr(parsed.callee))

    elseif tag == "StmtFold" or tag == "StmtScan" then
      error("parsed_to_tree: " .. tostring(tag) .. " may only appear directly inside a parsed for/range loop", 2)
    end

    error("parsed_to_tree: unsupported statement tag " .. tostring(tag), 2)
  end

  --- Convert an array of parsed statement nodes.
  function ToTree.stmts(list)
    local out = {}
    for i, s in ipairs(list or {}) do
      out[i] = ToTree.stmt(s)
    end
    return out
  end

  return ToTree
end

return bind_context
