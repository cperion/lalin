local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi then ffi = nil end

local U32 = 4294967296

local function require_ffi(operation)
    if ffi == nil then error("lalin.native: ffi is required for " .. operation, 3) end
    return ffi
end

local function write_u32_le(address, value)
    local f = require_ffi("native patch writes")
    local n = value % U32
    if n < 0 then n = n + U32 end
    local p = f.cast("uint8_t *", address)
    p[0] = n % 256
    n = math.floor(n / 256)
    p[1] = n % 256
    n = math.floor(n / 256)
    p[2] = n % 256
    n = math.floor(n / 256)
    p[3] = n % 256
end

local function write_u64_le(address, value)
    local f = require_ffi("native patch writes")
    local p = f.cast("uint8_t *", address)
    local u = f.new("uint64_t", value)
    local src = f.cast("uint8_t *", f.new("uint64_t[1]", u))
    for i = 0, 7 do p[i] = src[i] end
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native ~= nil then return T._lalin_api_cache.native end

    local Native = T.LalinNative
    local Code = T.LalinCode
    local api = {}

    local function patch_address(input)
        return input.base_address + input.layout.offset
    end

    local function value_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            if left[i] ~= right[i] then return false end
        end
        return true
    end

    local function axis_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            if not left[i]:native_axis_equals(right[i]) then return false end
        end
        return true
    end

    local function write_patch_u32(input, value)
        write_u32_le(patch_address(input), value)
        return nil
    end

    function Native.NativeCompileRequest:compile_native()
        local plan = self.subject:plan_native_copy(Native.NativePlanInput(self.target, self.runtime, self.bank))
        local copy_plan = plan:select_native_copy_plan(Native.NativeCopyPlanSelectionInput(self.target, self.runtime))
        local install = copy_plan:install_native(Native.NativeInstallInput(self.target, self.runtime, Native.NativeExecutableAllocatorMmap))
        return install:compile_native_result()
    end

    function Native.NativeCompileCodeModule:plan_native_copy(input)
        return self.module:plan_native_copy(input)
    end

    function Native.NativeCompileCodeFunc:plan_native_copy(input)
        return self.func:plan_native_copy(input)
    end

    function Native.NativeCompileKernelPlan:plan_native_copy(input)
        return self.plan:plan_native_copy(input)
    end

    function Native.NativeCompileStencilInstance:plan_native_copy(input)
        return self.instance:plan_native_copy(input)
    end

    function Native.NativeInstallSucceeded:compile_native_result()
        return Native.NativeCompileResult(self.executable)
    end

    function Native.NativeTemplateBank:select_native_template(input)
        return Native.NativeTemplateSelectionRejected({
            Native.NativeSelectionRejectMissingBankEntry(input.family),
        })
    end

    function Native.NativeTemplateBankEntry:select_native_template(input)
        if self.compiled.target ~= input.target then
            return Native.NativeTemplateSelectionRejected({
                Native.NativeSelectionRejectTargetMismatch(input.target, self.compiled.target),
            })
        end
        if not self.family:native_family_equals(input.family) then
            return Native.NativeTemplateSelectionRejected({
                Native.NativeSelectionRejectFamilyMismatch(input.family, self.family),
            })
        end
        return Native.NativeTemplateSelected(self)
    end

    function Native.NativeTemplateFamily:native_family_equals(other)
        return other ~= nil
            and self.id == other.id
            and self.role == other.role
            and self.protocol:native_protocol_equals(other.protocol)
            and axis_list_equals(self.axes, other.axes)
    end

    function Native.NativeTemplateProtocol:native_protocol_equals(other)
        return other ~= nil
            and self.call:native_call_protocol_equals(other.call)
            and self.registers:native_register_protocol_equals(other.registers)
    end

    function Native.NativeCallProtocol:native_call_protocol_equals(other)
        return self == other
    end

    function Native.NativeRegisterProtocol:native_register_protocol_equals(other)
        return self == other
    end

    function Native.NativeTemplateAxis:native_axis_equals(_other)
        return false
    end

    function Native.NativeAxisTarget:native_axis_equals(other)
        return other:native_axis_equals_target(self.target)
    end

    function Native.NativeTemplateAxis:native_axis_equals_target(_target)
        return false
    end

    function Native.NativeAxisTarget:native_axis_equals_target(target)
        return self.target == target
    end

    function Native.NativeAxisRegisterProtocol:native_axis_equals(other)
        return other:native_axis_equals_register_protocol(self.protocol)
    end

    function Native.NativeTemplateAxis:native_axis_equals_register_protocol(_protocol)
        return false
    end

    function Native.NativeAxisRegisterProtocol:native_axis_equals_register_protocol(protocol)
        return self.protocol:native_register_protocol_equals(protocol)
    end

    function Native.NativeAxisMachineScalar:native_axis_equals(other)
        return other:native_axis_equals_machine_scalar(self.scalar)
    end

    function Native.NativeTemplateAxis:native_axis_equals_machine_scalar(_scalar)
        return false
    end

    function Native.NativeAxisMachineScalar:native_axis_equals_machine_scalar(scalar)
        return self.scalar == scalar
    end

    function Native.NativeAxisRegisterClass:native_axis_equals(other)
        return other:native_axis_equals_register_class(self.class)
    end

    function Native.NativeTemplateAxis:native_axis_equals_register_class(_class)
        return false
    end

    function Native.NativeAxisRegisterClass:native_axis_equals_register_class(class)
        return self.class == class
    end

    function Native.NativeAxisValuePlacement:native_axis_equals(other)
        return other:native_axis_equals_value_placement(self.placement)
    end

    function Native.NativeTemplateAxis:native_axis_equals_value_placement(_placement)
        return false
    end

    function Native.NativeAxisValuePlacement:native_axis_equals_value_placement(placement)
        return self.placement == placement
    end

    function Native.NativeAxisAbiParam:native_axis_equals(other)
        return other:native_axis_equals_abi_param(self.placement)
    end

    function Native.NativeTemplateAxis:native_axis_equals_abi_param(_placement)
        return false
    end

    function Native.NativeAxisAbiParam:native_axis_equals_abi_param(placement)
        return self.placement == placement
    end

    function Native.NativeAxisAbiResult:native_axis_equals(other)
        return other:native_axis_equals_abi_result(self.placement)
    end

    function Native.NativeTemplateAxis:native_axis_equals_abi_result(_placement)
        return false
    end

    function Native.NativeAxisAbiResult:native_axis_equals_abi_result(placement)
        return self.placement == placement
    end

    function Native.NativeAxisCodeInst:native_axis_equals(other)
        return other:native_axis_equals_code_inst(self.axis)
    end

    function Native.NativeTemplateAxis:native_axis_equals_code_inst(_axis)
        return false
    end

    function Native.NativeAxisCodeInst:native_axis_equals_code_inst(axis)
        return self.axis:native_code_inst_axis_equals(axis)
    end

    function Native.NativeAxisCodeTerm:native_axis_equals(other)
        return other:native_axis_equals_code_term(self.axis)
    end

    function Native.NativeTemplateAxis:native_axis_equals_code_term(_axis)
        return false
    end

    function Native.NativeAxisCodeTerm:native_axis_equals_code_term(axis)
        return self.axis:native_code_term_axis_equals(axis)
    end

    function Native.NativeAxisCodeConst:native_axis_equals(other)
        return other:native_axis_equals_code_const(self.axis)
    end

    function Native.NativeTemplateAxis:native_axis_equals_code_const(_axis)
        return false
    end

    function Native.NativeAxisCodeConst:native_axis_equals_code_const(axis)
        return self.axis:native_code_const_axis_equals(axis)
    end

    function Native.NativeCodeInstAxis:native_code_inst_axis_equals(_other)
        return false
    end

    function Native.NativeCodeInstAliasAxis:native_code_inst_axis_equals(other)
        return other:native_code_inst_alias_axis_equals(self.ty)
    end

    function Native.NativeCodeInstAxis:native_code_inst_alias_axis_equals(_ty)
        return false
    end

    function Native.NativeCodeInstAliasAxis:native_code_inst_alias_axis_equals(ty)
        return self.ty == ty
    end

    function Native.NativeCodeInstUnaryAxis:native_code_inst_axis_equals(other)
        return other:native_code_inst_unary_axis_equals(self.op, self.ty)
    end

    function Native.NativeCodeInstAxis:native_code_inst_unary_axis_equals(_op, _ty)
        return false
    end

    function Native.NativeCodeInstUnaryAxis:native_code_inst_unary_axis_equals(op, ty)
        return self.op == op and self.ty == ty
    end

    function Native.NativeCodeInstBinaryAxis:native_code_inst_axis_equals(other)
        return other:native_code_inst_binary_axis_equals(self.op, self.ty, self.semantics)
    end

    function Native.NativeCodeInstAxis:native_code_inst_binary_axis_equals(_op, _ty, _semantics)
        return false
    end

    function Native.NativeCodeInstBinaryAxis:native_code_inst_binary_axis_equals(op, ty, semantics)
        return self.op == op and self.ty == ty and self.semantics == semantics
    end

    function Native.NativeCodeInstFloatBinaryAxis:native_code_inst_axis_equals(other)
        return other:native_code_inst_float_binary_axis_equals(self.op, self.ty, self.mode)
    end

    function Native.NativeCodeInstAxis:native_code_inst_float_binary_axis_equals(_op, _ty, _mode)
        return false
    end

    function Native.NativeCodeInstFloatBinaryAxis:native_code_inst_float_binary_axis_equals(op, ty, mode)
        return self.op == op and self.ty == ty and self.mode == mode
    end

    function Native.NativeCodeInstCompareAxis:native_code_inst_axis_equals(other)
        return other:native_code_inst_compare_axis_equals(self.cmp, self.operand_ty)
    end

    function Native.NativeCodeInstAxis:native_code_inst_compare_axis_equals(_cmp, _operand_ty)
        return false
    end

    function Native.NativeCodeInstCompareAxis:native_code_inst_compare_axis_equals(cmp, operand_ty)
        return self.cmp == cmp and self.operand_ty == operand_ty
    end

    function Native.NativeCodeTermAxis:native_code_term_axis_equals(_other)
        return false
    end

    function Native.NativeCodeTermReturnAxis:native_code_term_axis_equals(other)
        return other:native_code_term_return_axis_equals(self.results)
    end

    function Native.NativeCodeTermAxis:native_code_term_return_axis_equals(_results)
        return false
    end

    function Native.NativeCodeTermReturnAxis:native_code_term_return_axis_equals(results)
        return value_list_equals(self.results, results)
    end

    function Native.NativeCodeConstAxis:native_code_const_axis_equals(_other)
        return false
    end

    function Native.NativeCodeConstLiteralAxis:native_code_const_axis_equals(other)
        return other:native_code_const_literal_axis_equals(self.ty)
    end

    function Native.NativeCodeConstAxis:native_code_const_literal_axis_equals(_ty)
        return false
    end

    function Native.NativeCodeConstLiteralAxis:native_code_const_literal_axis_equals(ty)
        return self.ty == ty
    end

    function Native.NativePatchImm32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_imm32(input)
    end

    function Native.NativePatchFieldOffset32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_imm32(input)
    end

    function Native.NativePatchComponentIndex32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_imm32(input)
    end

    function Native.NativePatchStride32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_imm32(input)
    end

    function Native.NativePatchFrameOffset32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_imm32(input)
    end

    function Native.NativePatchFrameSize32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_imm32(input)
    end

    function Native.NativePatchImm64:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_imm64(input)
    end

    function Native.NativePatchCoordinate:write_native_patch_imm32(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self)
    end

    function Native.NativePatchImmediateI32:write_native_patch_imm32(input)
        return write_patch_u32(input, self.value)
    end

    function Native.NativePatchFieldOffset:write_native_patch_imm32(input)
        return write_patch_u32(input, self.offset)
    end

    function Native.NativePatchComponentIndex:write_native_patch_imm32(input)
        return write_patch_u32(input, self.component_index)
    end

    function Native.NativePatchStride:write_native_patch_imm32(input)
        return write_patch_u32(input, self.stride)
    end

    function Native.NativePatchWindowOffset:write_native_patch_imm32(input)
        return write_patch_u32(input, self.offset)
    end

    function Native.NativePatchFrameOffset:write_native_patch_imm32(input)
        return write_patch_u32(input, self.offset)
    end

    function Native.NativePatchFrameSize:write_native_patch_imm32(input)
        return write_patch_u32(input, self.size)
    end

    function Native.NativePatchCoordinate:write_native_patch_imm64(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self)
    end

    function Native.NativePatchImmediateI64:write_native_patch_imm64(input)
        write_u64_le(patch_address(input), self.value)
        return nil
    end

    function Native.NativeCallVoid:call_native_executable(input)
        local f = require_ffi("native executable calls")
        local fn = f.cast("void (*)()", input.executable.entry_address)
        fn()
        return Native.NativeCallReturnedVoid
    end

    function Native.NativeCallReturnI32:call_native_executable(input)
        local f = require_ffi("native executable calls")
        local fn = f.cast("int32_t (*)()", input.executable.entry_address)
        return Native.NativeCallReturnedI32(tonumber(fn()))
    end

    function Native.NativeCallReturnI64:call_native_executable(input)
        local f = require_ffi("native executable calls")
        local fn = f.cast("int64_t (*)()", input.executable.entry_address)
        return Native.NativeCallReturnedI64(tonumber(fn()))
    end

    function Native.NativeCallReturnF64:call_native_executable(input)
        local f = require_ffi("native executable calls")
        local fn = f.cast("double (*)()", input.executable.entry_address)
        return Native.NativeCallReturnedF64(tonumber(fn()))
    end

    function Native.NativeCallReturnScalar:call_native_executable(input)
        return self.scalar:call_native_executable_scalar(input)
    end

    function Native.NativeCallArg:native_arg_i32()
        error("lalin.native: call argument is not an i32-compatible scalar", 3)
    end

    function Native.NativeCallArg:native_arg_i64()
        error("lalin.native: call argument is not an i64-compatible scalar", 3)
    end

    function Native.NativeCallArg:native_arg_f64()
        error("lalin.native: call argument is not an f64-compatible scalar", 3)
    end

    function Native.NativeCallArgI32:native_arg_i32() return self.value end
    function Native.NativeCallArgI32:native_arg_i64() return self.value end
    function Native.NativeCallArgI64:native_arg_i64() return self.value end
    function Native.NativeCallArgF64:native_arg_f64() return self.value end
    function Native.NativeCallArgPtr:native_arg_i64() return self.address end

    local function call_i32(input, c_result, c_arg)
        local f = require_ffi("native executable calls")
        c_arg = c_arg or "int32_t"
        if #(input.args or {}) == 0 then
            local fn = f.cast(c_result .. " (*)()", input.executable.entry_address)
            return tonumber(fn())
        end
        if #(input.args or {}) == 1 then
            local fn = f.cast(c_result .. " (*)(" .. c_arg .. ")", input.executable.entry_address)
            return tonumber(fn(input.args[1]:native_arg_i32()))
        end
        local fn = f.cast(c_result .. " (*)(" .. c_arg .. ", " .. c_arg .. ")", input.executable.entry_address)
        return tonumber(fn(input.args[1]:native_arg_i32(), input.args[2]:native_arg_i32()))
    end

    local function call_i64(input, c_result)
        local f = require_ffi("native executable calls")
        if #(input.args or {}) == 0 then
            local fn = f.cast(c_result .. " (*)()", input.executable.entry_address)
            return tonumber(fn())
        end
        if #(input.args or {}) == 1 then
            local fn = f.cast(c_result .. " (*)(int64_t)", input.executable.entry_address)
            return tonumber(fn(input.args[1]:native_arg_i64()))
        end
        local fn = f.cast(c_result .. " (*)(int64_t, int64_t)", input.executable.entry_address)
        return tonumber(fn(input.args[1]:native_arg_i64(), input.args[2]:native_arg_i64()))
    end

    local function call_f32(input, c_result)
        local f = require_ffi("native executable calls")
        if #(input.args or {}) == 0 then
            local fn = f.cast(c_result .. " (*)()", input.executable.entry_address)
            return tonumber(fn())
        end
        if #(input.args or {}) == 1 then
            local fn = f.cast(c_result .. " (*)(float)", input.executable.entry_address)
            return tonumber(fn(input.args[1]:native_arg_f64()))
        end
        local fn = f.cast(c_result .. " (*)(float, float)", input.executable.entry_address)
        return tonumber(fn(input.args[1]:native_arg_f64(), input.args[2]:native_arg_f64()))
    end

    local function call_f64(input, c_result)
        local f = require_ffi("native executable calls")
        if #(input.args or {}) == 0 then
            local fn = f.cast(c_result .. " (*)()", input.executable.entry_address)
            return tonumber(fn())
        end
        if #(input.args or {}) == 1 then
            local fn = f.cast(c_result .. " (*)(double)", input.executable.entry_address)
            return tonumber(fn(input.args[1]:native_arg_f64()))
        end
        local fn = f.cast(c_result .. " (*)(double, double)", input.executable.entry_address)
        return tonumber(fn(input.args[1]:native_arg_f64(), input.args[2]:native_arg_f64()))
    end

    function Native.NativeScalarBool8:call_native_executable_scalar(input)
        return Native.NativeCallReturnedI32(call_i32(input, "uint8_t", "uint8_t"))
    end

    function Native.NativeScalarInt:call_native_executable_scalar(input)
        local prefix = self.signedness == Code.CodeSigned and "int" or "uint"
        local c_type = prefix .. tostring(self.bits) .. "_t"
        if self.bits > 32 then return Native.NativeCallReturnedI64(call_i64(input, c_type)) end
        return Native.NativeCallReturnedI32(call_i32(input, c_type, c_type))
    end

    function Native.NativeScalarIndex:call_native_executable_scalar(input)
        return Native.NativeCallReturnedI64(call_i64(input, "int64_t"))
    end

    function Native.NativeScalarPointer:call_native_executable_scalar(input)
        return Native.NativeCallReturnedI64(call_i64(input, "uint64_t"))
    end

    function Native.NativeScalarFloat:call_native_executable_scalar(input)
        if self.bits == 32 then return Native.NativeCallReturnedF64(call_f32(input, "float")) end
        return Native.NativeCallReturnedF64(call_f64(input, "double"))
    end

    function api.write_u32_le(address, value)
        return write_u32_le(address, value)
    end

    function api.write_u64_le(address, value)
        return write_u64_le(address, value)
    end

    T._lalin_api_cache.native = api
    return api
end

return bind_context
