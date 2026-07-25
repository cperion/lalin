-- impl/kernel_plan.lua — typed kernel loop-fact projection and planning.
require("lalin.schema_v2")
require("lalin.impl.code_mem")
local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Value = require("lalin.schema_v2.value")
local Mem = require("lalin.schema_v2.mem")
local Effect = require("lalin.schema_v2.effect")
local Kernel = require("lalin.schema_v2.kernel")

local function sanitize(s)
  s = tostring(s):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  return s ~= "" and s or "x"
end

local function append_all(left, right)
  local out = {}
  for i = 1, #left do out[#out + 1] = left[i] end
  for i = 1, #right do out[#out + 1] = right[i] end
  return out
end

function Flow.FlowTripCountExact:kernel_trip_evidence() return Kernel.KernelTripKnown(self) end
function Flow.FlowTripCountNonNegative:kernel_trip_evidence() return Kernel.KernelTripKnown(self) end
function Flow.FlowTripCountRejected:kernel_trip_evidence(subject)
  return Kernel.KernelTripUnavailable(self, Kernel.KernelRejectNoFacts(subject, "flow trip count rejected: " .. tostring(self.reject)))
end

function Kernel.KernelTripProjection:merged(other) return Kernel.KernelTripProjection(append_all(self.entries, other.entries)) end
function Flow.FlowLoopNormalizedCounted:kernel_trip_projection() return Kernel.KernelTripProjection({ Kernel.KernelTripByLoopEntry(self.loop, self.trip_count) }) end
function Flow.FlowLoopInductionRange:kernel_trip_projection() return Kernel.KernelTripProjection({}) end
function Flow.FlowLoopInductionNoWrap:kernel_trip_projection() return Kernel.KernelTripProjection({}) end
function Flow.FlowSemanticFactSet:project_kernel_trips()
  local projection = Kernel.KernelTripProjection({})
  for _, fact in ipairs(self.facts) do projection = projection:merged(fact:kernel_trip_projection()) end
  return projection
end
function Kernel.KernelTripProjection:lookup(loop)
  for _, entry in ipairs(self.entries) do if entry.loop == loop then return Kernel.KernelTripFound(entry) end end
  return Kernel.KernelTripMissing(loop)
end
function Kernel.KernelTripFound:kernel_trip_evidence(subject) return self.entry.trip_count:kernel_trip_evidence(subject) end
function Kernel.KernelTripMissing:kernel_trip_evidence(subject)
  local trip = Flow.FlowTripCountRejected(Flow.FlowTripCountNotLoop("semantic trip evidence is unavailable for " .. self.loop.text), nil)
  return Kernel.KernelTripUnavailable(trip, Kernel.KernelRejectNoFacts(subject, "semantic trip evidence unavailable"))
end

function Flow.FlowDomainLoop:kernel_trip_projection(trip_count) return Kernel.KernelTripProjection({ Kernel.KernelTripByLoopEntry(self.loop, trip_count) }) end
function Flow.FlowDomainBlockRange:kernel_trip_projection(trip_count) return Kernel.KernelTripProjection({}) end
function Flow.FlowDomainFunction:kernel_trip_projection(trip_count) return Kernel.KernelTripProjection({}) end
function Value.AlgebraFlowCounted:kernel_trip_projection(domain) return domain:kernel_trip_projection(self.trip_count) end
function Value.AlgebraFlowMonotonic:kernel_trip_projection(domain) return Kernel.KernelTripProjection({}) end
function Value.AlgebraFlowUnrolled:kernel_trip_projection(domain) return Kernel.KernelTripProjection({}) end
function Value.AlgebraProofFlow:kernel_trip_projection() return self.guarantee:kernel_trip_projection(self.domain) end
function Value.AlgebraProofNoWrap:kernel_trip_projection() return Kernel.KernelTripProjection({}) end
function Value.AlgebraProofIdentity:kernel_trip_projection() return Kernel.KernelTripProjection({}) end
function Value.AlgebraProofReduction:kernel_trip_projection() return Kernel.KernelTripProjection({}) end
function Value.AlgebraProofComposite:kernel_trip_projection()
  local projection = Kernel.KernelTripProjection({})
  for _, proof in ipairs(self.proofs) do projection = projection:merged(proof:kernel_trip_projection()) end
  return projection
