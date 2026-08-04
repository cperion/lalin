-- impl/tree_check/type.lua
-- Type-check support: scalar facts, type classification, ABI decisions, op classification.
-- Leaf methods on Core.Scalar, Ty.Type, Ty.TypeRef, Ty.TypeShape, Ty.ArrayLen, Core.BinaryOp, Core.UnaryOp, Core.CmpOp, Core.LogicOp, Core.MachineCastOp.

local T        = require("lalin.schema")
local Core     = require("lalin.schema.core")
local Ty       = require("lalin.schema.type")
local Host     = T.LalinHost
local Sem      = require("lalin.schema.sem")
local LCheck   = require("lalin.schema.check")
local asdl     = require("lalin.asdl")

-- Storage projection used by resolved field references. Schema-v2 owns this
-- projection; it must not install the legacy layout_resolve implementation.
function Ty.Type:sem_layout_storage() return Host.HostRepOpaque("sem_layout") end
function Ty.TScalar:sem_layout_storage() return Host.HostRepScalar(self.scalar) end
function Ty.TPtr:sem_layout_storage() return Host.HostRepPtr(self.elem) end
function Ty.TView:sem_layout_storage() return Host.HostRepView(self.elem) end
function Ty.TAccess:sem_layout_storage() return self.base:sem_layout_storage() end
-- Self-initializing utilities
local scalar_api = require("lalin.type_to_backend_scalar")
local layout_api = require("lalin.type_size_align")

local function void_ty() return Ty.TScalar(Core.ScalarVoid) end

----------------------------------------------------------------------
-- Scalar classification (from core_scalar.lua)
----------------------------------------------------------------------

-- signedness
function Core.Scalar:tree_check_is_signed() return false end
function Core.ScalarI8:tree_check_is_signed() return true end
function Core.ScalarI16:tree_check_is_signed() return true end
function Core.ScalarI32:tree_check_is_signed() return true end
function Core.ScalarI64:tree_check_is_signed() return true end

-- is_integer
function Core.Scalar:tree_check_is_integer() return false end
function Core.ScalarU8:tree_check_is_integer() return true end
function Core.ScalarU16:tree_check_is_integer() return true end
function Core.ScalarU32:tree_check_is_integer() return true end
function Core.ScalarU64:tree_check_is_integer() return true end
function Core.ScalarI8:tree_check_is_integer() return true end
function Core.ScalarI16:tree_check_is_integer() return true end
function Core.ScalarI32:tree_check_is_integer() return true end
function Core.ScalarI64:tree_check_is_integer() return true end
function Core.ScalarIndex:tree_check_is_integer() return true end
function Core.Scalar:tree_check_is_index() return false end
function Core.ScalarIndex:tree_check_is_index() return true end

-- is_unsigned
function Core.Scalar:tree_check_is_unsigned() return false end
function Core.ScalarU8:tree_check_is_unsigned() return true end
function Core.ScalarU16:tree_check_is_unsigned() return true end
function Core.ScalarU32:tree_check_is_unsigned() return true end
function Core.ScalarU64:tree_check_is_unsigned() return true end
function Core.ScalarIndex:tree_check_is_unsigned() return true end

-- is_float
function Core.Scalar:tree_check_is_float() return false end
function Core.ScalarF32:tree_check_is_float() return true end
function Core.ScalarF64:tree_check_is_float() return true end

-- is_bool
function Core.Scalar:tree_check_is_bool() return false end
function Core.ScalarBool:tree_check_is_bool() return true end

-- bit_width
function Core.Scalar:tree_check_bit_width() return 0 end
function Core.ScalarU8:tree_check_bit_width() return 8 end
function Core.ScalarU16:tree_check_bit_width() return 16 end
function Core.ScalarU32:tree_check_bit_width() return 32 end
function Core.ScalarU64:tree_check_bit_width() return 64 end
function Core.ScalarI8:tree_check_bit_width() return 8 end
function Core.ScalarI16:tree_check_bit_width() return 16 end
function Core.ScalarI32:tree_check_bit_width() return 32 end
function Core.ScalarI64:tree_check_bit_width() return 64 end
function Core.ScalarF32:tree_check_bit_width() return 32 end
function Core.ScalarF64:tree_check_bit_width() return 64 end
function Core.ScalarBool:tree_check_bit_width() return 8 end
function Core.ScalarVoid:tree_check_bit_width() return 0 end
function Core.ScalarIndex:tree_check_bit_width() return 64 end

-- backend scalar
function Core.Scalar:tree_check_backend_scalar(target, backend) return scalar_api.to_backend_scalar(self, target, backend) end


function Ty.Type:tree_check_is_index_type() return false end
function Ty.TScalar:tree_check_is_index_type() return self.scalar:tree_check_is_index() end

