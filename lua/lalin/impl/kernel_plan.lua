-- impl/kernel_plan.lua — typed kernel loop-fact projection and planning.
require("lalin.schema")
require("lalin.impl.code_mem")
require("lalin.impl.code_flow")
local Code = require("lalin.schema.code")
local Graph = require("lalin.schema.graph")
local Flow = require("lalin.schema.flow")
local Value = require("lalin.schema.value")
local Mem = require("lalin.schema.mem")
local Effect = require("lalin.schema.effect")
local Kernel = require("lalin.schema.kernel")
local Stencil = require("lalin.schema.stencil")

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
function Flow.FlowTripCountExpression:kernel_trip_evidence() return Kernel.KernelTripKnown(self) end
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
function Kernel.KernelReductionMissing:kernel_candidate(_fact)
  return Kernel.KernelLoopSkeletonCandidate(Kernel.KernelResultVoid)
end
function Kernel.KernelLoopCounted:kernel_candidate(projection, fact) return projection:lookup_closed_forms(fact.loop):kernel_candidate(projection, fact) end
function Kernel.KernelLoopNotCountedEvidence:kernel_candidate(projection, fact) return Kernel.KernelLoopNotCounted({ self.reject }) end
function Kernel.KernelLoopFactEntry:kernel_candidate(projection) return self.count:kernel_candidate(projection, self) end
function Flow.FlowLoopFacts:kernel_count_evidence(subject)
  if self.counted ~= nil then return Kernel.KernelLoopCounted(self.counted) end
  return Kernel.KernelLoopNotCountedEvidence(Kernel.KernelRejectNoFacts(subject, "loop is not counted"))
end

function Flow.FlowPrimaryInduction:kernel_counter_contribution(induction)
  return Kernel.KernelCounterCandidate(Kernel.KernelCounterValue(induction.value))
end
function Flow.FlowDerivedInduction:kernel_counter_contribution(_induction)
  return Kernel.KernelCounterIgnored
end
function Flow.FlowPointerInduction:kernel_counter_contribution(_induction)
  return Kernel.KernelCounterIgnored
end
function Kernel.KernelCounterIgnored:kernel_append_counter(counters) return counters end
function Kernel.KernelCounterCandidate:kernel_append_counter(counters)
  return append_all(counters, { self.counter })
end
function Flow.FlowLoopFacts:kernel_counter_selection(subject)
  local counters = {}
  for _, induction in ipairs(self.inductions) do
    counters = induction.role:kernel_counter_contribution(induction)
      :kernel_append_counter(counters)
  end
  if #counters == 0 then
    return Kernel.KernelCounterMissing(
      Kernel.KernelRejectNoFacts(subject, "counted loop has no primary induction"))
  end
  if #counters > 1 then
    return Kernel.KernelCounterAmbiguous(counters,
      Kernel.KernelRejectNoFacts(subject, "counted loop has multiple primary inductions"))
  end
  return Kernel.KernelCounterSelected(counters[1])
end

function Flow.FlowFactSet:project_kernel_loop_facts(values, trips)
  local loops, reductions, closed_forms = {}, {}, {}
  for _, reduction in ipairs(values.reductions) do reductions = append_all(reductions, reduction:kernel_reduction_entries()) end
  for _, closed_form in ipairs(values.closed_forms) do closed_forms = append_all(closed_forms, closed_form:kernel_closed_form_entries()) end
  for _, loop in ipairs(self.loops) do
    local subject = Kernel.KernelSubjectLoop(loop.loop)
    loops[#loops + 1] = Kernel.KernelLoopFactEntry(
      loop.loop, loop.domain, loop:kernel_count_evidence(subject),
      loop:kernel_counter_selection(subject),
      trips:lookup(loop.loop):kernel_trip_evidence(subject))
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
function Kernel.KernelEffectProjection:kernel_scan_selection(input)
  local selection = Kernel.KernelSkeletonNoSelection({})
  for i = 1, #self.entries do
    selection = selection:kernel_consider_scan(
      Kernel.KernelScanSelectionInput(
        input.reduction, input.build, self.entries[i]))
  end
  return selection
end
function Kernel.KernelSkeletonSelection:kernel_consider_scan(_input) return self end
function Kernel.KernelSkeletonNoSelection:kernel_consider_scan(input)
  return input.entry.effect:kernel_scan_selection(input)
