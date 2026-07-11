return function(T)
    local C = T.LalinCore
    local B = T.LalinBind
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local Check = T.LalinCheck
    local function void_ty()
        return Ty.TScalar(C.ScalarVoid)
    end

    local function variant_name_text(v)
        return v and (v.text or v.name) or tostring(v)
    end

    local function append_all(out, values)
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
    end

    local function clone_values(values)
        local out = {}
        for i = 1, #(values or {}) do out[#out + 1] = values[i] end
        return out
    end

    function Check.TypeValueScope:typecheck_tree_add_value(entry)
        local values = clone_values(self.values)
        values[#values + 1] = entry
        return Check.TypeValueScope(self.module_name, values, self.types, self.layouts, self.facts)
    end

    function Check.TypeValueScope:typecheck_tree_add_params(scope_name, params)
        local scope = self
        for i = 1, #(params or {}) do
            local p = params[i]
            local binding = B.Binding(C.Id("arg:" .. scope_name .. ":" .. p.name), p.name, p.ty, B.BindingRoleArg(i - 1))
            scope = scope:typecheck_tree_add_value(B.ValueEntry(p.name, binding))
        end
        return scope
    end

    function Check.TypeValueScope:typecheck_tree_with_layouts(layouts)
        return Check.TypeValueScope(self.module_name, self.values, self.types, layouts, self.facts)
    end

    function Check.TypeValueScope:typecheck_tree_lookup_value(name)
        for i = #self.values, 1, -1 do
            if self.values[i].name == name then return self.values[i].binding end
        end
        return nil
    end

    function Check.TypeValueScope:typecheck_tree_stmt_input(return_ty, yield)
        return Check.TypeStmtInput(self, return_ty, yield)
    end

    function Check.TypeValueScope:typecheck_tree_expr_input()
        return Check.TypeExprInput(self)
    end

    function Check.TypeValueScope:typecheck_tree_place_input()
        return Check.TypePlaceInput(self)
    end

    function Check.TypeStmtInput:typecheck_tree_with_scope(scope)
        return Check.TypeStmtInput(scope, self.return_ty, self.yield)
    end

    function Check.TypeStmtInput:typecheck_tree_with_yield(yield)
        return Check.TypeStmtInput(self.scope, self.return_ty, yield)
    end

    function Check.TypeStmtInput:typecheck_tree_expr_input()
        return self.scope:typecheck_tree_expr_input()
    end

    function Check.TypeStmtInput:typecheck_tree_place_input()
        return self.scope:typecheck_tree_place_input()
    end

    function Check.TypeStmtInput:typecheck_tree_expected_expr_input(expected)
        return Check.TypeExpectedExprInput(self.scope, expected)
    end

    function Ty.HandleFact:typecheck_tree_handle_domain()
        return nil
    end

    function Ty.HandleDomain:typecheck_tree_handle_domain()
        return self.domain
    end

    function Ty.HandleFact:typecheck_tree_handle_target()
        return nil
    end

    function Ty.HandleTarget:typecheck_tree_handle_target()
        return self.target
    end

    function Tr.TypeDecl:typecheck_tree_variant_defs(input)
        return {}
    end

    function Tr.TypeDeclEnumSugar:typecheck_tree_variant_defs(input)
        local variants = {}
        for i = 1, #self.variants do
            local name = variant_name_text(self.variants[i])
            variants[#variants + 1] = Check.TypeVariantCase(name, i - 1, void_ty(), {})
        end
        return { Check.TypeVariantDef(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.module_name, self.name)), variants) }
    end

    function Tr.TypeDeclTaggedUnionSugar:typecheck_tree_variant_defs(input)
        local variants = {}
        for i = 1, #self.variants do
            local v = self.variants[i]
            variants[#variants + 1] = Check.TypeVariantCase(v.name, i - 1, v.payload, v.fields or {})
        end
        return { Check.TypeVariantDef(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.module_name, self.name)), variants) }
    end

    function Tr.TypeDecl:typecheck_tree_handle_defs(input)
        return {}
    end

    function Tr.TypeDeclHandle:typecheck_tree_handle_defs(input)
        local domain, target = nil, nil
        for i = 1, #(self.facts or {}) do
            domain = self.facts[i]:typecheck_tree_handle_domain() or domain
            target = self.facts[i]:typecheck_tree_handle_target() or target
        end
        return { Check.TypeHandleDef(self.name, Ty.THandle(Ty.TypeRefGlobal(input.module_name, self.name), self.repr), self.repr, self.invalid, domain, target) }
    end

    function Tr.Func:typecheck_tree_effect_defs(input)
        return {}
    end

    function Tr.FuncLocal:typecheck_tree_effect_defs(input)
        return { Check.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    function Tr.FuncExport:typecheck_tree_effect_defs(input)
        return { Check.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    local function contract_effect_names(contracts)
        local readonly, preserve, invalidate = {}, {}, {}
        for i = 1, #(contracts or {}) do
            contracts[i]:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        end
        return readonly, preserve, invalidate
    end

    function Tr.FuncLocalContract:typecheck_tree_effect_defs(input)
        local readonly, preserve, invalidate = contract_effect_names(self.contracts)
        return { Check.TypeFuncEffect(self.name, self.params or {}, readonly, preserve, invalidate) }
    end

    function Tr.FuncExportContract:typecheck_tree_effect_defs(input)
        local readonly, preserve, invalidate = contract_effect_names(self.contracts)
        return { Check.TypeFuncEffect(self.name, self.params or {}, readonly, preserve, invalidate) }
    end

    function Tr.FuncDecl:typecheck_tree_effect_defs(input)
        return { Check.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    function Tr.FuncContract:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
    end

    function Tr.Expr:typecheck_tree_contract_name()
        return nil
    end

    function Tr.ExprRef:typecheck_tree_contract_name()
        return self.ref:typecheck_tree_contract_name()
    end

    function B.ValueRef:typecheck_tree_contract_name()
        return nil
    end

    function B.ValueRefName:typecheck_tree_contract_name()
        return self.name
    end

    function B.ValueRefBinding:typecheck_tree_contract_name()
        return self.binding and self.binding.name or nil
    end

    function Tr.FuncContract:typecheck_tree_contract(input)
        return self, {}
    end

    function Tr.ContractBounds:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local len = self.len:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, len.issues)
        return Tr.ContractBounds(base.expr, len.expr), issues
    end

    function Tr.ContractWindowBounds:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local base_len = self.base_len:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local start = self.start:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local len = self.len:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, base.issues)
        append_all(issues, base_len.issues)
        append_all(issues, start.issues)
        append_all(issues, len.issues)
        return Tr.ContractWindowBounds(base.expr, base_len.expr, start.expr, len.expr), issues
    end

    function Tr.ContractDisjoint:typecheck_tree_contract(input)
        local a = self.a:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local b = self.b:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, a.issues)
        append_all(issues, b.issues)
        return Tr.ContractDisjoint(a.expr, b.expr), issues
    end

    function Tr.ContractSameLen:typecheck_tree_contract(input)
        local a = self.a:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local b = self.b:typecheck_tree_expr(input:typecheck_tree_expr_input())
        local issues = {}
        append_all(issues, a.issues)
        append_all(issues, b.issues)
        return Tr.ContractSameLen(a.expr, b.expr), issues
    end

    function Tr.ContractSoAComponent:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractSoAComponent(base.expr, self.record_ty:typecheck_tree_canonical(input.scope), self.field_name, self.component_index), base.issues
    end

    function Tr.ContractNoAlias:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractNoAlias(base.expr), base.issues
    end

    function Tr.ContractReadonly:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractReadonly(base.expr), base.issues
    end

    function Tr.ContractWriteonly:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractWriteonly(base.expr), base.issues
    end

    function Tr.ContractInvalidate:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractInvalidate(base.expr), base.issues
    end

    function Tr.ContractPreserve:typecheck_tree_contract(input)
        local base = self.base:typecheck_tree_expr(input:typecheck_tree_expr_input())
        return Tr.ContractPreserve(base.expr), base.issues
    end

    function Tr.ContractReadonly:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        local name = self.base:typecheck_tree_contract_name()
        if name ~= nil then readonly[#readonly + 1] = name; preserve[#preserve + 1] = name end
    end

    function Tr.ContractPreserve:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        local name = self.base:typecheck_tree_contract_name()
        if name ~= nil then preserve[#preserve + 1] = name end
    end

    function Tr.ContractInvalidate:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
        local name = self.base:typecheck_tree_contract_name()
        if name ~= nil then invalidate[#invalidate + 1] = name end
    end

    function Tr.Item:typecheck_tree_variant_defs(input)
        return {}
    end

    function Tr.ItemType:typecheck_tree_variant_defs(input)
        return self.t:typecheck_tree_variant_defs(input)
    end

    function Tr.Item:typecheck_tree_handle_defs(input)
        return {}
    end

    function Tr.ItemType:typecheck_tree_handle_defs(input)
        return self.t:typecheck_tree_handle_defs(input)
    end

    function Tr.Item:typecheck_tree_region_defs(input)
        return {}
    end

    local function region_path(name)
        local parts = {}
        for part in tostring(name or ""):gmatch("[^%.]+") do parts[#parts + 1] = C.Name(part) end
        if #parts == 0 then parts[1] = C.Name(tostring(name or "")) end
        return C.Path(parts)
    end

    function Tr.ItemRegion:typecheck_tree_region_defs(input)
        return { Tr.TypeRegionDef(Tr.RegionInvokeTarget(region_path(self.region.name)), self.region) }
    end

    local function path_text(path)
        local parts = {}
        for i = 1, #(path and path.parts or {}) do parts[#parts + 1] = path.parts[i].text end
        return table.concat(parts, ".")
    end

    local function target_eq(a, b)
        return path_text(a and a.path) == path_text(b and b.path)
    end

    local function sanitize_name(s)
        s = tostring(s or ""):gsub("[^%w_]", "_")
        if s == "" then s = "region" end
        if s:match("^%d") then s = "_" .. s end
        return s
    end

    local function seal_base_for_target(target)
        return "__lalin_region_call_" .. sanitize_name(path_text(target.path))
    end

    local function find_region_def(regions, target)
        for i = 1, #(regions or {}) do
            if target_eq(regions[i].target, target) then return regions[i] end
        end
        return nil
    end

    local function has_region_call_target(targets, target)
        for i = 1, #(targets or {}) do
            if target_eq(targets[i], target) then return true end
        end
        return false
    end

    function Tr.Stmt:typecheck_tree_collect_region_call_targets(out) end

    function Tr.StmtRegionCall:typecheck_tree_collect_region_call_targets(out)
        if not has_region_call_target(out, self.target) then out[#out + 1] = self.target end
    end

    function Tr.Stmt:typecheck_tree_collect_region_root_call_targets(out) end

    function Tr.StmtRegionCall:typecheck_tree_collect_region_root_call_targets(out)
        if not has_region_call_target(out, self.target) then out[#out + 1] = self.target end
    end

    function Tr.Stmt:typecheck_tree_collect_region_emit_targets(out) end

    function Tr.StmtRegionEmit:typecheck_tree_collect_region_emit_targets(out)
        if not has_region_call_target(out, self.target) then out[#out + 1] = self.target end
    end

    function Tr.StmtIf:typecheck_tree_collect_region_call_targets(out)
        for i = 1, #(self.then_body or {}) do self.then_body[i]:typecheck_tree_collect_region_call_targets(out) end
        for i = 1, #(self.else_body or {}) do self.else_body[i]:typecheck_tree_collect_region_call_targets(out) end
    end

    function Tr.StmtIf:typecheck_tree_collect_region_root_call_targets(out)
        for i = 1, #(self.then_body or {}) do self.then_body[i]:typecheck_tree_collect_region_root_call_targets(out) end
        for i = 1, #(self.else_body or {}) do self.else_body[i]:typecheck_tree_collect_region_root_call_targets(out) end
    end

    function Tr.StmtIf:typecheck_tree_collect_region_emit_targets(out)
        for i = 1, #(self.then_body or {}) do self.then_body[i]:typecheck_tree_collect_region_emit_targets(out) end
        for i = 1, #(self.else_body or {}) do self.else_body[i]:typecheck_tree_collect_region_emit_targets(out) end
    end

    function Tr.StmtSwitch:typecheck_tree_collect_region_call_targets(out)
        for i = 1, #(self.arms or {}) do
            for j = 1, #(self.arms[i].body or {}) do self.arms[i].body[j]:typecheck_tree_collect_region_call_targets(out) end
        end
        for i = 1, #(self.variant_arms or {}) do
            for j = 1, #(self.variant_arms[i].body or {}) do self.variant_arms[i].body[j]:typecheck_tree_collect_region_call_targets(out) end
        end
        for i = 1, #(self.default_body or {}) do self.default_body[i]:typecheck_tree_collect_region_call_targets(out) end
    end

    function Tr.StmtSwitch:typecheck_tree_collect_region_root_call_targets(out)
        for i = 1, #(self.arms or {}) do
            for j = 1, #(self.arms[i].body or {}) do self.arms[i].body[j]:typecheck_tree_collect_region_root_call_targets(out) end
        end
        for i = 1, #(self.variant_arms or {}) do
            for j = 1, #(self.variant_arms[i].body or {}) do self.variant_arms[i].body[j]:typecheck_tree_collect_region_root_call_targets(out) end
        end
        for i = 1, #(self.default_body or {}) do self.default_body[i]:typecheck_tree_collect_region_root_call_targets(out) end
    end

    function Tr.StmtSwitch:typecheck_tree_collect_region_emit_targets(out)
        for i = 1, #(self.arms or {}) do
            for j = 1, #(self.arms[i].body or {}) do self.arms[i].body[j]:typecheck_tree_collect_region_emit_targets(out) end
        end
        for i = 1, #(self.variant_arms or {}) do
            for j = 1, #(self.variant_arms[i].body or {}) do self.variant_arms[i].body[j]:typecheck_tree_collect_region_emit_targets(out) end
        end
        for i = 1, #(self.default_body or {}) do self.default_body[i]:typecheck_tree_collect_region_emit_targets(out) end
    end

    function Tr.StmtControl:typecheck_tree_collect_region_call_targets(out)
        for i = 1, #(self.region.entry.body or {}) do self.region.entry.body[i]:typecheck_tree_collect_region_call_targets(out) end
        for i = 1, #(self.region.blocks or {}) do
            for j = 1, #(self.region.blocks[i].body or {}) do self.region.blocks[i].body[j]:typecheck_tree_collect_region_call_targets(out) end
        end
    end

    function Tr.StmtControl:typecheck_tree_collect_region_root_call_targets(out)
        for i = 1, #(self.region.entry.body or {}) do self.region.entry.body[i]:typecheck_tree_collect_region_root_call_targets(out) end
        for i = 1, #(self.region.blocks or {}) do
            for j = 1, #(self.region.blocks[i].body or {}) do self.region.blocks[i].body[j]:typecheck_tree_collect_region_root_call_targets(out) end
        end
    end

    function Tr.StmtControl:typecheck_tree_collect_region_emit_targets(out)
        for i = 1, #(self.region.entry.body or {}) do self.region.entry.body[i]:typecheck_tree_collect_region_emit_targets(out) end
        for i = 1, #(self.region.blocks or {}) do
            for j = 1, #(self.region.blocks[i].body or {}) do self.region.blocks[i].body[j]:typecheck_tree_collect_region_emit_targets(out) end
        end
    end

    function Tr.Func:typecheck_tree_collect_region_call_targets(out)
        for i = 1, #(self.body or {}) do self.body[i]:typecheck_tree_collect_region_call_targets(out) end
    end

    function Tr.Func:typecheck_tree_collect_region_root_call_targets(out)
        for i = 1, #(self.body or {}) do self.body[i]:typecheck_tree_collect_region_root_call_targets(out) end
    end

    function Tr.Func:typecheck_tree_collect_region_emit_targets(out)
        for i = 1, #(self.body or {}) do self.body[i]:typecheck_tree_collect_region_emit_targets(out) end
    end

    function Tr.Item:typecheck_tree_collect_region_call_targets(out) end
    function Tr.Item:typecheck_tree_collect_region_root_call_targets(out) end
    function Tr.Item:typecheck_tree_collect_region_emit_targets(out) end

    function Tr.ItemFunc:typecheck_tree_collect_region_call_targets(out)
        self.func:typecheck_tree_collect_region_call_targets(out)
    end

    function Tr.ItemFunc:typecheck_tree_collect_region_root_call_targets(out)
        self.func:typecheck_tree_collect_region_root_call_targets(out)
    end

    function Tr.ItemFunc:typecheck_tree_collect_region_emit_targets(out)
        self.func:typecheck_tree_collect_region_emit_targets(out)
    end

    function Tr.ItemRegion:typecheck_tree_collect_region_call_targets(out)
        for i = 1, #(self.region.entry.body or {}) do self.region.entry.body[i]:typecheck_tree_collect_region_call_targets(out) end
        for i = 1, #(self.region.blocks or {}) do
            for j = 1, #(self.region.blocks[i].body or {}) do self.region.blocks[i].body[j]:typecheck_tree_collect_region_call_targets(out) end
        end
    end

    function Ty.Type:protocol_param_name() error("missing protocol_param_name leaf method on " .. tostring(self), 2) end
    function Ty.TScalar:protocol_param_name()
        local s = self.scalar
        if s == C.ScalarVoid then return "void"
        elseif s == C.ScalarBool then return "bool"
        elseif s == C.ScalarI8 then return "i8" elseif s == C.ScalarI16 then return "i16"
        elseif s == C.ScalarI32 then return "i32" elseif s == C.ScalarI64 then return "i64"
        elseif s == C.ScalarU8 then return "u8" elseif s == C.ScalarU16 then return "u16"
        elseif s == C.ScalarU32 then return "u32" elseif s == C.ScalarU64 then return "u64"
        elseif s == C.ScalarF32 then return "f32" elseif s == C.ScalarF64 then return "f64"
        elseif s == C.ScalarRawPtr then return "rawptr"
        elseif s == C.ScalarIndex then return "index" end
        return "scalar"
    end
    function Ty.TPtr:protocol_param_name() return "ptr_" .. self.elem:protocol_param_name() end
    function Ty.TArray:protocol_param_name() return "arr" .. tostring(self.count.count) .. "_" .. self.elem:protocol_param_name() end
    function Ty.TSlice:protocol_param_name() return "slice_" .. self.elem:protocol_param_name() end
    function Ty.TView:protocol_param_name() return "view_" .. self.elem:protocol_param_name() end
    function Ty.TLease:protocol_param_name() return "lease_" .. self.base:protocol_param_name() end
    function Ty.TOwned:protocol_param_name() return self.base:protocol_param_name() end
    function Ty.TAccess:protocol_param_name() return self.base:protocol_param_name() end
    function Ty.TNamed:protocol_param_name() return self.ref:protocol_param_name() end
    function Ty.TypeRef:protocol_param_name() return "ref" end
    function Ty.TypeRefGlobal:protocol_param_name() return sanitize_name(self.module_name) .. "_" .. sanitize_name(self.type_name) end
    function Ty.TypeRefLocal:protocol_param_name() return sanitize_name(self.sym.name) end
    function Ty.TypeRefPath:protocol_param_name()
        local parts = {}
        for _, p in ipairs(self.path.parts or {}) do parts[#parts+1] = p.text end
        return sanitize_name(table.concat(parts, "_"))
    end
    function Ty.THandle:protocol_param_name() return "handle_" .. self.ref:protocol_param_name() end
    function Ty.TCType:protocol_param_name() return sanitize_name(self.id.module_name) .. "_" .. sanitize_name(self.id.spelling) end
    function Ty.TCFuncPtr:protocol_param_name() return "cfunc_" .. sanitize_name(self.sig.text) end

    local function protocol_key_for_region(region)
        local parts = {}
        for i, cont in ipairs(region.conts or {}) do
            parts[#parts + 1] = cont.name
            for j, param in ipairs(cont.params or {}) do
                parts[#parts + 1] = param.name .. "_" .. param.ty:protocol_param_name()
            end
        end
        return table.concat(parts, "__")
    end

    local function protocol_type_base(key)
        return "__lalin_region_protocol_" .. sanitize_name(key)
    end

    local function find_protocol(protocols, key)
        for i = 1, #(protocols or {}) do
            if protocols[i].key == key then return protocols[i] end
        end
        return nil
    end

    local function region_protocol_for(region)
        local key = protocol_key_for_region(region)
        local base = protocol_type_base(key)
        local payloads = {}
        for i = 1, #(region.conts or {}) do
            local cont = region.conts[i]
            if #(cont.params or {}) > 0 then
                payloads[#payloads + 1] = Tr.RegionSealPayload(cont, base .. "_" .. sanitize_name(cont.name) .. "_payload")
            end
        end
        return Tr.RegionProtocol(key, base .. "_result", payloads)
    end

    local function region_seal_for_def(def, protocol)
        return Tr.RegionSeal(def.target, def.region, seal_base_for_target(def.target), protocol)
    end

    function Tr.Module:typecheck_tree_region_call_seals(input, regions)
        local targets, protocols, seals = {}, {}, {}
        for i = 1, #self.items do self.items[i]:typecheck_tree_collect_region_call_targets(targets) end
        for i = 1, #targets do
            local def = find_region_def(regions, targets[i])
            if def ~= nil then
                local candidate = region_protocol_for(def.region)
                local protocol = find_protocol(protocols, candidate.key)
                if protocol == nil then
                    protocol = candidate
                    protocols[#protocols + 1] = protocol
                end
                seals[#seals + 1] = region_seal_for_def(def, protocol)
            end
        end
        return protocols, seals
    end

    local function find_seal(seals, target)
        for i = 1, #(seals or {}) do
            if target_eq(seals[i].target, target) then return seals[i] end
        end
        return nil
    end

    local function wire_forwards_cont_name(wire, name)
        return wire ~= nil and wire.target ~= nil and wire.target.cont ~= nil and wire.target.cont.name == name
    end

    local function find_wire(wiring, name)
        for i = 1, #(wiring or {}) do
            if wiring[i].name == name then return wiring[i] end
        end
        return nil
    end

    local function call_forwards_protocol(stmt, source_seal, target_seal)
        if target_seal == nil or target_seal.protocol.key ~= source_seal.protocol.key then return false end
        for i, cont in ipairs(target_seal.region.conts or {}) do
            if not wire_forwards_cont_name(find_wire(stmt.wiring or {}, cont.name), cont.name) then return false end
        end
        return true
    end

    function Tr.Stmt:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end

    function Tr.StmtRegionCall:typecheck_tree_collect_forward_region_targets(source_seal, seals, out)
        local target_seal = find_seal(seals, self.target)
        if target_seal ~= nil and target_seal.protocol.key == source_seal.protocol.key and not has_region_call_target(out, self.target) then
            out[#out + 1] = self.target
        end
    end

    function Tr.StmtIf:typecheck_tree_collect_forward_region_targets(source_seal, seals, out)
        for i = 1, #(self.then_body or {}) do self.then_body[i]:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end
        for i = 1, #(self.else_body or {}) do self.else_body[i]:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end
    end

    function Tr.StmtSwitch:typecheck_tree_collect_forward_region_targets(source_seal, seals, out)
        for i = 1, #(self.arms or {}) do
            for j = 1, #(self.arms[i].body or {}) do self.arms[i].body[j]:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end
        end
        for i = 1, #(self.variant_arms or {}) do
            for j = 1, #(self.variant_arms[i].body or {}) do self.variant_arms[i].body[j]:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end
        end
        for i = 1, #(self.default_body or {}) do self.default_body[i]:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end
    end

    function Tr.StmtControl:typecheck_tree_collect_forward_region_targets(source_seal, seals, out)
        for i = 1, #(self.region.entry.body or {}) do self.region.entry.body[i]:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end
        for i = 1, #(self.region.blocks or {}) do
            for j = 1, #(self.region.blocks[i].body or {}) do self.region.blocks[i].body[j]:typecheck_tree_collect_forward_region_targets(source_seal, seals, out) end
        end
    end

    local function bundle_entry_label(target)
        return Tr.BlockLabel("__bundle_entry_" .. sanitize_name(path_text(target.path)))
    end

    local function member_in_list(members, seal)
        for i = 1, #(members or {}) do
            if target_eq(members[i].seal.target, seal.target) then return true end
        end
        return false
    end

    local function bundle_member_namespace(target)
        return "region_bundle_member:" .. sanitize_name(path_text(target.path))
    end

    local function add_bundle_member(members, seal)
        if not member_in_list(members, seal) then members[#members + 1] = Tr.RegionBundleMember(seal, bundle_entry_label(seal.target), bundle_member_namespace(seal.target)) end
    end

    local function collect_region_body_call_targets(region, out)
        for i = 1, #(region.entry.body or {}) do region.entry.body[i]:typecheck_tree_collect_region_call_targets(out) end
        for i = 1, #(region.blocks or {}) do
            for j = 1, #(region.blocks[i].body or {}) do region.blocks[i].body[j]:typecheck_tree_collect_region_call_targets(out) end
        end
    end

    function Tr.Module:typecheck_tree_region_bundles(input, regions, seals)
        local root_targets, emit_targets, bundles = {}, {}, {}
        for i = 1, #self.items do
            self.items[i]:typecheck_tree_collect_region_root_call_targets(root_targets)
            self.items[i]:typecheck_tree_collect_region_emit_targets(emit_targets)
        end
        for i = 1, #emit_targets do
            local emitted = find_region_def(regions, emit_targets[i])
            if emitted ~= nil then collect_region_body_call_targets(emitted.region, root_targets) end
        end
        for i = 1, #root_targets do
            local root = find_seal(seals, root_targets[i])
            if root ~= nil then
                local members, scan = {}, {}
                add_bundle_member(members, root)
                scan[1] = root
                local scan_index = 1
                while scan_index <= #scan do
                    local seal = scan[scan_index]
                    scan_index = scan_index + 1
                    local forward_targets = {}
                    for j = 1, #(seal.region.entry.body or {}) do seal.region.entry.body[j]:typecheck_tree_collect_forward_region_targets(seal, seals, forward_targets) end
                    for j = 1, #(seal.region.blocks or {}) do
                        for k = 1, #(seal.region.blocks[j].body or {}) do seal.region.blocks[j].body[k]:typecheck_tree_collect_forward_region_targets(seal, seals, forward_targets) end
                    end
                    for j = 1, #forward_targets do
                        local target_seal = find_seal(seals, forward_targets[j])
                        if target_seal ~= nil and not member_in_list(members, target_seal) then
                            add_bundle_member(members, target_seal)
                            scan[#scan + 1] = target_seal
                        end
                    end
                end
                bundles[#bundles + 1] = Tr.RegionBundle(root, members)
            end
        end
        return bundles
    end

    function Tr.Item:typecheck_tree_effect_defs(input)
        return {}
    end

    function Tr.ItemFunc:typecheck_tree_effect_defs(input)
        return self.func:typecheck_tree_effect_defs(input)
    end

    function Tr.ItemExtern:typecheck_tree_effect_defs(input)
        return { Check.TypeFuncEffect(self.func.name, self.func.params or {}, {}, {}, {}) }
    end

    function Tr.Module:typecheck_tree_module_facts(input)
        local variants, handles, effects, regions = {}, {}, {}, {}
        for i = 1, #self.items do
            local item = self.items[i]
            local item_variants = item:typecheck_tree_variant_defs(input)
            for j = 1, #item_variants do variants[#variants + 1] = item_variants[j] end
            local item_handles = item:typecheck_tree_handle_defs(input)
            for j = 1, #item_handles do handles[#handles + 1] = item_handles[j] end
            local item_effects = item:typecheck_tree_effect_defs(input)
            for j = 1, #item_effects do effects[#effects + 1] = item_effects[j] end
            local item_regions = item:typecheck_tree_region_defs(input)
            for j = 1, #item_regions do regions[#regions + 1] = item_regions[j] end
        end
        local region_protocols, region_seals = self:typecheck_tree_region_call_seals(input, regions)
        local region_bundles = self:typecheck_tree_region_bundles(input, regions, region_seals)
        return Check.TypeModuleFacts(variants, handles, effects, regions, region_protocols, region_seals, region_bundles)
    end
end
