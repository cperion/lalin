package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- CMAT-MULTISINK GCC runtime: one counted loop fused from two store sinks
-- (const 7 to out1, const 9 to out2) executes both stores per iteration in
-- computation order.

local ffi = require("ffi")
local asdl = require("lalin.asdl")
require("lalin.schema")
require("lalin.impl.lower_emit_c")

local Code = require("lalin.schema.code")
local Core = require("lalin.schema.core")
local Graph = require("lalin.schema.graph")
local Flow = require("lalin.schema.flow")
local Value = require("lalin.schema.value")
local Mem = require("lalin.schema.mem")
local Kernel = require("lalin.schema.kernel")
local Stencil = require("lalin.schema.stencil")
local CMat = require("lalin.schema.c_materialize")
local Lower = require("lalin.schema.lower")
local C = require("lalin.schema.c")
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
  io.write("test_cmat_multisink_gcc: skipped: " .. why.message .. "\n")
  os.exit(0)
end

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

local out1_access = Stencil.StencilAccess(
  "out1", Stencil.StencilAccessWrite, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local out2_access = Stencil.StencilAccess(
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
  { out1_access, out2_access }, { seven_stream, nine_stream },
  { store1, store2 },
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
  Stencil.StencilAccessByKernelLaneEntry(lane1, out1_access),
  Stencil.StencilAccessByKernelLaneEntry(lane2, out2_access),
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

local out1_param = C.CBackendLocal(
  C.CBackendLocalId("out1"), C.CBackendName("out1"), c_ptr)
local out2_param = C.CBackendLocal(
  C.CBackendLocalId("out2"), C.CBackendName("out2"), c_ptr)
local start_param = C.CBackendLocal(
  C.CBackendLocalId("start"), C.CBackendName("start"), c_i32)
local trip_param = C.CBackendLocal(
  C.CBackendLocalId("trip"), C.CBackendName("trip"), c_i32)
local values = CMat.CMatCExternalValueBindingProjection({
  CMat.CMatCExternalValueBindingEntry(start, start_param),
  CMat.CMatCExternalValueBindingEntry(trip_value, trip_param),
})
local accesses = CMat.CMatCFragmentAccessBindingProjection({
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("out1"), lane1_id, access1_id,
    CMat.CMatCFragmentAccessDirect(out1_param), 4, 4, Mem.MemAlignKnown(4),
    lane1.backend_info[1].bounds, lane1.backend_info[1].trap,
    lane1.backend_info[1].movement),
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("out2"), lane2_id, access2_id,
    CMat.CMatCFragmentAccessDirect(out2_param), 4, 4, Mem.MemAlignKnown(4),
    lane2.backend_info[1].bounds, lane2.backend_info[1].trap,
    lane2.backend_info[1].movement)
})
local address_spine = materialization.kernel:cmat_memory_use_spine()
assert(#address_spine.uses == 2)
local address_induction = Flow.FlowInduction(
  iteration.counter, iteration.index_ty, iteration.start, iteration.step,
  Flow.FlowPrimaryInduction, Flow.FlowRangeUnknown(iteration.counter))
local address_coordinates = Lower.LowerCMatCoordinateFacet(
  address_spine, iteration, {
    Lower.LowerCMatUseCoordinateEntry(address_spine.uses[1].id,
      Lower.LowerCMatIterationAffineCoordinate(
        Lower.LowerCMatAddressBasis(lane1.base, address_induction, 4), 0)),
    Lower.LowerCMatUseCoordinateEntry(address_spine.uses[2].id,
      Lower.LowerCMatIterationAffineCoordinate(
        Lower.LowerCMatAddressBasis(lane2.base, address_induction, 4), 0)),
  })
local address_projection = address_coordinates:materialize_c_address_plan(
  CMat.CMatCAddressPlanInput(iteration, accesses,
    CMat.CMatCFragmentNamespace("multisink_address")))
assert(asdl.classof(address_projection) == CMat.CMatCAddressPlanReady)
local address_plan = address_projection.plan
local exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, exit_id, C.CBackendLabel("exit"), {}),
})
local target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)
local request = CMat.CMatCFragmentInput(
  materialization, code_func, { block_id }, block_id, target,
  values, accesses, address_plan, exits,
  CMat.CMatCFragmentNamespace("multisink"), {})
local emitted = request:emit_cmat_fragment()
assert(asdl.classof(emitted) == CMat.CMatCFragmentEmitted)
local fragment = emitted.fragment
assert(#fragment.blocks == 5)
assert(#fragment.blocks[3].stmts == 2)

local blocks = {}
for i = 1, #fragment.blocks do blocks[#blocks + 1] = fragment.blocks[i] end
blocks[#blocks + 1] = C.CBackendBlock(
  C.CBackendLabel("exit"), {}, {}, C.CBackendReturnVoid)
local c_sig_id = C.CBackendFuncSigId("multisink_sig")
local c_sig = C.CBackendFuncSig(
  c_sig_id, { c_ptr, c_ptr, c_i32, c_i32 }, C.CBackendVoid)
local c_func = C.CBackendFunc(
  C.CBackendName("multisink"), "multisink", Core.VisibilityExport,
  c_sig_id, { out1_param, out2_param, start_param, trip_param },
  fragment.locals, C.CBackendBodyBlocks(fragment.entry, blocks))
local unit = C.CBackendUnit(
  "multisink", target, { c_sig }, {}, {}, {}, fragment.helpers, { c_func })
local report = require("lalin.impl.lower_emit_c.validate").validate(unit)
assert(#report.issues == 0)

local source = require("tests.c_backend.cemit_source").source(unit, target)
local session, err = c_gcc.compile(source, {
  out_dir = "target/test_cmat_multisink_gcc",
  stem = "multisink",
  opt = 3,
})
assert(session, err and (err.output or err.message))
local fn = assert(session:symbol(
  "multisink",
  "void (*)(int32_t *, int32_t *, int32_t, int32_t)"))
local out1 = ffi.new("int32_t[8]")
local out2 = ffi.new("int32_t[8]")
for i = 0, 7 do out1[i] = -1; out2[i] = -1 end
fn(out1, out2, 0, 4)
for i = 0, 3 do
  assert(out1[i] == 7 and out2[i] == 9, "iteration " .. i .. " must store both sinks")
end
for i = 4, 7 do
  assert(out1[i] == -1 and out2[i] == -1, "iteration " .. i .. " must stay untouched")
end
for i = 0, 7 do out1[i] = -1; out2[i] = -1 end
fn(out1, out2, 2, 0)
for i = 0, 7 do
  assert(out1[i] == -1 and out2[i] == -1, "zero-trip multisink must not write")
end
session:free()

io.write("cmat multisink GCC ok\n")
