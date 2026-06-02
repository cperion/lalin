#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get({ fresh = true })

assert(T.LuaSrc and T.LuaFact and T.LuaRegion and T.LuaSem and T.LuaNF and T.LuaContract and T.LuaPlace and T.MoonCFG and T.MoonOut and T.LuaCompile)
local op = T.LuaSrc.ADDI(T.LuaSrc.Pc(1), T.LuaSrc.Slot(1), T.LuaSrc.Slot(1), T.LuaSrc.Imm(7))
assert(op.kind == "ADDI")
assert(pvm.classof(op) == T.LuaSrc.ADDI)
local evidence = T.LuaFact.Evidence({}, {}, T.LuaRegion.RegionSet({}))
assert(pvm.classof(evidence) == T.LuaFact.Evidence)
local upv = T.LuaNF.UpvalueTValue(T.LuaSrc.UpRef(0))
assert(upv.kind == "UpvalueTValue")
local barrier = T.LuaNF.BarrierAfterStore(T.LuaNF.UpvalueTValue(T.LuaSrc.UpRef(0)), T.LuaNF.NilTValue, T.LuaFact.BarrierPayload(T.LuaSrc.Pc(1), {}))
assert(barrier.payload.kind == "BarrierPayload")
local function field_names(cls)
  local out = {}
  for _, f in ipairs(cls.__fields or {}) do out[#out + 1] = f.name end
  return table.concat(out, ",")
end
assert(field_names(T.LuaNF.SlotWrite) == "slot,value", "LuaNF.SlotWrite fields must not be shadowed by StepWrite")
assert(field_names(T.LuaNF.FactGuard) == "subject,predicate,value_key,value,deps,exit", "LuaNF.FactGuard fields must preserve value_key and not be shadowed")
assert(field_names(T.LuaNF.ReturnExit) == "id,pc,value,projection", "LuaNF exits must not be shadowed by StepExit")
assert(T.MoonCFG.Kernel and T.MoonCFG.Region and T.MoonCFG.Block)
assert(T.MoonCFG.Let and T.MoonCFG.Return and T.MoonCFG.Primitive)
assert(field_names(T.MoonCFG.Kernel) == "id,kind,params,returns,body,contract")
assert(field_names(T.MoonCFG.Block) == "id,params,ops,terminator")
print("ok - SpongeJIT LuaCompile schema")
