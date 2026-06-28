package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function command_ok(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

assert(command_ok("make lalin-bin"), "expected make lalin-bin to build the embedded Lalin executable")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_bc_bank.c"), "expected binary build to generate embedded BC bank source")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_bc_bank.h"), "expected binary build to generate embedded BC bank header")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_mc_bank.c"), "expected binary build to generate embedded MC bank source")
assert(command_ok("test -f target/lalin_binary/lalin_embedded_mc_bank.h"), "expected binary build to generate embedded MC bank header")
assert(command_ok("target/lalin --version >/dev/null"), "expected embedded Lalin executable to start")
assert(command_ok("target/lalin -e " .. shell_quote("local lalin=require('lalin'); assert(type(lalin.compile)=='function'); assert(type(require('llbl'))=='table'); assert((debug.getregistry()['lalin.embedded_mc_bank.count'] or 0) > 0)")), "expected embedded banks to be installed")

os.execute("mkdir -p target/lalin_binary_smoke")
local path = "target/lalin_binary_smoke/smoke.lua"
local f = assert(io.open(path, "wb"))
f:write([=[
local lalin = require("lalin")
local add = lalin.dsl.load([[return fn. add { a [i32], b [i32] } [i32] { ret (a + b), }]], "embedded_smoke.lua")
local m = lalin.compile("embedded_smoke", { add })
assert(m.add(20, 22) == 42)
]=])
f:close()

assert(command_ok("target/lalin " .. shell_quote(path)), "expected embedded Lalin executable to compile and run DSL input")

local mc_path = "target/lalin_binary_smoke/embedded_mc.lua"
local mc = assert(io.open(mc_path, "wb"))
mc:write([==[
local ffi = require("ffi")
local lalin = require("lalin")
local parsed = assert(lalin.loadstring([=[
local zip_add = fn(dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  requires disjoint(dst)(lhs), disjoint(dst)(rhs), disjoint(lhs)(rhs)
  loop i in 0 .. n do
    dst[i] = lhs[i] + rhs[i]
  end
end

return { zip_add }
]=], "@embedded_mc.lln"))()
local warnings = {}
local m = lalin.compile("embedded_mc", parsed, {
  collect_warnings = warnings,
  allow_bc_fallback = false,
})
assert(m.__lalin_artifact.residual == "mc")
assert(m.__lalin_artifact.mc_bank ~= nil)
assert(#warnings == 0)
local lhs = ffi.new("int32_t[3]", { 1, 2, 3 })
local rhs = ffi.new("int32_t[3]", { 10, 20, 30 })
local dst = ffi.new("int32_t[3]")
m.zip_add(dst, lhs, rhs, 3)
assert(dst[0] == 11 and dst[1] == 22 and dst[2] == 33)
]==])
mc:close()

assert(command_ok("target/lalin " .. shell_quote(mc_path)), "expected embedded Lalin executable to resolve MC stencils from the fat bank")

io.write("lalin binary ok\n")
