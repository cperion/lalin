-- moon_out_abi.lua -- MoonOut.Param and kernel ABI vocabulary.
--
-- The LuaCompile MoonOut boundary is not the old SponJIT runtime ABI.  It is a
-- small typed protocol used by generated Moonlift kernels while the real VM
-- integration ABI is still being designed.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local Out = B.MoonOut
local NF = T.LuaNF

local M = {}

M.TAG = {
  ok = 0,
  return_ = 1,
  guard = 2,
  jump = 3,
  loop_region = 4,
  branch = 5,
  call = 6,
  close = 7,
  generic_for = 8,
}

M.VALUE_KIND = {
  none = 0,
  i64 = 1,
  f64 = 2,
  bool = 3,
  nil_ = 4,
  tvalue_slot = 5,
  const_tvalue = 6,
  upvalue_tvalue = 7,
  field_tvalue = 8,
  array_tvalue = 9,
  table_tvalue = 10,
  closure_tvalue = 11,
  vararg_tvalue = 12,
  string_tvalue = 13,
}

M.EVENT_KIND = {
  none = 0,
  slot_write = 1,
  field_read = 2,
  array_read = 3,
  upvalue_read = 4,
  field_write = 5,
  array_write = 6,
  upvalue_write = 7,
  barrier = 8,
  setlist = 9,
}

M.ADDRESS_KIND = {
  none = 0,
  field = 1,
  array = 2,
  upvalue = 3,
}

M.PAYLOAD_KIND = {
  none = 0,
  shape = 1,
  field = 2,
  array = 3,
  call_target = 4,
  barrier = 5,
}

M.PROTOCOL_PARAMS = {
  { "out_tag", "ptr(i32)" },
  { "out_value_kind", "ptr(i32)" },
  { "out_pc", "ptr(i64)" },
  { "out_offset", "ptr(i64)" },
  { "out_slot", "ptr(i64)" },
  { "out_i64", "ptr(i64)" },
  { "out_f64", "ptr(f64)" },
  { "out_bool", "ptr(bool)" },
  { "out_boundary_reason", "ptr(i32)" },
  { "out_projection_count", "ptr(i32)" },
  { "out_event_kind", "ptr(i32)" },
  { "out_address_kind", "ptr(i32)" },
  { "out_key", "ptr(i64)" },
  { "out_array_hint", "ptr(i64)" },
  { "out_hash_hint", "ptr(i64)" },
  { "out_narray", "ptr(i64)" },
  { "out_start", "ptr(i64)" },
  { "out_upvalue", "ptr(i64)" },
  { "out_table_slot", "ptr(i64)" },
  { "out_index_i64", "ptr(i64)" },
  { "out_payload_kind", "ptr(i32)" },
  { "out_payload_pc", "ptr(i64)" },
  { "out_event_count", "ptr(i32)" },
}

M.PRIMITIVE = {
  pow_f64_name = "lua_compile_prim_pow_f64",
  pow_f64_type = "func(f64, f64) -> f64",
  concat_string_name = "lua_compile_prim_concat_string",
  concat_string_type = "func(i64, i64) -> i64",
}

