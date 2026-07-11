-- Public Lalin compiler driver.
--
-- This is the public orchestration boundary: module AST -> compiler package ->
-- plan -> execute. The hosted frontend pipeline is just the implementation of
-- the current compiler machine, not the public entrypoint.

local asdl = require("lalin.asdl")
local CompilerPackage = require("lalin.compiler_package")
local PhasePlan = require("lalin.phase_plan")
local PhaseExecute = require("lalin.phase_execute")

local M = {}

function M.lower_module(module, opts)
    opts = opts or {}
    local T = opts.context or asdl.context_of(module)
    local package = CompilerPackage(T)
    local planned = PhasePlan.assert_plan(package, opts.root or "compile")
    local executor = opts.executor or PhaseExecute.registry(T)
    local CodeType = require("lalin.code_type")(T)
    local stage = T.LalinPhase.CompilerCStageInput(CodeType.default_target(opts.c_target or opts.target or {}))
    local request = T.LalinPhase.PhaseExecutionRequest(
        planned.plan, T.LalinPhase.PhaseValueTreeModule(module), stage
    )
    return executor:run(request):require_output():compiler_value()
end

return M
