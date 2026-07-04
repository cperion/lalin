package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local N = T.LalinNative
local Code = T.LalinCode
local scalar_i32 = N.NativeScalarInt(32, Code.CodeSigned)
local code_ty_i32 = Code.CodeTyInt(32, Code.CodeSigned)
local signature_i32 = N.NativeStencilSignature(N.NativeStencilFrameParam(scalar_i32), {}, {}, {})
local empty_constant_pool_layout = N.NativeConstantPoolLayout({}, 0, 1)

local function target(id)
    return N.NativeTarget(
        N.NativeTargetId(id),
        N.NativeArchX64,
        N.NativeOsLinux,
        N.NativeAbiSysV,
        64,
        N.NativeLittleEndian
    )
end

local function family(target_value, id)
    return N.NativeTemplateFamily(
        N.NativeTemplateFamilyId(id),
        N.NativeRoleRuntimeCall,
        { N.NativeAxisTarget(target_value) },
        N.NativeTemplateProtocol(N.NativeCallReturnI32, N.NativeRegisterProtocolNone)
    )
end

local function manifest(id, total_count)
    return N.NativeTemplateSourceManifest(
        N.NativeTemplateManifestId(id),
        N.NativeTemplateSupportDomainId(id .. ".support"),
        {},
        total_count
    )
end

local target_a = target("native-mc-target-a")
local target_b = target("native-mc-target-b")
local family_a = family(target_a, "native.mc.return_i32")
local hole_id = N.NativePatchHoleId("imm32:return")
local hole = N.NativeHoleLayout(hole_id, "return_imm", 1, 4, N.NativePatchImm32)
local hole_ordinal = N.NativeHoleOrdinal(N.NativeHoleOrdinalId("imm32:return:ordinal"), 0, hole.symbol, hole.hole)
local bytes = N.NativeTextSection(N.NativeTemplateBytes(string.char(0xB8, 0, 0, 0, 0, 0xC3), 6), 16)
local embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("native-mc-bank"),
    target_a,
    manifest("native-mc-bank.manifest", 1),
    {
        N.NativeEmbeddedTemplate(
            family_a,
            N.NativeExtractStandaloneCallable,
            signature_i32,
            bytes,
            { N.NativeSymbol("native_mc_return_i32", 0, 6) },
            {},
            { hole },
            { hole_ordinal },
            {},
            empty_constant_pool_layout
        ),
    }
)

local imported = N.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, N.NativeEmbeddedBankImported), tostring(imported))
assert(#imported.bank.entries == 1, "expected one native template bank entry")

local selected = imported.bank:select_native_template(N.NativeTemplateSelectionInput(target_a, family_a))
assert(asdl.isa(selected, N.NativeTemplateSelected), tostring(selected))

local mismatch = imported.bank:select_native_template(N.NativeTemplateSelectionInput(target_b, family_a))
assert(asdl.isa(mismatch, N.NativeTemplateSelectionRejected), tostring(mismatch))
assert(asdl.isa(mismatch.rejects[1], N.NativeSelectionRejectTargetMismatch), tostring(mismatch.rejects[1]))

local missing_family = family(target_a, "native.mc.missing")
local missing = imported.bank:select_native_template(N.NativeTemplateSelectionInput(target_a, missing_family))
assert(asdl.isa(missing, N.NativeTemplateSelectionRejected), tostring(missing))
assert(asdl.isa(missing.rejects[1], N.NativeSelectionRejectMissingBankEntry), tostring(missing.rejects[1]))

local node_id = N.NativeTemplateNodeId("node:return")
local node_instance = N.NativeTemplateInstanceId("instance:return")
local frame_layout = N.NativeFrameLayout({}, 0, 1)
local function binding_for(node, instance, coordinate)
    return N.NativePatchBinding(node, instance, N.NativePatchBindingHoleId(hole_id), coordinate)
end
local function ordinal_binding_for(node, instance, coordinate)
    return N.NativePatchBinding(node, instance, N.NativePatchBindingHoleOrdinal(hole_ordinal.id), coordinate)
end
local function graph_with_bindings(bindings)
    return N.NativeTemplateGraph(
        target_a,
        N.NativeCallReturnI32,
        frame_layout,
        { N.NativeTemplateNode(node_id, node_instance, selected.entry, {}, {}, bindings) },
        {},
        {},
        N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
        node_id,
        { node_id }
    )
end

local copy_plan = graph_with_bindings({ binding_for(node_id, node_instance, N.NativePatchImmediateI32(77)) })
    :select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
assert(copy_plan.layout.size == 6, "copy plan should lay out template bytes")
assert(copy_plan.total_size == 6, "copy plan should carry total executable layout size")
assert(copy_plan.layout.alignment == 16, "copy plan should preserve template alignment")
assert(asdl.isa(copy_plan.protocol, N.NativeCallReturnI32), "copy plan should preserve entry family call protocol")
local install = copy_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(install, N.NativeInstallSucceeded), tostring(install))
local call = copy_plan.protocol:call_native_executable(N.NativeExecutableCallInput(install.executable, {}))
assert(asdl.isa(call, N.NativeCallReturnedI32), tostring(call))
assert(call.value == 77, "patched native executable should return the imm32 coordinate")

