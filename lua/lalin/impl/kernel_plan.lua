-- impl/kernel_plan.lua — typed kernel loop-fact projection and planning.
require("lalin.schema_v2")
local Code = require("lalin.schema_v2.code")
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

local function planned(request, result, proofs)
  local fact = request.fact
  local body = Kernel.KernelBody(
    Kernel.KernelDomainFlow(fact.domain, fact.trip, nil),
    request.lanes, request.bindings, request.effects, result,
    Kernel.KernelEquivalenceProof(fact.trip:kernel_trip_proofs(fact.domain, proofs)))
  return Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(fact.loop.text)), Kernel.KernelSubjectLoop(fact.loop), body)
end
function Kernel.KernelLoopNoPlan:materialize_kernel_loop(request) return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(request.fact.loop), self.rejects) end
function Kernel.KernelLoopPlanOriginalControl:materialize_kernel_loop(request) return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(request.fact.loop), self.rejects) end
function Kernel.KernelLoopPlanClosedForm:materialize_kernel_loop(request)
  return planned(request, Kernel.KernelResultClosedForm(self.closed_form), append_all(request.proofs, { Kernel.KernelProofValue(self.closed_form.proof, "closed-form fact") }))
end
function Kernel.KernelLoopPlanReduction:materialize_kernel_loop(request)
  return planned(request, Kernel.KernelResultReduction(self.reduction), append_all(request.proofs, { Kernel.KernelProofValue(self.reduction.proof, "reduction fact") }))
end
function Kernel.KernelLoopPlanSkeleton:materialize_kernel_loop(request) return planned(request, self.result, request.proofs) end

function Kernel.KernelNoPlan:schedule_eligibility() return Kernel.KernelScheduleIneligible(self.subject, self.rejects) end
function Kernel.KernelPlanned:schedule_eligibility() return Kernel.KernelScheduleEligible(self) end

function Kernel.KernelModulePlanRequest:plan_kernels()
  local projection = self.flow:project_kernel_loop_facts(self.values, self.trips)
  local plans = {}
  for _, fact in ipairs(projection.loops) do
    local candidate = fact:kernel_candidate(projection)
    local request = Kernel.KernelLoopPlanRequest(fact, candidate, {}, {}, {}, {})
    plans[#plans + 1] = candidate:select_kernel_loop_plan():materialize_kernel_loop(request)
  end
  return Kernel.KernelModulePlan(self.mem.module, self.flow, self.values, self.mem, self.effects, plans)
end
function Mem.MemSemanticFactSet:plan_kernels(flow, values, mem, effects)
  return Kernel.KernelModulePlanRequest(flow, values, mem, effects, values:project_kernel_trips()):plan_kernels()
end
