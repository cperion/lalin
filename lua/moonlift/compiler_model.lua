-- Canonical compiler-world model used by MoonPhase compiler packages.

local Schema = require("moonlift.schema")

local M = {}

function M.schema(T)
    return Schema.schema(T)
end

function M.Define(T)
    if T.MoonCompiler ~= nil then return T end
    return Schema.Define(T)
end

return M
