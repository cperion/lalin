-- impl/kernel_plan.lua — plan_kernels methods on LalinMem, LalinKernel,
-- LalinFlow, LalinValue, LalinCode, LalinEffect types.
-- Produces LalinKernel.KernelModulePlan from MemSemanticFactSet.
-- Entry: Mem.MemSemanticFactSet:plan_kernels(flow, values, mem, effects)
-- Heavy classof refactored from code_kernel_plan.lua, kernel_validate.lua,
-- kernel_emit_support.lua.

local Core    = require("lalin.schema_v2.core")
local Code    = require("lalin.schema_v2.code")
local Graph   = require("lalin.schema_v2.graph")
local Flow    = require("lalin.schema_v2.flow")
local Value   = require("lalin.schema_v2.value")
local Mem     = require("lalin.schema_v2.mem")
local Effect  = require("lalin.schema_v2.effect")
local Kernel  = require("lalin.schema_v2.kernel")
local Schedule = require("lalin.schema_v2.schedule")

local function sanitize(s)
  s = tostring(s or "x"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "x" end
  return s
end

----------------------------------------------------------------------
-- KernelPlan leaf methods: kernel_plan_rejects
----------------------------------------------------------------------

function Kernel.KernelPlan:kernel_plan_rejects() return nil end
function Kernel.KernelNoPlan:kernel_plan_rejects() return self.rejects end

----------------------------------------------------------------------
-- KernelSkeletonSelection leaf methods
----------------------------------------------------------------------

function Kernel.KernelSkeletonSelection:kernel_skeleton_effects()
  return self.effects or {}
end

function Kernel.KernelSkeletonSelection:kernel_skeleton_result()
  return self.result
end

function Kernel.KernelSkeletonSelection:kernel_skeleton_handles_dependences()
  return false
end

-- Stencil.KernelSkeletonCopy/ScatterReduce handle dependences
-- (These are in the Stencil module, referenced by SkeletonSelection effects)

----------------------------------------------------------------------
-- KernelFunctionSkeletonSelection leaf methods
----------------------------------------------------------------------

function Kernel.KernelFunctionSkeletonSelection:add_function_skeleton_plan(plans)
end

function Kernel.KernelFunctionSkeletonPartition:add_function_skeleton_plan(plans)
  plans[#plans + 1] = self.plan
end

function Kernel.KernelFunctionSkeletonNoSelection:add_function_skeleton_plan(plans)
  plans[#plans + 1] = Kernel.KernelNoPlan(self.subject, self.rejects)
end

----------------------------------------------------------------------
-- FlowTripCount leaf methods
----------------------------------------------------------------------

function Flow.FlowTripCount:kernel_plan_closed_form_trip_unknown_proof() return false end
function Flow.FlowTripCountUnknown:kernel_plan_closed_form_trip_unknown_proof() return true end

----------------------------------------------------------------------
-- KernelLoopCandidate leaf methods
----------------------------------------------------------------------

function Kernel.KernelLoopCandidate:select_kernel_loop_plan()
  return Kernel.KernelLoopPlanOriginalControl
end

function Kernel.KernelLoopNotCounted:select_kernel_loop_plan()
  return Kernel.KernelLoopNoPlan(self.rejects)
end

function Kernel.KernelLoopMissingOwner:select_kernel_loop_plan()
  return Kernel.KernelLoopNoPlan(self.rejects)
end

function Kernel.KernelLoopRejectedFacts:select_kernel_loop_plan()
  return Kernel.KernelLoopNoPlan(self.rejects)
end

function Kernel.KernelLoopClosedFormCandidate:select_kernel_loop_plan()
  return Kernel.KernelLoopPlanClosedForm(self.closed_form, self.trip_count:kernel_plan_closed_form_trip_unknown_proof())
end

function Kernel.KernelLoopReductionCandidate:select_kernel_loop_plan()
  return Kernel.KernelLoopPlanReduction(self.reduction)
end

function Kernel.KernelLoopSkeletonCandidate:select_kernel_loop_plan()
  return Kernel.KernelLoopPlanSkeleton(self.result)
end

----------------------------------------------------------------------
-- is_scalar_code_ty helper
----------------------------------------------------------------------

local function is_scalar_code_ty(ty)
  if ty == Code.CodeTyVoid or ty == Code.CodeTyBool8 or ty == Code.CodeTyIndex then return true end
  if rawget(ty, "bits") ~= nil and rawget(ty, "signedness") ~= nil then return true end
  if rawget(ty, "bits") ~= nil and rawget(ty, "signedness") == nil then return true end
  if rawget(ty, "pointee") ~= nil then return true end
  if rawget(ty, "sig") ~= nil then return true end
  if ty == Code.CodeTyDataPtr or ty == Code.CodeTyCodePtr or ty == Code.CodeTyImportedCFuncPtr then return true end
  if rawget(ty, "id") ~= nil and rawget(ty, "source_ty") ~= nil then return true end  -- Handle/Lease
  return false
end

----------------------------------------------------------------------
-- value_expr_supported: check if a ValueExpr is kernel-lowerable
----------------------------------------------------------------------

local function value_expr_supported(expr, seen)
  if expr == nil then return false, "missing ValueExpr" end
  seen = seen or {}
  if seen[expr] then return true end
  seen[expr] = true
  if rawget(expr, "const") ~= nil then return true end
  if rawget(expr, "value") ~= nil and rawget(expr, "a") == nil and rawget(expr, "op") == nil then return true end
  if rawget(expr, "op") ~= nil and rawget(expr, "from") ~= nil then
    if not is_scalar_code_ty(expr.to) then return false, "non-scalar cast target type" end
    return value_expr_supported(expr.value, seen)
  end
  if rawget(expr, "a") ~= nil and rawget(expr, "b") ~= nil then
    if not is_scalar_code_ty(expr.ty) then return false, "non-scalar arithmetic type" end
    local ok, reason = value_expr_supported(expr.a, seen); if not ok then return false, reason end
    return value_expr_supported(expr.b, seen)
  end
  return false, "unsupported ValueExpr for kernel lowering"
end

----------------------------------------------------------------------
-- reject helpers
----------------------------------------------------------------------

local function reject_target(reason) return Schedule.ScheduleRejectTarget(reason) end
local function reject_memory(reason) return Schedule.ScheduleRejectMemory(reason) end
local function reject_algebra(reason) return Schedule.ScheduleRejectAlgebra(reason) end
local function reject_profit(reason) return Schedule.ScheduleRejectProfit(reason) end

----------------------------------------------------------------------
-- summarize_rejects
----------------------------------------------------------------------

local function summarize_rejects(rejects)
  if #(rejects or {}) == 0 then return "no reject reasons" end
  local out = {}
  for i = 1, math.min(4, #rejects) do
    local r = rejects[i]
    out[#out + 1] = tostring(r and (r.reason or r) or r)
  end
  if #rejects > #out then
    out[#out + 1] = tostring(#rejects - #out) .. " additional reject(s)"
  end
  return table.concat(out, "; ")
end

----------------------------------------------------------------------
-- plan_kernels: entry point
----------------------------------------------------------------------

function Mem.MemSemanticFactSet:plan_kernels(flow, values, mem, effects)
  -- Build kernel module plan from loop facts and memory/value analysis.
  -- For each counted loop detected in flow facts, evaluate candidates:
  --   closed-form, reduction, skeleton, or original control.
  -- Produce a KernelModulePlan with the best plan for each loop.
  local plans = {}

  -- Index flow facts by loop
  local flow_loops = {}
  for _, lf in ipairs(flow and flow.loops or {}) do
    if lf.counted ~= nil then flow_loops[lf.loop.text] = lf end
  end

  -- Index reductions and closed forms from value facts
  local reductions = {}
  for _, r in ipairs(values and values.reductions or {}) do
    local domain_text = r.domain and r.domain.loop and r.domain.loop.text or tostring(r)
    reductions[domain_text] = reductions[domain_text] or {}
    reductions[domain_text][#reductions[domain_text] + 1] = r
  end

  local closed_forms = {}
  for _, cf in ipairs(values and values.closed_forms or {}) do
    local loop_text = cf.reduction and cf.reduction.domain and cf.reduction.domain.loop and cf.reduction.domain.loop.text or tostring(cf)
    closed_forms[loop_text] = cf
  end

  -- Evaluate each loop
  for _, lf in ipairs(flow and flow.loops or {}) do
    if lf.counted ~= nil then
      local loop_text = lf.loop.text
      local candidates = {}
      -- closed-form candidate
      if closed_forms[loop_text] ~= nil then
        local cf = closed_forms[loop_text]
        candidates[#candidates + 1] = Kernel.KernelLoopClosedFormCandidate(cf, Flow.FlowTripCountUnknown("using flow trip count", nil))
      end
      -- reduction candidates
      for _, r in ipairs(reductions[loop_text] or {}) do
        candidates[#candidates + 1] = Kernel.KernelLoopReductionCandidate(r)
      end
      -- always original control as fallback
      candidates[#candidates + 1] = Kernel.KernelLoopOriginalControlCandidate

      -- Select best plan
      local selection = nil
      for _, c in ipairs(candidates) do
        selection = c:select_kernel_loop_plan()
        -- prefer first non-original-control plan
        if rawget(selection, "reason") ~= nil or rawget(selection, "rejects") ~= nil then
          -- this is a no-plan or fallback; keep trying
        else
          break
        end
      end

      if selection == Kernel.KernelLoopPlanOriginalControl then
        plans[#plans + 1] = Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(lf.loop), {})
      elseif rawget(selection, "rejects") ~= nil then
        plans[#plans + 1] = Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(lf.loop), selection.rejects or {})
      elseif rawget(selection, "closed_form") ~= nil then
        -- Build a planned kernel for closed form
        local tid = Kernel.KernelId("kernel:closed_form:" .. sanitize(loop_text))
        local body = Kernel.KernelBody(
          Kernel.KernelDomainFlow(Flow.FlowDomainLoop(lf.loop), lf.counted, lf.counted.counter),
          {}, {}, {},
          Kernel.KernelResultClosedForm(selection.closed_form),
          Kernel.KernelEquivalenceProof({ Kernel.KernelProofFlow(Flow.FlowDomainLoop(lf.loop), "closed-form equivalence") })
        )
        plans[#plans + 1] = Kernel.KernelPlanned(tid, Kernel.KernelSubjectLoop(lf.loop), body)
      elseif rawget(selection, "reduction") ~= nil then
        local tid = Kernel.KernelId("kernel:reduction:" .. sanitize(loop_text))
        local body = Kernel.KernelBody(
          Kernel.KernelDomainFlow(Flow.FlowDomainLoop(lf.loop), lf.counted, lf.counted.counter),
          {}, {}, {},
          Kernel.KernelResultReduction(selection.reduction),
          Kernel.KernelEquivalenceProof({ Kernel.KernelProofValue(Value.AlgebraProofComposite({}, "reduction equivalence")) })
        )
        plans[#plans + 1] = Kernel.KernelPlanned(tid, Kernel.KernelSubjectLoop(lf.loop), body)
      end
    else
      plans[#plans + 1] = Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(lf.loop), { Kernel.KernelRejectIncompleteFunction(Kernel.KernelSubjectLoop(lf.loop), "loop not counted") })
    end
  end

  return Kernel.KernelModulePlan(self.module, flow, values, mem or self, effects or Effect.EffectFactSet(self.module, {}, {}, {}), plans)
end
