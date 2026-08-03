-- impl/tree_check/expr.lua
-- Expression typechecking leaf methods.

require("lalin.schema_v2")
local C      = require("lalin.schema_v2.core")
local Ty     = require("lalin.schema_v2.type")
local Tr     = require("lalin.schema_v2.tree")
local B      = require("lalin.schema_v2.bind")
local LCheck = require("lalin.schema_v2.check")
local Sem    = require("lalin.schema_v2.sem")
local asdl   = require("lalin.asdl")

function Tr.Expr:typecheck_tree_expr(input) end  -- parent default

function Tr.ExprLit:typecheck_tree_expr(input)
  local lit_ty = self.value:typecheck_tree_literal_ty()
  return LCheck.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(lit_ty), self.value), lit_ty, {})
end

function Tr.ExprLit:typecheck_tree_expr_expected(input)
  local lit_ty = self.value:typecheck_tree_literal_expected(input.expected)
  return LCheck.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(lit_ty), self.value), lit_ty, {})
end

function C.Literal:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarVoid) end
function C.LitInt:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarI32) end
function C.LitFloat:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarF64) end
function C.LitBool:typecheck_tree_literal_ty() return Ty.TScalar(C.ScalarBool) end
function C.LitString:typecheck_tree_literal_ty() return Ty.TSlice(Ty.TScalar(C.ScalarU8)) end

function C.Literal:typecheck_tree_literal_expected(_expected) return self:typecheck_tree_literal_ty() end
function C.LitInt:typecheck_tree_literal_expected(expected)
  if expected ~= nil and expected:tree_check_is_integer_type() then return expected end
  return self:typecheck_tree_literal_ty()
end

function LCheck.TypeValueLookupFound:typecheck_tree_expr_ref(ref)
  local binding_ref = B.ValueRefBinding(self.binding)
  return LCheck.TypeExprResult(Tr.ExprRef(Tr.ExprTyped(self.binding.ty), binding_ref), self.binding.ty, {})
end

function LCheck.TypeValueLookupMissing:typecheck_tree_expr_ref(ref)
  return LCheck.TypeExprResult(ref, Ty.TScalar(C.ScalarVoid), {LCheck.TypeIssueUnresolvedValue(self.name)})
end

function Tr.ExprRef:typecheck_tree_expr(input)
  local ref_name = self.ref:typecheck_tree_ref_name()
  if not ref_name then
    return LCheck.TypeExprResult(self, Ty.TScalar(C.ScalarVoid), {LCheck.TypeIssueUnresolvedValue("?")})
  end
  return input.scope:typecheck_tree_lookup_value(ref_name):typecheck_tree_expr_ref(self)
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
    local lhs, rhs = lr.expr, rr.expr
    if lr.ty ~= result_ty then
      lhs = Tr.ExprCast(Tr.ExprTyped(result_ty), C.SurfaceCast, result_ty, lhs)
    end
    if rr.ty ~= result_ty then
      rhs = Tr.ExprCast(Tr.ExprTyped(result_ty), C.SurfaceCast, result_ty, rhs)
    end
    return LCheck.TypeExprResult(
      Tr.ExprBinary(Tr.ExprTyped(result_ty), self.op, lhs, rhs), result_ty, {})
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

-- Field access: the named-ref leaves own the layout search, the layout
-- lookup leaves own the field decision, and the field lookup leaves own
-- the lowered ExprField result (no nil protocol).
local function tree_check_field_layout_for(scope, ty, field_name)
  local base = ty:tree_check_field_lookup_base()
  return base:tree_check_named_ref_lookup():tree_check_layout_lookup(scope):tree_check_field_layout(field_name)
end

function Tr.ExprDot:typecheck_tree_expr(input)
  local base = self.base:typecheck_tree_expr(input); if base.ty == nil then return base end
  local field_lookup = tree_check_field_layout_for(input.scope, base.ty, self.name)
  return field_lookup:tree_check_dot_field_expr(input, base, self)
end
function Sem.FieldLayoutFound:tree_check_dot_field_expr(input, base, dot)
  local field = self.layout
  -- Lower to a resolved field ref (offset + storage) so the code phase
  -- can emit field access directly; FieldByName would require a
  -- separate sem_layout_resolve pass the v2 pipeline does not run.
  local ref = Sem.FieldByOffset(field.field_name, field.offset, field.ty, field.ty:sem_layout_storage())
  return LCheck.TypeExprResult(Tr.ExprField(Tr.ExprTyped(field.ty), base.expr, ref), field.ty, base.issues)
