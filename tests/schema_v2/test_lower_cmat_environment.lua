package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_plan")
require("lalin.impl.lower_emit_c")

local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Kernel = require("lalin.schema_v2.kernel")
local Schedule = require("lalin.schema_v2.schedule")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")
local Lower = require("lalin.schema_v2.lower")

local origin = Code.CodeOriginUnknown
local i32 = Code.CodeTyInt(32, Code.CodeSigned)

-----------------------------------------------------------------------
-- Function: entry jumps to the loop-header body, body jumps to exit.
-- One counted loop covers body; one exact loop exit body -> exit.
-----------------------------------------------------------------------
local env_func_id = Code.CodeFuncId("env_func")
local env_sig_id = Code.CodeSigId("env_sig")
local env_entry = Code.CodeBlockId("env_entry")
local env_body = Code.CodeBlockId("env_body")
local env_exit = Code.CodeBlockId("env_exit")
local env_return = Code.CodeTerm(
  Code.CodeTermId("env_return"), Code.CodeTermReturn({}), origin)
local env_func = Code.CodeFunc(
  env_func_id, "env_func", Code.CodeLinkageLocal, env_sig_id, {}, {}, env_entry, {
    Code.CodeBlock(env_entry, "entry", {}, {}, Code.CodeTerm(
      Code.CodeTermId("env_to_body"), Code.CodeTermJump(env_body, {}), origin), origin),
    Code.CodeBlock(env_body, "body", {}, {}, Code.CodeTerm(
      Code.CodeTermId("env_to_exit"), Code.CodeTermJump(env_exit, {}), origin), origin),
    Code.CodeBlock(env_exit, "exit", {}, {}, env_return, origin),
  }, origin)

local env_loop_id = Graph.GraphLoopId("env_loop")
local env_loop = Graph.GraphLoop(
  env_loop_id, env_func_id, Graph.GraphBlockId(env_func_id, env_body),
  { Graph.GraphBlockId(env_func_id, env_body) }, {}, {
    Graph.GraphEdge(
      Graph.GraphBlockId(env_func_id, env_body),
      Graph.GraphBlockId(env_func_id, env_exit), Graph.EdgeKindJump),
  })
local env_loops = Lower.LowerLoopByIdProjection({
  Lower.LowerLoopByIdEntry(env_loop_id, env_loop),
})
local env_coverage = Lower.LowerCoverLoop(env_loop_id)
:lower_c_fragment_coverage(Lower.LowerFragmentCoverageInput(env_func, env_loops))
assert(asdl.classof(env_coverage) == Lower.LowerFragmentCoverageResolved)
assert(env_coverage.coverage.replacement_source == env_body)

local env_graph = Graph.CodeFuncGraph(env_func_id, {
  Graph.GraphEdge(Graph.GraphBlockId(env_func_id, env_entry),
    Graph.GraphBlockId(env_func_id, env_body), Graph.EdgeKindJump),
  Graph.GraphEdge(Graph.GraphBlockId(env_func_id, env_body),
    Graph.GraphBlockId(env_func_id, env_exit), Graph.EdgeKindJump),
}, {}, {}, {})
local env_dominance = Lower.LowerCDominanceConstructionInput(
  env_func, env_graph):lower_c_dominance()
assert(asdl.classof(env_dominance) == Lower.LowerCDominanceReady)

local env_sig = Code.CodeSig(env_sig_id, {}, {})
local env_baseline = env_func:lower_c_function(
  Lower.LowerCFunctionInput(Lower.LowerCSignatureProjection({
    env_sig:lower_c_signature_entry(),
    env_sig:lower_c_signature_entry(),
  }), Lower.LowerCFuncSymbolProjection({})))
local env_adapters = Lower.LowerCReplacementEntryAdapterInput(
  env_func, env_baseline, env_body, env_dominance.dominance)
:lower_c_entry_adapters()
assert(asdl.classof(env_adapters) == Lower.LowerCReplacementEntryAdapterReady)

-----------------------------------------------------------------------
-- Materialization: direct canonical construction of a
-- CMatMaterializedKernelFragment carrying the loop provenance facet.
-----------------------------------------------------------------------
local env_kernel_id = Kernel.KernelId("env_kernel")
local env_schedule_id = Schedule.ScheduleId("env_schedule")
local env_index = Code.CodeValueId("env_index")
local env_start = Code.CodeValueId("env_start")
local env_stop = Code.CodeValueId("env_stop")
local env_step = Code.CodeValueId("env_step")
local env_trip_value = Code.CodeValueId("env_trip")
local env_trip = Flow.FlowTripCountExact(env_trip_value, nil, nil)

local env_planned = Kernel.KernelPlanned(
  env_kernel_id, Kernel.KernelSubjectLoop(env_loop_id),
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(
      Flow.FlowDomainLoop(env_loop_id),
      Kernel.KernelTripKnown(env_trip),
      Kernel.KernelCounterValue(env_index)),
    Kernel.KernelLaneProjection({}),
    Kernel.KernelBindingProjection({}),
    Kernel.KernelEffectProjection({}),
    Kernel.KernelResultVoid,
    Kernel.KernelEquivalenceProof({
      Kernel.KernelProofFunctionEquivalence("fixture"),
    })))
