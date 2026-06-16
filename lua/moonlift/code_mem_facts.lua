local pvm = require("moonlift.pvm")

local M = {}

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_mem_facts ~= nil then return T._moonlift_api_cache.code_mem_facts end

    local Code = T.MoonCode
    local Flow = T.MoonFlow
    local Mem = T.MoonMem

    local api = {}

    local function access_id(func, inst, ordinal)
        local stem = inst and inst.id and inst.id.text or ("access:" .. tostring(ordinal or 0))
        return Mem.MemAccessId("mem:" .. sanitize(func.name) .. ":" .. sanitize(stem))
    end

    local function assert_access_mode(site, access, allowed)
        if access == nil then error(site .. ": missing CodeMemoryAccess", 3) end
        if allowed[access.mode] then return end
        error(site .. ": CodeMemoryAccess mode " .. tostring(access.mode and access.mode.kind or access.mode) .. " is inconsistent with memory instruction", 3)
    end

    local function access_kind(inst_kind)
        local cls = pvm.classof(inst_kind)
        if cls == Code.CodeInstLoad then return Mem.MemLoad end
        if cls == Code.CodeInstStore then return Mem.MemStore end
        if cls == Code.CodeInstAtomicLoad then return Mem.MemAtomicLoad end
        if cls == Code.CodeInstAtomicStore then return Mem.MemAtomicStore end
        if cls == Code.CodeInstAtomicRmw then return Mem.MemAtomicRmw end
        if cls == Code.CodeInstAtomicCas then return Mem.MemAtomicCas end
        return nil
    end

    local function trap_fact(access)
        if access.trap == Code.CodeMustNotTrap then return Mem.MemNonTrapping("CodeMemoryAccess CodeMustNotTrap") end
        if access.trap == Code.CodeCheckedTrap then return Mem.MemCheckedTrap("CodeMemoryAccess CodeCheckedTrap") end
        return Mem.MemMayTrap
    end

    local function alignment_fact(access)
        if type(access.align) == "number" and access.align >= 1 then return Mem.MemAlignKnown(access.align) end
        return Mem.MemAlignUnknown
    end

    local function object_id(...)
        local parts = { ... }
        local out = {}
        for i = 1, #parts do out[#out + 1] = sanitize(parts[i]) end
        return Mem.MemObjectId("obj:" .. table.concat(out, ":"))
    end

    local function type_size_bytes(ty)
        local cls = pvm.classof(ty)
        if ty == Code.CodeTyBool8 then return 1 end
        if ty == Code.CodeTyIndex then return 8 end
        if cls == Code.CodeTyInt or cls == Code.CodeTyFloat then
            if ty.bits ~= nil and ty.bits % 8 == 0 then return ty.bits / 8 end
            return nil
        elseif cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr then
            return 8
        elseif cls == Code.CodeTyArray then
            local elem = type_size_bytes(ty.elem)
            if elem ~= nil and ty.count ~= nil then return elem * ty.count end
        elseif cls == Code.CodeTyVector then
            local elem = type_size_bytes(ty.elem)
            if elem ~= nil and ty.lanes ~= nil then return elem * ty.lanes end
        end
        return nil
    end

    local function storage_extent(ty, explicit_size, reason)
        if type(explicit_size) == "number" then return Mem.MemExtentBytes(explicit_size, reason) end
        local bytes = type_size_bytes(ty)
        if bytes ~= nil then return Mem.MemExtentBytes(bytes, reason) end
        return Mem.MemExtentUnknown(reason .. " size is not known in Code")
    end

    local function pointee_ty(ty)
        return pvm.classof(ty) == Code.CodeTyDataPtr and ty.pointee or nil
    end

    local function view_elem_ty(ty)
        return pvm.classof(ty) == Code.CodeTyView and ty.elem or nil
    end

    local function object_elem_ty(ty)
        if pvm.classof(ty) == Code.CodeTyArray then return ty.elem end
        return ty
    end

    local function flow_inductions(flow)
        local by_value = {}
        for _, loop in ipairs(flow and flow.loops or {}) do
            for _, induction in ipairs(loop.inductions or {}) do
                by_value[induction.value.text] = induction
            end
        end
        return by_value
    end

    local function value_defs(func)
        local ptr_offsets, view_data, value_ops = {}, {}, {}
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local cls = pvm.classof(k)
                if cls == Code.CodeInstPtrOffset then
                    ptr_offsets[k.dst.text] = k
                elseif cls == Code.CodeInstView then
                    view_data[k.dst.text] = { data = k.data, len = k.len, stride = k.stride, ty = k.ty }
                elseif cls == Code.CodeInstViewData then
                    view_data[k.dst.text] = { view = k.view, ty = k.view_ty }
                elseif cls == Code.CodeInstAlias then
                    value_ops[k.dst.text] = { cls = cls, src = k.src }
                elseif cls == Code.CodeInstCast then
                    value_ops[k.dst.text] = { cls = cls, value = k.value }
                elseif cls == Code.CodeInstBinary then
                    value_ops[k.dst.text] = { cls = cls, op = k.op, lhs = k.lhs, rhs = k.rhs }
                elseif cls == Code.CodeInstConst then
                    value_ops[k.dst.text] = { cls = cls, const = k.const }
                end
            end
        end
        return ptr_offsets, view_data, value_ops
    end

    local normalize_place

    local function derived_base(base, reason)
        return Mem.MemBaseDerived(base, reason)
    end

    local function const_int(value, value_ops)
        local op = value and value_ops[value.text] or nil
        if op == nil or op.cls ~= Code.CodeInstConst or pvm.classof(op.const) ~= Code.CodeConstLiteral then return nil end
        local lit = op.const.literal
        return lit and lit.raw and tonumber(lit.raw) or nil
    end

    local function stride_fact(value, value_ops)
        local n = const_int(value, value_ops or {})
        if n == 1 then return Mem.MemStrideUnit end
        if n ~= nil then return Mem.MemStrideConstElems(n) end
        if value ~= nil then return Mem.MemStrideValue(value) end
        return Mem.MemStrideUnknown("stride value is unavailable")
    end

    local function add_object(out, by_id, fact)
        local key = fact.id.text
        if by_id[key] == nil then
            by_id[key] = fact
            out[#out + 1] = fact
        end
        return fact.id
    end

    local function contract_index(contracts)
        local idx = { bounds = {}, window_bounds = {}, same_len = {}, disjoint = {}, noalias = {}, readonly = {}, writeonly = {}, facts = {} }
        for _, fact in ipairs(contracts and contracts.facts or {}) do
            idx.facts[fact.func.text] = idx.facts[fact.func.text] or {}
            idx.facts[fact.func.text][#idx.facts[fact.func.text] + 1] = fact
            local k = fact.fact
            local cls = pvm.classof(k)
            if cls == Code.CodeContractBounds then
                idx.bounds[fact.func.text .. "\0" .. k.base.text] = fact
            elseif cls == Code.CodeContractWindowBounds then
                idx.window_bounds[fact.func.text .. "\0" .. k.base.text] = fact
            elseif cls == Code.CodeContractSameLen then
                idx.same_len[#idx.same_len + 1] = fact
            elseif cls == Code.CodeContractDisjoint then
                idx.disjoint[fact.func.text .. "\0" .. k.a.text .. "\0" .. k.b.text] = fact
                idx.disjoint[fact.func.text .. "\0" .. k.b.text .. "\0" .. k.a.text] = fact
            elseif cls == Code.CodeContractNoAlias then
                idx.noalias[fact.func.text .. "\0" .. k.base.text] = fact
            elseif cls == Code.CodeContractReadonly then
                idx.readonly[fact.func.text .. "\0" .. k.base.text] = fact
            elseif cls == Code.CodeContractWriteonly then
                idx.writeonly[fact.func.text .. "\0" .. k.base.text] = fact
            end
        end
        return idx
    end

    local function semantic_objects(module, contracts)
        local objects, by_id = {}, {}
        local cidx = contract_index(contracts)
        local module_objects = { data = {}, global = {} }

        for _, data in ipairs(module.data or {}) do
            local id = object_id("data", data.id.text)
            module_objects.data[data.id.text] = id
            add_object(objects, by_id, Mem.MemObjectFact(
                id,
                nil,
                Mem.MemObjectData,
                Mem.MemProvData(data.id),
                nil,
                Mem.MemExtentBytes(data.size or 0, "CodeData.size"),
                Mem.MemStrideUnit
            ))
        end

        for _, global in ipairs(module.globals or {}) do
            local id = object_id("global", global.id.text)
            module_objects.global[global.id.text] = id
            add_object(objects, by_id, Mem.MemObjectFact(
                id,
                nil,
                Mem.MemObjectGlobal,
                Mem.MemProvGlobal(global.id),
                object_elem_ty(global.ty),
                storage_extent(global.ty, global.size, "CodeGlobal storage"),
                Mem.MemStrideUnit
            ))
        end

        local by_func = {}
        for _, func in ipairs(module.funcs or {}) do
            local ptr_offsets, view_data, value_ops = value_defs(func)
            local value_object, local_object, local_value_object = {}, {}, {}

            for _, param in ipairs(func.params or {}) do
                if pvm.classof(param.ty) == Code.CodeTyDataPtr then
                    local bounds_contract = cidx.bounds[func.id.text .. "\0" .. param.value.text]
                    local window_contract = cidx.window_bounds[func.id.text .. "\0" .. param.value.text]
                    local extent_contract = bounds_contract or window_contract
                    local id = extent_contract and object_id(func.name, "contract", param.value.text) or object_id(func.name, "param", param.value.text)
                    value_object[param.value.text] = id
                    if extent_contract ~= nil then
                        local extent_len = bounds_contract and bounds_contract.fact.len or window_contract.fact.base_len
                        local reason = bounds_contract and "CodeContractBounds object extent" or "CodeContractWindowBounds base extent"
                        add_object(objects, by_id, Mem.MemObjectFact(
                            id,
                            func.id,
                            Mem.MemObjectContract,
                            Mem.MemProvContract(extent_contract),
                            pointee_ty(param.ty),
                            Mem.MemExtentElements(extent_len, pointee_ty(param.ty) or Code.CodeTyVoid, reason),
                            Mem.MemStrideUnit
                        ))
                    else
                        add_object(objects, by_id, Mem.MemObjectFact(
                            id,
                            func.id,
                            Mem.MemObjectParam,
                            Mem.MemProvValue(param.value),
                            pointee_ty(param.ty),
                            Mem.MemExtentUnknown("raw pointer parameter has no extent without contract or object provenance"),
                            Mem.MemStrideUnit
                        ))
                    end
                elseif pvm.classof(param.ty) == Code.CodeTyView then
                    local bounds_contract = cidx.bounds[func.id.text .. "\0" .. param.value.text]
                    local window_contract = cidx.window_bounds[func.id.text .. "\0" .. param.value.text]
                    local extent_contract = bounds_contract or window_contract
                    local id = object_id(func.name, "view_param", param.value.text)
                    value_object[param.value.text] = id
                    local extent = Mem.MemExtentUnknown("view parameter extent requires descriptor length facts")
                    if extent_contract ~= nil then
                        local elem = view_elem_ty(param.ty) or Code.CodeTyVoid
                        local len = bounds_contract and bounds_contract.fact.len or window_contract.fact.base_len
                        local reason = bounds_contract and "CodeContractBounds view extent" or "CodeContractWindowBounds view base extent"
                        extent = Mem.MemExtentElements(len, elem, reason)
                    end
                    add_object(objects, by_id, Mem.MemObjectFact(
                        id,
                        func.id,
                        extent_contract and Mem.MemObjectContract or Mem.MemObjectView,
                        extent_contract and Mem.MemProvContract(extent_contract) or Mem.MemProvValue(param.value),
                        view_elem_ty(param.ty),
                        extent,
                        Mem.MemStrideUnknown("view parameter stride requires descriptor stride facts")
                    ))
                end
            end

            for _, local_decl in ipairs(func.locals or {}) do
                local id = object_id(func.name, "local", local_decl.id.text)
                local_object[local_decl.id.text] = id
                add_object(objects, by_id, Mem.MemObjectFact(
                    id,
                    func.id,
                    Mem.MemObjectLocal,
                    Mem.MemProvLocal(local_decl.id),
                    object_elem_ty(local_decl.ty),
                    storage_extent(local_decl.ty, nil, "CodeLocal storage"),
                    Mem.MemStrideUnit
                ))
            end

            local function object_for_place(place)
                local cls = pvm.classof(place)
                if cls == Code.CodePlaceLocal then return local_object[place["local"].text] end
                if cls == Code.CodePlaceGlobal then return module_objects.global[place.global.text] end
                if cls == Code.CodePlaceData then return module_objects.data[place.data.text] end
                if cls == Code.CodePlaceDeref then return value_object[place.addr.text] end
                if cls == Code.CodePlaceIndex then return object_for_place(place.base) end
                if cls == Code.CodePlaceField then
                    local parent = object_for_place(place.base)
                    if parent == nil then return nil end
                    local id = object_id(func.name, "field", parent.text, tostring(place.offset or 0))
                    add_object(objects, by_id, Mem.MemObjectFact(
                        id,
                        func.id,
                        Mem.MemObjectDerived,
                        Mem.MemProvProjection(parent, Mem.MemProjectField, place.offset or 0),
                        place.ty,
                        storage_extent(place.ty, place.size, "CodePlaceField projection"),
                        Mem.MemStrideUnit
                    ))
                    return id
                elseif cls == Code.CodePlaceBytes then
                    local parent = value_object[place.base.text]
                    if parent == nil then return nil end
                    local id = object_id(func.name, "bytes", parent.text, tostring(place.offset or 0))
                    add_object(objects, by_id, Mem.MemObjectFact(
                        id,
                        func.id,
                        Mem.MemObjectDerived,
                        Mem.MemProvProjection(parent, Mem.MemProjectBytes, place.offset or 0),
                        place.ty,
                        Mem.MemExtentBytes(place.size or 0, "CodePlaceBytes projection"),
                        Mem.MemStrideUnit
                    ))
                    return id
                end
                return nil
            end

            local function merge_local_value(local_id, object)
                local key = local_id.text
                local old = local_value_object[key]
                if old == nil then
                    local_value_object[key] = object or false
                elseif old ~= object then
                    local_value_object[key] = false
                end
            end

            for _, block in ipairs(func.blocks or {}) do
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstGlobalRef then
                        local rcls = pvm.classof(k.ref)
                        if rcls == Code.CodeGlobalRefData then value_object[k.dst.text] = module_objects.data[k.ref.data.text] end
                        if rcls == Code.CodeGlobalRefGlobal then value_object[k.dst.text] = module_objects.global[k.ref.global.text] end
                    elseif cls == Code.CodeInstAddrOf then
                        value_object[k.dst.text] = object_for_place(k.place)
                    elseif cls == Code.CodeInstPtrOffset then
                        local parent = value_object[k.base.text]
                        if parent ~= nil then
                            local id = object_id(func.name, "ptr_offset", k.dst.text)
                            value_object[k.dst.text] = id
                            add_object(objects, by_id, Mem.MemObjectFact(
                                id,
                                func.id,
                                Mem.MemObjectDerived,
                                Mem.MemProvProjection(parent, Mem.MemProjectPtrOffset, k.const_offset or 0),
                                pointee_ty(k.ptr_ty),
                                Mem.MemExtentUnknown("ptr-offset projection requires a bounded slice/window fact before it has an extent"),
                                Mem.MemStrideUnit
                            ))
                        end
                    elseif cls == Code.CodeInstView then
                        local id = object_id(func.name, "view", k.dst.text)
                        value_object[k.dst.text] = id
                        add_object(objects, by_id, Mem.MemObjectFact(
                            id,
                            func.id,
                            Mem.MemObjectView,
                            Mem.MemProvView(k.dst, k.data, k.len, k.stride),
                            view_elem_ty(k.ty),
                            Mem.MemExtentElements(k.len, view_elem_ty(k.ty) or Code.CodeTyVoid, "CodeInstView length"),
                            stride_fact(k.stride, value_ops)
                        ))
                    elseif cls == Code.CodeInstViewData then
                        value_object[k.dst.text] = value_object[k.view.text]
                    elseif cls == Code.CodeInstLoad then
                        if pvm.classof(k.place) == Code.CodePlaceLocal and local_value_object[k.place["local"].text] then
                            value_object[k.dst.text] = local_value_object[k.place["local"].text]
                        end
                    elseif cls == Code.CodeInstStore then
                        if pvm.classof(k.place) == Code.CodePlaceLocal then
                            merge_local_value(k.place["local"], value_object[k.value.text])
                        end
                    elseif cls == Code.CodeInstAlias then
                        value_object[k.dst.text] = value_object[k.src.text]
                    elseif cls == Code.CodeInstCast then
                        value_object[k.dst.text] = value_object[k.value.text]
                    end
                end
            end

            by_func[func.id.text] = {
                value_object = value_object,
                local_object = local_object,
                local_value_object = local_value_object,
                module_objects = module_objects,
                view_data = view_data,
                ptr_offsets = ptr_offsets,
                value_ops = value_ops,
                object_for_place = object_for_place,
            }
        end

        return objects, by_func
    end

    local function resolve_index_induction(value, inductions, value_ops, seen)
        if value == nil then return nil, nil end
        local direct = inductions[value.text]
        if direct ~= nil then return direct, 1 end
        seen = seen or {}
        if seen[value.text] then return nil, nil end
        seen[value.text] = true
        local op = value_ops[value.text]
        if op == nil then return nil, nil end
        if op.cls == Code.CodeInstAlias then
            return resolve_index_induction(op.src, inductions, value_ops, seen)
        elseif op.cls == Code.CodeInstCast then
            return resolve_index_induction(op.value, inductions, value_ops, seen)
        elseif op.cls == Code.CodeInstBinary then
            local lhs_ind, lhs_scale = resolve_index_induction(op.lhs, inductions, value_ops, seen)
            local rhs_ind, rhs_scale = resolve_index_induction(op.rhs, inductions, value_ops, seen)
            if op.op == T.MoonCore.BinMul then
                if lhs_ind ~= nil then return lhs_ind, (lhs_scale or 1) * (const_int(op.rhs, value_ops) or 1) end
                if rhs_ind ~= nil then return rhs_ind, (rhs_scale or 1) * (const_int(op.lhs, value_ops) or 1) end
            elseif op.op == T.MoonCore.BinAdd or op.op == T.MoonCore.BinSub then
                if lhs_ind ~= nil then return lhs_ind, lhs_scale or 1 end
                if rhs_ind ~= nil and op.op == T.MoonCore.BinAdd then return rhs_ind, rhs_scale or 1 end
            end
        end
        return nil, nil
    end

    local function combine_index(existing, index, elem_size, const_offset, inductions, value_ops)
        if index == nil then return existing or Mem.MemIndexNone end
        local induction, scale = resolve_index_induction(index, inductions, value_ops or {})
        if induction ~= nil then return Mem.MemIndexInduction(induction, (elem_size or 1) * (scale or 1), const_offset or 0) end
        return Mem.MemIndexValue(index, elem_size or 1, const_offset or 0)
    end

    local function normalize_addr(addr, ty, ptr_offsets, view_data, inductions, value_ops)
        local offset = ptr_offsets[addr.text]
        if offset ~= nil then
            local base, index = normalize_addr(offset.base, ty, ptr_offsets, view_data, inductions, value_ops)
            return base, combine_index(index, offset.index, offset.elem_size, offset.const_offset, inductions, value_ops), Mem.MemAccessUnknown
        end
        -- Keep address bases value-based here. Structured object/provenance facts are
        -- emitted in MemSemanticFactSet instead of encoding view/data meaning in
        -- MemBaseDerived string reasons.
        return Mem.MemBaseValue(addr), Mem.MemIndexNone, Mem.MemAccessScalar
    end

    normalize_place = function(place, ptr_offsets, view_data, inductions, value_ops)
        local cls = pvm.classof(place)
        if cls == Code.CodePlaceLocal then
            return Mem.MemBaseLocal(place["local"]), Mem.MemIndexNone, Mem.MemAccessScalar, Mem.MemBoundsInObject("local storage")
        elseif cls == Code.CodePlaceGlobal then
            return Mem.MemBaseGlobal(place.global), Mem.MemIndexNone, Mem.MemAccessScalar, Mem.MemBoundsInObject("global storage")
        elseif cls == Code.CodePlaceData then
            return Mem.MemBaseData(place.data), Mem.MemIndexNone, Mem.MemAccessScalar, Mem.MemBoundsInObject("data object")
        elseif cls == Code.CodePlaceDeref then
            local base, index, pattern = normalize_addr(place.addr, place.ty, ptr_offsets, view_data, inductions, value_ops)
            return base, index, pattern, Mem.MemBoundsUnknown("deref bounds require Mem/contract proof")
        elseif cls == Code.CodePlaceIndex then
            local base, _, _, bounds = normalize_place(place.base, ptr_offsets, view_data, inductions, value_ops)
            local index = combine_index(nil, place.index, place.elem_size, 0, inductions, value_ops)
            local pattern = pvm.classof(index) == Mem.MemIndexInduction and Mem.MemAccessContiguous or Mem.MemAccessUnknown
            return base, index, pattern, bounds or Mem.MemBoundsUnknown("indexed place bounds unknown")
        elseif cls == Code.CodePlaceField then
            local base, index, pattern, bounds = normalize_place(place.base, ptr_offsets, view_data, inductions, value_ops)
            return derived_base(base, "field offset " .. tostring(place.offset or 0)), index, pattern, bounds or Mem.MemBoundsInObject("field in object")
        elseif cls == Code.CodePlaceBytes then
            return derived_base(Mem.MemBaseValue(place.base), "byte offset " .. tostring(place.offset or 0)), Mem.MemIndexNone, Mem.MemAccessScalar, Mem.MemBoundsUnknown("byte place bounds unknown")
        end
        return Mem.MemBaseUnknown("unsupported CodePlace " .. tostring(cls)), Mem.MemIndexNone, Mem.MemAccessUnknown, Mem.MemBoundsUnknown("unsupported place")
    end

    local function refine_pattern(kind, index, pattern)
        if pattern ~= Mem.MemAccessUnknown then return pattern end
        local icls = pvm.classof(index)
        if icls == Mem.MemIndexInduction then return Mem.MemAccessContiguous end
        if icls == Mem.MemIndexValue then
            if kind == Mem.MemStore or kind == Mem.MemAtomicStore or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas then return Mem.MemAccessScatter end
            return Mem.MemAccessGather
        end
        return Mem.MemAccessScalar
    end

    local function inst_access(inst_kind)
        local cls = pvm.classof(inst_kind)
        if cls == Code.CodeInstLoad then return inst_kind.place, inst_kind.access, inst_kind.dst end
        if cls == Code.CodeInstStore then return inst_kind.place, inst_kind.access, nil end
        if cls == Code.CodeInstAtomicLoad then return inst_kind.place, inst_kind.access, inst_kind.dst end
        if cls == Code.CodeInstAtomicStore then return inst_kind.place, inst_kind.access, nil end
        if cls == Code.CodeInstAtomicRmw then return inst_kind.place, inst_kind.access, inst_kind.dst end
        if cls == Code.CodeInstAtomicCas then return inst_kind.place, inst_kind.access, inst_kind.dst end
        return nil, nil, nil
    end

    local function analyze_func(func, flow, out_accesses)
        local inductions = flow_inductions(flow)
        local ptr_offsets, view_data, value_ops = value_defs(func)
        local ordinal = 0
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local kind = access_kind(k)
                if kind ~= nil then
                    ordinal = ordinal + 1
                    local place, access = inst_access(k)
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstLoad or cls == Code.CodeInstAtomicLoad then
                        assert_access_mode(inst.id.text, access, { [Code.CodeMemoryRead] = true, [Code.CodeMemoryReadWrite] = true })
                    elseif cls == Code.CodeInstStore or cls == Code.CodeInstAtomicStore then
                        assert_access_mode(inst.id.text, access, { [Code.CodeMemoryWrite] = true, [Code.CodeMemoryReadWrite] = true })
                    else
                        assert_access_mode(inst.id.text, access, { [Code.CodeMemoryReadWrite] = true })
                    end
                    if access.ty ~= nil and place.ty ~= nil and access.ty ~= place.ty then
                        error(inst.id.text .. ": CodeMemoryAccess type does not match CodePlace type", 2)
                    end
                    local base, index, pattern, bounds = normalize_place(place, ptr_offsets, view_data, inductions, value_ops)
                    pattern = refine_pattern(kind, index, pattern)
                    out_accesses[#out_accesses + 1] = Mem.MemAccessFact(
                        access_id(func, inst, ordinal),
                        func.id,
                        block.id,
                        inst.id,
                        kind,
                        place,
                        access,
                        base,
                        index,
                        pattern,
                        alignment_fact(access),
                        bounds,
                        trap_fact(access)
                    )
                end
            end
        end
    end

    local function alias_facts(accesses)
        local out = {}
        for i = 1, #accesses do
            for j = i + 1, #accesses do
                out[#out + 1] = Mem.MemAliasUnknown(accesses[i].id, accesses[j].id, "code_mem_facts foundation is conservative")
            end
        end
        return out
    end

    local function is_write(kind)
        return kind == Mem.MemStore or kind == Mem.MemAtomicStore or kind == Mem.MemAtomicRmw or kind == Mem.MemAtomicCas
    end

    local function dependence_facts(accesses)
        local out = {}
        for i = 1, #accesses do
            for j = i + 1, #accesses do
                if is_write(accesses[i].kind) or is_write(accesses[j].kind) then
                    out[#out + 1] = Mem.MemDependenceUnknown(accesses[i].id, accesses[j].id, "dependence analysis deferred")
                end
            end
        end
        return out
    end

    local function block_loops(flow)
        local out = {}
        for _, loop in ipairs(flow and flow.loops or {}) do
            for _, block in ipairs(loop.body_blocks or {}) do
                out[block.text] = loop.id
            end
        end
        return out
    end

    local function flow_semantic_ranges(flow_semantics)
        local out = {}
        for _, fact in ipairs(flow_semantics and flow_semantics.facts or {}) do
            if pvm.classof(fact) == Flow.FlowLoopInductionRange then
                local range = fact.range
                out[range.loop.text .. ":" .. range.value.text] = range
            end
        end
        return out
    end

    local function bound_const(bound, raw)
        return pvm.classof(bound) == Flow.FlowBoundConst and tostring(bound.raw) == tostring(raw)
    end

    local function object_by_id(objects)
        local out = {}
        for _, object in ipairs(objects or {}) do out[object.id.text] = object end
        return out
    end

    local mem_base_value
    mem_base_value = function(base)
        local cls = pvm.classof(base)
        if cls == Mem.MemBaseValue then return base.value end
        if cls == Mem.MemBaseArgument then return base.value end
        if cls == Mem.MemBaseDerived then return mem_base_value(base.base) end
        return nil
    end

    local function access_elem_size(access)
        local bytes = type_size_bytes(access.access and access.access.ty)
        if bytes ~= nil then return bytes end
        local cls = pvm.classof(access.index)
        if cls == Mem.MemIndexInduction or cls == Mem.MemIndexValue then return access.index.elem_size end
        return nil
    end

    local function index_const_offset(index)
        local cls = pvm.classof(index)
        if cls == Mem.MemIndexInduction or cls == Mem.MemIndexValue then return index.const_offset or 0 end
        return 0
    end

    local function stride_has_static_interval_proof(stride)
        if stride == Mem.MemStrideUnit then return true end
        if pvm.classof(stride) == Mem.MemStrideConstElems then return type(stride.elems) == "number" and stride.elems > 0 end
        return false
    end

    local function has_loop_range_proof(access, object, loop_id, ranges)
        if object == nil or pvm.classof(object.extent) ~= Mem.MemExtentElements then return false end
        if not stride_has_static_interval_proof(object.stride) then return false end
        if loop_id == nil or pvm.classof(access.index) ~= Mem.MemIndexInduction then return false end
        local range = ranges[loop_id.text .. ":" .. access.index.induction.value.text]
        if range == nil or not range.max_exclusive then return false end
        if not bound_const(range.min, "0") then return false end
        if pvm.classof(range.max) ~= Flow.FlowBoundValue or range.max.value ~= object.extent.len then return false end
        if index_const_offset(access.index) ~= 0 then return false end
        return true
    end

    local function has_scalar_object_proof(access, object)
        if object == nil or pvm.classof(access.index) ~= Mem.MemIndexNone then return false end
        if pvm.classof(access.bounds) == Mem.MemBoundsInObject then return true end
        local extent = object.extent
        if pvm.classof(extent) ~= Mem.MemExtentBytes then return false end
        local bytes = access_elem_size(access)
        return bytes ~= nil and bytes <= extent.bytes
    end

    local function safety_from_semantics(accesses, objects, by_func, flow, flow_semantics)
        local object_map = object_by_id(objects)
        local loops = block_loops(flow)
        local ranges = flow_semantic_ranges(flow_semantics)
        local intervals, safety, proofs = {}, {}, {}

        for _, access in ipairs(accesses or {}) do
            local func_ctx = by_func[access.func.text]
            local object_id_for_access = func_ctx and func_ctx.object_for_place and func_ctx.object_for_place(access.place) or nil
            local object = object_id_for_access and object_map[object_id_for_access.text] or nil
            if object ~= nil then
                local elem_size = access_elem_size(access)
                if elem_size ~= nil then
                    local loop_id = loops[access.block.text]
                    local interval = Mem.MemAccessInterval(
                        access.id,
                        object.id,
                        loop_id,
                        access.index,
                        Flow.FlowBoundConst("1"),
                        elem_size,
                        index_const_offset(access.index),
                        "normalized access interval over structured memory object"
                    )
                    intervals[#intervals + 1] = interval

                    local proved = has_loop_range_proof(access, object, loop_id, ranges) or has_scalar_object_proof(access, object)
                    if proved then
                        local proof = Mem.MemProofInterval(interval, "access interval is contained in structured memory object extent")
                        proofs[#proofs + 1] = proof
                        safety[#safety + 1] = Mem.MemAccessInBounds(interval, proof)
                        safety[#safety + 1] = Mem.MemAccessNonTrap(access.id, proof)
                        safety[#safety + 1] = Mem.MemAccessDerefBytes(access.id, elem_size, proof)
                        if type(access.access.align) == "number" and access.access.align >= 1 then
                            safety[#safety + 1] = Mem.MemAccessAlignKnown(access.id, access.access.align, proof)
                        end
                        if access.kind == Mem.MemLoad and not access.access.volatile then
                            safety[#safety + 1] = Mem.MemAccessMovable(access.id, proof)
                        end
                    end
                end
            end
        end

        return intervals, safety, proofs
    end

    local function contract_noalias_for(cidx, func_id, value)
        if value == nil then return nil end
        return cidx.noalias[func_id.text .. "\0" .. value.text]
    end

    local function contract_disjoint_for(cidx, func_id, a, b)
        if a == nil or b == nil then return nil end
        return cidx.disjoint[func_id.text .. "\0" .. a.text .. "\0" .. b.text]
            or contract_noalias_for(cidx, func_id, a)
            or contract_noalias_for(cidx, func_id, b)
    end

    local function contract_dependences(accesses, contracts)
        local cidx = contract_index(contracts)
        local dependences, proofs = {}, {}
        for i = 1, #(accesses or {}) do
            for j = i + 1, #(accesses or {}) do
                local a, b = accesses[i], accesses[j]
                if a.func == b.func then
                    if not is_write(a.kind) and not is_write(b.kind) then
                        dependences[#dependences + 1] = Mem.MemReadReadIndependent(a.id, b.id, "read/read streams are dependence-independent")
                    elseif is_write(a.kind) or is_write(b.kind) then
                        local av, bv = mem_base_value(a.base), mem_base_value(b.base)
                        local contract = contract_disjoint_for(cidx, a.func, av, bv)
                        if contract ~= nil then
                            local proof = Mem.MemProofContract(contract, "contract proves write-related streams are independent")
                            proofs[#proofs + 1] = proof
                            dependences[#dependences + 1] = Mem.MemNoDependence(a.id, b.id, proof)
                        end
                    end
                end
            end
        end
        return dependences, proofs
    end

    local function contract_effects(by_func, contracts)
        local cidx = contract_index(contracts)
        local effects, proofs = {}, {}
        for func_key, facts in pairs(cidx.facts or {}) do
            local func_objects = by_func[func_key]
            local value_object = func_objects and func_objects.value_object or {}
            for _, fact in ipairs(facts) do
                local cls = pvm.classof(fact.fact)
                if cls == Code.CodeContractReadonly or cls == Code.CodeContractWriteonly then
                    local object = value_object[fact.fact.base.text]
                    if object ~= nil then
                        local proof = Mem.MemProofContract(fact, "object access-effect contract")
                        proofs[#proofs + 1] = proof
                        if cls == Code.CodeContractReadonly then
                            effects[#effects + 1] = Mem.MemObjectReadonly(object, proof)
                        else
                            effects[#effects + 1] = Mem.MemObjectWriteonly(object, proof)
                        end
                    end
                end
            end
        end
        return effects, proofs
    end

    local function contract_relations(by_func, contracts)
        local cidx = contract_index(contracts)
        local relations, proofs = {}, {}
        for func_key, facts in pairs(cidx.facts or {}) do
            local func_objects = by_func[func_key]
            local value_object = func_objects and func_objects.value_object or {}
            for _, fact in ipairs(facts) do
                local k = fact.fact
                local cls = pvm.classof(k)
                if cls == Code.CodeContractSameLen then
                    local a, b = value_object[k.a.text], value_object[k.b.text]
                    if a ~= nil and b ~= nil then
                        local proof = Mem.MemProofContract(fact, "same_len contract relates object extents")
                        proofs[#proofs + 1] = proof
                        relations[#relations + 1] = Mem.MemObjectsSameLen(a, b, proof)
                    end
                elseif cls == Code.CodeContractWindowBounds then
                    local object = value_object[k.base.text]
                    if object ~= nil then
                        local proof = Mem.MemProofContract(fact, "window_bounds contract proves a bounded object window")
                        proofs[#proofs + 1] = proof
                        relations[#relations + 1] = Mem.MemObjectWindowBounds(object, k.base_len, k.start, k.len, proof)
                    end
                end
            end
        end
        return relations, proofs
    end

    local function facts(module, flow)
        local accesses = {}
        for _, func in ipairs(module.funcs or {}) do analyze_func(func, flow, accesses) end
        return Mem.MemFactSet(module.id, accesses, alias_facts(accesses), dependence_facts(accesses), {})
    end

    local function semantic_facts(module, flow, flow_semantics, contracts)
        local objects, by_func = semantic_objects(module, contracts)
        local accesses = {}
        for _, func in ipairs(module.funcs or {}) do analyze_func(func, flow, accesses) end
        local intervals, safety, proofs = safety_from_semantics(accesses, objects, by_func, flow, flow_semantics)
        local dependences, dep_proofs = contract_dependences(accesses, contracts)
        for _, proof in ipairs(dep_proofs) do proofs[#proofs + 1] = proof end
        local effects, effect_proofs = contract_effects(by_func, contracts)
        for _, proof in ipairs(effect_proofs) do proofs[#proofs + 1] = proof end
        local relations, relation_proofs = contract_relations(by_func, contracts)
        for _, proof in ipairs(relation_proofs) do proofs[#proofs + 1] = proof end
        return Mem.MemSemanticFactSet(module.id, objects, intervals, safety, effects, dependences, relations, proofs)
    end

    api.facts = facts
    api.module = facts
    api.semantic_facts = semantic_facts
    api.semantics = semantic_facts

    T._moonlift_api_cache.code_mem_facts = api
    return api
end

return M
