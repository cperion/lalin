-- lua_nf_to_moon_cfg_lower.lua -- LuaNF.Program + LuaContract -> MoonCFG.Kernel.
--
-- First honest slice: lower only self-contained scalar return kernels into an
-- explicit single-block MoonCFG.  Unsupported Lua behavior rejects; it is not
-- translated into protocol/out_tag success.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local NF, CFG = T.LuaNF, T.MoonCFG
local Src, Sem = T.LuaSrc, T.LuaSem
local Abi = require("lua_compile.moon_cfg_abi")

local M = {}

local FORBIDDEN_PROTOCOL_EXITS = {
  [NF.CallProtocolExit] = "CallProtocolExit",
  [NF.CloseProtocolExit] = "CloseProtocolExit",
  [NF.GenericForProtocolExit] = "GenericForProtocolExit",
  [NF.SetListProtocolExit] = "SetListProtocolExit",
  [NF.GetVargProtocolExit] = "GetVargProtocolExit",
}

local function cfg_name(s) return CFG.Name(tostring(s)) end
local function type_ref(s) return CFG.TypeRef(tostring(s)) end
local function const_i64(n) return CFG.ConstValue(CFG.I64Const(tonumber(n) or 0)) end
local function const_f64(n) return CFG.ConstValue(CFG.F64Const(tonumber(n) or 0)) end
local function const_bool(b) return CFG.ConstValue(CFG.BoolConst(b == true)) end

local function new_state()
  return { next_temp = 1, ops = {}, errors = {} }
end