local missing_binding_plan = graph_with_bindings({})
    :select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local missing_binding_install = missing_binding_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(missing_binding_install, N.NativeInstallRejected), tostring(missing_binding_install))
assert(asdl.isa(missing_binding_install.rejects[1], N.NativeInstallRejectMissingBinding), tostring(missing_binding_install.rejects[1]))

local duplicate_plan = graph_with_bindings({
    binding_for(node_id, node_instance, N.NativePatchImmediateI32(1)),
    binding_for(node_id, node_instance, N.NativePatchImmediateI32(2)),
}):select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local duplicate_install = duplicate_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(duplicate_install, N.NativeInstallRejected), tostring(duplicate_install))
assert(asdl.isa(duplicate_install.rejects[1], N.NativeInstallRejectDuplicateBinding), tostring(duplicate_install.rejects[1]))

local mixed_duplicate_plan = graph_with_bindings({
    binding_for(node_id, node_instance, N.NativePatchImmediateI32(1)),
    ordinal_binding_for(node_id, node_instance, N.NativePatchImmediateI32(2)),
}):select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local mixed_duplicate_install = mixed_duplicate_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(mixed_duplicate_install, N.NativeInstallRejected), tostring(mixed_duplicate_install))
assert(asdl.isa(mixed_duplicate_install.rejects[1], N.NativeInstallRejectDuplicateBinding), tostring(mixed_duplicate_install.rejects[1]))

local second_node_id = N.NativeTemplateNodeId("node:return:second")
local second_node_instance = N.NativeTemplateInstanceId("instance:return:second")
local repeated_graph = N.NativeTemplateGraph(
    target_a,
    N.NativeCallReturnI32,
    frame_layout,
    {
        N.NativeTemplateNode(node_id, node_instance, selected.entry, {}, {}, { binding_for(node_id, node_instance, N.NativePatchImmediateI32(3)) }),
        N.NativeTemplateNode(second_node_id, second_node_instance, selected.entry, {}, {}, { binding_for(second_node_id, second_node_instance, N.NativePatchImmediateI32(4)) }),
    },
    {},
    {},
    N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
    node_id,
    { second_node_id }
)
local repeated_plan = repeated_graph:select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local repeated_install = repeated_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(repeated_install, N.NativeInstallSucceeded), "same template hole may be bound independently per node instance: " .. tostring(repeated_install))
local repeated_call = repeated_plan.protocol:call_native_executable(N.NativeExecutableCallInput(repeated_install.executable, {}))
assert(asdl.isa(repeated_call, N.NativeCallReturnedI32), tostring(repeated_call))
assert(repeated_call.value == 3, "first node instance should keep its own patch binding")
local repeated_second_entry_graph = N.NativeTemplateGraph(
    target_a,
    N.NativeCallReturnI32,
    frame_layout,
    {
        N.NativeTemplateNode(node_id, node_instance, selected.entry, {}, {}, { binding_for(node_id, node_instance, N.NativePatchImmediateI32(3)) }),
        N.NativeTemplateNode(second_node_id, second_node_instance, selected.entry, {}, {}, { binding_for(second_node_id, second_node_instance, N.NativePatchImmediateI32(4)) }),
    },
    {},
    {},
    N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
    second_node_id,
    { second_node_id }
)
local repeated_second_plan = repeated_second_entry_graph:select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local repeated_second_install = repeated_second_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(repeated_second_install, N.NativeInstallSucceeded), tostring(repeated_second_install))
local repeated_second_call = repeated_second_plan.protocol:call_native_executable(N.NativeExecutableCallInput(repeated_second_install.executable, {}))
assert(asdl.isa(repeated_second_call, N.NativeCallReturnedI32), tostring(repeated_second_call))
assert(repeated_second_call.value == 4, "second node instance should keep its own patch binding")

