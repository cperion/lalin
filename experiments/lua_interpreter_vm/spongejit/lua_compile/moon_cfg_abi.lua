-- moon_cfg_abi.lua -- typed MoonCFG parameter/type helpers.
--
-- Accepted LuaCompile kernels use these typed value parameters directly.  This
-- module intentionally exposes no out_tag/out_* semantic protocol ABI.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local CFG = T.MoonCFG
local NF = T.LuaNF

local M = {}

function M.name(s) return CFG.Name(tostring(s or "")) end
function M.ty(s) return CFG.TypeRef(tostring(s or "void")) end
function M.param(s, moon_type)
  return CFG.Param(M.name(s), M.ty(moon_type), CFG.ValueParam)
end

local function add_param(params, seen, name, moon_type)
  if not seen[name] then
    seen[name] = true
    params[#params + 1] = M.param(name, moon_type)
  end
end

function M.slot_i64_name(slot) return string.format("slot_%d_i64", tonumber(slot and slot.id or slot) or 0) end
function M.slot_f64_name(slot) return string.format("slot_%d_f64", tonumber(slot and slot.id or slot) or 0) end
function M.vararg_i64_name(base, index) return string.format("vararg_%d_%d_i64", tonumber(base and base.id or base) or 0, tonumber(index and index.value or index) or 0) end
function M.vararg_f64_name(base, index) return string.format("vararg_%d_%d_f64", tonumber(base and base.id or base) or 0, tonumber(index and index.value or index) or 0) end
function M.const_i64_name(k) return string.format("const_%d_i64", tonumber(k and k.id or k) or 0) end
function M.const_f64_name(k) return string.format("const_%d_f64", tonumber(k and k.id or k) or 0) end

local function walk(v, fn, seen)
  if type(v) ~= "table" then return end
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

local function is_src_slot_tvalue(v)
  return type(v) == "table" and pvm.classof(v) == NF.SrcSlotTValue
end

function M.params_for_nf(nf)
  local params, seen = {}, {}
  walk(nf, function(v)
    local cls = pvm.classof(v)
    if cls == NF.SrcSlotI64 then
      add_param(params, seen, M.slot_i64_name(v.slot), "i64")
    elseif cls == NF.ConstI64 then
      add_param(params, seen, M.const_i64_name(v.k), "i64")
    elseif cls == NF.UnboxI64 and is_src_slot_tvalue(v.value) then
      add_param(params, seen, M.slot_i64_name(v.value.slot), "i64")
    elseif cls == NF.VarargI64 then
      add_param(params, seen, M.vararg_i64_name(v.base, v.index), "i64")
    elseif cls == NF.ToF64 and is_src_slot_tvalue(v.value) then
      add_param(params, seen, M.slot_f64_name(v.value.slot), "f64")
    elseif cls == NF.ConstF64 then
      add_param(params, seen, M.const_f64_name(v.k), "f64")
    elseif cls == NF.VarargF64 then
      add_param(params, seen, M.vararg_f64_name(v.base, v.index), "f64")
    end
  end)
  return params
end

function M.default_params() return {} end

return M
