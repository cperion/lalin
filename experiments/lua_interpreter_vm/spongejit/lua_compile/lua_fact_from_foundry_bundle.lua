-- lua_fact_from_foundry_bundle.lua -- foundry bundles -> LuaFact.Evidence.
--
-- Foundry bundles are evidence input only.  This module imports facts and
-- payload leases into LuaFact ASDL and deliberately does not adapt old
-- quarantined execution APIs.

local B = require("lua_compile.builders")
local T = B.T
local Fact = T.LuaFact
local Closure = require("lua_compile.lua_fact_closure")
local RuntimeImport = require("lua_compile.lua_fact_from_runtime_observe")

local M = {}

local function append_records(out, xs)
  for _, x in ipairs(xs or {}) do out[#out + 1] = x end
end

local function normalize_bundle(bundle)
  if not bundle then return {}, {} end
  if bundle.facts or bundle.observed or bundle.payloads or bundle.leases then
    local facts, payloads = {}, {}
    append_records(facts, bundle.facts)
    append_records(facts, bundle.observed)
    append_records(payloads, bundle.payloads)
    append_records(payloads, bundle.leases)
    for _, x in ipairs(bundle) do
      if RuntimeImport.payload_kind(x) then payloads[#payloads + 1] = x else facts[#facts + 1] = x end
    end
    return facts, payloads
  end
  local facts, payloads = {}, {}
  for _, x in ipairs(bundle or {}) do
    if RuntimeImport.payload_kind(x) then payloads[#payloads + 1] = x else facts[#facts + 1] = x end
  end
  return facts, payloads
end

function M.from_bundle(bundle, regions)
  local fact_records, payload_records = normalize_bundle(bundle)
  local facts, payloads = {}, {}
  for _, f in ipairs(fact_records) do
    local pred = RuntimeImport.predicate(f.predicate or f.kind or f.fact)
    if pred then
      facts[#facts + 1] = Fact.Fact(RuntimeImport.subject(f), pred, RuntimeImport.value_key(f, pred), RuntimeImport.deps(f.deps))
    end
  end
  for _, p in ipairs(payload_records) do
    local lease = RuntimeImport.payload(p)
    if lease then payloads[#payloads + 1] = lease end
  end
  return Closure.close(Fact.Evidence(facts, payloads, regions or B.region_set({})))
end

return M
