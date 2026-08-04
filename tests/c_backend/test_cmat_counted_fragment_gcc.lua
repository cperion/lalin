package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
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
  io.write("test_cmat_counted_fragment_gcc: skipped: " .. why.message .. "\n")
  os.exit(0)
end

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local exact_int = Code.CodeIntSemantics(
  Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local c_i32 = C.CBackendScalar(Core.ScalarI32)
local c_ptr = C.CBackendDataPtr(c_i32)
local func_id = Code.CodeFuncId("counted_fragment")
local sig_id = Code.CodeSigId("counted_fragment_sig")
local block_id = Code.CodeBlockId("source_loop")
local loop_id = Graph.GraphLoopId("counted_fragment_loop")
local domain = Flow.FlowDomainLoop(loop_id)
local index = Code.CodeValueId("source_index")
local load_value = Code.CodeValueId("source_load")
local plus_value = Code.CodeValueId("source_plus_one")
local alias_value = Code.CodeValueId("source_alias")
local start = Code.CodeValueId("start")
local stop = Code.CodeValueId("stop")
local step = Code.CodeValueId("step")
local trip_value = Code.CodeValueId("trip")
local access_id = Mem.MemAccessId("counted_fragment_access")
local input_access_id = Mem.MemAccessId("counted_fragment_input_access")
local lane_id = Kernel.KernelLaneId("counted_fragment_lane")
local input_lane_id = Kernel.KernelLaneId("counted_fragment_input_lane")
local stream_id = Stencil.StencilStreamId("counted_fragment_index_stream")
local plus_stream_id = Stencil.StencilStreamId("counted_fragment_plus_stream")
local alias_stream_id = Stencil.StencilStreamId("counted_fragment_alias_stream")
local sink_id = Stencil.StencilSinkId("counted_fragment_store")
local origin = Code.CodeOriginUnknown

local trip = Flow.FlowTripCountExact(trip_value, nil, nil)
local iteration = Stencil.StencilKernelIteration(
  loop_id, index, i32, start, stop, step, 1,
  Stencil.StencilIterationStopInclusive,
  Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(trip))
local producer = Stencil.StencilProducer(
  Stencil.StencilProducerOriginNone,
  Stencil.StencilProduceCountedRange1D(
    i32, Stencil.StencilBoundValue(Value.ValueExprValue(start)),
    Stencil.StencilBoundValue(Value.ValueExprValue(stop)), 1,
    Stencil.StencilProducerForward, Stencil.StencilIterationStopInclusive,
    Stencil.StencilKernelTripExact(trip)))
local input_access = Stencil.StencilAccess(
  "input", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local output = Stencil.StencilAccess(
  "out", Stencil.StencilAccessWrite, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(8)))
local stream = Stencil.StencilStreamDef(
  stream_id, i32, Stencil.StencilStreamAccess(
    Stencil.StencilAccessRef("input"), Stencil.StencilIndexProducer))
local plus_stream = Stencil.StencilStreamDef(
  plus_stream_id, i32, Stencil.StencilStreamValueExpr(
    Value.ValueExprAdd(
      Value.ValueExprValue(load_value),
      Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("1"))),
      i32, exact_int),
    i32))
local alias_stream = Stencil.StencilStreamDef(
  alias_stream_id, i32,
  Stencil.StencilStreamAlias(Stencil.StencilStreamRef(plus_stream_id)))
local sink = Stencil.StencilSinkDef(
  sink_id, Stencil.StencilSinkOpStore(
    Stencil.StencilAccessRef("out"), Stencil.StencilIndexProducer,
    Stencil.StencilStreamRef(alias_stream_id), Stencil.StencilStoreElementwise))
local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("counted_fragment"), producer,
  { input_access, output }, { stream, plus_stream, alias_stream }, { sink },
  Stencil.StencilFusionLegality({}, {}, {}), schedule, {})
local function backend_info(mem_access)
  return Mem.MemBackendAccessInfo(
    mem_access, Mem.MemNonTrapping("fixture"), Mem.MemAlignKnown(4),
    Mem.MemBoundsInObject("fixture"), Mem.MemDerefBytesKnown(4),
    Mem.MemMovementMovable("fixture"), {})
end

local input_lane = Kernel.KernelLane(
  input_lane_id, Mem.MemObjectId("input_object"), { input_access_id },
  Mem.MemBaseLocal(Code.CodeLocalId("input")), i32,
  Mem.MemAccessScalar, { backend_info(input_access_id) })
local lane = Kernel.KernelLane(
  lane_id, Mem.MemObjectId("out_object"), { access_id },
  Mem.MemBaseLocal(Code.CodeLocalId("out")), i32,
  Mem.MemAccessScalar, { backend_info(access_id) })
local binding = Kernel.KernelBinding(
  Kernel.KernelValueId("counted_fragment_load_value"), i32,
  Kernel.KernelExprLaneLoad(input_lane, Value.ValueExprValue(index)))
local plus_binding = Kernel.KernelBinding(
  Kernel.KernelValueId("counted_fragment_plus_value"), i32,
  Kernel.KernelExprAlgebra(plus_stream.op.value))
local alias_binding = Kernel.KernelBinding(
  Kernel.KernelValueId("counted_fragment_alias_value"), i32,
  Kernel.KernelExprKernelValue(plus_binding.id))
local planned = Kernel.KernelPlanned(
  Kernel.KernelId("counted_fragment_kernel"), Kernel.KernelSubjectLoop(loop_id),
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, Kernel.KernelTripKnown(trip),
      Kernel.KernelCounterValue(index)),
    Kernel.KernelLaneProjection({
      Kernel.KernelLaneByAccessEntry(input_access_id, input_lane),
      Kernel.KernelLaneByAccessEntry(access_id, lane),
    }),
    Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(load_value, binding),
      Kernel.KernelBindingByCodeValueEntry(plus_value, plus_binding),
      Kernel.KernelBindingByCodeValueEntry(alias_value, alias_binding),
    }),
    Kernel.KernelEffectProjection({}), Kernel.KernelResultVoid,
    Kernel.KernelEquivalenceProof({ Kernel.KernelProofFunctionEquivalence("fixture") })))
local access_projection = Stencil.StencilAccessByKernelLaneProjection({
  Stencil.StencilAccessByKernelLaneEntry(input_lane, input_access),
  Stencil.StencilAccessByKernelLaneEntry(lane, output),
})
local stream_projection = Stencil.StencilStreamByKernelValueProjection({
  Stencil.StencilStreamByKernelValueEntry(load_value, binding, stream),
  Stencil.StencilStreamByKernelValueEntry(plus_value, plus_binding, plus_stream),
  Stencil.StencilStreamByKernelValueEntry(alias_value, alias_binding, alias_stream),
})
local source_shape = Flow.FlowDomainShapeFact(
  domain, Flow.FlowDomainShapeRange1D(
    i32, Value.ValueExprValue(start), Value.ValueExprValue(stop),
    1, Flow.FlowDomainForward), {}, Flow.FlowFactCheckerDerived)
local domain_provenance = Stencil.StencilKernelCountedDomain1D(source_shape)
local provenance = Stencil.StencilKernelProvenanceFacet(
  planned, iteration, domain_provenance, access_projection, stream_projection,
  Stencil.StencilKernelResultVoid)
