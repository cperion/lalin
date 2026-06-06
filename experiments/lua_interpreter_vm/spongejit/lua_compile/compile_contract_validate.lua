-- compile_contract_validate.lua -- executable contract structural validation.

local pvm = require("moonlift.pvm")
local Schema = require("lua_compile.schema")
local T = Schema.get()

local M = {}

local function add(errors, msg) errors[#errors + 1] = msg end
local function is(v, cls) return pvm.classof(v) == cls end
local function member(v, family)
  return family and family.members and family.members[pvm.classof(v)]
end

local function validate_deps(errors, deps, path)
  for i, d in ipairs(deps or {}) do
    if not member(d, T.LuaFact.Dependency) then add(errors, path .. ".deps[" .. i .. "] must be LuaFact.Dependency") end
  end
end

local function validate_fact_use(errors, f, path)
  if not is(f, T.CompileContract.FactUse) then
    add(errors, path .. " must be CompileContract.FactUse")
    return
  end
  if not member(f.role, T.CompileContract.FactRole) then add(errors, path .. ".role must be CompileContract.FactRole") end
  if not member(f.subject, T.LuaFact.Subject) then add(errors, path .. ".subject must be LuaFact.Subject") end
  if not member(f.predicate, T.LuaFact.Predicate) then add(errors, path .. ".predicate must be LuaFact.Predicate") end
  if type(f.value_key) ~= "string" then add(errors, path .. ".value_key must be string") end
  validate_deps(errors, f.deps, path)
end

local function validate_payload_use(errors, p, path)
  if not is(p, T.CompileContract.PayloadUse) then
    add(errors, path .. " must be CompileContract.PayloadUse")
    return
  end
  if not member(p.payload, T.LuaFact.PayloadLease) then add(errors, path .. ".payload must be LuaFact.PayloadLease") end
end

local function validate_obligation(errors, o, path)
  if not member(o, T.CompileContract.Obligation) then
    add(errors, path .. " must be CompileContract.Obligation")
    return
  end
  local cls = pvm.classof(o)
  if cls == T.CompileContract.RequiresFact then validate_fact_use(errors, o.fact, path .. ".fact")
  elseif cls == T.CompileContract.RequiresPayload then validate_payload_use(errors, o.payload, path .. ".payload")
  elseif cls == T.CompileContract.RequiresRuntimeGuard then
    if not member(o.guard, T.LuaRT.Guard) then add(errors, path .. ".guard must be LuaRT.Guard") end
  elseif cls == T.CompileContract.RequiresExecObligation then
    if not member(o.obligation, T.LuaExec.Obligation) then add(errors, path .. ".obligation must be LuaExec.Obligation") end
  elseif cls == T.CompileContract.RequiresCompanion then
    if not is(o.pc, T.LuaRT.Pc) then add(errors, path .. ".pc must be LuaRT.Pc") end
    if not member(o.kind, T.LuaRT.CompanionKind) then add(errors, path .. ".kind must be LuaRT.CompanionKind") end
  elseif cls == T.CompileContract.RequiresResolvedRegion then
    if not is(o.region, T.LuaExec.Name) then add(errors, path .. ".region must be LuaExec.Name") end
  elseif cls == T.CompileContract.RequiresContinuation then
    if not is(o.continuation, T.LuaExec.ContRef) then add(errors, path .. ".continuation must be LuaExec.ContRef") end
  end
end

local function validate_guarantee(errors, g, path)
  if not member(g, T.CompileContract.Guarantee) then
    add(errors, path .. " must be CompileContract.Guarantee")
    return
  end
  local cls = pvm.classof(g)
  if cls == T.CompileContract.GuaranteesFact then validate_fact_use(errors, g.fact, path .. ".fact")
  elseif cls == T.CompileContract.GuaranteesExec then
    if not member(g.guarantee, T.LuaExec.Guarantee) then add(errors, path .. ".guarantee must be LuaExec.Guarantee") end
  elseif cls == T.CompileContract.ProducesRuntimeValue then
    if not member(g.value, T.LuaRT.ValueRef) then add(errors, path .. ".value must be LuaRT.ValueRef") end
  elseif cls == T.CompileContract.PreservesRuntimeFrame then
    if not is(g.frame, T.LuaRT.FrameRef) then add(errors, path .. ".frame must be LuaRT.FrameRef") end
  elseif cls == T.CompileContract.UpdatesRuntimeTop then
    if not is(g.top, T.LuaRT.TopRef) then add(errors, path .. ".top must be LuaRT.TopRef") end
  end
end

function M.validate(contract)
  local errors = {}
  if not is(contract, T.CompileContract.Contract) then
    return false, { "expected CompileContract.Contract" }
  end
  if not is(contract.transfer, T.CompileContract.Transfer) then add(errors, "contract transfer must be CompileContract.Transfer") end
  for i, f in ipairs((contract.transfer and contract.transfer.facts) or {}) do
    validate_fact_use(errors, f, "transfer.facts[" .. i .. "]")
  end
  for i, p in ipairs((contract.transfer and contract.transfer.payloads) or {}) do
    validate_payload_use(errors, p, "transfer.payloads[" .. i .. "]")
  end
  for i, o in ipairs(contract.obligations or {}) do validate_obligation(errors, o, "obligations[" .. i .. "]") end
  for i, g in ipairs(contract.guarantees or {}) do validate_guarantee(errors, g, "guarantees[" .. i .. "]") end
  validate_deps(errors, contract.dependencies, "contract")
  return #errors == 0, errors
end

return M
