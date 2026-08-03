package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
    assert(why.skip == true, "unavailable GCC runner must return a skip diagnostic")
    io.write("lalin parsed loop GCC matrix skipped\n")
    os.exit(0)
end

local source = [=[
fn plain(dst [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst)
  loop i in 0 .. n do
    dst[i] = 7
  end
end

fn copy(dst [ptr [i32]], src [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i in 0 .. n do
    dst[i] = src[i]
  end
end

fn fold_add(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 0 by add step xs[i]
  end
end

fn fold_mul(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 1 by mul step xs[i]
  end
end

fn fold_min(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 2147483647 by min step xs[i]
  end
end

fn fold_max(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = -2147483647 by max step xs[i]
  end
end

fn scan_add(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by add step xs[i] into dst[i]
  end
end

fn grid2d(dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i, j in grid(0 .. h, 0 .. w) do
    dst[i * w + j] = src[i * w + j]
  end
end

fn tiled2d(dst [ptr [i32]], src [ptr [i32]], h [index], w [index], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i, j in tiled grid(0 .. h, 0 .. w) by 2, 2 do
    dst[i * w + j] = src[i * w + j] * 2
  end
end

fn window_prev_clamp(dst [ptr [i32]], src [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(src)(n), readonly(src), disjoint(dst)(src)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    dst[i] = src[i - 1]
  end
end

fn soac_zip(dst [ptr [i32]], lhs [ptr [i32]], rhs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(lhs)(n), readonly(lhs), bounds(rhs)(n), readonly(rhs)
  requires disjoint(dst)(lhs), disjoint(dst)(rhs), disjoint(lhs)(rhs)
  loop i in 0 .. n do
    dst[i] = lhs[i] + rhs[i]
  end
end
]=]

local session = lalin.compile_v2("parsed_loops_gcc", source, {
    gcc = true,
    opt = 3,
    out_dir = "target/test_lalin_parsed_loops_gcc",
})

local function symbol(name, ctype) return assert(session:symbol(name, ctype)) end
local plain = symbol("plain", "void (*)(int32_t *, size_t)")
local copy = symbol("copy", "void (*)(int32_t *, int32_t *, size_t)")
local fold_add = symbol("fold_add", "int32_t (*)(int32_t *, size_t)")
local fold_mul = symbol("fold_mul", "int32_t (*)(int32_t *, size_t)")
local fold_min = symbol("fold_min", "int32_t (*)(int32_t *, size_t)")
local fold_max = symbol("fold_max", "int32_t (*)(int32_t *, size_t)")
local scan_add = symbol("scan_add", "void (*)(int32_t *, int32_t *, size_t)")
local grid2d = symbol("grid2d", "void (*)(int32_t *, int32_t *, size_t, size_t, size_t)")
local tiled2d = symbol("tiled2d", "void (*)(int32_t *, int32_t *, size_t, size_t, size_t)")
local window_prev_clamp = symbol("window_prev_clamp", "void (*)(int32_t *, int32_t *, size_t)")
local soac_zip = symbol("soac_zip", "void (*)(int32_t *, int32_t *, int32_t *, size_t)")

local xs = ffi.new("int32_t[5]", { 3, -2, 5, 4, -1 })
local dst = ffi.new("int32_t[6]", { 91, 92, 93, 94, 95, 96 })

plain(dst, 0)
assert(dst[0] == 91, "zero-trip plain loop must not store")
plain(dst, 1)
assert(dst[0] == 7 and dst[1] == 92, "one-trip plain loop must store exactly once")
plain(dst, 5)
assert(dst[0] == 7 and dst[1] == 7 and dst[2] == 7 and dst[3] == 7 and dst[4] == 7, "plain loop values")

copy(dst, xs, 0)
assert(dst[0] == 7, "zero-trip copy must not store")
copy(dst, xs, 1)
assert(dst[0] == 3 and dst[1] == 7, "one-trip copy")
copy(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == -2 and dst[2] == 5 and dst[3] == 4 and dst[4] == -1, "copy values")

assert(fold_add(xs, 0) == 0 and fold_add(xs, 1) == 3 and fold_add(xs, 5) == 9, "add fold zero/one/many")
assert(fold_mul(xs, 0) == 1 and fold_mul(xs, 1) == 3 and fold_mul(xs, 5) == 120, "mul fold zero/one/many")
assert(fold_min(xs, 1) == 3 and fold_min(xs, 5) == -2, "min fold")
assert(fold_max(xs, 1) == 3 and fold_max(xs, 5) == 5, "max fold")

scan_add(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == 1 and dst[2] == 6 and dst[3] == 10 and dst[4] == 9, "inclusive add scan")

local matrix_src = ffi.new("int32_t[6]", { 1, 2, 3, 4, 5, 6 })
local grid_dst = ffi.new("int32_t[6]")
local tiled_dst = ffi.new("int32_t[6]")
grid2d(grid_dst, matrix_src, 2, 3, 6)
assert(grid_dst[0] == 1 and grid_dst[1] == 2 and grid_dst[2] == 3 and grid_dst[3] == 4 and grid_dst[4] == 5 and grid_dst[5] == 6, "2D grid coordinates")
tiled2d(tiled_dst, matrix_src, 2, 3, 6)
assert(tiled_dst[0] == 2 and tiled_dst[1] == 4 and tiled_dst[2] == 6 and tiled_dst[3] == 8 and tiled_dst[4] == 10 and tiled_dst[5] == 12, "tiled 2D values")

local window_dst = ffi.new("int32_t[5]")
window_prev_clamp(window_dst, xs, 5)
assert(window_dst[0] == 3 and window_dst[1] == 3 and window_dst[2] == -2 and window_dst[3] == 5 and window_dst[4] == 4, "window clamp at the lower edge")

local rhs = ffi.new("int32_t[5]", { 10, 20, -5, 7, 4 })
soac_zip(dst, xs, rhs, 5)
assert(dst[0] == 13 and dst[1] == 18 and dst[2] == 0 and dst[3] == 11 and dst[4] == 3, "SOAC zip/map values")

session:free()
io.write("lalin parsed loop GCC matrix ok: plain=7,7,7,7,7 add=9 mul=120 min=-2 max=5 scan=3,1,6,10,9 grid=1,2,3,4,5,6 tiled=2,4,6,8,10,12 window=3,3,-2,5,4 soac=13,18,0,11,3\n")
