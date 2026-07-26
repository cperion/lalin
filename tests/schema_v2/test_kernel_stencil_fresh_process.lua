package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema_v2")
require("lalin.impl.compiler_api")

local forbidden = {
  "lalin.code_kernel_plan",
  "lalin.code_schedule_plan",
  "lalin.stencil_artifact_plan",
  "lalin.code_lower_plan",
  "lalin.lower_to_c",
}
for i = 1, #forbidden do
  assert(package.loaded[forbidden[i]] == nil,
    "canonical kernel/stencil bootstrap loaded old module " .. forbidden[i])
end

assert(package.loaded["lalin.impl.stencil_kernel"],
  "canonical compiler bootstrap did not install kernel/stencil methods")

print("canonical kernel stencil fresh-process loading ok")
