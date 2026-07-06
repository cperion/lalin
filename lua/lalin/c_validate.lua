local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.c_validate ~= nil then return T._lalin_api_cache.c_validate end

    local Core = T.LalinCore
    local C = T.LalinC
    require("lalin.c_emit")(T)
    local Coverage = require("lalin.c_coverage")

    local function is_c_name(s)
        return type(s) == "string" and s:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
    end

    local function align_ok(n)
        return type(n) == "number" and n >= 1 and n % 1 == 0 and (n == 1 or n % 2 == 0) and (function(x)
            while x > 1 do if x % 2 ~= 0 then return false end; x = x / 2 end
            return true
        end)(n)
    end

    local function index_by(items, key_fn, dup_issue, st)
        local by = {}
        for i = 1, #(items or {}) do
            local item = items[i]
            local key, ref = key_fn(item)
            if by[key] ~= nil then st:add(dup_issue(ref)) else by[key] = item end
        end
        return by
    end

    -- Type equality is leaf-owned double dispatch.  No ASDL class inspection: a
    -- type asks the other type whether it accepts this concrete left-hand shape.
    function C.CBackendType:c_validate_type_eq(other) return false end
    function C.CBackendType:c_validate_eq_void(left) return false end
    function C.CBackendType:c_validate_eq_bool8(left) return false end
    function C.CBackendType:c_validate_eq_scalar(left) return false end
    function C.CBackendType:c_validate_eq_index(left) return false end
    function C.CBackendType:c_validate_eq_data_ptr(left) return false end
    function C.CBackendType:c_validate_eq_code_ptr(left) return false end
    function C.CBackendType:c_validate_eq_imported_code_ptr(left) return false end
    function C.CBackendType:c_validate_eq_named(left) return false end
    function C.CBackendType:c_validate_eq_array(left) return false end
    function C.CBackendType:c_validate_eq_slice_descriptor(left) return false end
    function C.CBackendType:c_validate_eq_bytespan_descriptor(left) return false end
    function C.CBackendType:c_validate_eq_view_descriptor(left) return false end
    function C.CBackendType:c_validate_eq_closure_descriptor(left) return false end
    function C.CBackendType:c_validate_eq_hidden_out_ptr(left) return false end
    function C.CBackendType:c_validate_eq_vector(left) return false end

    function C.CBackendVoid:c_validate_type_eq(other) return other:c_validate_eq_void(self) end
    function C.CBackendVoid:c_validate_eq_void(left) return true end
    function C.CBackendBool8:c_validate_type_eq(other) return other:c_validate_eq_bool8(self) end
    function C.CBackendBool8:c_validate_eq_bool8(left) return true end
    function C.CBackendIndex:c_validate_type_eq(other) return other:c_validate_eq_index(self) end
    function C.CBackendIndex:c_validate_eq_index(left) return true end
    function C.CBackendScalar:c_validate_type_eq(other) return other:c_validate_eq_scalar(self) end
    function C.CBackendScalar:c_validate_eq_scalar(left) return self.scalar == left.scalar end
    function C.CBackendDataPtr:c_validate_type_eq(other) return other:c_validate_eq_data_ptr(self) end
    function C.CBackendDataPtr:c_validate_eq_data_ptr(left)
        if self.pointee == nil or left.pointee == nil then return true end
        return left.pointee:c_validate_type_eq(self.pointee)
    end
    function C.CBackendDataPtr:c_validate_eq_array(left) return self.pointee == nil or self.pointee:c_validate_type_eq(left.elem) end
    function C.CBackendCodePtr:c_validate_type_eq(other) return other:c_validate_eq_code_ptr(self) end
    function C.CBackendCodePtr:c_validate_eq_code_ptr(left) return self.sig.text == left.sig.text end
    function C.CBackendImportedCodePtr:c_validate_type_eq(other) return other:c_validate_eq_imported_code_ptr(self) end
    function C.CBackendImportedCodePtr:c_validate_eq_imported_code_ptr(left) return self.sig.text == left.sig.text end
    function C.CBackendNamed:c_validate_type_eq(other) return other:c_validate_eq_named(self) end
    function C.CBackendNamed:c_validate_eq_named(left) return self.id.module_name == left.id.module_name and self.id.spelling == left.id.spelling end
    function C.CBackendArray:c_validate_type_eq(other) return other:c_validate_eq_array(self) end
    function C.CBackendArray:c_validate_eq_array(left) return self.count == left.count and left.elem:c_validate_type_eq(self.elem) end
    function C.CBackendArray:c_validate_eq_data_ptr(left) return left.pointee == nil or self.elem:c_validate_type_eq(left.pointee) end
    function C.CBackendSliceDescriptor:c_validate_type_eq(other) return other:c_validate_eq_slice_descriptor(self) end
    function C.CBackendSliceDescriptor:c_validate_eq_slice_descriptor(left) return left.elem:c_validate_type_eq(self.elem) end
    function C.CBackendByteSpanDescriptor:c_validate_type_eq(other) return other:c_validate_eq_bytespan_descriptor(self) end
    function C.CBackendByteSpanDescriptor:c_validate_eq_bytespan_descriptor(left) return true end
    function C.CBackendViewDescriptor:c_validate_type_eq(other) return other:c_validate_eq_view_descriptor(self) end
    function C.CBackendViewDescriptor:c_validate_eq_view_descriptor(left) return left.elem:c_validate_type_eq(self.elem) end
    function C.CBackendClosureDescriptor:c_validate_type_eq(other) return other:c_validate_eq_closure_descriptor(self) end
    function C.CBackendClosureDescriptor:c_validate_eq_closure_descriptor(left)
        if self.sig.text ~= left.sig.text then return false end
        if self.ctx == nil or left.ctx == nil then return self.ctx == left.ctx end
        return left.ctx:c_validate_type_eq(self.ctx)
    end
    function C.CBackendAbiHiddenOutPtr:c_validate_type_eq(other) return other:c_validate_eq_hidden_out_ptr(self) end
    function C.CBackendAbiHiddenOutPtr:c_validate_eq_hidden_out_ptr(left) return left.result:c_validate_type_eq(self.result) end
    function C.CBackendVector:c_validate_type_eq(other) return other:c_validate_eq_vector(self) end
    function C.CBackendVector:c_validate_eq_vector(left) return self.lanes == left.lanes and left.elem:c_validate_type_eq(self.elem) end

    local function type_eq(a, b) return a ~= nil and b ~= nil and a:c_validate_type_eq(b) end

    function Core.Scalar:c_validate_static_size() return 0 end
    function Core.ScalarBool:c_validate_static_size() return 1 end
    function Core.ScalarI8:c_validate_static_size() return 1 end
    function Core.ScalarU8:c_validate_static_size() return 1 end
    function Core.ScalarI16:c_validate_static_size() return 2 end
    function Core.ScalarU16:c_validate_static_size() return 2 end
    function Core.ScalarI32:c_validate_static_size() return 4 end
    function Core.ScalarU32:c_validate_static_size() return 4 end
    function Core.ScalarF32:c_validate_static_size() return 4 end
    function Core.ScalarI64:c_validate_static_size() return 8 end
    function Core.ScalarU64:c_validate_static_size() return 8 end
    function Core.ScalarF64:c_validate_static_size() return 8 end
    function Core.ScalarIndex:c_validate_static_size() return 8 end
    function Core.ScalarRawPtr:c_validate_static_size() return 8 end
    function C.CBackendType:c_validate_static_size() return 0 end
    function C.CBackendBool8:c_validate_static_size() return 1 end
    function C.CBackendIndex:c_validate_static_size() return 8 end
    function C.CBackendScalar:c_validate_static_size() return self.scalar:c_validate_static_size() end
    function C.CBackendDataPtr:c_validate_static_size() return 8 end
    function C.CBackendCodePtr:c_validate_static_size() return 8 end
    function C.CBackendImportedCodePtr:c_validate_static_size() return 8 end

    function C.CBackendDataInit:c_validate_size() return 0 end
    function C.CBackendDataZero:c_validate_size() return self.size end
    function C.CBackendDataBytes:c_validate_size() return #self.bytes end
    function C.CBackendDataScalar:c_validate_size() return self.ty:c_validate_static_size() end
    function C.CBackendDataReloc:c_validate_size() return 8 end
    function C.CBackendDataInit:c_validate_reloc(st) end
    function C.CBackendDataReloc:c_validate_reloc(st) self.target:c_validate_reloc_target(st) end
    function C.CBackendRelocTarget:c_validate_reloc_target(st) end
    function C.CBackendRelocGlobal:c_validate_reloc_target(st) if st.globals[self.global.text] == nil then st:add(C.CBackendIssueMissingGlobal(self.global)) end end
    function C.CBackendRelocFunc:c_validate_reloc_target(st) if st.funcs[self.func.text] == nil then st:add(C.CBackendIssueMissingFunc(self.func)) end end
    function C.CBackendRelocExtern:c_validate_reloc_target(st) if st.externs[self["extern"].text] == nil then st:add(C.CBackendIssueMissingExtern(self["extern"])) end end

    function C.CBackendFuncBody:c_validate_blocks() return {} end
    function C.CBackendBodyBlocks:c_validate_blocks() return self.blocks end
    function C.CBackendBodyMixed:c_validate_blocks() return self.blocks end
    function C.CBackendBodyExec:c_validate_blocks() return {} end

    function C.CBackendAtom:c_validate_type(st, locals) return nil end
    function C.CBackendAtomLocal:c_validate_type(st, locals) return locals[self.local_id.text] end
    function C.CBackendAtomGlobal:c_validate_type(st, locals) local g = st.globals[self.global.text]; return g and g.ty or nil end
    function C.CBackendAtomLiteral:c_validate_type(st, locals) return self.ty end
    function C.CBackendAtomNull:c_validate_type(st, locals) return self.ty end
    function C.CBackendAtom:c_validate_check(st, func, locals, initialized) end
    function C.CBackendAtomLocal:c_validate_check(st, func, locals, initialized)
        if locals[self.local_id.text] == nil then st:add(C.CBackendIssueMissingLocal(func.name, self.local_id))
        elseif initialized ~= nil and initialized[self.local_id.text] == false then st:add(C.CBackendIssueUninitializedLocal(func.name, self.local_id)) end
    end
    function C.CBackendAtomGlobal:c_validate_check(st, func, locals, initialized) if st.globals[self.global.text] == nil then st:add(C.CBackendIssueMissingGlobal(self.global)) end end

    local function atom_type(atom, st, locals) return atom:c_validate_type(st, locals) end
    local function check_atom(atom, st, func, locals, initialized) atom:c_validate_check(st, func, locals, initialized) end

    function C.CBackendRValue:c_validate_type(st, func, locals, initialized) return nil end
    function C.CBackendRAtom:c_validate_type(st, func, locals, initialized) check_atom(self.atom, st, func, locals, initialized); return atom_type(self.atom, st, locals) end
    function C.CBackendRCompare:c_validate_type(st, func, locals, initialized) check_atom(self.lhs, st, func, locals, initialized); check_atom(self.rhs, st, func, locals, initialized); return C.CBackendBool8 end
    function C.CBackendRCast:c_validate_type(st, func, locals, initialized) check_atom(self.value, st, func, locals, initialized); return self.to end
    function C.CBackendRSelect:c_validate_type(st, func, locals, initialized) check_atom(self.cond, st, func, locals, initialized); check_atom(self.then_value, st, func, locals, initialized); check_atom(self.else_value, st, func, locals, initialized); return self.ty end
    function C.CBackendRFuncAddr:c_validate_type(st, func, locals, initialized) if st.funcs[self.func.text] == nil then st:add(C.CBackendIssueMissingFunc(self.func)) end; return C.CBackendCodePtr(self.sig) end
    function C.CBackendRExternAddr:c_validate_type(st, func, locals, initialized) if st.externs[self["extern"].text] == nil then st:add(C.CBackendIssueMissingExtern(self["extern"])) end; return C.CBackendCodePtr(self.sig) end
    function C.CBackendRPtrOffset:c_validate_type(st, func, locals, initialized) check_atom(self.base, st, func, locals, initialized); check_atom(self.index, st, func, locals, initialized); return C.CBackendDataPtr(nil) end
    function C.CBackendRAddrOfPlace:c_validate_type(st, func, locals, initialized) return C.CBackendDataPtr(self.place:c_validate_type(st, func, locals)) end

    function C.CBackendPlace:c_validate_type(st, func, locals) return nil end
    function C.CBackendPlace:c_validate_mark_initialized(mark_init) end
    function C.CBackendPlaceLocal:c_validate_type(st, func, locals) if locals[self.local_id.text] == nil then st:add(C.CBackendIssueMissingLocal(func.name, self.local_id)) end; return self.ty end
    function C.CBackendPlaceLocal:c_validate_mark_initialized(mark_init) mark_init(self.local_id) end
    function C.CBackendPlaceGlobal:c_validate_type(st, func, locals) if st.globals[self.global.text] == nil then st:add(C.CBackendIssueMissingGlobal(self.global)) end; return self.ty end
    function C.CBackendPlaceDeref:c_validate_type(st, func, locals) check_atom(self.addr, st, func, locals); return self.ty end
    function C.CBackendPlaceField:c_validate_type(st, func, locals) self.base:c_validate_type(st, func, locals); if self.align ~= nil and not align_ok(self.align) then st:add(C.CBackendIssueInvalidAlignment("place-field", self.align)) end; return self.ty end
    function C.CBackendPlaceIndex:c_validate_type(st, func, locals) self.base:c_validate_type(st, func, locals); check_atom(self.index, st, func, locals); return self.ty end
    function C.CBackendPlaceBytes:c_validate_type(st, func, locals) check_atom(self.base, st, func, locals); if not align_ok(self.align) then st:add(C.CBackendIssueInvalidAlignment("place-bytes", self.align)) end; return self.ty end

    function C.CBackendExecResult:c_validate_result(st, func, sig, locals, initialized, site) if sig ~= nil and not sig.result:c_emit_is_void() then st:add(C.CBackendIssueCallResultType("exec-return:" .. func.name.text, sig.id, sig.result, C.CBackendVoid)) end end
    function C.CBackendExecResultVoid:c_validate_result(st, func, sig, locals, initialized, site) if sig ~= nil and not sig.result:c_emit_is_void() then st:add(C.CBackendIssueCallResultType("exec-return:" .. func.name.text, sig.id, sig.result, C.CBackendVoid)) end end
    function C.CBackendExecResultLocal:c_validate_result(st, func, sig, locals, initialized, site)
        local dty = locals[self.dst.text]
        if dty == nil then
            st:add(C.CBackendIssueMissingLocal(func.name, self.dst))
        else
            if not type_eq(dty, self.ty) then st:add(C.CBackendIssueCallResultType("exec:" .. func.name.text, sig and sig.id or C.CBackendFuncSigId("<exec>"), self.ty, dty)) end
            if sig ~= nil and not type_eq(sig.result, dty) then st:add(C.CBackendIssueCallResultType("exec-return:" .. func.name.text, sig.id, sig.result, dty)) end
        end
        initialized[self.dst.text] = true
    end
    function C.CBackendExecSite:c_validate_site(st, func, sig, locals, initialized)
        for a = 1, #(self.args or {}) do
            local arg = self.args[a]
            check_atom(arg.atom, st, func, locals, initialized)
            local aty = atom_type(arg.atom, st, locals)
            if aty ~= nil and not type_eq(aty, arg.ty) then st:add(C.CBackendIssueCallArgType("exec:" .. tostring(arg.name), sig and sig.id or C.CBackendFuncSigId("<exec>"), a, arg.ty, aty)) end
        end
        self.result:c_validate_result(st, func, sig, locals, initialized, self)
    end

    local function check_call_sig(st, site, sig, args, dst, locals)
        if sig == nil then return end
        if #args ~= #sig.params then st:add(C.CBackendIssueCallArgCount(site, sig.id, #sig.params, #args)) end
        local n = math.min(#args, #sig.params)
        for i = 1, n do
            local aty = atom_type(args[i], st, locals)
            if aty and not type_eq(aty, sig.params[i]) then st:add(C.CBackendIssueCallArgType(site, sig.id, i, sig.params[i], aty)) end
        end
        if dst ~= nil then
            local dty = locals[dst.text]
            if dty and not type_eq(dty, sig.result) then st:add(C.CBackendIssueCallResultType(site, sig.id, sig.result, dty)) end
        elseif not sig.result:c_emit_is_void() then
            st:add(C.CBackendIssueCallResultType(site, sig.id, sig.result, C.CBackendVoid))
        end
    end

    function C.CBackendCallTarget:c_validate_call(st, func, locals, call) end
    function C.CBackendCallDirect:c_validate_call(st, func, locals, call)
        local tf = st.funcs[self.func.text]
        if not tf then st:add(C.CBackendIssueMissingFunc(self.func)) else check_call_sig(st, "call:" .. self.func.text, st.sigs[tf.sig.text], call.args, call.dst, locals) end
    end
    function C.CBackendCallExtern:c_validate_call(st, func, locals, call)
        local te = st.externs[self["extern"].text]
        if not te then st:add(C.CBackendIssueMissingExtern(self["extern"])) else check_call_sig(st, "extern:" .. self["extern"].text, st.sigs[te.sig.text], call.args, call.dst, locals) end
    end
    function C.CBackendCallIndirect:c_validate_call(st, func, locals, call)
        check_atom(self.callee, st, func, locals)
        local cty = atom_type(self.callee, st, locals)
        if not cty or not cty:c_validate_is_code_ptr() then st:add(C.CBackendIssueIndirectCallNonCodePtr("indirect", cty or C.CBackendVoid))
        elseif cty.sig.text ~= self.sig.text then st:add(C.CBackendIssueDataCodePtrConfusion("indirect", cty)) end
        check_call_sig(st, "indirect", st.sigs[self.sig.text], call.args, call.dst, locals)
    end
    function C.CBackendCallClosure:c_validate_call(st, func, locals, call)
        check_atom(self.closure, st, func, locals)
        local cty = atom_type(self.closure, st, locals)
        if not cty or not cty:c_validate_is_closure_descriptor() then st:add(C.CBackendIssueIndirectCallNonCodePtr("closure", cty or C.CBackendVoid)) end
        check_call_sig(st, "closure", st.sigs[self.sig.text], call.args, call.dst, locals)
    end
    function C.CBackendType:c_validate_is_code_ptr() return false end
    function C.CBackendCodePtr:c_validate_is_code_ptr() return true end
    function C.CBackendType:c_validate_is_closure_descriptor() return false end
    function C.CBackendClosureDescriptor:c_validate_is_closure_descriptor() return true end

    function C.CBackendStmt:c_validate_stmt(st, func, locals, initialized, mark_init) end
    function C.CBackendAssign:c_validate_stmt(st, func, locals, initialized, mark_init)
        if locals[self.dst.text] == nil then st:add(C.CBackendIssueMissingLocal(func.name, self.dst)) end
        local rty = self.rhs:c_validate_type(st, func, locals, initialized)
        if rty and locals[self.dst.text] and not type_eq(rty, locals[self.dst.text]) then st:add(C.CBackendIssueCallResultType("assign:" .. self.dst.text, C.CBackendFuncSigId("<assign>"), locals[self.dst.text], rty)) end
        mark_init(self.dst)
    end
    function C.CBackendHelperCall:c_validate_stmt(st, func, locals, initialized, mark_init)
        local helper = st.helpers[self.helper.text]
        if helper == nil then st:add(C.CBackendIssueMissingHelper(self.helper)) end
        local actual = {}
        for a = 1, #self.args do check_atom(self.args[a], st, func, locals, initialized); actual[a] = atom_type(self.args[a], st, locals) or C.CBackendVoid end
        if helper ~= nil then
            local ok, hsig = pcall(function() return helper:c_helper_signature() end)
            if not ok or hsig == nil then
                st:add(C.CBackendIssueHelperMismatch(self.helper, tostring(hsig)))
            else
                local mismatch = (#actual ~= #hsig.params)
                local n = math.min(#actual, #hsig.params)
                for a = 1, n do if not type_eq(actual[a], hsig.params[a]) then mismatch = true end end
                if self.dst ~= nil then
                    local dty = locals[self.dst.text]
                    if dty == nil then st:add(C.CBackendIssueMissingLocal(func.name, self.dst)) elseif not type_eq(dty, hsig.result) then mismatch = true end
                elseif not hsig.result:c_emit_is_void() then mismatch = true end
                if mismatch then st:add(C.CBackendIssueHelperSignatureMismatch(self.helper, hsig.params, actual)) end
            end
        end
        mark_init(self.dst)
    end
    function C.CBackendLoad:c_validate_stmt(st, func, locals, initialized, mark_init) check_atom(self.addr, st, func, locals, initialized); if not align_ok(self.access.align) then st:add(C.CBackendIssueInvalidAlignment("load", self.access.align)) end; if locals[self.dst.text] == nil then st:add(C.CBackendIssueMissingLocal(func.name, self.dst)) end; mark_init(self.dst) end
    function C.CBackendStore:c_validate_stmt(st, func, locals, initialized, mark_init) check_atom(self.addr, st, func, locals, initialized); check_atom(self.value, st, func, locals, initialized); if not align_ok(self.access.align) then st:add(C.CBackendIssueInvalidAlignment("store", self.access.align)) end end
    function C.CBackendPlaceLoad:c_validate_stmt(st, func, locals, initialized, mark_init)
        local pty = self.place:c_validate_type(st, func, locals); local dty = locals[self.dst.text]
        if dty == nil then st:add(C.CBackendIssueMissingLocal(func.name, self.dst)) elseif pty ~= nil and not type_eq(pty, dty) then st:add(C.CBackendIssuePlaceTypeMismatch("place-load", self.place, dty, pty)) end
        mark_init(self.dst)
    end
    function C.CBackendPlaceStore:c_validate_stmt(st, func, locals, initialized, mark_init)
        local pty = self.place:c_validate_type(st, func, locals); check_atom(self.value, st, func, locals, initialized); local vty = atom_type(self.value, st, locals)
        if pty ~= nil and vty ~= nil and not type_eq(pty, vty) then st:add(C.CBackendIssuePlaceTypeMismatch("place-store", self.place, pty, vty)) end
        self.place:c_validate_mark_initialized(mark_init)
    end
    function C.CBackendZeroInit:c_validate_stmt(st, func, locals, initialized, mark_init)
        local pty = self.place:c_validate_type(st, func, locals)
        if pty ~= nil and not type_eq(pty, self.ty) then st:add(C.CBackendIssuePlaceTypeMismatch("zero-init", self.place, self.ty, pty)) end
        self.place:c_validate_mark_initialized(mark_init)
    end
    function C.CBackendAggregateInit:c_validate_stmt(st, func, locals, initialized, mark_init)
        local pty = self.place:c_validate_type(st, func, locals)
        if pty ~= nil and not type_eq(pty, self.ty) then st:add(C.CBackendIssuePlaceTypeMismatch("aggregate-init", self.place, self.ty, pty)) end
        for a = 1, #self.fields do check_atom(self.fields[a].value, st, func, locals, initialized) end
        self.place:c_validate_mark_initialized(mark_init)
    end
    function C.CBackendArrayInit:c_validate_stmt(st, func, locals, initialized, mark_init)
        local pty = self.place:c_validate_type(st, func, locals)
        if pty ~= nil and not type_eq(pty, self.ty) then st:add(C.CBackendIssuePlaceTypeMismatch("array-init", self.place, self.ty, pty)) end
        for a = 1, #self.elems do if self.elems[a].index < 0 then st:add(C.CBackendIssueLoadStoreTypeMismatch("array-init-index", C.CBackendIndex, C.CBackendVoid)) end; check_atom(self.elems[a].value, st, func, locals, initialized) end
        self.place:c_validate_mark_initialized(mark_init)
    end
    function C.CBackendCall:c_validate_stmt(st, func, locals, initialized, mark_init) for a = 1, #self.args do check_atom(self.args[a], st, func, locals, initialized) end; self.target:c_validate_call(st, func, locals, self); mark_init(self.dst) end

    local function check_transfer(st, func, labels, locals, dest, args)
        local block = labels[dest.text]
        if not block then st:add(C.CBackendIssueMissingLabel(func.name, dest)); return end
        if #args ~= #block.params then st:add(C.CBackendIssueBlockArgCount(func.name, dest, #block.params, #args)) end
        local n = math.min(#args, #block.params)
        for i = 1, n do
            local aty = atom_type(args[i], st, locals)
            check_atom(args[i], st, func, locals)
            if aty and not type_eq(aty, block.params[i].ty) then st:add(C.CBackendIssueBlockArgType(func.name, dest, i, block.params[i].ty, aty)) end
        end
    end

    function C.CBackendTerminator:c_validate_term(st, func, labels, locals, initialized) end
    function C.CBackendGoto:c_validate_term(st, func, labels, locals, initialized) check_transfer(st, func, labels, locals, self.dest, self.args) end
    function C.CBackendIfGoto:c_validate_term(st, func, labels, locals, initialized) check_atom(self.cond, st, func, locals, initialized); check_transfer(st, func, labels, locals, self.then_dest, self.then_args); check_transfer(st, func, labels, locals, self.else_dest, self.else_args) end
    function C.CBackendSwitchCase:c_validate_case(st, func, labels, locals) check_transfer(st, func, labels, locals, self.dest, self.args) end
    function C.CBackendSwitchGoto:c_validate_term(st, func, labels, locals, initialized) check_atom(self.value, st, func, locals, initialized); for k = 1, #self.cases do self.cases[k]:c_validate_case(st, func, labels, locals) end; check_transfer(st, func, labels, locals, self.default_dest, self.default_args) end
    function C.CBackendReturn:c_validate_term(st, func, labels, locals, initialized) check_atom(self.value, st, func, locals, initialized) end

    function C.CBackendTypeDecl:c_validate_decl(st) end
    function C.CBackendStructDecl:c_validate_decl(st) if self.size == nil or self.align == nil then st:add(C.CBackendIssueLayoutAssertionMissing(self.id)) end; if self.align ~= nil and not align_ok(self.align) then st:add(C.CBackendIssueInvalidAlignment("type:" .. self.id.spelling, self.align)) end end
    function C.CBackendUnionDecl:c_validate_decl(st) if self.size == nil or self.align == nil then st:add(C.CBackendIssueLayoutAssertionMissing(self.id)) end; if self.align ~= nil and not align_ok(self.align) then st:add(C.CBackendIssueInvalidAlignment("type:" .. self.id.spelling, self.align)) end end

    function C.CBackendHelperSpec:c_validate_helper_target(st, use) end
    function C.CBackendHelperAtomicLoad:c_validate_helper_target(st, use) if not st.target_has_c11_atomics then st:add(C.CBackendIssueInvalidTargetFeature(C.CBackendFeatureC11Atomics, "atomic helper requires C11 atomics or runtime provider")) end end
    function C.CBackendHelperAtomicStore:c_validate_helper_target(st, use) if not st.target_has_c11_atomics then st:add(C.CBackendIssueInvalidTargetFeature(C.CBackendFeatureC11Atomics, "atomic helper requires C11 atomics or runtime provider")) end end
    function C.CBackendHelperAtomicRmw:c_validate_helper_target(st, use) if not st.target_has_c11_atomics then st:add(C.CBackendIssueInvalidTargetFeature(C.CBackendFeatureC11Atomics, "atomic helper requires C11 atomics or runtime provider")) end end
    function C.CBackendHelperAtomicCas:c_validate_helper_target(st, use) if not st.target_has_c11_atomics then st:add(C.CBackendIssueInvalidTargetFeature(C.CBackendFeatureC11Atomics, "atomic helper requires C11 atomics or runtime provider")) end end
    function C.CBackendHelperAtomicFence:c_validate_helper_target(st, use) if not st.target_has_c11_atomics then st:add(C.CBackendIssueInvalidTargetFeature(C.CBackendFeatureC11Atomics, "atomic helper requires C11 atomics or runtime provider")) end end
    function C.CBackendHelperRequireFeature:c_validate_helper_target(st, use) st:add(C.CBackendIssueInvalidTargetFeature(self.feature, self.reason)) end

    function C.CBackendLocalInitState:c_validate_is_initialized() return true end
    function C.CBackendLocalUninitialized:c_validate_is_initialized() return false end
    function C.CBackendResidence:c_validate_address_taken_ok() return true end
    function C.CBackendResidenceValue:c_validate_address_taken_ok() return false end

    local function make_initialized(func, storage)
        local initialized = {}
        for _, p in ipairs(func.params) do initialized[p.id.text] = true end
        for id, rec in pairs(storage or {}) do initialized[id] = rec.init_state:c_validate_is_initialized() end
        return initialized
    end

    local function validate_func_body_prefix(st, func, sig, locals, storage)
        local initialized = make_initialized(func, storage)
        func.body:c_validate_exec_prefix(st, func, sig, locals, initialized)
    end
    function C.CBackendFuncBody:c_validate_exec_prefix(st, func, sig, locals, initialized) end
    function C.CBackendBodyExec:c_validate_exec_prefix(st, func, sig, locals, initialized) self.fragment:c_validate_site(st, func, sig, locals, initialized) end
    function C.CBackendBodyMixed:c_validate_exec_prefix(st, func, sig, locals, initialized) for _, site in ipairs(self.fragments or {}) do site:c_validate_site(st, func, nil, locals, initialized) end end

    local function validate_input(input, collector)
        local unit = input.unit or input
        local issues = {}
        local st = {
            unit = unit,
            issues = issues,
            collector = collector,
            add = function(self, issue)
                self.issues[#self.issues + 1] = issue
                if self.collector and self.collector.emit then pcall(function() self.collector:emit(issue, "c") end) end
            end,
        }
        for i = 1, #(input.abi_issues or {}) do st:add(input.abi_issues[i]) end
        local storage_by_func = {}
        for i = 1, #(input.storage or {}) do
            local rec = input.storage[i]
            local by_local = storage_by_func[rec.func.text] or {}
            storage_by_func[rec.func.text] = by_local
            for j = 1, #rec.storage do by_local[rec.storage[j].id.text] = rec.storage[j] end
        end
        local valid_coverage_status = Coverage.statuses()
        for sum_name, table_ in pairs(Coverage.all_tables()) do
            for variant, c in pairs(table_) do
                if not valid_coverage_status[c.status] then st:add(C.CBackendIssueCoverageMissing(sum_name, variant)) end
            end
        end
        st.sigs = index_by(unit.sigs, function(s) return s.id.text, s.id end, function(id) return C.CBackendIssueDuplicateSig(id) end, st)
        st.globals = index_by(unit.globals, function(g) return g.id.text, g.id end, function(id) return C.CBackendIssueDuplicateGlobal(id) end, st)
        st.externs = index_by(unit.externs, function(e) return e.name.text, e.name end, function(n) return C.CBackendIssueDuplicateExtern(n) end, st)
        st.helpers = index_by(unit.helpers, function(h) return h.id.text, h.id end, function(id) return C.CBackendIssueDuplicateHelper(id) end, st)
        st.funcs = index_by(unit.funcs, function(f) return f.name.text, f.name end, function(n) return C.CBackendIssueDuplicateFunc(n) end, st)
        st.target_has_c11_atomics = unit.target ~= nil and unit.target.dialect:c_emit_supports_c11_atomics()

        local c_names = {}
        local function check_c_name(site, name)
            if not is_c_name(name.text) then st:add(C.CBackendIssueInvalidCName(site, name)) end
            local key = site .. ":" .. name.text
            if c_names[key] then st:add(C.CBackendIssueDuplicateCName(site, name)) end
            c_names[key] = true
        end
        for i = 1, #unit.funcs do check_c_name("func", unit.funcs[i].name) end
        for i = 1, #unit.externs do check_c_name("extern", unit.externs[i].name) end
        for i = 1, #unit.globals do check_c_name("global", unit.globals[i].name) end

        for i = 1, #unit.globals do
            local g = unit.globals[i]
            if not align_ok(g.align) then st:add(C.CBackendIssueInvalidAlignment("global:" .. g.id.text, g.align)) end
            for j = 1, #g.inits do
                local init = g.inits[j]
                local off = init.offset or 0
                local sz = init:c_validate_size()
                if off < 0 or off + sz > g.size then st:add(C.CBackendIssueDataInitOutOfBounds(g.id, off, sz, g.size)) end
                init:c_validate_reloc(st)
            end
        end

        for i = 1, #unit.externs do if st.sigs[unit.externs[i].sig.text] == nil then st:add(C.CBackendIssueMissingSig(unit.externs[i].sig)) end end
        for i = 1, #unit.helpers do
            local ok, sig_or_err = pcall(function() return unit.helpers[i]:c_helper_signature() end)
            if not ok or not sig_or_err then st:add(C.CBackendIssueHelperMismatch(unit.helpers[i].id, tostring(sig_or_err))) end
        end
        for i = 1, #unit.types do unit.types[i]:c_validate_decl(st) end
        for i = 1, #unit.helpers do unit.helpers[i].spec:c_validate_helper_target(st, unit.helpers[i]) end

        for i = 1, #unit.funcs do
            local func = unit.funcs[i]
            local sig = st.sigs[func.sig.text]
            if sig == nil then st:add(C.CBackendIssueMissingSig(func.sig)) end
            local locals, labels = {}, {}
            for j = 1, #func.params do
                local p = func.params[j]
                if locals[p.id.text] then st:add(C.CBackendIssueDuplicateLocal(func.name, p.id)) end
                locals[p.id.text] = p.ty
                if sig and sig.params[j] and not type_eq(sig.params[j], p.ty) then st:add(C.CBackendIssueFuncSigMismatch(func.name, sig.params[j], p.ty)) end
            end
            if sig and #func.params ~= #sig.params then st:add(C.CBackendIssueCallArgCount("func:" .. func.name.text, sig.id, #sig.params, #func.params)) end
            for j = 1, #func.locals do
                local l = func.locals[j]
                if locals[l.id.text] then st:add(C.CBackendIssueDuplicateLocal(func.name, l.id)) end
                locals[l.id.text] = l.ty
            end
            local storage = storage_by_func[func.name.text] or {}
            validate_func_body_prefix(st, func, sig, locals, storage)
            local blocks = assert(func.body, "CBackendFunc requires body"):c_validate_blocks()
            for j = 1, #blocks do
                local b = blocks[j]
                if labels[b.label.text] then st:add(C.CBackendIssueDuplicateLabel(func.name, b.label)) end
                labels[b.label.text] = b
                for k = 1, #b.params do locals[b.params[k].local_id.text] = b.params[k].ty end
            end
            for _, rec in pairs(storage) do if rec.address_taken and not rec.residence:c_validate_address_taken_ok() then st:add(C.CBackendIssueUnmaterializedAddressTakenValue(func.name, rec.id)) end end
            for j = 1, #blocks do
                local b = blocks[j]
                local initialized = make_initialized(func, storage)
                for _, bp in ipairs(b.params) do initialized[bp.local_id.text] = true end
                local function mark_init(id) if id ~= nil then initialized[id.text] = true end end
                for k = 1, #b.stmts do b.stmts[k]:c_validate_stmt(st, func, locals, initialized, mark_init) end
                b.term:c_validate_term(st, func, labels, locals, initialized)
            end
        end

        return C.CBackendValidationReport(issues)
    end

    local function validate(unit, collector) return validate_input(C.CBackendValidationInput(unit, {}, {}), collector) end

    local api = { validate = validate, validate_input = validate_input }
    T._lalin_api_cache.c_validate = api
    return api
end

return bind_context
