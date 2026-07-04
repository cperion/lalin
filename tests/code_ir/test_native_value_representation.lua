package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.native_backend")(T)

local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local Sem = T.LalinSem
local Type = T.LalinType
local C = T.LalinC
local Backend = require("lalin.native_backend")(T)
local target = Backend.host_target()

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local i32_layout = i32:native_storage_layout(target)
assert(asdl.isa(i32_layout.representation, Native.NativeScalarValueRepresentation), "i32 storage should be an explicit scalar representation")
assert(i32_layout.size == 4 and i32_layout.alignment == 4, "i32 storage layout should be 4-byte aligned")

local ptr_layout = Code.CodeTyDataPtr(nil):native_storage_layout(target)
assert(asdl.isa(ptr_layout.representation, Native.NativeUntypedPointerValueRepresentation), "opaque data pointers without pointee should be untyped pointer representations")
local typed_ptr_layout = Code.CodeTyDataPtr(i32):native_storage_layout(target)
assert(asdl.isa(typed_ptr_layout.representation, Native.NativeOpaquePointerValueRepresentation), "typed data pointers should carry pointee CodeType")
assert(typed_ptr_layout.representation.pointee == i32, "typed pointer representation should preserve pointee type")

local slice_layout = Code.CodeTySlice(i32):native_storage_layout(target)
assert(asdl.isa(slice_layout.representation, Native.NativeDescriptorValueRepresentation), "slice storage should be a descriptor representation")
assert(slice_layout.size == 16 and #slice_layout.representation.fields == 2, "slice descriptor should carry data and len fields")
local view_layout = Code.CodeTyView(i32):native_storage_layout(target)
assert(view_layout.size == 24 and #view_layout.representation.fields == 3, "view descriptor should carry data, len, and stride fields")
local closure_layout = Code.CodeTyClosure(Code.CodeSigId("native.value.rep.sig")):native_storage_layout(target)
assert(closure_layout.size == 16 and closure_layout.representation.fields[1].field_name == "fn", "closure storage should be a two-pointer descriptor")

local array_layout = Code.CodeTyArray(i32, 3):native_storage_layout(target)
assert(asdl.isa(array_layout.representation, Native.NativeAggregateStorageRepresentation), "array storage should be aggregate storage")
assert(array_layout.size == 12 and array_layout.representation.element_count == 3, "array storage should multiply element layout by count")
local vector_layout = Code.CodeTyVector(i32, 4):native_storage_layout(target)
assert(asdl.isa(vector_layout.representation, Native.NativeVectorStorageRepresentation), "vector storage should be vector storage")
assert(vector_layout.size == 16 and vector_layout.representation.lanes == 4, "vector storage should preserve lane count and byte size")

local source_i32 = Type.TScalar(Core.ScalarI32)
local named_source = Type.TNamed(Type.TypeRefGlobal("native.value", "Named"))
local named_ty = Code.CodeTyNamed("native.value", "Named", named_source)
local named_sem_layout = Sem.LayoutNamed("native.value", "Named", { Sem.FieldLayout("value", 0, source_i32) }, 4, 4)
local module_facts = Code.CodeBackModuleFacts(
    {},
    {},
    {},
    Code.CodeValueSemanticsProjection({}, {}),
    {},
    Code.CodeBackReadonlyProjection({}),
    Sem.LayoutEnv({ named_sem_layout }),
    nil
)
local code_module = Code.CodeModule(
    Code.CodeModuleId("native.value.module"),
    {},
    { Code.CodeTypeDecl(Code.CodeTypeId("native.value.Named"), "Named", named_ty, Code.CodeOriginUnknown) },
    {},
    {},
    {},
    {},
    Code.CodeOriginUnknown
)
local type_layout_plan = code_module:native_code_type_layout_plan(module_facts, target)
assert(#type_layout_plan.named == 1, "CodeModule layout projection should include named type declarations")
local named_layout = named_ty:native_storage_layout(target, type_layout_plan)
assert(named_layout.size == 4 and named_layout.alignment == 4, "CodeTyNamed storage should come from NativeCodeNamedLayoutEntry")
assert(type_layout_plan.named[1].fields[1].field_name == "value", "named layout entries should carry field storage projections")

local c_i32 = C.CTypeId("native.value", "int32_t")
local c_struct = C.CTypeId("native.value", "struct imported")
local c_field = C.CFieldLayout(c_struct, "value", c_i32, 0, 4, 4, nil, nil)
local imported_entry = C.CLayoutFact(c_struct, 4, 4, { c_field }):native_code_imported_c_layout_entry()
local imported_plan = Native.NativeCodeTypeLayoutPlan({}, { imported_entry }, {})
local imported_layout = Code.CodeTyImportedC(c_struct):native_storage_layout(target, imported_plan)
assert(imported_layout.size == 4 and imported_entry.fields[1].field_ref.field == c_field, "CodeTyImportedC storage should require imported-C layout entries")

local lowering_sig = Code.CodeSig(Code.CodeSigId("native.value.lowering.sig"), { i32 }, { i32 })
local lowering_func_id = Code.CodeFuncId("native.value.lowering.func")
local lowering_param = Code.CodeParam(Code.CodeValueId("native.value.lowering.param"), "x", i32, Code.CodeOriginUnknown)
local lowering_term = Code.CodeTerm(Code.CodeTermId("native.value.lowering.term"), Code.CodeTermReturn({ lowering_param.value }), Code.CodeOriginUnknown)
local lowering_block = Code.CodeBlock(Code.CodeBlockId("native.value.lowering.entry"), "entry", {}, {}, lowering_term, Code.CodeOriginUnknown)
local lowering_func = Code.CodeFunc(
    lowering_func_id,
    "lowering_func",
    Code.CodeLinkageLocal,
    lowering_sig.id,
    { lowering_param },
    {},
    lowering_block.id,
    { lowering_block },
    Code.CodeOriginUnknown
)
local lowering_data = Code.CodeData(
    Code.CodeDataId("native.value.lowering.data"),
    "lowering_data",
    Code.CodeLinkageLocal,
    4,
    4,
    { Code.CodeDataBytes(0, "data") },
    Code.CodeOriginUnknown
)
local lowering_global = Code.CodeGlobal(
    Code.CodeGlobalId("native.value.lowering.global"),
    "lowering_global",
    i32,
    Code.CodeLinkageLocal,
    4,
    4,
    {},
    Code.CodeOriginUnknown
)
local lowering_extern = Code.CodeExtern(Code.CodeExternId("native.value.lowering.extern"), "extern_add", "native_value_extern_add", lowering_sig.id, Code.CodeOriginUnknown)
local lowering_module = Code.CodeModule(
    Code.CodeModuleId("native.value.lowering.module"),
    { lowering_sig },
    {},
    { lowering_data },
    { lowering_global },
    { lowering_extern },
    { lowering_func },
    Code.CodeOriginUnknown
)
local lowering_runtime_symbol = Native.NativeRuntimeSymbol(
    Native.NativeRuntimeSymbolId("native.value.lowering.runtime.extern_add"),
    lowering_extern.symbol,
    lowering_sig:native_abi_projection(target),
    Native.NativeRuntimeAddressSupplied(0x1234)
)
local lowering_runtime = Native.NativeRuntime({ lowering_runtime_symbol })
local lowering_manifest = Native.NativeTemplateSourceManifest(
    Native.NativeTemplateManifestId("native.value.lowering.empty.manifest"),
    Native.NativeTemplateSupportDomainId("native.value.lowering.empty.domain"),
    {},
    0
)
local lowering_bank = Native.NativeTemplateBank(Native.NativeBankId("native.value.lowering.empty.bank"), target, lowering_manifest, {})
local lowering_plan = Native.NativePlanInput(target, lowering_runtime, lowering_bank)
local lowering_input = lowering_module:native_code_lowering_input(module_facts, lowering_func, lowering_plan)
assert(#lowering_input.module.signatures == 1, "CodeBackModuleFacts native lowering should populate signature ABI entries")
assert(asdl.isa(lowering_input.module.addresses.data[1].projection.capability, Native.NativeCodeAddressConstantPoolEntry), "readonly CodeData should project to constant-pool address capability")
assert(asdl.isa(lowering_input.module.data_storage[1].inits[1], Native.NativeCodeStaticBytesInit), "CodeData bytes init should become a typed native static init")
assert(lowering_input.module.data_storage[1].backing.entry.bytes.bytes == "data", "CodeData constant-pool backing should materialize readonly bytes")
assert(asdl.isa(lowering_input.module.global_storage[1].backing, Native.NativeCodeStaticWritableRuntimeBacking), "CodeGlobal storage should require explicit writable runtime backing")
assert(lowering_input.module.extern_runtime[1].runtime_symbol == lowering_runtime_symbol.id, "CodeExtern lowering should map to a typed runtime symbol")
assert(lowering_input.active_func.value_types[1].value == lowering_param.value, "active function plans should carry value type/storage facts")
assert(asdl.isa(Code.CodeGlobalRefData(lowering_data.id):native_address_patch_coordinate(target), Native.NativePatchCodeDataAddress), "CodeGlobalRefData should lower through typed module data address coordinates")
assert(asdl.isa(Code.CodeGlobalRefGlobal(lowering_global.id):native_address_patch_coordinate(target), Native.NativePatchCodeGlobalAddress), "CodeGlobalRefGlobal should lower through typed module global address coordinates")
assert(asdl.isa(Code.CodeGlobalRefFunc(lowering_func_id):native_address_patch_coordinate(target), Native.NativePatchCodeFuncAddress), "CodeGlobalRefFunc should lower through typed module function address coordinates")
assert(asdl.isa(Code.CodeGlobalRefExtern(lowering_extern.id):native_address_patch_coordinate(target), Native.NativePatchCodeExternAddress), "CodeGlobalRefExtern should lower through typed module extern address coordinates")

local variant_ref = Code.CodeVariantRef(named_ty, "some", 1, i32)
local variant_case = Native.NativeCodeVariantCaseLayout(variant_ref, 1, 4, i32_layout, 8, 4)
local variant_entry = Native.NativeCodeVariantLayoutEntry(
    named_ty,
    i32_layout,
    0,
    { variant_case },
    Native.NativeStorageLayout(Native.NativeVariantStorageRepresentation(named_ty, Native.NativeScalarInt(32, Code.CodeUnsigned), { Native.NativeVariantRepresentationCase("some", 1, i32_layout.representation) }, 8, 4), 8, 4)
)
local variant_plan = Native.NativeCodeTypeLayoutPlan({}, {}, { variant_entry })
assert(variant_ref:native_storage_layout(target, variant_plan).size == 8, "CodeVariantRef storage should require NativeCodeVariantLayoutEntry")
assert(variant_ref:native_payload_storage_layout(target, variant_plan) == i32_layout, "CodeVariantRef payload layout should come from NativeCodeVariantCaseLayout")
assert(named_ty:native_storage_layout(target, variant_plan).representation.cases[1].payload == i32_layout.representation, "variant owner storage should come from NativeCodeVariantLayoutEntry when present")

local local_place = Code.CodePlaceLocal(Code.CodeLocalId("native.value.local"), i32)
local global_place = Code.CodePlaceGlobal(Code.CodeGlobalId("native.value.global"), i32)
local data_place = Code.CodePlaceData(Code.CodeDataId("native.value.data"), i32)
local deref_place = Code.CodePlaceDeref(Code.CodeValueId("native.value.ptr"), i32, 4)
local field_place = Code.CodePlaceField(local_place, Sem.FieldByName("x", Type.TScalar(Core.ScalarI32)), i32, 4, 4, 4)
local index_place = Code.CodePlaceIndex(local_place, Code.CodeValueId("native.value.index"), i32, 4)
local bytes_place = Code.CodePlaceBytes(Code.CodeValueId("native.value.bytes"), 1, i32, 4, 4)

assert(asdl.isa(local_place:native_code_address_target(target), Native.NativeCodeLocalAddressTarget), "local places should project to local address targets")
assert(asdl.isa(global_place:native_code_address_target(target), Native.NativeCodeGlobalAddressTarget), "global places should project to global address targets")
assert(asdl.isa(data_place:native_code_address_target(target), Native.NativeCodeDataAddressTarget), "data places should project to data address targets")
assert(asdl.isa(deref_place:native_code_address_target(target), Native.NativeCodePlaceAddressTarget), "deref places should project to composite place address targets")
assert(asdl.isa(field_place:native_code_address_target(target), Native.NativeCodePlaceAddressTarget), "field places should project to composite place address targets")
assert(asdl.isa(index_place:native_code_address_target(target), Native.NativeCodePlaceAddressTarget), "index places should project to composite place address targets")
assert(asdl.isa(bytes_place:native_code_address_target(target), Native.NativeCodePlaceAddressTarget), "bytes places should project to composite place address targets")
assert(asdl.isa(global_place:native_address_patch_coordinate(target), Native.NativePatchCodeGlobalAddress), "global places should expose code-global address patch coordinates")
assert(asdl.isa(data_place:native_address_patch_coordinate(target), Native.NativePatchCodeDataAddress), "data places should expose code-data address patch coordinates")
assert(field_place:native_storage_layout(target).size == 4, "field places should expose typed storage layouts")
assert(field_place:native_field_storage_layout(target).offset == 4, "field place storage layouts should preserve field offsets")
assert(index_place:native_storage_layout(target).size == 4, "index places should verify element storage size")
assert(bytes_place:native_storage_layout(target).alignment == 4, "byte places should carry explicit byte storage alignment")

local slot = Native.NativeFrameSlot(Native.NativeFrameSlotId("native.value.local.slot"), i32_layout.representation, 0, 4, 4)
local projection = local_place:native_code_address_projection(target, local_place:native_address_capability_for_frame_slot(slot))
assert(projection.capability.slot == slot.id, "local address projections should carry frame-slot address capability")

local address_local = Code.CodeLocal(Code.CodeLocalId("native.value.address.local"), "addr_local", i32, Code.CodeResidenceAddressed, Code.CodeOriginUnknown)
local address_index_value = Code.CodeValueId("native.value.address.index")
local address_bytes_value = Code.CodeValueId("native.value.address.bytes")
local address_func = Code.CodeFunc(
    Code.CodeFuncId("native.value.address.func"),
    "address_func",
    Code.CodeLinkageLocal,
    lowering_sig.id,
    { Code.CodeParam(address_index_value, "idx", i32, Code.CodeOriginUnknown), Code.CodeParam(address_bytes_value, "bytes", i32, Code.CodeOriginUnknown) },
    { address_local },
    lowering_block.id,
    { lowering_block },
    Code.CodeOriginUnknown
)
local address_module = Code.CodeModule(
    Code.CodeModuleId("native.value.address.module"),
    { lowering_sig },
    {},
    {},
    {},
    {},
    { address_func },
    Code.CodeOriginUnknown
)
local address_lowering = address_module:native_code_lowering_input(module_facts, address_func, lowering_plan)
local address_state = Native.NativeCodeGraphBuilderState(
    Native.NativeValueLocationPlan({}, address_lowering.module.addresses),
    Native.NativeFrameLayoutPlan({}, {}, {}, {}, 0),
    Native.NativeControlPlan({}, {}, {}, {}),
    Native.NativeEdgeCopyPlan({}),
    {}
)
local index_slot = Native.NativeFrameSlot(Native.NativeFrameSlotId("native.value.address.index.slot"), i32_layout.representation, 16, 4, 4)
local bytes_slot = Native.NativeFrameSlot(Native.NativeFrameSlotId("native.value.address.bytes.slot"), i32_layout.representation, 32, 4, 4)
address_state.value_locations.entries[#address_state.value_locations.entries + 1] = Native.NativeCodeValuePlacementEntry(
    address_index_value,
    i32_layout.representation,
    Native.NativeValuePlacement(Native.NativeTemplateValueId("native.value.address.index.placement"), i32_layout.representation, Native.NativeValueFrameSlotLocation(index_slot))
)
address_state.value_locations.entries[#address_state.value_locations.entries + 1] = Native.NativeCodeValuePlacementEntry(
    address_bytes_value,
    i32_layout.representation,
    Native.NativeValuePlacement(Native.NativeTemplateValueId("native.value.address.bytes.placement"), i32_layout.representation, Native.NativeValueFrameSlotLocation(bytes_slot))
)
local address_build = Native.NativeCodeGraphBuildInput(lowering_plan, address_lowering, address_state)
local planned_local_place = Code.CodePlaceLocal(address_local.id, address_local.ty)
local planned_field_place = Code.CodePlaceField(planned_local_place, Sem.FieldByName("value", Type.TScalar(Core.ScalarI32)), i32, 4, 4, 4)
local planned_index_place = Code.CodePlaceIndex(planned_local_place, address_index_value, i32, 4)
local planned_bytes_place = Code.CodePlaceBytes(address_bytes_value, 1, i32, 4, 4)
planned_local_place:append_native_place_address_plan(address_build)
planned_field_place:append_native_place_address_plan(address_build)
planned_index_place:append_native_place_address_plan(address_build)
planned_bytes_place:append_native_place_address_plan(address_build)
assert(#address_state.value_locations.addresses.locals == 1, "address planning should create one ASDL local address entry")
assert(asdl.isa(address_state.value_locations.addresses.locals[1].projection.capability, Native.NativeCodeAddressFrameSlot), "local address entries should be backed by frame slots")
assert(#address_state.value_locations.addresses.places == 4, "address planning should create ASDL place address entries")
assert(asdl.isa(address_state.value_locations.addresses.places[2].projection.capability, Native.NativeCodeAddressPlaceOffset), "field place entries should carry typed base-place offsets")
assert(address_state.value_locations.addresses.places[2].projection.capability.offset == 4, "field place address entries should preserve field byte offsets")
assert(asdl.isa(address_state.value_locations.addresses.places[3].projection.capability, Native.NativeCodeAddressPlaceIndexOffset), "index place entries should carry typed index/element-size facts")
assert(address_state.value_locations.addresses.places[3].projection.capability.elem_size == 4, "index place entries should preserve element size")
assert(asdl.isa(address_state.value_locations.addresses.places[4].projection.capability, Native.NativeCodeAddressValueOffset), "bytes place entries should carry typed base-value offsets")
assert(address_state.frame_layout_plan.slots[1].id.text == "native.frame.local." .. address_local.id.text, "addressed locals should allocate NativeFrameSlot storage")

io.write("native value representation ok\n")