-- Type classification (from type_classify.lua)
----------------------------------------------------------------------

function Ty.Type:tree_check_is_numeric() return false end
function Ty.TScalar:tree_check_is_numeric()
  return self.scalar:tree_check_is_integer() or self.scalar:tree_check_is_float()
end

function Ty.Type:tree_check_is_integer_type() return false end
function Ty.TScalar:tree_check_is_integer_type() return self.scalar:tree_check_is_integer() end

function Ty.Type:tree_check_is_float_type() return false end
function Ty.TScalar:tree_check_is_float_type() return self.scalar:tree_check_is_float() end

function Ty.Type:tree_check_is_signed_type() return false end
function Ty.TScalar:tree_check_is_signed_type() return self.scalar:tree_check_is_signed() end

function Ty.Type:tree_check_is_unsigned_type() return false end
function Ty.TScalar:tree_check_is_unsigned_type() return self.scalar:tree_check_is_unsigned() end

function Ty.Type:tree_check_is_bool_type() return false end
function Ty.TScalar:tree_check_is_bool_type() return self.scalar:tree_check_is_bool() end

function Ty.Type:tree_check_is_ptr_type() return false end
function Ty.TPtr:tree_check_is_ptr_type() return true end

function Ty.Type:tree_check_is_void_type() return false end
function Ty.TScalar:tree_check_is_void_type() return self.scalar == Core.ScalarVoid end

function Ty.Type:tree_check_is_aggregate_type() return false end
function Ty.TNamed:tree_check_is_aggregate_type() return true end
function Ty.TArray:tree_check_is_aggregate_type() return true end
function Ty.TSlice:tree_check_is_aggregate_type() return true end
function Ty.TView:tree_check_is_aggregate_type() return true end
function Ty.TClosure:tree_check_is_aggregate_type() return true end
-- Field access: struct layouts own field resolution during typecheck.
function Ty.Type:tree_check_field_lookup_base() return self end
function Ty.TPtr:tree_check_field_lookup_base() return self.elem end
function Ty.TAccess:tree_check_field_lookup_base() return self.base:tree_check_field_lookup_base() end
function Ty.TLease:tree_check_field_lookup_base() return self.base:tree_check_field_lookup_base() end
function Ty.Type:tree_check_named_ref_lookup() return LCheck.TypeNamedRefMissing(self) end
function Ty.TNamed:tree_check_named_ref_lookup() return LCheck.TypeNamedRefFound(self.ref) end

-- The named-ref leaves own the layout search; the layout lookup leaves own
-- the field decision (no nil protocol).
function LCheck.TypeNamedRefFound:tree_check_layout_lookup(scope)
  for i = 1, #(scope.layouts or {}) do
    local layout = scope.layouts[i]
    if layout:tree_check_matches_ref(self.ref) then return Sem.TypeLayoutFound(layout) end
  end
  return Sem.TypeLayoutMissing
end
function LCheck.TypeNamedRefMissing:tree_check_layout_lookup(scope)
  return Sem.TypeLayoutMissing
end
function Sem.TypeLayoutFound:tree_check_field_layout(field_name)
  return self.layout:tree_check_field_layout_lookup(field_name)
end
function Sem.TypeLayoutMissing:tree_check_field_layout(field_name)
  return Sem.FieldLayoutMissing
end
function Sem.TypeLayout:tree_check_field_layout_lookup(field_name)
  for i = 1, #(self.fields or {}) do
    if self.fields[i].field_name == field_name then return Sem.FieldLayoutFound(self.fields[i]) end
  end
  return Sem.FieldLayoutMissing
end

function Sem.TypeLayout:tree_check_matches_ref(ref) return false end
function Sem.LayoutNamed:tree_check_matches_ref(ref) return ref:tree_check_matches_named_layout(self) end
function Sem.LayoutLocal:tree_check_matches_ref(ref) return ref:tree_check_matches_local_layout(self) end
function Ty.TypeRef:tree_check_matches_named_layout(layout) return false end
function Ty.TypeRefGlobal:tree_check_matches_named_layout(layout)
  return layout.module_name == self.module_name and layout.type_name == self.type_name
end
function Ty.TypeRefPath:tree_check_matches_named_layout(layout)
  local parts = self.path.parts or {}
  return #parts > 0 and layout.type_name == parts[#parts].text
end
function Ty.TypeRef:tree_check_matches_local_layout(layout) return false end
function Ty.TypeRefLocal:tree_check_matches_local_layout(layout) return layout.sym == self.sym end
-- field lookup: replaced by Sem.TypeLayout:tree_check_field_layout_lookup
-- with FieldLayoutLookup leaves (see above).

