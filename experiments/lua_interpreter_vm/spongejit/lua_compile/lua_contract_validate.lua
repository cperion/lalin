-- lua_contract_validate.lua -- contract invariants.

local Validate = require("lua_compile.validate")
local M = {}
function M.validate(contract) return Validate.lua_contract(contract) end
return M
