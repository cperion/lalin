-- lua_compile_to_moon_kernel.lua -- LuaCompile.Unit -> MoonKernel product.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local ToNF = require("lua_compile.lua_compile_to_normal_form")
local MoonLower = require("lua_compile.lua_nf_to_moon_cfg_lower")
local T = B.T

local M = {}

local function compile_value(unit)
  local r = ToNF.compile(unit)
  if pvm.classof(r) == T.LuaCompile.Reject then return r end
  local product = r.product
  local kernel, lower_errors = MoonLower.lower(product.nf, product.contract)
  if not kernel then
    return T.LuaCompile.Reject(MoonLower.rejection_for(product.nf, lower_errors))
  end
  return T.LuaCompile.Ok(T.LuaCompile.MoonKernel(kernel))
end

local phase = pvm.phase("spongejit_lua_compile_to_moon_kernel", function(unit)
  return compile_value(unit)
end)

function M.compile(unit)
  return pvm.one(phase(unit))
end

M.phase = phase
M.compile_uncached = compile_value

return M
