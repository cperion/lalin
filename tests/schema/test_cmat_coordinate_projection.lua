package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema")
require("lalin.impl.lower_emit_c.coordinates")
require("lalin.impl.lower_emit_c.address_plan")

local Core = require("lalin.schema.core")
local Code = require("lalin.schema.code")
local C = require("lalin.schema.c")
local Graph = require("lalin.schema.graph")
local Flow = require("lalin.schema.flow")
local Value = require("lalin.schema.value")
local Mem = require("lalin.schema.mem")
local Kernel = require("lalin.schema.kernel")
local Stencil = require("lalin.schema.stencil")
local CMat = require("lalin.schema.c_materialize")
local Lower = require("lalin.schema.lower")

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_ty = Code.CodeTyDataPtr(i32)
local func = Code.CodeFuncId("fn:coordinates")
local block = Code.CodeBlockId("body")
local graph_block = Graph.GraphBlockId(func, block)
local loop = Graph.GraphLoopId("loop:coordinates")
local counter = Code.CodeValueId("i")
local start = Code.CodeValueId("start")
local stop = Code.CodeValueId("stop")
local step = Code.CodeValueId("step")
local dynamic = Code.CodeValueId("dynamic")
local ptr = Code.CodeValueId("ptr")
local ptr_absolute = Code.CodeValueId("ptr_absolute")
local access_id = Mem.MemAccessId("access:coordinates")
local absolute_access_id = Mem.MemAccessId("access:absolute")
local root = Mem.MemBaseValue(ptr)
local absolute_root = Mem.MemBaseValue(ptr_absolute)
local induction = Flow.FlowInduction(
  counter, i32, start, step, Flow.FlowPrimaryInduction,
  Flow.FlowRangeUnknown(counter))
local iteration = Stencil.StencilKernelIteration(
  loop, counter, i32, start, stop, step, 2,
  Stencil.StencilIterationStopExclusive, Stencil.StencilProducerForward,
  Stencil.StencilKernelTripExact(
    Flow.FlowTripCountExact(Code.CodeValueId("trip"), nil, nil)))

local function memory_fact(id, pointer, base, index, op)
  local place = Code.CodePlaceDeref(pointer, i32, 4)
  local mode = op == Mem.MemStore and Code.CodeMemoryWrite or Code.CodeMemoryRead
  return Mem.MemAccessFact(
    id, func, graph_block, nil, op, place,
    Code.CodeMemoryAccess(
      mode, i32, 4, Code.CodeMustNotTrap, false, nil),
    base, index, Mem.MemAccessContiguous, Mem.MemAlignKnown(4),
    Mem.MemBoundsInObject("coordinate fixture"),
    Mem.MemNonTrapping("coordinate fixture"))
end

local memory = memory_fact(
  access_id, ptr, root, Mem.MemIndexInduction(induction, induction.value, 4, 8, 0), Mem.MemLoad)
local absolute_memory = memory_fact(
  absolute_access_id, ptr_absolute, absolute_root,
  Mem.MemIndexValue(dynamic, 4, 3), Mem.MemLoad)
local memory_projection = Mem.MemAccessProjection({
  Mem.MemAccessByIdEntry(memory),
  Mem.MemAccessByIdEntry(absolute_memory),
}, {}, {}, {})

