-- lua_sem_write.lua -- semantic writes, kills, barriers.

local B = require("lua_compile.builders")
local Sem = B.LuaSem

local M = {}

function M.slot(slot_class, value)
  return Sem.DoWrite(Sem.SlotWrite(slot_class, value))
end

function M.field(address, value)
  return Sem.DoWrite(Sem.FieldWrite(address, value))
end

function M.barrier(owner, value, payload)
  return Sem.BarrierAfterStore(owner, value, payload)
end

return M
