-- impl/schedule_plan.lua — typed schedule candidates and capabilities.
require("lalin.schema")
local Backend = require("lalin.schema.backend")
local Kernel = require("lalin.schema.kernel")
local Schedule = require("lalin.schema.schedule")

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

function Schedule.ScheduleEmitterScalar:schedule_emitter_name() return "scalar" end
function Schedule.ScheduleEmitterVector:schedule_emitter_name() return "vector" end
function Schedule.ScheduleEmitterClosedForm:schedule_emitter_name() return "closed_form" end
function Schedule.ScheduleEmitterFallback:schedule_emitter_name() return "fallback" end

function Schedule.ScheduleEmitterExecutable:schedule_candidate_decision(form, cursor)
  return Schedule.ScheduleCandidateSelected(form, self, cursor.rejects)
end
function Schedule.ScheduleEmitterRejected:schedule_candidate_decision(form, cursor)
  return Schedule.ScheduleCandidateRejected(self.rejects)
end
function Schedule.ScheduleVectorCandidate:attempt_schedule(cursor) return self.capability:schedule_candidate_decision(self.form, cursor) end
function Schedule.ScheduleScalarCandidate:attempt_schedule(cursor) return self.capability:schedule_candidate_decision(self.form, cursor) end
function Schedule.ScheduleClosedFormCandidate:attempt_schedule(cursor) return self.capability:schedule_candidate_decision(Schedule.ScheduleClosedForm, cursor) end
function Schedule.ScheduleCandidateSelected:continue_schedule_selection(cursor)
  return Schedule.ScheduleSelectionPlanned(self.form, self.capability, self.rejected_alternatives)
end
function Schedule.ScheduleCandidateRejected:continue_schedule_selection(cursor)
  return cursor:select_kernel_schedule_from(cursor.ordinal + 1, append_all(cursor.rejects, self.rejects))
end
function Schedule.ScheduleCandidateCursor:select_kernel_schedule_from(ordinal, rejects)
  if ordinal > #self.candidates then return Schedule.ScheduleSelectionNoPlan(rejects) end
  local cursor = Schedule.ScheduleCandidateCursor(self.candidates, ordinal, rejects)
  return self.candidates[ordinal]:attempt_schedule(cursor):continue_schedule_selection(cursor)
end
function Schedule.SchedulePlanInput:select_kernel_schedule()
  return Schedule.ScheduleCandidateCursor(self.candidates, 1, {}):select_kernel_schedule_from(1, {})
end

function Schedule.ScheduleSelectionNoPlan:to_kernel_schedule(plan) return Schedule.ScheduleNoPlan(plan.id, self.rejects) end
function Schedule.ScheduleSelectionPlanned:to_kernel_schedule(plan)
  local name = self.capability.kind:schedule_emitter_name()
  return Schedule.SchedulePlanned(
    Schedule.ScheduleId("schedule:" .. sanitize(plan.id.text) .. ":" .. name),
    plan.id, self.form, self.capability.proofs, self.rejected_alternatives)
end

local function scalar_capability()
  return Schedule.ScheduleEmitterExecutable(
    Schedule.ScheduleEmitterScalar, "scalar lowering available",
    { Schedule.ScheduleProofTarget("scalar semantic emitter is available"), Schedule.ScheduleProofProfit("scalar schedule is the deterministic fallback") })
end
local function closed_capability()
  return Schedule.ScheduleEmitterExecutable(
    Schedule.ScheduleEmitterClosedForm, "closed-form lowering available",
    { Schedule.ScheduleProofTarget("closed-form semantic emitter is available"), Schedule.ScheduleProofProfit("closed form removes loop control") })
end
function Kernel.KernelResultVoid:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end
function Kernel.KernelResultValue:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end
function Kernel.KernelResultFind:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end
function Kernel.KernelResultAll:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end
function Kernel.KernelResultAllCompare:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end
function Kernel.KernelResultAny:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end
function Kernel.KernelResultReduction:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end
function Kernel.KernelResultClosedForm:schedule_base_candidates() return { Schedule.ScheduleClosedFormCandidate(closed_capability()) } end
function Kernel.KernelResultOriginalControl:schedule_base_candidates() return { Schedule.ScheduleScalarCandidate(Schedule.ScheduleScalarIndex, scalar_capability()) } end

