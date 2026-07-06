local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_code_methods ~= nil then return T._lalin_api_cache.native_code_methods end

    local Code = T.LalinCode
    local Core = T.LalinCore
    local Native = T.LalinNative
    local Sem = T.LalinSem
    local C = T.LalinC
    local Support = require("lalin.native_template_support")(T)
    require("lalin.native_template_sources")(T)
    local CodeType = require("lalin.code_type")(T)
    local TypeSizeAlign = require("lalin.type_size_align")(T)
    local api = {}

    local function internal_error(message)
        error("lalin.native_code_methods: " .. message, 3)
    end

    local function scalar_token(scalar)
        return scalar:native_scalar_token()
    end

    local function native_value_id(value)
        return Native.NativeTemplateValueId("native.code.value." .. value.text)
    end

    local function node_id_for(state, role)
        return Native.NativeTemplateNodeId("native.code.node." .. tostring(#state.control_plan.nodes + 1) .. "." .. role)
    end

    local function instance_id_for(node_id)
        return Native.NativeTemplateInstanceId("native.code.instance." .. node_id.text)
    end

    local function align_up(offset, alignment)
        if alignment <= 1 then return offset end
        local rem = offset % alignment
        if rem == 0 then return offset end
        return offset + (alignment - rem)
    end

    local function target_frame_alignment(target)
        if asdl.isa(target.arch, Native.NativeArchX64) and asdl.isa(target.abi, Native.NativeAbiSysV) then return 16 end
        internal_error("native Code frame layout is only defined for the x64 SysV proof-slice target")
    end

    local function scalar_size(scalar)
        return scalar:native_size_bytes()
    end

    local function frame_slot_id(value, suffix)
        return Native.NativeFrameSlotId("native.frame.slot." .. value.text .. (suffix and ("." .. suffix) or ""))
    end

    local function local_frame_slot_id(local_id)
        return Native.NativeFrameSlotId("native.frame.local." .. local_id.text)
    end

    local function scalar_value_representation(scalar)
        return Native.NativeScalarValueRepresentation(scalar)
    end

    function Native.NativeValueRepresentation:native_scalar_rep()
        internal_error("native value representation is not a scalar/address value")
    end

    function Native.NativeScalarValueRepresentation:native_scalar_rep()
        return self.scalar
    end

    function Native.NativeAddressValueRepresentation:native_scalar_rep()
        return self.address_scalar
    end

    function Native.NativeOpaquePointerValueRepresentation:native_scalar_rep()
        return self.address_scalar
    end

    function Native.NativeUntypedPointerValueRepresentation:native_scalar_rep()
        return self.address_scalar
    end

    local function scalar_storage_layout_for_frame(scalar)
        return Native.NativeStorageLayout(scalar_value_representation(scalar), scalar_size(scalar), scalar:native_frame_alignment())
    end

    local function make_frame_slot_for_layout(value, layout, offset, suffix)
        return Native.NativeFrameSlot(
            frame_slot_id(value, suffix),
            layout.representation,
            offset,
            layout.size,
            layout.alignment
        )
    end

    local function make_frame_slot(value, scalar, offset, suffix)
        return make_frame_slot_for_layout(value, scalar_storage_layout_for_frame(scalar), offset, suffix)
    end

    local function value_frame_placement_for_layout(value, layout, slot)
        return Native.NativeValuePlacement(
            native_value_id(value),
            layout.representation,
            Native.NativeValueFrameSlotLocation(slot)
        )
    end

    local function value_frame_placement(value, scalar, slot)
        return value_frame_placement_for_layout(value, scalar_storage_layout_for_frame(scalar), slot)
    end

    local function find_placement_for_value(state, value)
        for _, entry in ipairs(state.value_locations.entries) do
            if entry.value == value then return entry.placement end
        end
    end

    local function placement_for_value(state, value)
        local placement = find_placement_for_value(state, value)
        if placement ~= nil then return placement end
        internal_error("no native frame placement for CodeValueId " .. tostring(value and value.text))
    end

    local function set_placement(state, value, placement)
        for i, entry in ipairs(state.value_locations.entries) do
            if entry.value == value then
                state.value_locations.entries[i] = Native.NativeCodeValuePlacementEntry(value, placement.representation, placement)
                return placement
            end
        end
        state.value_locations.entries[#state.value_locations.entries + 1] = Native.NativeCodeValuePlacementEntry(value, placement.representation, placement)
        return placement
    end

    local function append_frame_slot(state, value, slot)
        state.frame_layout_plan.slots[#state.frame_layout_plan.slots + 1] = slot
        state.frame_layout_plan.value_slots[#state.frame_layout_plan.value_slots + 1] = Native.NativeFrameValueSlotEntry(value, slot.representation, slot)
        local end_offset = slot.offset + slot.size
        if end_offset > state.frame_layout_plan.next_frame_offset then state.frame_layout_plan.next_frame_offset = end_offset end
        return slot
    end

    local function append_local_frame_slot(state, slot)
        state.frame_layout_plan.slots[#state.frame_layout_plan.slots + 1] = slot
        local end_offset = slot.offset + slot.size
        if end_offset > state.frame_layout_plan.next_frame_offset then state.frame_layout_plan.next_frame_offset = end_offset end
        return slot
    end

    local function find_frame_slot(state, value, suffix)
        local id = frame_slot_id(value, suffix)
        for _, slot in ipairs(state.frame_layout_plan.slots) do
            if slot.id == id then return slot end
        end
    end

    local function allocate_ordered_storage_slot(state, value, layout, suffix, frame_alignment)
        local offset = align_up(state.frame_layout_plan.next_frame_offset, frame_alignment)
        local slot = append_frame_slot(state, value, make_frame_slot_for_layout(value, layout, offset, suffix))
        local placement = value_frame_placement_for_layout(value, layout, slot)
        set_placement(state, value, placement)
        return placement
    end

    local function allocate_ordered_frame_slot(state, value, scalar, suffix, frame_alignment)
        return allocate_ordered_storage_slot(state, value, scalar_storage_layout_for_frame(scalar), suffix, frame_alignment)
    end

    local function reserve_ordered_storage_slot(state, value, layout, suffix, frame_alignment)
        local existing = find_frame_slot(state, value, suffix)
        if existing ~= nil then return existing end
        local offset = align_up(state.frame_layout_plan.next_frame_offset, frame_alignment)
        return append_frame_slot(state, value, make_frame_slot_for_layout(value, layout, offset, suffix))
    end

    local function reserve_ordered_frame_slot(state, value, scalar, suffix, frame_alignment)
        return reserve_ordered_storage_slot(state, value, scalar_storage_layout_for_frame(scalar), suffix, frame_alignment)
    end

    local function allocate_param_slot(state, value, scalar, index, frame_alignment)
        return allocate_ordered_frame_slot(state, value, scalar, "param" .. tostring(index), frame_alignment)
    end

    local function allocate_param_storage_slot(state, value, layout, index, frame_alignment)
        return allocate_ordered_storage_slot(state, value, layout, "param" .. tostring(index), frame_alignment)
    end

    local function allocate_value_slot(state, value, scalar, frame_alignment)
        return allocate_ordered_frame_slot(state, value, scalar, nil, frame_alignment)
    end

    local function ensure_value_storage_slot(state, value, layout, frame_alignment)
        local existing = find_placement_for_value(state, value)
        if existing ~= nil then return existing end
        return allocate_ordered_storage_slot(state, value, layout, nil, frame_alignment)
    end

    local function reserve_return_slot(state, value, scalar, frame_alignment)
        return reserve_ordered_frame_slot(state, value, scalar, "return", frame_alignment)
    end

    local function reserve_return_storage_slot(state, value, layout, frame_alignment)
        return reserve_ordered_storage_slot(state, value, layout, "return", frame_alignment)
    end

    local function allocate_local_storage_slot(state, local_id, layout, frame_alignment)
        for _, slot in ipairs(state.frame_layout_plan.slots) do
            if slot.id == local_frame_slot_id(local_id) then return slot end
        end
        local offset = align_up(state.frame_layout_plan.next_frame_offset, frame_alignment)
        return append_local_frame_slot(state, Native.NativeFrameSlot(
            local_frame_slot_id(local_id),
            layout.representation,
            offset,
            layout.size,
            layout.alignment
        ))
    end

    local function address_representation_for_target(target, address_target)
        return Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), address_target)
    end

    local function address_projection_for_capability(target, address_target, capability)
        return Native.NativeCodeAddressProjection(address_target, address_representation_for_target(target, address_target), capability)
    end

    local function append_local_address_entry(state, target, local_id, ty, capability)
        local address_target = Native.NativeCodeLocalAddressTarget(local_id, ty)
        local projection = address_projection_for_capability(target, address_target, capability)
        for i, entry in ipairs(state.value_locations.addresses.locals or {}) do
            if entry.local_id == local_id then
                state.value_locations.addresses.locals[i] = Native.NativeLocalAddressEntry(local_id, projection)
                return projection
            end
        end
        state.value_locations.addresses.locals[#state.value_locations.addresses.locals + 1] = Native.NativeLocalAddressEntry(local_id, projection)
        return projection
    end

    local function append_place_address_entry(state, target, place, capability)
        local address_target = place:native_code_address_target(target)
        local projection = address_projection_for_capability(target, address_target, capability)
        for i, entry in ipairs(state.value_locations.addresses.places or {}) do
            if entry.place == place then
                state.value_locations.addresses.places[i] = Native.NativePlaceAddressEntry(place, projection)
                return projection
            end
        end
        state.value_locations.addresses.places[#state.value_locations.addresses.places + 1] = Native.NativePlaceAddressEntry(place, projection)
        return projection
    end

    local function return_slot_for(state, value, scalar)
        local slot = find_frame_slot(state, value, "return")
        if slot == nil then internal_error("native Code return slot was not reserved before stencil selection") end
        local placement = value_frame_placement(value, scalar, slot)
        set_placement(state, value, placement)
        return placement
    end

    local function append_node(state, node)
        local previous = state.control_plan.nodes[#state.control_plan.nodes]
        state.control_plan.nodes[#state.control_plan.nodes + 1] = node
        if previous ~= nil then
            state.control_plan.edges[#state.control_plan.edges + 1] = Native.NativeContinuationEdge(
                previous.id,
                node.id,
                Support.next_continuation_symbol()
            )
        end
        return node
    end

    local function remove_auto_continuation_edge(state, from_node, to_node)
        if from_node == nil or to_node == nil then return false end
        for i = #state.control_plan.edges, 1, -1 do
            local edge = state.control_plan.edges[i]
            if asdl.isa(edge, Native.NativeContinuationEdge)
                and edge.from == from_node.id
                and edge.to == to_node.id
                and edge.symbol == Support.next_continuation_symbol() then
                table.remove(state.control_plan.edges, i)
                return true
            end
        end
        return false
    end

    local function append_control_edge(state, edge)
        state.control_plan.edges[#state.control_plan.edges + 1] = edge
        return edge
    end

    local function replace_conditional_else_target(state, from, to)
        for i = #state.control_plan.edges, 1, -1 do
            local edge = state.control_plan.edges[i]
            if asdl.isa(edge, Native.NativeConditionalBranchEdge) and edge.from == from then
                state.control_plan.edges[i] = Native.NativeConditionalBranchEdge(
                    edge.from,
                    edge.then_to,
                    edge.then_symbol,
                    to,
                    edge.else_symbol,
                    edge.condition
                )
                return true
            end
        end
        return false
    end

    local function materialize_bindings(node_id, instance, binding_specs)
        local bindings = {}
        for _, spec in ipairs(binding_specs or {}) do
            if type(spec) == "function" then
                bindings[#bindings + 1] = spec(node_id, instance)
            else
                bindings[#bindings + 1] = spec
            end
        end
        return bindings
    end

    local function append_family_node(input, role, family, inputs, outputs, binding_specs)
        local node_id = node_id_for(input.state, role)
        local instance = instance_id_for(node_id)
        local node = Native.NativeTemplateNode(
            node_id,
            instance,
            family,
            inputs or {},
            outputs or {},
            materialize_bindings(node_id, instance, binding_specs)
        )
        return append_node(input.state, node)
    end

    local function frame_layout_from_state(target, state)
        local alignment = target_frame_alignment(target)
        return Native.NativeFrameLayout(state.frame_layout_plan.slots, align_up(state.frame_layout_plan.next_frame_offset, alignment), alignment)
    end

    local function graph_from_state(plan, state, protocol, entry_node)
        if #state.control_plan.nodes == 0 then internal_error("native Code graph has no continuation nodes") end
        local nodes = { entry_node }
        for _, node in ipairs(state.control_plan.nodes) do nodes[#nodes + 1] = node end
        local control_edges = {
            Native.NativeContinuationEdge(entry_node.id, state.control_plan.nodes[1].id, Support.first_continuation_symbol()),
        }
        for _, edge in ipairs(state.control_plan.edges) do control_edges[#control_edges + 1] = edge end
        local exits = state.control_plan.exits
        if #(exits or {}) == 0 then exits = { state.control_plan.nodes[#state.control_plan.nodes].id } end
        return Native.NativeTemplateGraph(
            plan.target,
            protocol,
            frame_layout_from_state(plan.target, state),
            nodes,
            control_edges,
            state.value_edges,
            state.value_locations.addresses,
            entry_node.id,
            exits
        )
    end

    local function hole(id, coordinate)
        local hole_id = Native.NativePatchHoleId(id)
        return function(node_id, instance)
            return Native.NativePatchBinding(node_id, instance, Native.NativePatchBindingHoleId(hole_id), coordinate)
        end
    end

    local function frame_offset_binding(id, placement)
        return hole(id, Native.NativePatchFrameOffset(placement.location.slot.offset))
    end

    local function frame_offset_value_binding(id, offset)
        return hole(id, Native.NativePatchFrameOffset(offset))
    end

    local function scalar_immediate_hole_id(id, scalar)
        if scalar.bits and scalar.bits > 32 then return id .. ".imm64" end
        return id .. ".imm32"
    end

    local function block_entry_node_id(block_id)
        return Native.NativeTemplateNodeId("native.code.block_entry." .. block_id.text)
    end

    local function result_frame_slot_id(func_id, suffix)
        return Native.NativeFrameSlotId("native.frame.result." .. func_id.text .. "." .. suffix)
    end

    local function sret_pointer_value_id(func_id)
        return Code.CodeValueId("native.value.sret_ptr." .. func_id.text)
    end

    function Code.CodeTyBool8:native_machine_scalar(_target)
        return Support.scalar_bool8()
    end

    function Code.CodeTyInt:native_machine_scalar(_target)
        return Support.scalar_int(self.bits, self.signedness)
    end

    function Code.CodeTyIndex:native_machine_scalar(target)
        return Support.scalar_index(target.pointer_bits)
    end

    function Code.CodeTyDataPtr:native_machine_scalar(target)
        return Support.scalar_pointer(target.pointer_bits)
    end

    function Code.CodeTyFloat:_native_machine_scalar(_target)
        return Native.NativeScalarFloat(self.bits)
    end

    function Code.CodeTyFloat:native_machine_scalar(_target)
        return Native.NativeScalarFloat(self.bits)
    end

    function Code.CodeTyCodePtr:native_machine_scalar(target)
        return Support.scalar_pointer(target.pointer_bits)
    end

    function Code.CodeTyImportedCFuncPtr:native_machine_scalar(target)
        return Support.scalar_pointer(target.pointer_bits)
    end

    function Code.CodeTyHandle:native_machine_scalar(target)
        return self.repr:native_machine_scalar(target)
    end

    function Code.CodeTyLease:native_machine_scalar(target)
        return self.base:native_machine_scalar(target)
    end

    function Code.CodeType:native_machine_scalar(_target)
        internal_error("Code type does not have a scalar native machine representation")
    end

    local function native_pointer_projection(target)
        return Native.NativeAbiPointerValue(Support.scalar_pointer(target.pointer_bits))
    end

    local function descriptor_layout(name, size, align)
        return Sem.LayoutNamed("lalin.native.abi", name, {}, size, align)
    end

    local function descriptor_field(name, offset, abi)
        return Native.NativeAbiDescriptorField(name, offset, abi)
    end

    local function index_projection(target)
        return Native.NativeAbiScalarValue(Support.scalar_index(target.pointer_bits), Native.NativePreserveLowerBits)
    end

    local function scalar_storage_layout(scalar)
        return Native.NativeStorageLayout(Native.NativeScalarValueRepresentation(scalar), scalar:native_size_bytes(), scalar:native_frame_alignment())
    end

    local function pointer_storage_layout(target, representation)
        return Native.NativeStorageLayout(representation, target.pointer_bits / 8, target.pointer_bits / 8)
    end

    local function storage_field(name, offset, representation)
        return Native.NativeDescriptorRepresentationField(name, offset, representation)
    end

    local function require_known_source_layout(source_ty, layout_env, target, label)
        local result = TypeSizeAlign.result(source_ty, layout_env, target)
        local layout = result:type_size_align_layout()
        if layout == nil then internal_error("native Code type layout projection is missing a known layout for " .. label) end
        return layout
    end

    function Sem.TypeLayout:native_matches_code_named_type(_ty)
        return false
    end

    function Sem.LayoutNamed:native_matches_code_named_type(ty)
        return self.module_name == ty.module_name and self.type_name == ty.type_name
    end

    function Sem.LayoutLocal:native_matches_code_named_type(_ty)
        return false
    end

    local function find_sem_layout_for_named(layout_env, ty)
        for _, layout in ipairs((layout_env and layout_env.layouts) or {}) do
            if layout:native_matches_code_named_type(ty) then return layout end
        end
    end

    local function source_type_storage_layout(source_ty, target, layout_env, layout_plan)
        local code_ty = CodeType.type_to_code(source_ty)
        local layout = require_known_source_layout(source_ty, layout_env, target, "field `" .. tostring(source_ty) .. "`")
        local storage = code_ty:native_storage_layout(target, layout_plan)
        if storage.size ~= layout.size or storage.alignment ~= layout.align then
            internal_error("native field storage for source type disagrees with TypeLayout size/alignment")
        end
        return storage
    end

    local function sem_field_storage_layout(field, target, layout_env, layout_plan)
        local storage = source_type_storage_layout(field.ty, target, layout_env, layout_plan)
        return Native.NativeCodeFieldStorageLayout(
            field.field_name,
            Native.NativeCodeSemFieldLayoutRef(Sem.FieldByName(field.field_name, field.ty)),
            field.offset,
            storage.size,
            storage.alignment,
            storage.representation
        )
    end

    function Native.NativeCodeNamedLayoutKey:native_matches_code_named_type(_ty)
        return false
    end

    function Native.NativeCodeNamedLayoutByName:native_matches_code_named_type(ty)
        return self.module_name == ty.module_name and self.type_name == ty.type_name and self.source_ty == ty.source_ty
    end

    function Native.NativeCodeNamedLayoutByTypeId:native_matches_code_named_type(ty)
        return self.ty == ty
    end

    function Native.NativeCodeNamedLayoutEntry:native_matches_code_named_type(ty)
        return self.key:native_matches_code_named_type(ty)
    end

    function Native.NativeCodeImportedCLayoutEntry:native_matches_code_imported_c_type(ty)
        return self.c_type == ty.id
    end

    function Native.NativeCodeVariantCaseLayout:native_matches_code_variant_ref(variant)
        return self.variant == variant
    end

    function Native.NativeCodeVariantLayoutEntry:native_matches_code_variant_ref(variant)
        return self.owner_ty == variant.owner_ty
    end

    local function find_named_layout_entry(layout_plan, ty)
        for _, entry in ipairs((layout_plan and layout_plan.named) or {}) do
            if entry:native_matches_code_named_type(ty) then return entry end
        end
    end

    local function find_imported_c_layout_entry(layout_plan, ty)
        for _, entry in ipairs((layout_plan and layout_plan.imported_c) or {}) do
            if entry:native_matches_code_imported_c_type(ty) then return entry end
        end
    end

    local function find_variant_layout_entry(layout_plan, variant)
        for _, entry in ipairs((layout_plan and layout_plan.variants) or {}) do
            if entry:native_matches_code_variant_ref(variant) then return entry end
        end
    end

    local function find_variant_layout_entry_for_owner(layout_plan, owner_ty)
        for _, entry in ipairs((layout_plan and layout_plan.variants) or {}) do
            if entry.owner_ty == owner_ty then return entry end
        end
    end

    local function find_variant_case_layout(layout_plan, variant)
        local entry = find_variant_layout_entry(layout_plan, variant)
        if entry == nil then return nil end
        for _, case_layout in ipairs(entry.cases or {}) do
            if case_layout:native_matches_code_variant_ref(variant) then return entry, case_layout end
        end
        return entry, nil
    end

    local function named_layout_entry_exists(entries, ty)
        for _, entry in ipairs(entries) do
            if entry:native_matches_code_named_type(ty) then return true end
        end
        return false
    end

    function Code.CodeType:native_named_layout_entry(_type_id, _target, _layout_env, _layout_plan)
        return nil
    end

    function Code.CodeTyNamed:native_named_layout_entry(type_id, target, layout_env, layout_plan)
        local sem_layout = find_sem_layout_for_named(layout_env, self)
        if sem_layout == nil then
            internal_error("CodeTyNamed native layout projection is missing Sem.TypeLayout for " .. tostring(self.module_name) .. "." .. tostring(self.type_name))
        end
        local storage = Native.NativeStorageLayout(
            Native.NativeObjectStorageRepresentation(self, sem_layout.size, sem_layout.align),
            sem_layout.size,
            sem_layout.align
        )
        local fields = {}
        for _, field in ipairs(sem_layout.fields or {}) do
            fields[#fields + 1] = sem_field_storage_layout(field, target, layout_env, layout_plan)
        end
        local key
        if type_id ~= nil then
            key = Native.NativeCodeNamedLayoutByTypeId(type_id, self)
        else
            key = Native.NativeCodeNamedLayoutByName(self.module_name, self.type_name, self.source_ty)
        end
        return Native.NativeCodeNamedLayoutEntry(key, self, sem_layout, storage, fields)
    end

    function C.CLayoutFact:native_code_imported_c_layout_entry()
        local ty = Code.CodeTyImportedC(self.type)
        local storage = Native.NativeStorageLayout(Native.NativeObjectStorageRepresentation(ty, self.size, self.align), self.size, self.align)
        local fields = {}
        for _, field in ipairs(self.fields or {}) do
            fields[#fields + 1] = Native.NativeCodeFieldStorageLayout(
                field.name,
                Native.NativeCodeCFieldLayoutRef(field),
                field.offset,
                field.size,
                field.align,
                Native.NativeObjectStorageRepresentation(Code.CodeTyImportedC(field.type), field.size, field.align)
            )
        end
        return Native.NativeCodeImportedCLayoutEntry(self.type, ty, self, storage, fields)
    end

    function Code.CodeBackModuleFacts:native_code_type_layout_plan(module, target)
        if target == nil then internal_error("native Code type layout projection requires a NativeTarget") end
        local layout_env = self.layout_env
        local plan = Native.NativeCodeTypeLayoutPlan({}, {}, {})
        for _, decl in ipairs(module.types or {}) do
            local entry = decl.ty:native_named_layout_entry(decl.id, target, layout_env, plan)
            if entry ~= nil and not named_layout_entry_exists(plan.named, entry.ty) then plan.named[#plan.named + 1] = entry end
        end
        for _, global in ipairs(module.globals or {}) do
            local entry = global.ty:native_named_layout_entry(nil, target, layout_env, plan)
            if entry ~= nil and not named_layout_entry_exists(plan.named, entry.ty) then plan.named[#plan.named + 1] = entry end
        end
        return plan
    end

    function Code.CodeModule:native_code_type_layout_plan(facts, target)
        if facts == nil then internal_error("native CodeModule type layout projection requires CodeBackModuleFacts") end
        return facts:native_code_type_layout_plan(self, target)
    end

    function Code.CodeVariantRef:native_variant_layout_entry(layout_plan)
        local entry = find_variant_layout_entry(layout_plan, self)
        if entry == nil then internal_error("CodeVariantRef native storage requires a NativeCodeVariantLayoutEntry") end
        return entry
    end

    function Code.CodeVariantRef:native_variant_case_layout(layout_plan)
        local _entry, case_layout = find_variant_case_layout(layout_plan, self)
        if case_layout == nil then internal_error("CodeVariantRef native storage requires a NativeCodeVariantCaseLayout for " .. tostring(self.variant_name)) end
        return case_layout
    end

    function Code.CodeVariantRef:native_storage_layout(_target, layout_plan)
        return self:native_variant_layout_entry(layout_plan).storage
    end

    function Code.CodeVariantRef:native_payload_storage_layout(_target, layout_plan)
        local case_layout = self:native_variant_case_layout(layout_plan)
        if case_layout.payload == nil then return Native.NativeStorageLayout(Native.NativeObjectStorageRepresentation(Code.CodeTyVoid, 0, 1), 0, 1) end
        return case_layout.payload
    end

    function Code.CodeType:native_storage_layout(_target, _layout_plan)
        internal_error("Code type does not have a native storage layout")
    end

    function Code.CodeType:native_value_representation(target, layout_plan)
        return self:native_storage_layout(target, layout_plan).representation
    end

    function Code.CodeTyVoid:native_storage_layout(_target)
        return Native.NativeStorageLayout(Native.NativeObjectStorageRepresentation(Code.CodeTyVoid, 0, 1), 0, 1)
    end

    function Code.CodeTyBool8:native_storage_layout(_target)
        return scalar_storage_layout(Support.scalar_bool8())
    end

    function Code.CodeTyInt:native_storage_layout(_target)
        return scalar_storage_layout(Support.scalar_int(self.bits, self.signedness))
    end

    function Code.CodeTyIndex:native_storage_layout(target)
        return scalar_storage_layout(Support.scalar_index(target.pointer_bits))
    end

    function Code.CodeTyFloat:native_storage_layout(_target)
        return scalar_storage_layout(Native.NativeScalarFloat(self.bits))
    end

    function Code.CodeTyDataPtr:native_storage_layout(target)
        local scalar = Support.scalar_pointer(target.pointer_bits)
        if self.pointee ~= nil then return pointer_storage_layout(target, Native.NativeOpaquePointerValueRepresentation(scalar, self.pointee)) end
        return pointer_storage_layout(target, Native.NativeUntypedPointerValueRepresentation(scalar))
    end

    function Code.CodeTyCodePtr:native_storage_layout(target)
        return pointer_storage_layout(target, Native.NativeUntypedPointerValueRepresentation(Support.scalar_pointer(target.pointer_bits)))
    end

    function Code.CodeTyImportedCFuncPtr:native_storage_layout(target)
        return pointer_storage_layout(target, Native.NativeUntypedPointerValueRepresentation(Support.scalar_pointer(target.pointer_bits)))
    end

    function Code.CodeTySlice:native_storage_layout(target)
        local ptr = Native.NativeUntypedPointerValueRepresentation(Support.scalar_pointer(target.pointer_bits))
        local index = Native.NativeScalarValueRepresentation(Support.scalar_index(target.pointer_bits))
        local rep = Native.NativeDescriptorValueRepresentation(
            descriptor_layout("slice", 16, 8),
            { storage_field("data", 0, ptr), storage_field("len", 8, index) }
        )
        return Native.NativeStorageLayout(rep, 16, 8)
    end

    function Code.CodeTyView:native_storage_layout(target)
        local ptr = Native.NativeUntypedPointerValueRepresentation(Support.scalar_pointer(target.pointer_bits))
        local index = Native.NativeScalarValueRepresentation(Support.scalar_index(target.pointer_bits))
        local rep = Native.NativeDescriptorValueRepresentation(
            descriptor_layout("view", 24, 8),
            { storage_field("data", 0, ptr), storage_field("len", 8, index), storage_field("stride", 16, index) }
        )
        return Native.NativeStorageLayout(rep, 24, 8)
    end

    function Code.CodeTyByteSpan:native_storage_layout(target)
        local ptr = Native.NativeUntypedPointerValueRepresentation(Support.scalar_pointer(target.pointer_bits))
        local index = Native.NativeScalarValueRepresentation(Support.scalar_index(target.pointer_bits))
        local rep = Native.NativeDescriptorValueRepresentation(
            descriptor_layout("bytespan", 16, 8),
            { storage_field("data", 0, ptr), storage_field("len", 8, index) }
        )
        return Native.NativeStorageLayout(rep, 16, 8)
    end

    function Code.CodeTyClosure:native_storage_layout(target)
        local ptr = Native.NativeUntypedPointerValueRepresentation(Support.scalar_pointer(target.pointer_bits))
        local rep = Native.NativeDescriptorValueRepresentation(
            descriptor_layout("closure", 16, 8),
            { storage_field("fn", 0, ptr), storage_field("ctx", 8, ptr) }
        )
        return Native.NativeStorageLayout(rep, 16, 8)
    end

    function Code.CodeTyArray:native_storage_layout(target, layout_plan)
        local elem_layout = self.elem:native_storage_layout(target, layout_plan)
        local size = elem_layout.size * self.count
        local rep = Native.NativeAggregateStorageRepresentation(self, { elem_layout.representation }, self.count, size, elem_layout.alignment)
        return Native.NativeStorageLayout(rep, size, elem_layout.alignment)
    end

    function Code.CodeTyVector:native_storage_layout(target, layout_plan)
        local elem_layout = self.elem:native_storage_layout(target, layout_plan)
        local size = elem_layout.size * self.lanes
        local alignment = elem_layout.alignment
        if size >= 16 then alignment = 16 elseif size >= 8 and alignment < 8 then alignment = 8 end
        local rep = Native.NativeVectorStorageRepresentation(self, elem_layout.representation, self.lanes, size, alignment)
        return Native.NativeStorageLayout(rep, size, alignment)
    end

    function Code.CodeTyHandle:native_storage_layout(target, layout_plan)
        return self.repr:native_storage_layout(target, layout_plan)
    end

    function Code.CodeTyLease:native_storage_layout(target, layout_plan)
        return self.base:native_storage_layout(target, layout_plan)
    end

    function Code.CodeTyNamed:native_storage_layout(_target, layout_plan)
        local variant_entry = find_variant_layout_entry_for_owner(layout_plan, self)
        if variant_entry ~= nil then return variant_entry.storage end
        local entry = find_named_layout_entry(layout_plan, self)
        if entry == nil then internal_error("CodeTyNamed native storage layout requires a NativeCodeNamedLayoutEntry") end
        return entry.storage
    end

    function Code.CodeTyImportedC:native_storage_layout(_target, layout_plan)
        local entry = find_imported_c_layout_entry(layout_plan, self)
        if entry == nil then internal_error("CodeTyImportedC native storage layout requires a NativeCodeImportedCLayoutEntry") end
        return entry.storage
    end

    function Code.CodeType:native_abi_projection(_target)
        internal_error("Code type cannot be projected into the native ABI")
    end

    function Code.CodeTyVoid:native_abi_projection(_target)
        internal_error("CodeTyVoid is not a native ABI parameter/result value")
    end

    function Code.CodeTyBool8:native_abi_projection(_target)
        return Native.NativeAbiScalarValue(Support.scalar_bool8(), Native.NativeZeroExtend)
    end

    function Code.CodeTyInt:native_abi_projection(_target)
        local extension = self.signedness == Code.CodeSigned and Native.NativeSignExtend or Native.NativeZeroExtend
        return Native.NativeAbiScalarValue(Support.scalar_int(self.bits, self.signedness), extension)
    end

    function Code.CodeTyIndex:native_abi_projection(target)
        return index_projection(target)
    end

    function Code.CodeTyFloat:native_abi_projection(_target)
        return Native.NativeAbiScalarValue(Native.NativeScalarFloat(self.bits), Native.NativePreserveLowerBits)
    end

    function Code.CodeTyDataPtr:native_abi_projection(target)
        return native_pointer_projection(target)
    end

    function Code.CodeTyCodePtr:native_abi_projection(target)
        return native_pointer_projection(target)
    end

    function Code.CodeTyImportedCFuncPtr:native_abi_projection(target)
        return native_pointer_projection(target)
    end

    function Code.CodeTySlice:native_abi_projection(target)
        return Native.NativeAbiDescriptorValue(
            descriptor_layout("slice", 16, 8),
            {
                descriptor_field("data", 0, native_pointer_projection(target)),
                descriptor_field("len", 8, index_projection(target)),
            }
        )
    end

    function Code.CodeTyView:native_abi_projection(target)
        return Native.NativeAbiDescriptorValue(
            descriptor_layout("view", 24, 8),
            {
                descriptor_field("data", 0, native_pointer_projection(target)),
                descriptor_field("len", 8, index_projection(target)),
                descriptor_field("stride", 16, index_projection(target)),
            }
        )
    end

    function Code.CodeTyByteSpan:native_abi_projection(target)
        return Native.NativeAbiDescriptorValue(
            descriptor_layout("bytespan", 16, 8),
            {
                descriptor_field("data", 0, native_pointer_projection(target)),
                descriptor_field("len", 8, index_projection(target)),
            }
        )
    end

    function Code.CodeTyClosure:native_abi_projection(target)
        return Native.NativeAbiDescriptorValue(
            descriptor_layout("closure", 16, 8),
            {
                descriptor_field("fn", 0, native_pointer_projection(target)),
                descriptor_field("ctx", 8, native_pointer_projection(target)),
            }
        )
    end

    function Code.CodeTyHandle:native_abi_projection(target)
        return self.repr:native_abi_projection(target)
    end

    function Code.CodeTyLease:native_abi_projection(target)
        return self.base:native_abi_projection(target)
    end

    function Code.CodeType:native_byref_alignment(_target)
        return 8
    end

    function Code.CodeTyArray:native_byref_alignment(target)
        return self.elem:native_byref_alignment(target)
    end

    function Code.CodeTyVector:native_byref_alignment(target)
        return self.elem:native_byref_alignment(target)
    end

    function Code.CodeTyNamed:native_abi_projection(_target)
        return Native.NativeAbiByRefValue(self, Native.NativeAbiByRefReadonly, self:native_byref_alignment(_target))
    end

    function Code.CodeTyArray:native_abi_projection(target)
        return Native.NativeAbiByRefValue(self, Native.NativeAbiByRefReadonly, self:native_byref_alignment(target))
    end

    function Code.CodeTyVector:native_abi_projection(target)
        return Native.NativeAbiByRefValue(self, Native.NativeAbiByRefReadonly, self:native_byref_alignment(target))
    end

    function Code.CodeTyImportedC:native_abi_projection(target)
        return Native.NativeAbiByRefValue(self, Native.NativeAbiByRefReadonly, self:native_byref_alignment(target))
    end

    function Code.CodeType:native_requires_sret_result()
        return false
    end

    function Code.CodeTyNamed:native_requires_sret_result() return true end
    function Code.CodeTyArray:native_requires_sret_result() return true end
    function Code.CodeTyVector:native_requires_sret_result() return true end
    function Code.CodeTyImportedC:native_requires_sret_result() return true end

    local function abi_param_projection(target, index, ty)
        return Native.NativeAbiParamProjection(index, ty, ty:native_abi_projection(target))
    end

    function Code.CodeSig:native_abi_projection(target)
        if #(self.results or {}) > 1 then
            internal_error("native CodeSig ABI projection supports zero or one result, got " .. tostring(#self.results))
        end
        local params = {}
        local result_abi = Native.NativeAbiVoidResult
        local result_ty = nil
        local param_index = 0
        if #(self.results or {}) == 1 then
            result_ty = self.results[1]
            if result_ty:native_requires_sret_result() then
                local pointer_ty = Code.CodeTyDataPtr(result_ty)
                local sret_param = Native.NativeAbiParamProjection(param_index, pointer_ty, native_pointer_projection(target))
                params[#params + 1] = sret_param
                param_index = param_index + 1
                result_abi = Native.NativeAbiSRetResult(result_ty, sret_param)
            else
                result_abi = result_ty:native_abi_projection(target)
            end
        end
        for _, ty in ipairs(self.params or {}) do
            params[#params + 1] = abi_param_projection(target, param_index, ty)
            param_index = param_index + 1
        end
        return Native.NativeAbiFunctionProjection(target, params, Native.NativeAbiResultProjection(result_ty, result_abi))
    end

    function Code.CodeSig:select_native_abi_protocol(target)
        return Native.NativeCallCodeSig(self:native_abi_projection(target))
    end

    function Code.CodeSig:native_code_result_shape(target)
        return self:native_abi_projection(target).result:native_code_result_shape()
    end

    function Code.CodeCallDirect:select_native_call_projection(sig, target)
        return sig:native_abi_projection(target)
    end

    function Code.CodeCallExtern:select_native_call_projection(sig, target)
        return sig:native_abi_projection(target)
    end

    function Code.CodeCallIndirect:select_native_call_projection(sig, target)
        return sig:native_abi_projection(target)
    end

    function Code.CodeCallClosure:select_native_call_projection(sig, target)
        return sig:native_abi_projection(target)
    end

    function Code.CodeCallTarget:native_code_call_shape()
        internal_error("Code call target has no native call shape")
    end

    function Code.CodeCallTarget:native_call_family_mode()
        internal_error("Code call target has no native call family mode")
    end

    function Code.CodeCallDirect:native_call_family_mode() return "direct" end
    function Code.CodeCallExtern:native_call_family_mode() return "extern" end
    function Code.CodeCallIndirect:native_call_family_mode() return "indirect" end
    function Code.CodeCallClosure:native_call_family_mode() return "closure" end

    function Code.CodeCallDirect:native_code_call_shape()
        return Native.NativeCodeCallDirectTarget
    end

    function Code.CodeCallExtern:native_code_call_shape()
        return Native.NativeCodeCallExternTarget
    end

    function Code.CodeCallIndirect:native_code_call_shape()
        return Native.NativeCodeCallIndirectPointer
    end

    function Code.CodeCallClosure:native_code_call_shape()
        return Native.NativeCodeCallClosurePointer
    end

    function Code.CodePlace:native_code_address_target(_target)
        internal_error("Code place does not have a native address target")
    end

    function Code.CodePlaceLocal:native_code_address_target(_target)
        return Native.NativeCodeLocalAddressTarget(self.local_id, self.ty)
    end

    function Code.CodePlaceGlobal:native_code_address_target(_target)
        return Native.NativeCodeGlobalAddressTarget(self.global, self.ty)
    end

    function Code.CodePlaceData:native_code_address_target(_target)
        return Native.NativeCodeDataAddressTarget(self.data, self.ty)
    end

    function Code.CodePlaceDeref:native_code_address_target(_target)
        return Native.NativeCodePlaceAddressTarget(self)
    end

    function Code.CodePlaceField:native_code_address_target(_target)
        return Native.NativeCodePlaceAddressTarget(self)
    end

    function Code.CodePlaceIndex:native_code_address_target(_target)
        return Native.NativeCodePlaceAddressTarget(self)
    end

    function Code.CodePlaceBytes:native_code_address_target(_target)
        return Native.NativeCodePlaceAddressTarget(self)
    end

    function Code.CodePlace:native_storage_layout(_target, _layout_plan)
        internal_error("Code place does not have a native storage layout")
    end

    function Code.CodePlaceLocal:native_storage_layout(target, layout_plan)
        return self.ty:native_storage_layout(target, layout_plan)
    end

    function Code.CodePlaceGlobal:native_storage_layout(target, layout_plan)
        return self.ty:native_storage_layout(target, layout_plan)
    end

    function Code.CodePlaceData:native_storage_layout(target, layout_plan)
        return self.ty:native_storage_layout(target, layout_plan)
    end

    function Code.CodePlaceDeref:native_storage_layout(target, layout_plan)
        return self.ty:native_storage_layout(target, layout_plan)
    end

    function Code.CodePlaceField:native_storage_layout(target, layout_plan)
        local storage = self.ty:native_storage_layout(target, layout_plan)
        if self.size ~= nil and storage.size ~= self.size then internal_error("CodePlaceField storage size disagrees with field layout projection") end
        if self.align ~= nil and storage.alignment ~= self.align then internal_error("CodePlaceField storage alignment disagrees with field layout projection") end
        return storage
    end

    function Code.CodePlaceField:native_field_storage_layout(target, layout_plan)
        local storage = self:native_storage_layout(target, layout_plan)
        return Native.NativeCodeFieldStorageLayout(
            self.field.field_name,
            Native.NativeCodeSemFieldLayoutRef(self.field),
            self.offset,
            storage.size,
            storage.alignment,
            storage.representation
        )
    end

    function Code.CodePlaceIndex:native_storage_layout(target, layout_plan)
        local storage = self.ty:native_storage_layout(target, layout_plan)
        if storage.size ~= self.elem_size then internal_error("CodePlaceIndex element size disagrees with storage layout projection") end
        return storage
    end

    function Code.CodePlaceBytes:native_storage_layout(_target, _layout_plan)
        return Native.NativeStorageLayout(Native.NativeObjectStorageRepresentation(self.ty, self.size, self.align), self.size, self.align)
    end

    function Code.CodePlace:native_address_patch_coordinate(_target)
        internal_error("Code place address is not a module patch coordinate")
    end

    function Code.CodePlaceGlobal:native_address_patch_coordinate(_target)
        return Native.NativePatchCodeGlobalAddress(self.global)
    end

    function Code.CodePlaceData:native_address_patch_coordinate(_target)
        return Native.NativePatchCodeDataAddress(self.data)
    end

    function Code.CodeGlobalRef:native_address_patch_coordinate(_target)
        internal_error("CodeGlobalRef leaf is missing native address patch coordinate")
    end

    function Code.CodeGlobalRefData:native_address_patch_coordinate(_target)
        return Native.NativePatchCodeDataAddress(self.data)
    end

    function Code.CodeGlobalRefGlobal:native_address_patch_coordinate(_target)
        return Native.NativePatchCodeGlobalAddress(self.global)
    end

    function Code.CodeGlobalRefFunc:native_address_patch_coordinate(_target)
        return Native.NativePatchCodeFuncAddress(self.func)
    end

    function Code.CodeGlobalRefExtern:native_address_patch_coordinate(_target)
        return Native.NativePatchCodeExternAddress(self.extern)
    end

    function Code.CodePlaceLocal:native_address_capability_for_frame_slot(slot)
        return Native.NativeCodeAddressFrameSlot(slot.id)
    end

    function Code.CodePlace:append_native_place_address_plan(_input)
        internal_error("CodePlace leaf is missing native place address planning")
    end

    function Code.CodePlaceLocal:append_native_place_address_plan(input)
        for _, entry in ipairs(input.lowering.active_func.local_storage or {}) do
            if entry.local_id == self.local_id then
                local slot = allocate_local_storage_slot(input.state, self.local_id, entry.storage, target_frame_alignment(input.plan.target))
                append_local_address_entry(input.state, input.plan.target, self.local_id, self.ty, Native.NativeCodeAddressFrameSlot(slot.id))
                return append_place_address_entry(input.state, input.plan.target, self, Native.NativeCodeAddressFrameSlot(slot.id))
            end
        end
        internal_error("native place address planning could not find local storage for " .. tostring(self.local_id and self.local_id.text))
    end

    function Code.CodePlaceGlobal:append_native_place_address_plan(input)
        return append_place_address_entry(input.state, input.plan.target, self, Native.NativeCodeAddressPatchable(self:native_address_patch_coordinate(input.plan.target)))
    end

    function Code.CodePlaceData:append_native_place_address_plan(input)
        return append_place_address_entry(input.state, input.plan.target, self, Native.NativeCodeAddressPatchable(self:native_address_patch_coordinate(input.plan.target)))
    end

    function Code.CodePlaceDeref:append_native_place_address_plan(input)
        placement_for_value(input.state, self.addr)
        return append_place_address_entry(input.state, input.plan.target, self, Native.NativeCodeAddressValueOffset(self.addr, 0))
    end

    function Code.CodePlaceField:append_native_place_address_plan(input)
        self.base:append_native_place_address_plan(input)
        self:native_field_storage_layout(input.plan.target, input.lowering.module.type_layouts)
        return append_place_address_entry(input.state, input.plan.target, self, Native.NativeCodeAddressPlaceOffset(self.base, self.offset))
    end

    function Code.CodePlaceIndex:append_native_place_address_plan(input)
        self.base:append_native_place_address_plan(input)
        placement_for_value(input.state, self.index)
        self:native_storage_layout(input.plan.target, input.lowering.module.type_layouts)
        return append_place_address_entry(input.state, input.plan.target, self, Native.NativeCodeAddressPlaceIndexOffset(self.base, self.index, self.elem_size, 0))
    end

    function Code.CodePlaceBytes:append_native_place_address_plan(input)
        placement_for_value(input.state, self.base)
        self:native_storage_layout(input.plan.target, input.lowering.module.type_layouts)
        return append_place_address_entry(input.state, input.plan.target, self, Native.NativeCodeAddressValueOffset(self.base, self.offset))
    end

    function Code.CodeInst:append_native_address_plan(_input)
        return nil
    end

    function Code.CodeInstAddrOf:append_native_address_plan(input)
        return self.place:append_native_place_address_plan(input)
    end

    function Code.CodeInstLoad:append_native_address_plan(input)
        return self.place:append_native_place_address_plan(input)
    end

    function Code.CodeInstStore:append_native_address_plan(input)
        return self.place:append_native_place_address_plan(input)
    end

    function Code.CodeInstAtomicLoad:append_native_address_plan(input)
        return self.place:append_native_place_address_plan(input)
    end

    function Code.CodeInstAtomicStore:append_native_address_plan(input)
        return self.place:append_native_place_address_plan(input)
    end

    function Code.CodeInstAtomicRmw:append_native_address_plan(input)
        return self.place:append_native_place_address_plan(input)
    end

    function Code.CodeInstAtomicCas:append_native_address_plan(input)
        return self.place:append_native_place_address_plan(input)
    end

    function Code.CodePlace:native_code_address_projection(target, capability)
        local address_target = self:native_code_address_target(target)
        return Native.NativeCodeAddressProjection(
            address_target,
            Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), address_target),
            capability
        )
    end

    function Core.BinAdd:native_binary_family_name() return "add" end
    function Core.BinSub:native_binary_family_name() return "sub" end
    function Core.BinMul:native_binary_family_name() return "mul" end
    function Core.BinBitAnd:native_binary_family_name() return "and" end
    function Core.BinBitOr:native_binary_family_name() return "or" end
    function Core.BinBitXor:native_binary_family_name() return "xor" end
    function Core.BinShl:native_binary_family_name() return "shl" end
    function Core.BinLShr:native_binary_family_name() return "lshr" end
    function Core.BinAShr:native_binary_family_name() return "ashr" end
    function Core.BinDiv:native_binary_family_name() return "div" end

    function Core.UnaryNeg:native_unary_family_name() return "neg" end
    function Core.UnaryBitNot:native_unary_family_name() return "bitnot" end
    function Core.UnaryNot:native_unary_family_name() return "not" end

    function Core.CmpEq:native_compare_family_name() return "eq" end
    function Core.CmpNe:native_compare_family_name() return "ne" end
    function Core.CmpLt:native_compare_family_name() return "lt" end
    function Core.CmpLe:native_compare_family_name() return "le" end
    function Core.CmpGt:native_compare_family_name() return "gt" end
    function Core.CmpGe:native_compare_family_name() return "ge" end

    function Core.LitInt:native_patch_coordinate_for_scalar(scalar)
        local value = tonumber(self.raw)
        if scalar.bits and scalar.bits > 32 then return Native.NativePatchImmediateI64(value) end
        return Native.NativePatchImmediateI32(value)
    end

    function Core.LitBool:native_patch_coordinate_for_scalar(_scalar)
        return Native.NativePatchImmediateI32(self.value and 1 or 0)
    end

    local function module_sig_for_func(module, func)
        for _, sig in ipairs(module.sigs or {}) do
            if sig.id == func.sig then return sig end
        end
        internal_error("native CodeModule is missing CodeSig " .. tostring(func.sig and func.sig.text))
    end

    local function module_sig_by_id(module, sig_id)
        for _, sig in ipairs(module.sigs or {}) do
            if sig.id == sig_id then return sig end
        end
        internal_error("native CodeModule is missing CodeSig " .. tostring(sig_id and sig_id.text))
    end

    local function empty_type_layout_plan()
        return Native.NativeCodeTypeLayoutPlan({}, {}, {})
    end

    local function empty_module_address_plan()
        return Native.NativeModuleAddressPlan({}, {}, {}, {}, {}, {})
    end

    local function patchable_address_projection(target, address_target, coordinate)
        return Native.NativeCodeAddressProjection(
            address_target,
            Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), address_target),
            Native.NativeCodeAddressPatchable(coordinate)
        )
    end

    local function runtime_address_projection(target, address_target, symbol)
        return Native.NativeCodeAddressProjection(
            address_target,
            Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), address_target),
            Native.NativeCodeAddressRuntimeSymbol(symbol.id)
        )
    end

    local function runtime_symbol_for_extern(runtime, extern)
        for _, symbol in ipairs((runtime and runtime.symbols) or {}) do
            if symbol.name == extern.symbol then return symbol end
        end
        internal_error("native Code extern " .. tostring(extern.id and extern.id.text) .. " has no matching NativeRuntimeSymbol for `" .. tostring(extern.symbol) .. "`")
    end

    local function constant_pool_entry_id_for_data(data)
        return Native.NativeConstantPoolEntryId("native.code.data." .. data.id.text .. ".rodata")
    end

    local function template_bytes_from_buffer(buffer)
        return Native.NativeTemplateBytes(table.concat(buffer), #buffer)
    end

    local function put_byte(buffer, offset, value)
        buffer[offset + 1] = string.char(value % 256)
    end

    function Code.CodeDataInit:native_static_init(_target, _layout_plan)
        internal_error("CodeDataInit leaf is missing native static init projection")
    end

    function Code.CodeDataZero:native_static_init(_target, _layout_plan)
        return Native.NativeCodeStaticZeroInit(self.offset, self.size), nil
    end

    function Code.CodeDataBytes:native_static_init(_target, _layout_plan)
        return Native.NativeCodeStaticBytesInit(self.offset, self.bytes), nil
    end

    function Code.CodeDataScalar:native_static_init(target, layout_plan)
        return Native.NativeCodeStaticScalarInit(self.offset, self.ty, self.literal, self.ty:native_storage_layout(target, layout_plan)), nil
    end

    function Code.CodeDataReloc:native_static_init(_target, _layout_plan)
        local relocation = Native.NativeCodeStaticRelocation(
            self.reloc.id,
            self.reloc.offset,
            self.reloc.target,
            self.reloc.addend,
            Native.NativeCodeStaticRelocAbs64
        )
        return Native.NativeCodeStaticRelocationInit(relocation), relocation
    end

    function Code.CodeDataInit:apply_native_static_bytes(_buffer)
        internal_error("CodeDataInit leaf is missing native static byte materialization")
    end

    function Code.CodeDataZero:apply_native_static_bytes(buffer)
        for index = 0, self.size - 1 do put_byte(buffer, self.offset + index, 0) end
    end

    function Code.CodeDataBytes:apply_native_static_bytes(buffer)
        for index = 1, #self.bytes do
            put_byte(buffer, self.offset + index - 1, string.byte(self.bytes, index))
        end
    end

    function Code.CodeDataReloc:apply_native_static_bytes(buffer)
        for index = 0, 7 do put_byte(buffer, self.reloc.offset + index, 0) end
    end

    function Code.CodeDataScalar:apply_native_static_bytes(_buffer)
        internal_error("native static scalar data init needs a scalar byte encoder before it can be constant-pool backed")
    end

    local function native_static_plan_from_inits(inits, target, layout_plan)
        local plan_inits = {}
        local relocations = {}
        for _, init in ipairs(inits or {}) do
            local plan_init, relocation = init:native_static_init(target, layout_plan)
            plan_inits[#plan_inits + 1] = plan_init
            if relocation ~= nil then relocations[#relocations + 1] = relocation end
        end
        return plan_inits, relocations
    end

    local function native_static_bytes(size, inits)
        local buffer = {}
        for index = 1, size do buffer[index] = "\0" end
        for _, init in ipairs(inits or {}) do init:apply_native_static_bytes(buffer) end
        return template_bytes_from_buffer(buffer)
    end

    local function append_value_type_plan_entry(out, target, layout_plan, value, ty)
        out[#out + 1] = Native.NativeCodeValueTypePlanEntry(value, ty, ty:native_storage_layout(target, layout_plan))
    end

    local function native_code_function_entry_symbol(signature, target)
        return "lalin_native_public_abi_adapter_" .. signature:native_abi_projection(target):native_projection_token()
    end

    local function native_public_abi_adapter_family(target, projection)
        return Native.NativeTemplateFamily(
            Support.code_func_family_id("public_abi_adapter." .. projection:native_projection_token()),
            Native.NativeRoleCodeFunc,
            { Support.axis_target(target), Support.axis_abi(Support.native_call_code_sig(projection)) },
            Support.protocol(Support.native_call_code_sig(projection), Support.register_none())
        )
    end

    local function native_code_function_entry_address(func, signature, target)
        local address_target = Native.NativeCodeFuncAddressTarget(func.id, func.sig)
        return Native.NativeCodeAddressProjection(
            address_target,
            Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), address_target),
            Native.NativeCodeAddressFunctionEntry(func.id, native_code_function_entry_symbol(signature, target))
        )
    end

    local function native_code_function_plan(func, signature, target, layout_plan)
        local abi = signature:native_abi_projection(target)
        local value_types = {}
        local block_params = {}
        local local_storage = {}
        for _, param in ipairs(func.params or {}) do
            append_value_type_plan_entry(value_types, target, layout_plan, param.value, param.ty)
        end
        for _, block in ipairs(func.blocks or {}) do
            block_params[#block_params + 1] = Native.NativeCodeBlockParamPlanEntry(block.id, block.params or {})
            for _, param in ipairs(block.params or {}) do
                append_value_type_plan_entry(value_types, target, layout_plan, param.value, param.ty)
            end
        end
        for _, local_decl in ipairs(func.locals or {}) do
            local_storage[#local_storage + 1] = Native.NativeCodeLocalStoragePlanEntry(
                local_decl.id,
                local_decl.name,
                local_decl.ty,
                local_decl.residence,
                local_decl.ty:native_storage_layout(target, layout_plan)
            )
        end
        return Native.NativeCodeFunctionPlan(func.id, func.sig, signature, abi, native_code_function_entry_address(func, signature, target), value_types, block_params, local_storage)
    end

    local function native_code_module_plan(module, target, runtime, type_layouts)
        type_layouts = type_layouts or empty_type_layout_plan()
        local addresses = empty_module_address_plan()
        local signatures = {}
        local function_signatures = {}
        local data_storage = {}
        local global_storage = {}
        local extern_runtime = {}
        local functions = {}
        for _, sig in ipairs(module.sigs or {}) do
            signatures[#signatures + 1] = Native.NativeCodeSignaturePlanEntry(sig.id, sig, sig:native_abi_projection(target))
        end
        for _, data in ipairs(module.data or {}) do
            local plan_inits, relocations = native_static_plan_from_inits(data.inits, target, type_layouts)
            local pool_entry = Native.NativeConstantPoolEntry(
                constant_pool_entry_id_for_data(data),
                native_static_bytes(data.size, data.inits),
                data.align,
                Native.NativeConstantPoolBytes(data.size, data.align)
            )
            local address_target = Native.NativeCodeRawDataAddressTarget(data.id, data.size, data.align)
            local address = Native.NativeCodeAddressProjection(
                address_target,
                Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), address_target),
                Native.NativeCodeAddressConstantPoolEntry(pool_entry.id)
            )
            data_storage[#data_storage + 1] = Native.NativeCodeDataStoragePlanEntry(
                data.id,
                data.name,
                data.linkage,
                data.size,
                data.align,
                Native.NativeCodeStaticReadOnly,
                Native.NativeCodeStaticConstantPoolBacking(pool_entry),
                plan_inits,
                relocations,
                address
            )
            addresses.data[#addresses.data + 1] = Native.NativeModuleDataAddressEntry(data.id, address)
        end
        for _, global in ipairs(module.globals or {}) do
            local storage = global.ty:native_storage_layout(target, type_layouts)
            if global.size ~= nil and global.size ~= storage.size then internal_error("native CodeGlobal size disagrees with storage plan for " .. tostring(global.id and global.id.text)) end
            if global.align ~= nil and global.align ~= storage.alignment then internal_error("native CodeGlobal alignment disagrees with storage plan for " .. tostring(global.id and global.id.text)) end
            local plan_inits, relocations = native_static_plan_from_inits(global.inits, target, type_layouts)
            local capability = Native.NativeWritableDataRuntimeCapability("native.code.global." .. global.id.text, storage.size, storage.alignment)
            local address_target = Native.NativeCodeGlobalAddressTarget(global.id, global.ty)
            local address = Native.NativeCodeAddressProjection(
                address_target,
                Native.NativeAddressValueRepresentation(Support.scalar_pointer(target.pointer_bits), address_target),
                Native.NativeCodeAddressWritableDataRuntime(capability)
            )
            global_storage[#global_storage + 1] = Native.NativeCodeGlobalStoragePlanEntry(
                global.id,
                global.name,
                global.ty,
                global.linkage,
                storage,
                storage.size,
                storage.alignment,
                Native.NativeCodeStaticWritable,
                Native.NativeCodeStaticWritableRuntimeBacking(capability),
                plan_inits,
                relocations,
                address
            )
            addresses.globals[#addresses.globals + 1] = Native.NativeModuleGlobalAddressEntry(global.id, address)
        end
        for _, extern in ipairs(module.externs or {}) do
            local sig = module_sig_by_id(module, extern.sig)
            local symbol = runtime_symbol_for_extern(runtime, extern)
            local abi = sig:native_abi_projection(target)
            extern_runtime[#extern_runtime + 1] = Native.NativeCodeExternRuntimePlanEntry(extern.id, extern.symbol, extern.sig, symbol.id, abi)
            local address_target = Native.NativeCodeExternAddressTarget(extern.id)
            addresses.externs[#addresses.externs + 1] = Native.NativeModuleExternAddressEntry(
                extern.id,
                runtime_address_projection(target, address_target, symbol)
            )
        end
        for _, func in ipairs(module.funcs or {}) do
            local signature = module_sig_for_func(module, func)
            local abi = signature:native_abi_projection(target)
            function_signatures[#function_signatures + 1] = Native.NativeCodeFunctionSignaturePlanEntry(func.id, func.sig, signature, abi)
            local entry_address = native_code_function_entry_address(func, signature, target)
            addresses.funcs[#addresses.funcs + 1] = Native.NativeModuleFuncAddressEntry(func.id, entry_address)
            functions[#functions + 1] = native_code_function_plan(func, signature, target, type_layouts)
        end
        return Native.NativeCodeModulePlan(
            Native.NativeCodeModulePlanFromCodeModule(module.id),
            type_layouts,
            addresses,
            signatures,
            function_signatures,
            data_storage,
            global_storage,
            extern_runtime,
            functions
        )
    end

    local function native_code_lowering_for_module(module, func, plan)
        local module_plan = native_code_module_plan(module, plan.target, plan.runtime, empty_type_layout_plan())
        return Native.NativeCodeLoweringInput(module_plan, native_code_function_plan(func, module_sig_for_func(module, func), plan.target, module_plan.type_layouts))
    end

    function Code.CodeBackModuleFacts:native_code_lowering_input(module, func, plan)
        local type_layouts = self:native_code_type_layout_plan(module, plan.target)
        local module_plan = native_code_module_plan(module, plan.target, plan.runtime, type_layouts)
        return Native.NativeCodeLoweringInput(module_plan, native_code_function_plan(func, module_sig_for_func(module, func), plan.target, type_layouts))
    end

    function Code.CodeModule:native_code_lowering_input(facts, func, plan)
        if facts ~= nil then return facts:native_code_lowering_input(self, func, plan) end
        return native_code_lowering_for_module(self, func, plan)
    end

    local function native_code_lowering_for_single_function(func, signature, plan)
        local type_layouts = empty_type_layout_plan()
        local func_plan = native_code_function_plan(func, signature, plan.target, type_layouts)
        local addresses = empty_module_address_plan()
        addresses.funcs[#addresses.funcs + 1] = Native.NativeModuleFuncAddressEntry(func.id, func_plan.entry_address)
        local module_plan = Native.NativeCodeModulePlan(
            Native.NativeCodeModulePlanForSingleFunction(func.id),
            type_layouts,
            addresses,
            { Native.NativeCodeSignaturePlanEntry(signature.id, signature, func_plan.abi) },
            { Native.NativeCodeFunctionSignaturePlanEntry(func.id, func.sig, signature, func_plan.abi) },
            {},
            {},
            {},
            { func_plan }
        )
        return Native.NativeCodeLoweringInput(module_plan, func_plan)
    end

    function Code.CodeModule:plan_native_copy(input)
        if #self.funcs ~= 1 then internal_error("native CodeModule graph construction expects one function in this phase") end
        local func = self.funcs[1]
        module_sig_for_func(self, func):native_abi_projection(input.target)
        return func:plan_native_copy(input, self:native_code_lowering_input(nil, func, input))
    end

    local function result_scalar_from_protocol(protocol)
        if asdl.isa(protocol, Native.NativeCallReturnScalar) then return protocol.scalar end
        internal_error("native C frame entry selection requires a scalar return protocol")
    end

    local function abi_projection_storage_layout(abi, target)
        if asdl.isa(abi, Native.NativeAbiScalarValue) then
            return scalar_storage_layout_for_frame(abi.scalar)
        end
        if asdl.isa(abi, Native.NativeAbiPointerValue) or asdl.isa(abi, Native.NativeAbiByRefValue) then
            return scalar_storage_layout_for_frame(Support.scalar_pointer(target.pointer_bits))
        end
        if asdl.isa(abi, Native.NativeAbiDescriptorValue) then
            local fields = {}
            for _, field in ipairs(abi.fields or {}) do
                fields[#fields + 1] = Native.NativeDescriptorRepresentationField(field.field_name, field.offset, abi_projection_storage_layout(field.value, target).representation)
            end
            return Native.NativeStorageLayout(Native.NativeDescriptorValueRepresentation(abi.layout, fields), abi.layout.size, abi.layout.align or abi.layout.alignment or 1)
        end
        internal_error("native Code ABI projection has no direct frame storage layout")
    end

    local function append_direct_result_slot(state, func_id, shape, storage)
        local existing
        for _, entry in ipairs(state.frame_layout_plan.result_slots or {}) do
            if asdl.isa(entry, Native.NativeFrameDirectResultSlot) and entry.shape:native_code_result_shape_equals(shape) then return entry.slot end
        end
        local offset = align_up(state.frame_layout_plan.next_frame_offset, storage.alignment)
        local slot = Native.NativeFrameSlot(result_frame_slot_id(func_id, "direct"), storage.representation, offset, storage.size, storage.alignment)
        state.frame_layout_plan.slots[#state.frame_layout_plan.slots + 1] = slot
        state.frame_layout_plan.result_slots[#state.frame_layout_plan.result_slots + 1] = Native.NativeFrameDirectResultSlot(shape, slot)
        state.frame_layout_plan.next_frame_offset = slot.offset + slot.size
        return slot
    end

    local function append_sret_result_pointer_slot(state, func_id, pointer_slot, shape)
        state.frame_layout_plan.result_slots[#state.frame_layout_plan.result_slots + 1] = Native.NativeFrameSRetResultSlot(shape, pointer_slot)
        return pointer_slot
    end

    local function append_void_result_slot(state, shape)
        state.frame_layout_plan.result_slots[#state.frame_layout_plan.result_slots + 1] = Native.NativeFrameVoidResultSlot(shape)
    end

    local function direct_result_slot(state)
        for _, entry in ipairs(state.frame_layout_plan.result_slots or {}) do
            if asdl.isa(entry, Native.NativeFrameDirectResultSlot) then return entry.slot, entry.shape end
        end
    end

    local function sret_result_pointer_slot(state)
        for _, entry in ipairs(state.frame_layout_plan.result_slots or {}) do
            if asdl.isa(entry, Native.NativeFrameSRetResultSlot) then return entry.pointer_slot, entry.shape end
        end
    end

    local function native_public_abi_adapter_stack_limit(projection)
        return Native.NativeFrameStackLimit(256, target_frame_alignment(projection.target))
    end

    local function enforce_frame_stack_limit(limit, layout)
        local aligned_size = align_up(layout.size, limit.alignment)
        if aligned_size > limit.max_bytes then
            internal_error("native frame layout requires " .. tostring(aligned_size) .. " bytes, exceeding entry frame stack limit " .. tostring(limit.max_bytes))
        end
    end

    local function produced_scalar_from_inst(inst, value, target)
        if inst.op.produced_native_scalar == nil then
            internal_error("native frame planner has no scalar-result method for CodeInst " .. tostring(inst.id and inst.id.text))
        end
        return inst.op:produced_native_scalar(value, target)
    end

    function Code.CodeInstConst:produced_native_scalar(value, target)
        if self.dst == value then return self.const.ty:native_machine_scalar(target) end
    end

    function Code.CodeInstAlias:produced_native_scalar(value, target)
        if self.dst == value then return self.ty:native_machine_scalar(target) end
    end

    function Core.UnaryNeg:native_unary_result_scalar(ty, target)
        return ty:native_machine_scalar(target)
    end

    function Core.UnaryBitNot:native_unary_result_scalar(ty, target)
        return ty:native_machine_scalar(target)
    end

    function Core.UnaryNot:native_unary_result_scalar(_ty, _target)
        return Support.scalar_bool8()
    end

    function Code.CodeInstUnary:produced_native_scalar(value, target)
        if self.dst == value then return self.op:native_unary_result_scalar(self.ty, target) end
    end

    function Code.CodeInstBinary:produced_native_scalar(value, target)
        if self.dst == value then return self.ty:native_machine_scalar(target) end
    end

    function Code.CodeInstFloatBinary:produced_native_scalar(value, target)
        if self.dst == value then return self.ty:native_machine_scalar(target) end
    end

    function Code.CodeInstCompare:produced_native_scalar(value, _target)
        if self.dst == value then return Support.scalar_bool8() end
    end

    function Code.CodeInst:produced_native_storage_layout(value, target, layout_plan)
        if self.op.produced_native_storage_layout ~= nil then
            return self.op:produced_native_storage_layout(value, target, layout_plan)
        end
        if self.op.produced_native_scalar ~= nil then
            local scalar = self.op:produced_native_scalar(value, target)
            if scalar ~= nil then return scalar_storage_layout(scalar) end
        end
    end

    function Code.CodeInstAggregate:produced_native_storage_layout(value, target, layout_plan)
        if self.dst == value then return self.ty:native_storage_layout(target, layout_plan) end
    end

    function Code.CodeInstArray:produced_native_storage_layout(value, target, layout_plan)
        if self.dst == value then return self.ty:native_storage_layout(target, layout_plan) end
    end

    function Code.CodeInstViewMake:produced_native_storage_layout(value, target, layout_plan)
        if self.dst == value then return Code.CodeTyView(self.elem_ty):native_storage_layout(target, layout_plan) end
    end

    function Code.CodeInstSliceMake:produced_native_storage_layout(value, target, layout_plan)
        if self.dst == value then return Code.CodeTySlice(self.elem_ty):native_storage_layout(target, layout_plan) end
    end

    function Code.CodeInstByteSpanMake:produced_native_storage_layout(value, target, _layout_plan)
        if self.dst == value then return Code.CodeTyByteSpan:native_storage_layout(target) end
    end

    function Code.CodeInstClosure:produced_native_storage_layout(value, target, layout_plan)
        if self.dst == value then return self.ty:native_storage_layout(target, layout_plan) end
    end

    function Code.CodeInstVariantCtor:produced_native_storage_layout(value, target, layout_plan)
        if self.dst == value then return self.ty:native_storage_layout(target, layout_plan) end
    end

    function Code.CodeInstVariantPayload:produced_native_storage_layout(value, target, layout_plan)
        if self.dst == value then return self.variant:native_payload_storage_layout(target, layout_plan) end
    end

    function Code.CodeFunc:native_storage_layout_for_value(value, target, layout_plan)
        for _, param in ipairs(self.params or {}) do
            if param.value == value then return param.ty:native_storage_layout(target, layout_plan) end
        end
        for _, block in ipairs(self.blocks or {}) do
            for _, param in ipairs(block.params or {}) do
                if param.value == value then return param.ty:native_storage_layout(target, layout_plan) end
            end
            for _, inst in ipairs(block.insts or {}) do
                local layout = inst:produced_native_storage_layout(value, target, layout_plan)
                if layout ~= nil then return layout end
            end
        end
        internal_error("native frame planner cannot resolve storage layout for CodeValueId " .. tostring(value and value.text))
    end

    local function representation_is_scalar_like(representation)
        return asdl.isa(representation, Native.NativeScalarValueRepresentation)
            or asdl.isa(representation, Native.NativeAddressValueRepresentation)
            or asdl.isa(representation, Native.NativeOpaquePointerValueRepresentation)
            or asdl.isa(representation, Native.NativeUntypedPointerValueRepresentation)
    end

    function Code.CodeInst:preallocate_native_storage(_input, _frame_alignment)
        return nil
    end

    function Code.CodeInst:preallocate_native_storage_for_value(input, value, layout, frame_alignment)
        if layout ~= nil and not representation_is_scalar_like(layout.representation) then
            return ensure_value_storage_slot(input.state, value, layout, frame_alignment)
        end
    end

    function Code.CodeInstAggregate:preallocate_native_storage(input, frame_alignment)
        return self:preallocate_native_storage_for_value(input, self.dst, self.ty:native_storage_layout(input.plan.target, input.lowering.module.type_layouts), frame_alignment)
    end

    function Code.CodeInstArray:preallocate_native_storage(input, frame_alignment)
        return self:preallocate_native_storage_for_value(input, self.dst, self.ty:native_storage_layout(input.plan.target, input.lowering.module.type_layouts), frame_alignment)
    end

    function Code.CodeInstViewMake:preallocate_native_storage(input, frame_alignment)
        return self:preallocate_native_storage_for_value(input, self.dst, Code.CodeTyView(self.elem_ty):native_storage_layout(input.plan.target, input.lowering.module.type_layouts), frame_alignment)
    end

    function Code.CodeInstSliceMake:preallocate_native_storage(input, frame_alignment)
        return self:preallocate_native_storage_for_value(input, self.dst, Code.CodeTySlice(self.elem_ty):native_storage_layout(input.plan.target, input.lowering.module.type_layouts), frame_alignment)
    end

    function Code.CodeInstByteSpanMake:preallocate_native_storage(input, frame_alignment)
        return self:preallocate_native_storage_for_value(input, self.dst, Code.CodeTyByteSpan:native_storage_layout(input.plan.target, input.lowering.module.type_layouts), frame_alignment)
    end

    function Code.CodeInstVariantCtor:preallocate_native_storage(input, frame_alignment)
        return self:preallocate_native_storage_for_value(input, self.dst, self.ty:native_storage_layout(input.plan.target, input.lowering.module.type_layouts), frame_alignment)
    end

    local function scalar_for_code_value(func, value, target)
        for _, param in ipairs(func.params or {}) do
            if param.value == value then return param.ty:native_machine_scalar(target) end
        end
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do
                if param.value == value then return param.ty:native_machine_scalar(target) end
            end
            for _, inst in ipairs(block.insts or {}) do
                if inst.op.produced_native_scalar ~= nil then
                    local scalar = inst.op:produced_native_scalar(value, target)
                    if scalar ~= nil then return scalar end
                end
            end
        end
        internal_error("native frame planner cannot resolve scalar type for CodeValueId " .. tostring(value and value.text))
    end

    local function find_func_param(func, user_index)
        local param = (func.params or {})[user_index]
        if param == nil then internal_error("native ABI parameter plan has no matching CodeFunc parameter " .. tostring(user_index)) end
        return param
    end

    local function allocate_abi_frame_slots(func, projection, state, target, layout_plan, frame_alignment)
        local user_index = 1
        for _, param in ipairs(projection.params or {}) do
            if asdl.isa(projection.result.abi, Native.NativeAbiSRetResult) and param == projection.result.abi.pointer_param then
                local value = sret_pointer_value_id(func.id)
                local slot = allocate_param_storage_slot(state, value, scalar_storage_layout_for_frame(Support.scalar_pointer(target.pointer_bits)), param.param_index, frame_alignment)
                append_sret_result_pointer_slot(state, func.id, slot.location.slot, projection.result:native_code_result_shape())
            else
                local code_param = find_func_param(func, user_index)
                allocate_param_storage_slot(state, code_param.value, code_param.ty:native_storage_layout(target, layout_plan), param.param_index, frame_alignment)
                user_index = user_index + 1
            end
        end
        if user_index <= #(func.params or {}) then internal_error("native ABI parameter plan did not consume all CodeFunc parameters") end
    end

    local function allocate_result_frame_slot(func, projection, state, target)
        local shape = projection.result:native_code_result_shape()
        if asdl.isa(shape, Native.NativeCodeResultVoidShape) then
            append_void_result_slot(state, shape)
            return nil
        end
        if asdl.isa(shape, Native.NativeCodeResultSRetShape) then return sret_result_pointer_slot(state) end
        return append_direct_result_slot(state, func.id, shape, abi_projection_storage_layout(projection.result.abi, target))
    end

    local function append_block_entry_node(input, block)
        local family = Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())
        local node_id = block_entry_node_id(block.id)
        local node = Native.NativeTemplateNode(node_id, instance_id_for(node_id), family, {}, {}, {})
        return append_node(input.state, node)
    end

    local function entry_binding_specs_for_projection(func, projection, state)
        local token = projection:native_projection_token()
        local specs = { hole("native.hole.code.func.public_abi_adapter." .. token .. ".frame_size", Native.NativePatchFrameSize(align_up(state.frame_layout_plan.next_frame_offset, target_frame_alignment(projection.target)))) }
        local user_index = 1
        for _, param in ipairs(projection.params or {}) do
            local offset
            if asdl.isa(projection.result.abi, Native.NativeAbiSRetResult) and param == projection.result.abi.pointer_param then
                local slot = sret_result_pointer_slot(state)
                if slot == nil then internal_error("native public ABI adapter needs reserved sret pointer slot") end
                offset = slot.offset
            else
                local code_param = find_func_param(func, user_index)
                offset = placement_for_value(state, code_param.value).location.slot.offset
                user_index = user_index + 1
            end
            specs[#specs + 1] = hole("native.hole.code.func.public_abi_adapter." .. token .. ".param" .. tostring(param.param_index), Native.NativePatchFrameOffset(offset))
        end
        if not asdl.isa(projection.result.abi, Native.NativeAbiVoidResult) and not asdl.isa(projection.result.abi, Native.NativeAbiSRetResult) then
            local result_slot = direct_result_slot(state)
            if result_slot == nil then internal_error("native public ABI adapter needs reserved direct result slot") end
            specs[#specs + 1] = hole("native.hole.code.func.public_abi_adapter." .. token .. ".result", Native.NativePatchFrameOffset(result_slot.offset))
        end
        return specs
    end

    local function native_fast_block_entry_region_id(func, block_id)
        return Native.NativeFastRegionId("native.fast.code." .. func.id.text .. "." .. block_id.text .. ".entry")
    end

    local function native_fast_inst_region_id(func, inst, suffix)
        return Native.NativeFastRegionId("native.fast.code." .. func.id.text .. "." .. inst.id.text .. (suffix and ("." .. suffix) or ""))
    end

    local function native_fast_term_region_id(func, term, suffix)
        return Native.NativeFastRegionId("native.fast.code." .. func.id.text .. "." .. term.id.text .. (suffix and ("." .. suffix) or ""))
    end

    local function native_fast_code_region_origin(func, block, first_inst, last_inst)
        if first_inst ~= nil and last_inst ~= nil then
            return Native.NativeCodeTraceRegion(func.id, first_inst.id, last_inst.id)
        end
        return Native.NativeCodeBlockRegion(func.id, block.id)
    end

    local function native_fast_region(id, origin, body, inputs, outputs, transfer)
        return Native.NativeFastRegion(id, origin, body, inputs or {}, outputs or {}, transfer)
    end

    local function frame_residence_for_placement(placement)
        if asdl.isa(placement.location, Native.NativeValueFrameSlotLocation) then
            return Native.NativeResidenceFrameSlot(placement.location.slot)
        end
        internal_error("native fast Code region requires a frame-slot boundary residence")
    end

    local function frame_binding_for_placement(placement)
        return Native.NativeRegionValueBinding(placement.value, placement.representation:native_scalar_rep(), frame_residence_for_placement(placement))
    end

    local function frame_binding_for_code_value(input, value)
        return frame_binding_for_placement(placement_for_value(input.state, value))
    end

    local function immediate_binding_for_code_value(value, scalar, coordinate)
        return Native.NativeRegionValueBinding(native_value_id(value), scalar, Native.NativeResidenceImmediate(scalar, coordinate))
    end

    local function append_native_fast_input_atom(bindings, binding)
        local ordinal = #bindings
        bindings[#bindings + 1] = binding
        return Native.NativeExprInput(ordinal, binding.scalar)
    end

    local function append_native_fast_frame_atom(input, bindings, value)
        return append_native_fast_input_atom(bindings, frame_binding_for_code_value(input, value))
    end

    function Code.CodeConst:native_fast_immediate_coordinate(_target)
        return nil
    end

    function Code.CodeConstLiteral:native_fast_immediate_coordinate(target)
        local scalar = self.ty:native_machine_scalar(target)
        return self.literal:native_patch_coordinate_for_scalar(scalar), scalar
    end

    function Code.CodeConstNull:native_fast_immediate_coordinate(target)
        local scalar = self.ty:native_machine_scalar(target)
        return scalar:native_null_patch_coordinate(), scalar
    end

    function Code.CodeConstUndef:native_fast_immediate_coordinate(_target)
        return nil
    end

    function Code.CodeInstOp:native_fast_output_value()
        return nil
    end

    function Code.CodeInstConst:native_fast_output_value() return self.dst end
    function Code.CodeInstAlias:native_fast_output_value() return self.dst end
    function Code.CodeInstUnary:native_fast_output_value() return self.dst end
    function Code.CodeInstBinary:native_fast_output_value() return self.dst end
    function Code.CodeInstFloatBinary:native_fast_output_value() return self.dst end
    function Code.CodeInstCompare:native_fast_output_value() return self.dst end
    function Code.CodeInstCast:native_fast_output_value() return self.dst end
    function Code.CodeInstSelect:native_fast_output_value() return self.dst end
    function Code.CodeInstIntrinsic:native_fast_output_value() return self.dst end
    function Code.CodeInstAddrOf:native_fast_output_value() return self.dst end
    function Code.CodeInstGlobalRef:native_fast_output_value() return self.dst end
    function Code.CodeInstPtrOffset:native_fast_output_value() return self.dst end
    function Code.CodeInstLoad:native_fast_output_value() return self.dst end
    function Code.CodeInstAggregate:native_fast_output_value() return self.dst end
    function Code.CodeInstArray:native_fast_output_value() return self.dst end
    function Code.CodeInstViewMake:native_fast_output_value() return self.dst end
    function Code.CodeInstViewData:native_fast_output_value() return self.dst end
    function Code.CodeInstViewLen:native_fast_output_value() return self.dst end
    function Code.CodeInstViewStride:native_fast_output_value() return self.dst end
    function Code.CodeInstSliceMake:native_fast_output_value() return self.dst end
    function Code.CodeInstSliceData:native_fast_output_value() return self.dst end
    function Code.CodeInstSliceLen:native_fast_output_value() return self.dst end
    function Code.CodeInstByteSpanMake:native_fast_output_value() return self.dst end
    function Code.CodeInstByteSpanData:native_fast_output_value() return self.dst end
    function Code.CodeInstByteSpanLen:native_fast_output_value() return self.dst end
    function Code.CodeInstClosure:native_fast_output_value() return self.dst end
    function Code.CodeInstVariantCtor:native_fast_output_value() return self.dst end
    function Code.CodeInstVariantTag:native_fast_output_value() return self.dst end
    function Code.CodeInstVariantPayload:native_fast_output_value() return self.dst end
    function Code.CodeInstCall:native_fast_output_value() return self.dst end
    function Code.CodeInstAtomicLoad:native_fast_output_value() return self.dst end
    function Code.CodeInstAtomicRmw:native_fast_output_value() return self.dst end
    function Code.CodeInstAtomicCas:native_fast_output_value() return self.dst end

    function Code.CodeInst:native_fast_output_value()
        return self.op:native_fast_output_value()
    end

    function Code.CodeInst:preallocate_native_fast_storage(input, frame_alignment)
        local value = self:native_fast_output_value()
        if value == nil then return nil end
        local layout = self:produced_native_storage_layout(value, input.plan.target, input.lowering.module.type_layouts)
        if layout ~= nil then return ensure_value_storage_slot(input.state, value, layout, frame_alignment) end
    end

    local function find_native_fast_producer(block, value, max_index)
        local last = max_index or #(block.insts or {})
        for i = last, 1, -1 do
            local inst = block.insts[i]
            if inst:native_fast_output_value() == value then return inst, i end
        end
    end

    local function native_fast_immediate_from_inst(input, inst)
        if inst == nil or not asdl.isa(inst.op, Code.CodeInstConst) then return nil end
        local coordinate, scalar = inst.op.const:native_fast_immediate_coordinate(input.plan.target)
        if coordinate == nil then return nil end
        return immediate_binding_for_code_value(inst.op.dst, scalar, coordinate), scalar
    end

    local function native_fast_atom_for_value(input, block, value, max_index, bindings)
        local producer = find_native_fast_producer(block, value, max_index)
        local immediate, scalar = native_fast_immediate_from_inst(input, producer)
        if immediate ~= nil then
            bindings[#bindings + 1] = immediate
            return Native.NativeExprImmediate(scalar), producer
        end
        return append_native_fast_frame_atom(input, bindings, value), nil
    end

    function Native.NativeCodeResultShape:native_fast_direct_result_scalar()
        return nil
    end

    function Native.NativeCodeResultScalarShape:native_fast_direct_result_scalar()
        return self.scalar
    end

    function Native.NativeCodeResultPointerShape:native_fast_direct_result_scalar()
        return self.scalar
    end

    local function native_fast_public_result_binding(input, value, _scalar)
        return frame_binding_for_code_value(input, value)
    end

    local function native_fast_public_result_residence_binding(input, value, scalar)
        return Native.NativeRegionValueBinding(
            native_value_id(value),
            scalar,
            Native.NativeResidencePublicResult(input.lowering.active_func.abi.result.abi)
        )
    end

    local function native_fast_public_param_binding(input, func, value)
        for i, param in ipairs(func.params or {}) do
            if param.value == value then
                local projection = input.lowering.active_func.abi.params[i]
                if projection == nil then return nil end
                local scalar = projection.abi:native_fast_public_operand_scalar(input.plan.target)
                if scalar == nil then return nil end
                return Native.NativeRegionValueBinding(
                    native_value_id(value),
                    scalar,
                    Native.NativeResidencePublicParam(projection.param_index, projection.abi)
                )
            end
        end
    end

    local function append_native_fast_public_param_atom(bindings, binding)
        bindings[#bindings + 1] = binding
        return Native.NativeExprInput(binding.residence.index, binding.scalar)
    end

    local function native_fast_public_atom_for_value(input, func, block, value, max_index, bindings)
        local producer = find_native_fast_producer(block, value, max_index)
        local immediate, scalar = native_fast_immediate_from_inst(input, producer)
        if immediate ~= nil then
            bindings[#bindings + 1] = immediate
            return Native.NativeExprImmediate(scalar), producer
        end
        local public = native_fast_public_param_binding(input, func, value)
        if public ~= nil then return append_native_fast_public_param_atom(bindings, public), nil end
        return nil, nil
    end

    local function native_fast_public_abi_shape_for_func(func, projection, target)
        if #(func.params or {}) ~= #(projection.params or {}) then return nil end
        if projection.result.abi:native_fast_public_operand_scalar(target) == nil then return nil end
        local params = {}
        for i, param in ipairs(projection.params or {}) do
            if param.param_index ~= i - 1 then return nil end
            if param.abi:native_fast_public_operand_scalar(target) == nil then return nil end
            params[#params + 1] = param.abi
        end
        if #params == 0 then return Native.NativeFastAbi0(projection.result.abi) end
        if #params == 1 then return Native.NativeFastAbi1(params[1], projection.result.abi) end
        if #params == 2 then return Native.NativeFastAbi2(params[1], params[2], projection.result.abi) end
        if #params == 3 then return Native.NativeFastAbi3(params[1], params[2], params[3], projection.result.abi) end
        return nil
    end

    local function loaded_bank_has_template_family(bank, family)
        local manifest = bank and bank.artifact and bank.artifact.manifest
        for _, group in ipairs((manifest and manifest.groups) or {}) do
            for _, entry in ipairs(group.entries or {}) do
                if entry.family.id == family.id then return true end
            end
        end
        return false
    end

    function Code.CodeIntOverflow:native_fast_wrapping_overflow()
        return false
    end

    function Code.CodeIntWrap:native_fast_wrapping_overflow()
        return true
    end

    function Code.CodeDivPolicy:native_fast_div_policy_supported()
        return false
    end

    function Code.CodeDivTrapOnZero:native_fast_div_policy_supported()
        return true
    end

    function Code.CodeShiftPolicy:native_fast_shift_policy_supported()
        return false
    end

    function Code.CodeShiftMaskCount:native_fast_shift_policy_supported()
        return true
    end

    function Code.CodeIntSemantics:native_fast_wrap_mask_semantics()
        return self.overflow:native_fast_wrapping_overflow()
            and self.div:native_fast_div_policy_supported()
            and self.shift:native_fast_shift_policy_supported()
    end

    function Core.BinaryOp:native_fast_int_binary_supported(_semantics)
        return false
    end

    function Core.BinAdd:native_fast_int_binary_supported(semantics) return semantics:native_fast_wrap_mask_semantics() end
    function Core.BinSub:native_fast_int_binary_supported(semantics) return semantics:native_fast_wrap_mask_semantics() end
    function Core.BinMul:native_fast_int_binary_supported(semantics) return semantics:native_fast_wrap_mask_semantics() end
    function Core.BinBitAnd:native_fast_int_binary_supported(_semantics) return true end
    function Core.BinBitOr:native_fast_int_binary_supported(_semantics) return true end
    function Core.BinBitXor:native_fast_int_binary_supported(_semantics) return true end
    function Core.BinShl:native_fast_int_binary_supported(semantics) return semantics.shift:native_fast_shift_policy_supported() end
    function Core.BinLShr:native_fast_int_binary_supported(semantics) return semantics.shift:native_fast_shift_policy_supported() end
    function Core.BinAShr:native_fast_int_binary_supported(semantics) return semantics.shift:native_fast_shift_policy_supported() end

    function Core.BinaryOp:native_fast_mul_op_supported()
        return false
    end

    function Core.BinMul:native_fast_mul_op_supported()
        return true
    end

    function Core.BinaryOp:native_fast_add_op_supported()
        return false
    end

    function Core.BinAdd:native_fast_add_op_supported()
        return true
    end

    function Code.CodeInstOp:native_frame_micro_op_region_parts(_input)
        internal_error("CodeInstOp leaf is missing native fast baseline micro-op projection")
    end

    function Code.CodeInstConst:native_frame_micro_op_region_parts(input)
        local scalar = self.const.ty:native_machine_scalar(input.plan.target)
        local output = frame_binding_for_code_value(input, self.dst)
        local family = Support.code_const_frame_family("literal." .. scalar_token(scalar), input.plan.target, scalar, Native.NativeCodeConstLiteralAxis(self.const.ty))
        return Native.NativeFrameMicroOpRegion(family), {}, { output }
    end

    function Code.CodeInstAlias:native_frame_micro_op_region_parts(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local family = Support.code_inst_frame_family("alias." .. scalar_token(scalar), input.plan.target, scalar, Native.NativeCodeInstAliasAxis(self.ty))
        return Native.NativeFrameMicroOpRegion(family), { frame_binding_for_code_value(input, self.src) }, { frame_binding_for_code_value(input, self.dst) }
    end

    function Code.CodeInstUnary:native_frame_micro_op_region_parts(input)
        local source_scalar = self.ty:native_machine_scalar(input.plan.target)
        local result_scalar = self.op:native_unary_result_scalar(self.ty, input.plan.target)
        local name = self.op:native_unary_family_name()
        local family = Support.code_inst_frame_family("unary." .. scalar_token(source_scalar) .. "." .. name, input.plan.target, source_scalar, Native.NativeCodeInstUnaryAxis(self.op, self.ty))
        return Native.NativeFrameMicroOpRegion(family), { frame_binding_for_code_value(input, self.value) }, { frame_binding_for_code_value(input, self.dst) }
    end

    function Code.CodeInstBinary:native_frame_micro_op_region_parts(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local name = self.op:native_binary_family_name()
        local family = Support.code_inst_frame_family("binary." .. scalar_token(scalar) .. "." .. name, input.plan.target, scalar, Native.NativeCodeInstBinaryAxis(self.op, self.ty, self.semantics))
        return Native.NativeFrameMicroOpRegion(family), { frame_binding_for_code_value(input, self.lhs), frame_binding_for_code_value(input, self.rhs) }, { frame_binding_for_code_value(input, self.dst) }
    end

    function Code.CodeInstFloatBinary:native_frame_micro_op_region_parts(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local name = self.op:native_binary_family_name()
        local family = Support.code_inst_frame_family("float_binary." .. scalar_token(scalar) .. "." .. name, input.plan.target, scalar, Native.NativeCodeInstFloatBinaryAxis(self.op, self.ty, self.mode))
        return Native.NativeFrameMicroOpRegion(family), { frame_binding_for_code_value(input, self.lhs), frame_binding_for_code_value(input, self.rhs) }, { frame_binding_for_code_value(input, self.dst) }
    end

    function Code.CodeInstCompare:native_frame_micro_op_region_parts(input)
        local operand_scalar = self.operand_ty:native_machine_scalar(input.plan.target)
        local name = self.op:native_compare_family_name()
        local family = Support.code_inst_frame_family("compare." .. scalar_token(operand_scalar) .. "." .. name, input.plan.target, operand_scalar, Native.NativeCodeInstCompareAxis(self.op, self.operand_ty))
        return Native.NativeFrameMicroOpRegion(family), { frame_binding_for_code_value(input, self.lhs), frame_binding_for_code_value(input, self.rhs) }, { frame_binding_for_code_value(input, self.dst) }
    end

    function Code.CodeInst:native_frame_micro_op_region(input, func, block, transfer)
        local body, inputs, outputs = self.op:native_frame_micro_op_region_parts(input)
        return native_fast_region(
            native_fast_inst_region_id(func, self),
            native_fast_code_region_origin(func, block, self, self),
            body,
            inputs,
            outputs,
            transfer
        )
    end

    function Code.CodeInstConst:native_fast_return_expr_region(input, func, block, inst, term, result_scalar)
        local immediate, scalar = native_fast_immediate_from_inst(input, inst)
        if immediate == nil then return nil end
        local shape = Native.NativeExprReturnAtom(result_scalar, Native.NativeExprImmediate(scalar))
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_const"),
            native_fast_code_region_origin(func, block, inst, inst),
            Native.NativeCodeExprRegion(shape),
            { immediate },
            { native_fast_public_result_binding(input, self.dst, result_scalar) },
            Native.NativeRegionReturn
        ), #block.insts
    end

    function Code.CodeInstUnary:native_fast_return_expr_region(input, func, block, inst, term, result_scalar)
        local inputs = {}
        local atom = native_fast_atom_for_value(input, block, self.value, nil, inputs)
        local shape = Native.NativeExprReturnUnary(result_scalar, self.op, atom)
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_unary"),
            native_fast_code_region_origin(func, block, inst, inst),
            Native.NativeCodeExprRegion(shape),
            inputs,
            { native_fast_public_result_binding(input, self.dst, result_scalar) },
            Native.NativeRegionReturn
        ), #block.insts
    end

    function Code.CodeInstFloatBinary:native_fast_return_expr_region(input, func, block, inst, term, result_scalar)
        local inputs = {}
        local lhs = native_fast_atom_for_value(input, block, self.lhs, nil, inputs)
        local rhs = native_fast_atom_for_value(input, block, self.rhs, nil, inputs)
        local shape = Native.NativeExprReturnBinary(result_scalar, self.op, lhs, rhs)
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_float_binary"),
            native_fast_code_region_origin(func, block, inst, inst),
            Native.NativeCodeExprRegion(shape),
            inputs,
            { native_fast_public_result_binding(input, self.dst, result_scalar) },
            Native.NativeRegionReturn
        ), #block.insts
    end

    local function native_fast_binary_immediate_region(input, func, block, inst, term, result_scalar, const_inst, first_index)
        local op = inst.op
        local immediate = native_fast_immediate_from_inst(input, const_inst)
        if immediate == nil then return nil end
        local inputs = {}
        local lhs = append_native_fast_frame_atom(input, inputs, op.lhs)
        inputs[#inputs + 1] = immediate
        local shape = Native.NativeExprReturnBinaryImmRhs(result_scalar, op.op, lhs)
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_binary_imm_rhs"),
            native_fast_code_region_origin(func, block, const_inst, inst),
            Native.NativeCodeExprRegion(shape),
            inputs,
            { native_fast_public_result_binding(input, op.dst, result_scalar) },
            Native.NativeRegionReturn
        ), first_index
    end

    local function native_fast_mul_add_immediate_region(input, func, block, inst, term, result_scalar, mul_inst, const_inst, first_index)
        local add = inst.op
        local mul = mul_inst.op
        if not add.op:native_fast_add_op_supported() or not mul.op:native_fast_mul_op_supported() then return nil end
        if not mul.semantics:native_fast_wrap_mask_semantics() then return nil end
        local immediate = native_fast_immediate_from_inst(input, const_inst)
        if immediate == nil then return nil end
        local inputs = {}
        local lhs = native_fast_atom_for_value(input, block, mul.lhs, nil, inputs)
        local rhs = native_fast_atom_for_value(input, block, mul.rhs, nil, inputs)
        inputs[#inputs + 1] = immediate
        local shape = Native.NativeExprReturnMulAddImm(result_scalar, lhs, rhs)
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_mul_add_imm"),
            native_fast_code_region_origin(func, block, block.insts[first_index], inst),
            Native.NativeCodeExprRegion(shape),
            inputs,
            { native_fast_public_result_binding(input, add.dst, result_scalar) },
            Native.NativeRegionReturn
        ), first_index
    end

    function Code.CodeInstBinary:native_fast_return_expr_region(input, func, block, inst, term, result_scalar)
        if not self.op:native_fast_int_binary_supported(self.semantics) then return nil end
        local inst_index = #block.insts
        local left_producer, left_index = find_native_fast_producer(block, self.lhs, inst_index - 1)
        local right_producer, right_index = find_native_fast_producer(block, self.rhs, inst_index - 1)
        if left_producer ~= nil and asdl.isa(left_producer.op, Code.CodeInstBinary) and right_producer ~= nil and asdl.isa(right_producer.op, Code.CodeInstConst) then
            local fused, first = native_fast_mul_add_immediate_region(input, func, block, inst, term, result_scalar, left_producer, right_producer, math.min(left_index, right_index))
            if fused ~= nil then return fused, first end
        end
        if right_producer ~= nil and asdl.isa(right_producer.op, Code.CodeInstBinary) and left_producer ~= nil and asdl.isa(left_producer.op, Code.CodeInstConst) then
            local fused, first = native_fast_mul_add_immediate_region(input, func, block, inst, term, result_scalar, right_producer, left_producer, math.min(left_index, right_index))
            if fused ~= nil then return fused, first end
        end
        local previous = block.insts[inst_index - 1]
        if previous ~= nil and self.rhs == previous:native_fast_output_value() then
            local imm_region, imm_first = native_fast_binary_immediate_region(input, func, block, inst, term, result_scalar, previous, inst_index - 1)
            if imm_region ~= nil then return imm_region, imm_first end
        end
        local inputs = {}
        local lhs = native_fast_atom_for_value(input, block, self.lhs, inst_index - 1, inputs)
        local rhs = native_fast_atom_for_value(input, block, self.rhs, inst_index - 1, inputs)
        local shape = Native.NativeExprReturnBinary(result_scalar, self.op, lhs, rhs)
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_binary"),
            native_fast_code_region_origin(func, block, inst, inst),
            Native.NativeCodeExprRegion(shape),
            inputs,
            { native_fast_public_result_binding(input, self.dst, result_scalar) },
            Native.NativeRegionReturn
        ), inst_index
    end

    function Code.CodeInstOp:native_fast_return_expr_region(_input, _func, _block, _inst, _term, _result_scalar)
        return nil
    end

    function Code.CodeInstOp:native_fast_public_return_expr_region(_input, _func, _block, _inst, _term, _result_scalar, _abi_shape)
        return nil
    end

    local function native_fast_public_code_expr_region(input, func, block, first_inst, last_inst, term, abi_shape, shape, inputs, result_value, result_scalar, suffix)
        return native_fast_region(
            native_fast_term_region_id(func, term, suffix),
            native_fast_code_region_origin(func, block, first_inst, last_inst),
            Native.NativeFastPublicCodeExprRegion(abi_shape, shape),
            inputs,
            { native_fast_public_result_residence_binding(input, result_value, result_scalar) },
            Native.NativeRegionReturn
        )
    end

    function Code.CodeInstConst:native_fast_public_return_expr_region(input, func, block, inst, term, result_scalar, abi_shape)
        local immediate, scalar = native_fast_immediate_from_inst(input, inst)
        if immediate == nil then return nil end
        local shape = Native.NativeExprReturnAtom(result_scalar, Native.NativeExprImmediate(scalar))
        return native_fast_public_code_expr_region(input, func, block, inst, inst, term, abi_shape, shape, { immediate }, self.dst, result_scalar, "public_return_const"), #block.insts
    end

    function Code.CodeInstUnary:native_fast_public_return_expr_region(input, func, block, inst, term, result_scalar, abi_shape)
        local inputs = {}
        local atom = native_fast_public_atom_for_value(input, func, block, self.value, nil, inputs)
        if atom == nil then return nil end
        local shape = Native.NativeExprReturnUnary(result_scalar, self.op, atom)
        return native_fast_public_code_expr_region(input, func, block, inst, inst, term, abi_shape, shape, inputs, self.dst, result_scalar, "public_return_unary"), #block.insts
    end

    function Code.CodeInstFloatBinary:native_fast_public_return_expr_region(input, func, block, inst, term, result_scalar, abi_shape)
        local inputs = {}
        local lhs = native_fast_public_atom_for_value(input, func, block, self.lhs, nil, inputs)
        local rhs = native_fast_public_atom_for_value(input, func, block, self.rhs, nil, inputs)
        if lhs == nil or rhs == nil then return nil end
        local shape = Native.NativeExprReturnBinary(result_scalar, self.op, lhs, rhs)
        return native_fast_public_code_expr_region(input, func, block, inst, inst, term, abi_shape, shape, inputs, self.dst, result_scalar, "public_return_float_binary"), #block.insts
    end

    local function native_fast_public_binary_immediate_region(input, func, block, inst, term, result_scalar, abi_shape, const_inst, first_index)
        local op = inst.op
        local immediate = native_fast_immediate_from_inst(input, const_inst)
        if immediate == nil then return nil end
        local inputs = {}
        local lhs = native_fast_public_atom_for_value(input, func, block, op.lhs, first_index - 1, inputs)
        if lhs == nil then return nil end
        inputs[#inputs + 1] = immediate
        local shape = Native.NativeExprReturnBinaryImmRhs(result_scalar, op.op, lhs)
        return native_fast_public_code_expr_region(input, func, block, const_inst, inst, term, abi_shape, shape, inputs, op.dst, result_scalar, "public_return_binary_imm_rhs"), first_index
    end

    local function native_fast_public_mul_add_immediate_region(input, func, block, inst, term, result_scalar, abi_shape, mul_inst, const_inst, first_index)
        local add = inst.op
        local mul = mul_inst.op
        if not add.op:native_fast_add_op_supported() or not mul.op:native_fast_mul_op_supported() then return nil end
        if not mul.semantics:native_fast_wrap_mask_semantics() then return nil end
        local immediate = native_fast_immediate_from_inst(input, const_inst)
        if immediate == nil then return nil end
        local inputs = {}
        local lhs = native_fast_public_atom_for_value(input, func, block, mul.lhs, first_index - 1, inputs)
        local rhs = native_fast_public_atom_for_value(input, func, block, mul.rhs, first_index - 1, inputs)
        if lhs == nil or rhs == nil then return nil end
        inputs[#inputs + 1] = immediate
        local shape = Native.NativeExprReturnMulAddImm(result_scalar, lhs, rhs)
        return native_fast_public_code_expr_region(input, func, block, block.insts[first_index], inst, term, abi_shape, shape, inputs, add.dst, result_scalar, "public_return_mul_add_imm"), first_index
    end

    function Code.CodeInstBinary:native_fast_public_return_expr_region(input, func, block, inst, term, result_scalar, abi_shape)
        if not self.op:native_fast_int_binary_supported(self.semantics) then return nil end
        local inst_index = #block.insts
        local left_producer, left_index = find_native_fast_producer(block, self.lhs, inst_index - 1)
        local right_producer, right_index = find_native_fast_producer(block, self.rhs, inst_index - 1)
        if left_producer ~= nil and asdl.isa(left_producer.op, Code.CodeInstBinary) and right_producer ~= nil and asdl.isa(right_producer.op, Code.CodeInstConst) then
            local fused, first = native_fast_public_mul_add_immediate_region(input, func, block, inst, term, result_scalar, abi_shape, left_producer, right_producer, math.min(left_index, right_index))
            if fused ~= nil then return fused, first end
        end
        if right_producer ~= nil and asdl.isa(right_producer.op, Code.CodeInstBinary) and left_producer ~= nil and asdl.isa(left_producer.op, Code.CodeInstConst) then
            local fused, first = native_fast_public_mul_add_immediate_region(input, func, block, inst, term, result_scalar, abi_shape, right_producer, left_producer, math.min(left_index, right_index))
            if fused ~= nil then return fused, first end
        end
        local previous = block.insts[inst_index - 1]
        if previous ~= nil and self.rhs == previous:native_fast_output_value() then
            local imm_region, imm_first = native_fast_public_binary_immediate_region(input, func, block, inst, term, result_scalar, abi_shape, previous, inst_index - 1)
            if imm_region ~= nil then return imm_region, imm_first end
        end
        local inputs = {}
        local lhs = native_fast_public_atom_for_value(input, func, block, self.lhs, inst_index - 1, inputs)
        local rhs = native_fast_public_atom_for_value(input, func, block, self.rhs, inst_index - 1, inputs)
        if lhs == nil or rhs == nil then return nil end
        local shape = Native.NativeExprReturnBinary(result_scalar, self.op, lhs, rhs)
        return native_fast_public_code_expr_region(input, func, block, inst, inst, term, abi_shape, shape, inputs, self.dst, result_scalar, "public_return_binary"), inst_index
    end

    local function native_fast_public_return_atom_region(input, func, block, term, result_value, result_scalar, abi_shape)
        local inputs = {}
        local atom, producer = native_fast_public_atom_for_value(input, func, block, result_value, #block.insts, inputs)
        if atom == nil then return nil end
        if producer ~= nil and producer ~= block.insts[1] then return nil end
        local shape = Native.NativeExprReturnAtom(result_scalar, atom)
        return native_fast_public_code_expr_region(input, func, block, producer, producer, term, abi_shape, shape, inputs, result_value, result_scalar, "public_return_atom"), producer and 1 or nil
    end

    local function native_fast_return_atom_region(input, func, block, term, result_value, result_scalar)
        local inputs = {}
        local atom = native_fast_atom_for_value(input, block, result_value, #block.insts, inputs)
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_atom"),
            native_fast_code_region_origin(func, block, nil, nil),
            Native.NativeCodeExprRegion(Native.NativeExprReturnAtom(result_scalar, atom)),
            inputs,
            { native_fast_public_result_binding(input, result_value, result_scalar) },
            Native.NativeRegionReturn
        ), nil
    end

    local function native_fast_compare_shape_for_inst(input, block, inst, inst_index, inputs)
        local cmp = inst.op
        local scalar = cmp.operand_ty:native_machine_scalar(input.plan.target)
        local rhs_producer = find_native_fast_producer(block, cmp.rhs, inst_index - 1)
        local immediate = native_fast_immediate_from_inst(input, rhs_producer)
        if immediate ~= nil and rhs_producer == block.insts[inst_index - 1] then
            local lhs = append_native_fast_frame_atom(input, inputs, cmp.lhs)
            inputs[#inputs + 1] = immediate
            return Native.NativeCompareBranchImmRhs(cmp.op, scalar, lhs), inst_index - 1
        end
        local lhs = native_fast_atom_for_value(input, block, cmp.lhs, inst_index - 1, inputs)
        local rhs = native_fast_atom_for_value(input, block, cmp.rhs, inst_index - 1, inputs)
        return Native.NativeCompareBranchAtoms(cmp.op, scalar, lhs, rhs), inst_index
    end

    function Code.CodeTermOp:native_fast_terminal_region(_input, _func, _block, _term)
        internal_error("CodeTermOp leaf is missing native fast terminal projection")
    end

    local function native_fast_term_return_baseline_region(input, func, block, term)
        local shape = input.lowering.active_func.abi.result:native_code_result_shape()
        local scalar = shape:native_result_family_scalar(input.plan.target)
        local family = Support.code_term_frame_family("return." .. shape:native_result_shape_token(), input.plan.target, scalar, Native.NativeCodeTermReturnShapeAxis(shape))
        local inputs = {}
        if #(term.values or {}) == 1 then inputs[1] = frame_binding_for_code_value(input, term.values[1]) end
        local outputs = {}
        if #(term.values or {}) == 1 and shape:native_fast_direct_result_scalar() ~= nil then
            outputs[1] = native_fast_public_result_binding(input, term.values[1], shape:native_fast_direct_result_scalar())
        end
        return native_fast_region(
            native_fast_term_region_id(func, term, "return_baseline"),
            native_fast_code_region_origin(func, block, nil, nil),
            Native.NativeFrameMicroOpRegion(family),
            inputs,
            outputs,
            Native.NativeRegionReturn
        ), nil
    end

    function Code.CodeTermReturn:native_fast_terminal_region(input, func, block, term)
        if #(self.values or {}) > 1 then internal_error("Lalin native CodeTermReturn is invalid: Lalin has zero or one return value") end
        local shape = input.lowering.active_func.abi.result:native_code_result_shape()
        local result_scalar = shape:native_fast_direct_result_scalar()
        if result_scalar == nil or #(self.values or {}) ~= 1 then return native_fast_term_return_baseline_region(input, func, block, term) end
        local result_value = self.values[1]
        local last_inst = block.insts[#block.insts]
        if last_inst ~= nil and last_inst:native_fast_output_value() == result_value then
            local region, first_index = last_inst.op:native_fast_return_expr_region(input, func, block, last_inst, term, result_scalar)
            if region ~= nil then return region, first_index end
        end
        return native_fast_return_atom_region(input, func, block, term, result_value, result_scalar)
    end

    function Code.CodeTermOp:native_fast_public_terminal_region(_input, _func, _block, _term, _abi_shape)
        return nil
    end

    function Code.CodeTermReturn:native_fast_public_terminal_region(input, func, block, term, abi_shape)
        if #(self.values or {}) ~= 1 then return nil end
        local result_scalar = input.lowering.active_func.abi.result.abi:native_fast_public_operand_scalar(input.plan.target)
        if result_scalar == nil then return nil end
        local result_value = self.values[1]
        local last_inst = block.insts[#block.insts]
        if last_inst ~= nil and last_inst:native_fast_output_value() == result_value then
            local region, first_index = last_inst.op:native_fast_public_return_expr_region(input, func, block, last_inst, term, result_scalar, abi_shape)
            if region ~= nil and first_index == 1 then return region end
            return nil
        end
        if #(block.insts or {}) > 1 then return nil end
        return native_fast_public_return_atom_region(input, func, block, term, result_value, result_scalar, abi_shape)
    end

    function Code.CodeTerm:native_fast_public_terminal_region(input, func, block, abi_shape)
        return self.op:native_fast_public_terminal_region(input, func, block, self, abi_shape)
    end

    function Code.CodeTermJump:native_fast_terminal_region(input, func, block, term)
        local family = Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())
        return native_fast_region(
            native_fast_term_region_id(func, term, "jump_baseline"),
            native_fast_code_region_origin(func, block, nil, nil),
            Native.NativeFrameMicroOpRegion(family),
            {},
            {},
            Native.NativeRegionJump(native_fast_block_entry_region_id(func, self.dest))
        ), nil
    end

    function Code.CodeTermBranch:native_fast_terminal_region(input, func, block, term)
        local last_inst = block.insts[#block.insts]
        if last_inst ~= nil and asdl.isa(last_inst.op, Code.CodeInstCompare) and last_inst.op.dst == self.cond and #(self.then_args or {}) == 0 and #(self.else_args or {}) == 0 then
            local inputs = {}
            local shape, first_index = native_fast_compare_shape_for_inst(input, block, last_inst, #block.insts, inputs)
            return native_fast_region(
                native_fast_term_region_id(func, term, "compare_branch"),
                native_fast_code_region_origin(func, block, block.insts[first_index], last_inst),
                Native.NativeCodeCompareBranchRegion(shape),
                inputs,
                {},
                Native.NativeRegionBranch(native_value_id(self.cond), native_fast_block_entry_region_id(func, self.then_dest), native_fast_block_entry_region_id(func, self.else_dest))
            ), first_index
        end
        local cond = frame_binding_for_code_value(input, self.cond)
        local family = Support.code_term_family("branch.bool8.slot", input.plan.target, Native.NativeCodeTermBranchAxis, Support.protocol_void_none())
        return native_fast_region(
            native_fast_term_region_id(func, term, "branch_baseline"),
            native_fast_code_region_origin(func, block, nil, nil),
            Native.NativeFrameMicroOpRegion(family),
            { cond },
            {},
            Native.NativeRegionBranch(cond.value, native_fast_block_entry_region_id(func, self.then_dest), native_fast_block_entry_region_id(func, self.else_dest))
        ), nil
    end

    local function native_fast_switch_step_family(input, shape)
        local scalar = shape:native_fast_switch_step_scalar()
        return Native.NativeTemplateFamily(
            Native.NativeTemplateFamilyId("native.fast.code.switch_step." .. shape:native_fast_switch_step_token()),
            Native.NativeRoleCodeTerm,
            {
                Support.axis_target(input.plan.target),
                Support.axis_machine_scalar(scalar),
                Support.axis_fast_code_switch_step(shape),
            },
            Support.protocol_void_none()
        )
    end

    function Code.CodeTermSwitch:native_fast_terminal_region(input, func, block, term)
        local key = frame_binding_for_code_value(input, self.value)
        local scalar = key.scalar
        local key_atom = Native.NativeExprInput(0, scalar)
        local step_shape = Native.NativeSwitchStepAtoms(scalar, key_atom)
        local family = native_fast_switch_step_family(input, step_shape)
        local cases = {}
        for _, case in ipairs(self.cases or {}) do
            cases[#cases + 1] = Native.NativeRegionSwitchCase(case.literal, native_fast_block_entry_region_id(func, case.dest))
        end
        if #cases == 0 then
            local jump_family = Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())
            return native_fast_region(
                native_fast_term_region_id(func, term, "switch_empty"),
                native_fast_code_region_origin(func, block, nil, nil),
                Native.NativeFrameMicroOpRegion(jump_family),
                {},
                {},
                Native.NativeRegionJump(native_fast_block_entry_region_id(func, self.default_dest))
            ), nil
        end
        return native_fast_region(
            native_fast_term_region_id(func, term, "switch_baseline"),
            native_fast_code_region_origin(func, block, nil, nil),
            Native.NativeFrameMicroOpRegion(family),
            { key },
            {},
            Native.NativeRegionSwitch(key.value, step_shape, cases, native_fast_block_entry_region_id(func, self.default_dest))
        ), nil
    end

    function Code.CodeTermVariantSwitch:native_fast_terminal_region(input, func, block, term)
        local key = frame_binding_for_code_value(input, self.tag)
        local scalar = key.scalar
        local key_atom = Native.NativeExprInput(0, scalar)
        local step_shape = Native.NativeSwitchStepAtoms(scalar, key_atom)
        local family = native_fast_switch_step_family(input, step_shape)
        local cases = {}
        for _, case in ipairs(self.cases or {}) do
            cases[#cases + 1] = Native.NativeRegionSwitchCase(Core.LitInt(tostring(case.variant.tag_value)), native_fast_block_entry_region_id(func, case.dest))
        end
        if #cases == 0 then
            local jump_family = Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())
            return native_fast_region(
                native_fast_term_region_id(func, term, "variant_switch_empty"),
                native_fast_code_region_origin(func, block, nil, nil),
                Native.NativeFrameMicroOpRegion(jump_family),
                {},
                {},
                Native.NativeRegionJump(native_fast_block_entry_region_id(func, self.default_dest))
            ), nil
        end
        return native_fast_region(
            native_fast_term_region_id(func, term, "variant_switch_baseline"),
            native_fast_code_region_origin(func, block, nil, nil),
            Native.NativeFrameMicroOpRegion(family),
            { key },
            {},
            Native.NativeRegionSwitch(key.value, step_shape, cases, native_fast_block_entry_region_id(func, self.default_dest))
        ), nil
    end

    function Code.CodeTermTrap:native_fast_terminal_region(input, func, block, term)
        local family = Support.code_term_family("trap.trap", input.plan.target, Native.NativeCodeTermTrapAxis, Support.protocol_void_none())
        return native_fast_region(native_fast_term_region_id(func, term, "trap_baseline"), native_fast_code_region_origin(func, block, nil, nil), Native.NativeFrameMicroOpRegion(family), {}, {}, Native.NativeRegionTrap), nil
    end

    function Code.CodeTermUnreachable:native_fast_terminal_region(input, func, block, term)
        local family = Support.code_term_family("unreachable.trap", input.plan.target, Native.NativeCodeTermUnreachableAxis, Support.protocol_void_none())
        return native_fast_region(native_fast_term_region_id(func, term, "unreachable_baseline"), native_fast_code_region_origin(func, block, nil, nil), Native.NativeFrameMicroOpRegion(family), {}, {}, Native.NativeRegionTrap), nil
    end

    function Code.CodeTerm:native_fast_terminal_region(input, func, block)
        return self.op:native_fast_terminal_region(input, func, block, self)
    end

    function Native.NativeRegionTransfer:native_fast_region_is_exit()
        return false
    end

    function Native.NativeRegionReturn:native_fast_region_is_exit()
        return true
    end

    function Native.NativeRegionTrap:native_fast_region_is_exit()
        return true
    end

    function Code.CodeBlock:append_native_fast_regions(input, func, regions)
        local terminal_region, first_terminal_inst = self.term:native_fast_terminal_region(input, func, self)
        local prefix_end = first_terminal_inst and (first_terminal_inst - 1) or #(self.insts or {})
        local first_body_region_id = prefix_end >= 1 and native_fast_inst_region_id(func, self.insts[1]) or terminal_region.id
        regions[#regions + 1] = native_fast_region(
            native_fast_block_entry_region_id(func, self.id),
            Native.NativeCodeBlockRegion(func.id, self.id),
            Native.NativeFrameMicroOpRegion(Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())),
            {},
            {},
            Native.NativeRegionFallthrough(first_body_region_id)
        )
        for i = 1, prefix_end do
            local inst = self.insts[i]
            local next_id = (i < prefix_end) and native_fast_inst_region_id(func, self.insts[i + 1]) or terminal_region.id
            regions[#regions + 1] = inst:native_frame_micro_op_region(input, func, self, Native.NativeRegionFallthrough(next_id))
        end
        regions[#regions + 1] = terminal_region
    end

    local function native_fast_exits_from_regions(regions)
        local exits = {}
        for _, region in ipairs(regions or {}) do
            if region.transfer:native_fast_region_is_exit() then exits[#exits + 1] = region.id end
        end
        return exits
    end

    local function initialize_native_fast_code_build(func, plan, lowering, signature)
        if lowering == nil and signature == nil then internal_error("native CodeFunc fast-region projection requires an ASDL CodeSig, not only CodeFunc.sig id") end
        local lowering_input = lowering or native_code_lowering_for_single_function(func, signature, plan)
        local state = Native.NativeCodeGraphBuilderState(
            Native.NativeValueLocationPlan({}, lowering_input.module.addresses),
            Native.NativeFrameLayoutPlan({}, {}, {}, {}, 0),
            Native.NativeControlPlan({}, {}, {}, {}),
            Native.NativeEdgeCopyPlan({}),
            {}
        )
        local build = Native.NativeCodeGraphBuildInput(plan, lowering_input, state)
        local frame_alignment = target_frame_alignment(plan.target)
        allocate_abi_frame_slots(func, lowering_input.active_func.abi, state, plan.target, lowering_input.module.type_layouts, frame_alignment)
        allocate_result_frame_slot(func, lowering_input.active_func.abi, state, plan.target)
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do
                allocate_ordered_storage_slot(state, param.value, param.ty:native_storage_layout(plan.target, lowering_input.module.type_layouts), "block_param", frame_alignment)
            end
        end
        for _, local_storage_entry in ipairs(lowering_input.active_func.local_storage or {}) do
            if local_storage_entry.residence ~= Code.CodeResidenceStatic then
                local slot = allocate_local_storage_slot(state, local_storage_entry.local_id, local_storage_entry.storage, frame_alignment)
                append_local_address_entry(state, plan.target, local_storage_entry.local_id, local_storage_entry.ty, Native.NativeCodeAddressFrameSlot(slot.id))
            end
        end
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do inst:preallocate_native_storage(build, frame_alignment) end
        end
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do inst:preallocate_native_fast_storage(build, frame_alignment) end
        end
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do inst:append_native_address_plan(build) end
        end
        return build
    end

    function Code.CodeFunc:plan_native_fast_regions(plan, lowering, signature)
        local build = initialize_native_fast_code_build(self, plan, lowering, signature)
        local entry_block
        for _, candidate in ipairs(self.blocks or {}) do if candidate.id == self.entry then entry_block = candidate end end
        if entry_block == nil then internal_error("native CodeFunc fast-region entry block is absent: " .. self.entry.text) end
        local regions = {}
        for _, block in ipairs(self.blocks or {}) do block:append_native_fast_regions(build, self, regions) end
        return Native.NativeFastRegionPlan(
            plan.target,
            Support.native_call_code_sig(build.lowering.active_func.abi),
            regions,
            native_fast_block_entry_region_id(self, self.entry),
            native_fast_exits_from_regions(regions),
            frame_layout_from_state(plan.target, build.state)
        )
    end

    local function initialize_native_fast_public_code_build(func, plan, lowering, signature)
        if lowering == nil and signature == nil then internal_error("native CodeFunc fast public projection requires an ASDL CodeSig, not only CodeFunc.sig id") end
        local lowering_input = lowering or native_code_lowering_for_single_function(func, signature, plan)
        local state = Native.NativeCodeGraphBuilderState(
            Native.NativeValueLocationPlan({}, lowering_input.module.addresses),
            Native.NativeFrameLayoutPlan({}, {}, {}, {}, 0),
            Native.NativeControlPlan({}, {}, {}, {}),
            Native.NativeEdgeCopyPlan({}),
            {}
        )
        return Native.NativeCodeGraphBuildInput(plan, lowering_input, state)
    end

    local function plan_native_fast_public_code_expr_graph(func, plan, lowering, signature)
        local build = initialize_native_fast_public_code_build(func, plan, lowering, signature)
        local projection = build.lowering.active_func.abi
        local abi_shape = native_fast_public_abi_shape_for_func(func, projection, plan.target)
        if abi_shape == nil then return nil end
        if #(func.blocks or {}) ~= 1 then return nil end
        local block = func.blocks[1]
        if block.id ~= func.entry or #(block.params or {}) ~= 0 then return nil end
        if #(func.locals or {}) ~= 0 then return nil end
        local region = block.term:native_fast_public_terminal_region(build, func, block, abi_shape)
        if region == nil then return nil end
        local family = region.body:native_fast_template_family(Native.NativeFastRegionPlan(
            plan.target,
            Support.native_call_code_sig(projection),
            { region },
            region.id,
            { region.id },
            frame_layout_from_state(plan.target, build.state)
        ))
        if not loaded_bank_has_template_family(plan.bank, family) then return nil end
        return Native.NativeFastRegionPlan(
            plan.target,
            Support.native_call_code_sig(projection),
            { region },
            region.id,
            { region.id },
            frame_layout_from_state(plan.target, build.state)
        ):lower_native_template_graph(build.lowering.module.addresses)
    end

    function Code.CodeFunc:plan_native_copy(plan, lowering, signature)
        if lowering == nil and signature == nil then internal_error("native CodeFunc compilation requires an ASDL CodeSig, not only CodeFunc.sig id") end
        local fast_public_graph = plan_native_fast_public_code_expr_graph(self, plan, lowering, signature)
        if fast_public_graph ~= nil then return fast_public_graph end
        local lowering_input = lowering or native_code_lowering_for_single_function(self, signature, plan)
        local state = Native.NativeCodeGraphBuilderState(
            Native.NativeValueLocationPlan({}, lowering_input.module.addresses),
            Native.NativeFrameLayoutPlan({}, {}, {}, {}, 0),
            Native.NativeControlPlan({}, {}, {}, {}),
            Native.NativeEdgeCopyPlan({}),
            {}
        )
        local build = Native.NativeCodeGraphBuildInput(plan, lowering_input, state)
        local frame_alignment = target_frame_alignment(plan.target)
        local entry_block
        for _, candidate in ipairs(self.blocks or {}) do if candidate.id == self.entry then entry_block = candidate end end
        if entry_block == nil then internal_error("native CodeFunc entry block is absent: " .. self.entry.text) end
        allocate_abi_frame_slots(self, lowering_input.active_func.abi, state, plan.target, lowering_input.module.type_layouts, frame_alignment)
        allocate_result_frame_slot(self, lowering_input.active_func.abi, state, plan.target)
        for _, block in ipairs(self.blocks or {}) do
            for _, param in ipairs(block.params or {}) do
                allocate_ordered_storage_slot(state, param.value, param.ty:native_storage_layout(plan.target, lowering_input.module.type_layouts), "block_param", frame_alignment)
            end
        end
        for _, local_storage_entry in ipairs(lowering_input.active_func.local_storage or {}) do
            if local_storage_entry.residence ~= Code.CodeResidenceStatic then
                local slot = allocate_local_storage_slot(state, local_storage_entry.local_id, local_storage_entry.storage, frame_alignment)
                append_local_address_entry(state, plan.target, local_storage_entry.local_id, local_storage_entry.ty, Native.NativeCodeAddressFrameSlot(slot.id))
            end
        end
        for _, block in ipairs(self.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do inst:preallocate_native_storage(build, frame_alignment) end
        end
        for _, block in ipairs(self.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do inst:append_native_address_plan(build) end
        end
        for _, block in ipairs(self.blocks or {}) do block:select_native_template_graph(build) end
        local projection = lowering_input.active_func.abi
        local family = native_public_abi_adapter_family(plan.target, projection)
        local entry_node_id = Native.NativeTemplateNodeId("native.code.node.entry." .. self.id.text)
        local entry_node = Native.NativeTemplateNode(
            entry_node_id,
            instance_id_for(entry_node_id),
            family,
            {},
            {},
            materialize_bindings(entry_node_id, instance_id_for(entry_node_id), entry_binding_specs_for_projection(self, projection, state))
        )
        enforce_frame_stack_limit(native_public_abi_adapter_stack_limit(projection), frame_layout_from_state(plan.target, state))
        return graph_from_state(plan, state, Support.native_call_code_sig(projection), entry_node)
    end

    function Code.CodeBlock:select_native_template_graph(input)
        local before_node = input.state.control_plan.nodes[#input.state.control_plan.nodes]
        local before_count = #input.state.control_plan.nodes
        local entry_node = append_block_entry_node(input, self)
        if before_count > 0 then remove_auto_continuation_edge(input.state, before_node, entry_node) end
        for _, inst in ipairs(self.insts or {}) do inst:append_native_inst_template(input) end
        self.term:append_native_term_template(input)
        local exit_node = input.state.control_plan.nodes[#input.state.control_plan.nodes]
        input.state.control_plan.blocks[#input.state.control_plan.blocks + 1] = Native.NativeControlBlockEntry(self.id, entry_node.id, { exit_node.id })
        return exit_node
    end

    function Code.CodeInst:append_native_inst_template(input)
        return self.op:append_native_inst_template(input)
    end

    function Code.CodeInstConst:append_native_inst_template(input)
        return self.const:append_native_const_template(input, self.dst)
    end

    local function append_native_coordinate_const(input, dst, ty, coordinate)
        local scalar = ty:native_machine_scalar(input.plan.target)
        local axis = Native.NativeCodeConstLiteralAxis(ty)
        local family = Support.code_const_frame_family("literal." .. scalar_token(scalar), input.plan.target, scalar, axis)
        local hole_suffix = (coordinate.value and scalar.bits and scalar.bits > 32) and "imm64" or "imm32"
        local output = allocate_value_slot(input.state, dst, scalar, target_frame_alignment(input.plan.target))
        local token = scalar_token(scalar)
        local bindings = {
            frame_offset_binding("native.hole.code.const.literal." .. token .. ".dst", output),
            hole("native.hole.code.const.literal." .. token .. "." .. hole_suffix, coordinate),
        }
        local node = append_family_node(input, "const", family, {}, { output }, bindings)
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativePatchCoordinateValueEdge(output.value, scalar_value_representation(scalar), coordinate)
        return node
    end

    function Code.CodeConstLiteral:append_native_const_template(input, dst)
        return append_native_coordinate_const(input, dst, self.ty, self.literal:native_patch_coordinate_for_scalar(self.ty:native_machine_scalar(input.plan.target)))
    end

    function Native.NativeMachineScalarRep:native_null_patch_coordinate()
        internal_error("native null constants require an integer-like or pointer scalar")
    end

    function Native.NativeScalarBool8:native_null_patch_coordinate()
        return Native.NativePatchImmediateI32(0)
    end

    function Native.NativeScalarInt:native_null_patch_coordinate()
        if self.bits > 32 then return Native.NativePatchImmediateI64(0) end
        return Native.NativePatchImmediateI32(0)
    end

    function Native.NativeScalarIndex:native_null_patch_coordinate()
        if self.bits > 32 then return Native.NativePatchImmediateI64(0) end
        return Native.NativePatchImmediateI32(0)
    end

    function Native.NativeScalarPointer:native_null_patch_coordinate()
        if self.bits > 32 then return Native.NativePatchImmediateI64(0) end
        return Native.NativePatchImmediateI32(0)
    end

    function Code.CodeConstNull:append_native_const_template(input, dst)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        return append_native_coordinate_const(input, dst, self.ty, scalar:native_null_patch_coordinate())
    end

    function Code.CodeInstAlias:append_native_inst_template(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local source = placement_for_value(input.state, self.src)
        local output = allocate_value_slot(input.state, self.dst, scalar, target_frame_alignment(input.plan.target))
        local axis = Native.NativeCodeInstAliasAxis(self.ty)
        local family = Support.code_inst_frame_family("alias." .. scalar_token(scalar), input.plan.target, scalar, axis)
        local token = scalar_token(scalar)
        local node = append_family_node(input, "alias", family, { source }, { output }, {
            frame_offset_binding("native.hole.code.inst.alias." .. token .. ".src", source),
            frame_offset_binding("native.hole.code.inst.alias." .. token .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar_value_representation(scalar), output.location.slot)
        return node
    end

    function Code.CodeInstUnary:append_native_inst_template(input)
        local source_scalar = self.ty:native_machine_scalar(input.plan.target)
        local result_scalar = self.op:native_unary_result_scalar(self.ty, input.plan.target)
        local source = placement_for_value(input.state, self.value)
        local output = allocate_value_slot(input.state, self.dst, result_scalar, target_frame_alignment(input.plan.target))
        local name = self.op:native_unary_family_name()
        local axis = Native.NativeCodeInstUnaryAxis(self.op, self.ty)
        local family = Support.code_inst_frame_family("unary." .. scalar_token(source_scalar) .. "." .. name, input.plan.target, source_scalar, axis)
        local token = scalar_token(source_scalar)
        local node = append_family_node(input, "unary", family, { source }, { output }, {
            frame_offset_binding("native.hole.code.inst.unary." .. token .. "." .. name .. ".src", source),
            frame_offset_binding("native.hole.code.inst.unary." .. token .. "." .. name .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar_value_representation(result_scalar), output.location.slot)
        return node
    end

    function Code.CodeInstBinary:append_native_inst_template(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local lhs = placement_for_value(input.state, self.lhs)
        local rhs = placement_for_value(input.state, self.rhs)
        local output = allocate_value_slot(input.state, self.dst, scalar, target_frame_alignment(input.plan.target))
        local name = self.op:native_binary_family_name()
        local axis = Native.NativeCodeInstBinaryAxis(self.op, self.ty, self.semantics)
        local family = Support.code_inst_frame_family("binary." .. scalar_token(scalar) .. "." .. name, input.plan.target, scalar, axis)
        local token = scalar_token(scalar)
        local node = append_family_node(input, "binary", family, { lhs, rhs }, { output }, {
            frame_offset_binding("native.hole.code.inst.binary." .. token .. "." .. name .. ".lhs", lhs),
            frame_offset_binding("native.hole.code.inst.binary." .. token .. "." .. name .. ".rhs", rhs),
            frame_offset_binding("native.hole.code.inst.binary." .. token .. "." .. name .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar_value_representation(scalar), output.location.slot)
        return node
    end

    function Code.CodeInstFloatBinary:append_native_inst_template(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local lhs = placement_for_value(input.state, self.lhs)
        local rhs = placement_for_value(input.state, self.rhs)
        local output = allocate_value_slot(input.state, self.dst, scalar, target_frame_alignment(input.plan.target))
        local name = self.op:native_binary_family_name()
        local axis = Native.NativeCodeInstFloatBinaryAxis(self.op, self.ty, self.mode)
        local family = Support.code_inst_frame_family("float_binary." .. scalar_token(scalar) .. "." .. name, input.plan.target, scalar, axis)
        local token = scalar_token(scalar)
        local node = append_family_node(input, "float_binary", family, { lhs, rhs }, { output }, {
            frame_offset_binding("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".lhs", lhs),
            frame_offset_binding("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".rhs", rhs),
            frame_offset_binding("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar_value_representation(scalar), output.location.slot)
        return node
    end

    function Code.CodeInstCompare:append_native_inst_template(input)
        local operand_scalar = self.operand_ty:native_machine_scalar(input.plan.target)
        local result_scalar = Support.scalar_bool8()
        local lhs = placement_for_value(input.state, self.lhs)
        local rhs = placement_for_value(input.state, self.rhs)
        local output = allocate_value_slot(input.state, self.dst, result_scalar, target_frame_alignment(input.plan.target))
        local name = self.op:native_compare_family_name()
        local axis = Native.NativeCodeInstCompareAxis(self.op, self.operand_ty)
        local family = Support.code_inst_frame_family("compare." .. scalar_token(operand_scalar) .. "." .. name, input.plan.target, operand_scalar, axis)
        local token = scalar_token(operand_scalar)
        local node = append_family_node(input, "compare", family, { lhs, rhs }, { output }, {
            frame_offset_binding("native.hole.code.inst.compare." .. token .. "." .. name .. ".lhs", lhs),
            frame_offset_binding("native.hole.code.inst.compare." .. token .. "." .. name .. ".rhs", rhs),
            frame_offset_binding("native.hole.code.inst.compare." .. token .. "." .. name .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar_value_representation(result_scalar), output.location.slot)
        return node
    end

    function Core.MachineCastIdentity:native_cast_family_name() return "identity" end
    function Core.MachineCastBitcast:native_cast_family_name() return "bitcast" end
    function Core.MachineCastIreduce:native_cast_family_name() return "ireduce" end
    function Core.MachineCastSextend:native_cast_family_name() return "sext" end
    function Core.MachineCastUextend:native_cast_family_name() return "uext" end
    function Core.MachineCastFpromote:native_cast_family_name() return "fpromote" end
    function Core.MachineCastFdemote:native_cast_family_name() return "fdemote" end
    function Core.MachineCastSToF:native_cast_family_name() return "stof" end
    function Core.MachineCastUToF:native_cast_family_name() return "utof" end
    function Core.MachineCastFToS:native_cast_family_name() return "ftos" end
    function Core.MachineCastFToU:native_cast_family_name() return "ftou" end

    function Core.AtomicSeqCst:native_atomic_order_token() return "seq_cst" end
    function Core.AtomicRmwAdd:native_atomic_rmw_token() return "add" end
    function Core.AtomicRmwSub:native_atomic_rmw_token() return "sub" end
    function Core.AtomicRmwAnd:native_atomic_rmw_token() return "and" end
    function Core.AtomicRmwOr:native_atomic_rmw_token() return "or" end
    function Core.AtomicRmwXor:native_atomic_rmw_token() return "xor" end
    function Core.AtomicRmwXchg:native_atomic_rmw_token() return "xchg" end

    function Code.CodeInstCast:produced_native_scalar(value, target)
        if self.dst == value then return self.to:native_machine_scalar(target) end
    end

    function Code.CodeInstSelect:produced_native_scalar(value, target)
        if self.dst == value then return self.ty:native_machine_scalar(target) end
    end

    function Code.CodeInstAddrOf:produced_native_scalar(value, target)
        if self.dst == value then return self.ptr_ty:native_machine_scalar(target) end
    end

    function Code.CodeInstGlobalRef:produced_native_scalar(value, target)
        if self.dst == value then return self.ptr_ty:native_machine_scalar(target) end
    end

    function Code.CodeInstPtrOffset:produced_native_scalar(value, target)
        if self.dst == value then return self.ptr_ty:native_machine_scalar(target) end
    end

    function Code.CodeInstLoad:produced_native_scalar(value, target)
        if self.dst == value then return self.access.ty:native_machine_scalar(target) end
    end

    function Code.CodeInstAtomicLoad:produced_native_scalar(value, target)
        if self.dst == value then return self.access.ty:native_machine_scalar(target) end
    end

    function Code.CodeInstAtomicRmw:produced_native_scalar(value, target)
        if self.dst == value then return self.access.ty:native_machine_scalar(target) end
    end

    function Code.CodeInstAtomicCas:produced_native_scalar(value, _target)
        if self.dst == value then return Support.scalar_bool8() end
    end

    function Code.CodeInstViewData:produced_native_scalar(value, target)
        if self.dst == value then return Support.scalar_pointer(target.pointer_bits) end
    end

    function Code.CodeInstViewLen:produced_native_scalar(value, target)
        if self.dst == value then return Support.scalar_index(target.pointer_bits) end
    end

    function Code.CodeInstViewStride:produced_native_scalar(value, target)
        if self.dst == value then return Support.scalar_index(target.pointer_bits) end
    end

    function Code.CodeInstSliceData:produced_native_scalar(value, target)
        if self.dst == value then return Support.scalar_pointer(target.pointer_bits) end
    end

    function Code.CodeInstSliceLen:produced_native_scalar(value, target)
        if self.dst == value then return Support.scalar_index(target.pointer_bits) end
    end

    function Code.CodeInstByteSpanData:produced_native_scalar(value, target)
        if self.dst == value then return Support.scalar_pointer(target.pointer_bits) end
    end

    function Code.CodeInstByteSpanLen:produced_native_scalar(value, target)
        if self.dst == value then return Support.scalar_index(target.pointer_bits) end
    end

    function Code.CodeInstVariantTag:produced_native_scalar(value, target)
        if self.dst == value then return self.tag_ty:native_machine_scalar(target) end
    end

    function Code.CodeInstVariantPayload:produced_native_scalar(value, target)
        if self.dst == value and self.variant.payload_ty ~= nil then return self.variant.payload_ty:native_machine_scalar(target) end
    end

    local function scalar_source_family_location_suffix(_placement)
        return "slot"
    end

    local function scalar_dest_family_location_suffix(_placement)
        return "slot"
    end

    local function append_frame_value_edge(input, output, node, scalar)
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar_value_representation(scalar), output.location.slot)
        return node
    end

    local function append_storage_value_edge(input, output, node)
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, output.representation, output.location.slot)
        return node
    end

    local function frame_slot_offset_by_id(state, slot_id)
        for _, slot in ipairs(state.frame_layout_plan.slots or {}) do
            if slot.id == slot_id then return slot.offset end
        end
        internal_error("native frame slot address plan references unknown slot " .. tostring(slot_id and slot_id.text))
    end

    local function place_projection(input, place)
        for _, entry in ipairs(input.state.value_locations.addresses.places or {}) do
            if entry.place == place then return entry.projection end
        end
        return place:append_native_place_address_plan(input)
    end

    function Native.NativeCodeAddressCapability:native_static_frame_offset(_input)
        return nil
    end

    function Native.NativeCodeAddressFrameSlot:native_static_frame_offset(input)
        return frame_slot_offset_by_id(input.state, self.slot)
    end

    function Native.NativeCodeAddressFrameSlotOffset:native_static_frame_offset(input)
        return frame_slot_offset_by_id(input.state, self.slot) + self.offset
    end

    function Native.NativeCodeAddressValueOffset:native_static_frame_offset(input)
        local placement = placement_for_value(input.state, self.value)
        if not asdl.isa(placement.location, Native.NativeValueFrameSlotLocation) then return nil end
        return placement.location.slot.offset + self.offset
    end

    function Native.NativeCodeAddressPlaceOffset:native_static_frame_offset(input)
        local base = place_projection(input, self.base).capability:native_static_frame_offset(input)
        if base == nil then return nil end
        return base + self.offset
    end

    function Native.NativeCodeAddressPlaceIndexOffset:native_static_frame_offset(_input)
        return nil
    end

    local function append_addr_of_frame_to_slot(input, role, dst, ptr_scalar, frame_offset)
        local output = ensure_value_storage_slot(input.state, dst, scalar_storage_layout_for_frame(ptr_scalar), target_frame_alignment(input.plan.target))
        local family_name = "addr_of.frame.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, ptr_scalar, Native.NativeCodeInstAddressMaterializeAxis(Native.NativeCodeAddressMaterializeFrameSlot, ptr_scalar))
        local id_base = "native.hole.code.inst.addr_of.frame.to.slot"
        local node = append_family_node(input, role, family, {}, { output }, {
            frame_offset_value_binding(id_base .. ".frame", frame_offset),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, ptr_scalar), output
    end

    local function append_module_address_to_slot(input, role, dst, ptr_scalar, coordinate)
        local output = ensure_value_storage_slot(input.state, dst, scalar_storage_layout_for_frame(ptr_scalar), target_frame_alignment(input.plan.target))
        local family_name = "global_ref.ptr64.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, ptr_scalar, Native.NativeCodeInstAddressMaterializeAxis(Native.NativeCodeAddressMaterializeModuleSymbol, ptr_scalar))
        local id_base = "native.hole.code.inst.global_ref.ptr64.to.slot"
        local node = append_family_node(input, role, family, {}, { output }, {
            hole(id_base .. ".target", coordinate),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativePatchCoordinateValueEdge(output.value, output.representation, coordinate)
        return append_frame_value_edge(input, output, node, ptr_scalar), output
    end

    local function append_ptr_offset_to_slot(input, role, dst, ptr_scalar, base, index, elem_size, const_offset)
        local output = ensure_value_storage_slot(input.state, dst, scalar_storage_layout_for_frame(ptr_scalar), target_frame_alignment(input.plan.target))
        local family_name = "ptr_offset.ptr64.slot.index.slot.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, ptr_scalar, Native.NativeCodeInstPointerOffsetAxis(ptr_scalar, Support.scalar_index(input.plan.target.pointer_bits)))
        local id_base = "native.hole.code.inst.ptr_offset.slot.index.slot.to.slot"
        local node = append_family_node(input, role, family, { base, index }, { output }, {
            frame_offset_binding(id_base .. ".base.src", base),
            frame_offset_binding(id_base .. ".index.src", index),
            hole(id_base .. ".elem_size.imm32", Native.NativePatchImmediateI32(elem_size)),
            hole(id_base .. ".const_offset.imm32", Native.NativePatchImmediateI32(const_offset)),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, ptr_scalar), output
    end

    local function append_scalar_field_store(input, role, storage_kind, base_offset, field_offset, scalar, value)
        local token = scalar_token(scalar)
        local kind = storage_kind == Native.NativeCodeArrayElementStorage and "array" or "aggregate"
        local family_name = kind .. ".field_store." .. token .. ".value.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstLayoutFieldStoreAxis(storage_kind, scalar))
        local id_base = "native.hole.code.inst." .. family_name
        return append_family_node(input, role, family, { value }, {}, {
            frame_offset_value_binding(id_base .. ".base", base_offset),
            hole(id_base .. ".offset", Native.NativePatchImmediateI32(field_offset)),
            frame_offset_binding(id_base .. ".value.src", value),
        })
    end

    local function append_scalar_field_store_immediate(input, role, storage_kind, base_offset, field_offset, scalar, coordinate)
        local token = scalar_token(scalar)
        local kind = storage_kind == Native.NativeCodeArrayElementStorage and "array" or "aggregate"
        local family_name = kind .. ".field_store." .. token .. ".value.const"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstLayoutFieldStoreAxis(storage_kind, scalar))
        local id_base = "native.hole.code.inst." .. family_name
        return append_family_node(input, role, family, {}, {}, {
            frame_offset_value_binding(id_base .. ".base", base_offset),
            hole(id_base .. ".offset", Native.NativePatchImmediateI32(field_offset)),
            hole(id_base .. ".value.imm32", coordinate),
        })
    end

    local function append_scalar_field_load(input, role, storage_kind, dst, base_offset, field_offset, scalar)
        local output = ensure_value_storage_slot(input.state, dst, scalar_storage_layout_for_frame(scalar), target_frame_alignment(input.plan.target))
        local token = scalar_token(scalar)
        local kind = storage_kind == Native.NativeCodeArrayElementStorage and "array" or "aggregate"
        local family_name = kind .. ".field_load." .. token .. ".to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstLayoutFieldLoadAxis(storage_kind, scalar))
        local id_base = "native.hole.code.inst." .. family_name
        local node = append_family_node(input, role, family, {}, { output }, {
            frame_offset_value_binding(id_base .. ".base", base_offset),
            hole(id_base .. ".offset", Native.NativePatchImmediateI32(field_offset)),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, scalar), output
    end

    local function append_scalar_load_from_ptr(input, role, dst, scalar, ptr)
        local output = ensure_value_storage_slot(input.state, dst, scalar_storage_layout_for_frame(scalar), target_frame_alignment(input.plan.target))
        local family_name = "load." .. scalar_token(scalar) .. ".ptr.slot.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstLoadAxis(Code.CodeMemoryAccess(Code.CodeMemoryRead, scalar:native_code_type(), scalar:native_frame_alignment(), Code.CodeMayTrap, false, nil)))
        local id_base = "native.hole.code.inst.load." .. scalar_token(scalar) .. ".ptr.slot.to.slot"
        local node = append_family_node(input, role, family, { ptr }, { output }, {
            frame_offset_binding(id_base .. ".ptr.src", ptr),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, scalar)
    end

    local function append_scalar_store_to_ptr(input, role, scalar, ptr, value)
        local family_name = "store." .. scalar_token(scalar) .. ".ptr.slot.value.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstStoreAxis(Code.CodeMemoryAccess(Code.CodeMemoryWrite, scalar:native_code_type(), scalar:native_frame_alignment(), Code.CodeMayTrap, false, nil)))
        local id_base = "native.hole.code.inst.store." .. scalar_token(scalar) .. ".ptr.slot.value.slot"
        return append_family_node(input, role, family, { ptr, value }, {}, {
            frame_offset_binding(id_base .. ".ptr.src", ptr),
            frame_offset_binding(id_base .. ".value.src", value),
        })
    end

    function Native.NativeCodeAddressCapability:append_native_address_materialization(_input, _role, _dst, _ptr_scalar)
        internal_error("native address capability cannot be materialized by current Code lowering")
    end

    function Native.NativeCodeAddressPatchable:append_native_address_materialization(input, role, dst, ptr_scalar)
        return append_module_address_to_slot(input, role, dst, ptr_scalar, self.coordinate)
    end

    function Native.NativeCodeAddressFrameSlot:append_native_address_materialization(input, role, dst, ptr_scalar)
        return append_addr_of_frame_to_slot(input, role, dst, ptr_scalar, self:native_static_frame_offset(input))
    end

    function Native.NativeCodeAddressFrameSlotOffset:append_native_address_materialization(input, role, dst, ptr_scalar)
        return append_addr_of_frame_to_slot(input, role, dst, ptr_scalar, self:native_static_frame_offset(input))
    end

    function Native.NativeCodeAddressValueOffset:append_native_address_materialization(input, role, dst, ptr_scalar)
        local offset = self:native_static_frame_offset(input)
        if offset == nil then internal_error("native value-offset address materialization requires a frame-slot value placement") end
        return append_addr_of_frame_to_slot(input, role, dst, ptr_scalar, offset)
    end

    function Native.NativeCodeAddressPlaceOffset:append_native_address_materialization(input, role, dst, ptr_scalar)
        local offset = self:native_static_frame_offset(input)
        if offset == nil then internal_error("native place-offset address materialization requires a frame-slot base place") end
        return append_addr_of_frame_to_slot(input, role, dst, ptr_scalar, offset)
    end

    function Native.NativeCodeAddressPlaceIndexOffset:append_native_address_materialization(input, role, dst, ptr_scalar)
        local base_projection = place_projection(input, self.base)
        local base_offset = base_projection.capability:native_static_frame_offset(input)
        if base_offset == nil then internal_error("native indexed place address materialization requires a frame-slot base place") end
        local base_addr_value = Code.CodeValueId(dst.text .. ".base_addr")
        local _, base_addr = append_addr_of_frame_to_slot(input, role .. ".base", base_addr_value, ptr_scalar, base_offset + self.const_offset)
        return append_ptr_offset_to_slot(input, role, dst, ptr_scalar, base_addr, placement_for_value(input.state, self.index), self.elem_size, 0)
    end

    function Code.CodeInstCast:append_native_inst_template(input)
        local from_scalar = self.from:native_machine_scalar(input.plan.target)
        local to_scalar = self.to:native_machine_scalar(input.plan.target)
        local source = placement_for_value(input.state, self.value)
        local output = allocate_value_slot(input.state, self.dst, to_scalar, target_frame_alignment(input.plan.target))
        local op_name = self.op:native_cast_family_name()
        local src_token = scalar_source_family_location_suffix(source)
        local dst_token = scalar_dest_family_location_suffix(output)
        local family_name = "cast." .. op_name .. "." .. scalar_token(from_scalar) .. ".to." .. scalar_token(to_scalar) .. "." .. src_token .. ".to." .. dst_token
        local family = Support.code_inst_frame_family(family_name, input.plan.target, to_scalar, Native.NativeCodeInstCastAxis(self.op, self.from, self.to))
        local id_base = "native.hole.code.inst.cast." .. op_name .. "." .. scalar_token(from_scalar) .. ".to." .. scalar_token(to_scalar) .. "." .. src_token .. ".to." .. dst_token
        local node = append_family_node(input, "cast", family, { source }, { output }, {
            frame_offset_binding(id_base .. ".src", source),
            frame_offset_binding(id_base .. ".dst", output),
        })
        return append_frame_value_edge(input, output, node, to_scalar)
    end

    function Code.CodeInstSelect:append_native_inst_template(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local cond = placement_for_value(input.state, self.cond)
        local then_value = placement_for_value(input.state, self.then_value)
        local else_value = placement_for_value(input.state, self.else_value)
        local output = allocate_value_slot(input.state, self.dst, scalar, target_frame_alignment(input.plan.target))
        local family_name = "select." .. scalar_token(scalar) .. ".cond.slot.true.slot.false.slot.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstSelectAxis(self.ty))
        local id_base = "native.hole.code.inst.select." .. scalar_token(scalar) .. ".cond.slot.true.slot.false.slot.to.slot"
        local node = append_family_node(input, "select", family, { cond, then_value, else_value }, { output }, {
            frame_offset_binding(id_base .. ".cond.src", cond),
            frame_offset_binding(id_base .. ".true.src", then_value),
            frame_offset_binding(id_base .. ".false.src", else_value),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, scalar)
    end

    function Code.CodeInstAddrOf:append_native_inst_template(input)
        local ptr_scalar = self.ptr_ty:native_machine_scalar(input.plan.target)
        local projection = place_projection(input, self.place)
        return projection.capability:append_native_address_materialization(input, "addr_of", self.dst, ptr_scalar)
    end

    function Code.CodeInstGlobalRef:append_native_inst_template(input)
        local ptr_scalar = self.ptr_ty:native_machine_scalar(input.plan.target)
        local coordinate = self.ref:native_address_patch_coordinate(input.plan.target)
        return append_module_address_to_slot(input, "global_ref", self.dst, ptr_scalar, coordinate)
    end

    function Code.CodeInstPtrOffset:append_native_inst_template(input)
        local ptr_scalar = self.ptr_ty:native_machine_scalar(input.plan.target)
        return append_ptr_offset_to_slot(input, "ptr_offset", self.dst, ptr_scalar, placement_for_value(input.state, self.base), placement_for_value(input.state, self.index), self.elem_size, self.const_offset)
    end

    function Code.CodeInstLoad:append_native_inst_template(input)
        local scalar = self.access.ty:native_machine_scalar(input.plan.target)
        if asdl.isa(self.place, Code.CodePlaceDeref) then
            return append_scalar_load_from_ptr(input, "load", self.dst, scalar, placement_for_value(input.state, self.place.addr))
        end
        local projection = place_projection(input, self.place)
        local base_offset = projection.capability:native_static_frame_offset(input)
        if base_offset ~= nil then return append_scalar_field_load(input, "load.place", Native.NativeCodeAggregateObjectStorage, self.dst, base_offset, 0, scalar) end
        local ptr_value = Code.CodeValueId(self.dst.text .. ".addr")
        local _, ptr = projection.capability:append_native_address_materialization(input, "load.place.addr", ptr_value, Support.scalar_pointer(input.plan.target.pointer_bits))
        return append_scalar_load_from_ptr(input, "load.place", self.dst, scalar, ptr)
    end

    function Code.CodeInstStore:append_native_inst_template(input)
        local scalar = self.access.ty:native_machine_scalar(input.plan.target)
        local value = placement_for_value(input.state, self.value)
        if asdl.isa(self.place, Code.CodePlaceDeref) then
            return append_scalar_store_to_ptr(input, "store", scalar, placement_for_value(input.state, self.place.addr), value)
        end
        local projection = place_projection(input, self.place)
        local base_offset = projection.capability:native_static_frame_offset(input)
        if base_offset ~= nil then return append_scalar_field_store(input, "store.place", Native.NativeCodeAggregateObjectStorage, base_offset, 0, scalar, value) end
        local ptr_value = Code.CodeValueId(self.value.text .. ".store_addr")
        local _, ptr = projection.capability:append_native_address_materialization(input, "store.place.addr", ptr_value, Support.scalar_pointer(input.plan.target.pointer_bits))
        return append_scalar_store_to_ptr(input, "store.place", scalar, ptr, value)
    end

    local function frame_slot_offset_for_placement(placement)
        if not asdl.isa(placement.location, Native.NativeValueFrameSlotLocation) then internal_error("native object lowering requires frame-slot placement") end
        return placement.location.slot.offset
    end

    local function field_offset_for_aggregate_ty(ty, field, layout_plan)
        local entry = find_named_layout_entry(layout_plan, ty)
        if entry ~= nil then
            for _, field_layout in ipairs(entry.fields or {}) do
                if field_layout.field_name == field.field_name then return field_layout.offset end
            end
        end
        internal_error("native aggregate lowering is missing field layout for `" .. tostring(field.field_name) .. "`")
    end

    local function append_descriptor_make(input, role, dst, kind, elem_ty, data_value, len_value, stride_value)
        local layout_ty = kind == "view" and Code.CodeTyView(elem_ty) or (kind == "slice" and Code.CodeTySlice(elem_ty) or Code.CodeTyByteSpan)
        local layout = layout_ty:native_storage_layout(input.plan.target, input.lowering.module.type_layouts)
        local output = ensure_value_storage_slot(input.state, dst, layout, target_frame_alignment(input.plan.target))
        local ptr_scalar = Support.scalar_pointer(input.plan.target.pointer_bits)
        local index_scalar = Support.scalar_index(input.plan.target.pointer_bits)
        local data = placement_for_value(input.state, data_value)
        local len = placement_for_value(input.state, len_value)
        local stride = stride_value and placement_for_value(input.state, stride_value) or nil
        local elem_token = elem_ty and scalar_token(elem_ty:native_machine_scalar(input.plan.target)) or "bytes"
        local id_tail = kind .. ".make." .. elem_token .. ".data.slot.len.slot" .. (stride and ".stride.slot" or "")
        local axis = kind == "view" and Native.NativeCodeInstViewMakeAxis(elem_ty) or (kind == "slice" and Native.NativeCodeInstSliceMakeAxis(elem_ty) or Native.NativeCodeInstByteSpanMakeAxis)
        local family = Support.code_inst_frame_family(id_tail, input.plan.target, ptr_scalar, axis)
        local id_base = "native.hole.code.inst." .. id_tail
        local bindings = {
            frame_offset_binding(id_base .. ".dst", output),
            frame_offset_binding(id_base .. ".data.src", data),
            frame_offset_binding(id_base .. ".len.src", len),
        }
        local inputs = { data, len }
        if stride ~= nil then
            bindings[#bindings + 1] = frame_offset_binding(id_base .. ".stride.src", stride)
            inputs[#inputs + 1] = stride
        end
        local node = append_family_node(input, role, family, inputs, { output }, bindings)
        return append_storage_value_edge(input, output, node)
    end

    function Code.CodeInstViewMake:append_native_inst_template(input)
        return append_descriptor_make(input, "view_make", self.dst, "view", self.elem_ty, self.data, self.len, self.stride)
    end

    function Code.CodeInstSliceMake:append_native_inst_template(input)
        return append_descriptor_make(input, "slice_make", self.dst, "slice", self.elem_ty, self.data, self.len, nil)
    end

    function Code.CodeInstByteSpanMake:append_native_inst_template(input)
        return append_descriptor_make(input, "bytespan_make", self.dst, "bytespan", nil, self.data, self.len, nil)
    end

    local function append_descriptor_extract(input, role, dst, source_value, kind, field_name, scalar, axis)
        local source = placement_for_value(input.state, source_value)
        local output = ensure_value_storage_slot(input.state, dst, scalar_storage_layout_for_frame(scalar), target_frame_alignment(input.plan.target))
        local id_tail = kind .. "." .. field_name .. ".to.slot"
        local family = Support.code_inst_frame_family(id_tail, input.plan.target, scalar, axis)
        local id_base = "native.hole.code.inst." .. id_tail
        local node = append_family_node(input, role, family, { source }, { output }, {
            frame_offset_binding(id_base .. ".src", source),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, scalar)
    end

    function Code.CodeInstViewData:append_native_inst_template(input)
        return append_descriptor_extract(input, "view_data", self.dst, self.view, "view", "data", Support.scalar_pointer(input.plan.target.pointer_bits), Native.NativeCodeInstViewDataAxis)
    end

    function Code.CodeInstViewLen:append_native_inst_template(input)
        return append_descriptor_extract(input, "view_len", self.dst, self.view, "view", "len", Support.scalar_index(input.plan.target.pointer_bits), Native.NativeCodeInstViewLenAxis)
    end

    function Code.CodeInstViewStride:append_native_inst_template(input)
        return append_descriptor_extract(input, "view_stride", self.dst, self.view, "view", "stride", Support.scalar_index(input.plan.target.pointer_bits), Native.NativeCodeInstViewStrideAxis)
    end

    function Code.CodeInstSliceData:append_native_inst_template(input)
        return append_descriptor_extract(input, "slice_data", self.dst, self.slice, "slice", "data", Support.scalar_pointer(input.plan.target.pointer_bits), Native.NativeCodeInstSliceDataAxis)
    end

    function Code.CodeInstSliceLen:append_native_inst_template(input)
        return append_descriptor_extract(input, "slice_len", self.dst, self.slice, "slice", "len", Support.scalar_index(input.plan.target.pointer_bits), Native.NativeCodeInstSliceLenAxis)
    end

    function Code.CodeInstByteSpanData:append_native_inst_template(input)
        return append_descriptor_extract(input, "bytespan_data", self.dst, self.span, "bytespan", "data", Support.scalar_pointer(input.plan.target.pointer_bits), Native.NativeCodeInstByteSpanDataAxis)
    end

    function Code.CodeInstByteSpanLen:append_native_inst_template(input)
        return append_descriptor_extract(input, "bytespan_len", self.dst, self.span, "bytespan", "len", Support.scalar_index(input.plan.target.pointer_bits), Native.NativeCodeInstByteSpanLenAxis)
    end

    function Code.CodeInstAggregate:append_native_inst_template(input)
        local layout = self.ty:native_storage_layout(input.plan.target, input.lowering.module.type_layouts)
        local output = ensure_value_storage_slot(input.state, self.dst, layout, target_frame_alignment(input.plan.target))
        local base_offset = frame_slot_offset_for_placement(output)
        local last_node
        for _, field in ipairs(self.fields or {}) do
            local value = placement_for_value(input.state, field.value)
            local scalar = value.representation:native_scalar_rep()
            last_node = append_scalar_field_store(input, "aggregate.field_store", Native.NativeCodeAggregateObjectStorage, base_offset, field_offset_for_aggregate_ty(self.ty, field.field, input.lowering.module.type_layouts), scalar, value)
        end
        if last_node ~= nil then append_storage_value_edge(input, output, last_node) end
        return last_node
    end

    function Code.CodeInstArray:append_native_inst_template(input)
        local layout = self.ty:native_storage_layout(input.plan.target, input.lowering.module.type_layouts)
        local output = ensure_value_storage_slot(input.state, self.dst, layout, target_frame_alignment(input.plan.target))
        local base_offset = frame_slot_offset_for_placement(output)
        local elem_layout = self.ty.elem:native_storage_layout(input.plan.target, input.lowering.module.type_layouts)
        local last_node
        for _, elem in ipairs(self.elems or {}) do
            local value = placement_for_value(input.state, elem.value)
            local scalar = value.representation:native_scalar_rep()
            last_node = append_scalar_field_store(input, "array.field_store", Native.NativeCodeArrayElementStorage, base_offset, elem.index * elem_layout.size, scalar, value)
        end
        if last_node ~= nil then append_storage_value_edge(input, output, last_node) end
        return last_node
    end

    function Code.CodeInstVariantCtor:append_native_inst_template(input)
        local entry, case_layout = find_variant_case_layout(input.lowering.module.type_layouts, self.variant)
        if entry == nil or case_layout == nil then internal_error("native variant constructor lowering requires typed variant layout entry and case layout") end
        local output = ensure_value_storage_slot(input.state, self.dst, entry.storage, target_frame_alignment(input.plan.target))
        if self.payload == nil then
            local tag_scalar = entry.tag_storage.representation:native_scalar_rep()
            local node = append_scalar_field_store_immediate(input, "variant_ctor.tag", Native.NativeCodeAggregateObjectStorage, frame_slot_offset_for_placement(output), entry.tag_offset, tag_scalar, Native.NativePatchImmediateI32(case_layout.tag_value))
            return append_storage_value_edge(input, output, node)
        end
        if case_layout.payload == nil then internal_error("native variant constructor payload does not match payload-less variant layout") end
        local payload = placement_for_value(input.state, self.payload)
        local payload_scalar = payload.representation:native_scalar_rep()
        local family_name = "variant.ctor." .. scalar_token(payload_scalar) .. ".value.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, payload_scalar, Native.NativeCodeInstVariantScalarCtorAxis(Support.scalar_i32(), payload_scalar))
        local id_base = "native.hole.code.inst." .. family_name
        local node = append_family_node(input, "variant_ctor", family, { payload }, { output }, {
            frame_offset_binding(id_base .. ".base", output),
            hole(id_base .. ".tag_offset", Native.NativePatchImmediateI32(entry.tag_offset)),
            hole(id_base .. ".tag_value", Native.NativePatchImmediateI32(case_layout.tag_value)),
            hole(id_base .. ".payload_offset", Native.NativePatchImmediateI32(case_layout.payload_offset)),
            frame_offset_binding(id_base .. ".payload.src", payload),
        })
        return append_storage_value_edge(input, output, node)
    end

    local function append_variant_scalar_load(input, role, dst, source, offset_name, offset_value, scalar, axis)
        local output = ensure_value_storage_slot(input.state, dst, scalar_storage_layout_for_frame(scalar), target_frame_alignment(input.plan.target))
        local family_name = "variant." .. offset_name .. "." .. scalar_token(scalar) .. ".to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, axis)
        local id_base = "native.hole.code.inst." .. family_name
        local hole_name = offset_name == "tag" and ".tag_offset" or ".payload_offset"
        local node = append_family_node(input, role, family, { source }, { output }, {
            frame_offset_binding(id_base .. ".base", source),
            hole(id_base .. hole_name, Native.NativePatchImmediateI32(offset_value)),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, scalar)
    end

    function Code.CodeInstVariantTag:append_native_inst_template(input)
        local value = placement_for_value(input.state, self.value)
        if not asdl.isa(value.representation, Native.NativeVariantStorageRepresentation) then internal_error("native variant tag lowering requires a variant storage representation") end
        local entry = find_variant_layout_entry_for_owner(input.lowering.module.type_layouts, value.representation.source_ty)
        if entry == nil then internal_error("native variant tag lowering requires a typed variant layout entry") end
        local tag_scalar = entry.tag_storage.representation:native_scalar_rep()
        return append_variant_scalar_load(input, "variant_tag", self.dst, value, "tag", entry.tag_offset, tag_scalar, Native.NativeCodeInstVariantScalarTagAxis(tag_scalar))
    end

    function Code.CodeInstVariantPayload:append_native_inst_template(input)
        local value = placement_for_value(input.state, self.value)
        local _entry, case_layout = find_variant_case_layout(input.lowering.module.type_layouts, self.variant)
        if case_layout == nil or case_layout.payload == nil then internal_error("native variant payload lowering requires typed variant case layout") end
        local scalar = case_layout.payload.representation:native_scalar_rep()
        return append_variant_scalar_load(input, "variant_payload", self.dst, value, "payload", case_layout.payload_offset, scalar, Native.NativeCodeInstVariantScalarPayloadAxis(scalar))
    end

    function Code.CodeInstAtomicLoad:append_native_inst_template(input)
        local scalar = self.access.ty:native_machine_scalar(input.plan.target)
        if not asdl.isa(self.place, Code.CodePlaceDeref) then internal_error("native CodeInstAtomicLoad lowering currently requires CodePlaceDeref") end
        local ptr = placement_for_value(input.state, self.place.addr)
        local output = allocate_value_slot(input.state, self.dst, scalar, target_frame_alignment(input.plan.target))
        local order = self.ordering:native_atomic_order_token()
        local family_name = "atomic_load." .. scalar_token(scalar) .. "." .. order .. ".ptr.slot.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstAtomicLoadAxis(self.access, self.ordering))
        local id_base = "native.hole.code.inst." .. family_name
        local node = append_family_node(input, "atomic_load", family, { ptr }, { output }, {
            frame_offset_binding(id_base .. ".ptr.src", ptr),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, scalar)
    end

    function Code.CodeInstAtomicStore:append_native_inst_template(input)
        local scalar = self.access.ty:native_machine_scalar(input.plan.target)
        if not asdl.isa(self.place, Code.CodePlaceDeref) then internal_error("native CodeInstAtomicStore lowering currently requires CodePlaceDeref") end
        local ptr = placement_for_value(input.state, self.place.addr)
        local value = placement_for_value(input.state, self.value)
        local order = self.ordering:native_atomic_order_token()
        local family_name = "atomic_store." .. scalar_token(scalar) .. "." .. order .. ".ptr.slot.value.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstAtomicStoreAxis(self.access, self.ordering))
        local id_base = "native.hole.code.inst." .. family_name
        return append_family_node(input, "atomic_store", family, { ptr, value }, {}, {
            frame_offset_binding(id_base .. ".ptr.src", ptr),
            frame_offset_binding(id_base .. ".value.src", value),
        })
    end

    function Code.CodeInstAtomicRmw:append_native_inst_template(input)
        local scalar = self.access.ty:native_machine_scalar(input.plan.target)
        if not asdl.isa(self.place, Code.CodePlaceDeref) then internal_error("native CodeInstAtomicRmw lowering currently requires CodePlaceDeref") end
        local ptr = placement_for_value(input.state, self.place.addr)
        local value = placement_for_value(input.state, self.value)
        local output = allocate_value_slot(input.state, self.dst, scalar, target_frame_alignment(input.plan.target))
        local order = self.ordering:native_atomic_order_token()
        local op = self.op:native_atomic_rmw_token()
        local family_name = "atomic_rmw." .. scalar_token(scalar) .. "." .. op .. "." .. order .. ".ptr.slot.value.slot.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, scalar, Native.NativeCodeInstAtomicRmwAxis(self.op, self.access, self.ordering))
        local id_base = "native.hole.code.inst." .. family_name
        local node = append_family_node(input, "atomic_rmw", family, { ptr, value }, { output }, {
            frame_offset_binding(id_base .. ".ptr.src", ptr),
            frame_offset_binding(id_base .. ".value.src", value),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, scalar)
    end

    function Code.CodeInstAtomicCas:append_native_inst_template(input)
        local scalar = self.access.ty:native_machine_scalar(input.plan.target)
        if not asdl.isa(self.place, Code.CodePlaceDeref) then internal_error("native CodeInstAtomicCas lowering currently requires CodePlaceDeref") end
        local ptr = placement_for_value(input.state, self.place.addr)
        local expected = placement_for_value(input.state, self.expected)
        local replacement = placement_for_value(input.state, self.replacement)
        local result_scalar = Support.scalar_bool8()
        local output = allocate_value_slot(input.state, self.dst, result_scalar, target_frame_alignment(input.plan.target))
        local order = self.ordering:native_atomic_order_token()
        local family_name = "atomic_cas." .. scalar_token(scalar) .. "." .. order .. ".ptr.slot.expected.slot.replacement.slot.to.slot"
        local family = Support.code_inst_frame_family(family_name, input.plan.target, result_scalar, Native.NativeCodeInstAtomicCasAxis(self.access, self.ordering))
        local id_base = "native.hole.code.inst." .. family_name
        local node = append_family_node(input, "atomic_cas", family, { ptr, expected, replacement }, { output }, {
            frame_offset_binding(id_base .. ".ptr.src", ptr),
            frame_offset_binding(id_base .. ".expected.src", expected),
            frame_offset_binding(id_base .. ".replacement.src", replacement),
            frame_offset_binding(id_base .. ".dst.dst", output),
        })
        return append_frame_value_edge(input, output, node, result_scalar)
    end

    function Code.CodeInstAtomicFence:append_native_inst_template(input)
        local order = self.ordering:native_atomic_order_token()
        local frame_scalar = Support.scalar_bool8()
        local family = Support.code_inst_frame_family("atomic_fence." .. order, input.plan.target, frame_scalar, Native.NativeCodeInstAtomicFenceAxis(self.ordering))
        return append_family_node(input, "atomic_fence", family, {}, {}, {})
    end

    local function signature_for_call(input, sig_id)
        for _, entry in ipairs(input.lowering.module.signatures or {}) do
            if entry.sig == sig_id then return entry.signature end
        end
        internal_error("native CodeInstCall references unknown CodeSig " .. tostring(sig_id and sig_id.text))
    end

    local function call_result_storage_layout(projection, target, layout_plan)
        if asdl.isa(projection.result.abi, Native.NativeAbiVoidResult) then return nil end
        if asdl.isa(projection.result.abi, Native.NativeAbiSRetResult) then return projection.result.abi.result_ty:native_storage_layout(target, layout_plan) end
        return abi_projection_storage_layout(projection.result.abi, target)
    end

    local function append_call_result_output(input, dst, projection)
        if dst == nil then return nil end
        local storage = call_result_storage_layout(projection, input.plan.target, input.lowering.module.type_layouts)
        if storage == nil then internal_error("native CodeInstCall has a destination for a void ABI projection") end
        return ensure_value_storage_slot(input.state, dst, storage, target_frame_alignment(input.plan.target))
    end

    local function append_call_arg_bindings(input, token, mode, projection, args, result_output, prefix_bindings)
        local bindings = prefix_bindings or {}
        local arg_index = 1
        for _, param in ipairs(projection.params or {}) do
            if asdl.isa(projection.result.abi, Native.NativeAbiSRetResult) and param == projection.result.abi.pointer_param then
                if result_output == nil then internal_error("native sret call requires a destination frame slot") end
                local ptr_value = Code.CodeValueId((result_output.value and result_output.value.text or "native.sret") .. ".sret_addr")
                local _, ptr_placement = append_addr_of_frame_to_slot(input, "call.sret_addr", ptr_value, Support.scalar_pointer(input.plan.target.pointer_bits), result_output.location.slot.offset)
                bindings[#bindings + 1] = frame_offset_binding("native.hole.code.inst.call." .. mode .. "." .. token .. ".arg" .. tostring(param.param_index), ptr_placement)
            else
                local arg_value = (args or {})[arg_index]
                if arg_value == nil then internal_error("native call missing argument " .. tostring(arg_index)) end
                bindings[#bindings + 1] = frame_offset_binding("native.hole.code.inst.call." .. mode .. "." .. token .. ".arg" .. tostring(param.param_index), placement_for_value(input.state, arg_value))
                arg_index = arg_index + 1
            end
        end
        if arg_index <= #(args or {}) then internal_error("native call argument list has more values than ABI params") end
        if result_output ~= nil and not asdl.isa(projection.result.abi, Native.NativeAbiSRetResult) then
            bindings[#bindings + 1] = frame_offset_binding("native.hole.code.inst.call." .. mode .. "." .. token .. ".result", result_output)
        end
        return bindings
    end

    function Code.CodeCallTarget:append_native_call_bindings(_input, _token, _projection, _args, _result_output)
        internal_error("CodeCallTarget leaf is missing native call binding lowering")
    end

    function Code.CodeCallDirect:append_native_call_bindings(input, token, projection, args, result_output)
        return append_call_arg_bindings(input, token, "direct", projection, args, result_output, {
            hole("native.hole.code.inst.call.direct." .. token .. ".target", Native.NativePatchCodeFuncAddress(self.func)),
        })
    end

    function Code.CodeCallExtern:append_native_call_bindings(input, token, projection, args, result_output)
        return append_call_arg_bindings(input, token, "extern", projection, args, result_output, {
            hole("native.hole.code.inst.call.extern." .. token .. ".target", Native.NativePatchCodeExternAddress(self.extern)),
        })
    end

    function Code.CodeCallIndirect:append_native_call_bindings(input, token, projection, args, result_output)
        return append_call_arg_bindings(input, token, "indirect", projection, args, result_output, {
            frame_offset_binding("native.hole.code.inst.call.indirect." .. token .. ".fn", placement_for_value(input.state, self.callee)),
        })
    end

    function Code.CodeCallClosure:append_native_call_bindings(input, token, projection, args, result_output)
        local closure = placement_for_value(input.state, self.closure)
        if not asdl.isa(closure.location, Native.NativeValueFrameSlotLocation) then internal_error("native closure call requires a frame-slot closure value") end
        return append_call_arg_bindings(input, token, "closure", projection, args, result_output, {
            frame_offset_value_binding("native.hole.code.inst.call.closure." .. token .. ".fn", closure.location.slot.offset),
            frame_offset_value_binding("native.hole.code.inst.call.closure." .. token .. ".env", closure.location.slot.offset + 8),
        })
    end

    function Code.CodeInstCall:append_native_inst_template(input)
        local sig = signature_for_call(input, self.sig)
        local projection = self.target:select_native_call_projection(sig, input.plan.target)
        local shape = self.target:native_code_call_shape()
        local token = projection:native_projection_token()
        local mode = self.target:native_call_family_mode()
        local output = append_call_result_output(input, self.dst, projection)
        local family = Support.code_inst_frame_family("call." .. mode .. "." .. token, input.plan.target, Support.scalar_bool8(), Native.NativeCodeInstCallShapeAxis(shape, projection))
        local node = append_family_node(input, "call", family, {}, output and { output } or {}, self.target:append_native_call_bindings(input, token, projection, self.args, output))
        if output ~= nil then append_storage_value_edge(input, output, node) end
        return node
    end

    local function find_block_param_plan(input, block_id)
        for _, entry in ipairs(input.lowering.active_func.block_params or {}) do
            if entry.block == block_id then return entry.params or {} end
        end
        internal_error("native control lowering cannot find block parameter plan for " .. tostring(block_id and block_id.text))
    end

    local function append_edge_copy_node(input, source_value, dest_value)
        local source = placement_for_value(input.state, source_value)
        local dest = placement_for_value(input.state, dest_value)
        local scalar = source.representation:native_scalar_rep()
        local family = Support.code_inst_frame_family("edge_copy." .. scalar_token(scalar) .. ".slot.to.slot", input.plan.target, scalar, Native.NativeCodeInstAliasAxis(scalar:native_code_type()))
        local id_base = "native.hole.code.inst.edge_copy." .. scalar_token(scalar) .. ".slot.to.slot"
        local node = append_family_node(input, "edge_copy", family, { source }, { dest }, {
            frame_offset_binding(id_base .. ".src", source),
            frame_offset_binding(id_base .. ".dst", dest),
        })
        input.state.edge_copy_plan.entries[#input.state.edge_copy_plan.entries + 1] = Native.NativeEdgeCopyEntry(Code.CodeBlockId("native.edge.unknown.from"), Code.CodeBlockId("native.edge.unknown.to"), { Native.NativeEdgeCopyValue(source_value, dest_value, dest) })
        return append_frame_value_edge(input, dest, node, scalar)
    end

    local function append_parallel_copy_node(input, dest_block, args, params)
        local src0 = placement_for_value(input.state, args[1])
        local src1 = placement_for_value(input.state, args[2])
        local dst0 = placement_for_value(input.state, params[1].value)
        local dst1 = placement_for_value(input.state, params[2].value)
        local scalar = src0.representation:native_scalar_rep()
        if src1.representation:native_scalar_rep() ~= scalar
            or dst0.representation:native_scalar_rep() ~= scalar
            or dst1.representation:native_scalar_rep() ~= scalar then
            return nil
        end
        local temp_value = Code.CodeValueId("native.edge.parallel.tmp." .. dest_block.text .. "." .. tostring(#input.state.edge_copy_plan.entries + 1))
        local temp = allocate_value_slot(input.state, temp_value, scalar, target_frame_alignment(input.plan.target))
        local token = scalar_token(scalar)
        local family = Support.code_inst_frame_family("parallel_copy." .. token .. ".slot.slot.temp", input.plan.target, scalar, Native.NativeCodeInstAliasAxis(scalar:native_code_type()))
        local id_base = "native.hole.code.inst.parallel_copy." .. token
        local node = append_family_node(input, "parallel_copy", family, { src0, src1 }, { dst0, dst1 }, {
            frame_offset_binding(id_base .. ".src0", src0),
            frame_offset_binding(id_base .. ".src1", src1),
            frame_offset_binding(id_base .. ".dst0", dst0),
            frame_offset_binding(id_base .. ".dst1", dst1),
            frame_offset_binding(id_base .. ".tmp", temp),
        })
        input.state.edge_copy_plan.entries[#input.state.edge_copy_plan.entries + 1] = Native.NativeEdgeCopyEntry(dest_block, dest_block, {
            Native.NativeEdgeCopyValue(args[1], params[1].value, dst0),
            Native.NativeEdgeCopyValue(args[2], params[2].value, dst1),
        })
        append_frame_value_edge(input, dst0, node, scalar)
        append_frame_value_edge(input, dst1, node, scalar)
        return node
    end

    local function append_successor_copy_chain(input, dest_block, args, source_symbol)
        local params = find_block_param_plan(input, dest_block)
        if #(args or {}) ~= #params then internal_error("native control edge argument count does not match destination block params") end
        local first_node
        local last_node
        local previous_tail = input.state.control_plan.nodes[#input.state.control_plan.nodes]
        if #(args or {}) == 2 then
            local parallel = append_parallel_copy_node(input, dest_block, args, params)
            if parallel ~= nil then
                first_node = parallel
                last_node = parallel
            end
        end
        if first_node == nil then
            for i, arg in ipairs(args or {}) do
                local node = append_edge_copy_node(input, arg, params[i].value)
                if first_node == nil then first_node = node end
                last_node = node
            end
        end
        local target = first_node and first_node.id or block_entry_node_id(dest_block)
        if first_node ~= nil then
            remove_auto_continuation_edge(input.state, previous_tail, first_node)
            append_control_edge(input.state, Native.NativeContinuationEdge(last_node.id, block_entry_node_id(dest_block), Support.next_continuation_symbol()))
        end
        return target
    end

    local function append_terminal_exit(input, node)
        input.state.control_plan.exits[#input.state.control_plan.exits + 1] = node.id
        return node
    end

    local function append_result_copy_to_direct_slot(input, value, shape, result_slot)
        local placement = placement_for_value(input.state, value)
        local scalar = shape:native_result_family_scalar(input.plan.target)
        local result_placement = Native.NativeValuePlacement(
            Native.NativeTemplateValueId("native.code.result." .. result_slot.id.text),
            result_slot.representation,
            Native.NativeValueFrameSlotLocation(result_slot)
        )
        local family = Support.code_inst_frame_family("result_copy." .. shape:native_result_shape_token(), input.plan.target, scalar, Native.NativeCodeInstResultCopyAxis(shape))
        local id_base = "native.hole.code.inst.result_copy." .. shape:native_result_shape_token()
        return append_family_node(input, "result_copy", family, { placement }, { result_placement }, {
            frame_offset_binding(id_base .. ".src", placement),
            frame_offset_binding(id_base .. ".dst", result_placement),
        })
    end

    local function append_result_copy_to_sret(input, value, shape, pointer_slot)
        local placement = placement_for_value(input.state, value)
        local scalar = shape:native_result_family_scalar(input.plan.target)
        local family = Support.code_inst_frame_family("result_copy." .. shape:native_result_shape_token(), input.plan.target, scalar, Native.NativeCodeInstResultCopyAxis(shape))
        local id_base = "native.hole.code.inst.result_copy." .. shape:native_result_shape_token()
        return append_family_node(input, "result_copy", family, { placement }, {}, {
            frame_offset_binding(id_base .. ".src", placement),
            frame_offset_value_binding(id_base .. ".sret_ptr", pointer_slot.offset),
            hole(id_base .. ".size", Native.NativePatchImmediateI32(placement.location.slot.size)),
        })
    end

    local function append_return_terminal(input, shape, inputs)
        local scalar = shape:native_result_family_scalar(input.plan.target)
        local family = Support.code_term_frame_family("return." .. shape:native_result_shape_token(), input.plan.target, scalar, Native.NativeCodeTermReturnShapeAxis(shape))
        local node = append_family_node(input, "return", family, inputs or {}, {}, {})
        return append_terminal_exit(input, node)
    end

    function Code.CodeTerm:append_native_term_template(input)
        return self.op:append_native_term_template(input)
    end

    function Code.CodeTermReturn:append_native_term_template(input)
        if #(self.values or {}) > 1 then internal_error("Lalin native CodeTermReturn is invalid: Lalin has zero or one return value") end
        local shape = input.lowering.active_func.abi.result:native_code_result_shape()
        if asdl.isa(shape, Native.NativeCodeResultVoidShape) then
            if #(self.values or {}) ~= 0 then internal_error("native void CodeTermReturn must not carry result values") end
            return append_return_terminal(input, shape, {})
        end
        if #(self.values or {}) ~= 1 then internal_error("native non-void CodeTermReturn requires exactly one result value") end
        local value = self.values[1]
        if asdl.isa(shape, Native.NativeCodeResultSRetShape) then
            local pointer_slot = sret_result_pointer_slot(input.state)
            if pointer_slot == nil then internal_error("native sret CodeTermReturn has no reserved sret pointer slot") end
            local copy_node = append_result_copy_to_sret(input, value, shape, pointer_slot)
            return append_return_terminal(input, shape, { placement_for_value(input.state, value) })
        end
        local result_slot = direct_result_slot(input.state)
        if result_slot == nil then internal_error("native direct CodeTermReturn has no reserved result slot") end
        append_result_copy_to_direct_slot(input, value, shape, result_slot)
        return append_return_terminal(input, shape, { placement_for_value(input.state, value) })
    end

    function Code.CodeTermJump:append_native_term_template(input)
        local family = Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())
        local node = append_family_node(input, "jump", family, {}, {}, {})
        local target = append_successor_copy_chain(input, self.dest, self.args, Support.next_continuation_symbol())
        append_control_edge(input.state, Native.NativeContinuationEdge(node.id, target, Support.next_continuation_symbol()))
        return node
    end

    function Code.CodeTermBranch:append_native_term_template(input)
        local cond = placement_for_value(input.state, self.cond)
        local family = Support.code_term_family("branch.bool8.slot", input.plan.target, Native.NativeCodeTermBranchAxis, Support.protocol_void_none())
        local node = append_family_node(input, "branch", family, { cond }, {}, {
            frame_offset_binding("native.hole.code.term.branch.bool8.slot.src", cond),
        })
        local then_target = append_successor_copy_chain(input, self.then_dest, self.then_args, Support.then_continuation_symbol())
        local then_first = input.state.control_plan.nodes[#input.state.control_plan.nodes]
        local else_target = append_successor_copy_chain(input, self.else_dest, self.else_args, Support.else_continuation_symbol())
        append_control_edge(input.state, Native.NativeConditionalBranchEdge(node.id, then_target, Support.then_continuation_symbol(), else_target, Support.else_continuation_symbol(), cond.value))
        return node
    end

    function Code.CodeTermSwitch:append_native_term_template(input)
        local key = placement_for_value(input.state, self.value)
        local scalar = key.representation:native_scalar_rep()
        local previous_compare
        for _, case in ipairs(self.cases or {}) do
            local family = Support.code_term_family("switch_step." .. scalar_token(scalar) .. ".slot.imm", input.plan.target, Native.NativeCodeTermSwitchAxis, Support.protocol_void_none())
            local node = append_family_node(input, "switch", family, { key }, {}, {
                frame_offset_binding("native.hole.code.term.switch_step." .. scalar_token(scalar) .. ".slot.src", key),
                hole(scalar_immediate_hole_id("native.hole.code.term.switch_step." .. scalar_token(scalar) .. ".slot.case", scalar), case.literal:native_patch_coordinate_for_scalar(scalar)),
            })
            if previous_compare ~= nil then replace_conditional_else_target(input.state, previous_compare.id, node.id) end
            local case_target = append_successor_copy_chain(input, case.dest, case.args, Support.then_continuation_symbol())
            append_control_edge(input.state, Native.NativeConditionalBranchEdge(node.id, case_target, Support.then_continuation_symbol(), block_entry_node_id(self.default_dest), Support.else_continuation_symbol(), key.value))
            previous_compare = node
        end
        local default_target = append_successor_copy_chain(input, self.default_dest, self.default_args, Support.next_continuation_symbol())
        if previous_compare == nil then
            local family = Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())
            local node = append_family_node(input, "switch.default", family, {}, {}, {})
            append_control_edge(input.state, Native.NativeContinuationEdge(node.id, default_target, Support.next_continuation_symbol()))
            return node
        end
        replace_conditional_else_target(input.state, previous_compare.id, default_target)
        return previous_compare
    end

    function Code.CodeTermVariantSwitch:append_native_term_template(input)
        local key = placement_for_value(input.state, self.tag)
        local scalar = key.representation:native_scalar_rep()
        local last_node
        for _, case in ipairs(self.cases or {}) do
            local family = Support.code_term_family("variant_switch_step." .. scalar_token(scalar) .. ".slot.imm", input.plan.target, Native.NativeCodeTermVariantSwitchAxis, Support.protocol_void_none())
            local previous_node = last_node
            last_node = append_family_node(input, "variant_switch", family, { key }, {}, {
                frame_offset_binding("native.hole.code.term.variant_switch_step." .. scalar_token(scalar) .. ".slot.src", key),
                hole(scalar_immediate_hole_id("native.hole.code.term.variant_switch_step." .. scalar_token(scalar) .. ".slot.case", scalar), Native.NativePatchImmediateI32(case.variant.tag_value)),
            })
            if previous_node ~= nil then replace_conditional_else_target(input.state, previous_node.id, last_node.id) end
            local case_target = append_successor_copy_chain(input, case.dest, case.args, Support.then_continuation_symbol())
            append_control_edge(input.state, Native.NativeConditionalBranchEdge(last_node.id, case_target, Support.then_continuation_symbol(), block_entry_node_id(self.default_dest), Support.else_continuation_symbol(), key.value))
        end
        local default_target = append_successor_copy_chain(input, self.default_dest, self.default_args, Support.next_continuation_symbol())
        if last_node == nil then
            local family = Support.code_term_family("jump.next", input.plan.target, Native.NativeCodeTermJumpAxis, Support.protocol_void_none())
            local node = append_family_node(input, "variant_switch.default", family, {}, {}, {})
            append_control_edge(input.state, Native.NativeContinuationEdge(node.id, default_target, Support.next_continuation_symbol()))
            return node
        end
        replace_conditional_else_target(input.state, last_node.id, default_target)
        return last_node
    end

    function Code.CodeTermTrap:append_native_term_template(input)
        local family = Support.code_term_family("trap.trap", input.plan.target, Native.NativeCodeTermTrapAxis, Support.protocol_void_none())
        return append_terminal_exit(input, append_family_node(input, "trap", family, {}, {}, {}))
    end

    function Code.CodeTermUnreachable:append_native_term_template(input)
        local family = Support.code_term_family("unreachable.trap", input.plan.target, Native.NativeCodeTermUnreachableAxis, Support.protocol_void_none())
        return append_terminal_exit(input, append_family_node(input, "unreachable", family, {}, {}, {}))
    end

    T._lalin_api_cache.native_code_methods = api
    return api
end

return bind_context
