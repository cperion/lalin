package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local session = lalin.compile_v2("v2_fold_public", [=[
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
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_fold_gcc",
})

local source = assert(session:get_source())
assert(source:find("frag_fn_sum_seeded_kernel_", 1, true),
  "sum fold must materialize through the CMat fragment path")

local sum_seeded = assert(session:symbol(
  "sum_seeded", "int32_t (*)(int32_t *, size_t)"))
local sum_unproven = assert(session:symbol(
  "sum_unproven", "int32_t (*)(int32_t *, size_t)"))
local xs = ffi.new("int32_t[5]", { 3, -2, 5, 4, -1 })
assert(sum_seeded(xs, 0) == 7, "zero-trip fold must return its seed")
assert(sum_seeded(xs, 1) == 13, "one-trip fold")
assert(sum_seeded(xs, 5) == 25, "many-trip arithmetic sum fold")
assert(sum_unproven(xs, 0) == 0 and sum_unproven(xs, 5) == 9,
  "missing optimization evidence must retain correct conservative scalar C")
session:free()

print("public schema-v2 typed 1D integer sum fold GCC path ok")
