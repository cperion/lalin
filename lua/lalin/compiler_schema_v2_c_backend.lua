local M = {}
local Lower = require("lalin.schema_v2.lower")
local Compiler = require("lalin.schema_v2.compiler")
local Cemit = require("lalin.schema_v2.cemit")

function Lower.LowerCModuleEmitted:compiler_c_backend_result(input)
    local unit = self.emission.unit
    local validation = require("lalin.impl.lower_emit_c.validate").validate(unit)
    local backend = Compiler.CompilerCBackendResult(unit, validation)
    local signatures = {}
    for i = 1, #unit.sigs do
        signatures[i] = Cemit.CEmitCSigEntry(unit.sigs[i].id.text, unit.sigs[i])
    end
    return Compiler.CompilerCBackendEmitted(backend,
        Cemit.CEmitMachine(input.spine, signatures, unit.sigs, {}, {}))
end

function Lower.LowerCModuleRejected:compiler_c_backend_result(_input)
    return Compiler.CompilerCBackendRejected(self.issues)
end

function Compiler.CompilerCBackendEmitted:public_c_backend_result()
    return self.backend
end
function Compiler.CompilerCBackendRejected:public_c_backend_result()
    local issues = {}
    for i = 1, #self.issues do issues[i] = tostring(self.issues[i]) end
    error("typed canonical C lowering rejected with " .. #issues
        .. " issue(s): " .. table.concat(issues, "; "), 2)
end

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

    local module = code_result.module
    local graph = module:build_graph()
    local flow = graph:compute_flow(module)
    local values = graph:compute_values(module, flow)
    local mem = graph:compute_mem(module, flow, values, code_result.contracts)
    local effects = graph:compute_effects(module, mem, code_result.contracts)
    local kernels = mem:plan_kernels(module, graph, flow, values, effects)
    local schedules = kernels:plan_schedules(module, flow, values, mem, effects)
    local semantics = flow:compute_semantic_flow(module, graph)
    local prepared = Lower.LowerKernelCMatPreparationInput(
      module, graph, kernels, schedules, semantics, request.compiler)
:lower_prepare_cmat()
    local lower_plan = module:plan_lowering(
      graph, kernels, schedules, Lower.LowerTargetC)
    local spine = Lower.LowerBackSpine(module, graph, target)
    return prepared:lower_c_prepared_module(
      Lower.LowerCPreparedModuleInput(spine, lower_plan))
:compiler_c_backend_result(Compiler.CompilerCBackendEmissionInput(spine))
end

return M
