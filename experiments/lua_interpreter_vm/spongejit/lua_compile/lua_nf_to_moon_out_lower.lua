-- lua_nf_to_moon_out_lower.lua -- LuaNF.Program + LuaContract.Contract -> MoonOut.Kernel.

local B = require("lua_compile.builders")
local Out = B.MoonOut
local Abi = require("lua_compile.moon_out_abi")
local Projection = require("lua_compile.moon_out_projection")

local M = {}

local pvm = require("moonlift.pvm")

local function lower_value(nf, contract)
  local projections = {}
  for _, e in ipairs(nf.exits or {}) do projections[#projections + 1] = Projection.from_exit(e) end
  return Out.Kernel(Out.InlineSpan, Abi.params_for_nf(nf), nf, contract, projections)
end

local phase = pvm.phase("spongejit_lua_nf_to_moon_out_lower", function(nf, contract)
  return lower_value(nf, contract)
end)

function M.lower(nf, contract)
  return pvm.one(phase(nf, contract))
end

M.phase = phase
M.lower_uncached = lower_value

return M
