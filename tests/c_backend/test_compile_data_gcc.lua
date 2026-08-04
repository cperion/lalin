package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

ffi.cdef[[
typedef struct { void* data; size_t len; } lalin_slice_t;
]]

local session = lalin.compile_source("data_public", [=[
fn greeting() [slice [u8]] do
  return "hello"
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_source_data_gcc",
})

local greeting = assert(session:symbol("greeting", "lalin_slice_t (*)(void)"))
local value = greeting()
assert(value.len == 5)
assert(ffi.string(value.data, value.len) == "hello")
session:free()

print("public schema data/slice GCC path ok")
