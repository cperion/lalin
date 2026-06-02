-- lua_sem_env.lua -- virtual slot/value environment.

local B = require("lua_compile.builders")
local Sem = B.LuaSem

local Env = {}
Env.__index = Env

function Env.new()
  return setmetatable({ aliases = {}, values = {}, next_value_id = 1 }, Env)
end

function Env:slot_class(slot)
  local id = type(slot) == "table" and slot.id or tonumber(slot) or 0
  return Sem.SlotClass(id)
end

function Env:alias(slot, first_pc, last_pc)
  local id = type(slot) == "table" and slot.id or tonumber(slot) or 0
  if not self.aliases[id] then self.aliases[id] = Sem.SlotAlias(type(slot) == "table" and slot or B.slot(id), Sem.SlotClass(id), first_pc or B.pc(0), last_pc or first_pc or B.pc(0)) end
  return self.aliases[id]
end

function Env:slot_value(slot)
  return Sem.SlotValue(self:slot_class(slot))
end

function Env:next_value()
  local id = self.next_value_id
  self.next_value_id = id + 1
  return Sem.ValueId(id)
end

function Env:aliases_array()
  local keys, out = {}, {}
  for k in pairs(self.aliases) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do out[#out + 1] = self.aliases[k] end
  return out
end

return Env
