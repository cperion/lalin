-- impl/lower_emit_c/code_to_c.lua
-- Methods on Code.*, Core.*, and C.* types for C emission.
-- Ported from code_to_c.lua.

require("lalin.schema_v2")

local Code    = require("lalin.schema_v2.code")
local Core    = require("lalin.schema_v2.core")
local C       = require("lalin.schema_v2.c")
local Sem     = require("lalin.schema_v2.sem")
local Mem     = require("lalin.schema_v2.mem")
local Lower   = require("lalin.schema_v2.lower")

----------------------------------------------------------------------
-- CodeType → code_to_c_type_name / helper queries
----------------------------------------------------------------------

function Code.CodeTyVoid:code_to_c_type_name() return "void" end
function Code.CodeTyBool8:code_to_c_type_name() return "bool" end
function Code.CodeTyInt:code_to_c_type_name()
  local prefix = self.signedness == Code.CodeSigned and "int" or "uint"
  return prefix .. tostring(self.bits) .. "_t"
end
function Code.CodeTyFloat:code_to_c_type_name()
  return self.bits == 32 and "float" or "double"
end
function Code.CodeTyIndex:code_to_c_type_name() return "size_t" end
function Code.CodeTyDataPtr:code_to_c_type_name()
  if self.pointee ~= nil then return self.pointee:code_to_c_type_name() .. "*" end
  return "void*"
end
function Code.CodeTyCodePtr:code_to_c_type_name() return "void(*)(void)" end
function Code.CodeTyNamed:code_to_c_type_name() return self.type_name end
function Code.CodeTyArray:code_to_c_type_name()
  return self.elem:code_to_c_type_name() .. "[" .. tostring(self.count) .. "]"
end
function Code.CodeTySlice:code_to_c_type_name() return "slice_t" end
function Code.CodeTyView:code_to_c_type_name() return "view_t" end
function Code.CodeTyByteSpan:code_to_c_type_name() return "bytespan_t" end
function Code.CodeTyHandle:code_to_c_type_name() return "handle_t" end
function Code.CodeTyLease:code_to_c_type_name() return self.base:code_to_c_type_name() end
function Code.CodeTyClosure:code_to_c_type_name() return "closure_t" end
function Code.CodeTyImportedC:code_to_c_type_name() return self.id.spelling end
function Code.CodeTyImportedCFuncPtr:code_to_c_type_name() return "void(*)(void)" end
function Code.CodeTyVector:code_to_c_type_name()
  return self.elem:code_to_c_type_name() .. " __attribute__((vector_size(" .. tostring(self.lanes * 4) .. ")))"
end

-- parent default
function Code.CodeType:code_to_c_type_name()
  return "/* unknown CodeType */"
end

----------------------------------------------------------------------
-- CodeType → variant_payload / without_lease / view_elem / slice_elem
----------------------------------------------------------------------

function Code.CodeType:code_to_c_variant_payload_union_id() return nil end
function Code.CodeTyNamed:code_to_c_variant_payload_union_id()
  return C.CTypeId(self.module_name, self.type_name .. "_payload")
end

function Code.CodeType:code_to_c_without_lease() return self end
function Code.CodeTyLease:code_to_c_without_lease() return self.base end

function Code.CodeType:code_to_c_view_elem_type() return nil end
function Code.CodeTyView:code_to_c_view_elem_type() return self.elem end

function Code.CodeType:code_to_c_slice_elem_type() return nil end
function Code.CodeTySlice:code_to_c_slice_elem_type() return self.elem end

----------------------------------------------------------------------
-- CodeConst → code_to_c_literal
----------------------------------------------------------------------

function Code.CodeConst:code_to_c_literal() return nil end
function Code.CodeConstLiteral:code_to_c_literal()
  local lit = self.literal
  -- Core.Literal leaves
  if lit ~= nil then return lit:code_to_c_literal_value() end
  return nil
end
function Code.CodeConstNull:code_to_c_literal() return "NULL" end
function Code.CodeConstUndef:code_to_c_literal() return nil end