end
function Sem.FieldLayoutMissing:tree_check_dot_field_expr(input, base, dot)
  return LCheck.TypeExprResult(Tr.ExprDot(Tr.ExprTyped(Ty.TScalar(C.ScalarVoid)), base.expr, dot.name), Ty.TScalar(C.ScalarVoid), base.issues)
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
      if expected ~= ar.ty then
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
  local br = self.base:typecheck_tree_index_base(LCheck.TypeIndexBaseInput(input.scope))
  local ir = self.index:typecheck_tree_expr(input)
  local issues = {}
  for i = 1, #(br.issues or {}) do issues[#issues + 1] = br.issues[i] end
  for i = 1, #(ir.issues or {}) do issues[#issues + 1] = ir.issues[i] end
  return LCheck.TypeExprResult(
    Tr.ExprIndex(Tr.ExprTyped(br.elem), br.base, ir.expr), br.elem, issues)
end

function Tr.IndexBase:typecheck_tree_index_base(_input)
  return LCheck.TypeIndexBaseResult(self, Ty.TScalar(C.ScalarVoid),
    { LCheck.TypeIssueExpected("index base", Ty.TPtr(Ty.TScalar(C.ScalarVoid)), Ty.TScalar(C.ScalarVoid)) })
end
function Tr.IndexBaseExpr:typecheck_tree_index_base(input)
  local result = self.base:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  local elem = result.ty:tree_code_index_elem_type()
  if elem == nil then
    local issues = {}
    for i = 1, #(result.issues or {}) do issues[i] = result.issues[i] end
    issues[#issues + 1] = LCheck.TypeIssueNotIndexable(result.ty)
    return LCheck.TypeIndexBaseResult(Tr.IndexBaseExpr(result.expr), Ty.TScalar(C.ScalarVoid), issues)
  end
  return LCheck.TypeIndexBaseResult(Tr.IndexBaseExpr(result.expr), elem, result.issues or {})
end
function Tr.IndexBasePlace:typecheck_tree_index_base(input)
  local result = self.base:typecheck_tree_place(LCheck.TypePlaceInput(input.scope))
  return LCheck.TypeIndexBaseResult(
    Tr.IndexBasePlace(result.place, self.elem), self.elem, result.issues or {})
end

-- ExprIntrinsic moved below; see full implementation

-- Place typechecking
function Tr.Place:typecheck_tree_place(input)
  local ty = self.h and self.h:tree_code_place_type() or Ty.TScalar(C.ScalarVoid)
  return LCheck.TypePlaceResult(self, ty, {})
end

function LCheck.TypeValueLookupFound:typecheck_tree_place_ref(place)
  local typed = Tr.PlaceRef(Tr.PlaceTyped(self.binding.ty), B.ValueRefBinding(self.binding))
  return LCheck.TypePlaceResult(typed, self.binding.ty, {})
end

function LCheck.TypeValueLookupMissing:typecheck_tree_place_ref(place)
  return LCheck.TypePlaceResult(place, nil, {LCheck.TypeIssueUnresolvedValue(self.name)})
end

function Tr.PlaceRef:typecheck_tree_place(input)
  local ref_name = self.ref:typecheck_tree_ref_name()
  if not ref_name then
    return LCheck.TypePlaceResult(self, nil, {LCheck.TypeIssueUnresolvedValue("?")})
  end
  return input.scope:typecheck_tree_lookup_value(ref_name):typecheck_tree_place_ref(self)
end

function Tr.PlaceDeref:typecheck_tree_place(input)
  local er = self.base:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  if er.ty and er.ty:tree_check_is_ptr_type() then
    return LCheck.TypePlaceResult(Tr.PlaceDeref(Tr.PlaceTyped(er.ty.elem), er.expr), er.ty.elem, er.issues or {})
  end
  return LCheck.TypePlaceResult(self, nil, er.issues or {})
end
function Tr.PlaceIndex:typecheck_tree_place(input)
  local base = self.base:typecheck_tree_index_base(LCheck.TypeIndexBaseInput(input.scope))
  local index = self.index:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  local issues = {}
  for i = 1, #(base.issues or {}) do issues[#issues + 1] = base.issues[i] end
  for i = 1, #(index.issues or {}) do issues[#issues + 1] = index.issues[i] end
  return LCheck.TypePlaceResult(
    Tr.PlaceIndex(Tr.PlaceTyped(base.elem), base.base, index.expr), base.elem, issues)
end

-- PlaceDot: the named-ref leaves own the layout search, the layout
-- lookup leaves own the field decision, and the field lookup leaves own
-- the lowered PlaceField result (no nil protocol). Mirrors ExprDot.
function Tr.PlaceDot:typecheck_tree_place(input)
  local base = self.base:typecheck_tree_place(LCheck.TypePlaceInput(input.scope))
  local field_lookup = tree_check_field_layout_for(input.scope, base.ty, self.name)
  return field_lookup:tree_check_dot_field_place(input, base, self)
end
function Sem.FieldLayoutFound:tree_check_dot_field_place(input, base, dot)
  local field = self.layout
  -- Lower to a resolved field ref (offset + storage) so the code phase
  -- can emit field access directly; FieldByName would require a
  -- separate sem_layout_resolve pass the v2 pipeline does not run.
  local ref = Sem.FieldByOffset(field.field_name, field.offset, field.ty, field.ty:sem_layout_storage())
  return LCheck.TypePlaceResult(Tr.PlaceField(Tr.PlaceTyped(field.ty), base.place, ref), field.ty, base.issues)
end
function Sem.FieldLayoutMissing:tree_check_dot_field_place(input, base, dot)
  return LCheck.TypePlaceResult(dot, Ty.TScalar(C.ScalarVoid), base.issues)
end

-- ============================================================
-- Remaining expr leaves (real implementations)
-- ============================================================

function Tr.ExprAgg:typecheck_tree_expr(input)
  -- Struct aggregate init: canonicalize type, resolve each field's offset
  -- from the layout, typecheck each field value.
  local ty = self.ty  -- canonicalized by caller if needed
  local fields = {}
  local issues = {}
  for i = 1, #(self.fields or {}) do
    local fi = self.fields[i]
    local vr = fi.value:typecheck_tree_expr(input)
    if vr.issues then for _, iss in ipairs(vr.issues) do issues[#issues+1]=iss end end
    -- The field layout leaves own the offset decision; the aggregate init
    -- carries the resolved offset so the code phase can emit field stores.
    local offset_lookup = tree_check_field_layout_for(input.scope, ty, fi.name)
    local init = offset_lookup:tree_check_agg_field_init(input, ty, fi, vr)
    fields[#fields+1] = init.init
    for j = 1, #init.issues do issues[#issues+1] = init.issues[j] end
  end
  return LCheck.TypeExprResult(Tr.ExprAgg(Tr.ExprTyped(ty), ty, fields), ty, issues)
end
function Sem.FieldLayoutFound:tree_check_agg_field_init(input, agg_ty, fi, vr)
  return LCheck.TypeAggFieldInit(Tr.FieldInit(fi.name, vr.expr, self.layout.offset), {})
end
function Sem.FieldLayoutMissing:tree_check_agg_field_init(input, agg_ty, fi, vr)
  return LCheck.TypeAggFieldInit(Tr.FieldInit(fi.name, vr.expr, fi.offset), { LCheck.TypeIssueExpected("aggregate field", agg_ty, vr.ty) })
end

-- ExprAgg:typecheck_tree_expr_expected: delegate to type if aggregate
function Tr.ExprAgg:typecheck_tree_expr_expected(input)
  if input.expected and input.expected:tree_check_is_aggregate_type() then
    return Tr.ExprAgg(Tr.ExprSurface, input.expected, self.fields):typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
  end
  return self:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
end

function Tr.ExprArray:typecheck_tree_expr(input)
  -- Array init: typecheck elements, validate count if expected
  local issues = {}
  local elems = {}
  for i = 1, #(self.elems or {}) do
    local er = self.elems[i]:typecheck_tree_expr(input)
    if er.issues then for _, iss in ipairs(er.issues) do issues[#issues+1]=iss end end
    if er.ty and er.expr then
      elems[#elems+1] = er.expr
      -- Validate element type against elem_ty
      if not self.elem_ty:tree_check_is_void_type() and not er.ty:tree_check_is_void_type() then
        if self.elem_ty ~= er.ty then
          issues[#issues+1] = LCheck.TypeIssueExpected("array elem", self.elem_ty, er.ty)
        end
      end
    else
      elems[#elems+1] = self.elems[i]
    end
  end
  local result_ty = Ty.TArray(Ty.ArrayLenConst(#elems), self.elem_ty)
  return LCheck.TypeExprResult(Tr.ExprArray(Tr.ExprTyped(result_ty), self.elem_ty, elems), result_ty, issues)
end

-- ExprArray:typecheck_tree_expr_expected: match element types against expected array
function Tr.ExprArray:typecheck_tree_expr_expected(input)
  if input.expected and input.expected:tree_check_is_array_type() then
    local counts_match = true
    if input.expected.count and input.expected.count:tree_check_is_const() then
      local expected_n = input.expected.count:tree_check_const_value()
      if expected_n ~= #(self.elems or {}) then
        local issues = {LCheck.TypeIssueExpected("array length", input.expected, Ty.TArray(Ty.ArrayLenConst(#(self.elems or 0)), input.expected.elem))}
        return LCheck.TypeExprResult(self, input.expected, issues)
      end
    end
    local issues = {}
    local elems = {}
    for i = 1, #(self.elems or {}) do
      local er = self.elems[i]:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, input.expected.elem))
      if er.issues then for _, iss in ipairs(er.issues) do issues[#issues+1]=iss end end
      if er.ty and er.expr then
        elems[#elems+1] = er.expr
        if input.expected.elem ~= er.ty then
          issues[#issues+1] = LCheck.TypeIssueExpected("array elem", input.expected.elem, er.ty)
        end
      else
        elems[#elems+1] = self.elems[i]
      end
    end
    local result_ty = Ty.TArray(Ty.ArrayLenConst(#elems), input.expected.elem)
    return LCheck.TypeExprResult(Tr.ExprArray(Tr.ExprTyped(result_ty), input.expected.elem, elems), result_ty, issues)
  end
  return self:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
end

function Tr.ExprNull:typecheck_tree_expr(input)
  -- Null of pointer type: type = TPtr(elem)
  local ptr_ty = self.elem:tree_check_is_ptr_type() and self.elem or Ty.TPtr(self.elem)
  return LCheck.TypeExprResult(Tr.ExprNull(Tr.ExprTyped(ptr_ty), self.elem), ptr_ty, {})
end

function Tr.ExprSizeOf:typecheck_tree_expr(input)
  -- SizeOf returns index type; layout computed later in lowering
  return LCheck.TypeExprResult(Tr.ExprSizeOf(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), self.ty), Ty.TScalar(C.ScalarIndex), {})
end

function Tr.ExprAlignOf:typecheck_tree_expr(input)
  -- AlignOf returns index type
  return LCheck.TypeExprResult(Tr.ExprAlignOf(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), self.ty), Ty.TScalar(C.ScalarIndex), {})
end

function Tr.ExprIsNull:typecheck_tree_expr(input)
  -- IsNull: value must be pointer or nullable type, returns bool
  local vr = self.value:typecheck_tree_expr(input)
  if vr.ty == nil then return LCheck.TypeExprResult(nil, nil, vr.issues or {}) end
  local issues = {}
  if vr.issues then for _, iss in ipairs(vr.issues) do issues[#issues+1]=iss end end
  if not vr.ty:tree_check_is_ptr_type() then
    issues[#issues+1] = LCheck.TypeIssueNotPointer(vr.ty)
  end
  return LCheck.TypeExprResult(Tr.ExprIsNull(Tr.ExprTyped(Ty.TScalar(C.ScalarBool)), vr.expr), Ty.TScalar(C.ScalarBool), issues)
end

-- ExprCtor: variant lookup alternatives own construction behavior.
local function ctor_without_payload(lookup, expr)
  local issues = {}
  if #expr.args ~= 0 then issues[#issues + 1] = LCheck.TypeIssueArgCount("variant constructor", 0, #expr.args) end
  return LCheck.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(lookup.def.ty), expr.type_name, expr.variant_name, {}), lookup.def.ty, issues)
end

function LCheck.TypeVariantPayloadNone:typecheck_tree_ctor_payload(lookup, expr, input)
  return ctor_without_payload(lookup, expr)
end

function LCheck.TypeVariantPayloadUnsupported:typecheck_tree_ctor_payload(lookup, expr, input)
  local issues = { LCheck.TypeIssueVariantPayloadUnsupported(lookup.def.type_name, expr.variant_name, self.field_count) }
  local args = {}
  for i = 1, #expr.args do
    local ar = expr.args[i]:typecheck_tree_expr(input)
    for _, issue in ipairs(ar.issues or {}) do issues[#issues + 1] = issue end
    args[i] = ar.expr
  end
  return LCheck.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(lookup.def.ty), expr.type_name, expr.variant_name, args), lookup.def.ty, issues)
end

function LCheck.TypeVariantPayloadFound:typecheck_tree_ctor_payload(lookup, expr, input)
  local issues, args = {}, {}
  if #expr.args ~= 1 then issues[#issues + 1] = LCheck.TypeIssueArgCount("variant constructor", 1, #expr.args) end
  if #expr.args >= 1 then
    local ar = expr.args[1]:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, self.ty))
    for _, issue in ipairs(ar.issues or {}) do issues[#issues + 1] = issue end
    if ar.ty ~= self.ty then issues[#issues + 1] = LCheck.TypeIssueExpected("variant payload", self.ty, ar.ty) end
    args[1] = ar.expr
  end
  return LCheck.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(lookup.def.ty), expr.type_name, expr.variant_name, args), lookup.def.ty, issues)
end

function LCheck.TypeVariantCaseLookupFound:typecheck_tree_ctor(expr, input)
  return self.case:typecheck_tree_payload_lookup():typecheck_tree_ctor_payload(self, expr, input)
end

function LCheck.TypeVariantCaseLookupMissing:typecheck_tree_ctor(expr, input)
  local issues = { LCheck.TypeIssueUnknownVariant(self.type_name, self.variant_name) }
  if #expr.args ~= 0 then issues[#issues + 1] = LCheck.TypeIssueArgCount("variant constructor", 0, #expr.args) end
  return LCheck.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(self.ty), expr.type_name, expr.variant_name, {}), self.ty, issues)
end

function Tr.ExprCtor:typecheck_tree_expr(input)
  return input.scope.facts:typecheck_tree_lookup_variant_name(self.type_name)
    :typecheck_tree_lookup_variant_case(self.variant_name)
    :typecheck_tree_ctor(self, input)
end

-- ExprLoad: validate that addr is a pointer to self.ty
function Tr.ExprLoad:typecheck_tree_expr(input)
  local expected_ptr = Ty.TPtr(self.ty)
  local ar = self.addr:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, expected_ptr))
  local issues = {}
  if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
  if ar.ty and not ar.ty:tree_check_is_void_type() then
    if not ar.ty:tree_check_is_ptr_type() then
      issues[#issues+1] = LCheck.TypeIssueNotPointer(ar.ty)
    end
  end
  return LCheck.TypeExprResult(Tr.ExprLoad(Tr.ExprTyped(self.ty), self.ty, ar.expr or self.addr), self.ty, issues)
end

-- ExprAtomicLoad: validate address is pointer to self.ty
function Tr.ExprAtomicLoad:typecheck_tree_expr(input)
  local expected_ptr = Ty.TPtr(self.ty)
  local ar = self.addr:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, expected_ptr))
  local issues = {}
  if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
  if ar.ty and not ar.ty:tree_check_is_void_type() and not ar.ty:tree_check_is_ptr_type() then
    issues[#issues+1] = LCheck.TypeIssueNotPointer(ar.ty)
  end
  return LCheck.TypeExprResult(Tr.ExprAtomicLoad(Tr.ExprTyped(self.ty), self.ty, ar.expr or self.addr, self.ordering), self.ty, issues)
end

-- ExprAtomicRmw: validate address is ptr, value matches
function Tr.ExprAtomicRmw:typecheck_tree_expr(input)
  local expected_ptr = Ty.TPtr(self.ty)
  local ar = self.addr:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, expected_ptr))
  local vr = self.value:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, self.ty))
  local issues = {}
  if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
  if vr.issues then for _, iss in ipairs(vr.issues) do issues[#issues+1]=iss end end
  if ar.ty and not ar.ty:tree_check_is_void_type() and not ar.ty:tree_check_is_ptr_type() then
    issues[#issues+1] = LCheck.TypeIssueNotPointer(ar.ty)
  end
  if vr.ty and not vr.ty:tree_check_is_void_type() and self.ty and not self.ty:tree_check_is_void_type() then
    if self.ty ~= vr.ty then
      issues[#issues+1] = LCheck.TypeIssueExpected("atomic rmw value", self.ty, vr.ty)
    end
  end
  return LCheck.TypeExprResult(Tr.ExprAtomicRmw(Tr.ExprTyped(self.ty), self.op, self.ty, ar.expr or self.addr, vr.expr or self.value, self.ordering), self.ty, issues)
end

-- ExprAtomicCas: validate addr is ptr, expected/replacement match
function Tr.ExprAtomicCas:typecheck_tree_expr(input)
  local expected_ptr = Ty.TPtr(self.ty)
  local ar = self.addr:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, expected_ptr))
  local er = self.expected:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, self.ty))
  local rr = self.replacement:typecheck_tree_expr_expected(LCheck.TypeExpectedExprInput(input.scope, self.ty))
  local issues = {}
  if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
  if er.issues then for _, iss in ipairs(er.issues) do issues[#issues+1]=iss end end
  if rr.issues then for _, iss in ipairs(rr.issues) do issues[#issues+1]=iss end end
  if ar.ty and not ar.ty:tree_check_is_void_type() and not ar.ty:tree_check_is_ptr_type() then
    issues[#issues+1] = LCheck.TypeIssueNotPointer(ar.ty)
  end
  if er.ty and not er.ty:tree_check_is_void_type() and self.ty and not self.ty:tree_check_is_void_type() then
    if self.ty ~= er.ty then
      issues[#issues+1] = LCheck.TypeIssueExpected("atomic cas expected", self.ty, er.ty)
    end
  end
  if rr.ty and not rr.ty:tree_check_is_void_type() and self.ty and not self.ty:tree_check_is_void_type() then
    if self.ty ~= rr.ty then
      issues[#issues+1] = LCheck.TypeIssueExpected("atomic cas replacement", self.ty, rr.ty)
    end
  end
  return LCheck.TypeExprResult(Tr.ExprAtomicCas(Tr.ExprTyped(self.ty), self.ty, ar.expr or self.addr, er.expr or self.expected, rr.expr or self.replacement, self.ordering), self.ty, issues)
end

-- ExprSelect: variant discrimination (select condition on variant type)
function Tr.ExprSelect:typecheck_tree_expr(input)
  local cr = self.cond:typecheck_tree_expr(input)
  if cr.ty == nil or cr.expr == nil then return cr end
  local tr = self.then_expr:typecheck_tree_expr(input)
  if tr.ty == nil or tr.expr == nil then return tr end
  local er = self.else_expr:typecheck_tree_expr(input)
  if er.ty == nil or er.expr == nil then return er end
  local issues = {}
  if cr.issues then for _, iss in ipairs(cr.issues) do issues[#issues+1]=iss end end
  if tr.issues then for _, iss in ipairs(tr.issues) do issues[#issues+1]=iss end end
  if er.issues then for _, iss in ipairs(er.issues) do issues[#issues+1]=iss end end
  -- Branch type unification
  local result_ty = tr.ty
  if tr.ty and er.ty then
    if tr.ty ~= er.ty then
      issues[#issues+1] = LCheck.TypeIssueExpected("select branches", tr.ty, er.ty)
    end
  end
  return LCheck.TypeExprResult(Tr.ExprSelect(Tr.ExprTyped(result_ty), cr.expr, tr.expr, er.expr), result_ty, issues)
end

-- ExprSwitch: switch expression with scalar + variant arms, default
function Tr.ExprSwitch:typecheck_tree_expr(input)
  local vr = self.value:typecheck_tree_expr(input)
  if vr.ty == nil or vr.expr == nil then return LCheck.TypeExprResult(nil, nil, vr.issues or {}) end
  local issues = {}
  if vr.issues then for _, iss in ipairs(vr.issues) do issues[#issues+1]=iss end end
  local result_ty = nil
  -- Typecheck each scalar arm (result expression)
  local arms = {}
  for i = 1, #(self.arms or {}) do
    local arm = self.arms[i]
    local stmt_input = LCheck.TypeStmtInput(input.scope, Ty.TScalar(C.ScalarVoid), LCheck.TypeYieldNone)
    local body = stmt_input:typecheck_tree_stmt_body(arm.body or {})
    local ar = arm.result:typecheck_tree_expr(input)
    if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
    if ar.ty and not ar.ty:tree_check_is_void_type() then
      if result_ty == nil then result_ty = ar.ty
      elseif result_ty ~= ar.ty then
        issues[#issues+1] = LCheck.TypeIssueExpected("switch arm", result_ty, ar.ty)
      end
    end
    arms[#arms+1] = Tr.SwitchExprArm(arm.key, body.stmts, ar.expr or arm.result)
  end
  -- Typecheck variant arms
  local variant_arms = {}
  for i = 1, #(self.variant_arms or {}) do
    local va = self.variant_arms[i]
    local scope = input.scope
    for j = 1, #(va.binds or {}) do
      scope = scope:typecheck_tree_add_value(va.binds[j].name, va.binds[j].ty)
    end
    local stmt_input = LCheck.TypeStmtInput(scope, Ty.TScalar(C.ScalarVoid), LCheck.TypeYieldNone)
    local body = stmt_input:typecheck_tree_stmt_body(va.body or {})
    local ar = va.result:typecheck_tree_expr(LCheck.TypeExprInput(scope))
    if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
    if ar.ty and not ar.ty:tree_check_is_void_type() then
      if result_ty == nil then result_ty = ar.ty
      elseif result_ty ~= ar.ty then
        issues[#issues+1] = LCheck.TypeIssueExpected("switch variant arm", result_ty, ar.ty)
      end
    end
    variant_arms[#variant_arms+1] = Tr.SwitchVariantExprArm(va.variant_name, va.binds, body.stmts, ar.expr or va.result)
  end
  -- Typecheck default
  local stmt_input = LCheck.TypeStmtInput(input.scope, Ty.TScalar(C.ScalarVoid), LCheck.TypeYieldNone)
  local default_body = stmt_input:typecheck_tree_stmt_body(self.default_body or {})
  local default_expr = self.default_expr and self.default_expr:typecheck_tree_expr(input)
  if default_expr and default_expr.ty and not default_expr.ty:tree_check_is_void_type() then
    if result_ty == nil then result_ty = default_expr.ty
    elseif result_ty ~= default_expr.ty then
      issues[#issues+1] = LCheck.TypeIssueExpected("switch default", result_ty, default_expr.ty)
    end
  end
  if result_ty == nil then result_ty = Ty.TScalar(C.ScalarVoid) end
  return LCheck.TypeExprResult(Tr.ExprSwitch(Tr.ExprTyped(result_ty), vr.expr, arms, variant_arms, default_body.stmts, default_expr and default_expr.expr or self.default_expr), result_ty, issues)
end

-- Expression control regions own value-yield typing and exact parameter identities.
local function expr_control_scope(input, region_id, label, params, is_entry, result_ty)
  local scope = input.scope
  for i = 1, #(params or {}) do
    local param = params[i]
    local role = is_entry
      and B.BindingRoleEntryBlockParam(region_id, label.name, i)
      or B.BindingRoleBlockParam(region_id, label.name, i)
    local binding = B.Binding(C.Id("control:param:" .. region_id .. "_" ..
      label.name .. "_" .. param.name), param.name, param.ty, role)
    scope = scope:typecheck_tree_add_value(param.name, param.ty, binding)
  end
  return LCheck.TypeStmtInput(scope, result_ty, LCheck.TypeYieldValue(result_ty))
end
function Tr.ControlExprRegion:typecheck_tree_expr_region(input)
  local result_ty = self.result_ty or Ty.TScalar(C.ScalarVoid)
  local issues = {}
  local entry_input = expr_control_scope(input, self.region_id,
    self.entry.label, self.entry.params, true, result_ty)
  local entry_result = entry_input:typecheck_tree_stmt_body(self.entry.body or {})
  for i = 1, #(entry_result.issues or {}) do issues[#issues + 1] = entry_result.issues[i] end
  local entry = Tr.EntryControlBlock(
    self.entry.label, self.entry.params, entry_result.stmts)
  local blocks = {}
  for i = 1, #(self.blocks or {}) do
    local block = self.blocks[i]
    local block_input = expr_control_scope(input, self.region_id,
      block.label, block.params, false, result_ty)
    local block_result = block_input:typecheck_tree_stmt_body(block.body or {})
    blocks[i] = Tr.ControlBlock(block.label, block.params, block_result.stmts)
    for j = 1, #(block_result.issues or {}) do
      issues[#issues + 1] = block_result.issues[j]
    end
  end
  return LCheck.TypeControlExprRegionResult(
    Tr.ControlExprRegion(self.region_id, result_ty, entry, blocks), issues)
end
function Tr.ExprControl:typecheck_tree_expr(input)
  local result = self.region:typecheck_tree_expr_region(input)
  return LCheck.TypeExprResult(
    Tr.ExprControl(Tr.ExprTyped(result.region.result_ty), result.region),
    result.region.result_ty, result.issues)
end
function Tr.ExprDomainControl:typecheck_tree_expr(input)
  local result = self.region:typecheck_tree_expr_region(input)
  return LCheck.TypeExprResult(
    Tr.ExprDomainControl(Tr.ExprTyped(result.region.result_ty),
      result.region, self.domain),
    result.region.result_ty, result.issues)
end

-- ExprView: view/slice construction
function Tr.ExprView:typecheck_tree_expr(input)
  if not self.view then
    return LCheck.TypeExprResult(nil, nil, {})
  end
  local view_ty = Ty.TView(self.view.elem)
  return LCheck.TypeExprResult(Tr.ExprView(Tr.ExprTyped(view_ty), self.view), view_ty, {})
end

-- ExprLen: compute length of array/slice/view
function Tr.ExprLen:typecheck_tree_expr(input)
  local vr = self.value:typecheck_tree_expr(input)
  if vr.ty == nil then return LCheck.TypeExprResult(nil, nil, vr.issues or {}) end
  local issues = {}
  if vr.issues then for _, iss in ipairs(vr.issues) do issues[#issues+1]=iss end end
  -- Validate the value has a len operation (arrays, slices, views)
  local ok = vr.ty:tree_check_is_aggregate_type()
  if ok == false then
    issues[#issues+1] = LCheck.TypeIssueNotIndexable(vr.ty)
  end
  return LCheck.TypeExprResult(Tr.ExprLen(Tr.ExprTyped(Ty.TScalar(C.ScalarIndex)), vr.expr), Ty.TScalar(C.ScalarIndex), issues)
end

-- ExprIntrinsic: per-intrinsic return type resolution
function Tr.ExprIntrinsic:typecheck_tree_expr(input)
  local args, issues = {}, {}
  for i = 1, #(self.args or {}) do
    local ar = self.args[i]:typecheck_tree_expr(input)
    if ar.ty == nil then return ar end
    if ar.issues then for _, iss in ipairs(ar.issues) do issues[#issues+1]=iss end end
    args[i] = ar.expr
  end
  -- Determine return type based on intrinsic
  local result_ty = self.op:typecheck_tree_intrinsic_result(self.args or {})
  if result_ty == nil then result_ty = Ty.TScalar(C.ScalarVoid) end
  return LCheck.TypeExprResult(Tr.ExprIntrinsic(Tr.ExprTyped(result_ty), self.op, args), result_ty, issues)
end

-- Intrinsic result type resolution (leaf methods on Intrinsic)
function C.Intrinsic:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarVoid) end
function C.IntrinsicPopcount:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarI32) end
function C.IntrinsicClz:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarI32) end
function C.IntrinsicCtz:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarI32) end
function C.IntrinsicRotl:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarI32) end
function C.IntrinsicRotr:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarI32) end
function C.IntrinsicBswap:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarI32) end
function C.IntrinsicFma:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarF64) end
function C.IntrinsicSqrt:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarF64) end
function C.IntrinsicAbs:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarI32) end
function C.IntrinsicFloor:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarF64) end
function C.IntrinsicCeil:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarF64) end
function C.IntrinsicTruncFloat:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarF64) end
function C.IntrinsicRound:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarF64) end
function C.IntrinsicTrap:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarVoid) end
function C.IntrinsicAssume:typecheck_tree_intrinsic_result(args) return Ty.TScalar(C.ScalarVoid) end

-- ExprBlock: statements introduce a lexical scope used by the result.
function Tr.ExprBlock:typecheck_tree_expr(input)
  local stmt_input = LCheck.TypeStmtInput(input.scope, Ty.TScalar(C.ScalarVoid), LCheck.TypeYieldNone)
  local body = stmt_input:typecheck_tree_stmt_body(self.stmts)
  local result = self.result:typecheck_tree_expr(LCheck.TypeExprInput(body.state.scope))
  local issues = {}
  for i=1,#body.issues do issues[#issues+1]=body.issues[i] end
  for i=1,#result.issues do issues[#issues+1]=result.issues[i] end
  return LCheck.TypeExprResult(Tr.ExprBlock(Tr.ExprTyped(result.ty),body.stmts,result.expr),result.ty,issues)
end

-- ExprClosure: build closure type from params and result
function Tr.ExprClosure:typecheck_tree_expr(input)
  -- Typecheck the body with local scope
  local scope = input.scope
  for j = 1, #(self.params or {}) do
    local p = self.params[j]
    scope = scope:typecheck_tree_add_value(p.name, p.ty)
  end
  local stmt_input = LCheck.TypeStmtInput(scope, self.result, LCheck.TypeYieldNone)
  local body = stmt_input:typecheck_tree_stmt_body(self.body or {})
  local param_types = {}
  for i = 1, #self.params do param_types[i] = self.params[i].ty end
  local closure_ty = Ty.TClosure(param_types, self.result)
  return LCheck.TypeExprResult(Tr.ExprClosure(Tr.ExprTyped(closure_ty), self.params, self.result, body.stmts), closure_ty, {})
end

-- ============================================================
-- typecheck_tree_expr_expected: default fallback
-- ============================================================
function Tr.Expr:typecheck_tree_expr_expected(input)
  return self:typecheck_tree_expr(LCheck.TypeExprInput(input.scope))
end
