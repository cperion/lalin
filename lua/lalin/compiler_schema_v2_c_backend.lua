local M = {}

function M.code_result_to_c(code_result, opts)
    opts = opts or {}
    require("lalin.impl.code_graph")
    require("lalin.impl.code_flow")
    require("lalin.impl.code_value")
    require("lalin.impl.code_mem")
    require("lalin.impl.code_effect")
    require("lalin.impl.kernel_plan")
    require("lalin.impl.schedule_plan")
    require("lalin.impl.lower_plan")
    require("lalin.impl.lower_emit_c")

    local Lower = require("lalin.schema_v2.lower")
    local module = code_result.module
    local graph = module:build_graph()
    local flow = graph:compute_flow(module)
    local values = graph:compute_values(module, flow)
    local mem = graph:compute_mem(module, flow, values, code_result.contracts)
    local effects = graph:compute_effects(module, mem, code_result.contracts)
    local kernels = mem:plan_kernels(flow, values, mem, effects)
    local schedules = kernels:plan_schedules(module, flow, values, mem, effects, opts.target_model or opts.backend_target_model)
    local lower_plan = module:plan_lowering(graph, kernels, schedules, Lower.LowerTargetC)
    local unit = lower_plan:emit_c(module)
    local validation = require("lalin.impl.lower_emit_c.validate").validate(unit)
    return require("lalin.schema_v2.compiler").CompilerCBackendResult(unit, validation)
end

return M
