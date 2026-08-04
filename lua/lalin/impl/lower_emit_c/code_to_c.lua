-- impl/lower_emit_c/code_to_c.lua
-- Methods on Code.*, Core.*, and C.* types for C emission.
-- Ported from code_to_c.lua.

require("lalin.schema")

local Code    = require("lalin.schema.code")
local Core    = require("lalin.schema.core")
local C       = require("lalin.schema.c")
local Sem     = require("lalin.schema.sem")
local Mem     = require("lalin.schema.mem")
local Lower   = require("lalin.schema.lower")

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
-- CodePlace → code_to_c_is_deref / lower_code_place_to_c
----------------------------------------------------------------------


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
  return C.CBackendPlaceGlobal(C.CBackendGlobalId(self.data.text), cty)
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
-- CodeGlobalRef → lower_code_global_ref_to_c_name / to_c_sig / to_c_assign
----------------------------------------------------------------------

function Code.CodeGlobalRef:lower_code_global_ref_to_c_name(c_emission)
  error("code_to_c: unsupported global ref", 3)
end
function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendName(self.func.text)
end
function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendName(c_emission.extern_symbols:lower_c_extern_symbol_lookup(self.extern):lower_c_extern_symbol())
end
function Code.CodeGlobalRefGlobal:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendName(self.global.text)
end
function Code.CodeGlobalRefData:lower_code_global_ref_to_c_name(c_emission)
  return C.CBackendName(self.data.text)
end

function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_sig(c_emission)
  return C.CBackendFuncSigId(self.func.text .. "_sig")
end
function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_sig(c_emission)
  return c_emission.extern_symbols:lower_c_extern_symbol_lookup(self.extern):lower_c_extern_sig()
end

function Code.CodeGlobalRef:lower_code_global_ref_to_c_assign(c_emission, dst)
  error("code_to_c: unsupported global ref assign", 3)
end
function Code.CodeGlobalRefFunc:lower_code_global_ref_to_c_assign(c_emission, dst)
  local name = self:lower_code_global_ref_to_c_name()
  local sig_id = self:lower_code_global_ref_to_c_sig()
  return C.CBackendAssign(dst, C.CBackendRFuncAddr(name, sig_id))
end

function Code.CodeGlobalRefData:lower_code_global_ref_to_c_assign(_c_emission, dst, ptr_ty)
  return ptr_ty:lower_code_data_ref_assign(
    Lower.LowerCodeDataRefAssignInput(self, dst))
end
function Code.CodeTyDataPtr:lower_code_data_ref_assign(input)
  return C.CBackendAssign(input.dst, C.CBackendRAtom(
    C.CBackendAtomGlobal(C.CBackendGlobalId(input.ref.data.text))))
end

function Code.CodeGlobalRefExtern:lower_code_global_ref_to_c_assign(c_emission, dst)
  local name = self:lower_code_global_ref_to_c_name(c_emission)
  local sig_id = self:lower_code_global_ref_to_c_sig(c_emission)
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
  -- Resolve the internal fn_ id to the public CodeFunc.name so the emitted
  -- call matches the emitted definition and the dlopen symbol contract.
  local symbol = c_emission.func_symbols:lower_c_func_symbol_lookup(self.func):lower_c_func_symbol()
  return C.CBackendCallDirect(C.CBackendName(symbol))
end

function Code.CodeCallExtern:lower_code_call_target_to_c(c_emission)
  -- Resolve the internal extern_ id to the declared C symbol so the emitted
  -- call matches the emitted extern prototype and the linkage contract.
  local symbol = c_emission.extern_symbols:lower_c_extern_symbol_lookup(self.extern):lower_c_extern_symbol()
  return C.CBackendCallExtern(C.CBackendName(symbol))
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

function Code.CodeTyHandle:code_to_c_backend_type()
  return self.repr:code_to_c_backend_type()
end

function Code.CodeTyLease:code_to_c_backend_type()
  return self.base:code_to_c_backend_type()
end

