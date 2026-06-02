-- lua_nf_to_lua_place_plan.lua -- optional LuaNF -> LuaPlace planning boundary.
--
-- Placement is not semantic identity. The default scaffold deliberately returns
-- an empty plan so semantic phases cannot depend on physical locations.

local B = require("lua_compile.builders")
local Place = B.T.LuaPlace
local M = {}
function M.plan(_nf) return Place.Plan({}, {}) end
return M
