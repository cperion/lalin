package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
    io.write("skip C-owned native bank runtime: requires x64 non-Windows little-endian 64-bit host\n")
    os.exit(0)
end

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local N = T.LalinNative
local Code = T.LalinCode

local dir = "target/test_artifacts/test_native_mc_import"
assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))

local runtime_callbacks = {}

local function manifest_text(opts)
    local runtime_expr = opts.runtime_expr or "N.NativeRuntime({})"
    local relocation_expr = opts.declared_relocation_kinds_expr or "{}"
    local hole_decls = opts.declared_holes_expr or "{}"
    local hole_ordinals = opts.declared_hole_ordinals_expr or "{}"
    return string.format([[
return function(T)
  local ffi = require('ffi')
  local N = T.LalinNative
  local Code = T.LalinCode
  local Support = require('lalin.native_template_support')(T)
  local arch = ffi.arch == 'x64' and N.NativeArchX64 or N.NativeArchAArch64
  local os_name = ffi.os == 'Linux' and N.NativeOsLinux or (ffi.os == 'OSX' and N.NativeOsDarwin or N.NativeOsWindows)
  local abi = ffi.os == 'Windows' and N.NativeAbiWin64 or ((ffi.arch == 'arm64' or ffi.arch == 'aarch64') and N.NativeAbiAapcs64 or N.NativeAbiSysV)
  local target = N.NativeTarget(N.NativeTargetId('native-mc-owned-host'), arch, os_name, abi, ffi.abi('64bit') and 64 or 32, ffi.abi('le') and N.NativeLittleEndian or N.NativeBigEndian)
  local i32 = Support.scalar_i32()
  local protocol = N.NativeTemplateProtocol(N.NativeCallReturnI32, N.NativeRegisterProtocolNone)
  local family = N.NativeTemplateFamily(N.NativeTemplateFamilyId('%s'), N.NativeRoleRuntimeCall, { N.NativeAxisTarget(target) }, protocol)
  local generator = Support.stencil_generator(Support.stencil_generator_id('%s.generator'), family, N.NativeChunkStandaloneCallable, {})
  local configuration = Support.stencil_configuration(Support.stencil_configuration_id('%s.configuration'), generator, {})
  local signature = Support.spill_all_stencil_signature(i32, {}, {})
  local hole0 = Support.hole_ordinal(Support.hole_ordinal_id('native.mc.owned.hole0'), 0, 'lalin_native_hole0', N.NativePatchImm32)
  local hole0_layout = N.NativeHoleLayout(N.NativePatchHoleId('native.mc.owned.hole0'), hole0.symbol, -1, 4, N.NativePatchImm32)
  local runtime_abi = N.NativeAbiFunctionProjection(target, { N.NativeAbiParamProjection(0, Code.CodeTyInt(32, Code.CodeSigned), N.NativeAbiScalarValue(i32, N.NativeSignExtend)) }, N.NativeAbiResultProjection(Code.CodeTyInt(32, Code.CodeSigned), N.NativeAbiScalarValue(i32, N.NativeSignExtend)))
  local runtime = %s
  local source = N.NativeTemplateSource(
    N.NativeTemplateId('%s.template'),
    family,
    generator,
    configuration,
    signature,
    N.NativeExtractStandaloneCallable,
    'lalin_native_owned_case',
    %q,
    %s,
    %s,
    {},
    %s)
  local entry = Support.template_manifest_entry_for_source(source)
  local manifest = Support.template_source_manifest(Support.template_manifest_id('%s.manifest'), N.NativeTemplateSupportDomainId('%s.support'), { Support.template_manifest_group(generator, { entry }) })
  return N.NativeTemplateBankRequest(N.NativeBankId('%s.bank'), target, runtime, manifest, { source })
end
]], opts.family_id, opts.family_id, opts.family_id, runtime_expr, opts.family_id, opts.c_text, hole_decls, hole_ordinals, relocation_expr, opts.family_id, opts.family_id, opts.family_id)
end

