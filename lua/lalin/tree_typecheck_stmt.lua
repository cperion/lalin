return function(T)
    local asdl = require("lalin.asdl")
    local C = T.LalinCore
    local B = T.LalinBind
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local function append_all(out, values)
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    end

    local function type_eq(a, b)
        return a == b
    end

    local function check_expected(site, expected, actual, issues)
        if not type_eq(expected, actual) then issues[#issues + 1] = Tr.TypeIssueExpected(site, expected, actual) end
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

    function Tr.TypeModuleFacts:typecheck_tree_region_def_for(target)
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

    function Tr.RegionWireBlock:typecheck_tree_region_invoke_jump(args)
        return Tr.StmtJump(Tr.StmtSurface, self.label, args)
    end

    function Tr.RegionWireCont:typecheck_tree_region_invoke_jump(args)
        return Tr.StmtJumpCont(Tr.StmtSurface, self.cont, args)
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

    clone_stmt_for_region_invoke = function(stmt, invoke_id, wiring)
        return stmt:typecheck_tree_region_invoke_clone(invoke_id, wiring)
    end

    clone_stmt_list_for_region_invoke = function(stmts, invoke_id, wiring)
        local out = {}
        for i = 1, #(stmts or {}) do out[i] = clone_stmt_for_region_invoke(stmts[i], invoke_id, wiring) end
        return out
    end

    function Tr.EntryBlockParam:typecheck_tree_add_to_scope(input, region_id, label, index)
        local init = type_expr_expect(self.init, input, self.ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("entry param", self.ty, init.ty, issues)
        local binding = block_param_binding(region_id, label, self, index, B.BindingRoleEntryBlockParam(region_id, label.name, index))
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.name, binding))
        return input:typecheck_tree_with_scope(scope), Tr.EntryBlockParam(self.name, self.ty, init.expr), issues
    end

    function Tr.BlockParam:typecheck_tree_add_to_scope(input, region_id, label, index)
        local binding = block_param_binding(region_id, label, self, index, B.BindingRoleBlockParam(region_id, label.name, index))
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.name, binding))
        return input:typecheck_tree_with_scope(scope), self, {}
    end

    function Tr.JumpArg:typecheck_tree_jump_arg(input)
        local value = self.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.JumpArg(self.name, value.expr), value.issues
    end

    function Tr.StmtReturnValue:typecheck_tree_stmt(input)
        local value = type_expr_expect(self.value, input, input.return_ty)
        if (input.return_ty:typecheck_tree_accept_nil_literal() or asdl.classof(input.return_ty) == Ty.TPtr)
            and tostring(value.ty) == tostring(Ty.TScalar(C.ScalarVoid))
            and tostring(asdl.classof(value.expr)):find("LalinTree.ExprLit", 1, true)
            and tostring(asdl.classof(value.expr.value)):find("LalinCore.LitNil", 1, true)
        then
            value = Tr.TypeExprResult(Tr.ExprLit(Tr.ExprTyped(input.return_ty), value.expr.value), input.return_ty, value.issues)
        end
        local issues = {}
        append_all(issues, value.issues)
        check_expected("return", input.return_ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtReturnValue(self.h, value.expr) }, issues)
    end

    function Tr.StmtReturnVoid:typecheck_tree_stmt(input)
        local issues = {}
        check_expected("return", input.return_ty, Ty.TScalar(C.ScalarVoid), issues)
        return Tr.TypeStmtResult(input, { Tr.StmtReturnVoid(self.h) }, issues)
    end

    function Tr.StmtExpr:typecheck_tree_stmt(input)
        local expr = self.expr:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.TypeStmtResult(input, { Tr.StmtExpr(self.h, expr.expr) }, expr.issues)
    end

    function Tr.StmtLet:typecheck_tree_stmt(input)
        local init = type_expr_expect(self.init, input, self.binding.ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("let", self.binding.ty, init.ty, issues)
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.binding.name, self.binding))
        return Tr.TypeStmtResult(input:typecheck_tree_with_scope(scope), { Tr.StmtLet(self.h, self.binding, init.expr) }, issues)
    end

    function Tr.StmtVar:typecheck_tree_stmt(input)
        local init = type_expr_expect(self.init, input, self.binding.ty)
        local issues = {}
        append_all(issues, init.issues)
        check_expected("var", self.binding.ty, init.ty, issues)
        local scope = input.scope:typecheck_tree_add_value(B.ValueEntry(self.binding.name, self.binding))
        return Tr.TypeStmtResult(input:typecheck_tree_with_scope(scope), { Tr.StmtVar(self.h, self.binding, init.expr) }, issues)
    end

    function Tr.StmtSet:typecheck_tree_stmt(input)
        local place = self.place:typecheck_tree_place(input:typecheck_tree_place_input())
        local value = type_expr_expect(self.value, input, place.ty)
        local issues = {}
        append_all(issues, place.issues)
        append_all(issues, value.issues)
        check_expected("set", place.ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtSet(self.h, place.place, value.expr) }, issues)
    end

    function Tr.StmtAtomicStore:typecheck_tree_stmt(input)
        local addr = self.addr:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local value = type_expr_expect(self.value, input, self.ty)
        local issues = {}
        append_all(issues, addr.issues)
        append_all(issues, value.issues)
        check_expected("atomic store", self.ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtAtomicStore(self.h, self.ty, addr.expr, value.expr, self.ordering) }, issues)
    end

    function Tr.StmtAtomicFence:typecheck_tree_stmt(input)
        return Tr.TypeStmtResult(input, { self }, {})
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
        return Tr.TypeStmtResult(input, { Tr.StmtIf(self.h, cond.expr, then_body.stmts, else_body.stmts) }, issues)
    end

    function Tr.StmtAssert:typecheck_tree_stmt(input)
        local cond = type_expr_expect(self.cond, input, Ty.TScalar(C.ScalarBool))
        local issues = {}
        append_all(issues, cond.issues)
        check_expected("assert condition", Ty.TScalar(C.ScalarBool), cond.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtAssert(self.h, cond.expr) }, issues)
    end

    function Tr.SwitchStmtArm:typecheck_tree_stmt_arm(input)
        local body = input:typecheck_tree_stmt_body(self.body)
        return Tr.SwitchStmtArm(self.key, body.stmts), body.issues
    end

    function Tr.SwitchVariantStmtArm:typecheck_tree_stmt_arm(input)
        local body = input:typecheck_tree_stmt_body(self.body)
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
        return Tr.TypeStmtResult(input, { Tr.StmtSwitch(self.h, value.expr, arms, variant_arms, default_body.stmts) }, issues)
    end

    function Tr.StmtJump:typecheck_tree_stmt(input)
        local args = {}
        local issues = {}
        for i = 1, #(self.args or {}) do
            local arg, arg_issues = self.args[i]:typecheck_tree_jump_arg(input)
            args[#args + 1] = arg
            append_all(issues, arg_issues)
        end
        return Tr.TypeStmtResult(input, { Tr.StmtJump(self.h, self.target, args) }, issues)
    end

    function Tr.StmtJumpCont:typecheck_tree_stmt(input)
        local args = {}
        local issues = {}
        for i = 1, #(self.args or {}) do
            local arg, arg_issues = self.args[i]:typecheck_tree_jump_arg(input)
            args[#args + 1] = arg
            append_all(issues, arg_issues)
        end
        return Tr.TypeStmtResult(input, { Tr.StmtJumpCont(self.h, self.cont, args) }, issues)
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

    function Tr.StmtRegionEmit:typecheck_tree_stmt(input)
        local args, issues = typecheck_region_invoke_args(self, input)
        return Tr.TypeStmtResult(input, { Tr.StmtRegionEmit(self.h, self.invoke_id, self.target, args, self.wiring) }, issues)
    end

    function Tr.StmtRegionCall:typecheck_tree_stmt(input)
        local args, issues = typecheck_region_invoke_args(self, input)
        return Tr.TypeStmtResult(input, { Tr.StmtRegionCall(self.h, self.invoke_id, self.target, args, self.wiring) }, issues)
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

    function Tr.StmtRegionCall:typecheck_tree_expand_region_invoke(input)
        return Tr.RegionInvokeRejected(Tr.RegionInvokeCallFrameUnsupported(self.target))
    end

    function Tr.TypeYieldResult:typecheck_tree_yield_void(stmt, input)
        return Tr.TypeStmtResult(input, { stmt }, { Tr.TypeIssueUnexpectedYield("yield") })
    end

    function Tr.TypeYieldVoid:typecheck_tree_yield_void(stmt, input)
        return Tr.TypeStmtResult(input, { stmt }, {})
    end

    function Tr.TypeYieldResult:typecheck_tree_yield_value(stmt, input)
        local value = stmt.value:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, value.issues)
        issues[#issues + 1] = Tr.TypeIssueUnexpectedYield("yield")
        return Tr.TypeStmtResult(input, { Tr.StmtYieldValue(stmt.h, value.expr) }, issues)
    end

    function Tr.TypeYieldValue:typecheck_tree_yield_value(stmt, input)
        local value = type_expr_expect(stmt.value, input, self.ty)
        local issues = {}
        append_all(issues, value.issues)
        check_expected("yield", self.ty, value.ty, issues)
        return Tr.TypeStmtResult(input, { Tr.StmtYieldValue(stmt.h, value.expr) }, issues)
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

    local function append_splice_blocks(blocks, splice)
        for i = 1, #(splice.blocks or {}) do blocks[#blocks + 1] = splice.blocks[i] end
    end

    local function expand_control_stmt(stmt, stmt_input, extra_blocks, issues)
        local cls = asdl.classof(stmt)
        if cls == Tr.StmtRegionEmit or cls == Tr.StmtRegionCall then
            local r = stmt:typecheck_tree_expand_region_invoke(Tr.RegionInvokeExpandInput(stmt_input.scope))
            if asdl.classof(r) == Tr.RegionInvokeExpanded then
                append_splice_blocks(extra_blocks, r.splice)
                return r.splice.entry_stmt
            end
            issues[#issues + 1] = Tr.TypeIssueRegionInvoke(r.reject)
            return Tr.StmtTrap(Tr.StmtSurface)
        elseif cls == Tr.StmtIf then
            local then_body = expand_control_body(stmt.then_body or {}, stmt_input, extra_blocks, issues)
            local else_body = expand_control_body(stmt.else_body or {}, stmt_input, extra_blocks, issues)
            return Tr.StmtIf(stmt.h, stmt.cond, then_body, else_body)
        elseif cls == Tr.StmtSwitch then
            local arms, variant_arms = {}, {}
            for i = 1, #(stmt.arms or {}) do
                arms[i] = Tr.SwitchStmtArm(stmt.arms[i].key, expand_control_body(stmt.arms[i].body or {}, stmt_input, extra_blocks, issues))
            end
            for i = 1, #(stmt.variant_arms or {}) do
                variant_arms[i] = Tr.SwitchVariantStmtArm(stmt.variant_arms[i].variant_name, stmt.variant_arms[i].binds, expand_control_body(stmt.variant_arms[i].body or {}, stmt_input, extra_blocks, issues))
            end
            return Tr.StmtSwitch(stmt.h, stmt.value, arms, variant_arms, expand_control_body(stmt.default_body or {}, stmt_input, extra_blocks, issues))
        end
        return stmt
    end

    expand_control_body = function(body, stmt_input, extra_blocks, issues)
        local out = {}
        for i = 1, #(body or {}) do out[i] = expand_control_stmt(body[i], stmt_input, extra_blocks, issues) end
        return out
    end

    function Tr.ControlStmtRegion:typecheck_tree_control_stmt_region(input)
        local stmt_input = input.stmt:typecheck_tree_with_yield(Tr.TypeYieldVoid)
        local expansion_issues = {}
        local expansion_blocks = {}
        local expanded_entry = Tr.EntryControlBlock(self.entry.label, self.entry.params, expand_control_body(self.entry.body or {}, stmt_input, expansion_blocks, expansion_issues))
        local expanded_blocks = {}
        for i = 1, #(self.blocks or {}) do
            expanded_blocks[#expanded_blocks + 1] = Tr.ControlBlock(self.blocks[i].label, self.blocks[i].params, expand_control_body(self.blocks[i].body or {}, stmt_input, expansion_blocks, expansion_issues))
        end
        for i = 1, #expansion_blocks do expanded_blocks[#expanded_blocks + 1] = expansion_blocks[i] end

        local control_input = Tr.TypeControlInput(stmt_input, self.region_id)
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
        return Tr.TypeControlStmtRegionResult(Tr.ControlStmtRegion(self.region_id, entry, blocks), issues)
    end

    function Tr.ControlExprRegion:typecheck_tree_control_expr_region(input)
        local stmt_input = input.stmt:typecheck_tree_with_yield(Tr.TypeYieldValue(self.result_ty))
        local expansion_issues = {}
        local expansion_blocks = {}
        local expanded_entry = Tr.EntryControlBlock(self.entry.label, self.entry.params, expand_control_body(self.entry.body or {}, stmt_input, expansion_blocks, expansion_issues))
        local expanded_blocks = {}
        for i = 1, #(self.blocks or {}) do
            expanded_blocks[#expanded_blocks + 1] = Tr.ControlBlock(self.blocks[i].label, self.blocks[i].params, expand_control_body(self.blocks[i].body or {}, stmt_input, expansion_blocks, expansion_issues))
        end
        for i = 1, #expansion_blocks do expanded_blocks[#expanded_blocks + 1] = expansion_blocks[i] end

        local control_input = Tr.TypeControlInput(stmt_input, self.region_id)
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
        return Tr.TypeControlExprRegionResult(Tr.ControlExprRegion(self.region_id, self.result_ty, entry, blocks), issues)
    end

    function Tr.StmtControl:typecheck_tree_stmt(input)
        local region = self.region:typecheck_tree_control_stmt_region(Tr.TypeControlInput(input, self.region.region_id))
        local issues = {}
        append_all(issues, region.issues)
        return Tr.TypeStmtResult(input, { Tr.StmtControl(self.h, region.region) }, issues)
    end

    function Tr.StmtTrap:typecheck_tree_stmt(input)
        return Tr.TypeStmtResult(input, { self }, {})
    end

    function Tr.TypeStmtInput:typecheck_tree_stmt_body(stmts)
        local state = self
        local out = {}
        local issues = {}
        for i = 1, #(stmts or {}) do
            local r = stmts[i]:typecheck_tree_stmt(state)
            state = r.state
            append_all(out, r.stmts)
            append_all(issues, r.issues)
        end
        return Tr.TypeStmtResult(state, out, issues)
    end
end
