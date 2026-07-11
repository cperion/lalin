return function(T)
    local asdl = require("lalin.asdl")
    local C = T.LalinCore
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local Check = T.LalinCheck
    local function void_ty()
        return Ty.TScalar(C.ScalarVoid)
    end

    local function canonical_type(scope, ty)
        return ty:typecheck_tree_canonical(scope)
    end

    local function append_all(out, values)
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    end

    local function type_eq(a, b)
        return a == b
    end

    function Ty.Type:typecheck_tree_field_lookup_base()
        return self
    end

    function Ty.TPtr:typecheck_tree_field_lookup_base()
        return self.elem
    end

    function Ty.TAccess:typecheck_tree_field_lookup_base()
        return self.base:typecheck_tree_field_lookup_base()
    end

    function Ty.TLease:typecheck_tree_field_lookup_base()
        return self.base:typecheck_tree_field_lookup_base()
    end

    local function field_layout_for(scope, ty, field_name)
        ty = canonical_type(scope, ty):typecheck_tree_field_lookup_base()
        local ref = ty:typecheck_tree_named_ref()
        if ref == nil then return nil end
        for i = 1, #scope.layouts do
            local layout = scope.layouts[i]
            if layout:typecheck_tree_matches_ref(ref) then return layout:typecheck_tree_field_layout(field_name) end
        end
        return nil
    end

    function Tr.ExprHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.ExprTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    function Tr.PlaceHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.PlaceTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    function C.Scalar:typecheck_tree_cast_bits() return nil end
    function C.ScalarBool:typecheck_tree_cast_bits() return 8 end
    function C.ScalarI8:typecheck_tree_cast_bits() return 8 end
    function C.ScalarI16:typecheck_tree_cast_bits() return 16 end
    function C.ScalarI32:typecheck_tree_cast_bits() return 32 end
    function C.ScalarI64:typecheck_tree_cast_bits() return 64 end
    function C.ScalarU8:typecheck_tree_cast_bits() return 8 end
    function C.ScalarU16:typecheck_tree_cast_bits() return 16 end
    function C.ScalarU32:typecheck_tree_cast_bits() return 32 end
    function C.ScalarU64:typecheck_tree_cast_bits() return 64 end
    function C.ScalarF32:typecheck_tree_cast_bits() return 32 end
    function C.ScalarF64:typecheck_tree_cast_bits() return 64 end
    function C.ScalarIndex:typecheck_tree_cast_bits() return 64 end

    function C.Scalar:typecheck_tree_cast_is_float() return false end
    function C.ScalarF32:typecheck_tree_cast_is_float() return true end
    function C.ScalarF64:typecheck_tree_cast_is_float() return true end

    function C.Scalar:typecheck_tree_cast_is_signed_int() return false end
    function C.ScalarI8:typecheck_tree_cast_is_signed_int() return true end
    function C.ScalarI16:typecheck_tree_cast_is_signed_int() return true end
    function C.ScalarI32:typecheck_tree_cast_is_signed_int() return true end
    function C.ScalarI64:typecheck_tree_cast_is_signed_int() return true end

    function C.Scalar:typecheck_tree_cast_is_unsigned_int() return false end
    function C.ScalarBool:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU8:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU16:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU32:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarU64:typecheck_tree_cast_is_unsigned_int() return true end
    function C.ScalarIndex:typecheck_tree_cast_is_unsigned_int() return true end

    function C.Scalar:typecheck_tree_cast_is_int() return self:typecheck_tree_cast_is_signed_int() or self:typecheck_tree_cast_is_unsigned_int() end

    function Ty.Type:typecheck_tree_scalar_cast_op(op, to)
        if op == C.SurfaceCast and self == to then return C.MachineCastIdentity end
        return nil
    end
    function Ty.TScalar:typecheck_tree_scalar_cast_op(op, to)
        return to:typecheck_tree_scalar_cast_from(op, self.scalar)
    end
    function Ty.TPtr:typecheck_tree_scalar_cast_op(op, to)
        if op == C.SurfaceCast
            and asdl.classof(to) == Ty.TPtr
            and type_eq(self.pointee, to.pointee)
        then
            return C.MachineCastIdentity
        end
        return nil
    end
    function Ty.Type:typecheck_tree_scalar_cast_from() return nil end
    function Ty.TScalar:typecheck_tree_scalar_cast_from(op, from)
        return op:typecheck_tree_machine_cast(from, self.scalar)
    end

    function C.SurfaceCastOp:typecheck_tree_machine_cast() return nil end
    function C.SurfaceBitcast:typecheck_tree_machine_cast(from, to) return C.MachineCastBitcast end
    function C.SurfaceTrunc:typecheck_tree_machine_cast(from, to) return C.MachineCastIreduce end
    function C.SurfaceSExt:typecheck_tree_machine_cast(from, to) return C.MachineCastSextend end
    function C.SurfaceZExt:typecheck_tree_machine_cast(from, to) return C.MachineCastUextend end
    function C.SurfaceSatCast:typecheck_tree_machine_cast() return nil end
    function C.SurfaceCast:typecheck_tree_machine_cast(from, to)
        if from == to then return C.MachineCastIdentity end
        local from_bits = from:typecheck_tree_cast_bits()
        local to_bits = to:typecheck_tree_cast_bits()
        if from_bits == nil or to_bits == nil then return nil end
        local from_float = from:typecheck_tree_cast_is_float()
        local to_float = to:typecheck_tree_cast_is_float()
        if from_float and to_float then
            if from_bits < to_bits then return C.MachineCastFpromote end
            if from_bits > to_bits then return C.MachineCastFdemote end
            return C.MachineCastBitcast
        end
        if from_float and to:typecheck_tree_cast_is_int() then
            return to:typecheck_tree_cast_is_signed_int() and C.MachineCastFToS or C.MachineCastFToU
        end
        if from:typecheck_tree_cast_is_int() and to_float then
            return from:typecheck_tree_cast_is_signed_int() and C.MachineCastSToF or C.MachineCastUToF
        end
        if from:typecheck_tree_cast_is_int() and to:typecheck_tree_cast_is_int() then
            if from_bits > to_bits then return C.MachineCastIreduce end
            if from_bits < to_bits then
                return from:typecheck_tree_cast_is_signed_int() and C.MachineCastSextend or C.MachineCastUextend
            end
            return C.MachineCastBitcast
        end
        return nil
    end

    function B.ValueRefBinding:typecheck_tree_ref()
        return Check.TypeValueRefResult(self, self.binding.ty, {})
    end

    function B.ValueRefName:typecheck_tree_ref(input)
        return input.scope:typecheck_tree_lookup_value(self.name):typecheck_tree_ref(self)
    end

    function B.ValueRefPath:typecheck_tree_ref()
        return Check.TypeValueRefResult(self, void_ty(), { Check.TypeIssueUnresolvedPath(self.path) })
    end

    function Tr.Expr:typecheck_tree_expr(_input)
        error("tree_typecheck: missing typecheck_tree_expr leaf method", 2)
    end

    function Tr.ExprLit:typecheck_tree_expr()
        local ty = self.value:typecheck_tree_literal()
        return Check.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(ty), self.value), ty, {})
    end

    function Tr.ExprLit:typecheck_tree_expr_expected(input)
        local ty = self.value:typecheck_tree_literal_expected(input.expected)
        if input.expected ~= nil
            and ty:typecheck_tree_is_integer_scalar()
            and input.expected:typecheck_tree_is_integer_scalar()
        then
            ty = input.expected
        end
        return Check.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(ty), self.value), ty, {})
    end

    function B.ValueRef:typecheck_tree_binding_name() return nil end
    function B.ValueRefName:typecheck_tree_binding_name() return self.name end
    function B.ValueRefBinding:typecheck_tree_binding_name() return self.binding.name end

    function Tr.Expr:typecheck_tree_binding_name() return nil end
    function Tr.ExprRef:typecheck_tree_binding_name() return self.ref:typecheck_tree_binding_name() end

    function Check.TypeValueScope:typecheck_tree_check_live_lease_invalidation(actual, issues)
        local actual_name = actual:typecheck_tree_binding_name()
        for i = #self.values, 1, -1 do
            self.values[i].binding.ty:typecheck_tree_check_lease_origin_invalidation(actual_name, issues)
        end
    end

    function Tr.ExprRef:typecheck_tree_expr(input)
        local ref_result = self.ref:typecheck_tree_ref(Check.TypeValueRefInput(input.scope))
        return Check.TypeExprResult(Tr.ExprRef(Tr.ExprTyped(ref_result.ty), ref_result.ref), ref_result.ty, ref_result.issues)
    end

    function Tr.ExprDot:typecheck_tree_expr(input)
        local base = self.base:typecheck_tree_expr(input)
        local typed_ty = self.h:typecheck_tree_typed_ty()
        local field = field_layout_for(input.scope, base.ty, self.name)
        if field ~= nil then
            local ref = Sem.FieldByName(field.field_name, field.ty)
            return Check.TypeExprResult(Tr.ExprField(Tr.ExprTyped(field.ty), base.expr, ref), field.ty, base.issues)
        end
        if typed_ty ~= nil then return Check.TypeExprResult(Tr.ExprDot(Tr.ExprTyped(typed_ty), base.expr, self.name), typed_ty, base.issues) end
        return Check.TypeExprResult(Tr.ExprDot(Tr.ExprTyped(void_ty()), base.expr, self.name), void_ty(), base.issues)
    end

    function Tr.ExprCast:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local ty = canonical_type(input.scope, self.ty)
        local machine_op = value.ty:typecheck_tree_scalar_cast_op(self.op, ty)
        if machine_op == nil and self.op == C.SurfaceCast and type_eq(value.ty, ty) then
            machine_op = C.MachineCastIdentity
        end
        if machine_op ~= nil then
            return Check.TypeExprResult(Tr.ExprMachineCast(Tr.ExprTyped(ty), machine_op, ty, value.expr), ty, value.issues)
        end
        return Check.TypeExprResult(Tr.ExprCast(Tr.ExprTyped(ty), self.op, ty, value.expr), ty, value.issues)
    end

    function Tr.ExprSizeOf:typecheck_tree_expr(input)
        local ty = canonical_type(input.scope, self.ty)
        local result_ty = Ty.TScalar(C.ScalarIndex)
        return Check.TypeExprResult(Tr.ExprSizeOf(Tr.ExprTyped(result_ty), ty), result_ty, {})
    end

    function Tr.ExprCast:typecheck_tree_expr_expected(input)
        return self:typecheck_tree_expr(Check.TypeExprInput(input.scope))
    end

    function Tr.ExprMachineCast:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local ty = canonical_type(input.scope, self.ty)
        return Check.TypeExprResult(Tr.ExprMachineCast(Tr.ExprTyped(ty), self.op, ty, value.expr), ty, value.issues)
    end

    function Tr.ExprUnary:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, value.issues)
        local ty = self.op:typecheck_tree_unary_result(value.ty)
        if ty == nil then
            issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryInvalidOperator(tostring(self.op)), value.ty)
            ty = value.ty
        end
        return Check.TypeExprResult(Tr.ExprUnary(Tr.ExprTyped(ty), self.op, value.expr), ty, issues)
    end

    function Tr.ExprBinary:typecheck_tree_expr(input)
        local lhs = self.lhs:typecheck_tree_expr(input)
        local rhs = self.op:typecheck_tree_binary_rhs(self.rhs, input, lhs.ty)
        if lhs.ty:typecheck_tree_is_integer_scalar()
            and rhs.ty:typecheck_tree_is_integer_scalar()
            and rawget(rhs.expr, "value") ~= nil
            and asdl.isa(rawget(rhs.expr, "value"), C.Literal)
        then
            rhs = Check.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(lhs.ty), rhs.expr.value), lhs.ty, rhs.issues)
        end
        local issues = {}
        append_all(issues, lhs.issues)
        append_all(issues, rhs.issues)
        local ty = self.op:typecheck_tree_binary_result(lhs.ty, rhs.ty)
        if ty == nil then
            issues[#issues + 1] = Check.TypeIssueInvalidBinary(tostring(self.op), lhs.ty, rhs.ty)
            ty = lhs.ty
        end
        return Check.TypeExprResult(Tr.ExprBinary(Tr.ExprTyped(ty), self.op, lhs.expr, rhs.expr), ty, issues)
    end

    function Tr.ExprLogic:typecheck_tree_expr(input)
        local lhs = self.lhs:typecheck_tree_expr(input)
        local rhs = self.rhs:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, lhs.issues)
        append_all(issues, rhs.issues)
        local ty = self.op:typecheck_tree_logic_result(lhs.ty, rhs.ty)
        if ty == nil then
            issues[#issues + 1] = Check.TypeIssueInvalidLogic(tostring(self.op), lhs.ty, rhs.ty)
            ty = Ty.TScalar(C.ScalarBool)
        end
        return Check.TypeExprResult(Tr.ExprLogic(Tr.ExprTyped(ty), self.op, lhs.expr, rhs.expr), ty, issues)
    end

    local function type_conditional_expr(expr, input)
        local cond = expr.cond:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, Ty.TScalar(C.ScalarBool)))
        local then_expr = expr.then_expr:typecheck_tree_expr(input)
        local else_expr = expr.else_expr:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, then_expr.ty))
        local issues = {}
        append_all(issues, cond.issues)
        append_all(issues, then_expr.issues)
        append_all(issues, else_expr.issues)
        if not type_eq(then_expr.ty, else_expr.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("conditional branch", then_expr.ty, else_expr.ty)
        end
        return cond, then_expr, else_expr, issues
    end

    function Tr.ExprIf:typecheck_tree_expr(input)
        local cond, then_expr, else_expr, issues = type_conditional_expr(self, input)
        return Check.TypeExprResult(Tr.ExprIf(Tr.ExprTyped(then_expr.ty), cond.expr, then_expr.expr, else_expr.expr), then_expr.ty, issues)
    end

    function Tr.ExprSelect:typecheck_tree_expr(input)
        local cond, then_expr, else_expr, issues = type_conditional_expr(self, input)
        return Check.TypeExprResult(Tr.ExprSelect(Tr.ExprTyped(then_expr.ty), cond.expr, then_expr.expr, else_expr.expr), then_expr.ty, issues)
    end

    function Tr.ExprCompare:typecheck_tree_expr(input)
        local lhs = self.lhs:typecheck_tree_expr(input)
        local rhs = self.rhs:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, lhs.issues)
        append_all(issues, rhs.issues)
        if not type_eq(lhs.ty, rhs.ty) then issues[#issues + 1] = Check.TypeIssueInvalidCompare(tostring(self.op), lhs.ty, rhs.ty) end
        local ty = Ty.TScalar(C.ScalarBool)
        return Check.TypeExprResult(Tr.ExprCompare(Tr.ExprTyped(ty), self.op, lhs.expr, rhs.expr), ty, issues)
    end

    function Tr.ExprControl:typecheck_tree_expr(input)
        local stmt_input = Check.TypeStmtInput(input.scope, self.region.result_ty, Check.TypeYieldValue(self.region.result_ty))
        local region = self.region:typecheck_tree_control_expr_region(Check.TypeControlInput(stmt_input, self.region.region_id))
        return Check.TypeExprResult(Tr.ExprControl(Tr.ExprTyped(self.region.result_ty), region.region), self.region.result_ty, region.issues)
    end

    function Tr.ExprAddrOf:typecheck_tree_expr(input)
        local place = self.place:typecheck_tree_place(input.scope:typecheck_tree_place_input())
        local ty = Ty.TPtr(place.ty)
        return Check.TypeExprResult(Tr.ExprAddrOf(Tr.ExprTyped(ty), place.place), ty, place.issues)
    end

    function Tr.ExprDeref:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, value.issues)
        local ty = value.ty:typecheck_tree_deref_result()
        if ty == nil then
            issues[#issues + 1] = Check.TypeIssueNotPointer(value.ty)
            ty = void_ty()
        end
        return Check.TypeExprResult(Tr.ExprDeref(Tr.ExprTyped(ty), value.expr), ty, issues)
    end

    function Tr.ExprCall:typecheck_tree_expr(input)
        local callee = self.callee:typecheck_tree_expr(input)
        local result_ty, param_tys = callee.ty:typecheck_tree_callable_result()
        local issues = {}
        append_all(issues, callee.issues)
        if result_ty == nil then
            issues[#issues + 1] = Check.TypeIssueNotCallable(callee.ty)
            result_ty, param_tys = void_ty(), {}
        end
        if #self.args ~= #(param_tys or {}) then
            issues[#issues + 1] = Check.TypeIssueArgCount("call", #(param_tys or {}), #self.args)
        end
        local args = {}
        for i = 1, #self.args do
            local expected = param_tys and param_tys[i] or nil
            local arg = expected ~= nil
                and self.args[i]:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, expected))
                or self.args[i]:typecheck_tree_expr(input)
            append_all(issues, arg.issues)
            if expected ~= nil then
                if not type_eq(expected, arg.ty)
                    and not expected:typecheck_tree_arg_matches_actual(input.scope, arg.ty)
                then
                    issues[#issues + 1] = Check.TypeIssueExpected("call arg", expected, arg.ty)
                end
                expected:typecheck_tree_check_lease_call_argument(arg.ty, issues)
                expected:typecheck_tree_check_live_lease_invalidation(input.scope, arg.expr, issues)
            end
            args[#args + 1] = arg.expr
        end
        return Check.TypeExprResult(Tr.ExprCall(Tr.ExprTyped(result_ty), callee.expr, args), result_ty, issues)
    end

    local function typecheck_ctor_without_payload(lookup, expr)
        local issues = {}
        if #expr.args ~= 0 then issues[#issues + 1] = Check.TypeIssueArgCount("variant constructor", 0, #expr.args) end
        return Check.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(lookup.def.ty), expr.type_name, expr.variant_name, {}), lookup.def.ty, issues)
    end

    function Check.TypeVariantPayloadNone:typecheck_tree_ctor_payload(lookup, expr, input)
        return typecheck_ctor_without_payload(lookup, expr)
    end

    function Check.TypeVariantPayloadUnsupported:typecheck_tree_ctor_payload(lookup, expr, input)
        local issues = { Check.TypeIssueVariantPayloadUnsupported(lookup.def.type_name, expr.variant_name, self.field_count) }
        local args = {}
        for i = 1, #expr.args do
            local arg = expr.args[i]:typecheck_tree_expr(input.scope:typecheck_tree_expr_input())
            append_all(issues, arg.issues)
            args[i] = arg.expr
        end
        return Check.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(lookup.def.ty), expr.type_name, expr.variant_name, args), lookup.def.ty, issues)
    end

    function Check.TypeVariantPayloadFound:typecheck_tree_ctor_payload(lookup, expr, input)
        local payload_ty = canonical_type(input.scope, self.ty)
        local issues, args = {}, {}
        if #expr.args ~= 1 then issues[#issues + 1] = Check.TypeIssueArgCount("variant constructor", 1, #expr.args) end
        if #expr.args >= 1 then
            local arg = expr.args[1]:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, payload_ty))
            append_all(issues, arg.issues)
            if not type_eq(payload_ty, arg.ty) then issues[#issues + 1] = Check.TypeIssueExpected("variant payload", payload_ty, arg.ty) end
            args[1] = arg.expr
        end
        return Check.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(lookup.def.ty), expr.type_name, expr.variant_name, args), lookup.def.ty, issues)
    end

    function Check.TypeVariantCaseLookupFound:typecheck_tree_ctor(expr, input)
        return self.case:typecheck_tree_payload_lookup():typecheck_tree_ctor_payload(self, expr, input)
    end

    function Check.TypeVariantCaseLookupMissing:typecheck_tree_ctor(expr, input)
        local issues = { Check.TypeIssueUnknownVariant(self.type_name, self.variant_name) }
        if #expr.args ~= 0 then issues[#issues + 1] = Check.TypeIssueArgCount("variant constructor", 0, #expr.args) end
        return Check.TypeExprResult(Tr.ExprCtor(Tr.ExprTyped(self.ty), expr.type_name, expr.variant_name, {}), self.ty, issues)
    end

    function Tr.ExprCtor:typecheck_tree_expr(input)
        return input.scope.facts:typecheck_tree_lookup_variant_name(self.type_name)
            :typecheck_tree_lookup_variant_case(self.variant_name)
            :typecheck_tree_ctor(self, input)
    end

    function Tr.ExprLoad:typecheck_tree_expr(input)
        local addr = self.addr:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, Ty.TPtr(self.ty)))
        local issues = {}
        append_all(issues, addr.issues)
        if not type_eq(Ty.TPtr(self.ty), addr.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("load addr", Ty.TPtr(self.ty), addr.ty)
        end
        return Check.TypeExprResult(Tr.ExprLoad(Tr.ExprTyped(self.ty), self.ty, addr.expr), self.ty, issues)
    end

    function Tr.ExprAtomicLoad:typecheck_tree_expr(input)
        local addr = self.addr:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, Ty.TPtr(self.ty)))
        local issues = {}
        append_all(issues, addr.issues)
        if not type_eq(Ty.TPtr(self.ty), addr.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("atomic load addr", Ty.TPtr(self.ty), addr.ty)
        end
        return Check.TypeExprResult(Tr.ExprAtomicLoad(Tr.ExprTyped(self.ty), self.ty, addr.expr, self.ordering), self.ty, issues)
    end

    function Tr.ExprAtomicRmw:typecheck_tree_expr(input)
        local addr = self.addr:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, Ty.TPtr(self.ty)))
        local value = self.value:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, self.ty))
        local issues = {}
        append_all(issues, addr.issues)
        append_all(issues, value.issues)
        if not type_eq(Ty.TPtr(self.ty), addr.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("atomic rmw addr", Ty.TPtr(self.ty), addr.ty)
        end
        if not type_eq(self.ty, value.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("atomic rmw value", self.ty, value.ty)
        end
        return Check.TypeExprResult(Tr.ExprAtomicRmw(Tr.ExprTyped(self.ty), self.op, self.ty, addr.expr, value.expr, self.ordering), self.ty, issues)
    end

    function Tr.ExprAtomicCas:typecheck_tree_expr(input)
        local addr = self.addr:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, Ty.TPtr(self.ty)))
        local expected = self.expected:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, self.ty))
        local replacement = self.replacement:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, self.ty))
        local issues = {}
        append_all(issues, addr.issues)
        append_all(issues, expected.issues)
        append_all(issues, replacement.issues)
        if not type_eq(Ty.TPtr(self.ty), addr.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("atomic cas addr", Ty.TPtr(self.ty), addr.ty)
        end
        if not type_eq(self.ty, expected.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("atomic cas expected", self.ty, expected.ty)
        end
        if not type_eq(self.ty, replacement.ty) then
            issues[#issues + 1] = Check.TypeIssueExpected("atomic cas replacement", self.ty, replacement.ty)
        end
        return Check.TypeExprResult(Tr.ExprAtomicCas(Tr.ExprTyped(self.ty), self.ty, addr.expr, expected.expr, replacement.expr, self.ordering), self.ty, issues)
    end

    function Tr.ExprLen:typecheck_tree_expr(input)
        local value = self.value:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, value.issues)
        local ty = value.ty:typecheck_tree_len_result()
        if ty == nil then
            issues[#issues + 1] = Check.TypeIssueNotIndexable(value.ty)
            ty = Ty.TScalar(C.ScalarIndex)
        end
        return Check.TypeExprResult(Tr.ExprLen(Tr.ExprTyped(ty), value.expr), ty, issues)
    end

    function Tr.IndexBase:typecheck_tree_index_base()
        return Check.TypeIndexBaseResult(self, void_ty(), { Check.TypeIssueNotIndexable(void_ty()) })
    end

    function Tr.IndexBaseExpr:typecheck_tree_index_base(input)
        local base = self.base:typecheck_tree_expr(Check.TypeExprInput(input.scope))
        local issues = {}
        append_all(issues, base.issues)
        local elem = base.ty:typecheck_tree_index_elem()
        if elem == nil then
            issues[#issues + 1] = Check.TypeIssueNotIndexable(base.ty)
            elem = void_ty()
        end
        return Check.TypeIndexBaseResult(Tr.IndexBaseExpr(base.expr), elem, issues)
    end

    function Tr.IndexBasePlace:typecheck_tree_index_base(input)
        local place = self.base:typecheck_tree_place(Check.TypePlaceInput(input.scope))
        local elem = place.ty:typecheck_tree_index_elem() or self.elem
        local issues = {}
        append_all(issues, place.issues)
        if elem == nil then
            issues[#issues + 1] = Check.TypeIssueNotIndexable(place.ty)
            elem = void_ty()
        end
        return Check.TypeIndexBaseResult(Tr.IndexBasePlace(place.place, elem), elem, issues)
    end

    function Tr.IndexBaseView:typecheck_tree_index_base(input)
        local view = self.view:typecheck_tree_view(Check.TypeViewInput(input.scope))
        local elem = view.view:typecheck_tree_elem()
        return Check.TypeIndexBaseResult(Tr.IndexBaseView(view.view), elem, view.issues)
    end

    function Tr.ExprIndex:typecheck_tree_expr(input)
        local base = self.base:typecheck_tree_index_base(Check.TypeIndexBaseInput(input.scope))
        local index = self.index:typecheck_tree_expr(input)
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, index.issues)
        if not index.ty:typecheck_tree_is_integer_scalar() then
            issues[#issues + 1] = Check.TypeIssueExpected("index", Ty.TScalar(C.ScalarIndex), index.ty)
        end
        return Check.TypeExprResult(Tr.ExprIndex(Tr.ExprTyped(base.elem), base.base, index.expr), base.elem, issues)
    end

    function Tr.PlaceRef:typecheck_tree_place(input)
        local ref_result = self.ref:typecheck_tree_ref(Check.TypeValueRefInput(input.scope))
        return Check.TypePlaceResult(Tr.PlaceRef(Tr.PlaceTyped(ref_result.ty), ref_result.ref), ref_result.ty, ref_result.issues)
    end

    function Tr.PlaceDeref:typecheck_tree_place(input)
        local base = self.base:typecheck_tree_expr(Check.TypeExprInput(input.scope))
        local issues = {}
        append_all(issues, base.issues)
        local ty = base.ty:typecheck_tree_deref_result()
        if ty == nil then
            issues[#issues + 1] = Check.TypeIssueNotPointer(base.ty)
            ty = void_ty()
        end
        return Check.TypePlaceResult(Tr.PlaceDeref(Tr.PlaceTyped(ty), base.expr), ty, issues)
    end

    function Tr.PlaceDot:typecheck_tree_place(input)
        local base = self.base:typecheck_tree_place(input)
        local typed_ty = self.h:typecheck_tree_typed_ty()
        local field = field_layout_for(input.scope, base.ty, self.name)
        if field ~= nil then
            local ref = Sem.FieldByName(field.field_name, field.ty)
            return Check.TypePlaceResult(Tr.PlaceField(Tr.PlaceTyped(field.ty), base.place, ref), field.ty, base.issues)
        end
        if typed_ty ~= nil then return Check.TypePlaceResult(Tr.PlaceDot(Tr.PlaceTyped(typed_ty), base.place, self.name), typed_ty, base.issues) end
        return Check.TypePlaceResult(Tr.PlaceDot(Tr.PlaceTyped(void_ty()), base.place, self.name), void_ty(), base.issues)
    end

    function Tr.PlaceIndex:typecheck_tree_place(input)
        local base = self.base:typecheck_tree_index_base(Check.TypeIndexBaseInput(input.scope))
        local index = self.index:typecheck_tree_expr(Check.TypeExprInput(input.scope))
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, index.issues)
        if not index.ty:typecheck_tree_is_integer_scalar() then
            issues[#issues + 1] = Check.TypeIssueExpected("index", Ty.TScalar(C.ScalarIndex), index.ty)
        end
        return Check.TypePlaceResult(Tr.PlaceIndex(Tr.PlaceTyped(base.elem), base.base, index.expr), base.elem, issues)
    end

    function Tr.Expr:typecheck_tree_expr_expected(input)
        local result = self:typecheck_tree_expr(Check.TypeExprInput(input.scope))
        if input.expected ~= nil
            and result.ty:typecheck_tree_is_integer_scalar()
            and input.expected:typecheck_tree_is_integer_scalar()
            and asdl.classof(result.expr) == Tr.ExprLit
        then
            return Check.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(input.expected), result.expr.value), input.expected, result.issues)
        end
        return result
    end

    function Tr.ExprAgg:typecheck_tree_expr_expected(input)
        return input.expected:typecheck_tree_expr_agg_expected(self, input)
    end

    function Tr.ExprAgg:typecheck_tree_expr(input)
        local ty = canonical_type(input.scope, self.ty)
        local fields = {}
        local issues = {}
        for i = 1, #(self.fields or {}) do
            local field = self.fields[i]
            local value = field.value:typecheck_tree_expr(Check.TypeExprInput(input.scope))
            append_all(issues, value.issues)
            value.ty:typecheck_tree_append_lease_escape(issues, Check.TypeUnaryLeaseEscapeAggregate)
            fields[#fields + 1] = Tr.FieldInit(field.name, value.expr, field.offset)
        end
        return Check.TypeExprResult(Tr.ExprAgg(Tr.ExprTyped(ty), ty, fields), ty, issues)
    end

    function Ty.Type:typecheck_tree_expr_agg_expected(expr, input)
        return expr:typecheck_tree_expr(Check.TypeExprInput(input.scope))
    end

    function Ty.TNamed:typecheck_tree_expr_agg_expected(expr, input)
        return Tr.ExprAgg(Tr.ExprSurface, self, expr.fields):typecheck_tree_expr(Check.TypeExprInput(input.scope))
    end

    function Ty.TClosure:typecheck_tree_expr_agg_expected(expr, input)
        return Tr.ExprAgg(Tr.ExprSurface, self, expr.fields):typecheck_tree_expr(Check.TypeExprInput(input.scope))
    end

    function Tr.ExprArray:typecheck_tree_expr_expected(input)
        return input.expected:typecheck_tree_expr_array_expected(self, input)
    end

    function Ty.Type:typecheck_tree_expr_array_expected(expr, input)
        return expr:typecheck_tree_expr(Check.TypeExprInput(input.scope))
    end

    function Ty.TArray:typecheck_tree_expr_array_expected(expr, input)
        local expected_count = self.count:typecheck_tree_const_count()
        local issues = {}
        if expected_count ~= nil and expected_count ~= #expr.elems then
            issues[#issues + 1] = Check.TypeIssueExpected("array length", self, Ty.TArray(Ty.ArrayLenConst(#expr.elems), self.elem))
        end
        local elems = {}
        for i = 1, #expr.elems do
            local elem_result = expr.elems[i]:typecheck_tree_expr_expected(Check.TypeExpectedExprInput(input.scope, self.elem))
            for j = 1, #elem_result.issues do issues[#issues + 1] = elem_result.issues[j] end
            if elem_result.ty ~= self.elem then issues[#issues + 1] = Check.TypeIssueExpected("array elem", self.elem, elem_result.ty) end
            elems[#elems + 1] = elem_result.expr
        end
        local ty = Ty.TArray(Ty.ArrayLenConst(#elems), self.elem)
        return Check.TypeExprResult(Tr.ExprArray(Tr.ExprTyped(ty), self.elem, elems), ty, issues)
    end
end
