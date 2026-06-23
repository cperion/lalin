-- Project tracking schema projection.

local S = require("moonlift.schema.dsl")

local M = {}

local function project_module()
    return require("moonlift.schema.project")
end

function M.schema(T)
    return S.to_asdl_schema(T, { project_module() })
end

function M.Define(T)
    if T.MoonProject ~= nil then return T end
    return S.define(T, { project_module() })
end

return M