----------------------------------------------------------------------
-- Core.Literal → code_to_c_literal_value
----------------------------------------------------------------------

function Core.Literal:code_to_c_literal_value() return nil end
function Core.LitInt:code_to_c_literal_value() return tostring(self.raw) end
function Core.LitFloat:code_to_c_literal_value() return tostring(self.raw) end
function Core.LitBool:code_to_c_literal_value() return self.value and "true" or "false" end
function Core.LitString:code_to_c_literal_value()
  return '"' .. self.bytes:gsub('"', '\\"') .. '"'
end
function Core.LitNil:code_to_c_literal_value() return "NULL" end

function Core.Literal:code_to_c_is_zero_literal() return false end
function Core.LitInt:code_to_c_is_zero_literal() return tostring(self.raw) == "0" end

----------------------------------------------------------------------
-- Core.Scalar → emit_c_scalar_type
----------------------------------------------------------------------

function Core.Scalar:emit_c_scalar_type() return nil end
function Core.ScalarVoid:emit_c_scalar_type() return "void" end
function Core.ScalarBool:emit_c_scalar_type() return "bool" end
function Core.ScalarI8:emit_c_scalar_type() return "int8_t" end
function Core.ScalarI16:emit_c_scalar_type() return "int16_t" end
function Core.ScalarI32:emit_c_scalar_type() return "int32_t" end
function Core.ScalarI64:emit_c_scalar_type() return "int64_t" end
function Core.ScalarU8:emit_c_scalar_type() return "uint8_t" end
function Core.ScalarU16:emit_c_scalar_type() return "uint16_t" end
function Core.ScalarU32:emit_c_scalar_type() return "uint32_t" end
function Core.ScalarU64:emit_c_scalar_type() return "uint64_t" end
function Core.ScalarF32:emit_c_scalar_type() return "float" end
function Core.ScalarF64:emit_c_scalar_type() return "double" end
function Core.ScalarRawPtr:emit_c_scalar_type() return "void*" end
function Core.ScalarIndex:emit_c_scalar_type() return "size_t" end

----------------------------------------------------------------------
-- C.CBackendType → code_to_c_is_pointer_type
----------------------------------------------------------------------

function C.CBackendType:code_to_c_is_pointer_type() return false end
function C.CBackendDataPtr:code_to_c_is_pointer_type() return true end
function C.CBackendCodePtr:code_to_c_is_pointer_type() return true end
function C.CBackendImportedCodePtr:code_to_c_is_pointer_type() return true end
function C.CBackendAbiHiddenOutPtr:code_to_c_is_pointer_type() return true end
function C.CBackendSliceDescriptor:code_to_c_is_pointer_type() return true end
function C.CBackendViewDescriptor:code_to_c_is_pointer_type() return true end
function C.CBackendClosureDescriptor:code_to_c_is_pointer_type() return true end

----------------------------------------------------------------------
-- C.CBackendAtom → code_to_c_is_nullish_const
----------------------------------------------------------------------

function C.CBackendAtom:code_to_c_is_nullish_const() return false end
function C.CBackendAtomNull:code_to_c_is_nullish_const() return true end
function C.CBackendAtomLiteral:code_to_c_is_nullish_const()
  -- literal is null if the CodeConst is null
  return false
end

----------------------------------------------------------------------
-- Sem.FieldRef → code_to_c_field_name
----------------------------------------------------------------------

function Sem.FieldRef:code_to_c_field_name() return "field_" .. tostring(self) end
function Sem.FieldByName:code_to_c_field_name() return self.name end
function Sem.FieldByOffset:code_to_c_field_name() return "__offset_" .. tostring(self.offset) end

----------------------------------------------------------------------
-- Mem.MemBase → code_to_c_atom
----------------------------------------------------------------------

function Mem.MemBase:code_to_c_atom(c_emission)
  error("code_to_c: unsupported address-thread base", 3)
