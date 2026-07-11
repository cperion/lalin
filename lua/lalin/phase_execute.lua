-- Typed LalinPhase plan execution.

local llbl = require("llbl")
local asdl = require("lalin.asdl")

local M = {}
local Executor = {}
Executor.__index = Executor

local function append(values, value)
    local out = {}
    for i = 1, #values do out[i] = values[i] end
    out[#out + 1] = value
    return out
end

local function install_methods(T)
    local P = T.LalinPhase

    function P.ImplLua:machine_implementation_capability() return P.MachineImplementationCapability(self) end
    function P.ImplLalin:machine_implementation_capability() return P.MachineImplementationCapability(self) end
    function P.ImplC:machine_implementation_capability() return P.MachineImplementationCapability(self) end
    function P.ImplExternal:machine_implementation_capability() return P.MachineImplementationCapability(self) end

    local function resolve_implementation(implementation, executor)
        return executor:resolve(implementation:machine_implementation_capability())
    end

    function P.ImplLua:resolve_machine_implementation(executor) return resolve_implementation(self, executor) end
    function P.ImplLalin:resolve_machine_implementation(executor) return resolve_implementation(self, executor) end
    function P.ImplC:resolve_machine_implementation(executor) return resolve_implementation(self, executor) end
    function P.ImplExternal:resolve_machine_implementation(executor) return resolve_implementation(self, executor) end

    function P.MachineImplementationAvailable:execute_machine(executor, request)
        return executor:invoke(self.capability, request)
    end

    function P.MachineImplementationUnavailable:execute_machine(_, request)
        return P.PhaseMachineExecutionFailed(P.PhaseDiagnosticMachineUnavailable(
            request.step, self.capability.implementation, self.reason
        ))
    end

    function P.PhaseMachineExecutionSucceeded:advance_execution(progress, step)
        local report = P.PhaseExecutionStepReport(step, progress.current, self)
        return P.PhaseExecutionContinuing(
            self.output, append(progress.steps, report), progress.diagnostics,
            append(progress.run_steps, P.PhaseRunStep(step.index, step.phase, step.machine, P.PhaseRunStepCompleted))
        )
    end

    function P.PhaseMachineExecutionFailed:advance_execution(progress, step)
        local report = P.PhaseExecutionStepReport(step, progress.current, self)
        return P.PhaseExecutionStopped(
            progress.current, append(progress.steps, report), append(progress.diagnostics, self.diagnostic),
            append(progress.run_steps, P.PhaseRunStep(step.index, step.phase, step.machine, P.PhaseRunStepFailed))
        )
    end

    local function run_artifact(request, status, events, steps)
        return P.PhaseRunArtifact(P.PhaseRunTaskId(request.plan.root.text), status, events, steps)
    end

    function P.PhaseExecutionContinuing:execute_remaining(executor, request, index, ctx, run_events)
        if index > #request.plan.steps then
            local event = P.PhaseRunExecuteSucceeded(#run_events + 1)
            run_events[#run_events + 1] = event
            ctx:event("execute_done", event)
            return P.PhaseExecutionSucceeded(
                request, self.current, self.steps, self.diagnostics,
                run_artifact(request, P.PhaseRunSucceeded, run_events, self.run_steps)
            )
        end

        local step = request.plan.steps[index]

        local started = P.PhaseRunStepStarted(#run_events + 1, step.index, step.phase, step.machine)
        run_events[#run_events + 1] = started
        local machine_request = P.PhaseMachineExecutionRequest(step, self.current, request.stage)
        ctx:event("step_start", machine_request)
        local result = step.impl:resolve_machine_implementation(executor):execute_machine(executor, machine_request)
        local finished = P.PhaseRunStepFinished(#run_events + 1, step.index, step.phase, step.machine)
        run_events[#run_events + 1] = finished
        ctx:event("step_done", result)
        return result:advance_execution(self, step):execute_remaining(executor, request, index + 1, ctx, run_events)
    end

    function P.PhaseExecutionStopped:execute_remaining(_, request, _, ctx, run_events)
        local event = P.PhaseRunExecuteFailed(#run_events + 1)
        run_events[#run_events + 1] = event
        ctx:event("execute_done", event)
        return P.PhaseExecutionFailed(
            request, self.current, self.steps, self.diagnostics,
            run_artifact(request, P.PhaseRunFailed, run_events, self.run_steps)
        )
    end

    function P.PhaseExecutionSucceeded:require_output() return self.output end
    function P.PhaseExecutionFailed:require_output()
        local messages = {}
        for i = 1, #self.diagnostics do messages[i] = self.diagnostics[i]:diagnostic_text() end
        error(table.concat(messages, "\n"), 2)
    end

    function P.PhaseDiagnosticMachineUnavailable:diagnostic_text()
        return "machine " .. self.step.machine.text .. " unavailable: " .. self.reason
    end
    function P.PhaseDiagnosticMachineFailed:diagnostic_text()
        return "machine " .. self.step.machine.text .. " failed: " .. self.message
    end

    function P.PhaseValueTreeModule:compiler_value() return self.module end
    function P.PhaseValueCheckedModule:compiler_value() return self.checked end
    function P.PhaseValueCompilerCode:compiler_value() return self.code end
    function P.PhaseValueCBackend:compiler_value() return self.result.unit end
    function P.PhaseValueNumber:compiler_value() return self.value end
end

function M.registry(T)
    if T ~= nil then install_methods(T) end
    return setmetatable({ bindings = {}, context = T }, Executor)
end

function Executor:register(capability, fn)
    if type(fn) ~= "function" then error("phase_execute: capability binding must be a function", 2) end
    local T = asdl.context_of(capability)
    if self.context == nil then self.context = T; install_methods(T) end
    self.bindings[capability.implementation] = fn
    return self
end

function Executor:resolve(capability)
    if self.bindings[capability.implementation] ~= nil then
        return self.context.LalinPhase.MachineImplementationAvailable(capability)
    end
    return self.context.LalinPhase.MachineImplementationUnavailable(capability, "no registered typed capability")
end

function Executor:invoke(capability, request)
    local P = self.context.LalinPhase
    local ok, output = pcall(self.bindings[capability.implementation], request)
    if ok then return P.PhaseMachineExecutionSucceeded(output) end
    return P.PhaseMachineExecutionFailed(P.PhaseDiagnosticMachineFailed(
        request.step, capability.implementation, tostring(output)
    ))
end

local function collecting_context(ctx, events)
    return {
        event = function(_, kind, payload)
            local event = ctx:make_event(kind, payload)
            events[#events + 1] = event
            return event
        end,
    }
end

local function materialized_event_region(ctx, fn)
    local function gen(param, state)
        if state == nil then
            local events = {}
            local report = param.fn(collecting_context(param.ctx, events))
            events[#events + 1] = param.ctx:make_event("result", { result = report })
            state = { events = events, index = 1 }
        end
        local event = state.events[state.index]
        if event == nil then return nil end
        state.index = state.index + 1
        return state, event
    end
    return gen, { ctx = ctx, fn = fn }, nil
end

local function execute_request(ctx, executor, request)
    local P = executor.context.LalinPhase
    local run_events = { P.PhaseRunExecuteStarted(1) }
    ctx:event("execute_start", request)
    return P.PhaseExecutionContinuing(request.input, {}, {}, {}):execute_remaining(
        executor, request, 1, ctx, run_events
    )
end

local function phase_execute_process_body(ctx, executor, request)
    return materialized_event_region(ctx, function(event_ctx)
        return execute_request(event_ctx, executor, request)
    end)
end

M.process = llbl.process.phase_execute { "executor", "request" } (phase_execute_process_body)

function Executor:run(request)
    local handle = M.process:start(self, request)
    for _ in handle:events() do end
    return handle:result()
end

function Executor:process(request) return M.process:start(self, request) end
function M.execute(request, executor) return executor:run(request) end

return M
