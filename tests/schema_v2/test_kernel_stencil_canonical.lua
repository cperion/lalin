package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.code_flow")
require("lalin.impl.kernel_plan")
require("lalin.impl.stencil_kernel")
require("lalin.impl.lower_emit_c.materialize")
require("lalin.impl.lower_emit_c.stencil")
require("lalin.impl.lower_emit_c.fragment")
require("lalin.impl.lower_emit_c.lower_sem")

local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Effect = require("lalin.schema_v2.effect")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local Lower = require("lalin.schema_v2.lower")
local Schedule = require("lalin.schema_v2.schedule")
local Backend = require("lalin.schema_v2.backend")
local C = require("lalin.schema_v2.c")

local module_id = Code.CodeModuleId("kernel_canonical")
local func_id = Code.CodeFuncId("fn:kernel_canonical")
local sig_id = Code.CodeSigId("sig:kernel_canonical")
local block_id = Code.CodeBlockId("body")
local loop_id = Graph.GraphLoopId("loop:kernel_canonical")
local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local exact_int = Code.CodeIntSemantics(
  Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
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
}, {}, {
  Flow.FlowDomainShapeFact(domain, Flow.FlowDomainShapeRange1D(
    i32, Value.ValueExprValue(start), Value.ValueExprValue(stop),
    1, Flow.FlowDomainForward), {}, Flow.FlowFactCheckerDerived),
}, {}, {}, {}, {})
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
  exact_int,
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
  Mem.MemIndexInduction(induction, 4, 0),
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
local explicit_store_index = seven:stencil_index_selection(
  Stencil.StencilKernelIndexSelectionInput(iteration, seven))
assert(asdl.classof(explicit_store_index) == Stencil.StencilIndexExplicit)
assert(asdl.classof(explicit_store_index.index) == Stencil.StencilIndexPoint)
assert(explicit_store_index.index.expr == seven)

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
  Stencil.StencilCompilerGcc, Stencil.StencilOptO2, {})
local target = Backend.BackTargetModel(Backend.BackTargetNative, {})
local projected = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, store_kernel, scalar_schedule, compiler, target,
  mem, effects):project_kernel_stencil()
local computation = projected.projection.computation
assert(projected.projection.source_schedule == scalar_schedule)
assert(projected.projection.provenance.kernel == store_kernel)
assert(projected.projection.provenance.iteration.counter == index)
assert(projected.projection.provenance.accesses.entries[1].lane ==
  store_kernel.body.lanes.entries[1].lane)
assert(projected.projection.provenance.streams.entries[3].source == stored)
local canonical_materialization = projected.projection:cmat_materialize_kernel(
  CMat.CMatKernelMaterializationInput(CMat.CMatKernelId("kernel:store")))
assert(canonical_materialization.provenance == projected.projection.provenance)
assert(canonical_materialization.kernel.computation == computation)
local cmat_state = projected:lower_cmat_state(
  Lower.LowerKernelCMatStateInput(store_kernel.id, mem:project_accesses()))
assert(asdl.classof(cmat_state) == Lower.LowerKernelCMatReady)
assert(asdl.classof(cmat_state.coordinates) ==
  Lower.LowerCMatCoordinatesProjected)
assert(#cmat_state.coordinates.facet.entries == 1)
assert(asdl.classof(cmat_state.coordinates.facet.entries[1].coordinate) ==
  Lower.LowerCMatIterationAffineCoordinate)
assert(computation.producer.shape.step == 1)
assert(computation.producer.shape.stop_convention ==
  Stencil.StencilIterationStopExclusive)
assert(#computation.accesses == 1)
assert(computation.accesses[1].layout.base.stride == 4)
assert(computation.accesses[1].role == Stencil.StencilAccessWrite)
assert(#computation.streams == 3)
assert(#computation.sinks == 1)
assert(computation.sinks[1].op.dst.name == computation.accesses[1].name)
assert(computation.sinks[1].op.index == Stencil.StencilIndexProducer)
assert(computation.schedule.compiler == compiler)

local store_effect_entry = store_kernel.body.effects.entries[1]
local explicit_store_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:store:explicit"), store_kernel.subject, Kernel.KernelBody(
    store_kernel.body.domain, store_kernel.body.lanes, store_kernel.body.bindings,
    Kernel.KernelEffectProjection({
      Kernel.KernelEffectByInstructionEntry(
        store_effect_entry.inst, Kernel.KernelEffectStore(
          store_effect_entry.effect.dst, seven, store_effect_entry.effect.value)),
    }), Kernel.KernelResultVoid, store_kernel.body.equivalence))
local explicit_store_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:store:explicit"), explicit_store_kernel.id,
  Schedule.ScheduleScalarIndex, {}, {})
local explicit_store_projected = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, explicit_store_kernel, explicit_store_schedule,
  compiler, target, mem, effects):project_kernel_stencil()