local fused = CMat.CMatFusedKernel(
  CMat.CMatKernelId("counted_fragment_kernel"), computation,
  CMat.CMatLoopNest({ CMat.CMatLoopAxis(
    Stencil.StencilAxisRef(1), CMat.CMatLocalId("source_index"), i32, 1,
    CMat.CMatLoopForward) }, CMat.CMatSchedulePolicy(1, 1, CMat.CMatVectorNone)),
  {}, {
    CMat.CMatStreamInline(Stencil.StencilStreamRef(stream_id), i32),
    CMat.CMatStreamInline(Stencil.StencilStreamRef(plus_stream_id), i32),
    CMat.CMatStreamInline(Stencil.StencilStreamRef(alias_stream_id), i32),
  },
  { CMat.CMatSinkStoreResult(Stencil.StencilSinkRef(sink_id), Stencil.StencilAccessRef("out")) },
  schedule, {})
local function materialize_kernel_fragment(tag, source_computation, source_provenance)
  return source_computation:cmat_materialize(
    CMat.CMatMaterializationInput(CMat.CMatKernelId(tag)))
:cmat_attach_kernel_provenance(source_provenance)
end
local materialization = materialize_kernel_fragment(
  "counted_fragment_kernel", computation, provenance)

local void_sig = Code.CodeSig(sig_id, {}, {})
local source_term = Code.CodeTerm(
  Code.CodeTermId("source_return"), Code.CodeTermReturn({}), origin)
local source_block = Code.CodeBlock(
  block_id, "source_loop", {}, {}, source_term, origin)
local exit_source = Code.CodeBlock(
  Code.CodeBlockId("exit"), "exit", {}, {},
  Code.CodeTerm(Code.CodeTermId("exit_return"), Code.CodeTermReturn({}), origin),
  origin)
local code_func = Code.CodeFunc(
  func_id, "counted_fragment", Code.CodeLinkageExport, sig_id,
  {}, {}, block_id, { source_block, exit_source }, origin)

local input_param = C.CBackendLocal(
  C.CBackendLocalId("input"), C.CBackendName("input"), c_ptr)
local out_param = C.CBackendLocal(
  C.CBackendLocalId("out"), C.CBackendName("out"), c_ptr)
local start_param = C.CBackendLocal(
  C.CBackendLocalId("start"), C.CBackendName("start"), c_i32)
local trip_param = C.CBackendLocal(
  C.CBackendLocalId("trip"), C.CBackendName("trip"), c_i32)
local external_values = CMat.CMatCExternalValueBindingProjection({
  CMat.CMatCExternalValueBindingEntry(start, start_param),
  CMat.CMatCExternalValueBindingEntry(trip_value, trip_param),
})
local fragment_accesses = CMat.CMatCFragmentAccessBindingProjection({
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("input"), input_lane_id, input_access_id,
    CMat.CMatCFragmentAccessDirect(input_param), 4, 4, Mem.MemAlignKnown(4),
    input_lane.backend_info[1].bounds, input_lane.backend_info[1].trap,
    input_lane.backend_info[1].movement),
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("out"), lane_id, access_id,
    CMat.CMatCFragmentAccessDirect(out_param), 4, 8, Mem.MemAlignKnown(4),
    lane.backend_info[1].bounds, lane.backend_info[1].trap,
    lane.backend_info[1].movement)
})
function CMat.CMatMemorySelectedIndex:test_coordinate(basis, _domain)
  local Lower = require("lalin.schema_v2.lower")
  return Lower.LowerCMatIterationAffineCoordinate(basis, 0)
end
function CMat.CMatMemoryWindowOffset:test_coordinate(basis, domain)
  local Lower = require("lalin.schema_v2.lower")
  return Lower.LowerCMatWindowDynamicCoordinate(
    basis, Lower.LowerCMatWindowCoordinateProvenance(
      self.offset, domain.window.extent, domain.window.boundary), 0)
end
function test_address_plan(materialization, accesses)
  local Lower = require("lalin.schema_v2.lower")
  local spine = materialization.kernel:cmat_memory_use_spine()
  local iteration = materialization.provenance.iteration
  local induction = Flow.FlowInduction(
    iteration.counter, iteration.index_ty, iteration.start, iteration.step,
    Flow.FlowPrimaryInduction, Flow.FlowRangeUnknown(iteration.counter))
  local entries = {}
  for i = 1, #spine.uses do
    local use = spine.uses[i]
    local bindings = {}
    for j = 1, #accesses.entries do
      if accesses.entries[j].access == use.access then
        bindings[#bindings + 1] = accesses.entries[j]
      end
    end
    assert(#bindings == 1, "test address plan requires one access binding")
    local provenance = {}
    for j = 1, #materialization.provenance.accesses.entries do
      local candidate = materialization.provenance.accesses.entries[j]
      if Stencil.StencilAccessRef(candidate.access.name) == use.access then
        provenance[#provenance + 1] = candidate
      end
    end
    assert(#provenance == 1, "test address plan requires one provenance entry")
    local scale = bindings[1].stride
    local basis = Lower.LowerCMatAddressBasis(
      provenance[1].lane.base, induction, scale)
    entries[#entries + 1] = Lower.LowerCMatUseCoordinateEntry(
      use.id, use.index:test_coordinate(
        basis, materialization.provenance.domain))
  end
  local facet = Lower.LowerCMatCoordinateFacet(spine, iteration, entries)
  local projection = facet:materialize_c_address_plan(CMat.CMatCAddressPlanInput(
    iteration, accesses, CMat.CMatCFragmentNamespace(
      materialization.kernel.id.text .. "_address")))
  assert(asdl.classof(projection) == CMat.CMatCAddressPlanReady,
    "test fixture must produce a canonical C address plan")
  return projection.plan
end
function cursor_address_plan()
  local Lower = require("lalin.schema_v2.lower")
  local spine = materialization.kernel:cmat_memory_use_spine()
  assert(#spine.uses == 2)
  local induction = Flow.FlowInduction(
    iteration.counter, iteration.index_ty, iteration.start, iteration.step,
    Flow.FlowPrimaryInduction, Flow.FlowRangeUnknown(iteration.counter))
  local input_basis = Lower.LowerCMatAddressBasis(input_lane.base, induction, 4)
  local output_basis = Lower.LowerCMatAddressBasis(lane.base, induction, 8)
  local input_cursor = CMat.CMatCAddressCursor(
    CMat.CMatCAddressCursorId("counted_fragment_cursor_input"), input_basis,
    input_param, CMat.CMatCFragmentAccessDirect(input_param), C.CBackendLocal(
      C.CBackendLocalId("counted_fragment_cursor_input"),
      C.CBackendName("counted_fragment_cursor_input"), c_ptr), start, 4)
  local output_cursor = CMat.CMatCAddressCursor(
    CMat.CMatCAddressCursorId("counted_fragment_cursor_output"), output_basis,
    out_param, CMat.CMatCFragmentAccessDirect(out_param), C.CBackendLocal(
      C.CBackendLocalId("counted_fragment_cursor_output"),
      C.CBackendName("counted_fragment_cursor_output"), c_ptr), start, 8)
  return CMat.CMatCAddressPlan(spine, iteration,
    { input_cursor, output_cursor }, {
      CMat.CMatCUseAddressingEntry(spine.uses[1].id,
        CMat.CMatCCursorAddressing(input_cursor.id, 0)),
      CMat.CMatCUseAddressingEntry(spine.uses[2].id,
        CMat.CMatCCursorAddressing(output_cursor.id, 0)),
    })
end
local fragment_exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, Code.CodeBlockId("exit"),
    C.CBackendLabel("exit"), {}),
})
local target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)
local request = CMat.CMatCFragmentInput(
  materialization, code_func, { block_id }, block_id, target,
  external_values, fragment_accesses,
  cursor_address_plan(), fragment_exits,
  CMat.CMatCFragmentNamespace("counted_fragment"), {})
local emitted = request:emit_cmat_fragment()
local bad_fragment_accesses = CMat.CMatCFragmentAccessBindingProjection({
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("input"), input_lane_id, input_access_id,
    CMat.CMatCFragmentAccessDirect(input_param), 4, 8, Mem.MemAlignKnown(4),
    input_lane.backend_info[1].bounds, input_lane.backend_info[1].trap,
    input_lane.backend_info[1].movement),
  fragment_accesses.entries[2],
})
local bad_access_emission = CMat.CMatCFragmentInput(
  materialization, code_func, { block_id }, block_id, target,
  external_values, bad_fragment_accesses,
  cursor_address_plan(), fragment_exits,
  CMat.CMatCFragmentNamespace("counted_fragment_bad_access"), {})