local env_iteration = Stencil.StencilKernelIteration(
  env_loop_id, env_index, i32, env_start, env_stop, env_step, 1,
  Stencil.StencilIterationStopInclusive, Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(env_trip))
local env_source_shape = Flow.FlowDomainShapeFact(
  Flow.FlowDomainLoop(env_loop_id),
  Flow.FlowDomainShapeRange1D(
    i32, Value.ValueExprValue(env_start), Value.ValueExprValue(env_stop),
    1, Flow.FlowDomainForward),
  {}, Flow.FlowFactCheckerDerived)
local env_domain_provenance = Stencil.StencilKernelCountedDomain1D(env_source_shape)
local env_provenance = Stencil.StencilKernelProvenanceFacet(
  env_planned, env_iteration, env_domain_provenance,
  Stencil.StencilAccessByKernelLaneProjection({}),
  Stencil.StencilStreamByKernelValueProjection({}),
  Stencil.StencilKernelResultVoid)

local env_compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local env_schedule = Stencil.StencilScheduleScalar(env_compiler)
local env_producer = Stencil.StencilProducer(
  Stencil.StencilProducerOriginNone,
  Stencil.StencilProduceCountedRange1D(
    i32,
    Stencil.StencilBoundValue(Value.ValueExprValue(env_start)),
    Stencil.StencilBoundValue(Value.ValueExprValue(env_stop)),
    1, Stencil.StencilProducerForward,
    Stencil.StencilIterationStopInclusive,
    Stencil.StencilKernelTripExact(env_trip)))
local env_computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("env_computation"), env_producer,
  {}, {}, {}, Stencil.StencilFusionLegality({}, {}, {}), env_schedule, {})
local env_loop_nest = CMat.CMatLoopNest(
  {}, CMat.CMatSchedulePolicy(1, 1, CMat.CMatVectorNone))
local env_fused = CMat.CMatFusedKernel(
  CMat.CMatKernelId("env_kernel"), env_computation, env_loop_nest,
  {}, {}, {}, env_schedule, {})
local env_materialization = CMat.CMatMaterializedKernelFragment(
  env_fused, env_provenance)

-----------------------------------------------------------------------
-- Fragment, namespace, labels, target.
-----------------------------------------------------------------------
local env_fragment_id = Lower.LowerFragmentId("env_fragment")
local env_cover = Lower.LowerCoverLoop(env_loop_id)
local env_strategy = Lower.LowerStrategyKernel(env_kernel_id, env_schedule_id)
local env_fragment = Lower.LowerFragment(
  env_fragment_id, env_cover, env_strategy, {}, {})
local env_namespace = CMat.CMatCFragmentNamespace("env_ns")
local env_reserved_labels = {
  C.CBackendLabel("env_reserved_1"),
  C.CBackendLabel("env_reserved_2"),
}
local env_target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)

local function environment_input(overrides)
  overrides = overrides or {}
  return Lower.LowerCMatEnvironmentInput(
    overrides.fragment or env_fragment,
    overrides.materialization or env_materialization,
    overrides.coordinates or Lower.LowerCMatCoordinateFacet(
      env_fused:cmat_memory_use_spine(),
      env_materialization.provenance.iteration, {}),
    overrides.coverage or env_coverage.coverage,
    overrides.code_func or env_func,
    overrides.baseline or env_baseline,
    overrides.dominance or env_dominance.dominance,
    overrides.adapters or env_adapters.projection,
    overrides.namespace or env_namespace,
    overrides.reserved_labels or env_reserved_labels,
    overrides.target or env_target)
end