assert(asdl.classof(explicit_store_projected) ==
  Stencil.StencilKernelProjected)
local explicit_sink_index =
  explicit_store_projected.projection.computation.sinks[1].op.index
assert(asdl.classof(explicit_sink_index) == Stencil.StencilIndexExplicit)
assert(asdl.classof(explicit_sink_index.index) == Stencil.StencilIndexPoint)
assert(explicit_sink_index.index.expr == seven)

local control_success = Code.CodeBlockId("control_success")
local control_failure = Code.CodeBlockId("control_failure")
local control_result = Kernel.KernelResultAll(
  Kernel.KernelExprValue(stored), stored, Stencil.StencilPredNonZero,
  control_success, control_failure)
local control_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:control-all"), planned.subject, Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, planned.body.bindings,
    Kernel.KernelEffectProjection({}), control_result, planned.body.equivalence))
local control_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:control-all:scalar"), control_kernel.id,
  Schedule.ScheduleScalarIndex, {}, {})
local control_projected = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, control_kernel, control_schedule, compiler, target,
  mem, effects):project_kernel_stencil()
assert(asdl.classof(control_projected) == Stencil.StencilKernelProjected)
local control_projection = control_projected.projection
local control_provenance = control_projection.provenance.result
assert(asdl.classof(control_provenance) == Stencil.StencilKernelResultAll)
assert(control_provenance.src_value == stored)
assert(control_provenance.pred == Stencil.StencilPredNonZero)
assert(control_provenance.success == control_success)
assert(control_provenance.failure == control_failure)
local control_stream = control_projection.provenance.streams.entries[4]
assert(control_stream.source == stored)
assert(control_stream.binding == planned.body.bindings.entries[3].binding)
assert(control_stream.definition == control_projection.computation.streams[4])
assert(control_projection.computation.sinks[1] ==
  Stencil.StencilSinkDef(control_provenance.sink,
    Stencil.StencilSinkOpAll(control_provenance.src, control_provenance.pred)))

local find_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:find"), planned.subject, Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, planned.body.bindings,
    Kernel.KernelEffectProjection({}), Kernel.KernelResultFind(
      Kernel.KernelExprValue(stored), stored, Stencil.StencilPredNonZero, index,
      control_success, control_failure, zero), planned.body.equivalence))
local find_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:find"), find_kernel.id,
  Schedule.ScheduleScalarIndex, {}, {})
local find_projected = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, find_kernel, find_schedule,
  compiler, target, mem, effects):project_kernel_stencil()
assert(asdl.classof(find_projected) == Stencil.StencilKernelProjected)
assert(find_projected.projection.provenance.result.src_value == stored)
assert(find_projected.projection.provenance.result.found_value == index)

local mismatched_find = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:find-mismatch"), planned.subject, Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, planned.body.bindings,
    Kernel.KernelEffectProjection({}), Kernel.KernelResultFind(
      Kernel.KernelExprValue(stored), stored, Stencil.StencilPredNonZero, stored,
      control_success, control_failure, zero), planned.body.equivalence))
local mismatched_find_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:find-mismatch"), mismatched_find.id,
  Schedule.ScheduleScalarIndex, {}, {})
local find_rejected = Stencil.StencilKernelProjectionInput(
  module, graph, flow, semantics, mismatched_find, mismatched_find_schedule,
  compiler, target, mem, effects):project_kernel_stencil()
assert(asdl.classof(find_rejected) == Stencil.StencilKernelProjectionRejected)
assert(asdl.classof(find_rejected.rejects[1]) ==
  Stencil.StencilKernelFindValueMismatch)

local window_source = Code.CodeValueId("window_source")
local window_index = Value.ValueExprSub(
  Value.ValueExprValue(index),
  Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("1"))),
  i32, exact_int)
local window_shape = Flow.FlowDomainShapeWindowND({
  Flow.FlowDomainAxis(
    i32, Value.ValueExprValue(start), Value.ValueExprValue(stop),
    1, Flow.FlowDomainForward, nil),
}, { Flow.FlowWindowAxis(1, 1, Flow.FlowWindowBoundaryZero) })
local window_flow = Flow.FlowFactSet(module_id, { domain }, {}, {
  Flow.FlowLoopFacts(loop_id, domain, counted, { graph_block }, { induction }, {}, {})
}, {}, {
  Flow.FlowDomainShapeFact(domain, window_shape, {}, Flow.FlowFactCheckerDerived),
}, {}, {}, {}, {})
local window_semantics = window_flow:compute_semantic_flow(module, graph)
local window_result = Kernel.KernelResultAll(
  Kernel.KernelExprLaneLoad(planned.body.lanes.entries[1].lane, window_index),
  window_source, Stencil.StencilPredNonZero, control_success, control_failure)
