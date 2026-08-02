package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local source = [=[
fn previous_clamp(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    dst[i] = xs[i - 1]
  end
end

fn previous_wrap(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 7, after = 7, boundary = wrap) do
    dst[i] = xs[i - 7]
  end
end

fn next_wrap(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 7, after = 7, boundary = wrap) do
    dst[i] = xs[i + 7]
  end
end

fn previous_zero(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = zero) do
    dst[i] = xs[i - 1]
  end
end

fn centered_reject(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = reject) do
    dst[i] = xs[i]
  end
end

fn window_pair(sum [ptr [i32]], copy [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(sum)(n), writeonly(sum), bounds(copy)(n), writeonly(copy)
  requires bounds(xs)(n), readonly(xs), disjoint(sum)(copy)
  requires disjoint(sum)(xs), disjoint(copy)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    sum[i] = xs[i - 1] + xs[i]
    copy[i] = xs[i]
  end
end

fn ordered_alias(a [ptr [i32]], b [ptr [i32]], n [index]) [void] do
  requires bounds(a)(n), writeonly(a), bounds(b)(n), writeonly(b)
  loop i in window(0 .. n, before = 1, after = 1, boundary = clamp) do
    a[i] = 1
    b[i] = 2
  end
end

fn integer_arithmetic(divs [ptr [i32]], rems [ptr [i32]], shifts [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(divs)(n), writeonly(divs), bounds(rems)(n), writeonly(rems)
  requires bounds(shifts)(n), writeonly(shifts), bounds(xs)(n), readonly(xs)
  requires disjoint(divs)(rems), disjoint(divs)(shifts), disjoint(divs)(xs)
  requires disjoint(rems)(shifts), disjoint(rems)(xs), disjoint(shifts)(xs)
  loop i in 0 .. n do
    divs[i] = xs[i] / 4
    rems[i] = xs[i] % 3
    shifts[i] = xs[i] << 2
  end
end
]=]

local artifact = lalin.compile_v2("v2_window_source", source)
assert(artifact.source:match("window_clamped"), "schema-v2 CMat must emit dynamic clamp realization")
assert(artifact.source:match("window_wrapped_target"), "schema-v2 CMat must emit dynamic wrap realization")
assert(artifact.source:match("window_zero_"), "schema-v2 CMat must emit dynamic zero realization")
assert(artifact.source:match("kernel_loop"), "schema-v2 CMat fragment must replace parsed loops")
local alias_params = assert(artifact.source:match("void ordered_alias%(([^\n]+)"))
assert(not alias_params:match("restrict"), "alias uncertainty must not emit restrict")

local session = lalin.compile_v2("v2_window_public", source, {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_window_gcc",
})
local previous_clamp = assert(session:symbol(
  "previous_clamp", "void (*)(int32_t *, int32_t *, size_t)"))
local previous_wrap = assert(session:symbol(
  "previous_wrap", "void (*)(int32_t *, int32_t *, size_t)"))
local next_wrap = assert(session:symbol(
  "next_wrap", "void (*)(int32_t *, int32_t *, size_t)"))
local previous_zero = assert(session:symbol(
  "previous_zero", "void (*)(int32_t *, int32_t *, size_t)"))
local centered_reject = assert(session:symbol(
  "centered_reject", "void (*)(int32_t *, int32_t *, size_t)"))
local window_pair = assert(session:symbol(
  "window_pair", "void (*)(int32_t *, int32_t *, int32_t *, size_t)"))
local ordered_alias = assert(session:symbol(
  "ordered_alias", "void (*)(int32_t *, int32_t *, size_t)"))
local integer_arithmetic = assert(session:symbol(
  "integer_arithmetic",
  "void (*)(int32_t *, int32_t *, int32_t *, int32_t *, size_t)"))
local xs = ffi.new("int32_t[5]", { 10, 20, 30, 40, 50 })
local dst = ffi.new("int32_t[5]", { -1, -1, -1, -1, -1 })

previous_clamp(dst, xs, 0)
assert(dst[0] == -1, "zero-trip window must not store")
previous_clamp(dst, xs, 5)
assert(dst[0] == 10 and dst[1] == 10 and dst[2] == 20
  and dst[3] == 30 and dst[4] == 40, "1D clamp window result")
previous_wrap(dst, xs, 5)
assert(dst[0] == 40 and dst[1] == 50 and dst[2] == 10
  and dst[3] == 20 and dst[4] == 30, "negative wrap beyond extent")
next_wrap(dst, xs, 5)
assert(dst[0] == 30 and dst[1] == 40 and dst[2] == 50
  and dst[3] == 10 and dst[4] == 20, "positive wrap beyond extent")
previous_zero(dst, xs, 5)
assert(dst[0] == 0 and dst[1] == 10 and dst[2] == 20
  and dst[3] == 30 and dst[4] == 40, "1D zero window result")
centered_reject(dst, xs, 5)
assert(dst[0] == 10 and dst[1] == 20 and dst[2] == 30
  and dst[3] == 40 and dst[4] == 50, "centered reject window result")
local sums, copies = ffi.new("int32_t[5]"), ffi.new("int32_t[5]")
window_pair(sums, copies, xs, 5)
assert(sums[0] == 20 and sums[1] == 30 and sums[2] == 50
  and sums[3] == 70 and sums[4] == 90, "window arithmetic stream result")
assert(copies[0] == 10 and copies[1] == 20 and copies[2] == 30
  and copies[3] == 40 and copies[4] == 50, "window multisink result")
local aliased = ffi.new("int32_t[5]")
ordered_alias(aliased, aliased, 5)
assert(aliased[0] == 2 and aliased[1] == 2 and aliased[2] == 2
  and aliased[3] == 2 and aliased[4] == 2,
  "potentially aliasing sinks must retain source order")
local divs, rems, shifts = ffi.new("int32_t[5]"), ffi.new("int32_t[5]"),
  ffi.new("int32_t[5]")
integer_arithmetic(divs, rems, shifts, xs, 5)
assert(divs[0] == 2 and divs[1] == 5 and divs[2] == 7
  and divs[3] == 10 and divs[4] == 12, "integer division helpers")
assert(rems[0] == 1 and rems[1] == 2 and rems[2] == 0
  and rems[3] == 1 and rems[4] == 2, "integer remainder helpers")
assert(shifts[0] == 40 and shifts[1] == 80 and shifts[2] == 120
  and shifts[3] == 160 and shifts[4] == 200, "masked shift helpers")

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

print("public schema-v2 1D window boundary/arithmetic/multisink GCC paths ok")
