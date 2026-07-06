package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local dir = "target/test_artifacts/test_native_bank_generator"
local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local lua_path = dir .. "/bank.lua"
local so_path = dir .. "/bank.so"
local manifest_path = dir .. "/manifest.lua"

assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))

local function manifest_text(opts)
    opts = opts or {}
    local c_text = assert(opts.c_text, "c_text")
    local entry_symbol = opts.entry_symbol or "lalin_native_generator_case"
    local family_suffix = opts.family_suffix or entry_symbol
    local extraction_expr = opts.extraction_expr or "N.NativeExtractStandaloneCallable"
    local declared_holes_expr = opts.declared_holes_expr or "{}"
    local declared_hole_ordinals_expr = opts.declared_hole_ordinals_expr or "{}"
    local declared_cont_ordinals_expr = opts.declared_cont_ordinals_expr or "{}"
    local declared_relocation_kinds_expr = opts.declared_relocation_kinds_expr or "{}"
    return string.format([[
return function(T)
  local ffi = require('ffi')
  local N = T.LalinNative
  local arch = ffi.arch == 'x64' and N.NativeArchX64 or N.NativeArchAArch64
  local os_name = ffi.os == 'Linux' and N.NativeOsLinux or (ffi.os == 'OSX' and N.NativeOsDarwin or N.NativeOsWindows)
  local abi = ffi.os == 'Windows' and N.NativeAbiWin64 or ((ffi.arch == 'arm64' or ffi.arch == 'aarch64') and N.NativeAbiAapcs64 or N.NativeAbiSysV)
  local target = N.NativeTarget(N.NativeTargetId('native-generator-host'), arch, os_name, abi, ffi.abi('64bit') and 64 or 32, ffi.abi('le') and N.NativeLittleEndian or N.NativeBigEndian)
  local Support = require('lalin.native_template_support')(T)
  local protocol = N.NativeTemplateProtocol(N.NativeCallReturnI32, N.NativeRegisterProtocolNone)
  local family = N.NativeTemplateFamily(N.NativeTemplateFamilyId('native.generator.%s'), N.NativeRoleRuntimeCall, { N.NativeAxisTarget(target) }, protocol)
  local generator = Support.stencil_generator(Support.stencil_generator_id('generator.%s'), family, N.NativeChunkStandaloneCallable, {})
  local configuration = Support.stencil_configuration(Support.stencil_configuration_id('generator.%s'), generator, {})
  local signature = Support.spill_all_stencil_signature(Support.scalar_i32(), {}, {})
  local first = Support.first_continuation_symbol()
  local first_ordinal = Support.first_continuation_ordinal()
  local hole0 = Support.hole_ordinal(Support.hole_ordinal_id('generator.hole0'), 0, 'lalin_native_hole0', N.NativePatchImm32)
  local hole0_layout = N.NativeHoleLayout(N.NativePatchHoleId('native.generator.hole0'), hole0.symbol, -1, 4, N.NativePatchImm32)
  local source = N.NativeTemplateSource(
    N.NativeTemplateId('native.generator.%s'),
    family,
    generator,
    configuration,
    signature,
    %s,
    %q,
    %q,
    %s,
    %s,
    %s,
    %s)
  local entry = Support.template_manifest_entry_for_source(source)
  local group = Support.template_manifest_group(generator, { entry })
  local manifest = Support.template_source_manifest(Support.template_manifest_id('generator.%s'), N.NativeTemplateSupportDomainId('native.template.support.generator.%s'), { group })
  return N.NativeTemplateBankRequest(N.NativeBankId('native-generator-bank'), target, N.NativeRuntime({}), manifest, { source })
end
]], family_suffix, family_suffix, family_suffix, family_suffix, extraction_expr, entry_symbol, c_text, declared_holes_expr, declared_hole_ordinals_expr, declared_cont_ordinals_expr, declared_relocation_kinds_expr, family_suffix, family_suffix)
end

