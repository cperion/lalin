-- lua_compile/validate.lua -- shared cross-layer invariants.

local Schema = require("lua_compile.schema")
local pvm = require("moonlift.pvm")
local T = Schema.get()

local M = {}

local FORBIDDEN_PHYSICAL = { gpr0 = true, rax = true, rcx = true, rdx = true, rdi = true, rsi = true, rsp = true, rbp = true, x64 = true }

local function add(errors, msg) errors[#errors + 1] = msg end
local function walk(v, fn, seen)
  if type(v) ~= "table" then fn(v); return end
  seen = seen or {}
  if seen[v] then return end
  seen[v] = true
  fn(v)
  local cls = pvm.classof(v)
  if cls and rawget(cls, "__fields") then
    for _, f in ipairs(cls.__fields) do walk(v[f.name], fn, seen) end
  elseif not cls then
    for _, x in pairs(v) do walk(x, fn, seen) end
  end
end

function M.no_physical_residency(node)
  local errors = {}
  walk(node, function(v)
    if type(v) == "string" and FORBIDDEN_PHYSICAL[v] then add(errors, "physical residency leaked into semantic product: " .. v) end
  end)
  return #errors == 0, errors
end

function M.lua_src_window(window)
  local errors = {}
  if pvm.classof(window) ~= T.LuaSrc.Window then add(errors, "expected LuaSrc.Window") end
  for i, op in ipairs((window and window.ops) or {}) do
    if not T.LuaSrc.Op.members[pvm.classof(op)] then add(errors, "window op " .. i .. " is not LuaSrc.Op") end
  end
  return #errors == 0, errors
end

function M.lua_fact_evidence(evidence)
  local errors = {}
  if pvm.classof(evidence) ~= T.LuaFact.Evidence then add(errors, "expected LuaFact.Evidence") end
  return #errors == 0, errors
end

function M.lua_sem_result(result)
  local errors = {}
  if not T.LuaSem.Result.members[pvm.classof(result)] then add(errors, "expected LuaSem.Result") end
  local ok, phys = M.no_physical_residency(result)
  for _, e in ipairs(phys) do add(errors, e) end
  return #errors == 0 and ok, errors
end

function M.lua_nf_program(nf)
  local errors = {}
  if pvm.classof(nf) ~= T.LuaNF.Program then add(errors, "expected LuaNF.Program") end
  local ok, phys = M.no_physical_residency(nf)
  for _, e in ipairs(phys) do add(errors, e) end
  return #errors == 0 and ok, errors
end

function M.lua_contract(contract)
  local errors = {}
  if pvm.classof(contract) ~= T.LuaContract.Contract then add(errors, "expected LuaContract.Contract") end
  return #errors == 0, errors
end

function M.moon_out_kernel(kernel)
  local errors = {}
  if pvm.classof(kernel) ~= T.MoonOut.Kernel then add(errors, "expected MoonOut.Kernel") end
  return #errors == 0, errors
end

return M
