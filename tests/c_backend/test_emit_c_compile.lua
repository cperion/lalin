package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local ok, why = c_gcc.available()
assert(type(ok) == "boolean", "available returns boolean")
if not ok then
    assert(type(why) == "table" and why.skip == true, "absent gcc runner should report skip diagnostic")
    io.write("gcc C runner not available; skip ok\n")
    os.exit(0)
end

local src = [[
fn add(a [i32], b [i32]) [i32]
  return a + b
end
]]
local parsed = assert(lalin.loadstring(src, "@test_c_gcc.lln"))
local session, c_src = lalin.compile_c_gcc("gcc_add", parsed, {
    gcc_opts = {
        opt = 3,
        out_dir = "target/test_c_gcc",
        stem = "gcc_add",
    },
})
assert(type(c_src) == "string" and c_src:match("int32_t add"), "gcc runner must compile emit_c output")
assert(session.artifact and session.artifact.kind == "CBackendArtifact", "gcc runner should retain emit_c artifact")
assert(session.c_path and session.so_path, "gcc runner should expose cooked C/shared-object paths")
local add = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
assert(add(20, 22) == 42, "gcc-compiled emit_c symbol should execute through LuaJIT FFI")
session:free()

io.write("lalin.emit_c_compile compile-run ok\n")
