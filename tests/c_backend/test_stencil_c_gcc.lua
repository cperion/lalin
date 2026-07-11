package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")
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
local c_gcc = require("lalin.emit_c_compile")

local available, why = c_gcc.available()
if not available then io.write("test_stencil_c_gcc: skipped: " .. why.message .. "\n"); os.exit(0) end

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local function int(raw) return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(raw)))) end
local compiler = Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, Stencil.StencilMachineNative, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local target = C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
local function producer() return Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(i32, int(0), int(5), 1, Stencil.StencilProducerForward)) end
local function access(name, role) return Stencil.StencilAccess(name, role, i32, Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4))) end
local function materialize(computation, symbol)
  return computation:cmat_materialize(CMat.CMatMaterializationInput(CMat.CMatKernelId(symbol))):cmat_emit_c(CMat.CMatCEmissionInput(symbol, symbol, target))
end
local function source_for(emitted)
  assert(asdl.classof(emitted) == CMat.CMatCEmitted)
  return require("lalin.emit_c_lower")(require("lalin.schema_v2")).emit_artifact(emitted.unit, {}).source
end
local function compile(emitted, stem)
  local session, err = c_gcc.compile(source_for(emitted), { out_dir = "target/test_stencil_c_gcc", stem = stem, opt = 3 })
  assert(session, err and err.output or err and err.message)
  return session
end

local xs, out = access("xs", Stencil.StencilAccessRead), access("out", Stencil.StencilAccessWrite)
local x_id, y_id = Stencil.StencilStreamId("x"), Stencil.StencilStreamId("y")
local x = Stencil.StencilStreamDef(x_id, i32, Stencil.StencilStreamAccess(Stencil.StencilAccessRef("xs"), nil))
local map_expr = Stencil.StencilPointBinary(Stencil.StencilBinaryMul, Stencil.StencilPointInput(Stencil.StencilAccessRef("a")), Stencil.StencilPointConst(int(3), i32), i32, nil, nil)
local y = Stencil.StencilStreamDef(y_id, i32, Stencil.StencilStreamMap(map_expr, { Stencil.StencilStreamParam("a", Stencil.StencilStreamRef(x_id)) }))
local store = Stencil.StencilSinkDef(Stencil.StencilSinkId("store"), Stencil.StencilSinkOpStore(Stencil.StencilAccessRef("out"), Stencil.StencilStreamRef(y_id), Stencil.StencilStoreElementwise))
local map_computation = Stencil.StencilComputation(Stencil.StencilMetastencilId("map"), producer(), { xs, out }, { x, y }, { store }, Stencil.StencilFusionLegality({}, {}, {}), schedule, {})
local map_session = compile(materialize(map_computation, "cmat_map_store"), "cmat_map_store")
local map_fn = assert(map_session:symbol("cmat_map_store", "void (*)(int32_t *, int32_t *)"))
local input = ffi.new("int32_t[5]", { 2, -1, 4, 7, 3 })
local output = ffi.new("int32_t[5]")
map_fn(input, output)
assert(output[0] == 6 and output[1] == -3 and output[2] == 12 and output[3] == 21 and output[4] == 9)
map_session:free()

local fold = Stencil.StencilSinkDef(Stencil.StencilSinkId("fold"), Stencil.StencilSinkOpFold(
  Stencil.StencilStreamRef(x_id), Stencil.StencilReducer(Value.ReductionAdd, i32, int(0), nil, nil),
  i32, Stencil.StencilReduceInitIdentity, nil))
local fold_computation = Stencil.StencilComputation(Stencil.StencilMetastencilId("fold"), producer(), { xs }, { x }, { fold }, Stencil.StencilFusionLegality({}, {}, {}), schedule, {})
local fold_session = compile(materialize(fold_computation, "cmat_fold"), "cmat_fold")
local fold_fn = assert(fold_session:symbol("cmat_fold", "int32_t (*)(int32_t *)"))
assert(fold_fn(input) == 15)
fold_session:free()

io.write("test_stencil_c_gcc: ok\n")
