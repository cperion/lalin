package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
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
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then
  io.write("test_cmat_all_compare_memcmp_gcc: skipped: " .. why.message .. "\n")
  os.exit(0)
end

local tag = "all_compare_memcmp"
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local u8 = Code.CodeTyInt(8, Code.CodeUnsigned)
local index_ty = Code.CodeTyIndex
local c_i32 = C.CBackendScalar(Core.ScalarI32)
local c_u8 = C.CBackendScalar(Core.ScalarU8)
local c_u8ptr = C.CBackendDataPtr(c_u8)
local origin = Code.CodeOriginUnknown

-- ---------------------------------------------------------------------------
-- Kernel vocabulary: byte lanes with exact bounds, readonly, declared noalias
-- ---------------------------------------------------------------------------
local func_id = Code.CodeFuncId(tag)
local sig_id = Code.CodeSigId(tag .. "_sig")
local block_id = Code.CodeBlockId("source_loop")
local loop_id = Graph.GraphLoopId(tag .. "_loop")
local domain = Flow.FlowDomainLoop(loop_id)
local index = Code.CodeValueId("source_index")
local start = Code.CodeValueId("start")
local stop = Code.CodeValueId("stop")
local step = Code.CodeValueId("step")
local trip_value = Code.CodeValueId("trip")
local left_value = Code.CodeValueId(tag .. ":left")
local right_value = Code.CodeValueId(tag .. ":right")
local left_mem_access = Mem.MemAccessId(tag .. "_left_access")
local right_mem_access = Mem.MemAccessId(tag .. "_right_access")
local left_lane_id = Kernel.KernelLaneId(tag .. "_left_lane")
local right_lane_id = Kernel.KernelLaneId(tag .. "_right_lane")
local left_stream_id = Stencil.StencilStreamId(tag .. ":left")
local right_stream_id = Stencil.StencilStreamId(tag .. ":right")
local sink_id = Stencil.StencilSinkId(tag .. ":sink")
local success_id = Code.CodeBlockId(tag .. ":success")
local failure_id = Code.CodeBlockId(tag .. ":failure")

local trip = Flow.FlowTripCountExact(trip_value, nil, nil)
local iteration = Stencil.StencilKernelIteration(
  loop_id, index, index_ty, start, stop, step, 1,
  Stencil.StencilIterationStopInclusive,
  Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(trip))

local producer = Stencil.StencilProducer(
  Stencil.StencilProducerOriginNone,
  Stencil.StencilProduceCountedRange1D(
    index_ty, Stencil.StencilBoundValue(Value.ValueExprValue(start)),
    Stencil.StencilBoundValue(Value.ValueExprValue(stop)), 1,
    Stencil.StencilProducerForward, Stencil.StencilIterationStopInclusive,
    Stencil.StencilKernelTripExact(trip)))

local left_access = Stencil.StencilAccess(
  "left_bytes", Stencil.StencilAccessRead, u8,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(1)))
local right_access = Stencil.StencilAccess(
  "right_bytes", Stencil.StencilAccessRead, u8,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(1)))

local left_stream = Stencil.StencilStreamDef(
  left_stream_id, u8, Stencil.StencilStreamAccess(
    Stencil.StencilAccessRef("left_bytes"), Stencil.StencilIndexProducer))
local right_stream = Stencil.StencilStreamDef(
  right_stream_id, u8, Stencil.StencilStreamAccess(
    Stencil.StencilAccessRef("right_bytes"), Stencil.StencilIndexProducer))

local sink = Stencil.StencilSinkDef(sink_id, Stencil.StencilSinkOpAllCompare(
  Stencil.StencilStreamRef(left_stream_id),
  Stencil.StencilStreamRef(right_stream_id), Core.CmpEq))

local legality = Stencil.StencilFusionLegality({
  Stencil.StencilFusionAccessAliasRelation(
    Stencil.StencilAccessRef("left_bytes"),
    Stencil.StencilAccessRef("right_bytes"),
    Stencil.StencilAliasNoAlias),
}, {}, {})

