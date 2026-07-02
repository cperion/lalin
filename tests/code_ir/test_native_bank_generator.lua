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

local dir = "target/test_artifacts/test_native_bank_generator"
local c_path = dir .. "/bank.c"
local h_path = dir .. "/bank.h"
local lua_path = dir .. "/bank.lua"
local manifest_path = dir .. "/manifest.lua"

assert(command_ok("rm -rf " .. shell_quote(dir)))
assert(command_ok("mkdir -p " .. shell_quote(dir)))

local manifest = [[
return function(T)
  local ffi = require('ffi')
  local N = T.LalinNative
  local arch = ffi.arch == 'x64' and N.NativeArchX64 or N.NativeArchAArch64
  local os_name = ffi.os == 'Linux' and N.NativeOsLinux or (ffi.os == 'OSX' and N.NativeOsDarwin or N.NativeOsWindows)
  local abi = ffi.os == 'Windows' and N.NativeAbiWin64 or ((ffi.arch == 'arm64' or ffi.arch == 'aarch64') and N.NativeAbiAapcs64 or N.NativeAbiSysV)
  local target = N.NativeTarget(N.NativeTargetId('native-generator-host'), arch, os_name, abi, ffi.abi('64bit') and 64 or 32, ffi.abi('le') and N.NativeLittleEndian or N.NativeBigEndian)
  local protocol = N.NativeTemplateProtocol(N.NativeCallReturnI32, N.NativeRegisterProtocolNone)
  local family = N.NativeTemplateFamily(N.NativeTemplateFamilyId('native.generator.trivial'), N.NativeRoleRuntimeCall, { N.NativeAxisTarget(target) }, protocol)
  local source = N.NativeTemplateSource(N.NativeTemplateId('native.generator.trivial'), family, N.NativeExtractStandaloneCallable, 'lalin_native_generator_trivial', 'int lalin_native_generator_trivial(void) { return 7; }\n', {})
  return N.NativeTemplateBankRequest(N.NativeBankId('native-generator-bank'), target, N.NativeRuntime({}), { source })
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

io.write("lalin native bank generator ok\n")
