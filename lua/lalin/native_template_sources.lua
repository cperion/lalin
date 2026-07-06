local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_template_sources ~= nil then return T._lalin_api_cache.native_template_sources end

    local Native = T.LalinNative
    local Code = T.LalinCode
    local Core = T.LalinCore
    local Value = T.LalinValue
    local Stencil = T.LalinStencil
    require("lalin.native")(T)
    local Support = require("lalin.native_template_support")(T)
    local api = {}

    local FRAME_PARAM0_OFFSET = 0
    local FRAME_PARAM1_OFFSET = 16
    local FRAME_RESULT_OFFSET = 32
    local FRAME_BYTES = 256

    local function internal_error(message)
        error("lalin.native_template_sources: " .. message, 3)
    end

    local function require_value(value, name)
        if value == nil then internal_error("missing " .. name) end
        return value
    end

    local function source_id(text)
        return Native.NativeTemplateId("native.source." .. require_value(text, "source id text"))
    end

    local function symbol_fragment(text)
        return tostring(text):gsub("[^%w_]", "_")
    end

    local function concat_lines(lines)
        lines[#lines + 1] = ""
        return table.concat(lines, "\n")
    end

    local function c_prelude()
        return {
            "#include <stdint.h>",
            "#include <stddef.h>",
            "#include <string.h>",
        }
    end

    function api.template_source_id(text)
        return source_id(text)
    end

    function api.append_source(out, source)
        require_value(out, "source output list")
        if not asdl.isa(source, Native.NativeTemplateSource) then
            internal_error("source builder produced non-NativeTemplateSource value")
        end
        out[#out + 1] = source
        return source
    end

    function api.assert_unique_source_ids(sources)
        local seen = {}
        for _, source in ipairs(sources or {}) do
            local key = source.id.text
            if seen[key] ~= nil then internal_error("duplicate NativeTemplateSource id: " .. tostring(key)) end
            seen[key] = true
        end
        return true
    end

    function api.assert_unique_family_ids(sources)
        local seen = {}
        for _, source in ipairs(sources or {}) do
            local key = source.family.id.text
            if seen[key] ~= nil then internal_error("duplicate NativeTemplateFamily id in source set: " .. tostring(key)) end
            seen[key] = true
        end
        return true
    end

    local function id_tail(text)
        return tostring(require_value(text, "id text")):gsub("^native%.source%.", ""):gsub("^code%.", "")
    end

    local function generator_for_source(id_text, family, chunk_class)
        return Support.stencil_generator(
            Support.stencil_generator_id(id_tail(id_text)),
            family,
            chunk_class,
            {}
        )
    end

    local function configuration_for_source(id_text, generator)
        return Support.stencil_configuration(
            Support.stencil_configuration_id(id_tail(id_text)),
            generator,
            {}
        )
    end

    local function hole_ordinal_for_layout(source_text, index, layout)
        return Support.hole_ordinal(
            Support.hole_ordinal_id(id_tail(source_text) .. "." .. tostring(index) .. "." .. layout.id.text:gsub("[^%w_%.%-]", "_")),
            index - 1,
            layout.symbol,
            layout.hole
        )
    end

    local function hole_ordinals_for_layouts(source_text, holes)
        local out = {}
        for i, hole in ipairs(holes or {}) do out[#out + 1] = hole_ordinal_for_layout(source_text, i, hole) end
        return out
    end

    local function relocation_declarations(hole_ordinals, continuation_ordinals, extra_relocation_kinds)
        local out = {}
        if #(hole_ordinals or {}) > 0 then out[#out + 1] = Native.NativeTemplateRelocationHoleOrdinal end
        if #(continuation_ordinals or {}) > 0 then out[#out + 1] = Native.NativeTemplateRelocationContinuation end
        for _, kind in ipairs(extra_relocation_kinds or {}) do out[#out + 1] = kind end
        return out
    end

    local function scalar_frame_signature(scalar, operand_count, continuation_ordinals)
        local operands = {}
        for i = 0, (operand_count or 0) - 1 do
            operands[#operands + 1] = Support.stencil_operand(i, scalar, Support.location_class_frame_slot())
        end
        local continuations = {}
        for _, ordinal in ipairs(continuation_ordinals or {}) do
            continuations[#continuations + 1] = Support.stencil_continuation_signature(ordinal, {})
        end
        return Support.spill_all_stencil_signature(scalar, operands, continuations)
    end

    local function manifest_entry_for_source_facts(id_text, family, chunk_class, signature, extraction, holes, continuation_ordinals, extra_relocation_kinds)
        local generator = generator_for_source(id_text, family, chunk_class)
        local configuration = configuration_for_source(id_text, generator)
        local hole_ordinals = hole_ordinals_for_layouts(id_text, holes or {})
        return Support.template_manifest_entry(
            source_id(id_text),
            family,
            generator,
            configuration,
            require_value(signature, "NativeStencilSignature"),
            require_value(extraction, "NativeTemplateExtraction"),
            hole_ordinals,
            continuation_ordinals or {},
            relocation_declarations(hole_ordinals, continuation_ordinals or {}, extra_relocation_kinds or {})
        )
    end

    function api.c_source_from_manifest_entry(entry, entry_symbol, c_text, holes)
        entry = require_value(entry, "NativeTemplateManifestEntry")
        return Native.NativeTemplateSource(
            entry.source,
            entry.family,
            entry.generator,
            entry.configuration,
            entry.signature,
            entry.extraction,
            require_value(entry_symbol, "entry symbol"),
            require_value(c_text, "C source text"),
            holes or {},
            entry.declared_hole_ordinals,
            entry.declared_continuation_ordinals,
            entry.declared_relocation_kinds
        )
    end

    function api.c_source(id_text, family, generator, configuration, signature, extraction, entry_symbol, c_text, holes, hole_ordinals, continuation_ordinals, relocation_kinds)
        return Native.NativeTemplateSource(
            source_id(id_text),
            require_value(family, "NativeTemplateFamily"),
            require_value(generator, "NativeStencilGenerator"),
            require_value(configuration, "NativeStencilConfiguration"),
            require_value(signature, "NativeStencilSignature"),
            require_value(extraction, "NativeTemplateExtraction"),
            require_value(entry_symbol, "entry symbol"),
            require_value(c_text, "C source text"),
            holes or {},
            hole_ordinals or {},
            continuation_ordinals or {},
            relocation_kinds or {}
        )
    end

    local function manifest_entries(manifest)
        local out = {}
        for _, group in ipairs((manifest and manifest.groups) or {}) do
            for _, entry in ipairs(group.entries or {}) do out[#out + 1] = entry end
        end
        return out
    end

    local function source_manifest_entry_key(entry)
        return entry.source.text
    end

    function api.assert_manifest_matches_sources(manifest, sources)
        sources = sources or {}
        local entries = manifest_entries(require_value(manifest, "NativeTemplateSourceManifest"))
        if manifest.total_count ~= #entries then internal_error("manifest total_count does not equal manifest entries") end
        if #sources ~= #entries then internal_error("source count " .. tostring(#sources) .. " does not match manifest total_count " .. tostring(#entries)) end
        local by_source = {}
        for _, entry in ipairs(entries) do
            local key = source_manifest_entry_key(entry)
            if by_source[key] ~= nil then internal_error("duplicate manifest source id: " .. tostring(key)) end
            by_source[key] = entry
        end
        for _, source in ipairs(sources) do
            local entry = by_source[source.id.text]
            if entry == nil then internal_error("source not declared by manifest: " .. tostring(source.id.text)) end
            if source.family ~= entry.family then internal_error("source family does not match manifest for " .. source.id.text) end
            if source.generator ~= entry.generator then internal_error("source generator does not match manifest for " .. source.id.text) end
            if source.configuration ~= entry.configuration then internal_error("source configuration does not match manifest for " .. source.id.text) end
            if source.signature ~= entry.signature then internal_error("source signature does not match manifest for " .. source.id.text) end
            if source.extraction ~= entry.extraction then internal_error("source extraction does not match manifest for " .. source.id.text) end
            if #(source.declared_hole_ordinals or {}) ~= #(entry.declared_hole_ordinals or {}) then internal_error("source hole ordinal count does not match manifest for " .. source.id.text) end
            if #(source.declared_continuation_ordinals or {}) ~= #(entry.declared_continuation_ordinals or {}) then internal_error("source continuation ordinal count does not match manifest for " .. source.id.text) end
            if #(source.declared_relocation_kinds or {}) ~= #(entry.declared_relocation_kinds or {}) then internal_error("source relocation declaration count does not match manifest for " .. source.id.text) end
        end
        return true
    end

    function api.bank_request_from_sources(bank_id, target, runtime, manifest, sources)
        api.assert_unique_source_ids(sources or {})
        api.assert_unique_family_ids(sources or {})
        api.assert_manifest_matches_sources(manifest, sources or {})
        return Native.NativeTemplateBankRequest(
            require_value(bank_id, "NativeBankId"),
            require_value(target, "NativeTarget"),
            require_value(runtime, "NativeRuntime"),
            require_value(manifest, "NativeTemplateSourceManifest"),
            sources or {}
        )
    end

    local function require_x64_sysv_target(target)
        target = require_value(target, "NativeTarget")
        if not asdl.isa(target.arch, Native.NativeArchX64)
            or not asdl.isa(target.abi, Native.NativeAbiSysV)
            or not asdl.isa(target.endian, Native.NativeLittleEndian)
            or target.pointer_bits ~= 64 then
            internal_error("native scalar template sources are currently authored for x64/sysv/little-endian/64-bit support")
        end
        return target
    end

    local function int_wrap_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
    end

    local function float_mode()
        return Code.CodeFloatStrict
    end

    local function c_int_type(bits, signedness)
        local prefix = signedness == Code.CodeSigned and "int" or "uint"
        return prefix .. tostring(bits) .. "_t"
    end

    local function c_uint_type(bits)
        return "uint" .. tostring(bits) .. "_t"
    end

    function Code.CodeTyBool8:native_c_scalar_type()
        return "uint8_t"
    end

    function Code.CodeTyInt:native_c_scalar_type()
        return c_int_type(self.bits, self.signedness)
    end

    function Code.CodeTyIndex:native_c_scalar_type()
        return "intptr_t"
    end

    function Code.CodeTyDataPtr:native_c_scalar_type()
        return "uintptr_t"
    end

    function Code.CodeTyFloat:native_c_scalar_type()
        if self.bits == 32 then return "float" end
        return "double"
    end

    function Code.CodeType:native_source_type_token()
        internal_error("Code type does not have a finite native source type token")
    end

    function Code.CodeTyBool8:native_source_type_token() return "bool8" end
    function Code.CodeTyInt:native_source_type_token()
        local prefix = self.signedness == Code.CodeSigned and "i" or "u"
        return prefix .. tostring(self.bits)
    end
    function Code.CodeTyIndex:native_source_type_token() return "index" end
    function Code.CodeTyDataPtr:native_source_type_token() return "ptr" end
    function Code.CodeTyFloat:native_source_type_token() return "f" .. tostring(self.bits) end

    function Native.NativeScalarBool8:native_c_scalar_type()
        return "uint8_t"
    end

    function Native.NativeScalarInt:native_c_scalar_type()
        return c_int_type(self.bits, self.signedness)
    end

    function Native.NativeScalarIndex:native_c_scalar_type()
        return "intptr_t"
    end

    function Native.NativeScalarPointer:native_c_scalar_type()
        return "uintptr_t"
    end

    function Native.NativeScalarFloat:native_c_scalar_type()
        if self.bits == 32 then return "float" end
        return "double"
    end

    function Native.NativeScalarBool8:native_c_unsigned_type()
        return "uint8_t"
    end

    function Native.NativeScalarInt:native_c_unsigned_type()
        return c_uint_type(self.bits)
    end

    function Native.NativeScalarIndex:native_c_unsigned_type()
        return "uintptr_t"
    end

    function Native.NativeScalarPointer:native_c_unsigned_type()
        return "uintptr_t"
    end

    function Native.NativeScalarFloat:native_c_unsigned_type()
        return nil
    end

    function Native.NativeScalarBool8:native_size_bytes() return 1 end
    function Native.NativeScalarInt:native_size_bytes() return self.bits / 8 end
    function Native.NativeScalarIndex:native_size_bytes() return self.bits / 8 end
    function Native.NativeScalarPointer:native_size_bytes() return self.bits / 8 end
    function Native.NativeScalarFloat:native_size_bytes() return self.bits / 8 end

    function Native.NativeMachineScalarRep:native_frame_alignment()
        local size = self:native_size_bytes()
        if size > 8 then return 8 end
        if size < 1 then return 1 end
        return size
    end

    local function hole_c_symbol(id)
        return "lalin_native_hole_" .. tostring(id):gsub("[^%w_]", "_")
    end

    local function frame_offset_hole(id)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            hole_c_symbol(id),
            -1,
            4,
            Native.NativePatchFrameOffset32
        )
    end

    local function imm32_hole(id)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            hole_c_symbol(id),
            -1,
            4,
            Native.NativePatchImm32
        )
    end

    local function imm64_hole(id)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            hole_c_symbol(id),
            -1,
            8,
            Native.NativePatchImm64
        )
    end

    local function ptr64_hole(id)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            hole_c_symbol(id),
            -1,
            8,
            Native.NativePatchPtr64
        )
    end

    local function call_rel32_hole(id)
        return Native.NativeHoleLayout(
            Native.NativePatchHoleId(id),
            hole_c_symbol(id),
            -1,
            4,
            Native.NativePatchCallRel32
        )
    end

    local function scalar_immediate_hole(id, scalar)
        if scalar.bits and scalar.bits > 32 then return imm64_hole(id .. ".imm64") end
        return imm32_hole(id .. ".imm32")
    end

    local function hole_address_expr(hole)
        return "((uintptr_t)&" .. hole.symbol .. ")"
    end

    local function frame_load(c_type, offset_expr)
        return "*(" .. c_type .. " *)(void *)(frame + " .. offset_expr .. ")"
    end

    local function frame_store(c_type, offset_expr, expr)
        return "    *(" .. c_type .. " *)(void *)(frame + " .. offset_expr .. ") = " .. expr .. ";"
    end

    local function append_hole_externs(lines, holes)
        for _, hole in ipairs(holes or {}) do
            if asdl.isa(hole.hole, Native.NativePatchCallRel32) then
                lines[#lines + 1] = "extern void " .. hole.symbol .. "(uint8_t *frame);"
            else
                lines[#lines + 1] = "extern const uint8_t " .. hole.symbol .. ";"
            end
        end
    end

    local function c_params_for_signature(signature)
        local params = { "uint8_t *frame" }
        for _, param in ipairs((signature and signature.params) or {}) do
            params[#params + 1] = param.scalar:native_c_scalar_type() .. " arg" .. tostring(param.index)
        end
        return params
    end

    local function continuation_extern(symbol, continuation_signature)
        return "extern void " .. symbol.name .. "(" .. table.concat(c_params_for_signature(continuation_signature), ", ") .. ");"
    end

    local function fragment_signature_params(signature)
        local params = { "uint8_t *frame" }
        for _, operand in ipairs((signature and signature.operands) or {}) do
            if asdl.isa(operand.location, Native.NativeStencilContinuationArgLocationClass) then
                params[#params + 1] = operand.scalar:native_c_scalar_type() .. " arg" .. tostring(operand.index)
            end
        end
        return params
    end

    function Native.NativeStencilValueLocationClass:native_edge_copy_source_holes(_id_base, _scalar)
        internal_error("unsupported edge-copy source location class")
    end

    function Native.NativeStencilFrameSlotLocationClass:native_edge_copy_source_holes(id_base, _scalar)
        return { frame_offset_hole(id_base .. ".src") }
    end

    function Native.NativeStencilContinuationArgLocationClass:native_edge_copy_source_holes(_id_base, _scalar)
        return {}
    end

    function Native.NativeStencilImmediateLocationClass:native_edge_copy_source_holes(id_base, scalar)
        return { scalar_immediate_hole(id_base .. ".src", scalar) }
    end

    function Native.NativeStencilConstantPoolLocationClass:native_edge_copy_source_holes(id_base, _scalar)
        return { ptr64_hole(id_base .. ".src.pool") }
    end

    function Native.NativeStencilValueLocationClass:native_edge_copy_dest_holes(_id_base, _scalar)
        internal_error("unsupported edge-copy destination location class")
    end

    function Native.NativeStencilFrameSlotLocationClass:native_edge_copy_dest_holes(id_base, _scalar)
        return { frame_offset_hole(id_base .. ".dst") }
    end

    function Native.NativeStencilContinuationArgLocationClass:native_edge_copy_dest_holes(_id_base, _scalar)
        return {}
    end

    function Native.NativeStencilValueLocationClass:native_edge_copy_source_expr(_scalar, _holes)
        internal_error("unsupported edge-copy source expression location class")
    end

    function Native.NativeStencilFrameSlotLocationClass:native_edge_copy_source_expr(scalar, holes)
        return frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1]))
    end

    function Native.NativeStencilContinuationArgLocationClass:native_edge_copy_source_expr(_scalar, _holes)
        return "arg0"
    end

    function Native.NativeStencilImmediateLocationClass:native_edge_copy_source_expr(scalar, holes)
        return "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(holes[1])
    end

    function Native.NativeStencilConstantPoolLocationClass:native_edge_copy_source_expr(scalar, holes)
        return "*(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)" .. hole_address_expr(holes[1])
    end

    function Native.NativeStencilValueLocationClass:native_edge_copy_dest_store(_scalar, _holes, _value_expr)
        internal_error("unsupported edge-copy destination store location class")
    end

    function Native.NativeStencilFrameSlotLocationClass:native_edge_copy_dest_store(scalar, holes, value_expr)
        return frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[1]), value_expr)
    end

    function Native.NativeStencilContinuationArgLocationClass:native_edge_copy_dest_store(_scalar, _holes, _value_expr)
        return nil
    end

    function Native.NativeStencilValueLocationClass:native_edge_copy_next_args(_value_expr)
        return {}
    end

    function Native.NativeStencilContinuationArgLocationClass:native_edge_copy_next_args(value_expr)
        return { value_expr }
    end

    function Native.NativeConstantPoolEntryKind:native_constant_pool_kind_token(_target)
        internal_error("unsupported native constant-pool entry kind")
    end

    function Native.NativeConstantPoolScalarConst:native_constant_pool_kind_token(_target)
        return "scalar." .. self.scalar:native_scalar_token()
    end

    function Native.NativeConstantPoolPointerConst:native_constant_pool_kind_token(target)
        return "ptr" .. tostring(target.pointer_bits)
    end

    function Native.NativeConstantPoolBytes:native_constant_pool_kind_token(_target)
        return "bytes." .. tostring(self.size) .. ".align" .. tostring(self.alignment)
    end

    function Native.NativeConstantPoolEntryKind:native_constant_load_scalar(_target)
        internal_error("unsupported native constant-pool load kind")
    end

    function Native.NativeConstantPoolScalarConst:native_constant_load_scalar(_target)
        return self.scalar
    end

    function Native.NativeConstantPoolPointerConst:native_constant_load_scalar(target)
        return Support.scalar_pointer(target.pointer_bits)
    end

    function Native.NativeConstantPoolBytes:native_constant_load_scalar(target)
        return Support.scalar_pointer(target.pointer_bits)
    end

    function Native.NativeConstantPoolEntryKind:native_constant_load_expr(_scalar, _hole)
        internal_error("unsupported native constant-pool load expression")
    end

    function Native.NativeConstantPoolScalarConst:native_constant_load_expr(scalar, hole)
        return "*(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)" .. hole_address_expr(hole)
    end

    function Native.NativeConstantPoolPointerConst:native_constant_load_expr(scalar, hole)
        return "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(hole)
    end

    function Native.NativeConstantPoolBytes:native_constant_load_expr(scalar, hole)
        return "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(hole)
    end

    function Native.NativeAbiProjection:native_c_boundary_type()
        internal_error("unsupported native ABI projection in C source builder")
    end

    function Native.NativeAbiVoidResult:native_c_boundary_type() return "void" end
    function Native.NativeAbiScalarValue:native_c_boundary_type() return self.scalar:native_c_scalar_type() end
    function Native.NativeAbiPointerValue:native_c_boundary_type() return "void *" end
    function Native.NativeAbiDescriptorValue:native_c_boundary_type() return "struct lalin_native_abi_descriptor_" .. symbol_fragment(self:native_projection_token()) end
    function Native.NativeAbiByRefValue:native_c_boundary_type() return "void *" end
    function Native.NativeAbiSRetResult:native_c_boundary_type() return "void" end

    function Native.NativeAbiProjection:native_projection_token(_target)
        internal_error("unsupported native ABI projection token")
    end

    function Native.NativeAbiVoidResult:native_projection_token(_target) return "void" end
    function Native.NativeAbiScalarValue:native_projection_token(_target) return self.scalar:native_scalar_token() end
    function Native.NativeAbiPointerValue:native_projection_token(_target) return "ptr" .. tostring(self.scalar.bits) end
    function Native.NativeAbiDescriptorValue:native_projection_token(_target) return "desc." .. symbol_fragment(self.layout.name or "layout") .. "." .. tostring(self.layout.size) .. "." .. tostring(self.layout.align or self.layout.alignment or 1) end
    function Native.NativeAbiByRefValue:native_projection_token(_target) return "byref" .. tostring(self.alignment) end
    function Native.NativeAbiSRetResult:native_projection_token(target) return "sret." .. self.pointer_param.abi:native_projection_token(target) end

    function Native.NativeAbiProjection:native_frame_c_type(_target)
        internal_error("unsupported native ABI projection frame type")
    end

    function Native.NativeAbiScalarValue:native_frame_c_type(_target) return self.scalar:native_c_scalar_type() end
    function Native.NativeAbiPointerValue:native_frame_c_type(_target) return "uintptr_t" end
    function Native.NativeAbiDescriptorValue:native_frame_c_type(_target) return self:native_c_boundary_type() end
    function Native.NativeAbiByRefValue:native_frame_c_type(_target) return "uintptr_t" end

    function Native.NativeAbiProjection:native_store_param_to_frame(_target, _hole, _param_name)
        internal_error("unsupported native ABI parameter frame store")
    end

    function Native.NativeAbiScalarValue:native_store_param_to_frame(target, hole, param_name)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(" .. self:native_frame_c_type(target) .. ")" .. param_name)
    end

    function Native.NativeAbiPointerValue:native_store_param_to_frame(target, hole, param_name)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(uintptr_t)" .. param_name)
    end

    function Native.NativeAbiByRefValue:native_store_param_to_frame(target, hole, param_name)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(uintptr_t)" .. param_name)
    end

    function Native.NativeAbiDescriptorValue:native_store_param_to_frame(_target, hole, param_name)
        return "    __builtin_memcpy(frame + (uintptr_t)&" .. hole.symbol .. ", &" .. param_name .. ", " .. tostring(self.layout.size) .. ");"
    end

    function Native.NativeAbiProjection:native_load_arg_from_frame(_target, _hole)
        internal_error("unsupported native ABI argument frame load")
    end

    function Native.NativeAbiScalarValue:native_load_arg_from_frame(target, hole)
        return frame_load(self:native_frame_c_type(target), hole_address_expr(hole))
    end

    function Native.NativeAbiPointerValue:native_load_arg_from_frame(target, hole)
        return "(void *)(uintptr_t)" .. frame_load(self:native_frame_c_type(target), hole_address_expr(hole))
    end

    function Native.NativeAbiByRefValue:native_load_arg_from_frame(target, hole)
        return "(void *)(uintptr_t)" .. frame_load(self:native_frame_c_type(target), hole_address_expr(hole))
    end

    function Native.NativeAbiDescriptorValue:native_load_arg_from_frame(target, hole)
        return "*(" .. self:native_frame_c_type(target) .. " *)(void *)(frame + (uintptr_t)&" .. hole.symbol .. ")"
    end

    function Native.NativeAbiProjection:native_store_result_to_frame(_target, _hole, _expr)
        internal_error("unsupported native ABI result frame store")
    end

    function Native.NativeAbiScalarValue:native_store_result_to_frame(target, hole, expr)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(" .. self:native_frame_c_type(target) .. ")(" .. expr .. ")")
    end

    function Native.NativeAbiPointerValue:native_store_result_to_frame(target, hole, expr)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(uintptr_t)(" .. expr .. ")")
    end

    function Native.NativeAbiByRefValue:native_store_result_to_frame(target, hole, expr)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(uintptr_t)(" .. expr .. ")")
    end

    function Native.NativeAbiDescriptorValue:native_store_result_to_frame(_target, hole, expr)
        return "    __builtin_memcpy(frame + (uintptr_t)&" .. hole.symbol .. ", &(" .. expr .. "), " .. tostring(self.layout.size) .. ");"
    end

    function Native.NativeAbiProjection:native_return_from_frame(_target, _hole)
        internal_error("unsupported native ABI return frame load")
    end

    function Native.NativeAbiScalarValue:native_return_from_frame(target, hole)
        return frame_load(self:native_frame_c_type(target), hole_address_expr(hole))
    end

    function Native.NativeAbiPointerValue:native_return_from_frame(target, hole)
        return "(void *)(uintptr_t)" .. frame_load(self:native_frame_c_type(target), hole_address_expr(hole))
    end

    function Native.NativeAbiByRefValue:native_return_from_frame(target, hole)
        return "(void *)(uintptr_t)" .. frame_load(self:native_frame_c_type(target), hole_address_expr(hole))
    end

    function Native.NativeAbiDescriptorValue:native_return_from_frame(target, hole)
        return "*(" .. self:native_frame_c_type(target) .. " *)(void *)(frame + (uintptr_t)&" .. hole.symbol .. ")"
    end

    function Native.NativeAbiProjection:append_native_c_declarations(_lines, _seen)
        return nil
    end

    function Native.NativeAbiDescriptorValue:append_native_c_declarations(lines, seen)
        seen = seen or {}
        local ty = self:native_c_boundary_type()
        if seen[ty] then return end
        seen[ty] = true
        lines[#lines + 1] = ty .. " {"
        for _, field in ipairs(self.fields or {}) do
            lines[#lines + 1] = "    " .. field.value:native_frame_c_type() .. " " .. symbol_fragment(field.field_name) .. ";"
        end
        lines[#lines + 1] = "};"
    end

    function Native.NativeAbiFunctionProjection:append_native_c_declarations(lines)
        local seen = {}
        self.result.abi:append_native_c_declarations(lines, seen)
        for _, param in ipairs(self.params or {}) do param.abi:append_native_c_declarations(lines, seen) end
    end

    function Native.NativeAbiFunctionProjection:native_projection_token()
        local params = {}
        for _, param in ipairs(self.params or {}) do
            params[#params + 1] = param.abi:native_projection_token(self.target)
        end
        return "p" .. table.concat(params, "_") .. ".r" .. self.result.abi:native_projection_token(self.target)
    end

    function Native.NativeAbiFunctionProjection:native_c_function_declaration(name)
        local params = {}
        for _, param in ipairs(self.params or {}) do
            params[#params + 1] = param.abi:native_c_boundary_type() .. " p" .. tostring(param.param_index)
        end
        if #params == 0 then params[#params + 1] = "void" end
        return self.result.abi:native_c_boundary_type() .. " " .. name .. "(" .. table.concat(params, ", ") .. ")"
    end

    function Native.NativeAbiFunctionProjection:native_c_function_pointer_typedef(name)
        local params = {}
        for _, param in ipairs(self.params or {}) do
            params[#params + 1] = param.abi:native_c_boundary_type()
        end
        if #params == 0 then params[#params + 1] = "void" end
        return "typedef " .. self.result.abi:native_c_boundary_type() .. " (*" .. name .. ")(" .. table.concat(params, ", ") .. ");"
    end

    function Native.NativeAbiFunctionProjection:native_has_no_params()
        return #(self.params or {}) == 0
    end

    function Native.NativeAbiFunctionProjection:native_result_is_void()
        return asdl.isa(self.result.abi, Native.NativeAbiVoidResult) or asdl.isa(self.result.abi, Native.NativeAbiSRetResult)
    end

    function Native.NativeCodeResultShape:native_result_shape_token()
        internal_error("unsupported native Code result shape token")
    end

    function Native.NativeCodeResultVoidShape:native_result_shape_token() return "void" end
    function Native.NativeCodeResultScalarShape:native_result_shape_token() return self.scalar:native_scalar_token() end
    function Native.NativeCodeResultPointerShape:native_result_shape_token() return "ptr" .. tostring(self.scalar.bits) end
    function Native.NativeCodeResultDescriptorShape:native_result_shape_token() return "descriptor." .. symbol_fragment(self.layout.name or "layout") .. "." .. tostring(self.layout.size) end
    function Native.NativeCodeResultByRefShape:native_result_shape_token() return "byref" .. tostring(self.alignment) end
    function Native.NativeCodeResultSRetShape:native_result_shape_token() return "sret." .. symbol_fragment(self.result_ty:native_source_type_token()) end

    function Native.NativeCodeResultShape:native_result_copy_size(_target)
        internal_error("unsupported native Code result copy size")
    end

    function Native.NativeCodeResultScalarShape:native_result_copy_size(_target) return self.scalar:native_size_bytes() end
    function Native.NativeCodeResultPointerShape:native_result_copy_size(target) return target.pointer_bits / 8 end
    function Native.NativeCodeResultDescriptorShape:native_result_copy_size(_target) return self.layout.size end
    function Native.NativeCodeResultByRefShape:native_result_copy_size(target) return target.pointer_bits / 8 end

    function Native.NativeCodeResultShape:native_result_family_scalar(target)
        return Support.scalar_bool8(target and target.pointer_bits or nil)
    end

    function Native.NativeCodeResultScalarShape:native_result_family_scalar(_target) return self.scalar end
    function Native.NativeCodeResultPointerShape:native_result_family_scalar(_target) return self.scalar end
    function Native.NativeCodeResultByRefShape:native_result_family_scalar(target) return Support.scalar_pointer(target.pointer_bits) end

    function Core.BinAdd:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")((" .. u .. ")(" .. lhs .. ") + (" .. u .. ")(" .. rhs .. "))", "add"
    end

    function Core.BinSub:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")((" .. u .. ")(" .. lhs .. ") - (" .. u .. ")(" .. rhs .. "))", "sub"
    end

    function Core.BinMul:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")((" .. u .. ")(" .. lhs .. ") * (" .. u .. ")(" .. rhs .. "))", "mul"
    end

    function Core.BinBitAnd:native_integer_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " & " .. rhs .. ")", "and" end
    function Core.BinBitOr:native_integer_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " | " .. rhs .. ")", "or" end
    function Core.BinBitXor:native_integer_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " ^ " .. rhs .. ")", "xor" end

    function Core.BinShl:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local mask = tostring(scalar.bits - 1)
        return "(" .. scalar:native_c_scalar_type() .. ")((" .. u .. ")(" .. lhs .. ") << ((" .. u .. ")(" .. rhs .. ") & " .. mask .. "))", "shl"
    end

    function Core.BinLShr:native_integer_c_expr(scalar, lhs, rhs)
        local u = scalar:native_c_unsigned_type()
        local mask = tostring(scalar.bits - 1)
        return "(" .. scalar:native_c_scalar_type() .. ")((" .. u .. ")(" .. lhs .. ") >> ((" .. u .. ")(" .. rhs .. ") & " .. mask .. "))", "lshr"
    end

    function Core.BinAShr:native_integer_c_expr(scalar, lhs, rhs)
        local mask = tostring(scalar.bits - 1)
        return "(" .. lhs .. " >> (" .. rhs .. " & " .. mask .. "))", "ashr"
    end

    function Core.BinAdd:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " + " .. rhs .. ")", "add" end
    function Core.BinSub:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " - " .. rhs .. ")", "sub" end
    function Core.BinMul:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " * " .. rhs .. ")", "mul" end
    function Core.BinDiv:native_float_c_expr(_scalar, lhs, rhs) return "(" .. lhs .. " / " .. rhs .. ")", "div" end

    function Core.UnaryNeg:native_integer_c_expr(scalar, value)
        local u = scalar:native_c_unsigned_type()
        local c = scalar:native_c_scalar_type()
        return "(" .. c .. ")(-(" .. u .. ")(" .. value .. "))", "neg"
    end

    function Core.UnaryBitNot:native_integer_c_expr(_scalar, value)
        return "(~" .. value .. ")", "bitnot"
    end

    function Core.UnaryNot:native_integer_c_expr(_scalar, value)
        return "(" .. value .. " == 0)", "not"
    end

    function Core.CmpEq:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " == " .. rhs .. ")", "eq" end
    function Core.CmpNe:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " != " .. rhs .. ")", "ne" end
    function Core.CmpLt:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " < " .. rhs .. ")", "lt" end
    function Core.CmpLe:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " <= " .. rhs .. ")", "le" end
    function Core.CmpGt:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " > " .. rhs .. ")", "gt" end
    function Core.CmpGe:native_c_compare_expr(_scalar, lhs, rhs) return "(" .. lhs .. " >= " .. rhs .. ")", "ge" end

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

    function Native.NativeMachineScalarRep:native_cast_is_float() return false end
    function Native.NativeScalarFloat:native_cast_is_float() return true end

    function Native.NativeMachineScalarRep:native_cast_is_integer_like() return false end
    function Native.NativeScalarBool8:native_cast_is_integer_like() return true end
    function Native.NativeScalarInt:native_cast_is_integer_like() return true end
    function Native.NativeScalarIndex:native_cast_is_integer_like() return true end
    function Native.NativeScalarPointer:native_cast_is_integer_like() return true end

    function Native.NativeMachineScalarRep:native_cast_is_signed_integer() return false end
    function Native.NativeScalarInt:native_cast_is_signed_integer() return self.signedness == Code.CodeSigned end
    function Native.NativeScalarIndex:native_cast_is_signed_integer() return true end

    function Native.NativeMachineScalarRep:native_cast_min_expr() return "0" end
    function Native.NativeScalarInt:native_cast_min_expr()
        if self.signedness == Code.CodeSigned then return "INT" .. tostring(self.bits) .. "_MIN" end
        return "0"
    end
    function Native.NativeScalarIndex:native_cast_min_expr() return "INTPTR_MIN" end

    function Native.NativeScalarBool8:native_cast_max_expr() return "UINT8_MAX" end
    function Native.NativeScalarInt:native_cast_max_expr()
        local prefix = self.signedness == Code.CodeSigned and "INT" or "UINT"
        return prefix .. tostring(self.bits) .. "_MAX"
    end
    function Native.NativeScalarIndex:native_cast_max_expr() return "INTPTR_MAX" end
    function Native.NativeScalarPointer:native_cast_max_expr() return "UINTPTR_MAX" end

    function Core.MachineCastOp:append_native_cast_c_lines(_lines, _from_scalar, _to_scalar, _src_name, _dst_name)
        internal_error("unsupported machine cast op in native C source builder")
    end

    function Core.MachineCastOp:native_cast_extra_relocation_kinds()
        return {}
    end

    function Core.MachineCastOp:native_cast_source_qualifier()
        return ""
    end

    function Core.MachineCastSToF:native_cast_source_qualifier()
        return "volatile "
    end

    function Core.MachineCastUToF:native_cast_source_qualifier()
        return "volatile "
    end

    function Core.MachineCastSToF:native_cast_extra_relocation_kinds()
        return { Native.NativeTemplateRelocationConstantPool }
    end

    function Core.MachineCastUToF:native_cast_extra_relocation_kinds()
        return { Native.NativeTemplateRelocationConstantPool }
    end

    function Core.MachineCastFToS:native_cast_extra_relocation_kinds()
        return { Native.NativeTemplateRelocationConstantPool }
    end

    function Core.MachineCastFToU:native_cast_extra_relocation_kinds()
        return { Native.NativeTemplateRelocationConstantPool }
    end

    local function append_simple_cast(lines, to_scalar, src_name, dst_name, expr)
        lines[#lines + 1] = "    " .. to_scalar:native_c_scalar_type() .. " " .. dst_name .. " = " .. expr .. ";"
    end

    function Core.MachineCastIdentity:append_native_cast_c_lines(lines, _from_scalar, to_scalar, src_name, dst_name)
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")" .. src_name)
    end

    function Core.MachineCastIreduce:append_native_cast_c_lines(lines, from_scalar, to_scalar, src_name, dst_name)
        local from_unsigned = from_scalar:native_c_unsigned_type()
        local to_unsigned = to_scalar:native_c_unsigned_type()
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")((" .. to_unsigned .. ")(" .. from_unsigned .. ")" .. src_name .. ")")
    end

    function Core.MachineCastSextend:append_native_cast_c_lines(lines, from_scalar, to_scalar, src_name, dst_name)
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")(" .. from_scalar:native_c_scalar_type() .. ")" .. src_name)
    end

    function Core.MachineCastUextend:append_native_cast_c_lines(lines, from_scalar, to_scalar, src_name, dst_name)
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")(" .. from_scalar:native_c_unsigned_type() .. ")" .. src_name)
    end

    function Core.MachineCastBitcast:append_native_cast_c_lines(lines, from_scalar, to_scalar, src_name, dst_name)
        lines[#lines + 1] = "    " .. to_scalar:native_c_scalar_type() .. " " .. dst_name .. ";"
        lines[#lines + 1] = "    unsigned char *native_cast_dst = (unsigned char *)(void *)&" .. dst_name .. ";"
        lines[#lines + 1] = "    const unsigned char *native_cast_src = (const unsigned char *)(const void *)&" .. src_name .. ";"
        lines[#lines + 1] = "    for (size_t native_cast_i = 0; native_cast_i < sizeof(" .. dst_name .. "); ++native_cast_i) { native_cast_dst[native_cast_i] = 0; }"
        lines[#lines + 1] = "    for (size_t native_cast_i = 0; native_cast_i < (sizeof(" .. dst_name .. ") < sizeof(" .. src_name .. ") ? sizeof(" .. dst_name .. ") : sizeof(" .. src_name .. ")); ++native_cast_i) { native_cast_dst[native_cast_i] = native_cast_src[native_cast_i]; }"
    end

    function Core.MachineCastFpromote:append_native_cast_c_lines(lines, _from_scalar, to_scalar, src_name, dst_name)
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")" .. src_name)
    end

    function Core.MachineCastFdemote:append_native_cast_c_lines(lines, _from_scalar, to_scalar, src_name, dst_name)
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")" .. src_name)
    end

    function Core.MachineCastSToF:append_native_cast_c_lines(lines, _from_scalar, to_scalar, src_name, dst_name)
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")((long double)" .. src_name .. ")")
    end

    function Core.MachineCastUToF:append_native_cast_c_lines(lines, from_scalar, to_scalar, src_name, dst_name)
        append_simple_cast(lines, to_scalar, src_name, dst_name, "(" .. to_scalar:native_c_scalar_type() .. ")((long double)(" .. from_scalar:native_c_unsigned_type() .. ")" .. src_name .. ")")
    end

    local function append_float_to_integer_cast(lines, to_scalar, src_name, dst_name)
        local c_type = to_scalar:native_c_scalar_type()
        lines[#lines + 1] = "    long double native_cast_value = (long double)" .. src_name .. ";"
        lines[#lines + 1] = "    " .. c_type .. " " .. dst_name .. ";"
        lines[#lines + 1] = "    if (!(native_cast_value == native_cast_value)) {"
        lines[#lines + 1] = "        " .. dst_name .. " = (" .. c_type .. ")0;"
        lines[#lines + 1] = "    } else if (native_cast_value <= (long double)(" .. to_scalar:native_cast_min_expr() .. ")) {"
        lines[#lines + 1] = "        " .. dst_name .. " = (" .. c_type .. ")(" .. to_scalar:native_cast_min_expr() .. ");"
        lines[#lines + 1] = "    } else if (native_cast_value >= (long double)(" .. to_scalar:native_cast_max_expr() .. ")) {"
        lines[#lines + 1] = "        " .. dst_name .. " = (" .. c_type .. ")(" .. to_scalar:native_cast_max_expr() .. ");"
        lines[#lines + 1] = "    } else {"
        lines[#lines + 1] = "        " .. dst_name .. " = (" .. c_type .. ")native_cast_value;"
        lines[#lines + 1] = "    }"
    end

    function Core.MachineCastFToS:append_native_cast_c_lines(lines, _from_scalar, to_scalar, src_name, dst_name)
        append_float_to_integer_cast(lines, to_scalar, src_name, dst_name)
    end

    function Core.MachineCastFToU:append_native_cast_c_lines(lines, _from_scalar, to_scalar, src_name, dst_name)
        append_float_to_integer_cast(lines, to_scalar, src_name, dst_name)
    end

    function Native.NativeMachineScalarRep:native_cast_op_to(to_scalar)
        if self == to_scalar then return Core.MachineCastIdentity end
        if self:native_cast_is_float() then
            if to_scalar:native_cast_is_float() then
                if self.bits < to_scalar.bits then return Core.MachineCastFpromote end
                if self.bits > to_scalar.bits then return Core.MachineCastFdemote end
                return Core.MachineCastBitcast
            end
            if to_scalar:native_cast_is_integer_like() then
                return to_scalar:native_cast_is_signed_integer() and Core.MachineCastFToS or Core.MachineCastFToU
            end
        elseif self:native_cast_is_integer_like() then
            if to_scalar:native_cast_is_float() then
                return self:native_cast_is_signed_integer() and Core.MachineCastSToF or Core.MachineCastUToF
            end
            if to_scalar:native_cast_is_integer_like() then
                if self:native_size_bytes() > to_scalar:native_size_bytes() then return Core.MachineCastIreduce end
                if self:native_size_bytes() < to_scalar:native_size_bytes() then
                    return self:native_cast_is_signed_integer() and Core.MachineCastSextend or Core.MachineCastUextend
                end
                return Core.MachineCastBitcast
            end
        end
        return nil
    end

    local function append_manifest_source(out, id_text, family, chunk_class, signature, extraction, entry_symbol, lines, holes, continuation_ordinals, extra_relocation_kinds)
        local manifest_entry = manifest_entry_for_source_facts(id_text, family, chunk_class, signature, extraction, holes or {}, continuation_ordinals or {}, extra_relocation_kinds or {})
        return api.append_source(out, api.c_source_from_manifest_entry(manifest_entry, entry_symbol, concat_lines(lines), holes or {}))
    end

    function Core.UnaryOp:native_float_c_expr(_scalar, _value)
        internal_error("unsupported float unary op in native fast region source builder")
    end

    function Core.UnaryNeg:native_float_c_expr(_scalar, value)
        return "(-" .. value .. ")", "neg"
    end

    function Native.NativeMachineScalarRep:native_fast_unary_c_expr(op, value)
        return op:native_integer_c_expr(self, value)
    end

    function Native.NativeScalarFloat:native_fast_unary_c_expr(op, value)
        return op:native_float_c_expr(self, value)
    end

    function Native.NativeMachineScalarRep:native_fast_binary_c_expr(op, lhs, rhs)
        return op:native_integer_c_expr(self, lhs, rhs)
    end

    function Native.NativeScalarFloat:native_fast_binary_c_expr(op, lhs, rhs)
        return op:native_float_c_expr(self, lhs, rhs)
    end

    function Native.NativeMachineScalarRep:native_fast_mul_add_imm_c_expr(lhs, rhs, imm)
        local mul = self:native_fast_binary_c_expr(Core.BinMul, lhs, rhs)
        return self:native_fast_binary_c_expr(Core.BinAdd, mul, imm)
    end

    function Native.NativeCodeExprAtomShape:native_fast_atom_token()
        internal_error("unsupported native fast expression atom token")
    end

    function Native.NativeExprInput:native_fast_atom_token()
        return "input" .. tostring(self.ordinal) .. "." .. self.scalar:native_scalar_token()
    end

    function Native.NativeExprImmediate:native_fast_atom_token()
        return "imm." .. self.scalar:native_scalar_token()
    end

    function Native.NativeExprConstPool:native_fast_atom_token()
        return "pool." .. self.scalar:native_scalar_token()
    end

    function Native.NativeCodeExprAtomShape:native_fast_atom_scalar()
        internal_error("unsupported native fast expression atom scalar")
    end

    function Native.NativeExprInput:native_fast_atom_scalar() return self.scalar end
    function Native.NativeExprImmediate:native_fast_atom_scalar() return self.scalar end
    function Native.NativeExprConstPool:native_fast_atom_scalar() return self.scalar end

    function Native.NativeCodeExprAtomShape:append_native_fast_atom_holes(_holes, _id_base)
        internal_error("unsupported native fast expression atom holes")
    end

    function Native.NativeExprInput:append_native_fast_atom_holes(holes, id_base)
        local hole = frame_offset_hole(id_base .. ".input" .. tostring(self.ordinal))
        holes[#holes + 1] = hole
        return { hole }
    end

    function Native.NativeExprImmediate:append_native_fast_atom_holes(holes, id_base)
        local hole = scalar_immediate_hole(id_base .. ".imm", self.scalar)
        holes[#holes + 1] = hole
        return { hole }
    end

    function Native.NativeExprConstPool:append_native_fast_atom_holes(holes, id_base)
        local hole = ptr64_hole(id_base .. ".pool")
        holes[#holes + 1] = hole
        return { hole }
    end

    function Native.NativeCodeExprAtomShape:append_native_fast_atom_operand(_operands, _operand_index)
        internal_error("unsupported native fast expression atom operand")
    end

    function Native.NativeExprInput:append_native_fast_atom_operand(operands, operand_index)
        operands[#operands + 1] = Support.stencil_operand(operand_index, self.scalar, Support.location_class_frame_slot())
    end

    function Native.NativeExprImmediate:append_native_fast_atom_operand(operands, operand_index)
        operands[#operands + 1] = Support.stencil_operand(operand_index, self.scalar, Support.location_class_immediate())
    end

    function Native.NativeExprConstPool:append_native_fast_atom_operand(operands, operand_index)
        operands[#operands + 1] = Support.stencil_operand(operand_index, self.scalar, Support.location_class_constant_pool())
    end

    function Native.NativeCodeExprAtomShape:native_fast_atom_c_expr(_holes)
        internal_error("unsupported native fast expression atom C expression")
    end

    function Native.NativeExprInput:native_fast_atom_c_expr(holes)
        return frame_load(self.scalar:native_c_scalar_type(), hole_address_expr(holes[1]))
    end

    function Native.NativeExprImmediate:native_fast_atom_c_expr(holes)
        return "(" .. self.scalar:native_c_scalar_type() .. ")" .. hole_address_expr(holes[1])
    end

    function Native.NativeExprConstPool:native_fast_atom_c_expr(holes)
        return "*(" .. self.scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)" .. hole_address_expr(holes[1])
    end

    function Native.NativeCodeExprRegionShape:native_fast_expr_token()
        internal_error("unsupported native fast Code expression region token")
    end

    function Native.NativeExprReturnAtom:native_fast_expr_token()
        return "return_atom." .. self.result:native_scalar_token() .. "." .. self.atom:native_fast_atom_token()
    end

    function Native.NativeExprReturnUnary:native_fast_expr_token()
        return "return_unary." .. self.result:native_scalar_token() .. "." .. self.op:native_unary_family_name() .. "." .. self.src:native_fast_atom_token()
    end

    function Native.NativeExprReturnBinary:native_fast_expr_token()
        return "return_binary." .. self.result:native_scalar_token() .. "." .. self.op:native_binary_family_name() .. "." .. self.lhs:native_fast_atom_token() .. "." .. self.rhs:native_fast_atom_token()
    end

    function Native.NativeExprReturnBinaryImmRhs:native_fast_expr_token()
        return "return_binary_imm_rhs." .. self.result:native_scalar_token() .. "." .. self.op:native_binary_family_name() .. "." .. self.lhs:native_fast_atom_token()
    end

    function Native.NativeExprReturnMulAddImm:native_fast_expr_token()
        return "return_mul_add_imm." .. self.result:native_scalar_token() .. "." .. self.mul_lhs:native_fast_atom_token() .. "." .. self.mul_rhs:native_fast_atom_token()
    end

    function Native.NativeCodeExprRegionShape:native_fast_expr_result_scalar()
        internal_error("unsupported native fast Code expression result scalar")
    end

    function Native.NativeExprReturnAtom:native_fast_expr_result_scalar() return self.result end
    function Native.NativeExprReturnUnary:native_fast_expr_result_scalar() return self.result end
    function Native.NativeExprReturnBinary:native_fast_expr_result_scalar() return self.result end
    function Native.NativeExprReturnBinaryImmRhs:native_fast_expr_result_scalar() return self.result end
    function Native.NativeExprReturnMulAddImm:native_fast_expr_result_scalar() return self.result end

    local function fast_code_expr_family(input, shape, token)
        return Native.NativeTemplateFamily(
            Native.NativeTemplateFamilyId("native.fast.code.expr." .. token),
            Native.NativeRoleCodeTerm,
            {
                Support.axis_target(input.target),
                Support.axis_machine_scalar(shape:native_fast_expr_result_scalar()),
                Support.axis_fast_code_expr(shape),
            },
            Support.protocol_void_none()
        )
    end

    local function append_fast_expr_atom(operands, holes, id_base, atom, operand_index)
        atom:append_native_fast_atom_operand(operands, operand_index)
        return atom:append_native_fast_atom_holes(holes, id_base)
    end

    local function append_fast_code_expr_source(out, input, shape, expr_builder)
        local token = shape:native_fast_expr_token()
        local result_scalar = shape:native_fast_expr_result_scalar()
        local holes = {}
        local operands = {}
        local atom_holes = expr_builder(operands, holes, "native.hole.fast.code.expr." .. token)
        local result_hole = frame_offset_hole("native.hole.fast.code.expr." .. token .. ".result")
        holes[#holes + 1] = result_hole
        operands[#operands + 1] = Support.stencil_operand(#operands, result_scalar, Support.location_class_frame_slot())
        local signature = Support.spill_all_stencil_signature(result_scalar, operands, {})
        local family = fast_code_expr_family(input, shape, token)
        local entry = "lalin_native_fast_code_expr_" .. symbol_fragment(token)
        local c_type = result_scalar:native_c_scalar_type()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " result = " .. shape:native_fast_expr_c_expr(atom_holes) .. ";"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(result_hole), "result")
        lines[#lines + 1] = "}"
        append_manifest_source(out, "fast.code.expr." .. token, family, Native.NativeChunkSupertemplate, signature, Native.NativeExtractFallthroughFragment, entry, lines, holes, {})
    end

    function Native.NativeCodeExprRegionShape:native_fast_expr_c_expr(_atom_holes)
        internal_error("unsupported native fast Code expression C expression")
    end

    function Native.NativeExprReturnAtom:append_native_template_sources(out, input)
        append_fast_code_expr_source(out, input, self, function(operands, holes, id_base)
            return { atom = append_fast_expr_atom(operands, holes, id_base .. ".atom", self.atom, 0) }
        end)
    end

    function Native.NativeExprReturnAtom:native_fast_expr_c_expr(atom_holes)
        return self.atom:native_fast_atom_c_expr(atom_holes.atom)
    end

    function Native.NativeExprReturnUnary:append_native_template_sources(out, input)
        append_fast_code_expr_source(out, input, self, function(operands, holes, id_base)
            return { src = append_fast_expr_atom(operands, holes, id_base .. ".src", self.src, 0) }
        end)
    end

    function Native.NativeExprReturnUnary:native_fast_expr_c_expr(atom_holes)
        local src = self.src:native_fast_atom_c_expr(atom_holes.src)
        return self.result:native_fast_unary_c_expr(self.op, src)
    end

    function Native.NativeExprReturnBinary:append_native_template_sources(out, input)
        append_fast_code_expr_source(out, input, self, function(operands, holes, id_base)
            return {
                lhs = append_fast_expr_atom(operands, holes, id_base .. ".lhs", self.lhs, 0),
                rhs = append_fast_expr_atom(operands, holes, id_base .. ".rhs", self.rhs, 1),
            }
        end)
    end

    function Native.NativeExprReturnBinary:native_fast_expr_c_expr(atom_holes)
        local lhs = self.lhs:native_fast_atom_c_expr(atom_holes.lhs)
        local rhs = self.rhs:native_fast_atom_c_expr(atom_holes.rhs)
        return self.result:native_fast_binary_c_expr(self.op, lhs, rhs)
    end

    function Native.NativeExprReturnBinaryImmRhs:append_native_template_sources(out, input)
        append_fast_code_expr_source(out, input, self, function(operands, holes, id_base)
            local imm = Native.NativeExprImmediate(self.result)
            return {
                lhs = append_fast_expr_atom(operands, holes, id_base .. ".lhs", self.lhs, 0),
                rhs = append_fast_expr_atom(operands, holes, id_base .. ".rhs", imm, 1),
            }
        end)
    end

    function Native.NativeExprReturnBinaryImmRhs:native_fast_expr_c_expr(atom_holes)
        local lhs = self.lhs:native_fast_atom_c_expr(atom_holes.lhs)
        local rhs = Native.NativeExprImmediate(self.result):native_fast_atom_c_expr(atom_holes.rhs)
        return self.result:native_fast_binary_c_expr(self.op, lhs, rhs)
    end

    function Native.NativeExprReturnMulAddImm:append_native_template_sources(out, input)
        append_fast_code_expr_source(out, input, self, function(operands, holes, id_base)
            local imm = Native.NativeExprImmediate(self.result)
            return {
                lhs = append_fast_expr_atom(operands, holes, id_base .. ".mul_lhs", self.mul_lhs, 0),
                rhs = append_fast_expr_atom(operands, holes, id_base .. ".mul_rhs", self.mul_rhs, 1),
                imm = append_fast_expr_atom(operands, holes, id_base .. ".imm", imm, 2),
            }
        end)
    end

    function Native.NativeExprReturnMulAddImm:native_fast_expr_c_expr(atom_holes)
        local lhs = self.mul_lhs:native_fast_atom_c_expr(atom_holes.lhs)
        local rhs = self.mul_rhs:native_fast_atom_c_expr(atom_holes.rhs)
        local imm = Native.NativeExprImmediate(self.result):native_fast_atom_c_expr(atom_holes.imm)
        return self.result:native_fast_mul_add_imm_c_expr(lhs, rhs, imm)
    end

    function Native.NativeCodeCompareShape:native_fast_compare_token()
        internal_error("unsupported native fast compare-branch token")
    end

    function Native.NativeCompareBranchAtoms:native_fast_compare_token()
        return "compare_branch." .. self.scalar:native_scalar_token() .. "." .. self.cmp:native_compare_family_name() .. "." .. self.lhs:native_fast_atom_token() .. "." .. self.rhs:native_fast_atom_token()
    end

    function Native.NativeCompareBranchImmRhs:native_fast_compare_token()
        return "compare_branch_imm_rhs." .. self.scalar:native_scalar_token() .. "." .. self.cmp:native_compare_family_name() .. "." .. self.lhs:native_fast_atom_token()
    end

    function Native.NativeCodeCompareShape:native_fast_compare_scalar()
        internal_error("unsupported native fast compare-branch scalar")
    end

    function Native.NativeCompareBranchAtoms:native_fast_compare_scalar() return self.scalar end
    function Native.NativeCompareBranchImmRhs:native_fast_compare_scalar() return self.scalar end

    local function fast_code_compare_family(input, shape, token)
        return Native.NativeTemplateFamily(
            Native.NativeTemplateFamilyId("native.fast.code.compare_branch." .. token),
            Native.NativeRoleCodeTerm,
            {
                Support.axis_target(input.target),
                Support.axis_machine_scalar(shape:native_fast_compare_scalar()),
                Support.axis_fast_code_compare_branch(shape),
            },
            Support.protocol_void_none()
        )
    end

    local function append_fast_code_compare_source(out, input, shape, atom_builder)
        local token = shape:native_fast_compare_token()
        local scalar = shape:native_fast_compare_scalar()
        local holes = {}
        local operands = {}
        local atom_holes = atom_builder(operands, holes, "native.hole.fast.code.compare_branch." .. token)
        local then_symbol, else_symbol = Support.then_continuation_symbol(), Support.else_continuation_symbol()
        local then_ordinal, else_ordinal = Support.then_continuation_ordinal(), Support.else_continuation_ordinal()
        local then_signature = Support.stencil_continuation_signature(then_ordinal, {})
        local else_signature = Support.stencil_continuation_signature(else_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, operands, { then_signature, else_signature })
        local family = fast_code_compare_family(input, shape, token)
        local entry = "lalin_native_fast_code_compare_branch_" .. symbol_fragment(token)
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(then_symbol, then_signature)
        lines[#lines + 1] = continuation_extern(else_symbol, else_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    if (" .. shape:native_fast_compare_c_expr(atom_holes) .. ") { " .. then_symbol.name .. "(frame); } else { " .. else_symbol.name .. "(frame); }"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "fast.code.compare_branch." .. token, family, Native.NativeChunkControlOp, signature, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), entry, lines, holes, { then_ordinal, else_ordinal })
    end

    function Native.NativeCodeCompareShape:native_fast_compare_c_expr(_atom_holes)
        internal_error("unsupported native fast compare-branch C expression")
    end

    function Native.NativeCompareBranchAtoms:append_native_template_sources(out, input)
        append_fast_code_compare_source(out, input, self, function(operands, holes, id_base)
            return {
                lhs = append_fast_expr_atom(operands, holes, id_base .. ".lhs", self.lhs, 0),
                rhs = append_fast_expr_atom(operands, holes, id_base .. ".rhs", self.rhs, 1),
            }
        end)
    end

    function Native.NativeCompareBranchAtoms:native_fast_compare_c_expr(atom_holes)
        local lhs = self.lhs:native_fast_atom_c_expr(atom_holes.lhs)
        local rhs = self.rhs:native_fast_atom_c_expr(atom_holes.rhs)
        return self.cmp:native_c_compare_expr(self.scalar, lhs, rhs)
    end

    function Native.NativeCompareBranchImmRhs:append_native_template_sources(out, input)
        append_fast_code_compare_source(out, input, self, function(operands, holes, id_base)
            local imm = Native.NativeExprImmediate(self.scalar)
            return {
                lhs = append_fast_expr_atom(operands, holes, id_base .. ".lhs", self.lhs, 0),
                rhs = append_fast_expr_atom(operands, holes, id_base .. ".rhs", imm, 1),
            }
        end)
    end

    function Native.NativeCompareBranchImmRhs:native_fast_compare_c_expr(atom_holes)
        local lhs = self.lhs:native_fast_atom_c_expr(atom_holes.lhs)
        local rhs = Native.NativeExprImmediate(self.scalar):native_fast_atom_c_expr(atom_holes.rhs)
        return self.cmp:native_c_compare_expr(self.scalar, lhs, rhs)
    end

    function Native.NativeCodeSwitchStepShape:native_fast_switch_step_token()
        internal_error("unsupported native fast switch-step token")
    end

    function Native.NativeSwitchStepAtoms:native_fast_switch_step_token()
        return "switch_step." .. self.scalar:native_scalar_token() .. "." .. self.key:native_fast_atom_token()
    end

    function Native.NativeSwitchStepImmKey:native_fast_switch_step_token()
        return "switch_step_imm_key." .. self.scalar:native_scalar_token()
    end

    function Native.NativeCodeSwitchStepShape:native_fast_switch_step_scalar()
        internal_error("unsupported native fast switch-step scalar")
    end

    function Native.NativeSwitchStepAtoms:native_fast_switch_step_scalar() return self.scalar end
    function Native.NativeSwitchStepImmKey:native_fast_switch_step_scalar() return self.scalar end

    local function fast_code_switch_step_family(input, shape, token)
        return Native.NativeTemplateFamily(
            Native.NativeTemplateFamilyId("native.fast.code.switch_step." .. token),
            Native.NativeRoleCodeTerm,
            {
                Support.axis_target(input.target),
                Support.axis_machine_scalar(shape:native_fast_switch_step_scalar()),
                Support.axis_fast_code_switch_step(shape),
            },
            Support.protocol_void_none()
        )
    end

    local function append_fast_code_switch_step_source(out, input, shape, atom_builder)
        local token = shape:native_fast_switch_step_token()
        local scalar = shape:native_fast_switch_step_scalar()
        local holes = {}
        local operands = {}
        local atom_holes = atom_builder(operands, holes, "native.hole.fast.code.switch_step." .. token)
        local case_atom = Native.NativeExprImmediate(scalar)
        local case_holes = append_fast_expr_atom(operands, holes, "native.hole.fast.code.switch_step." .. token .. ".case", case_atom, #operands)
        local case_symbol, default_symbol = Support.then_continuation_symbol(), Support.else_continuation_symbol()
        local case_ordinal, default_ordinal = Support.then_continuation_ordinal(), Support.else_continuation_ordinal()
        local case_signature = Support.stencil_continuation_signature(case_ordinal, {})
        local default_signature = Support.stencil_continuation_signature(default_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, operands, { case_signature, default_signature })
        local family = fast_code_switch_step_family(input, shape, token)
        local entry = "lalin_native_fast_code_switch_step_" .. symbol_fragment(token)
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(case_symbol, case_signature)
        lines[#lines + 1] = continuation_extern(default_symbol, default_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    if (" .. shape:native_fast_switch_step_key_c_expr(atom_holes) .. " == " .. case_atom:native_fast_atom_c_expr(case_holes) .. ") { " .. case_symbol.name .. "(frame); } else { " .. default_symbol.name .. "(frame); }"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "fast.code.switch_step." .. token, family, Native.NativeChunkControlOp, signature, Native.NativeExtractContinuationFragment({ case_symbol, default_symbol }), entry, lines, holes, { case_ordinal, default_ordinal })
    end

    function Native.NativeCodeSwitchStepShape:native_fast_switch_step_key_c_expr(_atom_holes)
        internal_error("unsupported native fast switch-step key C expression")
    end

    function Native.NativeSwitchStepAtoms:append_native_template_sources(out, input)
        append_fast_code_switch_step_source(out, input, self, function(operands, holes, id_base)
            return { key = append_fast_expr_atom(operands, holes, id_base .. ".key", self.key, 0) }
        end)
    end

    function Native.NativeSwitchStepAtoms:native_fast_switch_step_key_c_expr(atom_holes)
        return self.key:native_fast_atom_c_expr(atom_holes.key)
    end

    function Native.NativeSwitchStepImmKey:append_native_template_sources(out, input)
        append_fast_code_switch_step_source(out, input, self, function(operands, holes, id_base)
            local key = Native.NativeExprImmediate(self.scalar)
            return { key = append_fast_expr_atom(operands, holes, id_base .. ".key", key, 0) }
        end)
    end

    function Native.NativeSwitchStepImmKey:native_fast_switch_step_key_c_expr(atom_holes)
        return Native.NativeExprImmediate(self.scalar):native_fast_atom_c_expr(atom_holes.key)
    end

    function Native.NativeAbiProjection:native_fast_public_result_scalar(target)
        return Support.scalar_pointer(target.pointer_bits)
    end

    function Native.NativeAbiProjection:native_fast_public_call_protocol(target)
        return Support.native_call_return_scalar(self:native_fast_public_result_scalar(target))
    end

    function Native.NativeAbiVoidResult:native_fast_public_result_scalar(_target) return Support.scalar_bool8() end
    function Native.NativeAbiVoidResult:native_fast_public_call_protocol(_target) return Support.native_call_void() end
    function Native.NativeAbiScalarValue:native_fast_public_result_scalar(_target) return self.scalar end
    function Native.NativeAbiPointerValue:native_fast_public_result_scalar(_target) return self.scalar end
    function Native.NativeAbiByRefValue:native_fast_public_result_scalar(target) return Support.scalar_pointer(target.pointer_bits) end

    function Native.NativeAbiProjection:append_native_fast_public_result_holes(_holes, _id_base)
        internal_error("unsupported native fast public ABI result hole")
    end

    function Native.NativeAbiVoidResult:append_native_fast_public_result_holes(_holes, _id_base)
        return {}
    end

    function Native.NativeAbiScalarValue:append_native_fast_public_result_holes(holes, id_base)
        local hole = scalar_immediate_hole(id_base .. ".result", self.scalar)
        holes[#holes + 1] = hole
        return { hole }
    end

    function Native.NativeAbiPointerValue:append_native_fast_public_result_holes(holes, id_base)
        local hole = ptr64_hole(id_base .. ".result")
        holes[#holes + 1] = hole
        return { hole }
    end

    function Native.NativeAbiByRefValue:append_native_fast_public_result_holes(holes, id_base)
        local hole = ptr64_hole(id_base .. ".result")
        holes[#holes + 1] = hole
        return { hole }
    end

    function Native.NativeAbiProjection:native_fast_public_result_expr(_target, _holes)
        internal_error("unsupported native fast public ABI result expression")
    end

    function Native.NativeAbiScalarValue:native_fast_public_result_expr(_target, holes)
        return "(" .. self:native_c_boundary_type() .. ")" .. hole_address_expr(holes[1])
    end

    function Native.NativeAbiPointerValue:native_fast_public_result_expr(_target, holes)
        return "(void *)(uintptr_t)" .. hole_address_expr(holes[1])
    end

    function Native.NativeAbiByRefValue:native_fast_public_result_expr(_target, holes)
        return "(void *)(uintptr_t)" .. hole_address_expr(holes[1])
    end

    function Native.NativeAbiProjection:append_native_fast_public_return_lines(_lines, _target, _holes)
        internal_error("unsupported native fast public ABI return")
    end

    function Native.NativeAbiVoidResult:append_native_fast_public_return_lines(lines, _target, _holes)
        lines[#lines + 1] = "    return;"
    end

    function Native.NativeAbiScalarValue:append_native_fast_public_return_lines(lines, target, holes)
        lines[#lines + 1] = "    return " .. self:native_fast_public_result_expr(target, holes) .. ";"
    end

    function Native.NativeAbiPointerValue:append_native_fast_public_return_lines(lines, target, holes)
        lines[#lines + 1] = "    return " .. self:native_fast_public_result_expr(target, holes) .. ";"
    end

    function Native.NativeAbiByRefValue:append_native_fast_public_return_lines(lines, target, holes)
        lines[#lines + 1] = "    return " .. self:native_fast_public_result_expr(target, holes) .. ";"
    end

    function Native.NativeFastPublicAbiShape:native_fast_public_abi_token(_target)
        internal_error("unsupported native fast public ABI shape token")
    end

    function Native.NativeFastAbi0:native_fast_public_abi_token(target)
        return "abi0.r" .. self.result:native_projection_token(target)
    end

    function Native.NativeFastAbi1:native_fast_public_abi_token(target)
        return "abi1.p" .. self.p0:native_projection_token(target) .. ".r" .. self.result:native_projection_token(target)
    end

    function Native.NativeFastAbi2:native_fast_public_abi_token(target)
        return "abi2.p" .. self.p0:native_projection_token(target) .. "_" .. self.p1:native_projection_token(target) .. ".r" .. self.result:native_projection_token(target)
    end

    function Native.NativeFastAbi3:native_fast_public_abi_token(target)
        return "abi3.p" .. self.p0:native_projection_token(target) .. "_" .. self.p1:native_projection_token(target) .. "_" .. self.p2:native_projection_token(target) .. ".r" .. self.result:native_projection_token(target)
    end

    function Native.NativeFastPublicAbiShape:native_fast_public_params()
        internal_error("unsupported native fast public ABI params")
    end

    function Native.NativeFastAbi0:native_fast_public_params() return {} end
    function Native.NativeFastAbi1:native_fast_public_params() return { self.p0 } end
    function Native.NativeFastAbi2:native_fast_public_params() return { self.p0, self.p1 } end
    function Native.NativeFastAbi3:native_fast_public_params() return { self.p0, self.p1, self.p2 } end

    function Native.NativeFastPublicAbiShape:native_fast_public_result()
        internal_error("unsupported native fast public ABI result")
    end

    function Native.NativeFastAbi0:native_fast_public_result() return self.result end
    function Native.NativeFastAbi1:native_fast_public_result() return self.result end
    function Native.NativeFastAbi2:native_fast_public_result() return self.result end
    function Native.NativeFastAbi3:native_fast_public_result() return self.result end

    local function fast_public_abi_family(input, shape, token, result, result_scalar)
        return Native.NativeTemplateFamily(
            Native.NativeTemplateFamilyId("native.fast.public_abi." .. token),
            Native.NativeRoleCodeFunc,
            {
                Support.axis_target(input.target),
                Support.axis_machine_scalar(result_scalar),
                Support.axis_fast_public_abi(shape),
            },
            Support.protocol(result:native_fast_public_call_protocol(input.target), Support.register_none())
        )
    end

    function Native.NativeFastPublicAbiShape:append_native_template_sources(out, input)
        local target = input.target
        local token = self:native_fast_public_abi_token(target)
        local result = self:native_fast_public_result()
        local result_scalar = result:native_fast_public_result_scalar(target)
        local holes = {}
        local result_holes = result:append_native_fast_public_result_holes(holes, "native.hole.fast.public_abi." .. token)
        local family = fast_public_abi_family(input, self, token, result, result_scalar)
        local signature = Support.spill_all_stencil_signature(result_scalar, {}, {})
        local entry = "lalin_native_fast_public_abi_" .. symbol_fragment(token)
        local public_params = self:native_fast_public_params()
        local params = {}
        for i, param in ipairs(public_params) do
            params[#params + 1] = param:native_c_boundary_type() .. " p" .. tostring(i - 1)
        end
        if #params == 0 then params[#params + 1] = "void" end
        local lines = c_prelude()
        self:native_fast_public_result():append_native_c_declarations(lines, {})
        for _, param in ipairs(public_params) do param:append_native_c_declarations(lines, {}) end
        append_hole_externs(lines, holes)
        lines[#lines + 1] = result:native_c_boundary_type() .. " " .. entry .. "(" .. table.concat(params, ", ") .. ") {"
        for i = 1, #public_params do lines[#lines + 1] = "    (void)p" .. tostring(i - 1) .. ";" end
        result:append_native_fast_public_return_lines(lines, target, result_holes)
        lines[#lines + 1] = "}"
        append_manifest_source(out, "fast.public_abi." .. token, family, Native.NativeChunkPublicAbiAdapter, signature, Native.NativeExtractStandaloneCallable, entry, lines, holes, {})
    end

    function Native.NativeAbiProjection:native_fast_public_operand_scalar(_target)
        return nil
    end

    function Native.NativeAbiScalarValue:native_fast_public_operand_scalar(_target)
        return self.scalar
    end

    function Native.NativeAbiPointerValue:native_fast_public_operand_scalar(_target)
        return self.scalar
    end

    function Native.NativeFastPublicAbiShape:native_fast_public_param_at(_ordinal)
        return nil
    end

    function Native.NativeFastAbi1:native_fast_public_param_at(ordinal)
        if ordinal == 0 then return self.p0 end
    end

    function Native.NativeFastAbi2:native_fast_public_param_at(ordinal)
        if ordinal == 0 then return self.p0 end
        if ordinal == 1 then return self.p1 end
    end

    function Native.NativeFastAbi3:native_fast_public_param_at(ordinal)
        if ordinal == 0 then return self.p0 end
        if ordinal == 1 then return self.p1 end
        if ordinal == 2 then return self.p2 end
    end

    function Native.NativeCodeExprAtomShape:native_fast_public_abi_supported(_abi, _target)
        return false
    end

    function Native.NativeExprInput:native_fast_public_abi_supported(abi, target)
        local param = abi:native_fast_public_param_at(self.ordinal)
        return param ~= nil and param:native_fast_public_operand_scalar(target) == self.scalar
    end

    function Native.NativeExprImmediate:native_fast_public_abi_supported(_abi, _target)
        return true
    end

    function Native.NativeExprConstPool:native_fast_public_abi_supported(_abi, _target)
        return true
    end

    function Native.NativeCodeExprRegionShape:native_fast_public_abi_supported(_abi, _target)
        return false
    end

    function Native.NativeExprReturnAtom:native_fast_public_abi_supported(abi, target)
        return self.result == abi:native_fast_public_result():native_fast_public_result_scalar(target)
            and self.atom:native_fast_public_abi_supported(abi, target)
    end

    function Native.NativeExprReturnUnary:native_fast_public_abi_supported(abi, target)
        return self.result == abi:native_fast_public_result():native_fast_public_result_scalar(target)
            and self.src:native_fast_public_abi_supported(abi, target)
    end

    function Native.NativeExprReturnBinary:native_fast_public_abi_supported(abi, target)
        return self.result == abi:native_fast_public_result():native_fast_public_result_scalar(target)
            and self.lhs:native_fast_public_abi_supported(abi, target)
            and self.rhs:native_fast_public_abi_supported(abi, target)
    end

    function Native.NativeExprReturnBinaryImmRhs:native_fast_public_abi_supported(abi, target)
        return self.result == abi:native_fast_public_result():native_fast_public_result_scalar(target)
            and self.lhs:native_fast_public_abi_supported(abi, target)
    end

    function Native.NativeExprReturnMulAddImm:native_fast_public_abi_supported(abi, target)
        return self.result == abi:native_fast_public_result():native_fast_public_result_scalar(target)
            and self.mul_lhs:native_fast_public_abi_supported(abi, target)
            and self.mul_rhs:native_fast_public_abi_supported(abi, target)
    end

    function Native.NativeCodeExprAtomShape:append_native_fast_public_atom_holes(_holes, _id_base)
        internal_error("unsupported native fast public expression atom holes")
    end

    function Native.NativeExprInput:append_native_fast_public_atom_holes(_holes, _id_base)
        return {}
    end

    function Native.NativeExprImmediate:append_native_fast_public_atom_holes(holes, id_base)
        return self:append_native_fast_atom_holes(holes, id_base)
    end

    function Native.NativeExprConstPool:append_native_fast_public_atom_holes(holes, id_base)
        return self:append_native_fast_atom_holes(holes, id_base)
    end

    function Native.NativeCodeExprAtomShape:append_native_fast_public_atom_operand(_operands, _operand_index)
    end

    function Native.NativeExprImmediate:append_native_fast_public_atom_operand(operands, operand_index)
        self:append_native_fast_atom_operand(operands, operand_index)
    end

    function Native.NativeExprConstPool:append_native_fast_public_atom_operand(operands, operand_index)
        self:append_native_fast_atom_operand(operands, operand_index)
    end

    function Native.NativeCodeExprAtomShape:native_fast_public_atom_c_expr(_holes)
        internal_error("unsupported native fast public expression atom C expression")
    end

    function Native.NativeExprInput:native_fast_public_atom_c_expr(_holes)
        return "p" .. tostring(self.ordinal)
    end

    function Native.NativeExprImmediate:native_fast_public_atom_c_expr(holes)
        return self:native_fast_atom_c_expr(holes)
    end

    function Native.NativeExprConstPool:native_fast_public_atom_c_expr(holes)
        return self:native_fast_atom_c_expr(holes)
    end

    local function append_fast_public_expr_atom(operands, holes, id_base, atom, operand_index)
        atom:append_native_fast_public_atom_operand(operands, operand_index)
        return atom:append_native_fast_public_atom_holes(holes, id_base)
    end

    function Native.NativeCodeExprRegionShape:native_fast_public_expr_c_expr(_atom_holes)
        internal_error("unsupported native fast public Code expression C expression")
    end

    function Native.NativeExprReturnAtom:native_fast_public_expr_c_expr(atom_holes)
        return self.atom:native_fast_public_atom_c_expr(atom_holes.atom)
    end

    function Native.NativeExprReturnUnary:native_fast_public_expr_c_expr(atom_holes)
        local src = self.src:native_fast_public_atom_c_expr(atom_holes.src)
        return self.result:native_fast_unary_c_expr(self.op, src)
    end

    function Native.NativeExprReturnBinary:native_fast_public_expr_c_expr(atom_holes)
        local lhs = self.lhs:native_fast_public_atom_c_expr(atom_holes.lhs)
        local rhs = self.rhs:native_fast_public_atom_c_expr(atom_holes.rhs)
        return self.result:native_fast_binary_c_expr(self.op, lhs, rhs)
    end

    function Native.NativeExprReturnBinaryImmRhs:native_fast_public_expr_c_expr(atom_holes)
        local lhs = self.lhs:native_fast_public_atom_c_expr(atom_holes.lhs)
        local rhs = Native.NativeExprImmediate(self.result):native_fast_public_atom_c_expr(atom_holes.rhs)
        return self.result:native_fast_binary_c_expr(self.op, lhs, rhs)
    end

    function Native.NativeExprReturnMulAddImm:native_fast_public_expr_c_expr(atom_holes)
        local lhs = self.mul_lhs:native_fast_public_atom_c_expr(atom_holes.lhs)
        local rhs = self.mul_rhs:native_fast_public_atom_c_expr(atom_holes.rhs)
        local imm = Native.NativeExprImmediate(self.result):native_fast_public_atom_c_expr(atom_holes.imm)
        return self.result:native_fast_mul_add_imm_c_expr(lhs, rhs, imm)
    end

    function Native.NativeCodeExprRegionShape:append_native_fast_public_code_expr_source(_out, _input, _abi)
        internal_error("unsupported native fast public Code expression source")
    end

    local function append_fast_public_code_expr_source(out, input, abi, shape, expr_builder)
        if not shape:native_fast_public_abi_supported(abi, input.target) then return nil end
        local abi_token = abi:native_fast_public_abi_token(input.target)
        local expr_token = shape:native_fast_expr_token()
        local token = abi_token .. "." .. expr_token
        local holes = {}
        local operands = {}
        local atom_holes = expr_builder(operands, holes, "native.hole.fast.public_code_expr." .. token)
        local result = abi:native_fast_public_result()
        local result_scalar = shape:native_fast_expr_result_scalar()
        local family = Support.fast_public_code_expr_family(input.target, abi, shape)
        local signature = Support.spill_all_stencil_signature(result_scalar, operands, {})
        local entry = "lalin_native_fast_public_code_expr_" .. symbol_fragment(token)
        local public_params = abi:native_fast_public_params()
        local params = {}
        for i, param in ipairs(public_params) do
            params[#params + 1] = param:native_c_boundary_type() .. " p" .. tostring(i - 1)
        end
        if #params == 0 then params[#params + 1] = "void" end
        local lines = c_prelude()
        result:append_native_c_declarations(lines, {})
        for _, param in ipairs(public_params) do param:append_native_c_declarations(lines, {}) end
        append_hole_externs(lines, holes)
        lines[#lines + 1] = result:native_c_boundary_type() .. " " .. entry .. "(" .. table.concat(params, ", ") .. ") {"
        lines[#lines + 1] = "    " .. result_scalar:native_c_scalar_type() .. " result = " .. shape:native_fast_public_expr_c_expr(atom_holes) .. ";"
        lines[#lines + 1] = "    return (" .. result:native_c_boundary_type() .. ")result;"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "fast.public_code_expr." .. token, family, Native.NativeChunkPublicAbiAdapter, signature, Native.NativeExtractStandaloneCallable, entry, lines, holes, {})
    end

    function Native.NativeExprReturnAtom:append_native_fast_public_code_expr_source(out, input, abi)
        append_fast_public_code_expr_source(out, input, abi, self, function(operands, holes, id_base)
            return { atom = append_fast_public_expr_atom(operands, holes, id_base .. ".atom", self.atom, 0) }
        end)
    end

    function Native.NativeExprReturnUnary:append_native_fast_public_code_expr_source(out, input, abi)
        append_fast_public_code_expr_source(out, input, abi, self, function(operands, holes, id_base)
            return { src = append_fast_public_expr_atom(operands, holes, id_base .. ".src", self.src, 0) }
        end)
    end

    function Native.NativeExprReturnBinary:append_native_fast_public_code_expr_source(out, input, abi)
        append_fast_public_code_expr_source(out, input, abi, self, function(operands, holes, id_base)
            return {
                lhs = append_fast_public_expr_atom(operands, holes, id_base .. ".lhs", self.lhs, 0),
                rhs = append_fast_public_expr_atom(operands, holes, id_base .. ".rhs", self.rhs, 1),
            }
        end)
    end

    function Native.NativeExprReturnBinaryImmRhs:append_native_fast_public_code_expr_source(out, input, abi)
        append_fast_public_code_expr_source(out, input, abi, self, function(operands, holes, id_base)
            local imm = Native.NativeExprImmediate(self.result)
            return {
                lhs = append_fast_public_expr_atom(operands, holes, id_base .. ".lhs", self.lhs, 0),
                rhs = append_fast_public_expr_atom(operands, holes, id_base .. ".rhs", imm, 1),
            }
        end)
    end

    function Native.NativeExprReturnMulAddImm:append_native_fast_public_code_expr_source(out, input, abi)
        append_fast_public_code_expr_source(out, input, abi, self, function(operands, holes, id_base)
            local imm = Native.NativeExprImmediate(self.result)
            return {
                lhs = append_fast_public_expr_atom(operands, holes, id_base .. ".mul_lhs", self.mul_lhs, 0),
                rhs = append_fast_public_expr_atom(operands, holes, id_base .. ".mul_rhs", self.mul_rhs, 1),
                imm = append_fast_public_expr_atom(operands, holes, id_base .. ".imm", imm, 2),
            }
        end)
    end

    function Native.NativeFastRegionCapability:append_native_template_sources(out, input)
        for _, shape in ipairs(self.public_abi_shapes or {}) do shape:append_native_template_sources(out, input) end
        for _, shape in ipairs(self.code_expr_shapes or {}) do shape:append_native_template_sources(out, input) end
        for _, abi in ipairs(self.public_abi_shapes or {}) do
            for _, shape in ipairs(self.code_expr_shapes or {}) do shape:append_native_fast_public_code_expr_source(out, input, abi) end
        end
        for _, shape in ipairs(self.compare_branch_shapes or {}) do shape:append_native_template_sources(out, input) end
        for _, shape in ipairs(self.switch_step_shapes or {}) do shape:append_native_template_sources(out, input) end
    end

    local function append_hole_relocation_markers(lines, holes)
        for _, hole in ipairs(holes or {}) do
            if not asdl.isa(hole.hole, Native.NativePatchCallRel32) then
                local directive = hole.width == 8 and ".quad" or ".long"
                lines[#lines + 1] = "    __asm__ volatile(\"jmp 1f\\n " .. directive .. " " .. hole.symbol .. "\\n1:\");"
            end
        end
    end

    local function complete_target(input)
        return require_value(input.target, "complete-bank target")
    end

    local function complete_pointer_scalar(input)
        return Support.scalar_pointer(complete_target(input).pointer_bits)
    end

    function Native.NativeCompleteValueClass:native_complete_value_token()
        internal_error("unsupported complete value class token")
    end
    function Native.NativeCompleteValueVoidClass:native_complete_value_token() return "void" end
    function Native.NativeCompleteValueScalarClass:native_complete_value_token() return self.scalar:native_scalar_token() end
    function Native.NativeCompleteValuePointerClass:native_complete_value_token() return "ptr." .. self.pointer_scalar:native_scalar_token() end
    function Native.NativeCompleteValueBytesClass:native_complete_value_token() return "bytes" end

    function Native.NativeCompleteValueClass:native_complete_value_scalar(input)
        return complete_pointer_scalar(input)
    end
    function Native.NativeCompleteValueScalarClass:native_complete_value_scalar(_input) return self.scalar end
    function Native.NativeCompleteValuePointerClass:native_complete_value_scalar(_input) return self.pointer_scalar end

    function Native.NativeCompleteScalarBytesClass:native_complete_scalar_bytes_token()
        internal_error("unsupported complete scalar/bytes class token")
    end
    function Native.NativeCompleteScalarBytesScalarClass:native_complete_scalar_bytes_token() return self.scalar:native_scalar_token() end
    function Native.NativeCompleteScalarBytesPointerClass:native_complete_scalar_bytes_token() return "ptr." .. self.pointer_scalar:native_scalar_token() end
    function Native.NativeCompleteScalarBytesBytesClass:native_complete_scalar_bytes_token() return "bytes" end
    function Native.NativeCompleteScalarBytesClass:native_complete_scalar_bytes_scalar(input)
        return complete_pointer_scalar(input)
    end
    function Native.NativeCompleteScalarBytesScalarClass:native_complete_scalar_bytes_scalar(_input) return self.scalar end
    function Native.NativeCompleteScalarBytesPointerClass:native_complete_scalar_bytes_scalar(_input) return self.pointer_scalar end

    function Native.NativeCompleteScalarPointerClass:native_complete_scalar_pointer_token()
        internal_error("unsupported complete scalar/pointer class token")
    end
    function Native.NativeCompleteScalarPointerScalarClass:native_complete_scalar_pointer_token() return self.scalar:native_scalar_token() end
    function Native.NativeCompleteScalarPointerPointerClass:native_complete_scalar_pointer_token() return "ptr." .. self.pointer_scalar:native_scalar_token() end
    function Native.NativeCompleteScalarPointerClass:native_complete_scalar_pointer_scalar(input)
        return complete_pointer_scalar(input)
    end
    function Native.NativeCompleteScalarPointerScalarClass:native_complete_scalar_pointer_scalar(_input) return self.scalar end
    function Native.NativeCompleteScalarPointerPointerClass:native_complete_scalar_pointer_scalar(_input) return self.pointer_scalar end

    function Native.NativeCodeMicroOpShape:native_code_micro_op_token()
        internal_error("unsupported Code complete-bank micro-op token")
    end
    function Native.NativeCodeMicroOpFrameEntryShape:native_code_micro_op_token() return "frame_entry" end
    function Native.NativeCodeMicroOpScalarLoadShape:native_code_micro_op_token() return "scalar_load." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpScalarStoreShape:native_code_micro_op_token() return "scalar_store." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpScalarCopyShape:native_code_micro_op_token() return "scalar_copy." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpBytesCopyShape:native_code_micro_op_token() return "bytes_copy" end
    function Native.NativeCodeMicroOpBytesMoveShape:native_code_micro_op_token() return "bytes_move" end
    function Native.NativeCodeMicroOpConstShape:native_code_micro_op_token() return "const." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpUnaryShape:native_code_micro_op_token() return "unary." .. self.op:native_unary_family_name() .. "." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpBinaryShape:native_code_micro_op_token() return "binary." .. self.op:native_binary_family_name() .. "." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpCompareShape:native_code_micro_op_token() return "compare." .. self.cmp:native_compare_family_name() .. "." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpCastShape:native_code_micro_op_token() return "cast." .. self.op:native_cast_family_name() .. "." .. self.from_scalar:native_scalar_token() .. ".to." .. self.to_scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpSelectShape:native_code_micro_op_token() return "select." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpAddressBaseShape:native_code_micro_op_token() return "address_base" end
    function Native.NativeCodeMicroOpAddressFieldShape:native_code_micro_op_token() return "address_field" end
    function Native.NativeCodeMicroOpAddressIndexShape:native_code_micro_op_token() return "address_index" end
    function Native.NativeCodeMicroOpAddressOffsetShape:native_code_micro_op_token() return "address_offset" end
    function Native.NativeCodeMicroOpLoadShape:native_code_micro_op_token() return "load." .. self.value_class:native_complete_scalar_bytes_token() end
    function Native.NativeCodeMicroOpStoreShape:native_code_micro_op_token() return "store." .. self.value_class:native_complete_scalar_bytes_token() end
    function Native.NativeCodeMicroOpDescriptorFieldShape:native_code_micro_op_token() return "descriptor_field" end
    function Native.NativeCodeMicroOpAggregateStepShape:native_code_micro_op_token() return "aggregate_step" end
    function Native.NativeCodeMicroOpArrayStepShape:native_code_micro_op_token() return "array_step" end
    function Native.NativeCodeMicroOpVariantTagShape:native_code_micro_op_token() return "variant_tag" end
    function Native.NativeCodeMicroOpVariantPayloadShape:native_code_micro_op_token() return "variant_payload" end
    function Native.NativeCodeMicroOpJumpShape:native_code_micro_op_token() return "jump" end
    function Native.NativeCodeMicroOpBranchShape:native_code_micro_op_token() return "branch" end
    function Native.NativeCodeMicroOpSwitchStepShape:native_code_micro_op_token() return "switch_step" end
    function Native.NativeCodeMicroOpTrapShape:native_code_micro_op_token() return "trap" end
    function Native.NativeCodeMicroOpUnreachableShape:native_code_micro_op_token() return "unreachable" end
    function Native.NativeCodeMicroOpReturnVoidShape:native_code_micro_op_token() return "return_void" end
    function Native.NativeCodeMicroOpReturnScalarShape:native_code_micro_op_token() return "return_scalar." .. self.scalar:native_scalar_token() end
    function Native.NativeCodeMicroOpReturnSretShape:native_code_micro_op_token() return "return_sret" end
    function Native.NativeCodeMicroOpCallDirectShape:native_code_micro_op_token() return "call_direct" end
    function Native.NativeCodeMicroOpCallExternShape:native_code_micro_op_token() return "call_extern" end
    function Native.NativeCodeMicroOpCallIndirectShape:native_code_micro_op_token() return "call_indirect" end
    function Native.NativeCodeMicroOpCallClosureShape:native_code_micro_op_token() return "call_closure" end

    local function append_complete_code_source(out, input, shape, chunk_class, scalar, role, holes, body_lines, continuation_ordinals, extraction, signature, extra_relocation_kinds)
        local token = shape:native_code_micro_op_token()
        local family = Support.code_micro_op_frame_family(token, complete_target(input), scalar, shape, role)
        local entry = "lalin_native_code_micro_" .. symbol_fragment(token)
        local lines = c_prelude()
        append_hole_externs(lines, holes or {})
        for _, line in ipairs(body_lines or {}) do lines[#lines + 1] = line end
        append_manifest_source(
            out,
            "code.micro." .. token,
            family,
            chunk_class,
            signature or scalar_frame_signature(scalar, #(holes or {}), continuation_ordinals or {}),
            extraction or Native.NativeExtractContinuationFragment({ Support.next_continuation_symbol() }),
            entry,
            lines,
            holes or {},
            continuation_ordinals or { Support.next_continuation_ordinal() },
            extra_relocation_kinds or {}
        )
    end

    local function append_complete_next_fragment(out, input, shape, chunk_class, scalar, holes, body, extra_relocation_kinds)
        local next_symbol = Support.next_continuation_symbol()
        local lines = { continuation_extern(next_symbol), "void lalin_native_code_micro_" .. symbol_fragment(shape:native_code_micro_op_token()) .. "(uint8_t *frame) {" }
        append_hole_relocation_markers(lines, holes or {})
        for _, line in ipairs(body or {}) do lines[#lines + 1] = line end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_complete_code_source(out, input, shape, chunk_class, scalar, Native.NativeRoleCodeInst, holes or {}, lines, { Support.next_continuation_ordinal() }, nil, nil, extra_relocation_kinds or {})
    end

    function Native.NativeCodeMicroOpShape:append_native_template_sources(_out, _input)
        internal_error("unsupported Code complete-bank micro-op source builder")
    end

    function Native.NativeCodeMicroOpFrameEntryShape:append_native_template_sources(out, input)
        local scalar = complete_pointer_scalar(input)
        local first = Support.first_continuation_symbol()
        local first_ordinal = Support.first_continuation_ordinal()
        local first_signature = Support.stencil_continuation_signature(first_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, {}, { first_signature })
        local lines = { continuation_extern(first, first_signature), "void lalin_native_code_micro_frame_entry(uint8_t *frame) {", "    " .. first.name .. "(frame);", "}" }
        append_complete_code_source(out, input, self, Native.NativeChunkFrameEntry, scalar, Native.NativeRoleCodeFunc, {}, lines, { first_ordinal }, Native.NativeExtractEntryCallable(Native.NativePatchFrameSize(FRAME_BYTES), first), signature)
    end

    function Native.NativeCodeMicroOpScalarLoadShape:append_native_template_sources(out, input)
        local c_type, token = self.scalar:native_c_scalar_type(), self.scalar:native_scalar_token()
        local holes = { frame_offset_hole("native.hole.code.micro.scalar_load." .. token .. ".addr"), frame_offset_hole("native.hole.code.micro.scalar_load." .. token .. ".dst") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkAddressMemoryOp, self.scalar, holes, {
            "    uintptr_t addr = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";",
            frame_store(c_type, hole_address_expr(holes[2]), "*(" .. c_type .. " *)(void *)addr"),
        })
    end

    function Native.NativeCodeMicroOpScalarStoreShape:append_native_template_sources(out, input)
        local c_type, token = self.scalar:native_c_scalar_type(), self.scalar:native_scalar_token()
        local holes = { frame_offset_hole("native.hole.code.micro.scalar_store." .. token .. ".addr"), frame_offset_hole("native.hole.code.micro.scalar_store." .. token .. ".src") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkAddressMemoryOp, self.scalar, holes, {
            "    uintptr_t addr = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";",
            "    *(" .. c_type .. " *)(void *)addr = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";",
        })
    end

    function Native.NativeCodeMicroOpScalarCopyShape:append_native_template_sources(out, input)
        local c_type, token = self.scalar:native_c_scalar_type(), self.scalar:native_scalar_token()
        local holes = { frame_offset_hole("native.hole.code.micro.scalar_copy." .. token .. ".src"), frame_offset_hole("native.hole.code.micro.scalar_copy." .. token .. ".dst") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkEdgeCopy, self.scalar, holes, {
            "    " .. c_type .. " value = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";",
            frame_store(c_type, hole_address_expr(holes[2]), "value"),
        })
    end

    local function complete_byte_copy_body(holes, move)
        local body = {
            "    uint8_t *dst = (uint8_t *)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";",
            "    const uint8_t *src = (const uint8_t *)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[2])) .. ";",
            "    uint32_t n = (uint32_t)" .. hole_address_expr(holes[3]) .. ";",
        }
        if move then
            body[#body + 1] = "    if (dst > src) { while (n != 0) { n = n - 1; dst[n] = src[n]; } }"
            body[#body + 1] = "    else { for (uint32_t i = 0; i < n; i = i + 1) dst[i] = src[i]; }"
        else
            body[#body + 1] = "    for (uint32_t i = 0; i < n; i = i + 1) dst[i] = src[i];"
        end
        return body
    end

    local function append_complete_bytes_copy(out, input, shape, move)
        local scalar = complete_pointer_scalar(input)
        local token = move and "bytes_move" or "bytes_copy"
        local holes = { frame_offset_hole("native.hole.code.micro." .. token .. ".dst"), frame_offset_hole("native.hole.code.micro." .. token .. ".src"), imm32_hole("native.hole.code.micro." .. token .. ".size") }
        append_complete_next_fragment(out, input, shape, move and Native.NativeChunkParallelCopy or Native.NativeChunkEdgeCopy, scalar, holes, complete_byte_copy_body(holes, move))
    end
    function Native.NativeCodeMicroOpBytesCopyShape:append_native_template_sources(out, input) append_complete_bytes_copy(out, input, self, false) end
    function Native.NativeCodeMicroOpBytesMoveShape:append_native_template_sources(out, input) append_complete_bytes_copy(out, input, self, true) end

    function Native.NativeCodeMicroOpConstShape:append_native_template_sources(out, input)
        local token, c_type = self.scalar:native_scalar_token(), self.scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.code.micro.const." .. token .. ".dst"), scalar_immediate_hole("native.hole.code.micro.const." .. token, self.scalar) }
        append_complete_next_fragment(out, input, self, Native.NativeChunkConstantLoad, self.scalar, holes, { frame_store(c_type, hole_address_expr(holes[1]), "(" .. c_type .. ")" .. hole_address_expr(holes[2])) })
    end

    function Native.NativeCodeMicroOpUnaryShape:append_native_template_sources(out, input)
        local c_type, token, name = self.scalar:native_c_scalar_type(), self.scalar:native_scalar_token(), self.op:native_unary_family_name()
        local result_type = name == "not" and "uint8_t" or c_type
        local holes = { frame_offset_hole("native.hole.code.micro.unary." .. token .. "." .. name .. ".src"), frame_offset_hole("native.hole.code.micro.unary." .. token .. "." .. name .. ".dst") }
        local src = frame_load(c_type, hole_address_expr(holes[1]))
        local is_float = asdl.isa(self.scalar, Native.NativeScalarFloat)
        local expr = is_float and "(-src)" or self.op:native_integer_c_expr(self.scalar, "src")
        local extra_relocations = is_float and { Native.NativeTemplateRelocationConstantPool } or {}
        append_complete_next_fragment(out, input, self, Native.NativeChunkUnaryOp, self.scalar, holes, { "    " .. c_type .. " src = " .. src .. ";", frame_store(result_type, hole_address_expr(holes[2]), expr) }, extra_relocations)
    end

    function Native.NativeCodeMicroOpBinaryShape:append_native_template_sources(out, input)
        local c_type, token, name = self.scalar:native_c_scalar_type(), self.scalar:native_scalar_token(), self.op:native_binary_family_name()
        local holes = { frame_offset_hole("native.hole.code.micro.binary." .. token .. "." .. name .. ".lhs"), frame_offset_hole("native.hole.code.micro.binary." .. token .. "." .. name .. ".rhs"), frame_offset_hole("native.hole.code.micro.binary." .. token .. "." .. name .. ".dst") }
        local expr = asdl.isa(self.scalar, Native.NativeScalarFloat) and self.op:native_float_c_expr(self.scalar, "lhs", "rhs") or self.op:native_integer_c_expr(self.scalar, "lhs", "rhs")
        append_complete_next_fragment(out, input, self, Native.NativeChunkBinaryOp, self.scalar, holes, {
            "    " .. c_type .. " lhs = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";",
            "    " .. c_type .. " rhs = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";",
            frame_store(c_type, hole_address_expr(holes[3]), expr),
        })
    end

    function Native.NativeCodeMicroOpCompareShape:append_native_template_sources(out, input)
        local c_type, token, name = self.scalar:native_c_scalar_type(), self.scalar:native_scalar_token(), self.cmp:native_compare_family_name()
        local holes = { frame_offset_hole("native.hole.code.micro.compare." .. token .. "." .. name .. ".lhs"), frame_offset_hole("native.hole.code.micro.compare." .. token .. "." .. name .. ".rhs"), frame_offset_hole("native.hole.code.micro.compare." .. token .. ".dst") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkCompareOp, self.scalar, holes, {
            "    " .. c_type .. " lhs = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";",
            "    " .. c_type .. " rhs = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";",
            frame_store("uint8_t", hole_address_expr(holes[3]), self.cmp:native_c_compare_expr(self.scalar, "lhs", "rhs")),
        })
    end

    function Native.NativeCodeMicroOpCastShape:append_native_template_sources(out, input)
        local from_token, to_token, name = self.from_scalar:native_scalar_token(), self.to_scalar:native_scalar_token(), self.op:native_cast_family_name()
        local holes = { frame_offset_hole("native.hole.code.micro.cast." .. name .. "." .. from_token .. ".src"), frame_offset_hole("native.hole.code.micro.cast." .. name .. "." .. from_token .. ".to." .. to_token .. ".dst") }
        local lines = { "    " .. self.from_scalar:native_c_scalar_type() .. " source_value = " .. frame_load(self.from_scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";" }
        self.op:append_native_cast_c_lines(lines, self.from_scalar, self.to_scalar, "source_value", "cast_value")
        lines[#lines + 1] = frame_store(self.to_scalar:native_c_scalar_type(), hole_address_expr(holes[2]), "cast_value")
        append_complete_next_fragment(out, input, self, Native.NativeChunkCastOp, self.to_scalar, holes, lines, self.op:native_cast_extra_relocation_kinds())
    end

    function Native.NativeCodeMicroOpSelectShape:append_native_template_sources(out, input)
        local c_type, token = self.scalar:native_c_scalar_type(), self.scalar:native_scalar_token()
        local holes = { frame_offset_hole("native.hole.code.micro.select." .. token .. ".cond"), frame_offset_hole("native.hole.code.micro.select." .. token .. ".true"), frame_offset_hole("native.hole.code.micro.select." .. token .. ".false"), frame_offset_hole("native.hole.code.micro.select." .. token .. ".dst") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkSelectOp, self.scalar, holes, {
            "    uint8_t cond = " .. frame_load("uint8_t", hole_address_expr(holes[1])) .. ";",
            "    " .. c_type .. " true_value = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";",
            "    " .. c_type .. " false_value = " .. frame_load(c_type, hole_address_expr(holes[3])) .. ";",
            frame_store(c_type, hole_address_expr(holes[4]), "cond ? true_value : false_value"),
        })
    end

    local function append_complete_address_binary(out, input, shape, suffix, expr)
        local scalar = complete_pointer_scalar(input)
        local holes = { frame_offset_hole("native.hole.code.micro." .. suffix .. ".base"), frame_offset_hole("native.hole.code.micro." .. suffix .. ".index"), imm32_hole("native.hole.code.micro." .. suffix .. ".payload"), frame_offset_hole("native.hole.code.micro." .. suffix .. ".dst") }
        append_complete_next_fragment(out, input, shape, Native.NativeChunkAddressMemoryOp, scalar, holes, {
            "    uintptr_t base = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";",
            "    uintptr_t index = " .. frame_load("uintptr_t", hole_address_expr(holes[2])) .. ";",
            frame_store("uintptr_t", hole_address_expr(holes[4]), expr("base", "index", hole_address_expr(holes[3]))),
        })
    end
    function Native.NativeCodeMicroOpAddressBaseShape:append_native_template_sources(out, input)
        local scalar = complete_pointer_scalar(input)
        local holes = { ptr64_hole("native.hole.code.micro.address_base.symbol"), frame_offset_hole("native.hole.code.micro.address_base.dst") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkAddressMemoryOp, scalar, holes, { frame_store("uintptr_t", hole_address_expr(holes[2]), hole_address_expr(holes[1])) })
    end
    function Native.NativeCodeMicroOpAddressFieldShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "address_field", function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeCodeMicroOpAddressIndexShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "address_index", function(base, index, payload) return base .. " + (" .. index .. " * (uintptr_t)" .. payload .. ")" end) end
    function Native.NativeCodeMicroOpAddressOffsetShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "address_offset", function(base, index, payload) return base .. " + " .. index .. " + (uintptr_t)" .. payload end) end
    function Native.NativeCodeMicroOpDescriptorFieldShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "descriptor_field", function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeCodeMicroOpAggregateStepShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "aggregate_step", function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeCodeMicroOpArrayStepShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "array_step", function(base, index, payload) return base .. " + (" .. index .. " * (uintptr_t)" .. payload .. ")" end) end
    function Native.NativeCodeMicroOpVariantTagShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "variant_tag", function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeCodeMicroOpVariantPayloadShape:append_native_template_sources(out, input) append_complete_address_binary(out, input, self, "variant_payload", function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end

    function Native.NativeCodeMicroOpLoadShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_scalar_bytes_scalar(input)
        local c_type, token = scalar:native_c_scalar_type(), self.value_class:native_complete_scalar_bytes_token()
        local holes = { frame_offset_hole("native.hole.code.micro.load." .. token .. ".addr"), frame_offset_hole("native.hole.code.micro.load." .. token .. ".dst") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkAddressMemoryOp, scalar, holes, {
            "    uintptr_t addr = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";",
            frame_store(c_type, hole_address_expr(holes[2]), "*(" .. c_type .. " *)(void *)addr"),
        })
    end
    function Native.NativeCodeMicroOpStoreShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_scalar_bytes_scalar(input)
        local c_type, token = scalar:native_c_scalar_type(), self.value_class:native_complete_scalar_bytes_token()
        local holes = { frame_offset_hole("native.hole.code.micro.store." .. token .. ".addr"), frame_offset_hole("native.hole.code.micro.store." .. token .. ".src") }
        append_complete_next_fragment(out, input, self, Native.NativeChunkAddressMemoryOp, scalar, holes, {
            "    uintptr_t addr = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";",
            "    *(" .. c_type .. " *)(void *)addr = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";",
        })
    end

    function Native.NativeCodeMicroOpJumpShape:append_native_template_sources(out, input)
        append_complete_next_fragment(out, input, self, Native.NativeChunkControlOp, complete_pointer_scalar(input), {}, {})
    end
    function Native.NativeCodeMicroOpBranchShape:append_native_template_sources(out, input)
        local scalar = complete_pointer_scalar(input)
        local then_symbol, else_symbol = Support.then_continuation_symbol(), Support.else_continuation_symbol()
        local then_ordinal, else_ordinal = Support.then_continuation_ordinal(), Support.else_continuation_ordinal()
        local holes = { frame_offset_hole("native.hole.code.micro.branch.cond") }
        local lines = { continuation_extern(then_symbol), continuation_extern(else_symbol), "void lalin_native_code_micro_branch(uint8_t *frame) {", "    uint8_t cond = " .. frame_load("uint8_t", hole_address_expr(holes[1])) .. ";", "    if (cond != 0) { " .. then_symbol.name .. "(frame); } else { " .. else_symbol.name .. "(frame); }", "}" }
        append_complete_code_source(out, input, self, Native.NativeChunkControlOp, scalar, Native.NativeRoleCodeTerm, holes, lines, { then_ordinal, else_ordinal }, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), scalar_frame_signature(scalar, 1, { then_ordinal, else_ordinal }))
    end
    function Native.NativeCodeMicroOpSwitchStepShape:append_native_template_sources(out, input)
        local scalar = complete_pointer_scalar(input)
        local then_symbol, else_symbol = Support.then_continuation_symbol(), Support.else_continuation_symbol()
        local then_ordinal, else_ordinal = Support.then_continuation_ordinal(), Support.else_continuation_ordinal()
        local holes = { frame_offset_hole("native.hole.code.micro.switch_step.key"), imm32_hole("native.hole.code.micro.switch_step.case") }
        local lines = { continuation_extern(then_symbol), continuation_extern(else_symbol), "void lalin_native_code_micro_switch_step(uint8_t *frame) {", "    uintptr_t key = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";", "    if (key == (uintptr_t)" .. hole_address_expr(holes[2]) .. ") { " .. then_symbol.name .. "(frame); } else { " .. else_symbol.name .. "(frame); }", "}" }
        append_complete_code_source(out, input, self, Native.NativeChunkControlOp, scalar, Native.NativeRoleCodeTerm, holes, lines, { then_ordinal, else_ordinal }, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), scalar_frame_signature(scalar, 2, { then_ordinal, else_ordinal }))
    end
    function Native.NativeCodeMicroOpTrapShape:append_native_template_sources(out, input)
        append_complete_code_source(out, input, self, Native.NativeChunkControlOp, complete_pointer_scalar(input), Native.NativeRoleCodeTerm, {}, { "void lalin_native_code_micro_trap(uint8_t *frame) {", "    (void)frame;", "    __builtin_trap();", "}" }, {}, Native.NativeExtractTerminalContinuation, scalar_frame_signature(complete_pointer_scalar(input), 0, {}))
    end
    function Native.NativeCodeMicroOpUnreachableShape:append_native_template_sources(out, input)
        append_complete_code_source(out, input, self, Native.NativeChunkControlOp, complete_pointer_scalar(input), Native.NativeRoleCodeTerm, {}, { "void lalin_native_code_micro_unreachable(uint8_t *frame) {", "    (void)frame;", "    __builtin_unreachable();", "}" }, {}, Native.NativeExtractTerminalContinuation, scalar_frame_signature(complete_pointer_scalar(input), 0, {}))
    end
    function Native.NativeCodeMicroOpReturnVoidShape:append_native_template_sources(out, input)
        append_complete_code_source(out, input, self, Native.NativeChunkTerminalContinuation, complete_pointer_scalar(input), Native.NativeRoleCodeTerm, {}, { "void lalin_native_code_micro_return_void(uint8_t *frame) {", "    (void)frame;", "    return;", "}" }, {}, Native.NativeExtractTerminalContinuation, scalar_frame_signature(complete_pointer_scalar(input), 0, {}))
    end
    function Native.NativeCodeMicroOpReturnScalarShape:append_native_template_sources(out, input)
        append_complete_code_source(out, input, self, Native.NativeChunkTerminalContinuation, self.scalar, Native.NativeRoleCodeTerm, {}, { "void lalin_native_code_micro_" .. symbol_fragment(self:native_code_micro_op_token()) .. "(uint8_t *frame) {", "    (void)frame;", "    return;", "}" }, {}, Native.NativeExtractTerminalContinuation, scalar_frame_signature(self.scalar, 0, {}))
    end
    function Native.NativeCodeMicroOpReturnSretShape:append_native_template_sources(out, input)
        append_complete_code_source(out, input, self, Native.NativeChunkTerminalContinuation, complete_pointer_scalar(input), Native.NativeRoleCodeTerm, {}, { "void lalin_native_code_micro_return_sret(uint8_t *frame) {", "    (void)frame;", "    return;", "}" }, {}, Native.NativeExtractTerminalContinuation, scalar_frame_signature(complete_pointer_scalar(input), 0, {}))
    end

    local function append_complete_call(out, input, shape, suffix, indirect, closure)
        local scalar = complete_pointer_scalar(input)
        local holes = {}
        if indirect or closure then holes[#holes + 1] = frame_offset_hole("native.hole.code.micro.call_" .. suffix .. ".fn") else holes[#holes + 1] = call_rel32_hole("native.hole.code.micro.call_" .. suffix .. ".target") end
        if closure then holes[#holes + 1] = frame_offset_hole("native.hole.code.micro.call_closure.env") end
        local next_symbol = Support.next_continuation_symbol()
        local lines = { continuation_extern(next_symbol), "typedef void (*lalin_native_graph_call_t)(uint8_t *frame);", "void lalin_native_code_micro_call_" .. suffix .. "(uint8_t *frame) {" }
        append_hole_relocation_markers(lines, holes)
        if indirect or closure then
            lines[#lines + 1] = "    lalin_native_graph_call_t fn = (lalin_native_graph_call_t)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";"
            if closure then lines[#lines + 1] = "    (void)" .. frame_load("uintptr_t", hole_address_expr(holes[2])) .. ";" end
            lines[#lines + 1] = "    fn(frame);"
        else
            lines[#lines + 1] = "    extern void " .. holes[1].symbol .. "(uint8_t *frame);"
            lines[#lines + 1] = "    " .. holes[1].symbol .. "(frame);"
        end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_complete_code_source(out, input, shape, Native.NativeChunkCallOp, scalar, Native.NativeRoleCodeInst, holes, lines, { Support.next_continuation_ordinal() })
    end
    function Native.NativeCodeMicroOpCallDirectShape:append_native_template_sources(out, input) append_complete_call(out, input, self, "direct", false, false) end
    function Native.NativeCodeMicroOpCallExternShape:append_native_template_sources(out, input) append_complete_call(out, input, self, "extern", false, false) end
    function Native.NativeCodeMicroOpCallIndirectShape:append_native_template_sources(out, input) append_complete_call(out, input, self, "indirect", true, false) end
    function Native.NativeCodeMicroOpCallClosureShape:append_native_template_sources(out, input) append_complete_call(out, input, self, "closure", true, true) end

    function Native.NativeAbiMicroOpShape:native_abi_micro_op_token()
        internal_error("unsupported ABI complete-bank micro-op token")
    end
    function Native.NativeAbiMicroOpParamRegisterShape:native_abi_micro_op_token() return "param_register." .. self.value_class:native_complete_scalar_pointer_token() end
    function Native.NativeAbiMicroOpParamStackShape:native_abi_micro_op_token() return "param_stack." .. self.value_class:native_complete_value_token() end
    function Native.NativeAbiMicroOpParamByRefShape:native_abi_micro_op_token() return "param_byref" end
    function Native.NativeAbiMicroOpResultRegisterShape:native_abi_micro_op_token() return "result_register." .. self.value_class:native_complete_scalar_pointer_token() end
    function Native.NativeAbiMicroOpResultSretShape:native_abi_micro_op_token() return "result_sret" end
    function Native.NativeAbiMicroOpResultVoidShape:native_abi_micro_op_token() return "result_void" end
    function Native.NativeAbiMicroOpCallDirectShape:native_abi_micro_op_token() return "call_direct" end
    function Native.NativeAbiMicroOpCallExternShape:native_abi_micro_op_token() return "call_extern" end
    function Native.NativeAbiMicroOpCallIndirectShape:native_abi_micro_op_token() return "call_indirect" end
    function Native.NativeAbiMicroOpCallClosureShape:native_abi_micro_op_token() return "call_closure" end
    function Native.NativeAbiMicroOpReturnVoidShape:native_abi_micro_op_token() return "return_void" end
    function Native.NativeAbiMicroOpReturnScalarShape:native_abi_micro_op_token() return "return_scalar." .. self.value_class:native_complete_scalar_pointer_token() end
    function Native.NativeAbiMicroOpReturnSretShape:native_abi_micro_op_token() return "return_sret" end

    local function append_complete_abi_source(out, input, shape, scalar, holes, body, terminal)
        local token = shape:native_abi_micro_op_token()
        local family = Support.abi_micro_op_frame_family(token, complete_target(input), scalar, shape)
        local entry = "lalin_native_abi_micro_" .. symbol_fragment(token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes or {})
        if not terminal then lines[#lines + 1] = continuation_extern(next_symbol) end
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        append_hole_relocation_markers(lines, holes or {})
        for _, line in ipairs(body or {}) do lines[#lines + 1] = line end
        if not terminal then lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);" end
        lines[#lines + 1] = "}"
        append_manifest_source(out, "abi.micro." .. token, family, Native.NativeChunkPublicAbiAdapter, scalar_frame_signature(scalar, #(holes or {}), terminal and {} or { Support.next_continuation_ordinal() }), terminal and Native.NativeExtractTerminalContinuation or Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes or {}, terminal and {} or { Support.next_continuation_ordinal() })
    end

    function Native.NativeAbiMicroOpShape:append_native_template_sources(_out, _input)
        internal_error("unsupported ABI complete-bank micro-op source builder")
    end
    function Native.NativeAbiMicroOpParamRegisterShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_scalar_pointer_scalar(input)
        local token = self:native_abi_micro_op_token()
        local hole = frame_offset_hole("native.hole.abi.micro." .. token .. ".dst")
        local next_symbol = Support.next_continuation_symbol()
        local next_ordinal = Support.next_continuation_ordinal()
        local signature = Support.spill_all_stencil_signature(
            scalar,
            { Support.stencil_operand(0, scalar, Support.location_class_continuation_arg()), Support.stencil_operand(1, scalar, Support.location_class_frame_slot()) },
            { Support.stencil_continuation_signature(next_ordinal, {}) }
        )
        local family = Support.abi_micro_op_frame_family(token, complete_target(input), scalar, self)
        local lines = c_prelude()
        append_hole_externs(lines, { hole })
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void lalin_native_abi_micro_" .. symbol_fragment(token) .. "(uint8_t *frame, " .. scalar:native_c_scalar_type() .. " arg0) {"
        lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(hole), "arg0")
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "abi.micro." .. token, family, Native.NativeChunkPublicAbiAdapter, signature, Native.NativeExtractContinuationFragment({ next_symbol }), "lalin_native_abi_micro_" .. symbol_fragment(token), lines, { hole }, { next_ordinal })
    end
    function Native.NativeAbiMicroOpParamStackShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_value_scalar(input)
        local holes = { frame_offset_hole("native.hole.abi.micro." .. self:native_abi_micro_op_token() .. ".dst"), frame_offset_hole("native.hole.abi.micro." .. self:native_abi_micro_op_token() .. ".src") }
        append_complete_abi_source(out, input, self, scalar, holes, { frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[1]), frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[2]))) })
    end
    function Native.NativeAbiMicroOpParamByRefShape:append_native_template_sources(out, input)
        local scalar = complete_pointer_scalar(input)
        local holes = { frame_offset_hole("native.hole.abi.micro.param_byref.dst"), frame_offset_hole("native.hole.abi.micro.param_byref.src") }
        append_complete_abi_source(out, input, self, scalar, holes, { frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[1]), frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[2]))) })
    end
    function Native.NativeAbiMicroOpResultRegisterShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_scalar_pointer_scalar(input)
        local holes = { frame_offset_hole("native.hole.abi.micro." .. self:native_abi_micro_op_token() .. ".src") }
        append_complete_abi_source(out, input, self, scalar, holes, { "    volatile " .. scalar:native_c_scalar_type() .. " value = " .. frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";", "    (void)value;" })
    end
    function Native.NativeAbiMicroOpResultSretShape:append_native_template_sources(out, input)
        append_complete_abi_source(out, input, self, complete_pointer_scalar(input), {}, { "    (void)frame;" })
    end
    function Native.NativeAbiMicroOpResultVoidShape:append_native_template_sources(out, input)
        append_complete_abi_source(out, input, self, complete_pointer_scalar(input), {}, { "    (void)frame;" })
    end
    local function append_complete_abi_call(out, input, shape, suffix, indirect, closure)
        local scalar = complete_pointer_scalar(input)
        local token = shape:native_abi_micro_op_token()
        local holes = {}
        if indirect or closure then holes[#holes + 1] = frame_offset_hole("native.hole.abi.micro." .. token .. ".fn") else holes[#holes + 1] = call_rel32_hole("native.hole.abi.micro." .. token .. ".target") end
        if closure then holes[#holes + 1] = frame_offset_hole("native.hole.abi.micro." .. token .. ".env") end
        local next_symbol = Support.next_continuation_symbol()
        local lines = { "typedef void (*lalin_native_abi_call_t)(uint8_t *frame);" }
        if indirect or closure then
            lines[#lines + 1] = "    lalin_native_abi_call_t fn = (lalin_native_abi_call_t)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";"
            if closure then lines[#lines + 1] = "    (void)" .. frame_load("uintptr_t", hole_address_expr(holes[2])) .. ";" end
            lines[#lines + 1] = "    fn(frame);"
        else
            lines[#lines + 1] = "    extern void " .. holes[1].symbol .. "(uint8_t *frame);"
            lines[#lines + 1] = "    " .. holes[1].symbol .. "(frame);"
        end
        append_complete_abi_source(out, input, shape, scalar, holes, lines)
    end
    function Native.NativeAbiMicroOpCallDirectShape:append_native_template_sources(out, input) append_complete_abi_call(out, input, self, "direct", false, false) end
    function Native.NativeAbiMicroOpCallExternShape:append_native_template_sources(out, input) append_complete_abi_call(out, input, self, "extern", false, false) end
    function Native.NativeAbiMicroOpCallIndirectShape:append_native_template_sources(out, input) append_complete_abi_call(out, input, self, "indirect", true, false) end
    function Native.NativeAbiMicroOpCallClosureShape:append_native_template_sources(out, input) append_complete_abi_call(out, input, self, "closure", true, true) end
    function Native.NativeAbiMicroOpReturnVoidShape:append_native_template_sources(out, input)
        append_complete_abi_source(out, input, self, complete_pointer_scalar(input), {}, { "    (void)frame;", "    return;" }, true)
    end
    function Native.NativeAbiMicroOpReturnScalarShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_scalar_pointer_scalar(input)
        local token = self:native_abi_micro_op_token()
        local holes = { frame_offset_hole("native.hole.abi.micro." .. token .. ".src") }
        local family = Support.abi_micro_op_frame_family(token, complete_target(input), scalar, self)
        local entry = "lalin_native_abi_micro_" .. symbol_fragment(token)
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = scalar:native_c_scalar_type() .. " " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    return " .. frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "abi.micro." .. token, family, Native.NativeChunkPublicAbiAdapter, scalar_frame_signature(scalar, 1, {}), Native.NativeExtractTerminalContinuation, entry, lines, holes, {})
    end
    function Native.NativeAbiMicroOpReturnSretShape:append_native_template_sources(out, input)
        append_complete_abi_source(out, input, self, complete_pointer_scalar(input), {}, { "    (void)frame;", "    return;" }, true)
    end

    function Native.NativeReducerClass:native_complete_reducer_token()
        return self.reduction:native_kernel_reduction_token() .. "." .. self.value_class:native_complete_value_token()
    end

    function Native.NativeCallClass:native_complete_call_token()
        internal_error("unsupported complete call class token")
    end
    function Native.NativeCallDirectClass:native_complete_call_token() return "direct" end
    function Native.NativeCallExternClass:native_complete_call_token() return "extern" end
    function Native.NativeCallIndirectClass:native_complete_call_token() return "indirect" end
    function Native.NativeCallClosureClass:native_complete_call_token() return "closure" end

    function Native.NativeKernelMicroOpShape:native_kernel_micro_op_token()
        internal_error("unsupported Kernel complete-bank micro-op token")
    end
    function Native.NativeKernelMicroOpScalarLoadShape:native_kernel_micro_op_token() return "scalar_load." .. self.scalar:native_scalar_token() end
    function Native.NativeKernelMicroOpScalarStoreShape:native_kernel_micro_op_token() return "scalar_store." .. self.scalar:native_scalar_token() end
    function Native.NativeKernelMicroOpPointerLoadShape:native_kernel_micro_op_token() return "pointer_load." .. self.pointer_scalar:native_scalar_token() end
    function Native.NativeKernelMicroOpPointerStoreShape:native_kernel_micro_op_token() return "pointer_store." .. self.pointer_scalar:native_scalar_token() end
    function Native.NativeKernelMicroOpBytesCopyShape:native_kernel_micro_op_token() return "bytes_copy" end
    function Native.NativeKernelMicroOpBytesMoveShape:native_kernel_micro_op_token() return "bytes_move" end
    function Native.NativeKernelMicroOpLaneAddressBaseShape:native_kernel_micro_op_token() return "lane_address_base" end
    function Native.NativeKernelMicroOpLaneAddressAddIndexShape:native_kernel_micro_op_token() return "lane_address_add_index" end
    function Native.NativeKernelMicroOpLaneAddressAddStrideShape:native_kernel_micro_op_token() return "lane_address_add_stride" end
    function Native.NativeKernelMicroOpLaneAddressAddOffsetShape:native_kernel_micro_op_token() return "lane_address_add_offset" end
    function Native.NativeKernelMicroOpExprConstShape:native_kernel_micro_op_token() return "expr_const." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprCodeValueShape:native_kernel_micro_op_token() return "expr_code_value." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprKernelValueShape:native_kernel_micro_op_token() return "expr_kernel_value." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprLaneLoadShape:native_kernel_micro_op_token() return "expr_lane_load." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprUnaryShape:native_kernel_micro_op_token() return "expr_unary." .. self.op:native_unary_family_name() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprBinaryShape:native_kernel_micro_op_token() return "expr_binary." .. self.op:native_binary_family_name() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprCastShape:native_kernel_micro_op_token() return "expr_cast." .. self.op:native_cast_family_name() .. "." .. self.from_class:native_complete_value_token() .. ".to." .. self.to_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprCompareShape:native_kernel_micro_op_token() return "expr_compare." .. self.cmp:native_compare_family_name() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpExprSelectShape:native_kernel_micro_op_token() return "expr_select." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpAffineInitShape:native_kernel_micro_op_token() return "affine_init." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpAffineAddTermShape:native_kernel_micro_op_token() return "affine_add_term." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpAffineFinishShape:native_kernel_micro_op_token() return "affine_finish." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpPredicateNonZeroShape:native_kernel_micro_op_token() return "predicate_nonzero" end
    function Native.NativeKernelMicroOpPredicateCompareConstShape:native_kernel_micro_op_token() return "predicate_compare_const." .. self.cmp:native_compare_family_name() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpPredicateRangeShape:native_kernel_micro_op_token() return "predicate_range." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpPredicateLogicalInitShape:native_kernel_micro_op_token() return "predicate_logical_init" end
    function Native.NativeKernelMicroOpPredicateLogicalTermShape:native_kernel_micro_op_token() return "predicate_logical_term" end
    function Native.NativeKernelMicroOpPredicateLogicalFinishShape:native_kernel_micro_op_token() return "predicate_logical_finish" end
    function Native.NativeKernelMicroOpPredicateFloatClassShape:native_kernel_micro_op_token() return "predicate_float_class." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpLoopEnterShape:native_kernel_micro_op_token() return "loop_enter" end
    function Native.NativeKernelMicroOpLoopStepShape:native_kernel_micro_op_token() return "loop_step" end
    function Native.NativeKernelMicroOpLoopExitShape:native_kernel_micro_op_token() return "loop_exit" end
    function Native.NativeKernelMicroOpBodyEnterShape:native_kernel_micro_op_token() return "body_enter" end
    function Native.NativeKernelMicroOpBodyNextShape:native_kernel_micro_op_token() return "body_next" end
    function Native.NativeKernelMicroOpBodyExitShape:native_kernel_micro_op_token() return "body_exit" end
    function Native.NativeKernelMicroOpEffectStoreShape:native_kernel_micro_op_token() return "effect_store" end
    function Native.NativeKernelMicroOpEffectCopyShape:native_kernel_micro_op_token() return "effect_copy" end
    function Native.NativeKernelMicroOpEffectScanShape:native_kernel_micro_op_token() return "effect_scan." .. self.scan_mode:native_kernel_scan_token() .. "." .. self.reducer_class:native_complete_reducer_token() end
    function Native.NativeKernelMicroOpEffectPartitionShape:native_kernel_micro_op_token() return "effect_partition." .. self.partition_semantics:native_kernel_partition_token() end
    function Native.NativeKernelMicroOpEffectScatterReduceShape:native_kernel_micro_op_token() return "effect_scatter_reduce." .. self.reducer_class:native_complete_reducer_token() end
    function Native.NativeKernelMicroOpEffectFoldShape:native_kernel_micro_op_token() return "effect_fold." .. self.reducer_class:native_complete_reducer_token() end
    function Native.NativeKernelMicroOpEffectCallShape:native_kernel_micro_op_token() return "effect_call." .. self.call_class:native_complete_call_token() end
    function Native.NativeKernelMicroOpResultVoidShape:native_kernel_micro_op_token() return "result_void" end
    function Native.NativeKernelMicroOpResultValueShape:native_kernel_micro_op_token() return "result_value." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpResultFindShape:native_kernel_micro_op_token() return "result_find." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpResultReductionShape:native_kernel_micro_op_token() return "result_reduction." .. self.reducer_class:native_complete_reducer_token() end
    function Native.NativeKernelMicroOpResultClosedFormShape:native_kernel_micro_op_token() return "result_closed_form." .. self.value_class:native_complete_value_token() end
    function Native.NativeKernelMicroOpResultOriginalControlShape:native_kernel_micro_op_token() return "result_original_control" end

    local function append_complete_kernel_source(out, input, shape, scalar, holes, body, chunk_class, extra_relocation_kinds)
        local token = shape:native_kernel_micro_op_token()
        local family = Support.kernel_micro_op_frame_family(token, complete_target(input), scalar, shape)
        local entry = "lalin_native_kernel_micro_" .. symbol_fragment(token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes or {})
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        append_hole_relocation_markers(lines, holes)
        for _, line in ipairs(body or {}) do lines[#lines + 1] = line end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "kernel.micro." .. token, family, chunk_class or Native.NativeChunkKernelOp, scalar_frame_signature(scalar, #(holes or {}), { Support.next_continuation_ordinal() }), Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes or {}, { Support.next_continuation_ordinal() }, extra_relocation_kinds or {})
    end

    function Native.NativeKernelMicroOpShape:append_native_template_sources(_out, _input)
        internal_error("unsupported Kernel complete-bank micro-op source builder")
    end

    local function append_kernel_scalar_load(out, input, shape, scalar, suffix)
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. suffix .. ".addr"), frame_offset_hole("native.hole.kernel.micro." .. suffix .. ".dst") }
        append_complete_kernel_source(out, input, shape, scalar, holes, { "    uintptr_t addr = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";", frame_store(c_type, hole_address_expr(holes[2]), "*(" .. c_type .. " *)(void *)addr") })
    end
    local function append_kernel_scalar_store(out, input, shape, scalar, suffix)
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. suffix .. ".addr"), frame_offset_hole("native.hole.kernel.micro." .. suffix .. ".src") }
        append_complete_kernel_source(out, input, shape, scalar, holes, { "    uintptr_t addr = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";", "    *(" .. c_type .. " *)(void *)addr = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";" })
    end
    function Native.NativeKernelMicroOpScalarLoadShape:append_native_template_sources(out, input) append_kernel_scalar_load(out, input, self, self.scalar, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpScalarStoreShape:append_native_template_sources(out, input) append_kernel_scalar_store(out, input, self, self.scalar, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpPointerLoadShape:append_native_template_sources(out, input) append_kernel_scalar_load(out, input, self, self.pointer_scalar, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpPointerStoreShape:append_native_template_sources(out, input) append_kernel_scalar_store(out, input, self, self.pointer_scalar, self:native_kernel_micro_op_token()) end
    local function append_kernel_bytes_copy(out, input, shape, move)
        local scalar = complete_pointer_scalar(input)
        local token = shape:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".src"), imm32_hole("native.hole.kernel.micro." .. token .. ".size") }
        append_complete_kernel_source(out, input, shape, scalar, holes, complete_byte_copy_body(holes, move))
    end
    function Native.NativeKernelMicroOpBytesCopyShape:append_native_template_sources(out, input) append_kernel_bytes_copy(out, input, self, false) end
    function Native.NativeKernelMicroOpBytesMoveShape:append_native_template_sources(out, input) append_kernel_bytes_copy(out, input, self, true) end

    local function append_kernel_address(out, input, shape, expr)
        local scalar = complete_pointer_scalar(input)
        local token = shape:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".base"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".index"), imm32_hole("native.hole.kernel.micro." .. token .. ".payload"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        append_complete_kernel_source(out, input, shape, scalar, holes, { "    uintptr_t base = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";", "    uintptr_t index = " .. frame_load("uintptr_t", hole_address_expr(holes[2])) .. ";", frame_store("uintptr_t", hole_address_expr(holes[4]), expr("base", "index", hole_address_expr(holes[3]))) })
    end
    function Native.NativeKernelMicroOpLaneAddressBaseShape:append_native_template_sources(out, input) append_kernel_address(out, input, self, function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeKernelMicroOpLaneAddressAddIndexShape:append_native_template_sources(out, input) append_kernel_address(out, input, self, function(base, index, payload) return base .. " + (" .. index .. " * (uintptr_t)" .. payload .. ")" end) end
    function Native.NativeKernelMicroOpLaneAddressAddStrideShape:append_native_template_sources(out, input) append_kernel_address(out, input, self, function(base, index, payload) return base .. " + " .. index .. " + (uintptr_t)" .. payload end) end
    function Native.NativeKernelMicroOpLaneAddressAddOffsetShape:append_native_template_sources(out, input) append_kernel_address(out, input, self, function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end

    local function append_kernel_value_copy(out, input, shape, value_class, suffix)
        local scalar = value_class:native_complete_value_scalar(input)
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. suffix .. ".src"), frame_offset_hole("native.hole.kernel.micro." .. suffix .. ".dst") }
        append_complete_kernel_source(out, input, shape, scalar, holes, { frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[2]), frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1]))) })
    end
    function Native.NativeKernelMicroOpExprConstShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_value_scalar(input)
        local token = self:native_kernel_micro_op_token()
        local holes = { scalar_immediate_hole("native.hole.kernel.micro." .. token, scalar), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        append_complete_kernel_source(out, input, self, scalar, holes, { frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[2]), "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(holes[1])) })
    end
    function Native.NativeKernelMicroOpExprCodeValueShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpExprKernelValueShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpExprLaneLoadShape:append_native_template_sources(out, input) append_kernel_scalar_load(out, input, self, self.value_class:native_complete_value_scalar(input), self:native_kernel_micro_op_token()) end

    function Native.NativeKernelMicroOpExprUnaryShape:append_native_template_sources(out, input)
        local scalar, name, token = self.value_class:native_complete_value_scalar(input), self.op:native_unary_family_name(), self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".src"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        local result_type = name == "not" and "uint8_t" or scalar:native_c_scalar_type()
        local is_float = asdl.isa(scalar, Native.NativeScalarFloat)
        local expr = is_float and "(-src)" or self.op:native_integer_c_expr(scalar, "src")
        local extra_relocations = is_float and { Native.NativeTemplateRelocationConstantPool } or {}
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. scalar:native_c_scalar_type() .. " src = " .. frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";", frame_store(result_type, hole_address_expr(holes[2]), expr) }, nil, extra_relocations)
    end
    function Native.NativeKernelMicroOpExprBinaryShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_kernel_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".lhs"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".rhs"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        local expr = asdl.isa(scalar, Native.NativeScalarFloat) and self.op:native_float_c_expr(scalar, "lhs", "rhs") or self.op:native_integer_c_expr(scalar, "lhs", "rhs")
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. c_type .. " lhs = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " rhs = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";", frame_store(c_type, hole_address_expr(holes[3]), expr) })
    end
    function Native.NativeKernelMicroOpExprCastShape:append_native_template_sources(out, input)
        local from_scalar, to_scalar, token = self.from_class:native_complete_value_scalar(input), self.to_class:native_complete_value_scalar(input), self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".src"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        local lines = { "    " .. from_scalar:native_c_scalar_type() .. " source_value = " .. frame_load(from_scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";" }
        self.op:append_native_cast_c_lines(lines, from_scalar, to_scalar, "source_value", "cast_value")
        lines[#lines + 1] = frame_store(to_scalar:native_c_scalar_type(), hole_address_expr(holes[2]), "cast_value")
        append_complete_kernel_source(out, input, self, to_scalar, holes, lines, nil, self.op:native_cast_extra_relocation_kinds())
    end
    function Native.NativeKernelMicroOpExprCompareShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_kernel_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".lhs"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".rhs"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. c_type .. " lhs = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " rhs = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";", frame_store("uint8_t", hole_address_expr(holes[3]), self.cmp:native_c_compare_expr(scalar, "lhs", "rhs")) })
    end
    function Native.NativeKernelMicroOpExprSelectShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_kernel_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".cond"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".true"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".false"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        append_complete_kernel_source(out, input, self, scalar, holes, { "    uint8_t cond = " .. frame_load("uint8_t", hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " t = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";", "    " .. c_type .. " f = " .. frame_load(c_type, hole_address_expr(holes[3])) .. ";", frame_store(c_type, hole_address_expr(holes[4]), "cond ? t : f") })
    end

    function Native.NativeKernelMicroOpAffineInitShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpAffineAddTermShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_kernel_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".acc"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".term"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        local expr = asdl.isa(scalar, Native.NativeScalarFloat) and Core.BinAdd:native_float_c_expr(scalar, "acc", "term") or Core.BinAdd:native_integer_c_expr(scalar, "acc", "term")
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. c_type .. " acc = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " term = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";", frame_store(c_type, hole_address_expr(holes[3]), expr) })
    end
    function Native.NativeKernelMicroOpAffineFinishShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpPredicateNonZeroShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, Support.complete_value_scalar_class(Support.scalar_bool8()), self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpPredicateCompareConstShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_kernel_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".src"), scalar_immediate_hole("native.hole.kernel.micro." .. token .. ".const", scalar), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. c_type .. " src = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " k = (" .. c_type .. ")" .. hole_address_expr(holes[2]) .. ";", frame_store("uint8_t", hole_address_expr(holes[3]), self.cmp:native_c_compare_expr(scalar, "src", "k")) })
    end
    function Native.NativeKernelMicroOpPredicateRangeShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpPredicateLogicalInitShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, Support.complete_value_scalar_class(Support.scalar_bool8()), self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpPredicateLogicalTermShape:append_native_template_sources(out, input)
        local scalar, token = Support.scalar_bool8(), self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".acc"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".term"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        append_complete_kernel_source(out, input, self, scalar, holes, { "    uint8_t acc = " .. frame_load("uint8_t", hole_address_expr(holes[1])) .. ";", "    uint8_t term = " .. frame_load("uint8_t", hole_address_expr(holes[2])) .. ";", frame_store("uint8_t", hole_address_expr(holes[3]), "(uint8_t)(acc && term)") })
    end
    function Native.NativeKernelMicroOpPredicateLogicalFinishShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, Support.complete_value_scalar_class(Support.scalar_bool8()), self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpPredicateFloatClassShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, Support.complete_value_scalar_class(Support.scalar_bool8()), self:native_kernel_micro_op_token()) end

    local function append_kernel_control(out, input, shape)
        append_complete_kernel_source(out, input, shape, complete_pointer_scalar(input), {}, { "    __asm__ volatile(\"\" ::: \"memory\");" })
    end
    function Native.NativeKernelMicroOpLoopEnterShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end
    function Native.NativeKernelMicroOpLoopStepShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end
    function Native.NativeKernelMicroOpLoopExitShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end
    function Native.NativeKernelMicroOpBodyEnterShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end
    function Native.NativeKernelMicroOpBodyNextShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end
    function Native.NativeKernelMicroOpBodyExitShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end

    function Native.NativeKernelMicroOpEffectStoreShape:append_native_template_sources(out, input) append_kernel_scalar_store(out, input, self, complete_pointer_scalar(input), self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpEffectCopyShape:append_native_template_sources(out, input) append_kernel_bytes_copy(out, input, self, false) end
    function Native.NativeKernelMicroOpEffectScanShape:append_native_template_sources(out, input)
        local scalar = self.reducer_class.value_class:native_complete_value_scalar(input)
        local token = self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".state"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".value"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        local c_type = scalar:native_c_scalar_type()
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. c_type .. " old_value = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " next_value = " .. self.reducer_class.reduction:native_kernel_reduce_expr(scalar, "old_value", frame_load(c_type, hole_address_expr(holes[2]))) .. ";", frame_store(c_type, hole_address_expr(holes[1]), "next_value"), frame_store(c_type, hole_address_expr(holes[3]), self.scan_mode == T.LalinStencil.StencilScanExclusive and "old_value" or "next_value") })
    end
    function Native.NativeKernelMicroOpEffectPartitionShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end
    function Native.NativeKernelMicroOpEffectScatterReduceShape:append_native_template_sources(out, input)
        local scalar = self.reducer_class.value_class:native_complete_value_scalar(input)
        local token = self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".address"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".value") }
        local c_type = scalar:native_c_scalar_type()
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. c_type .. " *dst = (" .. c_type .. " *)(void *)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " old_value = *dst;", "    *dst = " .. self.reducer_class.reduction:native_kernel_reduce_expr(scalar, "old_value", frame_load(c_type, hole_address_expr(holes[2]))) .. ";" })
    end
    function Native.NativeKernelMicroOpEffectFoldShape:append_native_template_sources(out, input)
        local scalar = self.reducer_class.value_class:native_complete_value_scalar(input)
        local token = self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".state"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".value") }
        append_complete_kernel_source(out, input, self, scalar, holes, { "    " .. scalar:native_c_scalar_type() .. " old_value = " .. frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";", frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[1]), self.reducer_class.reduction:native_kernel_reduce_expr(scalar, "old_value", frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[2])))) })
    end
    function Native.NativeKernelMicroOpEffectCallShape:append_native_template_sources(out, input)
        local scalar = complete_pointer_scalar(input)
        local token = self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".fn") }
        if asdl.isa(self.call_class, Native.NativeCallClosureClass) then holes[#holes + 1] = frame_offset_hole("native.hole.kernel.micro." .. token .. ".env") end
        local lines = { "    typedef void (*lalin_native_kernel_call_t)(uint8_t *frame);", "    lalin_native_kernel_call_t fn = (lalin_native_kernel_call_t)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";" }
        if holes[2] ~= nil then lines[#lines + 1] = "    (void)" .. frame_load("uintptr_t", hole_address_expr(holes[2])) .. ";" end
        lines[#lines + 1] = "    fn(frame);"
        append_complete_kernel_source(out, input, self, scalar, holes, lines)
    end

    function Native.NativeKernelMicroOpResultVoidShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end
    function Native.NativeKernelMicroOpResultValueShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpResultFindShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpResultReductionShape:append_native_template_sources(out, input)
        local scalar = self.reducer_class.value_class:native_complete_value_scalar(input)
        local token = self:native_kernel_micro_op_token()
        local holes = { frame_offset_hole("native.hole.kernel.micro." .. token .. ".state"), frame_offset_hole("native.hole.kernel.micro." .. token .. ".dst") }
        append_complete_kernel_source(out, input, self, scalar, holes, { frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[2]), frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1]))) })
    end
    function Native.NativeKernelMicroOpResultClosedFormShape:append_native_template_sources(out, input) append_kernel_value_copy(out, input, self, self.value_class, self:native_kernel_micro_op_token()) end
    function Native.NativeKernelMicroOpResultOriginalControlShape:append_native_template_sources(out, input) append_kernel_control(out, input, self) end

    function Native.NativePredicateClass:native_complete_predicate_token()
        internal_error("unsupported complete predicate class token")
    end
    function Native.NativePredicateNonZeroClass:native_complete_predicate_token() return "nonzero" end
    function Native.NativePredicateCompareConstClass:native_complete_predicate_token() return "compare_const." .. self.cmp:native_compare_family_name() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativePredicateRangeClass:native_complete_predicate_token() return "range." .. self.value_class:native_complete_value_token() end
    function Native.NativePredicateLogicalClass:native_complete_predicate_token() return "logical" end
    function Native.NativePredicateFloatClass:native_complete_predicate_token() return "float_class." .. self.value_class:native_complete_value_token() end

    function Native.NativeDescriptorUserFieldKind:native_complete_descriptor_user_field_token()
        internal_error("unsupported descriptor user field kind token")
    end
    function Native.NativeDescriptorUserElementSizeField:native_complete_descriptor_user_field_token() return "element_size" end
    function Native.NativeDescriptorUserCapacityField:native_complete_descriptor_user_field_token() return "capacity" end
    function Native.NativeDescriptorUserAlignmentField:native_complete_descriptor_user_field_token() return "alignment" end
    function Native.NativeDescriptorUserLengthField:native_complete_descriptor_user_field_token() return "user_length" end

    function Native.NativeDescriptorFieldClass:native_complete_descriptor_field_token()
        internal_error("unsupported descriptor field class token")
    end
    function Native.NativeDescriptorDataField:native_complete_descriptor_field_token() return "data" end
    function Native.NativeDescriptorLengthField:native_complete_descriptor_field_token() return "length" end
    function Native.NativeDescriptorStrideField:native_complete_descriptor_field_token() return "stride" end
    function Native.NativeDescriptorBaseField:native_complete_descriptor_field_token() return "base" end
    function Native.NativeDescriptorUserField:native_complete_descriptor_field_token() return "user." .. self.kind:native_complete_descriptor_user_field_token() end

    function Native.NativeStencilStoreSemanticsClass:native_complete_store_token()
        internal_error("unsupported stencil store semantics class token")
    end
    function Native.NativeStencilStoreElementwiseClass:native_complete_store_token() return "elementwise" end
    function Native.NativeStencilStoreCopyClass:native_complete_store_token() return "copy." .. self.copy_semantics:native_kernel_copy_token() end
    function Native.NativeStencilStoreScatterClass:native_complete_store_token() return "scatter." .. self.conflict_semantics:native_stencil_scatter_conflict_token() end
    function Native.NativeStencilStorePartitionClass:native_complete_store_token() return "partition." .. self.partition_semantics:native_kernel_partition_token() end

    function Native.NativeStencilReduceScopeClass:native_complete_reduce_scope_token()
        internal_error("unsupported stencil reduce scope class token")
    end
    function Native.NativeStencilReduceScopeDomainClass:native_complete_reduce_scope_token() return "domain" end
    function Native.NativeStencilReduceScopeAxesClass:native_complete_reduce_scope_token() return "axes" end
    function Native.NativeStencilReduceScopeWindowClass:native_complete_reduce_scope_token() return "window" end

    function Native.NativeStencilScatterReduceConflictClass:native_complete_scatter_reduce_conflict_token()
        internal_error("unsupported stencil scatter-reduce conflict class token")
    end
    function Native.NativeStencilScatterReduceSequentialClass:native_complete_scatter_reduce_conflict_token() return "sequential" end
    function Native.NativeStencilScatterReduceUniqueIndicesClass:native_complete_scatter_reduce_conflict_token() return "unique" end
    function Native.NativeStencilScatterReduceAtomicClass:native_complete_scatter_reduce_conflict_token() return "atomic." .. self.ordering:native_atomic_order_token() end
    function Native.NativeStencilScatterReducePrivatizedClass:native_complete_scatter_reduce_conflict_token() return "privatized" end

    function Native.NativeVectorCapabilityClass:native_complete_vector_token()
        internal_error("unsupported vector capability token")
    end
    function Native.NativeVectorDisabled:native_complete_vector_token() return "disabled" end
    function Native.NativeVectorNative:native_complete_vector_token() return "native" end
    function Native.NativeVectorSSE2:native_complete_vector_token() return "sse2" end
    function Native.NativeVectorAVX2:native_complete_vector_token() return "avx2" end
    function Native.NativeVectorAVX512F:native_complete_vector_token() return "avx512f" end

    function Native.NativeUnrollCapabilityClass:native_complete_unroll_token()
        internal_error("unsupported unroll capability token")
    end
    function Native.NativeUnrollScalar:native_complete_unroll_token() return "scalar" end
    function Native.NativeUnrollFixed:native_complete_unroll_token() return "fixed" .. tostring(self.factor) end

    function Native.NativeStencilMicroOpShape:native_stencil_micro_op_token()
        internal_error("unsupported Stencil complete-bank micro-op token")
    end
    function Native.NativeStencilMicroOpProducerEnterShape:native_stencil_micro_op_token() return "producer_enter" end
    function Native.NativeStencilMicroOpProducerAxisStepShape:native_stencil_micro_op_token() return "producer_axis_step." .. self.order_class:native_stencil_order_token() end
    function Native.NativeStencilMicroOpProducerAxisExitShape:native_stencil_micro_op_token() return "producer_axis_exit" end
    function Native.NativeStencilMicroOpProducerWindowOffsetShape:native_stencil_micro_op_token() return "producer_window_offset" end
    function Native.NativeStencilMicroOpProducerTileStepShape:native_stencil_micro_op_token() return "producer_tile_step" end
    function Native.NativeStencilMicroOpAccessBaseShape:native_stencil_micro_op_token() return "access_base." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpAccessContiguousShape:native_stencil_micro_op_token() return "access_contiguous." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpAccessIndexedShape:native_stencil_micro_op_token() return "access_indexed." .. self.value_class:native_complete_value_token() .. ".index" .. tostring(self.index_class.pointer_width) end
    function Native.NativeStencilMicroOpAccessAffineInitShape:native_stencil_micro_op_token() return "access_affine_init." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpAccessAffineTermShape:native_stencil_micro_op_token() return "access_affine_term." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpAccessFieldOffsetShape:native_stencil_micro_op_token() return "access_field_offset." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpAccessSoAComponentShape:native_stencil_micro_op_token() return "access_soa_component." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpAccessDescriptorFieldShape:native_stencil_micro_op_token() return "access_descriptor_field." .. self.descriptor_field_class:native_complete_descriptor_field_token() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointInputShape:native_stencil_micro_op_token() return "point_input." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointWindowInputShape:native_stencil_micro_op_token() return "point_window_input." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointConstShape:native_stencil_micro_op_token() return "point_const." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointUnaryShape:native_stencil_micro_op_token() return "point_unary." .. self.op:native_stencil_unary_token() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointBinaryShape:native_stencil_micro_op_token() return "point_binary." .. self.op:native_stencil_binary_token() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointCastShape:native_stencil_micro_op_token() return "point_cast." .. self.op:native_cast_family_name() .. "." .. self.from_class:native_complete_value_token() .. ".to." .. self.to_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointPredicateShape:native_stencil_micro_op_token() return "point_predicate." .. self.predicate_class:native_complete_predicate_token() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointCompareShape:native_stencil_micro_op_token() return "point_compare." .. self.cmp:native_compare_family_name() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpPointSelectShape:native_stencil_micro_op_token() return "point_select." .. self.predicate_class:native_complete_predicate_token() .. "." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpBodyEnterShape:native_stencil_micro_op_token() return "body_enter" end
    function Native.NativeStencilMicroOpBodyPointShape:native_stencil_micro_op_token() return "body_point." .. self.value_class:native_complete_value_token() end
    function Native.NativeStencilMicroOpBodyExitShape:native_stencil_micro_op_token() return "body_exit" end
    function Native.NativeStencilMicroOpSinkStoreShape:native_stencil_micro_op_token() return "sink_store." .. self.store_semantics_class:native_complete_store_token() end
    function Native.NativeStencilMicroOpSinkReduceShape:native_stencil_micro_op_token() return "sink_reduce." .. self.reducer_class:native_complete_reducer_token() .. "." .. self.reduce_scope_class:native_complete_reduce_scope_token() end
    function Native.NativeStencilMicroOpSinkScanShape:native_stencil_micro_op_token() return "sink_scan." .. self.scan_mode:native_kernel_scan_token() .. "." .. self.reducer_class:native_complete_reducer_token() end
    function Native.NativeStencilMicroOpSinkScatterReduceShape:native_stencil_micro_op_token() return "sink_scatter_reduce." .. self.reducer_class:native_complete_reducer_token() .. "." .. self.scatter_reduce_conflict_class:native_complete_scatter_reduce_conflict_token() end
    function Native.NativeStencilMicroOpScheduleScalarShape:native_stencil_micro_op_token() return "schedule_scalar" end
    function Native.NativeStencilMicroOpScheduleAutoVectorShape:native_stencil_micro_op_token() return "schedule_autovector." .. self.vector_capability_class:native_complete_vector_token() end
    function Native.NativeStencilMicroOpScheduleUnrolledShape:native_stencil_micro_op_token() return "schedule_unrolled." .. self.unroll_capability_class:native_complete_unroll_token() end
    function Native.NativeStencilMicroOpScheduleVectorShape:native_stencil_micro_op_token() return "schedule_vector." .. self.vector_capability_class:native_complete_vector_token() end

    local function append_complete_stencil_source(out, input, shape, scalar, holes, body, extra_relocation_kinds)
        local token = shape:native_stencil_micro_op_token()
        local family = Support.stencil_micro_op_frame_family(token, complete_target(input), scalar, shape)
        local entry = "lalin_native_stencil_micro_" .. symbol_fragment(token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes or {})
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        append_hole_relocation_markers(lines, holes)
        for _, line in ipairs(body or {}) do lines[#lines + 1] = line end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "stencil.micro." .. token, family, Native.NativeChunkStencilOp, scalar_frame_signature(scalar, #(holes or {}), { Support.next_continuation_ordinal() }), Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes or {}, { Support.next_continuation_ordinal() }, extra_relocation_kinds or {})
    end

    function Native.NativeStencilMicroOpShape:append_native_template_sources(_out, _input)
        internal_error("unsupported Stencil complete-bank micro-op source builder")
    end

    local function append_stencil_control(out, input, shape)
        append_complete_stencil_source(out, input, shape, complete_pointer_scalar(input), {}, { "    __asm__ volatile(\"\" ::: \"memory\");" })
    end
    function Native.NativeStencilMicroOpProducerEnterShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpProducerAxisStepShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpProducerAxisExitShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpProducerWindowOffsetShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpProducerTileStepShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end

    local function append_stencil_address(out, input, shape, value_class, expr)
        local scalar = complete_pointer_scalar(input)
        local token = shape:native_stencil_micro_op_token()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".base"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".index"), imm32_hole("native.hole.stencil.micro." .. token .. ".payload"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        append_complete_stencil_source(out, input, shape, scalar, holes, { "    uintptr_t base = " .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";", "    uintptr_t index = " .. frame_load("uintptr_t", hole_address_expr(holes[2])) .. ";", "    (void)sizeof(" .. value_class:native_complete_value_scalar(input):native_c_scalar_type() .. ");", frame_store("uintptr_t", hole_address_expr(holes[4]), expr("base", "index", hole_address_expr(holes[3]))) })
    end
    function Native.NativeStencilMicroOpAccessBaseShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeStencilMicroOpAccessContiguousShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, index, payload) return base .. " + (" .. index .. " * (uintptr_t)" .. payload .. ")" end) end
    function Native.NativeStencilMicroOpAccessIndexedShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, index, payload) return base .. " + " .. index .. " + (uintptr_t)" .. payload end) end
    function Native.NativeStencilMicroOpAccessAffineInitShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeStencilMicroOpAccessAffineTermShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, index, payload) return base .. " + (" .. index .. " * (uintptr_t)" .. payload .. ")" end) end
    function Native.NativeStencilMicroOpAccessFieldOffsetShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeStencilMicroOpAccessSoAComponentShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end
    function Native.NativeStencilMicroOpAccessDescriptorFieldShape:append_native_template_sources(out, input) append_stencil_address(out, input, self, self.value_class, function(base, _index, payload) return base .. " + (uintptr_t)" .. payload end) end

    local function append_stencil_value_copy(out, input, shape, value_class)
        local scalar = value_class:native_complete_value_scalar(input)
        local token = shape:native_stencil_micro_op_token()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".src"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        append_complete_stencil_source(out, input, shape, scalar, holes, { frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[2]), frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1]))) })
    end
    function Native.NativeStencilMicroOpPointInputShape:append_native_template_sources(out, input) append_stencil_value_copy(out, input, self, self.value_class) end
    function Native.NativeStencilMicroOpPointWindowInputShape:append_native_template_sources(out, input) append_stencil_value_copy(out, input, self, self.value_class) end
    function Native.NativeStencilMicroOpPointConstShape:append_native_template_sources(out, input)
        local scalar = self.value_class:native_complete_value_scalar(input)
        local token = self:native_stencil_micro_op_token()
        local holes = { scalar_immediate_hole("native.hole.stencil.micro." .. token, scalar), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        append_complete_stencil_source(out, input, self, scalar, holes, { frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[2]), "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(holes[1])) })
    end
    function Native.NativeStencilMicroOpPointUnaryShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_stencil_micro_op_token()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".src"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        local extra_relocations = asdl.isa(scalar, Native.NativeScalarFloat) and { Native.NativeTemplateRelocationConstantPool } or {}
        append_complete_stencil_source(out, input, self, scalar, holes, { "    " .. scalar:native_c_scalar_type() .. " src = " .. frame_load(scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";", frame_store(scalar:native_c_scalar_type(), hole_address_expr(holes[2]), self.op:native_stencil_unary_expr(scalar, "src")) }, extra_relocations)
    end
    function Native.NativeStencilMicroOpPointBinaryShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_stencil_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".lhs"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".rhs"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        append_complete_stencil_source(out, input, self, scalar, holes, { "    " .. c_type .. " lhs = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " rhs = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";", frame_store(c_type, hole_address_expr(holes[3]), self.op:native_stencil_binary_expr(scalar, "lhs", "rhs")) })
    end
    function Native.NativeStencilMicroOpPointCastShape:append_native_template_sources(out, input)
        local from_scalar, to_scalar, token = self.from_class:native_complete_value_scalar(input), self.to_class:native_complete_value_scalar(input), self:native_stencil_micro_op_token()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".src"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        local lines = { "    " .. from_scalar:native_c_scalar_type() .. " source_value = " .. frame_load(from_scalar:native_c_scalar_type(), hole_address_expr(holes[1])) .. ";" }
        self.op:append_native_cast_c_lines(lines, from_scalar, to_scalar, "source_value", "cast_value")
        lines[#lines + 1] = frame_store(to_scalar:native_c_scalar_type(), hole_address_expr(holes[2]), "cast_value")
        append_complete_stencil_source(out, input, self, to_scalar, holes, lines, self.op:native_cast_extra_relocation_kinds())
    end
    function Native.NativeStencilMicroOpPointPredicateShape:append_native_template_sources(out, input) append_stencil_value_copy(out, input, self, Support.complete_value_scalar_class(Support.scalar_bool8())) end
    function Native.NativeStencilMicroOpPointCompareShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_stencil_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".lhs"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".rhs"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        append_complete_stencil_source(out, input, self, scalar, holes, { "    " .. c_type .. " lhs = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " rhs = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";", frame_store("uint8_t", hole_address_expr(holes[3]), self.cmp:native_c_compare_expr(scalar, "lhs", "rhs")) })
    end
    function Native.NativeStencilMicroOpPointSelectShape:append_native_template_sources(out, input)
        local scalar, token = self.value_class:native_complete_value_scalar(input), self:native_stencil_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".pred"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".true"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".false"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        append_complete_stencil_source(out, input, self, scalar, holes, { "    uint8_t pred = " .. frame_load("uint8_t", hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " t = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";", "    " .. c_type .. " f = " .. frame_load(c_type, hole_address_expr(holes[3])) .. ";", frame_store(c_type, hole_address_expr(holes[4]), "pred ? t : f") })
    end

    function Native.NativeStencilMicroOpBodyEnterShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpBodyPointShape:append_native_template_sources(out, input) append_stencil_value_copy(out, input, self, self.value_class) end
    function Native.NativeStencilMicroOpBodyExitShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end

    function Native.NativeStencilMicroOpSinkStoreShape:append_native_template_sources(out, input)
        local scalar = complete_pointer_scalar(input)
        local token = self:native_stencil_micro_op_token()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".addr"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".value"), imm32_hole("native.hole.stencil.micro." .. token .. ".size") }
        append_complete_stencil_source(out, input, self, scalar, holes, {
            "    uint8_t *dst = (uint8_t *)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";",
            "    uint8_t *src = frame + " .. hole_address_expr(holes[2]) .. ";",
            "    uint32_t n = (uint32_t)" .. hole_address_expr(holes[3]) .. ";",
            "    for (uint32_t i = 0; i < n; ++i) { dst[i] = src[i]; }",
        })
    end
    function Native.NativeStencilMicroOpSinkReduceShape:append_native_template_sources(out, input)
        local scalar = self.reducer_class.value_class:native_complete_value_scalar(input)
        local token = self:native_stencil_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".state"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".value") }
        append_complete_stencil_source(out, input, self, scalar, holes, { "    " .. c_type .. " old_value = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", frame_store(c_type, hole_address_expr(holes[1]), self.reducer_class.reduction:native_kernel_reduce_expr(scalar, "old_value", frame_load(c_type, hole_address_expr(holes[2])))) })
    end
    function Native.NativeStencilMicroOpSinkScanShape:append_native_template_sources(out, input)
        local scalar = self.reducer_class.value_class:native_complete_value_scalar(input)
        local token = self:native_stencil_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".state"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".value"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".dst") }
        append_complete_stencil_source(out, input, self, scalar, holes, { "    " .. c_type .. " old_value = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " next_value = " .. self.reducer_class.reduction:native_kernel_reduce_expr(scalar, "old_value", frame_load(c_type, hole_address_expr(holes[2]))) .. ";", frame_store(c_type, hole_address_expr(holes[1]), "next_value"), frame_store(c_type, hole_address_expr(holes[3]), self.scan_mode == Stencil.StencilScanExclusive and "old_value" or "next_value") })
    end
    function Native.NativeStencilMicroOpSinkScatterReduceShape:append_native_template_sources(out, input)
        local scalar = self.reducer_class.value_class:native_complete_value_scalar(input)
        local token = self:native_stencil_micro_op_token()
        local c_type = scalar:native_c_scalar_type()
        local holes = { frame_offset_hole("native.hole.stencil.micro." .. token .. ".addr"), frame_offset_hole("native.hole.stencil.micro." .. token .. ".value") }
        append_complete_stencil_source(out, input, self, scalar, holes, { "    " .. c_type .. " *dst = (" .. c_type .. " *)(void *)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";", "    " .. c_type .. " old_value = *dst;", "    *dst = " .. self.reducer_class.reduction:native_kernel_reduce_expr(scalar, "old_value", frame_load(c_type, hole_address_expr(holes[2]))) .. ";" })
    end

    function Native.NativeStencilMicroOpScheduleScalarShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpScheduleAutoVectorShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpScheduleUnrolledShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end
    function Native.NativeStencilMicroOpScheduleVectorShape:append_native_template_sources(out, input) append_stencil_control(out, input, self) end

    local function append_frame_entry_source(out, input, scalar)
        local token = scalar:native_scalar_token()
        local family_name = "frame_entry." .. token
        local family = Support.code_func_family(family_name, input.domain.target, nil, Support.protocol_void_none())
        local entry = "lalin_native_code_frame_entry_" .. symbol_fragment(token)
        local first = Support.first_continuation_symbol()
        local first_ordinal = Support.first_continuation_ordinal()
        local continuation_signature = Support.stencil_continuation_signature(first_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, {}, { continuation_signature })
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(first, continuation_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. first.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.func." .. family_name,
            family,
            Native.NativeChunkFrameEntry,
            signature,
            Native.NativeExtractEntryCallable(Native.NativePatchFrameSize(FRAME_BYTES), first),
            entry,
            lines,
            {},
            { first_ordinal }
        )
    end

    local function append_entry_source(out, input, param_scalar, result_scalar)
        local param_token = param_scalar:native_scalar_token()
        local result_token = result_scalar:native_scalar_token()
        local family_name = "entry." .. param_token .. ".return." .. result_token
        local family = Support.code_func_frame_family(family_name, input.domain.target, param_scalar, result_scalar)
        local entry = "lalin_native_code_func_" .. symbol_fragment(family_name)
        local param_c = param_scalar:native_c_scalar_type()
        local result_c = result_scalar:native_c_scalar_type()
        local first = Support.first_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(first)
        lines[#lines + 1] = result_c .. " " .. entry .. "(" .. param_c .. " a, " .. param_c .. " b) {"
        lines[#lines + 1] = "    uint8_t frame[" .. tostring(FRAME_BYTES) .. "];"
        lines[#lines + 1] = "    *(" .. param_c .. " *)(void *)(frame + " .. tostring(FRAME_PARAM0_OFFSET) .. ") = a;"
        lines[#lines + 1] = "    *(" .. param_c .. " *)(void *)(frame + " .. tostring(FRAME_PARAM1_OFFSET) .. ") = b;"
        lines[#lines + 1] = "    " .. first.name .. "(frame);"
        lines[#lines + 1] = "    return *(" .. result_c .. " *)(void *)(frame + " .. tostring(FRAME_RESULT_OFFSET) .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.func." .. family_name,
            family,
            Native.NativeChunkStandaloneCallable,
            scalar_frame_signature(param_scalar, 0, { Support.first_continuation_ordinal() }),
            Native.NativeExtractEntryCallable(Native.NativePatchFrameSize(FRAME_BYTES), first),
            entry,
            lines,
            {},
            { Support.first_continuation_ordinal() }
        )
    end

    local function append_terminal_source_for_shape(out, input, shape)
        local token = shape:native_result_shape_token()
        local scalar = shape:native_result_family_scalar(input.domain.target)
        local axis = Native.NativeCodeTermReturnShapeAxis(shape)
        local family = Support.code_term_frame_family("return." .. token, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_term_return_" .. symbol_fragment(token)
        local lines = c_prelude()
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    (void)frame;"
        lines[#lines + 1] = "    return;"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.term.return." .. token,
            family,
            Native.NativeChunkTerminalContinuation,
            scalar_frame_signature(scalar, 0, {}),
            Native.NativeExtractTerminalContinuation,
            entry,
            lines,
            {},
            {}
        )
    end

    local function append_terminal_source(out, input, scalar)
        append_terminal_source_for_shape(out, input, Native.NativeCodeResultScalarShape(scalar))
    end

    local function append_void_terminal_source(out, input)
        append_terminal_source_for_shape(out, input, Native.NativeCodeResultVoidShape)
    end

    local function append_result_copy_source(out, input, shape)
        if asdl.isa(shape, Native.NativeCodeResultVoidShape) then return end
        local token = shape:native_result_shape_token()
        local scalar = shape:native_result_family_scalar(input.domain.target)
        local axis = Native.NativeCodeInstResultCopyAxis(shape)
        local family = Support.code_inst_frame_family("result_copy." .. token, input.domain.target, scalar, axis)
        local id_base = "native.hole.code.inst.result_copy." .. token
        local src_hole = frame_offset_hole(id_base .. ".src")
        local dst_hole = frame_offset_hole(id_base .. ".dst")
        local holes = { src_hole, dst_hole }
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void lalin_native_code_inst_result_copy_" .. symbol_fragment(token) .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    __builtin_memcpy(frame + (uintptr_t)&" .. dst_hole.symbol .. ", frame + (uintptr_t)&" .. src_hole.symbol .. ", " .. tostring(shape:native_result_copy_size(input.domain.target)) .. ");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst.result_copy." .. token,
            family,
            Native.NativeChunkParallelCopy,
            scalar_frame_signature(scalar, 2, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            "lalin_native_code_inst_result_copy_" .. symbol_fragment(token),
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
    end

    local function append_sret_result_copy_source(out, input, shape)
        local token = shape:native_result_shape_token()
        local scalar = shape:native_result_family_scalar(input.domain.target)
        local axis = Native.NativeCodeInstResultCopyAxis(shape)
        local family = Support.code_inst_frame_family("result_copy." .. token, input.domain.target, scalar, axis)
        local id_base = "native.hole.code.inst.result_copy." .. token
        local src_hole = frame_offset_hole(id_base .. ".src")
        local ptr_hole = frame_offset_hole(id_base .. ".sret_ptr")
        local size_hole = imm32_hole(id_base .. ".size")
        local holes = { src_hole, ptr_hole, size_hole }
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void lalin_native_code_inst_result_copy_" .. symbol_fragment(token) .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    uint8_t *dst = (uint8_t *)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(ptr_hole)) .. ";"
        lines[#lines + 1] = "    __builtin_memcpy(dst, frame + (uintptr_t)&" .. src_hole.symbol .. ", (uint32_t)(uintptr_t)&" .. size_hole.symbol .. ");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst.result_copy." .. token,
            family,
            Native.NativeChunkParallelCopy,
            scalar_frame_signature(scalar, 3, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            "lalin_native_code_inst_result_copy_" .. symbol_fragment(token),
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
    end

    local function append_edge_copy_source(out, input, scalar, source_location, dest_location)
        local token = scalar:native_scalar_token()
        local src_token = Support.logical_location_token(source_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_base = "native.hole.code.inst.edge_copy." .. token .. "." .. src_token .. ".to." .. dst_token
        local source_holes = source_location:native_edge_copy_source_holes(id_base, scalar)
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base, scalar)
        local holes = {}
        for _, hole in ipairs(source_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local operands = {
            Support.stencil_operand(0, scalar, source_location),
            Support.stencil_operand(1, scalar, dest_location),
        }
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then
            next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location)
        end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, operands, { next_signature })
        local family_name = "edge_copy." .. token .. "." .. src_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstAliasAxis(scalar:native_code_type())
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_edge_copy_" .. symbol_fragment(token .. "_" .. src_token .. "_to_" .. dst_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = " .. source_location:native_edge_copy_source_expr(scalar, source_holes) .. ";"
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst." .. family_name,
            family,
            Native.NativeChunkEdgeCopy,
            signature,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { next_ordinal }
        )
    end

    local function append_parallel_copy_source(out, input, scalar)
        local token = scalar:native_scalar_token()
        local axis = Native.NativeCodeInstAliasAxis(scalar:native_code_type())
        local family_name = "parallel_copy." .. token .. ".slot.slot.temp"
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_parallel_copy_" .. symbol_fragment(token)
        local holes = {
            frame_offset_hole("native.hole.code.inst.parallel_copy." .. token .. ".src0"),
            frame_offset_hole("native.hole.code.inst.parallel_copy." .. token .. ".src1"),
            frame_offset_hole("native.hole.code.inst.parallel_copy." .. token .. ".dst0"),
            frame_offset_hole("native.hole.code.inst.parallel_copy." .. token .. ".dst1"),
            frame_offset_hole("native.hole.code.inst.parallel_copy." .. token .. ".tmp"),
        }
        local slot_class = Support.location_class_frame_slot()
        local operands = {
            Support.stencil_operand(0, scalar, slot_class),
            Support.stencil_operand(1, scalar, slot_class),
            Support.stencil_operand(2, scalar, slot_class),
            Support.stencil_operand(3, scalar, slot_class),
            Support.stencil_operand(4, scalar, slot_class),
        }
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, operands, { next_signature })
        local c_type = scalar:native_c_scalar_type()
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " first = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(holes[5]), "first")
        lines[#lines + 1] = "    " .. c_type .. " second = " .. frame_load(c_type, hole_address_expr(holes[2])) .. ";"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(holes[4]), "second")
        lines[#lines + 1] = "    " .. c_type .. " saved = " .. frame_load(c_type, hole_address_expr(holes[5])) .. ";"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(holes[3]), "saved")
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst." .. family_name,
            family,
            Native.NativeChunkParallelCopy,
            signature,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { next_ordinal }
        )
    end

    local function append_constant_pool_load_source(out, input, kind, dest_location)
        local scalar = kind:native_constant_load_scalar(input.domain.target)
        local token = scalar:native_scalar_token()
        local kind_token = kind:native_constant_pool_kind_token(input.domain.target)
        local dst_token = Support.logical_location_token(dest_location)
        local hole = ptr64_hole("native.hole.code.const.pool." .. kind_token .. ".to." .. dst_token)
        local holes = { hole }
        local operands = {
            Support.stencil_operand(0, scalar, Support.location_class_constant_pool()),
            Support.stencil_operand(1, scalar, dest_location),
        }
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then
            next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location)
        end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, operands, { next_signature })
        local family_name = "pool." .. kind_token .. ".to." .. dst_token
        local axis = Native.NativeCodeConstLiteralAxis(scalar:native_code_type())
        local family = Support.code_const_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_const_pool_" .. symbol_fragment(kind_token .. "_to_" .. dst_token)
        local next_symbol = Support.next_continuation_symbol()
        if asdl.isa(dest_location, Native.NativeStencilFrameSlotLocationClass) then
            holes[#holes + 1] = frame_offset_hole("native.hole.code.const.pool." .. kind_token .. ".to." .. dst_token .. ".dst")
        end
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = " .. kind:native_constant_load_expr(scalar, hole) .. ";"
        local dest_holes = {}
        if holes[2] ~= nil then dest_holes[1] = holes[2] end
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.const." .. family_name,
            family,
            Native.NativeChunkConstantLoad,
            signature,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { next_ordinal }
        )
    end

    local function append_scalar_copy_sources(out, input, scalar)
        local frame_slot = Support.location_class_frame_slot()
        local cont_arg = Support.location_class_continuation_arg()
        local source_locations = { frame_slot, cont_arg, Support.location_class_constant_pool() }
        if not asdl.isa(scalar, Native.NativeScalarFloat) then
            source_locations[#source_locations + 1] = Support.location_class_immediate()
        end
        for _, source_location in ipairs(source_locations) do
            for _, dest_location in ipairs({ frame_slot, cont_arg }) do
                append_edge_copy_source(out, input, scalar, source_location, dest_location)
            end
        end
        append_parallel_copy_source(out, input, scalar)
    end

    local function append_domain_constant_pool_sources(out, input)
        for _, kind in ipairs((input.domain.constant_pool_support and input.domain.constant_pool_support.entry_kinds) or {}) do
            append_constant_pool_load_source(out, input, kind, Support.location_class_frame_slot())
            append_constant_pool_load_source(out, input, kind, Support.location_class_continuation_arg())
        end
    end

    local function scalar_source_locations(scalar)
        local locations = {
            Support.location_class_frame_slot(),
            Support.location_class_continuation_arg(),
        }
        if not asdl.isa(scalar, Native.NativeScalarFloat) then locations[#locations + 1] = Support.location_class_immediate() end
        return locations
    end

    local function scalar_dest_locations()
        return { Support.location_class_frame_slot(), Support.location_class_continuation_arg() }
    end

    local function source_expr_for_operand(location, scalar, holes, operand_index)
        if asdl.isa(location, Native.NativeStencilContinuationArgLocationClass) then return "arg" .. tostring(operand_index) end
        return location:native_edge_copy_source_expr(scalar, holes)
    end

    local function append_cast_source(out, input, op, from_scalar, to_scalar, source_location, dest_location)
        local from_token = from_scalar:native_scalar_token()
        local to_token = to_scalar:native_scalar_token()
        local src_token = Support.logical_location_token(source_location)
        local dst_token = Support.logical_location_token(dest_location)
        local op_name = op:native_cast_family_name()
        local id_base = "native.hole.code.inst.cast." .. op_name .. "." .. from_token .. ".to." .. to_token .. "." .. src_token .. ".to." .. dst_token
        local source_holes = source_location:native_edge_copy_source_holes(id_base, from_scalar)
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base, to_scalar)
        local holes = {}
        for _, hole in ipairs(source_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local operands = {
            Support.stencil_operand(0, from_scalar, source_location),
            Support.stencil_operand(1, to_scalar, dest_location),
        }
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then
            next_params[#next_params + 1] = Support.stencil_continuation_param(0, to_scalar, dest_location)
        end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(to_scalar, operands, { next_signature })
        local family_name = "cast." .. op_name .. "." .. from_token .. ".to." .. to_token .. "." .. src_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstCastAxis(op, from_scalar:native_code_type(), to_scalar:native_code_type())
        local family = Support.code_inst_frame_family(family_name, input.domain.target, to_scalar, axis)
        local entry = "lalin_native_code_inst_cast_" .. symbol_fragment(op_name .. "_" .. from_token .. "_to_" .. to_token .. "_" .. src_token .. "_to_" .. dst_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. op:native_cast_source_qualifier() .. from_scalar:native_c_scalar_type() .. " source_value = " .. source_expr_for_operand(source_location, from_scalar, source_holes, 0) .. ";"
        op:append_native_cast_c_lines(lines, from_scalar, to_scalar, "source_value", "cast_value")
        local store = dest_location:native_edge_copy_dest_store(to_scalar, dest_holes, "cast_value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("cast_value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst." .. family_name,
            family,
            Native.NativeChunkCastOp,
            signature,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { next_ordinal },
            op:native_cast_extra_relocation_kinds()
        )
    end

    local function append_select_source(out, input, scalar, condition_location, true_location, false_location, dest_location)
        local token = scalar:native_scalar_token()
        local cond_token = Support.logical_location_token(condition_location)
        local true_token = Support.logical_location_token(true_location)
        local false_token = Support.logical_location_token(false_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_base = "native.hole.code.inst.select." .. token .. ".cond." .. cond_token .. ".true." .. true_token .. ".false." .. false_token .. ".to." .. dst_token
        local cond_holes = condition_location:native_edge_copy_source_holes(id_base .. ".cond", Support.scalar_bool8())
        local true_holes = true_location:native_edge_copy_source_holes(id_base .. ".true", scalar)
        local false_holes = false_location:native_edge_copy_source_holes(id_base .. ".false", scalar)
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", scalar)
        local holes = {}
        for _, hole in ipairs(cond_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(true_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(false_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local operands = {
            Support.stencil_operand(0, Support.scalar_bool8(), condition_location),
            Support.stencil_operand(1, scalar, true_location),
            Support.stencil_operand(2, scalar, false_location),
            Support.stencil_operand(3, scalar, dest_location),
        }
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then
            next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location)
        end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, operands, { next_signature })
        local family_name = "select." .. token .. ".cond." .. cond_token .. ".true." .. true_token .. ".false." .. false_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstSelectAxis(scalar:native_code_type())
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_select_" .. symbol_fragment(token .. "_cond_" .. cond_token .. "_true_" .. true_token .. "_false_" .. false_token .. "_to_" .. dst_token)
        local next_symbol = Support.next_continuation_symbol()
        local c_type = scalar:native_c_scalar_type()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uint8_t cond = " .. source_expr_for_operand(condition_location, Support.scalar_bool8(), cond_holes, 0) .. ";"
        lines[#lines + 1] = "    " .. c_type .. " true_value = " .. source_expr_for_operand(true_location, scalar, true_holes, 1) .. ";"
        lines[#lines + 1] = "    " .. c_type .. " false_value = " .. source_expr_for_operand(false_location, scalar, false_holes, 2) .. ";"
        lines[#lines + 1] = "    volatile " .. c_type .. " selected_value = (cond != 0) ? true_value : false_value;"
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "(" .. c_type .. ")selected_value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("selected_value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst." .. family_name,
            family,
            Native.NativeChunkSelectOp,
            signature,
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { next_ordinal }
        )
    end

    local function append_cast_sources_for_scalar(out, input, from_scalar)
        for _, to_support in ipairs(input.domain.scalars or {}) do
            local to_scalar = to_support.scalar
            local op = from_scalar:native_cast_op_to(to_scalar)
            if op ~= nil then
                for _, source_location in ipairs(scalar_source_locations(from_scalar)) do
                    for _, dest_location in ipairs(scalar_dest_locations()) do
                        append_cast_source(out, input, op, from_scalar, to_scalar, source_location, dest_location)
                    end
                end
            end
        end
    end

    local function append_select_sources_for_scalar(out, input, scalar)
        local condition_locations = { Support.location_class_frame_slot(), Support.location_class_continuation_arg() }
        local value_locations = scalar_source_locations(scalar)
        for _, condition_location in ipairs(condition_locations) do
            for _, true_location in ipairs(value_locations) do
                for _, false_location in ipairs(value_locations) do
                    for _, dest_location in ipairs(scalar_dest_locations()) do
                        append_select_source(out, input, scalar, condition_location, true_location, false_location, dest_location)
                    end
                end
            end
        end
    end

    local function memory_access_for_scalar(effect, scalar)
        return Code.CodeMemoryAccess(effect, scalar:native_code_type(), scalar:native_frame_alignment(), Code.CodeMayTrap, false, nil)
    end

    local function append_global_ref_source(out, input, dest_location)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local dst_token = Support.logical_location_token(dest_location)
        local id_base = "native.hole.code.inst.global_ref.ptr64.to." .. dst_token
        local target_hole = ptr64_hole(id_base .. ".target")
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", ptr_scalar)
        local holes = { target_hole }
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then
            next_params[#next_params + 1] = Support.stencil_continuation_param(0, ptr_scalar, dest_location)
        end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(ptr_scalar, { Support.stencil_operand(0, ptr_scalar, dest_location) }, { next_signature })
        local family_name = "global_ref.ptr64.to." .. dst_token
        local axis = Native.NativeCodeInstAddressMaterializeAxis(Native.NativeCodeAddressMaterializeModuleSymbol, ptr_scalar)
        local family = Support.code_inst_frame_family(family_name, input.domain.target, ptr_scalar, axis)
        local entry = "lalin_native_code_inst_global_ref_" .. symbol_fragment(dst_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t value = (uintptr_t)&" .. target_hole.symbol .. ";"
        local store = dest_location:native_edge_copy_dest_store(ptr_scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_addr_of_frame_source(out, input, dest_location)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local dst_token = Support.logical_location_token(dest_location)
        local id_base = "native.hole.code.inst.addr_of.frame.to." .. dst_token
        local frame_hole = frame_offset_hole(id_base .. ".frame")
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", ptr_scalar)
        local holes = { frame_hole }
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, ptr_scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(ptr_scalar, { Support.stencil_operand(0, ptr_scalar, dest_location) }, { next_signature })
        local family_name = "addr_of.frame.to." .. dst_token
        local axis = Native.NativeCodeInstAddressMaterializeAxis(Native.NativeCodeAddressMaterializeFrameSlot, ptr_scalar)
        local family = Support.code_inst_frame_family(family_name, input.domain.target, ptr_scalar, axis)
        local entry = "lalin_native_code_inst_addr_of_frame_" .. symbol_fragment(dst_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t value = (uintptr_t)(frame + " .. hole_address_expr(frame_hole) .. ");"
        local store = dest_location:native_edge_copy_dest_store(ptr_scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_ptr_offset_source(out, input, base_location, index_location, dest_location)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local index_scalar = Support.scalar_index(input.domain.target.pointer_bits)
        local base_token = Support.logical_location_token(base_location)
        local index_token = Support.logical_location_token(index_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_base = "native.hole.code.inst.ptr_offset." .. base_token .. ".index." .. index_token .. ".to." .. dst_token
        local base_holes = base_location:native_edge_copy_source_holes(id_base .. ".base", ptr_scalar)
        local index_holes = index_location:native_edge_copy_source_holes(id_base .. ".index", index_scalar)
        local elem_hole = imm32_hole(id_base .. ".elem_size")
        local const_hole = imm32_hole(id_base .. ".const_offset")
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", ptr_scalar)
        local holes = {}
        for _, hole in ipairs(base_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(index_holes) do holes[#holes + 1] = hole end
        holes[#holes + 1] = elem_hole
        holes[#holes + 1] = const_hole
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, ptr_scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local operands = { Support.stencil_operand(0, ptr_scalar, base_location), Support.stencil_operand(1, index_scalar, index_location), Support.stencil_operand(2, ptr_scalar, dest_location) }
        local signature = Support.spill_all_stencil_signature(ptr_scalar, operands, { next_signature })
        local family_name = "ptr_offset.ptr64." .. base_token .. ".index." .. index_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstPointerOffsetAxis(ptr_scalar, index_scalar)
        local family = Support.code_inst_frame_family(family_name, input.domain.target, ptr_scalar, axis)
        local entry = "lalin_native_code_inst_ptr_offset_" .. symbol_fragment(base_token .. "_" .. index_token .. "_to_" .. dst_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t base = " .. source_expr_for_operand(base_location, ptr_scalar, base_holes, 0) .. ";"
        lines[#lines + 1] = "    intptr_t index = " .. source_expr_for_operand(index_location, index_scalar, index_holes, 1) .. ";"
        lines[#lines + 1] = "    uintptr_t value = base + ((uintptr_t)index * (uintptr_t)" .. hole_address_expr(elem_hole) .. ") + (uintptr_t)" .. hole_address_expr(const_hole) .. ";"
        local store = dest_location:native_edge_copy_dest_store(ptr_scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_load_source(out, input, scalar, ptr_location, dest_location)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local ptr_token = Support.logical_location_token(ptr_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_base = "native.hole.code.inst.load." .. scalar:native_scalar_token() .. ".ptr." .. ptr_token .. ".to." .. dst_token
        local ptr_holes = ptr_location:native_edge_copy_source_holes(id_base .. ".ptr", ptr_scalar)
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", scalar)
        local holes = {}
        for _, hole in ipairs(ptr_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, ptr_scalar, ptr_location), Support.stencil_operand(1, scalar, dest_location) }, { next_signature })
        local family_name = "load." .. scalar:native_scalar_token() .. ".ptr." .. ptr_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstLoadAxis(memory_access_for_scalar(Code.CodeMemoryRead, scalar))
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_load_" .. symbol_fragment(scalar:native_scalar_token() .. "_" .. ptr_token .. "_to_" .. dst_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t address = " .. source_expr_for_operand(ptr_location, ptr_scalar, ptr_holes, 0) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = *(" .. scalar:native_c_scalar_type() .. " *)(void *)address;"
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_store_source(out, input, scalar, ptr_location, value_location)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local ptr_token = Support.logical_location_token(ptr_location)
        local value_token = Support.logical_location_token(value_location)
        local id_base = "native.hole.code.inst.store." .. scalar:native_scalar_token() .. ".ptr." .. ptr_token .. ".value." .. value_token
        local ptr_holes = ptr_location:native_edge_copy_source_holes(id_base .. ".ptr", ptr_scalar)
        local value_holes = value_location:native_edge_copy_source_holes(id_base .. ".value", scalar)
        local holes = {}
        for _, hole in ipairs(ptr_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(value_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, ptr_scalar, ptr_location), Support.stencil_operand(1, scalar, value_location) }, { next_signature })
        local family_name = "store." .. scalar:native_scalar_token() .. ".ptr." .. ptr_token .. ".value." .. value_token
        local axis = Native.NativeCodeInstStoreAxis(memory_access_for_scalar(Code.CodeMemoryWrite, scalar))
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_store_" .. symbol_fragment(scalar:native_scalar_token() .. "_" .. ptr_token .. "_" .. value_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t address = " .. source_expr_for_operand(ptr_location, ptr_scalar, ptr_holes, 0) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = " .. source_expr_for_operand(value_location, scalar, value_holes, 1) .. ";"
        lines[#lines + 1] = "    *(" .. scalar:native_c_scalar_type() .. " *)(void *)address = value;"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function descriptor_field_store_line(c_type, desc_hole, offset, value_expr)
        return "    *(" .. c_type .. " *)(void *)(frame + " .. hole_address_expr(desc_hole) .. " + " .. tostring(offset) .. ") = " .. value_expr .. ";"
    end

    local function descriptor_field_load_expr(c_type, desc_hole, offset)
        return "*(" .. c_type .. " *)(void *)(frame + " .. hole_address_expr(desc_hole) .. " + " .. tostring(offset) .. ")"
    end

    local function append_descriptor_make_source(out, input, kind_name, axis, elem_ty, data_location, len_location, stride_location)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local index_scalar = Support.scalar_index(input.domain.target.pointer_bits)
        local data_token = Support.logical_location_token(data_location)
        local len_token = Support.logical_location_token(len_location)
        local stride_token = stride_location and Support.logical_location_token(stride_location) or nil
        local elem_token = elem_ty and symbol_fragment(elem_ty:native_source_type_token()) or "bytes"
        local id_tail = kind_name .. ".make." .. elem_token .. ".data." .. data_token .. ".len." .. len_token .. (stride_token and (".stride." .. stride_token) or "")
        local id_base = "native.hole.code.inst." .. id_tail
        local desc_hole = frame_offset_hole(id_base .. ".dst")
        local data_holes = data_location:native_edge_copy_source_holes(id_base .. ".data", ptr_scalar)
        local len_holes = len_location:native_edge_copy_source_holes(id_base .. ".len", index_scalar)
        local stride_holes = stride_location and stride_location:native_edge_copy_source_holes(id_base .. ".stride", index_scalar) or {}
        local holes = { desc_hole }
        for _, hole in ipairs(data_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(len_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(stride_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local operands = { Support.stencil_operand(0, ptr_scalar, data_location), Support.stencil_operand(1, index_scalar, len_location) }
        if stride_location ~= nil then operands[#operands + 1] = Support.stencil_operand(2, index_scalar, stride_location) end
        local signature = Support.spill_all_stencil_signature(ptr_scalar, operands, { next_signature })
        local family = Support.code_inst_frame_family(id_tail, input.domain.target, ptr_scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(id_tail)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t data = " .. source_expr_for_operand(data_location, ptr_scalar, data_holes, 0) .. ";"
        lines[#lines + 1] = "    intptr_t len = " .. source_expr_for_operand(len_location, index_scalar, len_holes, 1) .. ";"
        lines[#lines + 1] = descriptor_field_store_line("uintptr_t", desc_hole, 0, "data")
        lines[#lines + 1] = descriptor_field_store_line("intptr_t", desc_hole, 8, "len")
        if stride_location ~= nil then
            lines[#lines + 1] = "    intptr_t stride = " .. source_expr_for_operand(stride_location, index_scalar, stride_holes, 2) .. ";"
            lines[#lines + 1] = descriptor_field_store_line("intptr_t", desc_hole, 16, "stride")
        end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. id_tail, family, Native.NativeChunkDescriptorOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_descriptor_extract_source(out, input, kind_name, axis, field_name, dest_scalar, dest_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_tail = kind_name .. "." .. field_name .. ".to." .. dst_token
        local id_base = "native.hole.code.inst." .. id_tail
        local desc_hole = frame_offset_hole(id_base .. ".src")
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", dest_scalar)
        local holes = { desc_hole }
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, dest_scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(dest_scalar, { Support.stencil_operand(0, dest_scalar, dest_location) }, { next_signature })
        local family = Support.code_inst_frame_family(id_tail, input.domain.target, dest_scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(id_tail)
        local next_symbol = Support.next_continuation_symbol()
        local offset = field_name == "data" and 0 or (field_name == "len" and 8 or 16)
        local c_type = dest_scalar:native_c_scalar_type()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. c_type .. " value = " .. descriptor_field_load_expr(c_type, desc_hole, offset) .. ";"
        local store = dest_location:native_edge_copy_dest_store(dest_scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. id_tail, family, Native.NativeChunkDescriptorOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_aggregate_store_source(out, input, scalar, kind, value_location)
        local value_token = Support.logical_location_token(value_location)
        local id_tail = kind .. ".field_store." .. scalar:native_scalar_token() .. ".value." .. value_token
        local id_base = "native.hole.code.inst." .. id_tail
        local base_hole = frame_offset_hole(id_base .. ".base")
        local offset_hole = imm32_hole(id_base .. ".offset")
        local value_holes = value_location:native_edge_copy_source_holes(id_base .. ".value", scalar)
        local holes = { base_hole, offset_hole }
        for _, hole in ipairs(value_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, scalar, value_location) }, { next_signature })
        local storage = kind == "array" and Native.NativeCodeArrayElementStorage or Native.NativeCodeAggregateObjectStorage
        local axis = Native.NativeCodeInstLayoutFieldStoreAxis(storage, scalar)
        local family = Support.code_inst_frame_family(id_tail, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(id_tail)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = " .. source_expr_for_operand(value_location, scalar, value_holes, 0) .. ";"
        lines[#lines + 1] = "    *(" .. scalar:native_c_scalar_type() .. " *)(void *)(frame + " .. hole_address_expr(base_hole) .. " + " .. hole_address_expr(offset_hole) .. ") = value;"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. id_tail, family, Native.NativeChunkAggregateVariantOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_aggregate_load_source(out, input, scalar, kind, dest_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_tail = kind .. ".field_load." .. scalar:native_scalar_token() .. ".to." .. dst_token
        local id_base = "native.hole.code.inst." .. id_tail
        local base_hole = frame_offset_hole(id_base .. ".base")
        local offset_hole = imm32_hole(id_base .. ".offset")
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", scalar)
        local holes = { base_hole, offset_hole }
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, scalar, dest_location) }, { next_signature })
        local storage = kind == "array" and Native.NativeCodeArrayElementStorage or Native.NativeCodeAggregateObjectStorage
        local axis = Native.NativeCodeInstLayoutFieldLoadAxis(storage, scalar)
        local family = Support.code_inst_frame_family(id_tail, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(id_tail)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = *(" .. scalar:native_c_scalar_type() .. " *)(void *)(frame + " .. hole_address_expr(base_hole) .. " + " .. hole_address_expr(offset_hole) .. ");"
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. id_tail, family, Native.NativeChunkAggregateVariantOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_variant_tag_source(out, input, dest_location)
        local tag_scalar = Support.scalar_i32()
        local dst_token = Support.logical_location_token(dest_location)
        local id_tail = "variant.tag.i32.to." .. dst_token
        local id_base = "native.hole.code.inst." .. id_tail
        local base_hole = frame_offset_hole(id_base .. ".base")
        local tag_offset_hole = imm32_hole(id_base .. ".tag_offset")
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", tag_scalar)
        local holes = { base_hole, tag_offset_hole }
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, tag_scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(tag_scalar, { Support.stencil_operand(0, tag_scalar, dest_location) }, { next_signature })
        local family = Support.code_inst_frame_family(id_tail, input.domain.target, tag_scalar, Native.NativeCodeInstVariantScalarTagAxis(tag_scalar))
        local entry = "lalin_native_code_inst_" .. symbol_fragment(id_tail)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    int32_t value = *(int32_t *)(void *)(frame + " .. hole_address_expr(base_hole) .. " + " .. hole_address_expr(tag_offset_hole) .. ");"
        local store = dest_location:native_edge_copy_dest_store(tag_scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. id_tail, family, Native.NativeChunkAggregateVariantOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_variant_payload_source(out, input, scalar, dest_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_tail = "variant.payload." .. scalar:native_scalar_token() .. ".to." .. dst_token
        local id_base = "native.hole.code.inst." .. id_tail
        local base_hole = frame_offset_hole(id_base .. ".base")
        local payload_offset_hole = imm32_hole(id_base .. ".payload_offset")
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", scalar)
        local holes = { base_hole, payload_offset_hole }
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, scalar, dest_location) }, { next_signature })
        local family = Support.code_inst_frame_family(id_tail, input.domain.target, scalar, Native.NativeCodeInstVariantScalarPayloadAxis(scalar))
        local entry = "lalin_native_code_inst_" .. symbol_fragment(id_tail)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = *(" .. scalar:native_c_scalar_type() .. " *)(void *)(frame + " .. hole_address_expr(base_hole) .. " + " .. hole_address_expr(payload_offset_hole) .. ");"
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. id_tail, family, Native.NativeChunkAggregateVariantOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_variant_ctor_source(out, input, scalar, value_location)
        local value_token = Support.logical_location_token(value_location)
        local id_tail = "variant.ctor." .. scalar:native_scalar_token() .. ".value." .. value_token
        local id_base = "native.hole.code.inst." .. id_tail
        local base_hole = frame_offset_hole(id_base .. ".base")
        local tag_offset_hole = imm32_hole(id_base .. ".tag_offset")
        local tag_value_hole = imm32_hole(id_base .. ".tag_value")
        local payload_offset_hole = imm32_hole(id_base .. ".payload_offset")
        local value_holes = value_location:native_edge_copy_source_holes(id_base .. ".payload", scalar)
        local holes = { base_hole, tag_offset_hole, tag_value_hole, payload_offset_hole }
        for _, hole in ipairs(value_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, scalar, value_location) }, { next_signature })
        local family = Support.code_inst_frame_family(id_tail, input.domain.target, scalar, Native.NativeCodeInstVariantScalarCtorAxis(Support.scalar_i32(), scalar))
        local entry = "lalin_native_code_inst_" .. symbol_fragment(id_tail)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " payload = " .. source_expr_for_operand(value_location, scalar, value_holes, 0) .. ";"
        lines[#lines + 1] = "    *(int32_t *)(void *)(frame + " .. hole_address_expr(base_hole) .. " + " .. hole_address_expr(tag_offset_hole) .. ") = (int32_t)" .. hole_address_expr(tag_value_hole) .. ";"
        lines[#lines + 1] = "    *(" .. scalar:native_c_scalar_type() .. " *)(void *)(frame + " .. hole_address_expr(base_hole) .. " + " .. hole_address_expr(payload_offset_hole) .. ") = payload;"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. id_tail, family, Native.NativeChunkAggregateVariantOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_domain_address_memory_descriptor_aggregate_sources(out, input)
        local frame_slot = Support.location_class_frame_slot()
        local cont_arg = Support.location_class_continuation_arg()
        for _, dest_location in ipairs({ frame_slot, cont_arg }) do
            append_global_ref_source(out, input, dest_location)
            append_addr_of_frame_source(out, input, dest_location)
            append_variant_tag_source(out, input, dest_location)
        end
        for _, base_location in ipairs({ frame_slot, cont_arg }) do
            for _, index_location in ipairs({ frame_slot, cont_arg }) do
                for _, dest_location in ipairs({ frame_slot, cont_arg }) do
                    append_ptr_offset_source(out, input, base_location, index_location, dest_location)
                end
            end
        end
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local index_scalar = Support.scalar_index(input.domain.target.pointer_bits)
        for _, scalar_support in ipairs(input.domain.scalars or {}) do
            local scalar = scalar_support.scalar
            for _, ptr_location in ipairs({ frame_slot, cont_arg }) do
                for _, dest_location in ipairs({ frame_slot, cont_arg }) do append_load_source(out, input, scalar, ptr_location, dest_location) end
                for _, value_location in ipairs(scalar_source_locations(scalar)) do append_store_source(out, input, scalar, ptr_location, value_location) end
            end
            for _, value_location in ipairs(scalar_source_locations(scalar)) do
                append_aggregate_store_source(out, input, scalar, "aggregate", value_location)
                append_aggregate_store_source(out, input, scalar, "array", value_location)
                append_variant_ctor_source(out, input, scalar, value_location)
            end
            for _, dest_location in ipairs({ frame_slot, cont_arg }) do
                append_aggregate_load_source(out, input, scalar, "aggregate", dest_location)
                append_aggregate_load_source(out, input, scalar, "array", dest_location)
                append_variant_payload_source(out, input, scalar, dest_location)
            end
            local elem_ty = scalar:native_code_type()
            for _, data_location in ipairs({ frame_slot, cont_arg }) do
                for _, len_location in ipairs({ frame_slot, cont_arg }) do
                    append_descriptor_make_source(out, input, "slice", Native.NativeCodeInstSliceMakeAxis(elem_ty), elem_ty, data_location, len_location, nil)
                    for _, stride_location in ipairs({ frame_slot, cont_arg }) do append_descriptor_make_source(out, input, "view", Native.NativeCodeInstViewMakeAxis(elem_ty), elem_ty, data_location, len_location, stride_location) end
                end
            end
        end
        for _, data_location in ipairs({ frame_slot, cont_arg }) do
            for _, len_location in ipairs({ frame_slot, cont_arg }) do append_descriptor_make_source(out, input, "bytespan", Native.NativeCodeInstByteSpanMakeAxis, nil, data_location, len_location, nil) end
        end
        for _, dest_location in ipairs({ frame_slot, cont_arg }) do
            append_descriptor_extract_source(out, input, "slice", Native.NativeCodeInstSliceDataAxis, "data", ptr_scalar, dest_location)
            append_descriptor_extract_source(out, input, "slice", Native.NativeCodeInstSliceLenAxis, "len", index_scalar, dest_location)
            append_descriptor_extract_source(out, input, "view", Native.NativeCodeInstViewDataAxis, "data", ptr_scalar, dest_location)
            append_descriptor_extract_source(out, input, "view", Native.NativeCodeInstViewLenAxis, "len", index_scalar, dest_location)
            append_descriptor_extract_source(out, input, "view", Native.NativeCodeInstViewStrideAxis, "stride", index_scalar, dest_location)
            append_descriptor_extract_source(out, input, "bytespan", Native.NativeCodeInstByteSpanDataAxis, "data", ptr_scalar, dest_location)
            append_descriptor_extract_source(out, input, "bytespan", Native.NativeCodeInstByteSpanLenAxis, "len", index_scalar, dest_location)
        end
    end

    function Core.AtomicOrdering:native_atomic_order_token()
        internal_error("unsupported native atomic ordering")
    end

    function Core.AtomicSeqCst:native_atomic_order_token()
        return "seq_cst"
    end

    function Core.AtomicOrdering:native_atomic_order_c()
        internal_error("unsupported native atomic ordering")
    end

    function Core.AtomicSeqCst:native_atomic_order_c()
        return "__ATOMIC_SEQ_CST"
    end

    function Core.AtomicRmwOp:native_atomic_rmw_token()
        internal_error("unsupported native atomic rmw op")
    end

    function Core.AtomicRmwAdd:native_atomic_rmw_token() return "add" end
    function Core.AtomicRmwSub:native_atomic_rmw_token() return "sub" end
    function Core.AtomicRmwAnd:native_atomic_rmw_token() return "and" end
    function Core.AtomicRmwOr:native_atomic_rmw_token() return "or" end
    function Core.AtomicRmwXor:native_atomic_rmw_token() return "xor" end
    function Core.AtomicRmwXchg:native_atomic_rmw_token() return "xchg" end

    function Core.AtomicRmwOp:native_atomic_fetch_builtin()
        internal_error("unsupported native atomic rmw op")
    end

    function Core.AtomicRmwAdd:native_atomic_fetch_builtin() return "__atomic_fetch_add" end
    function Core.AtomicRmwSub:native_atomic_fetch_builtin() return "__atomic_fetch_sub" end
    function Core.AtomicRmwAnd:native_atomic_fetch_builtin() return "__atomic_fetch_and" end
    function Core.AtomicRmwOr:native_atomic_fetch_builtin() return "__atomic_fetch_or" end
    function Core.AtomicRmwXor:native_atomic_fetch_builtin() return "__atomic_fetch_xor" end
    function Core.AtomicRmwXchg:native_atomic_fetch_builtin() return "__atomic_exchange_n" end

    local function require_atomic_codegen(input)
        if input.domain.atomic_codegen ~= Native.NativeAtomicGccBuiltins then
            internal_error("native atomic source builders require NativeAtomicGccBuiltins support-domain capability")
        end
    end

    local function scalar_supports_atomic(scalar)
        return scalar:native_cast_is_integer_like()
    end

    local function atomic_access_for_scalar(effect, scalar)
        return Code.CodeMemoryAccess(effect, scalar:native_code_type(), scalar:native_frame_alignment(), Code.CodeMayTrap, true, Core.AtomicSeqCst)
    end

    local function append_atomic_load_source(out, input, scalar, ptr_location, dest_location, ordering)
        require_atomic_codegen(input)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local ptr_token = Support.logical_location_token(ptr_location)
        local dst_token = Support.logical_location_token(dest_location)
        local order_token = ordering:native_atomic_order_token()
        local id_base = "native.hole.code.inst.atomic_load." .. scalar:native_scalar_token() .. "." .. order_token .. ".ptr." .. ptr_token .. ".to." .. dst_token
        local ptr_holes = ptr_location:native_edge_copy_source_holes(id_base .. ".ptr", ptr_scalar)
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", scalar)
        local holes = {}
        for _, hole in ipairs(ptr_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, ptr_scalar, ptr_location), Support.stencil_operand(1, scalar, dest_location) }, { next_signature })
        local family_name = "atomic_load." .. scalar:native_scalar_token() .. "." .. order_token .. ".ptr." .. ptr_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstAtomicLoadAxis(atomic_access_for_scalar(Code.CodeMemoryRead, scalar), ordering)
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(family_name)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t address = " .. source_expr_for_operand(ptr_location, ptr_scalar, ptr_holes, 0) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = __atomic_load_n((" .. scalar:native_c_scalar_type() .. " *)(void *)address, " .. ordering:native_atomic_order_c() .. ");"
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_atomic_store_source(out, input, scalar, ptr_location, value_location, ordering)
        require_atomic_codegen(input)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local ptr_token = Support.logical_location_token(ptr_location)
        local value_token = Support.logical_location_token(value_location)
        local order_token = ordering:native_atomic_order_token()
        local id_base = "native.hole.code.inst.atomic_store." .. scalar:native_scalar_token() .. "." .. order_token .. ".ptr." .. ptr_token .. ".value." .. value_token
        local ptr_holes = ptr_location:native_edge_copy_source_holes(id_base .. ".ptr", ptr_scalar)
        local value_holes = value_location:native_edge_copy_source_holes(id_base .. ".value", scalar)
        local holes = {}
        for _, hole in ipairs(ptr_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(value_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, ptr_scalar, ptr_location), Support.stencil_operand(1, scalar, value_location) }, { next_signature })
        local family_name = "atomic_store." .. scalar:native_scalar_token() .. "." .. order_token .. ".ptr." .. ptr_token .. ".value." .. value_token
        local axis = Native.NativeCodeInstAtomicStoreAxis(atomic_access_for_scalar(Code.CodeMemoryWrite, scalar), ordering)
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(family_name)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t address = " .. source_expr_for_operand(ptr_location, ptr_scalar, ptr_holes, 0) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = " .. source_expr_for_operand(value_location, scalar, value_holes, 1) .. ";"
        lines[#lines + 1] = "    __atomic_store_n((" .. scalar:native_c_scalar_type() .. " *)(void *)address, value, " .. ordering:native_atomic_order_c() .. ");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_atomic_rmw_source(out, input, scalar, op, ptr_location, value_location, dest_location, ordering)
        require_atomic_codegen(input)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local ptr_token = Support.logical_location_token(ptr_location)
        local value_token = Support.logical_location_token(value_location)
        local dst_token = Support.logical_location_token(dest_location)
        local order_token = ordering:native_atomic_order_token()
        local op_token = op:native_atomic_rmw_token()
        local id_base = "native.hole.code.inst.atomic_rmw." .. scalar:native_scalar_token() .. "." .. op_token .. "." .. order_token .. ".ptr." .. ptr_token .. ".value." .. value_token .. ".to." .. dst_token
        local ptr_holes = ptr_location:native_edge_copy_source_holes(id_base .. ".ptr", ptr_scalar)
        local value_holes = value_location:native_edge_copy_source_holes(id_base .. ".value", scalar)
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", scalar)
        local holes = {}
        for _, hole in ipairs(ptr_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(value_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(scalar, { Support.stencil_operand(0, ptr_scalar, ptr_location), Support.stencil_operand(1, scalar, value_location), Support.stencil_operand(2, scalar, dest_location) }, { next_signature })
        local family_name = "atomic_rmw." .. scalar:native_scalar_token() .. "." .. op_token .. "." .. order_token .. ".ptr." .. ptr_token .. ".value." .. value_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstAtomicRmwAxis(op, atomic_access_for_scalar(Code.CodeMemoryReadWrite, scalar), ordering)
        local family = Support.code_inst_frame_family(family_name, input.domain.target, scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(family_name)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t address = " .. source_expr_for_operand(ptr_location, ptr_scalar, ptr_holes, 0) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " value = " .. source_expr_for_operand(value_location, scalar, value_holes, 1) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " old_value = " .. op:native_atomic_fetch_builtin() .. "((" .. scalar:native_c_scalar_type() .. " *)(void *)address, value, " .. ordering:native_atomic_order_c() .. ");"
        local store = dest_location:native_edge_copy_dest_store(scalar, dest_holes, "old_value")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("old_value")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_atomic_cas_source(out, input, scalar, ptr_location, expected_location, replacement_location, dest_location, ordering)
        require_atomic_codegen(input)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local result_scalar = Support.scalar_bool8()
        local ptr_token = Support.logical_location_token(ptr_location)
        local expected_token = Support.logical_location_token(expected_location)
        local replacement_token = Support.logical_location_token(replacement_location)
        local dst_token = Support.logical_location_token(dest_location)
        local order_token = ordering:native_atomic_order_token()
        local id_base = "native.hole.code.inst.atomic_cas." .. scalar:native_scalar_token() .. "." .. order_token .. ".ptr." .. ptr_token .. ".expected." .. expected_token .. ".replacement." .. replacement_token .. ".to." .. dst_token
        local ptr_holes = ptr_location:native_edge_copy_source_holes(id_base .. ".ptr", ptr_scalar)
        local expected_holes = expected_location:native_edge_copy_source_holes(id_base .. ".expected", scalar)
        local replacement_holes = replacement_location:native_edge_copy_source_holes(id_base .. ".replacement", scalar)
        local dest_holes = dest_location:native_edge_copy_dest_holes(id_base .. ".dst", result_scalar)
        local holes = {}
        for _, hole in ipairs(ptr_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(expected_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(replacement_holes) do holes[#holes + 1] = hole end
        for _, hole in ipairs(dest_holes) do holes[#holes + 1] = hole end
        local next_ordinal = Support.next_continuation_ordinal()
        local next_params = {}
        if asdl.isa(dest_location, Native.NativeStencilContinuationArgLocationClass) then next_params[#next_params + 1] = Support.stencil_continuation_param(0, result_scalar, dest_location) end
        local next_signature = Support.stencil_continuation_signature(next_ordinal, next_params)
        local signature = Support.spill_all_stencil_signature(result_scalar, { Support.stencil_operand(0, ptr_scalar, ptr_location), Support.stencil_operand(1, scalar, expected_location), Support.stencil_operand(2, scalar, replacement_location), Support.stencil_operand(3, result_scalar, dest_location) }, { next_signature })
        local family_name = "atomic_cas." .. scalar:native_scalar_token() .. "." .. order_token .. ".ptr." .. ptr_token .. ".expected." .. expected_token .. ".replacement." .. replacement_token .. ".to." .. dst_token
        local axis = Native.NativeCodeInstAtomicCasAxis(atomic_access_for_scalar(Code.CodeMemoryReadWrite, scalar), ordering)
        local family = Support.code_inst_frame_family(family_name, input.domain.target, result_scalar, axis)
        local entry = "lalin_native_code_inst_" .. symbol_fragment(family_name)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uintptr_t address = " .. source_expr_for_operand(ptr_location, ptr_scalar, ptr_holes, 0) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " expected = " .. source_expr_for_operand(expected_location, scalar, expected_holes, 1) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " replacement = " .. source_expr_for_operand(replacement_location, scalar, replacement_holes, 2) .. ";"
        lines[#lines + 1] = "    uint8_t success = (uint8_t)__atomic_compare_exchange_n((" .. scalar:native_c_scalar_type() .. " *)(void *)address, &expected, replacement, 0, " .. ordering:native_atomic_order_c() .. ", " .. ordering:native_atomic_order_c() .. ");"
        local store = dest_location:native_edge_copy_dest_store(result_scalar, dest_holes, "success")
        if store ~= nil then lines[#lines + 1] = store end
        local next_args = { "frame" }
        for _, arg in ipairs(dest_location:native_edge_copy_next_args("success")) do next_args[#next_args + 1] = arg end
        lines[#lines + 1] = "    " .. next_symbol.name .. "(" .. table.concat(next_args, ", ") .. ");"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function append_atomic_fence_source(out, input, ordering)
        require_atomic_codegen(input)
        local frame_scalar = Support.scalar_bool8()
        local order_token = ordering:native_atomic_order_token()
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = Support.spill_all_stencil_signature(frame_scalar, {}, { next_signature })
        local family_name = "atomic_fence." .. order_token
        local family = Support.code_inst_frame_family(family_name, input.domain.target, frame_scalar, Native.NativeCodeInstAtomicFenceAxis(ordering))
        local entry = "lalin_native_code_inst_atomic_fence_" .. symbol_fragment(order_token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    __atomic_thread_fence(" .. ordering:native_atomic_order_c() .. ");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst." .. family_name, family, Native.NativeChunkAddressMemoryOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    local function append_domain_atomic_sources(out, input)
        append_atomic_fence_source(out, input, Core.AtomicSeqCst)
        for _, scalar_support in ipairs(input.domain.scalars or {}) do
            local scalar = scalar_support.scalar
            if scalar_supports_atomic(scalar) then
                for _, ptr_location in ipairs({ Support.location_class_frame_slot(), Support.location_class_continuation_arg() }) do
                    for _, dest_location in ipairs({ Support.location_class_frame_slot(), Support.location_class_continuation_arg() }) do
                        append_atomic_load_source(out, input, scalar, ptr_location, dest_location, Core.AtomicSeqCst)
                    end
                    for _, value_location in ipairs(scalar_source_locations(scalar)) do
                        append_atomic_store_source(out, input, scalar, ptr_location, value_location, Core.AtomicSeqCst)
                        for _, dest_location in ipairs({ Support.location_class_frame_slot(), Support.location_class_continuation_arg() }) do
                            for _, op in ipairs({ Core.AtomicRmwAdd, Core.AtomicRmwSub, Core.AtomicRmwAnd, Core.AtomicRmwOr, Core.AtomicRmwXor, Core.AtomicRmwXchg }) do
                                append_atomic_rmw_source(out, input, scalar, op, ptr_location, value_location, dest_location, Core.AtomicSeqCst)
                            end
                            for _, replacement_location in ipairs(scalar_source_locations(scalar)) do
                                append_atomic_cas_source(out, input, scalar, ptr_location, value_location, replacement_location, dest_location, Core.AtomicSeqCst)
                            end
                        end
                    end
                end
            end
        end
    end

    local function control_signature(frame_scalar, operands, continuation_signatures)
        return Support.spill_all_stencil_signature(frame_scalar, operands or {}, continuation_signatures or {})
    end

    local function control_family(input, name, axis)
        return Support.code_term_family(name, input.domain.target, axis, Support.protocol_void_none())
    end

    local function append_jump_control_source(out, input)
        local frame_scalar = Support.scalar_bool8()
        local next_symbol = Support.next_continuation_symbol()
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = control_signature(frame_scalar, {}, { next_signature })
        local axis = Native.NativeCodeTermJumpAxis
        local family = control_family(input, "jump.next", axis)
        local entry = "lalin_native_code_term_jump_next"
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.jump.next", family, Native.NativeChunkControlOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    local function append_branch_control_source(out, input, condition_location)
        local cond_scalar = Support.scalar_bool8()
        local loc_token = Support.logical_location_token(condition_location)
        local id_base = "native.hole.code.term.branch.bool8." .. loc_token
        local cond_holes = condition_location:native_edge_copy_source_holes(id_base, cond_scalar)
        local operands = { Support.stencil_operand(0, cond_scalar, condition_location) }
        local then_ordinal = Support.then_continuation_ordinal()
        local else_ordinal = Support.else_continuation_ordinal()
        local then_symbol = Support.then_continuation_symbol()
        local else_symbol = Support.else_continuation_symbol()
        local then_signature = Support.stencil_continuation_signature(then_ordinal, {})
        local else_signature = Support.stencil_continuation_signature(else_ordinal, {})
        local signature = control_signature(cond_scalar, operands, { then_signature, else_signature })
        local family = control_family(input, "branch.bool8." .. loc_token, Native.NativeCodeTermBranchAxis)
        local entry = "lalin_native_code_term_branch_bool8_" .. symbol_fragment(loc_token)
        local lines = c_prelude()
        append_hole_externs(lines, cond_holes)
        lines[#lines + 1] = continuation_extern(then_symbol, then_signature)
        lines[#lines + 1] = continuation_extern(else_symbol, else_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    uint8_t cond = " .. condition_location:native_edge_copy_source_expr(cond_scalar, cond_holes) .. ";"
        lines[#lines + 1] = "    if (cond != 0) {"
        lines[#lines + 1] = "        " .. then_symbol.name .. "(frame);"
        lines[#lines + 1] = "    } else {"
        lines[#lines + 1] = "        " .. else_symbol.name .. "(frame);"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.branch.bool8." .. loc_token, family, Native.NativeChunkControlOp, signature, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), entry, lines, cond_holes, { then_ordinal, else_ordinal })
    end

    local function append_switch_step_control_source(out, input, scalar, key_location)
        local token = scalar:native_scalar_token()
        local loc_token = Support.logical_location_token(key_location)
        local id_base = "native.hole.code.term.switch_step." .. token .. "." .. loc_token
        local key_holes = key_location:native_edge_copy_source_holes(id_base, scalar)
        local case_hole = scalar_immediate_hole(id_base .. ".case", scalar)
        local holes = {}
        for _, hole in ipairs(key_holes) do holes[#holes + 1] = hole end
        holes[#holes + 1] = case_hole
        local operands = { Support.stencil_operand(0, scalar, key_location), Support.stencil_operand(1, scalar, Support.location_class_immediate()) }
        local then_ordinal = Support.then_continuation_ordinal()
        local else_ordinal = Support.else_continuation_ordinal()
        local then_symbol = Support.then_continuation_symbol()
        local else_symbol = Support.else_continuation_symbol()
        local then_signature = Support.stencil_continuation_signature(then_ordinal, {})
        local else_signature = Support.stencil_continuation_signature(else_ordinal, {})
        local signature = control_signature(scalar, operands, { then_signature, else_signature })
        local family = control_family(input, "switch_step." .. token .. "." .. loc_token .. ".imm", Native.NativeCodeTermSwitchAxis)
        local entry = "lalin_native_code_term_switch_step_" .. symbol_fragment(token .. "_" .. loc_token)
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(then_symbol, then_signature)
        lines[#lines + 1] = continuation_extern(else_symbol, else_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " key = " .. key_location:native_edge_copy_source_expr(scalar, key_holes) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " case_value = (" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(case_hole) .. ";"
        lines[#lines + 1] = "    if (key == case_value) {"
        lines[#lines + 1] = "        " .. then_symbol.name .. "(frame);"
        lines[#lines + 1] = "    } else {"
        lines[#lines + 1] = "        " .. else_symbol.name .. "(frame);"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.switch_step." .. token .. "." .. loc_token .. ".imm", family, Native.NativeChunkControlOp, signature, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), entry, lines, holes, { then_ordinal, else_ordinal })
    end

    local function append_variant_switch_step_control_source(out, input, scalar, key_location)
        local token = scalar:native_scalar_token()
        local loc_token = Support.logical_location_token(key_location)
        local id_base = "native.hole.code.term.variant_switch_step." .. token .. "." .. loc_token
        local key_holes = key_location:native_edge_copy_source_holes(id_base, scalar)
        local case_hole = scalar_immediate_hole(id_base .. ".case", scalar)
        local holes = {}
        for _, hole in ipairs(key_holes) do holes[#holes + 1] = hole end
        holes[#holes + 1] = case_hole
        local operands = { Support.stencil_operand(0, scalar, key_location), Support.stencil_operand(1, scalar, Support.location_class_immediate()) }
        local then_ordinal = Support.then_continuation_ordinal()
        local else_ordinal = Support.else_continuation_ordinal()
        local then_symbol = Support.then_continuation_symbol()
        local else_symbol = Support.else_continuation_symbol()
        local then_signature = Support.stencil_continuation_signature(then_ordinal, {})
        local else_signature = Support.stencil_continuation_signature(else_ordinal, {})
        local signature = control_signature(scalar, operands, { then_signature, else_signature })
        local family = control_family(input, "variant_switch_step." .. token .. "." .. loc_token .. ".imm", Native.NativeCodeTermVariantSwitchAxis)
        local entry = "lalin_native_code_term_variant_switch_step_" .. symbol_fragment(token .. "_" .. loc_token)
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(then_symbol, then_signature)
        lines[#lines + 1] = continuation_extern(else_symbol, else_signature)
        lines[#lines + 1] = "void " .. entry .. "(" .. table.concat(fragment_signature_params(signature), ", ") .. ") {"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " key = " .. key_location:native_edge_copy_source_expr(scalar, key_holes) .. ";"
        lines[#lines + 1] = "    " .. scalar:native_c_scalar_type() .. " case_value = (" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(case_hole) .. ";"
        lines[#lines + 1] = "    if (key == case_value) { " .. then_symbol.name .. "(frame); } else { " .. else_symbol.name .. "(frame); }"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.variant_switch_step." .. token .. "." .. loc_token .. ".imm", family, Native.NativeChunkControlOp, signature, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), entry, lines, holes, { then_ordinal, else_ordinal })
    end

    local function append_unreachable_control_source(out, input)
        local frame_scalar = Support.scalar_bool8()
        local signature = control_signature(frame_scalar, {}, {})
        local family = control_family(input, "unreachable.trap", Native.NativeCodeTermUnreachableAxis)
        local entry = "lalin_native_code_term_unreachable"
        local lines = c_prelude()
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    (void)frame;"
        lines[#lines + 1] = "    __builtin_trap();"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.unreachable.trap", family, Native.NativeChunkControlOp, signature, Native.NativeExtractTerminalContinuation, entry, lines, {}, {})
    end

    local function append_trap_control_source(out, input)
        local frame_scalar = Support.scalar_bool8()
        local signature = control_signature(frame_scalar, {}, {})
        local family = control_family(input, "trap.trap", Native.NativeCodeTermTrapAxis)
        local entry = "lalin_native_code_term_trap"
        local lines = c_prelude()
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    (void)frame;"
        lines[#lines + 1] = "    __builtin_trap();"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.trap.trap", family, Native.NativeChunkControlOp, signature, Native.NativeExtractTerminalContinuation, entry, lines, {}, {})
    end

    local function append_call_return_control_source(out, input)
        local frame_scalar = Support.scalar_bool8()
        local next_symbol = Support.next_continuation_symbol()
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        local signature = control_signature(frame_scalar, {}, { next_signature })
        local family = control_family(input, "call_return.next", Native.NativeCodeTermJumpAxis)
        local entry = "lalin_native_code_term_call_return_next"
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.call_return.next", family, Native.NativeChunkControlOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    local function append_trap_runtime_source(out, input, symbol)
        if not symbol.abi:native_has_no_params() then internal_error("trap runtime symbol must not require source-builder-supplied parameters: " .. symbol.name) end
        local frame_scalar = Support.scalar_bool8()
        local signature = control_signature(frame_scalar, {}, {})
        local family = Support.runtime_call_family("trap." .. symbol.id.text, input.domain.target, Support.protocol_void_none())
        local entry = "lalin_native_code_term_trap_" .. symbol_fragment(symbol.id.text)
        local lines = c_prelude()
        lines[#lines + 1] = "extern " .. symbol.abi:native_c_function_declaration(symbol.name) .. ";"
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    (void)frame;"
        lines[#lines + 1] = "    " .. (symbol.abi:native_result_is_void() and "" or "(void)") .. symbol.name .. "();"
        lines[#lines + 1] = "    __builtin_trap();"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.term.trap." .. symbol.id.text, family, Native.NativeChunkControlOp, signature, Native.NativeExtractTerminalContinuation, entry, lines, {}, {}, { Native.NativeTemplateRelocationRuntimeSymbol })
    end

    local function append_domain_control_sources(out, input)
        append_jump_control_source(out, input)
        append_branch_control_source(out, input, Support.location_class_frame_slot())
        append_branch_control_source(out, input, Support.location_class_continuation_arg())
        append_unreachable_control_source(out, input)
        append_trap_control_source(out, input)
        append_call_return_control_source(out, input)
        append_void_terminal_source(out, input)
        for _, scalar_support in ipairs(input.domain.scalars or {}) do
            local scalar = scalar_support.scalar
            append_switch_step_control_source(out, input, scalar, Support.location_class_frame_slot())
            append_switch_step_control_source(out, input, scalar, Support.location_class_continuation_arg())
            append_variant_switch_step_control_source(out, input, scalar, Support.location_class_frame_slot())
            append_variant_switch_step_control_source(out, input, scalar, Support.location_class_continuation_arg())
        end
        for _, symbol in ipairs((input.domain.runtime and input.domain.runtime.symbols) or {}) do
            if symbol.abi:native_has_no_params() then append_trap_runtime_source(out, input, symbol) end
        end
    end

    local function deterministic_param_offset(param)
        return param.param_index * 16
    end

    local function deterministic_result_offset(projection)
        return #(projection.params or {}) * 16
    end

    local function abi_adapter_family(input, projection, name)
        return Native.NativeTemplateFamily(
            Support.code_func_family_id(name),
            Native.NativeRoleCodeFunc,
            { Support.axis_target(input.domain.target), Support.axis_abi(Support.native_call_code_sig(projection)) },
            Support.protocol(Support.native_call_code_sig(projection), Support.register_none())
        )
    end

    local call_result_hole_needed

    local function append_public_abi_adapter_source(out, input, projection)
        local token = projection:native_projection_token()
        local id_text = "code.func.public_abi_adapter." .. token
        local family = abi_adapter_family(input, projection, "public_abi_adapter." .. token)
        local entry = "lalin_native_public_abi_adapter_" .. symbol_fragment(token)
        local frame_size_hole = frame_offset_hole("native.hole.code.func.public_abi_adapter." .. token .. ".frame_size")
        frame_size_hole = Native.NativeHoleLayout(frame_size_hole.id, frame_size_hole.symbol, -1, 4, Native.NativePatchFrameSize32)
        local holes = { frame_size_hole }
        for _, param in ipairs(projection.params or {}) do
            holes[#holes + 1] = frame_offset_hole("native.hole.code.func.public_abi_adapter." .. token .. ".param" .. tostring(param.param_index))
        end
        local result_hole
        if call_result_hole_needed(projection) then
            result_hole = frame_offset_hole("native.hole.code.func.public_abi_adapter." .. token .. ".result")
            holes[#holes + 1] = result_hole
        end
        local hole_ordinals = hole_ordinals_for_layouts(id_text, holes)
        local first_symbol = Support.first_continuation_symbol()
        local first_ordinal = Support.first_continuation_ordinal()
        local first_signature = Support.stencil_continuation_signature(first_ordinal, {})
        local signature = Support.spill_all_stencil_signature(Support.scalar_bool8(), {}, { first_signature })
        local extraction = Native.NativeExtractPublicAbiAdapter(projection, hole_ordinals[1], input.domain.frame_stack_limit.alignment, first_symbol)
        local generator = generator_for_source(id_text, family, Native.NativeChunkPublicAbiAdapter)
        local configuration = configuration_for_source(id_text, generator)
        local manifest_entry = Support.template_manifest_entry(
            source_id(id_text),
            family,
            generator,
            configuration,
            signature,
            extraction,
            hole_ordinals,
            { first_ordinal },
            relocation_declarations(hole_ordinals, { first_ordinal })
        )
        local lines = c_prelude()
        projection:append_native_c_declarations(lines)
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(first_symbol, first_signature)
        lines[#lines + 1] = projection:native_c_function_declaration(entry) .. " {"
        lines[#lines + 1] = "    __asm__ volatile(\"jmp 1f\\n .long " .. frame_size_hole.symbol .. "\\n1:\");"
        lines[#lines + 1] = "    uint8_t frame[" .. tostring(FRAME_BYTES) .. "];"
        lines[#lines + 1] = "    (void)frame;"
        local hole_index = 2
        for _, param in ipairs(projection.params or {}) do
            lines[#lines + 1] = param.abi:native_store_param_to_frame(input.domain.target, holes[hole_index], "p" .. tostring(param.param_index))
            hole_index = hole_index + 1
        end
        lines[#lines + 1] = "    " .. first_symbol.name .. "(frame);"
        if asdl.isa(projection.result.abi, Native.NativeAbiVoidResult) or asdl.isa(projection.result.abi, Native.NativeAbiSRetResult) then
            lines[#lines + 1] = "    return;"
        else
            lines[#lines + 1] = "    return " .. projection.result.abi:native_return_from_frame(input.domain.target, result_hole) .. ";"
        end
        lines[#lines + 1] = "}"
        api.append_source(out, api.c_source_from_manifest_entry(manifest_entry, entry, concat_lines(lines), holes))
    end

    local function call_source_signature(projection)
        local operands = {}
        for _, param in ipairs(projection.params or {}) do
            if not asdl.isa(param.abi, Native.NativeAbiVoidResult) then
                local scalar = Support.scalar_pointer(projection.target.pointer_bits)
                if asdl.isa(param.abi, Native.NativeAbiScalarValue) then scalar = param.abi.scalar end
                operands[#operands + 1] = Support.stencil_operand(param.param_index, scalar, Support.location_class_frame_slot())
            end
        end
        local result_abi = projection.result.abi
        if asdl.isa(result_abi, Native.NativeAbiScalarValue) then
            operands[#operands + 1] = Support.stencil_operand(#operands, result_abi.scalar, Support.location_class_frame_slot())
        elseif asdl.isa(result_abi, Native.NativeAbiPointerValue) or asdl.isa(result_abi, Native.NativeAbiByRefValue) or asdl.isa(result_abi, Native.NativeAbiDescriptorValue) then
            operands[#operands + 1] = Support.stencil_operand(#operands, Support.scalar_pointer(projection.target.pointer_bits), Support.location_class_frame_slot())
        end
        local next_ordinal = Support.next_continuation_ordinal()
        return Support.spill_all_stencil_signature(Support.scalar_bool8(), operands, { Support.stencil_continuation_signature(next_ordinal, {}) })
    end

    function call_result_hole_needed(projection)
        return asdl.isa(projection.result.abi, Native.NativeAbiScalarValue)
            or asdl.isa(projection.result.abi, Native.NativeAbiPointerValue)
            or asdl.isa(projection.result.abi, Native.NativeAbiDescriptorValue)
            or asdl.isa(projection.result.abi, Native.NativeAbiByRefValue)
    end

    local function append_call_common_lines(lines, input, projection, holes, call_expr)
        local args = {}
        local hole_index = 1
        for _, param in ipairs(projection.params or {}) do
            args[#args + 1] = param.abi:native_load_arg_from_frame(input.domain.target, holes[hole_index])
            hole_index = hole_index + 1
        end
        local result_hole = call_result_hole_needed(projection) and holes[#holes] or nil
        local call = call_expr(table.concat(args, ", "))
        if call_result_hole_needed(projection) then
            lines[#lines + 1] = "    " .. projection.result.abi:native_c_boundary_type() .. " result = " .. call .. ";"
            lines[#lines + 1] = projection.result.abi:native_store_result_to_frame(input.domain.target, result_hole, "result")
        else
            lines[#lines + 1] = "    " .. call .. ";"
        end
    end

    local function append_direct_call_source(out, input, projection)
        local token = projection:native_projection_token()
        local id_text = "code.inst.call.direct." .. token
        local axis = Native.NativeCodeInstCallShapeAxis(Native.NativeCodeCallDirectTarget, projection)
        local family = Support.code_inst_frame_family("call.direct." .. token, input.domain.target, Support.scalar_bool8(), axis)
        local call_hole = call_rel32_hole("native.hole.code.inst.call.direct." .. token .. ".target")
        local holes = { call_hole }
        for _, param in ipairs(projection.params or {}) do holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.direct." .. token .. ".arg" .. tostring(param.param_index)) end
        if call_result_hole_needed(projection) then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.direct." .. token .. ".result") end
        local next_symbol = Support.next_continuation_symbol()
        local signature = call_source_signature(projection)
        local entry = "lalin_native_code_inst_call_direct_" .. symbol_fragment(token)
        local lines = c_prelude()
        projection:append_native_c_declarations(lines)
        for i = 2, #holes do lines[#lines + 1] = "extern const uint8_t " .. holes[i].symbol .. ";" end
        lines[#lines + 1] = "extern " .. projection:native_c_function_declaration(call_hole.symbol) .. ";"
        lines[#lines + 1] = continuation_extern(next_symbol, Support.stencil_continuation_signature(Support.next_continuation_ordinal(), {}))
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        append_call_common_lines(lines, input, projection, { unpack(holes, 2) }, function(args) return call_hole.symbol .. "(" .. args .. ")" end)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, id_text, family, Native.NativeChunkCallOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { Support.next_continuation_ordinal() })
    end

    local function append_indirect_call_source(out, input, projection, closure)
        local token = projection:native_projection_token()
        local mode = closure and "closure" or "indirect"
        local id_text = "code.inst.call." .. mode .. "." .. token
        local axis = Native.NativeCodeInstCallShapeAxis(closure and Native.NativeCodeCallClosurePointer or Native.NativeCodeCallIndirectPointer, projection)
        local family = Support.code_inst_frame_family("call." .. mode .. "." .. token, input.domain.target, Support.scalar_bool8(), axis)
        local holes = { frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".fn") }
        if closure then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".env") end
        for _, param in ipairs(projection.params or {}) do holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".arg" .. tostring(param.param_index)) end
        if call_result_hole_needed(projection) then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".result") end
        local next_symbol = Support.next_continuation_symbol()
        local signature = call_source_signature(projection)
        local entry = "lalin_native_code_inst_call_" .. mode .. "_" .. symbol_fragment(token)
        local lines = c_prelude()
        projection:append_native_c_declarations(lines)
        append_hole_externs(lines, holes)
        if closure then
            local closure_params = { "void *" }
            for _, param in ipairs(projection.params or {}) do closure_params[#closure_params + 1] = param.abi:native_c_boundary_type() end
            lines[#lines + 1] = "typedef " .. projection.result.abi:native_c_boundary_type() .. " (*lalin_native_call_fn_t)(" .. table.concat(closure_params, ", ") .. ");"
        else
            lines[#lines + 1] = projection:native_c_function_pointer_typedef("lalin_native_call_fn_t")
        end
        lines[#lines + 1] = continuation_extern(next_symbol, Support.stencil_continuation_signature(Support.next_continuation_ordinal(), {}))
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    lalin_native_call_fn_t fn = (lalin_native_call_fn_t)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[1])) .. ";"
        local arg_holes = {}
        local first_arg_hole = closure and 3 or 2
        for i = first_arg_hole, #holes do arg_holes[#arg_holes + 1] = holes[i] end
        append_call_common_lines(lines, input, projection, arg_holes, function(args)
            if closure then
                local env = "(void *)(uintptr_t)" .. frame_load("uintptr_t", hole_address_expr(holes[2]))
                if args == "" then return "fn(" .. env .. ")" end
                return "fn(" .. env .. ", " .. args .. ")"
            end
            return "fn(" .. args .. ")"
        end)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, id_text, family, Native.NativeChunkCallOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { Support.next_continuation_ordinal() })
    end

    local function append_extern_call_source(out, input, projection)
        local token = projection:native_projection_token()
        local id_text = "code.inst.call.extern." .. token
        local axis = Native.NativeCodeInstCallShapeAxis(Native.NativeCodeCallExternTarget, projection)
        local family = Support.code_inst_frame_family("call.extern." .. token, input.domain.target, Support.scalar_bool8(), axis)
        local call_hole = call_rel32_hole("native.hole.code.inst.call.extern." .. token .. ".target")
        local holes = { call_hole }
        for _, param in ipairs(projection.params or {}) do holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.extern." .. token .. ".arg" .. tostring(param.param_index)) end
        if call_result_hole_needed(projection) then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.extern." .. token .. ".result") end
        local next_symbol = Support.next_continuation_symbol()
        local signature = call_source_signature(projection)
        local entry = "lalin_native_code_inst_call_extern_" .. symbol_fragment(token)
        local lines = c_prelude()
        projection:append_native_c_declarations(lines)
        for i = 2, #holes do lines[#lines + 1] = "extern const uint8_t " .. holes[i].symbol .. ";" end
        lines[#lines + 1] = "extern " .. projection:native_c_function_declaration(call_hole.symbol) .. ";"
        lines[#lines + 1] = continuation_extern(next_symbol, Support.stencil_continuation_signature(Support.next_continuation_ordinal(), {}))
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        append_call_common_lines(lines, input, projection, { unpack(holes, 2) }, function(args) return call_hole.symbol .. "(" .. args .. ")" end)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, id_text, family, Native.NativeChunkCallOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { Support.next_continuation_ordinal() })
    end

    local function append_unique_extern_call_source(out, input, projections, projection)
        for _, existing in ipairs(projections) do
            if existing:native_abi_function_projection_equals(projection) then return end
        end
        projections[#projections + 1] = projection
        append_extern_call_source(out, input, projection)
    end

    local function append_result_sources_for_projection(out, input, projection)
        local shape = projection.result:native_code_result_shape()
        append_terminal_source_for_shape(out, input, shape)
        if asdl.isa(shape, Native.NativeCodeResultSRetShape) then
            append_sret_result_copy_source(out, input, shape)
        else
            append_result_copy_source(out, input, shape)
        end
    end

    local function append_unique_result_sources_for_projection(out, input, shapes, projection)
        local shape = projection.result:native_code_result_shape()
        for _, existing in ipairs(shapes) do
            if existing:native_code_result_shape_equals(shape) then return end
        end
        shapes[#shapes + 1] = shape
        append_result_sources_for_projection(out, input, projection)
    end

    local function append_domain_abi_and_call_sources(out, input)
        local extern_call_projections = {}
        local result_shapes = { Native.NativeCodeResultVoidShape }
        for _, scalar_support in ipairs(input.domain.scalars or {}) do
            local scalar = scalar_support.scalar
            if asdl.isa(scalar, Native.NativeScalarPointer) then
                result_shapes[#result_shapes + 1] = Native.NativeCodeResultPointerShape(scalar)
            else
                result_shapes[#result_shapes + 1] = Native.NativeCodeResultScalarShape(scalar)
            end
        end
        for _, projection in ipairs(input.domain.public_abi_adapters or {}) do
            append_public_abi_adapter_source(out, input, projection)
            append_unique_result_sources_for_projection(out, input, result_shapes, projection)
            append_direct_call_source(out, input, projection)
            append_indirect_call_source(out, input, projection, false)
            append_indirect_call_source(out, input, projection, true)
            append_unique_extern_call_source(out, input, extern_call_projections, projection)
        end
        for _, symbol in ipairs((input.domain.runtime and input.domain.runtime.symbols) or {}) do
            append_unique_result_sources_for_projection(out, input, result_shapes, symbol.abi)
            append_unique_extern_call_source(out, input, extern_call_projections, symbol.abi)
        end
    end

    function Core.BinRem:native_binary_family_name() return "rem" end

    function Core.BinDiv:native_integer_c_expr(_scalar, lhs, rhs)
        return "((" .. rhs .. ") == 0 ? 0 : (" .. lhs .. ") / (" .. rhs .. "))", "div"
    end

    function Core.BinRem:native_integer_c_expr(_scalar, lhs, rhs)
        return "((" .. rhs .. ") == 0 ? 0 : (" .. lhs .. ") % (" .. rhs .. "))", "rem"
    end

    function Value.ReductionOp:native_kernel_reduction_token()
        internal_error("unsupported kernel reduction op token")
    end

    function Value.ReductionAdd:native_kernel_reduction_token() return "add" end
    function Value.ReductionMul:native_kernel_reduction_token() return "mul" end
    function Value.ReductionMin:native_kernel_reduction_token() return "min" end
    function Value.ReductionMax:native_kernel_reduction_token() return "max" end
    function Value.ReductionAnd:native_kernel_reduction_token() return "and" end
    function Value.ReductionOr:native_kernel_reduction_token() return "or" end
    function Value.ReductionXor:native_kernel_reduction_token() return "xor" end

    function Value.ReductionOp:native_kernel_reduce_expr(_scalar, _acc, _value)
        internal_error("unsupported kernel reduction op C expression")
    end

    function Value.ReductionAdd:native_kernel_reduce_expr(scalar, acc, value)
        if asdl.isa(scalar, Native.NativeScalarFloat) then return "(" .. acc .. " + " .. value .. ")" end
        return Core.BinAdd:native_integer_c_expr(scalar, acc, value)
    end

    function Value.ReductionMul:native_kernel_reduce_expr(scalar, acc, value)
        if asdl.isa(scalar, Native.NativeScalarFloat) then return "(" .. acc .. " * " .. value .. ")" end
        return Core.BinMul:native_integer_c_expr(scalar, acc, value)
    end

    function Value.ReductionMin:native_kernel_reduce_expr(_scalar, acc, value)
        return "((" .. value .. ") < (" .. acc .. ") ? (" .. value .. ") : (" .. acc .. "))"
    end

    function Value.ReductionMax:native_kernel_reduce_expr(_scalar, acc, value)
        return "((" .. value .. ") > (" .. acc .. ") ? (" .. value .. ") : (" .. acc .. "))"
    end

    function Value.ReductionAnd:native_kernel_reduce_expr(_scalar, acc, value)
        return "(" .. acc .. " & " .. value .. ")"
    end

    function Value.ReductionOr:native_kernel_reduce_expr(_scalar, acc, value)
        return "(" .. acc .. " | " .. value .. ")"
    end

    function Value.ReductionXor:native_kernel_reduce_expr(_scalar, acc, value)
        return "(" .. acc .. " ^ " .. value .. ")"
    end

    function Stencil.StencilScanMode:native_kernel_scan_token()
        internal_error("unsupported kernel scan mode token")
    end

    function Stencil.StencilScanInclusive:native_kernel_scan_token() return "inclusive" end
    function Stencil.StencilScanExclusive:native_kernel_scan_token() return "exclusive" end

    function Stencil.StencilCopySemantics:native_kernel_copy_token()
        internal_error("unsupported kernel copy semantics token")
    end

    function Stencil.StencilCopyNoOverlap:native_kernel_copy_token() return "no_overlap" end
    function Stencil.StencilCopyMayOverlapForward:native_kernel_copy_token() return "may_overlap_forward" end
    function Stencil.StencilCopyMayOverlapBackward:native_kernel_copy_token() return "may_overlap_backward" end
    function Stencil.StencilCopyMemMove:native_kernel_copy_token() return "memmove" end

    function Stencil.StencilPartitionSemantics:native_kernel_partition_token()
        internal_error("unsupported kernel partition semantics token")
    end

    function Stencil.StencilPartitionStable:native_kernel_partition_token() return "stable" end
    function Stencil.StencilPartitionUnstable:native_kernel_partition_token() return "unstable" end

    function Native.NativeKernelValueSourceShape:native_kernel_value_token()
        internal_error("unsupported kernel value source-shape token")
    end

    function Native.NativeKernelValueVoidShape:native_kernel_value_token() return "void" end
    function Native.NativeKernelValueScalarShape:native_kernel_value_token() return self.scalar:native_scalar_token() end
    function Native.NativeKernelValuePointerShape:native_kernel_value_token() return "ptr." .. self.pointer:native_scalar_token() end
    function Native.NativeKernelValueBytesShape:native_kernel_value_token() return "bytes" .. tostring(self.size) .. ".align" .. tostring(self.alignment) end

    function Native.NativeKernelValueSourceShape:native_kernel_family_scalar(target)
        return Support.scalar_bool8(target and target.pointer_bits or nil)
    end

    function Native.NativeKernelValueScalarShape:native_kernel_family_scalar(_target) return self.scalar end
    function Native.NativeKernelValuePointerShape:native_kernel_family_scalar(_target) return self.pointer end

    function Native.NativeKernelValueSourceShape:native_kernel_c_scalar(_target)
        return nil
    end

    function Native.NativeKernelValueScalarShape:native_kernel_c_scalar(_target) return self.scalar end
    function Native.NativeKernelValuePointerShape:native_kernel_c_scalar(_target) return self.pointer end

    function Native.NativeKernelValueSourceShape:native_kernel_value_size(target)
        return target.pointer_bits / 8
    end

    function Native.NativeKernelValueVoidShape:native_kernel_value_size(_target) return 0 end
    function Native.NativeKernelValueScalarShape:native_kernel_value_size(_target) return self.scalar:native_size_bytes() end
    function Native.NativeKernelValuePointerShape:native_kernel_value_size(_target) return self.pointer:native_size_bytes() end
    function Native.NativeKernelValueBytesShape:native_kernel_value_size(_target) return self.size end

    function Native.NativeKernelValueSourceShape:native_kernel_load_expr(_target, _hole)
        internal_error("kernel value source shape is not scalar-loadable")
    end

    function Native.NativeKernelValueScalarShape:native_kernel_load_expr(_target, hole)
        return frame_load(self.scalar:native_c_scalar_type(), hole_address_expr(hole))
    end

    function Native.NativeKernelValuePointerShape:native_kernel_load_expr(_target, hole)
        return frame_load(self.pointer:native_c_scalar_type(), hole_address_expr(hole))
    end

    function Native.NativeKernelValueSourceShape:native_kernel_store_line(_target, _hole, _expr)
        internal_error("kernel value source shape is not scalar-storable")
    end

    function Native.NativeKernelValueScalarShape:native_kernel_store_line(_target, hole, expr)
        return frame_store(self.scalar:native_c_scalar_type(), hole_address_expr(hole), expr)
    end

    function Native.NativeKernelValuePointerShape:native_kernel_store_line(_target, hole, expr)
        return frame_store(self.pointer:native_c_scalar_type(), hole_address_expr(hole), expr)
    end

    function Native.NativeKernelTripCountSourceShape:native_kernel_trip_token()
        internal_error("unsupported kernel trip-count source-shape token")
    end

    function Native.NativeKernelTripUnknownShape:native_kernel_trip_token() return "unknown" end
    function Native.NativeKernelTripDynamicExactShape:native_kernel_trip_token() return "dynamic_exact" end
    function Native.NativeKernelTripDynamicNonNegativeShape:native_kernel_trip_token() return "dynamic_nonnegative" end

    function Native.NativeKernelTripCountSourceShape:native_kernel_trip_holes(_id_base)
        return {}
    end

    function Native.NativeKernelTripDynamicExactShape:native_kernel_trip_holes(id_base)
        return { frame_offset_hole(id_base .. ".trip") }
    end

    function Native.NativeKernelTripDynamicNonNegativeShape:native_kernel_trip_holes(id_base)
        return { frame_offset_hole(id_base .. ".trip") }
    end

    function Native.NativeKernelTripCountSourceShape:native_kernel_trip_expr(_target, _holes)
        return nil
    end

    function Native.NativeKernelTripDynamicExactShape:native_kernel_trip_expr(_target, holes)
        return frame_load("intptr_t", hole_address_expr(holes[1]))
    end

    function Native.NativeKernelTripDynamicNonNegativeShape:native_kernel_trip_expr(_target, holes)
        return frame_load("intptr_t", hole_address_expr(holes[1]))
    end

    function Native.NativeKernelTripCountSourceShape:native_kernel_trip_adjust_lines(_lines, _trip_name)
        return nil
    end

    function Native.NativeKernelTripDynamicNonNegativeShape:native_kernel_trip_adjust_lines(lines, trip_name)
        lines[#lines + 1] = "    if (" .. trip_name .. " < 0) { " .. trip_name .. " = 0; }"
    end

    function Native.NativeKernelLoopSourceShape:native_kernel_loop_token()
        internal_error("unsupported kernel loop source-shape token")
    end

    function Native.NativeKernelLoopRange1DShape:native_kernel_loop_token()
        return "range1d." .. self.index_scalar:native_scalar_token() .. ".trip." .. self.trip_count:native_kernel_trip_token() .. (self.has_counter and ".counter" or ".nocounter")
    end

    function Native.NativeKernelLaneAddressSourceShape:native_kernel_lane_token()
        internal_error("unsupported kernel lane address source-shape token")
    end

    function Native.NativeKernelLaneScalarAddressShape:native_kernel_lane_token()
        return "scalar." .. self.elem:native_kernel_value_token() .. ".addr." .. self.address:native_scalar_token() .. ".index." .. self.index:native_scalar_token()
    end

    function Native.NativeKernelLaneContiguousAddressShape:native_kernel_lane_token()
        return "contiguous." .. self.elem:native_kernel_value_token() .. ".addr." .. self.address:native_scalar_token() .. ".index." .. self.index:native_scalar_token()
    end

    function Native.NativeKernelLaneStridedAddressShape:native_kernel_lane_token()
        return "strided." .. self.elem:native_kernel_value_token() .. ".addr." .. self.address:native_scalar_token() .. ".index." .. self.index:native_scalar_token()
    end

    function Native.NativeKernelLaneIndexedAddressShape:native_kernel_lane_token()
        return "indexed." .. self.elem:native_kernel_value_token() .. ".addr." .. self.address:native_scalar_token() .. ".index." .. self.index:native_scalar_token()
    end

    local function add_hole(holes, hole)
        holes[#holes + 1] = hole
        return hole
    end

    local function append_kernel_hole_externs(lines, holes)
        for _, hole in ipairs(holes or {}) do
            if not asdl.isa(hole.hole, Native.NativePatchCallRel32) then
                lines[#lines + 1] = "extern const uint8_t " .. hole.symbol .. ";"
            end
        end
    end

    function Native.NativeKernelLaneAddressSourceShape:native_kernel_address_expr(_input, _id_base, _holes, _lines)
        internal_error("unsupported kernel lane address source-shape expression")
    end

    local function lane_base_and_index(shape, _input, id_base, holes)
        local base_hole = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        local index_hole = add_hole(holes, frame_offset_hole(id_base .. ".index"))
        local base = frame_load(shape.address:native_c_scalar_type(), hole_address_expr(base_hole))
        local index = frame_load(shape.index:native_c_scalar_type(), hole_address_expr(index_hole))
        return base, index
    end

    function Native.NativeKernelLaneScalarAddressShape:native_kernel_address_expr(input, id_base, holes, _lines)
        local base_hole = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        return frame_load(self.address:native_c_scalar_type(), hole_address_expr(base_hole))
    end

    function Native.NativeKernelLaneContiguousAddressShape:native_kernel_address_expr(input, id_base, holes, _lines)
        local base, index = lane_base_and_index(self, input, id_base, holes)
        local elem_hole = add_hole(holes, imm32_hole(id_base .. ".elem_size"))
        return "((uintptr_t)(" .. base .. ") + (uintptr_t)(" .. index .. ") * (uintptr_t)" .. hole_address_expr(elem_hole) .. ")"
    end

    function Native.NativeKernelLaneStridedAddressShape:native_kernel_address_expr(input, id_base, holes, _lines)
        local base, index = lane_base_and_index(self, input, id_base, holes)
        local stride_hole = add_hole(holes, frame_offset_hole(id_base .. ".stride"))
        local stride = frame_load(self.index:native_c_scalar_type(), hole_address_expr(stride_hole))
        return "((uintptr_t)(" .. base .. ") + (uintptr_t)(" .. index .. ") * (uintptr_t)(" .. stride .. "))"
    end

    function Native.NativeKernelLaneIndexedAddressShape:native_kernel_address_expr(input, id_base, holes, _lines)
        local base, index = lane_base_and_index(self, input, id_base, holes)
        local elem_hole = add_hole(holes, imm32_hole(id_base .. ".elem_size"))
        return "((uintptr_t)(" .. base .. ") + (uintptr_t)(" .. index .. ") * (uintptr_t)" .. hole_address_expr(elem_hole) .. ")"
    end

    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_token()
        internal_error("unsupported kernel expression source-shape token")
    end

    function Native.NativeKernelExprCodeValueShape:native_kernel_expr_token() return "code_value." .. self.value:native_kernel_value_token() end
    function Native.NativeKernelExprKernelValueShape:native_kernel_expr_token() return "kernel_value." .. self.value:native_kernel_value_token() end
    function Native.NativeKernelExprConstShape:native_kernel_expr_token() return "const." .. self.value:native_kernel_value_token() end
    function Native.NativeKernelExprAffineShape:native_kernel_expr_token() return "affine." .. self.value:native_kernel_value_token() .. ".terms" .. tostring(self.term_count) end
    function Native.NativeKernelExprUnaryShape:native_kernel_expr_token() return "unary." .. self.op:native_unary_family_name() .. "." .. self.value:native_kernel_value_token() end
    function Native.NativeKernelExprCastShape:native_kernel_expr_token() return "cast." .. self.op:native_cast_family_name() .. "." .. self.from:native_kernel_value_token() .. ".to." .. self.to:native_kernel_value_token() end
    function Native.NativeKernelExprBinaryShape:native_kernel_expr_token() return "binary." .. self.op:native_binary_family_name() .. "." .. self.value:native_kernel_value_token() end
    function Native.NativeKernelExprCompareShape:native_kernel_expr_token() return "compare." .. self.cmp:native_compare_family_name() .. "." .. self.operand:native_kernel_value_token() end
    function Native.NativeKernelExprSelectShape:native_kernel_expr_token() return "select." .. self.value:native_kernel_value_token() end
    function Native.NativeKernelExprLaneLoadShape:native_kernel_expr_token() return "lane_load." .. self.lane:native_kernel_lane_token() end

    function Native.NativeKernelValueExprSourceShape:native_kernel_result_value_shape()
        internal_error("unsupported kernel expression result value shape")
    end

    function Native.NativeKernelExprCodeValueShape:native_kernel_result_value_shape() return self.value end
    function Native.NativeKernelExprKernelValueShape:native_kernel_result_value_shape() return self.value end
    function Native.NativeKernelExprConstShape:native_kernel_result_value_shape() return self.value end
    function Native.NativeKernelExprAffineShape:native_kernel_result_value_shape() return self.value end
    function Native.NativeKernelExprUnaryShape:native_kernel_result_value_shape() return self.value end
    function Native.NativeKernelExprCastShape:native_kernel_result_value_shape() return self.to end
    function Native.NativeKernelExprBinaryShape:native_kernel_result_value_shape() return self.value end
    function Native.NativeKernelExprCompareShape:native_kernel_result_value_shape() return Native.NativeKernelValueScalarShape(Support.scalar_bool8()) end
    function Native.NativeKernelExprSelectShape:native_kernel_result_value_shape() return self.value end
    function Native.NativeKernelExprLaneLoadShape:native_kernel_result_value_shape() return self.lane.elem end

    function Native.NativeKernelValueExprSourceShape:native_kernel_inline_expr(_input, _id_base, _holes, _lines)
        internal_error("unsupported kernel inline expression source shape")
    end

    function Native.NativeKernelExprCodeValueShape:native_kernel_inline_expr(input, id_base, holes, _lines)
        local src = add_hole(holes, frame_offset_hole(id_base .. ".src"))
        return self.value:native_kernel_load_expr(input.domain.target, src)
    end

    function Native.NativeKernelExprKernelValueShape:native_kernel_inline_expr(input, id_base, holes, _lines)
        local src = add_hole(holes, frame_offset_hole(id_base .. ".src"))
        return self.value:native_kernel_load_expr(input.domain.target, src)
    end

    function Native.NativeKernelExprConstShape:native_kernel_inline_expr(input, id_base, holes, _lines)
        local scalar = self.value:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel const expressions must be emitted by a byte-copy source") end
        local hole = add_hole(holes, asdl.isa(scalar, Native.NativeScalarPointer) and ptr64_hole(id_base .. ".const") or scalar_immediate_hole(id_base .. ".const", scalar))
        return "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(hole)
    end

    function Native.NativeKernelExprAffineShape:native_kernel_inline_expr(input, id_base, holes, lines)
        local scalar = self.value:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel affine expressions are not scalar source shapes") end
        local c_type = scalar:native_c_scalar_type()
        local var = "kernel_affine_" .. symbol_fragment(id_base)
        local base_hole = add_hole(holes, scalar_immediate_hole(id_base .. ".base", scalar))
        lines[#lines + 1] = "    " .. c_type .. " " .. var .. " = (" .. c_type .. ")" .. hole_address_expr(base_hole) .. ";"
        for i = 0, self.term_count - 1 do
            local term_hole = add_hole(holes, frame_offset_hole(id_base .. ".term" .. tostring(i)))
            local coeff_hole = add_hole(holes, imm32_hole(id_base .. ".coeff" .. tostring(i)))
            lines[#lines + 1] = "    " .. var .. " = (" .. c_type .. ")((intptr_t)" .. var .. " + (intptr_t)" .. self.value:native_kernel_load_expr(input.domain.target, term_hole) .. " * (intptr_t)" .. hole_address_expr(coeff_hole) .. ");"
        end
        return var
    end

    local function kernel_unary_expr(op, scalar, value)
        if op == Core.UnaryNeg then
            if asdl.isa(scalar, Native.NativeScalarFloat) then return "(-(" .. value .. "))" end
            return op:native_integer_c_expr(scalar, value)
        end
        if op == Core.UnaryNot then return "((" .. value .. ") == 0)" end
        if op == Core.UnaryBitNot then return "(~(" .. value .. "))" end
        internal_error("unsupported kernel unary op")
    end

    function Native.NativeKernelExprUnaryShape:native_kernel_inline_expr(input, id_base, holes, lines)
        local scalar = self.value:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel unary expressions are not scalar source shapes") end
        return kernel_unary_expr(self.op, scalar, self.value:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".src"))))
    end

    local function kernel_binary_expr(op, scalar, lhs, rhs)
        if asdl.isa(scalar, Native.NativeScalarFloat) then
            if op == Core.BinAdd or op == Core.BinSub or op == Core.BinMul or op == Core.BinDiv then return op:native_float_c_expr(scalar, lhs, rhs) end
        else
            return op:native_integer_c_expr(scalar, lhs, rhs)
        end
        internal_error("unsupported kernel binary op for scalar")
    end

    function Native.NativeKernelExprCastShape:native_kernel_inline_expr(input, id_base, holes, lines)
        local from_scalar = self.from:native_kernel_c_scalar(input.domain.target)
        local to_scalar = self.to:native_kernel_c_scalar(input.domain.target)
        if from_scalar == nil or to_scalar == nil then internal_error("bytes kernel cast expressions are not scalar source shapes") end
        local src = self.from:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".src")))
        local var = "kernel_cast_" .. symbol_fragment(id_base)
        self.op:append_native_cast_c_lines(lines, from_scalar, to_scalar, src, var)
        return var
    end

    function Native.NativeKernelExprBinaryShape:native_kernel_inline_expr(input, id_base, holes, _lines)
        local scalar = self.value:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel binary expressions are not scalar source shapes") end
        local lhs = self.value:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".lhs")))
        local rhs = self.value:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".rhs")))
        return kernel_binary_expr(self.op, scalar, lhs, rhs)
    end

    function Native.NativeKernelExprCompareShape:native_kernel_inline_expr(input, id_base, holes, _lines)
        local scalar = self.operand:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel compare expressions are not scalar source shapes") end
        local lhs = self.operand:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".lhs")))
        local rhs = self.operand:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".rhs")))
        return "(uint8_t)(" .. self.cmp:native_c_compare_expr(scalar, lhs, rhs) .. ")"
    end

    function Native.NativeKernelExprSelectShape:native_kernel_inline_expr(input, id_base, holes, _lines)
        local scalar = self.value:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel select expressions are not scalar source shapes") end
        local cond = frame_load("uint8_t", hole_address_expr(add_hole(holes, frame_offset_hole(id_base .. ".cond"))))
        local lhs = self.value:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".true")))
        local rhs = self.value:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".false")))
        return "((" .. cond .. ") != 0 ? (" .. lhs .. ") : (" .. rhs .. "))"
    end

    function Native.NativeKernelExprLaneLoadShape:native_kernel_inline_expr(input, id_base, holes, lines)
        local address = self.lane:native_kernel_address_expr(input, id_base .. ".lane", holes, lines)
        local scalar = self.lane.elem:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel lane loads require byte-copy lowering") end
        return "*(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)(" .. address .. ")"
    end

    function Native.NativeKernelPredicateSourceShape:native_kernel_predicate_token()
        internal_error("unsupported kernel predicate source-shape token")
    end

    function Native.NativeKernelPredicateNonZeroShape:native_kernel_predicate_token() return "nonzero" end
    function Native.NativeKernelPredicateCompareConstShape:native_kernel_predicate_token() return "compare_const." .. self.cmp:native_compare_family_name() .. "." .. self.operand:native_kernel_value_token() end
    function Native.NativeKernelPredicateRangeShape:native_kernel_predicate_token() return "range." .. self.operand:native_kernel_value_token() end
    function Native.NativeKernelPredicateLogicalShape:native_kernel_predicate_token() return "logical" .. tostring(self.term_count) end
    function Native.NativeKernelPredicateFloatClassShape:native_kernel_predicate_token() return "float_class." .. self.operand:native_kernel_value_token() end

    function Native.NativeKernelPredicateSourceShape:native_kernel_inline_predicate(_input, _id_base, _holes, _lines)
        internal_error("unsupported kernel predicate source-shape expression")
    end

    function Native.NativeKernelPredicateNonZeroShape:native_kernel_inline_predicate(_input, _id_base, _holes, _lines)
        return "1"
    end

    function Native.NativeKernelPredicateCompareConstShape:native_kernel_inline_predicate(input, id_base, holes, _lines)
        local scalar = self.operand:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel compare predicate is not scalar source shape") end
        local lhs = self.operand:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".value")))
        local rhs_hole = add_hole(holes, scalar_immediate_hole(id_base .. ".const", scalar))
        local rhs = "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(rhs_hole)
        return self.cmp:native_c_compare_expr(scalar, lhs, rhs)
    end

    function Native.NativeKernelPredicateRangeShape:native_kernel_inline_predicate(input, id_base, holes, _lines)
        local scalar = self.operand:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel range predicate is not scalar source shape") end
        local value = self.operand:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".value")))
        local lo = add_hole(holes, scalar_immediate_hole(id_base .. ".lo", scalar))
        local hi = add_hole(holes, scalar_immediate_hole(id_base .. ".hi", scalar))
        return "((" .. value .. ") >= (" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(lo) .. " && (" .. value .. ") < (" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(hi) .. ")"
    end

    function Native.NativeKernelPredicateLogicalShape:native_kernel_inline_predicate(input, id_base, holes, _lines)
        local parts = {}
        for i = 0, self.term_count - 1 do
            parts[#parts + 1] = "(" .. frame_load("uint8_t", hole_address_expr(add_hole(holes, frame_offset_hole(id_base .. ".term" .. tostring(i))))) .. " != 0)"
        end
        if #parts == 0 then return "1" end
        return table.concat(parts, " && ")
    end

    function Native.NativeKernelPredicateFloatClassShape:native_kernel_inline_predicate(input, id_base, holes, _lines)
        local scalar = self.operand:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel float-class predicate is not scalar source shape") end
        local value = self.operand:native_kernel_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".value")))
        return "((" .. value .. ") == (" .. value .. "))"
    end

    function Native.NativeKernelReducerSourceShape:native_kernel_reducer_token()
        return self.op:native_kernel_reduction_token() .. "." .. self.value:native_kernel_value_token()
    end

    function Native.NativeKernelCallSourceShape:native_kernel_call_token()
        internal_error("unsupported kernel call source-shape token")
    end

    function Native.NativeKernelCallInternalShape:native_kernel_call_token() return "internal" end
    function Native.NativeKernelCallExternShape:native_kernel_call_token() return "extern" end
    function Native.NativeKernelCallEffectOnlyShape:native_kernel_call_token() return "effect_only" .. tostring(self.effect_count) end

    function Native.NativeKernelEffectSourceShape:native_kernel_effect_token()
        internal_error("unsupported kernel effect source-shape token")
    end

    function Native.NativeKernelEffectStoreShape:native_kernel_effect_token() return "store." .. self.dst:native_kernel_lane_token() .. "." .. self.value:native_kernel_expr_token() end
    function Native.NativeKernelEffectScanShape:native_kernel_effect_token() return "scan." .. self.mode:native_kernel_scan_token() .. "." .. self.dst:native_kernel_lane_token() .. "." .. self.reducer:native_kernel_reducer_token() end
    function Native.NativeKernelEffectPartitionShape:native_kernel_effect_token() return "partition." .. self.semantics:native_kernel_partition_token() .. "." .. self.dst:native_kernel_lane_token() .. "." .. self.src:native_kernel_expr_token() .. "." .. self.pred:native_kernel_predicate_token() end
    function Native.NativeKernelEffectCopyShape:native_kernel_effect_token() return "copy." .. self.semantics:native_kernel_copy_token() .. "." .. self.dst:native_kernel_lane_token() .. "." .. self.src:native_kernel_expr_token() end
    function Native.NativeKernelEffectScatterReduceShape:native_kernel_effect_token() return "scatter_reduce." .. self.dst:native_kernel_lane_token() .. "." .. self.value:native_kernel_expr_token() .. "." .. self.reducer:native_kernel_reducer_token() end
    function Native.NativeKernelEffectFoldShape:native_kernel_effect_token() return "fold." .. self.reducer:native_kernel_reducer_token() end
    function Native.NativeKernelEffectCallShape:native_kernel_effect_token() return "call." .. self.call:native_kernel_call_token() end

    function Native.NativeKernelResultSourceShape:native_kernel_result_token()
        internal_error("unsupported kernel result source-shape token")
    end

    function Native.NativeKernelResultVoidShape:native_kernel_result_token() return "void" end
    function Native.NativeKernelResultValueShape:native_kernel_result_token() return "value." .. self.value:native_kernel_expr_token() end
    function Native.NativeKernelResultFindShape:native_kernel_result_token() return "find." .. self.src:native_kernel_expr_token() .. "." .. self.pred:native_kernel_predicate_token() end
    function Native.NativeKernelResultReductionShape:native_kernel_result_token() return "reduction." .. self.reducer:native_kernel_reducer_token() end
    function Native.NativeKernelResultClosedFormShape:native_kernel_result_token() return "closed_form." .. self.value:native_kernel_value_token() end
    function Native.NativeKernelResultOriginalControlShape:native_kernel_result_token() return "original_control" end

    function Native.NativeKernelProofSourceShape:native_kernel_proof_token()
        internal_error("unsupported kernel proof source-shape token")
    end

    function Native.NativeKernelProofFlowShape:native_kernel_proof_token() return "flow" end
    function Native.NativeKernelProofValueShape:native_kernel_proof_token() return "value" end
    function Native.NativeKernelProofMemoryShape:native_kernel_proof_token() return "memory" end
    function Native.NativeKernelProofEffectShape:native_kernel_proof_token() return "effect" end
    function Native.NativeKernelProofFunctionEquivalenceShape:native_kernel_proof_token() return "function_equivalence" end

    function Native.NativeKernelBodySourceShape:native_kernel_body_token()
        return "body." .. self.loop:native_kernel_loop_token() .. ".lanes" .. tostring(self.lane_count) .. ".bindings" .. tostring(self.binding_count) .. ".effects" .. tostring(self.effect_count) .. ".result." .. self.result:native_kernel_result_token()
    end

    function Native.NativeKernelPlanSourceShape:native_kernel_plan_token()
        internal_error("unsupported kernel plan source-shape token")
    end

    function Native.NativeKernelNoPlanSourceShape:native_kernel_plan_token() return "no_plan" end
    function Native.NativeKernelPlannedSourceShape:native_kernel_plan_token() return "planned." .. self.body:native_kernel_body_token() end

    function Native.NativeKernelOpSourceShape:native_kernel_op_source_token()
        internal_error("unsupported kernel op source-shape token")
    end

    function Native.NativeKernelDomainOpShape:native_kernel_op_source_token() return "domain." .. self.loop:native_kernel_loop_token() end
    function Native.NativeKernelLaneOpShape:native_kernel_op_source_token() return "lane." .. self.lane:native_kernel_lane_token() end
    function Native.NativeKernelExprOpShape:native_kernel_op_source_token() return "expr." .. self.expr:native_kernel_expr_token() end
    function Native.NativeKernelEffectOpShape:native_kernel_op_source_token() return "effect." .. self.effect:native_kernel_effect_token() end
    function Native.NativeKernelResultOpShape:native_kernel_op_source_token() return "result." .. self.result:native_kernel_result_token() end
    function Native.NativeKernelProofOpShape:native_kernel_op_source_token() return "proof." .. self.proof:native_kernel_proof_token() end
    function Native.NativeKernelBodyOpShape:native_kernel_op_source_token() return self.body:native_kernel_body_token() end
    function Native.NativeKernelPlanOpShape:native_kernel_op_source_token() return "plan." .. self.plan:native_kernel_plan_token() end

    local function kernel_family(input, op_shape, role)
        local name = op_shape:native_kernel_op_source_token()
        return Support.family(
            Support.kernel_family_id(name),
            role,
            {
                Support.axis_target(input.domain.target),
                Support.axis_kernel(Native.NativeKernelSourceShapeAxis(op_shape)),
            },
            Support.protocol_void_none()
        )
    end

    local function kernel_next_signature(frame_scalar)
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        return Support.spill_all_stencil_signature(frame_scalar, {}, { next_signature }), next_ordinal, next_signature, Support.next_continuation_symbol()
    end

    local function append_kernel_manifest_source(out, input, op_shape, role, signature, extraction, entry, lines, holes, continuation_ordinals, extra_relocations)
        append_manifest_source(
            out,
            "kernel." .. op_shape:native_kernel_op_source_token(),
            kernel_family(input, op_shape, role),
            Native.NativeChunkKernelOp,
            signature,
            extraction,
            entry,
            lines,
            holes,
            continuation_ordinals or {},
            extra_relocations or {}
        )
    end

    function Native.NativeKernelOpSourceShape:append_native_template_sources(_out, _input)
        internal_error("unsupported KernelOp source shape")
    end

    function Native.NativeKernelDomainOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local id_base = "native.hole.kernel." .. token
        local holes = {}
        local counter_hole
        if self.loop.has_counter then counter_hole = add_hole(holes, frame_offset_hole(id_base .. ".counter")) end
        local trip_holes = self.loop.trip_count:native_kernel_trip_holes(id_base)
        for _, hole in ipairs(trip_holes) do holes[#holes + 1] = hole end
        local then_ordinal = Support.then_continuation_ordinal()
        local else_ordinal = Support.else_continuation_ordinal()
        local then_signature = Support.stencil_continuation_signature(then_ordinal, {})
        local else_signature = Support.stencil_continuation_signature(else_ordinal, {})
        local signature = Support.spill_all_stencil_signature(self.loop.index_scalar, {}, { then_signature, else_signature })
        local then_symbol = Support.then_continuation_symbol()
        local else_symbol = Support.else_continuation_symbol()
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local lines = c_prelude()
        append_kernel_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(then_symbol, then_signature)
        lines[#lines + 1] = continuation_extern(else_symbol, else_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        local counter_expr = counter_hole and frame_load(self.loop.index_scalar:native_c_scalar_type(), hole_address_expr(counter_hole)) or "0"
        local trip_expr = self.loop.trip_count:native_kernel_trip_expr(input.domain.target, trip_holes)
        lines[#lines + 1] = "    intptr_t kernel_counter = (intptr_t)(" .. counter_expr .. ");"
        if trip_expr ~= nil then
            lines[#lines + 1] = "    intptr_t kernel_trip = (intptr_t)(" .. trip_expr .. ");"
            self.loop.trip_count:native_kernel_trip_adjust_lines(lines, "kernel_trip")
            lines[#lines + 1] = "    if (kernel_counter < kernel_trip) {"
        else
            lines[#lines + 1] = "    if (1) {"
        end
        if counter_hole ~= nil then lines[#lines + 1] = frame_store(self.loop.index_scalar:native_c_scalar_type(), hole_address_expr(counter_hole), "(" .. self.loop.index_scalar:native_c_scalar_type() .. ")(kernel_counter + 1)") end
        lines[#lines + 1] = "        " .. then_symbol.name .. "(frame);"
        lines[#lines + 1] = "    } else {"
        lines[#lines + 1] = "        " .. else_symbol.name .. "(frame);"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelDomain, signature, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), entry, lines, holes, { then_ordinal, else_ordinal })
    end

    function Native.NativeKernelLaneOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local id_base = "native.hole.kernel." .. token
        local holes = {}
        local dst_hole = add_hole(holes, frame_offset_hole(id_base .. ".dst"))
        local address = self.lane:native_kernel_address_expr(input, id_base, holes, {})
        local signature, next_ordinal, next_signature, next_symbol = kernel_next_signature(self.lane.address)
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local lines = c_prelude()
        append_kernel_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = frame_store(self.lane.address:native_c_scalar_type(), hole_address_expr(dst_hole), "(" .. self.lane.address:native_c_scalar_type() .. ")(" .. address .. ")")
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelLane, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    function Native.NativeKernelExprOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local id_base = "native.hole.kernel." .. token
        local holes = {}
        local result_shape = self.expr:native_kernel_result_value_shape()
        local dst_hole = add_hole(holes, frame_offset_hole(id_base .. ".dst"))
        local scalar = result_shape:native_kernel_family_scalar(input.domain.target)
        local signature, next_ordinal, next_signature, next_symbol = kernel_next_signature(scalar)
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local body = {}
        body[#body + 1] = continuation_extern(next_symbol, next_signature)
        body[#body + 1] = "void " .. entry .. "(uint8_t *frame) {"
        if asdl.isa(result_shape, Native.NativeKernelValueBytesShape) then
            body[#body + 1] = "    __builtin_memset(frame + " .. hole_address_expr(dst_hole) .. ", 0, " .. tostring(result_shape.size) .. ");"
        else
            local expr = self.expr:native_kernel_inline_expr(input, id_base, holes, body)
            body[#body + 1] = result_shape:native_kernel_store_line(input.domain.target, dst_hole, expr)
        end
        body[#body + 1] = "    " .. next_symbol.name .. "(frame);"
        body[#body + 1] = "}"
        local lines = c_prelude()
        append_kernel_hole_externs(lines, holes)
        for _, line in ipairs(body) do lines[#lines + 1] = line end
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelExpr, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    local function kernel_store_value_to_address(lines, input, value_shape, address_expr, value_expr)
        local scalar = value_shape:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then
            internal_error("bytes kernel stores require explicit byte-copy source shape")
        end
        lines[#lines + 1] = "    *(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)(" .. address_expr .. ") = (" .. scalar:native_c_scalar_type() .. ")(" .. value_expr .. ");"
    end

    function Native.NativeKernelEffectSourceShape:native_kernel_emit_effect(_input, _id_base, _holes, _lines)
        internal_error("unsupported kernel effect source-shape emission")
    end

    function Native.NativeKernelEffectStoreShape:native_kernel_emit_effect(input, id_base, holes, lines)
        local address = self.dst:native_kernel_address_expr(input, id_base .. ".dst", holes, lines)
        local value = self.value:native_kernel_inline_expr(input, id_base .. ".value", holes, lines)
        kernel_store_value_to_address(lines, input, self.value:native_kernel_result_value_shape(), address, value)
    end

    function Native.NativeKernelEffectCopyShape:native_kernel_emit_effect(input, id_base, holes, lines)
        local address = self.dst:native_kernel_address_expr(input, id_base .. ".dst", holes, lines)
        local value = self.src:native_kernel_inline_expr(input, id_base .. ".src", holes, lines)
        kernel_store_value_to_address(lines, input, self.src:native_kernel_result_value_shape(), address, value)
    end

    function Native.NativeKernelEffectPartitionShape:native_kernel_emit_effect(input, id_base, holes, lines)
        local pred = self.pred:native_kernel_inline_predicate(input, id_base .. ".pred", holes, lines)
        lines[#lines + 1] = "    if (" .. pred .. ") {"
        local address = self.dst:native_kernel_address_expr(input, id_base .. ".dst", holes, lines)
        local value = self.src:native_kernel_inline_expr(input, id_base .. ".src", holes, lines)
        kernel_store_value_to_address(lines, input, self.src:native_kernel_result_value_shape(), address, value)
        lines[#lines + 1] = "    }"
    end

    function Native.NativeKernelEffectScanShape:native_kernel_emit_effect(input, id_base, holes, lines)
        local value_shape = self.reducer.value
        local scalar = value_shape:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel scan reducers require byte-aware source shapes") end
        local state_hole = add_hole(holes, frame_offset_hole(id_base .. ".state"))
        local address = self.dst:native_kernel_address_expr(input, id_base .. ".dst", holes, lines)
        local old = value_shape:native_kernel_load_expr(input.domain.target, state_hole)
        local loaded = "*(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)(" .. address .. ")"
        local reduced = self.reducer.op:native_kernel_reduce_expr(scalar, old, loaded)
        if self.mode == Stencil.StencilScanExclusive then
            kernel_store_value_to_address(lines, input, value_shape, address, old)
            lines[#lines + 1] = value_shape:native_kernel_store_line(input.domain.target, state_hole, reduced)
        else
            lines[#lines + 1] = value_shape:native_kernel_store_line(input.domain.target, state_hole, reduced)
            kernel_store_value_to_address(lines, input, value_shape, address, reduced)
        end
    end

    function Native.NativeKernelEffectScatterReduceShape:native_kernel_emit_effect(input, id_base, holes, lines)
        local value_shape = self.reducer.value
        local scalar = value_shape:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel scatter-reduce reducers require byte-aware source shapes") end
        local address = self.dst:native_kernel_address_expr(input, id_base .. ".dst", holes, lines)
        local value = self.value:native_kernel_inline_expr(input, id_base .. ".value", holes, lines)
        local old = "*(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)(" .. address .. ")"
        local reduced = self.reducer.op:native_kernel_reduce_expr(scalar, old, value)
        kernel_store_value_to_address(lines, input, value_shape, address, reduced)
    end

    function Native.NativeKernelEffectFoldShape:native_kernel_emit_effect(input, id_base, holes, lines)
        local value_shape = self.reducer.value
        local scalar = value_shape:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes kernel fold reducers require byte-aware source shapes") end
        local state_hole = add_hole(holes, frame_offset_hole(id_base .. ".state"))
        local value_hole = add_hole(holes, frame_offset_hole(id_base .. ".value"))
        local old = value_shape:native_kernel_load_expr(input.domain.target, state_hole)
        local value = value_shape:native_kernel_load_expr(input.domain.target, value_hole)
        lines[#lines + 1] = value_shape:native_kernel_store_line(input.domain.target, state_hole, self.reducer.op:native_kernel_reduce_expr(scalar, old, value))
    end

    function Native.NativeKernelEffectCallShape:native_kernel_emit_effect(input, id_base, holes, lines)
        return self.call:native_kernel_emit_call(input, id_base, holes, lines)
    end

    function Native.NativeKernelCallSourceShape:native_kernel_emit_call(_input, _id_base, _holes, _lines)
        internal_error("unsupported kernel call source-shape emission")
    end

    function Native.NativeKernelCallEffectOnlyShape:native_kernel_emit_call(_input, _id_base, _holes, lines)
        lines[#lines + 1] = "    __asm__ volatile(\"\" ::: \"memory\");"
    end

    function Native.NativeKernelCallInternalShape:native_kernel_emit_call(_input, id_base, holes, lines)
        local target_hole = add_hole(holes, call_rel32_hole(id_base .. ".target"))
        lines[#lines + 1] = "    extern void " .. target_hole.symbol .. "(uint8_t *frame);"
        lines[#lines + 1] = "    " .. target_hole.symbol .. "(frame);"
    end

    function Native.NativeKernelCallExternShape:native_kernel_emit_call(_input, id_base, holes, lines)
        local target_hole = add_hole(holes, call_rel32_hole(id_base .. ".target"))
        lines[#lines + 1] = "    extern void " .. target_hole.symbol .. "(uint8_t *frame);"
        lines[#lines + 1] = "    " .. target_hole.symbol .. "(frame);"
    end

    function Native.NativeKernelEffectOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local id_base = "native.hole.kernel." .. token
        local holes = {}
        local signature, next_ordinal, next_signature, next_symbol = kernel_next_signature(Support.scalar_bool8())
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        self.effect:native_kernel_emit_effect(input, id_base, holes, lines)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        local header = c_prelude()
        append_kernel_hole_externs(header, holes)
        for i = 4, #lines do header[#header + 1] = lines[i] end
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelEffect, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, header, holes, { next_ordinal })
    end

    function Native.NativeKernelResultSourceShape:native_kernel_emit_result(_input, _id_base, _holes, _lines)
        internal_error("unsupported kernel result source-shape emission")
    end

    function Native.NativeKernelResultVoidShape:native_kernel_emit_result(_input, _id_base, _holes, lines)
        lines[#lines + 1] = "    (void)frame;"
    end

    function Native.NativeKernelResultValueShape:native_kernel_emit_result(input, id_base, holes, lines)
        local dst = add_hole(holes, frame_offset_hole(id_base .. ".result"))
        local expr = self.value:native_kernel_inline_expr(input, id_base .. ".value", holes, lines)
        lines[#lines + 1] = self.value:native_kernel_result_value_shape():native_kernel_store_line(input.domain.target, dst, expr)
    end

    function Native.NativeKernelResultFindShape:native_kernel_emit_result(input, id_base, holes, lines)
        local dst = add_hole(holes, frame_offset_hole(id_base .. ".result"))
        local pred = self.pred:native_kernel_inline_predicate(input, id_base .. ".pred", holes, lines)
        local expr = self.src:native_kernel_inline_expr(input, id_base .. ".src", holes, lines)
        lines[#lines + 1] = "    if (" .. pred .. ") {"
        lines[#lines + 1] = self.src:native_kernel_result_value_shape():native_kernel_store_line(input.domain.target, dst, expr)
        lines[#lines + 1] = "    }"
    end

    function Native.NativeKernelResultReductionShape:native_kernel_emit_result(input, id_base, holes, lines)
        local dst = add_hole(holes, frame_offset_hole(id_base .. ".result"))
        local state = add_hole(holes, frame_offset_hole(id_base .. ".state"))
        lines[#lines + 1] = self.reducer.value:native_kernel_store_line(input.domain.target, dst, self.reducer.value:native_kernel_load_expr(input.domain.target, state))
    end

    function Native.NativeKernelResultClosedFormShape:native_kernel_emit_result(input, id_base, holes, lines)
        local dst = add_hole(holes, frame_offset_hole(id_base .. ".result"))
        local src = add_hole(holes, frame_offset_hole(id_base .. ".value"))
        lines[#lines + 1] = self.value:native_kernel_store_line(input.domain.target, dst, self.value:native_kernel_load_expr(input.domain.target, src))
    end

    function Native.NativeKernelResultOriginalControlShape:native_kernel_emit_result(_input, _id_base, _holes, lines)
        lines[#lines + 1] = "    __asm__ volatile(\"\" ::: \"memory\");"
    end

    function Native.NativeKernelResultOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local id_base = "native.hole.kernel." .. token
        local holes = {}
        local signature = Support.spill_all_stencil_signature(Support.scalar_bool8(), {}, {})
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local lines = c_prelude()
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        self.result:native_kernel_emit_result(input, id_base, holes, lines)
        lines[#lines + 1] = "}"
        local header = c_prelude()
        append_kernel_hole_externs(header, holes)
        for i = 4, #lines do header[#header + 1] = lines[i] end
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelResult, signature, Native.NativeExtractTerminalContinuation, entry, header, holes, {})
    end

    function Native.NativeKernelProofOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local signature, next_ordinal, next_signature, next_symbol = kernel_next_signature(Support.scalar_bool8())
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    __asm__ volatile(\"\" ::: \"memory\");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelProof, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    function Native.NativeKernelBodyOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local signature, next_ordinal, next_signature, next_symbol = kernel_next_signature(Support.scalar_bool8())
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    __asm__ volatile(\"\" ::: \"memory\");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelBody, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    function Native.NativeKernelPlanOpShape:append_native_template_sources(out, input)
        local token = self:native_kernel_op_source_token()
        local signature, next_ordinal, next_signature, next_symbol = kernel_next_signature(Support.scalar_bool8())
        local entry = "lalin_native_kernel_" .. symbol_fragment(token)
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    __asm__ volatile(\"\" ::: \"memory\");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_kernel_manifest_source(out, input, self, Native.NativeRoleKernelPlan, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    local function append_domain_kernel_sources(out, input)
        for _, shape in ipairs((input.domain.kernel_sources and input.domain.kernel_sources.shapes) or {}) do
            shape:append_native_template_sources(out, input)
        end
    end

    function Stencil.StencilProducerOrder:native_stencil_order_token()
        internal_error("unsupported stencil producer order token")
    end
    function Stencil.StencilProducerForward:native_stencil_order_token() return "forward" end
    function Stencil.StencilProducerBackward:native_stencil_order_token() return "backward" end

    function Native.NativeStencilValueSourceShape:native_stencil_value_token()
        internal_error("unsupported stencil value source-shape token")
    end
    function Native.NativeStencilValueVoidShape:native_stencil_value_token() return "void" end
    function Native.NativeStencilValueScalarShape:native_stencil_value_token() return self.scalar:native_scalar_token() end
    function Native.NativeStencilValuePointerShape:native_stencil_value_token() return "ptr." .. self.pointer:native_scalar_token() end
    function Native.NativeStencilValueBytesShape:native_stencil_value_token() return "bytes" .. tostring(self.size) .. ".align" .. tostring(self.alignment) end

    function Native.NativeStencilValueSourceShape:native_stencil_family_scalar(target)
        return Support.scalar_bool8(target and target.pointer_bits or nil)
    end
    function Native.NativeStencilValueScalarShape:native_stencil_family_scalar(_target) return self.scalar end
    function Native.NativeStencilValuePointerShape:native_stencil_family_scalar(_target) return self.pointer end

    function Native.NativeStencilValueSourceShape:native_stencil_c_scalar(_target)
        return nil
    end
    function Native.NativeStencilValueScalarShape:native_stencil_c_scalar(_target) return self.scalar end
    function Native.NativeStencilValuePointerShape:native_stencil_c_scalar(_target) return self.pointer end

    function Native.NativeStencilValueSourceShape:native_stencil_value_size(target)
        return target.pointer_bits / 8
    end
    function Native.NativeStencilValueVoidShape:native_stencil_value_size(_target) return 0 end
    function Native.NativeStencilValueScalarShape:native_stencil_value_size(_target) return self.scalar:native_size_bytes() end
    function Native.NativeStencilValuePointerShape:native_stencil_value_size(_target) return self.pointer:native_size_bytes() end
    function Native.NativeStencilValueBytesShape:native_stencil_value_size(_target) return self.size end

    function Native.NativeStencilValueSourceShape:native_stencil_load_expr(_target, _hole)
        internal_error("stencil value source shape is not scalar-loadable")
    end
    function Native.NativeStencilValueScalarShape:native_stencil_load_expr(_target, hole)
        return frame_load(self.scalar:native_c_scalar_type(), hole_address_expr(hole))
    end
    function Native.NativeStencilValuePointerShape:native_stencil_load_expr(_target, hole)
        return frame_load(self.pointer:native_c_scalar_type(), hole_address_expr(hole))
    end

    function Native.NativeStencilValueSourceShape:native_stencil_store_line(_target, _hole, _expr)
        internal_error("stencil value source shape is not scalar-storable")
    end
    function Native.NativeStencilValueScalarShape:native_stencil_store_line(_target, hole, expr)
        return frame_store(self.scalar:native_c_scalar_type(), hole_address_expr(hole), expr)
    end
    function Native.NativeStencilValuePointerShape:native_stencil_store_line(_target, hole, expr)
        return frame_store(self.pointer:native_c_scalar_type(), hole_address_expr(hole), expr)
    end

    local function append_stencil_hole_externs(lines, holes)
        for _, hole in ipairs(holes or {}) do
            if not asdl.isa(hole.hole, Native.NativePatchCallRel32) then
                lines[#lines + 1] = "extern const uint8_t " .. hole.symbol .. ";"
            end
        end
    end

    function Native.NativeStencilProducerSourceShape:native_stencil_producer_token()
        internal_error("unsupported stencil producer source-shape token")
    end
    function Native.NativeStencilProducerRange1DShape:native_stencil_producer_token()
        return "range1d." .. self.index:native_stencil_value_token() .. ".step" .. tostring(self.step) .. "." .. self.order:native_stencil_order_token()
    end
    function Native.NativeStencilProducerRangeNDShape:native_stencil_producer_token() return "rangend.rank" .. tostring(self.rank) end
    function Native.NativeStencilProducerWindowNDShape:native_stencil_producer_token() return "windownd.rank" .. tostring(self.rank) .. ".windows" .. tostring(self.window_count) end
    function Native.NativeStencilProducerTiledNDShape:native_stencil_producer_token() return "tilednd.rank" .. tostring(self.rank) .. ".tiles" .. tostring(self.tile_count) end

    function Native.NativeStencilAccessSourceShape:native_stencil_access_token()
        internal_error("unsupported stencil access source-shape token")
    end
    function Native.NativeStencilAccessScalarShape:native_stencil_access_token() return "scalar." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilAccessContiguousShape:native_stencil_access_token() return "contiguous." .. self.value:native_stencil_value_token() .. ".stride" .. tostring(self.stride) end
    function Native.NativeStencilAccessIndexedShape:native_stencil_access_token() return "indexed." .. self.value:native_stencil_value_token() .. ".index." .. self.index:native_stencil_value_token() .. ".stride" .. tostring(self.stride) end
    function Native.NativeStencilAccessAffine1DShape:native_stencil_access_token() return "affine1d." .. self.value:native_stencil_value_token() .. ".scale" .. tostring(self.scale) end
    function Native.NativeStencilAccessAffineNDShape:native_stencil_access_token() return "affinend." .. self.value:native_stencil_value_token() .. ".terms" .. tostring(self.term_count) end
    function Native.NativeStencilAccessFieldProjectionShape:native_stencil_access_token() return "field." .. symbol_fragment(self.field_name) .. "." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilAccessSoAComponentShape:native_stencil_access_token() return "soa." .. symbol_fragment(self.field_name) .. "." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilAccessSliceDescriptorShape:native_stencil_access_token() return "slice_descriptor." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilAccessByteSpanDescriptorShape:native_stencil_access_token() return "bytespan_descriptor." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilAccessViewDescriptorShape:native_stencil_access_token() return "view_descriptor." .. self.value:native_stencil_value_token() .. (self.has_const_stride and ".const_stride" or ".dynamic_stride") end

    function Stencil.StencilUnaryOp:native_stencil_unary_token()
        internal_error("unsupported stencil unary op token")
    end
    function Stencil.StencilUnaryIdentity:native_stencil_unary_token() return "identity" end
    function Stencil.StencilUnaryNeg:native_stencil_unary_token() return "neg" end
    function Stencil.StencilUnaryBitNot:native_stencil_unary_token() return "bitnot" end
    function Stencil.StencilUnaryBoolNot:native_stencil_unary_token() return "boolnot" end

    function Stencil.StencilUnaryOp:native_stencil_unary_expr(_scalar, _value)
        internal_error("unsupported stencil unary op C expression")
    end
    function Stencil.StencilUnaryIdentity:native_stencil_unary_expr(_scalar, value) return value end
    function Stencil.StencilUnaryNeg:native_stencil_unary_expr(_scalar, value) return "(-(" .. value .. "))" end
    function Stencil.StencilUnaryBitNot:native_stencil_unary_expr(_scalar, value) return "(~(" .. value .. "))" end
    function Stencil.StencilUnaryBoolNot:native_stencil_unary_expr(_scalar, value) return "((" .. value .. ") == 0)" end

    function Stencil.StencilBinaryOp:native_stencil_binary_token()
        internal_error("unsupported stencil binary op token")
    end
    function Stencil.StencilBinaryAdd:native_stencil_binary_token() return "add" end
    function Stencil.StencilBinarySub:native_stencil_binary_token() return "sub" end
    function Stencil.StencilBinaryMul:native_stencil_binary_token() return "mul" end
    function Stencil.StencilBinaryDiv:native_stencil_binary_token() return "div" end
    function Stencil.StencilBinaryMod:native_stencil_binary_token() return "mod" end
    function Stencil.StencilBinaryAnd:native_stencil_binary_token() return "and" end
    function Stencil.StencilBinaryOr:native_stencil_binary_token() return "or" end
    function Stencil.StencilBinaryXor:native_stencil_binary_token() return "xor" end
    function Stencil.StencilBinaryShl:native_stencil_binary_token() return "shl" end
    function Stencil.StencilBinaryLShr:native_stencil_binary_token() return "lshr" end
    function Stencil.StencilBinaryAShr:native_stencil_binary_token() return "ashr" end
    function Stencil.StencilBinaryMin:native_stencil_binary_token() return "min" end
    function Stencil.StencilBinaryMax:native_stencil_binary_token() return "max" end

    function Stencil.StencilBinaryOp:native_stencil_binary_expr(_scalar, _lhs, _rhs)
        internal_error("unsupported stencil binary op C expression")
    end
    function Stencil.StencilBinaryAdd:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") + (" .. rhs .. "))" end
    function Stencil.StencilBinarySub:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") - (" .. rhs .. "))" end
    function Stencil.StencilBinaryMul:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") * (" .. rhs .. "))" end
    function Stencil.StencilBinaryDiv:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. rhs .. ") == 0 ? 0 : ((" .. lhs .. ") / (" .. rhs .. ")))" end
    function Stencil.StencilBinaryMod:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. rhs .. ") == 0 ? 0 : ((" .. lhs .. ") % (" .. rhs .. ")))" end
    function Stencil.StencilBinaryAnd:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") & (" .. rhs .. "))" end
    function Stencil.StencilBinaryOr:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") | (" .. rhs .. "))" end
    function Stencil.StencilBinaryXor:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") ^ (" .. rhs .. "))" end
    function Stencil.StencilBinaryShl:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") << (" .. rhs .. "))" end
    function Stencil.StencilBinaryLShr:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") >> (" .. rhs .. "))" end
    function Stencil.StencilBinaryAShr:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") >> (" .. rhs .. "))" end
    function Stencil.StencilBinaryMin:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") < (" .. rhs .. ") ? (" .. lhs .. ") : (" .. rhs .. "))" end
    function Stencil.StencilBinaryMax:native_stencil_binary_expr(_scalar, lhs, rhs) return "((" .. lhs .. ") > (" .. rhs .. ") ? (" .. lhs .. ") : (" .. rhs .. "))" end

    function Native.NativeStencilPointSourceShape:native_stencil_point_token()
        internal_error("unsupported stencil point source-shape token")
    end
    function Native.NativeStencilPointInputShape:native_stencil_point_token() return "input." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilPointWindowInputShape:native_stencil_point_token() return "window_input." .. self.value:native_stencil_value_token() .. ".offsets" .. tostring(self.offset_count) end
    function Native.NativeStencilPointConstShape:native_stencil_point_token() return "const." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilPointUnaryShape:native_stencil_point_token() return "unary." .. self.op:native_stencil_unary_token() .. "." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilPointBinaryShape:native_stencil_point_token() return "binary." .. self.op:native_stencil_binary_token() .. "." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilPointCastShape:native_stencil_point_token() return "cast." .. self.op:native_cast_family_name() .. "." .. self.from:native_stencil_value_token() .. ".to." .. self.to:native_stencil_value_token() end
    function Native.NativeStencilPointPredicateShape:native_stencil_point_token() return "predicate." .. self.pred:native_kernel_predicate_token() .. "." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilPointCompareShape:native_stencil_point_token() return "compare." .. self.cmp:native_compare_family_name() .. "." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilPointSelectShape:native_stencil_point_token() return "select." .. self.pred:native_kernel_predicate_token() .. "." .. self.value:native_stencil_value_token() end

    function Native.NativeStencilPointSourceShape:native_stencil_result_value_shape()
        internal_error("unsupported stencil point result value shape")
    end
    function Native.NativeStencilPointInputShape:native_stencil_result_value_shape() return self.value end
    function Native.NativeStencilPointWindowInputShape:native_stencil_result_value_shape() return self.value end
    function Native.NativeStencilPointConstShape:native_stencil_result_value_shape() return self.value end
    function Native.NativeStencilPointUnaryShape:native_stencil_result_value_shape() return self.value end
    function Native.NativeStencilPointBinaryShape:native_stencil_result_value_shape() return self.value end
    function Native.NativeStencilPointCastShape:native_stencil_result_value_shape() return self.to end
    function Native.NativeStencilPointPredicateShape:native_stencil_result_value_shape() return self.value end
    function Native.NativeStencilPointCompareShape:native_stencil_result_value_shape() return Native.NativeStencilValueScalarShape(Support.scalar_bool8()) end
    function Native.NativeStencilPointSelectShape:native_stencil_result_value_shape() return self.value end

    function Native.NativeStencilBodySourceShape:native_stencil_body_token()
        internal_error("unsupported stencil body source-shape token")
    end
    function Native.NativeStencilBodyPointShape:native_stencil_body_token() return "point." .. self.expr:native_stencil_point_token() end

    function Stencil.StencilStoreSemantics:native_stencil_store_token()
        internal_error("unsupported stencil store semantics token")
    end
    function Stencil.StencilStoreElementwise:native_stencil_store_token() return "elementwise" end
    function Stencil.StencilStoreCopy:native_stencil_store_token() return "copy." .. self.semantics:native_kernel_copy_token() end
    function Stencil.StencilStoreScatter:native_stencil_store_token() return "scatter." .. self.conflicts:native_stencil_scatter_conflict_token() end
    function Stencil.StencilStorePartition:native_stencil_store_token() return "partition." .. self.semantics:native_kernel_partition_token() end

    function Stencil.StencilScatterConflictSemantics:native_stencil_scatter_conflict_token()
        internal_error("unsupported stencil scatter conflict token")
    end
    function Stencil.StencilScatterUniqueIndices:native_stencil_scatter_conflict_token() return "unique" end
    function Stencil.StencilScatterLastWriteWins:native_stencil_scatter_conflict_token() return "last_write" end
    function Stencil.StencilScatterConflictUndefined:native_stencil_scatter_conflict_token() return "undefined" end

    function Stencil.StencilScatterReduceConflictSemantics:native_stencil_scatter_reduce_conflict_token()
        internal_error("unsupported stencil scatter-reduce conflict token")
    end
    function Stencil.StencilScatterReduceSequential:native_stencil_scatter_reduce_conflict_token() return "sequential" end
    function Stencil.StencilScatterReduceUniqueIndices:native_stencil_scatter_reduce_conflict_token() return "unique" end
    function Stencil.StencilScatterReduceAtomic:native_stencil_scatter_reduce_conflict_token() return "atomic." .. self.ordering:native_atomic_order_token() end
    function Stencil.StencilScatterReducePrivatized:native_stencil_scatter_reduce_conflict_token() return "privatized" end

    function Stencil.StencilReducer:native_stencil_reducer_token()
        return self.reduction:native_kernel_reduction_token() .. "." .. self.result_ty:native_source_type_token()
    end

    function Stencil.StencilReductionSemantics:native_stencil_reduction_token()
        internal_error("unsupported stencil reduction semantics token")
    end
    function Stencil.StencilReduceFold:native_stencil_reduction_token() return "fold." .. self.reducer:native_stencil_reducer_token() end
    function Stencil.StencilReduceCount:native_stencil_reduction_token() return "count" end
    function Stencil.StencilReduceFind:native_stencil_reduction_token() return "find" end

    function Stencil.StencilReduceScope:native_stencil_reduce_scope_token()
        internal_error("unsupported stencil reduce scope token")
    end
    function Stencil.StencilReduceScopeDomain:native_stencil_reduce_scope_token() return "domain" end
    function Stencil.StencilReduceScopeAxes:native_stencil_reduce_scope_token() return "axes" .. tostring(#(self.axes or {})) end
    function Stencil.StencilReduceScopeWindow:native_stencil_reduce_scope_token() return "window" .. tostring(#(self.axes or {})) end

    function Native.NativeStencilSinkSourceShape:native_stencil_sink_token()
        internal_error("unsupported stencil sink source-shape token")
    end
    function Native.NativeStencilSinkStoreShape:native_stencil_sink_token() return "store." .. self.semantics:native_stencil_store_token() .. "." .. self.dst:native_stencil_access_token() end
    function Native.NativeStencilSinkReduceShape:native_stencil_sink_token() return "reduce." .. self.value:native_stencil_value_token() .. "." .. self.scope:native_stencil_reduce_scope_token() .. "." .. self.semantics:native_stencil_reduction_token() end
    function Native.NativeStencilSinkScanShape:native_stencil_sink_token() return "scan." .. self.mode:native_kernel_scan_token() .. "." .. self.reducer:native_kernel_reducer_token() .. "." .. self.value:native_stencil_value_token() end
    function Native.NativeStencilSinkScatterReduceShape:native_stencil_sink_token() return "scatter_reduce." .. self.conflicts:native_stencil_scatter_reduce_conflict_token() .. "." .. self.reducer:native_kernel_reducer_token() .. "." .. self.value:native_stencil_value_token() end

    function Stencil.StencilCompiler:native_stencil_compiler_token()
        internal_error("unsupported stencil compiler token")
    end
    function Stencil.StencilCompilerGcc:native_stencil_compiler_token() return "gcc" end
    function Stencil.StencilCompilerClang:native_stencil_compiler_token() return "clang" end
    function Stencil.StencilCompilerSystemC:native_stencil_compiler_token() return "systemc" end

    function Stencil.StencilOptLevel:native_stencil_opt_token()
        internal_error("unsupported stencil opt token")
    end
    function Stencil.StencilOptO0:native_stencil_opt_token() return "o0" end
    function Stencil.StencilOptO1:native_stencil_opt_token() return "o1" end
    function Stencil.StencilOptO2:native_stencil_opt_token() return "o2" end
    function Stencil.StencilOptO3:native_stencil_opt_token() return "o3" end
    function Stencil.StencilOptOs:native_stencil_opt_token() return "os" end
    function Stencil.StencilOptOz:native_stencil_opt_token() return "oz" end

    function Stencil.StencilMachineTarget:native_stencil_machine_token()
        internal_error("unsupported stencil machine target token")
    end
    function Stencil.StencilMachineNative:native_stencil_machine_token() return "native" end
    function Stencil.StencilMachineBaseline:native_stencil_machine_token() return "baseline" end
    function Stencil.StencilMachineNamed:native_stencil_machine_token() return "named." .. symbol_fragment(self.name) end

    function Stencil.StencilCompilerPolicy:native_stencil_compiler_policy_token()
        local flags = {}
        for _, flag in ipairs(self.flags or {}) do flags[#flags + 1] = symbol_fragment(flag) end
        return self.compiler:native_stencil_compiler_token() .. "." .. self.opt_level:native_stencil_opt_token() .. "." .. self.machine:native_stencil_machine_token() .. ".flags." .. table.concat(flags, "_")
    end

    function Stencil.StencilTripCountFact:native_stencil_trip_count_token()
        internal_error("unsupported stencil trip-count fact token")
    end
    function Stencil.StencilTripCountUnknown:native_stencil_trip_count_token() return "unknown" end
    function Stencil.StencilTripCountDynamic:native_stencil_trip_count_token() return "dynamic" end
    function Stencil.StencilTripCountMultipleOf:native_stencil_trip_count_token() return "multiple" .. tostring(self.factor) end
    function Stencil.StencilTripCountExact:native_stencil_trip_count_token() return "exact" .. tostring(self.count) end

    function Stencil.StencilVectorFeatureRequirement:native_stencil_vector_feature_token()
        internal_error("unsupported stencil vector feature token")
    end
    function Stencil.StencilVectorFeatureNative:native_stencil_vector_feature_token() return "native" end
    function Stencil.StencilVectorFeatureSSE2:native_stencil_vector_feature_token() return "sse2" end
    function Stencil.StencilVectorFeatureAVX2:native_stencil_vector_feature_token() return "avx2" end
    function Stencil.StencilVectorFeatureAVX512F:native_stencil_vector_feature_token() return "avx512f" end
    function Stencil.StencilVectorFeatureNamed:native_stencil_vector_feature_token() return "named." .. symbol_fragment(self.name) end

    function Stencil.StencilLanePolicy:native_stencil_lane_policy_token()
        internal_error("unsupported stencil lane policy token")
    end
    function Stencil.StencilLaneFromTarget:native_stencil_lane_policy_token() return "from_target" end
    function Stencil.StencilLaneNative:native_stencil_lane_policy_token() return "native" end
    function Stencil.StencilLaneFixed:native_stencil_lane_policy_token() return "fixed" .. tostring(self.lanes) end

    function Stencil.StencilVectorAlignmentPolicy:native_stencil_alignment_token()
        internal_error("unsupported stencil alignment token")
    end
    function Stencil.StencilVectorAlignmentUnknown:native_stencil_alignment_token() return "unknown" end
    function Stencil.StencilVectorUnaligned:native_stencil_alignment_token() return "unaligned" end
    function Stencil.StencilVectorAligned:native_stencil_alignment_token() return "aligned" .. tostring(self.bytes) end

    function Stencil.StencilVectorTailPolicy:native_stencil_tail_token()
        internal_error("unsupported stencil tail token")
    end
    function Stencil.StencilVectorScalarTail:native_stencil_tail_token() return "scalar_tail" end
    function Stencil.StencilVectorMaskTail:native_stencil_tail_token() return "mask_tail" end
    function Stencil.StencilVectorOverreadProvenSafe:native_stencil_tail_token() return "overread_safe" end

    function Stencil.StencilVectorReductionStrategy:native_stencil_vector_reduction_token()
        internal_error("unsupported stencil vector reduction token")
    end
    function Stencil.StencilVectorReductionTree:native_stencil_vector_reduction_token() return "tree" end
    function Stencil.StencilVectorReductionHorizontal:native_stencil_vector_reduction_token() return "horizontal" end
    function Stencil.StencilVectorReductionScalarFinish:native_stencil_vector_reduction_token() return "scalar_finish" end

    function Native.NativeStencilScheduleSourceShape:native_stencil_schedule_token()
        internal_error("unsupported stencil schedule source-shape token")
    end
    function Native.NativeStencilScheduleScalarShape:native_stencil_schedule_token() return "scalar." .. self.compiler:native_stencil_compiler_policy_token() end
    function Native.NativeStencilScheduleAutoVectorShape:native_stencil_schedule_token() return "autovector." .. self.trip_count:native_stencil_trip_count_token() end
    function Native.NativeStencilScheduleUnrolledShape:native_stencil_schedule_token() return "unrolled" .. tostring(self.factor) .. "." .. self.trip_count:native_stencil_trip_count_token() end
    function Native.NativeStencilScheduleVectorShape:native_stencil_schedule_token()
        return "vector." .. self.feature:native_stencil_vector_feature_token() .. "." .. self.lane_policy:native_stencil_lane_policy_token() .. "." .. self.required_alignment:native_stencil_alignment_token() .. "." .. self.tail:native_stencil_tail_token() .. "." .. self.reduction:native_stencil_vector_reduction_token() .. ".vu" .. tostring(self.vector_unroll) .. ".i" .. tostring(self.interleave)
    end

    local function stencil_family(input, name, role, axis)
        return Support.family(
            Support.stencil_family_id(name),
            role,
            { Support.axis_target(input.domain.target), axis },
            Support.protocol_void_none()
        )
    end

    local function stencil_next_signature(frame_scalar)
        local next_ordinal = Support.next_continuation_ordinal()
        local next_signature = Support.stencil_continuation_signature(next_ordinal, {})
        return Support.spill_all_stencil_signature(frame_scalar, {}, { next_signature }), next_ordinal, next_signature, Support.next_continuation_symbol()
    end

    local function append_stencil_manifest_source(out, input, id_tail_text, family, signature, extraction, entry, lines, holes, continuation_ordinals, extra_relocations)
        append_manifest_source(
            out,
            "stencil." .. id_tail_text,
            family,
            Native.NativeChunkStencilOp,
            signature,
            extraction,
            entry,
            lines,
            holes,
            continuation_ordinals or {},
            extra_relocations or {}
        )
    end

    local function stencil_family_for_producer(input, shape)
        local name = "producer." .. shape:native_stencil_producer_token()
        return name, stencil_family(input, name, Native.NativeRoleStencilProducer, Support.axis_stencil_producer(Native.NativeStencilProducerSourceShapeAxis(shape)))
    end

    local function stencil_family_for_access(input, shape)
        local name = "access." .. shape:native_stencil_access_token()
        return name, stencil_family(input, name, Native.NativeRoleStencilAccess, Support.axis_stencil_access(Native.NativeStencilAccessSourceShapeAxis(shape)))
    end

    local function stencil_family_for_point(input, shape)
        local name = "point." .. shape:native_stencil_point_token()
        return name, stencil_family(input, name, Native.NativeRoleStencilPoint, Support.axis_stencil_point(Native.NativeStencilPointSourceShapeAxis(shape)))
    end

    local function stencil_family_for_body(input, shape)
        local name = "body." .. shape:native_stencil_body_token()
        return name, stencil_family(input, name, Native.NativeRoleStencilBody, Support.axis_stencil_body(Native.NativeStencilBodySourceShapeAxis(shape)))
    end

    local function stencil_family_for_sink(input, shape)
        local name = "sink." .. shape:native_stencil_sink_token()
        return name, stencil_family(input, name, Native.NativeRoleStencilSink, Support.axis_stencil_sink(Native.NativeStencilSinkSourceShapeAxis(shape)))
    end

    local function stencil_family_for_schedule(input, shape)
        local name = "schedule." .. shape:native_stencil_schedule_token()
        return name, stencil_family(input, name, Native.NativeRoleStencilSchedule, Support.axis_stencil_schedule(Native.NativeStencilScheduleSourceShapeAxis(shape)))
    end

    function Native.NativeStencilProducerSourceShape:append_native_template_sources(_out, _input)
        internal_error("unsupported StencilProducer source shape")
    end

    local function append_stencil_producer_source(out, input, shape, emit_loop_lines)
        local name, family = stencil_family_for_producer(input, shape)
        local token = shape:native_stencil_producer_token()
        local id_base = "native.hole.stencil." .. name
        local holes = {}
        local then_ordinal = Support.then_continuation_ordinal()
        local else_ordinal = Support.else_continuation_ordinal()
        local then_signature = Support.stencil_continuation_signature(then_ordinal, {})
        local else_signature = Support.stencil_continuation_signature(else_ordinal, {})
        local then_symbol = Support.then_continuation_symbol()
        local else_symbol = Support.else_continuation_symbol()
        local signature = Support.spill_all_stencil_signature(shape.index and shape.index:native_stencil_family_scalar(input.domain.target) or Support.scalar_index(input.domain.target.pointer_bits), {}, { then_signature, else_signature })
        local entry = "lalin_native_stencil_" .. symbol_fragment(name)
        local lines = c_prelude()
        local body = {}
        body[#body + 1] = continuation_extern(then_symbol, then_signature)
        body[#body + 1] = continuation_extern(else_symbol, else_signature)
        body[#body + 1] = "void " .. entry .. "(uint8_t *frame) {"
        emit_loop_lines(body, holes, id_base, then_symbol, else_symbol)
        body[#body + 1] = "}"
        append_stencil_hole_externs(lines, holes)
        for _, line in ipairs(body) do lines[#lines + 1] = line end
        append_stencil_manifest_source(out, input, name, family, signature, Native.NativeExtractContinuationFragment({ then_symbol, else_symbol }), entry, lines, holes, { then_ordinal, else_ordinal })
    end

    function Native.NativeStencilProducerRange1DShape:append_native_template_sources(out, input)
        append_stencil_producer_source(out, input, self, function(lines, holes, id_base, then_symbol, else_symbol)
            local counter_hole = add_hole(holes, frame_offset_hole(id_base .. ".counter"))
            local stop_hole = add_hole(holes, frame_offset_hole(id_base .. ".stop"))
            local scalar = self.index:native_stencil_family_scalar(input.domain.target)
            local c_type = scalar:native_c_scalar_type()
            lines[#lines + 1] = "    " .. c_type .. " counter = " .. frame_load(c_type, hole_address_expr(counter_hole)) .. ";"
            lines[#lines + 1] = "    " .. c_type .. " stop = " .. frame_load(c_type, hole_address_expr(stop_hole)) .. ";"
            local cmp = (self.order == Stencil.StencilProducerBackward) and "counter > stop" or "counter < stop"
            local step = tonumber(self.step) or 1
            if self.order == Stencil.StencilProducerBackward and step > 0 then step = -step end
            lines[#lines + 1] = "    if (" .. cmp .. ") {"
            lines[#lines + 1] = frame_store(c_type, hole_address_expr(counter_hole), "(" .. c_type .. ")(counter + (" .. tostring(step) .. "))")
            lines[#lines + 1] = "        " .. then_symbol.name .. "(frame);"
            lines[#lines + 1] = "    } else {"
            lines[#lines + 1] = "        " .. else_symbol.name .. "(frame);"
            lines[#lines + 1] = "    }"
        end)
    end

    local function append_ranked_producer_lines(shape, input, lines, holes, id_base, then_symbol, else_symbol)
        local rank = shape.rank or 0
        local scalar = Support.scalar_index(input.domain.target.pointer_bits)
        local c_type = scalar:native_c_scalar_type()
        local active = {}
        for i = 0, rank - 1 do
            local counter_hole = add_hole(holes, frame_offset_hole(id_base .. ".axis" .. tostring(i) .. ".counter"))
            local stop_hole = add_hole(holes, frame_offset_hole(id_base .. ".axis" .. tostring(i) .. ".stop"))
            lines[#lines + 1] = "    " .. c_type .. " axis" .. tostring(i) .. " = " .. frame_load(c_type, hole_address_expr(counter_hole)) .. ";"
            lines[#lines + 1] = "    " .. c_type .. " stop" .. tostring(i) .. " = " .. frame_load(c_type, hole_address_expr(stop_hole)) .. ";"
            active[#active + 1] = "axis" .. tostring(i) .. " < stop" .. tostring(i)
            if i == 0 then lines[#lines + 1] = frame_store(c_type, hole_address_expr(counter_hole), "(" .. c_type .. ")(axis0 + 1)") end
        end
        local condition = #active == 0 and "0" or table.concat(active, " && ")
        lines[#lines + 1] = "    if (" .. condition .. ") { " .. then_symbol.name .. "(frame); } else { " .. else_symbol.name .. "(frame); }"
    end

    function Native.NativeStencilProducerRangeNDShape:append_native_template_sources(out, input)
        append_stencil_producer_source(out, input, self, function(lines, holes, id_base, then_symbol, else_symbol)
            append_ranked_producer_lines(self, input, lines, holes, id_base, then_symbol, else_symbol)
        end)
    end

    function Native.NativeStencilProducerWindowNDShape:append_native_template_sources(out, input)
        append_stencil_producer_source(out, input, self, function(lines, holes, id_base, then_symbol, else_symbol)
            local window_hole = add_hole(holes, imm32_hole(id_base .. ".window_count"))
            lines[#lines + 1] = "    (void)(uintptr_t)&" .. window_hole.symbol .. ";"
            append_ranked_producer_lines(self, input, lines, holes, id_base, then_symbol, else_symbol)
        end)
    end

    function Native.NativeStencilProducerTiledNDShape:append_native_template_sources(out, input)
        append_stencil_producer_source(out, input, self, function(lines, holes, id_base, then_symbol, else_symbol)
            local tile_hole = add_hole(holes, imm32_hole(id_base .. ".tile_count"))
            lines[#lines + 1] = "    (void)(uintptr_t)&" .. tile_hole.symbol .. ";"
            append_ranked_producer_lines(self, input, lines, holes, id_base, then_symbol, else_symbol)
        end)
    end

    function Native.NativeStencilAccessSourceShape:native_stencil_address_expr(_input, _id_base, _holes, _lines)
        internal_error("unsupported stencil access address source shape")
    end

    function Native.NativeStencilAccessScalarShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local base = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        return frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(base))
    end

    function Native.NativeStencilAccessContiguousShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local base = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        local index = add_hole(holes, frame_offset_hole(id_base .. ".index"))
        local elem = add_hole(holes, imm32_hole(id_base .. ".elem_size"))
        return "((uintptr_t)" .. frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(base)) .. " + (uintptr_t)" .. frame_load("intptr_t", hole_address_expr(index)) .. " * (uintptr_t)" .. hole_address_expr(elem) .. " * (uintptr_t)" .. tostring(self.stride) .. ")"
    end

    function Native.NativeStencilAccessIndexedShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local base = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        local index = add_hole(holes, frame_offset_hole(id_base .. ".index"))
        local elem = add_hole(holes, imm32_hole(id_base .. ".elem_size"))
        return "((uintptr_t)" .. frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(base)) .. " + (uintptr_t)" .. frame_load("intptr_t", hole_address_expr(index)) .. " * (uintptr_t)" .. hole_address_expr(elem) .. " * (uintptr_t)" .. tostring(self.stride) .. ")"
    end

    function Native.NativeStencilAccessAffine1DShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local base = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        local index = add_hole(holes, frame_offset_hole(id_base .. ".index"))
        local offset = add_hole(holes, imm32_hole(id_base .. ".offset"))
        return "((uintptr_t)" .. frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(base)) .. " + (uintptr_t)(((intptr_t)" .. frame_load("intptr_t", hole_address_expr(index)) .. " * (intptr_t)" .. tostring(self.scale) .. ") + (intptr_t)" .. hole_address_expr(offset) .. "))"
    end

    function Native.NativeStencilAccessAffineNDShape:native_stencil_address_expr(input, id_base, holes, lines)
        local base = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        local acc = "stencil_affine_" .. symbol_fragment(id_base)
        lines[#lines + 1] = "    intptr_t " .. acc .. " = 0;"
        for i = 0, self.term_count - 1 do
            local term = add_hole(holes, frame_offset_hole(id_base .. ".term" .. tostring(i)))
            local coeff = add_hole(holes, imm32_hole(id_base .. ".coeff" .. tostring(i)))
            lines[#lines + 1] = "    " .. acc .. " += (intptr_t)" .. frame_load("intptr_t", hole_address_expr(term)) .. " * (intptr_t)" .. hole_address_expr(coeff) .. ";"
        end
        return "((uintptr_t)" .. frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(base)) .. " + (uintptr_t)" .. acc .. ")"
    end

    function Native.NativeStencilAccessFieldProjectionShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local base = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        local field = add_hole(holes, imm32_hole(id_base .. ".field_offset"))
        return "((uintptr_t)" .. frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(base)) .. " + (uintptr_t)" .. hole_address_expr(field) .. ")"
    end

    function Native.NativeStencilAccessSoAComponentShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local base = add_hole(holes, frame_offset_hole(id_base .. ".base"))
        local component = add_hole(holes, imm32_hole(id_base .. ".component_offset"))
        return "((uintptr_t)" .. frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(base)) .. " + (uintptr_t)" .. hole_address_expr(component) .. ")"
    end

    function Native.NativeStencilAccessSliceDescriptorShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local descriptor = add_hole(holes, frame_offset_hole(id_base .. ".descriptor"))
        local index = add_hole(holes, frame_offset_hole(id_base .. ".index"))
        local elem = add_hole(holes, imm32_hole(id_base .. ".elem_size"))
        local base = frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(descriptor))
        return "((uintptr_t)" .. base .. " + (uintptr_t)" .. frame_load("intptr_t", hole_address_expr(index)) .. " * (uintptr_t)" .. hole_address_expr(elem) .. ")"
    end

    function Native.NativeStencilAccessByteSpanDescriptorShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local descriptor = add_hole(holes, frame_offset_hole(id_base .. ".descriptor"))
        local offset = add_hole(holes, frame_offset_hole(id_base .. ".byte_offset"))
        local base = frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(descriptor))
        return "((uintptr_t)" .. base .. " + (uintptr_t)" .. frame_load("intptr_t", hole_address_expr(offset)) .. ")"
    end

    function Native.NativeStencilAccessViewDescriptorShape:native_stencil_address_expr(input, id_base, holes, _lines)
        local descriptor = add_hole(holes, frame_offset_hole(id_base .. ".descriptor"))
        local index = add_hole(holes, frame_offset_hole(id_base .. ".index"))
        local stride_hole = self.has_const_stride and add_hole(holes, imm32_hole(id_base .. ".stride_const")) or add_hole(holes, frame_offset_hole(id_base .. ".stride"))
        local stride = self.has_const_stride and hole_address_expr(stride_hole) or frame_load("intptr_t", hole_address_expr(stride_hole))
        local base = frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(descriptor))
        return "((uintptr_t)" .. base .. " + (uintptr_t)" .. frame_load("intptr_t", hole_address_expr(index)) .. " * (uintptr_t)(" .. stride .. "))"
    end

    function Native.NativeStencilAccessSourceShape:append_native_template_sources(out, input)
        local name, family = stencil_family_for_access(input, self)
        local holes = {}
        local id_base = "native.hole.stencil." .. name
        local dst = add_hole(holes, frame_offset_hole(id_base .. ".dst"))
        local signature, next_ordinal, next_signature, next_symbol = stencil_next_signature(Support.scalar_pointer(input.domain.target.pointer_bits))
        local entry = "lalin_native_stencil_" .. symbol_fragment(name)
        local lines = c_prelude()
        local body = {}
        body[#body + 1] = continuation_extern(next_symbol, next_signature)
        body[#body + 1] = "void " .. entry .. "(uint8_t *frame) {"
        local address = self:native_stencil_address_expr(input, id_base, holes, body)
        body[#body + 1] = frame_store(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(dst), "(" .. Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type() .. ")(uintptr_t)(" .. address .. ")")
        body[#body + 1] = "    " .. next_symbol.name .. "(frame);"
        body[#body + 1] = "}"
        append_stencil_hole_externs(lines, holes)
        for _, line in ipairs(body) do lines[#lines + 1] = line end
        append_stencil_manifest_source(out, input, name, family, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    function Native.NativeStencilPointSourceShape:native_stencil_inline_expr(_input, _id_base, _holes, _lines)
        internal_error("unsupported stencil point inline expression")
    end

    function Native.NativeStencilPointInputShape:native_stencil_inline_expr(input, id_base, holes, _lines)
        return self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".src")))
    end

    function Native.NativeStencilPointWindowInputShape:native_stencil_inline_expr(input, id_base, holes, _lines)
        local window = add_hole(holes, imm32_hole(id_base .. ".window_offset_count"))
        local src = add_hole(holes, frame_offset_hole(id_base .. ".src"))
        return "(" .. self.value:native_stencil_load_expr(input.domain.target, src) .. " + (" .. self.value:native_stencil_load_expr(input.domain.target, src) .. " * 0) + (" .. hole_address_expr(window) .. " * 0))"
    end

    function Native.NativeStencilPointConstShape:native_stencil_inline_expr(input, id_base, holes, _lines)
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes stencil const expressions require byte source shape") end
        local hole = add_hole(holes, asdl.isa(scalar, Native.NativeScalarPointer) and ptr64_hole(id_base .. ".const") or scalar_immediate_hole(id_base .. ".const", scalar))
        return "(" .. scalar:native_c_scalar_type() .. ")" .. hole_address_expr(hole)
    end

    function Native.NativeStencilPointUnaryShape:native_stencil_inline_expr(input, id_base, holes, _lines)
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes stencil unary expressions are not scalar source shapes") end
        local src = self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".src")))
        return self.op:native_stencil_unary_expr(scalar, src)
    end

    function Native.NativeStencilPointBinaryShape:native_stencil_inline_expr(input, id_base, holes, _lines)
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes stencil binary expressions are not scalar source shapes") end
        local lhs = self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".lhs")))
        local rhs = self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".rhs")))
        return self.op:native_stencil_binary_expr(scalar, lhs, rhs)
    end

    function Native.NativeStencilPointCastShape:native_stencil_inline_expr(input, id_base, holes, lines)
        local from_scalar = self.from:native_stencil_c_scalar(input.domain.target)
        local to_scalar = self.to:native_stencil_c_scalar(input.domain.target)
        if from_scalar == nil or to_scalar == nil then internal_error("bytes stencil casts are not scalar source shapes") end
        local src = self.from:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".src")))
        local var = "stencil_cast_" .. symbol_fragment(id_base)
        self.op:append_native_cast_c_lines(lines, from_scalar, to_scalar, src, var)
        return var
    end

    function Native.NativeStencilPointPredicateShape:native_stencil_inline_expr(input, id_base, holes, lines)
        local value = self.value:native_stencil_c_scalar(input.domain.target)
        if value == nil then internal_error("bytes stencil predicate results are not scalar source shapes") end
        local pred = self.pred:native_kernel_inline_predicate(input, id_base .. ".pred", holes, lines)
        return "(" .. value:native_c_scalar_type() .. ")((" .. pred .. ") != 0)"
    end

    function Native.NativeStencilPointCompareShape:native_stencil_inline_expr(input, id_base, holes, _lines)
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes stencil compare expressions are not scalar source shapes") end
        local lhs = self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".lhs")))
        local rhs = self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".rhs")))
        return "(uint8_t)(" .. self.cmp:native_c_compare_expr(scalar, lhs, rhs) .. ")"
    end

    function Native.NativeStencilPointSelectShape:native_stencil_inline_expr(input, id_base, holes, lines)
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("bytes stencil select expressions are not scalar source shapes") end
        local pred = self.pred:native_kernel_inline_predicate(input, id_base .. ".pred", holes, lines)
        local lhs = self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".true")))
        local rhs = self.value:native_stencil_load_expr(input.domain.target, add_hole(holes, frame_offset_hole(id_base .. ".false")))
        return "((" .. pred .. ") ? (" .. lhs .. ") : (" .. rhs .. "))"
    end

    function Native.NativeStencilPointSourceShape:append_native_template_sources(out, input)
        local name, family = stencil_family_for_point(input, self)
        local token = self:native_stencil_point_token()
        local id_base = "native.hole.stencil." .. name
        local holes = {}
        local result = self:native_stencil_result_value_shape()
        local dst = add_hole(holes, frame_offset_hole(id_base .. ".dst"))
        local signature, next_ordinal, next_signature, next_symbol = stencil_next_signature(result:native_stencil_family_scalar(input.domain.target))
        local entry = "lalin_native_stencil_" .. symbol_fragment(name)
        local body = {}
        body[#body + 1] = continuation_extern(next_symbol, next_signature)
        body[#body + 1] = "void " .. entry .. "(uint8_t *frame) {"
        if asdl.isa(result, Native.NativeStencilValueBytesShape) then
            body[#body + 1] = "    __builtin_memset(frame + " .. hole_address_expr(dst) .. ", 0, " .. tostring(result.size) .. ");"
        else
            local expr = self:native_stencil_inline_expr(input, id_base, holes, body)
            body[#body + 1] = result:native_stencil_store_line(input.domain.target, dst, expr)
        end
        body[#body + 1] = "    " .. next_symbol.name .. "(frame);"
        body[#body + 1] = "}"
        local lines = c_prelude()
        append_stencil_hole_externs(lines, holes)
        for _, line in ipairs(body) do lines[#lines + 1] = line end
        append_stencil_manifest_source(out, input, "point." .. token, family, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    function Native.NativeStencilBodySourceShape:append_native_template_sources(out, input)
        local name, family = stencil_family_for_body(input, self)
        local signature, next_ordinal, next_signature, next_symbol = stencil_next_signature(Support.scalar_bool8())
        local entry = "lalin_native_stencil_" .. symbol_fragment(name)
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    __asm__ volatile(\"\" ::: \"memory\");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_stencil_manifest_source(out, input, name, family, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    local function stencil_store_value_to_address(lines, input, value_shape, address_expr, value_expr)
        local scalar = value_shape:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then
            lines[#lines + 1] = "    __builtin_memcpy((void *)(uintptr_t)(" .. address_expr .. "), (const void *)(frame + (uintptr_t)(" .. value_expr .. ")), " .. tostring(value_shape:native_stencil_value_size(input.domain.target)) .. ");"
        else
            lines[#lines + 1] = "    *(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)(" .. address_expr .. ") = (" .. scalar:native_c_scalar_type() .. ")(" .. value_expr .. ");"
        end
    end

    function Native.NativeStencilSinkSourceShape:native_stencil_emit_sink(_input, _id_base, _holes, _lines)
        internal_error("unsupported stencil sink source-shape emission")
    end

    function Native.NativeStencilSinkStoreShape:native_stencil_emit_sink(input, id_base, holes, lines)
        local address = self.dst:native_stencil_address_expr(input, id_base .. ".dst", holes, lines)
        local value_hole = add_hole(holes, frame_offset_hole(id_base .. ".value"))
        local scalar = self.dst.value:native_stencil_c_scalar(input.domain.target)
        local value_expr = scalar and self.dst.value:native_stencil_load_expr(input.domain.target, value_hole) or hole_address_expr(value_hole)
        stencil_store_value_to_address(lines, input, self.dst.value, address, value_expr)
    end

    local function reducer_expr_for_stencil(reducer, input, acc, value)
        local scalar = reducer.value:native_kernel_c_scalar(input.domain.target)
        if scalar == nil then internal_error("byte stencil reducers need byte-aware source shapes") end
        return reducer.op:native_kernel_reduce_expr(scalar, acc, value)
    end

    function Native.NativeStencilSinkReduceShape:native_stencil_emit_sink(input, id_base, holes, lines)
        local state = add_hole(holes, frame_offset_hole(id_base .. ".state"))
        local value_hole = add_hole(holes, frame_offset_hole(id_base .. ".value"))
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("byte stencil reductions need byte-aware source shapes") end
        local old = frame_load(scalar:native_c_scalar_type(), hole_address_expr(state))
        local value = frame_load(scalar:native_c_scalar_type(), hole_address_expr(value_hole))
        if asdl.isa(self.semantics, Stencil.StencilReduceFold) then
            local reducer = Native.NativeKernelReducerSourceShape(self.semantics.reducer.reduction, Native.NativeKernelValueScalarShape(scalar))
            lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(state), reducer_expr_for_stencil(reducer, input, old, value))
        elseif asdl.isa(self.semantics, Stencil.StencilReduceCount) then
            lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(state), "(" .. scalar:native_c_scalar_type() .. ")(" .. old .. " + ((" .. value .. ") != 0))")
        else
            lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(state), "(" .. value .. ")")
        end
    end

    function Native.NativeStencilSinkScanShape:native_stencil_emit_sink(input, id_base, holes, lines)
        local state = add_hole(holes, frame_offset_hole(id_base .. ".state"))
        local dst = add_hole(holes, frame_offset_hole(id_base .. ".dst"))
        local value_hole = add_hole(holes, frame_offset_hole(id_base .. ".value"))
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("byte stencil scans need byte-aware source shapes") end
        local old = frame_load(scalar:native_c_scalar_type(), hole_address_expr(state))
        local value = frame_load(scalar:native_c_scalar_type(), hole_address_expr(value_hole))
        local reduced = self.reducer.op:native_kernel_reduce_expr(scalar, old, value)
        if self.mode == Stencil.StencilScanExclusive then
            lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(dst), old)
            lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(state), reduced)
        else
            lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(state), reduced)
            lines[#lines + 1] = frame_store(scalar:native_c_scalar_type(), hole_address_expr(dst), reduced)
        end
    end

    function Native.NativeStencilSinkScatterReduceShape:native_stencil_emit_sink(input, id_base, holes, lines)
        local address = add_hole(holes, frame_offset_hole(id_base .. ".address"))
        local value_hole = add_hole(holes, frame_offset_hole(id_base .. ".value"))
        local scalar = self.value:native_stencil_c_scalar(input.domain.target)
        if scalar == nil then internal_error("byte stencil scatter reductions need byte-aware source shapes") end
        local ptr = frame_load(Support.scalar_pointer(input.domain.target.pointer_bits):native_c_scalar_type(), hole_address_expr(address))
        local value = frame_load(scalar:native_c_scalar_type(), hole_address_expr(value_hole))
        local old = "*(" .. scalar:native_c_scalar_type() .. " *)(void *)(uintptr_t)(" .. ptr .. ")"
        lines[#lines + 1] = "    " .. old .. " = " .. self.reducer.op:native_kernel_reduce_expr(scalar, old, value) .. ";"
    end

    function Native.NativeStencilSinkSourceShape:append_native_template_sources(out, input)
        local name, family = stencil_family_for_sink(input, self)
        local id_base = "native.hole.stencil." .. name
        local holes = {}
        local signature, next_ordinal, next_signature, next_symbol = stencil_next_signature(Support.scalar_bool8())
        local entry = "lalin_native_stencil_" .. symbol_fragment(name)
        local body = {}
        body[#body + 1] = continuation_extern(next_symbol, next_signature)
        body[#body + 1] = "void " .. entry .. "(uint8_t *frame) {"
        self:native_stencil_emit_sink(input, id_base, holes, body)
        body[#body + 1] = "    " .. next_symbol.name .. "(frame);"
        body[#body + 1] = "}"
        local lines = c_prelude()
        append_stencil_hole_externs(lines, holes)
        for _, line in ipairs(body) do lines[#lines + 1] = line end
        append_stencil_manifest_source(out, input, name, family, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { next_ordinal })
    end

    function Native.NativeStencilScheduleSourceShape:append_native_template_sources(out, input)
        local name, family = stencil_family_for_schedule(input, self)
        local signature, next_ordinal, next_signature, next_symbol = stencil_next_signature(Support.scalar_bool8())
        local entry = "lalin_native_stencil_" .. symbol_fragment(name)
        local lines = c_prelude()
        lines[#lines + 1] = continuation_extern(next_symbol, next_signature)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    __asm__ volatile(\"\" ::: \"memory\");"
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_stencil_manifest_source(out, input, name, family, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, {}, { next_ordinal })
    end

    local function append_domain_stencil_sources(out, input)
        local sources = input.domain.stencil_sources or Support.empty_stencil_source_support()
        for _, shape in ipairs(sources.producers or {}) do shape:append_native_template_sources(out, input) end
        for _, shape in ipairs(sources.accesses or {}) do shape:append_native_template_sources(out, input) end
        for _, shape in ipairs(sources.points or {}) do shape:append_native_template_sources(out, input) end
        for _, shape in ipairs(sources.bodies or {}) do shape:append_native_template_sources(out, input) end
        for _, shape in ipairs(sources.sinks or {}) do shape:append_native_template_sources(out, input) end
        for _, shape in ipairs(sources.schedules or {}) do shape:append_native_template_sources(out, input) end
    end

    function Native.NativeCodeInstBinaryAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local token = scalar:native_scalar_token()
        local name = self.op:native_binary_family_name()
        local holes = {
            frame_offset_hole("native.hole.code.inst.binary." .. token .. "." .. name .. ".lhs"),
            frame_offset_hole("native.hole.code.inst.binary." .. token .. "." .. name .. ".rhs"),
            frame_offset_hole("native.hole.code.inst.binary." .. token .. "." .. name .. ".dst"),
        }
        local lhs = frame_load(c_type, hole_address_expr(holes[1]))
        local rhs = frame_load(c_type, hole_address_expr(holes[2]))
        local expr = self.op:native_integer_c_expr(scalar, lhs, rhs)
        local family = Support.code_inst_frame_family("binary." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_binary_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " lhs = " .. lhs .. ";"
        lines[#lines + 1] = "    " .. c_type .. " rhs = " .. rhs .. ";"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(holes[3]), expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst.binary." .. token .. "." .. name,
            family,
            Native.NativeChunkBinaryOp,
            scalar_frame_signature(scalar, 3, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
    end

    function Native.NativeCodeInstFloatBinaryAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local token = scalar:native_scalar_token()
        local name = self.op:native_binary_family_name()
        local holes = {
            frame_offset_hole("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".lhs"),
            frame_offset_hole("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".rhs"),
            frame_offset_hole("native.hole.code.inst.float_binary." .. token .. "." .. name .. ".dst"),
        }
        local lhs = frame_load(c_type, hole_address_expr(holes[1]))
        local rhs = frame_load(c_type, hole_address_expr(holes[2]))
        local expr = self.op:native_float_c_expr(scalar, lhs, rhs)
        local family = Support.code_inst_frame_family("float_binary." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_float_binary_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " lhs = " .. lhs .. ";"
        lines[#lines + 1] = "    " .. c_type .. " rhs = " .. rhs .. ";"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(holes[3]), expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst.float_binary." .. token .. "." .. name,
            family,
            Native.NativeChunkBinaryOp,
            scalar_frame_signature(scalar, 3, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
    end

    function Native.NativeCodeInstUnaryAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local token = scalar:native_scalar_token()
        local name = self.op:native_unary_family_name()
        local holes = {
            frame_offset_hole("native.hole.code.inst.unary." .. token .. "." .. name .. ".src"),
            frame_offset_hole("native.hole.code.inst.unary." .. token .. "." .. name .. ".dst"),
        }
        local src = frame_load(c_type, hole_address_expr(holes[1]))
        local expr = self.op:native_integer_c_expr(scalar, src)
        local result_type = name == "not" and "uint8_t" or c_type
        local result_scalar = name == "not" and Support.scalar_bool8() or scalar
        local family = Support.code_inst_frame_family("unary." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_unary_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " src = " .. src .. ";"
        lines[#lines + 1] = frame_store(result_type, hole_address_expr(holes[2]), expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst.unary." .. token .. "." .. name,
            family,
            Native.NativeChunkUnaryOp,
            scalar_frame_signature(scalar, 2, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
        return result_scalar
    end

    function Native.NativeCodeInstCompareAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local token = scalar:native_scalar_token()
        local name = self.cmp:native_compare_family_name()
        local holes = {
            frame_offset_hole("native.hole.code.inst.compare." .. token .. "." .. name .. ".lhs"),
            frame_offset_hole("native.hole.code.inst.compare." .. token .. "." .. name .. ".rhs"),
            frame_offset_hole("native.hole.code.inst.compare." .. token .. "." .. name .. ".dst"),
        }
        local lhs = frame_load(c_type, hole_address_expr(holes[1]))
        local rhs = frame_load(c_type, hole_address_expr(holes[2]))
        local expr = self.cmp:native_c_compare_expr(scalar, lhs, rhs)
        local family = Support.code_inst_frame_family("compare." .. token .. "." .. name, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_compare_" .. symbol_fragment(token) .. "_" .. name
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " lhs = " .. lhs .. ";"
        lines[#lines + 1] = "    " .. c_type .. " rhs = " .. rhs .. ";"
        lines[#lines + 1] = frame_store("uint8_t", hole_address_expr(holes[3]), expr)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst.compare." .. token .. "." .. name,
            family,
            Native.NativeChunkCompareOp,
            scalar_frame_signature(scalar, 3, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
    end

    function Native.NativeCodeInstAliasAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local c_type = scalar:native_c_scalar_type()
        local token = scalar:native_scalar_token()
        local holes = {
            frame_offset_hole("native.hole.code.inst.alias." .. token .. ".src"),
            frame_offset_hole("native.hole.code.inst.alias." .. token .. ".dst"),
        }
        local family = Support.code_inst_frame_family("alias." .. token, input.domain.target, scalar, self)
        local entry = "lalin_native_code_inst_alias_" .. symbol_fragment(token)
        local next_symbol = Support.next_continuation_symbol()
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = "    " .. c_type .. " src = " .. frame_load(c_type, hole_address_expr(holes[1])) .. ";"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(holes[2]), "src")
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.inst.alias." .. token,
            family,
            Native.NativeChunkEdgeCopy,
            scalar_frame_signature(scalar, 2, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
    end

    function Core.LitInt:native_patch_coordinate_for_scalar(scalar)
        local value = tonumber(self.raw)
        if scalar.bits and scalar.bits > 32 then return Native.NativePatchImmediateI64(value) end
        return Native.NativePatchImmediateI32(value)
    end

    function Core.LitBool:native_patch_coordinate_for_scalar(_scalar)
        return Native.NativePatchImmediateI32(self.value and 1 or 0)
    end

    function Native.NativeCodeConstLiteralAxis:append_native_template_sources(out, input)
        local scalar = input.support.scalar
        local token = scalar:native_scalar_token()
        local c_type = scalar:native_c_scalar_type()
        local family = Support.code_const_frame_family("literal." .. token, input.domain.target, scalar, self)
        local entry = "lalin_native_code_const_literal_" .. symbol_fragment(token)
        local next_symbol = Support.next_continuation_symbol()
        local hole = (scalar.bits and scalar.bits > 32)
            and imm64_hole("native.hole.code.const.literal." .. token .. ".imm64")
            or imm32_hole("native.hole.code.const.literal." .. token .. ".imm32")
        local holes = {
            frame_offset_hole("native.hole.code.const.literal." .. token .. ".dst"),
            hole,
        }
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(next_symbol)
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        lines[#lines + 1] = frame_store(c_type, hole_address_expr(holes[1]), "(" .. c_type .. ")" .. hole_address_expr(hole))
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(
            out,
            "code.const.literal." .. token,
            family,
            Native.NativeChunkConstantLoad,
            scalar_frame_signature(scalar, 2, { Support.next_continuation_ordinal() }),
            Native.NativeExtractContinuationFragment({ next_symbol }),
            entry,
            lines,
            holes,
            { Support.next_continuation_ordinal() }
        )
    end

    local function append_integer_sources(out, input)
        local scalar = input.support.scalar
        local ty = input.support.code_type
        append_frame_entry_source(out, input, scalar)
        append_scalar_copy_sources(out, input, scalar)
        append_entry_source(out, input, scalar, scalar)
        append_entry_source(out, input, scalar, Support.scalar_bool8())
        for _, op in ipairs({
            Core.BinAdd, Core.BinSub, Core.BinMul,
            Core.BinBitAnd, Core.BinBitOr, Core.BinBitXor,
            Core.BinShl, Core.BinLShr, Core.BinAShr,
        }) do
            Native.NativeCodeInstBinaryAxis(op, ty, int_wrap_semantics()):append_native_template_sources(out, input)
        end
        for _, op in ipairs({ Core.UnaryNeg, Core.UnaryBitNot }) do
            Native.NativeCodeInstUnaryAxis(op, ty):append_native_template_sources(out, input)
        end
        for _, cmp in ipairs({ Core.CmpEq, Core.CmpNe, Core.CmpLt, Core.CmpLe, Core.CmpGt, Core.CmpGe }) do
            Native.NativeCodeInstCompareAxis(cmp, ty):append_native_template_sources(out, input)
        end
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        if not scalar.bits or scalar.bits >= 32 then
            Native.NativeCodeConstLiteralAxis(ty):append_native_template_sources(out, input)
        end
        append_terminal_source(out, input, scalar)
        append_result_copy_source(out, input, Native.NativeCodeResultScalarShape(scalar))
    end

    function Native.NativeScalarBool8:append_native_template_sources(out, input)
        local ty = input.support.code_type
        append_frame_entry_source(out, input, self)
        append_scalar_copy_sources(out, input, self)
        append_entry_source(out, input, self, self)
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        Native.NativeCodeInstUnaryAxis(Core.UnaryNot, ty):append_native_template_sources(out, input)
        Native.NativeCodeInstCompareAxis(Core.CmpEq, ty):append_native_template_sources(out, input)
        Native.NativeCodeInstCompareAxis(Core.CmpNe, ty):append_native_template_sources(out, input)
        append_terminal_source(out, input, self)
        append_result_copy_source(out, input, Native.NativeCodeResultScalarShape(self))
    end

    function Native.NativeScalarInt:append_native_template_sources(out, input)
        append_integer_sources(out, input)
    end

    function Native.NativeScalarIndex:append_native_template_sources(out, input)
        append_integer_sources(out, input)
    end

    function Native.NativeScalarPointer:append_native_template_sources(out, input)
        local ty = input.support.code_type
        append_frame_entry_source(out, input, self)
        append_scalar_copy_sources(out, input, self)
        append_entry_source(out, input, self, self)
        append_entry_source(out, input, self, Support.scalar_bool8())
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        Native.NativeCodeConstLiteralAxis(ty):append_native_template_sources(out, input)
        append_terminal_source_for_shape(out, input, Native.NativeCodeResultPointerShape(self))
        append_result_copy_source(out, input, Native.NativeCodeResultPointerShape(self))
        Native.NativeCodeInstCompareAxis(Core.CmpEq, ty):append_native_template_sources(out, input)
        Native.NativeCodeInstCompareAxis(Core.CmpNe, ty):append_native_template_sources(out, input)
    end

    function Native.NativeScalarFloat:append_native_template_sources(out, input)
        local ty = input.support.code_type
        local scalar = input.support.scalar
        append_frame_entry_source(out, input, scalar)
        append_scalar_copy_sources(out, input, scalar)
        append_entry_source(out, input, scalar, scalar)
        for _, op in ipairs({ Core.BinAdd, Core.BinSub, Core.BinMul, Core.BinDiv }) do
            Native.NativeCodeInstFloatBinaryAxis(op, ty, float_mode()):append_native_template_sources(out, input)
        end
        Native.NativeCodeInstAliasAxis(ty):append_native_template_sources(out, input)
        append_terminal_source(out, input, scalar)
        append_result_copy_source(out, input, Native.NativeCodeResultScalarShape(scalar))
    end

    local function build_sources_for_domain(domain)
        require_x64_sysv_target(domain.target)
        local input = Native.NativeTemplateSourceBuildInput(domain)
        local out = {}
        for _, scalar_support in ipairs(domain.scalars) do
            scalar_support:append_native_template_sources(out, input)
        end
        for _, scalar_support in ipairs(domain.scalars) do
            append_cast_sources_for_scalar(out, input, scalar_support.scalar)
            append_select_sources_for_scalar(out, input, scalar_support.scalar)
        end
        append_domain_constant_pool_sources(out, input)
        append_domain_address_memory_descriptor_aggregate_sources(out, input)
        append_domain_atomic_sources(out, input)
        append_domain_control_sources(out, input)
        append_domain_abi_and_call_sources(out, input)
        append_domain_kernel_sources(out, input)
        append_domain_stencil_sources(out, input)
        return out
    end

    local function manifest_groups_from_sources(sources)
        local groups = {}
        local by_generator = {}
        local order = {}
        for _, source in ipairs(sources or {}) do
            local key = source.generator.id.text
            local bucket = by_generator[key]
            if bucket == nil then
                bucket = { generator = source.generator, entries = {} }
                by_generator[key] = bucket
                order[#order + 1] = key
            end
            bucket.entries[#bucket.entries + 1] = Support.template_manifest_entry_for_source(source)
        end
        for _, key in ipairs(order) do
            local bucket = by_generator[key]
            groups[#groups + 1] = Support.template_manifest_group(bucket.generator, bucket.entries)
        end
        return groups
    end

    local function manifest_from_sources(domain, sources)
        return Support.template_source_manifest(
            Support.template_manifest_id(domain.id.text),
            domain,
            manifest_groups_from_sources(sources)
        )
    end

    local function complete_manifest_from_sources(capability, sources)
        return Support.template_source_manifest(
            Support.template_manifest_id(capability.id.text),
            Support.complete_capability_manifest_domain_id(capability),
            manifest_groups_from_sources(sources)
        )
    end

    local function fast_region_manifest_from_sources(bank_id, sources)
        return Support.template_source_manifest(
            Support.template_manifest_id(bank_id.text .. ".fast-region"),
            Native.NativeTemplateSupportDomainId(bank_id.text .. ".fast-region.support"),
            manifest_groups_from_sources(sources)
        )
    end

    function Native.NativeFastRegionCapability:native_template_sources_for_target(target)
        local input = Native.NativeFastRegionTemplateSourceInput(require_x64_sysv_target(target), self)
        local out = {}
        self:append_native_template_sources(out, input)
        return out
    end

    function Native.NativeFastRegionCapability:native_template_bank_request(target, runtime, bank_id)
        bank_id = bank_id or Native.NativeBankId("native.fast-region.bank")
        local sources = self:native_template_sources_for_target(target)
        local manifest = fast_region_manifest_from_sources(bank_id, sources)
        api.assert_manifest_matches_sources(manifest, sources)
        return api.bank_request_from_sources(
            bank_id,
            require_x64_sysv_target(target),
            require_value(runtime, "NativeRuntime"),
            manifest,
            sources
        )
    end

    local manifest_source_cache = setmetatable({}, { __mode = "k" })

    function Native.NativeTemplateSupportDomain:native_template_manifest()
        local sources = build_sources_for_domain(self)
        local manifest = manifest_from_sources(self, sources)
        manifest_source_cache[self] = { manifest = manifest, sources = sources }
        return manifest
    end

    function Native.NativeTemplateSupportDomain:native_template_sources()
        local manifest = self:native_template_manifest()
        local cached = manifest_source_cache[self]
        local sources = cached and cached.sources or build_sources_for_domain(self)
        api.assert_manifest_matches_sources(manifest, sources)
        return sources
    end

    function Native.NativeTemplateSupportDomain:native_template_bank_request(bank_id)
        local manifest = self:native_template_manifest()
        local cached = manifest_source_cache[self]
        local sources = cached and cached.sources or build_sources_for_domain(self)
        api.assert_manifest_matches_sources(manifest, sources)
        return api.bank_request_from_sources(
            bank_id or Support.bank_id_for_support_domain(self),
            self.target,
            self.runtime,
            manifest,
            sources
        )
    end

    local function build_sources_for_complete_capability(capability)
        require_x64_sysv_target(capability.target)
        local out = {}
        if #(capability.abi.public_adapters or {}) > 0 then
            local domain = Support.support_domain(
                Support.complete_capability_manifest_domain_id(capability),
                capability.target,
                Support.empty_runtime(),
                capability.scalars,
                capability.abi.public_adapters
            )
            for _, source in ipairs(build_sources_for_domain(domain)) do out[#out + 1] = source end
        end
        capability.code:append_native_template_sources(out, capability)
        capability.abi:append_native_template_sources(out, capability)
        capability.kernel:append_native_template_sources(out, capability)
        capability.stencil:append_native_template_sources(out, capability)
        return out
    end

    local complete_manifest_source_cache = setmetatable({}, { __mode = "k" })

    function Native.NativeCompleteCodeCapability:append_native_template_sources(out, input)
        for _, micro_op in ipairs(self.micro_ops or {}) do micro_op:append_native_template_sources(out, input) end
    end

    function Native.NativeCompleteAbiCapability:append_native_template_sources(out, input)
        for _, micro_op in ipairs(self.micro_ops or {}) do micro_op:append_native_template_sources(out, input) end
    end

    function Native.NativeCompleteKernelCapability:append_native_template_sources(out, input)
        for _, micro_op in ipairs(self.micro_ops or {}) do micro_op:append_native_template_sources(out, input) end
    end

    function Native.NativeCompleteStencilCapability:append_native_template_sources(out, input)
        for _, micro_op in ipairs(self.micro_ops or {}) do micro_op:append_native_template_sources(out, input) end
    end

    function Native.NativeCompleteBankCapability:native_template_manifest()
        local sources = build_sources_for_complete_capability(self)
        local manifest = complete_manifest_from_sources(self, sources)
        complete_manifest_source_cache[self] = { manifest = manifest, sources = sources }
        return manifest
    end

    function Native.NativeCompleteBankCapability:native_template_sources()
        local manifest = self:native_template_manifest()
        local cached = complete_manifest_source_cache[self]
        local sources = cached and cached.sources or build_sources_for_complete_capability(self)
        api.assert_manifest_matches_sources(manifest, sources)
        return sources
    end

    function Native.NativeCompleteBankCapability:native_template_bank_request(bank_id)
        local manifest = self:native_template_manifest()
        local cached = complete_manifest_source_cache[self]
        local sources = cached and cached.sources or build_sources_for_complete_capability(self)
        api.assert_manifest_matches_sources(manifest, sources)
        return api.bank_request_from_sources(
            bank_id or Support.complete_bank_id(self),
            self.target,
            Support.empty_runtime(),
            manifest,
            sources
        )
    end

    function Native.NativeScalarSupport:append_native_template_sources(out, input)
        return self.scalar:append_native_template_sources(
            out,
            Native.NativeScalarTemplateSourceBuildInput(input.domain, self)
        )
    end

    function api.bank_request_for_support_domain(domain, bank_id)
        return domain:native_template_bank_request(bank_id)
    end

    function api.bank_request_for_complete_capability(capability, bank_id)
        return capability:native_template_bank_request(bank_id)
    end

    function api.bank_request_for_fast_region_capability(capability, target, runtime, bank_id)
        return capability:native_template_bank_request(target, runtime, bank_id)
    end

    function api.host_complete_bank_request()
        return api.bank_request_for_complete_capability(Support.host_complete_bank_capability())
    end

    function api.host_scalar_bank_request()
        local domain = Support.host_scalar_support_domain()
        return api.bank_request_for_support_domain(domain, Support.bank_id_for_support_domain(domain))
    end

    function api.host_scalar_i32_bank_request()
        return api.bank_request_for_support_domain(
            Support.host_scalar_i32_support_domain(),
            Support.host_scalar_i32_bank_id()
        )
    end

    function api.append_host_scalar_i32_sources(out, target, runtime)
        local domain = Support.support_domain(
            Native.NativeTemplateSupportDomainId("native.template.support.explicit-scalar-i32"),
            require_x64_sysv_target(target),
            require_value(runtime, "NativeRuntime"),
            { Support.scalar_i32() }
        )
        for _, source in ipairs(domain:native_template_sources()) do
            api.append_source(out, source)
        end
    end

    function api.append_RuntimeCallReturnI32_sources(out, target, runtime)
        api.append_host_scalar_i32_sources(out, target, runtime)
    end

    T._lalin_api_cache.native_template_sources = api
    return api
end

return bind_context