function Ty.Type:tree_check_is_array_type() return false end
function Ty.TArray:tree_check_is_array_type() return true end
----------------------------------------------------------------------
-- Type size / align via layout_api
----------------------------------------------------------------------

function Ty.Type:tree_check_size_of(env, target) return layout_api.size_of(self, env, target) end
function Ty.Type:tree_check_align_of(env, target) return layout_api.align_of(self, env, target) end
function Ty.Type:tree_check_layout(env, target) return layout_api.result(self, env, target) end

----------------------------------------------------------------------
-- ABI classification (from type_abi_classify.lua)
----------------------------------------------------------------------

function Ty.Type:tree_check_abi_class(target) return scalar_api.abi_classify(self, target) end

----------------------------------------------------------------------
-- Op classification (from tree_typecheck_type.lua)
----------------------------------------------------------------------

-- Binary ops
function Core.BinaryOp:tree_check_result_type(lt, rt) return void_ty() end
function Core.BinAdd:tree_check_result_type(lt, rt)
  if lt:tree_check_is_numeric() and rt:tree_check_is_numeric() then
    if lt == rt then return lt end
    if lt:tree_check_is_index_type() or rt:tree_check_is_index_type() then
      return Ty.TScalar(Core.ScalarIndex)
    end
    if lt:tree_check_is_float_type() or rt:tree_check_is_float_type() then
      return lt:tree_check_is_float_type() and lt or rt
    end
    if lt:tree_check_is_signed_type() and rt:tree_check_is_signed_type() then return lt end
    return Ty.TScalar(Core.ScalarI32)
  end
  return void_ty()
end

function Core.BinSub:tree_check_result_type(lt, rt) return Core.BinAdd:tree_check_result_type(lt, rt) end
function Core.BinMul:tree_check_result_type(lt, rt) return Core.BinAdd:tree_check_result_type(lt, rt) end
function Core.BinDiv:tree_check_result_type(lt, rt) return Core.BinAdd:tree_check_result_type(lt, rt) end
function Core.BinRem:tree_check_result_type(lt, rt)
  if lt:tree_check_is_integer_type() and rt:tree_check_is_integer_type() then return lt end
  return void_ty()
end

function Core.BinBitAnd:tree_check_result_type(lt, rt)
  if lt:tree_check_is_integer_type() and rt:tree_check_is_integer_type() then return lt end
  return void_ty()
end
function Core.BinBitOr:tree_check_result_type(lt, rt) return Core.BinBitAnd:tree_check_result_type(lt, rt) end
function Core.BinBitXor:tree_check_result_type(lt, rt) return Core.BinBitAnd:tree_check_result_type(lt, rt) end
function Core.BinShl:tree_check_result_type(lt, rt)
  if lt:tree_check_is_integer_type() and rt:tree_check_is_integer_type() then return lt end
  return void_ty()
end
function Core.BinLShr:tree_check_result_type(lt, rt) return Core.BinShl:tree_check_result_type(lt, rt) end
function Core.BinAShr:tree_check_result_type(lt, rt) return Core.BinShl:tree_check_result_type(lt, rt) end

-- Cmp ops
function Core.CmpOp:tree_check_cmp_result(lt, rt) return void_ty() end
function Core.CmpEq:tree_check_cmp_result(lt, rt)
  if lt:tree_check_is_numeric() and rt:tree_check_is_numeric() then return Ty.TScalar(Core.ScalarBool) end
  if lt:tree_check_is_bool_type() and rt:tree_check_is_bool_type() then return Ty.TScalar(Core.ScalarBool) end
  if lt:tree_check_is_ptr_type() and rt:tree_check_is_ptr_type() then return Ty.TScalar(Core.ScalarBool) end
  return void_ty()
end
function Core.CmpNe:tree_check_cmp_result(lt, rt) return Core.CmpEq:tree_check_cmp_result(lt, rt) end
function Core.CmpLt:tree_check_cmp_result(lt, rt)
  if lt:tree_check_is_numeric() and rt:tree_check_is_numeric() then return Ty.TScalar(Core.ScalarBool) end
  if lt:tree_check_is_ptr_type() and rt:tree_check_is_ptr_type() then return Ty.TScalar(Core.ScalarBool) end
  return void_ty()
end
function Core.CmpLe:tree_check_cmp_result(lt, rt) return Core.CmpLt:tree_check_cmp_result(lt, rt) end
function Core.CmpGt:tree_check_cmp_result(lt, rt) return Core.CmpLt:tree_check_cmp_result(lt, rt) end
function Core.CmpGe:tree_check_cmp_result(lt, rt) return Core.CmpLt:tree_check_cmp_result(lt, rt) end

