package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema_v2")
require("lalin.impl.code_flow")
require("lalin.impl.kernel_plan")
require("lalin.impl.stencil_kernel")

local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Effect = require("lalin.schema_v2.effect")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local Schedule = require("lalin.schema_v2.schedule")
local Backend = require("lalin.schema_v2.backend")

local module_id = Code.CodeModuleId("kernel_canonical")
local func_id = Code.CodeFuncId("fn:kernel_canonical")
local sig_id = Code.CodeSigId("sig:kernel_canonical")
local block_id = Code.CodeBlockId("body")
local loop_id = Graph.GraphLoopId("loop:kernel_canonical")
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_ty = Code.CodeTyDataPtr(i32)
local ptr = Code.CodeValueId("ptr")
local index = Code.CodeValueId("i")
local start = Code.CodeValueId("zero")
local stop = Code.CodeValueId("n")
local step = Code.CodeValueId("one")
local stored = Code.CodeValueId("stored")

local place = Code.CodePlaceDeref(ptr, i32, 4)
local memory_access = Code.CodeMemoryAccess(Code.CodeMemoryWrite, i32, 4, Code.CodeMustNotTrap, false, nil)
local const_inst = Code.CodeInst(
  Code.CodeInstId("const"),
  Code.CodeInstConst(stored, Code.CodeConstLiteral(i32, Core.LitInt("7"))),
  origin)
local start_inst = Code.CodeInst(
  Code.CodeInstId("start"),
  Code.CodeInstConst(start, Code.CodeConstLiteral(i32, Core.LitInt("0"))),
  origin)
local step_inst = Code.CodeInst(
  Code.CodeInstId("step"),
  Code.CodeInstConst(step, Code.CodeConstLiteral(i32, Core.LitInt("1"))),
  origin)
local store_inst = Code.CodeInst(
  Code.CodeInstId("store"),
  Code.CodeInstStore(place, stored, memory_access),
  origin)
local term = Code.CodeTerm(Code.CodeTermId("return"), Code.CodeTermReturn({}), origin)
local block = Code.CodeBlock(
  block_id, "body", {}, { start_inst, step_inst, const_inst, store_inst }, term, origin)
local func = Code.CodeFunc(
  func_id,
  "kernel_canonical",
  Code.CodeLinkageLocal,
  sig_id,
  { Code.CodeParam(ptr, "ptr", ptr_ty, origin) },
  {},
  block_id,
  { block },
  origin)
local module = Code.CodeModule(module_id, { Code.CodeSig(sig_id, { ptr_ty }, {}) }, {}, {}, {}, {}, { func }, origin)

local graph_block = Graph.GraphBlockId(func_id, block_id)
local graph_loop = Graph.GraphLoop(loop_id, func_id, graph_block, { graph_block }, {}, {})
local graph = Graph.CodeGraph(module_id, { Graph.CodeFuncGraph(func_id, {}, {}, {}, { graph_loop }) })

local domain = Flow.FlowDomainLoop(loop_id)
local counted = Flow.FlowCountedDomain(
  start, stop, step, Flow.FlowStopExclusive, Flow.FlowLoopIncreasing)
local induction = Flow.FlowInduction(
  index, i32, counted.start, counted.step, Flow.FlowPrimaryInduction,
  Flow.FlowRangeUnknown(index))
local flow = Flow.FlowFactSet(module_id, { domain }, {}, {
  Flow.FlowLoopFacts(loop_id, domain, counted, { graph_block }, { induction }, {}, {})
}, {}, {}, {}, {}, {}, {})
local trip = Flow.FlowTripCountExact(Code.CodeValueId("trip"), nil, nil)
local zero = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local seven = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("7")))
local reduction = Value.ReductionFact(
  Value.AlgebraFactId("reduction"),
  domain,
  stored,
  Value.ReductionAdd,
  zero,
  seven,
  i32,
  nil,
  nil,
  Value.AlgebraProofFlow(domain, Value.AlgebraFlowCounted(trip)))
local closed = Value.ClosedFormFact(
  Value.AlgebraFactId("closed"),
  reduction,
  seven,
  Value.AlgebraProofComposite({}, "closed form fixture"))
