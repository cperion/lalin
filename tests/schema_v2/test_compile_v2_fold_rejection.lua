package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
require("lalin.impl.compiler_api")

local Compiler = T.LalinCompiler
local source = [=[
fn product(xs [ptr [i32]], n [index]) [i32] do
  loop i in 0 .. n do
    fold acc [i32] = 1 by mul step xs[i]
  end
end
]=]

local session = Compiler.CompilerSession(source, "v2_fold_reject")
local ok, result = pcall(function() return session:compile() end)
assert(ok, "unsupported reducer rejection must not escape CompilerSession as a Lua error")
assert(asdl.classof(result) == Compiler.CompilerArtifactError)
assert(result.message:match("currently supports only the add reducer"),
  "rejection must preserve the narrow sum-fold gate")

local shifted_source = [=[
fn shifted_sum(xs [ptr [i32]], n [index]) [i32] do
  loop i in 1 .. n do
    fold acc [i32] = 0 by add step xs[i]
  end
end
]=]
local shifted_session = Compiler.CompilerSession(
  shifted_source, "v2_fold_shifted_reject")
local shifted_ok, shifted = pcall(function() return shifted_session:compile() end)
assert(shifted_ok, "unsupported fold domain must remain a typed artifact")
assert(asdl.classof(shifted) == Compiler.CompilerArtifactError)
assert(shifted.message:match("requires a zero%-based unit%-stride loop"),
  "rejection must preserve the narrow fold domain gate")

print("public schema-v2 unsupported fold alternatives are typed compiler artifacts")
