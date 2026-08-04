package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local function shell_quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local function command_ok(cmd) local ok = os.execute(cmd); return ok == true or ok == 0 end
local function write_file(path, text) local f = assert(io.open(path, "wb")); f:write(text); f:close() end

local src = [=[
fn prefix_sum(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void]
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs)
  requires disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by add step xs[i] into dst[i]
  end
end
]=]

local parsed = assert(lalin.loadstring(src, "@test_emit_c_inline_cmat_scan.lln"))
local dir = "target/test_emit_c_inline_cmat_scan"
local artifact = lalin.emit_c(parsed, {
    name = "emit_c_inline_cmat_scan",
    c_path = dir .. "/prefix_sum.c",
    h_path = dir .. "/prefix_sum.h",
})

-- Typed pipeline contract: the scan loop lowers to an inline CMat kernel
-- fragment (frag_fn_<fn>_kernel_) owning the scan lane; no outlined stencil C.
assert(artifact.source:find("frag_fn_prefix_sum_kernel_", 1, true), "scan loop must route through inline CMat")
assert(artifact.source:find("_scan", 1, true), "CMat scan fragment should own the scan lane")
assert(not artifact.source:find("ml_stencil_scan_n", 1, true), "main emit_c path must inline scan CMat, not outline stencil C")
assert(not artifact.source:find("semantic vector main loop", 1, true), "old direct vector KernelEffect emitter must not be present")

if command_ok("command -v gcc >/dev/null 2>&1") then
    write_file(dir .. "/main.c", [[
#include <stdint.h>
#include <stddef.h>
#include "prefix_sum.h"

int main(void) {
    int32_t xs[5] = { 1, -2, 5, 0, 3 };
    int32_t dst[5] = { 0, 0, 0, 0, 0 };
    prefix_sum(dst, xs, 5);
    return dst[0] == 1 && dst[1] == -1 && dst[2] == 4 && dst[3] == 4 && dst[4] == 7 ? 0 : 1;
}
]])
    assert(command_ok("gcc -std=c99 -O3 " .. shell_quote(dir .. "/prefix_sum.c") .. " " .. shell_quote(dir .. "/main.c") .. " -o " .. shell_quote(dir .. "/prefix_sum_test")), "gcc should compile emitted inline CMat scan")
    assert(command_ok(shell_quote(dir .. "/prefix_sum_test")), "inline CMat scan should run correctly")
end

io.write("lalin emit_c inline CMat scan ok\n")
