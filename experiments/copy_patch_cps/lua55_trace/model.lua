local function product(name, fields)
    local class = { name = name }
    class.__index = class
    function class:is(value) return getmetatable(value) == self end
    return setmetatable(class, {
        __call = function(_, ...)
            local values = { ... }
            assert(#values == #fields, name .. " constructor arity changed")
            local instance = {}
            for index = 1, #fields do instance[fields[index]] = values[index] end
            return setmetatable(instance, class)
        end,
    })
end

local M = {}

M.RegisterIdentity = product("RegisterIdentity", { "index" })
M.InstructionIdentity = product("InstructionIdentity", { "pc" })

M.IntegerAddForLoopPlan = product("IntegerAddForLoopPlan", {
    "register_count", "forprep", "body", "companion", "forloop",
    "sum", "index", "limit", "step", "exit_pc",
})
M.PlanTraceProjection = product("PlanTraceProjection", { "plan", "code_size" })

M.UnsupportedInstruction = product("UnsupportedInstruction", { "identity" })

M.TraceRecorded = product("TraceRecorded", { "projection" })
M.TraceRecordingRejected = product("TraceRecordingRejected", { "failure" })
M.TraceLoopCompleted = product("TraceLoopCompleted", { "exit_pc" })

return M
