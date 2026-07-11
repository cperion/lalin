package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.compiler_api")
local Compiler = require("lalin.schema_v2.compiler")

local source_a = [=[
extern host_a(x [i32]) [i32]
end
fn a(x [i32]) [i32] do
  return x + 1
end
fn greeting() [slice [u8]] do
  return "hello"
end
]=]

local source_b = [=[
extern host_b(x [f64]) [f64]
end
fn b(x [f64]) [f64] do
  return x
end
]=]

local function compile(name, source)
  return Compiler.CompilerSession(source, name):compile()
end

local function assert_ok(name, source)
  local artifact = compile(name, source)
  assert(not tostring(asdl.classof(artifact)):match("CompilerArtifactError"), tostring(artifact.message))
  assert(tostring(asdl.classof(artifact)):match("CompilerArtifactC"))
  return artifact.source
end

local a1 = assert_ok("A", source_a)
local b1 = assert_ok("B", source_b)
local a2 = assert_ok("A", source_a)
local a3 = assert_ok("A", source_a)

assert(a1 == a2, "public A -> B -> A compile sessions differ")
assert(a2 == a3, "public repeated compile session differs")
assert(a1:match("int32_t a%(") and a1:match("greeting%(") )
assert(not a1:match("double b%(") and not a1:match("host_b"))
assert(b1:match("double b%(") )
assert(not b1:match("int32_t a%(") and not b1:match("greeting%(") and not b1:match("host_a"))

local failed = compile("Bad", "fn broken( do end")
assert(tostring(asdl.classof(failed)):match("CompilerArtifactError"), "invalid session unexpectedly succeeded")
assert(assert_ok("A", source_a) == a1, "failed public session contaminated following success")

print("lalin public compile session isolation ok")
