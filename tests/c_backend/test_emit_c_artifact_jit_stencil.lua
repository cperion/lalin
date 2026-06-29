package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s)
    s = tostring(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
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

local src = [=[
local zip_add = fn(dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  requires disjoint(dst)(lhs), disjoint(dst)(rhs), disjoint(lhs)(rhs)
  loop i in 0 .. n do
    dst[i] = lhs[i] + rhs[i]
  end
end

return { zip_add }
]=]

local parsed = assert(lalin.loadstring(src, "@test_emit_c_artifact_jit_stencil.lln"))()
local dir = "target/test_emit_c_artifact_jit_stencil"
local artifact = lalin.emit_c_artifact(parsed, {
    name = "emit_c_jit_stencil",
    c_path = dir .. "/zip_add.c",
    h_path = dir .. "/zip_add.h",
})

assert(artifact.kind == "LuaJITCSourceArtifact", "emit_c_artifact should use the LuaJIT C artifact path")
assert(#artifact.artifacts == 1, "expected one selected stencil artifact")
assert(artifact.source:match("static inline void ml_stencil_"), "selected stencil should be emitted as inline C")
assert(artifact.source:match("void zip_add%("), "residual function should be emitted as C")
assert(artifact.source:match("ml_stencil_[%w_]+%([^;]-v_zip_add_arg_zip_add_dst"), "residual should call selected stencil directly")
assert(not artifact.source:match("__lalin_luajit_stencil_symbols"), "emit_c must not route through a LuaJIT stencil symbol table")
assert(not artifact.source:match("mmap"), "emit_c must not install an MC bank")
assert(not artifact.source:match("LuaTrace"), "emit_c must not emit BC artifacts")

if command_ok("command -v gcc >/dev/null 2>&1") then
    write_file(dir .. "/main.c", [[
#include <stdint.h>
#include <stddef.h>

void zip_add(int32_t *dst, int32_t *lhs, int32_t *rhs, intptr_t n);

int main(void) {
    int32_t lhs[5] = { 1, -2, 5, 0, 3 };
    int32_t rhs[5] = { 10, 20, -5, 7, 4 };
    int32_t dst[5] = { 0, 0, 0, 0, 0 };
    zip_add(dst, lhs, rhs, 5);
    return dst[0] == 11 && dst[1] == 18 && dst[2] == 0 && dst[3] == 7 && dst[4] == 7 ? 0 : 1;
}
]])
    assert(command_ok("gcc -std=c99 -O3 " .. shell_quote(dir .. "/zip_add.c") .. " " .. shell_quote(dir .. "/main.c") .. " -o " .. shell_quote(dir .. "/zip_add_test")), "gcc should compile emitted JIT C artifact")
    assert(command_ok(shell_quote(dir .. "/zip_add_test")), "emitted JIT C artifact should run correctly")
end

io.write("lalin emit_c_artifact jit stencil ok\n")
