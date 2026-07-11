package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")

local source = [=[
struct Pair
  x [i32]
  y [i32]
end

fn expression_matrix() [i32] do
  let xs [array [i32] [3]] = { 10, 20, 12 }
  var pair [Pair] = Pair { x = 3, y = 4 }
  pair.y = 7
  let p [ptr [i32]] = &xs[0]
  p[1] = 21
  return as [i32](sizeof [i32])
    + as [i32](sizeof [Pair])
    + as [i32](sizeof [array [i32] [3]])
    + as [i32](p[1])
    + pair.x
    + pair.y
end
]=]

local decls = assert(lalin.loadstring(source, "@parsed-expressions-gcc.lln"))
local session = lalin.compile_c_gcc("parsed_expressions_gcc", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_lalin_parsed_expressions_gcc" },
})
local expression_matrix = assert(session:symbol("expression_matrix", "int32_t (*)(void)"))
assert(expression_matrix() == 55, "sizeof/cast/index/field/record/array matrix must execute through GCC")
session:free()

io.write("lalin parsed expressions gcc ok\n")