local xs = Stencil.StencilAccess(
  "xs", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local absolute_access = Stencil.StencilAccess(
  "absolute", Stencil.StencilAccessRead, i32,
  Stencil.StencilAccessDirect(Stencil.StencilLayoutContiguous(4)))
local lane = Kernel.KernelLane(
  Kernel.KernelLaneId("lane:xs"), Mem.MemObjectId("object:xs"),
  { access_id }, root, i32, Mem.MemAccessContiguous, {})
local absolute_lane = Kernel.KernelLane(
  Kernel.KernelLaneId("lane:absolute"),
  Mem.MemObjectId("object:absolute"), { absolute_access_id },
  absolute_root, i32, Mem.MemAccessContiguous, {})
local provenance = Stencil.StencilAccessByKernelLaneProjection({
  Stencil.StencilAccessByKernelLaneEntry(lane, xs),
  Stencil.StencilAccessByKernelLaneEntry(absolute_lane, absolute_access),
})

local xs_ref = Stencil.StencilAccessRef("xs")
local absolute_ref = Stencil.StencilAccessRef("absolute")
local centered_id = CMat.CMatStreamMemoryUse(
  Stencil.StencilStreamRef(Stencil.StencilStreamId("centered")))
local window_id = CMat.CMatWindowMemoryUse(
  Stencil.StencilStreamRef(Stencil.StencilStreamId("window")), 1)
local store_id = CMat.CMatSinkMemoryUse(
  Stencil.StencilSinkRef(Stencil.StencilSinkId("store")))
local absolute_id = CMat.CMatStreamMemoryUse(
  Stencil.StencilStreamRef(Stencil.StencilStreamId("absolute")))
local window_extent = Stencil.StencilWindowExtent(
  Stencil.StencilElementDistance(1), Stencil.StencilElementDistance(1))
local window_axis = Stencil.StencilWindowAxis(
  window_extent, Stencil.StencilWindowBoundaryClamp)
local window_source = Flow.FlowDomainShapeFact(
  Flow.FlowDomainLoop(loop), Flow.FlowDomainShapeWindowND({
    Flow.FlowDomainAxis(i32, Value.ValueExprValue(start),
      Value.ValueExprValue(stop), 2, Flow.FlowDomainForward, nil),
  }, { Flow.FlowWindowAxis(1, 1, Flow.FlowWindowBoundaryClamp) }),
  {}, Flow.FlowFactCheckerDerived)
local window_domain = Stencil.StencilKernelCountedWindow1D(
  window_source, window_axis)
local offset = Stencil.StencilWindowOffset(
  Stencil.StencilAxisRef(1), Stencil.StencilElementDistance(-1))
local explicit = Stencil.StencilIndexExplicit(
  Stencil.StencilIndexPoint(Value.ValueExprValue(dynamic)))
local spine = CMat.CMatMemoryUseSpine({
  CMat.CMatMemoryUse(
    centered_id, xs_ref, CMat.CMatMemoryLoad,
    CMat.CMatMemorySelectedIndex(Stencil.StencilIndexProducer)),
  CMat.CMatMemoryUse(
    window_id, xs_ref, CMat.CMatMemoryLoad,
    CMat.CMatMemoryWindowOffset(offset)),
  CMat.CMatMemoryUse(
    store_id, xs_ref, CMat.CMatMemoryStore,
    CMat.CMatMemorySelectedIndex(Stencil.StencilIndexProducer)),
  CMat.CMatMemoryUse(
    absolute_id, absolute_ref, CMat.CMatMemoryLoad,
    CMat.CMatMemorySelectedIndex(explicit)),
})

local input = Lower.LowerCMatCoordinateInput(
  iteration, window_domain, provenance, memory_projection)
local projected = spine:lower_coordinates(input)
assert(asdl.classof(projected) == Lower.LowerCMatCoordinatesProjected)
local facet = projected.facet
assert(facet.spine == spine)
assert(#facet.entries == #spine.uses)

local centered = facet:lookup(centered_id).entry.coordinate
local window = facet:lookup(window_id).entry.coordinate
local store = facet:lookup(store_id).entry.coordinate
local absolute = facet:lookup(absolute_id).entry.coordinate
assert(asdl.classof(centered) ==
  Lower.LowerCMatIterationAffineCoordinate)
assert(asdl.classof(window) ==
  Lower.LowerCMatWindowDynamicCoordinate)
assert(asdl.classof(store) ==
  Lower.LowerCMatIterationAffineCoordinate)
assert(centered.basis == window.basis and centered.basis == store.basis,
  "one structural address basis must be shared by aligned uses")
assert(centered.basis.root == root)
assert(centered.basis.induction == induction)
assert(centered.basis.index_scale_bytes == 4)
assert(centered.use_offset_bytes == 8)
assert(window.const_offset_bytes == 8)
assert(window.provenance.offset == offset)
assert(window.provenance.extent == window_extent)
assert(window.provenance.boundary == Stencil.StencilWindowBoundaryClamp)
assert(store.use_offset_bytes == 8)
assert(asdl.classof(absolute) == Lower.LowerCMatAbsoluteCoordinate)
assert(absolute.root == absolute_root)
assert(absolute.index == explicit.index)
assert(absolute.index_scale_bytes == 4)
assert(absolute.const_offset_bytes == 3)

local c_i32 = C.CBackendScalar(Core.ScalarI32)
local xs_base = C.CBackendLocal(
  C.CBackendLocalId("xs"), C.CBackendName("xs"), C.CBackendDataPtr(c_i32))
local absolute_base = C.CBackendLocal(
  C.CBackendLocalId("absolute"), C.CBackendName("absolute"),
  C.CBackendDataPtr(c_i32))
local address_accesses = CMat.CMatCFragmentAccessBindingProjection({
  CMat.CMatCFragmentAccessBindingEntry(
    xs_ref, lane.id, access_id, CMat.CMatCFragmentAccessDirect(xs_base),
    4, 4, Mem.MemAlignKnown(4),
    Mem.MemBoundsInObject("coordinate fixture"),
    Mem.MemNonTrapping("coordinate fixture"),
    Mem.MemMovementMovable("coordinate fixture")),
  CMat.CMatCFragmentAccessBindingEntry(
    absolute_ref, absolute_lane.id, absolute_access_id,
    CMat.CMatCFragmentAccessDirect(absolute_base),
    4, 4, Mem.MemAlignKnown(4),
    Mem.MemBoundsInObject("absolute coordinate fixture"),
    Mem.MemNonTrapping("absolute coordinate fixture"),
    Mem.MemMovementMovable("absolute coordinate fixture"))
})
local plan_input = CMat.CMatCAddressPlanInput(
  iteration, address_accesses, CMat.CMatCFragmentNamespace("coord"))
local address_projection = facet:materialize_c_address_plan(plan_input)
assert(asdl.classof(address_projection) == CMat.CMatCAddressPlanReady)
local address_plan = address_projection.plan
assert(#address_plan.cursors == 1)
assert(address_plan.cursors[1].basis == centered.basis)
assert(address_plan.cursors[1].base == xs_base)
assert(address_plan.cursors[1].step_bytes == 8)
assert(asdl.classof(address_plan:lookup(centered_id).entry.addressing) ==
  CMat.CMatCCursorAddressing)
assert(address_plan:lookup(centered_id).entry.addressing.cursor ==
  address_plan:lookup(store_id).entry.addressing.cursor)
assert(asdl.classof(address_plan:lookup(window_id).entry.addressing) ==
  CMat.CMatCDynamicWindowAddressing)
assert(asdl.classof(address_plan:lookup(absolute_id).entry.addressing) ==
  CMat.CMatCAbsoluteAddressing)
local repeated_plan = facet:materialize_c_address_plan(plan_input).plan
assert(repeated_plan.cursors[1].id == address_plan.cursors[1].id)
assert(repeated_plan.cursors[1].cursor_local.id ==
  address_plan.cursors[1].cursor_local.id)
local missing_binding_plan = facet:materialize_c_address_plan(
  CMat.CMatCAddressPlanInput(iteration,
    CMat.CMatCFragmentAccessBindingProjection({}),
    CMat.CMatCFragmentNamespace("missing")))
assert(asdl.classof(missing_binding_plan) ==
  CMat.CMatCAddressPlanRejected)
assert(asdl.classof(missing_binding_plan.issues[1]) ==
  CMat.CMatCAddressMissingBinding)
local incomplete_plan = Lower.LowerCMatCoordinateFacet(spine, iteration, {
  facet.entries[1], facet.entries[2], facet.entries[3],
}):materialize_c_address_plan(plan_input)
assert(asdl.classof(incomplete_plan) == CMat.CMatCAddressPlanRejected)
assert(asdl.classof(incomplete_plan.issues[1]) ==
  CMat.CMatCAddressMissingUse)
local duplicate_plan = Lower.LowerCMatCoordinateFacet(spine, iteration, {
  facet.entries[1], facet.entries[1], facet.entries[2], facet.entries[3],
  facet.entries[4],
}):materialize_c_address_plan(plan_input)
assert(asdl.classof(duplicate_plan) == CMat.CMatCAddressPlanRejected)
assert(asdl.classof(duplicate_plan.issues[1]) ==
  CMat.CMatCAddressAmbiguousUse)
local mismatched_iteration_plan = facet:materialize_c_address_plan(
  CMat.CMatCAddressPlanInput(Stencil.StencilKernelIteration(
    loop, counter, i32, start, stop, step, 3,
    Stencil.StencilIterationStopExclusive, Stencil.StencilProducerForward,
    iteration.trip), address_accesses, CMat.CMatCFragmentNamespace("mismatch")))
assert(asdl.classof(mismatched_iteration_plan) ==
  CMat.CMatCAddressPlanRejected)
assert(asdl.classof(mismatched_iteration_plan.issues[1]) ==
  CMat.CMatCAddressIterationDisagreement)

local zero_offset = Stencil.StencilWindowOffset(
  Stencil.StencilAxisRef(1), Stencil.StencilElementDistance(0))
local zero_id = CMat.CMatWindowMemoryUse(
  Stencil.StencilStreamRef(Stencil.StencilStreamId("window-zero")), 1)
local zero_spine = CMat.CMatMemoryUseSpine({ CMat.CMatMemoryUse(
  zero_id, xs_ref, CMat.CMatMemoryLoad,
  CMat.CMatMemoryWindowOffset(zero_offset)) })
local zero_projection = zero_spine:lower_coordinates(input)
assert(asdl.classof(zero_projection) == Lower.LowerCMatCoordinatesProjected)
local zero_coordinate = zero_projection.facet.entries[1].coordinate
assert(asdl.classof(zero_coordinate) ==
  Lower.LowerCMatWindowRelativeCoordinate)
assert(zero_coordinate.provenance.offset == zero_offset)
local zero_plan = zero_projection.facet:materialize_c_address_plan(plan_input)
assert(asdl.classof(zero_plan) == CMat.CMatCAddressPlanReady)
assert(asdl.classof(zero_plan.plan.uses[1].addressing) ==
  CMat.CMatCCursorAddressing)

local reject_domain = Stencil.StencilKernelCountedWindow1D(
  window_source, Stencil.StencilWindowAxis(
    window_extent, Stencil.StencilWindowBoundaryReject))
local reject_window = CMat.CMatMemoryUseSpine({ spine.uses[2] }):lower_coordinates(
  Lower.LowerCMatCoordinateInput(
    iteration, reject_domain, provenance, memory_projection))
assert(asdl.classof(reject_window) == Lower.LowerCMatCoordinatesRejected)
assert(asdl.classof(reject_window.issues[1]) ==
  Lower.LowerCMatCoordinateWindowBoundaryUnsupported)

local outside_offset = Stencil.StencilWindowOffset(
  Stencil.StencilAxisRef(1), Stencil.StencilElementDistance(-2))
local outside_use = CMat.CMatMemoryUse(
  CMat.CMatWindowMemoryUse(
    Stencil.StencilStreamRef(Stencil.StencilStreamId("window-outside")), 1),
  xs_ref, CMat.CMatMemoryLoad, CMat.CMatMemoryWindowOffset(outside_offset))
local outside = CMat.CMatMemoryUseSpine({ outside_use }):lower_coordinates(input)
assert(asdl.classof(outside.issues[1]) ==
  Lower.LowerCMatCoordinateWindowDistanceOutsideExtent)

local fraction_offset = Stencil.StencilWindowOffset(
  Stencil.StencilAxisRef(1), Stencil.StencilElementDistance(0.5))
local fraction_use = CMat.CMatMemoryUse(
  CMat.CMatWindowMemoryUse(
    Stencil.StencilStreamRef(Stencil.StencilStreamId("window-fraction")), 1),
  xs_ref, CMat.CMatMemoryLoad, CMat.CMatMemoryWindowOffset(fraction_offset))
local fraction = CMat.CMatMemoryUseSpine({ fraction_use }):lower_coordinates(input)
assert(asdl.classof(fraction.issues[1]) ==
  Lower.LowerCMatCoordinateWindowDistanceInvalid)

local missing_domain = CMat.CMatMemoryUseSpine({ spine.uses[2] }):lower_coordinates(
  Lower.LowerCMatCoordinateInput(
    iteration, Stencil.StencilKernelCountedDomain1D(window_source),
    provenance, memory_projection))
assert(asdl.classof(missing_domain.issues[1]) ==
  Lower.LowerCMatCoordinateWindowDomainMissing)

local missing_use = CMat.CMatMemoryUse(
  CMat.CMatStreamMemoryUse(
    Stencil.StencilStreamRef(Stencil.StencilStreamId("missing"))),
  Stencil.StencilAccessRef("missing"), CMat.CMatMemoryLoad,
  CMat.CMatMemorySelectedIndex(Stencil.StencilIndexProducer))
local missing = CMat.CMatMemoryUseSpine({ missing_use })
:lower_coordinates(input)
assert(asdl.classof(missing) == Lower.LowerCMatCoordinatesRejected)
assert(asdl.classof(missing.issues[1]) ==
  Lower.LowerCMatCoordinateAccessMissing)

local dynamic_memory = memory_fact(
  access_id, ptr, root, Mem.MemIndexValue(counter, 4, 0), Mem.MemLoad)
local no_induction = CMat.CMatMemoryUseSpine({ spine.uses[1] })
:lower_coordinates(Lower.LowerCMatCoordinateInput(
  iteration, window_domain, provenance, Mem.MemAccessProjection({
    Mem.MemAccessByIdEntry(dynamic_memory),
    Mem.MemAccessByIdEntry(absolute_memory),
  }, {}, {}, {})))
assert(asdl.classof(no_induction) == Lower.LowerCMatCoordinatesRejected)
assert(asdl.classof(no_induction.issues[1]) ==
  Lower.LowerCMatCoordinateInductionMissing)

local wrong_start_iteration = Stencil.StencilKernelIteration(
  loop, counter, i32, Code.CodeValueId("wrong_start"), stop, step, 2,
  Stencil.StencilIterationStopExclusive, Stencil.StencilProducerForward,
  iteration.trip)
local disagreement = CMat.CMatMemoryUseSpine({ spine.uses[1] })
:lower_coordinates(Lower.LowerCMatCoordinateInput(
  wrong_start_iteration, window_domain, provenance, memory_projection))
assert(asdl.classof(disagreement) ==
  Lower.LowerCMatCoordinatesRejected)
assert(asdl.classof(disagreement.issues[1]) ==
  Lower.LowerCMatCoordinateInductionDisagreement)
assert(disagreement.issues[1].axis == Lower.LowerCMatAlignmentInit)

local duplicate_provenance = Stencil.StencilAccessByKernelLaneProjection({
  provenance.entries[1], provenance.entries[1],
})
local ambiguous_access = CMat.CMatMemoryUseSpine({ spine.uses[1] })
:lower_coordinates(Lower.LowerCMatCoordinateInput(
  iteration, window_domain, duplicate_provenance, memory_projection))
assert(asdl.classof(ambiguous_access.issues[1]) ==
  Lower.LowerCMatCoordinateAccessAmbiguous)

local duplicate_memory = Mem.MemAccessProjection({
  Mem.MemAccessByIdEntry(memory), Mem.MemAccessByIdEntry(memory),
}, {}, {}, {})
local ambiguous_memory = CMat.CMatMemoryUseSpine({ spine.uses[1] })
:lower_coordinates(Lower.LowerCMatCoordinateInput(
  iteration, window_domain, Stencil.StencilAccessByKernelLaneProjection({
    provenance.entries[1],
  }), duplicate_memory))
assert(asdl.classof(ambiguous_memory.issues[1]) ==
  Lower.LowerCMatCoordinateMemoryFactAmbiguous)

local mismatched_lane = Kernel.KernelLane(
  Kernel.KernelLaneId("lane:root-mismatch"), lane.object, { access_id },
  absolute_root, i32, Mem.MemAccessContiguous, {})
local root_disagreement = CMat.CMatMemoryUseSpine({ spine.uses[1] })
:lower_coordinates(Lower.LowerCMatCoordinateInput(
  iteration, window_domain, Stencil.StencilAccessByKernelLaneProjection({
    Stencil.StencilAccessByKernelLaneEntry(mismatched_lane, xs),
  }), memory_projection))
assert(asdl.classof(root_disagreement.issues[1]) ==
  Lower.LowerCMatCoordinateRootDisagreement)

local wrong_axis_offset = Stencil.StencilWindowOffset(
  Stencil.StencilAxisRef(2), Stencil.StencilElementDistance(1))
local wrong_axis_use = CMat.CMatMemoryUse(
  CMat.CMatWindowMemoryUse(
    Stencil.StencilStreamRef(Stencil.StencilStreamId("wrong-axis")), 1),
  xs_ref, CMat.CMatMemoryLoad,
  CMat.CMatMemoryWindowOffset(wrong_axis_offset))
local wrong_axis = CMat.CMatMemoryUseSpine({ wrong_axis_use })
:lower_coordinates(input)
assert(asdl.classof(wrong_axis.issues[1]) ==
  Lower.LowerCMatCoordinateWindowAxisDisagreement)

assert(asdl.classof(facet:lookup(
  CMat.CMatSinkMemoryUse(
    Stencil.StencilSinkRef(Stencil.StencilSinkId("missing"))))) ==
  Lower.LowerCMatUseCoordinateMissing)
local ambiguous_facet = Lower.LowerCMatCoordinateFacet(spine, iteration, {
  facet.entries[1], facet.entries[1],
})
assert(asdl.classof(ambiguous_facet:lookup(centered_id)) ==
  Lower.LowerCMatUseCoordinateAmbiguous)

local function absolute_address(base, start_value, ordinal, direction, magnitude,
                                scale, const_offset, use_offset)
  return base + (start_value + direction * ordinal * magnitude) * scale
    + const_offset + use_offset
end
local function cursor_address(base, start_value, ordinal, direction, magnitude,
                              scale, const_offset, use_offset)
  local cursor0 = base + start_value * scale
  local cursor = cursor0 + ordinal * direction * magnitude * scale
  return cursor + const_offset + use_offset
end
for _, equation in ipairs({
  { 1000, 0, 5, 1, 1, 4, 0, 0 },
  { 1000, 7, 3, -1, 1, 4, 8, -4 },
  { 1000, 2, 4, 1, 3, 8, 16, 8 },
}) do
  assert(absolute_address(unpack(equation)) ==
    cursor_address(unpack(equation)))
end

io.write("test_cmat_coordinate_projection: ok\n")