local wrong_coordinate_plan = graph_with_bindings({ binding_for(node_id, node_instance, N.NativePatchPointer64(0)) })
    :select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local wrong_coordinate_install = wrong_coordinate_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(wrong_coordinate_install, N.NativeInstallRejected), tostring(wrong_coordinate_install))
assert(asdl.isa(wrong_coordinate_install.rejects[1], N.NativeInstallRejectWrongCoordinate), tostring(wrong_coordinate_install.rejects[1]))

local pool_hole_id = N.NativePatchHoleId("ptr64:pool")
local pool_hole = N.NativeHoleLayout(pool_hole_id, "pool_ptr", 2, 8, N.NativePatchPtr64)
local pool_entry_id = N.NativeConstantPoolEntryId("pool.entry")
local pool_entry = N.NativeConstantPoolEntry(
    pool_entry_id,
    N.NativeTemplateBytes("abcdefgh", 8),
    8,
    N.NativeConstantPoolBytes(8, 8)
)
local pool_layout = N.NativeConstantPoolLayout({ N.NativeConstantPoolLayoutEntry(pool_entry, 0) }, 8, 8)
local pool_embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("native-mc-pool-bank"),
    target_a,
    manifest("native-mc-pool-bank.manifest", 1),
    {
        N.NativeEmbeddedTemplate(
            family_a,
            N.NativeExtractStandaloneCallable,
            signature_i32,
            N.NativeTextSection(N.NativeTemplateBytes(string.char(0x90, 0x90, 0, 0, 0, 0, 0, 0, 0, 0), 10), 1),
            {},
            {},
            { pool_hole },
            {},
            {},
            pool_layout
        ),
    }
)
local pool_imported = N.NativeEmbeddedBankImportRequest(pool_embedded):import_native_bank()
assert(asdl.isa(pool_imported, N.NativeEmbeddedBankImported), tostring(pool_imported))
local pool_entry_template = pool_imported.bank.entries[1]
local pool_node_a = N.NativeTemplateNodeId("node:pool:a")
local pool_node_b = N.NativeTemplateNodeId("node:pool:b")
local pool_instance_a = N.NativeTemplateInstanceId("instance:pool:a")
local pool_instance_b = N.NativeTemplateInstanceId("instance:pool:b")
local pool_graph = N.NativeTemplateGraph(
    target_a,
    N.NativeCallReturnI32,
    frame_layout,
    {
        N.NativeTemplateNode(pool_node_a, pool_instance_a, pool_entry_template, {}, {}, { N.NativePatchBinding(pool_node_a, pool_instance_a, N.NativePatchBindingHoleId(pool_hole_id), N.NativePatchPointer64(1)) }),
        N.NativeTemplateNode(pool_node_b, pool_instance_b, pool_entry_template, {}, {}, { N.NativePatchBinding(pool_node_b, pool_instance_b, N.NativePatchBindingHoleId(pool_hole_id), N.NativePatchConstantPoolEntry(pool_entry_id, pool_entry.bytes, nil)) }),
    },
    {},
    {},
    N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
    pool_node_a,
    {}
)
local pool_plan = pool_graph:select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local pool_install = pool_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(pool_install, N.NativeInstallSucceeded), tostring(pool_install))
local node_b_offset
for _, layout_node in ipairs(pool_plan.layout.nodes) do
    if layout_node.node == pool_node_b then node_b_offset = layout_node.offset end