end
function Kernel.KernelEffect:kernel_scan_selection(_input)
  return Kernel.KernelSkeletonNoSelection({})
end
function Kernel.KernelEffectStore:kernel_scan_selection(input)
  return self.value:kernel_scan_selection(input)
end
local function scan_selected(input)
  local store = input.entry.effect
  local entries = {}
  for i = 1, #input.build.effects.entries do
    local entry = input.build.effects.entries[i]
    if entry == input.entry then
      entries[i] = Kernel.KernelEffectByInstructionEntry(entry.inst,
        Kernel.KernelEffectScan(store.dst, store.index, input.reduction,
          Stencil.StencilScanInclusive, Kernel.KernelScanLinear))
    else
      entries[i] = entry
    end
  end
  return Kernel.KernelSkeletonScanSelected(
    Kernel.KernelEffectProjection(entries), Kernel.KernelResultVoid)
end
function Kernel.KernelCounter:kernel_scan_index_selection(input)
  return Kernel.KernelSkeletonNoSelection({
    Kernel.KernelRejectUnsupportedSubject(
      Kernel.KernelSubjectDomain(input.reduction.domain),
      "stored recurrence update has no exact primary scan index"),
  })
end
function Kernel.KernelCounterValue:kernel_scan_index_selection(input)
  return input.entry.effect.index:kernel_scan_index_selection(
    Kernel.KernelScanIndexInput(input, self.value))
end
function Value.ValueExpr:kernel_scan_index_selection(input)
  return Kernel.KernelSkeletonNoSelection({
    Kernel.KernelRejectUnsupportedSubject(
      Kernel.KernelSubjectDomain(input.selection.reduction.domain),
      "stored recurrence update index is not the primary scan axis"),
  })
end
function Value.ValueExprValue:kernel_scan_index_selection(input)
  if self.value == input.counter then return scan_selected(input.selection) end
  return Value.ValueExpr.kernel_scan_index_selection(self, input)
end
function Value.ValueExprCast:kernel_scan_index_selection(input)
  return self.value:kernel_scan_index_selection(input)
end
function Kernel.KernelExpr:kernel_scan_selection(_input)
  return Kernel.KernelSkeletonNoSelection({})
end
function Kernel.KernelExprKernelValue:kernel_scan_selection(input)
  for i = 1, #input.build.bindings.entries do
    local entry = input.build.bindings.entries[i]
    if entry.binding.id == self.value then
      if entry.value == input.reduction.update then
        return input.build.counter:kernel_scan_index_selection(input)
      end
      return entry.binding.expr:kernel_scan_selection(input)
    end
  end
  return Kernel.KernelSkeletonNoSelection({})
end
function Kernel.KernelExprValue:kernel_scan_selection(input)
  if self.value == input.reduction.update then
    return input.build.counter:kernel_scan_index_selection(input)
  end
  for i = 1, #input.build.bindings.entries do
    local entry = input.build.bindings.entries[i]
    if entry.value == self.value then
      return entry.binding.expr:kernel_scan_selection(input)
    end
  end
  return Kernel.KernelSkeletonNoSelection({})
end
function Kernel.KernelSkeletonSelection:materialize_kernel_reduction(input)
  return planned(input.request, input.build,
    Kernel.KernelResultReduction(input.reduction), {
      Kernel.KernelProofValue(input.reduction.proof, "reduction fact"),
    })
end
function Kernel.KernelSkeletonNoSelection:materialize_kernel_reduction(input)
  if #self.rejects ~= 0 then
    return Kernel.KernelNoPlan(
      Kernel.KernelSubjectDomain(input.reduction.domain), self.rejects)
  end
  return Kernel.KernelSkeletonSelection.materialize_kernel_reduction(self, input)
end
function Kernel.KernelSkeletonScanSelected:materialize_kernel_reduction(input)
  local source = input.build
  local build = Kernel.KernelLoopPlanBuild(
    source.domain, source.trip, source.counter, source.lanes, source.bindings,
    self.effects, source.proofs)
  return planned(input.request, build, self.result, {
    Kernel.KernelProofValue(input.reduction.proof, "reduction fact"),
    Kernel.KernelProofFunctionEquivalence(
      "store of the exact loop-carried update at the primary index is an inclusive scan"),
  })
