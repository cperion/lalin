package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local session = lalin.compile_v2("v2_scalar_public", [=[
fn add(a [i32], b [i32]) [i32] do
  return a + b
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_scalar_gcc",
})

local add = assert(session:symbol("add", "int32_t (*)(int32_t, int32_t)"))
assert(add(4, 5) == 9)
session:free()

print("public schema-v2 scalar GCC path ok")
