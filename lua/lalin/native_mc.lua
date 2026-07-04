local asdl = require("lalin.asdl")
local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then ffi = nil end

if ffi ~= nil then
    ffi.cdef [[
        void *mmap(void *addr, size_t length, int prot, int flags, int fd, int64_t offset);
    ]]
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_mc ~= nil then return T._lalin_api_cache.native_mc end

    local native_api = require("lalin.native")(T)

    local Native = T.LalinNative
    local api = {}

    local PROT_READ = 0x1
    local PROT_WRITE = 0x2
    local PROT_EXEC = 0x4
    local MAP_PRIVATE = 0x02
    local MAP_ANON_LINUX = 0x20
    local MAP_ANON_DARWIN = 0x1000

    local function mmap_failed_pointer()
        return ffi.cast("void *", -1)
    end

    local function map_anon_flag()
        if jit and jit.os == "OSX" then return MAP_ANON_DARWIN end
        if jit and jit.os == "Linux" then return MAP_ANON_LINUX end
        error("lalin.native_mc: mmap allocator is not modeled for host OS " .. tostring(jit and jit.os), 3)
    end

    local function template_id_for_embedded(bank, index, embedded)
        local family_id = embedded.family.id and embedded.family.id.text or tostring(index)
        return Native.NativeTemplateId(bank.id.text .. ":" .. family_id .. ":" .. tostring(index))
    end

    local function text_size(section)
        if section.bytes.size ~= nil then return section.bytes.size end
        return #section.bytes.bytes
    end

    local function compiled_from_embedded(bank, embedded, index)
        return Native.NativeCompiledTemplate(
            template_id_for_embedded(bank, index, embedded),
            embedded.family,
            bank.target,
            embedded.extraction,
            embedded.signature,
            embedded.text,
            embedded.symbols,
            embedded.relocations,
            embedded.holes,
            embedded.hole_ordinals,
            embedded.relocation_declarations,
            embedded.constant_pool_layout
        )
    end

    local function align_up(offset, alignment)
        alignment = alignment or 1
        if alignment <= 1 then return offset end
        local rem = offset % alignment
        if rem == 0 then return offset end
        return offset + (alignment - rem)
    end

    local function node_layout_offset(layout, node_id)
        for _, node_layout in ipairs(layout.nodes) do
            if node_layout.node == node_id then return node_layout.offset end
        end
        return nil
    end

    local function entry_node_for_graph(graph)
        for _, node in ipairs(graph.nodes) do
            if node.id == graph.entry then return node end
        end
        error("lalin.native_mc: NativeTemplateGraph entry node is absent", 3)
    end

    local function symbol_offset(template, name)
        for _, sym in ipairs(template.symbols or {}) do
            if sym.name == name then return sym.offset end
        end
        return nil
    end

    function Native.NativeFallthroughEdge:native_continuation_target(from, symbol)
        if self.from == from and self.symbol == symbol then return self.to end
        return nil
    end

    function Native.NativeConditionalBranchEdge:native_continuation_target(from, symbol)
        if self.from ~= from then return nil end
        if self.then_symbol == symbol then return self.then_to end
        if self.else_symbol == symbol then return self.else_to end
        return nil
    end

    function Native.NativeLoopBackedgeEdge:native_continuation_target(from, symbol)
        if self.from == from and self.symbol == symbol then return self.to end
        return nil
    end

    function Native.NativeExitEdge:native_continuation_target(_from, _symbol)
        return nil
    end

    function Native.NativeContinuationEdge:native_continuation_target(from, symbol)
        if self.from == from and self.symbol == symbol then return self.to end
        return nil
    end

    function Native.NativeRuntimeCallReturnEdge:native_continuation_target(from, symbol)
        if self.from == from and self.return_symbol == symbol then return self.to end
        return nil
    end

    local function continuation_target(graph, from, symbol)
        for _, edge in ipairs(graph.control_edges or {}) do
            local target = edge:native_continuation_target(from, symbol)
            if target ~= nil then return target end
        end
        return nil
    end

    function Native.NativePatchBindingHoleId:native_patch_binding_key()
        return "hole:" .. self.hole.text
    end

    function Native.NativePatchBindingHoleOrdinal:native_patch_binding_key()
        return "ordinal:" .. self.ordinal.text
    end

    function Native.NativePatchBindingTarget:native_matches_hole(_hole_layout, _ordinal_id)
        return false
    end

    function Native.NativePatchBindingHoleId:native_matches_hole(hole_layout, _ordinal_id)
        return self.hole == hole_layout.id
    end

    function Native.NativePatchBindingHoleOrdinal:native_matches_hole(_hole_layout, ordinal_id)
        return ordinal_id ~= nil and self.ordinal == ordinal_id
    end

    local function same_binding_scope(a, b)
        return a.node == b.node and a.instance == b.instance
    end

    local function ordinal_id_for_hole(template, hole_layout)
        for _, ordinal in ipairs(template.hole_ordinals or {}) do
            if ordinal.symbol == hole_layout.symbol then return ordinal.id end
        end
        return nil
    end

    local function hole_layout_for_ordinal(template, ordinal)
        for _, hole_layout in ipairs(template.holes or {}) do
            if hole_layout.symbol == ordinal.symbol then return hole_layout end
        end
        local width = 4
        if asdl.isa(ordinal.hole, Native.NativePatchImm64) or asdl.isa(ordinal.hole, Native.NativePatchPtr64) then width = 8 end
        return Native.NativeHoleLayout(Native.NativePatchHoleId(ordinal.id.text), ordinal.symbol, 0, width, ordinal.hole)
    end

    local function duplicate_binding_hole_id(plan, binding)
        if asdl.isa(binding.target, Native.NativePatchBindingHoleId) then return binding.target.hole end
        for _, node in ipairs(plan.graph.nodes or {}) do
            if node.id == binding.node and node.instance == binding.instance then
                for _, ordinal in ipairs(node.entry.compiled.hole_ordinals or {}) do
                    if asdl.isa(binding.target, Native.NativePatchBindingHoleOrdinal) and binding.target.ordinal == ordinal.id then
                        return hole_layout_for_ordinal(node.entry.compiled, ordinal).id
                    end
                end
            end
        end
        return Native.NativePatchHoleId(binding.target:native_patch_binding_key())
    end

    local function duplicate_binding_rejects(plan)
        local rejects = {}
        for i = 1, #(plan.bindings or {}) do
            for j = i + 1, #(plan.bindings or {}) do
                if same_binding_scope(plan.bindings[i], plan.bindings[j]) then
                    local left_hole = duplicate_binding_hole_id(plan, plan.bindings[i])
                    local right_hole = duplicate_binding_hole_id(plan, plan.bindings[j])
                    if left_hole == right_hole then
                        rejects[#rejects + 1] = Native.NativeInstallRejectDuplicateBinding(left_hole)
                    end
                end
            end
        end
        return rejects
    end

    local function binding_for_hole(plan, node, hole_layout)
        local ordinal_id = ordinal_id_for_hole(node.entry.compiled, hole_layout)
        local found
        for _, binding in ipairs(plan.bindings or {}) do
            if binding.node == node.id and binding.instance == node.instance and binding.target:native_matches_hole(hole_layout, ordinal_id) then
                if found ~= nil then return found end
                found = binding
            end
        end
        return found
    end

    local function binding_for_ordinal(plan, node, ordinal)
        local found
        for _, binding in ipairs(plan.bindings or {}) do
            if binding.node == node.id and binding.instance == node.instance
                and asdl.isa(binding.target, Native.NativePatchBindingHoleOrdinal)
                and binding.target.ordinal == ordinal.id then
                if found ~= nil then return found end
                found = binding
            end
        end
        if found ~= nil then return found end
        return binding_for_hole(plan, node, hole_layout_for_ordinal(node.entry.compiled, ordinal))
    end

    local function executable_id_for_plan(plan)
        return Native.NativeExecutableId("native-executable:" .. plan.graph.entry.text)
    end

    function Native.NativeEmbeddedBankImportRequest:import_native_bank()
        local embedded = self.embedded
        local rejects = {}
        local entries = {}

        for i, entry in ipairs(embedded.entries) do
            local source_id = template_id_for_embedded(embedded, i, entry)
            local size = text_size(entry.text)
            if size <= 0 or entry.text.bytes.bytes == "" then
                rejects[#rejects + 1] = Native.NativeBuildRejectEmptyText(source_id, "embedded native template has no text bytes")
            end
            for _, hole_layout in ipairs(entry.holes) do
                if hole_layout.offset < 0 or hole_layout.width <= 0 or hole_layout.offset + hole_layout.width > size then
                    rejects[#rejects + 1] = Native.NativeBuildRejectHoleOutOfRange(
                        source_id,
                        hole_layout.id,
                        hole_layout.offset,
                        hole_layout.width
                    )
                end
            end
            if #rejects == 0 then
                local compiled = compiled_from_embedded(embedded, entry, i)
                entries[#entries + 1] = Native.NativeTemplateBankEntry(entry.family, compiled)
            end
        end

        if #rejects > 0 then
            return Native.NativeEmbeddedBankRejected(rejects)
        end
        return Native.NativeEmbeddedBankImported(Native.NativeTemplateBank(embedded.id, embedded.target, embedded.manifest, entries))
    end

    function Native.NativeTemplateBank:select_native_template(input)
        if self.target ~= input.target then
            return Native.NativeTemplateSelectionRejected({
                Native.NativeSelectionRejectTargetMismatch(input.target, self.target),
            })
        end

        local matches = {}
        for _, entry in ipairs(self.entries) do
            local selected = entry:select_native_template(input)
            if asdl.isa(selected, Native.NativeTemplateSelected) then
                matches[#matches + 1] = entry
            end
        end

        if #matches == 1 then
            return Native.NativeTemplateSelected(matches[1])
        end
        if #matches > 1 then
            return Native.NativeTemplateSelectionAmbiguous(input.family, matches)
        end
        return Native.NativeTemplateSelectionRejected({
            Native.NativeSelectionRejectMissingBankEntry(input.family),
        })
    end

    function Native.NativeTemplateGraph:select_native_copy_plan(_input)
        local layout_nodes = {}
        local offset = 0
        local alignment = 1
        local bindings = {}
        local constant_pool_entries = {}
        local constant_pool_alignment = 1

        for _, node in ipairs(self.nodes) do
            local text = node.entry.compiled.text
            offset = align_up(offset, text.alignment)
            layout_nodes[#layout_nodes + 1] = Native.NativeCodeLayoutNode(node.id, offset)
            for _, binding in ipairs(node.bindings) do
                bindings[#bindings + 1] = binding
            end
            offset = offset + text_size(text)
            if text.alignment > alignment then alignment = text.alignment end
        end

        local code_size = offset
        for _, node in ipairs(self.nodes) do
            local pool = node.entry.compiled.constant_pool_layout
            if pool ~= nil then
                if pool.alignment > constant_pool_alignment then constant_pool_alignment = pool.alignment end
                for _, layout_entry in ipairs(pool.entries or {}) do
                    local entry_alignment = layout_entry.entry.alignment or pool.alignment or 1
                    offset = align_up(offset, entry_alignment)
                    constant_pool_entries[#constant_pool_entries + 1] = Native.NativeConstantPoolLayoutEntry(layout_entry.entry, offset)
                    offset = offset + layout_entry.entry.bytes.size
                    if entry_alignment > alignment then alignment = entry_alignment end
                end
            end
        end

        entry_node_for_graph(self)
        return Native.NativeCopyPlan(
            self,
            Native.NativeCodeLayout(layout_nodes, code_size, alignment),
            self.frame_layout,
            Native.NativeConstantPoolLayout(constant_pool_entries, offset - code_size, constant_pool_alignment),
            self.addresses,
            offset,
            bindings,
            self.protocol
        )
    end

    local function apply_rel32(base_address, patch_address, target_address, addend)
        local delta = target_address + (addend or 0) - patch_address
        if delta < -2147483648 or delta > 2147483647 then
            return false
        end
        native_api.write_u32_le(patch_address, delta)
        return true
    end

    local function constant_pool_offset_for_node(plan, node, entry_id)
        local flat_index = 0
        for _, graph_node in ipairs(plan.graph.nodes or {}) do
            for _, layout_entry in ipairs((graph_node.entry.compiled.constant_pool_layout and graph_node.entry.compiled.constant_pool_layout.entries) or {}) do
                flat_index = flat_index + 1
                local copied_entry = plan.constant_pool_layout.entries[flat_index]
                if graph_node == node and layout_entry.entry.id == entry_id and copied_entry ~= nil then
                    return copied_entry.offset
                end
            end
        end
        return nil
    end

    local function constant_pool_layout_for_node(plan, node)
        local entries = {}
        local max_align = 1
        local flat_index = 0
        for _, graph_node in ipairs(plan.graph.nodes or {}) do
            for _, layout_entry in ipairs((graph_node.entry.compiled.constant_pool_layout and graph_node.entry.compiled.constant_pool_layout.entries) or {}) do
                flat_index = flat_index + 1
                local copied_entry = plan.constant_pool_layout.entries[flat_index]
                if graph_node == node and copied_entry ~= nil then
                    entries[#entries + 1] = copied_entry
                    if copied_entry.entry.alignment > max_align then max_align = copied_entry.entry.alignment end
                end
            end
        end
        return Native.NativeConstantPoolLayout(entries, plan.constant_pool_layout.size, max_align)
    end

    local function runtime_symbol_by_id(runtime, symbol_id)
        for _, symbol in ipairs((runtime and runtime.symbols) or {}) do
            if symbol.id == symbol_id then return symbol end
        end
        return nil
    end

    function Native.NativeRuntimeAddressCapability:native_runtime_address()
        return nil
    end

    function Native.NativeRuntimeAddressSupplied:native_runtime_address()
        return self.address
    end

    function Native.NativeRuntimeAddressLinkerSymbol:native_runtime_address()
        return nil
    end

    local function relocation_patch_in_range(node, relocation, width)
        return relocation.offset >= 0 and relocation.offset + width <= text_size(node.entry.compiled.text)
    end

    local function native_patch_apply_input(input, plan, node, base_address, node_offset, hole_layout, binding, addend, branch_target_address)
        local executable_hole_layout = Native.NativeHoleLayout(
            hole_layout.id,
            hole_layout.symbol,
            node_offset + hole_layout.offset,
            hole_layout.width,
            hole_layout.hole
        )
        return Native.NativePatchApplyInput(
            base_address,
            executable_hole_layout,
            binding,
            input.runtime,
            constant_pool_layout_for_node(plan, node),
            plan.graph,
            plan.layout,
            plan.addresses,
            base_address + node_offset,
            branch_target_address,
            addend or 0
        )
    end

    local function apply_node_relocation(plan, node, node_offset, relocation, base_address, input)
        local patch_address = base_address + node_offset + relocation.offset
        if asdl.isa(relocation, Native.NativeRelocationContinuation) then
            if not relocation_patch_in_range(node, relocation, 4) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "continuation relocation is out of node text range")
            end
            local target_node = continuation_target(plan.graph, node.id, relocation.symbol)
            if target_node == nil then
                return Native.NativeInstallRejectMissingContinuationTarget(node.id, relocation.symbol)
            end
            local target_offset = node_layout_offset(plan.layout, target_node)
            if target_offset == nil then
                return Native.NativeInstallRejectMissingContinuationTarget(node.id, relocation.symbol)
            end
            if not apply_rel32(base_address, patch_address, base_address + target_offset, relocation.addend) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "continuation rel32 target is out of range")
            end
            return nil
        end
        if asdl.isa(relocation, Native.NativeRelocationRel32) then
            if not relocation_patch_in_range(node, relocation, 4) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "rel32 relocation is out of node text range")
            end
            local target_offset = symbol_offset(node.entry.compiled, relocation.symbol)
            if target_offset == nil then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "missing local rel32 symbol " .. tostring(relocation.symbol))
            end
            if not apply_rel32(base_address, patch_address, base_address + node_offset + target_offset, relocation.addend) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "local rel32 target is out of range")
            end
            return nil
        end
        if asdl.isa(relocation, Native.NativeRelocationAbs64) then
            if not relocation_patch_in_range(node, relocation, 8) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "abs64 relocation is out of node text range")
            end
            local target_offset = symbol_offset(node.entry.compiled, relocation.symbol)
            if target_offset == nil then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "missing local abs64 symbol " .. tostring(relocation.symbol))
            end
            native_api.write_u64_le(patch_address, base_address + node_offset + target_offset + (relocation.addend or 0))
            return nil
        end
        if asdl.isa(relocation, Native.NativeRelocationHoleOrdinal) then
            local hole_layout = hole_layout_for_ordinal(node.entry.compiled, relocation.ordinal)
            hole_layout = Native.NativeHoleLayout(hole_layout.id, hole_layout.symbol, relocation.offset, hole_layout.width, hole_layout.hole)
            if not relocation_patch_in_range(node, relocation, hole_layout.width) then
                return Native.NativeInstallRejectPatchOutOfRange(hole_layout.id, node_offset + relocation.offset, hole_layout.width, plan.layout.size)
            end
            local binding = binding_for_ordinal(plan, node, relocation.ordinal)
            if binding == nil then return Native.NativeInstallRejectMissingBinding(hole_layout.id) end
            local patch_input = native_patch_apply_input(input, plan, node, base_address, node_offset, hole_layout, binding, relocation.addend, nil)
            if asdl.isa(relocation.formula, Native.NativePatchPcRel32)
                and not asdl.isa(hole_layout.hole, Native.NativePatchFrameOffset32)
                and not asdl.isa(hole_layout.hole, Native.NativePatchImm32) then
                return binding.coordinate:write_native_patch_rel32(patch_input)
            end
            return hole_layout.hole:apply_native_patch(patch_input)
        end
        if asdl.isa(relocation, Native.NativeRelocationConstantPool) then
            local width = 4
            if asdl.isa(relocation.formula, Native.NativePatchSym64) then width = 8 end
            if not relocation_patch_in_range(node, relocation, width) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "constant-pool relocation is out of node text range")
            end
            local target_offset = constant_pool_offset_for_node(plan, node, relocation.entry)
            if target_offset == nil then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "missing constant-pool entry " .. tostring(relocation.entry.text))
            end
            local target_address = base_address + target_offset
            if asdl.isa(relocation.formula, Native.NativePatchPcRel32) then
                if not apply_rel32(base_address, patch_address, target_address, relocation.addend) then
                    return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "constant-pool rel32 target is out of range")
                end
                return nil
            end
            if asdl.isa(relocation.formula, Native.NativePatchSym64) then
                native_api.write_u64_le(patch_address, target_address + (relocation.addend or 0))
                return nil
            end
            if asdl.isa(relocation.formula, Native.NativePatchSym32) then
                local value = target_address + (relocation.addend or 0)
                if value < 0 or value > 4294967295 then
                    return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "constant-pool absolute 32-bit target is out of range")
                end
                native_api.write_u32_le(patch_address, value)
                return nil
            end
            return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "unsupported constant-pool relocation formula")
        end
        if asdl.isa(relocation, Native.NativeRelocationRuntimeSymbol) then
            if not relocation_patch_in_range(node, relocation, 4) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "runtime-symbol relocation is out of node text range")
            end
            local symbol = runtime_symbol_by_id(input.runtime, relocation.symbol)
            local address = symbol and symbol.address and symbol.address:native_runtime_address() or nil
            if address == nil then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "runtime symbol relocation has no supplied runtime address")
            end
            if not apply_rel32(base_address, patch_address, address, relocation.addend) then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "runtime symbol rel32 target is out of range")
            end
            return nil
        end
        return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "unknown relocation kind")
    end

    function Native.NativeExecutableAllocatorMmap:allocate_native_memory(_input, size)
        if ffi == nil then error("lalin.native_mc: ffi is required for mmap native executable allocation", 3) end
        if size <= 0 then
            return nil, Native.NativeInstallRejectAllocation("native executable allocation requested zero bytes")
        end
        local ptr = ffi.C.mmap(nil, size, PROT_READ + PROT_WRITE + PROT_EXEC, MAP_PRIVATE + map_anon_flag(), -1, 0)
        if ptr == mmap_failed_pointer() then
            return nil, Native.NativeInstallRejectAllocation("mmap failed")
        end
        return tonumber(ffi.cast("uintptr_t", ptr)), nil
    end

    function Native.NativeCopyPlan:install_native(input)
        local rejects = duplicate_binding_rejects(self)

        for _, node in ipairs(self.graph.nodes) do
            local node_offset = node_layout_offset(self.layout, node.id)
            if node_offset == nil then
                error("lalin.native_mc: NativeCodeLayout is missing a graph node", 3)
            end
            local code_size = self.layout.size
            for _, hole_layout in ipairs(node.entry.compiled.holes) do
                local binding = binding_for_hole(self, node, hole_layout)
                if binding == nil then
                    rejects[#rejects + 1] = Native.NativeInstallRejectMissingBinding(hole_layout.id)
                elseif node_offset + hole_layout.offset < 0 or node_offset + hole_layout.offset + hole_layout.width > code_size then
                    rejects[#rejects + 1] = Native.NativeInstallRejectPatchOutOfRange(
                        hole_layout.id,
                        node_offset + hole_layout.offset,
                        hole_layout.width,
                        code_size
                    )
                end
            end
        end

        if #rejects > 0 then
            return Native.NativeInstallRejected(rejects)
        end

        local base_address, allocation_reject = input.allocator:allocate_native_memory(input, self.total_size)
        if allocation_reject ~= nil then
            return Native.NativeInstallRejected({ allocation_reject })
        end

        for _, node in ipairs(self.graph.nodes) do
            local node_offset = node_layout_offset(self.layout, node.id)
            local dest = ffi.cast("uint8_t *", base_address + node_offset)
            local bytes = node.entry.compiled.text.bytes.bytes
            ffi.copy(dest, bytes, #bytes)
        end

        for _, node in ipairs(self.graph.nodes) do
            local node_offset = node_layout_offset(self.layout, node.id)
            for _, relocation in ipairs(node.entry.compiled.relocations or {}) do
                local reject = apply_node_relocation(self, node, node_offset, relocation, base_address, input)
                if reject ~= nil then rejects[#rejects + 1] = reject end
            end
        end

        for _, layout_entry in ipairs(self.constant_pool_layout.entries or {}) do
            local dest = ffi.cast("uint8_t *", base_address + layout_entry.offset)
            local bytes = layout_entry.entry.bytes.bytes
            ffi.copy(dest, bytes, #bytes)
        end

        for _, node in ipairs(self.graph.nodes) do
            local node_offset = node_layout_offset(self.layout, node.id)
            for _, hole_layout in ipairs(node.entry.compiled.holes) do
                local binding = binding_for_hole(self, node, hole_layout)
                local reject = hole_layout.hole:apply_native_patch(native_patch_apply_input(input, self, node, base_address, node_offset, hole_layout, binding, 0, nil))
                if reject ~= nil then rejects[#rejects + 1] = reject end
            end
        end

        if #rejects > 0 then
            return Native.NativeInstallRejected(rejects)
        end

        local entry_offset = node_layout_offset(self.layout, self.graph.entry)
        if entry_offset == nil then error("lalin.native_mc: NativeCodeLayout is missing graph entry", 3) end
        return Native.NativeInstallSucceeded(Native.NativeExecutable(
            executable_id_for_plan(self),
            input.target,
            base_address,
            base_address + entry_offset,
            self.total_size,
            self.protocol
        ))
    end

    T._lalin_api_cache.native_mc = api
    return api
end

return bind_context
