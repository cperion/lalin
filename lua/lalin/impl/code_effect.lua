-- impl/code_effect.lua — compute_effects methods on LalinGraph, LalinCode,
-- LalinMem, LalinEffect types. Produces LalinEffect.EffectFactSet.
-- Entry: Graph.CodeGraph:compute_effects(module, mem, contracts)

require("lalin.schema_v2")
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
-- CodeContractFact effect leaves return typed immutable results
----------------------------------------------------------------------

local function contract_evidence(input)
  local proof = Mem.MemProofContract(input.source, Mem.MemContractBounds("effect contract"))
  return Effect.EffectEvidenceContract(input.source, proof)
end
local function contract_no_effect(input, reason) return Effect.ContractNoEffect(Effect.EffectEvidenceDeclared(reason)) end
function Code.CodeContractBounds:contract_effect(input) return contract_no_effect(input, "bounds contract has no runtime effect") end
function Code.CodeContractProjectionBounds:contract_effect(input) return contract_no_effect(input, "projection bounds contract has no runtime effect") end
function Code.CodeContractWindowBounds:contract_effect(input) return contract_no_effect(input, "window bounds contract has no runtime effect") end
function Code.CodeContractDisjoint:contract_effect(input) return contract_no_effect(input, "disjointness is alias evidence") end
function Code.CodeContractSameLen:contract_effect(input) return contract_no_effect(input, "same-length is shape evidence") end
function Code.CodeContractSoAComponent:contract_effect(input) return contract_no_effect(input, "SoA component is layout evidence") end
function Code.CodeContractNoAlias:contract_effect(input)
  return Effect.ContractEffects({ Effect.EffectNoEscape(self.base, contract_evidence(input)) })
end
function Code.CodeContractReadonly:contract_effect(input)
  local evidence = contract_evidence(input)
  return Effect.ContractEffects({ Effect.EffectRead(Effect.EffectObjectStore(self.base), evidence), Effect.EffectNoEscape(self.base, evidence) })
end
function Code.CodeContractWriteonly:contract_effect(input)
  return Effect.ContractEffects({ Effect.EffectWrite(Effect.EffectObjectStore(self.base), contract_evidence(input)) })
end
function Code.CodeContractProjectionReadonly:contract_effect(input)
  return Effect.ContractEffects({ Effect.EffectRead(Effect.EffectObjectUnknown("readonly contract projection"), contract_evidence(input)) })
end
function Code.CodeContractProjectionWriteonly:contract_effect(input)
  return Effect.ContractEffects({ Effect.EffectWrite(Effect.EffectObjectUnknown("writeonly contract projection"), contract_evidence(input)) })
end
function Code.CodeContractInvalidate:contract_effect(input)
  return Effect.ContractEffects({ Effect.EffectInvalidate(Effect.EffectObjectStore(self.base), contract_evidence(input)) })
end
function Code.CodeContractPreserve:contract_effect(input)
  return Effect.ContractEffects({ Effect.EffectRetain(self.base, contract_evidence(input)) })
end
function Code.CodeContractRejected:contract_effect(input)
  return Effect.ContractEffects({ Effect.EffectUnknown(Effect.EffectEvidenceConservative(self.reason)) })