local function add_param(params, seen, name, moon_type)
  if not seen[name] then
    seen[name] = true
    params[#params + 1] = Out.Param(name, moon_type)
  end
end

function M.slot_i64_name(slot) return string.format("slot_%d_i64", tonumber(slot and slot.id or slot) or 0) end
function M.slot_f64_name(slot) return string.format("slot_%d_f64", tonumber(slot and slot.id or slot) or 0) end
function M.slot_value_kind_name(slot) return string.format("slot_%d_value_kind", tonumber(slot and slot.id or slot) or 0) end
function M.slot_bool_name(slot) return string.format("slot_%d_bool", tonumber(slot and slot.id or slot) or 0) end
function M.slot_len_name(slot) return string.format("slot_%d_len", tonumber(slot and slot.id or slot) or 0) end
function M.slot_string_name(slot) return string.format("slot_%d_string", tonumber(slot and slot.id or slot) or 0) end
function M.const_i64_name(k) return string.format("const_%d_i64", tonumber(k and k.id or k) or 0) end
function M.const_f64_name(k) return string.format("const_%d_f64", tonumber(k and k.id or k) or 0) end
function M.prim_pow_f64_name() return M.PRIMITIVE.pow_f64_name end
function M.prim_pow_f64_type() return M.PRIMITIVE.pow_f64_type end
function M.prim_concat_string_name() return M.PRIMITIVE.concat_string_name end
function M.prim_concat_string_type() return M.PRIMITIVE.concat_string_type end

local function walk(v, fn, seen)
  if type(v) ~= "table" then return end
  seen = seen or {}
  if seen[v] then return end
  seen[v] = true
  fn(v)
  local cls = pvm.classof(v)
  if cls and cls.__fields then
    for _, f in ipairs(cls.__fields) do walk(v[f.name], fn, seen) end
  end
  for k, x in pairs(v) do
    if k ~= "kind" and k ~= "__slot" then walk(x, fn, seen) end
  end
end

local function is_src_slot_tvalue(v)
  return type(v) == "table" and pvm.classof(v) == NF.SrcSlotTValue
end

local function add_dynamic_tvalue_params(params, seen, v)
  if is_src_slot_tvalue(v) then
    add_param(params, seen, M.slot_value_kind_name(v.slot), "i32")
    add_param(params, seen, M.slot_bool_name(v.slot), "bool")
  end
end

local function collect_bool_tvalue_params(params, seen, b, visiting)
  if type(b) ~= "table" then return end
  visiting = visiting or {}
  if visiting[b] then return end
  visiting[b] = true
  local cls = pvm.classof(b)
  if cls == NF.NotTValue or cls == NF.Truthy then
    add_dynamic_tvalue_params(params, seen, b.value)
    if b.value and b.value.kind == "BoolExprTValue" then collect_bool_tvalue_params(params, seen, b.value.value, visiting) end
  elseif cls == NF.CmpI64 then
    return
  end
end

function M.params_for_nf(nf)
  local params, seen = {}, {}
  for _, p in ipairs(M.PROTOCOL_PARAMS) do add_param(params, seen, p[1], p[2]) end
  walk(nf, function(v)
    local cls = pvm.classof(v)
    if cls == NF.SrcSlotI64 then
      add_param(params, seen, M.slot_i64_name(v.slot), "i64")
    elseif cls == NF.ConstI64 then
      add_param(params, seen, M.const_i64_name(v.k), "i64")
    elseif cls == NF.UnboxI64 and is_src_slot_tvalue(v.value) then
      add_param(params, seen, M.slot_i64_name(v.value.slot), "i64")
    elseif cls == NF.TableLenI64 and v.table and v.table.kind == "TableFromTValue" and is_src_slot_tvalue(v.table.value) then
      add_param(params, seen, M.slot_len_name(v.table.value.slot), "i64")
    elseif cls == NF.ToF64 and is_src_slot_tvalue(v.value) then
      add_param(params, seen, M.slot_f64_name(v.value.slot), "f64")
    elseif cls == NF.ConstF64 then
      add_param(params, seen, M.const_f64_name(v.k), "f64")
    elseif cls == NF.PowF64 then
      add_param(params, seen, M.prim_pow_f64_name(), M.prim_pow_f64_type())
    elseif cls == NF.SrcSlotString then
      add_param(params, seen, M.slot_string_name(v.slot), "i64")
    elseif cls == NF.ConcatString then
      add_param(params, seen, M.prim_concat_string_name(), M.prim_concat_string_type())
    elseif cls == NF.NotTValue or cls == NF.Truthy then
      collect_bool_tvalue_params(params, seen, v)
    end
  end)
  return params
end

function M.default_params()
  local out = {}
  for _, p in ipairs(M.PROTOCOL_PARAMS) do out[#out + 1] = Out.Param(p[1], p[2]) end
  return out
end

return M
