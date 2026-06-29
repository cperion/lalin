return function(T)
    local C = T.LalinCore
    local B = T.LalinBind
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local function void_ty()
        return Ty.TScalar(C.ScalarVoid)
    end

    function Tr.TypeValueScope:typecheck_lookup_value(name)
        for i = #self.values, 1, -1 do
            if self.values[i].name == name then return self.values[i].binding end
        end
        return nil
    end

    function Tr.TypeValueScope:typecheck_with_value(entry)
        local values = {}
        for i = 1, #self.values do values[i] = self.values[i] end
        values[#values + 1] = entry
        return Tr.TypeValueScope(self.module_name, values, self.types, self.layouts, self.facts)
    end

    function B.ValueRefBinding:typecheck_tree_ref()
        return Tr.TypeValueRefResult(self, self.binding.ty, {})
    end

    function B.ValueRefName:typecheck_tree_ref(input)
        local binding = input.scope:typecheck_lookup_value(self.name)
        if binding ~= nil then return B.ValueRefBinding(binding):typecheck_tree_ref() end
        return Tr.TypeValueRefResult(self, void_ty(), { Tr.TypeIssueUnresolvedValue(self.name) })
    end

    function B.ValueRefPath:typecheck_tree_ref()
        return Tr.TypeValueRefResult(self, void_ty(), { Tr.TypeIssueUnresolvedPath(self.path) })
    end

    function Tr.ExprLit:typecheck_tree_expr()
        local ty = self.value:typecheck_tree_literal()
        return Tr.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(ty), self.value), ty, {})
    end

    function Tr.ExprLit:typecheck_tree_expr_expected(input)
        local ty = self.value:typecheck_tree_literal_expected(input.expected)
        return Tr.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(ty), self.value), ty, {})
    end

    function Tr.ExprRef:typecheck_tree_expr(input)
        local ref_result = self.ref:typecheck_tree_ref(Tr.TypeValueRefInput(input.scope))
        return Tr.TypeExprResult(Tr.ExprRef(Tr.ExprTyped(ref_result.ty), ref_result.ref), ref_result.ty, ref_result.issues)
    end

    function Tr.Expr:typecheck_tree_expr_expected(input)
        return self:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Tr.ExprAgg:typecheck_tree_expr_expected(input)
        return input.expected:typecheck_tree_expr_agg_expected(self, input)
    end

    function Ty.Type:typecheck_tree_expr_agg_expected(expr, input)
        return expr:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Ty.TNamed:typecheck_tree_expr_agg_expected(expr, input)
        return Tr.ExprAgg(Tr.ExprSurface, self, expr.fields):typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Tr.ExprArray:typecheck_tree_expr_expected(input)
        return input.expected:typecheck_tree_expr_array_expected(self, input)
    end

    function Ty.Type:typecheck_tree_expr_array_expected(expr, input)
        return expr:typecheck_tree_expr(Tr.TypeExprInput(input.scope))
    end

    function Ty.TArray:typecheck_tree_expr_array_expected(expr, input)
        local expected_count = self.count:typecheck_tree_const_count()
        local issues = {}
        if expected_count ~= nil and expected_count ~= #expr.elems then
            issues[#issues + 1] = Tr.TypeIssueExpected("array length", self, Ty.TArray(Ty.ArrayLenConst(#expr.elems), self.elem))
        end
        local elems = {}
        for i = 1, #expr.elems do
            local elem_result = expr.elems[i]:typecheck_tree_expr_expected(Tr.TypeExpectedExprInput(input.scope, self.elem))
            for j = 1, #elem_result.issues do issues[#issues + 1] = elem_result.issues[j] end
            if elem_result.ty ~= self.elem then issues[#issues + 1] = Tr.TypeIssueExpected("array elem", self.elem, elem_result.ty) end
            elems[#elems + 1] = elem_result.expr
        end
        local ty = Ty.TArray(Ty.ArrayLenConst(#elems), self.elem)
        return Tr.TypeExprResult(Tr.ExprArray(Tr.ExprTyped(ty), self.elem, elems), ty, issues)
    end
end
