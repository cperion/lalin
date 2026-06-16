local pvm = require("moonlift.pvm")

local M = {}

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.kernel_validate ~= nil then return T._moonlift_api_cache.kernel_validate end

    local Code = T.MoonCode
    local Flow = T.MoonFlow
    local Mem = T.MoonMem
    local Kernel = T.MoonKernel

    local api = {}

    local function issue(ctx, kind, message)
        local item = { kind = kind, message = message }
        ctx.issues[#ctx.issues + 1] = item
        if ctx.collector and ctx.collector.emit then pcall(function() ctx.collector:emit(item, "kernel") end) end
    end

    local function index_code(module)
        local idx = { funcs = {}, blocks = {}, insts = {}, values = {}, params = {}, access_by_inst = {}, kind_by_inst = {}, place_by_inst = {} }
        local function add_value(v) if v ~= nil then idx.values[v.text] = true end end
        local function scan_place(place)
            if place == nil then return end
            local cls = pvm.classof(place)
            if cls == Code.CodePlaceDeref then add_value(place.addr)
            elseif cls == Code.CodePlaceField then scan_place(place.base)
            elseif cls == Code.CodePlaceIndex then scan_place(place.base); add_value(place.index)
            elseif cls == Code.CodePlaceBytes then add_value(place.base) end
        end
        for _, func in ipairs(module.funcs or {}) do
            idx.funcs[func.id.text] = func
            for _, param in ipairs(func.params or {}) do add_value(param.value); idx.params[param.value.text] = true end
            for _, block in ipairs(func.blocks or {}) do
                idx.blocks[block.id.text] = block
                for _, param in ipairs(block.params or {}) do add_value(param.value); idx.params[param.value.text] = true end
                for _, inst in ipairs(block.insts or {}) do
                    idx.insts[inst.id.text] = inst
                    local k, cls = inst.kind, pvm.classof(inst.kind)
                    if k.dst ~= nil then add_value(k.dst) end
                    if cls == Code.CodeInstAlias then add_value(k.src)
                    elseif cls == Code.CodeInstUnary then add_value(k.value)
                    elseif cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstCompare then add_value(k.lhs); add_value(k.rhs)
                    elseif cls == Code.CodeInstCast then add_value(k.value)
                    elseif cls == Code.CodeInstSelect then add_value(k.cond); add_value(k.then_value); add_value(k.else_value)
                    elseif cls == Code.CodeInstPtrOffset then add_value(k.base); add_value(k.index)
                    elseif cls == Code.CodeInstLoad then idx.access_by_inst[inst.id.text] = k.access; idx.kind_by_inst[inst.id.text] = Mem.MemLoad; idx.place_by_inst[inst.id.text] = k.place; scan_place(k.place)
                    elseif cls == Code.CodeInstStore then idx.access_by_inst[inst.id.text] = k.access; idx.kind_by_inst[inst.id.text] = Mem.MemStore; idx.place_by_inst[inst.id.text] = k.place; scan_place(k.place); add_value(k.value)
                    elseif cls == Code.CodeInstAtomicLoad then idx.access_by_inst[inst.id.text] = k.access; idx.kind_by_inst[inst.id.text] = Mem.MemAtomicLoad; idx.place_by_inst[inst.id.text] = k.place; scan_place(k.place)
                    elseif cls == Code.CodeInstAtomicStore then idx.access_by_inst[inst.id.text] = k.access; idx.kind_by_inst[inst.id.text] = Mem.MemAtomicStore; idx.place_by_inst[inst.id.text] = k.place; scan_place(k.place); add_value(k.value)
                    elseif cls == Code.CodeInstAtomicRmw then idx.access_by_inst[inst.id.text] = k.access; idx.kind_by_inst[inst.id.text] = Mem.MemAtomicRmw; idx.place_by_inst[inst.id.text] = k.place; scan_place(k.place); add_value(k.value)
                    elseif cls == Code.CodeInstAtomicCas then idx.access_by_inst[inst.id.text] = k.access; idx.kind_by_inst[inst.id.text] = Mem.MemAtomicCas; idx.place_by_inst[inst.id.text] = k.place; scan_place(k.place); add_value(k.expected); add_value(k.replacement)
                    end
                end
                local term = block.term and block.term.kind
                local tcls = pvm.classof(term)
                if tcls == Code.CodeTermJump then for _, v in ipairs(term.args or {}) do add_value(v) end
                elseif tcls == Code.CodeTermBranch then add_value(term.cond); for _, v in ipairs(term.then_args or {}) do add_value(v) end; for _, v in ipairs(term.else_args or {}) do add_value(v) end
                elseif tcls == Code.CodeTermSwitch then add_value(term.value)
                elseif tcls == Code.CodeTermVariantSwitch then add_value(term.tag)
                elseif tcls == Code.CodeTermReturn then for _, v in ipairs(term.values or {}) do add_value(v) end end
            end
        end
        return idx
    end

    local function check_unique_ids(ctx, items, id_fn, site)
        local seen = {}
        for _, item in ipairs(items or {}) do
            local id = id_fn(item)
            if id ~= nil then
                if seen[id] then issue(ctx, "duplicate-id", site .. " duplicate id " .. id) end
                seen[id] = true
            end
        end
    end

    local function flow_loop_by_id(flow)
        local out = {}
        for _, loop in ipairs(flow and flow.loops or {}) do out[loop.id.text] = loop end
        return out
    end

    local function mem_access_by_id(memory)
        local out = {}
        for _, access in ipairs(memory and memory.accesses or {}) do out[access.id.text] = access end
        return out
    end

    local function check_value(ctx, code_idx, value, site)
        if value ~= nil and not code_idx.values[value.text] then issue(ctx, "missing-value", site .. " references missing value " .. value.text) end
    end

    local function validate_flow(ctx, module, code_idx, flow)
        if flow == nil then issue(ctx, "missing-flow", "missing FlowFactSet"); return end
        if flow.module ~= module.id then issue(ctx, "module-mismatch", "FlowFactSet module does not match CodeModule") end
        check_unique_ids(ctx, flow.edges, function(e) return e.id.text end, "flow.edges")
        for _, edge in ipairs(flow.edges or {}) do
            if code_idx.funcs[edge.func.text] == nil then issue(ctx, "missing-func", "flow edge references missing func " .. edge.func.text) end
            if code_idx.blocks[edge.pred.text] == nil then issue(ctx, "missing-block", "flow edge pred missing " .. edge.pred.text) end
            if code_idx.blocks[edge.succ.text] == nil then issue(ctx, "missing-block", "flow edge succ missing " .. edge.succ.text) end
            for _, arg in ipairs(edge.args or {}) do check_value(ctx, code_idx, arg.src, "flow edge arg"); check_value(ctx, code_idx, arg.dst_param, "flow edge param") end
        end
        check_unique_ids(ctx, flow.loops, function(l) return l.id.text end, "flow.loops")
        for _, loop in ipairs(flow.loops or {}) do
            local src = loop.source
            if pvm.classof(src) == Flow.FlowLoopFromCode then
                if code_idx.funcs[src.func.text] == nil then issue(ctx, "missing-func", "loop source func missing " .. src.func.text) end
                if code_idx.blocks[src.header.text] == nil then issue(ctx, "missing-block", "loop header missing " .. src.header.text) end
                if code_idx.blocks[src.backedge.text] == nil then issue(ctx, "missing-block", "loop backedge missing " .. src.backedge.text) end
            end
            local body = {}
            for _, block in ipairs(loop.body_blocks or {}) do
                if body[block.text] then issue(ctx, "duplicate-block", "loop body duplicates block " .. block.text) end
                body[block.text] = true
                if code_idx.blocks[block.text] == nil then issue(ctx, "missing-block", "loop body missing block " .. block.text) end
            end
            for _, ind in ipairs(loop.inductions or {}) do
                check_value(ctx, code_idx, ind.value, "flow induction")
                check_value(ctx, code_idx, ind.init, "flow induction init")
                check_value(ctx, code_idx, ind.step, "flow induction step")
            end
            for _, exit in ipairs(loop.exits or {}) do
                if code_idx.blocks[exit.from.text] == nil then issue(ctx, "missing-block", "loop exit from missing " .. exit.from.text) end
                if code_idx.blocks[exit.to.text] == nil then issue(ctx, "missing-block", "loop exit to missing " .. exit.to.text) end
                check_value(ctx, code_idx, exit.condition, "loop exit condition")
            end
        end
    end

    local function validate_memory(ctx, module, code_idx, memory)
        if memory == nil then issue(ctx, "missing-memory", "missing MemFactSet"); return end
        if memory.module ~= module.id then issue(ctx, "module-mismatch", "MemFactSet module does not match CodeModule") end
        check_unique_ids(ctx, memory.accesses, function(a) return a.id.text end, "memory.accesses")
        for _, access in ipairs(memory.accesses or {}) do
            if code_idx.funcs[access.func.text] == nil then issue(ctx, "missing-func", "memory access func missing " .. access.func.text) end
            if code_idx.blocks[access.block.text] == nil then issue(ctx, "missing-block", "memory access block missing " .. access.block.text) end
            if access.inst == nil then issue(ctx, "missing-inst", "memory access lacks CodeInstId " .. access.id.text)
            else
                local expected_access = code_idx.access_by_inst[access.inst.text]
                if expected_access == nil then issue(ctx, "missing-inst", "memory access inst missing/not-memory " .. access.inst.text)
                elseif expected_access ~= access.access then issue(ctx, "access-contradiction", "MemAccessFact access does not match CodeMemoryAccess for " .. access.inst.text) end
                local expected_kind = code_idx.kind_by_inst[access.inst.text]
                if expected_kind ~= nil and expected_kind ~= access.kind then issue(ctx, "access-contradiction", "MemAccessFact kind does not match instruction for " .. access.inst.text) end
                local expected_place = code_idx.place_by_inst[access.inst.text]
                if expected_place ~= nil and expected_place ~= access.place then issue(ctx, "access-contradiction", "MemAccessFact place does not match instruction for " .. access.inst.text) end
            end
            if access.access.volatile and access.trap == Mem.MemNonTrapping then
                -- This is legal; volatility is carried by CodeMemoryAccess. Keep this branch explicit for auditability.
            end
        end
        local access_by_id = mem_access_by_id(memory)
        for _, alias in ipairs(memory.aliases or {}) do
            if alias.a ~= nil and access_by_id[alias.a.text] == nil then issue(ctx, "missing-access", "alias fact missing access " .. alias.a.text) end
            if alias.b ~= nil and access_by_id[alias.b.text] == nil then issue(ctx, "missing-access", "alias fact missing access " .. alias.b.text) end
            if alias.access ~= nil and access_by_id[alias.access.text] == nil then issue(ctx, "missing-access", "alias scope missing access " .. alias.access.text) end
        end
        for _, dep in ipairs(memory.dependences or {}) do
            if dep.before ~= nil and access_by_id[dep.before.text] == nil then issue(ctx, "missing-access", "dependence before missing " .. dep.before.text) end
            if dep.after ~= nil and access_by_id[dep.after.text] == nil then issue(ctx, "missing-access", "dependence after missing " .. dep.after.text) end
        end
    end

    local function stream_access_ids(streams)
        local out = {}
        for _, stream in ipairs(streams or {}) do for _, id in ipairs(stream.accesses or {}) do out[id.text] = stream end end
        return out
    end

    local function validate_kernel(ctx, module, code_idx, flow, memory, plan)
        if plan == nil then issue(ctx, "missing-kernel", "missing KernelModulePlan"); return end
        if plan.module ~= module.id then issue(ctx, "module-mismatch", "KernelModulePlan module does not match CodeModule") end
        if flow ~= nil and plan.flow ~= flow then issue(ctx, "flow-mismatch", "KernelModulePlan does not reference supplied FlowFactSet") end
        if memory ~= nil and plan.memory ~= memory then issue(ctx, "memory-mismatch", "KernelModulePlan does not reference supplied MemFactSet") end
        if plan.flow_semantics ~= nil and plan.flow_semantics.module ~= module.id then issue(ctx, "module-mismatch", "KernelModulePlan FlowSemanticFactSet module does not match CodeModule") end
        if plan.memory_semantics ~= nil and plan.memory_semantics.module ~= module.id then issue(ctx, "module-mismatch", "KernelModulePlan MemSemanticFactSet module does not match CodeModule") end
        local accesses = mem_access_by_id(memory)
        local normalized_nontrap = {}
        for _, safety in ipairs(plan.memory_semantics and plan.memory_semantics.safety or {}) do
            if pvm.classof(safety) == Mem.MemAccessNonTrap then normalized_nontrap[safety.access.text] = true end
        end
        for _, func_plan in ipairs(plan.funcs or {}) do
            if code_idx.funcs[func_plan.func.text] == nil then issue(ctx, "missing-func", "kernel func plan missing func " .. func_plan.func.text) end
            local kp = func_plan.plan
            if kp == nil then
                issue(ctx, "missing-plan", "kernel func plan lacks plan for " .. func_plan.func.text)
            else
                local subject = kp.subject
                if subject == nil then issue(ctx, "missing-subject", "kernel plan lacks subject")
                elseif subject.func ~= func_plan.func then issue(ctx, "func-mismatch", "kernel plan subject func does not match KernelFuncPlan " .. func_plan.func.text) end
                local cls = pvm.classof(kp)
                if cls == Kernel.KernelNoPlan then
                    if #(kp.rejects or {}) == 0 then issue(ctx, "missing-rejection", "KernelNoPlan must carry explicit rejection facts") end
                elseif cls == Kernel.KernelPlanned then
                    local body = kp.body
                    if body == nil or pvm.classof(body) ~= Kernel.KernelBodyCounted then issue(ctx, "missing-body", "KernelPlanned must carry a counted kernel body") end
                    local streams = body and body.streams or {}
                    local by_access = stream_access_ids(streams)
                    for id in pairs(by_access) do if accesses[id] == nil then issue(ctx, "missing-access", "kernel stream references missing memory access " .. id) end end
                    for id in pairs(by_access) do
                        local access = accesses[id]
                        if access ~= nil then
                            if subject ~= nil and access.func ~= subject.func then issue(ctx, "func-mismatch", "kernel stream access belongs to different func " .. id) end
                            if access.access.volatile then issue(ctx, "unsafe-plan", "planned kernel includes volatile access " .. id) end
                            local atomic = access.kind == Mem.MemAtomicLoad or access.kind == Mem.MemAtomicStore or access.kind == Mem.MemAtomicRmw or access.kind == Mem.MemAtomicCas
                            if atomic then issue(ctx, "unsafe-plan", "planned kernel includes atomic access " .. id) end
                            if body ~= nil and access.trap == Mem.MemMayTrap and pvm.classof(body.safety) == Kernel.KernelSafetyProven and not normalized_nontrap[id] then
                                issue(ctx, "unsafe-plan", "proven kernel includes may-trap access without normalized nontrap proof " .. id)
                            end
                        end
                    end
                else
                    issue(ctx, "unknown-plan", "unknown kernel plan variant " .. class_name(kp))
                end
            end
        end
    end

    local function validate(module, flow, memory, kernel, opts)
        opts = opts or {}
        local ctx = { issues = {}, collector = opts.collector }
        local code_idx = index_code(module)
        validate_flow(ctx, module, code_idx, flow)
        validate_memory(ctx, module, code_idx, memory)
        validate_kernel(ctx, module, code_idx, flow, memory, kernel)
        return ctx
    end

    api.validate = validate

    T._moonlift_api_cache.kernel_validate = api
    return api
end

return M