end
function Value.ReductionFact:kernel_trip_projection() return self.proof:kernel_trip_projection() end
function Value.ClosedFormFact:kernel_trip_projection() return self.proof:kernel_trip_projection() end
function Value.ValueFactSet:project_kernel_trips()
  local projection = Kernel.KernelTripProjection({})
  for _, reduction in ipairs(self.reductions) do projection = projection:merged(reduction:kernel_trip_projection()) end
  for _, closed_form in ipairs(self.closed_forms) do projection = projection:merged(closed_form:kernel_trip_projection()) end
  return projection
end

function Flow.FlowDomainLoop:kernel_reduction_contribution(reduction)
  return Kernel.KernelReductionForLoop(Kernel.KernelReductionByLoopEntry(self.loop, reduction))
end
function Flow.FlowDomainBlockRange:kernel_reduction_contribution(reduction) return Kernel.KernelReductionOutsideLoop(reduction) end
function Flow.FlowDomainFunction:kernel_reduction_contribution(reduction) return Kernel.KernelReductionOutsideLoop(reduction) end
function Kernel.KernelReductionForLoop:kernel_reduction_entries() return { self.entry } end
function Kernel.KernelReductionOutsideLoop:kernel_reduction_entries() return {} end
function Value.ReductionFact:kernel_reduction_entries() return self.domain:kernel_reduction_contribution(self):kernel_reduction_entries() end

function Flow.FlowDomainLoop:kernel_closed_form_contribution(closed_form)
  return Kernel.KernelClosedFormForLoop(Kernel.KernelClosedFormByLoopEntry(self.loop, closed_form))
end
function Flow.FlowDomainBlockRange:kernel_closed_form_contribution(closed_form) return Kernel.KernelClosedFormOutsideLoop(closed_form) end
function Flow.FlowDomainFunction:kernel_closed_form_contribution(closed_form) return Kernel.KernelClosedFormOutsideLoop(closed_form) end
function Kernel.KernelClosedFormForLoop:kernel_closed_form_entries() return { self.entry } end
function Kernel.KernelClosedFormOutsideLoop:kernel_closed_form_entries() return {} end
function Value.ClosedFormFact:kernel_closed_form_entries() return self.reduction.domain:kernel_closed_form_contribution(self):kernel_closed_form_entries() end

