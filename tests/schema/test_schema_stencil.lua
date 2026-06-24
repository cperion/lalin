package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local pvm = require("moonlift.pvm")
local Schema = require("moonlift.schema")

local T = pvm.context()
Schema(T)

local Core = T.MoonCore
local Code = T.MoonCode
local Flow = T.MoonFlow
local Graph = T.MoonGraph
local Value = T.MoonValue
local Kernel = T.MoonKernel
local Stencil = T.MoonStencil

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local loop = Graph.GraphLoopId("loop:sum")
local domain = Flow.FlowDomainLoop(loop)
local init = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
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
local instance = Stencil.StencilInstance(
    Stencil.StencilInstanceId("stencil:reduce_array:i32:add"),
    Stencil.StencilReduceArray,
    Stencil.StencilShapeReduceArray(i32, i32, Value.ReductionAdd, sem, nil, init, 1),
    {
        Stencil.StencilParamType("elem_ty", i32),
        Stencil.StencilParamReduction("reduction", Value.ReductionAdd),
        Stencil.StencilParamNumber("stride", 1),
    },
    Stencil.StencilAbi({ Code.CodeTyDataPtr(i32), i32, i32, i32 }, i32),
    { proof }
)
local artifact = Stencil.StencilArtifact(
    instance,
    Stencil.StencilProviderC,
    Stencil.StencilSymbolId("ml_stencil_reduce_array_i32_add_s1"),
    "int32_t ml_stencil_reduce_array_i32_add_s1(const int32_t *, int32_t, int32_t, int32_t);"
)

assert(instance.vocab == Stencil.StencilReduceArray)
assert(pvm.classof(instance.shape) == Stencil.StencilShapeReduceArray)
assert(artifact.provider == Stencil.StencilProviderC)
assert(artifact.instance == instance)

local map_shape = Stencil.StencilShapeMapArray(i32, i32, Stencil.StencilUnaryNeg, 1)
local zip_shape = Stencil.StencilShapeZipMapArray(i32, i32, i32, Stencil.StencilBinaryAdd, 1)
local scan_shape = Stencil.StencilShapeScanArray(i32, i32, Value.ReductionAdd, sem, nil, init, Stencil.StencilScanInclusive, 1)
local copy_shape = Stencil.StencilShapeCopyArray(i32, Stencil.StencilCopyNoOverlap, 1)
local fill_shape = Stencil.StencilShapeFillArray(i32, init, 1)
local pred = Stencil.StencilPredEqConst(init)
local find_shape = Stencil.StencilShapeFindArray(i32, pred, 1)
local partition_shape = Stencil.StencilShapePartitionArray(i32, Stencil.StencilPredNonZero, Stencil.StencilPartitionStable, 1)
local cast_shape = Stencil.StencilShapeCastArray(i32, Code.CodeTyFloat(64), Core.MachineCastSToF, 1)
local compare_shape = Stencil.StencilShapeCompareArray(i32, Code.CodeTyBool8, pred, 1)
local zip_compare_shape = Stencil.StencilShapeZipCompareArray(i32, i32, Code.CodeTyBool8, Core.CmpLt, 1)
local gather_shape = Stencil.StencilShapeGatherArray(i32, i32, 1)
local scatter_shape = Stencil.StencilShapeScatterArray(i32, i32, Stencil.StencilScatterUniqueIndices, 1)
local in_place_shape = Stencil.StencilShapeInPlaceMapArray(i32, Stencil.StencilUnaryNeg, 1)
local count_shape = Stencil.StencilShapeCountArray(i32, pred, 1)
local map_reduce_shape = Stencil.StencilShapeMapReduceArray(i32, i32, i32, Stencil.StencilUnaryNeg, Value.ReductionAdd, sem, nil, init, 1)
local zip_reduce_shape = Stencil.StencilShapeZipReduceArray(i32, i32, i32, i32, Stencil.StencilBinaryAdd, Value.ReductionAdd, sem, nil, init, 1)

assert(map_shape.op == Stencil.StencilUnaryNeg)
assert(zip_shape.op == Stencil.StencilBinaryAdd)
assert(pvm.classof(scan_shape) == Stencil.StencilShapeScanArray)
assert(pvm.classof(copy_shape) == Stencil.StencilShapeCopyArray)
assert(pvm.classof(fill_shape) == Stencil.StencilShapeFillArray)
assert(pvm.classof(find_shape.pred) == Stencil.StencilPredEqConst)
assert(partition_shape.pred == Stencil.StencilPredNonZero)
assert(cast_shape.op == Core.MachineCastSToF)
assert(compare_shape.result_ty == Code.CodeTyBool8)
assert(zip_compare_shape.cmp == Core.CmpLt)
assert(pvm.classof(gather_shape) == Stencil.StencilShapeGatherArray)
assert(scatter_shape.conflicts == Stencil.StencilScatterUniqueIndices)
assert(in_place_shape.op == Stencil.StencilUnaryNeg)
assert(pvm.classof(count_shape.pred) == Stencil.StencilPredEqConst)
assert(map_reduce_shape.reduction == Value.ReductionAdd)
assert(zip_reduce_shape.op == Stencil.StencilBinaryAdd)

io.write("moonlift schema_stencil ok\n")
