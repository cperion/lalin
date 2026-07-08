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
function Sem.FieldByName:code_to_c_field_name() return self.field_name end
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
  local cty = self.ty:code_to_c_backend_type()
  return C.CBackendPlaceLocal(self.local_id:code_to_c_local_id(), cty)
end
function Code.CodePlaceGlobal:lower_code_place_to_c(c_emission)
  local cty = self.ty:code_to_c_backend_type()
  return C.CBackendPlaceGlobal(C.CBackendGlobalId(self.global.text), cty)
end
function Code.CodePlaceData:lower_code_place_to_c(c_emission)
  local cty = self.ty:code_to_c_backend_type()
  return C.CBackendPlaceGlobal(C.CBackendGlobalId("__data_" .. self.data.text), cty)
end
function Code.CodePlaceDeref:lower_code_place_to_c(c_emission)
  local cty = self.ty:code_to_c_backend_type()
  local addr_atom = C.CBackendAtomLocal(self.addr:code_to_c_local_id())
  return C.CBackendPlaceDeref(addr_atom, cty, self.align)
end
function Code.CodePlaceField:lower_code_place_to_c(c_emission)
  local cty = self.ty:code_to_c_backend_type()
  local base = self.base:lower_code_place_to_c(c_emission)
  return C.CBackendPlaceField(base, C.CBackendName(self.field:code_to_c_field_name()), cty, self.offset, self.size, self.align)
end
function Code.CodePlaceIndex:lower_code_place_to_c(c_emission)
  local cty = self.ty:code_to_c_backend_type()
  local base = self.base:lower_code_place_to_c(c_emission)
  local idx = C.CBackendAtomLocal(self.index:code_to_c_local_id())
  return C.CBackendPlaceIndex(base, idx, cty, self.elem_size)
