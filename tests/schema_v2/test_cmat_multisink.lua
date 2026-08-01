package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- CMAT-MULTISINK: scalar counted fragment emission accepts multiple sinks
-- and emits them deterministically in computation order. Two store sinks
-- (const 7 to out1, const 9 to out2) must produce one counted loop whose
-- body executes both stores, in computation order, with a single shared
-- control result (None) and the CMat fragment otherwise unchanged.

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")

local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Kernel = require("lalin.schema_v2.kernel")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local c_i32 = C.CBackendScalar(Core.ScalarI32)
local c_ptr = C.CBackendDataPtr(c_i32)

local func_id = Code.CodeFuncId("multisink")
local sig_id = Code.CodeSigId("multisink_sig")
local block_id = Code.CodeBlockId("body")
local exit_id = Code.CodeBlockId("exit")
local loop_id = Graph.GraphLoopId("multisink_loop")
local start = Code.CodeValueId("start")
local stop = Code.CodeValueId("stop")
local step = Code.CodeValueId("step")
local trip_value = Code.CodeValueId("trip")
local index = Code.CodeValueId("index")

local trip = Flow.FlowTripCountExact(trip_value, nil, nil)
local iteration = Stencil.StencilKernelIteration(
  loop_id, index, i32, start, stop, step, 1,
  Stencil.StencilIterationStopInclusive, Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(trip))
local producer = Stencil.StencilProducer(
  Stencil.StencilProducerOriginNone,
  Stencil.StencilProduceCountedRange1D(
    i32, Stencil.StencilBoundValue(Value.ValueExprValue(start)),
    Stencil.StencilBoundValue(Value.ValueExprValue(stop)), 1,
    Stencil.StencilProducerForward, Stencil.StencilIterationStopInclusive,
    Stencil.StencilKernelTripExact(trip)))

local access1_id = Mem.MemAccessId("out1_access")
local access2_id = Mem.MemAccessId("out2_access")
local lane1_id = Kernel.KernelLaneId("out1_lane")
local lane2_id = Kernel.KernelLaneId("out2_lane")
local stream1_id = Stencil.StencilStreamId("seven_stream")
local stream2_id = Stencil.StencilStreamId("nine_stream")
local sink1_id = Stencil.StencilSinkId("store1")
local sink2_id = Stencil.StencilSinkId("store2")

local out1 = Stencil.StencilAccess(
  "out1", Stencil.StencilAccessWrite, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local out2 = Stencil.StencilAccess(
  "out2", Stencil.StencilAccessWrite, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local seven_stream = Stencil.StencilStreamDef(
  stream1_id, i32, Stencil.StencilStreamConst(
    Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("7"))), i32))
local nine_stream = Stencil.StencilStreamDef(
  stream2_id, i32, Stencil.StencilStreamConst(
    Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("9"))), i32))
local store1 = Stencil.StencilSinkDef(
  sink1_id, Stencil.StencilSinkOpStore(
    Stencil.StencilAccessRef("out1"), Stencil.StencilIndexProducer,
    Stencil.StencilStreamRef(stream1_id), Stencil.StencilStoreElementwise))
local store2 = Stencil.StencilSinkDef(
  sink2_id, Stencil.StencilSinkOpStore(
    Stencil.StencilAccessRef("out2"), Stencil.StencilIndexProducer,
    Stencil.StencilStreamRef(stream2_id), Stencil.StencilStoreElementwise))
local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("multisink"), producer,
  { out1, out2 }, { seven_stream, nine_stream }, { store1, store2 },
  Stencil.StencilFusionLegality({}, {}, {}), schedule, {})

local function backend_info(mem_access)
  return Mem.MemBackendAccessInfo(
    mem_access, Mem.MemNonTrapping("fixture"), Mem.MemAlignKnown(4),
    Mem.MemBoundsInObject("fixture"), Mem.MemDerefBytesKnown(4),
    Mem.MemMovementMovable("fixture"), {})
end
local lane1 = Kernel.KernelLane(
  lane1_id, Mem.MemObjectId("out1_object"), { access1_id },
  Mem.MemBaseValue(Code.CodeValueId("base1")), i32,
  Mem.MemAccessScalar, { backend_info(access1_id) })
local lane2 = Kernel.KernelLane(
  lane2_id, Mem.MemObjectId("out2_object"), { access2_id },
  Mem.MemBaseValue(Code.CodeValueId("base2")), i32,
  Mem.MemAccessScalar, { backend_info(access2_id) })
local stored1 = Code.CodeValueId("stored1")
local stored2 = Code.CodeValueId("stored2")
local binding1 = Kernel.KernelBinding(
  Kernel.KernelValueId("v1"), i32, Kernel.KernelExprValue(stored1))
local binding2 = Kernel.KernelBinding(
  Kernel.KernelValueId("v2"), i32, Kernel.KernelExprValue(stored2))
local planned = Kernel.KernelPlanned(
  Kernel.KernelId("multisink_kernel"), Kernel.KernelSubjectLoop(loop_id),
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(
      Flow.FlowDomainLoop(loop_id), Kernel.KernelTripKnown(trip),
      Kernel.KernelCounterValue(index)),
    Kernel.KernelLaneProjection({
      Kernel.KernelLaneByAccessEntry(access1_id, lane1),
      Kernel.KernelLaneByAccessEntry(access2_id, lane2),
    }),
    Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(stored1, binding1),
      Kernel.KernelBindingByCodeValueEntry(stored2, binding2),
    }),
    Kernel.KernelEffectProjection({}), Kernel.KernelResultVoid,
    Kernel.KernelEquivalenceProof({
      Kernel.KernelProofFunctionEquivalence("fixture") })))

