-- lua_fact_contradiction.lua -- contradiction detection for LuaFact evidence.

local Schema = require("lua_compile.schema")
local T = Schema.get()
local Fact = T.LuaFact
local Closure = require("lua_compile.lua_fact_closure")

local M = {}

local function subject_key(s)
  return Closure.subject_key(s)
end

local TYPE_GROUP = {
  IsNil = "nil",
  IsFalse = "bool_false",
  IsTrue = "bool_true",
  IsI64 = "number_i64",
  IsF64 = "number_f64",
  IsTable = "table",
  IsClosure = "closure",
}

local function compatible_category(category, group)
  if category == "IsBool" then return group == "bool_false" or group == "bool_true" end
  if category == "IsNumber" then return group == "number_i64" or group == "number_f64" end
  return true
end

function M.find(evidence)
  local by_subject = {}
  local errors = {}
  for _, f in ipairs((evidence and evidence.observed) or {}) do
    local pk = f.predicate and f.predicate.kind
    local k = subject_key(f.subject)
    by_subject[k] = by_subject[k] or { groups = {}, categories = {} }
    if TYPE_GROUP[pk] then by_subject[k].groups[TYPE_GROUP[pk]] = true end
    if pk == "IsBool" or pk == "IsNumber" then by_subject[k].categories[pk] = true end
  end
  for subject, info in pairs(by_subject) do
    local concrete = {}
    for group in pairs(info.groups) do concrete[#concrete + 1] = group end
    table.sort(concrete)
    if #concrete > 1 then
      local incompatible = false
      if #concrete == 2 and concrete[1] == "bool_false" and concrete[2] == "bool_true" then incompatible = true
      elseif #concrete > 1 then incompatible = true end
      if incompatible then errors[#errors + 1] = "contradictory type facts for " .. subject .. ": " .. table.concat(concrete, ",") end
    end
    for cat in pairs(info.categories) do
      for group in pairs(info.groups) do
        if not compatible_category(cat, group) then
          errors[#errors + 1] = "contradictory type category for " .. subject .. ": " .. cat .. " vs " .. group
        end
      end
    end
  end
  return errors
end

return M
