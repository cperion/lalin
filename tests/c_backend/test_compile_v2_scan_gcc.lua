package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local session = lalin.compile_v2("v2_scan_public", [=[
fn scan_add(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 7 by add step xs[i] * 2 into dst[i]
  end
end

fn scan_mul(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 1 by mul over i step xs[i] into dst[i]
  end
end

fn scan_min(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 2147483647 by min over 1 step xs[i] into dst[i]
  end
end

fn scan_max(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = -2147483647 by max step xs[i] into dst[i]
  end
end

fn scan_and(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = -1 by band step xs[i] into dst[i]
  end
end

fn scan_or(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by bor step xs[i] into dst[i]
  end
end

fn scan_xor(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by bxor step xs[i] into dst[i]
  end
end

fn scan_in_place(xs [ptr [i32]], n [index]) [void] do
  requires bounds(xs)(n)
  loop i in 0 .. n do
    scan acc [i32] = 0 by add step xs[i] into xs[i]
  end
end

fn scan_with_store(out [ptr [i32]], prefix [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(out)(n), writeonly(out), bounds(prefix)(n), writeonly(prefix)
  requires bounds(xs)(n), readonly(xs), disjoint(out)(prefix), disjoint(out)(xs), disjoint(prefix)(xs)
  loop i in 0 .. n do
    out[i] = xs[i] * 3
    scan acc [i32] = 0 by add step xs[i] into prefix[i]
  end
end

fn scan_shifted(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    scan acc [i32] = 0 by add step xs[i] into dst[i + 1]
  end
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_scan_gcc",
})

local source = assert(session:get_source())
for _, name in ipairs({ "scan_add", "scan_mul", "scan_min", "scan_max",
    "scan_and", "scan_or", "scan_xor" }) do
  assert(source:find("frag_fn_" .. name .. "_kernel_", 1, true),
    name .. " must materialize through the CMat fragment path")
end
assert(source:find("frag_fn_scan_with_store_kernel_", 1, true),
  "scan with an ordered sibling store must materialize through CMat")

local function symbol(name)
  return assert(session:symbol(name, "void (*)(int32_t *, int32_t *, size_t)"))
end
local xs = ffi.new("int32_t[5]", { 3, -2, 5, 4, -1 })
local dst = ffi.new("int32_t[5]", { 91, 92, 93, 94, 95 })

symbol("scan_add")(dst, xs, 0)
assert(dst[0] == 91, "zero-trip scan must not store")
symbol("scan_add")(dst, xs, 1)
assert(dst[0] == 13 and dst[1] == 92, "one-trip arithmetic scan")
symbol("scan_add")(dst, xs, 5)
assert(dst[0] == 13 and dst[1] == 9 and dst[2] == 19 and dst[3] == 27 and dst[4] == 25,
  "inclusive arithmetic add scan")

symbol("scan_mul")(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == -6 and dst[2] == -30 and dst[3] == -120 and dst[4] == 120,
  "inclusive multiply scan")
symbol("scan_min")(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == -2 and dst[2] == -2 and dst[3] == -2 and dst[4] == -2,
  "inclusive minimum scan")
symbol("scan_max")(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == 3 and dst[2] == 5 and dst[3] == 5 and dst[4] == 5,
  "inclusive maximum scan")
symbol("scan_and")(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == 2 and dst[2] == 0 and dst[3] == 0 and dst[4] == 0,
  "inclusive bit-and scan")
symbol("scan_or")(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == -1 and dst[2] == -1 and dst[3] == -1 and dst[4] == -1,
  "inclusive bit-or scan")
symbol("scan_xor")(dst, xs, 5)
assert(dst[0] == 3 and dst[1] == -3 and dst[2] == -8 and dst[3] == -4 and dst[4] == 3,
  "inclusive bit-xor scan")
local in_place = assert(session:symbol(
  "scan_in_place", "void (*)(int32_t *, size_t)"))
local aliased = ffi.new("int32_t[5]", { 3, -2, 5, 4, -1 })
in_place(aliased, 5)
assert(aliased[0] == 3 and aliased[1] == 1 and aliased[2] == 6
    and aliased[3] == 10 and aliased[4] == 9,
  "possible aliasing must retain inclusive scan order in conservative scalar C")
local scan_with_store = assert(session:symbol("scan_with_store",
  "void (*)(int32_t *, int32_t *, int32_t *, size_t)"))
local out, prefix = ffi.new("int32_t[5]"), ffi.new("int32_t[5]")
scan_with_store(out, prefix, xs, 5)
assert(out[0] == 9 and out[1] == -6 and out[2] == 15
    and out[3] == 12 and out[4] == -3,
  "scan must preserve its ordered sibling store")
assert(prefix[0] == 3 and prefix[1] == 1 and prefix[2] == 6
    and prefix[3] == 10 and prefix[4] == 9,
  "scan with sibling store must preserve inclusive prefixes")
local scan_shifted = assert(session:symbol(
  "scan_shifted", "void (*)(int32_t *, int32_t *, size_t)"))
local shifted = ffi.new("int32_t[6]", { 77, 0, 0, 0, 0, 0 })
scan_shifted(shifted, xs, 5)
assert(shifted[0] == 77 and shifted[1] == 3 and shifted[2] == 1
    and shifted[3] == 6 and shifted[4] == 10 and shifted[5] == 9,
  "a displaced scan store must retain conservative scalar C semantics")

session:free()
print("public schema-v2 typed inclusive scan reducer matrix GCC path ok")
