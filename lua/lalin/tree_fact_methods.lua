return function(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local Tr = T.LalinTree

    local function void_ty()
        return Ty.TScalar(C.ScalarVoid)
    end

    local function variant_name_text(v)
        return v and (v.text or v.name) or tostring(v)
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
            variants[#variants + 1] = Tr.TypeVariantCase(name, i - 1, void_ty(), {})
        end
        return { Tr.TypeVariantDef(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.module_name, self.name)), variants) }
    end

    function Tr.TypeDeclTaggedUnionSugar:typecheck_tree_variant_defs(input)
        local variants = {}
        for i = 1, #self.variants do
            local v = self.variants[i]
            variants[#variants + 1] = Tr.TypeVariantCase(v.name, i - 1, v.payload, v.fields or {})
        end
        return { Tr.TypeVariantDef(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.module_name, self.name)), variants) }
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
        return { Tr.TypeHandleDef(self.name, Ty.THandle(Ty.TypeRefGlobal(input.module_name, self.name), self.repr), self.repr, self.invalid, domain, target) }
    end

    function Tr.Func:typecheck_tree_effect_defs(input)
        return {}
    end

    function Tr.FuncLocal:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    function Tr.FuncExport:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
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
        return { Tr.TypeFuncEffect(self.name, self.params or {}, readonly, preserve, invalidate) }
    end

    function Tr.FuncExportContract:typecheck_tree_effect_defs(input)
        local readonly, preserve, invalidate = contract_effect_names(self.contracts)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, readonly, preserve, invalidate) }
    end

    function Tr.FuncDecl:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.name, self.params or {}, {}, {}, {}) }
    end

    function Tr.FuncContract:typecheck_tree_append_effect_names(readonly, preserve, invalidate)
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

    function Tr.Item:typecheck_tree_effect_defs(input)
        return {}
    end

    function Tr.ItemFunc:typecheck_tree_effect_defs(input)
        return self.func:typecheck_tree_effect_defs(input)
    end

    function Tr.ItemExtern:typecheck_tree_effect_defs(input)
        return { Tr.TypeFuncEffect(self.func.name, self.func.params or {}, {}, {}, {}) }
    end

    function Tr.Module:typecheck_tree_module_facts(input)
        local variants, handles, effects = {}, {}, {}
        for i = 1, #self.items do
            local item = self.items[i]
            local item_variants = item:typecheck_tree_variant_defs(input)
            for j = 1, #item_variants do variants[#variants + 1] = item_variants[j] end
            local item_handles = item:typecheck_tree_handle_defs(input)
            for j = 1, #item_handles do handles[#handles + 1] = item_handles[j] end
            local item_effects = item:typecheck_tree_effect_defs(input)
            for j = 1, #item_effects do effects[#effects + 1] = item_effects[j] end
        end
        return Tr.TypeModuleFacts(variants, handles, effects)
    end
end
