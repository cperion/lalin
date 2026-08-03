package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
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
  shifted_source, "v2_fold_shifted_reject")
local shifted_ok, shifted = pcall(function() return shifted_session:compile() end)
assert(shifted_ok, "pending fold traversal must remain a typed artifact")
assert(asdl.classof(shifted) == Compiler.CompilerArtifactError)
assert(shifted.message:match("general parsed fold traversal projection is pending"),
  "rejection must preserve the exact pending traversal gap")

print("public schema-v2 pending fold traversal is a typed compiler artifact")
