-- Hosted machine implementations for lalin.compiler_package.

local M = {}

function M.typecheck_module(stage, module)
    return stage:typecheck_compiler_module(module)
end

function M.checked_to_c_code(stage, checked)
    return stage:lower_checked_compiler_module(checked)
end

function M.code_to_c(stage, code_result)
    return stage:lower_compiler_code_to_c(code_result)
end

function M.install_stage_methods(T)
    local P = T.LalinPhase
    function P.CompilerCStageInput:typecheck_compiler_module(module)
        return require("lalin.frontend_pipeline")(T).typecheck_module(module, { target = self.target })
    end
    function P.CompilerCStageInput:lower_checked_compiler_module(checked)
        return require("lalin.frontend_pipeline")(T).checked_to_code_result(checked, { root = "emit_c", target = self.target })
    end
    function P.CompilerCStageInput:lower_compiler_code_to_c(code_result)
        return require("lalin.frontend_pipeline")(T).code_result_to_c(code_result, { target = self.target })
    end
end

function M.register_capabilities(executor, T)
    M.install_stage_methods(T)
    local P = T.LalinPhase
    local Compiler = T.LalinCompiler
    function Compiler.CompilerCBackendEmitted:phase_execution_value()
        local issues = self.backend.report.issues
        if #issues ~= 0 then
            local messages = {}
            for i = 1, #issues do messages[i] = tostring(issues[i]) end
            error("C backend validation failed: " .. table.concat(messages, "; "), 2)
        end
        return P.PhaseValueCBackend(self)
    end
    function Compiler.CompilerCBackendRejected:phase_execution_value()
        local issues = {}
        for i = 1, #self.issues do issues[i] = tostring(self.issues[i]) end
        error("C backend rejected with " .. #issues
            .. " issue(s): " .. table.concat(issues, "; "), 2)
    end
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "typecheck_module")), function(request)
        return P.PhaseValueCheckedModule(M.typecheck_module(request.stage, request.input.module))
    end)
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "checked_to_c_code")), function(request)
        return P.PhaseValueCompilerCode(M.checked_to_c_code(request.stage, request.input.checked))
    end)
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "code_to_c")), function(request)
        return M.code_to_c(request.stage, request.input.code):phase_execution_value()
    end)
    return executor
end

return M
