-- Canonical compiler phase/wiring model, authored as MoonSchema data.

local S = require("moonlift.schema.dsl")

local M = {}

local function phase_module()
    return require("moonlift.schema.phase")
end

function M.schema(T)
    return S.to_asdl_schema(T, { phase_module() })
end

function M.Define(T)
    if T.MoonPhase ~= nil then return T end
    return S.define(T, { phase_module() })
end

return M