:emit_cmat_fragment()
assert(asdl.classof(bad_access_emission) == CMat.CMatCFragmentRejected)
local fragment = emitted.fragment
assert(#fragment.blocks == 5)
assert(fragment.block_alignments[1].source == block_id)

local blocks = {}
for i = 1, #fragment.blocks do blocks[#blocks + 1] = fragment.blocks[i] end
blocks[#blocks + 1] = C.CBackendBlock(
  C.CBackendLabel("exit"), {}, {}, C.CBackendReturnVoid)
local c_sig_id = C.CBackendFuncSigId("counted_fragment_sig")
local c_sig = C.CBackendFuncSig(
  c_sig_id, { c_ptr, c_ptr, c_i32, c_i32 }, C.CBackendVoid)
local c_func = C.CBackendFunc(
  C.CBackendName("counted_fragment"), "counted_fragment", Core.VisibilityExport,
  c_sig_id, { input_param, out_param, start_param, trip_param }, fragment.locals,
  C.CBackendBodyBlocks(fragment.entry, blocks))
local unit = C.CBackendUnit(
  "counted_fragment", target, { c_sig }, {}, {}, {}, fragment.helpers, { c_func })
local report = require("lalin.impl.lower_emit_c.validate").validate(unit)
assert(#report.issues == 0)
local source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
  .emit_artifact(unit, {}).source
local session, err = c_gcc.compile(source, {
  out_dir = "target/test_cmat_counted_fragment_gcc",
  stem = "counted_fragment",
  opt = 3,
})
assert(session, err and (err.output or err.message))
local fn = assert(session:symbol(
  "counted_fragment",
  "void (*)(int32_t *, int32_t *, int32_t, int32_t)"))
local source_values = ffi.new("int32_t[12]")
for i = 0, 11 do source_values[i] = i * 10 end
local values = ffi.new("int32_t[12]")
for i = 0, 11 do values[i] = -1 end
fn(source_values, values, 1, 5)
assert(values[2] == 11 and values[4] == 21 and values[6] == 31)
assert(values[8] == 41 and values[10] == 51)
for i = 0, 11 do
  if i % 2 == 1 or i == 0 then assert(values[i] == -1) end
end
for i = 0, 11 do values[i] = 99 end
fn(source_values, values, 3, 0)
for i = 0, 11 do assert(values[i] == 99) end
session:free()

local fold_stream_id = Stencil.StencilStreamId("counted_fragment_fold_index")
local fold_stream = Stencil.StencilStreamDef(
  fold_stream_id, i32,
  Stencil.StencilStreamValueExpr(Value.ValueExprValue(index), i32))
local fold_binding = Kernel.KernelBinding(
  Kernel.KernelValueId("counted_fragment_fold_index_value"), i32,
  Kernel.KernelExprValue(index))
local reduction = Value.ReductionFact(
  Value.AlgebraFactId("counted_fragment_sum"), domain,
  Code.CodeValueId("sum_result"), Code.CodeValueId("sum_update"), Value.ReductionAdd,
  Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0"))),
  Value.ValueExprValue(index), i32, nil, nil,
  Value.AlgebraProofComposite({}, "counted fragment fold"))
local fold_sink = Stencil.StencilSinkDef(
  Stencil.StencilSinkId("counted_fragment_fold"),
  Stencil.StencilSinkOpFold(
    Stencil.StencilStreamRef(fold_stream_id),
    Stencil.StencilReducer(
      Value.ReductionAdd, i32,
      Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0"))),
      Stencil.StencilArithmeticInteger(exact_int)),
    i32, Stencil.StencilReduceInitIdentity, Stencil.StencilFoldReturnsValue))
local fold_computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("counted_fragment_fold"), producer, {},
  { fold_stream }, { fold_sink }, Stencil.StencilFusionLegality({}, {}, {}),
  schedule, {})
local fold_planned = Kernel.KernelPlanned(
  Kernel.KernelId("counted_fragment_fold_kernel"), Kernel.KernelSubjectLoop(loop_id),
  Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, Kernel.KernelTripKnown(trip),
      Kernel.KernelCounterValue(index)),
    Kernel.KernelLaneProjection({}),
    Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(index, fold_binding),
    }),
    Kernel.KernelEffectProjection({}), Kernel.KernelResultReduction(reduction),
    Kernel.KernelEquivalenceProof({
      Kernel.KernelProofFunctionEquivalence("fold fixture"),
    })))
local fold_provenance = Stencil.StencilKernelProvenanceFacet(
  fold_planned, iteration, domain_provenance,
  Stencil.StencilAccessByKernelLaneProjection({}),
  Stencil.StencilStreamByKernelValueProjection({
    Stencil.StencilStreamByKernelValueEntry(
      reduction.accumulator, fold_binding, fold_stream),
  }),
  Stencil.StencilKernelResultReduction(
    fold_sink.id, Value.ReductionAdd, reduction.accumulator,
    Stencil.StencilStreamRef(fold_stream_id)))
local fold_fused = CMat.CMatFusedKernel(
  CMat.CMatKernelId("counted_fragment_fold_kernel"), fold_computation,
  CMat.CMatLoopNest({ CMat.CMatLoopAxis(
    Stencil.StencilAxisRef(1), CMat.CMatLocalId("source_index"), i32, 1,
    CMat.CMatLoopForward) }, CMat.CMatSchedulePolicy(1, 1, CMat.CMatVectorNone)),
  {}, { CMat.CMatStreamInline(Stencil.StencilStreamRef(fold_stream_id), i32) },
  { CMat.CMatSinkInline(Stencil.StencilSinkRef(fold_sink.id)) }, schedule, {})
local fold_materialization = materialize_kernel_fragment(
  "counted_fragment_fold_kernel", fold_computation, fold_provenance)
