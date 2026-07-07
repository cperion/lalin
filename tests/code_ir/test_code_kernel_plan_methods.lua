package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.code_kernel_plan")(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Flow = T.LalinFlow
local Kernel = T.LalinKernel
local Value = T.LalinValue

local subject = Kernel.KernelSubjectLoop(T.LalinGraph.GraphLoopId("loop:test"))
local domain = Flow.FlowDomainLoop(T.LalinGraph.GraphLoopId("loop:test"))
local reject_not_counted = Kernel.KernelRejectNoFacts(subject, "not-counted")
local reject_no_owner = Kernel.KernelRejectNoFacts(subject, "no-owner")
local reject_memory = Kernel.KernelRejectNoFacts(subject, "memory-reject")
local reject_effect = Kernel.KernelRejectNoFacts(subject, "effect-reject")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local acc = Code.CodeValueId("v:acc")
local zero = Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0")))
local proof = Value.AlgebraProofFlow(domain, "test proof")
local reduction = Value.ReductionFact(Value.AlgebraFactId("red:test"), domain, acc, Value.ReductionAdd, zero, zero, i32, nil, nil, proof)
local closed_form = Value.ClosedFormFact(Value.AlgebraFactId("cf:test"), reduction, zero, Value.AlgebraProofReduction(reduction, "closed form"))

local function input(spec)
    if spec.counted == false then return Kernel.KernelLoopNotCounted({ reject_not_counted }) end
    if spec.has_func_id == false then return Kernel.KernelLoopMissingOwner({ reject_no_owner }) end
    if spec.rejects ~= nil then return Kernel.KernelLoopRejectedFacts(spec.rejects) end
    if spec.closed_form ~= nil then return Kernel.KernelLoopClosedFormCandidate(spec.closed_form, spec.trip_count or Flow.FlowTripCountNonNegative(Code.CodeValueId("trip:test"), nil)) end
    if spec.reduction ~= nil then return Kernel.KernelLoopReductionCandidate(spec.reduction) end
    if spec.skeleton_result ~= nil then return Kernel.KernelLoopSkeletonCandidate(spec.skeleton_result) end
    return Kernel.KernelLoopOriginalControlCandidate
end

do
    local selection = input { counted = false, has_func_id = false }:select_kernel_loop_plan()
    assert(selection.rejects[1] == reject_not_counted, "uncounted loop must use counted-domain reject")
end

do
    local selection = input { has_func_id = false }:select_kernel_loop_plan()
    assert(selection.rejects[1] == reject_no_owner, "ownerless loop must use graph-owner reject")
end

do
    local selection = input { rejects = { reject_memory, reject_effect } }:select_kernel_loop_plan()
    assert(#selection.rejects == 2 and selection.rejects[2] == reject_effect, "semantic rejects must be preserved")
end

do
    local selection = input {
        closed_form = closed_form,
        reduction = reduction,
        trip_count = Flow.FlowTripCountUnknown("test unknown"),
    }:select_kernel_loop_plan()
    assert(selection.closed_form == closed_form, "closed-form fact must be returned")
    assert(selection.add_trip_unknown_proof == true, "trip-count proof bit must be carried")
end

do
    local selection = input { reduction = reduction }:select_kernel_loop_plan()
    assert(selection.reduction == reduction, "reduction fact must be returned")
end

do
    local skeleton = Kernel.KernelResultVoid
    local selection = input { skeleton_result = skeleton }:select_kernel_loop_plan()
    assert(selection.result == skeleton, "skeleton result must be returned")
end

do
    local selection = input {}:select_kernel_loop_plan()
    assert(selection == Kernel.KernelLoopPlanOriginalControl, "original-control result must be the semantic default")
end

local ok = pcall(require, "lalin.code_kernel_plan_rules")
assert(not ok, "code_kernel_plan_rules must not exist")

io.write("lalin code_kernel_plan methods ok\n")

-- Multi-loop coverage: verify candidates do not leak across loop boundaries.
do
    local loop_id_a = T.LalinGraph.GraphLoopId("loop:a")
    local loop_id_b = T.LalinGraph.GraphLoopId("loop:b")
    local func_id = Code.CodeFuncId("fn:multi")

    -- Two distinct reductions on different domain loops.
    local domain_a = Flow.FlowDomainLoop(loop_id_a)
    local domain_b = Flow.FlowDomainLoop(loop_id_b)
    local acc = Code.CodeValueId("v:acc")
    local ra = Value.ReductionFact(Value.AlgebraFactId("red:a"), domain_a, acc, Value.ReductionAdd, zero, zero, i32, nil, nil, proof)
    local rb = Value.ReductionFact(Value.AlgebraFactId("red:b"), domain_b, acc, Value.ReductionMul, zero, zero, i32, nil, nil, proof)

    -- Verify reduction filtering by domain.
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local value_facts = Value.ValueFactSet(Code.CodeModuleId("mod:test"), {}, { ra, rb }, {})

    -- Loop A gets only reduction A.
    local ra_list = {}
    for _, r in ipairs(value_facts.reductions or {}) do
        if asdl.classof(r.domain) == Flow.FlowDomainLoop and asdl.classof(domain_a) == Flow.FlowDomainLoop and r.domain.loop == domain_a.loop then
            ra_list[#ra_list + 1] = r
        end
    end
    assert(#ra_list == 1 and ra_list[1].id.text == "red:a", "domain filter: loop A sees only reduction A")

    -- Loop B gets only reduction B.
    local rb_list = {}
    for _, r in ipairs(value_facts.reductions or {}) do
        if asdl.classof(r.domain) == Flow.FlowDomainLoop and asdl.classof(domain_b) == Flow.FlowDomainLoop and r.domain.loop == domain_b.loop then
            rb_list[#rb_list + 1] = r
        end
    end
    assert(#rb_list == 1 and rb_list[1].id.text == "red:b", "domain filter: loop B sees only reduction B")

    -- Two loop candidates with independent plans must not interfere.
    local subject_a = Kernel.KernelSubjectLoop(loop_id_a)
    local subject_b = Kernel.KernelSubjectLoop(loop_id_b)
    local plan_a = Kernel.KernelLoopReductionCandidate(ra):select_kernel_loop_plan()
    local plan_b = Kernel.KernelLoopReductionCandidate(rb):select_kernel_loop_plan()
    assert(plan_a.reduction == ra, "plan A holds reduction A")
    assert(plan_b.reduction == rb, "plan B holds reduction B")
    assert(plan_a.reduction ~= plan_b.reduction, "reduction candidates do not alias")

    -- Build loop plans and verify they carry their own domain.
    local plans = {}
    plan_a:add_selected_loop_plan(plans, subject_a, Kernel.KernelLoopPlanBuild(
        domain_a, Flow.FlowTripCountUnknown("no trip"), nil, {}, {}, {}, {}))
    plan_b:add_selected_loop_plan(plans, subject_b, Kernel.KernelLoopPlanBuild(
        domain_b, Flow.FlowTripCountUnknown("no trip"), nil, {}, {}, {}, {}))
    assert(#plans == 2, "two loop plans produced")
    assert(asdl.classof(plans[1]) == Kernel.KernelPlanned, "plan 1 is KernelPlanned")
    assert(asdl.classof(plans[2]) == Kernel.KernelPlanned, "plan 2 is KernelPlanned")
    assert(plans[1].id.text ~= plans[2].id.text, "plan ids do not collide")
    assert(plans[1].subject.loop.text == "loop:a", "plan 1 subject is loop A")
    assert(plans[2].subject.loop.text == "loop:b", "plan 2 subject is loop B")
end
