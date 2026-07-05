package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.native_backend")(T)

local Native = T.LalinNative
local Kernel = T.LalinKernel
local Code = T.LalinCode
local Core = T.LalinCore
local Flow = T.LalinFlow
local Mem = T.LalinMem
local Value = T.LalinValue
local Effect = T.LalinEffect
local Support = require("lalin.native_template_support")(T)

local target = Support.host_target()
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local func = Code.CodeFuncId("native.kernel.func")
local domain = Flow.FlowDomainFunction(func)
local trip = Flow.FlowTripCountNonNegative(Code.CodeValueId("native.kernel.n"), nil)
local induction = Code.CodeValueId("native.kernel.i")
local expr_i = Value.ValueExprValue(induction)
local proof = Value.AlgebraProofFlow(domain, "native kernel projection smoke")
local reduction = Value.ReductionFact(
    Value.AlgebraFactId("native.kernel.reduction"),
    domain,
    Code.CodeValueId("native.kernel.acc"),
    Value.ReductionAdd,
    Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("0"))),
    expr_i,
    i32,
    nil,
    nil,
    proof
)
local closed = Value.ClosedFormFact(Value.AlgebraFactId("native.kernel.closed"), reduction, expr_i, Value.AlgebraProofReduction(reduction, "closed"))
local lane = Kernel.KernelLane(
    Kernel.KernelLaneId("native.kernel.lane"),
    Mem.MemObjectId("native.kernel.object"),
    { Mem.MemAccessId("native.kernel.access") },
    Mem.MemBaseValue(Code.CodeValueId("native.kernel.ptr")),
    i32,
    Mem.MemAccessContiguous,
    {}
)
local binding = Kernel.KernelBinding(Kernel.KernelValueId("native.kernel.kv"), i32, Kernel.KernelExprAlgebra(expr_i))
local store = Kernel.KernelEffectStore(lane, expr_i, Kernel.KernelExprKernelValue(binding.id))
local fold = Kernel.KernelEffectFold(reduction)
local call = Effect.CallSummary(func, nil, { Effect.EffectNoTrap("native kernel contract") })
local body = Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, trip, induction),
    { lane },
    { binding },
    { store, fold },
    Kernel.KernelResultClosedForm(closed),
    Kernel.KernelEquivalenceProof({ Kernel.KernelProofFlow(domain, "counted") })
)
local plan = Kernel.KernelPlanned(Kernel.KernelId("native.kernel.plan"), Kernel.KernelSubjectFunction(func), body)
local type_layouts = Native.NativeCodeTypeLayoutPlan({}, {}, {})

local domain_projection = body.domain:native_kernel_loop_projection(target)
assert(asdl.isa(domain_projection, Native.NativeKernelLoopProjection), "KernelDomainFlow should own native loop projection")
assert(domain_projection.trip_count_value == trip.count, "trip-count projection should carry dynamic trip count value")
assert(body.domain:native_kernel_axis(target):native_kernel_axis_equals(Native.NativeKernelDomainProjectionAxis(domain_projection)), "domain projection axis should compare by typed projection")

local lane_projection = lane:native_kernel_lane_projection(target, type_layouts)
assert(asdl.isa(lane_projection, Native.NativeKernelLaneProjection), "KernelLane should own lane/address projection")
assert(lane_projection.elem_storage.size == 4, "lane projection should carry element storage layout")
assert(lane:native_kernel_axis(target, type_layouts):native_kernel_axis_equals(Native.NativeKernelLaneProjectionAxis(lane_projection)), "lane projection axis should compare by typed projection")

local binding_projection = binding:native_kernel_binding_projection(target, type_layouts)
assert(asdl.isa(binding_projection.expr, Native.NativeKernelExprProjection), "KernelBinding should project its expression through typed expr projection")
assert(asdl.isa(binding_projection.frame.role, Native.NativeKernelFrameRole), "KernelBinding projection should allocate a typed frame role")

local store_projection = store:native_kernel_effect_projection(target, type_layouts)
local fold_projection = fold:native_kernel_effect_projection(target, type_layouts)
assert(asdl.isa(store_projection, Native.NativeKernelEffectProjection), "KernelEffectStore should own store projection")
assert(asdl.isa(fold_projection.state, Native.NativeKernelEffectReductionState), "KernelEffectFold should carry reduction state storage")
assert(store:native_kernel_axis(target, type_layouts):native_kernel_axis_equals(Native.NativeKernelEffectProjectionAxis(store_projection)), "effect projection axis should compare by typed projection")

