package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema")
require("lalin.impl.compiler_api")

local Compiler = T.LalinCompiler
local source = [=[
fn previous_reject(dst [ptr [i32]], xs [ptr [i32]], n [index]) [void] do
  requires bounds(dst)(n), writeonly(dst), bounds(xs)(n), readonly(xs), disjoint(dst)(xs)
  loop i in window(0 .. n, before = 1, after = 1, boundary = reject) do
    dst[i] = xs[i - 1]
  end
end
]=]

local session = Compiler.CompilerSession(source, "window_reject")
local ok, result = pcall(function() return session:compile() end)
assert(ok, "typed compiler rejection must not escape as a Lua error")
assert(asdl.classof(result) == Compiler.CompilerArtifactError)
assert(result.message:match("LowerCMatCoordinateWindowBoundaryUnsupported"),
  "rejection must preserve the exact LOWER coordinate issue")

print("public schema reject-window lowering is a typed compiler artifact")
