package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
local Schema = require("lalin.schema")

local T = asdl.context()
Schema(T)
require("lalin.native_backend")(T)

local Native = T.LalinNative
local Stencil = T.LalinStencil
local Code = T.LalinCode
local Core = T.LalinCore
local Value = T.LalinValue
local Support = require("lalin.native_template_support")(T)

local target = Support.host_target()
local type_layouts = Native.NativeCodeTypeLayoutPlan({}, {}, {})
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local access_ref = Stencil.StencilAccessRef("a")
local access = Stencil.StencilAccess("a", Stencil.StencilAccessRead, i32, Stencil.StencilLayoutContiguous(1))
local producer = Stencil.StencilProducer(
    nil,
    Stencil.StencilProduceRange1D(i32, nil, nil, 1, Stencil.StencilProducerForward)
)
local point = Stencil.StencilPointBinary(
    Stencil.StencilBinaryAdd,
    Stencil.StencilPointInput(access_ref),
    Stencil.StencilPointConst(Value.ValueExprConst(Code.CodeConstLiteral(i32, Core.LitInt("1"))), i32),
    i32,
    nil,
    nil
)
local body = Stencil.StencilBodyPoint(point)
local sink = Stencil.StencilSinkStore(access_ref, Stencil.StencilStoreElementwise)
local descriptor = Stencil.StencilDescriptor(producer, { access }, body, sink)
local compiler = Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO2, Stencil.StencilMachineNative, {})
local schedule = Stencil.StencilScheduleScalar(compiler)
local abi = Stencil.StencilAbi({ i32 }, nil)
local instance = Stencil.StencilInstance(Stencil.StencilInstanceId("native.stencil.contract"), descriptor, schedule, abi, {})

local projection = instance:native_stencil_projection(target, type_layouts)
assert(asdl.isa(projection, Native.NativeStencilInstanceProjection), "StencilInstance should own native instance projection")
assert(asdl.isa(projection.descriptor.producer.shape, Native.NativeStencilProducerSourceShape), "producer projection should carry finite source shape")
assert(asdl.isa(projection.descriptor.accesses[1].shape, Native.NativeStencilAccessSourceShape), "access projection should carry finite source shape")
assert(asdl.isa(projection.descriptor.body.shape, Native.NativeStencilBodySourceShape), "body projection should carry finite source shape")
assert(asdl.isa(projection.descriptor.sink.shape, Native.NativeStencilSinkSourceShape), "sink projection should carry finite source shape")
assert(asdl.isa(projection.schedule.shape, Native.NativeStencilScheduleSourceShape), "schedule projection should carry finite source shape")

local producer_axis = producer:native_stencil_axis(target, type_layouts)
assert(producer_axis:native_stencil_producer_axis_equals(Native.NativeStencilProducerSourceShapeAxis(projection.descriptor.producer.shape)), "producer source-shape axis should compare structurally")
local access_axis = access:native_stencil_axis(target, type_layouts)
assert(access_axis:native_stencil_access_axis_equals(Native.NativeStencilAccessSourceShapeAxis(projection.descriptor.accesses[1].shape)), "access source-shape axis should compare structurally")
local point_axis = point:native_stencil_axis(target, type_layouts, descriptor)
assert(point_axis:native_stencil_point_axis_equals(Native.NativeStencilPointSourceShapeAxis(projection.descriptor.body.point.shape)), "point source-shape axis should compare structurally")
local body_axis = body:native_stencil_axis(target, type_layouts, descriptor)
assert(body_axis:native_stencil_body_axis_equals(Native.NativeStencilBodySourceShapeAxis(projection.descriptor.body.shape)), "body source-shape axis should compare structurally")
local sink_axis = sink:native_stencil_axis(target, type_layouts, descriptor)
assert(sink_axis:native_stencil_sink_axis_equals(Native.NativeStencilSinkSourceShapeAxis(projection.descriptor.sink.shape)), "sink source-shape axis should compare structurally")
local schedule_axis = schedule:native_stencil_axis(target, type_layouts)
assert(schedule_axis:native_stencil_schedule_axis_equals(Native.NativeStencilScheduleSourceShapeAxis(projection.schedule.shape)), "schedule source-shape axis should compare structurally")