-----------------------------------------------------------------------
-- Success: values/accesses/exits compose into one fragment request.
-----------------------------------------------------------------------
local env_result = environment_input():lower_cmat_environment()
assert(asdl.classof(env_result) == Lower.LowerCMatEnvironmentReady)
local request = env_result.request
assert(request.materialization == env_materialization)
assert(request.code_func == env_func)
assert(request.covered_blocks[1] == env_body)
assert(request.replacement_source == env_body)
assert(request.target == env_target)
assert(request.namespace == env_namespace)
assert(#request.reserved_labels == 2)
assert(request.reserved_labels[1] == env_reserved_labels[1])
assert(request.reserved_labels[2] == env_reserved_labels[2])
assert(#request.values.entries == 0)
assert(#request.accesses.entries == 0)
assert(#request.exits.entries == 1)
assert(request.exits.entries[1].role == CMat.CMatCExitNormal)
assert(request.exits.entries[1].destination == env_exit)

-----------------------------------------------------------------------
-- Rejections
-----------------------------------------------------------------------
-- R1: coverage names a different function than the code func.
local foreign_func = Code.CodeFuncId("foreign_func")
local foreign_coverage = Lower.LowerFragmentCoverage(
  foreign_func, Lower.LowerCoverageLoop(env_loop),
  env_coverage.coverage.covered_blocks, env_coverage.coverage.replacement_source)
local r1 = environment_input({ coverage = foreign_coverage }):lower_cmat_environment()
assert(asdl.classof(r1) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r1.issue) == Lower.LowerIssueValueEnvironmentRejected)

-- R2: materialization provenance kernel disagrees with fragment strategy.
local foreign_kernel = Lower.LowerFragment(
  env_fragment_id, env_cover,
  Lower.LowerStrategyKernel(Kernel.KernelId("foreign_kernel"), env_schedule_id),
  {}, {})
local r2 = environment_input({ fragment = foreign_kernel }):lower_cmat_environment()
assert(asdl.classof(r2) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r2.issue) == Lower.LowerIssueFragmentRejected)

-- R3: a code strategy fragment has no CMat materialization.
local code_fragment = Lower.LowerFragment(
  env_fragment_id, env_cover, Lower.LowerStrategyCode("fixture"), {}, {})
local r3 = environment_input({ fragment = code_fragment }):lower_cmat_environment()
assert(asdl.classof(r3) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r3.issue) == Lower.LowerIssueFragmentRejected)

-- R4: adapters target a different replacement block than the coverage.
local exit_adapters = Lower.LowerCReplacementEntryAdapterInput(
  env_func, env_baseline, env_exit, env_dominance.dominance)
:lower_c_entry_adapters()
assert(asdl.classof(exit_adapters) == Lower.LowerCReplacementEntryAdapterReady)
local r4 = environment_input({ adapters = exit_adapters.projection })
:lower_cmat_environment()
assert(asdl.classof(r4) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r4.issue) == Lower.LowerIssueValueEnvironmentRejected)

-- R5: dominance projection belongs to a different function instance.
local stale_func = Code.CodeFunc(
  env_func.id, "stale", env_func.linkage, env_func.sig, env_func.params,
  env_func.locals, env_func.entry, env_func.blocks, origin)
local stale_dominance = Lower.LowerCDominanceProjection(
  stale_func, env_graph, env_dominance.dominance.entries)
local r5 = environment_input({ dominance = stale_dominance }):lower_cmat_environment()
assert(asdl.classof(r5) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r5.issue) == Lower.LowerIssueValueEnvironmentRejected)

-- R6: dominance entries omit the replacement entry -> values leaf rejects.
local partial_dominance = Lower.LowerCDominanceProjection(
  env_func, env_graph, {
    Lower.LowerCDominatorEntry(env_entry, { env_entry }),
  })
local r6 = environment_input({ dominance = partial_dominance }):lower_cmat_environment()
assert(asdl.classof(r6) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r6.issue) == Lower.LowerIssueDominanceRejected)

-- R7: a loop with two exits rejects at the exits leaf.
local two_exit_loop_id = Graph.GraphLoopId("env_loop_two_exits")
local two_exit_loop = Graph.GraphLoop(
  two_exit_loop_id, env_func_id, Graph.GraphBlockId(env_func_id, env_body),
  { Graph.GraphBlockId(env_func_id, env_body) }, {}, {
    Graph.GraphEdge(
      Graph.GraphBlockId(env_func_id, env_body),
      Graph.GraphBlockId(env_func_id, env_exit), Graph.EdgeKindJump),
    Graph.GraphEdge(
      Graph.GraphBlockId(env_func_id, env_body),
      Graph.GraphBlockId(env_func_id, env_exit), Graph.EdgeKindJump),
  })
local two_exit_coverage = Lower.LowerCoverLoop(two_exit_loop_id)
:lower_c_fragment_coverage(Lower.LowerFragmentCoverageInput(
  env_func, Lower.LowerLoopByIdProjection({
    Lower.LowerLoopByIdEntry(two_exit_loop_id, two_exit_loop),
  })))
assert(asdl.classof(two_exit_coverage) == Lower.LowerFragmentCoverageResolved)
local r7 = environment_input({ coverage = two_exit_coverage.coverage })
:lower_cmat_environment()
assert(asdl.classof(r7) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r7.issue) == Lower.LowerIssueExitShapeRejected)

-- R8: a materialized access without provenance relation rejects at the
-- accesses leaf.
local env_mem_access = Mem.MemAccessId("env_access")
local env_access = Stencil.StencilAccess(
  "env_input", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local env_binding = env_access:cmat_canonical_binding(
  CMat.CMatAccessBindingInput(CMat.CMatLocalId("env_input"),
    Stencil.StencilAccessRestrictMissing(Stencil.StencilAccessRef("other"))))
local orphan_fused = CMat.CMatFusedKernel(
  CMat.CMatKernelId("env_kernel"), env_computation, env_loop_nest,
  { env_binding }, {}, {}, env_schedule, {})
local orphan_materialization = CMat.CMatMaterializedKernelFragment(
  orphan_fused, env_provenance)
local r8 = environment_input({ materialization = orphan_materialization })
:lower_cmat_environment()
assert(asdl.classof(r8) == Lower.LowerCMatEnvironmentRejected)
assert(asdl.classof(r8.issue) == Lower.LowerIssueAccessRejected)

print("schema_v2 LOWER CMat environment glue ok")
