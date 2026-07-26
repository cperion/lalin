package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
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
    Stencil.StencilAccessRef("out"), Stencil.StencilStreamRef(alias_stream_id),
    Stencil.StencilStoreElementwise))
local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3,
  Stencil.StencilMachineNative, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local computation = Stencil.StencilComputation(
  Stencil.StencilMetastencilId("counted_fragment"), producer,
  { input_access, output }, { stream, plus_stream, alias_stream }, { sink },
  Stencil.StencilFusionLegality({}, {}, {}), schedule, {})

local input_lane = Kernel.KernelLane(
  input_lane_id, Mem.MemObjectId("input_object"), { input_access_id },
  Mem.MemBaseLocal(Code.CodeLocalId("input")), i32,
  Mem.MemAccessScalar, {})
local lane = Kernel.KernelLane(
  lane_id, Mem.MemObjectId("out_object"), { access_id },
  Mem.MemBaseLocal(Code.CodeLocalId("out")), i32,
  Mem.MemAccessScalar, {})
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
local provenance = Stencil.StencilKernelProvenanceFacet(
  planned, iteration, access_projection, stream_projection, Kernel.KernelResultVoid)
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
local materialization = CMat.CMatMaterializedKernelFragment(fused, provenance)

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
    CMat.CMatCFragmentAccessDirect(input_param), 4, 4, Mem.MemAlignKnown(4)),
  CMat.CMatCFragmentAccessBindingEntry(
    Stencil.StencilAccessRef("out"), lane_id, access_id,
    CMat.CMatCFragmentAccessDirect(out_param), 4, 8, Mem.MemAlignKnown(4)),
})
local fragment_exits = CMat.CMatCExitBindingProjection({
  CMat.CMatCExitBindingEntry(
    CMat.CMatCExitNormal, Code.CodeBlockId("exit"),
    C.CBackendLabel("exit"), {}),
})
local target = C.CBackendTarget(
  C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian)
local request = CMat.CMatCFragmentInput(
  materialization, code_func, { block_id }, block_id, target,
  external_values, fragment_accesses, fragment_exits,
  CMat.CMatCFragmentNamespace("counted_fragment"))
local emitted = request:emit_cmat_fragment()
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
  Code.CodeValueId("sum_result"), Value.ReductionAdd,
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
  Stencil.StencilMetastencilId("counted_fragment_fold"), producer, {},
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
  fold_planned, iteration, Stencil.StencilAccessByKernelLaneProjection({}),
  Stencil.StencilStreamByKernelValueProjection({
    Stencil.StencilStreamByKernelValueEntry(index, fold_binding, fold_stream),
  }),
  Kernel.KernelResultReduction(reduction))
local fold_fused = CMat.CMatFusedKernel(
  CMat.CMatKernelId("counted_fragment_fold_kernel"), fold_computation,
  CMat.CMatLoopNest({ CMat.CMatLoopAxis(
    Stencil.StencilAxisRef(1), CMat.CMatLocalId("source_index"), i32, 1,
    CMat.CMatLoopForward) }, CMat.CMatSchedulePolicy(1, 1, CMat.CMatVectorNone)),
  {}, { CMat.CMatStreamInline(Stencil.StencilStreamRef(fold_stream_id), i32) },
  { CMat.CMatSinkInline(Stencil.StencilSinkRef(fold_sink.id)) }, schedule, {})
local fold_materialization = CMat.CMatMaterializedKernelFragment(
  fold_fused, fold_provenance)
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
  external_values, CMat.CMatCFragmentAccessBindingProjection({}), fold_exit,
  CMat.CMatCFragmentNamespace("counted_fold"))
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

io.write("test_cmat_counted_fragment_gcc: ok\n")
