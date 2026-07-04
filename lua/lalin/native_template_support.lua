local asdl = require("lalin.asdl")
local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then ffi = nil end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_template_support ~= nil then return T._lalin_api_cache.native_template_support end

    local Native = T.LalinNative
    local Code = T.LalinCode
    local api = {}

    local function boundary_error(message)
        error("lalin.native_template_support: " .. message, 3)
    end

    local function require_value(value, name)
        if value == nil then boundary_error("missing " .. name) end
        return value
    end

    local function require_ffi()
        if ffi == nil then boundary_error("ffi is required for host native template support facts") end
        return ffi
    end

    -- This module constructs ASDL support-domain and manifest facts for
    -- NativeTemplateSource construction. Support domains declare finite stencil
    -- generator/metavar dimensions; unbounded program values remain patch
    -- coordinates, ABI projections, frame slots, constant-pool entries, or graph
    -- edges, never register-fragment bank axes.

    function api.i8() return Code.CodeTyInt(8, Code.CodeSigned) end
    function api.u8() return Code.CodeTyInt(8, Code.CodeUnsigned) end
    function api.i16() return Code.CodeTyInt(16, Code.CodeSigned) end
    function api.u16() return Code.CodeTyInt(16, Code.CodeUnsigned) end
    function api.i32() return Code.CodeTyInt(32, Code.CodeSigned) end
    function api.u32() return Code.CodeTyInt(32, Code.CodeUnsigned) end
    function api.i64() return Code.CodeTyInt(64, Code.CodeSigned) end
    function api.u64() return Code.CodeTyInt(64, Code.CodeUnsigned) end
    function api.f32() return Code.CodeTyFloat(32) end
    function api.f64() return Code.CodeTyFloat(64) end
    function api.index() return Code.CodeTyIndex end
    function api.data_ptr(pointee) return Code.CodeTyDataPtr(pointee) end

    function api.scalar_bool8() return Native.NativeScalarBool8 end
    function api.scalar_int(bits, signedness)
        return Native.NativeScalarInt(require_value(bits, "integer scalar bit width"), require_value(signedness, "CodeIntSignedness"))
    end
    function api.scalar_i8() return api.scalar_int(8, Code.CodeSigned) end
    function api.scalar_u8() return api.scalar_int(8, Code.CodeUnsigned) end
    function api.scalar_i16() return api.scalar_int(16, Code.CodeSigned) end
    function api.scalar_u16() return api.scalar_int(16, Code.CodeUnsigned) end
    function api.scalar_i32() return api.scalar_int(32, Code.CodeSigned) end
    function api.scalar_u32() return api.scalar_int(32, Code.CodeUnsigned) end
    function api.scalar_i64() return api.scalar_int(64, Code.CodeSigned) end
    function api.scalar_u64() return api.scalar_int(64, Code.CodeUnsigned) end
    function api.scalar_index(bits) return Native.NativeScalarIndex(require_value(bits, "index scalar bit width")) end
    function api.scalar_pointer(bits) return Native.NativeScalarPointer(require_value(bits, "pointer scalar bit width")) end
    function api.scalar_f32() return Native.NativeScalarFloat(32) end
    function api.scalar_f64() return Native.NativeScalarFloat(64) end

    function Native.NativeScalarBool8:native_code_type()
        return Code.CodeTyBool8
    end

    function Native.NativeScalarInt:native_code_type()
        return Code.CodeTyInt(self.bits, self.signedness)
    end

    function Native.NativeScalarIndex:native_code_type()
        return Code.CodeTyIndex
    end

    function Native.NativeScalarPointer:native_code_type()
        return Code.CodeTyDataPtr(nil)
    end

    function Native.NativeScalarFloat:native_code_type()
        return Code.CodeTyFloat(self.bits)
    end

    function Native.NativeScalarBool8:native_scalar_token()
        return "bool8"
    end

    function Native.NativeScalarInt:native_scalar_token()
        local prefix = self.signedness == Code.CodeSigned and "i" or "u"
        return prefix .. tostring(self.bits)
    end

    function Native.NativeScalarIndex:native_scalar_token()
        return "index" .. tostring(self.bits)
    end

    function Native.NativeScalarPointer:native_scalar_token()
        return "ptr" .. tostring(self.bits)
    end

    function Native.NativeScalarFloat:native_scalar_token()
        return "f" .. tostring(self.bits)
    end

    function Native.NativeScalarBool8:native_extension_policy()
        return Native.NativeZeroExtend
    end

    function Native.NativeScalarInt:native_extension_policy()
        if self.signedness == Code.CodeSigned then return Native.NativeSignExtend end
        return Native.NativeZeroExtend
    end

    function Native.NativeScalarIndex:native_extension_policy()
        return Native.NativePreserveLowerBits
    end

    function Native.NativeScalarPointer:native_extension_policy()
        return Native.NativePreserveLowerBits
    end

    function Native.NativeScalarFloat:native_extension_policy()
        return Native.NativePreserveLowerBits
    end

    function Native.NativeScalarBool8:native_register_class()
        return Native.NativeRegisterClassGpr
    end

    function Native.NativeScalarInt:native_register_class()
        return Native.NativeRegisterClassGpr
    end

    function Native.NativeScalarIndex:native_register_class()
        return Native.NativeRegisterClassGpr
    end

    function Native.NativeScalarPointer:native_register_class()
        return Native.NativeRegisterClassPointer
    end

    function Native.NativeScalarFloat:native_register_class()
        return Native.NativeRegisterClassFloat
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

    function Native.NativeScalarBool8:native_x64_result_register_name()
        return "al"
    end

    function Native.NativeScalarBool8:native_x64_param_register_name(index)
        index = index or 0
        if index == 0 then return "dil" end
        if index == 1 then return "sil" end
        if index == 2 then return "dl" end
        if index == 3 then return "cl" end
        if index == 4 then return "r8b" end
        return "r9b"
    end

    function Native.NativeScalarBool8:native_x64_scratch_register_name()
        return "cl"
    end

    function Native.NativeScalarInt:native_x64_result_register_name()
        if self.bits <= 8 then return "al" end
        if self.bits <= 16 then return "ax" end
        if self.bits <= 32 then return "eax" end
        return "rax"
    end

    function Native.NativeScalarInt:native_x64_param_register_name(index)
        index = index or 0
        if index == 0 then
            if self.bits <= 8 then return "dil" end
            if self.bits <= 16 then return "di" end
            if self.bits <= 32 then return "edi" end
            return "rdi"
        end
        if index == 1 then
            if self.bits <= 8 then return "sil" end
            if self.bits <= 16 then return "si" end
            if self.bits <= 32 then return "esi" end
            return "rsi"
        end
        if index == 2 then
            if self.bits <= 8 then return "dl" end
            if self.bits <= 16 then return "dx" end
            if self.bits <= 32 then return "edx" end
            return "rdx"
        end
        if index == 3 then return self:native_x64_scratch_register_name() end
        if index == 4 then
            if self.bits <= 8 then return "r8b" end
            if self.bits <= 16 then return "r8w" end
            if self.bits <= 32 then return "r8d" end
            return "r8"
        end
        if self.bits <= 8 then return "r9b" end
        if self.bits <= 16 then return "r9w" end
        if self.bits <= 32 then return "r9d" end
        return "r9"
    end

    function Native.NativeScalarInt:native_x64_scratch_register_name()
        if self.bits <= 8 then return "cl" end
        if self.bits <= 16 then return "cx" end
        if self.bits <= 32 then return "ecx" end
        return "rcx"
    end

    function Native.NativeScalarIndex:native_x64_result_register_name()
        return "rax"
    end

    function Native.NativeScalarIndex:native_x64_param_register_name(index)
        return Native.NativeScalarInt(64, Code.CodeSigned):native_x64_param_register_name(index or 0)
    end

    function Native.NativeScalarIndex:native_x64_scratch_register_name()
        return "rcx"
    end

    function Native.NativeScalarPointer:native_x64_result_register_name()
        return "rax"
    end

    function Native.NativeScalarPointer:native_x64_param_register_name(index)
        return Native.NativeScalarInt(64, Code.CodeUnsigned):native_x64_param_register_name(index or 0)
    end

    function Native.NativeScalarPointer:native_x64_scratch_register_name()
        return "rcx"
    end

    function Native.NativeScalarFloat:native_x64_result_register_name()
        return "xmm0"
    end

    function Native.NativeScalarFloat:native_x64_param_register_name(index)
        index = index or 0
        if index == 0 then return "xmm0" end
        if index == 1 then return "xmm1" end
        if index == 2 then return "xmm2" end
        if index == 3 then return "xmm3" end
        if index == 4 then return "xmm4" end
        return "xmm5"
    end

    function Native.NativeScalarFloat:native_x64_scratch_register_name()
        return "xmm1"
    end

    local function register_id(target, scalar, role, machine_name)
        return Native.NativeRegisterId(table.concat({
            "native.register",
            target.id.text,
            scalar:native_scalar_token(),
            role,
            machine_name,
        }, "."))
    end

    function api.register(target, scalar, role, machine_name)
        target = require_value(target, "NativeTarget")
        scalar = require_value(scalar, "NativeMachineScalarRep")
        machine_name = require_value(machine_name, "register machine name")
        return Native.NativeRegister(
            register_id(target, scalar, require_value(role, "register role"), machine_name),
            target,
            scalar:native_register_class(),
            scalar,
            machine_name
        )
    end

    function api.result_register(target, scalar)
        return api.register(target, scalar, "result", scalar:native_x64_result_register_name())
    end

    function api.param_register(target, scalar, index)
        index = index or 0
        return api.register(target, scalar, "param" .. tostring(index), scalar:native_x64_param_register_name(index))
    end

    function api.scratch_register(target, scalar)
        return api.register(target, scalar, "scratch", scalar:native_x64_scratch_register_name())
    end

    function api.scalar_support(scalar)
        scalar = require_value(scalar, "NativeMachineScalarRep")
        return Native.NativeScalarSupport(scalar, scalar:native_code_type(), scalar:native_extension_policy())
    end

    function api.register_support(target, scalar)
        local result = api.result_register(target, scalar)
        local param = api.param_register(target, scalar)
        local scratch = api.scratch_register(target, scalar)
        return {
            Native.NativeRegisterSupport(result, { scalar }, {
                Native.NativeRegisterUseResult,
                Native.NativeRegisterUseAccumulator(Native.NativeAccumulatorGeneral),
            }),
            Native.NativeRegisterSupport(param, { scalar }, { Native.NativeRegisterUseParam }),
            Native.NativeRegisterSupport(scratch, { scalar }, {
                Native.NativeRegisterUseScratch(Native.NativeScratchGeneral),
            }),
        }
    end

    function api.abi_scalar_convention(target, scalar)
        local param0_location = Native.NativeValueRegisterLocation(api.param_register(target, scalar, 0))
        local param1_location = Native.NativeValueRegisterLocation(api.param_register(target, scalar, 1))
        local result_location = Native.NativeValueRegisterLocation(api.result_register(target, scalar))
        return Native.NativeAbiScalarConvention(
            scalar,
            {
                Native.NativeAbiParamPlacement(0, scalar, param0_location, scalar:native_extension_policy()),
                Native.NativeAbiParamPlacement(1, scalar, param1_location, scalar:native_extension_policy()),
            },
            { Native.NativeAbiResultPlacement(0, scalar, result_location, scalar:native_extension_policy()) }
        )
    end

    function api.native_call_void() return Native.NativeCallVoid end
    function api.native_call_return_i32() return Native.NativeCallReturnI32 end
    function api.native_call_return_i64() return Native.NativeCallReturnI64 end
    function api.native_call_return_f64() return Native.NativeCallReturnF64 end
    function api.native_call_return_scalar(scalar) return Native.NativeCallReturnScalar(require_value(scalar, "NativeMachineScalarRep")) end
    function api.native_call_code_sig(projection) return Native.NativeCallCodeSig(require_value(projection, "NativeAbiFunctionProjection")) end
    function api.native_call_stencil_abi(projection) return Native.NativeCallStencilAbi(require_value(projection, "NativeAbiFunctionProjection")) end

    function api.register_none() return Native.NativeRegisterProtocolNone end
    function api.register_x64_sysv() return Native.NativeRegisterProtocolX64SysV end
    function api.register_x64_win64() return Native.NativeRegisterProtocolX64Win64 end
    function api.register_aarch64() return Native.NativeRegisterProtocolAArch64 end

    function api.protocol(call, registers)
        return Native.NativeTemplateProtocol(
            require_value(call, "NativeCallProtocol"),
            require_value(registers, "NativeRegisterProtocol")
        )
    end

    function api.protocol_for_scalar(scalar, registers)
        return api.protocol(api.native_call_return_scalar(scalar), registers or api.register_x64_sysv())
    end

    function api.protocol_for_scalar_frame(scalar)
        return api.protocol(api.native_call_return_scalar(scalar), api.register_none())
    end

    function api.protocol_void_none()
        return api.protocol(api.native_call_void(), api.register_none())
    end

    function api.protocol_i32_none()
        return api.protocol(api.native_call_return_i32(), api.register_none())
    end

    function api.protocol_i32_x64_sysv()
        return api.protocol(api.native_call_return_i32(), api.register_x64_sysv())
    end

    function api.axis_target(target) return Native.NativeAxisTarget(require_value(target, "NativeTarget")) end
    function api.axis_code_inst(axis) return Native.NativeAxisCodeInst(require_value(axis, "NativeCodeInstAxis")) end
    function api.axis_code_term(axis) return Native.NativeAxisCodeTerm(require_value(axis, "NativeCodeTermAxis")) end
    function api.axis_code_const(axis) return Native.NativeAxisCodeConst(require_value(axis, "NativeCodeConstAxis")) end
    function api.axis_code_type(ty) return Native.NativeAxisCodeType(require_value(ty, "CodeType")) end
    function api.axis_abi(protocol) return Native.NativeAxisAbi(require_value(protocol, "NativeCallProtocol")) end
    function api.axis_register_protocol(protocol) return Native.NativeAxisRegisterProtocol(require_value(protocol, "NativeRegisterProtocol")) end
    function api.axis_machine_scalar(scalar) return Native.NativeAxisMachineScalar(require_value(scalar, "NativeMachineScalarRep")) end
    function api.axis_register_class(class) return Native.NativeAxisRegisterClass(require_value(class, "NativeRegisterClass")) end
    function api.axis_value_placement(placement) return Native.NativeAxisValuePlacement(require_value(placement, "NativeValuePlacement")) end
    function api.axis_abi_param(placement) return Native.NativeAxisAbiParam(require_value(placement, "NativeAbiParamPlacement")) end
    function api.axis_abi_result(placement) return Native.NativeAxisAbiResult(require_value(placement, "NativeAbiResultPlacement")) end

    function api.abi_void_result()
        return Native.NativeAbiVoidResult
    end

    function api.abi_scalar_value(scalar, extension)
        return Native.NativeAbiScalarValue(
            require_value(scalar, "NativeMachineScalarRep"),
            extension or scalar:native_extension_policy()
        )
    end

    function api.abi_pointer_value(scalar)
        return Native.NativeAbiPointerValue(require_value(scalar, "NativeMachineScalarRep"))
    end

    function api.abi_byref_value(pointee_ty, mutability, alignment)
        return Native.NativeAbiByRefValue(
            require_value(pointee_ty, "CodeType"),
            mutability or Native.NativeAbiByRefReadonly,
            require_value(alignment, "ABI byref alignment")
        )
    end

    function api.abi_descriptor_field(field_name, offset, value)
        return Native.NativeAbiDescriptorField(
            require_value(field_name, "ABI descriptor field name"),
            require_value(offset, "ABI descriptor field offset"),
            require_value(value, "NativeAbiProjection")
        )
    end

    function api.abi_descriptor_value(layout, fields)
        return Native.NativeAbiDescriptorValue(
            require_value(layout, "TypeLayout"),
            fields or {}
        )
    end

    function api.abi_param_projection(param_index, source_ty, abi)
        return Native.NativeAbiParamProjection(
            require_value(param_index, "ABI parameter index"),
            require_value(source_ty, "CodeType"),
            require_value(abi, "NativeAbiProjection")
        )
    end

    function api.abi_result_projection(source_ty, abi)
        return Native.NativeAbiResultProjection(
            source_ty,
            require_value(abi, "NativeAbiProjection")
        )
    end

    function api.abi_sret_result(result_ty, pointer_param)
        return Native.NativeAbiSRetResult(
            require_value(result_ty, "CodeType"),
            require_value(pointer_param, "NativeAbiParamProjection")
        )
    end

    function api.abi_function_projection(target, params, result)
        return Native.NativeAbiFunctionProjection(
            require_value(target, "NativeTarget"),
            params or {},
            require_value(result, "NativeAbiResultProjection")
        )
    end

    function api.stencil_generator_id(text)
        return Native.NativeStencilGeneratorId("native.stencil.generator." .. require_value(text, "stencil generator id text"))
    end

    function api.stencil_metavar_id(text)
        return Native.NativeStencilMetavarId("native.stencil.metavar." .. require_value(text, "stencil metavar id text"))
    end

    function api.stencil_configuration_id(text)
        return Native.NativeStencilConfigurationId("native.stencil.configuration." .. require_value(text, "stencil configuration id text"))
    end

    function api.template_manifest_id(text)
        return Native.NativeTemplateManifestId("native.template.manifest." .. require_value(text, "template manifest id text"))
    end

    function api.hole_ordinal_id(text)
        return Native.NativeHoleOrdinalId("native.hole.ordinal." .. require_value(text, "hole ordinal id text"))
    end

    function api.constant_pool_entry_id(text)
        return Native.NativeConstantPoolEntryId("native.constant_pool.entry." .. require_value(text, "constant-pool entry id text"))
    end

    function api.location_class_continuation_arg() return Native.NativeStencilContinuationArgLocationClass end
    function api.location_class_frame_slot() return Native.NativeStencilFrameSlotLocationClass end
    function api.location_class_constant_pool() return Native.NativeStencilConstantPoolLocationClass end
    function api.location_class_immediate() return Native.NativeStencilImmediateLocationClass end
    function api.location_class_stack_slot() return Native.NativeStencilStackSlotLocationClass end
    function api.location_class_runtime_param() return Native.NativeStencilRuntimeParamLocationClass end

    function Native.NativeStencilContinuationArgLocationClass:native_logical_location_token() return "arg" end
    function Native.NativeStencilFrameSlotLocationClass:native_logical_location_token() return "slot" end
    function Native.NativeStencilConstantPoolLocationClass:native_logical_location_token() return "pool" end
    function Native.NativeStencilImmediateLocationClass:native_logical_location_token() return "const" end
    function Native.NativeStencilStackSlotLocationClass:native_logical_location_token() return "stack" end
    function Native.NativeStencilRuntimeParamLocationClass:native_logical_location_token() return "runtime" end

    function api.logical_location_token(location_class)
        return require_value(location_class, "NativeStencilValueLocationClass"):native_logical_location_token()
    end

    function api.logical_location_arg_token(index)
        if index == nil then return "arg" end
        return "arg" .. tostring(index)
    end

    function api.logical_location_slot_token(slot)
        if slot == nil then return "slot" end
        if slot.id ~= nil and slot.id.text ~= nil then return "slot." .. slot.id.text end
        return "slot" .. tostring(slot)
    end

    function api.logical_location_const_token(value)
        if value == nil then return "const" end
        return "const" .. tostring(value)
    end

    function api.logical_location_pool_token(entry)
        if entry == nil then return "pool" end
        if entry.text ~= nil then return "pool." .. entry.text end
        if entry.id ~= nil and entry.id.text ~= nil then return "pool." .. entry.id.text end
        return "pool" .. tostring(entry)
    end

    local function zero_to(limit)
        limit = require_value(limit, "passthrough limit")
        local out = {}
        for i = 0, limit do out[#out + 1] = i end
        return out
    end

    function api.passthrough_int_limit(limit)
        return require_value(limit, "integer passthrough limit")
    end

    function api.passthrough_float_limit(limit)
        return require_value(limit, "float passthrough limit")
    end

    function api.spill_all_passthrough_int_limit() return 0 end
    function api.spill_all_passthrough_float_limit() return 0 end
    function api.passthrough_int_counts(limit) return zero_to(api.passthrough_int_limit(limit)) end
    function api.passthrough_float_counts(limit) return zero_to(api.passthrough_float_limit(limit)) end

    function api.frame_stack_limit(max_bytes, alignment)
        return Native.NativeFrameStackLimit(
            require_value(max_bytes, "frame stack byte limit"),
            require_value(alignment, "frame stack alignment")
        )
    end

    function api.x64_sysv_frame_stack_limit()
        return api.frame_stack_limit(256, 16)
    end

    function api.public_abi_adapter_support(projections)
        return projections or {}
    end

    function api.constant_pool_scalar_const_kind(scalar)
        return Native.NativeConstantPoolScalarConst(require_value(scalar, "NativeMachineScalarRep"))
    end

    function api.constant_pool_pointer_const_kind()
        return Native.NativeConstantPoolPointerConst
    end

    function api.constant_pool_bytes_kind(size, alignment)
        return Native.NativeConstantPoolBytes(
            require_value(size, "constant-pool byte entry size"),
            require_value(alignment, "constant-pool byte entry alignment")
        )
    end

    function api.constant_pool_support(max_entries, max_bytes, entry_kinds)
        return Native.NativeConstantPoolSupport(
            require_value(max_entries, "constant-pool entry limit"),
            require_value(max_bytes, "constant-pool byte limit"),
            entry_kinds or {}
        )
    end

    function api.empty_constant_pool_support()
        return api.constant_pool_support(0, 0, {})
    end

    function api.hole_ordinal(id, ordinal, symbol, hole)
        return Native.NativeHoleOrdinal(
            require_value(id, "NativeHoleOrdinalId"),
            require_value(ordinal, "hole ordinal"),
            require_value(symbol, "extern hole symbol"),
            require_value(hole, "NativePatchHole")
        )
    end

    function api.extern_hole_symbol(ordinal, c_symbol)
        return Native.NativeExternHoleSymbol(
            require_value(ordinal, "NativeHoleOrdinal"),
            require_value(c_symbol, "C extern hole symbol")
        )
    end

    function api.continuation_symbol(name)
        name = require_value(name, "native continuation symbol name")
        return Native.NativeContinuationSymbol(
            Native.NativeContinuationSymbolId("native.continuation." .. name),
            name
        )
    end

    function api.first_continuation_symbol()
        return api.continuation_symbol("lalin_native_cont_first")
    end

    function api.next_continuation_symbol()
        return api.continuation_symbol("lalin_native_cont_next")
    end

    function api.then_continuation_symbol()
        return api.continuation_symbol("lalin_native_cont_then")
    end

    function api.else_continuation_symbol()
        return api.continuation_symbol("lalin_native_cont_else")
    end

    function api.terminal_continuation_symbol()
        return api.continuation_symbol("lalin_native_cont_terminal")
    end

    function api.continuation_ordinal(ordinal, symbol)
        return Native.NativeContinuationOrdinal(
            require_value(ordinal, "continuation ordinal"),
            require_value(symbol, "NativeContinuationSymbol")
        )
    end

    function api.first_continuation_ordinal()
        return api.continuation_ordinal(0, api.first_continuation_symbol())
    end

    function api.next_continuation_ordinal()
        return api.continuation_ordinal(0, api.next_continuation_symbol())
    end

    function api.then_continuation_ordinal()
        return api.continuation_ordinal(0, api.then_continuation_symbol())
    end

    function api.else_continuation_ordinal()
        return api.continuation_ordinal(1, api.else_continuation_symbol())
    end

    function api.terminal_continuation_ordinal()
        return api.continuation_ordinal(0, api.terminal_continuation_symbol())
    end

    function api.stencil_frame_param(scalar)
        return Native.NativeStencilFrameParam(require_value(scalar, "NativeMachineScalarRep"))
    end

    function api.stencil_passthrough(index, scalar, class)
        return Native.NativeStencilPassthrough(
            require_value(index, "stencil passthrough index"),
            require_value(scalar, "NativeMachineScalarRep"),
            require_value(class, "NativeStencilPassthroughClass")
        )
    end

    function api.stencil_int_passthrough(index, scalar)
        return api.stencil_passthrough(index, scalar, Native.NativeStencilPassthroughIntLike)
    end

    function api.stencil_float_passthrough(index, scalar)
        return api.stencil_passthrough(index, scalar, Native.NativeStencilPassthroughFloatLike)
    end

    function api.stencil_operand(index, scalar, location)
        return Native.NativeStencilOperand(
            require_value(index, "stencil operand index"),
            require_value(scalar, "NativeMachineScalarRep"),
            require_value(location, "NativeStencilValueLocationClass")
        )
    end

    function api.stencil_continuation_param(index, scalar, location)
        return Native.NativeStencilContinuationParam(
            require_value(index, "stencil continuation parameter index"),
            require_value(scalar, "NativeMachineScalarRep"),
            require_value(location, "NativeStencilValueLocationClass")
        )
    end

    function api.stencil_continuation_signature(ordinal, params)
        return Native.NativeStencilContinuationSignature(
            require_value(ordinal, "NativeContinuationOrdinal"),
            params or {}
        )
    end

    function api.stencil_signature(frame_param, passthroughs, operands, continuations)
        return Native.NativeStencilSignature(
            require_value(frame_param, "NativeStencilFrameParam"),
            passthroughs or {},
            operands or {},
            continuations or {}
        )
    end

    function api.spill_all_stencil_signature(frame_scalar, operands, continuations)
        return api.stencil_signature(
            api.stencil_frame_param(require_value(frame_scalar, "NativeMachineScalarRep")),
            {},
            operands or {},
            continuations or {}
        )
    end

    function api.scalar_metavar(id, values)
        return Native.NativeStencilScalarMetavar(require_value(id, "NativeStencilMetavarId"), values or {})
    end

    function api.location_class_metavar(id, values)
        return Native.NativeStencilLocationClassMetavar(require_value(id, "NativeStencilMetavarId"), values or {})
    end

    function api.passthrough_int_count_metavar(id, counts)
        return Native.NativeStencilPassthroughIntCountMetavar(require_value(id, "NativeStencilMetavarId"), counts or {})
    end

    function api.passthrough_float_count_metavar(id, counts)
        return Native.NativeStencilPassthroughFloatCountMetavar(require_value(id, "NativeStencilMetavarId"), counts or {})
    end

    function api.control_shape_metavar(id, shapes)
        return Native.NativeStencilControlShapeMetavar(require_value(id, "NativeStencilMetavarId"), shapes or {})
    end

    function api.code_inst_metavar(id, axes)
        return Native.NativeStencilCodeInstMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.code_term_metavar(id, axes)
        return Native.NativeStencilCodeTermMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.kernel_metavar(id, axes)
        return Native.NativeStencilKernelMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.stencil_producer_metavar(id, axes)
        return Native.NativeStencilProducerMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.stencil_access_metavar(id, axes)
        return Native.NativeStencilAccessMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.stencil_point_metavar(id, axes)
        return Native.NativeStencilPointMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.stencil_sink_metavar(id, axes)
        return Native.NativeStencilSinkMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.stencil_schedule_metavar(id, axes)
        return Native.NativeStencilScheduleMetavar(require_value(id, "NativeStencilMetavarId"), axes or {})
    end

    function api.scalar_metavar_value(scalar) return Native.NativeStencilScalarMetavarValue(require_value(scalar, "NativeMachineScalarRep")) end
    function api.location_class_metavar_value(location) return Native.NativeStencilLocationClassMetavarValue(require_value(location, "NativeStencilValueLocationClass")) end
    function api.passthrough_int_count_metavar_value(count) return Native.NativeStencilPassthroughIntCountMetavarValue(require_value(count, "integer passthrough count")) end
    function api.passthrough_float_count_metavar_value(count) return Native.NativeStencilPassthroughFloatCountMetavarValue(require_value(count, "float passthrough count")) end
    function api.control_shape_metavar_value(shape) return Native.NativeStencilControlShapeMetavarValue(require_value(shape, "NativeStencilControlShape")) end
    function api.code_inst_metavar_value(axis) return Native.NativeStencilCodeInstMetavarValue(require_value(axis, "NativeCodeInstAxis")) end
    function api.code_term_metavar_value(axis) return Native.NativeStencilCodeTermMetavarValue(require_value(axis, "NativeCodeTermAxis")) end
    function api.kernel_metavar_value(axis) return Native.NativeStencilKernelMetavarValue(require_value(axis, "NativeKernelAxis")) end
    function api.stencil_producer_metavar_value(axis) return Native.NativeStencilProducerMetavarValue(require_value(axis, "NativeStencilProducerAxis")) end
    function api.stencil_access_metavar_value(axis) return Native.NativeStencilAccessMetavarValue(require_value(axis, "NativeStencilAccessAxis")) end
    function api.stencil_point_metavar_value(axis) return Native.NativeStencilPointMetavarValue(require_value(axis, "NativeStencilPointAxis")) end
    function api.stencil_sink_metavar_value(axis) return Native.NativeStencilSinkMetavarValue(require_value(axis, "NativeStencilSinkAxis")) end
    function api.stencil_schedule_metavar_value(axis) return Native.NativeStencilScheduleMetavarValue(require_value(axis, "NativeStencilScheduleAxis")) end

    local function metavar_id_of(metavar_or_id)
        if asdl.isa(metavar_or_id, Native.NativeStencilMetavarId) then return metavar_or_id end
        if asdl.isa(metavar_or_id, Native.NativeStencilMetavar) then return metavar_or_id.id end
        return require_value(metavar_or_id, "NativeStencilMetavar or NativeStencilMetavarId")
    end

    function api.metavar_binding(metavar_or_id, value)
        return Native.NativeStencilMetavarBinding(
            metavar_id_of(metavar_or_id),
            require_value(value, "NativeStencilMetavarValue")
        )
    end

    function api.stencil_generator(id, owner_family, chunk_class, metavars)
        return Native.NativeStencilGenerator(
            require_value(id, "NativeStencilGeneratorId"),
            require_value(owner_family, "NativeTemplateFamily"),
            require_value(chunk_class, "NativeTemplateChunkClass"),
            metavars or {}
        )
    end

    local function generator_id_of(generator_or_id)
        if asdl.isa(generator_or_id, Native.NativeStencilGeneratorId) then return generator_or_id end
        if asdl.isa(generator_or_id, Native.NativeStencilGenerator) then return generator_or_id.id end
        return require_value(generator_or_id, "NativeStencilGenerator or NativeStencilGeneratorId")
    end

    function api.stencil_configuration(id, generator_or_id, bindings)
        return Native.NativeStencilConfiguration(
            require_value(id, "NativeStencilConfigurationId"),
            generator_id_of(generator_or_id),
            bindings or {}
        )
    end

    function api.template_manifest_entry(source, family, generator, configuration, signature, extraction, hole_ordinals, continuation_ordinals, relocation_kinds)
        return Native.NativeTemplateManifestEntry(
            require_value(source, "NativeTemplateId"),
            require_value(family, "NativeTemplateFamily"),
            require_value(generator, "NativeStencilGenerator"),
            require_value(configuration, "NativeStencilConfiguration"),
            require_value(signature, "NativeStencilSignature"),
            require_value(extraction, "NativeTemplateExtraction"),
            hole_ordinals or {},
            continuation_ordinals or {},
            relocation_kinds or {}
        )
    end

    function api.template_manifest_entry_for_source(source)
        source = require_value(source, "NativeTemplateSource")
        return api.template_manifest_entry(
            source.id,
            source.family,
            source.generator,
            source.configuration,
            source.signature,
            source.extraction,
            source.declared_hole_ordinals,
            source.declared_continuation_ordinals,
            source.declared_relocation_kinds
        )
    end

    function api.template_manifest_group(generator, entries)
        entries = entries or {}
        return Native.NativeTemplateManifestGroup(
            require_value(generator, "NativeStencilGenerator"),
            generator.chunk_class,
            entries,
            #entries
        )
    end

    local function support_domain_id_of(domain_or_id)
        if asdl.isa(domain_or_id, Native.NativeTemplateSupportDomainId) then return domain_or_id end
        if asdl.isa(domain_or_id, Native.NativeTemplateSupportDomain) then return domain_or_id.id end
        return require_value(domain_or_id, "NativeTemplateSupportDomain or NativeTemplateSupportDomainId")
    end

    function api.template_source_manifest(id, support_domain_or_id, groups)
        groups = groups or {}
        local total = 0
        for _, group in ipairs(groups) do total = total + group.total_count end
        return Native.NativeTemplateSourceManifest(
            require_value(id, "NativeTemplateManifestId"),
            support_domain_id_of(support_domain_or_id),
            groups,
            total
        )
    end

    function api.family_id(text)
        return Native.NativeTemplateFamilyId(require_value(text, "family id text"))
    end

    function api.runtime_call_family_id(name)
        return api.family_id("native.runtime_call." .. require_value(name, "runtime call family name"))
    end

    function api.code_func_family_id(name)
        return api.family_id("native.code.func." .. require_value(name, "code function family name"))
    end

    function api.code_block_family_id(name)
        return api.family_id("native.code.block." .. require_value(name, "code block family name"))
    end

    function api.code_inst_family_id(name)
        return api.family_id("native.code.inst." .. require_value(name, "code instruction family name"))
    end

    function api.code_term_family_id(name)
        return api.family_id("native.code.term." .. require_value(name, "code terminator family name"))
    end

    function api.code_const_family_id(name)
        return api.family_id("native.code.const." .. require_value(name, "code constant family name"))
    end

    function api.stencil_family_id(name)
        return api.family_id("native.stencil." .. require_value(name, "stencil family name"))
    end

    function api.kernel_family_id(name)
        return api.family_id("native.kernel." .. require_value(name, "kernel family name"))
    end

    function api.family(id, role, axes, protocol)
        return Native.NativeTemplateFamily(
            require_value(id, "NativeTemplateFamilyId"),
            require_value(role, "NativeTemplateRole"),
            axes or {},
            require_value(protocol, "NativeTemplateProtocol")
        )
    end

    function api.family_axes_for_scalar(target, scalar, extra_axes)
        local axes = {
            api.axis_target(require_value(target, "NativeTarget")),
            api.axis_machine_scalar(require_value(scalar, "NativeMachineScalarRep")),
            api.axis_register_class(scalar:native_register_class()),
        }
        for _, axis in ipairs(extra_axes or {}) do axes[#axes + 1] = axis end
        return axes
    end

    function api.frame_family_axes_for_scalar(target, scalar, extra_axes)
        local axes = {
            api.axis_target(require_value(target, "NativeTarget")),
            api.axis_machine_scalar(require_value(scalar, "NativeMachineScalarRep")),
        }
        for _, axis in ipairs(extra_axes or {}) do axes[#axes + 1] = axis end
        return axes
    end

    function api.runtime_call_family(name, target, protocol)
        return api.family(
            api.runtime_call_family_id(name),
            Native.NativeRoleRuntimeCall,
            { api.axis_target(require_value(target, "NativeTarget")) },
            require_value(protocol, "NativeTemplateProtocol")
        )
    end

    function api.runtime_call_scalar_family(name, target, scalar)
        return api.family(
            api.runtime_call_family_id(name),
            Native.NativeRoleRuntimeCall,
            api.family_axes_for_scalar(target, scalar),
            api.protocol_for_scalar(scalar)
        )
    end

    function api.code_func_family(name, target, axis_or_scalar, protocol)
        local axes
        if axis_or_scalar ~= nil and asdl.isa(axis_or_scalar, Native.NativeMachineScalarRep) then
            axes = api.family_axes_for_scalar(target, axis_or_scalar)
            protocol = protocol or api.protocol_for_scalar(axis_or_scalar)
        else
            axes = {
                api.axis_target(require_value(target, "NativeTarget")),
            }
        end
        return api.family(
            api.code_func_family_id(name),
            Native.NativeRoleCodeFunc,
            axes,
            require_value(protocol, "NativeTemplateProtocol")
        )
    end

    function api.code_block_family(name, target, axis_or_scalar, protocol)
        local axes
        if axis_or_scalar ~= nil and asdl.isa(axis_or_scalar, Native.NativeMachineScalarRep) then
            axes = api.family_axes_for_scalar(target, axis_or_scalar)
            protocol = protocol or api.protocol_for_scalar(axis_or_scalar)
        else
            axes = {
                api.axis_target(require_value(target, "NativeTarget")),
            }
        end
        return api.family(
            api.code_block_family_id(name),
            Native.NativeRoleCodeBlock,
            axes,
            require_value(protocol, "NativeTemplateProtocol")
        )
    end

    function api.code_inst_family(name, target, axis, protocol)
        return api.family(
            api.code_inst_family_id(name),
            Native.NativeRoleCodeInst,
            {
                api.axis_target(require_value(target, "NativeTarget")),
                api.axis_code_inst(require_value(axis, "NativeCodeInstAxis")),
            },
            require_value(protocol, "NativeTemplateProtocol")
        )
    end

    function api.code_inst_scalar_family(name, target, scalar, axis)
        return api.family(
            api.code_inst_family_id(name),
            Native.NativeRoleCodeInst,
            api.family_axes_for_scalar(target, scalar, { api.axis_code_inst(require_value(axis, "NativeCodeInstAxis")) }),
            api.protocol_for_scalar(scalar)
        )
    end

    function api.code_inst_frame_family(name, target, scalar, axis)
        return api.family(
            api.code_inst_family_id(name),
            Native.NativeRoleCodeInst,
            api.frame_family_axes_for_scalar(target, scalar, { api.axis_code_inst(require_value(axis, "NativeCodeInstAxis")) }),
            api.protocol_void_none()
        )
    end

    function api.code_term_family(name, target, axis, protocol)
        return api.family(
            api.code_term_family_id(name),
            Native.NativeRoleCodeTerm,
            {
                api.axis_target(require_value(target, "NativeTarget")),
                api.axis_code_term(require_value(axis, "NativeCodeTermAxis")),
            },
            require_value(protocol, "NativeTemplateProtocol")
        )
    end

    function api.code_term_scalar_family(name, target, scalar, axis)
        return api.family(
            api.code_term_family_id(name),
            Native.NativeRoleCodeTerm,
            api.family_axes_for_scalar(target, scalar, { api.axis_code_term(require_value(axis, "NativeCodeTermAxis")) }),
            api.protocol_for_scalar(scalar)
        )
    end

    function api.code_term_frame_family(name, target, scalar, axis)
        return api.family(
            api.code_term_family_id(name),
            Native.NativeRoleCodeTerm,
            api.frame_family_axes_for_scalar(target, scalar, { api.axis_code_term(require_value(axis, "NativeCodeTermAxis")) }),
            api.protocol_void_none()
        )
    end

    function api.code_const_family(name, target, axis, protocol)
        return api.family(
            api.code_const_family_id(name),
            Native.NativeRoleCodeConst,
            {
                api.axis_target(require_value(target, "NativeTarget")),
                api.axis_code_const(require_value(axis, "NativeCodeConstAxis")),
            },
            require_value(protocol, "NativeTemplateProtocol")
        )
    end

    function api.code_const_scalar_family(name, target, scalar, axis)
        return api.family(
            api.code_const_family_id(name),
            Native.NativeRoleCodeConst,
            api.family_axes_for_scalar(target, scalar, { api.axis_code_const(require_value(axis, "NativeCodeConstAxis")) }),
            api.protocol_for_scalar(scalar)
        )
    end

    function api.code_const_frame_family(name, target, scalar, axis)
        return api.family(
            api.code_const_family_id(name),
            Native.NativeRoleCodeConst,
            api.frame_family_axes_for_scalar(target, scalar, { api.axis_code_const(require_value(axis, "NativeCodeConstAxis")) }),
            api.protocol_void_none()
        )
    end

    function api.code_func_frame_family(name, target, param_scalar, result_scalar)
        return api.family(
            api.code_func_family_id(name),
            Native.NativeRoleCodeFunc,
            {
                api.axis_target(require_value(target, "NativeTarget")),
                api.axis_machine_scalar(require_value(param_scalar, "NativeMachineScalarRep")),
                api.axis_machine_scalar(require_value(result_scalar, "NativeMachineScalarRep")),
            },
            api.protocol_for_scalar_frame(result_scalar)
        )
    end

    local function host_arch()
        local f = require_ffi()
        if f.arch == "x64" then return Native.NativeArchX64, "x64" end
        if f.arch == "arm64" or f.arch == "aarch64" then return Native.NativeArchAArch64, "aarch64" end
        boundary_error("host architecture is not represented by LalinNative: " .. tostring(f.arch))
    end

    local function host_os()
        local f = require_ffi()
        if f.os == "Linux" then return Native.NativeOsLinux, "linux" end
        if f.os == "OSX" then return Native.NativeOsDarwin, "darwin" end
        if f.os == "Windows" then return Native.NativeOsWindows, "windows" end
        boundary_error("host OS is not represented by LalinNative: " .. tostring(f.os))
    end

    local function host_abi(arch_key, os_key)
        if arch_key == "x64" and os_key == "windows" then return Native.NativeAbiWin64, "win64" end
        if arch_key == "x64" then return Native.NativeAbiSysV, "sysv" end
        if arch_key == "aarch64" then return Native.NativeAbiAapcs64, "aapcs64" end
        boundary_error("host ABI is not represented by LalinNative for " .. tostring(arch_key) .. "/" .. tostring(os_key))
    end

    local function host_endian()
        local f = require_ffi()
        if f.abi("le") then return Native.NativeLittleEndian, "le" end
        return Native.NativeBigEndian, "be"
    end

    local function host_pointer_bits()
        local f = require_ffi()
        return f.abi("64bit") and 64 or 32
    end

    function api.host_target()
        local arch, arch_key = host_arch()
        local os, os_key = host_os()
        local abi, abi_key = host_abi(arch_key, os_key)
        local endian, endian_key = host_endian()
        local pointer_bits = host_pointer_bits()
        return Native.NativeTarget(
            Native.NativeTargetId(table.concat({ "native-template-host", arch_key, os_key, abi_key, tostring(pointer_bits), endian_key }, "-")),
            arch,
            os,
            abi,
            pointer_bits,
            endian
        )
    end

    function api.empty_runtime()
        return Native.NativeRuntime({})
    end

    function api.scalar_machine_types()
        return {
            api.i8(), api.u8(), api.i16(), api.u16(),
            api.i32(), api.u32(), api.i64(), api.u64(),
            api.index(), api.data_ptr(nil), api.f32(), api.f64(),
        }
    end

    function api.host_scalar_reps()
        local pointer_bits = host_pointer_bits()
        return {
            api.scalar_bool8(),
            api.scalar_i8(), api.scalar_u8(), api.scalar_i16(), api.scalar_u16(),
            api.scalar_i32(), api.scalar_u32(), api.scalar_i64(), api.scalar_u64(),
            api.scalar_index(pointer_bits), api.scalar_pointer(pointer_bits),
            api.scalar_f32(), api.scalar_f64(),
        }
    end

    function api.scalar_i32_slice_types()
        return { api.i32() }
    end

    function api.supported_rank_1d()
        return { 1 }
    end

    function api.supported_scalar_lanes()
        return { 1 }
    end

    function api.supported_scalar_unroll_factors()
        return { 1 }
    end

    function api.atomic_gcc_builtins_support()
        return Native.NativeAtomicGccBuiltins
    end

    function api.support_domain(
        id,
        target,
        runtime,
        scalar_reps,
        public_abi_adapters,
        continuation_signatures,
        constant_pool_support,
        passthrough_int_limit,
        passthrough_float_limit,
        frame_stack_limit,
        atomic_codegen
    )
        target = require_value(target, "NativeTarget")
        runtime = require_value(runtime, "NativeRuntime")
        scalar_reps = scalar_reps or {}
        public_abi_adapters = api.public_abi_adapter_support(public_abi_adapters)
        continuation_signatures = continuation_signatures or {}
        constant_pool_support = constant_pool_support or api.empty_constant_pool_support()
        passthrough_int_limit = passthrough_int_limit or api.spill_all_passthrough_int_limit()
        passthrough_float_limit = passthrough_float_limit or api.spill_all_passthrough_float_limit()
        frame_stack_limit = frame_stack_limit or api.x64_sysv_frame_stack_limit()
        atomic_codegen = atomic_codegen or api.atomic_gcc_builtins_support()
        local scalar_supports = {}
        local register_supports = {}
        local abi = {}
        local call_protocols = { Native.NativeCallVoid }
        for _, scalar in ipairs(scalar_reps) do
            scalar_supports[#scalar_supports + 1] = api.scalar_support(scalar)
            for _, reg_support in ipairs(api.register_support(target, scalar)) do
                register_supports[#register_supports + 1] = reg_support
            end
            abi[#abi + 1] = api.abi_scalar_convention(target, scalar)
            call_protocols[#call_protocols + 1] = api.native_call_return_scalar(scalar)
        end
        return Native.NativeTemplateSupportDomain(
            require_value(id, "NativeTemplateSupportDomainId"),
            target,
            runtime,
            scalar_supports,
            register_supports,
            abi,
            call_protocols,
            { api.register_none() },
            { Native.NativeScratchGeneral, Native.NativeScratchInteger, Native.NativeScratchFloat, Native.NativeScratchAddress },
            { Native.NativeAccumulatorGeneral, Native.NativeAccumulatorInteger, Native.NativeAccumulatorFloat },
            api.supported_scalar_lanes(),
            api.supported_rank_1d(),
            api.supported_scalar_unroll_factors(),
            passthrough_int_limit,
            passthrough_float_limit,
            frame_stack_limit,
            public_abi_adapters,
            continuation_signatures,
            constant_pool_support,
            atomic_codegen
        )
    end

    function api.host_template_support_domain_id(name)
        return Native.NativeTemplateSupportDomainId("native.template.support.host." .. require_value(name, "support domain name"))
    end

    function api.host_scalar_support_domain()
        return api.support_domain(
            api.host_template_support_domain_id("scalar"),
            api.host_target(),
            api.empty_runtime(),
            api.host_scalar_reps()
        )
    end

    function api.host_scalar_i32_support_domain()
        return api.support_domain(
            api.host_template_support_domain_id("scalar-i32"),
            api.host_target(),
            api.empty_runtime(),
            { api.scalar_i32() }
        )
    end

    function api.host_scalar_i32_bank_id()
        return Native.NativeBankId("native.template.host.scalar-i32")
    end

    function api.bank_id_for_support_domain(domain)
        domain = require_value(domain, "NativeTemplateSupportDomain")
        return Native.NativeBankId("native.template.bank." .. domain.id.text)
    end

    T._lalin_api_cache.native_template_support = api
    return api
end

return bind_context
