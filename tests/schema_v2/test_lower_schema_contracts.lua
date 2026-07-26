package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local Lower = T.LalinLower

local function field_names(cls)
  local result = {}
  for _, field in ipairs(asdl.fields(cls)) do result[#result + 1] = field.name end
  return table.concat(result, ",")
end

assert(field_names(Lower.LowerCModuleInput) ==
  "spine,plan,materializations")
assert(field_names(Lower.LowerFragmentEmissionInput) == "spine,code_func,plan,fragment,signatures,carriers,addresses")
assert(field_names(Lower.LowerCFragment) == "blocks,locals,helpers,block_mappings,value_mappings")
assert(field_names(Lower.LowerModule) == "module,target,kernels,schedules,carriers,addresses,funcs,issues")
assert(Lower.LowerFunctionPlanFound and Lower.LowerFunctionPlanMissing)
assert(Lower.LowerAddressPlanFound and Lower.LowerAddressPlanMissing)
assert(Lower.LowerCarrierLocalResolved and Lower.LowerCarrierLocalRejected)
assert(Lower.LowerAddressPlaceResolved and Lower.LowerAddressPlaceRejected)
assert(Lower.LowerCodeFragmentEmitted)
assert(Lower.LowerClosedFormFragmentEmitted)
assert(Lower.LowerKernelFragmentEmitted)
assert(Lower.LowerFragmentEmissionRejected)
assert(Lower.LowerFunctionEmitted and Lower.LowerFunctionEmissionRejected)
assert(Lower.LowerKernelCMatPrepared and Lower.LowerKernelCMatPreparationRejected)
assert(Lower.LowerFragmentCoverageResolved and Lower.LowerFragmentCoverageRejected)
assert(Lower.LowerCMatEnvironmentReady and Lower.LowerCMatEnvironmentRejected)
assert(Lower.LowerCFunctionAssemblyReady and Lower.LowerCFunctionAssemblyRejected)
assert(Lower.LowerCModuleEmitted and Lower.LowerCModuleRejected)
assert(Lower.LowerBackEmitInput == nil, "obsolete generic lower input must be removed")
assert(Lower.LowerCEmitInput == nil, "obsolete generic C emit input must be removed")

local f = assert(io.open("lua/lalin/schema_v2/lower.lua", "rb"))
local source = f:read("*a")
f:close()
assert(not source:match("optional%s*%["))
assert(not source:match("%[bool%]"))

print("schema_v2 lower contracts ok")