end
assert(node_b_offset ~= nil, "pool test should find second node layout")
local patched = tonumber(ffi.cast("uint64_t *", pool_install.executable.base_address + node_b_offset + pool_hole.offset)[0])
local expected_pool_address = pool_install.executable.base_address + pool_plan.constant_pool_layout.entries[2].offset
assert(patched == expected_pool_address, "constant-pool patch coordinate must use executable-global pool offsets for non-entry nodes")

local rel_pool_family = family(target_a, "native.mc.pool.rel32")
local rel_pool_entry_id = N.NativeConstantPoolEntryId("pool.entry.rel32")
local rel_pool_entry = N.NativeConstantPoolEntry(
    rel_pool_entry_id,
    N.NativeTemplateBytes(string.char(123, 0, 0, 0), 4),
    4,
    N.NativeConstantPoolScalarConst(scalar_i32)
)
local rel_pool_layout = N.NativeConstantPoolLayout({ N.NativeConstantPoolLayoutEntry(rel_pool_entry, 0) }, 4, 4)
local rel_pool_embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("native-mc-pool-rel-bank"),
    target_a,
    manifest("native-mc-pool-rel-bank.manifest", 1),
    {
        N.NativeEmbeddedTemplate(
            rel_pool_family,
            N.NativeExtractStandaloneCallable,
            signature_i32,
            N.NativeTextSection(N.NativeTemplateBytes(string.char(0x8B, 0x05, 0, 0, 0, 0, 0xC3), 7), 1),
            {},
            { N.NativeRelocationConstantPool(2, rel_pool_entry_id, N.NativePatchPcRel32, -4) },
            {},
            {},
            { N.NativeTemplateRelocationConstantPool },
            rel_pool_layout
        ),
    }
)
local rel_pool_imported = N.NativeEmbeddedBankImportRequest(rel_pool_embedded):import_native_bank()
assert(asdl.isa(rel_pool_imported, N.NativeEmbeddedBankImported), tostring(rel_pool_imported))
local rel_pool_node = N.NativeTemplateNodeId("node:pool:rel32")
local rel_pool_graph = N.NativeTemplateGraph(
    target_a,
    N.NativeCallReturnI32,
    frame_layout,
    { N.NativeTemplateNode(rel_pool_node, N.NativeTemplateInstanceId("instance:pool:rel32"), rel_pool_imported.bank.entries[1], {}, {}, {}) },
    {},
    {},
    N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
    rel_pool_node,
    { rel_pool_node }
)
local rel_pool_plan = rel_pool_graph:select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local rel_pool_install = rel_pool_plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
assert(asdl.isa(rel_pool_install, N.NativeInstallSucceeded), tostring(rel_pool_install))
local rel_pool_call = rel_pool_plan.protocol:call_native_executable(N.NativeExecutableCallInput(rel_pool_install.executable, {}))
assert(asdl.isa(rel_pool_call, N.NativeCallReturnedI32), tostring(rel_pool_call))
assert(rel_pool_call.value == 123, "NativeRelocationConstantPool should patch a rel32 load from executable constant pool")

local fixed_alloc_storage = ffi.new("uint8_t[?]", 256)
local fixed_alloc_base = tonumber(ffi.cast("uintptr_t", fixed_alloc_storage))
function N.NativeExecutableAllocatorVirtualAlloc:allocate_native_memory(_input, _size)
    return fixed_alloc_base, nil
