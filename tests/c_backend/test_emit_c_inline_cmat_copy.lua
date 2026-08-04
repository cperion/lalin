package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local function shell_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function command_ok(cmd) local ok = os.execute(cmd); return ok == true or ok == 0 end
local function write_file(path, text) local f = assert(io.open(path, "wb")); f:write(text); f:close() end

local src = [=[
fn copy_i32(dst [ptr [i32]], src [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src)
  requires disjoint(dst)(src)
  loop i in 0 .. n do
    dst[i] = src[i]
  end
end
]=]

local parsed = assert(lalin.loadstring(src, "@test_emit_c_inline_cmat_copy.lln"))
local dir = "target/test_emit_c_inline_cmat_copy"
local artifact = lalin.emit_c(parsed, { name = "emit_c_inline_cmat_copy", c_path = dir .. "/copy_i32.c", h_path = dir .. "/copy_i32.h" })
-- Typed pipeline contract: the loop body lowers to an inline CMat kernel
-- fragment (frag_fn_<fn>_kernel_) owning lane loads; no outlined stencil C.
assert(artifact.source:find("frag_fn_copy_i32_kernel_", 1, true), "copy loop must route through inline CMat")
assert(artifact.source:find("_load", 1, true), "CMat copy fragment should own lane loads")
assert(not artifact.source:find("ml_stencil_store_n", 1, true), "main emit_c path must inline copy CMat, not outline stencil C")

if command_ok("command -v gcc >/dev/null 2>&1") then
    write_file(dir .. "/main.c", [[
#include <stdint.h>
#include <stddef.h>
#include "copy_i32.h"
int main(void) {
    int32_t src[4] = { 4, -1, 9, 2 };
    int32_t dst[4] = { 0, 0, 0, 0 };
    copy_i32(dst, src, 4);
    return dst[0] == 4 && dst[1] == -1 && dst[2] == 9 && dst[3] == 2 ? 0 : 1;
}
]])
    assert(command_ok("gcc -std=c99 -O3 " .. shell_quote(dir .. "/copy_i32.c") .. " " .. shell_quote(dir .. "/main.c") .. " -o " .. shell_quote(dir .. "/copy_i32_test")), "gcc should compile emitted inline CMat copy")
    assert(command_ok(shell_quote(dir .. "/copy_i32_test")), "inline CMat copy should run correctly")
end

io.write("lalin emit_c inline CMat copy ok\n")