local fold_exit = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, Code.CodeBlockId("exit"),
    C.CBackendLabel("fold_exit"), { CMat.CMatCExitArgumentControlValue }),
})
local fold_source_exit = Code.CodeBlock(
  Code.CodeBlockId("exit"), "fold_exit", {
    Code.CodeParam(
      reduction.accumulator, "fold_result", i32, origin),
  }, {},
  Code.CodeTerm(Code.CodeTermId("fold_exit_return"), Code.CodeTermReturn({}), origin),
  origin)
local fold_code_func = Code.CodeFunc(
  code_func.id, code_func.name, code_func.linkage, code_func.sig,
  code_func.params, code_func.locals, code_func.entry,
  { source_block, fold_source_exit }, code_func.origin)
local fold_request = CMat.CMatCFragmentInput(
  fold_materialization, fold_code_func, { block_id }, block_id, target,
  external_values, CMat.CMatCFragmentAccessBindingProjection({}),
  test_address_plan(fold_materialization,
    CMat.CMatCFragmentAccessBindingProjection({})), fold_exit,
  CMat.CMatCFragmentNamespace("counted_fold"), {})
local fold_fragment = fold_request:emit_cmat_fragment().fragment
local fold_result_id = C.CBackendLocalId("fold_result")
local fold_blocks = {}
for i = 1, #fold_fragment.blocks do
  fold_blocks[#fold_blocks + 1] = fold_fragment.blocks[i]
end
fold_blocks[#fold_blocks + 1] = C.CBackendBlock(
  C.CBackendLabel("fold_exit"),
  { C.CBackendBlockParam(fold_result_id, c_i32) }, {},
  C.CBackendReturn(C.CBackendAtomLocal(fold_result_id)))
local fold_sig_id = C.CBackendFuncSigId("counted_fold_sig")
local fold_sig = C.CBackendFuncSig(fold_sig_id, { c_i32, c_i32 }, c_i32)
local fold_locals = {}
for i = 1, #fold_fragment.locals do
  fold_locals[#fold_locals + 1] = fold_fragment.locals[i]
end
local fold_func = C.CBackendFunc(
  C.CBackendName("counted_fold"), "counted_fold", Core.VisibilityExport,
  fold_sig_id, { start_param, trip_param }, fold_locals,
  C.CBackendBodyBlocks(fold_fragment.entry, fold_blocks))
local fold_unit = C.CBackendUnit(
  "counted_fold", target, { fold_sig }, {}, {}, {},
  fold_fragment.helpers, { fold_func })
local fold_report = require("lalin.impl.lower_emit_c.validate").validate(fold_unit)
assert(#fold_report.issues == 0)
local fold_source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
  .emit_artifact(fold_unit, {}).source
local fold_session, fold_err = c_gcc.compile(fold_source, {
  out_dir = "target/test_cmat_counted_fragment_gcc",
  stem = "counted_fold", opt = 3,
})
assert(fold_session, fold_err and (fold_err.output or fold_err.message))
local fold_fn = assert(fold_session:symbol(
  "counted_fold", "int32_t (*)(int32_t, int32_t)"))
assert(fold_fn(1, 5) == 15)
assert(fold_fn(7, 0) == 0)
fold_session:free()

function Stencil.StencilProducerForward:test_flow_window_order()
  return Flow.FlowDomainForward
end
function Stencil.StencilProducerBackward:test_flow_window_order()
  return Flow.FlowDomainBackward
end
function Stencil.StencilProducerForward:test_cmat_window_order()
  return CMat.CMatLoopForward
end
function Stencil.StencilProducerBackward:test_cmat_window_order()
  return CMat.CMatLoopBackward
end
local function run_window(tag, boundary, expected, offset, step_magnitude,
    order, start_argument, source_values, output_slots, output_size)
  local window = Stencil.StencilWindowAxis(
    Stencil.StencilWindowExtent(
      Stencil.StencilElementDistance(1), Stencil.StencilElementDistance(1)),
    boundary)
  local window_iteration = Stencil.StencilKernelIteration(
    loop_id, index, i32, start, stop, step, step_magnitude,
    Stencil.StencilIterationStopInclusive, order,
    Stencil.StencilKernelTripExact(trip))
  local producer = Stencil.StencilProducer(
    Stencil.StencilProducerOriginFlow(domain),
    Stencil.StencilProduceCountedWindow1D(
      i32, Stencil.StencilBoundValue(Value.ValueExprValue(start)),
      Stencil.StencilBoundValue(Value.ValueExprValue(stop)), step_magnitude,
      order, Stencil.StencilIterationStopInclusive,
      Stencil.StencilKernelTripExact(trip), window))
  local window_stream_id = Stencil.StencilStreamId(tag .. ":stream")
  local window_stream = Stencil.StencilStreamDef(
    window_stream_id, i32, Stencil.StencilStreamWindowAccess(
      Stencil.StencilAccessRef(input_access.name), {
        Stencil.StencilWindowOffset(
          Stencil.StencilAxisRef(1), Stencil.StencilElementDistance(offset)),
      }))
  local window_sink = Stencil.StencilSinkDef(
    Stencil.StencilSinkId(tag .. ":sink"), Stencil.StencilSinkOpStore(
      Stencil.StencilAccessRef(output.name), Stencil.StencilIndexProducer,
      Stencil.StencilStreamRef(window_stream_id), Stencil.StencilStoreElementwise))
  local window_computation = Stencil.StencilComputation(
    Stencil.StencilComputationId(tag), producer, { input_access, output },
    { window_stream }, { window_sink }, Stencil.StencilFusionLegality({}, {}, {}),
    Stencil.StencilScheduleScalar(compiler), {})
  local source_window = Flow.FlowDomainShapeFact(
    domain, Flow.FlowDomainShapeWindowND({
      Flow.FlowDomainAxis(
        i32, Value.ValueExprValue(start), Value.ValueExprValue(stop),
        step_magnitude, order:test_flow_window_order(), nil),
    }, { Flow.FlowWindowAxis(1, 1,
      boundary == Stencil.StencilWindowBoundaryClamp and Flow.FlowWindowBoundaryClamp
        or boundary == Stencil.StencilWindowBoundaryWrap and Flow.FlowWindowBoundaryWrap
        or boundary == Stencil.StencilWindowBoundaryReject and Flow.FlowWindowBoundaryReject
        or Flow.FlowWindowBoundaryZero),
    }), {}, Flow.FlowFactCheckerDerived)
  local window_domain = Stencil.StencilKernelCountedWindow1D(source_window, window)
  local window_provenance = Stencil.StencilKernelProvenanceFacet(
    planned, window_iteration, window_domain, access_projection,
    Stencil.StencilStreamByKernelValueProjection({
      Stencil.StencilStreamByKernelValueEntry(
        load_value, binding, window_stream),
    }), Stencil.StencilKernelResultVoid)
  local window_loop = CMat.CMatLoopNest({ CMat.CMatLoopAxis(
    Stencil.StencilAxisRef(1), CMat.CMatLocalId(tag .. ":index"), i32,
    step_magnitude, order:test_cmat_window_order()),
  }, fused.loop.policy)
  local window_fused = CMat.CMatFusedKernel(
    CMat.CMatKernelId(tag), window_computation, window_loop, {}, {}, {},
    window_computation.schedule, {})
  local window_materialization = materialize_kernel_fragment(
    tag, window_computation, window_provenance)
  local request = CMat.CMatCFragmentInput(
    window_materialization, code_func, { block_id }, block_id, target,
    external_values, fragment_accesses,
    test_address_plan(window_materialization, fragment_accesses), fragment_exits,
    CMat.CMatCFragmentNamespace(tag), {})
  local emission = request:emit_cmat_fragment()
  if boundary == Stencil.StencilWindowBoundaryReject
      or offset < -window.extent.before.elements
      or offset > window.extent.after.elements
      or offset ~= math.floor(offset) then
    assert(asdl.classof(emission) == CMat.CMatCFragmentRejected)
    assert(asdl.classof(emission.issues[1]) ==
      CMat.CMatCEmissionInvalidWindow)
    return
  end
  assert(asdl.classof(emission) ==
    CMat.CMatCFragmentEmitted)
  local emitted_fragment = emission.fragment
  local blocks = {}
  for i = 1, #emitted_fragment.blocks do blocks[#blocks + 1] = emitted_fragment.blocks[i] end
  blocks[#blocks + 1] = C.CBackendBlock(
    C.CBackendLabel("exit"), {}, {}, C.CBackendReturnVoid)
  local sig = C.CBackendFuncSig(
    C.CBackendFuncSigId(tag .. "_sig"), { c_ptr, c_ptr, c_i32, c_i32 },
    C.CBackendVoid)
  local fn = C.CBackendFunc(
    C.CBackendName(tag), tag, Core.VisibilityExport, sig.id,
    { input_param, out_param, start_param, trip_param },
    emitted_fragment.locals, C.CBackendBodyBlocks(emitted_fragment.entry, blocks))
  local unit = C.CBackendUnit(
    tag, target, { sig }, {}, {}, {}, emitted_fragment.helpers, { fn })
  local validation = require("lalin.impl.lower_emit_c.validate").validate(unit)
  assert(#validation.issues == 0)
  local c_source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
  .emit_artifact(unit, {}).source
  local compiled, compile_err = c_gcc.compile(c_source, {
    out_dir = "target/test_cmat_counted_fragment_gcc", stem = tag, opt = 3,
  })
  assert(compiled, compile_err and (compile_err.output or compile_err.message))
  local c_fn = assert(compiled:symbol(
    tag, "void (*)(int32_t *, int32_t *, int32_t, int32_t)"))
  local input = ffi.new("int32_t[?]", #source_values)
  for i = 1, #source_values do input[i - 1] = source_values[i] end
  local output_values = ffi.new("int32_t[?]", output_size)
  for i = 0, output_size - 1 do output_values[i] = -1 end
  c_fn(input, output_values, start_argument, #expected)
  for i = 1, #expected do
    local slot = output_slots[i]
    assert(output_values[slot] == expected[i],
      tag .. "[" .. slot .. "]=" .. tonumber(output_values[slot]))
  end
  for i = 0, output_size - 1 do output_values[i] = -7 end
  c_fn(input, output_values, start_argument, 0)
  for i = 0, output_size - 1 do assert(output_values[i] == -7) end
  compiled:free()
end

run_window("counted_window_clamp", Stencil.StencilWindowBoundaryClamp,
  { 10, 10, 20 }, -1, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, { 0, 2, 4 }, 5)
run_window("counted_window_wrap", Stencil.StencilWindowBoundaryWrap,
  { 30, 10, 20 }, -1, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, { 0, 2, 4 }, 5)
run_window("counted_window_wrap_positive", Stencil.StencilWindowBoundaryWrap,
  { 20, 30, 10 }, 1, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, { 0, 2, 4 }, 5)
run_window("counted_window_clamp_positive", Stencil.StencilWindowBoundaryClamp,
  { 20, 30, 30 }, 1, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, { 0, 2, 4 }, 5)
run_window("counted_window_zero", Stencil.StencilWindowBoundaryZero,
  { 0, 10, 20 }, -1, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, { 0, 2, 4 }, 5)
run_window("counted_window_zero_positive", Stencil.StencilWindowBoundaryZero,
  { 20, 30, 0 }, 1, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, { 0, 2, 4 }, 5)
run_window("counted_window_reject", Stencil.StencilWindowBoundaryReject,
  {}, -1, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, {}, 5)
run_window("counted_window_extent_reject", Stencil.StencilWindowBoundaryZero,
  {}, 2, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, {}, 5)
run_window("counted_window_fraction_reject", Stencil.StencilWindowBoundaryZero,
  {}, 0.5, 1, Stencil.StencilProducerForward, 0,
  { 10, 20, 30 }, {}, 5)

run_window("counted_window_step2_clamp", Stencil.StencilWindowBoundaryClamp,
  { 10, 11, 21 }, -1, 2, Stencil.StencilProducerForward, 0,
  { 10, 11, 20, 21, 30 }, { 0, 4, 8 }, 9)
run_window("counted_window_step2_wrap", Stencil.StencilWindowBoundaryWrap,
  { 30, 11, 21 }, -1, 2, Stencil.StencilProducerForward, 0,
  { 10, 11, 20, 21, 30 }, { 0, 4, 8 }, 9)
run_window("counted_window_step2_zero", Stencil.StencilWindowBoundaryZero,
  { 0, 11, 21 }, -1, 2, Stencil.StencilProducerForward, 0,
  { 10, 11, 20, 21, 30 }, { 0, 4, 8 }, 9)
run_window("counted_window_backward_clamp", Stencil.StencilWindowBoundaryClamp,
  { 21, 11, 10 }, -1, 2, Stencil.StencilProducerBackward, 4,
  { 10, 11, 20, 21, 30 }, { 8, 4, 0 }, 9)
run_window("counted_window_backward_wrap", Stencil.StencilWindowBoundaryWrap,
  { 21, 11, 30 }, -1, 2, Stencil.StencilProducerBackward, 4,
  { 10, 11, 20, 21, 30 }, { 8, 4, 0 }, 9)
run_window("counted_window_backward_zero", Stencil.StencilWindowBoundaryZero,
  { 21, 11, 0 }, -1, 2, Stencil.StencilProducerBackward, 4,
  { 10, 11, 20, 21, 30 }, { 8, 4, 0 }, 9)

local function compile_bool_control(tag, sink_op, result, result_provenance)
  local control_stream_id = Stencil.StencilStreamId(tag .. ":stream")
  local control_binding = Kernel.KernelBinding(
    Kernel.KernelValueId(tag .. ":value"), i32,
    Kernel.KernelExprValue(index))
  local control_stream = Stencil.StencilStreamDef(
    control_stream_id, i32,
    Stencil.StencilStreamValueExpr(Value.ValueExprValue(index), i32))
  local sink = Stencil.StencilSinkDef(
    Stencil.StencilSinkId(tag .. ":sink"), sink_op(control_stream_id))
  local computation = Stencil.StencilComputation(
    Stencil.StencilComputationId(tag), producer, {}, { control_stream }, { sink },
    Stencil.StencilFusionLegality({}, {}, {}),
    Stencil.StencilScheduleScalar(compiler), {})
  local control_body = Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(index, control_binding),
    }), Kernel.KernelEffectProjection({}), result, planned.body.equivalence)
  local control_planned = Kernel.KernelPlanned(
    Kernel.KernelId(tag), planned.subject, control_body)
  local control_provenance = Stencil.StencilKernelProvenanceFacet(
    control_planned, iteration, domain_provenance,
    Stencil.StencilAccessByKernelLaneProjection({}),
    Stencil.StencilStreamByKernelValueProjection({
      Stencil.StencilStreamByKernelValueEntry(
        index, control_binding, control_stream),
    }), result_provenance(sink.id, control_stream_id))
  local materialization = materialize_kernel_fragment(
    tag, computation, control_provenance)
  local success_id = result.success
  local failure_id = result.failure
  local semantic_func = Code.CodeFunc(
    code_func.id, code_func.name, code_func.linkage, code_func.sig,
    code_func.params, code_func.locals, code_func.entry, {
      source_block,
      Code.CodeBlock(success_id, tag .. "_success", {}, {}, source_block.term, origin),
      Code.CodeBlock(failure_id, tag .. "_failure", {}, {}, source_block.term, origin),
    }, code_func.origin)
  local exits = CMat.CMatCExitBindingProjection({
    CMat.CMatCExitBindingEntry(
      CMat.CMatCExitSuccess, success_id, C.CBackendLabel(tag .. "_success"), {}),
    CMat.CMatCExitBindingEntry(
      CMat.CMatCExitFailure, failure_id, C.CBackendLabel(tag .. "_failure"), {}),
  })
  local bad_computation = Stencil.StencilComputation(
    computation.id, computation.producer, computation.accesses, computation.streams, {},
    computation.legality, computation.schedule, computation.proofs)
  local bad_materialization = materialize_kernel_fragment(
    tag .. ":bad", bad_computation, control_provenance)
  local bad_relation = CMat.CMatCFragmentInput(
    bad_materialization, semantic_func, { block_id }, block_id, target,
    external_values, CMat.CMatCFragmentAccessBindingProjection({}),
    test_address_plan(bad_materialization,
      CMat.CMatCFragmentAccessBindingProjection({})), exits,
    CMat.CMatCFragmentNamespace(tag .. "_bad"), {}):emit_cmat_fragment()
  assert(asdl.classof(bad_relation) == CMat.CMatCFragmentRejected)
  local bypassed_plan = CMat.CMatMaterializedKernelFragment(
    CMat.CMatFusedKernel(CMat.CMatKernelId(tag .. ":bypassed"), computation,
      fused.loop, {}, {}, {}, computation.schedule, {}), control_provenance)
  local bypassed = CMat.CMatCFragmentInput(
    bypassed_plan, semantic_func, { block_id }, block_id, target,
    external_values, CMat.CMatCFragmentAccessBindingProjection({}),
    test_address_plan(bypassed_plan,
      CMat.CMatCFragmentAccessBindingProjection({})), exits,
    CMat.CMatCFragmentNamespace(tag .. "_bypassed"), {})
:emit_cmat_fragment()
  assert(asdl.classof(bypassed) == CMat.CMatCFragmentRejected)
  local collision = CMat.CMatCFragmentInput(
    materialization, semantic_func, { block_id }, block_id, target,
    external_values, CMat.CMatCFragmentAccessBindingProjection({}),
    test_address_plan(materialization,
      CMat.CMatCFragmentAccessBindingProjection({})), exits,
    CMat.CMatCFragmentNamespace(tag), { C.CBackendLabel(tag .. "_entry") })
:emit_cmat_fragment()
  assert(asdl.classof(collision) == CMat.CMatCFragmentRejected)
  local emission = CMat.CMatCFragmentInput(
    materialization, semantic_func, { block_id }, block_id, target,
    external_values, CMat.CMatCFragmentAccessBindingProjection({}),
    test_address_plan(materialization,
      CMat.CMatCFragmentAccessBindingProjection({})), exits,
    CMat.CMatCFragmentNamespace(tag), {}):emit_cmat_fragment()
  assert(asdl.classof(emission) == CMat.CMatCFragmentEmitted)
  local fragment = emission.fragment
  local blocks = {}
  for i = 1, #fragment.blocks do blocks[#blocks + 1] = fragment.blocks[i] end
  blocks[#blocks + 1] = C.CBackendBlock(
    C.CBackendLabel(tag .. "_success"), {}, {},
    C.CBackendReturn(C.CBackendAtomLiteral(c_i32, Core.LitInt("1"))))
  blocks[#blocks + 1] = C.CBackendBlock(
    C.CBackendLabel(tag .. "_failure"), {}, {},
    C.CBackendReturn(C.CBackendAtomLiteral(c_i32, Core.LitInt("0"))))
  local sig = C.CBackendFuncSig(
    C.CBackendFuncSigId(tag .. "_sig"), { c_i32, c_i32 }, c_i32)
  local fn = C.CBackendFunc(
    C.CBackendName(tag), tag, Core.VisibilityExport, sig.id,
    { start_param, trip_param }, fragment.locals,
    C.CBackendBodyBlocks(fragment.entry, blocks))
  local unit = C.CBackendUnit(
    tag, target, { sig }, {}, {}, {}, fragment.helpers, { fn })
  local validation = require("lalin.impl.lower_emit_c.validate").validate(unit)
  assert(#validation.issues == 0)
  local c_source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
    .emit_artifact(unit, {}).source
  local compiled, compile_err = c_gcc.compile(c_source, {
    out_dir = "target/test_cmat_counted_fragment_gcc", stem = tag, opt = 3,
  })
  assert(compiled, compile_err and (compile_err.output or compile_err.message))
  return assert(compiled:symbol(tag, "int32_t (*)(int32_t, int32_t)")), compiled
end

local all_success_id = Code.CodeBlockId("control_all_success")
local all_failure_id = Code.CodeBlockId("control_all_failure")
local all_result = Kernel.KernelResultAll(
  Kernel.KernelExprValue(index), index, Stencil.StencilPredNonZero,
  all_success_id, all_failure_id)
local all_fn, all_session = compile_bool_control(
  "counted_control_all",
  function(stream) return Stencil.StencilSinkOpAll(
    Stencil.StencilStreamRef(stream), Stencil.StencilPredNonZero) end,
  all_result,
  function(sink, stream) return Stencil.StencilKernelResultAll(
    sink, Stencil.StencilStreamRef(stream), index, Stencil.StencilPredNonZero,
    all_success_id, all_failure_id) end)
assert(all_fn(1, 3) == 1)
assert(all_fn(0, 3) == 0)
assert(all_fn(0, 0) == 1)
all_session:free()

local any_success_id = Code.CodeBlockId("control_any_success")
local any_failure_id = Code.CodeBlockId("control_any_failure")
local any_result = Kernel.KernelResultAny(
  Kernel.KernelExprValue(index), index, Stencil.StencilPredNonZero,
  any_success_id, any_failure_id)
local any_fn, any_session = compile_bool_control(
  "counted_control_any",
  function(stream) return Stencil.StencilSinkOpAny(
    Stencil.StencilStreamRef(stream), Stencil.StencilPredNonZero) end,
  any_result,
  function(sink, stream) return Stencil.StencilKernelResultAny(
    sink, Stencil.StencilStreamRef(stream), index, Stencil.StencilPredNonZero,
    any_success_id, any_failure_id) end)
assert(any_fn(0, 1) == 0)
assert(any_fn(0, 3) == 1)
assert(any_fn(4, 0) == 0)
any_session:free()

local compare_tag = "counted_control_all_compare"
local compare_left_value = index
local compare_right_value = Code.CodeValueId(compare_tag .. ":right")
local compare_right_expr = Value.ValueExprConst(
  Code.CodeConstLiteral(i32, Core.LitInt("2")))
local compare_left_stream = Stencil.StencilStreamDef(
  Stencil.StencilStreamId(compare_tag .. ":left"), i32,
  Stencil.StencilStreamValueExpr(Value.ValueExprValue(index), i32))
local compare_right_stream = Stencil.StencilStreamDef(
  Stencil.StencilStreamId(compare_tag .. ":right"), i32,
  Stencil.StencilStreamValueExpr(compare_right_expr, i32))
local compare_left_binding = Kernel.KernelBinding(
  Kernel.KernelValueId(compare_tag .. ":left-binding"), i32,
  Kernel.KernelExprValue(index))
local compare_right_binding = Kernel.KernelBinding(
  Kernel.KernelValueId(compare_tag .. ":right-binding"), i32,
  Kernel.KernelExprAlgebra(compare_right_expr))
local compare_success = Code.CodeBlockId(compare_tag .. ":success")
local compare_failure = Code.CodeBlockId(compare_tag .. ":failure")
local compare_result = Kernel.KernelResultAllCompare(
  Kernel.KernelExprValue(index), compare_left_value,
  Kernel.KernelExprAlgebra(compare_right_expr), compare_right_value,
  Core.CmpLt, compare_success, compare_failure)
local compare_sink_id = Stencil.StencilSinkId(compare_tag .. ":sink")
local compare_sink = Stencil.StencilSinkDef(compare_sink_id,
  Stencil.StencilSinkOpAllCompare(
    Stencil.StencilStreamRef(compare_left_stream.id),
    Stencil.StencilStreamRef(compare_right_stream.id), Core.CmpLt))
local compare_computation = Stencil.StencilComputation(
  Stencil.StencilComputationId(compare_tag), producer, {},
  { compare_left_stream, compare_right_stream }, { compare_sink },
  Stencil.StencilFusionLegality({}, {}, {}),
  Stencil.StencilScheduleScalar(compiler), {})
local compare_planned = Kernel.KernelPlanned(
  Kernel.KernelId(compare_tag), planned.subject, Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(compare_left_value, compare_left_binding),
      Kernel.KernelBindingByCodeValueEntry(compare_right_value, compare_right_binding),
    }), Kernel.KernelEffectProjection({}), compare_result, planned.body.equivalence))
local compare_provenance = Stencil.StencilKernelProvenanceFacet(
  compare_planned, iteration, domain_provenance,
  Stencil.StencilAccessByKernelLaneProjection({}),
  Stencil.StencilStreamByKernelValueProjection({
    Stencil.StencilStreamByKernelValueEntry(
      compare_left_value, compare_left_binding, compare_left_stream),
    Stencil.StencilStreamByKernelValueEntry(
      compare_right_value, compare_right_binding, compare_right_stream),
  }), Stencil.StencilKernelResultAllCompare(
    compare_sink_id, Stencil.StencilStreamRef(compare_left_stream.id),
    compare_left_value, Stencil.StencilStreamRef(compare_right_stream.id),
    compare_right_value, Core.CmpLt, compare_success, compare_failure))
local compare_materialization = materialize_kernel_fragment(
  compare_tag, compare_computation, compare_provenance)
local compare_func = Code.CodeFunc(
  code_func.id, code_func.name, code_func.linkage, code_func.sig,
  code_func.params, code_func.locals, code_func.entry, {
    source_block,
    Code.CodeBlock(compare_success, "compare_success", {}, {}, source_block.term, origin),
    Code.CodeBlock(compare_failure, "compare_failure", {}, {}, source_block.term, origin),
  }, code_func.origin)
local compare_exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(CMat.CMatCExitSuccess, compare_success,
    C.CBackendLabel(compare_tag .. "_success"), {}),
  CMat.CMatCExitBindingEntry(CMat.CMatCExitFailure, compare_failure,
    C.CBackendLabel(compare_tag .. "_failure"), {}),
})
local compare_emission = CMat.CMatCFragmentInput(
  compare_materialization, compare_func, { block_id }, block_id, target,
  external_values, CMat.CMatCFragmentAccessBindingProjection({}),
  test_address_plan(compare_materialization,
    CMat.CMatCFragmentAccessBindingProjection({})), compare_exits,
  CMat.CMatCFragmentNamespace(compare_tag), {}):emit_cmat_fragment()
