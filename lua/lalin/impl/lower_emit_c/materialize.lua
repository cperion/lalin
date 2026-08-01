-- Typed stencil-to-C materialization.  CBackend emission begins at CMAT-3.
require("lalin.schema_v2")
require("lalin.impl.stencil_plan")
local Stencil = require("lalin.schema_v2.stencil")
local CMat = require("lalin.schema_v2.c_materialize")

function Stencil.StencilAccessRead:cmat_mutability() return CMat.CMatAccessReadOnly end
function Stencil.StencilAccessWrite:cmat_mutability() return CMat.CMatAccessWriteOnly end
function Stencil.StencilAccessIndex:cmat_mutability() return CMat.CMatAccessReadOnly end
function Stencil.StencilAccessReadWrite:cmat_mutability() return CMat.CMatAccessReadWrite end
function Stencil.StencilAccessReduce:cmat_mutability() return CMat.CMatAccessReduce end
function Stencil.StencilAccessControlResult:cmat_mutability() return CMat.CMatAccessWriteOnly end
function Stencil.StencilAccessRead:cmat_const_capability() return CMat.CMatConstEligible end
function Stencil.StencilAccessIndex:cmat_const_capability() return CMat.CMatConstEligible end
function Stencil.StencilAccessWrite:cmat_const_capability() return CMat.CMatConstIneligible("write access") end
function Stencil.StencilAccessReadWrite:cmat_const_capability() return CMat.CMatConstIneligible("read-write access") end
function Stencil.StencilAccessReduce:cmat_const_capability() return CMat.CMatConstIneligible("reduction access") end
function Stencil.StencilAccessControlResult:cmat_const_capability() return CMat.CMatConstIneligible("control result") end

function Stencil.StencilLayoutScalar:cmat_restrict_capability() return CMat.CMatRestrictIneligible("scalar is not pointer-like") end
function Stencil.StencilLayoutContiguous:cmat_restrict_capability() return CMat.CMatRestrictIneligible("no declared noalias proof") end
function Stencil.StencilLayoutIndexed:cmat_restrict_capability() return CMat.CMatRestrictIneligible("no declared noalias proof") end
function Stencil.StencilLayoutAffine1D:cmat_restrict_capability() return CMat.CMatRestrictIneligible("no declared noalias proof") end
function Stencil.StencilLayoutAffineND:cmat_restrict_capability() return CMat.CMatRestrictIneligible("no declared noalias proof") end
function Stencil.StencilLayoutFieldProjection:cmat_restrict_capability() return CMat.CMatRestrictIneligible("no declared noalias proof") end
function Stencil.StencilLayoutSoAComponent:cmat_restrict_capability() return CMat.CMatRestrictIneligible("no declared noalias proof") end
function Stencil.StencilAccessDirect:cmat_restrict_capability() return self.base:cmat_restrict_capability() end
function Stencil.StencilAccessDescribed:cmat_restrict_capability() return self.base:cmat_restrict_capability() end

function Stencil.StencilAccess:cmat_canonical_binding(input)
  return CMat.CMatAccessBinding(
    Stencil.StencilAccessRef(self.name), self, input.local_id, self.ty, self.layout,
    self.role:cmat_mutability(), self.layout:cmat_restrict_capability(),
    self.role:cmat_const_capability(), Stencil.StencilAlignmentUnknown)
end
function Stencil.StencilValidationAccepted:cmat_bind(access, input)
  return CMat.CMatAccessBound(access:cmat_canonical_binding(input))
end
function Stencil.StencilValidationRejected:cmat_bind(access, input)
  return CMat.CMatAccessBindingRejected(
    CMat.CMatIssueUnsupportedAccess(access, "access layout validation rejected materialization"))
end
function Stencil.StencilAccess:cmat_binding(input)
  return self:stencil_validate():cmat_bind(self, input)
end