function Code.CodeTyClosure:code_to_c_backend_type()
  return C.CBackendClosureDescriptor(C.CBackendFuncSigId(self.sig.text))
end

function Code.CodeTyImportedC:code_to_c_backend_type()
  return C.CBackendNamed(self.id)
end

function Code.CodeTyImportedCFuncPtr:code_to_c_backend_type()
  return C.CBackendImportedCodePtr(self.sig)
end

function Code.CodeTyVector:code_to_c_backend_type()
  return C.CBackendVector(self.elem:code_to_c_backend_type(), self.lanes)
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

function Lower.LowerCValueTypeProjection:lower_c_value_lookup(value)
  for i = 1, #self.entries do
    if self.entries[i].value == value then return Lower.LowerCValueTypeFound(self.entries[i]) end
  end
  return Lower.LowerCValueTypeMissing(value)
end
function Lower.LowerCValueTypeFound:lower_c_backend_type() return self.entry.code_ty:code_to_c_backend_type() end

-- CodeFuncId -> public C symbol resolution. The projection is built by the
-- module lowering phase from CodeFunc.id/name; the leaves own the outcome.
function Lower.LowerCFuncSymbolProjection:lower_c_func_symbol_lookup(id)
  for i = 1, #self.entries do
    if self.entries[i].func_id == id then return Lower.LowerCFuncSymbolFound(self.entries[i]) end
  end
  return Lower.LowerCFuncSymbolMissing(id)
end
function Lower.LowerCFuncSymbolFound:lower_c_func_symbol() return self.entry.symbol end
function Lower.LowerCFuncSymbolMissing:lower_c_func_symbol()
  error("C lowering missing validated function " .. self.id.text, 2)
end

function Lower.LowerCExternSymbolProjection:lower_c_extern_symbol_lookup(id)
  for i = 1, #self.entries do
    if self.entries[i].extern_id == id then return Lower.LowerCExternSymbolFound(self.entries[i]) end
  end
  return Lower.LowerCExternSymbolMissing(id)
end
function Lower.LowerCExternSymbolFound:lower_c_extern_symbol() return self.entry.symbol end
function Lower.LowerCExternSymbolFound:lower_c_extern_sig() return self.entry.sig end
function Lower.LowerCExternSymbolMissing:lower_c_extern_symbol() error("C lowering missing validated extern " .. self.extern_id.text, 2) end
function Lower.LowerCExternSymbolMissing:lower_c_extern_sig() error("C lowering missing validated extern " .. self.extern_id.text, 2) end
function Lower.LowerCValueTypeMissing:lower_c_backend_type() error("C lowering missing validated value " .. self.value.text, 2) end

local function value_entry(value, code_ty)
  local cty = code_ty:code_to_c_backend_type()
  local local_value = C.CBackendLocal(value:code_to_c_local_id(), C.CBackendName(value.text), cty)
  return Lower.LowerCValueTypeEntry(value, code_ty, local_value)
end

local function emitted(stmts, helpers, locals, definitions)
  return Lower.LowerCInstEmission(stmts or {}, helpers or {}, locals or {}, definitions or {})
end

local function emitted_value(value, code_ty, stmts, helpers, locals)
  local definition = value_entry(value, code_ty)
  local all_locals = { definition.c_local }
  for i = 1, #(locals or {}) do all_locals[#all_locals + 1] = locals[i] end
  return emitted(stmts, helpers, all_locals, { definition })
end

local function atom(value) return C.CBackendAtomLocal(value:code_to_c_local_id()) end
local function atoms(values)
  local result = {}
  for i = 1, #values do result[i] = atom(values[i]) end
  return result
end

function Code.CodeInst:lower_to_c_backend(input) return self.op:lower_code_inst_to_c(input) end
function Code.CodeInstOp:lower_code_inst_to_c(input) error("missing lower_code_inst_to_c leaf method", 2) end

