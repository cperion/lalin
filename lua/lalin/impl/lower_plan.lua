-- impl/lower_plan.lua — plan_lowering methods on LalinCode, LalinGraph,
-- LalinKernel, LalinSchedule, LalinLower, LalinFlow types.
-- Produces LalinLower.LowerModule.
-- Entry: Code.CodeModule:plan_lowering(graph, kernels, schedules, target)

require("lalin.schema_v2")
local Code     = require("lalin.schema_v2.code")
local Graph    = require("lalin.schema_v2.graph")
local Flow     = require("lalin.schema_v2.flow")
local Kernel   = require("lalin.schema_v2.kernel")
local Schedule = require("lalin.schema_v2.schedule")
local Lower    = require("lalin.schema_v2.lower")
local C        = require("lalin.schema_v2.c")

local function sanitize(s)
  s = tostring(s or "x"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "x" end
  return s
end
local function append_all(left, right)
  local out = {}
  for i = 1, #left do out[#out + 1] = left[i] end
  for i = 1, #right do out[#out + 1] = right[i] end
  return out
end

local function short_hash(text)
  text = tostring(text or "")
  local h = 2166136261
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i))
    h = (h * 16777619) % 4294967296
  end
  return string.format("%08x", h)
end

----------------------------------------------------------------------
-- Typed kernel/schedule relations and lower-fragment selection
----------------------------------------------------------------------

function Schedule.SchedulePlanned:lower_schedule_relation() return Lower.LowerScheduleRelationEntry(Lower.LowerScheduleByKernelEntry(self.kernel, self)) end
function Schedule.ScheduleNoPlan:lower_schedule_relation() return Lower.LowerScheduleRelationEntry(Lower.LowerScheduleByKernelEntry(self.kernel, self)) end
function Schedule.ScheduleKernelRejected:lower_schedule_relation() return Lower.LowerScheduleRelationOutsideKernel end
function Lower.LowerScheduleRelationEntry:lower_schedule_entries() return { self.entry } end
function Lower.LowerScheduleRelationOutsideKernel:lower_schedule_entries() return {} end
function Schedule.ScheduleModulePlan:lower_schedule_projection()
  local entries = {}
  for _, schedule in ipairs(self.schedules) do entries = append_all(entries, schedule:lower_schedule_relation():lower_schedule_entries()) end
  return Lower.LowerScheduleByKernelProjection(entries)
end
function Lower.LowerScheduleByKernelProjection:lookup(kernel)
  for _, entry in ipairs(self.entries) do if entry.kernel == kernel then return Lower.LowerScheduleByKernelFound(entry) end end
  return Lower.LowerScheduleByKernelMissing(kernel)
