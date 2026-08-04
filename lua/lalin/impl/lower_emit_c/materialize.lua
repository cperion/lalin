-- Typed stencil-to-C materialization.  CBackend emission begins at CMAT-3.
require("lalin.schema")
require("lalin.impl.stencil_plan")
local Stencil = require("lalin.schema.stencil")
local CMat = require("lalin.schema.c_materialize")

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

function Stencil.StencilFusionLegalityFact:cmat_alias_pair_contribution(_input)
  return Stencil.StencilAccessAliasPairNotMatched
end
function Stencil.StencilFusionAccessAliasRelation:cmat_alias_pair_contribution(input)
  if (self.left == input.left and self.right == input.right)
      or (self.left == input.right and self.right == input.left) then
    return Stencil.StencilAccessAliasPairMatched(self.relation)
  end
  return Stencil.StencilAccessAliasPairNotMatched
end
function Stencil.StencilAccessAliasPairMatched:cmat_add_alias_evidence(evidence)
  local relations = {}
  for i = 1, #evidence.relations do relations[i] = evidence.relations[i] end
  relations[#relations + 1] = self.relation
  return Stencil.StencilAccessAliasPairEvidence(relations)
end
function Stencil.StencilAccessAliasPairNotMatched:cmat_add_alias_evidence(evidence)
  return evidence
end
function Stencil.StencilFusionLegality:cmat_alias_pair_lookup(input)
  local evidence = Stencil.StencilAccessAliasPairEvidence({})
  for i = 1, #self.facts do
    evidence = self.facts[i]:cmat_alias_pair_contribution(input)
      :cmat_add_alias_evidence(evidence)
  end
  return evidence:cmat_alias_pair_lookup()
end
function Stencil.StencilAccessAliasPairEvidence:cmat_alias_pair_lookup()
  if #self.relations == 0 then return Stencil.StencilAccessAliasPairMissing end
  if #self.relations == 1 then
    return Stencil.StencilAccessAliasPairFound(self.relations[1])
  end
  return Stencil.StencilAccessAliasPairAmbiguous(#self.relations)
end
function Stencil.StencilComputation:cmat_access_restrict_decision(access)
  local decision = Stencil.StencilAccessRestrictDerived
  for i = 1, #self.accesses do
    local other = Stencil.StencilAccessRef(self.accesses[i].name)
    if other ~= access then
      decision = decision:cmat_restrict_step(Stencil.StencilAccessRestrictStepInput(
        other, self.legality:cmat_alias_pair_lookup(
          Stencil.StencilAccessAliasPairInput(access, other))))
    end
  end
  return decision
end
function Stencil.StencilAccessRestrictDerived:cmat_restrict_step(input)
  return input.lookup:cmat_restrict_decision(input.other)
end
function Stencil.StencilAccessRestrictMissing:cmat_restrict_step(_input) return self end
function Stencil.StencilAccessRestrictContradicted:cmat_restrict_step(_input) return self end
function Stencil.StencilAccessRestrictAmbiguous:cmat_restrict_step(_input) return self end
function Stencil.StencilAccessAliasPairFound:cmat_restrict_decision(other)
  return self.relation:cmat_restrict_decision(other)
end
function Stencil.StencilAccessAliasPairMissing:cmat_restrict_decision(other)
  return Stencil.StencilAccessRestrictMissing(other)
end
function Stencil.StencilAccessAliasPairAmbiguous:cmat_restrict_decision(other)
  return Stencil.StencilAccessRestrictAmbiguous(other, self.count)
end
function Stencil.StencilAliasNoAlias:cmat_restrict_decision(_other)
  return Stencil.StencilAccessRestrictDerived
end
function Stencil.StencilAliasUnknown:cmat_restrict_decision(other)
  return Stencil.StencilAccessRestrictContradicted(other, self)
end
function Stencil.StencilAliasMayAlias:cmat_restrict_decision(other)
  return Stencil.StencilAccessRestrictContradicted(other, self)
end
function Stencil.StencilAccessRestrictDerived:cmat_restrict_capability()
  return CMat.CMatRestrictEligible
end
function Stencil.StencilAccessRestrictMissing:cmat_restrict_capability()
  return CMat.CMatRestrictIneligible("missing declared noalias relation")
end
function Stencil.StencilAccessRestrictContradicted:cmat_restrict_capability()
  return CMat.CMatRestrictIneligible("declared alias relation prevents restrict")
end
function Stencil.StencilAccessRestrictAmbiguous:cmat_restrict_capability()
  return CMat.CMatRestrictIneligible("ambiguous declared alias relation")
end
function Stencil.StencilComputation:cmat_access_binding_input(access)
  local ref = Stencil.StencilAccessRef(access.name)
  return CMat.CMatAccessBindingInput(
    CMat.CMatLocalId(access.name), self:cmat_access_restrict_decision(ref))
end

function Stencil.StencilAccessAliasPairLookup:cmat_all_compare_pair_evidence()
  return CMat.CMatNoAliasMissing("declared alias relation for all-compare lanes is absent")
end
function Stencil.StencilAccessAliasPairFound:cmat_all_compare_pair_evidence()
  return self.relation:cmat_all_compare_pair_evidence()
end
function Stencil.StencilAccessAliasPairMissing:cmat_all_compare_pair_evidence()
  return CMat.CMatNoAliasMissing("missing declared alias relation")
end
function Stencil.StencilAccessAliasPairAmbiguous:cmat_all_compare_pair_evidence()
  return CMat.CMatNoAliasMissing("ambiguous declared alias relation")
end
function Stencil.StencilAliasFact:cmat_all_compare_pair_evidence()
  return CMat.CMatNoAliasMissing("declared alias relation is not no-alias")
end
function Stencil.StencilAliasNoAlias:cmat_all_compare_pair_evidence()
  return CMat.CMatNoAliasDeclared
end

function Stencil.StencilAccess:cmat_canonical_binding(input)
  return CMat.CMatAccessBinding(
    Stencil.StencilAccessRef(self.name), self, input.local_id, self.ty, self.layout,
    self.role:cmat_mutability(), input.restrict:cmat_restrict_capability(),
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

function CMat.CMatMemoryUseContribution:cmat_append_memory_uses(spine)
  local uses = {}
  for i = 1, #spine.uses do uses[i] = spine.uses[i] end
  for i = 1, #self.uses do uses[#uses + 1] = self.uses[i] end
  return CMat.CMatMemoryUseSpine(uses)
end
local function no_memory_uses()
  return CMat.CMatMemoryUseContribution({})
end
local function selected_memory_use(id, access, role, selection)
  return CMat.CMatMemoryUse(
    id, access, role, CMat.CMatMemorySelectedIndex(selection))
end

function Stencil.StencilStreamIndex:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilStreamAccess:cmat_memory_uses(definition)
  return CMat.CMatMemoryUseContribution({
    selected_memory_use(
      CMat.CMatStreamMemoryUse(Stencil.StencilStreamRef(definition.id)),
      self.access, CMat.CMatMemoryLoad, self.index),
  })
end
function Stencil.StencilStreamWindowAccess:cmat_memory_uses(definition)
  local uses = {}
  local stream = Stencil.StencilStreamRef(definition.id)
  for ordinal = 1, #self.offsets do
    uses[#uses + 1] = CMat.CMatMemoryUse(
      CMat.CMatWindowMemoryUse(stream, ordinal), self.access,
      CMat.CMatMemoryLoad, CMat.CMatMemoryWindowOffset(self.offsets[ordinal]))
  end
  return CMat.CMatMemoryUseContribution(uses)
end
function Stencil.StencilStreamConst:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilStreamValueExpr:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilStreamAlias:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilStreamZip:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilStreamSelect:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilStreamMask:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilStreamGather:cmat_memory_uses(definition)
  return CMat.CMatMemoryUseContribution({
    selected_memory_use(
      CMat.CMatStreamMemoryUse(Stencil.StencilStreamRef(definition.id)),
      self.source, CMat.CMatMemoryLoad,
      Stencil.StencilIndexExplicit(Stencil.StencilIndexStream(self.index_stream))),
  })
end

function CMat.CMatPointMemoryUseAssembly:cmat_append_point_memory_use(use)
  local uses = {}
  for i = 1, #self.uses do uses[i] = self.uses[i] end
  uses[#uses + 1] = use
  return CMat.CMatPointMemoryUseAssembly(
    self.stream, uses, self.next_window_ordinal + 1)
end
function Stencil.StencilPointInput:cmat_point_memory_uses(assembly)
  return assembly
end
function Stencil.StencilPointWindowInput:cmat_point_memory_uses(assembly)
  local result = assembly
  for i = 1, #self.offsets do
    result = result:cmat_append_point_memory_use(CMat.CMatMemoryUse(
      CMat.CMatWindowMemoryUse(result.stream, result.next_window_ordinal),
      self.access, CMat.CMatMemoryLoad,
      CMat.CMatMemoryWindowOffset(self.offsets[i])))
  end
  return result
end
function Stencil.StencilPointConst:cmat_point_memory_uses(assembly)
  return assembly
end
function Stencil.StencilPointUnary:cmat_point_memory_uses(assembly)
  return self.arg:cmat_point_memory_uses(assembly)
end
function Stencil.StencilPointBinary:cmat_point_memory_uses(assembly)
  return self.right:cmat_point_memory_uses(
    self.left:cmat_point_memory_uses(assembly))
end
function Stencil.StencilPointCast:cmat_point_memory_uses(assembly)
  return self.arg:cmat_point_memory_uses(assembly)
end
function Stencil.StencilPointPredicate:cmat_point_memory_uses(assembly)
  return self.arg:cmat_point_memory_uses(assembly)
end
function Stencil.StencilPointCompare:cmat_point_memory_uses(assembly)
  return self.right:cmat_point_memory_uses(
    self.left:cmat_point_memory_uses(assembly))
end
function Stencil.StencilPointSelect:cmat_point_memory_uses(assembly)
  local result = self.cond:cmat_point_memory_uses(assembly)
  result = self.then_expr:cmat_point_memory_uses(result)
  return self.else_expr:cmat_point_memory_uses(result)
end
function Stencil.StencilStreamMap:cmat_memory_uses(definition)
  local assembly = self.expr:cmat_point_memory_uses(
    CMat.CMatPointMemoryUseAssembly(
      Stencil.StencilStreamRef(definition.id), {}, 1))
  return CMat.CMatMemoryUseContribution(assembly.uses)
end

function Stencil.StencilSinkOpStore:cmat_memory_uses(definition)
  return CMat.CMatMemoryUseContribution({
    selected_memory_use(
      CMat.CMatSinkMemoryUse(Stencil.StencilSinkRef(definition.id)),
      self.dst, CMat.CMatMemoryStore, self.index),
  })
end
function Stencil.StencilFoldReturnsValue:cmat_fold_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilFoldStores:cmat_fold_memory_uses(definition)
  return CMat.CMatMemoryUseContribution({
    selected_memory_use(
      CMat.CMatSinkMemoryUse(Stencil.StencilSinkRef(definition.id)),
      self.access, CMat.CMatMemoryStore, self.index),
  })
end
function Stencil.StencilSinkOpFold:cmat_memory_uses(definition)
  return self.destination:cmat_fold_memory_uses(definition)
end
function Stencil.StencilSinkOpScan:cmat_memory_uses(definition)
  return CMat.CMatMemoryUseContribution({
    selected_memory_use(
      CMat.CMatSinkMemoryUse(Stencil.StencilSinkRef(definition.id)),
      self.dst, CMat.CMatMemoryStore,
      Stencil.StencilIndexExplicit(Stencil.StencilIndexAxis(self.axis))),
  })
end
function Stencil.StencilSinkOpScatterStore:cmat_memory_uses(definition)
  return CMat.CMatMemoryUseContribution({
    selected_memory_use(
      CMat.CMatSinkMemoryUse(Stencil.StencilSinkRef(definition.id)),
      self.dst, CMat.CMatMemoryStore,
      Stencil.StencilIndexExplicit(Stencil.StencilIndexStream(self.index))),
  })
end
function Stencil.StencilSinkOpScatterFold:cmat_memory_uses(definition)
  return CMat.CMatMemoryUseContribution({
    selected_memory_use(
      CMat.CMatSinkMemoryUse(Stencil.StencilSinkRef(definition.id)),
      self.dst, CMat.CMatMemoryStore,
      Stencil.StencilIndexExplicit(Stencil.StencilIndexStream(self.index))),
  })
end
function Stencil.StencilSinkOpAll:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilSinkOpAny:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilSinkOpFind:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilSinkOpAllCompare:cmat_memory_uses(_definition)
  return no_memory_uses()
end
function Stencil.StencilComputation:cmat_memory_use_spine()
  local spine = CMat.CMatMemoryUseSpine({})
  for i = 1, #self.streams do
    spine = self.streams[i].op:cmat_memory_uses(self.streams[i])
      :cmat_append_memory_uses(spine)
  end
  for i = 1, #self.sinks do
    spine = self.sinks[i].op:cmat_memory_uses(self.sinks[i])
      :cmat_append_memory_uses(spine)
  end
  return spine
end
function CMat.CMatFusedKernel:cmat_memory_use_spine()
  return self.computation:cmat_memory_use_spine()
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
    collection = access:cmat_binding(computation:cmat_access_binding_input(access))
      :cmat_collect(collection)
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