local function run_generator(name, opts)
    local case_dir = dir .. "/" .. name
    assert(command_ok("mkdir -p " .. shell_quote(case_dir)))
    local case_manifest = case_dir .. "/manifest.lua"
    local case_c = case_dir .. "/bank.c"
    local case_h = case_dir .. "/bank.h"
    local case_lua = case_dir .. "/bank.lua"
    local case_log = case_dir .. "/generator.log"
    write_file(case_manifest, manifest_text(opts))
    local env = opts.env or ""
    local cmd = table.concat({
        env,
        "luajit tools/gen_lalin_mc_bank.lua",
        shell_quote(case_c),
        shell_quote(case_h),
        shell_quote(case_lua),
        shell_quote(case_manifest),
        "2>",
        shell_quote(case_log),
    }, " ")
    local ok = command_ok(cmd)
    return ok, case_c, case_h, case_lua, case_log
end

-- Keep the original trivial standalone generation smoke.
write_file(manifest_path, manifest_text({
    family_suffix = "trivial",
    entry_symbol = "lalin_native_generator_trivial",
    c_text = "int lalin_native_generator_trivial(void) { return 7; }\n",
}))

local cmd = table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(c_path),
    shell_quote(h_path),
    shell_quote(lua_path),
    shell_quote(manifest_path),
    "2>",
    shell_quote(dir .. "/generator.log"),
}, " ")
assert(command_ok(cmd), "expected native bank generator to build a C-owned bank artifact")
assert(command_ok("gcc -c " .. shell_quote(c_path) .. " -o " .. shell_quote(dir .. "/bank.o")), "generated C bank should compile")
assert(command_ok("gcc -shared -fPIC " .. shell_quote(c_path) .. " -o " .. shell_quote(so_path)), "generated C bank should link as a shared object")

local log = read_file(dir .. "/generator.log")
local header = read_file(h_path)
local source = read_file(c_path)
local lua_source = read_file(lua_path)

assert(log:find("C%-owned native template bank native%-generator%-bank with 1 templates"), "expected native bank generator log")
assert(header:find("LalinNativeBankArtifact", 1, true), "expected native bank artifact C type")
assert(header:find("lalin_native_bank_install", 1, true), "expected installer API declaration")
assert(source:find("lalin_native_templates", 1, true), "expected native template table in C source")
assert(source:find("lalin_native_bank_install", 1, true), "expected generated C installer")
assert(source:find("native.generator.trivial", 1, true), "expected native family id in C source")
assert(not source:find("LJMC", 1, true), "generator must not emit LuaJIT MC bank data")
assert(not source:find("lalin_mc_template_entries", 1, true), "generator must not emit old MC template manifests")
assert(lua_source:find("NativeBankArtifact", 1, true), "generated Lua bridge should construct NativeBankArtifact")
assert(not lua_source:find("NativeEmbeddedTemplateBank", 1, true), "generated Lua bridge must not construct NativeEmbeddedTemplateBank")
assert(not lua_source:find("NativeTemplateBytes", 1, true), "generated Lua bridge must not carry template bytes")

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local N = T.LalinNative
local Support = require("lalin.native_template_support")(T)
local artifact = dofile(lua_path)(T)
assert(asdl.isa(artifact, N.NativeBankArtifact), tostring(artifact))
assert(artifact.template_count == 1, "generated artifact should describe one C-owned template")
assert(artifact.installer_symbol == "lalin_native_bank_install", "artifact should record generated installer symbol")
local loaded_result = artifact:load_native_bank(so_path)
assert(asdl.isa(loaded_result, N.NativeBankLoaded), tostring(loaded_result))
local loaded_bank = loaded_result.bank
local trivial_family = artifact.manifest.groups[1].entries[1].family
local selector_key = N.NativeTemplateSelectorKey(artifact.target, trivial_family)
local selected_trivial = loaded_bank:select_native_template(N.NativeTemplateSelectionInput(loaded_bank, selector_key))
assert(asdl.isa(selected_trivial, N.NativeTemplateSelected), tostring(selected_trivial))
local trivial_node = N.NativeTemplateNodeId("native.generator.trivial.node")
local trivial_graph = N.NativeTemplateGraph(
    artifact.target,
    N.NativeCallReturnI32,
    N.NativeFrameLayout({}, 0, 1),
    { N.NativeTemplateNode(trivial_node, N.NativeTemplateInstanceId("native.generator.trivial.instance"), trivial_family, {}, {}, {}) },
    {},
    {},
    N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
    trivial_node,
    { trivial_node }
)
local trivial_plan = trivial_graph:select_native_bank_install_plan(N.NativeBankInstallPlanSelectionInput(artifact.target, N.NativeRuntime({})))
local trivial_install = N.NativeBankInstallRequest(loaded_bank, trivial_plan, N.NativeExecutableAllocatorMmap):install_native()
assert(asdl.isa(trivial_install, N.NativeInstallSucceeded), tostring(trivial_install))
local trivial_call = trivial_install.executable.protocol:call_native_executable(N.NativeExecutableCallInput(trivial_install.executable, {}))
assert(asdl.isa(trivial_call, N.NativeCallReturnedI32) and trivial_call.value == 7, "C-owned generated bank should select, install, and execute through its C API")