end
function Kernel.KernelLoopPlanReduction:materialize_kernel_build(request, build)
  local input = Kernel.KernelScanMaterializationInput(request, build, self.reduction)
  return build.effects:kernel_scan_selection(input)
    :materialize_kernel_reduction(input)
end
local function kernel_loop_contains(loop, block_id)
  for i = 1, #(loop.body or {}) do if loop.body[i].block.text == block_id.text then return true end end
  return false
end

function Code.CodeTermOp:kernel_allcompare_exit_fact(_edge, _loop) return {} end
function Code.CodeTermBranch:kernel_allcompare_exit_fact(edge, loop)
  local then_in = kernel_loop_contains(loop, self.then_dest)
  local else_in = kernel_loop_contains(loop, self.else_dest)
  if then_in == else_in then return {} end
  local polarity = then_in and Kernel.KernelAllCompareContinueWhenTrue or Kernel.KernelAllCompareContinueWhenFalse
  return { Kernel.KernelAllComparePredicateExit(self.cond, polarity, edge.to.block) }
end
function Kernel.KernelAllCompareExitFact:kernel_allcompare_count_exits(out) return out end
function Kernel.KernelAllCompareCountExit:kernel_allcompare_count_exits(out) out[#out + 1] = self; return out end
function Kernel.KernelAllCompareExitFact:kernel_allcompare_predicate_exits(out) return out end
function Kernel.KernelAllComparePredicateExit:kernel_allcompare_predicate_exits(out) out[#out + 1] = self; return out end

function Kernel.KernelBindingMissing:kernel_allcompare_operand(_value) return Kernel.KernelAllCompareOperandMissing end
function Kernel.KernelBindingFound:kernel_allcompare_operand(value) return self.entry.binding.expr:kernel_allcompare_operand(value) end
function Kernel.KernelExpr:kernel_allcompare_operand(_value) return Kernel.KernelAllCompareOperandMissing end
function Kernel.KernelExprLaneLoad:kernel_allcompare_operand(value) return Kernel.KernelAllCompareOperandFound(self, value) end
function Kernel.KernelAllCompareOperandMissing:kernel_allcompare_finish(_right, _cmp, _success, _failure) return Kernel.KernelAllCompareMissing end
function Kernel.KernelAllCompareOperandFound:kernel_allcompare_finish(right, cmp, success, failure)
  return right:kernel_allcompare_finish_right(self, cmp, success, failure)
end
function Kernel.KernelAllCompareOperandMissing:kernel_allcompare_finish_right(_left, _cmp, _success, _failure) return Kernel.KernelAllCompareMissing end
function Kernel.KernelAllCompareOperandFound:kernel_allcompare_finish_right(left, cmp, success, failure)
  return Kernel.KernelAllCompareFound(
    Kernel.KernelResultAllCompare(left.expr, left.value, self.expr, self.value, cmp, success, failure),
    Kernel.KernelProofFunctionEquivalence("sealed counted loop compares two primary lane streams and exits on mismatch"))
end

function Core.CmpEq:kernel_allcompare_invert() return Core.CmpNe end
function Core.CmpNe:kernel_allcompare_invert() return Core.CmpEq end
function Core.CmpLt:kernel_allcompare_invert() return Core.CmpGe end
function Core.CmpLe:kernel_allcompare_invert() return Core.CmpGt end
function Core.CmpGt:kernel_allcompare_invert() return Core.CmpLe end
function Core.CmpGe:kernel_allcompare_invert() return Core.CmpLt end
function Kernel.KernelAllCompareContinueWhenTrue:kernel_allcompare_cmp(op) return op end
function Kernel.KernelAllCompareContinueWhenFalse:kernel_allcompare_cmp(op) return op:kernel_allcompare_invert() end

function Code.CodeInstOp:kernel_allcompare_condition(_cond, _build, _predicate, _success) return Kernel.KernelAllCompareMissing end
function Code.CodeInstCompare:kernel_allcompare_condition(cond, build, predicate, success)
  if self.dst.text ~= cond.text then return Kernel.KernelAllCompareMissing end
  local left = build.bindings:lookup(self.lhs):kernel_allcompare_operand(self.lhs)
  local right = build.bindings:lookup(self.rhs):kernel_allcompare_operand(self.rhs)
  return left:kernel_allcompare_finish(right, predicate.polarity:kernel_allcompare_cmp(self.op), success.destination, predicate.destination)
end
function Kernel.KernelAllCompareMissing:kernel_allcompare_consider(candidate) return candidate end
function Kernel.KernelAllCompareFound:kernel_allcompare_consider(_candidate) return self end
function Code.CodeFunc:kernel_allcompare_condition(cond, build, predicate, success)
  local found = Kernel.KernelAllCompareMissing
  for i = 1, #self.blocks do
    for j = 1, #self.blocks[i].insts do
      local candidate = self.blocks[i].insts[j].op:kernel_allcompare_condition(cond, build, predicate, success)
      found = found:kernel_allcompare_consider(candidate)
    end
  end
  return found
end
function Kernel.KernelLoopAnalysisInput:kernel_allcompare_analysis(build)
  local exits = {}
  for i = 1, #self.graph.funcs do
    for j = 1, #self.graph.funcs[i].loops do
      local loop = self.graph.funcs[i].loops[j]
      if loop.id == self.fact.loop then
        for k = 1, #loop.exits do
          local edge = loop.exits[k]
          if edge.from.block.text == loop.header.block.text then
            exits[#exits + 1] = Kernel.KernelAllCompareCountExit(edge.to.block)
          else
            for f = 1, #self.module.funcs do
              if self.module.funcs[f].id == loop.func then
                for b = 1, #self.module.funcs[f].blocks do
                  if self.module.funcs[f].blocks[b].id == edge.from.block then
                    local facts = self.module.funcs[f].blocks[b].term.op:kernel_allcompare_exit_fact(edge, loop)
                    for n = 1, #facts do exits[#exits + 1] = facts[n] end
                  end
                end
              end
            end
          end
        end
        local projection = Kernel.KernelAllCompareExitProjection(exits)
        local counts, predicates = {}, {}
        for n = 1, #projection.exits do
          projection.exits[n]:kernel_allcompare_count_exits(counts)
          projection.exits[n]:kernel_allcompare_predicate_exits(predicates)
        end
        if #counts == 1 and #predicates == 1 then
          for f = 1, #self.module.funcs do
            if self.module.funcs[f].id == loop.func then
              return self.module.funcs[f]:kernel_allcompare_condition(predicates[1].cond, build, predicates[1], counts[1])
            end
          end
        end
      end
    end
  end
  return Kernel.KernelAllCompareMissing
end
function Kernel.KernelAllCompareMissing:kernel_materialize_allcompare(request, _build)
  return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(request.fact.loop), {})
end
function Kernel.KernelTripUnavailable:kernel_materialize_allcompare_trip(_found, request, _build)
  return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(request.fact.loop), { self.reject })
end
function Kernel.KernelAllCompareFound:kernel_allcompare_build(build)
  local lanes = {}
  local left_id, right_id = self.result.left.lane.id, self.result.right.lane.id
  for i = 1, #build.lanes.entries do
    local entry = build.lanes.entries[i]
    if entry.lane.id == left_id or entry.lane.id == right_id then lanes[#lanes + 1] = entry end
  end
  return Kernel.KernelLoopPlanBuild(
    build.domain, build.trip, build.counter, Kernel.KernelLaneProjection(lanes),
    build.bindings, build.effects, build.proofs)
end
function Kernel.KernelTripKnown:kernel_materialize_allcompare_trip(found, request, build)
  return planned(request, found:kernel_allcompare_build(build), found.result, { found.proof })
end
function Kernel.KernelAllCompareFound:kernel_materialize_allcompare(request, build)
  return build.trip:kernel_materialize_allcompare_trip(self, request, build)
end
function Kernel.KernelLoopAnalysisReadyAllCompare:materialize_kernel_selection(_selection, request)
  local found = Kernel.KernelAllCompareFound(self.result, self.proof)
  return self.build.trip:kernel_materialize_allcompare_trip(found, request, self.build)
end
function Kernel.KernelLoopPlanSkeleton:materialize_kernel_build(request, build)
  if #build.effects.entries == 0 then
    return Kernel.KernelNoPlan(Kernel.KernelSubjectLoop(request.fact.loop), {})
  end
  return planned(request, build, self.result, {})
end

function Kernel.KernelNoPlan:schedule_eligibility() return Kernel.KernelScheduleIneligible(self.subject, self.rejects) end
function Kernel.KernelPlanned:schedule_eligibility() return Kernel.KernelScheduleEligible(self) end

function Kernel.KernelCounterMissing:kernel_initial_analysis(fact)
  return Kernel.KernelLoopAnalysisRejected(fact, { self.reject })
end
function Kernel.KernelCounterAmbiguous:kernel_initial_analysis(fact)
  return Kernel.KernelLoopAnalysisRejected(fact, { self.reject })
end
function Kernel.KernelCounterSelected:kernel_initial_analysis(fact)
  return Kernel.KernelLoopAnalysisReady(Kernel.KernelLoopPlanBuild(
    fact.domain, fact.trip, self.counter,
    Kernel.KernelLaneProjection({}),
    Kernel.KernelBindingProjection({}),
    Kernel.KernelEffectProjection({}),
    Kernel.KernelProofProjection({})))
end
function Kernel.KernelLoopFactEntry:kernel_initial_analysis()
  return self.counter:kernel_initial_analysis(self)
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
    object.object,
    { access.id },
    access.base,
    access.access.ty,
    access.pattern,
    { backend },
    object.fact)
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
  if self.value == value then return Kernel.KernelObjectFound(object.id, object) end
  return current
end
function Mem.MemProvFieldPointer:kernel_match_value(object, value, current)
  if self.ptr_value == value then return Kernel.KernelObjectFound(object.id, object) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_local(object, local_id, current) return current end
function Mem.MemProvLocal:kernel_match_local(object, local_id, current)
  if self.local_id == local_id then return Kernel.KernelObjectFound(object.id, object) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_global(object, global, current) return current end
function Mem.MemProvGlobal:kernel_match_global(object, global, current)
  if self.global == global then return Kernel.KernelObjectFound(object.id, object) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_data(object, data, current) return current end
function Mem.MemProvData:kernel_match_data(object, data, current)
  if self.data == data then return Kernel.KernelObjectFound(object.id, object) end
  return current
end
function Mem.MemObjectProvenance:kernel_match_projection(object, parent, projection, byte_offset, current) return current end
function Mem.MemProvProjection:kernel_match_projection(object, parent, projection, byte_offset, current)
  if self.parent == parent and self.projection == projection and self.byte_offset == byte_offset then return Kernel.KernelObjectFound(object.id, object) end
  return current
end

local function object_for_value(objects, access, value)
  local current = Kernel.KernelObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_value(object, value, current) end
  return current
end
local function object_for_local(objects, access, local_id)
  local current = Kernel.KernelObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_local(object, local_id, current) end
  return current
end
local function object_for_global(objects, access, global)
  local current = Kernel.KernelObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_global(object, global, current) end
  return current
end
local function object_for_data(objects, access, data)
  local current = Kernel.KernelObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_data(object, data, current) end
  return current
end
function Mem.MemBaseValue:kernel_object_for_access(objects, access) return object_for_value(objects, access, self.value) end
function Mem.MemBaseArgument:kernel_object_for_access(objects, access) return object_for_value(objects, access, self.value) end
function Mem.MemBaseLocal:kernel_object_for_access(objects, access) return object_for_local(objects, access, self.local_id) end
function Mem.MemBaseGlobal:kernel_object_for_access(objects, access) return object_for_global(objects, access, self.global) end
function Mem.MemBaseData:kernel_object_for_access(objects, access) return object_for_data(objects, access, self.data) end
function Mem.MemBaseUnknown:kernel_object_for_access(objects, access) return Kernel.KernelObjectMissing(access) end
function Kernel.KernelObjectMissing:kernel_projection_for_access(objects, access, projection, byte_offset) return self end
function Kernel.KernelObjectFound:kernel_projection_for_access(objects, access, projection, byte_offset)
  local current = Kernel.KernelObjectMissing(access)
  for _, object in ipairs(objects) do current = object.provenance:kernel_match_projection(object, self.object, projection, byte_offset, current) end
  return current
end
function Mem.MemBaseProjection:kernel_object_for_access(objects, access)
  return self.base:kernel_object_for_access(objects, access):kernel_projection_for_access(objects, access, self.projection, self.byte_offset)
end

function Kernel.KernelObjectMissing:kernel_analyze_object(input, analysis, access)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "memory access has no canonical object projection"))
end
function Kernel.KernelObjectFound:kernel_analyze_object(input, analysis, access)
  return input.mem:project_accesses():backend_for_access(access.id):kernel_analyze_backend(input, analysis, access, self)
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
function Value.ValueFact:kernel_index_expr_contribution(_value, current) return current end
function Value.ValueExprFact:kernel_index_expr_contribution(value, current)
  if self.value == value then return self.expr end
  return current
