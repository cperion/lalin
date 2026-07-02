local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_code_methods ~= nil then return T._lalin_api_cache.native_code_methods end

    local Code = T.LalinCode
    local Core = T.LalinCore
    local Native = T.LalinNative
    local Support = require("lalin.native_template_support")(T)
    local api = {}

    local FRAME_PARAM_STRIDE = 16
    local FRAME_RESULT_OFFSET = 32
    local FRAME_ALIGNMENT = 16

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
        return Native.NativeTemplateNodeId("native.code.node." .. tostring(#state.nodes + 1) .. "." .. role)
    end

    local function align_up(offset, alignment)
        if alignment <= 1 then return offset end
        local rem = offset % alignment
        if rem == 0 then return offset end
        return offset + (alignment - rem)
    end

    local function scalar_size(scalar)
        return scalar:native_size_bytes()
    end

    local function frame_slot_id(value, suffix)
        return Native.NativeFrameSlotId("native.frame.slot." .. value.text .. (suffix and ("." .. suffix) or ""))
    end

    local function make_frame_slot(value, scalar, offset, suffix)
        return Native.NativeFrameSlot(
            frame_slot_id(value, suffix),
            scalar,
            offset,
            scalar_size(scalar),
            scalar:native_frame_alignment()
        )
    end

    local function value_frame_placement(value, scalar, slot)
        return Native.NativeValuePlacement(
            native_value_id(value),
            scalar,
            Native.NativeValueFrameSlotLocation(slot)
        )
    end

    local function placement_for_value(state, value)
        for _, entry in ipairs(state.placements) do
            if entry.value == value then return entry.placement end
        end
        internal_error("no native frame placement for CodeValueId " .. tostring(value and value.text))
    end

    local function set_placement(state, value, placement)
        for i, entry in ipairs(state.placements) do
            if entry.value == value then
                state.placements[i] = Native.NativeCodeValuePlacementEntry(value, placement)
                return placement
            end
        end
        state.placements[#state.placements + 1] = Native.NativeCodeValuePlacementEntry(value, placement)
        return placement
    end

    local function append_frame_slot(state, slot)
        state.frame_slots[#state.frame_slots + 1] = slot
        local end_offset = slot.offset + slot.size
        if end_offset > state.next_frame_offset then state.next_frame_offset = end_offset end
        return slot
    end

    local function allocate_param_slot(state, value, scalar, index)
        local slot = append_frame_slot(state, make_frame_slot(value, scalar, index * FRAME_PARAM_STRIDE, "param" .. tostring(index)))
        local placement = value_frame_placement(value, scalar, slot)
        set_placement(state, value, placement)
        return placement
    end

    local function allocate_value_slot(state, value, scalar)
        local offset = align_up(state.next_frame_offset, FRAME_ALIGNMENT)
        local slot = append_frame_slot(state, make_frame_slot(value, scalar, offset))
        local placement = value_frame_placement(value, scalar, slot)
        set_placement(state, value, placement)
        return placement
    end

    local function return_slot_for(state, value, scalar)
        local slot = append_frame_slot(state, make_frame_slot(value, scalar, FRAME_RESULT_OFFSET, "return"))
        local placement = value_frame_placement(value, scalar, slot)
        set_placement(state, value, placement)
        return placement
    end

    local function selected_entry(plan, family)
        local selected = plan.bank:select_native_template(Native.NativeTemplateSelectionInput(plan.target, family))
        if asdl.isa(selected, Native.NativeTemplateSelected) then return selected.entry end
        internal_error("native template selection failed for " .. family.id.text .. ": " .. tostring(selected))
    end

    local function append_node(state, node)
        local previous = state.nodes[#state.nodes]
        state.nodes[#state.nodes + 1] = node
        if previous ~= nil then
            state.control_edges[#state.control_edges + 1] = Native.NativeContinuationEdge(
                previous.id,
                node.id,
                Support.next_continuation_symbol()
            )
        end
        return node
    end

    local function append_family_node(input, role, family, inputs, outputs, bindings)
        local node = Native.NativeTemplateNode(
            node_id_for(input.state, role),
            selected_entry(input.plan, family),
            inputs or {},
            outputs or {},
            bindings or {}
        )
        return append_node(input.state, node)
    end

    local function frame_layout_from_state(state)
        return Native.NativeFrameLayout(state.frame_slots, align_up(state.next_frame_offset, FRAME_ALIGNMENT), FRAME_ALIGNMENT)
    end

    local function graph_from_state(plan, state, protocol, entry_node)
        if #state.nodes == 0 then internal_error("native Code graph has no continuation nodes") end
        local nodes = { entry_node }
        for _, node in ipairs(state.nodes) do nodes[#nodes + 1] = node end
        local control_edges = {
            Native.NativeContinuationEdge(entry_node.id, state.nodes[1].id, Support.first_continuation_symbol()),
        }
        for _, edge in ipairs(state.control_edges) do control_edges[#control_edges + 1] = edge end
        return Native.NativeTemplateGraph(
            plan.target,
            protocol,
            frame_layout_from_state(state),
            nodes,
            control_edges,
            state.value_edges,
            entry_node.id,
            { state.nodes[#state.nodes].id }
        )
    end

    local function hole(id, coordinate)
        return Native.NativePatchBinding(Native.NativePatchHoleId(id), coordinate)
    end

    local function frame_offset_binding(id, placement)
        return hole(id, Native.NativePatchFrameOffset(placement.location.slot.offset))
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

    function Code.CodeModule:plan_native_copy(input)
        if #self.funcs ~= 1 then internal_error("native CodeModule graph construction expects one function in this phase") end
        return self.funcs[1]:plan_native_copy(input)
    end

    local function result_scalar_from_protocol(protocol)
        if asdl.isa(protocol, Native.NativeCallReturnScalar) then return protocol.scalar end
        internal_error("native C frame entry selection requires a scalar return protocol")
    end

    function Code.CodeFunc:plan_native_copy(plan)
        if #(self.params or {}) == 0 then internal_error("native C frame entry currently requires at least one scalar parameter") end
        local state = Native.NativeCodeGraphBuilderState({}, {}, {}, {}, {}, 0)
        local build = Native.NativeCodeGraphBuildInput(plan, state)
        for index, param in ipairs(self.params or {}) do
            local scalar = param.ty:native_machine_scalar(plan.target)
            allocate_param_slot(state, param.value, scalar, index - 1)
        end
        local block
        for _, candidate in ipairs(self.blocks or {}) do
            if candidate.id == self.entry then block = candidate end
        end
        if block == nil then internal_error("native CodeFunc entry block is absent: " .. self.entry.text) end
        local protocol = block:select_native_template_graph(build)
        local param_scalar = self.params[1].ty:native_machine_scalar(plan.target)
        local result_scalar = result_scalar_from_protocol(protocol)
        local family_name = "entry." .. scalar_token(param_scalar) .. ".return." .. scalar_token(result_scalar)
        local family = Support.code_func_frame_family(family_name, plan.target, param_scalar, result_scalar)
        local entry_node = Native.NativeTemplateNode(
            Native.NativeTemplateNodeId("native.code.node.entry." .. self.id.text),
            selected_entry(plan, family),
            {},
            {},
            {}
        )
        return graph_from_state(plan, state, protocol, entry_node)
    end

    function Code.CodeBlock:select_native_template_graph(input)
        for _, inst in ipairs(self.insts or {}) do
            inst:append_native_inst_template(input)
        end
        return self.term:append_native_term_template(input)
    end

    function Code.CodeInst:append_native_inst_template(input)
        return self.op:append_native_inst_template(input)
    end

    function Code.CodeInstConst:append_native_inst_template(input)
        return self.const:append_native_const_template(input, self.dst)
    end

    function Code.CodeConstLiteral:append_native_const_template(input, dst)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local axis = Native.NativeCodeConstLiteralAxis(self.ty)
        local family = Support.code_const_frame_family("literal." .. scalar_token(scalar), input.plan.target, scalar, axis)
        local coordinate = self.literal:native_patch_coordinate_for_scalar(scalar)
        local hole_suffix = (coordinate.value and scalar.bits and scalar.bits > 32) and "imm64" or "imm32"
        local output = allocate_value_slot(input.state, dst, scalar)
        local token = scalar_token(scalar)
        local bindings = {
            frame_offset_binding("native.hole.code.const.literal." .. token .. ".dst", output),
            hole("native.hole.code.const.literal." .. token .. "." .. hole_suffix, coordinate),
        }
        local node = append_family_node(input, "const", family, {}, { output }, bindings)
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativePatchCoordinateValueEdge(output.value, scalar, coordinate)
        return node
    end

    function Code.CodeInstBinary:append_native_inst_template(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local lhs = placement_for_value(input.state, self.lhs)
        local rhs = placement_for_value(input.state, self.rhs)
        local output = allocate_value_slot(input.state, self.dst, scalar)
        local name = self.op:native_binary_family_name()
        local axis = Native.NativeCodeInstBinaryAxis(self.op, self.ty, self.semantics)
        local family = Support.code_inst_frame_family("binary." .. scalar_token(scalar) .. "." .. name, input.plan.target, scalar, axis)
        local token = scalar_token(scalar)
        local node = append_family_node(input, "binary", family, { lhs, rhs }, { output }, {
            frame_offset_binding("native.hole.code.inst.binary." .. token .. "." .. name .. ".lhs", lhs),
            frame_offset_binding("native.hole.code.inst.binary." .. token .. "." .. name .. ".rhs", rhs),
            frame_offset_binding("native.hole.code.inst.binary." .. token .. "." .. name .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar, output.location.slot)
        return node
    end

    function Code.CodeInstFloatBinary:append_native_inst_template(input)
        local scalar = self.ty:native_machine_scalar(input.plan.target)
        local lhs = placement_for_value(input.state, self.lhs)
        local rhs = placement_for_value(input.state, self.rhs)
        local output = allocate_value_slot(input.state, self.dst, scalar)
        local name = self.op:native_binary_family_name()
        local axis = Native.NativeCodeInstFloatBinaryAxis(self.op, self.ty, self.mode)
        local family = Support.code_inst_frame_family("float_binary." .. scalar_token(scalar) .. "." .. name, input.plan.target, scalar, axis)
        local token = scalar_token(scalar)
        local node = append_family_node(input, "float_binary", family, { lhs, rhs }, { output }, {
            frame_offset_binding("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".lhs", lhs),
            frame_offset_binding("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".rhs", rhs),
            frame_offset_binding("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, scalar, output.location.slot)
        return node
    end

    function Code.CodeInstCompare:append_native_inst_template(input)
        local operand_scalar = self.operand_ty:native_machine_scalar(input.plan.target)
        local result_scalar = Support.scalar_bool8()
        local lhs = placement_for_value(input.state, self.lhs)
        local rhs = placement_for_value(input.state, self.rhs)
        local output = allocate_value_slot(input.state, self.dst, result_scalar)
        local name = self.op:native_compare_family_name()
        local axis = Native.NativeCodeInstCompareAxis(self.op, self.operand_ty)
        local family = Support.code_inst_frame_family("compare." .. scalar_token(operand_scalar) .. "." .. name, input.plan.target, operand_scalar, axis)
        local token = scalar_token(operand_scalar)
        local node = append_family_node(input, "compare", family, { lhs, rhs }, { output }, {
            frame_offset_binding("native.hole.code.inst.compare." .. token .. "." .. name .. ".lhs", lhs),
            frame_offset_binding("native.hole.code.inst.compare." .. token .. "." .. name .. ".rhs", rhs),
            frame_offset_binding("native.hole.code.inst.compare." .. token .. "." .. name .. ".dst", output),
        })
        input.state.value_edges[#input.state.value_edges + 1] = Native.NativeFrameSlotValueEdge(output.value, node.id, node.id, result_scalar, output.location.slot)
        return node
    end

    local function append_alias_to_return_slot(input, value, placement)
        if placement.location.slot.offset == FRAME_RESULT_OFFSET then return placement end
        local scalar = placement.scalar
        local output = return_slot_for(input.state, value, scalar)
        local axis = Native.NativeCodeInstAliasAxis(scalar:native_code_type())
        local family = Support.code_inst_frame_family("alias." .. scalar_token(scalar), input.plan.target, scalar, axis)
        local token = scalar_token(scalar)
        append_family_node(input, "return.alias", family, { placement }, { output }, {
            frame_offset_binding("native.hole.code.inst.alias." .. token .. ".src", placement),
            frame_offset_binding("native.hole.code.inst.alias." .. token .. ".dst", output),
        })
        return output
    end

    function Code.CodeTerm:append_native_term_template(input)
        return self.op:append_native_term_template(input)
    end

    function Code.CodeTermReturn:append_native_term_template(input)
        if #(self.values or {}) == 0 then internal_error("native C frame protocol does not yet model void CodeTermReturn") end
        if #(self.values or {}) > 1 then internal_error("Lalin native CodeTermReturn is invalid: Lalin has zero or one return value") end
        local value = self.values[1]
        local placement = append_alias_to_return_slot(input, value, placement_for_value(input.state, value))
        local scalar = placement.scalar
        local ty = scalar:native_code_type()
        local axis = Native.NativeCodeTermReturnAxis({ ty })
        local family = Support.code_term_frame_family("return." .. scalar_token(scalar), input.plan.target, scalar, axis)
        append_family_node(input, "return", family, { placement }, {}, {})
        return Native.NativeCallReturnScalar(scalar)
    end

    T._lalin_api_cache.native_code_methods = api
    return api
end

return bind_context