local access_projection = Stencil.StencilAccessByKernelLaneProjection({
  Stencil.StencilAccessByKernelLaneEntry(lane1, out1),
  Stencil.StencilAccessByKernelLaneEntry(lane2, out2),
})
local stream_projection = Stencil.StencilStreamByKernelValueProjection({
  Stencil.StencilStreamByKernelValueEntry(stored1, binding1, seven_stream),
  Stencil.StencilStreamByKernelValueEntry(stored2, binding2, nine_stream),
})
local source_shape = Flow.FlowDomainShapeFact(
  Flow.FlowDomainLoop(loop_id),
  Flow.FlowDomainShapeRange1D(
    i32, Value.ValueExprValue(start), Value.ValueExprValue(stop),
    1, Flow.FlowDomainForward),
  {}, Flow.FlowFactCheckerDerived)
local provenance = Stencil.StencilKernelProvenanceFacet(
  planned, iteration, Stencil.StencilKernelCountedDomain1D(source_shape),
  access_projection, stream_projection, Stencil.StencilKernelResultVoid)
local materialization = computation:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("multisink_kernel")))
  :cmat_attach_kernel_provenance(provenance)

local origin = Code.CodeOriginUnknown
local body_block = Code.CodeBlock(
  block_id, "body", {}, {},
  Code.CodeTerm(Code.CodeTermId("body_ret"), Code.CodeTermReturn({}), origin), origin)
local exit_block = Code.CodeBlock(
  exit_id, "exit", {}, {},
  Code.CodeTerm(Code.CodeTermId("exit_ret"), Code.CodeTermReturn({}), origin), origin)
local code_func = Code.CodeFunc(
  func_id, "multisink", Code.CodeLinkageExport, sig_id,
  {}, {}, block_id, { body_block, exit_block }, origin)

local start_local = C.CBackendLocal(
  C.CBackendLocalId("start"), C.CBackendName("start"), c_i32)
local trip_local = C.CBackendLocal(
  C.CBackendLocalId("trip"), C.CBackendName("trip"), c_i32)
local out1_local = C.CBackendLocal(
  C.CBackendLocalId("out1"), C.CBackendName("out1"), c_ptr)
local out2_local = C.CBackendLocal(
  C.CBackendLocalId("out2"), C.CBackendName("out2"), c_ptr)
local values = CMat.CMatCExternalValueBindingProjection({
  CMat.CMatCExternalValueBindingEntry(start, start_local),
  CMat.CMatCExternalValueBindingEntry(trip_value, trip_local),
})
local accesses = CMat.CMatCFragmentAccessBindingProjection({
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("out1"), lane1_id, access1_id,
    CMat.CMatCFragmentAccessDirect(out1_local), 4, 4, Mem.MemAlignKnown(4)),
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("out2"), lane2_id, access2_id,
    CMat.CMatCFragmentAccessDirect(out2_local), 4, 4, Mem.MemAlignKnown(4)),
})
local address_spine = materialization.kernel:cmat_memory_use_spine()
local address_plan = CMat.CMatCAddressPlan(
  address_spine, materialization.provenance.iteration, {}, {
    CMat.CMatCUseAddressingEntry(address_spine.uses[1].id,
      CMat.CMatCIterationAddressing(out1_local, 4, 0)),
    CMat.CMatCUseAddressingEntry(address_spine.uses[2].id,
      CMat.CMatCIterationAddressing(out2_local, 4, 0)),
  })
local exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, exit_id, C.CBackendLabel("exit"), {}),
})
local request = CMat.CMatCFragmentInput(
  materialization, code_func, { block_id }, block_id,
  C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian),
  values, accesses, address_plan, exits,
  CMat.CMatCFragmentNamespace("multisink"), {})

local emission = request:emit_cmat_fragment()
assert(asdl.classof(emission) == CMat.CMatCFragmentEmitted)
local fragment = emission.fragment

-- One counted loop; the body carries both stores in computation order.
assert(#fragment.blocks == 5)
assert(fragment.entry.text == "multisink_entry")
assert(fragment.control == CMat.CMatCControlNone)
assert(#fragment.block_alignments == 1)
assert(asdl.classof(fragment.block_alignments[1]) == CMat.CMatCBlockReplacementEntry)
assert(fragment.block_alignments[1].source == block_id)

local body_stmts = fragment.blocks[3].stmts
assert(#body_stmts == 2, "both sinks must emit into the counted body")
assert(asdl.classof(body_stmts[1]) == C.CBackendPlaceStore)
assert(asdl.classof(body_stmts[2]) == C.CBackendPlaceStore)
assert(body_stmts[1].place.base.local_id == out1_local.id, "first sink stores out1")
assert(body_stmts[2].place.base.local_id == out2_local.id, "second sink stores out2")
assert(asdl.classof(body_stmts[1].value) == C.CBackendAtomLiteral)
assert(asdl.classof(body_stmts[2].value) == C.CBackendAtomLiteral)
assert(body_stmts[1].value.literal.raw == "7")
assert(body_stmts[2].value.literal.raw == "9")

io.write("schema_v2 CMat multisink ok\n")
