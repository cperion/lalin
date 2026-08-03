package.path = "tests/?.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path
require("lalin.schema_v2")
local asdl = require("lalin.asdl")
local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Kernel = require("lalin.schema_v2.kernel")
require("lalin.impl.kernel_plan")

local loop = Graph.GraphLoopId("loop:a")
local domain = Flow.FlowDomainLoop(loop)
local trip = Flow.FlowTripCountExact(Code.CodeValueId("trip:a"), nil, nil)
local known = trip:kernel_trip_evidence(Kernel.KernelSubjectLoop(loop))
assert(asdl.classof(known) == Kernel.KernelTripKnown and known.trip_count == trip)
local rejected_trip = Flow.FlowTripCountRejected(Flow.FlowTripCountNotLoop("rejected"), nil)
local unavailable = rejected_trip:kernel_trip_evidence(Kernel.KernelSubjectLoop(loop))
assert(asdl.classof(unavailable) == Kernel.KernelTripUnavailable and unavailable.trip_count == rejected_trip)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local zero = Value.ValueExprConst(Code.CodeConstLiteral(i32, require("lalin.schema_v2.core").LitInt("0")))
local reduction = Value.ReductionFact(Value.AlgebraFactId("red:a"), domain, Code.CodeValueId("acc"), Code.CodeValueId("update"), Value.ReductionAdd, zero, zero, i32, nil, nil, Value.AlgebraProofComposite({}, "proof"))
local closed = Value.ClosedFormFact(Value.AlgebraFactId("cf:a"), reduction, zero, Value.AlgebraProofComposite({}, "closed"))
local fact = Kernel.KernelLoopFactEntry(
  loop, domain,
  Kernel.KernelLoopCounted(Flow.FlowCountedDomain(
    Code.CodeValueId("start"), Code.CodeValueId("stop"),
    Code.CodeValueId("step"), Flow.FlowStopExclusive, Flow.FlowLoopIncreasing)),
  Kernel.KernelCounterSelected(Kernel.KernelCounterValue(Code.CodeValueId("counter"))),
  known)
local projection = Kernel.KernelLoopFactProjection({ fact }, { Kernel.KernelReductionByLoopEntry(loop, reduction) }, { Kernel.KernelClosedFormByLoopEntry(loop, closed) })
local candidate = fact:kernel_candidate(projection)
assert(asdl.classof(candidate) == Kernel.KernelLoopClosedFormCandidate)
local selection = candidate:select_kernel_loop_plan()
assert(asdl.classof(selection) == Kernel.KernelLoopPlanClosedForm)
local build = Kernel.KernelLoopPlanBuild(domain, known, Kernel.KernelCounterValue(Code.CodeValueId("start")), Kernel.KernelLaneProjection({}), Kernel.KernelBindingProjection({}), Kernel.KernelEffectProjection({}), Kernel.KernelProofProjection({}))
local request = Kernel.KernelLoopPlanRequest(fact, candidate, Kernel.KernelLoopAnalysisReady(build))
local plan = request.analysis:materialize_kernel_selection(selection, request)
assert(asdl.classof(plan) == Kernel.KernelPlanned)
assert(plan.body.domain.trip == known, "materialized kernel must retain real trip evidence")
assert(asdl.classof(plan:schedule_eligibility()) == Kernel.KernelScheduleEligible)
local no_plan = Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(loop), { unavailable.reject })
assert(asdl.classof(no_plan:schedule_eligibility()) == Kernel.KernelScheduleIneligible)
print("test_kernel_plan_leaf_ownership: ok")
