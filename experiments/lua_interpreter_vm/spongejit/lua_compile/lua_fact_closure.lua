-- lua_fact_closure.lua -- implication/dependency closure for LuaFact evidence.

local B = require("lua_compile.builders")
local T = B.T
local Fact = T.LuaFact
local M = {}

local function field_value_key(shape_key, key)
  local kid = type(key) == "table" and key.id or key
  return tostring(shape_key or "") .. ":k" .. tostring(kid or 0)
end

local function subject_key(s)
  if not s then return "?" end
  if s.kind == "SrcSlot" then return "slot:" .. s.slot.id end
  if s.kind == "CanonSlot" then return "canon:" .. s.slot_class end
  if s.kind == "Const" then return "const:" .. s.k.id end
  if s.kind == "Upvalue" then return "up:" .. s.up.id end
  if s.kind == "TableValue" then return "table:" .. s.id end
  if s.kind == "Callsite" then return "call:" .. s.pc.id end
  if s.kind == "Memory" then return "mem:" .. s.domain end
  if s.kind == "Global" then return "global" end
  return tostring(s.kind)
end

local function fact_key(f)
  return subject_key(f.subject) .. ":" .. tostring(f.predicate and f.predicate.kind) .. ":" .. tostring(f.value_key or "")
end
local function add(out, seen, f)
  local k = fact_key(f)
  if not seen[k] then seen[k] = true; out[#out + 1] = f end
end
local function add_fact(out, seen, subject, pred, value_key, deps)
  add(out, seen, Fact.Fact(subject, pred, value_key or "", deps or {}))
end

local function payload_implied_facts(p, out, seen)
  if p.kind == "ShapePayload" then
    add_fact(out, seen, p.subject, Fact.ShapeEq, p.shape_key, p.deps)
    add_fact(out, seen, p.subject, Fact.ShapeKnown, p.shape_key, p.deps)
    add_fact(out, seen, p.subject, Fact.IsTable, "", p.deps)
  elseif p.kind == "FieldPayload" then
    add_fact(out, seen, p.subject, Fact.FieldOffset, field_value_key(p.shape_key, p.key), p.deps)
  elseif p.kind == "ArrayPayload" then
    add_fact(out, seen, p.subject, Fact.ArrayHit, "", p.deps)
    add_fact(out, seen, p.subject, Fact.ArrayBaseOffset, "", p.deps)
    add_fact(out, seen, p.subject, Fact.IsTable, "", p.deps)
  elseif p.kind == "CallTargetPayload" then
    add_fact(out, seen, p.subject, Fact.KnownCallTarget, p.target_key, p.deps)
    add_fact(out, seen, p.subject, Fact.TargetEq, p.target_key, p.deps)
  end
end

function M.close(evidence)
  local out, seen = {}, {}
  for _, p in ipairs((evidence and evidence.payloads) or {}) do payload_implied_facts(p, out, seen) end
  for _, f in ipairs((evidence and evidence.observed) or {}) do
    add(out, seen, f)
    if f.predicate == Fact.ShapeEq then
      add_fact(out, seen, f.subject, Fact.ShapeKnown, f.value_key or "", f.deps)
      add_fact(out, seen, f.subject, Fact.IsTable, "", f.deps)
    elseif f.predicate == Fact.ShapeKnown then
      add_fact(out, seen, f.subject, Fact.IsTable, "", f.deps)
    elseif f.predicate == Fact.IsTrue or f.predicate == Fact.IsFalse then
      add_fact(out, seen, f.subject, Fact.IsBool, "", f.deps)
    elseif f.predicate == Fact.IsI64 or f.predicate == Fact.IsF64 or f.predicate == Fact.ConstI64 or f.predicate == Fact.ConstF64 then
      add_fact(out, seen, f.subject, Fact.IsNumber, "", f.deps)
      if f.predicate == Fact.ConstI64 then add_fact(out, seen, f.subject, Fact.IsI64, "", f.deps) end
      if f.predicate == Fact.ConstF64 then add_fact(out, seen, f.subject, Fact.IsF64, "", f.deps) end
    elseif f.predicate == Fact.FieldOffset and f.value_key and f.value_key ~= "" then
      -- A field-offset fact is only meaningful with a constant field key.  If
      -- the key can be represented as the canonical :kN suffix, expose it as a
      -- KeyConst implication for consumers that route dynamic GETTABLE through
      -- the field path.
      local kid = tostring(f.value_key):match(":k(%d+)$")
      if kid then add_fact(out, seen, f.subject, Fact.KeyConst, kid, f.deps) end
    elseif f.predicate == Fact.KnownCallTarget then
      add_fact(out, seen, f.subject, Fact.TargetEq, f.value_key or "", f.deps)
    end
  end
  return Fact.Evidence(out, evidence and evidence.payloads or {}, evidence and evidence.regions or B.region_set({}))
end

M.subject_key = subject_key
return M
