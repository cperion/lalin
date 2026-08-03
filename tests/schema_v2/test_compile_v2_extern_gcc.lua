package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

-- The extern declaration must keep its typed signature ([i32] -> [i32]) and
-- its declared C linkage symbol (`abs`) across Tree -> Code -> LOWER -> C.
-- The emitted C unit declares and calls `abs` directly (no `extern_c_absolute`
-- fallback name), and the GCC-cooked session runs run_abs against the real
-- libc symbol.
local session = lalin.compile_v2("v2_extern_c_absolute", [=[
extern c_absolute(x [i32]) [i32] do
  symbol = "abs"
end
fn run_abs(x [i32]) [i32] do
  return c_absolute(x)
end
]=], {
  gcc = true,
  opt = 3,
  out_dir = "target/test_compile_v2_extern_gcc",
})

local source = assert(session:get_source(), "extern GCC session must expose the emitted C source")
assert(source:find("extern int32_t abs(int32_t);", 1, true) ~= nil,
  "emitted C must declare the extern C symbol `abs` with its typed signature")

local run_abs = assert(session:symbol("run_abs", "int32_t (*)(int32_t)"))
assert(run_abs(-7) == 7)
assert(run_abs(5) == 5)
session:free()

print("schema_v2 typed extern signature/symbol projection through GCC ok")
