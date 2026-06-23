-- MoonSchema runtime projection facade.
--
-- This defines the runtime class context from canonical MoonSchema Lua modules.
-- The internal projection value vocabulary is still MoonAsdl, but users enter
-- through MoonSchema and this projection facade, not through an ASDL source API.

local Schema = require("moonlift.schema")

local M = {}

function M.schema(T)
    return Schema.schema(T)
end

function M.Define(T)
    return Schema.Define(T)
end

return M
