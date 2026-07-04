package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

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

assert(command_ok("make lalin-bin"), "expected make lalin-bin to build the embedded Lalin executable")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_bc_bank.c"), "expected binary build to generate embedded BC bank source")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_bc_bank.h"), "expected binary build to generate embedded BC bank header")
assert(command_ok("test -f target/lalin_binary/lalin_native_template_bank.c"), "expected binary build to generate native template bank source")
assert(command_ok("test -f target/lalin_binary/lalin_native_template_bank.h"), "expected binary build to generate native template bank header")
assert(command_ok("test -f target/lalin_binary/lalin_native_template_bank.lua"), "expected binary build to generate native template bank Lua bridge")
assert(command_ok("target/lalin --version >/dev/null"), "expected embedded Lalin executable to start")
assert(command_ok("target/lalin -e " .. shell_quote("local lalin=require('lalin'); assert(type(lalin.compile)=='function'); assert(type(require('llbl'))=='table'); assert(debug.getregistry()['lalin.embedded_mc_bank.count']==nil)")), "expected embedded binary to expose no stale MC registry shim")

assert(command_ok("mkdir -p target/lalin_binary_smoke"))

local luajit_path = "target/lalin_binary_smoke/luajit_smoke.lua"
write_file(luajit_path, [=[
local lalin = require("lalin")
local add = lalin.dsl.load([[return fn. add { a [i32], b [i32] } [i32] { ret (a + b), }]], "embedded_luajit_smoke.lua")
local m = lalin.compile("embedded_luajit_smoke", { add }, { luajit = true })
assert(m.add(20, 22) == 42)
assert(m.__lalin_artifact.bytecode == true)
]=])
assert(command_ok("target/lalin " .. shell_quote(luajit_path)), "expected embedded Lalin executable to compile and run explicit LuaJIT bytecode input")

local no_bank_path = "target/lalin_binary_smoke/native_no_bank.lua"
write_file(no_bank_path, [=[
local lalin = require("lalin")
local add = lalin.dsl.load([[return fn. add { a [i32], b [i32] } [i32] { ret (a + b), }]], "embedded_native_no_bank.lua")
local ok, err = pcall(function()
  lalin.compile("embedded_native_no_bank", { add })
end)
assert(not ok, "default native compile without a supplied bank must fail")
assert(tostring(err):find("compile_native requires opts.native_bank", 1, true), tostring(err))
assert(not tostring(err):lower():find("fallback", 1, true), tostring(err))
]=])
assert(command_ok("target/lalin " .. shell_quote(no_bank_path)), "expected native compile without supplied NativeTemplateBank to error clearly")

local native_dir = "target/lalin_binary_smoke/native_bank"
assert(command_ok("rm -rf " .. shell_quote(native_dir)))
assert(command_ok("mkdir -p " .. shell_quote(native_dir)))
local manifest_path = native_dir .. "/manifest.lua"
write_file(manifest_path, [[return function(T)
  return require('lalin.native_template_sources')(T).host_scalar_i32_bank_request()
end
]])
local native_c = native_dir .. "/bank.c"
local native_h = native_dir .. "/bank.h"
local native_lua = native_dir .. "/bank.lua"
local gen_cmd = table.concat({
    "luajit tools/gen_lalin_mc_bank.lua",
    shell_quote(native_c),
    shell_quote(native_h),
    shell_quote(native_lua),
    shell_quote(manifest_path),
    ">", shell_quote(native_dir .. "/generator.out"),
    "2>", shell_quote(native_dir .. "/generator.log"),
}, " ")
assert(command_ok(gen_cmd), "expected test to generate a non-empty native scalar bank")

local native_path = "target/lalin_binary_smoke/native_scalar.lua"
write_file(native_path, string.format([=[
local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")
local T = asdl.context()
Schema(T)
local Native = T.LalinNative
local Code = T.LalinCode
local Core = T.LalinCore
local NativeBackend = require("lalin.native_backend")(T)
local embedded = dofile(%q)(T)
local bank = NativeBackend.require_imported_bank(embedded)
local target = NativeBackend.host_target()
local runtime = NativeBackend.empty_runtime()
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local a = Code.CodeValueId("native.binary.a")
local b = Code.CodeValueId("native.binary.b")
local dst = Code.CodeValueId("native.binary.dst")
local inst = Code.CodeInst(
  Code.CodeInstId("native.binary.inst"),
  Code.CodeInstBinary(dst, Core.BinAdd, i32, Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount), a, b),
  origin)
local term = Code.CodeTerm(Code.CodeTermId("native.binary.term"), Code.CodeTermReturn({ dst }), origin)
local block_id = Code.CodeBlockId("native.binary.entry")
local block = Code.CodeBlock(block_id, "entry", {}, { inst }, term, origin)
local func = Code.CodeFunc(
  Code.CodeFuncId("native.binary.add"),
  "native_binary_add",
  Code.CodeLinkageExport,
  Code.CodeSigId("native.binary.sig"),
  { Code.CodeParam(a, "a", i32, origin), Code.CodeParam(b, "b", i32, origin) },
  {},
  block_id,
  { block },
  origin)
local result = NativeBackend.compile_code_func(func, target, runtime, bank)
local call = result.executable.protocol:call_native_executable(Native.NativeExecutableCallInput(result.executable, { Native.NativeCallArgI32(20), Native.NativeCallArgI32(22) }))
assert(call.value == 42, "minimal scalar native compile should execute from supplied non-empty NativeTemplateBank")
]=], native_lua))
assert(command_ok("target/lalin " .. shell_quote(native_path)), "expected embedded Lalin executable to run a minimal supplied-bank native scalar compile")

io.write("lalin binary ok\n")
