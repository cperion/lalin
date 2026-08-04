package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local lalin = require("lalin")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
  assert(why.skip == true)
  io.write("schema parsed expressions GCC skipped\n")
  os.exit(0)
end

-- Mirrors tests/c_backend/test_lalin_parsed_expressions_gcc.lua but through
-- the schema compile_source pipeline: array-typed locals, aggregate
-- initialization, casts, indexing, field access, and aggregate returns.
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

fn mk_pair(x [i32]) [Pair] do
  return Pair { x = x, y = x + 1 }
end

fn copy_array(src [array [i32] [3]]) [i32] do
  let dst [array [i32] [3]] = src
  dst[2] = dst[0] + dst[1]
  return dst[0] + dst[1] + dst[2]
end
]=]

-- C artifact shape: struct decls are concrete (not opaque), with the
-- emitted-C __offset_N field naming contract matching place access.
local artifact = lalin.compile_source("parsed_expressions_source", source)
assert(artifact.source ~= nil and #artifact.source > 0, "no C source emitted")
assert(artifact.source:match("typedef struct module_Pair %{"),
  "struct decl must be emitted concretely")
assert(artifact.source:match("__offset_0"), "struct decl must carry the emitted-C __offset_N field contract")
assert(artifact.source:match("__offset_4"), "struct decl must carry offset 4 field")

local session = lalin.compile_source("parsed_expressions_gcc", source, {
  gcc = true,
  opt = 3,
  out_dir = "target/test_parsed_expressions_gcc",
})
local expression_matrix = assert(session:symbol("expression_matrix", "int32_t (*)(void)"))
assert(expression_matrix() == 55, "sizeof/cast/index/field/record/array matrix must execute through GCC")
local ffi = require("ffi")
ffi.cdef[[
typedef struct { int32_t x; int32_t y; } module_Pair;
]]
local mk_pair = assert(session:symbol("mk_pair", "module_Pair (*)(int32_t)"))
local p = mk_pair(5)
assert(p.x == 5 and p.y == 6, "aggregate return must round-trip field values through GCC")
local copy_array = assert(session:symbol("copy_array", "int32_t (*)(int32_t*)"))
local arr = ffi.new("int32_t[3]", { 10, 20, 12 })
assert(copy_array(arr) == 60, "array local copy + index store must execute through GCC")
session:free()

io.write("schema parsed expressions GCC ok\n")
