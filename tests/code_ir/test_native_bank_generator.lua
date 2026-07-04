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
assert(command_ok(cmd), "expected native bank generator to build a typed embedded bank")
assert(command_ok("gcc -c " .. shell_quote(c_path) .. " -o " .. shell_quote(dir .. "/bank.o")), "generated C bridge should compile")

local log = read_file(dir .. "/generator.log")
local header = read_file(h_path)
local source = read_file(c_path)
local lua_source = read_file(lua_path)

assert(log:find("embedded native template bank native%-generator%-bank with 1 templates"), "expected native bank generator log")
assert(header:find("LalinNativeEmbeddedTemplateBank", 1, true), "expected native embedded bank C type")
assert(source:find("lalin_native_template_entries", 1, true), "expected native template entries in C source")
assert(source:find("native.generator.trivial", 1, true), "expected native family id in C source")
assert(not source:find("lalin_install_embedded_native_bank", 1, true), "generator must not emit runtime install hooks")
assert(not source:find("LJMC", 1, true), "generator must not emit LuaJIT MC bank data")
assert(not source:find("lalin_mc_template_entries", 1, true), "generator must not emit old MC template manifests")
assert(lua_source:find("NativeEmbeddedTemplateBank", 1, true), "generated Lua bridge should construct NativeEmbeddedTemplateBank")
assert(lua_source:find("NativeTemplateBytes", 1, true), "generated Lua bridge should carry template bytes")

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local N = T.LalinNative
local embedded = dofile(lua_path)(T)
assert(#embedded.entries == 1, "generated embedded bank should contain one template")
local imported = N.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, N.NativeEmbeddedBankImported), tostring(imported))
local selected = imported.bank:select_native_template(N.NativeTemplateSelectionInput(embedded.target, embedded.entries[1].family))
assert(asdl.isa(selected, N.NativeTemplateSelected), tostring(selected))

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
assert(hole_lua_source:find("NativeRelocationHoleOrdinal", 1, true), "Lua bridge should reconstruct NativeRelocationHoleOrdinal")
assert(hole_lua_source:find("NativeHoleLayout", 1, true), "Lua bridge should reconstruct concrete NativeHoleLayout offsets")
assert(not hole_lua_source:find("0x11111111", 1, true), "generated Lua must not mention marker holes")
assert(not read_file(hole_bank_c):find("0x11111111", 1, true), "generated C bridge must not mention marker holes")

local hole_embedded = dofile(hole_bank_lua)(T)
local hole_entry = hole_embedded.entries[1]
assert(#hole_entry.holes == 1, "hole ordinal relocation should produce one concrete hole layout")
assert(hole_entry.holes[1].offset >= 0, "hole layout offset should be resolved from object relocation")
local saw_hole_relocation = false
for _, relocation in ipairs(hole_entry.relocations or {}) do
    if asdl.isa(relocation, N.NativeRelocationHoleOrdinal) then
        saw_hole_relocation = true
        assert(relocation.ordinal == hole_entry.hole_ordinals[1], "hole relocation should carry the declared ordinal")
    end
end
assert(saw_hole_relocation, "embedded template should retain typed hole ordinal relocation")

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

local multi_ok, _multi_c, _multi_h, multi_lua = run_generator("multi_hole_occurrence", {
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
local multi_entry = dofile(multi_lua)(T).entries[1]
assert(#multi_entry.holes >= 2, "multiple hole ordinal relocation occurrences should produce multiple patch sites")

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
assert(cp_lua_source:find("NativeRelocationConstantPool", 1, true), "Lua bridge should reconstruct constant-pool relocations")
assert(cp_lua_source:find("NativeConstantPoolEntry", 1, true), "Lua bridge should reconstruct object-derived constant-pool entries")
local cp_entry = dofile(cp_lua)(T).entries[1]
assert(#cp_entry.constant_pool_layout.entries >= 1, "object .rodata should become constant-pool layout entries")
assert(asdl.isa(cp_entry.relocations[1], N.NativeRelocationConstantPool), "text relocation to .rodata should become NativeRelocationConstantPool")
assert(cp_entry.relocations[1].formula == N.NativePatchPcRel32, "x64 PC-relative .rodata relocation should carry PcRel32 formula")

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