local window_kernel = Kernel.KernelPlanned(
  Kernel.KernelId("kernel:control-window"), planned.subject, Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, planned.body.bindings,
    Kernel.KernelEffectProjection({}), window_result, planned.body.equivalence))
local window_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("schedule:control-window:scalar"), window_kernel.id,
  Schedule.ScheduleScalarIndex, {}, {})
local window_projected = Stencil.StencilKernelProjectionInput(
  module, graph, window_flow, window_semantics, window_kernel, window_schedule,
  compiler, target, mem, effects):project_kernel_stencil()
assert(asdl.classof(window_projected) == Stencil.StencilKernelProjected)
local window_projection = window_projected.projection
assert(asdl.classof(window_projection.provenance.domain) ==
  Stencil.StencilKernelCountedWindow1D)
assert(window_projection.provenance.domain.window.before == 1)
assert(window_projection.provenance.domain.window.after == 1)
assert(asdl.classof(window_projection.computation.producer.shape) ==
  Stencil.StencilProduceCountedWindow1D)
local window_streams = {}
for i = 1, #window_projection.provenance.streams.entries do
  local entry = window_projection.provenance.streams.entries[i]
  if entry.source == window_source then
    window_streams[#window_streams + 1] = entry
  end
end
assert(#window_streams == 1)
local window_stream = window_streams[1]
assert(asdl.classof(window_stream.definition.op) ==
  Stencil.StencilStreamWindowAccess)
assert(window_stream.definition.op.offsets[1].offset == -1)
local c_i32 = C.CBackendScalar(Core.ScalarI32)
local c_ptr = C.CBackendDataPtr(c_i32)
local base_local = C.CBackendLocal(
  C.CBackendLocalId("ptr"), C.CBackendName("ptr"), c_ptr)
local external_values = CMat.CMatCExternalValueBindingProjection({
  CMat.CMatCExternalValueBindingEntry(
    stop, C.CBackendLocal(C.CBackendLocalId("n"), C.CBackendName("n"), c_i32)),
  CMat.CMatCExternalValueBindingEntry(
    trip.count, C.CBackendLocal(
      C.CBackendLocalId("trip"), C.CBackendName("trip"), c_i32)),
  CMat.CMatCExternalValueBindingEntry(
    start, C.CBackendLocal(
      C.CBackendLocalId("start"), C.CBackendName("start"), c_i32)),
})
local fragment_accesses = CMat.CMatCFragmentAccessBindingProjection({
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef(computation.accesses[1].name),
    store_kernel.body.lanes.entries[1].lane.id, access_id,
    CMat.CMatCFragmentAccessDirect(base_local), 4, 4, Mem.MemAlignKnown(4)),
})
local fragment_namespace = CMat.CMatCFragmentNamespace("kernel_store")
local fragment_address_plan = cmat_state.coordinates.facet
:materialize_c_address_plan(CMat.CMatCAddressPlanInput(
  cmat_state.materialization.provenance.iteration, fragment_accesses,
  fragment_namespace)).plan
local fragment_exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, Code.CodeBlockId("exit"),
    C.CBackendLabel("exit"), {}),
})
local exit_block_id = Code.CodeBlockId("exit")
local exit_block = Code.CodeBlock(
  exit_block_id, "exit", {}, {},
  Code.CodeTerm(Code.CodeTermId("exit:return"), Code.CodeTermReturn({}), origin),
  origin)
local fragment_func = Code.CodeFunc(
  func.id, func.name, func.linkage, func.sig, func.params, func.locals,
  func.entry, { block, exit_block }, func.origin)
local fragment_input = CMat.CMatCFragmentInput(
  canonical_materialization, fragment_func, { block_id }, block_id,
  C.CBackendTarget(
    C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian),
  external_values, fragment_accesses, fragment_address_plan, fragment_exits,
  fragment_namespace, {})
assert(fragment_input.materialization == canonical_materialization)
assert(fragment_input.accesses.entries[1].mem_access == access_id)
assert(fragment_input.accesses.entries[1].source.base == base_local)
local alias = Stencil.StencilStreamAlias(
  Stencil.StencilStreamRef(computation.streams[1].id))
