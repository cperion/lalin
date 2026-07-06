package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

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

local src = [=[
fn sum_i32(xs [ptr [i32]], n [index]) [i32]
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 0 by add step xs[i]
  end
end
]=]

local parsed = assert(lalin.loadstring(src, "@test_emit_c_inline_cmat_reduce.lln"))
local dir = "target/test_emit_c_inline_cmat_reduce"
local artifact = lalin.emit_c(parsed, {
    name = "emit_c_inline_cmat_reduce",
    c_path = dir .. "/sum_i32.c",
    h_path = dir .. "/sum_i32.h",
})

assert(artifact.source:find("semantic scalar CMat kernel", 1, true), "reduction loop must route through inline CMat")
assert(artifact.source:find("semantic_cmat_load", 1, true), "CMat reduction should own lane loads")
assert(not artifact.source:find("KernelEffectFold", 1, true), "fold must not leak as direct KernelEffect emission")
assert(not artifact.source:find("ml_stencil_reduce_n", 1, true), "main emit_c path must inline reduce CMat, not outline stencil C")
assert(artifact.source:find("return", 1, true), "reduction function should return computed accumulator")

if command_ok("command -v gcc >/dev/null 2>&1") then
    write_file(dir .. "/main.c", [[
#include <stdint.h>
#include <stddef.h>
#include "sum_i32.h"

int main(void) {
    int32_t xs[5] = { 1, -2, 5, 0, 3 };
    return sum_i32(xs, 5) == 7 ? 0 : 1;
}
]])
    assert(command_ok("gcc -std=c99 -O3 " .. shell_quote(dir .. "/sum_i32.c") .. " " .. shell_quote(dir .. "/main.c") .. " -o " .. shell_quote(dir .. "/sum_i32_test")), "gcc should compile emitted inline CMat reduction")
    assert(command_ok(shell_quote(dir .. "/sum_i32_test")), "inline CMat reduction should run correctly")
end

io.write("lalin emit_c inline CMat reduce ok\n")
