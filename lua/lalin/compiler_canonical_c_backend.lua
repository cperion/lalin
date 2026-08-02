local function bind_context(T)
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)
    local KernelValidate = require("lalin.kernel_validate")(T)
    local CodeLowerPlan = require("lalin.code_lower_plan")(T)
    local CodeType = require("lalin.code_type")(T)
    local LowerToC = require("lalin.lower_to_c")(T)
    local CValidate = require("lalin.emit_c_validate")(T)
    local Errors = require("lalin.error")
    local api = {}

    function api.code_result_to_c(code_result, opts)
        opts = opts or {}
        local collector = opts.collector or Errors.ThrowingCollector(
            Errors.SpanResolvers.RESOLVERS, opts.analysis_ctx or {}, Errors.Catalog, Errors.Terminal.render
        )
        local c_target = CodeType.default_target(opts.c_target or opts)
        local c_opts = {}
        for k, v in pairs(opts.c_opts or {}) do c_opts[k] = v end
        for k, v in pairs(opts) do if c_opts[k] == nil then c_opts[k] = v end end
        c_opts.target, c_opts.c_target, c_opts.layout_env = c_target, c_target, code_result.layout_env
        local code_module, contracts = code_result.module, code_result.contracts
        local graph = CodeGraph.graph(code_module)
        local flow = CodeFlowFacts.facts(code_module, graph)
        local flow_semantics = CodeFlowFacts.semantic_facts(code_module, graph, flow)
        local values = CodeValueFacts.facts(code_module, graph, flow)
        local mem_semantics = CodeMemFacts.semantic_facts(code_module, graph, flow, values, contracts)
        local mem = CodeMemFacts.facts(code_module, graph, flow, values, contracts)
        local effects = CodeEffectFacts.facts(code_module, graph, mem_semantics, contracts)
        local kernels = CodeKernelPlan.plan(code_module, graph, flow, values, mem_semantics, effects)
        local schedules = CodeSchedulePlan.plan(code_module, kernels, flow, values, mem_semantics, effects, opts.target_model or opts.backend_target_model)
        local lower_plan = CodeLowerPlan.plan(code_module, graph, kernels, schedules, T.LalinLower.LowerTargetC)
        KernelValidate.validate(code_module, graph, flow, values, mem_semantics, effects, kernels, schedules, lower_plan, { collector = collector })
        c_opts.validate = false
        local c_unit = LowerToC.module(code_module, lower_plan, c_opts)
        return T.LalinCompiler.CompilerCBackendEmitted(
            T.LalinCompiler.CompilerCBackendResult(
                c_unit, CValidate.validate(c_unit, collector)))
    end

    return api
end

return bind_context
