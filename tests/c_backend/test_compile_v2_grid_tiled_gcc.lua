package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local session = lalin.compile_v2("v2_grid_tiled_public", [=[
fn grid_copy(dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i, j in grid(0 .. h, 0 .. w) do
    dst[i * w + j] = src[i * w + j]
  end
end

fn tiled_double(dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 3 do
    dst[i * w + j] = src[i * w + j] * 2
  end
end

fn generalized_grid(dst [ptr [i32]], h [index], w [index]) [void] do
  loop i, j in grid(1 .. h .. 2, 4 .. 0 .. -2) do
    dst[i * w + j] = 7
  end
end

fn grid_fold(src [ptr [i32]], h [index], w [index]) [i32] do
  loop i, j in grid(0 .. h, 0 .. w) do
    fold acc [i32] = 5 by add step src[i * w + j]
  end
end

fn tiled_fold(src [ptr [i32]], h [index], w [index]) [i32] do
  loop i, j in tiled grid(0 .. h, 0 .. w) by 3, 2 do
    fold acc [i32] = 1 by mul step src[i * w + j]
  end
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_grid_tiled_gcc",
})

local source = assert(session:get_source())
assert(not source:find("frag_fn_grid_copy_kernel_", 1, true),
  "multi-axis grid must retain canonical scalar C until ND CMat is materialized")
assert(not source:find("frag_fn_tiled_double_kernel_", 1, true),
  "tiled grid must retain canonical scalar C until tiled CMat is materialized")

local src = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
local grid = ffi.new("int32_t[6]")
local tiled = ffi.new("int32_t[6]")
local grid_copy = assert(session:symbol(
  "grid_copy", "void (*)(int32_t *, int32_t *, size_t, size_t, size_t)"))
local tiled_double = assert(session:symbol(
  "tiled_double", "void (*)(int32_t *, int32_t *, size_t, size_t, size_t)"))
grid_copy(grid, src, 2, 3, 6)
tiled_double(tiled, src, 2, 3, 6)
for i = 0, 5 do
  assert(grid[i] == src[i], "row-major grid lane " .. i)
  assert(tiled[i] == src[i] * 2, "tiled full-domain lane " .. i)
end

local generalized_grid = assert(session:symbol(
  "generalized_grid", "void (*)(int32_t *, size_t, size_t)"))
local marked = ffi.new("int32_t[30]")
generalized_grid(marked, 6, 5)
local expected = { [7] = true, [9] = true, [17] = true,
  [19] = true, [27] = true, [29] = true }
for i = 0, 29 do
  assert(marked[i] == (expected[i] and 7 or 0),
    "generalized grid coordinate " .. i)
end

local grid_fold = assert(session:symbol(
  "grid_fold", "int32_t (*)(int32_t *, size_t, size_t)"))
local tiled_fold = assert(session:symbol(
  "tiled_fold", "int32_t (*)(int32_t *, size_t, size_t)"))
assert(grid_fold(src, 2, 3) == 26, "global grid fold")
assert(grid_fold(src, 0, 3) == 5, "zero-trip grid fold returns seed")
assert(tiled_fold(src, 2, 3) == 720, "global tiled fold")
assert(tiled_fold(src, 2, 0) == 1, "zero-trip tiled fold returns seed")

session:free()
print("public schema-v2 multi-axis grid/tiled GCC paths ok")
