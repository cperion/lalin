#!/usr/bin/env luajit
package.path = "./experiments/lua_interpreter_vm/spongejit/?.lua;./experiments/lua_interpreter_vm/spongejit/?/init.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Opt-in future completeness gate: this is intentionally stricter than the
-- main suite and is not part of the green implemented-slice gate until the
-- corresponding MoonCFG regions exist. It must never treat rejection as success.

local C = require("lua_compile")
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

local valid_cases = {
  { label = "generic ADD", events = { {op="ADD", pc=1, a=1, b=1, c=2}, {op="RETURN1", pc=2, a=1} } },
  { label = "generic GETTABLE", events = { {op="GETTABLE", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} } },
  { label = "generic SETTABLE", events = { {op="SETTABLE", pc=1, a=2, b=3, c=1, k=false} } },
  { label = "generic LEN", events = { {op="LEN", pc=1, a=1, b=2}, {op="RETURN1", pc=2, a=1} } },
  { label = "generic CONCAT", events = { {op="CONCAT", pc=1, a=1, b=2, c=3}, {op="RETURN1", pc=2, a=1} } },
  { label = "variable-count VARARG", events = { {op="VARARG", pc=1, a=1, c=0}, {op="RETURN", pc=2, a=1, b=0} } },
  { label = "multivalue RETURN", events = { {op="RETURN", pc=1, a=1, b=0} } },
  { label = "ERRNNIL runtime check", events = { {op="ERRNNIL", pc=1, a=1} } },
}

local red = {}
for _, case in ipairs(valid_cases) do
  local r = C.compile_to_moon_kernel(C.unit_from_events(case.events, case.evidence or {}))
  if r.kind ~= "Ok" then
    local reason = r.rejection and r.rejection.reason and r.rejection.reason.kind or tostring(r.kind)
    red[#red + 1] = case.label .. " -> " .. reason
  end
end

if #red > 0 then
  io.stderr:write("SpongeJIT LuaCompile completion is RED: valid Lua behavior still rejects\n")
  for _, line in ipairs(red) do io.stderr:write("  ", line, "\n") end
  error("LuaCompile lowering incomplete: valid Lua behavior rejected", 0)
end

print("ok - SpongeJIT LuaCompile completion (" .. #names .. "/" .. #names .. " opcode families; valid semantic fixtures compile)")