end
function Value.ValueFactSet:kernel_index_expr(value)
  local result = Value.ValueExprValue(value)
  for i = 1, #self.values do
    result = self.values[i]:kernel_index_expr_contribution(value, result)
  end
  return result
end
function Value.ValueExpr:kernel_resolve_index_expr(_flow, _values) return self end
function Value.ValueExprValue:kernel_resolve_index_expr(flow, values)
  return flow:kernel_resolve_index_value(
    Kernel.KernelIndexExprProjectionInput(values, self.value))
end
function Value.ValueExprAffine:kernel_resolve_index_expr(_flow, _values)
  local affine = self.affine
  if tonumber(affine.constant) == 0 and #affine.terms == 1
      and tonumber(affine.terms[1].coeff) == 1 then
    return Value.ValueExprValue(affine.terms[1].value)
  end
  return self
end
function Value.ValueExprCast:kernel_resolve_index_expr(flow, values)
  return Value.ValueExprCast(self.op, self.from, self.to,
    self.value:kernel_resolve_index_expr(flow, values))
end
function Value.ValueExprAdd:kernel_resolve_index_expr(flow, values)
  return Value.ValueExprAdd(self.a:kernel_resolve_index_expr(flow, values),
    self.b:kernel_resolve_index_expr(flow, values), self.ty, self.sem)
