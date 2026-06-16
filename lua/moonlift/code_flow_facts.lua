local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_flow_facts ~= nil then return T._moonlift_api_cache.code_flow_facts end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Flow = T.MoonFlow

    local api = {}

    local function block_order(func)
        local by_id, order = {}, {}
        for i = 1, #(func.blocks or {}) do
            local block = func.blocks[i]
            by_id[block.id.text] = block
            order[block.id.text] = i
        end
        return by_id, order
    end

    local function edge_args(dest_block, args)
        local out = {}
        local params = dest_block and dest_block.params or {}
        for i = 1, #(args or {}) do
            local param = params[i]
            if param ~= nil then out[#out + 1] = Flow.FlowEdgeArg(args[i], param.value) end
        end
        return out
    end

    local function append_edge_specs(func, block, block_by_id, specs, rejects)
        local term = block.term and block.term.kind or nil
        local cls = pvm.classof(term)
        local function add(dest, kind, args, condition)
            local dest_block = dest and block_by_id[dest.text] or nil
            specs[#specs + 1] = {
                func = func.id,
                pred = block.id,
                succ = dest,
                kind = kind,
                args = edge_args(dest_block, args or {}),
                condition = condition,
            }
        end
        if cls == Code.CodeTermJump then
            add(term.dest, Flow.FlowEdgeJump, term.args)
        elseif cls == Code.CodeTermBranch then
            add(term.then_dest, Flow.FlowEdgeThen, term.then_args, term.cond)
            add(term.else_dest, Flow.FlowEdgeElse, term.else_args, term.cond)
        elseif cls == Code.CodeTermSwitch then
            for i = 1, #(term.cases or {}) do
                local case = term.cases[i]
                local raw = case.literal and (case.literal.raw or tostring(case.literal.value)) or tostring(i)
                add(case.dest, Flow.FlowEdgeSwitchCase(raw), case.args)
            end
            add(term.default_dest, Flow.FlowEdgeSwitchDefault, term.default_args)
        elseif cls == Code.CodeTermVariantSwitch then
            for i = 1, #(term.cases or {}) do
                local case = term.cases[i]
                add(case.dest, Flow.FlowEdgeVariantCase(case.variant.variant_name), case.args)
            end
            add(term.default_dest, Flow.FlowEdgeVariantDefault, term.default_args)
        elseif cls == Code.CodeTermReturn or cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then
            -- Terminal blocks have no CFG successors.
        else
            rejects[#rejects + 1] = Flow.FlowRejectUnsupportedTerminator(block.id, term or Code.CodeTermUnreachable("missing terminator"))
        end
    end

    local function add_pred(preds, succ, pred)
        if succ == nil then return end
        local key = succ.text
        preds[key] = preds[key] or {}
        preds[key][#preds[key] + 1] = pred
    end

    local function value_defs(func)
        local defs, types = {}, {}
        for _, param in ipairs(func.params or {}) do types[param.value.text] = param.ty end
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do types[param.value.text] = param.ty end
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local cls = pvm.classof(k)
                if cls == Code.CodeInstConst then
                    defs[k.dst.text] = { cls = cls, inst = inst, const = k.const }
                    types[k.dst.text] = k.const.ty
                elseif cls == Code.CodeInstAlias then
                    defs[k.dst.text] = { cls = cls, inst = inst, src = k.src }
                    types[k.dst.text] = k.ty
                elseif cls == Code.CodeInstBinary then
                    defs[k.dst.text] = { cls = cls, inst = inst, op = k.op, ty = k.ty, semantics = k.semantics, lhs = k.lhs, rhs = k.rhs }
                    types[k.dst.text] = k.ty
                elseif cls == Code.CodeInstCompare then
                    defs[k.dst.text] = { cls = cls, inst = inst, op = k.op, operand_ty = k.operand_ty, lhs = k.lhs, rhs = k.rhs }
                    types[k.dst.text] = Code.CodeTyBool8
                elseif k.dst ~= nil then
                    defs[k.dst.text] = { cls = cls, inst = inst }
                    types[k.dst.text] = k.ty or k.ptr_ty or k.tag_ty or k.view_ty
                end
            end
        end
        return defs, types
    end

    local function const_ranges(defs)
        local ranges = {}
        local keys = {}
        for key in pairs(defs) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local def = defs[key]
            if def.cls == Code.CodeInstConst and pvm.classof(def.const) == Code.CodeConstLiteral then
                local lit = def.const.literal
                if lit ~= nil and lit.raw ~= nil then
                    local value = Code.CodeValueId(key)
                    ranges[#ranges + 1] = Flow.FlowRangeExact(value, Flow.FlowBoundConst(lit.raw))
                end
            end
        end
        return ranges
    end

    local function natural_loop(header, latch, preds)
        local set = {}
        set[header.text] = true
        set[latch.text] = true
        local stack = { latch }
        while #stack > 0 do
            local node = table.remove(stack)
            for _, pred in ipairs(preds[node.text] or {}) do
                if not set[pred.text] then
                    set[pred.text] = true
                    if pred.text ~= header.text then stack[#stack + 1] = pred end
                end
            end
        end
        return set
    end

    local function incoming_arg_for(edges, header, param, skip_pred)
        for _, edge in ipairs(edges) do
            if edge.succ == header and (skip_pred == nil or edge.pred ~= skip_pred) then
                for _, arg in ipairs(edge.args or {}) do
                    if arg.dst_param == param.value then return arg.src end
                end
            end
        end
        return nil
    end

    local function backedge_arg_for(edge, param)
        for _, arg in ipairs(edge.args or {}) do
            if arg.dst_param == param.value then return arg.src end
        end
        return nil
    end

    local function induction_step(param_value, back_value, defs)
        local def = back_value and defs[back_value.text] or nil
        if def == nil or def.cls ~= Code.CodeInstBinary then return nil, "backedge value is not a binary recurrence" end
        if def.op == Core.BinAdd then
            if def.lhs == param_value then return def.rhs, nil end
            if def.rhs == param_value then return def.lhs, nil end
        elseif def.op == Core.BinSub then
            if def.lhs == param_value then return def.rhs, "subtraction induction records positive step magnitude; signed direction is not represented yet" end
        end
        return nil, "binary recurrence does not reference the header parameter"
    end

    local function compare_stop(cond, induction_value, defs)
        local def = cond and defs[cond.text] or nil
        if def == nil or def.cls ~= Code.CodeInstCompare then return nil, nil end
        if def.lhs == induction_value then
            local op = def.op
            local exclusive = (op == Core.CmpLt or op == Core.CmpGe)
            return def.rhs, exclusive
        elseif def.rhs == induction_value then
            local op = def.op
            local exclusive = (op == Core.CmpGt or op == Core.CmpLe)
            return def.lhs, exclusive
        end
        return nil, nil
    end

    local function ordered_body_blocks(func, set)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do
            if set[block.id.text] then out[#out + 1] = block.id end
        end
        return out
    end

    local function analyze_func(func, out_edges, out_loops, out_ranges, out_rejects)
        local block_by_id, order = block_order(func)
        local specs, rejects = {}, {}
        for _, block in ipairs(func.blocks or {}) do append_edge_specs(func, block, block_by_id, specs, rejects) end
        for _, reject in ipairs(rejects) do out_rejects[#out_rejects + 1] = reject end

        local preds, succ_count = {}, {}
        for _, spec in ipairs(specs) do
            add_pred(preds, spec.succ, spec.pred)
            succ_count[spec.pred.text] = (succ_count[spec.pred.text] or 0) + 1
        end

        local defs, types = value_defs(func)
        local ranges = const_ranges(defs)
        for _, range in ipairs(ranges) do out_ranges[#out_ranges + 1] = range end

        local edge_roles = {}
        local loops = {}
        for i, spec in ipairs(specs) do
            local pred_order = order[spec.pred.text]
            local succ_order = spec.succ and order[spec.succ.text]
            if pred_order ~= nil and succ_order ~= nil and succ_order <= pred_order then
                local loop_id = Flow.FlowLoopId("loop:" .. sanitize(func.name) .. ":" .. sanitize(spec.succ.text))
                edge_roles[i] = edge_roles[i] or {}
                edge_roles[i][#edge_roles[i] + 1] = Flow.FlowRoleBackedge(loop_id)
                loops[#loops + 1] = { id = loop_id, header = spec.succ, latch = spec.pred, backedge = spec }
            end
        end

        for _, loop in ipairs(loops) do
            loop.body = natural_loop(loop.header, loop.latch, preds)
            loop.exits = {}
            for i, spec in ipairs(specs) do
                if loop.body[spec.pred.text] and spec.succ ~= nil and not loop.body[spec.succ.text] then
                    edge_roles[i] = edge_roles[i] or {}
                    edge_roles[i][#edge_roles[i] + 1] = Flow.FlowRoleLoopExit(loop.id)
                    loop.exits[#loop.exits + 1] = Flow.FlowLoopExit(spec.pred, spec.succ, spec.condition)
                end
            end
        end

        for i, spec in ipairs(specs) do
            if succ_count[spec.pred.text] and succ_count[spec.pred.text] > 1 and #(preds[spec.succ.text] or {}) > 1 then
                edge_roles[i] = edge_roles[i] or {}
                edge_roles[i][#edge_roles[i] + 1] = Flow.FlowRoleCritical
            end
            out_edges[#out_edges + 1] = Flow.FlowEdge(
                Flow.FlowEdgeId("edge:" .. sanitize(func.name) .. ":" .. tostring(i)),
                spec.func,
                spec.pred,
                spec.succ,
                spec.kind,
                edge_roles[i] or {},
                spec.args or {}
            )
        end

        for _, loop in ipairs(loops) do
            local header_block = block_by_id[loop.header.text]
            local loop_rejects, inductions = {}, {}
            local stop, stop_exclusive = nil, true
            local primary = nil
            if header_block ~= nil then
                for _, exit in ipairs(loop.exits) do
                    local candidate, exclusive = compare_stop(exit.condition, nil, defs)
                    if candidate ~= nil then stop, stop_exclusive = candidate, exclusive end
                end
                for _, param in ipairs(header_block.params or {}) do
                    local init = incoming_arg_for(specs, loop.header, param, loop.latch)
                    local back = backedge_arg_for(loop.backedge, param)
                    local step, step_note = induction_step(param.value, back, defs)
                    if init ~= nil and step ~= nil then
                        for _, exit in ipairs(loop.exits) do
                            local candidate, exclusive = compare_stop(exit.condition, param.value, defs)
                            if candidate ~= nil then stop, stop_exclusive = candidate, exclusive end
                        end
                        local range = stop and Flow.FlowRangeDerived(param.value, Flow.FlowBoundValue(init), Flow.FlowBoundValue(stop), "counted loop induction") or Flow.FlowRangeUnknown(param.value)
                        out_ranges[#out_ranges + 1] = range
                        local induction = Flow.FlowInduction(param.value, param.ty or types[param.value.text] or Code.CodeTyIndex, init, step, Flow.FlowPrimaryInduction, range)
                        inductions[#inductions + 1] = induction
                        if primary == nil then primary = induction end
                        if step_note ~= nil then loop_rejects[#loop_rejects + 1] = Flow.FlowRejectUnsupportedInduction(param.value, step_note) end
                    elseif back ~= nil then
                        loop_rejects[#loop_rejects + 1] = Flow.FlowRejectUnsupportedInduction(param.value, step or step_note or "no affine backedge recurrence")
                    end
                end
            end

            local domain
            if primary ~= nil and stop ~= nil then
                domain = Flow.FlowDomainCounted(Flow.FlowCountedDomain(primary.init, stop, primary.step, stop_exclusive ~= false))
            else
                local reject = Flow.FlowRejectNotCounted(loop.header, "no primary induction with comparable loop exit")
                loop_rejects[#loop_rejects + 1] = reject
                out_rejects[#out_rejects + 1] = reject
                domain = Flow.FlowDomainRejected(reject)
            end
            for _, reject in ipairs(loop_rejects) do
                if pvm.classof(reject) ~= Flow.FlowRejectNotCounted then out_rejects[#out_rejects + 1] = reject end
            end
            out_loops[#out_loops + 1] = Flow.FlowLoopFacts(
                loop.id,
                Flow.FlowLoopFromCode(func.id, loop.header, loop.latch),
                domain,
                ordered_body_blocks(func, loop.body),
                inductions,
                loop.exits,
                {},
                loop_rejects
            )
        end
    end

    local function facts(module)
        local edges, loops, ranges, rejects = {}, {}, {}, {}
        for _, func in ipairs(module.funcs or {}) do analyze_func(func, edges, loops, ranges, rejects) end
        return Flow.FlowFactSet(module.id, edges, loops, ranges, rejects)
    end

    local function literal_number(raw)
        if raw == nil then return nil end
        return tonumber(tostring(raw))
    end

    local function const_values(defs)
        local out = {}
        for key, def in pairs(defs or {}) do
            if def.cls == Code.CodeInstConst and pvm.classof(def.const) == Code.CodeConstLiteral then
                local lit = def.const.literal
                if lit ~= nil and lit.raw ~= nil then out[key] = lit.raw end
            end
        end
        return out
    end

    local function const_number(value, consts)
        return value and literal_number(consts[value.text]) or nil
    end

    local function bound_for_value(value, consts)
        if value ~= nil and consts[value.text] ~= nil then return Flow.FlowBoundConst(consts[value.text]) end
        return Flow.FlowBoundValue(value)
    end

    local function is_primary_induction(induction)
        return induction ~= nil and induction.kind == Flow.FlowPrimaryInduction
    end

    local function edge_has_role(edge, role_cls, loop_id)
        for _, role in ipairs(edge.roles or {}) do
            if pvm.classof(role) == role_cls and (loop_id == nil or role.loop == loop_id) then return true end
        end
        return false
    end

    local function backedge_for_loop(flow_facts, loop_id)
        for _, edge in ipairs(flow_facts.edges or {}) do
            if edge_has_role(edge, Flow.FlowRoleBackedge, loop_id) then return edge end
        end
        return nil
    end

    local function backedge_value(edge, induction)
        if edge == nil or induction == nil then return nil end
        for _, arg in ipairs(edge.args or {}) do
            if arg.dst_param == induction.value then return arg.src end
        end
        return nil
    end

    local function recurrence_info(induction, edge, defs, consts)
        local src = backedge_value(edge, induction)
        local def = src and defs[src.text] or nil
        if def == nil or def.cls ~= Code.CodeInstBinary then return { direction = Flow.FlowLoopDirectionUnknown } end
        local step_num = const_number(induction.step, consts)
        local direction = Flow.FlowLoopDirectionUnknown
        if step_num ~= nil and step_num ~= 0 then
            if def.op == Core.BinAdd and (def.lhs == induction.value or def.rhs == induction.value) then
                direction = step_num > 0 and Flow.FlowLoopIncreasing or Flow.FlowLoopDecreasing
            elseif def.op == Core.BinSub and def.lhs == induction.value then
                direction = step_num > 0 and Flow.FlowLoopDecreasing or Flow.FlowLoopIncreasing
            end
        end
        local nowrap_reason = nil
        if def.semantics ~= nil and pvm.classof(def.semantics.overflow) == Code.CodeIntAssumeNoOverflow then
            nowrap_reason = def.semantics.overflow.reason or "integer semantics assume no overflow on induction update"
        end
        return { direction = direction, step_num = step_num, nowrap_reason = nowrap_reason }
    end

    local function trip_count_for(loop, counted, info)
        if info.direction == Flow.FlowLoopIncreasing and counted.stop_exclusive and info.step_num == 1 then
            return Flow.FlowTripCountNonNegative(
                Flow.FlowBoundDerived("trip-count:nonnegative:" .. loop.id.text, { counted.start, counted.stop, counted.step }),
                "increasing exclusive counted loop has a non-negative trip count; empty when start is not below stop"
            )
        end
        if info.nowrap_reason ~= nil and info.direction ~= Flow.FlowLoopDirectionUnknown and counted.stop_exclusive and info.step_num ~= nil then
            return Flow.FlowTripCountNonNegative(
                Flow.FlowBoundDerived("trip-count:nonnegative:" .. loop.id.text, { counted.start, counted.stop, counted.step }),
                "no-wrap monotone exclusive counted loop has a non-negative trip count"
            )
        end
        return Flow.FlowTripCountUnknown("trip count needs monotone exclusive step/range proof")
    end

    local function semantic_facts(module, flow_facts)
        flow_facts = flow_facts or facts(module)
        local defs_by_func, consts_by_func = {}, {}
        for _, func in ipairs(module.funcs or {}) do
            local defs = value_defs(func)
            defs_by_func[func.id.text] = defs
            consts_by_func[func.id.text] = const_values(defs)
        end

        local out = {}
        for _, loop in ipairs(flow_facts.loops or {}) do
            if pvm.classof(loop.domain) == Flow.FlowDomainCounted then
                local counted = loop.domain.counted
                local primary = nil
                for _, induction in ipairs(loop.inductions or {}) do
                    if is_primary_induction(induction) then primary = primary or induction end
                end

                local source = loop.source
                local func_id = source and source.func
                local defs = func_id and defs_by_func[func_id.text] or {}
                local consts = func_id and consts_by_func[func_id.text] or {}
                local backedge = backedge_for_loop(flow_facts, loop.id)
                local info = primary and recurrence_info(primary, backedge, defs, consts) or { direction = Flow.FlowLoopDirectionUnknown }

                out[#out + 1] = Flow.FlowLoopNormalizedCounted(loop.id, counted, info.direction, trip_count_for(loop, counted, info))

                if primary ~= nil and info.nowrap_reason ~= nil then
                    out[#out + 1] = Flow.FlowLoopInductionNoWrap(loop.id, primary.value, info.nowrap_reason)
                end

                if primary ~= nil and info.direction == Flow.FlowLoopIncreasing and counted.stop_exclusive and (info.step_num == 1 or info.nowrap_reason ~= nil) then
                    out[#out + 1] = Flow.FlowLoopInductionRange(Flow.FlowInductionRangeFact(
                        loop.id,
                        primary.value,
                        bound_for_value(counted.start, consts),
                        bound_for_value(counted.stop, consts),
                        true,
                        "primary induction of increasing exclusive counted loop stays within [start, stop) on executed iterations"
                    ))
                end
            end
        end
        return Flow.FlowSemanticFactSet(module.id, out)
    end

    api.facts = facts
    api.module = facts
    api.semantic_facts = semantic_facts
    api.semantics = semantic_facts

    T._moonlift_api_cache.code_flow_facts = api
    return api
end

return M