local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local computation = Stencil.StencilComputation(
  Stencil.StencilComputationId(tag), producer,
  { left_access, right_access },
  { left_stream, right_stream }, { sink },
  legality, schedule, {})

local function backend_info(mem_access)
  return Mem.MemBackendAccessInfo(
    mem_access, Mem.MemNonTrapping("fixture"), Mem.MemAlignKnown(1),
    Mem.MemBoundsInObject("fixture"), Mem.MemDerefBytesKnown(1),
    Mem.MemMovementMovable("fixture"), {})
end

local left_lane = Kernel.KernelLane(
  left_lane_id, Mem.MemObjectId("left_object"), { left_mem_access },
  Mem.MemBaseLocal(Code.CodeLocalId("left")), u8,
  Mem.MemAccessScalar, { backend_info(left_mem_access) })
local right_lane = Kernel.KernelLane(
  right_lane_id, Mem.MemObjectId("right_object"), { right_mem_access },
  Mem.MemBaseLocal(Code.CodeLocalId("right")), u8,
  Mem.MemAccessScalar, { backend_info(right_mem_access) })

local left_binding = Kernel.KernelBinding(
  Kernel.KernelValueId(tag .. ":left-binding"), u8,
  Kernel.KernelExprLaneLoad(left_lane, Value.ValueExprValue(index)))
local right_binding = Kernel.KernelBinding(
  Kernel.KernelValueId(tag .. ":right-binding"), u8,
  Kernel.KernelExprLaneLoad(right_lane, Value.ValueExprValue(index)))

local result = Kernel.KernelResultAllCompare(
  Kernel.KernelExprLaneLoad(left_lane, Value.ValueExprValue(index)), left_value,
  Kernel.KernelExprLaneLoad(right_lane, Value.ValueExprValue(index)), right_value,
  Core.CmpEq, success_id, failure_id)

local subject = Kernel.KernelSubjectLoop(loop_id)
local planned = Kernel.KernelPlanned(
  Kernel.KernelId(tag), subject, Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, Kernel.KernelTripKnown(trip),
      Kernel.KernelCounterValue(index)),
    Kernel.KernelLaneProjection({
      Kernel.KernelLaneByAccessEntry(left_mem_access, left_lane),
      Kernel.KernelLaneByAccessEntry(right_mem_access, right_lane),
    }),
    Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(left_value, left_binding),
      Kernel.KernelBindingByCodeValueEntry(right_value, right_binding),
    }),
    Kernel.KernelEffectProjection({}), result,
    Kernel.KernelEquivalenceProof({ Kernel.KernelProofFunctionEquivalence("fixture") })))

local source_shape = Flow.FlowDomainShapeFact(
  domain, Flow.FlowDomainShapeRange1D(
    index_ty, Value.ValueExprValue(start), Value.ValueExprValue(stop),
    1, Flow.FlowDomainForward), {}, Flow.FlowFactCheckerDerived)
local domain_provenance = Stencil.StencilKernelCountedDomain1D(source_shape)

local provenance = Stencil.StencilKernelProvenanceFacet(
  planned, iteration, domain_provenance,
  Stencil.StencilAccessByKernelLaneProjection({
    Stencil.StencilAccessByKernelLaneEntry(left_lane, left_access),
    Stencil.StencilAccessByKernelLaneEntry(right_lane, right_access),
  }),
  Stencil.StencilStreamByKernelValueProjection({
    Stencil.StencilStreamByKernelValueEntry(left_value, left_binding, left_stream),
    Stencil.StencilStreamByKernelValueEntry(right_value, right_binding, right_stream),
  }),
  Stencil.StencilKernelResultAllCompare(
    sink_id, Stencil.StencilStreamRef(left_stream_id), left_value,
    Stencil.StencilStreamRef(right_stream_id), right_value,
    Core.CmpEq, success_id, failure_id))

