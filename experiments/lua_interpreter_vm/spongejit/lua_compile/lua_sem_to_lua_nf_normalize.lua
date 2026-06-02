-- lua_sem_to_lua_nf_normalize.lua -- LuaSem.Program -> LuaNF.Program.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local Sem, NF = T.LuaSem, T.LuaNF
local Canon = require("lua_compile.lua_nf_expr_canonicalize")
local Proj = require("lua_compile.lua_nf_projection_reduce")
local WriteReduce = require("lua_compile.lua_nf_write_reduce")

local M = {}

local function atom_to_nf(a, env)
  if a.kind == "SlotI64" then
    local cur = env[a.slot.id]
    if cur and cur.kind == "BoxI64TValue" then return cur.value end
    return NF.CanonAffineI64({ NF.I64Term(1, NF.SrcSlotI64(a.slot)) }, 0)
  elseif a.kind == "ImmI64" then
    return NF.CanonAffineI64({}, a.imm.value)
  elseif a.kind == "ConstI64" then
    return NF.CanonAffineI64({ NF.I64Term(1, NF.ConstI64(a.k)) }, 0)
  elseif a.kind == "UnboxI64" then
    return NF.CanonAffineI64({ NF.I64Term(1, NF.UnboxI64(M.tvalue(a.value, env))) }, 0)
  elseif a.kind == "ValueI64" then
    return NF.CanonAffineI64({ NF.I64Term(1, NF.RefI64(NF.ValueId(a.id.id))) }, 0)
  end
  error("unsupported LuaSem.I64Atom " .. tostring(a.kind))
end