function Backend.BackTargetPointerBits:schedule_target_fact() return Schedule.ScheduleTargetFactIgnored end
function Backend.BackTargetIndexBits:schedule_target_fact() return Schedule.ScheduleTargetFactIgnored end
function Backend.BackTargetEndian:schedule_target_fact() return Schedule.ScheduleTargetFactIgnored end
function Backend.BackTargetCacheLineBytes:schedule_target_fact() return Schedule.ScheduleTargetFactIgnored end
function Backend.BackTargetFeature:schedule_target_fact() return Schedule.ScheduleTargetFactIgnored end
function Backend.BackTargetSupportsShape:schedule_target_fact() return Schedule.ScheduleTargetVectorShape(self.shape) end
function Backend.BackTargetSupportsVectorOp:schedule_target_fact() return Schedule.ScheduleTargetVectorShape(Backend.BackShapeVec(self.vec)) end
function Backend.BackTargetSupportsMaskedTail:schedule_target_fact() return Schedule.ScheduleTargetFactIgnored end
function Backend.BackTargetPrefersUnroll:schedule_target_fact() return Schedule.ScheduleTargetUnrollPreference(self.unroll) end
function Backend.BackTargetModel:project_schedule_target()
  local contributions = {}
  for _, fact in ipairs(self.facts) do contributions = append_all(contributions, { fact:schedule_target_fact() }) end
  return Schedule.ScheduleTargetProjection(contributions)
end

function Kernel.KernelPlanned:schedule_vector_lane_evidence()
  if #self.body.lanes > 0 then return Schedule.ScheduleVectorLaneAvailable(self.body.lanes[1]) end
  return Schedule.ScheduleVectorLaneUnavailable("kernel has no vectorizable lane")
end
function Schedule.ScheduleVectorLaneUnavailable:vector_candidate(vec) return Schedule.ScheduleCandidateNotContributed end
function Schedule.ScheduleVectorLaneAvailable:vector_candidate(vec)
  local form = Schedule.ScheduleVector(Schedule.LaneVector(self.lane.elem_ty, vec.lanes), 1, 1, Schedule.TailScalar)
  local capability = Schedule.ScheduleEmitterRejected(Schedule.ScheduleEmitterVector(require("lalin.schema.stencil").StencilVectorFeatureNative), { Schedule.ScheduleRejectTarget("vector emitter is outside SCH-1") })
  return Schedule.ScheduleCandidateContributed(Schedule.ScheduleVectorCandidate(form, capability))
end
function Backend.BackShapeScalar:schedule_vector_candidate(plan) return Schedule.ScheduleCandidateNotContributed end
function Backend.BackShapeVec:schedule_vector_candidate(plan) return plan:schedule_vector_lane_evidence():vector_candidate(self.vec) end
function Schedule.ScheduleTargetFactIgnored:vector_candidate(plan) return Schedule.ScheduleCandidateNotContributed end
function Schedule.ScheduleTargetUnrollPreference:vector_candidate(plan) return Schedule.ScheduleCandidateNotContributed end
function Schedule.ScheduleTargetVectorShape:vector_candidate(plan) return self.shape:schedule_vector_candidate(plan) end
function Schedule.ScheduleCandidateContributed:candidate_entries() return { self.candidate } end
function Schedule.ScheduleCandidateNotContributed:candidate_entries() return {} end
function Schedule.ScheduleTargetProjection:vector_candidates(plan)
  local candidates = {}
  for _, contribution in ipairs(self.contributions) do candidates = append_all(candidates, contribution:vector_candidate(plan):candidate_entries()) end
  return candidates
end

function Kernel.KernelScheduleIneligible:schedule_contribution(target) return Schedule.ScheduleKernelRejected(self.subject, self.rejects) end
function Kernel.KernelScheduleEligible:schedule_contribution(target)
  local target_projection = target:project_schedule_target()
  local candidates = append_all(target_projection:vector_candidates(self.plan), self.plan.body.result:schedule_base_candidates())
  return Schedule.SchedulePlanInput(self.plan, candidates):select_kernel_schedule():to_kernel_schedule(self.plan)
end
function Kernel.KernelModulePlan:plan_schedules(code_module, flow, values, mem, effects, target)
  local selected_target = target or Backend.BackTargetModel(Backend.BackTargetNative, {})
  local schedules = {}
  for _, plan in ipairs(self.plans) do schedules = append_all(schedules, { plan:schedule_eligibility():schedule_contribution(selected_target) }) end
  return Schedule.ScheduleModulePlan(code_module.id, Schedule.ScheduleTarget(selected_target), schedules)
end
