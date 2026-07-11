package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)

local Core = T.LalinCore
local Code = T.LalinCode
local Value = T.LalinValue
local Schedule = T.LalinSchedule
local Stencil = T.LalinStencil
local Plan = require("lalin.stencil_artifact_plan")(T)

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local sem = Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftMaskCount)
local function iconst(n)
    return Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt(tostring(n))))
end
local reduction = { op = Value.ReductionAdd, init = iconst(0), int_semantics = sem }
local input = Plan.input_expr("xs")

local store = Plan.store_n_artifact({
    result_ty = i32,
    inputs = { { name = "xs", ty = i32 } },
    expr = input,
    step_num = 1,
    schedule = Schedule.ScheduleScalarPointer,
})
local reduce = Plan.reduce_n_artifact(reduction, nil, {
    result_ty = i32,
    item_ty = i32,
    inputs = { { name = "xs", ty = i32 } },
    expr = input,
    step_num = 1,
    schedule = Schedule.ScheduleScalarPointer,
})
local scan = Plan.scan_array_artifact(reduction, nil, {
    elem_ty = i32,
    result_ty = i32,
    step_num = 1,
    schedule = Schedule.ScheduleScalarPointer,
})

local missing_ok, missing_error = pcall(Plan.store_n_artifact, {
    result_ty = i32,
    inputs = { { name = "xs", ty = i32 } },
    expr = input,
    step_num = 1,
})
assert(not missing_ok, "missing schedule selection must not choose a scalar or vector default")
assert(tostring(missing_error):find("explicitly unscheduled", 1, true) ~= nil)
assert(asdl.classof(store.instance.descriptor.schedule_selection) == Stencil.StencilDescriptorScheduleSelected)
assert(asdl.classof(store.instance.schedule) == Stencil.StencilScheduleScalar)
assert(asdl.classof(reduce.instance.descriptor.schedule_selection) == Stencil.StencilDescriptorScheduleSelected)
assert(asdl.classof(scan.instance.descriptor.schedule_selection) == Stencil.StencilDescriptorScheduleSelected)

local selected_outcome = Plan.instance_outcome(store.instance.id, store.instance.descriptor, store.instance.abi, store.instance.proofs)
assert(asdl.classof(selected_outcome) == Stencil.StencilInstanceScheduled)
assert(selected_outcome.instance.schedule == store.instance.schedule)

local desc = store.instance.descriptor
local unscheduled = Stencil.StencilDescriptor(
    desc.producer, desc.accesses, desc.body, desc.sink,
    Stencil.StencilDescriptorExplicitlyUnscheduled("artifact emission intentionally deferred")
)
local unscheduled_outcome = Plan.instance_outcome(store.instance.id, unscheduled, store.instance.abi, store.instance.proofs)
assert(asdl.classof(unscheduled_outcome) == Stencil.StencilInstanceExplicitlyUnscheduled)
assert(unscheduled_outcome.reason == "artifact emission intentionally deferred")

local reduce_desc = reduce.instance.descriptor
local vector_facts = Stencil.StencilVectorizationFacts(
    {},
    {},
    Stencil.StencilTripCountDynamic,
    Stencil.StencilArithmeticVectorFact(true, sem, nil),
    {}
)
local resolution = Stencil.StencilScheduleResolutionInput(
    Stencil.StencilDescriptorShape(reduce_desc.producer, reduce_desc.accesses, reduce_desc.body, reduce_desc.sink),
    reduce.instance.schedule.compiler,
    vector_facts
)
local invalid_vector = Schedule.ScheduleVector(Schedule.LaneScalar, 1, 1, Schedule.TailScalar)
local invalid_selection = invalid_vector:stencil_artifact_select_descriptor_schedule(resolution)
assert(asdl.classof(invalid_selection) == Stencil.StencilDescriptorScheduleRejected)
assert(asdl.classof(invalid_selection.rejects[1]) == Stencil.StencilScheduleRejectIllegalLaneCount)

