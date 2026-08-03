package.path = "tests/?.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
require("lalin.schema_v2")
local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Kernel = require("lalin.schema_v2.kernel")
require("lalin.impl.kernel_plan")

local module = Code.CodeModuleId("kernel_projection")
local a, b = Graph.GraphLoopId("loop:a"), Graph.GraphLoopId("loop:b")
local da, db = Flow.FlowDomainLoop(a), Flow.FlowDomainLoop(b)
local counted = Flow.FlowCountedDomain(
  Code.CodeValueId("start"), Code.CodeValueId("stop"),
  Code.CodeValueId("step"), Flow.FlowStopExclusive, Flow.FlowLoopIncreasing)
local induction_a = Flow.FlowInduction(
  Code.CodeValueId("i:a"), Code.CodeTyIndex, counted.start, counted.step,
  Flow.FlowPrimaryInduction, Flow.FlowRangeUnknown(Code.CodeValueId("i:a")))
local induction_b = Flow.FlowInduction(
  Code.CodeValueId("i:b"), Code.CodeTyIndex, counted.start, counted.step,
  Flow.FlowPrimaryInduction, Flow.FlowRangeUnknown(Code.CodeValueId("i:b")))
local flow = Flow.FlowFactSet(module, { da, db }, {}, {
  Flow.FlowLoopFacts(a, da, counted, {}, { induction_a }, {}, {}),
  Flow.FlowLoopFacts(b, db, counted, {}, { induction_b }, {}, {})
}, {}, {}, {}, {})
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local zero = Value.ValueExprConst(Code.CodeConstLiteral(i32, require("lalin.schema_v2.core").LitInt("0")))
local trip_a = Flow.FlowTripCountExact(Code.CodeValueId("trip:a"), nil, nil)
local trip_b = Flow.FlowTripCountNonNegative(Code.CodeValueId("trip:b"), nil, nil)
local function reduction(id, domain, trip) return Value.ReductionFact(Value.AlgebraFactId(id), domain, Code.CodeValueId("acc:" .. id), Code.CodeValueId("update:" .. id), Value.ReductionAdd, zero, zero, i32, nil, nil, Value.AlgebraProofFlow(domain, Value.AlgebraFlowCounted(trip))) end
local ra, rb = reduction("red:a", da, trip_a), reduction("red:b", db, trip_b)
local cfa = Value.ClosedFormFact(Value.AlgebraFactId("cf:a"), ra, zero, Value.AlgebraProofComposite({}, "cf:a"))
local values = Value.ValueFactSet(module, {}, { ra, rb }, { cfa })
local trips = values:project_kernel_trips()
local projection = flow:project_kernel_loop_facts(values, trips)
assert(#projection.loops == 2 and #projection.reductions == 2 and #projection.closed_forms == 1)
assert(projection:lookup_closed_forms(a).entries[1].closed_form == cfa)
assert(projection:lookup_reductions(b).entries[1].reduction == rb)
assert(require("lalin.asdl").classof(projection:lookup_closed_forms(b)) == Kernel.KernelClosedFormMissing, "closed form from loop A must not leak into loop B")
assert(projection.loops[1].trip.trip_count.count.text == "trip:a")
assert(projection.loops[2].trip.trip_count.count.text == "trip:b")
local func_id = Code.CodeFuncId("fn:kernel_projection")
local block_id = Code.CodeBlockId("entry")
local sig_id = Code.CodeSigId("sig:kernel_projection")
local origin = Code.CodeOriginUnknown
local term = Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({}), origin)
local block = Code.CodeBlock(block_id, "entry", {}, {}, term, origin)
local func = Code.CodeFunc(func_id, "kernel_projection", Code.CodeLinkageLocal, sig_id, {}, {}, block_id, { block }, origin)
local code_module = Code.CodeModule(module, { Code.CodeSig(sig_id, {}, {}) }, {}, {}, {}, {}, { func }, origin)
local graph = Graph.CodeGraph(module, { Graph.CodeFuncGraph(func_id, {}, {}, {}, {
  Graph.GraphLoop(a, func_id, Graph.GraphBlockId(func_id, block_id), { Graph.GraphBlockId(func_id, block_id) }, {}, {}),
  Graph.GraphLoop(b, func_id, Graph.GraphBlockId(func_id, block_id), { Graph.GraphBlockId(func_id, block_id) }, {}, {}),
}) })
local request_plan = Kernel.KernelModulePlanRequest(code_module, graph, flow, values, require("lalin.schema_v2.mem").MemSemanticFactSet(module, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}), require("lalin.schema_v2.effect").EffectFactSet(module, {}, {}, {}), trips):plan_kernels()
assert(request_plan.plans[1].body.domain.trip.trip_count == trip_a, "module planning must wire real trip evidence")
print("test_kernel_plan_module: ok")