function Kernel.KernelLoopFactProjection:lookup_reductions(loop)
  local found = {}
  for _, entry in ipairs(self.reductions) do if entry.loop == loop then found[#found + 1] = entry end end
  if #found > 0 then return Kernel.KernelReductionFound(found) end
  return Kernel.KernelReductionMissing(loop)
end
function Kernel.KernelLoopFactProjection:lookup_closed_forms(loop)
  local found = {}
  for _, entry in ipairs(self.closed_forms) do if entry.loop == loop then found[#found + 1] = entry end end
  if #found > 0 then return Kernel.KernelClosedFormFound(found) end
  return Kernel.KernelClosedFormMissing(loop)
end
function Kernel.KernelClosedFormFound:kernel_candidate(projection, fact)
  return Kernel.KernelLoopClosedFormCandidate(self.entries[1].closed_form)
end
function Kernel.KernelClosedFormMissing:kernel_candidate(projection, fact)
  return projection:lookup_reductions(fact.loop):kernel_candidate(fact)
end
function Kernel.KernelReductionFound:kernel_candidate(fact) return Kernel.KernelLoopReductionCandidate(self.entries[1].reduction) end
function Kernel.KernelReductionMissing:kernel_candidate(fact)
  return Kernel.KernelLoopOriginalControlCandidate({ Kernel.KernelRejectNoFacts(Kernel.KernelSubjectLoop(fact.loop), "no closed-form, reduction, or skeleton candidate") })
end
function Kernel.KernelLoopCounted:kernel_candidate(projection, fact) return projection:lookup_closed_forms(fact.loop):kernel_candidate(projection, fact) end
function Kernel.KernelLoopNotCountedEvidence:kernel_candidate(projection, fact) return Kernel.KernelLoopNotCounted({ self.reject }) end
function Kernel.KernelLoopFactEntry:kernel_candidate(projection) return self.count:kernel_candidate(projection, self) end
function Flow.FlowLoopFacts:kernel_count_evidence(subject)
  if self.counted ~= nil then return Kernel.KernelLoopCounted(self.counted) end
  return Kernel.KernelLoopNotCountedEvidence(Kernel.KernelRejectNoFacts(subject, "loop is not counted"))
end

function Flow.FlowFactSet:project_kernel_loop_facts(values, trips)
  local loops, reductions, closed_forms = {}, {}, {}
  for _, reduction in ipairs(values.reductions) do reductions = append_all(reductions, reduction:kernel_reduction_entries()) end
  for _, closed_form in ipairs(values.closed_forms) do closed_forms = append_all(closed_forms, closed_form:kernel_closed_form_entries()) end
  for _, loop in ipairs(self.loops) do
    local subject = Kernel.KernelSubjectLoop(loop.loop)
    loops[#loops + 1] = Kernel.KernelLoopFactEntry(loop.loop, loop.domain, loop:kernel_count_evidence(subject), trips:lookup(loop.loop):kernel_trip_evidence(subject))
  end
  return Kernel.KernelLoopFactProjection(loops, reductions, closed_forms)
end

function Kernel.KernelLoopNotCounted:select_kernel_loop_plan() return Kernel.KernelLoopNoPlan(self.rejects) end
function Kernel.KernelLoopMissingOwner:select_kernel_loop_plan() return Kernel.KernelLoopNoPlan(self.rejects) end
function Kernel.KernelLoopRejectedFacts:select_kernel_loop_plan() return Kernel.KernelLoopNoPlan(self.rejects) end
function Kernel.KernelLoopClosedFormCandidate:select_kernel_loop_plan() return Kernel.KernelLoopPlanClosedForm(self.closed_form) end
function Kernel.KernelLoopReductionCandidate:select_kernel_loop_plan() return Kernel.KernelLoopPlanReduction(self.reduction) end
function Kernel.KernelLoopSkeletonCandidate:select_kernel_loop_plan() return Kernel.KernelLoopPlanSkeleton(self.result) end
function Kernel.KernelLoopOriginalControlCandidate:select_kernel_loop_plan() return Kernel.KernelLoopPlanOriginalControl(self.rejects) end

function Kernel.KernelTripKnown:kernel_trip_count() return self.trip_count end
function Kernel.KernelTripUnavailable:kernel_trip_count() return self.trip_count end
function Kernel.KernelTripKnown:kernel_trip_proofs(domain, proofs)
  return append_all(proofs, { Kernel.KernelProofFlow(domain, "real flow trip-count evidence retained") })
end
function Kernel.KernelTripUnavailable:kernel_trip_proofs(domain, proofs) return proofs end

function Flow.FlowCountedDomain:kernel_counter() return Kernel.KernelCounterValue(self.start) end
function Kernel.KernelLoopCounted:kernel_counter() return self.domain:kernel_counter() end
function Kernel.KernelLoopNotCountedEvidence:kernel_counter() return Kernel.KernelCounterAbsent end

local function planned(request, build, result, proofs)
  local fact = request.fact
  local all_proofs = fact.trip:kernel_trip_proofs(fact.domain, append_all(build.proofs.proofs, proofs))
  local body = Kernel.KernelBody(
    Kernel.KernelDomainFlow(build.domain, build.trip, build.counter),
    build.lanes, build.bindings, build.effects, result,
    Kernel.KernelEquivalenceProof(all_proofs))
  return Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(fact.loop.text)), Kernel.KernelSubjectLoop(fact.loop), body)
end
function Kernel.KernelLoopAnalysisReady:materialize_kernel_selection(selection, request) return selection:materialize_kernel_build(request, self.build) end
function Kernel.KernelLoopAnalysisRejected:materialize_kernel_selection(selection, request) return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(self.fact.loop), self.rejects) end
function Kernel.KernelLoopNoPlan:materialize_kernel_build(request, build) return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(request.fact.loop), self.rejects) end
function Kernel.KernelLoopPlanOriginalControl:materialize_kernel_build(request, build) return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(request.fact.loop), self.rejects) end
function Kernel.KernelLoopPlanClosedForm:materialize_kernel_build(request, build)
  return planned(request, build, Kernel.KernelResultClosedForm(self.closed_form), { Kernel.KernelProofValue(self.closed_form.proof, "closed-form fact") })
