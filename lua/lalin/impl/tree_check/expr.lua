-- impl/tree_check/expr.lua
-- Expression typechecking leaf methods.

require("lalin.schema_v2")
local C      = require("lalin.schema_v2.core")
local Ty     = require("lalin.schema_v2.type")
local Tr     = require("lalin.schema_v2.tree")
local B      = require("lalin.schema_v2.bind")
local LCheck = require("lalin.schema_v2.check")
local asdl   = require("lalin.asdl")

function Tr.Expr:typecheck_tree_expr(input) end  -- parent default

function Tr.ExprLit:typecheck_tree_expr(input)
  local lit_ty = self.value:typecheck_tree_literal_ty()
  return LCheck.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(lit_ty), self.value), lit_ty, {})
end

function C.Literal:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarVoid) end
function C.LitInt:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarI32) end
function C.LitFloat:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarF64) end
function C.LitBool:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarBool) end
function C.LitString:typecheck_tree_literal_ty() return Ty.TSlice(Ty.TScalar(C.ScalarU8)) end

function Tr.ExprRef:typecheck_tree_expr(input)
  local entry = input.scope and input.scope:typecheck_tree_lookup_value(self.ref:typecheck_tree_ref_name())
  if entry then
    return LCheck.TypeExprResult(Tr.ExprRef(Tr.ExprTyped(entry.ty), self.ref), entry.ty, {})
  end
  return LCheck.TypeExprResult(nil, nil, {LCheck.TypeIssueUnresolvedValue(self.ref:typecheck_tree_ref_name() or "?")})
end

function B.ValueRef:typecheck_tree_ref_name() return nil end
function B.ValueRefName:typecheck_tree_ref_name() return self.name end
function B.ValueRefBinding:typecheck_tree_ref_name() return self.binding.name end

function Tr.ExprUnary:typecheck_tree_expr(input)
  local vr = self.value:typecheck_tree_expr(input); if vr.ty == nil then return vr end
  local result_ty = self.op:tree_check_unary_result(vr.ty)
  if result_ty and not result_ty:tree_check_is_void_type() then
    return LCheck.TypeExprResult(Tr.ExprUnary(Tr.ExprTyped(result_ty), self.op, vr.expr), result_ty, {})
  end
  return LCheck.TypeExprResult(nil, nil, {})
end

function Tr.ExprBinary:typecheck_tree_expr(input)
  local lr = self.lhs:typecheck_tree_expr(input); if lr.ty == nil then return lr end
  local rr = self.rhs:typecheck_tree_expr(input); if rr.ty == nil then return rr end
  local result_ty = self.op:tree_check_result_type(lr.ty, rr.ty)
  if not result_ty:tree_check_is_void_type() then
    return LCheck.TypeExprResult(Tr.ExprBinary(Tr.ExprTyped(result_ty), self.op, lr.expr, rr.expr), result_ty, {})
  end
  return LCheck.TypeExprResult(nil, nil, {})
end

function Tr.ExprCompare:typecheck_tree_expr(input)
  local lr = self.lhs:typecheck_tree_expr(input); if lr.ty == nil then return lr end
  local rr = self.rhs:typecheck_tree_expr(input); if rr.ty == nil then return rr end
  local result_ty = self.op:tree_check_cmp_result(lr.ty, rr.ty)
  if not result_ty:tree_check_is_void_type() then
    return LCheck.TypeExprResult(Tr.ExprCompare(Tr.ExprTyped(result_ty), self.op, lr.expr, rr.expr), result_ty, {})
  end
  return LCheck.TypeExprResult(nil, nil, {})
end

function Tr.ExprLogic:typecheck_tree_expr(input)
  local lr = self.lhs:typecheck_tree_expr(input); if lr.ty == nil then return lr end
  local rr = self.rhs:typecheck_tree_expr(input); if rr.ty == nil then return rr end
  local result_ty = self.op:tree_check_logic_result(lr.ty, rr.ty)
  if not result_ty:tree_check_is_void_type() then
    return LCheck.TypeExprResult(Tr.ExprLogic(Tr.ExprTyped(result_ty), self.op, lr.expr, rr.expr), result_ty, {})
  end
  return LCheck.TypeExprResult(nil, nil, {})
end

function Tr.ExprCast:typecheck_tree_expr(input)
  local vr = self.value:typecheck_tree_expr(input); if vr.ty == nil then return vr end
  return LCheck.TypeExprResult(Tr.ExprCast(Tr.ExprTyped(self.ty), self.op, self.ty, vr.expr), self.ty, {})
end

function Tr.ExprMachineCast:typecheck_tree_expr(input)
  local vr = self.value:typecheck_tree_expr(input); if vr.ty == nil then return vr end
  local result_ty = self.op:tree_check_machine_cast_result(vr.ty, self.ty)
  if not result_ty:tree_check_is_void_type() then
    return LCheck.TypeExprResult(Tr.ExprMachineCast(Tr.ExprTyped(result_ty), self.op, self.ty, vr.expr), result_ty, {})
  end
  return LCheck.TypeExprResult(nil, nil, {})
end

function Tr.ExprAddrOf:typecheck_tree_expr(input)
  local pr = self.place:typecheck_tree_place(input); if pr.ty == nil then return LCheck.TypeExprResult(nil, nil, {}) end
  local ptr_ty = Ty.TPtr(pr.ty)
  return LCheck.TypeExprResult(Tr.ExprAddrOf(Tr.ExprTyped(ptr_ty), pr.place), ptr_ty, {})
