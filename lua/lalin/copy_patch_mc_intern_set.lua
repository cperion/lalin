local function bind_context(T)
    local Core = T.LalinCore
    local Code = T.LalinCode
    local Ty = T.LalinType
    local Value = T.LalinValue
    local Stencil = T.LalinStencil
    local Plan = require("lalin.stencil_artifact_plan")(T)

    local M = {}

    local i32 = Code.CodeTyInt(32, Code.CodeSigned)
    local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
    local f64 = Code.CodeTyFloat(64)
    local bool8 = Code.CodeTyBool8
    local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
    local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
    local pair_soa_ty = Code.CodeTyNamed("Demo", "PairSoA", Ty.TNamed(Ty.TypeRefGlobal("Demo", "PairSoA")))

    local function iconst(raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw))))
    end

    local function u8const(raw)
        return Value.ValueExprConst(Code.CodeConstLiteral(u8, Core.LitInt(tostring(raw))))
    end

    local function pred(cmp, ty, value)
        return Stencil.StencilPredCompareConst(cmp, ty, value)
    end

    local function reduction(kind, init)
        return {
            kind = kind,
            init = iconst(init),
            int_semantics = sem,
            float_mode = nil,
        }
    end

    local function view_topology(name)
        return Stencil.StencilTopologyViewDescriptor(
            Code.CodeValueId("v:view:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name),
            Code.CodeValueId("v:stride:" .. name),
            nil
        )
    end

    local function slice_topology(name)
        return Stencil.StencilTopologySliceDescriptor(
            Code.CodeValueId("v:slice:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name)
        )
    end

    local function bytespan_topology(name)
        return Stencil.StencilTopologyByteSpanDescriptor(
            Code.CodeValueId("v:bytespan:" .. name),
            Code.CodeValueId("v:data:" .. name),
            Code.CodeValueId("v:len:" .. name)
        )
    end

    local function field_topology()
        return Stencil.StencilTopologyFieldProjection(
            Stencil.StencilTopologyContiguous(1),
            pair_ty,
            "right",
            4
        )
    end

    local function soa_component(field_name, component_index)
        return Stencil.StencilTopologySoAComponent(
            Stencil.StencilTopologyContiguous(1),
            pair_soa_ty,
            field_name,
            component_index
        )
    end

    local function append_all(out, xs)
        for _, x in ipairs(xs) do out[#out + 1] = x end
    end

    local function base_artifacts(topology_kind)
        local topo = topology_kind == "view" and view_topology or topology_kind == "slice" and slice_topology or nil
        local function top(name) return topo and topo(name) or nil end
        return {
            Plan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = top("reduce_xs") }),
            Plan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = top("map_dst"), src_topology = top("map_xs") }),
            Plan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = top("zip_map_dst"), lhs_topology = top("zip_map_lhs"), rhs_topology = top("zip_map_rhs") }),
            Plan.scan_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, dst_topology = top("scan_dst"), array_topology = top("scan_xs") }),
            Plan.copy_array_artifact({ elem_ty = i32, step_num = 1, dst_topology = top("copy_dst"), src_topology = top("copy_src") }),
            Plan.copy_array_artifact({ elem_ty = i32, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = top("copy_move_dst"), src_topology = top("copy_move_src") }),
            Plan.fill_array_artifact({ elem_ty = i32, value = iconst(7), step_num = 1, dst_topology = top("fill_dst") }),
            Plan.find_array_artifact(pred(Core.CmpEq, i32, iconst(5)), { elem_ty = i32, step_num = 1, array_topology = top("find_xs") }),
            Plan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, dst_topology = top("partition_dst"), array_topology = top("partition_xs") }),
            Plan.cast_array_artifact(Core.MachineCastSToF, { src_ty = i32, dst_ty = f64, step_num = 1, dst_topology = top("cast_dst"), src_topology = top("cast_xs") }),
            Plan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, result_ty = bool8, step_num = 1, dst_topology = top("compare_dst"), src_topology = top("compare_xs") }),
            Plan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = top("zip_compare_dst"), lhs_topology = top("zip_compare_lhs"), rhs_topology = top("zip_compare_rhs") }),
            Plan.gather_array_artifact({ elem_ty = i32, index_ty = i32, step_num = 1, dst_topology = top("gather_dst"), index_topology = top("gather_idx") }),
            Plan.scatter_array_artifact({ elem_ty = i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, src_topology = top("scatter_src"), index_topology = top("scatter_idx") }),
            Plan.in_place_map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, step_num = 1, src_topology = top("in_place_xs") }),
            Plan.count_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, array_topology = top("count_xs") }),
            Plan.map_reduce_array_artifact(Stencil.StencilUnaryNeg, reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, array_topology = top("map_reduce_xs") }),
            Plan.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, lhs_topology = top("zip_reduce_lhs"), rhs_topology = top("zip_reduce_rhs") }),
        }
    end

    function M.artifacts()
        local out = {}
        append_all(out, base_artifacts())
        append_all(out, base_artifacts("view"))
        append_all(out, base_artifacts("slice"))
        append_all(out, {
            Plan.copy_array_artifact({ elem_ty = u8, step_num = 1, dst_topology = bytespan_topology("copy_dst"), src_topology = bytespan_topology("copy_src") }),
            Plan.copy_array_artifact({ elem_ty = u8, semantics = Stencil.StencilCopyMemMove, step_num = 1, dst_topology = bytespan_topology("move_dst"), src_topology = bytespan_topology("move_src") }),
            Plan.fill_array_artifact({ elem_ty = u8, value = u8const(127), step_num = 1, dst_topology = bytespan_topology("fill_dst") }),
            Plan.find_array_artifact(pred(Core.CmpEq, u8, u8const(13)), { elem_ty = u8, step_num = 1, array_topology = bytespan_topology("find_xs") }),
            Plan.compare_array_artifact(pred(Core.CmpGt, u8, u8const(9)), { elem_ty = u8, result_ty = bool8, step_num = 1, dst_topology = bytespan_topology("compare_dst"), src_topology = bytespan_topology("compare_xs") }),
            Plan.count_array_artifact(pred(Core.CmpGt, u8, u8const(9)), { elem_ty = u8, step_num = 1, array_topology = bytespan_topology("count_xs") }),
            Plan.reduce_array_artifact(reduction(Value.ReductionAdd, 0), nil, { elem_ty = i32, result_ty = i32, step_num = 1, array_topology = field_topology() }),
            Plan.map_array_artifact(Stencil.StencilUnaryNeg, { elem_ty = i32, result_ty = i32, step_num = 1, src_topology = field_topology() }),
            Plan.find_array_artifact(pred(Core.CmpEq, i32, iconst(20)), { elem_ty = i32, step_num = 1, array_topology = field_topology() }),
            Plan.compare_array_artifact(pred(Core.CmpGt, i32, iconst(10)), { elem_ty = i32, result_ty = bool8, step_num = 1, src_topology = field_topology() }),
            Plan.fill_array_artifact({ elem_ty = i32, value = iconst(99), step_num = 1, dst_topology = field_topology() }),
            Plan.zip_map_array_artifact(Stencil.StencilBinaryAdd, { lhs_ty = i32, rhs_ty = i32, result_ty = i32, step_num = 1, dst_topology = soa_component("sum", 2), lhs_topology = soa_component("left", 0), rhs_topology = soa_component("right", 1) }),
            Plan.zip_reduce_array_artifact(Stencil.StencilBinaryAdd, reduction(Value.ReductionAdd, 0), nil, { lhs_ty = i32, rhs_ty = i32, mapped_ty = i32, result_ty = i32, step_num = 1, lhs_topology = soa_component("left", 0), rhs_topology = soa_component("right", 1) }),
            Plan.zip_compare_array_artifact(Core.CmpLt, { lhs_ty = i32, rhs_ty = i32, result_ty = bool8, step_num = 1, dst_topology = soa_component("lt", 2), lhs_topology = soa_component("left", 0), rhs_topology = soa_component("right", 1) }),
            Plan.partition_array_artifact(pred(Core.CmpGt, i32, iconst(0)), { elem_ty = i32, step_num = 1, dst_topology = soa_component("positive_then_rest", 1), array_topology = soa_component("left", 0) }),
        })
        return out
    end

    function M.preamble()
        return "typedef struct { int32_t left; int32_t right; } Demo_Pair;"
    end

    return M
end

return bind_context
