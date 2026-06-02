-- lua_compile_validate.lua -- whole-pipeline invariants.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()
local M = {}

function M.validate_result(result)
  if not T.LuaCompile.Result.members[pvm.classof(result)] then return false, { "expected LuaCompile.Result" } end
  return true, {}
end

return M
