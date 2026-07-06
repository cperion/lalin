local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
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

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_lower_plan ~= nil then return T._lalin_api_cache.code_lower_plan end

    local Flow = T.LalinFlow
    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local Lower = T.LalinLower
    local C = T.LalinC
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)

    local api = {}
    local block_set_for
    local schedule_summary

    function Schedule.KernelSchedule:lower_plan_fragment_candidate(kplan, closed_form, skipped)
        return Lower.LowerFragmentNoSchedule("explicit Code fallback for " .. skipped .. ": " .. schedule_summary(self))
    end
    function Schedule.SchedulePlanned:lower_plan_fragment_candidate(kplan, closed_form, skipped)
        return self.form:lower_plan_fragment_candidate(kplan, closed_form, skipped, self)
    end
    function Schedule.ScheduleForm:lower_plan_fragment_candidate(kplan, closed_form, skipped, schedule)
        return Lower.LowerFragmentKernelCandidate(kplan, schedule)
    end
    function Schedule.ScheduleClosedForm:lower_plan_fragment_candidate(kplan, closed_form, skipped, schedule)
        if closed_form ~= nil then return Lower.LowerFragmentClosedFormCandidate(closed_form) end
        return Lower.LowerFragmentClosedFormMissing("explicit Code fallback because ScheduleClosedForm has no ClosedFormFact")
    end

    function Kernel.KernelResult:lower_plan_closed_form_fact() return nil end
    function Kernel.KernelResultClosedForm:lower_plan_closed_form_fact() return self.closed_form end

    function Lower.LowerFragmentCandidate:select_lower_fragment()
        return Lower.LowerSelectNone
    end

    function Lower.LowerFragmentClosedFormCandidate:select_lower_fragment()
        return Lower.LowerSelectClosedForm(self.closed_form)
    end

    function Lower.LowerFragmentClosedFormMissing:select_lower_fragment()
        return Lower.LowerSelectFallback(self.reason)
    end

    function Lower.LowerFragmentKernelCandidate:select_lower_fragment()
        return Lower.LowerSelectKernel
    end

    function Lower.LowerFragmentNoSchedule:select_lower_fragment()
        return Lower.LowerSelectFallback(self.reason)
    end

    function Lower.LowerFragmentKernelRejected:select_lower_fragment()
        return Lower.LowerSelectFallback(self.reason)
    end

    function Lower.LowerFragmentSelection:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        error("code_lower_plan: unsupported lower fragment selection", 2)
    end

    function Lower.LowerSelectClosedForm:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        fragments[#fragments + 1] = Lower.LowerFragment(
            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":semantic:" .. sanitize(loop.id.text)),
            cover,
            Lower.LowerStrategyClosedForm(kplan.id, self.closed_form),
            {
                Lower.LowerProofKernel(kplan.id, "planned semantic closed-form kernel"),
                Lower.LowerProofSchedule(sched.id, "closed-form schedule has a semantic lowering emitter"),
            },
            {}
        )
        for block in pairs(block_set_for(loop)) do covered[block] = true end
    end

    function Lower.LowerSelectKernel:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        fragments[#fragments + 1] = Lower.LowerFragment(
            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":semantic:" .. sanitize(loop.id.text)),
            cover,
            Lower.LowerStrategyKernel(kplan.id, sched.id),
            {
                Lower.LowerProofKernel(kplan.id, "planned semantic kernel"),
                Lower.LowerProofSchedule(sched.id, "kernel schedule has a semantic lowering emitter"),
            },
            {}
        )
        for block in pairs(block_set_for(loop)) do covered[block] = true end
    end

    function Lower.LowerSelectFallback:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
        local issue = Lower.LowerIssueFallback(cover, self.reason)
        issues[#issues + 1] = issue
        fragments[#fragments + 1] = Lower.LowerFragment(
            Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":loop_fallback:" .. sanitize(loop.id.text)),
            cover,
            Lower.LowerStrategyCode(self.reason),
            { Lower.LowerProofFallback(self.reason) },
            { issue }
        )
        for block in pairs(block_set_for(loop)) do covered[block] = true end
    end

    function Lower.LowerSelectNone:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched) end

    local function graph_indexes(graph)
        local loops, funcs = {}, {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            funcs[fg.func.text] = fg
            for _, loop in ipairs(fg.loops or {}) do loops[loop.id.text] = loop end
        end
        return funcs, loops
    end

    local function kernels_by_loop(kernels)
        local planned, no_plan = {}, {}
        for _, plan in ipairs(kernels and kernels.plans or {}) do
            local cls = asdl.classof(plan)
            if cls == Kernel.KernelPlanned and asdl.classof(plan.subject) == Kernel.KernelSubjectLoop then planned[plan.subject.loop.text] = plan end
            if cls == Kernel.KernelNoPlan and asdl.classof(plan.subject) == Kernel.KernelSubjectLoop then no_plan[plan.subject.loop.text] = plan end
        end
        return planned, no_plan
    end

    local function schedule_by_kernel(schedules)
        local out = {}
        for _, sched in ipairs(schedules and schedules.schedules or {}) do out[sched.kernel.text] = sched end
        return out
    end

    block_set_for = function(loop)
        local set = {}
        for _, bid in ipairs(loop and loop.body or {}) do set[bid.block.text] = true end
        return set
    end

    local function loop_body_count(loop)
        return #(loop and loop.body or {})
    end

    local function ordered_loops(graph_func)
        local loops = {}
        for i, loop in ipairs(graph_func and graph_func.loops or {}) do
            loops[#loops + 1] = { loop = loop, ordinal = i, blocks = loop_body_count(loop) }
        end
        table.sort(loops, function(a, b)
            if a.blocks ~= b.blocks then return a.blocks < b.blocks end
            local at = a.loop and a.loop.id and a.loop.id.text or ""
            local bt = b.loop and b.loop.id and b.loop.id.text or ""
            if at ~= bt then return at < bt end
            return a.ordinal < b.ordinal
        end)
        return loops
    end

    local function can_claim_loop(loop, covered)
        for block in pairs(block_set_for(loop)) do
            if covered[block] then return false end
        end
        return true
    end

    local function loop_result_closed_form(kernel_plan)
        local result = kernel_plan and kernel_plan.body and kernel_plan.body.result or nil
        if asdl.classof(result) == Kernel.KernelResultClosedForm then return result.closed_form end
        return nil
    end

    local function reject_summary(rejects)
        local out = {}
        for _, reject in ipairs(rejects or {}) do out[#out + 1] = tostring(asdl.classof(reject) or reject) end
        return #out > 0 and table.concat(out, ",") or "no detailed rejects"
    end

    schedule_summary = function(sched)
        if sched == nil then return "no schedule was produced" end
        if asdl.classof(sched) == Schedule.ScheduleNoPlan then return "schedule rejected: " .. reject_summary(sched.rejects) end
        return "schedule selected"
    end

    local function lower_fragment_input(loop, kplan, no_plan, sched)
        local cf = loop_result_closed_form(kplan)
        local skipped
        if cf ~= nil then
            skipped = "closed-form fact " .. tostring(cf.id and cf.id.text or cf)
        elseif kplan ~= nil then
            skipped = "kernel " .. kplan.id.text
        else
            skipped = "loop " .. loop.id.text
        end

        if kplan ~= nil then
            if sched ~= nil then return sched:lower_plan_fragment_candidate(kplan, cf, skipped) end
            return Lower.LowerFragmentNoSchedule("explicit Code fallback for " .. skipped .. ": " .. schedule_summary(sched))
        end
        if no_plan ~= nil then
            return Lower.LowerFragmentKernelRejected("explicit Code fallback because KernelNoPlan rejected loop: " .. reject_summary(no_plan.rejects))
        end
        return Lower.LowerFragmentNoCandidate
    end

    local function carrier_param_id(carrier, block)
        return C.CBackendLocalId("sem_car_" .. short_hash(carrier.id.text .. "\0" .. block.func.text .. "\0" .. block.block.text))
    end

    local function address_param_id(address, block)
        return C.CBackendLocalId("sem_addr_" .. short_hash(address.id.text .. "\0" .. block.func.text .. "\0" .. block.block.text))
    end

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
        return Lower.LowerCarrierBlockParam(self.id, block, carrier_param_id(self, block), self.value_ty)
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
        return Lower.LowerCarrierEdgeTransfer(self.id, edge, source, carrier_param_id(self, edge.to))
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
        return Lower.LowerAddressBlockParam(address.id, self.block, address_param_id(address, self.block), address.base.elem_ty)
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
        return Lower.LowerAddressEdgeTransfer(address.id, self.edge, self.source:lower_plan_address_edge_source(address), address_param_id(address, self.edge.to))
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

    function Flow.FlowAddressThread:lower_plan_address(kernels, carrier_plan_by_id)
        local carrier = carrier_plan_by_id and carrier_plan_by_id[self.carrier.text] or nil
        local strategy, blocks, transfers
        local proofs = { Lower.LowerProofCoverage("Flow address selected for materialization") }
        if carrier == nil then
            strategy = Lower.LowerAddressReject("missing LowerCarrierPlan for Flow address carrier " .. self.carrier.text)
            blocks, transfers = {}, {}
        else
            strategy = carrier:lower_plan_address_strategy(self)
            blocks = carrier:lower_plan_address_blocks(self)
            transfers = carrier:lower_plan_address_transfers(self)
            proofs[#proofs + 1] = Lower.LowerProofCoverage("address projection carried from Flow carrier recurrence")
        end
        return Lower.LowerAddressPlan(self.id, self.carrier, self.base, strategy, blocks, transfers, lower_plan_address_lane_uses(self, kernels), self:lower_plan_inst_uses(), proofs)
    end

    local function carrier_and_address_plans(flow, graph, kernels)
        local _, graph_loops = graph_indexes(graph)
        local carriers, addresses, carrier_plan_by_id = {}, {}, {}
        for _, carrier in ipairs((flow and flow.carriers) or {}) do
            local plan = carrier:lower_plan_carrier(graph_loops, graph, flow)
            carriers[#carriers + 1] = plan
            carrier_plan_by_id[plan.carrier.text] = plan
        end
        for _, address in ipairs((flow and flow.addresses) or {}) do addresses[#addresses + 1] = address:lower_plan_address(kernels, carrier_plan_by_id) end
        return carriers, addresses
    end

    local function plan_func(func, graph_func, kernel_for_loop, kernel_no_plan_for_loop, schedule_for_kernel, issues)
        local fragments, covered = {}, {}
        local function add(fragment)
            fragments[#fragments + 1] = fragment
            return fragment
        end

        for _, ordered in ipairs(ordered_loops(graph_func)) do
            local loop = ordered.loop
            if can_claim_loop(loop, covered) then
                local kplan = kernel_for_loop[loop.id.text]
                local cover = Lower.LowerCoverLoop(loop.id)
                local sched = kplan ~= nil and schedule_for_kernel[kplan.id.text] or nil
                local no_plan = kernel_no_plan_for_loop[loop.id.text]
                local selection = lower_fragment_input(loop, kplan, no_plan, sched):select_lower_fragment()
                selection:lower_plan_add_loop_fragment(func, loop, cover, fragments, covered, issues, kplan, sched)
            end
        end

        for _, block in ipairs(func.blocks or {}) do
            if not covered[block.id.text] then
                add(Lower.LowerFragment(
                    Lower.LowerFragmentId("frag:" .. sanitize(func.id.text) .. ":block:" .. sanitize(block.id.text)),
                    Lower.LowerCoverBlock(func.id, block.id),
                    Lower.LowerStrategyCode("ordinary Code lowering for uncovered block"),
                    { Lower.LowerProofCoverage("block is not covered by a kernel fragment") },
                    {}
                ))
                covered[block.id.text] = true
            end
        end

        if #fragments == 0 then
            local issue = Lower.LowerIssueGap(func.id, "function has no Code blocks to cover")
            issues[#issues + 1] = issue
        end
        return Lower.LowerFuncPlan(func.id, fragments)
    end

    local function plan(code_module, graph, kernels, schedules, target)
        graph = graph or CodeGraph.graph(code_module)
        if kernels == nil then
            local flow = CodeFlowFacts.facts(code_module, graph)
            local value = CodeValueFacts.facts(code_module, graph, flow)
            local mem = CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
            local effect = CodeEffectFacts.facts(code_module, graph, mem, nil)
            kernels = CodeKernelPlan.plan(code_module, graph, flow, value, mem, effect)
            schedules = schedules or CodeSchedulePlan.plan(code_module, kernels, flow, value, mem, effect, nil)
        end
        schedules = schedules or CodeSchedulePlan.plan(code_module, kernels, nil, nil, nil, nil, nil)
        target = target or Lower.LowerTargetBack

        local graph_funcs = graph_indexes(graph)
        local kernel_for_loop, kernel_no_plan_for_loop = kernels_by_loop(kernels)
        local schedule_for_kernel = schedule_by_kernel(schedules)
        local funcs, issues = {}, {}
        for _, func in ipairs(code_module.funcs or {}) do funcs[#funcs + 1] = plan_func(func, graph_funcs[func.id.text], kernel_for_loop, kernel_no_plan_for_loop, schedule_for_kernel, issues) end
        local carrier_plans, address_plans = carrier_and_address_plans(kernels and kernels.flow, graph, kernels)
        return Lower.LowerModule(code_module.id, target, kernels, schedules, carrier_plans, address_plans, funcs, issues)
    end

    api.plan = plan
    api.module = plan

    T._lalin_api_cache.code_lower_plan = api
    return api
end

return bind_context