function Code.CodeInstConst:lower_code_inst_to_c(input)
  local ty = self.const.ty
  local cty = ty:code_to_c_backend_type()
  local literal = self.const:code_to_c_atom(cty)
  return emitted_value(self.dst, ty, { C.CBackendAssign(self.dst:code_to_c_local_id(), C.CBackendRAtom(literal)) })
end
function Code.CodeConst:code_to_c_atom(cty) return C.CBackendAtomNull(cty) end
function Code.CodeConstLiteral:code_to_c_atom(cty) return C.CBackendAtomLiteral(cty, self.literal) end
function Code.CodeConstNull:code_to_c_atom(cty) return C.CBackendAtomNull(cty) end
function Code.CodeConstUndef:code_to_c_atom(cty) return C.CBackendAtomNull(cty) end

function Code.CodeInstAlias:lower_code_inst_to_c(input)
  return emitted_value(self.dst, self.ty, { C.CBackendAssign(self.dst:code_to_c_local_id(), C.CBackendRAtom(atom(self.src))) })
end
function Code.CodeInstUnary:lower_code_inst_to_c(input)
  local cty = self.ty:code_to_c_backend_type()
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperUnary(self.op, cty))
  return emitted_value(self.dst, self.ty, { C.CBackendHelperCall(self.dst:code_to_c_local_id(), helper_id, { atom(self.value) }) }, { helper })
end
function Code.CodeInstBinary:lower_code_inst_to_c(input)
  local cty = self.ty:code_to_c_backend_type()
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperIntBinary(self.op, cty, C.CBackendIntWrap))
  return emitted_value(self.dst, self.ty, { C.CBackendHelperCall(self.dst:code_to_c_local_id(), helper_id, { atom(self.lhs), atom(self.rhs) }) }, { helper })
end
function Code.CodeInstFloatBinary:lower_code_inst_to_c(input)
  local cty = self.ty:code_to_c_backend_type()
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperFloatBinary(self.op, cty))
  return emitted_value(self.dst, self.ty, { C.CBackendHelperCall(self.dst:code_to_c_local_id(), helper_id, { atom(self.lhs), atom(self.rhs) }) }, { helper })
end
function Code.CodeInstCompare:lower_code_inst_to_c(input)
  local rhs = C.CBackendRCompare(self.op, self.operand_ty:code_to_c_backend_type(), atom(self.lhs), atom(self.rhs))
  return emitted_value(self.dst, Code.CodeTyBool8, { C.CBackendAssign(self.dst:code_to_c_local_id(), rhs) })
end
function Code.CodeInstCast:lower_code_inst_to_c(input)
  local rhs = C.CBackendRCast(self.op, self.to:code_to_c_backend_type(), atom(self.value))
  return emitted_value(self.dst, self.to, { C.CBackendAssign(self.dst:code_to_c_local_id(), rhs) })
end
function Code.CodeInstSelect:lower_code_inst_to_c(input)
  local rhs = C.CBackendRSelect(self.ty:code_to_c_backend_type(), atom(self.cond), atom(self.then_value), atom(self.else_value))
  return emitted_value(self.dst, self.ty, { C.CBackendAssign(self.dst:code_to_c_local_id(), rhs) })
end
function Code.CodeInstIntrinsicVoid:lower_code_inst_to_c(input)
  local helper_id = C.CBackendHelperId("helper_intrinsic_" .. self.op:c_helper_suffix())
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperIntrinsic(self.op, self.ty:code_to_c_backend_type()))
  return emitted({ C.CBackendHelperCall(nil, helper_id, atoms(self.args)) }, { helper })
end
function Code.CodeInstIntrinsicValue:lower_code_inst_to_c(input)
  local helper_id = C.CBackendHelperId("helper_" .. self.dst.text)
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperIntrinsic(self.op, self.ty:code_to_c_backend_type()))
  return emitted_value(self.dst, self.ty, { C.CBackendHelperCall(self.dst:code_to_c_local_id(), helper_id, atoms(self.args)) }, { helper })
