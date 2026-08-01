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
assert(command_ok("target/lalin --version >/dev/null"), "expected embedded Lalin executable to start")
assert(command_ok("target/lalin -e " .. shell_quote("local lalin=require('lalin'); assert(type(lalin.compile)=='function'); assert(type(require('llbl'))=='table'); assert(debug.getregistry()['lalin.embedded_mc_bank.count']==nil)")), "expected embedded binary to expose no stale MC registry shim")

assert(command_ok("mkdir -p target/lalin_binary_smoke"))


local default_c_path = "target/lalin_binary_smoke/default_c.lua"
write_file(default_c_path, [=[
local lalin = require("lalin")
local add = lalin.dsl.load([[return fn. add { a [i32], b [i32] } [i32] { ret (a + b), }]], "embedded_default_c.lua")
local session = lalin.compile("embedded_default_c", { add }, {
  out_dir = "target/lalin_binary_smoke/default_c_build",
})
local add_fn = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
assert(add_fn(20, 22) == 42)
session:free()
]=])
assert(command_ok("target/lalin " .. shell_quote(default_c_path)),
  "expected default compile to emit fused C, cook with GCC, and execute")

io.write("lalin binary ok\n")