-- Logic ops
function Core.LogicOp:tree_check_logic_result(lt, rt)
  if lt:tree_check_is_bool_type() and rt:tree_check_is_bool_type() then return Ty.TScalar(Core.ScalarBool) end
  return void_ty()
end

-- Unary ops
function Core.UnaryOp:tree_check_unary_result(ty) return void_ty() end
function Core.UnaryNeg:tree_check_unary_result(ty)
  if ty:tree_check_is_numeric() then return ty end
  return void_ty()
end
function Core.UnaryNot:tree_check_unary_result(ty)
  if ty:tree_check_is_bool_type() then return ty end
  return void_ty()
end
function Core.UnaryBitNot:tree_check_unary_result(ty)
  if ty:tree_check_is_integer_type() then return ty end
  return void_ty()
end

-- MachineCast ops
function Core.MachineCastOp:tree_check_machine_cast_result(from_ty, to_ty) return to_ty end
function Core.MachineCastSextend:tree_check_machine_cast_result(from_ty, to_ty)
  if from_ty:tree_check_is_integer_type() and to_ty:tree_check_is_integer_type() then return to_ty end
  return void_ty()
end
function Core.MachineCastUextend:tree_check_machine_cast_result(from_ty, to_ty)
  return Core.MachineCastSextend:tree_check_machine_cast_result(from_ty, to_ty)
end
function Core.MachineCastBitcast:tree_check_machine_cast_result(from_ty, to_ty)
  return Core.MachineCastSextend:tree_check_machine_cast_result(from_ty, to_ty)
end
function Core.MachineCastBitcast:tree_check_machine_cast_result(from_ty, to_ty) return to_ty end
function Core.MachineCastFToS:tree_check_machine_cast_result(from_ty, to_ty)
  if from_ty:tree_check_is_float_type() and to_ty:tree_check_is_integer_type() then return to_ty end
  return void_ty()
end
function Core.MachineCastSToF:tree_check_machine_cast_result(from_ty, to_ty)
  if from_ty:tree_check_is_integer_type() and to_ty:tree_check_is_float_type() then return to_ty end
  return void_ty()
end
function Core.MachineCastFpromote:tree_check_machine_cast_result(from_ty, to_ty)
  if from_ty:tree_check_is_float_type() and to_ty:tree_check_is_float_type() then return to_ty end
  return void_ty()
end
function Core.MachineCastFdemote:tree_check_machine_cast_result(from_ty, to_ty)
  return Core.MachineCastFpromote:tree_check_machine_cast_result(from_ty, to_ty)
end

----------------------------------------------------------------------
-- TypeRef resolution
----------------------------------------------------------------------

function Ty.TypeRef:tree_check_resolve_type(env) return nil end
function Ty.TypeRefGlobal:tree_check_resolve_type(env)
  for _, e in ipairs(env.types or {}) do
    if e.name == self.type_name then return e.ty end
  end
  return nil
end
function Ty.TypeRefLocal:tree_check_resolve_type(env)
  for _, e in ipairs(env.types or {}) do
    if e.name == self.sym.name then return e.ty end
  end
  return nil
end
function Ty.TypeRefPath:tree_check_resolve_type(env)
  for _, e in ipairs(env.types or {}) do
    if e.name == self.path.parts[#self.path.parts].text then return e.ty end
  end
  return nil
end

----------------------------------------------------------------------
-- ArrayLen classification
----------------------------------------------------------------------

function Ty.ArrayLen:tree_check_is_const() return false end
function Ty.ArrayLenConst:tree_check_is_const() return true end
function Ty.ArrayLen:tree_check_const_value() return nil end
function Ty.ArrayLenConst:tree_check_const_value() return self.count end

----------------------------------------------------------------------
-- Cast-surface validation helpers (for tree_surface.lua)
----------------------------------------------------------------------

function Ty.Type:tree_check_surface_cast_reject_reason(op, target) return nil end
function Ty.TScalar:tree_check_surface_cast_reject_reason(op, target)
  if target:tree_check_is_numeric() and self.scalar:tree_check_is_numeric() then return nil end
  if target:tree_check_is_bool_type() and self.scalar:tree_check_is_bool_type() then return nil end
  return "cannot cast " .. tostring(self.scalar) .. " to target type"
end
function Ty.TPtr:tree_check_surface_cast_reject_reason(op, target)
  if target:tree_check_is_ptr_type() then return nil end
  if target:tree_check_is_integer_type() then return nil end
  return "cannot cast pointer to non-pointer/integer type"
end

----------------------------------------------------------------------
-- Callable result extraction (for ExprCall)
----------------------------------------------------------------------

function Ty.Type:tree_check_callable_result() return nil, nil end
function Ty.TFunc:tree_check_callable_result() return self.result, self.params end
function Ty.TClosure:tree_check_callable_result() return self.result, self.params end
