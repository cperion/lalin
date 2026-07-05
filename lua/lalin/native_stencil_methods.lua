local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_stencil_methods ~= nil then return T._lalin_api_cache.native_stencil_methods end

    require("lalin.native_template_sources")(T)

    local Native = T.LalinNative
    local Stencil = T.LalinStencil
    local Code = T.LalinCode
    local Value = T.LalinValue
    local Support = require("lalin.native_template_support")(T)
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

    local function template_value_id(text)
        return Native.NativeTemplateValueId("native.stencil." .. text)
    end

    local function scalar_storage(scalar)
        return Native.NativeStorageLayout(Native.NativeScalarValueRepresentation(scalar), scalar:native_size_bytes(), scalar:native_frame_alignment())
    end

    local function pointer_storage(target)
        local scalar = Support.scalar_pointer(target.pointer_bits)
        return Native.NativeStorageLayout(Native.NativeUntypedPointerValueRepresentation(scalar), scalar:native_size_bytes(), scalar:native_frame_alignment())
    end

    local function value_shape_storage(shape, target)
        if asdl.isa(shape, Native.NativeStencilValueScalarShape) then return scalar_storage(shape.scalar) end
        if asdl.isa(shape, Native.NativeStencilValuePointerShape) then return Native.NativeStorageLayout(Native.NativeUntypedPointerValueRepresentation(shape.pointer), shape.pointer:native_size_bytes(), shape.pointer:native_frame_alignment()) end
        if asdl.isa(shape, Native.NativeStencilValueBytesShape) then return Native.NativeStorageLayout(Native.NativeObjectStorageRepresentation(Code.CodeTyVoid, shape.size, shape.alignment), shape.size, shape.alignment) end
        return Native.NativeStorageLayout(Native.NativeObjectStorageRepresentation(Code.CodeTyVoid, 0, 1), 0, 1)
    end

    local function frame_entry(role, storage, text)
        return Native.NativeStencilFrameEntry(role, storage, template_value_id(text))
    end

    local function align_to(offset, alignment)
        if alignment == nil or alignment <= 1 then return offset end
        local rem = offset % alignment
        if rem == 0 then return offset end
        return offset + alignment - rem
    end

    local function stencil_frame_layout(entries)
        local slots = {}
        local slot_entries = {}
        local offset = 0
        local frame_alignment = 16
        for i, entry in ipairs(entries or {}) do
            local storage = entry.storage
            local alignment = storage.alignment or 1
            frame_alignment = math.max(frame_alignment, alignment)
            offset = align_to(offset, alignment)
            local slot = Native.NativeFrameSlot(
                Native.NativeFrameSlotId("native.stencil.frame.slot." .. tostring(i - 1) .. "." .. entry.value.text),
                storage.representation,
                offset,
                storage.size,
                alignment
            )
            slots[#slots + 1] = slot
            slot_entries[#slot_entries + 1] = Native.NativeStencilFrameSlotEntry(entry, slot)
            offset = offset + (storage.size or 0)
        end
        local size = align_to(offset, frame_alignment)
        return Native.NativeStencilFrameLayout(slot_entries, Native.NativeFrameLayout(slots, size, frame_alignment))
    end

    local function slot_for_frame_entry(lowering, frame_entry_value)
        for _, entry in ipairs(lowering.frame.entries or {}) do
            if entry.entry == frame_entry_value then return entry.slot end
        end
        internal_error("stencil lowering has no frame slot for " .. tostring(frame_entry_value and frame_entry_value.value and frame_entry_value.value.text))
    end

    local function frame_offset_for_entry(input, frame_entry_value)
        return slot_for_frame_entry(input.lowering, frame_entry_value).offset
    end

    local function placement_for_frame_entry(input, frame_entry_value)
        local slot = slot_for_frame_entry(input.lowering, frame_entry_value)
        return Native.NativeValuePlacement(frame_entry_value.value, frame_entry_value.storage.representation, Native.NativeValueFrameSlotLocation(slot))
    end

    local function append_frame_value_edge(input, node, frame_entry_value)
        local slot = slot_for_frame_entry(input.lowering, frame_entry_value)
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(
            frame_entry_value.value,
            node.id,
            node.id,
            frame_entry_value.storage.representation,
            slot
        )
    end

    local function hole_binding(id, coordinate)
        local hole_id = Native.NativePatchHoleId(id)
        return function(node_id, instance)
            return Native.NativePatchBinding(node_id, instance, Native.NativePatchBindingHoleId(hole_id), coordinate)
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

    local function materialize_bindings(node_id, instance, binding_specs)
        local bindings = {}
        for _, spec in ipairs(binding_specs or {}) do bindings[#bindings + 1] = spec(node_id, instance) end
        return bindings
    end

    function Native.NativeStencilProducerSourceShape:native_stencil_template_family(plan)
        local name = "producer." .. self:native_stencil_producer_token()
        return Support.family(Support.stencil_family_id(name), Native.NativeRoleStencilProducer, { Support.axis_target(plan.target), Support.axis_stencil_producer(Native.NativeStencilProducerSourceShapeAxis(self)) }, Support.protocol_void_none())
    end

    function Native.NativeStencilAccessSourceShape:native_stencil_template_family(plan)
        local name = "access." .. self:native_stencil_access_token()
        return Support.family(Support.stencil_family_id(name), Native.NativeRoleStencilAccess, { Support.axis_target(plan.target), Support.axis_stencil_access(Native.NativeStencilAccessSourceShapeAxis(self)) }, Support.protocol_void_none())
    end

    function Native.NativeStencilPointSourceShape:native_stencil_template_family(plan)
        local name = "point." .. self:native_stencil_point_token()
        return Support.family(Support.stencil_family_id(name), Native.NativeRoleStencilPoint, { Support.axis_target(plan.target), Support.axis_stencil_point(Native.NativeStencilPointSourceShapeAxis(self)) }, Support.protocol_void_none())
    end

    function Native.NativeStencilBodySourceShape:native_stencil_template_family(plan)
        local name = "body." .. self:native_stencil_body_token()
        return Support.family(Support.stencil_family_id(name), Native.NativeRoleStencilBody, { Support.axis_target(plan.target), Support.axis_stencil_body(Native.NativeStencilBodySourceShapeAxis(self)) }, Support.protocol_void_none())
    end

    function Native.NativeStencilSinkSourceShape:native_stencil_template_family(plan)
        local name = "sink." .. self:native_stencil_sink_token()
        return Support.family(Support.stencil_family_id(name), Native.NativeRoleStencilSink, { Support.axis_target(plan.target), Support.axis_stencil_sink(Native.NativeStencilSinkSourceShapeAxis(self)) }, Support.protocol_void_none())
    end

    function Native.NativeStencilScheduleSourceShape:native_stencil_template_family(plan)
        local name = "schedule." .. self:native_stencil_schedule_token()
        return Support.family(Support.stencil_family_id(name), Native.NativeRoleStencilSchedule, { Support.axis_target(plan.target), Support.axis_stencil_schedule(Native.NativeStencilScheduleSourceShapeAxis(self)) }, Support.protocol_void_none())
    end

    local function stencil_node_id(state, role)
        return Native.NativeTemplateNodeId("native.stencil.node." .. tostring(#state.nodes + 1) .. "." .. role)
    end

    local function stencil_instance_id(node_id)
        return Native.NativeTemplateInstanceId("native.stencil.instance." .. node_id.text)
    end

    local function append_stencil_node(input, role, shape, outputs, binding_specs)
        local node_id = stencil_node_id(input.state, role)
        local instance = stencil_instance_id(node_id)
        local family = shape:native_stencil_template_family(input.plan)
        local node = Native.NativeTemplateNode(node_id, instance, family, {}, outputs or {}, materialize_bindings(node_id, instance, binding_specs))
        input.state.nodes[#input.state.nodes + 1] = node
        return node
    end

    local function append_next_edge(input, from_node, to_node)
        input.state.control_edges[#input.state.control_edges + 1] = Native.NativeContinuationEdge(from_node.id, to_node.id, Support.next_continuation_symbol())
        return to_node
    end

    local function append_loopback_edge(input, from_node, to_node)
        input.state.control_edges[#input.state.control_edges + 1] = Native.NativeLoopBackedgeEdge(from_node.id, to_node.id, Support.next_continuation_symbol())
        return to_node
    end

    local function access_entry(input, ref)
        for _, entry in ipairs(input.lowering.accesses or {}) do
            if entry.access == ref then return entry end
            if entry.access.name == ref.name then return entry end
        end
        internal_error("stencil lowering has no access address entry for " .. tostring(ref and ref.name))
    end

    local function producer_entry(input, axis)
        for _, entry in ipairs(input.lowering.producers or {}) do
            if entry.axis == axis then return entry end
        end
        internal_error("stencil lowering has no producer loop entry for axis " .. tostring(axis))
    end

    local function point_entry(input, expr)
        for _, entry in ipairs(input.lowering.point_values or {}) do
            if entry.expr == expr then return entry end
        end
        internal_error("stencil lowering has no point value entry")
    end

    local function value_expr_const_i32(expr, default)
        if expr == nil then return default or 0 end
        if asdl.isa(expr, Value.ValueExprConst) and asdl.isa(expr.const, Code.CodeConstLiteral) and expr.const.literal.text ~= nil then
            local parsed = tonumber(expr.const.literal.text)
            if parsed ~= nil then return parsed end
        end
        internal_error("stencil native lowering requires a literal i32 source for this static stencil coordinate")
    end

    function Stencil.StencilProducerShape:append_native_stencil_producer_bindings(_input, _id_base, _bindings)
        internal_error("stencil producer shape has no native bindings")
    end

    function Stencil.StencilProduceRange1D:append_native_stencil_producer_bindings(input, id_base, bindings)
        local loop = producer_entry(input, 0)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".counter", loop.counter)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".stop", loop.stop)
    end

    local function append_ranked_producer_bindings(shape, input, id_base, bindings)
        for axis = 0, (shape.rank or #(shape.axes or {})) - 1 do
            local loop = producer_entry(input, axis)
            bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".axis" .. tostring(axis) .. ".counter", loop.counter)
            bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".axis" .. tostring(axis) .. ".stop", loop.stop)
        end
    end

    function Stencil.StencilProduceRangeND:append_native_stencil_producer_bindings(input, id_base, bindings) append_ranked_producer_bindings(self, input, id_base, bindings) end
    function Stencil.StencilProduceWindowND:append_native_stencil_producer_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".window_count", #(self.windows or {}))
        append_ranked_producer_bindings(self, input, id_base, bindings)
    end
    function Stencil.StencilProduceTiledND:append_native_stencil_producer_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".tile_count", #(self.tile_sizes or {}))
        append_ranked_producer_bindings(self, input, id_base, bindings)
    end

    function Stencil.StencilAccessLayout:append_native_stencil_access_bindings(_input, _access_entry, _id_base, _bindings)
        internal_error("stencil access layout has no native bindings")
    end

    local function bind_base_index_elem(input, access_entry_value, id_base, bindings, elem_size)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", access_entry_value.base)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".index", access_entry_value.index)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".elem_size", elem_size)
    end

    function Stencil.StencilLayoutScalar:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", access_entry_value.base)
    end

    function Stencil.StencilLayoutContiguous:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bind_base_index_elem(input, access_entry_value, id_base, bindings, access_entry_value.address.storage.size)
    end

    function Stencil.StencilLayoutIndexed:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bind_base_index_elem(input, access_entry_value, id_base, bindings, access_entry_value.address.storage.size)
    end

    function Stencil.StencilLayoutAffine1D:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", access_entry_value.base)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".index", access_entry_value.index)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".offset", value_expr_const_i32(self.offset, 0))
    end

    function Stencil.StencilLayoutAffineND:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        if self.offset ~= nil then internal_error("stencil affine-ND dynamic/static offset needs a source-shape hole before lowering") end
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", access_entry_value.base)
        for i, term in ipairs(self.terms or {}) do
            local ordinal = i - 1
            local loop = producer_entry(input, term.axis.index)
            bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".term" .. tostring(ordinal), loop.counter)
            bindings[#bindings + 1] = imm32_binding(id_base .. ".coeff" .. tostring(ordinal), term.coeff)
        end
    end

    function Stencil.StencilLayoutFieldProjection:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", access_entry_value.base)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".field_offset", self.field_offset)
    end

    function Stencil.StencilLayoutSoAComponent:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".base", access_entry_value.base)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".component_offset", self.component_index)
    end

    function Stencil.StencilLayoutSliceDescriptor:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".descriptor", access_entry_value.descriptor)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".index", access_entry_value.index)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".elem_size", access_entry_value.address.storage.size)
    end

    function Stencil.StencilLayoutByteSpanDescriptor:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".descriptor", access_entry_value.descriptor)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".byte_offset", access_entry_value.byte_offset)
    end

    function Stencil.StencilLayoutViewDescriptor:append_native_stencil_access_bindings(input, access_entry_value, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".descriptor", access_entry_value.descriptor)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".index", access_entry_value.index)
        if self.stride_const ~= nil then
            bindings[#bindings + 1] = imm32_binding(id_base .. ".stride_const", self.stride_const)
        else
            bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".stride", access_entry_value.stride)
        end
    end

    function Code.CodeConst:native_stencil_patch_coordinate(_target)
        internal_error("stencil constant leaf has no patch coordinate")
    end

    function Code.CodeConstLiteral:native_stencil_patch_coordinate(target)
        local scalar = self.ty:native_machine_scalar(target)
        if self.literal.native_patch_coordinate_for_scalar == nil then internal_error("stencil literal has no scalar patch coordinate") end
        return self.literal:native_patch_coordinate_for_scalar(scalar)
    end

    function Code.CodeConstNull:native_stencil_patch_coordinate(target)
        local scalar = self.ty:native_machine_scalar(target)
        if asdl.isa(scalar, Native.NativeScalarPointer) then return Native.NativePatchPointer64(0) end
        return scalar:native_null_patch_coordinate()
    end

    function Value.ValueExpr:native_stencil_patch_coordinate(_target)
        internal_error("stencil value expression is not a patchable constant")
    end

    function Value.ValueExprConst:native_stencil_patch_coordinate(target)
        return self.const:native_stencil_patch_coordinate(target)
    end

    function Stencil.StencilPointExpr:append_native_stencil_point_bindings(_input, _id_base, _bindings)
        internal_error("stencil point expression has no native bindings")
    end

    function Stencil.StencilPointInput:append_native_stencil_point_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", access_entry(input, self.access).address)
    end

    function Stencil.StencilPointWindowInput:append_native_stencil_point_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", access_entry(input, self.access).address)
        bindings[#bindings + 1] = imm32_binding(id_base .. ".window_offset_count", #(self.offsets or {}))
    end

    function Stencil.StencilPointConst:append_native_stencil_point_bindings(input, id_base, bindings)
        local scalar = value_shape_for_type(self.ty, input.plan.target, input.lowering.type_layouts):native_stencil_c_scalar(input.plan.target)
        if scalar == nil then internal_error("stencil const point lowering needs scalar storage") end
        bindings[#bindings + 1] = hole_binding(scalar_constant_hole_id(id_base .. ".const", scalar), self.value:native_stencil_patch_coordinate(input.plan.target))
    end

    function Stencil.StencilPointUnary:append_native_stencil_point_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", point_entry(input, self.arg).frame)
    end

    function Stencil.StencilPointCast:append_native_stencil_point_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".src", point_entry(input, self.arg).frame)
    end

    function Stencil.StencilPointPredicate:append_native_stencil_point_bindings(input, id_base, bindings)
        if self.pred.append_native_kernel_predicate_bindings == nil then internal_error("stencil predicate native bindings are not installed") end
        self.pred:append_native_kernel_predicate_bindings(input, id_base .. ".pred", bindings, point_entry(input, self.arg))
    end

    function Stencil.StencilPointBinary:append_native_stencil_point_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".lhs", point_entry(input, self.left).frame)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".rhs", point_entry(input, self.right).frame)
    end

    function Stencil.StencilPointCompare:append_native_stencil_point_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".lhs", point_entry(input, self.left).frame)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".rhs", point_entry(input, self.right).frame)
    end

    function Stencil.StencilPointSelect:append_native_stencil_point_bindings(input, id_base, bindings)
        if self.pred.append_native_kernel_predicate_bindings == nil then internal_error("stencil predicate native bindings are not installed") end
        self.pred:append_native_kernel_predicate_bindings(input, id_base .. ".pred", bindings, point_entry(input, self.cond))
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".true", point_entry(input, self.then_expr).frame)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".false", point_entry(input, self.else_expr).frame)
    end

    local function append_point_node(input, expr)
        local children = {}
        if asdl.isa(expr, Stencil.StencilPointUnary) or asdl.isa(expr, Stencil.StencilPointCast) or asdl.isa(expr, Stencil.StencilPointPredicate) then
            children[#children + 1] = append_point_node(input, expr.arg)
        elseif asdl.isa(expr, Stencil.StencilPointBinary) or asdl.isa(expr, Stencil.StencilPointCompare) then
            children[#children + 1] = append_point_node(input, expr.left)
            children[#children + 1] = append_point_node(input, expr.right)
        elseif asdl.isa(expr, Stencil.StencilPointSelect) then
            children[#children + 1] = append_point_node(input, expr.cond)
            children[#children + 1] = append_point_node(input, expr.then_expr)
            children[#children + 1] = append_point_node(input, expr.else_expr)
        end
        local projection = expr:native_stencil_projection(input.plan.target, input.lowering.type_layouts, input.lowering.projection.instance.descriptor)
        local output_entry = point_entry(input, expr).frame
        local id_base = "native.hole.stencil.point." .. projection.shape:native_stencil_point_token()
        local bindings = { frame_entry_binding(input, id_base .. ".dst", output_entry) }
        expr:append_native_stencil_point_bindings(input, id_base, bindings)
        local node = append_stencil_node(input, "point", projection.shape, { placement_for_frame_entry(input, output_entry) }, bindings)
        append_frame_value_edge(input, node, output_entry)
        if #children > 0 then append_next_edge(input, children[#children], node) end
        return node
    end

    function Stencil.StencilBody:append_native_stencil_body_templates(_input)
        internal_error("stencil body has no native lowering")
    end

    function Stencil.StencilBodyPoint:append_native_stencil_body_templates(input)
        local point_node = append_point_node(input, self.expr)
        local projection = self:native_stencil_projection(input.plan.target, input.lowering.type_layouts, input.lowering.projection.instance.descriptor)
        local body_node = append_stencil_node(input, "body", projection.shape, {}, {})
        append_next_edge(input, point_node, body_node)
        return { point_node, body_node }
    end

    function Stencil.StencilSink:append_native_stencil_sink_bindings(_input, _id_base, _bindings)
        internal_error("stencil sink has no native bindings")
    end

    function Stencil.StencilSinkStore:append_native_stencil_sink_bindings(input, id_base, bindings)
        access_for_ref(input.lowering.projection.instance.descriptor, self.dst).layout:append_native_stencil_access_bindings(input, access_entry(input, self.dst), id_base .. ".dst", bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", input.lowering.body_value.frame)
    end

    function Stencil.StencilSinkReduce:append_native_stencil_sink_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".state", input.lowering.sink_state.state)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", input.lowering.body_value.frame)
    end

    function Stencil.StencilSinkScan:append_native_stencil_sink_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".state", input.lowering.sink_state.state)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".dst", input.lowering.sink_state.value)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", input.lowering.body_value.frame)
    end

    function Stencil.StencilSinkScatterReduce:append_native_stencil_sink_bindings(input, id_base, bindings)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".address", access_entry(input, self.dst).address)
        bindings[#bindings + 1] = frame_entry_binding(input, id_base .. ".value", input.lowering.body_value.frame)
    end

    function Stencil.StencilSchedule:append_native_schedule_template(input)
        local projection = self:native_stencil_projection(input.plan.target, input.lowering.type_layouts)
        return append_stencil_node(input, "schedule", projection.shape, {}, {})
    end

    function Stencil.StencilProducerShape:append_native_producer_template(input)
        local projection = self:native_stencil_producer_source_shape(input.plan.target, input.lowering.type_layouts)
        local id_base = "native.hole.stencil.producer." .. projection:native_stencil_producer_token()
        local bindings = {}
        self:append_native_stencil_producer_bindings(input, id_base, bindings)
        return append_stencil_node(input, "producer", projection, {}, bindings)
    end

    function Stencil.StencilAccess:append_native_access_template(input)
        local projection = self:native_stencil_projection(input.plan.target, input.lowering.type_layouts)
        local entry = access_entry(input, Stencil.StencilAccessRef(self.name))
        local id_base = "native.hole.stencil.access." .. projection.shape:native_stencil_access_token()
        local bindings = { frame_entry_binding(input, id_base .. ".dst", entry.address) }
        self.layout:append_native_stencil_access_bindings(input, entry, id_base, bindings)
        local node = append_stencil_node(input, "access", projection.shape, { placement_for_frame_entry(input, entry.address) }, bindings)
        append_frame_value_edge(input, node, entry.address)
        return node
    end

    function Stencil.StencilSink:append_native_sink_template(input)
        local projection = self:native_stencil_projection(input.plan.target, input.lowering.type_layouts, input.lowering.projection.instance.descriptor)
        local id_base = "native.hole.stencil.sink." .. projection.shape:native_stencil_sink_token()
        local bindings = {}
        self:append_native_stencil_sink_bindings(input, id_base, bindings)
        return append_stencil_node(input, "sink", projection.shape, {}, bindings)
    end

    local function collect_point_entries(expr, target, type_layouts, descriptor, entries, point_entries)
        if asdl.isa(expr, Stencil.StencilPointUnary) or asdl.isa(expr, Stencil.StencilPointCast) or asdl.isa(expr, Stencil.StencilPointPredicate) then
            collect_point_entries(expr.arg, target, type_layouts, descriptor, entries, point_entries)
        elseif asdl.isa(expr, Stencil.StencilPointBinary) or asdl.isa(expr, Stencil.StencilPointCompare) then
            collect_point_entries(expr.left, target, type_layouts, descriptor, entries, point_entries)
            collect_point_entries(expr.right, target, type_layouts, descriptor, entries, point_entries)
        elseif asdl.isa(expr, Stencil.StencilPointSelect) then
            collect_point_entries(expr.cond, target, type_layouts, descriptor, entries, point_entries)
            collect_point_entries(expr.then_expr, target, type_layouts, descriptor, entries, point_entries)
            collect_point_entries(expr.else_expr, target, type_layouts, descriptor, entries, point_entries)
        end
        local ordinal = #point_entries
        local projection = expr:native_stencil_projection(target, type_layouts, descriptor)
        local entry = frame_entry(Native.NativeStencilFramePointValue(ordinal), projection.result_storage, "point." .. tostring(ordinal))
        entries[#entries + 1] = entry
        point_entries[#point_entries + 1] = Native.NativeStencilPointValueEntry(ordinal, expr, entry)
    end

    local function append_access_lowering_entry(access, target, type_layouts, entries, access_entries)
        local ref = Stencil.StencilAccessRef(access.name)
        local pointer = pointer_storage(target)
        local index = scalar_storage(Support.scalar_index(target.pointer_bits))
        local base = frame_entry(Native.NativeStencilFrameAccessBase(ref), pointer, "access." .. access.name .. ".base")
        local address = frame_entry(Native.NativeStencilFrameAccessAddress(ref), pointer, "access." .. access.name .. ".address")
        local index_entry = frame_entry(Native.NativeStencilFrameAccessIndex(ref), index, "access." .. access.name .. ".index")
        local stride_entry = frame_entry(Native.NativeStencilFrameAccessStride(ref), index, "access." .. access.name .. ".stride")
        local descriptor_entry = frame_entry(Native.NativeStencilFrameAccessDescriptor(ref), pointer, "access." .. access.name .. ".descriptor")
        local byte_offset_entry = frame_entry(Native.NativeStencilFrameAccessByteOffset(ref), index, "access." .. access.name .. ".byte_offset")
        entries[#entries + 1] = base
        entries[#entries + 1] = address
        entries[#entries + 1] = index_entry
        entries[#entries + 1] = stride_entry
        entries[#entries + 1] = descriptor_entry
        entries[#entries + 1] = byte_offset_entry
        access_entries[#access_entries + 1] = Native.NativeStencilAccessAddressEntry(ref, base, index_entry, stride_entry, descriptor_entry, byte_offset_entry, address)
    end

    local function producer_rank(producer)
        local shape = producer.shape
        if asdl.isa(shape, Stencil.StencilProduceRange1D) then return 1 end
        if shape.axes ~= nil then return #(shape.axes or {}) end
        return shape.rank or 0
    end

    function Stencil.StencilInstance:native_stencil_lowering_input(plan, type_layouts, addresses)
        type_layouts = type_layouts or Native.NativeCodeTypeLayoutPlan({}, {}, {})
        addresses = addresses or Native.NativeModuleAddressPlan({}, {}, {}, {}, {}, {})
        local projection = self:native_stencil_projection(plan.target, type_layouts)
        local entries = {}
        for i, ty in ipairs(self.abi.params or {}) do
            entries[#entries + 1] = frame_entry(Native.NativeStencilFrameAbiParam(i - 1), storage_for_type(ty, plan.target, type_layouts), "abi.param." .. tostring(i - 1))
        end
        local producer_entries = {}
        local index_storage = scalar_storage(Support.scalar_index(plan.target.pointer_bits))
        for axis = 0, producer_rank(self.descriptor.producer) - 1 do
            local counter = frame_entry(Native.NativeStencilFrameProducerCounter(axis), index_storage, "producer.axis" .. tostring(axis) .. ".counter")
            local stop = frame_entry(Native.NativeStencilFrameProducerStop(axis), index_storage, "producer.axis" .. tostring(axis) .. ".stop")
            entries[#entries + 1] = counter
            entries[#entries + 1] = stop
            producer_entries[#producer_entries + 1] = Native.NativeStencilProducerLoopEntry(axis, counter, stop)
        end
        local access_entries = {}
        for _, access in ipairs(self.descriptor.accesses or {}) do append_access_lowering_entry(access, plan.target, type_layouts, entries, access_entries) end
        local point_entries = {}
        collect_point_entries(self.descriptor.body.expr, plan.target, type_layouts, self.descriptor, entries, point_entries)
        local body_value = point_entries[#point_entries]
        local state_storage = body_value and body_value.frame.storage or scalar_storage(Support.scalar_i32())
        local state = frame_entry(Native.NativeStencilFrameSinkState(0), state_storage, "sink.state")
        local value = frame_entry(Native.NativeStencilFrameSinkState(1), state_storage, "sink.value")
        entries[#entries + 1] = state
        entries[#entries + 1] = value
        local sink_state = Native.NativeStencilSinkStateEntry(0, self.descriptor.sink, state, value)
        return Native.NativeStencilLoweringInput(self, projection, type_layouts, self.abi, stencil_frame_layout(entries), producer_entries, access_entries, point_entries, body_value, sink_state, addresses)
    end

    local function append_chain_edges(input, nodes)
        for i = 1, #nodes - 1 do append_next_edge(input, nodes[i], nodes[i + 1]) end
    end

    function Stencil.StencilDescriptor:select_native_template_graph(input, lowering)
        if lowering == nil then internal_error("StencilDescriptor:select_native_template_graph requires NativeStencilLoweringInput") end
        if lowering.projection.descriptor.descriptor ~= self then internal_error("NativeStencilLoweringInput descriptor does not match StencilDescriptor") end
        local state = Native.NativeStencilGraphBuilderState({}, {}, {}, {})
        local graph_input = Native.NativeStencilGraphBuildInput(input, lowering, state)
        local schedule_node = lowering.instance.schedule:append_native_schedule_template(graph_input)
        local producer_node = self.producer.shape:append_native_producer_template(graph_input)
        append_next_edge(graph_input, schedule_node, producer_node)
        local work_nodes = {}
        for _, access in ipairs(self.accesses or {}) do work_nodes[#work_nodes + 1] = access:append_native_access_template(graph_input) end
        local body_nodes = self.body:append_native_stencil_body_templates(graph_input)
        for _, node in ipairs(body_nodes or {}) do work_nodes[#work_nodes + 1] = node end
        local sink_node = self.sink:append_native_sink_template(graph_input)
        work_nodes[#work_nodes + 1] = sink_node
        append_chain_edges(graph_input, work_nodes)
        if #work_nodes > 0 then
            state.control_edges[#state.control_edges + 1] = Native.NativeConditionalBranchEdge(producer_node.id, work_nodes[1].id, Support.then_continuation_symbol(), schedule_node.id, Support.else_continuation_symbol(), Native.NativeTemplateValueId("native.stencil.producer.condition"))
            append_loopback_edge(graph_input, work_nodes[#work_nodes], producer_node)
        else
            state.control_edges[#state.control_edges + 1] = Native.NativeConditionalBranchEdge(producer_node.id, producer_node.id, Support.then_continuation_symbol(), schedule_node.id, Support.else_continuation_symbol(), Native.NativeTemplateValueId("native.stencil.producer.condition"))
        end
        state.exits[#state.exits + 1] = schedule_node.id
        return Native.NativeTemplateGraph(input.target, Native.NativeCallVoid, lowering.frame.frame, state.nodes, state.control_edges, state.value_edges, lowering.addresses, schedule_node.id, state.exits)
    end

    function Stencil.StencilInstance:plan_native_copy(input)
        local lowering = self:native_stencil_lowering_input(input, type_layouts_of(input), nil)
        return self.descriptor:select_native_template_graph(input, lowering)
    end

    T._lalin_api_cache.native_stencil_methods = api
    return api
end

return bind_context
