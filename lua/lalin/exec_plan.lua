local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.exec_plan ~= nil then return T._lalin_api_cache.exec_plan end

    local Exec = T.LalinExec
    local Kernel = T.LalinKernel
    local Stencil = T.LalinStencil
    local Flow = T.LalinFlow

    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)

    local api = {}

    function Kernel.KernelPlan:exec_kernel_plan_id() return nil end
    function Kernel.KernelPlanned:exec_kernel_plan_id() return self.id end

    function Stencil.StencilSelection:select_exec_stencil(input)
        return Exec.ExecSelectSkip(input.unselected_reason)
    end
    function Stencil.StencilSelected:select_exec_stencil(input)
        if input.artifact == nil then return Exec.ExecSelectSkip(input.missing_artifact_reason) end
        if input.func == nil then return Exec.ExecSelectSkip(input.missing_func_reason) end
        return Exec.ExecSelectStencil(input.selected_reason)
    end

    function Exec.ExecStencilSelection:add_exec_stencil(entries, by_func, entry, index, kernel_plan, loop_by_id, artifact, func_id)
        error("exec_plan: unsupported exec stencil selection", 2)
    end

    function Exec.ExecSelectStencil:add_exec_stencil(entries, by_func, entry, index, kernel_plan, loop_by_id, artifact, func_id)
        local blocks = kernel_plan.subject:exec_kernel_blocks(loop_by_id)
        local fragment = Exec.ExecFragment(
            Exec.ExecFragmentId("exec:" .. sanitize(func_id.text) .. ":stencil:" .. tostring(index)),
            func_id,
            blocks,
            Exec.ExecFragmentStencil(artifact, {}, Exec.ExecResultVoid)
        )
        entries[#entries + 1] = Exec.ExecPlanEntry(entry.kernel, Exec.ExecMaterializeStencil(fragment, self.reason))
        local list = by_func[func_id.text]
        if list == nil then list = {}; by_func[func_id.text] = list end
        list[#list + 1] = fragment
    end

    function Exec.ExecSelectSkip:add_exec_stencil(entries, by_func, entry, index, kernel_plan, loop_by_id, artifact, func_id)
        entries[#entries + 1] = Exec.ExecPlanEntry(entry.kernel, Exec.ExecSkipStencil(self.reason))
    end

    local function block_ids(func)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do out[#out + 1] = block.id end
        return out
    end

    local function func_fragment_id(func, suffix)
        return Exec.ExecFragmentId("exec:" .. sanitize(func.id.text) .. ":" .. suffix)
    end

    local function scalar_func_fragment(func)
        local blocks = block_ids(func)
        return Exec.ExecFragment(
            func_fragment_id(func, "blocks"),
            func.id,
            blocks,
            Exec.ExecFragmentScalarBlocks(blocks)
        )
    end

    local function artifact_index(artifacts)
        local out = {}
        for _, artifact in ipairs(artifacts or {}) do
            if artifact.instance ~= nil and artifact.instance.id ~= nil then out[artifact.instance.id.text] = artifact end
        end
        return out
    end

    local function graph_loop_indexes(graph)
        local loop_to_func, loop_by_id = {}, {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do
                loop_to_func[loop.id.text] = fg.func
                loop_by_id[loop.id.text] = loop
            end
        end
        return loop_to_func, loop_by_id
    end

    local function append_unique_block(out, seen, id)
        if id ~= nil and not seen[id.text] then
            seen[id.text] = true
            out[#out + 1] = id
        end
    end

    -- FlowDomain leaf methods: exec_domain_func_id / exec_domain_blocks
    function Flow.FlowDomainFunction:exec_domain_func_id(loop_to_func)
        return self.func
    end
    function Flow.FlowDomainBlockRange:exec_domain_func_id(loop_to_func)
        return self.func
    end
    function Flow.FlowDomainLoop:exec_domain_func_id(loop_to_func)
        return loop_to_func[self.loop.text]
    end

    function Flow.FlowDomainFunction:exec_domain_blocks(loop_by_id)
        return {}
    end
    function Flow.FlowDomainBlockRange:exec_domain_blocks(loop_by_id)
        return { self.entry, self.exit }
    end
    function Flow.FlowDomainLoop:exec_domain_blocks(loop_by_id)
        local loop = loop_by_id[self.loop.text]
        local out, seen = {}, {}
        append_unique_block(out, seen, loop and loop.header and loop.header.block)
        for _, block in ipairs(loop and loop.body or {}) do append_unique_block(out, seen, block.block) end
        return out
    end

    -- KernelSubject leaf methods: exec_kernel_func_id / exec_kernel_blocks
    function Kernel.KernelSubjectFunction:exec_kernel_func_id(loop_to_func)
        return self.func
    end
    function Kernel.KernelSubjectFragment:exec_kernel_func_id(loop_to_func)
        return self.func
    end
    function Kernel.KernelSubjectLoop:exec_kernel_func_id(loop_to_func)
        return loop_to_func[self.loop.text]
    end
    function Kernel.KernelSubjectDomain:exec_kernel_func_id(loop_to_func)
        return self.domain:exec_domain_func_id(loop_to_func)
    end

    function Kernel.KernelSubjectFunction:exec_kernel_blocks(loop_by_id)
        return {}
    end
    function Kernel.KernelSubjectFragment:exec_kernel_blocks(loop_by_id)
        return { self.entry, self.exit }
    end
    function Kernel.KernelSubjectLoop:exec_kernel_blocks(loop_by_id)
        return Flow.FlowDomainLoop(self.loop):exec_domain_blocks(loop_by_id)
    end
    function Kernel.KernelSubjectDomain:exec_kernel_blocks(loop_by_id)
        return self.domain:exec_domain_blocks(loop_by_id)
    end




    local function kernel_plan_index(kernels)
        local out = {}
        for _, plan in ipairs(kernels and kernels.plans or {}) do
            local id = plan:exec_kernel_plan_id()
            if id ~= nil then out[id.text] = plan end
        end
        return out
    end

    local function stencil_decisions(graph, kernels, stencil_plan, artifacts)
        local entries, by_func = {}, {}
        local by_instance = artifact_index(artifacts)
        local loop_to_func, loop_by_id = graph_loop_indexes(graph)
        local by_kernel = kernel_plan_index(kernels)
        for i, entry in ipairs(stencil_plan and stencil_plan.selections or {}) do
            local selection = entry.selection
            local artifact = selection:exec_plan_artifact(by_instance)
            local kernel_plan = by_kernel[entry.kernel.text]
            local func_id = kernel_plan and kernel_plan.subject and kernel_plan.subject:exec_kernel_func_id(loop_to_func)
            local exec_selection = selection:select_exec_stencil(Exec.ExecStencilInput(
                artifact,
                func_id,
                "selected stencil artifact has executable function owner",
                "stencil plan entry did not select an artifact",
                selection:exec_plan_missing_artifact_reason(),
                "selected stencil kernel has no owning Code function"
            ))
            exec_selection:add_exec_stencil(entries, by_func, entry, i, kernel_plan, loop_by_id, artifact, func_id)
        end
        return entries, by_func
    end

    function Stencil.StencilSelection:exec_plan_artifact(by_instance) return nil end
    function Stencil.StencilSelected:exec_plan_artifact(by_instance)
        return by_instance[self.instance.id.text]
    end
    function Stencil.StencilSelection:exec_plan_missing_artifact_reason()
        return "selected stencil instance has no artifact"
    end
    function Stencil.StencilSelected:exec_plan_missing_artifact_reason()
        return "selected stencil instance has no artifact " .. self.instance.id.text
    end

    local function default_stencil_plan(module, kernels)
        return Stencil.StencilModulePlan(module.id, kernels, {})
    end

    local function plan(module, opts)
        opts = opts or {}
        local graph = opts.graph or CodeGraph.graph(module)
        local flow = opts.flow or CodeFlowFacts.facts(module, graph)
        local value = opts.value or CodeValueFacts.facts(module, graph, flow)
        local mem = opts.mem or CodeMemFacts.semantic_facts(module, graph, flow, value, opts.contracts)
        local effect = opts.effect or CodeEffectFacts.facts(module, graph, mem, opts.contracts)
        local kernels = opts.kernels or CodeKernelPlan.plan(module, graph, flow, value, mem, effect)
        local stencil_plan = opts.stencil or default_stencil_plan(module, kernels)
        local entries, stencil_by_func = stencil_decisions(graph, kernels, stencil_plan, opts.artifacts)

        local funcs = {}
        for _, func in ipairs(module.funcs or {}) do
            local fragments = {}
            for _, fragment in ipairs(stencil_by_func[func.id.text] or {}) do fragments[#fragments + 1] = fragment end
            fragments[#fragments + 1] = scalar_func_fragment(func)
            funcs[#funcs + 1] = Exec.ExecFuncPlan(func.id, fragments)
        end

        return Exec.ExecModulePlan(module.id, stencil_plan, entries, funcs)
    end

    api.plan = plan
    api.module = plan

    T._lalin_api_cache.exec_plan = api
    return api
end

return bind_context
