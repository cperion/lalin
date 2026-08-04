package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.stencil_plan")
require("lalin.impl.lower_emit_c")
local Code = require("lalin.schema_v2.code")
local Core = require("lalin.schema_v2.core")
local Value = require("lalin.schema_v2.value")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")
local C = require("lalin.schema_v2.c")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local function int(raw) return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw)))) end
local compiler = Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local producer = Stencil.StencilProducer(Stencil.StencilProducerOriginNone, Stencil.StencilProduceRange1D(i32, Stencil.StencilBoundValue(int(0)), Stencil.StencilBoundValue(int(4)), 1, Stencil.StencilProducerForward))
local xs = Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32, Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local out = Stencil.StencilAccess("out", Stencil.StencilAccessWrite, i32, Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local x_id, y_id = Stencil.StencilStreamId("x"), Stencil.StencilStreamId("y")
local x = Stencil.StencilStreamDef(x_id, i32, Stencil.StencilStreamAccess(Stencil.StencilAccessRef("xs"), Stencil.StencilIndexProducer))
local expr = Stencil.StencilPointBinary(Stencil.StencilBinaryMul, Stencil.StencilPointInput(Stencil.StencilAccessRef("a")), Stencil.StencilPointConst(int(2), i32), Stencil.StencilPointResultTyped(i32, Stencil.StencilArithmeticInferred))
local y = Stencil.StencilStreamDef(y_id, i32, Stencil.StencilStreamMap(expr, { Stencil.StencilStreamParam("a", Stencil.StencilStreamRef(x_id)) }))
local sink = Stencil.StencilSinkDef(Stencil.StencilSinkId("store"), Stencil.StencilSinkOpStore(Stencil.StencilAccessRef("out"), Stencil.StencilIndexProducer, Stencil.StencilStreamRef(y_id), Stencil.StencilStoreElementwise))
local computation = Stencil.StencilComputation(Stencil.StencilComputationId("map"), producer, { xs, out }, { x, y }, { sink }, Stencil.StencilFusionLegality({}, {}, {}), schedule, {})
local materialized = computation:cmat_materialize(CMat.CMatMaterializationInput(CMat.CMatKernelId("map")))
local target = C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
local emitted = materialized:cmat_emit_c(CMat.CMatCEmissionInput("cmat_map", "cmat_map", target))
assert(asdl.classof(emitted) == CMat.CMatCEmitted)
assert(asdl.classof(emitted.unit) == C.CBackendUnit)
assert(#emitted.unit.funcs == 1 and #emitted.unit.funcs[1].body.blocks == 4)
assert(#require("lalin.impl.lower_emit_c.validate").validate(emitted.unit).issues == 0)
local source = require("tests.c_backend.cemit_source").source(emitted.unit, target)
assert(source:find("cmat_map", 1, true), "canonical CMat unit must remain source-emittable")

local explicit_sink = Stencil.StencilSinkDef(
  Stencil.StencilSinkId("explicit-store"), Stencil.StencilSinkOpStore(
    Stencil.StencilAccessRef("out"),
    Stencil.StencilIndexExplicit(Stencil.StencilIndexPoint(int(1))),
    Stencil.StencilStreamRef(y_id), Stencil.StencilStoreElementwise))
local explicit_computation = Stencil.StencilComputation(
  Stencil.StencilComputationId("explicit-store"), producer, { xs, out }, { x, y },
  { explicit_sink }, Stencil.StencilFusionLegality({}, {}, {}), schedule, {})
local explicit_rejected = explicit_computation:cmat_materialize(
  CMat.CMatMaterializationInput(CMat.CMatKernelId("explicit-store")))
:cmat_emit_c(CMat.CMatCEmissionInput(
  "explicit_store", "explicit_store", target))
assert(asdl.classof(explicit_rejected) == CMat.CMatCRejected)
assert(asdl.classof(explicit_rejected.issues[1]) ==
  CMat.CMatCEmissionUnsupportedSink)

local rejected_computation = Stencil.StencilComputation(Stencil.StencilComputationId("bad"), Stencil.StencilProducer(Stencil.StencilProducerOriginNone, Stencil.StencilProduceRangeND({})), { xs }, { x }, { sink }, Stencil.StencilFusionLegality({}, {}, {}), schedule, {})
local rejected = rejected_computation:cmat_materialize(CMat.CMatMaterializationInput(CMat.CMatKernelId("bad"))):cmat_emit_c(CMat.CMatCEmissionInput("bad", "bad", target))
assert(asdl.classof(rejected) == CMat.CMatCRejected)
assert(#rejected.issues == 1)
io.write("test_cmat_to_cbackend: ok\n")