end
function Code.CodeInstAddrOf:lower_code_inst_to_c(input)
  local rhs = C.CBackendRAddrOfPlace(self.place:lower_code_place_to_c(input))
  return emitted_value(self.dst, self.ptr_ty, { C.CBackendAssign(self.dst:code_to_c_local_id(), rhs) })
end
function Code.CodeInstGlobalRef:lower_code_inst_to_c(input)
  local stmt = self.ref:lower_code_global_ref_to_c_assign(
    input, self.dst:code_to_c_local_id(), self.ptr_ty)
  return emitted_value(self.dst, self.ptr_ty, { stmt })
end
function Code.CodeInstPtrOffset:lower_code_inst_to_c(input)
  local rhs = C.CBackendRPtrOffset(atom(self.base), atom(self.index), self.elem_size, self.const_offset)
  return emitted_value(self.dst, self.ptr_ty, { C.CBackendAssign(self.dst:code_to_c_local_id(), rhs) })
end
function Code.CodeInstLoad:lower_code_inst_to_c(input)
  return emitted_value(self.dst, self.access.ty, { C.CBackendPlaceLoad(self.dst:code_to_c_local_id(), self.place:lower_code_place_to_c(input)) })
end
function Code.CodeInstStore:lower_code_inst_to_c(input)
  return emitted({ C.CBackendPlaceStore(self.place:lower_code_place_to_c(input), atom(self.value)) })
end

function Code.CodeInstAggregate:lower_code_inst_to_c(input)
  local fields = {}
  for i = 1, #self.fields do
    fields[i] = C.CBackendAggregateFieldInit(C.CBackendName(self.fields[i].field:code_to_c_field_name()), atom(self.fields[i].value), nil)
  end
  local cty = self.ty:code_to_c_backend_type()
  return emitted_value(self.dst, self.ty, { C.CBackendAggregateInit(C.CBackendPlaceLocal(self.dst:code_to_c_local_id(), cty), cty, fields) })
end
function Code.CodeInstArray:lower_code_inst_to_c(input)
  local elems = {}
  for i = 1, #self.elems do elems[i] = C.CBackendArrayElemInit(self.elems[i].index, atom(self.elems[i].value)) end
  local cty = self.ty:code_to_c_backend_type()
  return emitted_value(self.dst, self.ty, { C.CBackendArrayInit(C.CBackendPlaceLocal(self.dst:code_to_c_local_id(), cty), cty, elems) })
end

function Code.CodeInstViewMake:lower_code_inst_to_c(input)
  local code_ty, cty = Code.CodeTyView(self.elem_ty), C.CBackendViewDescriptor(self.elem_ty:code_to_c_backend_type())
  local fields = {
    C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(self.data), 0),
    C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(self.len), nil),
    C.CBackendAggregateFieldInit(C.CBackendName("stride"), atom(self.stride), nil),
  }
  return emitted_value(self.dst, code_ty, { C.CBackendAggregateInit(C.CBackendPlaceLocal(self.dst:code_to_c_local_id(), cty), cty, fields) })
end
local function descriptor_field(dst, source, source_cty, name, field_cty, code_ty)
  local place = C.CBackendPlaceField(C.CBackendPlaceLocal(source:code_to_c_local_id(), source_cty), C.CBackendName(name), field_cty, 0, nil, nil)
  return emitted_value(dst, code_ty, { C.CBackendPlaceLoad(dst:code_to_c_local_id(), place) })
end
function Code.CodeInstViewData:lower_code_inst_to_c(input) return descriptor_field(self.dst, self.view, input.values:lower_c_value_lookup(self.view):lower_c_backend_type(), "data", C.CBackendDataPtr(nil), Code.CodeTyDataPtr(nil)) end
function Code.CodeInstViewLen:lower_code_inst_to_c(input) return descriptor_field(self.dst, self.view, input.values:lower_c_value_lookup(self.view):lower_c_backend_type(), "len", C.CBackendIndex, Code.CodeTyIndex) end
function Code.CodeInstViewStride:lower_code_inst_to_c(input) return descriptor_field(self.dst, self.view, input.values:lower_c_value_lookup(self.view):lower_c_backend_type(), "stride", C.CBackendIndex, Code.CodeTyIndex) end
function Code.CodeInstSliceMake:lower_code_inst_to_c(input)
  local code_ty, cty = Code.CodeTySlice(self.elem_ty), C.CBackendSliceDescriptor(self.elem_ty:code_to_c_backend_type())
  local fields = { C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(self.data), 0), C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(self.len), nil) }
  return emitted_value(self.dst, code_ty, { C.CBackendAggregateInit(C.CBackendPlaceLocal(self.dst:code_to_c_local_id(), cty), cty, fields) })