local function build_bank(name, opts)
    local case_dir = dir .. "/" .. name
    assert(command_ok("mkdir -p " .. shell_quote(case_dir)))
    local manifest_path = case_dir .. "/manifest.lua"
    local c_path = case_dir .. "/bank.c"
    local h_path = case_dir .. "/bank.h"
    local lua_path = case_dir .. "/bank.lua"
    local so_path = case_dir .. "/bank.so"
    write_file(manifest_path, manifest_text(opts))
    assert(command_ok(table.concat({
        "luajit tools/gen_lalin_mc_bank.lua",
        shell_quote(c_path), shell_quote(h_path), shell_quote(lua_path), shell_quote(manifest_path),
        ">", shell_quote(case_dir .. "/generator.out"),
        "2>", shell_quote(case_dir .. "/generator.log"),
    }, " ")), name .. " C-owned bank should generate")
    assert(command_ok("gcc -shared -fPIC " .. shell_quote(c_path) .. " -o " .. shell_quote(so_path)), name .. " C-owned bank should link as a shared object")
    local artifact = dofile(lua_path)(T)
    assert(asdl.isa(artifact, N.NativeBankArtifact), name .. " Lua descriptor must be NativeBankArtifact")
    local load = artifact:load_native_bank(so_path)
    assert(asdl.isa(load, N.NativeBankLoaded), tostring(load))
    local family = artifact.manifest.groups[1].entries[1].family
    return artifact, load.bank, family
end

local function graph_for(target, family, bindings)
    local node = N.NativeTemplateNodeId("native.mc.owned.node")
    local instance = N.NativeTemplateInstanceId("native.mc.owned.instance")
    return N.NativeTemplateGraph(
        target,
        N.NativeCallReturnI32,
        N.NativeFrameLayout({}, 0, 1),
        { N.NativeTemplateNode(node, instance, family, {}, {}, bindings or {}) },
        {},
        {},
        N.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}),
        node,
        { node }
    )
end

local function install_graph(bank, graph, runtime)
    local plan = graph:select_native_bank_install_plan(N.NativeBankInstallPlanSelectionInput(graph.target, runtime or N.NativeRuntime({})))
    return N.NativeBankInstallRequest(bank, plan, N.NativeExecutableAllocatorMmap):install_native()
end

local function call_i32(executable)
    local call = executable.protocol:call_native_executable(N.NativeExecutableCallInput(executable, {}))
    assert(asdl.isa(call, N.NativeCallReturnedI32), tostring(call))
    return call.value
end

local hole_artifact, hole_bank, hole_family = build_bank("hole_binding", {
    family_id = "native.mc.owned.hole",
    c_text = [[
#include <stdint.h>
extern const uint8_t lalin_native_hole0;
int lalin_native_owned_case(void) { return (int)(uintptr_t)&lalin_native_hole0; }
]],
    declared_holes_expr = "{ hole0_layout }",
    declared_hole_ordinals_expr = "{ hole0 }",
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationHoleOrdinal }",
})
local selected = hole_bank:select_native_template(N.NativeTemplateSelectionInput(hole_bank, N.NativeTemplateSelectorKey(hole_artifact.target, hole_family)))
assert(asdl.isa(selected, N.NativeTemplateSelected), tostring(selected))
assert(selected.handle.family == hole_family, "C selector should return the requested family handle")
local hole_node = N.NativeTemplateNodeId("native.mc.owned.node")
local hole_instance = N.NativeTemplateInstanceId("native.mc.owned.instance")
local binding = N.NativePatchBinding(hole_node, hole_instance, N.NativePatchBindingHoleId(N.NativePatchHoleId("native.mc.owned.hole0")), N.NativePatchImmediateI32(77))
local patched = install_graph(hole_bank, graph_for(hole_artifact.target, hole_family, { binding }))
assert(asdl.isa(patched, N.NativeInstallSucceeded), tostring(patched))
assert(call_i32(patched.executable) == 77, "C-owned installer should patch imm32 bindings and execute")
local missing = install_graph(hole_bank, graph_for(hole_artifact.target, hole_family, {}))
assert(asdl.isa(missing, N.NativeInstallRejected), tostring(missing))
assert(asdl.isa(missing.rejects[1], N.NativeInstallRejectMissingBinding), tostring(missing.rejects[1]))
local duplicate = install_graph(hole_bank, graph_for(hole_artifact.target, hole_family, { binding, binding }))
assert(asdl.isa(duplicate, N.NativeInstallRejected), tostring(duplicate))
assert(asdl.isa(duplicate.rejects[1], N.NativeInstallRejectDuplicateBinding), tostring(duplicate.rejects[1]))

