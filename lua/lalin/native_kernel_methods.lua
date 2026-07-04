local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_kernel_methods ~= nil then return T._lalin_api_cache.native_kernel_methods end

    require("lalin.native_code_methods")(T)

    local Native = T.LalinNative
    local Kernel = T.LalinKernel
    local Code = T.LalinCode
    local Flow = T.LalinFlow
    local Value = T.LalinValue
    local Stencil = T.LalinStencil
    local Effect = T.LalinEffect
    local Mem = T.LalinMem
    local Support = require("lalin.native_template_support")(T)
    local api = {}

    local function internal_error(message)
        error("lalin.native_kernel_methods: " .. message, 3)
    end

    local function template_value_id(text)
        return Native.NativeTemplateValueId("native.kernel." .. text)
    end

    local function storage_for_type(ty, target, type_layouts)
        return ty:native_storage_layout(target, type_layouts)
    end

    local function storage_for_scalar(scalar)
        return Native.NativeStorageLayout(Native.NativeScalarValueRepresentation(scalar), scalar:native_size_bytes(), scalar:native_frame_alignment())
    end

    local function frame_entry(role, storage, text)
        return Native.NativeKernelFrameEntry(role, storage, template_value_id(text))
    end

    local function value_source_shape_for_storage(storage)
        local representation = storage and storage.representation
        if asdl.isa(representation, Native.NativeScalarValueRepresentation) then return Native.NativeKernelValueScalarShape(representation.scalar) end
        if asdl.isa(representation, Native.NativeAddressValueRepresentation) then return Native.NativeKernelValuePointerShape(representation.address_scalar) end
        if asdl.isa(representation, Native.NativeOpaquePointerValueRepresentation) then return Native.NativeKernelValuePointerShape(representation.address_scalar) end
        if asdl.isa(representation, Native.NativeUntypedPointerValueRepresentation) then return Native.NativeKernelValuePointerShape(representation.address_scalar) end
        return Native.NativeKernelValueBytesShape(storage and storage.size or 0, storage and storage.alignment or 1)
    end

    local function value_source_shape_for_type(ty, target, type_layouts)
        return value_source_shape_for_storage(storage_for_type(ty, target, type_layouts))
    end

    function Flow.FlowTripCount:native_kernel_trip_count_value()
        return nil
    end

    function Flow.FlowTripCountExact:native_kernel_trip_count_value()
        return self.count
    end

    function Flow.FlowTripCountNonNegative:native_kernel_trip_count_value()
        return self.count
    end

    function Flow.FlowTripCountUnknown:native_kernel_trip_count_value()
        return nil
    end

    function Flow.FlowTripCount:native_kernel_trip_count_source_shape()
        return Native.NativeKernelTripUnknownShape
    end

    function Flow.FlowTripCountExact:native_kernel_trip_count_source_shape()
        return Native.NativeKernelTripDynamicExactShape
    end

    function Flow.FlowTripCountNonNegative:native_kernel_trip_count_source_shape()
        return Native.NativeKernelTripDynamicNonNegativeShape
    end

    function Flow.FlowTripCountUnknown:native_kernel_trip_count_source_shape()
        return Native.NativeKernelTripUnknownShape
    end

    function Kernel.KernelDomain:native_kernel_loop_projection(_target)
        internal_error("kernel domain has no native loop projection")
    end

    function Kernel.KernelDomainFlow:native_kernel_loop_projection(target)
        return Native.NativeKernelLoopProjection(
            self,
            self.trip_count,
            self.counter,
            Support.scalar_index(target.pointer_bits),
            self.trip_count:native_kernel_trip_count_value()
        )
    end

    function Kernel.KernelDomainFlow:native_kernel_axis(target)
        return Native.NativeKernelDomainProjectionAxis(self:native_kernel_loop_projection(target))
    end

    function Native.NativeKernelLoopProjection:native_kernel_loop_source_shape()
        return Native.NativeKernelLoopRange1DShape(self.index_scalar, self.trip_count:native_kernel_trip_count_source_shape(), self.counter ~= nil)
    end

    function Native.NativeKernelLoopProjection:native_kernel_source_axis()
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelDomainOpShape(self:native_kernel_loop_source_shape()))
    end

    function Kernel.KernelLane:native_kernel_lane_projection(target, type_layouts)
        return Native.NativeKernelLaneProjection(
            self,
            storage_for_type(self.elem_ty, target, type_layouts),
            Support.scalar_pointer(target.pointer_bits),
            Support.scalar_index(target.pointer_bits)
        )
    end

    function Kernel.KernelLane:native_kernel_axis(target, type_layouts)
        return Native.NativeKernelLaneProjectionAxis(self:native_kernel_lane_projection(target, type_layouts))
    end

    function Mem.MemAccessPattern:native_kernel_lane_address_source_shape(lane)
        return Native.NativeKernelLaneIndexedAddressShape(value_source_shape_for_storage(lane.elem_storage), lane.address_scalar, lane.index_scalar)
    end

    function Mem.MemAccessScalar:native_kernel_lane_address_source_shape(lane)
        return Native.NativeKernelLaneScalarAddressShape(value_source_shape_for_storage(lane.elem_storage), lane.address_scalar, lane.index_scalar)
    end

    function Mem.MemAccessContiguous:native_kernel_lane_address_source_shape(lane)
        return Native.NativeKernelLaneContiguousAddressShape(value_source_shape_for_storage(lane.elem_storage), lane.address_scalar, lane.index_scalar)
    end

    function Mem.MemAccessStrided:native_kernel_lane_address_source_shape(lane)
        return Native.NativeKernelLaneStridedAddressShape(value_source_shape_for_storage(lane.elem_storage), lane.address_scalar, lane.index_scalar)
    end

    function Native.NativeKernelLaneProjection:native_kernel_lane_address_source_shape()
        return self.lane.pattern:native_kernel_lane_address_source_shape(self)
    end

    function Native.NativeKernelLaneProjection:native_kernel_source_axis()
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelLaneOpShape(self:native_kernel_lane_address_source_shape()))
    end

    local function code_value_type_entry(value, ty, target, type_layouts)
        return Native.NativeKernelCodeValueTypeProjection(value, ty, storage_for_type(ty, target, type_layouts))
    end

    local function kernel_value_type_entry(value, ty, target, type_layouts)
        return Native.NativeKernelKernelValueTypeProjection(value, ty, storage_for_type(ty, target, type_layouts))
    end

    function Value.ValueExpr:native_kernel_value_expr_source_shape(ty, target, type_layouts)
        return Native.NativeKernelExprKernelValueShape(value_source_shape_for_type(ty, target, type_layouts))
    end

    function Value.ValueExprConst:native_kernel_value_expr_source_shape(ty, target, type_layouts)
        return Native.NativeKernelExprConstShape(value_source_shape_for_type(ty or self.const.ty, target, type_layouts))
    end

    function Value.ValueExprValue:native_kernel_value_expr_source_shape(ty, target, type_layouts)
        return Native.NativeKernelExprCodeValueShape(value_source_shape_for_type(ty, target, type_layouts))
    end

    function Value.ValueExprAffine:native_kernel_value_expr_source_shape(_ty, target, type_layouts)
        return Native.NativeKernelExprAffineShape(value_source_shape_for_type(self.affine.ty, target, type_layouts), #(self.affine.terms or {}))
    end

    function Value.ValueExprUnary:native_kernel_value_expr_source_shape(_ty, target, type_layouts)
        return Native.NativeKernelExprUnaryShape(self.op, value_source_shape_for_type(self.ty, target, type_layouts))
    end

    function Value.ValueExprCast:native_kernel_value_expr_source_shape(_ty, target, type_layouts)
        return Native.NativeKernelExprCastShape(self.op, value_source_shape_for_type(self.from, target, type_layouts), value_source_shape_for_type(self.to, target, type_layouts))
    end

    function Value.ValueExprBinary:native_kernel_value_expr_source_shape(_ty, target, type_layouts)
        return Native.NativeKernelExprBinaryShape(self.op, value_source_shape_for_type(self.ty, target, type_layouts))
    end

    function Value.ValueExprAdd:native_kernel_value_expr_source_shape(_ty, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinAdd, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprSub:native_kernel_value_expr_source_shape(_ty, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinSub, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprMul:native_kernel_value_expr_source_shape(_ty, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinMul, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprDiv:native_kernel_value_expr_source_shape(_ty, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinDiv, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprRem:native_kernel_value_expr_source_shape(_ty, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinRem, value_source_shape_for_type(self.ty, target, type_layouts)) end

    function Value.ValueExprCmp:native_kernel_value_expr_source_shape(_ty, target, type_layouts)
        return Native.NativeKernelExprCompareShape(self.op, value_source_shape_for_type(self.ty, target, type_layouts))
    end

    function Value.ValueExprSelect:native_kernel_value_expr_source_shape(ty, target, type_layouts)
        return Native.NativeKernelExprSelectShape(value_source_shape_for_type(ty, target, type_layouts))
    end

    function Kernel.KernelExpr:native_kernel_expr_projection(_ty, _target, _type_layouts)
        internal_error("kernel expression leaf has no native projection")
    end

    function Kernel.KernelExprValue:native_kernel_expr_projection(ty, target, type_layouts)
        if ty == nil then internal_error("KernelExprValue native projection requires an owner-provided CodeType") end
        return Native.NativeKernelExprCodeValueProjection(self.value, storage_for_type(ty, target, type_layouts))
    end

    function Kernel.KernelExprAlgebra:native_kernel_expr_projection(ty, target, type_layouts)
        if ty == nil then internal_error("KernelExprAlgebra native projection requires an owner-provided CodeType") end
        return Native.NativeKernelExprAlgebraProjection(self.expr, storage_for_type(ty, target, type_layouts))
    end

    function Kernel.KernelExprLaneLoad:native_kernel_expr_projection(_ty, target, type_layouts)
        return Native.NativeKernelExprLaneLoadProjection(self.lane:native_kernel_lane_projection(target, type_layouts), self.index)
    end

    function Kernel.KernelExprKernelValue:native_kernel_expr_projection(ty, target, type_layouts)
        if ty == nil then internal_error("KernelExprKernelValue native projection requires an owner-provided CodeType") end
        return Native.NativeKernelExprKernelValueProjection(self.value, storage_for_type(ty, target, type_layouts))
    end

    function Kernel.KernelExpr:native_kernel_axis(ty, target, type_layouts)
        return Native.NativeKernelExprProjectionAxis(self:native_kernel_expr_projection(ty, target, type_layouts))
    end

    function Native.NativeKernelExprProjection:native_kernel_value_expr_source_shape(_target, _type_layouts)
        internal_error("kernel expression projection has no source shape")
    end

    function Native.NativeKernelExprCodeValueProjection:native_kernel_value_expr_source_shape(_target, _type_layouts)
        return Native.NativeKernelExprCodeValueShape(value_source_shape_for_storage(self.storage))
    end

    function Native.NativeKernelExprAlgebraProjection:native_kernel_value_expr_source_shape(target, type_layouts)
        return self.expr:native_kernel_value_expr_source_shape_for_storage(self.storage, target, type_layouts)
    end

    function Native.NativeKernelExprLaneLoadProjection:native_kernel_value_expr_source_shape(_target, _type_layouts)
        return Native.NativeKernelExprLaneLoadShape(self.lane:native_kernel_lane_address_source_shape())
    end

    function Native.NativeKernelExprKernelValueProjection:native_kernel_value_expr_source_shape(_target, _type_layouts)
        return Native.NativeKernelExprKernelValueShape(value_source_shape_for_storage(self.storage))
    end

    function Native.NativeKernelExprProjection:native_kernel_source_axis(target, type_layouts)
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelExprOpShape(self:native_kernel_value_expr_source_shape(target, type_layouts)))
    end

    function Kernel.KernelBinding:native_kernel_binding_projection(target, type_layouts)
        local storage = storage_for_type(self.ty, target, type_layouts)
        return Native.NativeKernelBindingProjection(
            self,
            storage,
            self.expr:native_kernel_expr_projection(self.ty, target, type_layouts),
            frame_entry(Native.NativeKernelFrameKernelValue(self.id), storage, "value." .. self.id.text)
        )
    end

    function Stencil.StencilPredicate:native_kernel_predicate_source_shape(_target, _type_layouts)
        return Native.NativeKernelPredicateNonZeroShape
    end

    function Stencil.StencilPredNonZero:native_kernel_predicate_source_shape(_target, _type_layouts)
        return Native.NativeKernelPredicateNonZeroShape
    end

    function Stencil.StencilPredCompareConst:native_kernel_predicate_source_shape(target, type_layouts)
        return Native.NativeKernelPredicateCompareConstShape(self.cmp, value_source_shape_for_type(self.operand_ty, target, type_layouts))
    end

    function Stencil.StencilPredRange:native_kernel_predicate_source_shape(target, type_layouts)
        return Native.NativeKernelPredicateRangeShape(value_source_shape_for_type(self.operand_ty, target, type_layouts))
    end

    function Stencil.StencilPredAnd:native_kernel_predicate_source_shape(_target, _type_layouts) return Native.NativeKernelPredicateLogicalShape(#(self.terms or {})) end
    function Stencil.StencilPredOr:native_kernel_predicate_source_shape(_target, _type_layouts) return Native.NativeKernelPredicateLogicalShape(#(self.terms or {})) end
    function Stencil.StencilPredNot:native_kernel_predicate_source_shape(_target, _type_layouts) return Native.NativeKernelPredicateLogicalShape(1) end
    function Stencil.StencilPredIsNaN:native_kernel_predicate_source_shape(target, type_layouts) return Native.NativeKernelPredicateFloatClassShape(value_source_shape_for_type(self.operand_ty, target, type_layouts)) end
    function Stencil.StencilPredIsInf:native_kernel_predicate_source_shape(target, type_layouts) return Native.NativeKernelPredicateFloatClassShape(value_source_shape_for_type(self.operand_ty, target, type_layouts)) end
    function Stencil.StencilPredIsFinite:native_kernel_predicate_source_shape(target, type_layouts) return Native.NativeKernelPredicateFloatClassShape(value_source_shape_for_type(self.operand_ty, target, type_layouts)) end

    function Value.ReductionFact:native_kernel_reducer_source_shape(target, type_layouts)
        return Native.NativeKernelReducerSourceShape(self.op, value_source_shape_for_type(self.ty, target, type_layouts))
    end

    function Stencil.StencilReducer:native_kernel_reducer_source_shape(target, type_layouts)
        return Native.NativeKernelReducerSourceShape(self.reduction, value_source_shape_for_type(self.result_ty, target, type_layouts))
    end

    function Effect.CallSummary:native_kernel_call_source_shape()
        if self.callee ~= nil then return Native.NativeKernelCallInternalShape end
        if self.extern_name ~= nil then return Native.NativeKernelCallExternShape end
        return Native.NativeKernelCallEffectOnlyShape(#(self.effects or {}))
    end

    function Kernel.KernelEffect:native_kernel_effect_projection(_target, _type_layouts)
        internal_error("kernel effect leaf has no native projection")
    end

    function Kernel.KernelEffectStore:native_kernel_effect_projection(target, type_layouts)
        return Native.NativeKernelEffectStoreProjection(
            self.dst:native_kernel_lane_projection(target, type_layouts),
            self.index,
            self.value:native_kernel_expr_projection(self.dst.elem_ty, target, type_layouts),
            Native.NativeKernelEffectNoState
        )
    end

    function Kernel.KernelEffectScan:native_kernel_effect_projection(target, type_layouts)
        return Native.NativeKernelEffectScanProjection(
            self.dst:native_kernel_lane_projection(target, type_layouts),
            self.index,
            self.reduction,
            self.mode,
            Native.NativeKernelEffectScanState(self.reduction, self.mode, storage_for_type(self.reduction.ty, target, type_layouts))
        )
    end

    function Kernel.KernelEffectPartition:native_kernel_effect_projection(target, type_layouts)
        return Native.NativeKernelEffectPartitionProjection(
            self.dst:native_kernel_lane_projection(target, type_layouts),
            self.src:native_kernel_expr_projection(self.dst.elem_ty, target, type_layouts),
            self.pred,
            self.semantics,
            Native.NativeKernelEffectScratchState(storage_for_type(self.dst.elem_ty, target, type_layouts))
        )
    end

    function Kernel.KernelEffectCopy:native_kernel_effect_projection(target, type_layouts)
        return Native.NativeKernelEffectCopyProjection(
            self.dst:native_kernel_lane_projection(target, type_layouts),
            self.src:native_kernel_expr_projection(self.dst.elem_ty, target, type_layouts),
            self.semantics,
            Native.NativeKernelEffectNoState
        )
    end

    function Kernel.KernelEffectScatterReduce:native_kernel_effect_projection(target, type_layouts)
        return Native.NativeKernelEffectScatterReduceProjection(
            self.dst:native_kernel_lane_projection(target, type_layouts),
            self.index,
            self.value:native_kernel_expr_projection(self.dst.elem_ty, target, type_layouts),
            self.reducer,
            Native.NativeKernelEffectScratchState(storage_for_type(self.dst.elem_ty, target, type_layouts))
        )
    end

    function Kernel.KernelEffectFold:native_kernel_effect_projection(target, type_layouts)
        return Native.NativeKernelEffectFoldProjection(
            self.reduction,
            Native.NativeKernelEffectReductionState(self.reduction, storage_for_type(self.reduction.ty, target, type_layouts))
        )
    end

    function Kernel.KernelEffectCall:native_kernel_effect_projection(_target, _type_layouts)
        return Native.NativeKernelEffectCallProjection(self.call, Native.NativeKernelEffectNoState)
    end

    function Kernel.KernelEffect:native_kernel_axis(target, type_layouts)
        return Native.NativeKernelEffectProjectionAxis(self:native_kernel_effect_projection(target, type_layouts))
    end

    function Native.NativeKernelEffectProjection:native_kernel_effect_source_shape(_target, _type_layouts)
        internal_error("kernel effect projection has no source shape")
    end

    function Native.NativeKernelEffectStoreProjection:native_kernel_effect_source_shape(target, type_layouts)
        return Native.NativeKernelEffectStoreShape(self.dst:native_kernel_lane_address_source_shape(), self.value:native_kernel_value_expr_source_shape(target, type_layouts))
    end

    function Native.NativeKernelEffectScanProjection:native_kernel_effect_source_shape(target, type_layouts)
        return Native.NativeKernelEffectScanShape(self.dst:native_kernel_lane_address_source_shape(), self.reduction:native_kernel_reducer_source_shape(target, type_layouts), self.mode)
    end

    function Native.NativeKernelEffectPartitionProjection:native_kernel_effect_source_shape(target, type_layouts)
        return Native.NativeKernelEffectPartitionShape(self.dst:native_kernel_lane_address_source_shape(), self.src:native_kernel_value_expr_source_shape(target, type_layouts), self.pred:native_kernel_predicate_source_shape(target, type_layouts), self.semantics)
    end

    function Native.NativeKernelEffectCopyProjection:native_kernel_effect_source_shape(target, type_layouts)
        return Native.NativeKernelEffectCopyShape(self.dst:native_kernel_lane_address_source_shape(), self.src:native_kernel_value_expr_source_shape(target, type_layouts), self.semantics)
    end

    function Native.NativeKernelEffectScatterReduceProjection:native_kernel_effect_source_shape(target, type_layouts)
        return Native.NativeKernelEffectScatterReduceShape(self.dst:native_kernel_lane_address_source_shape(), self.value:native_kernel_value_expr_source_shape(target, type_layouts), self.reducer:native_kernel_reducer_source_shape(target, type_layouts))
    end

    function Native.NativeKernelEffectFoldProjection:native_kernel_effect_source_shape(target, type_layouts)
        return Native.NativeKernelEffectFoldShape(self.reduction:native_kernel_reducer_source_shape(target, type_layouts))
    end

    function Native.NativeKernelEffectCallProjection:native_kernel_effect_source_shape(_target, _type_layouts)
        return Native.NativeKernelEffectCallShape(self.call:native_kernel_call_source_shape())
    end

    function Native.NativeKernelEffectProjection:native_kernel_source_axis(target, type_layouts)
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelEffectOpShape(self:native_kernel_effect_source_shape(target, type_layouts)))
    end

    function Kernel.KernelResult:native_kernel_result_projection(_result_ty, _target, _type_layouts)
        internal_error("kernel result leaf has no native projection")
    end

    function Kernel.KernelResultVoid:native_kernel_result_projection(_result_ty, _target, _type_layouts)
        return Native.NativeKernelResultVoidProjection
    end

    function Kernel.KernelResultValue:native_kernel_result_projection(result_ty, target, type_layouts)
        if result_ty == nil then internal_error("KernelResultValue native projection requires an owner-provided result CodeType") end
        return Native.NativeKernelResultValueProjection(self.expr:native_kernel_expr_projection(result_ty, target, type_layouts))
    end

    function Kernel.KernelResultFind:native_kernel_result_projection(result_ty, target, type_layouts)
        if result_ty == nil then internal_error("KernelResultFind native projection requires an owner-provided result CodeType") end
        return Native.NativeKernelResultFindProjection(self.src:native_kernel_expr_projection(result_ty, target, type_layouts), self.pred, self.not_found)
    end

    function Kernel.KernelResultReduction:native_kernel_result_projection(_result_ty, target, type_layouts)
        return Native.NativeKernelResultReductionProjection(
            self.reduction,
            Native.NativeKernelEffectReductionState(self.reduction, storage_for_type(self.reduction.ty, target, type_layouts))
        )
    end

    function Kernel.KernelResultClosedForm:native_kernel_result_projection(_result_ty, _target, _type_layouts)
        return Native.NativeKernelResultClosedFormProjection(self.closed_form)
    end

    function Kernel.KernelResultOriginalControl:native_kernel_result_projection(_result_ty, _target, _type_layouts)
        return Native.NativeKernelResultOriginalControlProjection(self.reason)
    end

    function Kernel.KernelResult:native_kernel_axis(result_ty, target, type_layouts)
        return Native.NativeKernelResultProjectionAxis(self:native_kernel_result_projection(result_ty, target, type_layouts))
    end

    function Native.NativeKernelResultProjection:native_kernel_result_source_shape(_target, _type_layouts)
        internal_error("kernel result projection has no source shape")
    end

    function Native.NativeKernelResultVoidProjection:native_kernel_result_source_shape(_target, _type_layouts)
        return Native.NativeKernelResultVoidShape
    end

    function Native.NativeKernelResultValueProjection:native_kernel_result_source_shape(target, type_layouts)
        return Native.NativeKernelResultValueShape(self.expr:native_kernel_value_expr_source_shape(target, type_layouts))
    end

    function Native.NativeKernelResultFindProjection:native_kernel_result_source_shape(target, type_layouts)
        return Native.NativeKernelResultFindShape(self.src:native_kernel_value_expr_source_shape(target, type_layouts), self.pred:native_kernel_predicate_source_shape(target, type_layouts))
    end

    function Native.NativeKernelResultReductionProjection:native_kernel_result_source_shape(target, type_layouts)
        return Native.NativeKernelResultReductionShape(self.reduction:native_kernel_reducer_source_shape(target, type_layouts))
    end

    function Native.NativeKernelResultClosedFormProjection:native_kernel_result_source_shape(target, type_layouts)
        return Native.NativeKernelResultClosedFormShape(value_source_shape_for_type(self.closed_form.reduction.ty, target, type_layouts))
    end

    function Native.NativeKernelResultOriginalControlProjection:native_kernel_result_source_shape(_target, _type_layouts)
        return Native.NativeKernelResultOriginalControlShape
    end

    function Native.NativeKernelResultProjection:native_kernel_source_axis(target, type_layouts)
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelResultOpShape(self:native_kernel_result_source_shape(target, type_layouts)))
    end

    function Kernel.KernelProof:native_kernel_proof_projection()
        internal_error("kernel proof leaf has no native projection")
    end

    function Kernel.KernelProofFlow:native_kernel_proof_projection()
        return Native.NativeKernelProofFlowProjection(self.domain)
    end

    function Kernel.KernelProofValue:native_kernel_proof_projection()
        return Native.NativeKernelProofValueProjection(self.proof)
    end

    function Kernel.KernelProofMemory:native_kernel_proof_projection()
        return Native.NativeKernelProofMemoryProjection(self.proof)
    end

    function Kernel.KernelProofEffect:native_kernel_proof_projection()
        return Native.NativeKernelProofEffectProjection(self.effect)
    end

    function Kernel.KernelProofFunctionEquivalence:native_kernel_proof_projection()
        return Native.NativeKernelProofFunctionEquivalenceProjection
    end

    function Kernel.KernelProof:native_kernel_axis()
        return Native.NativeKernelProofProjectionAxis(self:native_kernel_proof_projection())
    end

    function Native.NativeKernelProofProjection:native_kernel_proof_source_shape()
        return Native.NativeKernelProofFunctionEquivalenceShape
    end

    function Native.NativeKernelProofFlowProjection:native_kernel_proof_source_shape() return Native.NativeKernelProofFlowShape end
    function Native.NativeKernelProofValueProjection:native_kernel_proof_source_shape() return Native.NativeKernelProofValueShape end
    function Native.NativeKernelProofMemoryProjection:native_kernel_proof_source_shape() return Native.NativeKernelProofMemoryShape end
    function Native.NativeKernelProofEffectProjection:native_kernel_proof_source_shape() return Native.NativeKernelProofEffectShape end
    function Native.NativeKernelProofFunctionEquivalenceProjection:native_kernel_proof_source_shape() return Native.NativeKernelProofFunctionEquivalenceShape end

    function Native.NativeKernelProofProjection:native_kernel_source_axis()
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelProofOpShape(self:native_kernel_proof_source_shape()))
    end

    function Kernel.KernelEquivalence:native_kernel_proof_projections()
        return {}
    end

    function Kernel.KernelEquivalenceProof:native_kernel_proof_projections()
        local out = {}
        for _, proof in ipairs(self.proofs or {}) do out[#out + 1] = proof:native_kernel_proof_projection() end
        return out
    end

    function Kernel.KernelEquivalenceRejected:native_kernel_proof_projections()
        return {}
    end

    local function value_environment_for_body(body, target, type_layouts)
        local entries = {}
        for _, binding in ipairs(body.bindings or {}) do
            entries[#entries + 1] = kernel_value_type_entry(binding.id, binding.ty, target, type_layouts)
        end
        for _, lane in ipairs(body.lanes or {}) do
            for _, access in ipairs(lane.accesses or {}) do
                if access.value ~= nil and access.ty ~= nil then
                    entries[#entries + 1] = code_value_type_entry(access.value, access.ty, target, type_layouts)
                end
            end
        end
        return Native.NativeKernelValueEnvironmentProjection(entries)
    end

    function Kernel.KernelBody:native_kernel_body_projection(target, type_layouts, result_ty)
        local lanes = {}
        local bindings = {}
        local effects = {}
        local frame = {}
        local domain_projection = self.domain:native_kernel_loop_projection(target)
        frame[#frame + 1] = frame_entry(Native.NativeKernelFrameDomainCounter, storage_for_scalar(domain_projection.index_scalar), "domain.counter")
        if domain_projection.trip_count_value ~= nil then
            frame[#frame + 1] = frame_entry(Native.NativeKernelFrameTripCount, storage_for_scalar(domain_projection.index_scalar), "domain.trip_count")
        end
        for _, lane in ipairs(self.lanes or {}) do
            local lane_projection = lane:native_kernel_lane_projection(target, type_layouts)
            lanes[#lanes + 1] = lane_projection
            frame[#frame + 1] = frame_entry(Native.NativeKernelFrameLaneBase(lane.id), storage_for_scalar(lane_projection.address_scalar), "lane." .. lane.id.text .. ".base")
            frame[#frame + 1] = frame_entry(Native.NativeKernelFrameLaneStride(lane.id), storage_for_scalar(lane_projection.index_scalar), "lane." .. lane.id.text .. ".stride")
            frame[#frame + 1] = frame_entry(Native.NativeKernelFrameLaneAddress(lane.id), storage_for_scalar(lane_projection.address_scalar), "lane." .. lane.id.text .. ".address")
        end
        for _, binding in ipairs(self.bindings or {}) do
            local projection = binding:native_kernel_binding_projection(target, type_layouts)
            bindings[#bindings + 1] = projection
            frame[#frame + 1] = projection.frame
        end
        for i, effect in ipairs(self.effects or {}) do
            local projection = effect:native_kernel_effect_projection(target, type_layouts)
            effects[#effects + 1] = projection
            local state = projection.state
            if state ~= nil and not rawequal(state, Native.NativeKernelEffectNoState) then
                local storage = state.storage
                if storage ~= nil then frame[#frame + 1] = frame_entry(Native.NativeKernelFrameEffectState(i - 1), storage, "effect." .. tostring(i - 1)) end
            end
        end
        if result_ty ~= nil then
            frame[#frame + 1] = frame_entry(Native.NativeKernelFrameResult, storage_for_type(result_ty, target, type_layouts), "result")
        end
        return Native.NativeKernelBodyProjection(
            self,
            domain_projection,
            lanes,
            bindings,
            value_environment_for_body(self, target, type_layouts),
            effects,
            self.result:native_kernel_result_projection(result_ty, target, type_layouts),
            self.equivalence:native_kernel_proof_projections(),
            frame
        )
    end

    function Kernel.KernelBody:native_kernel_axis(target, type_layouts, result_ty)
        return Native.NativeKernelBodyProjectionAxis(self:native_kernel_body_projection(target, type_layouts, result_ty))
    end

    function Native.NativeKernelBodyProjection:native_kernel_body_source_shape(target, type_layouts)
        return Native.NativeKernelBodySourceShape(
            self.domain:native_kernel_loop_source_shape(),
            #(self.lanes or {}),
            #(self.bindings or {}),
            #(self.effects or {}),
            self.result:native_kernel_result_source_shape(target, type_layouts)
        )
    end

    function Native.NativeKernelBodyProjection:native_kernel_source_axis(target, type_layouts)
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelBodyOpShape(self:native_kernel_body_source_shape(target, type_layouts)))
    end

    function Kernel.KernelPlan:native_kernel_plan_projection(_target, _type_layouts, _result_ty)
        internal_error("kernel plan leaf has no native projection")
    end

    function Kernel.KernelNoPlan:native_kernel_plan_projection(_target, _type_layouts, _result_ty)
        return Native.NativeKernelNoPlanProjection(self)
    end

    function Kernel.KernelPlanned:native_kernel_plan_projection(target, type_layouts, result_ty)
        return Native.NativeKernelPlannedProjection(self, self.body:native_kernel_body_projection(target, type_layouts, result_ty))
    end

    function Kernel.KernelPlan:native_kernel_axis(target, type_layouts, result_ty)
        return Native.NativeKernelPlanProjectionAxis(self:native_kernel_plan_projection(target, type_layouts, result_ty))
    end

    local function align_up(offset, alignment)
        if alignment <= 1 then return offset end
        local rem = offset % alignment
        if rem == 0 then return offset end
        return offset + (alignment - rem)
    end

    local function kernel_frame_slot_id(entry)
        local role = entry.role
        local text = entry.template_value.text
        return Native.NativeFrameSlotId("native.kernel.frame." .. text)
    end

    local function native_kernel_frame_layout(frame_entries)
        local slots = {}
        local entries = {}
        local seen = {}
        local offset = 0
        for _, entry in ipairs(frame_entries or {}) do
            local key = entry.template_value.text
            if seen[key] == nil then
                seen[key] = true
                offset = align_up(offset, entry.storage.alignment)
                local slot = Native.NativeFrameSlot(kernel_frame_slot_id(entry), entry.storage.representation, offset, entry.storage.size, entry.storage.alignment)
                slots[#slots + 1] = slot
                entries[#entries + 1] = Native.NativeKernelFrameSlotEntry(entry, slot)
                offset = offset + entry.storage.size
            end
        end
        return Native.NativeKernelFrameLayout(entries, Native.NativeFrameLayout(slots, align_up(offset, 16), 16))
    end

    local function frame_entry_for_kernel_value(frame_entries, value)
        for _, entry in ipairs(frame_entries or {}) do
            if asdl.isa(entry.role, Native.NativeKernelFrameKernelValue) and entry.role.value == value then return entry end
        end
    end

    local function native_kernel_inputs_from_projection(body_projection)
        local code_inputs = {}
        local kernel_inputs = {}
        for _, value in ipairs((body_projection.value_environment and body_projection.value_environment.entries) or {}) do
            if asdl.isa(value, Native.NativeKernelCodeValueTypeProjection) then
                local frame = frame_entry(Native.NativeKernelFrameCodeValue(value.value), value.storage, "code_value." .. value.value.text)
                code_inputs[#code_inputs + 1] = Native.NativeKernelCodeValueInputEntry(value.value, value.ty, value.storage, frame)
            elseif asdl.isa(value, Native.NativeKernelKernelValueTypeProjection) then
                local frame = frame_entry_for_kernel_value(body_projection.frame, value.value) or frame_entry(Native.NativeKernelFrameKernelValue(value.value), value.storage, "value." .. value.value.text)
                kernel_inputs[#kernel_inputs + 1] = Native.NativeKernelKernelValueInputEntry(value.value, value.ty, value.storage, frame)
            end
        end
        return code_inputs, kernel_inputs
    end

    local function native_kernel_lane_address_entries(body_projection)
        local out = {}
        for _, lane in ipairs(body_projection.lanes or {}) do
            local base = frame_entry(Native.NativeKernelFrameLaneBase(lane.lane.id), storage_for_scalar(lane.address_scalar), "lane." .. lane.lane.id.text .. ".base")
            local stride = frame_entry(Native.NativeKernelFrameLaneStride(lane.lane.id), storage_for_scalar(lane.index_scalar), "lane." .. lane.lane.id.text .. ".stride")
            local address = frame_entry(Native.NativeKernelFrameLaneAddress(lane.lane.id), storage_for_scalar(lane.address_scalar), "lane." .. lane.lane.id.text .. ".address")
            out[#out + 1] = Native.NativeKernelLaneAddressEntry(lane.lane.id, base, stride, address)
        end
        return out
    end

    function Effect.CallSummary:native_kernel_call_target_entry(capability)
        return Native.NativeKernelCallTargetEntry(self, capability or Native.NativeKernelCallEffectOnlyTarget(self.effects or {}))
    end

    function Kernel.KernelPlanned:native_kernel_lowering_input(target, type_layouts, result_ty, addresses, calls)
        local body_projection = self.body:native_kernel_body_projection(target, type_layouts, result_ty)
        local code_inputs, kernel_inputs = native_kernel_inputs_from_projection(body_projection)
        local frame_entries = {}
        for _, entry in ipairs(body_projection.frame or {}) do frame_entries[#frame_entries + 1] = entry end
        for _, input in ipairs(code_inputs or {}) do frame_entries[#frame_entries + 1] = input.frame end
        for _, input in ipairs(kernel_inputs or {}) do frame_entries[#frame_entries + 1] = input.frame end
        for _, lane in ipairs(native_kernel_lane_address_entries(body_projection)) do
            frame_entries[#frame_entries + 1] = lane.base
            if lane.stride ~= nil then frame_entries[#frame_entries + 1] = lane.stride end
            frame_entries[#frame_entries + 1] = lane.address
        end
        return Native.NativeKernelLoweringInput(
            self,
            result_ty,
            type_layouts,
            body_projection.value_environment,
            code_inputs,
            kernel_inputs,
            native_kernel_lane_address_entries(body_projection),
            native_kernel_frame_layout(frame_entries),
            calls or {},
            addresses or Native.NativeModuleAddressPlan({}, {}, {}, {}, {}, {})
        )
    end

    function Native.NativeKernelPlanProjection:native_kernel_plan_source_shape(_target, _type_layouts)
        return Native.NativeKernelNoPlanSourceShape
    end

    function Native.NativeKernelNoPlanProjection:native_kernel_plan_source_shape(_target, _type_layouts)
        return Native.NativeKernelNoPlanSourceShape
    end

    function Native.NativeKernelPlannedProjection:native_kernel_plan_source_shape(target, type_layouts)
        return Native.NativeKernelPlannedSourceShape(self.body:native_kernel_body_source_shape(target, type_layouts))
    end

    function Native.NativeKernelPlanProjection:native_kernel_source_axis(target, type_layouts)
        return Native.NativeKernelSourceShapeAxis(Native.NativeKernelPlanOpShape(self:native_kernel_plan_source_shape(target, type_layouts)))
    end

    function Native.NativeKernelFrameRole:native_kernel_frame_role_key()
        internal_error("kernel frame role has no key")
    end

    function Native.NativeKernelFrameDomainCounter:native_kernel_frame_role_key() return "domain.counter" end
    function Native.NativeKernelFrameTripCount:native_kernel_frame_role_key() return "domain.trip_count" end
    function Native.NativeKernelFrameLaneBase:native_kernel_frame_role_key() return "lane.base." .. self.lane.text end
    function Native.NativeKernelFrameLaneStride:native_kernel_frame_role_key() return "lane.stride." .. self.lane.text end
    function Native.NativeKernelFrameLaneAddress:native_kernel_frame_role_key() return "lane.address." .. self.lane.text end
    function Native.NativeKernelFrameKernelValue:native_kernel_frame_role_key() return "kernel.value." .. self.value.text end
    function Native.NativeKernelFrameCodeValue:native_kernel_frame_role_key() return "code.value." .. self.value.text end
    function Native.NativeKernelFrameEffectState:native_kernel_frame_role_key() return "effect.state." .. tostring(self.ordinal) end
    function Native.NativeKernelFrameResult:native_kernel_frame_role_key() return "result" end

    local function frame_role_equals(left, right)
        return left ~= nil and right ~= nil and left:native_kernel_frame_role_key() == right:native_kernel_frame_role_key()
    end

    local function frame_slot_for_entry(lowering, frame_entry)
        for _, entry in ipairs((lowering.frame and lowering.frame.entries) or {}) do
            if entry.entry == frame_entry then return entry.slot end
        end
        local key = frame_entry.role:native_kernel_frame_role_key()
        for _, entry in ipairs((lowering.frame and lowering.frame.entries) or {}) do
            if entry.entry.role:native_kernel_frame_role_key() == key then return entry.slot end
        end
        internal_error("kernel lowering frame has no slot for role " .. key)
    end

    local function frame_entry_for_role(lowering, role)
        for _, entry in ipairs((lowering.frame and lowering.frame.entries) or {}) do
            if frame_role_equals(entry.entry.role, role) then return entry.entry end
        end
        return nil
    end

    local function required_frame_entry_for_role(lowering, role)
        local entry = frame_entry_for_role(lowering, role)
        if entry ~= nil then return entry end
        internal_error("kernel lowering frame has no entry for role " .. role:native_kernel_frame_role_key())
    end

    local function frame_offset_for_entry(input, frame_entry)
        return frame_slot_for_entry(input.lowering, frame_entry).offset
    end

    local function placement_for_frame_entry(input, frame_entry)
        local slot = frame_slot_for_entry(input.lowering, frame_entry)
        return Native.NativeValuePlacement(
            frame_entry.template_value,
            frame_entry.storage.representation,
            Native.NativeValueFrameSlotLocation(slot)
        )
    end

    local function append_frame_value_edge(input, node, placement)
        if placement == nil or not asdl.isa(placement.location, Native.NativeValueFrameSlotLocation) then return nil end
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(
            placement.value,
            node.id,
            node.id,
            placement.representation,
            placement.location.slot
        )
        return node
    end

    local function selected_entry(plan, family)
        local selected = plan.bank:select_native_template(Native.NativeTemplateSelectionInput(plan.target, family))
        if asdl.isa(selected, Native.NativeTemplateSelected) then return selected.entry end
        internal_error("kernel native template selection failed for " .. family.id.text .. ": " .. tostring(selected))
    end

    function Native.NativeKernelOpSourceShape:native_kernel_template_role()
        internal_error("kernel source shape has no template role")
    end

    function Native.NativeKernelDomainOpShape:native_kernel_template_role() return Native.NativeRoleKernelDomain end
    function Native.NativeKernelLaneOpShape:native_kernel_template_role() return Native.NativeRoleKernelLane end
    function Native.NativeKernelExprOpShape:native_kernel_template_role() return Native.NativeRoleKernelExpr end
    function Native.NativeKernelEffectOpShape:native_kernel_template_role() return Native.NativeRoleKernelEffect end
    function Native.NativeKernelResultOpShape:native_kernel_template_role() return Native.NativeRoleKernelResult end
    function Native.NativeKernelProofOpShape:native_kernel_template_role() return Native.NativeRoleKernelProof end
    function Native.NativeKernelBodyOpShape:native_kernel_template_role() return Native.NativeRoleKernelBody end
    function Native.NativeKernelPlanOpShape:native_kernel_template_role() return Native.NativeRoleKernelPlan end

    local function kernel_family(target, op_shape)
        return Support.family(
            Support.kernel_family_id(op_shape:native_kernel_op_source_token()),
            op_shape:native_kernel_template_role(),
            {
                Support.axis_target(target),
                Support.axis_kernel(Native.NativeKernelSourceShapeAxis(op_shape)),
            },
            Support.protocol_void_none()
        )
    end

    local function kernel_node_id(state, role)
        return Native.NativeTemplateNodeId("native.kernel.node." .. tostring(#state.nodes + 1) .. "." .. role)
    end

    local function kernel_instance_id(node_id)
        return Native.NativeTemplateInstanceId("native.kernel.instance." .. node_id.text)
    end

    local function binding_target_for_hole_id(entry, hole_id)
        local compiled = entry and entry.compiled
        if compiled ~= nil then
            local symbol
            for _, layout in ipairs(compiled.holes or {}) do
                if layout.id == hole_id then
                    symbol = layout.symbol
                    break
                end
            end
            if symbol ~= nil then
                for _, ordinal in ipairs(compiled.hole_ordinals or {}) do
                    if ordinal.symbol == symbol then return Native.NativePatchBindingHoleOrdinal(ordinal.id) end
                end
            end
        end
        return Native.NativePatchBindingHoleId(hole_id)
    end

    local function hole_binding(id, coordinate)
        local hole_id = Native.NativePatchHoleId(id)
        return function(node_id, instance, entry)
            return Native.NativePatchBinding(node_id, instance, binding_target_for_hole_id(entry, hole_id), coordinate)
        end
    end

    local function frame_entry_binding(input, id, entry)
        return hole_binding(id, Native.NativePatchFrameOffset(frame_offset_for_entry(input, entry)))
    end

    local function imm32_binding(id, value)
        return hole_binding(id, Native.NativePatchImmediateI32(value))
    end

    local function scalar_immediate_hole_id(id, scalar)
        if scalar.bits and scalar.bits > 32 then return id .. ".imm64" end
        return id .. ".imm32"
    end

    local function scalar_constant_hole_id(id, scalar)
        if asdl.isa(scalar, Native.NativeScalarPointer) then return id end
        return scalar_immediate_hole_id(id, scalar)
    end

    local function materialize_bindings(node_id, instance, entry, binding_specs)
        local bindings = {}
        for _, spec in ipairs(binding_specs or {}) do
            bindings[#bindings + 1] = spec(node_id, instance, entry)
        end
        return bindings
    end

    local function append_kernel_node(input, role, op_shape, inputs, outputs, binding_specs)
        local node_id = kernel_node_id(input.state, role)
        local instance = kernel_instance_id(node_id)
        local entry = selected_entry(input.plan, kernel_family(input.plan.target, op_shape))
        local node = Native.NativeTemplateNode(
            node_id,
            instance,
            entry,
            inputs or {},
            outputs or {},
            materialize_bindings(node_id, instance, entry, binding_specs)
        )
        input.state.nodes[#input.state.nodes + 1] = node
        return node
    end

    local function append_next_edge(input, from_node, to_node)
        input.state.control_edges[#input.state.control_edges + 1] = Native.NativeContinuationEdge(
            from_node.id,
            to_node.id,
            Support.next_continuation_symbol()
        )
        return to_node
    end

    local function append_loopback_edge(input, from_node, to_node)
        input.state.control_edges[#input.state.control_edges + 1] = Native.NativeLoopBackedgeEdge(
            from_node.id,
            to_node.id,
            Support.next_continuation_symbol()
        )
        return to_node
    end

    local function frame_entry_for_kernel_value(input, value)
        for _, entry in ipairs(input.lowering.kernel_inputs or {}) do
            if entry.value == value then return entry.frame end
        end
        local frame = frame_entry_for_role(input.lowering, Native.NativeKernelFrameKernelValue(value))
        if frame ~= nil then return frame end
        internal_error("kernel lowering has no frame entry for KernelValueId " .. tostring(value and value.text))
    end

    function Flow.FlowTripCount:native_kernel_matches_code_value(_value)
        return false
    end

    function Flow.FlowTripCountExact:native_kernel_matches_code_value(value)
        return self.count == value
    end

    function Flow.FlowTripCountNonNegative:native_kernel_matches_code_value(value)
        return self.count == value
    end

    function Flow.FlowTripCountUnknown:native_kernel_matches_code_value(_value)
        return false
    end

    function Kernel.KernelPlan:native_kernel_code_value_frame_entry(_input, _value)
        return nil
    end

    function Kernel.KernelPlanned:native_kernel_code_value_frame_entry(input, value)
        return self.body:native_kernel_code_value_frame_entry(input, value)
    end

    function Kernel.KernelBody:native_kernel_code_value_frame_entry(input, value)
        return self.domain:native_kernel_code_value_frame_entry(input, value)
    end

    function Kernel.KernelDomain:native_kernel_code_value_frame_entry(_input, _value)
        return nil
    end

    function Kernel.KernelDomainFlow:native_kernel_code_value_frame_entry(input, value)
        if self.counter == value then return required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameDomainCounter) end
        if self.trip_count:native_kernel_matches_code_value(value) then return required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameTripCount) end
        return nil
    end

    local function frame_entry_for_code_value(input, value)
        for _, entry in ipairs(input.lowering.code_inputs or {}) do
            if entry.value == value then return entry.frame end
        end
        local from_plan = input.lowering.plan:native_kernel_code_value_frame_entry(input, value)
        if from_plan ~= nil then return from_plan end
        local frame = frame_entry_for_role(input.lowering, Native.NativeKernelFrameCodeValue(value))
        if frame ~= nil then return frame end
        internal_error("kernel lowering has no frame entry for CodeValueId " .. tostring(value and value.text))
    end

    local function lane_address_entry(input, lane_id)
        for _, entry in ipairs(input.lowering.lanes or {}) do
            if entry.lane == lane_id then return entry end
        end
        internal_error("kernel lowering has no lane address entry for " .. tostring(lane_id and lane_id.text))
    end

    function Code.CodeConst:native_kernel_patch_coordinate(_target)
        internal_error("kernel constant leaf has no patch coordinate")
    end

    function Code.CodeConstLiteral:native_kernel_patch_coordinate(target)
        local scalar = self.ty:native_machine_scalar(target)
        if self.literal.native_patch_coordinate_for_scalar == nil then internal_error("kernel literal has no scalar patch coordinate") end
        return self.literal:native_patch_coordinate_for_scalar(scalar)
    end

    function Code.CodeConstNull:native_kernel_patch_coordinate(target)
        local scalar = self.ty:native_machine_scalar(target)
        if asdl.isa(scalar, Native.NativeScalarPointer) then return Native.NativePatchPointer64(0) end
        return scalar:native_null_patch_coordinate()
    end

    function Code.CodeConstUndef:native_kernel_patch_coordinate(_target)
        internal_error("kernel native lowering cannot patch undef constants")
    end

    function Value.ValueExpr:native_kernel_source_frame_entry(_input)
        internal_error("kernel expression is not available as a frame source; bind it through a KernelBinding first")
    end

    function Value.ValueExprValue:native_kernel_source_frame_entry(input)
        return frame_entry_for_code_value(input, self.value)
    end

    function Value.ValueExpr:native_kernel_value_expr_source_shape_for_storage(storage, target, type_layouts)
        return self:native_kernel_value_expr_source_shape(nil, target, type_layouts or Native.NativeCodeTypeLayoutPlan({}, {}, {}))
    end

    function Value.ValueExprConst:native_kernel_value_expr_source_shape_for_storage(storage, _target, _type_layouts)
        return Native.NativeKernelExprConstShape(value_source_shape_for_storage(storage))
    end

    function Value.ValueExprValue:native_kernel_value_expr_source_shape_for_storage(storage, _target, _type_layouts)
        return Native.NativeKernelExprCodeValueShape(value_source_shape_for_storage(storage))
    end

    function Value.ValueExprAffine:native_kernel_value_expr_source_shape_for_storage(storage, _target, _type_layouts)
        return Native.NativeKernelExprAffineShape(value_source_shape_for_storage(storage), #(self.affine.terms or {}))
    end

    function Value.ValueExprUnary:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts)
        return Native.NativeKernelExprUnaryShape(self.op, value_source_shape_for_type(self.ty, target, type_layouts))
    end

    function Value.ValueExprCast:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts)
        return Native.NativeKernelExprCastShape(self.op, value_source_shape_for_type(self.from, target, type_layouts), value_source_shape_for_type(self.to, target, type_layouts))
    end

    function Value.ValueExprBinary:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts)
        return Native.NativeKernelExprBinaryShape(self.op, value_source_shape_for_type(self.ty, target, type_layouts))
    end

    function Value.ValueExprAdd:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinAdd, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprSub:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinSub, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprMul:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinMul, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprDiv:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinDiv, value_source_shape_for_type(self.ty, target, type_layouts)) end
    function Value.ValueExprRem:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts) return Native.NativeKernelExprBinaryShape(T.LalinCore.BinRem, value_source_shape_for_type(self.ty, target, type_layouts)) end

    function Value.ValueExprCmp:native_kernel_value_expr_source_shape_for_storage(_storage, target, type_layouts)
        return Native.NativeKernelExprCompareShape(self.op, value_source_shape_for_type(self.ty, target, type_layouts))
    end

    function Value.ValueExprSelect:native_kernel_value_expr_source_shape_for_storage(storage, _target, _type_layouts)
        return Native.NativeKernelExprSelectShape(value_source_shape_for_storage(storage))
    end

    function Value.ValueExpr:append_native_kernel_expr_bindings(_input, _id_base, _bindings, _storage)
        internal_error("kernel expression leaf has no native bindings")
    end

    function Value.ValueExprConst:append_native_kernel_expr_bindings(input, id_base, bindings, storage)
        local scalar = value_source_shape_for_storage(storage):native_kernel_c_scalar(input.plan.target)
        if scalar == nil then internal_error("kernel constant source requires scalar or pointer storage") end
        bindings[#bindings + 1] = hole_binding(scalar_constant_hole_id(id_base .. ".const", scalar), self.const:native_kernel_patch_coordinate(input.plan.target))
    end

    function Value.ValueExprValue:append_native_kernel_expr_bindings(input, id_base, bindings, _storage)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", frame_entry_for_code_value(input, self.value))
    end

    local function parse_i32(text, role)
        local value = tonumber(text)
        if value == nil then internal_error("kernel affine " .. role .. " is not an immediate integer: " .. tostring(text)) end
        return value
    end

    function Value.ValueExprAffine:append_native_kernel_expr_bindings(input, id_base, bindings, storage)
        local scalar = value_source_shape_for_storage(storage):native_kernel_c_scalar(input.plan.target)
        if scalar == nil then internal_error("kernel affine expression requires scalar storage") end
        bindings[#bindings + 1] = hole_binding(scalar_constant_hole_id(id_base .. ".base", scalar), scalar.bits and scalar.bits > 32 and Native.NativePatchImmediateI64(parse_i32(self.affine.constant, "constant")) or Native.NativePatchImmediateI32(parse_i32(self.affine.constant, "constant")))
        for i, term in ipairs(self.affine.terms or {}) do
            local ordinal = i - 1
            bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".term" .. tostring(ordinal), frame_entry_for_code_value(input, term.value))
            bindings[#bindings + 1] = imm32_binding(id_base .. ".coeff" .. tostring(ordinal), parse_i32(term.coeff, "coefficient"))
        end
    end

    function Value.ValueExprUnary:append_native_kernel_expr_bindings(input, id_base, bindings, _storage)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", self.value:native_kernel_source_frame_entry(input))
    end

    function Value.ValueExprCast:append_native_kernel_expr_bindings(input, id_base, bindings, _storage)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", self.value:native_kernel_source_frame_entry(input))
    end

    local function append_binary_value_expr_bindings(expr, input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".lhs", expr.a:native_kernel_source_frame_entry(input))
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".rhs", expr.b:native_kernel_source_frame_entry(input))
    end

    function Value.ValueExprBinary:append_native_kernel_expr_bindings(input, id_base, bindings, _storage)
        append_binary_value_expr_bindings(self, input, id_base, bindings)
    end

    function Value.ValueExprAdd:append_native_kernel_expr_bindings(input, id_base, bindings, _storage) append_binary_value_expr_bindings(self, input, id_base, bindings) end
    function Value.ValueExprSub:append_native_kernel_expr_bindings(input, id_base, bindings, _storage) append_binary_value_expr_bindings(self, input, id_base, bindings) end
    function Value.ValueExprMul:append_native_kernel_expr_bindings(input, id_base, bindings, _storage) append_binary_value_expr_bindings(self, input, id_base, bindings) end
    function Value.ValueExprDiv:append_native_kernel_expr_bindings(input, id_base, bindings, _storage) append_binary_value_expr_bindings(self, input, id_base, bindings) end
    function Value.ValueExprRem:append_native_kernel_expr_bindings(input, id_base, bindings, _storage) append_binary_value_expr_bindings(self, input, id_base, bindings) end

    function Value.ValueExprCmp:append_native_kernel_expr_bindings(input, id_base, bindings, _storage)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".lhs", self.a:native_kernel_source_frame_entry(input))
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".rhs", self.b:native_kernel_source_frame_entry(input))
    end

    function Value.ValueExprSelect:append_native_kernel_expr_bindings(input, id_base, bindings, _storage)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".cond", self.cond:native_kernel_source_frame_entry(input))
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".true", self.t:native_kernel_source_frame_entry(input))
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".false", self.f:native_kernel_source_frame_entry(input))
    end

    local function append_expr_projection_bindings(projection, input, id_base, bindings)
        return projection:append_native_kernel_expr_bindings(input, id_base, bindings)
    end

    function Native.NativeKernelExprProjection:append_native_kernel_expr_bindings(_input, _id_base, _bindings)
        internal_error("kernel expression projection has no native bindings")
    end

    function Native.NativeKernelExprCodeValueProjection:append_native_kernel_expr_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", frame_entry_for_code_value(input, self.value))
    end

    function Native.NativeKernelExprKernelValueProjection:append_native_kernel_expr_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", frame_entry_for_kernel_value(input, self.value))
    end

    function Native.NativeKernelExprAlgebraProjection:append_native_kernel_expr_bindings(input, id_base, bindings)
        self.expr:append_native_kernel_expr_bindings(input, id_base, bindings, self.storage)
    end

    function Native.NativeKernelLaneAddressSourceShape:append_native_kernel_address_bindings(_projection, _input, _id_base, _index_expr, _bindings)
        internal_error("kernel lane source shape has no address bindings")
    end

    function Native.NativeKernelLaneScalarAddressShape:append_native_kernel_address_bindings(projection, input, id_base, _index_expr, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", lane_address_entry(input, projection.lane.id).base)
    end

    local function append_indexed_lane_bindings(shape, projection, input, id_base, index_expr, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", lane_address_entry(input, projection.lane.id).base)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".index", index_expr:native_kernel_source_frame_entry(input))
        bindings[#bindings + 1] = imm32_binding(id_base .. ".elem_size", shape.elem:native_kernel_value_size(input.plan.target))
    end

    function Native.NativeKernelLaneContiguousAddressShape:append_native_kernel_address_bindings(projection, input, id_base, index_expr, bindings)
        append_indexed_lane_bindings(self, projection, input, id_base, index_expr, bindings)
    end

    function Native.NativeKernelLaneIndexedAddressShape:append_native_kernel_address_bindings(projection, input, id_base, index_expr, bindings)
        append_indexed_lane_bindings(self, projection, input, id_base, index_expr, bindings)
    end

    function Native.NativeKernelLaneStridedAddressShape:append_native_kernel_address_bindings(projection, input, id_base, index_expr, bindings)
        append_indexed_lane_bindings(self, projection, input, id_base, index_expr, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".stride", lane_address_entry(input, projection.lane.id).stride)
    end

    function Native.NativeKernelLaneProjection:append_native_kernel_address_bindings(input, id_base, index_expr, bindings)
        self:native_kernel_lane_address_source_shape():append_native_kernel_address_bindings(self, input, id_base, index_expr, bindings)
    end

    function Native.NativeKernelExprLaneLoadProjection:append_native_kernel_expr_bindings(input, id_base, bindings)
        self.lane:append_native_kernel_address_bindings(input, id_base .. ".lane", self.index, bindings)
    end

    function Native.NativeKernelExprProjection:native_kernel_source_frame_entry(_input)
        internal_error("kernel expression projection is not already materialized in a frame slot")
    end

    function Native.NativeKernelExprCodeValueProjection:native_kernel_source_frame_entry(input)
        return frame_entry_for_code_value(input, self.value)
    end

    function Native.NativeKernelExprKernelValueProjection:native_kernel_source_frame_entry(input)
        return frame_entry_for_kernel_value(input, self.value)
    end

    function Native.NativeKernelExprAlgebraProjection:native_kernel_source_frame_entry(input)
        return self.expr:native_kernel_source_frame_entry(input)
    end

    function Kernel.KernelExpr:select_native_expr_template(_input, _output_entry, _ty)
        internal_error("kernel expression leaf has no native template lowering")
    end

    local function append_expr_node(input, role, projection, output_entry)
        local source_shape = projection:native_kernel_value_expr_source_shape(input.plan.target, input.lowering.type_layouts)
        local op_shape = Native.NativeKernelExprOpShape(source_shape)
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local output = placement_for_frame_entry(input, output_entry)
        local bindings = { frame_entry_binding(input, id_base .. ".dst", output_entry) }
        append_expr_projection_bindings(projection, input, id_base, bindings)
        local node = append_kernel_node(input, role, op_shape, {}, { output }, bindings)
        append_frame_value_edge(input, node, output)
        return node
    end

    function Kernel.KernelExprValue:select_native_expr_template(input, output_entry, ty)
        return append_expr_node(input, "expr.value", self:native_kernel_expr_projection(ty, input.plan.target, input.lowering.type_layouts), output_entry)
    end

    function Kernel.KernelExprAlgebra:select_native_expr_template(input, output_entry, ty)
        return append_expr_node(input, "expr.algebra", self:native_kernel_expr_projection(ty, input.plan.target, input.lowering.type_layouts), output_entry)
    end

    function Kernel.KernelExprLaneLoad:select_native_expr_template(input, output_entry, ty)
        return append_expr_node(input, "expr.lane_load", self:native_kernel_expr_projection(ty, input.plan.target, input.lowering.type_layouts), output_entry)
    end

    function Kernel.KernelExprKernelValue:select_native_expr_template(input, output_entry, ty)
        return append_expr_node(input, "expr.kernel_value", self:native_kernel_expr_projection(ty, input.plan.target, input.lowering.type_layouts), output_entry)
    end

    function Kernel.KernelPlan:native_kernel_domain_counter_value()
        return nil
    end

    function Kernel.KernelPlanned:native_kernel_domain_counter_value()
        return self.body:native_kernel_domain_counter_value()
    end

    function Kernel.KernelBody:native_kernel_domain_counter_value()
        return self.domain:native_kernel_domain_counter_value()
    end

    function Kernel.KernelDomain:native_kernel_domain_counter_value()
        return nil
    end

    function Kernel.KernelDomainFlow:native_kernel_domain_counter_value()
        return self.counter
    end

    local function domain_counter_expr(input)
        local counter = input.lowering.plan:native_kernel_domain_counter_value()
        if counter == nil then internal_error("kernel lane/effect lowering requires a domain counter CodeValueId") end
        return Value.ValueExprValue(counter)
    end

    function Kernel.KernelLane:select_native_lane_template(input)
        local projection = self:native_kernel_lane_projection(input.plan.target, input.lowering.type_layouts)
        local source_shape = projection:native_kernel_lane_address_source_shape()
        local op_shape = Native.NativeKernelLaneOpShape(source_shape)
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local lane_entry = lane_address_entry(input, self.id)
        local output = placement_for_frame_entry(input, lane_entry.address)
        local bindings = { frame_entry_binding(input, id_base .. ".dst", lane_entry.address) }
        projection:append_native_kernel_address_bindings(input, id_base, domain_counter_expr(input), bindings)
        return append_frame_value_edge(input, append_kernel_node(input, "lane", op_shape, {}, { output }, bindings), output)
    end

    function Kernel.KernelDomainFlow:select_native_domain_template(input)
        local projection = self:native_kernel_loop_projection(input.plan.target)
        local op_shape = Native.NativeKernelDomainOpShape(projection:native_kernel_loop_source_shape())
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local bindings = {}
        if self.counter ~= nil then
            bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".counter", required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameDomainCounter))
        end
        if projection.trip_count_value ~= nil then
            bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".trip", required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameTripCount))
        end
        return append_kernel_node(input, "domain", op_shape, {}, {}, bindings)
    end

    function Stencil.StencilPredicate:append_native_kernel_predicate_bindings(_input, _id_base, _bindings, _tested_expr)
        internal_error("stencil predicate leaf has no native kernel bindings")
    end

    function Stencil.StencilPredNonZero:append_native_kernel_predicate_bindings(_input, _id_base, _bindings, _tested_expr)
        return nil
    end

    function Stencil.StencilPredCompareConst:append_native_kernel_predicate_bindings(input, id_base, bindings, tested_expr)
        if tested_expr == nil then internal_error("kernel compare-const predicate requires an owner-provided tested expression") end
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", tested_expr:native_kernel_source_frame_entry(input))
        if not asdl.isa(self.value, Value.ValueExprConst) then internal_error("kernel compare-const predicate requires a constant ValueExpr for the patch value") end
        local scalar = self.operand_ty:native_machine_scalar(input.plan.target)
        bindings[#bindings + 1] = hole_binding(scalar_constant_hole_id(id_base .. ".const", scalar), self.value.const:native_kernel_patch_coordinate(input.plan.target))
    end

    function Stencil.StencilPredRange:append_native_kernel_predicate_bindings(input, id_base, bindings, tested_expr)
        if tested_expr == nil then internal_error("kernel range predicate requires an owner-provided tested expression") end
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", tested_expr:native_kernel_source_frame_entry(input))
        if not asdl.isa(self.lower, Value.ValueExprConst) or not asdl.isa(self.upper, Value.ValueExprConst) then internal_error("kernel range predicate bounds must be constant ValueExpr values") end
        local scalar = self.operand_ty:native_machine_scalar(input.plan.target)
        bindings[#bindings + 1] = hole_binding(scalar_constant_hole_id(id_base .. ".lo", scalar), self.lower.const:native_kernel_patch_coordinate(input.plan.target))
        bindings[#bindings + 1] = hole_binding(scalar_constant_hole_id(id_base .. ".hi", scalar), self.upper.const:native_kernel_patch_coordinate(input.plan.target))
    end

    function Stencil.StencilPredAnd:append_native_kernel_predicate_bindings(_input, _id_base, _bindings, _tested_expr)
        internal_error("logical kernel predicates require predicate-temp frame facts before lowering")
    end

    function Stencil.StencilPredOr:append_native_kernel_predicate_bindings(_input, _id_base, _bindings, _tested_expr)
        internal_error("logical kernel predicates require predicate-temp frame facts before lowering")
    end

    function Stencil.StencilPredNot:append_native_kernel_predicate_bindings(_input, _id_base, _bindings, _tested_expr)
        internal_error("logical kernel predicates require predicate-temp frame facts before lowering")
    end

    function Stencil.StencilPredIsNaN:append_native_kernel_predicate_bindings(input, id_base, bindings, tested_expr)
        if tested_expr == nil then internal_error("kernel float-class predicate requires an owner-provided tested expression") end
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", tested_expr:native_kernel_source_frame_entry(input))
    end

    function Stencil.StencilPredIsInf:append_native_kernel_predicate_bindings(input, id_base, bindings, tested_expr)
        if tested_expr == nil then internal_error("kernel float-class predicate requires an owner-provided tested expression") end
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", tested_expr:native_kernel_source_frame_entry(input))
    end

    function Stencil.StencilPredIsFinite:append_native_kernel_predicate_bindings(input, id_base, bindings, tested_expr)
        if tested_expr == nil then internal_error("kernel float-class predicate requires an owner-provided tested expression") end
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", tested_expr:native_kernel_source_frame_entry(input))
    end

    function Native.NativeKernelEffectProjection:append_native_kernel_effect_bindings(_input, _id_base, _bindings, _ordinal)
        internal_error("kernel effect projection has no native bindings")
    end

    function Native.NativeKernelEffectStoreProjection:append_native_kernel_effect_bindings(input, id_base, bindings, _ordinal)
        self.dst:append_native_kernel_address_bindings(input, id_base .. ".dst", self.index, bindings)
        append_expr_projection_bindings(self.value, input, id_base .. ".value", bindings)
    end

    function Native.NativeKernelEffectScanProjection:append_native_kernel_effect_bindings(input, id_base, bindings, ordinal)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".state", required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameEffectState(ordinal)))
        self.dst:append_native_kernel_address_bindings(input, id_base .. ".dst", self.index, bindings)
    end

    function Native.NativeKernelEffectPartitionProjection:append_native_kernel_effect_bindings(input, id_base, bindings, _ordinal)
        self.pred:append_native_kernel_predicate_bindings(input, id_base .. ".pred", bindings, self.src)
        self.dst:append_native_kernel_address_bindings(input, id_base .. ".dst", domain_counter_expr(input), bindings)
        append_expr_projection_bindings(self.src, input, id_base .. ".src", bindings)
    end

    function Native.NativeKernelEffectCopyProjection:append_native_kernel_effect_bindings(input, id_base, bindings, _ordinal)
        self.dst:append_native_kernel_address_bindings(input, id_base .. ".dst", domain_counter_expr(input), bindings)
        append_expr_projection_bindings(self.src, input, id_base .. ".src", bindings)
    end

    function Native.NativeKernelEffectScatterReduceProjection:append_native_kernel_effect_bindings(input, id_base, bindings, _ordinal)
        self.dst:append_native_kernel_address_bindings(input, id_base .. ".dst", self.index, bindings)
        append_expr_projection_bindings(self.value, input, id_base .. ".value", bindings)
    end

    function Native.NativeKernelEffectFoldProjection:append_native_kernel_effect_bindings(input, id_base, bindings, ordinal)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".state", required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameEffectState(ordinal)))
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", self.reduction.contribution:native_kernel_source_frame_entry(input))
    end

    local function call_target_entry(input, call)
        for _, entry in ipairs(input.lowering.calls or {}) do
            if entry.call == call then return entry end
        end
        local shape = call:native_kernel_call_source_shape()
        if asdl.isa(shape, Native.NativeKernelCallEffectOnlyShape) then return call:native_kernel_call_target_entry() end
        internal_error("kernel lowering has no call target capability for CallSummary")
    end

    function Native.NativeKernelCallTargetCapability:append_native_kernel_call_bindings(_input, _id_base, _bindings)
        internal_error("kernel call target capability has no native binding")
    end

    function Native.NativeKernelCallInternalTarget:append_native_kernel_call_bindings(_input, id_base, bindings)
        bindings[#bindings + 1] = hole_binding(id_base .. ".target", Native.NativePatchCodeFuncAddress(self.func))
    end

    function Native.NativeKernelCallExternTarget:append_native_kernel_call_bindings(_input, id_base, bindings)
        bindings[#bindings + 1] = hole_binding(id_base .. ".target", Native.NativePatchCallTarget(self.runtime_symbol))
    end

    function Native.NativeKernelCallEffectOnlyTarget:append_native_kernel_call_bindings(_input, _id_base, _bindings)
        return nil
    end

    function Native.NativeKernelEffectCallProjection:append_native_kernel_effect_bindings(input, id_base, bindings, _ordinal)
        call_target_entry(input, self.call).capability:append_native_kernel_call_bindings(input, id_base, bindings)
    end

    function Kernel.KernelEffect:append_native_effect_template(_input, _ordinal)
        internal_error("kernel effect leaf has no native template lowering")
    end

    local function append_effect_node(input, role, projection, ordinal)
        local op_shape = Native.NativeKernelEffectOpShape(projection:native_kernel_effect_source_shape(input.plan.target, input.lowering.type_layouts))
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local bindings = {}
        projection:append_native_kernel_effect_bindings(input, id_base, bindings, ordinal)
        return append_kernel_node(input, role, op_shape, {}, {}, bindings)
    end

    function Kernel.KernelEffectStore:append_native_effect_template(input, ordinal) return append_effect_node(input, "effect.store", self:native_kernel_effect_projection(input.plan.target, input.lowering.type_layouts), ordinal) end
    function Kernel.KernelEffectScan:append_native_effect_template(input, ordinal) return append_effect_node(input, "effect.scan", self:native_kernel_effect_projection(input.plan.target, input.lowering.type_layouts), ordinal) end
    function Kernel.KernelEffectPartition:append_native_effect_template(input, ordinal) return append_effect_node(input, "effect.partition", self:native_kernel_effect_projection(input.plan.target, input.lowering.type_layouts), ordinal) end
    function Kernel.KernelEffectCopy:append_native_effect_template(input, ordinal) return append_effect_node(input, "effect.copy", self:native_kernel_effect_projection(input.plan.target, input.lowering.type_layouts), ordinal) end
    function Kernel.KernelEffectScatterReduce:append_native_effect_template(input, ordinal) return append_effect_node(input, "effect.scatter_reduce", self:native_kernel_effect_projection(input.plan.target, input.lowering.type_layouts), ordinal) end
    function Kernel.KernelEffectFold:append_native_effect_template(input, ordinal) return append_effect_node(input, "effect.fold", self:native_kernel_effect_projection(input.plan.target, input.lowering.type_layouts), ordinal) end
    function Kernel.KernelEffectCall:append_native_effect_template(input, ordinal) return append_effect_node(input, "effect.call", self:native_kernel_effect_projection(input.plan.target, input.lowering.type_layouts), ordinal) end

    local function result_frame_entry(input)
        return required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameResult)
    end

    local function reduction_state_frame_entry(input, reduction)
        local body = asdl.isa(input.lowering.plan, Kernel.KernelPlanned) and input.lowering.plan.body or nil
        for i, effect in ipairs((body and body.effects) or {}) do
            if asdl.isa(effect, Kernel.KernelEffectFold) and effect.reduction == reduction then
                return required_frame_entry_for_role(input.lowering, Native.NativeKernelFrameEffectState(i - 1))
            end
        end
        internal_error("kernel reduction result has no matching fold effect state")
    end

    function Kernel.KernelResult:append_native_result_template(_input)
        internal_error("kernel result leaf has no native template lowering")
    end

    local function append_result_node(input, role, projection, bindings)
        local op_shape = Native.NativeKernelResultOpShape(projection:native_kernel_result_source_shape(input.plan.target, input.lowering.type_layouts))
        return append_kernel_node(input, role, op_shape, {}, {}, bindings or {})
    end

    function Kernel.KernelResultVoid:append_native_result_template(input)
        return append_result_node(input, "result.void", self:native_kernel_result_projection(input.lowering.result_ty, input.plan.target, input.lowering.type_layouts), {})
    end

    function Kernel.KernelResultValue:append_native_result_template(input)
        local projection = self:native_kernel_result_projection(input.lowering.result_ty, input.plan.target, input.lowering.type_layouts)
        local op_shape = Native.NativeKernelResultOpShape(projection:native_kernel_result_source_shape(input.plan.target, input.lowering.type_layouts))
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local bindings = { frame_entry_binding(input, id_base .. ".result", result_frame_entry(input)) }
        append_expr_projection_bindings(projection.expr, input, id_base .. ".value", bindings)
        return append_kernel_node(input, "result.value", op_shape, {}, { placement_for_frame_entry(input, result_frame_entry(input)) }, bindings)
    end

    function Kernel.KernelResultFind:append_native_result_template(input)
        local projection = self:native_kernel_result_projection(input.lowering.result_ty, input.plan.target, input.lowering.type_layouts)
        local op_shape = Native.NativeKernelResultOpShape(projection:native_kernel_result_source_shape(input.plan.target, input.lowering.type_layouts))
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local bindings = { frame_entry_binding(input, id_base .. ".result", result_frame_entry(input)) }
        append_expr_projection_bindings(projection.src, input, id_base .. ".src", bindings)
        self.pred:append_native_kernel_predicate_bindings(input, id_base .. ".pred", bindings, projection.src)
        return append_kernel_node(input, "result.find", op_shape, {}, { placement_for_frame_entry(input, result_frame_entry(input)) }, bindings)
    end

    function Kernel.KernelResultReduction:append_native_result_template(input)
        local projection = self:native_kernel_result_projection(input.lowering.result_ty, input.plan.target, input.lowering.type_layouts)
        local op_shape = Native.NativeKernelResultOpShape(projection:native_kernel_result_source_shape(input.plan.target, input.lowering.type_layouts))
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local bindings = {
            frame_entry_binding(input, id_base .. ".result", result_frame_entry(input)),
            frame_entry_binding(input, id_base .. ".state", reduction_state_frame_entry(input, self.reduction)),
        }
        return append_kernel_node(input, "result.reduction", op_shape, {}, { placement_for_frame_entry(input, result_frame_entry(input)) }, bindings)
    end

    function Kernel.KernelResultClosedForm:append_native_result_template(input)
        local projection = self:native_kernel_result_projection(input.lowering.result_ty, input.plan.target, input.lowering.type_layouts)
        local op_shape = Native.NativeKernelResultOpShape(projection:native_kernel_result_source_shape(input.plan.target, input.lowering.type_layouts))
        local id_base = "native.hole.kernel." .. op_shape:native_kernel_op_source_token()
        local bindings = {
            frame_entry_binding(input, id_base .. ".result", result_frame_entry(input)),
            frame_entry_binding(input, id_base .. ".value", self.closed_form.expr:native_kernel_source_frame_entry(input)),
        }
        return append_kernel_node(input, "result.closed_form", op_shape, {}, { placement_for_frame_entry(input, result_frame_entry(input)) }, bindings)
    end

    function Kernel.KernelResultOriginalControl:append_native_result_template(input)
        return append_result_node(input, "result.original_control", self:native_kernel_result_projection(input.lowering.result_ty, input.plan.target, input.lowering.type_layouts), {})
    end

    function Kernel.KernelProof:require_native_proof(_input)
        internal_error("kernel proof leaf has no native proof requirement")
    end

    local function append_proof_node(input, role, projection)
        local op_shape = Native.NativeKernelProofOpShape(projection:native_kernel_proof_source_shape())
        return append_kernel_node(input, role, op_shape, {}, {}, {})
    end

    function Kernel.KernelProofFlow:require_native_proof(input) return append_proof_node(input, "proof.flow", self:native_kernel_proof_projection()) end
    function Kernel.KernelProofValue:require_native_proof(input) return append_proof_node(input, "proof.value", self:native_kernel_proof_projection()) end
    function Kernel.KernelProofMemory:require_native_proof(input) return append_proof_node(input, "proof.memory", self:native_kernel_proof_projection()) end
    function Kernel.KernelProofEffect:require_native_proof(input) return append_proof_node(input, "proof.effect", self:native_kernel_proof_projection()) end
    function Kernel.KernelProofFunctionEquivalence:require_native_proof(input) return append_proof_node(input, "proof.function_equivalence", self:native_kernel_proof_projection()) end

    function Kernel.KernelEquivalence:append_native_proof_templates(_input)
        return {}
    end

    function Kernel.KernelEquivalenceProof:append_native_proof_templates(input)
        local out = {}
        for _, proof in ipairs(self.proofs or {}) do out[#out + 1] = proof:require_native_proof(input) end
        return out
    end

    function Kernel.KernelEquivalenceRejected:append_native_proof_templates(_input)
        return {}
    end

    local function append_chain_edges(input, nodes)
        for i = 1, #nodes - 1 do append_next_edge(input, nodes[i], nodes[i + 1]) end
    end

    function Kernel.KernelBinding:append_native_binding_template(input)
        return self.expr:select_native_expr_template(input, self:native_kernel_binding_projection(input.plan.target, input.lowering.type_layouts).frame, self.ty)
    end

    local function graph_from_kernel_state(input, entry_node)
        if #input.state.nodes == 0 then internal_error("kernel native graph has no nodes") end
        local exits = input.state.exits
        if #(exits or {}) == 0 then exits = { input.state.nodes[#input.state.nodes].id } end
        return Native.NativeTemplateGraph(
            input.plan.target,
            Native.NativeCallVoid,
            input.lowering.frame.frame,
            input.state.nodes,
            input.state.control_edges,
            input.state.value_edges,
            input.lowering.addresses,
            entry_node.id,
            exits
        )
    end

    function Kernel.KernelBody:select_native_template_graph(input)
        local body_projection = self:native_kernel_body_projection(input.plan.target, input.lowering.type_layouts, input.lowering.result_ty)
        local body_node = append_kernel_node(
            input,
            "body",
            Native.NativeKernelBodyOpShape(body_projection:native_kernel_body_source_shape(input.plan.target, input.lowering.type_layouts)),
            {},
            {},
            {}
        )
        local domain_node = self.domain:select_native_domain_template(input)
        append_next_edge(input, body_node, domain_node)

        local work_nodes = {}
        for _, lane in ipairs(self.lanes or {}) do work_nodes[#work_nodes + 1] = lane:select_native_lane_template(input) end
        for _, binding in ipairs(self.bindings or {}) do work_nodes[#work_nodes + 1] = binding:append_native_binding_template(input) end
        for i, effect in ipairs(self.effects or {}) do work_nodes[#work_nodes + 1] = effect:append_native_effect_template(input, i - 1) end
        append_chain_edges(input, work_nodes)
        if #work_nodes > 0 then append_loopback_edge(input, work_nodes[#work_nodes], domain_node) end

        local exit_nodes = self.equivalence:append_native_proof_templates(input)
        local result_node = self.result:append_native_result_template(input)
        exit_nodes[#exit_nodes + 1] = result_node
        append_chain_edges(input, exit_nodes)

        local then_target = (#work_nodes > 0) and work_nodes[1].id or domain_node.id
        local else_target = exit_nodes[1].id
        input.state.control_edges[#input.state.control_edges + 1] = Native.NativeConditionalBranchEdge(
            domain_node.id,
            then_target,
            Support.then_continuation_symbol(),
            else_target,
            Support.else_continuation_symbol(),
            Native.NativeTemplateValueId("native.kernel.domain.condition")
        )
        input.state.exits[#input.state.exits + 1] = result_node.id
        return body_node
    end

    function Kernel.KernelPlan:plan_native_copy(_plan, _lowering)
        internal_error("kernel plan leaf has no native copy lowering")
    end

    function Kernel.KernelNoPlan:plan_native_copy(_plan, _lowering)
        internal_error("kernel native copy requires KernelPlanned")
    end

    function Kernel.KernelPlanned:plan_native_copy(plan, lowering)
        if lowering == nil then internal_error("KernelPlanned:plan_native_copy requires NativeKernelLoweringInput") end
        if lowering.plan ~= self then internal_error("NativeKernelLoweringInput.plan does not match KernelPlanned value") end
        local state = Native.NativeKernelGraphBuilderState({}, {}, {}, {})
        local input = Native.NativeKernelGraphBuildInput(plan, lowering, state)
        local plan_projection = self:native_kernel_plan_projection(plan.target, lowering.type_layouts, lowering.result_ty)
        local plan_node = append_kernel_node(
            input,
            "plan",
            Native.NativeKernelPlanOpShape(plan_projection:native_kernel_plan_source_shape(plan.target, lowering.type_layouts)),
            {},
            {},
            {}
        )
        local body_entry = self.body:select_native_template_graph(input)
        append_next_edge(input, plan_node, body_entry)
        return graph_from_kernel_state(input, plan_node)
    end

    api.code_value_type_entry = code_value_type_entry
    api.kernel_value_type_entry = kernel_value_type_entry

    T._lalin_api_cache.native_kernel_methods = api
    return api
end

return bind_context