end
local runtime_symbol_id = N.NativeRuntimeSymbolId("runtime.symbol.test")
local runtime_abi = N.NativeAbiFunctionProjection(target_a, {}, N.NativeAbiResultProjection(nil, N.NativeAbiVoidResult))
local runtime_family = family(target_a, "native.mc.runtime.rel32")
local runtime_embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("native-mc-runtime-bank"),
    target_a,
    manifest("native-mc-runtime-bank.manifest", 1),
    {
        N.NativeEmbeddedTemplate(
            runtime_family,
            N.NativeExtractStandaloneCallable,
            signature_i32,
            N.NativeTextSection(N.NativeTemplateBytes(string.char(0xE8, 0, 0, 0, 0, 0xC3), 6), 1),
            {},
            { N.NativeRelocationRuntimeSymbol(1, runtime_symbol_id, -4) },
            {},
            {},
            { N.NativeTemplateRelocationRuntimeSymbol },
            empty_constant_pool_layout
        ),
    }
)
local runtime_imported = N.NativeEmbeddedBankImportRequest(runtime_embedded):import_native_bank()
assert(asdl.isa(runtime_imported, N.NativeEmbeddedBankImported), tostring(runtime_imported))
local runtime_node = N.NativeTemplateNodeId("node:runtime")
local runtime_graph = N.NativeTemplateGraph(
    target_a,
    N.NativeCallReturnI32,
    frame_layout,
    { N.NativeTemplateNode(runtime_node, N.NativeTemplateInstanceId("instance:runtime"), runtime_imported.bank.entries[1], {}, {}, {}) },
    {},
    {},
    N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
    runtime_node,
    { runtime_node }
)
local runtime_plan = runtime_graph:select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local supplied_runtime = N.NativeRuntime({ N.NativeRuntimeSymbol(runtime_symbol_id, "runtime_symbol_test", runtime_abi, N.NativeRuntimeAddressSupplied(fixed_alloc_base + 128)) })
local runtime_install = runtime_plan:install_native(N.NativeInstallInput(target_a, supplied_runtime, N.NativeExecutableAllocatorVirtualAlloc))
assert(asdl.isa(runtime_install, N.NativeInstallSucceeded), tostring(runtime_install))
local runtime_disp = tonumber(ffi.cast("int32_t *", fixed_alloc_base + 1)[0])
assert(runtime_disp == 123, "runtime symbol rel32 should be patched from supplied runtime address")
local missing_runtime = N.NativeRuntime({ N.NativeRuntimeSymbol(runtime_symbol_id, "runtime_symbol_test", runtime_abi, nil) })
local missing_runtime_install = runtime_plan:install_native(N.NativeInstallInput(target_a, missing_runtime, N.NativeExecutableAllocatorVirtualAlloc))
assert(asdl.isa(missing_runtime_install, N.NativeInstallRejected), tostring(missing_runtime_install))
assert(asdl.isa(missing_runtime_install.rejects[1], N.NativeInstallRejectUnsupportedRelocation), tostring(missing_runtime_install.rejects[1]))

local scalar_i64 = N.NativeScalarInt(64, Code.CodeSigned)
local function family_i64(target_value, id)
    return N.NativeTemplateFamily(
        N.NativeTemplateFamilyId(id),
        N.NativeRoleRuntimeCall,
        { N.NativeAxisTarget(target_value) },
        N.NativeTemplateProtocol(N.NativeCallReturnI64, N.NativeRegisterProtocolNone)
    )