end
function Mem.MemBaseValue:code_to_c_atom(c_emission)
  -- returns a CBackendAtom for the value
  return nil -- placeholder: requires c_emission context
end
function Mem.MemBaseLocal:code_to_c_atom(c_emission)
  return C.CBackendAtomLocal(self.local_id.text)
end

function Mem.MemBase:code_to_c_materialize_atom(c_emission)
  return {}, self:code_to_c_atom(c_emission)
end
function Mem.MemBaseValue:code_to_c_materialize_atom(c_emission)
  -- value might need a temp local
  return {}, self:code_to_c_atom(c_emission)
end

----------------------------------------------------------------------
-- CodePlace → code_to_c_is_deref / lower_code_place_to_c
----------------------------------------------------------------------

function Code.CodePlace:code_to_c_is_deref() return false end
function Code.CodePlaceDeref:code_to_c_is_deref() return true end

function Code.CodePlace:lower_code_place_to_c(c_emission)
  error("code_to_c: unsupported place for C emission", 3)
end
function Code.CodePlaceLocal:lower_code_place_to_c(c_emission)
  return C.CBackendPlaceLocal(c_emission:local_name(self.local_id))
end
function Code.CodePlaceGlobal:lower_code_place_to_c(c_emission)
  return C.CBackendPlaceGlobal(self.global_id.text)
end
function Code.CodePlaceData:lower_code_place_to_c(c_emission)
  return C.CBackendPlaceGlobal("__data_" .. self.data_id.text)
end
function Code.CodePlaceDeref:lower_code_place_to_c(c_emission)
  local base = self.base:lower_code_place_to_c(c_emission)
  return C.CBackendPlaceDeref(base)
end
function Code.CodePlaceField:lower_code_place_to_c(c_emission)
  local base = self.base:lower_code_place_to_c(c_emission)
  return C.CBackendPlaceField(base, C.CBackendName(self.field:code_to_c_field_name()), nil, self.byte_offset, nil, nil)
end
function Code.CodePlaceIndex:lower_code_place_to_c(c_emission)
  local base = self.base:lower_code_place_to_c(c_emission)
  local idx = c_emission:atom(self.index)
  return C.CBackendPlaceIndex(base, idx, self.elem_size)
end
function Code.CodePlaceBytes:lower_code_place_to_c(c_emission)
  local base = self.base:lower_code_place_to_c(c_emission)
  return C.CBackendPlaceBytes(base, self.byte_offset)
end

----------------------------------------------------------------------
-- CodeValueId → code_to_c_materialize_atom
----------------------------------------------------------------------

function Code.CodeValueId:code_to_c_materialize_atom(c_emission)
  return {}, c_emission:atom(self)
end

----------------------------------------------------------------------
-- CodePlace → code_to_c_materialize_place
----------------------------------------------------------------------

function Code.CodePlace:code_to_c_materialize_place(c_emission)
  return {}, self:lower_code_place_to_c(c_emission)
end

function Code.CodePlaceDeref:code_to_c_materialize_place(c_emission)
  local stmts, addr = self.addr:code_to_c_materialize_atom(c_emission)
  return stmts, C.CBackendPlaceDeref(C.CBackendPlaceAtom(addr))
end

function Code.CodePlaceField:code_to_c_materialize_place(c_emission)
  local stmts, base = self.base:code_to_c_materialize_place(c_emission)
  return stmts, C.CBackendPlaceField(base, C.CBackendName(self.field:code_to_c_field_name()), nil, self.byte_offset, nil, nil)
end

