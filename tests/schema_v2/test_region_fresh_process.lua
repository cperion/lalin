package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema_v2")
require("lalin.impl.compiler_api")

local forbidden = {
  "lalin.tree_typecheck",
  "lalin.tree_typecheck_stmt",
  "lalin.tree_typecheck_expr",
  "lalin.tree_typecheck_fact",
  "lalin.tree_typecheck_layout",
  "lalin.tree_typecheck_type",
  "lalin.tree_control_facts",
}
for i = 1, #forbidden do
  assert(package.loaded[forbidden[i]] == nil, "canonical bootstrap loaded old module " .. forbidden[i])
end

print("canonical region fresh-process loading ok")