end
function Kernel.KernelLoopPlanReduction:materialize_kernel_build(request, build)
  return planned(request, build, Kernel.KernelResultReduction(self.reduction), { Kernel.KernelProofValue(self.reduction.proof, "reduction fact") })
end
function Kernel.KernelLoopPlanSkeleton:materialize_kernel_build(request, build) return planned(request, build, self.result, {}) end

function Kernel.KernelNoPlan:schedule_eligibility() return Kernel.KernelScheduleIneligible(self.subject, self.rejects) end
function Kernel.KernelPlanned:schedule_eligibility() return Kernel.KernelScheduleEligible(self) end

function Kernel.KernelLoopFactEntry:kernel_initial_analysis()
  return Kernel.KernelLoopAnalysisReady(Kernel.KernelLoopPlanBuild(
    self.domain,
    self.trip,
    self.count:kernel_counter(),
    Kernel.KernelLaneProjection({}),
    Kernel.KernelBindingProjection({}),
    Kernel.KernelEffectProjection({}),
    Kernel.KernelProofProjection({})))
end

local function append_memory_proofs(proofs, backend)
  local result = proofs
  for _, proof in ipairs(backend.proofs) do
    result = append_all(result, { Kernel.KernelProofMemory(proof, "backend memory proof retained by kernel analysis") })
  end
  return result
end

function Kernel.KernelLoopAnalysisRejected:kernel_reject(fact, reject) return self end
function Kernel.KernelLoopAnalysisReady:kernel_reject(fact, reject) return Kernel.KernelLoopAnalysisRejected(fact, { reject }) end
function Kernel.KernelLoopAnalysisRejected:kernel_append_lane(input, access, object, backend) return self end
function Kernel.KernelLoopAnalysisReady:kernel_append_lane(input, access, object, backend)
  local lane = Kernel.KernelLane(
    Kernel.KernelLaneId("lane:" .. sanitize(access.id.text)),
    object,
    { access.id },
    access.base,
    access.access.ty,
    access.pattern,
    { backend })
  local build = self.build
  return Kernel.KernelLoopAnalysisReady(Kernel.KernelLoopPlanBuild(
    build.domain, build.trip, build.counter,
    Kernel.KernelLaneProjection(append_all(build.lanes.entries, { Kernel.KernelLaneByAccessEntry(access.id, lane) })),
    build.bindings,
    build.effects,
    Kernel.KernelProofProjection(append_memory_proofs(build.proofs.proofs, backend))))
end

function Mem.MemObjectProvenance:kernel_match_value(object, value, current) return current end
function Mem.MemProvValue:kernel_match_value(object, value, current)
  if self.value == value then return Mem.MemObjectFound(object.id) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_local(object, local_id, current) return current end
function Mem.MemProvLocal:kernel_match_local(object, local_id, current)
  if self.local_id == local_id then return Mem.MemObjectFound(object.id) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_global(object, global, current) return current end
function Mem.MemProvGlobal:kernel_match_global(object, global, current)
  if self.global == global then return Mem.MemObjectFound(object.id) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_data(object, data, current) return current end
function Mem.MemProvData:kernel_match_data(object, data, current)
  if self.data == data then return Mem.MemObjectFound(object.id) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_projection(object, parent, projection, byte_offset, current) return current end
function Mem.MemProvProjection:kernel_match_projection(object, parent, projection, byte_offset, current)
  if self.parent == parent and self.projection == projection and self.byte_offset == byte_offset then return Mem.MemObjectFound(object.id) end
  return current
end

local function object_for_value(objects, access, value)
  local current = Mem.MemObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_value(object, value, current) end
  return current
end
local function object_for_local(objects, access, local_id)
  local current = Mem.MemObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_local(object, local_id, current) end
  return current
end
local function object_for_global(objects, access, global)
  local current = Mem.MemObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_global(object, global, current) end
  return current
end
local function object_for_data(objects, access, data)
  local current = Mem.MemObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_data(object, data, current) end
  return current
