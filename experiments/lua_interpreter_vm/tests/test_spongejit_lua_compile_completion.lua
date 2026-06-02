#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Completion gate: this is intentionally stricter than the foundation suite.
-- Foundation tests prove the current PVM pipeline is honest and safe. This test
-- proves the lowering is complete. It must stay red until every required LuaSrc
-- opcode family has real semantic lowering instead of structured rejection.

local Schema = require("lua_compile.schema")
local Lower = require("lua_compile.lua_src_to_lua_sem_lower")
local T = Schema.get()

local names = {}
for cls in pairs(T.LuaSrc.Op.members) do
  local kind = cls.kind
  if kind and kind ~= "UnsupportedOpcode" then names[#names + 1] = kind end
end
table.sort(names)

local missing = {}
for _, name in ipairs(names) do
  if Lower.decision_for(name) == "reject" then missing[#missing + 1] = name end
end

if #missing > 0 then
  io.stderr:write("SpongeJIT LuaCompile completion is RED: ", tostring(#names - #missing), "/", tostring(#names), " opcode families lowered; ", tostring(#missing), " missing\n")
  io.stderr:write("Missing lowering:\n")
  for _, name in ipairs(missing) do io.stderr:write("  ", name, "\n") end
  error("LuaCompile lowering incomplete: " .. tostring(#missing) .. " opcode families still reject", 0)
end

print("ok - SpongeJIT LuaCompile completion (" .. #names .. "/" .. #names .. " opcode families lowered)")