local function terms_from_i64(x, env, coeff, out)
  coeff = coeff or 1; out = out or {}
  if x.kind == "AtomI64" then
    local nx = atom_to_nf(x.atom, env)
    if nx.kind == "CanonAffineI64" then
      for _, t in ipairs(nx.terms) do out[#out + 1] = NF.I64Term(coeff * t.coefficient, t.atom) end
      return out, coeff * nx.constant
    end
  elseif x.kind == "AffineI64" then
    local const = coeff * (x.constant or 0)
    for _, t in ipairs(x.terms or {}) do
      local nx = atom_to_nf(t.atom, env)
      if nx.kind == "CanonAffineI64" then
        for _, nt in ipairs(nx.terms) do out[#out + 1] = NF.I64Term(coeff * t.coefficient * nt.coefficient, nt.atom) end
        const = const + coeff * t.coefficient * nx.constant
      end
    end
    return out, const
  end
  return { NF.I64Term(coeff, NF.RefI64(NF.ValueId(0))) }, 0
end

function M.i64(x, env)
  if x.kind == "AtomI64" or x.kind == "AffineI64" then
    local terms, const = terms_from_i64(x, env, 1, {})
    return Canon.affine(terms, const)
  elseif x.kind == "MulI64" then return NF.CanonMulI64(M.i64(x.lhs, env), M.i64(x.rhs, env))
  elseif x.kind == "IDivI64" then return NF.CanonIDivI64(M.i64(x.lhs, env), M.i64(x.rhs, env))
  elseif x.kind == "ModI64" then return NF.CanonModI64(M.i64(x.lhs, env), M.i64(x.rhs, env))
  elseif x.kind == "TableLenI64" then return NF.CanonAffineI64({ NF.I64Term(1, NF.TableLenI64(M.table(x.table, env))) }, 0)
  elseif x.kind == "BitAndI64" then return NF.CanonBitAndI64({ M.i64(x.lhs, env), M.i64(x.rhs, env) })
  elseif x.kind == "BitOrI64" then return NF.CanonBitOrI64({ M.i64(x.lhs, env), M.i64(x.rhs, env) })
  elseif x.kind == "BitXorI64" then return NF.CanonBitXorI64({ M.i64(x.lhs, env), M.i64(x.rhs, env) })
  elseif x.kind == "ShlI64" then return NF.CanonShiftI64(B.LuaSrc.Shl, M.i64(x.lhs, env), M.i64(x.rhs, env))
  elseif x.kind == "ShrI64" then return NF.CanonShiftI64(B.LuaSrc.Shr, M.i64(x.lhs, env), M.i64(x.rhs, env))
  elseif x.kind == "NegI64" then return NF.CanonNegI64(M.i64(x.value, env))
  elseif x.kind == "BitNotI64" then return NF.CanonBitNotI64(M.i64(x.value, env)) end
  error("unsupported LuaSem.I64 " .. tostring(x.kind))
end

function M.f64(x, env)
  if x.kind == "SlotF64" then
    local cur = env[x.slot.id]
    if cur and cur.kind == "BoxF64TValue" then return cur.value end
    return NF.ToF64(NF.SrcSlotTValue(x.slot))
  elseif x.kind == "ConstF64" then return NF.ConstF64(x.k)
  elseif x.kind == "ImmF64" then return NF.ImmF64(x.imm)
  elseif x.kind == "ToF64" then return NF.ToF64(M.tvalue(x.value, env))
  elseif x.kind == "I64ToF64" then return NF.I64ToF64(M.i64(x.value, env))
  elseif x.kind == "DivF64" then return NF.DivF64(M.f64(x.lhs, env), M.f64(x.rhs, env))
  elseif x.kind == "PowF64" then return NF.PowF64(M.f64(x.lhs, env), M.f64(x.rhs, env)) end
  error("unsupported LuaSem.F64 " .. tostring(x.kind))
end

function M.string(x, env)
  if x.kind == "SlotString" then return NF.SrcSlotString(x.slot)
  elseif x.kind == "ConcatString" then
    local parts = {}
    for _, p in ipairs(x.parts or {}) do parts[#parts + 1] = M.string(p, env) end
    return NF.ConcatString(parts)
  end
  error("unsupported LuaSem.String " .. tostring(x.kind))
end

function M.bool(x, env)
  if x.kind == "NotTValue" then return NF.NotTValue(M.tvalue(x.value, env))
  elseif x.kind == "CmpI64" then return NF.CmpI64(x.op, M.i64(x.lhs, env), M.i64(x.rhs, env), x.polarity)
  elseif x.kind == "BoolAnd" then return NF.BoolAnd(M.bool(x.lhs, env), M.bool(x.rhs, env))
  elseif x.kind == "BoolOr" then return NF.BoolOr(M.bool(x.lhs, env), M.bool(x.rhs, env))
  elseif x.kind == "IsTruthy" then return NF.Truthy(M.tvalue(x.value, env), x.polarity) end
  error("unsupported LuaSem.Bool " .. tostring(x.kind))
end

function M.table(x, env)
  if x.kind == "CheckedTable" then return NF.TableFromTValue(M.tvalue(x.value, env), x.leases or {})
  elseif x.kind == "UpvalueTable" then return NF.TableFromUpvalue(x.up, x.leases or {})
  elseif x.kind == "NewTable" then return NF.TableFromNew(x.array_hint, x.hash_hint) end
  error("unsupported LuaSem.Table " .. tostring(x.kind))
end

function M.closure(x, env)
  if x.kind == "CheckedClosure" then return NF.ClosureFromTValue(M.tvalue(x.value, env), x.leases or {})
  elseif x.kind == "ProtoClosure" then return NF.ClosureFromProto(x.proto) end
  error("unsupported LuaSem.Closure " .. tostring(x.kind))
end

function M.address(x, env)
  if x.kind == "TableField" then return NF.FieldAddress(M.table(x.table, env), x.key, x.field_payload)
  elseif x.kind == "TableArray" then return NF.ArrayAddress(M.table(x.table, env), M.i64(x.index, env), x.array_payload)
  elseif x.kind == "UpvalueCell" then return NF.UpvalueAddress(x.up) end
  error("unsupported LuaSem.Address " .. tostring(x.kind))
end

function M.tvalue(v, env)
  if v.kind == "SlotValue" then return env[v.slot.id] or NF.SrcSlotTValue(v.slot)
  elseif v.kind == "ConstValue" then return NF.ConstTValue(v.k)
  elseif v.kind == "UpvalueValue" then return NF.UpvalueTValue(v.up)
  elseif v.kind == "VarargValue" then return NF.VarargTValue(v.base, v.index)
  elseif v.kind == "Nil" then return NF.NilTValue
  elseif v.kind == "Bool" then return NF.BoolTValue(v.value == true)
  elseif v.kind == "BoolValue" then return NF.BoolExprTValue(M.bool(v.value, env))
  elseif v.kind == "BoxI64" then return NF.BoxI64TValue(M.i64(v.value, env))
  elseif v.kind == "BoxF64" then return NF.BoxF64TValue(M.f64(v.value, env))
  elseif v.kind == "StringValue" then return NF.StringTValue(M.string(v.value, env))
  elseif v.kind == "FieldValue" then return NF.FieldTValue(M.address(v.address, env))
  elseif v.kind == "ArrayValue" then return NF.ArrayTValue(M.address(v.address, env))
  elseif v.kind == "TableObject" then return NF.TableTValue(M.table(v.object, env))
  elseif v.kind == "ClosureObject" then return NF.ClosureTValue(M.closure(v.object, env))
  elseif v.kind == "UnknownTValue" then return NF.RefTValue(NF.ValueId(0)) end
  return NF.RefTValue(NF.ValueId(0))
end

local function next_exit_id(state)
  local id = state.next_exit_id; state.next_exit_id = id + 1; return NF.ExitId(id)
end

local function lower_observation(obs, state)
  if obs.kind == "GuardObservation" then
    local projection = Proj.for_exit(state.env)
    local exit = NF.GuardExit(next_exit_id(state), obs.guard.pc, projection)
    state.exits[#state.exits + 1] = exit
    if obs.guard.kind == "FactGuard" then
      state.steps[#state.steps + 1] = NF.StepGuard(NF.FactGuard(obs.guard.subject, obs.guard.predicate, obs.guard.value_key or "", M.tvalue(obs.guard.value, state.env), obs.guard.deps or {}, exit))
    elseif obs.guard.kind == "I64NonZeroGuard" then
      state.steps[#state.steps + 1] = NF.StepGuard(NF.I64NonZeroGuard(M.i64(obs.guard.value, state.env), exit))
    elseif obs.guard.kind == "BoundsGuard" then
      state.steps[#state.steps + 1] = NF.StepGuard(NF.BoundsGuard(M.table(obs.guard.table, state.env), M.i64(obs.guard.index, state.env), obs.guard.payload, exit))
    end
  elseif obs.kind == "ReturnObservation" then
    local projection = Proj.for_exit(state.env)
    local exit = NF.ReturnExit(next_exit_id(state), obs.pc, M.tvalue(obs.value, state.env), projection)
    state.exits[#state.exits + 1] = exit
    state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "Return0Observation" then
    local projection = Proj.for_exit(state.env)
    local exit = NF.Return0Exit(next_exit_id(state), obs.pc, projection)
    state.exits[#state.exits + 1] = exit
    state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "JumpObservation" then
    local exit = NF.JumpExit(next_exit_id(state), obs.pc, obs.offset, Proj.for_exit(state.env))
    state.exits[#state.exits + 1] = exit; state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "ConditionalJumpObservation" then
    local exit = NF.ConditionalJumpExit(next_exit_id(state), obs.pc, M.bool(obs.condition, state.env), obs.offset, Proj.for_exit(state.env))
    state.exits[#state.exits + 1] = exit; state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "TestSetObservation" then
    local value = M.tvalue(obs.value, state.env)
    local fallthrough_env = {}
    local taken_env = {}
    for k, v in pairs(state.env or {}) do fallthrough_env[k] = v; taken_env[k] = v end
    taken_env[obs.target.id] = value
    local exit = NF.TestSetExit(next_exit_id(state), obs.pc, M.bool(obs.condition, state.env), obs.offset, Proj.for_exit(taken_env), Proj.for_exit(fallthrough_env))
    state.exits[#state.exits + 1] = exit; state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "LoopRegionObservation" then
    local exit = NF.LoopRegionExit(next_exit_id(state), obs.region, Proj.for_exit(state.env))
    state.exits[#state.exits + 1] = exit; state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "CallProtocolObservation" then
    local exit = NF.CallProtocolExit(next_exit_id(state), obs.pc, obs.base, obs.nargs, obs.nresults, obs.tail, Proj.for_exit(state.env))
    state.exits[#state.exits + 1] = exit; state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "CloseProtocolObservation" then
    local exit = NF.CloseProtocolExit(next_exit_id(state), obs.pc, obs.slot, obs.tbc, Proj.for_exit(state.env))
    state.exits[#state.exits + 1] = exit; state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  elseif obs.kind == "GenericForProtocolObservation" then
    local exit = NF.GenericForProtocolExit(next_exit_id(state), obs.pc, obs.base, obs.nresults, obs.offset, obs.phase, Proj.for_exit(state.env))
    state.exits[#state.exits + 1] = exit; state.steps[#state.steps + 1] = NF.StepExit(exit)
    state.has_terminal_exit = true
  end
end

local function normalize_value(program)
  local state = { env = {}, steps = {}, exits = {}, next_exit_id = 1 }
  for _, eff in ipairs(program.effects or {}) do
    if eff.kind == "DoWrite" and eff.write.kind == "SlotWrite" then
      state.env[eff.write.slot.id] = M.tvalue(eff.write.value, state.env)
    elseif eff.kind == "DoWrite" and eff.write.kind == "FieldWrite" then
      state.steps[#state.steps + 1] = NF.StepWrite(NF.FieldWrite(M.address(eff.write.address, state.env), M.tvalue(eff.write.value, state.env)))
    elseif eff.kind == "DoWrite" and eff.write.kind == "ArrayWrite" then
      state.steps[#state.steps + 1] = NF.StepWrite(NF.ArrayWrite(M.address(eff.write.address, state.env), M.tvalue(eff.write.value, state.env)))
    elseif eff.kind == "DoWrite" and eff.write.kind == "UpvalueWrite" then
      state.steps[#state.steps + 1] = NF.StepWrite(NF.UpvalueWrite(eff.write.up, M.tvalue(eff.write.value, state.env)))
    elseif eff.kind == "DoWrite" and eff.write.kind == "SetListWrite" then
      state.steps[#state.steps + 1] = NF.StepWrite(NF.SetListWrite(eff.write.table, eff.write.narray, eff.write.start))
    elseif eff.kind == "Observe" then
      lower_observation(eff.observation, state)
    elseif eff.kind == "BarrierAfterStore" then
      state.steps[#state.steps + 1] = NF.StepBarrier(NF.BarrierAfterStore(M.tvalue(eff.owner, state.env), M.tvalue(eff.value, state.env), eff.payload))
    end
  end
  if not state.has_terminal_exit then
    for _, w in ipairs(WriteReduce.final_slot_writes(state.env)) do
      state.steps[#state.steps + 1] = NF.StepWrite(NF.SlotWrite(B.LuaSem.SlotClass(w.slot), w.value))
    end
  end
  return NF.Program(program.slots or {}, state.steps, state.exits)
end

local phase = pvm.phase("spongejit_lua_sem_to_lua_nf_normalize", function(program)
  return normalize_value(program)
end)

function M.normalize(program)
  return pvm.one(phase(program))
end

M.phase = phase
M.normalize_uncached = normalize_value

return M