local vector_schedule = Stencil.StencilScheduleVector(
    Stencil.StencilVectorFeatureNative,
    Stencil.StencilLaneFixed(4),
    Stencil.StencilVectorUnaligned,
    Stencil.StencilVectorScalarTail,
    Stencil.StencilVectorReductionHorizontal,
    Stencil.StencilVectorCompilerCompiledStencil,
    2,
    3,
    reduce.instance.schedule.compiler,
    vector_facts
)
local function realized_vector(feature, lanes, unroll, interleave, tail)
    return Stencil.StencilRealizedVector(
        feature, lanes, unroll, interleave, tail, Stencil.StencilMaterializerResidualBC, {}
)
end
local exact_realized = realized_vector(Stencil.StencilVectorFeatureNative, 4, 2, 3, Stencil.StencilVectorScalarTail)
assert(vector_schedule:stencil_artifact_matches_realized(exact_realized))
assert(#Plan.schedule_rejects_for_realized(vector_schedule, exact_realized) == 0)

local function assert_vector_mismatch(realized, label)
    assert(not vector_schedule:stencil_artifact_matches_realized(realized), label)
    assert(#Plan.schedule_rejects_for_realized(vector_schedule, realized) == 1, label .. " should produce a typed mismatch reject")
end
assert_vector_mismatch(realized_vector(Stencil.StencilVectorFeatureAVX2, 4, 2, 3, Stencil.StencilVectorScalarTail), "feature mismatch")
assert_vector_mismatch(realized_vector(Stencil.StencilVectorFeatureNative, 8, 2, 3, Stencil.StencilVectorScalarTail), "lane mismatch")
assert_vector_mismatch(realized_vector(Stencil.StencilVectorFeatureNative, 4, 1, 3, Stencil.StencilVectorScalarTail), "unroll mismatch")
assert_vector_mismatch(realized_vector(Stencil.StencilVectorFeatureNative, 4, 2, 1, Stencil.StencilVectorScalarTail), "interleave mismatch")
assert_vector_mismatch(realized_vector(Stencil.StencilVectorFeatureNative, 4, 2, 3, Stencil.StencilVectorMaskTail), "scalar versus masked tail mismatch")
assert_vector_mismatch(
    Stencil.StencilRealizedScalar(Stencil.StencilMaterializerResidualBC, {}),
    "requested vector versus realized scalar mismatch"
)
assert_vector_mismatch(
    Stencil.StencilRealizedUnrolled(2, Stencil.StencilMaterializerResidualBC, {}),
    "requested vector versus realized unrolled mismatch"
)

local function vector_schedule_with_lane_policy(lane_policy)
    return Stencil.StencilScheduleVector(
        Stencil.StencilVectorFeatureNative,
        lane_policy,
        Stencil.StencilVectorUnaligned,
        Stencil.StencilVectorScalarTail,
        Stencil.StencilVectorReductionHorizontal,
        Stencil.StencilVectorCompilerCompiledStencil,
        2,
        3,
        reduce.instance.schedule.compiler,
        vector_facts
)
end
local native_lane_schedule = vector_schedule_with_lane_policy(Stencil.StencilLaneNative)
assert(native_lane_schedule:stencil_artifact_matches_realized(exact_realized))
assert(not native_lane_schedule:stencil_artifact_matches_realized(
    realized_vector(Stencil.StencilVectorFeatureNative, 1, 2, 3, Stencil.StencilVectorScalarTail)
))
local target_lane_schedule = vector_schedule_with_lane_policy(Stencil.StencilLaneFromTarget)
assert(target_lane_schedule:stencil_artifact_matches_realized(exact_realized))
assert(not target_lane_schedule:stencil_artifact_matches_realized(
    realized_vector(Stencil.StencilVectorFeatureNative, 1, 2, 3, Stencil.StencilVectorScalarTail)
))

local masked_schedule = Stencil.StencilScheduleVector(
    Stencil.StencilVectorFeatureNative,
    Stencil.StencilLaneFixed(4),
    Stencil.StencilVectorUnaligned,
    Stencil.StencilVectorMaskTail,
    Stencil.StencilVectorReductionHorizontal,
    Stencil.StencilVectorCompilerCompiledStencil,
    2,
    3,
    reduce.instance.schedule.compiler,
    vector_facts
)
assert(masked_schedule:stencil_artifact_matches_realized(
    realized_vector(Stencil.StencilVectorFeatureNative, 4, 2, 3, Stencil.StencilVectorMaskTail)
))
assert(not masked_schedule:stencil_artifact_matches_realized(exact_realized), "masked versus scalar tail mismatch")

local reject = Stencil.StencilScheduleRejectIllegalLaneCount(1, "vector schedule requires more than one lane")
local rejected = Stencil.StencilDescriptor(
    desc.producer, desc.accesses, desc.body, desc.sink,
    Stencil.StencilDescriptorScheduleRejected({ reject }, reject.reason)
)
local rejected_outcome = Plan.instance_outcome(store.instance.id, rejected, store.instance.abi, store.instance.proofs)
assert(asdl.classof(rejected_outcome) == Stencil.StencilInstanceScheduleRejected)
assert(rejected_outcome.rejects[1] == reject)

io.write("test_stencil_schedule_selection: ok\n")