end
local address_family = family_i64(target_a, "native.mc.address.patch")
local address_hole = N.NativeHoleLayout(N.NativePatchHoleId("ptr64:address"), "address_ptr", 2, 8, N.NativePatchPtr64)
local address_pool_entry = N.NativeConstantPoolEntry(
    N.NativeConstantPoolEntryId("native.mc.address.pool.data"),
    N.NativeTemplateBytes(string.char(1, 2, 3, 4), 4),
    4,
    N.NativeConstantPoolBytes(4, 4)
)
local address_template = N.NativeTemplateBankEntry(address_family, N.NativeCompiledTemplate(
    N.NativeTemplateId("native.mc.address.template"),
    address_family,
    target_a,
    N.NativeExtractStandaloneCallable,
    N.NativeStencilSignature(N.NativeStencilFrameParam(scalar_i64), {}, {}, {}),
    N.NativeTextSection(N.NativeTemplateBytes(string.char(0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0xC3), 11), 1),
    { N.NativeSymbol("native_mc_address_entry", 0, 11) },
    {},
    { address_hole },
    {},
    {},
    N.NativeConstantPoolLayout({ N.NativeConstantPoolLayoutEntry(address_pool_entry, 0) }, 4, 4)
))
local address_data_id = Code.CodeDataId("native.mc.address.data")
local address_global_id = Code.CodeGlobalId("native.mc.address.global")
local address_func_id = Code.CodeFuncId("native.mc.address.func")
local address_extern_id = Code.CodeExternId("native.mc.address.extern")
local address_runtime_symbol = N.NativeRuntimeSymbolId("native.mc.address.extern.symbol")
local pointer_rep = N.NativeAddressValueRepresentation(N.NativeScalarPointer(64), N.NativeCodeDataAddressTarget(address_data_id, code_ty_i32))
local address_plan = N.NativeModuleAddressPlan(
    { N.NativeModuleDataAddressEntry(address_data_id, N.NativeCodeAddressProjection(N.NativeCodeDataAddressTarget(address_data_id, code_ty_i32), pointer_rep, N.NativeCodeAddressConstantPoolEntry(address_pool_entry.id))) },
    { N.NativeModuleGlobalAddressEntry(address_global_id, N.NativeCodeAddressProjection(N.NativeCodeGlobalAddressTarget(address_global_id, code_ty_i32), N.NativeAddressValueRepresentation(N.NativeScalarPointer(64), N.NativeCodeGlobalAddressTarget(address_global_id, code_ty_i32)), N.NativeCodeAddressPatchable(N.NativePatchPointer64(fixed_alloc_base + 200)))) },
    { N.NativeModuleFuncAddressEntry(address_func_id, N.NativeCodeAddressProjection(N.NativeCodeFuncAddressTarget(address_func_id, Code.CodeSigId("native.mc.address.sig")), N.NativeAddressValueRepresentation(N.NativeScalarPointer(64), N.NativeCodeFuncAddressTarget(address_func_id, Code.CodeSigId("native.mc.address.sig"))), N.NativeCodeAddressBankSymbol("native_mc_address_entry"))) },
    { N.NativeModuleExternAddressEntry(address_extern_id, N.NativeCodeAddressProjection(N.NativeCodeExternAddressTarget(address_extern_id), N.NativeAddressValueRepresentation(N.NativeScalarPointer(64), N.NativeCodeExternAddressTarget(address_extern_id)), N.NativeCodeAddressRuntimeSymbol(address_runtime_symbol))) },
    {},
    {}
)
local address_nodes = {
    N.NativeTemplateNode(N.NativeTemplateNodeId("node:address:data"), N.NativeTemplateInstanceId("instance:address:data"), address_template, {}, {}, { N.NativePatchBinding(N.NativeTemplateNodeId("node:address:data"), N.NativeTemplateInstanceId("instance:address:data"), N.NativePatchBindingHoleId(address_hole.id), N.NativePatchCodeDataAddress(address_data_id)) }),
    N.NativeTemplateNode(N.NativeTemplateNodeId("node:address:global"), N.NativeTemplateInstanceId("instance:address:global"), address_template, {}, {}, { N.NativePatchBinding(N.NativeTemplateNodeId("node:address:global"), N.NativeTemplateInstanceId("instance:address:global"), N.NativePatchBindingHoleId(address_hole.id), N.NativePatchCodeGlobalAddress(address_global_id)) }),
    N.NativeTemplateNode(N.NativeTemplateNodeId("node:address:func"), N.NativeTemplateInstanceId("instance:address:func"), address_template, {}, {}, { N.NativePatchBinding(N.NativeTemplateNodeId("node:address:func"), N.NativeTemplateInstanceId("instance:address:func"), N.NativePatchBindingHoleId(address_hole.id), N.NativePatchCodeFuncAddress(address_func_id)) }),
    N.NativeTemplateNode(N.NativeTemplateNodeId("node:address:extern"), N.NativeTemplateInstanceId("instance:address:extern"), address_template, {}, {}, { N.NativePatchBinding(N.NativeTemplateNodeId("node:address:extern"), N.NativeTemplateInstanceId("instance:address:extern"), N.NativePatchBindingHoleId(address_hole.id), N.NativePatchCodeExternAddress(address_extern_id)) }),
}
local address_graph = N.NativeTemplateGraph(target_a, N.NativeCallReturnI64, frame_layout, address_nodes, {}, {}, address_plan, address_nodes[1].id, { address_nodes[4].id })
local address_copy_plan = address_graph:select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
local address_runtime = N.NativeRuntime({ N.NativeRuntimeSymbol(address_runtime_symbol, "native_mc_address_extern", runtime_abi, N.NativeRuntimeAddressSupplied(fixed_alloc_base + 216)) })
local address_install = address_copy_plan:install_native(N.NativeInstallInput(target_a, address_runtime, N.NativeExecutableAllocatorVirtualAlloc))
assert(asdl.isa(address_install, N.NativeInstallSucceeded), tostring(address_install))
local function patched_address(node_id)
    local node_offset = nil
    for _, layout_node in ipairs(address_copy_plan.layout.nodes) do if layout_node.node == node_id then node_offset = layout_node.offset end end
    return tonumber(ffi.cast("uint64_t *", fixed_alloc_base + node_offset + address_hole.offset)[0])
