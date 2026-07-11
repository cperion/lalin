-- Hosted machine implementations for lalin.compiler_package.

local asdl = require("lalin.asdl")

local M = {}

local function context_of(node)
    local cls = asdl.classof(node)
    local ctx = cls and asdl.context_of(cls)
    if ctx then return ctx end
    error("lalin.compiler_machines: input value does not carry a schema context", 3)
end

function M.typecheck_module(module)
    local T = context_of(module)
    return require("lalin.frontend_pipeline")(T).typecheck_module(module, {})
end

function M.checked_to_c_code(checked)
    local T = context_of(checked)
    return require("lalin.frontend_pipeline")(T).checked_to_code_result(checked, { root = "emit_c" })
end

function M.code_to_c(code_result)
    local T = context_of(code_result)
    local result = require("lalin.frontend_pipeline")(T).code_result_to_c(code_result, {})
    if #result.report.issues ~= 0 then
        local messages = {}
        for i = 1, #result.report.issues do messages[i] = tostring(result.report.issues[i]) end
        error("lalin compiler machine code_to_c validation failed: " .. table.concat(messages, "\n"), 2)
    end
    return result
end

function M.register_capabilities(executor, T)
    local P = T.LalinPhase
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "typecheck_module")), function(request)
        return P.PhaseValueCheckedModule(M.typecheck_module(request.input.module))
    end)
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "checked_to_c_code")), function(request)
        return P.PhaseValueCompilerCode(M.checked_to_c_code(request.input.checked))
    end)
    executor:register(P.MachineImplementationCapability(P.ImplLua("lalin.compiler_machines", "code_to_c")), function(request)
        return P.PhaseValueCBackend(M.code_to_c(request.input.code))
    end)
    return executor
end

return M
