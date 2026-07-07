local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.c_emit ~= nil then return T._lalin_api_cache.c_emit end

    local Core = T.LalinCore
    local C = T.LalinC
    local CEm = T.LalinCEmit
    local Exec = T.LalinExec
    local asdl = require("lalin.asdl")
    local function append_all(out, xs) for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end end

    local function sanitize(s)
        s = tostring(s or "x"):gsub("[^%w_]", "_")
        if s:match("^%d") then s = "_" .. s end
        if s == "" then s = "x" end
        return s
    end

    local function c_string_literal(bytes)
        local out = { '"' }
        for i = 1, #bytes do
            local b = bytes:byte(i)
            if b == 34 then out[#out + 1] = '\\"'
            elseif b == 92 then out[#out + 1] = "\\\\"
            elseif b == 10 then out[#out + 1] = "\\n"
            elseif b == 13 then out[#out + 1] = "\\r"
            elseif b == 9 then out[#out + 1] = "\\t"
            elseif b >= 32 and b <= 126 then out[#out + 1] = string.char(b)
            else out[#out + 1] = string.format("\\x%02x", b) end
        end
        out[#out + 1] = '"'
        return table.concat(out)
    end

    local function c_type_name(ty) return ty:c_emit_type() end
    local function decl(ty, name) return ty:c_emit_decl(name) end
    local function atom(a) return a:c_emit_atom() end
    local function place(p) return p:c_emit_place() end
    local function rvalue(rv) return rv:c_emit_rvalue() end
    local function literal(lit) return lit:c_emit_literal() end

    function Core.Scalar:c_emit_scalar_name() error("missing c_emit_scalar_name leaf method", 2) end
    function Core.ScalarBool:c_emit_scalar_name() return "uint8_t" end
    function Core.ScalarI8:c_emit_scalar_name() return "int8_t" end
    function Core.ScalarI16:c_emit_scalar_name() return "int16_t" end
    function Core.ScalarI32:c_emit_scalar_name() return "int32_t" end
    function Core.ScalarI64:c_emit_scalar_name() return "int64_t" end
    function Core.ScalarU8:c_emit_scalar_name() return "uint8_t" end
    function Core.ScalarU16:c_emit_scalar_name() return "uint16_t" end
    function Core.ScalarU32:c_emit_scalar_name() return "uint32_t" end
    function Core.ScalarU64:c_emit_scalar_name() return "uint64_t" end
    function Core.ScalarF32:c_emit_scalar_name() return "float" end
    function Core.ScalarF64:c_emit_scalar_name() return "double" end
    function Core.ScalarRawPtr:c_emit_scalar_name() return "void*" end
    function Core.ScalarIndex:c_emit_scalar_name() return "intptr_t" end
    function Core.ScalarVoid:c_emit_scalar_name() return "void" end

    function Core.Literal:c_emit_literal() error("missing c_emit_literal leaf method", 2) end
    function Core.LitInt:c_emit_literal() return self.raw end
    function Core.LitFloat:c_emit_literal() return self.raw end
    function Core.LitBool:c_emit_literal() return self.value and "1" or "0" end
    function Core.LitNil:c_emit_literal() return "0" end
    function Core.LitString:c_emit_literal() return c_string_literal(self.bytes) end

    function Core.CmpOp:c_emit_cmp_op() error("missing c_emit_cmp_op leaf method", 2) end
    function Core.CmpEq:c_emit_cmp_op() return "==" end
    function Core.CmpNe:c_emit_cmp_op() return "!=" end
    function Core.CmpLt:c_emit_cmp_op() return "<" end
    function Core.CmpLe:c_emit_cmp_op() return "<=" end
    function Core.CmpGt:c_emit_cmp_op() return ">" end
    function Core.CmpGe:c_emit_cmp_op() return ">=" end

    function Core.CmpOp:c_helper_suffix() error("missing c_helper_suffix leaf method for CmpOp", 2) end
    function Core.CmpEq:c_helper_suffix() return "eq" end
    function Core.CmpNe:c_helper_suffix() return "ne" end
    function Core.CmpLt:c_helper_suffix() return "lt" end
    function Core.CmpLe:c_helper_suffix() return "le" end
    function Core.CmpGt:c_helper_suffix() return "gt" end
    function Core.CmpGe:c_helper_suffix() return "ge" end

    function C.CBackendType:c_emit_type() error("missing c_emit_type leaf method for CBackendType", 2) end
    function C.CBackendType:c_emit_decl(name) return self:c_emit_type() .. " " .. name end
    function C.CBackendType:c_emit_named_deps(out) end
    function C.CBackendType:c_emit_visit_implicit(add_descriptor, add_closure) end
    function C.CBackendType:c_emit_is_array() return false end
    function C.CBackendType:c_emit_needs_compound_decl_only() return false end
    function C.CBackendType:c_emit_is_void() return false end
    function C.CBackendType:c_emit_can_hoist_field_load() return false end
    function C.CBackendType:c_emit_can_copy_propagate() return false end

    function C.CBackendVoid:c_emit_type() return "void" end
    function C.CBackendVoid:c_emit_is_void() return true end
    function C.CBackendBool8:c_emit_type() return "uint8_t" end
    function C.CBackendBool8:c_emit_can_copy_propagate() return true end
    function C.CBackendScalar:c_emit_type() return self.scalar:c_emit_scalar_name() end
    function C.CBackendScalar:c_emit_can_copy_propagate() return true end
    function C.CBackendIndex:c_emit_type() return "ml_index" end
    function C.CBackendIndex:c_emit_can_copy_propagate() return true end
    function C.CBackendDataPtr:c_emit_type() return self.pointee and (self.pointee:c_emit_type() .. "*") or "void*" end
    function C.CBackendDataPtr:c_emit_can_hoist_field_load() return true end
    function C.CBackendDataPtr:c_emit_can_copy_propagate() return true end
    function C.CBackendDataPtr:c_emit_visit_implicit(add_descriptor, add_closure) if self.pointee then self.pointee:c_emit_visit_implicit(add_descriptor, add_closure) end end
    function C.CBackendQualifiedDataPtr:c_emit_type()
        local q = {}
        if self.const_pointee then q[#q + 1] = "const" end
        if self.volatile_pointee then q[#q + 1] = "volatile" end
        local base = self.pointee and self.pointee:c_emit_type() or "void"
        local left = (#q > 0 and (table.concat(q, " ") .. " ") or "") .. base .. "*"
        return self.restrict_ptr and (left .. " restrict") or left
    end
    function C.CBackendQualifiedDataPtr:c_emit_can_hoist_field_load() return true end
    function C.CBackendQualifiedDataPtr:c_emit_can_copy_propagate() return true end
    function C.CBackendQualifiedDataPtr:c_emit_visit_implicit(add_descriptor, add_closure) if self.pointee then self.pointee:c_emit_visit_implicit(add_descriptor, add_closure) end end
    function C.CBackendType:c_emit_points_to_place_type(_ty) return false end
    function C.CBackendDataPtr:c_emit_points_to_place_type(ty) return self.pointee ~= nil and self.pointee:c_emit_type() == ty:c_emit_type() end
    function C.CBackendQualifiedDataPtr:c_emit_points_to_place_type(ty) return self.pointee ~= nil and self.pointee:c_emit_type() == ty:c_emit_type() end
    function C.CBackendCodePtr:c_emit_type() return self.sig.text end
    function C.CBackendCodePtr:c_emit_can_copy_propagate() return true end
    function C.CBackendImportedCodePtr:c_emit_type() return "void (*)(void)" end
    function C.CBackendImportedCodePtr:c_emit_can_copy_propagate() return true end
    function C.CBackendNamed:c_emit_type() return (self.id.module_name .. "_" .. self.id.spelling):gsub("[^%w_]", "_") end
    function C.CBackendNamed:c_emit_named_deps(out) out[#out + 1] = self.id.module_name .. "\0" .. self.id.spelling end
    function C.CBackendNamed:c_emit_needs_compound_decl_only() return true end
    function C.CBackendArray:c_emit_type() return self.elem:c_emit_type() end
    function C.CBackendArray:c_emit_decl(name) return self.elem:c_emit_type() .. " " .. name .. "[" .. tostring(self.count) .. "]" end
    function C.CBackendArray:c_emit_named_deps(out) self.elem:c_emit_named_deps(out) end
    function C.CBackendArray:c_emit_visit_implicit(add_descriptor, add_closure) self.elem:c_emit_visit_implicit(add_descriptor, add_closure) end
    function C.CBackendArray:c_emit_is_array() return true end
    function C.CBackendArray:c_emit_needs_compound_decl_only() return true end
    function C.CBackendSliceDescriptor:c_emit_type() return C.CBackendDescriptorSlice(self.elem):c_emit_descriptor_type_name() end
    function C.CBackendSliceDescriptor:c_emit_visit_implicit(add_descriptor, add_closure) add_descriptor(C.CBackendDescriptorSlice(self.elem)); self.elem:c_emit_visit_implicit(add_descriptor, add_closure) end
    function C.CBackendSliceDescriptor:c_emit_needs_compound_decl_only() return true end
    function C.CBackendByteSpanDescriptor:c_emit_type() return "ml_bytespan" end
    function C.CBackendByteSpanDescriptor:c_emit_visit_implicit(add_descriptor, add_closure) add_descriptor(C.CBackendDescriptorByteSpan) end
    function C.CBackendByteSpanDescriptor:c_emit_needs_compound_decl_only() return true end
    function C.CBackendViewDescriptor:c_emit_type() return C.CBackendDescriptorView(self.elem):c_emit_descriptor_type_name() end
    function C.CBackendViewDescriptor:c_emit_visit_implicit(add_descriptor, add_closure) add_descriptor(C.CBackendDescriptorView(self.elem)); self.elem:c_emit_visit_implicit(add_descriptor, add_closure) end
    function C.CBackendViewDescriptor:c_emit_needs_compound_decl_only() return true end
    function C.CBackendClosureDescriptor:c_emit_type() return "ml_closure_" .. sanitize(self.sig.text) end
    function C.CBackendClosureDescriptor:c_emit_visit_implicit(add_descriptor, add_closure)
        add_closure(self:c_emit_type(), self)
        if self.ctx then self.ctx:c_emit_visit_implicit(add_descriptor, add_closure) end
    end
    function C.CBackendClosureDescriptor:c_emit_needs_compound_decl_only() return true end
    function C.CBackendAbiHiddenOutPtr:c_emit_type() return C.CBackendDataPtr(self.result):c_emit_type() end
    function C.CBackendAbiHiddenOutPtr:c_emit_named_deps(out) self.result:c_emit_named_deps(out) end
    function C.CBackendAbiHiddenOutPtr:c_emit_visit_implicit(add_descriptor, add_closure) self.result:c_emit_visit_implicit(add_descriptor, add_closure) end
    function C.CBackendVector:c_emit_type() return self.elem:c_emit_type() end
    function C.CBackendVector:c_emit_named_deps(out) self.elem:c_emit_named_deps(out) end
    function C.CBackendVector:c_emit_decl(name) return self.elem:c_emit_type() .. " " .. name .. "[" .. tostring(self.lanes) .. "]" end

    function C.CBackendDescriptorSlice:c_emit_descriptor_type_name()
        local elem = "any"
        if self.elem then
            elem = sanitize((self.elem.c_emit_type and self.elem:c_emit_type() or tostring(self.elem)):gsub("%*", "ptr"))
        end
        return "ml_slice_" .. elem
    end
    function C.CBackendDescriptorByteSpan:c_emit_descriptor_type_name() return "ml_bytespan" end
    function C.CBackendDescriptorView:c_emit_descriptor_type_name()
        local elem = "any"
        if self.elem then
            elem = sanitize((self.elem.c_emit_type and self.elem:c_emit_type() or tostring(self.elem)):gsub("%*", "ptr"))
        end
        return "ml_view_" .. elem
    end


    function C.CBackendAtom:c_emit_atom() error("missing c_emit_atom leaf method", 2) end
    function C.CBackendAtom:c_emit_local_text() return nil end
    function C.CBackendAtom:c_emit_note_arg_local(out) end
    function C.CBackendAtomLocal:c_emit_atom() return self.local_id.text end
    function C.CBackendAtomLocal:c_emit_local_text() return self.local_id.text end
    function C.CBackendAtomLocal:c_emit_note_arg_local(out) out[self.local_id.text] = true end
    function C.CBackendAtomGlobal:c_emit_atom() return self.global.text end
    function C.CBackendAtomLiteral:c_emit_atom() return "(" .. self.ty:c_emit_type() .. ")" .. self.literal:c_emit_literal() end
    function C.CBackendAtomNull:c_emit_atom() return "NULL" end
    function C.CBackendAtom:c_emit_cast_to(to) return "(" .. to:c_emit_type() .. ")(" .. self:c_emit_atom() .. ")" end
    function C.CBackendAtomLiteral:c_emit_cast_to(to) return "(" .. to:c_emit_type() .. ")" .. self.literal:c_emit_literal() end
    function C.CBackendAtomNull:c_emit_cast_to(to) return "(" .. to:c_emit_type() .. ")NULL" end
    function C.CBackendAtom:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendAtom:c_emit_alias_source_text() return nil end
    function C.CBackendAtom:c_emit_collect_used_locals(used) end
    function C.CBackendAtom:c_emit_inline_expr(ctx) return self:c_emit_atom() end
    function C.CBackendAtomLocal:c_emit_rewrite_aliases(aliases) return aliases[self.local_id.text] or self end
    function C.CBackendAtomLocal:c_emit_alias_source_text() return self.local_id.text end
    function C.CBackendAtomLocal:c_emit_collect_used_locals(used) if used.__count then used[self.local_id.text] = (used[self.local_id.text] or 0) + 1 else used[self.local_id.text] = true end end
    function C.CBackendAtomLocal:c_emit_inline_expr(ctx) return ctx:expr_for_local(self.local_id.text) or self.local_id.text end

    function C.CBackendPlace:c_emit_place() error("missing c_emit_place leaf method", 2) end
    function C.CBackendPlace:c_emit_place_typed(_local_types) return self:c_emit_place() end
    function C.CBackendPlaceLocal:c_emit_place() return self.local_id.text end
    function C.CBackendPlaceGlobal:c_emit_place() return self.global.text end
    function C.CBackendPlaceDeref:c_emit_place() return "(*(" .. self.ty:c_emit_type() .. "*)" .. self.addr:c_emit_atom() .. ")" end
    function C.CBackendPlaceDeref:c_emit_place_typed(local_types)
        local name = self.addr:c_emit_local_text()
        local aty = name and local_types and local_types[name]
        if aty ~= nil and aty:c_emit_points_to_place_type(self.ty) then return "*" .. self.addr:c_emit_atom() end
        return self:c_emit_place()
    end
    function C.CBackendPlace:c_emit_field_place(field) return self:c_emit_place() .. "." .. field.text end
    function C.CBackendPlaceDeref:c_emit_field_place(field) return "((" .. self.ty:c_emit_type() .. "*)" .. self.addr:c_emit_atom() .. ")->" .. field.text end
    function C.CBackendPlaceField:c_emit_place() return self.base:c_emit_field_place(self.field) end
    function C.CBackendPlaceIndex:c_emit_place() return self.base:c_emit_index_place(self.index) end
    function C.CBackendPlacePtrIndex:c_emit_place() return self.base:c_emit_atom() .. "[" .. self.index:c_emit_atom() .. "]" end
    function C.CBackendPlace:c_emit_index_place(index_atom) return self:c_emit_place() .. "[" .. index_atom:c_emit_atom() .. "]" end
    function C.CBackendPlaceDeref:c_emit_index_place(index_atom) return "((" .. self.ty:c_emit_type() .. "*)" .. self.addr:c_emit_atom() .. ")[" .. index_atom:c_emit_atom() .. "]" end
    function C.CBackendPlaceBytes:c_emit_place() return "(*(" .. self.ty:c_emit_type() .. "*)((unsigned char*)" .. self.base:c_emit_atom() .. " + " .. tostring(self.offset) .. "))" end

    function C.CBackendPlace:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendPlace:c_emit_collect_used_locals(used) end
    function C.CBackendPlace:c_emit_inline_place_expr(ctx) return self:c_emit_place(), false end
    function C.CBackendPlaceLocal:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendPlaceLocal:c_emit_collect_used_locals(used) if used.__count then used[self.local_id.text] = (used[self.local_id.text] or 0) + 1 else used[self.local_id.text] = true end end
    function C.CBackendPlaceLocal:c_emit_inline_place_expr(ctx) return self.local_id.text, true end
    function C.CBackendPlaceGlobal:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendPlaceGlobal:c_emit_inline_place_expr(ctx) return self.global.text, false end
    function C.CBackendPlaceDeref:c_emit_rewrite_aliases(aliases) return C.CBackendPlaceDeref(self.addr:c_emit_rewrite_aliases(aliases), self.ty, self.align) end
    function C.CBackendPlaceDeref:c_emit_collect_used_locals(used) self.addr:c_emit_collect_used_locals(used) end
    function C.CBackendPlaceField:c_emit_rewrite_aliases(aliases) return C.CBackendPlaceField(self.base:c_emit_rewrite_aliases(aliases), self.field, self.ty, self.offset, self.size, self.align) end
    function C.CBackendPlaceField:c_emit_collect_used_locals(used) self.base:c_emit_collect_used_locals(used) end
    function C.CBackendPlaceField:c_emit_inline_place_expr(ctx) local base, ok = self.base:c_emit_inline_place_expr(ctx); if not ok then return self:c_emit_place(), false end; return base .. "." .. self.field.text, true end
    function C.CBackendPlaceIndex:c_emit_rewrite_aliases(aliases) return C.CBackendPlaceIndex(self.base:c_emit_rewrite_aliases(aliases), self.index:c_emit_rewrite_aliases(aliases), self.ty, self.elem_size) end
    function C.CBackendPlaceIndex:c_emit_collect_used_locals(used) self.base:c_emit_collect_used_locals(used); self.index:c_emit_collect_used_locals(used) end
    function C.CBackendPlaceIndex:c_emit_inline_place_expr(ctx) local base, ok = self.base:c_emit_inline_place_expr(ctx); if not ok then return self:c_emit_place(), false end; return base .. "[" .. self.index:c_emit_inline_expr(ctx) .. "]", true end
    function C.CBackendPlacePtrIndex:c_emit_rewrite_aliases(aliases) return C.CBackendPlacePtrIndex(self.base:c_emit_rewrite_aliases(aliases), self.index:c_emit_rewrite_aliases(aliases), self.ty, self.elem_size) end
    function C.CBackendPlacePtrIndex:c_emit_collect_used_locals(used) self.base:c_emit_collect_used_locals(used); self.index:c_emit_collect_used_locals(used) end
    function C.CBackendPlacePtrIndex:c_emit_inline_place_expr(ctx) return self.base:c_emit_inline_expr(ctx) .. "[" .. self.index:c_emit_inline_expr(ctx) .. "]", true end
    function C.CBackendPlaceBytes:c_emit_rewrite_aliases(aliases) return C.CBackendPlaceBytes(self.base:c_emit_rewrite_aliases(aliases), self.offset, self.ty, self.size, self.align) end
    function C.CBackendPlaceBytes:c_emit_collect_used_locals(used) self.base:c_emit_collect_used_locals(used) end

    function C.CBackendPlace:c_emit_direct_field_base_local() return nil end
    function C.CBackendPlaceDeref:c_emit_direct_field_base_local() return self.addr:c_emit_local_text() end
    function C.CBackendPlace:c_emit_direct_field_load_candidate(canonicalize) return nil end
    function C.CBackendPlaceField:c_emit_direct_field_load_candidate(canonicalize)
        local base = self.base:c_emit_direct_field_base_local()
        if base == nil or not self.ty:c_emit_can_hoist_field_load() then return nil end
        local canonical_base = (canonicalize and canonicalize(base)) or base
        local hoist_base = C.CBackendPlaceDeref(C.CBackendAtomLocal(C.CBackendLocalId(canonical_base)), self.base.ty, self.base.align)
        local hoist_place = C.CBackendPlaceField(hoist_base, self.field, self.ty, self.offset, self.size, self.align)
        return { key = canonical_base .. "\0" .. self.field.text, base = canonical_base, raw_base = base, field = self.field.text, place = hoist_place, ty = self.ty }
    end
    function C.CBackendPlace:c_emit_note_direct_field_store(blocked_fields, blocked_bases, canonicalize) end
    function C.CBackendPlaceDeref:c_emit_note_direct_field_store(blocked_fields, blocked_bases, canonicalize)
        local base = self.addr:c_emit_local_text()
        if base ~= nil then blocked_bases[(canonicalize and canonicalize(base)) or base] = true end
    end
    function C.CBackendPlaceField:c_emit_note_direct_field_store(blocked_fields, blocked_bases, canonicalize)
        local candidate = self:c_emit_direct_field_load_candidate(canonicalize)
        if candidate ~= nil then blocked_fields[candidate.key] = true end
        self.base:c_emit_note_direct_field_store(blocked_fields, blocked_bases, canonicalize)
    end

    function C.CBackendRValue:c_emit_rvalue() error("missing c_emit_rvalue leaf method", 2) end
    function C.CBackendRAtom:c_emit_rvalue() return self.atom:c_emit_atom() end
    function C.CBackendRCompare:c_emit_rvalue() return "(" .. self.lhs:c_emit_atom() .. " " .. self.op:c_emit_cmp_op() .. " " .. self.rhs:c_emit_atom() .. ")" end
    function C.CBackendRCast:c_emit_rvalue() return self.value:c_emit_cast_to(self.to) end
    function C.CBackendRSelect:c_emit_rvalue() return "(" .. self.cond:c_emit_atom() .. " ? " .. self.then_value:c_emit_atom() .. " : " .. self.else_value:c_emit_atom() .. ")" end
    function C.CBackendRFuncAddr:c_emit_rvalue() return self.func.text end
    function C.CBackendRExternAddr:c_emit_rvalue() return self["extern"].text end
    function C.CBackendRPtrOffset:c_emit_rvalue() return "(void*)((char*)" .. self.base:c_emit_atom() .. " + (" .. self.index:c_emit_atom() .. ") * " .. tostring(self.elem_size) .. " + " .. tostring(self.const_offset) .. ")" end
    function C.CBackendRAddrOfPlace:c_emit_rvalue() return "&" .. self.place:c_emit_place() end
    function C.CBackendRValue:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendRValue:c_emit_copy_alias_atom() return nil end
    function C.CBackendRValue:c_emit_collect_used_locals(used) end
    function C.CBackendRValue:c_emit_inline_expr(ctx) return self:c_emit_rvalue() end
    function C.CBackendRAtom:c_emit_rewrite_aliases(aliases) return C.CBackendRAtom(self.atom:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendRAtom:c_emit_copy_alias_atom() return self.atom end
    function C.CBackendRAtom:c_emit_collect_used_locals(used) self.atom:c_emit_collect_used_locals(used) end
    function C.CBackendRAtom:c_emit_inline_expr(ctx) return self.atom:c_emit_inline_expr(ctx) end
    function C.CBackendRCompare:c_emit_rewrite_aliases(aliases) return C.CBackendRCompare(self.op, self.ty, self.lhs:c_emit_rewrite_aliases(aliases), self.rhs:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendRCompare:c_emit_collect_used_locals(used) self.lhs:c_emit_collect_used_locals(used); self.rhs:c_emit_collect_used_locals(used) end
    function C.CBackendRCompare:c_emit_inline_expr(ctx) return "(" .. self.lhs:c_emit_inline_expr(ctx) .. " " .. self.op:c_emit_cmp_op() .. " " .. self.rhs:c_emit_inline_expr(ctx) .. ")" end
    function C.CBackendRCast:c_emit_rewrite_aliases(aliases) return C.CBackendRCast(self.op, self.to, self.value:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendRCast:c_emit_collect_used_locals(used) self.value:c_emit_collect_used_locals(used) end
    function C.CBackendRCast:c_emit_inline_expr(ctx) return "(" .. self.to:c_emit_type() .. ")(" .. self.value:c_emit_inline_expr(ctx) .. ")" end
    function C.CBackendRSelect:c_emit_rewrite_aliases(aliases) return C.CBackendRSelect(self.ty, self.cond:c_emit_rewrite_aliases(aliases), self.then_value:c_emit_rewrite_aliases(aliases), self.else_value:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendRSelect:c_emit_collect_used_locals(used) self.cond:c_emit_collect_used_locals(used); self.then_value:c_emit_collect_used_locals(used); self.else_value:c_emit_collect_used_locals(used) end
    function C.CBackendRSelect:c_emit_inline_expr(ctx) return "(" .. self.cond:c_emit_inline_expr(ctx) .. " ? " .. self.then_value:c_emit_inline_expr(ctx) .. " : " .. self.else_value:c_emit_inline_expr(ctx) .. ")" end
    function C.CBackendRFuncAddr:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendRFuncAddr:c_emit_inline_expr(ctx) return self.func.text end
    function C.CBackendRExternAddr:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendRExternAddr:c_emit_inline_expr(ctx) return self["extern"].text end
    function C.CBackendRPtrOffset:c_emit_rewrite_aliases(aliases) return C.CBackendRPtrOffset(self.base:c_emit_rewrite_aliases(aliases), self.index:c_emit_rewrite_aliases(aliases), self.elem_size, self.const_offset) end
    function C.CBackendRPtrOffset:c_emit_collect_used_locals(used) self.base:c_emit_collect_used_locals(used); self.index:c_emit_collect_used_locals(used) end
    function C.CBackendRPtrOffset:c_emit_inline_expr(ctx) return "(void*)((char*)" .. self.base:c_emit_inline_expr(ctx) .. " + (" .. self.index:c_emit_inline_expr(ctx) .. ") * " .. tostring(self.elem_size) .. " + " .. tostring(self.const_offset) .. ")" end
    function C.CBackendRAddrOfPlace:c_emit_rewrite_aliases(aliases) return C.CBackendRAddrOfPlace(self.place:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendRAddrOfPlace:c_emit_collect_used_locals(used) self.place:c_emit_collect_used_locals(used) end
    function C.CBackendRAddrOfPlace:c_emit_inline_expr(ctx) local p = self.place:c_emit_inline_place_expr(ctx); return "&" .. p end

    function C.CBackendRValueBuiltin:c_emit_rvalue()
        if self.builtin == C.CBackendBuiltinAssumeAligned then
            return "__builtin_assume_aligned(" .. self.args[1]:c_emit_rvalue() .. ", " .. self.args[2]:c_emit_rvalue() .. ")"
        elseif self.builtin == C.CBackendBuiltinExpect then
            return "__builtin_expect(" .. self.args[1]:c_emit_rvalue() .. ", " .. self.args[2]:c_emit_rvalue() .. ")"
        elseif self.builtin == C.CBackendBuiltinAssume then
            return "__builtin_assume(" .. self.args[1]:c_emit_rvalue() .. ")"
        end
        return "/* unknown builtin */"
    end
    function C.CBackendRValueBuiltin:c_emit_rewrite_aliases(aliases)
        local args = {}
        for i = 1, #self.args do args[i] = self.args[i]:c_emit_rewrite_aliases(aliases) end
        return C.CBackendRValueBuiltin(self.builtin, args)
    end
    function C.CBackendRValueBuiltin:c_emit_collect_used_locals(used)
        for i = 1, #self.args do self.args[i]:c_emit_collect_used_locals(used) end
    end
    function C.CBackendRValueBuiltin:c_emit_inline_expr(ctx)
        return self:c_emit_rvalue()
    end

    function C.CBackendTypeDecl:c_emit_key() return self.id and (self.id.module_name .. "\0" .. self.id.spelling) or nil end
    function C.CBackendTypeDecl:c_emit_deps() return {} end
    function C.CBackendTypedef:c_emit_deps() local out = {}; self.ty:c_emit_named_deps(out); return out end
    function C.CBackendStructDecl:c_emit_deps() local out = {}; for i = 1, #(self.fields or {}) do self.fields[i].ty:c_emit_named_deps(out) end; return out end
    function C.CBackendUnionDecl:c_emit_deps() local out = {}; for i = 1, #(self.fields or {}) do self.fields[i].ty:c_emit_named_deps(out) end; return out end
    function C.CBackendField:c_emit_field_decl() local attr = (self.align and self.align > 1) and (" __attribute__((aligned(" .. tostring(self.align) .. ")))" ) or ""; return "    " .. self.ty:c_emit_decl(self.name.text) .. attr .. ";" end
    function C.CBackendTypeDecl:c_emit_type_decl(out) error("missing c_emit_type_decl leaf method", 2) end
    function C.CBackendTypedef:c_emit_type_decl(out) local name = sanitize(self.id.module_name .. "_" .. self.id.spelling); out[#out + 1] = "typedef " .. self.ty:c_emit_decl(name) .. ";" end
    function C.CBackendStructDecl:c_emit_type_decl(out)
        local name = sanitize(self.id.module_name .. "_" .. self.id.spelling)
        out[#out + 1] = "typedef struct " .. name .. " {"
        for i = 1, #self.fields do out[#out + 1] = self.fields[i]:c_emit_field_decl() end
        out[#out + 1] = "} " .. name .. ";"
        if self.size ~= nil then out[#out + 1] = "typedef char ml_assert_size_" .. name .. "[(sizeof(" .. name .. ") == " .. tostring(self.size) .. ") ? 1 : -1];" end
        if self.align ~= nil then out[#out + 1] = "typedef char ml_assert_align_" .. name .. "[(offsetof(struct { char c; " .. name .. " x; }, x) == " .. tostring(self.align) .. ") ? 1 : -1];" end
    end
    function C.CBackendUnionDecl:c_emit_type_decl(out)
        local name = sanitize(self.id.module_name .. "_" .. self.id.spelling)
        out[#out + 1] = "typedef union " .. name .. " {"
        for i = 1, #self.fields do out[#out + 1] = self.fields[i]:c_emit_field_decl() end
        out[#out + 1] = "} " .. name .. ";"
        if self.size ~= nil then out[#out + 1] = "typedef char ml_assert_size_" .. name .. "[(sizeof(" .. name .. ") == " .. tostring(self.size) .. ") ? 1 : -1];" end
        if self.align ~= nil then out[#out + 1] = "typedef char ml_assert_align_" .. name .. "[(offsetof(struct { char c; " .. name .. " x; }, x) == " .. tostring(self.align) .. ") ? 1 : -1];" end
    end
    function C.CBackendOpaqueDecl:c_emit_type_decl(out) local name = sanitize(self.id.module_name .. "_" .. self.id.spelling); out[#out + 1] = "typedef struct " .. name .. " " .. name .. ";" end

    function C.CBackendDataInit:c_emit_byte_entries(entries) end
    function C.CBackendDataBytes:c_emit_byte_entries(entries) for k = 1, #self.bytes do entries[#entries + 1] = "[" .. tostring(self.offset + k - 1) .. "] = " .. tostring(self.bytes:byte(k)) end end
    function C.CBackendDataZero:c_emit_comment() return "/* zero init at " .. tostring(self.offset) .. " size " .. tostring(self.size) .. " */" end
    function C.CBackendDataBytes:c_emit_comment() return "/* bytes init at " .. tostring(self.offset) .. " size " .. tostring(#self.bytes) .. " */" end
    function C.CBackendDataScalar:c_emit_comment() return "/* scalar init at " .. tostring(self.offset) .. ": " .. self.literal:c_emit_literal() .. " */" end
    function C.CBackendDataReloc:c_emit_comment() return "/* reloc init at " .. tostring(self.offset) .. " */" end
    function C.CBackendDataInit:c_emit_scalar_literal_for_global(g) return nil end
    function C.CBackendDataScalar:c_emit_scalar_literal_for_global(g) if (self.offset or 0) == 0 then return self.literal:c_emit_literal() end end

    local function byte_init_list(g)
        local entries = {}
        for i = 1, #(g.inits or {}) do g.inits[i]:c_emit_byte_entries(entries) end
        if #entries == 0 then return "{0}" end
        return "{ " .. table.concat(entries, ", ") .. " }"
    end

    function C.CBackendType:c_emit_global_is_byte_storage(g) return false end
    function C.CBackendDataPtr:c_emit_global_is_byte_storage(g) return true end
    function C.CBackendGlobal:c_emit_scalar_init_literal()
        if #(self.inits or {}) ~= 1 then return nil end
        return self.ty:c_emit_accepts_scalar_global_init() and self.inits[1]:c_emit_scalar_literal_for_global(self) or nil
    end
    function C.CBackendType:c_emit_accepts_scalar_global_init() return false end
    function C.CBackendBool8:c_emit_accepts_scalar_global_init() return true end
    function C.CBackendIndex:c_emit_accepts_scalar_global_init() return true end
    function C.CBackendScalar:c_emit_accepts_scalar_global_init() return true end
    function C.CBackendGlobal:c_emit_global(out)
        local byte_global = self.ty:c_emit_global_is_byte_storage(self)
        if not byte_global and #(self.inits or {}) > 0 and self.inits[1].c_emit_forces_byte_global then byte_global = self.inits[1]:c_emit_forces_byte_global() end
        local scalar_init = self:c_emit_scalar_init_literal()
        if byte_global then out[#out + 1] = "static unsigned char " .. self.name.text .. "[" .. tostring(self.size) .. "] = " .. byte_init_list(self) .. ";"
        elseif scalar_init ~= nil then out[#out + 1] = "static " .. self.ty:c_emit_decl(self.name.text) .. " = " .. scalar_init .. ";"
        else out[#out + 1] = "static " .. self.ty:c_emit_decl(self.name.text) .. ";" end
        for i = 1, #(self.inits or {}) do out[#out + 1] = self.inits[i]:c_emit_comment() end
    end
    function C.CBackendDataInit:c_emit_forces_byte_global() return false end
    function C.CBackendDataBytes:c_emit_forces_byte_global() return true end

    local function emit_storage_copy(out, dst, src) out[#out + 1] = "    memcpy(" .. dst .. ", " .. src .. ", sizeof(" .. dst .. "));" end

    function C.CBackendBlock:c_emit_transfer_needs_scratch(args)
        local dests = {}
        for i = 1, #(self.params or {}) do dests[self.params[i].local_id.text] = true end
        local needed = {}
        for i = 1, #(self.params or {}) do
            local src_local = args[i] and args[i]:c_emit_local_text() or nil
            local dst = self.params[i].local_id.text
            if src_local ~= nil and src_local ~= dst and dests[src_local] then needed[i] = true end
        end
        return needed
    end

    function C.CBackendBlock:c_emit_transfer_scratch_name(index) return "__xfer_" .. self.label.text .. "_" .. tostring(index) end
    function C.CBackendBlock:c_emit_note_transfer_scratch(args, scratch)
        local needed = self:c_emit_transfer_needs_scratch(args)
        for i = 1, #(self.params or {}) do
            if needed[i] then
                local name = self:c_emit_transfer_scratch_name(i)
                if scratch.by_name[name] == nil then
                    scratch.by_name[name] = self.params[i].ty
                    scratch.order[#scratch.order + 1] = name
                end
            end
        end
    end
    function C.CBackendBlock:c_emit_transfer(out, args, scratch_needed)
        scratch_needed = scratch_needed or self:c_emit_transfer_needs_scratch(args)
        for i = 1, #self.params do
            if scratch_needed[i] then
                local tmp = self:c_emit_transfer_scratch_name(i)
                if self.params[i].ty:c_emit_is_array() then emit_storage_copy(out, tmp, args[i]:c_emit_atom()) else out[#out + 1] = "    " .. tmp .. " = " .. args[i]:c_emit_atom() .. ";" end
            end
        end
        for i = 1, #self.params do
            if args[i] == nil then error("c_emit: missing transfer argument " .. tostring(i) .. " for block " .. self.label.text .. " with " .. tostring(#self.params) .. " params", 2) end
            local dst = self.params[i].local_id.text
            local src = scratch_needed[i] and self:c_emit_transfer_scratch_name(i) or args[i]:c_emit_atom()
            if src ~= dst then
                if self.params[i].ty:c_emit_is_array() then emit_storage_copy(out, dst, src) else out[#out + 1] = "    " .. dst .. " = " .. src .. ";" end
            end
        end
        out[#out + 1] = "    goto " .. self.label.text .. ";"
    end

    function C.CBackendStmt:c_emit_stmt(out, blocks, local_types) error("missing c_emit_stmt leaf method", 2) end
    function C.CBackendStmt:c_emit_collect_field_hoist_state(state) end
    function C.CBackendStmt:c_emit_apply_field_hoists(hoists_by_key) return self end
    function C.CBackendStmt:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendStmt:c_emit_assigned_local() return nil end
    function C.CBackendStmt:c_emit_copy_alias(local_types) return nil end
    function C.CBackendStmt:c_emit_collect_used_locals(used) end
    function C.CBackendStmt:c_emit_is_dead_copy_assign(used) return false end
    function C.CBackendStmt:c_emit_inline_expr(ctx) return nil end
    function C.CBackendAssign:c_emit_stmt(out, blocks, local_types)
        if local_types[self.dst.text]:c_emit_is_array() then
            emit_storage_copy(out, self.dst.text, self.rhs.atom:c_emit_atom())
        else out[#out + 1] = "    " .. self.dst.text .. " = " .. self.rhs:c_emit_rvalue() .. ";" end
    end
    function C.CBackendAssign:c_emit_collect_field_hoist_state(state) state:mark_assigned(self.dst.text) end
    function C.CBackendAssign:c_emit_rewrite_aliases(aliases) return C.CBackendAssign(self.dst, self.rhs:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendAssign:c_emit_assigned_local() return self.dst.text end
    function C.CBackendAssign:c_emit_copy_alias(local_types)
        local atom = self.rhs:c_emit_copy_alias_atom()
        local src = atom and atom:c_emit_alias_source_text() or nil
        if src == nil or src == self.dst.text then return nil end
        local dst_ty, src_ty = local_types[self.dst.text], local_types[src]
        if dst_ty == nil or src_ty == nil or not dst_ty:c_emit_can_copy_propagate() or not src_ty:c_emit_can_copy_propagate() then return nil end
        return atom
    end
    function C.CBackendAssign:c_emit_collect_used_locals(used) self.rhs:c_emit_collect_used_locals(used) end
    function C.CBackendAssign:c_emit_is_dead_copy_assign(used) return self.rhs:c_emit_copy_alias_atom() ~= nil and not used[self.dst.text] end
    function C.CBackendAssign:c_emit_inline_expr(ctx) return self.rhs:c_emit_inline_expr(ctx) end
    function C.CBackendHelperCall:c_emit_stmt(out)
        local args = {}; for i = 1, #self.args do args[i] = self.args[i]:c_emit_atom() end
        local call = self.helper.text .. "(" .. table.concat(args, ", ") .. ")"
        if self.dst then out[#out + 1] = "    " .. self.dst.text .. " = " .. call .. ";" else out[#out + 1] = "    " .. call .. ";" end
    end
    function C.CBackendHelperCall:c_emit_collect_field_hoist_state(state)
        if self.dst then state:mark_assigned(self.dst.text) end
        for i = 1, #self.args do self.args[i]:c_emit_note_arg_local(state.call_arg_locals) end
    end
    function C.CBackendHelperCall:c_emit_rewrite_aliases(aliases) local args = {}; for i = 1, #self.args do args[i] = self.args[i]:c_emit_rewrite_aliases(aliases) end; return C.CBackendHelperCall(self.dst, self.helper, args) end
    function C.CBackendHelperCall:c_emit_assigned_local() return self.dst and self.dst.text or nil end
    function C.CBackendHelperCall:c_emit_collect_used_locals(used) for i = 1, #self.args do self.args[i]:c_emit_collect_used_locals(used) end end
    function C.CBackendLoad:c_emit_stmt(out) out[#out + 1] = "    memcpy(&" .. self.dst.text .. ", " .. self.addr:c_emit_atom() .. ", sizeof(" .. self.dst.text .. "));" end
    function C.CBackendLoad:c_emit_rewrite_aliases(aliases) return C.CBackendLoad(self.dst, self.addr:c_emit_rewrite_aliases(aliases), self.access) end
    function C.CBackendLoad:c_emit_assigned_local() return self.dst.text end
    function C.CBackendLoad:c_emit_collect_used_locals(used) self.addr:c_emit_collect_used_locals(used) end
    function C.CBackendStore:c_emit_stmt(out) out[#out + 1] = "    memcpy(" .. self.addr:c_emit_atom() .. ", &" .. self.value:c_emit_atom() .. ", sizeof(" .. self.value:c_emit_atom() .. "));" end
    function C.CBackendStore:c_emit_collect_field_hoist_state(state) local base = self.addr:c_emit_local_text(); if base ~= nil then state:mark_base_clobber(base) end end
    function C.CBackendStore:c_emit_rewrite_aliases(aliases) return C.CBackendStore(self.addr:c_emit_rewrite_aliases(aliases), self.value:c_emit_rewrite_aliases(aliases), self.access) end
    function C.CBackendStore:c_emit_collect_used_locals(used) self.addr:c_emit_collect_used_locals(used); self.value:c_emit_collect_used_locals(used) end
    function C.CBackendPlaceLoad:c_emit_stmt(out, blocks, local_types) if local_types[self.dst.text]:c_emit_is_array() then emit_storage_copy(out, self.dst.text, self.place:c_emit_place_typed(local_types)) else out[#out + 1] = "    " .. self.dst.text .. " = " .. self.place:c_emit_place_typed(local_types) .. ";" end end
    function C.CBackendPlaceLoad:c_emit_collect_field_hoist_state(state)
        state:mark_assigned(self.dst.text)
        local candidate = self.place:c_emit_direct_field_load_candidate(function(name) return state:canonical_local(name) end)
        if candidate == nil then return end
        local entry = state.candidates[candidate.key]
        if entry == nil then
            entry = candidate
            entry.count = 0
            state.candidates[candidate.key] = entry
            state.order[#state.order + 1] = candidate.key
        end
        entry.count = entry.count + 1
    end
    function C.CBackendPlaceLoad:c_emit_apply_field_hoists(hoists_by_key, canonicalize)
        local candidate = self.place:c_emit_direct_field_load_candidate(canonicalize)
        local hoist = candidate and hoists_by_key[candidate.key] or nil
        if hoist == nil then return self end
        return C.CBackendAssign(self.dst, C.CBackendRAtom(C.CBackendAtomLocal(hoist.local_id)))
    end
    function C.CBackendPlaceLoad:c_emit_rewrite_aliases(aliases) return C.CBackendPlaceLoad(self.dst, self.place:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendPlaceLoad:c_emit_assigned_local() return self.dst.text end
    function C.CBackendPlaceLoad:c_emit_collect_used_locals(used) self.place:c_emit_collect_used_locals(used) end
    function C.CBackendPlaceLoad:c_emit_inline_expr(ctx) local expr, ok = self.place:c_emit_inline_place_expr(ctx); return ok and expr or nil end
    function C.CBackendPlaceStore:c_emit_stmt(out, _blocks, local_types) if self.place.ty:c_emit_is_array() then emit_storage_copy(out, self.place:c_emit_place_typed(local_types), self.value:c_emit_atom()) else out[#out + 1] = "    " .. self.place:c_emit_place_typed(local_types) .. " = " .. self.value:c_emit_atom() .. ";" end end
    function C.CBackendPlaceStore:c_emit_collect_field_hoist_state(state) self.place:c_emit_note_direct_field_store(state.blocked_fields, state.blocked_bases, function(name) return state:canonical_local(name) end) end
    function C.CBackendPlaceStore:c_emit_rewrite_aliases(aliases) return C.CBackendPlaceStore(self.place:c_emit_rewrite_aliases(aliases), self.value:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendPlaceStore:c_emit_collect_used_locals(used) self.place:c_emit_collect_used_locals(used); self.value:c_emit_collect_used_locals(used) end
    function C.CBackendZeroInit:c_emit_stmt(out) out[#out + 1] = "    memset(&" .. self.place:c_emit_place() .. ", 0, (size_t)" .. tostring(self.size) .. ");" end
    function C.CBackendZeroInit:c_emit_collect_field_hoist_state(state) self.place:c_emit_note_direct_field_store(state.blocked_fields, state.blocked_bases, function(name) return state:canonical_local(name) end) end
    function C.CBackendZeroInit:c_emit_rewrite_aliases(aliases) return C.CBackendZeroInit(self.place:c_emit_rewrite_aliases(aliases), self.ty, self.size) end
    function C.CBackendZeroInit:c_emit_collect_used_locals(used) self.place:c_emit_collect_used_locals(used) end
    function C.CBackendAggregateInit:c_emit_stmt(out) for i = 1, #self.fields do out[#out + 1] = "    " .. self.place:c_emit_place() .. "." .. self.fields[i].field.text .. " = " .. self.fields[i].value:c_emit_atom() .. ";" end end
    function C.CBackendAggregateInit:c_emit_collect_field_hoist_state(state) self.place:c_emit_note_direct_field_store(state.blocked_fields, state.blocked_bases, function(name) return state:canonical_local(name) end) end
    function C.CBackendAggregateInit:c_emit_rewrite_aliases(aliases) local fields = {}; for i = 1, #self.fields do fields[i] = C.CBackendAggregateFieldInit(self.fields[i].field, self.fields[i].value:c_emit_rewrite_aliases(aliases), self.fields[i].offset) end; return C.CBackendAggregateInit(self.place:c_emit_rewrite_aliases(aliases), self.ty, fields) end
    function C.CBackendAggregateInit:c_emit_collect_used_locals(used) self.place:c_emit_collect_used_locals(used); for i = 1, #self.fields do self.fields[i].value:c_emit_collect_used_locals(used) end end
    function C.CBackendArrayInit:c_emit_stmt(out) for i = 1, #self.elems do out[#out + 1] = "    " .. self.place:c_emit_place() .. "[" .. tostring(self.elems[i].index) .. "] = " .. self.elems[i].value:c_emit_atom() .. ";" end end
    function C.CBackendArrayInit:c_emit_collect_field_hoist_state(state) self.place:c_emit_note_direct_field_store(state.blocked_fields, state.blocked_bases, function(name) return state:canonical_local(name) end) end
    function C.CBackendArrayInit:c_emit_rewrite_aliases(aliases) local elems = {}; for i = 1, #self.elems do elems[i] = C.CBackendArrayElemInit(self.elems[i].index, self.elems[i].value:c_emit_rewrite_aliases(aliases)) end; return C.CBackendArrayInit(self.place:c_emit_rewrite_aliases(aliases), self.ty, elems) end
    function C.CBackendArrayInit:c_emit_collect_used_locals(used) self.place:c_emit_collect_used_locals(used); for i = 1, #self.elems do self.elems[i].value:c_emit_collect_used_locals(used) end end
    function C.CBackendCall:c_emit_stmt(out)
        local args = {}; for i = 1, #self.args do args[i] = self.args[i]:c_emit_atom() end
        local call = self.target:c_emit_callee(args) .. "(" .. table.concat(args, ", ") .. ")"
        if self.dst then out[#out + 1] = "    " .. self.dst.text .. " = " .. call .. ";" else out[#out + 1] = "    " .. call .. ";" end
    end
    function C.CBackendCall:c_emit_collect_field_hoist_state(state)
        if self.dst then state:mark_assigned(self.dst.text) end
        self.target:c_emit_note_call_arg_locals(state.call_arg_locals)
        for i = 1, #self.args do self.args[i]:c_emit_note_arg_local(state.call_arg_locals) end
    end
    function C.CBackendCall:c_emit_rewrite_aliases(aliases) local args = {}; for i = 1, #self.args do args[i] = self.args[i]:c_emit_rewrite_aliases(aliases) end; return C.CBackendCall(self.dst, self.target:c_emit_rewrite_aliases(aliases), args) end
    function C.CBackendCall:c_emit_assigned_local() return self.dst and self.dst.text or nil end
    function C.CBackendCall:c_emit_collect_used_locals(used) self.target:c_emit_collect_used_locals(used); for i = 1, #self.args do self.args[i]:c_emit_collect_used_locals(used) end end
    function C.CBackendComment:c_emit_stmt(out)
        if self.text:sub(1, 7) == "#pragma" then
            out[#out + 1] = self.text
        else
            out[#out + 1] = "    /* " .. self.text:gsub("%*/", "* /") .. " */"
        end
    end

    function C.CBackendCallTarget:c_emit_callee(args) error("missing c_emit_callee leaf method", 2) end
    function C.CBackendCallTarget:c_emit_note_call_arg_locals(out) end
    function C.CBackendCallTarget:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendCallTarget:c_emit_collect_used_locals(used) end
    function C.CBackendCallDirect:c_emit_callee(args) return self.func.text end
    function C.CBackendCallExtern:c_emit_callee(args) return self["extern"].text end
    function C.CBackendCallIndirect:c_emit_callee(args) return self.callee:c_emit_atom() end
    function C.CBackendCallIndirect:c_emit_note_call_arg_locals(out) self.callee:c_emit_note_arg_local(out) end
    function C.CBackendCallIndirect:c_emit_rewrite_aliases(aliases) return C.CBackendCallIndirect(self.callee:c_emit_rewrite_aliases(aliases), self.sig) end
    function C.CBackendCallIndirect:c_emit_collect_used_locals(used) self.callee:c_emit_collect_used_locals(used) end
    function C.CBackendCallClosure:c_emit_callee(args) local closure = self.closure:c_emit_atom(); table.insert(args, 1, closure .. ".ctx"); return closure .. ".fn" end
    function C.CBackendCallClosure:c_emit_note_call_arg_locals(out) self.closure:c_emit_note_arg_local(out) end
    function C.CBackendCallClosure:c_emit_rewrite_aliases(aliases) return C.CBackendCallClosure(self.closure:c_emit_rewrite_aliases(aliases), self.sig) end
    function C.CBackendCallClosure:c_emit_collect_used_locals(used) self.closure:c_emit_collect_used_locals(used) end

    function C.CBackendTerminator:c_emit_term(out, blocks) error("missing c_emit_term leaf method", 2) end
    function C.CBackendTerminator:c_emit_collect_transfer_scratch(blocks, scratch) end
    function C.CBackendTerminator:c_emit_collect_transfer_edges(edges) end
    function C.CBackendTerminator:c_emit_rewrite_aliases(aliases) return self end
    function C.CBackendTerminator:c_emit_collect_used_locals(used) end
    function C.CBackendGoto:c_emit_collect_transfer_scratch(blocks, scratch) blocks[self.dest.text]:c_emit_note_transfer_scratch(self.args, scratch) end
    function C.CBackendGoto:c_emit_collect_transfer_edges(edges) edges[#edges + 1] = { dest = self.dest.text, args = self.args } end
    function C.CBackendGoto:c_emit_term(out, blocks) blocks[self.dest.text]:c_emit_transfer(out, self.args) end
    function C.CBackendGoto:c_emit_rewrite_aliases(aliases) local args = {}; for i = 1, #self.args do args[i] = self.args[i]:c_emit_rewrite_aliases(aliases) end; return C.CBackendGoto(self.dest, args) end
    function C.CBackendGoto:c_emit_collect_used_locals(used) for i = 1, #self.args do self.args[i]:c_emit_collect_used_locals(used) end end
    function C.CBackendIfGoto:c_emit_collect_transfer_scratch(blocks, scratch)
        blocks[self.then_dest.text]:c_emit_note_transfer_scratch(self.then_args, scratch)
        blocks[self.else_dest.text]:c_emit_note_transfer_scratch(self.else_args, scratch)
    end
    function C.CBackendIfGoto:c_emit_collect_transfer_edges(edges)
        edges[#edges + 1] = { dest = self.then_dest.text, args = self.then_args }
        edges[#edges + 1] = { dest = self.else_dest.text, args = self.else_args }
    end
    function C.CBackendIfGoto:c_emit_term(out, blocks)
        out[#out + 1] = "    if (" .. self.cond:c_emit_atom() .. ") {"
        local nested = {}; blocks[self.then_dest.text]:c_emit_transfer(nested, self.then_args); for i = 1, #nested do out[#out + 1] = "    " .. nested[i] end
        out[#out + 1] = "    } else {"
        nested = {}; blocks[self.else_dest.text]:c_emit_transfer(nested, self.else_args); for i = 1, #nested do out[#out + 1] = "    " .. nested[i] end
        out[#out + 1] = "    }"
    end
    function C.CBackendIfGoto:c_emit_rewrite_aliases(aliases)
        local then_args, else_args = {}, {}
        for i = 1, #self.then_args do then_args[i] = self.then_args[i]:c_emit_rewrite_aliases(aliases) end
        for i = 1, #self.else_args do else_args[i] = self.else_args[i]:c_emit_rewrite_aliases(aliases) end
        return C.CBackendIfGoto(self.cond:c_emit_rewrite_aliases(aliases), self.then_dest, then_args, self.else_dest, else_args)
    end
    function C.CBackendIfGoto:c_emit_collect_used_locals(used) self.cond:c_emit_collect_used_locals(used); for i = 1, #self.then_args do self.then_args[i]:c_emit_collect_used_locals(used) end; for i = 1, #self.else_args do self.else_args[i]:c_emit_collect_used_locals(used) end end
    function C.CBackendSwitchCase:c_emit_collect_transfer_scratch(blocks, scratch) blocks[self.dest.text]:c_emit_note_transfer_scratch(self.args, scratch) end
    function C.CBackendSwitchCase:c_emit_collect_transfer_edges(edges) edges[#edges + 1] = { dest = self.dest.text, args = self.args } end
    function C.CBackendSwitchCase:c_emit_case(out, blocks)
        out[#out + 1] = "    case " .. self.literal:c_emit_literal() .. ":"
        blocks[self.dest.text]:c_emit_transfer(out, self.args)
    end
    function C.CBackendSwitchCase:c_emit_rewrite_aliases(aliases) local args = {}; for i = 1, #self.args do args[i] = self.args[i]:c_emit_rewrite_aliases(aliases) end; return C.CBackendSwitchCase(self.literal, self.dest, args) end
    function C.CBackendSwitchCase:c_emit_collect_used_locals(used) for i = 1, #self.args do self.args[i]:c_emit_collect_used_locals(used) end end
    function C.CBackendSwitchGoto:c_emit_collect_transfer_scratch(blocks, scratch)
        for i = 1, #self.cases do self.cases[i]:c_emit_collect_transfer_scratch(blocks, scratch) end
        blocks[self.default_dest.text]:c_emit_note_transfer_scratch(self.default_args, scratch)
    end
    function C.CBackendSwitchGoto:c_emit_collect_transfer_edges(edges)
        for i = 1, #self.cases do self.cases[i]:c_emit_collect_transfer_edges(edges) end
        edges[#edges + 1] = { dest = self.default_dest.text, args = self.default_args }
    end
    function C.CBackendSwitchGoto:c_emit_term(out, blocks)
        out[#out + 1] = "    switch (" .. self.value:c_emit_atom() .. ") {"
        for i = 1, #self.cases do self.cases[i]:c_emit_case(out, blocks) end
        out[#out + 1] = "    default:"
        blocks[self.default_dest.text]:c_emit_transfer(out, self.default_args)
        out[#out + 1] = "    }"
    end
    function C.CBackendSwitchGoto:c_emit_rewrite_aliases(aliases)
        local cases, default_args = {}, {}
        for i = 1, #self.cases do cases[i] = self.cases[i]:c_emit_rewrite_aliases(aliases) end
        for i = 1, #self.default_args do default_args[i] = self.default_args[i]:c_emit_rewrite_aliases(aliases) end
        return C.CBackendSwitchGoto(self.value:c_emit_rewrite_aliases(aliases), cases, self.default_dest, default_args)
    end
    function C.CBackendSwitchGoto:c_emit_collect_used_locals(used) self.value:c_emit_collect_used_locals(used); for i = 1, #self.cases do self.cases[i]:c_emit_collect_used_locals(used) end; for i = 1, #self.default_args do self.default_args[i]:c_emit_collect_used_locals(used) end end
    function C.CBackendReturnVoid:c_emit_term(out) out[#out + 1] = "    return;" end
    function C.CBackendReturn:c_emit_term(out) out[#out + 1] = "    return " .. self.value:c_emit_atom() .. ";" end
    function C.CBackendReturn:c_emit_rewrite_aliases(aliases) return C.CBackendReturn(self.value:c_emit_rewrite_aliases(aliases)) end
    function C.CBackendReturn:c_emit_collect_used_locals(used) self.value:c_emit_collect_used_locals(used) end
    function C.CBackendTrap:c_emit_term(out) out[#out + 1] = "    abort();" end
    function C.CBackendTerminator:c_emit_term_optimized(out, blocks, ctx) self:c_emit_term(out, blocks) end
    function C.CBackendIfGoto:c_emit_term_optimized(out, blocks, ctx)
        out[#out + 1] = "    if (" .. self.cond:c_emit_inline_expr(ctx) .. ") {"
        local nested = {}; blocks[self.then_dest.text]:c_emit_transfer(nested, self.then_args); for i = 1, #nested do out[#out + 1] = "    " .. nested[i] end
        out[#out + 1] = "    } else {"
        nested = {}; blocks[self.else_dest.text]:c_emit_transfer(nested, self.else_args); for i = 1, #nested do out[#out + 1] = "    " .. nested[i] end
        out[#out + 1] = "    }"
    end
    function C.CBackendSwitchGoto:c_emit_term_optimized(out, blocks, ctx)
        out[#out + 1] = "    switch (" .. self.value:c_emit_inline_expr(ctx) .. ") {"
        for i = 1, #self.cases do self.cases[i]:c_emit_case(out, blocks) end
        out[#out + 1] = "    default:"
        blocks[self.default_dest.text]:c_emit_transfer(out, self.default_args)
        out[#out + 1] = "    }"
    end
    function C.CBackendReturn:c_emit_term_optimized(out, blocks, ctx) out[#out + 1] = "    return " .. self.value:c_emit_inline_expr(ctx) .. ";" end

    function C.CBackendFuncBody:c_emit_blocks() error("missing c_emit_blocks leaf method", 2) end
    function C.CBackendBodyBlocks:c_emit_blocks() return self.blocks end
    function C.CBackendBodyMixed:c_emit_blocks() return self.blocks end
    function C.CBackendBodyExec:c_emit_blocks() return {} end



    local function code_symbol_from_id(id) local text = tostring(id and id.text or "exec"):gsub("^fn:", ""):gsub("^func:", ""):gsub("^function:", ""):gsub("[^%w_]", "_"); if text:match("^%d") then text = "_" .. text end; if text == "" then text = "exec" end; return text end
    function Exec.ExecFragmentBody:c_emit_exec_symbol() error("missing c_emit_exec_symbol leaf method", 2) end
    function Exec.ExecFragmentStencil:c_emit_exec_symbol() return self.artifact.symbol.text end
    function Exec.ExecFragmentCall:c_emit_exec_symbol() return code_symbol_from_id(self.callee) end
    function C.CBackendExecSite:c_emit_exec_site(out)
        local args = {}; for i = 1, #(self.args or {}) do args[i] = self.args[i].atom:c_emit_atom() end
        local call = self.fragment.body:c_emit_exec_symbol() .. "(" .. table.concat(args, ", ") .. ")"
        return self.result:c_emit_exec_result(out, call)
    end
    function C.CBackendExecResult:c_emit_exec_result(out, call) error("missing c_emit_exec_result leaf method", 2) end
    function C.CBackendExecResultVoid:c_emit_exec_result(out, call) out[#out + 1] = "    " .. call .. ";"; return nil end
    function C.CBackendExecResultLocal:c_emit_exec_result(out, call) out[#out + 1] = "    " .. self.dst.text .. " = " .. call .. ";"; return self.dst end

    local function collect_implicit_types(unit)
        local closure_types, closure_order, descriptor_types, descriptor_order = {}, {}, {}, {}
        local function add_descriptor(desc)
            local name = desc:c_emit_descriptor_type_name()
            if descriptor_types[name] == nil then descriptor_types[name] = desc; descriptor_order[#descriptor_order + 1] = name end
        end
        local function add_closure(name, ty) if closure_types[name] == nil then closure_types[name] = ty; closure_order[#closure_order + 1] = name end end
        local function visit_ty(ty) ty:c_emit_visit_implicit(add_descriptor, add_closure) end
        for i = 1, #(unit.sigs or {}) do for j = 1, #unit.sigs[i].params do visit_ty(unit.sigs[i].params[j]) end; visit_ty(unit.sigs[i].result) end
        for i = 1, #(unit.funcs or {}) do
            for j = 1, #unit.funcs[i].params do visit_ty(unit.funcs[i].params[j].ty) end
            for j = 1, #unit.funcs[i].locals do visit_ty(unit.funcs[i].locals[j].ty) end
            local blocks = unit.funcs[i].body:c_emit_blocks()
            for j = 1, #blocks do for k = 1, #blocks[j].params do visit_ty(blocks[j].params[k].ty) end end
            unit.funcs[i].body:c_emit_visit_exec_site_types(visit_ty)
        end
        for i = 1, #(unit.globals or {}) do visit_ty(unit.globals[i].ty) end
        return closure_types, closure_order, descriptor_types, descriptor_order
    end
    function C.CBackendFuncBody:c_emit_visit_exec_site_types(visit_ty) end
    function C.CBackendBodyExec:c_emit_visit_exec_site_types(visit_ty) self.fragment:c_emit_visit_exec_site_types(visit_ty) end
    function C.CBackendBodyMixed:c_emit_visit_exec_site_types(visit_ty) for i = 1, #(self.fragments or {}) do self.fragments[i]:c_emit_visit_exec_site_types(visit_ty) end end
    function C.CBackendExecSite:c_emit_visit_exec_site_types(visit_ty) for i = 1, #(self.args or {}) do visit_ty(self.args[i].ty) end; self.result:c_emit_visit_result_type(visit_ty) end
    function C.CBackendExecResult:c_emit_visit_result_type(visit_ty) end
    function C.CBackendExecResultLocal:c_emit_visit_result_type(visit_ty) visit_ty(self.ty) end

    local function ordered_type_decls(types)
        local by_key, out, perm, temp = {}, {}, {}, {}
        for i = 1, #(types or {}) do local key = types[i]:c_emit_key(); if key and by_key[key] == nil then by_key[key] = types[i] end end
        local function visit(td)
            local key = td:c_emit_key(); if key == nil then out[#out + 1] = td; return end
            if perm[key] or temp[key] then return end
            temp[key] = true
            local deps = td:c_emit_deps(); for i = 1, #deps do if deps[i] ~= key and by_key[deps[i]] then visit(by_key[deps[i]]) end end
            temp[key] = nil; perm[key] = true; out[#out + 1] = td
        end
        for i = 1, #(types or {}) do visit(types[i]) end
        return out
    end

    local function emit_descriptor_type_decls(descriptor_types, descriptor_order, out)
        for i = 1, #descriptor_order do
            local name, d = descriptor_order[i], descriptor_types[descriptor_order[i]]
            local dcls = asdl.classof(d)
            if dcls == C.CBackendDescriptorSlice then out[#out + 1] = "struct " .. name .. " { " .. C.CBackendDataPtr(d.elem):c_emit_type() .. " data; ml_index len; };"
            elseif dcls == C.CBackendDescriptorByteSpan then out[#out + 1] = "struct " .. name .. " { uint8_t* data; ml_index len; };"
            elseif dcls == C.CBackendDescriptorView then out[#out + 1] = "struct " .. name .. " { " .. C.CBackendDataPtr(d.elem):c_emit_type() .. " data; ml_index len; ml_index stride; };"
            end
        end
    end
    local function emit_closure_type_decls(closure_types, closure_order, out) for i = 1, #closure_order do local name = closure_order[i]; out[#out + 1] = "struct " .. name .. " { " .. closure_types[name].sig.text .. " fn; void* ctx; };" end end
    local function emit_type_decls(unit, out) local types = ordered_type_decls(unit.types); for i = 1, #types do types[i]:c_emit_type_decl(out) end end
    local function emit_globals(unit, out) for i = 1, #unit.globals do unit.globals[i]:c_emit_global(out) end end
    local function sig_by_id(unit) local out = {}; for i = 1, #unit.sigs do out[unit.sigs[i].id.text] = unit.sigs[i] end; return out end
    local function sig_params(params) local out = {}; if #params == 0 then return "void" end; for i = 1, #params do out[i] = params[i]:c_emit_type() end; return table.concat(out, ", ") end
    local function func_params(params) local out = {}; if #params == 0 then return "void" end; for i = 1, #params do out[i] = params[i].ty:c_emit_decl(params[i].id.text) end; return table.concat(out, ", ") end
    local function emit_local_decl(out, local_id, ty) out[#out + 1] = "    " .. ty:c_emit_decl(local_id) .. ";" end

    local function fresh_local_id(existing, prefix)
        local n = 1
        local candidate = prefix
        while existing[candidate] do
            n = n + 1
            candidate = prefix .. "_" .. tostring(n)
        end
        existing[candidate] = true
        return C.CBackendLocalId(candidate)
    end

    local function invalidate_aliases_for_assignment(aliases, assigned)
        if assigned == nil then return end
        aliases[assigned] = nil
        for name, atom in pairs(aliases) do
            if atom:c_emit_alias_source_text() == assigned then aliases[name] = nil end
        end
    end

    local function copy_propagate_block(block, local_types)
        local aliases, stmts = {}, {}
        for i = 1, #(block.stmts or {}) do
            local stmt = block.stmts[i]:c_emit_rewrite_aliases(aliases)
            local assigned = stmt:c_emit_assigned_local()
            invalidate_aliases_for_assignment(aliases, assigned)
            local alias = stmt:c_emit_copy_alias(local_types)
            if alias ~= nil then aliases[assigned] = alias end
            stmts[#stmts + 1] = stmt
        end
        return C.CBackendBlock(block.label, block.params, stmts, block.term:c_emit_rewrite_aliases(aliases))
    end

    local function copy_propagate_blocks(f_blocks, local_types)
        local out = {}
        for i = 1, #(f_blocks or {}) do out[i] = copy_propagate_block(f_blocks[i], local_types) end
        return out
    end

    local function collect_used_locals(f_blocks)
        local used = {}
        for i = 1, #(f_blocks or {}) do
            for j = 1, #(f_blocks[i].stmts or {}) do f_blocks[i].stmts[j]:c_emit_collect_used_locals(used) end
            f_blocks[i].term:c_emit_collect_used_locals(used)
        end
        return used
    end

    local function remove_dead_copy_assigns(f_blocks)
        local used = collect_used_locals(f_blocks)
        local out = {}
        for i = 1, #(f_blocks or {}) do
            local b, stmts = f_blocks[i], {}
            for j = 1, #(b.stmts or {}) do
                if not b.stmts[j]:c_emit_is_dead_copy_assign(used) then stmts[#stmts + 1] = b.stmts[j] end
            end
            out[i] = C.CBackendBlock(b.label, b.params, stmts, b.term)
        end
        return out
    end

    local function block_use_counts(block)
        local used = { __count = true }
        for i = 1, #(block.stmts or {}) do block.stmts[i]:c_emit_collect_used_locals(used) end
        block.term:c_emit_collect_used_locals(used)
        return used
    end

    local function block_defs(block)
        local defs = {}
        for i = 1, #(block.stmts or {}) do
            local dst = block.stmts[i]:c_emit_assigned_local()
            if dst ~= nil and block.stmts[i]:c_emit_inline_expr({ expr_for_local = function() return nil end }) ~= nil then
                if defs[dst] == nil then defs[dst] = i else defs[dst] = false end
            end
        end
        return defs
    end

    local function emit_block_stmts_and_term(out, block, blocks, local_types)
        local used = block_use_counts(block)
        local defs = block_defs(block)
        local removed, resolving = {}, {}
        local ctx = {}
        function ctx:expr_for_local(name)
            if (used[name] or 0) ~= 1 or resolving[name] then return nil end
            local idx = defs[name]
            if type(idx) ~= "number" then return nil end
            resolving[name] = true
            local expr = block.stmts[idx]:c_emit_inline_expr(ctx)
            resolving[name] = nil
            if expr ~= nil then removed[idx] = true end
            return expr
        end
        local term_out = {}
        block.term:c_emit_term_optimized(term_out, blocks, ctx)
        for j = 1, #(block.stmts or {}) do if not removed[j] then block.stmts[j]:c_emit_stmt(out, blocks, local_types) end end
        for j = 1, #term_out do out[#out + 1] = term_out[j] end
    end

    local function transfer_edges_by_dest(f_blocks)
        local edges, by_dest = {}, {}
        for i = 1, #(f_blocks or {}) do f_blocks[i].term:c_emit_collect_transfer_edges(edges) end
        for i = 1, #edges do
            local dest = edges[i].dest
            by_dest[dest] = by_dest[dest] or {}
            by_dest[dest][#by_dest[dest] + 1] = edges[i]
        end
        return by_dest
    end

    local function compute_transfer_equivalence(func, f_blocks)
        local alias, block_by_label = {}, {}
        for i = 1, #(func.params or {}) do alias[func.params[i].id.text] = func.params[i].id.text end
        for i = 1, #(func.locals or {}) do alias[func.locals[i].id.text] = func.locals[i].id.text end
        for i = 1, #(f_blocks or {}) do
            block_by_label[f_blocks[i].label.text] = f_blocks[i]
            for j = 1, #(f_blocks[i].params or {}) do alias[f_blocks[i].params[j].local_id.text] = f_blocks[i].params[j].local_id.text end
        end
        local function root(name)
            local cur, seen = name, {}
            while alias[cur] ~= nil and alias[cur] ~= cur and not seen[cur] do seen[cur] = true; cur = alias[cur] end
            return cur
        end
        local by_dest = transfer_edges_by_dest(f_blocks)
        local changed = true
        local limit = (#(f_blocks or {}) + 1) * 8
        while changed and limit > 0 do
            changed = false
            limit = limit - 1
            for i = 1, #(f_blocks or {}) do
                local block = f_blocks[i]
                local preds = by_dest[block.label.text] or {}
                for j = 1, #(block.params or {}) do
                    local param = block.params[j].local_id.text
                    local chosen, invalid = nil, false
                    for k = 1, #preds do
                        local arg = preds[k].args[j]
                        local src = arg and arg:c_emit_local_text() or nil
                        if src == nil then invalid = true; break end
                        if src ~= param then
                            local src_root = root(src)
                            if chosen == nil then chosen = src_root elseif chosen ~= src_root then invalid = true; break end
                        end
                    end
                    if not invalid and chosen ~= nil and root(param) ~= chosen then alias[param] = chosen; changed = true end
                end
            end
        end
        return root
    end

    local function plan_field_hoists(func, f_blocks)
        local canonical = compute_transfer_equivalence(func, f_blocks)
        local state = { param_locals = {}, existing = {}, candidates = {}, order = {}, call_arg_locals = {}, blocked_fields = {}, blocked_bases = {} }
        function state:canonical_local(name) return canonical(name) end
        function state:mark_assigned(name) self.blocked_bases[self:canonical_local(name)] = true end
        function state:mark_base_clobber(name) self.blocked_bases[self:canonical_local(name)] = true end
        for i = 1, #(func.params or {}) do state.param_locals[func.params[i].id.text] = true; state.existing[func.params[i].id.text] = true end
        for i = 1, #(func.locals or {}) do state.existing[func.locals[i].id.text] = true end
        for i = 1, #(f_blocks or {}) do
            for j = 1, #(f_blocks[i].params or {}) do state.existing[f_blocks[i].params[j].local_id.text] = true end
            for j = 1, #(f_blocks[i].stmts or {}) do f_blocks[i].stmts[j]:c_emit_collect_field_hoist_state(state) end
        end
        local call_arg_roots = {}
        for name in pairs(state.call_arg_locals) do call_arg_roots[state:canonical_local(name)] = true end
        local hoists, by_key = {}, {}
        for i = 1, #state.order do
            local key = state.order[i]
            local candidate = state.candidates[key]
            if candidate.count >= 3 and state.param_locals[candidate.base] and not call_arg_roots[candidate.base] and not state.blocked_bases[candidate.base] and not state.blocked_fields[key] then
                local id = fresh_local_id(state.existing, "__hoist_field_" .. tostring(#hoists + 1))
                local local_ = C.CBackendLocal(id, C.CBackendName(id.text), candidate.ty)
                local hoist = { key = key, local_id = id, local_ = local_, init = C.CBackendPlaceLoad(id, candidate.place) }
                hoists[#hoists + 1] = hoist
                by_key[key] = hoist
            end
        end
        if #hoists == 0 then return f_blocks, {} end
        local rewritten = {}
        for i = 1, #f_blocks do
            local b = f_blocks[i]
            local stmts = {}
            if i == 1 then for j = 1, #hoists do stmts[#stmts + 1] = hoists[j].init end end
            for j = 1, #(b.stmts or {}) do stmts[#stmts + 1] = b.stmts[j]:c_emit_apply_field_hoists(by_key, function(name) return canonical(name) end) end
            rewritten[i] = C.CBackendBlock(b.label, b.params, stmts, b.term)
        end
        local locals = {}
        for i = 1, #hoists do locals[i] = hoists[i].local_ end
        return rewritten, locals
    end

    local function c_merge_tails(func_annotations, f_blocks, blocks_by_label)
        if not func_annotations or not func_annotations.loops then return f_blocks end
        return f_blocks
    end

    local function c_inject_hints(func_annotations, f_blocks, local_types)
        if not func_annotations then return f_blocks end
        local blocks_map = {}
        for i = 1, #f_blocks do blocks_map[f_blocks[i].label.text] = f_blocks[i] end

        -- 1. Loop pragmas
        if func_annotations.loops then
            for _, loop_ann in ipairs(func_annotations.loops) do
                local header = blocks_map[loop_ann.header_label.text]
                if header then
                    if loop_ann.vectorizable then
                        table.insert(header.stmts, 1, C.CBackendComment("#pragma GCC ivdep"))
                        table.insert(header.stmts, 1, C.CBackendComment("#pragma clang loop vectorize(enable)"))
                    end
                    if loop_ann.unroll_hint then
                        table.insert(header.stmts, 1, C.CBackendComment("#pragma GCC unroll " .. tostring(loop_ann.unroll_hint)))
                        table.insert(header.stmts, 1, C.CBackendComment("#pragma clang loop unroll(count=" .. tostring(loop_ann.unroll_hint) .. ")"))
                    end
                    if loop_ann.interleave_hint and loop_ann.interleave_hint > 1 then
                        table.insert(header.stmts, 1, C.CBackendComment("#pragma clang loop interleave(count=" .. tostring(loop_ann.interleave_hint) .. ")"))
                    end
                end
            end
        end

        -- 2. Pointer alignment
        if func_annotations.pointers then
            for _, ptr_ann in ipairs(func_annotations.pointers) do
                if ptr_ann.alignment and asdl.classof(ptr_ann.alignment) == C.CBackendAlignmentKnown then
                    table.insert(ptr_ann, 1, C.CBackendComment("/* ptr_align: " .. ptr_ann.local_ptr.text .. " = " .. ptr_ann.alignment.bytes .. " */"))
                end
            end
        end

        return f_blocks
    end

    function C.CBackendFunc:c_emit_func(sigs, out, func_annotations)
        local sig = sigs[self.sig.text]
        out[#out + 1] = sig.result:c_emit_type() .. " " .. self.name.text .. "(" .. func_params(self.params) .. ") {"
        local local_types = {}; for i = 1, #self.params do local_types[self.params[i].id.text] = self.params[i].ty end
        for i = 1, #self.locals do local_types[self.locals[i].id.text] = self.locals[i].ty; emit_local_decl(out, self.locals[i].id.text, self.locals[i].ty) end
        local body_cls = asdl.classof(self.body)
        if body_cls == C.CBackendBodyExec then
            local result = self.body.fragment:c_emit_exec_site(out)
            if sig.result:c_emit_is_void() then out[#out + 1] = "    return;" elseif result then out[#out + 1] = "    return " .. result.text .. ";" else error("c_emit: non-void exec function has no exec result", 2) end
            out[#out + 1] = "}"; return
        elseif body_cls == C.CBackendBodyMixed then for i = 1, #self.body.fragments do self.body.fragments[i]:c_emit_exec_site(out) end end
        local f_blocks = self.body:c_emit_blocks()
        local hoist_locals
        f_blocks, hoist_locals = plan_field_hoists(self, f_blocks)
        -- Inject compiler hints from annotations after optimizer passes
        f_blocks = c_inject_hints(func_annotations, f_blocks, local_types)
        for i = 1, #(hoist_locals or {}) do local_types[hoist_locals[i].id.text] = hoist_locals[i].ty end
        for i = 1, #f_blocks do for j = 1, #f_blocks[i].params do local_types[f_blocks[i].params[j].local_id.text] = f_blocks[i].params[j].ty end end
        if #(hoist_locals or {}) > 0 then f_blocks = remove_dead_copy_assigns(copy_propagate_blocks(f_blocks, local_types)) end
        local blocks = {}; for i = 1, #f_blocks do blocks[f_blocks[i].label.text] = f_blocks[i] end
        local scratch = { by_name = {}, order = {} }
        for i = 1, #f_blocks do f_blocks[i].term:c_emit_collect_transfer_scratch(blocks, scratch) end
        for i = 1, #(hoist_locals or {}) do emit_local_decl(out, hoist_locals[i].id.text, hoist_locals[i].ty) end
        for i = 1, #f_blocks do for j = 1, #f_blocks[i].params do emit_local_decl(out, f_blocks[i].params[j].local_id.text, f_blocks[i].params[j].ty) end end
        for i = 1, #scratch.order do local name = scratch.order[i]; local_types[name] = scratch.by_name[name]; emit_local_decl(out, name, scratch.by_name[name]) end
        for i = 1, #f_blocks do local b = f_blocks[i]; out[#out + 1] = b.label.text .. ":"; emit_block_stmts_and_term(out, b, blocks, local_types) end
        out[#out + 1] = "}"
    end

    function C.CBackendHelperUse:c_emit_helper_is_atomic() return self.spec:c_emit_helper_is_atomic() end
    function C.CBackendHelperSpec:c_emit_helper_is_atomic() return false end
    function C.CBackendHelperAtomicLoad:c_emit_helper_is_atomic() return true end
    function C.CBackendHelperAtomicStore:c_emit_helper_is_atomic() return true end
    function C.CBackendHelperAtomicRmw:c_emit_helper_is_atomic() return true end
    function C.CBackendHelperAtomicCas:c_emit_helper_is_atomic() return true end
    function C.CBackendHelperAtomicFence:c_emit_helper_is_atomic() return true end
    function C.CBackendDialect:c_emit_supports_c11_atomics() return false end
    function C.CBackendC11:c_emit_supports_c11_atomics() return true end
    function C.CBackendGnuC:c_emit_supports_c11_atomics() return true end
    function C.CBackendClangC:c_emit_supports_c11_atomics() return true end



    function Core.Scalar:c_helper_suffix() error("missing c_helper_suffix leaf method for Scalar", 2) end
    function Core.ScalarVoid:c_helper_suffix() return "void" end
    function Core.ScalarBool:c_helper_suffix() return "bool8" end
    function Core.ScalarI8:c_helper_suffix() return "i8" end
    function Core.ScalarI16:c_helper_suffix() return "i16" end
    function Core.ScalarI32:c_helper_suffix() return "i32" end
    function Core.ScalarI64:c_helper_suffix() return "i64" end
    function Core.ScalarU8:c_helper_suffix() return "u8" end
    function Core.ScalarU16:c_helper_suffix() return "u16" end
    function Core.ScalarU32:c_helper_suffix() return "u32" end
    function Core.ScalarU64:c_helper_suffix() return "u64" end
    function Core.ScalarF32:c_helper_suffix() return "f32" end
    function Core.ScalarF64:c_helper_suffix() return "f64" end
    function Core.ScalarRawPtr:c_helper_suffix() return "ptr" end
    function Core.ScalarIndex:c_helper_suffix() return "index" end

    function Core.UnaryOp:c_helper_suffix() error("missing c_helper_suffix leaf method for UnaryOp", 2) end
    function Core.UnaryNeg:c_helper_suffix() return "neg" end
    function Core.UnaryNot:c_helper_suffix() return "not" end
    function Core.UnaryBitNot:c_helper_suffix() return "bitnot" end

    function Core.BinaryOp:c_helper_suffix() error("missing c_helper_suffix leaf method for BinaryOp", 2) end
    function Core.BinAdd:c_helper_suffix() return "add" end
    function Core.BinSub:c_helper_suffix() return "sub" end
    function Core.BinMul:c_helper_suffix() return "mul" end
    function Core.BinDiv:c_helper_suffix() return "div" end
    function Core.BinRem:c_helper_suffix() return "rem" end
    function Core.BinBitAnd:c_helper_suffix() return "and" end
    function Core.BinBitOr:c_helper_suffix() return "or" end
    function Core.BinBitXor:c_helper_suffix() return "xor" end
    function Core.BinShl:c_helper_suffix() return "shl" end
    function Core.BinLShr:c_helper_suffix() return "lshr" end
    function Core.BinAShr:c_helper_suffix() return "ashr" end
    function Core.BinaryOp:c_helper_expr(a, b) error("missing c_helper_expr leaf method for BinaryOp", 2) end
    function Core.BinAdd:c_helper_expr(a, b) return a .. " + " .. b end
    function Core.BinSub:c_helper_expr(a, b) return a .. " - " .. b end
    function Core.BinMul:c_helper_expr(a, b) return a .. " * " .. b end
    function Core.BinDiv:c_helper_expr(a, b) return a .. " / " .. b end
    function Core.BinRem:c_helper_expr(a, b) return a .. " % " .. b end
    function Core.BinBitAnd:c_helper_expr(a, b) return a .. " & " .. b end
    function Core.BinBitOr:c_helper_expr(a, b) return a .. " | " .. b end
    function Core.BinBitXor:c_helper_expr(a, b) return a .. " ^ " .. b end
    function Core.BinShl:c_helper_expr(a, b) return a .. " << " .. b end
    function Core.BinLShr:c_helper_expr(a, b) return a .. " >> " .. b end
    function Core.BinAShr:c_helper_expr(a, b) return a .. " >> " .. b end

    function Core.MachineCastOp:c_helper_suffix() error("missing c_helper_suffix leaf method for MachineCastOp", 2) end
    function Core.MachineCastIdentity:c_helper_suffix() return "identity" end
    function Core.MachineCastBitcast:c_helper_suffix() return "bitcast" end
    function Core.MachineCastIreduce:c_helper_suffix() return "ireduce" end
    function Core.MachineCastSextend:c_helper_suffix() return "sextend" end
    function Core.MachineCastUextend:c_helper_suffix() return "uextend" end
    function Core.MachineCastFpromote:c_helper_suffix() return "fpromote" end
    function Core.MachineCastFdemote:c_helper_suffix() return "fdemote" end
    function Core.MachineCastSToF:c_helper_suffix() return "stof" end
    function Core.MachineCastUToF:c_helper_suffix() return "utof" end
    function Core.MachineCastFToS:c_helper_suffix() return "ftos" end
    function Core.MachineCastFToU:c_helper_suffix() return "ftou" end
    function Core.MachineCastOp:c_emit_helper_cast_body(lines, ret) lines[#lines + 1] = "    return (" .. ret .. ")a1;" end
    function Core.MachineCastBitcast:c_emit_helper_cast_body(lines, ret)
        lines[#lines + 1] = "    " .. ret .. " out;"
        lines[#lines + 1] = "    memset(&out, 0, sizeof(out));"
        lines[#lines + 1] = "    memcpy(&out, &a1, sizeof(out) < sizeof(a1) ? sizeof(out) : sizeof(a1));"
        lines[#lines + 1] = "    return out;"
    end

    function Core.Intrinsic:c_helper_suffix() error("missing c_helper_suffix leaf method for Intrinsic", 2) end
    function Core.IntrinsicPopcount:c_helper_suffix() return "popcount" end
    function Core.IntrinsicClz:c_helper_suffix() return "clz" end
    function Core.IntrinsicCtz:c_helper_suffix() return "ctz" end
    function Core.IntrinsicRotl:c_helper_suffix() return "rotl" end
    function Core.IntrinsicRotr:c_helper_suffix() return "rotr" end
    function Core.IntrinsicBswap:c_helper_suffix() return "bswap" end
    function Core.IntrinsicFma:c_helper_suffix() return "fma" end
    function Core.IntrinsicSqrt:c_helper_suffix() return "sqrt" end
    function Core.IntrinsicAbs:c_helper_suffix() return "abs" end
    function Core.IntrinsicFloor:c_helper_suffix() return "floor" end
    function Core.IntrinsicCeil:c_helper_suffix() return "ceil" end
    function Core.IntrinsicTruncFloat:c_helper_suffix() return "truncfloat" end
    function Core.IntrinsicRound:c_helper_suffix() return "round" end
    function Core.IntrinsicTrap:c_helper_suffix() return "trap" end
    function Core.IntrinsicAssume:c_helper_suffix() return "assume" end
    function Core.Intrinsic:c_helper_signature(ty) return { params = { ty }, result = ty } end
    function Core.IntrinsicTrap:c_helper_signature(ty) return { params = {}, result = C.CBackendVoid } end
    function Core.IntrinsicAssume:c_helper_signature(ty) return { params = { C.CBackendBool8 }, result = C.CBackendVoid } end
    function Core.IntrinsicFma:c_helper_signature(ty) return { params = { ty, ty, ty }, result = ty } end
    function Core.IntrinsicRotl:c_helper_signature(ty) return { params = { ty, ty }, result = ty } end
    function Core.IntrinsicRotr:c_helper_signature(ty) return { params = { ty, ty }, result = ty } end
    function Core.Intrinsic:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return a1;" end
    function Core.IntrinsicTrap:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    abort();" end
    function Core.IntrinsicAssume:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    if (!a1) abort();" end
    function Core.IntrinsicSqrt:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")sqrt((double)a1);" end
    function Core.IntrinsicAbs:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return a1 < 0 ? (" .. ret .. ")((" .. uret .. ")0 - (" .. uret .. ")a1) : a1;" end
    function Core.IntrinsicFma:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")fma((double)a1, (double)a2, (double)a3);" end
    function Core.IntrinsicRotl:c_emit_helper_intrinsic_body(lines, ret, uret)
        lines[#lines + 1] = "    unsigned int s = ((unsigned int)a2) & ((unsigned int)(sizeof(a1) * 8u - 1u));"
        lines[#lines + 1] = "    return (" .. ret .. ")(((" .. uret .. ")a1 << s) | ((" .. uret .. ")a1 >> ((sizeof(a1)*8u - s) & (sizeof(a1)*8u - 1u))));"
    end
    function Core.IntrinsicRotr:c_emit_helper_intrinsic_body(lines, ret, uret)
        lines[#lines + 1] = "    unsigned int s = ((unsigned int)a2) & ((unsigned int)(sizeof(a1) * 8u - 1u));"
        lines[#lines + 1] = "    return (" .. ret .. ")(((" .. uret .. ")a1 >> s) | ((" .. uret .. ")a1 << ((sizeof(a1)*8u - s) & (sizeof(a1)*8u - 1u))));"
    end
    function Core.IntrinsicPopcount:c_emit_helper_intrinsic_body(lines, ret, uret)
        lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1; unsigned int n = 0;"
        lines[#lines + 1] = "    while (x) { n += (unsigned int)(x & 1u); x >>= 1; } return (" .. ret .. ")n;"
    end
    function Core.IntrinsicClz:c_emit_helper_intrinsic_body(lines, ret, uret)
        lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1; unsigned int n = 0;"
        lines[#lines + 1] = "    for (int i = (int)(sizeof(a1)*8u)-1; i >= 0; --i) { if ((x >> i) & 1u) break; ++n; } return (" .. ret .. ")n;"
    end
    function Core.IntrinsicCtz:c_emit_helper_intrinsic_body(lines, ret, uret)
        lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1; unsigned int n = 0;"
        lines[#lines + 1] = "    for (unsigned int i = 0; i < sizeof(a1)*8u; ++i) { if ((x >> i) & 1u) break; ++n; } return (" .. ret .. ")n;"
    end
    function Core.IntrinsicBswap:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    " .. uret .. " x = (" .. uret .. ")a1, y = 0; for (unsigned int i = 0; i < sizeof(a1); ++i) { y = (y << 8) | (x & 255u); x >>= 8; } return (" .. ret .. ")y;" end
    function Core.IntrinsicFloor:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")floor((double)a1);" end
    function Core.IntrinsicCeil:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")ceil((double)a1);" end
    function Core.IntrinsicTruncFloat:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")trunc((double)a1);" end
    function Core.IntrinsicRound:c_emit_helper_intrinsic_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")round((double)a1);" end

    function Core.AtomicRmwOp:c_helper_suffix() error("missing c_helper_suffix leaf method for AtomicRmwOp", 2) end
    function Core.AtomicRmwAdd:c_helper_suffix() return "add" end
    function Core.AtomicRmwSub:c_helper_suffix() return "sub" end
    function Core.AtomicRmwAnd:c_helper_suffix() return "and" end
    function Core.AtomicRmwOr:c_helper_suffix() return "or" end
    function Core.AtomicRmwXor:c_helper_suffix() return "xor" end
    function Core.AtomicRmwXchg:c_helper_suffix() return "xchg" end
    function Core.AtomicRmwOp:c_emit_helper_atomic_rmw(lines) error("missing c_emit_helper_atomic_rmw leaf method", 2) end
    function Core.AtomicRmwAdd:c_emit_helper_atomic_rmw(lines) lines[#lines + 1] = "    return atomic_fetch_add_explicit(p, a2, memory_order_seq_cst);" end
    function Core.AtomicRmwSub:c_emit_helper_atomic_rmw(lines) lines[#lines + 1] = "    return atomic_fetch_sub_explicit(p, a2, memory_order_seq_cst);" end
    function Core.AtomicRmwAnd:c_emit_helper_atomic_rmw(lines) lines[#lines + 1] = "    return atomic_fetch_and_explicit(p, a2, memory_order_seq_cst);" end
    function Core.AtomicRmwOr:c_emit_helper_atomic_rmw(lines) lines[#lines + 1] = "    return atomic_fetch_or_explicit(p, a2, memory_order_seq_cst);" end
    function Core.AtomicRmwXor:c_emit_helper_atomic_rmw(lines) lines[#lines + 1] = "    return atomic_fetch_xor_explicit(p, a2, memory_order_seq_cst);" end
    function Core.AtomicRmwXchg:c_emit_helper_atomic_rmw(lines) lines[#lines + 1] = "    return atomic_exchange_explicit(p, a2, memory_order_seq_cst);" end
    function Core.AtomicSeqCst:c_helper_suffix() return "seqcst" end

    function C.CBackendIntOverflow:c_helper_suffix() error("missing c_helper_suffix leaf method for CBackendIntOverflow", 2) end
    function C.CBackendIntWrap:c_helper_suffix() return "intwrap" end
    function C.CBackendIntTrapOnOverflow:c_helper_suffix() return "inttraponoverflow" end
    function C.CBackendIntAssumeNoOverflow:c_helper_suffix() return "intassumenooverflow" end
    function C.CBackendDivPolicy:c_helper_suffix() error("missing c_helper_suffix leaf method for CBackendDivPolicy", 2) end
    function C.CBackendDivTrapOnZero:c_helper_suffix() return "divtraponzero" end
    function C.CBackendDivTrapOnZeroOrOverflow:c_helper_suffix() return "divtraponzerooroverflow" end
    function C.CBackendShiftPolicy:c_helper_suffix() error("missing c_helper_suffix leaf method for CBackendShiftPolicy", 2) end
    function C.CBackendShiftMaskCount:c_helper_suffix() return "shiftmaskcount" end
    function C.CBackendShiftTrapOutOfRange:c_helper_suffix() return "shifttrapoutofrange" end
    function C.CBackendTargetFeature:c_helper_suffix() error("missing c_helper_suffix leaf method for CBackendTargetFeature", 2) end
    function C.CBackendFeatureC11Atomics:c_helper_suffix() return "c11atomics" end
    function C.CBackendFeatureLibm:c_helper_suffix() return "libm" end
    function C.CBackendFeatureBuiltinOverflow:c_helper_suffix() return "builtinoverflow" end
    function C.CBackendFeatureBuiltinBitops:c_helper_suffix() return "builtinbitops" end
    function C.CBackendFeatureUnalignedAccess:c_helper_suffix() return "unalignedaccess" end
    function C.CBackendFeatureStaticAssert:c_helper_suffix() return "staticassert" end
    function C.CBackendFeatureHostedRuntime:c_helper_suffix() return "hostedruntime" end

    function C.CBackendType:c_helper_suffix() error("missing c_helper_suffix leaf method for CBackendType", 2) end
    function C.CBackendVoid:c_helper_suffix() return "void" end
    function C.CBackendBool8:c_helper_suffix() return "bool8" end
    function C.CBackendScalar:c_helper_suffix() return self.scalar:c_helper_suffix() end
    function C.CBackendIndex:c_helper_suffix() return "index" end
    function C.CBackendDataPtr:c_helper_suffix() return "ptr" end
    function C.CBackendQualifiedDataPtr:c_helper_suffix() return (self.const_pointee and "const_" or "") .. (self.volatile_pointee and "volatile_" or "") .. (self.restrict_ptr and "restrict_" or "") .. "ptr" end
    function C.CBackendCodePtr:c_helper_suffix() return "codeptr_" .. sanitize(self.sig.text) end
    function C.CBackendImportedCodePtr:c_helper_suffix() return "c_codeptr_" .. sanitize(self.sig.text) end
    function C.CBackendNamed:c_helper_suffix() return sanitize(self.id.module_name .. "_" .. self.id.spelling) end
    function C.CBackendArray:c_helper_suffix() return "arr" .. tostring(self.count) .. "_" .. self.elem:c_helper_suffix() end
    function C.CBackendSliceDescriptor:c_helper_suffix() return "slice_" .. self.elem:c_helper_suffix() end
    function C.CBackendByteSpanDescriptor:c_helper_suffix() return "bytespan" end
    function C.CBackendViewDescriptor:c_helper_suffix() return "view_" .. self.elem:c_helper_suffix() end
    function C.CBackendClosureDescriptor:c_helper_suffix() return "closure_" .. sanitize(self.sig.text) end
    function C.CBackendAbiHiddenOutPtr:c_helper_suffix() return "out_" .. self.result:c_helper_suffix() end
    function C.CBackendVector:c_helper_suffix() return self.elem:c_helper_suffix() .. "x" .. tostring(self.lanes) end
    function C.CBackendType:c_helper_unsigned_c_type() return "uint64_t" end
    function C.CBackendIndex:c_helper_unsigned_c_type() return "uintptr_t" end
    function C.CBackendScalar:c_helper_unsigned_c_type()
        if self.scalar == Core.ScalarBool or self.scalar == Core.ScalarI8 or self.scalar == Core.ScalarU8 then return "uint8_t" end
        if self.scalar == Core.ScalarI16 or self.scalar == Core.ScalarU16 then return "uint16_t" end
        if self.scalar == Core.ScalarI32 or self.scalar == Core.ScalarU32 then return "uint32_t" end
        return "uint64_t"
    end
    function C.CBackendType:c_helper_is_signed() return false end
    function C.CBackendScalar:c_helper_is_signed() return self.scalar == Core.ScalarI8 or self.scalar == Core.ScalarI16 or self.scalar == Core.ScalarI32 or self.scalar == Core.ScalarI64 or self.scalar == Core.ScalarIndex end

    function C.CBackendHelperSpec:c_helper_id() error("missing c_helper_id leaf method for CBackendHelperSpec", 2) end
    function C.CBackendHelperUnary:c_helper_id() return C.CBackendHelperId("ml_" .. self.ty:c_helper_suffix() .. "_" .. self.op:c_helper_suffix()) end
    function C.CBackendHelperBoolNormalize:c_helper_id() return C.CBackendHelperId("ml_bool_normalize_" .. self.ty:c_helper_suffix()) end
    function C.CBackendHelperCast:c_helper_id() return C.CBackendHelperId("ml_cast_" .. self.op:c_helper_suffix() .. "_" .. self.from:c_helper_suffix() .. "_to_" .. self.to:c_helper_suffix()) end
    function C.CBackendHelperPtrOffset:c_helper_id() return C.CBackendHelperId("ml_ptroff_" .. self.pointee:c_helper_suffix() .. "_" .. tostring(self.elem_size) .. (self.checked and "_checked" or "")) end
    function C.CBackendHelperIntBinary:c_helper_id() return C.CBackendHelperId("ml_" .. self.ty:c_helper_suffix() .. "_" .. self.op:c_helper_suffix() .. "_" .. self.overflow:c_helper_suffix()) end
    function C.CBackendHelperFloatBinary:c_helper_id() return C.CBackendHelperId("ml_" .. self.ty:c_helper_suffix() .. "_" .. self.op:c_helper_suffix()) end
    function C.CBackendHelperDivRem:c_helper_id() return C.CBackendHelperId("ml_" .. self.ty:c_helper_suffix() .. "_" .. self.op:c_helper_suffix() .. "_" .. self.mode:c_helper_suffix()) end
    function C.CBackendHelperShift:c_helper_id() return C.CBackendHelperId("ml_" .. self.ty:c_helper_suffix() .. "_" .. self.op:c_helper_suffix() .. "_" .. self.mode:c_helper_suffix()) end
    function C.CBackendHelperIntrinsic:c_helper_id() return C.CBackendHelperId("ml_" .. self.ty:c_helper_suffix() .. "_" .. self.intrinsic:c_helper_suffix()) end
    function C.CBackendHelperLoad:c_helper_id() return C.CBackendHelperId("ml_load_" .. self.access.ty:c_helper_suffix() .. "_a" .. tostring(self.access.align)) end
    function C.CBackendHelperStore:c_helper_id() return C.CBackendHelperId("ml_store_" .. self.access.ty:c_helper_suffix() .. "_a" .. tostring(self.access.align)) end
    function C.CBackendHelperAtomicLoad:c_helper_id() return C.CBackendHelperId("ml_atomic_load_" .. self.access.ty:c_helper_suffix()) end
    function C.CBackendHelperAtomicStore:c_helper_id() return C.CBackendHelperId("ml_atomic_store_" .. self.access.ty:c_helper_suffix()) end
    function C.CBackendHelperAtomicRmw:c_helper_id() return C.CBackendHelperId("ml_atomic_" .. self.op:c_helper_suffix() .. "_" .. self.access.ty:c_helper_suffix()) end
    function C.CBackendHelperAtomicCas:c_helper_id() return C.CBackendHelperId("ml_atomic_cas_" .. self.access.ty:c_helper_suffix()) end
    function C.CBackendHelperAtomicFence:c_helper_id() return C.CBackendHelperId("ml_atomic_fence_" .. self.ordering:c_helper_suffix()) end
    function C.CBackendHelperMemcpy:c_helper_id() return C.CBackendHelperId("ml_memcpy") end
    function C.CBackendHelperTypedMemcpy:c_helper_id() return C.CBackendHelperId("ml_memcpy_" .. self.ty:c_helper_suffix() .. "_" .. tostring(self.size) .. "_a" .. tostring(self.align)) end
    function C.CBackendHelperMemset:c_helper_id() return C.CBackendHelperId("ml_memset") end
    function C.CBackendHelperTypedMemset:c_helper_id() return C.CBackendHelperId("ml_memset_" .. self.ty:c_helper_suffix() .. "_" .. tostring(self.size) .. "_a" .. tostring(self.align)) end
    function C.CBackendHelperMemcmp:c_helper_id() return C.CBackendHelperId("ml_memcmp") end
    function C.CBackendHelperLayoutAssert:c_helper_id() return C.CBackendHelperId("ml_layout_assert_" .. C.CBackendNamed(self.assertion.id):c_helper_suffix()) end
    function C.CBackendHelperRequireFeature:c_helper_id() return C.CBackendHelperId("ml_require_" .. self.feature:c_helper_suffix()) end
    function C.CBackendHelperTrap:c_helper_id() return C.CBackendHelperId("ml_trap") end
    function C.CBackendHelperScan:c_helper_id() return C.CBackendHelperId("ml_scan_" .. (self.inclusive and "inc" or "exc") .. "_" .. self.ty:c_helper_suffix() .. "_" .. self.op:c_helper_suffix() .. "_a" .. tostring(self.align)) end
    function C.CBackendHelperFind:c_helper_id() return C.CBackendHelperId("ml_find_" .. self.cmp:c_helper_suffix() .. "_" .. self.ty:c_helper_suffix() .. "_a" .. tostring(self.align)) end
    function C.CBackendHelperReduce:c_helper_id() return C.CBackendHelperId("ml_reduce_" .. self.op:c_helper_suffix() .. "_" .. self.ty:c_helper_suffix() .. "_a" .. tostring(self.align)) end

    function C.CBackendHelperSpec:c_helper_signature() error("missing c_helper_signature leaf method for CBackendHelperSpec", 2) end
    function C.CBackendHelperUse:c_helper_signature() return self.spec:c_helper_signature() end
    function C.CBackendHelperUnary:c_helper_signature() return { params = { self.ty }, result = self.ty } end
    function C.CBackendHelperBoolNormalize:c_helper_signature() return { params = { self.ty }, result = C.CBackendBool8 } end
    function C.CBackendHelperCast:c_helper_signature() return { params = { self.from }, result = self.to } end
    function C.CBackendHelperPtrOffset:c_helper_signature() return { params = { C.CBackendDataPtr(nil), C.CBackendIndex }, result = C.CBackendDataPtr(nil) } end
    function C.CBackendHelperIntBinary:c_helper_signature() return { params = { self.ty, self.ty }, result = self.ty } end
    function C.CBackendHelperFloatBinary:c_helper_signature() return { params = { self.ty, self.ty }, result = self.ty } end
    function C.CBackendHelperDivRem:c_helper_signature() return { params = { self.ty, self.ty }, result = self.ty } end
    function C.CBackendHelperShift:c_helper_signature() return { params = { self.ty, self.ty }, result = self.ty } end
    function C.CBackendHelperIntrinsic:c_helper_signature() return self.intrinsic:c_helper_signature(self.ty) end
    function C.CBackendHelperLoad:c_helper_signature() return { params = { C.CBackendDataPtr(nil) }, result = self.access.ty } end
    function C.CBackendHelperStore:c_helper_signature() return { params = { C.CBackendDataPtr(nil), self.access.ty }, result = C.CBackendVoid } end
    function C.CBackendHelperAtomicLoad:c_helper_signature() return { params = { C.CBackendDataPtr(self.access.ty) }, result = self.access.ty } end
    function C.CBackendHelperAtomicStore:c_helper_signature() return { params = { C.CBackendDataPtr(self.access.ty), self.access.ty }, result = C.CBackendVoid } end
    function C.CBackendHelperAtomicRmw:c_helper_signature() return { params = { C.CBackendDataPtr(self.access.ty), self.access.ty }, result = self.access.ty } end
    function C.CBackendHelperAtomicCas:c_helper_signature() return { params = { C.CBackendDataPtr(self.access.ty), C.CBackendDataPtr(self.access.ty), self.access.ty }, result = self.access.ty } end
    function C.CBackendHelperAtomicFence:c_helper_signature() return { params = {}, result = C.CBackendVoid } end
    function C.CBackendHelperMemcpy:c_helper_signature() return { params = { C.CBackendDataPtr(nil), C.CBackendDataPtr(nil), C.CBackendIndex }, result = C.CBackendVoid } end
    function C.CBackendHelperTypedMemcpy:c_helper_signature() return { params = { C.CBackendDataPtr(nil), C.CBackendDataPtr(nil) }, result = C.CBackendVoid } end
    function C.CBackendHelperMemset:c_helper_signature() return { params = { C.CBackendDataPtr(nil), C.CBackendScalar(Core.ScalarI32), C.CBackendIndex }, result = C.CBackendVoid } end
    function C.CBackendHelperTypedMemset:c_helper_signature() return { params = { C.CBackendDataPtr(nil), C.CBackendScalar(Core.ScalarI32) }, result = C.CBackendVoid } end
    function C.CBackendHelperMemcmp:c_helper_signature() return { params = { C.CBackendDataPtr(nil), C.CBackendDataPtr(nil), C.CBackendIndex }, result = C.CBackendScalar(Core.ScalarI32) } end
    function C.CBackendHelperLayoutAssert:c_helper_signature() return { params = {}, result = C.CBackendVoid } end
    function C.CBackendHelperRequireFeature:c_helper_signature() return { params = {}, result = C.CBackendVoid } end
    function C.CBackendHelperTrap:c_helper_signature() return { params = {}, result = C.CBackendVoid } end
    function C.CBackendHelperScan:c_helper_signature() return { params = { C.CBackendDataPtr(self.ty), C.CBackendDataPtr(self.ty), C.CBackendIndex }, result = C.CBackendVoid } end
    function C.CBackendHelperFind:c_helper_signature() return { params = { C.CBackendDataPtr(self.ty), C.CBackendIndex, self.ty }, result = C.CBackendIndex } end
    function C.CBackendHelperReduce:c_helper_signature() return { params = { C.CBackendDataPtr(self.ty), C.CBackendIndex }, result = self.ty } end

    local function helper_header(id, sig, emit_type)
        local ret = emit_type(sig.result)
        local params = {}
        for i = 1, #sig.params do params[i] = emit_type(sig.params[i]) .. " a" .. tostring(i) end
        return { "static inline " .. ret .. " " .. id.text .. "(" .. table.concat(params, ", ") .. ") {" }, ret
    end

    function C.CBackendHelperSpec:c_emit_helper_body(lines, ret, uret, emit_type) lines[#lines + 1] = "    /* helper spec has no side effects */" end
    function C.CBackendHelperUnary:c_emit_helper_body(lines, ret, uret, emit_type)
        return self.op:c_emit_helper_unary_body(lines, ret, uret)
    end
    function Core.UnaryOp:c_emit_helper_unary_body(lines, ret, uret) error("missing c_emit_helper_unary_body leaf method", 2) end
    function Core.UnaryNot:c_emit_helper_unary_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")(!a1);" end
    function Core.UnaryBitNot:c_emit_helper_unary_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")(~(" .. uret .. ")a1);" end
    function Core.UnaryNeg:c_emit_helper_unary_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")0 - (" .. uret .. ")a1);" end
    function C.CBackendHelperBoolNormalize:c_emit_helper_body(lines) lines[#lines + 1] = "    return a1 ? 1u : 0u;" end
    function C.CBackendHelperCast:c_emit_helper_body(lines, ret) self.op:c_emit_helper_cast_body(lines, ret) end
    function C.CBackendHelperPtrOffset:c_emit_helper_body(lines) lines[#lines + 1] = "    return (void*)((unsigned char*)a1 + ((intptr_t)a2 * (intptr_t)" .. tostring(self.elem_size) .. "));" end
    function C.CBackendHelperLoad:c_emit_helper_body(lines, ret, uret, emit_type) lines[#lines + 1] = "    " .. emit_type(self.access.ty) .. " v;"; lines[#lines + 1] = "    memcpy(&v, a1, sizeof(v));"; lines[#lines + 1] = "    return v;" end
    function C.CBackendHelperStore:c_emit_helper_body(lines) lines[#lines + 1] = "    memcpy(a1, &a2, sizeof(a2));" end
    function C.CBackendHelperAtomicLoad:c_emit_helper_body(lines, ret, uret, emit_type) lines[#lines + 1] = "    _Atomic(" .. emit_type(self.access.ty) .. ")* p = (_Atomic(" .. emit_type(self.access.ty) .. ")*)a1;"; lines[#lines + 1] = "    return atomic_load_explicit(p, memory_order_seq_cst);" end
    function C.CBackendHelperAtomicStore:c_emit_helper_body(lines, ret, uret, emit_type) lines[#lines + 1] = "    _Atomic(" .. emit_type(self.access.ty) .. ")* p = (_Atomic(" .. emit_type(self.access.ty) .. ")*)a1;"; lines[#lines + 1] = "    atomic_store_explicit(p, a2, memory_order_seq_cst);" end
    function C.CBackendHelperAtomicRmw:c_emit_helper_body(lines, ret, uret, emit_type) lines[#lines + 1] = "    _Atomic(" .. emit_type(self.access.ty) .. ")* p = (_Atomic(" .. emit_type(self.access.ty) .. ")*)a1;"; self.op:c_emit_helper_atomic_rmw(lines) end
    function C.CBackendHelperAtomicCas:c_emit_helper_body(lines, ret, uret, emit_type) lines[#lines + 1] = "    _Atomic(" .. emit_type(self.access.ty) .. ")* p = (_Atomic(" .. emit_type(self.access.ty) .. ")*)a1;"; lines[#lines + 1] = "    " .. emit_type(self.access.ty) .. " old = *(" .. emit_type(self.access.ty) .. "*)a2;"; lines[#lines + 1] = "    atomic_compare_exchange_strong_explicit(p, (" .. emit_type(self.access.ty) .. "*)a2, a3, memory_order_seq_cst, memory_order_seq_cst);"; lines[#lines + 1] = "    return old;" end
    function C.CBackendHelperAtomicFence:c_emit_helper_body(lines) lines[#lines + 1] = "    atomic_thread_fence(memory_order_seq_cst);" end
    function C.CBackendHelperMemcpy:c_emit_helper_body(lines) lines[#lines + 1] = "    memcpy(a1, a2, (size_t)a3);" end
    function C.CBackendHelperTypedMemcpy:c_emit_helper_body(lines) lines[#lines + 1] = "    memcpy(a1, a2, (size_t)" .. tostring(self.size) .. ");" end
    function C.CBackendHelperMemset:c_emit_helper_body(lines) lines[#lines + 1] = "    memset(a1, a2, (size_t)a3);" end
    function C.CBackendHelperTypedMemset:c_emit_helper_body(lines) lines[#lines + 1] = "    memset(a1, a2, (size_t)" .. tostring(self.size) .. ");" end
    function C.CBackendHelperMemcmp:c_emit_helper_body(lines) lines[#lines + 1] = "    return memcmp(a1, a2, (size_t)a3);" end
    function C.CBackendHelperTrap:c_emit_helper_body(lines) lines[#lines + 1] = "    abort();" end
    function C.CBackendHelperScan:c_emit_helper_body(lines, ret, uret, emit_type)
        local elem_ty = emit_type(self.ty)
        lines[#lines + 1] = "    a1 = __builtin_assume_aligned(a1, " .. tostring(self.align) .. ");"
        lines[#lines + 1] = "    a2 = __builtin_assume_aligned(a2, " .. tostring(self.align) .. ");"
        lines[#lines + 1] = "    " .. elem_ty .. " acc = 0;"
        if self.inclusive then
            lines[#lines + 1] = "    for (ml_index i = 0; i < (ml_index)a3; i++) {"
            lines[#lines + 1] = "        acc = (" .. elem_ty .. ")(" .. self.op:c_helper_expr("acc", "a2[i]") .. ");"
            lines[#lines + 1] = "        a1[i] = acc;"
            lines[#lines + 1] = "    }"
        else
            lines[#lines + 1] = "    for (ml_index i = 0; i < (ml_index)a3; i++) {"
            lines[#lines + 1] = "        a1[i] = acc;"
            lines[#lines + 1] = "        acc = (" .. elem_ty .. ")(" .. self.op:c_helper_expr("acc", "a2[i]") .. ");"
            lines[#lines + 1] = "    }"
        end
    end
    function C.CBackendHelperFind:c_emit_helper_body(lines, ret, uret, emit_type)
        lines[#lines + 1] = "    a1 = __builtin_assume_aligned(a1, " .. tostring(self.align) .. ");"
        lines[#lines + 1] = "    for (ml_index i = 0; i < (ml_index)a2; i++) {"
        lines[#lines + 1] = "        if (a1[i] " .. self.cmp:c_emit_cmp_op() .. " a3) return i;"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return a2;"
    end
    function C.CBackendHelperReduce:c_emit_helper_body(lines, ret, uret, emit_type)
        local elem_ty = emit_type(self.ty)
        lines[#lines + 1] = "    a1 = __builtin_assume_aligned(a1, " .. tostring(self.align) .. ");"
        lines[#lines + 1] = "    " .. elem_ty .. " acc = " .. (self.identity_is_zero and "0" or "a1[0]") .. ";"
        local start = self.identity_is_zero and "0" or "1"
        lines[#lines + 1] = "    for (ml_index i = " .. start .. "; i < (ml_index)a2; i++) {"
        lines[#lines + 1] = "        acc = (" .. elem_ty .. ")(" .. self.op:c_helper_expr("acc", "a1[i]") .. ");"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "    return acc;"
    end
    function C.CBackendHelperIntrinsic:c_emit_helper_body(lines, ret, uret) self.intrinsic:c_emit_helper_intrinsic_body(lines, ret, uret) end
    function C.CBackendHelperDivRem:c_emit_helper_body(lines, ret, uret) lines[#lines + 1] = "    if (a2 == 0) abort();"; if self.ty:c_helper_is_signed() then lines[#lines + 1] = "    if (a2 == (" .. ret .. ")-1 && a1 == (" .. ret .. ")(((" .. uret .. ")1) << (sizeof(a1) * 8u - 1u))) abort();" end; lines[#lines + 1] = "    return (" .. ret .. ")(" .. self.op:c_helper_expr("a1", "a2") .. ");" end
    function C.CBackendHelperShift:c_emit_helper_body(lines, ret, uret)
        lines[#lines + 1] = "    unsigned int width = (unsigned int)(sizeof(a1) * 8u);"
        lines[#lines + 1] = "    unsigned int s = ((unsigned int)a2) & (width - 1u);"
        self.op:c_emit_helper_shift_body(lines, ret, uret, self.ty)
    end
    function Core.BinaryOp:c_emit_helper_shift_body(lines, ret, uret, ty) lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 >> s);" end
    function Core.BinShl:c_emit_helper_shift_body(lines, ret, uret, ty) lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 << s);" end
    function Core.BinAShr:c_emit_helper_shift_body(lines, ret, uret, ty)
        if ty:c_helper_is_signed() then
            lines[#lines + 1] = "    " .. uret .. " mask = (" .. uret .. ")~(" .. uret .. ")0;"
            lines[#lines + 1] = "    " .. uret .. " x = ((" .. uret .. ")a1) & mask;"
            lines[#lines + 1] = "    if (s != 0u && a1 < 0) x = (x >> s) | (mask << (width - s)); else x >>= s;"
            lines[#lines + 1] = "    return (" .. ret .. ")(x & mask);"
        else
            lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 >> s);"
        end
    end
    function C.CBackendHelperIntBinary:c_emit_helper_body(lines, ret, uret) self.op:c_emit_helper_int_binary_body(lines, ret, uret) end
    function Core.BinaryOp:c_emit_helper_int_binary_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")(" .. self:c_helper_expr("a1", "a2") .. ");" end
    function Core.BinAdd:c_emit_helper_int_binary_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 + (" .. uret .. ")a2);" end
    function Core.BinSub:c_emit_helper_int_binary_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 - (" .. uret .. ")a2);" end
    function Core.BinMul:c_emit_helper_int_binary_body(lines, ret, uret) lines[#lines + 1] = "    return (" .. ret .. ")((" .. uret .. ")a1 * (" .. uret .. ")a2);" end
    function C.CBackendHelperFloatBinary:c_emit_helper_body(lines, ret) self.op:c_emit_helper_float_binary_body(lines, ret) end
    function Core.BinaryOp:c_emit_helper_float_binary_body(lines, ret) lines[#lines + 1] = "    return (" .. ret .. ")(a1 + a2);" end
    function Core.BinAdd:c_emit_helper_float_binary_body(lines, ret) lines[#lines + 1] = "    return (" .. ret .. ")(a1 + a2);" end
    function Core.BinSub:c_emit_helper_float_binary_body(lines, ret) lines[#lines + 1] = "    return (" .. ret .. ")(a1 - a2);" end
    function Core.BinMul:c_emit_helper_float_binary_body(lines, ret) lines[#lines + 1] = "    return (" .. ret .. ")(a1 * a2);" end
    function Core.BinDiv:c_emit_helper_float_binary_body(lines, ret) lines[#lines + 1] = "    return (" .. ret .. ")(a1 / a2);" end
    function C.CBackendHelperLayoutAssert:c_emit_helper_body(lines) lines[#lines + 1] = "    typedef char ml_size_assert[(sizeof(" .. C.CBackendNamed(self.assertion.id):c_emit_type() .. ") == " .. tostring(self.assertion.size) .. ") ? 1 : -1]; (void)sizeof(ml_size_assert);" end
    function C.CBackendHelperRequireFeature:c_emit_helper_body(lines) lines[#lines + 1] = "    /* required target feature: " .. self.feature:c_helper_suffix() .. " - " .. tostring(self.reason):gsub("[\r\n]", " ") .. " */" end

    function C.CBackendHelperSpec:c_emit_helper_lines_with_id(id, emit_type)
        emit_type = emit_type or c_type_name
        local sig = self:c_helper_signature()
        local lines, ret = helper_header(id, sig, emit_type)
        local uret = ((not sig.result:c_emit_is_void() and sig.result) or sig.params[1] or C.CBackendIndex):c_helper_unsigned_c_type()
        self:c_emit_helper_body(lines, ret, uret, emit_type)
        lines[#lines + 1] = "}"
        return lines
    end
    function C.CBackendHelperSpec:c_emit_helper_lines(emit_type) return self:c_emit_helper_lines_with_id(self:c_helper_id(), emit_type) end
    function C.CBackendHelperUse:c_emit_helper_lines(emit_type) return self.spec:c_emit_helper_lines_with_id(self.id, emit_type) end

    local function helper_key(spec) return spec:c_helper_id().text end
    local function helper_id(spec) return spec:c_helper_id() end
    local function helper_signature(use) return use:c_helper_signature() end
    local function emit_helper(use, emit_type) return use:c_emit_helper_lines(emit_type) end
    -- Register a backend helper with the C emit machine.
    -- Returns (id, new_machine) when machine is non-nil.
    local function register(machine, spec)
        local id = spec:c_helper_id()
        if machine == nil then return id, machine end
        local entry = CEm.CEmitHelperEntry(id.text, CEm.CEmitHelper("", ""))
        local new_machine = machine:with_helper(entry)
        return id, new_machine
    end

    local function emit_includes(unit, out)
        local needs_atomics = false; for i = 1, #unit.helpers do if unit.helpers[i]:c_emit_helper_is_atomic() then needs_atomics = true end end
        out[#out + 1] = "#include <stdint.h>"; out[#out + 1] = "#include <stddef.h>"; out[#out + 1] = "#include <string.h>"; out[#out + 1] = "#include <stdlib.h>"; out[#out + 1] = "#include <math.h>"
        if needs_atomics and unit.target and unit.target.dialect:c_emit_supports_c11_atomics() then out[#out + 1] = "#include <stdatomic.h>" end
        if needs_atomics and (not unit.target or not unit.target.dialect:c_emit_supports_c11_atomics()) then out[#out + 1] = "/* atomics require C11 <stdatomic.h> or a runtime helper provider */" end
    end

    function C.CBackendTypeDecl:c_emit_forward(out) end
    function C.CBackendStructDecl:c_emit_forward(out) local name = sanitize(self.id.module_name .. "_" .. self.id.spelling); out[#out + 1] = "typedef struct " .. name .. " " .. name .. ";" end
    function C.CBackendUnionDecl:c_emit_forward(out) local name = sanitize(self.id.module_name .. "_" .. self.id.spelling); out[#out + 1] = "typedef union " .. name .. " " .. name .. ";" end
    function C.CBackendOpaqueDecl:c_emit_forward(out) local name = sanitize(self.id.module_name .. "_" .. self.id.spelling); out[#out + 1] = "typedef struct " .. name .. " " .. name .. ";" end
    local function emit_type_forwards(unit, descriptor_order, closure_order, out) for i = 1, #descriptor_order do out[#out + 1] = "typedef struct " .. descriptor_order[i] .. " " .. descriptor_order[i] .. ";" end; for i = 1, #closure_order do out[#out + 1] = "typedef struct " .. closure_order[i] .. " " .. closure_order[i] .. ";" end; for i = 1, #unit.types do unit.types[i]:c_emit_forward(out) end end
    local function emit_signatures(unit, out) for i = 1, #unit.sigs do local s = unit.sigs[i]; out[#out + 1] = "typedef " .. s.result:c_emit_type() .. " (*" .. s.id.text .. ")(" .. sig_params(s.params) .. ");" end end
    local function emit_extern_prototypes(unit, sigs, out) for i = 1, #unit.externs do local e, s = unit.externs[i], sigs[unit.externs[i].sig.text]; out[#out + 1] = "extern " .. s.result:c_emit_type() .. " " .. e.name.text .. "(" .. sig_params(s.params) .. ");" end end
    function Exec.ExecFragmentBody:c_emit_exec_prototype(out, seen) end
    function Exec.ExecFragmentStencil:c_emit_exec_prototype(out, seen) local decl = self.artifact.c_signature; if decl and decl ~= "" and not seen[decl] then seen[decl] = true; out[#out + 1] = decl:match(";%s*$") and decl or (decl .. ";") end end
    local function emit_exec_prototypes(unit, out) local seen = {}; for i = 1, #(unit.funcs or {}) do unit.funcs[i].body:c_emit_exec_prototypes(out, seen) end end
    function C.CBackendFuncBody:c_emit_exec_prototypes(out, seen) end
    function C.CBackendBodyExec:c_emit_exec_prototypes(out, seen) self.fragment.fragment.body:c_emit_exec_prototype(out, seen) end
    function C.CBackendBodyMixed:c_emit_exec_prototypes(out, seen) for i = 1, #(self.fragments or {}) do self.fragments[i].fragment.body:c_emit_exec_prototype(out, seen) end end
    local function emit_func_prototypes(unit, sigs, out, opts) for i = 1, #unit.funcs do local f = unit.funcs[i]; if not opts.exported_only or f.visibility == Core.VisibilityExport then local s = sigs[f.sig.text]; out[#out + 1] = s.result:c_emit_type() .. " " .. f.name.text .. "(" .. func_params(f.params) .. ");" end end end
    local function emit_support(opts) local sources = {}; if type(opts.support_source) == "string" and opts.support_source ~= "" then sources[#sources + 1] = opts.support_source end; if type(opts.support_sources) == "table" then for i = 1, #opts.support_sources do if type(opts.support_sources[i]) == "string" and opts.support_sources[i] ~= "" then sources[#sources + 1] = opts.support_sources[i] end end end; if #sources == 0 then return "" end; return table.concat(sources, "\n\n") .. "\n" end

    local function emit(unit, opts)
        opts = opts or {}; local out = {}
        out[#out + 1] = "/* generated by lalin C backend */"; out[#out + 1] = "/* target: pointer_bits=" .. tostring(unit.target and unit.target.pointer_bits or 64) .. " index_bits=" .. tostring(unit.target and unit.target.index_bits or 64) .. " hosted=" .. tostring(unit.target and unit.target.hosted ~= false) .. " */"; emit_includes(unit, out); out[#out + 1] = ""
        out[#out + 1] = "/* typedefs */"; local index_ty = (unit.target and unit.target.index_bits == 32) and "int32_t" or "int64_t"; out[#out + 1] = "typedef " .. index_ty .. " ml_index;"; out[#out + 1] = ""
        local closure_types, closure_order, descriptor_types, descriptor_order = collect_implicit_types(unit)
        out[#out + 1] = "/* type forwards for signatures */"; emit_type_forwards(unit, descriptor_order, closure_order, out); out[#out + 1] = ""
        out[#out + 1] = "/* signatures */"; emit_signatures(unit, out); out[#out + 1] = ""
        out[#out + 1] = "/* type declarations and layout assertions */"; emit_descriptor_type_decls(descriptor_types, descriptor_order, out); emit_closure_type_decls(closure_types, closure_order, out); emit_type_decls(unit, out); out[#out + 1] = ""
        local sigs = sig_by_id(unit); out[#out + 1] = "/* externs */"; emit_extern_prototypes(unit, sigs, out); emit_exec_prototypes(unit, out); out[#out + 1] = ""
        out[#out + 1] = "/* globals */"; emit_globals(unit, out); out[#out + 1] = ""
        out[#out + 1] = "/* helpers */"; for i = 1, #unit.helpers do append_all(out, unit.helpers[i]:c_emit_helper_lines(c_type_name)) end; out[#out + 1] = ""
        out[#out + 1] = "/* prototypes */"; emit_func_prototypes(unit, sigs, out, { exported_only = false }); out[#out + 1] = ""
        out[#out + 1] = "/* bodies */"
        local func_annotations = unit._func_annotations or {}
        for i = 1, #unit.funcs do unit.funcs[i]:c_emit_func(sigs, out, func_annotations[unit.funcs[i].name.text]) end
        return table.concat(out, "\n") .. "\n"
    end

    local function emit_header(unit, opts)
        opts = opts or {}; local out = {}; local guard = sanitize((opts.guard or opts.name or unit.module_name or "lalin") .. "_h"):upper()
        out[#out + 1] = "/* generated by lalin C backend */"; out[#out + 1] = "#ifndef " .. guard; out[#out + 1] = "#define " .. guard; out[#out + 1] = ""; emit_includes(unit, out); out[#out + 1] = ""; out[#out + 1] = "#ifdef __cplusplus"; out[#out + 1] = "extern \"C\" {"; out[#out + 1] = "#endif"; out[#out + 1] = ""
        out[#out + 1] = "/* typedefs */"; local index_ty = (unit.target and unit.target.index_bits == 32) and "int32_t" or "int64_t"; out[#out + 1] = "typedef " .. index_ty .. " ml_index;"; out[#out + 1] = ""
        local closure_types, closure_order, descriptor_types, descriptor_order = collect_implicit_types(unit)
        out[#out + 1] = "/* type forwards for signatures */"; emit_type_forwards(unit, descriptor_order, closure_order, out); out[#out + 1] = ""
        out[#out + 1] = "/* signatures */"; emit_signatures(unit, out); out[#out + 1] = ""
        out[#out + 1] = "/* type declarations */"; emit_descriptor_type_decls(descriptor_types, descriptor_order, out); emit_closure_type_decls(closure_types, closure_order, out); emit_type_decls(unit, out); out[#out + 1] = ""
        local sigs = sig_by_id(unit); out[#out + 1] = "/* required extern pins */"; emit_extern_prototypes(unit, sigs, out); out[#out + 1] = ""; out[#out + 1] = "/* functions */"; emit_func_prototypes(unit, sigs, out, { exported_only = opts.exported_only == true }); out[#out + 1] = ""; out[#out + 1] = "#ifdef __cplusplus"; out[#out + 1] = "}"; out[#out + 1] = "#endif"; out[#out + 1] = ""; out[#out + 1] = "#endif"
        return table.concat(out, "\n") .. "\n"
    end

    local function emit_artifact(unit, opts)
        opts = opts or {}; local source = emit(unit, opts); local header = emit_header(unit, opts); local support = emit_support(opts); local combined = support ~= "" and (support .. "\n" .. source) or source
        return { unit = unit, source = source, header = header, support = support, combined = combined }
    end

    local helper_api = { helper_key = helper_key, helper_id = helper_id, register = register, helper_signature = helper_signature, emit_helper = emit_helper, type_suffix = function(ty) return ty:c_helper_suffix() end }
    local api = { emit_artifact = emit_artifact, emit_header = emit_header, emit_support = emit_support, emit_type = c_type_name, helpers = helper_api }
    T._lalin_api_cache.c_emit = api
    return api
end

return bind_context
