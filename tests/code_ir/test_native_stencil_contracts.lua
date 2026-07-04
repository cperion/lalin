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

print("native stencil contracts ok")
