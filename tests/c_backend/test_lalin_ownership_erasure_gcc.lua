package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local lalin = require("lalin")

local source = [=[
struct Record
  value [i32]
end
struct Store
  record [Record]
end
handle Store.Ref [u32]
  invalid = 0
  domain [Store]
  target [Record]
end
region Store.resolve(self [readonly [ptr [Store]]], ref [Store.Ref];
  granted(record [lease("self", ptr [Record])]),
  missing(ref [Store.Ref])
)
  entry start()
    jump missing(ref)
  end
end

fn f_read(p [readonly [ptr [i32]]]) [i32] do
  return p[0]
end
fn f_write(p [writeonly [ptr [i32]]], value [i32]) [i32] do
  p[0] = value
  return p[0]
end
fn f_keep(p [preserve [ptr [i32]]]) [i32] do
  return p[0]
end
fn f_sink(p [noescape [ptr [i32]]]) [i32] do
  return p[0]
end
fn f_temp(p [lease("p", ptr [i32])]) [i32] do
  return p[0]
end
fn f_view(xs [view [i32]]) [index] do
  return 0
end
fn ownership_matrix(p [ptr [i32]]) [i32] do
  let a [i32] = f_read(p)
  let b [i32] = f_write(p, a + 1)
  let c [i32] = f_keep(p)
  let sink [i32] = f_sink(p)
  let d [i32] = f_temp(p)
  return a + b + c + sink + d
end
]=]

local decls = assert(lalin.loadstring(source, "@ownership-erasure-gcc.lln"))
local artifact = lalin.emit_c(decls, {
  name = "ownership_erasure_gcc",
  c_path = "target/test_lalin_ownership_erasure_gcc/ownership.c",
  h_path = "target/test_lalin_ownership_erasure_gcc/ownership.h",
  combined_path = "target/test_lalin_ownership_erasure_gcc/ownership_combined.c",
})
assert(not artifact.source:find("lease", 1, true), "lease ownership must erase from emitted C")
assert(not artifact.source:find("borrow", 1, true), "emitted C must not contain runtime borrow tracking")
assert(not artifact.source:find("preserve", 1, true), "preserve ownership must erase from emitted C")
assert(not artifact.source:find("noescape", 1, true), "noescape ownership must erase from emitted C")
assert(not artifact.source:find("writeonly", 1, true), "writeonly ownership must erase from emitted C")
assert(not artifact.source:find("readonly", 1, true), "readonly ownership must erase from emitted C")

local session = lalin.compile_c_gcc("ownership_erasure_gcc", decls, {
  gcc_opts = { opt = 3, out_dir = "target/test_lalin_ownership_erasure_gcc" },
})
local matrix = assert(session:symbol("ownership_matrix", "int32_t (*)(int32_t *)"))
local value = ffi.new("int32_t[1]", 10)
assert(matrix(value) == 54, "ownership-erased pointer operations must execute through GCC")
assert(value[0] == 11, "writeonly pointer operation must update caller storage")
session:free()

io.write("lalin ownership erasure gcc ok\n")

