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

local function append_all(out, xs)
    for i = 1, #xs do out[#out + 1] = xs[i] end
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

    local module_type_api = require("lalin.tree_module_type")(T)
    local control_api = require("lalin.tree_control_facts")(T)
    require("lalin.tree_type_methods")(T)
    require("lalin.tree_layout_methods")(T)
    require("lalin.tree_fact_methods")(T)
    local type_view
    local type_index_base
    local type_place
    local type_expr
    local type_expr_expect
    local type_stmt
    local type_stmt_body
    local type_control_stmt_region
    local type_control_expr_region
    local type_switch_key
    local type_func
    local type_item
    local type_module

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

    local function env_with_values(env, values)
        return B.Env(env.module_name, values, env.types, env.layouts)
    end

    local function env_add_value(env, entry)
        local values = clone_values(env.values)
        values[#values + 1] = entry
        return env_with_values(env, values)
    end

    local function ctx_with_env(ctx, env)
        return Tr.TypeCheckEnv(env, ctx.facts, ctx.return_ty, ctx.yield)
    end

    local function ctx_with_yield(ctx, yield)
        return Tr.TypeCheckEnv(ctx.env, ctx.facts, ctx.return_ty, yield)
    end

    local function env_lookup_value(env, name)
        for i = #env.values, 1, -1 do
            if env.values[i].name == name then return env.values[i].binding end
        end
        return nil
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

    local function named_ref(ty)
        return ty:typecheck_tree_named_ref()
    end

    local function path_leaf(ref)
        return ref:typecheck_tree_ref_leaf()
    end

    local function field_layout_for(env, ty, field_name)
        ty = canonical_type(env, ty)
        local ref = named_ref(ty)
        if ref == nil then return nil end
        for i = 1, #env.layouts do
            local layout = env.layouts[i]
            if layout:typecheck_tree_matches_ref(ref) then return layout:typecheck_tree_field_layout(field_name) end
        end
        return nil
    end

    local function is_bool(ty)
        return ty:typecheck_tree_is_bool()
    end

    local function is_numeric_scalar(ty)
        return ty:typecheck_tree_is_numeric_scalar()
    end

    local function is_integer_scalar(ty)
        return ty:typecheck_tree_is_integer_scalar()
    end

    local function is_float_scalar(ty)
        return ty:typecheck_tree_is_float_scalar()
    end

    local int_scalar_info = {
        [C.ScalarBool] = { bits = 1, signed = false },
        [C.ScalarI8] = { bits = 8, signed = true },
        [C.ScalarI16] = { bits = 16, signed = true },
        [C.ScalarI32] = { bits = 32, signed = true },
        [C.ScalarI64] = { bits = 64, signed = true },
        [C.ScalarU8] = { bits = 8, signed = false },
        [C.ScalarU16] = { bits = 16, signed = false },
        [C.ScalarU32] = { bits = 32, signed = false },
        [C.ScalarU64] = { bits = 64, signed = false },
        [C.ScalarIndex] = { bits = 64, signed = true },
    }

    local float_scalar_bits = {
        [C.ScalarF32] = 32,
        [C.ScalarF64] = 64,
    }

    local function semantic_cast_op(src_ty, dst_ty)
        local src, dst = scalar_kind(src_ty), scalar_kind(dst_ty)
        if src == nil or dst == nil then return C.MachineCastBitcast end
        if src == dst then return C.MachineCastIdentity end
        local si, di = int_scalar_info[src], int_scalar_info[dst]
        if si ~= nil and di ~= nil then
            if di.bits < si.bits then return C.MachineCastIreduce end
            if di.bits > si.bits then return si.signed and C.MachineCastSextend or C.MachineCastUextend end
            return C.MachineCastIdentity
        end
        local sf, df = float_scalar_bits[src], float_scalar_bits[dst]
        if sf ~= nil and df ~= nil then
            if df > sf then return C.MachineCastFpromote end
            if df < sf then return C.MachineCastFdemote end
            return C.MachineCastIdentity
        end
        if si ~= nil and df ~= nil then return si.signed and C.MachineCastSToF or C.MachineCastUToF end
        if sf ~= nil and di ~= nil then return di.signed and C.MachineCastFToS or C.MachineCastFToU end
        return C.MachineCastBitcast
    end

    local function surface_cast_to_machine_op(surface_op, src_ty, dst_ty)
        if surface_op == C.SurfaceCast then return semantic_cast_op(src_ty, dst_ty) end
        if surface_op == C.SurfaceTrunc then return C.MachineCastIreduce end
        if surface_op == C.SurfaceZExt then return C.MachineCastUextend end
        if surface_op == C.SurfaceSExt then return C.MachineCastSextend end
        if surface_op == C.SurfaceBitcast then return C.MachineCastBitcast end
        if surface_op == C.SurfaceSatCast then return C.MachineCastBitcast end
        return C.MachineCastBitcast
    end

    local function is_atomic_value_type(ty)
        return ty:typecheck_tree_is_atomic_value_type()
    end

    local function check_atomic_value_type(site, ty, issues)
        if not is_atomic_value_type(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(site, ty) end
    end

    local function check_atomic_rmw_value_type(op, ty, issues)
        check_atomic_value_type("atomic_rmw", ty, issues)
        if op == C.AtomicRmwXchg then return end
        if ty:typecheck_tree_rejects_atomic_rmw_arithmetic() then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("atomic_rmw pointer op", ty); return end
        if is_bool(ty) and (op == C.AtomicRmwAdd or op == C.AtomicRmwSub) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("atomic_rmw bool add/sub", ty) end
    end

    local function result_expr(expr, ty, issues)
        return Tr.TypeExprResult(expr, ty, issues or {})
    end

    local function result_place(place, ty, issues)
        return Tr.TypePlaceResult(place, ty, issues or {})
    end

    require("lalin.tree_expr_methods")(T)

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

    local function merge_env_layouts(env, extra_layout_env)
        local extra = extra_layout_env and extra_layout_env.layouts
        if extra == nil or #extra == 0 then return env end
        local layouts = clone_values(env.layouts)
        for i = 1, #extra do layouts[#layouts + 1] = extra[i] end
        return B.Env(env.module_name, env.values, env.types, layouts)
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
        return Tr.TypeModuleFacts({}, {}, {})
    end

    local function variant_name_text(v)
        if type(v) == "string" then return v end
        return v and (v.text or v.name) or tostring(v)
    end

    local function type_value_scope_from_env(env)
        return Tr.TypeValueScope(env.module_name, env.values, env.types, env.layouts, empty_type_module_facts())
    end

    local function type_value_scope_from_state(type_state)
        return Tr.TypeValueScope(type_state.env.module_name, type_state.env.values, type_state.env.types, type_state.env.layouts, type_state.facts)
    end

    local function type_expr_input_from_state(type_state)
        return Tr.TypeExprInput(type_value_scope_from_state(type_state))
    end

    local function type_expected_expr_input_from_state(type_state, expected)
        return Tr.TypeExpectedExprInput(type_value_scope_from_state(type_state), expected)
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

    local function find_handle_def(ctx, name)
        for i = 1, #(ctx.facts.handles or {}) do
            if ctx.facts.handles[i].name == name then return ctx.facts.handles[i] end
        end
        return nil
    end

    local function find_handle_def_for_type(ctx, ty)
        return ty:typecheck_tree_handle_def(ctx)
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
        local base = lease_access_base(param_ty)
        local cls = schema.classof(base)
        if cls ~= Ty.TPtr and cls ~= Ty.TView then return false end
        return type_ref_matches_ty(domain_ref, base.elem)
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

    local function check_handle_resolution_signature(ctx, params, payload_params, issues, site)
        local handle_defs = {}
        local domain_params = {}
        local preserving_domain_params = {}
        local all_defs = ctx.facts.handles or {}
        for i = 1, #(params or {}) do
            local pty = canonical_type(ctx.env, params[i].ty)
            local def = find_handle_def_for_type(ctx, pty)
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
            local info = lease_payload_info(canonical_type(ctx.env, payload_params[i].ty))
            if info ~= nil then
                local matched = nil
                for j = 1, #handle_defs do
                    if type_ref_matches_ty(handle_defs[j].target, info.target) then
                        matched = handle_defs[j]
                        break
                    end
                end
                if matched == nil then
                    issues[#issues + 1] = Tr.TypeIssueInvalidUnary("handle target mismatch", info.lease)
                elseif matched.domain then
                    local key = type_ref_leaf(matched.domain) or ""
                    if #(domain_params[key] or {}) == 0 then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary("handle domain missing", info.lease)
                    elseif #(preserving_domain_params[key] or {}) == 0 then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary("handle domain access", info.lease)
                    elseif info.origin == nil then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary("handle lease origin missing", info.lease)
                    elseif not contains_name(preserving_domain_params[key], info.origin) then
                        issues[#issues + 1] = Tr.TypeIssueInvalidUnary("handle lease origin mismatch", info.lease)
                    end
                end
            end
        end
    end

    local function find_variant(ctx, type_name, variant_name)
        for i = 1, #(ctx.facts.variants or {}) do
            local def = ctx.facts.variants[i]
            if def.type_name == type_name then
                for j = 1, #(def.variants or {}) do
                    if def.variants[j].name == variant_name then return def, def.variants[j] end
                end
                return def, nil
            end
        end
        return nil, nil
    end

    local function variant_def_for_value_ty(ctx, ty)
        return ty:typecheck_tree_variant_def(ctx.facts)
    end

    local function bind_env_for_variant(ctx, region_id, variant, requested_binds)
        local env = ctx.env
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
            local b = B.Binding(C.Id("variant:" .. tostring(region_id or "switch") .. ":" .. variant.name .. ":" .. binds[i].name), binds[i].name, binds[i].ty, B.BindingClassLocalValue)
            env = env_add_value(env, B.ValueEntry(b.name, b))
        end
        return env, binds
    end

    local function live_lease_tys(ctx)
        local out = {}
        for i = #ctx.env.values, 1, -1 do
            local ty = canonical_type(ctx.env, ctx.env.values[i].binding.ty)
            ty:typecheck_tree_append_live_lease(out)
        end
        return out
    end

    local function callee_effect_def(type_state, callee_expr)
        local binding_name = callee_expr:typecheck_tree_binding_name()
        if binding_name == nil then return nil end
        for i = 1, #(type_state.facts.effects or {}) do
            if type_state.facts.effects[i].name == binding_name then return type_state.facts.effects[i] end
        end
        return nil
    end

    local function call_may_invalidate_while_lease_live(ctx, callee_expr, param_tys, typed_args)
        local leases = live_lease_tys(ctx)
        if #leases == 0 then return nil end
        local effect = callee_effect_def(ctx, callee_expr)
        local preserve = effect and effect.preserve or {}
        local explicit_invalidate = effect and effect.invalidate or {}
        for i = 1, #(param_tys or {}) do
            local pty = canonical_type(ctx.env, param_tys[i])
            local pcls = schema.classof(pty)
            if pcls ~= Ty.TLease and (pcls == Ty.TPtr or pcls == Ty.TView) then
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

    type_expr_expect = function(expr, type_state, expected)
        return expr:typecheck_tree_expr_expected(type_expected_expr_input_from_state(type_state, expected))
    end

    local function callable_result(fn_ty)
        return fn_ty:typecheck_tree_callable_result()
    end

    local function check_expected(site, expected, actual, issues)
        if not type_eq(expected, actual) then issues[#issues + 1] = Tr.TypeIssueExpected(site, expected, actual) end
    end

    local function type_binary_op(op, lhs_ty, rhs_ty, issues)
        if op == C.BinAdd then
            local ty = lhs_ty:typecheck_tree_bin_add(rhs_ty)
            if ty ~= nil then return ty end
        end
        if op == C.BinSub then
            local ty = lhs_ty:typecheck_tree_bin_sub(rhs_ty)
            if ty ~= nil then return ty end
        end
        if not type_eq(lhs_ty, rhs_ty) then
            issues[#issues + 1] = Tr.TypeIssueInvalidBinary(tostring(op), lhs_ty, rhs_ty)
            return lhs_ty
        end
        if op == C.BinAdd or op == C.BinSub or op == C.BinMul or op == C.BinDiv or op == C.BinRem then
            if is_numeric_scalar(lhs_ty) then return lhs_ty end
        else
            if is_integer_scalar(lhs_ty) then return lhs_ty end
        end
        issues[#issues + 1] = Tr.TypeIssueInvalidBinary(tostring(op), lhs_ty, rhs_ty)
        return lhs_ty
    end

    local function type_compare_op(op, lhs_ty, rhs_ty, issues)
        if not type_eq(lhs_ty, rhs_ty) then issues[#issues + 1] = Tr.TypeIssueInvalidCompare(tostring(op), lhs_ty, rhs_ty) end
        return bool_ty()
    end

    function type_view(node, ...)
        return node:typecheck_tree_view(...)
    end

    function Tr.IndexBase:typecheck_tree_elem()
        return void_ty()
    end

    function Tr.IndexBaseView:typecheck_tree_elem()
        return self.view.elem
    end

    function Tr.IndexBasePlace:typecheck_tree_elem()
        return self.elem
    end

    function Tr.IndexBaseExpr:typecheck_tree_elem()
        return void_ty()
    end

    local function index_base_elem(base)
        return base:typecheck_tree_elem()
    end

    function type_index_base(node, ...)
        return node:typecheck_tree_index_base(...)
    end

    function type_place(node, ...)
        return node:typecheck_tree_place(...)
    end

    function type_expr(node, type_state)
        return node:typecheck_tree_expr(type_expr_input_from_state(type_state))
    end

    type_switch_key = function(key, ctx, value_ty, issues)
        if key.kind == "expr" then
            local expr = only(type_expr(key.expr, ctx))
            append_all(issues, expr.issues)
            check_expected("switch key", value_ty, expr.ty, issues)
            return { kind = "expr", expr = expr.expr }
        end
        -- SwitchKeyRaw: if the raw string is a bare name (not a literal number),
        -- re-typecheck it as an expression so named constants resolve to their values.
        if key.kind == "raw" then
            local raw = key.raw
            -- Check if it looks like a non-numeric identifier
            if raw:match("^[%a_][%w_]*$") then
                local ref_expr = Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(raw))
                local expr = only(type_expr(ref_expr, ctx))
                if #expr.issues == 0 then
                    check_expected("switch key", value_ty, expr.ty, issues)
                    return { kind = "expr", expr = expr.expr }
                end
                -- Name not found — fall through to keep raw (will fail at backend with clear error)
            end
        end
        return key
    end

    local function jump_args_by_name(args)
        local out = {}; local dup = {}
        for i = 1, #args do if out[args[i].name] ~= nil then dup[args[i].name] = true end; out[args[i].name] = args[i] end
        return out, dup
    end

    local function block_param_bindings(region_id, label, params, is_entry)
        local entries = {}
        for i = 1, #params do
            local class = is_entry and B.BindingClassEntryBlockParam(region_id, label.name, i) or B.BindingClassBlockParam(region_id, label.name, i)
            local binding = B.Binding(C.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. params[i].name), params[i].name, params[i].ty, class)
            entries[#entries + 1] = B.ValueEntry(params[i].name, binding)
        end
        return entries
    end

    local function env_with_block_params(env, region_id, label, params, is_entry)
        local out = env
        local entries = block_param_bindings(region_id, label, params, is_entry)
        for i = 1, #entries do out = env_add_value(out, entries[i]) end
        return out
    end

    function type_stmt(node, ...)
        return node:typecheck_tree_stmt(...)
    end

    function type_control_stmt_region(node, ...)
        return node:typecheck_tree_control_stmt_region(...)
    end

    function type_control_expr_region(node, ...)
        return node:typecheck_tree_control_expr_region(...)
    end

    local function type_contracts(contracts, ctx)
        local out, issues = {}, {}
        for i = 1, #contracts do local c, ci = type_contract(contracts[i], ctx); out[#out + 1] = c; append_all(issues, ci) end
        return out, issues
    end

    local function check_func_types(func, issues)
        for i = 1, #(func.params or {}) do check_type_policy(func.params[i].ty, issues, "param " .. tostring(func.params[i].name)) end
        check_type_policy(func.result, issues, "result")
        if type_contains_lease(func.result) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape result", func.result) end
    end

    local function check_region_signature(region, module_env, facts, issues)
        local ctx = Tr.TypeCheckEnv(module_env, facts, Ty.TScalar(C.ScalarVoid), Tr.TypeYieldNone)
        for i = 1, #(region.params or {}) do
            check_type_policy(region.params[i].ty, issues, "region param " .. tostring(region.params[i].name))
        end
        for i = 1, #(region.conts or {}) do
            local cont = region.conts[i]
            for j = 1, #(cont.params or {}) do
                local param = cont.params[j]
                check_type_policy(param.ty, issues, "continuation " .. tostring(cont.name) .. " param " .. tostring(param.name))
            end
            check_handle_resolution_signature(ctx, region.params, cont.params, issues, "region " .. tostring(cont.name))
        end
    end

    local function canonical_func(self, module_env)
        return schema.with(self, { params = canonical_params(module_env, self.params), result = canonical_type(module_env, self.result) })
    end

    local function canonical_block_params(module_env, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = schema.with(params[i], { ty = canonical_type(module_env, params[i].ty) }) end
        return out
    end

    local function canonical_entry_params(module_env, params)
        local out = {}
        for i = 1, #(params or {}) do out[i] = schema.with(params[i], { ty = canonical_type(module_env, params[i].ty) }) end
        return out
    end

    local function canonical_region(module_env, region)
        local params = canonical_params(module_env, region.params or {})
        local conts = {}
        for i = 1, #(region.conts or {}) do conts[i] = schema.with(region.conts[i], { params = canonical_block_params(module_env, region.conts[i].params) }) end
        local entry = schema.with(region.entry, { params = canonical_entry_params(module_env, region.entry.params) })
        local blocks = {}
        for i = 1, #(region.blocks or {}) do blocks[i] = schema.with(region.blocks[i], { params = canonical_block_params(module_env, region.blocks[i].params) }) end
        return schema.with(region, { params = params, conts = conts, entry = entry, blocks = blocks })
    end

    local function type_plain_func(self, module_env, facts)
        local func = canonical_func(self, module_env)
        local ctx = Tr.TypeCheckEnv(env_with_params(module_env, func.name, func.params), facts, func.result, Tr.TypeYieldNone)
        local body = type_stmt_body(func.body, ctx)
        local issues = {}; check_func_types(func, issues); append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues)
        return Tr.TypeFuncResult(schema.with(func, { body = body.stmts }), issues)
    end

    local function type_contract_func(self, module_env, facts)
        local func = canonical_func(self, module_env)
        local ctx = Tr.TypeCheckEnv(env_with_params(module_env, func.name, func.params), facts, func.result, Tr.TypeYieldNone)
        local contracts, issues = type_contracts(func.contracts, ctx)
        check_func_types(func, issues)
        local body = type_stmt_body(func.body, ctx)
        append_all(issues, body.issues)
        check_owned_function(func.name, func.params, body.stmts, issues)
        return Tr.TypeFuncResult(schema.with(func, { contracts = contracts, body = body.stmts }), issues)
    end

    function Tr.FuncLocal:typecheck_tree_func(module_env, facts)
        return type_plain_func(self, module_env, facts)
    end

    function Tr.FuncExport:typecheck_tree_func(module_env, facts)
        return type_plain_func(self, module_env, facts)
    end

    function Tr.FuncLocalContract:typecheck_tree_func(module_env, facts)
        return type_contract_func(self, module_env, facts)
    end

    function Tr.FuncExportContract:typecheck_tree_func(module_env, facts)
        return type_contract_func(self, module_env, facts)
    end

    function type_func(node, ...)
        return node:typecheck_tree_func(...)
    end

    function Tr.ItemFunc:typecheck_tree_item(module_env, facts)
        local r = type_func(self.func, module_env, facts)
        return Tr.TypeItemResult({ Tr.ItemFunc(r.func) }, r.issues)
    end

    function Tr.ItemConst:typecheck_tree_item(module_env, facts)
        local ty = canonical_type(module_env, self.c.ty)
        local type_state = Tr.TypeCheckEnv(module_env, facts, ty, Tr.TypeYieldNone)
        local value = type_expr(self.c.value, type_state)
        local issues = {}
        check_type_policy(ty, issues, "const")
        append_all(issues, value.issues)
        check_expected("const", ty, value.ty, issues)
        if type_contains_lease(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape const", ty) end
        if type_contains_owned(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", ty) end
        return Tr.TypeItemResult({ Tr.ItemConst(schema.with(self.c, { ty = ty, value = value.expr })) }, issues)
    end

    function Tr.ItemStatic:typecheck_tree_item(module_env, facts)
        local ty = canonical_type(module_env, self.s.ty)
        local type_state = Tr.TypeCheckEnv(module_env, facts, ty, Tr.TypeYieldNone)
        local value = type_expr(self.s.value, type_state)
        local issues = {}
        check_type_policy(ty, issues, "static")
        append_all(issues, value.issues)
        check_expected("static", ty, value.ty, issues)
        if type_contains_lease(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape static", ty) end
        if type_contains_owned(ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", ty) end
        return Tr.TypeItemResult({ Tr.ItemStatic(schema.with(self.s, { ty = ty, value = value.expr })) }, issues)
    end

    function Tr.ItemExtern:typecheck_tree_item()
        local issues = {}
        check_func_types(self.func, issues)
        return Tr.TypeItemResult({ self }, issues)
    end

    function Tr.ItemImport:typecheck_tree_item()
        return Tr.TypeItemResult({ self }, {})
    end

    function Tr.TypeDecl:typecheck_tree_item_issues()
        return {}
    end

    function Tr.TypeDeclStruct:typecheck_tree_item_issues()
        local issues = {}
        for i = 1, #self.fields do
            check_type_policy(self.fields[i].ty, issues, "field " .. self.fields[i].field_name)
            if type_contains_lease(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape field", self.fields[i].ty) end
            if type_contains_owned(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", self.fields[i].ty) end
        end
        return issues
    end

    function Tr.TypeDeclUnion:typecheck_tree_item_issues()
        local issues = {}
        for i = 1, #self.fields do
            check_type_policy(self.fields[i].ty, issues, "field " .. self.fields[i].field_name)
            if type_contains_lease(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("lease escape field", self.fields[i].ty) end
            if type_contains_owned(self.fields[i].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary("owned stored in durable field", self.fields[i].ty) end
        end
        return issues
    end

    function Tr.TypeDeclEnumSugar:typecheck_tree_item_issues()
        local issues = {}
        local seen = {}
        for i = 1, #self.variants do
            local name = variant_name_text(self.variants[i])
            if seen[name] then issues[#issues + 1] = Tr.TypeIssueDuplicateVariant(self.name, name) end
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
            if type_contains_lease(v.payload) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "region call lease payload" or "lease escape variant field", v.payload) end
            if type_contains_owned(v.payload) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "owned region call payload" or "owned stored in durable field", v.payload) end
            for j = 1, #(v.fields or {}) do
                check_type_policy(v.fields[j].ty, issues, "variant field " .. v.fields[j].field_name)
                if type_contains_lease(v.fields[j].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "region call lease payload" or "lease escape variant field", v.fields[j].ty) end
                if type_contains_owned(v.fields[j].ty) then issues[#issues + 1] = Tr.TypeIssueInvalidUnary(is_region_call_result and "owned region call payload" or "owned stored in durable field", v.fields[j].ty) end
            end
            if seen[name] then issues[#issues + 1] = Tr.TypeIssueDuplicateVariant(self.name, name) end
            seen[name] = true
        end
        return issues
    end

    function Tr.TypeDeclHandle:typecheck_tree_item_issues()
        local issues = {}
        self.repr:typecheck_tree_check_handle_decl(self.name, issues)
        return issues
    end

    function Tr.ItemType:typecheck_tree_item()
        local issues = self.t:typecheck_tree_item_issues()
        return Tr.TypeItemResult({ self }, issues)
    end

    function Tr.ItemRegion:typecheck_tree_item(module_env, facts)
        local region = canonical_region(module_env, self.region)
        local issues = {}
        check_region_signature(region, module_env, facts, issues)
        local type_state = Tr.TypeCheckEnv(env_with_params(module_env, "region:" .. tostring(region.name), region.params), facts, Ty.TScalar(C.ScalarVoid), Tr.TypeYieldNone)
        local region_id = "region:" .. tostring(region.name)
        local typed_entry, entry_issues = type_entry_block(region_id, region.entry, type_state, Tr.TypeYieldVoid)
        append_all(issues, entry_issues)
        local typed_blocks = {}
        for i = 1, #(region.blocks or {}) do
            local b, bi = type_control_block(region_id, region.blocks[i], type_state, Tr.TypeYieldVoid)
            typed_blocks[#typed_blocks + 1] = b
            append_all(issues, bi)
        end
        local runtime_bindings = {}
        for i = 1, #region.params do
            local p = region.params[i]
            local b = B.Binding(C.Id("region-param:" .. region.name .. ":" .. p.name), p.name, p.ty, B.BindingClassArg(i - 1))
            runtime_bindings[#runtime_bindings + 1] = B.ValueEntry(p.name, b)
        end
        local cont_targets = {}
        for i = 1, #(region.conts or {}) do cont_targets[region.conts[i].name] = true end
        check_owned_control_region(Tr.ControlStmtRegion(region_id, typed_entry, typed_blocks), issues, runtime_bindings, cont_targets)
        return Tr.TypeItemResult({}, issues)
    end

    function type_item(node, ...)
        return node:typecheck_tree_item(...)
    end

    local function item_diagnostic_name(item)
        local cls = schema.classof(item)
        if cls == Tr.ItemFunc and item.func then return item.func.name end
        if cls == Tr.ItemRegion and item.region then return item.region.name end
        if cls == Tr.ItemType and item.t then return item.t.name end
        if cls == Tr.ItemExtern and item.func then return item.func.name end
        if cls == Tr.ItemConst and item.c then return item.c.name end
        if cls == Tr.ItemStatic and item.s then return item.s.name end
        return nil
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

    local function type_module_with_layout_env(module, extra_layout_env, target, collector, analysis_ctx)
        local base_env = module_type_api.env(module, target)
        local facts = module:typecheck_tree_module_facts(Tr.TypeModuleFactsInput(base_env.module_name))
        local module_env = merge_env_layouts(base_env, extra_layout_env)
        local items = {}
        local issues = {}
        for i = 1, #module.items do
            local item = module.items[i]
            local r = type_item(item, module_env, facts)
            append_all(items, r.items)
            append_all(issues, r.issues)
            emit_item_issues(collector, analysis_ctx or {}, item, r.issues)
        end
        return Tr.TypeModuleResult(Tr.Module(Tr.ModuleTyped(module_env.module_name), items), issues)
    end

    function type_module(node, ...)
        return node:typecheck_tree_module(...)
    end

    function Tr.Module:typecheck_tree_module(extra_layout_env, target, collector, analysis_ctx)
        return type_module_with_layout_env(self, extra_layout_env, target, collector, analysis_ctx)
    end

    return {
        expr = type_expr,
        place = type_place,
        stmt = type_stmt,
        stmt_body = type_stmt_body,
        control_stmt_region = type_control_stmt_region,
        control_expr_region = type_control_expr_region,
        func = type_func,
        item = type_item,
        module = type_module,
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

local Format = require("lalin.error.format")

local function site_description(site)
    -- Produces a human-readable context string from a site string
    if not site or site == "" then return "expression" end
    -- Check specific site types
    if site:find("let ") then return "variable initializer" end
    if site:find("var ") then return "variable initializer" end
    if site:find("return") then return "return value" end
    if site:find("yield") then return "yielded value" end
    if site:find("set") then return "assignment" end
    if site:find("if cond") then return "if condition" end
    if site:find("select cond") then return "select condition" end
    if site:find("if branches") then return "if branches" end
    if site:find("select branches") then return "select branches" end
    if site:find("call") then return "call argument" end
    if site:find("index") then return "index expression" end
    if site:find("view data") then return "view data" end
    if site:find("view len") or site:find("view stride") or site:find("view window") then return "view" end
    if site:find("bounds") then return "bounds" end
    if site:find("window_bounds") then return "window_bounds" end
    if site:find("disjoint") then return "disjoint" end
    if site:find("same_len") then return "same_len" end
    if site:find("memory contract") then return "memory contract" end
    if site:find("atomic") then return "atomic" end
    if site:find("block param") then return "block parameter" end
    if site:find("assert") then return "assert" end
    if site:find("switch key") then return "switch key" end
    if site:find("switch arm") then return "switch arm" end
    if site:find("array elem") then return "array element" end
    if site:find("len") then return "len" end
    if site:find("const") or site:find("static") then return "constant initializer" end
    return site
end

local function explain_type_issue(issue, analysis)
	analysis = analysis or { anchors = {} }
	local resolvers = require("lalin.error.span_resolvers")
	local schema = require("lalin.schema_runtime")
	local span = resolvers.typecheck_resolver(issue, analysis)
    local cls = schema.classof(issue)
    if not cls then return { code = "E9999", severity = "error", primary = { span = span, message = tostring(issue) } } end
    local kind = cls.kind

    if kind == "TypeIssueExpected" then
        -- Port of E0301 builder logic
        local site = issue.site or "expression"
        local expected = Format.type_name(issue.expected)
        local actual = Format.type_name(issue.actual)
        local expected_raw = issue.expected
        local actual_raw = issue.actual
        local notes = {}
        local suggestions = {}

        -- Context-specific notes
        if site:find("call") then
            notes[#notes + 1] = { message = "this argument has type `" .. actual .. "`, but the function expects `" .. expected .. "`" }
        elseif site:find("let ") or site:find("var ") then
            local var_name = site:match("let (%w+)") or site:match("var (%w+)") or ""
            notes[#notes + 1] = { message = "the initializer has type `" .. actual .. "`, but the variable is declared as `" .. expected .. "`" }
        elseif site:find("return") then
            notes[#notes + 1] = { message = "the return value has type `" .. actual .. "`, but the function returns `" .. expected .. "`" }
        elseif site:find("yield") then
            notes[#notes + 1] = { message = "the yielded value has type `" .. actual .. "`, but the region yields `" .. expected .. "`" }
        elseif site:find("set") then
            notes[#notes + 1] = { message = "the assigned value has type `" .. actual .. "`, but the target has type `" .. expected .. "`" }
        elseif site:find("if cond") or site:find("select cond") then
            notes[#notes + 1] = { message = "the condition has type `" .. actual .. "`, but the condition must be `bool`" }
        elseif site:find("if branches") or site:find("select branches") then
            notes[#notes + 1] = { message = "both branches must have the same type; the then-branch is `" .. actual .. "`, the else-branch is `" .. expected .. "`" }
        elseif site:find("index") then
            notes[#notes + 1] = { message = "indexing requires an integer type, got `" .. actual .. "`" }
        elseif site:find("view data") then
            notes[#notes + 1] = { message = "view data must be a `ptr` or `view`, got `" .. actual .. "`" }
        elseif site:find("view len") or site:find("view stride") or site:find("view window") or site:find("bounds") or site:find("window_bounds") then
            notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
        elseif site:find("disjoint") then
            notes[#notes + 1] = { message = "disjoint contract requires `ptr` or `view`, got `" .. actual .. "`" }
        elseif site:find("same_len") then
            notes[#notes + 1] = { message = "same_len contract requires `view`, got `" .. actual .. "`" }
        elseif site:find("memory contract") then
            notes[#notes + 1] = { message = "memory contract requires `ptr` or `view`, got `" .. actual .. "`" }
        elseif site:find("atomic") then
            notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
        elseif site:find("block param") then
            notes[#notes + 1] = { message = "block parameter initializer has type `" .. actual .. "`, but the parameter is declared as `" .. expected .. "`" }
        elseif site:find("assert") then
            notes[#notes + 1] = { message = "assert condition must be `bool`, got `" .. actual .. "`" }
        elseif site:find("switch key") then
            notes[#notes + 1] = { message = "switch key has type `" .. actual .. "`, but the switch expression is `" .. expected .. "`" }
        elseif site:find("switch arm") then
            notes[#notes + 1] = { message = "switch arm has type `" .. actual .. "`, but the default arm is `" .. expected .. "`" }
        elseif site:find("array elem") then
            notes[#notes + 1] = { message = "array element has type `" .. actual .. "`, but the array expects `" .. expected .. "`" }
        elseif site:find("len") then
            notes[#notes + 1] = { message = "`len` requires a `view`, got `" .. actual .. "`" }
        elseif site:find("const") or site:find("static") then
            notes[#notes + 1] = { message = "the initializer has type `" .. actual .. "`, but the declaration is `" .. expected .. "`" }
        else
            notes[#notes + 1] = { message = "expected `" .. expected .. "`, got `" .. actual .. "`" }
        end

        -- Numeric conversion hint
        local function is_integer(ty)
            return ty ~= nil and ty:typecheck_tree_is_integer_scalar()
        end

        if actual == "bool" and expected ~= "bool" then
            suggestions[#suggestions + 1] = { message = "to convert a boolean to an integer, use a conditional: `select(flag, 1, 0)`" }
        elseif actual == "f64" and is_integer(expected_raw) then
            suggestions[#suggestions + 1] = { message = "to convert a float to an integer, use `as(i32, value)`" }
        elseif is_integer(actual_raw) and expected == "f64" then
            suggestions[#suggestions + 1] = { message = "to convert an integer to a float, use `as(f64, value)`" }
        end

        return {
            code = "E0301",
            severity = "error",
            phase_context = "while type-checking",
            primary = { span = span, message = "type mismatch" },
            notes = notes,
            suggestions = suggestions,
        }
    end

    if kind == "TypeIssueNotCallable" then
        local ty = Format.type_name(issue.ty)
        return { code = "E0302", severity = "error", phase_context = "while type-checking a call",
            primary = { span = span, message = "type `" .. ty .. "` is not callable" },
            notes = { { message = "only `func` and `closure` types can be called" } },
            suggestions = { { message = "did you mean to index? write `expr[idx]` for element access" } } }
    end

    if kind == "TypeIssueNotIndexable" or kind == "TypeIssueNotPointer" then
        local ty = Format.type_name(issue.ty)
        return { code = "E0303", severity = "error", phase_context = "while type-checking an index",
            primary = { span = span, message = "type `" .. ty .. "` is not indexable" },
            notes = { { message = "only `view`, `ptr`, and `array` types support indexing" } },
            suggestions = { { message = "if you meant to access a field, use `.` syntax: `expr.field`" } } }
    end

    if kind == "TypeIssueArgCount" then
        return { code = "E0305", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = (issue.site or "call") .. " expected " .. tostring(issue.expected) .. " arguments, got " .. tostring(issue.actual) },
            suggestions = { { message = "check the function signature and add or remove arguments" } } }
    end

    if kind == "TypeIssueInvalidUnary" then
        local op = Format.op_symbol(issue.op)
        local ty = Format.type_name(issue.ty)
        local raw_op = tostring(issue.op or "")
        local function report(primary, notes, suggestions)
            return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
                primary = { span = span, message = primary }, notes = notes or {}, suggestions = suggestions or {} }
        end
        if raw_op == "lease escape return" then
            return report("lease escapes through return", {
                { message = "lease value `" .. ty .. "` is temporary access produced by a store or boundary" },
                { message = "leases may access memory inside their dynamic extent but may not be returned as durable identity" },
            }, { { message = "return a handle or copied scalar data instead, or keep the pointer parameter marked `noescape`" } })
        elseif raw_op == "lease escape yield" then
            return report("lease escapes through yield", {
                { message = "yielding `" .. ty .. "` would move temporary access outside the granting region" },
            }, { { message = "yield a handle/status protocol, not the lease pointer/view" } })
        elseif raw_op == "lease escape store" then
            return report("lease escapes through store", {
                { message = "storing `" .. ty .. "` would make temporary access durable" },
            }, { { message = "store the handle, or copy the data through the lease instead" } })
        elseif raw_op == "lease escape call" then
            return report("lease passed to retaining parameter", {
                { message = "a lease can only be passed to another `lease` or `noescape` parameter" },
                { message = "plain `ptr`/`view` parameters are treated as possibly retained" },
            }, { { message = "mark the callee parameter `noescape`, or change it to `lease ptr(T)` / `lease view(T)`" } })
        elseif raw_op == "lease invalidating call" then
            return report("call may invalidate store while lease is live", {
                { message = "live lease `" .. ty .. "` may refer to storage that this call can move, free, compact, clear, or reuse" },
                { message = "`readonly` and `preserve` parameters keep leases valid; unannotated pointer/view parameters are conservative invalidators" },
            }, { { message = "end the lease scope before the call, call a `preserve`/`readonly` API, or use `lease(store)` to associate the lease with the correct store" } })
        elseif raw_op == "lease escape aggregate" then
            return report("lease captured in aggregate", {
                { message = "aggregates can outlive the current access extent, so they cannot contain `" .. ty .. "`" },
            }, { { message = "store a handle or copied data instead of the lease" } })
        elseif raw_op == "region call lease payload" then
            return report("cannot call region because continuation payload contains a lease", {
                { message = "continuation payload `" .. ty .. "` is temporary access and cannot be packed into the generated region-call result" },
            }, { { message = "use `emit` so temporary access stays in control flow" } })
        elseif raw_op == "lease escape field" or raw_op == "lease escape variant field" or raw_op == "lease escape result" or raw_op == "lease escape const" or raw_op == "lease escape static" then
            return report("lease appears in durable type position", {
                { message = "`" .. ty .. "` is temporary access, not storable data" },
                { message = "leases may appear in function/block/continuation parameters, not durable fields/results/statics" },
            }, { { message = "use a handle type for durable identity, or a plain pointer only at an unchecked ABI boundary" } })
        elseif raw_op == "owned dropped" then
            return report("owned obligation is not discharged", {
                { message = "`" .. ty .. "` must be transferred to an owned parameter/result or consumed by a closing protocol" },
                { message = "owned values do not have destructors and cannot silently fall out of scope" },
            }, { { message = "jump/return/yield/pass the owner to an `owned` slot, or call the explicit close/retire region" } })
        elseif raw_op == "owned use after move" then
            return report("owned value used after transfer", {
                { message = "`" .. ty .. "` was already consumed by an ownership transfer" },
            }, { { message = "thread the returned/re-yielded owner forward if the protocol preserves the obligation" } })
        elseif raw_op == "owned observed without transfer" or raw_op == "owned passed to non-owned parameter" then
            return report("owned value used without an ownership contract", {
                { message = "`" .. ty .. "` is linear authority and cannot be copied or borrowed as a plain value" },
            }, { { message = "make the callee parameter `owned`, or use a protocol that returns the owner on every preserving edge" } })
        elseif raw_op == "owned captured in aggregate" or raw_op == "owned stored in durable field" then
            return report("owned value captured in durable storage", {
                { message = "`" .. ty .. "` is a CFG obligation, not storable data" },
            }, { { message = "store the plain handle separately and keep the owned obligation in control flow" } })
        elseif raw_op == "owned branch mismatch" then
            return report("branches leave different owned obligations live", {
                { message = "all continuing paths must preserve the same live owned set" },
            }, { { message = "move the transfer before the branch, or return/jump/yield on the consuming path" } })
        elseif raw_op == "owned var cell unsupported" then
            return report("owned values cannot live in mutable cells", {
                { message = "`var owned T` needs explicit take/put semantics and is rejected" },
            }, { { message = "use `let` ownership threading through CFG parameters" } })
        elseif raw_op == "owned region call payload" then
            return report("owned payload cannot use expression-style region call", {
                { message = "`" .. ty .. "` cannot be packed into the generated region-call result aggregate" },
            }, { { message = "use `emit`/explicit continuations so ownership stays in CFG" } })
        elseif raw_op == "owned emit target mismatch" then
            return report("owned continuation payload has no matching target parameter", {
                { message = "`" .. ty .. "` must land in a target block/continuation parameter with the same owned type and name" },
            }, { { message = "add the owned parameter to the filled target, or consume the owner inside the emitted fragment" } })
        elseif raw_op == "owned lease composition" or raw_op == "owned access composition" or raw_op == "owned invalid base" then
            return report("invalid owned type composition", {
                { message = "`" .. ty .. "` mixes ownership authority with access modifiers or temporary leases" },
            }, { { message = "own the durable handle/resource token; borrow access through a protocol that returns the owner" } })
        elseif raw_op == "handle cast" then
            return report("handle representation is opaque", {
                { message = "handle `" .. ty .. "` is not its integer representation in safe casts" },
                { message = "ordinary `as(...)` cannot convert handles to or from raw scalars" },
            }, { { message = "resolve the handle through a store region, or use trusted `repr(handle)` / `Handle.from_repr(raw)` inside store implementation code" } })
        elseif raw_op == "handle repr" then
            return report("`repr` expects a handle", {
                { message = "`repr(value)` is the explicit trusted handle-to-scalar boundary" },
                { message = "the value has type `" .. ty .. "`, not a handle" },
            })
        elseif raw_op == "handle target mismatch" then
            return report("handle resolver returns a lease to the wrong target", {
                { message = "a handle with a `target` fact may only grant leases to that target type" },
                { message = "the continuation payload has type `" .. ty .. "`" },
            }, { { message = "change the lease payload target, or declare a different handle target fact" } })
        elseif raw_op == "handle domain missing" then
            return report("handle resolver does not take the owning domain", {
                { message = "a handle with a `domain` fact must be resolved through that store/domain parameter" },
                { message = "the continuation payload has type `" .. ty .. "`" },
            }, { { message = "add a `readonly` or `preserve` `ptr(Store)` parameter matching the handle domain" } })
        elseif raw_op == "handle domain access" then
            return report("handle resolver domain parameter does not preserve leases", {
                { message = "resolver regions that grant leases must take the owning domain as `readonly` or `preserve`" },
                { message = "bare pointer/view parameters are conservative invalidators" },
            }, { { message = "mark the domain parameter `readonly` or `preserve`" } })
        elseif raw_op == "handle lease origin missing" then
            return report("handle resolver lease is not tied to its store parameter", {
                { message = "a handle resolver must return `lease(store) ptr(Target)` or `lease(store) view(Target)`" },
                { message = "anonymous leases cannot participate in store invalidation checks" },
            }, { { message = "write the lease as `lease(store_param) ptr(T)`" } })
        elseif raw_op == "handle lease origin mismatch" then
            return report("handle resolver lease is tied to the wrong store parameter", {
                { message = "the lease origin must name the `readonly` or `preserve` domain parameter for the handle" },
                { message = "the continuation payload has type `" .. ty .. "`" },
            }, { { message = "change the `lease(...)` origin to the matching store parameter" } })
        end
        local unotes = {}
        local usuggestions = {}
        if op == "not" then
            unotes[#unotes + 1] = { message = "`not` requires a `bool` operand, got `" .. ty .. "`" }
        else
            unotes[#unotes + 1] = { message = "operator `" .. op .. "` is not defined for type `" .. ty .. "`" }
            unotes[#unotes + 1] = { message = "arithmetic operators require numeric types (i8, i16, i32, ...)" }
        end
        if ty == "bool" and op ~= "not" then
            usuggestions[#usuggestions + 1] = { message = "for boolean logic, use `not`: `not value`" }
        end
        return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
            primary = { span = span, message = "invalid unary operator `" .. op .. "` for type `" .. ty .. "`" },
            notes = unotes, suggestions = usuggestions }
    end

    if kind == "TypeIssueInvalidBinary" then
        local op = Format.op_symbol(issue.op)
        local lhs = Format.type_name(issue.lhs)
        local rhs = Format.type_name(issue.rhs)
        local bnotes = { { message = "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" } }
        local bsuggestions = {}
        if lhs == "bool" and rhs == "bool" then
            if op == "+" or op == "-" or op == "*" or op == "/" then
                bnotes[#bnotes + 1] = { message = "arithmetic operators require numeric types (i8, i16, i32, ...)" }
                bsuggestions[#bsuggestions + 1] = { message = "for boolean logic, use `and` / `or`: `a and b` or `a or b`" }
            end
        end
        if lhs ~= rhs then
            bnotes[#bnotes + 1] = { message = "both operands must have the same type" }
        end
        return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
            primary = { span = span, message = "invalid operator `" .. op .. "`" },
            notes = bnotes, suggestions = bsuggestions }
    end

    if kind == "TypeIssueInvalidCompare" or kind == "TypeIssueInvalidLogic" then
        local op = Format.op_symbol(issue.op)
        local lhs = Format.type_name(issue.lhs)
        local rhs = Format.type_name(issue.rhs)
        local cnotes = { { message = "operator `" .. op .. "` is not defined for `" .. lhs .. "` and `" .. rhs .. "`" } }
        if lhs ~= rhs then
            cnotes[#cnotes + 1] = { message = "both operands must have the same type" }
        end
        return { code = "E0304", severity = "error", phase_context = "while type-checking an expression",
            primary = { span = span, message = "invalid operator `" .. op .. "`" },
            notes = cnotes }
    end

    if kind == "TypeIssueUnresolvedValue" then
        return { code = "E0201", severity = "error", phase_context = "while resolving names",
            primary = { span = span, message = "unresolved name `" .. tostring(issue.name or "?") .. "`" },
            notes = { { message = "`" .. tostring(issue.name or "?") .. "` is not defined in this scope" } } }
    end

    if kind == "TypeIssueUnresolvedPath" then
        local path_text = tostring(issue.path_text or "?")
        local first_segment = issue.first_name or path_text:match("^([%w_]+)") or "?"
        -- Try did_you_mean on the first path segment
        local dym = nil
        local analysis_scope = analysis and analysis.in_scope_names or {}
        if #analysis_scope > 0 then
            local suggest = require("lalin.error.suggest")
            dym = suggest.did_you_mean(first_segment, analysis_scope)
        end
        local suggestions = {}
        if dym then suggestions[#suggestions + 1] = { message = dym } end
        return { code = "E0202", severity = "error", phase_context = "while resolving names",
            primary = { span = span, message = "unresolved path `" .. path_text .. "`" },
            notes = { { message = "the first segment `" .. first_segment .. "` could not be resolved" } },
            suggestions = suggestions }
    end

    if kind == "TypeIssueInvalidControl" then
        local reject = issue.reject
        local reject_kind = reject and schema.classof(reject).kind or "ControlRejectIrreducible"
        local label = reject and reject.label and reject.label.name or "?"
        local name = reject and reject.name or "?"
        local region = issue.region_id or (reject and reject.region_id) or "?"
        local code = "E0405"
        local primary = "invalid control flow"
        local notes = { { message = "region: " .. tostring(region) } }
        local suggestions = {}

        if reject_kind == "ControlRejectMissingJumpArg" then
            code = "E0404"
            primary = "jump to `" .. label .. "` is missing argument `" .. tostring(name) .. "`"
            notes[#notes + 1] = { message = "target block `" .. label .. "` declares parameter `" .. tostring(name) .. "`, but this jump does not provide it" }
            suggestions[#suggestions + 1] = { message = "pass `" .. tostring(name) .. " = ...` at the jump, or rename the target block parameter to match the existing argument" }
        elseif reject_kind == "ControlRejectExtraJumpArg" then
            code = "E0404"
            primary = "jump to `" .. label .. "` has extra argument `" .. tostring(name) .. "`"
            notes[#notes + 1] = { message = "target block `" .. label .. "` has no parameter named `" .. tostring(name) .. "`" }
            suggestions[#suggestions + 1] = { message = "remove the extra argument or add a matching block parameter" }
        elseif reject_kind == "ControlRejectDuplicateJumpArg" then
            code = "E0203"
            primary = "duplicate jump argument `" .. tostring(name) .. "` for `" .. label .. "`"
            suggestions[#suggestions + 1] = { message = "provide each jump argument name only once" }
        elseif reject_kind == "ControlRejectJumpType" then
            code = "E0301"
            primary = "jump argument `" .. tostring(name) .. "` for `" .. label .. "` has wrong type"
            notes[#notes + 1] = { message = "expected `" .. Format.type_name(reject.expected) .. "`, got `" .. Format.type_name(reject.actual) .. "`" }
        elseif reject_kind == "ControlRejectMissingLabel" then
            code = "E0402"
            primary = "missing jump target `" .. label .. "`"
            notes[#notes + 1] = { message = "block `" .. label .. "` is not defined in this region" }
        elseif reject_kind == "ControlRejectDuplicateLabel" then
            code = "E0203"
            primary = "duplicate block label `" .. label .. "`"
            suggestions[#suggestions + 1] = { message = "rename one of the blocks" }
        elseif reject_kind == "ControlRejectUnterminatedBlock" then
            code = "E0406"
            primary = "block `" .. label .. "` does not terminate"
            notes[#notes + 1] = { message = "every block path must end in jump, yield, return, or trap" }
        elseif reject_kind == "ControlRejectYieldOutsideRegion" then
            code = "E0407"
            primary = "invalid yield in control region"
            notes[#notes + 1] = { message = reject.reason or "yield kind does not match this region" }
        elseif reject_kind == "ControlRejectYieldType" then
            code = "E0301"
            primary = "yield has wrong type"
            notes[#notes + 1] = { message = "expected `" .. Format.type_name(reject.expected) .. "`, got `" .. Format.type_name(reject.actual) .. "`" }
        elseif reject_kind == "ControlRejectUnknownVariant" then
            code = "E0201"
            primary = "unknown switch variant `" .. tostring(reject.variant_name or "?") .. "`"
        else
            primary = "irreducible control flow"
            notes[#notes + 1] = { message = (reject and reject.reason) or "irreducible cycle detected" }
            notes[#notes + 1] = { message = "control flow is irreducible when no block dominates the others — restructure so one block is the single entry point" }
            suggestions[#suggestions + 1] = { message = "add a dispatch block that dominates all other blocks in this region" }
        end

        return { code = code, severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = primary }, notes = notes, suggestions = suggestions }
    end

    if kind == "TypeIssueMissingJumpTarget" then
        local label = (issue.label and issue.label.name) or (issue.label_name) or "?"
        local candidates = issue.block_names or {}
        local dym = Format.Suggest.did_you_mean(label, candidates)
        local mnotes = { { message = "block `" .. label .. "` is not defined in this region" } }
        local msuggestions = {}
        if dym then msuggestions[#msuggestions + 1] = { message = dym } end
        return { code = "E0402", severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = "missing jump target `" .. label .. "`" },
            notes = mnotes, suggestions = msuggestions }
    end

    if kind == "TypeIssueMissingJumpArg" or kind == "TypeIssueExtraJumpArg" then
        return { code = "E0404", severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = "jump argument count mismatch for `" .. tostring(issue.name or "?") .. "`" },
            notes = { { message = "check that the number of arguments passed to the jump matches the block parameters" } } }
    end

    if kind == "TypeIssueDuplicateJumpArg" then
        return { code = "E0203", severity = "error", phase_context = "while checking control flow",
            primary = { span = span, message = "duplicate jump argument `" .. tostring(issue.name or "?") .. "`" },
            suggestions = { { message = "remove the duplicate argument or rename one of them" } } }
    end

    if kind == "TypeIssueUnexpectedYield" then
        return { code = "E0407", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = "`yield` used outside a region" },
            notes = { { message = "`yield` can only be used inside a `region` or a `return region: T` expression" } },
            suggestions = { { message = "did you mean `return`? Functions use `return`, not `yield`" } } }
    end

    if kind == "TypeIssueUnknownVariant" then
        return { code = "E0201", severity = "error", phase_context = "while resolving names",
            primary = { span = span, message = "unknown variant `" .. tostring(issue.variant_name or "?") .. "` in type `" .. Format.type_name(issue.type_name) .. "`" } }
    end

    if kind == "TypeIssueVariantPayloadMismatch" then
        return { code = "E0301", severity = "error", phase_context = "while type-checking",
            primary = { span = span, message = "variant payload mismatch for `" .. tostring(issue.variant_name or "?") .. "`" } }
    end

    if kind == "TypeIssueDuplicateVariant" then
        return { code = "E0203", severity = "error", phase_context = "while checking declarations",
            primary = { span = span, message = "duplicate variant `" .. tostring(issue.variant_name or "?") .. "`" } }
    end

    -- Fallback
    return { code = "E9999", severity = "error", primary = { span = span, message = kind or tostring(issue) } }
end

return setmetatable({
    explain_type_issue = explain_type_issue,
}, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