end
function Code.CodePlaceBytes:lower_code_place_to_c(c_emission)
  local cty = self.ty:code_to_c_backend_type()
  local base_atom = C.CBackendAtomLocal(self.base:code_to_c_local_id())
  return C.CBackendPlaceBytes(base_atom, self.offset, cty, self.size, self.align)
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
  return stmts, C.CBackendPlaceDeref(addr, self.ty:code_to_c_backend_type(), nil)
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
  stmts[#stmts + 1] = C.CBackendPlaceLoad(dst, place)
  return stmts, dst
end

function Code.CodeInstAlias:code_to_c_materialize_base_value(c_emission)
  return self.src:code_to_c_materialize_atom(c_emission)
end

function Code.CodeInstCast:code_to_c_materialize_base_value(c_emission)
  local stmts, src = self.value:code_to_c_materialize_atom(c_emission)
  if self.op ~= nil then
    local dst = c_emission:temp(self.to)
    stmts[#stmts + 1] = C.CBackendAssign(dst, C.CBackendRCast(self.op, self.to:code_to_c_backend_type(), src))
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
  return C.CBackendName(self.func.text)
end
function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendName(self.extern.text)
end
function Code.CodeGlobalRefGlobal:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendName("__global_" .. self.global.text)
end
function Code.CodeGlobalRefData:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendName("__data_" .. self.data.text)
end

function Code.CodeGlobalRef:lower_code_global_ref_to_c_sig(c_emission)
  return nil
end
function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_sig(c_emission)
  return C.CBackendFuncSigId(self.func.text .. "_sig")
end
function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_sig(c_emission)
  return C.CBackendFuncSigId(self.extern.text .. "_sig")
end

function Code.CodeGlobalRef:lower_code_global_ref_to_c_assign(c_emission, dst)
  error("code_to_c: unsupported global ref assign", 3)
end
function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_assign(c_emission, dst)
  local name = self:lower_code_global_ref_to_c_name()
  local sig_id = self:lower_code_global_ref_to_c_sig()
  return C.CBackendAssign(dst, C.CBackendRFuncAddr(name, sig_id))
end

function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_assign(c_emission, dst)
  local name = self:lower_code_global_ref_to_c_name()
  local sig_id = self:lower_code_global_ref_to_c_sig()
  return C.CBackendAssign(dst, C.CBackendRExternAddr(name, sig_id))
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
  return C.CBackendCallDirect(C.CBackendName(self.func.text))
end

function Code.CodeCallExtern:lower_code_call_target_to_c(c_emission)
  return C.CBackendCallExtern(C.CBackendName(self.extern.text))
end

function Code.CodeCallIndirect:lower_code_call_target_to_c(c_emission)
  local callee_atom = C.CBackendAtomLocal(self.callee:code_to_c_local_id())
  return C.CBackendCallIndirect(callee_atom, C.CBackendFuncSigId(self.sig.text))
end
function Code.CodeCallClosure:lower_code_call_target_to_c(c_emission)
  local closure_atom = C.CBackendAtomLocal(self.closure:code_to_c_local_id())
  return C.CBackendCallClosure(closure_atom, C.CBackendFuncSigId(self.sig.text))
end

----------------------------------------------------------------------
-- CodeType → code_to_c_backend_type (scalar CBackendType mapping)
----------------------------------------------------------------------

function Code.CodeType:code_to_c_backend_type()
  error("code_to_c: unsupported CodeType for backend conversion: " .. tostring(self), 3)
end
function Code.CodeTyVoid:code_to_c_backend_type() return C.CBackendVoid end
function Code.CodeTyBool8:code_to_c_backend_type() return C.CBackendBool8 end
function Code.CodeTyInt:code_to_c_backend_type()
  local scalar
  if self.signedness == Code.CodeSigned then
    if     self.bits == 8  then scalar = Core.ScalarI8
    elseif self.bits == 16 then scalar = Core.ScalarI16
    elseif self.bits == 32 then scalar = Core.ScalarI32
    elseif self.bits == 64 then scalar = Core.ScalarI64
    end
  else
    if     self.bits == 8  then scalar = Core.ScalarU8
    elseif self.bits == 16 then scalar = Core.ScalarU16
    elseif self.bits == 32 then scalar = Core.ScalarU32
    elseif self.bits == 64 then scalar = Core.ScalarU64
    end
  end
  if scalar == nil then error("code_to_c: unsupported int bits: " .. tostring(self.bits), 3) end
  return C.CBackendScalar(scalar)
end
function Code.CodeTyFloat:code_to_c_backend_type()
  local scalar = self.bits == 32 and Core.ScalarF32 or Core.ScalarF64
  return C.CBackendScalar(scalar)
end
function Code.CodeTyIndex:code_to_c_backend_type() return C.CBackendIndex end
function Code.CodeTyDataPtr:code_to_c_backend_type()
  local pointee = self.pointee and self.pointee:code_to_c_backend_type() or nil
  return C.CBackendDataPtr(pointee)
end

function Code.CodeTyNamed:code_to_c_backend_type()
  return C.CBackendNamed(C.CTypeId(self.module_name, self.type_name))
end

function Code.CodeTyArray:code_to_c_backend_type()
  return C.CBackendArray(self.elem:code_to_c_backend_type(), self.count)
end

function Code.CodeTyCodePtr:code_to_c_backend_type()
  return C.CBackendCodePtr(C.CBackendFuncSigId(self.sig.text))
end

function Code.CodeTySlice:code_to_c_backend_type()
  return C.CBackendSliceDescriptor(self.elem:code_to_c_backend_type())
end

function Code.CodeTyView:code_to_c_backend_type()
  return C.CBackendViewDescriptor(self.elem:code_to_c_backend_type())
end

function Code.CodeTyByteSpan:code_to_c_backend_type()
  return C.CBackendByteSpanDescriptor
end

function Code.CodeTyClosure:code_to_c_backend_type()
  return C.CBackendClosureDescriptor(C.CBackendFuncSigId(self.sig.text))
end
----------------------------------------------------------------------
-- CodeValueId / CodeParam → CBackendLocalId / CBackendLocal mapping
----------------------------------------------------------------------

function Code.CodeValueId:code_to_c_local_id()
  return C.CBackendLocalId(self.text)
end

function Code.CodeLocalId:code_to_c_local_id()
  return C.CBackendLocalId(self.text)
end

function Code.CodeParam:code_to_c_local()
  return C.CBackendLocal(
    self.value:code_to_c_local_id(),
    C.CBackendName(self.name),
    self.ty:code_to_c_backend_type()
  )
end

----------------------------------------------------------------------
-- Scalar instruction lowering: CodeInst → CBackendStmt[]
----------------------------------------------------------------------

function Code.CodeInst:lower_to_c_backend(lowered)
  -- lowered = { stmts = [], helpers = {}, locals = {}, sigs = {} } accumulator
  local op = self.op
  if op == nil then return end
  op:lower_code_inst_to_c(self, lowered)
end

function Code.CodeInstOp:lower_code_inst_to_c(inst, lowered)
  -- parent default: unsupported
  error("code_to_c: unsupported instruction for lowering: " .. tostring(self), 3)
end

function Code.CodeInstConst:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.const.ty:code_to_c_backend_type()
  local lit = self.const:code_to_c_literal()
  local atom
  if lit ~= nil then
    local lit_val = self.const.literal
    if lit_val ~= nil then
      atom = C.CBackendAtomLiteral(ty, lit_val)
    else
      atom = C.CBackendAtomNull(ty)
    end
  else
    atom = C.CBackendAtomNull(ty)
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(dst_id, C.CBackendRAtom(atom))
end

function Code.CodeInstBinary:lower_code_inst_to_c(inst, lowered)
  -- Scalar binary: use a helper call
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local sem = self.semantics
  local overflow
  if sem and sem.overflow then
    overflow = C.CBackendIntWrap
  else
    overflow = C.CBackendIntWrap
  end
  local spec = C.CBackendHelperIntBinary(self.op, ty, overflow)
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  local lhs_atom = C.CBackendAtomLocal(self.lhs:code_to_c_local_id())
  local rhs_atom = C.CBackendAtomLocal(self.rhs:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(dst_id, helper_id, { lhs_atom, rhs_atom })
end

function Code.CodeInstAlias:lower_code_inst_to_c(inst, lowered)
  -- Alias is a no-op; the value id is just another name for the same local
  -- We register the mapping so subsequent uses resolve correctly
  -- For now: no stmt emission needed
end

----------------------------------------------------------------------
-- CodeInstUnary: negate, bitnot, boolnot via helper call
----------------------------------------------------------------------

function Code.CodeInstUnary:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local spec = C.CBackendHelperUnary(self.op, ty)
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  local val_atom = C.CBackendAtomLocal(self.value:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(dst_id, helper_id, { val_atom })
end

----------------------------------------------------------------------
-- CodeInstCast: type cast via assign
----------------------------------------------------------------------

function Code.CodeInstCast:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local to_ty = self.to:code_to_c_backend_type()
  local src_atom = C.CBackendAtomLocal(self.value:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(dst_id, C.CBackendRCast(self.op, to_ty, src_atom))
end

----------------------------------------------------------------------
-- CodeInstCompare: EQ, NE, LT, LE, GT, GE → RCompare assign
----------------------------------------------------------------------

function Code.CodeInstCompare:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local operand_ty = self.operand_ty:code_to_c_backend_type()
  local lhs_atom = C.CBackendAtomLocal(self.lhs:code_to_c_local_id())
  local rhs_atom = C.CBackendAtomLocal(self.rhs:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(dst_id, C.CBackendRCompare(self.op, operand_ty, lhs_atom, rhs_atom))
end

----------------------------------------------------------------------
-- CodeInstSelect: ternary select → RSelect assign
----------------------------------------------------------------------

function Code.CodeInstSelect:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local cond_atom = C.CBackendAtomLocal(self.cond:code_to_c_local_id())
  local then_atom = C.CBackendAtomLocal(self.then_value:code_to_c_local_id())
  local else_atom = C.CBackendAtomLocal(self.else_value:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(dst_id, C.CBackendRSelect(ty, cond_atom, then_atom, else_atom))
end

----------------------------------------------------------------------
-- CodeInstFloatBinary: float binary op via helper call
----------------------------------------------------------------------

function Code.CodeInstFloatBinary:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local spec = C.CBackendHelperFloatBinary(self.op, ty)
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  local lhs_atom = C.CBackendAtomLocal(self.lhs:code_to_c_local_id())
  local rhs_atom = C.CBackendAtomLocal(self.rhs:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(dst_id, helper_id, { lhs_atom, rhs_atom })
end

----------------------------------------------------------------------
-- CodeInstIntrinsicValue / CodeInstIntrinsicVoid → helper call
----------------------------------------------------------------------

function Code.CodeInstIntrinsicValue:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local spec = C.CBackendHelperIntrinsic(self.op, ty)
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  local args = {}
  for i = 1, #(self.args or {}) do
    args[i] = C.CBackendAtomLocal(self.args[i]:code_to_c_local_id())
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(dst_id, helper_id, args)
end

function Code.CodeInstIntrinsicVoid:lower_code_inst_to_c(inst, lowered)
  local ty = self.ty:code_to_c_backend_type()
  local spec = C.CBackendHelperIntrinsic(self.op, ty)
  local helper_id = C.CBackendHelperId("helper_intrinsic_void")
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  local args = {}
  for i = 1, #(self.args or {}) do
    args[i] = C.CBackendAtomLocal(self.args[i]:code_to_c_local_id())
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(nil, helper_id, args)
end

----------------------------------------------------------------------
-- CodeInstLoad: load from place
----------------------------------------------------------------------

function Code.CodeInstLoad:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local place = self.place:lower_code_place_to_c(nil)
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id, place)
end

----------------------------------------------------------------------
-- CodeInstStore: store to place
----------------------------------------------------------------------

function Code.CodeInstStore:lower_code_inst_to_c(inst, lowered)
  local place = self.place:lower_code_place_to_c(nil)
  local val_atom = C.CBackendAtomLocal(self.value:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceStore(place, val_atom)
end

----------------------------------------------------------------------
-- CodeInstAddrOf: address-of place → assign
----------------------------------------------------------------------

function Code.CodeInstAddrOf:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local place = self.place:lower_code_place_to_c(nil)
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(dst_id, C.CBackendRAddrOfPlace(place))
end

----------------------------------------------------------------------
-- CodeInstPtrOffset: pointer offset arithmetic → assign
----------------------------------------------------------------------

function Code.CodeInstPtrOffset:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local base_atom = C.CBackendAtomLocal(self.base:code_to_c_local_id())
  local idx_atom = C.CBackendAtomLocal(self.index:code_to_c_local_id())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(dst_id, C.CBackendRPtrOffset(base_atom, idx_atom, self.elem_size, self.const_offset))
end

----------------------------------------------------------------------
-- CodeInstGlobalRef: function / extern reference → assign
----------------------------------------------------------------------

function Code.CodeInstGlobalRef:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  -- Use the instance (not type) method to get assign stmt
  local assign = self.ref:lower_code_global_ref_to_c_assign(nil, dst_id)
  lowered.stmts[#lowered.stmts + 1] = assign
end

----------------------------------------------------------------------
-- CodeInstCall: direct / extern / indirect call
----------------------------------------------------------------------

function Code.CodeInstCall:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst and self.dst:code_to_c_local_id() or nil
  local target = self.target:lower_code_call_target_to_c(nil)
  local args = {}
  for i = 1, #(self.args or {}) do
    args[i] = C.CBackendAtomLocal(self.args[i]:code_to_c_local_id())
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendCall(dst_id, target, args)
end

----------------------------------------------------------------------
-- CodeInstAggregate: struct aggregate init → CBackendAggregateInit
----------------------------------------------------------------------

function Code.CodeInstAggregate:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local fields = {}
  for i = 1, #(self.fields or {}) do
    local f = self.fields[i]
    fields[i] = C.CBackendAggregateFieldInit(
      C.CBackendName(f.field:code_to_c_field_name()),
      C.CBackendAtomLocal(f.value:code_to_c_local_id()),
      nil
    )
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAggregateInit(
    C.CBackendPlaceLocal(dst_id, ty), ty, fields
  )
end

----------------------------------------------------------------------
-- CodeInstArray: array init → CBackendArrayInit
----------------------------------------------------------------------

function Code.CodeInstArray:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local elems = {}
  for i = 1, #(self.elems or {}) do
    local e = self.elems[i]
    elems[i] = C.CBackendArrayElemInit(
      e.index,
      C.CBackendAtomLocal(e.value:code_to_c_local_id())
    )
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendArrayInit(
    C.CBackendPlaceLocal(dst_id, ty), ty, elems
  )
end

----------------------------------------------------------------------
-- CodeInstViewMake: view aggregate init
----------------------------------------------------------------------

function Code.CodeInstViewMake:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = C.CBackendViewDescriptor(self.elem_ty:code_to_c_backend_type())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAggregateInit(
    C.CBackendPlaceLocal(dst_id, ty), ty,
    {
      C.CBackendAggregateFieldInit(C.CBackendName("data"),
        C.CBackendAtomLocal(self.data:code_to_c_local_id()), 0),
      C.CBackendAggregateFieldInit(C.CBackendName("len"),
        C.CBackendAtomLocal(self.len:code_to_c_local_id()), nil),
      C.CBackendAggregateFieldInit(C.CBackendName("stride"),
        C.CBackendAtomLocal(self.stride:code_to_c_local_id()), nil),
    }
  )
end

----------------------------------------------------------------------
-- CodeInstViewData: load view.data field
----------------------------------------------------------------------

function Code.CodeInstViewData:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local view_local = C.CBackendPlaceLocal(
    self.view:code_to_c_local_id(),
    C.CBackendViewDescriptor(Code.CodeTyVoid:code_to_c_backend_type())
  )
  local data_ty = C.CBackendDataPtr(Code.CodeTyVoid:code_to_c_backend_type())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(view_local, C.CBackendName("data"), data_ty, 0, nil, nil)
  )
end

----------------------------------------------------------------------
-- CodeInstViewLen: load view.len field
----------------------------------------------------------------------

function Code.CodeInstViewLen:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local view_local = C.CBackendPlaceLocal(
    self.view:code_to_c_local_id(),
    C.CBackendViewDescriptor(Code.CodeTyVoid:code_to_c_backend_type())
  )
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(view_local, C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)
  )
end

----------------------------------------------------------------------
-- CodeInstViewStride: load view.stride field
----------------------------------------------------------------------

function Code.CodeInstViewStride:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local view_local = C.CBackendPlaceLocal(
    self.view:code_to_c_local_id(),
    C.CBackendViewDescriptor(Code.CodeTyVoid:code_to_c_backend_type())
  )
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(view_local, C.CBackendName("stride"), C.CBackendIndex, 0, nil, nil)
  )
end

----------------------------------------------------------------------
-- CodeInstSliceMake: slice aggregate init
----------------------------------------------------------------------

function Code.CodeInstSliceMake:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = C.CBackendSliceDescriptor(self.elem_ty:code_to_c_backend_type())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAggregateInit(
    C.CBackendPlaceLocal(dst_id, ty), ty,
    {
      C.CBackendAggregateFieldInit(C.CBackendName("data"),
        C.CBackendAtomLocal(self.data:code_to_c_local_id()), 0),
      C.CBackendAggregateFieldInit(C.CBackendName("len"),
        C.CBackendAtomLocal(self.len:code_to_c_local_id()), nil),
    }
  )
end

----------------------------------------------------------------------
-- CodeInstSliceData: load slice.data field
----------------------------------------------------------------------

function Code.CodeInstSliceData:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local slice_local = C.CBackendPlaceLocal(
    self.slice:code_to_c_local_id(),
    C.CBackendSliceDescriptor(Code.CodeTyVoid:code_to_c_backend_type())
  )
  local data_ty = C.CBackendDataPtr(Code.CodeTyVoid:code_to_c_backend_type())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(slice_local, C.CBackendName("data"), data_ty, 0, nil, nil)
  )
end

----------------------------------------------------------------------
-- CodeInstSliceLen: load slice.len field
----------------------------------------------------------------------

function Code.CodeInstSliceLen:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local slice_local = C.CBackendPlaceLocal(
    self.slice:code_to_c_local_id(),
    C.CBackendSliceDescriptor(Code.CodeTyVoid:code_to_c_backend_type())
  )
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(slice_local, C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)
  )
end

----------------------------------------------------------------------
-- CodeInstByteSpanMake: byte span aggregate init
----------------------------------------------------------------------

function Code.CodeInstByteSpanMake:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = Code.CodeTyByteSpan:code_to_c_backend_type()
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAggregateInit(
    C.CBackendPlaceLocal(dst_id, ty), ty,
    {
      C.CBackendAggregateFieldInit(C.CBackendName("data"),
        C.CBackendAtomLocal(self.data:code_to_c_local_id()), 0),
      C.CBackendAggregateFieldInit(C.CBackendName("len"),
        C.CBackendAtomLocal(self.len:code_to_c_local_id()), nil),
    }
  )
end

----------------------------------------------------------------------
-- CodeInstByteSpanData: load bytespan.data field
----------------------------------------------------------------------

function Code.CodeInstByteSpanData:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local span_local = C.CBackendPlaceLocal(
    self.span:code_to_c_local_id(),
    Code.CodeTyByteSpan:code_to_c_backend_type()
  )
  local data_ty = C.CBackendDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned):code_to_c_backend_type())
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(span_local, C.CBackendName("data"), data_ty, 0, nil, nil)
  )
end

----------------------------------------------------------------------
-- CodeInstByteSpanLen: load bytespan.len field
----------------------------------------------------------------------

function Code.CodeInstByteSpanLen:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local span_local = C.CBackendPlaceLocal(
    self.span:code_to_c_local_id(),
    Code.CodeTyByteSpan:code_to_c_backend_type()
  )
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(span_local, C.CBackendName("len"), C.CBackendIndex, 0, nil, nil)
  )