assert(asdl.classof(compare_emission) == CMat.CMatCFragmentEmitted)
local compare_fragment = compare_emission.fragment
local compare_blocks = {}
for i = 1, #compare_fragment.blocks do
  compare_blocks[#compare_blocks + 1] = compare_fragment.blocks[i]
end
compare_blocks[#compare_blocks + 1] = C.CBackendBlock(
  C.CBackendLabel(compare_tag .. "_success"), {}, {},
  C.CBackendReturn(C.CBackendAtomLiteral(c_i32, Core.LitInt("1"))))
compare_blocks[#compare_blocks + 1] = C.CBackendBlock(
  C.CBackendLabel(compare_tag .. "_failure"), {}, {},
  C.CBackendReturn(C.CBackendAtomLiteral(c_i32, Core.LitInt("0"))))
local compare_sig = C.CBackendFuncSig(
  C.CBackendFuncSigId(compare_tag .. "_sig"), { c_i32, c_i32 }, c_i32)
local compare_c_func = C.CBackendFunc(
  C.CBackendName(compare_tag), compare_tag, Core.VisibilityExport, compare_sig.id,
  { start_param, trip_param }, compare_fragment.locals,
  C.CBackendBodyBlocks(compare_fragment.entry, compare_blocks))
local compare_unit = C.CBackendUnit(
  compare_tag, target, { compare_sig }, {}, {}, {},
  compare_fragment.helpers, { compare_c_func })
assert(#require("lalin.impl.lower_emit_c.validate").validate(compare_unit).issues == 0)
local compare_source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
.emit_artifact(compare_unit, {}).source
local compare_session, compare_err = c_gcc.compile(compare_source, {
  out_dir = "target/test_cmat_counted_fragment_gcc", stem = compare_tag, opt = 3,
})
assert(compare_session, compare_err and (compare_err.output or compare_err.message))
local compare_fn = assert(compare_session:symbol(
  compare_tag, "int32_t (*)(int32_t, int32_t)"))
assert(compare_fn(0, 2) == 1)
assert(compare_fn(1, 2) == 0)
assert(compare_fn(4, 0) == 1)
compare_session:free()

local find_tag = "counted_control_find"
local find_stream_id = Stencil.StencilStreamId(find_tag .. ":stream")
local find_sink_id = Stencil.StencilSinkId(find_tag .. ":sink")
local find_found_id = Code.CodeBlockId("control_find_found")
local find_not_found_id = Code.CodeBlockId("control_find_not_found")
local find_pred = Stencil.StencilPredCompareConst(
  Core.CmpEq, i32,
  Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("2"))))
