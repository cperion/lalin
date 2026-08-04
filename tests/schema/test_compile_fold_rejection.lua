package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema")
require("lalin.impl.compiler_api")

local Compiler = T.LalinCompiler

local shifted_source = [=[
fn shifted_sum(xs [ptr [i32]], n [index]) [i32] do
  loop i in 1 .. n do
    fold acc [i32] = 0 by add step xs[i]
  end
end
]=]
local shifted_session = Compiler.CompilerSession(
  shifted_source, "fold_shifted")
local shifted_ok, shifted = pcall(function() return shifted_session:compile() end)
assert(shifted_ok, "nonzero-start fold must compile through CompilerSession")
assert(asdl.classof(shifted) == Compiler.CompilerArtifactC,
  "nonzero-start fold is part of the implemented traversal surface")

local zero_step = Compiler.CompilerSession([=[
fn invalid(xs [ptr [i32]], n [index]) [i32] do
  loop i in 0 .. n .. 0 do
    fold acc [i32] = 0 by add step xs[i]
  end
end
]=], "fold_zero_step")
local invalid_ok, invalid = pcall(function() return zero_step:compile() end)
assert(invalid_ok, "invalid loop steps must remain compiler artifacts")
assert(asdl.classof(invalid) == Compiler.CompilerArtifactError)
assert(invalid.message:match("loop step must be nonzero"),
  "zero step must preserve its exact diagnostic")

print("public schema fold traversal and invalid-step diagnostics ok")