end

----------------------------------------------------------------------
-- CodeInstClosure: closure aggregate init (fn + ctx)
----------------------------------------------------------------------

function Code.CodeInstClosure:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAggregateInit(
    C.CBackendPlaceLocal(dst_id, ty), ty,
    {
      C.CBackendAggregateFieldInit(C.CBackendName("fn"),
        C.CBackendAtomLocal(self.fn:code_to_c_local_id()), 0),
      C.CBackendAggregateFieldInit(C.CBackendName("ctx"),
        C.CBackendAtomLocal(self.ctx:code_to_c_local_id()), nil),
    }
  )
end

----------------------------------------------------------------------
-- CodeInstVariantCtor: variant construction (tag + optional payload)
----------------------------------------------------------------------

function Code.CodeInstVariantCtor:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local ty = self.ty:code_to_c_backend_type()
  local dst_place = C.CBackendPlaceLocal(dst_id, ty)
  -- Write __tag field
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAggregateInit(
    dst_place, ty,
    {
      C.CBackendAggregateFieldInit(C.CBackendName("__tag"),
        C.CBackendAtomLiteral(C.CBackendScalar(Core.ScalarU32),
          Core.LitInt(tostring(self.variant.tag_value))),
        0),
    }
  )
  -- Write payload if present
  if self.payload ~= nil then
    local union_id = self.variant.owner_ty:code_to_c_variant_payload_union_id()
    local payload_place = C.CBackendPlaceField(
      dst_place,
      C.CBackendName("__payload"),
      union_id and C.CBackendNamed(union_id) or C.CBackendVoid,
      0, nil, nil
    )
    local variant_place = C.CBackendPlaceField(
      payload_place,
      C.CBackendName(self.variant.variant_name),
      self.variant.payload_ty and self.variant.payload_ty:code_to_c_backend_type() or C.CBackendVoid,
      0, nil, nil
    )
    lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceStore(
      variant_place,
      C.CBackendAtomLocal(self.payload:code_to_c_local_id())
    )
  end
