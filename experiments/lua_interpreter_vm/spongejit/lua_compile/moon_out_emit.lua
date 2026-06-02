-- moon_out_emit.lua -- Moonlift source emission for MoonOut.Kernel.
--
-- Emission consumes LuaNF through MoonOut.  It does not emit opcode dispatch,
-- retired descriptor adapters, byte-bank shims, or fallback helpers.

local pvm = require("moonlift.pvm")
local B = require("lua_compile.builders")
local T = B.T
local NF = T.LuaNF
local Src = T.LuaSrc
local Abi = require("lua_compile.moon_out_abi")
local Validate = require("lua_compile.moon_out_validate")

local M = {}

local function n(v) return tonumber(v) or 0 end
local function int_lit(v) return tostring(math.floor(n(v))) end
local function i64_lit(v) return "as(i64, " .. int_lit(v) .. ")" end
local function f_lit(v)
  local s = tostring(tonumber(v) or 0)
  if not s:find("[%.eE]") then s = s .. ".0" end
  return s
end
local function par(s) return "(" .. s .. ")" end
local function join_binary(xs, op, empty)
  if #xs == 0 then return empty end
  local s = xs[1]
  for i = 2, #xs do s = par(s .. " " .. op .. " " .. xs[i]) end
  return s
end

local function slot_id(slot) return n(slot and slot.id or slot) end
local function k_id(k) return n(k and k.id or k) end

local E = {}

function E.i64_atom(a)
  if a.kind == "SrcSlotI64" then return Abi.slot_i64_name(a.slot)
  elseif a.kind == "ImmI64" then return i64_lit(a.imm.value)
  elseif a.kind == "ConstI64" then return Abi.const_i64_name(a.k)
  elseif a.kind == "UnboxI64" and a.value and a.value.kind == "SrcSlotTValue" then return Abi.slot_i64_name(a.value.slot)
  elseif a.kind == "TableLenI64" and a.table and a.table.kind == "TableFromTValue" and a.table.value and a.table.value.kind == "SrcSlotTValue" then return Abi.slot_len_name(a.table.value.slot)
  end
  error("unsupported LuaNF.I64Atom reached emission: " .. tostring(a and a.kind))
end