local stencil_sources = Native.NativeStencilSourceSupport(
    { projection.descriptor.producer.shape },
    { projection.descriptor.accesses[1].shape },
    { projection.descriptor.body.point.shape },
    { projection.descriptor.body.shape },
    { projection.descriptor.sink.shape },
    { projection.schedule.shape }
)
local domain = Support.support_domain_with_sources(
    Support.host_template_support_domain_id("stencil-contract"),
    target,
    Support.empty_runtime(),
    Support.host_scalar_reps(),
    Support.empty_kernel_source_support(),
    stencil_sources
)
assert(domain.stencil_sources == stencil_sources, "support domains should carry stencil source support separately from kernel support")

local function fake_loaded_bank(id)
    local manifest = Native.NativeTemplateSourceManifest(Native.NativeTemplateManifestId(id .. ".manifest"), Native.NativeTemplateSupportDomainId(id .. ".support"), {}, 0)
    local artifact = Native.NativeBankArtifact(Native.NativeBankId(id), target, manifest, 0, "lalin_native_bank_artifact", "lalin_native_bank_select", "lalin_native_bank_install")
    return Native.NativeLoadedBank(artifact, 1)
end

local lowering_plan = Native.NativePlanInput(target, Support.empty_runtime(), fake_loaded_bank("native.stencil.contracts.empty"))
local lowering = instance:native_stencil_lowering_input(lowering_plan, type_layouts, Native.NativeModuleAddressPlan({}, {}, {}, {}, {}, {}))
assert(asdl.isa(lowering, Native.NativeStencilLoweringInput), "StencilInstance should build a typed NativeStencilLoweringInput")
assert(lowering.instance == instance, "stencil lowering should carry the instance")
assert(asdl.isa(lowering.frame, Native.NativeStencilFrameLayout), "stencil lowering should carry a role-to-slot frame layout")
assert(#lowering.producers == 1, "range-1D producer should allocate one counter/stop frame entry")
assert(#lowering.accesses == 1, "stencil lowering should allocate access address entries")
assert(#lowering.point_values == 3, "recursive point expression lowering should allocate child and root point value entries")
assert(lowering.body_value.expr == point, "body value should reference the root point expression")


local input_shape = point.left:native_stencil_projection(target, type_layouts, descriptor).shape
local const_shape = point.right:native_stencil_projection(target, type_layouts, descriptor).shape
local graph_shapes = {
    projection.schedule.shape,
    projection.descriptor.producer.shape,
    projection.descriptor.accesses[1].shape,
    input_shape,
    const_shape,
    projection.descriptor.body.point.shape,
    projection.descriptor.body.shape,
    projection.descriptor.sink.shape,
}
local graph_bank = fake_loaded_bank("native.stencil.contracts.fake.bank")
local graph = instance:plan_native_copy(Native.NativePlanInput(target, Support.empty_runtime(), graph_bank))
assert(asdl.isa(graph, Native.NativeTemplateGraph), "StencilInstance should lower to a NativeTemplateGraph")
assert(graph.frame_layout.size > 0, "stencil graph should use a concrete NativeFrameLayout")
assert(#graph.nodes == 8, "stencil graph should compose schedule/producer/access/point/body/sink nodes")
local has_branch = false
local has_loopback = false
for _, edge in ipairs(graph.control_edges or {}) do
    has_branch = has_branch or asdl.isa(edge, Native.NativeConditionalBranchEdge)
    has_loopback = has_loopback or asdl.isa(edge, Native.NativeLoopBackedgeEdge)
end
assert(has_branch, "stencil producer lowering should use symbol-bearing then/else control edges")
assert(has_loopback, "stencil work chain should loop back to the producer with a symbol-bearing edge")
assert(graph.addresses ~= nil and asdl.isa(graph.addresses, Native.NativeModuleAddressPlan), "stencil graph should carry a typed module address plan")

print("native stencil contracts ok")