local values = Value.ValueFactSet(module_id, {
  Value.ValueExprFact(stored, seven, Value.AlgebraProofComposite({}, "constant fixture"))
}, { reduction }, { closed })

local access_id = Mem.MemAccessId("access:kernel_canonical:body:store")
local object_id = Mem.MemObjectId("object:ptr")
local object = Mem.MemObjectFact(
  object_id,
  func_id,
  Mem.MemObjectParam,
  Mem.MemProvValue(ptr),
  i32,
  Mem.MemExtentElements(stop, i32, Mem.MemExtentByConstruction),
  Mem.MemStrideUnit)
local access = Mem.MemAccessFact(
  access_id,
  func_id,
  graph_block,
  store_inst.id,
  Mem.MemStore,
  place,
  memory_access,
  Mem.MemBaseValue(ptr),
  Mem.MemIndexValue(index, 4, 0),
  Mem.MemAccessScalar,
  Mem.MemAlignKnown(4),
  Mem.MemBoundsInObject("counted loop access"),
  Mem.MemNonTrapping("counted loop access"))
local proof = Mem.MemProofBackend(access_id, Mem.MemBackendNoTrapOnAligned("counted loop access"))
local backend = Mem.MemBackendAccessInfo(
  access_id,
  Mem.MemNonTrapping("counted loop access"),
  Mem.MemAlignKnown(4),
  Mem.MemBoundsInObject("counted loop access"),
  Mem.MemDerefBytesKnown(4),
  Mem.MemMovementMovable("counted loop access"),
  { proof })
local mem = Mem.MemSemanticFactSet(module_id, { object }, {}, { access }, {}, {}, {}, {}, {}, { backend }, { proof })
local effects = Effect.EffectFactSet(module_id, {}, {
  Effect.InstEffect(store_inst.id, { Effect.EffectWrite(Effect.EffectObjectMem(object_id), Effect.EffectEvidenceMemory(proof)) })
}, {})

local plan = mem:plan_kernels(module, graph, flow, values, effects)
assert(#plan.plans == 1)
local planned = plan.plans[1]
assert(planned.body.domain.counter.value == index)
assert(#planned.body.lanes.entries == 1)
assert(planned.body.lanes.entries[1].lane.object == object_id)
assert(planned.body.lanes.entries[1].lane.accesses[1] == access_id)
assert(#planned.body.bindings.entries == 3)
assert(planned.body.bindings.entries[3].value == stored)
assert(#planned.body.effects.entries == 1)
assert(planned.body.effects.entries[1].inst.inst == store_inst.id)
assert(planned.body.effects.entries[1].effect.dst == planned.body.lanes.entries[1].lane)
assert(planned.body.result.closed_form == closed)
assert(#planned.body.equivalence.proofs >= 3)

local semantics = flow:compute_semantic_flow(module, graph)
local iteration_result = Stencil.StencilKernelIterationInput(
  module, graph, planned, flow, semantics):project_iteration()
local iteration = iteration_result.iteration
assert(iteration.counter == index)
assert(iteration.counter ~= counted.start,
  "projected counter must be the primary induction, not the initial value")
assert(iteration.index_ty == i32)
assert(iteration.start == counted.start and iteration.stop == counted.stop)
assert(iteration.step == step and iteration.step_magnitude == 1)
assert(iteration.stop_convention == Stencil.StencilIterationStopExclusive)
assert(iteration.order == Stencil.StencilProducerForward)

local absent_counter_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:absent-counter"), planned.subject,
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, planned.body.domain.trip, Kernel.KernelCounterAbsent),
    planned.body.lanes, planned.body.bindings, planned.body.effects,
    planned.body.result, planned.body.equivalence))
local absent_counter = Stencil.StencilKernelIterationInput(
  module, graph, absent_counter_kernel, flow, semantics):project_iteration()
assert(absent_counter.reject.kernel == absent_counter_kernel.id)
local stale_counter_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:stale-counter"), planned.subject,
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(
      domain, planned.body.domain.trip, Kernel.KernelCounterValue(start)),
    planned.body.lanes, planned.body.bindings, planned.body.effects,
    planned.body.result, planned.body.equivalence))