end
local function pool_address_for_first_node()
    for _, entry in ipairs(address_copy_plan.constant_pool_layout.entries) do
        if entry.entry.id == address_pool_entry.id then return fixed_alloc_base + entry.offset end
    end
end
assert(patched_address(address_nodes[1].id) == pool_address_for_first_node(), "CodeData address patch should resolve through NativeModuleAddressPlan constant-pool capability")
assert(patched_address(address_nodes[2].id) == fixed_alloc_base + 200, "CodeGlobal address patch should resolve through patchable address capability")
assert(patched_address(address_nodes[3].id) == fixed_alloc_base, "CodeFunc address patch should resolve copied bank symbol address")
assert(patched_address(address_nodes[4].id) == fixed_alloc_base + 216, "CodeExtern address patch should resolve runtime symbol capability")
local missing_address_runtime = N.NativeRuntime({ N.NativeRuntimeSymbol(address_runtime_symbol, "native_mc_address_extern", runtime_abi, nil) })
local missing_address_install = address_copy_plan:install_native(N.NativeInstallInput(target_a, missing_address_runtime, N.NativeExecutableAllocatorVirtualAlloc))
assert(asdl.isa(missing_address_install, N.NativeInstallRejected), tostring(missing_address_install))
assert(asdl.isa(missing_address_install.rejects[#missing_address_install.rejects], N.NativeInstallRejectWrongCoordinate), tostring(missing_address_install.rejects[#missing_address_install.rejects]))

local continuation_symbol = N.NativeContinuationSymbol(N.NativeContinuationSymbolId("native.mc.cont.edge"), "native_mc_cont_edge")
local jump_family = family(target_a, "native.mc.jump.cont")
local return9_hole_id = N.NativePatchHoleId("imm32:return9")
local return9_hole = N.NativeHoleLayout(return9_hole_id, "return_imm9", 1, 4, N.NativePatchImm32)
local jump_entry = N.NativeTemplateBankEntry(jump_family, N.NativeCompiledTemplate(
    N.NativeTemplateId("native.mc.jump.cont"),
    jump_family,
    target_a,
    N.NativeExtractContinuationFragment({ continuation_symbol }),
    signature_i32,
    N.NativeTextSection(N.NativeTemplateBytes(string.char(0xE9, 0, 0, 0, 0), 5), 1),
    {},
    { N.NativeRelocationContinuation(1, continuation_symbol, -4) },
    {},
    {},
    { N.NativeTemplateRelocationContinuation },
    empty_constant_pool_layout
))
local return9_family = family(target_a, "native.mc.return9")
local return9_entry = N.NativeTemplateBankEntry(return9_family, N.NativeCompiledTemplate(
    N.NativeTemplateId("native.mc.return9"),
    return9_family,
    target_a,
    N.NativeExtractStandaloneCallable,
    signature_i32,
    bytes,
    { N.NativeSymbol("native_mc_return9", 0, 6) },
    {},
    { return9_hole },
    {},
    {},
    empty_constant_pool_layout
))
local function assert_edge_exec(edge, expected)
    local from_node = N.NativeTemplateNodeId("node:edge:from:" .. tostring(expected))
    local to_node = N.NativeTemplateNodeId("node:edge:to:" .. tostring(expected))
    local graph = N.NativeTemplateGraph(
        target_a,
        N.NativeCallReturnI32,
        frame_layout,
        {
            N.NativeTemplateNode(from_node, N.NativeTemplateInstanceId("instance:edge:from:" .. tostring(expected)), jump_entry, {}, {}, {}),
            N.NativeTemplateNode(to_node, N.NativeTemplateInstanceId("instance:edge:to:" .. tostring(expected)), return9_entry, {}, {}, { N.NativePatchBinding(to_node, N.NativeTemplateInstanceId("instance:edge:to:" .. tostring(expected)), N.NativePatchBindingHoleId(return9_hole_id), N.NativePatchImmediateI32(expected)) }),
        },
        { edge(from_node, to_node) },
        {},
        N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
        from_node,
        { to_node }
    )
    local plan = graph:select_native_copy_plan(N.NativeCopyPlanSelectionInput(target_a, N.NativeRuntime({})))
    local installed = plan:install_native(N.NativeInstallInput(target_a, N.NativeRuntime({}), N.NativeExecutableAllocatorMmap))
    assert(asdl.isa(installed, N.NativeInstallSucceeded), tostring(installed))
    local called = plan.protocol:call_native_executable(N.NativeExecutableCallInput(installed.executable, {}))
    assert(asdl.isa(called, N.NativeCallReturnedI32), tostring(called))
    assert(called.value == expected, "symbol-bearing control edge should resolve continuation target")
end
assert_edge_exec(function(from_node, to_node) return N.NativeLoopBackedgeEdge(from_node, to_node, continuation_symbol) end, 91)
assert_edge_exec(function(from_node, to_node) return N.NativeRuntimeCallReturnEdge(from_node, to_node, runtime_symbol_id, continuation_symbol) end, 92)
assert_edge_exec(function(from_node, to_node) return N.NativeConditionalBranchEdge(from_node, to_node, continuation_symbol, to_node, N.NativeContinuationSymbol(N.NativeContinuationSymbolId("native.mc.cont.unused"), "native_mc_cont_unused"), N.NativeTemplateValueId("cond")) end, 93)

local bad_embedded = N.NativeEmbeddedTemplateBank(
    N.NativeBankId("native-mc-bad-bank"),
    target_a,
    manifest("native-mc-bad-bank.manifest", 1),
    {
        N.NativeEmbeddedTemplate(
            family_a,
            N.NativeExtractStandaloneCallable,
            signature_i32,
            N.NativeTextSection(N.NativeTemplateBytes(string.char(0xC3), 1), 1),
            {},
            {},
            { N.NativeHoleLayout(N.NativePatchHoleId("bad"), "bad", 1, 4, N.NativePatchImm32) },
            {},
            {},
            empty_constant_pool_layout
        ),
    }
)
local bad_import = N.NativeEmbeddedBankImportRequest(bad_embedded):import_native_bank()
assert(asdl.isa(bad_import, N.NativeEmbeddedBankRejected), tostring(bad_import))
assert(asdl.isa(bad_import.rejects[1], N.NativeBuildRejectHoleOutOfRange), tostring(bad_import.rejects[1]))

io.write("lalin native_mc import ok\n")