function Stencil.StencilProducerForward:cmat_loop_order() return CMat.CMatLoopForward end
function Stencil.StencilProducerBackward:cmat_loop_order() return CMat.CMatLoopBackward end
local function axis(index, ty, step, order)
  return CMat.CMatLoopAxis(Stencil.StencilAxisRef(index), CMat.CMatLocalId("i" .. tostring(index)), ty, step, order:cmat_loop_order())
end
function Stencil.StencilProduceRange1D:cmat_loop_plan()
  return CMat.CMatLoopPlanned({ axis(1, self.index_ty, self.step, self.order) })
end
function Stencil.StencilProduceCountedRange1D:cmat_loop_plan()
  return CMat.CMatLoopPlanned({ axis(1, self.index_ty, self.step, self.order) })
end
function Stencil.StencilProduceCountedWindow1D:cmat_loop_plan()
  return CMat.CMatLoopPlanned({
    axis(1, self.index_ty, self.step, self.order),
  })
end
local function axes_plan(axes)
  local result = {}
  for i, producer_axis in ipairs(axes) do
    result[#result + 1] = axis(i, producer_axis.index_ty, producer_axis.step, producer_axis.order)
  end
  return CMat.CMatLoopPlanned(result)
end
function Stencil.StencilProduceRangeND:cmat_loop_plan() return axes_plan(self.axes) end
function Stencil.StencilProduceWindowND:cmat_loop_plan() return axes_plan(self.axes) end
function Stencil.StencilProduceTiledND:cmat_loop_plan() return axes_plan(self.axes) end

function Stencil.StencilVectorScalarTail:cmat_tail_policy() return CMat.CMatTailScalar end
function Stencil.StencilVectorMaskTail:cmat_tail_policy() return CMat.CMatTailMask end
function Stencil.StencilVectorOverreadProvenSafe:cmat_tail_policy() return CMat.CMatTailOverreadProvenSafe end
function Stencil.StencilLaneFromTarget:cmat_lane_capability() return CMat.CMatLaneFromTarget end
function Stencil.StencilLaneNative:cmat_lane_capability() return CMat.CMatLaneNative end
function Stencil.StencilLaneFixed:cmat_lane_capability() return CMat.CMatLaneFixed(self.lanes) end
function Stencil.StencilScheduleScalar:cmat_schedule_policy() return CMat.CMatSchedulePolicy(1, 1, CMat.CMatVectorNone) end
function Stencil.StencilScheduleAutoVector:cmat_schedule_policy()
  return CMat.CMatSchedulePolicy(1, 1, CMat.CMatVectorAutovec(CMat.CMatLaneFromTarget, CMat.CMatTailScalar))
end
function Stencil.StencilScheduleUnrolled:cmat_schedule_policy() return CMat.CMatSchedulePolicy(self.factor, 1, CMat.CMatVectorNone) end
function Stencil.StencilScheduleVector:cmat_schedule_policy()
  return CMat.CMatSchedulePolicy(self.vector_unroll, self.interleave,
    CMat.CMatVectorExplicit(self.lane_policy:cmat_lane_capability(), self.tail:cmat_tail_policy()))
end

function Stencil.StencilStreamDef:cmat_stream_materialization()
  return CMat.CMatStreamInline(Stencil.StencilStreamRef(self.id), self.ty)
end
function Stencil.StencilSinkDef:cmat_sink_materialization() return self.op:cmat_sink_materialization(self.id) end
function Stencil.StencilSinkOpStore:cmat_sink_materialization(id) return CMat.CMatSinkStoreResult(Stencil.StencilSinkRef(id), self.dst) end
function Stencil.StencilSinkOpFold:cmat_sink_materialization(id) return CMat.CMatSinkInline(Stencil.StencilSinkRef(id)) end
function Stencil.StencilSinkOpScan:cmat_sink_materialization(id) return CMat.CMatSinkStoreResult(Stencil.StencilSinkRef(id), self.dst) end
function Stencil.StencilSinkOpScatterStore:cmat_sink_materialization(id) return CMat.CMatSinkStoreResult(Stencil.StencilSinkRef(id), self.dst) end
function Stencil.StencilSinkOpScatterFold:cmat_sink_materialization(id) return CMat.CMatSinkStoreResult(Stencil.StencilSinkRef(id), self.dst) end
function Stencil.StencilSinkOpAll:cmat_sink_materialization(id) return CMat.CMatSinkControlResult(Stencil.StencilSinkRef(id)) end
function Stencil.StencilSinkOpAllCompare:cmat_sink_materialization(id) return CMat.CMatSinkControlResult(Stencil.StencilSinkRef(id)) end
function Stencil.StencilSinkOpAny:cmat_sink_materialization(id) return CMat.CMatSinkControlResult(Stencil.StencilSinkRef(id)) end
function Stencil.StencilSinkOpFind:cmat_sink_materialization(id) return CMat.CMatSinkControlResult(Stencil.StencilSinkRef(id)) end

function CMat.CMatAccessCollectionReady:cmat_add_bound(binding)
  local bindings = {}
  for _, prior in ipairs(self.bindings) do bindings[#bindings + 1] = prior end
  bindings[#bindings + 1] = binding
  return CMat.CMatAccessCollectionReady(bindings)
end
function CMat.CMatAccessCollectionRejected:cmat_add_bound(binding) return self end
function CMat.CMatAccessCollectionReady:cmat_add_issue(issue) return CMat.CMatAccessCollectionRejected({ issue }) end
function CMat.CMatAccessCollectionRejected:cmat_add_issue(issue)
  local issues = {}
  for _, prior in ipairs(self.issues) do issues[#issues + 1] = prior end
  issues[#issues + 1] = issue
  return CMat.CMatAccessCollectionRejected(issues)
end
function CMat.CMatAccessBound:cmat_collect(collection) return collection:cmat_add_bound(self.binding) end
function CMat.CMatAccessBindingRejected:cmat_collect(collection) return collection:cmat_add_issue(self.issue) end
function CMat.CMatAccessCollectionRejected:cmat_finish(computation, input, loop, streams, sinks)
  return CMat.CMatRejectedComputation(computation, self.issues)
end
function CMat.CMatAccessCollectionReady:cmat_finish(computation, input, loop, streams, sinks)
  return CMat.CMatMaterializedFused(CMat.CMatFusedKernel(
    input.kernel, computation, CMat.CMatLoopNest(loop.axes, computation.schedule:cmat_schedule_policy()),
    self.bindings, streams, sinks, computation.schedule, computation.proofs))
end
function CMat.CMatLoopRejected:cmat_materialize_computation(computation, input)
  return CMat.CMatRejectedComputation(computation, { self.issue })
end
function CMat.CMatLoopPlanned:cmat_materialize_computation(computation, input)
  local collection = CMat.CMatAccessCollectionReady({})
  for _, access in ipairs(computation.accesses) do
    collection = access:cmat_binding(CMat.CMatAccessBindingInput(CMat.CMatLocalId(access.name))):cmat_collect(collection)
  end
  local streams = {}
  for _, stream in ipairs(computation.streams) do streams[#streams + 1] = stream:cmat_stream_materialization() end
  local sinks = {}
  for _, sink in ipairs(computation.sinks) do sinks[#sinks + 1] = sink:cmat_sink_materialization() end
  return collection:cmat_finish(computation, input, self, streams, sinks)
end
function Stencil.StencilComputation:cmat_materialize(input)
  return self.producer.shape:cmat_loop_plan():cmat_materialize_computation(self, input)
end
function CMat.CMatMaterializedFused:cmat_attach_kernel_provenance(provenance)
  return CMat.CMatMaterializedKernelFragment(self.kernel, provenance)
end
function CMat.CMatRejectedComputation:cmat_attach_kernel_provenance(provenance)
  return CMat.CMatRejectedKernelFragment(
    self.computation, provenance, self.issues)
end
function Stencil.StencilKernelComputationProjection:cmat_materialize_kernel(input)
  return self.computation:cmat_materialize(
    CMat.CMatMaterializationInput(input.kernel))
:cmat_attach_kernel_provenance(self.provenance)
end
