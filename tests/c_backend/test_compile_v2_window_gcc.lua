package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local source = [=[
fn previous(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    dst[i] = xs[i - 1]
  end
end
]=]

local artifact = lalin.compile_v2("v2_window_source", source)
assert(artifact.source:match("window_clamped"), "schema-v2 CMat must emit dynamic clamp realization")
assert(artifact.source:match("kernel_loop"), "schema-v2 CMat fragment must replace the parsed loop")

local session = lalin.compile_v2("v2_window_public", source, {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_window_gcc",
})
local previous = assert(session:symbol(
  "previous", "void (*)(int32_t *, int32_t *, size_t)"))
local xs = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
local dst = ffi.new("int32_t[5]", { -1, -1, -1, -1, -1 })

previous(dst, xs, 0)
assert(dst[0] == -1, "zero-trip window must not store")
previous(dst, xs, 5)
assert(dst[0] == 10 and dst[1] == 10 and dst[2] == 20
  and dst[3] == 30 and dst[4] == 40, "1D clamp window result")

session:free()

-- Source coordinates, not line number alone, own parsed-loop identity.
local identity_session = lalin.compile_v2("v2_loop_identity", [=[
fn fill7(xs [ptr [i32]], n [index]) [void] do requires bounds(xs)(n), writeonly(xs) loop i in 0 .. n do xs[i] = 7 end end fn fill9(xs [ptr [i32]], n [index]) [void] do requires bounds(xs)(n), writeonly(xs) loop j in 0 .. n do xs[j] = 9 end end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_loop_identity_gcc",
})
local fill7 = assert(identity_session:symbol(
  "fill7", "void (*)(int32_t *, size_t)"))
local fill9 = assert(identity_session:symbol(
  "fill9", "void (*)(int32_t *, size_t)"))
local sevens, nines = ffi.new("int32_t[2]"), ffi.new("int32_t[2]")
fill7(sevens, 2)
fill9(nines, 2)
assert(sevens[0] == 7 and sevens[1] == 7
  and nines[0] == 9 and nines[1] == 9, "same-line loop identities")
identity_session:free()

print("public schema-v2 1D clamp window GCC path ok")
