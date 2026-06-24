local pvm = require("moonlift.pvm")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.stencil_c ~= nil then return T._moonlift_api_cache.stencil_c end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Value = T.MoonValue
    local Kernel = T.MoonKernel
    local Stencil = T.MoonStencil
    local CodeType = require("moonlift.code_type")(T)
    local CEmit = require("moonlift.c_emit")(T)

    local api = {}

    local function type_name(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if ty == Code.CodeTyIndex then return "index" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        return "ty"
    end

    local function c_type(ty)
        return CEmit.emit_type(CodeType.code_type_to_c(ty, {}))
    end

    local function unsigned_c_type(ty)
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt and (ty.bits == 8 or ty.bits == 16 or ty.bits == 32 or ty.bits == 64) then return "uint" .. tostring(ty.bits) .. "_t" end
        return c_type(ty)
    end

    local function reduction_name(kind)
        if kind == Value.ReductionAdd then return "add" end
        if kind == Value.ReductionMul then return "mul" end
        if kind == Value.ReductionAnd then return "and" end
        if kind == Value.ReductionOr then return "or" end
        if kind == Value.ReductionXor then return "xor" end
        if kind == Value.ReductionMin then return "min" end
        if kind == Value.ReductionMax then return "max" end
        return "reduction"
    end

    local function unary_name(op)
        if op == Stencil.StencilUnaryIdentity then return "identity" end
        if op == Stencil.StencilUnaryNeg then return "neg" end
        if op == Stencil.StencilUnaryBitNot then return "bitnot" end
        if op == Stencil.StencilUnaryBoolNot then return "boolnot" end
        return "unary"
    end

    local function binary_name(op)
        if op == Stencil.StencilBinaryAdd then return "add" end
        if op == Stencil.StencilBinarySub then return "sub" end
        if op == Stencil.StencilBinaryMul then return "mul" end
        if op == Stencil.StencilBinaryAnd then return "and" end
        if op == Stencil.StencilBinaryOr then return "or" end
        if op == Stencil.StencilBinaryXor then return "xor" end
        if op == Stencil.StencilBinaryMin then return "min" end
        if op == Stencil.StencilBinaryMax then return "max" end
        return "binary"
    end

    local function pred_name(pred)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return "nonzero" end
        if cls == Stencil.StencilPredEqConst then return "eq" end
        if cls == Stencil.StencilPredNeConst then return "ne" end
        if cls == Stencil.StencilPredLtConst then return "lt" end
        if cls == Stencil.StencilPredLeConst then return "le" end
        if cls == Stencil.StencilPredGtConst then return "gt" end
        if cls == Stencil.StencilPredGeConst then return "ge" end
        return "pred"
    end

    local function cmp_name(op)
        if op == Core.CmpEq then return "eq" end
        if op == Core.CmpNe then return "ne" end
        if op == Core.CmpLt then return "lt" end
        if op == Core.CmpLe then return "le" end
        if op == Core.CmpGt then return "gt" end
        if op == Core.CmpGe then return "ge" end
        return "cmp"
    end

    local function cast_name(op)
        if op == Core.MachineCastIdentity then return "identity" end
        if op == Core.MachineCastBitcast then return "bitcast" end
        if op == Core.MachineCastIreduce then return "ireduce" end
        if op == Core.MachineCastSextend then return "sext" end
        if op == Core.MachineCastUextend then return "uext" end
        if op == Core.MachineCastFpromote then return "fpromote" end
        if op == Core.MachineCastFdemote then return "fdemote" end
        if op == Core.MachineCastSToF then return "stof" end
        if op == Core.MachineCastUToF then return "utof" end
        if op == Core.MachineCastFToS then return "ftos" end
        if op == Core.MachineCastFToU then return "ftou" end
        return "cast"
    end

    local function scan_mode_name(mode)
        if mode == Stencil.StencilScanInclusive then return "inclusive" end
        if mode == Stencil.StencilScanExclusive then return "exclusive" end
        return "scan"
    end

    local function copy_semantics_name(semantics)
        if semantics == Stencil.StencilCopyNoOverlap then return "nooverlap" end
        if semantics == Stencil.StencilCopyMayOverlapForward then return "forward" end
        if semantics == Stencil.StencilCopyMayOverlapBackward then return "backward" end
        if semantics == Stencil.StencilCopyMemMove then return "memmove" end
        return "copy"
    end

    local function partition_semantics_name(semantics)
        if semantics == Stencil.StencilPartitionStable then return "stable" end
        if semantics == Stencil.StencilPartitionUnstable then return "unstable" end
        return "partition"
    end

    local function scatter_conflict_name(conflicts)
        if conflicts == Stencil.StencilScatterUniqueIndices then return "unique" end
        if conflicts == Stencil.StencilScatterLastWriteWins then return "last" end
        if conflicts == Stencil.StencilScatterConflictUndefined then return "undefined" end
        return "scatter"
    end

    local function proof_list(plan)
        local eq = plan and plan.body and plan.body.equivalence or nil
        if pvm.classof(eq) == Kernel.KernelEquivalenceProof then return eq.proofs or {} end
        return {}
    end

    local function reduce_instance_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilInstanceId("stencil:reduce_array:" .. type_name(elem_ty) .. ":" .. reduction_name(reduction) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
    end

    local function reduce_symbol_id(elem_ty, result_ty, reduction, stride)
        return Stencil.StencilSymbolId("ml_stencil_reduce_array_" .. type_name(elem_ty) .. "_" .. reduction_name(reduction) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
    end

    local function reduce_c_decl(symbol, elem_ty, result_ty)
        local elem = c_type(elem_ty)
        local result = c_type(result_ty)
        return result .. " " .. symbol.text .. "(const " .. elem .. " *xs, int32_t start, int32_t stop, " .. result .. " init);"
    end

    local function scalar_param_ty(ty)
        return c_type(ty)
    end

    local function void_decl(symbol, args)
        return "void " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function result_decl(symbol, result_ty, args)
        return c_type(result_ty) .. " " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function int32_decl(symbol, args)
        return "int32_t " .. symbol.text .. "(" .. table.concat(args, ", ") .. ");"
    end

    local function is_int(ty)
        return pvm.classof(ty) == Code.CodeTyInt
    end

    local function is_float(ty)
        return pvm.classof(ty) == Code.CodeTyFloat
    end

    local function same_type(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function is_scalar(ty)
        local cls = pvm.classof(ty)
        return cls == Code.CodeTyInt or cls == Code.CodeTyFloat or ty == Code.CodeTyIndex or ty == Code.CodeTyBool8
    end

    local function supports_bitwise_ty(ty)
        return pvm.classof(ty) == Code.CodeTyInt or ty == Code.CodeTyBool8
    end

    local function const_literal_source(expr, ty)
        local cls = pvm.classof(expr)
        if cls ~= Value.ValueExprConst or pvm.classof(expr.const) ~= Code.CodeConstLiteral then
            error("stencil_c: predicate/fill const must be a literal ValueExprConst", 3)
        end
        local lit = expr.const.literal
        local lcls = pvm.classof(lit)
        if lcls == Core.LitInt then
            local raw = tostring(lit.raw)
            local tcls = pvm.classof(ty or expr.const.ty)
            if tcls == Code.CodeTyInt and ty.bits == 64 then
                return raw .. ((ty.signedness == Code.CodeUnsigned) and "ULL" or "LL")
            end
            return raw
        elseif lcls == Core.LitFloat then
            return tostring(lit.raw)
        elseif lcls == Core.LitBool then
            return lit.value and "1" or "0"
        end
        error("stencil_c: unsupported literal for C stencil", 3)
    end

    local function predicate_expr(pred, item, ty)
        local cls = pvm.classof(pred)
        if pred == Stencil.StencilPredNonZero or cls == Stencil.StencilPredNonZero then return "(" .. item .. " != 0)" end
        local c = "(" .. c_type(ty) .. ")(" .. const_literal_source(pred.value, ty) .. ")"
        if cls == Stencil.StencilPredEqConst then return "(" .. item .. " == " .. c .. ")" end
        if cls == Stencil.StencilPredNeConst then return "(" .. item .. " != " .. c .. ")" end
        if cls == Stencil.StencilPredLtConst then return "(" .. item .. " < " .. c .. ")" end
        if cls == Stencil.StencilPredLeConst then return "(" .. item .. " <= " .. c .. ")" end
        if cls == Stencil.StencilPredGtConst then return "(" .. item .. " > " .. c .. ")" end
        if cls == Stencil.StencilPredGeConst then return "(" .. item .. " >= " .. c .. ")" end
        error("stencil_c: unsupported predicate " .. pred_name(pred), 3)
    end

    local function compare_expr(cmp, lhs, rhs)
        if cmp == Core.CmpEq then return "(" .. lhs .. " == " .. rhs .. ")" end
        if cmp == Core.CmpNe then return "(" .. lhs .. " != " .. rhs .. ")" end
        if cmp == Core.CmpLt then return "(" .. lhs .. " < " .. rhs .. ")" end
        if cmp == Core.CmpLe then return "(" .. lhs .. " <= " .. rhs .. ")" end
        if cmp == Core.CmpGt then return "(" .. lhs .. " > " .. rhs .. ")" end
        if cmp == Core.CmpGe then return "(" .. lhs .. " >= " .. rhs .. ")" end
        error("stencil_c: unsupported compare op " .. cmp_name(cmp), 3)
    end

    local function bool_result_expr(cond, result_ty)
        return "(" .. c_type(result_ty) .. ")((" .. cond .. ") ? 1 : 0)"
    end

    local function reduction_update_expr(kind, acc, item, ty)
        local ct = c_type(ty)
        local acc_ty = (kind == Value.ReductionMin or kind == Value.ReductionMax) and ct or unsigned_c_type(ty)
        if kind == Value.ReductionAdd then return "(" .. acc_ty .. ")((" .. acc .. ") + (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionMul then return "(" .. acc_ty .. ")((" .. acc .. ") * (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionAnd then return "(" .. acc_ty .. ")((" .. acc .. ") & (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionOr then return "(" .. acc_ty .. ")((" .. acc .. ") | (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionXor then return "(" .. acc_ty .. ")((" .. acc .. ") ^ (" .. acc_ty .. ")(" .. item .. "))" end
        if kind == Value.ReductionMin then return "((" .. item .. ") < (" .. acc .. ") ? (" .. item .. ") : (" .. acc .. "))" end
        if kind == Value.ReductionMax then return "((" .. item .. ") > (" .. acc .. ") ? (" .. item .. ") : (" .. acc .. "))" end
        error("stencil_c: unsupported reduction " .. reduction_name(kind), 3)
    end

    local function unary_expr(op, value, result_ty)
        local ct = c_type(result_ty)
        if op == Stencil.StencilUnaryIdentity then return "(" .. ct .. ")(" .. value .. ")" end
        if op == Stencil.StencilUnaryNeg then return "(" .. ct .. ")(-(" .. value .. "))" end
        if op == Stencil.StencilUnaryBitNot then return "(" .. ct .. ")(~(" .. unsigned_c_type(result_ty) .. ")(" .. value .. "))" end
        if op == Stencil.StencilUnaryBoolNot then return "(" .. ct .. ")(!(" .. value .. "))" end
        error("stencil_c: unsupported unary op " .. unary_name(op), 3)
    end

    local function binary_expr(op, lhs, rhs, result_ty)
        local ct = c_type(result_ty)
        local ut = unsigned_c_type(result_ty)
        if op == Stencil.StencilBinaryAdd then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") + (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinarySub then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") - (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryMul then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") * (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryAnd then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") & (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryOr then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") | (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryXor then return "(" .. ct .. ")((" .. ut .. ")(" .. lhs .. ") ^ (" .. ut .. ")(" .. rhs .. "))" end
        if op == Stencil.StencilBinaryMin then return "((" .. lhs .. ") < (" .. rhs .. ") ? (" .. lhs .. ") : (" .. rhs .. "))" end
        if op == Stencil.StencilBinaryMax then return "((" .. lhs .. ") > (" .. rhs .. ") ? (" .. lhs .. ") : (" .. rhs .. "))" end
        error("stencil_c: unsupported binary op " .. binary_name(op), 3)
    end

    function api.reduce_array_supported(reduction, info)
        local elem_ty = info and info.elem_ty or nil
        local result_ty = info and info.result_ty or nil
        if elem_ty == nil or result_ty == nil then return false, "reduce_array stencil requires elem_ty and result_ty" end
        if not same_type(elem_ty, result_ty) then return false, "reduce_array stencil currently requires matching element/result types" end
        local ok_type, err = pcall(function() c_type(elem_ty); c_type(result_ty) end)
        if not ok_type then return false, tostring(err) end
        local kind = reduction.kind
        if is_int(result_ty) then
            if kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionAnd or kind == Value.ReductionOr or kind == Value.ReductionXor
                or kind == Value.ReductionMin or kind == Value.ReductionMax then
                return true
            end
            return false, "unsupported integer reduction"
        end
        if is_float(result_ty) then
            if kind == Value.ReductionAdd or kind == Value.ReductionMul
                or kind == Value.ReductionMin or kind == Value.ReductionMax then
                return true
            end
            return false, "float reduce_array stencil only supports add/mul/min/max"
        end
        return false, "reduce_array stencil only supports integer and float scalar types"
    end

    local function binary_supported(op, ty)
        if op == Stencil.StencilBinaryAnd or op == Stencil.StencilBinaryOr or op == Stencil.StencilBinaryXor then return supports_bitwise_ty(ty) end
        return is_scalar(ty)
    end

    local function unary_supported(op, ty)
        if op == Stencil.StencilUnaryBitNot then return supports_bitwise_ty(ty) end
        return is_scalar(ty)
    end

    local function artifact(instance, symbol, signature)
        return Stencil.StencilArtifact(instance, Stencil.StencilProviderC, symbol, signature)
    end

    function api.reduce_array_artifact(reduction, plan, info)
        local elem_ty = assert(info.elem_ty, "stencil_c.reduce_array_artifact requires elem_ty")
        local result_ty = assert(info.result_ty, "stencil_c.reduce_array_artifact requires result_ty")
        local stride = assert(info.step_num, "stencil_c.reduce_array_artifact requires step_num")
        local supported, reason = api.reduce_array_supported(reduction, info)
        if not supported then error("stencil_c: unsupported reduce_array artifact: " .. tostring(reason), 2) end
        local id = reduce_instance_id(elem_ty, result_ty, reduction.kind, stride)
        local symbol = reduce_symbol_id(elem_ty, result_ty, reduction.kind, stride)
        local instance = Stencil.StencilInstance(
            id,
            Stencil.StencilReduceArray,
            Stencil.StencilShapeReduceArray(
                elem_ty,
                result_ty,
                reduction.kind,
                reduction.int_semantics,
                reduction.float_mode,
                reduction.init,
                stride
            ),
            {
                Stencil.StencilParamType("elem_ty", elem_ty),
                Stencil.StencilParamType("result_ty", result_ty),
                Stencil.StencilParamReduction("reduction", reduction.kind),
                Stencil.StencilParamNumber("stride", stride),
                Stencil.StencilParamValueExpr("init", reduction.init),
            },
            Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned), result_ty }, result_ty),
            proof_list(plan)
        )
        return artifact(instance, symbol, reduce_c_decl(symbol, elem_ty, result_ty))
    end

    function api.map_array_artifact(op, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_c: unsupported map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:map_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_map_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilMapArray, Stencil.StencilShapeMapArray(elem_ty, result_ty, op, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", unary_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(result_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.zip_map_array_artifact(op, info)
        local lhs_ty, rhs_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) or not same_type(lhs_ty, result_ty) then error("stencil_c: zip_map_array currently requires matching lhs/rhs/result types", 2) end
        if not binary_supported(op, result_ty) then error("stencil_c: unsupported zip_map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_map_array:" .. type_name(lhs_ty) .. ":" .. binary_name(op) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_map_array_" .. type_name(lhs_ty) .. "_" .. binary_name(op) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilZipMapArray, Stencil.StencilShapeZipMapArray(lhs_ty, rhs_ty, result_ty, op, stride), {
            Stencil.StencilParamType("lhs_ty", lhs_ty),
            Stencil.StencilParamType("rhs_ty", rhs_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", binary_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(result_ty) .. " *dst", "const " .. c_type(lhs_ty) .. " *lhs", "const " .. c_type(rhs_ty) .. " *rhs", "int32_t start", "int32_t stop" }))
    end

    function api.scan_array_artifact(reduction, plan, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local mode = info.mode or Stencil.StencilScanInclusive
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = elem_ty, result_ty = result_ty })
        if not ok then error("stencil_c: unsupported scan_array artifact: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:scan_array:" .. type_name(elem_ty) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":" .. scan_mode_name(mode) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_scan_array_" .. type_name(elem_ty) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_" .. scan_mode_name(mode) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilScanArray, Stencil.StencilShapeScanArray(elem_ty, result_ty, reduction.kind, reduction.int_semantics, reduction.float_mode, reduction.init, mode, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamReduction("reduction", reduction.kind),
            Stencil.StencilParamText("mode", scan_mode_name(mode)),
            Stencil.StencilParamNumber("stride", stride),
            Stencil.StencilParamValueExpr("init", reduction.init),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned), result_ty }, result_ty), proof_list(plan))
        return artifact(instance, symbol, result_decl(symbol, result_ty, { c_type(result_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.copy_array_artifact(info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilCopyNoOverlap
        local id = Stencil.StencilInstanceId("stencil:copy_array:" .. type_name(elem_ty) .. ":" .. copy_semantics_name(semantics) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_copy_array_" .. type_name(elem_ty) .. "_" .. copy_semantics_name(semantics) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilCopyArray, Stencil.StencilShapeCopyArray(elem_ty, semantics, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("semantics", copy_semantics_name(semantics)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *src", "int32_t start", "int32_t stop" }))
    end

    function api.fill_array_artifact(info)
        local elem_ty, stride, value = assert(info.elem_ty), assert(info.step_num or info.stride or 1), assert(info.value)
        local id = Stencil.StencilInstanceId("stencil:fill_array:" .. type_name(elem_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_fill_array_" .. type_name(elem_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilFillArray, Stencil.StencilShapeFillArray(elem_ty, value, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamValueExpr("value", value),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned), elem_ty }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(elem_ty) .. " *dst", "int32_t start", "int32_t stop", scalar_param_ty(elem_ty) .. " value" }))
    end

    function api.find_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:find_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_find_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilFindArray, Stencil.StencilShapeFindArray(elem_ty, pred, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, Code.CodeTyInt(32, Code.CodeSigned)), {})
        return artifact(instance, symbol, int32_decl(symbol, { "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.partition_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local semantics = info.semantics or Stencil.StencilPartitionStable
        local id = Stencil.StencilInstanceId("stencil:partition_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":" .. partition_semantics_name(semantics) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_partition_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_" .. partition_semantics_name(semantics) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilPartitionArray, Stencil.StencilShapePartitionArray(elem_ty, pred, semantics, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamText("semantics", partition_semantics_name(semantics)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, Code.CodeTyInt(32, Code.CodeSigned)), {})
        return artifact(instance, symbol, int32_decl(symbol, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.cast_array_artifact(op, info)
        local src_ty, dst_ty, stride = assert(info.src_ty), assert(info.dst_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:cast_array:" .. type_name(src_ty) .. ":" .. cast_name(op) .. ":to:" .. type_name(dst_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_cast_array_" .. type_name(src_ty) .. "_" .. cast_name(op) .. "_to_" .. type_name(dst_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilCastArray, Stencil.StencilShapeCastArray(src_ty, dst_ty, op, stride), {
            Stencil.StencilParamType("src_ty", src_ty),
            Stencil.StencilParamType("dst_ty", dst_ty),
            Stencil.StencilParamText("op", cast_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(dst_ty), Code.CodeTyDataPtr(src_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(dst_ty) .. " *dst", "const " .. c_type(src_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.compare_array_artifact(pred, info)
        local elem_ty, result_ty, stride = assert(info.elem_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:compare_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_compare_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilCompareArray, Stencil.StencilShapeCompareArray(elem_ty, result_ty, pred, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(result_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.zip_compare_array_artifact(cmp, info)
        local lhs_ty, rhs_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) then error("stencil_c: zip_compare_array currently requires matching lhs/rhs types", 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_compare_array:" .. type_name(lhs_ty) .. ":" .. cmp_name(cmp) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_compare_array_" .. type_name(lhs_ty) .. "_" .. cmp_name(cmp) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilZipCompareArray, Stencil.StencilShapeZipCompareArray(lhs_ty, rhs_ty, result_ty, cmp, stride), {
            Stencil.StencilParamType("lhs_ty", lhs_ty),
            Stencil.StencilParamType("rhs_ty", rhs_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("cmp", cmp_name(cmp)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(result_ty), Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(result_ty) .. " *dst", "const " .. c_type(lhs_ty) .. " *lhs", "const " .. c_type(rhs_ty) .. " *rhs", "int32_t start", "int32_t stop" }))
    end

    function api.gather_array_artifact(info)
        local elem_ty, index_ty, stride = assert(info.elem_ty), assert(info.index_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:gather_array:" .. type_name(elem_ty) .. ":index:" .. type_name(index_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_gather_array_" .. type_name(elem_ty) .. "_idx_" .. type_name(index_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilGatherArray, Stencil.StencilShapeGatherArray(elem_ty, index_ty, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("index_ty", index_ty),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(index_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *src", "const " .. c_type(index_ty) .. " *idx", "int32_t start", "int32_t stop" }))
    end

    function api.scatter_array_artifact(info)
        local elem_ty, index_ty, stride = assert(info.elem_ty), assert(info.index_ty), assert(info.step_num or info.stride or 1)
        local conflicts = info.conflicts or Stencil.StencilScatterUniqueIndices
        local id = Stencil.StencilInstanceId("stencil:scatter_array:" .. type_name(elem_ty) .. ":index:" .. type_name(index_ty) .. ":" .. scatter_conflict_name(conflicts) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_scatter_array_" .. type_name(elem_ty) .. "_idx_" .. type_name(index_ty) .. "_" .. scatter_conflict_name(conflicts) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilScatterArray, Stencil.StencilShapeScatterArray(elem_ty, index_ty, conflicts, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("index_ty", index_ty),
            Stencil.StencilParamText("conflicts", scatter_conflict_name(conflicts)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(elem_ty), Code.CodeTyDataPtr(index_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(elem_ty) .. " *dst", "const " .. c_type(elem_ty) .. " *src", "const " .. c_type(index_ty) .. " *idx", "int32_t start", "int32_t stop" }))
    end

    function api.in_place_map_array_artifact(op, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_c: unsupported in_place_map_array op/type", 2) end
        local id = Stencil.StencilInstanceId("stencil:in_place_map_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_in_place_map_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilInPlaceMapArray, Stencil.StencilShapeInPlaceMapArray(elem_ty, op, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("op", unary_name(op)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, nil), {})
        return artifact(instance, symbol, void_decl(symbol, { c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.count_array_artifact(pred, info)
        local elem_ty, stride = assert(info.elem_ty), assert(info.step_num or info.stride or 1)
        local id = Stencil.StencilInstanceId("stencil:count_array:" .. type_name(elem_ty) .. ":" .. pred_name(pred) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_count_array_" .. type_name(elem_ty) .. "_" .. pred_name(pred) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilCountArray, Stencil.StencilShapeCountArray(elem_ty, pred, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamText("pred", pred_name(pred)),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned) }, Code.CodeTyInt(32, Code.CodeSigned)), {})
        return artifact(instance, symbol, int32_decl(symbol, { "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop" }))
    end

    function api.map_reduce_array_artifact(op, reduction, plan, info)
        local elem_ty, mapped_ty, result_ty, stride = assert(info.elem_ty), assert(info.mapped_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not unary_supported(op, elem_ty) then error("stencil_c: unsupported map_reduce_array op/type", 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = mapped_ty, result_ty = result_ty })
        if not ok then error("stencil_c: unsupported map_reduce_array reduction: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:map_reduce_array:" .. type_name(elem_ty) .. ":" .. unary_name(op) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_map_reduce_array_" .. type_name(elem_ty) .. "_" .. unary_name(op) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilMapReduceArray, Stencil.StencilShapeMapReduceArray(elem_ty, mapped_ty, result_ty, op, reduction.kind, reduction.int_semantics, reduction.float_mode, reduction.init, stride), {
            Stencil.StencilParamType("elem_ty", elem_ty),
            Stencil.StencilParamType("mapped_ty", mapped_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", unary_name(op)),
            Stencil.StencilParamReduction("reduction", reduction.kind),
            Stencil.StencilParamValueExpr("init", reduction.init),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(elem_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned), result_ty }, result_ty), proof_list(plan))
        return artifact(instance, symbol, result_decl(symbol, result_ty, { "const " .. c_type(elem_ty) .. " *xs", "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    function api.zip_reduce_array_artifact(op, reduction, plan, info)
        local lhs_ty, rhs_ty, mapped_ty, result_ty, stride = assert(info.lhs_ty), assert(info.rhs_ty), assert(info.mapped_ty), assert(info.result_ty), assert(info.step_num or info.stride or 1)
        if not same_type(lhs_ty, rhs_ty) or not same_type(lhs_ty, mapped_ty) then error("stencil_c: zip_reduce_array currently requires matching lhs/rhs/mapped types", 2) end
        if not binary_supported(op, mapped_ty) then error("stencil_c: unsupported zip_reduce_array op/type", 2) end
        local ok, reason = api.reduce_array_supported(reduction, { elem_ty = mapped_ty, result_ty = result_ty })
        if not ok then error("stencil_c: unsupported zip_reduce_array reduction: " .. tostring(reason), 2) end
        local id = Stencil.StencilInstanceId("stencil:zip_reduce_array:" .. type_name(lhs_ty) .. ":" .. binary_name(op) .. ":" .. reduction_name(reduction.kind) .. ":to:" .. type_name(result_ty) .. ":stride" .. tostring(stride))
        local symbol = Stencil.StencilSymbolId("ml_stencil_zip_reduce_array_" .. type_name(lhs_ty) .. "_" .. binary_name(op) .. "_" .. reduction_name(reduction.kind) .. "_to_" .. type_name(result_ty) .. "_s" .. tostring(stride))
        local instance = Stencil.StencilInstance(id, Stencil.StencilZipReduceArray, Stencil.StencilShapeZipReduceArray(lhs_ty, rhs_ty, mapped_ty, result_ty, op, reduction.kind, reduction.int_semantics, reduction.float_mode, reduction.init, stride), {
            Stencil.StencilParamType("lhs_ty", lhs_ty),
            Stencil.StencilParamType("rhs_ty", rhs_ty),
            Stencil.StencilParamType("mapped_ty", mapped_ty),
            Stencil.StencilParamType("result_ty", result_ty),
            Stencil.StencilParamText("op", binary_name(op)),
            Stencil.StencilParamReduction("reduction", reduction.kind),
            Stencil.StencilParamValueExpr("init", reduction.init),
            Stencil.StencilParamNumber("stride", stride),
        }, Stencil.StencilAbi({ Code.CodeTyDataPtr(lhs_ty), Code.CodeTyDataPtr(rhs_ty), Code.CodeTyInt(32, Code.CodeSigned), Code.CodeTyInt(32, Code.CodeSigned), result_ty }, result_ty), proof_list(plan))
        return artifact(instance, symbol, result_decl(symbol, result_ty, { "const " .. c_type(lhs_ty) .. " *lhs", "const " .. c_type(rhs_ty) .. " *rhs", "int32_t start", "int32_t stop", c_type(result_ty) .. " init" }))
    end

    local function reduce_array_source(artifact)
        local shape = artifact.instance.shape
        local elem_ty, result_ty = shape.elem_ty, shape.result_ty
        local ct = c_type(result_ty)
        local et = c_type(elem_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and ct or unsigned_c_type(result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = ct .. " " .. artifact.symbol.text .. "(const " .. et .. " *xs, int32_t start, int32_t stop, " .. ct .. " init) {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        if shape.reduction == Value.ReductionAdd then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc + (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionMul then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc * (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionAnd then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc & (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionOr then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc | (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionXor then
            lines[#lines + 1] = "        acc = (" .. acc_ty .. ")(acc ^ (" .. acc_ty .. ")xs[i]);"
        elseif shape.reduction == Value.ReductionMin then
            lines[#lines + 1] = "        if (xs[i] < acc) acc = xs[i];"
        elseif shape.reduction == Value.ReductionMax then
            lines[#lines + 1] = "        if (xs[i] > acc) acc = xs[i];"
        else
            error("stencil_c: unsupported reduce_array reduction " .. reduction_name(shape.reduction), 3)
        end
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. ct .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function map_array_source(artifact)
        local shape = artifact.instance.shape
        local et, rt = c_type(shape.elem_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. rt .. " *dst, const " .. et .. " *xs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        dst[i] = " .. unary_expr(shape.op, "xs[i]", shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function zip_map_array_source(artifact)
        local shape = artifact.instance.shape
        local lt, rt = c_type(shape.lhs_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. rt .. " *dst, const " .. lt .. " *lhs, const " .. lt .. " *rhs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        dst[i] = " .. binary_expr(shape.op, "lhs[i]", "rhs[i]", shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function scan_array_source(artifact)
        local shape = artifact.instance.shape
        local et, rt = c_type(shape.elem_ty), c_type(shape.result_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = rt .. " " .. artifact.symbol.text .. "(" .. rt .. " *dst, const " .. et .. " *xs, int32_t start, int32_t stop, " .. rt .. " init) {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        if shape.mode == Stencil.StencilScanExclusive then
            lines[#lines + 1] = "        dst[i] = (" .. rt .. ")acc;"
            lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", "xs[i]", shape.result_ty) .. ";"
        else
            lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", "xs[i]", shape.result_ty) .. ";"
            lines[#lines + 1] = "        dst[i] = (" .. rt .. ")acc;"
        end
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. rt .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function copy_array_source(artifact)
        local shape = artifact.instance.shape
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. et .. " *dst, const " .. et .. " *src, int32_t start, int32_t stop) {"
        if shape.semantics == Stencil.StencilCopyMemMove and stride == 1 then
            lines[#lines + 1] = "    if (stop > start) memmove(dst + start, src + start, (size_t)(stop - start) * sizeof(" .. et .. "));"
        elseif shape.semantics == Stencil.StencilCopyMayOverlapBackward then
            lines[#lines + 1] = "    for (int32_t i = stop - 1; i >= start; i -= " .. tostring(stride) .. ") dst[i] = src[i];"
        elseif shape.semantics == Stencil.StencilCopyMemMove then
            lines[#lines + 1] = "    if ((uintptr_t)dst <= (uintptr_t)src) {"
            lines[#lines + 1] = "        for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[i] = src[i];"
            lines[#lines + 1] = "    } else {"
            lines[#lines + 1] = "        for (int32_t i = stop - 1; i >= start; i -= " .. tostring(stride) .. ") dst[i] = src[i];"
            lines[#lines + 1] = "    }"
        else
            lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[i] = src[i];"
        end
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function fill_array_source(artifact)
        local shape = artifact.instance.shape
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. et .. " *dst, int32_t start, int32_t stop, " .. et .. " value) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[i] = value;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function find_array_source(artifact)
        local shape = artifact.instance.shape
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(const " .. et .. " *xs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        if " .. predicate_expr(shape.pred, "xs[i]", shape.elem_ty) .. " return i;"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return -1;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function partition_array_source(artifact)
        local shape = artifact.instance.shape
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(" .. et .. " *dst, const " .. et .. " *xs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    int32_t out = start;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") { if " .. predicate_expr(shape.pred, "xs[i]", shape.elem_ty) .. " dst[out++] = xs[i]; }"
        lines[#lines + 1] = "    int32_t split = out;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") { if (!" .. predicate_expr(shape.pred, "xs[i]", shape.elem_ty) .. ") dst[out++] = xs[i]; }"
        lines[#lines + 1] = "    return split;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function cast_array_source(artifact)
        local shape = artifact.instance.shape
        local st, dt = c_type(shape.src_ty), c_type(shape.dst_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. dt .. " *dst, const " .. st .. " *xs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        if shape.op == Core.MachineCastBitcast then
            lines[#lines + 1] = "        memset(&dst[i], 0, sizeof(dst[i]));"
            lines[#lines + 1] = "        memcpy(&dst[i], &xs[i], sizeof(dst[i]) < sizeof(xs[i]) ? sizeof(dst[i]) : sizeof(xs[i]));"
        else
            lines[#lines + 1] = "        dst[i] = (" .. dt .. ")(xs[i]);"
        end
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function compare_array_source(artifact)
        local shape = artifact.instance.shape
        local et, rt = c_type(shape.elem_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. rt .. " *dst, const " .. et .. " *xs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[i] = " .. bool_result_expr(predicate_expr(shape.pred, "xs[i]", shape.elem_ty), shape.result_ty) .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function zip_compare_array_source(artifact)
        local shape = artifact.instance.shape
        local lt, rt = c_type(shape.lhs_ty), c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. rt .. " *dst, const " .. lt .. " *lhs, const " .. lt .. " *rhs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[i] = " .. bool_result_expr(compare_expr(shape.cmp, "lhs[i]", "rhs[i]"), shape.result_ty) .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function gather_array_source(artifact)
        local shape = artifact.instance.shape
        local et, it = c_type(shape.elem_ty), c_type(shape.index_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. et .. " *dst, const " .. et .. " *src, const " .. it .. " *idx, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[i] = src[(intptr_t)idx[i]];"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function scatter_array_source(artifact)
        local shape = artifact.instance.shape
        local et, it = c_type(shape.elem_ty), c_type(shape.index_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. et .. " *dst, const " .. et .. " *src, const " .. it .. " *idx, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") dst[(intptr_t)idx[i]] = src[i];"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function in_place_map_array_source(artifact)
        local shape = artifact.instance.shape
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "void " .. artifact.symbol.text .. "(" .. et .. " *xs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") xs[i] = " .. unary_expr(shape.op, "xs[i]", shape.elem_ty) .. ";"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function count_array_source(artifact)
        local shape = artifact.instance.shape
        local et = c_type(shape.elem_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = "int32_t " .. artifact.symbol.text .. "(const " .. et .. " *xs, int32_t start, int32_t stop) {"
        lines[#lines + 1] = "    int32_t count = 0;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") if " .. predicate_expr(shape.pred, "xs[i]", shape.elem_ty) .. " count++;"
        lines[#lines + 1] = "    return count;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function map_reduce_array_source(artifact)
        local shape = artifact.instance.shape
        local et, mt, rt = c_type(shape.elem_ty), c_type(shape.mapped_ty), c_type(shape.result_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = rt .. " " .. artifact.symbol.text .. "(const " .. et .. " *xs, int32_t start, int32_t stop, " .. rt .. " init) {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        " .. mt .. " mapped = " .. unary_expr(shape.op, "xs[i]", shape.mapped_ty) .. ";"
        lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", "mapped", shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. rt .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function zip_reduce_array_source(artifact)
        local shape = artifact.instance.shape
        local lt, rt, mt = c_type(shape.lhs_ty), c_type(shape.result_ty), c_type(shape.mapped_ty)
        local acc_ty = (shape.reduction == Value.ReductionMin or shape.reduction == Value.ReductionMax) and rt or unsigned_c_type(shape.result_ty)
        local stride = tonumber(shape.stride) or 1
        local lines = {}
        lines[#lines + 1] = rt .. " " .. artifact.symbol.text .. "(const " .. lt .. " *lhs, const " .. lt .. " *rhs, int32_t start, int32_t stop, " .. rt .. " init) {"
        lines[#lines + 1] = "    " .. acc_ty .. " acc = (" .. acc_ty .. ")init;"
        lines[#lines + 1] = "    for (int32_t i = start; i < stop; i += " .. tostring(stride) .. ") {"
        lines[#lines + 1] = "        " .. mt .. " mapped = " .. binary_expr(shape.op, "lhs[i]", "rhs[i]", shape.mapped_ty) .. ";"
        lines[#lines + 1] = "        acc = " .. reduction_update_expr(shape.reduction, "acc", "mapped", shape.result_ty) .. ";"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return (" .. rt .. ")acc;"
        lines[#lines + 1] = "}"
        return table.concat(lines, "\n")
    end

    local function artifact_source(artifact)
        local cls = pvm.classof(artifact.instance.shape)
        if cls == Stencil.StencilShapeReduceArray then return reduce_array_source(artifact) end
        if cls == Stencil.StencilShapeMapArray then return map_array_source(artifact) end
        if cls == Stencil.StencilShapeZipMapArray then return zip_map_array_source(artifact) end
        if cls == Stencil.StencilShapeScanArray then return scan_array_source(artifact) end
        if cls == Stencil.StencilShapeCopyArray then return copy_array_source(artifact) end
        if cls == Stencil.StencilShapeFillArray then return fill_array_source(artifact) end
        if cls == Stencil.StencilShapeFindArray then return find_array_source(artifact) end
        if cls == Stencil.StencilShapePartitionArray then return partition_array_source(artifact) end
        if cls == Stencil.StencilShapeCastArray then return cast_array_source(artifact) end
        if cls == Stencil.StencilShapeCompareArray then return compare_array_source(artifact) end
        if cls == Stencil.StencilShapeZipCompareArray then return zip_compare_array_source(artifact) end
        if cls == Stencil.StencilShapeGatherArray then return gather_array_source(artifact) end
        if cls == Stencil.StencilShapeScatterArray then return scatter_array_source(artifact) end
        if cls == Stencil.StencilShapeInPlaceMapArray then return in_place_map_array_source(artifact) end
        if cls == Stencil.StencilShapeCountArray then return count_array_source(artifact) end
        if cls == Stencil.StencilShapeMapReduceArray then return map_reduce_array_source(artifact) end
        if cls == Stencil.StencilShapeZipReduceArray then return zip_reduce_array_source(artifact) end
        error("stencil_c: unsupported stencil shape", 3)
    end

    function api.source(artifacts)
        local out = { "#include <stdint.h>", "#include <stddef.h>", "#include <string.h>", "typedef intptr_t ml_index;" }
        local seen = {}
        for _, artifact in ipairs(artifacts or {}) do
            local key = artifact.symbol.text
            if not seen[key] then
                out[#out + 1] = artifact_source(artifact)
                seen[key] = true
            end
        end
        return table.concat(out, "\n\n") .. "\n"
    end

    local function shell_quote(s)
        return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
    end

    local function write_file(path, source)
        local f = assert(io.open(path, "wb"))
        f:write(source)
        f:close()
    end

    function api.compile_artifacts(artifacts, opts)
        opts = opts or {}
        local ffi = require("ffi")
        local dir = opts.dir or "target/stencil"
        os.execute("mkdir -p " .. shell_quote(dir))
        local stem = opts.stem or ("moonlift_stencil_" .. tostring(os.time()) .. "_" .. sanitize(tostring(os.clock())))
        local c_path = dir .. "/" .. stem .. ".c"
        local so_path = dir .. "/" .. stem .. ".so"
        local source = api.source(artifacts)
        write_file(c_path, source)
        local cc = opts.cc or os.getenv("CC") or "gcc"
        local cflags = opts.cflags or "-std=c99 -O3 -march=native -fPIC -shared"
        local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(so_path) }, " ")
        local ok = os.execute(cmd)
        if not (ok == true or ok == 0) then return nil, "stencil_c: compile failed: " .. cmd, source end
        local decls = {}
        local seen = {}
        for _, artifact in ipairs(artifacts or {}) do
            if not seen[artifact.symbol.text] then
                decls[#decls + 1] = artifact.c_signature
                seen[artifact.symbol.text] = true
            end
        end
        if #decls > 0 then ffi.cdef(table.concat(decls, "\n")) end
        local lib = ffi.load(so_path)
        local symbols = {}
        for _, artifact in ipairs(artifacts or {}) do symbols[artifact.symbol.text] = lib[artifact.symbol.text] end
        return {
            c_path = c_path,
            so_path = so_path,
            source = source,
            command = cmd,
            lib = lib,
            symbols = symbols,
        }, nil, source
    end

    T._moonlift_api_cache.stencil_c = api
    return api
end

return bind_context