end
function Mem.MemBaseValue:kernel_object_for_access(objects, access) return object_for_value(objects, access, self.value) end
function Mem.MemBaseArgument:kernel_object_for_access(objects, access) return object_for_value(objects, access, self.value) end
function Mem.MemBaseLocal:kernel_object_for_access(objects, access) return object_for_local(objects, access, self.local_id) end
function Mem.MemBaseGlobal:kernel_object_for_access(objects, access) return object_for_global(objects, access, self.global) end
function Mem.MemBaseData:kernel_object_for_access(objects, access) return object_for_data(objects, access, self.data) end
function Mem.MemBaseUnknown:kernel_object_for_access(objects, access) return Mem.MemObjectMissing(access) end
function Mem.MemObjectMissing:kernel_projection_for_access(objects, access, projection, byte_offset) return self end
function Mem.MemObjectFound:kernel_projection_for_access(objects, access, projection, byte_offset)
  local current = Mem.MemObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_projection(object, self.object, projection, byte_offset, current) end
  return current
end
function Mem.MemBaseProjection:kernel_object_for_access(objects, access)
  return self.base:kernel_object_for_access(objects, access):kernel_projection_for_access(objects, access, self.projection, self.byte_offset)
end

function Mem.MemObjectMissing:kernel_analyze_object(input, analysis, access)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "memory access has no canonical object projection"))
end
function Mem.MemObjectFound:kernel_analyze_object(input, analysis, access)
  return input.mem:project_accesses():backend_for_access(access.id):kernel_analyze_backend(input, analysis, access, self.object)
end
function Mem.MemBackendMissing:kernel_analyze_backend(input, analysis, access, object)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "memory access has no backend safety projection"))
end
function Mem.MemBackendFound:kernel_analyze_backend(input, analysis, access, object)
  return self.backend.trap:kernel_accept_trap(input, analysis, access, object, self.backend)
end
function Mem.MemMayTrap:kernel_accept_trap(input, analysis, access, object, backend)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "potentially trapping memory access cannot enter a kernel"))
end
function Mem.MemCheckedTrap:kernel_accept_trap(input, analysis, access, object, backend)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "checked-trap ordering cannot enter a kernel"))
end
function Mem.MemNonTrapping:kernel_accept_trap(input, analysis, access, object, backend)
  return backend.bounds:kernel_accept_bounds(input, analysis, access, object, backend)
end
function Mem.MemBoundsUnknown:kernel_accept_bounds(input, analysis, access, object, backend)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "memory bounds are not proven"))
end
function Mem.MemBoundsInObject:kernel_accept_bounds(input, analysis, access, object, backend) return backend.movement:kernel_accept_movement(input, analysis, access, object, backend) end
function Mem.MemBoundsRange:kernel_accept_bounds(input, analysis, access, object, backend) return backend.movement:kernel_accept_movement(input, analysis, access, object, backend) end
function Mem.MemBoundsAssumed:kernel_accept_bounds(input, analysis, access, object, backend) return backend.movement:kernel_accept_movement(input, analysis, access, object, backend) end
function Mem.MemMovementPinned:kernel_accept_movement(input, analysis, access, object, backend)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "pinned memory access cannot enter a kernel: " .. self.reason))
end
function Mem.MemMovementMovable:kernel_accept_movement(input, analysis, access, object, backend) return analysis:kernel_append_lane(input, access, object, backend) end

function Kernel.KernelLoopAnalysisRejected:kernel_add_access(input, access) return self end
function Kernel.KernelLoopAnalysisReady:kernel_add_access(input, access)
  return access.base:kernel_object_for_access(input.mem.objects, access.id):kernel_analyze_object(input, self, access)
end
function Graph.GraphLoop:kernel_analyze_memory(input, analysis)
  local current = analysis
  for _, member in ipairs(self.body) do
    for _, access in ipairs(input.mem.accesses) do
      if access.func == self.func and access.block == member then current = current:kernel_add_access(input, access) end
    end
  end
  return current
end

function Kernel.KernelLaneProjection:lookup(access)
  for _, entry in ipairs(self.entries) do if entry.access == access then return Kernel.KernelLaneFound(entry) end end
  return Kernel.KernelLaneMissing(access)
end
function Kernel.KernelBindingProjection:lookup(value)
  for _, entry in ipairs(self.entries) do if entry.value == value then return Kernel.KernelBindingFound(entry) end end
  return Kernel.KernelBindingMissing(value)
end
function Kernel.KernelEffectProjection:lookup(inst)
  for _, entry in ipairs(self.entries) do if entry.inst == inst then return Kernel.KernelEffectFound(entry) end end
  return Kernel.KernelEffectMissing(inst)
