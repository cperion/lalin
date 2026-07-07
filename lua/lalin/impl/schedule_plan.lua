-- impl/schedule_plan.lua — plan_schedules methods on LalinKernel, LalinSchedule,
-- LalinBackend types. Produces LalinSchedule.ScheduleModulePlan.
-- Entry: Kernel.KernelModulePlan:plan_schedules(code_module, flow, values, mem, effects, target)

local Backend  = require("lalin.schema_v2.backend")
local Code     = require("lalin.schema_v2.code")
local Flow     = require("lalin.schema_v2.flow")
local Value    = require("lalin.schema_v2.value")
local Mem      = require("lalin.schema_v2.mem")
local Kernel   = require("lalin.schema_v2.kernel")
local Schedule = require("lalin.schema_v2.schedule")

local function sanitize(s)
  s = tostring(s or "x"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "x" end
  return s
end

local function capability_executable(capability)
  return capability ~= nil and capability.executable == true
end

local function capability_rejects(capability)
  return capability and capability.rejects or {}
end

----------------------------------------------------------------------
-- SchedulePlanInput: select kernel schedule
----------------------------------------------------------------------

function Schedule.SchedulePlanInput:select_kernel_schedule()
  if self.vector_form ~= nil and capability_executable(self.vector_capability) then
    return Schedule.ScheduleSelectionPlanned(self.vector_form, self.vector_capability, {})
  end
  if self.vector_form ~= nil and (not capability_executable(self.vector_capability)) and capability_executable(self.scalar_capability) then
    return Schedule.ScheduleSelectionPlanned(self.scalar_form, self.scalar_capability, capability_rejects(self.vector_capability))
  end
  if self.vector_form == nil and capability_executable(self.scalar_capability) then
    return Schedule.ScheduleSelectionPlanned(self.scalar_form, self.scalar_capability, {})
  end
  return Schedule.ScheduleSelectionNoPlan(capability_rejects(self.scalar_capability))
end

----------------------------------------------------------------------
-- SchedulePlanSelection leaf methods
----------------------------------------------------------------------

function Schedule.SchedulePlanSelection:to_kernel_schedule(kid, plan, proofs_for_selection)
  error("code_schedule_plan: unsupported schedule selection", 2)
end

function Schedule.ScheduleSelectionNoPlan:to_kernel_schedule(kid, plan, proofs_for_selection)
  return Schedule.ScheduleNoPlan(kid, self.rejects)
end

function Schedule.ScheduleSelectionPlanned:to_kernel_schedule(kid, plan, proofs_for_selection)
  local capability = assert(self.capability, "planned schedule selection has no emitter capability")
  return Schedule.SchedulePlanned(
    Schedule.ScheduleId("schedule:" .. sanitize(kid.text) .. ":" .. sanitize(capability.kind)),
    kid, self.form,
    proofs_for_selection(plan, capability),
    self.rejected_alternatives or {}
  )
end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function default_target()
  return Backend.BackTargetModel(Backend.BackTargetNative, {})
end

local function target_prefers_unroll(target)
  for _, fact in ipairs(target and target.facts or {}) do
    if rawget(fact, "unroll") ~= nil then return fact.unroll end
  end
  return 1
end

local function proofs_for(plan, capability)
  local proofs = { Schedule.ScheduleProofTarget(capability.reason or "kernel emitter support classified executable") }
  local eq = plan.body and plan.body.equivalence or nil
  if rawget(eq, "proofs") ~= nil then
    for _, proof in ipairs(eq.proofs or {}) do
      if rawget(proof, "proof") ~= nil then
        if rawget(proof, "reason") ~= nil then
          proofs[#proofs + 1] = Schedule.ScheduleProofMemory(proof.proof)
        else
          proofs[#proofs + 1] = Schedule.ScheduleProofAlgebra(proof.proof)
        end
      end
    end
  end
  proofs[#proofs + 1] = Schedule.ScheduleProofProfit("selected because semantic lowering has an emitter for " .. tostring(capability.kind))
  return proofs
end

local function scalar_for_code_ty(ty)
  if ty == Code.CodeTyBool8 then return Backend.BackBool end
  if ty == Code.CodeTyIndex then return Backend.BackIndex end
  local bits = rawget(ty, "bits")
  local signedness = rawget(ty, "signedness")
  if bits ~= nil and signedness ~= nil then
    if bits == 8 then return signedness == Code.CodeSigned and Backend.BackI8 or Backend.BackU8 end
    if bits == 16 then return signedness == Code.CodeSigned and Backend.BackI16 or Backend.BackU16 end
    if bits == 32 then return signedness == Code.CodeSigned and Backend.BackI32 or Backend.BackU32 end
    if bits == 64 then return signedness == Code.CodeSigned and Backend.BackI64 or Backend.BackU64 end
  elseif bits ~= nil then
    if bits == 32 then return Backend.BackF32 end
    if bits == 64 then return Backend.BackF64 end
  end
  return nil
end

local function vector_schedule_form(plan, target)
  local body = plan.body
  if body == nil or #(body.lanes or {}) == 0 then return nil end
  if rawget(body.result, "closed_form") ~= nil then return nil end
  local elem_ty = nil
  for _, lane in ipairs(body.lanes or {}) do
    if lane.pattern ~= Mem.MemAccessContiguous then return nil end
    elem_ty = elem_ty or lane.elem_ty
    if scalar_for_code_ty(lane.elem_ty) ~= scalar_for_code_ty(elem_ty) then return nil end
  end
  local elem = scalar_for_code_ty(elem_ty)
  if elem == nil then return nil end
  for _, fact in ipairs(target and target.facts or {}) do
    local shape = rawget(fact, "shape")
    if shape ~= nil and rawget(shape, "vec") ~= nil and shape.vec.elem == elem then
      return Schedule.ScheduleVector(Schedule.LaneVector(elem_ty, shape.vec.lanes), target_prefers_unroll(target), 1, Schedule.TailScalar)
    end
  end
  return nil
end

local function scalar_or_closed_form_for(plan)
  if rawget(plan.body and plan.body.result, "closed_form") ~= nil then return Schedule.ScheduleClosedForm end
  return Schedule.ScheduleScalarIndex
end

local function schedule_for_plan(plan, target, flow)
  local kid = plan.id
  local vector_form = vector_schedule_form(plan, target)
  local vector_cap = nil
  if vector_form ~= nil then
    -- classify via kernel_emit_support — simplified: assume scalar fallback
    vector_cap = Schedule.ScheduleEmitterCapability(Schedule.ScheduleEmitterVector(nil), false, "vector classification deferred", { Schedule.ScheduleRejectTarget("vector lowering not yet classified") })
  end
  local scalar_form = scalar_or_closed_form_for(plan)
  local scalar_cap = (vector_cap and not vector_cap.executable) and Schedule.ScheduleEmitterCapability(Schedule.ScheduleEmitterScalar, true, "scalar fallback", {}) or Schedule.ScheduleEmitterCapability(Schedule.ScheduleEmitterScalar, true, "scalar lowering available", {})
  local selection = Schedule.SchedulePlanInput(vector_form, vector_cap, scalar_form, scalar_cap):select_kernel_schedule()
  return selection:to_kernel_schedule(kid, plan, proofs_for)
end

----------------------------------------------------------------------
-- plan_schedules: entry point
----------------------------------------------------------------------

function Kernel.KernelModulePlan:plan_schedules(code_module, flow, values, mem, effects, target)
  target = target or default_target()
  local schedules = {}
  for _, kernel_plan in ipairs(self.plans or {}) do
    if rawget(kernel_plan, "body") ~= nil then
      schedules[#schedules + 1] = schedule_for_plan(kernel_plan, target, flow)
    end
  end
  return Schedule.ScheduleModulePlan(code_module.id, Schedule.ScheduleTarget(target), schedules)
end