end
function Code.CodeInstSliceData:lower_code_inst_to_c(input) return descriptor_field(self.dst, self.slice, input.values:lower_c_value_lookup(self.slice):lower_c_backend_type(), "data", C.CBackendDataPtr(nil), Code.CodeTyDataPtr(nil)) end
function Code.CodeInstSliceLen:lower_code_inst_to_c(input) return descriptor_field(self.dst, self.slice, input.values:lower_c_value_lookup(self.slice):lower_c_backend_type(), "len", C.CBackendIndex, Code.CodeTyIndex) end
function Code.CodeInstByteSpanMake:lower_code_inst_to_c(input)
  local cty = C.CBackendByteSpanDescriptor
  local fields = { C.CBackendAggregateFieldInit(C.CBackendName("data"), atom(self.data), 0), C.CBackendAggregateFieldInit(C.CBackendName("len"), atom(self.len), nil) }
  return emitted_value(self.dst, Code.CodeTyByteSpan, { C.CBackendAggregateInit(C.CBackendPlaceLocal(self.dst:code_to_c_local_id(), cty), cty, fields) })
end
function Code.CodeInstByteSpanData:lower_code_inst_to_c(input) return descriptor_field(self.dst, self.span, C.CBackendByteSpanDescriptor, "data", C.CBackendDataPtr(nil), Code.CodeTyDataPtr(nil)) end
function Code.CodeInstByteSpanLen:lower_code_inst_to_c(input) return descriptor_field(self.dst, self.span, C.CBackendByteSpanDescriptor, "len", C.CBackendIndex, Code.CodeTyIndex) end

function Code.CodeInstClosure:lower_code_inst_to_c(input)
  local cty = self.ty:code_to_c_backend_type()
  local fields = { C.CBackendAggregateFieldInit(C.CBackendName("fn"), atom(self.fn), 0), C.CBackendAggregateFieldInit(C.CBackendName("ctx"), atom(self.ctx), nil) }
  return emitted_value(self.dst, self.ty, { C.CBackendAggregateInit(C.CBackendPlaceLocal(self.dst:code_to_c_local_id(), cty), cty, fields) })
