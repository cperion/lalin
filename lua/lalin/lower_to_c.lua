local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s:match("^%d") then s = "_" .. s end
    if s == "" then s = "x" end
    return s
end

local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.lower_to_c ~= nil then return T._lalin_api_cache.lower_to_c end

    local Core = T.LalinCore
    local Code = T.LalinCode
    local C = T.LalinC
    local Lower = T.LalinLower
    local Kernel = T.LalinKernel
    local Schedule = T.LalinSchedule
    local Value = T.LalinValue
    local Mem = T.LalinMem

    local CodeToC = require("lalin.code_to_c")(T)
    local CodeType = require("lalin.code_type")(T)
    local CodeGraph = require("lalin.code_graph")(T)
    local CodeFlowFacts = require("lalin.code_flow_facts")(T)
    local CodeValueFacts = require("lalin.code_value_facts")(T)
    local CodeMemFacts = require("lalin.code_mem_facts")(T)
    local CodeEffectFacts = require("lalin.code_effect_facts")(T)
    local CodeKernelPlan = require("lalin.code_kernel_plan")(T)
    local CodeSchedulePlan = require("lalin.code_schedule_plan")(T)
    local CodeLowerPlan = require("lalin.code_lower_plan")(T)
    local ExecPlan = require("lalin.exec_plan")(T)

    local api = {}

    function Schedule.ScheduleForm:lower_emit_kernel_selection()
        return Lower.LowerEmitScalarKernel
    end
    function Schedule.ScheduleVector:lower_emit_kernel_selection()
        return Lower.LowerEmitVectorKernel
    end
    function Schedule.KernelSchedule:lower_emit_kernel_selection()
        return Lower.LowerEmitScalarKernel
    end
    function Schedule.SchedulePlanned:lower_emit_kernel_selection()
        return self.form:lower_emit_kernel_selection()
    end

    function Lower.LowerStrategy:lower_emit_candidate(schedule)
        return Lower.LowerEmitUnsupportedCandidate("unsupported LowerStrategy for C emission " .. tostring(self))
    end
    function Lower.LowerStrategyCode:lower_emit_candidate(schedule)
        return Lower.LowerEmitCodeCandidate
    end
    function Lower.LowerStrategyClosedForm:lower_emit_candidate(schedule)
        return Lower.LowerEmitClosedFormCandidate
    end
    function Lower.LowerStrategyKernel:lower_emit_candidate(schedule)
        if schedule == nil then return Lower.LowerEmitMissingScheduleCandidate(self:lower_emit_missing_schedule_reason()) end
        return Lower.LowerEmitKernelCandidate(schedule)
    end

    function Lower.LowerEmitCandidate:select_lower_emit()
        return Lower.LowerEmitUnsupported("unsupported lower emit candidate " .. tostring(self))
    end
    function Lower.LowerEmitCodeCandidate:select_lower_emit()
        return Lower.LowerEmitCode
    end
    function Lower.LowerEmitClosedFormCandidate:select_lower_emit()
        return Lower.LowerEmitClosedForm
    end
    function Lower.LowerEmitKernelCandidate:select_lower_emit()
        return self.schedule:lower_emit_kernel_selection()
    end
    function Lower.LowerEmitMissingScheduleCandidate:select_lower_emit()
        return Lower.LowerEmitMissingSchedule(self.reason)
    end
    function Lower.LowerEmitUnsupportedCandidate:select_lower_emit()
        return Lower.LowerEmitUnsupported(self.reason)
    end

    local function cname(text) return C.CBackendName(sanitize(text)) end
    local function clabel(id) return C.CBackendLabel(sanitize(id.text)) end
    local function cid(id) return C.CBackendLocalId(sanitize(id.text)) end
    local function atom(id) return C.CBackendAtomLocal(cid(id)) end

    local function node_name(x) return tostring(x) end

    local function make_c_type_projection(code_module)
        local c_type_projection = { code_sigs = {}, code_sig_order = {} }
        for _, sig in ipairs(code_module.sigs or {}) do c_type_projection.code_sigs[sig.id.text] = sig end
        return c_type_projection
    end

    local function c_ty(c_emission, ty)
        return CodeType.code_type_to_c(ty, c_emission.c_type_projection)
    end

    local function helper_key(spec) return tostring(spec) end

    local function add_helper(c_emission, spec)
        local key = helper_key(spec)
        local existing = c_emission.helper_by_key[key]
        if existing ~= nil then return existing.id end
        c_emission.next_helper = c_emission.next_helper + 1
        local use = C.CBackendHelperUse(C.CBackendHelperId("ml_semantic_helper_" .. tostring(c_emission.next_helper)), spec)
        c_emission.helper_by_key[key] = use
        c_emission.unit.helpers[#c_emission.unit.helpers + 1] = use
        return use.id
    end

    local function add_local(c_emission, id, ty)
        local text = id.text or id
        local lid = type(id) == "table" and id or C.CBackendLocalId(text)
        if c_emission.local_seen[lid.text] then return lid end
        c_emission.local_seen[lid.text] = true
        c_emission.func.locals[#c_emission.func.locals + 1] = C.CBackendLocal(lid, C.CBackendName(lid.text), c_ty(c_emission, ty))
        return lid
    end

    local function note_value(c_emission, id, ty)
        if id ~= nil and ty ~= nil then c_emission.value_types[id.text] = ty end
    end

    local function value_ty(c_emission, id) return id and c_emission.value_types[id.text] or nil end
    function Code.CodeType:lower_c_without_lease() return self end
    function Code.CodeTyLease:lower_c_without_lease() return self.base end
    function Code.CodeType:lower_c_view_elem_type() return nil end
    function Code.CodeTyView:lower_c_view_elem_type() return self.elem end
    function Code.CodeType:lower_c_slice_elem_type() return nil end
    function Code.CodeTySlice:lower_c_slice_elem_type() return self.elem end
    function Code.CodeType:lower_c_is_descriptor_like() return false end
    function Code.CodeTyView:lower_c_is_descriptor_like() return true end
    function Code.CodeTySlice:lower_c_is_descriptor_like() return true end
    function Code.CodeTyByteSpan:lower_c_is_descriptor_like() return true end

    local function view_type(c_emission, id)
        local ty = value_ty(c_emission, id)
        return ty and ty:lower_c_without_lease() or nil
    end
    local function view_elem_type(c_emission, id)
        local ty = view_type(c_emission, id)
        return ty and ty:lower_c_view_elem_type() or nil
    end
    local function view_data_type(c_emission, id)
        return Code.CodeTyDataPtr(view_elem_type(c_emission, id))
    end
    local function slice_elem_type(c_emission, id)
        local ty = view_type(c_emission, id)
        return ty and ty:lower_c_slice_elem_type() or nil
    end
    local function slice_data_type(c_emission, id)
        return Code.CodeTyDataPtr(slice_elem_type(c_emission, id))
    end
    local function byte_ty()
        return Code.CodeTyInt(8, Code.CodeUnsigned)
    end

    local function tmp(c_emission, prefix, ty)
        c_emission.next_tmp = c_emission.next_tmp + 1
        local id = C.CBackendLocalId(sanitize("semantic." .. prefix .. "." .. tostring(c_emission.next_tmp)))
        add_local(c_emission, id, ty)
        return id
    end

    function Code.CodeConst:lower_c_const_atom(c_emission) error("lower_to_c: unsupported semantic const " .. node_name(self), 3) end
    function Code.CodeConstLiteral:lower_c_const_atom(c_emission) return C.CBackendAtomLiteral(c_ty(c_emission, self.ty), self.literal), self.ty end
    function Code.CodeConstNull:lower_c_const_atom(c_emission) return C.CBackendAtomNull(c_ty(c_emission, self.ty)), self.ty end
    function Code.CodeConstUndef:lower_c_const_atom(c_emission) return C.CBackendAtomLiteral(c_ty(c_emission, self.ty), Core.LitInt("0")), self.ty end
    function Code.CodeConst:lower_c_literal_int_raw() return nil end
    function Code.CodeConstLiteral:lower_c_literal_int_raw() return self.literal:lower_c_literal_int_raw(self.ty) end
    function Core.Literal:lower_c_literal_int_raw(ty) return nil end
    function Core.LitInt:lower_c_literal_int_raw(ty) return self.raw, ty end
    function Code.CodeConst:lower_c_literal_bool_value() return nil end
    function Code.CodeConstLiteral:lower_c_literal_bool_value() return self.literal:lower_c_literal_bool_value() end
    function Core.Literal:lower_c_literal_bool_value() return nil end
    function Core.LitBool:lower_c_literal_bool_value() return self.value end
    function Core.LitInt:lower_c_literal_bool_value() return self.raw ~= "0" end

    local function const_atom(c_emission, const) return const:lower_c_const_atom(c_emission) end

    local function assign(c_emission, dst, rhs)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, rhs)
    end

    local function cast_to(c_emission, src_atom, src_ty, dst_ty, name)
        if tostring(c_ty(c_emission, src_ty)) == tostring(c_ty(c_emission, dst_ty)) then return src_atom, dst_ty end
        local dst = tmp(c_emission, name or "cast", dst_ty)
        assign(c_emission, dst, C.CBackendRCast(Core.MachineCastIdentity, c_ty(c_emission, dst_ty), src_atom))
        return C.CBackendAtomLocal(dst), dst_ty
    end

    function Code.CodeIntOverflow:lower_c_overflow_mode() return C.CBackendIntWrap end
    function Code.CodeIntWrap:lower_c_overflow_mode() return C.CBackendIntWrap end
    function Code.CodeIntTrapOnOverflow:lower_c_overflow_mode() return C.CBackendIntTrapOnOverflow end
    function Code.CodeIntAssumeNoOverflow:lower_c_overflow_mode() return C.CBackendIntAssumeNoOverflow end
    function Code.CodeDivPolicy:lower_c_div_mode() return C.CBackendDivTrapOnZero end
    function Code.CodeDivTrapOnZero:lower_c_div_mode() return C.CBackendDivTrapOnZero end
    function Code.CodeDivTrapOnZeroOrOverflow:lower_c_div_mode() return C.CBackendDivTrapOnZeroOrOverflow end

    local function overflow_mode(sem) return sem and sem.overflow and sem.overflow:lower_c_overflow_mode() or C.CBackendIntWrap end

    local function binary_helper(c_emission, op, ty, sem)
        if op:lower_c_is_div_or_rem() then
            local mode = sem and sem.div and sem.div:lower_c_div_mode() or C.CBackendDivTrapOnZero
            return add_helper(c_emission, C.CBackendHelperDivRem(op, c_ty(c_emission, ty), mode))
        end
        return add_helper(c_emission, C.CBackendHelperIntBinary(op, c_ty(c_emission, ty), overflow_mode(sem)))
    end
    function Core.BinaryOp:lower_c_is_div_or_rem() return false end
    function Core.BinDiv:lower_c_is_div_or_rem() return true end
    function Core.BinRem:lower_c_is_div_or_rem() return true end

    local simplify_value_expr, lower_value_expr, lower_value_expr_lane
    local function literal_int_raw(expr) return expr:lower_c_literal_int_raw() end
    local function literal_bool_value(expr) return expr:lower_c_literal_bool_value() end
    local function int_const(ty, raw) return Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(raw)))) end
    local function is_raw(raw, want) return raw ~= nil and tostring(raw) == tostring(want) end

    function Value.ValueExpr:lower_c_literal_int_raw() return nil end
    function Value.ValueExprConst:lower_c_literal_int_raw() return self.const:lower_c_literal_int_raw() end
    function Value.ValueExpr:lower_c_literal_bool_value() return nil end
    function Value.ValueExprConst:lower_c_literal_bool_value() return self.const:lower_c_literal_bool_value() end
    function Value.ValueExpr:lower_c_simplify() return self end
    function Value.ValueExprAdd:lower_c_rebuild(a, b) return Value.ValueExprAdd(a, b, self.ty, self.sem) end
    function Value.ValueExprSub:lower_c_rebuild(a, b) return Value.ValueExprSub(a, b, self.ty, self.sem) end
    function Value.ValueExprMul:lower_c_rebuild(a, b) return Value.ValueExprMul(a, b, self.ty, self.sem) end
    function Value.ValueExprDiv:lower_c_rebuild(a, b) return Value.ValueExprDiv(a, b, self.ty, self.sem) end
    function Value.ValueExprRem:lower_c_rebuild(a, b) return Value.ValueExprRem(a, b, self.ty, self.sem) end
    function Value.ValueExpr:lower_c_arith_op() return nil end
    function Value.ValueExprAdd:lower_c_arith_op() return Core.BinAdd end
    function Value.ValueExprSub:lower_c_arith_op() return Core.BinSub end
    function Value.ValueExprMul:lower_c_arith_op() return Core.BinMul end
    function Value.ValueExprDiv:lower_c_arith_op() return Core.BinDiv end
    function Value.ValueExprRem:lower_c_arith_op() return Core.BinRem end
    function Value.ValueExprAdd:lower_c_simplify_binary_identity(a, b, ar, br) if is_raw(ar, "0") then return b end; if is_raw(br, "0") then return a end end
    function Value.ValueExprSub:lower_c_simplify_binary_identity(a, b, ar, br) if is_raw(br, "0") then return a end end
    function Value.ValueExprMul:lower_c_simplify_binary_identity(a, b, ar, br) if is_raw(ar, "0") or is_raw(br, "0") then return int_const(self.ty, "0") end; if is_raw(ar, "1") then return b end; if is_raw(br, "1") then return a end end
    function Value.ValueExprDiv:lower_c_simplify_binary_identity(a, b, ar, br) if is_raw(br, "1") then return a end end
    function Value.ValueExprRem:lower_c_simplify_binary_identity(a, b, ar, br) if is_raw(br, "1") then return a end end
    function Core.BinaryOp:lower_c_fold_int(ty, av, bv) return nil end
    function Core.BinAdd:lower_c_fold_int(ty, av, bv) return int_const(ty, av + bv) end
    function Core.BinSub:lower_c_fold_int(ty, av, bv) return int_const(ty, av - bv) end
    function Core.BinMul:lower_c_fold_int(ty, av, bv) return int_const(ty, av * bv) end
    function Core.BinDiv:lower_c_fold_int(ty, av, bv) if bv ~= 0 then return int_const(ty, math.floor(av / bv)) end end
    function Core.BinRem:lower_c_fold_int(ty, av, bv) if bv ~= 0 then return int_const(ty, av % bv) end end
    function Value.ValueExprAdd:lower_c_simplify() local a,b=simplify_value_expr(self.a),simplify_value_expr(self.b); local ar,br=literal_int_raw(a),literal_int_raw(b); local r=self:lower_c_simplify_binary_identity(a,b,ar,br); if r then return r end; if ar and br then local av,bv=tonumber(ar),tonumber(br); if av and bv and av==math.floor(av) and bv==math.floor(bv) then local f=self:lower_c_arith_op():lower_c_fold_int(self.ty,av,bv); if f then return f end end end; return self:lower_c_rebuild(a,b) end
    function Value.ValueExprSub:lower_c_simplify() return Value.ValueExprAdd.lower_c_simplify(self) end
    function Value.ValueExprMul:lower_c_simplify() return Value.ValueExprAdd.lower_c_simplify(self) end
    function Value.ValueExprDiv:lower_c_simplify() return Value.ValueExprAdd.lower_c_simplify(self) end
    function Value.ValueExprRem:lower_c_simplify() return Value.ValueExprAdd.lower_c_simplify(self) end
    function Value.ValueExprBinary:lower_c_simplify() return Value.ValueExprBinary(self.op, simplify_value_expr(self.a), simplify_value_expr(self.b), self.ty, self.sem) end
    function Core.CmpOp:lower_c_eval_int(av, bv) return false end
    function Core.CmpEq:lower_c_eval_int(av, bv) return av == bv end
    function Core.CmpNe:lower_c_eval_int(av, bv) return av ~= bv end
    function Core.CmpLt:lower_c_eval_int(av, bv) return av < bv end
    function Core.CmpLe:lower_c_eval_int(av, bv) return av <= bv end
    function Core.CmpGt:lower_c_eval_int(av, bv) return av > bv end
    function Core.CmpGe:lower_c_eval_int(av, bv) return av >= bv end
    function Value.ValueExprCmp:lower_c_simplify() local a,b=simplify_value_expr(self.a),simplify_value_expr(self.b); local ar,br=literal_int_raw(a),literal_int_raw(b); if ar and br then local av,bv=tonumber(ar),tonumber(br); if av and bv then return Value.ValueExprConst(Code.CodeConstLiteral(Code.CodeTyBool8, Core.LitBool(self.op:lower_c_eval_int(av,bv)))) end end; return Value.ValueExprCmp(self.op,self.ty,a,b) end
    function Value.ValueExprSelect:lower_c_simplify() local cnd=simplify_value_expr(self.cond); local bv=literal_bool_value(cnd); if bv==true then return simplify_value_expr(self.t) end; if bv==false then return simplify_value_expr(self.f) end; return Value.ValueExprSelect(cnd, simplify_value_expr(self.t), simplify_value_expr(self.f)) end
    function Value.ValueExprAffine:lower_c_simplify() if self.affine.constant == "0" and #(self.affine.terms or {}) == 1 and self.affine.terms[1].coeff == "1" then return Value.ValueExprValue(self.affine.terms[1].value) end; return self end
    simplify_value_expr = function(expr) return expr:lower_c_simplify() end

    function Value.ValueExpr:lower_c_value(c_emission) error("lower_to_c: unsupported semantic ValueExpr " .. node_name(self), 3) end
    function Value.ValueExprConst:lower_c_value(c_emission) return const_atom(c_emission, self.const) end
    function Value.ValueExprValue:lower_c_value(c_emission) local ty=value_ty(c_emission,self.value); if ty==nil then error("lower_to_c: semantic expression references unknown value " .. self.value.text, 3) end; return atom(self.value), ty end
    function Value.ValueExprCast:lower_c_value(c_emission) local src,src_ty=lower_value_expr(c_emission,self.value); local dst=tmp(c_emission,"cast",self.to); assign(c_emission,dst,C.CBackendRCast(self.op,c_ty(c_emission,self.to),src)); return C.CBackendAtomLocal(dst),self.to end
    local function lower_binary_value(c_emission, expr, op, lane, index_ty)
        local lower = lane == nil and lower_value_expr or lower_value_expr_lane
        local a, aty = lower(c_emission, expr.a, lane, index_ty); local b, bty = lower(c_emission, expr.b, lane, index_ty)
        a = cast_to(c_emission, a, aty, expr.ty, lane == nil and "bin_lhs" or "vec_bin_lhs"); b = cast_to(c_emission, b, bty, expr.ty, lane == nil and "bin_rhs" or "vec_bin_rhs")
        local dst = tmp(c_emission, lane == nil and "bin" or "vec_bin", expr.ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, op, expr.ty, expr.sem), { a, b })
        return C.CBackendAtomLocal(dst), expr.ty
    end
    function Value.ValueExprAdd:lower_c_value(c_emission) return lower_binary_value(c_emission,self,Core.BinAdd) end
    function Value.ValueExprSub:lower_c_value(c_emission) return lower_binary_value(c_emission,self,Core.BinSub) end
    function Value.ValueExprMul:lower_c_value(c_emission) return lower_binary_value(c_emission,self,Core.BinMul) end
    function Value.ValueExprDiv:lower_c_value(c_emission) return lower_binary_value(c_emission,self,Core.BinDiv) end
    function Value.ValueExprRem:lower_c_value(c_emission) return lower_binary_value(c_emission,self,Core.BinRem) end
    function Value.ValueExprBinary:lower_c_value(c_emission) return lower_binary_value(c_emission,self,self.op) end
    function Value.ValueExprCmp:lower_c_value(c_emission) local a,aty=lower_value_expr(c_emission,self.a); local b,bty=lower_value_expr(c_emission,self.b); a=cast_to(c_emission,a,aty,self.ty,"cmp_lhs"); b=cast_to(c_emission,b,bty,self.ty,"cmp_rhs"); local dst=tmp(c_emission,"cmp",Code.CodeTyBool8); assign(c_emission,dst,C.CBackendRCompare(self.op,c_ty(c_emission,self.ty),a,b)); return C.CBackendAtomLocal(dst),Code.CodeTyBool8 end
    function Value.ValueExprSelect:lower_c_value(c_emission) local cnd=lower_value_expr(c_emission,self.cond); local t,tty=lower_value_expr(c_emission,self.t); local f,fty=lower_value_expr(c_emission,self.f); local ty=tty or fty; f=cast_to(c_emission,f,fty,ty,"sel_f"); t=cast_to(c_emission,t,tty,ty,"sel_t"); local dst=tmp(c_emission,"select",ty); assign(c_emission,dst,C.CBackendRSelect(c_ty(c_emission,ty),cnd,t,f)); return C.CBackendAtomLocal(dst),ty end
    function Value.ValueExprAffine:lower_c_value(c_emission) local ty=self.affine.ty; local acc,acc_ty=nil,nil; if self.affine.constant ~= "0" then acc,acc_ty=lower_value_expr(c_emission,Value.ValueExprConst(Code.CodeConstLiteral(ty,Core.LitInt(self.affine.constant)))) end; for _,term in ipairs(self.affine.terms or {}) do local tv,tty=lower_value_expr(c_emission,Value.ValueExprValue(term.value)); tv=cast_to(c_emission,tv,tty,ty,"affine_cast"); if term.coeff ~= "1" then local cv=C.CBackendAtomLiteral(c_ty(c_emission,ty),Core.LitInt(term.coeff)); local mul=tmp(c_emission,"affine_mul",ty); c_emission.stmts[#c_emission.stmts+1]=C.CBackendHelperCall(mul,binary_helper(c_emission,Core.BinMul,ty,self.affine.sem),{tv,cv}); tv=C.CBackendAtomLocal(mul) end; if acc==nil then acc,acc_ty=tv,ty else local sum=tmp(c_emission,"affine_add",ty); c_emission.stmts[#c_emission.stmts+1]=C.CBackendHelperCall(sum,binary_helper(c_emission,Core.BinAdd,ty,self.affine.sem),{acc,tv}); acc,acc_ty=C.CBackendAtomLocal(sum),ty end end; if acc==nil then return C.CBackendAtomLiteral(c_ty(c_emission,ty),Core.LitInt("0")),ty end; return acc,acc_ty end
    lower_value_expr = function(c_emission, expr) return simplify_value_expr(expr):lower_c_value(c_emission) end

    function Mem.MemAccessOp:lower_c_read_access(access) return nil end
    function Mem.MemLoad:lower_c_read_access(access) return access end
    function Mem.MemAtomicLoad:lower_c_read_access(access) return access end
    function Mem.MemAtomicRmw:lower_c_read_access(access) return access end
    function Mem.MemAtomicCas:lower_c_read_access(access) return access end

    function Mem.MemAccessOp:lower_c_write_access(access) return nil end
    function Mem.MemStore:lower_c_write_access(access) return access end
    function Mem.MemAtomicStore:lower_c_write_access(access) return access end
    function Mem.MemAtomicRmw:lower_c_write_access(access) return access end
    function Mem.MemAtomicCas:lower_c_write_access(access) return access end

    local function first_lane_access(c_emission, lane, selector)
        for _, aid in ipairs(lane.accesses or {}) do
            local access = c_emission.mem_projection:mem_access(aid)
            if access ~= nil then
                local selected_access = access.op[selector](access.op, access)
                if selected_access ~= nil then return selected_access, c_emission.mem_projection:backend_for_access(aid) end
            end
        end
        local aid = lane.accesses and lane.accesses[1]
        if aid ~= nil then return c_emission.mem_projection:mem_access(aid), c_emission.mem_projection:backend_for_access(aid) end
        return nil, nil
    end

    local function first_read_access(c_emission, lane)
        return first_lane_access(c_emission, lane, "lower_c_read_access")
    end

    local function first_write_access(c_emission, lane)
        return first_lane_access(c_emission, lane, "lower_c_write_access")
    end

    function Mem.MemBase:lower_c_base_atom(c_emission) error("lower_to_c: unsupported KernelLane base " .. node_name(self), 3) end
    function Mem.MemBaseValue:lower_c_base_atom(c_emission) return atom(self.value) end
    function Mem.MemBaseArgument:lower_c_base_atom(c_emission) return atom(self.value) end
    function Mem.MemBaseGlobal:lower_c_base_atom(c_emission) return C.CBackendAtomGlobal(C.CBackendGlobalId(self.global.text)) end
    function Mem.MemBaseData:lower_c_base_atom(c_emission) return C.CBackendAtomGlobal(C.CBackendGlobalId(self.data.text)) end
    function Mem.MemBaseProjection:lower_c_base_atom(c_emission)
        local b = self.base:lower_c_base_atom(c_emission)
        local zero = C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("0"))
        local dst = tmp(c_emission, "base_projection", Code.CodeTyDataPtr(nil))
        assign(c_emission, dst, C.CBackendRPtrOffset(b, zero, 1, self.byte_offset or 0))
        return C.CBackendAtomLocal(dst)
    end
    local function base_atom(c_emission, base) return base:lower_c_base_atom(c_emission) end

    local function address_index_atom(c_emission, index_expr)
        local idx, ity = lower_value_expr(c_emission, index_expr)
        idx = cast_to(c_emission, idx, ity, Code.CodeTyIndex, "index_cast")
        return idx
    end

    function Mem.MemIndex:lower_c_elem_size() return 1 end
    function Mem.MemIndex:lower_c_const_offset() return 0 end
    function Mem.MemIndexValue:lower_c_elem_size() return self.elem_size or 1 end
    function Mem.MemIndexValue:lower_c_const_offset() return self.const_offset or 0 end
    function Mem.MemIndexInduction:lower_c_elem_size() return self.elem_size or 1 end
    function Mem.MemIndexInduction:lower_c_const_offset() return self.const_offset or 0 end

    function Lower.LowerAddressLaneUse:lower_c_serves_lane(lane)
        return self.lane == lane.id
    end
    function Lower.LowerCarrierBlockParam:lower_c_matches_block(func, block)
        return self.block.func == func and self.block.block == block
    end
    function Lower.LowerAddressPlan:lower_c_serves_lane(lane)
        for _, use in ipairs(self.lanes or {}) do if use:lower_c_serves_lane(lane) then return true end end
        return false
    end
    function Lower.LowerCarrierPlan:lower_c_block_param_for(func, block)
        for _, param in ipairs(self.blocks or {}) do if param:lower_c_matches_block(func, block) then return param end end
        return nil
    end
    function Lower.LowerAddressBlockParam:lower_c_matches_block(func, block)
        return self.block.func == func and self.block.block == block
    end
    function Lower.LowerAddressPlan:lower_c_block_param_for(func, block)
        for _, param in ipairs(self.blocks or {}) do if param:lower_c_matches_block(func, block) then return param end end
        return nil
    end
    function Lower.LowerAddressStrategy:lower_c_address_place(plan, c_emission, lane, block)
        error("lower_to_c: unsupported LowerAddressStrategy " .. node_name(self), 2)
    end
    function Lower.LowerAddressReject:lower_c_address_place(plan, c_emission, lane, block)
        error("lower_to_c: rejected LowerAddressPlan " .. plan.address.text .. ": " .. self.reason, 2)
    end
    function Lower.LowerAddressCarryProjected:lower_c_address_place(plan, c_emission, lane, block)
        local param = plan:lower_c_block_param_for(c_emission.code_func.id, block)
        if param == nil then error("lower_to_c: carried LowerAddressPlan has no block param for current block " .. plan.address.text, 2) end
        return C.CBackendPlaceDeref(C.CBackendAtomLocal(param.param), c_ty(c_emission, plan.base.elem_ty), nil)
    end
    function Lower.LowerAddressPlan:lower_c_address_place(c_emission, lane, block)
        if not self:lower_c_serves_lane(lane) then return nil end
        return self.strategy:lower_c_address_place(self, c_emission, lane, block)
    end

    local function address_place_for_lane(c_emission, lane)
        local block_id = c_emission.current_code_block_id
        if block_id == nil then return nil end
        for _, plan in ipairs(c_emission.active_address_plans or {}) do
            local place = plan:lower_c_address_place(c_emission, lane, block_id)
            if place ~= nil then return place end
        end
        return nil
    end

    local function place_for_access(c_emission, lane, access, index_expr)
        local address_place = address_place_for_lane(c_emission, lane)
        if address_place ~= nil then return address_place end
        local index = access and access.index or nil
        local elem_size = index and index:lower_c_elem_size() or 1
        local const_offset = index and index:lower_c_const_offset() or 0
        local base = base_atom(c_emission, lane.base)
        local idx = address_index_atom(c_emission, index_expr)
        local base_place = C.CBackendPlaceDeref(base, c_ty(c_emission, lane.elem_ty), nil)
        if const_offset ~= 0 then
            local ptr = tmp(c_emission, "ptr_offset", Code.CodeTyDataPtr(lane.elem_ty))
            assign(c_emission, ptr, C.CBackendRPtrOffset(base, idx, elem_size, const_offset))
            return C.CBackendPlaceDeref(C.CBackendAtomLocal(ptr), c_ty(c_emission, lane.elem_ty), nil)
        end
        return C.CBackendPlaceIndex(base_place, idx, c_ty(c_emission, lane.elem_ty), elem_size)
    end

    local function place_for_read_lane(c_emission, lane, index_expr) return place_for_access(c_emission, lane, first_read_access(c_emission, lane), index_expr) end
    local function place_for_write_lane(c_emission, lane, index_expr) return place_for_access(c_emission, lane, first_write_access(c_emission, lane), index_expr) end

    local function kernel_value_atom(c_emission, kid)
        local mapped = c_emission.kernel_value_local[kid.text]
        if mapped ~= nil then return C.CBackendAtomLocal(mapped), c_emission.kernel_value_types[kid.text] end
        return C.CBackendAtomLocal(C.CBackendLocalId(sanitize(kid.text))), c_emission.kernel_value_types[kid.text]
    end

    local lower_kernel_expr
    function Kernel.KernelExpr:lower_c_kernel_expr(c_emission) error("lower_to_c: unsupported KernelExpr " .. node_name(self), 3) end
    function Kernel.KernelExprValue:lower_c_kernel_expr(c_emission) return atom(self.value), value_ty(c_emission, self.value) end
    function Kernel.KernelExprKernelValue:lower_c_kernel_expr(c_emission) return kernel_value_atom(c_emission, self.value) end
    function Kernel.KernelExprAlgebra:lower_c_kernel_expr(c_emission) return lower_value_expr(c_emission, self.expr) end
    function Kernel.KernelExprLaneLoad:lower_c_kernel_expr(c_emission)
        local dst = tmp(c_emission, "load", self.lane.elem_ty)
        local place = place_for_read_lane(c_emission, self.lane, self.index)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(dst, place)
        return C.CBackendAtomLocal(dst), self.lane.elem_ty
    end
    lower_kernel_expr = function(c_emission, expr) return expr:lower_c_kernel_expr(c_emission) end

    local function bind_kernel_value(c_emission, binding)
        local dst = c_emission.kernel_value_local[binding.id.text]
        if dst == nil then
            dst = C.CBackendLocalId(sanitize(binding.id.text))
            c_emission.kernel_value_local[binding.id.text] = dst
            add_local(c_emission, dst, binding.ty)
        end
        local src, sty = lower_kernel_expr(c_emission, binding.expr)
        src = cast_to(c_emission, src, sty, binding.ty, "kernel_bind_cast")
        assign(c_emission, dst, C.CBackendRAtom(src))
        c_emission.kernel_value_types[binding.id.text] = binding.ty
    end

    function Kernel.KernelEffect:lower_c_emit_effect(c_emission) error("lower_to_c: unsupported KernelEffect " .. node_name(self), 3) end
    function Kernel.KernelEffectStore:lower_c_emit_effect(c_emission)
        local value, vty = lower_kernel_expr(c_emission, self.value)
        value = cast_to(c_emission, value, vty, self.dst.elem_ty, "store_cast")
        local place = place_for_write_lane(c_emission, self.dst, self.index)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceStore(place, value)
    end
    function Kernel.KernelEffectFold:lower_c_emit_effect(c_emission) end
    local function emit_kernel_effect(c_emission, effect) return effect:lower_c_emit_effect(c_emission) end

    local function term_args(xs)
        local out = {}
        for i = 1, #(xs or {}) do out[i] = atom(xs[i]) end
        return out
    end
    function Code.CodeTermOp:lower_c_term(c_emission) error("lower_to_c: unsupported CodeTermOp " .. node_name(self), 2) end
    function Code.CodeTermJump:lower_c_term(c_emission) return C.CBackendGoto(clabel(self.dest), term_args(self.args)) end
    function Code.CodeTermBranch:lower_c_term(c_emission) return C.CBackendIfGoto(atom(self.cond), clabel(self.then_dest), term_args(self.then_args), clabel(self.else_dest), term_args(self.else_args)) end
    function Code.CodeTermSwitch:lower_c_term(c_emission) local cases={}; for i=1,#self.cases do cases[i]=C.CBackendSwitchCase(self.cases[i].literal, clabel(self.cases[i].dest), term_args(self.cases[i].args)) end; return C.CBackendSwitchGoto(atom(self.value), cases, clabel(self.default_dest), term_args(self.default_args)) end
    function Code.CodeTermVariantSwitch:lower_c_term(c_emission) local cases={}; for i=1,#self.cases do cases[i]=C.CBackendSwitchCase(Core.LitInt(tostring(self.cases[i].variant.tag_value)), clabel(self.cases[i].dest), term_args(self.cases[i].args)) end; return C.CBackendSwitchGoto(atom(self.tag), cases, clabel(self.default_dest), term_args(self.default_args)) end
    function Code.CodeTermReturn:lower_c_term(c_emission) return (#self.values == 0) and C.CBackendReturnVoid or C.CBackendReturn(atom(self.values[1])) end
    function Code.CodeTermTrap:lower_c_term(c_emission) return C.CBackendTrap end
    function Code.CodeTermUnreachable:lower_c_term(c_emission) return C.CBackendTrap end
    function Code.CodeTermOp:lower_c_jump_dest() return nil end
    function Code.CodeTermJump:lower_c_jump_dest() return self.dest end
    local function term_to_c(c_emission, term) return term.op:lower_c_term(c_emission) end

    local function graph_loop_by_id(graph)
        local out = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do for _, loop in ipairs(fg.loops or {}) do out[loop.id.text] = loop end end
        return out
    end

    local function edge_fact_by_key(flow)
        local out = {}
        for _, ef in ipairs(flow and flow.edges or {}) do out[ef.edge.from.block.text .. "\0" .. ef.edge.to.block.text] = ef end
        return out
    end

    function Kernel.KernelPlan:lower_c_index_plan(out) end
    function Kernel.KernelPlanned:lower_c_index_plan(out) out[self.id.text] = self end
    local function kernel_by_id(kernels)
        local out = {}
        for _, kp in ipairs(kernels and kernels.plans or {}) do kp:lower_c_index_plan(out) end
        return out
    end

    function Schedule.KernelSchedule:lower_c_index_schedule(out) end
    function Schedule.SchedulePlanned:lower_c_index_schedule(out) out[self.id.text] = self end
    local function schedule_by_id(schedules)
        local out = {}
        for _, sp in ipairs(schedules and schedules.schedules or {}) do sp:lower_c_index_schedule(out) end
        return out
    end

    local function edge_args(c_emission, edge_fact)
        local args = {}
        for _, arg in ipairs(edge_fact and edge_fact.args or {}) do args[#args + 1] = atom(arg.src) end
        return args
    end

    local function code_block_by_id(func)
        local out = {}; for _, b in ipairs(func.blocks or {}) do out[b.id.text] = b end; return out
    end

    local function c_block_params(c_emission, code_block)
        local params = {}
        for i, p in ipairs(code_block.params or {}) do params[i] = C.CBackendBlockParam(cid(p.value), c_ty(c_emission, p.ty)) end
        return params
    end

    local semantic_fragment_prelude

    local function emit_closed_form_fragment(c_emission, graph, flow, kernels, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        if kplan == nil then error("lower_to_c: closed-form strategy references missing kernel " .. fragment.strategy.kernel.text, 2) end
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil or #(loop.exits or {}) ~= 1 then error("lower_to_c: closed-form fragment requires one loop exit", 2) end
        local exit = loop.exits[1]
        local edge_facts = edge_fact_by_key(flow)
        local jump_dest = exit.to.block
        local jump_fact = edge_facts[exit.from.block.text .. "\0" .. exit.to.block.text]
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if block.id == exit.to.block and block.term.op:lower_c_jump_dest() ~= nil then
                jump_dest = block.term.op:lower_c_jump_dest()
                jump_fact = edge_facts[block.id.text .. "\0" .. block.term.op.dest.text] or jump_fact
            end
        end
        c_emission.stmts = { C.CBackendComment("semantic closed-form " .. tostring(fragment.strategy.fact.id and fragment.strategy.fact.id.text or fragment.id.text)) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, loop.header.block) end
        local result = lower_value_expr(c_emission, fragment.strategy.fact.expr)
        local args = {}
        for i, arg in ipairs(jump_fact and jump_fact.args or {}) do
            args[i] = (arg.src == fragment.strategy.fact.reduction.accumulator) and result or atom(arg.src)
        end
        local header = c_emission.block_by_id[loop.header.block.text]
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, header), c_emission.stmts, C.CBackendGoto(clabel(jump_dest), args))
    end

    local function loop_partition(c_emission, graph, flow, kplan)
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        if loop == nil or #(loop.latches or {}) ~= 1 or #(loop.exits or {}) ~= 1 then error("lower_to_c: kernel fragment requires one loop/latch/exit", 2) end
        local body_set = {}; for _, gb in ipairs(loop.body or {}) do body_set[gb.block.text] = true end
        local edge_facts = edge_fact_by_key(flow)
        local exit_edge, latch_edge = loop.exits[1], loop.latches[1]
        local body_successor = nil
        for _, fg in ipairs(graph.funcs or {}) do
            if fg.func == loop.func then
                for _, edge in ipairs(fg.edges or {}) do
                    if edge.from.block == loop.header.block and body_set[edge.to.block.text] and edge.to.block ~= loop.header.block then body_successor = edge.to.block end
                end
            end
        end
        if body_successor == nil then error("lower_to_c: kernel cannot find header body successor", 2) end
        local loop_fact = nil
        for _, lf in ipairs(flow.loops or {}) do if lf.loop == loop.id then loop_fact = lf end end
        local cond = loop_fact and loop_fact.exits and loop_fact.exits[1] and loop_fact.exits[1].condition
        if cond == nil then error("lower_to_c: kernel loop exit has no condition", 2) end
        return loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, cond, loop_fact
    end

    function Kernel.KernelEffect:lower_c_place_effect(c_emission, effects_by_block) error("lower_to_c: unsupported KernelEffect in planned kernel", 2) end
    function Kernel.KernelEffectFold:lower_c_place_effect(c_emission, effects_by_block) end
    function Kernel.KernelEffectStore:lower_c_place_effect(c_emission, effects_by_block)
        local access = first_write_access(c_emission, self.dst)
        local block = access and access.block and access.block.block
        if block ~= nil then effects_by_block[block.text] = effects_by_block[block.text] or {}; effects_by_block[block.text][#effects_by_block[block.text] + 1] = self end
    end
    local function place_bindings_effects(c_emission, kplan)
        local bindings_by_block, effects_by_block = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = c_emission.kernel_value_block[binding.id.text]
            if block ~= nil then bindings_by_block[block.text] = bindings_by_block[block.text] or {}; bindings_by_block[block.text][#bindings_by_block[block.text] + 1] = binding end
        end
        for _, effect in ipairs(kplan.body.effects or {}) do effect:lower_c_place_effect(c_emission, effects_by_block) end
        return bindings_by_block, effects_by_block
    end

    function Lower.LowerCarrierStrategy:lower_c_is_carry_carrier() return false end
    function Lower.LowerCarrierCarry:lower_c_is_carry_carrier() return true end
    function Lower.LowerAddressPlan:lower_c_is_active_for_kernel(kplan)
        for _, lane in ipairs(kplan.body and kplan.body.lanes or {}) do if self:lower_c_serves_lane(lane) then return true end end
        return false
    end

    local function active_addresses_for_kernel(c_emission, kplan)
        local active = {}
        for _, plan in ipairs(c_emission.address_plans or {}) do
            if plan:lower_c_is_active_for_kernel(kplan) then active[#active + 1] = plan end
        end
        return active
    end

    local function emit_scalar_kernel_fragment(c_emission, graph, flow, kernels, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        if kplan == nil then error("lower_to_c: kernel strategy references missing kernel " .. fragment.strategy.kernel.text, 2) end
        local loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, cond = loop_partition(c_emission, graph, flow, kplan)
        local previous_active_addresses = c_emission.active_address_plans
        c_emission.active_address_plans = active_addresses_for_kernel(c_emission, kplan)
        local bindings_by_block, effects_by_block = place_bindings_effects(c_emission, kplan)
        local header_block = c_emission.block_by_id[loop.header.block.text]
        c_emission.current_code_block_id = loop.header.block
        c_emission.stmts = { C.CBackendComment("semantic scalar kernel " .. kplan.id.text) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, loop.header.block) end
        for _, b in ipairs(bindings_by_block[loop.header.block.text] or {}) do bind_kernel_value(c_emission, b) end
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, header_block), c_emission.stmts,
            C.CBackendIfGoto(atom(cond), clabel(body_successor), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text]), clabel(exit_edge.to.block), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text])))
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= loop.header.block then
                c_emission.current_code_block_id = block.id
                c_emission.stmts = { C.CBackendComment("semantic scalar kernel body " .. kplan.id.text) }
                if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, block.id) end
                for _, b in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(c_emission, b) end
                for _, e in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(c_emission, e) end
                local term
                if block.id == latch_edge.from.block then
                    term = C.CBackendGoto(clabel(loop.header.block), edge_args(c_emission, edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end end end
                    if next_edge == nil then error("lower_to_c: scalar kernel body block has no in-loop successor", 2) end
                    term = C.CBackendGoto(clabel(next_edge.to.block), edge_args(c_emission, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
                c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(block.id), c_block_params(c_emission, block), c_emission.stmts, term)
            end
        end
        c_emission.current_code_block_id = nil
        c_emission.active_address_plans = previous_active_addresses
    end

    local function value_expr_add_lane(c_emission, expr, lane, ty)
        if lane == 0 then return expr end
        return Value.ValueExprAdd(expr, Value.ValueExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(lane)))), ty, Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount))
    end

    local function vector_lane_place_for_access(c_emission, lane_desc, access, lane, counter_ty)
        local idx = atom(c_emission.vector_counter)
        if lane ~= 0 then
            local dst = tmp(c_emission, "vec_lane_index", counter_ty)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, Core.BinAdd, counter_ty, nil), { atom(c_emission.vector_counter), C.CBackendAtomLiteral(c_ty(c_emission, counter_ty), Core.LitInt(tostring(lane))) })
            idx = C.CBackendAtomLocal(dst)
        end
        local index = access and access.index or nil
        local elem_size = index and index:lower_c_elem_size() or 1
        local const_offset = index and index:lower_c_const_offset() or 0
        local base = base_atom(c_emission, lane_desc.base)
        if const_offset ~= 0 then
            local ptr = tmp(c_emission, "vec_lane_ptr", Code.CodeTyDataPtr(lane_desc.elem_ty))
            assign(c_emission, ptr, C.CBackendRPtrOffset(base, idx, elem_size, const_offset))
            return C.CBackendPlaceDeref(C.CBackendAtomLocal(ptr), c_ty(c_emission, lane_desc.elem_ty), nil)
        end
        return C.CBackendPlaceIndex(C.CBackendPlaceDeref(base, c_ty(c_emission, lane_desc.elem_ty), nil), idx, c_ty(c_emission, lane_desc.elem_ty), elem_size)
    end

    local function vector_read_lane_place(c_emission, lane_desc, lane, counter_ty)
        return vector_lane_place_for_access(c_emission, lane_desc, first_read_access(c_emission, lane_desc), lane, counter_ty)
    end

    local function vector_write_lane_place(c_emission, lane_desc, lane, counter_ty)
        return vector_lane_place_for_access(c_emission, lane_desc, first_write_access(c_emission, lane_desc), lane, counter_ty)
    end

    function Value.ValueExpr:lower_c_value_lane(c_emission, lane, index_ty) return self:lower_c_value(c_emission) end
    function Value.ValueExprValue:lower_c_value_lane(c_emission, lane, index_ty)
        local cached = c_emission.lane_value_by_code and c_emission.lane_value_by_code[self.value.text]
        if cached ~= nil then return cached.atom, cached.ty end
        return self:lower_c_value(c_emission)
    end
    function Value.ValueExprConst:lower_c_value_lane(c_emission, lane, index_ty) return const_atom(c_emission, self.const) end
    function Value.ValueExprCast:lower_c_value_lane(c_emission, lane, index_ty) local src,src_ty=lower_value_expr_lane(c_emission,self.value,lane,index_ty); local dst=tmp(c_emission,"vec_cast",self.to); assign(c_emission,dst,C.CBackendRCast(self.op,c_ty(c_emission,self.to),src)); return C.CBackendAtomLocal(dst),self.to end
    function Value.ValueExprAdd:lower_c_value_lane(c_emission, lane, index_ty) return lower_binary_value(c_emission,self,Core.BinAdd,lane,index_ty) end
    function Value.ValueExprSub:lower_c_value_lane(c_emission, lane, index_ty) return lower_binary_value(c_emission,self,Core.BinSub,lane,index_ty) end
    function Value.ValueExprMul:lower_c_value_lane(c_emission, lane, index_ty) return lower_binary_value(c_emission,self,Core.BinMul,lane,index_ty) end
    function Value.ValueExprDiv:lower_c_value_lane(c_emission, lane, index_ty) return lower_binary_value(c_emission,self,Core.BinDiv,lane,index_ty) end
    function Value.ValueExprRem:lower_c_value_lane(c_emission, lane, index_ty) return lower_binary_value(c_emission,self,Core.BinRem,lane,index_ty) end
    function Value.ValueExprBinary:lower_c_value_lane(c_emission, lane, index_ty) return lower_binary_value(c_emission,self,self.op,lane,index_ty) end
    function Value.ValueExprCmp:lower_c_value_lane(c_emission, lane, index_ty) local a,aty=lower_value_expr_lane(c_emission,self.a,lane,index_ty); local b,bty=lower_value_expr_lane(c_emission,self.b,lane,index_ty); a=cast_to(c_emission,a,aty,self.ty,"vec_cmp_lhs"); b=cast_to(c_emission,b,bty,self.ty,"vec_cmp_rhs"); local dst=tmp(c_emission,"vec_cmp",Code.CodeTyBool8); assign(c_emission,dst,C.CBackendRCompare(self.op,c_ty(c_emission,self.ty),a,b)); return C.CBackendAtomLocal(dst),Code.CodeTyBool8 end
    function Value.ValueExprSelect:lower_c_value_lane(c_emission, lane, index_ty) local cnd=lower_value_expr_lane(c_emission,self.cond,lane,index_ty); local t,tty=lower_value_expr_lane(c_emission,self.t,lane,index_ty); local f,fty=lower_value_expr_lane(c_emission,self.f,lane,index_ty); local ty=tty or fty; t=cast_to(c_emission,t,tty,ty,"vec_sel_t"); f=cast_to(c_emission,f,fty,ty,"vec_sel_f"); local dst=tmp(c_emission,"vec_select",ty); assign(c_emission,dst,C.CBackendRSelect(c_ty(c_emission,ty),cnd,t,f)); return C.CBackendAtomLocal(dst),ty end
    function Value.ValueExprAffine:lower_c_value_lane(c_emission, lane, index_ty) local ty=self.affine.ty; local acc,acc_ty=nil,nil; if self.affine.constant ~= "0" then acc,acc_ty=const_atom(c_emission,Code.CodeConstLiteral(ty,Core.LitInt(self.affine.constant))) end; for _,term in ipairs(self.affine.terms or {}) do local tv,tty=lower_value_expr_lane(c_emission,Value.ValueExprValue(term.value),lane,index_ty); tv=cast_to(c_emission,tv,tty,ty,"vec_affine_cast"); if term.coeff ~= "1" then local cv=C.CBackendAtomLiteral(c_ty(c_emission,ty),Core.LitInt(term.coeff)); local mul=tmp(c_emission,"vec_affine_mul",ty); c_emission.stmts[#c_emission.stmts+1]=C.CBackendHelperCall(mul,binary_helper(c_emission,Core.BinMul,ty,self.affine.sem),{tv,cv}); tv=C.CBackendAtomLocal(mul) end; if acc==nil then acc,acc_ty=tv,ty else local sum=tmp(c_emission,"vec_affine_add",ty); c_emission.stmts[#c_emission.stmts+1]=C.CBackendHelperCall(sum,binary_helper(c_emission,Core.BinAdd,ty,self.affine.sem),{acc,tv}); acc,acc_ty=C.CBackendAtomLocal(sum),ty end end; if acc==nil then return C.CBackendAtomLiteral(c_ty(c_emission,ty),Core.LitInt("0")),ty end; return acc,acc_ty end
    lower_value_expr_lane = function(c_emission, expr, lane, index_ty) return expr:lower_c_value_lane(c_emission, lane, index_ty) end

    function Kernel.KernelExpr:lower_c_kernel_expr_lane(c_emission, lane, index_ty) error("lower_to_c: unsupported vector KernelExpr " .. node_name(self), 3) end
    function Kernel.KernelExprValue:lower_c_kernel_expr_lane(c_emission, lane, index_ty) local cached=c_emission.lane_value_by_code and c_emission.lane_value_by_code[self.value.text]; if cached ~= nil then return cached.atom,cached.ty end; return atom(self.value), value_ty(c_emission,self.value) end
    function Kernel.KernelExprKernelValue:lower_c_kernel_expr_lane(c_emission, lane, index_ty)
        local cached = c_emission.lane_value_by_kernel and c_emission.lane_value_by_kernel[self.value.text]
        if cached ~= nil then return cached.atom, cached.ty end
        local binding = c_emission.kernel_binding_by_id[self.value.text]
        if binding == nil then return kernel_value_atom(c_emission, self.value) end
        local v, ty = lower_kernel_expr_lane(c_emission, binding.expr, lane, index_ty)
        c_emission.lane_value_by_kernel[self.value.text] = { atom = v, ty = ty }
        local code_id = c_emission.kernel_value_code_id and c_emission.kernel_value_code_id[self.value.text]
        if code_id ~= nil then c_emission.lane_value_by_code[code_id.text] = { atom = v, ty = ty } end
        return v, ty
    end
    function Kernel.KernelExprAlgebra:lower_c_kernel_expr_lane(c_emission, lane, index_ty) return lower_value_expr_lane(c_emission, self.expr, lane, index_ty) end
    function Kernel.KernelExprLaneLoad:lower_c_kernel_expr_lane(c_emission, lane, index_ty) local dst=tmp(c_emission,"vec_lane_load",self.lane.elem_ty); local place=vector_read_lane_place(c_emission,self.lane,lane,index_ty); c_emission.stmts[#c_emission.stmts+1]=C.CBackendPlaceLoad(dst,place); return C.CBackendAtomLocal(dst),self.lane.elem_ty end
    lower_kernel_expr_lane = function(c_emission, expr, lane, index_ty) return expr:lower_c_kernel_expr_lane(c_emission, lane, index_ty) end

    function Kernel.KernelEffect:lower_c_emit_vector_lane(c_emission, lane, index_ty) end
    function Kernel.KernelEffectStore:lower_c_emit_vector_lane(c_emission, lane, index_ty)
        c_emission.lane_value_by_code = {}
        c_emission.lane_value_by_kernel = {}
        for _, binding in ipairs(c_emission.current_kernel_bindings or {}) do lower_kernel_expr_lane(c_emission, Kernel.KernelExprKernelValue(binding.id), lane, index_ty) end
        local value, vty = lower_kernel_expr_lane(c_emission, self.value, lane, index_ty)
        value = cast_to(c_emission, value, vty, self.dst.elem_ty, "vec_store_cast")
        local place = vector_write_lane_place(c_emission, self.dst, lane, index_ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceStore(place, value)
    end
    local function emit_vector_lane_effect(c_emission, effect, lane, index_ty) return effect:lower_c_emit_vector_lane(c_emission, lane, index_ty) end

    function Schedule.ScheduleForm:lower_c_vector_lanes() return nil end
    function Schedule.ScheduleVector:lower_c_vector_lanes() return self.lanes:lower_c_lane_count() end
    function Schedule.LaneShape:lower_c_lane_count() return nil end
    function Schedule.LaneVector:lower_c_lane_count() return self.lanes end

    local function emit_vector_kernel_fragment(c_emission, graph, flow, kernels, schedules, fragment)
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        local sched = schedule_by_id(schedules)[fragment.strategy.schedule.text]
        if kplan == nil or sched == nil or sched.form:lower_c_vector_lanes() == nil then error("lower_to_c: vector kernel strategy requires ScheduleVector", 2) end
        local lanes = sched.form:lower_c_vector_lanes()
        local loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, scalar_cond, loop_fact = loop_partition(c_emission, graph, flow, kplan)
        if loop_fact == nil or loop_fact.counted == nil or kplan.body.domain.counter == nil then error("lower_to_c: vector kernel requires counted loop", 2) end
        c_emission.current_kernel_bindings = kplan.body.bindings or {}
        for _, binding in ipairs(kplan.body.bindings or {}) do c_emission.kernel_binding_by_id[binding.id.text] = binding end
        local counter = kplan.body.domain.counter
        c_emission.vector_counter = counter
        local counter_ty = value_ty(c_emission, counter) or Code.CodeTyIndex
        local vector_label = C.CBackendLabel(clabel(loop.header.block).text .. "_semantic_vector")
        local tail_label = C.CBackendLabel(clabel(loop.header.block).text .. "_semantic_tail")
        local next_i = C.CBackendLocalId("semantic_vec_next_i_" .. sanitize(loop.id.text))
        add_local(c_emission, next_i, counter_ty)
        local ok = C.CBackendLocalId("semantic_vec_ok_" .. sanitize(loop.id.text))
        add_local(c_emission, ok, Code.CodeTyBool8)

        c_emission.stmts = { C.CBackendComment("semantic vector kernel dispatch " .. kplan.id.text) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, loop.header.block) end
        for _, binding in ipairs(kplan.body.bindings or {}) do
            local block = c_emission.kernel_value_block and c_emission.kernel_value_block[binding.id.text]
            if block == loop.header.block then bind_kernel_value(c_emission, binding) end
        end
        local lane_atom = C.CBackendAtomLiteral(c_ty(c_emission, counter_ty), Core.LitInt(tostring(lanes)))
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(next_i, binary_helper(c_emission, Core.BinAdd, counter_ty, nil), { atom(counter), lane_atom })
        local stop = atom(loop_fact.counted.stop)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(ok, C.CBackendRCompare(Core.CmpLe, c_ty(c_emission, counter_ty), C.CBackendAtomLocal(next_i), stop))
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, c_emission.block_by_id[loop.header.block.text]), c_emission.stmts,
            C.CBackendIfGoto(C.CBackendAtomLocal(ok), vector_label, {}, tail_label, {}))

        c_emission.stmts = { C.CBackendComment("semantic vector main loop lanes=" .. tostring(lanes)) }
        for _, effect in ipairs(kplan.body.effects or {}) do for lane = 0, lanes - 1 do emit_vector_lane_effect(c_emission, effect, lane, counter_ty) end end
        local latch_fact = edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]
        local jump_args = {}
        for _, arg in ipairs(latch_fact and latch_fact.args or {}) do jump_args[#jump_args + 1] = (arg.dst_param == counter) and C.CBackendAtomLocal(next_i) or atom(arg.dst_param) end
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(vector_label, {}, c_emission.stmts, C.CBackendGoto(clabel(loop.header.block), jump_args))

        c_emission.stmts = { C.CBackendComment("semantic vector scalar tail") }
        c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(tail_label, {}, c_emission.stmts,
            C.CBackendIfGoto(atom(scalar_cond), clabel(exit_edge.to.block), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text]), clabel(body_successor), edge_args(c_emission, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text])))

        local bindings_by_block, effects_by_block = place_bindings_effects(c_emission, kplan)
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= loop.header.block then
                c_emission.stmts = { C.CBackendComment("semantic vector scalar-tail body " .. kplan.id.text) }
                if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, block.id) end
                for _, b in ipairs(bindings_by_block[block.id.text] or {}) do bind_kernel_value(c_emission, b) end
                for _, e in ipairs(effects_by_block[block.id.text] or {}) do emit_kernel_effect(c_emission, e) end
                local term
                if block.id == latch_edge.from.block then
                    term = C.CBackendGoto(clabel(loop.header.block), edge_args(c_emission, latch_fact))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end end end
                    if next_edge == nil then error("lower_to_c: vector tail body block has no in-loop successor", 2) end
                    term = C.CBackendGoto(clabel(next_edge.to.block), edge_args(c_emission, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                end
                c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(block.id), c_block_params(c_emission, block), c_emission.stmts, term)
            end
        end
    end

    function Lower.LowerCover:lower_c_cover_blocks(func, graph_loops, add) end
    function Lower.LowerCoverFunction:lower_c_cover_blocks(func, graph_loops, add) for _, b in ipairs(func.blocks or {}) do add(b) end end
    function Lower.LowerCoverBlock:lower_c_cover_blocks(func, graph_loops, add) for _, b in ipairs(func.blocks or {}) do if b.id == self.block then add(b) end end end
    function Lower.LowerCoverLoop:lower_c_cover_blocks(func, graph_loops, add) local loop=graph_loops[self.loop.text]; local body={}; for _,gb in ipairs(loop and loop.body or {}) do body[gb.block.text]=true end; for _,b in ipairs(func.blocks or {}) do if body[b.id.text] then add(b) end end end
    function Lower.LowerCoverBlockRange:lower_c_cover_blocks(func, graph_loops, add) local active=false; for _,b in ipairs(func.blocks or {}) do if b.id == self.entry then active=true end; if active then add(b) end; if b.id == self.exit then break end end end
    local function cover_blocks(fragment, func, graph_loops)
        local out, set = {}, {}
        local function add(block) if block and not set[block.id.text] then set[block.id.text] = true; out[#out + 1] = block end end
        fragment.cover:lower_c_cover_blocks(func, graph_loops, add)
        return out, set
    end

    semantic_fragment_prelude = function(c_emission, graph, fragment, only_block)
        local _, covered = cover_blocks(fragment, c_emission.code_func, graph_loop_by_id(graph))
        local aliases = {}
        local components = {}
        local emitted = {}

        local function ref(id, ty)
            return { atom = atom(id), ty = ty or value_ty(c_emission, id) }
        end
        local function emit_assign_once(dst, src)
            if dst == nil or src == nil or emitted[dst.text] then return end
            emitted[dst.text] = true
            note_value(c_emission, dst, src.ty)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(cid(dst), C.CBackendRAtom(src.atom))
        end
        local function resolve_view(id)
            local seen = {}
            while id ~= nil and aliases[id.text] ~= nil and not seen[id.text] do
                seen[id.text] = true
                id = aliases[id.text]
            end
            return id
        end
        local function component(id, field)
            id = resolve_view(id)
            local comp = id and components[id.text] or nil
            return comp and comp[field] or nil
        end
        local function emit_field_load(dst, view, field, ty)
            if dst == nil or view == nil or emitted[dst.text] then return end
            emitted[dst.text] = true
            note_value(c_emission, dst, ty)
            local vty = view_type(c_emission, view)
            if vty == nil then error("lower_to_c: semantic descriptor projection references unknown value " .. tostring(view.text), 3) end
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(cid(dst), C.CBackendPlaceField(C.CBackendPlaceLocal(cid(view), c_ty(c_emission, vty)), C.CBackendName(field), c_ty(c_emission, ty), 0, nil, nil))
        end

        function Code.CodeInstOp:lower_c_descriptor_collect() end
        function Code.CodeInstViewMake:lower_c_descriptor_collect()
            note_value(c_emission, self.dst, Code.CodeTyView(self.elem_ty))
            components[self.dst.text] = { data = ref(self.data, Code.CodeTyDataPtr(self.elem_ty)), len = ref(self.len, Code.CodeTyIndex), stride = ref(self.stride, Code.CodeTyIndex) }
        end
        function Code.CodeInstSliceMake:lower_c_descriptor_collect()
            note_value(c_emission, self.dst, Code.CodeTySlice(self.elem_ty))
            components[self.dst.text] = { data = ref(self.data, Code.CodeTyDataPtr(self.elem_ty)), len = ref(self.len, Code.CodeTyIndex) }
        end
        function Code.CodeInstByteSpanMake:lower_c_descriptor_collect()
            note_value(c_emission, self.dst, Code.CodeTyByteSpan)
            components[self.dst.text] = { data = ref(self.data, Code.CodeTyDataPtr(byte_ty())), len = ref(self.len, Code.CodeTyIndex) }
        end
        function Code.CodeInstAlias:lower_c_descriptor_collect()
            local ty = value_ty(c_emission, self.dst)
            if ty == nil or not ty:lower_c_is_descriptor_like() then return end
            local src = resolve_view(self.src)
            if src ~= nil then aliases[self.dst.text] = src end
            if src ~= nil and components[src.text] ~= nil then components[self.dst.text] = components[src.text] end
        end
        function Code.CodeInstOp:lower_c_descriptor_emit() end
        function Code.CodeInstViewData:lower_c_descriptor_emit() local src = component(self.view, "data"); if src ~= nil then emit_assign_once(self.dst, src) else emit_field_load(self.dst, resolve_view(self.view), "data", view_data_type(c_emission, self.view)) end end
        function Code.CodeInstViewLen:lower_c_descriptor_emit() local src = component(self.view, "len"); if src ~= nil then emit_assign_once(self.dst, src) else emit_field_load(self.dst, resolve_view(self.view), "len", Code.CodeTyIndex) end end
        function Code.CodeInstViewStride:lower_c_descriptor_emit() local src = component(self.view, "stride"); if src ~= nil then emit_assign_once(self.dst, src) else emit_field_load(self.dst, resolve_view(self.view), "stride", Code.CodeTyIndex) end end
        function Code.CodeInstSliceData:lower_c_descriptor_emit() local src = component(self.slice, "data"); if src ~= nil then emit_assign_once(self.dst, src) else emit_field_load(self.dst, resolve_view(self.slice), "data", slice_data_type(c_emission, self.slice)) end end
        function Code.CodeInstSliceLen:lower_c_descriptor_emit() local src = component(self.slice, "len"); if src ~= nil then emit_assign_once(self.dst, src) else emit_field_load(self.dst, resolve_view(self.slice), "len", Code.CodeTyIndex) end end
        function Code.CodeInstByteSpanData:lower_c_descriptor_emit() local src = component(self.span, "data"); if src ~= nil then emit_assign_once(self.dst, src) else emit_field_load(self.dst, resolve_view(self.span), "data", Code.CodeTyDataPtr(byte_ty())) end end
        function Code.CodeInstByteSpanLen:lower_c_descriptor_emit() local src = component(self.span, "len"); if src ~= nil then emit_assign_once(self.dst, src) else emit_field_load(self.dst, resolve_view(self.span), "len", Code.CodeTyIndex) end end

        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if covered[block.id.text] then for _, inst in ipairs(block.insts or {}) do inst.op:lower_c_descriptor_collect() end end
        end

        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if covered[block.id.text] and (only_block == nil or only_block == block.id) then for _, inst in ipairs(block.insts or {}) do inst.op:lower_c_descriptor_emit() end end
        end
    end

    local function ordered_fragments_for_func(func, func_plan, graph_loops)
        local ordered, emitted = {}, {}
        for _, block in ipairs(func.blocks or {}) do
            if not emitted[block.id.text] then
                local chosen = nil
                for _, fragment in ipairs(func_plan.fragments or {}) do
                    local _, set = cover_blocks(fragment, func, graph_loops)
                    if set[block.id.text] then chosen = fragment; break end
                end
                if chosen then
                    ordered[#ordered + 1] = chosen
                    local _, set = cover_blocks(chosen, func, graph_loops)
                    for key in pairs(set) do emitted[key] = true end
                end
            end
        end
        return ordered
    end

    function Lower.LowerStrategy:lower_c_is_semantic_strategy() return false end
    function Lower.LowerStrategyKernel:lower_c_is_semantic_strategy() return true end
    function Lower.LowerStrategyClosedForm:lower_c_is_semantic_strategy() return true end
    local function semantic_strategy(fragment) return fragment.strategy:lower_c_is_semantic_strategy() end

    local function lower_emit_candidate(fragment, schedules_by_id)
        return fragment.strategy:lower_emit_candidate(fragment.strategy:lower_emit_schedule(schedules_by_id))
    end

    function Lower.LowerStrategy:lower_emit_schedule(schedules_by_id) return nil end
    function Lower.LowerStrategyKernel:lower_emit_schedule(schedules_by_id)
        return schedules_by_id and schedules_by_id[self.schedule.text] or nil
    end
    function Lower.LowerStrategy:lower_emit_missing_schedule_reason() return "" end
    function Lower.LowerStrategyKernel:lower_emit_missing_schedule_reason()
        return "kernel strategy references missing schedule " .. self.schedule.text
    end

    local function baseline_block_by_label(blocks)
        local out = {}
        for _, block in ipairs(blocks or {}) do out[block.label.text] = block end
        return out
    end

    function Lower.LowerEmitSelection:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: unsupported lower emission selection", 2)
    end

    function Lower.LowerEmitCode:emit_to_c(c_emission, fragment_emit)
        local baseline_blocks = baseline_block_by_label(fragment_emit.baseline_blocks)
        local graph_loops = graph_loop_by_id(fragment_emit.graph)
        for _, b in ipairs(cover_blocks(fragment_emit.fragment, fragment_emit.code_func, graph_loops)) do
            c_emission.blocks[#c_emission.blocks + 1] = baseline_blocks[clabel(b.id).text]
        end
    end

    function Lower.LowerEmitClosedForm:emit_to_c(c_emission, fragment_emit)
        emit_closed_form_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.fragment)
    end

    function Lower.LowerEmitScalarKernel:emit_to_c(c_emission, fragment_emit)
        emit_scalar_kernel_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.fragment)
    end

    function Lower.LowerEmitVectorKernel:emit_to_c(c_emission, fragment_emit)
        emit_vector_kernel_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.schedules, fragment_emit.fragment)
    end

    function Lower.LowerEmitMissingSchedule:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: " .. tostring(self.reason), 2)
    end

    function Lower.LowerEmitUnsupported:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: " .. tostring(self.reason), 2)
    end

    local function prepare_func_emission(c_emission, code_func, c_func)
        c_emission.code_func = code_func
        c_emission.func = c_func
        c_emission.blocks = {}
        c_emission.block_by_id = code_block_by_id(code_func)
        c_emission.value_types = {}
        c_emission.kernel_value_local = {}
        c_emission.kernel_value_types = {}
        c_emission.kernel_value_block = {}
        c_emission.kernel_value_code_id = {}
        c_emission.kernel_binding_by_id = {}
        c_emission.const_by_value = {}
        c_emission.local_seen = {}
        for _, p in ipairs(c_func.params or {}) do c_emission.local_seen[p.id.text] = true end
        for _, l in ipairs(c_func.locals or {}) do c_emission.local_seen[l.id.text] = true end
        local function record_dst(block, dst, ty)
            if dst ~= nil and ty ~= nil then
                note_value(c_emission, dst, ty)
                local kid = Kernel.KernelValueId("kval:" .. dst.text)
                c_emission.kernel_value_local[kid.text] = cid(dst)
                c_emission.kernel_value_types[kid.text] = ty
                c_emission.kernel_value_block[kid.text] = block.id
                c_emission.kernel_value_code_id[kid.text] = dst
            end
        end
        function Code.CodeInstOp:lower_c_note_dst(block) end
        function Code.CodeInstConst:lower_c_note_dst(block) c_emission.const_by_value[self.dst.text] = self.const; record_dst(block, self.dst, self.const.ty) end
        function Code.CodeInstAlias:lower_c_note_dst(block) record_dst(block, self.dst, self.ty) end
        function Code.CodeInstUnary:lower_c_note_dst(block) record_dst(block, self.dst, self.ty) end
        function Code.CodeInstBinary:lower_c_note_dst(block) record_dst(block, self.dst, self.ty) end
        function Code.CodeInstFloatBinary:lower_c_note_dst(block) record_dst(block, self.dst, self.ty) end
        function Code.CodeInstSelect:lower_c_note_dst(block) record_dst(block, self.dst, self.ty) end
        function Code.CodeInstCompare:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyBool8) end
        function Code.CodeInstCast:lower_c_note_dst(block) record_dst(block, self.dst, self.to) end
        function Code.CodeInstAddrOf:lower_c_note_dst(block) record_dst(block, self.dst, self.ptr_ty) end
        function Code.CodeInstGlobalRef:lower_c_note_dst(block) record_dst(block, self.dst, self.ptr_ty) end
        function Code.CodeInstPtrOffset:lower_c_note_dst(block) record_dst(block, self.dst, self.ptr_ty) end
        function Code.CodeInstLoad:lower_c_note_dst(block) record_dst(block, self.dst, self.access.ty) end
        function Code.CodeInstAtomicLoad:lower_c_note_dst(block) record_dst(block, self.dst, self.access.ty) end
        function Code.CodeInstAtomicRmw:lower_c_note_dst(block) record_dst(block, self.dst, self.access.ty) end
        function Code.CodeInstViewMake:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyView(self.elem_ty)) end
        function Code.CodeInstViewData:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyDataPtr(nil)) end
        function Code.CodeInstViewLen:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyIndex) end
        function Code.CodeInstViewStride:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyIndex) end
        function Code.CodeInstSliceMake:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTySlice(self.elem_ty)) end
        function Code.CodeInstSliceData:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyDataPtr(nil)) end
        function Code.CodeInstSliceLen:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyIndex) end
        function Code.CodeInstByteSpanMake:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyByteSpan) end
        function Code.CodeInstByteSpanData:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyDataPtr(byte_ty())) end
        function Code.CodeInstByteSpanLen:lower_c_note_dst(block) record_dst(block, self.dst, Code.CodeTyIndex) end
        function Code.CodeInstCall:lower_c_note_dst(block) record_dst(block, rawget(self, "dst"), nil) end
        local function note_inst_dst(block, k) k:lower_c_note_dst(block) end
        for _, param in ipairs(code_func.params or {}) do note_value(c_emission, param.value, param.ty) end
        for _, b in ipairs(code_func.blocks or {}) do
            for _, param in ipairs(b.params or {}) do note_value(c_emission, param.value, param.ty) end
            for _, inst in ipairs(b.insts or {}) do note_inst_dst(b, inst.op) end
        end
    end

    local function append_args(base, extra)
        local out = {}; for i = 1, #(base or {}) do out[i] = base[i] end; for i = 1, #(extra or {}) do out[#out + 1] = extra[i] end; return out
    end

    function Lower.LowerCarrierBlockParam:lower_c_label_text()
        return clabel(self.block.block).text
    end
    function Lower.LowerCarrierEdgeTransfer:lower_c_matches_labels(source_label, dest_label)
        return clabel(self.edge.from.block).text == source_label and clabel(self.edge.to.block).text == dest_label
    end
    function Lower.LowerCarrierPlan:lower_c_transfer_for_labels(source_label, dest_label)
        for _, transfer in ipairs(self.transfers or {}) do if transfer:lower_c_matches_labels(source_label, dest_label) then return transfer end end
        return nil
    end
    function Lower.LowerCarrierPlan:lower_c_param_for_label(label_text)
        for _, param in ipairs(self.blocks or {}) do if param:lower_c_label_text() == label_text then return param end end
        return nil
    end
    function Lower.LowerCarrierPlan:lower_c_recompute_arg(c_emission, index)
        return atom(index), {}
    end
    function Lower.LowerCarrierEdgeSource:lower_c_arg(c_emission, plan, transfer, source_label) return nil, {} end
    function Lower.LowerCarrierEdgeRecompute:lower_c_arg(c_emission, plan, transfer, source_label)
        return plan:lower_c_recompute_arg(c_emission, self.index)
    end
    function Lower.LowerCarrierEdgeCarrySame:lower_c_arg(c_emission, plan, transfer, source_label)
        local source_param = plan:lower_c_param_for_label(source_label)
        if source_param == nil then return nil, {} end
        return C.CBackendAtomLocal(source_param.param), {}
    end
    function Lower.LowerCarrierEdgeCarryConst:lower_c_arg(c_emission, plan, transfer, source_label)
        local source_param = plan:lower_c_param_for_label(source_label)
        if source_param == nil then return nil, {} end
        local dst = tmp(c_emission, "carrier_next", plan.value_ty)
        return C.CBackendAtomLocal(dst), { C.CBackendHelperCall(dst, binary_helper(c_emission, Core.BinAdd, plan.value_ty, nil), { C.CBackendAtomLocal(source_param.param), C.CBackendAtomLiteral(c_ty(c_emission, plan.value_ty), Core.LitInt(tostring(self.amount))) }) }
    end
    function Lower.LowerCarrierEdgeCarryDynamic:lower_c_arg(c_emission, plan, transfer, source_label)
        local source_param = plan:lower_c_param_for_label(source_label)
        if source_param == nil then return nil, {} end
        local dst = tmp(c_emission, "carrier_next", plan.value_ty)
        return C.CBackendAtomLocal(dst), { C.CBackendHelperCall(dst, binary_helper(c_emission, Core.BinAdd, plan.value_ty, nil), { C.CBackendAtomLocal(source_param.param), atom(self.step) }) }
    end
    function Lower.LowerCarrierEdgeTransfer:lower_c_arg(c_emission, plan, source_label)
        return self.source:lower_c_arg(c_emission, plan, self, source_label)
    end

    function Lower.LowerAddressBlockParam:lower_c_label_text()
        return clabel(self.block.block).text
    end
    function Lower.LowerAddressPlan:lower_c_param_for_label(label_text)
        for _, param in ipairs(self.blocks or {}) do if param:lower_c_label_text() == label_text then return param end end
        return nil
    end
    function Lower.LowerAddressPlan:lower_c_applies_to_func(func)
        for _, param in ipairs(self.blocks or {}) do if param.block.func == func.id then return true end end
        return false
    end
    function Lower.LowerAddressEdgeTransfer:lower_c_matches_labels(source_label, dest_label)
        return clabel(self.edge.from.block).text == source_label and clabel(self.edge.to.block).text == dest_label
    end
    function Lower.LowerAddressPlan:lower_c_transfer_for_labels(source_label, dest_label)
        for _, transfer in ipairs(self.transfers or {}) do if transfer:lower_c_matches_labels(source_label, dest_label) then return transfer end end
        return nil
    end
    function Lower.LowerAddressEdgeSource:lower_c_arg(c_emission, plan, transfer, source_label) return nil, {} end
    local function zero_index_atom() return C.CBackendAtomLiteral(C.CBackendIndex, Core.LitInt("0")) end
    local function address_next_arg(c_emission, plan, rhs)
        local dst = tmp(c_emission, "address_next", Code.CodeTyDataPtr(plan.base.elem_ty))
        return C.CBackendAtomLocal(dst), { C.CBackendAssign(dst, rhs) }
    end
    function Lower.LowerAddressEdgeRecomputeFromCarrier:lower_c_arg(c_emission, plan, transfer, source_label)
        return address_next_arg(c_emission, plan, C.CBackendRPtrOffset(base_atom(c_emission, plan.base.base), atom(self.index), plan.base.elem_size, 0))
    end
    function Lower.LowerAddressEdgeCarrySame:lower_c_arg(c_emission, plan, transfer, source_label)
        local source_param = plan:lower_c_param_for_label(source_label)
        if source_param == nil then return nil, {} end
        return C.CBackendAtomLocal(source_param.param), {}
    end
    function Lower.LowerAddressEdgeCarryConstBytes:lower_c_arg(c_emission, plan, transfer, source_label)
        local source_param = plan:lower_c_param_for_label(source_label)
        if source_param == nil then return nil, {} end
        return address_next_arg(c_emission, plan, C.CBackendRPtrOffset(C.CBackendAtomLocal(source_param.param), zero_index_atom(), 1, self.amount))
    end
    function Lower.LowerAddressEdgeCarryDynamicBytes:lower_c_arg(c_emission, plan, transfer, source_label)
        local source_param = plan:lower_c_param_for_label(source_label)
        if source_param == nil then return nil, {} end
        return address_next_arg(c_emission, plan, C.CBackendRPtrOffset(C.CBackendAtomLocal(source_param.param), atom(self.step), self.elem_size, 0))
    end
    function Lower.LowerAddressEdgeTransfer:lower_c_arg(c_emission, plan, source_label)
        return self.source:lower_c_arg(c_emission, plan, self, source_label)
    end

    local function edge_carrier_args(c_emission, source_label, dest_label)
        local args, pre = {}, {}
        for _, plan in ipairs(c_emission.carrier_plans or {}) do
            local dest_param = plan:lower_c_param_for_label(dest_label)
            local transfer = plan:lower_c_transfer_for_labels(source_label, dest_label)
            if dest_param ~= nil and transfer == nil then error("lower_to_c: missing carrier transfer " .. plan.carrier.text .. " from " .. source_label .. " to " .. dest_label, 2) end
            if transfer ~= nil then
                local atom_, pre_ = transfer:lower_c_arg(c_emission, plan, source_label)
                if atom_ == nil then error("lower_to_c: failed carrier transfer " .. plan.carrier.text .. " from " .. source_label .. " to " .. dest_label, 2) end
                for _, st in ipairs(pre_ or {}) do pre[#pre + 1] = st end
                args[#args + 1] = atom_
            end
        end
        return args, pre
    end
    local function edge_address_args(c_emission, source_label, dest_label)
        local args, pre = {}, {}
        for _, plan in ipairs(c_emission.address_plans or {}) do
            local dest_param = plan:lower_c_param_for_label(dest_label)
            local transfer = plan:lower_c_transfer_for_labels(source_label, dest_label)
            if dest_param ~= nil and transfer == nil then error("lower_to_c: missing address transfer " .. plan.address.text .. " from " .. source_label .. " to " .. dest_label, 2) end
            if transfer ~= nil then
                local atom_, pre_ = transfer:lower_c_arg(c_emission, plan, source_label)
                if atom_ == nil then error("lower_to_c: failed address transfer " .. plan.address.text .. " from " .. source_label .. " to " .. dest_label, 2) end
                for _, st in ipairs(pre_ or {}) do pre[#pre + 1] = st end
                args[#args + 1] = atom_
            end
        end
        return args, pre
    end
    local function edge_lower_args(c_emission, source_label, dest_label)
        local carrier_args, carrier_pre = edge_carrier_args(c_emission, source_label, dest_label)
        if carrier_args == nil then return nil, nil end
        local address_args, address_pre = edge_address_args(c_emission, source_label, dest_label)
        if address_args == nil then return nil, nil end
        local args, pre = {}, {}
        for _, atom_ in ipairs(carrier_args) do args[#args + 1] = atom_ end
        for _, atom_ in ipairs(address_args) do args[#args + 1] = atom_ end
        for _, st in ipairs(carrier_pre or {}) do pre[#pre + 1] = st end
        for _, st in ipairs(address_pre or {}) do pre[#pre + 1] = st end
        return args, pre
    end

    function C.CBackendTerminator:lower_c_apply_carrier_edges(c_emission, source_label) return self, {} end
    function C.CBackendGoto:lower_c_apply_carrier_edges(c_emission, source_label)
        local extra, pre = edge_lower_args(c_emission, source_label, self.dest.text)
        if extra == nil then return self, {} end
        return C.CBackendGoto(self.dest, append_args(self.args, extra)), pre
    end
    local function edge_transfer_label(c_emission, source_label, dest_label, suffix)
        c_emission.next_edge_transfer = (c_emission.next_edge_transfer or 0) + 1
        return C.CBackendLabel(sanitize("edge_xfer:" .. source_label .. ":" .. dest_label .. ":" .. suffix .. ":" .. tostring(c_emission.next_edge_transfer)))
    end
    local function edge_transfer_dest(c_emission, source_label, dest, args, extra, pre, suffix)
        if #(pre or {}) == 0 then return dest, append_args(args, extra) end
        local label = edge_transfer_label(c_emission, source_label, dest.text, suffix)
        c_emission.edge_transfer_blocks = c_emission.edge_transfer_blocks or {}
        c_emission.edge_transfer_blocks[#c_emission.edge_transfer_blocks + 1] = C.CBackendBlock(label, {}, pre, C.CBackendGoto(dest, append_args(args, extra)))
        return label, {}
    end
    function C.CBackendIfGoto:lower_c_apply_carrier_edges(c_emission, source_label)
        local then_extra, then_pre = edge_lower_args(c_emission, source_label, self.then_dest.text)
        local else_extra, else_pre = edge_lower_args(c_emission, source_label, self.else_dest.text)
        if then_extra == nil or else_extra == nil then return self, {} end
        local then_dest, then_args = edge_transfer_dest(c_emission, source_label, self.then_dest, self.then_args, then_extra, then_pre, "then")
        local else_dest, else_args = edge_transfer_dest(c_emission, source_label, self.else_dest, self.else_args, else_extra, else_pre, "else")
        return C.CBackendIfGoto(self.cond, then_dest, then_args, else_dest, else_args), {}
    end
    function C.CBackendSwitchCase:lower_c_apply_carrier_edge(c_emission, source_label)
        local extra, pre = edge_lower_args(c_emission, source_label, self.dest.text)
        if extra == nil then return self end
        local dest, args = edge_transfer_dest(c_emission, source_label, self.dest, self.args, extra, pre, "case")
        return C.CBackendSwitchCase(self.literal, dest, args)
    end
    function C.CBackendSwitchGoto:lower_c_apply_carrier_edges(c_emission, source_label)
        local default_extra, default_pre = edge_lower_args(c_emission, source_label, self.default_dest.text)
        if default_extra == nil then return self, {} end
        local default_dest, default_args = edge_transfer_dest(c_emission, source_label, self.default_dest, self.default_args, default_extra, default_pre, "default")
        local cases = {}; for i = 1, #self.cases do cases[i] = self.cases[i]:lower_c_apply_carrier_edge(c_emission, source_label) end
        return C.CBackendSwitchGoto(self.value, cases, default_dest, default_args), {}
    end

    function Lower.LowerCarrierPlan:lower_c_applies_to_func(func)
        for _, param in ipairs(self.blocks or {}) do if param.block.func == func.id then return true end end
        return false
    end

    local function apply_lower_c_carriers(c_emission, code_func, graph_loops, blocks)
        local has_lower_edge_state = false
        for _, plan in ipairs(c_emission.carrier_plans or {}) do if plan:lower_c_applies_to_func(code_func) then has_lower_edge_state = true end end
        for _, plan in ipairs(c_emission.address_plans or {}) do if plan:lower_c_applies_to_func(code_func) then has_lower_edge_state = true end end
        if not has_lower_edge_state then return blocks end
        local rewritten = {}
        for i, block in ipairs(blocks or {}) do
            c_emission.edge_transfer_blocks = {}
            local params = {}; for j = 1, #(block.params or {}) do params[j] = block.params[j] end
            for _, plan in ipairs(c_emission.carrier_plans or {}) do
                local param = plan:lower_c_param_for_label(block.label.text)
                if param ~= nil and param.block.func == code_func.id then params[#params + 1] = C.CBackendBlockParam(param.param, c_ty(c_emission, param.value_ty)) end
            end
            for _, plan in ipairs(c_emission.address_plans or {}) do
                local param = plan:lower_c_param_for_label(block.label.text)
                if param ~= nil and param.block.func == code_func.id then params[#params + 1] = C.CBackendBlockParam(param.param, c_ty(c_emission, Code.CodeTyDataPtr(param.elem_ty))) end
            end
            local term, pre = block.term:lower_c_apply_carrier_edges(c_emission, block.label.text)
            local stmts = {}; for j = 1, #(block.stmts or {}) do stmts[j] = block.stmts[j] end; for _, st in ipairs(pre or {}) do stmts[#stmts + 1] = st end
            rewritten[#rewritten + 1] = C.CBackendBlock(block.label, params, stmts, term)
            for _, edge_block in ipairs(c_emission.edge_transfer_blocks or {}) do rewritten[#rewritten + 1] = edge_block end
            c_emission.edge_transfer_blocks = nil
        end
        return rewritten
    end

    local function lower_semantic_func(c_emission, graph, flow, kernels, schedules, code_func, c_func, func_plan, graph_loops, baseline_blocks)
        local mutable_func = {
            name = c_func.name,
            symbol = c_func.symbol,
            visibility = c_func.visibility,
            sig = c_func.sig,
            params = c_func.params,
            locals = {},
        }
        for i, l in ipairs(c_func.locals or {}) do mutable_func.locals[i] = l end
        prepare_func_emission(c_emission, code_func, mutable_func)
        local schedules_by_id = schedule_by_id(schedules)
        for _, fragment in ipairs(ordered_fragments_for_func(code_func, func_plan, graph_loops)) do
            local selection = lower_emit_candidate(fragment, schedules_by_id):select_lower_emit()
            selection:emit_to_c(c_emission, Lower.LowerCEmitInput(graph, flow, kernels, schedules, code_func, fragment, baseline_blocks))
        end
        local lowered_blocks = apply_lower_c_carriers(c_emission, code_func, graph_loops, c_emission.blocks)
        return C.CBackendFunc(
            mutable_func.name,
            mutable_func.symbol,
            mutable_func.visibility,
            mutable_func.sig,
            mutable_func.params,
            mutable_func.locals,
            C.CBackendBodyBlocks(clabel(code_func.blocks[1].id), lowered_blocks)
        )
    end

    local function func_by_id(code_module)
        local out = {}; for _, f in ipairs(code_module.funcs or {}) do out[f.id.text] = f end; return out
    end

    function C.CBackendFuncBody:lower_c_canonical_blocks() error("lower_to_c: semantic lowering requires canonical C block body", 3) end
    function C.CBackendBodyBlocks:lower_c_canonical_blocks() return self.blocks end
    local function c_block_body(func)
        local body = assert(func and func.body, "lower_to_c: expected C function with body")
        return body:lower_c_canonical_blocks()
    end

    local function graph_indexes(graph)
        local loops = {}
        for _, fg in ipairs(graph and graph.funcs or {}) do for _, loop in ipairs(fg.loops or {}) do loops[loop.id.text] = loop end end
        return loops
    end

    function Lower.LowerModule:lower_c_is_lower_module() return true end

    local function normalize_args(code_module, lower_module, opts)
        opts = opts or {}
        if lower_module ~= nil and lower_module.lower_c_is_lower_module and lower_module:lower_c_is_lower_module() then
            local graph = CodeGraph.graph(code_module)
            local flow = lower_module.kernels and lower_module.kernels.flow or CodeFlowFacts.facts(code_module, graph)
            local value = lower_module.kernels and lower_module.kernels.value or CodeValueFacts.facts(code_module, graph, flow)
            local mem = lower_module.kernels and lower_module.kernels.mem or CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
            local effect = lower_module.kernels and lower_module.kernels.effect or CodeEffectFacts.facts(code_module, graph, mem, nil)
            return graph, flow, value, mem, effect, lower_module.kernels, lower_module.schedules, lower_module, opts
        end
        local graph = CodeGraph.graph(code_module)
        local flow = CodeFlowFacts.facts(code_module, graph)
        local value = CodeValueFacts.facts(code_module, graph, flow)
        local mem = CodeMemFacts.semantic_facts(code_module, graph, flow, value, nil)
        local effect = CodeEffectFacts.facts(code_module, graph, mem, nil)
        local kernels = CodeKernelPlan.plan(code_module, graph, flow, value, mem, effect)
        local schedules = CodeSchedulePlan.plan(code_module, kernels, flow, value, mem, effect, opts and (opts.target_model or opts.back_target_model))
        local lower = CodeLowerPlan.plan(code_module, graph, kernels, schedules, Lower.LowerTargetC)
        flow = kernels.flow
        value = kernels.value
        mem = kernels.mem
        effect = kernels.effect
        return graph, flow, value, mem, effect, kernels, schedules, lower, opts
    end

    local function module(code_module, lower_module, opts)
        local graph, flow, value, mem, effect, kernels, schedules, lower
        graph, flow, value, mem, effect, kernels, schedules, lower, opts = normalize_args(code_module, lower_module, opts)
        opts = opts or {}
        local has_semantic = false
        local semantic_func = {}
        for _, fp in ipairs(lower.funcs or {}) do for _, frag in ipairs(fp.fragments or {}) do if semantic_strategy(frag) then has_semantic = true; semantic_func[fp.func.text] = true end end end
        local code_to_c_opts = {}; for k, v in pairs(opts or {}) do code_to_c_opts[k] = v end; code_to_c_opts.lower = lower; code_to_c_opts.lower_skip_funcs = semantic_func
        local unit = CodeToC.module(code_module, code_to_c_opts)
        if not has_semantic then return unit end

        local base_func_by_name = {}; for _, f in ipairs(unit.funcs or {}) do base_func_by_name[f.symbol] = f end
        local plans = {}; for _, fp in ipairs(lower.funcs or {}) do plans[fp.func.text] = fp end
        local funcs = func_by_id(code_module)
        local graph_loops = graph_indexes(graph)
        local cfuncs = {}
        local carrier_plan_by_id = {}
        for _, carrier in ipairs((lower and lower.carriers) or {}) do carrier_plan_by_id[carrier.carrier.text] = carrier end
        local c_emission = {
            unit = unit,
            c_type_projection = make_c_type_projection(code_module),
            helper_by_key = {},
            next_helper = 0,
            next_tmp = 0,
            mem = mem,
            mem_projection = CodeMemFacts.access_projection(mem),
            carrier_plans = (lower and lower.carriers) or {},
            carrier_plan_by_id = carrier_plan_by_id,
            address_plans = (lower and lower.addresses) or {},
        }
        for _, h in ipairs(unit.helpers or {}) do c_emission.helper_by_key[helper_key(h.spec)] = h end

        for _, code_func in ipairs(code_module.funcs or {}) do
            local fp = plans[code_func.id.text]
            local base = base_func_by_name[code_func.name]
            if fp ~= nil then
                local semantic = false
                for _, frag in ipairs(fp.fragments or {}) do if semantic_strategy(frag) then semantic = true end end
                if semantic then cfuncs[#cfuncs + 1] = lower_semantic_func(c_emission, graph, flow, kernels, schedules, code_func, base, fp, graph_loops, c_block_body(base))
                else cfuncs[#cfuncs + 1] = base end
            else
                cfuncs[#cfuncs + 1] = base
            end
        end
        return C.CBackendUnit(unit.module_name, unit.target, unit.sigs, unit.types, unit.globals, unit.externs, unit.helpers, cfuncs)
    end

    local function exec_plan(code_module, lower_module, opts)
        local graph, flow, value, mem, effect, kernels
        graph, flow, value, mem, effect, kernels, _, _, opts = normalize_args(code_module, lower_module, opts)
        opts = opts or {}
        return ExecPlan.plan(code_module, {
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernels = kernels,
            stencil = opts.stencil,
            artifacts = opts.artifacts,
            contracts = opts.contracts,
        })
    end

    api.module = module
    api.unit = module
    api.exec_plan = exec_plan
    api.exec = exec_plan

    T._lalin_api_cache.lower_to_c = api
    return api
end

return bind_context
