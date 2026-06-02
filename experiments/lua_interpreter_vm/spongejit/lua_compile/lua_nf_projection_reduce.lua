-- lua_nf_projection_reduce.lua -- minimal projection obligations.

local B = require("lua_compile.builders")
local NF = B.LuaNF

local M = {}

function M.for_exit(slot_values)
  local out, keys = {}, {}
  for id in pairs(slot_values or {}) do keys[#keys + 1] = id end
  table.sort(keys)
  for _, id in ipairs(keys) do
    local v = slot_values[id]
    if v and v.kind == "BoxI64TValue" then out[#out + 1] = NF.LiveI64(B.LuaSem.SlotClass(id), v.value)
    elseif v then out[#out + 1] = NF.LiveTValue(B.LuaSem.SlotClass(id), v) end
  end
  return out
end

return M
