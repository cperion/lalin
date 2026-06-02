-- lua_place_projection_plan.lua -- projection realization hints.

local B = require("lua_compile.builders")
local Place = B.T.LuaPlace
local M = {}
function M.already_synced(slot) return Place.AlreadySynced(type(slot) == "table" and slot or B.LuaSem.SlotClass(slot)) end
return M