local function add_error(state, msg)
  state.errors[#state.errors + 1] = msg
  return nil
end

local function temp_place(state, prefix)
  local id = state.next_temp
  state.next_temp = id + 1
  return CFG.Temp(cfg_name((prefix or "tmp") .. tostring(id)))
end

local function let_primitive(state, prefix, op, args)
  local place = temp_place(state, prefix)
  state.ops[#state.ops + 1] = CFG.Let(place, CFG.Primitive(op, args or {}))
  return CFG.PlaceValue(place)
end

local function i64_atom(state, atom)
  local cls = pvm.classof(atom)
  if cls == NF.SrcSlotI64 then
    return CFG.ParamValue(cfg_name(Abi.slot_i64_name(atom.slot)))
  elseif cls == NF.ImmI64 then
    return const_i64(atom.imm and atom.imm.value or 0)
  elseif cls == NF.ConstI64 then
    return CFG.ParamValue(cfg_name(Abi.const_i64_name(atom.k)))
  elseif cls == NF.UnboxI64 and atom.value and pvm.classof(atom.value) == NF.SrcSlotTValue then
    return CFG.ParamValue(cfg_name(Abi.slot_i64_name(atom.value.slot)))
  elseif cls == NF.VarargI64 then
    return CFG.ParamValue(cfg_name(Abi.vararg_i64_name(atom.base, atom.index)))
  end
  return add_error(state, "unsupported_i64_atom:" .. tostring(atom and atom.kind))
end

local lower_i64
local function scaled_i64_term(state, term)
  local v = i64_atom(state, term.atom)
  if not v then return nil end
  local c = tonumber(term.coefficient) or 0
  if c == 1 then return v end
  return let_primitive(state, "mul", CFG.MulI64, { const_i64(c), v })
end

function lower_i64(state, x)
  local cls = pvm.classof(x)
  if cls == NF.CanonAffineI64 then
    local parts = {}
    if (tonumber(x.constant) or 0) ~= 0 or #(x.terms or {}) == 0 then parts[#parts + 1] = const_i64(x.constant or 0) end
    for _, term in ipairs(x.terms or {}) do
      local v = scaled_i64_term(state, term)
      if not v then return nil end
      parts[#parts + 1] = v
    end
    if #parts == 1 then return parts[1] end
    return let_primitive(state, "add", CFG.AddI64, parts)
  elseif cls == NF.CanonMulI64 then
    local lhs, rhs = lower_i64(state, x.lhs), lower_i64(state, x.rhs)
    if lhs and rhs then return let_primitive(state, "mul", CFG.MulI64, { lhs, rhs }) end
  elseif cls == NF.CanonIDivI64 then
    local lhs, rhs = lower_i64(state, x.lhs), lower_i64(state, x.rhs)
    if lhs and rhs then return let_primitive(state, "idiv", CFG.IDivI64, { lhs, rhs }) end
  elseif cls == NF.CanonModI64 then
    local lhs, rhs = lower_i64(state, x.lhs), lower_i64(state, x.rhs)
    if lhs and rhs then return let_primitive(state, "mod", CFG.ModI64, { lhs, rhs }) end
  end
  return add_error(state, "unsupported_i64:" .. tostring(x and x.kind))
end

local function lower_f64(state, x)
  local cls = pvm.classof(x)
  if cls == NF.ImmF64 then
    return const_f64(x.imm and x.imm.value or 0)
  elseif cls == NF.ConstF64 then
    return CFG.ParamValue(cfg_name(Abi.const_f64_name(x.k)))
  elseif cls == NF.ToF64 and x.value and pvm.classof(x.value) == NF.SrcSlotTValue then
    return CFG.ParamValue(cfg_name(Abi.slot_f64_name(x.value.slot)))
  elseif cls == NF.VarargF64 then
    return CFG.ParamValue(cfg_name(Abi.vararg_f64_name(x.base, x.index)))
  elseif cls == NF.I64ToF64 then
    local v = lower_i64(state, x.value)
    if v then
      local place = temp_place(state, "f")
      state.ops[#state.ops + 1] = CFG.Let(place, CFG.Convert(type_ref("f64"), v))
      return CFG.PlaceValue(place)
    end
  elseif cls == NF.DivF64 then
    local lhs, rhs = lower_f64(state, x.lhs), lower_f64(state, x.rhs)
    if lhs and rhs then return let_primitive(state, "divf", CFG.DivF64, { lhs, rhs }) end
  end
  return add_error(state, "unsupported_f64:" .. tostring(x and x.kind))
end

local function lower_tvalue_for_return(state, value)
  local cls = pvm.classof(value)
  if cls == NF.BoxI64TValue then
    return lower_i64(state, value.value), "i64"
  elseif cls == NF.BoxF64TValue then
    return lower_f64(state, value.value), "f64"
  elseif cls == NF.BoolTValue then
    return const_bool(value.value), "bool"
  elseif cls == NF.BoolExprTValue then
    return add_error(state, "unsupported_return_bool_expr"), nil
  elseif cls == NF.NilTValue then
    return nil, "void"
  end
  return add_error(state, "unsupported_return_tvalue:" .. tostring(value and value.kind)), nil
end

local function terminal_exit(nf)
  for _, step in ipairs(nf.steps or {}) do
    if pvm.classof(step) == NF.StepExit then return step.exit end
  end
  return nil
end

local function scan_forbidden(nf)
  local errors = {}
  local function walk(v, seen)
    if type(v) ~= "table" then return end
    seen = seen or {}; if seen[v] then return end; seen[v] = true
    local cls = pvm.classof(v)
    if FORBIDDEN_PROTOCOL_EXITS[cls] then errors[#errors + 1] = "forbidden_protocol_exit:" .. FORBIDDEN_PROTOCOL_EXITS[cls] end
    if cls and rawget(cls, "__fields") then
      for _, f in ipairs(cls.__fields) do walk(v[f.name], seen) end
    elseif not cls then
      for _, x in pairs(v) do walk(x, seen) end
    end
  end
  walk(nf)
  return errors
end

local function lower_value(nf, contract)
  local forbidden = scan_forbidden(nf)
  if #forbidden > 0 then return nil, forbidden end

  for _, step in ipairs(nf.steps or {}) do
    if pvm.classof(step) == NF.StepGuard then
      local gcls = pvm.classof(step.guard)
      if gcls ~= NF.FactGuard and gcls ~= NF.BoundsGuard then
        return nil, { "unsupported_guard:" .. tostring(step.guard and step.guard.kind) }
      end
    elseif pvm.classof(step) == NF.StepWrite or pvm.classof(step) == NF.StepBarrier then
      return nil, { "unsupported_non_terminal_effect:" .. tostring(step.kind) }
    end
  end

  local exit = terminal_exit(nf)
  if not exit then return nil, { "unsupported_no_terminal_return" } end
  local state = new_state()
  local returns, values = {}, {}
  local ecls = pvm.classof(exit)
  if ecls == NF.ReturnExit then
    local v, ty = lower_tvalue_for_return(state, exit.value)
    if not v or not ty then return nil, state.errors end
    returns = { type_ref(ty) }
    values = { v }
  elseif ecls == NF.Return0Exit then
    returns = {}
    values = {}
  else
    return nil, { "unsupported_terminal_exit:" .. tostring(exit and exit.kind) }
  end
  if #state.errors > 0 then return nil, state.errors end

  local kid = CFG.KernelId(cfg_name("lua_compile_kernel"))
  local rid = CFG.RegionId(cfg_name("lua_compile_kernel_body"))
  local bid = CFG.BlockId(cfg_name("entry"))
  local block = CFG.Block(bid, {}, state.ops, CFG.Return(values))
  local region = CFG.Region(rid, Abi.params_for_nf(nf), {}, bid, { block })
  local kernel = CFG.Kernel(kid, CFG.InlineSpan, Abi.params_for_nf(nf), returns, region, contract)
  return kernel, nil
end

local phase = pvm.phase("spongejit_lua_nf_to_moon_cfg_lower", function(nf, contract)
  local kernel, errors = lower_value(nf, contract)
  if not kernel then error("MoonCFG lower unsupported inside cached phase: " .. table.concat(errors or {}, "; ")) end
  return kernel
end)

function M.lower(nf, contract)
  local kernel, errors = lower_value(nf, contract)
  if not kernel then return nil, errors end
  return pvm.one(phase(nf, contract))
end

function M.rejection_for(_nf, _errors)
  return Sem.Rejection(B.pc(0), Sem.UnsupportedSemanticCase, Src.UnsupportedOpcode(B.pc(0), "moon_cfg_lower"), {}, {})
end

M.phase = phase
M.lower_uncached = lower_value

return M
