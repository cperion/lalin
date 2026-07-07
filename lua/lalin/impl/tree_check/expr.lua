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
  local ref_name = self.ref:typecheck_tree_ref_name()
  if not ref_name then
    return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarVoid), {LCheck.TypeIssueUnresolvedValue("?")})
  end
  local entry = input.scope and input.scope:typecheck_tree_lookup_value(ref_name)
  if entry and entry.binding then
    return LCheck.TypeExprResult(Tr.ExprRef(Tr.ExprTyped(entry.binding.ty), B.ValueRefBinding(entry.binding)), entry.binding.ty, {})
  end
  return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarVoid), {LCheck.TypeIssueUnresolvedValue(ref_name)})
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
  local result_ty, param_tys = cr.ty:tree_check_callable_result()
  local issues = {}
  if result_ty == nil then
    issues[#issues + 1] = LCheck.TypeIssueNotCallable(cr.ty)
    result_ty = Ty.TScalar(C.ScalarVoid)
    param_tys = {}
  end
  if #(self.args or {}) ~= #(param_tys or {}) then
    issues[#issues + 1] = LCheck.TypeIssueArgCount("call", #(param_tys or {}), #(self.args or {}))
  end
  local args = {}
  for i = 1, #(self.args or {}) do
    local expected = param_tys and param_tys[i] or nil
    local ar
    if expected ~= nil then
      ar = self.args[i]:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, expected))
    else
      ar = self.args[i]:typecheck_tree_expr(input)
    end
    if ar.ty == nil then return ar end
    if expected ~= nil and not (expected:tree_check_is_void_type() or ar.ty:tree_check_is_void_type()) then
      -- compare types (structural equality via tostring for now)
      if tostring(expected) ~= tostring(ar.ty) then
        issues[#issues + 1] = LCheck.TypeIssueExpected("call arg", expected, ar.ty)
      end
    end
    args[#args + 1] = ar.expr
  end
  return LCheck.TypeExprResult(Tr.ExprCall(Tr.ExprTyped(result_ty), cr.expr, args), result_ty, issues)
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
  local ref_name = self.ref:typecheck_tree_ref_name()
  if not ref_name then
    return LCheck.TypePlaceResult(self, nil, {LCheck.TypeIssueUnresolvedValue("?")})
  end
  local entry = input.scope and input.scope:typecheck_tree_lookup_value(ref_name)
  if entry and entry.binding then
    local place = Tr.PlaceRef(Tr.PlaceTyped(entry.binding.ty), B.ValueRefBinding(entry.binding))
    return LCheck.TypePlaceResult(place, entry.binding.ty, {})
  end
  return LCheck.TypePlaceResult(self, nil, {LCheck.TypeIssueUnresolvedValue(ref_name)})
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
function Tr.ExprCtor:typecheck_tree_expr(input)
  local issues = {}
  -- Look up variant in scope facts
  local variant_def, variant_case = nil, nil
  if input.scope and input.scope.facts then
    local facts = input.scope.facts
    for i = 1, #(facts.variants or {}) do
      if facts.variants[i].type_name == self.type_name then
        variant_def = facts.variants[i]
        for j = 1, #(variant_def.variants or {}) do
          if variant_def.variants[j].name == self.variant_name then
            variant_case = variant_def.variants[j]
            break
          end
        end
        break
      end
    end
  end
  local result_ty = variant_def and variant_def.ty or Ty.TScalar(C.ScalarVoid)
  if variant_def == nil or variant_case == nil then
    issues[#issues + 1] = LCheck.TypeIssueUnknownVariant(self.type_name, self.variant_name)
  end
  -- Determine expected argument count from payload type
  local payload_ty = nil
  if variant_case then
    if #(variant_case.fields or {}) == 1 then
      payload_ty = variant_case.fields[1].ty
    elseif #(variant_case.fields or {}) > 1 then
      payload_ty = nil  -- multiple fields, no single payload
    elseif variant_case.payload and not variant_case.payload:tree_check_is_void_type() then
      payload_ty = variant_case.payload
    end
  end
  local expected_args = payload_ty and 1 or 0
  local args = {}
  if #(self.args or {}) ~= expected_args then
    issues[#issues + 1] = LCheck.TypeIssueArgCount("variant constructor", expected_args, #(self.args or {}))
  end
  if payload_ty and #(self.args or {}) >= 1 then
    local ar = self.args[1]:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, payload_ty))
    if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues + 1] = iss end end
    if ar.ty and not ar.ty:tree_check_is_void_type() and
       not payload_ty:tree_check_is_void_type() and
       tostring(payload_ty) ~= tostring(ar.ty) then
      issues[#issues + 1] = LCheck.TypeIssueExpected("variant payload", payload_ty, ar.ty)
    end
    args[1] = ar.expr
  end
  return LCheck.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(result_ty), self.type_name, self.variant_name, args), result_ty, issues)
end
function Tr.ExprLoad:typecheck_tree_expr(input) return LCheck.TypeExprResult(self, self.ty, {}) end
-- typecheck_tree_expr_expected: default fallback to typecheck_tree_expr
function Tr.Expr:typecheck_tree_expr_expected(input)
  return self:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
end

function Tr.ExprBlock:typecheck_tree_expr(input)
  local stmt_input = LCheck.TypeStmtInput(input.scope, Ty.TScalar(C.ScalarVoid), LCheck.TypeYieldNone)
  local body = stmt_input:typecheck_tree_stmt_body(self.stmts or {})
  local result = self.result and self.result:typecheck_tree_expr(input)
  if result == nil or result.ty == nil then
    return LCheck.TypeExprResult(nil, nil, body.issues or {})
  end
  local result_ty = result.ty
  return LCheck.TypeExprResult(Tr.ExprBlock(Tr.ExprTyped(result_ty), body.stmts, result.expr), result_ty, result.issues)
end

function Tr.ExprIf:typecheck_tree_expr(input)
  local cr = self.cond:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, Ty.TScalar(C.ScalarBool)))
  if cr.ty == nil or cr.expr == nil then return cr end
  local tr = self.then_expr:typecheck_tree_expr(input)
  if tr.ty == nil or tr.expr == nil then return tr end
  local er = self.else_expr:typecheck_tree_expr(input)
  if er.ty == nil or er.expr == nil then return er end
  local issues = {}
  if cr.issues then for _, iss in ipairs(cr.issues) do issues[#issues + 1] = iss end end
  if tr.issues then for _, iss in ipairs(tr.issues) do issues[#issues + 1] = iss end end
  if er.issues then for _, iss in ipairs(er.issues) do issues[#issues + 1] = iss end end
  -- Branch type unification: if types differ, use void
  local result_ty = tr.ty
  if tr.ty and er.ty then
    if tostring(tr.ty) ~= tostring(er.ty) then
      issues[#issues + 1] = LCheck.TypeIssueExpected("if-else branches", tr.ty, er.ty)
      result_ty = tr.ty
    end
  end
  return LCheck.TypeExprResult(Tr.ExprIf(Tr.ExprTyped(result_ty), cr.expr, tr.expr, er.expr), result_ty, issues)
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
