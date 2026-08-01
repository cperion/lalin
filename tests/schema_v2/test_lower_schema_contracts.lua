package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local Lower = T.LalinLower
local Flow = T.LalinFlow

local function field_names(cls)
  local result = {}
  for _, field in ipairs(asdl.fields(cls)) do result[#result + 1] = field.name end
  return table.concat(result, ",")
end

assert(field_names(Lower.LowerCModuleInput) ==
  "spine,plan,materializations")
assert(not Flow.FlowCarrierId and not Flow.FlowAddressId)
assert(not Lower.LowerCarrierPlan and not Lower.LowerAddressPlan)
assert(field_names(Lower.LowerCTermEdgeOrigin) == "source,term")
assert(field_names(Lower.LowerCIncomingEdgeArguments) ==
  "origin,occurrence,destination,args")
assert(field_names(Lower.LowerCIncomingEdgeProjection) == "entries")
assert(field_names(Lower.LowerCIncomingBlockArgument) ==
  "edge,ordinal,value,definition,evidence")
assert(field_names(Lower.LowerCIncomingArgumentInput) ==
  "func,replacement,edge,ordinal,value,definition,dominance")
assert(Lower.LowerCTermEdgeOnly and Lower.LowerCTermEdgeThen and
  Lower.LowerCTermEdgeElse and Lower.LowerCTermEdgeCase and
  Lower.LowerCTermEdgeDefault)
assert(field_names(Lower.LowerCFragmentAssemblyInput) ==
  "fragment,coverage,code_func,baseline,materializations,dominance,adapters,namespace,reserved_labels,target")
assert(field_names(Lower.LowerCFunctionAssembly) ==
  "code_func,baseline,fragments,blocks,locals,helpers")
assert(field_names(Lower.LowerCFunctionAssemblyInput) ==
  "spine,code_func,plan,baseline,materializations")
assert(Lower.LowerCCodeFragment and Lower.LowerCKernelCMatFragment and
  Lower.LowerCRejectedFragment)
assert(Lower.LowerCFragment == nil, "lossy C fragment protocol must stay removed")
assert(Lower.LowerFragmentEmission == nil, "old fragment emission protocol must stay removed")
assert(Lower.LowerEmitSelection == nil, "stale schedule-form dispatch must stay removed")
assert(Lower.LowerKernelCMatPrepared and Lower.LowerKernelCMatPreparationRejected)
assert(Lower.LowerFragmentCoverageResolved and Lower.LowerFragmentCoverageRejected)
assert(Lower.LowerCMatEnvironmentReady and Lower.LowerCMatEnvironmentRejected)
assert(Lower.LowerCFunctionAssemblyReady and Lower.LowerCFunctionAssemblyRejected)
assert(Lower.LowerCModuleEmitted and Lower.LowerCModuleRejected)
assert(field_names(Lower.LowerCMatCoordinateInput) ==
  "iteration,domain,provenance,memory")
assert(field_names(Lower.LowerCMatWindowCoordinateProvenance) ==
  "offset,extent,boundary")
assert(field_names(Lower.LowerCMatWindowRelativeCoordinate) ==
  "basis,provenance,use_offset_bytes")
assert(field_names(Lower.LowerCMatWindowDynamicCoordinate) ==
  "basis,provenance,const_offset_bytes")
assert(Lower.LowerCMatCoordinateWindowBoundaryUnsupported)
assert(field_names(Lower.LowerCMatAccessFact) ==
  "binding,provenance,mem_access,alignment,bounds,trap,movement,elem_size,stride")
assert(Lower.LowerCMatAccessContractAdmitted and
  Lower.LowerCMatAccessContractRejected)
assert(Lower.LowerCMatCoordinateWindowDistanceOutsideExtent)
assert(Lower.LowerBackEmitInput == nil, "obsolete generic lower input must be removed")
assert(Lower.LowerCEmitInput == nil, "obsolete generic C emit input must be removed")

local f = assert(io.open("lua/lalin/schema_v2/lower.lua", "rb"))
local source = f:read("*a")
f:close()
assert(not source:match("optional%s*%["))
assert(not source:match("%[bool%]"))

print("schema_v2 lower contracts ok")