local stale_counter = Stencil.StencilKernelIterationInput(
  module, graph, stale_counter_kernel, flow, semantics):project_iteration()
assert(stale_counter.reject.loop == loop_id)

local inclusive_counted = Flow.FlowCountedDomain(
  start, stop, step, Flow.FlowStopInclusive, Flow.FlowLoopIncreasing)
local inclusive_flow = Flow.FlowFactSet(module_id, { domain }, {}, {
  Flow.FlowLoopFacts(
    loop_id, domain, inclusive_counted, { graph_block }, { induction }, {}, {})
}, {}, {}, {}, {}, {}, {})
local inclusive_semantics = inclusive_flow:compute_semantic_flow(module, graph)
local inclusive_iteration = Stencil.StencilKernelIterationInput(
  module, graph, planned, inclusive_flow, inclusive_semantics)
:project_iteration().iteration
assert(inclusive_iteration.stop_convention ==
  Stencil.StencilIterationStopInclusive)
local stale_iteration = Stencil.StencilKernelIterationInput(
  module, graph, planned, inclusive_flow, semantics):project_iteration()
assert(stale_iteration.reject.loop == loop_id)

local store_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:store"), planned.subject,
  Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, planned.body.bindings, planned.body.effects,
    Kernel.KernelResultVoid, planned.body.equivalence))
local scalar_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:store:scalar"), store_kernel.id,
  Schedule.ScheduleScalarIndex, {}, {})
local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO2,
  Stencil.StencilMachineNative, {})
local target = Backend.BackTargetModel(Backend.BackTargetNative, {})
local projected = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, store_kernel, scalar_schedule, compiler, target,
  mem, effects):project_kernel_stencil()
local computation = projected.projection.computation
assert(projected.projection.source_schedule == scalar_schedule)
assert(computation.producer.shape.step == 1)
assert(computation.producer.shape.stop_convention ==
  Stencil.StencilIterationStopExclusive)
assert(#computation.accesses == 1)
assert(computation.accesses[1].layout.base.stride == 4)
assert(computation.accesses[1].role == Stencil.StencilAccessWrite)
assert(#computation.streams == 3)
assert(#computation.sinks == 1)
assert(computation.sinks[1].op.dst.name == computation.accesses[1].name)
assert(computation.schedule.compiler == compiler)

local module_kernels = Kernel.KernelModulePlan(
  module_id, flow, values, mem, effects, { store_kernel })
local module_schedules = Schedule.ScheduleModulePlan(
  module_id, Schedule.ScheduleTarget(target), { scalar_schedule })
local module_projection = Stencil.StencilKernelModuleProjectionInput(
  module, graph, flow, semantics, module_kernels, module_schedules, compiler)
:project_kernel_module().projection
assert(#module_projection.entries == 1)
assert(module_projection.entries[1].kernel == store_kernel.id)
assert(module_projection.entries[1].result.projection.computation.sinks[1].op.dst.name ==
  computation.sinks[1].op.dst.name)
local stale_flow = Flow.FlowFactSet(
  module_id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
local stale_module_projection = Stencil.StencilKernelModuleProjectionInput(
  module, graph, stale_flow, semantics, module_kernels, module_schedules, compiler)
:project_kernel_module()
assert(stale_module_projection.reason:find("different flow", 1, true))

local no_schedule = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, store_kernel,
  Schedule.ScheduleNoPlan(store_kernel.id, {}), compiler, target, mem, effects)
:project_kernel_stencil()
assert(no_schedule.rejects[1].schedule.kernel == store_kernel.id)

local unknown_counted = Flow.FlowCountedDomain(
  start, stop, step, Flow.FlowStopExclusive, Flow.FlowLoopDirectionUnknown)
local unknown_flow = Flow.FlowFactSet(module_id, { domain }, {}, {
  Flow.FlowLoopFacts(
    loop_id, domain, unknown_counted, { graph_block }, { induction }, {}, {})
}, {}, {}, {}, {}, {}, {})
local unknown_semantics = Flow.FlowSemanticFactSet(module_id, {
  Flow.FlowLoopNormalizedCounted(
    loop_id, unknown_counted, Flow.FlowLoopDirectionUnknown, trip),
})
local unknown_direction = Stencil.StencilKernelIterationInput(
  module, graph, store_kernel, unknown_flow, unknown_semantics):project_iteration()
assert(unknown_direction.reject.direction == Flow.FlowLoopDirectionUnknown)

local decreasing_counted = Flow.FlowCountedDomain(
  start, stop, step, Flow.FlowStopExclusive, Flow.FlowLoopDecreasing)
local decreasing_flow = Flow.FlowFactSet(module_id, { domain }, {}, {
  Flow.FlowLoopFacts(
    loop_id, domain, decreasing_counted, { graph_block }, { induction }, {}, {})
}, {}, {}, {}, {}, {}, {})
local decreasing_semantics = Flow.FlowSemanticFactSet(module_id, {
  Flow.FlowLoopNormalizedCounted(
    loop_id, decreasing_counted, Flow.FlowLoopDecreasing, trip),
})
local decreasing_iteration = Stencil.StencilKernelIterationInput(
  module, graph, store_kernel, decreasing_flow, decreasing_semantics)
:project_iteration().iteration
assert(decreasing_iteration.order == Stencil.StencilProducerBackward)
assert(decreasing_iteration.step_magnitude == 1)

local fold_ref = Graph.GraphInstRef(func_id, block_id, const_inst.id)
local fold_effects = Kernel.KernelEffectProjection({
  Kernel.KernelEffectByInstructionEntry(fold_ref, Kernel.KernelEffectFold(reduction)),
})
local reduction_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:reduction"), planned.subject,
  Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, planned.body.bindings,
    fold_effects, Kernel.KernelResultReduction(reduction),
    planned.body.equivalence))
local reduction_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:reduction:scalar"), reduction_kernel.id,
  Schedule.ScheduleScalarIndex, {}, {})
local reduction_projection = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, reduction_kernel, reduction_schedule, compiler, target,
  mem, Effect.EffectFactSet(module_id, {}, {}, {})):project_kernel_stencil()
