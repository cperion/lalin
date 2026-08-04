package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local K = T.LalinKernel

local function field_names(cls)
  local result = {}
  for _, field in ipairs(asdl.fields(cls)) do result[#result + 1] = field.name end
  return table.concat(result, ",")
end

assert(field_names(K.KernelModulePlanRequest) == "module,graph,flow,values,mem,effects,trips")
assert(field_names(K.KernelLoopAnalysisInput) == "module,graph,flow,values,mem,effects,fact,candidate")
assert(field_names(K.KernelLoopPlanRequest) == "fact,candidate,analysis")
assert(field_names(K.KernelLoopPlanBuild) == "domain,trip,counter,lanes,bindings,effects,proofs")
assert(field_names(K.KernelLoopFactEntry) == "loop,domain,count,counter,trip")
assert(field_names(K.KernelBody) == "domain,lanes,bindings,effects,result,equivalence")

assert(K.KernelCounterAbsent and K.KernelCounterValue)
assert(K.KernelCounterSelected and K.KernelCounterMissing and
  K.KernelCounterAmbiguous)
assert(K.KernelLaneProjection and K.KernelLaneFound and K.KernelLaneMissing)
assert(K.KernelBindingProjection and K.KernelBindingFound and K.KernelBindingMissing)
assert(K.KernelEffectProjection and K.KernelEffectFound and K.KernelEffectMissing)
assert(K.KernelLoopAnalysisReady and K.KernelLoopAnalysisRejected)
assert(K.KernelSkeletonScanSelected and K.KernelSkeletonCopySelected)
assert(K.KernelSkeletonAllSelected and K.KernelSkeletonAllCompareSelected and K.KernelSkeletonAnySelected)
assert(K.KernelSkeletonKind == nil, "skeleton selection must use concrete alternatives")

local f = assert(io.open("lua/lalin/schema_v2/kernel.lua", "rb"))
local source = f:read("*a")
f:close()
source = source:gsub("object_fact %[%s*optional %[%s*LalinMem%.MemObjectFact%s*%]%s*%]", "object_fact [factual-absence]")
assert(not source:match("optional%s*%["), "canonical kernel schema must not use optional protocol fields; factual source-object absence is the sole exception")
assert(not source:match("%[bool%]"), "canonical kernel schema must not encode decisions as booleans")

print("schema_v2 kernel contracts ok")