local result_projection = body.result:native_kernel_result_projection(i32, target, type_layouts)
assert(asdl.isa(result_projection, Native.NativeKernelResultClosedFormProjection), "KernelResultClosedForm should own result projection")

local body_projection = body:native_kernel_body_projection(target, type_layouts, i32)
assert(asdl.isa(body_projection, Native.NativeKernelBodyProjection), "KernelBody should own full native body projection")
assert(#body_projection.lanes == 1 and #body_projection.bindings == 1 and #body_projection.effects == 2, "body projection should carry lane/binding/effect facets")
assert(asdl.isa(body_projection.value_environment, Native.NativeKernelValueEnvironmentProjection), "body projection should carry a typed value environment")
assert(#body_projection.frame >= 6, "body projection should carry domain/lane/binding/effect/result frame entries")
assert(body:native_kernel_axis(target, type_layouts, i32):native_kernel_axis_equals(Native.NativeKernelBodyProjectionAxis(body_projection)), "body projection axis should compare by typed projection")

local loop_shape = domain_projection:native_kernel_loop_source_shape()
local lane_shape = lane_projection:native_kernel_lane_address_source_shape()
local expr_shape = binding_projection.expr:native_kernel_value_expr_source_shape(target, type_layouts)
local effect_shape = store_projection:native_kernel_effect_source_shape(target, type_layouts)
local result_shape = body_projection.result:native_kernel_result_source_shape(target, type_layouts)
local body_shape = body_projection:native_kernel_body_source_shape(target, type_layouts)
assert(asdl.isa(loop_shape, Native.NativeKernelLoopSourceShape), "kernel loop source shape should be finite ASDL vocabulary")
assert(asdl.isa(lane_shape, Native.NativeKernelLaneAddressSourceShape), "kernel lane source shape should not carry program lane identity")
assert(asdl.isa(expr_shape, Native.NativeKernelValueExprSourceShape), "kernel expr source shape should be finite ASDL vocabulary")
assert(asdl.isa(effect_shape, Native.NativeKernelEffectSourceShape), "kernel effect source shape should be finite ASDL vocabulary")
assert(asdl.isa(result_shape, Native.NativeKernelResultSourceShape), "kernel result source shape should be finite ASDL vocabulary")
assert(asdl.isa(body_shape, Native.NativeKernelBodySourceShape), "kernel body source shape should summarize counts/shapes only")
assert(body_projection:native_kernel_source_axis(target, type_layouts):native_kernel_axis_equals(Native.NativeKernelSourceShapeAxis(Native.NativeKernelBodyOpShape(body_shape))), "kernel body source-shape axis should select by finite shape")
assert(store_projection:native_kernel_source_axis(target, type_layouts):native_kernel_axis_equals(Native.NativeKernelSourceShapeAxis(Native.NativeKernelEffectOpShape(effect_shape))), "kernel effect source-shape axis should select by finite shape")

local support_domain = Support.support_domain(
    Native.NativeTemplateSupportDomainId("native.kernel.contracts.source.support"),
    target,
    Support.empty_runtime(),
    { Support.scalar_i32(), Support.scalar_index(target.pointer_bits), Support.scalar_pointer(target.pointer_bits) }
)
assert(asdl.isa(support_domain.kernel_sources, Native.NativeKernelSourceSupport), "support domains should carry finite Kernel source-shape support")

local plan_projection = plan:native_kernel_plan_projection(target, type_layouts, i32)
assert(asdl.isa(plan_projection, Native.NativeKernelPlannedProjection), "KernelPlanned should own native plan projection")
assert(plan:native_kernel_axis(target, type_layouts, i32):native_kernel_axis_equals(Native.NativeKernelPlanProjectionAxis(plan_projection)), "plan projection axis should compare by typed projection")
local plan_shape = plan_projection:native_kernel_plan_source_shape(target, type_layouts)
assert(asdl.isa(plan_shape, Native.NativeKernelPlanSourceShape), "kernel plan source shape should be finite ASDL vocabulary")
assert(plan_projection:native_kernel_source_axis(target, type_layouts):native_kernel_axis_equals(Native.NativeKernelSourceShapeAxis(Native.NativeKernelPlanOpShape(plan_shape))), "kernel plan source-shape axis should select by finite shape")

local lowering = plan:native_kernel_lowering_input(target, type_layouts, i32, Native.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}), {})
assert(asdl.isa(lowering, Native.NativeKernelLoweringInput), "KernelPlanned should build typed NativeKernelLoweringInput")
assert(lowering.result_ty == i32, "kernel lowering input should carry result type")
assert(lowering.type_layouts == type_layouts, "kernel lowering input should carry Code type layout plan")
assert(asdl.isa(lowering.frame, Native.NativeKernelFrameLayout), "kernel lowering input should carry role-to-slot frame layout")
assert(#lowering.frame.entries > 0 and asdl.isa(lowering.frame.entries[1].slot, Native.NativeFrameSlot), "kernel frame roles should lower to concrete NativeFrameSlot values")
assert(#lowering.lanes == 1 and asdl.isa(lowering.lanes[1], Native.NativeKernelLaneAddressEntry), "kernel lowering input should carry lane address entries")
assert(asdl.isa(lowering.lanes[1].address.role, Native.NativeKernelFrameLaneAddress), "kernel lane lowering should carry a separate materialized-address frame role")
assert(#lowering.kernel_inputs >= 1, "kernel lowering input should carry kernel value inputs")
local effect_only_call = call:native_kernel_call_target_entry()
assert(asdl.isa(effect_only_call.capability, Native.NativeKernelCallEffectOnlyTarget), "CallSummary should produce typed call target entries")

local function fake_loaded_bank(id)
    local manifest = Native.NativeTemplateSourceManifest(Native.NativeTemplateManifestId(id .. ".manifest"), Native.NativeTemplateSupportDomainId(id .. ".support"), {}, 0)
    local artifact = Native.NativeBankArtifact(Native.NativeBankId(id), target, manifest, 0, "lalin_native_bank_artifact", "lalin_native_bank_select", "lalin_native_bank_install")
    return Native.NativeLoadedBank(artifact, 1)
end

local graph_shapes = {
    Native.NativeKernelPlanOpShape(plan_shape),
    Native.NativeKernelBodyOpShape(body_shape),
    Native.NativeKernelDomainOpShape(loop_shape),
    Native.NativeKernelLaneOpShape(lane_shape),
    Native.NativeKernelExprOpShape(binding_projection.expr:native_kernel_value_expr_source_shape(target, type_layouts)),
    Native.NativeKernelEffectOpShape(store_projection:native_kernel_effect_source_shape(target, type_layouts)),
    Native.NativeKernelEffectOpShape(fold_projection:native_kernel_effect_source_shape(target, type_layouts)),
    Native.NativeKernelProofOpShape(Native.NativeKernelProofFlowShape),
    Native.NativeKernelResultOpShape(result_shape),
}
local graph_bank = fake_loaded_bank("native.kernel.contracts.fake.bank")
local graph = plan:plan_native_copy(Native.NativePlanInput(target, Support.empty_runtime(), graph_bank), lowering)
assert(asdl.isa(graph, Native.NativeTemplateGraph), "KernelPlanned should lower to a NativeTemplateGraph")
assert(graph.frame_layout == lowering.frame.frame, "kernel graph should use the NativeKernelLoweringInput frame layout")
assert(graph.addresses == lowering.addresses, "kernel graph should carry lowering module address plans")
assert(#graph.nodes == 9, "kernel graph should compose plan/body/domain/lane/binding/effect/proof/result nodes")
local has_conditional_domain = false
local has_loopback = false
for _, edge in ipairs(graph.control_edges or {}) do
    has_conditional_domain = has_conditional_domain or asdl.isa(edge, Native.NativeConditionalBranchEdge)
    has_loopback = has_loopback or asdl.isa(edge, Native.NativeLoopBackedgeEdge)
end
assert(has_conditional_domain, "kernel domain lowering should use symbol-bearing then/else control edges")
assert(has_loopback, "kernel effect chain should loop back to the domain node with a symbol-bearing backedge")
assert(#graph.exits == 1, "kernel result terminal should be the single graph exit")

io.write("native kernel contracts ok\n")
