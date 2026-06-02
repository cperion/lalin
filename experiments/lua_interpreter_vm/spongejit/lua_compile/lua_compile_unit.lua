-- lua_compile_unit.lua -- LuaCompile.Unit construction.

local B = require("lua_compile.builders")
local Collect = require("lua_compile.lua_src_window_collect")
local FactObserve = require("lua_compile.lua_fact_from_runtime_observe")

local M = {}

function M.from_parts(source_window, evidence)
  return B.LuaCompile.Unit(source_window, evidence or B.empty_evidence())
end

function M.from_events(events, observations)
  local window = Collect.collect(events or {})
  local evidence = FactObserve.observe(observations or {})
  return M.from_parts(window, evidence)
end

return M
