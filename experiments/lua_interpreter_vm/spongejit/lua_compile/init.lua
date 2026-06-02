-- lua_compile/init.lua -- public facade for the SpongeJIT LuaCompile rewrite.

local M = {}

M.schema = require("lua_compile.schema")
M.builders = require("lua_compile.builders")
M.validate = require("lua_compile.validate")
M.diagnostics = require("lua_compile.diagnostics")
M.errors = require("lua_compile.errors")

M.lua_compile_unit = require("lua_compile.lua_compile_unit")
M.lua_compile_to_normal_form = require("lua_compile.lua_compile_to_normal_form")
M.lua_compile_to_moon_kernel = require("lua_compile.lua_compile_to_moon_kernel")
M.lua_compile_validate = require("lua_compile.lua_compile_validate")
M.moon_cfg_abi = require("lua_compile.moon_cfg_abi")
M.moon_cfg_validate = require("lua_compile.moon_cfg_validate")
M.moon_cfg_emit = require("lua_compile.moon_cfg_emit")
M.lua_nf_to_moon_cfg_lower = require("lua_compile.lua_nf_to_moon_cfg_lower")

function M.unit_from_events(events, observations)
  return M.lua_compile_unit.from_events(events, observations)
end

function M.compile_to_normal_form(unit)
  return M.lua_compile_to_normal_form.compile(unit)
end

function M.compile_to_moon_kernel(unit)
  return M.lua_compile_to_moon_kernel.compile(unit)
end

return M
