-- Hosted machine implementations for lalin.compiler_package.


function M.typecheck_module(stage, module)
    return stage:typecheck_compiler_module(module)
end

function M.checked_to_c_code(stage, checked)
    return stage:lower_checked_compiler_module(checked)
end

function M.code_to_c(stage, code_result)
    local result = stage:lower_compiler_code_to_c(code_result)
    if #result.report.issues ~= 0 then
        local messages = {}
        for i = 1, #result.report.issues do messages[i] = tostring(result.report.issues[i]) end
        error("lalin compiler machine code_to_c validation failed: " .. table.concat(messages, "\n"), 2)
    end
    return result
end

function M.register_capabilities(executor, T)
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
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "typecheck_module")), function(request)
        return P.PhaseValueCheckedModule(M.typecheck_module(request.stage, request.input.module))
    end)
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "checked_to_c_code")), function(request)
        return P.PhaseValueCompilerCode(M.checked_to_c_code(request.stage, request.input.checked))
    end)
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "code_to_c")), function(request)
        return P.PhaseValueCBackend(M.code_to_c(request.stage, request.input.code))
    end)
    return executor
end

return M
