package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local modules = Schema.modules_for_test()
local saw_native = false
for _, name in ipairs(modules) do
    assert(name ~= "residual", "default schema modules must not load LalinResidual")
    if name == "native" then saw_native = true end
end
assert(saw_native, "default schema modules should load LalinNative")

local T = asdl.context()
Schema(T)
assert(T.LalinNative ~= nil, "LalinNative schema should be defined")
assert(T.LalinResidual == nil, "LalinResidual should not be part of the default schema projection")

require("lalin.native_mc")(T)
local N = T.LalinNative
local Code = T.LalinCode
local Sem = T.LalinSem
local C = T.LalinC
local Core = T.LalinCore
local Type = T.LalinType
local target = N.NativeTarget(
    N.NativeTargetId("schema-native-target"),
    N.NativeArchX64,
    N.NativeOsLinux,
    N.NativeAbiSysV,
    64,
    N.NativeLittleEndian
)
local scalar_i32 = N.NativeScalarInt(32, Code.CodeSigned)
local scalar_ptr = N.NativeScalarPointer(64)
local code_ty_i32 = Code.CodeTyInt(32, Code.CodeSigned)
local abi_i32 = N.NativeAbiScalarValue(scalar_i32, N.NativeSignExtend)
local abi_ptr = N.NativeAbiPointerValue(scalar_ptr)
local descriptor_layout = Sem.LayoutNamed("schema.native", "Descriptor", {}, 16, 8)
local abi_descriptor = N.NativeAbiDescriptorValue(descriptor_layout, {})
local abi_byref = N.NativeAbiByRefValue(code_ty_i32, N.NativeAbiByRefReadonly, 4)
local abi_param0 = N.NativeAbiParamProjection(0, code_ty_i32, abi_i32)
local abi_result = N.NativeAbiResultProjection(code_ty_i32, abi_i32)
local abi_function = N.NativeAbiFunctionProjection(target, { abi_param0 }, abi_result)
local abi_sret = N.NativeAbiSRetResult(code_ty_i32, N.NativeAbiParamProjection(0, code_ty_i32, abi_ptr))
local abi_void_function = N.NativeAbiFunctionProjection(target, {}, N.NativeAbiResultProjection(nil, N.NativeAbiVoidResult))
local runtime_symbol = N.NativeRuntimeSymbol(
    N.NativeRuntimeSymbolId("schema-native-runtime:trap"),
    "lalin_schema_runtime_trap",
    abi_void_function,
    N.NativeRuntimeAddressSupplied(0x1000)
)
local runtime = N.NativeRuntime({ runtime_symbol })
assert(asdl.isa(abi_i32, N.NativeAbiProjection), "NativeAbiScalarValue should be a NativeAbiProjection leaf")
assert(asdl.isa(abi_ptr, N.NativeAbiProjection), "NativeAbiPointerValue should be a NativeAbiProjection leaf")
assert(asdl.isa(abi_descriptor, N.NativeAbiProjection), "NativeAbiDescriptorValue should be a NativeAbiProjection leaf")
assert(asdl.isa(abi_byref, N.NativeAbiProjection), "NativeAbiByRefValue should be a NativeAbiProjection leaf")
assert(asdl.isa(abi_sret, N.NativeAbiProjection), "NativeAbiSRetResult should be a NativeAbiProjection leaf")
assert(asdl.isa(N.NativeAbiVoidResult, N.NativeAbiProjection), "NativeAbiVoidResult should be a NativeAbiProjection leaf")
assert(abi_function.result.abi == abi_i32, "NativeAbiFunctionProjection should carry a typed result projection")
assert(abi_sret.pointer_param.abi == abi_ptr, "NativeAbiSRetResult should name its hidden pointer param projection")
assert(abi_descriptor.layout == descriptor_layout, "NativeAbiDescriptorValue should carry descriptor layout facts")
assert(abi_byref.mutability == N.NativeAbiByRefReadonly, "NativeAbiByRefValue should carry mutability")
assert(runtime.symbols[1].abi == abi_void_function, "NativeRuntimeSymbol should carry a typed ABI projection")
assert(runtime.symbols[1].address.address == 0x1000, "NativeRuntimeSymbol should carry an explicit address capability when supplied")
local register = N.NativeRegister(
    N.NativeRegisterId("schema-native-register:x64:eax"),
    target,
    N.NativeRegisterClassGpr,
    scalar_i32,
    "eax"
)
local value_id = N.NativeTemplateValueId("schema-native-value")
local scalar_representation = N.NativeScalarValueRepresentation(scalar_i32)
local opaque_pointer_representation = N.NativeOpaquePointerValueRepresentation(scalar_ptr, code_ty_i32)
local untyped_pointer_representation = N.NativeUntypedPointerValueRepresentation(scalar_ptr)
local scalar_storage_layout = N.NativeStorageLayout(scalar_representation, 4, 4)
local data_address_target = N.NativeCodeDataAddressTarget(Code.CodeDataId("schema.code.data"), code_ty_i32)
local address_representation = N.NativeAddressValueRepresentation(scalar_ptr, data_address_target)
local object_representation = N.NativeObjectStorageRepresentation(code_ty_i32, 4, 4)
local aggregate_representation = N.NativeAggregateStorageRepresentation(Code.CodeTyArray(code_ty_i32, 1), { scalar_representation }, 1, 4, 4)
local vector_representation = N.NativeVectorStorageRepresentation(Code.CodeTyVector(code_ty_i32, 4), scalar_representation, 4, 16, 16)
local descriptor_representation = N.NativeDescriptorValueRepresentation(descriptor_layout, {
    N.NativeDescriptorRepresentationField("len", 0, scalar_representation),
})
local variant_representation = N.NativeVariantStorageRepresentation(
    code_ty_i32,
    scalar_i32,
    { N.NativeVariantRepresentationCase("some", 1, object_representation) },
    8,
    4
)
assert(asdl.isa(scalar_representation, N.NativeValueRepresentation), "scalar values should use explicit NativeValueRepresentation")
assert(address_representation.target == data_address_target, "address representations should carry typed Code address targets")
assert(opaque_pointer_representation.pointee == code_ty_i32, "opaque pointer representations should carry pointee CodeType")
assert(untyped_pointer_representation.address_scalar == scalar_ptr, "untyped pointer representations should carry pointer scalar")
assert(scalar_storage_layout.representation == scalar_representation, "native storage layouts should carry representation/size/alignment facts")
assert(descriptor_representation.fields[1].representation == scalar_representation, "descriptor representations should carry typed fields")
assert(aggregate_representation.elements[1] == scalar_representation, "aggregate representations should carry element representations")
assert(aggregate_representation.element_count == 1, "aggregate representations should carry element counts without exact-cell lowering side tables")
assert(vector_representation.lanes == 4, "vector storage representations should carry lane counts")
assert(variant_representation.cases[1].payload == object_representation, "variant storage representations should carry payload representation")
local source_i32_type = Type.TScalar(Core.ScalarI32)
local named_code_ty = Code.CodeTyNamed("schema.native", "Named", source_i32_type)
local named_sem_layout = Sem.LayoutNamed("schema.native", "Named", { Sem.FieldLayout("value", 0, source_i32_type) }, 4, 4)
local named_field_layout = N.NativeCodeFieldStorageLayout(
    "value",
    N.NativeCodeSemFieldLayoutRef(Sem.FieldByName("value", source_i32_type)),
    0,
    4,
    4,
    scalar_representation
)
local named_layout_entry = N.NativeCodeNamedLayoutEntry(
    N.NativeCodeNamedLayoutByName("schema.native", "Named", source_i32_type),
    named_code_ty,
    named_sem_layout,
    N.NativeStorageLayout(N.NativeObjectStorageRepresentation(named_code_ty, 4, 4), 4, 4),
    { named_field_layout }
)
local named_decl_layout_entry = N.NativeCodeNamedLayoutEntry(
    N.NativeCodeNamedLayoutByTypeId(Code.CodeTypeId("schema.code.type.Named"), named_code_ty),
    named_code_ty,
    named_sem_layout,
    named_layout_entry.storage,
    { named_field_layout }
)
local c_i32_type = C.CTypeId("schema.native", "int32_t")
local c_struct_type = C.CTypeId("schema.native", "struct imported")
local c_field = C.CFieldLayout(c_struct_type, "value", c_i32_type, 0, 4, 4, nil, nil)
local imported_code_ty = Code.CodeTyImportedC(c_struct_type)
local imported_layout_entry = N.NativeCodeImportedCLayoutEntry(
    c_struct_type,
    imported_code_ty,
    C.CLayoutFact(c_struct_type, 4, 4, { c_field }),
    N.NativeStorageLayout(N.NativeObjectStorageRepresentation(imported_code_ty, 4, 4), 4, 4),
    { N.NativeCodeFieldStorageLayout("value", N.NativeCodeCFieldLayoutRef(c_field), 0, 4, 4, scalar_representation) }
)
local variant_owner_ty = Code.CodeTyNamed("schema.native", "MaybeI32", source_i32_type)
local some_variant = Code.CodeVariantRef(variant_owner_ty, "some", 1, code_ty_i32)
local variant_case_layout = N.NativeCodeVariantCaseLayout(some_variant, some_variant.tag_value, 4, scalar_storage_layout, 8, 4)
local variant_layout_entry = N.NativeCodeVariantLayoutEntry(
    variant_owner_ty,
    scalar_storage_layout,
    0,
    { variant_case_layout },
    N.NativeStorageLayout(N.NativeVariantStorageRepresentation(variant_owner_ty, scalar_i32, { N.NativeVariantRepresentationCase("some", 1, scalar_representation) }, 8, 4), 8, 4)
)
local type_layout_plan = N.NativeCodeTypeLayoutPlan({ named_layout_entry, named_decl_layout_entry }, { imported_layout_entry }, { variant_layout_entry })
assert(asdl.isa(named_layout_entry.key, N.NativeCodeNamedLayoutKey), "named layout entries should carry typed layout keys")
assert(asdl.isa(named_field_layout.field_ref, N.NativeCodeFieldLayoutRef), "field storage layouts should carry typed field refs")
assert(named_layout_entry.fields[1].representation == scalar_representation, "named layout fields should carry native value representations")
assert(named_decl_layout_entry.key.type_id.text == "schema.code.type.Named", "named layout entries can be keyed by CodeTypeId")
assert(imported_layout_entry.fields[1].field_ref.field == c_field, "imported-C layout entries should carry C field refs")
assert(variant_case_layout.payload == scalar_storage_layout, "variant case layouts should carry optional payload storage when present")
assert(type_layout_plan.variants[1].cases[1].variant == some_variant, "type layout plans should carry CodeVariantRef-keyed case layouts")
local aggregate_store_axis = N.NativeCodeInstLayoutFieldStoreAxis(N.NativeCodeAggregateObjectStorage, scalar_i32)
local array_load_axis = N.NativeCodeInstLayoutFieldLoadAxis(N.NativeCodeArrayElementStorage, scalar_i32)
local module_address_axis = N.NativeCodeInstAddressMaterializeAxis(N.NativeCodeAddressMaterializeModuleSymbol, scalar_ptr)
local frame_address_axis = N.NativeCodeInstAddressMaterializeAxis(N.NativeCodeAddressMaterializeFrameSlot, scalar_ptr)
local pointer_offset_axis = N.NativeCodeInstPointerOffsetAxis(scalar_ptr, N.NativeScalarIndex(64))
local variant_ctor_axis = N.NativeCodeInstVariantScalarCtorAxis(scalar_i32, scalar_i32)
local variant_tag_axis = N.NativeCodeInstVariantScalarTagAxis(scalar_i32)
local variant_payload_axis = N.NativeCodeInstVariantScalarPayloadAxis(scalar_i32)
local direct_call_axis = N.NativeCodeInstCallShapeAxis(N.NativeCodeCallDirectTarget, abi_function)
local extern_call_axis = N.NativeCodeInstCallShapeAxis(N.NativeCodeCallExternTarget, abi_function)
local indirect_call_axis = N.NativeCodeInstCallShapeAxis(N.NativeCodeCallIndirectPointer, abi_function)
local closure_call_axis = N.NativeCodeInstCallShapeAxis(N.NativeCodeCallClosurePointer, abi_function)
local void_result_shape = N.NativeCodeResultVoidShape
local scalar_result_shape = N.NativeCodeResultScalarShape(scalar_i32)
local pointer_result_shape = N.NativeCodeResultPointerShape(scalar_ptr)
local descriptor_result_shape = N.NativeCodeResultDescriptorShape(descriptor_layout)
local byref_result_shape = N.NativeCodeResultByRefShape(code_ty_i32, N.NativeAbiByRefReadonly, 4)
local sret_result_shape = N.NativeCodeResultSRetShape(code_ty_i32)
local result_copy_axis = N.NativeCodeInstResultCopyAxis(scalar_result_shape)
local return_shape_axis = N.NativeCodeTermReturnShapeAxis(void_result_shape)
assert(asdl.isa(aggregate_store_axis, N.NativeCodeInstAxis), "layout-parametric aggregate store axes should be CodeInst axes")
assert(asdl.isa(array_load_axis, N.NativeCodeInstAxis), "layout-parametric array load axes should be CodeInst axes")
assert(asdl.isa(module_address_axis, N.NativeCodeInstAxis), "module address materialization axes should be CodeInst axes")
assert(asdl.isa(frame_address_axis, N.NativeCodeInstAxis), "frame address materialization axes should be CodeInst axes")
assert(asdl.isa(pointer_offset_axis, N.NativeCodeInstAxis), "pointer offset axes should be scalar/layout-parametric CodeInst axes")
assert(asdl.isa(variant_ctor_axis, N.NativeCodeInstAxis), "variant ctor axes should be scalar/layout-parametric CodeInst axes")
assert(asdl.isa(direct_call_axis, N.NativeCodeInstAxis), "call shape axes should be CodeInst axes")
assert(asdl.isa(result_copy_axis, N.NativeCodeInstAxis), "result copy axes should be CodeInst axes")
assert(asdl.isa(return_shape_axis, N.NativeCodeTermAxis), "return shape axes should be CodeTerm axes")
assert(asdl.isa(void_result_shape, N.NativeCodeResultShape), "void result shape should be typed")
assert(asdl.isa(scalar_result_shape, N.NativeCodeResultShape), "scalar result shape should be typed")
assert(asdl.isa(pointer_result_shape, N.NativeCodeResultShape), "pointer result shape should be typed")
assert(asdl.isa(descriptor_result_shape, N.NativeCodeResultShape), "descriptor result shape should be typed")
assert(asdl.isa(byref_result_shape, N.NativeCodeResultShape), "byref result shape should be typed")
assert(asdl.isa(sret_result_shape, N.NativeCodeResultShape), "sret result shape should be typed")
assert(asdl.isa(N.NativeCodeCallDirectTarget, N.NativeCodeCallShape), "direct call target shape should be a typed call shape")
assert(asdl.isa(N.NativeCodeCallExternTarget, N.NativeCodeCallShape), "extern call target shape should be a typed call shape")
assert(asdl.isa(N.NativeCodeCallIndirectPointer, N.NativeCodeCallShape), "indirect call target shape should be a typed call shape")
assert(asdl.isa(N.NativeCodeCallClosurePointer, N.NativeCodeCallShape), "closure call target shape should be a typed call shape")
assert(aggregate_store_axis:native_code_inst_axis_equals(N.NativeCodeInstLayoutFieldStoreAxis(N.NativeCodeAggregateObjectStorage, scalar_i32)), "layout field store equality should use storage kind and scalar representation")
assert(not aggregate_store_axis:native_code_inst_axis_equals(N.NativeCodeInstLayoutFieldStoreAxis(N.NativeCodeArrayElementStorage, scalar_i32)), "layout field store equality must distinguish aggregate and array storage shape")
assert(not module_address_axis:native_code_inst_axis_equals(frame_address_axis), "address materialization equality must distinguish module-symbol and frame-slot source shape")
assert(variant_tag_axis:native_code_inst_axis_equals(N.NativeCodeInstVariantScalarTagAxis(scalar_i32)), "variant tag equality should use tag scalar representation")
assert(variant_payload_axis:native_code_inst_axis_equals(N.NativeCodeInstVariantScalarPayloadAxis(scalar_i32)), "variant payload equality should use payload scalar representation")
assert(direct_call_axis:native_code_inst_axis_equals(N.NativeCodeInstCallShapeAxis(N.NativeCodeCallDirectTarget, abi_function)), "call shape equality should use kind and ABI projection")
assert(not direct_call_axis:native_code_inst_axis_equals(extern_call_axis), "call shape equality must distinguish direct and extern call targets")
assert(not indirect_call_axis:native_code_inst_axis_equals(closure_call_axis), "call shape equality must distinguish indirect and closure pointer protocols")
assert(result_copy_axis:native_code_inst_axis_equals(N.NativeCodeInstResultCopyAxis(N.NativeCodeResultScalarShape(scalar_i32))), "result copy equality should use typed result shape")
assert(not result_copy_axis:native_code_inst_axis_equals(N.NativeCodeInstResultCopyAxis(pointer_result_shape)), "result copy equality should distinguish scalar and pointer shapes")
assert(return_shape_axis:native_code_term_axis_equals(N.NativeCodeTermReturnShapeAxis(N.NativeCodeResultVoidShape)), "return shape equality should use typed result shape")
local code_sig = Code.CodeSig(Code.CodeSigId("schema.code.sig"), { code_ty_i32 }, { code_ty_i32 })
local code_func_id = Code.CodeFuncId("schema.code.func")
local code_param = Code.CodeParam(Code.CodeValueId("schema.code.value.param"), "x", code_ty_i32, Code.CodeOriginUnknown)
local code_block_id = Code.CodeBlockId("schema.code.block.entry")
local code_local = Code.CodeLocal(Code.CodeLocalId("schema.code.local"), "tmp", code_ty_i32, Code.CodeResidenceValue, Code.CodeOriginUnknown)
local code_data = Code.CodeData(
    Code.CodeDataId("schema.code.data.plan"),
    "data_plan",
    Code.CodeLinkageLocal,
    4,
    4,
    { Code.CodeDataBytes(0, "abcd") },
    Code.CodeOriginUnknown
)
local code_global = Code.CodeGlobal(
    Code.CodeGlobalId("schema.code.global.plan"),
    "global_plan",
    code_ty_i32,
    Code.CodeLinkageLocal,
    4,
    4,
    {},
    Code.CodeOriginUnknown
)
local code_extern = Code.CodeExtern(Code.CodeExternId("schema.code.extern.plan"), "trap", "lalin_schema_runtime_trap", code_sig.id, Code.CodeOriginUnknown)
local static_bytes_init = N.NativeCodeStaticBytesInit(0, "abcd")
local data_pool_entry = N.NativeConstantPoolEntry(
    N.NativeConstantPoolEntryId("schema.code.data.plan.rodata"),
    N.NativeTemplateBytes("abcd", 4),
    4,
    N.NativeConstantPoolBytes(4, 4)
)
local writable_global_capability = N.NativeWritableDataRuntimeCapability("schema.code.global.plan.storage", 4, 4)
local raw_data_target = N.NativeCodeRawDataAddressTarget(code_data.id, code_data.size, code_data.align)
local data_address_projection = N.NativeCodeAddressProjection(
    raw_data_target,
    N.NativeAddressValueRepresentation(scalar_ptr, raw_data_target),
    N.NativeCodeAddressConstantPoolEntry(data_pool_entry.id)
)
local global_address_projection = N.NativeCodeAddressProjection(
    N.NativeCodeGlobalAddressTarget(code_global.id, code_global.ty),
    N.NativeAddressValueRepresentation(scalar_ptr, N.NativeCodeGlobalAddressTarget(code_global.id, code_global.ty)),
    N.NativeCodeAddressWritableDataRuntime(writable_global_capability)
)
local func_address_projection = N.NativeCodeAddressProjection(
    N.NativeCodeFuncAddressTarget(code_func_id, code_sig.id),
    N.NativeAddressValueRepresentation(scalar_ptr, N.NativeCodeFuncAddressTarget(code_func_id, code_sig.id)),
    N.NativeCodeAddressFunctionEntry(code_func_id, "schema_native_func_entry")
)
local extern_address_projection = N.NativeCodeAddressProjection(
    N.NativeCodeExternAddressTarget(code_extern.id),
    N.NativeAddressValueRepresentation(scalar_ptr, N.NativeCodeExternAddressTarget(code_extern.id)),
    N.NativeCodeAddressRuntimeSymbol(runtime_symbol.id)
)
local local_address_target = N.NativeCodeLocalAddressTarget(code_local.id, code_local.ty)
local place_address_target = N.NativeCodePlaceAddressTarget(Code.CodePlaceLocal(code_local.id, code_local.ty))
local local_address_projection = N.NativeCodeAddressProjection(
    local_address_target,
    N.NativeAddressValueRepresentation(scalar_ptr, local_address_target),
    N.NativeCodeAddressFrameSlot(N.NativeFrameSlotId("schema.native.local.slot"))
)
local place_address_projection = N.NativeCodeAddressProjection(
    place_address_target,
    N.NativeAddressValueRepresentation(scalar_ptr, place_address_target),
    N.NativeCodeAddressFrameSlotOffset(N.NativeFrameSlotId("schema.native.local.slot"), 4)
)
local value_offset_capability = N.NativeCodeAddressValueOffset(code_param.value, 8)
local place_offset_capability = N.NativeCodeAddressPlaceOffset(Code.CodePlaceLocal(code_local.id, code_local.ty), 12)
local place_index_capability = N.NativeCodeAddressPlaceIndexOffset(Code.CodePlaceLocal(code_local.id, code_local.ty), code_param.value, 4, 0)
assert(asdl.isa(value_offset_capability, N.NativeCodeAddressCapability), "value-offset address capability should type-check")
assert(asdl.isa(place_offset_capability, N.NativeCodeAddressCapability), "place-offset address capability should type-check")
assert(asdl.isa(place_index_capability, N.NativeCodeAddressCapability), "place-index address capability should type-check")
local module_address_plan = N.NativeModuleAddressPlan(
    { N.NativeModuleDataAddressEntry(code_data.id, data_address_projection) },
    { N.NativeModuleGlobalAddressEntry(code_global.id, global_address_projection) },
    { N.NativeModuleFuncAddressEntry(code_func_id, func_address_projection) },
    { N.NativeModuleExternAddressEntry(code_extern.id, extern_address_projection) },
    { N.NativeLocalAddressEntry(code_local.id, local_address_projection) },
    { N.NativePlaceAddressEntry(Code.CodePlaceLocal(code_local.id, code_local.ty), place_address_projection) }
)
local function_plan = N.NativeCodeFunctionPlan(
    code_func_id,
    code_sig.id,
    code_sig,
    abi_function,
    func_address_projection,
    { N.NativeCodeValueTypePlanEntry(code_param.value, code_param.ty, scalar_storage_layout) },
    { N.NativeCodeBlockParamPlanEntry(code_block_id, { code_param }) },
    { N.NativeCodeLocalStoragePlanEntry(code_local.id, code_local.name, code_local.ty, code_local.residence, scalar_storage_layout) }
)
local module_plan = N.NativeCodeModulePlan(
    N.NativeCodeModulePlanFromCodeModule(Code.CodeModuleId("schema.code.module")),
    type_layout_plan,
    module_address_plan,
    { N.NativeCodeSignaturePlanEntry(code_sig.id, code_sig, abi_function) },
    { N.NativeCodeFunctionSignaturePlanEntry(code_func_id, code_sig.id, code_sig, abi_function) },
    {
        N.NativeCodeDataStoragePlanEntry(
            code_data.id,
            code_data.name,
            code_data.linkage,
            code_data.size,
            code_data.align,
            N.NativeCodeStaticReadOnly,
            N.NativeCodeStaticConstantPoolBacking(data_pool_entry),
            { static_bytes_init },
            {},
            data_address_projection
        ),
    },
    {
        N.NativeCodeGlobalStoragePlanEntry(
            code_global.id,
            code_global.name,
            code_global.ty,
            code_global.linkage,
            scalar_storage_layout,
            scalar_storage_layout.size,
            scalar_storage_layout.alignment,
            N.NativeCodeStaticWritable,
            N.NativeCodeStaticWritableRuntimeBacking(writable_global_capability),
            {},
            {},
            global_address_projection
        ),
    },
    { N.NativeCodeExternRuntimePlanEntry(code_extern.id, code_extern.symbol, code_extern.sig, runtime_symbol.id, abi_function) },
    { function_plan }
)
local lowering_input = N.NativeCodeLoweringInput(module_plan, function_plan)
assert(asdl.isa(module_plan.origin, N.NativeCodeModulePlanOrigin), "native Code module plans should carry a typed origin")
assert(asdl.isa(raw_data_target, N.NativeCodeAddressTarget), "raw CodeData addresses should have a typed untyped-data address target")
assert(module_plan.signatures[1].abi == abi_function, "native Code module plans should carry a signature/ABI table")
assert(module_plan.function_signatures[1].signature == code_sig, "native Code function signature plans should carry the actual CodeSig")
assert(module_plan.functions[1].abi == abi_function, "native Code function plans should carry the selected ABI projection")
assert(asdl.isa(module_plan.functions[1].entry_address.capability, N.NativeCodeAddressFunctionEntry), "native Code function plans should carry copied entry address facts")
assert(module_plan.data_storage[1].size == code_data.size, "native Code data storage plans should carry concrete size/alignment")
assert(module_plan.data_storage[1].backing.entry == data_pool_entry, "readonly CodeData plans should name constant-pool backing")
assert(asdl.isa(module_plan.data_storage[1].inits[1], N.NativeCodeStaticInit), "CodeData initializers should be native typed static init facts")
assert(module_plan.global_storage[1].storage == scalar_storage_layout, "native Code global storage plans should carry typed storage layouts")
assert(module_plan.global_storage[1].backing.capability == writable_global_capability, "writable globals should carry an explicit runtime storage capability")
assert(module_plan.extern_runtime[1].runtime_symbol == runtime_symbol.id, "native Code extern plans should map to runtime symbols")
assert(lowering_input.active_func.block_params[1].params[1] == code_param, "native Code lowering input should carry per-function block params")
local register_location = N.NativeValueRegisterLocation(register)
local continuation_location = N.NativeValueContinuationArgLocation(0, scalar_representation)
local constant_location = N.NativeValueConstantPoolLocation(N.NativeConstantPoolEntryId("schema.native.const.0"), scalar_representation)
local value_placement = N.NativeValuePlacement(value_id, scalar_representation, register_location)
local continuation_placement = N.NativeValuePlacement(N.NativeTemplateValueId("schema-native-cont-value"), scalar_representation, continuation_location)
local constant_placement = N.NativeValuePlacement(N.NativeTemplateValueId("schema-native-const-value"), scalar_representation, constant_location)
local param_placement = N.NativeAbiParamPlacement(0, scalar_i32, register_location, N.NativeSignExtend)
local result_placement = N.NativeAbiResultPlacement(0, scalar_i32, register_location, N.NativePreserveLowerBits)
local frame_stack_limit = N.NativeFrameStackLimit(256, 16)
local constant_pool_support = N.NativeConstantPoolSupport(0, 0, {})
local support_domain = N.NativeTemplateSupportDomain(
    N.NativeTemplateSupportDomainId("schema-native-support-domain"),
    target,
    runtime,
    { N.NativeScalarSupport(scalar_i32, code_ty_i32, N.NativeSignExtend) },
    { N.NativeRegisterSupport(register, { scalar_i32 }, { N.NativeRegisterUseParam, N.NativeRegisterUseResult }) },
    { N.NativeAbiScalarConvention(scalar_i32, { param_placement }, { result_placement }) },
    { N.NativeCallReturnScalar(scalar_i32) },
    {},
    { N.NativeScratchInteger },
    { N.NativeAccumulatorInteger },
    { 1 },
    { 1 },
    { 1 },
    0,
    0,
    frame_stack_limit,
    N.NativeKernelSourceSupport({}),
    N.NativeStencilSourceSupport({}, {}, {}, {}, {}, {}),
    {},
    {},
    constant_pool_support,
    N.NativeAtomicGccBuiltins
)
assert(support_domain.scalars[1].scalar == scalar_i32, "support domain must carry typed scalar facts")
assert(support_domain.passthrough_int_limit == 0, "support domain should carry explicit passthrough bounds")
assert(support_domain.frame_stack_limit == frame_stack_limit, "support domain should carry a typed frame stack limit")
assert(asdl.isa(support_domain.kernel_sources, N.NativeKernelSourceSupport), "support domain should carry finite Kernel source-shape support")
local kernel_bytes_shape = N.NativeKernelValueBytesShape(16, 8)
local kernel_cast_shape = N.NativeKernelExprCastShape(Core.MachineCastIdentity, N.NativeKernelValueScalarShape(scalar_i32), N.NativeKernelValueScalarShape(scalar_i32))
assert(kernel_bytes_shape.size == 16 and kernel_bytes_shape.alignment == 8, "kernel byte source shape should carry size and alignment")
assert(asdl.isa(N.NativeKernelExprOpShape(kernel_cast_shape), N.NativeKernelOpSourceShape), "kernel cast source shape should type-check as a KernelOp source shape")
assert(asdl.isa(N.NativeRoleKernelLane, N.NativeTemplateRole) and asdl.isa(N.NativeRoleKernelPlan, N.NativeTemplateRole), "kernel source roles should cover lane/body/plan source families")
assert(support_domain.atomic_codegen == N.NativeAtomicGccBuiltins, "support domain should carry typed atomic codegen capability")
assert(#support_domain.register_protocols == 0, "schema smoke should not treat register protocols as a baseline source axis")
local protocol = N.NativeTemplateProtocol(N.NativeCallReturnI32, N.NativeRegisterProtocolNone)
local family = N.NativeTemplateFamily(
    N.NativeTemplateFamilyId("schema.native.family"),
    N.NativeRoleRuntimeCall,
    { N.NativeAxisTarget(target) },
    protocol
)
local metavars = {
    N.NativeStencilScalarMetavar(N.NativeStencilMetavarId("schema.native.metavar.scalar"), { scalar_i32 }),
    N.NativeStencilLocationClassMetavar(N.NativeStencilMetavarId("schema.native.metavar.location"), { N.NativeStencilContinuationArgLocationClass }),
    N.NativeStencilPassthroughIntCountMetavar(N.NativeStencilMetavarId("schema.native.metavar.pass.int"), { 0 }),
    N.NativeStencilPassthroughFloatCountMetavar(N.NativeStencilMetavarId("schema.native.metavar.pass.float"), { 0 }),
    N.NativeStencilControlShapeMetavar(N.NativeStencilMetavarId("schema.native.metavar.control"), { N.NativeStencilControlNext }),
    N.NativeStencilCodeInstMetavar(N.NativeStencilMetavarId("schema.native.metavar.code.inst"), {}),
    N.NativeStencilCodeTermMetavar(N.NativeStencilMetavarId("schema.native.metavar.code.term"), {}),
    N.NativeStencilKernelMetavar(N.NativeStencilMetavarId("schema.native.metavar.kernel"), {}),
    N.NativeStencilProducerMetavar(N.NativeStencilMetavarId("schema.native.metavar.producer"), {}),
    N.NativeStencilAccessMetavar(N.NativeStencilMetavarId("schema.native.metavar.access"), {}),
    N.NativeStencilPointMetavar(N.NativeStencilMetavarId("schema.native.metavar.point"), {}),
    N.NativeStencilSinkMetavar(N.NativeStencilMetavarId("schema.native.metavar.sink"), {}),
    N.NativeStencilScheduleMetavar(N.NativeStencilMetavarId("schema.native.metavar.schedule"), {}),
}
for _, metavar in ipairs(metavars) do
    assert(asdl.isa(metavar, N.NativeStencilMetavar), "NativeStencilMetavar leaves should type-check")
end
local generator = N.NativeStencilGenerator(
    N.NativeStencilGeneratorId("schema.native.generator"),
    family,
    N.NativeChunkStandaloneCallable,
    metavars
)
local configuration = N.NativeStencilConfiguration(
    N.NativeStencilConfigurationId("schema.native.configuration"),
    generator.id,
    {
        N.NativeStencilMetavarBinding(metavars[1].id, N.NativeStencilScalarMetavarValue(scalar_i32)),
        N.NativeStencilMetavarBinding(metavars[2].id, N.NativeStencilLocationClassMetavarValue(N.NativeStencilContinuationArgLocationClass)),
        N.NativeStencilMetavarBinding(metavars[3].id, N.NativeStencilPassthroughIntCountMetavarValue(0)),
        N.NativeStencilMetavarBinding(metavars[4].id, N.NativeStencilPassthroughFloatCountMetavarValue(0)),
        N.NativeStencilMetavarBinding(metavars[5].id, N.NativeStencilControlShapeMetavarValue(N.NativeStencilControlNext)),
    }
)
assert(generator.metavars[1] == metavars[1], "NativeStencilGenerator should carry typed metavars")
assert(configuration.bindings[1].metavar == metavars[1].id, "NativeStencilConfiguration should bind by metavar id")
local signature = N.NativeStencilSignature(N.NativeStencilFrameParam(scalar_i32), {}, {}, {})
local constant_pool_entry = N.NativeConstantPoolEntry(
    N.NativeConstantPoolEntryId("schema.native.const.0"),
    N.NativeTemplateBytes(string.char(0x2A, 0x00, 0x00, 0x00), 4),
    4,
    N.NativeConstantPoolScalarConst(scalar_i32)
)
local constant_pool_layout = N.NativeConstantPoolLayout({ N.NativeConstantPoolLayoutEntry(constant_pool_entry, 0) }, 4, 4)
local hole_ordinal = N.NativeHoleOrdinal(
    N.NativeHoleOrdinalId("schema.native.hole.ordinal"),
    0,
    "LALIN_SCHEMA_HOLE_0",
    N.NativePatchImm32
)
local adapter_first_symbol = N.NativeContinuationSymbol(N.NativeContinuationSymbolId("schema-native-adapter-first"), "schema_native_adapter_first")
local public_abi_extraction = N.NativeExtractPublicAbiAdapter(abi_function, hole_ordinal, 16, adapter_first_symbol)
assert(public_abi_extraction.abi_projection == abi_function, "NativeExtractPublicAbiAdapter should carry an ABI projection")
assert(public_abi_extraction.frame_size_hole == hole_ordinal, "NativeExtractPublicAbiAdapter should carry its frame-size hole ordinal")
local source = N.NativeTemplateSource(
    N.NativeTemplateId("schema.native.source"),
    family,
    generator,
    configuration,
    signature,
    N.NativeExtractStandaloneCallable,
    "lalin_schema_native_source",
    "int lalin_schema_native_source(void) { return 0; }\n",
    {},
    { hole_ordinal },
    {},
    { N.NativeTemplateRelocationHoleOrdinal }
)
local manifest_entry = N.NativeTemplateManifestEntry(
    source.id,
    family,
    generator,
    configuration,
    signature,
    source.extraction,
    source.declared_hole_ordinals,
    source.declared_continuation_ordinals,
    source.declared_relocation_kinds
)
local manifest_group = N.NativeTemplateManifestGroup(generator, generator.chunk_class, { manifest_entry }, 1)
local manifest = N.NativeTemplateSourceManifest(
    N.NativeTemplateManifestId("schema.native.manifest"),
    support_domain.id,
    { manifest_group },
    1
)
assert(manifest.total_count == 1, "template source manifest should carry exact cardinality")
assert(source.configuration == configuration, "NativeTemplateSource should carry its stencil configuration")
local object_section = N.NativeObjectSection(
    N.NativeObjectSectionId("schema.native.object.text"),
    ".text",
    N.NativeTemplateBytes(string.char(0xC3), 1),
    64,
    1,
    1,
    { N.NativeObjectSectionAlloc, N.NativeObjectSectionExecutable }
)
local object_symbol = N.NativeObjectSymbol(
    N.NativeObjectSymbolId("schema.native.object.symbol.entry"),
    "schema_native_entry",
    N.NativeObjectSymbolGlobal,
    N.NativeObjectSymbolFunction,
    object_section.id,
    0,
    1
)
local object_relocation = N.NativeObjectRelocation(
    N.NativeObjectRelocationId("schema.native.object.reloc.hole"),
    object_section.id,
    0,
    N.NativeObjectRelocX64Pc32,
    object_symbol.id,
    -4
)
local object_abs32s_relocation = N.NativeObjectRelocation(
    N.NativeObjectRelocationId("schema.native.object.reloc.abs32s"),
    object_section.id,
    4,
    N.NativeObjectRelocX64Abs32S,
    object_symbol.id,
    0
)
local object_file = N.NativeObjectFile(
    N.NativeObjectFormatElf64X64,
    target,
    N.NativeTemplateBytes("ELF", 3),
    { object_section },
    { object_symbol },
    { object_relocation, object_abs32s_relocation }
)
assert(object_file.relocations[1].kind == N.NativeObjectRelocX64Pc32, "NativeObjectFile should carry x64 ELF relocation facts")
assert(object_file.relocations[2].kind == N.NativeObjectRelocX64Abs32S, "NativeObjectFile should carry x64 signed 32-bit absolute hole relocations")
local extern_hole = N.NativeExternHoleSymbol(hole_ordinal, "lalin_native_hole_schema_0")
local ordinal_relocation = N.NativeRelocationHoleOrdinal(0, hole_ordinal, N.NativePatchPcRel32, -4)
local constant_relocation = N.NativeRelocationConstantPool(4, constant_pool_entry.id, N.NativePatchPcRel32, 0)
local pool_patch = N.NativePatchConstantPoolEntry(constant_pool_entry.id, constant_pool_entry.bytes, code_ty_i32)
assert(extern_hole.ordinal == hole_ordinal, "NativeExternHoleSymbol should bind a C symbol to a hole ordinal")
assert(ordinal_relocation.ordinal == hole_ordinal, "NativeRelocationHoleOrdinal should carry an object-derived hole ordinal")
assert(constant_relocation.entry == constant_pool_entry.id, "NativeRelocationConstantPool should name the pool entry")
assert(constant_relocation.formula == N.NativePatchPcRel32, "NativeRelocationConstantPool should carry a patch formula")
assert(pool_patch.entry == constant_pool_entry.id, "NativePatchConstantPoolEntry should bind by pool entry id")
local malformed_reject = N.NativeBuildRejectMalformedObject(source.id, "bad ELF header")
local missing_ordinal_reject = N.NativeBuildRejectMissingHoleOrdinal(source.id, 0, hole_ordinal.symbol)
local duplicate_ordinal_reject = N.NativeBuildRejectDuplicateHoleOrdinal(source.id, 0, hole_ordinal.symbol)
local missing_cont_reject = N.NativeBuildRejectMissingContinuationRelocation(
    source.id,
    N.NativeContinuationSymbol(N.NativeContinuationSymbolId("schema.native.cont"), "schema_native_cont")
)
local extra_symbol_reject = N.NativeBuildRejectExtraUnresolvedSymbol(source.id, "schema_extra", "not declared")
local object_format_reject = N.NativeBuildRejectUnsupportedObjectFormat(source.id, "ELF32", "expected ELF64 x64")
local pool_reloc_reject = N.NativeBuildRejectUnsupportedConstantPoolRelocation(source.id, 4, "R_X86_64_32", "not admitted")
assert(malformed_reject.reason == "bad ELF header", "malformed object rejects should be typed")
assert(missing_ordinal_reject.ordinal == 0 and duplicate_ordinal_reject.ordinal == 0, "hole ordinal rejects should be typed")
assert(missing_cont_reject.symbol.name == "schema_native_cont", "missing continuation relocation rejects should carry the symbol")
assert(extra_symbol_reject.symbol == "schema_extra", "extra unresolved symbol rejects should be typed")
assert(object_format_reject.format == "ELF32", "unsupported object format rejects should carry the parsed format")
assert(pool_reloc_reject.offset == 4, "unsupported constant-pool relocation rejects should carry the offset")
local code_sig_protocol = N.NativeCallCodeSig(abi_function)
local stencil_abi_protocol = N.NativeCallStencilAbi(abi_function)
assert(code_sig_protocol.projection == abi_function, "NativeCallCodeSig should carry a NativeAbiFunctionProjection")
assert(stencil_abi_protocol.projection == abi_function, "NativeCallStencilAbi should carry a NativeAbiFunctionProjection")
local embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("schema-native-bank"),
    target,
    manifest,
    {
        N.NativeEmbeddedTemplate(
            family,
            N.NativeExtractStandaloneCallable,
            signature,
            N.NativeTextSection(N.NativeTemplateBytes(string.char(0xC3), 1), 1),
            { N.NativeSymbol("schema_native_entry", 0, 1) },
            {},
            {},
            { hole_ordinal },
            { N.NativeTemplateRelocationHoleOrdinal, N.NativeTemplateRelocationConstantPool },
            constant_pool_layout
        ),
    }
)
local imported = N.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, N.NativeEmbeddedBankImported), tostring(imported))
assert(#imported.bank.entries == 1, "embedded native bank should import as NativeTemplateBank")

local node_id = N.NativeTemplateNodeId("schema-native-node")
local node_instance = N.NativeTemplateInstanceId("schema-native-node-instance")
local frame_slot = N.NativeFrameSlot(N.NativeFrameSlotId("schema-native-frame-slot"), scalar_representation, 0, 4, 4)
local frame_layout = N.NativeFrameLayout({ frame_slot }, 16, 16)
local first_symbol = N.NativeContinuationSymbol(N.NativeContinuationSymbolId("schema-native-first"), "schema_native_first")
local second_symbol = N.NativeContinuationSymbol(N.NativeContinuationSymbolId("schema-native-second"), "schema_native_second")
local patch_hole_id = N.NativePatchHoleId("schema.native.patch.hole")
local patch_binding = N.NativePatchBinding(node_id, node_instance, N.NativePatchBindingHoleId(patch_hole_id), N.NativePatchImmediateI32(1))
local ordinal_patch_binding = N.NativePatchBinding(node_id, node_instance, N.NativePatchBindingHoleOrdinal(hole_ordinal.id), N.NativePatchImmediateI32(2))
local data_address_projection = N.NativeCodeAddressProjection(
    data_address_target,
    address_representation,
    N.NativeCodeAddressPatchable(N.NativePatchCodeDataAddress(data_address_target.data))
)
local func_address_target = N.NativeCodeFuncAddressTarget(Code.CodeFuncId("schema.code.func"), Code.CodeSigId("schema.code.sig"))
local func_address_projection = N.NativeCodeAddressProjection(
    func_address_target,
    N.NativeAddressValueRepresentation(scalar_ptr, func_address_target),
    N.NativeCodeAddressBankSymbol("schema_native_func")
)
local extern_address_target = N.NativeCodeExternAddressTarget(Code.CodeExternId("schema.code.extern"))
local extern_address_projection = N.NativeCodeAddressProjection(
    extern_address_target,
    N.NativeAddressValueRepresentation(scalar_ptr, extern_address_target),
    N.NativeCodeAddressRuntimeSymbol(runtime_symbol.id)
)
local global_address_target = N.NativeCodeGlobalAddressTarget(Code.CodeGlobalId("schema.code.global"), code_ty_i32)
local global_address_projection = N.NativeCodeAddressProjection(
    global_address_target,
    N.NativeAddressValueRepresentation(scalar_ptr, global_address_target),
    N.NativeCodeAddressPatchable(N.NativePatchCodeGlobalAddress(global_address_target.global))
)
local local_address_target = N.NativeCodeLocalAddressTarget(Code.CodeLocalId("schema.code.local"), code_ty_i32)
local local_address_projection = N.NativeCodeAddressProjection(
    local_address_target,
    N.NativeAddressValueRepresentation(scalar_ptr, local_address_target),
    N.NativeCodeAddressFrameSlot(frame_slot.id)
)
local place_address_target = N.NativeCodePlaceAddressTarget(Code.CodePlaceLocal(local_address_target.local_id, code_ty_i32))
local place_address_projection = N.NativeCodeAddressProjection(
    place_address_target,
    N.NativeAddressValueRepresentation(scalar_ptr, place_address_target),
    N.NativeCodeAddressConstantPoolEntry(N.NativeConstantPoolEntryId("schema.native.const.0"))
)
local address_plan = N.NativeModuleAddressPlan(
    { N.NativeModuleDataAddressEntry(data_address_target.data, data_address_projection) },
    { N.NativeModuleGlobalAddressEntry(global_address_target.global, global_address_projection) },
    { N.NativeModuleFuncAddressEntry(func_address_target.func, func_address_projection) },
    { N.NativeModuleExternAddressEntry(extern_address_target.extern, extern_address_projection) },
    { N.NativeLocalAddressEntry(local_address_target.local_id, local_address_projection) },
    { N.NativePlaceAddressEntry(place_address_target.place, place_address_projection) }
)
local value_plan = N.NativeValueLocationPlan({ N.NativeCodeValuePlacementEntry(Code.CodeValueId("schema.code.value"), scalar_representation, continuation_placement) }, address_plan)
local frame_plan = N.NativeFrameLayoutPlan(
    { N.NativeFrameValueSlotEntry(Code.CodeValueId("schema.code.value"), scalar_representation, frame_slot) },
    { N.NativeFrameBlockSlotEntry(Code.CodeBlockId("schema.code.block"), { frame_slot }) },
    { N.NativeFrameDirectResultSlot(N.NativeCodeResultScalarShape(scalar_i32), frame_slot) },
    { frame_slot },
    16
)
local conditional_edge = N.NativeConditionalBranchEdge(node_id, node_id, first_symbol, node_id, second_symbol, value_id)
local loop_edge = N.NativeLoopBackedgeEdge(node_id, node_id, first_symbol)
local exit_edge = N.NativeExitEdge(node_id, second_symbol)
local continuation_edge = N.NativeContinuationEdge(node_id, node_id, first_symbol)
local runtime_return_edge = N.NativeRuntimeCallReturnEdge(node_id, node_id, runtime_symbol.id, second_symbol)
local control_plan = N.NativeControlPlan(
    {},
    { conditional_edge, loop_edge, exit_edge, continuation_edge, runtime_return_edge },
    { N.NativeControlBlockEntry(Code.CodeBlockId("schema.code.block"), node_id, { node_id }) },
    { node_id }
)
local edge_copy_plan = N.NativeEdgeCopyPlan({
    N.NativeEdgeCopyEntry(
        Code.CodeBlockId("schema.code.block"),
        Code.CodeBlockId("schema.code.next_block"),
        { N.NativeEdgeCopyValue(Code.CodeValueId("schema.code.value"), Code.CodeValueId("schema.code.next_value"), constant_placement) }
    ),
})
local builder_state = N.NativeCodeGraphBuilderState(value_plan, frame_plan, control_plan, edge_copy_plan, {})
local graph = N.NativeTemplateGraph(
    target,
    N.NativeCallReturnScalar(scalar_i32),
    frame_layout,
    { N.NativeTemplateNode(node_id, node_instance, imported.bank.entries[1], { value_placement }, { value_placement }, { patch_binding, ordinal_patch_binding }) },
    { N.NativeFallthroughEdge(node_id, node_id, first_symbol) },
    { N.NativeRegisterValueEdge(value_id, node_id, node_id, scalar_representation, register) },
    address_plan,
    node_id,
    { node_id }
)
assert(graph.protocol.scalar == scalar_i32, "NativeTemplateGraph should carry graph-level call protocol")
assert(graph.nodes[1].instance == node_instance, "NativeTemplateNode should carry node-local instance identity")
assert(graph.nodes[1].bindings[1].node == node_id, "NativePatchBinding should carry node scope")
assert(graph.nodes[1].bindings[1].instance == node_instance, "NativePatchBinding should carry template-instance scope")
assert(graph.nodes[1].bindings[2].target.ordinal == hole_ordinal.id, "NativePatchBinding should support hole-ordinal targets")
assert(graph.nodes[1].inputs[1].location.register == register, "NativeTemplateNode inputs should carry typed value placements")
assert(graph.frame_layout.slots[1].representation == scalar_representation, "NativeFrameSlot should carry explicit value representation")
assert(graph.value_edges[1].representation == scalar_representation, "NativeValueEdge should carry typed value representations")
assert(graph.value_edges[1].register == register, "NativeValueEdge should carry typed register values, not register strings")
assert(builder_state.value_locations.entries[1].representation == scalar_representation, "NativeValueLocationPlan should carry value representations next to CodeValueId keys")
assert(builder_state.value_locations.entries[1].placement.location.arg_index == 0, "NativeValueLocationPlan should key continuation-arg locations by CodeValueId entries")
assert(builder_state.value_locations.addresses.data[1].projection.capability.coordinate.data == data_address_target.data, "NativeModuleAddressPlan should carry CodeDataId-keyed address projections")
assert(builder_state.value_locations.addresses.globals[1].projection.capability.coordinate.global == global_address_target.global, "NativeModuleAddressPlan should carry CodeGlobalId-keyed address projections")
assert(builder_state.value_locations.addresses.funcs[1].projection.capability.symbol_name == "schema_native_func", "NativeModuleAddressPlan should carry CodeFuncId-keyed address projections")
assert(builder_state.value_locations.addresses.externs[1].projection.capability.symbol == runtime_symbol.id, "NativeModuleAddressPlan should carry CodeExternId-keyed address projections")
assert(builder_state.value_locations.addresses.locals[1].projection.capability.slot == frame_slot.id, "NativeModuleAddressPlan should carry local address capabilities")
assert(builder_state.value_locations.addresses.places[1].projection.capability.entry.text == "schema.native.const.0", "NativeModuleAddressPlan should carry place address capabilities")
assert(builder_state.frame_layout_plan.value_slots[1].representation == scalar_representation, "NativeFrameLayoutPlan should carry slot representations")
assert(builder_state.frame_layout_plan.block_slots[1].block.text == "schema.code.block", "NativeFrameLayoutPlan should carry CodeBlockId-keyed entries")
assert(builder_state.control_plan.edges[1].then_symbol == first_symbol, "NativeControlPlan branch edges should carry continuation symbols")
assert(builder_state.control_plan.edges[2].symbol == first_symbol, "NativeLoopBackedgeEdge should carry a continuation symbol")
assert(builder_state.control_plan.edges[3].symbol == second_symbol, "NativeExitEdge should carry a continuation symbol")
assert(builder_state.control_plan.edges[4].symbol == first_symbol, "NativeContinuationEdge should carry a continuation symbol")
assert(builder_state.control_plan.edges[5].return_symbol == second_symbol, "NativeRuntimeCallReturnEdge should carry a return continuation symbol")
assert(builder_state.edge_copy_plan.entries[1].values[1].placement.location.entry.text == "schema.native.const.0", "NativeEdgeCopyPlan should carry constant-pool value placements")

io.write("lalin schema_native ok\n")