end

function Tr.ExprDeref:typecheck_tree_expr(input)
  local vr = self.value:typecheck_tree_expr(input); if vr.ty == nil then return vr end
  if vr.ty:tree_check_is_ptr_type() then
    return LCheck.TypeExprResult(Tr.ExprDeref(Tr.ExprTyped(vr.ty.elem), vr.expr), vr.ty.elem, {})
  end
  return LCheck.TypeExprResult(nil, nil, {})
end

function Tr.ExprCall:typecheck_tree_expr(input)
  local cr = self.callee:typecheck_tree_expr(input); if cr.ty == nil then return cr end
  local result_ty = cr.ty  -- simplified
  local args = {}
  for i = 1, #(self.args or {}) do
    local ar = self.args[i]:typecheck_tree_expr(input)
    if ar.ty == nil then return ar end; args[i] = ar.expr
  end
  return LCheck.TypeExprResult(Tr.ExprCall(Tr.ExprTyped(result_ty), cr.expr, args), result_ty, {})
end

function Tr.ExprField:typecheck_tree_expr(input)
  local br = self.base:typecheck_tree_expr(input); if br.ty == nil then return br end
  return LCheck.TypeExprResult(Tr.ExprField(Tr.ExprTyped(self.field.ty), br.expr, self.field), self.field.ty, {})
end

function Tr.ExprIndex:typecheck_tree_expr(input)
  local base_ty = self.base:typecheck_tree_index_base_ty(input)
  if base_ty == nil then return LCheck.TypeExprResult(nil, nil, {}) end
  local ir = self.index:typecheck_tree_expr(input); if ir.ty == nil then return ir end
  local elem_ty = base_ty:tree_code_index_elem_type()
  return LCheck.TypeExprResult(Tr.ExprIndex(Tr.ExprTyped(elem_ty), self.base, ir.expr), elem_ty, {})
end

function Tr.IndexBase:typecheck_tree_index_base_ty(input) return nil end
function Tr.IndexBaseExpr:typecheck_tree_index_base_ty(input)
  return self.base:typecheck_tree_expr(input).ty
end

function Tr.ExprIntrinsic:typecheck_tree_expr(input)
  local arg_tys, args = {}, {}
  for i = 1, #(self.args or {}) do
    local ar = self.args[i]:typecheck_tree_expr(input)
    if ar.ty == nil then return ar end; arg_tys[i] = ar.ty; args[i] = ar.expr
  end
  local result_ty = Ty.TScalar(C.ScalarVoid)  -- intrinsic-specific
  return LCheck.TypeExprResult(Tr.ExprIntrinsic(Tr.ExprTyped(result_ty), self.op, args), result_ty, {})
end

-- Place typechecking
function Tr.Place:typecheck_tree_place(input)
  local ty = self.h and self.h:tree_code_place_type()
  return LCheck.TypePlaceResult(self, ty, {})
end

function Tr.PlaceRef:typecheck_tree_place(input)
  local entry = input.scope and input.scope:typecheck_tree_lookup_value(self.ref:typecheck_tree_ref_name())
  if entry then return LCheck.TypePlaceResult(self, entry.ty, {}) end
  return LCheck.TypePlaceResult(self, nil, {})
end

function Tr.PlaceDeref:typecheck_tree_place(input)
  local er = self.base:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if er.ty and er.ty:tree_check_is_ptr_type() then
    return LCheck.TypePlaceResult(self, er.ty.elem, {})
  end
  return LCheck.TypePlaceResult(self, nil, er.issues or {})
end

-- Remaining expr leaves (simplified — full impl in old files)
function Tr.ExprAgg:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.ty, {}) end
function Tr.ExprArray:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TArray(Ty.ArrayLenConst(#self.elems or 0), self.elem_ty), {}) end
function Tr.ExprNull:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.elem, {}) end
function Tr.ExprSizeOf:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarIndex), {}) end
function Tr.ExprAlignOf:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarIndex), {}) end
function Tr.ExprIsNull:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarBool), {}) end
function Tr.ExprCtor:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarU32), {}) end
function Tr.ExprLoad:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.ty, {}) end
function Tr.ExprBlock:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.result and self.result.h and self.result.h:tree_code_expr_type() or Ty.TScalar(C.ScalarVoid), {}) end
function Tr.ExprIf:typecheck_tree_expr(input)
  local tr = self.then_expr:typecheck_tree_expr(input)
  return LCheck.TypeExprResult(self, tr.ty, {})
end
function Tr.ExprSelect:typecheck_tree_expr(input)
  local tr = self.then_expr:typecheck_tree_expr(input)
  return LCheck.TypeExprResult(self, tr.ty, {})
end
function Tr.ExprSwitch:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarVoid), {}) end
function Tr.ExprControl:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.region.result_ty or Ty.TScalar(C.ScalarVoid), {}) end
function Tr.ExprView:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TView(self.view.elem), {}) end
function Tr.ExprLen:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarIndex), {}) end
function Tr.ExprAtomicLoad:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.ty, {}) end
function Tr.ExprAtomicRmw:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.ty, {}) end
function Tr.ExprAtomicCas:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.ty, {}) end
function Tr.ExprClosure:typecheck_tree_expr(input)
  return LCheck.TypeExprResult(self, Ty.TClosure(self.params, self.result), {})
end
