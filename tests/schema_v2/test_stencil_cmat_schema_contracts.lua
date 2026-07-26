package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local Stencil, CMat = T.LalinStencil, T.LalinCMat

local function field_names(cls)
  local result = {}
  for _, field in ipairs(asdl.fields(cls)) do result[#result + 1] = field.name end
  return table.concat(result, ",")
end

local function field_type(cls, name)
  for _, field in ipairs(asdl.fields(cls)) do
    if field.name == name then return tostring(field.type) end
  end
  error("missing field " .. name)
end

assert(field_names(Stencil.StencilKernelProjectionInput) ==
  "module,graph,flow,semantics,kernel,schedule,compiler,target,mem,effects")
assert(field_type(Stencil.StencilKernelProjectionInput, "schedule") ==
  "LalinSchedule.KernelSchedule")
assert(field_type(Stencil.StencilKernelProjectionInput, "flow") ==
  "LalinFlow.FlowFactSet")
assert(field_type(Stencil.StencilKernelProjectionInput, "semantics") ==
  "LalinFlow.FlowSemanticFactSet")
assert(field_names(Stencil.StencilKernelIteration) ==
  "loop,counter,index_ty,start,stop,step,step_magnitude,stop_convention,order,trip")
assert(field_names(Stencil.StencilKernelIterationInput) ==
  "module,graph,kernel,flow,semantics")
assert(field_names(Stencil.StencilKernelScheduleConversionInput) ==
  "schedule,compiler,target,accesses,result")
assert(field_names(Stencil.StencilKernelConstructionState) ==
  "kernel,iteration,producer,access_by_lane,stream_by_value,sinks,legality,proofs,next_stream_ordinal")
assert(Stencil.StencilKernelLoopFactFound and Stencil.StencilKernelLoopFactMissing and
  Stencil.StencilKernelLoopFactAmbiguous)
assert(Stencil.StencilKernelSemanticIterationFound and
  Stencil.StencilKernelSemanticIterationMissing and
  Stencil.StencilKernelSemanticIterationAmbiguous)
assert(Stencil.StencilKernelInductionFound and Stencil.StencilKernelInductionMissing and
  Stencil.StencilKernelInductionAmbiguous)
assert(Stencil.StencilKernelStepDefinitionMissing and
  Stencil.StencilKernelStepDefinitionFound and
  Stencil.StencilKernelStepDefinitionAmbiguous)
assert(Stencil.StencilKernelIterationProjected and Stencil.StencilKernelIterationRejected)
assert(Stencil.StencilKernelScheduleConverted and Stencil.StencilKernelScheduleRejected)
assert(Stencil.StencilKernelConstructionCollecting and
  Stencil.StencilKernelConstructionFinalizable and
  Stencil.StencilKernelConstructionRejected)
assert(field_names(Stencil.StencilKernelFinalizationInput) == "schedule")
assert(field_names(Stencil.StencilKernelComputationProjection) ==
  "source_schedule,computation")
assert(Stencil.StencilKernelProjected and Stencil.StencilKernelProjectionRejected)
assert(Stencil.StencilBoundDynamic and Stencil.StencilBoundValue)
assert(Stencil.StencilArithmeticInferred and Stencil.StencilArithmeticInteger and Stencil.StencilArithmeticFloat)
assert(Stencil.StencilReadonlyFact and Stencil.StencilUnitStrideFact)
assert(Stencil.StencilScheduleCandidateNoPlan and Stencil.StencilScheduleCandidatePlanned)

assert(field_names(CMat.CMatCFragmentInput) == "materialization,code_func,covered_blocks,target,carriers,addresses")
assert(field_names(CMat.CMatCFragment) == "blocks,locals,helpers,block_mappings,value_mappings,control")
assert(CMat.CMatCFragmentEmitted and CMat.CMatCFragmentRejected)
assert(CMat.CMatCCarrierBindingFound and CMat.CMatCCarrierBindingMissing)
assert(CMat.CMatCAddressBindingFound and CMat.CMatCAddressBindingMissing)
assert(CMat.CMatWindowIndexInBounds and CMat.CMatWindowIndexClamped)
assert(CMat.CMatWindowIndexWrapped and CMat.CMatWindowIndexZero and CMat.CMatWindowIndexRejected)

local function source(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end
for _, path in ipairs {
  "lua/lalin/schema_v2/stencil.lua",
  "lua/lalin/schema_v2/c_materialize.lua",
} do
  local text = source(path)
  assert(not text:match("optional%s*%["), path .. " must not contain optional protocol soup")
  assert(not text:match("%[bool%]"), path .. " must not contain semantic booleans")
  assert(not text:match("LalinLuaJIT"), path .. " must remain backend-neutral")
end

print("schema_v2 stencil/CMat contracts ok")
