package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Focused assembly test for the immutable CMat-preserving function
-- assembly protocol (lalin.impl.lower_emit_c.assembly).
--
-- Fixtures are minimal hand-built values (no kernel-planning pipeline):
-- a store-only counted kernel materialization plus a three-block function
-- whose loop body is exactly covered. Coverage: baseline-only, one
-- zero-argument loop replacement, one parameterized replacement entry
-- (entry parameters injected, predecessor argument atoms preserved), and a
-- typed rejection for a kernel with no materialization.

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")
require("lalin.impl.lower_emit_c.assembly")

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
local Schedule = require("lalin.schema_v2.schedule")
local Backend = require("lalin.schema_v2.backend")
local C = require("lalin.schema_v2.c")
local Lower = require("lalin.schema_v2.lower")

----------------------------------------------------------------------
-- Shared ids and simple fixture values
----------------------------------------------------------------------

local origin = Code.CodeOriginUnknown
local func_id = Code.CodeFuncId("asm_func")
local sig_id = Code.CodeSigId("asm_sig")
local entry_id = Code.CodeBlockId("entry")
local body_id = Code.CodeBlockId("body")
local exit_id = Code.CodeBlockId("exit")
local loop_id = Graph.GraphLoopId("asm_loop")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_ty = Code.CodeTyDataPtr(i32)

local trip = Code.CodeValueId("trip")            -- function param i32
local start = Code.CodeValueId("start")          -- function param i32
local base = Code.CodeValueId("base")            -- function param ptr
local body_base = Code.CodeValueId("body_base")  -- body block parameter (ptr)
local index = Code.CodeValueId("index")          -- kernel counter
local stored = Code.CodeValueId("stored")        -- const-stream source key
local stop = Code.CodeValueId("stop")
local step = Code.CodeValueId("step")

local target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)

----------------------------------------------------------------------
-- Minimal store-only counted kernel materialization
----------------------------------------------------------------------

local trip_count = Flow.FlowTripCountExact(trip, nil, nil)
local iteration = Stencil.StencilKernelIteration(
  loop_id, index, i32, start, stop, step, 1,
  Stencil.StencilIterationStopInclusive, Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(trip_count))
local producer = Stencil.StencilProducer(
  Stencil.StencilProducerOriginNone,
  Stencil.StencilProduceCountedRange1D(
    i32, Stencil.StencilBoundValue(Value.ValueExprValue(start)),
    Stencil.StencilBoundValue(Value.ValueExprValue(stop)), 1,
    Stencil.StencilProducerForward, Stencil.StencilIterationStopInclusive,
    Stencil.StencilKernelTripExact(trip_count)))

local access_id = Mem.MemAccessId("asm_access")
local lane_id = Kernel.KernelLaneId("asm_lane")
local stream_id = Stencil.StencilStreamId("asm_stream")
local sink_id = Stencil.StencilSinkId("asm_sink")

local output_access = Stencil.StencilAccess(
  "out", Stencil.StencilAccessWrite, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local const_stream = Stencil.StencilStreamDef(
  stream_id, i32, Stencil.StencilStreamConst(
    Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("7"))), i32))
local sink = Stencil.StencilSinkDef(
  sink_id, Stencil.StencilSinkOpStore(
    Stencil.StencilAccessRef("out"), Stencil.StencilIndexProducer,
    Stencil.StencilStreamRef(stream_id), Stencil.StencilStoreElementwise))
local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("asm_computation"), producer,
  { output_access }, { const_stream }, { sink },
  Stencil.StencilFusionLegality({}, {}, {}), schedule, {})

local function backend_info(mem_access)
  return Mem.MemBackendAccessInfo(
    mem_access, Mem.MemNonTrapping("fixture"), Mem.MemAlignKnown(4),
    Mem.MemBoundsInObject("fixture"), Mem.MemDerefBytesKnown(4),
    Mem.MemMovementMovable("fixture"), {})
end
local lane = Kernel.KernelLane(
  lane_id, Mem.MemObjectId("asm_object"), { access_id },
  Mem.MemBaseValue(base), i32, Mem.MemAccessScalar, { backend_info(access_id) })

local stored_binding = Kernel.KernelBinding(
  Kernel.KernelValueId("asm_stored"), i32, Kernel.KernelExprValue(stored))
local planned = Kernel.KernelPlanned(
  Kernel.KernelId("asm_kernel"), Kernel.KernelSubjectLoop(loop_id),
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(
      Flow.FlowDomainLoop(loop_id), Kernel.KernelTripKnown(trip_count),
      Kernel.KernelCounterValue(index)),
    Kernel.KernelLaneProjection({
      Kernel.KernelLaneByAccessEntry(access_id, lane) }),
    Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(stored, stored_binding) }),
    Kernel.KernelEffectProjection({}), Kernel.KernelResultVoid,
    Kernel.KernelEquivalenceProof({
      Kernel.KernelProofFunctionEquivalence("fixture") })))

