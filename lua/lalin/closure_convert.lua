local asdl = require("lalin.asdl")

local function bind_context(T)
    local C = T.LalinCore
    local Ty = T.LalinType
    local B = T.LalinBind
    local Sem = T.LalinSem
    local Tr = T.LalinTree

    -- Closure conversion owns this canonical header-name dependency. Install the
    -- existing concrete ModuleHeader leaf methods before the module API uses them.
    require("lalin.tree_module_type")(T)

    ------------------------------------------------------------------------
    -- Ty.Type: closure_size_align leaf methods (no classof dispatch)
    ------------------------------------------------------------------------
    function Ty.Type:closure_size_align()
        error("closure conversion cannot capture value with unsupported environment layout: " .. tostring(self), 2)
    end
    local function closure_pointer_size(target)
        return target.pointer_bits / 8
    end
    function Ty.TScalar:closure_size_align(target)
        if self.scalar == C.ScalarBool or self.scalar == C.ScalarI8 or self.scalar == C.ScalarU8 then return 1, 1 end
        if self.scalar == C.ScalarI16 or self.scalar == C.ScalarU16 then return 2, 2 end
        if self.scalar == C.ScalarI32 or self.scalar == C.ScalarU32 or self.scalar == C.ScalarF32 then return 4, 4 end
        if self.scalar == C.ScalarI64 or self.scalar == C.ScalarU64 or self.scalar == C.ScalarF64 then return 8, 8 end
        if self.scalar == C.ScalarIndex or self.scalar == C.ScalarRawPtr then
            local size = closure_pointer_size(target)
            return size, size
        end
        if self.scalar == C.ScalarVoid then return 0, 1 end
        error("closure conversion cannot capture unsupported scalar: " .. tostring(self.scalar), 2)
    end
    function Ty.TPtr:closure_size_align(target) local size = closure_pointer_size(target); return size, size end
    function Ty.TFunc:closure_size_align(target) local size = closure_pointer_size(target); return size, size end
    function Ty.TClosure:closure_size_align(target) local size = closure_pointer_size(target); return size, size end

    ------------------------------------------------------------------------
    -- B.ValueRef: closure leaf methods (no classof dispatch)
    ------------------------------------------------------------------------
    function B.ValueRef:closure_is_name_ref() return false end
    function B.ValueRefName:closure_is_name_ref() return true end
    function B.ValueRefName:closure_captured_name() return self.name end

    ------------------------------------------------------------------------
    -- Pure helpers
    ------------------------------------------------------------------------
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

    local function clone(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = xs[i] end
        return out
    end

    local function params_scope(params)
        local out = {}
        for i = 1, #(params or {}) do out[params[i].name] = params[i].ty end
        return out
    end

    ------------------------------------------------------------------------
    -- Input management (operate on mutable input table)
    ------------------------------------------------------------------------
    local function fresh_helper_name(input)
        input.counter = input.counter + 1
        return "__lalin_closure_" .. tostring(input.module_name or "mod") .. "_" .. tostring(input.owner or "anon") .. "_" .. tostring(input.counter)
    end

    local function scope_get(input, name)
        for i = #input.scopes, 1, -1 do
            local ty = input.scopes[i][name]
            if ty ~= nil then return ty end
        end
        return nil
    end

    local function push_scope(input, entries)
        input.scopes[#input.scopes + 1] = entries or {}
    end

    local function pop_scope(input)
        input.scopes[#input.scopes] = nil
    end

    local function capture_layout(captures, target)
        local offset, align = 0, 1
        for i = 1, #captures do
            local size, a = captures[i].ty:closure_size_align(target)
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
    -- Forward declarations (assigned after leaf methods)
    ------------------------------------------------------------------------
    local _rewrite_stmts
    local _closure_captures
    local _helper_for_closure
    local _helper_for_escaping_closure
    local _collect_captures_stmts

    ------------------------------------------------------------------------
    -- Tr.Expr: closure_rewrite(input) -> expr, input
    ------------------------------------------------------------------------
    function Tr.Expr:closure_rewrite(input)
        return self, input
    end
    function Tr.ExprLit:closure_rewrite(input)
        return self, input
    end
    function Tr.ExprDot:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.ExprUnary:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if value == self.value then return self, input end
        return asdl.with(self, { value = value }), input
    end
    function Tr.ExprDeref:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if value == self.value then return self, input end
        return asdl.with(self, { value = value }), input
    end
    function Tr.ExprLen:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if value == self.value then return self, input end
        return asdl.with(self, { value = value }), input
    end
    function Tr.ExprBinary:closure_rewrite(input)
        local lhs, input = self.lhs:closure_rewrite(input)
        local rhs, input = self.rhs:closure_rewrite(input)
        if lhs == self.lhs and rhs == self.rhs then return self, input end
        return asdl.with(self, { lhs = lhs, rhs = rhs }), input
    end
    function Tr.ExprCompare:closure_rewrite(input)
        local lhs, input = self.lhs:closure_rewrite(input)
        local rhs, input = self.rhs:closure_rewrite(input)
        if lhs == self.lhs and rhs == self.rhs then return self, input end
        return asdl.with(self, { lhs = lhs, rhs = rhs }), input
    end
    function Tr.ExprLogic:closure_rewrite(input)
        local lhs, input = self.lhs:closure_rewrite(input)
        local rhs, input = self.rhs:closure_rewrite(input)
        if lhs == self.lhs and rhs == self.rhs then return self, input end
        return asdl.with(self, { lhs = lhs, rhs = rhs }), input
    end
    function Tr.ExprCast:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if value == self.value then return self, input end
        return asdl.with(self, { value = value }), input
    end
    function Tr.ExprMachineCast:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if value == self.value then return self, input end
        return asdl.with(self, { value = value }), input
    end
    function Tr.ExprIntrinsic:closure_rewrite(input)
        local changed = false
        local args = {}
        for i = 1, #(self.args or {}) do
            args[i], input = self.args[i]:closure_rewrite(input)
            if args[i] ~= self.args[i] then changed = true end
        end
        if not changed then return self, input end
        return asdl.with(self, { args = args }), input
    end
    function Tr.ExprAddrOf:closure_rewrite(input)
        local place, input = self.place:closure_rewrite(input)
        if place == self.place then return self, input end
        return asdl.with(self, { place = place }), input
    end
    function Tr.ExprField:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.ExprIndex:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        local index, input = self.index:closure_rewrite(input)
        if base == self.base and index == self.index then return self, input end
        return asdl.with(self, { base = base, index = index }), input
    end
    function Tr.ExprAgg:closure_rewrite(input)
        local changed = false
        local fields = {}
        for i = 1, #self.fields do
            local val, input2 = self.fields[i].value:closure_rewrite(input)
            input = input2
            if val ~= self.fields[i].value then changed = true end
            fields[i] = changed and asdl.with(self.fields[i], { value = val }) or self.fields[i]
        end
        if not changed then return self, input end
        return asdl.with(self, { fields = fields }), input
    end
    function Tr.ExprCtor:closure_rewrite(input)
        local changed = false
        local args = {}
        for i = 1, #(self.args or {}) do
            args[i], input = self.args[i]:closure_rewrite(input)
            if args[i] ~= self.args[i] then changed = true end
        end
        if not changed then return self, input end
        return asdl.with(self, { args = args }), input
    end
    function Tr.ExprArray:closure_rewrite(input)
        local changed = false
        local elems = {}
        for i = 1, #(self.elems or {}) do
            elems[i], input = self.elems[i]:closure_rewrite(input)
            if elems[i] ~= self.elems[i] then changed = true end
        end
        if not changed then return self, input end
        return asdl.with(self, { elems = elems }), input
    end
    function Tr.ExprIf:closure_rewrite(input)
        local cond, input = self.cond:closure_rewrite(input)
        local then_expr, input = self.then_expr:closure_rewrite(input)
        local else_expr, input = self.else_expr:closure_rewrite(input)
        if cond == self.cond and then_expr == self.then_expr and else_expr == self.else_expr then return self, input end
        return asdl.with(self, { cond = cond, then_expr = then_expr, else_expr = else_expr }), input
    end
    function Tr.ExprSelect:closure_rewrite(input)
        local cond, input = self.cond:closure_rewrite(input)
        local then_expr, input = self.then_expr:closure_rewrite(input)
        local else_expr, input = self.else_expr:closure_rewrite(input)
        if cond == self.cond and then_expr == self.then_expr and else_expr == self.else_expr then return self, input end
        return asdl.with(self, { cond = cond, then_expr = then_expr, else_expr = else_expr }), input
    end
    function Tr.ExprLoad:closure_rewrite(input)
        local addr, input = self.addr:closure_rewrite(input)
        if addr == self.addr then return self, input end
        return asdl.with(self, { addr = addr }), input
    end
    function Tr.ExprAtomicLoad:closure_rewrite(input)
        local addr, input = self.addr:closure_rewrite(input)
        if addr == self.addr then return self, input end
        return asdl.with(self, { addr = addr }), input
    end
    function Tr.ExprAtomicRmw:closure_rewrite(input)
        local addr, input = self.addr:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if addr == self.addr and value == self.value then return self, input end
        return asdl.with(self, { addr = addr, value = value }), input
    end
    function Tr.ExprAtomicCas:closure_rewrite(input)
        local addr, input = self.addr:closure_rewrite(input)
        local expected, input = self.expected:closure_rewrite(input)
        local replacement, input = self.replacement:closure_rewrite(input)
        if addr == self.addr and expected == self.expected and replacement == self.replacement then return self, input end
        return asdl.with(self, { addr = addr, expected = expected, replacement = replacement }), input
    end
    function Tr.ExprView:closure_rewrite(input)
        local view, input = self.view:closure_rewrite(input)
        if view == self.view then return self, input end
        return asdl.with(self, { view = view }), input
    end
    function Tr.ExprCall:closure_rewrite(input)
        local callee, input = self.callee:closure_rewrite(input)
        local changed = callee ~= self.callee
        local args = {}
        for i = 1, #(self.args or {}) do
            args[i], input = self.args[i]:closure_rewrite(input)
            if args[i] ~= self.args[i] then changed = true end
        end
        if not changed then return self, input end
        return asdl.with(self, { callee = callee, args = args }), input
    end
    function Tr.ExprSwitch:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        local arms = {}
        for i = 1, #self.arms do
            local body, input2 = _rewrite_stmts(self.arms[i].body, input)
            input = input2
            local result, input3 = self.arms[i].result:closure_rewrite(input)
            input = input3
            arms[i] = asdl.with(self.arms[i], { body = body, result = result })
        end
        local var_arms = {}
        for i = 1, #(self.variant_arms or {}) do
            local body, input2 = _rewrite_stmts(self.variant_arms[i].body, input)
            input = input2
            local result, input3 = self.variant_arms[i].result:closure_rewrite(input)
            input = input3
            var_arms[i] = asdl.with(self.variant_arms[i], { body = body, result = result })
        end
        local default_body, input = _rewrite_stmts(self.default_body or {}, input)
        local default_expr, input = self.default_expr:closure_rewrite(input)
        return asdl.with(self, { value = value, arms = arms, variant_arms = var_arms, default_body = default_body, default_expr = default_expr }), input
    end
    function Tr.ExprControl:closure_rewrite(input)
        local blocks = {}
        for i = 1, #self.region.blocks do
            local body, input2 = _rewrite_stmts(self.region.blocks[i].body, input)
            input = input2
            blocks[i] = asdl.with(self.region.blocks[i], { body = body })
        end
        local entry_params = {}
        for i = 1, #self.region.entry.params do
            local init, input2 = self.region.entry.params[i].init:closure_rewrite(input)
            input = input2
            entry_params[i] = asdl.with(self.region.entry.params[i], { init = init })
        end
        local entry_body, input = _rewrite_stmts(self.region.entry.body, input)
        local entry = asdl.with(self.region.entry, { params = entry_params, body = entry_body })
        return asdl.with(self, { region = asdl.with(self.region, { entry = entry, blocks = blocks }) }), input
    end
    function Tr.ExprBlock:closure_rewrite(input)
        local stmts, input = _rewrite_stmts(self.stmts, input)
        local result, input = self.result:closure_rewrite(input)
        return asdl.with(self, { stmts = stmts, result = result }), input
    end

    -- ExprRef: uses ValueRef leaf methods — no classof
    function Tr.ExprRef:closure_rewrite(input)
        if self.ref:closure_is_name_ref() and input.capture_env ~= nil then
            local name = self.ref:closure_captured_name()
            local cap = input.capture_env[name]
            if cap ~= nil and scope_get(input, name) == nil then
                return captured_load(cap), input
            end
        end
        return self, input
    end

    -- ExprClosure: becomes descriptor aggregate
    function Tr.ExprClosure:closure_rewrite(input)
        local captures = _closure_captures(self, input)
        local helper_name, input = _helper_for_escaping_closure(input, self, captures)
        local fields = { Tr.FieldInit("__lalin_fn", name_ref(helper_name), 0) }
        for i = 1, #captures do
            fields[#fields + 1] = Tr.FieldInit("__lalin_cap_" .. captures[i].name, name_ref(captures[i].name), captures[i].offset)
        end
        local params = {}
        for i = 1, #self.params do params[i] = self.params[i].ty end
        return Tr.ExprAgg(Tr.ExprSurface, Ty.TClosure(params, self.result), fields), input
    end

    ------------------------------------------------------------------------
    -- Tr.View: closure_rewrite
    ------------------------------------------------------------------------
    function Tr.View:closure_rewrite(input) return self, input end
    function Tr.ViewFromExpr:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.ViewContiguous:closure_rewrite(input)
        local data, input = self.data:closure_rewrite(input)
        local len, input = self.len:closure_rewrite(input)
        if data == self.data and len == self.len then return self, input end
        return asdl.with(self, { data = data, len = len }), input
    end
    function Tr.ViewStrided:closure_rewrite(input)
        local data, input = self.data:closure_rewrite(input)
        local len, input = self.len:closure_rewrite(input)
        local stride, input = self.stride:closure_rewrite(input)
        if data == self.data and len == self.len and stride == self.stride then return self, input end
        return asdl.with(self, { data = data, len = len, stride = stride }), input
    end
    function Tr.ViewRestrided:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        local stride, input = self.stride:closure_rewrite(input)
        if base == self.base and stride == self.stride then return self, input end
        return asdl.with(self, { base = base, stride = stride }), input
    end
    function Tr.ViewWindow:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        local start, input = self.start:closure_rewrite(input)
        local len, input = self.len:closure_rewrite(input)
        if base == self.base and start == self.start and len == self.len then return self, input end
        return asdl.with(self, { base = base, start = start, len = len }), input
    end
    function Tr.ViewRowBase:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        local row_offset, input = self.row_offset:closure_rewrite(input)
        if base == self.base and row_offset == self.row_offset then return self, input end
        return asdl.with(self, { base = base, row_offset = row_offset }), input
    end
    function Tr.ViewInterleaved:closure_rewrite(input)
        local data, input = self.data:closure_rewrite(input)
        local len, input = self.len:closure_rewrite(input)
        local stride, input = self.stride:closure_rewrite(input)
        local lane, input = self.lane:closure_rewrite(input)
        if data == self.data and len == self.len and stride == self.stride and lane == self.lane then return self, input end
        return asdl.with(self, { data = data, len = len, stride = stride, lane = lane }), input
    end
    function Tr.ViewInterleavedView:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        local stride, input = self.stride:closure_rewrite(input)
        local lane, input = self.lane:closure_rewrite(input)
        if base == self.base and stride == self.stride and lane == self.lane then return self, input end
        return asdl.with(self, { base = base, stride = stride, lane = lane }), input
    end

    ------------------------------------------------------------------------
    -- Tr.IndexBase: closure_rewrite
    ------------------------------------------------------------------------
    function Tr.IndexBase:closure_rewrite(input) return self, input end
    function Tr.IndexBaseExpr:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.IndexBasePlace:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.IndexBaseView:closure_rewrite(input)
        local view, input = self.view:closure_rewrite(input)
        if view == self.view then return self, input end
        return asdl.with(self, { view = view }), input
    end

    ------------------------------------------------------------------------
    -- Tr.Place: closure_rewrite
    ------------------------------------------------------------------------
    function Tr.Place:closure_rewrite(input) return self, input end
    function Tr.PlaceDeref:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.PlaceDot:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.PlaceField:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        if base == self.base then return self, input end
        return asdl.with(self, { base = base }), input
    end
    function Tr.PlaceIndex:closure_rewrite(input)
        local base, input = self.base:closure_rewrite(input)
        local index, input = self.index:closure_rewrite(input)
        if base == self.base and index == self.index then return self, input end
        return asdl.with(self, { base = base, index = index }), input
    end

    ------------------------------------------------------------------------
    -- Tr.Stmt: closure_rewrite
    ------------------------------------------------------------------------
    function Tr.Stmt:closure_rewrite(input) return self, input end
    function Tr.StmtLet:closure_rewrite(input)
        local init, input = self.init:closure_rewrite(input)
        if #input.scopes > 0 then input.scopes[#input.scopes][self.binding.name] = self.binding.ty end
        if init == self.init then return self, input end
        return asdl.with(self, { init = init }), input
    end
    function Tr.StmtVar:closure_rewrite(input)
        local init, input = self.init:closure_rewrite(input)
        if #input.scopes > 0 then input.scopes[#input.scopes][self.binding.name] = self.binding.ty end
        if init == self.init then return self, input end
        return asdl.with(self, { init = init }), input
    end
    function Tr.StmtSet:closure_rewrite(input)
        local place, input = self.place:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if place == self.place and value == self.value then return self, input end
        return asdl.with(self, { place = place, value = value }), input
    end
    function Tr.StmtAtomicStore:closure_rewrite(input)
        local addr, input = self.addr:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if addr == self.addr and value == self.value then return self, input end
        return asdl.with(self, { addr = addr, value = value }), input
    end
    function Tr.StmtExpr:closure_rewrite(input)
        local expr, input = self.expr:closure_rewrite(input)
        if expr == self.expr then return self, input end
        return asdl.with(self, { expr = expr }), input
    end
    function Tr.StmtAssert:closure_rewrite(input)
        local cond, input = self.cond:closure_rewrite(input)
        if cond == self.cond then return self, input end
        return asdl.with(self, { cond = cond }), input
    end
    function Tr.StmtIf:closure_rewrite(input)
        local cond, input = self.cond:closure_rewrite(input)
        local then_body, input = _rewrite_stmts(self.then_body, input)
        local else_body, input = _rewrite_stmts(self.else_body, input)
        return asdl.with(self, { cond = cond, then_body = then_body, else_body = else_body }), input
    end
    function Tr.StmtSwitch:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        local arms = {}
        for i = 1, #self.arms do
            local body, input2 = _rewrite_stmts(self.arms[i].body, input)
            input = input2
            arms[i] = asdl.with(self.arms[i], { body = body })
        end
        local var_arms = {}
        for i = 1, #(self.variant_arms or {}) do
            local body, input2 = _rewrite_stmts(self.variant_arms[i].body, input)
            input = input2
            var_arms[i] = asdl.with(self.variant_arms[i], { body = body })
        end
        local default_body, input = _rewrite_stmts(self.default_body or {}, input)
        return asdl.with(self, { value = value, arms = arms, variant_arms = var_arms, default_body = default_body }), input
    end
    function Tr.StmtJump:closure_rewrite(input)
        local changed = false
        local args = {}
        for i = 1, #(self.args or {}) do
            local val, input2 = self.args[i].value:closure_rewrite(input)
            input = input2
            if val ~= self.args[i].value then changed = true end
            args[i] = changed and asdl.with(self.args[i], { value = val }) or self.args[i]
        end
        if not changed then return self, input end
        return asdl.with(self, { args = args }), input
    end
    function Tr.StmtJumpCont:closure_rewrite(input)
        local changed = false
        local args = {}
        for i = 1, #(self.args or {}) do
            local val, input2 = self.args[i].value:closure_rewrite(input)
            input = input2
            if val ~= self.args[i].value then changed = true end
            args[i] = changed and asdl.with(self.args[i], { value = val }) or self.args[i]
        end
        if not changed then return self, input end
        return asdl.with(self, { args = args }), input
    end
    function Tr.StmtYieldValue:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if value == self.value then return self, input end
        return asdl.with(self, { value = value }), input
    end
    function Tr.StmtReturnValue:closure_rewrite(input)
        local value, input = self.value:closure_rewrite(input)
        if value == self.value then return self, input end
        return asdl.with(self, { value = value }), input
    end
    function Tr.StmtControl:closure_rewrite(input)
        local blocks = {}
        for i = 1, #self.region.blocks do
            local body, input2 = _rewrite_stmts(self.region.blocks[i].body, input)
            input = input2
            blocks[i] = asdl.with(self.region.blocks[i], { body = body })
        end
        local entry_params = {}
        for i = 1, #self.region.entry.params do
            local init, input2 = self.region.entry.params[i].init:closure_rewrite(input)
            input = input2
            entry_params[i] = asdl.with(self.region.entry.params[i], { init = init })
        end
        local entry_body, input = _rewrite_stmts(self.region.entry.body, input)
        local entry = asdl.with(self.region.entry, { params = entry_params, body = entry_body })
        return asdl.with(self, { region = asdl.with(self.region, { entry = entry, blocks = blocks }) }), input
    end

    ------------------------------------------------------------------------
    -- Tr.Func: closure_rewrite
    ------------------------------------------------------------------------
    function Tr.Func:closure_rewrite(input)
        local saved_owner = input.owner
        push_scope(input, params_scope(self.params or {}))
        local body, input = _rewrite_stmts(self.body, input)
        pop_scope(input)
        input.owner = saved_owner
        return asdl.with(self, { body = body }), input
    end
    function Tr.FuncLocal:closure_rewrite(input)
        input.owner = self.name
        return Tr.Func.closure_rewrite(self, input)
    end
    function Tr.FuncExport:closure_rewrite(input)
        input.owner = self.name
        return Tr.Func.closure_rewrite(self, input)
    end
    function Tr.FuncLocalContract:closure_rewrite(input)
        input.owner = self.name
        return Tr.Func.closure_rewrite(self, input)
    end
    function Tr.FuncExportContract:closure_rewrite(input)
        input.owner = self.name
        return Tr.Func.closure_rewrite(self, input)
    end

    ------------------------------------------------------------------------
    -- Tr.Item: closure_rewrite
    ------------------------------------------------------------------------
    function Tr.Item:closure_rewrite(input) return self, input end
    function Tr.ItemFunc:closure_rewrite(input)
        local func, input = self.func:closure_rewrite(input)
        if func == self.func then return self, input end
        return asdl.with(self, { func = func }), input
    end
    function Tr.ItemConst:closure_rewrite(input)
        local value, input = self.c.value:closure_rewrite(input)
        if value == self.c.value then return self, input end
        return asdl.with(self, { c = asdl.with(self.c, { value = value }) }), input
    end
    function Tr.ItemStatic:closure_rewrite(input)
        local value, input = self.s.value:closure_rewrite(input)
        if value == self.s.value then return self, input end
        return asdl.with(self, { s = asdl.with(self.s, { value = value }) }), input
    end

    ------------------------------------------------------------------------
    -- Rewrite helpers (defined after leaf methods, assigned to forward decls)
    ------------------------------------------------------------------------
    _rewrite_stmts = function(stmts, input)
        local out = {}
        for i = 1, #(stmts or {}) do
            out[i], input = stmts[i]:closure_rewrite(input)
        end
        return out, input
    end

    _closure_captures = function(expr, input)
        local locals = params_scope(expr.params)
        local out, seen = {}, {}
        _collect_captures_stmts(expr.body, input, locals, out, seen)
        return out
    end

    _helper_for_closure = function(input, expr, captures)
        local name = fresh_helper_name(input)
        captures = captures or _closure_captures(expr, input)
        local helper_params = clone(expr.params)
        for i = 1, #captures do helper_params[#helper_params + 1] = Ty.Param(captures[i].name, captures[i].ty) end
        local saved_owner = input.owner
        input.owner = name
        push_scope(input, params_scope(helper_params))
        local body, input = _rewrite_stmts(expr.body, input)
        pop_scope(input)
        input.owner = saved_owner
        local helper = Tr.FuncLocal(name, helper_params, expr.result, body)
        input.helpers[#input.helpers + 1] = Tr.ItemFunc(helper)
        return name, input
    end

    _helper_for_escaping_closure = function(input, expr, captures)
        local name = fresh_helper_name(input)
        captures = captures or _closure_captures(expr, input)
        capture_layout(captures, input.target)
        local helper_params = { Ty.Param("__lalin_ctx", Ty.TPtr(Ty.TScalar(C.ScalarU8))) }
        for i = 1, #expr.params do helper_params[#helper_params + 1] = expr.params[i] end
        local capture_env = {}
        for i = 1, #captures do capture_env[captures[i].name] = captures[i] end
        local saved_owner = input.owner
        local saved_capture_env = input.capture_env
        local saved_scopes = input.scopes
        input.owner = name
        input.capture_env = capture_env
        input.scopes = {}
        push_scope(input, params_scope(helper_params))
        local body, input = _rewrite_stmts(expr.body, input)
        pop_scope(input)
        input.scopes = saved_scopes
        input.capture_env = saved_capture_env
        input.owner = saved_owner
        local helper = Tr.FuncLocal(name, helper_params, expr.result, body)
        input.helpers[#input.helpers + 1] = Tr.ItemFunc(helper)
        return name, input
    end

    ------------------------------------------------------------------------
    -- collect_captures_expr
    ------------------------------------------------------------------------
    function Tr.Expr:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprRef:closure_collect_captures(input, locals, out, seen)
        if not self.ref:closure_is_name_ref() then return end
        local name = self.ref:closure_captured_name()
        if locals[name] or seen[name] then return end
        local ty = scope_get(input, name)
        if ty ~= nil then seen[name] = true; out[#out + 1] = { name = name, ty = ty } end
    end
    function Tr.ExprUnary:closure_collect_captures(input, locals, out, seen) self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprDeref:closure_collect_captures(input, locals, out, seen) self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprLen:closure_collect_captures(input, locals, out, seen) self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprBinary:closure_collect_captures(input, locals, out, seen) self.lhs:closure_collect_captures(input, locals, out, seen); self.rhs:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprCompare:closure_collect_captures(input, locals, out, seen) self.lhs:closure_collect_captures(input, locals, out, seen); self.rhs:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprLogic:closure_collect_captures(input, locals, out, seen) self.lhs:closure_collect_captures(input, locals, out, seen); self.rhs:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprCast:closure_collect_captures(input, locals, out, seen) self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprMachineCast:closure_collect_captures(input, locals, out, seen) self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprIntrinsic:closure_collect_captures(input, locals, out, seen) for i = 1, #self.args do self.args[i]:closure_collect_captures(input, locals, out, seen) end end
    function Tr.ExprAddrOf:closure_collect_captures(input, locals, out, seen) self.place:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprCall:closure_collect_captures(input, locals, out, seen) self.callee:closure_collect_captures(input, locals, out, seen); for i = 1, #self.args do self.args[i]:closure_collect_captures(input, locals, out, seen) end end
    function Tr.ExprField:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprDot:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprIndex:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen); self.index:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprAgg:closure_collect_captures(input, locals, out, seen) for i = 1, #self.fields do self.fields[i].value:closure_collect_captures(input, locals, out, seen) end end
    function Tr.ExprCtor:closure_collect_captures(input, locals, out, seen) for i = 1, #(self.args or {}) do self.args[i]:closure_collect_captures(input, locals, out, seen) end end
    function Tr.ExprArray:closure_collect_captures(input, locals, out, seen) for i = 1, #self.elems do self.elems[i]:closure_collect_captures(input, locals, out, seen) end end
    function Tr.ExprIf:closure_collect_captures(input, locals, out, seen) self.cond:closure_collect_captures(input, locals, out, seen); self.then_expr:closure_collect_captures(input, locals, out, seen); self.else_expr:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprSelect:closure_collect_captures(input, locals, out, seen) self.cond:closure_collect_captures(input, locals, out, seen); self.then_expr:closure_collect_captures(input, locals, out, seen); self.else_expr:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprBlock:closure_collect_captures(input, locals, out, seen)
        local inner = {}; for k, v in pairs(locals) do inner[k] = v end
        _collect_captures_stmts(self.stmts, input, inner, out, seen)
        self.result:closure_collect_captures(input, inner, out, seen)
    end
    function Tr.ExprView:closure_collect_captures(input, locals, out, seen) self.view:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprLoad:closure_collect_captures(input, locals, out, seen) self.addr:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprAtomicLoad:closure_collect_captures(input, locals, out, seen) self.addr:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprAtomicRmw:closure_collect_captures(input, locals, out, seen) self.addr:closure_collect_captures(input, locals, out, seen); self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.ExprAtomicCas:closure_collect_captures(input, locals, out, seen) self.addr:closure_collect_captures(input, locals, out, seen); self.expected:closure_collect_captures(input, locals, out, seen); self.replacement:closure_collect_captures(input, locals, out, seen) end

    ------------------------------------------------------------------------
    -- collect_captures_place
    ------------------------------------------------------------------------
    function Tr.Place:closure_collect_captures(input, locals, out, seen) end
    function Tr.PlaceRef:closure_collect_captures(input, locals, out, seen)
        if self.ref:closure_is_name_ref() then
            Tr.ExprRef(Tr.ExprSurface, self.ref):closure_collect_captures(input, locals, out, seen)
        end
    end
    function Tr.PlaceDeref:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.PlaceDot:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.PlaceField:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.PlaceIndex:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen); self.index:closure_collect_captures(input, locals, out, seen) end

    ------------------------------------------------------------------------
    -- collect_captures_index_base
    ------------------------------------------------------------------------
    function Tr.IndexBase:closure_collect_captures(input, locals, out, seen) end
    function Tr.IndexBaseExpr:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.IndexBasePlace:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.IndexBaseView:closure_collect_captures(input, locals, out, seen) self.view:closure_collect_captures(input, locals, out, seen) end

    ------------------------------------------------------------------------
    -- collect_captures_view
    ------------------------------------------------------------------------
    function Tr.View:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewFromExpr:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewContiguous:closure_collect_captures(input, locals, out, seen) self.data:closure_collect_captures(input, locals, out, seen); self.len:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewStrided:closure_collect_captures(input, locals, out, seen) self.data:closure_collect_captures(input, locals, out, seen); self.len:closure_collect_captures(input, locals, out, seen); self.stride:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewRestrided:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen); self.stride:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewWindow:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen); self.start:closure_collect_captures(input, locals, out, seen); self.len:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewRowBase:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen); self.row_offset:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewInterleaved:closure_collect_captures(input, locals, out, seen) self.data:closure_collect_captures(input, locals, out, seen); self.len:closure_collect_captures(input, locals, out, seen); self.stride:closure_collect_captures(input, locals, out, seen); self.lane:closure_collect_captures(input, locals, out, seen) end
    function Tr.ViewInterleavedView:closure_collect_captures(input, locals, out, seen) self.base:closure_collect_captures(input, locals, out, seen); self.stride:closure_collect_captures(input, locals, out, seen); self.lane:closure_collect_captures(input, locals, out, seen) end

    ------------------------------------------------------------------------
    -- collect_captures_stmts
    ------------------------------------------------------------------------
    function Tr.Stmt:closure_collect_captures(input, locals, out, seen) end
    function Tr.StmtLet:closure_collect_captures(input, locals, out, seen) self.init:closure_collect_captures(input, locals, out, seen); locals[self.binding.name] = self.binding.ty end
    function Tr.StmtVar:closure_collect_captures(input, locals, out, seen) self.init:closure_collect_captures(input, locals, out, seen); locals[self.binding.name] = self.binding.ty end
    function Tr.StmtSet:closure_collect_captures(input, locals, out, seen) self.place:closure_collect_captures(input, locals, out, seen); self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.StmtExpr:closure_collect_captures(input, locals, out, seen) self.expr:closure_collect_captures(input, locals, out, seen) end
    function Tr.StmtReturnValue:closure_collect_captures(input, locals, out, seen) self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.StmtYieldValue:closure_collect_captures(input, locals, out, seen) self.value:closure_collect_captures(input, locals, out, seen) end
    function Tr.StmtIf:closure_collect_captures(input, locals, out, seen)
        self.cond:closure_collect_captures(input, locals, out, seen)
        local a = {}; for k, v in pairs(locals) do a[k] = v end
        _collect_captures_stmts(self.then_body, input, a, out, seen)
        local b = {}; for k, v in pairs(locals) do b[k] = v end
        _collect_captures_stmts(self.else_body, input, b, out, seen)
    end

    _collect_captures_stmts = function(stmts, input, locals, out, seen)
        for i = 1, #(stmts or {}) do
            stmts[i]:closure_collect_captures(input, locals, out, seen)
        end
    end

    ------------------------------------------------------------------------
    -- Module-level public API
    ------------------------------------------------------------------------
    local function module_name(module)
        return module.h:tree_module_name()
    end

    local function rewrite_module(module, module_input)
        local input = {
            module_name = module_name(module),
            owner = "module",
            counter = 0,
            helpers = {},
            scopes = {},
            target = module_input.target,
        }
        local items = {}
        for i = 1, #module.items do
            local before = #input.helpers
            local rewritten
            rewritten, input = module.items[i]:closure_rewrite(input)
            for j = before + 1, #input.helpers do items[#items + 1] = input.helpers[j] end
            items[#items + 1] = rewritten
        end
        return asdl.with(module, { items = items })
    end

    local function rewrite_func(func, module_input)
        local input = {
            module_name = "",
            owner = "func",
            counter = 0,
            helpers = {},
            scopes = {},
            target = module_input.target,
        }
        local out, input = func:closure_rewrite(input)
        return out, input.helpers
    end

    return {
        module = rewrite_module,
        func = rewrite_func,
    }
end

return bind_context
