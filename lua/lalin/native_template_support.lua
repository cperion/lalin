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

    -- This module constructs ASDL support-domain facts for NativeTemplateSource
    -- construction. Unbounded program values remain NativePatchCoordinate values,
    -- ABI parameters, or graph edges; they are not bank-domain dimensions.

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
    function api.native_call_code_sig(sig) return Native.NativeCallCodeSig(require_value(sig, "CodeSig")) end
    function api.native_call_stencil_abi(abi) return Native.NativeCallStencilAbi(require_value(abi, "StencilAbi")) end

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
            api.axis_register_protocol(api.register_x64_sysv()),
        }
        for _, axis in ipairs(extra_axes or {}) do axes[#axes + 1] = axis end
        return axes
    end

    function api.frame_family_axes_for_scalar(target, scalar, extra_axes)
        local axes = {
            api.axis_target(require_value(target, "NativeTarget")),
            api.axis_machine_scalar(require_value(scalar, "NativeMachineScalarRep")),
            api.axis_register_protocol(api.register_none()),
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
                api.axis_register_protocol(api.register_x64_sysv()),
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
                api.axis_register_protocol(api.register_x64_sysv()),
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
                api.axis_register_protocol(api.register_none()),
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

    function api.support_domain(id, target, runtime, scalar_reps)
        target = require_value(target, "NativeTarget")
        runtime = require_value(runtime, "NativeRuntime")
        scalar_reps = scalar_reps or {}
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
            { api.register_x64_sysv() },
            { Native.NativeScratchGeneral, Native.NativeScratchInteger, Native.NativeScratchFloat, Native.NativeScratchAddress },
            { Native.NativeAccumulatorGeneral, Native.NativeAccumulatorInteger, Native.NativeAccumulatorFloat },
            api.supported_scalar_lanes(),
            api.supported_rank_1d(),
            api.supported_scalar_unroll_factors()
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