local find_sentinel = Value.ValueExprConst(
  Code.CodeConstLiteral(i32, Core.LitInt("-1")))
local find_result = Kernel.KernelResultFind(
  Kernel.KernelExprValue(index), index, find_pred, index,
  find_found_id, find_not_found_id, find_sentinel)
local find_binding = Kernel.KernelBinding(
  Kernel.KernelValueId(find_tag .. ":value"), i32, Kernel.KernelExprValue(index))
local find_stream = Stencil.StencilStreamDef(
  find_stream_id, i32,
  Stencil.StencilStreamValueExpr(Value.ValueExprValue(index), i32))
local find_sink = Stencil.StencilSinkDef(find_sink_id, Stencil.StencilSinkOpFind(
  Stencil.StencilStreamRef(find_stream_id), find_pred, find_sentinel))
local find_computation = Stencil.StencilComputation(
  Stencil.StencilComputationId(find_tag), producer, {}, { find_stream }, { find_sink },
  Stencil.StencilFusionLegality({}, {}, {}),
  Stencil.StencilScheduleScalar(compiler), {})
local find_planned = Kernel.KernelPlanned(
  Kernel.KernelId(find_tag), planned.subject, Kernel.KernelBody(
    planned.body.domain, planned.body.lanes, Kernel.KernelBindingProjection({
      Kernel.KernelBindingByCodeValueEntry(index, find_binding),
    }), Kernel.KernelEffectProjection({}), find_result, planned.body.equivalence))
