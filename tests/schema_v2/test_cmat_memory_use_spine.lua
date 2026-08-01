package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c.materialize")

local Code = require("lalin.schema_v2.code")
local Value = require("lalin.schema_v2.value")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local axis = Stencil.StencilAxisRef(1)
local input = Stencil.StencilAccess(
  "xs", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local output = Stencil.StencilAccess(
  "out", Stencil.StencilAccessWrite, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local centered_id = Stencil.StencilStreamId("centered")
local window_id = Stencil.StencilStreamId("window")
local const_id = Stencil.StencilStreamId("constant")
local point_window_id = Stencil.StencilStreamId("point-window")
local gather_id = Stencil.StencilStreamId("gather")
local sink_id = Stencil.StencilSinkId("store")
local minus_one = Stencil.StencilWindowOffset(
  axis, Stencil.StencilElementDistance(-1))
local plus_one = Stencil.StencilWindowOffset(
  axis, Stencil.StencilElementDistance(1))
local centered = Stencil.StencilStreamDef(
  centered_id, i32, Stencil.StencilStreamAccess(
    Stencil.StencilAccessRef("xs"), Stencil.StencilIndexProducer))
local window = Stencil.StencilStreamDef(
  window_id, i32, Stencil.StencilStreamWindowAccess(
    Stencil.StencilAccessRef("xs"), { minus_one, minus_one, plus_one }))
local constant = Stencil.StencilStreamDef(
  const_id, i32, Stencil.StencilStreamConst(
    require("lalin.schema_v2.value").ValueExprValue(
      Code.CodeValueId("constant")), i32))
local point_window = Stencil.StencilStreamDef(
  point_window_id, i32, Stencil.StencilStreamMap(
    Stencil.StencilPointWindowInput(
      Stencil.StencilAccessRef("xs"), { minus_one, plus_one }), {}))
local gather = Stencil.StencilStreamDef(
  gather_id, i32, Stencil.StencilStreamGather(
    Stencil.StencilAccessRef("xs"), Stencil.StencilStreamRef(centered_id)))
local store = Stencil.StencilSinkDef(
  sink_id, Stencil.StencilSinkOpStore(
    Stencil.StencilAccessRef("out"), Stencil.StencilIndexProducer,
    Stencil.StencilStreamRef(centered_id), Stencil.StencilStoreElementwise))
local compiler = Stencil.StencilCompilerPolicy(
  Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("memory-use-spine"),
  Stencil.StencilProducer(
    Stencil.StencilProducerOriginNone,
    Stencil.StencilProduceRange1D(
      i32, Stencil.StencilBoundDynamic, Stencil.StencilBoundDynamic, 1,
      Stencil.StencilProducerForward)),
  { input, output },
  { centered, window, constant, point_window, gather }, { store },
  Stencil.StencilFusionLegality({}, {}, {}),
  Stencil.StencilScheduleScalar(compiler), {})

local spine = computation:cmat_memory_use_spine()
assert(#spine.uses == 8)

local center_use = spine.uses[1]
assert(asdl.classof(center_use.id) == CMat.CMatStreamMemoryUse)
assert(center_use.id.stream == Stencil.StencilStreamRef(centered_id))
assert(center_use.access == Stencil.StencilAccessRef("xs"))
assert(center_use.role == CMat.CMatMemoryLoad)
assert(asdl.classof(center_use.index) == CMat.CMatMemorySelectedIndex)
assert(center_use.index.selection == Stencil.StencilIndexProducer)

for ordinal = 1, 3 do
  local use = spine.uses[ordinal + 1]
  assert(asdl.classof(use.id) == CMat.CMatWindowMemoryUse)
  assert(use.id.stream == Stencil.StencilStreamRef(window_id))
  assert(use.id.ordinal == ordinal)
  assert(use.access == center_use.access)
  assert(use.role == CMat.CMatMemoryLoad)
  assert(asdl.classof(use.index) == CMat.CMatMemoryWindowOffset)
end
assert(spine.uses[2].index.offset == minus_one)
assert(spine.uses[3].index.offset == minus_one)
assert(spine.uses[2].id ~= spine.uses[3].id,
  "duplicate window offsets require distinct occurrence identities")
assert(spine.uses[4].index.offset == plus_one)

local point_window_first = spine.uses[5]
local point_window_second = spine.uses[6]
assert(asdl.classof(point_window_first.id) == CMat.CMatWindowMemoryUse)
assert(point_window_first.id.stream ==
  Stencil.StencilStreamRef(point_window_id))
assert(point_window_first.id.ordinal == 1)
assert(point_window_first.index.offset == minus_one)
assert(point_window_second.id.ordinal == 2)
assert(point_window_second.index.offset == plus_one)

local gather_use = spine.uses[7]
assert(asdl.classof(gather_use.id) == CMat.CMatStreamMemoryUse)
assert(gather_use.id.stream == Stencil.StencilStreamRef(gather_id))
assert(gather_use.access == Stencil.StencilAccessRef("xs"))
assert(asdl.classof(gather_use.index) == CMat.CMatMemorySelectedIndex)
assert(asdl.classof(gather_use.index.selection) ==
  Stencil.StencilIndexExplicit)
assert(asdl.classof(gather_use.index.selection.index) ==
  Stencil.StencilIndexStream)
assert(gather_use.index.selection.index.stream ==
  Stencil.StencilStreamRef(centered_id))

local store_use = spine.uses[8]
assert(asdl.classof(store_use.id) == CMat.CMatSinkMemoryUse)
assert(store_use.id.sink == Stencil.StencilSinkRef(sink_id))
assert(store_use.access == Stencil.StencilAccessRef("out"))
assert(store_use.role == CMat.CMatMemoryStore)
assert(asdl.classof(store_use.index) == CMat.CMatMemorySelectedIndex)
assert(store_use.index.selection == Stencil.StencilIndexProducer)

local reducer = Stencil.StencilReducer(
  Value.ReductionAdd, i32, Value.ValueExprValue(Code.CodeValueId("identity")),
  Stencil.StencilArithmeticInferred)
local function one_sink_use(id, op)
  local definition = Stencil.StencilSinkDef(Stencil.StencilSinkId(id), op)
  local contribution = op:cmat_memory_uses(definition)
  assert(#contribution.uses == 1)
  return contribution.uses[1]
end

local scan_use = one_sink_use("scan", Stencil.StencilSinkOpScan(
  Stencil.StencilAccessRef("out"), Stencil.StencilStreamRef(centered_id),
  reducer, Stencil.StencilScanInclusive, axis))
assert(asdl.classof(scan_use.index.selection.index) ==
  Stencil.StencilIndexAxis)
assert(scan_use.index.selection.index.axis == axis)

local scatter_use = one_sink_use(
  "scatter", Stencil.StencilSinkOpScatterStore(
    Stencil.StencilAccessRef("out"), Stencil.StencilStreamRef(centered_id),
    Stencil.StencilStreamRef(point_window_id),
    Stencil.StencilScatterUniqueIndices))
assert(asdl.classof(scatter_use.index.selection.index) ==
  Stencil.StencilIndexStream)
assert(scatter_use.index.selection.index.stream ==
  Stencil.StencilStreamRef(centered_id))

local fold_use = one_sink_use("fold-store", Stencil.StencilSinkOpFold(
  Stencil.StencilStreamRef(centered_id), reducer, i32,
  Stencil.StencilReduceInitIdentity,
  Stencil.StencilFoldStores(
    Stencil.StencilAccessRef("out"), Stencil.StencilIndexProducer)))
assert(fold_use.access == Stencil.StencilAccessRef("out"))
assert(fold_use.index.selection == Stencil.StencilIndexProducer)

local materialized = computation:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("memory-use-spine")))
local materialized_spine = materialized.kernel:cmat_memory_use_spine()
assert(#materialized_spine.uses == #spine.uses)
assert(materialized.kernel.computation.sinks[1].op.index ==
  Stencil.StencilIndexProducer)

io.write("test_cmat_memory_use_spine: ok\n")
