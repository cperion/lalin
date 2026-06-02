#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Collect = require("lua_compile.lua_src_window_collect")
local Observe = require("lua_compile.lua_fact_from_runtime_observe")
local Foundry = require("lua_compile.lua_fact_from_foundry_bundle")
local Lower = require("lua_compile.lua_src_to_lua_sem_lower")
local Validate = require("lua_compile.lua_sem_validate")
local Schema = require("lua_compile.schema")
local T = Schema.get()

local sem = Lower.lower(Collect.collect({ { op="ADDI", pc=1, a=1, b=1, c=129, sc=2 } }), Observe.observe({ { slot=1, predicate="is_i64" } }))
assert(sem.kind == "Accepted")
assert(#sem.program.effects == 2, "guard observation + write expected")
local ok, errs = Validate.validate(sem); assert(ok, table.concat(errs, "\n"))
local bad = Lower.lower(Collect.collect({ { op="ADDI", pc=1, a=1, b=1, c=129, sc=2 } }), Observe.observe({}))
assert(bad.kind == "Rejected" and bad.rejection.reason == T.LuaSem.MissingFact)
local call_sem = Lower.lower(Collect.collect({ { op="CALL", pc=3, a=0, b=1, c=1 } }), Observe.observe({}))
assert(call_sem.kind == "Accepted" and call_sem.program.effects[1].observation.kind == "CallProtocolObservation", "CALL must lower to an explicit call protocol, not a fake boundary")
local function real_op_names()
  local names = {}
  for cls in pairs(T.LuaSrc.Op.members) do
    local kind = cls.kind
    if kind and kind ~= "UnsupportedOpcode" then names[#names + 1] = kind end
  end
  table.sort(names)
  return names
end

local function sample_event(name)
  return { op=name, name=name, pc=1, a=1, b=2, c=3, k=false, bx=1, sbx=1, ax=1, binop="ADD" }
end

local all_evidence = Observe.observe({
  { slot=1, predicate="is_i64" }, { slot=2, predicate="is_i64" }, { slot=3, predicate="is_i64" },
  { const=1, predicate="const_i64", value=1 }, { const=2, predicate="const_i64", value=2 }, { const=3, predicate="const_i64", value=3 },
})
local decision_total, accepted_count = 0, 0
local ledger = { semantic = 0, reject = 0 }
for _, name in ipairs(real_op_names()) do
  local decision = Lower.decision_for(name)
  assert(decision, "missing semantic decision for " .. name)
  assert(ledger[decision] ~= nil, "bad decision kind for " .. name .. ": " .. tostring(decision))
  ledger[decision] = ledger[decision] + 1
  local result = Lower.lower(Collect.collect({ sample_event(name) }), all_evidence)
  assert(result.kind == "Accepted" or result.kind == "Rejected", "bad semantic result for " .. name)
  if result.kind == "Accepted" then
    accepted_count = accepted_count + 1
  end
  decision_total = decision_total + 1
end
assert(decision_total == 85)
assert(accepted_count > 0, "semantic test fixtures must include real accepted lowering")

local missing = Lower.lower(Collect.collect({ { op="MUL", pc=9, a=1, b=1, c=2 } }), Observe.observe({ { slot=1, predicate="is_i64" } }))
assert(missing.kind == "Rejected" and missing.rejection.reason == T.LuaSem.MissingFact, "missing RHS i64 evidence must reject")
local idiv = Lower.lower(Collect.collect({ { op="IDIV", pc=9, a=1, b=1, c=2 } }), Observe.observe({ { slot=1, predicate="is_i64" }, { slot=2, predicate="is_i64" } }))
assert(idiv.kind == "Accepted", "IDIV must lower with i64 evidence")
local saw_nonzero = false
for _, eff in ipairs(idiv.program.effects or {}) do
  if eff.kind == "Observe" and eff.observation.kind == "GuardObservation" and eff.observation.guard.kind == "I64NonZeroGuard" then saw_nonzero = true end
end
assert(saw_nonzero, "IDIV/MOD lowering must guard zero divisor explicitly")
local table_op = Lower.lower(Collect.collect({ { op="GETTABLE", pc=10, a=1, b=2, c=3 } }), Observe.observe({}))
assert(table_op.kind == "Rejected" and (table_op.rejection.reason == T.LuaSem.MissingFact or table_op.rejection.reason == T.LuaSem.MissingPayloadLease), "table ops must reject with structured missing proof/lease, not boundary")

local function field_obs(slot, pc, key)
  return {
    { slot=slot, predicate="is_table" }, { slot=slot, predicate="shape_eq", shape_key="s" },
    { slot=slot, predicate="metatable_absent", shape_key="s" }, { slot=slot, predicate="field_offset", shape_key="s", key=key },
    { slot=slot, payload="shape", pc=pc, shape_key="s" }, { slot=slot, payload="field", key=key, pc=pc, shape_key="s" },
  }
end
local getfield = Lower.lower(Collect.collect({ { op="GETFIELD", pc=20, a=1, b=2, c=3 } }), Observe.observe(field_obs(2, 20, 3)))
assert(getfield.kind == "Accepted", "GETFIELD with field proofs must lower")
local miss_field = Lower.lower(Collect.collect({ { op="GETFIELD", pc=21, a=1, b=2, c=3 } }), Observe.observe({ { slot=2, predicate="is_table" } }))
assert(miss_field.kind == "Rejected" and (miss_field.rejection.reason == T.LuaSem.MissingFact or miss_field.rejection.reason == T.LuaSem.MissingPayloadLease))
local notv = Lower.lower(Collect.collect({ { op="NOT", pc=22, a=1, b=2 } }), Observe.observe({}))
assert(notv.kind == "Accepted", "NOT must lower to dynamic bool TValue")
local concat = Lower.lower(Collect.collect({ { op="CONCAT", pc=22, a=1, b=2, c=3 } }), Observe.observe({ { slot=2, predicate="is_string" }, { slot=3, predicate="is_string" } }))
assert(concat.kind == "Accepted" and Lower.decision_for("CONCAT") == "semantic", "CONCAT must lower on proven string fast path")
local missing_concat = Lower.lower(Collect.collect({ { op="CONCAT", pc=22, a=1, b=2, c=3 } }), Observe.observe({ { slot=2, predicate="is_string" } }))
assert(missing_concat.kind == "Rejected" and missing_concat.rejection.reason == T.LuaSem.MissingFact, "CONCAT must reject without string proof for every source")
local testset = Lower.lower(Collect.collect({ { op="TESTSET", pc=22, a=1, b=2, k=true } }), Observe.observe({}))
assert(testset.kind == "Accepted" and Lower.decision_for("TESTSET") == "semantic", "TESTSET must lower to conditional copy/branch semantics")
assert(testset.program.effects[1].observation.kind == "TestSetObservation", "TESTSET must not lower as a fake boundary or plain unconditional write")
local up = Lower.lower(Collect.collect({ { op="GETUPVAL", pc=23, a=1, b=0 }, { op="SETUPVAL", pc=24, a=1, b=0 } }), Observe.observe({}))
assert(up.kind == "Accepted", "upvalue read/write must lower semantically")
local mmb_bad = Lower.lower(Collect.collect({ { op="MMBINI", pc=25, a=1, sb=1, binop="ADD" } }), Observe.observe({}))
assert(mmb_bad.kind == "Rejected" and mmb_bad.rejection.reason == T.LuaSem.UnsupportedSemanticCase, "MMBIN* is no-op only as an immediate typed-arithmetic companion")
local varargprep = Lower.lower(Collect.collect({ { op="VARARGPREP", pc=26, a=2 } }), Observe.observe({}))
assert(varargprep.kind == "Accepted" and #varargprep.program.effects == 0, "VARARGPREP alone is frame metadata; VARARG/GETVARG carry actual reads")

local function assert_accept(events, evidence, label)
  local r = Lower.lower(Collect.collect(events), evidence)
  assert(r.kind == "Accepted", label .. " must accept, got " .. tostring(r.kind) .. " " .. tostring(r.rejection and r.rejection.reason and r.rejection.reason.kind))
  return r
end
local function assert_reject(events, evidence, label)
  local r = Lower.lower(Collect.collect(events), evidence)
  assert(r.kind == "Rejected", label .. " must reject structurally")
  return r
end
local function runtime_field_evidence(slot, pc, key, barrier)
  local obs = {
    { slot=slot, payload="shape", pc=pc, shape_key="shape" .. slot },
    { slot=slot, predicate="metatable_absent", shape_key="shape" .. slot },
    { slot=slot, payload="field", key=key, pc=pc, shape_key="shape" .. slot },
  }
  if barrier then obs[#obs + 1] = { slot=slot, predicate="barrier_clean" }; obs[#obs + 1] = { payload="barrier", pc=pc } end
  return Observe.observe(obs)
end
local function runtime_array_evidence(slot, pc, barrier)
  local obs = {
    { slot=slot, payload="array", pc=pc },
    { slot=slot, predicate="bounds_ok" },
  }
  if barrier then obs[#obs + 1] = { slot=slot, predicate="barrier_clean" }; obs[#obs + 1] = { payload="barrier", pc=pc } end
  return Observe.observe(obs)
end
local function foundry_field_evidence(subject, pc, key, barrier)
  local facts = { { subject=subject, predicate="metatable_absent", shape_key="shapeF" } }
  if barrier then facts[#facts + 1] = { subject=subject, predicate="barrier_clean" } end
  local payloads = {
    { subject=subject, payload="shape", pc=pc, shape_key="shapeF" },
    { subject=subject, payload="field", key=key, pc=pc, shape_key="shapeF" },
  }
  if barrier then payloads[#payloads + 1] = { payload="barrier", pc=pc } end
  return Foundry.from_bundle({ facts=facts, payloads=payloads })
end
local function foundry_array_evidence(slot, pc, barrier)
  local facts = { { subject={kind="slot", id="R" .. slot}, predicate="bounds_ok" } }
  if barrier then facts[#facts + 1] = { subject={kind="slot", id="R" .. slot}, predicate="barrier_clean" } end
  local payloads = { { subject={kind="slot", id="R" .. slot}, payload="array", pc=pc } }
  if barrier then payloads[#payloads + 1] = { payload="barrier", pc=pc } end
  return Foundry.from_bundle({ facts=facts, payloads=payloads })
end

-- Evidence behavior: all table/upvalue op lowerings are driven from runtime or foundry import boundaries.
assert_accept({ {op="GETFIELD",pc=30,a=1,b=2,c=3} }, runtime_field_evidence(2, 30, 3), "runtime GETFIELD")
assert_accept({ {op="GETI",pc=31,a=1,b=2,c=5} }, runtime_array_evidence(2, 31), "runtime GETI")
local rt_gettable = runtime_array_evidence(2, 32); rt_gettable = Observe.observe({
  { slot=2, payload="array", pc=32 }, { slot=2, predicate="bounds_ok" }, { slot=3, predicate="is_i64" },
})
assert_accept({ {op="GETTABLE",pc=32,a=1,b=2,c=3} }, rt_gettable, "runtime GETTABLE array")
assert_accept({ {op="GETTABUP",pc=33,a=1,b=0,c=3} }, Foundry.from_bundle({ facts={ {subject={kind="upvalue", id="U0"}, predicate="metatable_absent", shape_key="shapeF"} }, payloads={ {subject={kind="upvalue", id="U0"}, payload="shape", pc=33, shape_key="shapeF"}, {subject={kind="upvalue", id="U0"}, payload="field", key=3, pc=33, shape_key="shapeF"} } }), "foundry GETTABUP")
assert_accept({ {op="SETFIELD",pc=34,a=2,b=3,c=1,k=false} }, runtime_field_evidence(2, 34, 3, true), "runtime SETFIELD")
local rt_seti = Observe.observe({ {slot=1,predicate="is_i64"}, {slot=2,payload="array",pc=35}, {slot=2,predicate="bounds_ok"}, {slot=2,predicate="barrier_clean"}, {payload="barrier",pc=35} })
assert_accept({ {op="SETI",pc=35,a=2,b=5,c=1,k=false} }, rt_seti, "runtime SETI")
local fd_settable = Foundry.from_bundle({ facts={ {subject={kind="slot", id="R1"}, predicate="is_i64"}, {subject={kind="slot", id="R2"}, predicate="bounds_ok"}, {subject={kind="slot", id="R2"}, predicate="barrier_clean"}, {subject={kind="slot", id="R3"}, predicate="is_i64"} }, payloads={ {subject={kind="slot", id="R2"}, payload="array", pc=36}, {payload="barrier", pc=36} } })
assert_accept({ {op="SETTABLE",pc=36,a=2,b=3,c=1,k=false} }, fd_settable, "foundry SETTABLE array")
assert_accept({ {op="SETTABUP",pc=37,a=0,b=3,c=1,k=false} }, foundry_field_evidence({kind="upvalue", id="U0"}, 37, 3, true), "foundry SETTABUP")
assert_accept({ {op="SETUPVAL",pc=38,a=1,b=0} }, Observe.observe({ {slot=1,predicate="is_i64"} }), "runtime SETUPVAL")
assert_accept({ {op="SELF",pc=39,a=1,b=2,c=3} }, foundry_field_evidence({kind="slot", id="R2"}, 39, 3), "foundry SELF")

local mismatched = Observe.observe({
  { slot=2, payload="shape", pc=40, shape_key="s1" },
  { slot=2, predicate="metatable_absent", shape_key="s1" },
  { slot=2, payload="field", key=3, pc=40, shape_key="s2" },
})
assert_reject({ {op="GETFIELD",pc=40,a=1,b=2,c=3} }, mismatched, "mismatched field shape payload")
assert_reject({ {op="SETFIELD",pc=41,a=2,b=3,c=1,k=false} }, runtime_field_evidence(2, 41, 3, false), "missing barrier evidence for field write")
assert_reject({ {op="GETI",pc=42,a=1,b=2,c=5} }, Observe.observe({ {slot=2,payload="array",pc=42} }), "missing bounds fact for array read")

print("ok - SpongeJIT LuaCompile LuaSem")
