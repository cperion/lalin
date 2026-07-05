package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.native_backend")(T)

local Native = T.LalinNative
local Kernel = T.LalinKernel
local Stencil = T.LalinStencil
local Code = T.LalinCode
local Core = T.LalinCore
local Flow = T.LalinFlow
local Mem = T.LalinMem
local Value = T.LalinValue
local Support = require("lalin.native_template_support")(T)

local target = Support.host_target()
local runtime = Support.empty_runtime()
local type_layouts = Native.NativeCodeTypeLayoutPlan({}, {}, {})
local addresses = Native.NativeModuleAddressPlan({}, {}, {}, {}, {}, {})
local i32 = Code.CodeTyInt(32, Code.CodeSigned)

local function bank(id)
    local manifest = Native.NativeTemplateSourceManifest(Native.NativeTemplateManifestId(id .. ".manifest"), Native.NativeTemplateSupportDomainId(id .. ".support"), {}, 0)
    local artifact = Native.NativeBankArtifact(Native.NativeBankId(id), target, manifest, 0, "lalin_native_bank_artifact", "lalin_native_bank_select", "lalin_native_bank_install")
    return Native.NativeLoadedBank(artifact, 1)
end

-- Kernel graph lowering: counted domain, lane address, scalar expr, store effect, proof, result.
local func = Code.CodeFuncId("native.kernel_stencil.kernel.func")
local domain = Flow.FlowDomainFunction(func)
local trip = Flow.FlowTripCountNonNegative(Code.CodeValueId("native.kernel_stencil.n"), nil)
local induction = Code.CodeValueId("native.kernel_stencil.i")
local expr_i = Value.ValueExprValue(induction)
local lane = Kernel.KernelLane(
    Kernel.KernelLaneId("native.kernel_stencil.lane"),
    Mem.MemObjectId("native.kernel_stencil.object"),
    { Mem.MemAccessId("native.kernel_stencil.access") },
    Mem.MemBaseValue(Code.CodeValueId("native.kernel_stencil.ptr")),
    i32,
    Mem.MemAccessContiguous,
    {}
)
local binding = Kernel.KernelBinding(Kernel.KernelValueId("native.kernel_stencil.kv"), i32, Kernel.KernelExprAlgebra(expr_i))
local store = Kernel.KernelEffectStore(lane, expr_i, Kernel.KernelExprKernelValue(binding.id))
local result = Kernel.KernelResultValue(Kernel.KernelExprKernelValue(binding.id))
local body = Kernel.KernelBody(
    Kernel.KernelDomainFlow(domain, trip, induction),
    { lane },
    { binding },
    { store },
    result,
    Kernel.KernelEquivalenceProof({ Kernel.KernelProofFlow(domain, "native kernel/stencil graph test") })
)
local kplan = Kernel.KernelPlanned(Kernel.KernelId("native.kernel_stencil.kernel.plan"), Kernel.KernelSubjectFunction(func), body)
local klowering = kplan:native_kernel_lowering_input(target, type_layouts, i32, addresses, {})
assert(asdl.isa(klowering, Native.NativeKernelLoweringInput), "kernel should build typed lowering input")
assert(#klowering.frame.entries >= 5, "kernel lowering should allocate role-to-slot frame entries")
assert(#klowering.lanes == 1 and asdl.isa(klowering.lanes[1].address.role, Native.NativeKernelFrameLaneAddress), "kernel lowering should materialize lane address frame roles")

local kprojection = kplan:native_kernel_plan_projection(target, type_layouts, i32)
local kbody_projection = body:native_kernel_body_projection(target, type_layouts, i32)
local kshapes = {
    Native.NativeKernelPlanOpShape(kprojection:native_kernel_plan_source_shape(target, type_layouts)),
    Native.NativeKernelBodyOpShape(kbody_projection:native_kernel_body_source_shape(target, type_layouts)),
    Native.NativeKernelDomainOpShape(body.domain:native_kernel_loop_projection(target):native_kernel_loop_source_shape()),
    Native.NativeKernelLaneOpShape(lane:native_kernel_lane_projection(target, type_layouts):native_kernel_lane_address_source_shape()),
    Native.NativeKernelExprOpShape(binding:native_kernel_binding_projection(target, type_layouts).expr:native_kernel_value_expr_source_shape(target, type_layouts)),
    Native.NativeKernelEffectOpShape(store:native_kernel_effect_projection(target, type_layouts):native_kernel_effect_source_shape(target, type_layouts)),
    Native.NativeKernelProofOpShape(Native.NativeKernelProofFlowShape),
    Native.NativeKernelResultOpShape(result:native_kernel_result_projection(i32, target, type_layouts):native_kernel_result_source_shape(target, type_layouts)),
}
local kgraph = kplan:plan_native_copy(Native.NativePlanInput(target, runtime, bank("native.kernel_stencil.kernel.bank")), klowering)
assert(asdl.isa(kgraph, Native.NativeTemplateGraph), "KernelPlanned should lower to a graph")
assert(#kgraph.nodes == 8, "kernel graph should contain plan/body/domain/lane/expr/effect/proof/result nodes")
local kernel_has_domain_branch = false
local kernel_has_loopback = false
for _, edge in ipairs(kgraph.control_edges or {}) do
    kernel_has_domain_branch = kernel_has_domain_branch or asdl.isa(edge, Native.NativeConditionalBranchEdge)
    kernel_has_loopback = kernel_has_loopback or asdl.isa(edge, Native.NativeLoopBackedgeEdge)
end
assert(kernel_has_domain_branch, "kernel domain should lower to a symbol-bearing branch edge")
assert(kernel_has_loopback, "kernel work chain should lower to a loopback edge")
assert(kgraph.frame_layout == klowering.frame.frame, "kernel graph should use lowering frame layout")

-- Stencil graph lowering: producer loop, access address, recursive point scalar fragments, body, sink, schedule.
local access_ref = Stencil.StencilAccessRef("a")
local access = Stencil.StencilAccess("a", Stencil.StencilAccessReadWrite, i32, Stencil.StencilLayoutContiguous(1))
local producer = Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(i32, nil, nil, 1, Stencil.StencilProducerForward))
local point = Stencil.StencilPointBinary(
    Stencil.StencilBinaryAdd,
    Stencil.StencilPointInput(access_ref),
    Stencil.StencilPointConst(Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("7"))), i32),
    i32,
    nil,
    nil
)
local descriptor = Stencil.StencilDescriptor(producer, { access }, Stencil.StencilBodyPoint(point), Stencil.StencilSinkStore(access_ref, Stencil.StencilStoreElementwise))
local schedule = Stencil.StencilScheduleScalar(Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO2, Stencil.StencilMachineNative, {}))
local instance = Stencil.StencilInstance(Stencil.StencilInstanceId("native.kernel_stencil.stencil"), descriptor, schedule, Stencil.StencilAbi({ i32 }, nil), {})
local empty_plan = Native.NativePlanInput(target, runtime, bank("native.kernel_stencil.stencil.empty"))
local slowering = instance:native_stencil_lowering_input(empty_plan, type_layouts, addresses)
assert(asdl.isa(slowering, Native.NativeStencilLoweringInput), "stencil should build typed lowering input")
assert(#slowering.producers == 1, "stencil producer should allocate loop frame roles")
assert(#slowering.accesses == 1, "stencil access should allocate address frame roles")
assert(#slowering.point_values == 3, "stencil point expression should allocate recursive point value slots")
assert(asdl.isa(slowering.sink_state.value.role, Native.NativeStencilFrameSinkState), "stencil sink lowering should allocate sink value/state frame roles")

local sprojection = instance:native_stencil_projection(target, type_layouts)
local input_shape = point.left:native_stencil_projection(target, type_layouts, descriptor).shape
local const_shape = point.right:native_stencil_projection(target, type_layouts, descriptor).shape
local sshapes = {
    sprojection.schedule.shape,
    sprojection.descriptor.producer.shape,
    sprojection.descriptor.accesses[1].shape,
    input_shape,
    const_shape,
    sprojection.descriptor.body.point.shape,
    sprojection.descriptor.body.shape,
    sprojection.descriptor.sink.shape,
}
local sgraph = instance:plan_native_copy(Native.NativePlanInput(target, runtime, bank("native.kernel_stencil.stencil.bank")))
assert(asdl.isa(sgraph, Native.NativeTemplateGraph), "StencilInstance should lower to a graph")
assert(#sgraph.nodes == 8, "stencil graph should contain schedule/producer/access/point/body/sink nodes")
local stencil_has_producer_branch = false
local stencil_has_loopback = false
local stencil_has_access_output = false
for _, edge in ipairs(sgraph.control_edges or {}) do
    stencil_has_producer_branch = stencil_has_producer_branch or asdl.isa(edge, Native.NativeConditionalBranchEdge)
    stencil_has_loopback = stencil_has_loopback or asdl.isa(edge, Native.NativeLoopBackedgeEdge)
end
for _, edge in ipairs(sgraph.value_edges or {}) do
    stencil_has_access_output = stencil_has_access_output or tostring(edge.value.text):find("access%.a%.address") ~= nil
end
assert(stencil_has_producer_branch, "stencil producer should lower to a symbol-bearing branch edge")
assert(stencil_has_loopback, "stencil sink/work chain should loop back to producer")
assert(stencil_has_access_output, "stencil access lowering should materialize an address value edge")
assert(sgraph.addresses ~= nil and asdl.isa(sgraph.addresses, Native.NativeModuleAddressPlan), "stencil graph should carry typed address plans")

print("native kernel/stencil lowering ok")
