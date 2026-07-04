local asdl = require("lalin.asdl")

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_template_sources ~= nil then return T._lalin_api_cache.native_template_sources end

    local Native = T.LalinNative
    local Code = T.LalinCode
    local Core = T.LalinCore
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
            lines[#lines + 1] = "extern const uint8_t " .. hole.symbol .. ";"
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
    function Native.NativeAbiByRefValue:native_c_boundary_type() return "void *" end
    function Native.NativeAbiSRetResult:native_c_boundary_type() return "void" end

    function Native.NativeAbiProjection:native_projection_token(_target)
        internal_error("unsupported native ABI projection token")
    end

    function Native.NativeAbiVoidResult:native_projection_token(_target) return "void" end
    function Native.NativeAbiScalarValue:native_projection_token(_target) return self.scalar:native_scalar_token() end
    function Native.NativeAbiPointerValue:native_projection_token(_target) return "ptr" .. tostring(self.scalar.bits) end
    function Native.NativeAbiByRefValue:native_projection_token(_target) return "byref" .. tostring(self.alignment) end
    function Native.NativeAbiSRetResult:native_projection_token(target) return "sret." .. self.pointer_param.abi:native_projection_token(target) end

    function Native.NativeAbiProjection:native_frame_c_type(_target)
        internal_error("unsupported native ABI projection frame type")
    end

    function Native.NativeAbiScalarValue:native_frame_c_type(_target) return self.scalar:native_c_scalar_type() end
    function Native.NativeAbiPointerValue:native_frame_c_type(_target) return "uintptr_t" end
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

    function Native.NativeAbiProjection:native_store_result_to_frame(_target, _hole, _expr)
        internal_error("unsupported native ABI result frame store")
    end

    function Native.NativeAbiScalarValue:native_store_result_to_frame(target, hole, expr)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(" .. self:native_frame_c_type(target) .. ")(" .. expr .. ")")
    end

    function Native.NativeAbiPointerValue:native_store_result_to_frame(target, hole, expr)
        return frame_store(self:native_frame_c_type(target), hole_address_expr(hole), "(uintptr_t)(" .. expr .. ")")
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

    local function append_terminal_source(out, input, scalar)
        local token = scalar:native_scalar_token()
        local ty = scalar:native_code_type()
        local axis = Native.NativeCodeTermReturnAxis({ ty })
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

    local function append_descriptor_make_source(out, input, kind, elem_ty, data_location, len_location, stride_location)
        local ptr_scalar = Support.scalar_pointer(input.domain.target.pointer_bits)
        local index_scalar = Support.scalar_index(input.domain.target.pointer_bits)
        local data_token = Support.logical_location_token(data_location)
        local len_token = Support.logical_location_token(len_location)
        local stride_token = stride_location and Support.logical_location_token(stride_location) or nil
        local elem_token = elem_ty and symbol_fragment(elem_ty:native_source_type_token()) or "bytes"
        local id_tail = kind .. ".make." .. elem_token .. ".data." .. data_token .. ".len." .. len_token .. (stride_token and (".stride." .. stride_token) or "")
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
        local axis = kind == "view" and Native.NativeCodeInstViewMakeAxis(elem_ty) or (kind == "slice" and Native.NativeCodeInstSliceMakeAxis(elem_ty) or Native.NativeCodeInstByteSpanMakeAxis)
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

    local function append_descriptor_extract_source(out, input, kind, field_name, dest_scalar, dest_location)
        local dst_token = Support.logical_location_token(dest_location)
        local id_tail = kind .. "." .. field_name .. ".to." .. dst_token
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
        local axis = (kind == "view" and (field_name == "data" and Native.NativeCodeInstViewDataAxis or (field_name == "len" and Native.NativeCodeInstViewLenAxis or Native.NativeCodeInstViewStrideAxis)))
            or (kind == "slice" and (field_name == "data" and Native.NativeCodeInstSliceDataAxis or Native.NativeCodeInstSliceLenAxis))
            or (field_name == "data" and Native.NativeCodeInstByteSpanDataAxis or Native.NativeCodeInstByteSpanLenAxis)
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
                    append_descriptor_make_source(out, input, "slice", elem_ty, data_location, len_location, nil)
                    for _, stride_location in ipairs({ frame_slot, cont_arg }) do append_descriptor_make_source(out, input, "view", elem_ty, data_location, len_location, stride_location) end
                end
            end
        end
        for _, data_location in ipairs({ frame_slot, cont_arg }) do
            for _, len_location in ipairs({ frame_slot, cont_arg }) do append_descriptor_make_source(out, input, "bytespan", nil, data_location, len_location, nil) end
        end
        for _, dest_location in ipairs({ frame_slot, cont_arg }) do
            append_descriptor_extract_source(out, input, "slice", "data", ptr_scalar, dest_location)
            append_descriptor_extract_source(out, input, "slice", "len", index_scalar, dest_location)
            append_descriptor_extract_source(out, input, "view", "data", ptr_scalar, dest_location)
            append_descriptor_extract_source(out, input, "view", "len", index_scalar, dest_location)
            append_descriptor_extract_source(out, input, "view", "stride", index_scalar, dest_location)
            append_descriptor_extract_source(out, input, "bytespan", "data", ptr_scalar, dest_location)
            append_descriptor_extract_source(out, input, "bytespan", "len", index_scalar, dest_location)
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
        append_call_return_control_source(out, input)
        for _, scalar_support in ipairs(input.domain.scalars or {}) do
            local scalar = scalar_support.scalar
            append_switch_step_control_source(out, input, scalar, Support.location_class_frame_slot())
            append_switch_step_control_source(out, input, scalar, Support.location_class_continuation_arg())
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
        if asdl.isa(projection.result.abi, Native.NativeAbiScalarValue) or asdl.isa(projection.result.abi, Native.NativeAbiPointerValue) then
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
        append_hole_externs(lines, holes)
        lines[#lines + 1] = continuation_extern(first_symbol, first_signature)
        lines[#lines + 1] = projection:native_c_function_declaration(entry) .. " {"
        lines[#lines + 1] = "    uint8_t frame[(uint32_t)(uintptr_t)&" .. frame_size_hole.symbol .. "];"
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
        elseif asdl.isa(result_abi, Native.NativeAbiPointerValue) then
            operands[#operands + 1] = Support.stencil_operand(#operands, Support.scalar_pointer(projection.target.pointer_bits), Support.location_class_frame_slot())
        end
        local next_ordinal = Support.next_continuation_ordinal()
        return Support.spill_all_stencil_signature(Support.scalar_bool8(), operands, { Support.stencil_continuation_signature(next_ordinal, {}) })
    end

    local function call_result_hole_needed(projection)
        return asdl.isa(projection.result.abi, Native.NativeAbiScalarValue) or asdl.isa(projection.result.abi, Native.NativeAbiPointerValue)
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
        local axis = Native.NativeCodeInstCallAxis(Code.CodeCallDirect(Code.CodeFuncId("native.call.direct." .. token)), Code.CodeSigId("native.call.sig." .. token))
        local family = Support.code_inst_frame_family("call.direct." .. token, input.domain.target, Support.scalar_bool8(), axis)
        local call_hole = call_rel32_hole("native.hole.code.inst.call.direct." .. token .. ".target")
        local holes = { call_hole }
        for _, param in ipairs(projection.params or {}) do holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.direct." .. token .. ".arg" .. tostring(param.param_index)) end
        if call_result_hole_needed(projection) then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.direct." .. token .. ".result") end
        local next_symbol = Support.next_continuation_symbol()
        local signature = call_source_signature(projection)
        local entry = "lalin_native_code_inst_call_direct_" .. symbol_fragment(token)
        local lines = c_prelude()
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
        local sig_id = Code.CodeSigId("native.call.sig." .. token)
        local call_target = closure and Code.CodeCallClosure(Code.CodeValueId("native.call.closure." .. token), sig_id) or Code.CodeCallIndirect(Code.CodeValueId("native.call.indirect." .. token), sig_id)
        local axis = Native.NativeCodeInstCallAxis(call_target, sig_id)
        local family = Support.code_inst_frame_family("call." .. mode .. "." .. token, input.domain.target, Support.scalar_bool8(), axis)
        local holes = { frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".fn") }
        if closure then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".env") end
        for _, param in ipairs(projection.params or {}) do holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".arg" .. tostring(param.param_index)) end
        if call_result_hole_needed(projection) then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call." .. mode .. "." .. token .. ".result") end
        local next_symbol = Support.next_continuation_symbol()
        local signature = call_source_signature(projection)
        local entry = "lalin_native_code_inst_call_" .. mode .. "_" .. symbol_fragment(token)
        local lines = c_prelude()
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

    local function append_runtime_call_source(out, input, symbol)
        local projection = symbol.abi
        local token = symbol.id.text .. "." .. projection:native_projection_token()
        local axis = Native.NativeCodeInstCallAxis(Code.CodeCallExtern(Code.CodeExternId(symbol.id.text)), Code.CodeSigId("native.call.sig." .. token))
        local family = Support.code_inst_frame_family("call.extern." .. token, input.domain.target, Support.scalar_bool8(), axis)
        local holes = {}
        for _, param in ipairs(projection.params or {}) do holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.extern." .. token .. ".arg" .. tostring(param.param_index)) end
        if call_result_hole_needed(projection) then holes[#holes + 1] = frame_offset_hole("native.hole.code.inst.call.extern." .. token .. ".result") end
        local next_symbol = Support.next_continuation_symbol()
        local signature = call_source_signature(projection)
        local entry = "lalin_native_code_inst_call_extern_" .. symbol_fragment(token)
        local lines = c_prelude()
        append_hole_externs(lines, holes)
        lines[#lines + 1] = "extern " .. projection:native_c_function_declaration(symbol.name) .. ";"
        lines[#lines + 1] = continuation_extern(next_symbol, Support.stencil_continuation_signature(Support.next_continuation_ordinal(), {}))
        lines[#lines + 1] = "void " .. entry .. "(uint8_t *frame) {"
        append_call_common_lines(lines, input, projection, holes, function(args) return symbol.name .. "(" .. args .. ")" end)
        lines[#lines + 1] = "    " .. next_symbol.name .. "(frame);"
        lines[#lines + 1] = "}"
        append_manifest_source(out, "code.inst.call.extern." .. token, family, Native.NativeChunkCallOp, signature, Native.NativeExtractContinuationFragment({ next_symbol }), entry, lines, holes, { Support.next_continuation_ordinal() }, { Native.NativeTemplateRelocationRuntimeSymbol })
    end

    local function append_domain_abi_and_call_sources(out, input)
        for _, projection in ipairs(input.domain.public_abi_adapters or {}) do
            append_public_abi_adapter_source(out, input, projection)
            append_direct_call_source(out, input, projection)
            append_indirect_call_source(out, input, projection, false)
            append_indirect_call_source(out, input, projection, true)
        end
        for _, symbol in ipairs((input.domain.runtime and input.domain.runtime.symbols) or {}) do
            append_runtime_call_source(out, input, symbol)
        end
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
        append_terminal_source(out, input, self)
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
        return out
    end

    local function manifest_from_sources(domain, sources)
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
        return Support.template_source_manifest(
            Support.template_manifest_id(domain.id.text),
            domain,
            groups
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

    function Native.NativeScalarSupport:append_native_template_sources(out, input)
        return self.scalar:append_native_template_sources(
            out,
            Native.NativeScalarTemplateSourceBuildInput(input.domain, self)
        )
    end

    function api.bank_request_for_support_domain(domain, bank_id)
        return domain:native_template_bank_request(bank_id)
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
