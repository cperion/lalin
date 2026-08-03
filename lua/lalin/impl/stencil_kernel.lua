-- Canonical KernelPlanned -> StencilComputation projection.
require("lalin.schema_v2")
require("lalin.impl.code_mem")

local Core = require("lalin.schema_v2.core")
local Code = require("lalin.schema_v2.code")
local Graph = require("lalin.schema_v2.graph")
local Flow = require("lalin.schema_v2.flow")
local Mem = require("lalin.schema_v2.mem")
local Value = require("lalin.schema_v2.value")
local Kernel = require("lalin.schema_v2.kernel")
local Schedule = require("lalin.schema_v2.schedule")
local Stencil = require("lalin.schema_v2.stencil")

local function append_one(values, value)
  local result = {}
  for i = 1, #values do result[i] = values[i] end
  result[#result + 1] = value
  return result
end

local function sanitized(text)
  local result = tostring(text):gsub("[^%w_]", "_")
  if result:match("^%d") then result = "_" .. result end
  return result ~= "" and result or "value"
end

function Flow.FlowFactSet:stencil_kernel_loop_fact(loop)
  local found = {}
  for _, fact in ipairs(self.loops) do
    if fact.loop == loop then found[#found + 1] = fact end
  end
  if #found == 0 then
    return Stencil.StencilKernelLoopFactMissing(Stencil.StencilKernelMissingLoopFact(loop))
  end
  if #found > 1 then
    return Stencil.StencilKernelLoopFactAmbiguous(Stencil.StencilKernelAmbiguousLoopFact(loop, #found))
  end
  return Stencil.StencilKernelLoopFactFound(found[1])
end

function Graph.CodeGraph:stencil_kernel_loop_owner(loop)
  local found = {}
  for _, func in ipairs(self.funcs) do
    for _, candidate in ipairs(func.loops) do
      if candidate.id == loop then found[#found + 1] = func.func end
    end
  end
  if #found == 0 then
    return Stencil.StencilKernelLoopOwnerMissing(Stencil.StencilKernelMissingLoopOwner(loop))
  end
  if #found > 1 then
    return Stencil.StencilKernelLoopOwnerAmbiguous(Stencil.StencilKernelAmbiguousLoopOwner(loop, #found))
  end
  return Stencil.StencilKernelLoopOwnerFound(found[1])
end

function Stencil.StencilKernelSemanticIterationIgnored:stencil_append_semantic_match(found)
  return found
end
function Stencil.StencilKernelSemanticIterationMatched:stencil_append_semantic_match(found)
  return append_one(found, self.fact)
end
function Flow.FlowSemanticFactSet:stencil_kernel_semantic_iteration(loop)
  local found = {}
  for _, fact in ipairs(self.facts) do
    found = fact:stencil_kernel_semantic_match(loop):stencil_append_semantic_match(found)
  end
  if #found == 0 then
    return Stencil.StencilKernelSemanticIterationMissing(
      Stencil.StencilKernelMissingSemanticIteration(loop))
  end
  if #found > 1 then
    return Stencil.StencilKernelSemanticIterationAmbiguous(
      Stencil.StencilKernelAmbiguousSemanticIteration(loop, #found))
  end
  return Stencil.StencilKernelSemanticIterationFound(found[1])
end

function Flow.FlowLoopSemanticFact:stencil_kernel_semantic_match(_loop)
  return Stencil.StencilKernelSemanticIterationIgnored
end
function Flow.FlowLoopNormalizedCounted:stencil_kernel_semantic_match(loop)
  if self.loop == loop then return Stencil.StencilKernelSemanticIterationMatched(self) end
  return Stencil.StencilKernelSemanticIterationIgnored
end

function Flow.FlowPrimaryInduction:stencil_primary_induction(induction)
  return Stencil.StencilKernelPrimaryInductionSelected(induction)
end
function Flow.FlowDerivedInduction:stencil_primary_induction(_induction)
  return Stencil.StencilKernelPrimaryInductionIgnored
end
function Flow.FlowPointerInduction:stencil_primary_induction(_induction)
  return Stencil.StencilKernelPrimaryInductionIgnored
end
function Stencil.StencilKernelPrimaryInductionIgnored:stencil_append_primary(found)
  return found
end
function Stencil.StencilKernelPrimaryInductionSelected:stencil_append_primary(found)
  return append_one(found, self.induction)
end
function Flow.FlowLoopFacts:stencil_kernel_primary_induction()
  local found = {}
  for _, induction in ipairs(self.inductions) do
    found = induction.role:stencil_primary_induction(induction)
      :stencil_append_primary(found)
  end
  if #found == 0 then
    return Stencil.StencilKernelInductionMissing(
      Stencil.StencilKernelMissingPrimaryInduction(self.loop))
  end
  if #found > 1 then
    return Stencil.StencilKernelInductionAmbiguous(
      Stencil.StencilKernelAmbiguousPrimaryInduction(self.loop, #found))
  end
  return Stencil.StencilKernelInductionFound(found[1])
end

function Stencil.StencilKernelStepDefinitionMissing:stencil_add_step_definition(input)
  local contribution = input.contribution
  return Stencil.StencilKernelStepDefinitionFound(
    contribution.func, contribution.step, input.constant)
end
function Stencil.StencilKernelStepDefinitionFound:stencil_add_step_definition(input)
  return Stencil.StencilKernelStepDefinitionAmbiguous(input.contribution.step, 2)
end
function Stencil.StencilKernelStepDefinitionAmbiguous:stencil_add_step_definition(input)
  return Stencil.StencilKernelStepDefinitionAmbiguous(
    input.contribution.step, self.count + 1)
end
function Stencil.StencilKernelStepDefinitionAlias:stencil_add_step_definition(input)
  return Stencil.StencilKernelStepDefinitionAmbiguous(input.contribution.step, 2)
end

function Code.CodeInstOp:stencil_step_contribution(input) return input.lookup end
function Code.CodeInstConst:stencil_step_contribution(input)
  if self.dst ~= input.step then return input.lookup end
  return input.lookup:stencil_add_step_definition(
    Stencil.StencilKernelStepDefinitionInput(input, self.const))
end
function Code.CodeInstCast:stencil_step_contribution(input)
  if self.dst ~= input.step then return input.lookup end
  return Stencil.StencilKernelStepDefinitionAlias(input.func, input.step, self.value)
end
function Code.CodeInstAlias:stencil_step_contribution(input)
  if self.dst ~= input.step then return input.lookup end
  return Stencil.StencilKernelStepDefinitionAlias(input.func, input.step, self.src)
end
function Code.CodeFunc:stencil_kernel_step_lookup(step)
  local lookup = Stencil.StencilKernelStepDefinitionMissing(step)
  for _, block in ipairs(self.blocks) do
    for _, inst in ipairs(block.insts) do
      lookup = inst.op:stencil_step_contribution(
        Stencil.StencilKernelStepContributionInput(lookup, self.id, step))
    end
  end
  return lookup
end

function Stencil.StencilKernelLoopOwnerMissing:stencil_step_lookup(_cursor)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelLoopOwnerAmbiguous:stencil_step_lookup(_cursor)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelLoopOwnerFound:stencil_step_lookup(cursor)
  local step = cursor.semantic.fact.domain.step
  local lookup = Stencil.StencilKernelStepDefinitionMissing(step)
  for _, func in ipairs(cursor.request.module.funcs) do
    if func.id == self.func then lookup = func:stencil_kernel_step_lookup(step) end
  end
  return lookup:stencil_resolve_step(cursor)
end

function Stencil.StencilKernelStepDefinitionMissing:stencil_resolve_step(_cursor)
  return Stencil.StencilKernelIterationRejected(
    Stencil.StencilKernelMissingStepDefinition(self.step))
end
function Stencil.StencilKernelStepDefinitionAmbiguous:stencil_resolve_step(_cursor)
  return Stencil.StencilKernelIterationRejected(
    Stencil.StencilKernelAmbiguousStepDefinition(self.step, self.count))
end
function Stencil.StencilKernelStepDefinitionAlias:stencil_resolve_step(cursor)
  local lookup = Stencil.StencilKernelStepDefinitionMissing(self.source)
  for i = 1, #cursor.request.module.funcs do
    local func = cursor.request.module.funcs[i]
    if func.id == self.func then lookup = func:stencil_kernel_step_lookup(self.source) end
  end
  return lookup:stencil_resolve_step(cursor)
end
function Stencil.StencilKernelStepDefinitionFound:stencil_resolve_step(cursor)
  return self.constant:stencil_integer_step(
    Stencil.StencilKernelLiteralStepInput(self.step, self.constant))
    :stencil_build_iteration(cursor)
end

function Code.CodeConst:stencil_integer_step(input)
  return Stencil.StencilKernelStepRejected(
    Stencil.StencilKernelNonIntegerStep(input.step, input.constant))
end
function Code.CodeConstLiteral:stencil_integer_step(input)
  return self.literal:stencil_integer_literal_step(input)
end
function Core.Literal:stencil_integer_literal_step(input)
  return Stencil.StencilKernelStepRejected(
    Stencil.StencilKernelNonIntegerStep(input.step, input.constant))
end
function Core.LitInt:stencil_integer_literal_step(input)
  local value = tonumber(self.raw)
  if value == nil then
    return Stencil.StencilKernelStepRejected(
      Stencil.StencilKernelNonIntegerStep(input.step, input.constant))
  end
  if value == 0 then
    return Stencil.StencilKernelStepRejected(
      Stencil.StencilKernelZeroStep(input.step))
  end
  return Stencil.StencilKernelStepResolved(
    Stencil.StencilKernelStepConstant(input.step, math.abs(value)))
end

function Stencil.StencilKernelStepRejected:stencil_build_iteration(_cursor)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelStepResolved:stencil_build_iteration(cursor)
  local input = Stencil.StencilKernelIterationBuildInput(
    cursor.request.kernel, cursor.semantic.fact, cursor.induction, self.step,
    cursor.request.kernel.body.domain.trip)
  return cursor.semantic.fact.direction:stencil_build_iteration(input)
end

function Flow.FlowStopExclusive:stencil_stop_convention()
  return Stencil.StencilIterationStopExclusive
end
function Flow.FlowStopInclusive:stencil_stop_convention()
  return Stencil.StencilIterationStopInclusive
end
function Flow.FlowTripCountExact:stencil_kernel_trip()
  return Stencil.StencilKernelTripExact(self)
end
function Flow.FlowTripCountNonNegative:stencil_kernel_trip()
  return Stencil.StencilKernelTripNonNegative(self)
end
function Flow.FlowTripCountRejected:stencil_kernel_trip()
  return Stencil.StencilKernelIterationRejected(Stencil.StencilKernelRejectedTripCount(self))
end

function Flow.FlowLoopDirectionUnknown:stencil_build_iteration(_input)
  return Stencil.StencilKernelIterationRejected(
    Stencil.StencilKernelUnsupportedDirection(self))
end
function Flow.FlowLoopIncreasing:stencil_build_iteration(input)
  return input.trip:stencil_kernel_iteration_trip(
    Stencil.StencilKernelTripBuildInput(input, Stencil.StencilProducerForward))
end
function Flow.FlowLoopDecreasing:stencil_build_iteration(input)
  return input.trip:stencil_kernel_iteration_trip(
    Stencil.StencilKernelTripBuildInput(input, Stencil.StencilProducerBackward))
end
function Kernel.KernelTripKnown:stencil_kernel_iteration_trip(input)
  return self.trip_count:stencil_kernel_iteration_with_trip(input)
end
function Kernel.KernelTripUnavailable:stencil_kernel_iteration_trip(_input)
  return Stencil.StencilKernelIterationRejected(
    Stencil.StencilKernelUnavailableTrip(self))
end

function Flow.FlowTripCountRejected:stencil_kernel_iteration_with_trip(_input)
  return Stencil.StencilKernelIterationRejected(Stencil.StencilKernelRejectedTripCount(self))
end
function Flow.FlowTripCountExact:stencil_kernel_iteration_with_trip(input)
  local build = input.iteration
  return Stencil.StencilKernelIterationProjected(Stencil.StencilKernelIteration(
    build.semantic.loop, build.induction.value, build.induction.ty,
    build.semantic.domain.start, build.semantic.domain.stop, build.semantic.domain.step,
    build.step.magnitude, build.semantic.domain.stop_convention:stencil_stop_convention(),
    input.order, Stencil.StencilKernelTripExact(self)))
end
function Flow.FlowTripCountNonNegative:stencil_kernel_iteration_with_trip(input)
  local build = input.iteration
  return Stencil.StencilKernelIterationProjected(Stencil.StencilKernelIteration(
    build.semantic.loop, build.induction.value, build.induction.ty,
    build.semantic.domain.start, build.semantic.domain.stop, build.semantic.domain.step,
    build.step.magnitude, build.semantic.domain.stop_convention:stencil_stop_convention(),
    input.order, Stencil.StencilKernelTripNonNegative(self)))
end

function Stencil.StencilKernelInductionMissing:stencil_continue_iteration(_input)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelInductionAmbiguous:stencil_continue_iteration(_input)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelInductionFound:stencil_continue_iteration(input)
  return input.request.kernel.body.domain.counter:stencil_align_counter(
    Stencil.StencilKernelCounterAlignmentInput(input, self.induction))
end
function Kernel.KernelCounterAbsent:stencil_align_counter(input)
  return Stencil.StencilKernelIterationRejected(
    Stencil.StencilKernelMissingCounter(input.continuation.request.kernel.id))
end
function Kernel.KernelCounterValue:stencil_align_counter(input)
  if self.value ~= input.induction.value then
    return Stencil.StencilKernelIterationRejected(
      Stencil.StencilKernelIterationFactMismatch(
        input.continuation.semantic.fact.loop,
        "kernel counter does not match primary induction"))
  end
  local cursor = Stencil.StencilKernelIterationCursor(
    input.continuation.request, input.continuation.semantic, input.induction)
  return input.continuation.request.graph:stencil_kernel_loop_owner(
    input.continuation.semantic.fact.loop):stencil_step_lookup(cursor)
end

function Stencil.StencilKernelSemanticIterationMissing:stencil_continue_iteration(_input)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelSemanticIterationAmbiguous:stencil_continue_iteration(_input)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelSemanticIterationFound:stencil_continue_iteration(input)
  if input.loop_fact.counted ~= self.fact.domain then
    return Stencil.StencilKernelIterationRejected(
      Stencil.StencilKernelIterationFactMismatch(
        self.fact.loop, "semantic counted domain does not match loop facts"))
  end
  if self.fact.direction ~= self.fact.domain.direction then
    return Stencil.StencilKernelIterationRejected(
      Stencil.StencilKernelIterationFactMismatch(
        self.fact.loop, "semantic direction does not match counted domain"))
  end
  if input.request.kernel.body.domain.domain ~= input.loop_fact.domain then
    return Stencil.StencilKernelIterationRejected(
      Stencil.StencilKernelIterationFactMismatch(
        self.fact.loop, "kernel domain does not match loop facts"))
  end
  local continuation = Stencil.StencilKernelInductionContinuationInput(
    input.request, self)
  return input.loop_fact:stencil_kernel_primary_induction()
    :stencil_continue_iteration(continuation)
end

function Stencil.StencilKernelLoopFactMissing:stencil_continue_iteration(_input)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelLoopFactAmbiguous:stencil_continue_iteration(_input)
  return Stencil.StencilKernelIterationRejected(self.reject)
end
function Stencil.StencilKernelLoopFactFound:stencil_continue_iteration(input)
  local continuation = Stencil.StencilKernelSemanticContinuationInput(
    input.request, self.fact)
  return input.request.semantics:stencil_kernel_semantic_iteration(input.loop)
    :stencil_continue_iteration(continuation)
end

function Kernel.KernelSubjectFunction:stencil_project_iteration(_input)
  return Stencil.StencilKernelIterationRejected(Stencil.StencilKernelUnsupportedSubject(self))
end
function Kernel.KernelSubjectDomain:stencil_project_iteration(_input)
  return Stencil.StencilKernelIterationRejected(Stencil.StencilKernelUnsupportedSubject(self))
end
function Kernel.KernelSubjectFragment:stencil_project_iteration(_input)
  return Stencil.StencilKernelIterationRejected(Stencil.StencilKernelUnsupportedSubject(self))
end
function Kernel.KernelSubjectLoop:stencil_project_iteration(input)
  return input.flow:stencil_kernel_loop_fact(self.loop):stencil_continue_iteration(
    Stencil.StencilKernelLoopFactContinuationInput(input, self.loop))
end
function Stencil.StencilKernelIterationInput:project_iteration()
  if self.module.id ~= self.flow.module then
    return Stencil.StencilKernelIterationRejected(
      Stencil.StencilKernelModuleMismatch(self.module.id, self.flow.module))
  end
  if self.module.id ~= self.semantics.module then
    return Stencil.StencilKernelIterationRejected(
      Stencil.StencilKernelModuleMismatch(self.module.id, self.semantics.module))
  end
  return self.kernel.subject:stencil_project_iteration(self)
end

function Stencil.StencilAccessByKernelLaneProjection:lookup(lane)
  for _, entry in ipairs(self.entries) do
    if entry.lane == lane then return Stencil.StencilAccessByKernelLaneFound(entry) end
  end
  return Stencil.StencilAccessByKernelLaneMissing(lane)
end
function Stencil.StencilStreamByKernelValueProjection:lookup(value)
  for _, entry in ipairs(self.entries) do
    if entry.binding.id == value then return Stencil.StencilStreamByKernelValueFound(entry) end
  end
  return Stencil.StencilStreamByKernelValueMissing(value)
end

function Stencil.StencilKernelConstructionState:with_access(input)
  return Stencil.StencilKernelConstructionState(
    self.kernel, self.iteration, self.domain, self.producer,
    Stencil.StencilAccessByKernelLaneProjection(append_one(
      self.access_by_lane.entries,
      Stencil.StencilAccessByKernelLaneEntry(input.lane, input.access))),
    self.stream_by_value, self.result_streams, self.sinks, self.deferred_reductions,
    self.legality, self.proofs, self.next_stream_ordinal)
end
function Stencil.StencilKernelConstructionState:with_legality(legality)
  return Stencil.StencilKernelConstructionState(
    self.kernel, self.iteration, self.domain, self.producer, self.access_by_lane,
    self.stream_by_value, self.result_streams, self.sinks, self.deferred_reductions,
    legality, self.proofs, self.next_stream_ordinal)
end
function Stencil.StencilKernelConstructionState:with_stream(input)
  return Stencil.StencilKernelConstructionState(
    self.kernel, self.iteration, self.domain, self.producer, self.access_by_lane,
    Stencil.StencilStreamByKernelValueProjection(append_one(
      self.stream_by_value.entries,
      Stencil.StencilStreamByKernelValueEntry(
        input.source, input.binding, input.definition))),
    self.result_streams, self.sinks, self.deferred_reductions,
    self.legality, self.proofs,
    self.next_stream_ordinal + 1)
end
function Stencil.StencilKernelConstructionState:with_result_stream(definition)
  return Stencil.StencilKernelConstructionState(
    self.kernel, self.iteration, self.domain, self.producer, self.access_by_lane,
    self.stream_by_value, append_one(self.result_streams, definition),
    self.sinks, self.deferred_reductions, self.legality, self.proofs,
    self.next_stream_ordinal + 1)
end
function Stencil.StencilKernelConstructionState:with_sinks(sinks)
  local combined = self.sinks
  for _, sink in ipairs(sinks) do combined = append_one(combined, sink) end
  return Stencil.StencilKernelConstructionState(
    self.kernel, self.iteration, self.domain, self.producer, self.access_by_lane,
    self.stream_by_value, self.result_streams, combined, self.deferred_reductions,
    self.legality, self.proofs, self.next_stream_ordinal)
end
function Stencil.StencilKernelConstructionState:with_deferred_reduction(reduction)
  return Stencil.StencilKernelConstructionState(
    self.kernel, self.iteration, self.domain, self.producer, self.access_by_lane,
    self.stream_by_value, self.result_streams, self.sinks,
    append_one(self.deferred_reductions, reduction),
    self.legality, self.proofs, self.next_stream_ordinal)
end

function Stencil.StencilKernelConstructionCollecting:stencil_reject(reject)
  return Stencil.StencilKernelConstructionRejected(self.state, { reject })
end
function Stencil.StencilKernelConstructionFinalizable:stencil_reject(reject)
  return Stencil.StencilKernelConstructionRejected(self.state, { reject })
end
function Stencil.StencilKernelConstructionRejected:stencil_reject(reject)
  return Stencil.StencilKernelConstructionRejected(self.state, append_one(self.rejects, reject))
end

function Flow.FlowFactSet:stencil_domain_shape_lookup(domain)
  local facts = {}
  for i = 1, #self.domain_shapes do
    if self.domain_shapes[i].domain == domain then
      facts[#facts + 1] = self.domain_shapes[i]
    end
  end
  if #facts == 0 then return Stencil.StencilKernelDomainShapeMissing(domain) end
  if #facts > 1 then
    return Stencil.StencilKernelDomainShapeAmbiguous(domain, facts)
  end
  return Stencil.StencilKernelDomainShapeFound(facts[1])
end
function Flow.FlowDomainForward:stencil_producer_order()
  return Stencil.StencilProducerForward
end
function Flow.FlowDomainBackward:stencil_producer_order()
  return Stencil.StencilProducerBackward
end
function Flow.FlowWindowBoundaryReject:stencil_window_boundary()
  return Stencil.StencilWindowBoundaryReject
end
function Flow.FlowWindowBoundaryClamp:stencil_window_boundary()
  return Stencil.StencilWindowBoundaryClamp
end
function Flow.FlowWindowBoundaryWrap:stencil_window_boundary()
  return Stencil.StencilWindowBoundaryWrap
end
function Flow.FlowWindowBoundaryZero:stencil_window_boundary()
  return Stencil.StencilWindowBoundaryZero
end
function Flow.FlowDomainShape:stencil_resolve_kernel_domain(input)
  return Stencil.StencilKernelDomainRejected(
    Stencil.StencilKernelUnsupportedDomainShape(
      self, "domain shape is outside scalar counted projection"))
end
function Flow.FlowDomainShapeRange1D:stencil_resolve_kernel_domain(input)
  local iteration = input.iteration
  if self.index_ty ~= iteration.index_ty
      or self.start ~= Value.ValueExprValue(iteration.start)
      or self.stop ~= Value.ValueExprValue(iteration.stop)
      or self.step ~= iteration.step_magnitude
      or self.order:stencil_producer_order() ~= iteration.order then
    return Stencil.StencilKernelDomainRejected(
      Stencil.StencilKernelUnsupportedDomainShape(
        self, "range shape disagrees with exact counted iteration"))
  end
  local producer = Stencil.StencilProducer(
    Stencil.StencilProducerOriginFlow(input.source.domain),
    Stencil.StencilProduceCountedRange1D(
      iteration.index_ty, Stencil.StencilBoundValue(Value.ValueExprValue(iteration.start)),
      Stencil.StencilBoundValue(Value.ValueExprValue(iteration.stop)),
      iteration.step_magnitude, iteration.order, iteration.stop_convention, iteration.trip))
  return Stencil.StencilKernelDomainResolved(
    Stencil.StencilKernelCountedDomain1D(input.source), producer)
end
function Flow.FlowDomainShapeWindowND:stencil_resolve_kernel_domain(input)
  local iteration = input.iteration
  if #self.axes ~= 1 or #self.windows ~= 1
      or self.axes[1].index_ty ~= iteration.index_ty
      or self.axes[1].start ~= Value.ValueExprValue(iteration.start)
      or self.axes[1].stop ~= Value.ValueExprValue(iteration.stop)
      or self.axes[1].step ~= iteration.step_magnitude
      or self.axes[1].order:stencil_producer_order() ~= iteration.order then
    return Stencil.StencilKernelDomainRejected(
      Stencil.StencilKernelUnsupportedDomainShape(
        self, "initial counted-window projection requires one exact axis and window"))
  end
  local source_window = self.windows[1]
  local window = Stencil.StencilWindowAxis(
    Stencil.StencilWindowExtent(
      Stencil.StencilElementDistance(source_window.before),
      Stencil.StencilElementDistance(source_window.after)),
    source_window.boundary:stencil_window_boundary())
  local axis = Stencil.StencilProducerAxis(
    iteration.index_ty, Stencil.StencilBoundValue(Value.ValueExprValue(iteration.start)),
    Stencil.StencilBoundValue(Value.ValueExprValue(iteration.stop)),
    iteration.step_magnitude, iteration.order, Stencil.StencilIndexAnonymous)
  local producer = Stencil.StencilProducer(
    Stencil.StencilProducerOriginFlow(input.source.domain),
    Stencil.StencilProduceCountedWindow1D(
      iteration.index_ty, axis.start, axis.stop, axis.step, axis.order,
      iteration.stop_convention, iteration.trip, window))
  return Stencil.StencilKernelDomainResolved(
    Stencil.StencilKernelCountedWindow1D(input.source, window), producer)
end
function Stencil.StencilKernelDomainShapeFound:stencil_resolve_kernel_domain(iteration)
  return self.fact.shape:stencil_resolve_kernel_domain(
    Stencil.StencilKernelDomainProjectionInput(iteration, self.fact))
end
function Stencil.StencilKernelDomainShapeMissing:stencil_resolve_kernel_domain(_input)
  return Stencil.StencilKernelDomainRejected(
    Stencil.StencilKernelMissingDomainShape(self.domain))
end
function Stencil.StencilKernelDomainShapeAmbiguous:stencil_resolve_kernel_domain(_input)
  return Stencil.StencilKernelDomainRejected(
    Stencil.StencilKernelAmbiguousDomainShape(self.domain, #self.facts))
end
function Kernel.KernelEquivalenceProof:stencil_initialize_construction(input)
  return Stencil.StencilKernelConstructionCollecting(Stencil.StencilKernelConstructionState(
    input.kernel, input.iteration, input.domain, input.producer,
    Stencil.StencilAccessByKernelLaneProjection({}),
    Stencil.StencilStreamByKernelValueProjection({}), {}, {}, {},
    Stencil.StencilFusionLegality({}, {}, {}), self.proofs, 1))
end
function Kernel.KernelEquivalenceRejected:stencil_initialize_construction(input)
  local state = Stencil.StencilKernelConstructionState(
    input.kernel, input.iteration, input.domain, input.producer,
    Stencil.StencilAccessByKernelLaneProjection({}),
    Stencil.StencilStreamByKernelValueProjection({}), {}, {}, {},
    Stencil.StencilFusionLegality({}, {}, {}), {}, 1)
  return Stencil.StencilKernelConstructionRejected(state, {
    Stencil.StencilKernelEquivalenceRejected(self.failures),
  })
end

function Mem.MemLoad:stencil_access_role(_input)
  return Stencil.StencilKernelAccessRoleProjected(Stencil.StencilAccessRead)
end
function Mem.MemStore:stencil_access_role(_input)
  return Stencil.StencilKernelAccessRoleProjected(Stencil.StencilAccessWrite)
end
function Mem.MemAtomicLoad:stencil_access_role(_input)
  return Stencil.StencilKernelAccessRoleProjected(Stencil.StencilAccessRead)
end
function Mem.MemAtomicStore:stencil_access_role(_input)
  return Stencil.StencilKernelAccessRoleProjected(Stencil.StencilAccessWrite)
end
function Mem.MemAtomicRmw:stencil_access_role(_input)
  return Stencil.StencilKernelAccessRoleProjected(Stencil.StencilAccessReadWrite)
end
function Mem.MemAtomicCas:stencil_access_role(_input)
  return Stencil.StencilKernelAccessRoleProjected(Stencil.StencilAccessReadWrite)
end

function Stencil.StencilKernelAccessRoleRejected:stencil_prepare_access(_input)
  return Stencil.StencilKernelAccessPreparationRejected(self.reject)
end
function Stencil.StencilKernelAccessRoleProjected:stencil_prepare_access(input)
  return input.access.pattern:stencil_access_layout(Stencil.StencilKernelAccessLayoutInput(
    input.construction, input.lane, input.access, self.role))
end
function Mem.MemIndexNone:stencil_scalar_access_layout(input)
  return Stencil.StencilKernelAccessPrepared(input.lane, Stencil.StencilAccess(
    sanitized(input.lane.id.text), input.role, input.lane.elem_ty,
    Stencil.StencilAccessDirect(
      Stencil.StencilLayoutScalar(Stencil.StencilScalarValueNone))))
end
function Mem.MemIndexValue:stencil_scalar_access_layout(input)
  if #input.lane.backend_info ~= 1 then
    return Stencil.StencilKernelAccessPreparationRejected(
      Stencil.StencilKernelUnsupportedLane(
        input.lane, "indexed scalar access requires one backend access fact"))
  end
  return input.lane.backend_info[1].deref_bytes:stencil_access_stride(
    Stencil.StencilKernelStrideInput(input, 1))
end
function Mem.MemIndexInduction:stencil_scalar_access_layout(input)
  if #input.lane.backend_info ~= 1 then
    return Stencil.StencilKernelAccessPreparationRejected(
      Stencil.StencilKernelUnsupportedLane(
        input.lane, "induction access requires one backend access fact"))
  end
  return input.lane.backend_info[1].deref_bytes:stencil_access_stride(
    Stencil.StencilKernelStrideInput(input, 1))
end
function Mem.MemAccessScalar:stencil_access_layout(input)
  return input.access.index:stencil_scalar_access_layout(input)
end
function Mem.MemDerefBytesKnown:stencil_access_stride(input)
  return Stencil.StencilKernelAccessPrepared(input.layout.lane, Stencil.StencilAccess(
    sanitized(input.layout.lane.id.text), input.layout.role, input.layout.lane.elem_ty,
    Stencil.StencilAccessDirect(
      Stencil.StencilLayoutContiguous(self.bytes * input.stride_elems))))
end
function Mem.MemDerefBytesUnavailable:stencil_access_stride(input)
  return Stencil.StencilKernelAccessPreparationRejected(
    Stencil.StencilKernelUnsupportedLane(
      input.layout.lane, "element byte size is unavailable"))
end
function Mem.MemAccessContiguous:stencil_access_layout(input)
  if #input.lane.backend_info ~= 1 then
    return Stencil.StencilKernelAccessPreparationRejected(
      Stencil.StencilKernelUnsupportedLane(
        input.lane, "contiguous lane requires one backend access fact"))
  end
  return input.lane.backend_info[1].deref_bytes:stencil_access_stride(
    Stencil.StencilKernelStrideInput(input, 1))
end
function Mem.MemAccessStrided:stencil_access_layout(input)
  if #input.lane.backend_info ~= 1 then
    return Stencil.StencilKernelAccessPreparationRejected(
      Stencil.StencilKernelUnsupportedLane(
        input.lane, "strided lane requires one backend access fact"))
  end
  return input.lane.backend_info[1].deref_bytes:stencil_access_stride(
    Stencil.StencilKernelStrideInput(input, self.stride_elems))
end
function Mem.MemAccessGather:stencil_access_layout(input)
  return Stencil.StencilKernelAccessPreparationRejected(
    Stencil.StencilKernelUnsupportedLane(input.lane, "gather lanes are not in the initial canonical C materializer"))
end
function Mem.MemAccessScatter:stencil_access_layout(input)
  return Stencil.StencilKernelAccessPreparationRejected(
    Stencil.StencilKernelUnsupportedLane(input.lane, "scatter lanes require a typed index stream"))
end
function Mem.MemAccessUnknown:stencil_access_layout(input)
  return Stencil.StencilKernelAccessPreparationRejected(
    Stencil.StencilKernelUnsupportedLane(input.lane, "memory access pattern is unknown"))
end

function Stencil.StencilKernelAccessPrepared:stencil_apply_access(construction)
  return Stencil.StencilKernelConstructionCollecting(
    construction.state:with_access(
      Stencil.StencilKernelStateAccessInput(self.lane, self.access)))
end
function Stencil.StencilKernelAccessPreparationRejected:stencil_apply_access(construction)
  return construction:stencil_reject(self.reject)
end
function Mem.MemAccessMissing:stencil_prepare_lane(input)
  return input.construction:stencil_reject(
    Stencil.StencilKernelMissingLaneAccess(input.contribution.lane, self.access))
end
function Mem.MemAccessFound:stencil_prepare_lane(input)
  local contribution = input.contribution
  local fact_input = Stencil.StencilKernelAccessFactInput(
    input.construction, contribution.lane, self.access)
  return self.access.op:stencil_access_role(fact_input):stencil_prepare_access(fact_input)
    :stencil_apply_access(input.construction)
end
function Stencil.StencilAccessByKernelLaneFound:stencil_contribute_lane(input)
  return input.construction:stencil_reject(
    Stencil.StencilKernelDuplicateLane(self.entry.lane))
end
function Stencil.StencilAccessByKernelLaneMissing:stencil_contribute_lane(input)
  local contribution = input.contribution
  if #contribution.lane.accesses ~= 1 then
    return input.construction:stencil_reject(Stencil.StencilKernelUnsupportedLane(
      contribution.lane, "canonical stencil lanes require exactly one memory access"))
  end
  return contribution.mem:project_accesses():mem_access(contribution.lane.accesses[1])
    :stencil_prepare_lane(input)
end
function Stencil.StencilKernelConstructionCollecting:stencil_contribute_access(input)
  local resolution = Stencil.StencilKernelAccessResolutionInput(self, input)
  return self.state.access_by_lane:lookup(input.lane):stencil_contribute_lane(resolution)
end
function Stencil.StencilKernelConstructionFinalizable:stencil_contribute_access(input)
  return self:stencil_reject(Stencil.StencilKernelConstructionIncomplete(self.state.kernel.id))
end
function Kernel.KernelBindingProjection:stencil_add_live_code_value(live, value)
  for i = 1, #self.entries do
    if self.entries[i].value == value then
      return Kernel.KernelExprKernelValue(
        self.entries[i].binding.id):stencil_add_live_binding(live)
    end
  end
  return live
end
function Value.ValueExpr:stencil_add_live_dependencies(live, _bindings) return live end
function Value.ValueExprValue:stencil_add_live_dependencies(live, bindings)
  return bindings:stencil_add_live_code_value(live, self.value)
end
function Value.ValueExprUnary:stencil_add_live_dependencies(live, bindings)
  return self.value:stencil_add_live_dependencies(live, bindings)
end
function Value.ValueExprCast:stencil_add_live_dependencies(live, bindings)
  return self.value:stencil_add_live_dependencies(live, bindings)
end
function Value.ValueExprBinary:stencil_add_live_dependencies(live, bindings)
  return self.b:stencil_add_live_dependencies(
    self.a:stencil_add_live_dependencies(live, bindings), bindings)
end
Value.ValueExprAdd.stencil_add_live_dependencies = Value.ValueExprBinary.stencil_add_live_dependencies
Value.ValueExprSub.stencil_add_live_dependencies = Value.ValueExprBinary.stencil_add_live_dependencies
Value.ValueExprMul.stencil_add_live_dependencies = Value.ValueExprBinary.stencil_add_live_dependencies
Value.ValueExprDiv.stencil_add_live_dependencies = Value.ValueExprBinary.stencil_add_live_dependencies
Value.ValueExprRem.stencil_add_live_dependencies = Value.ValueExprBinary.stencil_add_live_dependencies
function Value.ValueExprCmp:stencil_add_live_dependencies(live, bindings)
  return self.b:stencil_add_live_dependencies(
    self.a:stencil_add_live_dependencies(live, bindings), bindings)
end
function Value.ValueExprSelect:stencil_add_live_dependencies(live, bindings)
  live = self.cond:stencil_add_live_dependencies(live, bindings)
  live = self.t:stencil_add_live_dependencies(live, bindings)
  return self.f:stencil_add_live_dependencies(live, bindings)
end
function Kernel.KernelExpr:stencil_add_live_dependencies(live, _bindings) return live end
function Kernel.KernelExprValue:stencil_add_live_dependencies(live, bindings)
  return bindings:stencil_add_live_code_value(live, self.value)
end
function Kernel.KernelExprAlgebra:stencil_add_live_dependencies(live, bindings)
  return self.expr:stencil_add_live_dependencies(live, bindings)
end
function Kernel.KernelExprLaneLoad:stencil_add_live_dependencies(live, bindings)
  return self.index:stencil_add_live_dependencies(live, bindings)
end
function Kernel.KernelExprKernelValue:stencil_add_live_dependencies(live, _bindings)
  return self:stencil_add_live_binding(live)
end
function Kernel.KernelBindingProjection:stencil_complete_live_bindings(live)
  local previous = -1
  while previous ~= #live.values do
    previous = #live.values
    for i = 1, #self.entries do
      for j = 1, #live.values do
        if self.entries[i].binding.id == live.values[j] then
          live = self.entries[i].binding.expr:stencil_add_live_dependencies(live, self)
        end
      end
    end
  end
  return live
end
function Kernel.KernelExpr:stencil_add_live_binding(projection) return projection end
function Kernel.KernelExprKernelValue:stencil_add_live_binding(projection)
  for i = 1, #projection.values do
    if projection.values[i] == self.value then return projection end
  end
  return Stencil.StencilKernelLiveBindingProjection(
    append_one(projection.values, self.value))
end
function Kernel.KernelEffect:stencil_add_live_bindings(projection) return projection end
function Kernel.KernelEffectStore:stencil_add_live_bindings(projection)
  return self.value:stencil_add_live_binding(projection)
end
function Kernel.KernelResult:stencil_add_live_bindings(input) return input.live end
function Kernel.KernelResultValue:stencil_add_live_bindings(input)
  return self.expr:stencil_add_live_binding(input.live)
end
function Kernel.KernelResultFind:stencil_add_live_bindings(input)
  return self.src:stencil_add_live_binding(input.live)
end
function Kernel.KernelResultAll:stencil_add_live_bindings(input)
  return self.src:stencil_add_live_binding(input.live)
end
function Kernel.KernelResultAny:stencil_add_live_bindings(input)
  return self.src:stencil_add_live_binding(input.live)
end
function Kernel.KernelResultAllCompare:stencil_add_live_bindings(input)
  return self.right:stencil_add_live_binding(
    self.left:stencil_add_live_binding(input.live))
end
function Kernel.KernelResultReduction:stencil_add_live_bindings(input)
  return self.reduction.contribution:stencil_add_live_dependencies(
    input.live, input.bindings)
end
function Kernel.KernelBody:stencil_live_bindings()
  local projection = Stencil.StencilKernelLiveBindingProjection({})
  for i = 1, #self.effects.entries do
    projection = self.effects.entries[i].effect:stencil_add_live_bindings(projection)
  end
  projection = self.result:stencil_add_live_bindings(
    Stencil.StencilKernelResultLiveInput(projection, self.bindings))
  return self.bindings:stencil_complete_live_bindings(projection)
end
function Stencil.StencilKernelLiveBindingProjection:stencil_contribute_stream(input)
  for i = 1, #self.values do
    if self.values[i] == input.entry.binding.id then
      return input.construction:stencil_contribute_stream(
        Stencil.StencilKernelStreamContributionInput(input.entry))
    end
  end
  return input.construction
end
function Stencil.StencilKernelConstructionRejected:stencil_contribute_access(_input) return self end

function Kernel.KernelExprValue:stencil_prepare_stream(input)
  return Stencil.StencilKernelStreamPrepared(input.source, input.binding, Stencil.StencilStreamDef(
    input.id, input.binding.ty, Stencil.StencilStreamValueExpr(
      require("lalin.schema_v2.value").ValueExprValue(self.value), input.binding.ty)))
end
function Kernel.KernelExprAlgebra:stencil_prepare_stream(input)
  return Stencil.StencilKernelStreamPrepared(input.source, input.binding, Stencil.StencilStreamDef(
    input.id, input.binding.ty, Stencil.StencilStreamValueExpr(self.expr, input.binding.ty)))
end
function Value.ValueExpr:stencil_index_selection(input)
  return Stencil.StencilIndexExplicit(Stencil.StencilIndexPoint(input.index))
end
function Value.ValueExprValue:stencil_index_selection(input)
  if self.value == input.iteration.counter then return Stencil.StencilIndexProducer end
  return Stencil.StencilIndexExplicit(Stencil.StencilIndexPoint(input.index))
end
function Stencil.StencilKernelCountedDomain1D:stencil_lane_stream(input)
  local stream, access = input.stream, input.access
  local selection = stream.binding.expr.index:stencil_index_selection(
    Stencil.StencilKernelIndexSelectionInput(
      stream.construction.state.iteration, stream.binding.expr.index))
  return Stencil.StencilKernelStreamPrepared(
    stream.source, stream.binding, Stencil.StencilStreamDef(
      stream.id, stream.binding.ty, Stencil.StencilStreamAccess(
        Stencil.StencilAccessRef(access.entry.access.name), selection)))
end
function Value.ValueExpr:stencil_project_window_index(input)
  return Stencil.StencilKernelWindowIndexRejected(
    Stencil.StencilKernelUnsupportedWindowIndex(
      self, "window load index is not counter-relative"))
end
function Value.ValueExprValue:stencil_project_window_index(input)
  if self.value == input.iteration.counter then
    return Stencil.StencilKernelWindowIndexCenter
  end
  return Stencil.StencilKernelWindowIndexRejected(
    Stencil.StencilKernelUnsupportedWindowIndex(
      self, "window load index is not the primary counter"))
end
function Stencil.StencilKernelWindowIndexRejected:stencil_apply_window_offset(_input)
  return self
end
function Stencil.StencilKernelWindowIndexOffset:stencil_apply_window_offset(input)
  return Stencil.StencilKernelWindowIndexRejected(
    Stencil.StencilKernelUnsupportedWindowIndex(
      input.window.index, "nested counter-relative window offset is unsupported"))
end
function Stencil.StencilKernelWindowIndexCenter:stencil_apply_window_offset(input)
  return input.expr:stencil_window_offset_literal(input)
end
function Value.ValueExpr:stencil_window_offset_literal(input)
  return Stencil.StencilKernelWindowIndexRejected(
    Stencil.StencilKernelUnsupportedWindowIndex(
      input.window.index, "window offset is not an integer literal"))
end
function Value.ValueExprCast:stencil_window_offset_literal(input)
  return self.value:stencil_window_offset_literal(input)
end
function Value.ValueExprConst:stencil_window_offset_literal(input)
  return self.const:stencil_window_offset_literal(input)
end
function Code.CodeConst:stencil_window_offset_literal(input)
  return Stencil.StencilKernelWindowIndexRejected(
    Stencil.StencilKernelUnsupportedWindowIndex(
      input.window.index, "window offset constant is not a scalar literal"))
end
function Code.CodeConstLiteral:stencil_window_offset_literal(input)
  return self.literal:stencil_window_offset_literal(input)
end
function Core.Literal:stencil_window_offset_literal(input)
  return Stencil.StencilKernelWindowIndexRejected(
    Stencil.StencilKernelUnsupportedWindowIndex(
      input.window.index, "window offset literal is not an integer"))
end
function Core.LitInt:stencil_window_offset_literal(input)
  local raw, first, sign = self.raw, 1, 1
  local head = raw:sub(1, 1)
  if head == "-" then sign, first = -1, 2
  elseif head == "+" then first = 2 end
  if first > #raw then
    return Stencil.StencilKernelWindowIndexRejected(
      Stencil.StencilKernelUnsupportedWindowIndex(
        input.window.index, "window offset integer is malformed"))
  end
  local amount = 0
  for i = first, #raw do
    local digit = raw:byte(i) - 48
    if digit < 0 or digit > 9
        or amount > math.floor((9007199254740991 - digit) / 10) then
      return Stencil.StencilKernelWindowIndexRejected(
        Stencil.StencilKernelUnsupportedWindowIndex(
          input.window.index, "window offset integer is malformed"))
    end
    amount = amount * 10 + digit
  end
  amount = amount * sign
  return Stencil.StencilKernelWindowIndexOffset(
    input.direction:stencil_window_offset_amount(amount))
end
function Stencil.StencilKernelWindowOffsetAdd:stencil_window_offset_amount(amount)
  return Stencil.StencilElementDistance(amount)
end
function Stencil.StencilKernelWindowOffsetSubtract:stencil_window_offset_amount(amount)
  return Stencil.StencilElementDistance(-amount)
end
function Value.ValueExprAdd:stencil_project_window_index(input)
  return self.a:stencil_project_window_index(input):stencil_apply_window_offset(
    Stencil.StencilKernelWindowOffsetApplyInput(
      self.b, Stencil.StencilKernelWindowOffsetAdd, input))
end
function Value.ValueExprSub:stencil_project_window_index(input)
  return self.a:stencil_project_window_index(input):stencil_apply_window_offset(
    Stencil.StencilKernelWindowOffsetApplyInput(
      self.b, Stencil.StencilKernelWindowOffsetSubtract, input))
end
function Stencil.StencilKernelWindowIndexRejected:stencil_window_lane_stream(_input)
  return Stencil.StencilKernelStreamPreparationRejected(self.reject)
end
function Stencil.StencilKernelWindowIndexCenter:stencil_window_lane_stream(input)
  return Stencil.StencilKernelWindowIndexOffset(
    Stencil.StencilElementDistance(0)):stencil_window_lane_stream(input)
end
function Stencil.StencilKernelWindowIndexOffset:stencil_window_lane_stream(input)
  local stream, access = input.stream, input.access
  local window = stream.construction.state.domain.window
  local distance = self.distance.elements
  if distance < -window.extent.before.elements
      or distance > window.extent.after.elements then
    return Stencil.StencilKernelStreamPreparationRejected(
      Stencil.StencilKernelUnsupportedWindowIndex(
        stream.binding.expr.index, "window offset exceeds declared extent"))
  end
  return Stencil.StencilKernelStreamPrepared(
    stream.source, stream.binding, Stencil.StencilStreamDef(
      stream.id, stream.binding.ty, Stencil.StencilStreamWindowAccess(
        Stencil.StencilAccessRef(access.entry.access.name), {
          Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), self.distance),
        })))
end
function Stencil.StencilKernelCountedWindow1D:stencil_lane_stream(input)
  local stream = input.stream
  local projection = stream.binding.expr.index:stencil_project_window_index(
    Stencil.StencilKernelWindowIndexInput(
      stream.construction.state.iteration, self.window, stream.binding.expr.index))
  return projection:stencil_window_lane_stream(input)
end
function Stencil.StencilAccessByKernelLaneFound:stencil_lane_stream(input)
  return input.construction.state.domain:stencil_lane_stream(
    Stencil.StencilKernelLaneStreamInput(input, self))
end
function Stencil.StencilAccessByKernelLaneMissing:stencil_lane_stream(input)
  return Stencil.StencilKernelStreamPreparationRejected(
    Stencil.StencilKernelUnsupportedBinding(input.binding, "lane load has no projected stencil access"))
end
function Kernel.KernelExprLaneLoad:stencil_prepare_stream(input)
  return input.construction.state.access_by_lane:lookup(self.lane):stencil_lane_stream(input)
end
function Stencil.StencilStreamByKernelValueFound:stencil_alias_stream(input)
  return Stencil.StencilKernelStreamPrepared(input.source, input.binding, Stencil.StencilStreamDef(
    input.id, input.binding.ty,
    Stencil.StencilStreamAlias(Stencil.StencilStreamRef(self.entry.definition.id))))
end
function Stencil.StencilStreamByKernelValueMissing:stencil_alias_stream(input)
  return Stencil.StencilKernelStreamPreparationRejected(
    Stencil.StencilKernelUnresolvedValue(self.value))
end
function Kernel.KernelExprKernelValue:stencil_prepare_stream(input)
  return input.construction.state.stream_by_value:lookup(self.value):stencil_alias_stream(input)
end
function Stencil.StencilKernelStreamPrepared:stencil_apply_stream(construction)
  return Stencil.StencilKernelConstructionCollecting(
    construction.state:with_stream(
      Stencil.StencilKernelStateStreamInput(
        self.source, self.binding, self.definition)))
end
function Stencil.StencilKernelStreamPreparationRejected:stencil_apply_stream(construction)
  return construction:stencil_reject(self.reject)
end
function Stencil.StencilStreamByKernelValueFound:stencil_contribute_binding(input)
  return input.construction:stencil_reject(
    Stencil.StencilKernelDuplicateValue(input.contribution.binding.id))
end
function Stencil.StencilStreamByKernelValueMissing:stencil_contribute_binding(input)
  local contribution = input.contribution
  local source = contribution.entry.value
  local binding = contribution.entry.binding
  local id = Stencil.StencilStreamId(
    "kernel-stream:" .. sanitized(binding.id.text) .. ":" ..
      input.construction.state.next_stream_ordinal)
  local expr_input = Stencil.StencilKernelBindingExprInput(
    input.construction, source, binding, id)
  return binding.expr:stencil_prepare_stream(expr_input)
    :stencil_apply_stream(input.construction)
end
function Stencil.StencilKernelConstructionCollecting:stencil_contribute_stream(input)
  local cursor = Stencil.StencilKernelStreamContributionCursor(self, input)
  return self.state.stream_by_value:lookup(input.entry.binding.id)
    :stencil_contribute_binding(cursor)
end
function Stencil.StencilKernelConstructionFinalizable:stencil_contribute_stream(_input)
  return self:stencil_reject(Stencil.StencilKernelConstructionIncomplete(self.state.kernel.id))
end
function Stencil.StencilKernelConstructionRejected:stencil_contribute_stream(_input) return self end

function Stencil.StencilAccessByKernelLaneMissing:stencil_effect_access(effect_input)
  return Stencil.StencilKernelSinkPreparationRejected(
    Stencil.StencilKernelUnsupportedEffect(
      effect_input.effect.effect, "effect lane has no projected access"))
end
function Stencil.StencilStreamByKernelValueMissing:stencil_effect_value(effect_input)
  return Stencil.StencilKernelSinkPreparationRejected(
    Stencil.StencilKernelUnresolvedValue(self.value))
end
function Stencil.StencilStreamByKernelValueFound:stencil_effect_value(effect_input)
  local effect = effect_input.effect.effect
  local dst = effect_input.effect.construction.state.access_by_lane:lookup(effect.dst)
  return dst:stencil_effect_access_with_stream(
    Stencil.StencilKernelEffectStreamInput(effect_input, self.entry.definition))
end
function Stencil.StencilAccessByKernelLaneFound:stencil_effect_access_with_stream(input)
  local store_input = input.effect
  local sink = Stencil.StencilSinkDef(
    Stencil.StencilSinkId("kernel-sink:store:" .. sanitized(self.entry.lane.id.text)),
    Stencil.StencilSinkOpStore(
      Stencil.StencilAccessRef(self.entry.access.name),
      store_input.index,
      Stencil.StencilStreamRef(input.definition.id),
      Stencil.StencilStoreElementwise))
  return Stencil.StencilKernelSinkPrepared({ sink })
end
function Stencil.StencilAccessByKernelLaneMissing:stencil_effect_access_with_stream(input)
  return self:stencil_effect_access(input.effect)
end
function Kernel.KernelExprKernelValue:stencil_store_value(store_input)
  return store_input.effect.construction.state.stream_by_value:lookup(self.value)
    :stencil_effect_value(store_input)
end
function Kernel.KernelExpr:stencil_store_value(store_input)
  return Stencil.StencilKernelSinkPreparationRejected(
    Stencil.StencilKernelUnsupportedEffect(store_input.effect.effect,
      "store value is not a projected kernel binding"))
end
function Kernel.KernelEffectStore:stencil_prepare_sinks(input)
  local selection = self.index:stencil_index_selection(
    Stencil.StencilKernelIndexSelectionInput(
      input.construction.state.iteration, self.index))
  return self.value:stencil_store_value(
    Stencil.StencilKernelStoreEffectInput(input, selection))
end
function Kernel.KernelEffectFold:stencil_prepare_sinks(_input)
  return Stencil.StencilKernelSinkDeferredToResult(self.reduction)
end
function Kernel.KernelEffect:stencil_prepare_sinks(input)
  return Stencil.StencilKernelSinkPreparationRejected(
    Stencil.StencilKernelUnsupportedEffect(self, "kernel effect is outside the initial canonical stencil bridge"))
end
function Stencil.StencilKernelSinkDeferredToResult:stencil_apply_sinks(construction)
  return Stencil.StencilKernelConstructionCollecting(
    construction.state:with_deferred_reduction(self.reduction))
end
function Stencil.StencilKernelSinkPrepared:stencil_apply_sinks(construction)
  return Stencil.StencilKernelConstructionCollecting(
    construction.state:with_sinks(self.sinks))
end
function Stencil.StencilKernelSinkPreparationRejected:stencil_apply_sinks(construction)
  return construction:stencil_reject(self.reject)
end
function Stencil.StencilKernelConstructionCollecting:stencil_contribute_sink(input)
  local effect_input = Stencil.StencilKernelEffectInput(self, input.effect)
  return input.effect:stencil_prepare_sinks(effect_input):stencil_apply_sinks(self)
end
function Stencil.StencilKernelConstructionFinalizable:stencil_contribute_sink(_input)
  return self:stencil_reject(Stencil.StencilKernelConstructionIncomplete(self.state.kernel.id))
end
function Stencil.StencilKernelConstructionRejected:stencil_contribute_sink(_input) return self end

function Kernel.KernelExprValue:stencil_prepare_result_stream(input)
  return input.construction.state.kernel.body.bindings:lookup(self.value)
:stencil_prepare_result_binding(
    Stencil.StencilKernelResultBindingInput(input, self))
end
function Kernel.KernelBindingMissing:stencil_prepare_result_binding(input)
  return Stencil.StencilKernelResultStreamRejected(
    Stencil.StencilKernelUnsupportedResultExpr(
      input.expr, "control result value has no kernel binding"))
end
function Kernel.KernelBindingFound:stencil_prepare_result_binding(input)
  if self.entry.value ~= input.result.source then
    return Stencil.StencilKernelResultStreamRejected(
      Stencil.StencilKernelUnsupportedResultExpr(
        input.expr, "control result source disagrees with its kernel binding"))
  end
  return self.entry.binding.expr:stencil_prepare_bound_result_expr(
    Stencil.StencilKernelResultBoundExprInput(
      input.result, self.entry.binding))
end
function Kernel.KernelExpr:stencil_prepare_bound_result_expr(input)
  return Stencil.StencilKernelResultStreamRejected(
    Stencil.StencilKernelUnsupportedResultExpr(
      self, "control result binding expression is not scalar"))
end
function Kernel.KernelExprValue:stencil_prepare_bound_result_expr(input)
  local definition = Stencil.StencilStreamDef(
    input.result.id, input.binding.ty, Stencil.StencilStreamValueExpr(
      Value.ValueExprValue(self.value), input.binding.ty))
  return Stencil.StencilKernelResultStreamPrepared(
    Stencil.StencilStreamByKernelValueEntry(
      input.result.source, input.binding, definition))
end
function Kernel.KernelExprAlgebra:stencil_prepare_bound_result_expr(input)
  local definition = Stencil.StencilStreamDef(
    input.result.id, input.binding.ty,
    Stencil.StencilStreamValueExpr(self.expr, input.binding.ty))
  return Stencil.StencilKernelResultStreamPrepared(
    Stencil.StencilStreamByKernelValueEntry(
      input.result.source, input.binding, definition))
end
function Kernel.KernelExpr:stencil_prepare_result_stream(_input)
  return Stencil.StencilKernelResultStreamRejected(
    Stencil.StencilKernelUnsupportedResultExpr(
      self, "control result expression is outside direct lane-load projection"))
end
function Stencil.StencilAccessByKernelLaneMissing:stencil_prepare_result_lane(input)
  return Stencil.StencilKernelResultStreamRejected(
    Stencil.StencilKernelUnsupportedResultExpr(
      input.expr, "control result lane has no projected access"))
end
function Stencil.StencilKernelCountedDomain1D:stencil_prepare_result_lane(input)
  local result, access, expr = input.result, input.access, input.expr
  local ty = access.entry.access.ty
  local definition = Stencil.StencilStreamDef(
    result.id, ty, Stencil.StencilStreamAccess(
      Stencil.StencilAccessRef(access.entry.access.name),
      Stencil.StencilIndexExplicit(Stencil.StencilIndexPoint(expr.index))))
  local binding = Kernel.KernelBinding(
    Kernel.KernelValueId("kernel-result:" .. result.id.text), ty, expr)
  return Stencil.StencilKernelResultStreamPrepared(
    Stencil.StencilStreamByKernelValueEntry(
      result.source, binding, definition))
end
function Stencil.StencilKernelWindowIndexRejected:stencil_prepare_window_result_lane(_input)
  return Stencil.StencilKernelResultStreamRejected(self.reject)
end
function Stencil.StencilKernelWindowIndexCenter:stencil_prepare_window_result_lane(input)
  return Stencil.StencilKernelWindowIndexOffset(
    Stencil.StencilElementDistance(0))
:stencil_prepare_window_result_lane(input)
end
function Stencil.StencilKernelWindowIndexOffset:stencil_prepare_window_result_lane(input)
  local result, access, expr = input.result, input.access, input.expr
  local window = result.construction.state.domain.window
  local distance = self.distance.elements
  if distance < -window.extent.before.elements
      or distance > window.extent.after.elements then
    return Stencil.StencilKernelResultStreamRejected(
      Stencil.StencilKernelUnsupportedWindowIndex(
        expr.index, "window result offset exceeds declared extent"))
  end
  local ty = access.entry.access.ty
  local definition = Stencil.StencilStreamDef(
    result.id, ty, Stencil.StencilStreamWindowAccess(
      Stencil.StencilAccessRef(access.entry.access.name), {
        Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), self.distance),
      }))
  local binding = Kernel.KernelBinding(
    Kernel.KernelValueId("kernel-result:" .. result.id.text), ty, expr)
  return Stencil.StencilKernelResultStreamPrepared(
    Stencil.StencilStreamByKernelValueEntry(
      result.source, binding, definition))
end
function Stencil.StencilKernelCountedWindow1D:stencil_prepare_result_lane(input)
  local result, expr = input.result, input.expr
  local projection = expr.index:stencil_project_window_index(
    Stencil.StencilKernelWindowIndexInput(
      result.construction.state.iteration, self.window, expr.index))
  return projection:stencil_prepare_window_result_lane(input)
end
function Stencil.StencilAccessByKernelLaneFound:stencil_prepare_result_lane(input)
  return input.result.construction.state.domain:stencil_prepare_result_lane(
    Stencil.StencilKernelResultLaneStreamInput(input.result, self, input.expr))
end
function Kernel.KernelExprLaneLoad:stencil_prepare_result_stream(input)
  return input.construction.state.access_by_lane:lookup(self.lane)
:stencil_prepare_result_lane(
  Stencil.StencilKernelResultLaneLookupInput(input, self))
end
function Stencil.StencilKernelConstructionCollecting:stencil_add_result_stream(definition)
  return Stencil.StencilKernelConstructionCollecting(
    self.state:with_result_stream(definition))
end
function Stencil.StencilKernelConstructionFinalizable:stencil_add_result_stream(_definition)
  return self:stencil_reject(
    Stencil.StencilKernelConstructionIncomplete(self.state.kernel.id))
end
function Stencil.StencilKernelConstructionRejected:stencil_add_result_stream(_definition)
  return self
end
function Stencil.StencilKernelResultStreamRejected:stencil_apply_control_stream(input)
  return input.construction:stencil_reject(self.reject)
end
function Stencil.StencilKernelResultStreamPrepared:stencil_apply_control_stream(input)
  local construction = input.construction:stencil_add_result_stream(self.entry)
  return input.result:stencil_finish_control_result(
    Stencil.StencilKernelControlFinishInput(
      construction, input.sink, self.entry.definition))
end
function Stencil.StencilKernelConstructionCollecting:stencil_finish_void_result(result)
  if #self.state.deferred_reductions > 0 then
    return self:stencil_reject(
      Stencil.StencilKernelDeferredReductionMismatch(
        self.state.deferred_reductions, result))
  end
  return Stencil.StencilKernelConstructionFinalizable(self.state)
end
function Stencil.StencilKernelConstructionFinalizable:stencil_finish_void_result(_result)
  return self
end
function Stencil.StencilKernelConstructionRejected:stencil_finish_void_result(_result)
  return self
end
function Kernel.KernelResultVoid:stencil_contribute_result(input)
  return input.construction:stencil_finish_void_result(self)
end
function Kernel.KernelResultAll:stencil_contribute_result(input)
  local sink = Stencil.StencilSinkId("kernel-sink:all")
  local stream = Stencil.StencilStreamId("kernel-stream:all")
  return self.src:stencil_prepare_result_stream(
    Stencil.StencilKernelResultStreamInput(
      input.construction, stream, self.src_value))
:stencil_apply_control_stream(
  Stencil.StencilKernelControlStreamUse(input.construction, self, sink))
end
function Kernel.KernelResultAll:stencil_finish_control_result(input)
  local sink = Stencil.StencilSinkDef(input.sink,
    Stencil.StencilSinkOpAll(Stencil.StencilStreamRef(input.stream.id), self.pred))
  return Stencil.StencilKernelConstructionFinalizable(
    input.construction.state:with_sinks({ sink }))
end
function Kernel.KernelResultAny:stencil_contribute_result(input)
  local sink = Stencil.StencilSinkId("kernel-sink:any")
  local stream = Stencil.StencilStreamId("kernel-stream:any")
  return self.src:stencil_prepare_result_stream(
    Stencil.StencilKernelResultStreamInput(
      input.construction, stream, self.src_value))
:stencil_apply_control_stream(
  Stencil.StencilKernelControlStreamUse(input.construction, self, sink))
end
function Kernel.KernelResultAny:stencil_finish_control_result(input)
  local sink = Stencil.StencilSinkDef(input.sink,
    Stencil.StencilSinkOpAny(Stencil.StencilStreamRef(input.stream.id), self.pred))
  return Stencil.StencilKernelConstructionFinalizable(
    input.construction.state:with_sinks({ sink }))
end
function Kernel.KernelResultFind:stencil_contribute_result(input)
  local counter = input.construction.state.iteration.counter
  if self.found_value ~= counter then
    return input.construction:stencil_reject(
      Stencil.StencilKernelFindValueMismatch(
        counter, self.found_value))
  end
  local sink = Stencil.StencilSinkId("kernel-sink:find")
  local stream = Stencil.StencilStreamId("kernel-stream:find")
  return self.src:stencil_prepare_result_stream(
    Stencil.StencilKernelResultStreamInput(
      input.construction, stream, self.src_value))
:stencil_apply_control_stream(
  Stencil.StencilKernelControlStreamUse(input.construction, self, sink))
end
function Kernel.KernelResultFind:stencil_finish_control_result(input)
  local sink = Stencil.StencilSinkDef(input.sink, Stencil.StencilSinkOpFind(
    Stencil.StencilStreamRef(input.stream.id), self.pred, self.not_found_value))
  return Stencil.StencilKernelConstructionFinalizable(
    input.construction.state:with_sinks({ sink }))
end
function Stencil.StencilKernelResultStreamRejected:stencil_prepare_all_compare_right(input)
  return input.construction:stencil_reject(self.reject)
end
function Stencil.StencilKernelResultStreamPrepared:stencil_prepare_all_compare_right(input)
  local construction = input.construction:stencil_add_result_stream(self.entry)
  return input.result.right:stencil_prepare_result_stream(
    Stencil.StencilKernelResultStreamInput(
      construction, input.right_id, input.result.right_value))
:stencil_finish_all_compare(
  Stencil.StencilKernelAllCompareRightInput(
    construction, input.result, input.sink, self.entry.definition, input.right_id))
end
function Stencil.StencilKernelResultStreamRejected:stencil_finish_all_compare(input)
  return input.construction:stencil_reject(self.reject)
end
function Stencil.StencilKernelResultStreamPrepared:stencil_finish_all_compare(input)
  local construction = input.construction:stencil_add_result_stream(self.entry)
  local sink = Stencil.StencilSinkDef(input.sink, Stencil.StencilSinkOpAllCompare(
    Stencil.StencilStreamRef(input.left.id),
    Stencil.StencilStreamRef(self.entry.definition.id), input.result.cmp))
  return Stencil.StencilKernelConstructionFinalizable(
    construction.state:with_sinks({ sink }))
end
function Kernel.KernelResultAllCompare:stencil_contribute_result(input)
  local sink = Stencil.StencilSinkId("kernel-sink:all-compare")
  local left = Stencil.StencilStreamId("kernel-stream:all-compare:left")
  local right = Stencil.StencilStreamId("kernel-stream:all-compare:right")
  return self.left:stencil_prepare_result_stream(
    Stencil.StencilKernelResultStreamInput(
      input.construction, left, self.left_value))
:stencil_prepare_all_compare_right(
  Stencil.StencilKernelAllCompareLeftInput(
    input.construction, self, sink, right))
end
function Value.ReductionFact:stencil_reduction_arithmetic()
  if self.int_semantics ~= nil and self.float_mode ~= nil then
    return Stencil.StencilKernelReductionArithmeticRejected(
      Stencil.StencilKernelAmbiguousReductionArithmetic(self))
  end
  if self.int_semantics ~= nil then
    return Stencil.StencilKernelReductionArithmeticResolved(
      Stencil.StencilArithmeticInteger(self.int_semantics))
  end
  if self.float_mode ~= nil then
    return Stencil.StencilKernelReductionArithmeticResolved(
      Stencil.StencilArithmeticFloat(self.float_mode))
  end
  return self.op:stencil_inferred_reduction_arithmetic(self)
end
function Value.ReductionOp:stencil_inferred_reduction_arithmetic(reduction)
  return Stencil.StencilKernelReductionArithmeticRejected(
    Stencil.StencilKernelMissingReductionArithmetic(reduction))
end
function Value.ReductionMin:stencil_inferred_reduction_arithmetic(_reduction)
  return Stencil.StencilKernelReductionArithmeticResolved(
    Stencil.StencilArithmeticInferred)
end
function Value.ReductionMax:stencil_inferred_reduction_arithmetic(_reduction)
  return Stencil.StencilKernelReductionArithmeticResolved(
    Stencil.StencilArithmeticInferred)
end
function Stencil.StencilKernelReductionArithmeticRejected:stencil_finish_reduction(input)
  return Stencil.StencilKernelConstructionCollecting(input.state)
:stencil_reject(self.reject)
end
function Stencil.StencilKernelReductionArithmeticResolved:stencil_finish_reduction(input)
  local reducer = Stencil.StencilReducer(
    input.reduction.op, input.reduction.ty, input.reduction.init, self.arithmetic)
  local sink = Stencil.StencilSinkDef(
    Stencil.StencilSinkId(
      "kernel-sink:reduction:" .. sanitized(input.reduction.id.text)),
    Stencil.StencilSinkOpFold(
      Stencil.StencilStreamRef(input.stream), reducer, input.reduction.ty,
      Stencil.StencilReduceInitIdentity, Stencil.StencilFoldReturnsValue))
  return Stencil.StencilKernelConstructionFinalizable(
    input.state:with_sinks({ sink }))
end
function Kernel.KernelResultReduction:stencil_contribute_result(input)
  local state = input.construction.state
  if #state.deferred_reductions > 1
      or (#state.deferred_reductions == 1
        and state.deferred_reductions[1] ~= self.reduction) then
    return input.construction:stencil_reject(
      Stencil.StencilKernelDeferredReductionMismatch(
        state.deferred_reductions, self))
  end
  local binding = Kernel.KernelBinding(
    Kernel.KernelValueId("kernel-reduction:" .. sanitized(self.reduction.id.text)),
    self.reduction.ty, Kernel.KernelExprAlgebra(self.reduction.contribution))
  local stream_id = Stencil.StencilStreamId(
    "kernel-stream:reduction:" .. sanitized(self.reduction.id.text))
  local definition = Stencil.StencilStreamDef(stream_id, self.reduction.ty,
    Stencil.StencilStreamValueExpr(self.reduction.contribution, self.reduction.ty))
  state = state:with_stream(
    Stencil.StencilKernelStateStreamInput(
      self.reduction.accumulator, binding, definition))
  return self.reduction:stencil_reduction_arithmetic():stencil_finish_reduction(
    Stencil.StencilKernelReductionFinishInput(state, self.reduction, stream_id))
end
function Kernel.KernelResultVoid:stencil_result_provenance(_state)
  return Stencil.StencilKernelResultVoid
end
function Kernel.KernelResultReduction:stencil_result_provenance(_state)
  local suffix = sanitized(self.reduction.id.text)
  return Stencil.StencilKernelResultReduction(
    Stencil.StencilSinkId("kernel-sink:reduction:" .. suffix),
    self.reduction.op, self.reduction.accumulator,
    Stencil.StencilStreamRef(Stencil.StencilStreamId(
      "kernel-stream:reduction:" .. suffix)))
end
function Kernel.KernelResultAll:stencil_result_provenance(_state)
  return Stencil.StencilKernelResultAll(
    Stencil.StencilSinkId("kernel-sink:all"),
    Stencil.StencilStreamRef(Stencil.StencilStreamId("kernel-stream:all")),
    self.src_value, self.pred,
    self.success, self.failure)
end
function Kernel.KernelResultAny:stencil_result_provenance(_state)
  return Stencil.StencilKernelResultAny(
    Stencil.StencilSinkId("kernel-sink:any"),
    Stencil.StencilStreamRef(Stencil.StencilStreamId("kernel-stream:any")),
    self.src_value, self.pred,
    self.success, self.failure)
end
function Kernel.KernelResultAllCompare:stencil_result_provenance(_state)
  return Stencil.StencilKernelResultAllCompare(
    Stencil.StencilSinkId("kernel-sink:all-compare"),
    Stencil.StencilStreamRef(Stencil.StencilStreamId(
      "kernel-stream:all-compare:left")), self.left_value,
    Stencil.StencilStreamRef(Stencil.StencilStreamId(
      "kernel-stream:all-compare:right")), self.right_value,
    self.cmp, self.success, self.failure)
end
function Kernel.KernelResultFind:stencil_result_provenance(_state)
  return Stencil.StencilKernelResultFind(
    Stencil.StencilSinkId("kernel-sink:find"),
    Stencil.StencilStreamRef(Stencil.StencilStreamId("kernel-stream:find")),
    self.src_value, self.pred,
    self.found_value, self.found, self.not_found, self.not_found_value)
end
function Kernel.KernelResult:stencil_contribute_result(input)
  return input.construction:stencil_reject(
    Stencil.StencilKernelUnsupportedResult(self,
      "kernel result is outside the initial canonical stencil bridge"))
end
function Stencil.StencilKernelConstructionRejected:stencil_contribute_result(_input) return self end

function Schedule.ScheduleScalarIndex:stencil_convert_schedule(input)
  return Stencil.StencilKernelScheduleConverted(input.schedule,
    Stencil.StencilScheduleScalar(input.compiler))
end
function Schedule.ScheduleScalarPointer:stencil_convert_schedule(input)
  return Stencil.StencilKernelScheduleConverted(input.schedule,
    Stencil.StencilScheduleScalar(input.compiler))
end
function Schedule.ScheduleVector:stencil_convert_schedule(_input)
  return Stencil.StencilKernelScheduleRejected(
    Stencil.StencilKernelUnsupportedScheduleForm(self,
      "canonical vector schedule lacks a selected stencil vector policy"))
end
function Schedule.ScheduleClosedForm:stencil_convert_schedule(_input)
  return Stencil.StencilKernelScheduleRejected(
    Stencil.StencilKernelUnsupportedScheduleForm(self,
      "closed-form kernels bypass stencil materialization"))
end
function Schedule.ScheduleNoPlan:stencil_convert_kernel_schedule(_input)
  return Stencil.StencilKernelScheduleRejected(
    Stencil.StencilKernelScheduleNotPlanned(self, "kernel has no selected schedule"))
end
function Schedule.ScheduleKernelRejected:stencil_convert_kernel_schedule(_input)
  return Stencil.StencilKernelScheduleRejected(
    Stencil.StencilKernelScheduleNotPlanned(self, "kernel was rejected before schedule selection"))
end
function Schedule.SchedulePlanned:stencil_convert_kernel_schedule(input)
  if self.kernel ~= input.kernel.id then
    return Stencil.StencilKernelScheduleRejected(
      Stencil.StencilKernelScheduleMismatch(input.kernel.id, self.kernel))
  end
  return self.form:stencil_convert_schedule(input)
end

function Mem.MemDependenceFact:stencil_noalias_contribution(_input)
  return Stencil.StencilAccessAliasPairNotMatched
end
function Mem.MemNoDependence:stencil_noalias_contribution(input)
  if (self.before == input.left and self.after == input.right)
      or (self.before == input.right and self.after == input.left) then
    return self.proof:stencil_noalias_proof_contribution()
  end
  return Stencil.StencilAccessAliasPairNotMatched
end
function Mem.MemNoLoopCarriedDependence:stencil_noalias_contribution(input)
  if (self.before == input.left and self.after == input.right)
      or (self.before == input.right and self.after == input.left) then
    return self.proof:stencil_noalias_proof_contribution()
  end
  return Stencil.StencilAccessAliasPairNotMatched
end
function Mem.MemProof:stencil_noalias_proof_contribution()
  return Stencil.StencilAccessAliasPairNotMatched
end
function Mem.MemProofContract:stencil_noalias_proof_contribution()
  return self.guarantee:stencil_noalias_guarantee_contribution()
end
function Mem.MemContractGuarantee:stencil_noalias_guarantee_contribution()
  return Stencil.StencilAccessAliasPairNotMatched
end
function Mem.MemContractNoAlias:stencil_noalias_guarantee_contribution()
  return Stencil.StencilAccessAliasPairMatched(Stencil.StencilAliasNoAlias)
end
function Stencil.StencilAccessAliasPairNotMatched:stencil_append_alias_legality(input)
  return input.legality
end
function Stencil.StencilAccessAliasPairMatched:stencil_append_alias_legality(input)
  local facts = append_one(input.legality.facts,
    Stencil.StencilFusionAccessAliasRelation(input.left, input.right, self.relation))
  return Stencil.StencilFusionLegality(
    facts, input.legality.proof_obligations, input.legality.rejects)
end
function Stencil.StencilKernelConstructionState:stencil_with_alias_legality(input)
  local legality = self.legality
  local entries = self.access_by_lane.entries
  for i = 1, #entries do
    for j = i + 1, #entries do
      local left, right = entries[i], entries[j]
      local pair = Stencil.StencilKernelMemAccessPairInput(
        left.lane.accesses[1], right.lane.accesses[1])
      local alias_input = Stencil.StencilKernelAliasLegalityInput(
        legality, Stencil.StencilAccessRef(left.access.name),
        Stencil.StencilAccessRef(right.access.name))
      for k = 1, #input.mem.dependences do
        legality = input.mem.dependences[k]:stencil_noalias_contribution(pair)
:stencil_append_alias_legality(alias_input)
        alias_input = Stencil.StencilKernelAliasLegalityInput(
          legality, alias_input.left, alias_input.right)
      end
    end
  end
  return self:with_legality(legality)
end

function Stencil.StencilKernelConstructionCollecting:stencil_finish_projection(_input)
  return Stencil.StencilKernelProjectionRejected(self.state.kernel, {
    Stencil.StencilKernelConstructionIncomplete(self.state.kernel.id),
  })
end
function Stencil.StencilKernelConstructionRejected:stencil_finish_projection(_input)
  return Stencil.StencilKernelProjectionRejected(self.state.kernel, self.rejects)
end
function Stencil.StencilKernelConstructionFinalizable:stencil_finish_projection(input)
  local schedule_input = Stencil.StencilKernelScheduleConversionInput(
    input.kernel, input.schedule, input.compiler, input.target,
    self.state.access_by_lane, input.kernel.body.result)
  local converted = input.schedule:stencil_convert_kernel_schedule(schedule_input)
  local construction = Stencil.StencilKernelConstructionFinalizable(
    self.state:stencil_with_alias_legality(
      Stencil.StencilKernelAliasProjectionInput(input.mem)))
  return construction:stencil_finalize(
    Stencil.StencilKernelFinalizationInput(converted))
end

function Stencil.StencilKernelScheduleRejected:stencil_finalize(construction)
  return Stencil.StencilKernelProjectionRejected(
    construction.state.kernel, { self.reject })
end
function Stencil.StencilKernelScheduleConverted:stencil_finalize(construction)
  local state = construction.state
  local accesses, streams, stream_entries = {}, {}, {}
  for _, entry in ipairs(state.access_by_lane.entries) do accesses[#accesses + 1] = entry.access end
  for _, entry in ipairs(state.stream_by_value.entries) do
    streams[#streams + 1] = entry.definition
    stream_entries[#stream_entries + 1] = entry
  end
  for _, entry in ipairs(state.result_streams) do
    streams[#streams + 1] = entry.definition
    stream_entries[#stream_entries + 1] = entry
  end
  local computation = Stencil.StencilComputation(
    Stencil.StencilComputationId("kernel-computation:" .. sanitized(state.kernel.id.text)),
    state.producer, accesses, streams, state.sinks, state.legality, self.schedule, state.proofs)
  return Stencil.StencilKernelProjected(
    Stencil.StencilKernelComputationProjection(
      self.source,
      Stencil.StencilKernelProvenanceFacet(
        state.kernel, state.iteration, state.domain, state.access_by_lane,
        Stencil.StencilStreamByKernelValueProjection(stream_entries),
        state.kernel.body.result:stencil_result_provenance(state)),
      computation))
end
function Stencil.StencilKernelConstructionCollecting:stencil_finalize(_input)
  return Stencil.StencilKernelProjectionRejected(self.state.kernel, {
    Stencil.StencilKernelConstructionIncomplete(self.state.kernel.id),
  })
end
function Stencil.StencilKernelConstructionRejected:stencil_finalize(_input)
  return Stencil.StencilKernelProjectionRejected(self.state.kernel, self.rejects)
end
function Stencil.StencilKernelConstructionFinalizable:stencil_finalize(input)
  return input.schedule:stencil_finalize(self)
end

function Stencil.StencilKernelIterationRejected:stencil_continue_projection(input)
  return Stencil.StencilKernelProjectionRejected(input.kernel, { self.reject })
end
function Stencil.StencilKernelDomainRejected:stencil_continue_domain(input)
  return Stencil.StencilKernelProjectionRejected(
    input.projection.kernel, { self.reject })
end
function Stencil.StencilKernelDomainResolved:stencil_continue_domain(input)
  local projection, iteration = input.projection, input.iteration
  local construction = projection.kernel.body.equivalence:stencil_initialize_construction(
    Stencil.StencilKernelConstructionInitInput(
      projection.kernel, iteration, self.domain, self.producer))
  local live_bindings = projection.kernel.body:stencil_live_bindings()
  for _, entry in ipairs(projection.kernel.body.lanes.entries) do
    construction = construction:stencil_contribute_access(
      Stencil.StencilKernelAccessContributionInput(entry.lane, projection.mem))
  end
  for _, entry in ipairs(projection.kernel.body.bindings.entries) do
    construction = live_bindings:stencil_contribute_stream(
      Stencil.StencilKernelLiveStreamInput(construction, entry))
  end
  for _, entry in ipairs(projection.kernel.body.effects.entries) do
    construction = construction:stencil_contribute_sink(
      Stencil.StencilKernelSinkContributionInput(entry.effect))
  end
  construction = projection.kernel.body.result:stencil_contribute_result(
    Stencil.StencilKernelResultContributionInput(construction))
  return construction:stencil_finish_projection(projection)
end
function Stencil.StencilKernelIterationProjected:stencil_continue_projection(input)
  local domain = Flow.FlowDomainLoop(self.iteration.loop)
  return input.flow:stencil_domain_shape_lookup(domain)
:stencil_resolve_kernel_domain(self.iteration)
:stencil_continue_domain(
  Stencil.StencilKernelDomainContinuationInput(input, self.iteration))
end
function Stencil.StencilKernelProjectionInput:project_kernel_stencil()
  local expected = self.module.id
  if self.graph.module ~= expected then
    return Stencil.StencilKernelProjectionRejected(self.kernel, {
      Stencil.StencilKernelModuleMismatch(expected, self.graph.module),
    })
  end
  if self.mem.module ~= expected then
    return Stencil.StencilKernelProjectionRejected(self.kernel, {
      Stencil.StencilKernelModuleMismatch(expected, self.mem.module),
    })
  end
  if self.effects.module ~= expected then
    return Stencil.StencilKernelProjectionRejected(self.kernel, {
      Stencil.StencilKernelModuleMismatch(expected, self.effects.module),
    })
  end
  return Stencil.StencilKernelIterationInput(
    self.module, self.graph, self.kernel, self.flow, self.semantics)
:project_iteration():stencil_continue_projection(self)
end

function Schedule.SchedulePlanned:stencil_kernel_schedule_match(kernel)
  if self.kernel == kernel then
    return Stencil.StencilKernelScheduleMatched(self)
  end
  return Stencil.StencilKernelScheduleIgnored
end
function Schedule.ScheduleNoPlan:stencil_kernel_schedule_match(kernel)
  if self.kernel == kernel then
    return Stencil.StencilKernelScheduleMatched(self)
  end
  return Stencil.StencilKernelScheduleIgnored
end
function Schedule.ScheduleKernelRejected:stencil_kernel_schedule_match(_kernel)
  return Stencil.StencilKernelScheduleIgnored
end
function Stencil.StencilKernelScheduleIgnored:stencil_append_schedule(found) return found end
function Stencil.StencilKernelScheduleMatched:stencil_append_schedule(found)
  return append_one(found, self.schedule)
end
function Schedule.ScheduleModulePlan:stencil_kernel_schedule_lookup(kernel)
  local found = {}
  for _, schedule in ipairs(self.schedules) do
    found = schedule:stencil_kernel_schedule_match(kernel):stencil_append_schedule(found)
  end
  if #found == 0 then
    return Stencil.StencilKernelScheduleLookupMissing(
      Stencil.StencilKernelScheduleMissing(kernel))
  end
  if #found > 1 then
    return Stencil.StencilKernelScheduleLookupAmbiguous(
      Stencil.StencilKernelScheduleAmbiguous(kernel, #found))
  end
  return Stencil.StencilKernelScheduleFound(found[1])
end

function Stencil.StencilKernelScheduleFound:stencil_project_module_entry(input)
  local projection = input.projection
  local result = Stencil.StencilKernelProjectionInput(
    projection.module, projection.graph, projection.flow, projection.semantics,
    input.kernel, self.schedule, projection.compiler, projection.schedules.target.target,
    projection.kernels.mem, projection.kernels.effect):project_kernel_stencil()
  return Stencil.StencilKernelModuleProjectedEntry(input.kernel.id, result)
end
function Stencil.StencilKernelScheduleLookupMissing:stencil_project_module_entry(input)
  return Stencil.StencilKernelModuleProjectedEntry(input.kernel.id,
    Stencil.StencilKernelProjectionRejected(input.kernel, { self.reject }))
end
function Stencil.StencilKernelScheduleLookupAmbiguous:stencil_project_module_entry(input)
  return Stencil.StencilKernelModuleProjectedEntry(input.kernel.id,
    Stencil.StencilKernelProjectionRejected(input.kernel, { self.reject }))
end
function Kernel.KernelPlanned:stencil_project_module_entry(input)
  return input.schedules:stencil_kernel_schedule_lookup(self.id)
    :stencil_project_module_entry(Stencil.StencilKernelModuleEntryInput(input, self))
end
function Kernel.KernelNoPlan:stencil_project_module_entry(_input)
  return Stencil.StencilKernelModuleRejectedEntry(self)
end
function Stencil.StencilKernelModuleProjectionInput:project_kernel_module()
  local expected = self.module.id
  if self.graph.module ~= expected then
    return Stencil.StencilKernelModuleProjectionRejected(expected, self.graph.module)
  end
  if self.flow.module ~= expected then
    return Stencil.StencilKernelModuleProjectionRejected(expected, self.flow.module)
  end
  if self.semantics.module ~= expected then
    return Stencil.StencilKernelModuleProjectionRejected(expected, self.semantics.module)
  end
  if self.kernels.module ~= expected then
    return Stencil.StencilKernelModuleProjectionRejected(expected, self.kernels.module)
  end
  if self.schedules.module ~= expected then
    return Stencil.StencilKernelModuleProjectionRejected(expected, self.schedules.module)
  end
  if self.flow ~= self.kernels.flow then
    return Stencil.StencilKernelModuleFacetMismatch(
      "kernel plan was produced from a different flow fact projection")
  end
  local entries = {}
  for _, kernel in ipairs(self.kernels.plans) do
    entries[#entries + 1] = kernel:stencil_project_module_entry(self)
  end
  return Stencil.StencilKernelModuleProjected(
    Stencil.StencilKernelModuleProjection(expected, entries))
end

return Stencil