local reduction_computation = reduction_projection.projection.computation
assert(#reduction_computation.sinks == 1)
assert(reduction_computation.sinks[1].op.reducer.reduction == Value.ReductionAdd)
assert(reduction_computation.sinks[1].op.init == Stencil.StencilReduceInitIdentity)

local other_reduction = Value.ReductionFact(
  Value.AlgebraFactId("reduction:other"), domain, stored, Value.ReductionAdd,
  zero, seven, i32, nil, nil,
  Value.AlgebraProofFlow(domain, Value.AlgebraFlowCounted(trip)))
local mismatch_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:reduction:mismatch"), planned.subject,
  Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, planned.body.bindings,
    Kernel.KernelEffectProjection({
      Kernel.KernelEffectByInstructionEntry(
        fold_ref, Kernel.KernelEffectFold(other_reduction)),
    }),
    Kernel.KernelResultReduction(reduction), planned.body.equivalence))
local mismatch_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:reduction:mismatch"), mismatch_kernel.id,
  Schedule.ScheduleScalarIndex, {}, {})
local mismatch_projection = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, mismatch_kernel, mismatch_schedule, compiler, target,
  mem, Effect.EffectFactSet(module_id, {}, {}, {})):project_kernel_stencil()
assert(mismatch_projection.rejects[1].deferred[1] == other_reduction)
assert(mismatch_projection.rejects[1].result.reduction == reduction)

local missing_graph = Graph.CodeGraph(module_id, {})
local rejected = mem:plan_kernels(module, missing_graph, flow, values, effects).plans[1]
assert(#rejected.rejects == 1)
assert(rejected.subject.loop == loop_id)

local volatile = Effect.EffectVolatile(Effect.EffectEvidenceDeclared("volatile fixture"))
local volatile_effects = Effect.EffectFactSet(module_id, {}, { Effect.InstEffect(const_inst.id, { volatile }) }, {})
local effect_rejected = mem:plan_kernels(module, graph, flow, values, volatile_effects).plans[1]
assert(#effect_rejected.rejects == 1)
assert(effect_rejected.rejects[1].effect == volatile)

print("canonical kernel stencil projection ok")
