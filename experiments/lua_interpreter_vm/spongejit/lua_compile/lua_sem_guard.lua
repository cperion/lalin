-- lua_sem_guard.lua -- semantic guard construction and success facts.

local B = require("lua_compile.builders")
local Sem, Fact = B.LuaSem, B.LuaFact

local M = {}

function M.fact_guard(subject, predicate, value, deps, pc, value_key)
  return Sem.FactGuard(subject, predicate, value_key or "", value, deps or {}, type(pc) == "table" and pc or B.pc(pc))
end

function M.observe(guard)
  return Sem.Observe(Sem.GuardObservation(guard))
end

function M.i64_slot_guard(slot, pc)
  local subject = Fact.SrcSlot(type(slot) == "table" and slot or B.slot(slot))
  local value = Sem.SlotValue(Sem.SlotClass(subject.slot.id))
  return M.fact_guard(subject, Fact.IsI64, value, {}, pc)
end

return M
