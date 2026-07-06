package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Graph = T.LalinGraph
local Value = T.LalinValue
local Kernel = T.LalinKernel
local Stencil = T.LalinStencil
local CMat = T.LalinCMat

local CMaterialize = require("lalin.emit_c_materialize")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local init = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local loop = Graph.GraphLoopId("loop:sum")
local domain = Flow.FlowDomainLoop(loop)
local reduction = Value.ReductionFact(
    Value.AlgebraFactId("reduction:sum"),
    domain,
    Code.CodeValueId("v:acc"),
    Value.ReductionAdd,
    init,
    Value.ValueExprValue(Code.CodeValueId("v:item")),
    i32,
    sem,
    nil,
    Value.AlgebraProofFlow(domain, "test reduction")
)
local proof = Kernel.KernelProofValue(reduction.proof, "test proof")
local compiler = Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, Stencil.StencilMachineNative, {})
local facts = Stencil.StencilVectorizationFacts(
    {},
    {},
    Stencil.StencilTripCountDynamic,
    Stencil.StencilArithmeticVectorFact(true, sem, nil),
    {}
)
local schedule = Stencil.StencilScheduleAutoVector(compiler, facts)
local producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward))

local map_stream = Stencil.StencilStreamDef(
    Stencil.StencilStreamId("mapped"),
    i32,
    Stencil.StencilStreamMap(Stencil.StencilPointInput(Stencil.StencilAccessRef("xs")), {})
)
local store_sink = Stencil.StencilSinkDef(
    Stencil.StencilSinkId("store"),
    Stencil.StencilSinkOpStore(Stencil.StencilAccessRef("dst"), Stencil.StencilStreamRef(map_stream.id), Stencil.StencilStoreElementwise)
)
local store_computation = Stencil.StencilComputation(
    Stencil.StencilMetastencilId("metastencil:map_store"),
    producer,
    {
        Stencil.StencilAccess("dst", Stencil.StencilAccessWrite, i32, Stencil.StencilLayoutContiguous(1)),
        Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32, Stencil.StencilLayoutContiguous(1)),
    },
    { map_stream },
    { store_sink },
    Stencil.StencilFusionLegality({}, {}, {}),
    schedule,
    { proof }
)

local store_mat = store_computation:cmat_materialize()
assert(asdl.classof(store_mat) == CMat.CMatMaterializedFused, "StencilComputation should be the only CMat materialization product")
assert(asdl.classof(store_mat.kernel) == CMat.CMatFusedKernel, "materialization should carry a fused CMat kernel")
assert(store_mat.kernel.computation == store_computation, "CMatFusedKernel should retain the source SOAC composition as its contract")
assert(#store_mat.kernel.loop.axes == 1, "range producer should create one CMat loop axis")
assert(store_mat.kernel.loop.axes[1].step == 1, "range stride should become loop step")
assert(asdl.classof(store_mat.kernel.loop.vector) == CMat.CMatVectorAutovec, "autovec schedule should become CMat autovec policy")
assert(#store_mat.kernel.accesses == 2, "composition accesses should become CMat access bindings")
assert(store_mat.kernel.accesses[1].mutability == CMat.CMatAccessWriteOnly, "write access should carry write mutability")
assert(store_mat.kernel.accesses[1].restrict_eligible == true, "contiguous write access should be restrict eligible when legality proves it")
assert(store_mat.kernel.accesses[2].const_eligible == true, "read access should become const eligible")
assert(store_mat.kernel.accesses[2].restrict_eligible == true, "contiguous read access should be restrict eligible when legality proves it")
assert(#store_mat.kernel.streams == 1, "fused kernel should materialize stream composition")
assert(asdl.classof(store_mat.kernel.streams[1]) == CMat.CMatStreamInline, "map stream should be inline materialized")
assert(#store_mat.kernel.sinks == 1, "fused kernel should materialize sink composition")
assert(asdl.classof(store_mat.kernel.sinks[1]) == CMat.CMatSinkInline, "store sink should be inline materialized")

local reducer = Stencil.StencilReducer(Value.ReductionAdd, i32, init, sem, nil)
local reduce_stream = Stencil.StencilStreamDef(
    Stencil.StencilStreamId("item"),
    i32,
    Stencil.StencilStreamMap(Stencil.StencilPointInput(Stencil.StencilAccessRef("xs")), {})
)
local fold_sink = Stencil.StencilSinkDef(
    Stencil.StencilSinkId("fold"),
    Stencil.StencilSinkOpFold(Stencil.StencilStreamRef(reduce_stream.id), reducer, i32, Stencil.StencilReduceInitExternal, nil)
)
local reduce_computation = Stencil.StencilComputation(
    Stencil.StencilMetastencilId("metastencil:fold"),
    producer,
    {
        Stencil.StencilAccess("xs", Stencil.StencilAccessRead, i32, Stencil.StencilLayoutContiguous(1)),
        Stencil.StencilAccess("acc", Stencil.StencilAccessReduce, i32, Stencil.StencilLayoutScalar(init)),
    },
    { reduce_stream },
    { fold_sink },
    Stencil.StencilFusionLegality({}, {}, {}),
    schedule,
    { proof }
)
local reduce_mat = reduce_computation:cmat_materialize()
assert(asdl.classof(reduce_mat) == CMat.CMatMaterializedFused, "fold also materializes as fused SOAC CMat")
assert(reduce_mat.kernel.sinks[1].sink.sink.text == "fold", "fold sink should survive as a sink materialization, not a CMatBody")
assert(reduce_mat.kernel.accesses[2].mutability == CMat.CMatAccessReduce, "reduce access should carry reduce mutability")

local module_mat = CMaterialize.materialize_computations(Code.CodeModuleId("mod:cmat:composition"), { store_computation, reduce_computation })
assert(asdl.classof(module_mat) == CMat.CMatModule, "computation list should produce a CMat module")
assert(#module_mat.kernels == 2, "CMat module should carry fused computation kernels")
for _, kernel in ipairs(module_mat.kernels) do
    assert(asdl.classof(kernel) == CMat.CMatMaterializedFused, "CMat modules must not contain legacy artifact kernels")
end
assert(CMaterialize.materialize_artifacts == nil, "artifact materialization API must not exist")
assert(CMat.CMatBodyStore == nil, "legacy CMatBodyStore constructor must not exist")
assert(CMat.CMatMaterializedKernel == nil, "legacy CMatMaterializedKernel constructor must not exist")

io.write("lalin schema_c_materialize ok\n")
