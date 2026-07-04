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

    local function write_patch_u64(input, value)
        write_u64_le(patch_address(input), value)
        return nil
    end

    local function write_patch_rel32(input, target_address, addend)
        local address = patch_address(input)
        write_u32_le(address, target_address + (addend or 0) - address)
        return nil
    end

    local function constant_pool_entry_address(input, entry_id)
        for _, entry in ipairs((input.constant_pool_layout and input.constant_pool_layout.entries) or {}) do
            if entry.entry.id == entry_id then return input.base_address + entry.offset end
        end
        return nil
    end

    local function runtime_symbol(input, symbol_id)
        for _, symbol in ipairs((input.runtime and input.runtime.symbols) or {}) do
            if symbol.id == symbol_id then return symbol end
        end
        return nil
    end

    local function code_layout_node_offset(input, node_id)
        for _, layout in ipairs((input.code_layout and input.code_layout.nodes) or {}) do
            if layout.node == node_id then return layout.offset end
        end
    end

    local function bank_symbol_address(input, symbol_name)
        for _, node in ipairs((input.graph and input.graph.nodes) or {}) do
            local node_offset = code_layout_node_offset(input, node.id)
            if node_offset ~= nil then
                for _, symbol in ipairs((node.entry.compiled and node.entry.compiled.symbols) or {}) do
                    if symbol.name == symbol_name then return input.base_address + node_offset + symbol.offset end
                end
            end
        end
    end

    local function module_address_entry(entries, key_name, key)
        for _, entry in ipairs(entries or {}) do
            if entry[key_name] == key then return entry end
        end
    end

    function Native.NativeCodeAddressCapability:native_code_address(_input)
        return nil
    end

    function Native.NativeCodeAddressBankSymbol:native_code_address(input)
        return bank_symbol_address(input, self.symbol_name)
    end

    function Native.NativeCodeAddressFunctionEntry:native_code_address(input)
        return bank_symbol_address(input, self.symbol_name)
    end

    function Native.NativeCodeAddressRuntimeSymbol:native_code_address(input)
        local symbol = runtime_symbol(input, self.symbol)
        return symbol and symbol.address and symbol.address:native_runtime_address() or nil
    end

    function Native.NativeCodeAddressConstantPoolEntry:native_code_address(input)
        return constant_pool_entry_address(input, self.entry)
    end

    function Native.NativeCodeAddressPatchable:native_code_address(input)
        return self.coordinate:native_patch_coordinate_address(input)
    end

    function Native.NativeCodeAddressFrameSlot:native_code_address(_input)
        return nil
    end

    function Native.NativeCodeAddressFrameSlotOffset:native_code_address(_input)
        return nil
    end

    function Native.NativeCodeAddressValueOffset:native_code_address(_input)
        return nil
    end

    function Native.NativeCodeAddressPlaceOffset:native_code_address(_input)
        return nil
    end

    function Native.NativeCodeAddressPlaceIndexOffset:native_code_address(_input)
        return nil
    end

    function Native.NativePatchCoordinate:native_patch_coordinate_address(_input)
        return nil
    end

    function Native.NativePatchPointer64:native_patch_coordinate_address(_input)
        return self.address
    end

    function Native.NativePatchConstantPoolEntry:native_patch_coordinate_address(input)
        return constant_pool_entry_address(input, self.entry)
    end

    function Native.NativePatchCallTarget:native_patch_coordinate_address(input)
        local symbol = runtime_symbol(input, self.symbol)
        return symbol and symbol.address and symbol.address:native_runtime_address() or nil
    end

    function Native.NativePatchCodeDataAddress:native_module_address_projection(input)
        local entry = module_address_entry(input.module_addresses and input.module_addresses.data, "data", self.data)
        return entry and entry.projection or nil
    end

    function Native.NativePatchCodeGlobalAddress:native_module_address_projection(input)
        local entry = module_address_entry(input.module_addresses and input.module_addresses.globals, "global", self.global)
        return entry and entry.projection or nil
    end

    function Native.NativePatchCodeFuncAddress:native_module_address_projection(input)
        local entry = module_address_entry(input.module_addresses and input.module_addresses.funcs, "func", self.func)
        return entry and entry.projection or nil
    end

    function Native.NativePatchCodeExternAddress:native_module_address_projection(input)
        local entry = module_address_entry(input.module_addresses and input.module_addresses.externs, "extern", self.extern)
        return entry and entry.projection or nil
    end

    function Native.NativePatchCoordinate:native_module_address_projection(_input)
        return nil
    end

    local function module_patch_coordinate_address(input, coordinate)
        local projection = coordinate:native_module_address_projection(input)
        if projection == nil then return nil end
        return projection.capability:native_code_address(input)
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
        return self.func:plan_native_copy(input, nil, self.signature)
    end

    function Native.NativeCompileKernelPlan:plan_native_copy(input)
        return self.plan:plan_native_copy(input, self.lowering)
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

    function Native.NativeCallProtocol:native_call_protocol_equals(_other)
        return false
    end

    function Native.NativeCallVoid:native_call_protocol_equals(other)
        return other:native_call_protocol_equals_void()
    end

    function Native.NativeCallProtocol:native_call_protocol_equals_void()
        return false
    end

    function Native.NativeCallVoid:native_call_protocol_equals_void()
        return true
    end

    function Native.NativeCallReturnI32:native_call_protocol_equals(other)
        return other:native_call_protocol_equals_return_i32()
    end

    function Native.NativeCallProtocol:native_call_protocol_equals_return_i32()
        return false
    end

    function Native.NativeCallReturnI32:native_call_protocol_equals_return_i32()
        return true
    end

    function Native.NativeCallReturnI64:native_call_protocol_equals(other)
        return other:native_call_protocol_equals_return_i64()
    end

    function Native.NativeCallProtocol:native_call_protocol_equals_return_i64()
        return false
    end

    function Native.NativeCallReturnI64:native_call_protocol_equals_return_i64()
        return true
    end

    function Native.NativeCallReturnF64:native_call_protocol_equals(other)
        return other:native_call_protocol_equals_return_f64()
    end

    function Native.NativeCallProtocol:native_call_protocol_equals_return_f64()
        return false
    end

    function Native.NativeCallReturnF64:native_call_protocol_equals_return_f64()
        return true
    end

    function Native.NativeCallReturnScalar:native_call_protocol_equals(other)
        return other:native_call_protocol_equals_return_scalar(self.scalar)
    end

    function Native.NativeCallProtocol:native_call_protocol_equals_return_scalar(_scalar)
        return false
    end

    function Native.NativeCallReturnScalar:native_call_protocol_equals_return_scalar(scalar)
        return self.scalar == scalar
    end

    function Native.NativeCallCodeSig:native_call_protocol_equals(other)
        return other:native_call_protocol_equals_code_sig(self.projection)
    end

    function Native.NativeCallProtocol:native_call_protocol_equals_code_sig(_projection)
        return false
    end

    function Native.NativeCallCodeSig:native_call_protocol_equals_code_sig(projection)
        return self.projection:native_abi_function_projection_equals(projection)
    end

    function Native.NativeCallStencilAbi:native_call_protocol_equals(other)
        return other:native_call_protocol_equals_stencil_abi(self.projection)
    end

    function Native.NativeCallProtocol:native_call_protocol_equals_stencil_abi(_projection)
        return false
    end

    function Native.NativeCallStencilAbi:native_call_protocol_equals_stencil_abi(projection)
        return self.projection:native_abi_function_projection_equals(projection)
    end

    function Native.NativeRegisterProtocol:native_register_protocol_equals(other)
        return self == other
    end

    local function abi_param_projection_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            if not left[i]:native_abi_param_projection_equals(right[i]) then return false end
        end
        return true
    end

    local function abi_descriptor_field_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            if not left[i]:native_abi_descriptor_field_equals(right[i]) then return false end
        end
        return true
    end

    function Native.NativeAbiFunctionProjection:native_abi_function_projection_equals(other)
        return other ~= nil
            and self.target == other.target
            and abi_param_projection_list_equals(self.params, other.params)
            and self.result:native_abi_result_projection_equals(other.result)
    end

    function Native.NativeAbiParamProjection:native_abi_param_projection_equals(other)
        return other ~= nil
            and self.param_index == other.param_index
            and self.source_ty == other.source_ty
            and self.abi:native_abi_projection_equals(other.abi)
    end

    function Native.NativeAbiResultProjection:native_abi_result_projection_equals(other)
        return other ~= nil
            and self.source_ty == other.source_ty
            and self.abi:native_abi_projection_equals(other.abi)
    end

    function Native.NativeAbiDescriptorField:native_abi_descriptor_field_equals(other)
        return other ~= nil
            and self.field_name == other.field_name
            and self.offset == other.offset
            and self.value:native_abi_projection_equals(other.value)
    end

    function Native.NativeAbiProjection:native_abi_projection_equals(_other)
        return false
    end

    function Native.NativeAbiVoidResult:native_abi_projection_equals(other)
        return other:native_abi_projection_equals_void_result()
    end

    function Native.NativeAbiProjection:native_abi_projection_equals_void_result()
        return false
    end

    function Native.NativeAbiVoidResult:native_abi_projection_equals_void_result()
        return true
    end

    function Native.NativeAbiScalarValue:native_abi_projection_equals(other)
        return other:native_abi_projection_equals_scalar_value(self.scalar, self.extension)
    end

    function Native.NativeAbiProjection:native_abi_projection_equals_scalar_value(_scalar, _extension)
        return false
    end

    function Native.NativeAbiScalarValue:native_abi_projection_equals_scalar_value(scalar, extension)
        return self.scalar == scalar and self.extension == extension
    end

    function Native.NativeAbiPointerValue:native_abi_projection_equals(other)
        return other:native_abi_projection_equals_pointer_value(self.scalar)
    end

    function Native.NativeAbiProjection:native_abi_projection_equals_pointer_value(_scalar)
        return false
    end

    function Native.NativeAbiPointerValue:native_abi_projection_equals_pointer_value(scalar)
        return self.scalar == scalar
    end

    function Native.NativeAbiDescriptorValue:native_abi_projection_equals(other)
        return other:native_abi_projection_equals_descriptor_value(self.layout, self.fields)
    end

    function Native.NativeAbiProjection:native_abi_projection_equals_descriptor_value(_layout, _fields)
        return false
    end

    function Native.NativeAbiDescriptorValue:native_abi_projection_equals_descriptor_value(layout, fields)
        return self.layout == layout and abi_descriptor_field_list_equals(self.fields, fields)
    end

    function Native.NativeAbiByRefValue:native_abi_projection_equals(other)
        return other:native_abi_projection_equals_byref_value(self.pointee_ty, self.mutability, self.alignment)
    end

    function Native.NativeAbiProjection:native_abi_projection_equals_byref_value(_pointee_ty, _mutability, _alignment)
        return false
    end

    function Native.NativeAbiByRefValue:native_abi_projection_equals_byref_value(pointee_ty, mutability, alignment)
        return self.pointee_ty == pointee_ty and self.mutability == mutability and self.alignment == alignment
    end

    function Native.NativeAbiSRetResult:native_abi_projection_equals(other)
        return other:native_abi_projection_equals_sret_result(self.result_ty, self.pointer_param)
    end

    function Native.NativeAbiProjection:native_abi_projection_equals_sret_result(_result_ty, _pointer_param)
        return false
    end

    function Native.NativeAbiSRetResult:native_abi_projection_equals_sret_result(result_ty, pointer_param)
        return self.result_ty == result_ty and self.pointer_param:native_abi_param_projection_equals(pointer_param)
    end

    function Native.NativeAbiProjection:native_code_result_shape()
        error("lalin.native: unsupported ABI projection result shape", 2)
    end

    function Native.NativeAbiVoidResult:native_code_result_shape()
        return Native.NativeCodeResultVoidShape
    end

    function Native.NativeAbiScalarValue:native_code_result_shape()
        return Native.NativeCodeResultScalarShape(self.scalar)
    end

    function Native.NativeAbiPointerValue:native_code_result_shape()
        return Native.NativeCodeResultPointerShape(self.scalar)
    end

    function Native.NativeAbiDescriptorValue:native_code_result_shape()
        return Native.NativeCodeResultDescriptorShape(self.layout)
    end

    function Native.NativeAbiByRefValue:native_code_result_shape()
        return Native.NativeCodeResultByRefShape(self.pointee_ty, self.mutability, self.alignment)
    end

    function Native.NativeAbiSRetResult:native_code_result_shape()
        return Native.NativeCodeResultSRetShape(self.result_ty)
    end

    function Native.NativeAbiResultProjection:native_code_result_shape()
        return self.abi:native_code_result_shape()
    end

    function Native.NativePatchFormula:native_patch_formula_equals(_other)
        return false
    end

    function Native.NativePatchSym32:native_patch_formula_equals(other)
        return other:native_patch_formula_equals_sym32()
    end

    function Native.NativePatchFormula:native_patch_formula_equals_sym32()
        return false
    end

    function Native.NativePatchSym32:native_patch_formula_equals_sym32()
        return true
    end

    function Native.NativePatchSym64:native_patch_formula_equals(other)
        return other:native_patch_formula_equals_sym64()
    end

    function Native.NativePatchFormula:native_patch_formula_equals_sym64()
        return false
    end

    function Native.NativePatchSym64:native_patch_formula_equals_sym64()
        return true
    end

    function Native.NativePatchPcRel32:native_patch_formula_equals(other)
        return other:native_patch_formula_equals_pcrel32()
    end

    function Native.NativePatchFormula:native_patch_formula_equals_pcrel32()
        return false
    end

    function Native.NativePatchPcRel32:native_patch_formula_equals_pcrel32()
        return true
    end

    local function stencil_metavar_binding_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            if not left[i]:native_stencil_metavar_binding_equals(right[i]) then return false end
        end
        return true
    end

    function Native.NativeStencilMetavarBinding:native_stencil_metavar_binding_equals(other)
        return other ~= nil and self.metavar == other.metavar and self.value:native_stencil_metavar_value_equals(other.value)
    end

    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals(_other)
        return false
    end

    function Native.NativeStencilScalarMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_scalar(self.scalar) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_scalar(_scalar) return false end
    function Native.NativeStencilScalarMetavarValue:native_stencil_metavar_value_equals_scalar(scalar) return self.scalar == scalar end
    function Native.NativeStencilLocationClassMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_location_class(self.location) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_location_class(_location) return false end
    function Native.NativeStencilLocationClassMetavarValue:native_stencil_metavar_value_equals_location_class(location) return self.location == location end
    function Native.NativeStencilPassthroughIntCountMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_passthrough_int_count(self.count) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_passthrough_int_count(_count) return false end
    function Native.NativeStencilPassthroughIntCountMetavarValue:native_stencil_metavar_value_equals_passthrough_int_count(count) return self.count == count end
    function Native.NativeStencilPassthroughFloatCountMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_passthrough_float_count(self.count) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_passthrough_float_count(_count) return false end
    function Native.NativeStencilPassthroughFloatCountMetavarValue:native_stencil_metavar_value_equals_passthrough_float_count(count) return self.count == count end
    function Native.NativeStencilControlShapeMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_control_shape(self.shape) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_control_shape(_shape) return false end
    function Native.NativeStencilControlShapeMetavarValue:native_stencil_metavar_value_equals_control_shape(shape) return self.shape == shape end
    function Native.NativeStencilCodeInstMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_code_inst(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_code_inst(_axis) return false end
    function Native.NativeStencilCodeInstMetavarValue:native_stencil_metavar_value_equals_code_inst(axis) return self.axis:native_code_inst_axis_equals(axis) end
    function Native.NativeStencilCodeTermMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_code_term(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_code_term(_axis) return false end
    function Native.NativeStencilCodeTermMetavarValue:native_stencil_metavar_value_equals_code_term(axis) return self.axis:native_code_term_axis_equals(axis) end
    function Native.NativeStencilKernelMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_kernel(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_kernel(_axis) return false end
    function Native.NativeStencilKernelMetavarValue:native_stencil_metavar_value_equals_kernel(axis) return self.axis:native_kernel_axis_equals(axis) end
    function Native.NativeStencilProducerMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_stencil_producer(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_stencil_producer(_axis) return false end
    function Native.NativeStencilProducerMetavarValue:native_stencil_metavar_value_equals_stencil_producer(axis) return self.axis:native_stencil_producer_axis_equals(axis) end
    function Native.NativeStencilAccessMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_stencil_access(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_stencil_access(_axis) return false end
    function Native.NativeStencilAccessMetavarValue:native_stencil_metavar_value_equals_stencil_access(axis) return self.axis:native_stencil_access_axis_equals(axis) end
    function Native.NativeStencilPointMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_stencil_point(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_stencil_point(_axis) return false end
    function Native.NativeStencilPointMetavarValue:native_stencil_metavar_value_equals_stencil_point(axis) return self.axis:native_stencil_point_axis_equals(axis) end
    function Native.NativeStencilSinkMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_stencil_sink(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_stencil_sink(_axis) return false end
    function Native.NativeStencilSinkMetavarValue:native_stencil_metavar_value_equals_stencil_sink(axis) return self.axis:native_stencil_sink_axis_equals(axis) end
    function Native.NativeStencilScheduleMetavarValue:native_stencil_metavar_value_equals(other) return other:native_stencil_metavar_value_equals_stencil_schedule(self.axis) end
    function Native.NativeStencilMetavarValue:native_stencil_metavar_value_equals_stencil_schedule(_axis) return false end
    function Native.NativeStencilScheduleMetavarValue:native_stencil_metavar_value_equals_stencil_schedule(axis) return self.axis:native_stencil_schedule_axis_equals(axis) end

    function Native.NativeStencilConfiguration:native_stencil_configuration_equals(other)
        return other ~= nil
            and self.id == other.id
            and self.generator == other.generator
            and stencil_metavar_binding_list_equals(self.bindings, other.bindings)
    end

    local function stencil_passthrough_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            local a, b = left[i], right[i]
            if b == nil or a.index ~= b.index or a.scalar ~= b.scalar or a.class ~= b.class then return false end
        end
        return true
    end

    local function stencil_operand_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            local a, b = left[i], right[i]
            if b == nil or a.index ~= b.index or a.scalar ~= b.scalar or a.location ~= b.location then return false end
        end
        return true
    end

    local function stencil_continuation_signature_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            if not left[i]:native_stencil_continuation_signature_equals(right[i]) then return false end
        end
        return true
    end

    local function stencil_continuation_param_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            local a, b = left[i], right[i]
            if b == nil or a.index ~= b.index or a.scalar ~= b.scalar or a.location ~= b.location then return false end
        end
        return true
    end

    function Native.NativeContinuationOrdinal:native_continuation_ordinal_equals(other)
        return other ~= nil and self.ordinal == other.ordinal and self.symbol == other.symbol
    end

    function Native.NativeStencilContinuationSignature:native_stencil_continuation_signature_equals(other)
        return other ~= nil
            and self.ordinal:native_continuation_ordinal_equals(other.ordinal)
            and stencil_continuation_param_list_equals(self.params, other.params)
    end

    function Native.NativeStencilSignature:native_stencil_signature_equals(other)
        return other ~= nil
            and self.frame_param.scalar == other.frame_param.scalar
            and stencil_passthrough_list_equals(self.passthroughs, other.passthroughs)
            and stencil_operand_list_equals(self.operands, other.operands)
            and stencil_continuation_signature_list_equals(self.continuations, other.continuations)
    end

    local function hole_ordinal_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            local a, b = left[i], right[i]
            if b == nil or a.id ~= b.id or a.ordinal ~= b.ordinal or a.symbol ~= b.symbol or a.hole ~= b.hole then return false end
        end
        return true
    end

    local function continuation_ordinal_list_equals(left, right)
        if #(left or {}) ~= #(right or {}) then return false end
        for i = 1, #(left or {}) do
            if not left[i]:native_continuation_ordinal_equals(right[i]) then return false end
        end
        return true
    end

    local function relocation_kind_list_equals(left, right)
        return value_list_equals(left, right)
    end

    function Native.NativeTemplateExtraction:native_template_extraction_equals(_other)
        return false
    end

    function Native.NativeExtractStandaloneCallable:native_template_extraction_equals(other) return other:native_template_extraction_equals_standalone_callable() end
    function Native.NativeTemplateExtraction:native_template_extraction_equals_standalone_callable() return false end
    function Native.NativeExtractStandaloneCallable:native_template_extraction_equals_standalone_callable() return true end
    function Native.NativeExtractEntryCallable:native_template_extraction_equals(other) return other:native_template_extraction_equals_entry_callable(self.frame_bytes, self.first_continuation) end
    function Native.NativeTemplateExtraction:native_template_extraction_equals_entry_callable(_frame_bytes, _first_continuation) return false end
    function Native.NativeExtractEntryCallable:native_template_extraction_equals_entry_callable(frame_bytes, first_continuation) return self.frame_bytes == frame_bytes and self.first_continuation == first_continuation end
    function Native.NativeExtractPublicAbiAdapter:native_template_extraction_equals(other) return other:native_template_extraction_equals_public_abi_adapter(self.abi_projection, self.frame_size_hole, self.frame_alignment, self.first_continuation) end
    function Native.NativeTemplateExtraction:native_template_extraction_equals_public_abi_adapter(_projection, _hole, _alignment, _first) return false end
    function Native.NativeExtractPublicAbiAdapter:native_template_extraction_equals_public_abi_adapter(projection, hole, alignment, first) return self.abi_projection:native_abi_function_projection_equals(projection) and self.frame_size_hole == hole and self.frame_alignment == alignment and self.first_continuation == first end
    function Native.NativeExtractContinuationFragment:native_template_extraction_equals(other) return other:native_template_extraction_equals_continuation_fragment(self.successors) end
    function Native.NativeTemplateExtraction:native_template_extraction_equals_continuation_fragment(_successors) return false end
    function Native.NativeExtractContinuationFragment:native_template_extraction_equals_continuation_fragment(successors) return value_list_equals(self.successors, successors) end
    function Native.NativeExtractTerminalContinuation:native_template_extraction_equals(other) return other:native_template_extraction_equals_terminal_continuation() end
    function Native.NativeTemplateExtraction:native_template_extraction_equals_terminal_continuation() return false end
    function Native.NativeExtractTerminalContinuation:native_template_extraction_equals_terminal_continuation() return true end

    function Native.NativeStencilGenerator:native_stencil_generator_equals(other)
        return other ~= nil
            and self.id == other.id
            and self.owner_family:native_family_equals(other.owner_family)
            and self.chunk_class == other.chunk_class
            and value_list_equals(self.metavars, other.metavars)
    end

    function Native.NativeTemplateManifestEntry:native_template_manifest_entry_equals(other)
        return other ~= nil
            and self.source == other.source
            and self.family:native_family_equals(other.family)
            and self.generator:native_stencil_generator_equals(other.generator)
            and self.configuration:native_stencil_configuration_equals(other.configuration)
            and self.signature:native_stencil_signature_equals(other.signature)
            and self.extraction:native_template_extraction_equals(other.extraction)
            and hole_ordinal_list_equals(self.declared_hole_ordinals, other.declared_hole_ordinals)
            and continuation_ordinal_list_equals(self.declared_continuation_ordinals, other.declared_continuation_ordinals)
            and relocation_kind_list_equals(self.declared_relocation_kinds, other.declared_relocation_kinds)
    end

    function Native.NativeTemplateAxis:native_axis_equals(_other)
        return false
    end

    function Native.NativeAxisTarget:native_axis_equals(other) return other:native_axis_equals_target(self.target) end
    function Native.NativeTemplateAxis:native_axis_equals_target(_target) return false end
    function Native.NativeAxisTarget:native_axis_equals_target(target) return self.target == target end
    function Native.NativeAxisRegisterProtocol:native_axis_equals(other) return other:native_axis_equals_register_protocol(self.protocol) end
    function Native.NativeTemplateAxis:native_axis_equals_register_protocol(_protocol) return false end
    function Native.NativeAxisRegisterProtocol:native_axis_equals_register_protocol(protocol) return self.protocol:native_register_protocol_equals(protocol) end
    function Native.NativeAxisMachineScalar:native_axis_equals(other) return other:native_axis_equals_machine_scalar(self.scalar) end
    function Native.NativeTemplateAxis:native_axis_equals_machine_scalar(_scalar) return false end
    function Native.NativeAxisMachineScalar:native_axis_equals_machine_scalar(scalar) return self.scalar == scalar end
    function Native.NativeAxisRegisterClass:native_axis_equals(other) return other:native_axis_equals_register_class(self.class) end
    function Native.NativeTemplateAxis:native_axis_equals_register_class(_class) return false end
    function Native.NativeAxisRegisterClass:native_axis_equals_register_class(class) return self.class == class end
    function Native.NativeAxisValuePlacement:native_axis_equals(other) return other:native_axis_equals_value_placement(self.placement) end
    function Native.NativeTemplateAxis:native_axis_equals_value_placement(_placement) return false end
    function Native.NativeAxisValuePlacement:native_axis_equals_value_placement(placement) return self.placement == placement end
    function Native.NativeAxisAbiParam:native_axis_equals(other) return other:native_axis_equals_abi_param(self.placement) end
    function Native.NativeTemplateAxis:native_axis_equals_abi_param(_placement) return false end
    function Native.NativeAxisAbiParam:native_axis_equals_abi_param(placement) return self.placement == placement end
    function Native.NativeAxisAbiResult:native_axis_equals(other) return other:native_axis_equals_abi_result(self.placement) end
    function Native.NativeTemplateAxis:native_axis_equals_abi_result(_placement) return false end
    function Native.NativeAxisAbiResult:native_axis_equals_abi_result(placement) return self.placement == placement end
    function Native.NativeAxisAbi:native_axis_equals(other) return other:native_axis_equals_abi(self.protocol) end
    function Native.NativeTemplateAxis:native_axis_equals_abi(_protocol) return false end
    function Native.NativeAxisAbi:native_axis_equals_abi(protocol) return self.protocol:native_call_protocol_equals(protocol) end
    function Native.NativeAxisCodeType:native_axis_equals(other) return other:native_axis_equals_code_type(self.ty) end
    function Native.NativeTemplateAxis:native_axis_equals_code_type(_ty) return false end
    function Native.NativeAxisCodeType:native_axis_equals_code_type(ty) return self.ty == ty end
    function Native.NativeAxisCodeSig:native_axis_equals(other) return other:native_axis_equals_code_sig(self.sig) end
    function Native.NativeTemplateAxis:native_axis_equals_code_sig(_sig) return false end
    function Native.NativeAxisCodeSig:native_axis_equals_code_sig(sig) return self.sig == sig end
    function Native.NativeAxisCodeInst:native_axis_equals(other) return other:native_axis_equals_code_inst(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_code_inst(_axis) return false end
    function Native.NativeAxisCodeInst:native_axis_equals_code_inst(axis) return self.axis:native_code_inst_axis_equals(axis) end
    function Native.NativeAxisCodeTerm:native_axis_equals(other) return other:native_axis_equals_code_term(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_code_term(_axis) return false end
    function Native.NativeAxisCodeTerm:native_axis_equals_code_term(axis) return self.axis:native_code_term_axis_equals(axis) end
    function Native.NativeAxisCodePlace:native_axis_equals(other) return other:native_axis_equals_code_place(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_code_place(_axis) return false end
    function Native.NativeAxisCodePlace:native_axis_equals_code_place(axis) return self.axis:native_code_place_axis_equals(axis) end
    function Native.NativeAxisCodeConst:native_axis_equals(other) return other:native_axis_equals_code_const(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_code_const(_axis) return false end
    function Native.NativeAxisCodeConst:native_axis_equals_code_const(axis) return self.axis:native_code_const_axis_equals(axis) end
    function Native.NativeAxisKernel:native_axis_equals(other) return other:native_axis_equals_kernel(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_kernel(_axis) return false end
    function Native.NativeAxisKernel:native_axis_equals_kernel(axis) return self.axis:native_kernel_axis_equals(axis) end
    function Native.NativeAxisStencilProducer:native_axis_equals(other) return other:native_axis_equals_stencil_producer(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_stencil_producer(_axis) return false end
    function Native.NativeAxisStencilProducer:native_axis_equals_stencil_producer(axis) return self.axis:native_stencil_producer_axis_equals(axis) end
    function Native.NativeAxisStencilAccess:native_axis_equals(other) return other:native_axis_equals_stencil_access(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_stencil_access(_axis) return false end
    function Native.NativeAxisStencilAccess:native_axis_equals_stencil_access(axis) return self.axis:native_stencil_access_axis_equals(axis) end
    function Native.NativeAxisStencilPoint:native_axis_equals(other) return other:native_axis_equals_stencil_point(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_stencil_point(_axis) return false end
    function Native.NativeAxisStencilPoint:native_axis_equals_stencil_point(axis) return self.axis:native_stencil_point_axis_equals(axis) end
    function Native.NativeAxisStencilBody:native_axis_equals(other) return other:native_axis_equals_stencil_body(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_stencil_body(_axis) return false end
    function Native.NativeAxisStencilBody:native_axis_equals_stencil_body(axis) return self.axis:native_stencil_body_axis_equals(axis) end
    function Native.NativeAxisStencilSink:native_axis_equals(other) return other:native_axis_equals_stencil_sink(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_stencil_sink(_axis) return false end
    function Native.NativeAxisStencilSink:native_axis_equals_stencil_sink(axis) return self.axis:native_stencil_sink_axis_equals(axis) end
    function Native.NativeAxisStencilSchedule:native_axis_equals(other) return other:native_axis_equals_stencil_schedule(self.axis) end
    function Native.NativeTemplateAxis:native_axis_equals_stencil_schedule(_axis) return false end
    function Native.NativeAxisStencilSchedule:native_axis_equals_stencil_schedule(axis) return self.axis:native_stencil_schedule_axis_equals(axis) end

    function Native.NativeCodeResultShape:native_code_result_shape_equals(_other) return false end
    function Native.NativeCodeResultVoidShape:native_code_result_shape_equals(other) return other:native_code_result_shape_equals_void() end
    function Native.NativeCodeResultShape:native_code_result_shape_equals_void() return false end
    function Native.NativeCodeResultVoidShape:native_code_result_shape_equals_void() return true end
    function Native.NativeCodeResultScalarShape:native_code_result_shape_equals(other) return other:native_code_result_shape_equals_scalar(self.scalar) end
    function Native.NativeCodeResultShape:native_code_result_shape_equals_scalar(_scalar) return false end
    function Native.NativeCodeResultScalarShape:native_code_result_shape_equals_scalar(scalar) return self.scalar == scalar end
    function Native.NativeCodeResultPointerShape:native_code_result_shape_equals(other) return other:native_code_result_shape_equals_pointer(self.scalar) end
    function Native.NativeCodeResultShape:native_code_result_shape_equals_pointer(_scalar) return false end
    function Native.NativeCodeResultPointerShape:native_code_result_shape_equals_pointer(scalar) return self.scalar == scalar end
    function Native.NativeCodeResultDescriptorShape:native_code_result_shape_equals(other) return other:native_code_result_shape_equals_descriptor(self.layout) end
    function Native.NativeCodeResultShape:native_code_result_shape_equals_descriptor(_layout) return false end
    function Native.NativeCodeResultDescriptorShape:native_code_result_shape_equals_descriptor(layout) return self.layout == layout end
    function Native.NativeCodeResultByRefShape:native_code_result_shape_equals(other) return other:native_code_result_shape_equals_byref(self.pointee_ty, self.mutability, self.alignment) end
    function Native.NativeCodeResultShape:native_code_result_shape_equals_byref(_pointee_ty, _mutability, _alignment) return false end
    function Native.NativeCodeResultByRefShape:native_code_result_shape_equals_byref(pointee_ty, mutability, alignment) return self.pointee_ty == pointee_ty and self.mutability == mutability and self.alignment == alignment end
    function Native.NativeCodeResultSRetShape:native_code_result_shape_equals(other) return other:native_code_result_shape_equals_sret(self.result_ty) end
    function Native.NativeCodeResultShape:native_code_result_shape_equals_sret(_result_ty) return false end
    function Native.NativeCodeResultSRetShape:native_code_result_shape_equals_sret(result_ty) return self.result_ty == result_ty end

    function Native.NativeCodeInstAxis:native_code_inst_axis_equals(_other) return false end
    function Native.NativeCodeInstConstAxis:native_code_inst_axis_equals(other) return other:native_code_inst_const_axis_equals(self.ty) end
    function Native.NativeCodeInstAxis:native_code_inst_const_axis_equals(_ty) return false end
    function Native.NativeCodeInstConstAxis:native_code_inst_const_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodeInstAliasAxis:native_code_inst_axis_equals(other) return other:native_code_inst_alias_axis_equals(self.ty) end
    function Native.NativeCodeInstAxis:native_code_inst_alias_axis_equals(_ty) return false end
    function Native.NativeCodeInstAliasAxis:native_code_inst_alias_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodeInstUnaryAxis:native_code_inst_axis_equals(other) return other:native_code_inst_unary_axis_equals(self.op, self.ty) end
    function Native.NativeCodeInstAxis:native_code_inst_unary_axis_equals(_op, _ty) return false end
    function Native.NativeCodeInstUnaryAxis:native_code_inst_unary_axis_equals(op, ty) return self.op == op and self.ty == ty end
    function Native.NativeCodeInstBinaryAxis:native_code_inst_axis_equals(other) return other:native_code_inst_binary_axis_equals(self.op, self.ty, self.semantics) end
    function Native.NativeCodeInstAxis:native_code_inst_binary_axis_equals(_op, _ty, _semantics) return false end
    function Native.NativeCodeInstBinaryAxis:native_code_inst_binary_axis_equals(op, ty, semantics) return self.op == op and self.ty == ty and self.semantics == semantics end
    function Native.NativeCodeInstFloatBinaryAxis:native_code_inst_axis_equals(other) return other:native_code_inst_float_binary_axis_equals(self.op, self.ty, self.mode) end
    function Native.NativeCodeInstAxis:native_code_inst_float_binary_axis_equals(_op, _ty, _mode) return false end
    function Native.NativeCodeInstFloatBinaryAxis:native_code_inst_float_binary_axis_equals(op, ty, mode) return self.op == op and self.ty == ty and self.mode == mode end
    function Native.NativeCodeInstCompareAxis:native_code_inst_axis_equals(other) return other:native_code_inst_compare_axis_equals(self.cmp, self.operand_ty) end
    function Native.NativeCodeInstAxis:native_code_inst_compare_axis_equals(_cmp, _operand_ty) return false end
    function Native.NativeCodeInstCompareAxis:native_code_inst_compare_axis_equals(cmp, operand_ty) return self.cmp == cmp and self.operand_ty == operand_ty end
    function Native.NativeCodeInstCastAxis:native_code_inst_axis_equals(other) return other:native_code_inst_cast_axis_equals(self.op, self.from, self.to) end
    function Native.NativeCodeInstAxis:native_code_inst_cast_axis_equals(_op, _from, _to) return false end
    function Native.NativeCodeInstCastAxis:native_code_inst_cast_axis_equals(op, from, to) return self.op == op and self.from == from and self.to == to end
    function Native.NativeCodeInstSelectAxis:native_code_inst_axis_equals(other) return other:native_code_inst_select_axis_equals(self.ty) end
    function Native.NativeCodeInstAxis:native_code_inst_select_axis_equals(_ty) return false end
    function Native.NativeCodeInstSelectAxis:native_code_inst_select_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodeInstIntrinsicAxis:native_code_inst_axis_equals(other) return other:native_code_inst_intrinsic_axis_equals(self.intrinsic, self.ty) end
    function Native.NativeCodeInstAxis:native_code_inst_intrinsic_axis_equals(_intrinsic, _ty) return false end
    function Native.NativeCodeInstIntrinsicAxis:native_code_inst_intrinsic_axis_equals(intrinsic, ty) return self.intrinsic == intrinsic and self.ty == ty end
    function Native.NativeCodeInstAddrOfAxis:native_code_inst_axis_equals(other) return other:native_code_inst_addr_of_axis_equals(self.ptr_ty) end
    function Native.NativeCodeInstAxis:native_code_inst_addr_of_axis_equals(_ptr_ty) return false end
    function Native.NativeCodeInstAddrOfAxis:native_code_inst_addr_of_axis_equals(ptr_ty) return self.ptr_ty == ptr_ty end
    function Native.NativeCodeInstGlobalRefAxis:native_code_inst_axis_equals(other) return other:native_code_inst_global_ref_axis_equals(self.ptr_ty) end
    function Native.NativeCodeInstAxis:native_code_inst_global_ref_axis_equals(_ptr_ty) return false end
    function Native.NativeCodeInstGlobalRefAxis:native_code_inst_global_ref_axis_equals(ptr_ty) return self.ptr_ty == ptr_ty end
    function Native.NativeCodeInstPtrOffsetAxis:native_code_inst_axis_equals(other) return other:native_code_inst_ptr_offset_axis_equals(self.ptr_ty, self.elem_size, self.const_offset) end
    function Native.NativeCodeInstAxis:native_code_inst_ptr_offset_axis_equals(_ptr_ty, _elem_size, _const_offset) return false end
    function Native.NativeCodeInstPtrOffsetAxis:native_code_inst_ptr_offset_axis_equals(ptr_ty, elem_size, const_offset) return self.ptr_ty == ptr_ty and self.elem_size == elem_size and self.const_offset == const_offset end
    function Native.NativeCodeInstPointerOffsetAxis:native_code_inst_axis_equals(other) return other:native_code_inst_pointer_offset_axis_equals(self.pointer, self.index) end
    function Native.NativeCodeInstAxis:native_code_inst_pointer_offset_axis_equals(_pointer, _index) return false end
    function Native.NativeCodeInstPointerOffsetAxis:native_code_inst_pointer_offset_axis_equals(pointer, index) return self.pointer == pointer and self.index == index end
    function Native.NativeCodeInstLoadAxis:native_code_inst_axis_equals(other) return other:native_code_inst_load_axis_equals(self.access) end
    function Native.NativeCodeInstAxis:native_code_inst_load_axis_equals(_access) return false end
    function Native.NativeCodeInstLoadAxis:native_code_inst_load_axis_equals(access) return self.access == access end
    function Native.NativeCodeInstStoreAxis:native_code_inst_axis_equals(other) return other:native_code_inst_store_axis_equals(self.access) end
    function Native.NativeCodeInstAxis:native_code_inst_store_axis_equals(_access) return false end
    function Native.NativeCodeInstStoreAxis:native_code_inst_store_axis_equals(access) return self.access == access end
    function Native.NativeCodeInstLayoutFieldStoreAxis:native_code_inst_axis_equals(other) return other:native_code_inst_layout_field_store_axis_equals(self.storage, self.scalar) end
    function Native.NativeCodeInstAxis:native_code_inst_layout_field_store_axis_equals(_storage, _scalar) return false end
    function Native.NativeCodeInstLayoutFieldStoreAxis:native_code_inst_layout_field_store_axis_equals(storage, scalar) return self.storage == storage and self.scalar == scalar end
    function Native.NativeCodeInstLayoutFieldLoadAxis:native_code_inst_axis_equals(other) return other:native_code_inst_layout_field_load_axis_equals(self.storage, self.scalar) end
    function Native.NativeCodeInstAxis:native_code_inst_layout_field_load_axis_equals(_storage, _scalar) return false end
    function Native.NativeCodeInstLayoutFieldLoadAxis:native_code_inst_layout_field_load_axis_equals(storage, scalar) return self.storage == storage and self.scalar == scalar end
    function Native.NativeCodeInstAddressMaterializeAxis:native_code_inst_axis_equals(other) return other:native_code_inst_address_materialize_axis_equals(self.kind, self.pointer) end
    function Native.NativeCodeInstAxis:native_code_inst_address_materialize_axis_equals(_kind, _pointer) return false end
    function Native.NativeCodeInstAddressMaterializeAxis:native_code_inst_address_materialize_axis_equals(kind, pointer) return self.kind == kind and self.pointer == pointer end
    function Native.NativeCodeInstAggregateAxis:native_code_inst_axis_equals(other) return other:native_code_inst_aggregate_axis_equals(self.ty) end
    function Native.NativeCodeInstAxis:native_code_inst_aggregate_axis_equals(_ty) return false end
    function Native.NativeCodeInstAggregateAxis:native_code_inst_aggregate_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodeInstArrayAxis:native_code_inst_axis_equals(other) return other:native_code_inst_array_axis_equals(self.ty) end
    function Native.NativeCodeInstAxis:native_code_inst_array_axis_equals(_ty) return false end
    function Native.NativeCodeInstArrayAxis:native_code_inst_array_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodeInstViewMakeAxis:native_code_inst_axis_equals(other) return other:native_code_inst_view_make_axis_equals(self.elem_ty) end
    function Native.NativeCodeInstAxis:native_code_inst_view_make_axis_equals(_elem_ty) return false end
    function Native.NativeCodeInstViewMakeAxis:native_code_inst_view_make_axis_equals(elem_ty) return self.elem_ty == elem_ty end
    function Native.NativeCodeInstViewDataAxis:native_code_inst_axis_equals(other) return other:native_code_inst_view_data_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_view_data_axis_equals() return false end
    function Native.NativeCodeInstViewDataAxis:native_code_inst_view_data_axis_equals() return true end
    function Native.NativeCodeInstViewLenAxis:native_code_inst_axis_equals(other) return other:native_code_inst_view_len_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_view_len_axis_equals() return false end
    function Native.NativeCodeInstViewLenAxis:native_code_inst_view_len_axis_equals() return true end
    function Native.NativeCodeInstViewStrideAxis:native_code_inst_axis_equals(other) return other:native_code_inst_view_stride_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_view_stride_axis_equals() return false end
    function Native.NativeCodeInstViewStrideAxis:native_code_inst_view_stride_axis_equals() return true end
    function Native.NativeCodeInstSliceMakeAxis:native_code_inst_axis_equals(other) return other:native_code_inst_slice_make_axis_equals(self.elem_ty) end
    function Native.NativeCodeInstAxis:native_code_inst_slice_make_axis_equals(_elem_ty) return false end
    function Native.NativeCodeInstSliceMakeAxis:native_code_inst_slice_make_axis_equals(elem_ty) return self.elem_ty == elem_ty end
    function Native.NativeCodeInstSliceDataAxis:native_code_inst_axis_equals(other) return other:native_code_inst_slice_data_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_slice_data_axis_equals() return false end
    function Native.NativeCodeInstSliceDataAxis:native_code_inst_slice_data_axis_equals() return true end
    function Native.NativeCodeInstSliceLenAxis:native_code_inst_axis_equals(other) return other:native_code_inst_slice_len_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_slice_len_axis_equals() return false end
    function Native.NativeCodeInstSliceLenAxis:native_code_inst_slice_len_axis_equals() return true end
    function Native.NativeCodeInstByteSpanMakeAxis:native_code_inst_axis_equals(other) return other:native_code_inst_byte_span_make_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_byte_span_make_axis_equals() return false end
    function Native.NativeCodeInstByteSpanMakeAxis:native_code_inst_byte_span_make_axis_equals() return true end
    function Native.NativeCodeInstByteSpanDataAxis:native_code_inst_axis_equals(other) return other:native_code_inst_byte_span_data_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_byte_span_data_axis_equals() return false end
    function Native.NativeCodeInstByteSpanDataAxis:native_code_inst_byte_span_data_axis_equals() return true end
    function Native.NativeCodeInstByteSpanLenAxis:native_code_inst_axis_equals(other) return other:native_code_inst_byte_span_len_axis_equals() end
    function Native.NativeCodeInstAxis:native_code_inst_byte_span_len_axis_equals() return false end
    function Native.NativeCodeInstByteSpanLenAxis:native_code_inst_byte_span_len_axis_equals() return true end
    function Native.NativeCodeInstClosureAxis:native_code_inst_axis_equals(other) return other:native_code_inst_closure_axis_equals(self.ty, self.sig) end
    function Native.NativeCodeInstAxis:native_code_inst_closure_axis_equals(_ty, _sig) return false end
    function Native.NativeCodeInstClosureAxis:native_code_inst_closure_axis_equals(ty, sig) return self.ty == ty and self.sig == sig end
    function Native.NativeCodeInstVariantScalarCtorAxis:native_code_inst_axis_equals(other) return other:native_code_inst_variant_scalar_ctor_axis_equals(self.tag, self.payload) end
    function Native.NativeCodeInstAxis:native_code_inst_variant_scalar_ctor_axis_equals(_tag, _payload) return false end
    function Native.NativeCodeInstVariantScalarCtorAxis:native_code_inst_variant_scalar_ctor_axis_equals(tag, payload) return self.tag == tag and self.payload == payload end
    function Native.NativeCodeInstVariantScalarTagAxis:native_code_inst_axis_equals(other) return other:native_code_inst_variant_scalar_tag_axis_equals(self.tag) end
    function Native.NativeCodeInstAxis:native_code_inst_variant_scalar_tag_axis_equals(_tag) return false end
    function Native.NativeCodeInstVariantScalarTagAxis:native_code_inst_variant_scalar_tag_axis_equals(tag) return self.tag == tag end
    function Native.NativeCodeInstVariantScalarPayloadAxis:native_code_inst_axis_equals(other) return other:native_code_inst_variant_scalar_payload_axis_equals(self.payload) end
    function Native.NativeCodeInstAxis:native_code_inst_variant_scalar_payload_axis_equals(_payload) return false end
    function Native.NativeCodeInstVariantScalarPayloadAxis:native_code_inst_variant_scalar_payload_axis_equals(payload) return self.payload == payload end
    function Native.NativeCodeInstVariantCtorAxis:native_code_inst_axis_equals(other) return other:native_code_inst_variant_ctor_axis_equals(self.ty, self.variant) end
    function Native.NativeCodeInstAxis:native_code_inst_variant_ctor_axis_equals(_ty, _variant) return false end
    function Native.NativeCodeInstVariantCtorAxis:native_code_inst_variant_ctor_axis_equals(ty, variant) return self.ty == ty and self.variant == variant end
    function Native.NativeCodeInstVariantTagAxis:native_code_inst_axis_equals(other) return other:native_code_inst_variant_tag_axis_equals(self.tag_ty) end
    function Native.NativeCodeInstAxis:native_code_inst_variant_tag_axis_equals(_tag_ty) return false end
    function Native.NativeCodeInstVariantTagAxis:native_code_inst_variant_tag_axis_equals(tag_ty) return self.tag_ty == tag_ty end
    function Native.NativeCodeInstVariantPayloadAxis:native_code_inst_axis_equals(other) return other:native_code_inst_variant_payload_axis_equals(self.variant) end
    function Native.NativeCodeInstAxis:native_code_inst_variant_payload_axis_equals(_variant) return false end
    function Native.NativeCodeInstVariantPayloadAxis:native_code_inst_variant_payload_axis_equals(variant) return self.variant == variant end
    function Native.NativeCodeInstCallShapeAxis:native_code_inst_axis_equals(other) return other:native_code_inst_call_shape_axis_equals(self.shape, self.abi) end
    function Native.NativeCodeInstAxis:native_code_inst_call_shape_axis_equals(_shape, _abi) return false end
    function Native.NativeCodeInstCallShapeAxis:native_code_inst_call_shape_axis_equals(shape, abi) return self.shape == shape and self.abi:native_abi_function_projection_equals(abi) end
    function Native.NativeCodeInstResultCopyAxis:native_code_inst_axis_equals(other) return other:native_code_inst_result_copy_axis_equals(self.result) end
    function Native.NativeCodeInstAxis:native_code_inst_result_copy_axis_equals(_result) return false end
    function Native.NativeCodeInstResultCopyAxis:native_code_inst_result_copy_axis_equals(result) return self.result:native_code_result_shape_equals(result) end
    function Native.NativeCodeInstAtomicLoadAxis:native_code_inst_axis_equals(other) return other:native_code_inst_atomic_load_axis_equals(self.access, self.ordering) end
    function Native.NativeCodeInstAxis:native_code_inst_atomic_load_axis_equals(_access, _ordering) return false end
    function Native.NativeCodeInstAtomicLoadAxis:native_code_inst_atomic_load_axis_equals(access, ordering) return self.access == access and self.ordering == ordering end
    function Native.NativeCodeInstAtomicStoreAxis:native_code_inst_axis_equals(other) return other:native_code_inst_atomic_store_axis_equals(self.access, self.ordering) end
    function Native.NativeCodeInstAxis:native_code_inst_atomic_store_axis_equals(_access, _ordering) return false end
    function Native.NativeCodeInstAtomicStoreAxis:native_code_inst_atomic_store_axis_equals(access, ordering) return self.access == access and self.ordering == ordering end
    function Native.NativeCodeInstAtomicRmwAxis:native_code_inst_axis_equals(other) return other:native_code_inst_atomic_rmw_axis_equals(self.op, self.access, self.ordering) end
    function Native.NativeCodeInstAxis:native_code_inst_atomic_rmw_axis_equals(_op, _access, _ordering) return false end
    function Native.NativeCodeInstAtomicRmwAxis:native_code_inst_atomic_rmw_axis_equals(op, access, ordering) return self.op == op and self.access == access and self.ordering == ordering end
    function Native.NativeCodeInstAtomicCasAxis:native_code_inst_axis_equals(other) return other:native_code_inst_atomic_cas_axis_equals(self.access, self.ordering) end
    function Native.NativeCodeInstAxis:native_code_inst_atomic_cas_axis_equals(_access, _ordering) return false end
    function Native.NativeCodeInstAtomicCasAxis:native_code_inst_atomic_cas_axis_equals(access, ordering) return self.access == access and self.ordering == ordering end
    function Native.NativeCodeInstAtomicFenceAxis:native_code_inst_axis_equals(other) return other:native_code_inst_atomic_fence_axis_equals(self.ordering) end
    function Native.NativeCodeInstAxis:native_code_inst_atomic_fence_axis_equals(_ordering) return false end
    function Native.NativeCodeInstAtomicFenceAxis:native_code_inst_atomic_fence_axis_equals(ordering) return self.ordering == ordering end

    function Native.NativeCodeTermAxis:native_code_term_axis_equals(_other) return false end
    function Native.NativeCodeTermJumpAxis:native_code_term_axis_equals(other) return other:native_code_term_jump_axis_equals() end
    function Native.NativeCodeTermAxis:native_code_term_jump_axis_equals() return false end
    function Native.NativeCodeTermJumpAxis:native_code_term_jump_axis_equals() return true end
    function Native.NativeCodeTermBranchAxis:native_code_term_axis_equals(other) return other:native_code_term_branch_axis_equals() end
    function Native.NativeCodeTermAxis:native_code_term_branch_axis_equals() return false end
    function Native.NativeCodeTermBranchAxis:native_code_term_branch_axis_equals() return true end
    function Native.NativeCodeTermSwitchAxis:native_code_term_axis_equals(other) return other:native_code_term_switch_axis_equals() end
    function Native.NativeCodeTermAxis:native_code_term_switch_axis_equals() return false end
    function Native.NativeCodeTermSwitchAxis:native_code_term_switch_axis_equals() return true end
    function Native.NativeCodeTermVariantSwitchAxis:native_code_term_axis_equals(other) return other:native_code_term_variant_switch_axis_equals() end
    function Native.NativeCodeTermAxis:native_code_term_variant_switch_axis_equals() return false end
    function Native.NativeCodeTermVariantSwitchAxis:native_code_term_variant_switch_axis_equals() return true end
    function Native.NativeCodeTermReturnAxis:native_code_term_axis_equals(other) return other:native_code_term_return_axis_equals(self.results) end
    function Native.NativeCodeTermAxis:native_code_term_return_axis_equals(_results) return false end
    function Native.NativeCodeTermReturnAxis:native_code_term_return_axis_equals(results) return value_list_equals(self.results, results) end
    function Native.NativeCodeTermReturnShapeAxis:native_code_term_axis_equals(other) return other:native_code_term_return_shape_axis_equals(self.result) end
    function Native.NativeCodeTermAxis:native_code_term_return_shape_axis_equals(_result) return false end
    function Native.NativeCodeTermReturnShapeAxis:native_code_term_return_shape_axis_equals(result) return self.result:native_code_result_shape_equals(result) end
    function Native.NativeCodeTermTrapAxis:native_code_term_axis_equals(other) return other:native_code_term_trap_axis_equals() end
    function Native.NativeCodeTermAxis:native_code_term_trap_axis_equals() return false end
    function Native.NativeCodeTermTrapAxis:native_code_term_trap_axis_equals() return true end
    function Native.NativeCodeTermUnreachableAxis:native_code_term_axis_equals(other) return other:native_code_term_unreachable_axis_equals() end
    function Native.NativeCodeTermAxis:native_code_term_unreachable_axis_equals() return false end
    function Native.NativeCodeTermUnreachableAxis:native_code_term_unreachable_axis_equals() return true end

    function Native.NativeCodeConstAxis:native_code_const_axis_equals(_other) return false end
    function Native.NativeCodeConstLiteralAxis:native_code_const_axis_equals(other) return other:native_code_const_literal_axis_equals(self.ty) end
    function Native.NativeCodeConstAxis:native_code_const_literal_axis_equals(_ty) return false end
    function Native.NativeCodeConstLiteralAxis:native_code_const_literal_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodeConstNullAxis:native_code_const_axis_equals(other) return other:native_code_const_null_axis_equals(self.ty) end
    function Native.NativeCodeConstAxis:native_code_const_null_axis_equals(_ty) return false end
    function Native.NativeCodeConstNullAxis:native_code_const_null_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodeConstUndefAxis:native_code_const_axis_equals(other) return other:native_code_const_undef_axis_equals(self.ty) end
    function Native.NativeCodeConstAxis:native_code_const_undef_axis_equals(_ty) return false end
    function Native.NativeCodeConstUndefAxis:native_code_const_undef_axis_equals(ty) return self.ty == ty end

    function Native.NativeCodePlaceAxis:native_code_place_axis_equals(_other) return false end
    function Native.NativeCodePlaceLocalAxis:native_code_place_axis_equals(other) return other:native_code_place_local_axis_equals(self.ty) end
    function Native.NativeCodePlaceAxis:native_code_place_local_axis_equals(_ty) return false end
    function Native.NativeCodePlaceLocalAxis:native_code_place_local_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodePlaceGlobalAxis:native_code_place_axis_equals(other) return other:native_code_place_global_axis_equals(self.ty) end
    function Native.NativeCodePlaceAxis:native_code_place_global_axis_equals(_ty) return false end
    function Native.NativeCodePlaceGlobalAxis:native_code_place_global_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodePlaceDataAxis:native_code_place_axis_equals(other) return other:native_code_place_data_axis_equals(self.ty) end
    function Native.NativeCodePlaceAxis:native_code_place_data_axis_equals(_ty) return false end
    function Native.NativeCodePlaceDataAxis:native_code_place_data_axis_equals(ty) return self.ty == ty end
    function Native.NativeCodePlaceDerefAxis:native_code_place_axis_equals(other) return other:native_code_place_deref_axis_equals(self.ty, self.align) end
    function Native.NativeCodePlaceAxis:native_code_place_deref_axis_equals(_ty, _align) return false end
    function Native.NativeCodePlaceDerefAxis:native_code_place_deref_axis_equals(ty, align) return self.ty == ty and self.align == align end
    function Native.NativeCodePlaceFieldAxis:native_code_place_axis_equals(other) return other:native_code_place_field_axis_equals(self.ty, self.offset, self.align) end
    function Native.NativeCodePlaceAxis:native_code_place_field_axis_equals(_ty, _offset, _align) return false end
    function Native.NativeCodePlaceFieldAxis:native_code_place_field_axis_equals(ty, offset, align) return self.ty == ty and self.offset == offset and self.align == align end
    function Native.NativeCodePlaceIndexAxis:native_code_place_axis_equals(other) return other:native_code_place_index_axis_equals(self.ty, self.elem_size) end
    function Native.NativeCodePlaceAxis:native_code_place_index_axis_equals(_ty, _elem_size) return false end
    function Native.NativeCodePlaceIndexAxis:native_code_place_index_axis_equals(ty, elem_size) return self.ty == ty and self.elem_size == elem_size end
    function Native.NativeCodePlaceBytesAxis:native_code_place_axis_equals(other) return other:native_code_place_bytes_axis_equals(self.ty, self.size, self.align) end
    function Native.NativeCodePlaceAxis:native_code_place_bytes_axis_equals(_ty, _size, _align) return false end
    function Native.NativeCodePlaceBytesAxis:native_code_place_bytes_axis_equals(ty, size, align) return self.ty == ty and self.size == size and self.align == align end

    local function native_storage_layout_equals(left, right)
        return left == right or (left ~= nil and right ~= nil and left.size == right.size and left.alignment == right.alignment)
    end

    function Native.NativeKernelLoopProjection:native_kernel_loop_projection_equals(other)
        return other ~= nil and self.domain == other.domain and self.trip_count == other.trip_count and self.counter == other.counter and self.index_scalar == other.index_scalar and self.trip_count_value == other.trip_count_value
    end

    function Native.NativeKernelLaneProjection:native_kernel_lane_projection_equals(other)
        return other ~= nil and self.lane == other.lane and native_storage_layout_equals(self.elem_storage, other.elem_storage) and self.address_scalar == other.address_scalar and self.index_scalar == other.index_scalar
    end

    function Native.NativeKernelFrameEntry:native_kernel_frame_entry_equals(other)
        return other ~= nil and self.role == other.role and native_storage_layout_equals(self.storage, other.storage) and self.template_value == other.template_value
    end

    function Native.NativeKernelExprProjection:native_kernel_expr_projection_equals(other)
        return self == other
    end
    function Native.NativeKernelExprCodeValueProjection:native_kernel_expr_projection_equals(other) return other ~= nil and other.native_kernel_expr_code_value_projection_equals ~= nil and other:native_kernel_expr_code_value_projection_equals(self.value, self.storage) end
    function Native.NativeKernelExprProjection:native_kernel_expr_code_value_projection_equals(_value, _storage) return false end
    function Native.NativeKernelExprCodeValueProjection:native_kernel_expr_code_value_projection_equals(value, storage) return self.value == value and native_storage_layout_equals(self.storage, storage) end
    function Native.NativeKernelExprAlgebraProjection:native_kernel_expr_projection_equals(other) return other ~= nil and other.native_kernel_expr_algebra_projection_equals ~= nil and other:native_kernel_expr_algebra_projection_equals(self.expr, self.storage) end
    function Native.NativeKernelExprProjection:native_kernel_expr_algebra_projection_equals(_expr, _storage) return false end
    function Native.NativeKernelExprAlgebraProjection:native_kernel_expr_algebra_projection_equals(expr, storage) return self.expr == expr and native_storage_layout_equals(self.storage, storage) end
    function Native.NativeKernelExprLaneLoadProjection:native_kernel_expr_projection_equals(other) return other ~= nil and other.native_kernel_expr_lane_load_projection_equals ~= nil and other:native_kernel_expr_lane_load_projection_equals(self.lane, self.index) end
    function Native.NativeKernelExprProjection:native_kernel_expr_lane_load_projection_equals(_lane, _index) return false end
    function Native.NativeKernelExprLaneLoadProjection:native_kernel_expr_lane_load_projection_equals(lane, index) return self.lane:native_kernel_lane_projection_equals(lane) and self.index == index end
    function Native.NativeKernelExprKernelValueProjection:native_kernel_expr_projection_equals(other) return other ~= nil and other.native_kernel_expr_kernel_value_projection_equals ~= nil and other:native_kernel_expr_kernel_value_projection_equals(self.value, self.storage) end
    function Native.NativeKernelExprProjection:native_kernel_expr_kernel_value_projection_equals(_value, _storage) return false end
    function Native.NativeKernelExprKernelValueProjection:native_kernel_expr_kernel_value_projection_equals(value, storage) return self.value == value and native_storage_layout_equals(self.storage, storage) end

    function Native.NativeKernelEffectStateProjection:native_kernel_effect_state_projection_equals(other) return self == other end
    function Native.NativeKernelEffectNoState:native_kernel_effect_state_projection_equals(other) return other == Native.NativeKernelEffectNoState end
    function Native.NativeKernelEffectScratchState:native_kernel_effect_state_projection_equals(other) return other ~= nil and other.native_kernel_effect_scratch_state_equals ~= nil and other:native_kernel_effect_scratch_state_equals(self.storage) end
    function Native.NativeKernelEffectStateProjection:native_kernel_effect_scratch_state_equals(_storage) return false end
    function Native.NativeKernelEffectScratchState:native_kernel_effect_scratch_state_equals(storage) return native_storage_layout_equals(self.storage, storage) end
    function Native.NativeKernelEffectReductionState:native_kernel_effect_state_projection_equals(other) return other ~= nil and other.native_kernel_effect_reduction_state_equals ~= nil and other:native_kernel_effect_reduction_state_equals(self.reduction, self.storage) end
    function Native.NativeKernelEffectStateProjection:native_kernel_effect_reduction_state_equals(_reduction, _storage) return false end
    function Native.NativeKernelEffectReductionState:native_kernel_effect_reduction_state_equals(reduction, storage) return self.reduction == reduction and native_storage_layout_equals(self.storage, storage) end
    function Native.NativeKernelEffectScanState:native_kernel_effect_state_projection_equals(other) return other ~= nil and other.native_kernel_effect_scan_state_equals ~= nil and other:native_kernel_effect_scan_state_equals(self.reduction, self.mode, self.storage) end
    function Native.NativeKernelEffectStateProjection:native_kernel_effect_scan_state_equals(_reduction, _mode, _storage) return false end
    function Native.NativeKernelEffectScanState:native_kernel_effect_scan_state_equals(reduction, mode, storage) return self.reduction == reduction and self.mode == mode and native_storage_layout_equals(self.storage, storage) end

    function Native.NativeKernelEffectProjection:native_kernel_effect_projection_equals(other) return self == other end
    function Native.NativeKernelEffectStoreProjection:native_kernel_effect_projection_equals(other) return other ~= nil and other.native_kernel_effect_store_projection_equals ~= nil and other:native_kernel_effect_store_projection_equals(self.dst, self.index, self.value, self.state) end
    function Native.NativeKernelEffectProjection:native_kernel_effect_store_projection_equals(_dst, _index, _value, _state) return false end
    function Native.NativeKernelEffectStoreProjection:native_kernel_effect_store_projection_equals(dst, index, value, state) return self.dst:native_kernel_lane_projection_equals(dst) and self.index == index and self.value:native_kernel_expr_projection_equals(value) and self.state:native_kernel_effect_state_projection_equals(state) end
    function Native.NativeKernelEffectFoldProjection:native_kernel_effect_projection_equals(other) return other ~= nil and other.native_kernel_effect_fold_projection_equals ~= nil and other:native_kernel_effect_fold_projection_equals(self.reduction, self.state) end
    function Native.NativeKernelEffectProjection:native_kernel_effect_fold_projection_equals(_reduction, _state) return false end
    function Native.NativeKernelEffectFoldProjection:native_kernel_effect_fold_projection_equals(reduction, state) return self.reduction == reduction and self.state:native_kernel_effect_state_projection_equals(state) end

    function Native.NativeKernelResultProjection:native_kernel_result_projection_equals(other) return self == other end
    function Native.NativeKernelResultVoidProjection:native_kernel_result_projection_equals(other) return other == Native.NativeKernelResultVoidProjection end
    function Native.NativeKernelResultClosedFormProjection:native_kernel_result_projection_equals(other) return other ~= nil and other.native_kernel_result_closed_form_projection_equals ~= nil and other:native_kernel_result_closed_form_projection_equals(self.closed_form) end
    function Native.NativeKernelResultProjection:native_kernel_result_closed_form_projection_equals(_closed_form) return false end
    function Native.NativeKernelResultClosedFormProjection:native_kernel_result_closed_form_projection_equals(closed_form) return self.closed_form == closed_form end

    function Native.NativeKernelBodyProjection:native_kernel_body_projection_equals(other)
        return other ~= nil and self.body == other.body and self.domain:native_kernel_loop_projection_equals(other.domain) and #self.lanes == #other.lanes and #self.bindings == #other.bindings and #self.effects == #other.effects and self.result:native_kernel_result_projection_equals(other.result)
    end

    function Native.NativeKernelPlanProjection:native_kernel_plan_projection_equals(other) return self == other end
    function Native.NativeKernelNoPlanProjection:native_kernel_plan_projection_equals(other) return other ~= nil and other.native_kernel_no_plan_projection_equals ~= nil and other:native_kernel_no_plan_projection_equals(self.plan) end
    function Native.NativeKernelPlanProjection:native_kernel_no_plan_projection_equals(_plan) return false end
    function Native.NativeKernelNoPlanProjection:native_kernel_no_plan_projection_equals(plan) return self.plan == plan end
    function Native.NativeKernelPlannedProjection:native_kernel_plan_projection_equals(other) return other ~= nil and other.native_kernel_planned_projection_equals ~= nil and other:native_kernel_planned_projection_equals(self.plan, self.body) end
    function Native.NativeKernelPlanProjection:native_kernel_planned_projection_equals(_plan, _body) return false end
    function Native.NativeKernelPlannedProjection:native_kernel_planned_projection_equals(plan, body) return self.plan == plan and self.body:native_kernel_body_projection_equals(body) end

    function Native.NativeKernelAxis:native_kernel_axis_equals(_other) return false end
    function Native.NativeKernelDomainProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_domain_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_domain_projection_axis_equals(_projection) return false end
    function Native.NativeKernelDomainProjectionAxis:native_kernel_domain_projection_axis_equals(projection) return self.projection:native_kernel_loop_projection_equals(projection) end
    function Native.NativeKernelLaneProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_lane_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_lane_projection_axis_equals(_projection) return false end
    function Native.NativeKernelLaneProjectionAxis:native_kernel_lane_projection_axis_equals(projection) return self.projection:native_kernel_lane_projection_equals(projection) end
    function Native.NativeKernelExprProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_expr_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_expr_projection_axis_equals(_projection) return false end
    function Native.NativeKernelExprProjectionAxis:native_kernel_expr_projection_axis_equals(projection) return self.projection:native_kernel_expr_projection_equals(projection) end
    function Native.NativeKernelEffectProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_effect_projection_axis_equals(_projection) return false end
    function Native.NativeKernelEffectProjectionAxis:native_kernel_effect_projection_axis_equals(projection) return self.projection:native_kernel_effect_projection_equals(projection) end
    function Native.NativeKernelResultProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_result_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_result_projection_axis_equals(_projection) return false end
    function Native.NativeKernelResultProjectionAxis:native_kernel_result_projection_axis_equals(projection) return self.projection:native_kernel_result_projection_equals(projection) end
    function Native.NativeKernelProofProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_proof_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_proof_projection_axis_equals(_projection) return false end
    function Native.NativeKernelProofProjectionAxis:native_kernel_proof_projection_axis_equals(projection) return self.projection == projection end
    function Native.NativeKernelBodyProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_body_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_body_projection_axis_equals(_projection) return false end
    function Native.NativeKernelBodyProjectionAxis:native_kernel_body_projection_axis_equals(projection) return self.projection:native_kernel_body_projection_equals(projection) end
    function Native.NativeKernelPlanProjectionAxis:native_kernel_axis_equals(other) return other:native_kernel_plan_projection_axis_equals(self.projection) end
    function Native.NativeKernelAxis:native_kernel_plan_projection_axis_equals(_projection) return false end
    function Native.NativeKernelPlanProjectionAxis:native_kernel_plan_projection_axis_equals(projection) return self.projection:native_kernel_plan_projection_equals(projection) end
    function Native.NativeKernelValueSourceShape:native_kernel_value_source_shape_equals(other) return self == other end
    function Native.NativeKernelValueScalarShape:native_kernel_value_source_shape_equals(other) return other ~= nil and other.native_kernel_value_scalar_shape_equals ~= nil and other:native_kernel_value_scalar_shape_equals(self.scalar) end
    function Native.NativeKernelValueSourceShape:native_kernel_value_scalar_shape_equals(_scalar) return false end
    function Native.NativeKernelValueScalarShape:native_kernel_value_scalar_shape_equals(scalar) return self.scalar == scalar end
    function Native.NativeKernelValuePointerShape:native_kernel_value_source_shape_equals(other) return other ~= nil and other.native_kernel_value_pointer_shape_equals ~= nil and other:native_kernel_value_pointer_shape_equals(self.pointer) end
    function Native.NativeKernelValueSourceShape:native_kernel_value_pointer_shape_equals(_pointer) return false end
    function Native.NativeKernelValuePointerShape:native_kernel_value_pointer_shape_equals(pointer) return self.pointer == pointer end
    function Native.NativeKernelValueBytesShape:native_kernel_value_source_shape_equals(other) return other ~= nil and other.native_kernel_value_bytes_shape_equals ~= nil and other:native_kernel_value_bytes_shape_equals(self.size, self.alignment) end
    function Native.NativeKernelValueSourceShape:native_kernel_value_bytes_shape_equals(_size, _alignment) return false end
    function Native.NativeKernelValueBytesShape:native_kernel_value_bytes_shape_equals(size, alignment) return self.size == size and self.alignment == alignment end

    function Native.NativeKernelLoopSourceShape:native_kernel_loop_source_shape_equals(other) return self == other end
    function Native.NativeKernelLoopRange1DShape:native_kernel_loop_source_shape_equals(other) return other ~= nil and other.native_kernel_loop_range_1d_shape_equals ~= nil and other:native_kernel_loop_range_1d_shape_equals(self.index_scalar, self.trip_count, self.has_counter) end
    function Native.NativeKernelLoopSourceShape:native_kernel_loop_range_1d_shape_equals(_index_scalar, _trip_count, _has_counter) return false end
    function Native.NativeKernelLoopRange1DShape:native_kernel_loop_range_1d_shape_equals(index_scalar, trip_count, has_counter) return self.index_scalar == index_scalar and self.trip_count == trip_count and self.has_counter == has_counter end

    function Native.NativeKernelLaneAddressSourceShape:native_kernel_lane_address_source_shape_equals(other) return self == other end
    function Native.NativeKernelLaneScalarAddressShape:native_kernel_lane_address_source_shape_equals(other) return other ~= nil and other.native_kernel_lane_scalar_address_shape_equals ~= nil and other:native_kernel_lane_scalar_address_shape_equals(self.elem, self.address, self.index) end
    function Native.NativeKernelLaneAddressSourceShape:native_kernel_lane_scalar_address_shape_equals(_elem, _address, _index) return false end
    function Native.NativeKernelLaneScalarAddressShape:native_kernel_lane_scalar_address_shape_equals(elem, address, index) return self.elem:native_kernel_value_source_shape_equals(elem) and self.address == address and self.index == index end
    function Native.NativeKernelLaneContiguousAddressShape:native_kernel_lane_address_source_shape_equals(other) return other ~= nil and other.native_kernel_lane_contiguous_address_shape_equals ~= nil and other:native_kernel_lane_contiguous_address_shape_equals(self.elem, self.address, self.index) end
    function Native.NativeKernelLaneAddressSourceShape:native_kernel_lane_contiguous_address_shape_equals(_elem, _address, _index) return false end
    function Native.NativeKernelLaneContiguousAddressShape:native_kernel_lane_contiguous_address_shape_equals(elem, address, index) return self.elem:native_kernel_value_source_shape_equals(elem) and self.address == address and self.index == index end
    function Native.NativeKernelLaneStridedAddressShape:native_kernel_lane_address_source_shape_equals(other) return other ~= nil and other.native_kernel_lane_strided_address_shape_equals ~= nil and other:native_kernel_lane_strided_address_shape_equals(self.elem, self.address, self.index) end
    function Native.NativeKernelLaneAddressSourceShape:native_kernel_lane_strided_address_shape_equals(_elem, _address, _index) return false end
    function Native.NativeKernelLaneStridedAddressShape:native_kernel_lane_strided_address_shape_equals(elem, address, index) return self.elem:native_kernel_value_source_shape_equals(elem) and self.address == address and self.index == index end
    function Native.NativeKernelLaneIndexedAddressShape:native_kernel_lane_address_source_shape_equals(other) return other ~= nil and other.native_kernel_lane_indexed_address_shape_equals ~= nil and other:native_kernel_lane_indexed_address_shape_equals(self.elem, self.address, self.index) end
    function Native.NativeKernelLaneAddressSourceShape:native_kernel_lane_indexed_address_shape_equals(_elem, _address, _index) return false end
    function Native.NativeKernelLaneIndexedAddressShape:native_kernel_lane_indexed_address_shape_equals(elem, address, index) return self.elem:native_kernel_value_source_shape_equals(elem) and self.address == address and self.index == index end

    function Native.NativeKernelValueExprSourceShape:native_kernel_value_expr_source_shape_equals(other) return self == other end
    function Native.NativeKernelExprCodeValueShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_code_value_shape_equals ~= nil and other:native_kernel_expr_code_value_shape_equals(self.value) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_code_value_shape_equals(_value) return false end
    function Native.NativeKernelExprCodeValueShape:native_kernel_expr_code_value_shape_equals(value) return self.value:native_kernel_value_source_shape_equals(value) end
    function Native.NativeKernelExprKernelValueShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_kernel_value_shape_equals ~= nil and other:native_kernel_expr_kernel_value_shape_equals(self.value) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_kernel_value_shape_equals(_value) return false end
    function Native.NativeKernelExprKernelValueShape:native_kernel_expr_kernel_value_shape_equals(value) return self.value:native_kernel_value_source_shape_equals(value) end
    function Native.NativeKernelExprConstShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_const_shape_equals ~= nil and other:native_kernel_expr_const_shape_equals(self.value) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_const_shape_equals(_value) return false end
    function Native.NativeKernelExprConstShape:native_kernel_expr_const_shape_equals(value) return self.value:native_kernel_value_source_shape_equals(value) end
    function Native.NativeKernelExprAffineShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_affine_shape_equals ~= nil and other:native_kernel_expr_affine_shape_equals(self.value, self.term_count) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_affine_shape_equals(_value, _term_count) return false end
    function Native.NativeKernelExprAffineShape:native_kernel_expr_affine_shape_equals(value, term_count) return self.value:native_kernel_value_source_shape_equals(value) and self.term_count == term_count end
    function Native.NativeKernelExprUnaryShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_unary_shape_equals ~= nil and other:native_kernel_expr_unary_shape_equals(self.op, self.value) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_unary_shape_equals(_op, _value) return false end
    function Native.NativeKernelExprUnaryShape:native_kernel_expr_unary_shape_equals(op, value) return self.op == op and self.value:native_kernel_value_source_shape_equals(value) end
    function Native.NativeKernelExprCastShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_cast_shape_equals ~= nil and other:native_kernel_expr_cast_shape_equals(self.op, self.from, self.to) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_cast_shape_equals(_op, _from, _to) return false end
    function Native.NativeKernelExprCastShape:native_kernel_expr_cast_shape_equals(op, from, to) return self.op == op and self.from:native_kernel_value_source_shape_equals(from) and self.to:native_kernel_value_source_shape_equals(to) end
    function Native.NativeKernelExprBinaryShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_binary_shape_equals ~= nil and other:native_kernel_expr_binary_shape_equals(self.op, self.value) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_binary_shape_equals(_op, _value) return false end
    function Native.NativeKernelExprBinaryShape:native_kernel_expr_binary_shape_equals(op, value) return self.op == op and self.value:native_kernel_value_source_shape_equals(value) end
    function Native.NativeKernelExprCompareShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_compare_shape_equals ~= nil and other:native_kernel_expr_compare_shape_equals(self.cmp, self.operand) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_compare_shape_equals(_cmp, _operand) return false end
    function Native.NativeKernelExprCompareShape:native_kernel_expr_compare_shape_equals(cmp, operand) return self.cmp == cmp and self.operand:native_kernel_value_source_shape_equals(operand) end
    function Native.NativeKernelExprSelectShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_select_shape_equals ~= nil and other:native_kernel_expr_select_shape_equals(self.value) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_select_shape_equals(_value) return false end
    function Native.NativeKernelExprSelectShape:native_kernel_expr_select_shape_equals(value) return self.value:native_kernel_value_source_shape_equals(value) end
    function Native.NativeKernelExprLaneLoadShape:native_kernel_value_expr_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_lane_load_shape_equals ~= nil and other:native_kernel_expr_lane_load_shape_equals(self.lane) end
    function Native.NativeKernelValueExprSourceShape:native_kernel_expr_lane_load_shape_equals(_lane) return false end
    function Native.NativeKernelExprLaneLoadShape:native_kernel_expr_lane_load_shape_equals(lane) return self.lane:native_kernel_lane_address_source_shape_equals(lane) end

    function Native.NativeKernelPredicateSourceShape:native_kernel_predicate_source_shape_equals(other) return self == other end
    function Native.NativeKernelPredicateCompareConstShape:native_kernel_predicate_source_shape_equals(other) return other ~= nil and other.native_kernel_predicate_compare_const_shape_equals ~= nil and other:native_kernel_predicate_compare_const_shape_equals(self.cmp, self.operand) end
    function Native.NativeKernelPredicateSourceShape:native_kernel_predicate_compare_const_shape_equals(_cmp, _operand) return false end
    function Native.NativeKernelPredicateCompareConstShape:native_kernel_predicate_compare_const_shape_equals(cmp, operand) return self.cmp == cmp and self.operand:native_kernel_value_source_shape_equals(operand) end
    function Native.NativeKernelPredicateRangeShape:native_kernel_predicate_source_shape_equals(other) return other ~= nil and other.native_kernel_predicate_range_shape_equals ~= nil and other:native_kernel_predicate_range_shape_equals(self.operand) end
    function Native.NativeKernelPredicateSourceShape:native_kernel_predicate_range_shape_equals(_operand) return false end
    function Native.NativeKernelPredicateRangeShape:native_kernel_predicate_range_shape_equals(operand) return self.operand:native_kernel_value_source_shape_equals(operand) end
    function Native.NativeKernelPredicateLogicalShape:native_kernel_predicate_source_shape_equals(other) return other ~= nil and other.native_kernel_predicate_logical_shape_equals ~= nil and other:native_kernel_predicate_logical_shape_equals(self.term_count) end
    function Native.NativeKernelPredicateSourceShape:native_kernel_predicate_logical_shape_equals(_term_count) return false end
    function Native.NativeKernelPredicateLogicalShape:native_kernel_predicate_logical_shape_equals(term_count) return self.term_count == term_count end
    function Native.NativeKernelPredicateFloatClassShape:native_kernel_predicate_source_shape_equals(other) return other ~= nil and other.native_kernel_predicate_float_class_shape_equals ~= nil and other:native_kernel_predicate_float_class_shape_equals(self.operand) end
    function Native.NativeKernelPredicateSourceShape:native_kernel_predicate_float_class_shape_equals(_operand) return false end
    function Native.NativeKernelPredicateFloatClassShape:native_kernel_predicate_float_class_shape_equals(operand) return self.operand:native_kernel_value_source_shape_equals(operand) end

    function Native.NativeKernelReducerSourceShape:native_kernel_reducer_source_shape_equals(other)
        return other ~= nil and self.op == other.op and self.value:native_kernel_value_source_shape_equals(other.value)
    end

    function Native.NativeKernelCallSourceShape:native_kernel_call_source_shape_equals(other) return self == other end
    function Native.NativeKernelCallEffectOnlyShape:native_kernel_call_source_shape_equals(other) return other ~= nil and other.native_kernel_call_effect_only_shape_equals ~= nil and other:native_kernel_call_effect_only_shape_equals(self.effect_count) end
    function Native.NativeKernelCallSourceShape:native_kernel_call_effect_only_shape_equals(_effect_count) return false end
    function Native.NativeKernelCallEffectOnlyShape:native_kernel_call_effect_only_shape_equals(effect_count) return self.effect_count == effect_count end

    function Native.NativeKernelEffectSourceShape:native_kernel_effect_source_shape_equals(other) return self == other end
    function Native.NativeKernelEffectStoreShape:native_kernel_effect_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_store_shape_equals ~= nil and other:native_kernel_effect_store_shape_equals(self.dst, self.value) end
    function Native.NativeKernelEffectSourceShape:native_kernel_effect_store_shape_equals(_dst, _value) return false end
    function Native.NativeKernelEffectStoreShape:native_kernel_effect_store_shape_equals(dst, value) return self.dst:native_kernel_lane_address_source_shape_equals(dst) and self.value:native_kernel_value_expr_source_shape_equals(value) end
    function Native.NativeKernelEffectScanShape:native_kernel_effect_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_scan_shape_equals ~= nil and other:native_kernel_effect_scan_shape_equals(self.dst, self.reducer, self.mode) end
    function Native.NativeKernelEffectSourceShape:native_kernel_effect_scan_shape_equals(_dst, _reducer, _mode) return false end
    function Native.NativeKernelEffectScanShape:native_kernel_effect_scan_shape_equals(dst, reducer, mode) return self.dst:native_kernel_lane_address_source_shape_equals(dst) and self.reducer:native_kernel_reducer_source_shape_equals(reducer) and self.mode == mode end
    function Native.NativeKernelEffectPartitionShape:native_kernel_effect_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_partition_shape_equals ~= nil and other:native_kernel_effect_partition_shape_equals(self.dst, self.src, self.pred, self.semantics) end
    function Native.NativeKernelEffectSourceShape:native_kernel_effect_partition_shape_equals(_dst, _src, _pred, _semantics) return false end
    function Native.NativeKernelEffectPartitionShape:native_kernel_effect_partition_shape_equals(dst, src, pred, semantics) return self.dst:native_kernel_lane_address_source_shape_equals(dst) and self.src:native_kernel_value_expr_source_shape_equals(src) and self.pred:native_kernel_predicate_source_shape_equals(pred) and self.semantics == semantics end
    function Native.NativeKernelEffectCopyShape:native_kernel_effect_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_copy_shape_equals ~= nil and other:native_kernel_effect_copy_shape_equals(self.dst, self.src, self.semantics) end
    function Native.NativeKernelEffectSourceShape:native_kernel_effect_copy_shape_equals(_dst, _src, _semantics) return false end
    function Native.NativeKernelEffectCopyShape:native_kernel_effect_copy_shape_equals(dst, src, semantics) return self.dst:native_kernel_lane_address_source_shape_equals(dst) and self.src:native_kernel_value_expr_source_shape_equals(src) and self.semantics == semantics end
    function Native.NativeKernelEffectScatterReduceShape:native_kernel_effect_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_scatter_reduce_shape_equals ~= nil and other:native_kernel_effect_scatter_reduce_shape_equals(self.dst, self.value, self.reducer) end
    function Native.NativeKernelEffectSourceShape:native_kernel_effect_scatter_reduce_shape_equals(_dst, _value, _reducer) return false end
    function Native.NativeKernelEffectScatterReduceShape:native_kernel_effect_scatter_reduce_shape_equals(dst, value, reducer) return self.dst:native_kernel_lane_address_source_shape_equals(dst) and self.value:native_kernel_value_expr_source_shape_equals(value) and self.reducer:native_kernel_reducer_source_shape_equals(reducer) end
    function Native.NativeKernelEffectFoldShape:native_kernel_effect_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_fold_shape_equals ~= nil and other:native_kernel_effect_fold_shape_equals(self.reducer) end
    function Native.NativeKernelEffectSourceShape:native_kernel_effect_fold_shape_equals(_reducer) return false end
    function Native.NativeKernelEffectFoldShape:native_kernel_effect_fold_shape_equals(reducer) return self.reducer:native_kernel_reducer_source_shape_equals(reducer) end
    function Native.NativeKernelEffectCallShape:native_kernel_effect_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_call_shape_equals ~= nil and other:native_kernel_effect_call_shape_equals(self.call) end
    function Native.NativeKernelEffectSourceShape:native_kernel_effect_call_shape_equals(_call) return false end
    function Native.NativeKernelEffectCallShape:native_kernel_effect_call_shape_equals(call) return self.call:native_kernel_call_source_shape_equals(call) end

    function Native.NativeKernelResultSourceShape:native_kernel_result_source_shape_equals(other) return self == other end
    function Native.NativeKernelResultValueShape:native_kernel_result_source_shape_equals(other) return other ~= nil and other.native_kernel_result_value_shape_equals ~= nil and other:native_kernel_result_value_shape_equals(self.value) end
    function Native.NativeKernelResultSourceShape:native_kernel_result_value_shape_equals(_value) return false end
    function Native.NativeKernelResultValueShape:native_kernel_result_value_shape_equals(value) return self.value:native_kernel_value_expr_source_shape_equals(value) end
    function Native.NativeKernelResultFindShape:native_kernel_result_source_shape_equals(other) return other ~= nil and other.native_kernel_result_find_shape_equals ~= nil and other:native_kernel_result_find_shape_equals(self.src, self.pred) end
    function Native.NativeKernelResultSourceShape:native_kernel_result_find_shape_equals(_src, _pred) return false end
    function Native.NativeKernelResultFindShape:native_kernel_result_find_shape_equals(src, pred) return self.src:native_kernel_value_expr_source_shape_equals(src) and self.pred:native_kernel_predicate_source_shape_equals(pred) end
    function Native.NativeKernelResultReductionShape:native_kernel_result_source_shape_equals(other) return other ~= nil and other.native_kernel_result_reduction_shape_equals ~= nil and other:native_kernel_result_reduction_shape_equals(self.reducer) end
    function Native.NativeKernelResultSourceShape:native_kernel_result_reduction_shape_equals(_reducer) return false end
    function Native.NativeKernelResultReductionShape:native_kernel_result_reduction_shape_equals(reducer) return self.reducer:native_kernel_reducer_source_shape_equals(reducer) end
    function Native.NativeKernelResultClosedFormShape:native_kernel_result_source_shape_equals(other) return other ~= nil and other.native_kernel_result_closed_form_shape_equals ~= nil and other:native_kernel_result_closed_form_shape_equals(self.value) end
    function Native.NativeKernelResultSourceShape:native_kernel_result_closed_form_shape_equals(_value) return false end
    function Native.NativeKernelResultClosedFormShape:native_kernel_result_closed_form_shape_equals(value) return self.value:native_kernel_value_source_shape_equals(value) end

    function Native.NativeKernelBodySourceShape:native_kernel_body_source_shape_equals(other)
        return other ~= nil and self.loop:native_kernel_loop_source_shape_equals(other.loop) and self.lane_count == other.lane_count and self.binding_count == other.binding_count and self.effect_count == other.effect_count and self.result:native_kernel_result_source_shape_equals(other.result)
    end
    function Native.NativeKernelPlanSourceShape:native_kernel_plan_source_shape_equals(other) return self == other end
    function Native.NativeKernelPlannedSourceShape:native_kernel_plan_source_shape_equals(other) return other ~= nil and other.native_kernel_planned_source_shape_equals ~= nil and other:native_kernel_planned_source_shape_equals(self.body) end
    function Native.NativeKernelPlanSourceShape:native_kernel_planned_source_shape_equals(_body) return false end
    function Native.NativeKernelPlannedSourceShape:native_kernel_planned_source_shape_equals(body) return self.body:native_kernel_body_source_shape_equals(body) end

    function Native.NativeKernelOpSourceShape:native_kernel_op_source_shape_equals(other) return self == other end
    function Native.NativeKernelDomainOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_domain_op_shape_equals ~= nil and other:native_kernel_domain_op_shape_equals(self.loop) end
    function Native.NativeKernelOpSourceShape:native_kernel_domain_op_shape_equals(_loop) return false end
    function Native.NativeKernelDomainOpShape:native_kernel_domain_op_shape_equals(loop) return self.loop:native_kernel_loop_source_shape_equals(loop) end
    function Native.NativeKernelLaneOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_lane_op_shape_equals ~= nil and other:native_kernel_lane_op_shape_equals(self.lane) end
    function Native.NativeKernelOpSourceShape:native_kernel_lane_op_shape_equals(_lane) return false end
    function Native.NativeKernelLaneOpShape:native_kernel_lane_op_shape_equals(lane) return self.lane:native_kernel_lane_address_source_shape_equals(lane) end
    function Native.NativeKernelExprOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_expr_op_shape_equals ~= nil and other:native_kernel_expr_op_shape_equals(self.expr) end
    function Native.NativeKernelOpSourceShape:native_kernel_expr_op_shape_equals(_expr) return false end
    function Native.NativeKernelExprOpShape:native_kernel_expr_op_shape_equals(expr) return self.expr:native_kernel_value_expr_source_shape_equals(expr) end
    function Native.NativeKernelBodyOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_body_op_shape_equals ~= nil and other:native_kernel_body_op_shape_equals(self.body) end
    function Native.NativeKernelOpSourceShape:native_kernel_body_op_shape_equals(_body) return false end
    function Native.NativeKernelBodyOpShape:native_kernel_body_op_shape_equals(body) return self.body:native_kernel_body_source_shape_equals(body) end
    function Native.NativeKernelEffectOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_effect_op_shape_equals ~= nil and other:native_kernel_effect_op_shape_equals(self.effect) end
    function Native.NativeKernelOpSourceShape:native_kernel_effect_op_shape_equals(_effect) return false end
    function Native.NativeKernelEffectOpShape:native_kernel_effect_op_shape_equals(effect) return self.effect:native_kernel_effect_source_shape_equals(effect) end
    function Native.NativeKernelResultOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_result_op_shape_equals ~= nil and other:native_kernel_result_op_shape_equals(self.result) end
    function Native.NativeKernelOpSourceShape:native_kernel_result_op_shape_equals(_result) return false end
    function Native.NativeKernelResultOpShape:native_kernel_result_op_shape_equals(result) return self.result:native_kernel_result_source_shape_equals(result) end
    function Native.NativeKernelProofOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_proof_op_shape_equals ~= nil and other:native_kernel_proof_op_shape_equals(self.proof) end
    function Native.NativeKernelOpSourceShape:native_kernel_proof_op_shape_equals(_proof) return false end
    function Native.NativeKernelProofOpShape:native_kernel_proof_op_shape_equals(proof) return self.proof == proof end
    function Native.NativeKernelPlanOpShape:native_kernel_op_source_shape_equals(other) return other ~= nil and other.native_kernel_plan_op_shape_equals ~= nil and other:native_kernel_plan_op_shape_equals(self.plan) end
    function Native.NativeKernelOpSourceShape:native_kernel_plan_op_shape_equals(_plan) return false end
    function Native.NativeKernelPlanOpShape:native_kernel_plan_op_shape_equals(plan) return self.plan:native_kernel_plan_source_shape_equals(plan) end
    function Native.NativeKernelSourceShapeAxis:native_kernel_axis_equals(other) return other:native_kernel_source_shape_axis_equals(self.shape) end
    function Native.NativeKernelAxis:native_kernel_source_shape_axis_equals(_shape) return false end
    function Native.NativeKernelSourceShapeAxis:native_kernel_source_shape_axis_equals(shape) return self.shape:native_kernel_op_source_shape_equals(shape) end
    function Native.NativeKernelDomainFlowAxis:native_kernel_axis_equals(other) return other:native_kernel_domain_flow_axis_equals() end
    function Native.NativeKernelAxis:native_kernel_domain_flow_axis_equals() return false end
    function Native.NativeKernelDomainFlowAxis:native_kernel_domain_flow_axis_equals() return true end
    function Native.NativeKernelExprValueAxis:native_kernel_axis_equals(other) return other:native_kernel_expr_value_axis_equals() end
    function Native.NativeKernelAxis:native_kernel_expr_value_axis_equals() return false end
    function Native.NativeKernelExprValueAxis:native_kernel_expr_value_axis_equals() return true end
    function Native.NativeKernelExprAlgebraAxis:native_kernel_axis_equals(other) return other:native_kernel_expr_algebra_axis_equals() end
    function Native.NativeKernelAxis:native_kernel_expr_algebra_axis_equals() return false end
    function Native.NativeKernelExprAlgebraAxis:native_kernel_expr_algebra_axis_equals() return true end
    function Native.NativeKernelExprLaneLoadAxis:native_kernel_axis_equals(other) return other:native_kernel_expr_lane_load_axis_equals(self.elem_ty) end
    function Native.NativeKernelAxis:native_kernel_expr_lane_load_axis_equals(_elem_ty) return false end
    function Native.NativeKernelExprLaneLoadAxis:native_kernel_expr_lane_load_axis_equals(elem_ty) return self.elem_ty == elem_ty end
    function Native.NativeKernelExprKernelValueAxis:native_kernel_axis_equals(other) return other:native_kernel_expr_kernel_value_axis_equals() end
    function Native.NativeKernelAxis:native_kernel_expr_kernel_value_axis_equals() return false end
    function Native.NativeKernelExprKernelValueAxis:native_kernel_expr_kernel_value_axis_equals() return true end
    function Native.NativeKernelEffectStoreAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_store_axis_equals(self.elem_ty) end
    function Native.NativeKernelAxis:native_kernel_effect_store_axis_equals(_elem_ty) return false end
    function Native.NativeKernelEffectStoreAxis:native_kernel_effect_store_axis_equals(elem_ty) return self.elem_ty == elem_ty end
    function Native.NativeKernelEffectScanAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_scan_axis_equals(self.reduction, self.mode) end
    function Native.NativeKernelAxis:native_kernel_effect_scan_axis_equals(_reduction, _mode) return false end
    function Native.NativeKernelEffectScanAxis:native_kernel_effect_scan_axis_equals(reduction, mode) return self.reduction == reduction and self.mode == mode end
    function Native.NativeKernelEffectPartitionAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_partition_axis_equals(self.semantics) end
    function Native.NativeKernelAxis:native_kernel_effect_partition_axis_equals(_semantics) return false end
    function Native.NativeKernelEffectPartitionAxis:native_kernel_effect_partition_axis_equals(semantics) return self.semantics == semantics end
    function Native.NativeKernelEffectCopyAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_copy_axis_equals(self.semantics) end
    function Native.NativeKernelAxis:native_kernel_effect_copy_axis_equals(_semantics) return false end
    function Native.NativeKernelEffectCopyAxis:native_kernel_effect_copy_axis_equals(semantics) return self.semantics == semantics end
    function Native.NativeKernelEffectScatterReduceAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_scatter_reduce_axis_equals(self.reducer) end
    function Native.NativeKernelAxis:native_kernel_effect_scatter_reduce_axis_equals(_reducer) return false end
    function Native.NativeKernelEffectScatterReduceAxis:native_kernel_effect_scatter_reduce_axis_equals(reducer) return self.reducer == reducer end
    function Native.NativeKernelEffectFoldAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_fold_axis_equals(self.reduction) end
    function Native.NativeKernelAxis:native_kernel_effect_fold_axis_equals(_reduction) return false end
    function Native.NativeKernelEffectFoldAxis:native_kernel_effect_fold_axis_equals(reduction) return self.reduction == reduction end
    function Native.NativeKernelEffectCallAxis:native_kernel_axis_equals(other) return other:native_kernel_effect_call_axis_equals(self.call) end
    function Native.NativeKernelAxis:native_kernel_effect_call_axis_equals(_call) return false end
    function Native.NativeKernelEffectCallAxis:native_kernel_effect_call_axis_equals(call) return self.call == call end
    function Native.NativeKernelResultVoidAxis:native_kernel_axis_equals(other) return other:native_kernel_result_void_axis_equals() end
    function Native.NativeKernelAxis:native_kernel_result_void_axis_equals() return false end
    function Native.NativeKernelResultVoidAxis:native_kernel_result_void_axis_equals() return true end
    function Native.NativeKernelResultValueAxis:native_kernel_axis_equals(other) return other:native_kernel_result_value_axis_equals() end
    function Native.NativeKernelAxis:native_kernel_result_value_axis_equals() return false end
    function Native.NativeKernelResultValueAxis:native_kernel_result_value_axis_equals() return true end
    function Native.NativeKernelResultFindAxis:native_kernel_axis_equals(other) return other:native_kernel_result_find_axis_equals(self.pred) end
    function Native.NativeKernelAxis:native_kernel_result_find_axis_equals(_pred) return false end
    function Native.NativeKernelResultFindAxis:native_kernel_result_find_axis_equals(pred) return self.pred == pred end
    function Native.NativeKernelResultReductionAxis:native_kernel_axis_equals(other) return other:native_kernel_result_reduction_axis_equals(self.reduction) end
    function Native.NativeKernelAxis:native_kernel_result_reduction_axis_equals(_reduction) return false end
    function Native.NativeKernelResultReductionAxis:native_kernel_result_reduction_axis_equals(reduction) return self.reduction == reduction end
    function Native.NativeKernelResultClosedFormAxis:native_kernel_axis_equals(other) return other:native_kernel_result_closed_form_axis_equals(self.closed_form) end
    function Native.NativeKernelAxis:native_kernel_result_closed_form_axis_equals(_closed_form) return false end
    function Native.NativeKernelResultClosedFormAxis:native_kernel_result_closed_form_axis_equals(closed_form) return self.closed_form == closed_form end
    function Native.NativeKernelResultOriginalControlAxis:native_kernel_axis_equals(other) return other:native_kernel_result_original_control_axis_equals() end
    function Native.NativeKernelAxis:native_kernel_result_original_control_axis_equals() return false end
    function Native.NativeKernelResultOriginalControlAxis:native_kernel_result_original_control_axis_equals() return true end

    function Native.NativeStencilValueSourceShape:native_stencil_value_source_shape_equals(other) return self == other end
    function Native.NativeStencilValueScalarShape:native_stencil_value_source_shape_equals(other) return other ~= nil and other.native_stencil_value_scalar_shape_equals ~= nil and other:native_stencil_value_scalar_shape_equals(self.scalar) end
    function Native.NativeStencilValueSourceShape:native_stencil_value_scalar_shape_equals(_scalar) return false end
    function Native.NativeStencilValueScalarShape:native_stencil_value_scalar_shape_equals(scalar) return self.scalar == scalar end
    function Native.NativeStencilValuePointerShape:native_stencil_value_source_shape_equals(other) return other ~= nil and other.native_stencil_value_pointer_shape_equals ~= nil and other:native_stencil_value_pointer_shape_equals(self.pointer) end
    function Native.NativeStencilValueSourceShape:native_stencil_value_pointer_shape_equals(_pointer) return false end
    function Native.NativeStencilValuePointerShape:native_stencil_value_pointer_shape_equals(pointer) return self.pointer == pointer end
    function Native.NativeStencilValueBytesShape:native_stencil_value_source_shape_equals(other) return other ~= nil and other.native_stencil_value_bytes_shape_equals ~= nil and other:native_stencil_value_bytes_shape_equals(self.size, self.alignment) end
    function Native.NativeStencilValueSourceShape:native_stencil_value_bytes_shape_equals(_size, _alignment) return false end
    function Native.NativeStencilValueBytesShape:native_stencil_value_bytes_shape_equals(size, alignment) return self.size == size and self.alignment == alignment end

    function Native.NativeStencilProducerSourceShape:native_stencil_producer_source_shape_equals(other) return self == other end
    function Native.NativeStencilProducerRange1DShape:native_stencil_producer_source_shape_equals(other) return other ~= nil and other.native_stencil_producer_range_1d_shape_equals ~= nil and other:native_stencil_producer_range_1d_shape_equals(self.index, self.step, self.order) end
    function Native.NativeStencilProducerSourceShape:native_stencil_producer_range_1d_shape_equals(_index, _step, _order) return false end
    function Native.NativeStencilProducerRange1DShape:native_stencil_producer_range_1d_shape_equals(index, step, order) return self.index:native_stencil_value_source_shape_equals(index) and self.step == step and self.order == order end
    function Native.NativeStencilProducerRangeNDShape:native_stencil_producer_source_shape_equals(other) return other ~= nil and other.native_stencil_producer_range_nd_shape_equals ~= nil and other:native_stencil_producer_range_nd_shape_equals(self.rank) end
    function Native.NativeStencilProducerSourceShape:native_stencil_producer_range_nd_shape_equals(_rank) return false end
    function Native.NativeStencilProducerRangeNDShape:native_stencil_producer_range_nd_shape_equals(rank) return self.rank == rank end
    function Native.NativeStencilProducerWindowNDShape:native_stencil_producer_source_shape_equals(other) return other ~= nil and other.native_stencil_producer_window_nd_shape_equals ~= nil and other:native_stencil_producer_window_nd_shape_equals(self.rank, self.window_count) end
    function Native.NativeStencilProducerSourceShape:native_stencil_producer_window_nd_shape_equals(_rank, _window_count) return false end
    function Native.NativeStencilProducerWindowNDShape:native_stencil_producer_window_nd_shape_equals(rank, window_count) return self.rank == rank and self.window_count == window_count end
    function Native.NativeStencilProducerTiledNDShape:native_stencil_producer_source_shape_equals(other) return other ~= nil and other.native_stencil_producer_tiled_nd_shape_equals ~= nil and other:native_stencil_producer_tiled_nd_shape_equals(self.rank, self.tile_count) end
    function Native.NativeStencilProducerSourceShape:native_stencil_producer_tiled_nd_shape_equals(_rank, _tile_count) return false end
    function Native.NativeStencilProducerTiledNDShape:native_stencil_producer_tiled_nd_shape_equals(rank, tile_count) return self.rank == rank and self.tile_count == tile_count end

    function Native.NativeStencilAccessSourceShape:native_stencil_access_source_shape_equals(other) return self == other end
    function Native.NativeStencilAccessScalarShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_scalar_shape_equals ~= nil and other:native_stencil_access_scalar_shape_equals(self.value) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_scalar_shape_equals(_value) return false end
    function Native.NativeStencilAccessScalarShape:native_stencil_access_scalar_shape_equals(value) return self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilAccessContiguousShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_contiguous_shape_equals ~= nil and other:native_stencil_access_contiguous_shape_equals(self.value, self.stride) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_contiguous_shape_equals(_value, _stride) return false end
    function Native.NativeStencilAccessContiguousShape:native_stencil_access_contiguous_shape_equals(value, stride) return self.value:native_stencil_value_source_shape_equals(value) and self.stride == stride end
    function Native.NativeStencilAccessIndexedShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_indexed_shape_equals ~= nil and other:native_stencil_access_indexed_shape_equals(self.value, self.index, self.stride) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_indexed_shape_equals(_value, _index, _stride) return false end
    function Native.NativeStencilAccessIndexedShape:native_stencil_access_indexed_shape_equals(value, index, stride) return self.value:native_stencil_value_source_shape_equals(value) and self.index:native_stencil_value_source_shape_equals(index) and self.stride == stride end
    function Native.NativeStencilAccessAffine1DShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_affine_1d_shape_equals ~= nil and other:native_stencil_access_affine_1d_shape_equals(self.value, self.scale) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_affine_1d_shape_equals(_value, _scale) return false end
    function Native.NativeStencilAccessAffine1DShape:native_stencil_access_affine_1d_shape_equals(value, scale) return self.value:native_stencil_value_source_shape_equals(value) and self.scale == scale end
    function Native.NativeStencilAccessAffineNDShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_affine_nd_shape_equals ~= nil and other:native_stencil_access_affine_nd_shape_equals(self.value, self.term_count) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_affine_nd_shape_equals(_value, _term_count) return false end
    function Native.NativeStencilAccessAffineNDShape:native_stencil_access_affine_nd_shape_equals(value, term_count) return self.value:native_stencil_value_source_shape_equals(value) and self.term_count == term_count end
    function Native.NativeStencilAccessFieldProjectionShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_field_projection_shape_equals ~= nil and other:native_stencil_access_field_projection_shape_equals(self.value, self.field_name) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_field_projection_shape_equals(_value, _field_name) return false end
    function Native.NativeStencilAccessFieldProjectionShape:native_stencil_access_field_projection_shape_equals(value, field_name) return self.value:native_stencil_value_source_shape_equals(value) and self.field_name == field_name end
    function Native.NativeStencilAccessSoAComponentShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_soa_component_shape_equals ~= nil and other:native_stencil_access_soa_component_shape_equals(self.value, self.field_name) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_soa_component_shape_equals(_value, _field_name) return false end
    function Native.NativeStencilAccessSoAComponentShape:native_stencil_access_soa_component_shape_equals(value, field_name) return self.value:native_stencil_value_source_shape_equals(value) and self.field_name == field_name end
    function Native.NativeStencilAccessSliceDescriptorShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_slice_descriptor_shape_equals ~= nil and other:native_stencil_access_slice_descriptor_shape_equals(self.value) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_slice_descriptor_shape_equals(_value) return false end
    function Native.NativeStencilAccessSliceDescriptorShape:native_stencil_access_slice_descriptor_shape_equals(value) return self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilAccessByteSpanDescriptorShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_byte_span_descriptor_shape_equals ~= nil and other:native_stencil_access_byte_span_descriptor_shape_equals(self.value) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_byte_span_descriptor_shape_equals(_value) return false end
    function Native.NativeStencilAccessByteSpanDescriptorShape:native_stencil_access_byte_span_descriptor_shape_equals(value) return self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilAccessViewDescriptorShape:native_stencil_access_source_shape_equals(other) return other ~= nil and other.native_stencil_access_view_descriptor_shape_equals ~= nil and other:native_stencil_access_view_descriptor_shape_equals(self.value, self.has_const_stride) end
    function Native.NativeStencilAccessSourceShape:native_stencil_access_view_descriptor_shape_equals(_value, _has_const_stride) return false end
    function Native.NativeStencilAccessViewDescriptorShape:native_stencil_access_view_descriptor_shape_equals(value, has_const_stride) return self.value:native_stencil_value_source_shape_equals(value) and self.has_const_stride == has_const_stride end

    function Native.NativeStencilPointSourceShape:native_stencil_point_source_shape_equals(other) return self == other end
    function Native.NativeStencilPointInputShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_input_shape_equals ~= nil and other:native_stencil_point_input_shape_equals(self.value) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_input_shape_equals(_value) return false end
    function Native.NativeStencilPointInputShape:native_stencil_point_input_shape_equals(value) return self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilPointWindowInputShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_window_input_shape_equals ~= nil and other:native_stencil_point_window_input_shape_equals(self.value, self.offset_count) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_window_input_shape_equals(_value, _offset_count) return false end
    function Native.NativeStencilPointWindowInputShape:native_stencil_point_window_input_shape_equals(value, offset_count) return self.value:native_stencil_value_source_shape_equals(value) and self.offset_count == offset_count end
    function Native.NativeStencilPointConstShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_const_shape_equals ~= nil and other:native_stencil_point_const_shape_equals(self.value) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_const_shape_equals(_value) return false end
    function Native.NativeStencilPointConstShape:native_stencil_point_const_shape_equals(value) return self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilPointUnaryShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_unary_shape_equals ~= nil and other:native_stencil_point_unary_shape_equals(self.op, self.value) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_unary_shape_equals(_op, _value) return false end
    function Native.NativeStencilPointUnaryShape:native_stencil_point_unary_shape_equals(op, value) return self.op == op and self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilPointBinaryShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_binary_shape_equals ~= nil and other:native_stencil_point_binary_shape_equals(self.op, self.value) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_binary_shape_equals(_op, _value) return false end
    function Native.NativeStencilPointBinaryShape:native_stencil_point_binary_shape_equals(op, value) return self.op == op and self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilPointCastShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_cast_shape_equals ~= nil and other:native_stencil_point_cast_shape_equals(self.op, self.from, self.to) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_cast_shape_equals(_op, _from, _to) return false end
    function Native.NativeStencilPointCastShape:native_stencil_point_cast_shape_equals(op, from, to) return self.op == op and self.from:native_stencil_value_source_shape_equals(from) and self.to:native_stencil_value_source_shape_equals(to) end
    function Native.NativeStencilPointPredicateShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_predicate_shape_equals ~= nil and other:native_stencil_point_predicate_shape_equals(self.pred, self.value) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_predicate_shape_equals(_pred, _value) return false end
    function Native.NativeStencilPointPredicateShape:native_stencil_point_predicate_shape_equals(pred, value) return self.pred:native_kernel_predicate_source_shape_equals(pred) and self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilPointCompareShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_compare_shape_equals ~= nil and other:native_stencil_point_compare_shape_equals(self.cmp, self.value) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_compare_shape_equals(_cmp, _value) return false end
    function Native.NativeStencilPointCompareShape:native_stencil_point_compare_shape_equals(cmp, value) return self.cmp == cmp and self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilPointSelectShape:native_stencil_point_source_shape_equals(other) return other ~= nil and other.native_stencil_point_select_shape_equals ~= nil and other:native_stencil_point_select_shape_equals(self.pred, self.value) end
    function Native.NativeStencilPointSourceShape:native_stencil_point_select_shape_equals(_pred, _value) return false end
    function Native.NativeStencilPointSelectShape:native_stencil_point_select_shape_equals(pred, value) return self.pred:native_kernel_predicate_source_shape_equals(pred) and self.value:native_stencil_value_source_shape_equals(value) end

    function Native.NativeStencilBodySourceShape:native_stencil_body_source_shape_equals(other) return self == other end
    function Native.NativeStencilBodyPointShape:native_stencil_body_source_shape_equals(other) return other ~= nil and other.native_stencil_body_point_shape_equals ~= nil and other:native_stencil_body_point_shape_equals(self.expr) end
    function Native.NativeStencilBodySourceShape:native_stencil_body_point_shape_equals(_expr) return false end
    function Native.NativeStencilBodyPointShape:native_stencil_body_point_shape_equals(expr) return self.expr:native_stencil_point_source_shape_equals(expr) end

    function Native.NativeStencilSinkSourceShape:native_stencil_sink_source_shape_equals(other) return self == other end
    function Native.NativeStencilSinkStoreShape:native_stencil_sink_source_shape_equals(other) return other ~= nil and other.native_stencil_sink_store_shape_equals ~= nil and other:native_stencil_sink_store_shape_equals(self.semantics, self.dst) end
    function Native.NativeStencilSinkSourceShape:native_stencil_sink_store_shape_equals(_semantics, _dst) return false end
    function Native.NativeStencilSinkStoreShape:native_stencil_sink_store_shape_equals(semantics, dst) return self.semantics == semantics and self.dst:native_stencil_access_source_shape_equals(dst) end
    function Native.NativeStencilSinkReduceShape:native_stencil_sink_source_shape_equals(other) return other ~= nil and other.native_stencil_sink_reduce_shape_equals ~= nil and other:native_stencil_sink_reduce_shape_equals(self.value, self.scope, self.semantics) end
    function Native.NativeStencilSinkSourceShape:native_stencil_sink_reduce_shape_equals(_value, _scope, _semantics) return false end
    function Native.NativeStencilSinkReduceShape:native_stencil_sink_reduce_shape_equals(value, scope, semantics) return self.value:native_stencil_value_source_shape_equals(value) and self.scope == scope and self.semantics == semantics end
    function Native.NativeStencilSinkScanShape:native_stencil_sink_source_shape_equals(other) return other ~= nil and other.native_stencil_sink_scan_shape_equals ~= nil and other:native_stencil_sink_scan_shape_equals(self.reducer, self.mode, self.value) end
    function Native.NativeStencilSinkSourceShape:native_stencil_sink_scan_shape_equals(_reducer, _mode, _value) return false end
    function Native.NativeStencilSinkScanShape:native_stencil_sink_scan_shape_equals(reducer, mode, value) return self.reducer:native_kernel_reducer_source_shape_equals(reducer) and self.mode == mode and self.value:native_stencil_value_source_shape_equals(value) end
    function Native.NativeStencilSinkScatterReduceShape:native_stencil_sink_source_shape_equals(other) return other ~= nil and other.native_stencil_sink_scatter_reduce_shape_equals ~= nil and other:native_stencil_sink_scatter_reduce_shape_equals(self.reducer, self.conflicts, self.value) end
    function Native.NativeStencilSinkSourceShape:native_stencil_sink_scatter_reduce_shape_equals(_reducer, _conflicts, _value) return false end
    function Native.NativeStencilSinkScatterReduceShape:native_stencil_sink_scatter_reduce_shape_equals(reducer, conflicts, value) return self.reducer:native_kernel_reducer_source_shape_equals(reducer) and self.conflicts == conflicts and self.value:native_stencil_value_source_shape_equals(value) end

    function Native.NativeStencilScheduleSourceShape:native_stencil_schedule_source_shape_equals(other) return self == other end
    function Native.NativeStencilScheduleScalarShape:native_stencil_schedule_source_shape_equals(other) return other ~= nil and other.native_stencil_schedule_scalar_shape_equals ~= nil and other:native_stencil_schedule_scalar_shape_equals(self.compiler) end
    function Native.NativeStencilScheduleSourceShape:native_stencil_schedule_scalar_shape_equals(_compiler) return false end
    function Native.NativeStencilScheduleScalarShape:native_stencil_schedule_scalar_shape_equals(compiler) return self.compiler == compiler end
    function Native.NativeStencilScheduleAutoVectorShape:native_stencil_schedule_source_shape_equals(other) return other ~= nil and other.native_stencil_schedule_auto_vector_shape_equals ~= nil and other:native_stencil_schedule_auto_vector_shape_equals(self.trip_count) end
    function Native.NativeStencilScheduleSourceShape:native_stencil_schedule_auto_vector_shape_equals(_trip_count) return false end
    function Native.NativeStencilScheduleAutoVectorShape:native_stencil_schedule_auto_vector_shape_equals(trip_count) return self.trip_count == trip_count end
    function Native.NativeStencilScheduleUnrolledShape:native_stencil_schedule_source_shape_equals(other) return other ~= nil and other.native_stencil_schedule_unrolled_shape_equals ~= nil and other:native_stencil_schedule_unrolled_shape_equals(self.factor, self.trip_count) end
    function Native.NativeStencilScheduleSourceShape:native_stencil_schedule_unrolled_shape_equals(_factor, _trip_count) return false end
    function Native.NativeStencilScheduleUnrolledShape:native_stencil_schedule_unrolled_shape_equals(factor, trip_count) return self.factor == factor and self.trip_count == trip_count end
    function Native.NativeStencilScheduleVectorShape:native_stencil_schedule_source_shape_equals(other) return other ~= nil and other.native_stencil_schedule_vector_shape_equals ~= nil and other:native_stencil_schedule_vector_shape_equals(self.feature, self.lane_policy, self.required_alignment, self.tail, self.reduction, self.vector_unroll, self.interleave) end
    function Native.NativeStencilScheduleSourceShape:native_stencil_schedule_vector_shape_equals(_feature, _lane_policy, _required_alignment, _tail, _reduction, _vector_unroll, _interleave) return false end
    function Native.NativeStencilScheduleVectorShape:native_stencil_schedule_vector_shape_equals(feature, lane_policy, required_alignment, tail, reduction, vector_unroll, interleave) return self.feature == feature and self.lane_policy == lane_policy and self.required_alignment == required_alignment and self.tail == tail and self.reduction == reduction and self.vector_unroll == vector_unroll and self.interleave == interleave end

    function Native.NativeStencilProducerAxis:native_stencil_producer_axis_equals(_other) return false end
    function Native.NativeStencilProducerSourceShapeAxis:native_stencil_producer_axis_equals(other) return other:native_stencil_producer_source_shape_axis_equals(self.shape) end
    function Native.NativeStencilProducerAxis:native_stencil_producer_source_shape_axis_equals(_shape) return false end
    function Native.NativeStencilProducerSourceShapeAxis:native_stencil_producer_source_shape_axis_equals(shape) return self.shape:native_stencil_producer_source_shape_equals(shape) end
    function Native.NativeStencilRange1DAxis:native_stencil_producer_axis_equals(other) return other:native_stencil_range_1d_axis_equals(self.index_ty, self.step, self.order) end
    function Native.NativeStencilProducerAxis:native_stencil_range_1d_axis_equals(_index_ty, _step, _order) return false end
    function Native.NativeStencilRange1DAxis:native_stencil_range_1d_axis_equals(index_ty, step, order) return self.index_ty == index_ty and self.step == step and self.order == order end
    function Native.NativeStencilRangeNDAxis:native_stencil_producer_axis_equals(other) return other:native_stencil_range_nd_axis_equals(self.rank) end
    function Native.NativeStencilProducerAxis:native_stencil_range_nd_axis_equals(_rank) return false end
    function Native.NativeStencilRangeNDAxis:native_stencil_range_nd_axis_equals(rank) return self.rank == rank end
    function Native.NativeStencilWindowNDAxis:native_stencil_producer_axis_equals(other) return other:native_stencil_window_nd_axis_equals(self.rank, self.windows) end
    function Native.NativeStencilProducerAxis:native_stencil_window_nd_axis_equals(_rank, _windows) return false end
    function Native.NativeStencilWindowNDAxis:native_stencil_window_nd_axis_equals(rank, windows) return self.rank == rank and value_list_equals(self.windows, windows) end
    function Native.NativeStencilTiledNDAxis:native_stencil_producer_axis_equals(other) return other:native_stencil_tiled_nd_axis_equals(self.rank, self.tile_sizes) end
    function Native.NativeStencilProducerAxis:native_stencil_tiled_nd_axis_equals(_rank, _tile_sizes) return false end
    function Native.NativeStencilTiledNDAxis:native_stencil_tiled_nd_axis_equals(rank, tile_sizes) return self.rank == rank and value_list_equals(self.tile_sizes, tile_sizes) end

    function Native.NativeStencilAccessAxis:native_stencil_access_axis_equals(_other) return false end
    function Native.NativeStencilAccessSourceShapeAxis:native_stencil_access_axis_equals(other) return other:native_stencil_access_source_shape_axis_equals(self.shape) end
    function Native.NativeStencilAccessAxis:native_stencil_access_source_shape_axis_equals(_shape) return false end
    function Native.NativeStencilAccessSourceShapeAxis:native_stencil_access_source_shape_axis_equals(shape) return self.shape:native_stencil_access_source_shape_equals(shape) end
    function Native.NativeStencilLayoutScalarAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_scalar_axis_equals(self.ty) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_scalar_axis_equals(_ty) return false end
    function Native.NativeStencilLayoutScalarAxis:native_stencil_layout_scalar_axis_equals(ty) return self.ty == ty end
    function Native.NativeStencilLayoutContiguousAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_contiguous_axis_equals(self.ty) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_contiguous_axis_equals(_ty) return false end
    function Native.NativeStencilLayoutContiguousAxis:native_stencil_layout_contiguous_axis_equals(ty) return self.ty == ty end
    function Native.NativeStencilLayoutIndexedAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_indexed_axis_equals(self.ty, self.index_ty) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_indexed_axis_equals(_ty, _index_ty) return false end
    function Native.NativeStencilLayoutIndexedAxis:native_stencil_layout_indexed_axis_equals(ty, index_ty) return self.ty == ty and self.index_ty == index_ty end
    function Native.NativeStencilLayoutAffine1DAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_affine_1d_axis_equals(self.ty, self.scale) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_affine_1d_axis_equals(_ty, _scale) return false end
    function Native.NativeStencilLayoutAffine1DAxis:native_stencil_layout_affine_1d_axis_equals(ty, scale) return self.ty == ty and self.scale == scale end
    function Native.NativeStencilLayoutAffineNDAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_affine_nd_axis_equals(self.ty, self.rank) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_affine_nd_axis_equals(_ty, _rank) return false end
    function Native.NativeStencilLayoutAffineNDAxis:native_stencil_layout_affine_nd_axis_equals(ty, rank) return self.ty == ty and self.rank == rank end
    function Native.NativeStencilLayoutFieldProjectionAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_field_projection_axis_equals(self.record_ty, self.field_name) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_field_projection_axis_equals(_record_ty, _field_name) return false end
    function Native.NativeStencilLayoutFieldProjectionAxis:native_stencil_layout_field_projection_axis_equals(record_ty, field_name) return self.record_ty == record_ty and self.field_name == field_name end
    function Native.NativeStencilLayoutSoAComponentAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_soa_component_axis_equals(self.record_ty, self.field_name) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_soa_component_axis_equals(_record_ty, _field_name) return false end
    function Native.NativeStencilLayoutSoAComponentAxis:native_stencil_layout_soa_component_axis_equals(record_ty, field_name) return self.record_ty == record_ty and self.field_name == field_name end
    function Native.NativeStencilLayoutSliceDescriptorAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_slice_descriptor_axis_equals(self.ty) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_slice_descriptor_axis_equals(_ty) return false end
    function Native.NativeStencilLayoutSliceDescriptorAxis:native_stencil_layout_slice_descriptor_axis_equals(ty) return self.ty == ty end
    function Native.NativeStencilLayoutByteSpanDescriptorAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_byte_span_descriptor_axis_equals(self.ty) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_byte_span_descriptor_axis_equals(_ty) return false end
    function Native.NativeStencilLayoutByteSpanDescriptorAxis:native_stencil_layout_byte_span_descriptor_axis_equals(ty) return self.ty == ty end
    function Native.NativeStencilLayoutViewDescriptorAxis:native_stencil_access_axis_equals(other) return other:native_stencil_layout_view_descriptor_axis_equals(self.ty) end
    function Native.NativeStencilAccessAxis:native_stencil_layout_view_descriptor_axis_equals(_ty) return false end
    function Native.NativeStencilLayoutViewDescriptorAxis:native_stencil_layout_view_descriptor_axis_equals(ty) return self.ty == ty end

    function Native.NativeStencilPointAxis:native_stencil_point_axis_equals(_other) return false end
    function Native.NativeStencilPointSourceShapeAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_source_shape_axis_equals(self.shape) end
    function Native.NativeStencilPointAxis:native_stencil_point_source_shape_axis_equals(_shape) return false end
    function Native.NativeStencilPointSourceShapeAxis:native_stencil_point_source_shape_axis_equals(shape) return self.shape:native_stencil_point_source_shape_equals(shape) end
    function Native.NativeStencilPointInputAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_input_axis_equals() end
    function Native.NativeStencilPointAxis:native_stencil_point_input_axis_equals() return false end
    function Native.NativeStencilPointInputAxis:native_stencil_point_input_axis_equals() return true end
    function Native.NativeStencilPointWindowInputAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_window_input_axis_equals(self.offset_count) end
    function Native.NativeStencilPointAxis:native_stencil_point_window_input_axis_equals(_offset_count) return false end
    function Native.NativeStencilPointWindowInputAxis:native_stencil_point_window_input_axis_equals(offset_count) return self.offset_count == offset_count end
    function Native.NativeStencilPointConstAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_const_axis_equals(self.ty) end
    function Native.NativeStencilPointAxis:native_stencil_point_const_axis_equals(_ty) return false end
    function Native.NativeStencilPointConstAxis:native_stencil_point_const_axis_equals(ty) return self.ty == ty end
    function Native.NativeStencilPointUnaryAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_unary_axis_equals(self.op, self.result_ty) end
    function Native.NativeStencilPointAxis:native_stencil_point_unary_axis_equals(_op, _result_ty) return false end
    function Native.NativeStencilPointUnaryAxis:native_stencil_point_unary_axis_equals(op, result_ty) return self.op == op and self.result_ty == result_ty end
    function Native.NativeStencilPointBinaryAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_binary_axis_equals(self.op, self.result_ty) end
    function Native.NativeStencilPointAxis:native_stencil_point_binary_axis_equals(_op, _result_ty) return false end
    function Native.NativeStencilPointBinaryAxis:native_stencil_point_binary_axis_equals(op, result_ty) return self.op == op and self.result_ty == result_ty end
    function Native.NativeStencilPointCastAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_cast_axis_equals(self.op, self.from, self.to) end
    function Native.NativeStencilPointAxis:native_stencil_point_cast_axis_equals(_op, _from, _to) return false end
    function Native.NativeStencilPointCastAxis:native_stencil_point_cast_axis_equals(op, from, to) return self.op == op and self.from == from and self.to == to end
    function Native.NativeStencilPointPredicateAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_predicate_axis_equals(self.pred, self.result_ty) end
    function Native.NativeStencilPointAxis:native_stencil_point_predicate_axis_equals(_pred, _result_ty) return false end
    function Native.NativeStencilPointPredicateAxis:native_stencil_point_predicate_axis_equals(pred, result_ty) return self.pred == pred and self.result_ty == result_ty end
    function Native.NativeStencilPointCompareAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_compare_axis_equals(self.cmp, self.result_ty) end
    function Native.NativeStencilPointAxis:native_stencil_point_compare_axis_equals(_cmp, _result_ty) return false end
    function Native.NativeStencilPointCompareAxis:native_stencil_point_compare_axis_equals(cmp, result_ty) return self.cmp == cmp and self.result_ty == result_ty end
    function Native.NativeStencilPointSelectAxis:native_stencil_point_axis_equals(other) return other:native_stencil_point_select_axis_equals(self.pred, self.result_ty) end
    function Native.NativeStencilPointAxis:native_stencil_point_select_axis_equals(_pred, _result_ty) return false end
    function Native.NativeStencilPointSelectAxis:native_stencil_point_select_axis_equals(pred, result_ty) return self.pred == pred and self.result_ty == result_ty end

    function Native.NativeStencilBodyAxis:native_stencil_body_axis_equals(_other) return false end
    function Native.NativeStencilBodySourceShapeAxis:native_stencil_body_axis_equals(other) return other:native_stencil_body_source_shape_axis_equals(self.shape) end
    function Native.NativeStencilBodyAxis:native_stencil_body_source_shape_axis_equals(_shape) return false end
    function Native.NativeStencilBodySourceShapeAxis:native_stencil_body_source_shape_axis_equals(shape) return self.shape:native_stencil_body_source_shape_equals(shape) end

    function Native.NativeStencilSinkAxis:native_stencil_sink_axis_equals(_other) return false end
    function Native.NativeStencilSinkSourceShapeAxis:native_stencil_sink_axis_equals(other) return other:native_stencil_sink_source_shape_axis_equals(self.shape) end
    function Native.NativeStencilSinkAxis:native_stencil_sink_source_shape_axis_equals(_shape) return false end
    function Native.NativeStencilSinkSourceShapeAxis:native_stencil_sink_source_shape_axis_equals(shape) return self.shape:native_stencil_sink_source_shape_equals(shape) end
    function Native.NativeStencilSinkStoreAxis:native_stencil_sink_axis_equals(other) return other:native_stencil_sink_store_axis_equals(self.semantics) end
    function Native.NativeStencilSinkAxis:native_stencil_sink_store_axis_equals(_semantics) return false end
    function Native.NativeStencilSinkStoreAxis:native_stencil_sink_store_axis_equals(semantics) return self.semantics == semantics end
    function Native.NativeStencilSinkReduceAxis:native_stencil_sink_axis_equals(other) return other:native_stencil_sink_reduce_axis_equals(self.result_ty, self.scope, self.semantics) end
    function Native.NativeStencilSinkAxis:native_stencil_sink_reduce_axis_equals(_result_ty, _scope, _semantics) return false end
    function Native.NativeStencilSinkReduceAxis:native_stencil_sink_reduce_axis_equals(result_ty, scope, semantics) return self.result_ty == result_ty and self.scope == scope and self.semantics == semantics end
    function Native.NativeStencilSinkScanAxis:native_stencil_sink_axis_equals(other) return other:native_stencil_sink_scan_axis_equals(self.reducer, self.mode, self.result_ty) end
    function Native.NativeStencilSinkAxis:native_stencil_sink_scan_axis_equals(_reducer, _mode, _result_ty) return false end
    function Native.NativeStencilSinkScanAxis:native_stencil_sink_scan_axis_equals(reducer, mode, result_ty) return self.reducer == reducer and self.mode == mode and self.result_ty == result_ty end
    function Native.NativeStencilSinkScatterReduceAxis:native_stencil_sink_axis_equals(other) return other:native_stencil_sink_scatter_reduce_axis_equals(self.reducer, self.conflicts, self.result_ty) end
    function Native.NativeStencilSinkAxis:native_stencil_sink_scatter_reduce_axis_equals(_reducer, _conflicts, _result_ty) return false end
    function Native.NativeStencilSinkScatterReduceAxis:native_stencil_sink_scatter_reduce_axis_equals(reducer, conflicts, result_ty) return self.reducer == reducer and self.conflicts == conflicts and self.result_ty == result_ty end

    function Native.NativeStencilScheduleAxis:native_stencil_schedule_axis_equals(_other) return false end
    function Native.NativeStencilScheduleSourceShapeAxis:native_stencil_schedule_axis_equals(other) return other:native_stencil_schedule_source_shape_axis_equals(self.shape) end
    function Native.NativeStencilScheduleAxis:native_stencil_schedule_source_shape_axis_equals(_shape) return false end
    function Native.NativeStencilScheduleSourceShapeAxis:native_stencil_schedule_source_shape_axis_equals(shape) return self.shape:native_stencil_schedule_source_shape_equals(shape) end
    function Native.NativeStencilScheduleScalarAxis:native_stencil_schedule_axis_equals(other) return other:native_stencil_schedule_scalar_axis_equals(self.compiler) end
    function Native.NativeStencilScheduleAxis:native_stencil_schedule_scalar_axis_equals(_compiler) return false end
    function Native.NativeStencilScheduleScalarAxis:native_stencil_schedule_scalar_axis_equals(compiler) return self.compiler == compiler end
    function Native.NativeStencilScheduleAutoVectorAxis:native_stencil_schedule_axis_equals(other) return other:native_stencil_schedule_auto_vector_axis_equals(self.facts) end
    function Native.NativeStencilScheduleAxis:native_stencil_schedule_auto_vector_axis_equals(_facts) return false end
    function Native.NativeStencilScheduleAutoVectorAxis:native_stencil_schedule_auto_vector_axis_equals(facts) return self.facts == facts end
    function Native.NativeStencilScheduleUnrolledAxis:native_stencil_schedule_axis_equals(other) return other:native_stencil_schedule_unrolled_axis_equals(self.factor, self.facts) end
    function Native.NativeStencilScheduleAxis:native_stencil_schedule_unrolled_axis_equals(_factor, _facts) return false end
    function Native.NativeStencilScheduleUnrolledAxis:native_stencil_schedule_unrolled_axis_equals(factor, facts) return self.factor == factor and self.facts == facts end
    function Native.NativeStencilScheduleVectorAxis:native_stencil_schedule_axis_equals(other) return other:native_stencil_schedule_vector_axis_equals(self.feature, self.lane_policy, self.required_alignment, self.tail, self.reduction, self.vector_unroll, self.interleave, self.facts) end
    function Native.NativeStencilScheduleAxis:native_stencil_schedule_vector_axis_equals(_feature, _lane_policy, _required_alignment, _tail, _reduction, _vector_unroll, _interleave, _facts) return false end
    function Native.NativeStencilScheduleVectorAxis:native_stencil_schedule_vector_axis_equals(feature, lane_policy, required_alignment, tail, reduction, vector_unroll, interleave, facts) return self.feature == feature and self.lane_policy == lane_policy and self.required_alignment == required_alignment and self.tail == tail and self.reduction == reduction and self.vector_unroll == vector_unroll and self.interleave == interleave and self.facts == facts end

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

    function Native.NativePatchPtr64:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_ptr64(input)
    end

    function Native.NativePatchRel32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_rel32(input)
    end

    function Native.NativePatchBranchRel32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_branch_rel32(input)
    end

    function Native.NativePatchCallRel32:apply_native_patch(input)
        return input.binding.coordinate:write_native_patch_call_rel32(input)
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
        return write_patch_u32(input, self.offset + (input.addend or 0))
    end

    function Native.NativePatchFrameSize:write_native_patch_imm32(input)
        return write_patch_u32(input, self.size + (input.addend or 0))
    end

    function Native.NativePatchCoordinate:write_native_patch_imm64(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self)
    end

    function Native.NativePatchImmediateI64:write_native_patch_imm64(input)
        return write_patch_u64(input, self.value)
    end

    function Native.NativePatchPointer64:write_native_patch_imm64(input)
        return write_patch_u64(input, self.address)
    end

    function Native.NativePatchCoordinate:write_native_patch_ptr64(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self)
    end

    function Native.NativePatchPointer64:write_native_patch_ptr64(input)
        return write_patch_u64(input, self.address)
    end

    function Native.NativePatchConstantPoolEntry:write_native_patch_ptr64(input)
        local address = constant_pool_entry_address(input, self.entry)
        if address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_u64(input, address)
    end

    function Native.NativePatchCallTarget:write_native_patch_ptr64(input)
        local symbol = runtime_symbol(input, self.symbol)
        if symbol == nil or symbol.address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return symbol.address:write_native_runtime_address_patch(input)
    end

    function Native.NativePatchCodeDataAddress:write_native_patch_ptr64(input)
        local address = module_patch_coordinate_address(input, self)
        if address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_u64(input, address)
    end

    function Native.NativePatchCodeGlobalAddress:write_native_patch_ptr64(input)
        local address = module_patch_coordinate_address(input, self)
        if address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_u64(input, address)
    end

    function Native.NativePatchCodeFuncAddress:write_native_patch_ptr64(input)
        local address = module_patch_coordinate_address(input, self)
        if address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_u64(input, address)
    end

    function Native.NativePatchCodeExternAddress:write_native_patch_ptr64(input)
        local address = module_patch_coordinate_address(input, self)
        if address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_u64(input, address)
    end

    function Native.NativeRuntimeAddressCapability:write_native_runtime_address_patch(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, input.binding.coordinate)
    end

    function Native.NativeRuntimeAddressSupplied:write_native_runtime_address_patch(input)
        return write_patch_u64(input, self.address)
    end

    function Native.NativeRuntimeAddressLinkerSymbol:write_native_runtime_address_patch(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, input.binding.coordinate)
    end

    function Native.NativePatchCoordinate:write_native_patch_rel32(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self)
    end

    function Native.NativePatchBranchTarget:write_native_patch_rel32(input)
        local target_address = input.branch_target_address
        if target_address == nil and input.node_address ~= nil then target_address = input.node_address end
        if target_address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_rel32(input, target_address, input.addend)
    end

    function Native.NativePatchConstantPoolEntry:write_native_patch_rel32(input)
        local target_address = constant_pool_entry_address(input, self.entry)
        if target_address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_rel32(input, target_address, input.addend)
    end

    function Native.NativePatchCodeDataAddress:write_native_patch_rel32(input)
        local target_address = module_patch_coordinate_address(input, self)
        if target_address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_rel32(input, target_address, input.addend)
    end

    function Native.NativePatchCodeGlobalAddress:write_native_patch_rel32(input)
        local target_address = module_patch_coordinate_address(input, self)
        if target_address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_rel32(input, target_address, input.addend)
    end

    function Native.NativePatchCodeFuncAddress:write_native_patch_rel32(input)
        local target_address = module_patch_coordinate_address(input, self)
        if target_address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_rel32(input, target_address, input.addend)
    end

    function Native.NativePatchCodeExternAddress:write_native_patch_rel32(input)
        local target_address = module_patch_coordinate_address(input, self)
        if target_address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return write_patch_rel32(input, target_address, input.addend)
    end

    function Native.NativePatchFrameSize:write_native_patch_rel32(input)
        return write_patch_rel32(input, self.size, input.addend)
    end

    function Native.NativePatchCoordinate:write_native_patch_branch_rel32(input)
        return self:write_native_patch_rel32(input)
    end

    function Native.NativePatchBranchTarget:write_native_patch_branch_rel32(input)
        return self:write_native_patch_rel32(input)
    end

    function Native.NativePatchCoordinate:write_native_patch_call_rel32(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self)
    end

    function Native.NativePatchCallTarget:write_native_patch_call_rel32(input)
        local symbol = runtime_symbol(input, self.symbol)
        if symbol == nil or symbol.address == nil then return Native.NativeInstallRejectWrongCoordinate(input.layout.id, self) end
        return symbol.address:write_native_runtime_rel32_patch(input)
    end

    function Native.NativePatchCodeFuncAddress:write_native_patch_call_rel32(input)
        return self:write_native_patch_rel32(input)
    end

    function Native.NativePatchCodeExternAddress:write_native_patch_call_rel32(input)
        return self:write_native_patch_rel32(input)
    end

    function Native.NativeRuntimeAddressCapability:write_native_runtime_rel32_patch(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, input.binding.coordinate)
    end

    function Native.NativeRuntimeAddressSupplied:write_native_runtime_rel32_patch(input)
        return write_patch_rel32(input, self.address, input.addend)
    end

    function Native.NativeRuntimeAddressLinkerSymbol:write_native_runtime_rel32_patch(input)
        return Native.NativeInstallRejectWrongCoordinate(input.layout.id, input.binding.coordinate)
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

    function Native.NativeCallArg:native_arg_pointer()
        error("lalin.native: call argument is not a pointer-compatible scalar", 3)
    end

    function Native.NativeCallArgI32:native_arg_i32() return self.value end
    function Native.NativeCallArgI32:native_arg_i64() return self.value end
    function Native.NativeCallArgI64:native_arg_i64() return self.value end
    function Native.NativeCallArgF64:native_arg_f64() return self.value end
    function Native.NativeCallArgPtr:native_arg_i64() return self.address end
    function Native.NativeCallArgPtr:native_arg_pointer()
        local f = require_ffi("native executable calls")
        return f.cast("void *", self.address)
    end

    function Native.NativeScalarBool8:native_ffi_c_type() return "uint8_t" end
    function Native.NativeScalarBool8:native_abi_source_type() return Code.CodeTyBool8 end
    function Native.NativeScalarBool8:native_default_extension_policy() return Native.NativeZeroExtend end
    function Native.NativeScalarBool8:native_call_arg_value(arg) return arg:native_arg_i32() end
    function Native.NativeScalarBool8:native_call_result(value) return Native.NativeCallReturnedI32(tonumber(value)) end

    function Native.NativeScalarInt:native_ffi_c_type()
        local prefix = self.signedness == Code.CodeSigned and "int" or "uint"
        return prefix .. tostring(self.bits) .. "_t"
    end
    function Native.NativeScalarInt:native_abi_source_type() return Code.CodeTyInt(self.bits, self.signedness) end
    function Native.NativeScalarInt:native_default_extension_policy()
        if self.signedness == Code.CodeSigned then return Native.NativeSignExtend end
        return Native.NativeZeroExtend
    end
    function Native.NativeScalarInt:native_call_arg_value(arg)
        if self.bits > 32 then return arg:native_arg_i64() end
        return arg:native_arg_i32()
    end
    function Native.NativeScalarInt:native_call_result(value)
        if self.bits > 32 then return Native.NativeCallReturnedI64(tonumber(value)) end
        return Native.NativeCallReturnedI32(tonumber(value))
    end

    function Native.NativeScalarIndex:native_ffi_c_type() return "int" .. tostring(self.bits) .. "_t" end
    function Native.NativeScalarIndex:native_abi_source_type() return Code.CodeTyIndex end
    function Native.NativeScalarIndex:native_default_extension_policy() return Native.NativePreserveLowerBits end
    function Native.NativeScalarIndex:native_call_arg_value(arg) return arg:native_arg_i64() end
    function Native.NativeScalarIndex:native_call_result(value) return Native.NativeCallReturnedI64(tonumber(value)) end

    function Native.NativeScalarPointer:native_ffi_c_type() return "uint" .. tostring(self.bits) .. "_t" end
    function Native.NativeScalarPointer:native_abi_source_type() return Code.CodeTyDataPtr(nil) end
    function Native.NativeScalarPointer:native_default_extension_policy() return Native.NativePreserveLowerBits end
    function Native.NativeScalarPointer:native_call_arg_value(arg) return arg:native_arg_i64() end
    function Native.NativeScalarPointer:native_call_result(value) return Native.NativeCallReturnedI64(tonumber(value)) end

    function Native.NativeScalarFloat:native_ffi_c_type()
        if self.bits == 32 then return "float" end
        return "double"
    end
    function Native.NativeScalarFloat:native_abi_source_type() return Code.CodeTyFloat(self.bits) end
    function Native.NativeScalarFloat:native_default_extension_policy() return Native.NativePreserveLowerBits end
    function Native.NativeScalarFloat:native_call_arg_value(arg) return arg:native_arg_f64() end
    function Native.NativeScalarFloat:native_call_result(value) return Native.NativeCallReturnedF64(tonumber(value)) end

    function Native.NativeAbiProjection:native_ffi_param_c_type()
        error("lalin.native: ABI projection is not a supported FFI parameter", 3)
    end

    function Native.NativeAbiScalarValue:native_ffi_param_c_type() return self.scalar:native_ffi_c_type() end
    function Native.NativeAbiPointerValue:native_ffi_param_c_type() return "void *" end
    function Native.NativeAbiByRefValue:native_ffi_param_c_type() return "void *" end

    function Native.NativeAbiProjection:native_ffi_result_c_type()
        error("lalin.native: ABI projection is not a supported FFI result", 3)
    end

    function Native.NativeAbiVoidResult:native_ffi_result_c_type() return "void" end
    function Native.NativeAbiScalarValue:native_ffi_result_c_type() return self.scalar:native_ffi_c_type() end
    function Native.NativeAbiPointerValue:native_ffi_result_c_type() return "void *" end
    function Native.NativeAbiSRetResult:native_ffi_result_c_type() return "void" end

    function Native.NativeAbiProjection:native_call_arg_value(_arg)
        error("lalin.native: ABI projection cannot consume a scalar call argument", 3)
    end

    function Native.NativeAbiScalarValue:native_call_arg_value(arg) return self.scalar:native_call_arg_value(arg) end
    function Native.NativeAbiPointerValue:native_call_arg_value(arg) return arg:native_arg_pointer() end
    function Native.NativeAbiByRefValue:native_call_arg_value(arg) return arg:native_arg_pointer() end

    function Native.NativeAbiProjection:native_call_result(_value)
        error("lalin.native: ABI projection cannot produce a native call result", 3)
    end

    function Native.NativeAbiVoidResult:native_call_result(_value) return Native.NativeCallReturnedVoid end
    function Native.NativeAbiScalarValue:native_call_result(value) return self.scalar:native_call_result(value) end
    function Native.NativeAbiPointerValue:native_call_result(value)
        local f = require_ffi("native executable calls")
        return Native.NativeCallReturnedI64(tonumber(f.cast("uintptr_t", value)))
    end
    function Native.NativeAbiSRetResult:native_call_result(_value) return Native.NativeCallReturnedVoid end

    function Native.NativeAbiFunctionProjection:native_ffi_signature()
        local params = {}
        for i, param in ipairs(self.params or {}) do
            if param.param_index ~= i - 1 then
                error("lalin.native: ABI parameter projections must be ordered and zero-based", 3)
            end
            params[#params + 1] = param.abi:native_ffi_param_c_type()
        end
        return self.result.abi:native_ffi_result_c_type() .. " (*)(" .. table.concat(params, ", ") .. ")"
    end

    function Native.NativeAbiFunctionProjection:call_native_executable(input)
        local f = require_ffi("native executable calls")
        if #(input.args or {}) ~= #(self.params or {}) then
            error("lalin.native: native call argument count does not match ABI projection", 3)
        end
        local c_args = {}
        for i, param in ipairs(self.params or {}) do
            c_args[#c_args + 1] = param.abi:native_call_arg_value(input.args[i])
        end
        local fn = f.cast(self:native_ffi_signature(), input.executable.entry_address)
        if self.result.abi:native_ffi_result_c_type() == "void" then
            fn(unpack(c_args))
            return self.result.abi:native_call_result(nil)
        end
        return self.result.abi:native_call_result(fn(unpack(c_args)))
    end

    local function scalar_abi_projection(scalar)
        return Native.NativeAbiScalarValue(scalar, scalar:native_default_extension_policy())
    end

    local function legacy_scalar_projection(input, scalar)
        local params = {}
        for i = 1, #(input.args or {}) do
            params[#params + 1] = Native.NativeAbiParamProjection(i - 1, scalar:native_abi_source_type(), scalar_abi_projection(scalar))
        end
        return Native.NativeAbiFunctionProjection(
            input.executable.target,
            params,
            Native.NativeAbiResultProjection(scalar:native_abi_source_type(), scalar_abi_projection(scalar))
        )
    end

    local function no_arg_projection(input, result_abi, result_ty)
        return Native.NativeAbiFunctionProjection(
            input.executable.target,
            {},
            Native.NativeAbiResultProjection(result_ty, result_abi)
        )
    end

    function Native.NativeCallVoid:call_native_executable(input)
        return no_arg_projection(input, Native.NativeAbiVoidResult, nil):call_native_executable(input)
    end

    function Native.NativeCallReturnI32:call_native_executable(input)
        local scalar = Native.NativeScalarInt(32, Code.CodeSigned)
        return no_arg_projection(input, scalar_abi_projection(scalar), scalar:native_abi_source_type()):call_native_executable(input)
    end

    function Native.NativeCallReturnI64:call_native_executable(input)
        local scalar = Native.NativeScalarInt(64, Code.CodeSigned)
        return no_arg_projection(input, scalar_abi_projection(scalar), scalar:native_abi_source_type()):call_native_executable(input)
    end

    function Native.NativeCallReturnF64:call_native_executable(input)
        local scalar = Native.NativeScalarFloat(64)
        return no_arg_projection(input, scalar_abi_projection(scalar), scalar:native_abi_source_type()):call_native_executable(input)
    end

    function Native.NativeCallReturnScalar:call_native_executable(input)
        return legacy_scalar_projection(input, self.scalar):call_native_executable(input)
    end

    function Native.NativeCallCodeSig:call_native_executable(input)
        return self.projection:call_native_executable(input)
    end

    function Native.NativeCallStencilAbi:call_native_executable(input)
        return self.projection:call_native_executable(input)
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