end
function Kernel.KernelBindingFound:kernel_effect_value() return Kernel.KernelExprKernelValue(self.entry.binding.id) end
function Kernel.KernelBindingMissing:kernel_effect_value() return Kernel.KernelExprValue(self.value) end

function Kernel.KernelLoopAnalysisRejected:kernel_add_binding(input, value, ty, expr) return self end
function Kernel.KernelLoopAnalysisReady:kernel_add_binding(input, value, ty, expr)
  local build = self.build
  local binding = Kernel.KernelBinding(Kernel.KernelValueId("kernel-value:" .. sanitize(value.text)), ty, expr)
  return Kernel.KernelLoopAnalysisReady(Kernel.KernelLoopPlanBuild(
    build.domain, build.trip, build.counter, build.lanes,
    Kernel.KernelBindingProjection(append_all(build.bindings.entries, { Kernel.KernelBindingByCodeValueEntry(value, binding) })),
    build.effects, build.proofs))
end
function Kernel.KernelLoopAnalysisRejected:kernel_add_effect(input, inst, effect) return self end
function Kernel.KernelLoopAnalysisReady:kernel_add_effect(input, inst, effect)
  local build = self.build
  return Kernel.KernelLoopAnalysisReady(Kernel.KernelLoopPlanBuild(
    build.domain, build.trip, build.counter, build.lanes, build.bindings,
    Kernel.KernelEffectProjection(append_all(build.effects.entries, { Kernel.KernelEffectByInstructionEntry(inst, effect) })),
    build.proofs))
end
function Kernel.KernelLoopAnalysisRejected:kernel_add_proof(input, proof) return self end
function Kernel.KernelLoopAnalysisReady:kernel_add_proof(input, proof)
  local build = self.build
  return Kernel.KernelLoopAnalysisReady(Kernel.KernelLoopPlanBuild(
    build.domain, build.trip, build.counter, build.lanes, build.bindings, build.effects,
    Kernel.KernelProofProjection(append_all(build.proofs.proofs, { proof }))))
end

function Effect.OpEffect:kernel_analyze_effect(input, analysis)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectEffect(self, "effect is outside the canonical kernel vocabulary"))
end
function Effect.EffectRead:kernel_analyze_effect(input, analysis) return analysis:kernel_add_proof(input, Kernel.KernelProofEffect(self, "read effect retained by kernel analysis")) end
function Effect.EffectWrite:kernel_analyze_effect(input, analysis) return analysis:kernel_add_proof(input, Kernel.KernelProofEffect(self, "write effect retained by kernel analysis")) end
function Effect.EffectRetain:kernel_analyze_effect(input, analysis) return analysis:kernel_add_proof(input, Kernel.KernelProofEffect(self, "retain effect retained by kernel analysis")) end
function Effect.EffectNoEscape:kernel_analyze_effect(input, analysis) return analysis:kernel_add_proof(input, Kernel.KernelProofEffect(self, "no-escape effect retained by kernel analysis")) end
function Effect.EffectNoTrap:kernel_analyze_effect(input, analysis) return analysis:kernel_add_proof(input, Kernel.KernelProofEffect(self, "no-trap effect retained by kernel analysis")) end
function Effect.EffectInvalidate:kernel_analyze_effect(input, analysis) return analysis:kernel_reject(input.fact, Kernel.KernelRejectEffect(self, "invalidate effect cannot enter a kernel")) end
function Effect.EffectMayTrap:kernel_analyze_effect(input, analysis) return analysis:kernel_reject(input.fact, Kernel.KernelRejectEffect(self, "may-trap effect cannot enter a kernel")) end
function Effect.EffectVolatile:kernel_analyze_effect(input, analysis) return analysis:kernel_reject(input.fact, Kernel.KernelRejectEffect(self, "volatile effect cannot enter a kernel")) end
function Effect.EffectAtomic:kernel_analyze_effect(input, analysis) return analysis:kernel_reject(input.fact, Kernel.KernelRejectEffect(self, "atomic effect is not supported by canonical kernel planning")) end
function Effect.EffectUnknown:kernel_analyze_effect(input, analysis) return analysis:kernel_reject(input.fact, Kernel.KernelRejectEffect(self, "unknown effect cannot enter a kernel")) end
function Effect.EffectFactSet:kernel_analyze_instruction_effects(input, analysis, inst)
  local current = analysis
  for _, entry in ipairs(self.insts) do
    if entry.inst == inst.id then
      for _, effect in ipairs(entry.effects) do current = effect:kernel_analyze_effect(input, current) end
    end
  end
  return current