end
function Code.CodeFuncContractFact:contract_effect() return self.fact:contract_effect(Effect.ContractEffectInput(self)) end
function Code.CodeContractFactSet:project_contract_effects()
  local entries = {}
  for _, source in ipairs(self.facts) do
    local next_entries = {}
    for i = 1, #entries do next_entries[i] = entries[i] end
    next_entries[#next_entries + 1] = Effect.ContractEffectEntry(source.func, source:contract_effect())
    entries = next_entries
  end
  return Effect.ContractEffectProjection(entries)
end


----------------------------------------------------------------------
-- Complete call-target summaries
----------------------------------------------------------------------

function Effect.FunctionEffectProjection:lookup(func)
  for _, entry in ipairs(self.functions) do if entry.func == func then return Effect.FunctionEffectFound(entry) end end
  return Effect.FunctionEffectMissing(func)
end
function Effect.FunctionEffectFound:call_summary_direct(target) return self.entry.classification:call_summary_direct(target) end
function Effect.FunctionEffectMissing:call_summary_direct(target)
  local evidence = Effect.EffectEvidenceConservative("direct callee classification is unavailable")
  return Effect.CallSummaryDirect(target.func, Effect.FunctionEffectUnresolved(evidence), { Effect.EffectUnknown(evidence) })
end
function Effect.FunctionEffectPure:call_summary_direct(target) return Effect.CallSummaryDirect(target.func, self, { Effect.EffectNoTrap(self.evidence) }) end
function Effect.FunctionEffectful:call_summary_direct(target) return Effect.CallSummaryDirect(target.func, self, self.effects) end
function Effect.FunctionEffectUnresolved:call_summary_direct(target) return Effect.CallSummaryDirect(target.func, self, { Effect.EffectUnknown(self.evidence) }) end

function Code.CodeCallDirect:effect_summary(input) return input.functions:lookup(self.func):call_summary_direct(self) end
function Code.CodeCallExtern:effect_summary(input)
  local symbol = self["extern"].text
  for _, ext in ipairs(input.module.externs) do if ext.id == self["extern"] then symbol = ext.symbol end end
  local evidence = Effect.EffectEvidenceConservative("extern call has no declared effect contract")
  return Effect.CallSummaryExtern(self["extern"], symbol, { Effect.EffectUnknown(evidence) })
end
function Code.CodeCallIndirect:effect_summary(input)
  local evidence = Effect.EffectEvidenceConservative("indirect call target is unresolved")
  return Effect.CallSummaryIndirect(self.callee, self.sig, { Effect.EffectUnknown(evidence) })
end
function Code.CodeCallClosure:effect_summary(input)
  local evidence = Effect.EffectEvidenceConservative("closure call target is unresolved")
  return Effect.CallSummaryClosure(self.closure, self.sig, { Effect.EffectUnknown(evidence) })
end

----------------------------------------------------------------------
-- Instruction and terminator effect leaves
----------------------------------------------------------------------

local function append_one(xs, value)
  local out = {}
  for i = 1, #xs do out[i] = xs[i] end
  out[#out + 1] = value
  return out
end
local function append_all(xs, ys)
  local out = {}
  for i = 1, #xs do out[#out + 1] = xs[i] end
  for i = 1, #ys do out[#out + 1] = ys[i] end
  return out
end

function Mem.MemObjectFound:effect_object() return Effect.EffectObjectMem(self.object) end
function Mem.MemObjectMissing:effect_object() return Effect.EffectObjectUnknown("memory access object is unresolved") end
function Mem.MemProofFound:effect_evidence() return Effect.EffectEvidenceMemory(self.proof) end
function Mem.MemProofMissing:effect_evidence() return Effect.EffectEvidenceConservative("memory proof is unavailable for " .. self.access.text) end
function Mem.MemNonTrapping:effect_trap(evidence) return Effect.EffectNoTrap(evidence) end
function Mem.MemCheckedTrap:effect_trap(evidence) return Effect.EffectMayTrap(evidence) end
function Mem.MemMayTrap:effect_trap(evidence) return Effect.EffectMayTrap(evidence) end
function Mem.MemBackendFound:effect_trap(access, evidence) return self.backend.trap:effect_trap(evidence) end
function Mem.MemBackendMissing:effect_trap(access, evidence) return access.trap:effect_trap(evidence) end
function Code.CodeMayTrap:effect_trap(evidence) return Effect.EffectMayTrap(evidence) end
function Code.CodeMustNotTrap:effect_trap(evidence) return Effect.EffectNoTrap(evidence) end
function Code.CodeCheckedTrap:effect_trap(evidence) return Effect.EffectMayTrap(evidence) end

function Mem.MemLoad:effects_for_access(object, evidence) return Effect.EffectAccessEffects({ Effect.EffectRead(object, evidence) }) end
function Mem.MemStore:effects_for_access(object, evidence) return Effect.EffectAccessEffects({ Effect.EffectWrite(object, evidence) }) end
function Mem.MemAtomicLoad:effects_for_access(object, evidence) return Effect.EffectAccessEffects({ Effect.EffectRead(object, evidence) }) end
function Mem.MemAtomicStore:effects_for_access(object, evidence) return Effect.EffectAccessEffects({ Effect.EffectWrite(object, evidence) }) end
function Mem.MemAtomicRmw:effects_for_access(object, evidence) return Effect.EffectAccessEffects({ Effect.EffectRead(object, evidence), Effect.EffectWrite(object, evidence) }) end
function Mem.MemAtomicCas:effects_for_access(object, evidence) return Effect.EffectAccessEffects({ Effect.EffectRead(object, evidence), Effect.EffectWrite(object, evidence) }) end

local function memory_effect(input, op, access, ordering)
  local aid = Mem.MemAccessId(access_id_text(input.func, input.block, input.inst))
  local object = input.memory:object_for_access(aid):effect_object()
  local evidence = input.memory:proof_for_access(aid):effect_evidence()
  local effects = op:effects_for_access(object, evidence).effects
  effects = append_one(effects, input.memory:backend_for_access(aid):effect_trap(access, evidence))
  if access.volatile then effects = append_one(effects, Effect.EffectVolatile(Effect.EffectEvidenceDeclared("volatile memory access"))) end
  if ordering then effects = append_one(effects, Effect.EffectAtomic(ordering, Effect.EffectEvidenceDeclared("atomic memory operation"))) end
  return Effect.EffectInstructionEffects(Effect.InstEffect(input.inst.id, effects))
end
function Code.CodeInstLoad:compute_effect(input) return memory_effect(input, Mem.MemLoad, self.access, self.access.ordering) end
function Code.CodeInstStore:compute_effect(input) return memory_effect(input, Mem.MemStore, self.access, self.access.ordering) end
function Code.CodeInstAtomicLoad:compute_effect(input) return memory_effect(input, Mem.MemAtomicLoad, self.access, self.ordering) end
function Code.CodeInstAtomicStore:compute_effect(input) return memory_effect(input, Mem.MemAtomicStore, self.access, self.ordering) end
function Code.CodeInstAtomicRmw:compute_effect(input) return memory_effect(input, Mem.MemAtomicRmw, self.access, self.ordering) end
function Code.CodeInstAtomicCas:compute_effect(input) return memory_effect(input, Mem.MemAtomicCas, self.access, self.ordering) end
function Code.CodeInstCall:compute_effect(input)
  local summary = self.target:effect_summary(Effect.CallSummaryInput(input.module, input.functions))
  return Effect.EffectInstructionCall(summary, Effect.InstEffect(input.inst.id, summary.effects))
end
function Code.CodeInstAtomicFence:compute_effect(input)
  return Effect.EffectInstructionEffects(Effect.InstEffect(input.inst.id, { Effect.EffectAtomic(self.ordering, Effect.EffectEvidenceDeclared("atomic fence")) }))
end

local function no_instruction_effect() return Effect.EffectInstructionNone end
function Code.CodeInstConst:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstAlias:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstUnary:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstBinary:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstFloatBinary:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstCompare:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstCast:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstSelect:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstIntrinsicVoid:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstIntrinsicValue:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstAddrOf:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstGlobalRef:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstPtrOffset:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstAggregate:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstArray:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstViewMake:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstViewData:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstViewLen:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstViewStride:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstSliceMake:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstSliceData:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstSliceLen:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstByteSpanMake:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstByteSpanData:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstByteSpanLen:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstClosure:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstVariantCtor:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstVariantTag:compute_effect(input) return no_instruction_effect() end
function Code.CodeInstVariantPayload:compute_effect(input) return no_instruction_effect() end

function Effect.FunctionEffectEmpty:append_effects(effects)
  if #effects == 0 then return self end
  return Effect.FunctionEffectsAccumulated(effects)
end
function Effect.FunctionEffectsAccumulated:append_effects(effects) return Effect.FunctionEffectsAccumulated(append_all(self.effects, effects)) end
function Effect.FunctionEffectEmpty:classification() return Effect.FunctionEffectPure(self.evidence) end
function Effect.FunctionEffectsAccumulated:classification() return Effect.FunctionEffectful(self.effects) end
function Effect.EffectInstructionNone:compose(state) return state end
function Effect.EffectInstructionEffects:compose(state)
  return Effect.EffectFunctionComposition(state.calls, append_one(state.insts, self.effect), state.terms, state.accumulation:append_effects(self.effect.effects))
end
function Effect.EffectInstructionCall:compose(state)
  return Effect.EffectFunctionComposition(append_one(state.calls, self.summary), append_one(state.insts, self.effect), state.terms, state.accumulation:append_effects(self.effect.effects))
end

function Code.CodeTermJump:compute_term_effect(input) return Effect.EffectTermNone end
function Code.CodeTermBranch:compute_term_effect(input) return Effect.EffectTermNone end
function Code.CodeTermSwitch:compute_term_effect(input) return Effect.EffectTermNone end
function Code.CodeTermVariantSwitch:compute_term_effect(input) return Effect.EffectTermNone end
function Code.CodeTermReturn:compute_term_effect(input) return Effect.EffectTermNone end
function Code.CodeTermTrap:compute_term_effect(input)
  return Effect.EffectTermEffects(Effect.TermEffect(input.block.id, { Effect.EffectMayTrap(Effect.EffectEvidenceDeclared(self.reason)) }))
end
function Code.CodeTermUnreachable:compute_term_effect(input)
  return Effect.EffectTermEffects(Effect.TermEffect(input.block.id, { Effect.EffectMayTrap(Effect.EffectEvidenceDeclared(self.reason)) }))
end
function Effect.EffectTermNone:compose(state) return state end
function Effect.EffectTermEffects:compose(state)
  return Effect.EffectFunctionComposition(state.calls, state.insts, append_one(state.terms, self.effect), state.accumulation:append_effects(self.effect.effects))
end

function Effect.ContractEffects:append_for_function(effects) return append_all(effects, self.effects) end
function Effect.ContractNoEffect:append_for_function(effects) return effects end
function Effect.ContractEffectProjection:effects_for_function(func)
  local effects = {}
  for _, entry in ipairs(self.entries) do if entry.func == func then effects = entry.result:append_for_function(effects) end end
  return effects
end

local function unresolved_function_projection(module)
  local entries = {}
  for _, func in ipairs(module.funcs) do
    entries = append_one(entries, Effect.FunctionEffectEntry(func.id, Effect.FunctionEffectUnresolved(Effect.EffectEvidenceConservative("function analysis is in progress"))))
  end
  return Effect.FunctionEffectProjection(entries)
end
function Effect.EffectAnalysisRequest:analyze()
  local memory = self.memory:project_accesses()
  local contract_projection = self.contracts:project_contract_effects()
  local function_inputs = unresolved_function_projection(self.module)
  local calls, insts, terms, classifications = {}, {}, {}, {}
  for _, func in ipairs(self.module.funcs) do
    local empty = Effect.FunctionEffectEmpty(Effect.EffectEvidenceDeclared("function has no observable effects"))
    local state = Effect.EffectFunctionComposition({}, {}, {}, empty)
    for _, block in ipairs(func.blocks) do
      for _, inst in ipairs(block.insts) do
        local input = Effect.EffectInstructionInput(self.module, func, block, inst, memory, function_inputs)
        state = inst.op:compute_effect(input):compose(state)
      end
      state = block.term.op:compute_term_effect(Effect.EffectTermInput(func, block, block.term, contract_projection)):compose(state)
    end
    local contract_effects = contract_projection:effects_for_function(func.id)
    if #contract_effects > 0 then
      local entry_effect = Effect.TermEffect(func.entry, contract_effects)
      state = Effect.EffectFunctionComposition(state.calls, state.insts, append_one(state.terms, entry_effect), state.accumulation:append_effects(contract_effects))
    end
    calls, insts, terms = append_all(calls, state.calls), append_all(insts, state.insts), append_all(terms, state.terms)
    classifications = append_one(classifications, Effect.FunctionEffectEntry(func.id, state.accumulation:classification()))
  end
  local facts = Effect.EffectFactSet(self.module.id, calls, insts, terms)
  return Effect.EffectAnalysisResult(facts, Effect.FunctionEffectProjection(classifications))
end

function Graph.CodeGraph:compute_effect_analysis(module, mem, contracts)
  return Effect.EffectAnalysisRequest(module, self, mem, contracts):analyze()
end
function Graph.CodeGraph:compute_effects(module, mem, contracts) return self:compute_effect_analysis(module, mem, contracts).facts end
