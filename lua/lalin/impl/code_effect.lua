-- impl/code_effect.lua — compute_effects methods on LalinGraph, LalinCode,
-- LalinMem, LalinEffect types. Produces LalinEffect.EffectFactSet.
-- Entry: Graph.CodeGraph:compute_effects(module, mem, contracts)

local Code   = require("lalin.schema_v2.code")
local Graph  = require("lalin.schema_v2.graph")
local Flow   = require("lalin.schema_v2.flow")
local Value  = require("lalin.schema_v2.value")
local Mem    = require("lalin.schema_v2.mem")
local Effect = require("lalin.schema_v2.effect")

local function sanitize(s)
  s = tostring(s or "x"):gsub("[^%w_]", "_")
  if s:match("^%d") then s = "_" .. s end
  if s == "" then s = "x" end
  return s
end

local function access_id_text(func, block, inst)
  return "access:" .. sanitize(func.name) .. ":" .. sanitize(block.id.text) .. ":" .. sanitize(inst.id.text)
end

----------------------------------------------------------------------
-- Leaf methods on CodeContractFact for effect classification
----------------------------------------------------------------------

function Code.CodeContractFact:code_effect_entry_effects(out, func_id, proof)
end

function Code.CodeContractReadonly:code_effect_entry_effects(out, func_id, proof)
  local effects = out[func_id.text]
  if effects == nil then effects = {}; out[func_id.text] = effects end
  effects[#effects + 1] = Effect.EffectRead(Effect.EffectObjectStore(self.base), proof)
  effects[#effects + 1] = Effect.EffectNoEscape(self.base, "readonly contract value does not escape through writes")
end

function Code.CodeContractWriteonly:code_effect_entry_effects(out, func_id, proof)
  local effects = out[func_id.text]
  if effects == nil then effects = {}; out[func_id.text] = effects end
  effects[#effects + 1] = Effect.EffectWrite(Effect.EffectObjectStore(self.base), proof)
end

function Code.CodeContractNoAlias:code_effect_entry_effects(out, func_id, proof)
  local effects = out[func_id.text]
  if effects == nil then effects = {}; out[func_id.text] = effects end
  effects[#effects + 1] = Effect.EffectNoEscape(self.base, "noalias/noescape contract boundary")
end

function Code.CodeContractInvalidate:code_effect_entry_effects(out, func_id, proof)
  local effects = out[func_id.text]
  if effects == nil then effects = {}; out[func_id.text] = effects end
  effects[#effects + 1] = Effect.EffectInvalidate(Effect.EffectObjectStore(self.base), "invalidate contract boundary")
end

function Code.CodeContractPreserve:code_effect_entry_effects(out, func_id, proof)
  local effects = out[func_id.text]
  if effects == nil then effects = {}; out[func_id.text] = effects end
  effects[#effects + 1] = Effect.EffectRetain(self.base, "preserve contract boundary")
end

function Code.CodeContractRejected:code_effect_entry_effects(out, func_id, proof)
  local effects = out[func_id.text]
  if effects == nil then effects = {}; out[func_id.text] = effects end
  effects[#effects + 1] = Effect.EffectUnknown(self.reason)
end

local function contract_entry_effects(contracts)
  local out = {}
  for _, f in ipairs(contracts and contracts.facts or {}) do
    local proof = Mem.MemProofContract(f, Mem.MemContractBounds("contract normalized into explicit effect fact"))
    f.fact:code_effect_entry_effects(out, f.func, proof)
  end
  return out
end

----------------------------------------------------------------------
-- Leaf methods on CodeCallTarget for effect summary
----------------------------------------------------------------------

function Code.CodeCallDirect:code_effect_summary(module, contracts, pure_funcs)
  if pure_funcs and pure_funcs[self.func.text] then
    return Effect.CallSummary(self.func, nil, { Effect.EffectNoTrap("direct internal callee has no memory/call/trap effects") })
  end
  return Effect.CallSummary(self.func, nil, { Effect.EffectUnknown("direct call effects require callee summary") })
end

function Code.CodeCallExtern:code_effect_summary(module, contracts, pure_funcs)
  local name = self["extern"].text
  for _, ext in ipairs(module.externs or {}) do if ext.id == self["extern"] then name = ext.symbol or ext.name or name end end
  return Effect.CallSummary(nil, name, { Effect.EffectUnknown("extern call has unknown effects without a contract summary") })
end

function Code.CodeCallIndirect:code_effect_summary(module, contracts, pure_funcs)
  return Effect.CallSummary(nil, nil, { Effect.EffectUnknown("indirect call target is unknown") })
end

function Code.CodeCallClosure:code_effect_summary(module, contracts, pure_funcs)
  return Effect.CallSummary(nil, nil, { Effect.EffectUnknown("closure call target is unknown") })
end

----------------------------------------------------------------------
-- Mem non-trapping check
----------------------------------------------------------------------

function Mem.MemTrap:code_effect_is_non_trapping() return false end
function Mem.MemNonTrapping:code_effect_is_non_trapping() return true end

----------------------------------------------------------------------
-- internal helpers
----------------------------------------------------------------------

local function pure_internal_functions(module)
  local pure = {}
  for _, func in ipairs(module.funcs or {}) do
    local ok = true
    for _, block in ipairs(func.blocks or {}) do
      for _, inst in ipairs(block.insts or {}) do
        local op = inst.op
        if rawget(op, "access") ~= nil or rawget(op, "target") ~= nil or rawget(op, "ordering") ~= nil then
          ok = false
        end
      end
      local term_op = block.term and block.term.op or nil
      if term_op ~= nil and (rawget(term_op, "reason") ~= nil) then ok = false end
    end
    if ok then pure[func.id.text] = true end
  end
  return pure
end

local function inst_effects(module, mem, contracts)
  local mem_projection = nil
  -- access projection from mem facts
  if mem ~= nil then
    local p = Mem.MemAccessProjection({}, {}, {}, {})
    for _, access in ipairs(mem.accesses or {}) do p.access_by_id[access.id.text] = access end
    for _, interval in ipairs(mem.intervals or {}) do p.object_by_access[interval.access.text] = interval.object end
    for _, info in ipairs(mem.backend_info or {}) do p.backend_by_access[info.access.text] = info end
    for _, proof in ipairs(mem.proofs or {}) do proof:code_mem_projection_index(p) end
    mem_projection = p
  end
  local pure_funcs = pure_internal_functions(module)
  local insts, calls = {}, {}
  for _, func in ipairs(module.funcs or {}) do
    for _, block in ipairs(func.blocks or {}) do
      for _, inst in ipairs(block.insts or {}) do
        local k = inst.op
        local effects = {}
        if rawget(k, "access") ~= nil then
          local aid = access_id_text(func, block, inst)
          local obj = mem_projection and mem_projection:object_for_access(aid) or nil
          local proof = mem_projection and mem_projection:proof_for_access(aid) or nil
          local eobj = obj and Effect.EffectObjectMem(obj) or Effect.EffectObjectUnknown("memory access object is unknown")
          if rawget(k, "dst") ~= nil and rawget(k, "value") == nil then
            -- Load/AtomicLoad
            effects[#effects + 1] = Effect.EffectRead(eobj, proof)
          elseif rawget(k, "value") ~= nil and rawget(k, "replacement") == nil then
            -- Store/AtomicStore
            effects[#effects + 1] = Effect.EffectWrite(eobj, proof)
          else
            -- AtomicRmw/AtomicCas — both read and write
            effects[#effects + 1] = Effect.EffectRead(eobj, proof)
            effects[#effects + 1] = Effect.EffectWrite(eobj, proof)
          end
          local backend = mem_projection and mem_projection:backend_for_access(aid) or nil
          if backend ~= nil and backend.trap:code_effect_is_non_trapping() then
            effects[#effects + 1] = Effect.EffectNoTrap(backend.trap.reason or "memory backend info proves non-trapping")
          elseif k.access.trap == Code.CodeMustNotTrap then
            effects[#effects + 1] = Effect.EffectNoTrap("Code memory access is marked must-not-trap")
          else
            effects[#effects + 1] = Effect.EffectMayTrap("memory access may trap")
          end
          if k.access.volatile then effects[#effects + 1] = Effect.EffectVolatile("volatile memory access") end
          if rawget(k, "ordering") ~= nil then effects[#effects + 1] = Effect.EffectAtomic(tostring(k.ordering or k.access.ordering or "atomic")) end
        elseif rawget(k, "target") ~= nil then
          local summary = k.target:code_effect_summary(module, contracts, pure_funcs)
          calls[#calls + 1] = summary
          for _, eff in ipairs(summary.effects or {}) do effects[#effects + 1] = eff end
        elseif rawget(k, "ordering") ~= nil then
          effects[#effects + 1] = Effect.EffectAtomic(tostring(k.ordering or "fence"))
        end
        if #effects > 0 then insts[#insts + 1] = Effect.InstEffect(inst.id, effects) end
      end
    end
  end
  return calls, insts
end

local function term_effects(module, contracts)
  local terms = {}
  local entry_effects = contract_entry_effects(contracts)
  for _, func in ipairs(module.funcs or {}) do
    local effects = entry_effects[func.id.text]
    if effects ~= nil and #effects > 0 then terms[#terms + 1] = Effect.TermEffect(func.entry, effects) end
    for _, block in ipairs(func.blocks or {}) do
      local term = block.term and block.term.op or nil
      if term ~= nil then
        if rawget(term, "reason") ~= nil and rawget(term, "dest") == nil and rawget(term, "cond") == nil and rawget(term, "values") == nil then
          terms[#terms + 1] = Effect.TermEffect(block.id, { Effect.EffectMayTrap(term.reason or "explicit trap/unreachable terminator") })
        end
      end
    end
  end
  return terms
end

----------------------------------------------------------------------
-- compute_effects: entry point
----------------------------------------------------------------------

local function compute_effect_facts(module, graph, mem, contracts)
  local calls, insts = inst_effects(module, mem, contracts)
  return Effect.EffectFactSet(module.id, calls, insts, term_effects(module, contracts))
end

function Graph.CodeGraph:compute_effects(module, mem, contracts)
  return compute_effect_facts(module, self, mem, contracts)
end
