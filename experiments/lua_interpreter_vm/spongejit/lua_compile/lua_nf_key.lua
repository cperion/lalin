-- lua_nf_key.lua -- stable semantic identity key for LuaNF.

local pvm = require("moonlift.pvm")
local M = {}

local function class_name(cls, v)
  return tostring((cls and cls.__plan and cls.__plan.name) or (v and v.kind) or cls or "table")
end

local function key(v, seen)
  local tv = type(v)
  if tv ~= "table" then return tv .. ":" .. tostring(v) end
  seen = seen or {}; if seen[v] then return "<cycle>" end; seen[v] = true
  local cls = pvm.classof(v)
  if cls then
    -- Do not trust cls.__fields here: ASDL sum/type constructor name collisions
    -- can shadow product field metadata (e.g. LuaNF.Step.Write vs
    -- LuaNF.SlotWrite). Object pairs contain the actual stored fields.
    local names, parts = {}, { class_name(cls, v) }
    for k in pairs(v) do
      if k ~= "__slot" and k ~= "kind" and type(k) ~= "function" then names[#names + 1] = k end
    end
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
    for _, name in ipairs(names) do parts[#parts + 1] = tostring(name) .. "=" .. key(v[name], seen) end
    seen[v] = nil
    return table.concat(parts, "|")
  end
  local parts = {}
  for i = 1, #v do parts[#parts + 1] = key(v[i], seen) end
  seen[v] = nil
  return "[" .. table.concat(parts, ",") .. "]"
end

function M.key(nf) return key(nf) end
return M
