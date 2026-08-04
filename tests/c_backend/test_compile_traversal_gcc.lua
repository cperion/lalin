package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local session = lalin.compile_source("traversal_public", [=[
fn stride_copy(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 1 .. n .. 2 do
    dst[i] = xs[i]
  end
end

fn backward_copy(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in n - 1 .. -1 .. -1 do
    dst[i] = xs[i]
  end
end

fn stride_fold(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 1 .. n .. 2 do
    fold acc [i32] = 7 by add step xs[i] * 2
  end
end

fn backward_scan(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in n - 1 .. -1 .. -1 do
    scan acc [i32] = 0 by add step xs[i] into dst[i]
  end
end

fn empty_forward(dst [ptr [i32]]) [void] do
  loop i in 6 .. 4 do
    dst[i] = 99
  end
end

fn empty_backward(dst [ptr [i32]]) [void] do
  loop i in 2 .. 4 .. -1 do
    dst[i] = 99
  end
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_source_traversal_gcc",
})

local source = assert(session:get_source())
for _, name in ipairs({ "stride_copy", "backward_copy", "stride_fold", "backward_scan" }) do
  assert(source:find("frag_fn_" .. name .. "_kernel_", 1, true),
    name .. " must materialize through the typed CMat traversal path")
end

local xs = ffi.new("int32_t[7]", { 3, -2, 5, 4, -1, 6, 8 })
local dst = ffi.new("int32_t[7]", { 91, 92, 93, 94, 95, 96, 97 })
local stride_copy = assert(session:symbol(
  "stride_copy", "void (*)(int32_t *, int32_t *, size_t)"))
stride_copy(dst, xs, 7)
assert(dst[0] == 91 and dst[1] == -2 and dst[2] == 93 and dst[3] == 4
    and dst[4] == 95 and dst[5] == 6 and dst[6] == 97,
  "nonzero-start non-unit traversal must visit exactly 1,3,5")

local backward_copy = assert(session:symbol(
  "backward_copy", "void (*)(int32_t *, int32_t *, size_t)"))
backward_copy(dst, xs, 7)
for i = 0, 6 do assert(dst[i] == xs[i], "backward copy lane " .. i) end

local stride_fold = assert(session:symbol(
  "stride_fold", "int32_t (*)(int32_t *, size_t)"))
assert(stride_fold(xs, 0) == 7, "empty nonzero-start fold returns seed")
assert(stride_fold(xs, 7) == 23, "strided arithmetic fold")

local backward_scan = assert(session:symbol(
  "backward_scan", "void (*)(int32_t *, int32_t *, size_t)"))
backward_scan(dst, xs, 7)
local suffix = { 23, 20, 22, 17, 13, 14, 8 }
for i = 0, 6 do assert(dst[i] == suffix[i + 1], "backward inclusive scan lane " .. i) end

local empty_forward = assert(session:symbol("empty_forward", "void (*)(int32_t *)"))
local empty_backward = assert(session:symbol("empty_backward", "void (*)(int32_t *)"))
for i = 0, 6 do dst[i] = 41 end
empty_forward(dst)
empty_backward(dst)
for i = 0, 6 do assert(dst[i] == 41, "empty traversal must not store") end

session:free()
print("public schema nonzero/non-unit/backward traversal GCC paths ok")
