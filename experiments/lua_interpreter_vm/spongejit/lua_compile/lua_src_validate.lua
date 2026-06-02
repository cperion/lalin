-- lua_src_validate.lua -- source-layer checks only.

local Validate = require("lua_compile.validate")

local M = {}

function M.validate(window)
  return Validate.lua_src_window(window)
end

return M
