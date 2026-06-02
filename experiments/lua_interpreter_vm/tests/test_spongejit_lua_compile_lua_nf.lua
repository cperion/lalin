#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local C = require("lua_compile")
local Key = require("lua_compile.lua_nf_key")
local Validate = require("lua_compile.lua_nf_validate")

local ops = {}
for i=1,4 do ops[#ops+1] = { op="ADDI", pc=i, a=1, b=1, c=128, sc=1 } end
local r = C.compile_to_normal_form(C.unit_from_events(ops, { { slot=1, predicate="is_i64" } }))
assert(r.kind == "Ok")
local nf = r.product.nf
local write
for _, s in ipairs(nf.steps) do if s.kind == "StepWrite" then assert(not write, "only one final write expected"); write = s.write end end
assert(write and write.value.kind == "BoxI64TValue")
assert(write.value.value.kind == "CanonAffineI64" and write.value.value.constant == 4)
assert(#write.value.value.terms == 1 and write.value.value.terms[1].atom.kind == "SrcSlotI64")
local ok, errs = Validate.validate(nf); assert(ok, table.concat(errs, "\n"))

local load7 = C.compile_to_normal_form(C.unit_from_events({ {op="LOADI",pc=1,a=1,b=7} }, {}))
local load8 = C.compile_to_normal_form(C.unit_from_events({ {op="LOADI",pc=1,a=1,b=8} }, {}))
assert(load7.kind == "Ok" and load8.kind == "Ok")
assert(Key.key(load7.product.nf) ~= Key.key(load8.product.nf), "LuaNF key must include nested write value fields")

local function return_value_key(events, observations)
  local rr = C.compile_to_normal_form(C.unit_from_events(events, observations))
  assert(rr.kind == "Ok")
  local exit = rr.product.nf.exits[#rr.product.nf.exits]
  return Key.key(exit.value)
end
local k1 = return_value_key({ {op="ADDI",pc=1,a=1,b=1,c=128,sc=1}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_i64"} })
local k2 = return_value_key({ {op="ADDK",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_i64"}, {const=2,predicate="const_i64",value=1} })
local k3 = return_value_key({ {op="LOADI",pc=1,a=2,b=1}, {op="ADD",pc=2,a=1,b=1,c=2}, {op="RETURN1",pc=3,a=1} }, { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"} })
assert(k1 == k2 and k2 == k3, "equivalent ADDI/ADDK/ADD return values should share LuaNF shape")

local function returned_value(events, observations)
  local rr = C.compile_to_normal_form(C.unit_from_events(events, observations))
  assert(rr.kind == "Ok")
  return rr.product.nf.exits[#rr.product.nf.exits].value
end
local function returned_i64(events, observations)
  local v = returned_value(events, observations)
  assert(v.kind == "BoxI64TValue", "expected i64 result, got " .. tostring(v.kind))
  return v.value
end
local obs_i64 = { {slot=1,predicate="is_i64"}, {slot=2,predicate="is_i64"}, {const=3,predicate="const_i64",value=3} }
assert(returned_i64({ {op="MULK",pc=1,a=1,b=1,c=3}, {op="RETURN1",pc=2,a=1} }, obs_i64).kind == "CanonMulI64")
assert(returned_i64({ {op="IDIV",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, obs_i64).kind == "CanonIDivI64")
assert(returned_i64({ {op="BAND",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, obs_i64).kind == "CanonBitAndI64")
local shl = returned_i64({ {op="SHL",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, obs_i64)
assert(shl.kind == "CanonShiftI64" and shl.op.kind == "Shl")
assert(returned_i64({ {op="UNM",pc=1,a=1,b=1}, {op="RETURN1",pc=2,a=1} }, obs_i64).kind == "CanonNegI64")
assert(returned_i64({ {op="BNOT",pc=1,a=1,b=1}, {op="RETURN1",pc=2,a=1} }, obs_i64).kind == "CanonBitNotI64")

local f64v = returned_value({ {op="DIV",pc=1,a=1,b=1,c=2}, {op="RETURN1",pc=2,a=1} }, { {slot=1,predicate="is_f64"}, {slot=2,predicate="is_f64"} })
assert(f64v.kind == "BoxF64TValue" and f64v.value.kind == "DivF64", "f64 DIV normalization must preserve expression")

local function field_obs(slot, pc, key)
  return {
    { slot=slot, predicate="is_table" }, { slot=slot, predicate="shape_eq", shape_key="s" },
    { slot=slot, predicate="metatable_absent", shape_key="s" }, { slot=slot, predicate="field_offset", shape_key="s", key=key },
    { slot=slot, payload="shape", pc=pc, shape_key="s" }, { slot=slot, payload="field", key=key, pc=pc, shape_key="s" },
  }
end
local function array_obs(slot, pc)
  return {
    { slot=slot, predicate="is_table" }, { slot=slot, predicate="array_hit" },
    { slot=slot, predicate="bounds_ok" }, { slot=slot, predicate="array_base_offset" },
    { slot=slot, payload="array", pc=pc },
  }
end
assert(returned_value({ {op="NOT",pc=1,a=1,b=2}, {op="RETURN1",pc=2,a=1} }, {}).kind == "BoolExprTValue")
assert(returned_value({ {op="GETUPVAL",pc=1,a=1,b=0}, {op="RETURN1",pc=2,a=1} }, {}).kind == "UpvalueTValue")
assert(returned_value({ {op="GETFIELD",pc=1,a=1,b=2,c=3}, {op="RETURN1",pc=2,a=1} }, field_obs(2, 1, 3)).kind == "FieldTValue")
assert(returned_value({ {op="GETTABUP",pc=1,a=1,b=0,c=3}, {op="RETURN1",pc=2,a=1} }, {
  { up=0, predicate="is_table" }, { up=0, predicate="shape_eq", shape_key="s" }, { up=0, predicate="metatable_absent", shape_key="s" }, { up=0, predicate="field_offset", shape_key="s", key=3 },
  { up=0, payload="shape", pc=1, shape_key="s" }, { up=0, payload="field", key=3, pc=1, shape_key="s" },
}).kind == "FieldTValue")
assert(returned_value({ {op="GETI",pc=1,a=1,b=2,c=5}, {op="RETURN1",pc=2,a=1} }, array_obs(2, 1)).kind == "ArrayTValue")
local gettable_array_obs = array_obs(2, 1); gettable_array_obs[#gettable_array_obs + 1] = { slot=3, predicate="is_i64" }
assert(returned_value({ {op="GETTABLE",pc=1,a=1,b=2,c=3}, {op="RETURN1",pc=2,a=1} }, gettable_array_obs).kind == "ArrayTValue")
local self_r = C.compile_to_normal_form(C.unit_from_events({ {op="SELF",pc=1,a=1,b=2,c=3} }, field_obs(2, 1, 3)))
assert(self_r.kind == "Ok")
local saw_method, saw_receiver = false, false
for _, step in ipairs(self_r.product.nf.steps) do
  if step.kind == "StepWrite" and step.write.slot and step.write.slot.id == 1 and step.write.value.kind == "FieldTValue" then saw_method = true end
  if step.kind == "StepWrite" and step.write.slot and step.write.slot.id == 2 and step.write.value.kind == "SrcSlotTValue" then saw_receiver = true end
end
assert(saw_method and saw_receiver, "SELF must write method to A and receiver to A+1")

print("ok - SpongeJIT LuaCompile LuaNF")