end
function Code.CodeInstVariantCtor:lower_code_inst_to_c(input)
  local cty, dst = self.ty:code_to_c_backend_type(), self.dst:code_to_c_local_id()
  -- Tagged unions lower to the flat __offset_N struct contract: the tag
  -- field at tag_offset and each payload field addressed inside the byte
  -- range at its own layout offset.
  local tag_offset = self.variant.tag_offset
  local fields = { C.CBackendAggregateFieldInit(C.CBackendName("__offset_" .. tostring(tag_offset)), C.CBackendAtomLiteral(C.CBackendScalar(Core.ScalarU32), Core.LitInt(tostring(self.variant.tag_value))), tag_offset) }
  local stmts = { C.CBackendAggregateInit(C.CBackendPlaceLocal(dst, cty), cty, fields) }
  local vfields = self.variant.fields or {}
  for i = 1, #vfields do
    local arg = self.args[i]
    if arg ~= nil then
      local f = vfields[i]
      local place = C.CBackendPlaceBytes(C.CBackendAtomAddr(C.CBackendPlaceLocal(dst, cty)), f.offset, f.ty:code_to_c_backend_type(), 0, 1)
      stmts[#stmts + 1] = C.CBackendPlaceStore(place, atom(arg))
    end
  end
  return emitted_value(self.dst, self.ty, stmts)
end
function Code.CodeInstVariantTag:lower_code_inst_to_c(input)
  local owner_cty = input.values:lower_c_value_lookup(self.value):lower_c_backend_type()
  local tag_offset = self.tag_offset
  local place = C.CBackendPlaceField(C.CBackendPlaceLocal(self.value:code_to_c_local_id(), owner_cty), C.CBackendName("__offset_" .. tostring(tag_offset)), self.tag_ty:code_to_c_backend_type(), tag_offset, nil, nil)
  return emitted_value(self.dst, self.tag_ty, { C.CBackendPlaceLoad(self.dst:code_to_c_local_id(), place) })
end
function Code.CodeInstVariantPayload:lower_code_inst_to_c(input)
  local owner_cty = self.variant.owner_ty:code_to_c_backend_type()
  local field = self.variant.fields[self.field_index]
  local place = C.CBackendPlaceBytes(C.CBackendAtomAddr(C.CBackendPlaceLocal(self.value:code_to_c_local_id(), owner_cty)), field.offset, field.ty:code_to_c_backend_type(), 0, 1)
  return emitted_value(self.dst, field.ty, { C.CBackendPlaceLoad(self.dst:code_to_c_local_id(), place) })
end

function Code.CodeInstCall:lower_code_inst_to_c(input)
  local stmt = C.CBackendCall(self.dst and self.dst:code_to_c_local_id() or nil, self.target:lower_code_call_target_to_c(input), atoms(self.args))
  if self.dst == nil then return emitted({ stmt }) end
  local code_ty = input.signatures:lower_c_signature_lookup(self.sig):lower_c_call_result_type()
  return emitted_value(self.dst, code_ty, { stmt })
end
function Lower.LowerCSignatureFound:lower_c_call_result_type()
  if #self.entry.code_signature.results ~= 1 then error("C lowering call result requires one result", 2) end
  return self.entry.code_signature.results[1]
end
function Lower.LowerCSignatureMissing:lower_c_call_result_type() error("C lowering missing validated signature " .. self.sig.text, 2) end

function Code.CodeTrapPolicy:lower_c_trap_policy() return C.CBackendMayTrap end
function Code.CodeMayTrap:lower_c_trap_policy() return C.CBackendMayTrap end
function Code.CodeMustNotTrap:lower_c_trap_policy() return C.CBackendMustNotTrap end
function Code.CodeCheckedTrap:lower_c_trap_policy() return C.CBackendCheckedTrap end
local function lower_access(access) return C.CBackendMemoryAccess(access.ty:code_to_c_backend_type(), access.align, access.trap:lower_c_trap_policy(), access.volatile, access.ordering) end
local function atomic_address(place, access, prefix)
  local id = C.CBackendLocalId(prefix)
  local local_value = C.CBackendLocal(id, C.CBackendName(prefix), C.CBackendDataPtr(access.ty))
  local stmt = C.CBackendAssign(id, C.CBackendRAddrOfPlace(place:lower_code_place_to_c(nil)))
  return local_value, stmt, C.CBackendAtomLocal(id)
end
function Code.CodeInstAtomicLoad:lower_code_inst_to_c(input)
  local access = lower_access(self.access)
  local temp, address_stmt, address = atomic_address(self.place, access, "atomic_addr_load_" .. self.dst.text)
  local helper_id = C.CBackendHelperId("helper_atomic_load_" .. self.dst.text)
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperAtomicLoad(access))
  return emitted_value(self.dst, self.access.ty, { address_stmt, C.CBackendHelperCall(self.dst:code_to_c_local_id(), helper_id, { address }) }, { helper }, { temp })
end
function Code.CodeInstAtomicStore:lower_code_inst_to_c(input)
  local access = lower_access(self.access)
  local temp, address_stmt, address = atomic_address(self.place, access, "atomic_addr_store")
  local helper_id = C.CBackendHelperId("helper_atomic_store")
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperAtomicStore(access))
  return emitted({ address_stmt, C.CBackendHelperCall(nil, helper_id, { address, atom(self.value) }) }, { helper }, { temp })
