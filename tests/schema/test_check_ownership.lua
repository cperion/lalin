package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local lalin = require("lalin")

local T = require("lalin.schema_v2")
local Tree = T.LalinTree
local Check = T.LalinCheck

assert(Check and Check.TypeIssue and Check.TypeModuleResult, "canonical context must own checking vocabulary in LalinCheck")
assert(Tree.TypeIssue == nil and Tree.TypeModuleResult == nil, "LalinTree must not expose check-stage aliases")
assert(T.LalinTreeCode and T.LalinTreeCode.TreeCodeInput, "canonical context must own LalinTreeCode")
require("lalin.impl.tree_check.init")

local decls = assert(lalin.loadstring([[
fn identity(x [i32]) [i32] do
  return x
end
]], "@check-ownership.lln"))
local module = lalin.syntax.to_module(decls, "CheckOwnership", T)
local checked = require("lalin.frontend_pipeline")(T).typecheck_module(module, {})
assert(asdl.classof(checked) == Check.TypeModuleResult, "public canonical typecheck result must be LalinCheck-owned")
assert(asdl.classof(checked.module) == Tree.Module, "canonical check result must retain the canonical tree identity")

io.write("lalin check ownership ok\n")
