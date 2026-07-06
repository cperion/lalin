local asdl = require("lalin.asdl")

local function class_name(x)
    local cls = asdl.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function is_power_of_two(n)
    if type(n) ~= "number" or n < 1 or n % 1 ~= 0 then return false end
    while n > 1 do
        if n % 2 ~= 0 then return false end
        n = n / 2
    end
    return true
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_validate ~= nil then return T._lalin_api_cache.code_validate end

    local Code = T.LalinCode

    local api = {}

    -- Machine: wraps the validation accumulator as an immutable wrapper.
    -- Each "mutation" returns a new Machine with the accumulated changes.
    local Machine = {}
    Machine.__index = Machine

    function Machine.new(sigs, data, globals, funcs, externs)
        return setmetatable({
            _issues = {},
            _relocs = {},
            _sigs = sigs,
            _data = data,
            _globals = globals,
            _funcs = funcs,
            _externs = externs,
        }, Machine)
    end

    function Machine:issues() return self._issues end

    function Machine:with_issue(issue)
        local m = Machine.new(self._sigs, self._data, self._globals, self._funcs, self._externs)
        for i = 1, #self._issues do m._issues[i] = self._issues[i] end
        m._issues[#m._issues + 1] = issue
        for k, v in pairs(self._relocs) do m._relocs[k] = v end
        return m
    end

    function Machine:sig(id) return self._sigs[id.text] end
    function Machine:data(id) return self._data[id.text] end
    function Machine:global(id) return self._globals[id.text] end
    function Machine:func(id) return self._funcs[id.text] end
    function Machine:extern(id) return self._externs[id.text] end

    function Machine:has_reloc(reloc_id) return self._relocs[reloc_id.text] end

    function Machine:with_reloc(reloc)
        local m = Machine.new(self._sigs, self._data, self._globals, self._funcs, self._externs)
        for i = 1, #self._issues do m._issues[i] = self._issues[i] end
        for k, v in pairs(self._relocs) do m._relocs[k] = v end
        m._relocs[reloc.id.text] = true
        return m
    end

    local function type_eq(a, b, seen)
        if a == b then return true end
        local ac, bc = asdl.classof(a), asdl.classof(b)
        if ac == Code.CodeTyLease then return type_eq(a.base, b, seen) end
        if bc == Code.CodeTyLease then return type_eq(a, b.base, seen) end
        if ac ~= bc then
            if ac == Code.CodeTyDataPtr and bc == Code.CodeTyDataPtr then return a.pointee == nil or b.pointee == nil end
            return false
        end
        if ac == Code.CodeTyDataPtr and (a.pointee == nil or b.pointee == nil) then return true end
        if ac == nil then return a == b end
        seen = seen or {}
        local key = tostring(a) .. "|" .. tostring(b)
        if seen[key] then return true end
        seen[key] = true
        local fields = asdl.fields(ac) or {}
        for i = 1, #fields do
            local name = fields[i].name
            local av, bv = a[name], b[name]
            if type(av) == "table" and asdl.classof(av) == nil then
                if type(bv) ~= "table" or #av ~= #bv then return false end
                for j = 1, #av do if not type_eq(av[j], bv[j], seen) then return false end end
            elseif type(av) == "table" and asdl.classof(av) ~= nil then
                if not type_eq(av, bv, seen) then return false end
            else
                if av ~= bv then return false end
            end
        end
        return true
    end

    local function is_bool(ty)
        return ty == Code.CodeTyBool8
    end

    local function is_integer_like(ty)
        local cls = asdl.classof(ty)
        return ty == Code.CodeTyIndex or cls == Code.CodeTyInt
    end

    local function type_uses_code_sig(ty, machine)
        local cls = asdl.classof(ty)
        if cls == Code.CodeTyCodePtr or cls == Code.CodeTyClosure then
            if machine:sig(ty.sig) == nil then machine = machine:with_issue(Code.CodeIssueMissingSig(ty.sig)) end
        elseif cls == Code.CodeTyDataPtr and ty.pointee ~= nil then
            machine = type_uses_code_sig(ty.pointee, machine)
        elseif cls == Code.CodeTyArray or cls == Code.CodeTySlice or cls == Code.CodeTyView or cls == Code.CodeTyVector then
            machine = type_uses_code_sig(ty.elem, machine)
        elseif cls == Code.CodeTyLease then
            machine = type_uses_code_sig(ty.base, machine)
        end
        return machine
    end

    local function expect_type(machine, site, expected, actual)
        if expected ~= nil and actual ~= nil and not type_eq(expected, actual) then
            return machine:with_issue(Code.CodeIssueTypeMismatch(site, expected, actual))
        end
        return machine
    end

    local function expect_bool(machine, site, actual)
        if actual ~= nil and not is_bool(actual) then
            return machine:with_issue(Code.CodeIssueTypeMismatch(site, Code.CodeTyBool8, actual))
        end
        return machine
    end

    local function check_align(machine, site, align, access)
        if align ~= nil and not is_power_of_two(align) then
            if access ~= nil then
                return machine:with_issue(Code.CodeIssueInvalidMemoryAccess(site, access))
            else
                return machine:with_issue(Code.CodeIssueUnsupportedSource(site, "invalid alignment " .. tostring(align)))
            end
        end
        return machine
    end

    local function global_ref_exists(machine, ref)
        local cls = asdl.classof(ref)
        local result
        if cls == Code.CodeGlobalRefData then
            result = machine:data(ref.data)
            if result == nil then machine = machine:with_issue(Code.CodeIssueMissingData(ref.data)) end
        elseif cls == Code.CodeGlobalRefGlobal then
            result = machine:global(ref.global)
            if result == nil then machine = machine:with_issue(Code.CodeIssueMissingGlobal(ref.global)) end
        elseif cls == Code.CodeGlobalRefFunc then
            result = machine:func(ref.func)
            if result == nil then machine = machine:with_issue(Code.CodeIssueMissingFunc(ref.func)) end
        elseif cls == Code.CodeGlobalRefExtern then
            result = machine:extern(ref["extern"])
            if result == nil then machine = machine:with_issue(Code.CodeIssueMissingExtern(ref["extern"])) end
        end
        return machine, result
    end

    local function check_sig_ref(machine, sig_id)
        local sig = sig_id and machine:sig(sig_id) or nil
        if sig_id and sig == nil then machine = machine:with_issue(Code.CodeIssueMissingSig(sig_id)) end
        return machine, sig
    end

    local function check_memory_access(machine, site, access, expected_mode)
        if access == nil then return machine end
        machine = check_align(machine, site, access.align, access)
        if expected_mode == "read" and access.effect ~= Code.CodeMemoryRead and access.effect ~= Code.CodeMemoryReadWrite then
            machine = machine:with_issue(Code.CodeIssueInvalidMemoryAccess(site, access))
        elseif expected_mode == "write" and access.effect ~= Code.CodeMemoryWrite and access.effect ~= Code.CodeMemoryReadWrite then
            machine = machine:with_issue(Code.CodeIssueInvalidMemoryAccess(site, access))
        end
        return type_uses_code_sig(access.ty, machine)
    end

    local function scalar_size(bits)
        if bits == 1 or bits == 8 then return 1 end
        if bits == 16 then return 2 end
        if bits == 32 then return 4 end
        if bits == 64 then return 8 end
        return nil
    end

    local function type_size(ty)
        local cls = asdl.classof(ty)
        if ty == Code.CodeTyBool8 then return 1 end
        if ty == Code.CodeTyIndex then return 8 end
        if cls == Code.CodeTyInt or cls == Code.CodeTyFloat then return scalar_size(ty.bits) end
        if cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr or cls == Code.CodeTyClosure or cls == Code.CodeTyImportedCFuncPtr then return 8 end
        if cls == Code.CodeTyArray then
            local elem_size = type_size(ty.elem)
            if elem_size ~= nil and type(ty.count) == "number" then return elem_size * ty.count end
        end
        if cls == Code.CodeTyHandle or cls == Code.CodeTyLease then return type_size(ty.repr or ty.base) end
        return nil
    end

    local function data_init_extent(init)
        local cls = asdl.classof(init)
        if cls == Code.CodeDataZero then return init.offset, init.size end
        if cls == Code.CodeDataBytes then return init.offset, #init.bytes end
        if cls == Code.CodeDataScalar then return init.offset, type_size(init.ty) or 0 end
        if cls == Code.CodeDataReloc then return init.reloc.offset, 8 end
        return 0, 0
    end

    local function check_init_bounds(machine, site, container_id, size, init)
        local off, n = data_init_extent(init)
        if type(off) ~= "number" or off < 0 or type(n) ~= "number" or n < 0 or (size ~= nil and off + n > size) then
            return machine:with_issue(Code.CodeIssueUnsupportedSource(site .. ":" .. container_id.text, "data initializer out of bounds"))
        end
        return machine
    end

    local function check_reloc(machine, reloc)
        if reloc == nil then return machine end
        if machine:has_reloc(reloc.id) then
            machine = machine:with_issue(Code.CodeIssueInvalidReloc(reloc, "duplicate reloc id"))
        end
        machine = machine:with_reloc(reloc)
        if type(reloc.offset) ~= "number" or reloc.offset < 0 or reloc.offset % 1 ~= 0 then
            machine = machine:with_issue(Code.CodeIssueInvalidReloc(reloc, "invalid relocation offset"))
        end
        machine, _ = global_ref_exists(machine, reloc.target)
        return machine
    end

    local function value_type(fctx, machine, value)
        local ty = value and fctx.values[value.text]
        if value ~= nil and ty == nil then machine = machine:with_issue(Code.CodeIssueMissingValue(value)) end
        return machine, ty
    end

    local function view_elem_type(fctx, machine, site, view)
        local vty
        machine, vty = value_type(fctx, machine, view)
        local cls = asdl.classof(vty)
        if cls == Code.CodeTyLease then
            vty = vty.base
            cls = asdl.classof(vty)
        end
        if vty ~= nil and cls ~= Code.CodeTyView then
            machine = machine:with_issue(Code.CodeIssueTypeMismatch(site, Code.CodeTyView(Code.CodeTyVoid), vty))
            return machine, nil
        end
        return machine, vty and vty.elem or nil
    end

    local function slice_elem_type(fctx, machine, site, slice)
        local sty
        machine, sty = value_type(fctx, machine, slice)
        local cls = asdl.classof(sty)
        if cls == Code.CodeTyLease then
            sty = sty.base
            cls = asdl.classof(sty)
        end
        if sty ~= nil and cls ~= Code.CodeTySlice then
            machine = machine:with_issue(Code.CodeIssueTypeMismatch(site, Code.CodeTySlice(Code.CodeTyVoid), sty))
            return machine, nil
        end
        return machine, sty and sty.elem or nil
    end

    local function byte_span_type(fctx, machine, site, span)
        local sty
        machine, sty = value_type(fctx, machine, span)
        local cls = asdl.classof(sty)
        if cls == Code.CodeTyLease then
            sty = sty.base
            cls = asdl.classof(sty)
        end
        if sty ~= nil and sty ~= Code.CodeTyByteSpan and cls ~= Code.CodeTyByteSpan then
            machine = machine:with_issue(Code.CodeIssueTypeMismatch(site, Code.CodeTyByteSpan, sty))
            return machine, false
        end
        return machine, true
    end

    local place_type
    place_type = function(machine, fctx, place, site)
        local cls = asdl.classof(place)
        if cls == Code.CodePlaceLocal then
            local local_id = place.local_id
            local local_ = fctx.locals[local_id.text]
            if local_ == nil then
                machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "missing local " .. local_id.text))
            else
                machine = expect_type(machine, site .. ":local", local_.ty, place.ty)
            end
            return machine, place.ty
        elseif cls == Code.CodePlaceGlobal then
            local global = machine:global(place.global)
            if global == nil then machine = machine:with_issue(Code.CodeIssueMissingGlobal(place.global))
            else machine = expect_type(machine, site .. ":global", global.ty, place.ty) end
            return machine, place.ty
        elseif cls == Code.CodePlaceData then
            if machine:data(place.data) == nil then machine = machine:with_issue(Code.CodeIssueMissingData(place.data)) end
            return machine, place.ty
        elseif cls == Code.CodePlaceDeref then
            local aty
            machine, aty = value_type(fctx, machine, place.addr)
            local ac = asdl.classof(aty)
            if aty ~= nil and ac ~= Code.CodeTyDataPtr then
                if ac == Code.CodeTyCodePtr then machine = machine:with_issue(Code.CodeIssueDataCodePointerConfusion(site .. ":deref", aty))
                else machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":deref", Code.CodeTyDataPtr(nil), aty)) end
            end
            machine = check_align(machine, site .. ":deref", place.align, nil)
            return machine, place.ty
        elseif cls == Code.CodePlaceField then
            machine, _ = place_type(machine, fctx, place.base, site .. ":field.base")
            machine = check_align(machine, site .. ":field", place.align, nil)
            if place.offset < 0 or (place.size ~= nil and place.size < 0) then machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "invalid field byte range")) end
            return machine, place.ty
        elseif cls == Code.CodePlaceIndex then
            machine, _ = place_type(machine, fctx, place.base, site .. ":index.base")
            local ity
            machine, ity = value_type(fctx, machine, place.index)
            if ity ~= nil and not is_integer_like(ity) then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":index", Code.CodeTyIndex, ity)) end
            if type(place.elem_size) ~= "number" or place.elem_size <= 0 then machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "invalid element size")) end
            return machine, place.ty
        elseif cls == Code.CodePlaceBytes then
            local bty
            machine, bty = value_type(fctx, machine, place.base)
            local bc = asdl.classof(bty)
            if bty ~= nil and bc ~= Code.CodeTyDataPtr then
                if bc == Code.CodeTyCodePtr then machine = machine:with_issue(Code.CodeIssueDataCodePointerConfusion(site .. ":bytes", bty))
                else machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":bytes", Code.CodeTyDataPtr(nil), bty)) end
            end
            machine = check_align(machine, site .. ":bytes", place.align, nil)
            if place.offset < 0 or place.size < 0 then machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "invalid byte place range")) end
            return machine, place.ty
        end
        machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "unsupported place " .. class_name(place)))
        return machine, nil
    end

    local function check_transfer(machine, fctx, site, dest, args)
        local block = fctx.blocks[dest.text]
        if block == nil then machine = machine:with_issue(Code.CodeIssueMissingBlock(dest)); return machine end
        if #args ~= #block.params then machine = machine:with_issue(Code.CodeIssueJumpArity(dest, #block.params, #args)) end
        local n = math.min(#args, #block.params)
        for i = 1, n do
            local aty
            machine, aty = value_type(fctx, machine, args[i])
            if aty ~= nil and not type_eq(block.params[i].ty, aty) then
                machine = machine:with_issue(Code.CodeIssueBlockParamMismatch(dest, i, block.params[i].ty, aty))
            end
        end
        return machine
    end

    local function check_call(machine, fctx, site, sig_id, target, args, dst)
        local sig
        machine, sig = check_sig_ref(machine, sig_id)
        local tcls = asdl.classof(target)
        if tcls == Code.CodeCallDirect then
            local fn = machine:func(target.func)
            if fn == nil then machine = machine:with_issue(Code.CodeIssueMissingFunc(target.func))
            elseif sig_id ~= nil and fn.sig ~= sig_id then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":direct-sig", Code.CodeTyCodePtr(fn.sig), Code.CodeTyCodePtr(sig_id))) end
        elseif tcls == Code.CodeCallExtern then
            local ex = machine:extern(target["extern"])
            if ex == nil then machine = machine:with_issue(Code.CodeIssueMissingExtern(target["extern"]))
            elseif sig_id ~= nil and ex.sig ~= sig_id then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":extern-sig", Code.CodeTyCodePtr(ex.sig), Code.CodeTyCodePtr(sig_id))) end
        elseif tcls == Code.CodeCallIndirect then
            machine, _ = check_sig_ref(machine, target.sig)
            if sig_id ~= nil and target.sig ~= sig_id then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":indirect-sig", Code.CodeTyCodePtr(target.sig), Code.CodeTyCodePtr(sig_id))) end
            local callee_ty
            machine, callee_ty = value_type(fctx, machine, target.callee)
            if callee_ty ~= nil then
                if asdl.classof(callee_ty) == Code.CodeTyCodePtr then
                    if target.sig ~= callee_ty.sig then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":callee", Code.CodeTyCodePtr(target.sig), callee_ty)) end
                elseif asdl.classof(callee_ty) == Code.CodeTyDataPtr then
                    machine = machine:with_issue(Code.CodeIssueDataCodePointerConfusion(site .. ":callee", callee_ty))
                else
                    machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":callee", Code.CodeTyCodePtr(target.sig), callee_ty))
                end
            end
        elseif tcls == Code.CodeCallClosure then
            machine, _ = check_sig_ref(machine, target.sig)
            if sig_id ~= nil and target.sig ~= sig_id then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":closure-sig", Code.CodeTyClosure(target.sig), Code.CodeTyClosure(sig_id))) end
            local closure_ty
            machine, closure_ty = value_type(fctx, machine, target.closure)
            if closure_ty ~= nil then
                if asdl.classof(closure_ty) == Code.CodeTyClosure then
                    if target.sig ~= closure_ty.sig then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(target.sig), closure_ty)) end
                else
                    machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(target.sig), closure_ty))
                end
            end
        else
            machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "unsupported call target " .. class_name(target)))
        end
        if sig == nil then return machine end
        if #args ~= #sig.params then machine = machine:with_issue(Code.CodeIssueCallArity(sig.id, #sig.params, #args)) end
        local n = math.min(#args, #sig.params)
        for i = 1, n do
            local aty
            machine, aty = value_type(fctx, machine, args[i])
            if aty ~= nil then machine = expect_type(machine, site .. ":arg" .. tostring(i), sig.params[i], aty) end
        end
        if #sig.results == 0 then
            if dst ~= nil then
                local dty
                machine, dty = value_type(fctx, machine, dst)
                machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":result", Code.CodeTyVoid, dty or Code.CodeTyVoid))
            end
        elseif #sig.results == 1 then
            if dst == nil then
                machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":result", sig.results[1], Code.CodeTyVoid))
            else
                local dty
                machine, dty = value_type(fctx, machine, dst)
                if dty ~= nil then machine = expect_type(machine, site .. ":result", sig.results[1], dty) end
            end
        else
            machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "multi-result call cannot be represented by one dst"))
        end
        return machine
    end

    local function register_dst(machine, fctx, id, ty)
        if id == nil then return machine end
        if fctx.values[id.text] ~= nil then machine = machine:with_issue(Code.CodeIssueDuplicateValue(id)) end
        fctx.values[id.text] = ty
        return type_uses_code_sig(ty, machine)
    end

    local function inst_dst_type(fctx, machine, kind)
        local cls = asdl.classof(kind)
        if cls == Code.CodeInstConst then return kind.dst, kind.const.ty
        elseif cls == Code.CodeInstAlias then return kind.dst, kind.ty
        elseif cls == Code.CodeInstUnary then return kind.dst, kind.ty
        elseif cls == Code.CodeInstBinary then return kind.dst, kind.ty
        elseif cls == Code.CodeInstFloatBinary then return kind.dst, kind.ty
        elseif cls == Code.CodeInstCompare then return kind.dst, Code.CodeTyBool8
        elseif cls == Code.CodeInstCast then return kind.dst, kind.to
        elseif cls == Code.CodeInstSelect then return kind.dst, kind.ty
        elseif cls == Code.CodeInstIntrinsic then return kind.dst, kind.ty
        elseif cls == Code.CodeInstAddrOf then return kind.dst, kind.ptr_ty
        elseif cls == Code.CodeInstGlobalRef then return kind.dst, kind.ptr_ty
        elseif cls == Code.CodeInstPtrOffset then return kind.dst, kind.ptr_ty
        elseif cls == Code.CodeInstLoad then return kind.dst, kind.access.ty
        elseif cls == Code.CodeInstAggregate then return kind.dst, kind.ty
        elseif cls == Code.CodeInstArray then return kind.dst, kind.ty
        elseif cls == Code.CodeInstViewMake then return kind.dst, Code.CodeTyView(kind.elem_ty)
        elseif cls == Code.CodeInstViewData then
            local elem
            machine, elem = view_elem_type(fctx, machine, "view.data", kind.view)
            return kind.dst, Code.CodeTyDataPtr(elem)
        elseif cls == Code.CodeInstViewLen then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstViewStride then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstSliceMake then return kind.dst, Code.CodeTySlice(kind.elem_ty)
        elseif cls == Code.CodeInstSliceData then
            local elem
            machine, elem = slice_elem_type(fctx, machine, "slice.data", kind.slice)
            return kind.dst, Code.CodeTyDataPtr(elem)
        elseif cls == Code.CodeInstSliceLen then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstByteSpanMake then return kind.dst, Code.CodeTyByteSpan
        elseif cls == Code.CodeInstByteSpanData then return kind.dst, Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
        elseif cls == Code.CodeInstByteSpanLen then return kind.dst, Code.CodeTyIndex
        elseif cls == Code.CodeInstClosure then return kind.dst, kind.ty
        elseif cls == Code.CodeInstVariantCtor then return kind.dst, kind.ty
        elseif cls == Code.CodeInstVariantTag then return kind.dst, kind.tag_ty
        elseif cls == Code.CodeInstVariantPayload then return kind.dst, kind.variant.payload_ty
        elseif cls == Code.CodeInstCall then
            return nil, nil
        elseif cls == Code.CodeInstAtomicLoad then return kind.dst, kind.access.ty
        elseif cls == Code.CodeInstAtomicRmw then return kind.dst, kind.access.ty
        elseif cls == Code.CodeInstAtomicCas then return kind.dst, kind.access.ty
        end
        return nil, nil
    end

    local function index_by(machine, items, key_fn, dup_issue_fn)
        local by = {}
        for i = 1, #(items or {}) do
            local item = items[i]
            local key, ref = key_fn(item)
            if by[key] ~= nil then machine = machine:with_issue(dup_issue_fn(ref)) else by[key] = item end
        end
        return machine, by
    end

    local function register_function_defs(machine, fctx, func)
        for i = 1, #(func.params or {}) do machine = register_dst(machine, fctx, func.params[i].value, func.params[i].ty) end
        for i = 1, #(func.locals or {}) do
            local local_ = func.locals[i]
            if fctx.locals[local_.id.text] ~= nil then machine = machine:with_issue(Code.CodeIssueUnsupportedSource("func:" .. func.name, "duplicate local " .. local_.id.text)) end
            fctx.locals[local_.id.text] = local_
            machine = type_uses_code_sig(local_.ty, machine)
        end
        machine, fctx.blocks = index_by(machine, func.blocks, function(b) return b.id.text, b.id end, function(id) return Code.CodeIssueDuplicateBlock(id) end)
        for i = 1, #(func.blocks or {}) do
            local block = func.blocks[i]
            if block.term == nil then machine = machine:with_issue(Code.CodeIssueUnterminatedBlock(block.id)) end
            if block.term ~= nil then
                if fctx.terms[block.term.id.text] ~= nil then machine = machine:with_issue(Code.CodeIssueDuplicateTerm(block.term.id)) end
                fctx.terms[block.term.id.text] = true
            end
            for j = 1, #(block.params or {}) do machine = register_dst(machine, fctx, block.params[j].value, block.params[j].ty) end
            for j = 1, #(block.insts or {}) do
                local inst = block.insts[j]
                if fctx.insts[inst.id.text] ~= nil then machine = machine:with_issue(Code.CodeIssueDuplicateInst(inst.id)) end
                fctx.insts[inst.id.text] = true
                local dst, ty = inst_dst_type(fctx, machine, inst.op)
                if asdl.classof(inst.op) == Code.CodeInstCall then
                    local sig = inst.op.sig and machine:sig(inst.op.sig) or nil
                    if sig ~= nil and #sig.results == 1 then dst, ty = rawget(inst.op, "dst"), sig.results[1] end
                end
                if dst ~= nil then machine = register_dst(machine, fctx, dst, ty) end
            end
        end
        return machine
    end

    local function check_inst(machine, fctx, func, block, inst)
        local site = "func:" .. func.name .. ":block:" .. block.name .. ":inst:" .. inst.id.text
        local k = inst.op
        local cls = asdl.classof(k)
        if cls == Code.CodeInstConst then
            machine = type_uses_code_sig(k.const.ty, machine)
        elseif cls == Code.CodeInstAlias then
            local aty
            machine, aty = value_type(fctx, machine, k.src)
            machine = expect_type(machine, site .. ":alias", k.ty, aty)
        elseif cls == Code.CodeInstUnary then
            local vty; machine, vty = value_type(fctx, machine, k.value)
            machine = expect_type(machine, site .. ":unary", k.ty, vty)
        elseif cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary then
            local lty, rty; machine, lty = value_type(fctx, machine, k.lhs); machine, rty = value_type(fctx, machine, k.rhs)
            machine = expect_type(machine, site .. ":lhs", k.ty, lty)
            machine = expect_type(machine, site .. ":rhs", k.ty, rty)
        elseif cls == Code.CodeInstCompare then
            local lty, rty; machine, lty = value_type(fctx, machine, k.lhs); machine, rty = value_type(fctx, machine, k.rhs)
            machine = expect_type(machine, site .. ":lhs", k.operand_ty, lty)
            machine = expect_type(machine, site .. ":rhs", k.operand_ty, rty)
        elseif cls == Code.CodeInstCast then
            local vty; machine, vty = value_type(fctx, machine, k.value)
            machine = expect_type(machine, site .. ":cast", k.from, vty)
        elseif cls == Code.CodeInstSelect then
            local cty, tty, ety
            machine, cty = value_type(fctx, machine, k.cond)
            machine = expect_bool(machine, site .. ":cond", cty)
            machine, tty = value_type(fctx, machine, k.then_value)
            machine = expect_type(machine, site .. ":then", k.ty, tty)
            machine, ety = value_type(fctx, machine, k.else_value)
            machine = expect_type(machine, site .. ":else", k.ty, ety)
        elseif cls == Code.CodeInstIntrinsic then
            for i = 1, #k.args do machine, _ = value_type(fctx, machine, k.args[i]) end
        elseif cls == Code.CodeInstAddrOf then
            local pty
            machine, pty = place_type(machine, fctx, k.place, site .. ":addr_of")
            if asdl.classof(k.ptr_ty) ~= Code.CodeTyDataPtr then machine = machine:with_issue(Code.CodeIssueDataCodePointerConfusion(site .. ":addr_of", k.ptr_ty))
            elseif pty ~= nil and k.ptr_ty.pointee ~= nil then machine = expect_type(machine, site .. ":addr_of", k.ptr_ty.pointee, pty) end
        elseif cls == Code.CodeInstGlobalRef then
            local target
            machine, target = global_ref_exists(machine, k.ref)
            local rcls = asdl.classof(k.ref)
            if rcls == Code.CodeGlobalRefFunc or rcls == Code.CodeGlobalRefExtern then
                local sig = target and target.sig or nil
                local expected = sig and Code.CodeTyCodePtr(sig) or nil
                if asdl.classof(k.ptr_ty) ~= Code.CodeTyCodePtr then machine = machine:with_issue(Code.CodeIssueDataCodePointerConfusion(site .. ":global_ref", k.ptr_ty))
                elseif expected ~= nil then machine = expect_type(machine, site .. ":global_ref", expected, k.ptr_ty) end
            else
                if asdl.classof(k.ptr_ty) ~= Code.CodeTyDataPtr then machine = machine:with_issue(Code.CodeIssueDataCodePointerConfusion(site .. ":global_ref", k.ptr_ty)) end
            end
        elseif cls == Code.CodeInstPtrOffset then
            if asdl.classof(k.ptr_ty) ~= Code.CodeTyDataPtr then machine = machine:with_issue(Code.CodeIssueDataCodePointerConfusion(site .. ":ptr_offset", k.ptr_ty)) end
            local bty
            machine, bty = value_type(fctx, machine, k.base)
            if bty ~= nil and asdl.classof(bty) ~= Code.CodeTyDataPtr then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":base", Code.CodeTyDataPtr(nil), bty)) end
            local ity
            machine, ity = value_type(fctx, machine, k.index)
            if ity ~= nil and not is_integer_like(ity) then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":index", Code.CodeTyIndex, ity)) end
            if k.elem_size <= 0 then machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "invalid element size")) end
        elseif cls == Code.CodeInstLoad then
            local pty
            machine, pty = place_type(machine, fctx, k.place, site .. ":load")
            machine = check_memory_access(machine, site .. ":load", k.access, "read")
            if pty ~= nil then machine = expect_type(machine, site .. ":load", k.access.ty, pty) end
        elseif cls == Code.CodeInstStore then
            local pty
            machine, pty = place_type(machine, fctx, k.place, site .. ":store")
            machine = check_memory_access(machine, site .. ":store", k.access, "write")
            if pty ~= nil then machine = expect_type(machine, site .. ":store.place", k.access.ty, pty) end
            local svty; machine, svty = value_type(fctx, machine, k.value)
            machine = expect_type(machine, site .. ":store.value", k.access.ty, svty)
        elseif cls == Code.CodeInstAggregate then
            for i = 1, #k.fields do machine, _ = value_type(fctx, machine, k.fields[i].value) end
        elseif cls == Code.CodeInstArray then
            for i = 1, #k.elems do machine, _ = value_type(fctx, machine, k.elems[i].value) end
        elseif cls == Code.CodeInstViewMake then
            machine = type_uses_code_sig(k.elem_ty, machine)
            local expected_data_ty = Code.CodeTyDataPtr(k.elem_ty)
            local dty
            machine, dty = value_type(fctx, machine, k.data)
            if dty ~= nil and asdl.classof(dty) ~= Code.CodeTyDataPtr then
                machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":view.data", Code.CodeTyDataPtr(nil), dty))
            elseif dty ~= nil and dty.pointee ~= nil then
                machine = expect_type(machine, site .. ":view.data", expected_data_ty, dty)
            end
            local lty
            machine, lty = value_type(fctx, machine, k.len)
            if lty ~= nil and not is_integer_like(lty) then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":view.len", Code.CodeTyIndex, lty)) end
            local sty
            machine, sty = value_type(fctx, machine, k.stride)
            if sty ~= nil and not is_integer_like(sty) then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":view.stride", Code.CodeTyIndex, sty)) end
        elseif cls == Code.CodeInstViewData then
            local elem
            machine, elem = view_elem_type(fctx, machine, site .. ":view.data", k.view)
            if elem ~= nil then machine = type_uses_code_sig(Code.CodeTyDataPtr(elem), machine) end
        elseif cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then
            machine, _ = view_elem_type(fctx, machine, site .. ":view", k.view)
        elseif cls == Code.CodeInstSliceMake then
            machine = type_uses_code_sig(k.elem_ty, machine)
            local expected_data_ty = Code.CodeTyDataPtr(k.elem_ty)
            local dty
            machine, dty = value_type(fctx, machine, k.data)
            if dty ~= nil and asdl.classof(dty) ~= Code.CodeTyDataPtr then
                machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":slice.data", Code.CodeTyDataPtr(nil), dty))
            elseif dty ~= nil and dty.pointee ~= nil then
                machine = expect_type(machine, site .. ":slice.data", expected_data_ty, dty)
            end
            local lty
            machine, lty = value_type(fctx, machine, k.len)
            if lty ~= nil and not is_integer_like(lty) then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":slice.len", Code.CodeTyIndex, lty)) end
        elseif cls == Code.CodeInstSliceData then
            local elem
            machine, elem = slice_elem_type(fctx, machine, site .. ":slice.data", k.slice)
            if elem ~= nil then machine = type_uses_code_sig(Code.CodeTyDataPtr(elem), machine) end
        elseif cls == Code.CodeInstSliceLen then
            machine, _ = slice_elem_type(fctx, machine, site .. ":slice", k.slice)
        elseif cls == Code.CodeInstByteSpanMake then
            local expected_data_ty = Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
            local dty
            machine, dty = value_type(fctx, machine, k.data)
            if dty ~= nil and asdl.classof(dty) ~= Code.CodeTyDataPtr then
                machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":bytespan.data", Code.CodeTyDataPtr(nil), dty))
            elseif dty ~= nil and dty.pointee ~= nil then
                machine = expect_type(machine, site .. ":bytespan.data", expected_data_ty, dty)
            end
            local lty
            machine, lty = value_type(fctx, machine, k.len)
            if lty ~= nil and not is_integer_like(lty) then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":bytespan.len", Code.CodeTyIndex, lty)) end
        elseif cls == Code.CodeInstByteSpanData then
            machine, _ = byte_span_type(fctx, machine, site .. ":bytespan.data", k.span)
        elseif cls == Code.CodeInstByteSpanLen then
            machine, _ = byte_span_type(fctx, machine, site .. ":bytespan", k.span)
        elseif cls == Code.CodeInstClosure then
            machine, _ = check_sig_ref(machine, k.sig)
            if asdl.classof(k.ty) ~= Code.CodeTyClosure then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(k.sig), k.ty))
            elseif k.ty.sig ~= k.sig then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":closure", Code.CodeTyClosure(k.sig), k.ty)) end
            local fnty; machine, fnty = value_type(fctx, machine, k.fn)
            machine = expect_type(machine, site .. ":closure.fn", Code.CodeTyCodePtr(k.sig), fnty)
            local cty
            machine, cty = value_type(fctx, machine, k.ctx)
            if cty ~= nil and asdl.classof(cty) ~= Code.CodeTyDataPtr then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":closure.ctx", Code.CodeTyDataPtr(nil), cty)) end
        elseif cls == Code.CodeInstVariantCtor then
            if k.payload ~= nil then
                if k.variant.payload_ty == nil then
                    local pty
                    machine, pty = value_type(fctx, machine, k.payload)
                    machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":variant.payload", Code.CodeTyVoid, pty or Code.CodeTyVoid))
                else
                    local pty; machine, pty = value_type(fctx, machine, k.payload)
                    machine = expect_type(machine, site .. ":variant.payload", k.variant.payload_ty, pty)
                end
            elseif k.variant.payload_ty ~= nil then
                machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":variant.payload", k.variant.payload_ty, Code.CodeTyVoid))
            end
        elseif cls == Code.CodeInstVariantTag then
            if not is_integer_like(k.tag_ty) then machine = machine:with_issue(Code.CodeIssueTypeMismatch(site .. ":variant.tag", Code.CodeTyIndex, k.tag_ty)) end
            machine, _ = value_type(fctx, machine, k.value)
        elseif cls == Code.CodeInstVariantPayload then
            machine, _ = value_type(fctx, machine, k.value)
        elseif cls == Code.CodeInstCall then
            machine = check_call(machine, fctx, site .. ":call", k.sig, k.target, k.args, k.dst)
        elseif cls == Code.CodeInstAtomicLoad then
            local pty
            machine, pty = place_type(machine, fctx, k.place, site .. ":atomic_load")
            machine = check_memory_access(machine, site .. ":atomic_load", k.access, "read")
            if pty ~= nil then machine = expect_type(machine, site .. ":atomic_load", k.access.ty, pty) end
        elseif cls == Code.CodeInstAtomicStore then
            local pty
            machine, pty = place_type(machine, fctx, k.place, site .. ":atomic_store")
            machine = check_memory_access(machine, site .. ":atomic_store", k.access, "write")
            if pty ~= nil then machine = expect_type(machine, site .. ":atomic_store.place", k.access.ty, pty) end
            local asvty; machine, asvty = value_type(fctx, machine, k.value)
            machine = expect_type(machine, site .. ":atomic_store.value", k.access.ty, asvty)
        elseif cls == Code.CodeInstAtomicRmw then
            local pty
            machine, pty = place_type(machine, fctx, k.place, site .. ":atomic_rmw")
            machine = check_memory_access(machine, site .. ":atomic_rmw", k.access, "write")
            if pty ~= nil then machine = expect_type(machine, site .. ":atomic_rmw.place", k.access.ty, pty) end
            local armvty; machine, armvty = value_type(fctx, machine, k.value)
            machine = expect_type(machine, site .. ":atomic_rmw.value", k.access.ty, armvty)
        elseif cls == Code.CodeInstAtomicCas then
            local pty
            machine, pty = place_type(machine, fctx, k.place, site .. ":atomic_cas")
            machine = check_memory_access(machine, site .. ":atomic_cas", k.access, "write")
            if pty ~= nil then machine = expect_type(machine, site .. ":atomic_cas.place", k.access.ty, pty) end
            local aevty, arpty
            machine, aevty = value_type(fctx, machine, k.expected)
            machine = expect_type(machine, site .. ":atomic_cas.expected", k.access.ty, aevty)
            machine, arpty = value_type(fctx, machine, k.replacement)
            machine = expect_type(machine, site .. ":atomic_cas.replacement", k.access.ty, arpty)
        elseif cls == Code.CodeInstAtomicFence then
            -- no value refs
        else
            machine = machine:with_issue(Code.CodeIssueUnsupportedSource(site, "unsupported instruction " .. class_name(k)))
        end
        return machine
    end

    local function check_term(machine, fctx, func, block)
        local term = block.term
        if term == nil then return machine end
        local site = "func:" .. func.name .. ":block:" .. block.name .. ":term:" .. term.id.text
        local k = term.op
        local cls = asdl.classof(k)
        if cls == Code.CodeTermJump then
            machine = check_transfer(machine, fctx, site .. ":jump", k.dest, k.args)
        elseif cls == Code.CodeTermBranch then
            local bcty; machine, bcty = value_type(fctx, machine, k.cond)
            machine = expect_bool(machine, site .. ":branch.cond", bcty)
            machine = check_transfer(machine, fctx, site .. ":branch.then", k.then_dest, k.then_args)
            machine = check_transfer(machine, fctx, site .. ":branch.else", k.else_dest, k.else_args)
        elseif cls == Code.CodeTermSwitch then
            machine, _ = value_type(fctx, machine, k.value)
            for i = 1, #k.cases do machine = check_transfer(machine, fctx, site .. ":switch.case" .. tostring(i), k.cases[i].dest, k.cases[i].args) end
            machine = check_transfer(machine, fctx, site .. ":switch.default", k.default_dest, k.default_args)
        elseif cls == Code.CodeTermVariantSwitch then
            machine, _ = value_type(fctx, machine, k.tag)
            for i = 1, #k.cases do machine = check_transfer(machine, fctx, site .. ":variant.case" .. tostring(i), k.cases[i].dest, k.cases[i].args) end
            machine = check_transfer(machine, fctx, site .. ":variant.default", k.default_dest, k.default_args)
        elseif cls == Code.CodeTermReturn then
            local sig = fctx.sig
            if sig ~= nil then
                if #k.values ~= #sig.results then machine = machine:with_issue(Code.CodeIssueCallArity(sig.id, #sig.results, #k.values)) end
                local n = math.min(#k.values, #sig.results)
                for i = 1, n do
                    local vty
                    machine, vty = value_type(fctx, machine, k.values[i])
                    if vty ~= nil then machine = expect_type(machine, site .. ":return" .. tostring(i), sig.results[i], vty) end
                end
            else
                for i = 1, #k.values do machine, _ = value_type(fctx, machine, k.values[i]) end
            end
        elseif cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then
            -- valid terminal forms
        else
            machine = machine:with_issue(Code.CodeIssueInvalidTerminator(site, term.id))
        end
        return machine
    end

    local function validate_func(machine, func)
        local sig
        machine, sig = check_sig_ref(machine, func.sig)
        local fctx = { func = func, sig = sig, values = {}, locals = {}, blocks = {}, insts = {}, terms = {} }
        if sig ~= nil then
            if #func.params ~= #sig.params then machine = machine:with_issue(Code.CodeIssueCallArity(sig.id, #sig.params, #func.params)) end
            local n = math.min(#func.params, #sig.params)
            for i = 1, n do machine = expect_type(machine, "func:" .. func.name .. ":param" .. tostring(i), sig.params[i], func.params[i].ty) end
        end
        machine = register_function_defs(machine, fctx, func)
        if fctx.blocks[func.entry.text] == nil then machine = machine:with_issue(Code.CodeIssueMissingBlock(func.entry)) end
        for i = 1, #(func.blocks or {}) do
            local block = func.blocks[i]
            for j = 1, #(block.params or {}) do machine = type_uses_code_sig(block.params[j].ty, machine) end
            for j = 1, #(block.insts or {}) do machine = check_inst(machine, fctx, func, block, block.insts[j]) end
            machine = check_term(machine, fctx, func, block)
        end
        return machine
    end

    local function validate(code_module, collector_or_opts)
        local collector = collector_or_opts
        if type(collector_or_opts) == "table" and collector_or_opts.collector ~= nil then collector = collector_or_opts.collector end
        local machine = Machine.new({}, {}, {}, {}, {})

        machine, machine._sigs = index_by(machine, code_module.sigs, function(s) return s.id.text, s.id end, function(id) return Code.CodeIssueDuplicateSig(id) end)
        machine, machine._data = index_by(machine, code_module.data, function(d) return d.id.text, d.id end, function(id) return Code.CodeIssueDuplicateData(id) end)
        machine, machine._globals = index_by(machine, code_module.globals, function(g) return g.id.text, g.id end, function(id) return Code.CodeIssueDuplicateGlobal(id) end)
        machine, machine._externs = index_by(machine, code_module.externs, function(e) return e.id.text, e.id end, function(id) return Code.CodeIssueDuplicateExtern(id) end)
        machine, machine._funcs = index_by(machine, code_module.funcs, function(f) return f.id.text, f.id end, function(id) return Code.CodeIssueDuplicateFunc(id) end)

        for i = 1, #(code_module.sigs or {}) do
            local sig = code_module.sigs[i]
            for j = 1, #sig.params do machine = type_uses_code_sig(sig.params[j], machine) end
            for j = 1, #sig.results do machine = type_uses_code_sig(sig.results[j], machine) end
        end
        for i = 1, #(code_module.types or {}) do machine = type_uses_code_sig(code_module.types[i].ty, machine) end
        for i = 1, #(code_module.externs or {}) do machine, _ = check_sig_ref(machine, code_module.externs[i].sig) end
        for i = 1, #(code_module.globals or {}) do
            local g = code_module.globals[i]
            machine = type_uses_code_sig(g.ty, machine)
            machine = check_align(machine, "global:" .. g.id.text, g.align, nil)
            for j = 1, #(g.inits or {}) do
                local init = g.inits[j]
                machine = check_init_bounds(machine, "global", g.id, g.size, init)
                if asdl.classof(init) == Code.CodeDataReloc then machine = check_reloc(machine, init.reloc) end
            end
        end
        for i = 1, #(code_module.data or {}) do
            local d = code_module.data[i]
            machine = check_align(machine, "data:" .. d.id.text, d.align, nil)
            for j = 1, #(d.inits or {}) do
                local init = d.inits[j]
                machine = check_init_bounds(machine, "data", d.id, d.size, init)
                if asdl.classof(init) == Code.CodeDataReloc then machine = check_reloc(machine, init.reloc) end
            end
        end
        for i = 1, #(code_module.funcs or {}) do machine = validate_func(machine, code_module.funcs[i]) end

        -- Support collector callback for backward compatibility
        if collector and collector.emit then
            for _, issue in ipairs(machine:issues()) do
                pcall(function() collector:emit(issue, "code") end)
            end
        end

        return Code.CodeValidationReport(machine:issues())
    end

    api.validate = validate
    api.type_eq = type_eq

    T._lalin_api_cache.code_validate = api
    return api
end

return bind_context
