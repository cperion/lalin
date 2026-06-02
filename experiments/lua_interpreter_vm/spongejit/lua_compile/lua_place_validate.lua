-- lua_place_validate.lua -- non-semantic placement invariants.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local M = {}
function M.validate(plan)
  if pvm.classof(plan) ~= T.LuaPlace.Plan then return false, { "expected LuaPlace.Plan" } end
  return true, {}
end
return M
