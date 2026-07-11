return function(T)
    local asdl = require("lalin.asdl")
    local C = T.LalinCore
    local B = T.LalinBind
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local Check = T.LalinCheck
    local function append_all(out, values)
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    end

    local function type_eq(a, b)
        return a == b
    end


    local function check_expected(site, expected, actual, issues, scope)
        if not type_eq(expected, actual) and not expected:typecheck_tree_arg_matches_actual(scope, actual) then
            issues[#issues + 1] = Check.TypeIssueExpected(site, expected, actual)
        end
    end

    local function type_expr_expect(expr, input, expected)
        return expr:typecheck_tree_expr_expected(input:typecheck_tree_expected_expr_input(expected))
    end

    local function block_param_binding(region_id, label, param, index, role)
        return B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, role)
    end

    local function path_text(path)
        local parts = {}
        for i, p in ipairs((path and path.parts) or {}) do parts[#parts + 1] = p.text end
        return table.concat(parts, ".")
    end

    function Tr.RegionInvokeTarget:typecheck_tree_same_region_target(other)
        return path_text(self.path) == path_text(other and other.path)
    end

    function Check.TypeModuleFacts:typecheck_tree_region_def_for(target)
        for i = 1, #(self.regions or {}) do
            if self.regions[i].target:typecheck_tree_same_region_target(target) then return self.regions[i] end
        end
        return nil
    end

    local function prefixed_label(invoke_id, label)
        return Tr.BlockLabel(tostring(invoke_id) .. "." .. tostring(label.name))
    end

    local function cont_name_eq(a, b)
        return a ~= nil and b ~= nil and a.name == b.name
    end

    function Tr.RegionContWire:typecheck_tree_wire_names_cont(cont)
        return self.name == cont.name
    end

    local function expr_ref_name(expr)
        if expr == nil or asdl.classof(expr) ~= Tr.ExprRef then return nil end
        local ref = expr.ref
        if ref ~= nil and ref.name ~= nil then return ref.name end
        return nil
    end

    local function substituted_wire_args(explicit, source_args)
        if #(explicit or {}) == 0 then return source_args end
        local by_name = {}
        for i, arg in ipairs(source_args or {}) do by_name[arg.name] = arg.value end
        local out = {}
        for i, arg in ipairs(explicit or {}) do
            local ref_name = expr_ref_name(arg.value)
            if ref_name ~= nil and by_name[ref_name] ~= nil then out[i] = Tr.JumpArg(arg.name, by_name[ref_name])
            else out[i] = arg end
        end
        return out
    end

    function Tr.RegionWireBlock:typecheck_tree_region_invoke_jump(args)
        return Tr.StmtJump(Tr.StmtSurface, self.label, substituted_wire_args(self.args or {}, args))
    end

    function Tr.RegionWireCont:typecheck_tree_region_invoke_jump(args)
        return Tr.StmtJumpCont(Tr.StmtSurface, self.cont, substituted_wire_args(self.args or {}, args))
    end

    local function find_wire(wiring, cont)
        for i = 1, #(wiring or {}) do
            if wiring[i]:typecheck_tree_wire_names_cont(cont) then return wiring[i] end
        end
        return nil
    end

    local function find_cont(conts, name)
        for i = 1, #(conts or {}) do if conts[i].name == name then return conts[i] end end
        return nil
    end

    local clone_stmt_for_region_invoke
    local clone_stmt_list_for_region_invoke

    function Tr.Stmt:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return self
    end

    local function invoke_local_binding(invoke_id, binding)
        if binding == nil then return binding end
        return B.Binding(C.Id("region-invoke:" .. tostring(invoke_id) .. ":" .. tostring(binding.id and binding.id.text or binding.name)), binding.name, binding.ty, binding.role)
    end

    function Tr.StmtLet:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.StmtLet(self.h, invoke_local_binding(invoke_id, self.binding), self.init)
    end

    function Tr.StmtVar:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.StmtVar(self.h, invoke_local_binding(invoke_id, self.binding), self.init)
    end

    function Tr.StmtJump:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.StmtJump(self.h, prefixed_label(invoke_id, self.target), self.args)
    end

    function Tr.StmtJumpCont:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        local wire = find_wire(wiring, self.cont)
        if wire == nil then return self end
        return wire.target:typecheck_tree_region_invoke_jump(self.args)
    end

    function Tr.StmtIf:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.StmtIf(self.h, self.cond,
            clone_stmt_list_for_region_invoke(self.then_body, invoke_id, wiring),
            clone_stmt_list_for_region_invoke(self.else_body, invoke_id, wiring))
    end

    function Tr.StmtSwitch:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        local arms, variant_arms, default_body = {}, {}, clone_stmt_list_for_region_invoke(self.default_body or {}, invoke_id, wiring)
        for i = 1, #(self.arms or {}) do
            arms[i] = Tr.SwitchStmtArm(self.arms[i].key, clone_stmt_list_for_region_invoke(self.arms[i].body, invoke_id, wiring))
        end
        for i = 1, #(self.variant_arms or {}) do
            variant_arms[i] = Tr.SwitchVariantStmtArm(self.variant_arms[i].variant_name, self.variant_arms[i].binds, clone_stmt_list_for_region_invoke(self.variant_arms[i].body, invoke_id, wiring))
        end
        return Tr.StmtSwitch(self.h, self.value, arms, variant_arms, default_body)
    end

    function Tr.RegionWireTarget:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return self
    end

    function Tr.RegionWireBlock:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.RegionWireBlock(prefixed_label(invoke_id, self.label), self.args)
    end

    function Tr.RegionWireCont:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        local wire = find_wire(wiring, self.cont)
        if wire ~= nil then return wire.target end
        return self
    end

    function Tr.RegionContWire:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.RegionContWire(self.name, self.target:typecheck_tree_region_invoke_clone(invoke_id, wiring))
    end

    local function clone_wiring_for_region_invoke(nested_wiring, invoke_id, wiring)
        local out = {}
        for i = 1, #(nested_wiring or {}) do out[i] = nested_wiring[i]:typecheck_tree_region_invoke_clone(invoke_id, wiring) end
        return out
    end

    function Tr.StmtRegionCall:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.StmtRegionCall(self.h, tostring(invoke_id) .. "." .. tostring(self.invoke_id), self.target, self.args, clone_wiring_for_region_invoke(self.wiring, invoke_id, wiring))
    end

    function Tr.StmtRegionEmit:typecheck_tree_region_invoke_clone(invoke_id, wiring)
        return Tr.StmtRegionEmit(self.h, tostring(invoke_id) .. "." .. tostring(self.invoke_id), self.target, self.args, clone_wiring_for_region_invoke(self.wiring, invoke_id, wiring))
    end

    clone_stmt_for_region_invoke = function(stmt, invoke_id, wiring)
        return stmt:typecheck_tree_region_invoke_clone(invoke_id, wiring)
    end

    clone_stmt_list_for_region_invoke = function(stmts, invoke_id, wiring)
        local out = {}
        for i = 1, #(stmts or {}) do out[i] = clone_stmt_for_region_invoke(stmts[i], invoke_id, wiring) end
        return out
    end

    function Tr.EntryBlockParam:typecheck_tree_add_to_scope(input, region_id, label, index)
        local ty = self.ty:typecheck_tree_canonical(input.scope)
        local init = type_expr_expect(self.init, input, ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("entry param", ty, init.ty, issues)
        local param = Tr.EntryBlockParam(self.name, ty, init.expr)
        local binding = block_param_binding(region_id, label, param, index, B.BindingRoleEntryBlockParam(region_id, label.name, index))
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.name, binding))
        return input:typecheck_tree_with_scope(scope), param, issues
    end

    function Tr.BlockParam:typecheck_tree_add_to_scope(input, region_id, label, index)
        local param = Tr.BlockParam(self.name, self.ty:typecheck_tree_canonical(input.scope))
        local binding = block_param_binding(region_id, label, param, index, B.BindingRoleBlockParam(region_id, label.name, index))
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.name, binding))
        return input:typecheck_tree_with_scope(scope), param, {}
    end

    function Tr.JumpArg:typecheck_tree_jump_arg(input)
        local value = self.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.JumpArg(self.name, value.expr), value.issues
    end

    function Tr.StmtReturnValue:typecheck_tree_stmt(input)
        local value = type_expr_expect(self.value, input, input.return_ty)
        if (input.return_ty:typecheck_tree_accept_nil_literal() or asdl.classof(input.return_ty) == Ty.TPtr)
            and type_eq(value.ty, Ty.TScalar(C.ScalarVoid))
            and asdl.classof(value.expr) == Tr.ExprLit
            and asdl.isa(value.expr.value, C.LitNil)
        then
            value = Check.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(input.return_ty), value.expr.value), input.return_ty, value.issues)
        end
        local issues = {}
        append_all(issues, value.issues)
        check_expected("return", input.return_ty, value.ty, issues, input.scope)
        value.ty:typecheck_tree_append_lease_escape(issues, Check.TypeUnaryLeaseEscapeReturn)
        return Check.TypeStmtResult(input, { Tr.StmtReturnValue(self.h, value.expr) }, issues)
    end

    function Tr.StmtReturnVoid:typecheck_tree_stmt(input)
        local issues = {}
        check_expected("return", input.return_ty, Ty.TScalar(C.ScalarVoid), issues)
        return Check.TypeStmtResult(input, { Tr.StmtReturnVoid(self.h) }, issues)
    end

    function Tr.StmtExpr:typecheck_tree_stmt(input)
        local expr = self.expr:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Check.TypeStmtResult(input, { Tr.StmtExpr(self.h, expr.expr) }, expr.issues)
    end

    function Tr.StmtLet:typecheck_tree_stmt(input)
        local ty = self.binding.ty:typecheck_tree_canonical(input.scope)
        local binding = B.Binding(self.binding.id, self.binding.name, ty, self.binding.role)
        local init = type_expr_expect(self.init, input, ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("let", ty, init.ty, issues)
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(binding.name, binding))
        return Check.TypeStmtResult(input:typecheck_tree_with_scope(scope), { Tr.StmtLet(self.h, binding, init.expr) }, issues)
    end

    function Tr.StmtVar:typecheck_tree_stmt(input)
        local ty = self.binding.ty:typecheck_tree_canonical(input.scope)
        local binding = B.Binding(self.binding.id, self.binding.name, ty, self.binding.role)
        local init = type_expr_expect(self.init, input, ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("var", ty, init.ty, issues)
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(binding.name, binding))
        return Check.TypeStmtResult(input:typecheck_tree_with_scope(scope), { Tr.StmtVar(self.h, binding, init.expr) }, issues)
    end

    function Tr.Place:typecheck_tree_check_store_escape(value_ty, issues) end
    function Tr.PlaceRef:typecheck_tree_check_store_escape(value_ty, issues) end
    function Tr.PlaceDeref:typecheck_tree_check_store_escape(value_ty, issues)
        value_ty:typecheck_tree_append_lease_escape(issues, Check.TypeUnaryLeaseEscapeStore)
    end
    function Tr.PlaceDot:typecheck_tree_check_store_escape(value_ty, issues)
        value_ty:typecheck_tree_append_lease_escape(issues, Check.TypeUnaryLeaseEscapeStore)
    end
    function Tr.PlaceField:typecheck_tree_check_store_escape(value_ty, issues)
        value_ty:typecheck_tree_append_lease_escape(issues, Check.TypeUnaryLeaseEscapeStore)
    end
    function Tr.PlaceIndex:typecheck_tree_check_store_escape(value_ty, issues)
        value_ty:typecheck_tree_append_lease_escape(issues, Check.TypeUnaryLeaseEscapeStore)
    end

    function Tr.StmtSet:typecheck_tree_stmt(input)
        local place = self.place:typecheck_tree_place(input:typecheck_tree_place_input())
        local value = type_expr_expect(self.value, input, place.ty)
        local issues = {}
        append_all(issues, place.issues)
        append_all(issues, value.issues)
        check_expected("set", place.ty, value.ty, issues, input.scope)
        place.place:typecheck_tree_check_store_escape(value.ty, issues)
        return Check.TypeStmtResult(input, { Tr.StmtSet(self.h, place.place, value.expr) }, issues)
    end

    function Tr.StmtAtomicStore:typecheck_tree_stmt(input)
        local addr = self.addr:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local value = type_expr_expect(self.value, input, self.ty)
        local issues = {}
        append_all(issues, addr.issues)
        append_all(issues, value.issues)
        check_expected("atomic store", self.ty, value.ty, issues, input.scope)
        value.ty:typecheck_tree_append_lease_escape(issues, Check.TypeUnaryLeaseEscapeStore)
        return Check.TypeStmtResult(input, { Tr.StmtAtomicStore(self.h, self.ty, addr.expr, value.expr, self.ordering) }, issues)
    end

    function Tr.StmtAtomicFence:typecheck_tree_stmt(input)
        return Check.TypeStmtResult(input, { self }, {})
    end

    function Tr.StmtIf:typecheck_tree_stmt(input)
        local cond = type_expr_expect(self.cond, input, Ty.TScalar(C.ScalarBool))
        local issues = {}
        append_all(issues, cond.issues)
        check_expected("if condition", Ty.TScalar(C.ScalarBool), cond.ty, issues)
        local then_body = input:typecheck_tree_stmt_body(self.then_body)
        local else_body = input:typecheck_tree_stmt_body(self.else_body)
        append_all(issues, then_body.issues)
        append_all(issues, else_body.issues)
        return Check.TypeStmtResult(input, { Tr.StmtIf(self.h, cond.expr, then_body.stmts, else_body.stmts) }, issues)
    end

    function Tr.StmtAssert:typecheck_tree_stmt(input)
        local cond = type_expr_expect(self.cond, input, Ty.TScalar(C.ScalarBool))
        local issues = {}
        append_all(issues, cond.issues)
        check_expected("assert condition", Ty.TScalar(C.ScalarBool), cond.ty, issues)
        return Check.TypeStmtResult(input, { Tr.StmtAssert(self.h, cond.expr) }, issues)
    end

    function Tr.SwitchStmtArm:typecheck_tree_stmt_arm(input)
        local body = input:typecheck_tree_stmt_body(self.body)
        return Tr.SwitchStmtArm(self.key, body.stmts), body.issues
    end


    function Tr.SwitchVariantStmtArm:typecheck_tree_stmt_arm(input)
        local scope = input.scope
        for i, bind in ipairs(self.binds or {}) do
            local b = B.Binding(C.Id("variant:stmt_switch:" .. tostring(self.variant_name) .. ":" .. tostring(bind.name)), bind.name, bind.ty, B.BindingRoleLocalValue)
            scope = scope:typecheck_tree_add_value(B.ValueEntry(bind.name, b))
        end
        local body = input:typecheck_tree_with_scope(scope):typecheck_tree_stmt_body(self.body)
        return Tr.SwitchVariantStmtArm(self.variant_name, self.binds, body.stmts), body.issues
    end

    function Tr.StmtSwitch:typecheck_tree_stmt(input)
        local value = self.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, value.issues)
        local arms = {}
        for i = 1, #(self.arms or {}) do
            local arm, arm_issues = self.arms[i]:typecheck_tree_stmt_arm(input)
            arms[#arms + 1] = arm
            append_all(issues, arm_issues)
        end
        local variant_arms = {}
        for i = 1, #(self.variant_arms or {}) do
            local arm, arm_issues = self.variant_arms[i]:typecheck_tree_stmt_arm(input)
            variant_arms[#variant_arms + 1] = arm
            append_all(issues, arm_issues)
        end
        local default_body = input:typecheck_tree_stmt_body(self.default_body)
        append_all(issues, default_body.issues)
        return Check.TypeStmtResult(input, { Tr.StmtSwitch(self.h, value.expr, arms, variant_arms, default_body.stmts) }, issues)
    end

    local function typecheck_source_variant_arm(lookup, source_arm, input, expected_binds, typed_binds)
        local issues = {}
        if #source_arm.binds ~= expected_binds then
            issues[#issues + 1] = Check.TypeIssueVariantBindCount(lookup.def.type_name, source_arm.variant_name, expected_binds, #source_arm.binds)
        end
        local typed_source_arm = Tr.SwitchVariantStmtArm(source_arm.variant_name, typed_binds, source_arm.body)
        local arm, arm_issues = typed_source_arm:typecheck_tree_stmt_arm(input)
        append_all(issues, arm_issues)
        return Check.TypeVariantArmResult(arm, issues)
    end

    function Check.TypeVariantPayloadNone:typecheck_tree_source_variant_arm(lookup, source_arm, input)
        return typecheck_source_variant_arm(lookup, source_arm, input, 0, {})
    end

    function Check.TypeVariantPayloadUnsupported:typecheck_tree_source_variant_arm(lookup, source_arm, input)
        local issues = { Check.TypeIssueVariantPayloadUnsupported(lookup.def.type_name, source_arm.variant_name, self.field_count) }
        local typed_source_arm = Tr.SwitchVariantStmtArm(source_arm.variant_name, {}, source_arm.body)
        local arm, arm_issues = typed_source_arm:typecheck_tree_stmt_arm(input)
        append_all(issues, arm_issues)
        return Check.TypeVariantArmResult(arm, issues)
    end

    function Check.TypeVariantPayloadFound:typecheck_tree_source_variant_arm(lookup, source_arm, input)
        local binds = {}
        if source_arm.binds[1] ~= nil then binds[1] = Tr.VariantBind(source_arm.binds[1], self.ty) end
        return typecheck_source_variant_arm(lookup, source_arm, input, 1, binds)
    end

    function Check.TypeVariantCaseLookupFound:typecheck_tree_source_variant_arm(source_arm, input)
        return self.case:typecheck_tree_payload_lookup():typecheck_tree_source_variant_arm(self, source_arm, input)
    end

    function Check.TypeVariantCaseLookupMissing:typecheck_tree_source_variant_arm(source_arm, input)
        local issues = { Check.TypeIssueUnknownVariant(self.type_name, source_arm.variant_name) }
        if #source_arm.binds ~= 0 then
            issues[#issues + 1] = Check.TypeIssueVariantBindCount(self.type_name, source_arm.variant_name, 0, #source_arm.binds)
        end
        local typed_source_arm = Tr.SwitchVariantStmtArm(source_arm.variant_name, {}, source_arm.body)
        local arm, arm_issues = typed_source_arm:typecheck_tree_stmt_arm(input)
        append_all(issues, arm_issues)
        return Check.TypeVariantArmResult(arm, issues)
    end

    function Tr.StmtVariantSwitchSource:typecheck_tree_stmt(input)
        local value = self.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, value.issues)
        local arms = {}
        for i = 1, #self.arms do
            local arm, arm_issues = self.arms[i]:typecheck_tree_stmt_arm(input)
            arms[#arms + 1] = arm
            append_all(issues, arm_issues)
        end
        local variant_arms = {}
        local variant_lookup = value.ty:typecheck_tree_lookup_variant(input.scope.facts)
        for i = 1, #self.variant_arms do
            local source_arm = self.variant_arms[i]
            local arm_result = variant_lookup:typecheck_tree_lookup_variant_case(source_arm.variant_name)
                :typecheck_tree_source_variant_arm(source_arm, input)
            variant_arms[#variant_arms + 1] = arm_result.arm
            append_all(issues, arm_result.issues)
        end
        local default_body = input:typecheck_tree_stmt_body(self.default_body)
        append_all(issues, default_body.issues)
        return Check.TypeStmtResult(input, { Tr.StmtSwitch(self.h, value.expr, arms, variant_arms, default_body.stmts) }, issues)
    end

    function Tr.StmtJump:typecheck_tree_stmt(input)
        local args = {}
        local issues = {}
        for i = 1, #(self.args or {}) do
            local arg, arg_issues = self.args[i]:typecheck_tree_jump_arg(input)
            args[#args + 1] = arg
            append_all(issues, arg_issues)
        end
        return Check.TypeStmtResult(input, { Tr.StmtJump(self.h, self.target, args) }, issues)
    end

    function Tr.StmtJumpCont:typecheck_tree_stmt(input)
        local args = {}
        local issues = {}
        for i = 1, #(self.args or {}) do
            local arg, arg_issues = self.args[i]:typecheck_tree_jump_arg(input)
            args[#args + 1] = arg
            append_all(issues, arg_issues)
        end
        return Check.TypeStmtResult(input, { Tr.StmtJumpCont(self.h, self.cont, args) }, issues)
    end

    local function typecheck_region_invoke_args(stmt, input)
        local args = {}
        local issues = {}
        for i = 1, #(stmt.args or {}) do
            local arg = stmt.args[i]:typecheck_tree_expr(input:typecheck_tree_expr_input())
            args[#args + 1] = arg.expr
            append_all(issues, arg.issues)
        end
        return args, issues
    end

    function Tr.RegionWireTarget:typecheck_tree_wire_target(input)
        return self, {}
    end

    local function typecheck_wire_args(args, input)
        local out, issues = {}, {}
        for i, arg in ipairs(args or {}) do
            local value = arg.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
            out[i] = Tr.JumpArg(arg.name, value.expr)
            append_all(issues, value.issues)
        end
        return out, issues
    end

    function Tr.RegionWireBlock:typecheck_tree_wire_target(input)
        local args, issues = typecheck_wire_args(self.args or {}, input)
        return Tr.RegionWireBlock(self.label, args), issues
    end

    function Tr.RegionWireCont:typecheck_tree_wire_target(input)
        local args, issues = typecheck_wire_args(self.args or {}, input)
        return Tr.RegionWireCont(self.cont, args), issues
    end

    function Tr.RegionContWire:typecheck_tree_wire(input)
        local target, issues = self.target:typecheck_tree_wire_target(input)
        return Tr.RegionContWire(self.name, target), issues
    end

    local function typecheck_region_wiring(wiring, input)
        local out, issues = {}, {}
        for i, wire in ipairs(wiring or {}) do
            local typed, wire_issues = wire:typecheck_tree_wire(input)
            out[i] = typed
            append_all(issues, wire_issues)
        end
        return out, issues
    end

    function Tr.StmtRegionEmit:typecheck_tree_stmt(input)
        local args, issues = typecheck_region_invoke_args(self, input)
        local wiring, wire_issues = typecheck_region_wiring(self.wiring, input)
        append_all(issues, wire_issues)
        return Check.TypeStmtResult(input, { Tr.StmtRegionEmit(self.h, self.invoke_id, self.target, args, wiring) }, issues)
    end

    function Tr.StmtRegionCall:typecheck_tree_stmt(input)
        local args, issues = typecheck_region_invoke_args(self, input)
        local wiring, wire_issues = typecheck_region_wiring(self.wiring, input)
        append_all(issues, wire_issues)
        return Check.TypeStmtResult(input, { Tr.StmtRegionCall(self.h, self.invoke_id, self.target, args, wiring) }, issues)
    end

    local function entry_param_from_region_param(param, arg)
        return Tr.BlockParam(param.name, param.ty), Tr.JumpArg(param.name, arg)
    end

    local function entry_param_from_entry_param(param)
        return Tr.BlockParam(param.name, param.ty), Tr.JumpArg(param.name, param.init)
    end

    function Tr.StmtRegionEmit:typecheck_tree_expand_region_invoke(input)
        local def = input.scope.facts:typecheck_tree_region_def_for(self.target)
        if def == nil then return Tr.RegionInvokeRejected(Tr.RegionInvokeMissingTarget(self.target)) end
        local region = def.region
        if #(region.params or {}) ~= #(self.args or {}) then
            return Tr.RegionInvokeRejected(Tr.RegionInvokeArgCount(self.target, #(region.params or {}), #(self.args or {})))
        end
        for i = 1, #(self.wiring or {}) do
            if find_cont(region.conts or {}, self.wiring[i].name) == nil then
                return Tr.RegionInvokeRejected(Tr.RegionInvokeExtraWire(self.target, self.wiring[i].name))
            end
            for j = i + 1, #(self.wiring or {}) do
                if self.wiring[i].name == self.wiring[j].name then
                    return Tr.RegionInvokeRejected(Tr.RegionInvokeDuplicateWire(self.target, self.wiring[i].name))
                end
            end
        end
        for i = 1, #(region.conts or {}) do
            if find_wire(self.wiring or {}, region.conts[i]) == nil then
                return Tr.RegionInvokeRejected(Tr.RegionInvokeMissingWire(self.target, region.conts[i]))
            end
        end

        local entry_label = prefixed_label(self.invoke_id, region.entry.label)
        local entry_params, entry_args = {}, {}
        for i = 1, #(region.params or {}) do
            local p, a = entry_param_from_region_param(region.params[i], self.args[i])
            entry_params[#entry_params + 1] = p
            entry_args[#entry_args + 1] = a
        end
        for i = 1, #(region.entry.params or {}) do
            local p, a = entry_param_from_entry_param(region.entry.params[i])
            entry_params[#entry_params + 1] = p
            entry_args[#entry_args + 1] = a
        end

        local blocks = {
            Tr.ControlBlock(entry_label, entry_params, clone_stmt_list_for_region_invoke(region.entry.body or {}, self.invoke_id, self.wiring)),
        }
        for i = 1, #(region.blocks or {}) do
            blocks[#blocks + 1] = Tr.ControlBlock(
                prefixed_label(self.invoke_id, region.blocks[i].label),
                region.blocks[i].params,
                clone_stmt_list_for_region_invoke(region.blocks[i].body or {}, self.invoke_id, self.wiring))
        end
        return Tr.RegionInvokeExpanded(Tr.RegionInvokeSplice(Tr.StmtJump(self.h, entry_label, entry_args), blocks))
    end

    local function find_region_seal(facts, target)
        for i = 1, #(facts.region_seals or {}) do
            if facts.region_seals[i].target:typecheck_tree_same_region_target(target) then return facts.region_seals[i] end
        end
        return nil
    end

    local function seal_payload_for_cont(seal, cont)
        for i = 1, #(seal.protocol.payloads or {}) do
            if seal.protocol.payloads[i].cont.name == cont.name then return seal.protocol.payloads[i] end
        end
        return nil
    end

    local function sanitize_region_call_name(s)
        s = tostring(s or ""):gsub("[^%w_]", "_")
        if s == "" then s = "region" end
        if s:match("^%d") then s = "_" .. s end
        return s
    end

    local function payload_field_expr(payload_name, field_name)
        return Tr.ExprDot(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(payload_name)), field_name)
    end

    local function typed_expr_ty(expr)
        local h = expr and expr.h
        if h ~= nil and h.typecheck_tree_typed_ty ~= nil then return h:typecheck_tree_typed_ty() end
        return nil
    end

    local function is_void_ty(ty)
        return ty ~= nil and asdl.classof(ty) == Ty.TScalar and ty.scalar == C.ScalarVoid
    end

    function Tr.RegionWireTarget:typecheck_tree_capture_call_wire_args(invoke_id, source_cont, wire_name, add_capture)
        return self
    end

    local function cont_param_named(cont, name)
        for i, p in ipairs((cont and cont.params) or {}) do if p.name == name then return true end end
        return false
    end

    local function capture_jump_args(args, invoke_id, source_cont, wire_name, add_capture)
        local out = {}
        for i, arg in ipairs(args or {}) do
            local ref_name = expr_ref_name(arg.value)
            if ref_name ~= nil and cont_param_named(source_cont, ref_name) then
                out[i] = arg
            else
                local name_part = arg.name ~= "" and arg.name or tostring(i)
                local capture_name = "__region_call_wire_" .. sanitize_region_call_name(invoke_id) .. "_" .. sanitize_region_call_name(wire_name) .. "_" .. sanitize_region_call_name(name_part) .. "_" .. tostring(i)
                add_capture(capture_name, typed_expr_ty(arg.value), arg.value)
                out[i] = Tr.JumpArg(arg.name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(capture_name)))
            end
        end
        return out
    end

    function Tr.RegionWireBlock:typecheck_tree_capture_call_wire_args(invoke_id, source_cont, wire_name, add_capture)
        return Tr.RegionWireBlock(self.label, capture_jump_args(self.args or {}, invoke_id, source_cont, wire_name, add_capture))
    end

    function Tr.RegionWireCont:typecheck_tree_capture_call_wire_args(invoke_id, source_cont, wire_name, add_capture)
        return Tr.RegionWireCont(self.cont, capture_jump_args(self.args or {}, invoke_id, source_cont, wire_name, add_capture))
    end

    function Tr.RegionContWire:typecheck_tree_capture_call_wire_args(invoke_id, source_cont, add_capture)
        return Tr.RegionContWire(self.name, self.target:typecheck_tree_capture_call_wire_args(invoke_id, source_cont, self.name, add_capture))
    end

    function Tr.RegionSeal:typecheck_tree_call_splice(stmt, input)
        local region = self.region
        if #(region.params or {}) ~= #(stmt.args or {}) then
            return Tr.RegionInvokeRejected(Tr.RegionInvokeArgCount(stmt.target, #(region.params or {}), #(stmt.args or {})))
        end
        for i = 1, #(stmt.wiring or {}) do
            if find_cont(region.conts or {}, stmt.wiring[i].name) == nil then
                return Tr.RegionInvokeRejected(Tr.RegionInvokeExtraWire(stmt.target, stmt.wiring[i].name))
            end
            for j = i + 1, #(stmt.wiring or {}) do
                if stmt.wiring[i].name == stmt.wiring[j].name then
                    return Tr.RegionInvokeRejected(Tr.RegionInvokeDuplicateWire(stmt.target, stmt.wiring[i].name))
                end
            end
        end
        for i = 1, #(region.conts or {}) do
            if find_wire(stmt.wiring or {}, region.conts[i]) == nil then
                return Tr.RegionInvokeRejected(Tr.RegionInvokeMissingWire(stmt.target, region.conts[i]))
            end
        end

        local result_ty = Ty.TNamed(Ty.TypeRefGlobal(input.scope.module_name, self.protocol.result_type_name))
        local result_var = "__region_call_result_" .. sanitize_region_call_name(stmt.invoke_id)
        local result_binding = B.Binding(C.Id("region-call-result:" .. tostring(stmt.invoke_id)), result_var, result_ty, B.BindingRoleLocalValue)
        local dispatch_label = prefixed_label(stmt.invoke_id, Tr.BlockLabel("call_dispatch"))
        local dispatch_params, dispatch_jump_args, call_args = {}, {}, {}
        for i, p in ipairs(region.params or {}) do
            local arg_name = "__region_call_arg_" .. sanitize_region_call_name(stmt.invoke_id) .. "_" .. sanitize_region_call_name(p.name)
            dispatch_params[#dispatch_params + 1] = Tr.BlockParam(arg_name, p.ty)
            dispatch_jump_args[#dispatch_jump_args + 1] = Tr.JumpArg(arg_name, stmt.args[i])
            call_args[i] = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(arg_name))
        end
        local captured_wiring = {}
        local function add_capture(name, ty, value)
            local capture_value = value
            local capture_ty = ty
            local ref_name = expr_ref_name(value)
            if (capture_ty == nil or is_void_ty(capture_ty)) and ref_name ~= nil then
                capture_ty = input.scope:typecheck_tree_lookup_value(ref_name):typecheck_tree_value_type_or(capture_ty)
            end
            if capture_ty == nil or is_void_ty(capture_ty) then
                local typed = value:typecheck_tree_expr(input.scope:typecheck_tree_expr_input())
                capture_value = typed.expr
                capture_ty = typed.ty
            end
            dispatch_params[#dispatch_params + 1] = Tr.BlockParam(name, capture_ty)
            dispatch_jump_args[#dispatch_jump_args + 1] = Tr.JumpArg(name, capture_value)
        end
        for i, wire in ipairs(stmt.wiring or {}) do
            captured_wiring[i] = wire:typecheck_tree_capture_call_wire_args(stmt.invoke_id, find_cont(region.conts or {}, wire.name), add_capture)
        end
        local call_expr = Tr.ExprCall(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(self.function_name)), call_args)
        local arms = {}
        for i = 1, #(region.conts or {}) do
            local cont = region.conts[i]
            local wire = find_wire(captured_wiring or {}, cont)
            local binds, args = {}, {}
            local payload = seal_payload_for_cont(self, cont)
            if payload ~= nil then
                local payload_name = "__region_call_payload_" .. sanitize_region_call_name(stmt.invoke_id) .. "_" .. sanitize_region_call_name(cont.name)
                binds[1] = Tr.VariantBind(payload_name, Ty.TNamed(Ty.TypeRefGlobal(input.scope.module_name, payload.type_name)))
                for j, p in ipairs(cont.params or {}) do
                    args[j] = Tr.JumpArg(p.name, payload_field_expr(payload_name, p.name))
                end
            end
            arms[i] = Tr.SwitchVariantStmtArm(cont.name, binds, { wire.target:typecheck_tree_region_invoke_jump(args) })
        end
        local dispatch_block = Tr.ControlBlock(dispatch_label, dispatch_params, {
            Tr.StmtLet(Tr.StmtSurface, result_binding, call_expr),
            Tr.StmtSwitch(Tr.StmtSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(result_var)), {}, arms, { Tr.StmtTrap(Tr.StmtSurface) }),
        })
        return Tr.RegionInvokeExpanded(Tr.RegionInvokeSplice(Tr.StmtJump(stmt.h, dispatch_label, dispatch_jump_args), { dispatch_block }))
    end

    function Tr.StmtRegionCall:typecheck_tree_expand_region_invoke(input)
        local def = input.scope.facts:typecheck_tree_region_def_for(self.target)
        if def == nil then return Tr.RegionInvokeRejected(Tr.RegionInvokeMissingTarget(self.target)) end
        local seal = find_region_seal(input.scope.facts, self.target)
        if seal == nil then return Tr.RegionInvokeRejected(Tr.RegionInvokeCallFrameUnsupported(self.target)) end
        return seal:typecheck_tree_call_splice(self, input)
    end

    function Check.TypeYieldResult:typecheck_tree_yield_void(stmt, input)
        return Check.TypeStmtResult(input, { stmt }, { Check.TypeIssueUnexpectedYield("yield") })
    end

    function Check.TypeYieldVoid:typecheck_tree_yield_void(stmt, input)
        return Check.TypeStmtResult(input, { stmt }, {})
    end

    function Check.TypeYieldResult:typecheck_tree_yield_value(stmt, input)
        local value = stmt.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, value.issues)
        issues[#issues + 1] = Check.TypeIssueUnexpectedYield("yield")
        return Check.TypeStmtResult(input, { Tr.StmtYieldValue(stmt.h, value.expr) }, issues)
    end

    function Check.TypeYieldValue:typecheck_tree_yield_value(stmt, input)
        local value = type_expr_expect(stmt.value, input, self.ty)
        local issues = {}
        append_all(issues, value.issues)
        check_expected("yield", self.ty, value.ty, issues)
        return Check.TypeStmtResult(input, { Tr.StmtYieldValue(stmt.h, value.expr) }, issues)
    end

    function Tr.StmtYieldVoid:typecheck_tree_stmt(input)
        return input.yield:typecheck_tree_yield_void(self, input)
    end

    function Tr.StmtYieldValue:typecheck_tree_stmt(input)
        return input.yield:typecheck_tree_yield_value(self, input)
    end

    function Tr.EntryControlBlock:typecheck_tree_control_entry(input)
        local stmt_input = input.stmt
        local params = {}
        local issues = {}
        for i = 1, #(self.params or {}) do
            local next_input, param, param_issues = self.params[i]:typecheck_tree_add_to_scope(stmt_input, input.region_id, self.label, i)
            stmt_input = next_input
            params[#params + 1] = param
            append_all(issues, param_issues)
        end
        local body = stmt_input:typecheck_tree_stmt_body(self.body)
        append_all(issues, body.issues)
        return Tr.EntryControlBlock(self.label, params, body.stmts), issues
    end

    function Tr.ControlBlock:typecheck_tree_control_block(input)
        local stmt_input = input.stmt
        local params = {}
        local issues = {}
        for i = 1, #(self.params or {}) do
            local next_input, param, param_issues = self.params[i]:typecheck_tree_add_to_scope(stmt_input, input.region_id, self.label, i)
            stmt_input = next_input
            params[#params + 1] = param
            append_all(issues, param_issues)
        end
        local body = stmt_input:typecheck_tree_stmt_body(self.body)
        append_all(issues, body.issues)
        return Tr.ControlBlock(self.label, params, body.stmts), issues
    end

    local expand_control_body

    local function expansion_scope_for_block_params(stmt_input, region_id, block, issues)
        local out = stmt_input
        for i = 1, #(block.params or {}) do
            local next_input, _, param_issues = block.params[i]:typecheck_tree_add_to_scope(out, region_id or "region-invoke", block.label, i)
            out = next_input
            append_all(issues, param_issues)
        end
        return out
    end

    local function append_splice_blocks(blocks, splice, stmt_input, extra_blocks, issues, region_id)
        for i = 1, #(splice.blocks or {}) do
            local block = splice.blocks[i]
            local nested_blocks = {}
            local body = expand_control_body(block.body or {}, expansion_scope_for_block_params(stmt_input, region_id, block, issues), nested_blocks, issues, region_id)
            blocks[#blocks + 1] = Tr.ControlBlock(block.label, block.params, body)
            for j = 1, #nested_blocks do blocks[#blocks + 1] = nested_blocks[j] end
        end
    end

    ------------------------------------------------------------------------
    -- Control expansion: leaf methods on Tr.Stmt
    -- Parent default: pass-through (no expansion needed)
    ------------------------------------------------------------------------
    function Tr.Stmt:typecheck_tree_expand_control(stmt_input, extra_blocks, issues, region_id)
        return self
    end

    function Tr.StmtRegionEmit:typecheck_tree_expand_control(stmt_input, extra_blocks, issues, region_id)
        local r = self:typecheck_tree_expand_region_invoke(Tr.RegionInvokeExpandInput(stmt_input.scope))
        if asdl.classof(r) == Tr.RegionInvokeExpanded then
            append_splice_blocks(extra_blocks, r.splice, stmt_input, extra_blocks, issues, region_id)
            return r.splice.entry_stmt
        end
        issues[#issues + 1] = Check.TypeIssueRegionInvoke(r.reject)
        return Tr.StmtTrap(Tr.StmtSurface)
    end

    function Tr.StmtRegionCall:typecheck_tree_expand_control(stmt_input, extra_blocks, issues, region_id)
        local r = self:typecheck_tree_expand_region_invoke(Tr.RegionInvokeExpandInput(stmt_input.scope))
        if asdl.classof(r) == Tr.RegionInvokeExpanded then
            append_splice_blocks(extra_blocks, r.splice, stmt_input, extra_blocks, issues, region_id)
            return r.splice.entry_stmt
        end
        issues[#issues + 1] = Check.TypeIssueRegionInvoke(r.reject)
        return Tr.StmtTrap(Tr.StmtSurface)
    end

    function Tr.StmtIf:typecheck_tree_expand_control(stmt_input, extra_blocks, issues, region_id)
        local then_body = expand_control_body(self.then_body or {}, stmt_input, extra_blocks, issues, region_id)
        local else_body = expand_control_body(self.else_body or {}, stmt_input, extra_blocks, issues, region_id)
        return Tr.StmtIf(self.h, self.cond, then_body, else_body)
    end

    function Tr.StmtSwitch:typecheck_tree_expand_control(stmt_input, extra_blocks, issues, region_id)
        local arms, variant_arms = {}, {}
        for i = 1, #(self.arms or {}) do
            arms[i] = Tr.SwitchStmtArm(self.arms[i].key, expand_control_body(self.arms[i].body or {}, stmt_input, extra_blocks, issues, region_id))
        end
        for i = 1, #(self.variant_arms or {}) do
            variant_arms[i] = Tr.SwitchVariantStmtArm(self.variant_arms[i].variant_name, self.variant_arms[i].binds, expand_control_body(self.variant_arms[i].body or {}, stmt_input, extra_blocks, issues, region_id))
        end
        return Tr.StmtSwitch(self.h, self.value, arms, variant_arms, expand_control_body(self.default_body or {}, stmt_input, extra_blocks, issues, region_id))
    end

    ------------------------------------------------------------------------
    -- Expansion input: leaf methods on Tr.Stmt
    -- Parent default: identity (scope unchanged)
    ------------------------------------------------------------------------
    function Tr.Stmt:typecheck_tree_expansion_input(stmt_input)
        return stmt_input
    end

    function Tr.StmtLet:typecheck_tree_expansion_input(stmt_input)
        return stmt_input:typecheck_tree_with_scope(stmt_input.scope:typecheck_tree_add_value(B.ValueEntry(self.binding.name, self.binding)))
    end

    function Tr.StmtVar:typecheck_tree_expansion_input(stmt_input)
        return stmt_input:typecheck_tree_with_scope(stmt_input.scope:typecheck_tree_add_value(B.ValueEntry(self.binding.name, self.binding)))
    end

    expand_control_body = function(body, stmt_input, extra_blocks, issues, region_id)
        local out = {}
        local current_input = stmt_input
        for i = 1, #(body or {}) do
            out[i] = body[i]:typecheck_tree_expand_control(current_input, extra_blocks, issues, region_id)
            current_input = out[i]:typecheck_tree_expansion_input(current_input)
        end
        return out
    end

    local function expansion_input_for_entry(stmt_input, region_id, entry, issues)
        local out = stmt_input
        for i = 1, #(entry.params or {}) do
            local next_input, _, param_issues = entry.params[i]:typecheck_tree_add_to_scope(out, region_id, entry.label, i)
            out = next_input
            append_all(issues, param_issues)
        end
        return out
    end

    local function expansion_input_for_block(stmt_input, region_id, block, issues)
        local out = stmt_input
        for i = 1, #(block.params or {}) do
            local next_input, _, param_issues = block.params[i]:typecheck_tree_add_to_scope(out, region_id, block.label, i)
            out = next_input
            append_all(issues, param_issues)
        end
        return out
    end
    function Tr.ControlStmtRegion:typecheck_tree_control_stmt_region(input)
        local stmt_input = input.stmt:typecheck_tree_with_yield(Check.TypeYieldVoid)
        local expansion_issues = {}
        local expansion_blocks = {}
        local expanded_entry = Tr.EntryControlBlock(self.entry.label, self.entry.params, expand_control_body(self.entry.body or {}, expansion_input_for_entry(stmt_input, self.region_id, self.entry, expansion_issues), expansion_blocks, expansion_issues, self.region_id))
        local expanded_blocks = {}
        for i = 1, #(self.blocks or {}) do
            expanded_blocks[#expanded_blocks + 1] = Tr.ControlBlock(self.blocks[i].label, self.blocks[i].params, expand_control_body(self.blocks[i].body or {}, expansion_input_for_block(stmt_input, self.region_id, self.blocks[i], expansion_issues), expansion_blocks, expansion_issues, self.region_id))
        end
        for i = 1, #expansion_blocks do expanded_blocks[#expanded_blocks + 1] = expansion_blocks[i] end

        local control_input = Check.TypeControlInput(stmt_input, self.region_id)
        local entry, entry_issues = expanded_entry:typecheck_tree_control_entry(control_input)
        local issues = {}
        append_all(issues, expansion_issues)
        append_all(issues, entry_issues)
        local blocks = {}
        for i = 1, #(expanded_blocks or {}) do
            local block, block_issues = expanded_blocks[i]:typecheck_tree_control_block(control_input)
            blocks[#blocks + 1] = block
            append_all(issues, block_issues)
        end
        return Check.TypeControlStmtRegionResult(Tr.ControlStmtRegion(self.region_id, entry, blocks), issues)
    end

    function Tr.ControlExprRegion:typecheck_tree_control_expr_region(input)
        local stmt_input = input.stmt:typecheck_tree_with_yield(Check.TypeYieldValue(self.result_ty))
        local expansion_issues = {}
        local expansion_blocks = {}
        local expanded_entry = Tr.EntryControlBlock(self.entry.label, self.entry.params, expand_control_body(self.entry.body or {}, expansion_input_for_entry(stmt_input, self.region_id, self.entry, expansion_issues), expansion_blocks, expansion_issues, self.region_id))
        local expanded_blocks = {}
        for i = 1, #(self.blocks or {}) do
            expanded_blocks[#expanded_blocks + 1] = Tr.ControlBlock(self.blocks[i].label, self.blocks[i].params, expand_control_body(self.blocks[i].body or {}, expansion_input_for_block(stmt_input, self.region_id, self.blocks[i], expansion_issues), expansion_blocks, expansion_issues, self.region_id))
        end
        for i = 1, #expansion_blocks do expanded_blocks[#expanded_blocks + 1] = expansion_blocks[i] end

        local control_input = Check.TypeControlInput(stmt_input, self.region_id)
        local entry, entry_issues = expanded_entry:typecheck_tree_control_entry(control_input)
        local issues = {}
        append_all(issues, expansion_issues)
        append_all(issues, entry_issues)
        local blocks = {}
        for i = 1, #(expanded_blocks or {}) do
            local block, block_issues = expanded_blocks[i]:typecheck_tree_control_block(control_input)
            blocks[#blocks + 1] = block
            append_all(issues, block_issues)
        end
        return Check.TypeControlExprRegionResult(Tr.ControlExprRegion(self.region_id, self.result_ty, entry, blocks), issues)
    end

    function Tr.StmtControl:typecheck_tree_stmt(input)
        local region = self.region:typecheck_tree_control_stmt_region(Check.TypeControlInput(input, self.region.region_id))
        local issues = {}
        append_all(issues, region.issues)
        return Check.TypeStmtResult(input, { Tr.StmtControl(self.h, region.region) }, issues)
    end

    function Tr.StmtTrap:typecheck_tree_stmt(input)
        return Check.TypeStmtResult(input, { self }, {})
    end

    function Check.TypeStmtInput:typecheck_tree_stmt_body(stmts)
        local state = self
        local out = {}
        local issues = {}
        for i = 1, #(stmts or {}) do
            local r = stmts[i]:typecheck_tree_stmt(state)
            state = r.state
            append_all(out, r.stmts)
            append_all(issues, r.issues)
        end
        return Check.TypeStmtResult(state, out, issues)
    end
end
