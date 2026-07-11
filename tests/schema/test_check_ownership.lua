package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local lalin = require("lalin")

local T = asdl.context()
require("lalin.schema_projection")(T)
local Tree = T.LalinTree
local Check = T.LalinCheck

assert(Check and Check.TypeIssue and Check.TypeModuleResult, "canonical context must own checking vocabulary in LalinCheck")
assert(Tree.TypeIssue == nil and Tree.TypeModuleResult == nil, "LalinTree must not expose check-stage aliases")
assert(T.LalinTreeLower and T.LalinTreeLower.TreeLowerInput, "canonical context must own LalinTreeLower")

require("lalin.tree_typecheck")(T)
require("lalin.tree_lower")(T)

local decls = assert(lalin.loadstring([[
fn bad() [i32] do
  return true
end
]], "@check-ownership.lln"))
local module = lalin.syntax.to_module(decls, "CheckOwnership", T)
local checked = module:typecheck_tree_module()
assert(#checked.issues == 1, "focused canonical typecheck must produce one issue")
assert(asdl.classof(checked) == Check.TypeModuleResult, "public canonical typecheck result must be LalinCheck-owned")
assert(asdl.classof(checked.issues[1]) == Check.TypeIssueExpected, "public canonical issue must be LalinCheck-owned")

local V2 = require("lalin.schema_v2")
assert(V2.LalinCheck and V2.LalinCheck.TypeIssue, "schema_v2 must retain its LalinCheck vocabulary")
assert(V2.LalinTree.TypeIssue == nil, "schema_v2 tree must not expose check aliases")
assert(V2.LalinTreeCode and V2.LalinTreeCode.TreeCodeInput, "schema_v2 must own LalinTreeCode")
assert(V2.LalinTreeLower == nil, "schema_v2 must not expose canonical legacy lowering vocabulary")
require("lalin.impl.tree_check.init")
require("lalin.impl.tree_code")

io.write("lalin check ownership ok\n")