end
function Value.ValueExprSub:kernel_resolve_index_expr(flow, values)
  return Value.ValueExprSub(self.a:kernel_resolve_index_expr(flow, values),
    self.b:kernel_resolve_index_expr(flow, values), self.ty, self.sem)
end
function Flow.FlowFactSet:kernel_resolve_index_value(input)
  local found = {}
  for i = 1, #self.edges do
    for j = 1, #self.edges[i].args do
      local arg = self.edges[i].args[j]
      if arg.dst_param == input.value then found[#found + 1] = arg.src end
    end
  end
  if #found == 1 and found[1] ~= input.value then
    return input.values:kernel_index_expr(found[1])
      :kernel_resolve_index_expr(self, input.values)
  end
  return input.values:kernel_index_expr(input.value)
end
function Mem.MemIndexNone:kernel_index_expr(_input) return Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyIndex, require("lalin.schema.core").LitInt("0"))) end
function Mem.MemIndexValue:kernel_index_expr(input)
  return input.values:kernel_index_expr(self.value)
    :kernel_resolve_index_expr(input.flow, input.values)
end
function Mem.MemIndexInduction:kernel_index_expr(input)
  return input.values:kernel_index_expr(self.value)
    :kernel_resolve_index_expr(input.flow, input.values)
end
function Kernel.KernelLaneMissing:kernel_bind_load(input, analysis, op, access)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "load has no analyzed kernel lane"))
end
function Kernel.KernelLaneFound:kernel_bind_load(input, analysis, op, access)
  return analysis:kernel_add_binding(input, op.dst, op.access.ty, Kernel.KernelExprLaneLoad(self.entry.lane, access.index:kernel_index_expr(input)))
