package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
if ffi.arch ~= "x64" or ffi.os == "Windows" or not ffi.abi("64bit") or not ffi.abi("le") then
    io.write("skip native template source slice: requires x64 non-Windows little-endian 64-bit host\n")
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

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function assert_no_forbidden_terms(label, text)
    local lower = tostring(text):lower()
    assert(not lower:find("residual", 1, true), label .. " must not mention residual")
    assert(not text:find("LuaJIT", 1, true), label .. " must not mention LuaJIT")
    assert(not text:find("LJMC", 1, true), label .. " must not mention LJMC")
    assert(not lower:find("input_count", 1, true), label .. " must not encode exact-cell input counts")
    assert(not lower:find("producer x layout", 1, true), label .. " must not encode Cartesian stencil products")
end

local T = asdl.context()
Schema(T)
require("lalin.native_mc")(T)
local Native = T.LalinNative
local Support = require("lalin.native_template_support")(T)
local NativeBackend = require("lalin.native_backend")(T)
local Sources = require("lalin.native_template_sources")(T)

assert(Support.host_target() == NativeBackend.host_target(), "native backend and template sources must share the host NativeTarget")

local i32_domain = Support.host_scalar_i32_support_domain()
local full_domain = Support.host_scalar_support_domain()
assert(#full_domain.scalars > #i32_domain.scalars, "support domain vocabulary must not be rooted in the i32 proof slice")
local saw_i64, saw_f64, saw_pointer
for _, scalar_support in ipairs(full_domain.scalars) do
    local token = scalar_support.scalar:native_scalar_token()
    if token == "i64" then saw_i64 = true end
    if token == "f64" then saw_f64 = true end
    if token == "ptr64" then saw_pointer = true end
end
assert(saw_i64 and saw_f64 and saw_pointer, "full support domain should name integer, float, and pointer scalar reps")

local full_request = Sources.host_scalar_bank_request()
assert(#full_request.sources > #i32_domain.scalars, "full scalar source request should be generated from the full support domain")
Sources.assert_unique_source_ids(full_request.sources)
Sources.assert_unique_family_ids(full_request.sources)
local function full_source_for_family(family_id)
    for _, source in ipairs(full_request.sources) do
        if source.family.id.text == family_id then return source end
    end
    return nil
end
for _, family_id in ipairs({
    "native.code.inst.binary.i64.add",
    "native.code.inst.float_binary.f64.add",
    "native.code.inst.unary.bool8.not",
    "native.code.inst.compare.i32.eq",
    "native.code.inst.alias.f64",
    "native.code.term.return.f64",
    "native.code.const.literal.i64",
}) do
    assert(full_source_for_family(family_id) ~= nil, "full scalar domain should include " .. family_id)
end
assert(asdl.isa(full_source_for_family("native.code.inst.float_binary.f64.add").extraction, Native.NativeExtractContinuationFragment), "f64 add should be a C continuation fragment")
assert(full_source_for_family("native.code.inst.float_binary.f64.add").c_text:find("lalin_native_cont_next", 1, true), "f64 add should tail into the declared C continuation")
assert(full_source_for_family("native.code.const.literal.i64").declared_holes[2].hole == Native.NativePatchImm64, "i64 literal should declare an imm64 hole")

local request = Sources.bank_request_for_support_domain(i32_domain, Support.host_scalar_i32_bank_id())
assert(#request.sources > 0, "scalar i32 support slice should be non-empty")
Sources.assert_unique_source_ids(request.sources)
Sources.assert_unique_family_ids(request.sources)

local required_families = {
    ["native.code.func.entry.i32.return.i32"] = true,
    ["native.code.func.entry.i32.return.bool8"] = true,
    ["native.code.inst.binary.i32.add"] = true,
    ["native.code.inst.binary.i32.sub"] = true,
    ["native.code.inst.binary.i32.mul"] = true,
    ["native.code.const.literal.i32"] = true,
    ["native.code.term.return.i32"] = true,
}

local seen_family = {}
local const_literal_source
for _, source in ipairs(request.sources) do
    local family_id = source.family.id.text
    assert(not seen_family[family_id], "duplicate source family " .. tostring(family_id))
    seen_family[family_id] = true
    assert_no_forbidden_terms(source.id.text, source.id.text .. "\n" .. family_id .. "\n" .. source.entry_symbol .. "\n" .. source.c_text)
    if family_id == "native.code.const.literal.i32" then const_literal_source = source end
end
for family_id in pairs(required_families) do
    assert(seen_family[family_id], "closed scalar i32 slice must include " .. family_id)
end
assert(const_literal_source ~= nil, "closed slice must include CodeConstLiteral i32")
assert(#const_literal_source.declared_holes == 2, "i32 literal source must use frame and literal patch holes")
assert(asdl.isa(const_literal_source.declared_holes[2].hole, Native.NativePatchImm32), "literal value must be a NativePatchImm32 hole, not a family axis")
assert(not const_literal_source.family.id.text:find("0", 1, true), "literal value must not appear in the family identity")
for _, name in ipairs({ "add", "sub", "mul" }) do
    local source
    for _, candidate in ipairs(request.sources) do
        if candidate.family.id.text == "native.code.inst.binary.i32." .. name then source = candidate end
    end
    assert(source ~= nil, "closed slice must include i32 " .. name)
    assert(asdl.isa(source.extraction, Native.NativeExtractContinuationFragment), "i32 " .. name .. " fragment should be a C continuation fragment")
    assert(source.c_text:find("uint8_t %*frame", 1, false), "i32 " .. name .. " should use the C frame protocol")
    assert(source.c_text:find("lalin_native_cont_next", 1, true), "i32 " .. name .. " should call the declared successor continuation")
    assert(source.c_text:find("uint32_t", 1, true), "i32 wrap " .. name .. " should express wrapping through unsigned C semantics")
end

local dir = "target/test_artifacts/test_native_template_sources"
local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local lua_path = dir .. "/bank.lua"
local manifest_path = dir .. "/manifest.lua"

assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))

local manifest = [[
return function(T)
  return require('lalin.native_template_sources')(T).host_scalar_i32_bank_request()
end
]]
local mf = assert(io.open(manifest_path, "wb"))
mf:write(manifest)
mf:close()

local cmd = table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(c_path),
    shell_quote(h_path),
    shell_quote(lua_path),
    shell_quote(manifest_path),
    ">",
    shell_quote(dir .. "/generator.out"),
    "2>",
    shell_quote(dir .. "/generator.log"),
}, " ")
assert(command_ok(cmd), "native bank generator should build the scalar i32 source slice")
assert(command_ok("gcc -c " .. shell_quote(c_path) .. " -o " .. shell_quote(dir .. "/bank.o")), "generated C bridge should compile")