local materialization = computation:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId(tag)))
  :cmat_attach_kernel_provenance(provenance)

-- ---------------------------------------------------------------------------
-- Fragment assembly: baseline function, params, exits, address plan
-- ---------------------------------------------------------------------------
local source_term = Code.CodeTerm(
  Code.CodeTermId("source_return"), Code.CodeTermReturn({}), origin)
local source_block = Code.CodeBlock(
  block_id, "source_loop", {}, {}, source_term, origin)
local code_func = Code.CodeFunc(
  func_id, tag, Code.CodeLinkageExport, sig_id,
  {}, {}, block_id, {
    source_block,
    Code.CodeBlock(success_id, tag .. ":success", {}, {}, source_term, origin),
    Code.CodeBlock(failure_id, tag .. ":failure", {}, {}, source_term, origin),
  }, origin)

local left_param = C.CBackendLocal(
  C.CBackendLocalId("left"), C.CBackendName("left"), c_u8ptr)
local right_param = C.CBackendLocal(
  C.CBackendLocalId("right"), C.CBackendName("right"), c_u8ptr)
local start_param = C.CBackendLocal(
  C.CBackendLocalId("start"), C.CBackendName("start"), C.CBackendIndex)
local len_param = C.CBackendLocal(
  C.CBackendLocalId("len"), C.CBackendName("len"), C.CBackendIndex)

local external_values = CMat.CMatCExternalValueBindingProjection({
  CMat.CMatCExternalValueBindingEntry(start, start_param),
  CMat.CMatCExternalValueBindingEntry(trip_value, len_param),
})

local fragment_accesses = CMat.CMatCFragmentAccessBindingProjection({
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("left_bytes"), left_lane_id, left_mem_access,
    CMat.CMatCFragmentAccessDirect(left_param), 1, 1, Mem.MemAlignKnown(1),
    Mem.MemBoundsInObject("fixture"), Mem.MemNonTrapping("fixture"),
    Mem.MemMovementMovable("fixture")),
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("right_bytes"), right_lane_id, right_mem_access,
    CMat.CMatCFragmentAccessDirect(right_param), 1, 1, Mem.MemAlignKnown(1),
    Mem.MemBoundsInObject("fixture"), Mem.MemNonTrapping("fixture"),
    Mem.MemMovementMovable("fixture")),
})

local spine = materialization.kernel:cmat_memory_use_spine()
assert(#spine.uses == 2, "all-compare memcmp fixture requires two lane memory uses")
local addressing = {
  CMat.CMatCUseAddressingEntry(spine.uses[1].id,
    CMat.CMatCAbsoluteAddressing(left_param,
      Stencil.StencilIndexAxis(Stencil.StencilAxisRef(1)), 1, 0)),
  CMat.CMatCUseAddressingEntry(spine.uses[2].id,
    CMat.CMatCAbsoluteAddressing(right_param,
      Stencil.StencilIndexAxis(Stencil.StencilAxisRef(1)), 1, 0)),
}
local address_plan = CMat.CMatCAddressPlan(
  spine, materialization.provenance.iteration, {}, addressing)

local exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(CMat.CMatCExitSuccess, success_id,
    C.CBackendLabel(tag .. "_success"), {}),
  CMat.CMatCExitBindingEntry(CMat.CMatCExitFailure, failure_id,
    C.CBackendLabel(tag .. "_failure"), {}),
})

local target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)

local emission = CMat.CMatCFragmentInput(
  materialization, code_func, { block_id }, block_id, target,
  external_values, fragment_accesses, address_plan, exits,
  CMat.CMatCFragmentNamespace(tag), {}):emit_cmat_fragment()

assert(asdl.classof(emission) == CMat.CMatCFragmentEmitted,
  "all-compare memcmp fragment must be emitted")
assert(asdl.classof(emission.fragment.control) == CMat.CMatCControlAllCompare,
  "all-compare memcmp fragment must carry an all-compare control result")