local pool_artifact, pool_bank, pool_family = build_bank("constant_pool", {
    family_id = "native.mc.owned.constant_pool",
    c_text = [[
#include <stdint.h>
static const int32_t lalin_native_cp_value[1] = { 42 };
int lalin_native_owned_case(void) { return ((const volatile int32_t *)lalin_native_cp_value)[0]; }
]],
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationConstantPool }",
})
local pool_install = install_graph(pool_bank, graph_for(pool_artifact.target, pool_family, {}))
assert(asdl.isa(pool_install, N.NativeInstallSucceeded), tostring(pool_install))
assert(call_i32(pool_install.executable) == 42, "C-owned installer should relocate object-derived constant pools")

local add1 = ffi.cast("int (*)(int)", function(x) return x + 1 end)
runtime_callbacks[#runtime_callbacks + 1] = add1
local runtime_address = tonumber(ffi.cast("uintptr_t", add1))
local runtime_expr = "N.NativeRuntime({ N.NativeRuntimeSymbol(N.NativeRuntimeSymbolId('native.mc.owned.runtime.add1'), 'lalin_native_runtime_add1', runtime_abi, nil) })"
local runtime_artifact, runtime_bank, runtime_family = build_bank("runtime_symbol", {
    family_id = "native.mc.owned.runtime",
    runtime_expr = runtime_expr,
    c_text = [[
#include <stdint.h>
extern int lalin_native_runtime_add1(int32_t value);
int lalin_native_owned_case(void) { return lalin_native_runtime_add1(41); }
]],
    declared_relocation_kinds_expr = "{ N.NativeTemplateRelocationRuntimeSymbol }",
})
local runtime_i32 = N.NativeScalarInt(32, Code.CodeSigned)
local runtime_abi = N.NativeAbiFunctionProjection(
    runtime_artifact.target,
    { N.NativeAbiParamProjection(0, Code.CodeTyInt(32, Code.CodeSigned), N.NativeAbiScalarValue(runtime_i32, N.NativeSignExtend)) },
    N.NativeAbiResultProjection(Code.CodeTyInt(32, Code.CodeSigned), N.NativeAbiScalarValue(runtime_i32, N.NativeSignExtend))
)
local supplied_runtime = N.NativeRuntime({
    N.NativeRuntimeSymbol(
        N.NativeRuntimeSymbolId("native.mc.owned.runtime.add1"),
        "lalin_native_runtime_add1",
        runtime_abi,
        N.NativeRuntimeAddressSupplied(runtime_address)
    ),
})
local runtime_install = install_graph(runtime_bank, graph_for(runtime_artifact.target, runtime_family, {}), supplied_runtime)
assert(asdl.isa(runtime_install, N.NativeInstallSucceeded), tostring(runtime_install))
assert(call_i32(runtime_install.executable) == 42, "C-owned installer should patch supplied runtime symbols")
local missing_runtime = install_graph(runtime_bank, graph_for(runtime_artifact.target, runtime_family, {}), N.NativeRuntime({}))
assert(asdl.isa(missing_runtime, N.NativeInstallRejected), "missing runtime symbol address should reject")

io.write("C-owned native bank runtime ok\n")
