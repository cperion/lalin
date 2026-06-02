-- lua_nf_validate.lua -- normal-form invariants.

local Validate = require("lua_compile.validate")
local M = {}
function M.validate(nf) return Validate.lua_nf_program(nf) end
return M