function E.i64(x)
  local cls = pvm.classof(x)
  if cls == NF.CanonAffineI64 then
    local parts = {}
    if (x.constant or 0) ~= 0 or #(x.terms or {}) == 0 then parts[#parts + 1] = i64_lit(x.constant or 0) end
    for _, t in ipairs(x.terms or {}) do
      local atom = E.i64_atom(t.atom)
      local c = n(t.coefficient)
      if c == 1 then parts[#parts + 1] = atom
      elseif c == -1 then parts[#parts + 1] = par(i64_lit(0) .. " - " .. atom)
      else parts[#parts + 1] = par(i64_lit(c) .. " * " .. atom) end
    end
    return join_binary(parts, "+", i64_lit(0))
  elseif cls == NF.CanonMulI64 then return par(E.i64(x.lhs) .. " * " .. E.i64(x.rhs))
  elseif cls == NF.CanonIDivI64 then return par(E.i64(x.lhs) .. " / " .. E.i64(x.rhs))
  elseif cls == NF.CanonModI64 then return par(E.i64(x.lhs) .. " % " .. E.i64(x.rhs))
  elseif cls == NF.CanonBitAndI64 then
    local xs = {}; for _, v in ipairs(x.terms or {}) do xs[#xs + 1] = E.i64(v) end; return join_binary(xs, "&", "0")
  elseif cls == NF.CanonBitOrI64 then
    local xs = {}; for _, v in ipairs(x.terms or {}) do xs[#xs + 1] = E.i64(v) end; return join_binary(xs, "|", "0")
  elseif cls == NF.CanonBitXorI64 then
    local xs = {}; for _, v in ipairs(x.terms or {}) do xs[#xs + 1] = E.i64(v) end; return join_binary(xs, "^", "0")
  elseif cls == NF.CanonShiftI64 then
    local op = (x.op == Src.Shr or (x.op and x.op.kind == "Shr")) and ">>" or "<<"
    return par(E.i64(x.lhs) .. " " .. op .. " " .. E.i64(x.rhs))
  elseif cls == NF.CanonNegI64 then return par(i64_lit(0) .. " - " .. E.i64(x.value))
  elseif cls == NF.CanonBitNotI64 then return par("~" .. E.i64(x.value)) end
  error("unsupported LuaNF.I64 reached emission: " .. tostring(x and x.kind))
end

function E.string(x)
  local cls = pvm.classof(x)
  if cls == NF.SrcSlotString then return Abi.slot_string_name(x.slot)
  elseif cls == NF.ConcatString then
    local parts = {}
    for _, p in ipairs(x.parts or {}) do parts[#parts + 1] = E.string(p) end
    if #parts == 0 then error("CONCAT reached emission with no string parts") end
    local acc = parts[1]
    for i = 2, #parts do acc = Abi.prim_concat_string_name() .. "(" .. acc .. ", " .. parts[i] .. ")" end
    return acc
  end
  error("unsupported LuaNF.String reached emission: " .. tostring(x and x.kind))
end

function E.f64(x)
  local cls = pvm.classof(x)
  if cls == NF.ImmF64 then return f_lit(x.imm.value)
  elseif cls == NF.ConstF64 then return Abi.const_f64_name(x.k)
  elseif cls == NF.ToF64 and x.value and x.value.kind == "SrcSlotTValue" then return Abi.slot_f64_name(x.value.slot)
  elseif cls == NF.I64ToF64 then return "as(f64, " .. E.i64(x.value) .. ")"
  elseif cls == NF.DivF64 then return par(E.f64(x.lhs) .. " / " .. E.f64(x.rhs))
  elseif cls == NF.PowF64 then return Abi.prim_pow_f64_name() .. "(" .. E.f64(x.lhs) .. ", " .. E.f64(x.rhs) .. ")" end
  error("unsupported LuaNF.F64 reached emission: " .. tostring(x and x.kind))
end

local function truthy_expr(value)
  if value.kind == "BoolTValue" then return value.value and "true" or "false" end
  if value.kind == "NilTValue" then return "false" end
  if value.kind == "BoolExprTValue" then return E.bool(value.value) end
  if value.kind == "SrcSlotTValue" then
    local vk = Abi.slot_value_kind_name(value.slot)
    local bv = Abi.slot_bool_name(value.slot)
    local is_nil = par(vk .. " == " .. Abi.VALUE_KIND.nil_)
    local is_false = par(vk .. " == " .. Abi.VALUE_KIND.bool .. " and not " .. bv)
    return par("not " .. is_nil .. " and not " .. is_false)
  end
  if value.kind == "BoxI64TValue" or value.kind == "BoxF64TValue" or value.kind == "FieldTValue" or
     value.kind == "ArrayTValue" or value.kind == "UpvalueTValue" or value.kind == "TableTValue" or
     value.kind == "ClosureTValue" or value.kind == "VarargTValue" or value.kind == "StringTValue" then
    return "true"
  end
  error("unsupported LuaNF.TValue truthiness reached emission: " .. tostring(value and value.kind))
end

function E.bool(x)
  local cls = pvm.classof(x)
  if cls == NF.CmpI64 then
    local k = x.op and x.op.kind
    local op = ({ Eq="==", Lt="<", Le="<=", EqI="==", LtI="<", LeI="<=", GtI=">", GeI=">=", EqK="==" })[k] or "=="
    local s = par(E.i64(x.lhs) .. " " .. op .. " " .. E.i64(x.rhs))
    return x.polarity == false and par("not " .. s) or s
  elseif cls == NF.Truthy then
    local s = truthy_expr(x.value)
    return x.polarity == false and par("not " .. s) or s
  elseif cls == NF.BoolAnd then
    return par(E.bool(x.lhs) .. " and " .. E.bool(x.rhs))
  elseif cls == NF.BoolOr then
    return par(E.bool(x.lhs) .. " or " .. E.bool(x.rhs))
  elseif cls == NF.NotTValue then
    return par("not " .. truthy_expr(x.value))
  end
  error("unsupported LuaNF.Bool reached emission: " .. tostring(x and x.kind))
end

local function payload_kind(payload)
  if not payload then return Abi.PAYLOAD_KIND.none end
  return ({ ShapePayload = Abi.PAYLOAD_KIND.shape, FieldPayload = Abi.PAYLOAD_KIND.field,
            ArrayPayload = Abi.PAYLOAD_KIND.array, CallTargetPayload = Abi.PAYLOAD_KIND.call_target,
            BarrierPayload = Abi.PAYLOAD_KIND.barrier })[payload.kind] or Abi.PAYLOAD_KIND.none
end

local function emit_table_metadata(lines, table)
  if table.kind == "TableFromTValue" and table.value and table.value.kind == "SrcSlotTValue" then
    lines[#lines + 1] = "    out_table_slot[0] = " .. i64_lit(table.value.slot.id)
  elseif table.kind == "TableFromUpvalue" then
    lines[#lines + 1] = "    out_upvalue[0] = " .. i64_lit(table.up.id)
  end
end

local function emit_address_assign(lines, address)
  if address.kind == "FieldAddress" then
    lines[#lines + 1] = "    out_address_kind[0] = " .. Abi.ADDRESS_KIND.field
    lines[#lines + 1] = "    out_key[0] = " .. i64_lit(address.key.id)
    lines[#lines + 1] = "    out_payload_kind[0] = " .. payload_kind(address.field_payload)
    lines[#lines + 1] = "    out_payload_pc[0] = " .. i64_lit(address.field_payload and address.field_payload.pc and address.field_payload.pc.id or 0)
    emit_table_metadata(lines, address.table)
  elseif address.kind == "ArrayAddress" then
    lines[#lines + 1] = "    out_address_kind[0] = " .. Abi.ADDRESS_KIND.array
    lines[#lines + 1] = "    out_index_i64[0] = " .. E.i64(address.index)
    lines[#lines + 1] = "    out_payload_kind[0] = " .. payload_kind(address.array_payload)
    lines[#lines + 1] = "    out_payload_pc[0] = " .. i64_lit(address.array_payload and address.array_payload.pc and address.array_payload.pc.id or 0)
    emit_table_metadata(lines, address.table)
  elseif address.kind == "UpvalueAddress" then
    lines[#lines + 1] = "    out_address_kind[0] = " .. Abi.ADDRESS_KIND.upvalue
    lines[#lines + 1] = "    out_upvalue[0] = " .. i64_lit(address.up.id)
  else
    error("unsupported LuaNF.Address reached emission: " .. tostring(address and address.kind))
  end
end

local function emit_event(lines, kind)
  lines[#lines + 1] = "    out_event_kind[0] = " .. kind
  lines[#lines + 1] = "    out_event_count[0] = out_event_count[0] + 1"
end

local function emit_value_assign(lines, value, pc_expr, slot_expr)
  slot_expr = slot_expr or i64_lit(0)
  if value.kind == "BoxI64TValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.i64
    lines[#lines + 1] = "    out_i64[0] = " .. E.i64(value.value)
  elseif value.kind == "BoxF64TValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.f64
    lines[#lines + 1] = "    out_f64[0] = " .. E.f64(value.value)
  elseif value.kind == "StringTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.string_tvalue
    lines[#lines + 1] = "    out_i64[0] = " .. E.string(value.value)
  elseif value.kind == "BoolTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.bool
    lines[#lines + 1] = "    out_bool[0] = " .. tostring(value.value == true)
  elseif value.kind == "BoolExprTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.bool
    lines[#lines + 1] = "    out_bool[0] = " .. E.bool(value.value)
  elseif value.kind == "NilTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.nil_
  elseif value.kind == "SrcSlotTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.tvalue_slot
    lines[#lines + 1] = "    out_table_slot[0] = " .. i64_lit(value.slot.id)
  elseif value.kind == "ConstTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.const_tvalue
    lines[#lines + 1] = "    out_key[0] = " .. i64_lit(value.k.id)
  elseif value.kind == "UpvalueTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.upvalue_tvalue
    lines[#lines + 1] = "    out_upvalue[0] = " .. i64_lit(value.up.id)
  elseif value.kind == "VarargTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.vararg_tvalue
    lines[#lines + 1] = "    out_table_slot[0] = " .. i64_lit(value.base.id)
    lines[#lines + 1] = "    out_start[0] = " .. i64_lit(value.index.value)
  elseif value.kind == "FieldTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.field_tvalue
    lines[#lines + 1] = "    out_event_kind[0] = " .. Abi.EVENT_KIND.field_read
    emit_address_assign(lines, value.address)
  elseif value.kind == "ArrayTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.array_tvalue
    lines[#lines + 1] = "    out_event_kind[0] = " .. Abi.EVENT_KIND.array_read
    emit_address_assign(lines, value.address)
  elseif value.kind == "TableTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.table_tvalue
    if value.table and value.table.kind == "TableFromNew" then
      lines[#lines + 1] = "    out_array_hint[0] = " .. i64_lit(value.table.array_hint and value.table.array_hint.value or 0)
      lines[#lines + 1] = "    out_hash_hint[0] = " .. i64_lit(value.table.hash_hint and value.table.hash_hint.value or 0)
    end
  elseif value.kind == "ClosureTValue" then
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.closure_tvalue
    if value.closure and value.closure.kind == "ClosureFromProto" then
      lines[#lines + 1] = "    out_key[0] = " .. i64_lit(value.closure.proto.id)
    end
  else
    error("unsupported LuaNF.TValue reached emission: " .. tostring(value and value.kind))
  end
  lines[#lines + 1] = "    out_pc[0] = " .. (pc_expr or i64_lit(0))
  lines[#lines + 1] = "    out_slot[0] = " .. slot_expr
end

local function emit_projection(lines, projection)
  projection = projection or {}
  lines[#lines + 1] = "    out_projection_count[0] = " .. tostring(#projection)
  for _, p in ipairs(projection) do
    if p.kind == "LiveI64" then
      lines[#lines + 1] = "    out_slot[0] = " .. i64_lit(p.slot.id)
      lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.i64
      lines[#lines + 1] = "    out_i64[0] = " .. E.i64(p.value)
      return
    elseif p.kind == "LiveF64" then
      lines[#lines + 1] = "    out_slot[0] = " .. i64_lit(p.slot.id)
      lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.f64
      lines[#lines + 1] = "    out_f64[0] = " .. E.f64(p.value)
      return
    elseif p.kind == "LiveTValue" then
      emit_value_assign(lines, p.value, "out_pc[0]", i64_lit(p.slot.id))
      return
    end
  end
end

local function emit_exit(lines, exit)
  local cls = pvm.classof(exit)
  local pc = exit.pc and i64_lit(exit.pc.id) or i64_lit(0)
  if cls == NF.ReturnExit then
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.return_
    emit_value_assign(lines, exit.value, pc, i64_lit(0))
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.Return0Exit then
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.return_
    lines[#lines + 1] = "    out_pc[0] = " .. pc
    lines[#lines + 1] = "    out_value_kind[0] = " .. Abi.VALUE_KIND.none
    emit_projection(lines, exit.projection or {})
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.JumpExit then
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.jump
    lines[#lines + 1] = "    out_pc[0] = " .. pc
    lines[#lines + 1] = "    out_offset[0] = " .. i64_lit(exit.offset and exit.offset.value or 0)
    emit_projection(lines, exit.projection or {})
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.ConditionalJumpExit then
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.branch
    lines[#lines + 1] = "    out_pc[0] = " .. pc
    lines[#lines + 1] = "    out_bool[0] = " .. E.bool(exit.condition)
    lines[#lines + 1] = "    out_offset[0] = " .. i64_lit(exit.offset and exit.offset.value or 0)
    emit_projection(lines, exit.projection or {})
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.TestSetExit then
    local cond = E.bool(exit.condition)
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.branch
    lines[#lines + 1] = "    out_pc[0] = " .. pc
    lines[#lines + 1] = "    out_offset[0] = " .. i64_lit(exit.offset and exit.offset.value or 0)
    lines[#lines + 1] = "    if " .. cond .. " then"
    lines[#lines + 1] = "        out_bool[0] = true"
    emit_projection(lines, exit.taken_projection or {})
    lines[#lines + 1] = "    else"
    lines[#lines + 1] = "        out_bool[0] = false"
    emit_projection(lines, exit.fallthrough_projection or {})
    lines[#lines + 1] = "    end"
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.LoopRegionExit then
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.loop_region
    lines[#lines + 1] = "    out_pc[0] = " .. i64_lit(0)
    emit_projection(lines, exit.projection or {})
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.CallProtocolExit then
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.call
    lines[#lines + 1] = "    out_pc[0] = " .. pc
    lines[#lines + 1] = "    out_slot[0] = " .. i64_lit(exit.base.id)
    lines[#lines + 1] = "    out_narray[0] = " .. i64_lit(exit.nargs.value)
    lines[#lines + 1] = "    out_start[0] = " .. i64_lit(exit.nresults.value)
    lines[#lines + 1] = "    out_bool[0] = " .. tostring(exit.tail == true)
    emit_projection(lines, exit.projection or {})
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.CloseProtocolExit then
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.close
    lines[#lines + 1] = "    out_pc[0] = " .. pc
    lines[#lines + 1] = "    out_slot[0] = " .. i64_lit(exit.slot.id)
    lines[#lines + 1] = "    out_bool[0] = " .. tostring(exit.tbc == true)
    emit_projection(lines, exit.projection or {})
    lines[#lines + 1] = "    return out_tag[0]"
  elseif cls == NF.GenericForProtocolExit then
    local phase_code = ({ prep = 1, call = 2, loop = 3 })[exit.phase] or 0
    lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.generic_for
    lines[#lines + 1] = "    out_pc[0] = " .. pc
    lines[#lines + 1] = "    out_slot[0] = " .. i64_lit(exit.base.id)
    lines[#lines + 1] = "    out_narray[0] = " .. i64_lit(exit.nresults.value)
    lines[#lines + 1] = "    out_offset[0] = " .. i64_lit(exit.offset.value)
    lines[#lines + 1] = "    out_event_kind[0] = " .. tostring(phase_code)
    emit_projection(lines, exit.projection or {})
    lines[#lines + 1] = "    return out_tag[0]"
  else
    error("unsupported exit reached emission: " .. tostring(exit and exit.kind))
  end
end

local function emit_guard(lines, guard)
  local cls = pvm.classof(guard)
  if cls == NF.I64NonZeroGuard then
    lines[#lines + 1] = "    if " .. E.i64(guard.value) .. " == 0 then"
    lines[#lines + 1] = "        out_tag[0] = " .. Abi.TAG.guard
    lines[#lines + 1] = "        out_pc[0] = " .. i64_lit(guard.exit.pc and guard.exit.pc.id or 0)
    lines[#lines + 1] = "        out_boundary_reason[0] = 0"
    emit_projection(lines, guard.exit.projection or {})
    lines[#lines + 1] = "        return out_tag[0]"
    lines[#lines + 1] = "    end"
  elseif cls == NF.FactGuard then
    -- Type and payload-backed facts are represented by typed MoonOut input
    -- parameters plus the derived contract, so this kernel treats them as
    -- prevalidated obligations rather than hidden runtime fallback checks.
  elseif cls == NF.BoundsGuard then
    -- Bounds are a contract/payload obligation at the current MoonOut boundary.
  else
    error("unsupported guard reached emission: " .. tostring(guard and guard.kind))
  end
end

local function emit_slot_write(lines, write)
  lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.ok
  emit_event(lines, Abi.EVENT_KIND.slot_write)
  emit_value_assign(lines, write.value, i64_lit(0), i64_lit(write.slot.id))
end

local function emit_memory_write(lines, write)
  local cls = pvm.classof(write)
  lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.ok
  if cls == NF.FieldWrite then
    emit_event(lines, Abi.EVENT_KIND.field_write)
    emit_address_assign(lines, write.address)
    emit_value_assign(lines, write.value, i64_lit(0), i64_lit(0))
  elseif cls == NF.ArrayWrite then
    emit_event(lines, Abi.EVENT_KIND.array_write)
    emit_address_assign(lines, write.address)
    emit_value_assign(lines, write.value, i64_lit(0), i64_lit(0))
  elseif cls == NF.UpvalueWrite then
    emit_event(lines, Abi.EVENT_KIND.upvalue_write)
    lines[#lines + 1] = "    out_address_kind[0] = " .. Abi.ADDRESS_KIND.upvalue
    lines[#lines + 1] = "    out_upvalue[0] = " .. i64_lit(write.up.id)
    emit_value_assign(lines, write.value, i64_lit(0), i64_lit(0))
  elseif cls == NF.SetListWrite then
    emit_event(lines, Abi.EVENT_KIND.setlist)
    lines[#lines + 1] = "    out_table_slot[0] = " .. i64_lit(write.table.id)
    lines[#lines + 1] = "    out_narray[0] = " .. i64_lit(write.narray.value)
    lines[#lines + 1] = "    out_start[0] = " .. i64_lit(write.start.value)
  else
    error("unsupported write reached emission: " .. tostring(write and write.kind))
  end
end

local function emit_barrier(lines, barrier)
  lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.ok
  emit_event(lines, Abi.EVENT_KIND.barrier)
  lines[#lines + 1] = "    out_payload_kind[0] = " .. payload_kind(barrier.payload)
  lines[#lines + 1] = "    out_payload_pc[0] = " .. i64_lit(barrier.payload and barrier.payload.pc and barrier.payload.pc.id or 0)
  emit_value_assign(lines, barrier.value, i64_lit(0), i64_lit(0))
end

local function param_sig(params)
  local parts = {}
  for _, p in ipairs(params or {}) do parts[#parts + 1] = p.name .. ": " .. p.moon_type end
  return table.concat(parts, ", ")
end

function M.emit(kernel, opts)
  opts = opts or {}
  local ok, errors = Validate.validate(kernel)
  if not ok then error("MoonOut validation failed before emission: " .. table.concat(errors, "; "), 2) end

  local lines = {}
  local name = opts.name or "lua_compile_kernel"
  lines[#lines + 1] = "local " .. name .. " = func(" .. param_sig(kernel.params) .. ") -> i32"
  lines[#lines + 1] = "    out_event_count[0] = 0"
  lines[#lines + 1] = "    out_event_kind[0] = " .. Abi.EVENT_KIND.none
  lines[#lines + 1] = "    out_address_kind[0] = " .. Abi.ADDRESS_KIND.none
  lines[#lines + 1] = "    out_payload_kind[0] = " .. Abi.PAYLOAD_KIND.none

  local saw_terminal = false
  for _, step in ipairs(kernel.normal_form.steps or {}) do
    local cls = pvm.classof(step)
    if cls == NF.StepGuard then emit_guard(lines, step.guard)
    elseif cls == NF.StepWrite then
      if pvm.classof(step.write) == NF.SlotWrite then emit_slot_write(lines, step.write) else emit_memory_write(lines, step.write) end
    elseif cls == NF.StepBarrier then emit_barrier(lines, step.barrier)
    elseif cls == NF.StepExit then emit_exit(lines, step.exit); saw_terminal = true; break end
  end
  if not saw_terminal then
    if #(kernel.normal_form.steps or {}) == 0 then lines[#lines + 1] = "    out_tag[0] = " .. Abi.TAG.ok end
    lines[#lines + 1] = "    return out_tag[0]"
  end
  lines[#lines + 1] = "end"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "return " .. name
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

M.TAGS = Abi.TAG
M.VALUE_KIND = Abi.VALUE_KIND
M.EVENT_KIND = Abi.EVENT_KIND
M.ADDRESS_KIND = Abi.ADDRESS_KIND
M.PAYLOAD_KIND = Abi.PAYLOAD_KIND
return M