local access_projection = Stencil.StencilAccessByKernelLaneProjection({
  Stencil.StencilAccessByKernelLaneEntry(lane, output_access) })
local stream_projection = Stencil.StencilStreamByKernelValueProjection({
  Stencil.StencilStreamByKernelValueEntry(stored, stored_binding, const_stream) })
local source_shape = Flow.FlowDomainShapeFact(
  Flow.FlowDomainLoop(loop_id),
  Flow.FlowDomainShapeRange1D(
    i32, Value.ValueExprValue(start), Value.ValueExprValue(stop),
    1, Flow.FlowDomainForward),
  {}, Flow.FlowFactCheckerDerived)
local domain_provenance = Stencil.StencilKernelCountedDomain1D(source_shape)
local provenance = Stencil.StencilKernelProvenanceFacet(
  planned, iteration, domain_provenance, access_projection, stream_projection,
  Stencil.StencilKernelResultVoid)

local materialization = computation:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("asm_kernel")))
  :cmat_attach_kernel_provenance(provenance)

local source_schedule = Schedule.SchedulePlanned(
  Schedule.ScheduleId("asm_schedule"), planned.id,
  Schedule.ScheduleScalarIndex, {}, {})
local memory_spine = materialization.kernel:cmat_memory_use_spine()
assert(#memory_spine.uses == 1)
local memory_basis = Lower.LowerCMatAddressBasis(
  Mem.MemBaseValue(base), Flow.FlowInduction(
    index, i32, start, step, Flow.FlowPrimaryInduction,
    Flow.FlowRangeUnknown(index)), 4)
local coordinate_facet = Lower.LowerCMatCoordinateFacet(
  memory_spine, provenance.iteration, {
  Lower.LowerCMatUseCoordinateEntry(
    memory_spine.uses[1].id,
    Lower.LowerCMatIterationAffineCoordinate(memory_basis, 0)),
})
local cmat_projection = Lower.LowerKernelCMatProjection({
  Lower.LowerKernelCMatEntry(planned.id, Lower.LowerKernelCMatReady(
    Stencil.StencilKernelComputationProjection(source_schedule, provenance, computation),
    materialization,
    Lower.LowerCMatCoordinatesProjected(coordinate_facet))) })

----------------------------------------------------------------------
-- Function fixtures: entry → body(loop) → exit
----------------------------------------------------------------------

local exit_term = Code.CodeTerm(
  Code.CodeTermId("exit_ret"), Code.CodeTermReturn({}), origin)
local exit_block = Code.CodeBlock(exit_id, "exit", {}, {}, exit_term, origin)

local function body_jump_term()
  return Code.CodeTerm(Code.CodeTermId("body_jump"), Code.CodeTermJump(exit_id, {}), origin)
end
local function entry_jump_term(args)
  return Code.CodeTerm(Code.CodeTermId("entry_jump"), Code.CodeTermJump(body_id, args), origin)
end

-- Zero-argument replacement: body has no parameters.
local func_zero = Code.CodeFunc(
  func_id, "asm_zero_arg", Code.CodeLinkageExport, sig_id,
  {
    Code.CodeParam(trip, "trip", i32, origin),
    Code.CodeParam(start, "start", i32, origin),
    Code.CodeParam(base, "base", ptr_ty, origin),
  }, {}, entry_id, {
    Code.CodeBlock(entry_id, "entry", {}, {}, entry_jump_term({}), origin),
    Code.CodeBlock(body_id, "body", {}, {}, body_jump_term(), origin),
    exit_block,
  }, origin)

-- Parameterized replacement: the body block carries one baseline parameter
-- and the entry predecessor passes one argument atom.
local func_param = Code.CodeFunc(
  func_id, "asm_param", Code.CodeLinkageExport, sig_id,
  {
    Code.CodeParam(trip, "trip", i32, origin),
    Code.CodeParam(start, "start", i32, origin),
    Code.CodeParam(base, "base", ptr_ty, origin),
  }, {}, entry_id, {
    Code.CodeBlock(entry_id, "entry", {}, {}, entry_jump_term({ base }), origin),
    Code.CodeBlock(body_id, "body", {
      Code.CodeParam(body_base, "body_base", ptr_ty, origin),
    }, {}, body_jump_term(), origin),
    exit_block,
  }, origin)

local graph = Graph.CodeFuncGraph(func_id, {
  Graph.GraphEdge(
    Graph.GraphBlockId(func_id, entry_id),
    Graph.GraphBlockId(func_id, body_id), Graph.EdgeKindJump),
  Graph.GraphEdge(
    Graph.GraphBlockId(func_id, body_id),
    Graph.GraphBlockId(func_id, exit_id), Graph.EdgeKindJump),
}, {}, {}, {
  Graph.GraphLoop(loop_id, func_id,
    Graph.GraphBlockId(func_id, body_id),
    { Graph.GraphBlockId(func_id, body_id) }, {},
    { Graph.GraphEdge(
        Graph.GraphBlockId(func_id, body_id),
        Graph.GraphBlockId(func_id, exit_id), Graph.EdgeKindJump) }),
})

local module = Code.CodeModule(
  Code.CodeModuleId("asm_module"),
  { Code.CodeSig(sig_id, { i32, i32, ptr_ty }, {}) },
  {}, {}, {}, {}, { func_param }, origin)
local spine = Lower.LowerBackSpine(module, Graph.CodeGraph(module.id, { graph }), target)

local signatures = Lower.LowerCSignatureProjection({
  Code.CodeSig(sig_id, { i32, i32, ptr_ty }, {}):lower_c_signature_entry() })
local baseline_param = func_param:lower_c_function(Lower.LowerCFunctionInput(signatures))
local baseline_zero = func_zero:lower_c_function(Lower.LowerCFunctionInput(signatures))

local kernel_fragment = Lower.LowerFragment(
  Lower.LowerFragmentId("asm_kernel_frag"),
  Lower.LowerCoverLoop(loop_id),
  Lower.LowerStrategyKernel(planned.id, source_schedule.id),
  { Lower.LowerProofCoverage("assembly fixture") }, {})
local kernel_plan = Lower.LowerFuncPlan(func_id, { kernel_fragment })

local function assemble(code_func, baseline, plan)
  return Lower.LowerCFunctionAssemblyInput(
    spine, code_func, plan, baseline, cmat_projection)
    :lower_c_function_assembly()
end

----------------------------------------------------------------------
-- Case 1: baseline-only plan retains every block.
----------------------------------------------------------------------

local baseline_only = assemble(
  func_param, baseline_param, Lower.LowerFuncPlan(func_id, {}))
assert(asdl.classof(baseline_only) == Lower.LowerCFunctionAssemblyReady)
assert(#baseline_only.assembly.fragments == 0)
assert(#baseline_only.assembly.blocks == 3)
local baseline_emission = baseline_only.assembly:lower_c_function()
assert(baseline_emission.func.body.entry.text == "entry")

----------------------------------------------------------------------
-- Case 2: parameterized loop replacement preserves entry params and args.
----------------------------------------------------------------------

local param_result = assemble(func_param, baseline_param, kernel_plan)
assert(asdl.classof(param_result) == Lower.LowerCFunctionAssemblyReady)
local param_assembly = param_result.assembly
assert(#param_assembly.fragments == 1)
assert(asdl.classof(param_assembly.fragments[1]) == Lower.LowerCKernelCMatFragment)
local cmat = param_assembly.fragments[1].cmat

-- CMat control and block alignments stay inside the CMat fragment.
assert(cmat.control == CMat.CMatCControlNone)
assert(#cmat.block_alignments == 1)
assert(asdl.classof(cmat.block_alignments[1]) == CMat.CMatCBlockReplacementEntry)
assert(cmat.block_alignments[1].source == body_id)

-- Spliced CMat entry block receives the exact baseline replacement params.
local splice_entry = param_assembly.blocks[1]
assert(splice_entry.label == cmat.entry)
assert(#splice_entry.params == 1)
local baseline_body_params = baseline_param:lower_c_block_params(body_id)
assert(#baseline_body_params == 1)
assert(splice_entry.params[1] == baseline_body_params[1])

-- Body block eliminated; entry and exit retained, in deterministic order.
assert(#param_assembly.blocks == 7) -- 5 fragment blocks + entry + exit
local entry_block = param_assembly.blocks[6]
local exit_block_out = param_assembly.blocks[7]
assert(entry_block.label.text == "entry")
assert(exit_block_out.label.text == "exit")
assert(exit_block_out.term == C.CBackendReturnVoid)

-- Retained predecessor retargeted to the CMat entry with args preserved.
assert(asdl.classof(entry_block.term) == C.CBackendGoto)
assert(entry_block.term.dest == cmat.entry)
assert(#entry_block.term.args == 1)
local base_found = baseline_param.value_types:lower_c_value_lookup(base)
assert(asdl.classof(base_found) == Lower.LowerCValueTypeFound)
assert(entry_block.term.args[1].local_id == base_found.entry.c_local.id)

-- Fragment locals/helpers are carried on the assembly.
assert(#param_assembly.locals >= 3) -- index, ordinal, test/advance locals
assert(#param_assembly.helpers >= 1) -- shared ordinal/index helper

-- Final CBackend function preserves baseline metadata and validates.
local param_emission = param_assembly:lower_c_function()
assert(asdl.classof(param_emission) == Lower.LowerCFunctionEmission)
assert(param_emission.func.name.text == "asm_param")
assert(param_emission.source == func_param)
assert(#param_emission.func.params == 3)
assert(param_emission.func.body.entry.text == "entry") -- entry not replaced
local unit = C.CBackendUnit(
  "asm_module", target, { signatures.entries[1].c_sig }, {}, {}, {},
  param_emission.helpers, { param_emission.func })
local report = require("lalin.impl.lower_emit_c.validate").validate(unit)
assert(#report.issues == 0, "assembled function must validate clean")

----------------------------------------------------------------------
-- Case 3: zero-argument loop replacement retargets with no args.
----------------------------------------------------------------------

local zero_result = assemble(func_zero, baseline_zero, kernel_plan)
assert(asdl.classof(zero_result) == Lower.LowerCFunctionAssemblyReady)
local zero_assembly = zero_result.assembly
assert(#zero_assembly.blocks == 7)
local zero_entry = zero_assembly.blocks[6]
assert(zero_entry.label.text == "entry")
assert(asdl.classof(zero_entry.term) == C.CBackendGoto)
assert(zero_entry.term.dest == zero_assembly.blocks[1].label)
assert(#zero_entry.term.args == 0)
assert(#zero_assembly.blocks[1].params == 0)

----------------------------------------------------------------------
-- Case 4: kernel with no materialization rejects with a typed issue.
----------------------------------------------------------------------

local missing_fragment = Lower.LowerFragment(
  Lower.LowerFragmentId("asm_missing"),
  Lower.LowerCoverLoop(loop_id),
  Lower.LowerStrategyKernel(Kernel.KernelId("absent"), Schedule.ScheduleId("absent_sched")),
  { Lower.LowerProofCoverage("assembly fixture") }, {})
local missing_result = assemble(
  func_param, baseline_param, Lower.LowerFuncPlan(func_id, { missing_fragment }))
assert(asdl.classof(missing_result) == Lower.LowerCFunctionAssemblyRejected)
assert(#missing_result.issues == 1)
assert(asdl.classof(missing_result.issues[1]) == Lower.LowerIssueFragmentRejected)

----------------------------------------------------------------------
-- Case 5: canonical module lowering installs the CMat replacement and GCC
-- executes the assembled function.
----------------------------------------------------------------------

local flow_facts = Flow.FlowFactSet(
  module.id, {}, {}, {}, {}, {}, {}, {})
local value_facts = Value.ValueFactSet(module.id, {}, {}, {})
local mem_facts = Mem.MemSemanticFactSet(module.id, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})
local effect_facts = Effect.EffectFactSet(module.id, {}, {}, {})
local kernel_module = Kernel.KernelModulePlan(
  module.id, flow_facts, value_facts, mem_facts, effect_facts, {})
local schedule_module = Schedule.ScheduleModulePlan(
  module.id, Schedule.ScheduleTarget(Backend.BackTargetModel(Backend.BackTargetNative, {})), {})
local module_plan = Lower.LowerModule(
  module.id, Lower.LowerTargetC, kernel_module, schedule_module,
  Lower.LowerFunctionPlanProjection({
    Lower.LowerFunctionPlanEntry(func_id, kernel_plan),
  }), {})
local module_result = module_plan:lower_c_module(
  Lower.LowerCModuleInput(spine, module_plan, cmat_projection))
assert(asdl.classof(module_result) == Lower.LowerCModuleEmitted)
local assembled_unit = module_result.emission.unit
assert(#assembled_unit.funcs == 1)
local assembled_blocks = assembled_unit.funcs[1].body.blocks
for i = 1, #assembled_blocks do
  assert(assembled_blocks[i].label.text ~= "body", "covered baseline body survived assembly")
end
local assembled_report = require("lalin.impl.lower_emit_c.validate").validate(assembled_unit)
assert(#assembled_report.issues == 0)

local c_gcc = require("lalin.emit_c_compile")
local available = c_gcc.available()
if available then
  local source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
    .emit_artifact(assembled_unit, {}).source
  local session, err = c_gcc.compile(source, {
    out_dir = "target/test_lower_cmat_assembly", stem = "canonical_assembly", opt = 3,
  })
  assert(session, err and (err.output or err.message))
  local ffi = require("ffi")
  local fn = assert(session:symbol(
    "asm_param", "void (*)(int32_t, int32_t, int32_t *)"))
  local output = ffi.new("int32_t[5]", { -1, -1, -1, -1, -1 })
  fn(3, 0, output)
  assert(output[0] == 7 and output[1] == 7 and output[2] == 7)
  session:free()
end

io.write("schema_v2 LOWER CMat assembly ok\n")
