-- lua_nf_to_lua_contract_derive.lua -- LuaNF.Program -> LuaContract.Contract.

local B = require("lua_compile.builders")
local pvm = require("moonlift.pvm")
local T = B.T
local NF, C, Fact = T.LuaNF, T.LuaContract, T.LuaFact
local FactUse = require("lua_compile.lua_contract_fact_use")
local Projection = require("lua_compile.lua_contract_projection")
local Dependency = require("lua_compile.lua_contract_dependency")
local RuntimeImport = require("lua_compile.lua_fact_from_runtime_observe")

local M = {}

local function add_payload(out, seen, payload)
  if not payload then return end
  local key = payload.kind .. ":" .. tostring(payload.subject and payload.subject.kind or "") .. ":" .. tostring(payload.key and payload.key.id or "") .. ":" .. tostring(payload.pc and payload.pc.id or "") .. ":" .. tostring(payload.shape_key or "")
  if not seen[key] then seen[key] = true; out[#out + 1] = C.PayloadUse(payload) end
end

local function collect_payloads(v, out, seen_payloads, seen_nodes)
  if type(v) ~= "table" then return end
  seen_nodes = seen_nodes or {}; if seen_nodes[v] then return end; seen_nodes[v] = true
  local cls = pvm.classof(v)
  if T.LuaFact.PayloadLease.members[cls] then add_payload(out, seen_payloads, v); return end
  if cls and cls.__fields then
    for _, f in ipairs(cls.__fields) do collect_payloads(v[f.name], out, seen_payloads, seen_nodes) end
  end
  for k, x in pairs(v) do
    if k ~= "kind" then collect_payloads(x, out, seen_payloads, seen_nodes) end
  end
end

local function payload_dependencies(payload_uses)
  local seen, out = {}, {}
  for _, u in ipairs(payload_uses or {}) do
    for _, d in ipairs((u.payload and u.payload.deps) or {}) do
      if not seen[d] then seen[d] = true; out[#out + 1] = d end
    end
  end
  return out
end

local function add_payload_fact_uses(facts, payload_uses)
  for _, u in ipairs(payload_uses or {}) do
    local p = u.payload
    if p.kind == "ShapePayload" then
      facts[#facts + 1] = FactUse.required(p.subject, Fact.IsTable, "", p.deps or {})
      facts[#facts + 1] = FactUse.required(p.subject, Fact.ShapeEq, p.shape_key, p.deps or {})
    elseif p.kind == "FieldPayload" then
      facts[#facts + 1] = FactUse.required(p.subject, Fact.FieldOffset, RuntimeImport.field_value_key(p.shape_key, p.key), p.deps or {})
    elseif p.kind == "ArrayPayload" then
      facts[#facts + 1] = FactUse.required(p.subject, Fact.ArrayHit, "", p.deps or {})
      facts[#facts + 1] = FactUse.required(p.subject, Fact.ArrayBaseOffset, "", p.deps or {})
    elseif p.kind == "CallTargetPayload" then
      facts[#facts + 1] = FactUse.required(p.subject, Fact.KnownCallTarget, p.target_key, p.deps or {})
      facts[#facts + 1] = FactUse.required(p.subject, Fact.TargetEq, p.target_key, p.deps or {})
    end
  end
end

local function derive_value(nf)
  local facts, payloads, projections = {}, {}, {}
  local seen_payloads = {}
  for _, step in ipairs(nf.steps or {}) do
    collect_payloads(step, payloads, seen_payloads)
    if step.kind == "StepGuard" then
      local g = step.guard
      if pvm.classof(g) == NF.FactGuard then
        facts[#facts + 1] = FactUse.required(g.subject, g.predicate, g.value_key or "", g.deps or {})
        facts[#facts + 1] = FactUse.checked(g.subject, g.predicate, g.value_key or "", g.deps or {})
      elseif pvm.classof(g) == NF.BoundsGuard then
        add_payload(payloads, seen_payloads, g.payload)
      end
    elseif step.kind == "StepWrite" then
      local w = step.write
      if pvm.classof(w) == NF.SlotWrite then
        local subject = Fact.CanonSlot(w.slot.id)
        facts[#facts + 1] = FactUse.killed(subject, Fact.IsI64, "", {})
        facts[#facts + 1] = FactUse.killed(subject, Fact.IsF64, "", {})
        facts[#facts + 1] = FactUse.killed(subject, Fact.IsTable, "", {})
        if pvm.classof(w.value) == NF.BoxI64TValue then facts[#facts + 1] = FactUse.produced(subject, Fact.IsI64, "", {}) end
        if pvm.classof(w.value) == NF.BoxF64TValue then facts[#facts + 1] = FactUse.produced(subject, Fact.IsF64, "", {}) end
      elseif pvm.classof(w) == NF.FieldWrite or pvm.classof(w) == NF.ArrayWrite then
        facts[#facts + 1] = FactUse.killed(Fact.Global, Fact.BarrierClean, "", {})
      elseif pvm.classof(w) == NF.UpvalueWrite then
        facts[#facts + 1] = FactUse.killed(Fact.Upvalue(w.up), Fact.IsI64, "", {})
        facts[#facts + 1] = FactUse.killed(Fact.Upvalue(w.up), Fact.IsF64, "", {})
        facts[#facts + 1] = FactUse.killed(Fact.Upvalue(w.up), Fact.IsTable, "", {})
      end
    elseif step.kind == "StepExit" then
      -- Projection obligations are derived once from nf.exits below. Step exits
      -- are control-flow placement, not a second contract obligation.
    end
  end
  for _, exit in ipairs(nf.exits or {}) do
    collect_payloads(exit, payloads, seen_payloads)
    projections[#projections + 1] = Projection.from_exit(exit)
  end
  add_payload_fact_uses(facts, payloads)
  local deps = Dependency.collect_from_facts(facts)
  for _, d in ipairs(payload_dependencies(payloads)) do deps[#deps + 1] = d end
  return C.Contract(C.Transfer(facts, payloads), projections, deps)
end

local phase = pvm.phase("spongejit_lua_nf_to_lua_contract_derive", function(nf)
  return derive_value(nf)
end)

function M.derive(nf)
  return pvm.one(phase(nf))
end

M.phase = phase
M.derive_uncached = derive_value

return M
