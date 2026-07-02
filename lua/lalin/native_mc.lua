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
            embedded.text,
            embedded.symbols,
            embedded.relocations,
            embedded.holes
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

    local function continuation_target(graph, from, symbol)
        for _, edge in ipairs(graph.control_edges or {}) do
            if asdl.isa(edge, Native.NativeContinuationEdge)
                and edge.from == from
                and edge.symbol == symbol then
                return edge.to
            end
        end
        return nil
    end

    local function duplicate_binding_rejects(plan)
        local rejects = {}
        for i = 1, #(plan.bindings or {}) do
            for j = i + 1, #(plan.bindings or {}) do
                if plan.bindings[i].hole == plan.bindings[j].hole then
                    rejects[#rejects + 1] = Native.NativeInstallRejectDuplicateBinding(plan.bindings[i].hole)
                end
            end
        end
        return rejects
    end

    local function binding_for_hole(plan, hole_id)
        local found
        for _, binding in ipairs(plan.bindings or {}) do
            if binding.hole == hole_id then
                if found ~= nil then return found end
                found = binding
            end
        end
        return found
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
        return Native.NativeEmbeddedBankImported(Native.NativeTemplateBank(embedded.id, embedded.target, entries))
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

        entry_node_for_graph(self)
        return Native.NativeCopyPlan(
            self,
            Native.NativeCodeLayout(layout_nodes, offset, alignment),
            self.frame_layout,
            bindings,
            self.protocol
        )
    end

    local function apply_rel32(base_address, patch_address, target_address, addend)
        native_api.write_u32_le(patch_address, target_address + (addend or 0) - patch_address)
        return nil
    end

    local function apply_node_relocation(plan, node, node_offset, relocation, base_address)
        local patch_address = base_address + node_offset + relocation.offset
        if asdl.isa(relocation, Native.NativeRelocationContinuation) then
            local target_node = continuation_target(plan.graph, node.id, relocation.symbol)
            if target_node == nil then
                return Native.NativeInstallRejectMissingContinuationTarget(node.id, relocation.symbol)
            end
            local target_offset = node_layout_offset(plan.layout, target_node)
            if target_offset == nil then
                return Native.NativeInstallRejectMissingContinuationTarget(node.id, relocation.symbol)
            end
            return apply_rel32(base_address, patch_address, base_address + target_offset, relocation.addend)
        end
        if asdl.isa(relocation, Native.NativeRelocationRel32) then
            local target_offset = symbol_offset(node.entry.compiled, relocation.symbol)
            if target_offset == nil then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "missing local rel32 symbol " .. tostring(relocation.symbol))
            end
            return apply_rel32(base_address, patch_address, base_address + node_offset + target_offset, relocation.addend)
        end
        if asdl.isa(relocation, Native.NativeRelocationAbs64) then
            local target_offset = symbol_offset(node.entry.compiled, relocation.symbol)
            if target_offset == nil then
                return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "missing local abs64 symbol " .. tostring(relocation.symbol))
            end
            native_api.write_u64_le(patch_address, base_address + node_offset + target_offset + (relocation.addend or 0))
            return nil
        end
        if asdl.isa(relocation, Native.NativeRelocationRuntimeSymbol) then
            return Native.NativeInstallRejectUnsupportedRelocation(node.id, relocation.offset, "runtime symbol relocation has no runtime address")
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
                local binding = binding_for_hole(self, hole_layout.id)
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

        local base_address, allocation_reject = input.allocator:allocate_native_memory(input, self.layout.size)
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
                local reject = apply_node_relocation(self, node, node_offset, relocation, base_address)
                if reject ~= nil then rejects[#rejects + 1] = reject end
            end
        end

        for _, node in ipairs(self.graph.nodes) do
            local node_offset = node_layout_offset(self.layout, node.id)
            for _, hole_layout in ipairs(node.entry.compiled.holes) do
                local binding = binding_for_hole(self, hole_layout.id)
                local reject = hole_layout.hole:apply_native_patch(Native.NativePatchApplyInput(base_address + node_offset, hole_layout, binding))
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
            self.layout.size,
            self.protocol
        ))
    end

    T._lalin_api_cache.native_mc = api
    return api
end

return bind_context