end
function Graph.CodeGraph:lower_loop_projection()
  local entries = {}
  for _, func in ipairs(self.funcs) do for _, loop in ipairs(func.loops) do entries[#entries + 1] = Lower.LowerLoopByIdEntry(loop.id, loop) end end
  return Lower.LowerLoopByIdProjection(entries)
end
function Lower.LowerLoopByIdProjection:lookup(id)
  for _, entry in ipairs(self.entries) do if entry.id == id then return Lower.LowerLoopByIdFound(entry) end end
  return Lower.LowerLoopByIdMissing(id)
end
function Kernel.KernelSubjectLoop:lower_kernel_relation(plan) return Lower.LowerKernelRelationEntry(Lower.LowerKernelByLoopEntry(self.loop, plan)) end
function Kernel.KernelSubjectFunction:lower_kernel_relation(plan) return Lower.LowerKernelRelationOutsideLoop end
function Kernel.KernelSubjectDomain:lower_kernel_relation(plan) return Lower.LowerKernelRelationOutsideLoop end
function Kernel.KernelSubjectFragment:lower_kernel_relation(plan) return Lower.LowerKernelRelationOutsideLoop end
function Lower.LowerKernelRelationEntry:lower_kernel_entries() return { self.entry } end
function Lower.LowerKernelRelationOutsideLoop:lower_kernel_entries() return {} end
function Kernel.KernelModulePlan:lower_kernel_projection()
  local entries = {}
  for _, plan in ipairs(self.plans) do entries = append_all(entries, plan.subject:lower_kernel_relation(plan):lower_kernel_entries()) end
  return Lower.LowerKernelByLoopProjection(entries)
end
function Lower.LowerKernelByLoopProjection:lookup(loop)
  for _, entry in ipairs(self.entries) do if entry.loop == loop then return Lower.LowerKernelByLoopFound(entry) end end
  return Lower.LowerKernelByLoopMissing(loop)
end

function Kernel.KernelResultClosedForm:lower_closed_form_lookup() return Lower.LowerClosedFormFound(self.closed_form) end
function Kernel.KernelResultVoid:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result is void") end
function Kernel.KernelResultValue:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result is a value") end
function Kernel.KernelResultFind:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result is find") end
function Kernel.KernelResultAll:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result is all") end
function Kernel.KernelResultAllCompare:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result is all-compare") end
function Kernel.KernelResultAny:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result is any") end
function Kernel.KernelResultReduction:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result is reduction") end
function Kernel.KernelResultOriginalControl:lower_closed_form_lookup() return Lower.LowerClosedFormMissing("kernel result preserves original control") end

function Lower.LowerKernelByLoopMissing:lower_fragment_candidate(schedules) return Lower.LowerFragmentNoCandidate(self.loop) end
function Lower.LowerKernelByLoopFound:lower_fragment_candidate(schedules) return self.entry.plan:lower_fragment_candidate(schedules) end
function Kernel.KernelNoPlan:lower_fragment_candidate(schedules) return Lower.LowerFragmentKernelRejected(self.rejects) end
function Kernel.KernelPlanned:lower_fragment_candidate(schedules) return schedules:lookup(self.id):lower_fragment_candidate(self) end
function Lower.LowerScheduleByKernelMissing:lower_fragment_candidate(plan) return Lower.LowerFragmentMissingSchedule(plan.id) end
function Lower.LowerScheduleByKernelFound:lower_fragment_candidate(plan) return self.entry.schedule:lower_fragment_candidate(plan) end
function Schedule.ScheduleNoPlan:lower_fragment_candidate(plan) return Lower.LowerFragmentNoSchedule(self.rejects) end
function Schedule.SchedulePlanned:lower_fragment_candidate(plan) return self.form:lower_fragment_candidate(plan, self) end
function Schedule.ScheduleScalarIndex:lower_fragment_candidate(plan, schedule) return Lower.LowerFragmentKernelCandidate(plan, schedule) end
function Schedule.ScheduleScalarPointer:lower_fragment_candidate(plan, schedule) return Lower.LowerFragmentKernelCandidate(plan, schedule) end
function Schedule.ScheduleVector:lower_fragment_candidate(plan, schedule) return Lower.LowerFragmentKernelCandidate(plan, schedule) end
function Schedule.ScheduleClosedForm:lower_fragment_candidate(plan, schedule) return plan.body.result:lower_closed_form_lookup():lower_fragment_candidate(plan, schedule) end
function Lower.LowerClosedFormFound:lower_fragment_candidate(plan, schedule) return Lower.LowerFragmentClosedFormCandidate(self.fact, plan, schedule) end
function Lower.LowerClosedFormMissing:lower_fragment_candidate(plan, schedule) return Lower.LowerFragmentClosedFormMissing(self.reason) end

function Lower.LowerFragmentClosedFormCandidate:select_lower_fragment()
  return Lower.LowerSelectClosedForm(self.closed_form, self.kernel.id, self.schedule.id)
end
function Lower.LowerFragmentKernelCandidate:select_lower_fragment() return Lower.LowerSelectKernel(self.kernel.id, self.schedule.id) end
function Lower.LowerFragmentClosedFormMissing:select_lower_fragment() return Lower.LowerSelectFallback(self.reason) end
function Lower.LowerFragmentNoSchedule:select_lower_fragment() return Lower.LowerSelectScheduleRejected(self.rejects) end
function Lower.LowerFragmentMissingSchedule:select_lower_fragment() return Lower.LowerSelectFallback("missing schedule for kernel " .. self.kernel.text) end
function Lower.LowerFragmentKernelRejected:select_lower_fragment() return Lower.LowerSelectKernelRejected(self.rejects) end
function Lower.LowerFragmentNoCandidate:select_lower_fragment() return Lower.LowerSelectNone("no kernel candidate for loop " .. self.loop.text) end

local function loop_blocks(loop)
  local out = {}
  for _, block in ipairs(loop.body) do out[#out + 1] = block.block end
  return out
end
local function fragment_id(input, suffix) return Lower.LowerFragmentId("frag:" .. sanitize(input.func.text) .. ":" .. suffix .. ":" .. sanitize(input.loop.id.text)) end
function Lower.LowerSelectClosedForm:lower_loop_fragment(input)
  local fragment = Lower.LowerFragment(fragment_id(input, "closed"), input.cover, Lower.LowerStrategyClosedForm(self.kernel, self.closed_form), { Lower.LowerProofKernel(self.kernel, "typed kernel relation"), Lower.LowerProofSchedule(self.schedule, "typed closed-form schedule relation") }, {})
  return Lower.LowerLoopFragmentResult(fragment, loop_blocks(input.loop), {})
end
function Lower.LowerSelectKernel:lower_loop_fragment(input)
  local fragment = Lower.LowerFragment(fragment_id(input, "kernel"), input.cover, Lower.LowerStrategyKernel(self.kernel, self.schedule), { Lower.LowerProofKernel(self.kernel, "typed kernel relation"), Lower.LowerProofSchedule(self.schedule, "typed schedule relation") }, {})
  return Lower.LowerLoopFragmentResult(fragment, loop_blocks(input.loop), {})
end
function Lower.LowerSelectFallback:lower_loop_fragment(input)
  local issue = Lower.LowerIssueFallback(input.cover, Lower.LowerFallbackNoKernel(self.reason))
  local fragment = Lower.LowerFragment(fragment_id(input, "fallback"), input.cover, Lower.LowerStrategyCode(self.reason), { Lower.LowerProofFallback(self.reason) }, { issue })
  return Lower.LowerLoopFragmentResult(fragment, loop_blocks(input.loop), { issue })
end
function Lower.LowerSelectKernelRejected:lower_loop_fragment(input)
  local reason = "kernel rejected: " .. tostring(self.rejects[1])
  local issue = Lower.LowerIssueKernelRejected(input.cover, self.rejects)
  local fragment = Lower.LowerFragment(fragment_id(input, "kernel_rejected"), input.cover, Lower.LowerStrategyCode(reason), { Lower.LowerProofFallback(reason) }, { issue })
  return Lower.LowerLoopFragmentResult(fragment, loop_blocks(input.loop), { issue })
end
function Lower.LowerSelectScheduleRejected:lower_loop_fragment(input)
  local reason = "kernel schedule rejected: " .. tostring(self.rejects[1])
  local issue = Lower.LowerIssueScheduleRejected(input.cover, self.rejects)
  local fragment = Lower.LowerFragment(fragment_id(input, "schedule_rejected"), input.cover, Lower.LowerStrategyCode(reason), { Lower.LowerProofFallback(reason) }, { issue })
  return Lower.LowerLoopFragmentResult(fragment, loop_blocks(input.loop), { issue })
end
function Lower.LowerSelectNone:lower_loop_fragment(input)
  local issue = Lower.LowerIssueFallback(input.cover, Lower.LowerFallbackNoKernel(self.reason))
  local fragment = Lower.LowerFragment(fragment_id(input, "none"), input.cover, Lower.LowerStrategyCode(self.reason), { Lower.LowerProofFallback(self.reason) }, { issue })
  return Lower.LowerLoopFragmentResult(fragment, loop_blocks(input.loop), { issue })
end

----------------------------------------------------------------------
-- Flow carrier/address plan helpers
----------------------------------------------------------------------

function Flow.FlowCarrierTransfer:lower_plan_matches_edge(edge)
  return self.edge == edge
end

function Flow.FlowCarrierThread:lower_plan_transfer_for_edge(edge)
  for _, transfer in ipairs(self.transfers or {}) do if transfer:lower_plan_matches_edge(edge) then return transfer end end
  return nil
end

function Flow.FlowCarrierStep:lower_plan_edge_source(carrier, edge, flow) return carrier:lower_plan_recompute_edge_source(edge, flow) end
function Flow.FlowCarrierStepSame:lower_plan_edge_source() return Lower.LowerCarrierEdgeCarrySame end
function Flow.FlowCarrierStepConst:lower_plan_edge_source() return Lower.LowerCarrierEdgeCarryConst(self.amount) end
function Flow.FlowCarrierStepDynamic:lower_plan_edge_source() return Lower.LowerCarrierEdgeCarryDynamic(self.step) end
function Flow.FlowCarrierStepRecompute:lower_plan_edge_source() return Lower.LowerCarrierEdgeRecompute(self.index) end

function Flow.FlowCarrierThread:lower_plan_block_param(block)
  return Lower.LowerCarrierBlockParam(self.id, block, C.CBackendLocalId("sem_car_" .. short_hash(self.id.text .. "\0" .. block.func.text .. "\0" .. block.block.text)), self.value_ty)
end

function Flow.FlowCarrierThread:lower_plan_recompute_edge_source(edge, flow)
  for _, fact in ipairs((flow and flow.edges) or {}) do
    if fact.edge == edge then
      for _, arg in ipairs(fact.args or {}) do
        if arg.dst_param == self.index then return Lower.LowerCarrierEdgeRecompute(arg.src) end
      end
    end
  end
  return Lower.LowerCarrierEdgeRecompute(self.index)
end

local function carrier_has_block(blocks, block)
  for _, b in ipairs(blocks or {}) do if b.block == block then return true end end
  return false
end

function Flow.FlowCarrierThread:lower_plan_edge_transfer(edge, blocks, flow)
  if not carrier_has_block(blocks, edge.to) then return nil end
  local transfer = self:lower_plan_transfer_for_edge(edge)
  local source
  if transfer ~= nil and carrier_has_block(blocks, edge.from) then source = transfer.step:lower_plan_edge_source(self, edge, flow)
  elseif carrier_has_block(blocks, edge.from) then source = Lower.LowerCarrierEdgeCarrySame
  else source = self:lower_plan_recompute_edge_source(edge, flow) end
  return Lower.LowerCarrierEdgeTransfer(self.id, edge, source, C.CBackendLocalId("sem_car_" .. short_hash(self.id.text .. "\0" .. edge.to.func.text .. "\0" .. edge.to.block.text)))
end

function Flow.FlowCarrierThread:lower_plan_carrier(graph_loops, graph, flow)
  local blocks = {}
  for _, block in ipairs(self.blocks or {}) do blocks[#blocks + 1] = self:lower_plan_block_param(block) end
  local transfers = {}
  for _, fg in ipairs((graph and graph.funcs) or {}) do
    if fg.func == self.func then
      for _, edge in ipairs(fg.edges or {}) do
        local transfer = self:lower_plan_edge_transfer(edge, blocks, flow)
        if transfer ~= nil then transfers[#transfers + 1] = transfer end
      end
    end
  end
  return Lower.LowerCarrierPlan(self.id, self.index, self.value_ty, Lower.LowerCarrierCarry, blocks, transfers, { Lower.LowerProofCoverage("Flow carrier selected for carry lowering") })
end

----------------------------------------------------------------------
-- Address plan helpers
----------------------------------------------------------------------

function Kernel.KernelLane:lower_plan_address_lane_use(address)
  for _, lane_access in ipairs(self.accesses or {}) do
    for _, address_access in ipairs(address.accesses or {}) do
      if lane_access == address_access then return Lower.LowerAddressLaneUse(address.id, self.id) end
    end
  end
  return nil
end

function Kernel.KernelPlan:lower_plan_address_lane_uses(address, out) end

function Kernel.KernelPlanned:lower_plan_address_lane_uses(address, out)
  for _, lane in ipairs(self.body and self.body.lanes or {}) do
    local use = lane:lower_plan_address_lane_use(address)
    if use ~= nil then out[#out + 1] = use end
  end
end

local function lower_plan_address_lane_uses(address, kernels)
  local out = {}
  for _, plan in ipairs((kernels and kernels.plans) or {}) do plan:lower_plan_address_lane_uses(address, out) end
  return out
end

function Flow.FlowAddressUse:lower_plan_inst_use(address)
  return Lower.LowerAddressInstUse(address.id, self.inst)
end

function Flow.FlowAddressThread:lower_plan_inst_uses()
  local out = {}
  for _, use in ipairs(self.uses or {}) do out[#out + 1] = use:lower_plan_inst_use(self) end
  return out
end

function Lower.LowerCarrierBlockParam:lower_plan_address_block_param(address)
  return Lower.LowerAddressBlockParam(address.id, self.block, C.CBackendLocalId("sem_addr_" .. short_hash(address.id.text .. "\0" .. self.block.func.text .. "\0" .. self.block.block.text)), address.base.elem_ty)
end

function Lower.LowerCarrierEdgeSource:lower_plan_address_edge_source(address)
  error("code_lower_plan: unsupported carrier edge source for address transfer " .. tostring(self), 2)
end

function Lower.LowerCarrierEdgeRecompute:lower_plan_address_edge_source(address)
  return Lower.LowerAddressEdgeRecomputeFromCarrier(self.index)
end

function Lower.LowerCarrierEdgeCarrySame:lower_plan_address_edge_source(address)
  return Lower.LowerAddressEdgeCarrySame
end

function Lower.LowerCarrierEdgeCarryConst:lower_plan_address_edge_source(address)
  return Lower.LowerAddressEdgeCarryConstBytes(self.amount * address.base.elem_size)
end

function Lower.LowerCarrierEdgeCarryDynamic:lower_plan_address_edge_source(address)
  return Lower.LowerAddressEdgeCarryDynamicBytes(self.step, address.base.elem_size)
end

function Lower.LowerCarrierEdgeTransfer:lower_plan_address_edge_transfer(address)
  return Lower.LowerAddressEdgeTransfer(address.id, self.edge, self.source:lower_plan_address_edge_source(address), C.CBackendLocalId("sem_addr_" .. short_hash(address.id.text .. "\0" .. self.edge.to.func.text .. "\0" .. self.edge.to.block.text)))
end

function Lower.LowerCarrierPlan:lower_plan_address_strategy(address)
  return Lower.LowerAddressCarryProjected
end

function Lower.LowerCarrierPlan:lower_plan_address_blocks(address)
  local out = {}
  for _, block in ipairs(self.blocks or {}) do out[#out + 1] = block:lower_plan_address_block_param(address) end
  return out
end

function Lower.LowerCarrierPlan:lower_plan_address_transfers(address)
  local out = {}
  for _, transfer in ipairs(self.transfers or {}) do out[#out + 1] = transfer:lower_plan_address_edge_transfer(address) end
  return out
end

function Lower.LowerCarrierPlanProjection:lookup(carrier)
  for _, plan in ipairs(self.plans) do if plan.carrier == carrier then return Lower.LowerCarrierPlanFound(plan) end end
  return Lower.LowerCarrierPlanMissing(carrier)
end
function Lower.LowerCarrierPlanFound:lower_plan_address(address, kernels)
  local carrier = self.plan
  return Lower.LowerAddressPlan(
    address.id, address.carrier, address.base, carrier:lower_plan_address_strategy(address),
    carrier:lower_plan_address_blocks(address), carrier:lower_plan_address_transfers(address),
    lower_plan_address_lane_uses(address, kernels), address:lower_plan_inst_uses(),
    { Lower.LowerProofCoverage("Flow address selected for materialization"), Lower.LowerProofCoverage("address projection carried from Flow carrier recurrence") })
end
function Lower.LowerCarrierPlanMissing:lower_plan_address(address, kernels)
  return Lower.LowerAddressPlan(
    address.id, address.carrier, address.base, Lower.LowerAddressReject("missing LowerCarrierPlan for Flow address carrier " .. self.carrier.text),
    {}, {}, lower_plan_address_lane_uses(address, kernels), address:lower_plan_inst_uses(),
    { Lower.LowerProofCoverage("Flow address selected for materialization") })
end
function Flow.FlowAddressThread:lower_plan_address(kernels, carriers) return carriers:lookup(self.carrier):lower_plan_address(self, kernels) end

local function carrier_and_address_plans(flow, graph, kernels)
  local carriers, addresses = {}, {}
  for _, carrier in ipairs(flow.carriers) do carriers[#carriers + 1] = carrier:lower_plan_carrier({}, graph, flow) end
  local projection = Lower.LowerCarrierPlanProjection(carriers)
  for _, address in ipairs(flow.addresses) do addresses[#addresses + 1] = address:lower_plan_address(kernels, projection) end
  return carriers, addresses
end

----------------------------------------------------------------------
-- Relation-driven lower module planning
----------------------------------------------------------------------

local function is_covered(covered, block)
  for _, value in ipairs(covered) do if value == block then return true end end
  return false
end
local function loop_is_available(loop, covered)
  for _, block in ipairs(loop.body) do if is_covered(covered, block.block) then return false end end
  return true
end
local function ordered_loops(graph_func)
  local loops = {}
  for i, loop in ipairs(graph_func.loops) do loops[#loops + 1] = Lower.LowerOrderedLoop(loop, i) end
  table.sort(loops, function(a, b)
    if #a.loop.body ~= #b.loop.body then return #a.loop.body < #b.loop.body end
    if a.loop.id.text ~= b.loop.id.text then return a.loop.id.text < b.loop.id.text end
    return a.ordinal < b.ordinal
  end)
  return loops
end
function Graph.CodeGraph:lower_func_lookup(func)
  for _, graph_func in ipairs(self.funcs) do if graph_func.func == func then return Lower.LowerCodeFuncGraphFound(graph_func) end end
  return Lower.LowerCodeFuncGraphMissing(func)
end
function Lower.LowerLoopFragmentResult:apply_lower_state(state)
  return Lower.LowerFuncPlanState(
    append_all(state.fragments, { self.fragment }),
    append_all(state.covered_blocks, self.covered_blocks),
    append_all(state.issues, self.issues))
end
function Lower.LowerFuncPlanState:add_code_block(func, block)
  if is_covered(self.covered_blocks, block.id) then return self end
  local fragment = Lower.LowerFragment(
    Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":block:" .. sanitize(block.id.text)),
    Lower.LowerCoverBlock(func.id, block.id), Lower.LowerStrategyCode("ordinary Code lowering for uncovered block"),
    { Lower.LowerProofCoverage("block is not covered by a semantic fragment") }, {})
  return Lower.LowerFuncPlanState(append_all(self.fragments, { fragment }), append_all(self.covered_blocks, { block.id }), self.issues)
end
local function plan_func(func, ordered_graph_loops, kernels, schedules)
  local state = Lower.LowerFuncPlanState({}, {}, {})
  for _, ordered in ipairs(ordered_graph_loops) do
    local loop = ordered.loop
    if loop_is_available(loop, state.covered_blocks) then
      local candidate = kernels:lookup(loop.id):lower_fragment_candidate(schedules)
      local result = candidate:select_lower_fragment():lower_loop_fragment(Lower.LowerLoopFragmentInput(func.id, loop, Lower.LowerCoverLoop(loop.id)))
      state = result:apply_lower_state(state)
    end
  end
  for _, block in ipairs(func.blocks) do state = state:add_code_block(func, block) end
  return Lower.LowerFunctionPlanResult(Lower.LowerFuncPlan(func.id, state.fragments), state.issues)
end
function Lower.LowerCodeFuncGraphFound:plan_lower_func(func, kernels, schedules) return plan_func(func, ordered_loops(self.graph), kernels, schedules) end
function Lower.LowerCodeFuncGraphMissing:plan_lower_func(func, kernels, schedules) return plan_func(func, {}, kernels, schedules) end
function Code.CodeModule:plan_lowering(graph, kernels, schedules, target)
  local selected_target = target or Lower.LowerTargetBack
  local kernel_projection = kernels:lower_kernel_projection()
  local schedule_projection = schedules:lower_schedule_projection()
  local func_entries, issues = {}, {}
  for _, func in ipairs(self.funcs) do
    local result = graph:lower_func_lookup(func.id):plan_lower_func(func, kernel_projection, schedule_projection)
    func_entries = append_all(func_entries, { Lower.LowerFunctionPlanEntry(func.id, result.plan) })
    issues = append_all(issues, result.issues)
  end
  local carrier_plans, address_plans = carrier_and_address_plans(kernels.flow, graph, kernels)
  return Lower.LowerModule(
    self.id,
    selected_target,
    kernels,
    schedules,
    Lower.LowerCarrierPlanProjection(carrier_plans),
    Lower.LowerAddressPlanProjection(address_plans),
    Lower.LowerFunctionPlanProjection(func_entries),
    issues)
end