assert(#emission.fragment.blocks == 1,
  "all-compare memcmp fragment must be straight-line (one block, no counted loop)")
assert(#emission.fragment.helpers == 1,
  "all-compare memcmp fragment must register the memcmp helper")
assert(emission.fragment.helpers[1].id.text == "ml_memcmp",
  "all-compare memcmp fragment must use the ml_memcmp helper")

-- ---------------------------------------------------------------------------
-- Assemble the C unit, validate, and check the emitted source
-- ---------------------------------------------------------------------------
local blocks = {}
for i = 1, #emission.fragment.blocks do
  blocks[#blocks + 1] = emission.fragment.blocks[i]
end
blocks[#blocks + 1] = C.CBackendBlock(
  C.CBackendLabel(tag .. "_success"), {}, {},
  C.CBackendReturn(C.CBackendAtomLiteral(c_i32, Core.LitInt("1"))))
blocks[#blocks + 1] = C.CBackendBlock(
  C.CBackendLabel(tag .. "_failure"), {}, {},
  C.CBackendReturn(C.CBackendAtomLiteral(c_i32, Core.LitInt("0"))))

local c_sig_id = C.CBackendFuncSigId(tag .. "_sig")
local c_sig = C.CBackendFuncSig(
  c_sig_id, { c_u8ptr, c_u8ptr, C.CBackendIndex, C.CBackendIndex }, c_i32)
local c_func = C.CBackendFunc(
  C.CBackendName(tag), tag, Core.VisibilityExport,
  c_sig_id, { left_param, right_param, start_param, len_param },
  emission.fragment.locals, C.CBackendBodyBlocks(emission.fragment.entry, blocks))
local unit = C.CBackendUnit(
  tag, target, { c_sig }, {}, {}, {}, emission.fragment.helpers, { c_func })

local report = require("lalin.impl.lower_emit_c.validate").validate(unit)
assert(#report.issues == 0, "all-compare memcmp C unit must validate cleanly")

local source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
  .emit_artifact(unit, {}).source
assert(source:find("return memcmp(a1, a2, (size_t)a3);", 1, true) ~= nil,
  "emitted C must contain a memcmp( call: " .. source)
assert(source:find("ml_memcmp") ~= nil,
  "emitted C must contain the ml_memcmp helper: " .. source)

-- ---------------------------------------------------------------------------
-- GCC execution: equal, first-byte-differing, and long strings
-- ---------------------------------------------------------------------------
local session, err = c_gcc.compile(source, {
  out_dir = "target/test_cmat_all_compare_memcmp_gcc",
  stem = tag, opt = 3,
})
assert(session, err and (err.output or err.message))
local eq = assert(session:symbol(
  tag, "int32_t (*)(const uint8_t*, const uint8_t*, size_t, size_t)"))

local function cstr(s)
  local buf = ffi.new("uint8_t[?]", #s + 1)
  ffi.copy(buf, s, #s)
  return buf
end

local a = cstr("hello")
local b = cstr("hello")
local c = cstr("jello")
assert(eq(a, b, 0, 5) == 1, "equal short strings must exit success")
assert(eq(a, c, 0, 5) == 0, "first-byte-differing strings must exit failure")
assert(eq(a, c, 0, 0) == 1, "empty compare must exit success")

local long_a = ffi.new("uint8_t[4096]")
local long_b = ffi.new("uint8_t[4096]")
for i = 0, 4095 do long_a[i] = i % 251 end
for i = 0, 4095 do long_b[i] = i % 251 end
assert(eq(long_a, long_b, 0, 4096) == 1, "equal long strings must exit success")
long_b[4095] = bit.bxor(long_b[4095], 1)
assert(eq(long_a, long_b, 0, 4096) == 0, "last-byte-differing long strings must exit failure")
assert(eq(long_a, long_b, 0, 4095) == 1, "prefix compare must exit success")

session:free()
io.write("test_cmat_all_compare_memcmp_gcc: ok\n")
