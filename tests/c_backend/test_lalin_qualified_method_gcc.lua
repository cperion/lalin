package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
    assert(why.skip == true)
    io.write("lalin qualified method GCC skipped\n")
    os.exit(0)
end

local parsed = assert(lalin.loadstring([=[
struct Point
  x [i32]
  y [i32]
end

fn Point.sum(self [ptr [Point]]) [i32] do
  return self.x + self.y
end

fn explicit_receiver(p [ptr [Point]]) [i32] do
  return sum(p)
end

fn injected_receiver(p [ptr [Point]]) [i32] do
  return p:sum()
end
]=], "@qualified-method-runtime.lln"))

local session = lalin.compile_c_gcc("qualified_method_gcc", parsed, {
    gcc_opts = { opt = 3, out_dir = "target/test_lalin_qualified_method_gcc", stem = "qualified_method_gcc" },
})
ffi.cdef("typedef struct { int32_t x; int32_t y; } lalin_test_point;")
local point = ffi.new("lalin_test_point[1]")
point[0].x, point[0].y = 19, 23
local explicit_receiver = assert(session:symbol("explicit_receiver", "int32_t (*)(void *)"))
local injected_receiver = assert(session:symbol("injected_receiver", "int32_t (*)(void *)"))
assert(explicit_receiver(point) == 42, "qualified function call must pass an explicit receiver")
assert(injected_receiver(point) == 42, "method call must inject its receiver")
session:free()

io.write("lalin qualified method GCC ok: explicit=42 injected=42\n")
