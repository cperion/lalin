-- lua_sem_validate.lua -- semantic-layer invariants.

local Validate = require("lua_compile.validate")
local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()

local M = {}

function M.validate(result)
  local ok, errors = Validate.lua_sem_result(result)
  if ok and pvm.classof(result) == T.LuaSem.Accepted then
    for i, eff in ipairs(result.program.effects or {}) do
      if not T.LuaSem.Effect.members[pvm.classof(eff)] then errors[#errors + 1] = "effect " .. i .. " is not LuaSem.Effect" end
    end
  end
  return #errors == 0, errors
end

return M
