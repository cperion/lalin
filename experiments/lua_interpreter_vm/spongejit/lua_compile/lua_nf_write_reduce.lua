-- lua_nf_write_reduce.lua -- dead write/value reduction.

local M = {}
function M.final_slot_writes(slot_values, live_slots)
  local out = {}
  local keys = {}
  local live = nil
  if live_slots then live = {}; for _, id in ipairs(live_slots) do live[id] = true end end
  for id in pairs(slot_values or {}) do if not live or live[id] then keys[#keys + 1] = id end end
  table.sort(keys)
  for _, id in ipairs(keys) do out[#out + 1] = { slot = id, value = slot_values[id] } end
  return out
end
return M
