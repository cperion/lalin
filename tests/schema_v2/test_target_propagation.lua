package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local T = require("lalin.schema_v2")
local Code, C, Compiler, Lower = T.LalinCode, T.LalinC, T.LalinCompiler, T.LalinLower
local Core = T.LalinCore
local Graph = T.LalinGraph
local Flow = T.LalinFlow
local Value = T.LalinValue
local Mem = T.LalinMem
local Effect = T.LalinEffect
local Kernel = T.LalinKernel
local Schedule = T.LalinSchedule
local Stencil = T.LalinStencil
local Backend = T.LalinBackend

require("lalin.impl.lower_emit_c")

local module_id = Code.CodeModuleId("target_identity")
local module = Code.CodeModule(module_id, {}, {}, {}, {}, {}, {}, Code.CodeOriginUnknown)
local target = C.CBackendTarget(C.CBackendC11, C.CBackendHostedNative, 32, 16, C.CBackendBigEndian)
local graph = Graph.CodeGraph(module_id, {})
local spine = Lower.LowerBackSpine(module, graph, target)
assert(spine.target == target, "LowerBackSpine must preserve the selected target")

local flow = Flow.FlowFactSet(module_id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
local values = Value.ValueFactSet(module_id, {}, {}, {})
local memory = Mem.MemSemanticFactSet(module_id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
local effects = Effect.EffectFactSet(module_id, {}, {}, {})
local kernels = Kernel.KernelModulePlan(module_id, flow, values, memory, effects, {})
local back_target = Backend.BackTargetModel(Backend.BackTargetNative, {})
local schedules = Schedule.ScheduleModulePlan(module_id, Schedule.ScheduleTarget(back_target), {})
local plan = Lower.LowerModule(module_id, Lower.LowerTargetC, kernels, schedules,
  Lower.LowerCarrierPlanProjection({}), Lower.LowerAddressPlanProjection({}),
  Lower.LowerFunctionPlanProjection({}), {})
local input = Lower.LowerCModuleInput(
  spine, plan, Lower.LowerKernelCMatProjection({}))
assert(input.spine.target == target, "LowerCModuleInput must retain spine target")

local module_result = plan:lower_c_module(input)
local emission = module_result.emission
assert(asdl.classof(emission.unit) == C.CBackendUnit)
assert(emission.unit.target == target, "CBackendUnit must retain exact target identity")
local prepared_input = Lower.LowerCPreparedModuleInput(spine, plan)
local rejected_preparation = Lower.LowerKernelCMatPreparationRejected(
  module_id, Code.CodeModuleId("other"))
:lower_c_prepared_module(prepared_input)
assert(asdl.classof(rejected_preparation) == Lower.LowerCModuleRejected)
assert(asdl.classof(rejected_preparation.issues[1]) ==
  Lower.LowerIssuePreparationModuleMismatch)
local rejected_facet = Lower.LowerKernelCMatPreparationFacetRejected(
  "facet mismatch"):lower_c_prepared_module(prepared_input)
assert(asdl.classof(rejected_facet) == Lower.LowerCModuleRejected)
assert(asdl.classof(rejected_facet.issues[1]) ==
  Lower.LowerIssuePreparationFacetRejected)

local request = Compiler.CompilerCCodegenRequest(
  Compiler.CodeResult(module, Code.CodeContractFactSet(module_id, {}), T.LalinSem.LayoutEnv({})),
  target, Stencil.StencilCompilerPolicy(
    Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {}))
assert(request.target == target, "CompilerCCodegenRequest must retain exact target identity")

local function atomic_report(dialect)
  local atomic_target = C.CBackendTarget(dialect, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)
  local access = C.CBackendMemoryAccess(C.CBackendScalar(Core.ScalarI32), 4, C.CBackendMayTrap, false, nil)
  local helper = C.CBackendHelperUse(C.CBackendHelperId("atomic"), C.CBackendHelperAtomicLoad(access))
  local unit = C.CBackendUnit("atomic", atomic_target, {}, {}, {}, {}, { helper }, {})
  return require("lalin.impl.lower_emit_c.validate").validate(unit)
end

assert(#atomic_report(C.CBackendC11).issues == 0, "C11 atomic capability must validate")
local rejected = atomic_report(C.CBackendC99)
assert(#rejected.issues == 1)
assert(asdl.classof(rejected.issues[1]) == C.CBackendIssueInvalidTargetFeature)
assert(rejected.issues[1].feature == C.CBackendFeatureC11Atomics)

print("schema_v2 target propagation ok")
