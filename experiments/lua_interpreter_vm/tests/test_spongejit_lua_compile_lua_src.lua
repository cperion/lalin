#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local Collect = require("lua_compile.lua_src_window_collect")
local Decode = require("lua_compile.lua_src_from_puc_decode")
local Validate = require("lua_compile.lua_src_validate")
local Slots = require("lua_compile.lua_src_slot_alias")
local Schema = require("lua_compile.schema")

local w = Collect.collect({ { op="LOADI", pc=1, a=1, b=42 }, { op="ADDI", pc=2, a=2, b=1, c=3 }, { op="NOPE", pc=3 } })
assert(#w.ops == 3)
assert(w.ops[1].kind == "LOADI")
assert(w.ops[2].kind == "ADDI")
assert(w.ops[3].kind == "UnsupportedOpcode")
local ok, errs = Validate.validate(w)
assert(ok, table.concat(errs, "\n"))
local inv = Slots.inventory(w)
assert(#inv == 2 and inv[1].id == 1 and inv[2].id == 2)
local function real_op_names()
  local T = Schema.get()
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

local names = real_op_names()
assert(#names == 85, "ASDL real LuaSrc.Op coverage count must be 85, got " .. tostring(#names))
local decode_count = 0
for _, name in ipairs(names) do
  assert(Decode.DECODER[name], "missing explicit decoder for " .. name)
  local op = Decode.decode(sample_event(name))
  assert(op.kind == name, "decoder for " .. name .. " produced " .. tostring(op.kind))
  decode_count = decode_count + 1
end
assert(decode_count == 85)

local addi_neg = Decode.decode({ op="ADDI", pc=1, a=1, b=1, c=126 })
assert(addi_neg.rhs.value == -1, "ADDI must decode signed sC, not raw C")
local addi_dumped = Decode.decode({ op="ADDI", pc=1, a=1, b=1, c=126, sc=-1 })
assert(addi_dumped.rhs.value == -1, "ADDI must prefer dumped signed sc")
local shli = Decode.decode({ op="SHLI", pc=1, a=1, b=2, c=124 })
assert(shli.lhs.value == -3 and shli.rhs.id == 2, "SHLI must decode sC << R[B]")
local eqi = Decode.decode({ op="EQI", pc=1, a=1, b=126, k=true })
assert(eqi.rhs.value == -1, "EQI must decode signed sB")
local jmp = Decode.decode({ op="JMP", pc=1, sj=-4, bx=999 })
assert(jmp.offset.value == -4, "JMP must decode signed sJ when present")
local settable_r = Decode.decode({ op="SETTABLE", pc=1, a=1, b=2, c=3, k=0 })
assert(settable_r.value.kind == "R" and settable_r.value.slot.id == 3, "numeric k=0 must not be treated as RK constant")
local settable_k = Decode.decode({ op="SETTABLE", pc=1, a=1, b=2, c=3, k=1 })
assert(settable_k.value.kind == "K" and settable_k.value.k.id == 3, "numeric k=1 must be treated as RK constant")
local nt = Decode.decode({ op="NEWTABLE", pc=1, a=1, b=63, c=255, vb=2, vc=9 })
assert(nt.array_hint.value == 2 and nt.hash_hint.value == 9, "ivABC opcodes must prefer vB/vC when dumped")

print("ok - SpongeJIT LuaCompile LuaSrc (decode coverage " .. decode_count .. "/85)")