local fallthrough_manifest = dir .. "/fallthrough_manifest.lua"
local fallthrough_c = dir .. "/fallthrough_bank.c"
local fallthrough_h = dir .. "/fallthrough_bank.h"
local fallthrough_lua = dir .. "/fallthrough_bank.lua"
local fallthrough_so = dir .. "/fallthrough_bank.so"
local fallthrough_log = dir .. "/fallthrough_generator.log"
write_file(fallthrough_manifest, [[
package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path
return function(T)
  local N = T.LalinNative
  local Support = require('lalin.native_template_support')(T)
  local target = Support.host_target()
  local function source(suffix)
    local family = N.NativeTemplateFamily(N.NativeTemplateFamilyId('native.generator.fallthrough.' .. suffix), N.NativeRoleCodeTerm, { Support.axis_target(target) }, Support.protocol_void_none())
    local generator = Support.stencil_generator(Support.stencil_generator_id('generator.fallthrough.' .. suffix), family, N.NativeChunkSupertemplate, {})
    local configuration = Support.stencil_configuration(Support.stencil_configuration_id('generator.fallthrough.' .. suffix), generator, {})
    local signature = Support.spill_all_stencil_signature(Support.scalar_i32(), {}, {})
    return N.NativeTemplateSource(
      N.NativeTemplateId('native.generator.fallthrough.' .. suffix),
      family, generator, configuration, signature,
      N.NativeExtractFallthroughFragment,
      'lalin_native_generator_fallthrough_' .. suffix,
      '#include <stdint.h>\nvoid lalin_native_generator_fallthrough_' .. suffix .. '(uint8_t *frame) { (void)frame; }\n',
      {}, {}, {}, {})
  end
  local a = source('a')
  local b = source('b')
  local group_a = Support.template_manifest_group(a.generator, { Support.template_manifest_entry_for_source(a) })
  local group_b = Support.template_manifest_group(b.generator, { Support.template_manifest_entry_for_source(b) })
  local manifest = Support.template_source_manifest(Support.template_manifest_id('generator.fallthrough'), N.NativeTemplateSupportDomainId('native.template.support.generator.fallthrough'), { group_a, group_b })
  return N.NativeTemplateBankRequest(N.NativeBankId('native-generator-fallthrough-bank'), target, Support.empty_runtime(), manifest, { a, b })
end
]])
assert(command_ok(table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(fallthrough_c), shell_quote(fallthrough_h), shell_quote(fallthrough_lua), shell_quote(fallthrough_manifest),
    "2>", shell_quote(fallthrough_log),
}, " ")), "fallthrough bank generator should build")
assert(command_ok("gcc -shared -fPIC " .. shell_quote(fallthrough_c) .. " -o " .. shell_quote(fallthrough_so)), "fallthrough generated C bank should link")
local fallthrough_artifact = dofile(fallthrough_lua)(T)
local fallthrough_loaded = assert(fallthrough_artifact:load_native_bank(fallthrough_so).bank)
local fallthrough_a = fallthrough_artifact.manifest.groups[1].entries[1].family
local fallthrough_b = fallthrough_artifact.manifest.groups[2].entries[1].family
local node_a = N.NativeTemplateNodeId("native.generator.fallthrough.a.node")
local node_b = N.NativeTemplateNodeId("native.generator.fallthrough.b.node")
local reversed_fallthrough_graph = N.NativeTemplateGraph(
    fallthrough_artifact.target,
    N.NativeCallVoid,
    N.NativeFrameLayout({}, 0, 1),
    {
        N.NativeTemplateNode(node_b, N.NativeTemplateInstanceId("native.generator.fallthrough.b.instance"), fallthrough_b, {}, {}, {}),
        N.NativeTemplateNode(node_a, N.NativeTemplateInstanceId("native.generator.fallthrough.a.instance"), fallthrough_a, {}, {}, {}),
    },
    { N.NativeFallthroughEdge(node_a, node_b, Support.next_continuation_symbol()) },
    {},
    N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
    node_a,
    { node_b }
)
local reversed_fallthrough_plan = reversed_fallthrough_graph:select_native_bank_install_plan(N.NativeBankInstallPlanSelectionInput(fallthrough_artifact.target, N.NativeRuntime({})))
local reversed_fallthrough_install = N.NativeBankInstallRequest(fallthrough_loaded, reversed_fallthrough_plan, N.NativeExecutableAllocatorMmap):install_native()
assert(asdl.isa(reversed_fallthrough_install, N.NativeInstallRejected), "non-adjacent fallthrough layout should reject")
assert(asdl.isa(reversed_fallthrough_install.rejects[1], N.NativeInstallRejectFallthroughLayout), "fallthrough rejection should be a typed ASDL install reject")

