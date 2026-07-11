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
    local Sem = T.LalinSem
    local Tr = T.LalinTree
    local H = T.LalinHost

    local module_type_api = require("lalin.tree_module_type")(T)

    local function index_ty() return Ty.TScalar(C.ScalarIndex) end

    local resolve_expr

    local function one(phase, node, env, target)
        return only(phase(node, env, target))
    end


    local function map_exprs(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = one(resolve_expr, xs[i], env, target) end
        return out
    end

    local function map_stmts(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = only(xs[i]:sem_layout_resolve(env, target)) end
        return out
    end

    local function map_jump_args(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = schema.with(xs[i], { value = one(resolve_expr, xs[i].value, env, target) }) end
        return out
    end

    local function map_items(xs, env, target)
        local out = {}
        for i = 1, #xs do out[#out + 1] = only(xs[i]:sem_layout_resolve(env, target)) end
        return out
    end

    function Sem.TypeLayoutMissing:sem_layout_or_else(candidate)
        return candidate
    end

    function Sem.TypeLayoutFound:sem_layout_or_else(candidate)
        return self
    end

    function Ty.TypeRefGlobal:sem_layout_match_named(layout)
        if layout.module_name == self.module_name and layout.type_name == self.type_name then
            return Sem.TypeLayoutFound(layout)
        end
        return Sem.TypeLayoutMissing
    end

    function Ty.TypeRefGlobal:sem_layout_match_local(layout)
        return Sem.TypeLayoutMissing
    end

    function Ty.TypeRefLocal:sem_layout_match_named(layout)
        return Sem.TypeLayoutMissing
    end

    function Ty.TypeRefLocal:sem_layout_match_local(layout)
        if layout.sym == self.sym then return Sem.TypeLayoutFound(layout) end
        return Sem.TypeLayoutMissing
    end

    function Ty.TypeRefPath:sem_layout_match_named(layout)
        if #self.path.parts == 1 and layout.type_name == self.path.parts[1].text then
            return Sem.TypeLayoutFound(layout)
        end
        return Sem.TypeLayoutMissing
    end

    function Ty.TypeRefPath:sem_layout_match_local(layout)
        return Sem.TypeLayoutMissing
    end

    function Sem.LayoutNamed:sem_layout_match_ref(ref)
        return ref:sem_layout_match_named(self)
    end

    function Sem.LayoutLocal:sem_layout_match_ref(ref)
        return ref:sem_layout_match_local(self)
    end

    local function resolve_type_layout(ref, env)
        local result = Sem.TypeLayoutMissing
        for i = 1, #env.layouts do
            result = result:sem_layout_or_else(env.layouts[i]:sem_layout_match_ref(ref))
        end
        return result
    end

    function Ty.TypeRefGlobal:sem_layout_resolve(env)
        return resolve_type_layout(self, env)
    end

    function Ty.TypeRefLocal:sem_layout_resolve(env)
        return resolve_type_layout(self, env)
    end

    function Ty.TypeRefPath:sem_layout_resolve(env)
        return resolve_type_layout(self, env)
    end

    function Ty.Type:sem_layout(env)
        return Sem.TypeLayoutMissing
    end

    function Ty.TNamed:sem_layout(env)
        return self.ref:sem_layout_resolve(env)
    end

    function Sem.FieldLayoutMissing:sem_layout_or_else(candidate)
        return candidate
    end

    function Sem.FieldLayoutFound:sem_layout_or_else(candidate)
        return self
    end

    local function find_layout_field(layout, field_name)
        local result = Sem.FieldLayoutMissing
        for i = 1, #layout.fields do
            local field = layout.fields[i]
            local candidate = Sem.FieldLayoutMissing
            if field.field_name == field_name then candidate = Sem.FieldLayoutFound(field) end
            result = result:sem_layout_or_else(candidate)
        end
        return result
    end

    function Sem.LayoutNamed:sem_layout_field(field_name)
        return find_layout_field(self, field_name)
    end

    function Sem.LayoutLocal:sem_layout_field(field_name)
        return find_layout_field(self, field_name)
    end


    function Ty.Type:sem_layout_storage()
        return H.HostRepOpaque("sem_layout")
    end

    function Ty.TScalar:sem_layout_storage()
        return H.HostRepScalar(self.scalar)
    end

    function Ty.TPtr:sem_layout_storage()
        return H.HostRepPtr(self.elem)
    end

    function Ty.TView:sem_layout_storage()
        return H.HostRepView(self.elem)
    end

    function Ty.TAccess:sem_layout_storage()
        return self.base:sem_layout_storage()
    end

    function Ty.Type:sem_layout_field_base_type()
        return self
    end

    function Ty.TPtr:sem_layout_field_base_type()
        return self.elem:sem_layout_field_base_type()
    end

    function Ty.TAccess:sem_layout_field_base_type()
        return self.base:sem_layout_field_base_type()
    end

    function Ty.TLease:sem_layout_field_base_type()
        return self.base:sem_layout_field_base_type()
    end

    function Sem.TypeLayoutMissing:sem_layout_resolve_field(field)
        return field
    end

    function Sem.TypeLayoutFound:sem_layout_resolve_field(field)
        return self.layout:sem_layout_field(field.field_name):sem_layout_resolve_field(field)
    end

    function Sem.FieldLayoutMissing:sem_layout_resolve_field(field)
        return field
    end

    function Sem.FieldLayoutFound:sem_layout_resolve_field(field)
        local resolved = self.layout
        return Sem.FieldByOffset(resolved.field_name, resolved.offset, resolved.ty, resolved.ty:sem_layout_storage())
    end

    function Sem.FieldByOffset:sem_resolve_field_ref(base_ty, env)
        return self
    end

    function Sem.FieldByName:sem_resolve_field_ref(base_ty, env)
        return base_ty:sem_layout(env):sem_layout_resolve_field(self)
    end

    function Tr.PlaceSurface:sem_layout_value_type()
        return Sem.LayoutValueUntyped
    end

    function Tr.PlaceTyped:sem_layout_value_type()
        return Sem.LayoutValueTyped(self.ty)
    end

    function Tr.ExprSurface:sem_layout_value_type()
        return Sem.LayoutValueUntyped
    end

    function Tr.ExprTyped:sem_layout_value_type()
        return Sem.LayoutValueTyped(self.ty)
    end

    function Sem.LayoutValueUntyped:sem_layout_resolve_field(field, env)
        return field
    end

    function Sem.LayoutValueTyped:sem_layout_resolve_field(field, env)
        return field:sem_resolve_field_ref(self.ty:sem_layout_field_base_type(), env)
    end


    function Sem.LayoutValueUntyped:sem_layout_place_dot(dot, base, env)
        return { schema.with(dot, { base = base }) }
    end

    function Sem.LayoutValueTyped:sem_layout_place_dot(dot, base, env)
        local base_ty = self.ty:sem_layout_field_base_type()
        local field = Sem.FieldByName(dot.name, base_ty):sem_resolve_field_ref(base_ty, env)
        return field:sem_layout_place_dot(dot, base)
    end

    function Sem.LayoutValueUntyped:sem_layout_expr_dot(dot, base, env)
        return { schema.with(dot, { base = base }) }
    end

    function Sem.LayoutValueTyped:sem_layout_expr_dot(dot, base, env)
        local base_ty = self.ty:sem_layout_field_base_type()
        local field = Sem.FieldByName(dot.name, base_ty):sem_resolve_field_ref(base_ty, env)
        return field:sem_layout_expr_dot(dot, base)
    end

    function Sem.FieldByName:sem_layout_place_dot(dot, base)
        return { schema.with(dot, { base = base }) }
    end

    function Sem.FieldByOffset:sem_layout_place_dot(dot, base)
        return { Tr.PlaceField(Tr.PlaceTyped(self.ty), base, self) }
    end

    function Sem.FieldByName:sem_layout_expr_dot(dot, base)
        return { schema.with(dot, { base = base }) }
    end

    function Sem.FieldByOffset:sem_layout_expr_dot(dot, base)
        return { Tr.ExprField(Tr.ExprTyped(self.ty), base, self) }
    end

    function Tr.TypeDecl:sem_layout_resolve()
        return { self }
    end

    function Tr.Place:sem_layout_resolve(env, target)
        return { self }
    end

    function Tr.PlaceDeref:sem_layout_resolve(env, target)
        return { schema.with(self, { base = one(resolve_expr, self.base, env, target) }) }
    end

    function Tr.PlaceDot:sem_layout_resolve(env, target)
        local base = only(self.base:sem_layout_resolve(env, target))
        return base.h:sem_layout_value_type():sem_layout_place_dot(self, base, env)
    end

    function Tr.PlaceField:sem_layout_resolve(env, target)
        local base = only(self.base:sem_layout_resolve(env, target))
        local field = base.h:sem_layout_value_type():sem_layout_resolve_field(self.field, env)
        return { schema.with(self, { base = base, field = field }) }
    end

    function Tr.IndexBaseExpr:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target) })
    end

    function Tr.IndexBasePlace:sem_layout_resolve(env, target)
        return schema.with(self, { base = only(self.base:sem_layout_resolve(env, target)) })
    end

    function Tr.IndexBaseView:sem_layout_resolve(env, target)
        return schema.with(self, { view = only(self.view:sem_layout_resolve(env, target)) })
    end

    function Tr.PlaceIndex:sem_layout_resolve(env, target)
        return { schema.with(self, { base = self.base:sem_layout_resolve(env, target), index = one(resolve_expr, self.index, env, target) }) }
    end


    function Tr.ViewFromExpr:sem_layout_resolve(env, target)
        return { schema.with(self, { base = one(resolve_expr, self.base, env, target) }) }
    end

    function Tr.ViewContiguous:sem_layout_resolve(env, target)
        return { schema.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target) }) }
    end

    function Tr.ViewStrided:sem_layout_resolve(env, target)
        return { schema.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target), stride = one(resolve_expr, self.stride, env, target) }) }
    end

    function Tr.ViewRestrided:sem_layout_resolve(env, target)
        return { schema.with(self, { base = only(self.base:sem_layout_resolve(env, target)), stride = one(resolve_expr, self.stride, env, target) }) }
    end

    function Tr.ViewWindow:sem_layout_resolve(env, target)
        return { schema.with(self, { base = only(self.base:sem_layout_resolve(env, target)), start = one(resolve_expr, self.start, env, target), len = one(resolve_expr, self.len, env, target) }) }
    end

    function Tr.ViewRowBase:sem_layout_resolve(env, target)
        return { schema.with(self, { base = only(self.base:sem_layout_resolve(env, target)), row_offset = one(resolve_expr, self.row_offset, env, target) }) }
    end

    function Tr.ViewInterleaved:sem_layout_resolve(env, target)
        return { schema.with(self, { data = one(resolve_expr, self.data, env, target), len = one(resolve_expr, self.len, env, target), stride = one(resolve_expr, self.stride, env, target), lane = one(resolve_expr, self.lane, env, target) }) }
    end

    function Tr.ViewInterleavedView:sem_layout_resolve(env, target)
        return { schema.with(self, { base = only(self.base:sem_layout_resolve(env, target)), stride = one(resolve_expr, self.stride, env, target), lane = one(resolve_expr, self.lane, env, target) }) }
    end


    function Tr.DomainRange:sem_layout_resolve(env, target)
        return { schema.with(self, { stop = one(resolve_expr, self.stop, env, target) }) }
    end

    function Tr.DomainRange2:sem_layout_resolve(env, target)
        return { schema.with(self, { start = one(resolve_expr, self.start, env, target), stop = one(resolve_expr, self.stop, env, target) }) }
    end

    function Tr.DomainZipEqValues:sem_layout_resolve(env, target)
        return { schema.with(self, { values = map_exprs(self.values, env, target) }) }
    end

    function Tr.DomainValue:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.DomainView:sem_layout_resolve(env, target)
        return { schema.with(self, { view = only(self.view:sem_layout_resolve(env, target)) }) }
    end

    function Tr.DomainZipEqViews:sem_layout_resolve(env, target)
        local views = {}
        for i = 1, #self.views do views[#views + 1] = only(self.views[i]:sem_layout_resolve(env, target)) end
        return { schema.with(self, { views = views }) }
    end


    resolve_expr = function(node, ...)
        return node:sem_layout_resolve(...)
    end

    function Tr.Expr:sem_layout_resolve(env, target)
        return { self }
    end

    function Tr.ExprUnary:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.ExprBinary:sem_layout_resolve(env, target)
        return { schema.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) }) }
    end

    function Tr.ExprCompare:sem_layout_resolve(env, target)
        return { schema.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) }) }
    end

    function Tr.ExprLogic:sem_layout_resolve(env, target)
        return { schema.with(self, { lhs = one(resolve_expr, self.lhs, env, target), rhs = one(resolve_expr, self.rhs, env, target) }) }
    end

    function Tr.ExprCast:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.ExprMachineCast:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.ExprIntrinsic:sem_layout_resolve(env, target)
        return { schema.with(self, { args = map_exprs(self.args, env, target) }) }
    end

    function Tr.ExprAddrOf:sem_layout_resolve(env, target)
        return { schema.with(self, { place = only(self.place:sem_layout_resolve(env, target)) }) }
    end

    function Tr.ExprDeref:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.ExprCall:sem_layout_resolve(env, target)
        return { schema.with(self, { callee = one(resolve_expr, self.callee, env, target), args = map_exprs(self.args, env, target) }) }
    end

    function Tr.ExprLen:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.ExprAgg:sem_layout_resolve(env, target)
        local fields = {}
        for i = 1, #self.fields do fields[#fields + 1] = schema.with(self.fields[i], { value = one(resolve_expr, self.fields[i].value, env, target) }) end
        return { schema.with(self, { fields = fields }) }
    end

    function Tr.ExprArray:sem_layout_resolve(env, target)
        return { schema.with(self, { elems = map_exprs(self.elems, env, target) }) }
    end

    function Tr.ExprIf:sem_layout_resolve(env, target)
        return { schema.with(self, { cond = one(resolve_expr, self.cond, env, target), then_expr = one(resolve_expr, self.then_expr, env, target), else_expr = one(resolve_expr, self.else_expr, env, target) }) }
    end

    function Tr.ExprSelect:sem_layout_resolve(env, target)
        return { schema.with(self, { cond = one(resolve_expr, self.cond, env, target), then_expr = one(resolve_expr, self.then_expr, env, target), else_expr = one(resolve_expr, self.else_expr, env, target) }) }
    end

    function Tr.ExprSwitch:sem_layout_resolve(env, target)
        local arms = {}
        for i = 1, #self.arms do arms[#arms + 1] = schema.with(self.arms[i], { body = map_stmts(self.arms[i].body, env, target), result = one(resolve_expr, self.arms[i].result, env, target) }) end
        local var_arms = {}
        for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { body = map_stmts(self.variant_arms[i].body, env, target), result = one(resolve_expr, self.variant_arms[i].result, env, target) }) end
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target), arms = arms, variant_arms = var_arms, default_body = map_stmts(self.default_body or {}, env, target), default_expr = one(resolve_expr, self.default_expr, env, target) }) }
    end

    function Tr.ExprControl:sem_layout_resolve(env, target)
        return { schema.with(self, { region = only(self.region:sem_layout_resolve(env, target)) }) }
    end

    function Tr.ExprBlock:sem_layout_resolve(env, target)
        return { schema.with(self, { stmts = map_stmts(self.stmts, env, target), result = one(resolve_expr, self.result, env, target) }) }
    end

    function Tr.ExprClosure:sem_layout_resolve(env, target)
        return { schema.with(self, { body = map_stmts(self.body, env, target) }) }
    end

    function Tr.ExprView:sem_layout_resolve(env, target)
        return { schema.with(self, { view = only(self.view:sem_layout_resolve(env, target)) }) }
    end

    function Tr.ExprLoad:sem_layout_resolve(env, target)
        return { schema.with(self, { addr = one(resolve_expr, self.addr, env, target) }) }
    end

    function Tr.ExprAtomicLoad:sem_layout_resolve(env, target)
        return { schema.with(self, { addr = one(resolve_expr, self.addr, env, target) }) }
    end

    function Tr.ExprAtomicRmw:sem_layout_resolve(env, target)
        return { schema.with(self, { addr = one(resolve_expr, self.addr, env, target), value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.ExprAtomicCas:sem_layout_resolve(env, target)
        return { schema.with(self, { addr = one(resolve_expr, self.addr, env, target), expected = one(resolve_expr, self.expected, env, target), replacement = one(resolve_expr, self.replacement, env, target) }) }
    end

    function Ty.TypeMemLayoutKnown:sem_layout_size_expr()
        return { Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt(tostring(self.layout.size))) }
    end

    function Ty.TypeMemLayoutUnknown:sem_layout_size_expr()
        return { Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt("0")) }
    end

    function Ty.TypeMemLayoutKnown:sem_layout_align_expr()
        return { Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt(tostring(self.layout.align))) }
    end

    function Ty.TypeMemLayoutUnknown:sem_layout_align_expr()
        return { Tr.ExprLit(Tr.ExprTyped(index_ty()), C.LitInt("1")) }
    end

    function Tr.ExprSizeOf:sem_layout_resolve(env, target)
        return require("lalin.type_size_align")(T).result(self.ty, env, target):sem_layout_size_expr()
    end

    function Tr.ExprAlignOf:sem_layout_resolve(env, target)
        return require("lalin.type_size_align")(T).result(self.ty, env, target):sem_layout_align_expr()
    end

    function Tr.ExprIsNull:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.ExprCtor:sem_layout_resolve(env, target)
        return { schema.with(self, { args = map_exprs(self.args, env, target) }) }
    end

    function Tr.ExprDot:sem_layout_resolve(env, target)
        local base = one(resolve_expr, self.base, env, target)
        return base.h:sem_layout_value_type():sem_layout_expr_dot(self, base, env)
    end

    function Tr.ExprField:sem_layout_resolve(env, target)
        local base = one(resolve_expr, self.base, env, target)
        local field = base.h:sem_layout_value_type():sem_layout_resolve_field(self.field, env)
        return { schema.with(self, { base = base, field = field }) }
    end

    function Tr.ExprIndex:sem_layout_resolve(env, target)
        return { schema.with(self, { base = self.base:sem_layout_resolve(env, target), index = one(resolve_expr, self.index, env, target) }) }
    end


    local function resolve_entry_block(block, env, target)
        local params = {}
        for i = 1, #block.params do params[#params + 1] = schema.with(block.params[i], { init = one(resolve_expr, block.params[i].init, env, target) }) end
        return schema.with(block, { params = params, body = map_stmts(block.body, env, target) })
    end

    local function resolve_control_block(block, env, target)
        return schema.with(block, { body = map_stmts(block.body, env, target) })
    end

    function Tr.ControlStmtRegion:sem_layout_resolve(env, target)
        local blocks = {}
        for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env, target) end
        return { schema.with(self, { entry = resolve_entry_block(self.entry, env, target), blocks = blocks }) }
    end


    function Tr.ControlExprRegion:sem_layout_resolve(env, target)
        local blocks = {}
        for i = 1, #self.blocks do blocks[#blocks + 1] = resolve_control_block(self.blocks[i], env, target) end
        return { schema.with(self, { entry = resolve_entry_block(self.entry, env, target), blocks = blocks }) }
    end


    function Tr.Stmt:sem_layout_resolve(env, target)
        return { self }
    end

    function Tr.StmtLet:sem_layout_resolve(env, target)
        return { schema.with(self, { init = one(resolve_expr, self.init, env, target) }) }
    end

    function Tr.StmtVar:sem_layout_resolve(env, target)
        return { schema.with(self, { init = one(resolve_expr, self.init, env, target) }) }
    end

    function Tr.StmtSet:sem_layout_resolve(env, target)
        return { schema.with(self, { place = only(self.place:sem_layout_resolve(env, target)), value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.StmtAtomicStore:sem_layout_resolve(env, target)
        return { schema.with(self, { addr = one(resolve_expr, self.addr, env, target), value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.StmtExpr:sem_layout_resolve(env, target)
        return { schema.with(self, { expr = one(resolve_expr, self.expr, env, target) }) }
    end

    function Tr.StmtAssert:sem_layout_resolve(env, target)
        return { schema.with(self, { cond = one(resolve_expr, self.cond, env, target) }) }
    end

    function Tr.StmtIf:sem_layout_resolve(env, target)
        return { schema.with(self, { cond = one(resolve_expr, self.cond, env, target), then_body = map_stmts(self.then_body, env, target), else_body = map_stmts(self.else_body, env, target) }) }
    end

    function Tr.StmtSwitch:sem_layout_resolve(env, target)
        local arms = {}
        for i = 1, #self.arms do arms[#arms + 1] = schema.with(self.arms[i], { body = map_stmts(self.arms[i].body, env, target) }) end
        local var_arms = {}
        for i = 1, #(self.variant_arms or {}) do var_arms[#var_arms + 1] = schema.with(self.variant_arms[i], { body = map_stmts(self.variant_arms[i].body, env, target) }) end
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target), arms = arms, variant_arms = var_arms, default_body = map_stmts(self.default_body, env, target) }) }
    end

    function Tr.StmtJump:sem_layout_resolve(env, target)
        return { schema.with(self, { args = map_jump_args(self.args, env, target) }) }
    end

    function Tr.StmtJumpCont:sem_layout_resolve(env, target)
        return { schema.with(self, { args = map_jump_args(self.args, env, target) }) }
    end

    function Tr.StmtYieldValue:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.StmtReturnValue:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end

    function Tr.StmtControl:sem_layout_resolve(env, target)
        return { schema.with(self, { region = only(self.region:sem_layout_resolve(env, target)) }) }
    end


    function Tr.FuncContract:sem_layout_resolve(env, target)
        return self
    end

    function Tr.ContractBounds:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target), len = one(resolve_expr, self.len, env, target) })
    end

    function Tr.ContractWindowBounds:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target), base_len = one(resolve_expr, self.base_len, env, target), start = one(resolve_expr, self.start, env, target), len = one(resolve_expr, self.len, env, target) })
    end

    function Tr.ContractDisjoint:sem_layout_resolve(env, target)
        return schema.with(self, { a = one(resolve_expr, self.a, env, target), b = one(resolve_expr, self.b, env, target) })
    end

    function Tr.ContractSameLen:sem_layout_resolve(env, target)
        return schema.with(self, { a = one(resolve_expr, self.a, env, target), b = one(resolve_expr, self.b, env, target) })
    end

    function Tr.ContractSoAComponent:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target) })
    end

    function Tr.ContractNoAlias:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target) })
    end

    function Tr.ContractReadonly:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target) })
    end

    function Tr.ContractWriteonly:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target) })
    end

    function Tr.ContractInvalidate:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target) })
    end

    function Tr.ContractPreserve:sem_layout_resolve(env, target)
        return schema.with(self, { base = one(resolve_expr, self.base, env, target) })
    end


    local function resolve_contracts(contracts, env, target)
        local out = {}
        for i = 1, #(contracts or {}) do out[i] = contracts[i]:sem_layout_resolve(env, target) end
        return out
    end

    function Tr.Func:sem_layout_resolve(env, target)
        return { schema.with(self, { body = map_stmts(self.body, env, target) }) }
    end

    function Tr.FuncLocalContract:sem_layout_resolve(env, target)
        return { schema.with(self, { contracts = resolve_contracts(self.contracts, env, target), body = map_stmts(self.body, env, target) }) }
    end

    function Tr.FuncExportContract:sem_layout_resolve(env, target)
        return { schema.with(self, { contracts = resolve_contracts(self.contracts, env, target), body = map_stmts(self.body, env, target) }) }
    end


    function Tr.ConstItem:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end


    function Tr.StaticItem:sem_layout_resolve(env, target)
        return { schema.with(self, { value = one(resolve_expr, self.value, env, target) }) }
    end



    function Tr.Item:sem_layout_resolve(env, target)
        return { self }
    end

    function Tr.ItemFunc:sem_layout_resolve(env, target)
        return { schema.with(self, { func = only(self.func:sem_layout_resolve(env, target)) }) }
    end

    function Tr.ItemConst:sem_layout_resolve(env, target)
        return { schema.with(self, { c = only(self.c:sem_layout_resolve(env, target)) }) }
    end

    function Tr.ItemStatic:sem_layout_resolve(env, target)
        return { schema.with(self, { s = only(self.s:sem_layout_resolve(env, target)) }) }
    end

    function Tr.ItemType:sem_layout_resolve(env, target)
        return { schema.with(self, { t = only(self.t:sem_layout_resolve()) }) }
    end


    function Tr.Module:sem_layout_resolve(env, target)
        local resolved_env = env
        if resolved_env == nil or #resolved_env.layouts == 0 then
            resolved_env = Sem.LayoutEnv(module_type_api.env(self, target).layouts)
        end
        return { schema.with(self, { items = map_items(self.items, resolved_env, target) }) }
    end


    local function empty_env()
        return Sem.LayoutEnv({})
    end

    return {
        empty_env = empty_env,
        resolve_expr = resolve_expr,
        resolve_place = resolve_place,
        resolve_module = resolve_module,
        field = function(field, base_ty, env) return field:sem_resolve_field_ref(base_ty, env or empty_env()) end,
        expr = function(expr, env, target) return one(resolve_expr, expr, env or empty_env(), target) end,
        place = function(place, env, target) return only(place:sem_layout_resolve(env or empty_env(), target)) end,
        module = function(module, env, target) return only(module:sem_layout_resolve(env, target)) end,
    }
end

return bind_context