end
function Code.CodeInstAtomicRmw:lower_code_inst_to_c(input)
  local access = lower_access(self.access)
  local temp, address_stmt, address = atomic_address(self.place, access, "atomic_addr_rmw_" .. self.dst.text)
  local helper_id = C.CBackendHelperId("helper_atomic_rmw_" .. self.dst.text)
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperAtomicRmw(self.op, access))
  return emitted_value(self.dst, self.access.ty, { address_stmt, C.CBackendHelperCall(self.dst:code_to_c_local_id(), helper_id, { address, atom(self.value) }) }, { helper }, { temp })
end
function Code.CodeInstAtomicCas:lower_code_inst_to_c(input)
  local access = lower_access(self.access)
  local temp, address_stmt, address = atomic_address(self.place, access, "atomic_addr_cas_" .. self.dst.text)
  local helper_id = C.CBackendHelperId("helper_atomic_cas_" .. self.dst.text)
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperAtomicCas(access, self.ordering, self.ordering))
  return emitted_value(self.dst, self.access.ty, { address_stmt, C.CBackendHelperCall(self.dst:code_to_c_local_id(), helper_id, { address, atom(self.expected), atom(self.replacement) }) }, { helper }, { temp })
end
function Code.CodeInstAtomicFence:lower_code_inst_to_c(input)
  local helper_id = C.CBackendHelperId("helper_atomic_fence")
  local helper = C.CBackendHelperUse(helper_id, C.CBackendHelperAtomicFence(self.ordering))
  return emitted({ C.CBackendHelperCall(nil, helper_id, {}) }, { helper })
end

function Code.CodeTerm:lower_to_c_backend_term(input) return self.op:lower_code_term_to_c(input) end
function Code.CodeTermReturn:lower_code_term_to_c(input)
  if #self.values == 0 then return Lower.LowerCTermEmission(C.CBackendReturnVoid) end
  return Lower.LowerCTermEmission(C.CBackendReturn(atom(self.values[1])))
end
function Code.CodeTermTrap:lower_code_term_to_c(input) return Lower.LowerCTermEmission(C.CBackendTrap) end
function Code.CodeTermUnreachable:lower_code_term_to_c(input) return Lower.LowerCTermEmission(C.CBackendTrap) end
function Code.CodeTermJump:lower_code_term_to_c(input) return Lower.LowerCTermEmission(C.CBackendGoto(C.CBackendLabel(self.dest.text), atoms(self.args))) end
function Code.CodeTermBranch:lower_code_term_to_c(input)
  return Lower.LowerCTermEmission(C.CBackendIfGoto(atom(self.cond), C.CBackendLabel(self.then_dest.text), atoms(self.then_args), C.CBackendLabel(self.else_dest.text), atoms(self.else_args)))
end
function Code.CodeTermSwitch:lower_code_term_to_c(input)
  local cases = {}
  for i = 1, #self.cases do cases[i] = C.CBackendSwitchCase(self.cases[i].literal, C.CBackendLabel(self.cases[i].dest.text), atoms(self.cases[i].args)) end
  return Lower.LowerCTermEmission(C.CBackendSwitchGoto(atom(self.value), cases, C.CBackendLabel(self.default_dest.text), atoms(self.default_args)))
end
function Code.CodeTermVariantSwitch:lower_code_term_to_c(input)
  local cases = {}
  for i = 1, #self.cases do cases[i] = C.CBackendSwitchCase(Core.LitInt(tostring(self.cases[i].variant.tag_value)), C.CBackendLabel(self.cases[i].dest.text), atoms(self.cases[i].args)) end
  return Lower.LowerCTermEmission(C.CBackendSwitchGoto(atom(self.tag), cases, C.CBackendLabel(self.default_dest.text), atoms(self.default_args)))
end