local find_provenance = Stencil.StencilKernelProvenanceFacet(
  find_planned, iteration, domain_provenance,
  Stencil.StencilAccessByKernelLaneProjection({}),
  Stencil.StencilStreamByKernelValueProjection({
    Stencil.StencilStreamByKernelValueEntry(index, find_binding, find_stream),
  }), Stencil.StencilKernelResultFind(
    find_sink_id, Stencil.StencilStreamRef(find_stream_id), index, find_pred, index,
    find_found_id, find_not_found_id, find_sentinel))
local find_materialization = materialize_kernel_fragment(
  find_tag, find_computation, find_provenance)
local found_code_value = Code.CodeValueId("find_found_result")
local not_found_code_value = Code.CodeValueId("find_not_found_result")
local find_code_func = Code.CodeFunc(
  code_func.id, code_func.name, code_func.linkage, code_func.sig,
  code_func.params, code_func.locals, code_func.entry, {
    source_block,
    Code.CodeBlock(find_found_id, "find_found", {
      Code.CodeParam(found_code_value, "found", i32, origin),
    }, {}, source_block.term, origin),
    Code.CodeBlock(find_not_found_id, "find_not_found", {
      Code.CodeParam(not_found_code_value, "not_found", i32, origin),
    }, {}, source_block.term, origin),
  }, code_func.origin)
