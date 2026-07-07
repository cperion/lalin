local asdl = require("lalin.asdl")

local function bind_context(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree

    local state = nil

    -- Forward declarations (used by leaf methods defined before their bodies)
    local _rewrite_stmts
    local _closure_captures
    local _helper_for_closure
    local _helper_for_escaping_closure
    local _collect_captures_stmts

    local function append_all(out, xs)
        for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end
    end

    local function clone(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = xs[i] end
        return out
    end

    local function fresh_helper_name()
        state.counter = state.counter + 1
        return "__lalin_closure_" .. tostring(state.module_name or "mod") .. "_" .. tostring(state.owner or "anon") .. "_" .. tostring(state.counter)
    end

    local function int_lit(raw)
        return Tr.ExprLit(Tr.ExprSurface, C.LitInt(tostring(raw)))
    end

    local function name_ref(name)
        return Tr.ExprRef(Tr.ExprSurface, B.ValueRefName(name))
    end

    local function captured_load(cap)
        local ctx = name_ref("__lalin_ctx")
        local addr = ctx
        if cap.offset ~= 0 then addr = Tr.ExprBinary(Tr.ExprSurface, C.BinAdd, ctx, int_lit(cap.offset)) end
        return Tr.ExprLoad(Tr.ExprSurface, cap.ty, Tr.ExprCast(Tr.ExprSurface, C.SurfaceCast, Ty.TPtr(cap.ty), addr))
    end

    local function scope_get(name)
        for i = #state.scopes, 1, -1 do
            local ty = state.scopes[i][name]
            if ty ~= nil then return ty end
        end
        return nil
    end

    local function push_scope(entries)
        state.scopes[#state.scopes + 1] = entries or {}
    end

    local function pop_scope()
        state.scopes[#state.scopes] = nil
    end

    local function params_scope(params)
        local out = {}
        for i = 1, #(params or {}) do out[params[i].name] = params[i].ty end
        return out
    end

    local function type_size_align(ty)
        local cls = asdl.classof(ty)
        if cls == Ty.TScalar then
            if ty.scalar == C.ScalarBool or ty.scalar == C.ScalarI8 or ty.scalar == C.ScalarU8 then return 1, 1 end
            if ty.scalar == C.ScalarI16 or ty.scalar == C.ScalarU16 then return 2, 2 end
            if ty.scalar == C.ScalarI32 or ty.scalar == C.ScalarU32 or ty.scalar == C.ScalarF32 then return 4, 4 end
            if ty.scalar == C.ScalarI64 or ty.scalar == C.ScalarU64 or ty.scalar == C.ScalarF64 or ty.scalar == C.ScalarIndex or ty.scalar == C.ScalarRawPtr then return 8, 8 end
            if ty.scalar == C.ScalarVoid then return 0, 1 end
        end
        if cls == Ty.TPtr or cls == Ty.TFunc or cls == Ty.TClosure then return 8, 8 end
        error("closure conversion cannot capture value with unsupported environment layout: " .. tostring(ty), 2)
    end

    local function capture_layout(captures)
        local offset, align = 0, 1
        for i = 1, #captures do
            local size, a = type_size_align(captures[i].ty)
            if a > align then align = a end
            local rem = offset % a
            if rem ~= 0 then offset = offset + (a - rem) end
            captures[i].offset = offset
            captures[i].size = size
            offset = offset + size
        end
        local rem = offset % align
        if rem ~= 0 then offset = offset + (align - rem) end
        return offset, align
    end

    ------------------------------------------------------------------------
    -- rewrite_expr: parent default (identity)
    ------------------------------------------------------------------------
    function Tr.Expr:closure_rewrite()
        return self
    end

    -- Leaves with child recursion
    function Tr.ExprDot:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.ExprUnary:closure_rewrite()
        return asdl.with(self, { value = self.value:closure_rewrite() })
    end
    function Tr.ExprDeref:closure_rewrite()
        return asdl.with(self, { value = self.value:closure_rewrite() })
    end
    function Tr.ExprLen:closure_rewrite()
        return asdl.with(self, { value = self.value:closure_rewrite() })
    end
    function Tr.ExprBinary:closure_rewrite()
        return asdl.with(self, { lhs = self.lhs:closure_rewrite(), rhs = self.rhs:closure_rewrite() })
    end
    function Tr.ExprCompare:closure_rewrite()
        return asdl.with(self, { lhs = self.lhs:closure_rewrite(), rhs = self.rhs:closure_rewrite() })
    end
    function Tr.ExprLogic:closure_rewrite()
        return asdl.with(self, { lhs = self.lhs:closure_rewrite(), rhs = self.rhs:closure_rewrite() })
    end
    function Tr.ExprCast:closure_rewrite()
        return asdl.with(self, { value = self.value:closure_rewrite() })
    end
    function Tr.ExprMachineCast:closure_rewrite()
        return asdl.with(self, { value = self.value:closure_rewrite() })
    end
    function Tr.ExprIntrinsic:closure_rewrite()
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = self.args[i]:closure_rewrite() end
        return asdl.with(self, { args = args })
    end
    function Tr.ExprAddrOf:closure_rewrite()
        return asdl.with(self, { place = self.place:closure_rewrite() })
    end
    function Tr.ExprField:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.ExprIndex:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite(), index = self.index:closure_rewrite() })
    end
    function Tr.ExprAgg:closure_rewrite()
        local fields = {}
        for i = 1, #self.fields do fields[i] = asdl.with(self.fields[i], { value = self.fields[i].value:closure_rewrite() }) end
        return asdl.with(self, { fields = fields })
    end
    function Tr.ExprCtor:closure_rewrite()
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = self.args[i]:closure_rewrite() end
        return asdl.with(self, { args = args })
    end
    function Tr.ExprArray:closure_rewrite()
        local elems = {}
        for i = 1, #(self.elems or {}) do elems[i] = self.elems[i]:closure_rewrite() end
        return asdl.with(self, { elems = elems })
    end
    function Tr.ExprIf:closure_rewrite()
        return asdl.with(self, { cond = self.cond:closure_rewrite(), then_expr = self.then_expr:closure_rewrite(), else_expr = self.else_expr:closure_rewrite() })
    end
    function Tr.ExprSelect:closure_rewrite()
        return asdl.with(self, { cond = self.cond:closure_rewrite(), then_expr = self.then_expr:closure_rewrite(), else_expr = self.else_expr:closure_rewrite() })
    end
    function Tr.ExprLoad:closure_rewrite()
        return asdl.with(self, { addr = self.addr:closure_rewrite() })
    end
    function Tr.ExprAtomicLoad:closure_rewrite()
        return asdl.with(self, { addr = self.addr:closure_rewrite() })
    end
    function Tr.ExprAtomicRmw:closure_rewrite()
        return asdl.with(self, { addr = self.addr:closure_rewrite(), value = self.value:closure_rewrite() })
    end
    function Tr.ExprAtomicCas:closure_rewrite()
        return asdl.with(self, { addr = self.addr:closure_rewrite(), expected = self.expected:closure_rewrite(), replacement = self.replacement:closure_rewrite() })
    end
    function Tr.ExprView:closure_rewrite()
        return asdl.with(self, { view = self.view:closure_rewrite() })
    end

    -- ExprCall: recurse callee and args
    function Tr.ExprCall:closure_rewrite()
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = self.args[i]:closure_rewrite() end
        return asdl.with(self, { callee = self.callee:closure_rewrite(), args = args })
    end

    -- ExprSwitch: recurse value, arms, default
    function Tr.ExprSwitch:closure_rewrite()
        local arms = {}
        for i = 1, #self.arms do arms[i] = asdl.with(self.arms[i], { body = _rewrite_stmts(self.arms[i].body), result = self.arms[i].result:closure_rewrite() }) end
        local var_arms = {}
        for i = 1, #(self.variant_arms or {}) do var_arms[i] = asdl.with(self.variant_arms[i], { body = _rewrite_stmts(self.variant_arms[i].body), result = self.variant_arms[i].result:closure_rewrite() }) end
        return asdl.with(self, { value = self.value:closure_rewrite(), arms = arms, variant_arms = var_arms, default_body = _rewrite_stmts(self.default_body or {}), default_expr = self.default_expr:closure_rewrite() })
    end

    -- ExprControl: recurse region
    function Tr.ExprControl:closure_rewrite()
        local blocks = {}
        for i = 1, #self.region.blocks do blocks[i] = asdl.with(self.region.blocks[i], { body = _rewrite_stmts(self.region.blocks[i].body) }) end
        local entry_params = {}
        for i = 1, #self.region.entry.params do entry_params[i] = asdl.with(self.region.entry.params[i], { init = self.region.entry.params[i].init:closure_rewrite() }) end
        local entry = asdl.with(self.region.entry, { params = entry_params, body = _rewrite_stmts(self.region.entry.body) })
        return asdl.with(self, { region = asdl.with(self.region, { entry = entry, blocks = blocks }) })
    end

    -- ExprBlock: recurse with new scope
    function Tr.ExprBlock:closure_rewrite()
        return asdl.with(self, { stmts = _rewrite_stmts(self.stmts), result = self.result:closure_rewrite() })
    end

    -- ExprRef: special — check capture environment
    function Tr.ExprRef:closure_rewrite()
        if asdl.classof(self.ref) == B.ValueRefName and state.capture_env ~= nil then
            local cap = state.capture_env[self.ref.name]
            if cap ~= nil and scope_get(self.ref.name) == nil then return captured_load(cap) end
        end
        return self
    end

    -- ExprClosure: special — becomes descriptor aggregate
    function Tr.ExprClosure:closure_rewrite()
        local captures = _closure_captures(self)
        local helper_name = _helper_for_escaping_closure(self, captures)
        local fields = { Tr.FieldInit("__lalin_fn", name_ref(helper_name), 0) }
        for i = 1, #captures do
            fields[#fields + 1] = Tr.FieldInit("__lalin_cap_" .. captures[i].name, name_ref(captures[i].name), captures[i].offset)
        end
        local params = {}
        for i = 1, #self.params do params[i] = self.params[i].ty end
        return Tr.ExprAgg(Tr.ExprSurface, Ty.TClosure(params, self.result), fields)
    end

    ------------------------------------------------------------------------
    -- rewrite_view: parent default + leaves
    ------------------------------------------------------------------------
    function Tr.View:closure_rewrite()
        return self
    end
    function Tr.ViewFromExpr:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.ViewContiguous:closure_rewrite()
        return asdl.with(self, { data = self.data:closure_rewrite(), len = self.len:closure_rewrite() })
    end
    function Tr.ViewStrided:closure_rewrite()
        return asdl.with(self, { data = self.data:closure_rewrite(), len = self.len:closure_rewrite(), stride = self.stride:closure_rewrite() })
    end
    function Tr.ViewRestrided:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite(), stride = self.stride:closure_rewrite() })
    end
    function Tr.ViewWindow:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite(), start = self.start:closure_rewrite(), len = self.len:closure_rewrite() })
    end
    function Tr.ViewRowBase:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite(), row_offset = self.row_offset:closure_rewrite() })
    end
    function Tr.ViewInterleaved:closure_rewrite()
        return asdl.with(self, { data = self.data:closure_rewrite(), len = self.len:closure_rewrite(), stride = self.stride:closure_rewrite(), lane = self.lane:closure_rewrite() })
    end
    function Tr.ViewInterleavedView:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite(), stride = self.stride:closure_rewrite(), lane = self.lane:closure_rewrite() })
    end

    ------------------------------------------------------------------------
    -- rewrite_index_base: parent default + leaves
    ------------------------------------------------------------------------
    function Tr.IndexBase:closure_rewrite()
        return self
    end
    function Tr.IndexBaseExpr:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.IndexBasePlace:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.IndexBaseView:closure_rewrite()
        return asdl.with(self, { view = self.view:closure_rewrite() })
    end

    ------------------------------------------------------------------------
    -- rewrite_place: parent default + leaves
    ------------------------------------------------------------------------
    function Tr.Place:closure_rewrite()
        return self
    end
    function Tr.PlaceDeref:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.PlaceDot:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.PlaceField:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite() })
    end
    function Tr.PlaceIndex:closure_rewrite()
        return asdl.with(self, { base = self.base:closure_rewrite(), index = self.index:closure_rewrite() })
    end

    ------------------------------------------------------------------------
    -- rewrite_stmt: parent default + leaves
    ------------------------------------------------------------------------
    function Tr.Stmt:closure_rewrite()
        return self
    end
    function Tr.StmtLet:closure_rewrite()
        local out = asdl.with(self, { init = self.init:closure_rewrite() })
        if #state.scopes > 0 then state.scopes[#state.scopes][self.binding.name] = self.binding.ty end
        return out
    end
    function Tr.StmtVar:closure_rewrite()
        local out = asdl.with(self, { init = self.init:closure_rewrite() })
        if #state.scopes > 0 then state.scopes[#state.scopes][self.binding.name] = self.binding.ty end
        return out
    end
    function Tr.StmtSet:closure_rewrite()
        return asdl.with(self, { place = self.place:closure_rewrite(), value = self.value:closure_rewrite() })
    end
    function Tr.StmtAtomicStore:closure_rewrite()
        return asdl.with(self, { addr = self.addr:closure_rewrite(), value = self.value:closure_rewrite() })
    end
    function Tr.StmtExpr:closure_rewrite()
        return asdl.with(self, { expr = self.expr:closure_rewrite() })
    end
    function Tr.StmtAssert:closure_rewrite()
        return asdl.with(self, { cond = self.cond:closure_rewrite() })
    end
    function Tr.StmtIf:closure_rewrite()
        return asdl.with(self, { cond = self.cond:closure_rewrite(), then_body = _rewrite_stmts(self.then_body), else_body = _rewrite_stmts(self.else_body) })
    end
    function Tr.StmtSwitch:closure_rewrite()
        local arms = {}
        for i = 1, #self.arms do arms[i] = asdl.with(self.arms[i], { body = _rewrite_stmts(self.arms[i].body) }) end
        local var_arms = {}
        for i = 1, #(self.variant_arms or {}) do var_arms[i] = asdl.with(self.variant_arms[i], { body = _rewrite_stmts(self.variant_arms[i].body) }) end
        return asdl.with(self, { value = self.value:closure_rewrite(), arms = arms, variant_arms = var_arms, default_body = _rewrite_stmts(self.default_body or {}) })
    end
    function Tr.StmtJump:closure_rewrite()
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = asdl.with(self.args[i], { value = self.args[i].value:closure_rewrite() }) end
        return asdl.with(self, { args = args })
    end
    function Tr.StmtJumpCont:closure_rewrite()
        local args = {}
        for i = 1, #(self.args or {}) do args[i] = asdl.with(self.args[i], { value = self.args[i].value:closure_rewrite() }) end
        return asdl.with(self, { args = args })
    end
    function Tr.StmtYieldValue:closure_rewrite()
        return asdl.with(self, { value = self.value:closure_rewrite() })
    end
    function Tr.StmtReturnValue:closure_rewrite()
        return asdl.with(self, { value = self.value:closure_rewrite() })
    end
    function Tr.StmtControl:closure_rewrite()
        local blocks = {}
        for i = 1, #self.region.blocks do blocks[i] = asdl.with(self.region.blocks[i], { body = _rewrite_stmts(self.region.blocks[i].body) }) end
        local entry_params = {}
        for i = 1, #self.region.entry.params do entry_params[i] = asdl.with(self.region.entry.params[i], { init = self.region.entry.params[i].init:closure_rewrite() }) end
        local entry = asdl.with(self.region.entry, { params = entry_params, body = _rewrite_stmts(self.region.entry.body) })
        return asdl.with(self, { region = asdl.with(self.region, { entry = entry, blocks = blocks }) })
    end

    ------------------------------------------------------------------------
    -- rewrite_func: parent default + leaves
    ------------------------------------------------------------------------
    function Tr.Func:closure_rewrite()
        local old_owner = state.owner
        push_scope(params_scope(self.params or {}))
        local out = asdl.with(self, { body = _rewrite_stmts(self.body) })
        pop_scope()
        state.owner = old_owner
        return out
    end
    function Tr.FuncLocal:closure_rewrite()
        state.owner = self.name
        return Tr.Func.closure_rewrite(self)
    end
    function Tr.FuncExport:closure_rewrite()
        state.owner = self.name
        return Tr.Func.closure_rewrite(self)
    end
    function Tr.FuncLocalContract:closure_rewrite()
        state.owner = self.name
        return Tr.Func.closure_rewrite(self)
    end
    function Tr.FuncExportContract:closure_rewrite()
        state.owner = self.name
        return Tr.Func.closure_rewrite(self)
    end

    ------------------------------------------------------------------------
    -- rewrite_item: parent default + leaves
    ------------------------------------------------------------------------
    function Tr.Item:closure_rewrite()
        return self
    end
    function Tr.ItemFunc:closure_rewrite()
        return asdl.with(self, { func = self.func:closure_rewrite() })
    end
    function Tr.ItemConst:closure_rewrite()
        return asdl.with(self, { c = asdl.with(self.c, { value = self.c.value:closure_rewrite() }) })
    end
    function Tr.ItemStatic:closure_rewrite()
        return asdl.with(self, { s = asdl.with(self.s, { value = self.s.value:closure_rewrite() }) })
    end

    ------------------------------------------------------------------------
    -- Rewrite helpers (used by leaf methods that need them before definition)
    ------------------------------------------------------------------------
    _rewrite_stmts = function(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = xs[i]:closure_rewrite() end
        return out
    end

    _closure_captures = function(expr)
        local locals = params_scope(expr.params)
        local out, seen = {}, {}
        _collect_captures_stmts(expr.body, locals, out, seen)
        return out
    end

    _helper_for_closure = function(expr, captures)
        local name = fresh_helper_name()
        captures = captures or _closure_captures(expr)
        local helper_params = clone(expr.params)
        for i = 1, #captures do helper_params[#helper_params + 1] = Ty.Param(captures[i].name, captures[i].ty) end
        local old_owner = state.owner
        state.owner = name
        push_scope(params_scope(helper_params))
        local body = _rewrite_stmts(expr.body)
        pop_scope()
        state.owner = old_owner
        local helper = Tr.FuncLocal(name, helper_params, expr.result, body)
        state.helpers[#state.helpers + 1] = Tr.ItemFunc(helper)
        return name, captures
    end

    _helper_for_escaping_closure = function(expr, captures)
        local name = fresh_helper_name()
        captures = captures or _closure_captures(expr)
        capture_layout(captures)
        local helper_params = { Ty.Param("__lalin_ctx", Ty.TPtr(Ty.TScalar(C.ScalarU8))) }
        append_all(helper_params, expr.params)
        local capture_env = {}
        for i = 1, #captures do capture_env[captures[i].name] = captures[i] end
        local old_owner, old_capture_env, old_scopes = state.owner, state.capture_env, state.scopes
        state.owner = name
        state.capture_env = capture_env
        state.scopes = {}
        push_scope(params_scope(helper_params))
        local body = _rewrite_stmts(expr.body)
        pop_scope()
        state.scopes = old_scopes
        state.capture_env = old_capture_env
        state.owner = old_owner
        local helper = Tr.FuncLocal(name, helper_params, expr.result, body)
        state.helpers[#state.helpers + 1] = Tr.ItemFunc(helper)
        return name, captures
    end

    ------------------------------------------------------------------------
    -- collect_captures_expr: parent default + leaves
    ------------------------------------------------------------------------
    function Tr.Expr:closure_collect_captures(locals, out, seen)
        -- default: no captures found here
    end
    function Tr.ExprRef:closure_collect_captures(locals, out, seen)
        if asdl.classof(self.ref) ~= B.ValueRefName then return end
        local name = self.ref.name
        if locals[name] or seen[name] then return end
        local ty = scope_get(name)
        if ty ~= nil then seen[name] = true; out[#out + 1] = { name = name, ty = ty } end
    end
    function Tr.ExprUnary:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprDeref:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprLen:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprBinary:closure_collect_captures(locals, out, seen)
        self.lhs:closure_collect_captures(locals, out, seen)
        self.rhs:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprCompare:closure_collect_captures(locals, out, seen)
        self.lhs:closure_collect_captures(locals, out, seen)
        self.rhs:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprLogic:closure_collect_captures(locals, out, seen)
        self.lhs:closure_collect_captures(locals, out, seen)
        self.rhs:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprCast:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprMachineCast:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprIntrinsic:closure_collect_captures(locals, out, seen)
        for i = 1, #self.args do self.args[i]:closure_collect_captures(locals, out, seen) end
    end
    function Tr.ExprAddrOf:closure_collect_captures(locals, out, seen)
        self.place:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprCall:closure_collect_captures(locals, out, seen)
        self.callee:closure_collect_captures(locals, out, seen)
        for i = 1, #self.args do self.args[i]:closure_collect_captures(locals, out, seen) end
    end
    function Tr.ExprField:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprDot:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprIndex:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
        self.index:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprAgg:closure_collect_captures(locals, out, seen)
        for i = 1, #self.fields do self.fields[i].value:closure_collect_captures(locals, out, seen) end
    end
    function Tr.ExprCtor:closure_collect_captures(locals, out, seen)
        for i = 1, #(self.args or {}) do self.args[i]:closure_collect_captures(locals, out, seen) end
    end
    function Tr.ExprArray:closure_collect_captures(locals, out, seen)
        for i = 1, #self.elems do self.elems[i]:closure_collect_captures(locals, out, seen) end
    end
    function Tr.ExprIf:closure_collect_captures(locals, out, seen)
        self.cond:closure_collect_captures(locals, out, seen)
        self.then_expr:closure_collect_captures(locals, out, seen)
        self.else_expr:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprSelect:closure_collect_captures(locals, out, seen)
        self.cond:closure_collect_captures(locals, out, seen)
        self.then_expr:closure_collect_captures(locals, out, seen)
        self.else_expr:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprBlock:closure_collect_captures(locals, out, seen)
        local inner = {}
        for k, v in pairs(locals) do inner[k] = v end
        _collect_captures_stmts(self.stmts, inner, out, seen)
        self.result:closure_collect_captures(inner, out, seen)
    end
    function Tr.ExprView:closure_collect_captures(locals, out, seen)
        self.view:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprLoad:closure_collect_captures(locals, out, seen)
        self.addr:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprAtomicLoad:closure_collect_captures(locals, out, seen)
        self.addr:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprAtomicRmw:closure_collect_captures(locals, out, seen)
        self.addr:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.ExprAtomicCas:closure_collect_captures(locals, out, seen)
        self.addr:closure_collect_captures(locals, out, seen)
        self.expected:closure_collect_captures(locals, out, seen)
        self.replacement:closure_collect_captures(locals, out, seen)
    end

    ------------------------------------------------------------------------
    -- collect_captures_place
    ------------------------------------------------------------------------
    function Tr.Place:closure_collect_captures(locals, out, seen)
    end
    function Tr.PlaceRef:closure_collect_captures(locals, out, seen)
        if asdl.classof(self.ref) == B.ValueRefName then
            Tr.ExprRef(Tr.ExprSurface, self.ref):closure_collect_captures(locals, out, seen)
        end
    end
    function Tr.PlaceDeref:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.PlaceDot:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.PlaceField:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.PlaceIndex:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
        self.index:closure_collect_captures(locals, out, seen)
    end

    ------------------------------------------------------------------------
    -- collect_captures_index_base
    ------------------------------------------------------------------------
    function Tr.IndexBase:closure_collect_captures(locals, out, seen)
    end
    function Tr.IndexBaseExpr:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.IndexBasePlace:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.IndexBaseView:closure_collect_captures(locals, out, seen)
        self.view:closure_collect_captures(locals, out, seen)
    end

    ------------------------------------------------------------------------
    -- collect_captures_view
    ------------------------------------------------------------------------
    function Tr.View:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewFromExpr:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewContiguous:closure_collect_captures(locals, out, seen)
        self.data:closure_collect_captures(locals, out, seen)
        self.len:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewStrided:closure_collect_captures(locals, out, seen)
        self.data:closure_collect_captures(locals, out, seen)
        self.len:closure_collect_captures(locals, out, seen)
        self.stride:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewRestrided:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
        self.stride:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewWindow:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
        self.start:closure_collect_captures(locals, out, seen)
        self.len:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewRowBase:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
        self.row_offset:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewInterleaved:closure_collect_captures(locals, out, seen)
        self.data:closure_collect_captures(locals, out, seen)
        self.len:closure_collect_captures(locals, out, seen)
        self.stride:closure_collect_captures(locals, out, seen)
        self.lane:closure_collect_captures(locals, out, seen)
    end
    function Tr.ViewInterleavedView:closure_collect_captures(locals, out, seen)
        self.base:closure_collect_captures(locals, out, seen)
        self.stride:closure_collect_captures(locals, out, seen)
        self.lane:closure_collect_captures(locals, out, seen)
    end

    ------------------------------------------------------------------------
    -- collect_captures_stmts
    ------------------------------------------------------------------------
    function Tr.Stmt:closure_collect_captures(locals, out, seen)
    end
    function Tr.StmtLet:closure_collect_captures(locals, out, seen)
        self.init:closure_collect_captures(locals, out, seen)
        locals[self.binding.name] = self.binding.ty
    end
    function Tr.StmtVar:closure_collect_captures(locals, out, seen)
        self.init:closure_collect_captures(locals, out, seen)
        locals[self.binding.name] = self.binding.ty
    end
    function Tr.StmtSet:closure_collect_captures(locals, out, seen)
        self.place:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.StmtExpr:closure_collect_captures(locals, out, seen)
        self.expr:closure_collect_captures(locals, out, seen)
    end
    function Tr.StmtReturnValue:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.StmtYieldValue:closure_collect_captures(locals, out, seen)
        self.value:closure_collect_captures(locals, out, seen)
    end
    function Tr.StmtIf:closure_collect_captures(locals, out, seen)
        self.cond:closure_collect_captures(locals, out, seen)
        local a = {}; for k, v in pairs(locals) do a[k] = v end
        _collect_captures_stmts(self.then_body, a, out, seen)
        local b = {}; for k, v in pairs(locals) do b[k] = v end
        _collect_captures_stmts(self.else_body, b, out, seen)
    end

    _collect_captures_stmts = function(stmts, locals, out, seen)
        for i = 1, #(stmts or {}) do
            stmts[i]:closure_collect_captures(locals, out, seen)
        end
    end

    ------------------------------------------------------------------------
    -- Module-level public API
    ------------------------------------------------------------------------
    local function module_name(module)
        local h = module.h
        local cls = asdl.classof(h)
        if cls == Tr.ModuleTyped or cls == Tr.ModuleSem or cls == Tr.ModuleCode then return h.module_name end
        return ""
    end

    local function rewrite_module(module)
        local previous = state
        state = { module_name = module_name(module), owner = "module", counter = 0, helpers = {}, scopes = {} }
        local items = {}
        for i = 1, #module.items do
            local before = #state.helpers
            local rewritten = module.items[i]:closure_rewrite()
            for j = before + 1, #state.helpers do items[#items + 1] = state.helpers[j] end
            items[#items + 1] = rewritten
        end
        local out = asdl.with(module, { items = items })
        state = previous
        return out
    end

    local function rewrite_func(func)
        state = { module_name = "", owner = "func", counter = 0, helpers = {}, scopes = {} }
        local out = func:closure_rewrite()
        local helpers = state.helpers
        state = nil
        return out, helpers
    end

    return {
        module = rewrite_module,
        func = rewrite_func,
    }
end

return bind_context
