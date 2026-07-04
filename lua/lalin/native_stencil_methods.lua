local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_stencil_methods ~= nil then return T._lalin_api_cache.native_stencil_methods end

    local Native = T.LalinNative
    local Stencil = T.LalinStencil
    local Code = T.LalinCode
    local Value = T.LalinValue
    local api = {}

    local function internal_error(msg)
        error("internal error: " .. msg, 2)
    end

    local function target_of(input_or_target)
        if input_or_target ~= nil and input_or_target.target ~= nil then return input_or_target.target end
        if input_or_target ~= nil and input_or_target.plan ~= nil and input_or_target.plan.target ~= nil then return input_or_target.plan.target end
        return input_or_target
    end

    local function type_layouts_of(input)
        if input ~= nil and input.type_layouts ~= nil then return input.type_layouts end
        if input ~= nil and input.plan ~= nil and input.plan.type_layouts ~= nil then return input.plan.type_layouts end
        return nil
    end

    local function descriptor_of(input)
        if input ~= nil and input.descriptor ~= nil then return input.descriptor end
        if input ~= nil and input.instance ~= nil then return input.instance.descriptor end
        return nil
    end

    local function storage_for_type(ty, target, type_layouts)
        if ty.native_storage_layout == nil then internal_error("CodeType native storage layout methods are not installed") end
        return ty:native_storage_layout(target, type_layouts)
    end

    local function value_shape_for_type(ty, target, type_layouts)
        if ty.native_stencil_value_source_shape == nil then internal_error("CodeType native stencil source-shape methods are not installed") end
        return ty:native_stencil_value_source_shape(target, type_layouts)
    end

    local function access_for_ref(descriptor, ref)
        if descriptor == nil then internal_error("stencil descriptor is required to project an access reference") end
        for _, access in ipairs(descriptor.accesses or {}) do
            if access.name == ref.name then return access end
        end
        internal_error("stencil access reference has no descriptor access: " .. tostring(ref.name))
    end

    function Code.CodeType:native_stencil_value_source_shape(_target, _type_layouts)
        internal_error("CodeType has no native stencil value source shape")
    end

    function Code.CodeTyVoid:native_stencil_value_source_shape(_target, _type_layouts)
        return Native.NativeStencilValueVoidShape
    end

    function Code.CodeTyBool8:native_stencil_value_source_shape(target, _type_layouts)
        return Native.NativeStencilValueScalarShape(self:native_machine_scalar(target))
    end

    function Code.CodeTyInt:native_stencil_value_source_shape(target, _type_layouts)
        return Native.NativeStencilValueScalarShape(self:native_machine_scalar(target))
    end

    function Code.CodeTyIndex:native_stencil_value_source_shape(target, _type_layouts)
        return Native.NativeStencilValueScalarShape(self:native_machine_scalar(target))
    end

    function Code.CodeTyFloat:native_stencil_value_source_shape(target, _type_layouts)
        return Native.NativeStencilValueScalarShape(self:native_machine_scalar(target))
    end

    function Code.CodeTyDataPtr:native_stencil_value_source_shape(target, _type_layouts)
        return Native.NativeStencilValuePointerShape(self:native_machine_scalar(target))
    end

    function Code.CodeTyCodePtr:native_stencil_value_source_shape(target, _type_layouts)
        return Native.NativeStencilValuePointerShape(self:native_machine_scalar(target))
    end

    function Code.CodeTyImportedCFuncPtr:native_stencil_value_source_shape(target, _type_layouts)
        return Native.NativeStencilValuePointerShape(self:native_machine_scalar(target))
    end

    function Code.CodeTyHandle:native_stencil_value_source_shape(target, type_layouts)
        return self.repr:native_stencil_value_source_shape(target, type_layouts)
    end

    function Code.CodeTyLease:native_stencil_value_source_shape(target, type_layouts)
        return self.base:native_stencil_value_source_shape(target, type_layouts)
    end

    local function byte_shape_for_type(ty, target, type_layouts)
        local storage = storage_for_type(ty, target, type_layouts)
        return Native.NativeStencilValueBytesShape(storage.size, storage.alignment)
    end

    function Code.CodeTySlice:native_stencil_value_source_shape(target, type_layouts) return byte_shape_for_type(self, target, type_layouts) end
    function Code.CodeTyView:native_stencil_value_source_shape(target, type_layouts) return byte_shape_for_type(self, target, type_layouts) end
    function Code.CodeTyByteSpan:native_stencil_value_source_shape(target, type_layouts) return byte_shape_for_type(self, target, type_layouts) end
    function Code.CodeTyArray:native_stencil_value_source_shape(target, type_layouts) return byte_shape_for_type(self, target, type_layouts) end
    function Code.CodeTyVector:native_stencil_value_source_shape(target, type_layouts) return byte_shape_for_type(self, target, type_layouts) end
    function Code.CodeTyNamed:native_stencil_value_source_shape(target, type_layouts) return byte_shape_for_type(self, target, type_layouts) end
    function Code.CodeTyImportedC:native_stencil_value_source_shape(target, type_layouts) return byte_shape_for_type(self, target, type_layouts) end

    function Stencil.StencilProducerShape:native_stencil_producer_source_shape(_target, _type_layouts)
        internal_error("StencilProducerShape has no native source shape")
    end

    function Stencil.StencilProduceRange1D:native_stencil_producer_source_shape(target, type_layouts)
        return Native.NativeStencilProducerRange1DShape(value_shape_for_type(self.index_ty, target, type_layouts), self.step, self.order)
    end

    function Stencil.StencilProduceRangeND:native_stencil_producer_source_shape(_target, _type_layouts)
        return Native.NativeStencilProducerRangeNDShape(#(self.axes or {}))
    end

    function Stencil.StencilProduceWindowND:native_stencil_producer_source_shape(_target, _type_layouts)
        return Native.NativeStencilProducerWindowNDShape(#(self.axes or {}), #(self.windows or {}))
    end

    function Stencil.StencilProduceTiledND:native_stencil_producer_source_shape(_target, _type_layouts)
        return Native.NativeStencilProducerTiledNDShape(#(self.axes or {}), #(self.tile_sizes or {}))
    end

    function Stencil.StencilProducer:native_stencil_projection(input_or_target, maybe_type_layouts)
        local target = target_of(input_or_target)
        local type_layouts = maybe_type_layouts or type_layouts_of(input_or_target)
        return Native.NativeStencilProducerProjection(self, self.shape:native_stencil_producer_source_shape(target, type_layouts))
    end

    function Stencil.StencilProducer:native_stencil_axis(input_or_target, maybe_type_layouts)
        return Native.NativeStencilProducerSourceShapeAxis(self:native_stencil_projection(input_or_target, maybe_type_layouts).shape)
    end

    function Stencil.StencilAccessLayout:native_stencil_access_source_shape(_value, _target, _type_layouts)
        internal_error("StencilAccessLayout has no native source shape")
    end

    function Stencil.StencilLayoutScalar:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessScalarShape(value)
    end

    function Stencil.StencilLayoutContiguous:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessContiguousShape(value, self.stride)
    end

    function Stencil.StencilLayoutIndexed:native_stencil_access_source_shape(value, target, type_layouts)
        return Native.NativeStencilAccessIndexedShape(value, value_shape_for_type(self.index_ty, target, type_layouts), self.stride)
    end

    function Stencil.StencilLayoutAffine1D:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessAffine1DShape(value, self.scale)
    end

    function Stencil.StencilLayoutAffineND:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessAffineNDShape(value, #(self.terms or {}))
    end

    function Stencil.StencilLayoutFieldProjection:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessFieldProjectionShape(value, self.field_name)
    end

    function Stencil.StencilLayoutSoAComponent:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessSoAComponentShape(value, self.field_name)
    end

    function Stencil.StencilLayoutSliceDescriptor:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessSliceDescriptorShape(value)
    end

    function Stencil.StencilLayoutByteSpanDescriptor:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessByteSpanDescriptorShape(value)
    end

    function Stencil.StencilLayoutViewDescriptor:native_stencil_access_source_shape(value, _target, _type_layouts)
        return Native.NativeStencilAccessViewDescriptorShape(value, self.stride_const ~= nil)
    end

    function Stencil.StencilAccess:native_stencil_projection(input_or_target, maybe_type_layouts)
        local target = target_of(input_or_target)
        local type_layouts = maybe_type_layouts or type_layouts_of(input_or_target)
        local storage = storage_for_type(self.ty, target, type_layouts)
        local value = value_shape_for_type(self.ty, target, type_layouts)
        return Native.NativeStencilAccessProjection(self, storage, self.layout:native_stencil_access_source_shape(value, target, type_layouts))
    end

    function Stencil.StencilAccess:native_stencil_axis(input_or_target, maybe_type_layouts)
        return Native.NativeStencilAccessSourceShapeAxis(self:native_stencil_projection(input_or_target, maybe_type_layouts).shape)
    end

    function Stencil.StencilPointExpr:native_stencil_result_type(_descriptor)
        internal_error("StencilPointExpr has no native stencil result type")
    end

    function Stencil.StencilPointInput:native_stencil_result_type(descriptor)
        return access_for_ref(descriptor, self.access).ty
    end

    function Stencil.StencilPointWindowInput:native_stencil_result_type(descriptor)
        return access_for_ref(descriptor, self.access).ty
    end

    function Stencil.StencilPointConst:native_stencil_result_type(_descriptor) return self.ty end
    function Stencil.StencilPointUnary:native_stencil_result_type(descriptor) return self.result_ty or self.arg:native_stencil_result_type(descriptor) end
    function Stencil.StencilPointBinary:native_stencil_result_type(descriptor) return self.result_ty or self.left:native_stencil_result_type(descriptor) end
    function Stencil.StencilPointCast:native_stencil_result_type(_descriptor) return self.to end
    function Stencil.StencilPointPredicate:native_stencil_result_type(_descriptor) return self.result_ty end
    function Stencil.StencilPointCompare:native_stencil_result_type(_descriptor) return self.result_ty end
    function Stencil.StencilPointSelect:native_stencil_result_type(_descriptor) return self.result_ty end

    function Stencil.StencilPointExpr:native_stencil_point_source_shape(_descriptor, _target, _type_layouts)
        internal_error("StencilPointExpr has no native source shape")
    end

    function Stencil.StencilPointInput:native_stencil_point_source_shape(descriptor, target, type_layouts)
        return Native.NativeStencilPointInputShape(value_shape_for_type(access_for_ref(descriptor, self.access).ty, target, type_layouts))
    end

    function Stencil.StencilPointWindowInput:native_stencil_point_source_shape(descriptor, target, type_layouts)
        return Native.NativeStencilPointWindowInputShape(value_shape_for_type(access_for_ref(descriptor, self.access).ty, target, type_layouts), #(self.offsets or {}))
    end

    function Stencil.StencilPointConst:native_stencil_point_source_shape(_descriptor, target, type_layouts)
        return Native.NativeStencilPointConstShape(value_shape_for_type(self.ty, target, type_layouts))
    end

    function Stencil.StencilPointUnary:native_stencil_point_source_shape(descriptor, target, type_layouts)
        return Native.NativeStencilPointUnaryShape(self.op, value_shape_for_type(self:native_stencil_result_type(descriptor), target, type_layouts))
    end

    function Stencil.StencilPointBinary:native_stencil_point_source_shape(descriptor, target, type_layouts)
        return Native.NativeStencilPointBinaryShape(self.op, value_shape_for_type(self:native_stencil_result_type(descriptor), target, type_layouts))
    end

    function Stencil.StencilPointCast:native_stencil_point_source_shape(_descriptor, target, type_layouts)
        return Native.NativeStencilPointCastShape(self.op, value_shape_for_type(self.from, target, type_layouts), value_shape_for_type(self.to, target, type_layouts))
    end

    local function predicate_shape(pred, target, type_layouts)
        if pred.native_kernel_predicate_source_shape == nil then internal_error("StencilPredicate native kernel source-shape methods are not installed") end
        return pred:native_kernel_predicate_source_shape(target, type_layouts)
    end

    function Stencil.StencilPointPredicate:native_stencil_point_source_shape(descriptor, target, type_layouts)
        return Native.NativeStencilPointPredicateShape(predicate_shape(self.pred, target, type_layouts), value_shape_for_type(self:native_stencil_result_type(descriptor), target, type_layouts))
    end

    function Stencil.StencilPointCompare:native_stencil_point_source_shape(descriptor, target, type_layouts)
        return Native.NativeStencilPointCompareShape(self.cmp, value_shape_for_type(self:native_stencil_result_type(descriptor), target, type_layouts))
    end

    function Stencil.StencilPointSelect:native_stencil_point_source_shape(descriptor, target, type_layouts)
        return Native.NativeStencilPointSelectShape(predicate_shape(self.pred, target, type_layouts), value_shape_for_type(self:native_stencil_result_type(descriptor), target, type_layouts))
    end

    function Stencil.StencilPointExpr:native_stencil_projection(input_or_target, maybe_type_layouts, maybe_descriptor)
        local target = target_of(input_or_target)
        local type_layouts = maybe_type_layouts or type_layouts_of(input_or_target)
        local descriptor = maybe_descriptor or descriptor_of(input_or_target)
        local result_ty = self:native_stencil_result_type(descriptor)
        return Native.NativeStencilPointProjection(
            self,
            storage_for_type(result_ty, target, type_layouts),
            self:native_stencil_point_source_shape(descriptor, target, type_layouts)
        )
    end

    function Stencil.StencilPointExpr:native_stencil_axis(input_or_target, maybe_type_layouts, maybe_descriptor)
        return Native.NativeStencilPointSourceShapeAxis(self:native_stencil_projection(input_or_target, maybe_type_layouts, maybe_descriptor).shape)
    end

    function Stencil.StencilBody:native_stencil_projection(_input_or_target, _maybe_type_layouts, _maybe_descriptor)
        internal_error("StencilBody has no native projection")
    end

    function Stencil.StencilBodyPoint:native_stencil_projection(input_or_target, maybe_type_layouts, maybe_descriptor)
        local point = self.expr:native_stencil_projection(input_or_target, maybe_type_layouts, maybe_descriptor)
        return Native.NativeStencilBodyProjection(self, point, Native.NativeStencilBodyPointShape(point.shape))
    end

    function Stencil.StencilBody:native_stencil_axis(input_or_target, maybe_type_layouts, maybe_descriptor)
        return Native.NativeStencilBodySourceShapeAxis(self:native_stencil_projection(input_or_target, maybe_type_layouts, maybe_descriptor).shape)
    end

    function Stencil.StencilReductionSemantics:native_stencil_reducer_shape(target, type_layouts)
        internal_error("StencilReductionSemantics has no native reducer source shape")
    end

    function Stencil.StencilReduceFold:native_stencil_reducer_shape(target, type_layouts)
        return self.reducer:native_kernel_reducer_source_shape(target, type_layouts)
    end

    function Stencil.StencilReduceCount:native_stencil_reducer_shape(target, type_layouts)
        return Native.NativeKernelReducerSourceShape(Value.ReductionAdd, value_shape_for_type(Code.CodeTyIndex, target, type_layouts))
    end

    function Stencil.StencilReduceFind:native_stencil_reducer_shape(target, type_layouts)
        return Native.NativeKernelReducerSourceShape(Value.ReductionMin, value_shape_for_type(Code.CodeTyIndex, target, type_layouts))
    end

    function Stencil.StencilSink:native_stencil_sink_source_shape(_descriptor, _target, _type_layouts)
        internal_error("StencilSink has no native source shape")
    end

    function Stencil.StencilSinkStore:native_stencil_sink_source_shape(descriptor, target, type_layouts)
        local dst = access_for_ref(descriptor, self.dst):native_stencil_projection(target, type_layouts).shape
        return Native.NativeStencilSinkStoreShape(self.semantics, dst)
    end

    function Stencil.StencilSinkReduce:native_stencil_sink_source_shape(_descriptor, target, type_layouts)
        return Native.NativeStencilSinkReduceShape(value_shape_for_type(self.result_ty, target, type_layouts), self.scope, self.semantics)
    end

    function Stencil.StencilSinkScan:native_stencil_sink_source_shape(_descriptor, target, type_layouts)
        return Native.NativeStencilSinkScanShape(self.reducer:native_kernel_reducer_source_shape(target, type_layouts), self.mode, value_shape_for_type(self.result_ty, target, type_layouts))
    end

    function Stencil.StencilSinkScatterReduce:native_stencil_sink_source_shape(_descriptor, target, type_layouts)
        return Native.NativeStencilSinkScatterReduceShape(self.reducer:native_kernel_reducer_source_shape(target, type_layouts), self.conflicts, value_shape_for_type(self.result_ty, target, type_layouts))
    end

    function Stencil.StencilSink:native_stencil_projection(input_or_target, maybe_type_layouts, maybe_descriptor)
        local target = target_of(input_or_target)
        local type_layouts = maybe_type_layouts or type_layouts_of(input_or_target)
        local descriptor = maybe_descriptor or descriptor_of(input_or_target)
        return Native.NativeStencilSinkProjection(self, self:native_stencil_sink_source_shape(descriptor, target, type_layouts))
    end

    function Stencil.StencilSink:native_stencil_axis(input_or_target, maybe_type_layouts, maybe_descriptor)
        return Native.NativeStencilSinkSourceShapeAxis(self:native_stencil_projection(input_or_target, maybe_type_layouts, maybe_descriptor).shape)
    end

    function Stencil.StencilSchedule:native_stencil_schedule_source_shape(_target, _type_layouts)
        internal_error("StencilSchedule has no native source shape")
    end

    function Stencil.StencilScheduleScalar:native_stencil_schedule_source_shape(_target, _type_layouts)
        return Native.NativeStencilScheduleScalarShape(self.compiler)
    end

    function Stencil.StencilScheduleAutoVector:native_stencil_schedule_source_shape(_target, _type_layouts)
        return Native.NativeStencilScheduleAutoVectorShape(self.facts.trip_count)
    end

    function Stencil.StencilScheduleUnrolled:native_stencil_schedule_source_shape(_target, _type_layouts)
        return Native.NativeStencilScheduleUnrolledShape(self.factor, self.facts.trip_count)
    end

    function Stencil.StencilScheduleVector:native_stencil_schedule_source_shape(_target, _type_layouts)
        return Native.NativeStencilScheduleVectorShape(self.feature, self.lane_policy, self.required_alignment, self.tail, self.reduction, self.vector_unroll, self.interleave)
    end

    function Stencil.StencilSchedule:native_stencil_projection(input_or_target, maybe_type_layouts)
        local target = target_of(input_or_target)
        local type_layouts = maybe_type_layouts or type_layouts_of(input_or_target)
        return Native.NativeStencilScheduleProjection(self, self:native_stencil_schedule_source_shape(target, type_layouts))
    end

    function Stencil.StencilSchedule:native_stencil_axis(input_or_target, maybe_type_layouts)
        return Native.NativeStencilScheduleSourceShapeAxis(self:native_stencil_projection(input_or_target, maybe_type_layouts).shape)
    end

    function Stencil.StencilDescriptor:native_stencil_projection(input_or_target, maybe_type_layouts)
        local target = target_of(input_or_target)
        local type_layouts = maybe_type_layouts or type_layouts_of(input_or_target)
        local access_projections = {}
        for _, access in ipairs(self.accesses or {}) do
            access_projections[#access_projections + 1] = access:native_stencil_projection(target, type_layouts)
        end
        return Native.NativeStencilDescriptorProjection(
            self,
            self.producer:native_stencil_projection(target, type_layouts),
            access_projections,
            self.body:native_stencil_projection(target, type_layouts, self),
            self.sink:native_stencil_projection(target, type_layouts, self)
        )
    end

    function Stencil.StencilInstance:native_stencil_projection(input_or_target, maybe_type_layouts)
        local target = target_of(input_or_target)
        local type_layouts = maybe_type_layouts or type_layouts_of(input_or_target)
        return Native.NativeStencilInstanceProjection(
            self,
            self.descriptor:native_stencil_projection(target, type_layouts),
            self.schedule:native_stencil_projection(target, type_layouts),
            self.abi
        )
    end

    function Stencil.StencilInstance:plan_native_copy(input)
        return self.descriptor:select_native_template_graph(input)
    end

    T._lalin_api_cache.native_stencil_methods = api
    return api
end

return bind_context