assert(alias.source.stream == computation.streams[1].id)
local fragment_emission = fragment_input:emit_cmat_fragment()
assert(#fragment_emission.fragment.blocks == 5)
assert(fragment_emission.fragment.entry.text == "kernel_store_entry")
assert(#fragment_emission.fragment.block_alignments == 1)
assert(fragment_emission.fragment.block_alignments[1].source == block_id)
assert(fragment_emission.fragment.control == CMat.CMatCControlNone)
assert(asdl.classof(Core.BinRem:cmat_fragment_float_spec(
  C.CBackendScalar(Core.ScalarF32))) == CMat.CMatCBinaryRejected)
assert(asdl.classof(
  Stencil.StencilArithmeticFloat(Code.CodeFloatStrict)
:cmat_fragment_reduction_spec(CMat.CMatCFragmentReductionSpecInput(
  Value.ReductionMin, Code.CodeTyFloat(32)))) ==
  CMat.CMatCBinaryRejected)
local empty_cover = CMat.CMatCFragmentInput(
  canonical_materialization, fragment_func, {}, block_id, fragment_input.target,
  external_values, fragment_accesses, fragment_address_plan, fragment_exits,
  CMat.CMatCFragmentNamespace("empty_cover"), {}):emit_cmat_fragment()
assert(asdl.classof(empty_cover) == CMat.CMatCFragmentRejected)
assert(empty_cover.issues[1].block == block_id)
local bad_exit = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, Code.CodeBlockId("missing_exit"),
    C.CBackendLabel("missing_exit"), {}),
})
local invalid_exit = CMat.CMatCFragmentInput(
  canonical_materialization, fragment_func, { block_id }, block_id,
  fragment_input.target, external_values, fragment_accesses,
  fragment_address_plan, bad_exit,
  CMat.CMatCFragmentNamespace("bad_exit"), {}):emit_cmat_fragment()
assert(asdl.classof(invalid_exit) == CMat.CMatCFragmentRejected)
local ambiguous_exits = CMat.CMatCExitBindingProjection({
  fragment_exits.entries[1], fragment_exits.entries[1],
})
local ambiguous_exit = CMat.CMatCFragmentInput(
  canonical_materialization, fragment_func, { block_id }, block_id,
  fragment_input.target, external_values, fragment_accesses,
  fragment_address_plan, ambiguous_exits,
  CMat.CMatCFragmentNamespace("ambiguous_exit"), {}):emit_cmat_fragment()
assert(asdl.classof(ambiguous_exit) == CMat.CMatCFragmentRejected)
local typed_exit_block = Code.CodeBlock(
  exit_block_id, "typed_exit", {
    Code.CodeParam(Code.CodeValueId("typed_exit_arg"), "arg",
      i32, origin),
  }, {}, exit_block.term, origin)
local typed_exit_func = Code.CodeFunc(
  func.id, func.name, func.linkage, func.sig, func.params, func.locals,
  func.entry, { block, typed_exit_block }, func.origin)
local c_i64 = C.CBackendScalar(Core.ScalarI64)
local mismatched_exit_projection = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, exit_block_id, C.CBackendLabel("typed_exit"), {
      CMat.CMatCExitArgumentAtom(
        C.CBackendAtomLiteral(c_i32, Core.LitInt("7")), c_i64),
    }),
})
local mismatched_exit = CMat.CMatCFragmentInput(
  canonical_materialization, typed_exit_func, { block_id }, block_id,
  fragment_input.target, external_values, fragment_accesses,
  fragment_address_plan, mismatched_exit_projection,
  CMat.CMatCFragmentNamespace("typed_exit"), {}):emit_cmat_fragment()
assert(asdl.classof(mismatched_exit) == CMat.CMatCFragmentRejected)
local wrong_trip_values = CMat.CMatCExternalValueBindingProjection({
  external_values.entries[1],
  CMat.CMatCExternalValueBindingEntry(
    trip.count, C.CBackendLocal(
      C.CBackendLocalId("trip64"), C.CBackendName("trip64"), c_i64)),
  external_values.entries[3],
})
local wrong_trip = CMat.CMatCFragmentInput(
  canonical_materialization, fragment_func, { block_id }, block_id,
  fragment_input.target, wrong_trip_values, fragment_accesses,
  fragment_address_plan, fragment_exits,
  CMat.CMatCFragmentNamespace("wrong_trip"), {}):emit_cmat_fragment()
assert(asdl.classof(wrong_trip) == CMat.CMatCFragmentRejected)
assert(wrong_trip.issues[1].subject == "counted trip")

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
assert(reduction_computation.sinks[1].op.reducer.arithmetic ==
  Stencil.StencilArithmeticInteger(exact_int))

local other_reduction = Value.ReductionFact(
  Value.AlgebraFactId("reduction:other"), domain, stored, Value.ReductionAdd,
  zero, seven, i32, exact_int, nil,
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
