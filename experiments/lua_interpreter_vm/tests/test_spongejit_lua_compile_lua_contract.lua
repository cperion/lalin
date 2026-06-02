#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local Validate = require("lua_compile.lua_contract_validate")
local T = require("lua_compile.schema").get()

local r = C.compile_to_normal_form(C.unit_from_events({ {op="ADDI",pc=1,a=1,b=1,c=128,sc=1} }, { {slot=1,predicate="is_i64"} }))
assert(r.kind == "Ok")
local contract = r.product.contract
local ok, errs = Validate.validate(contract); assert(ok, table.concat(errs, "\n"))
local checked, killed, produced, projections = false, false, false, #contract.projections
for _, fu in ipairs(contract.transfer.facts) do
  if fu.role == T.LuaContract.Checked and fu.predicate == T.LuaFact.IsI64 then checked = true end
  if fu.role == T.LuaContract.Killed and fu.predicate == T.LuaFact.IsI64 then killed = true end
  if fu.role == T.LuaContract.Produced and fu.predicate == T.LuaFact.IsI64 then produced = true end
end
assert(checked, "guard success must check facts")
assert(killed and produced, "slot write must kill/replace facts")
assert(projections > 0, "guard failure must carry projection obligations")

local ret = C.compile_to_normal_form(C.unit_from_events({ {op="RETURN1",pc=9,a=0} }, {}))
assert(ret.kind == "Ok")
assert(#ret.product.contract.projections == #ret.product.nf.exits, "contract must not duplicate projection obligations")

local field_obs = {
  { slot=1, predicate="is_i64" }, { slot=2, predicate="is_table" }, { slot=2, predicate="shape_eq", shape_key="s" },
  { slot=2, predicate="metatable_absent", shape_key="s" }, { slot=2, predicate="field_offset", shape_key="s", key=3 }, { slot=2, predicate="barrier_clean" },
  { slot=2, payload="shape", pc=1, shape_key="s", deps={"shape_epoch"} }, { slot=2, payload="field", key=3, pc=1, shape_key="s", deps={"table_epoch"} }, { payload="barrier", pc=1, deps={"gc_barrier_protocol"} },
}
local wr = C.compile_to_normal_form(C.unit_from_events({ {op="SETFIELD",pc=1,a=2,b=3,c=1,k=false} }, field_obs))
assert(wr.kind == "Ok")
assert(#wr.product.contract.transfer.payloads >= 3, "field write contract must preserve shape/field/barrier payload uses")
local killed_barrier = false
for _, fu in ipairs(wr.product.contract.transfer.facts) do
  if fu.role == T.LuaContract.Killed and fu.predicate == T.LuaFact.BarrierClean then killed_barrier = true end
end
assert(killed_barrier, "table writes must expose barrier/fact invalidation")
local deps_seen = {}
for _, d in ipairs(wr.product.contract.dependencies or {}) do deps_seen[d.kind] = true end
assert(deps_seen.ShapeEpoch and deps_seen.TableEpoch and deps_seen.GcBarrierProtocol, "payload dependencies must survive contract derivation")
for _, fu in ipairs(wr.product.contract.transfer.facts) do
  if fu.role == T.LuaContract.Required and (fu.predicate == T.LuaFact.ShapeEq or fu.predicate == T.LuaFact.MetatableAbsent or fu.predicate == T.LuaFact.FieldOffset) then
    assert(fu.value_key ~= "", "keyed table predicate must preserve value_key in contract: " .. fu.predicate.kind)
  end
end

local up = C.compile_to_normal_form(C.unit_from_events({ {op="SETUPVAL",pc=1,a=1,b=0} }, { {slot=1,predicate="is_i64"} }))
assert(up.kind == "Ok")
local killed_up = false
for _, fu in ipairs(up.product.contract.transfer.facts) do
  if fu.role == T.LuaContract.Killed and fu.subject.kind == "Upvalue" then killed_up = true end
end
assert(killed_up, "upvalue write contract must expose upvalue fact kills")

local array_obs = {
  { slot=1, predicate="is_i64" }, { slot=2, predicate="is_table" }, { slot=2, predicate="array_hit" },
  { slot=2, predicate="bounds_ok" }, { slot=2, predicate="array_base_offset" }, { slot=2, predicate="barrier_clean" },
  { slot=2, payload="array", pc=1 }, { payload="barrier", pc=1 }, { slot=3, predicate="is_i64" },
}
assert(C.compile_to_normal_form(C.unit_from_events({ {op="SETI",pc=1,a=2,b=5,c=1,k=false} }, array_obs)).kind == "Ok", "SETI must lower with array proofs")
assert(C.compile_to_normal_form(C.unit_from_events({ {op="SETTABLE",pc=1,a=2,b=3,c=1,k=false} }, array_obs)).kind == "Ok", "SETTABLE array-key path must lower with array/key proofs")
local up_field_obs = {
  { slot=1, predicate="is_i64" }, { up=0, predicate="is_table" }, { up=0, predicate="shape_eq", shape_key="s" },
  { up=0, predicate="metatable_absent", shape_key="s" }, { up=0, predicate="field_offset", shape_key="s", key=3 }, { up=0, predicate="barrier_clean" },
  { up=0, payload="shape", pc=1, shape_key="s" }, { up=0, payload="field", key=3, pc=1, shape_key="s" }, { payload="barrier", pc=1 },
}
assert(C.compile_to_normal_form(C.unit_from_events({ {op="SETTABUP",pc=1,a=0,b=3,c=1,k=false} }, up_field_obs)).kind == "Ok", "SETTABUP must lower with upvalue field proofs")
print("ok - SpongeJIT LuaCompile LuaContract")
