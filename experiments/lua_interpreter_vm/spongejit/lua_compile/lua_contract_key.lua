-- lua_contract_key.lua -- contract identity paired with LuaNF key.

local NFKey = require("lua_compile.lua_nf_key")
local M = {}
function M.key(contract) return NFKey.key(contract) end
return M
