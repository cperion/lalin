-- lua_src_window_collect.lua -- opcode stream -> LuaSrc.Window.

local B = require("lua_compile.builders")
local Decode = require("lua_compile.lua_src_from_puc_decode")

local M = {}

function M.collect(events)
  local ops = {}
  for i, ev in ipairs(events or {}) do ops[i] = Decode.decode(ev) end
  return B.window(ops)
end

return M
