local schema = require("lalin.schema_runtime")
local function single(value) return { value } end
local function as_list(values) return values end
local function only(values)
    if #values == 0 then error("phase output: expected exactly 1 value, got 0", 2) end
    if #values ~= 1 then error("phase output: expected exactly 1 value, got more", 2) end
    return values[1]
end
local function append_all(out, values)
    for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    return out
end
local function concat_all(lists)
    local out = {}
    for i = 1, #(lists or {}) do append_all(out, lists[i]) end
    return out
end
local function concat2(a, b)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    return out
end
local function concat3(a, b, c)
    local out = {}
    append_all(out, a)
    append_all(out, b)
    append_all(out, c)
    return out
end
local function flat_map(fn, values, n)
    local out = {}
    n = n or #(values or {})
    for i = 1, n do append_all(out, fn(values[i])) end
    return out
end

local function clone_values(values)
    local out = {}
    for i = 1, #values do out[#out + 1] = values[i] end
    return out
end

local function clone_types(types)
    local out = {}
    for i = 1, #types do out[#out + 1] = types[i] end
    return out
end

local function bind_context(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree
    local Check = T.LalinCheck
    local H = T.LalinHost

    local module_type_api = require("lalin.tree_module_type")(T)
    local control_api = require("lalin.tree_control_facts")(T)
    require("lalin.tree_typecheck_type")(T)
    require("lalin.tree_typecheck_layout")(T)
    require("lalin.tree_typecheck_fact")(T)
    local type_view
    local type_index_base
    local type_place
    local type_expr
    local type_expr_expect
    local type_func
    local type_item

    local function void_ty() return Ty.TScalar(C.ScalarVoid) end
    local function bool_ty() return Ty.TScalar(C.ScalarBool) end
    local function i32_ty() return Ty.TScalar(C.ScalarI32) end
    local function index_ty() return Ty.TScalar(C.ScalarIndex) end
    local function f64_ty() return Ty.TScalar(C.ScalarF64) end
    local function u8_ty() return Ty.TScalar(C.ScalarU8) end
    local function string_ty() return Ty.TSlice(u8_ty()) end

    function Tr.View:typecheck_tree_elem()
        return void_ty()
    end

    function Tr.ViewFromExpr:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewContiguous:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewStrided:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewRestrided:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewRowBase:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewInterleaved:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewInterleavedView:typecheck_tree_elem()
        return self.elem
    end

    function Tr.ViewWindow:typecheck_tree_elem()
        return self.base:typecheck_tree_elem()
    end

    local function view_elem(view)
        return view:typecheck_tree_elem()
    end

    local function type_eq(a, b)
        return a == b
    end

    local canonical_type
    canonical_type = function(env, ty)
        return ty:typecheck_tree_canonical(env)
    end

    local function canonical_params(env, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = Ty.Param(params[i].name, canonical_type(env, params[i].ty)) end
        return out
    end

    local function type_contains_lease(ty)
        return ty:typecheck_tree_contains_lease()
    end

    local function type_contains_owned(ty)
        return ty:typecheck_tree_contains_owned()
    end

    local function is_owned_type(ty)
        return ty:typecheck_tree_is_owned_type()
    end

    local function lease_access_base(ty)
        return ty:typecheck_tree_lease_access_base()
    end

    local function arg_matches_param(env, expected, actual)
        expected = canonical_type(env, expected)
        actual = canonical_type(env, actual)
        if type_eq(expected, actual) then return true end
        if is_owned_type(expected) or is_owned_type(actual) then return false end
        return expected:typecheck_tree_arg_matches_actual(env, actual)
    end

    require("lalin.tree_typecheck_expr")(T)
    require("lalin.tree_typecheck_stmt")(T)

    function Tr.ExprHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.ExprTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    local function typed_expr_header_ty(h)
        return h:typecheck_tree_typed_ty()
    end

    function Tr.PlaceHeader:typecheck_tree_typed_ty()
        return nil
    end

    function Tr.PlaceTyped:typecheck_tree_typed_ty()
        return self.ty
    end

    local function typed_place_header_ty(h)
        return h:typecheck_tree_typed_ty()
    end

    local function merged_layouts(scope, extra_layout_env)
        local extra = extra_layout_env and extra_layout_env.layouts
        if extra == nil or #extra == 0 then return scope.layouts end
        local layouts = clone_values(scope.layouts)
        for i = 1, #extra do layouts[#layouts + 1] = extra[i] end
        return layouts
    end

    local function array_len_const(len)
        return len:typecheck_tree_const_count()
    end

    local function check_type_policy(ty, issues, site)
        ty:typecheck_tree_check_policy(issues, site)
    end

    local function type_ref_text(ref)
        return ref:typecheck_tree_ref_text()
    end

    local function type_ref_leaf(ref)
        return ref:typecheck_tree_ref_leaf()
    end

    local function type_ref_matches_ty(ref, ty)
        return ty:typecheck_tree_matches_type_ref(ref)
    end

    local function empty_type_module_facts()
        return Check.TypeModuleFacts({}, {}, {}, {}, {}, {}, {})
    end

    local function variant_name_text(v)
        if type(v) == "string" then return v end
        return v and (v.text or v.name) or tostring(v)
    end

    local function is_void_type(ty)
        return ty:typecheck_tree_is_void_type()
    end

    local function is_handle_type(ty)
        return ty:typecheck_tree_is_handle_type()
    end

    local function handle_repr_type(handle_ty)
        return handle_ty:typecheck_tree_handle_repr_type()
    end

    local function find_handle_def(scope, name)
        for i = 1, #(scope.facts.handles or {}) do
            if scope.facts.handles[i].name == name then return scope.facts.handles[i] end
        end
        return nil
    end

    local function find_handle_def_for_type(scope, ty)
        return ty:typecheck_tree_handle_def(scope.facts)
    end

    local function lease_target_type(ty)
        return ty:typecheck_tree_lease_target_type()
    end

    local function lease_origin_name(lease_ty)
        return lease_ty:typecheck_tree_lease_origin_name()
    end

    local function lease_payload_info(ty)
        return ty:typecheck_tree_lease_payload_info()
    end

    local function access_allows_lease_grant(ty)
        return ty:typecheck_tree_access_allows_lease_grant()
    end

    local function param_domain_matches(param_ty, domain_ref)
        local elem = param_ty:typecheck_tree_domain_match_elem()
        if elem == nil then return false end
        return type_ref_matches_ty(domain_ref, elem)
    end

    local function append_domain_param(params_by_domain, domain_ref, param_name)
        local key = type_ref_leaf(domain_ref) or ""
        local bucket = params_by_domain[key]
        if not bucket then bucket = {}; params_by_domain[key] = bucket end
        bucket[#bucket + 1] = param_name
    end

    local function contains_name(names, name)
        for i = 1, #(names or {}) do if names[i] == name then return true end end
        return false
    end

    local function check_handle_resolution_signature(scope, params, payload_params, issues, site)
        local handle_defs = {}
        local domain_params = {}
        local preserving_domain_params = {}
        local all_defs = scope.facts.handles or {}
        for i = 1, #(params or {}) do
            local pty = canonical_type(scope, params[i].ty)
            local def = find_handle_def_for_type(scope, pty)
            if def and def.target then handle_defs[#handle_defs + 1] = def end
            for j = 1, #all_defs do
                local hdef = all_defs[j]
                if hdef.domain and param_domain_matches(pty, hdef.domain) then
                    append_domain_param(domain_params, hdef.domain, params[i].name)
                    if access_allows_lease_grant(pty) then append_domain_param(preserving_domain_params, hdef.domain, params[i].name) end
                end
            end
        end
        if #handle_defs == 0 then return end
        for i = 1, #(payload_params or {}) do
            local info = lease_payload_info(canonical_type(scope, payload_params[i].ty))
            if info ~= nil then
                local matched = nil
                for j = 1, #handle_defs do
                    if type_ref_matches_ty(handle_defs[j].target, info.target) then
                        matched = handle_defs[j]
                        break
                    end
                end
                if matched == nil then
                    issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryHandleTargetMismatch, info.lease)
                elseif matched.domain then
                    local key = type_ref_leaf(matched.domain) or ""
                    if #(domain_params[key] or {}) == 0 then
                        issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryHandleDomainMissing, info.lease)
                    elseif #(preserving_domain_params[key] or {}) == 0 then
                        issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryHandleDomainAccess, info.lease)
                    elseif info.origin == nil then
                        issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryHandleLeaseOriginMissing, info.lease)
                    elseif not contains_name(preserving_domain_params[key], info.origin) then
                        issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryHandleLeaseOriginMismatch, info.lease)
                    end
                end
            end
        end
    end


    local function bind_scope_for_variant(scope, region_id, variant, requested_binds)
        local out_scope = scope
        local binds = {}
        if requested_binds ~= nil and #requested_binds > 0 then
            for i = 1, #requested_binds do
                local rb = requested_binds[i]
                local ty = rb.ty
                for j = 1, #(variant.fields or {}) do
                    if variant.fields[j].field_name == rb.name then ty = variant.fields[j].ty end
                end
                if is_void_type(ty) and not is_void_type(variant.payload) then ty = variant.payload end
                binds[#binds + 1] = { name = rb.name, ty = ty }
            end
        elseif #(variant.fields or {}) > 0 then
            for i = 1, #variant.fields do binds[#binds + 1] = { name = variant.fields[i].field_name, ty = variant.fields[i].ty } end
        elseif not is_void_type(variant.payload) then
            binds[#binds + 1] = { name = "payload", ty = variant.payload }
        end
        for i = 1, #binds do
            local b = B.Binding(C.Id("variant:" .. tostring(region_id or "switch") .. ":" .. variant.name .. ":" .. binds[i].name), binds[i].name, binds[i].ty, B.BindingRoleLocalValue)
            out_scope = out_scope:typecheck_tree_add_value(B.ValueEntry(b.name, b))
        end
        return out_scope, binds
    end

    local function live_lease_tys(scope)
        local out = {}
        for i = #scope.values, 1, -1 do
            local ty = canonical_type(scope, scope.values[i].binding.ty)
            ty:typecheck_tree_append_live_lease(out)
        end
        return out
    end

    local function callee_effect_def(scope, callee_expr)
        local binding_name = callee_expr:typecheck_tree_binding_name()
        if binding_name == nil then return nil end
        for i = 1, #(scope.facts.effects or {}) do
            if scope.facts.effects[i].name == binding_name then return scope.facts.effects[i] end
        end
        return nil
    end

    local function call_may_invalidate_while_lease_live(scope, callee_expr, param_tys, typed_args)
        local leases = live_lease_tys(scope)
        if #leases == 0 then return nil end
        local effect = callee_effect_def(scope, callee_expr)
        local preserve = effect and effect.preserve or {}
        local explicit_invalidate = effect and effect.invalidate or {}
        for i = 1, #(param_tys or {}) do
            local pty = canonical_type(scope, param_tys[i])
            if pty:typecheck_tree_call_may_invalidate_live_lease_param() then
                local pname = effect and effect.params and effect.params[i] and effect.params[i].name
                local preserves_param = pname and contains_name(preserve, pname)
                local invalidates_param = (pname and contains_name(explicit_invalidate, pname)) or not preserves_param
                if invalidates_param then
                    local arg_name = typed_args and typed_args[i] and typed_args[i]:typecheck_tree_binding_name() or nil
                    for j = 1, #leases do
                        local origin = lease_origin_name(leases[j])
                        if origin == nil or arg_name == nil or origin == arg_name then return leases[j] end
                    end
                end
            end
        end
        return nil
    end

    type_expr_expect = function(expr, stmt_input, expected)
        return expr:typecheck_tree_expr_expected(stmt_input:typecheck_tree_expected_expr_input(expected))
    end

    local function check_expected(site, expected, actual, issues)
        if not type_eq(expected, actual) then issues[#issues + 1] = Check.TypeIssueExpected(site, expected, actual) end
    end

    function type_view(node, ...)
        return node:typecheck_tree_view(...)
    end

    function type_index_base(node, ...)
        return node:typecheck_tree_index_base(...)
    end

    function type_place(node, input)
        return node:typecheck_tree_place(input)
    end

    function type_expr(node, input)
        return node:typecheck_tree_expr(input)
    end

    local function jump_args_by_name(args)
        local out = {}; local dup = {}
        for i = 1, #args do if out[args[i].name] ~= nil then dup[args[i].name] = true end; out[args[i].name] = args[i] end
        return out, dup
    end

    local function block_param_bindings(region_id, label, params, is_entry)
        local entries = {}
        for i = 1, #params do
            local role = is_entry and B.BindingRoleEntryBlockParam(region_id, label.name, i) or B.BindingRoleBlockParam(region_id, label.name, i)
            local binding = B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. params[i].name), params[i].name, params[i].ty, role)
            entries[#entries + 1] = B.ValueEntry(params[i].name, binding)
        end
        return entries
    end

    local function scope_with_block_params(scope, region_id, label, params, is_entry)
        local out = scope
        local entries = block_param_bindings(region_id, label, params, is_entry)
        for i = 1, #entries do out = out:typecheck_tree_add_value(entries[i]) end
        return out
    end

    local function type_contracts(contracts, input)
        local out, issues = {}, {}
        for i = 1, #contracts do
            local c, ci = contracts[i]:typecheck_tree_contract(input)
            out[#out + 1] = c
            append_all(issues, ci)
        end
        return out, issues
    end

    local function check_func_types(func, issues)
        for i = 1, #(func.params or {}) do check_type_policy(func.params[i].ty, issues, "param " .. tostring(func.params[i].name)) end
        check_type_policy(func.result, issues, "result")
        if type_contains_lease(func.result) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryLeaseEscapeDurable, func.result) end
    end

    function Tr.Region:typecheck_tree_signature_issues(input)
        local issues = {}
        for i = 1, #(self.params or {}) do
            check_type_policy(self.params[i].ty, issues, "region param " .. tostring(self.params[i].name))
        end
        for i = 1, #(self.conts or {}) do
            local cont = self.conts[i]
            for j = 1, #(cont.params or {}) do
                local param = cont.params[j]
                check_type_policy(param.ty, issues, "continuation " .. tostring(cont.name) .. " param " .. tostring(param.name))
            end
            check_handle_resolution_signature(input.scope, self.params, cont.params, issues, "region " .. tostring(cont.name))
        end
        return issues
    end

    local function canonical_func(self, scope)
        return schema.with(self, { params = canonical_params(scope, self.params), result = canonical_type(scope, self.result) })
    end

    local function canonical_block_params(scope, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = schema.with(params[i], { ty = canonical_type(scope, params[i].ty) }) end
        return out
    end

    local function canonical_entry_params(scope, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = schema.with(params[i], { ty = canonical_type(scope, params[i].ty) }) end
        return out
    end

    local function canonical_region(scope, region)
        local params = canonical_params(scope, region.params or {})
        local conts = {}
        for i = 1, #(region.conts or {}) do conts[i] = schema.with(region.conts[i], { params = canonical_block_params(scope, region.conts[i].params) }) end
        local entry = schema.with(region.entry, { params = canonical_entry_params(scope, region.entry.params) })
        local blocks = {}
        for i = 1, #(region.blocks or {}) do blocks[i] = schema.with(region.blocks[i], { params = canonical_block_params(scope, region.blocks[i].params) }) end
        return schema.with(region, { params = params, conts = conts, contracts = region.contracts or {}, entry = entry, blocks = blocks })
    end

    local function type_plain_func(self, input)
        local func = canonical_func(self, input.scope)
        local func_scope = input.scope:typecheck_tree_add_params(func.name, func.params)
        local stmt_input = func_scope:typecheck_tree_stmt_input(func.result, Check.TypeYieldNone)
        local body = stmt_input:typecheck_tree_stmt_body(func.body)
        local issues = {}; check_func_types(func, issues); append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues)
        return Check.TypeFuncResult(schema.with(func, { body = body.stmts }), issues)
    end

    local function type_contract_func(self, input)
        local func = canonical_func(self, input.scope)
        local func_scope = input.scope:typecheck_tree_add_params(func.name, func.params)
        local stmt_input = func_scope:typecheck_tree_stmt_input(func.result, Check.TypeYieldNone)
        local contracts, issues = type_contracts(func.contracts, stmt_input)
        check_func_types(func, issues)
        local body = stmt_input:typecheck_tree_stmt_body(func.body)
        append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues)
        return Check.TypeFuncResult(schema.with(func, { contracts = contracts, body = body.stmts }), issues)
    end

    function Tr.FuncLocal:typecheck_tree_func(input)
        return type_plain_func(self, input)
    end

    function Tr.FuncExport:typecheck_tree_func(input)
        return type_plain_func(self, input)
    end

    function Tr.FuncLocalContract:typecheck_tree_func(input)
        return type_contract_func(self, input)
    end

    function Tr.FuncExportContract:typecheck_tree_func(input)
        return type_contract_func(self, input)
    end

    function type_func(node, ...)
        return node:typecheck_tree_func(...)
    end

    function Tr.ItemFunc:typecheck_tree_item(input)
        local r = type_func(self.func, Check.TypeFuncInput(input.scope))
        return Check.TypeItemResult({ Tr.ItemFunc(r.func) }, r.issues)
    end

    function Tr.ItemConst:typecheck_tree_item(input)
        local ty = canonical_type(input.scope, self.c.ty)
        local expr_input = input.scope:typecheck_tree_expr_input()
        local value = type_expr(self.c.value, expr_input)
        local issues = {}
        check_type_policy(ty, issues, "const")
        append_all(issues, value.issues)
        check_expected("const", ty, value.ty, issues)
        if type_contains_lease(ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryLeaseEscapeDurable, ty) end
        if type_contains_owned(ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryOwnedCapturedDurable, ty) end
        return Check.TypeItemResult({ Tr.ItemConst(schema.with(self.c, { ty = ty, value = value.expr })) }, issues)
    end

    function Tr.ItemStatic:typecheck_tree_item(input)
        local ty = canonical_type(input.scope, self.s.ty)
        local expr_input = input.scope:typecheck_tree_expr_input()
        local value = type_expr(self.s.value, expr_input)
        local issues = {}
        check_type_policy(ty, issues, "static")
        append_all(issues, value.issues)
        check_expected("static", ty, value.ty, issues)
        if type_contains_lease(ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryLeaseEscapeDurable, ty) end
        if type_contains_owned(ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryOwnedCapturedDurable, ty) end
        return Check.TypeItemResult({ Tr.ItemStatic(schema.with(self.s, { ty = ty, value = value.expr })) }, issues)
    end

    function Tr.ItemExtern:typecheck_tree_item()
        local issues = {}
        check_func_types(self.func, issues)
        return Check.TypeItemResult({ self }, issues)
    end

    function Tr.ItemImport:typecheck_tree_item()
        return Check.TypeItemResult({ self }, {})
    end

    function Tr.TypeDecl:typecheck_tree_item_issues()
        return {}
    end

    function Tr.TypeDeclStruct:typecheck_tree_item_issues()
        local issues = {}
        for i = 1, #self.fields do
            check_type_policy(self.fields[i].ty, issues, "field " .. self.fields[i].field_name)
            if type_contains_lease(self.fields[i].ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryLeaseEscapeDurable, self.fields[i].ty) end
            if type_contains_owned(self.fields[i].ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryOwnedCapturedDurable, self.fields[i].ty) end
        end
        return issues
    end

    function Tr.TypeDeclUnion:typecheck_tree_item_issues()
        local issues = {}
        for i = 1, #self.fields do
            check_type_policy(self.fields[i].ty, issues, "field " .. self.fields[i].field_name)
            if type_contains_lease(self.fields[i].ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryLeaseEscapeDurable, self.fields[i].ty) end
            if type_contains_owned(self.fields[i].ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(Check.TypeUnaryOwnedCapturedDurable, self.fields[i].ty) end
        end
        return issues
    end

    function Tr.TypeDeclEnumSugar:typecheck_tree_item_issues()
        local issues = {}
        local seen = {}
        for i = 1, #self.variants do
            local name = variant_name_text(self.variants[i])
            if seen[name] then issues[#issues + 1] = Check.TypeIssueDuplicateVariant(self.name, name) end
            seen[name] = true
        end
        return issues
    end

    function Tr.TypeDeclTaggedUnionSugar:typecheck_tree_item_issues()
        local issues = {}
        local seen = {}
        local is_region_call_result = type(self.name) == "string" and self.name:match("^__lalin_region_call_") ~= nil
        for i = 1, #self.variants do
            local v = self.variants[i]
            local name = v.name
            check_type_policy(v.payload, issues, "variant " .. name)
            if type_contains_lease(v.payload) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(is_region_call_result and Check.TypeUnaryRegionCallLeasePayload or Check.TypeUnaryLeaseEscapeDurable, v.payload) end
            if type_contains_owned(v.payload) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(is_region_call_result and Check.TypeUnaryOwnedRegionCallPayload or Check.TypeUnaryOwnedCapturedDurable, v.payload) end
            for j = 1, #(v.fields or {}) do
                check_type_policy(v.fields[j].ty, issues, "variant field " .. v.fields[j].field_name)
                if type_contains_lease(v.fields[j].ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(is_region_call_result and Check.TypeUnaryRegionCallLeasePayload or Check.TypeUnaryLeaseEscapeDurable, v.fields[j].ty) end
                if type_contains_owned(v.fields[j].ty) then issues[#issues + 1] = Check.TypeIssueInvalidUnary(is_region_call_result and Check.TypeUnaryOwnedRegionCallPayload or Check.TypeUnaryOwnedCapturedDurable, v.fields[j].ty) end
            end
            if seen[name] then issues[#issues + 1] = Check.TypeIssueDuplicateVariant(self.name, name) end
            seen[name] = true
        end
        return issues
    end

    local function path_text(path)
        local parts = {}
        for i = 1, #(path and path.parts or {}) do parts[#parts + 1] = path.parts[i].text end
        return table.concat(parts, ".")
    end

    local function type_ref_name(ref)
        local cls = schema.classof(ref)
        if cls == Ty.TypeRefPath then return path_text(ref.path) end
        if cls == Ty.TypeRefGlobal then return ref.type_name end
        if cls == Ty.TypeRefLocal then return ref.sym and ref.sym.text or tostring(ref) end
        return tostring(ref)
    end

    local function named_ref_name(ty)
        local cls = schema.classof(ty)
        if cls == Ty.TNamed or cls == Ty.THandle then return type_ref_name(ty.ref) end
        return nil
    end

    local function ptr_elem_name(ty)
        local cls = schema.classof(ty)
        if cls == Ty.TPtr then return named_ref_name(ty.elem) end
        if cls == Ty.TAccess then return ptr_elem_name(ty.base) end
        return nil
    end

    local function is_preserving_access(ty)
        local cls = schema.classof(ty)
        if cls == Ty.TAccess then
            local acls = schema.classof(ty.access)
            return acls == Ty.TypeAccessReadonly or acls == Ty.TypeAccessPreserve
        end
        return false
    end

    local function is_invalidating_access(ty)
        local cls = schema.classof(ty)
        if cls == Ty.TAccess then
            local acls = schema.classof(ty.access)
            return acls == Ty.TypeAccessInvalidate or acls == Ty.TypeAccessWriteonly
        end
        if cls == Ty.TPtr or cls == Ty.TView then return true end
        return false
    end

    local function handle_type_name_from_param(ty)
        local cls = schema.classof(ty)
        if cls == Ty.THandle then return type_ref_name(ty.ref) end
        if cls == Ty.TNamed then return type_ref_name(ty.ref) end
        return nil
    end

    local function lease_info(ty)
        local cls = schema.classof(ty)
        if cls ~= Ty.TLease then return nil end
        local origin = schema.classof(ty.origin) == Ty.LeaseOriginParam and ty.origin.name or nil
        return { origin = origin, target = ptr_elem_name(ty.base) }
    end

    local function region_domain_signature(region, domain_name, handle_name)
        if #(region.params or {}) < 2 then return nil end
        local self_param, handle_param = region.params[1], region.params[2]
        if self_param.name ~= "self" then return nil end
        if ptr_elem_name(self_param.ty) ~= domain_name then return nil end
        if handle_type_name_from_param(handle_param.ty) ~= handle_name then return nil end
        return self_param, handle_param
    end

    local function region_grants_domain_lease(region, target_name)
        for _, cont in ipairs(region.conts or {}) do
            for _, p in ipairs(cont.params or {}) do
                local info = lease_info(p.ty)
                if info and info.origin == "self" and (target_name == nil or info.target == target_name) then
                    return true, cont.name
                end
            end
        end
        return false, nil
    end

    local function domain_regions_for(scope, domain_name, handle_name)
        local out = {}
        local facts = scope and scope.facts
        for _, entry in ipairs(facts and facts.regions or {}) do
            local r = entry.region
            if r and tostring(r.name):match("^" .. domain_name:gsub("%.", "%%.") .. "%.") then
                if region_domain_signature(r, domain_name, handle_name) then out[#out + 1] = r end
            end
        end
        return out
    end

    local function check_domain_ops(scope, domain_name, issues)
        local facts = scope and scope.facts
        for _, effect in ipairs(facts and facts.effects or {}) do
            if #(effect.params or {}) > 0 then
                local first = effect.params[1]
                if first.name == "self" and ptr_elem_name(first.ty) == domain_name then
                    local has_contract_class = #(effect.readonly or {}) > 0 or #(effect.preserve or {}) > 0 or #(effect.invalidate or {}) > 0
                    local preserving, invalidating
                    if has_contract_class then
                        preserving = #(effect.readonly or {}) > 0 or #(effect.preserve or {}) > 0
                        invalidating = #(effect.invalidate or {}) > 0
                    else
                        preserving = is_preserving_access(first.ty)
                        invalidating = is_invalidating_access(first.ty)
                    end
                    if preserving == invalidating then
                        issues[#issues + 1] = Check.TypeIssueDomainContract(effect.name, domain_name, "operation whose receiver is the domain must classify access as exactly preserving or invalidating")
                    end
                end
            end
        end
    end

    local function check_domain_contract_for_handle(handle_decl, scope, issues)
        local domain_ref, target_ref = nil, nil
        for _, fact in ipairs(handle_decl.facts or {}) do
            domain_ref = fact:typecheck_tree_handle_domain() or domain_ref
            target_ref = fact:typecheck_tree_handle_target() or target_ref
        end
        if domain_ref == nil then return end
        local domain_name = type_ref_name(domain_ref)
        local target_name = target_ref and type_ref_name(target_ref) or nil
        local handle_name = handle_decl.name:find(".", 1, true) and handle_decl.name or (domain_name .. "." .. handle_decl.name)
        local candidates = domain_regions_for(scope, domain_name, handle_name)
        if #candidates == 0 then
            issues[#issues + 1] = Check.TypeIssueDomainContract(handle_name, domain_name, "missing domain resolver region taking `(self, handle)`")
            return
        end
        local grants = false
        for _, r in ipairs(candidates) do
            local ok = region_grants_domain_lease(r, target_name)
            grants = grants or ok
        end
        if not grants then
            issues[#issues + 1] = Check.TypeIssueDomainContract(handle_name, domain_name, "resolver region must grant `lease(\"self\", ptr(Target))` on a success continuation")
        end
        check_domain_ops(scope, domain_name, issues)
    end

    function Tr.TypeDeclHandle:typecheck_tree_item_issues(input)
        local issues = {}
        self.repr:typecheck_tree_check_handle_decl(self.name, issues)
        if input and input.scope then check_domain_contract_for_handle(self, input.scope, issues) end
        return issues
    end

    function Tr.TypeDecl:typecheck_tree_canonical_decl(scope)
        return self
    end

    function Tr.TypeDeclStruct:typecheck_tree_canonical_decl(scope)
        local fields = {}
        for i, f in ipairs(self.fields or {}) do fields[i] = Ty.FieldDecl(f.field_name, canonical_type(scope, f.ty)) end
        return Tr.TypeDeclStruct(self.name, fields)
    end

    function Tr.TypeDeclUnion:typecheck_tree_canonical_decl(scope)
        local fields = {}
        for i, f in ipairs(self.fields or {}) do fields[i] = Ty.FieldDecl(f.field_name, canonical_type(scope, f.ty)) end
        return Tr.TypeDeclUnion(self.name, fields)
    end

    function Tr.TypeDeclTaggedUnionSugar:typecheck_tree_canonical_decl(scope)
        local variants = {}
        for i, v in ipairs(self.variants or {}) do
            local fields = {}
            for j, f in ipairs(v.fields or {}) do fields[j] = Ty.FieldDecl(f.field_name, canonical_type(scope, f.ty)) end
            variants[i] = Ty.VariantDecl(v.name, canonical_type(scope, v.payload), fields)
        end
        return Tr.TypeDeclTaggedUnionSugar(self.name, variants)
    end

    function Tr.TypeDeclHandle:typecheck_tree_canonical_decl(scope)
        return self
    end

    function Tr.ItemType:typecheck_tree_item(input)
        local t = self.t:typecheck_tree_canonical_decl(input.scope)
        local issues = t:typecheck_tree_item_issues(input)
        return Check.TypeItemResult({ Tr.ItemType(t) }, issues)
    end

    function Tr.ItemRegion:typecheck_tree_item(input)
        local region = canonical_region(input.scope, self.region)
        local issues = region:typecheck_tree_signature_issues(input)
        if #(input.scope.facts.region_bundles or {}) > 0 then
            return Check.TypeItemResult({}, issues)
        end
        local region_scope = input.scope:typecheck_tree_add_params("region:" .. tostring(region.name), region.params)
        local stmt_input = region_scope:typecheck_tree_stmt_input(Ty.TScalar(C.ScalarVoid), Check.TypeYieldNone)
        local typed_contracts, contract_issues = type_contracts(region.contracts or {}, stmt_input)
        append_all(issues, contract_issues)
        region = schema.with(region, { contracts = typed_contracts })
        local region_id = "region:" .. tostring(region.name)
        local typed_region = Tr.ControlStmtRegion(region_id, region.entry, region.blocks):typecheck_tree_control_stmt_region(Check.TypeControlInput(stmt_input, region_id))
        append_all(issues, typed_region.issues)
        local runtime_bindings = {}
        for i = 1, #region.params do
            local p = region.params[i]
            local b = B.Binding(C.Id("region-param:" .. region.name .. ":" .. p.name), p.name, p.ty, B.BindingRoleArg(i - 1))
            runtime_bindings[#runtime_bindings + 1] = B.ValueEntry(p.name, b)
        end
        local cont_targets = {}
        for i = 1, #(region.conts or {}) do cont_targets[region.conts[i].name] = true end
        check_owned_control_region(typed_region.region, issues, runtime_bindings, cont_targets)
        return Check.TypeItemResult({}, issues)
    end

    function type_item(node, ...)
        return node:typecheck_tree_item(...)
    end

    function Tr.Item:typecheck_tree_diagnostic_name()
        return nil
    end

    function Tr.ItemFunc:typecheck_tree_diagnostic_name()
        return self.func and self.func.name or nil
    end

    function Tr.ItemRegion:typecheck_tree_diagnostic_name()
        return self.region and self.region.name or nil
    end

    function Tr.ItemType:typecheck_tree_diagnostic_name()
        return self.t and self.t.name or nil
    end

    function Tr.ItemExtern:typecheck_tree_diagnostic_name()
        return self.func and self.func.name or nil
    end

    function Tr.ItemConst:typecheck_tree_diagnostic_name()
        return self.c and self.c.name or nil
    end

    function Tr.ItemStatic:typecheck_tree_diagnostic_name()
        return self.s and self.s.name or nil
    end

    local function item_diagnostic_name(item)
        return item:typecheck_tree_diagnostic_name()
    end

    function Tr.ControlReject:typecheck_tree_report(region)
        return Tr.ControlRejectExplanation("E0405", "irreducible control flow", {
            "region: " .. tostring(region),
            self.reason or "irreducible cycle detected",
            "control flow is irreducible when no block dominates the others - restructure so one block is the single entry point",
        }, {
            "add a dispatch block that dominates all other blocks in this region",
        })
    end

    function Tr.ControlRejectMissingJumpArg:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        local name = tostring(self.name)
        return Tr.ControlRejectExplanation("E0404", "jump to `" .. label .. "` is missing argument `" .. name .. "`", {
            "region: " .. tostring(region),
            "target block `" .. label .. "` declares parameter `" .. name .. "`, but this jump does not provide it",
        }, {
            "pass `" .. name .. " = ...` at the jump, or rename the target block parameter to match the existing argument",
        })
    end

    function Tr.ControlRejectExtraJumpArg:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        local name = tostring(self.name)
        return Tr.ControlRejectExplanation("E0404", "jump to `" .. label .. "` has extra argument `" .. name .. "`", {
            "region: " .. tostring(region),
            "target block `" .. label .. "` has no parameter named `" .. name .. "`",
        }, {
            "remove the extra argument or add a matching block parameter",
        })
    end

    function Tr.ControlRejectDuplicateJumpArg:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0203", "duplicate jump argument `" .. tostring(self.name) .. "` for `" .. label .. "`", {
            "region: " .. tostring(region),
        }, {
            "provide each jump argument name only once",
        })
    end

    function Tr.ControlRejectJumpType:typecheck_tree_report(region)
        local Format = require("lalin.error.format")
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0301", "jump argument `" .. tostring(self.name) .. "` for `" .. label .. "` has wrong type", {
            "region: " .. tostring(region),
            "expected `" .. Format.type_name(self.expected) .. "`, got `" .. Format.type_name(self.actual) .. "`",
        }, {})
    end

    function Tr.ControlRejectMissingLabel:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0402", "missing jump target `" .. label .. "`", {
            "region: " .. tostring(region),
            "block `" .. label .. "` is not defined in this region",
        }, {})
    end

    function Tr.ControlRejectDuplicateLabel:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0203", "duplicate block label `" .. label .. "`", {
            "region: " .. tostring(region),
        }, {
            "rename one of the blocks",
        })
    end

    function Tr.ControlRejectUnterminatedBlock:typecheck_tree_report(region)
        local label = self.label and self.label.name or "?"
        return Tr.ControlRejectExplanation("E0406", "block `" .. label .. "` does not terminate", {
            "region: " .. tostring(region),
            "every block path must end in jump, yield, return, or trap",
        }, {})
    end

    function Tr.ControlRejectYieldOutsideRegion:typecheck_tree_report(region)
        return Tr.ControlRejectExplanation("E0407", "invalid yield in control region", {
            "region: " .. tostring(region),
            self.reason or "yield kind does not match this region",
        }, {})
    end

    function Tr.ControlRejectYieldType:typecheck_tree_report(region)
        local Format = require("lalin.error.format")
        return Tr.ControlRejectExplanation("E0301", "yield has wrong type", {
            "region: " .. tostring(region),
            "expected `" .. Format.type_name(self.expected) .. "`, got `" .. Format.type_name(self.actual) .. "`",
        }, {})
    end

    function Tr.ControlRejectUnknownVariant:typecheck_tree_report(region)
        return Tr.ControlRejectExplanation("E0201", "unknown switch variant `" .. tostring(self.variant_name or "?") .. "`", {
            "region: " .. tostring(region),
        }, {})
    end

    function Check.TypeIssueInvalidControl:typecheck_tree_fallback_control_report(region)
        return Tr.ControlRejectExplanation("E0405", "irreducible control flow", {
            "region: " .. tostring(region),
            "irreducible cycle detected",
            "control flow is irreducible when no block dominates the others - restructure so one block is the single entry point",
        }, {
            "add a dispatch block that dominates all other blocks in this region",
        })
    end

    function Check.TypeIssue:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E9999", "", tostring(self), {}, {})
    end

    function Check.TypeIssueInvalidControl:typecheck_tree_explanation()
        local reject = self.reject
        local region = self.region_id or (reject and reject.region_id) or "?"
        local report = reject and reject:typecheck_tree_report(region) or self:typecheck_tree_fallback_control_report(region)
        return Check.TypeIssueExplanation(report.code, "while checking control flow", report.primary, report.notes, report.suggestions)
    end

    local function invoke_target_name(target)
        local parts = {}
        for i, p in ipairs((target and target.path and target.path.parts) or {}) do parts[#parts + 1] = p.text end
        return table.concat(parts, ".")
    end

    function Tr.RegionInvokeMissingTarget:typecheck_tree_report()
        local name = invoke_target_name(self.target)
        return Check.TypeIssueExplanation("E0408", "while expanding region invocation", "unknown region `" .. name .. "`", {
            "region invocations must target a region declaration visible in the module",
        }, {})
    end

    function Tr.RegionInvokeArgCount:typecheck_tree_report()
        return Check.TypeIssueExplanation("E0408", "while expanding region invocation", "region argument count mismatch", {
            "expected " .. tostring(self.expected) .. " data argument(s), got " .. tostring(self.actual),
        }, {})
    end

    function Tr.RegionInvokeMissingWire:typecheck_tree_report()
        return Check.TypeIssueExplanation("E0408", "while expanding region invocation", "missing continuation wiring `" .. tostring(self.cont and self.cont.name or "?") .. "`", {
            "every region continuation must be wired at the call site",
        }, {})
    end

    function Tr.RegionInvokeExtraWire:typecheck_tree_report()
        return Check.TypeIssueExplanation("E0408", "while expanding region invocation", "unknown continuation wiring `" .. tostring(self.name or "?") .. "`", {}, {})
    end

    function Tr.RegionInvokeDuplicateWire:typecheck_tree_report()
        return Check.TypeIssueExplanation("E0203", "while expanding region invocation", "duplicate continuation wiring `" .. tostring(self.name or "?") .. "`", {}, {})
    end

    function Tr.RegionInvokeCallFrameUnsupported:typecheck_tree_report()
        return Check.TypeIssueExplanation("E0408", "while expanding region invocation", "region `call` frame expansion is not implemented yet", {
            "use `emit` for CFG splicing until region call frames are implemented",
        }, {})
    end

    function Check.TypeIssueRegionInvoke:typecheck_tree_explanation()
        return self.reject:typecheck_tree_report()
    end

    function Check.TypeIssueMissingJumpTarget:typecheck_tree_explanation()
        local label = (self.label and self.label.name) or "?"
        return Check.TypeIssueExplanation("E0402", "while checking control flow", "missing jump target `" .. label .. "`", {
            "block `" .. label .. "` is not defined in this region",
        }, {})
    end

    function Check.TypeIssueMissingJumpArg:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0404", "while checking control flow", "jump argument count mismatch for `" .. tostring(self.name or "?") .. "`", {
            "check that the number of arguments passed to the jump matches the block parameters",
        }, {})
    end

    function Check.TypeIssueExtraJumpArg:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0404", "while checking control flow", "jump argument count mismatch for `" .. tostring(self.name or "?") .. "`", {
            "check that the number of arguments passed to the jump matches the block parameters",
        }, {})
    end

    function Check.TypeIssueDuplicateJumpArg:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0203", "while checking control flow", "duplicate jump argument `" .. tostring(self.name or "?") .. "`", {}, {
            "remove the duplicate argument or rename one of them",
        })
    end

    function Check.TypeIssueUnexpectedYield:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0407", "while type-checking", "`yield` used outside a region", {
            "`yield` can only be used inside a `region` or a `return region: T` expression",
        }, {
            "did you mean `return`? Functions use `return`, not `yield`",
        })
    end

    function Check.TypeIssueUnknownVariant:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        return Check.TypeIssueExplanation("E0201", "while resolving names", "unknown variant `" .. tostring(self.variant_name or "?") .. "` in type `" .. Format.type_name(self.type_name) .. "`", {}, {})
    end

    function Check.TypeIssueVariantBindCount:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0306", "while type-checking a variant arm",
            "variant arm `" .. tostring(self.variant_name or "?") .. "` expected " .. tostring(self.expected) .. " payload binds, got " .. tostring(self.actual), {}, {})
    end

    function Check.TypeIssueVariantPayloadUnsupported:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0307", "while type-checking a variant payload",
            "variant `" .. tostring(self.variant_name or "?") .. "` has " .. tostring(self.field_count) .. " payload fields; parsed multi-field payloads are unsupported", {}, {})
    end

    function Check.TypeIssueVariantPayloadMismatch:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0301", "while type-checking", "variant payload mismatch for `" .. tostring(self.variant_name or "?") .. "`", {}, {})
    end

    function Check.TypeIssueDuplicateVariant:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0203", "while checking declarations", "duplicate variant `" .. tostring(self.variant_name or "?") .. "`", {}, {})
    end

    function Check.TypeIssueDomainContract:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0410", "while checking handle domain contract", "handle `" .. tostring(self.handle or "?") .. "` declares domain `" .. tostring(self.domain or "?") .. "` but the domain contract is not satisfied", {
            tostring(self.reason or "domain contract failed"),
        }, {
            "define a qualified resolver region on the domain taking `(self, handle)` and granting a `lease(\"self\", ptr(Target))` on its success exit",
            "classify qualified domain operations with readonly/preserve or invalidate/writeonly receiver access",
        })
    end

    function Check.TypeIssueNotCallable:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local ty = Format.type_name(self.ty)
        return Check.TypeIssueExplanation("E0302", "while type-checking a call", "type `" .. ty .. "` is not callable", {
            "only `func` and `closure` types can be called",
        }, {
            "did you mean to index? write `expr[idx]` for element access",
        })
    end

    function Check.TypeIssueNotIndexable:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local ty = Format.type_name(self.ty)
        return Check.TypeIssueExplanation("E0303", "while type-checking an index", "type `" .. ty .. "` is not indexable", {
            "only `view`, `ptr`, and `array` types support indexing",
        }, {
            "if you meant to access a field, use `.` syntax: `expr.field`",
        })
    end

    function Check.TypeIssueNotPointer:typecheck_tree_explanation()
        return self:typecheck_tree_explanation_not_indexable()
    end

    function Check.TypeIssueNotPointer:typecheck_tree_explanation_not_indexable()
        local Format = require("lalin.error.format")
        local ty = Format.type_name(self.ty)
        return Check.TypeIssueExplanation("E0303", "while type-checking an index", "type `" .. ty .. "` is not indexable", {
            "only `view`, `ptr`, and `array` types support indexing",
        }, {
            "if you meant to access a field, use `.` syntax: `expr.field`",
        })
    end

    function Check.TypeIssueArgCount:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0305", "while type-checking", (self.site or "call") .. " expected " .. tostring(self.expected) .. " arguments, got " .. tostring(self.actual), {}, {
            "check the function signature and add or remove arguments",
        })
    end

    function Check.TypeIssueInvalidBinary:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local lhs = Format.type_name(self.lhs)
        local rhs = Format.type_name(self.rhs)
        local notes = { "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" }
        local suggestions = {}
        if lhs == "bool" and rhs == "bool" and (op == "+" or op == "-" or op == "*" or op == "/") then
            notes[#notes + 1] = "arithmetic operators require numeric types (i8, i16, i32, ...)"
            suggestions[#suggestions + 1] = "for boolean logic, use `and` / `or`: `a and b` or `a or b`"
        end
        if lhs ~= rhs then notes[#notes + 1] = "both operands must have the same type" end
        return Check.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid operator `" .. op .. "`", notes, suggestions)
    end

    function Check.TypeIssueInvalidCompare:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local lhs = Format.type_name(self.lhs)
        local rhs = Format.type_name(self.rhs)
        local notes = { "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" }
        if lhs ~= rhs then notes[#notes + 1] = "both operands must have the same type" end
        return Check.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid operator `" .. op .. "`", notes, {})
    end

    function Check.TypeIssueInvalidLogic:typecheck_tree_explanation()
        return self:typecheck_tree_explanation_compare_like()
    end

    function Check.TypeIssueInvalidLogic:typecheck_tree_explanation_compare_like()
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local lhs = Format.type_name(self.lhs)
        local rhs = Format.type_name(self.rhs)
        local notes = { "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" }
        if lhs ~= rhs then notes[#notes + 1] = "both operands must have the same type" end
        return Check.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid operator `" .. op .. "`", notes, {})
    end

    function Check.TypeIssueUnresolvedValue:typecheck_tree_explanation()
        return Check.TypeIssueExplanation("E0201", "while resolving names", "unresolved name `" .. tostring(self.name or "?") .. "`", {
            "`" .. tostring(self.name or "?") .. "` is not defined in this scope",
        }, {})
    end

    function Check.TypeIssueUnresolvedPath:typecheck_tree_explanation()
        local parts = {}
        for i = 1, #((self.path and self.path.parts) or {}) do parts[i] = self.path.parts[i].text end
        local path_text = #parts > 0 and table.concat(parts, ".") or "?"
        local first_segment = parts[1] or "?"
        return Check.TypeIssueExplanation("E0202", "while resolving names", "unresolved path `" .. path_text .. "`", {
            "the first segment `" .. first_segment .. "` could not be resolved",
        }, {})
    end

    function Check.TypeIssueExpected:typecheck_tree_explanation()
        local Format = require("lalin.error.format")
        local site = self.site or "expression"
        local expected = Format.type_name(self.expected)
        local actual = Format.type_name(self.actual)
        local notes = {}
        local suggestions = {}

        if site:find("call") then
            notes[#notes + 1] = "this argument has type `" .. actual .. "`, but the function expects `" .. expected .. "`"
        elseif site:find("let ") or site:find("var ") then
            notes[#notes + 1] = "the initializer has type `" .. actual .. "`, but the variable is declared as `" .. expected .. "`"
        elseif site:find("return") then
            notes[#notes + 1] = "the return value has type `" .. actual .. "`, but the function returns `" .. expected .. "`"
        elseif site:find("yield") then
            notes[#notes + 1] = "the yielded value has type `" .. actual .. "`, but the region yields `" .. expected .. "`"
        elseif site:find("set") then
            notes[#notes + 1] = "the assigned value has type `" .. actual .. "`, but the target has type `" .. expected .. "`"
        elseif site:find("if cond") or site:find("select cond") then
            notes[#notes + 1] = "the condition has type `" .. actual .. "`, but the condition must be `bool`"
        elseif site:find("if branches") or site:find("select branches") then
            notes[#notes + 1] = "both branches must have the same type; the then-branch is `" .. actual .. "`, the else-branch is `" .. expected .. "`"
        elseif site:find("index") then
            notes[#notes + 1] = "indexing requires an integer type, got `" .. actual .. "`"
        elseif site:find("view data") then
            notes[#notes + 1] = "view data must be a `ptr` or `view`, got `" .. actual .. "`"
        elseif site:find("view len") or site:find("view stride") or site:find("view window") or site:find("bounds") or site:find("window_bounds") then
            notes[#notes + 1] = "expected `" .. expected .. "`, got `" .. actual .. "`"
        elseif site:find("disjoint") then
            notes[#notes + 1] = "disjoint contract requires `ptr` or `view`, got `" .. actual .. "`"
        elseif site:find("same_len") then
            notes[#notes + 1] = "same_len contract requires `view`, got `" .. actual .. "`"
        elseif site:find("memory contract") then
            notes[#notes + 1] = "memory contract requires `ptr` or `view`, got `" .. actual .. "`"
        elseif site:find("atomic") then
            notes[#notes + 1] = "expected `" .. expected .. "`, got `" .. actual .. "`"
        elseif site:find("block param") then
            notes[#notes + 1] = "block parameter initializer has type `" .. actual .. "`, but the parameter is declared as `" .. expected .. "`"
        elseif site:find("assert") then
            notes[#notes + 1] = "assert condition must be `bool`, got `" .. actual .. "`"
        elseif site:find("switch key") then
            notes[#notes + 1] = "switch key has type `" .. actual .. "`, but the switch expression is `" .. expected .. "`"
        elseif site:find("switch arm") then
            notes[#notes + 1] = "switch arm has type `" .. actual .. "`, but the default arm is `" .. expected .. "`"
        elseif site:find("array elem") then
            notes[#notes + 1] = "array element has type `" .. actual .. "`, but the array expects `" .. expected .. "`"
        elseif site:find("len") then
            notes[#notes + 1] = "`len` requires a `view`, got `" .. actual .. "`"
        elseif site:find("const") or site:find("static") then
            notes[#notes + 1] = "the initializer has type `" .. actual .. "`, but the declaration is `" .. expected .. "`"
        else
            notes[#notes + 1] = "expected `" .. expected .. "`, got `" .. actual .. "`"
        end

        if actual == "bool" and expected ~= "bool" then
            suggestions[#suggestions + 1] = "to convert a boolean to an integer, use a conditional: `select(flag, 1, 0)`"
        elseif actual == "f64" and self.expected:typecheck_tree_is_integer_scalar() then
            suggestions[#suggestions + 1] = "to convert a float to an integer, use `as(i32, value)`"
        elseif self.actual:typecheck_tree_is_integer_scalar() and expected == "f64" then
            suggestions[#suggestions + 1] = "to convert an integer to a float, use `as(f64, value)`"
        end

        return Check.TypeIssueExplanation("E0301", "while type-checking", "type mismatch", notes, suggestions)
    end

    function Check.TypeIssueInvalidUnary:typecheck_tree_explanation()
        return self.reason:typecheck_tree_explanation(self.ty)
    end

    function Check.TypeUnaryIssueReason:typecheck_tree_explanation(ty)
        local Format = require("lalin.error.format")
        local ty_text = Format.type_name(ty)
        return Check.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid unary operator for type `" .. ty_text .. "`", {}, {})
    end

    function Check.TypeUnaryInvalidOperator:typecheck_tree_explanation(ty)
        local Format = require("lalin.error.format")
        local op = Format.op_symbol(self.op)
        local ty_text = Format.type_name(ty)
        local notes = {}
        local suggestions = {}
        if op == "not" then
            notes[#notes + 1] = "`not` requires a `bool` operand, got `" .. ty_text .. "`"
        else
            notes[#notes + 1] = "operator `" .. op .. "` is not defined for type `" .. ty_text .. "`"
            notes[#notes + 1] = "arithmetic operators require numeric types (i8, i16, i32, ...)"
        end
        if ty_text == "bool" and op ~= "not" then suggestions[#suggestions + 1] = "for boolean logic, use `not`: `not value`" end
        return Check.TypeIssueExplanation("E0304", "while type-checking an expression", "invalid unary operator `" .. op .. "` for type `" .. ty_text .. "`", notes, suggestions)
    end

    local function unary_reason_report(primary, notes, suggestions)
        return Check.TypeIssueExplanation("E0304", "while type-checking an expression", primary, notes or {}, suggestions or {})
    end

    function Check.TypeUnaryLeaseEscapeReturn:typecheck_tree_explanation(ty)
        local ty_text = require("lalin.error.format").type_name(ty)
        return unary_reason_report("lease escapes through return", {
            "lease value `" .. ty_text .. "` is temporary access produced by a store or boundary",
            "leases may access memory inside their dynamic extent but may not be returned as durable identity",
        }, { "return a handle or copied scalar data instead, or keep the pointer parameter marked `noescape`" })
    end

    function Check.TypeUnaryLeaseEscapeYield:typecheck_tree_explanation(ty)
        local ty_text = require("lalin.error.format").type_name(ty)
        return unary_reason_report("lease escapes through yield", {
            "yielding `" .. ty_text .. "` would move temporary access outside the granting region",
        }, { "yield a handle/status protocol, not the lease pointer/view" })
    end

    function Check.TypeUnaryLeaseEscapeStore:typecheck_tree_explanation(ty)
        return unary_reason_report("lease escapes through store", {
            "storing `" .. require("lalin.error.format").type_name(ty) .. "` would make temporary access durable",
        }, { "store the handle, or copy the data through the lease instead" })
    end

    function Check.TypeUnaryLeaseEscapeCall:typecheck_tree_explanation(ty)
        return unary_reason_report("lease passed to retaining parameter", {
            "a lease can only be passed to another `lease` or `noescape` parameter",
            "plain `ptr`/`view` parameters are treated as possibly retained",
        }, { "mark the callee parameter `noescape`, or change it to `lease ptr(T)` / `lease view(T)`" })
    end

    function Check.TypeUnaryLeaseInvalidatingCall:typecheck_tree_explanation(ty)
        return unary_reason_report("call may invalidate store while lease is live", {
            "live lease `" .. require("lalin.error.format").type_name(ty) .. "` may refer to storage that this call can move, free, compact, clear, or reuse",
            "`readonly` and `preserve` parameters keep leases valid; unannotated pointer/view parameters are conservative invalidators",
        }, { "end the lease scope before the call, call a `preserve`/`readonly` API, or use `lease(store)` to associate the lease with the correct store" })
    end

    function Check.TypeUnaryLeaseEscapeAggregate:typecheck_tree_explanation(ty)
        return unary_reason_report("lease captured in aggregate", {
            "aggregates can outlive the current access extent, so they cannot contain `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "store a handle or copied data instead of the lease" })
    end

    function Check.TypeUnaryRegionCallLeasePayload:typecheck_tree_explanation(ty)
        return unary_reason_report("cannot call region because continuation payload contains a lease", {
            "continuation payload `" .. require("lalin.error.format").type_name(ty) .. "` is temporary access and cannot be packed into the generated region-call result",
        }, { "use `emit` so temporary access stays in control flow" })
    end

    function Check.TypeUnaryLeaseEscapeDurable:typecheck_tree_explanation(ty)
        return unary_reason_report("lease appears in durable type position", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` is temporary access, not storable data",
            "leases may appear in function/block/continuation parameters, not durable fields/results/statics",
        }, { "use a handle type for durable identity, or a plain pointer only at an unchecked ABI boundary" })
    end

    function Check.TypeUnaryOwnedDropped:typecheck_tree_explanation(ty)
        return unary_reason_report("owned obligation is not discharged", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` must be transferred to an owned parameter/result or consumed by a closing protocol",
            "owned values do not have destructors and cannot silently fall out of scope",
        }, { "jump/return/yield/pass the owner to an `owned` slot, or call the explicit close/retire region" })
    end

    function Check.TypeUnaryOwnedUseAfterMove:typecheck_tree_explanation(ty)
        return unary_reason_report("owned value used after transfer", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` was already consumed by an ownership transfer",
        }, { "thread the returned/re-yielded owner forward if the protocol preserves the obligation" })
    end

    function Check.TypeUnaryOwnedObservedWithoutTransfer:typecheck_tree_explanation(ty)
        return unary_reason_report("owned value used without an ownership contract", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` is linear authority and cannot be copied or borrowed as a plain value",
        }, { "make the callee parameter `owned`, or use a protocol that returns the owner on every preserving edge" })
    end

    function Check.TypeUnaryOwnedCapturedDurable:typecheck_tree_explanation(ty)
        return unary_reason_report("owned value captured in durable storage", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` is a CFG obligation, not storable data",
        }, { "store the plain handle separately and keep the owned obligation in control flow" })
    end

    function Check.TypeUnaryOwnedBranchMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("branches leave different owned obligations live", {
            "all continuing paths must preserve the same live owned set",
        }, { "move the transfer before the branch, or return/jump/yield on the consuming path" })
    end

    function Check.TypeUnaryOwnedVarCellUnsupported:typecheck_tree_explanation(ty)
        return unary_reason_report("owned values cannot live in mutable cells", {
            "`var owned T` needs explicit take/put semantics and is rejected",
        }, { "use `let` ownership threading through CFG parameters" })
    end

    function Check.TypeUnaryOwnedRegionCallPayload:typecheck_tree_explanation(ty)
        return unary_reason_report("owned payload cannot use expression-style region call", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` cannot be packed into the generated region-call result aggregate",
        }, { "use `emit`/explicit continuations so ownership stays in CFG" })
    end

    function Check.TypeUnaryOwnedEmitTargetMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("owned continuation payload has no matching target parameter", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` must land in a target block/continuation parameter with the same owned type and name",
        }, { "add the owned parameter to the filled target, or consume the owner inside the emitted fragment" })
    end

    function Check.TypeUnaryOwnedInvalidComposition:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid owned type composition", {
            "`" .. require("lalin.error.format").type_name(ty) .. "` mixes ownership authority with access modifiers or temporary leases",
        }, { "own the durable handle/resource token; borrow access through a protocol that returns the owner" })
    end

    function Check.TypeUnaryHandleCast:typecheck_tree_explanation(ty)
        return unary_reason_report("handle representation is opaque", {
            "handle `" .. require("lalin.error.format").type_name(ty) .. "` is not its integer representation in safe casts",
            "ordinary `as(...)` cannot convert handles to or from raw scalars",
        }, { "resolve the handle through a store region, or use trusted `repr(handle)` / `Handle.from_repr(raw)` inside store implementation code" })
    end

    function Check.TypeUnaryHandleRepr:typecheck_tree_explanation(ty)
        return unary_reason_report("`repr` expects a handle", {
            "`repr(value)` is the explicit trusted handle-to-scalar boundary",
            "the value has type `" .. require("lalin.error.format").type_name(ty) .. "`, not a handle",
        })
    end

    function Check.TypeUnaryHandleTargetMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver returns a lease to the wrong target", {
            "a handle with a `target` fact may only grant leases to that target type",
            "the continuation payload has type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "change the lease payload target, or declare a different handle target fact" })
    end

    function Check.TypeUnaryHandleDomainMissing:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver does not take the owning domain", {
            "a handle with a `domain` fact must be resolved through that store/domain parameter",
            "the continuation payload has type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "add a `readonly` or `preserve` `ptr(Store)` parameter matching the handle domain" })
    end

    function Check.TypeUnaryHandleDomainAccess:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver domain parameter does not preserve leases", {
            "resolver regions that grant leases must take the owning domain as `readonly` or `preserve`",
            "bare pointer/view parameters are conservative invalidators",
        }, { "mark the domain parameter `readonly` or `preserve`" })
    end

    function Check.TypeUnaryHandleLeaseOriginMissing:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver lease is not tied to its store parameter", {
            "a handle resolver must return `lease(store) ptr(Target)` or `lease(store) view(Target)`",
            "anonymous leases cannot participate in store invalidation checks",
        }, { "write the lease as `lease(store_param) ptr(T)`" })
    end

    function Check.TypeUnaryHandleLeaseOriginMismatch:typecheck_tree_explanation(ty)
        return unary_reason_report("handle resolver lease is tied to the wrong store parameter", {
            "the lease origin must name the `readonly` or `preserve` domain parameter for the handle",
            "the continuation payload has type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, { "change the `lease(...)` origin to the matching store parameter" })
    end

    function Check.TypeUnaryAtomicRmwPointerOp:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid atomic read-modify-write operation", {
            "atomic read-modify-write arithmetic is not defined for pointer type `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, {})
    end

    function Check.TypeUnaryAtomicRmwBoolAddSub:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid atomic read-modify-write operation", {
            "atomic add/sub is not defined for `bool`",
        }, {})
    end

    function Check.TypeUnaryAtomicInvalidValue:typecheck_tree_explanation(ty)
        return unary_reason_report("invalid atomic value type", {
            (self.site or "atomic") .. " requires an atomic scalar or pointer type, got `" .. require("lalin.error.format").type_name(ty) .. "`",
        }, {})
    end

    local function emit_item_issues(collector, base_analysis, item, issues)
        if not collector or #issues == 0 then return end
        local item_name = item_diagnostic_name(item)
        local item_analysis = item_name and base_analysis and base_analysis.item_analyses and base_analysis.item_analyses[item_name]
        local saved = collector.analysis_ctx
        if item_analysis then
            collector.analysis_ctx = {
                uri = item_analysis.uri,
                source_text = item_analysis.source_text,
                source_cache = base_analysis.source_cache or item_analysis.source_cache,
                anchors = item_analysis.anchors or {},
                document = item_analysis.document,
                item_analyses = base_analysis.item_analyses,
            }
        end
        for i = 1, #issues do collector:emit(issues[i], "typecheck") end
        collector.analysis_ctx = saved
    end

    local function type_ref_path(name)
        return Ty.TNamed(Ty.TypeRefPath(C.Path({ C.Name(name) })))
    end

    function Tr.RegionInvokeTarget:typecheck_tree_region_target_key()
        local parts = {}
        for i, p in ipairs((self.path and self.path.parts) or {}) do parts[#parts + 1] = p.text end
        return table.concat(parts, ".")
    end

    function Tr.RegionProtocol:payload_for_cont(cont)
        for i = 1, #(self.payloads or {}) do
            if self.payloads[i].cont.name == cont.name then return self.payloads[i] end
        end
        return nil
    end

    function Tr.RegionSeal:payload_for_cont(cont)
        return self.protocol:payload_for_cont(cont)
    end

    local function find_jump_arg(args, param, index)
        for i, arg in ipairs(args or {}) do
            if arg.name == param.name then return arg end
        end
        return (args or {})[index]
    end

    function Tr.RegionSeal:return_label_for_cont(cont)
        return Tr.BlockLabel("__seal_return_" .. tostring(cont.name))
    end

    function Tr.RegionSeal:sealed_return_for_cont_args(cont, args)
        local payload = self:payload_for_cont(cont)
        local ctor_args = {}
        if payload ~= nil then
            local fields = {}
            for i, p in ipairs(cont.params or {}) do
                local arg = find_jump_arg(args, p, i)
                fields[#fields + 1] = Tr.FieldInit(p.name, arg and arg.value or Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(p.name)), 0)
            end
            ctor_args[1] = Tr.ExprAgg(Tr.ExprSurface, type_ref_path(payload.type_name), fields)
        end
        return Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprCtor(Tr.ExprSurface, self.protocol.result_type_name, cont.name, ctor_args))
    end

    function Tr.RegionSeal:sealed_return_for_jump(stmt)
        return self:sealed_return_for_cont_args(stmt.cont, stmt.args)
    end

    function Tr.Stmt:rewrite_tree_region_seal_stmt(seal, all_seals)
        return self
    end

    function Tr.StmtJumpCont:rewrite_tree_region_seal_stmt(seal, all_seals)
        return seal:sealed_return_for_jump(self)
    end

    function Tr.StmtIf:rewrite_tree_region_seal_stmt(seal, all_seals)
        local then_body, else_body = {}, {}
        for i, s in ipairs(self.then_body or {}) do then_body[i] = s:rewrite_tree_region_seal_stmt(seal, all_seals) end
        for i, s in ipairs(self.else_body or {}) do else_body[i] = s:rewrite_tree_region_seal_stmt(seal, all_seals) end
        return Tr.StmtIf(self.h, self.cond, then_body, else_body)
    end

    function Tr.StmtSwitch:rewrite_tree_region_seal_stmt(seal, all_seals)
        local arms, variant_arms, default_body = {}, {}, {}
        for i, arm in ipairs(self.arms or {}) do
            local body = {}
            for j, s in ipairs(arm.body or {}) do body[j] = s:rewrite_tree_region_seal_stmt(seal, all_seals) end
            arms[i] = Tr.SwitchStmtArm(arm.key, body)
        end
        for i, arm in ipairs(self.variant_arms or {}) do
            local body = {}
            for j, s in ipairs(arm.body or {}) do body[j] = s:rewrite_tree_region_seal_stmt(seal, all_seals) end
            variant_arms[i] = Tr.SwitchVariantStmtArm(arm.variant_name, arm.binds, body)
        end
        for i, s in ipairs(self.default_body or {}) do default_body[i] = s:rewrite_tree_region_seal_stmt(seal, all_seals) end
        return Tr.StmtSwitch(self.h, self.value, arms, variant_arms, default_body)
    end

    function Tr.RegionWireTarget:rewrite_tree_region_seal_wire_target(seal)
        return self
    end

    function Tr.RegionWireCont:rewrite_tree_region_seal_wire_target(seal)
        return Tr.RegionWireBlock(seal:return_label_for_cont(self.cont), self.args or {})
    end

    function Tr.RegionContWire:rewrite_tree_region_seal_wire(seal)
        return Tr.RegionContWire(self.name, self.target:rewrite_tree_region_seal_wire_target(seal))
    end

    local function find_seal_for_target(seals, target)
        for i = 1, #(seals or {}) do
            if seals[i].target:typecheck_tree_same_region_target(target) then return seals[i] end
        end
        return nil
    end

    local function find_bundle_member(bundle, target)
        for i = 1, #(bundle and bundle.members or {}) do
            if bundle.members[i].seal.target:typecheck_tree_same_region_target(target) then return bundle.members[i] end
        end
        return nil
    end

    function Tr.RegionWireTarget:forwards_tree_region_cont_name(name)
        return false
    end

    function Tr.RegionWireCont:forwards_tree_region_cont_name(name)
        return self.cont.name == name
    end

    local function find_wire_by_name(wiring, name)
        for i = 1, #(wiring or {}) do
            if wiring[i].name == name then return wiring[i] end
        end
        return nil
    end

    function Tr.StmtRegionCall:forwards_tree_region_protocol_to(seal, all_seals)
        local target_seal = find_seal_for_target(all_seals or {}, self.target)
        if target_seal == nil or target_seal.protocol.key ~= seal.protocol.key then return nil end
        for i, cont in ipairs(target_seal.region.conts or {}) do
            local wire = find_wire_by_name(self.wiring, cont.name)
            if wire == nil or not wire.target:forwards_tree_region_cont_name(cont.name) then return nil end
        end
        return target_seal
    end

    function Tr.StmtRegionCall:rewrite_tree_region_seal_stmt(seal, all_seals)
        local tail_seal = self:forwards_tree_region_protocol_to(seal, all_seals)
        if tail_seal ~= nil then
            return Tr.StmtReturnValue(Tr.StmtSurface, Tr.ExprCall(Tr.ExprSurface, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(tail_seal.function_name)), self.args))
        end
        local wiring = {}
        for i, wire in ipairs(self.wiring or {}) do wiring[i] = wire:rewrite_tree_region_seal_wire(seal) end
        return Tr.StmtRegionCall(self.h, self.invoke_id, self.target, self.args, wiring)
    end

    function Tr.StmtRegionEmit:rewrite_tree_region_seal_stmt(seal, all_seals)
        local wiring = {}
        for i, wire in ipairs(self.wiring or {}) do wiring[i] = wire:rewrite_tree_region_seal_wire(seal) end
        return Tr.StmtRegionEmit(self.h, self.invoke_id, self.target, self.args, wiring)
    end

    function Tr.RegionSeal:rewrite_body_for_sealed_function(body, all_seals)
        local out = {}
        for i, stmt in ipairs(body or {}) do out[i] = stmt:rewrite_tree_region_seal_stmt(self, all_seals) end
        return out
    end

    function Tr.RegionProtocol:generated_type_items(all_seals)
        local items = {}
        for i, payload in ipairs(self.payloads or {}) do
            local fields = {}
            for j, p in ipairs(payload.cont.params or {}) do fields[j] = Ty.FieldDecl(p.name, p.ty) end
            items[#items + 1] = Tr.ItemType(Tr.TypeDeclStruct(payload.type_name, fields))
        end
        local variants = {}
        for i, payload in ipairs(self.payloads or {}) do
            variants[#variants + 1] = Ty.VariantDecl(payload.cont.name, type_ref_path(payload.type_name), {})
        end
        local seen = {}
        for i, payload in ipairs(self.payloads or {}) do seen[payload.cont.name] = true end
        for i, seal in ipairs(all_seals or {}) do
            if seal.protocol.key == self.key then
                for j, cont in ipairs(seal.region.conts or {}) do
                    if not seen[cont.name] then
                        variants[#variants + 1] = Ty.VariantDecl(cont.name, Ty.TScalar(C.ScalarVoid), {})
                        seen[cont.name] = true
                    end
                end
            end
        end
        items[#items + 1] = Tr.ItemType(Tr.TypeDeclTaggedUnionSugar(self.result_type_name, variants))
        return items
    end

    function Tr.RegionSeal:generated_func_item(all_seals)
        local entry = Tr.EntryControlBlock(self.region.entry.label, self.region.entry.params, self:rewrite_body_for_sealed_function(self.region.entry.body, all_seals))
        local blocks = {}
        for i, block in ipairs(self.region.blocks or {}) do
            blocks[i] = Tr.ControlBlock(block.label, block.params, self:rewrite_body_for_sealed_function(block.body, all_seals))
        end
        for i, cont in ipairs(self.region.conts or {}) do
            local args = {}
            for j, p in ipairs(cont.params or {}) do args[j] = Tr.JumpArg(p.name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(p.name))) end
            blocks[#blocks + 1] = Tr.ControlBlock(self:return_label_for_cont(cont), cont.params, { self:sealed_return_for_cont_args(cont, args) })
        end
        local body = {
            Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion("region-seal:" .. tostring(self.region.name), entry, blocks)),
        }
        local func = #(self.region.contracts or {}) > 0
            and Tr.FuncLocalContract(self.function_name, self.region.params, type_ref_path(self.protocol.result_type_name), self.region.contracts, body)
            or Tr.FuncLocal(self.function_name, self.region.params, type_ref_path(self.protocol.result_type_name), body)
        return Tr.ItemFunc(func)
    end

    function Tr.RegionSeal:generated_items(all_seals)
        return { self:generated_func_item(all_seals) }
    end

    local function sanitize_bundle_label(s)
        s = tostring(s or ""):gsub("[^%w_]", "_")
        if s == "" then s = "region" end
        if s:match("^%d") then s = "_" .. s end
        return s
    end

    local function bundle_target_name(target)
        local parts = {}
        for i = 1, #(target.path.parts or {}) do parts[#parts + 1] = target.path.parts[i].text end
        return table.concat(parts, "_")
    end

    function Tr.RegionBundleMember:label_for(label)
        return Tr.BlockLabel("__bundle_" .. sanitize_bundle_label(bundle_target_name(self.seal.target)) .. "_" .. tostring(label.name))
    end

    local function block_params_from_region_params(params)
        local out = {}
        for i, p in ipairs(params or {}) do out[i] = Tr.BlockParam(p.name, p.ty) end
        return out
    end

    local function jump_args_from_region_params(params)
        local out = {}
        for i, p in ipairs(params or {}) do out[i] = Tr.JumpArg(p.name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(p.name))) end
        return out
    end

    local function jump_args_for_region_call(params, args)
        local out = {}
        for i, p in ipairs(params or {}) do out[i] = Tr.JumpArg(p.name, (args or {})[i]) end
        return out
    end

    function Tr.RegionWireTarget:rewrite_tree_region_bundle_wire_target(root, member)
        return self
    end

    function Tr.RegionWireBlock:rewrite_tree_region_bundle_wire_target(root, member)
        return Tr.RegionWireBlock(member:label_for(self.label), self.args or {})
    end

    function Tr.RegionWireCont:rewrite_tree_region_bundle_wire_target(root, member)
        return Tr.RegionWireBlock(root:return_label_for_cont(self.cont), self.args or {})
    end

    function Tr.RegionContWire:rewrite_tree_region_bundle_wire(root, member)
        return Tr.RegionContWire(self.name, self.target:rewrite_tree_region_bundle_wire_target(root, member))
    end

    local function bundle_member_binding(member, binding)
        if binding == nil then return binding end
        return B.Binding(C.Id(tostring(member.local_namespace) .. ":" .. tostring(binding.id and binding.id.text or binding.name)), binding.name, binding.ty, binding.role)
    end

    function Tr.Stmt:rewrite_tree_region_bundle_stmt(root, member, bundle)
        return self
    end

    function Tr.StmtLet:rewrite_tree_region_bundle_stmt(root, member, bundle)
        return Tr.StmtLet(self.h, bundle_member_binding(member, self.binding), self.init)
    end

    function Tr.StmtVar:rewrite_tree_region_bundle_stmt(root, member, bundle)
        return Tr.StmtVar(self.h, bundle_member_binding(member, self.binding), self.init)
    end

    function Tr.StmtJump:rewrite_tree_region_bundle_stmt(root, member, bundle)
        return Tr.StmtJump(self.h, member:label_for(self.target), self.args)
    end

    function Tr.StmtJumpCont:rewrite_tree_region_bundle_stmt(root, member, bundle)
        return root:sealed_return_for_jump(self)
    end

    function Tr.StmtIf:rewrite_tree_region_bundle_stmt(root, member, bundle)
        local then_body, else_body = {}, {}
        for i, s in ipairs(self.then_body or {}) do then_body[i] = s:rewrite_tree_region_bundle_stmt(root, member, bundle) end
        for i, s in ipairs(self.else_body or {}) do else_body[i] = s:rewrite_tree_region_bundle_stmt(root, member, bundle) end
        return Tr.StmtIf(self.h, self.cond, then_body, else_body)
    end

    function Tr.StmtSwitch:rewrite_tree_region_bundle_stmt(root, member, bundle)
        local arms, variant_arms, default_body = {}, {}, {}
        for i, arm in ipairs(self.arms or {}) do
            local body = {}
            for j, s in ipairs(arm.body or {}) do body[j] = s:rewrite_tree_region_bundle_stmt(root, member, bundle) end
            arms[i] = Tr.SwitchStmtArm(arm.key, body)
        end
        for i, arm in ipairs(self.variant_arms or {}) do
            local body = {}
            for j, s in ipairs(arm.body or {}) do body[j] = s:rewrite_tree_region_bundle_stmt(root, member, bundle) end
            variant_arms[i] = Tr.SwitchVariantStmtArm(arm.variant_name, arm.binds, body)
        end
        for i, s in ipairs(self.default_body or {}) do default_body[i] = s:rewrite_tree_region_bundle_stmt(root, member, bundle) end
        return Tr.StmtSwitch(self.h, self.value, arms, variant_arms, default_body)
    end

    function Tr.StmtRegionEmit:rewrite_tree_region_bundle_stmt(root, member, bundle)
        local wiring = {}
        for i, wire in ipairs(self.wiring or {}) do wiring[i] = wire:rewrite_tree_region_bundle_wire(root, member) end
        return Tr.StmtRegionEmit(self.h, self.invoke_id, self.target, self.args, wiring)
    end

    function Tr.StmtRegionCall:rewrite_tree_region_bundle_stmt(root, member, bundle)
        local target_member = find_bundle_member(bundle, self.target)
        if target_member ~= nil and self:forwards_tree_region_protocol_to(member.seal, { target_member.seal }) ~= nil then
            return Tr.StmtJump(self.h, target_member.entry_label, jump_args_for_region_call(target_member.seal.region.params, self.args))
        end
        local wiring = {}
        for i, wire in ipairs(self.wiring or {}) do wiring[i] = wire:rewrite_tree_region_bundle_wire(root, member) end
        if target_member ~= nil then
            return Tr.StmtRegionEmit(self.h, self.invoke_id, self.target, self.args, wiring)
        end
        return Tr.StmtRegionCall(self.h, self.invoke_id, self.target, self.args, wiring)
    end

    function Tr.RegionBundleMember:generated_control_blocks(root, bundle)
        local blocks = {}
        local entry_member = schema.with(self, { local_namespace = tostring(self.local_namespace) .. ":entry" })
        local entry_body = {}
        for i, s in ipairs(self.seal.region.entry.body or {}) do entry_body[i] = s:rewrite_tree_region_bundle_stmt(root, entry_member, bundle) end
        blocks[#blocks + 1] = Tr.ControlBlock(self.entry_label, block_params_from_region_params(self.seal.region.params), entry_body)
        for i, block in ipairs(self.seal.region.blocks or {}) do
            local block_member = schema.with(self, { local_namespace = tostring(self.local_namespace) .. ":block:" .. tostring(block.label.name) })
            local body = {}
            for j, s in ipairs(block.body or {}) do body[j] = s:rewrite_tree_region_bundle_stmt(root, block_member, bundle) end
            blocks[#blocks + 1] = Tr.ControlBlock(self:label_for(block.label), block.params, body)
        end
        return blocks
    end

    function Tr.RegionBundle:generated_func_item()
        local root_member = find_bundle_member(self, self.root.target)
        local entry = Tr.EntryControlBlock(Tr.BlockLabel("__bundle_entry"), {}, {
            Tr.StmtJump(Tr.StmtSurface, root_member.entry_label, jump_args_from_region_params(self.root.region.params)),
        })
        local blocks = {}
        for i, member in ipairs(self.members or {}) do
            local generated = member:generated_control_blocks(self.root, self)
            for j = 1, #generated do blocks[#blocks + 1] = generated[j] end
        end
        for i, cont in ipairs(self.root.region.conts or {}) do
            local args = {}
            for j, p in ipairs(cont.params or {}) do args[j] = Tr.JumpArg(p.name, Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(p.name))) end
            blocks[#blocks + 1] = Tr.ControlBlock(self.root:return_label_for_cont(cont), cont.params, { self.root:sealed_return_for_cont_args(cont, args) })
        end
        return Tr.ItemFunc(Tr.FuncLocal(self.root.function_name, self.root.region.params, type_ref_path(self.root.protocol.result_type_name), {
            Tr.StmtControl(Tr.StmtSurface, Tr.ControlStmtRegion("region-bundle:" .. tostring(self.root.region.name), entry, blocks)),
        }))
    end

    function Tr.RegionBundle:generated_items()
        return { self:generated_func_item() }
    end

    function Tr.Module:with_tree_region_seals(module_name)
        local facts = self:typecheck_tree_module_facts(Check.TypeModuleFactsInput(module_name or module_type_api.module_name(self.h)))
        if #(facts.region_seals or {}) == 0 then return self end
        local items = clone_values(self.items)
        for i, protocol in ipairs(facts.region_protocols or {}) do
            local generated = protocol:generated_type_items(facts.region_seals)
            for j = 1, #generated do items[#items + 1] = generated[j] end
        end
        local bundled_by_target = {}
        for i, bundle in ipairs(facts.region_bundles or {}) do
            local generated = bundle:generated_items()
            for j = 1, #generated do items[#items + 1] = generated[j] end
            for j, member in ipairs(bundle.members or {}) do
                bundled_by_target[member.seal.target:typecheck_tree_region_target_key()] = true
            end
        end
        for i, seal in ipairs(facts.region_seals or {}) do
            if not bundled_by_target[seal.target:typecheck_tree_region_target_key()] then
                local generated = seal:generated_items(facts.region_seals)
                for j = 1, #generated do items[#items + 1] = generated[j] end
            end
        end
        return Tr.Module(self.h, items)
    end

    local function type_module_with_layout_env(module, extra_layout_env, target, collector, analysis_ctx)
        target = target or H.HostTargetModel(64, 64, H.HostEndianLittle)
        module = module:with_tree_region_seals(module_type_api.module_name(module.h))
        local base_env = module_type_api.env(module, target)
        local facts = module:typecheck_tree_module_facts(Check.TypeModuleFactsInput(base_env.module_name))
        local module_scope = Check.TypeValueScope(base_env.module_name, base_env.values, base_env.types, base_env.layouts, facts)
        module_scope = module_scope:typecheck_tree_with_layouts(merged_layouts(module_scope, extra_layout_env))
        local items = {}
        local issues = {}
        local input = Check.TypeItemInput(module_scope)
        for i = 1, #module.items do
            local item = module.items[i]
            local r = type_item(item, input)
            append_all(items, r.items)
            append_all(issues, r.issues)
            emit_item_issues(collector, analysis_ctx or {}, item, r.issues)
        end
        return Check.TypeModuleResult(Tr.Module(Tr.ModuleTyped(module_scope.module_name), items), issues, target)
    end

    function Tr.Module:typecheck_tree_module(extra_layout_env, target, collector, analysis_ctx)
        return type_module_with_layout_env(self, extra_layout_env, target, collector, analysis_ctx)
    end

    return {
        check_module = function(module, opts)
            opts = opts or {}
            local collector = opts.collector
            local analysis_ctx = opts.analysis_ctx or (collector and collector.analysis_ctx) or {}
            local result = opts.layout_env
                and type_module_with_layout_env(module, opts.layout_env, opts.target or opts.c_target, collector, analysis_ctx)
                or type_module_with_layout_env(module, nil, opts.target or opts.c_target, collector, analysis_ctx)
            if collector and not analysis_ctx.item_analyses then
                for i = 1, #result.issues do
                    collector:emit(result.issues[i], "typecheck")
                end
            end
            return result
        end,
    }
end

-----------------------------------------------------------------------------
-- explain_type_issue: explains a single TypeIssue
-----------------------------------------------------------------------------

local function explain_type_issue(issue, analysis)
	analysis = analysis or { anchors = {} }
	local resolvers = require("lalin.error.span_resolvers")
	local span = resolvers.typecheck_resolver(issue, analysis)
    local function message_list(lines)
        local out = {}
        for i = 1, #(lines or {}) do out[i] = { message = lines[i] } end
        return out
    end
    local report = issue:typecheck_tree_explanation()
    return { code = report.code, severity = "error", phase_context = report.phase_context,
        primary = { span = span, message = report.primary }, notes = message_list(report.notes), suggestions = message_list(report.suggestions) }
end

return setmetatable({
    explain_type_issue = explain_type_issue,
}, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