function Code.CodePlaceIndex:code_to_c_materialize_place(c_emission)
  local stmts, base = self.base:code_to_c_materialize_place(c_emission)
  local istmts, idx = self.index:code_to_c_materialize_atom(c_emission)
  for _, s in ipairs(istmts or {}) do stmts[#stmts + 1] = s end
  return stmts, C.CBackendPlaceIndex(base, idx, self.elem_size)
end

----------------------------------------------------------------------
-- CodeInstOp → code_to_c_materialize_base_value
----------------------------------------------------------------------

function Code.CodeInstOp:code_to_c_materialize_base_value(c_emission)
  return {}, nil
end

function Code.CodeInstLoad:code_to_c_materialize_base_value(c_emission)
  local stmts, place = self.place:code_to_c_materialize_place(c_emission)
  local dst = c_emission:temp(self.ty)
  stmts[#stmts + 1] = C.CBackendStmtLoad(dst, place)
  return stmts, dst
end

function Code.CodeInstAlias:code_to_c_materialize_base_value(c_emission)
  return self.src:code_to_c_materialize_atom(c_emission)
end

function Code.CodeInstCast:code_to_c_materialize_base_value(c_emission)
  local stmts, src = self.value:code_to_c_materialize_atom(c_emission)
  if self.op ~= nil then
    local dst = c_emission:temp(self.to)
    stmts[#stmts + 1] = C.CBackendStmtCast(dst, src, self.op)
    return stmts, dst
  end
  return stmts, src
end

----------------------------------------------------------------------
-- CodeGlobalRef → lower_code_global_ref_to_c_name / to_c_sig / to_c_assign
----------------------------------------------------------------------

function Code.CodeGlobalRef:lower_code_global_ref_to_c_name(c_emission)
  error("code_to_c: unsupported global ref", 3)
end
function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_name(c_emission)
  return c_emission:func_name(self.func)
end
function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_name(c_emission)
  return self.extern.spelling or self.extern.text
end
function Code.CodeGlobalRefGlobal:lower_code_global_ref_to_c_name(c_emission)
  return "__global_" .. self.global.text
end
function Code.CodeGlobalRefData:lower_code_global_ref_to_c_name(c_emission)
  return "__data_" .. self.data.text
end

function Code.CodeGlobalRef:lower_code_global_ref_to_c_sig(c_emission)
  return nil
end
function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_sig(c_emission)
  return c_emission:func_sig(self.func)
end
function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_sig(c_emission)
  return c_emission:extern_sig(self.extern)
end

function Code.CodeGlobalRef:lower_code_global_ref_to_c_assign(c_emission, dst)
  error("code_to_c: unsupported global ref assign", 3)
end
function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_assign(c_emission, dst)
  local name = self:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendStmtAssign(dst, C.CBackendAtomSymbol(name, nil))
end
function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_assign(c_emission, dst)
  local name = self:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendStmtAssign(dst, C.CBackendAtomSymbol(name, nil))
end

----------------------------------------------------------------------
-- CodeIntOverflow → lower_code_int_overflow_to_c
----------------------------------------------------------------------

function Code.CodeIntOverflow:lower_code_int_overflow_to_c() return "" end
function Code.CodeIntWrap:lower_code_int_overflow_to_c() return "" end
function Code.CodeIntTrapOnOverflow:lower_code_int_overflow_to_c() return " /* trap on overflow */" end
function Code.CodeIntAssumeNoOverflow:lower_code_int_overflow_to_c() return " /* assume no overflow */" end

----------------------------------------------------------------------
-- CodeCallTarget → lower_code_call_target_to_c
----------------------------------------------------------------------

function Code.CodeCallTarget:lower_code_call_target_to_c(c_emission)
  error("code_to_c: unsupported call target", 3)
end
function Code.CodeCallDirect:lower_code_call_target_to_c(c_emission)
  return C.CBackendCallTarget(c_emission:func_name(self.func))
end
function Code.CodeCallExtern:lower_code_call_target_to_c(c_emission)
  return C.CBackendCallTarget(self.extern.spelling or self.extern.text)
end
function Code.CodeCallIndirect:lower_code_call_target_to_c(c_emission)
  local _, callee = self.callee:code_to_c_materialize_atom(c_emission)
  return C.CBackendCallIndirect(callee)
end
function Code.CodeCallClosure:lower_code_call_target_to_c(c_emission)
  local _, closure = self.closure:code_to_c_materialize_atom(c_emission)
  return C.CBackendCallClosure(closure)
end