local complete_manifest = dir .. "/complete_micro_manifest.lua"
local complete_c = dir .. "/complete_micro_bank.c"
local complete_h = dir .. "/complete_micro_bank.h"
local complete_lua = dir .. "/complete_micro_bank.lua"
local complete_log = dir .. "/complete_micro_generator.log"
write_file(complete_manifest, [[
package.path = './?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;' .. package.path
return function(T)
  local N = T.LalinNative
  local Core = T.LalinCore
  local Stencil = T.LalinStencil
  local Support = require('lalin.native_template_support')(T)
  local Sources = require('lalin.native_template_sources')(T)
  local target = Support.host_target()
  local i32 = Support.scalar_i32()
  local ptr = Support.scalar_pointer(target.pointer_bits)
  local value = Support.complete_value_scalar_class(i32)
  local scalar_class = Support.complete_scalar_pointer_scalar_class(i32)
  local reducer = N.NativeReducerClass(T.LalinValue.ReductionAdd, value)
  local cap = N.NativeCompleteBankCapability(
    Support.complete_bank_capability_id('generator.micro'), target,
    { i32, ptr }, { value }, { Support.complete_scalar_bytes_scalar_class(i32) }, { scalar_class }, { Support.complete_index_class(target.pointer_bits) }, {},
    Support.complete_runtime_capability({}, {}, {}), Support.complete_frame_capability(ptr, {}, {}), Support.complete_constant_pool_capability({}), Support.complete_atomic_capability(N.NativeAtomicNoCodegen, {}, {}, {}),
    Support.complete_code_capability({ N.NativeCodeMicroOpScalarCopyShape(i32) }),
    Support.complete_abi_capability({ N.NativeAbiMicroOpReturnScalarShape(scalar_class) }),
    Support.complete_kernel_capability({ N.NativeKernelMicroOpExprBinaryShape(Core.BinAdd, value) }),
    Support.complete_stencil_capability({ N.NativeStencilMicroOpPointBinaryShape(Stencil.StencilBinaryAdd, value), N.NativeStencilMicroOpSinkReduceShape(reducer, N.NativeStencilReduceScopeDomainClass) })
  )
  return Sources.bank_request_for_complete_capability(cap, N.NativeBankId('native-generator-complete-micro-bank'))
end
]])
assert(command_ok(table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(complete_c), shell_quote(complete_h), shell_quote(complete_lua), shell_quote(complete_manifest),
    "2>", shell_quote(complete_log),
}, " ")), "complete micro-op bank generator should build")
assert(command_ok("gcc -c " .. shell_quote(complete_c) .. " -o " .. shell_quote(dir .. "/complete_micro_bank.o")), "complete micro-op generated C bridge should compile")
local complete_artifact = dofile(complete_lua)(T)
assert(asdl.isa(complete_artifact, N.NativeBankArtifact), tostring(complete_artifact))
assert(complete_artifact.template_count == 5, "complete micro-op bank should describe one C-owned template per requested micro-op")
local complete_entries = {}
for _, group in ipairs(complete_artifact.manifest.groups or {}) do
    for _, entry in ipairs(group.entries or {}) do complete_entries[#complete_entries + 1] = entry end
end
assert(#complete_entries == 5, "complete micro-op manifest should retain one entry per requested micro-op")
for _, entry in ipairs(complete_entries) do
    local saw_closed_axis = false
    for _, axis in ipairs(entry.family.axes) do
        assert(not asdl.isa(axis, N.NativeAxisCodeType), "complete generated bank must not use CodeType axes")
        assert(not asdl.isa(axis, N.NativeAxisCodeSig), "complete generated bank must not use CodeSig axes")
        assert(not asdl.isa(axis, N.NativeAxisKernel), "complete generated bank must not use exact Kernel axes")
        assert(not asdl.isa(axis, N.NativeAxisStencilProducer), "complete generated bank must not use exact Stencil producer axes")
        assert(not asdl.isa(axis, N.NativeAxisStencilAccess), "complete generated bank must not use exact Stencil access axes")
        assert(not asdl.isa(axis, N.NativeAxisStencilPoint), "complete generated bank must not use exact Stencil point axes")
        assert(not asdl.isa(axis, N.NativeAxisStencilBody), "complete generated bank must not use exact Stencil body axes")
        assert(not asdl.isa(axis, N.NativeAxisStencilSink), "complete generated bank must not use exact Stencil sink axes")
        assert(not asdl.isa(axis, N.NativeAxisStencilSchedule), "complete generated bank must not use exact Stencil schedule axes")
        saw_closed_axis = saw_closed_axis or asdl.isa(axis, N.NativeAxisCodeMicroOp) or asdl.isa(axis, N.NativeAxisAbiMicroOp) or asdl.isa(axis, N.NativeAxisKernelMicroOp) or asdl.isa(axis, N.NativeAxisStencilMicroOp)
    end
    assert(saw_closed_axis, entry.family.id.text .. " should carry a closed complete-bank micro-op axis")
end

-- Extern-symbol hole ordinals are recovered from object relocations by the
-- internal parser.  READELF is deliberately poisoned to prove it is not the
-- authority for parser correctness.
local hole_c = [[
#include <stdint.h>
extern const uint8_t lalin_native_hole0;
int lalin_native_generator_hole(void) {
  return (int)(uintptr_t)&lalin_native_hole0;
}
]]
local ok, hole_bank_c, _hole_h, hole_bank_lua = run_generator("hole_ordinal", {
    family_suffix = "hole_ordinal",
    entry_symbol = "lalin_native_generator_hole",
    c_text = hole_c,
    env = "READELF=/bin/false",
    declared_holes_expr = "{ hole0_layout }",
    declared_hole_ordinals_expr = "{ hole0 }",
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationHoleOrdinal }",
})
assert(ok, "extern-symbol hole ordinal source should build without readelf")
local hole_lua_source = read_file(hole_bank_lua)
local hole_c_source = read_file(hole_bank_c)
assert(hole_lua_source:find("NativeBankArtifact", 1, true), "Lua bridge should reconstruct only NativeBankArtifact")
assert(not hole_lua_source:find("NativeEmbeddedTemplateBank", 1, true), "Lua bridge must not reconstruct embedded templates")
assert(hole_c_source:find("LALIN_NATIVE_RELOC_HOLE_ORDINAL", 1, true), "C bank should retain hole ordinal relocation metadata")
assert(hole_c_source:find("LALIN_NATIVE_PATCH_HOLE_IMM32", 1, true), "C bank should retain concrete hole layout metadata")
assert(not hole_lua_source:find("0x11111111", 1, true), "generated Lua must not mention marker holes")
assert(not hole_c_source:find("0x11111111", 1, true), "generated C bridge must not mention marker holes")

local function expect_reject(name, opts, reject_name)
    local failed_ok, _c, _h, _lua, case_log = run_generator(name, opts)
    assert(not failed_ok, name .. " should reject")
    local reject_log = read_file(case_log)
    assert(reject_log:find(reject_name, 1, true), name .. " should report " .. reject_name .. ":\n" .. reject_log)
end

expect_reject("missing_hole_ordinal", {
    family_suffix = "missing_hole_ordinal",
    c_text = "int lalin_native_generator_case(void) { return 0; }\n",
    declared_holes_expr = "{ hole0_layout }",
    declared_hole_ordinals_expr = "{ hole0 }",
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationHoleOrdinal }",
}, "NativeBuildRejectMissingHole")

