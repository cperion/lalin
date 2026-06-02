-- moon_out_validate.lua -- MoonOut invariants and emission support checks.

local pvm = require("moonlift.pvm")
local Validate = require("lua_compile.validate")
local Abi = require("lua_compile.moon_out_abi")
local B = require("lua_compile.builders")
local T = B.T
local NF = T.LuaNF
local Fact = T.LuaFact

local M = {}

local CURRENT_SUPPORT = nil

local function add(errors, code, detail)
  errors[#errors + 1] = detail and (code .. ":" .. detail) or code
end

local function validate_i64(x, errors)
  local cls = pvm.classof(x)
  if cls == NF.CanonAffineI64 then
    for _, t in ipairs(x.terms or {}) do
      local ac = pvm.classof(t.atom)
      if ac == NF.SrcSlotI64 or ac == NF.ImmI64 or ac == NF.ConstI64 then
        -- supported
      elseif ac == NF.UnboxI64 and t.atom.value and t.atom.value.kind == "SrcSlotTValue" then
        -- supported as a typed slot_i64 input at the MoonOut ABI boundary
      elseif ac == NF.TableLenI64 and t.atom.table and t.atom.table.kind == "TableFromTValue" and t.atom.table.value and t.atom.table.value.kind == "SrcSlotTValue" then
        -- supported as a typed slot_len input at the MoonOut ABI boundary
      else
        add(errors, "unsupported_nf", "I64Atom." .. tostring(t.atom and t.atom.kind))
      end
    end
  elseif cls == NF.CanonMulI64 or cls == NF.CanonIDivI64 or cls == NF.CanonModI64 or cls == NF.CanonShiftI64 then
    validate_i64(x.lhs, errors); validate_i64(x.rhs, errors)
  elseif cls == NF.CanonBitAndI64 or cls == NF.CanonBitOrI64 or cls == NF.CanonBitXorI64 then
    for _, term in ipairs(x.terms or {}) do validate_i64(term, errors) end
  elseif cls == NF.CanonNegI64 or cls == NF.CanonBitNotI64 then
    validate_i64(x.value, errors)
  else
    add(errors, "unsupported_nf", "I64." .. tostring(x and x.kind))
  end
end

local function validate_f64(x, errors, support)
  support = support or CURRENT_SUPPORT
  local cls = pvm.classof(x)
  if cls == NF.ImmF64 or cls == NF.ConstF64 then
    return
  elseif cls == NF.ToF64 then
    if not (x.value and x.value.kind == "SrcSlotTValue") then add(errors, "unsupported_nf", "F64.ToF64." .. tostring(x.value and x.value.kind)) end
  elseif cls == NF.I64ToF64 then
    validate_i64(x.value, errors)
  elseif cls == NF.DivF64 then
    validate_f64(x.lhs, errors, support); validate_f64(x.rhs, errors, support)
  elseif cls == NF.PowF64 then
    validate_f64(x.lhs, errors, support); validate_f64(x.rhs, errors, support)
    if not (support and support.prim_pow_f64) then add(errors, "missing", "primitive_param." .. Abi.prim_pow_f64_name()) end
  else
    add(errors, "unsupported_nf", "F64." .. tostring(x and x.kind))
  end
end

local validate_tvalue
local validate_address
local validate_table

local function validate_string(x, errors, support)
  support = support or CURRENT_SUPPORT
  local cls = pvm.classof(x)
  if cls == NF.SrcSlotString then return
  elseif cls == NF.ConcatString then
    for _, p in ipairs(x.parts or {}) do validate_string(p, errors, support) end
    if #(x.parts or {}) < 2 then add(errors, "unsupported_nf", "String.ConcatString.arity") end
    if not (support and support.prim_concat_string) then add(errors, "missing", "primitive_param." .. Abi.prim_concat_string_name()) end
  else
    add(errors, "unsupported_nf", "String." .. tostring(x and x.kind))
  end
end

local function tvalue_truthiness_supported(v)
  if not v then return false end
  local cls = pvm.classof(v)
  return cls == NF.BoolTValue or cls == NF.BoolExprTValue or v.kind == "NilTValue" or
         cls == NF.SrcSlotTValue or cls == NF.BoxI64TValue or cls == NF.BoxF64TValue or cls == NF.StringTValue or
         cls == NF.FieldTValue or cls == NF.ArrayTValue or cls == NF.UpvalueTValue or cls == NF.VarargTValue or
         cls == NF.TableTValue or cls == NF.ClosureTValue
end

local function validate_bool(x, errors)
  local cls = pvm.classof(x)
  if cls == NF.CmpI64 then
    validate_i64(x.lhs, errors); validate_i64(x.rhs, errors)
  elseif cls == NF.BoolAnd or cls == NF.BoolOr then
    validate_bool(x.lhs, errors); validate_bool(x.rhs, errors)
  elseif cls == NF.Truthy then
    if not tvalue_truthiness_supported(x.value) then add(errors, "unsupported_nf", "Bool.Truthy." .. tostring(x.value and x.value.kind))
    else validate_tvalue(x.value, errors) end
  elseif cls == NF.NotTValue then
    if not tvalue_truthiness_supported(x.value) then
      add(errors, "unsupported_nf", "Bool.NotTValue." .. tostring(x.value and x.value.kind))
    else
      validate_tvalue(x.value, errors)
    end
  else
    add(errors, "unsupported_nf", "Bool." .. tostring(x and x.kind))
  end
end

validate_table = function(t, errors)
  local cls = pvm.classof(t)
  if cls == NF.TableFromTValue then validate_tvalue(t.value, errors)
  elseif cls == NF.TableFromUpvalue or cls == NF.TableFromNew then return
  else add(errors, "unsupported_nf", "Table." .. tostring(t and t.kind)) end
end

validate_address = function(a, errors)
  local cls = pvm.classof(a)
  if cls == NF.FieldAddress then validate_table(a.table, errors)
  elseif cls == NF.ArrayAddress then validate_table(a.table, errors); validate_i64(a.index, errors)
  elseif cls == NF.UpvalueAddress then return
  else add(errors, "unsupported_nf", "Address." .. tostring(a and a.kind)) end
end

validate_tvalue = function(v, errors)
  local cls = pvm.classof(v)
  if cls == NF.BoxI64TValue then validate_i64(v.value, errors)
  elseif cls == NF.BoxF64TValue then validate_f64(v.value, errors)
  elseif cls == NF.StringTValue then validate_string(v.value, errors)
  elseif cls == NF.BoolTValue or v.kind == "NilTValue" then return
  elseif cls == NF.BoolExprTValue then validate_bool(v.value, errors)
  elseif cls == NF.SrcSlotTValue or cls == NF.ConstTValue or cls == NF.UpvalueTValue or cls == NF.VarargTValue then return
  elseif cls == NF.FieldTValue or cls == NF.ArrayTValue then validate_address(v.address, errors)
  elseif cls == NF.TableTValue then validate_table(v.table, errors)
  elseif cls == NF.ClosureTValue then return
  else add(errors, "unsupported_nf", "TValue." .. tostring(v and v.kind)) end
end

local function validate_projection(p, errors)
  local cls = pvm.classof(p)
  if cls == NF.LiveI64 then validate_i64(p.value, errors)
  elseif cls == NF.LiveF64 then validate_f64(p.value, errors)
  elseif cls == NF.LiveTValue then validate_tvalue(p.value, errors)
  elseif cls == NF.SyncedSlot or cls == NF.DeadSlot then return
  else add(errors, "unsupported_nf", "Projection." .. tostring(p and p.kind)) end
end

local function validate_exit(exit, errors)
  local cls = pvm.classof(exit)
  for _, p in ipairs(exit.projection or {}) do validate_projection(p, errors) end
  if cls == NF.ReturnExit then validate_tvalue(exit.value, errors)
  elseif cls == NF.Return0Exit then return
  elseif cls == NF.ConditionalJumpExit then validate_bool(exit.condition, errors)
  elseif cls == NF.TestSetExit then
    validate_bool(exit.condition, errors)
    for _, p in ipairs(exit.taken_projection or {}) do validate_projection(p, errors) end
    for _, p in ipairs(exit.fallthrough_projection or {}) do validate_projection(p, errors) end
  elseif cls == NF.JumpExit or cls == NF.LoopRegionExit or cls == NF.GuardExit then return
  elseif cls == NF.CallProtocolExit or cls == NF.CloseProtocolExit or cls == NF.GenericForProtocolExit then return
  else add(errors, "unsupported_nf", "Exit." .. tostring(exit and exit.kind)) end
end

local SUPPORTED_FACT_GUARD = {
  IsI64 = true, IsF64 = true, IsNumber = true, IsString = true, IsTable = true,
  ShapeEq = true, MetatableAbsent = true, FieldOffset = true,
  ArrayHit = true, BoundsOk = true, ArrayBaseOffset = true, ArrayLenOffset = true,
  BarrierClean = true,
}

local function validate_guard(g, errors)
  local cls = pvm.classof(g)
  if cls == NF.FactGuard then
    local pred = g.predicate and g.predicate.kind
    if not SUPPORTED_FACT_GUARD[pred] then add(errors, "unsupported_nf", "FactGuard." .. tostring(pred)) end
    if g.value and g.value.kind ~= "SrcSlotTValue" then validate_tvalue(g.value, errors) end
    validate_exit(g.exit, errors)
  elseif cls == NF.I64NonZeroGuard then
    validate_i64(g.value, errors); validate_exit(g.exit, errors)
  elseif cls == NF.BoundsGuard then
    validate_table(g.table, errors); validate_i64(g.index, errors); validate_exit(g.exit, errors)
  else
    add(errors, "unsupported_nf", "Guard." .. tostring(g and g.kind))
  end
end

local function validate_barrier(b, errors)
  if not b or pvm.classof(b.payload) ~= Fact.BarrierPayload then add(errors, "unsupported_nf", "Barrier.payload") end
  if b then validate_tvalue(b.owner, errors); validate_tvalue(b.value, errors) end
end

local function validate_write(w, errors)
  local cls = pvm.classof(w)
  if cls == NF.SlotWrite then validate_tvalue(w.value, errors)
  elseif cls == NF.FieldWrite or cls == NF.ArrayWrite then validate_address(w.address, errors); validate_tvalue(w.value, errors)
  elseif cls == NF.UpvalueWrite then validate_tvalue(w.value, errors)
  elseif cls == NF.SetListWrite then return
  else add(errors, "unsupported_nf", "Write." .. tostring(w and w.kind)) end
end

local function validate_step(step, errors)
  local cls = pvm.classof(step)
  if cls == NF.StepWrite then validate_write(step.write, errors)
  elseif cls == NF.StepGuard then validate_guard(step.guard, errors)
  elseif cls == NF.StepExit then validate_exit(step.exit, errors)
  elseif cls == NF.StepBarrier then validate_barrier(step.barrier, errors)
  elseif cls == NF.StepDefine then add(errors, "unsupported_nf", "Define")
  else add(errors, "unsupported_nf", "Step." .. tostring(step and step.kind)) end
end

function M.validate(kernel)
  local ok0, errors = Validate.moon_out_kernel(kernel)
  errors = errors or {}
  if not ok0 then return false, errors end
  if not kernel.normal_form then add(errors, "missing", "normal_form") end
  if not kernel.contract then add(errors, "missing", "contract") end
  local required = {
    out_tag = "ptr(i32)", out_value_kind = "ptr(i32)", out_pc = "ptr(i64)", out_offset = "ptr(i64)",
    out_slot = "ptr(i64)", out_i64 = "ptr(i64)", out_f64 = "ptr(f64)",
    out_bool = "ptr(bool)", out_boundary_reason = "ptr(i32)", out_projection_count = "ptr(i32)",
    out_event_kind = "ptr(i32)", out_address_kind = "ptr(i32)", out_key = "ptr(i64)",
    out_array_hint = "ptr(i64)", out_hash_hint = "ptr(i64)", out_narray = "ptr(i64)", out_start = "ptr(i64)",
    out_upvalue = "ptr(i64)", out_table_slot = "ptr(i64)", out_index_i64 = "ptr(i64)",
    out_payload_kind = "ptr(i32)", out_payload_pc = "ptr(i64)", out_event_count = "ptr(i32)",
  }
  local seen = {}
  for _, p in ipairs(kernel.params or {}) do
    seen[p.name] = p.moon_type
    if p.moon_type and p.moon_type:find("Spon", 1, true) then add(errors, "forbidden_abi_name", p.moon_type) end
  end
  for name, ty in pairs(required) do
    if seen[name] ~= ty then add(errors, "missing", "protocol_param." .. name) end
  end
  CURRENT_SUPPORT = {
    prim_pow_f64 = seen[Abi.prim_pow_f64_name()] == Abi.prim_pow_f64_type(),
    prim_concat_string = seen[Abi.prim_concat_string_name()] == Abi.prim_concat_string_type(),
  }
  local nf = kernel.normal_form
  for _, step in ipairs((nf and nf.steps) or {}) do validate_step(step, errors) end
  for _, exit in ipairs((nf and nf.exits) or {}) do validate_exit(exit, errors) end
  return #errors == 0, errors
end

return M
