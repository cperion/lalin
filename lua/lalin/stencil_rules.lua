local pvm = require("lalin.pvm")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.stencil_rules ~= nil then return T._lalin_api_cache.stencil_rules end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local Kernel = T.LalinKernel
    local Stencil = T.LalinStencil
    local Value = T.LalinValue

    local function basis_vocab_for_kind(kind)
        if kind == "reduce" or kind == "reduce_n" or kind == "count" or kind == "find" or kind == "map_reduce" or kind == "zip_reduce" then return Stencil.StencilReduce end
        if kind == "scan" then return Stencil.StencilScan end
        return Stencil.StencilApply
    end

    local function selection(kind, fields)
        fields = fields or {}
        fields.kind = kind
        fields.vocab = basis_vocab_for_kind(kind)
        return fields
    end

    local function with_class(kind, fields)
        fields = fields or {}
        fields.kind = kind
        return fields
    end

    local function const_int_value(value)
        if pvm.classof(value) == Value.ValueExprConst
            and pvm.classof(value.const) == Code.CodeConstLiteral
            and pvm.classof(value.const.literal) == Core.LitInt then
            return tonumber(value.const.literal.raw)
        end
        return nil
    end

    local function const_ty(value)
        if pvm.classof(value) == Value.ValueExprConst and value.const ~= nil then return value.const.ty end
        return nil
    end

    local function stencil_unary_op(op)
        if op == Core.UnaryNeg then return Stencil.StencilUnaryNeg end
        if op == Core.UnaryBitNot then return Stencil.StencilUnaryBitNot end
        if op == Core.UnaryNot then return Stencil.StencilUnaryBoolNot end
        return nil
    end

    local function stencil_binary_op(op)
        if op == Core.BinAdd then return Stencil.StencilBinaryAdd end
        if op == Core.BinSub then return Stencil.StencilBinarySub end
        if op == Core.BinMul then return Stencil.StencilBinaryMul end
        if op == Core.BinDiv then return Stencil.StencilBinaryDiv end
        if op == Core.BinRem then return Stencil.StencilBinaryMod end
        if op == Core.BinBitAnd then return Stencil.StencilBinaryAnd end
        if op == Core.BinBitOr then return Stencil.StencilBinaryOr end
        if op == Core.BinBitXor then return Stencil.StencilBinaryXor end
        if op == Core.BinShl then return Stencil.StencilBinaryShl end
        if op == Core.BinLShr then return Stencil.StencilBinaryLShr end
        if op == Core.BinAShr then return Stencil.StencilBinaryAShr end
        return nil
    end

    local function is_int_type(ty) return pvm.classof(ty) == Code.CodeTyInt end
    local function is_float_type(ty) return pvm.classof(ty) == Code.CodeTyFloat end
    local function is_index_type(ty) return ty == Code.CodeTyIndex end
    local function is_bool8_type(ty) return ty == Code.CodeTyBool8 end

    local function is_type_family(ty, family)
        family = tostring(family)
        local cls = pvm.classof(ty)
        if family == "pointer" then return cls == Code.CodeTyDataPtr end
        if family == "code_pointer" then return cls == Code.CodeTyCodePtr end
        if family == "named" then return cls == Code.CodeTyNamed end
        if family == "array" then return cls == Code.CodeTyArray end
        if family == "slice" then return cls == Code.CodeTySlice end
        if family == "view" then return cls == Code.CodeTyView end
        if family == "byte_span" then return ty == Code.CodeTyByteSpan or cls == Code.CodeTyByteSpan end
        if family == "handle" then return cls == Code.CodeTyHandle end
        if family == "lease" then return cls == Code.CodeTyLease end
        if family == "closure" then return cls == Code.CodeTyClosure end
        if family == "imported_c" then return cls == Code.CodeTyImportedC end
        if family == "imported_c_func_pointer" then return cls == Code.CodeTyImportedCFuncPtr end
        if family == "vector" then return cls == Code.CodeTyVector end
        return false
    end

    local function is_scalar_type(ty)
        return is_int_type(ty) or is_float_type(ty) or is_index_type(ty) or is_bool8_type(ty)
    end

    local function same_source_type(a, b)
        if a == b then return true end
        if a == nil or b == nil then return false end
        return tostring(a) == tostring(b)
    end

    local same_type
    same_type = function(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        if ac == Code.CodeTyDataPtr then
            if a.pointee == nil or b.pointee == nil then return a.pointee == b.pointee end
            return same_type(a.pointee, b.pointee)
        end
        if ac == Code.CodeTyCodePtr then return a.sig == b.sig end
        if ac == Code.CodeTyNamed then return a.module_name == b.module_name and a.type_name == b.type_name end
        if ac == Code.CodeTyArray then return a.count == b.count and same_type(a.elem, b.elem) end
        if ac == Code.CodeTySlice or ac == Code.CodeTyView then return same_type(a.elem, b.elem) end
        if ac == Code.CodeTyHandle then return same_type(a.repr, b.repr) and same_source_type(a.source_ty, b.source_ty) end
        if ac == Code.CodeTyLease then return same_type(a.base, b.base) and same_source_type(a.source_ty, b.source_ty) end
        if ac == Code.CodeTyClosure then return a.sig == b.sig end
        if ac == Code.CodeTyImportedC then return a.id == b.id or (a.id.module_name == b.id.module_name and a.id.spelling == b.id.spelling) end
        if ac == Code.CodeTyImportedCFuncPtr then return a.sig == b.sig end
        if ac == Code.CodeTyVector then return a.lanes == b.lanes and same_type(a.elem, b.elem) end
        return false
    end

    local function is_index_data_type(ty) return is_int_type(ty) or is_index_type(ty) end
    local function supports_bitwise_ty(ty) return is_int_type(ty) or is_bool8_type(ty) end
    local function supports_div_ty(ty) return is_int_type(ty) or is_float_type(ty) or is_index_type(ty) end
    local function supports_integer_arithmetic_ty(ty) return is_int_type(ty) or is_index_type(ty) end

    local function unary_supported(op, ty)
        if op == Stencil.StencilUnaryIdentity then return ty ~= Code.CodeTyVoid end
        if not is_scalar_type(ty) then return false end
        if op == Stencil.StencilUnaryBitNot then return supports_bitwise_ty(ty) end
        if op == Stencil.StencilUnaryNeg or op == Stencil.StencilUnaryBoolNot then return true end
        return false
    end

    local function binary_supported(op, ty)
        if not is_scalar_type(ty) then return false end
        if op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor then return supports_bitwise_ty(ty) end
        if op == Stencil.StencilBinaryDiv then return supports_div_ty(ty) end
        if op == Stencil.StencilBinaryMod then return supports_integer_arithmetic_ty(ty) end
        if op == Stencil.StencilBinaryShl or op == Stencil.StencilBinaryLShr or op == Stencil.StencilBinaryAShr then return supports_bitwise_ty(ty) end
        if op == Stencil.StencilBinaryAdd or op == Stencil.StencilBinarySub or op == Stencil.StencilBinaryMul
            or op == Stencil.StencilBinaryMin or op == Stencil.StencilBinaryMax then
            return true
        end
        return false
    end

    local function reduction_supported(kind, elem_ty, result_ty)
        if not same_type(elem_ty, result_ty) then return false end
        if is_int_type(result_ty) then
            return kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionAnd or kind == Value.ReductionOr or kind == Value.ReductionXor
                or kind == Value.ReductionMin or kind == Value.ReductionMax
        end
        if is_float_type(result_ty) then
            return kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionMin or kind == Value.ReductionMax
        end
        return false
    end

    local function type_bits(ty)
        if is_int_type(ty) or is_float_type(ty) then return tonumber(ty.bits) end
        if is_bool8_type(ty) then return 8 end
        return nil
    end

    local function is_signed_int_type(ty) return is_int_type(ty) and ty.signedness == Code.CodeSigned end
    local function is_unsigned_int_type(ty) return is_int_type(ty) and ty.signedness == Code.CodeUnsigned end

    local function cast_supported(op, src_ty, dst_ty)
        if not is_scalar_type(src_ty) or not is_scalar_type(dst_ty) then return false end
        if op == Core.MachineCastIdentity then return same_type(src_ty, dst_ty) end
        if op == Core.MachineCastBitcast then return type_bits(src_ty) ~= nil and type_bits(src_ty) == type_bits(dst_ty) end
        if op == Core.MachineCastIreduce then return is_int_type(src_ty) and is_int_type(dst_ty) and type_bits(dst_ty) <= type_bits(src_ty) end
        if op == Core.MachineCastSextend or op == Core.MachineCastUextend then return is_int_type(src_ty) and is_int_type(dst_ty) and type_bits(dst_ty) >= type_bits(src_ty) end
        if op == Core.MachineCastFpromote then return is_float_type(src_ty) and is_float_type(dst_ty) and type_bits(dst_ty) >= type_bits(src_ty) end
        if op == Core.MachineCastFdemote then return is_float_type(src_ty) and is_float_type(dst_ty) and type_bits(dst_ty) <= type_bits(src_ty) end
        if op == Core.MachineCastSToF then return is_signed_int_type(src_ty) and is_float_type(dst_ty) end
        if op == Core.MachineCastUToF then return is_unsigned_int_type(src_ty) and is_float_type(dst_ty) end
        if op == Core.MachineCastFToS then return is_float_type(src_ty) and is_signed_int_type(dst_ty) end
        if op == Core.MachineCastFToU then return is_float_type(src_ty) and is_unsigned_int_type(dst_ty) end
        return false
    end

    local function predicate_from_cmp_const(op, operand_ty, cexpr, const_on_left)
        if pvm.classof(cexpr) ~= Value.ValueExprConst then return nil end
        if const_on_left then
            if op == Core.CmpLt then op = Core.CmpGt
            elseif op == Core.CmpLe then op = Core.CmpGe
            elseif op == Core.CmpGt then op = Core.CmpLt
            elseif op == Core.CmpGe then op = Core.CmpLe end
        end
        if op == Core.CmpEq or op == Core.CmpNe or op == Core.CmpLt or op == Core.CmpLe or op == Core.CmpGt or op == Core.CmpGe then
            return Stencil.StencilPredCompareConst(op, operand_ty, cexpr)
        end
        return nil
    end

    local function access_ref(name)
        return Stencil.StencilAccessRef(name)
    end

    local function input_expr(name)
        return Stencil.StencilApplyInput(access_ref(name))
    end

    local function const_expr(value, ty)
        return Stencil.StencilApplyConst(value, ty)
    end

    local function apply_unary_expr(op, arg, result_ty)
        return Stencil.StencilApplyUnary(op, arg, result_ty, nil, nil)
    end

    local function apply_binary_expr(op, left, right, result_ty, int_semantics)
        return Stencil.StencilApplyBinary(op, left, right, result_ty, int_semantics, nil)
    end

    local function apply_cast_expr(op, arg, from, to)
        return Stencil.StencilApplyCast(op, arg, from, to)
    end

    local function apply_predicate_expr(pred, arg, result_ty)
        return Stencil.StencilApplyPredicate(pred, arg, result_ty)
    end

    local function apply_compare_expr(cmp, left, right, result_ty)
        return Stencil.StencilApplyCompare(cmp, left, right, result_ty)
    end

    local function apply_select_expr(cond, then_expr, else_expr, result_ty)
        return Stencil.StencilApplySelect(Stencil.StencilPredNonZero, cond, then_expr, else_expr, result_ty)
    end

    local function scalar_input_expr(value, state)
        local name = "x" .. tostring(#state.inputs + 1)
        state.inputs[#state.inputs + 1] = {
            name = name,
            scalar_value = value,
            layout = Stencil.StencilLayoutScalar(value),
            role = Stencil.StencilAccessRead,
            index_primary = true,
        }
        return input_expr(name)
    end

    local expr_fact
    expr_fact = function(expr, bindings, seen)
        if expr == nil then return nil, "missing stencil expression" end
        seen = seen or {}
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprKernelValue then
            if seen[expr.value.text] then return nil, "cyclic kernel binding" end
            local binding = bindings and bindings[expr.value.text] or nil
            if binding == nil then return nil, "missing kernel binding " .. expr.value.text end
            local next_seen = {}
            for k, v in pairs(seen) do next_seen[k] = v end
            next_seen[expr.value.text] = true
            local fact, err = expr_fact(binding.expr, bindings, next_seen)
            if fact == nil then return nil, err end
            return { kind = "kernel_value", id = expr.value, binding = fact }, nil
        elseif cls == Kernel.KernelExprLaneLoad then
            return { kind = "load", lane = expr.lane, index = expr.index }, nil
        elseif cls == Kernel.KernelExprAlgebra then
            local v = expr.expr
            local vcls = pvm.classof(v)
            if vcls == Value.ValueExprConst then
                return { kind = "fill", value = v }, nil
            elseif vcls == Value.ValueExprValue then
                local kid = Kernel.KernelValueId("kval:" .. v.value.text)
                local binding = bindings and bindings[kid.text] or nil
                if binding ~= nil then
                    if seen[kid.text] then return nil, "cyclic kernel binding" end
                    local next_seen = {}
                    for k, x in pairs(seen) do next_seen[k] = x end
                    next_seen[kid.text] = true
                    local fact, err = expr_fact(binding.expr, bindings, next_seen)
                    if fact == nil then return nil, err end
                    return { kind = "kernel_value", id = kid, binding = fact }, nil
                end
                return { kind = "fill", value = v }, nil
            elseif vcls == Value.ValueExprUnary then
                local fact, err = expr_fact(Kernel.KernelExprAlgebra(v.value), bindings, seen)
                if fact == nil then return nil, err end
                return { kind = "unary", op = stencil_unary_op(v.op), raw_op = v.op, value = fact, result_ty = v.ty }, nil
            elseif vcls == Value.ValueExprCast then
                local fact, err = expr_fact(Kernel.KernelExprAlgebra(v.value), bindings, seen)
                if fact == nil then return nil, err end
                return { kind = "cast", op = v.op, value = fact, src_ty = v.from, result_ty = v.to }, nil
            elseif vcls == Value.ValueExprAdd or vcls == Value.ValueExprSub or vcls == Value.ValueExprMul or vcls == Value.ValueExprDiv or vcls == Value.ValueExprRem then
                local lhs, lhs_err = expr_fact(Kernel.KernelExprAlgebra(v.a), bindings, seen)
                if lhs == nil then return nil, lhs_err end
                local rhs, rhs_err = expr_fact(Kernel.KernelExprAlgebra(v.b), bindings, seen)
                if rhs == nil then return nil, rhs_err end
                local bop = vcls == Value.ValueExprAdd and Core.BinAdd
                    or vcls == Value.ValueExprSub and Core.BinSub
                    or vcls == Value.ValueExprMul and Core.BinMul
                    or vcls == Value.ValueExprRem and Core.BinRem
                    or Core.BinDiv
                local algebra = vcls == Value.ValueExprAdd and "add"
                    or vcls == Value.ValueExprSub and "sub"
                    or vcls == Value.ValueExprMul and "mul"
                    or vcls == Value.ValueExprRem and "rem"
                    or "div"
                return { kind = "binary", algebra = algebra, op = stencil_binary_op(bop), raw_op = bop, lhs = lhs, rhs = rhs, result_ty = v.ty, int_semantics = v.sem }, nil
            elseif vcls == Value.ValueExprBinary then
                local lhs, lhs_err = expr_fact(Kernel.KernelExprAlgebra(v.a), bindings, seen)
                if lhs == nil then return nil, lhs_err end
                local rhs, rhs_err = expr_fact(Kernel.KernelExprAlgebra(v.b), bindings, seen)
                if rhs == nil then return nil, rhs_err end
                local op = stencil_binary_op(v.op)
                if op == nil then return nil, "unsupported binary value expression" end
                return { kind = "binary", algebra = tostring(v.op), op = op, raw_op = v.op, lhs = lhs, rhs = rhs, result_ty = v.ty, int_semantics = v.sem }, nil
            elseif vcls == Value.ValueExprCmp then
                local lhs, lhs_err = expr_fact(Kernel.KernelExprAlgebra(v.a), bindings, seen)
                if lhs == nil then return nil, lhs_err end
                local rhs, rhs_err = expr_fact(Kernel.KernelExprAlgebra(v.b), bindings, seen)
                if rhs == nil then return nil, rhs_err end
                return { kind = "cmp", op = v.op, lhs = lhs, rhs = rhs, result_ty = Code.CodeTyBool8 }, nil
            elseif vcls == Value.ValueExprSelect then
                local cond, cond_err = expr_fact(Kernel.KernelExprAlgebra(v.cond), bindings, seen)
                if cond == nil then return nil, cond_err end
                local t, t_err = expr_fact(Kernel.KernelExprAlgebra(v.t), bindings, seen)
                if t == nil then return nil, t_err end
                local f, f_err = expr_fact(Kernel.KernelExprAlgebra(v.f), bindings, seen)
                if f == nil then return nil, f_err end
                return { kind = "select", cond = cond, t = t, f = f }, nil
            end
        end
        return nil, "unsupported store stencil expression"
    end

    local function lane_key(lane, index)
        local id = lane and lane.id and lane.id.text or tostring(lane)
        return id .. "@" .. tostring(index)
    end

    local function input_by_name(class, name)
        for _, input in ipairs(class.inputs or {}) do
            if input.name == name then return input end
        end
        return nil
    end

    local function single_input(class)
        if class == nil or #(class.inputs or {}) ~= 1 then return nil end
        return class.inputs[1]
    end

    local function single_input_expr(class)
        if class == nil or pvm.classof(class.expr) ~= Stencil.StencilApplyInput then return nil end
        return input_by_name(class, class.expr.access.name)
    end

    local function apply_const_int(expr)
        if pvm.classof(expr) ~= Stencil.StencilApplyConst then return nil end
        return const_int_value(expr.value)
    end

    local function index_input_from_apply_expr(class, expr)
        local cls = pvm.classof(expr)
        if cls == Stencil.StencilApplyInput then return input_by_name(class, expr.access.name) end
        if cls == Stencil.StencilApplyCast then return index_input_from_apply_expr(class, expr.arg) end
        if cls == Stencil.StencilApplyBinary then
            local lc, rc = apply_const_int(expr.left), apply_const_int(expr.right)
            if (expr.op == Stencil.StencilBinaryMul and rc == 1)
                or (expr.op == Stencil.StencilBinaryAdd and rc == 0)
                or (expr.op == Stencil.StencilBinarySub and rc == 0) then
                return index_input_from_apply_expr(class, expr.left)
            end
            if (expr.op == Stencil.StencilBinaryMul and lc == 1)
                or (expr.op == Stencil.StencilBinaryAdd and lc == 0) then
                return index_input_from_apply_expr(class, expr.right)
            end
        end
        return nil
    end

    local function apply_input_for_load(expr, state)
        local key = lane_key(expr.lane, expr.index)
        local existing = state.by_key[key]
        if existing ~= nil then return input_expr(existing.name), existing.ty end
        local name = "x" .. tostring(#state.inputs + 1)
        local input = {
            name = name,
            lane = expr.lane,
            index = expr.index,
            ty = expr.lane.elem_ty,
        }
        state.by_key[key] = input
        state.inputs[#state.inputs + 1] = input
        return input_expr(name), input.ty
    end

    local fact_to_apply_expr
    fact_to_apply_expr = function(expr, state)
        if expr.kind == "kernel_value" and expr.binding ~= nil then return fact_to_apply_expr(expr.binding, state) end
        if expr.kind == "load" then return apply_input_for_load(expr, state) end
        if expr.kind == "fill" then
            local ty = const_ty(expr.value)
            if ty == nil then return scalar_input_expr(expr.value, state), nil end
            return const_expr(expr.value, ty), ty
        end
        if expr.kind == "unary" then
            if expr.op == nil then return nil, nil, "unsupported unary stencil operator" end
            local arg, _, err = fact_to_apply_expr(expr.value, state)
            if arg == nil then return nil, nil, err end
            return apply_unary_expr(expr.op, arg, expr.result_ty), expr.result_ty
        end
        if expr.kind == "cast" then
            local arg, _, err = fact_to_apply_expr(expr.value, state)
            if arg == nil then return nil, nil, err end
            return apply_cast_expr(expr.op, arg, expr.src_ty, expr.result_ty), expr.result_ty
        end
        if expr.kind == "binary" then
            if expr.op == nil then return nil, nil, "unsupported binary stencil operator" end
            local lhs, _, lhs_err = fact_to_apply_expr(expr.lhs, state)
            if lhs == nil then return nil, nil, lhs_err end
            local rhs, _, rhs_err = fact_to_apply_expr(expr.rhs, state)
            if rhs == nil then return nil, nil, rhs_err end
            return apply_binary_expr(expr.op, lhs, rhs, expr.result_ty, expr.int_semantics), expr.result_ty
        end
        if expr.kind == "cmp" then
            local lhs, lhs_ty, lhs_err = fact_to_apply_expr(expr.lhs, state)
            if lhs == nil then return nil, nil, lhs_err end
            local rhs, rhs_ty, rhs_err = fact_to_apply_expr(expr.rhs, state)
            if rhs == nil then return nil, nil, rhs_err end
            if expr.lhs.kind == "load" and expr.rhs.kind == "fill" then
                local pred = predicate_from_cmp_const(expr.op, lhs_ty, expr.rhs.value, false)
                if pred ~= nil then return apply_predicate_expr(pred, lhs, expr.result_ty), expr.result_ty end
            end
            if expr.lhs.kind == "fill" and expr.rhs.kind == "load" then
                local pred = predicate_from_cmp_const(expr.op, rhs_ty, expr.lhs.value, true)
                if pred ~= nil then return apply_predicate_expr(pred, rhs, expr.result_ty), expr.result_ty end
            end
            return apply_compare_expr(expr.op, lhs, rhs, expr.result_ty), expr.result_ty
        end
        if expr.kind == "select" then
            local cond, _, cond_err = fact_to_apply_expr(expr.cond, state)
            if cond == nil then return nil, nil, cond_err end
            local t, result_ty, t_err = fact_to_apply_expr(expr.t, state)
            if t == nil then return nil, nil, t_err end
            local f, _, f_err = fact_to_apply_expr(expr.f, state)
            if f == nil then return nil, nil, f_err end
            return apply_select_expr(cond, t, f, result_ty), result_ty
        end
        return nil, nil, "unsupported store stencil expression"
    end

    local function classify_expr(expr)
        local state = { inputs = {}, by_key = {} }
        local apply_expr, result_ty, err = fact_to_apply_expr(expr, state)
        if apply_expr == nil then return nil, err end
        return with_class("apply_n", {
            expr = apply_expr,
            inputs = state.inputs,
            result_ty = result_ty,
            const_int = expr.kind == "fill" and const_int_value(expr.value) or nil,
        })
    end

    local function classify_type(ty)
        if is_int_type(ty) then return { kind = "int", ty = ty } end
        if is_float_type(ty) then return { kind = "float", ty = ty } end
        if is_index_type(ty) then return { kind = "index", ty = ty } end
        if is_bool8_type(ty) then return { kind = "bool8", ty = ty } end
        for _, family in ipairs({
            "pointer", "code_pointer", "named", "array", "slice", "view",
            "byte_span", "handle", "lease", "closure", "imported_c",
            "imported_c_func_pointer", "vector",
        }) do
            if is_type_family(ty, family) then return { kind = family, ty = ty } end
        end
        return nil, "unsupported stencil type"
    end

    local function type_ok(ty) return classify_type(ty) ~= nil end

    local function select_index_lane(class)
        if class.kind == "load" or class.kind == "cast" then return { lane = class.lane, index = class.index } end
        if class.kind == "apply_n" then
            local input = index_input_from_apply_expr(class, class.expr)
            if input ~= nil then return { lane = input.lane, index = input.index } end
        end
        return nil
    end

    local function append_info_inputs(info, inputs)
        for _, input in ipairs(inputs or {}) do info[input.name] = input.base end
        return info
    end

    local function all_apply_inputs_primary(class)
        for _, input in ipairs(class.inputs or {}) do
            if input.index_primary ~= true then return false end
        end
        return true
    end

    local function copy_inputs(inputs)
        local out = {}
        for i, input in ipairs(inputs or {}) do
            local item = {}
            for k, v in pairs(input) do item[k] = v end
            out[i] = item
        end
        return out
    end

    local function append_input_once(inputs, input)
        for _, existing in ipairs(inputs or {}) do
            if existing.name == input.name then return inputs end
        end
        inputs[#inputs + 1] = input
        return inputs
    end

    local function specialize_scalar_inputs(inputs, ty)
        for _, input in ipairs(inputs or {}) do
            if input.scalar_value ~= nil and input.ty == nil then input.ty = ty end
        end
        return inputs
    end

    local function apply_n_info(ctx, class, extra)
        local inputs = extra and extra.inputs or class.inputs
        local info = {
            step_num = ctx.step_num,
            producer = ctx.producer,
            result_ty = class.result_ty or ctx.dst_elem_ty,
            dst = ctx.dst,
            dst_layout = extra and extra.dst_layout or ctx.dst_layout,
            inputs = specialize_scalar_inputs(inputs, class.result_ty or ctx.dst_elem_ty),
            expr = class.expr,
            start = ctx.start,
            stop = ctx.stop,
            tag = "expr" .. tostring(#(inputs or {})),
        }
        for k, v in pairs(extra or {}) do
            if k ~= "inputs" and k ~= "dst_layout" then info[k] = v end
        end
        return append_info_inputs(info, info.inputs)
    end

    local function predicate_expr_operand(class)
        if class == nil then return nil, nil end
        local cls = pvm.classof(class.expr)
        if cls ~= Stencil.StencilApplyPredicate then return nil, nil end
        if pvm.classof(class.expr.arg) ~= Stencil.StencilApplyInput then return nil, nil end
        local input = input_by_name(class, class.expr.arg.access.name)
        return input, class.expr.pred
    end

    local function indexed_layout(parent, idx, step_num)
        return Stencil.StencilLayoutIndexed(parent, access_ref(idx.name), idx.ty or idx.elem_ty, step_num or 1)
    end

    local function select_store(ctx)
        local class = ctx.class or {}
        local copy_input = class.kind == "apply_n" and single_input_expr(class) or nil
        if copy_input ~= nil and ctx.copy_semantics ~= nil and ctx.store_index_primary == true and copy_input.index_primary == true
            and same_type(copy_input.ty, ctx.dst_elem_ty) and type_ok(copy_input.ty) and type_ok(ctx.dst_elem_ty) then
            return selection("copy", {
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = copy_input.ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = copy_input.base, semantics = ctx.copy_semantics,
                    dst_layout = ctx.dst_layout, src_layout = copy_input.layout,
                },
                args = { ctx.dst_expr, copy_input.base_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "apply_n" and ctx.store_index_primary == true and (class.result_ty == nil or same_type(class.result_ty, ctx.dst_elem_ty))
            and all_apply_inputs_primary(class) and type_ok(class.result_ty or ctx.dst_elem_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("apply_n", {
                info = apply_n_info(ctx, class),
                args = {},
            })
        end
        if class.kind == "apply_n" and ctx.store_index_primary == true and (class.result_ty == nil or same_type(class.result_ty, ctx.dst_elem_ty))
            and type_ok(class.result_ty or ctx.dst_elem_ty) and type_ok(ctx.dst_elem_ty) then
            local inputs, ok = copy_inputs(class.inputs), true
            for _, input in ipairs(inputs) do
                if input.index_primary ~= true then
                    local idx = input.index_lane
                    if idx == nil or not is_index_data_type(idx.ty) then ok = false; break end
                    input.layout = indexed_layout(input.layout, idx, ctx.step_num)
                    append_input_once(inputs, idx)
                end
            end
            if ok then
                return selection("apply_n", {
                    info = apply_n_info(ctx, class, {
                        inputs = inputs,
                    }),
                    args = {},
                })
            end
        end
        if class.kind == "apply_n" and ctx.store_index_lane ~= nil
            and (class.result_ty == nil or same_type(class.result_ty, ctx.dst_elem_ty)) and all_apply_inputs_primary(class)
            and is_index_data_type(ctx.store_index_lane.elem_ty) and type_ok(class.result_ty or ctx.dst_elem_ty) and type_ok(ctx.dst_elem_ty) then
            local idx = {
                name = "dst_idx",
                base = ctx.store_index_lane.base,
                base_expr = ctx.store_index_lane.base_expr,
                ty = ctx.store_index_lane.elem_ty,
                elem_ty = ctx.store_index_lane.elem_ty,
                layout = ctx.store_index_lane.layout,
                role = Stencil.StencilAccessIndex,
                index_primary = true,
            }
            local inputs = copy_inputs(class.inputs)
            append_input_once(inputs, idx)
            return selection("apply_n", {
                info = apply_n_info(ctx, class, {
                    inputs = inputs,
                    dst_layout = indexed_layout(ctx.dst_layout, idx, ctx.step_num),
                    apply_mode = Stencil.StencilStoreScatter(ctx.scatter_conflicts or Stencil.StencilScatterUniqueIndices),
                }),
                args = {},
            })
        end
        if class.kind == "fill" and ctx.store_index_primary == true and type_ok(ctx.dst_elem_ty) then
            return selection("fill", {
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = ctx.dst_elem_ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, value = class.value, dst_layout = ctx.dst_layout,
                },
                args = { ctx.dst_expr, ctx.start_expr, ctx.stop_expr, class.value_expr },
            })
        end
        if class.kind == "load" and ctx.store_index_primary == true and class.index_primary == true
            and same_type(class.elem_ty, ctx.dst_elem_ty) and type_ok(class.elem_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("copy", {
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = class.src, semantics = ctx.copy_semantics,
                    dst_layout = ctx.dst_layout, src_layout = class.src_layout,
                },
                args = { ctx.dst_expr, class.src_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "load" and ctx.store_index_primary == true and class.index_lane ~= nil
            and class.index_lane.index_primary == true and same_type(class.elem_ty, ctx.dst_elem_ty)
            and is_index_data_type(class.index_lane.elem_ty) and type_ok(class.elem_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("gather", {
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = class.src, index = class.index_lane.base,
                    index_ty = class.index_lane.elem_ty, dst_layout = ctx.dst_layout, src_layout = class.src_layout,
                    index_layout = class.index_lane.layout,
                },
                args = { ctx.dst_expr, class.src_expr, class.index_lane.base_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "load" and ctx.store_index_lane ~= nil and ctx.store_index_lane.index_primary == true
            and class.index_primary == true and same_type(class.elem_ty, ctx.dst_elem_ty)
            and is_index_data_type(ctx.store_index_lane.elem_ty) and type_ok(class.elem_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("scatter", {
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = class.src, index = ctx.store_index_lane.base,
                    index_ty = ctx.store_index_lane.elem_ty, conflicts = ctx.scatter_conflicts, dst_layout = ctx.dst_layout,
                    src_layout = class.src_layout, index_layout = ctx.store_index_lane.layout,
                },
                args = { ctx.dst_expr, class.src_expr, ctx.store_index_lane.base_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "map" and ctx.store_index_primary == true and class.index_primary == true
            and class.same_src_dst_ty == true and unary_supported(class.op, class.elem_ty)
            and same_type(class.result_ty, class.elem_ty) and type_ok(class.elem_ty) then
            return selection("in_place_map", {
                op = class.op,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty, result_ty = class.result_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = class.src, dst_layout = ctx.dst_layout,
                    src_layout = class.src_layout,
                },
                args = { ctx.dst_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "map" and ctx.store_index_primary == true and class.index_primary == true
            and unary_supported(class.op, class.elem_ty) and same_type(class.result_ty, ctx.dst_elem_ty)
            and type_ok(class.elem_ty) and type_ok(ctx.dst_elem_ty) and type_ok(class.result_ty) then
            return selection("map", {
                op = class.op,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty, result_ty = class.result_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = class.src, dst_layout = ctx.dst_layout,
                    src_layout = class.src_layout,
                },
                args = { ctx.dst_expr, class.src_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "cast" and ctx.store_index_primary == true and class.index_primary == true
            and same_type(class.result_ty, ctx.dst_elem_ty) and cast_supported(class.op, class.src_ty, class.result_ty)
            and type_ok(class.src_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("cast", {
                op = class.op,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = ctx.dst_elem_ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = class.src, src_ty = class.src_ty,
                    dst_ty = class.result_ty, dst_layout = ctx.dst_layout, src_layout = class.src_layout,
                },
                args = { ctx.dst_expr, class.src_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "compare" and ctx.store_index_primary == true and class.index_primary == true
            and is_bool8_type(ctx.dst_elem_ty) and same_type(class.result_ty, ctx.dst_elem_ty) and type_ok(class.elem_ty) then
            return selection("compare", {
                op = class.pred,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, src = class.src, pred = class.pred,
                    dst_layout = ctx.dst_layout, src_layout = class.src_layout,
                },
                args = { ctx.dst_expr, class.src_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "zip_map" and ctx.store_index_primary == true and class.lhs_index_primary == true
            and class.rhs_index_primary == true and same_type(class.lhs_ty, class.rhs_ty)
            and same_type(class.lhs_ty, class.result_ty) and same_type(class.result_ty, ctx.dst_elem_ty)
            and binary_supported(class.op, class.result_ty) and type_ok(class.result_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("zip_map", {
                op = class.op,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = ctx.dst_elem_ty, result_ty = class.result_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, lhs = class.lhs_base, rhs = class.rhs_base,
                    lhs_ty = class.lhs_ty, rhs_ty = class.rhs_ty, dst_layout = ctx.dst_layout,
                    lhs_layout = class.lhs_layout, rhs_layout = class.rhs_layout,
                },
                args = { ctx.dst_expr, class.lhs_expr, class.rhs_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "zip_compare" and ctx.store_index_primary == true and class.lhs_index_primary == true
            and class.rhs_index_primary == true and same_type(class.lhs_ty, class.rhs_ty) and is_bool8_type(ctx.dst_elem_ty)
            and type_ok(class.lhs_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("zip_compare", {
                op = class.cmp,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = ctx.dst_elem_ty, result_ty = ctx.dst_elem_ty,
                    dst = ctx.dst, start = ctx.start, stop = ctx.stop, lhs = class.lhs_base, rhs = class.rhs_base,
                    lhs_ty = class.lhs_ty, rhs_ty = class.rhs_ty, dst_layout = ctx.dst_layout,
                    lhs_layout = class.lhs_layout, rhs_layout = class.rhs_layout,
                },
                args = { ctx.dst_expr, class.lhs_expr, class.rhs_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        return nil
    end

    local function select_scan(ctx)
        local class = ctx.class or {}
        local input = class.kind == "apply_n" and single_input_expr(class) or nil
        if input ~= nil and ctx.store_index_primary == true and input.index_primary == true
            and same_type(ctx.result_ty, ctx.dst_elem_ty)
            and reduction_supported(ctx.reduction_kind, input.ty, ctx.result_ty) then
            return selection("scan", {
                reduction = ctx.reduction,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = input.ty, result_ty = ctx.result_ty,
                    init = ctx.init, mode = ctx.mode, axis = ctx.axis, dst = ctx.dst, array = input.base,
                    dst_layout = ctx.dst_layout, array_layout = input.layout,
                },
                args = { ctx.dst_expr, input.base_expr, ctx.start_expr, ctx.stop_expr, ctx.init_expr },
            })
        end
        if class.kind == "load" and ctx.store_index_primary == true and class.index_primary == true
            and same_type(ctx.result_ty, ctx.dst_elem_ty)
            and reduction_supported(ctx.reduction_kind, class.elem_ty, ctx.result_ty) then
            return selection("scan", {
                reduction = ctx.reduction,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty, result_ty = ctx.result_ty,
                    init = ctx.init, mode = ctx.mode, axis = ctx.axis, dst = ctx.dst, array = class.src,
                    dst_layout = ctx.dst_layout, array_layout = class.src_layout,
                },
                args = { ctx.dst_expr, class.src_expr, ctx.start_expr, ctx.stop_expr, ctx.init_expr },
            })
        end
        return nil
    end

    local function select_find(ctx)
        local class = ctx.class or {}
        local input = class.kind == "apply_n" and single_input_expr(class) or nil
        if input ~= nil and input.index_primary == true and ctx.not_found_minus_one == true and type_ok(input.ty) then
            return selection("find", {
                op = ctx.pred,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = input.ty,
                    array = input.base, pred = ctx.pred, array_layout = input.layout,
                },
                args = { input.base_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "load" and class.index_primary == true and ctx.not_found_minus_one == true and type_ok(class.elem_ty) then
            return selection("find", {
                op = ctx.pred,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty,
                    array = class.src, pred = ctx.pred, array_layout = class.src_layout,
                },
                args = { class.src_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        return nil
    end

    local function select_partition(ctx)
        local class = ctx.class or {}
        local input = class.kind == "apply_n" and single_input_expr(class) or nil
        if input ~= nil and ctx.store_index_primary == true and input.index_primary == true
            and same_type(input.ty, ctx.dst_elem_ty) and type_ok(input.ty) and type_ok(ctx.dst_elem_ty) then
            return selection("partition", {
                op = ctx.pred,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = input.ty,
                    dst = ctx.dst, array = input.base, pred = ctx.pred, semantics = ctx.semantics,
                    dst_layout = ctx.dst_layout, array_layout = input.layout,
                },
                args = { ctx.dst_expr, input.base_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "load" and ctx.store_index_primary == true and class.index_primary == true
            and same_type(class.elem_ty, ctx.dst_elem_ty) and type_ok(class.elem_ty) and type_ok(ctx.dst_elem_ty) then
            return selection("partition", {
                op = ctx.pred,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, elem_ty = class.elem_ty,
                    dst = ctx.dst, array = class.src, pred = ctx.pred, semantics = ctx.semantics,
                    dst_layout = ctx.dst_layout, array_layout = class.src_layout,
                },
                args = { ctx.dst_expr, class.src_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        return nil
    end

    local function select_reduce(ctx)
        local class = ctx.class or {}
        if class.kind == "apply_n" and all_apply_inputs_primary(class)
            and reduction_supported(ctx.reduction_kind, class.result_ty, ctx.result_ty) then
            return selection("reduce_n", {
                info = append_info_inputs({
                    step_num = ctx.step_num,
                    producer = ctx.producer,
                    result_ty = ctx.result_ty,
                    init = ctx.init,
                    inputs = class.inputs,
                    expr = class.expr,
                    item_ty = class.result_ty,
                    tag = "expr" .. tostring(#(class.inputs or {})),
                }, class.inputs),
                args = {},
            })
        end
        local pred_input, pred = predicate_expr_operand(class)
        if pred_input ~= nil and pred_input.index_primary == true and ctx.reduction_add == true
            and ctx.init_zero == true and ctx.result_i32 == true then
            return selection("count", {
                op = pred,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, result_ty = ctx.result_ty,
                    init = ctx.init, array = pred_input.base, elem_ty = pred_input.ty, pred = pred,
                    array_layout = pred_input.layout,
                },
                args = { pred_input.base_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        if class.kind == "load" and class.index_primary == true
            and reduction_supported(ctx.reduction_kind, class.elem_ty, ctx.result_ty) then
            return selection("reduce", {
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, result_ty = ctx.result_ty,
                    init = ctx.init, array = class.src, elem_ty = class.elem_ty, array_layout = class.src_layout,
                },
                args = { class.src_expr, ctx.start_expr, ctx.stop_expr, ctx.init_expr },
            })
        end
        if class.kind == "map" and class.index_primary == true and unary_supported(class.op, class.elem_ty)
            and reduction_supported(ctx.reduction_kind, class.result_ty, ctx.result_ty) then
            return selection("map_reduce", {
                op = class.op,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, result_ty = ctx.result_ty,
                    init = ctx.init, array = class.src, elem_ty = class.elem_ty, mapped_ty = class.result_ty,
                    array_layout = class.src_layout,
                },
                args = { class.src_expr, ctx.start_expr, ctx.stop_expr, ctx.init_expr },
            })
        end
        if class.kind == "zip_map" and class.lhs_index_primary == true and class.rhs_index_primary == true
            and same_type(class.lhs_ty, class.rhs_ty) and same_type(class.lhs_ty, class.result_ty)
            and binary_supported(class.op, class.result_ty)
            and reduction_supported(ctx.reduction_kind, class.result_ty, ctx.result_ty) then
            return selection("zip_reduce", {
                op = class.op,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, result_ty = ctx.result_ty,
                    init = ctx.init, lhs = class.lhs_base, rhs = class.rhs_base, lhs_ty = class.lhs_ty,
                    rhs_ty = class.rhs_ty, mapped_ty = class.result_ty, lhs_layout = class.lhs_layout,
                    rhs_layout = class.rhs_layout,
                },
                args = { class.lhs_expr, class.rhs_expr, ctx.start_expr, ctx.stop_expr, ctx.init_expr },
            })
        end
        if class.kind == "compare" and class.index_primary == true and ctx.reduction_add == true
            and ctx.init_zero == true and ctx.result_i32 == true then
            return selection("count", {
                op = class.pred,
                info = {
                    step_num = ctx.step_num, producer = ctx.producer, result_ty = ctx.result_ty,
                    init = ctx.init, array = class.src, elem_ty = class.elem_ty, pred = class.pred,
                    array_layout = class.src_layout,
                },
                args = { class.src_expr, ctx.start_expr, ctx.stop_expr },
            })
        end
        return nil
    end

    local constructors = {
        store_fill = { input = { "info", "args" }, output = { "selection" } },
        store_copy = { input = { "info", "args" }, output = { "selection" } },
        store_gather = { input = { "info", "args" }, output = { "selection" } },
        store_scatter = { input = { "info", "args" }, output = { "selection" } },
        store_in_place_map = { input = { "op", "info", "args" }, output = { "selection" } },
        store_map = { input = { "op", "info", "args" }, output = { "selection" } },
        store_cast = { input = { "op", "info", "args" }, output = { "selection" } },
        store_compare = { input = { "op", "info", "args" }, output = { "selection" } },
        store_zip_map = { input = { "op", "info", "args" }, output = { "selection" } },
        store_zip_compare = { input = { "op", "info", "args" }, output = { "selection" } },
        reduce_array = { input = { "info", "args" }, output = { "selection" } },
        scan_array = { input = { "reduction", "info", "args" }, output = { "selection" } },
        find_array = { input = { "op", "info", "args" }, output = { "selection" } },
        partition_array = { input = { "op", "info", "args" }, output = { "selection" } },
        reduce_map = { input = { "op", "info", "args" }, output = { "selection" } },
        reduce_zip = { input = { "op", "info", "args" }, output = { "selection" } },
        reduce_count = { input = { "op", "info", "args" }, output = { "selection" } },
        store_stencil_plan = { input = { "selection" }, output = { "plan" } },
        store_stencil_no_plan = { input = { "reason" }, output = { "plan" } },
        reduce_stencil_plan = { input = { "reduction", "selection" }, output = { "plan" } },
        reduce_stencil_no_plan = { input = { "reason" }, output = { "plan" } },
    }

    local function store_plan_reject_reason(ctx, suffix)
        return ("store stencil is not ready: planned=%s returns_void=%s counted_positive=%s single_store=%s dst_base_present=%s class_ready=%s (%s)"):format(
            tostring(ctx and ctx.planned), tostring(ctx and ctx.returns_void), tostring(ctx and ctx.counted_positive),
            tostring(ctx and ctx.single_store), tostring(ctx and ctx.dst_base_present), tostring(ctx and ctx.class_ready),
            tostring(suffix or "no matching plan")
        )
    end

    local function reduce_plan_reject_reason(ctx, suffix)
        return ("reduction stencil is not ready: planned=%s result_reduction=%s returns_reduction=%s counted_positive=%s class_ready=%s (%s)"):format(
            tostring(ctx and ctx.planned), tostring(ctx and ctx.result_reduction), tostring(ctx and ctx.returns_reduction),
            tostring(ctx and ctx.counted_positive), tostring(ctx and ctx.class_ready), tostring(suffix or "no matching plan")
        )
    end

    local function copy_fields(ctx)
        local out = {}
        for k, v in pairs(ctx or {}) do out[k] = v end
        return out
    end

    local api = {}

    function api:run(relation, input, _output_key, missing)
        local ctx = input and input.ctx
        if relation == "classify_expr" then
            local class = input and input.expr and classify_expr(input.expr)
            return class or nil, class == nil and (missing or "unsupported store stencil expression") or nil
        elseif relation == "classify_stencil_type" then
            local class = input and classify_type(input.ty)
            return class or nil, class == nil and (missing or "unsupported stencil type") or nil
        elseif relation == "select_index_lane" then
            local lane = input and input.class and select_index_lane(input.class)
            return lane or nil, lane == nil and (missing or "expression is not an index lane") or nil
        elseif relation == "select_store_stencil" then
            local selected = ctx and select_store(ctx)
            return selected or nil, selected == nil and (missing or "unsupported store stencil shape") or nil
        elseif relation == "select_scan_stencil" then
            local selected = ctx and select_scan(ctx)
            return selected or nil, selected == nil and (missing or "unsupported scan stencil shape") or nil
        elseif relation == "select_find_stencil" then
            local selected = ctx and select_find(ctx)
            return selected or nil, selected == nil and (missing or "unsupported find stencil shape") or nil
        elseif relation == "select_partition_stencil" then
            local selected = ctx and select_partition(ctx)
            return selected or nil, selected == nil and (missing or "unsupported partition stencil shape") or nil
        elseif relation == "select_reduce_stencil" then
            local selected = ctx and select_reduce(ctx)
            return selected or nil, selected == nil and (missing or "unsupported reduction stencil contribution") or nil
        end
        return nil, missing or ("unknown stencil selector relation " .. tostring(relation))
    end

    function api.classify_expr(expr, bindings)
        local fact, err = expr_fact(expr, bindings or {})
        if fact == nil then return nil, err end
        local class = classify_expr(fact)
        if class == nil then return nil, "unsupported store stencil expression" end
        return class
    end

    function api.classify_type(ty) return classify_type(ty) end

    function api.plan_store(ctx)
        local input = copy_fields(ctx)
        input.plan_ready = input.planned == true
            and input.returns_void == true
            and input.counted_positive == true
            and input.single_store == true
            and input.dst_base_present == true
            and input.class_ready == true
        input.reject_reason = store_plan_reject_reason(input)
        if not input.plan_ready then return nil, input.reject_reason end
        local selected, err = api:run("select_store_stencil", { ctx = input.selection_ctx }, "selection", "no matching plan")
        if selected == nil then return nil, store_plan_reject_reason(input, err) end
        return { selection = selected }, nil
    end

    function api.plan_reduce(ctx)
        local input = copy_fields(ctx)
        input.plan_ready = input.planned == true
            and input.result_reduction == true
            and input.returns_reduction == true
            and input.counted_positive == true
            and input.class_ready == true
        input.reject_reason = reduce_plan_reject_reason(input)
        if not input.plan_ready then return nil, input.reject_reason end
        local selected, err = api:run("select_reduce_stencil", { ctx = input.selection_ctx }, "selection", "no matching plan")
        if selected == nil then return nil, reduce_plan_reject_reason(input, err) end
        return { reduction = input.reduction, selection = selected }, nil
    end

    function api.constructor(name) return constructors[name] end

    function api.constructor_contract(name)
        local contract = constructors[name]
        if contract == nil then return nil end
        return { name = name, input = contract.input, output = contract.output, decl = contract }
    end

    api.expr_fact = expr_fact

    T._lalin_api_cache.stencil_rules = api
    return api
end

return bind_context
