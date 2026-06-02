-- lua_compile_to_normal_form.lua -- LuaCompile.Unit -> NormalForm product.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local SemLower = require("lua_compile.lua_src_to_lua_sem_lower")
local NFNormalize = require("lua_compile.lua_sem_to_lua_nf_normalize")
local ContractDerive = require("lua_compile.lua_nf_to_lua_contract_derive")

local T = B.T
local M = {}

local function compile_value(unit)
  local sem = SemLower.lower(unit.source, unit.evidence)
  if pvm.classof(sem) == T.LuaSem.Rejected then return T.LuaCompile.Reject(sem.rejection) end
  local nf = NFNormalize.normalize(sem.program)
  local contract = ContractDerive.derive(nf)
  return T.LuaCompile.Ok(T.LuaCompile.NormalForm(nf, contract))
end

local phase = pvm.phase("spongejit_lua_compile_to_normal_form", function(unit)
  return compile_value(unit)
end)

function M.compile(unit)
  return pvm.one(phase(unit))
end

M.phase = phase
M.compile_uncached = compile_value

return M
