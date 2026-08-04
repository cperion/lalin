package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local session = lalin.compile_source("fold_public", [=[
fn sum_seeded(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 7 by add step xs[i] * 2
  end
end

fn sum_unproven(xs [ptr [i32]], n [index]) [i32] do
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

fn fold_and(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = -1 by band step xs[i]
  end
end

fn fold_or(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 0 by bor step xs[i]
  end
end

fn fold_xor(xs [ptr [i32]], n [index]) [i32] do
  requires bounds(xs)(n), readonly(xs)
  loop i in 0 .. n do
    fold acc [i32] = 0 by bxor step xs[i]
  end
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_source_fold_gcc",
})

local source = assert(session:get_source())
assert(source:find("frag_fn_sum_seeded_kernel_", 1, true),
  "sum fold must materialize through the CMat fragment path")
for _, name in ipairs({ "fold_mul", "fold_min", "fold_max",
    "fold_and", "fold_or", "fold_xor" }) do
  assert(source:find("frag_fn_" .. name .. "_kernel_", 1, true),
    name .. " must materialize through the CMat fragment path")
end

local sum_seeded = assert(session:symbol(
  "sum_seeded", "int32_t (*)(int32_t *, size_t)"))
local sum_unproven = assert(session:symbol(
  "sum_unproven", "int32_t (*)(int32_t *, size_t)"))
local function fold_symbol(name)
  return assert(session:symbol(name, "int32_t (*)(int32_t *, size_t)"))
end
local fold_mul, fold_min, fold_max = fold_symbol("fold_mul"),
  fold_symbol("fold_min"), fold_symbol("fold_max")
local fold_and, fold_or, fold_xor = fold_symbol("fold_and"),
  fold_symbol("fold_or"), fold_symbol("fold_xor")
local xs = ffi.new("int32_t[5]", { 3, -2, 5, 4, -1 })
assert(sum_seeded(xs, 0) == 7, "zero-trip fold must return its seed")
assert(sum_seeded(xs, 1) == 13, "one-trip fold")
assert(sum_seeded(xs, 5) == 25, "many-trip arithmetic sum fold")
assert(sum_unproven(xs, 0) == 0 and sum_unproven(xs, 5) == 9,
  "missing optimization evidence must retain correct conservative scalar C")
assert(fold_mul(xs, 0) == 1 and fold_mul(xs, 5) == 120, "multiply fold")
assert(fold_min(xs, 0) == 2147483647 and fold_min(xs, 5) == -2, "minimum fold")
assert(fold_max(xs, 0) == -2147483647 and fold_max(xs, 5) == 5, "maximum fold")
assert(fold_and(xs, 0) == -1 and fold_and(xs, 5) == 0, "bit-and fold")
assert(fold_or(xs, 0) == 0 and fold_or(xs, 5) == -1, "bit-or fold")
assert(fold_xor(xs, 0) == 0 and fold_xor(xs, 5) == 3, "bit-xor fold")
session:free()

print("public schema typed 1D integer fold reducer matrix GCC path ok")
