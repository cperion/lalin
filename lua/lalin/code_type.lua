local asdl = require("lalin.asdl")

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function class_name(x)
    local cls = asdl.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function list_or_single(results)
    if results == nil then return {} end
    if asdl.classof(results) then return { results } end
    return results
end

local function append(list, item)
    local out = {}
    for i = 1, #(list or {}) do out[i] = list[i] end
    out[#out + 1] = item
    return out
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_type ~= nil then return T._lalin_api_cache.code_type end

    local Core = T.LalinCore
    local Ty = T.LalinType
    local Code = T.LalinCode
    local C = T.LalinC
    local CEm = T.LalinCEmit
    local CB = T.LalinCodeBackend
    local Lower = T.LalinLower
    local Graph = T.LalinGraph

    local api = {}

    -- =====================================================================
    -- Pure free functions — no state, no ctx, no mutation
    -- =====================================================================

    local function default_target(opts)
        opts = opts or {}
        local dialect = opts.dialect or C.CBackendC99
        if type(dialect) == "string" then
            if dialect == "c11" then dialect = C.CBackendC11
            elseif dialect == "gnu" or dialect == "gnu99" or dialect == "gnuc" then dialect = C.CBackendGnuC
            elseif dialect == "clang" then dialect = C.CBackendClangC
            else dialect = C.CBackendC99 end
        end
        local platform = opts.platform or C.CBackendHostedNative
        if type(platform) == "string" then
            if platform == "freestanding" then platform = C.CBackendFreestanding
            elseif platform == "wasm" or platform == "wasm-capable" then platform = C.CBackendWasmCapable
            elseif platform == "embedded" then platform = C.CBackendEmbedded
            else platform = C.CBackendHostedNative end
        end
        local endian = opts.endian or C.CBackendLittleEndian
        if type(endian) == "string" then
            endian = (endian == "big" or endian == "be") and C.CBackendBigEndian or C.CBackendLittleEndian
        end
        return C.CBackendTarget(
            dialect,
            platform,
            opts.pointer_bits or 64,
            opts.index_bits or opts.pointer_bits or 64,
            endian,
            opts.hosted ~= false
        )
    end

    local function normalize_target(target_or_opts)
        if asdl.classof(target_or_opts) == C.CBackendTarget then return target_or_opts end
        return default_target(target_or_opts)
    end

    local function target_facts(target_or_opts)
        local target = normalize_target(target_or_opts)
        return {
            target = target,
            pointer_bits = target.pointer_bits,
            index_bits = target.index_bits,
            endian = target.endian,
            hosted = target.hosted,
        }
    end

    local function scalar_to_code(scalar)
        if scalar == Core.ScalarVoid then return Code.CodeTyVoid end
        if scalar == Core.ScalarBool then return Code.CodeTyBool8 end
        if scalar == Core.ScalarRawPtr then return Code.CodeTyDataPtr(nil) end
        if scalar == Core.ScalarIndex then return Code.CodeTyIndex end
        if scalar == Core.ScalarI8 then return Code.CodeTyInt(8, Code.CodeSigned) end
        if scalar == Core.ScalarI16 then return Code.CodeTyInt(16, Code.CodeSigned) end
        if scalar == Core.ScalarI32 then return Code.CodeTyInt(32, Code.CodeSigned) end
        if scalar == Core.ScalarI64 then return Code.CodeTyInt(64, Code.CodeSigned) end
        if scalar == Core.ScalarU8 then return Code.CodeTyInt(8, Code.CodeUnsigned) end
        if scalar == Core.ScalarU16 then return Code.CodeTyInt(16, Code.CodeUnsigned) end
        if scalar == Core.ScalarU32 then return Code.CodeTyInt(32, Code.CodeUnsigned) end
        if scalar == Core.ScalarU64 then return Code.CodeTyInt(64, Code.CodeUnsigned) end
        if scalar == Core.ScalarF32 then return Code.CodeTyFloat(32) end
        if scalar == Core.ScalarF64 then return Code.CodeTyFloat(64) end
        error("code_type: unsupported scalar " .. class_name(scalar), 2)
    end

    local function int_scalar(bits, signedness)
        if signedness == Code.CodeSigned then
            if bits == 8 then return Core.ScalarI8 end
            if bits == 16 then return Core.ScalarI16 end
            if bits == 32 then return Core.ScalarI32 end
            if bits == 64 then return Core.ScalarI64 end
        elseif signedness == Code.CodeUnsigned then
            if bits == 8 then return Core.ScalarU8 end
            if bits == 16 then return Core.ScalarU16 end
            if bits == 32 then return Core.ScalarU32 end
            if bits == 64 then return Core.ScalarU64 end
        end
        error("code_type: unsupported integer width/signedness " .. tostring(bits), 3)
    end

    local function float_scalar(bits)
        if bits == 32 then return Core.ScalarF32 end
        if bits == 64 then return Core.ScalarF64 end
        error("code_type: unsupported float width " .. tostring(bits), 3)
    end

    local function named_type_name(ref, module_name)
        local rcls = asdl.classof(ref)
        if rcls == Ty.TypeRefGlobal then return ref.module_name, ref.type_name end
        if rcls == Ty.TypeRefLocal then return "local", ref.sym.name end
        if rcls == Ty.TypeRefPath and #ref.path.parts > 0 then return (module_name or ""), ref.path.parts[#ref.path.parts].text end
        error("code_type: unresolved named type " .. class_name(ref), 3)
    end

    local function canonical_named_source_ty(ty, module_name, type_name)
        local ref = ty and ty.ref
        if asdl.classof(ref) == Ty.TypeRefPath and module_name ~= nil and module_name ~= "" then
            return Ty.TNamed(Ty.TypeRefGlobal(module_name, type_name))
        end
        return ty
    end

    local code_type_key

    local function normalize_code_results(results)
        results = list_or_single(results)
        if #results == 1 and results[1] == Code.CodeTyVoid then return {} end
        return results
    end

    local function lalin_type_key(ty)
        local cls = asdl.classof(ty)
        if cls == Ty.THandle then
            local ref = ty.ref
            local rcls = asdl.classof(ref)
            if rcls == Ty.TypeRefGlobal then return "handle_" .. sanitize(ref.module_name) .. "_" .. sanitize(ref.type_name) end
            if rcls == Ty.TypeRefLocal then return "handle_local_" .. sanitize(ref.sym.key or ref.sym.name) end
            if rcls == Ty.TypeRefPath then
                local parts = {}
                for i = 1, #ref.path.parts do parts[#parts + 1] = ref.path.parts[i].text end
                return "handle_path_" .. sanitize(table.concat(parts, "_"))
            end
        elseif cls == Ty.TNamed then
            local ref = ty.ref
            local rcls = asdl.classof(ref)
            if rcls == Ty.TypeRefGlobal then return "named_" .. sanitize(ref.module_name) .. "_" .. sanitize(ref.type_name) end
            if rcls == Ty.TypeRefLocal then return "named_local_" .. sanitize(ref.sym.key or ref.sym.name) end
            if rcls == Ty.TypeRefPath then
                local parts = {}
                for i = 1, #ref.path.parts do parts[#parts + 1] = ref.path.parts[i].text end
                return "named_path_" .. sanitize(table.concat(parts, "_"))
            end
        end
        return sanitize(class_name(ty))
    end

    code_type_key = function(ty)
        if ty == Code.CodeTyVoid then return "void" end
        if ty == Code.CodeTyBool8 then return "bool8" end
        if ty == Code.CodeTyIndex then return "index" end
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyInt then return (ty.signedness == Code.CodeSigned and "i" or "u") .. tostring(ty.bits) end
        if cls == Code.CodeTyFloat then return "f" .. tostring(ty.bits) end
        if cls == Code.CodeTyDataPtr then return "ptr_" .. (ty.pointee and code_type_key(ty.pointee) or "opaque") end
        if cls == Code.CodeTyCodePtr then return "codeptr_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyNamed then return "named_" .. sanitize(ty.module_name) .. "_" .. sanitize(ty.type_name) end
        if cls == Code.CodeTyArray then return "arr_" .. tostring(ty.count) .. "_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTySlice then return "slice_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTyView then return "view_" .. code_type_key(ty.elem) end
        if cls == Code.CodeTyByteSpan or ty == Code.CodeTyByteSpan then return "bytespan" end
        if cls == Code.CodeTyHandle then return "handle_" .. lalin_type_key(ty.source_ty) .. "_" .. code_type_key(ty.repr) end
        if cls == Code.CodeTyLease then return "lease_" .. code_type_key(ty.base) end
        if cls == Code.CodeTyClosure then return "closure_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyImportedC then return "ctype_" .. sanitize(ty.id.module_name) .. "_" .. sanitize(ty.id.spelling) end
        if cls == Code.CodeTyImportedCFuncPtr then return "cfuncptr_" .. sanitize(ty.sig.text) end
        if cls == Code.CodeTyVector then return "vec_" .. tostring(ty.lanes) .. "_" .. code_type_key(ty.elem) end
        error("code_type: unsupported CodeType " .. class_name(ty), 2)
    end

    local function code_sig_id(params, results)
        results = normalize_code_results(results)
        local parts = { "codesig" }
        for i = 1, #(params or {}) do parts[#parts + 1] = code_type_key(params[i]) end
        parts[#parts + 1] = "to"
        if #results == 0 then
            parts[#parts + 1] = "void"
        else
            for i = 1, #results do parts[#parts + 1] = code_type_key(results[i]) end
        end
        return Code.CodeSigId(table.concat(parts, "_"))
    end


    local function c_backend_sig_id(code_sig_id_value)
        return C.CBackendFuncSigId(code_sig_id_value.text)
    end

    local function c_backend_closure_sig_id(code_sig_id_value)
        return C.CBackendFuncSigId("closure_" .. code_sig_id_value.text)
    end

    -- =====================================================================
    -- Typed CodeSig requirement projection for tree→Code lowering
    -- =====================================================================

    local function sig_state_lookup(sig_state, id)
        for _, entry in ipairs(sig_state.code_sigs or {}) do
            if entry.sig_id == id then return entry.sig end
        end
        return nil
    end

    local function sig_state_has_requirement(sig_state, sig, requirement)
        for _, entry in ipairs(sig_state.code_sigs or {}) do
            if entry.sig_id == sig.id and entry.requirement == requirement then return true end
        end
        return false
    end

    local function collect_sig_requirement(requirement, sig_state, sig)
        local entries = sig_state.code_sigs
        local order = sig_state.code_sig_order
        if not sig_state_has_requirement(sig_state, sig, requirement) then
            entries = append(entries, sig_state:tree_code_sig_entry(sig, requirement))
        end
        if sig_state_lookup(sig_state, sig.id) == nil then order = append(order, sig) end
        return sig_state:tree_code_with_sig_projection(entries, order)
    end

    local TreeLowerSchema = T.LalinTreeLower
    if TreeLowerSchema ~= nil then
        function TreeLowerSchema.TreeLowerModuleSigState:tree_code_sig_entry(sig, requirement)
            return TreeLowerSchema.TreeLowerSigEntry(sig.id, sig, requirement)
        end
        function TreeLowerSchema.TreeLowerModuleSigState:tree_code_with_sig_projection(entries, order)
            return TreeLowerSchema.TreeLowerModuleSigState(self.module_name, entries, order)
        end
        function TreeLowerSchema.TreeLowerModuleSigState:tree_code_helper_sig_requirement()
            return TreeLowerSchema.TreeLowerHelperSigRequirement
        end
        function TreeLowerSchema.TreeLowerFunctionSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeLowerSchema.TreeLowerExternSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeLowerSchema.TreeLowerDirectCallSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeLowerSchema.TreeLowerIndirectCallSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeLowerSchema.TreeLowerClosureSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeLowerSchema.TreeLowerHelperSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
    end

    local TreeCode = T.LalinTreeCode
    if TreeCode ~= nil then
        function TreeCode.TreeCodeModuleSigState:tree_code_sig_entry(sig, requirement)
            return TreeCode.TreeCodeSigEntry(sig.id, sig, requirement)
        end
        function TreeCode.TreeCodeModuleSigState:tree_code_with_sig_projection(entries, order)
            return TreeCode.TreeCodeModuleSigState(self.module_name, entries, order)
        end
        function TreeCode.TreeCodeModuleSigState:tree_code_helper_sig_requirement()
            return TreeCode.TreeCodeHelperSigRequirement
        end
        function TreeCode.TreeCodeFunctionSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeCode.TreeCodeExternSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeCode.TreeCodeDirectCallSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeCode.TreeCodeIndirectCallSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeCode.TreeCodeClosureSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
        function TreeCode.TreeCodeHelperSigRequirement:tree_lower_collect_code_sig(sig_state, sig) return collect_sig_requirement(self, sig_state, sig) end
    end

    -- =====================================================================
    -- CEmitMachine — typed machine for C emission phase only
    -- =====================================================================

    function CEm.CEmitMachine.empty(spine)
        return CEm.CEmitMachine(spine, {}, {}, {}, {})
    end

    function CEm.CEmitMachine.dummy(target)
        target = target or C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
        local spine = Lower.LowerBackSpine(
            Code.CodeModule(Code.CodeModuleId("_dummy"), {}, {}, {}, {}, {}, {}, Code.CodeOriginUnknown),
            Graph.CodeGraph(Code.CodeModuleId("_dummy"), {}),
            target
        )
        return CEm.CEmitMachine(spine, {}, {}, {}, {})
    end

    -- Look up a code sig from the spine's CodeModule (not from CEmitMachine).
    local function lookup_code_sig(spine, key)
        local mod = spine and spine.code_module
        if mod == nil then return nil end
        for _, sig in ipairs(mod.sigs or {}) do
            if sig.id.text == key then return sig end
        end
        return nil
    end

    function CEm.CEmitMachine:c_sig_for_key(key)
        for _, entry in ipairs(self.c_sigs or {}) do
            if entry.c_key == key then return entry.csig end
        end
        return nil
    end

    function CEm.CEmitMachine:with_c_sig(c_key, csig)
        if self:c_sig_for_key(c_key) ~= nil then return self end
        local new_c_sigs = append(self.c_sigs, CEm.CEmitCSigEntry(c_key, csig))
        local new_c_order = append(self.c_sig_order, csig)
        return CEm.CEmitMachine(self.spine, new_c_sigs, new_c_order, self.helpers, self.helper_order)
    end

    function CEm.CEmitMachine:with_helper(entry)
        local key = entry.helper_key
        for _, existing in ipairs(self.helpers or {}) do
            if existing.helper_key == key then return self end
        end
        local new_helpers = append(self.helpers, entry)
        local new_order = append(self.helper_order, entry)
        return CEm.CEmitMachine(self.spine, self.c_sigs, self.c_sig_order, new_helpers, new_order)
    end

    function CEm.CEmitMachine:helper_for_id(id_text)
        for _, entry in ipairs(self.helpers or {}) do
            if entry.helper_key == id_text then return entry.helper end
        end
        return nil
    end

    -- =====================================================================
    -- State-threading operations
    -- =====================================================================

    local function ensure_code_sig_requirement_on(sig_state, params, results, requirement)
        results = normalize_code_results(results)
        local id = code_sig_id(params or {}, results)
        local sig = Code.CodeSig(id, params or {}, results)
        return id, requirement:tree_lower_collect_code_sig(sig_state, sig)
    end

    local function ensure_code_sig_on(sig_state, params, results)
        return ensure_code_sig_requirement_on(sig_state, params, results, sig_state:tree_code_helper_sig_requirement())
    end

    local type_to_code_on
    type_to_code_on = function(sig_state, ty)
        local cls = asdl.classof(ty)
        if cls == Ty.TScalar then
            return scalar_to_code(ty.scalar), sig_state
        elseif cls == Ty.TPtr then
            local elem_ty, ss = type_to_code_on(sig_state, ty.elem)
            return Code.CodeTyDataPtr(elem_ty), ss
        elseif cls == Ty.TArray then
            if asdl.classof(ty.count) ~= Ty.ArrayLenConst then
                error("code_type: dynamic array length reached CodeType projection; typechecking must reject ArrayLenExpr before backend lowering", 2)
            end
            local elem_ty, ss = type_to_code_on(sig_state, ty.elem)
            return Code.CodeTyArray(elem_ty, ty.count.count), ss
        elseif cls == Ty.TSlice then
            local elem_ty, ss = type_to_code_on(sig_state, ty.elem)
            return Code.CodeTySlice(elem_ty), ss
        elseif cls == Ty.TView then
            local elem_ty, ss = type_to_code_on(sig_state, ty.elem)
            return Code.CodeTyView(elem_ty), ss
        elseif cls == Ty.TLease then
            local base_ty, ss = type_to_code_on(sig_state, ty.base)
            return Code.CodeTyLease(base_ty, ty), ss
        elseif cls == Ty.TOwned then
            return type_to_code_on(sig_state, ty.base)
        elseif cls == Ty.TAccess then
            return type_to_code_on(sig_state, ty.base)
        elseif cls == Ty.THandle then
            local rcls = asdl.classof(ty.repr)
            if rcls == Ty.HandleReprScalar then
                return Code.CodeTyHandle(scalar_to_code(ty.repr.scalar), ty), sig_state
            end
            error("code_type: unsupported handle repr " .. class_name(ty.repr), 2)
        elseif cls == Ty.TFunc then
            local params = {}
            local ss = sig_state
            for i = 1, #ty.params do
                params[i], ss = type_to_code_on(ss, ty.params[i])
            end
            local result, ss = type_to_code_on(ss, ty.result)
            local sig_id, ss = ensure_code_sig_on(ss, params, { result })
            return Code.CodeTyCodePtr(sig_id), ss
        elseif cls == Ty.TClosure then
            local params = {}
            local ss = sig_state
            for i = 1, #ty.params do
                params[i], ss = type_to_code_on(ss, ty.params[i])
            end
            local result, ss = type_to_code_on(ss, ty.result)
            local sig_id, ss = ensure_code_sig_on(ss, params, { result })
            return Code.CodeTyClosure(sig_id), ss
        elseif cls == Ty.TNamed then
            local module_name, type_name = named_type_name(ty.ref, sig_state.module_name)
            return Code.CodeTyNamed(module_name, type_name, canonical_named_source_ty(ty, module_name, type_name)), sig_state
        elseif cls == Ty.TCType then
            return Code.CodeTyImportedC(ty.id), sig_state
        elseif cls == Ty.TCFuncPtr then
            return Code.CodeTyImportedCFuncPtr(ty.sig), sig_state
        end
        error("code_type: unsupported LalinType " .. class_name(ty), 2)
    end

    local function code_sig_result_to_c(machine, sig)
        local results = sig.results or {}
        if #results == 0 then return C.CBackendVoid, machine end
        if #results == 1 then return code_type_to_c_on(machine, results[1]) end
        error("code_type: C backend cannot spell multi-result CodeSig " .. sig.id.text, 3)
    end

    local function ensure_c_backend_sig_on(machine, sig_id)
        local id = c_backend_sig_id(sig_id)
        local sig = lookup_code_sig(machine.spine, sig_id.text)
        if sig and machine:c_sig_for_key(id.text) == nil then
            local params = {}
            local m = machine
            for i = 1, #sig.params do
                params[i], m = code_type_to_c_on(m, sig.params[i])
            end
            local result, m = code_sig_result_to_c(m, sig)
            local c_sig = C.CBackendFuncSig(id, params, result)
            return id, m:with_c_sig(id.text, c_sig)
        end
        return id, machine
    end

    local function ensure_c_backend_closure_sig_on(machine, sig_id)
        local id = c_backend_closure_sig_id(sig_id)
        local sig = lookup_code_sig(machine.spine, sig_id.text)
        if sig and machine:c_sig_for_key(id.text) == nil then
            local params = { C.CBackendDataPtr(nil) }
            local m = machine
            for i = 1, #sig.params do
                params[#params + 1], m = code_type_to_c_on(m, sig.params[i])
            end
            local result, m = code_sig_result_to_c(m, sig)
            local c_sig = C.CBackendFuncSig(id, params, result)
            return id, m:with_c_sig(id.text, c_sig)
        end
        return id, machine
    end

    code_type_to_c_on = function(machine, ty)
        if ty == Code.CodeTyVoid then return C.CBackendVoid, machine end
        if ty == Code.CodeTyBool8 then return C.CBackendBool8, machine end
        if ty == Code.CodeTyIndex then return C.CBackendIndex, machine end
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyInt then return C.CBackendScalar(int_scalar(ty.bits, ty.signedness)), machine end
        if cls == Code.CodeTyFloat then return C.CBackendScalar(float_scalar(ty.bits)), machine end
        if cls == Code.CodeTyDataPtr then
            if ty.pointee then
                local pointee, m = code_type_to_c_on(machine, ty.pointee)
                return C.CBackendDataPtr(pointee), m
            end
            return C.CBackendDataPtr(nil), machine
        end
        if cls == Code.CodeTyCodePtr then
            local sig_id, m = ensure_c_backend_sig_on(machine, ty.sig)
            return C.CBackendCodePtr(sig_id), m
        end
        if cls == Code.CodeTyNamed then return C.CBackendNamed(C.CTypeId(ty.module_name, ty.type_name)), machine end
        if cls == Code.CodeTyArray then
            local elem, m = code_type_to_c_on(machine, ty.elem)
            return C.CBackendArray(elem, ty.count), m
        end
        if cls == Code.CodeTySlice then
            local elem, m = code_type_to_c_on(machine, ty.elem)
            return C.CBackendSliceDescriptor(elem), m
        end
        if cls == Code.CodeTyByteSpan or ty == Code.CodeTyByteSpan then return C.CBackendByteSpanDescriptor, machine end
        if cls == Code.CodeTyView then
            local elem, m = code_type_to_c_on(machine, ty.elem)
            return C.CBackendViewDescriptor(elem), m
        end
        if cls == Code.CodeTyHandle then return code_type_to_c_on(machine, ty.repr) end
        if cls == Code.CodeTyLease then return code_type_to_c_on(machine, ty.base) end
        if cls == Code.CodeTyClosure then
            local sig_id, m = ensure_c_backend_closure_sig_on(machine, ty.sig)
            return C.CBackendClosureDescriptor(sig_id, C.CBackendDataPtr(nil)), m
        end
        if cls == Code.CodeTyImportedC then return C.CBackendNamed(ty.id), machine end
        if cls == Code.CodeTyImportedCFuncPtr then return C.CBackendImportedCodePtr(ty.sig), machine end
        if cls == Code.CodeTyVector then
            local elem, m = code_type_to_c_on(machine, ty.elem)
            return C.CBackendVector(elem, ty.lanes), m
        end
        error("code_type: unsupported CodeType for C backend " .. class_name(ty), 2)
    end

    local function type_to_c_on(sig_state, ty)
        local code_ty, ss = type_to_code_on(sig_state, ty)
        -- C conversion needs a CEmitMachine; create a dummy for simple conversions
        return code_type_to_c_on(CEm.CEmitMachine.dummy(), code_ty)
    end

    local function ensure_type_sig_on(sig_state, params, result)
        local code_params = {}
        local ss = sig_state
        for i = 1, #(params or {}) do
            code_params[i], ss = type_to_code_on(ss, params[i])
        end
        local code_result, ss = type_to_code_on(ss, result)
        return ensure_code_sig_on(ss, code_params, { code_result })
    end

    -- Convenience: single-call code_type_to_c without accumulating state.
    -- For callers that just need a type conversion without sig accumulation.
    api.code_type_to_c_simple = function(ty)
        return select(1, code_type_to_c_on(CEm.CEmitMachine({}, {}, {}, {}), ty))
    end

    api.default_target = default_target
    api.normalize_target = normalize_target
    api.target_facts = target_facts
    api.scalar_to_code = scalar_to_code
    api.code_type_key = code_type_key
    api.code_sig_id = code_sig_id
    api.c_backend_sig_id = c_backend_sig_id
    api.c_backend_closure_sig_id = c_backend_closure_sig_id

    api.type_to_code = function(sig_state, ty)
        return type_to_code_on(sig_state, ty)
    end

    api.ensure_code_sig = function(sig_state, params, results)
        return ensure_code_sig_on(sig_state, params, results)
    end

    api.ensure_code_sig_requirement = function(sig_state, params, results, requirement)
        return ensure_code_sig_requirement_on(sig_state, params, results, requirement)
    end

    api.ensure_type_sig = function(sig_state, params, result)
        return ensure_type_sig_on(sig_state, params, result)
    end

    api.ensure_type_sig_requirement = function(sig_state, params, result, requirement)
        local code_params = {}
        local ss = sig_state
        for i = 1, #(params or {}) do code_params[i], ss = type_to_code_on(ss, params[i]) end
        local code_result
        code_result, ss = type_to_code_on(ss, result)
        return ensure_code_sig_requirement_on(ss, code_params, { code_result }, requirement)
    end

    api.ensure_c_backend_sig = function(machine, sig_id)
        return ensure_c_backend_sig_on(machine, sig_id)
    end

    api.ensure_c_backend_closure_sig = function(machine, sig_id)
        return ensure_c_backend_closure_sig_on(machine, sig_id)
    end

    api.code_type_to_c = function(machine, ty)
        return code_type_to_c_on(machine, ty)
    end

    api.type_to_c = function(sig_state, ty)
        return type_to_c_on(sig_state, ty)
    end

    T._lalin_api_cache.code_type = api
    return api
end

local function self_init()
  if package.loaded["lalin.code_type._api"] then return package.loaded["lalin.code_type._api"] end
  local T = require("lalin.schema_v2")
  local api = bind_context(T)
  package.loaded["lalin.code_type._api"] = api
  return api
end

-- Return a callable that auto-initializes when called with no args
return setmetatable({}, {
  __index = function(_, k) return self_init()[k] end,
  __call = function(_, T)
    if T ~= nil then
      local api = bind_context(T)
      package.loaded["lalin.code_type._api"] = api
      return api
    end
    return self_init()
  end,
})