local multi_ok, multi_c, _multi_h, _multi_lua = run_generator("multi_hole_occurrence", {
    family_suffix = "multi_hole_occurrence",
    c_text = [[
#include <stdint.h>
extern const uint8_t lalin_native_hole0;
int lalin_native_generator_case(void) {
  volatile uintptr_t a = (uintptr_t)&lalin_native_hole0;
  volatile uintptr_t b = (uintptr_t)&lalin_native_hole0;
  return (int)(a + b);
}
]],
    declared_holes_expr = "{ hole0_layout }",
    declared_hole_ordinals_expr = "{ hole0 }",
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationHoleOrdinal }",
})
assert(multi_ok, "multiple physical relocations to one logical hole ordinal should be valid")
local multi_c_source = read_file(multi_c)
local _, multi_hole_occurrences = multi_c_source:gsub("LALIN_NATIVE_PATCH_HOLE_IMM32", "")
assert(multi_hole_occurrences >= 2, "multiple hole ordinal relocation occurrences should produce multiple C patch sites")

local cp_ok, _cp_c, _cp_h, cp_lua = run_generator("object_constant_pool", {
    family_suffix = "object_constant_pool",
    c_text = [[
#include <stdint.h>
static const int32_t lalin_native_cp_value[1] = { 42 };
int lalin_native_generator_case(void) {
  return ((const volatile int32_t *)lalin_native_cp_value)[0];
}
]],
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationConstantPool }",
})
assert(cp_ok, "readonly object constants should be extracted into NativeConstantPoolLayout")
local cp_lua_source = read_file(cp_lua)
local cp_c_source = read_file(_cp_c)
assert(cp_lua_source:find("NativeBankArtifact", 1, true), "Lua bridge should reconstruct only NativeBankArtifact")
assert(cp_c_source:find("LALIN_NATIVE_RELOC_CONSTANT_POOL", 1, true), "C bank should retain constant-pool relocation metadata")
assert(cp_c_source:find("LALIN_NATIVE_PATCH_FORMULA_PCREL32", 1, true), "C bank should retain constant-pool relocation formula")
assert(cp_c_source:find("LalinNativeConstantPoolEntry", 1, true), "C bank should retain object-derived constant-pool entries")

