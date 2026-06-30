local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function class_name(x)
    return tostring(x)
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.tree_to_code ~= nil then return T._lalin_api_cache.tree_to_code end

    local Core = T.LalinCore
    local Ty = T.LalinType
    local Bind = T.LalinBind
    local Sem = T.LalinSem
    local Host = T.LalinHost
    local Tr = T.LalinTree
    local Code = T.LalinCode

    local CodeType = require("lalin.code_type")(T)
    local TypeSizeAlign = require("lalin.type_size_align")(T)
    local ModuleType = require("lalin.tree_module_type")(T)
    local ConstEval = require("lalin.sem_const_eval")(T)
    local TreeContractFacts = require("lalin.tree_contract_facts")(T)
    local api = {}
    local variant_name_text
    local source_access_base
    local expr_type
    local place_type

    function Tr.ModuleHeader:tree_code_module_name() return "module" end
    function Tr.ModuleTyped:tree_code_module_name() return self.module_name end
    function Tr.ModuleSem:tree_code_module_name() return self.module_name end
    function Tr.ModuleCode:tree_code_module_name() return self.module_name end
    function Tr.Module:tree_code_module_name() return self.h:tree_code_module_name() end

    function Core.Scalar:tree_code_is_void_scalar() return false end
    function Core.ScalarVoid:tree_code_is_void_scalar() return true end

    function Ty.Type:tree_code_is_void_type() return false end
    function Ty.TScalar:tree_code_is_void_type() return self.scalar:tree_code_is_void_scalar() end

    function Ty.Type:tree_code_source_access_base() return self end
    function Ty.TLease:tree_code_source_access_base() return self.base end
    function Ty.TOwned:tree_code_source_access_base() return self.base:tree_code_source_access_base() end
    function Ty.TAccess:tree_code_source_access_base() return self.base:tree_code_source_access_base() end

    function Ty.Type:tree_code_named_type_name() return nil end
    function Ty.TNamed:tree_code_named_type_name() return self.ref:tree_code_type_ref_name() end
    function Ty.TypeRef:tree_code_type_ref_name() return nil end
    function Ty.TypeRefGlobal:tree_code_type_ref_name() return self.type_name end
    function Ty.TypeRefLocal:tree_code_type_ref_name() return self.sym.name end
    function Ty.TypeRefPath:tree_code_type_ref_name()
        if #self.path.parts == 0 then return nil end
        return self.path.parts[#self.path.parts].text
    end

    function Tr.TypeDecl:tree_code_add_variant_defs(defs, mod_name) end
    function Tr.TypeDeclEnumSugar:tree_code_add_variant_defs(defs, mod_name)
        local variants = {}
        for i = 1, #self.variants do
            local name = variant_name_text(self.variants[i])
            variants[name] = Tr.TreeCodeVariantEntry(name, Tr.TreeCodeVariant(name, i - 1, Ty.TScalar(Core.ScalarVoid), {}))
        end
        defs[self.name] = Tr.TreeCodeVariantDefEntry(self.name, Tr.TreeCodeVariantDef(Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)), variants))
    end
    function Tr.TypeDeclTaggedUnionSugar:tree_code_add_variant_defs(defs, mod_name)
        local variants = {}
        for i = 1, #self.variants do
            local v = self.variants[i]
            variants[v.name] = Tr.TreeCodeVariantEntry(v.name, Tr.TreeCodeVariant(v.name, i - 1, v.payload, v.fields or {}))
        end
        defs[self.name] = Tr.TreeCodeVariantDefEntry(self.name, Tr.TreeCodeVariantDef(Ty.TNamed(Ty.TypeRefGlobal(mod_name, self.name)), variants))
    end
    function Tr.Item:tree_code_add_variant_defs(defs, mod_name) end
    function Tr.ItemType:tree_code_add_variant_defs(defs, mod_name)
        self.t:tree_code_add_variant_defs(defs, mod_name)
    end

    function Tr.ExprHeader:tree_code_expr_type() return nil end
    function Tr.ExprTyped:tree_code_expr_type() return self.ty end
    function Tr.PlaceHeader:tree_code_place_type() return nil end
    function Tr.PlaceTyped:tree_code_place_type() return self.ty end

    function Ty.Type:tree_code_index_elem_type() return nil end
    function Ty.TPtr:tree_code_index_elem_type() return self.elem end
    function Ty.TArray:tree_code_index_elem_type() return self.elem end
    function Ty.TSlice:tree_code_index_elem_type() return self.elem end
    function Ty.TView:tree_code_index_elem_type() return self.elem end
    function Tr.IndexBase:tree_code_index_base_elem_type() return nil end
    function Tr.IndexBaseExpr:tree_code_index_base_elem_type()
        return source_access_base(expr_type(self.base)):tree_code_index_elem_type()
    end
    function Tr.IndexBasePlace:tree_code_index_base_elem_type() return self.elem end
    function Tr.IndexBaseView:tree_code_index_base_elem_type() return self.view.elem end

    function Code.CodeType:tree_code_is_float_type() return false end
    function Code.CodeTyFloat:tree_code_is_float_type() return true end
    function Code.CodeType:tree_code_is_aggregate_type() return false end
    function Code.CodeTyNamed:tree_code_is_aggregate_type() return true end
    function Code.CodeTyArray:tree_code_is_aggregate_type() return true end
    function Code.CodeTySlice:tree_code_is_aggregate_type() return true end
    function Code.CodeTyView:tree_code_is_aggregate_type() return true end
    function Code.CodeTyClosure:tree_code_is_aggregate_type() return true end
    function Code.CodeType:tree_code_is_view_type() return false end
    function Code.CodeTyView:tree_code_is_view_type() return true end

    function Ty.TypeMemLayoutResult:tree_code_known_layout() return nil end
    function Ty.TypeMemLayoutKnown:tree_code_known_layout() return self.layout end

    local function unsupported(tree_code_input, node, what)
        local site = tree_code_input and tree_code_input:tree_code_func_name() or "module"
        error("tree_to_code unsupported lowering: " .. tostring(what or class_name(node)) .. " in " .. site, 3)
    end

    function Tr.TreeCodeInput:tree_code_expr_result(value, ty)
        return Tr.TreeCodeExprResult(value, ty, self:tree_code_state())
    end

    function Tr.TreeCodeInput:tree_code_place_result(place)
        return Tr.TreeCodePlaceResult(place, self:tree_code_state())
    end

    function Tr.TreeCodeInput:tree_code_module_facts() return self.facts.module_facts end
    function Tr.TreeCodeContractInput:tree_code_module_facts() return self.module_facts end

    function Tr.TreeCodeInput:tree_code_module_sigs() return self.facts.sigs end
    function Tr.TreeCodeContractInput:tree_code_module_sigs() return self.sigs end

    function Tr.TreeCodeInput:tree_code_module_emission() return self.facts.module_emission end

    function Tr.TreeCodeInput:tree_code_func_facts() return self.facts end

    function Tr.TreeCodeInput:tree_code_func_name() return self.facts.func_name end
    function Tr.TreeCodeContractInput:tree_code_func_name() return self.func_name end

    function Tr.TreeCodeInput:tree_code_state() return self.state end

    function Bind.Binding:tree_code_binding_key()
        if self.id and self.id.text then return self.id.text end
        return tostring(self.name)
    end

    local function clone_map(t)
        local out = {}
        for k, v in pairs(t or {}) do out[k] = v end
        return out
    end

    local function clone_array(t)
        local out = {}
        for i = 1, #(t or {}) do out[i] = t[i] end
        return out
    end

    local function map_with(t, key, value)
        local out = clone_map(t)
        out[key] = value
        return out
    end

    local function map_without(t, key)
        local out = clone_map(t)
        out[key] = nil
        return out
    end

    local function array_with(t, index, value)
        local out = clone_array(t)
        out[index] = value
        return out
    end

    local function array_append(t, value)
        local out = clone_array(t)
        out[#out + 1] = value
        return out
    end

    local function state_with(self, parts)
        return Tr.TreeCodeFuncState(
            parts.bindings or self.bindings,
            parts.residence or self.residence,
            parts.emission or self.emission,
            parts.counters or self.counters,
            parts.alpha or self.alpha,
            parts.control or self.control
        )
    end

    function Tr.TreeCodeFuncState:tree_code_scoped_binding_key(binding)
        local key = binding:tree_code_binding_key()
        local alpha = self.alpha.renamed_by_key
        local entry = alpha and alpha[key] or nil
        if entry ~= nil then return entry.renamed end
        return key
    end

    function Tr.TreeCodeFuncState:tree_code_binding_alpha_suffix()
        local entry = self.alpha.current_suffix_by_slot and self.alpha.current_suffix_by_slot.current
        return entry and entry.suffix or nil
    end

    function Tr.TreeCodeFuncState:tree_code_declare_binding_key(binding)
        local key = binding:tree_code_binding_key()
        local suffix = self:tree_code_binding_alpha_suffix()
        local state = self
        if self.alpha.renamed_by_key ~= nil and suffix ~= nil and self.alpha.renamed_by_key[key] == nil then
            local alpha = Tr.TreeCodeAlphaState(map_with(self.alpha.renamed_by_key, key, Tr.TreeCodeAlphaRenameEntry(key, key .. "@" .. suffix)), self.alpha.current_suffix_by_slot, self.alpha.seq)
            state = state_with(self, { alpha = alpha })
        end
        return Tr.TreeCodeBindingKeyResult(state:tree_code_scoped_binding_key(binding), state)
    end

    function Tr.TreeCodeFuncState:tree_code_declare_fresh_binding_key(binding)
        local key = binding:tree_code_binding_key()
        local suffix = self:tree_code_binding_alpha_suffix()
        local state = self
        if self.alpha.renamed_by_key ~= nil and suffix ~= nil then
            local counter = self:tree_code_next_counter("binding_alpha")
            state = counter.state
            local alpha = Tr.TreeCodeAlphaState(map_with(state.alpha.renamed_by_key, key, Tr.TreeCodeAlphaRenameEntry(key, key .. "@" .. suffix .. "_l" .. tostring(counter.value))), state.alpha.current_suffix_by_slot, state.alpha.seq)
            state = state_with(state, { alpha = alpha })
        end
        return Tr.TreeCodeBindingKeyResult(state:tree_code_scoped_binding_key(binding), state)
    end

    function Tr.TreeCodeInput:tree_code_binding_is_addressed(binding)
        local key = binding:tree_code_binding_key()
        local scoped = self:tree_code_state():tree_code_scoped_binding_key(binding)
        local state = self:tree_code_state()
        return (state.residence.addressed_by_key and (state.residence.addressed_by_key[key] or state.residence.addressed_by_key[scoped])) or false
    end

    function Tr.TreeCodeInput:tree_code_binding_is_mutable(binding)
        local key = binding:tree_code_binding_key()
        local scoped = self:tree_code_state():tree_code_scoped_binding_key(binding)
        local state = self:tree_code_state()
        return (state.residence.mutable_by_key and (state.residence.mutable_by_key[key] or state.residence.mutable_by_key[scoped])) or false
    end

    source_access_base = function(ty)
        return ty:tree_code_source_access_base()
    end

    variant_name_text = function(v)
        if type(v) == "string" then return v end
        return v and (v.text or v.name) or tostring(v)
    end

    function Tr.Module:tree_code_variant_defs(module_name)
        local defs = {}
        for i = 1, #(self.items or {}) do
            self.items[i]:tree_code_add_variant_defs(defs, module_name)
        end
        return defs
    end

    local function func_key(module_name, item_name)
        return tostring(module_name or "") .. "\0" .. tostring(item_name or "")
    end

    local function code_func_id(item_name)
        return Code.CodeFuncId("fn:" .. tostring(item_name))
    end

    local function code_extern_id(name)
        return Code.CodeExternId("extern:" .. tostring(name))
    end

    local function code_global_id(module_name, item_name)
        return Code.CodeGlobalId("global:" .. tostring(module_name or "") .. ":" .. tostring(item_name or ""))
    end

    local function code_data_id(id)
        return Code.CodeDataId("data:" .. tostring(id and id.text or id))
    end

    local function decoded_string_bytes(bytes)
        bytes = tostring(bytes or "")
        local first = bytes:sub(1, 1)
        if (first == '"' or first == "'") and bytes:sub(-1) == first then
            local loader = loadstring or load
            local fn = loader("return " .. bytes)
            if fn then
                local ok, value = pcall(fn)
                if ok and type(value) == "string" then return value end
            end
        end
        return bytes
    end

    function Tr.TreeCodeModuleParts:tree_code_func_lowering_start(func_name, residence)
        residence = residence or {}
        return Tr.TreeCodeFuncLoweringStart(
            Tr.TreeCodeFuncFacts(self.module_facts, self.sigs, self.registrations, self.emission, func_name),
            Tr.TreeCodeFuncState(
                Tr.TreeCodeBindingState({}, {}),
                Tr.TreeCodeResidenceFacts(residence.addressed or {}, residence.mutable or {}),
                Tr.TreeCodeEmissionState({}, {}, {}),
                Tr.TreeCodeCounterState({}),
                Tr.TreeCodeAlphaState({}, {}, 0),
                Tr.TreeCodeControlState({}, {})
            )
        )
    end

    function Tr.TreeCodeItemLowerInput:tree_code_func_lowering_start(func_name, residence)
        return Tr.TreeCodeModuleParts(self.module_facts, self.sigs, self.registrations, self.emission):tree_code_func_lowering_start(func_name, residence)
    end

    local function tree_code_target(raw_target)
        local target = raw_target and raw_target.c_target or raw_target
        local ok, normalized = pcall(CodeType.normalize_target, target)
        if ok then return normalized end
        return CodeType.default_target({
            pointer_bits = target and target.pointer_bits or nil,
            index_bits = target and (target.index_bits or target.pointer_bits) or nil,
            endian = type(target and target.endian) == "string" and target.endian or nil,
        })
    end

    function Tr.TreeCodeInput:tree_code_fresh_string_data(bytes)
        local module_facts = self:tree_code_module_facts()
        local emission = self:tree_code_module_emission()
        local next_string_data = ((emission.counters and emission.counters.string_data and emission.counters.string_data.next_value) or 0) + 1
        emission.counters.string_data = Tr.TreeCodeCounterEntry("string_data", next_string_data)
        local stem = "str_" .. sanitize(self:tree_code_func_name()) .. "_" .. tostring(next_string_data)
        local id = Code.CodeDataId("data:" .. tostring(module_facts.module_name or "module") .. ":" .. stem)
        local decoded = decoded_string_bytes(bytes)
        local nul_terminated = decoded .. "\0"
        emission.generated_data[#emission.generated_data + 1] = Code.CodeData(
            id,
            stem,
            Code.CodeLinkageLocal,
            #nul_terminated,
            1,
            { Code.CodeDataBytes(0, nul_terminated) },
            Code.CodeOriginGenerated("string literal " .. stem)
        )
        return id, #decoded
    end

    function Tr.TreeCodeModuleSigState:tree_code_sig_entry(sig)
        return Tr.TreeCodeSigEntry(sig.id.text, sig)
    end

    function Tr.TreeCodeInput:tree_code_value_id_for_binding(binding)
        return Code.CodeValueId("v:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(self:tree_code_state():tree_code_scoped_binding_key(binding)))
    end

    function Tr.TreeCodeInput:tree_code_local_id_for_binding(binding)
        return Code.CodeLocalId("local:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(self:tree_code_state():tree_code_scoped_binding_key(binding)))
    end

    local function origin_binding(binding)
        if binding ~= nil then return Code.CodeOriginBinding(binding) end
        return Code.CodeOriginUnknown
    end

    local function origin_generated(reason)
        return Code.CodeOriginGenerated(reason)
    end

    expr_type = function(expr)
        local h = expr and expr.h
        if h ~= nil then
            local ty = h:tree_code_expr_type()
            if ty ~= nil then return ty end
        end
        unsupported(nil, expr, "untyped expression " .. class_name(expr))
    end

    place_type = function(place)
        local h = place and place.h
        if h ~= nil then
            local ty = h:tree_code_place_type()
            if ty ~= nil then return ty end
        end
        unsupported(nil, place, "untyped place " .. class_name(place))
    end

    local function index_base_elem_ty(base)
        local elem = base:tree_code_index_base_elem_type()
        if elem ~= nil then return elem end
        unsupported(nil, base, "index base without element type " .. class_name(base))
    end

    function Tr.TreeCodeInput:tree_code_type(ty)
        return CodeType.type_to_code(ty, self:tree_code_module_sigs())
    end
    function Tr.TreeCodeContractInput:tree_code_type(ty)
        return CodeType.type_to_code(ty, self:tree_code_module_sigs())
    end

    local function u8_code_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    function Tr.TreeCodeInput:tree_code_variant_def(type_name)
        local module_facts = self:tree_code_module_facts()
        local entry = module_facts.variant_defs and module_facts.variant_defs[type_name] or nil
        return entry and entry.def or nil
    end

    function Tr.TreeCodeVariant:tree_code_payload_type(input)
        if #(self.fields or {}) > 1 then unsupported(input, self, "multi-field variant payload `" .. tostring(self.name) .. "`") end
        local ty = (#(self.fields or {}) == 1) and self.fields[1].ty or self.payload
        if ty == nil or ty:tree_code_is_void_type() then return nil end
        return ty
    end

    function Tr.TreeCodeVariant:tree_code_ref(input, owner_ty)
        local payload_ty = self:tree_code_payload_type(input)
        return Code.CodeVariantRef(input:tree_code_type(owner_ty), self.name, self.tag, payload_ty and input:tree_code_type(payload_ty) or nil)
    end

    function Tr.TreeCodeInput:tree_code_variant_payload_type(variant)
        return variant:tree_code_payload_type(self)
    end

    function Tr.TreeCodeInput:tree_code_variant_ref(owner_ty, variant)
        return variant:tree_code_ref(self, owner_ty)
    end

    function Tr.TreeCodeInput:tree_code_layout_of(ty)
        local module_facts = self:tree_code_module_facts()
        local result = TypeSizeAlign.result(ty, module_facts.layout_env, module_facts.target)
        return result:tree_code_known_layout()
    end

    function Tr.TreeCodeInput:tree_code_align_of(ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.align or 1
    end

    function Tr.TreeCodeInput:tree_code_size_of(ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.size or nil
    end

    function Tr.TreeCodeContractInput:tree_code_layout_of(ty)
        local module_facts = self:tree_code_module_facts()
        local result = TypeSizeAlign.result(ty, module_facts.layout_env, module_facts.target)
        return result:tree_code_known_layout()
    end

    function Tr.TreeCodeContractInput:tree_code_align_of(ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.align or 1
    end

    function Tr.TreeCodeContractInput:tree_code_size_of(ty)
        local layout = self:tree_code_layout_of(ty)
        return layout and layout.size or nil
    end

    local function variant_binding(kind, variant, bind)
        return Bind.Binding(Core.Id("variant:" .. kind .. ":" .. variant.name .. ":" .. bind.name), bind.name, bind.ty, Bind.BindingRoleLocalValue)
    end

    local label_key

    function Tr.TreeCodeFuncState:tree_code_next_counter(name)
        local entry = self.counters.values_by_name[name]
        local next_value = ((entry and entry.next_value) or 0) + 1
        local counters = Tr.TreeCodeCounterState(map_with(self.counters.values_by_name, name, Tr.TreeCodeCounterEntry(name, next_value)))
        return Tr.TreeCodeCounterResult(next_value, state_with(self, { counters = counters }))
    end

    function Tr.TreeCodeFuncState:tree_code_current_block()
        return self.emission.current_blocks and self.emission.current_blocks[1] or nil
    end

    function Tr.TreeCodeFuncState:tree_code_has_current_block()
        return self:tree_code_current_block() ~= nil
    end

    function Tr.TreeCodeFuncState:tree_code_set_current_block(block)
        local emission = Tr.TreeCodeEmissionState(self.emission.locals, self.emission.blocks, { block })
        return Tr.TreeCodeStateResult(state_with(self, { emission = emission }))
    end

    function Tr.TreeCodeFuncState:tree_code_clear_current_block()
        local emission = Tr.TreeCodeEmissionState(self.emission.locals, self.emission.blocks, {})
        return Tr.TreeCodeStateResult(state_with(self, { emission = emission }))
    end

    function Tr.TreeCodeFuncState:tree_code_append_block(block)
        local emission = Tr.TreeCodeEmissionState(self.emission.locals, array_append(self.emission.blocks, block), self.emission.current_blocks)
        return Tr.TreeCodeStateResult(state_with(self, { emission = emission }))
    end

    function Tr.TreeCodeFuncState:tree_code_save_bindings()
        return Tr.TreeCodeBindingSnapshot(clone_map(self.bindings.values_by_key), clone_map(self.bindings.locals_by_key))
    end

    function Tr.TreeCodeFuncState:tree_code_restore_bindings(saved)
        local bindings = Tr.TreeCodeBindingState(clone_map(saved.bindings), clone_map(saved.locals_by_key))
        return Tr.TreeCodeStateResult(state_with(self, { bindings = bindings }))
    end

    function Tr.TreeCodeFuncState:tree_code_note_binding(binding, value)
        local key = self:tree_code_scoped_binding_key(binding)
        local bindings = Tr.TreeCodeBindingState(map_with(self.bindings.values_by_key, key, Tr.TreeCodeBindingValueEntry(key, value)), self.bindings.locals_by_key)
        return Tr.TreeCodeStateResult(state_with(self, { bindings = bindings }))
    end

    function Tr.TreeCodeFuncState:tree_code_note_mutable(binding)
        local declared = self:tree_code_declare_fresh_binding_key(binding)
        local residence = Tr.TreeCodeResidenceFacts(declared.state.residence.addressed_by_key, map_with(declared.state.residence.mutable_by_key, declared.binding_name, Tr.TreeCodeBindingPresenceEntry(declared.binding_name)))
        return Tr.TreeCodeStateResult(state_with(declared.state, { residence = residence }))
    end

    function Tr.TreeCodeFuncState:tree_code_alpha_snapshot()
        return clone_map(self.alpha.renamed_by_key), self:tree_code_binding_alpha_suffix()
    end

    function Tr.TreeCodeFuncState:tree_code_use_alpha(alpha, suffix)
        local suffixes = self.alpha.current_suffix_by_slot
        if suffix == nil then
            suffixes = map_without(suffixes, "current")
        else
            suffixes = map_with(suffixes, "current", Tr.TreeCodeAlphaSuffixEntry("current", suffix))
        end
        local state = state_with(self, { alpha = Tr.TreeCodeAlphaState(clone_map(alpha), suffixes, self.alpha.seq) })
        return Tr.TreeCodeStateResult(state)
    end

    function Tr.TreeCodeFuncState:tree_code_fork_alpha(suffix)
        local alpha = setmetatable({}, { __index = self.alpha.renamed_by_key })
        local result = self:tree_code_use_alpha(alpha, suffix)
        return Tr.TreeCodeAlphaResult(result.state.alpha.renamed_by_key, result.state)
    end

    function Tr.TreeCodeFuncState:tree_code_enter_control_region(region)
        local depth = #(self.control.current_regions or {}) + 1
        local control = Tr.TreeCodeControlState(
            array_with(self.control.current_regions, depth, Tr.TreeCodeControlRegionSlot("control:" .. tostring(depth), region)),
            array_with(self.control.flags, depth, Tr.TreeCodeControlFlag("exit_seen:" .. tostring(depth), false))
        )
        return Tr.TreeCodeStateResult(state_with(self, { control = control }))
    end

    function Tr.TreeCodeFuncState:tree_code_leave_control_region(region)
        local depth = #(self.control.current_regions or {})
        local exit_flag = self.control.flags[depth]
        local saw_exit = exit_flag and exit_flag.enabled or false
        local control = Tr.TreeCodeControlState(array_with(self.control.current_regions, depth, nil), array_with(self.control.flags, depth, nil))
        return Tr.TreeCodeControlExitResult(saw_exit, state_with(self, { control = control }))
    end

    function Tr.TreeCodeFuncState:tree_code_current_control_region()
        local slot = self.control.current_regions[#(self.control.current_regions or {})]
        return slot and slot.region or nil
    end

    function Tr.TreeCodeFuncState:tree_code_note_control_exit()
        local depth = #(self.control.current_regions or {})
        if depth == 0 then return Tr.TreeCodeStateResult(self) end
        local control = Tr.TreeCodeControlState(self.control.current_regions, array_with(self.control.flags, depth, Tr.TreeCodeControlFlag("exit_seen:" .. tostring(depth), true)))
        return Tr.TreeCodeStateResult(state_with(self, { control = control }))
    end

    function Tr.TreeCodeFuncState:tree_code_control_target(label)
        local region = self:tree_code_current_control_region()
        if region == nil then return nil end
        local key = label_key(label)
        for _, entry in ipairs(region.targets or {}) do
            if entry.label_name == key then return entry.target end
        end
        return nil
    end

    function Tr.TreeCodeFuncState:tree_code_ensure_local(facts, binding, source_ty, residence)
        local declared = self:tree_code_declare_binding_key(binding)
        local state = declared.state
        local input = Tr.TreeCodeStmtInput(facts, state)
        local key = declared.binding_name
        local existing = state.bindings.locals_by_key[key]
        if existing ~= nil then return Tr.TreeCodeLocalResult(existing.binding.id, existing.binding.ty, state) end
        local cty = input:tree_code_type(source_ty or binding.ty)
        local id = input:tree_code_local_id_for_binding(binding)
        local local_ = Code.CodeLocal(id, binding.name, cty, residence or input:tree_code_residence_for(binding, source_ty or binding.ty), origin_binding(binding))
        local emission = Tr.TreeCodeEmissionState(array_append(state.emission.locals, local_), state.emission.blocks, state.emission.current_blocks)
        local bindings = Tr.TreeCodeBindingState(state.bindings.values_by_key, map_with(state.bindings.locals_by_key, key, Tr.TreeCodeLocalBindingEntry(key, Tr.TreeCodeLocalBinding(id, cty, source_ty or binding.ty))))
        return Tr.TreeCodeLocalResult(id, cty, state_with(state_with(state, { emission = emission }), { bindings = bindings }))
    end

    function Tr.TreeCodeExprInput:tree_code_with_state(state) return Tr.TreeCodeExprInput(self.facts, state) end
    function Tr.TreeCodePlaceInput:tree_code_with_state(state) return Tr.TreeCodePlaceInput(self.facts, state) end
    function Tr.TreeCodeStmtInput:tree_code_with_state(state) return Tr.TreeCodeStmtInput(self.facts, state) end
    function Tr.TreeCodeControlInput:tree_code_with_state(state) return Tr.TreeCodeControlInput(self.facts, state) end

    function Tr.TreeCodeInput:tree_code_with_result_state(result)
        return self:tree_code_with_state(result.state)
    end

    function Tr.TreeCodeInput:tree_code_expr_input()
        return Tr.TreeCodeExprInput(self:tree_code_func_facts(), self:tree_code_state())
    end

    function Tr.TreeCodeInput:tree_code_place_input()
        return Tr.TreeCodePlaceInput(self:tree_code_func_facts(), self:tree_code_state())
    end

    function Tr.TreeCodeInput:tree_code_new_value(prefix)
        local counter = self:tree_code_state():tree_code_next_counter("value")
        return Tr.TreeCodeValueIdResult(Code.CodeValueId("v:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "tmp") .. tostring(counter.value)), counter.state)
    end

    function Tr.TreeCodeInput:tree_code_new_inst(prefix)
        local counter = self:tree_code_state():tree_code_next_counter("inst")
        return Tr.TreeCodeInstIdResult(Code.CodeInstId("inst:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "i") .. tostring(counter.value)), counter.state)
    end

    function Tr.TreeCodeInput:tree_code_new_term(prefix)
        local counter = self:tree_code_state():tree_code_next_counter("term")
        return Tr.TreeCodeTermIdResult(Code.CodeTermId("term:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "t") .. tostring(counter.value)), counter.state)
    end

    function Tr.TreeCodeInput:tree_code_new_block(prefix)
        local counter = self:tree_code_state():tree_code_next_counter("block")
        return Tr.TreeCodeBlockIdResult(Code.CodeBlockId("block:" .. sanitize(self:tree_code_func_name()) .. ":" .. sanitize(prefix or "b") .. tostring(counter.value)), counter.state)
    end

    function Tr.TreeCodeInput:tree_code_append_inst(kind, origin)
        local block = self:tree_code_state():tree_code_current_block()
        if block == nil then unsupported(self, kind, "instruction after terminator") end
        local inst_id = self:tree_code_new_inst()
        local updated = Tr.TreeCodeBlockBuilder(block.id, block.name, block.params, array_append(block.insts, Code.CodeInst(inst_id.id, kind, origin or origin_generated("tree_to_code"))), block.origin)
        return inst_id.state:tree_code_set_current_block(updated)
    end

    function Tr.TreeCodeInput:tree_code_start_block(id, name, params, origin)
        if self:tree_code_state():tree_code_has_current_block() then unsupported(self, id, "starting block before terminating current block") end
        return self:tree_code_state():tree_code_set_current_block(Tr.TreeCodeBlockBuilder(id, name, params or {}, {}, origin or origin_generated("block " .. tostring(name or "block"))))
    end

    function Tr.TreeCodeInput:tree_code_terminate(kind, origin)
        if not self:tree_code_state():tree_code_has_current_block() then unsupported(self, kind, "terminator without current block") end
        local term_id = self:tree_code_new_term("term")
        local term = Code.CodeTerm(term_id.id, kind, origin or origin_generated("terminator"))
        local block = term_id.state:tree_code_current_block()
        local appended = term_id.state:tree_code_append_block(Code.CodeBlock(block.id, block.name, block.params, block.insts, term, block.origin))
        local cleared = appended.state:tree_code_clear_current_block()
        return Tr.TreeCodeTermResult(term, cleared.state)
    end

    function Tr.TreeCodeInput:tree_code_save_bindings()
        return self:tree_code_state():tree_code_save_bindings()
    end

    function Tr.TreeCodeInput:tree_code_restore_bindings(saved)
        return self:tree_code_state():tree_code_restore_bindings(saved)
    end

    local function default_int_semantics()
        return Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZeroOrOverflow, Code.CodeShiftTrapOutOfRange)
    end

    local function default_float_mode()
        return Code.CodeFloatStrict
    end

    function Tr.TreeCodeInput:tree_code_memory_access(mode, source_ty, code_type)
        return Code.CodeMemoryAccess(mode, code_type or self:tree_code_type(source_ty), self:tree_code_align_of(source_ty), Code.CodeMayTrap, false, nil)
    end

    function Tr.TreeCodeInput:tree_code_residence_for(binding, ty)
        if self:tree_code_binding_is_addressed(binding) then return Code.CodeResidenceAddressed end
        if self:tree_code_type(ty or binding.ty):tree_code_is_aggregate_type() then return Code.CodeResidenceAggregate end
        return Code.CodeResidenceValue
    end

    function Tr.TreeCodeInput:tree_code_ensure_local(binding, ty, residence)
        return self:tree_code_state():tree_code_ensure_local(self:tree_code_func_facts(), binding, ty, residence)
    end

    function Tr.TreeCodeInput:tree_code_lower_stmt_body(body)
        local input = Tr.TreeCodeStmtInput(self:tree_code_func_facts(), self:tree_code_state())
        for i = 1, #(body or {}) do
            if not input:tree_code_state():tree_code_has_current_block() then return input end
            local result = body[i]:lower_tree_stmt_to_code(input)
            input = Tr.TreeCodeStmtInput(input:tree_code_func_facts(), result.state)
        end
        return input
    end

    local collect_address_taken_expr, collect_address_taken_place, collect_address_taken_stmts

    collect_address_taken_place = function(place, out)
        place:tree_code_collect_address_taken_place(out)
    end

    collect_address_taken_expr = function(expr, out)
        if expr == nil then return end
        expr:tree_code_collect_address_taken_expr(out)
    end

    collect_address_taken_stmts = function(stmts, out)
        for i = 1, #(stmts or {}) do
            stmts[i]:tree_code_collect_address_taken_stmt(out)
        end
        return out
    end

    function Bind.ValueRef:tree_code_mark_addressed_binding(out) end
    function Bind.ValueRefBinding:tree_code_mark_addressed_binding(out)
        local key = self.binding:tree_code_binding_key()
        out.addressed[key] = Tr.TreeCodeBindingPresenceEntry(key)
    end

    function Tr.Place:tree_code_mark_addressed_place(out) end
    function Tr.PlaceRef:tree_code_mark_addressed_place(out) self.ref:tree_code_mark_addressed_binding(out) end
    function Tr.PlaceField:tree_code_mark_addressed_place(out) self.base:tree_code_mark_addressed_place(out) end
    function Tr.PlaceDot:tree_code_mark_addressed_place(out) self.base:tree_code_mark_addressed_place(out) end
    function Tr.PlaceIndex:tree_code_mark_addressed_place(out) self.base:tree_code_mark_addressed_index_base(out) end
    function Tr.IndexBase:tree_code_mark_addressed_index_base(out) end
    function Tr.IndexBasePlace:tree_code_mark_addressed_index_base(out) self.base:tree_code_mark_addressed_place(out) end

    function Tr.Place:tree_code_collect_address_taken_place(out) end
    function Tr.PlaceDeref:tree_code_collect_address_taken_place(out) collect_address_taken_expr(self.base, out) end
    function Tr.PlaceField:tree_code_collect_address_taken_place(out) collect_address_taken_place(self.base, out) end
    function Tr.PlaceDot:tree_code_collect_address_taken_place(out) collect_address_taken_place(self.base, out) end
    function Tr.PlaceIndex:tree_code_collect_address_taken_place(out)
        self.base:tree_code_collect_address_taken_index_base(out)
        collect_address_taken_expr(self.index, out)
    end
    function Tr.IndexBase:tree_code_collect_address_taken_index_base(out) end
    function Tr.IndexBaseExpr:tree_code_collect_address_taken_index_base(out) collect_address_taken_expr(self.base, out) end
    function Tr.IndexBasePlace:tree_code_collect_address_taken_index_base(out) collect_address_taken_place(self.base, out) end
    function Tr.IndexBaseView:tree_code_collect_address_taken_index_base(out) collect_address_taken_expr(self.view.base, out) end

    function Tr.Expr:tree_code_collect_address_taken_expr(out) end
    function Tr.ExprAddrOf:tree_code_collect_address_taken_expr(out)
        self.place:tree_code_mark_addressed_place(out)
        collect_address_taken_place(self.place, out)
    end
    function Tr.ExprUnary:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprDeref:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprLen:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprIsNull:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprBinary:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
    function Tr.ExprCompare:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
    function Tr.ExprLogic:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.lhs, out); collect_address_taken_expr(self.rhs, out) end
    function Tr.ExprCast:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprMachineCast:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.value, out) end
    function Tr.ExprLoad:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out) end
    function Tr.ExprAtomicLoad:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out) end
    function Tr.ExprAtomicRmw:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.value, out) end
    function Tr.ExprAtomicCas:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.expected, out); collect_address_taken_expr(self.replacement, out) end
    function Tr.ExprCall:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.callee, out)
        for i = 1, #(self.args or {}) do collect_address_taken_expr(self.args[i], out) end
    end
    function Tr.ExprField:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.base, out) end
    function Tr.ExprDot:tree_code_collect_address_taken_expr(out) collect_address_taken_expr(self.base, out) end
    function Tr.ExprIndex:tree_code_collect_address_taken_expr(out)
        self.base:tree_code_collect_address_taken_index_base(out)
        collect_address_taken_expr(self.index, out)
    end
    function Tr.ExprIntrinsic:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.args or {}) do collect_address_taken_expr(self.args[i], out) end
    end
    function Tr.ExprArray:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.elems or {}) do collect_address_taken_expr(self.elems[i], out) end
    end
    function Tr.ExprCtor:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.args or {}) do collect_address_taken_expr(self.args[i], out) end
    end
    function Tr.ExprAgg:tree_code_collect_address_taken_expr(out)
        for i = 1, #(self.fields or {}) do collect_address_taken_expr(self.fields[i].value, out) end
    end
    function Tr.ExprIf:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.cond, out); collect_address_taken_expr(self.then_expr, out); collect_address_taken_expr(self.else_expr, out)
    end
    function Tr.ExprSelect:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.cond, out); collect_address_taken_expr(self.then_expr, out); collect_address_taken_expr(self.else_expr, out)
    end
    function Tr.ExprSwitch:tree_code_collect_address_taken_expr(out)
        collect_address_taken_expr(self.value, out)
        for i = 1, #(self.arms or {}) do collect_address_taken_stmts(self.arms[i].body, out); collect_address_taken_expr(self.arms[i].result, out) end
        for i = 1, #(self.variant_arms or {}) do collect_address_taken_stmts(self.variant_arms[i].body, out); collect_address_taken_expr(self.variant_arms[i].result, out) end
        collect_address_taken_stmts(self.default_body or {}, out); collect_address_taken_expr(self.default_expr, out)
    end
    function Tr.ExprControl:tree_code_collect_address_taken_expr(out)
        collect_address_taken_stmts(self.region.entry.body, out)
        for i = 1, #(self.region.blocks or {}) do collect_address_taken_stmts(self.region.blocks[i].body, out) end
    end
    function Tr.ExprView:tree_code_collect_address_taken_expr(out) self.view:tree_code_collect_address_taken_view(out) end
    function Tr.ExprBlock:tree_code_collect_address_taken_expr(out)
        collect_address_taken_stmts(self.stmts or {}, out); collect_address_taken_expr(self.result, out)
    end

    function Tr.View:tree_code_collect_address_taken_view(out) end
    function Tr.ViewFromExpr:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.base, out) end
    function Tr.ViewContiguous:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out) end
    function Tr.ViewStrided:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out); collect_address_taken_expr(self.stride, out) end
    function Tr.ViewRestrided:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.stride, out) end
    function Tr.ViewWindow:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.start, out); collect_address_taken_expr(self.len, out) end
    function Tr.ViewRowBase:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.row_offset, out) end
    function Tr.ViewInterleaved:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.data, out); collect_address_taken_expr(self.len, out); collect_address_taken_expr(self.stride, out); collect_address_taken_expr(self.lane, out) end
    function Tr.ViewInterleavedView:tree_code_collect_address_taken_view(out) collect_address_taken_expr(self.stride, out); collect_address_taken_expr(self.lane, out) end

    function Tr.Stmt:tree_code_collect_address_taken_stmt(out) end
    function Tr.StmtLet:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.init, out) end
    function Tr.StmtVar:tree_code_collect_address_taken_stmt(out)
        local key = self.binding:tree_code_binding_key()
        out.mutable[key] = Tr.TreeCodeBindingPresenceEntry(key)
        collect_address_taken_expr(self.init, out)
    end
    function Tr.StmtSet:tree_code_collect_address_taken_stmt(out) collect_address_taken_place(self.place, out); collect_address_taken_expr(self.value, out) end
    function Tr.StmtAtomicStore:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.addr, out); collect_address_taken_expr(self.value, out) end
    function Tr.StmtExpr:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.expr, out) end
    function Tr.StmtAssert:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.cond, out) end
    function Tr.StmtYieldValue:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.value, out) end
    function Tr.StmtReturnValue:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.value, out) end
    function Tr.StmtIf:tree_code_collect_address_taken_stmt(out) collect_address_taken_expr(self.cond, out); collect_address_taken_stmts(self.then_body, out); collect_address_taken_stmts(self.else_body, out) end
    function Tr.StmtSwitch:tree_code_collect_address_taken_stmt(out)
        collect_address_taken_expr(self.value, out)
        for j = 1, #(self.arms or {}) do collect_address_taken_stmts(self.arms[j].body, out) end
        for j = 1, #(self.variant_arms or {}) do collect_address_taken_stmts(self.variant_arms[j].body, out) end
        collect_address_taken_stmts(self.default_body or {}, out)
    end
    function Tr.StmtJump:tree_code_collect_address_taken_stmt(out)
        for j = 1, #(self.args or {}) do collect_address_taken_expr(self.args[j].value, out) end
    end
    function Tr.StmtJumpCont:tree_code_collect_address_taken_stmt(out)
        for j = 1, #(self.args or {}) do collect_address_taken_expr(self.args[j].value, out) end
    end
    function Tr.StmtControl:tree_code_collect_address_taken_stmt(out)
        collect_address_taken_stmts(self.region.entry.body, out)
        for j = 1, #(self.region.blocks or {}) do collect_address_taken_stmts(self.region.blocks[j].body, out) end
    end

    function Bind.ValueRef:tree_code_lookup_binding(tree_code_input)
        unsupported(tree_code_input, self, "non-binding value reference " .. class_name(self))
    end
    function Bind.ValueRefBinding:tree_code_lookup_binding(tree_code_input)
        return self.binding, tree_code_input:tree_code_state():tree_code_scoped_binding_key(self.binding)
    end

    function Tr.TreeCodeInput:tree_code_load_place(place, source_ty, reason)
        local allocated = self:tree_code_new_value(reason or "load")
        local input = self:tree_code_with_result_state(allocated)
        local appended = input:tree_code_append_inst(Code.CodeInstLoad(allocated.value, place, input:tree_code_memory_access(Code.CodeMemoryRead, source_ty, input:tree_code_type(source_ty))), origin_generated(reason or "load"))
        input = input:tree_code_with_result_state(appended)
        return input:tree_code_expr_result(allocated.value, input:tree_code_type(source_ty))
    end

    function Tr.TreeCodeInput:tree_code_store_place(place, source_ty, value, origin)
        return self:tree_code_append_inst(Code.CodeInstStore(place, value, self:tree_code_memory_access(Code.CodeMemoryWrite, source_ty, self:tree_code_type(source_ty))), origin or origin_generated("store"))
    end

    function Tr.TreeCodeInput:tree_code_atomic_access(mode, source_ty, ordering)
        return Code.CodeMemoryAccess(mode, self:tree_code_type(source_ty), self:tree_code_align_of(source_ty), Code.CodeMayTrap, true, ordering)
    end

    function Tr.TreeCodeInput:tree_code_const_index(n, reason)
        local allocated = self:tree_code_new_value(reason or "index_const")
        local input = self:tree_code_with_result_state(allocated)
        local appended = input:tree_code_append_inst(Code.CodeInstConst(allocated.value, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(n)))), origin_generated(reason or "index const"))
        input = input:tree_code_with_result_state(appended)
        return input:tree_code_expr_result(allocated.value, Code.CodeTyIndex)
    end

    function Tr.TreeCodeInput:tree_code_as_index_value(value, value_ty, reason)
        if value_ty == Code.CodeTyIndex then return self:tree_code_expr_result(value, Code.CodeTyIndex) end
        local op = value_ty:tree_code_index_cast_op()
        if op == nil then unsupported(self, value_ty, "non-integer index value " .. class_name(value_ty)) end
        local allocated = self:tree_code_new_value(reason or "to_index")
        local input = self:tree_code_with_result_state(allocated)
        local appended = input:tree_code_append_inst(Code.CodeInstCast(allocated.value, op, value_ty, Code.CodeTyIndex, value), origin_generated(reason or "index cast"))
        input = input:tree_code_with_result_state(appended)
        return input:tree_code_expr_result(allocated.value, Code.CodeTyIndex)
    end

    function Tr.TreeCodeInput:tree_code_index_mul(lhs, rhs, reason)
        local allocated = self:tree_code_new_value(reason)
        local input = self:tree_code_with_result_state(allocated)
        local appended = input:tree_code_append_inst(Code.CodeInstBinary(allocated.value, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), lhs, rhs), origin_generated(reason))
        input = input:tree_code_with_result_state(appended)
        return input:tree_code_expr_result(allocated.value, Code.CodeTyIndex)
    end

    function Tr.TreeCodeInput:tree_code_data_offset(view, data, index, elem, reason)
        local ptr_ty = Code.CodeTyDataPtr(self:tree_code_type(elem))
        local allocated = self:tree_code_new_value(reason)
        local input = self:tree_code_with_result_state(allocated)
        local elem_size = self:tree_code_size_of(elem)
        if elem_size == nil then unsupported(self, view, "view element without known size") end
        local appended = input:tree_code_append_inst(Code.CodeInstPtrOffset(allocated.value, ptr_ty, data, index, elem_size, 0), origin_generated(reason))
        input = input:tree_code_with_result_state(appended)
        return input:tree_code_expr_result(allocated.value, ptr_ty)
    end

    function Code.CodeType:tree_code_index_cast_op() return nil end
    function Code.CodeTyInt:tree_code_index_cast_op()
        if self.bits < 64 then
            return self.signedness == Code.CodeSigned and Core.MachineCastSextend or Core.MachineCastUextend
        end
        return Core.MachineCastBitcast
    end
    function Code.CodeTyBool8:tree_code_index_cast_op() return Core.MachineCastUextend end

    function Tr.Expr:tree_code_lower_index_value(tree_code_input, reason)
        local result = self:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        local input = tree_code_input:tree_code_with_result_state(result)
        return input:tree_code_as_index_value(result.value, result.ty, reason)
    end

    function Tr.View:lower_tree_view_parts_to_code(tree_code_input)
        unsupported(tree_code_input, self, "view form " .. class_name(self))
    end
    function Tr.ViewContiguous:lower_tree_view_parts_to_code(tree_code_input)
        local data_result = self.data:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        local len_result = self.len:tree_code_lower_index_value(tree_code_input, "view_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(len_result)
        local len = len_result.value
        local stride_result = tree_code_input:tree_code_const_index(1, "view_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        local stride = stride_result.value
        return Tr.TreeCodeViewPartsResult(data, len, stride, tree_code_input:tree_code_state())
    end
    function Tr.ViewStrided:lower_tree_view_parts_to_code(tree_code_input)
        local data_result = self.data:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        local len_result = self.len:tree_code_lower_index_value(tree_code_input, "view_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(len_result)
        local len = len_result.value
        local stride_result = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        local stride = stride_result.value
        return Tr.TreeCodeViewPartsResult(data, len, stride, tree_code_input:tree_code_state())
    end
    function Tr.ViewFromExpr:lower_tree_view_parts_to_code(tree_code_input)
        return source_access_base(expr_type(self.base)):tree_code_lower_view_from_expr(tree_code_input, self)
    end
    function Ty.Type:tree_code_lower_view_from_expr(tree_code_input, view)
        unsupported(tree_code_input, view, "view-from expression type " .. class_name(self))
    end
    function Ty.TPtr:tree_code_lower_view_from_expr(tree_code_input, view)
        local data_result = view.base:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        local len_result = tree_code_input:tree_code_const_index(1, "view_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(len_result)
        local len = len_result.value
        local stride_result = tree_code_input:tree_code_const_index(1, "view_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        local stride = stride_result.value
        return Tr.TreeCodeViewPartsResult(data, len, stride, tree_code_input:tree_code_state())
    end
    function Ty.TView:tree_code_lower_view_from_expr(tree_code_input, view)
        local base_result = view.base:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        local base = base_result.value
        local data_result = tree_code_input:tree_code_new_value("view_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        local len_result = tree_code_input:tree_code_new_value("view_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(len_result)
        local len = len_result.value
        local stride_result = tree_code_input:tree_code_new_value("view_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        local stride = stride_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewData(data, base), origin_generated("view data")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewLen(len, base), origin_generated("view len")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewStride(stride, base), origin_generated("view stride")))
        return Tr.TreeCodeViewPartsResult(data, len, stride, tree_code_input:tree_code_state())
    end
    function Tr.ViewRestrided:lower_tree_view_parts_to_code(tree_code_input)
        local base_result = self.base:lower_tree_view_parts_to_code(tree_code_input)
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        local stride_result = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        return Tr.TreeCodeViewPartsResult(base_result.data, base_result.len, stride_result.value, tree_code_input:tree_code_state())
    end
    function Tr.ViewWindow:lower_tree_view_parts_to_code(tree_code_input)
        local base_result = self.base:lower_tree_view_parts_to_code(tree_code_input)
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        local start_result = self.start:tree_code_lower_index_value(tree_code_input, "view_window_start")
        tree_code_input = tree_code_input:tree_code_with_result_state(start_result)
        local scaled_result = tree_code_input:tree_code_index_mul(start_result.value, base_result.stride, "view_window_start")
        tree_code_input = tree_code_input:tree_code_with_result_state(scaled_result)
        local data_result = tree_code_input:tree_code_data_offset(self, base_result.data, scaled_result.value, self.elem, "view_window_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local len_result = self.len:tree_code_lower_index_value(tree_code_input, "view_window_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(len_result)
        return Tr.TreeCodeViewPartsResult(data_result.value, len_result.value, base_result.stride, tree_code_input:tree_code_state())
    end
    function Tr.ViewRowBase:lower_tree_view_parts_to_code(tree_code_input)
        local base_result = self.base:lower_tree_view_parts_to_code(tree_code_input)
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        local row_result = self.row_offset:tree_code_lower_index_value(tree_code_input, "view_row_base")
        tree_code_input = tree_code_input:tree_code_with_result_state(row_result)
        local scaled_result = tree_code_input:tree_code_index_mul(row_result.value, base_result.stride, "view_row_base_offset")
        tree_code_input = tree_code_input:tree_code_with_result_state(scaled_result)
        local data_result = tree_code_input:tree_code_data_offset(self, base_result.data, scaled_result.value, self.elem, "view_row_base_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        return Tr.TreeCodeViewPartsResult(data_result.value, base_result.len, base_result.stride, tree_code_input:tree_code_state())
    end
    function Tr.ViewInterleaved:lower_tree_view_parts_to_code(tree_code_input)
        local data_result = self.data:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        local len_result = self.len:tree_code_lower_index_value(tree_code_input, "view_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(len_result)
        local stride_result = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        local lane_result = self.lane:tree_code_lower_index_value(tree_code_input, "view_lane")
        tree_code_input = tree_code_input:tree_code_with_result_state(lane_result)
        local interleaved_data = tree_code_input:tree_code_data_offset(self, data, lane_result.value, self.elem, "view_interleaved_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(interleaved_data)
        return Tr.TreeCodeViewPartsResult(interleaved_data.value, len_result.value, stride_result.value, tree_code_input:tree_code_state())
    end
    function Tr.ViewInterleavedView:lower_tree_view_parts_to_code(tree_code_input)
        local base_result = self.base:lower_tree_view_parts_to_code(tree_code_input)
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        local stride_factor = self.stride:tree_code_lower_index_value(tree_code_input, "view_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_factor)
        local lane = self.lane:tree_code_lower_index_value(tree_code_input, "view_lane")
        tree_code_input = tree_code_input:tree_code_with_result_state(lane)
        local lane_offset = tree_code_input:tree_code_index_mul(lane.value, base_result.stride, "view_interleaved_lane")
        tree_code_input = tree_code_input:tree_code_with_result_state(lane_offset)
        local stride = tree_code_input:tree_code_index_mul(base_result.stride, stride_factor.value, "view_interleaved_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride)
        local data = tree_code_input:tree_code_data_offset(self, base_result.data, lane_offset.value, self.elem, "view_interleaved_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data)
        return Tr.TreeCodeViewPartsResult(data.value, base_result.len, stride.value, tree_code_input:tree_code_state())
    end

    function Bind.BindingRole:tree_code_lookup_value(tree_code_input, binding, ref)
        unsupported(tree_code_input, ref, "unbound scalar reference `" .. tostring(binding.name) .. "`")
    end
    function Bind.BindingRoleGlobalFunc:tree_code_lookup_value(tree_code_input, binding, ref)
        local ptr_ty = tree_code_input:tree_code_type(binding.ty)
        local dst_result = tree_code_input:tree_code_new_value("fnref")
        tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
        local dst = dst_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefFunc(code_func_id(self.item_name)), ptr_ty), origin_binding(binding)))
        return tree_code_input:tree_code_expr_result(dst, ptr_ty)
    end
    function Bind.BindingRoleExtern:tree_code_lookup_value(tree_code_input, binding, ref)
        local ptr_ty = tree_code_input:tree_code_type(binding.ty)
        local dst_result = tree_code_input:tree_code_new_value("externref")
        tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
        local dst = dst_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstGlobalRef(dst, Code.CodeGlobalRefExtern(code_extern_id(binding.name)), ptr_ty), origin_binding(binding)))
        return tree_code_input:tree_code_expr_result(dst, ptr_ty)
    end
    function Bind.BindingRoleGlobalConst:tree_code_lookup_value(tree_code_input, binding, ref)
        local gid = code_global_id(self.module_name, self.item_name)
        return tree_code_input:tree_code_load_place(Code.CodePlaceGlobal(gid, tree_code_input:tree_code_type(binding.ty)), binding.ty, "load_global_" .. binding.name)
    end
    function Bind.BindingRoleGlobalStatic:tree_code_lookup_value(tree_code_input, binding, ref)
        local gid = code_global_id(self.module_name, self.item_name)
        return tree_code_input:tree_code_load_place(Code.CodePlaceGlobal(gid, tree_code_input:tree_code_type(binding.ty)), binding.ty, "load_global_" .. binding.name)
    end

    function Ty.Type:tree_code_call_sig_id(tree_code_input)
        unsupported(tree_code_input, self, "non-callable type " .. class_name(self))
    end
    function Ty.TFunc:tree_code_call_sig_id(tree_code_input)
        return CodeType.ensure_type_sig(tree_code_input:tree_code_module_sigs(), self.params, self.result)
    end
    function Ty.TClosure:tree_code_call_sig_id(tree_code_input)
        return CodeType.ensure_type_sig(tree_code_input:tree_code_module_sigs(), self.params, self.result)
    end

    function Tr.Expr:tree_code_direct_call_target() return nil end
    function Tr.ExprRef:tree_code_direct_call_target()
        return self.ref:tree_code_direct_call_target()
    end
    function Bind.ValueRef:tree_code_direct_call_target() return nil end
    function Bind.ValueRefBinding:tree_code_direct_call_target()
        return self.binding.role:tree_code_direct_call_target(self.binding)
    end
    function Bind.BindingRole:tree_code_direct_call_target(binding) return nil end
    function Bind.BindingRoleGlobalFunc:tree_code_direct_call_target(binding)
        return Code.CodeCallDirect(code_func_id(self.item_name))
    end
    function Bind.BindingRoleExtern:tree_code_direct_call_target(binding)
        return Code.CodeCallExtern(code_extern_id(binding.name))
    end
    function Ty.Type:tree_code_indirect_call_target(callee, sig)
        return Code.CodeCallIndirect(callee, sig)
    end
    function Ty.TClosure:tree_code_indirect_call_target(callee, sig)
        return Code.CodeCallClosure(callee, sig)
    end

    function Ty.Type:tree_code_lower_field_base_place(tree_code_input, base)
        return base:tree_code_as_place(tree_code_input), self
    end
    function Ty.TPtr:tree_code_lower_field_base_place(tree_code_input, base)
        local addr_result = base:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
        local addr = addr_result.value
        return Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.elem), tree_code_input:tree_code_align_of(self.elem)), self.elem
    end
    function Sem.FieldRef:tree_code_require_lowered_field(tree_code_input)
        unsupported(tree_code_input, self, "field access before sem_layout_resolve")
    end
    function Sem.FieldByOffset:tree_code_require_lowered_field(tree_code_input) end

    function Tr.IndexBase:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        unsupported(tree_code_input, self, "index base " .. class_name(self))
    end
    function Tr.IndexBaseExpr:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        return source_access_base(expr_type(self.base)):tree_code_lower_expr_index_base(tree_code_input, self.base, idx, elem_ty)
    end
    function Tr.IndexBasePlace:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        return source_access_base(place_type(self.base)):tree_code_lower_place_index_base(tree_code_input, self.base, idx, elem_ty)
    end
    function Tr.IndexBaseView:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        local view_parts = self.view:lower_tree_view_parts_to_code(tree_code_input)
        tree_code_input = tree_code_input:tree_code_with_result_state(view_parts)
        local scaled_result = tree_code_input:tree_code_new_value("view_index_scaled")
        tree_code_input = tree_code_input:tree_code_with_result_state(scaled_result)
        local scaled = scaled_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, view_parts.stride), origin_generated("view index scale")))
        return Tr.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(view_parts.data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), scaled, tree_code_input:tree_code_state())
    end

    function Ty.Type:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        if tree_code_input:tree_code_type(self):tree_code_is_aggregate_type() then return Tr.TreeCodeIndexPlaceResult(base:tree_code_as_place(tree_code_input), idx, tree_code_input:tree_code_state()) end
        unsupported(tree_code_input, base, "index expression base type " .. class_name(self))
    end
    function Ty.TPtr:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        local addr_result = base:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
        return Tr.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(addr_result.value, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), idx, tree_code_input:tree_code_state())
    end
    function Ty.TView:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        local view_result = base:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(view_result)
        local view = view_result.value
        local data_result = tree_code_input:tree_code_new_value("view_index_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        local stride_result = tree_code_input:tree_code_new_value("view_index_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        local stride = stride_result.value
        local scaled_result = tree_code_input:tree_code_new_value("view_index_scaled")
        tree_code_input = tree_code_input:tree_code_with_result_state(scaled_result)
        local scaled = scaled_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewData(data, view), origin_generated("view index data")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewStride(stride, view), origin_generated("view index stride")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale")))
        return Tr.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), scaled, tree_code_input:tree_code_state())
    end
    function Ty.TSlice:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        local slice_result = base:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(slice_result)
        local slice = slice_result.value
        local data_result = tree_code_input:tree_code_new_value("slice_index_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstSliceData(data, slice), origin_generated("slice index data")))
        return Tr.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), idx, tree_code_input:tree_code_state())
    end
    function Ty.TArray:tree_code_lower_expr_index_base(tree_code_input, base, idx, elem_ty)
        return Tr.TreeCodeIndexPlaceResult(base:tree_code_as_place(tree_code_input), idx, tree_code_input:tree_code_state())
    end

    function Ty.Type:tree_code_lower_place_index_base(tree_code_input, base, idx, elem_ty)
        local base_result = base:lower_tree_place_to_code(tree_code_input:tree_code_place_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        return Tr.TreeCodeIndexPlaceResult(base_result.place, idx, tree_code_input:tree_code_state())
    end
    function Ty.TView:tree_code_lower_place_index_base(tree_code_input, base, idx, elem_ty)
        local base_result = base:lower_tree_place_to_code(tree_code_input:tree_code_place_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        local view_result = tree_code_input:tree_code_load_place(base_result.place, self, "view_index")
        tree_code_input = tree_code_input:tree_code_with_result_state(view_result)
        local view = view_result.value
        local data_result = tree_code_input:tree_code_new_value("view_index_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        local stride_result = tree_code_input:tree_code_new_value("view_index_stride")
        tree_code_input = tree_code_input:tree_code_with_result_state(stride_result)
        local stride = stride_result.value
        local scaled_result = tree_code_input:tree_code_new_value("view_index_scaled")
        tree_code_input = tree_code_input:tree_code_with_result_state(scaled_result)
        local scaled = scaled_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewData(data, view), origin_generated("view index data")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewStride(stride, view), origin_generated("view index stride")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstBinary(scaled, Core.BinMul, Code.CodeTyIndex, default_int_semantics(), idx, stride), origin_generated("view index scale")))
        return Tr.TreeCodeIndexPlaceResult(Code.CodePlaceDeref(data, tree_code_input:tree_code_type(elem_ty), tree_code_input:tree_code_align_of(elem_ty)), scaled, tree_code_input:tree_code_state())
    end

    function Bind.BindingRole:tree_code_global_place(tree_code_input, binding) return nil end
    function Bind.BindingRoleGlobalConst:tree_code_global_place(tree_code_input, binding)
        return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), tree_code_input:tree_code_type(binding.ty))
    end
    function Bind.BindingRoleGlobalStatic:tree_code_global_place(tree_code_input, binding)
        return Code.CodePlaceGlobal(code_global_id(self.module_name, self.item_name), tree_code_input:tree_code_type(binding.ty))
    end

    function Ty.Type:tree_code_lower_place_field_base(tree_code_input, base)
        return base:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place
    end
    function Ty.TPtr:tree_code_lower_place_field_base(tree_code_input, base)
        local ref = base:tree_code_ref_for_ptr_field()
        if ref == nil then return base:lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place end
        local addr_result = Tr.ExprRef(Tr.ExprTyped(self), ref):lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
        local addr = addr_result.value
        return Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.elem), tree_code_input:tree_code_align_of(self.elem))
    end
    function Tr.Place:tree_code_ref_for_ptr_field() return nil end
    function Tr.PlaceRef:tree_code_ref_for_ptr_field() return self.ref end

    function Tr.Expr:tree_code_as_place(tree_code_input)
        unsupported(tree_code_input, self, "expression is not addressable " .. class_name(self))
    end
    function Tr.ExprRef:tree_code_as_place(tree_code_input)
        return Tr.PlaceRef(Tr.PlaceTyped(expr_type(self)), self.ref):lower_tree_place_to_code(Tr.TreeCodePlaceInput(tree_code_input:tree_code_func_facts(), tree_code_input:tree_code_state())).place
    end
    function Tr.ExprDeref:tree_code_as_place(tree_code_input)
        local value_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
        local value = value_result.value
        return Code.CodePlaceDeref(value, tree_code_input:tree_code_type(expr_type(self)), tree_code_input:tree_code_align_of(expr_type(self)))
    end
    function Tr.ExprField:tree_code_as_place(tree_code_input)
        self.field:tree_code_require_lowered_field(tree_code_input)
        local base_ty = source_access_base(expr_type(self.base))
        local base_place = base_ty:tree_code_lower_field_base_place(tree_code_input, self.base)
        local field_layout = tree_code_input:tree_code_layout_of(self.field.ty)
        return Code.CodePlaceField(base_place, self.field, tree_code_input:tree_code_type(self.field.ty), self.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil)
    end
    function Tr.ExprIndex:tree_code_as_place(tree_code_input)
        return self.base:tree_code_lower_place(tree_code_input, self.index, expr_type(self)).place
    end

    function Core.Literal:lower_tree_literal_to_code(tree_code_input, source_ty)
        local ty = tree_code_input:tree_code_type(source_ty)
        local dst_result = tree_code_input:tree_code_new_value("lit")
        tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
        local dst = dst_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstConst(dst, Code.CodeConstLiteral(ty, self)), origin_generated("literal")))
        return tree_code_input:tree_code_expr_result(dst, ty)
    end
    function Core.LitString:lower_tree_literal_to_code(tree_code_input, source_ty)
        local ty = tree_code_input:tree_code_type(source_ty)
        local elem_ty = u8_code_ty()
        local data_id, len_bytes = tree_code_input:tree_code_fresh_string_data(self.bytes)
        local data_result = tree_code_input:tree_code_new_value("str_data")
        tree_code_input = tree_code_input:tree_code_with_result_state(data_result)
        local data = data_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstGlobalRef(data, Code.CodeGlobalRefData(data_id), Code.CodeTyDataPtr(elem_ty)), origin_generated("string literal data ref")))
        local len_result = tree_code_input:tree_code_new_value("str_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(len_result)
        local len = len_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstConst(len, Code.CodeConstLiteral(Code.CodeTyIndex, Core.LitInt(tostring(len_bytes)))), origin_generated("string literal length")))
        local dst_result = tree_code_input:tree_code_new_value("str")
        tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
        local dst = dst_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstSliceMake(dst, elem_ty, data, len), origin_generated("string literal slice")))
        return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Ty.Type:tree_code_is_ptr_type() return false end
    function Ty.TPtr:tree_code_is_ptr_type() return true end

    function Ty.Type:lower_tree_len_to_code(tree_code_input, expr)
        unsupported(tree_code_input, expr, "len of non-array/view")
    end
    function Ty.TArray:lower_tree_len_to_code(tree_code_input, expr)
        return self.count:lower_tree_array_len_to_code(tree_code_input, expr)
    end
    function Ty.ArrayLen:lower_tree_array_len_to_code(tree_code_input, expr)
        unsupported(tree_code_input, expr, "len of non-constant array")
    end
    function Ty.ArrayLenConst:lower_tree_array_len_to_code(tree_code_input, expr)
        local result = tree_code_input:tree_code_const_index(self.count, "array_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(result)
        return tree_code_input:tree_code_expr_result(result.value, Code.CodeTyIndex)
    end
    function Ty.TView:lower_tree_len_to_code(tree_code_input, expr)
        local view_result = expr.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(view_result)
        local view = view_result.value
        local dst_result = tree_code_input:tree_code_new_value("view_len")
        tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
        local dst = dst_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewLen(dst, view), origin_generated("view len")))
        return tree_code_input:tree_code_expr_result(dst, Code.CodeTyIndex)
    end

    function Bind.ValueRef:tree_code_lookup_value(tree_code_input)
        unsupported(tree_code_input, self, "non-binding value reference " .. class_name(self))
    end

    function Bind.ValueRefBinding:tree_code_lookup_value(tree_code_input)
        local binding, key = self:tree_code_lookup_binding(tree_code_input)
        local local_info = tree_code_input:tree_code_state().bindings.locals_by_key[key]
        if local_info ~= nil then
            return tree_code_input:tree_code_load_place(Code.CodePlaceLocal(local_info.binding.id, local_info.binding.ty), binding.ty, "load_" .. binding.name)
        end
        local value_entry = tree_code_input:tree_code_state().bindings.values_by_key[key]
        if value_entry ~= nil then return tree_code_input:tree_code_expr_result(value_entry.value, tree_code_input:tree_code_type(binding.ty)) end
        return binding.role:tree_code_lookup_value(tree_code_input, binding, self)
    end

    function Tr.IndexBase:tree_code_lower_place(tree_code_input, index, elem_ty)
        local index_result = index:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(index_result)
        local idx, idx_ty = index_result.value, index_result.ty
        local idx_result = tree_code_input:tree_code_as_index_value(idx, idx_ty, "index")
        tree_code_input = tree_code_input:tree_code_with_result_state(idx_result)
        idx = idx_result.value
        local elem_size = tree_code_input:tree_code_size_of(elem_ty)
        if elem_size == nil then unsupported(tree_code_input, self, "index element without known size") end
        local base_result = self:tree_code_lower_index_base_place(tree_code_input, idx, elem_ty)
        tree_code_input = tree_code_input:tree_code_with_result_state(base_result)
        return tree_code_input:tree_code_place_result(Code.CodePlaceIndex(base_result.place, base_result.index, tree_code_input:tree_code_type(elem_ty), elem_size))
    end

    function Tr.PlaceRef:lower_tree_place_to_code(input)
        local tree_code_input = input
        local binding, key = self.ref:tree_code_lookup_binding(tree_code_input)
        local global_place = binding.role:tree_code_global_place(tree_code_input, binding)
        if global_place ~= nil then return tree_code_input:tree_code_place_result(global_place) end
        local local_info = tree_code_input:tree_code_state().bindings.locals_by_key[key]
        if local_info == nil then
            if tree_code_input:tree_code_state().residence.addressed_by_key[key] or tree_code_input:tree_code_state().residence.mutable_by_key[key] or tree_code_input:tree_code_type(binding.ty):tree_code_is_aggregate_type() then
                tree_code_input:tree_code_ensure_local(binding, binding.ty)
                local_info = tree_code_input:tree_code_state().bindings.locals_by_key[key]
            else
                unsupported(tree_code_input, self, "address/store of value-resident binding `" .. tostring(binding.name) .. "`")
            end
        end
        return tree_code_input:tree_code_place_result(Code.CodePlaceLocal(local_info.binding.id, local_info.binding.ty))
    end

    function Tr.PlaceDeref:lower_tree_place_to_code(input)
        local tree_code_input = input
        local addr_result = self.base:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
        local addr = addr_result.value
        local ty = place_type(self)
        return tree_code_input:tree_code_place_result(Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty)))
    end

    function Tr.PlaceField:lower_tree_place_to_code(input)
        local tree_code_input = input
        self.field:tree_code_require_lowered_field(tree_code_input)
        local base_ty = source_access_base(place_type(self.base))
        local base_place = base_ty:tree_code_lower_place_field_base(tree_code_input, self.base)
        local field_layout = tree_code_input:tree_code_layout_of(self.field.ty)
        return tree_code_input:tree_code_place_result(Code.CodePlaceField(base_place, self.field, tree_code_input:tree_code_type(self.field.ty), self.field.offset, field_layout and field_layout.size or nil, field_layout and field_layout.align or nil))
    end

    function Tr.PlaceIndex:lower_tree_place_to_code(input)
        local tree_code_input = input
        return self.base:tree_code_lower_place(tree_code_input, self.index, place_type(self))
    end

    function Tr.PlaceDot:lower_tree_place_to_code(input)
        unsupported(input, self, "dot place before sem_layout_resolve")
    end

    function Tr.ExprLit:lower_tree_expr_to_code(input)
        local tree_code_input = input
        return self.value:lower_tree_literal_to_code(tree_code_input, expr_type(self))
    end

    function Tr.ExprRef:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local result = self.ref:tree_code_lookup_value(tree_code_input)
        tree_code_input = tree_code_input:tree_code_with_result_state(result)
        return tree_code_input:tree_code_expr_result(result.value, result.ty)
    end

    function Tr.ExprUnary:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local value_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
            local value = value_result.value
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst_result = tree_code_input:tree_code_new_value("unary")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstUnary(dst, self.op, ty, value), origin_generated("unary")))
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.ExprBinary:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local lhs_result = self.lhs:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(lhs_result)
            local rhs_result = self.rhs:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(rhs_result)
            local lhs, lhs_ty = lhs_result.value, lhs_result.ty
            local rhs, rhs_ty = rhs_result.value, rhs_result.ty
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst_result = tree_code_input:tree_code_new_value("bin")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            local lhs_src_ty = source_access_base(expr_type(self.lhs))
            local rhs_src_ty = source_access_base(expr_type(self.rhs))
            local lhs_is_ptr = lhs_src_ty:tree_code_is_ptr_type()
            local rhs_is_ptr = rhs_src_ty:tree_code_is_ptr_type()
            if self.op == Core.BinAdd and (lhs_is_ptr or rhs_is_ptr) then
                local ptr_value, index_value, index_ty, elem_ty
                if lhs_is_ptr then
                    ptr_value, index_value, index_ty, elem_ty = lhs, rhs, rhs_ty, lhs_src_ty.elem
                else
                    ptr_value, index_value, index_ty, elem_ty = rhs, lhs, lhs_ty, rhs_src_ty.elem
                end
                local index_result = tree_code_input:tree_code_as_index_value(index_value, index_ty, "ptr_add_index")
                tree_code_input = tree_code_input:tree_code_with_result_state(index_result)
                local index = index_result.value
                local elem_size = tree_code_input:tree_code_size_of(elem_ty)
                if elem_size == nil then unsupported(tree_code_input, self, "pointer arithmetic element without known size") end
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstPtrOffset(dst, ty, ptr_value, index, elem_size, 0), origin_generated("pointer add")))
            elseif self.op == Core.BinSub and lhs_is_ptr and not rhs_is_ptr then
                local index_result = tree_code_input:tree_code_as_index_value(rhs, rhs_ty, "ptr_sub_index")
                tree_code_input = tree_code_input:tree_code_with_result_state(index_result)
                local index = index_result.value
                local zero_result = tree_code_input:tree_code_const_index(0, "ptr_sub_zero")
                tree_code_input = tree_code_input:tree_code_with_result_state(zero_result)
                local zero = zero_result.value
                local neg_result = tree_code_input:tree_code_new_value("ptr_sub_neg")
                tree_code_input = tree_code_input:tree_code_with_result_state(neg_result)
                local neg = neg_result.value
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstBinary(neg, Core.BinSub, Code.CodeTyIndex, default_int_semantics(), zero, index), origin_generated("pointer subtract index")))
                local elem_size = tree_code_input:tree_code_size_of(lhs_src_ty.elem)
                if elem_size == nil then unsupported(tree_code_input, self, "pointer arithmetic element without known size") end
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstPtrOffset(dst, ty, lhs, neg, elem_size, 0), origin_generated("pointer subtract")))
            else
                if ty:tree_code_is_float_type() then
                    tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstFloatBinary(dst, self.op, ty, default_float_mode(), lhs, rhs), origin_generated("float binary")))
                else
                    tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstBinary(dst, self.op, ty, default_int_semantics(), lhs, rhs), origin_generated("binary")))
                end
            end
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.ExprCompare:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local lhs_result = self.lhs:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(lhs_result)
            local lhs = lhs_result.value
            local rhs_result = self.rhs:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(rhs_result)
            local rhs = rhs_result.value
            local operand_ty = tree_code_input:tree_code_type(expr_type(self.lhs))
            local dst_result = tree_code_input:tree_code_new_value("cmp")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstCompare(dst, self.op, operand_ty, lhs, rhs), origin_generated("compare")))
            return tree_code_input:tree_code_expr_result(dst, Code.CodeTyBool8)
    end

    function Tr.ExprControl:lower_tree_expr_to_code(input)
        local tree_code_input = input
        return self.region:tree_code_lower_expr_control_to_code(tree_code_input)
    end

    function Tr.ExprBlock:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local saved = tree_code_input:tree_code_save_bindings()
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(self.stmts or {})
            if not tree_code_input:tree_code_state():tree_code_has_current_block() then unsupported(tree_code_input, self, "expression block body terminated before result") end
            local result = self.result:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(result)
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
            return tree_code_input:tree_code_expr_result(result.value, result.ty)
    end

    function Tr.ExprMachineCast:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(result)
            local value, from = result.value, result.ty
            local to = tree_code_input:tree_code_type(self.ty or expr_type(self))
            local dst_result = tree_code_input:tree_code_new_value("cast")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstCast(dst, self.op, from, to, value), origin_generated("cast")))
            return tree_code_input:tree_code_expr_result(dst, to)
    end

    function Tr.ExprCast:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(result)
        local value, from = result.value, result.ty
        local to = tree_code_input:tree_code_type(self.ty or expr_type(self))
        local dst_result = tree_code_input:tree_code_new_value("cast")
        tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
        local dst = dst_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstCast(dst, Core.MachineCastIdentity, from, to, value), origin_generated("surface identity cast")))
        return tree_code_input:tree_code_expr_result(dst, to)
    end

    function Tr.ExprSelect:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local cond_result = self.cond:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(cond_result)
            local cond = cond_result.value
            local then_value_result = self.then_expr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(then_value_result)
            local then_value = then_value_result.value
            local else_value_result = self.else_expr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(else_value_result)
            local else_value = else_value_result.value
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst_result = tree_code_input:tree_code_new_value("select")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstSelect(dst, ty, cond, then_value, else_value), origin_generated("select")))
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.ExprAddrOf:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local place_result = self.place:lower_tree_place_to_code(tree_code_input:tree_code_place_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(place_result)
            local place = place_result.place
            local ptr_ty = tree_code_input:tree_code_type(expr_type(self))
            local dst_result = tree_code_input:tree_code_new_value("addr")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstAddrOf(dst, ptr_ty, place), origin_generated("address of")))
            return tree_code_input:tree_code_expr_result(dst, ptr_ty)
    end

    function Tr.ExprIntrinsic:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local args = {}
            for i = 1, #(self.args or {}) do
                local arg_result = self.args[i]:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
                tree_code_input = tree_code_input:tree_code_with_result_state(arg_result)
                args[i] = arg_result.value
            end
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst = nil
            if ty ~= Code.CodeTyVoid then
                local dst_result = tree_code_input:tree_code_new_value("intrin")
                tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
                dst = dst_result.value
            end
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstIntrinsic(dst, self.op, ty, args), origin_generated("intrinsic")))
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.ExprAgg:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = tree_code_input:tree_code_type(self.ty or expr_type(self))
            local fields = {}
            for i = 1, #(self.fields or {}) do
                local fi = self.fields[i]
                local value_result = fi.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
                tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
                local value = value_result.value
                fields[#fields + 1] = Code.CodeFieldValue(Sem.FieldByOffset(fi.name, fi.offset or 0, expr_type(fi.value), Host.HostRepOpaque("tree_to_code.aggregate")), value)
            end
            local dst_result = tree_code_input:tree_code_new_value("agg")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstAggregate(dst, ty, fields), origin_generated("aggregate")))
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.ExprArray:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local elems = {}
            for i = 1, #(self.elems or {}) do
                local elem_result = self.elems[i]:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
                tree_code_input = tree_code_input:tree_code_with_result_state(elem_result)
                elems[#elems + 1] = Code.CodeArrayValue(i - 1, elem_result.value)
            end
            local dst_result = tree_code_input:tree_code_new_value("array")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstArray(dst, ty, elems), origin_generated("array")))
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.ExprView:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local view_parts = self.view:lower_tree_view_parts_to_code(tree_code_input)
            tree_code_input = tree_code_input:tree_code_with_result_state(view_parts)
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst_result = tree_code_input:tree_code_new_value("view")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstViewMake(dst, ty.elem, view_parts.data, view_parts.len, view_parts.stride), origin_generated("view")))
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.ExprLen:lower_tree_expr_to_code(input)
        local tree_code_input = input
        return source_access_base(expr_type(self.value)):lower_tree_len_to_code(tree_code_input, self)
    end

    function Tr.ExprSizeOf:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local n = tree_code_input:tree_code_size_of(self.ty)
            if n == nil then unsupported(tree_code_input, self, "sizeof type without known layout") end
            local result = tree_code_input:tree_code_const_index(n, "sizeof")
            tree_code_input = tree_code_input:tree_code_with_result_state(result)
            return tree_code_input:tree_code_expr_result(result.value, Code.CodeTyIndex)
    end

    function Tr.ExprAlignOf:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local result = tree_code_input:tree_code_const_index(tree_code_input:tree_code_align_of(self.ty), "alignof")
        tree_code_input = tree_code_input:tree_code_with_result_state(result)
        return tree_code_input:tree_code_expr_result(result.value, Code.CodeTyIndex)
    end

    function Tr.ExprIsNull:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(result)
            local value, ty = result.value, result.ty
            local null_value_result = tree_code_input:tree_code_new_value("null_cmp")
            tree_code_input = tree_code_input:tree_code_with_result_state(null_value_result)
            local null_value = null_value_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstConst(null_value, Code.CodeConstNull(ty)), origin_generated("null compare literal")))
            local dst_result = tree_code_input:tree_code_new_value("is_null")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstCompare(dst, Core.CmpEq, ty, value, null_value), origin_generated("is null")))
            return tree_code_input:tree_code_expr_result(dst, Code.CodeTyBool8)
    end

    function Tr.ExprCall:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local fn_ty = expr_type(self.callee)
        local sig = fn_ty:tree_code_call_sig_id(tree_code_input)
        local args = {}
        for i = 1, #(self.args or {}) do
            local arg_result = self.args[i]:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(arg_result)
            args[i] = arg_result.value
        end
        local target = self.callee:tree_code_direct_call_target()
        if target == nil then
            local callee_result = self.callee:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(callee_result)
            local callee = callee_result.value
            target = fn_ty:tree_code_indirect_call_target(callee, sig)
        end
        local result_ty = tree_code_input:tree_code_type(expr_type(self))
        local dst = nil
        if result_ty ~= Code.CodeTyVoid then
            local dst_result = tree_code_input:tree_code_new_value("call")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            dst = dst_result.value
        end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstCall(dst, target, sig, args), origin_generated("call")))
        return tree_code_input:tree_code_expr_result(dst, result_ty)
    end

    function Tr.ExprDeref:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local addr_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
            local addr = addr_result.value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(expr_type(self)), tree_code_input:tree_code_align_of(expr_type(self)))
            local load = tree_code_input:tree_code_load_place(place, expr_type(self), "deref")
            tree_code_input = tree_code_input:tree_code_with_result_state(load)
            return tree_code_input:tree_code_expr_result(load.value, load.ty)
    end

    function Tr.ExprField:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local load = tree_code_input:tree_code_load_place(self:tree_code_as_place(tree_code_input), expr_type(self), "field")
        tree_code_input = tree_code_input:tree_code_with_result_state(load)
        return tree_code_input:tree_code_expr_result(load.value, load.ty)
    end

    function Tr.ExprIndex:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local place = self.base:tree_code_lower_place(tree_code_input, self.index, expr_type(self))
        tree_code_input = tree_code_input:tree_code_with_result_state(place)
        local load = tree_code_input:tree_code_load_place(place.place, expr_type(self), "index")
        tree_code_input = tree_code_input:tree_code_with_result_state(load)
        return tree_code_input:tree_code_expr_result(load.value, load.ty)
    end

    function Tr.ExprLoad:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local addr_result = self.addr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
            local addr = addr_result.value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.ty or expr_type(self)), tree_code_input:tree_code_align_of(self.ty or expr_type(self)))
            local load = tree_code_input:tree_code_load_place(place, self.ty or expr_type(self), "load")
            tree_code_input = tree_code_input:tree_code_with_result_state(load)
            return tree_code_input:tree_code_expr_result(load.value, load.ty)
    end

    function Tr.ExprAtomicLoad:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = self.ty or expr_type(self)
            local addr_result = self.addr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
            local addr = addr_result.value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty))
            local dst_result = tree_code_input:tree_code_new_value("atomic_load")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstAtomicLoad(dst, place, tree_code_input:tree_code_atomic_access(Code.CodeMemoryRead, ty, self.ordering), self.ordering), origin_generated("atomic load")))
            return tree_code_input:tree_code_expr_result(dst, tree_code_input:tree_code_type(ty))
    end

    function Tr.ExprAtomicRmw:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = self.ty or expr_type(self)
            local addr_result = self.addr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
            local addr = addr_result.value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty))
            local value_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
            local value = value_result.value
            local dst_result = tree_code_input:tree_code_new_value("atomic_rmw")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstAtomicRmw(dst, self.op, place, value, tree_code_input:tree_code_atomic_access(Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic rmw")))
            return tree_code_input:tree_code_expr_result(dst, tree_code_input:tree_code_type(ty))
    end

    function Tr.ExprAtomicCas:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = self.ty or expr_type(self)
            local addr_result = self.addr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
            local addr = addr_result.value
            local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(ty), tree_code_input:tree_code_align_of(ty))
            local expected_result = self.expected:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(expected_result)
            local expected = expected_result.value
            local replacement_result = self.replacement:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(replacement_result)
            local replacement = replacement_result.value
            local dst_result = tree_code_input:tree_code_new_value("atomic_cas")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstAtomicCas(dst, place, expected, replacement, tree_code_input:tree_code_atomic_access(Code.CodeMemoryReadWrite, ty, self.ordering), self.ordering), origin_generated("atomic cas")))
            return tree_code_input:tree_code_expr_result(dst, tree_code_input:tree_code_type(ty))
    end

    function Tr.ExprCtor:lower_tree_expr_to_code(input)
        local tree_code_input = input
            if #(self.args or {}) > 1 then unsupported(tree_code_input, self, "multi-argument variant constructor `" .. tostring(self.type_name) .. "." .. tostring(self.variant_name) .. "`") end
            local def = tree_code_input:tree_code_variant_def(self.type_name)
            local variant_entry = def and def.variants[self.variant_name] or nil
            local variant = variant_entry and variant_entry.variant or nil
            if variant == nil then unsupported(tree_code_input, self, "unknown variant constructor `" .. tostring(self.type_name) .. "." .. tostring(self.variant_name) .. "`") end
            local owner_ty = expr_type(self)
            local payload = nil
            if #(self.args or {}) == 1 then
                local payload_result = self.args[1]:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
                tree_code_input = tree_code_input:tree_code_with_result_state(payload_result)
                payload = payload_result.value
            end
            local dst_result = tree_code_input:tree_code_new_value("variant_ctor")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstVariantCtor(dst, tree_code_input:tree_code_type(owner_ty), tree_code_input:tree_code_variant_ref(owner_ty, variant), payload), origin_generated("variant constructor")))
            return tree_code_input:tree_code_expr_result(dst, tree_code_input:tree_code_type(owner_ty))
    end

    function Tr.ExprNull:lower_tree_expr_to_code(input)
        local tree_code_input = input
            local ty = tree_code_input:tree_code_type(expr_type(self))
            local dst_result = tree_code_input:tree_code_new_value("null")
            tree_code_input = tree_code_input:tree_code_with_result_state(dst_result)
            local dst = dst_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstConst(dst, Code.CodeConstNull(ty)), origin_generated("null")))
            return tree_code_input:tree_code_expr_result(dst, ty)
    end

    function Tr.TreeCodeInput:tree_code_bind_alias(binding, src, ty)
        local declared = self:tree_code_state():tree_code_declare_binding_key(binding)
        self = self:tree_code_with_result_state(declared)
        local dst = self:tree_code_value_id_for_binding(binding)
        self = self:tree_code_with_result_state(self:tree_code_state():tree_code_note_binding(binding, dst))
        self = self:tree_code_with_result_state(self:tree_code_append_inst(Code.CodeInstAlias(dst, ty, src), origin_binding(binding)))
        return Tr.TreeCodeStateResult(self:tree_code_state())
    end

    function Tr.TreeCodeInput:tree_code_bind_local_init(binding, init_value, source_ty, is_mutable)
        local residence = is_mutable and Code.CodeResidenceAddressed or self:tree_code_residence_for(binding, source_ty)
        local local_result = self:tree_code_ensure_local(binding, source_ty, residence)
        self = self:tree_code_with_result_state(local_result)
        local stored = self:tree_code_store_place(Code.CodePlaceLocal(local_result.id, local_result.ty), source_ty, init_value, origin_binding(binding))
        return Tr.TreeCodeStateResult(stored.state)
    end

    function Tr.SwitchVariantStmtArm:tree_code_bind_variant_payload(tree_code_input, kind, owner_value, owner_ty, variant)
        if #(self.binds or {}) == 0 then return end
        if #(self.binds or {}) > 1 then unsupported(tree_code_input, self, "multi-bind variant arm `" .. tostring(variant.name) .. "`") end
        local payload_ty = tree_code_input:tree_code_variant_payload_type(variant)
        if payload_ty == nil then unsupported(tree_code_input, self, "payload bind for void variant `" .. tostring(variant.name) .. "`") end
        local ref = tree_code_input:tree_code_variant_ref(owner_ty, variant)
        local payload_result = tree_code_input:tree_code_new_value("variant_payload")
        tree_code_input = tree_code_input:tree_code_with_result_state(payload_result)
        local payload = payload_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstVariantPayload(payload, ref, owner_value), origin_generated("variant payload")))
        local binding = variant_binding(kind, variant, self.binds[1])
        local ty = tree_code_input:tree_code_type(binding.ty)
        if tree_code_input:tree_code_binding_is_addressed(binding) or ty:tree_code_is_aggregate_type() then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_local_init(binding, payload, binding.ty, false))
        else
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_alias(binding, payload, ty))
        end
    end

    function Tr.SwitchVariantExprArm:tree_code_bind_variant_payload(tree_code_input, kind, owner_value, owner_ty, variant)
        if #(self.binds or {}) == 0 then return end
        if #(self.binds or {}) > 1 then unsupported(tree_code_input, self, "multi-bind variant arm `" .. tostring(variant.name) .. "`") end
        local payload_ty = tree_code_input:tree_code_variant_payload_type(variant)
        if payload_ty == nil then unsupported(tree_code_input, self, "payload bind for void variant `" .. tostring(variant.name) .. "`") end
        local ref = tree_code_input:tree_code_variant_ref(owner_ty, variant)
        local payload_result = tree_code_input:tree_code_new_value("variant_payload")
        tree_code_input = tree_code_input:tree_code_with_result_state(payload_result)
        local payload = payload_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstVariantPayload(payload, ref, owner_value), origin_generated("variant payload")))
        local binding = variant_binding(kind, variant, self.binds[1])
        local ty = tree_code_input:tree_code_type(binding.ty)
        if tree_code_input:tree_code_binding_is_addressed(binding) or ty:tree_code_is_aggregate_type() then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_local_init(binding, payload, binding.ty, false))
        else
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_alias(binding, payload, ty))
        end
    end

    label_key = function(label)
        return label and label.name or tostring(label)
    end

    local function find_jump_arg(args, name)
        local found = nil
        for i = 1, #(args or {}) do
            if args[i].name == name then
                if found ~= nil then unsupported(nil, args[i], "duplicate jump arg `" .. tostring(name) .. "`") end
                found = args[i]
            end
        end
        if found == nil then unsupported(nil, name, "missing jump arg `" .. tostring(name) .. "`") end
        return found
    end

    local function control_binding(region_id, label, param, index, is_entry)
        local role = is_entry and Bind.BindingRoleEntryBlockParam(region_id, label.name, index) or Bind.BindingRoleBlockParam(region_id, label.name, index)
        return Bind.Binding(Core.Id("control:param:" .. region_id .. ":" .. label.name .. ":" .. param.name), param.name, param.ty, role)
    end

    function Tr.SwitchKeyInt:tree_code_switch_literal()
        return Core.LitInt(self.raw)
    end

    function Tr.SwitchKeyBool:tree_code_switch_literal()
        return Core.LitBool(self.value)
    end

    function Tr.SwitchKeyName:tree_code_switch_literal()
        unsupported(nil, self.name, "named switch case requires resolved key lowering")
    end

    function Tr.SwitchKeyExpr:tree_code_switch_literal()
        unsupported(nil, self.expr, "expression switch case requires compare-fallback lowering")
    end

    function Tr.TreeCodeInput:tree_code_lower_stmt_fallthrough_to(body, block_id, name, join_id)
        self = self:tree_code_with_result_state(self:tree_code_start_block(block_id, name, {}, origin_generated(name)))
        local saved = self:tree_code_save_bindings()
        local input = self:tree_code_lower_stmt_body(body or {})
        local falls = input:tree_code_state():tree_code_has_current_block()
        if falls then input = input:tree_code_with_result_state(input:tree_code_terminate(Code.CodeTermJump(join_id, {}), origin_generated(name .. " fallthrough"))) end
        input = input:tree_code_with_result_state(input:tree_code_restore_bindings(saved))
        return Tr.TreeCodeFallthroughResult(falls, input:tree_code_state())
    end

    function Tr.StmtIf:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local stmt = self
        local cond_result = stmt.cond:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(cond_result)
        local cond = cond_result.value
        local then_id_result = tree_code_input:tree_code_new_block("if_then")
        tree_code_input = tree_code_input:tree_code_with_result_state(then_id_result)
        local then_id = then_id_result.id
        local else_id_result = tree_code_input:tree_code_new_block("if_else")
        tree_code_input = tree_code_input:tree_code_with_result_state(else_id_result)
        local else_id = else_id_result.id
        local join_id_result = tree_code_input:tree_code_new_block("if_join")
        tree_code_input = tree_code_input:tree_code_with_result_state(join_id_result)
        local join_id = join_id_result.id
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if branch")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        local then_fall = tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.then_body, then_id, "if.then", join_id)
        tree_code_input = tree_code_input:tree_code_with_result_state(then_fall)
        local then_falls = then_fall.falls
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        local else_fall = tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.else_body, else_id, "if.else", join_id)
        tree_code_input = tree_code_input:tree_code_with_result_state(else_fall)
        local else_falls = else_fall.falls
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        if then_falls or else_falls then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(join_id, "if.join", {}, origin_generated("if join")))
        end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtSwitch:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local stmt = self
        if #(stmt.variant_arms or {}) > 0 then
            if #(stmt.arms or {}) > 0 then unsupported(tree_code_input, stmt, "mixed scalar and variant switch arms") end
            local owner_ty = expr_type(stmt.value)
            local type_name = owner_ty:tree_code_named_type_name()
            local def = type_name and tree_code_input:tree_code_variant_def(type_name) or nil
            if def == nil then unsupported(tree_code_input, stmt, "variant switch without tagged-union facts") end
            local value_result = stmt.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
            local value = value_result.value
            local tag_result = tree_code_input:tree_code_new_value("variant_tag")
            tree_code_input = tree_code_input:tree_code_with_result_state(tag_result)
            local tag = tag_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag")))
            local case_ids = {}
            local cases = {}
            for i = 1, #(stmt.variant_arms or {}) do
                local arm = stmt.variant_arms[i]
                local variant_entry = def.variants[arm.variant_name]
                local variant = variant_entry and variant_entry.variant or nil
                if variant == nil then unsupported(tree_code_input, stmt, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid_result = tree_code_input:tree_code_new_block("switch_variant_case")
                tree_code_input = tree_code_input:tree_code_with_result_state(bid_result)
                local bid = bid_result.id
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(tree_code_input:tree_code_variant_ref(owner_ty, variant), bid, {})
            end
            local default_id_result = tree_code_input:tree_code_new_block("switch_variant_default")
            tree_code_input = tree_code_input:tree_code_with_result_state(default_id_result)
            local default_id = default_id_result.id
            local join_id_result = tree_code_input:tree_code_new_block("switch_variant_join")
            tree_code_input = tree_code_input:tree_code_with_result_state(join_id_result)
            local join_id = join_id_result.id
            local saved = tree_code_input:tree_code_save_bindings()
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch")))
            local any_falls = false
            for i = 1, #(stmt.variant_arms or {}) do
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
                local arm = stmt.variant_arms[i]
                local variant_entry = def.variants[arm.variant_name]
                local variant = variant_entry and variant_entry.variant or nil
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(case_ids[i], "switch.variant.case", {}, origin_generated("variant switch case")))
                arm:tree_code_bind_variant_payload(tree_code_input, "stmt_switch", value, owner_ty, variant)
                tree_code_input = tree_code_input:tree_code_lower_stmt_body(arm.body or {})
                if tree_code_input:tree_code_state():tree_code_has_current_block() then tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, {}), origin_generated("variant switch case fallthrough")); any_falls = true end
            end
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
            local default_fall = tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.default_body or {}, default_id, "switch.variant.default", join_id)
            tree_code_input = tree_code_input:tree_code_with_result_state(default_fall)
            if default_fall.falls then any_falls = true end
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
            if any_falls then tree_code_input:tree_code_start_block(join_id, "switch.variant.join", {}, origin_generated("variant switch join")) end
            return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
        end
        local value_result = stmt.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
        local value = value_result.value
        local case_ids = {}
        local cases = {}
        for i = 1, #(stmt.arms or {}) do
            local bid_result = tree_code_input:tree_code_new_block("switch_case")
            tree_code_input = tree_code_input:tree_code_with_result_state(bid_result)
            local bid = bid_result.id
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(stmt.arms[i].key:tree_code_switch_literal(), bid, {})
        end
        local default_id_result = tree_code_input:tree_code_new_block("switch_default")
        tree_code_input = tree_code_input:tree_code_with_result_state(default_id_result)
        local default_id = default_id_result.id
        local join_id_result = tree_code_input:tree_code_new_block("switch_join")
        tree_code_input = tree_code_input:tree_code_with_result_state(join_id_result)
        local join_id = join_id_result.id
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch")))
        local any_falls = false
        for i = 1, #(stmt.arms or {}) do
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
            local case_fall = tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.arms[i].body, case_ids[i], "switch.case", join_id)
            tree_code_input = tree_code_input:tree_code_with_result_state(case_fall)
            if case_fall.falls then any_falls = true end
        end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        local default_fall = tree_code_input:tree_code_lower_stmt_fallthrough_to(stmt.default_body or {}, default_id, "switch.default", join_id)
        tree_code_input = tree_code_input:tree_code_with_result_state(default_fall)
        if default_fall.falls then any_falls = true end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        if any_falls then tree_code_input:tree_code_start_block(join_id, "switch.join", {}, origin_generated("switch join")) end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.ExprIf:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local expr = self
        local cond_result = expr.cond:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(cond_result)
        local cond = cond_result.value
        local then_id_result = tree_code_input:tree_code_new_block("expr_if_then")
        tree_code_input = tree_code_input:tree_code_with_result_state(then_id_result)
        local then_id = then_id_result.id
        local else_id_result = tree_code_input:tree_code_new_block("expr_if_else")
        tree_code_input = tree_code_input:tree_code_with_result_state(else_id_result)
        local else_id = else_id_result.id
        local join_id_result = tree_code_input:tree_code_new_block("expr_if_join")
        tree_code_input = tree_code_input:tree_code_with_result_state(join_id_result)
        local join_id = join_id_result.id
        local result_ty = tree_code_input:tree_code_type(expr_type(expr))
        local result_value_result = tree_code_input:tree_code_new_value("if_result")
        tree_code_input = tree_code_input:tree_code_with_result_state(result_value_result)
        local result_value = result_value_result.value
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("if expression result"))
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermBranch(cond, then_id, {}, else_id, {}), origin_generated("if expression branch")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(then_id, "expr.if.then", {}, origin_generated("if expression then")))
        local then_value_result = expr.then_expr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(then_value_result)
        local then_value = then_value_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { then_value }), origin_generated("if expression then yield")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(else_id, "expr.if.else", {}, origin_generated("if expression else")))
        local else_value_result = expr.else_expr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(else_value_result)
        local else_value = else_value_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { else_value }), origin_generated("if expression else yield")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(join_id, "expr.if.join", { result_param }, origin_generated("if expression join")))
        return tree_code_input:tree_code_expr_result(result_value, result_ty)
    end

    function Tr.ExprLogic:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local expr = self
        local lhs_result = expr.lhs:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(lhs_result)
        local lhs = lhs_result.value
        local rhs_id_result = tree_code_input:tree_code_new_block("logic_rhs")
        tree_code_input = tree_code_input:tree_code_with_result_state(rhs_id_result)
        local rhs_id = rhs_id_result.id
        local short_id_result = tree_code_input:tree_code_new_block("logic_short")
        tree_code_input = tree_code_input:tree_code_with_result_state(short_id_result)
        local short_id = short_id_result.id
        local join_id_result = tree_code_input:tree_code_new_block("logic_join")
        tree_code_input = tree_code_input:tree_code_with_result_state(join_id_result)
        local join_id = join_id_result.id
        local result_value_result = tree_code_input:tree_code_new_value("logic_result")
        tree_code_input = tree_code_input:tree_code_with_result_state(result_value_result)
        local result_value = result_value_result.value
        local result_param = Code.CodeParam(result_value, "result", Code.CodeTyBool8, origin_generated("logic result"))
        if expr.op == Core.LogicAnd then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermBranch(lhs, rhs_id, {}, short_id, {}), origin_generated("logic and branch")))
        elseif expr.op == Core.LogicOr then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermBranch(lhs, short_id, {}, rhs_id, {}), origin_generated("logic or branch")))
        else
            unsupported(tree_code_input, expr, "logic op " .. class_name(expr.op))
        end
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(rhs_id, "logic.rhs", {}, origin_generated("logic rhs")))
        local rhs_result = expr.rhs:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(rhs_result)
        local rhs = rhs_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { rhs }), origin_generated("logic rhs yield")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(short_id, "logic.short", {}, origin_generated("logic short")))
        local lit = expr.op == Core.LogicAnd and Core.LitBool(false) or Core.LitBool(true)
        local short_value_result = tree_code_input:tree_code_new_value("logic_short")
        tree_code_input = tree_code_input:tree_code_with_result_state(short_value_result)
        local short_value = short_value_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstConst(short_value, Code.CodeConstLiteral(Code.CodeTyBool8, lit)), origin_generated("logic short-circuit literal")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { short_value }), origin_generated("logic short yield")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(join_id, "logic.join", { result_param }, origin_generated("logic join")))
        return tree_code_input:tree_code_expr_result(result_value, Code.CodeTyBool8)
    end

    function Tr.ExprSwitch:lower_tree_expr_to_code(input)
        local tree_code_input = input
        local expr = self
        if #(expr.variant_arms or {}) > 0 then
            if #(expr.arms or {}) > 0 then unsupported(tree_code_input, expr, "mixed scalar and variant switch expression arms") end
            local owner_ty = expr_type(expr.value)
            local type_name = owner_ty:tree_code_named_type_name()
            local def = type_name and tree_code_input:tree_code_variant_def(type_name) or nil
            if def == nil then unsupported(tree_code_input, expr, "variant switch expression without tagged-union facts") end
            local value_result = expr.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
            local value = value_result.value
            local tag_result = tree_code_input:tree_code_new_value("variant_tag")
            tree_code_input = tree_code_input:tree_code_with_result_state(tag_result)
            local tag = tag_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstVariantTag(tag, Code.CodeTyInt(32, Code.CodeUnsigned), value), origin_generated("variant tag")))
            local result_ty = tree_code_input:tree_code_type(expr_type(expr))
            local result_value_result = tree_code_input:tree_code_new_value("switch_result")
            tree_code_input = tree_code_input:tree_code_with_result_state(result_value_result)
            local result_value = result_value_result.value
            local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("variant switch expression result"))
            local case_ids = {}
            local cases = {}
            for i = 1, #(expr.variant_arms or {}) do
                local arm = expr.variant_arms[i]
                local variant_entry = def.variants[arm.variant_name]
                local variant = variant_entry and variant_entry.variant or nil
                if variant == nil then unsupported(tree_code_input, expr, "unknown variant arm `" .. tostring(arm.variant_name) .. "`") end
                local bid_result = tree_code_input:tree_code_new_block("expr_switch_variant_case")
                tree_code_input = tree_code_input:tree_code_with_result_state(bid_result)
                local bid = bid_result.id
                case_ids[i] = bid
                cases[i] = Code.CodeVariantCase(tree_code_input:tree_code_variant_ref(owner_ty, variant), bid, {})
            end
            local default_id_result = tree_code_input:tree_code_new_block("expr_switch_variant_default")
            tree_code_input = tree_code_input:tree_code_with_result_state(default_id_result)
            local default_id = default_id_result.id
            local join_id_result = tree_code_input:tree_code_new_block("expr_switch_variant_join")
            tree_code_input = tree_code_input:tree_code_with_result_state(join_id_result)
            local join_id = join_id_result.id
            local saved = tree_code_input:tree_code_save_bindings()
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermVariantSwitch(tag, cases, default_id, {}), origin_generated("variant switch expression")))
            local any_falls = false
            for i = 1, #(expr.variant_arms or {}) do
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
                local arm = expr.variant_arms[i]
                local variant_entry = def.variants[arm.variant_name]
                local variant = variant_entry and variant_entry.variant or nil
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(case_ids[i], "expr.switch.variant.case", {}, origin_generated("variant switch expression case")))
                arm:tree_code_bind_variant_payload(tree_code_input, "expr_switch", value, owner_ty, variant)
                tree_code_input = tree_code_input:tree_code_lower_stmt_body(arm.body or {})
                if tree_code_input:tree_code_state():tree_code_has_current_block() then
                    local arm_value_result = arm.result:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
                    tree_code_input = tree_code_input:tree_code_with_result_state(arm_value_result)
                    local arm_value = arm_value_result.value
                    tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { arm_value }), origin_generated("variant switch expression case yield")))
                    any_falls = true
                end
            end
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(default_id, "expr.switch.variant.default", {}, origin_generated("variant switch expression default")))
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(expr.default_body or {})
            if tree_code_input:tree_code_state():tree_code_has_current_block() then
                local default_value_result = expr.default_expr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
                tree_code_input = tree_code_input:tree_code_with_result_state(default_value_result)
                local default_value = default_value_result.value
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { default_value }), origin_generated("variant switch expression default yield")))
                any_falls = true
            end
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
            if not any_falls then unsupported(tree_code_input, expr, "variant switch expression has no value-producing arm") end
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(join_id, "expr.switch.variant.join", { result_param }, origin_generated("variant switch expression join")))
            return tree_code_input:tree_code_expr_result(result_value, result_ty)
        end
        local value_result = expr.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
        local value = value_result.value
        local result_ty = tree_code_input:tree_code_type(expr_type(expr))
        local result_value_result = tree_code_input:tree_code_new_value("switch_result")
        tree_code_input = tree_code_input:tree_code_with_result_state(result_value_result)
        local result_value = result_value_result.value
        local result_param = Code.CodeParam(result_value, "result", result_ty, origin_generated("switch expression result"))
        local case_ids = {}
        local cases = {}
        for i = 1, #(expr.arms or {}) do
            local bid_result = tree_code_input:tree_code_new_block("expr_switch_case")
            tree_code_input = tree_code_input:tree_code_with_result_state(bid_result)
            local bid = bid_result.id
            case_ids[i] = bid
            cases[i] = Code.CodeSwitchCase(expr.arms[i].key:tree_code_switch_literal(), bid, {})
        end
        local default_id_result = tree_code_input:tree_code_new_block("expr_switch_default")
        tree_code_input = tree_code_input:tree_code_with_result_state(default_id_result)
        local default_id = default_id_result.id
        local join_id_result = tree_code_input:tree_code_new_block("expr_switch_join")
        tree_code_input = tree_code_input:tree_code_with_result_state(join_id_result)
        local join_id = join_id_result.id
        local saved = tree_code_input:tree_code_save_bindings()
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermSwitch(value, cases, default_id, {}), origin_generated("switch expression")))
        local any_falls = false
        for i = 1, #(expr.arms or {}) do
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(case_ids[i], "expr.switch.case", {}, origin_generated("switch expression case")))
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(expr.arms[i].body or {})
            if tree_code_input:tree_code_state():tree_code_has_current_block() then
                local arm_value_result = expr.arms[i].result:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
                tree_code_input = tree_code_input:tree_code_with_result_state(arm_value_result)
                local arm_value = arm_value_result.value
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { arm_value }), origin_generated("switch expression case yield")))
                any_falls = true
            end
        end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(default_id, "expr.switch.default", {}, origin_generated("switch expression default")))
        tree_code_input = tree_code_input:tree_code_lower_stmt_body(expr.default_body or {})
        if tree_code_input:tree_code_state():tree_code_has_current_block() then
            local default_value_result = expr.default_expr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(default_value_result)
            local default_value = default_value_result.value
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(join_id, { default_value }), origin_generated("switch expression default yield")))
            any_falls = true
        end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved))
        if not any_falls then unsupported(tree_code_input, expr, "switch expression has no value-producing arm") end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(join_id, "expr.switch.join", { result_param }, origin_generated("switch expression join")))
        return tree_code_input:tree_code_expr_result(result_value, result_ty)
    end

    function Tr.ControlExprRegion:tree_code_lower_expr_control_to_code(tree_code_input)
        local region = self
        local result_ty = tree_code_input:tree_code_type(region.result_ty)
        local result_value_alloc = tree_code_input:tree_code_new_value("control_result")
        tree_code_input = tree_code_input:tree_code_with_result_state(result_value_alloc)
        local result_value = result_value_alloc.value
        local exit_params = { Code.CodeParam(result_value, "result", result_ty, origin_generated("control result")) }
        local saved_alpha, saved_alpha_suffix = tree_code_input:tree_code_state():tree_code_alpha_snapshot()
        local alpha_counter = tree_code_input:tree_code_state():tree_code_next_counter("control_scope")
        tree_code_input = tree_code_input:tree_code_with_result_state(alpha_counter)
        local alpha_suffix = "ctl" .. tostring(alpha_counter.value)
        local alpha_result = tree_code_input:tree_code_state():tree_code_fork_alpha(alpha_suffix)
        tree_code_input = tree_code_input:tree_code_with_result_state(alpha_result)
        local alpha = alpha_result.renamed_by_key
        local records = {}
        local targets = {}
        local function add_record(block, is_entry)
            local bid_result = tree_code_input:tree_code_new_block("ctl_" .. block.label.name)
            tree_code_input = tree_code_input:tree_code_with_result_state(bid_result)
            local bid = bid_result.id
            local params = {}
            local bindings = {}
            for i = 1, #(block.params or {}) do
                local b = control_binding(region.region_id, block.label, block.params[i], i, is_entry)
                local declared = tree_code_input:tree_code_state():tree_code_declare_binding_key(b)
                tree_code_input = tree_code_input:tree_code_with_result_state(declared)
                local v = tree_code_input:tree_code_value_id_for_binding(b)
                local ty = tree_code_input:tree_code_type(block.params[i].ty)
                params[#params + 1] = Code.CodeParam(v, block.params[i].name, ty, origin_binding(b))
                bindings[#bindings + 1] = { binding = b, value = v, ty = block.params[i].ty, code_ty = ty }
            end
            local rec = { id = bid, label = block.label, name = "ctl." .. block.label.name, params = params, bindings = bindings, body = block.body or {}, entry = is_entry, entry_params = block.params or {} }
            records[#records + 1] = rec
            targets[#targets + 1] = Tr.TreeCodeControlTargetEntry(label_key(block.label), Tr.TreeCodeControlTarget(bid, params))
            return rec
        end
        local entry = add_record(region.entry, true)
        for i = 1, #(region.blocks or {}) do add_record(region.blocks[i], false) end
        local region_alpha = clone_map(tree_code_input:tree_code_state().alpha.renamed_by_key)
        local exit_id_result = tree_code_input:tree_code_new_block("ctl_expr_exit")
        tree_code_input = tree_code_input:tree_code_with_result_state(exit_id_result)
        local exit_id = exit_id_result.id
        local saved_outer = tree_code_input:tree_code_save_bindings()
        local entry_args = {}
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix))
        for i = 1, #(region.entry.params or {}) do
            local entry_arg_result = region.entry.params[i].init:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(entry_arg_result)
            entry_args[#entry_args + 1] = entry_arg_result.value
        end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(region_alpha, alpha_suffix))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region")))
        local outer_control = tree_code_input:tree_code_state():tree_code_current_control_region()
        local control_region = Tr.TreeCodeExprControlRegion(exit_id, targets)
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_enter_control_region(control_region))
        local saved_region_outer = saved_outer
        for i = 1, #records do
            local rec = records[i]
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved_region_outer))
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(setmetatable({}, { __index = region_alpha }), alpha_suffix .. "_b" .. tostring(i)))
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(rec.id, rec.name, rec.params, origin_generated("control block " .. rec.label.name)))
            for j = 1, #rec.bindings do
                local b = rec.bindings[j]
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_note_binding(b.binding, b.value))
                if tree_code_input:tree_code_binding_is_addressed(b.binding) or b.code_ty:tree_code_is_aggregate_type() then
                    tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_local_init(b.binding, b.value, b.ty, false))
                end
            end
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(rec.body)
            if tree_code_input:tree_code_state():tree_code_has_current_block() then unsupported(tree_code_input, rec.label, "control block `" .. tostring(rec.label.name) .. "` can fall through") end
        end
        local exit_result = tree_code_input:tree_code_state():tree_code_leave_control_region(outer_control)
        tree_code_input = tree_code_input:tree_code_with_result_state(exit_result)
        local has_exit = exit_result.saw_exit
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved_outer))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(exit_id, "ctl.expr.exit", exit_params, origin_generated("control exit")))
        return tree_code_input:tree_code_expr_result(result_value, result_ty)
    end

    function Tr.ControlStmtRegion:tree_code_lower_stmt_control_to_code(tree_code_input)
        local region = self
        local saved_alpha, saved_alpha_suffix = tree_code_input:tree_code_state():tree_code_alpha_snapshot()
        local alpha_counter = tree_code_input:tree_code_state():tree_code_next_counter("control_scope")
        tree_code_input = tree_code_input:tree_code_with_result_state(alpha_counter)
        local alpha_suffix = "ctl" .. tostring(alpha_counter.value)
        local alpha_result = tree_code_input:tree_code_state():tree_code_fork_alpha(alpha_suffix)
        tree_code_input = tree_code_input:tree_code_with_result_state(alpha_result)
        local alpha = alpha_result.renamed_by_key
        local records = {}
        local targets = {}
        local function add_record(block, is_entry)
            local bid_result = tree_code_input:tree_code_new_block("ctl_" .. block.label.name)
            tree_code_input = tree_code_input:tree_code_with_result_state(bid_result)
            local bid = bid_result.id
            local params = {}
            local bindings = {}
            for i = 1, #(block.params or {}) do
                local b = control_binding(region.region_id, block.label, block.params[i], i, is_entry)
                local declared = tree_code_input:tree_code_state():tree_code_declare_binding_key(b)
                tree_code_input = tree_code_input:tree_code_with_result_state(declared)
                local v = tree_code_input:tree_code_value_id_for_binding(b)
                local ty = tree_code_input:tree_code_type(block.params[i].ty)
                params[#params + 1] = Code.CodeParam(v, block.params[i].name, ty, origin_binding(b))
                bindings[#bindings + 1] = { binding = b, value = v, ty = block.params[i].ty, code_ty = ty }
            end
            local rec = { id = bid, label = block.label, name = "ctl." .. block.label.name, params = params, bindings = bindings, body = block.body or {}, entry = is_entry, entry_params = block.params or {} }
            records[#records + 1] = rec
            targets[#targets + 1] = Tr.TreeCodeControlTargetEntry(label_key(block.label), Tr.TreeCodeControlTarget(bid, params))
            return rec
        end
        local entry = add_record(region.entry, true)
        for i = 1, #(region.blocks or {}) do add_record(region.blocks[i], false) end
        local region_alpha = clone_map(tree_code_input:tree_code_state().alpha.renamed_by_key)
        local exit_id_result = tree_code_input:tree_code_new_block("ctl_stmt_exit")
        tree_code_input = tree_code_input:tree_code_with_result_state(exit_id_result)
        local exit_id = exit_id_result.id
        local saved_outer = tree_code_input:tree_code_save_bindings()
        local entry_args = {}
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix))
        for i = 1, #(region.entry.params or {}) do
            local entry_arg_result = region.entry.params[i].init:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(entry_arg_result)
            entry_args[#entry_args + 1] = entry_arg_result.value
        end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(region_alpha, alpha_suffix))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(entry.id, entry_args), origin_generated("enter control region")))
        local outer_control = tree_code_input:tree_code_state():tree_code_current_control_region()
        local control_region = Tr.TreeCodeStmtControlRegion(exit_id, targets)
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_enter_control_region(control_region))
        local saved_region_outer = saved_outer
        for i = 1, #records do
            local rec = records[i]
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved_region_outer))
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(setmetatable({}, { __index = region_alpha }), alpha_suffix .. "_b" .. tostring(i)))
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(rec.id, rec.name, rec.params, origin_generated("control block " .. rec.label.name)))
            for j = 1, #rec.bindings do
                local b = rec.bindings[j]
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_note_binding(b.binding, b.value))
                if tree_code_input:tree_code_binding_is_addressed(b.binding) or b.code_ty:tree_code_is_aggregate_type() then
                    tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_local_init(b.binding, b.value, b.ty, false))
                end
            end
            tree_code_input = tree_code_input:tree_code_lower_stmt_body(rec.body)
            if tree_code_input:tree_code_state():tree_code_has_current_block() then unsupported(tree_code_input, rec.label, "control block `" .. tostring(rec.label.name) .. "` can fall through") end
        end
        local exit_result = tree_code_input:tree_code_state():tree_code_leave_control_region(outer_control)
        tree_code_input = tree_code_input:tree_code_with_result_state(exit_result)
        local has_exit = exit_result.saw_exit
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_use_alpha(saved_alpha, saved_alpha_suffix))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_restore_bindings(saved_outer))
        if has_exit then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(exit_id, "ctl.stmt.exit", {}, origin_generated("control exit")))
        end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtLet:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local init = self.init:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(init)
        local src, ty = init.value, init.ty
        local declared = tree_code_input:tree_code_state():tree_code_declare_fresh_binding_key(self.binding)
        tree_code_input = tree_code_input:tree_code_with_result_state(declared)
        if tree_code_input:tree_code_binding_is_addressed(self.binding) or (ty:tree_code_is_aggregate_type() and not ty:tree_code_is_view_type()) then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_local_init(self.binding, src, self.binding.ty, false))
        else
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_alias(self.binding, src, ty))
        end
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtVar:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local init = self.init:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(init)
        local src = init.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_note_mutable(self.binding))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_local_init(self.binding, src, self.binding.ty, true))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtSet:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local value_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
        local value = value_result.value
        local place_result = self.place:lower_tree_place_to_code(tree_code_input:tree_code_place_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(place_result)
        local place = place_result.place
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_store_place(place, place_type(self.place), value, origin_generated("set")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtAtomicStore:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local value_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
        local value = value_result.value
        local addr_result = self.addr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(addr_result)
        local addr = addr_result.value
        local place = Code.CodePlaceDeref(addr, tree_code_input:tree_code_type(self.ty), tree_code_input:tree_code_align_of(self.ty))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstAtomicStore(place, value, tree_code_input:tree_code_atomic_access(Code.CodeMemoryWrite, self.ty, self.ordering), self.ordering), origin_generated("atomic store")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtAtomicFence:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_append_inst(Code.CodeInstAtomicFence(self.ordering), origin_generated("atomic fence")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtExpr:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local result = self.expr:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(result)
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtControl:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        return self.region:tree_code_lower_stmt_control_to_code(tree_code_input)
    end

    function Tr.StmtJump:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local region = tree_code_input:tree_code_state():tree_code_current_control_region()
        if region == nil then unsupported(tree_code_input, self, "jump outside control region") end
        local target = tree_code_input:tree_code_state():tree_code_control_target(self.target)
        if target == nil then unsupported(tree_code_input, self, "missing control target `" .. tostring(self.target.name) .. "`") end
        local args = {}
        for i = 1, #target.params do
            local arg = find_jump_arg(self.args, target.params[i].name)
            local arg_result = arg.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
            tree_code_input = tree_code_input:tree_code_with_result_state(arg_result)
            args[#args + 1] = arg_result.value
        end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(target.id, args), origin_generated("control jump")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtJumpCont:lower_tree_stmt_to_code(input)
        unsupported(input, self, "continuation slot jump after open expansion")
    end

    function Tr.TreeCodeExprControlRegion:tree_code_yield_value_exit(tree_code_input, stmt)
        return self.exit_id
    end

    function Tr.TreeCodeStmtControlRegion:tree_code_yield_value_exit(tree_code_input, stmt)
        unsupported(tree_code_input, stmt, "value yield outside expression control region")
    end

    function Tr.TreeCodeExprControlRegion:tree_code_yield_void_exit(tree_code_input, stmt)
        unsupported(tree_code_input, stmt, "void yield outside statement control region")
    end

    function Tr.TreeCodeStmtControlRegion:tree_code_yield_void_exit(tree_code_input, stmt)
        return self.exit_id
    end

    function Tr.StmtYieldValue:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local region = tree_code_input:tree_code_state():tree_code_current_control_region()
        if region == nil then unsupported(tree_code_input, self, "value yield outside expression control region") end
        local value_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
        local value = value_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_note_control_exit())
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(region:tree_code_yield_value_exit(tree_code_input, self), { value }), origin_generated("control yield value")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtYieldVoid:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local region = tree_code_input:tree_code_state():tree_code_current_control_region()
        if region == nil then unsupported(tree_code_input, self, "void yield outside statement control region") end
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_note_control_exit())
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermJump(region:tree_code_yield_void_exit(tree_code_input, self), {}), origin_generated("control yield")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtReturnValue:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local value_result = self.value:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(value_result)
        local value = value_result.value
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermReturn({ value }), origin_generated("return")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtReturnVoid:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermReturn({}), origin_generated("return")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtTrap:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermTrap("source trap"), origin_generated("trap")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.StmtAssert:lower_tree_stmt_to_code(input)
        local tree_code_input = input
        local cond_result = self.cond:lower_tree_expr_to_code(tree_code_input:tree_code_expr_input())
        tree_code_input = tree_code_input:tree_code_with_result_state(cond_result)
        local cond = cond_result.value
        local ok_id_result = tree_code_input:tree_code_new_block("assert_ok")
        tree_code_input = tree_code_input:tree_code_with_result_state(ok_id_result)
        local ok_id = ok_id_result.id
        local trap_id_result = tree_code_input:tree_code_new_block("assert_trap")
        tree_code_input = tree_code_input:tree_code_with_result_state(trap_id_result)
        local trap_id = trap_id_result.id
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermBranch(cond, ok_id, {}, trap_id, {}), origin_generated("assert branch")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(trap_id, "assert.trap", {}, origin_generated("assert trap")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermTrap("assertion failed"), origin_generated("assert trap")))
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(ok_id, "assert.ok", {}, origin_generated("assert ok")))
        return Tr.TreeCodeStmtResult(tree_code_input:tree_code_state())
    end

    function Tr.FuncLocal:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageLocal, self.params, self.result, self.body)
    end

    function Tr.FuncExport:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageExport, self.params, self.result, self.body)
    end

    function Tr.FuncLocalContract:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageLocal, self.params, self.result, self.body)
    end

    function Tr.FuncExportContract:lower_tree_func_parts_to_code()
        return Tr.TreeCodeFuncParts(self.name, Code.CodeLinkageExport, self.params, self.result, self.body)
    end

    function Ty.Param:tree_code_param_binding(func_name, index)
        return Bind.Binding(Core.Id("arg:" .. func_name .. ":" .. self.name), self.name, self.ty, Bind.BindingRoleArg(index - 1))
    end

    function Tr.TreeCodeFuncParts:tree_code_param_types()
        local out = {}
        for i = 1, #(self.params or {}) do out[i] = self.params[i].ty end
        return out
    end

    function Ty.Param:lower_tree_param_to_code(tree_code_input, func_name, index)
        local binding = self:tree_code_param_binding(func_name, index)
        local ty = tree_code_input:tree_code_type(self.ty)
        local value = tree_code_input:tree_code_value_id_for_binding(binding)
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_state():tree_code_note_binding(binding, value))
        local code_param = Code.CodeParam(value, self.name, ty, origin_binding(binding))
        if tree_code_input:tree_code_binding_is_addressed(binding) or ty:tree_code_is_aggregate_type() then
            tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_bind_local_init(binding, value, self.ty, false))
        end
        return Tr.TreeCodeParamResult(code_param, ty, tree_code_input:tree_code_state())
    end

    function Tr.TreeCodeInput:tree_code_global_init_for_const(source_ty, value_expr, site)
        local value = ConstEval.value(value_expr, self:tree_code_module_facts().const_env, ConstEval.empty_local_env())
        local ty = self:tree_code_type(source_ty)
        return value:tree_code_global_init(self, ty, value_expr, site)
    end

    function Sem.ConstValue:tree_code_global_init(tree_code_input, ty, value_expr, site)
        unsupported(tree_code_input, value_expr, "non-scalar constant initializer for global `" .. tostring(site) .. "`")
    end
    function Sem.ConstInt:tree_code_global_init(tree_code_input, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitInt(self.raw)) }
    end
    function Sem.ConstFloat:tree_code_global_init(tree_code_input, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitFloat(self.raw)) }
    end
    function Sem.ConstBool:tree_code_global_init(tree_code_input, ty, value_expr, site)
        return { Code.CodeDataScalar(0, ty, Core.LitBool(self.value)) }
    end

    function Tr.ConstItem:tree_code_lower_global_to_code(input)
        local start = input:tree_code_func_lowering_start(input.module_facts.module_name)
        local expr_input = Tr.TreeCodeExprInput(start.facts, start.state)
        local inits = expr_input:tree_code_global_init_for_const(self.ty, self.value, self.name)
        return Code.CodeGlobal(code_global_id(input.module_facts.module_name, self.name), self.name, expr_input:tree_code_type(self.ty), Code.CodeLinkageLocal, expr_input:tree_code_size_of(self.ty), expr_input:tree_code_align_of(self.ty), inits, origin_generated("global " .. tostring(self.name)))
    end

    function Tr.StaticItem:tree_code_lower_global_to_code(input)
        local start = input:tree_code_func_lowering_start(input.module_facts.module_name)
        local input = Tr.TreeCodeExprInput(start.facts, start.state)
        local inits = input:tree_code_global_init_for_const(self.ty, self.value, self.name)
        return Code.CodeGlobal(code_global_id(input:tree_code_module_facts().module_name, self.name), self.name, input:tree_code_type(self.ty), Code.CodeLinkageLocal, input:tree_code_size_of(self.ty), input:tree_code_align_of(self.ty), inits, origin_generated("global " .. tostring(self.name)))
    end

    function Tr.TreeCodeContractInput:tree_code_value_for_binding(binding)
        return Code.CodeValueId("v:" .. sanitize(self.func_name) .. ":" .. sanitize(binding:tree_code_binding_key()))
    end

    function Tr.TreeCodeContractInput:tree_code_value_for_expr(expr)
        return expr:tree_code_contract_value(self)
    end

    function Tr.Expr:tree_code_contract_value(input)
        return nil, "contract expression is not a lowered binding reference: " .. class_name(self)
    end
    function Tr.ExprRef:tree_code_contract_value(input)
        return self.ref:tree_code_contract_value(input, self)
    end
    function Bind.ValueRef:tree_code_contract_value(input, expr)
        return nil, "contract expression is not a lowered binding reference: " .. class_name(expr)
    end
    function Bind.ValueRefBinding:tree_code_contract_value(input, expr)
        return input:tree_code_value_for_binding(self.binding)
    end

    function Tr.TreeCodeContractInput:tree_code_contract_reject(reason)
        return Code.CodeFuncContractFact(
            self.func_id,
            Code.CodeContractRejected(tostring(reason or "unsupported contract fact")),
            origin_generated("contract rejection")
        )
    end

    function Tr.TreeCodeContractInput:tree_code_join_reasons(...)
        local out = {}
        for i = 1, select("#", ...) do
            local reason = select(i, ...)
            if reason ~= nil then out[#out + 1] = tostring(reason) end
        end
        return table.concat(out, "; ")
    end

    function Tr.ContractFactBounds:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractBounds(
            tree_code_input:tree_code_value_for_binding(self.base),
            tree_code_input:tree_code_value_for_binding(self.len)
        ), origin_binding(self.base)))
    end

    function Tr.ContractFactWindowBounds:lower_tree_contract_fact_to_code(tree_code_input)
        local base = tree_code_input:tree_code_value_for_binding(self.base)
        local base_len, base_len_err = tree_code_input:tree_code_value_for_expr(self.base_len)
        local start, start_err = tree_code_input:tree_code_value_for_expr(self.start)
        local len, len_err = tree_code_input:tree_code_value_for_expr(self.len)
        if base_len == nil or start == nil or len == nil then
            return Tr.TreeCodeContractResult(tree_code_input:tree_code_contract_reject(tree_code_input:tree_code_join_reasons(base_len_err, start_err, len_err)))
        end
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractWindowBounds(base, base_len, start, len), origin_binding(self.base)))
    end

    function Tr.ContractFactDisjoint:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractDisjoint(tree_code_input:tree_code_value_for_binding(self.a), tree_code_input:tree_code_value_for_binding(self.b)), origin_binding(self.a)))
    end

    function Tr.ContractFactSameLen:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractSameLen(tree_code_input:tree_code_value_for_binding(self.a), tree_code_input:tree_code_value_for_binding(self.b)), origin_binding(self.a)))
    end

    function Tr.ContractFactSoAComponent:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractSoAComponent(tree_code_input:tree_code_value_for_binding(self.base), tree_code_input:tree_code_type(self.record_ty), self.field_name, self.component_index), origin_binding(self.base)))
    end

    function Tr.ContractFactNoAlias:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractNoAlias(tree_code_input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactReadonly:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractReadonly(tree_code_input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactWriteonly:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractWriteonly(tree_code_input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactInvalidate:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractInvalidate(tree_code_input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactPreserve:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(Code.CodeFuncContractFact(tree_code_input.func_id, Code.CodeContractPreserve(tree_code_input:tree_code_value_for_binding(self.base)), origin_binding(self.base)))
    end

    function Tr.ContractFactRejected:lower_tree_contract_fact_to_code(tree_code_input)
        return Tr.TreeCodeContractResult(tree_code_input:tree_code_contract_reject("tree contract rejected: " .. class_name(self.issue)))
    end

    function Tr.Module:tree_code_module_parts(opts)
        opts = opts or {}
        local layout_env = opts.layout_env
        if layout_env == nil then layout_env = T.LalinSem.LayoutEnv(ModuleType.env(self, opts.target).layouts) end
        local mod_name = self:tree_code_module_name()
        local const_entries = {}
        for i = 1, #(self.items or {}) do
            self.items[i]:tree_code_add_const_entries(const_entries, mod_name)
        end
        local module_facts = Tr.TreeCodeModuleFacts(
            mod_name,
            layout_env,
            tree_code_target(opts.target),
            Bind.ConstEnv(const_entries),
            self:tree_code_variant_defs(mod_name)
        )
        local sigs = Tr.TreeCodeModuleSigState(mod_name, {}, {})
        local registrations = Tr.TreeCodeModuleRegistrationState({}, {}, {})
        local emission = Tr.TreeCodeModuleEmissionState({}, {})
        local input = Tr.TreeCodeItemRegisterInput(module_facts, sigs, registrations)
        for i = 1, #(self.items or {}) do
            self.items[i]:lower_tree_item_register_to_code(input)
        end
        return Tr.TreeCodeModuleParts(module_facts, sigs, registrations, emission)
    end

    function Tr.Item:lower_tree_item_register_to_code(input) end
    function Tr.Item:tree_code_add_const_entries(entries, mod_name) end
    function Tr.ItemConst:tree_code_add_const_entries(entries, mod_name)
        self.c:tree_code_add_const_entries(entries, mod_name)
    end
    function Tr.ConstItem:tree_code_add_const_entries(entries, mod_name)
        entries[#entries + 1] = Bind.ConstEntry(mod_name, self.name, self.ty, self.value)
    end

    function Tr.ItemFunc:lower_tree_item_register_to_code(input)
        local parts = self.func:lower_tree_func_parts_to_code()
        local sig = CodeType.ensure_type_sig(input.sigs, parts:tree_code_param_types(), parts.result)
        local key = func_key(input.module_facts.module_name, parts.name)
        input.registrations.funcs[key] = Tr.TreeCodeFuncRegistrationEntry(key, Tr.TreeCodeFuncRegistration(code_func_id(parts.name), sig))
    end

    function Tr.ItemExtern:lower_tree_item_register_to_code(input)
        local f = self.func
        f:tree_code_register_extern(input)
    end

    function Tr.ExternFunc:tree_code_register_extern(input)
        local param_tys = {}
        for j = 1, #(self.params or {}) do param_tys[j] = self.params[j].ty end
        local sig = CodeType.ensure_type_sig(input.sigs, param_tys, self.result)
        local ex = Code.CodeExtern(code_extern_id(self.name), self.name, self.symbol, sig, origin_generated("extern " .. self.name))
        input.registrations.externs[self.name] = Tr.TreeCodeExternEntry(self.name, ex)
        input.registrations.extern_order[#input.registrations.extern_order + 1] = ex
    end

    function Tr.Module:lower_tree_module_contracts_to_code(opts)
        opts = opts or {}
        local parts = self:tree_code_module_parts(opts)
        local mod_id = Code.CodeModuleId("module:" .. sanitize(opts.module_id or self:tree_code_module_name()))
        local facts = {}
        local input = Tr.TreeCodeItemContractsInput(parts.module_facts, parts.sigs, parts.registrations, parts.emission, facts)
        for i = 1, #(self.items or {}) do
            local item = self.items[i]
            item:lower_tree_item_contracts_to_code(input)
        end
        return Code.CodeContractFactSet(mod_id, input.contract_facts)
    end

    function Tr.Item:lower_tree_item_contracts_to_code(input) end

    function Tr.ItemFunc:lower_tree_item_contracts_to_code(input)
        local parts = self.func:lower_tree_func_parts_to_code()
        local func_id = code_func_id(parts.name)
        local tree_facts = TreeContractFacts.facts(self.func)
        local contract_input = Tr.TreeCodeContractInput(input.module_facts, input.sigs, parts.name, func_id)
        for j = 1, #(tree_facts.facts or {}) do
            input.contract_facts[#input.contract_facts + 1] = tree_facts.facts[j]:lower_tree_contract_fact_to_code(contract_input).fact
        end
    end

    function Tr.Func:lower_tree_func_to_code(input)
        local parts = self:lower_tree_func_parts_to_code()
        local residence = collect_address_taken_stmts(parts.body or {}, { addressed = {}, mutable = {} })
        local start = input:tree_code_func_lowering_start(parts.name, residence)
        local tree_code_input = Tr.TreeCodeStmtInput(start.facts, start.state)

        local entry = Code.CodeBlockId("block:" .. sanitize(parts.name) .. ":entry")
        tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_start_block(entry, "entry", {}, origin_generated("entry block")))

        local code_params = {}
        local sig_params = {}
        for i = 1, #(parts.params or {}) do
            local param_result = parts.params[i]:lower_tree_param_to_code(tree_code_input, parts.name, i)
            tree_code_input = tree_code_input:tree_code_with_result_state(param_result)
            code_params[#code_params + 1] = param_result.param
            sig_params[#sig_params + 1] = param_result.ty
        end

        local result = tree_code_input:tree_code_type(parts.result)
        local sig_results = {}
        if result ~= Code.CodeTyVoid then sig_results[#sig_results + 1] = result end
        local sig = CodeType.ensure_code_sig(input.sigs, sig_params, sig_results)

        tree_code_input = tree_code_input:tree_code_lower_stmt_body(parts.body or {})
        if tree_code_input:tree_code_state():tree_code_has_current_block() then
            if result == Code.CodeTyVoid then
                tree_code_input = tree_code_input:tree_code_with_result_state(tree_code_input:tree_code_terminate(Code.CodeTermReturn({}), origin_generated("void fallthrough")))
            else
                unsupported(tree_code_input, self, "non-void function without return")
            end
        end

        return Code.CodeFunc(Code.CodeFuncId("fn:" .. parts.name), parts.name, parts.linkage, sig, code_params, tree_code_input:tree_code_state().emission.locals, entry, tree_code_input:tree_code_state().emission.blocks, origin_generated("function " .. parts.name))
    end

    function Tr.Module:lower_tree_module_to_code(opts)
        opts = opts or {}
        local mod_name = self:tree_code_module_name()
        local parts = self:tree_code_module_parts(opts)
        local funcs = {}
        local data = {}
        local globals = {}
        local input = Tr.TreeCodeItemLowerInput(parts.module_facts, parts.sigs, parts.registrations, parts.emission, mod_name, funcs, data, globals)
        for i = 1, #(self.items or {}) do
            self.items[i]:lower_tree_item_to_code(input)
        end
        funcs, data, globals = input.funcs, input.data, input.globals
        for i = 1, #parts.emission.generated_data do data[#data + 1] = parts.emission.generated_data[i] end
        return Code.CodeModule(
            Code.CodeModuleId("module:" .. sanitize(opts.module_id or self:tree_code_module_name())),
            parts.sigs.code_sig_order,
            {}, data, globals, parts.registrations.extern_order, funcs,
            origin_generated("tree_to_code module")
        )
    end

    function Tr.Item:lower_tree_item_to_code(input) end

    function Tr.ItemFunc:lower_tree_item_to_code(input)
        input.funcs[#input.funcs + 1] = self.func:lower_tree_func_to_code(input)
    end

    function Tr.ItemData:lower_tree_item_to_code(input)
        input.data[#input.data + 1] = Code.CodeData(code_data_id(self.data.id), self.data.id.text, Code.CodeLinkageLocal, self.data.size, self.data.align, { Code.CodeDataBytes(0, self.data.bytes) }, origin_generated("data " .. tostring(self.data.id.text)))
    end

    function Tr.ItemConst:lower_tree_item_to_code(input)
        self.c:tree_code_lower_const_item(input)
    end

    function Tr.ConstItem:tree_code_lower_const_item(input)
        input.globals[#input.globals + 1] = self:tree_code_lower_global_to_code(input)
    end

    function Tr.ItemStatic:lower_tree_item_to_code(input)
        self.s:tree_code_lower_static_item(input)
    end

    function Tr.StaticItem:tree_code_lower_static_item(input)
        input.globals[#input.globals + 1] = self:tree_code_lower_global_to_code(input)
    end

    function Tr.ItemExtern:lower_tree_item_to_code(input) end
    function Tr.ItemType:lower_tree_item_to_code(input) end
    function Tr.ItemImport:lower_tree_item_to_code(input) end

    function Tr.ItemRegion:lower_tree_item_to_code(input)
        unsupported(Tr.TreeCodeContractInput(input.module_facts, input.sigs, input.mod_name, Code.CodeFuncId("invalid:region")), self, "region item leaked past frontend expansion/typecheck")
    end

    function Tr.Module:lower_tree_module_with_contracts_to_code(opts)
        return self:lower_tree_module_to_code(opts), self:lower_tree_module_contracts_to_code(opts)
    end

    function api.module(module, opts)
        return module:lower_tree_module_to_code(opts)
    end
    function api.contracts(module, opts)
        return module:lower_tree_module_contracts_to_code(opts)
    end
    function api.module_with_contracts(module, opts)
        return module:lower_tree_module_with_contracts_to_code(opts)
    end

    T._lalin_api_cache.tree_to_code = api
    return api
end

return bind_context