local log = read_file(dir .. "/generator.log")
local header = read_file(h_path)
local c_source = read_file(c_path)
local lua_source = read_file(lua_path)
assert(log:find("embedded native template bank", 1, true), "generator should report a native template bank")
assert(header:find("LalinNativeEmbeddedTemplateBank", 1, true), "header should expose native embedded bank structs")
assert(c_source:find("lalin_native_template_entries", 1, true), "C bridge should carry raw native template entries")
assert(c_source:find("Runtime ASDL import uses the generated Lua bridge", 1, true), "C bridge should be marked as raw build data")
assert(lua_source:find("NativeEmbeddedTemplateBank", 1, true), "Lua bridge should construct NativeEmbeddedTemplateBank")
assert(lua_source:find("Code.CodeTyInt", 1, true), "Lua bridge should preserve CodeType axes as ASDL")
assert(lua_source:find("Core.BinAdd", 1, true), "Lua bridge should preserve Core operation axes as ASDL")
assert_no_forbidden_terms("generated C bridge", c_source)
assert_no_forbidden_terms("generated Lua bridge", lua_source)
assert(not c_source:find("lalin_install_embedded_native_bank", 1, true), "generator must not emit runtime install hooks")
assert(not c_source:find("lalin_mc_template_entries", 1, true), "generator must not emit old MC template manifests")

local embedded = dofile(lua_path)(T)
assert(#embedded.entries == #request.sources, "embedded bank should preserve every generated source")
local imported = Native.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
assert(asdl.isa(imported, Native.NativeEmbeddedBankImported), tostring(imported))
assert(#imported.bank.entries == #request.sources, "imported bank should contain every generated source")

for _, source in ipairs(request.sources) do
    local selected = imported.bank:select_native_template(Native.NativeTemplateSelectionInput(request.target, source.family))
    assert(asdl.isa(selected, Native.NativeTemplateSelected), "expected selection for " .. source.family.id.text .. ": " .. tostring(selected))
end

io.write("native template source closure ok\n")