local find_exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitFound, find_found_id, C.CBackendLabel("find_found"), {
      CMat.CMatCExitArgumentControlValue,
    }),
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNotFound, find_not_found_id, C.CBackendLabel("find_not_found"), {
      CMat.CMatCExitArgumentControlValue,
    }),
})
local find_emission = CMat.CMatCFragmentInput(
  find_materialization, find_code_func, { block_id }, block_id, target,
  external_values, CMat.CMatCFragmentAccessBindingProjection({}),
  test_address_plan(find_materialization,
    CMat.CMatCFragmentAccessBindingProjection({})), find_exits,
  CMat.CMatCFragmentNamespace(find_tag), {}):emit_cmat_fragment()
assert(asdl.classof(find_emission) == CMat.CMatCFragmentEmitted)
local bad_find_func = Code.CodeFunc(
  find_code_func.id, find_code_func.name, find_code_func.linkage, find_code_func.sig,
  find_code_func.params, find_code_func.locals, find_code_func.entry, {
    source_block,
    Code.CodeBlock(find_found_id, "find_found", {
      Code.CodeParam(found_code_value, "found", i32, origin),
      Code.CodeParam(Code.CodeValueId("unexpected_found_arg"),
        "unexpected", i32, origin),
    }, {}, source_block.term, origin),
    find_code_func.blocks[3],
  }, find_code_func.origin)
local bad_find_exit = CMat.CMatCFragmentInput(
  find_materialization, bad_find_func, { block_id }, block_id, target,
  external_values, CMat.CMatCFragmentAccessBindingProjection({}),
  test_address_plan(find_materialization,
    CMat.CMatCFragmentAccessBindingProjection({})), find_exits,
  CMat.CMatCFragmentNamespace(find_tag .. "_bad_exit"), {})
:emit_cmat_fragment()
assert(asdl.classof(bad_find_exit) == CMat.CMatCFragmentRejected)
assert(asdl.classof(bad_find_exit.issues[1]) == CMat.CMatCEmissionInvalidExit)
local find_fragment = find_emission.fragment
local find_blocks = {}
for i = 1, #find_fragment.blocks do find_blocks[#find_blocks + 1] = find_fragment.blocks[i] end
local found_local = C.CBackendLocalId("find_found_value")
local not_found_local = C.CBackendLocalId("find_not_found_value")
find_blocks[#find_blocks + 1] = C.CBackendBlock(
  C.CBackendLabel("find_found"), { C.CBackendBlockParam(found_local, c_i32) }, {},
  C.CBackendReturn(C.CBackendAtomLocal(found_local)))
find_blocks[#find_blocks + 1] = C.CBackendBlock(
  C.CBackendLabel("find_not_found"), {
    C.CBackendBlockParam(not_found_local, c_i32),
  }, {}, C.CBackendReturn(C.CBackendAtomLocal(not_found_local)))
local find_sig = C.CBackendFuncSig(
  C.CBackendFuncSigId(find_tag .. "_sig"), { c_i32, c_i32 }, c_i32)
local find_func = C.CBackendFunc(
  C.CBackendName(find_tag), find_tag, Core.VisibilityExport, find_sig.id,
  { start_param, trip_param }, find_fragment.locals,
  C.CBackendBodyBlocks(find_fragment.entry, find_blocks))
local find_unit = C.CBackendUnit(
  find_tag, target, { find_sig }, {}, {}, {}, find_fragment.helpers, { find_func })
local find_validation = require("lalin.impl.lower_emit_c.validate").validate(find_unit)
assert(#find_validation.issues == 0)
local find_source = require("lalin.emit_c_lower")(require("lalin.schema_v2"))
  .emit_artifact(find_unit, {}).source
local find_session, find_err = c_gcc.compile(find_source, {
  out_dir = "target/test_cmat_counted_fragment_gcc", stem = find_tag, opt = 3,
})
assert(find_session, find_err and (find_err.output or find_err.message))
local find_fn = assert(find_session:symbol(
  find_tag, "int32_t (*)(int32_t, int32_t)"))
assert(find_fn(0, 4) == 2)
assert(find_fn(3, 2) == -1)
assert(find_fn(0, 0) == -1)
find_session:free()

io.write("test_cmat_counted_fragment_gcc: ok\n")