end
function Mem.MemIndexNone:kernel_index_expr() return Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, require("lalin.schema_v2.core").LitInt("0"))) end
function Mem.MemIndexValue:kernel_index_expr() return Value.ValueExprValue(self.value) end
function Mem.MemIndexInduction:kernel_index_expr() return Value.ValueExprValue(self.induction.value) end
function Kernel.KernelLaneMissing:kernel_bind_load(input, analysis, op, access)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "load has no analyzed kernel lane"))
end
function Kernel.KernelLaneFound:kernel_bind_load(input, analysis, op, access)
  return analysis:kernel_add_binding(input, op.dst, op.access.ty, Kernel.KernelExprLaneLoad(self.entry.lane, access.index:kernel_index_expr()))
end
function Kernel.KernelLaneMissing:kernel_store_effect(input, analysis, op, access, inst)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "store has no analyzed kernel lane"))
end
function Kernel.KernelLaneFound:kernel_store_effect(input, analysis, op, access, inst)
  local value = analysis.build.bindings:lookup(op.value):kernel_effect_value()
  return analysis:kernel_add_effect(input, inst, Kernel.KernelEffectStore(self.entry.lane, access.index:kernel_index_expr(), value))
end

local function access_for_instruction(input, func, block, inst)
  local missing = Mem.MemAccessMissing(Mem.MemAccessId("access:" .. func.name .. ":" .. block.id.text .. ":" .. inst.id.text))
  local lookup = missing
  for _, access in ipairs(input.mem.accesses) do
    if access.func == func.id and access.block.block == block.id and access.inst == inst.id then lookup = Mem.MemAccessFound(access) end
  end
  return lookup
end
function Mem.MemAccessMissing:kernel_load_instruction(input, analysis, op, inst)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(self.access, "load instruction has no memory fact"))
end
function Mem.MemAccessFound:kernel_load_instruction(input, analysis, op, inst) return analysis.build.lanes:lookup(self.access.id):kernel_bind_load(input, analysis, op, self.access) end
function Mem.MemAccessMissing:kernel_store_instruction(input, analysis, op, inst)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(self.access, "store instruction has no memory fact"))
end
function Mem.MemAccessFound:kernel_store_instruction(input, analysis, op, inst) return analysis.build.lanes:lookup(self.access.id):kernel_store_effect(input, analysis, op, self.access, inst) end

function Code.CodeInstOp:kernel_analyze_instruction(input, func, block, inst, analysis)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedSubject(Kernel.KernelSubjectLoop(input.fact.loop), "instruction is outside the canonical kernel vocabulary: " .. tostring(self)))
end
function Code.CodeInstConst:kernel_analyze_instruction(input, func, block, inst, analysis) return analysis:kernel_add_binding(input, self.dst, self.const.ty, Kernel.KernelExprAlgebra(Value.ValueExprConst(self.const))) end
function Code.CodeInstAlias:kernel_analyze_instruction(input, func, block, inst, analysis) return analysis:kernel_add_binding(input, self.dst, self.ty, Kernel.KernelExprValue(self.src)) end
function Code.CodeInstUnary:kernel_analyze_instruction(input, func, block, inst, analysis) return analysis:kernel_add_binding(input, self.dst, self.ty, Kernel.KernelExprAlgebra(Value.ValueExprUnary(self.op, Value.ValueExprValue(self.value), self.ty))) end
function Code.CodeInstBinary:kernel_analyze_instruction(input, func, block, inst, analysis) return analysis:kernel_add_binding(input, self.dst, self.ty, Kernel.KernelExprAlgebra(Value.ValueExprBinary(self.op, Value.ValueExprValue(self.lhs), Value.ValueExprValue(self.rhs), self.ty, self.semantics))) end
function Code.CodeInstCompare:kernel_analyze_instruction(input, func, block, inst, analysis) return analysis:kernel_add_binding(input, self.dst, Code.CodeTyBool8, Kernel.KernelExprAlgebra(Value.ValueExprCmp(self.op, self.operand_ty, Value.ValueExprValue(self.lhs), Value.ValueExprValue(self.rhs)))) end
function Code.CodeInstCast:kernel_analyze_instruction(input, func, block, inst, analysis) return analysis:kernel_add_binding(input, self.dst, self.to, Kernel.KernelExprAlgebra(Value.ValueExprCast(self.op, self.from, self.to, Value.ValueExprValue(self.value)))) end
function Code.CodeInstSelect:kernel_analyze_instruction(input, func, block, inst, analysis) return analysis:kernel_add_binding(input, self.dst, self.ty, Kernel.KernelExprAlgebra(Value.ValueExprSelect(Value.ValueExprValue(self.cond), Value.ValueExprValue(self.then_value), Value.ValueExprValue(self.else_value)))) end
function Code.CodeInstLoad:kernel_analyze_instruction(input, func, block, inst, analysis) return access_for_instruction(input, func, block, inst):kernel_load_instruction(input, analysis, self, Graph.GraphInstRef(func.id, block.id, inst.id)) end
function Code.CodeInstStore:kernel_analyze_instruction(input, func, block, inst, analysis) return access_for_instruction(input, func, block, inst):kernel_store_instruction(input, analysis, self, Graph.GraphInstRef(func.id, block.id, inst.id)) end