expect_reject("duplicate_hole_ordinal_declaration", {
    family_suffix = "duplicate_hole_ordinal_declaration",
    c_text = [[
#include <stdint.h>
extern const uint8_t lalin_native_hole0;
int lalin_native_generator_case(void) { return (int)(uintptr_t)&lalin_native_hole0; }
]],
    declared_holes_expr = "{ hole0_layout }",
    declared_hole_ordinals_expr = "{ hole0, hole0 }",
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationHoleOrdinal }",
}, "NativeBuildRejectDuplicateHoleOrdinal")

expect_reject("extra_unresolved_symbol", {
    family_suffix = "extra_unresolved_symbol",
    c_text = [[
extern int lalin_native_extra_unresolved;
int lalin_native_generator_case(void) { return lalin_native_extra_unresolved; }
]],
}, "NativeBuildRejectExtraUnresolvedSymbol")

expect_reject("missing_continuation_relocation", {
    family_suffix = "missing_continuation_relocation",
    c_text = "int lalin_native_generator_case(void) { return 0; }\n",
    extraction_expr = "N.NativeExtractEntryCallable(N.NativePatchFrameSize(64), first)",
    declared_cont_ordinals_expr = "{ first_ordinal }",
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationContinuation }",
}, "NativeBuildRejectMissingContinuationRelocation")

expect_reject("unsupported_continuation_relocation", {
    family_suffix = "unsupported_continuation_relocation",
    c_text = [[
#include <stdint.h>
extern void lalin_native_cont_first(uint8_t *frame);
int lalin_native_generator_case(void) { return (int)(uintptr_t)&lalin_native_cont_first; }
]],
    extraction_expr = "N.NativeExtractEntryCallable(N.NativePatchFrameSize(64), first)",
    declared_cont_ordinals_expr = "{ first_ordinal }",
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationContinuation }",
}, "NativeBuildRejectUnsupportedRelocation")

expect_reject("constant_pool_unresolved", {
    family_suffix = "constant_pool_unresolved",
    c_text = [[
extern int lalin_native_constant_pool_entry0;
int lalin_native_generator_case(void) { return lalin_native_constant_pool_entry0; }
]],
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationConstantPool }",
}, "NativeBuildRejectExtraUnresolvedSymbol")

io.write("lalin native bank generator ok\n")