end

----------------------------------------------------------------------
-- CodeInstVariantTag: load __tag field from variant value
----------------------------------------------------------------------

function Code.CodeInstVariantTag:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local value_id = self.value:code_to_c_local_id()
  local tag_ty = self.tag_ty:code_to_c_backend_type()
  -- Look up the owner type from lowered.value_types if available
  local owner_ty = (lowered.value_types and lowered.value_types[self.value.text])
  local owner_cty = owner_ty and owner_ty:code_to_c_backend_type() or C.CBackendVoid
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id,
    C.CBackendPlaceField(
      C.CBackendPlaceLocal(value_id, owner_cty),
      C.CBackendName("__tag"),
      tag_ty, 0, nil, nil
    )
  )
end

----------------------------------------------------------------------
-- CodeInstVariantPayload: load payload field from variant value
----------------------------------------------------------------------

function Code.CodeInstVariantPayload:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local value_id = self.value:code_to_c_local_id()
  local owner_ty = self.variant.owner_ty
  local owner_cty = owner_ty and owner_ty:code_to_c_backend_type() or C.CBackendVoid
  local base_place = C.CBackendPlaceLocal(value_id, owner_cty)
  -- Navigate to __payload.variant_name
  local union_id = owner_ty and owner_ty:code_to_c_variant_payload_union_id()
  local payload_place = C.CBackendPlaceField(
    base_place,
    C.CBackendName("__payload"),
    union_id and C.CBackendNamed(union_id) or C.CBackendVoid,
    0, nil, nil
  )
  local variant_place = C.CBackendPlaceField(
    payload_place,
    C.CBackendName(self.variant.variant_name),
    self.variant.payload_ty and self.variant.payload_ty:code_to_c_backend_type() or C.CBackendVoid,
    0, nil, nil
  )
  lowered.stmts[#lowered.stmts + 1] = C.CBackendPlaceLoad(dst_id, variant_place)
end

----------------------------------------------------------------------
-- CodeInstAtomicLoad: atomic load via helper
----------------------------------------------------------------------

function Code.CodeInstAtomicLoad:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local access = self.access
  local trap = C.CBackendMayTrap
  if access.trap == Code.CodeMustNotTrap then trap = C.CBackendMustNotTrap
  elseif access.trap == Code.CodeCheckedTrap then trap = C.CBackendCheckedTrap end
  local c_access = C.CBackendMemoryAccess(
    access.ty:code_to_c_backend_type(),
    access.align, trap, access.volatile, access.ordering
  )
  local helper_id = C.CBackendHelperId("helper_atomic_load")
  local spec = C.CBackendHelperAtomicLoad(c_access)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  -- Get address from place
  local addr_atom
  if self.place:code_to_c_is_deref() then
    local cplace = self.place:lower_code_place_to_c(nil)
    addr_atom = cplace.addr
  else
    local addr_id = C.CBackendLocalId("atomic_addr_load")
    lowered.locals[#lowered.locals + 1] = C.CBackendLocal(addr_id, C.CBackendName("atomic_addr_load"),
      C.CBackendDataPtr(c_access.ty))
    lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(addr_id,
      C.CBackendRAddrOfPlace(self.place:lower_code_place_to_c(nil)))
    addr_atom = C.CBackendAtomLocal(addr_id)
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(dst_id, helper_id, { addr_atom })
end

----------------------------------------------------------------------
-- CodeInstAtomicStore: atomic store via helper
----------------------------------------------------------------------

function Code.CodeInstAtomicStore:lower_code_inst_to_c(inst, lowered)
  local access = self.access
  local trap = C.CBackendMayTrap
  if access.trap == Code.CodeMustNotTrap then trap = C.CBackendMustNotTrap
  elseif access.trap == Code.CodeCheckedTrap then trap = C.CBackendCheckedTrap end
  local c_access = C.CBackendMemoryAccess(
    access.ty:code_to_c_backend_type(),
    access.align, trap, access.volatile, access.ordering
  )
  local helper_id = C.CBackendHelperId("helper_atomic_store")
  local spec = C.CBackendHelperAtomicStore(c_access)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  local addr_atom
  if self.place:code_to_c_is_deref() then
    local cplace = self.place:lower_code_place_to_c(nil)
    addr_atom = cplace.addr
  else
    local addr_id = C.CBackendLocalId("atomic_addr_store")
    lowered.locals[#lowered.locals + 1] = C.CBackendLocal(addr_id, C.CBackendName("atomic_addr_store"),
      C.CBackendDataPtr(c_access.ty))
    lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(addr_id,
      C.CBackendRAddrOfPlace(self.place:lower_code_place_to_c(nil)))
    addr_atom = C.CBackendAtomLocal(addr_id)
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(nil, helper_id, {
    addr_atom,
    C.CBackendAtomLocal(self.value:code_to_c_local_id()),
  })
end

----------------------------------------------------------------------
-- CodeInstAtomicRmw: atomic read-modify-write via helper
----------------------------------------------------------------------

function Code.CodeInstAtomicRmw:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local access = self.access
  local trap = C.CBackendMayTrap
  if access.trap == Code.CodeMustNotTrap then trap = C.CBackendMustNotTrap
  elseif access.trap == Code.CodeCheckedTrap then trap = C.CBackendCheckedTrap end
  local c_access = C.CBackendMemoryAccess(
    access.ty:code_to_c_backend_type(),
    access.align, trap, access.volatile, access.ordering
  )
  local helper_id = C.CBackendHelperId("helper_atomic_rmw")
  local spec = C.CBackendHelperAtomicRmw(self.op, c_access)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  local addr_atom
  if self.place:code_to_c_is_deref() then
    local cplace = self.place:lower_code_place_to_c(nil)
    addr_atom = cplace.addr
  else
    local addr_id = C.CBackendLocalId("atomic_addr_rmw")
    lowered.locals[#lowered.locals + 1] = C.CBackendLocal(addr_id, C.CBackendName("atomic_addr_rmw"),
      C.CBackendDataPtr(c_access.ty))
    lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(addr_id,
      C.CBackendRAddrOfPlace(self.place:lower_code_place_to_c(nil)))
    addr_atom = C.CBackendAtomLocal(addr_id)
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(dst_id, helper_id, {
    addr_atom,
    C.CBackendAtomLocal(self.value:code_to_c_local_id()),
  })
end

----------------------------------------------------------------------
-- CodeInstAtomicCas: atomic compare-and-swap via helper
----------------------------------------------------------------------

function Code.CodeInstAtomicCas:lower_code_inst_to_c(inst, lowered)
  local dst_id = self.dst:code_to_c_local_id()
  local access = self.access
  local trap = C.CBackendMayTrap
  if access.trap == Code.CodeMustNotTrap then trap = C.CBackendMustNotTrap
  elseif access.trap == Code.CodeCheckedTrap then trap = C.CBackendCheckedTrap end
  local c_access = C.CBackendMemoryAccess(
    access.ty:code_to_c_backend_type(),
    access.align, trap, access.volatile, access.ordering
  )
  local helper_id = C.CBackendHelperId("helper_atomic_cas")
  local spec = C.CBackendHelperAtomicCas(c_access, self.ordering, self.ordering)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  -- Address-of expected value
  local expected_addr_id = C.CBackendLocalId("atomic_cas_expected_addr")
  lowered.locals[#lowered.locals + 1] = C.CBackendLocal(expected_addr_id,
    C.CBackendName("atomic_cas_expected_addr"), C.CBackendDataPtr(c_access.ty))
  lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(expected_addr_id,
    C.CBackendRAddrOfPlace(C.CBackendPlaceLocal(
      self.expected:code_to_c_local_id(), c_access.ty)))
  -- Get atomic address
  local addr_atom
  if self.place:code_to_c_is_deref() then
    local cplace = self.place:lower_code_place_to_c(nil)
    addr_atom = cplace.addr
  else
    local addr_id = C.CBackendLocalId("atomic_addr_cas")
    lowered.locals[#lowered.locals + 1] = C.CBackendLocal(addr_id, C.CBackendName("atomic_addr_cas"),
      C.CBackendDataPtr(c_access.ty))
    lowered.stmts[#lowered.stmts + 1] = C.CBackendAssign(addr_id,
      C.CBackendRAddrOfPlace(self.place:lower_code_place_to_c(nil)))
    addr_atom = C.CBackendAtomLocal(addr_id)
  end
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(dst_id, helper_id, {
    addr_atom,
    C.CBackendAtomLocal(expected_addr_id),
    C.CBackendAtomLocal(self.replacement:code_to_c_local_id()),
  })
end

----------------------------------------------------------------------
-- CodeInstAtomicFence: atomic fence via helper
----------------------------------------------------------------------

function Code.CodeInstAtomicFence:lower_code_inst_to_c(inst, lowered)
  local helper_id = C.CBackendHelperId("helper_atomic_fence")
  local spec = C.CBackendHelperAtomicFence(self.ordering)
  lowered.helpers[#lowered.helpers + 1] = C.CBackendHelperUse(helper_id, spec)
  lowered.stmts[#lowered.stmts + 1] = C.CBackendHelperCall(nil, helper_id, {})
end

----------------------------------------------------------------------
-- Terminator lowering: CodeTermOp → CBackendTerminator
----------------------------------------------------------------------

function Code.CodeTerm:lower_to_c_backend_term(lowered)
  if self.op then
    return self.op:lower_code_term_to_c(self, lowered)
  end
  return C.CBackendTrap
end

function Code.CodeTermOp:lower_code_term_to_c(term, lowered)
  error("code_to_c: unsupported terminator for lowering: " .. tostring(self), 3)
end

function Code.CodeTermReturn:lower_code_term_to_c(term, lowered)
  if #(self.values or {}) == 0 then
    return C.CBackendReturnVoid
  end
  local val = self.values[1]
  local atom = C.CBackendAtomLocal(val:code_to_c_local_id())
  return C.CBackendReturn(atom)
end

function Code.CodeTermTrap:lower_code_term_to_c(term, lowered)
  return C.CBackendTrap
end

function Code.CodeTermUnreachable:lower_code_term_to_c(term, lowered)
  return C.CBackendTrap
end

function Code.CodeTermJump:lower_code_term_to_c(term, lowered)
  local dest_label = C.CBackendLabel(self.dest.text)
  local args = {}
  for i, arg in ipairs(self.args or {}) do
    args[i] = C.CBackendAtomLocal(arg:code_to_c_local_id())
  end
  return C.CBackendGoto(dest_label, args)
end

function Code.CodeTermBranch:lower_code_term_to_c(term, lowered)
  local cond = C.CBackendAtomLocal(self.cond:code_to_c_local_id())
  local then_label = C.CBackendLabel(self.then_dest.text)
  local else_label = C.CBackendLabel(self.else_dest.text)
  local then_args = {}
  for i, arg in ipairs(self.then_args or {}) do
    then_args[i] = C.CBackendAtomLocal(arg:code_to_c_local_id())
  end
  local else_args = {}
  for i, arg in ipairs(self.else_args or {}) do
    else_args[i] = C.CBackendAtomLocal(arg:code_to_c_local_id())
  end
  return C.CBackendIfGoto(cond, then_label, then_args, else_label, else_args)
end

function Code.CodeTermSwitch:lower_code_term_to_c(term, lowered)
  local cases = {}
  for i, case in ipairs(self.cases or {}) do
    local cargs = {}
    for j, arg in ipairs(case.args or {}) do
      cargs[j] = C.CBackendAtomLocal(arg:code_to_c_local_id())
    end
    cases[i] = C.CBackendSwitchCase(case.literal, C.CBackendLabel(case.dest.text), cargs)
  end
  local def_args = {}
  for i, arg in ipairs(self.default_args or {}) do
    def_args[i] = C.CBackendAtomLocal(arg:code_to_c_local_id())
  end
  return C.CBackendSwitchGoto(
    C.CBackendAtomLocal(self.value:code_to_c_local_id()),
    cases,
    C.CBackendLabel(self.default_dest.text),
    def_args
  )
end

function Code.CodeTermVariantSwitch:lower_code_term_to_c(term, lowered)
  local cases = {}
  for i, case in ipairs(self.cases or {}) do
    local cargs = {}
    for j, arg in ipairs(case.args or {}) do
      cargs[j] = C.CBackendAtomLocal(arg:code_to_c_local_id())
    end
    cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(case.variant.tag_value)), C.CBackendLabel(case.dest.text), cargs)
  end
  local def_args = {}
  for i, arg in ipairs(self.default_args or {}) do
    def_args[i] = C.CBackendAtomLocal(arg:code_to_c_local_id())
  end
  return C.CBackendSwitchGoto(
    C.CBackendAtomLocal(self.tag:code_to_c_local_id()),
    cases,
    C.CBackendLabel(self.default_dest.text),
    def_args
  )
end