function Kernel.KernelLoopAnalysisRejected:kernel_apply_instruction(input, func, block, inst) return self end
function Kernel.KernelLoopAnalysisReady:kernel_apply_instruction(input, func, block, inst) return inst.op:kernel_analyze_instruction(input, func, block, inst, self) end
function Kernel.KernelLoopAnalysisRejected:kernel_continue_instruction(input, func, block, inst) return self end
function Kernel.KernelLoopAnalysisReady:kernel_continue_instruction(input, func, block, inst)
  return input.effects:kernel_analyze_instruction_effects(input, self, inst):kernel_apply_instruction(input, func, block, inst)
end
function Code.CodeFunc:kernel_analyze_owned_loop(input, loop)
  local analysis = loop:kernel_analyze_memory(input, input.fact:kernel_initial_analysis())
  for _, member in ipairs(loop.body) do
    for _, block in ipairs(self.blocks) do
      if block.id == member.block then
        for _, inst in ipairs(block.insts) do analysis = analysis:kernel_continue_instruction(input, self, block, inst) end
      end
    end
  end
  return analysis
end
function Graph.GraphLoop:kernel_analyze_owner(input)
  local analysis = Kernel.KernelLoopAnalysisRejected(input.fact, { Kernel.KernelRejectIncompleteFunction(self.func, "graph loop has no CodeFunc owner") })
  for _, func in ipairs(input.module.funcs) do if func.id == self.func then analysis = func:kernel_analyze_owned_loop(input, self) end end
  return analysis
end
function Graph.CodeGraph:kernel_analyze_loop(input)
  local analysis = Kernel.KernelLoopAnalysisRejected(input.fact, { Kernel.KernelRejectNoFacts(Kernel.KernelSubjectLoop(input.fact.loop), "graph has no owner for loop") })
  for _, func_graph in ipairs(self.funcs) do
    for _, loop in ipairs(func_graph.loops) do if loop.id == input.fact.loop then analysis = loop:kernel_analyze_owner(input) end end
  end
  return analysis
end
function Kernel.KernelLoopAnalysisInput:analyze_kernel_loop() return self.graph:kernel_analyze_loop(self) end

function Kernel.KernelModulePlanRequest:plan_kernels()
  local projection = self.flow:project_kernel_loop_facts(self.values, self.trips)
  local plans = {}
  for _, fact in ipairs(projection.loops) do
    local candidate = fact:kernel_candidate(projection)
    local analysis = Kernel.KernelLoopAnalysisInput(self.module, self.graph, self.flow, self.values, self.mem, self.effects, fact, candidate):analyze_kernel_loop()
    local request = Kernel.KernelLoopPlanRequest(fact, candidate, analysis)
    plans[#plans + 1] = analysis:materialize_kernel_selection(candidate:select_kernel_loop_plan(), request)
  end
  return Kernel.KernelModulePlan(self.module.id, self.flow, self.values, self.mem, self.effects, plans)
end
function Mem.MemSemanticFactSet:plan_kernels(module, graph, flow, values, effects)
  return Kernel.KernelModulePlanRequest(module, graph, flow, values, self, effects, values:project_kernel_trips()):plan_kernels()
end