end
function Kernel.KernelLaneMissing:kernel_store_effect(input, analysis, op, access, inst)
  return analysis:kernel_reject(input.fact, Kernel.KernelRejectUnsupportedMemory(access.id, "store has no analyzed kernel lane"))
end
function Kernel.KernelLaneFound:kernel_store_effect(input, analysis, op, access, inst)
  local value = analysis.build.bindings:lookup(op.value):kernel_effect_value()
  return analysis:kernel_add_effect(input, inst, Kernel.KernelEffectStore(
    self.entry.lane, access.index:kernel_index_expr(input), value))
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
function Kernel.KernelDomainAnalysis:kernel_consider_domain_shape(_shape, _input)
  return self
end
function Kernel.KernelDomainAnalysisAllowed:kernel_consider_domain_shape(shape, input)
  return shape:kernel_domain_analysis(input)
end
function Flow.FlowDomainShape:kernel_domain_analysis(_input)
  return Kernel.KernelDomainAnalysisAllowed
end
local function scalar_domain(input, reason)
  return Kernel.KernelDomainAnalysisScalar(
    Kernel.KernelRejectUnsupportedSubject(
      Kernel.KernelSubjectDomain(input.fact.domain), reason))
end
function Flow.FlowDomainShapeRangeND:kernel_domain_analysis(input)
  if #self.axes == 1 then return Kernel.KernelDomainAnalysisAllowed end
  return scalar_domain(input,
    "multi-axis range retains canonical scalar lowering")
