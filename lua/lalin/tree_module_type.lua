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

local function bind_context(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree

    local layout_api = require("lalin.type_size_align")(T)

    local module_name
    local func_entry
    local extern_entry
    local const_entry
    local static_entry
    local type_entry
    local item_env_entries
    local module_env
    local item_layout

    local function pack(g, p, c) return { g, p, c } end

    function Tr.ModuleHeader:tree_module_name()
        error("phase lalin_tree_module_name: no handler for " .. tostring(schema.classof(self) or type(self)), 2)
    end

    function Tr.ModuleTyped:tree_module_name()
        return self.module_name
    end

    function Tr.ModuleSem:tree_module_name()
        return self.module_name
    end

    function Tr.ModuleCode:tree_module_name()
        return self.module_name
    end

    function Tr.ModuleSurface:tree_module_name()
        return ""
    end


    local function path_type_name(path)
        if path and #(path.parts or {}) == 1 then return path.parts[1].text end
        return nil
    end

    function Ty.Type:tree_module_canonicalize(mod_name)
        return self
    end

    function Ty.TNamed:tree_module_canonicalize(mod_name)
        if schema.classof(self.ref) == Ty.TypeRefPath then
            local name = path_type_name(self.ref.path)
            if name ~= nil then return Ty.TNamed(Ty.TypeRefGlobal(mod_name, name)) end
        end
        return self
    end

    function Ty.THandle:tree_module_canonicalize(mod_name)
        if schema.classof(self.ref) == Ty.TypeRefPath then
            local name = path_type_name(self.ref.path)
            if name ~= nil then return Ty.THandle(Ty.TypeRefGlobal(mod_name, name), self.repr) end
        end
        return self
    end

    function Ty.TPtr:tree_module_canonicalize(mod_name)
        return Ty.TPtr(self.elem:tree_module_canonicalize(mod_name))
    end

    function Ty.TArray:tree_module_canonicalize(mod_name)
        return Ty.TArray(self.count, self.elem:tree_module_canonicalize(mod_name))
    end

    function Ty.TSlice:tree_module_canonicalize(mod_name)
        return Ty.TSlice(self.elem:tree_module_canonicalize(mod_name))
    end

    function Ty.TView:tree_module_canonicalize(mod_name)
        return Ty.TView(self.elem:tree_module_canonicalize(mod_name))
    end

    function Ty.TLease:tree_module_canonicalize(mod_name)
        return Ty.TLease(self.base:tree_module_canonicalize(mod_name), self.origin)
    end

    function Ty.TOwned:tree_module_canonicalize(mod_name)
        return Ty.TOwned(self.base:tree_module_canonicalize(mod_name))
    end

    function Ty.TAccess:tree_module_canonicalize(mod_name)
        return Ty.TAccess(self.access, self.base:tree_module_canonicalize(mod_name))
    end

    function Ty.TFunc:tree_module_canonicalize(mod_name)
        local params = {}
        for i = 1, #(self.params or {}) do params[i] = self.params[i]:tree_module_canonicalize(mod_name) end
        return Ty.TFunc(params, self.result:tree_module_canonicalize(mod_name))
    end

    function Ty.TClosure:tree_module_canonicalize(mod_name)
        local params = {}
        for i = 1, #(self.params or {}) do params[i] = self.params[i]:tree_module_canonicalize(mod_name) end
        return Ty.TClosure(params, self.result:tree_module_canonicalize(mod_name))
    end

    local function params_type(params, result, mod_name)
        local tys = {}
        for i = 1, #params do tys[#tys + 1] = params[i].ty:tree_module_canonicalize(mod_name or "") end
        return Ty.TFunc(tys, result:tree_module_canonicalize(mod_name or ""))
    end

    function Tr.Func:tree_module_func_entry(input)
        error("phase lalin_tree_func_value_entry: no handler for " .. tostring(schema.classof(self) or type(self)), 2)
    end

    function Tr.FuncLocal:tree_module_func_entry(input)
        local ty = params_type(self.params, self.result, input.mod_name)
        return { B.ValueEntry(self.name, B.Binding(C.Id("func:" .. input.mod_name .. ":" .. self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name))) }
    end

    function Tr.FuncExport:tree_module_func_entry(input)
        local ty = params_type(self.params, self.result, input.mod_name)
        return { B.ValueEntry(self.name, B.Binding(C.Id("func:" .. input.mod_name .. ":" .. self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name))) }
    end

    function Tr.FuncLocalContract:tree_module_func_entry(input)
        local ty = params_type(self.params, self.result, input.mod_name)
        return { B.ValueEntry(self.name, B.Binding(C.Id("func:" .. input.mod_name .. ":" .. self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name))) }
    end

    function Tr.FuncExportContract:tree_module_func_entry(input)
        local ty = params_type(self.params, self.result, input.mod_name)
        return { B.ValueEntry(self.name, B.Binding(C.Id("func:" .. input.mod_name .. ":" .. self.name), self.name, ty, B.BindingRoleGlobalFunc(input.mod_name, self.name))) }
    end

    function Tr.ExternFunc:tree_module_extern_entry()
        return { B.ValueEntry(self.name, B.Binding(C.Id("extern:" .. self.name), self.name, params_type(self.params, self.result, ""), B.BindingRoleExtern(self.symbol))) }
    end

    function Tr.ConstItem:tree_module_const_entry(input)
        return { B.ValueEntry(self.name, B.Binding(C.Id("const:" .. input.mod_name .. ":" .. self.name), self.name, self.ty, B.BindingRoleGlobalConst(input.mod_name, self.name))) }
    end

    function Tr.StaticItem:tree_module_static_entry(input)
        return { B.ValueEntry(self.name, B.Binding(C.Id("static:" .. input.mod_name .. ":" .. self.name), self.name, self.ty, B.BindingRoleGlobalStatic(input.mod_name, self.name))) }
    end


    function Tr.TypeDecl:tree_module_type_entry(input)
        error("phase lalin_tree_type_entry: no handler for " .. tostring(schema.classof(self) or type(self)), 2)
    end

    function Tr.TypeDeclStruct:tree_module_type_entry(input)
        return { B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name))) }
    end

    function Tr.TypeDeclUnion:tree_module_type_entry(input)
        return { B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name))) }
    end

    function Tr.TypeDeclEnumSugar:tree_module_type_entry(input)
        return { B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name))) }
    end

    function Tr.TypeDeclTaggedUnionSugar:tree_module_type_entry(input)
        return { B.TypeEntry(self.name, Ty.TNamed(Ty.TypeRefGlobal(input.mod_name, self.name))) }
    end

    function Tr.TypeDeclHandle:tree_module_type_entry(input)
        return { B.TypeEntry(self.name, Ty.THandle(Ty.TypeRefGlobal(input.mod_name, self.name), self.repr)) }
    end


    local function align_up(x, a)
        if a <= 1 then return x end
        return math.floor((x + a - 1) / a) * a
    end

    local function tag_ty() return Ty.TScalar(C.ScalarU32) end
    local function payload_byte_array(size) return Ty.TArray(Ty.ArrayLenConst(size), Ty.TScalar(C.ScalarU8)) end

    local function field_layout(fields, env, is_union, target)
        local out, offset, max_size, max_align = {}, 0, 0, 1
        for i = 1, #fields do
            local r = layout_api.result(fields[i].ty, env, target)
            local size, align = 0, 1
            if schema.classof(r) == Ty.TypeMemLayoutKnown then size, align = r.layout.size, r.layout.align end
            if is_union then
                out[#out + 1] = Sem.FieldLayout(fields[i].field_name, 0, fields[i].ty)
                if size > max_size then max_size = size end
                if align > max_align then max_align = align end
            else
                offset = align_up(offset, align)
                out[#out + 1] = Sem.FieldLayout(fields[i].field_name, offset, fields[i].ty)
                offset = offset + size
                if align > max_align then max_align = align end
            end
        end
        local size = is_union and max_size or offset
        return out, align_up(size, max_align), max_align
    end

    function Tr.Item:tree_module_item_layout(input)
        return {}
    end

    function Tr.ItemType:tree_module_item_layout(input)
        return self.t:tree_module_type_layout(input)
    end

    function Tr.TypeDecl:tree_module_type_layout(input)
        return {}
    end

    function Tr.TypeDeclStruct:tree_module_type_layout(input)
        local fields, size, align = field_layout(self.fields, input.env, false, input.target)
        return { Sem.LayoutNamed(input.mod_name, self.name, fields, size, align) }
    end

    function Tr.TypeDeclUnion:tree_module_type_layout(input)
        local fields, size, align = field_layout(self.fields, input.env, true, input.target)
        return { Sem.LayoutNamed(input.mod_name, self.name, fields, size, align) }
    end

    function Tr.TypeDeclEnumSugar:tree_module_type_layout(input)
        local tag_layout = layout_api.result(tag_ty(), input.env, input.target).layout
        return { Sem.LayoutNamed(input.mod_name, self.name, { Sem.FieldLayout("__tag", 0, tag_ty()) }, tag_layout.size, tag_layout.align) }
    end

    function Tr.TypeDeclHandle:tree_module_type_layout(input)
        local repr_ty = Ty.THandle(Ty.TypeRefGlobal(input.mod_name, self.name), self.repr)
        local layout = layout_api.result(repr_ty, input.env, input.target).layout
        return { Sem.LayoutNamed(input.mod_name, self.name, { Sem.FieldLayout("__handle", 0, repr_ty) }, layout.size, layout.align) }
    end

    function Tr.TypeDeclTaggedUnionSugar:tree_module_type_layout(input)
        local tag_layout = layout_api.result(tag_ty(), input.env, input.target).layout
        local payload_size, payload_align = 0, 1
        for i = 1, #self.variants do
            local v = self.variants[i]
            local sz, al
            if #(v.fields or {}) > 0 then
                local _, fsz, fal = field_layout(v.fields, input.env, false, input.target)
                sz, al = fsz, fal
            else
                local r = layout_api.result(v.payload, input.env, input.target)
                local l = schema.classof(r) == Ty.TypeMemLayoutKnown and r.layout or Sem.MemLayout(0, 1)
                sz, al = l.size, l.align
            end
            if sz > payload_size then payload_size = sz end
            if al > payload_align then payload_align = al end
        end
        local fields = { Sem.FieldLayout("__tag", 0, tag_ty()) }
        local size, align = tag_layout.size, tag_layout.align
        if payload_size > 0 then
            local payload_offset = align_up(tag_layout.size, payload_align)
            fields[#fields + 1] = Sem.FieldLayout("__payload", payload_offset, payload_byte_array(payload_size))
            size = payload_offset + payload_size
            if payload_align > align then align = payload_align end
        end
        return { Sem.LayoutNamed(input.mod_name, self.name, fields, align_up(size, align), align) }
    end


    function Tr.Item:tree_module_item_env_entries(input)
        error("phase lalin_tree_item_env_entries: no handler for " .. tostring(schema.classof(self) or type(self)), 2)
    end

    function Tr.ItemFunc:tree_module_item_env_entries(input)
        return self.func:tree_module_func_entry(input)
    end

    function Tr.ItemExtern:tree_module_item_env_entries(input)
        return self.func:tree_module_extern_entry()
    end

    function Tr.ItemConst:tree_module_item_env_entries(input)
        return self.c:tree_module_const_entry(input)
    end

    function Tr.ItemStatic:tree_module_item_env_entries(input)
        return self.s:tree_module_static_entry(input)
    end

    function Tr.ItemType:tree_module_item_env_entries(input)
        return self.t:tree_module_type_entry(input)
    end

    function Tr.ItemImport:tree_module_item_env_entries(input)
        return {}
    end

    function Tr.ItemRegion:tree_module_item_env_entries(input)
        return {}
    end

    function Tr.ItemData:tree_module_item_env_entries(input)
        return {}
    end


    function module_env(node, ...)
        local cls = schema.classof(node)
        if schema.isa(node, Tr.Module) then
            return (function(module, target)

            local mod_name = module.h:tree_module_name()
            local values = {}
            local types = {}
            local layouts = {}
            for i = 1, #module.items do
                local entries = module.items[i]:tree_module_item_env_entries(Sem.TreeModuleEntryInput(mod_name))
                for j = 1, #entries do
                    if schema.classof(entries[j]) == B.ValueEntry then values[#values + 1] = entries[j] end
                    if schema.classof(entries[j]) == B.TypeEntry then types[#types + 1] = entries[j] end
                end
            end
            for _ = 1, math.max(1, #module.items) do
                local pass_layouts = {}
                local layout_env = Sem.LayoutEnv(layouts)
                for i = 1, #module.items do
                    local ls = module.items[i]:tree_module_item_layout(Sem.TreeModuleLayoutInput(mod_name, layout_env, target))
                    for j = 1, #ls do pass_layouts[#pass_layouts + 1] = ls[j] end
                end
                layouts = pass_layouts
            end
            return single(B.Env(mod_name, values, types, layouts))
            end)(node, ...)
        else
            error("phase lalin_tree_module_env: no handler for " .. tostring(cls or type(node)), 2)
        end
    end

    return {
        module_name = module_name,
        item_env_entries = item_env_entries,
        module_env = module_env,
        env = function(module, target) return only(module_env(module, target)) end,
    }
end

return bind_context
