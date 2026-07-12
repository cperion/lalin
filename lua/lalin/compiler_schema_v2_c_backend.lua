local M = {}

function M.code_result_to_c(request)
    local code_result = request.result
    local target = request.target
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
    local Compiler = require("lalin.schema_v2.compiler")
    local module = code_result.module
    local graph = module:build_graph()
    local flow = graph:compute_flow(module)
    local values = graph:compute_values(module, flow)
    local mem = graph:compute_mem(module, flow, values, code_result.contracts)
    local effects = graph:compute_effects(module, mem, code_result.contracts)
    local kernels = mem:plan_kernels(module, graph, flow, values, effects)
    local schedules = kernels:plan_schedules(module, flow, values, mem, effects)
    local lower_plan = module:plan_lowering(graph, kernels, schedules, Lower.LowerTargetC)
    local spine = Lower.LowerBackSpine(module, graph, target)
    local emission = lower_plan:lower_c_module(Lower.LowerCModuleInput(spine, lower_plan))
    local unit = emission.unit
    local validation = require("lalin.impl.lower_emit_c.validate").validate(unit)
    return Compiler.CompilerCBackendResult(unit, validation)
end

return M