end
function Flow.FlowDomainShapeTiledND:kernel_domain_analysis(input)
  return scalar_domain(input,
    "tiled domain retains canonical scalar lowering")
end
function Flow.FlowDomainShapeWindowND:kernel_domain_analysis(input)
  if #self.axes == 1 and #self.windows == 1 then
    return Kernel.KernelDomainAnalysisAllowed
  end
  return scalar_domain(input,
    "multi-axis window retains canonical scalar lowering")
end
function Flow.FlowFactSet:kernel_domain_analysis(input)
  local analysis = Kernel.KernelDomainAnalysisAllowed
  for i = 1, #self.domain_shapes do
    local fact = self.domain_shapes[i]
    if fact.domain == input.fact.domain then
      analysis = analysis:kernel_consider_domain_shape(fact.shape, input)
    end
  end
  return analysis
end
function Kernel.KernelDomainAnalysisAllowed:kernel_analyze_domain(input)
  return input.graph:kernel_analyze_loop(input)
end
function Kernel.KernelDomainAnalysisScalar:kernel_analyze_domain(input)
  return Kernel.KernelLoopAnalysisRejected(input.fact, { self.reject })
end
function Kernel.KernelAllCompareMissing:kernel_apply_allcompare_analysis(analysis) return analysis end
function Kernel.KernelAllCompareFound:kernel_apply_allcompare_analysis(analysis)
  return Kernel.KernelLoopAnalysisReadyAllCompare(analysis.build, self.result, self.proof)
end
function Kernel.KernelLoopAnalysisRejected:kernel_detect_allcompare(_input) return self end
function Kernel.KernelLoopAnalysisReadyAllCompare:kernel_detect_allcompare(_input) return self end
function Kernel.KernelLoopAnalysisReady:kernel_detect_allcompare(input)
  if #self.build.effects.entries ~= 0 then return self end
  return input:kernel_allcompare_analysis(self.build):kernel_apply_allcompare_analysis(self)
end
function Kernel.KernelLoopAnalysisInput:analyze_kernel_loop()
  return self.flow:kernel_domain_analysis(self):kernel_analyze_domain(self):kernel_detect_allcompare(self)
end

function Kernel.KernelModulePlanRequest:plan_kernels()
  local projection = self.flow:project_kernel_loop_facts(self.values, self.trips)
  local plans = {}
  for _, fact in ipairs(projection.loops) do
    local candidate = fact:kernel_candidate(projection)
    local analysis_input = Kernel.KernelLoopAnalysisInput(self.module, self.graph, self.flow, self.values, self.mem, self.effects, fact, candidate)
    local analysis = analysis_input:analyze_kernel_loop()
    local request = Kernel.KernelLoopPlanRequest(fact, candidate, analysis)
    plans[#plans + 1] = analysis:materialize_kernel_selection(candidate:select_kernel_loop_plan(), request)
  end
  return Kernel.KernelModulePlan(self.module.id, self.flow, self.values, self.mem, self.effects, plans)
end
function Mem.MemSemanticFactSet:plan_kernels(module, graph, flow, values, effects)
  local semantic_trips = flow:compute_semantic_flow(module, graph):project_kernel_trips()
  local trips = semantic_trips:merged(values:project_kernel_trips())
  return Kernel.KernelModulePlanRequest(
    module, graph, flow, values, self, effects, trips):plan_kernels()
end
