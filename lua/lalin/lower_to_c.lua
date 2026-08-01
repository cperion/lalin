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
    local Flow = T.LalinFlow
    local Mem = T.LalinMem
    local Stencil = T.LalinStencil
    local CMat = T.LalinCMat
    local CEm = T.LalinCEmit
    local Graph = T.LalinGraph
    local asdl = require("lalin.asdl")

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
    local CMaterialize = require("lalin.emit_c_materialize")(T)
    local LowerKernelRewrite = require("lalin.lower_kernel_rewrite")(T)

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

    local function make_c_type_projection(code_module, target)
        local spine = Lower.LowerBackSpine(code_module, Graph.CodeGraph(code_module.id, {}), target or C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true))
        local machine = CEm.CEmitMachine.empty(spine)
        return machine
    end

    local function c_ty(c_emission, ty)
        local result, new_machine = CodeType.code_type_to_c(c_emission.c_type_projection, ty)
        c_emission.c_type_projection = new_machine
        return result
    end

    local function add_helper(c_emission, spec)
        local id = spec:c_helper_id()
        local existing = c_emission.helper_by_key[id.text]
        if existing ~= nil then return existing.id end
        local use = C.CBackendHelperUse(id, spec)
        c_emission.helper_by_key[id.text] = use
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
    local function unary_helper(c_emission, op, ty)
        return add_helper(c_emission, C.CBackendHelperUnary(op, c_ty(c_emission, ty)))
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

    function Mem.MemAlignment:lower_c_alignment_fact() return C.CBackendAlignmentUnknown end
    function Mem.MemAlignKnown:lower_c_alignment_fact() return C.CBackendAlignmentKnown(self.bytes) end
    function Mem.MemAlignAtLeast:lower_c_alignment_fact() return C.CBackendAlignmentKnown(self.bytes) end
    function Mem.MemAlignAssumed:lower_c_alignment_fact() return C.CBackendAlignmentAssumed(self.bytes, "mem proof") end

    function Mem.MemAlignment:lower_cmat_alignment_fact() return Stencil.StencilAlignmentUnknown end
    function Mem.MemAlignKnown:lower_cmat_alignment_fact() return Stencil.StencilAlignmentKnown(self.bytes) end
    function Mem.MemAlignAtLeast:lower_cmat_alignment_fact() return Stencil.StencilAlignmentKnown(self.bytes) end
    function Mem.MemAlignAssumed:lower_cmat_alignment_fact() return Stencil.StencilAlignmentKnown(self.bytes) end

    function Kernel.KernelResult:lower_rewrite_plan(_kernel_id, _kplan)
        return Kernel.KernelRewritePlan(
            Kernel.KernelRewriteNone(),
            nil, {}, {}, {}
        )
    end

    function Kernel.KernelResultClosedForm:lower_rewrite_plan(_kernel_id, kplan)
        local eq = kplan.body.equivalence
        return Kernel.KernelRewritePlan(
            Kernel.KernelRewriteClosedForm(self.closed_form.expr, nil),
            nil, {}, {},
            eq and eq.proofs or {}
        )
    end

    function Kernel.KernelResultFind:lower_rewrite_plan(_kernel_id, kplan)
        local eq = kplan.body.equivalence
        -- self.src is KernelExpr; KernelRewriteFind.src expects KernelLane
        -- resolved by the rewrite pass from the kernel body lanes
        return Kernel.KernelRewritePlan(
            Kernel.KernelRewriteFind(nil, self.pred, self.not_found, nil),
            nil, {}, {},
            eq and eq.proofs or {}
        )
    end

    function Kernel.KernelResultReduction:lower_rewrite_plan(_kernel_id, kplan)
        local eq = kplan.body.equivalence
        return Kernel.KernelRewritePlan(
            Kernel.KernelRewriteReduce(self.reduction, nil, nil, nil),
            nil, {}, {},
            eq and eq.proofs or {}
        )
    end

    function Kernel.KernelResultOriginalControl:lower_rewrite_plan(_kernel_id, _kplan)
        return Kernel.KernelRewritePlan(
            Kernel.KernelRewriteNone(),
            nil, {}, {}, {}
        )
    end

    function Kernel.KernelResultValue:lower_rewrite_plan(_kernel_id, _kplan)
        return Kernel.KernelRewritePlan(Kernel.KernelRewriteNone(), nil, {}, {}, {})
    end

    function Kernel.KernelResultAll:lower_rewrite_plan(_kernel_id, _kplan)
        return Kernel.KernelRewritePlan(Kernel.KernelRewriteNone(), nil, {}, {}, {})
    end

    function Kernel.KernelResultAllCompare:lower_rewrite_plan(_kernel_id, _kplan)
        return Kernel.KernelRewritePlan(Kernel.KernelRewriteNone(), nil, {}, {}, {})
    end

    function Kernel.KernelResultAny:lower_rewrite_plan(_kernel_id, _kplan)
        return Kernel.KernelRewritePlan(Kernel.KernelRewriteNone(), nil, {}, {}, {})
    end


    local function place_for_access(c_emission, lane, access, index_expr)
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

    function Kernel.KernelResult:lower_c_is_control_result() return false end
    function Kernel.KernelResultAll:lower_c_is_control_result() return true end
    function Kernel.KernelResultAllCompare:lower_c_is_control_result() return true end
    function Kernel.KernelResultAny:lower_c_is_control_result() return true end
    function Kernel.KernelResultFind:lower_c_is_control_result() return true end

    local function loop_partition(c_emission, graph, flow, kplan)
        local loop = graph_loop_by_id(graph)[kplan.subject.loop.text]
        local result_name = tostring(kplan and kplan.body and kplan.body.result or "")
        local control_result = kplan and kplan.body and kplan.body.result and kplan.body.result:lower_c_is_control_result() or false
        if loop == nil or #(loop.latches or {}) ~= 1 or (#(loop.exits or {}) ~= 1 and not (control_result and #(loop.exits or {}) == 2)) then
            local edges = {}
            for _, e in ipairs(loop and loop.exits or {}) do edges[#edges + 1] = (e.from.block.text .. "->" .. e.to.block.text) end
            error("lower_to_c: kernel fragment requires one loop/latch/exit (latches=" .. tostring(loop and #(loop.latches or {}) or 0) .. ", exits=" .. tostring(loop and #(loop.exits or {}) or 0) .. ", control=" .. tostring(control_result) .. ", result=" .. tostring(result_name) .. ", edges=" .. table.concat(edges, ",") .. ")", 2)
        end
        local body_set = {}; for _, gb in ipairs(loop.body or {}) do body_set[gb.block.text] = true end
        local edge_facts = edge_fact_by_key(flow)
        local exit_edge, latch_edge = loop.exits[1], loop.latches[1]
        if control_result then
            for _, edge in ipairs(loop.exits or {}) do if edge.from.block == loop.header.block then exit_edge = edge end end
        end
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
    function Kernel.KernelEffectFold:lower_c_place_effect(c_emission, effects_by_block)
        -- Fold ownership is represented by KernelResultReduction and lowered by
        -- the StencilSinkOpFold leaf of the active StencilComputation. It is
        -- intentionally not placed as a direct effect.
    end
    function Kernel.KernelEffectStore:lower_c_place_effect(c_emission, effects_by_block)
        local access = first_write_access(c_emission, self.dst)
        local block = access and access.block and access.block.block
        if block ~= nil then effects_by_block[block.text] = effects_by_block[block.text] or {}; effects_by_block[block.text][#effects_by_block[block.text] + 1] = self end
    end
    function Kernel.KernelEffectScan:lower_c_place_effect(c_emission, effects_by_block)
        local access = first_write_access(c_emission, self.dst)
        local block = access and access.block and access.block.block
        if block ~= nil then effects_by_block[block.text] = effects_by_block[block.text] or {}; effects_by_block[block.text][#effects_by_block[block.text] + 1] = self end
    end
    function Kernel.KernelEffectCopy:lower_c_place_effect(c_emission, effects_by_block)
        local access = first_write_access(c_emission, self.dst)
        local block = access and access.block and access.block.block
        if block ~= nil then effects_by_block[block.text] = effects_by_block[block.text] or {}; effects_by_block[block.text][#effects_by_block[block.text] + 1] = self end
    end
    function Kernel.KernelEffectScatterReduce:lower_c_place_effect(c_emission, effects_by_block)
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


    function Core.UnaryOp:lower_c_stencil_unary_op()
        error("lower_to_c: unary op cannot be represented as StencilPointUnary", 2)
    end
    function Core.UnaryNeg:lower_c_stencil_unary_op() return Stencil.StencilUnaryNeg end
    function Core.UnaryNot:lower_c_stencil_unary_op() return Stencil.StencilUnaryBoolNot end
    function Core.UnaryBitNot:lower_c_stencil_unary_op() return Stencil.StencilUnaryBitNot end

    function Core.BinaryOp:lower_c_stencil_binary_op()
        error("lower_to_c: binary op cannot be represented as StencilPointBinary", 2)
    end
    function Core.BinAdd:lower_c_stencil_binary_op() return Stencil.StencilBinaryAdd end
    function Core.BinSub:lower_c_stencil_binary_op() return Stencil.StencilBinarySub end
    function Core.BinMul:lower_c_stencil_binary_op() return Stencil.StencilBinaryMul end
    function Core.BinDiv:lower_c_stencil_binary_op() return Stencil.StencilBinaryDiv end
    function Core.BinRem:lower_c_stencil_binary_op() return Stencil.StencilBinaryMod end
    function Core.BinBitAnd:lower_c_stencil_binary_op() return Stencil.StencilBinaryAnd end
    function Core.BinBitOr:lower_c_stencil_binary_op() return Stencil.StencilBinaryOr end
    function Core.BinBitXor:lower_c_stencil_binary_op() return Stencil.StencilBinaryXor end
    function Core.BinShl:lower_c_stencil_binary_op() return Stencil.StencilBinaryShl end
    function Core.BinLShr:lower_c_stencil_binary_op() return Stencil.StencilBinaryLShr end
    function Core.BinAShr:lower_c_stencil_binary_op() return Stencil.StencilBinaryAShr end

    function Mem.MemBase:lower_c_cmat_local_id()
        error("lower_to_c: stencil CMat access base is not a local value", 2)
    end
    function Mem.MemBaseValue:lower_c_cmat_local_id() return CMat.CMatLocalId(sanitize(self.value.text)) end
    function Mem.MemBaseArgument:lower_c_cmat_local_id() return CMat.CMatLocalId(sanitize(self.value.text)) end

    local function lane_backend_alignment(lane)
        for _, info in ipairs(lane.backend_info or {}) do
            local align = info.alignment
            if align ~= nil and asdl.classof(align) ~= "MemAlignUnknown" then
                return align:lower_cmat_alignment_fact()
            end
        end
        return Stencil.StencilAlignmentUnknown
    end

    local function cmat_access_binding_for_lane(lane, name, role)
        local layout = Stencil.StencilLayoutContiguous(1)
        local source = Stencil.StencilAccess(name, role, lane.elem_ty, layout)
        return CMat.CMatAccessBinding(
            Stencil.StencilAccessRef(name),
            source,
            lane.base:lower_c_cmat_local_id(),
            lane.elem_ty,
            layout,
            role:cmat_mutability(),
            role:cmat_restrict_eligible(layout),
            role:cmat_const_eligible(),
            lane_backend_alignment(lane)
        )
    end

    local function append_discovered_lanes(out, discovery)
        for _, lane in ipairs(discovery.lanes) do
            local seen = false
            for _, prior in ipairs(out) do
                if prior == lane then seen = true; break end
            end
            if not seen then out[#out + 1] = lane end
        end
        return out
    end

    function CMat.CMatBindingProjection:lookup_kernel(id)
        for _, entry in ipairs(self.kernel_bindings) do
            if entry.id == id then return CMat.CMatBindingFound(entry.binding) end
        end
        return CMat.CMatBindingMissing("missing kernel binding `" .. id.text .. "`")
    end
    function CMat.CMatBindingProjection:lookup_code(value)
        for _, entry in ipairs(self.code_bindings) do
            if entry.value == value then return CMat.CMatBindingFound(entry.binding) end
        end
        return CMat.CMatBindingMissing("missing Code binding `" .. value.text .. "`")
    end
    function CMat.CMatBindingFound:lower_c_discover_lanes(projection)
        return self.binding.expr:lower_c_discover_lanes(projection)
    end

    function Kernel.KernelExprValue:lower_c_discover_lanes(projection)
        return projection:lookup_code(self.value):lower_c_discover_lanes(projection)
    end
    function Kernel.KernelExprAlgebra:lower_c_discover_lanes(projection) return self.expr:lower_c_discover_lanes(projection) end
    function Kernel.KernelExprLaneLoad:lower_c_discover_lanes(_projection) return CMat.CMatLaneDiscovery({ self.lane }) end
    function Kernel.KernelExprKernelValue:lower_c_discover_lanes(projection)
        return projection:lookup_kernel(self.value):lower_c_discover_lanes(projection)
    end
    function Value.ValueExprConst:lower_c_discover_lanes(_projection) return CMat.CMatLaneDiscovery({}) end
    function Value.ValueExprValue:lower_c_discover_lanes(projection)
        return projection:lookup_code(self.value):lower_c_discover_lanes(projection)
    end
    function Value.ValueExprUnary:lower_c_discover_lanes(projection) return self.value:lower_c_discover_lanes(projection) end
    function Value.ValueExprCast:lower_c_discover_lanes(projection) return self.value:lower_c_discover_lanes(projection) end
    local function discover_binary_lanes(a, b, projection)
        local lanes = {}
        append_discovered_lanes(lanes, a:lower_c_discover_lanes(projection))
        append_discovered_lanes(lanes, b:lower_c_discover_lanes(projection))
        return CMat.CMatLaneDiscovery(lanes)
    end
    function Value.ValueExprAdd:lower_c_discover_lanes(p) return discover_binary_lanes(self.a, self.b, p) end
    function Value.ValueExprSub:lower_c_discover_lanes(p) return discover_binary_lanes(self.a, self.b, p) end
    function Value.ValueExprMul:lower_c_discover_lanes(p) return discover_binary_lanes(self.a, self.b, p) end
    function Value.ValueExprDiv:lower_c_discover_lanes(p) return discover_binary_lanes(self.a, self.b, p) end
    function Value.ValueExprRem:lower_c_discover_lanes(p) return discover_binary_lanes(self.a, self.b, p) end
    function Value.ValueExprBinary:lower_c_discover_lanes(p) return discover_binary_lanes(self.a, self.b, p) end
    function Value.ValueExprCmp:lower_c_discover_lanes(p) return discover_binary_lanes(self.a, self.b, p) end
    function Value.ValueExprSelect:lower_c_discover_lanes(projection)
        local lanes = {}
        append_discovered_lanes(lanes, self.cond:lower_c_discover_lanes(projection))
        append_discovered_lanes(lanes, self.t:lower_c_discover_lanes(projection))
        append_discovered_lanes(lanes, self.f:lower_c_discover_lanes(projection))
        return CMat.CMatLaneDiscovery(lanes)
    end
    function Value.ValueExprAffine:lower_c_discover_lanes(_projection) return CMat.CMatLaneDiscovery({}) end

    local function cmat_binding_projection(kplan)
        local kernel_entries, code_entries = {}, {}
        for _, binding in ipairs(kplan.body.bindings or {}) do
            kernel_entries[#kernel_entries + 1] = CMat.CMatKernelBindingEntry(binding.id, binding)
            local code_name = binding.id.text:match("^kval:(.+)$")
            if code_name ~= nil then
                code_entries[#code_entries + 1] = CMat.CMatCodeBindingEntry(Code.CodeValueId(code_name), binding)
            end
        end
        return CMat.CMatBindingProjection(kernel_entries, code_entries)
    end

    function Kernel.KernelDomainFlow:lower_c_window_counter()
        if self.counter == nil then return CMat.CMatWindowNoCounter end
        return CMat.CMatWindowCounterValue(self.counter)
    end
    function Stencil.StencilProduceRange1D:lower_c_window_layout(_counter) return CMat.CMatWindowLayoutNone end
    function Stencil.StencilProduceRangeND:lower_c_window_layout(_counter) return CMat.CMatWindowLayoutNone end
    function Stencil.StencilProduceTiledND:lower_c_window_layout(_counter) return CMat.CMatWindowLayoutNone end
    function Stencil.StencilProduceWindowND:lower_c_window_layout(counter)
        if #self.axes ~= 1 or #self.windows ~= 1 then
            return CMat.CMatWindowLayoutRejected("inline CMat window projection requires exactly one axis")
        end
        return CMat.CMatWindowLayout1D(self.axes[1], self.windows[1], counter)
    end

    function CMat.CMatPointProjection:lookup_read(lane)
        for _, entry in ipairs(self.reads) do
            if entry.lane == lane then return CMat.CMatReadAccessFound(entry.access) end
        end
        return CMat.CMatReadAccessMissing(lane, "lane discovery omitted a materialized read")
    end
    function CMat.CMatReadAccessFound:lower_c_stencil_point() return Stencil.StencilPointInput(self.access.access) end

    local function cmat_point_projection(kplan, producer, exprs)
        local bindings = cmat_binding_projection(kplan)
        local lanes = {}
        for _, expr in ipairs(exprs) do append_discovered_lanes(lanes, expr:lower_c_discover_lanes(bindings)) end
        local reads = {}
        for i, lane in ipairs(lanes) do
            local access = cmat_access_binding_for_lane(lane, "x" .. tostring(i), Stencil.StencilAccessRead)
            reads[i] = CMat.CMatReadAccessEntry(lane, access)
        end
        local counter = kplan.body.domain:lower_c_window_counter()
        return CMat.CMatPointProjection(bindings, reads, producer.shape:lower_c_window_layout(counter))
    end

    function Mem.MemAccessScalar:lower_c_unbound_window_offset() return CMat.CMatWindowNotIndexed("scalar access is not a window index") end
    function Mem.MemAccessContiguous:lower_c_unbound_window_offset() return CMat.CMatWindowOffsetKnown(0) end
    function Mem.MemAccessStrided:lower_c_unbound_window_offset() return CMat.CMatWindowNotIndexed("strided access is not a primary window index") end
    function Mem.MemAccessGather:lower_c_unbound_window_offset() return CMat.CMatWindowNotIndexed("gather access is not a primary window index") end
    function Mem.MemAccessScatter:lower_c_unbound_window_offset() return CMat.CMatWindowNotIndexed("scatter access is not a primary window index") end
    function Mem.MemAccessUnknown:lower_c_unbound_window_offset() return CMat.CMatWindowNotIndexed("unknown access is not a primary window index") end

    function CMat.CMatWindowCounterValue:lower_c_value_window_offset(value, projection, pattern)
        if self.value == value then return CMat.CMatWindowOffsetKnown(0) end
        return projection.bindings:lookup_code(value):lower_c_window_offset(projection, pattern)
    end
    function CMat.CMatWindowNoCounter:lower_c_value_window_offset(value, projection, pattern)
        return projection.bindings:lookup_code(value):lower_c_window_offset(projection, pattern)
    end
    function CMat.CMatBindingFound:lower_c_window_offset(projection, pattern)
        return self.binding.expr:lower_c_window_offset(projection, pattern)
    end
    function CMat.CMatBindingMissing:lower_c_window_offset(_projection, pattern)
        return pattern:lower_c_unbound_window_offset()
    end

    function Kernel.KernelExprValue:lower_c_window_offset(projection, pattern)
        return projection.bindings:lookup_code(self.value):lower_c_window_offset(projection, pattern)
    end
    function Kernel.KernelExprAlgebra:lower_c_window_offset(projection, pattern) return self.expr:lower_c_window_offset(projection, pattern) end
    function Kernel.KernelExprLaneLoad:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowNotIndexed("nested lane load is not an affine index") end
    function Kernel.KernelExprKernelValue:lower_c_window_offset(projection, pattern)
        return projection.bindings:lookup_kernel(self.value):lower_c_window_offset(projection, pattern)
    end
    function Value.ValueExprConst:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowNotIndexed("constant is not an index origin") end
    function Value.ValueExprValue:lower_c_window_offset(projection, pattern)
        return projection.window:lower_c_counter():lower_c_value_window_offset(self.value, projection, pattern)
    end
    function Value.ValueExprUnary:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("unary index is not affine") end
    function Value.ValueExprCast:lower_c_window_offset(projection, pattern) return self.value:lower_c_window_offset(projection, pattern) end
    function Value.ValueExpr:lower_c_window_literal_int() return CMat.CMatLiteralIntMissing end
    function Value.ValueExprConst:lower_c_window_literal_int() return self.const:lower_c_window_literal_int() end
    function Code.CodeConst:lower_c_window_literal_int() return CMat.CMatLiteralIntMissing end
    function Code.CodeConstLiteral:lower_c_window_literal_int() return self.literal:lower_c_window_literal_int() end
    function Core.Literal:lower_c_window_literal_int() return CMat.CMatLiteralIntMissing end
    function Core.LitInt:lower_c_window_literal_int() return CMat.CMatLiteralIntKnown(self.raw) end
    function CMat.CMatLiteralIntKnown:lower_c_add_rhs_window_offset(lhs, _rhs, projection, pattern)
        return lhs:lower_c_window_offset(projection, pattern):lower_c_add_literal_offset(self.raw)
    end
    function CMat.CMatLiteralIntMissing:lower_c_add_rhs_window_offset(_lhs, rhs, projection, pattern)
        return rhs:lower_c_window_literal_int():lower_c_add_lhs_window_offset(rhs, projection, pattern)
    end
    function CMat.CMatLiteralIntKnown:lower_c_add_lhs_window_offset(rhs, projection, pattern)
        return rhs:lower_c_window_offset(projection, pattern):lower_c_add_literal_offset(self.raw)
    end
    function CMat.CMatLiteralIntMissing:lower_c_add_lhs_window_offset(_rhs, _projection, _pattern)
        return CMat.CMatWindowOffsetRejected("window index addition requires one literal operand")
    end
    function CMat.CMatLiteralIntKnown:lower_c_sub_rhs_window_offset(expr, projection, pattern)
        return expr:lower_c_window_offset(projection, pattern):lower_c_sub_literal_offset(self.raw)
    end
    function CMat.CMatLiteralIntMissing:lower_c_sub_rhs_window_offset(_expr, _projection, _pattern)
        return CMat.CMatWindowOffsetRejected("window index subtraction requires a literal right operand")
    end
    function Value.ValueExprAdd:lower_c_window_offset(projection, pattern)
        return self.b:lower_c_window_literal_int():lower_c_add_rhs_window_offset(self.a, self.b, projection, pattern)
    end
    function Value.ValueExprSub:lower_c_window_offset(projection, pattern)
        return self.b:lower_c_window_literal_int():lower_c_sub_rhs_window_offset(self.a, projection, pattern)
    end
    function Value.ValueExprMul:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("multiplied index is not a unit affine window index") end
    function Value.ValueExprDiv:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("divided index is not affine") end
    function Value.ValueExprRem:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("remainder index is not affine") end
    function Value.ValueExprBinary:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("generic binary index is not affine") end
    function Value.ValueExprSelect:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("selected index is not affine") end
    function Value.ValueExprCmp:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("comparison is not an index") end
    function Value.ValueExprAffine:lower_c_window_offset(_projection, _pattern) return CMat.CMatWindowOffsetRejected("affine fact requires an explicit axis projection") end

    function CMat.CMatWindowOffsetKnown:lower_c_add_literal_offset(raw) return CMat.CMatWindowOffsetKnown(self.offset + tonumber(raw)) end
    function CMat.CMatWindowOffsetKnown:lower_c_sub_literal_offset(raw) return CMat.CMatWindowOffsetKnown(self.offset - tonumber(raw)) end
    function CMat.CMatWindowNotIndexed:lower_c_add_literal_offset(_raw) return self end
    function CMat.CMatWindowNotIndexed:lower_c_sub_literal_offset(_raw) return self end
    function CMat.CMatWindowOffsetRejected:lower_c_add_literal_offset(_raw) return self end
    function CMat.CMatWindowOffsetRejected:lower_c_sub_literal_offset(_raw) return self end

    function CMat.CMatWindowLayoutNone:lower_c_counter() return CMat.CMatWindowNoCounter end
    function CMat.CMatWindowLayoutRejected:lower_c_counter() return CMat.CMatWindowNoCounter end
    function CMat.CMatWindowLayout1D:lower_c_counter() return self.counter end
    function CMat.CMatWindowNotIndexed:lower_c_stencil_point(read, _layout) return read:lower_c_stencil_point() end
    function CMat.CMatWindowOffsetKnown:lower_c_stencil_point(read, layout) return layout:lower_c_stencil_point(read, self.offset) end
    function CMat.CMatWindowLayoutNone:lower_c_stencil_point(read, _offset) return read:lower_c_stencil_point() end
    function CMat.CMatWindowLayout1D:lower_c_stencil_point(read, offset)
        if offset == 0 then return read:lower_c_stencil_point() end
        if offset < -self.window.before or offset > self.window.after then
            return CMat.CMatWindowOffsetRejected("window lane offset is outside the declared window"):lower_c_stencil_point(read, self)
        end
        return read:lower_c_window_stencil_point(offset)
    end
    function CMat.CMatReadAccessFound:lower_c_window_stencil_point(offset)
        return Stencil.StencilPointWindowInput(self.access.access, { Stencil.StencilWindowOffset(Stencil.StencilAxisRef(1), offset) })
    end


    function Kernel.KernelExprLaneLoad:lower_c_stencil_point_ty(_state) return self.lane.elem_ty end
    function Kernel.KernelExprKernelValue:lower_c_stencil_point_ty(projection)
        return projection.bindings:lookup_kernel(self.value):lower_c_stencil_point_ty(projection)
    end
    function Kernel.KernelExprAlgebra:lower_c_stencil_point_ty(state) return self.expr:lower_c_stencil_point_ty(state) end
    function Kernel.KernelExprValue:lower_c_stencil_point_ty(projection)
        return projection.bindings:lookup_code(self.value):lower_c_stencil_point_ty(projection)
    end
    function CMat.CMatBindingFound:lower_c_stencil_point_ty(projection) return self.binding.expr:lower_c_stencil_point_ty(projection) end

    function Kernel.KernelExprLaneLoad:lower_c_stencil_point(projection)
        local read = projection:lookup_read(self.lane)
        local offset = self.index:lower_c_window_offset(projection, self.lane.pattern)
        return offset:lower_c_stencil_point(read, projection.window)
    end
    function Kernel.KernelExprKernelValue:lower_c_stencil_point(projection)
        return projection.bindings:lookup_kernel(self.value):lower_c_stencil_point(projection)
    end
    function Kernel.KernelExprAlgebra:lower_c_stencil_point(state) return self.expr:lower_c_stencil_point(state) end
    function Kernel.KernelExprValue:lower_c_stencil_point(projection)
        return projection.bindings:lookup_code(self.value):lower_c_stencil_point(projection)
    end
    function CMat.CMatBindingFound:lower_c_stencil_point(projection) return self.binding.expr:lower_c_stencil_point(projection) end

    function Value.ValueExprConst:lower_c_stencil_point_ty(_state) return self.const.ty end
    function Value.ValueExprValue:lower_c_stencil_point_ty(projection)
        return projection.bindings:lookup_code(self.value):lower_c_stencil_point_ty(projection)
    end
    function Value.ValueExprUnary:lower_c_stencil_point_ty(_state) return self.ty end
    function Value.ValueExprCast:lower_c_stencil_point_ty(_state) return self.to end
    function Value.ValueExprAdd:lower_c_stencil_point_ty(_state) return self.ty end
    function Value.ValueExprSub:lower_c_stencil_point_ty(_state) return self.ty end
    function Value.ValueExprMul:lower_c_stencil_point_ty(_state) return self.ty end
    function Value.ValueExprDiv:lower_c_stencil_point_ty(_state) return self.ty end
    function Value.ValueExprRem:lower_c_stencil_point_ty(_state) return self.ty end
    function Value.ValueExprBinary:lower_c_stencil_point_ty(_state) return self.ty end
    function Value.ValueExprCmp:lower_c_stencil_point_ty(_state) return Code.CodeTyBool8 end
    function Value.ValueExprSelect:lower_c_stencil_point_ty(state) return self.t:lower_c_stencil_point_ty(state) end

    function Value.ValueExpr:lower_c_stencil_point(_state)
        error("lower_to_c: ValueExpr cannot become StencilPointExpr", 2)
    end
    function Value.ValueExprConst:lower_c_stencil_point(_state) return Stencil.StencilPointConst(self, self.const.ty) end
    function Value.ValueExprValue:lower_c_stencil_point(projection)
        return projection.bindings:lookup_code(self.value):lower_c_stencil_point(projection)
    end
    function Value.ValueExprUnary:lower_c_stencil_point(state) return Stencil.StencilPointUnary(self.op:lower_c_stencil_unary_op(), self.value:lower_c_stencil_point(state), self.ty, nil, nil) end
    function Value.ValueExprAdd:lower_c_stencil_point(state) return Stencil.StencilPointBinary(Stencil.StencilBinaryAdd, self.a:lower_c_stencil_point(state), self.b:lower_c_stencil_point(state), self.ty, self.sem, nil) end
    function Value.ValueExprSub:lower_c_stencil_point(state) return Stencil.StencilPointBinary(Stencil.StencilBinarySub, self.a:lower_c_stencil_point(state), self.b:lower_c_stencil_point(state), self.ty, self.sem, nil) end
    function Value.ValueExprMul:lower_c_stencil_point(state) return Stencil.StencilPointBinary(Stencil.StencilBinaryMul, self.a:lower_c_stencil_point(state), self.b:lower_c_stencil_point(state), self.ty, self.sem, nil) end
    function Value.ValueExprDiv:lower_c_stencil_point(state) return Stencil.StencilPointBinary(Stencil.StencilBinaryDiv, self.a:lower_c_stencil_point(state), self.b:lower_c_stencil_point(state), self.ty, self.sem, nil) end
    function Value.ValueExprRem:lower_c_stencil_point(state) return Stencil.StencilPointBinary(Stencil.StencilBinaryMod, self.a:lower_c_stencil_point(state), self.b:lower_c_stencil_point(state), self.ty, self.sem, nil) end
    function Value.ValueExprBinary:lower_c_stencil_point(state) return Stencil.StencilPointBinary(self.op:lower_c_stencil_binary_op(), self.a:lower_c_stencil_point(state), self.b:lower_c_stencil_point(state), self.ty, self.sem, nil) end
    function Value.ValueExprCast:lower_c_stencil_point(state) return Stencil.StencilPointCast(self.op, self.value:lower_c_stencil_point(state), self.from, self.to) end
    function Value.ValueExprCmp:lower_c_stencil_point(state) return Stencil.StencilPointCompare(self.op, self.a:lower_c_stencil_point(state), self.b:lower_c_stencil_point(state), Code.CodeTyBool8) end
    function Value.ValueExprSelect:lower_c_stencil_point(state)
        return Stencil.StencilPointSelect(Stencil.StencilPredNonZero, self.cond:lower_c_stencil_point(state), self.t:lower_c_stencil_point(state), self.f:lower_c_stencil_point(state), self:lower_c_stencil_point_ty(state))
    end

    function Stencil.StencilBinaryOp:lower_c_core_binary_op()
        error("lower_to_c: StencilBinaryOp cannot be emitted by CMat inline", 2)
    end
    function Stencil.StencilUnaryOp:lower_c_core_unary_op() error("lower_to_c: unary op cannot be represented as a C helper", 2) end
    function Stencil.StencilUnaryIdentity:lower_c_core_unary_op() return nil end
    function Stencil.StencilUnaryNeg:lower_c_core_unary_op() return Core.UnaryNeg end
    function Stencil.StencilUnaryBitNot:lower_c_core_unary_op() return Core.UnaryBitNot end
    function Stencil.StencilUnaryBoolNot:lower_c_core_unary_op() return Core.UnaryNot end

    function Stencil.StencilBinaryAdd:lower_c_core_binary_op() return Core.BinAdd end
    function Stencil.StencilBinarySub:lower_c_core_binary_op() return Core.BinSub end
    function Stencil.StencilBinaryMul:lower_c_core_binary_op() return Core.BinMul end
    function Stencil.StencilBinaryDiv:lower_c_core_binary_op() return Core.BinDiv end
    function Stencil.StencilBinaryMod:lower_c_core_binary_op() return Core.BinRem end
    function Stencil.StencilBinaryAnd:lower_c_core_binary_op() return Core.BinBitAnd end
    function Stencil.StencilBinaryOr:lower_c_core_binary_op() return Core.BinBitOr end
    function Stencil.StencilBinaryXor:lower_c_core_binary_op() return Core.BinBitXor end
    function Stencil.StencilBinaryShl:lower_c_core_binary_op() return Core.BinShl end
    function Stencil.StencilBinaryLShr:lower_c_core_binary_op() return Core.BinLShr end
    function Stencil.StencilBinaryAShr:lower_c_core_binary_op() return Core.BinAShr end

    function Stencil.StencilBinaryOp:lower_c_inline_binary(c_emission, lhs, rhs, ty, sem)
        local dst = tmp(c_emission, "cmat_bin", ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, binary_helper(c_emission, self:lower_c_core_binary_op(), ty, sem), { lhs, rhs })
        return C.CBackendAtomLocal(dst), ty
    end
    function Stencil.StencilBinaryMin:lower_c_inline_binary(c_emission, lhs, rhs, ty, _sem)
        local cond = tmp(c_emission, "cmat_min_cmp", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(cond, C.CBackendRCompare(Core.CmpLt, c_ty(c_emission, ty), lhs, rhs))
        local dst = tmp(c_emission, "cmat_min", ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRSelect(c_ty(c_emission, ty), C.CBackendAtomLocal(cond), lhs, rhs))
        return C.CBackendAtomLocal(dst), ty
    end
    function Stencil.StencilBinaryMax:lower_c_inline_binary(c_emission, lhs, rhs, ty, _sem)
        local cond = tmp(c_emission, "cmat_max_cmp", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(cond, C.CBackendRCompare(Core.CmpGt, c_ty(c_emission, ty), lhs, rhs))
        local dst = tmp(c_emission, "cmat_max", ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRSelect(c_ty(c_emission, ty), C.CBackendAtomLocal(cond), lhs, rhs))
        return C.CBackendAtomLocal(dst), ty
    end

    function Stencil.StencilAliasFact:lower_c_is_noalias() return false end
    function Stencil.StencilAliasNoAlias:lower_c_is_noalias() return true end
    function Stencil.StencilFusionLegalityFact:lower_c_access_noalias(_left, _right) return false end
    function Stencil.StencilFusionAccessAliasRelation:lower_c_access_noalias(left, right)
        local direct = self.left.name == left.name and self.right.name == right.name
        local reverse = self.left.name == right.name and self.right.name == left.name
        return (direct or reverse) and self.relation:lower_c_is_noalias()
    end
    function Stencil.StencilFusionLegality:lower_c_access_noalias(left, right)
        for _, fact in ipairs(self.facts or {}) do if fact:lower_c_access_noalias(left, right) then return true end end
        return false
    end
    function Stencil.StencilComputation:lower_c_access_restrict_proven(access)
        local seen_other = false
        for _, other in ipairs(self.accesses or {}) do
            if other.name ~= access.name then
                seen_other = true
                if not self.legality:lower_c_access_noalias(Stencil.StencilAccessRef(access.name), Stencil.StencilAccessRef(other.name)) then return false end
            end
        end
        return seen_other
    end
    local function note_cmat_param_qualifiers(c_emission, computation, bindings)
        c_emission.c_param_qualifiers = c_emission.c_param_qualifiers or {}
        for _, binding in ipairs(bindings or {}) do
            if binding.restrict_eligible and computation:lower_c_access_restrict_proven(binding.source) then
                local q = c_emission.c_param_qualifiers[binding.local_id.text] or { restrict_ptr = false }
                q.restrict_ptr = true
                c_emission.c_param_qualifiers[binding.local_id.text] = q
            end
        end
    end

    function CMat.CMatAccessBinding:lower_c_inline_load(c_emission, index_atom)
        local dst = tmp(c_emission, "cmat_load", self.ty)
        local place = C.CBackendPlacePtrIndex(C.CBackendAtomLocal(C.CBackendLocalId(self.local_id.text)), index_atom, c_ty(c_emission, self.ty), 1)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(dst, place)
        return C.CBackendAtomLocal(dst), self.ty
    end
    function CMat.CMatAccessBinding:lower_c_inline_store(c_emission, index_atom, value)
        local place = C.CBackendPlacePtrIndex(C.CBackendAtomLocal(C.CBackendLocalId(self.local_id.text)), index_atom, c_ty(c_emission, self.ty), 1)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceStore(place, value)
    end

    function CMat.CMatInlineProjection:lookup_access(access)
        for _, entry in ipairs(self.accesses) do
            if entry.name == access.name then return CMat.CMatAccessFound(entry.binding) end
        end
        return CMat.CMatAccessMissing(access, "CMat access is not bound")
    end
    function CMat.CMatInlineProjection:lookup_stream(stream)
        for _, entry in ipairs(self.streams) do
            if entry.id == stream then return CMat.CMatStreamFound(entry.stream) end
        end
        return CMat.CMatStreamMissing(stream, "CMat stream is not defined")
    end
    function CMat.CMatAccessFound:lower_c_inline_load(c_emission, index_atom) return self.binding:lower_c_inline_load(c_emission, index_atom) end
    function CMat.CMatAccessFound:lower_c_inline_store(c_emission, index_atom, value) return self.binding:lower_c_inline_store(c_emission, index_atom, value) end
    function CMat.CMatAccessFound:lower_c_inline_type() return self.binding.ty end
    function CMat.CMatAccessFound:lower_c_inline_local_id() return self.binding.local_id end
    function CMat.CMatStreamFound:lower_c_inline_stream(c_emission, cmat, index_atom) return self.stream:lower_c_inline_stream(c_emission, cmat, index_atom) end

    function Stencil.StencilPointExpr:lower_c_inline_point(_c_emission, _cmat, _index_atom)
        error("lower_to_c: unsupported inline CMat point expression", 2)
    end
    function Stencil.StencilPointInput:lower_c_inline_point(c_emission, cmat, index_atom)
        return cmat:lookup_access(self.access):lower_c_inline_load(c_emission, index_atom)
    end
    function Stencil.StencilWindowBoundaryClamp:lower_c_inline_window_index(c_emission, axis, index_atom, offset)
        local start, start_ty = lower_value_expr(c_emission, axis.start)
        local stop, stop_ty = lower_value_expr(c_emission, axis.stop)
        start = cast_to(c_emission, start, start_ty, Code.CodeTyIndex, "cmat_window_start")
        stop = cast_to(c_emission, stop, stop_ty, Code.CodeTyIndex, "cmat_window_stop")
        local current = tmp(c_emission, "cmat_window_current", Code.CodeTyIndex)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(current, binary_helper(c_emission, Core.BinAdd, Code.CodeTyIndex, nil), { start, index_atom })
        local shifted = tmp(c_emission, "cmat_window_shifted", Code.CodeTyIndex)
        local offset_atom = C.CBackendAtomLiteral(c_ty(c_emission, Code.CodeTyIndex), Core.LitInt(tostring(offset)))
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(shifted, binary_helper(c_emission, Core.BinAdd, Code.CodeTyIndex, nil), { C.CBackendAtomLocal(current), offset_atom })
        local below = tmp(c_emission, "cmat_window_below", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(below, C.CBackendRCompare(Core.CmpLt, c_ty(c_emission, Code.CodeTyIndex), C.CBackendAtomLocal(shifted), start))
        local low_clamped = tmp(c_emission, "cmat_window_low", Code.CodeTyIndex)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(low_clamped, C.CBackendRSelect(c_ty(c_emission, Code.CodeTyIndex), C.CBackendAtomLocal(below), start, C.CBackendAtomLocal(shifted)))
        local last = tmp(c_emission, "cmat_window_last", Code.CodeTyIndex)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(last, binary_helper(c_emission, Core.BinSub, Code.CodeTyIndex, nil), { stop, C.CBackendAtomLiteral(c_ty(c_emission, Code.CodeTyIndex), Core.LitInt("1")) })
        local above = tmp(c_emission, "cmat_window_above", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(above, C.CBackendRCompare(Core.CmpGt, c_ty(c_emission, Code.CodeTyIndex), C.CBackendAtomLocal(low_clamped), C.CBackendAtomLocal(last)))
        local clamped = tmp(c_emission, "cmat_window_clamped", Code.CodeTyIndex)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(clamped, C.CBackendRSelect(c_ty(c_emission, Code.CodeTyIndex), C.CBackendAtomLocal(above), C.CBackendAtomLocal(last), C.CBackendAtomLocal(low_clamped)))
        return C.CBackendAtomLocal(clamped)
    end
    function CMat.CMatWindowLayout1D:lower_c_inline_window_point(c_emission, cmat, index_atom, access, offset)
        local window_index = self.window.boundary:lower_c_inline_window_index(c_emission, self.axis, index_atom, offset)
        return cmat:lookup_access(access):lower_c_inline_load(c_emission, window_index)
    end
    function Stencil.StencilPointWindowInput:lower_c_inline_point(c_emission, cmat, index_atom)
        return cmat.window:lower_c_inline_window_point(c_emission, cmat, index_atom, self.access, self.offsets[1].offset)
    end
    function Stencil.StencilPointConst:lower_c_inline_point(c_emission) return lower_value_expr(c_emission, self.value) end
    function Stencil.StencilPointUnary:lower_c_inline_point(c_emission, cmat, index_atom)
        local value, vty = self.arg:lower_c_inline_point(c_emission, cmat, index_atom)
        local ty = self.result_ty or vty
        local op = self.op:lower_c_core_unary_op()
        if op == nil then return value, ty end
        local dst = tmp(c_emission, "cmat_un", ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(dst, unary_helper(c_emission, op, ty), { value })
        return C.CBackendAtomLocal(dst), ty
    end
    function Stencil.StencilPointBinary:lower_c_inline_point(c_emission, cmat, index_atom)
        local a, aty = self.left:lower_c_inline_point(c_emission, cmat, index_atom)
        local b, bty = self.right:lower_c_inline_point(c_emission, cmat, index_atom)
        local ty = self.result_ty or aty or bty
        a = cast_to(c_emission, a, aty, ty, "cmat_bin_lhs_cast")
        b = cast_to(c_emission, b, bty, ty, "cmat_bin_rhs_cast")
        return self.op:lower_c_inline_binary(c_emission, a, b, ty, self.int_semantics)
    end
    function Stencil.StencilPointCast:lower_c_inline_point(c_emission, cmat, index_atom)
        local src = self.arg:lower_c_inline_point(c_emission, cmat, index_atom)
        local dst = tmp(c_emission, "cmat_cast", self.to)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRCast(self.op, c_ty(c_emission, self.to), src))
        return C.CBackendAtomLocal(dst), self.to
    end
    function Stencil.StencilPointCompare:lower_c_inline_point(c_emission, cmat, index_atom)
        local a, aty = self.left:lower_c_inline_point(c_emission, cmat, index_atom)
        local b, bty = self.right:lower_c_inline_point(c_emission, cmat, index_atom)
        local ty = aty or bty
        a = cast_to(c_emission, a, aty, ty, "cmat_cmp_lhs_cast")
        b = cast_to(c_emission, b, bty, ty, "cmat_cmp_rhs_cast")
        local dst = tmp(c_emission, "cmat_cmp", self.result_ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRCompare(self.cmp, c_ty(c_emission, ty), a, b))
        return C.CBackendAtomLocal(dst), self.result_ty
    end
    function Stencil.StencilPointSelect:lower_c_inline_point(c_emission, cmat, index_atom)
        local cond_value, cty = self.cond:lower_c_inline_point(c_emission, cmat, index_atom)
        local cond = self.pred:lower_c_inline_pred(c_emission, cmat, index_atom, cond_value, cty)
        local t, tty = self.then_expr:lower_c_inline_point(c_emission, cmat, index_atom)
        local f, fty = self.else_expr:lower_c_inline_point(c_emission, cmat, index_atom)
        local ty = self.result_ty or tty or fty
        t = cast_to(c_emission, t, tty, ty, "cmat_select_then")
        f = cast_to(c_emission, f, fty, ty, "cmat_select_else")
        local dst = tmp(c_emission, "cmat_select", ty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRSelect(c_ty(c_emission, ty), cond, t, f))
        return C.CBackendAtomLocal(dst), ty
    end

    local function bool_literal(c_emission, value)
        return C.CBackendAtomLiteral(c_ty(c_emission, Code.CodeTyBool8), Core.LitBool(value))
    end

    local function emit_bool_select(c_emission, prefix, cond, then_atom, else_atom)
        local dst = tmp(c_emission, prefix, Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRSelect(c_ty(c_emission, Code.CodeTyBool8), cond, then_atom, else_atom))
        return C.CBackendAtomLocal(dst), Code.CodeTyBool8
    end

    function Stencil.StencilPredicate:lower_c_inline_pred(_c_emission, _cmat, _index_atom, _value, _ty)
        error("lower_to_c: unsupported StencilPredicate for inline CMat", 2)
    end
    function Stencil.StencilPredNonZero:lower_c_inline_pred(c_emission, _cmat, _index_atom, value, ty)
        local zero = C.CBackendAtomLiteral(c_ty(c_emission, ty), Core.LitInt("0"))
        local dst = tmp(c_emission, "cmat_pred_nonzero", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRCompare(Core.CmpNe, c_ty(c_emission, ty), value, zero))
        return C.CBackendAtomLocal(dst), Code.CodeTyBool8
    end
    function Stencil.StencilPredCompareConst:lower_c_inline_pred(c_emission, _cmat, _index_atom, value, ty)
        local rhs, rty = lower_value_expr(c_emission, self.value)
        rhs = cast_to(c_emission, rhs, rty, self.operand_ty or ty, "cmat_pred_const_cast")
        value = cast_to(c_emission, value, ty, self.operand_ty or ty, "cmat_pred_value_cast")
        local dst = tmp(c_emission, "cmat_pred_cmp", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRCompare(self.cmp, c_ty(c_emission, self.operand_ty or ty), value, rhs))
        return C.CBackendAtomLocal(dst), Code.CodeTyBool8
    end
    function Stencil.StencilPredRange:lower_c_inline_pred(c_emission, _cmat, _index_atom, value, ty)
        local pty = self.operand_ty or ty
        local lower, lty = lower_value_expr(c_emission, self.lower)
        local upper, uty = lower_value_expr(c_emission, self.upper)
        value = cast_to(c_emission, value, ty, pty, "cmat_pred_range_value")
        lower = cast_to(c_emission, lower, lty, pty, "cmat_pred_range_lower")
        upper = cast_to(c_emission, upper, uty, pty, "cmat_pred_range_upper")
        local lo = tmp(c_emission, "cmat_pred_range_lo", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(lo, C.CBackendRCompare(self.lower_cmp, c_ty(c_emission, pty), lower, value))
        local hi = tmp(c_emission, "cmat_pred_range_hi", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(hi, C.CBackendRCompare(self.upper_cmp, c_ty(c_emission, pty), value, upper))
        return emit_bool_select(c_emission, "cmat_pred_range", C.CBackendAtomLocal(lo), C.CBackendAtomLocal(hi), bool_literal(c_emission, false))
    end
    function Stencil.StencilPredAnd:lower_c_inline_pred(c_emission, cmat, index_atom, value, ty)
        local acc = bool_literal(c_emission, true)
        for _, term in ipairs(self.terms or {}) do
            local next_atom = term:lower_c_inline_pred(c_emission, cmat, index_atom, value, ty)
            acc = emit_bool_select(c_emission, "cmat_pred_and", acc, next_atom, bool_literal(c_emission, false))
        end
        return acc, Code.CodeTyBool8
    end
    function Stencil.StencilPredOr:lower_c_inline_pred(c_emission, cmat, index_atom, value, ty)
        local acc = bool_literal(c_emission, false)
        for _, term in ipairs(self.terms or {}) do
            local next_atom = term:lower_c_inline_pred(c_emission, cmat, index_atom, value, ty)
            acc = emit_bool_select(c_emission, "cmat_pred_or", acc, bool_literal(c_emission, true), next_atom)
        end
        return acc, Code.CodeTyBool8
    end
    function Stencil.StencilPredNot:lower_c_inline_pred(c_emission, cmat, index_atom, value, ty)
        local pred = self.term:lower_c_inline_pred(c_emission, cmat, index_atom, value, ty)
        return emit_bool_select(c_emission, "cmat_pred_not", pred, bool_literal(c_emission, false), bool_literal(c_emission, true))
    end

    function Stencil.StencilPointPredicate:lower_c_inline_point(c_emission, cmat, index_atom)
        local value, ty = self.arg:lower_c_inline_point(c_emission, cmat, index_atom)
        local pred = self.pred:lower_c_inline_pred(c_emission, cmat, index_atom, value, ty)
        return cast_to(c_emission, pred, Code.CodeTyBool8, self.result_ty, "cmat_pred_result")
    end

    function Stencil.StencilAccessRef:lower_c_binding(cmat) return cmat:lookup_access(self) end

    function Stencil.StencilIndexExpr:lower_c_inline_index(_c_emission, _cmat, index_atom)
        return index_atom, Code.CodeTyIndex
    end
    function Stencil.StencilIndexAxis:lower_c_inline_index(_c_emission, _cmat, index_atom)
        return index_atom, Code.CodeTyIndex
    end
    function Stencil.StencilIndexStream:lower_c_inline_index(c_emission, cmat, index_atom)
        return self.stream:lower_c_inline_stream(c_emission, cmat, index_atom)
    end
    function Stencil.StencilIndexPoint:lower_c_inline_index(c_emission, _cmat, _index_atom)
        return lower_value_expr(c_emission, self.expr)
    end

    function Stencil.StencilStreamRef:lower_c_inline_stream(c_emission, cmat, index_atom)
        return cmat:lookup_stream(self.stream):lower_c_inline_stream(c_emission, cmat, index_atom)
    end
    function Stencil.StencilStreamDef:lower_c_inline_stream(c_emission, cmat, index_atom)
        return self.op:lower_c_inline_stream(c_emission, cmat, index_atom, self.ty)
    end
    function Stencil.StencilStreamOp:lower_c_inline_stream(_c_emission, _cmat, _index_atom, _ty)
        error("lower_to_c: unsupported StencilStreamOp for inline CMat", 2)
    end
    function Stencil.StencilStreamIndex:lower_c_inline_stream(_c_emission, _cmat, index_atom, _ty)
        return index_atom, Code.CodeTyIndex
    end
    function Stencil.StencilStreamAccess:lower_c_inline_stream(c_emission, cmat, index_atom, _ty)
        local idx = index_atom
        if self.index ~= nil then idx = self.index:lower_c_inline_index(c_emission, cmat, index_atom) end
        return self.access:lower_c_binding(cmat):lower_c_inline_load(c_emission, idx)
    end
    function Stencil.StencilStreamWindowAccess:lower_c_inline_stream()
        error("lower_to_c: window access requires CMat window producer materialization", 2)
    end
    function Stencil.StencilStreamConst:lower_c_inline_stream(c_emission, _cmat, _index_atom, _ty)
        return lower_value_expr(c_emission, self.value)
    end
    function Stencil.StencilStreamMap:lower_c_inline_stream(c_emission, cmat, index_atom, _ty)
        return self.expr:lower_c_inline_point(c_emission, cmat, index_atom)
    end
    function Stencil.StencilStreamZip:lower_c_inline_stream()
        error("lower_to_c: zip stream is a structural stream group and cannot be consumed as one scalar", 2)
    end
    function Stencil.StencilStreamSelect:lower_c_inline_stream(c_emission, cmat, index_atom, ty)
        local pred, pty = self.pred:lower_c_inline_stream(c_emission, cmat, index_atom)
        local t, tty = self.then_stream:lower_c_inline_stream(c_emission, cmat, index_atom)
        local f, fty = self.else_stream:lower_c_inline_stream(c_emission, cmat, index_atom)
        local dst = tmp(c_emission, "cmat_select", ty or tty or fty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRSelect(c_ty(c_emission, ty or tty or fty), cast_to(c_emission, pred, pty, Code.CodeTyBool8, "cmat_select_pred"), t, f))
        return C.CBackendAtomLocal(dst), ty or tty or fty
    end
    function Stencil.StencilStreamMask:lower_c_inline_stream(c_emission, cmat, index_atom, ty)
        local pred, pty = self.pred:lower_c_inline_stream(c_emission, cmat, index_atom)
        local value, vty = self.value:lower_c_inline_stream(c_emission, cmat, index_atom)
        local masked, mty = self.masked_value:lower_c_inline_stream(c_emission, cmat, index_atom)
        local dst = tmp(c_emission, "cmat_mask", ty or vty or mty)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(dst, C.CBackendRSelect(c_ty(c_emission, ty or vty or mty), cast_to(c_emission, pred, pty, Code.CodeTyBool8, "cmat_mask_pred"), value, masked))
        return C.CBackendAtomLocal(dst), ty or vty or mty
    end
    function Stencil.StencilStreamGather:lower_c_inline_stream(c_emission, cmat, index_atom, _ty)
        local idx = self.index_stream:lower_c_inline_stream(c_emission, cmat, index_atom)
        return self.source:lower_c_binding(cmat):lower_c_inline_load(c_emission, idx)
    end

    function Stencil.StencilSinkDef:lower_c_inline_sink(c_emission, cmat, index_atom)
        return self.op:lower_c_inline_sink(c_emission, cmat, index_atom)
    end
    function Stencil.StencilSinkOp:lower_c_inline_sink(_c_emission, _cmat, _index_atom)
        error("lower_to_c: unsupported StencilSinkOp for inline CMat", 2)
    end
    function Stencil.StencilSinkOpStore:lower_c_inline_sink(c_emission, cmat, index_atom)
        local dst = self.dst:lower_c_binding(cmat)
        local value, vty = self.value:lower_c_inline_stream(c_emission, cmat, index_atom)
        value = cast_to(c_emission, value, vty, dst:lower_c_inline_type(), "cmat_store_cast")
        dst:lower_c_inline_store(c_emission, index_atom, value)
        return CMat.CMatInlineNoControl
    end

    function Value.ReductionOp:lower_c_inline_reduce_update(_c_emission, _acc, _value, _ty, _sem)
        error("lower_to_c: reduction op cannot be emitted by inline CMat", 2)
    end
    function Value.ReductionAdd:lower_c_inline_reduce_update(c_emission, acc, value, ty, sem)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(acc, binary_helper(c_emission, Core.BinAdd, ty, sem), { C.CBackendAtomLocal(acc), value })
    end
    function Value.ReductionMul:lower_c_inline_reduce_update(c_emission, acc, value, ty, sem)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(acc, binary_helper(c_emission, Core.BinMul, ty, sem), { C.CBackendAtomLocal(acc), value })
    end
    function Value.ReductionAnd:lower_c_inline_reduce_update(c_emission, acc, value, ty, sem)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(acc, binary_helper(c_emission, Core.BinBitAnd, ty, sem), { C.CBackendAtomLocal(acc), value })
    end
    function Value.ReductionOr:lower_c_inline_reduce_update(c_emission, acc, value, ty, sem)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(acc, binary_helper(c_emission, Core.BinBitOr, ty, sem), { C.CBackendAtomLocal(acc), value })
    end
    function Value.ReductionXor:lower_c_inline_reduce_update(c_emission, acc, value, ty, sem)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendHelperCall(acc, binary_helper(c_emission, Core.BinBitXor, ty, sem), { C.CBackendAtomLocal(acc), value })
    end
    function Value.ReductionMin:lower_c_inline_reduce_update(c_emission, acc, value, ty, _sem)
        local cond = tmp(c_emission, "cmat_reduce_min_cmp", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(cond, C.CBackendRCompare(Core.CmpLt, c_ty(c_emission, ty), value, C.CBackendAtomLocal(acc)))
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(acc, C.CBackendRSelect(c_ty(c_emission, ty), C.CBackendAtomLocal(cond), value, C.CBackendAtomLocal(acc)))
    end
    function Value.ReductionMax:lower_c_inline_reduce_update(c_emission, acc, value, ty, _sem)
        local cond = tmp(c_emission, "cmat_reduce_max_cmp", Code.CodeTyBool8)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(cond, C.CBackendRCompare(Core.CmpGt, c_ty(c_emission, ty), value, C.CBackendAtomLocal(acc)))
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(acc, C.CBackendRSelect(c_ty(c_emission, ty), C.CBackendAtomLocal(cond), value, C.CBackendAtomLocal(acc)))
    end

    function Stencil.StencilScanMode:lower_c_scan_store_before_update() return false end
    function Stencil.StencilScanExclusive:lower_c_scan_store_before_update() return true end
    function Stencil.StencilScanInclusive:lower_c_scan_store_before_update() return false end

    function CMat.CMatInlineAccumulatorLocal:lower_c_fold_sink(op, c_emission, cmat, index_atom)
        local value, vty = op.value:lower_c_inline_stream(c_emission, cmat, index_atom)
        value = cast_to(c_emission, value, vty, op.reducer.result_ty, "cmat_reduce_cast")
        op.reducer.reduction:lower_c_inline_reduce_update(c_emission, self.local_id, value, op.reducer.result_ty, op.reducer.int_semantics)
        return CMat.CMatInlineNoControl
    end
    function Stencil.StencilSinkOpFold:lower_c_inline_sink(c_emission, cmat, index_atom)
        return cmat.accumulator:lower_c_fold_sink(self, c_emission, cmat, index_atom)
    end

    function CMat.CMatInlineAccumulatorLocal:lower_c_scan_sink(op, c_emission, cmat, index_atom)
        local dst = op.dst:lower_c_binding(cmat)
        local value, vty = op.value:lower_c_inline_stream(c_emission, cmat, index_atom)
        value = cast_to(c_emission, value, vty, op.reducer.result_ty, "cmat_scan_cast")
        if op.mode:lower_c_scan_store_before_update() then
            dst:lower_c_inline_store(c_emission, index_atom, C.CBackendAtomLocal(self.local_id))
            op.reducer.reduction:lower_c_inline_reduce_update(c_emission, self.local_id, value, op.reducer.result_ty, op.reducer.int_semantics)
        else
            op.reducer.reduction:lower_c_inline_reduce_update(c_emission, self.local_id, value, op.reducer.result_ty, op.reducer.int_semantics)
            dst:lower_c_inline_store(c_emission, index_atom, C.CBackendAtomLocal(self.local_id))
        end
        return CMat.CMatInlineNoControl
    end
    function Stencil.StencilSinkOpScan:lower_c_inline_sink(c_emission, cmat, index_atom)
        return cmat.accumulator:lower_c_scan_sink(self, c_emission, cmat, index_atom)
    end

    function Stencil.StencilSinkOpScatterStore:lower_c_inline_sink(c_emission, cmat, index_atom)
        local dst = self.dst:lower_c_binding(cmat)
        local scatter_index, index_ty = self.index:lower_c_inline_stream(c_emission, cmat, index_atom)
        scatter_index = cast_to(c_emission, scatter_index, index_ty, Code.CodeTyIndex, "cmat_scatter_index_cast")
        local value, vty = self.value:lower_c_inline_stream(c_emission, cmat, index_atom)
        value = cast_to(c_emission, value, vty, dst:lower_c_inline_type(), "cmat_scatter_store_cast")
        dst:lower_c_inline_store(c_emission, scatter_index, value)
        return CMat.CMatInlineNoControl
    end

    function Stencil.StencilSinkOpScatterFold:lower_c_inline_sink(c_emission, cmat, index_atom)
        local dst = self.dst:lower_c_binding(cmat)
        local scatter_index, index_ty = self.index:lower_c_inline_stream(c_emission, cmat, index_atom)
        scatter_index = cast_to(c_emission, scatter_index, index_ty, Code.CodeTyIndex, "cmat_scatter_index_cast")
        local old = tmp(c_emission, "cmat_scatter_old", self.reducer.result_ty)
        local dst_local = dst:lower_c_inline_local_id()
        local place = C.CBackendPlacePtrIndex(C.CBackendAtomLocal(C.CBackendLocalId(dst_local.text)), scatter_index, c_ty(c_emission, self.reducer.result_ty), 1)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(old, place)
        local value, vty = self.value:lower_c_inline_stream(c_emission, cmat, index_atom)
        value = cast_to(c_emission, value, vty, self.reducer.result_ty, "cmat_scatter_reduce_cast")
        self.reducer.reduction:lower_c_inline_reduce_update(c_emission, old, value, self.reducer.result_ty, self.reducer.int_semantics)
        c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceStore(place, C.CBackendAtomLocal(old))
        return CMat.CMatInlineNoControl
    end

    local function lower_control_predicate_sink(op, c_emission, cmat, index_atom)
        local value, vty = op.src:lower_c_inline_stream(c_emission, cmat, index_atom)
        local pred = op.pred:lower_c_inline_pred(c_emission, cmat, index_atom, value, vty)
        return CMat.CMatInlineControl(pred)
    end
    function Stencil.StencilSinkOpAll:lower_c_inline_sink(c_emission, cmat, index_atom)
        return lower_control_predicate_sink(self, c_emission, cmat, index_atom)
    end
    function Stencil.StencilSinkOpAny:lower_c_inline_sink(c_emission, cmat, index_atom)
        return lower_control_predicate_sink(self, c_emission, cmat, index_atom)
    end
    function Stencil.StencilSinkOpFind:lower_c_inline_sink(c_emission, cmat, index_atom)
        return lower_control_predicate_sink(self, c_emission, cmat, index_atom)
    end

    function Stencil.StencilComputation:lower_c_inline_computation(c_emission, cmat, index_atom)
        local result = CMat.CMatInlineNoControl
        for _, sink in ipairs(self.sinks or {}) do result = sink:lower_c_inline_sink(c_emission, cmat, index_atom) end
        return result
    end
    function CMat.CMatInlineControl:lower_c_control_predicate() return self.predicate end

    local function default_stencil_schedule()
        return Stencil.StencilScheduleScalar(Stencil.StencilCompilerPolicy(Stencil.StencilCompilerGcc, Stencil.StencilOptO3, Stencil.StencilMachineNative, {}))
    end

    local function resolve_schedule(kernel_id, schedules_by_id)
        local kplan_sched = schedules_by_id and schedules_by_id[kernel_id.text]
        if not kplan_sched then return nil end
        if asdl.classof(kplan_sched) == Schedule.SchedulePlanned then
            return kplan_sched.form
        end
        return nil
    end

    local function schedule_index(schedules)
        local out = {}
        if schedules == nil then return out end
        for _, ks in ipairs(schedules.kernel_schedules or {}) do
            out[ks.kernel.text] = ks
        end
        return out
    end

    function Flow.FlowDomainOrder:lower_c_stencil_order() return Stencil.StencilProducerForward end
    function Flow.FlowDomainForward:lower_c_stencil_order() return Stencil.StencilProducerForward end
    function Flow.FlowDomainBackward:lower_c_stencil_order() return Stencil.StencilProducerBackward end
    function Flow.FlowDomainAxis:lower_c_stencil_axis()
        return Stencil.StencilProducerAxis(self.index_ty, self.start, self.stop, self.step, self.order:lower_c_stencil_order(), self.index_name)
    end
    function Flow.FlowWindowBoundaryReject:lower_c_stencil_boundary() return Stencil.StencilWindowBoundaryReject end
    function Flow.FlowWindowBoundaryClamp:lower_c_stencil_boundary() return Stencil.StencilWindowBoundaryClamp end
    function Flow.FlowWindowBoundaryWrap:lower_c_stencil_boundary() return Stencil.StencilWindowBoundaryWrap end
    function Flow.FlowWindowBoundaryZero:lower_c_stencil_boundary() return Stencil.StencilWindowBoundaryZero end
    function Flow.FlowWindowAxis:lower_c_stencil_window_axis()
        return Stencil.StencilWindowAxis(self.before, self.after, self.boundary:lower_c_stencil_boundary())
    end
    local function lower_c_stencil_axes(axes)
        local out = {}
        for i, axis in ipairs(axes) do out[i] = axis:lower_c_stencil_axis() end
        return out
    end
    function Flow.FlowDomainShapeRange1D:lower_c_stencil_shape()
        return Stencil.StencilProduceRange1D(self.index_ty, self.start, self.stop, self.step, self.order:lower_c_stencil_order())
    end
    function Flow.FlowDomainShapeRangeND:lower_c_stencil_shape() return Stencil.StencilProduceRangeND(lower_c_stencil_axes(self.axes)) end
    function Flow.FlowDomainShapeTiledND:lower_c_stencil_shape() return Stencil.StencilProduceTiledND(lower_c_stencil_axes(self.axes), self.tile_sizes) end
    function Flow.FlowDomainShapeWindowND:lower_c_stencil_shape()
        local windows = {}
        for i, window in ipairs(self.windows) do windows[i] = window:lower_c_stencil_window_axis() end
        return Stencil.StencilProduceWindowND(lower_c_stencil_axes(self.axes), windows)
    end

    local function producer_from_loop(c_emission, loop_fact)
        if loop_fact ~= nil then
            for _, fact in ipairs(c_emission.flow.domain_shapes or {}) do
                if fact.domain == loop_fact.domain then
                    return Stencil.StencilProducer(loop_fact.domain, fact.shape:lower_c_stencil_shape())
                end
            end
        end
        local counted = loop_fact and loop_fact.counted
        if counted == nil then return Stencil.StencilProducer(nil, Stencil.StencilProduceRange1D(Code.CodeTyIndex, nil, nil, 1, Stencil.StencilProducerForward)) end
        return Stencil.StencilProducer(
            loop_fact.domain,
            Stencil.StencilProduceRange1D(Code.CodeTyIndex, Value.ValueExprValue(counted.start), Value.ValueExprValue(counted.stop), 1, Stencil.StencilProducerForward)
        )
    end

    local function computation_for_body(c_emission, kplan, loop_fact, reads, dst, body_stream, sink, sched)
        local accesses, streams, sinks = {}, {}, {}
        if dst ~= nil then accesses[#accesses + 1] = dst.source end
        for _, access in ipairs(reads or {}) do accesses[#accesses + 1] = access.source end
        streams[#streams + 1] = body_stream
        sinks[#sinks + 1] = sink
        return Stencil.StencilComputation(
            Stencil.StencilMetastencilId("cmat:" .. sanitize(kplan.id.text) .. ":" .. sanitize(sink.id.text)),
            producer_from_loop(c_emission, loop_fact),
            accesses,
            streams,
            sinks,
            Stencil.StencilFusionLegality({}, {}, {}),
            sched or default_stencil_schedule(),
            kplan.body.equivalence and kplan.body.equivalence.proofs or {}
        )
    end

    local function cmat_bindings(dst, reads)
        local out = {}
        if dst ~= nil then out[#out + 1] = dst end
        for _, access in ipairs(reads or {}) do out[#out + 1] = access end
        return out
    end

    function CMat.CMatMaterializedFused:lower_c_inline_projection(computation, bindings, window)
        local accesses = {}
        for i, binding in ipairs(bindings) do accesses[i] = CMat.CMatAccessNameEntry(binding.access.name, binding) end
        local streams = {}
        for i, stream in ipairs(computation.streams) do streams[i] = CMat.CMatStreamEntry(stream.id, stream) end
        return CMat.CMatInlineProjection(self.kernel, computation, accesses, streams, window, CMat.CMatInlineNoAccumulator)
    end
    function CMat.CMatInlineProjection:with_accumulator(local_id)
        return CMat.CMatInlineProjection(self.kernel, self.computation, self.accesses, self.streams, self.window, CMat.CMatInlineAccumulatorLocal(local_id))
    end
    local function cmat_inline_projection_for_computation(computation, bindings)
        local materialized = computation:cmat_materialize()
        local window = computation.producer.shape:lower_c_window_layout(CMat.CMatWindowNoCounter)
        return materialized:lower_c_inline_projection(computation, bindings, window)
    end

    local function cmat_store_kernel_from_expr(c_emission, kplan, loop_fact, dst_lane, reads, expr, store_mode)
        local dst = cmat_access_binding_for_lane(dst_lane, "dst", Stencil.StencilAccessWrite)
        local stream = Stencil.StencilStreamDef(Stencil.StencilStreamId("value"), dst_lane.elem_ty, Stencil.StencilStreamMap(expr, {}))
        local sink = Stencil.StencilSinkDef(Stencil.StencilSinkId("store"), Stencil.StencilSinkOpStore(dst.access, Stencil.StencilStreamRef(stream.id), store_mode))
        local computation = computation_for_body(c_emission, kplan, loop_fact, reads, dst, stream, sink, c_emission.cmat_schedule)
        note_cmat_param_qualifiers(c_emission, computation, cmat_bindings(dst, reads))
        return cmat_inline_projection_for_computation(computation, cmat_bindings(dst, reads))
    end

    local function cmat_read_bindings(projection)
        local reads = {}
        for i, entry in ipairs(projection.reads) do reads[i] = entry.access end
        return reads
    end

    local function cmat_store_kernel(c_emission, kplan, loop_fact, store)
        local projection = cmat_point_projection(kplan, producer_from_loop(c_emission, loop_fact), { store.value })
        local expr = store.value:lower_c_stencil_point(projection)
        return cmat_store_kernel_from_expr(c_emission, kplan, loop_fact, store.dst, cmat_read_bindings(projection), expr, Stencil.StencilStoreElementwise)
    end

    local function cmat_copy_kernel(c_emission, kplan, loop_fact, copy)
        local projection = cmat_point_projection(kplan, producer_from_loop(c_emission, loop_fact), { copy.src })
        local expr = copy.src:lower_c_stencil_point(projection)
        return cmat_store_kernel_from_expr(c_emission, kplan, loop_fact, copy.dst, cmat_read_bindings(projection), expr, Stencil.StencilStoreCopy(copy.semantics))
    end

    local function cmat_reduce_kernel(c_emission, kplan, loop_fact, reduction)
        local projection = cmat_point_projection(kplan, producer_from_loop(c_emission, loop_fact), { reduction.contribution })
        local reads = cmat_read_bindings(projection)
        local expr = reduction.contribution:lower_c_stencil_point(projection)
        local stream = Stencil.StencilStreamDef(Stencil.StencilStreamId("value"), reduction.ty, Stencil.StencilStreamMap(expr, {}))
        local reducer = Stencil.StencilReducer(reduction.op, reduction.ty, reduction.init, reduction.int_semantics, reduction.float_mode)
        local sink = Stencil.StencilSinkDef(Stencil.StencilSinkId("fold"), Stencil.StencilSinkOpFold(Stencil.StencilStreamRef(stream.id), reducer, reduction.ty, Stencil.StencilReduceInitExternal, nil))
        local computation = computation_for_body(c_emission, kplan, loop_fact, reads, nil, stream, sink, c_emission.cmat_schedule)
        note_cmat_param_qualifiers(c_emission, computation, reads)
        return cmat_inline_projection_for_computation(computation, reads)
    end

    local function cmat_scan_kernel(c_emission, kplan, loop_fact, scan)
        local reduction = scan.reduction
        local projection = cmat_point_projection(kplan, producer_from_loop(c_emission, loop_fact), { reduction.contribution })
        local reads = cmat_read_bindings(projection)
        local expr = reduction.contribution:lower_c_stencil_point(projection)
        local dst = cmat_access_binding_for_lane(scan.dst, "dst", Stencil.StencilAccessWrite)
        local stream = Stencil.StencilStreamDef(Stencil.StencilStreamId("value"), reduction.ty, Stencil.StencilStreamMap(expr, {}))
        local reducer = Stencil.StencilReducer(reduction.op, reduction.ty, reduction.init, reduction.int_semantics, reduction.float_mode)
        local sink = Stencil.StencilSinkDef(Stencil.StencilSinkId("scan"), Stencil.StencilSinkOpScan(dst.access, Stencil.StencilStreamRef(stream.id), reducer, scan.mode, scan.axis or Stencil.StencilAxisRef(1)))
        local computation = computation_for_body(c_emission, kplan, loop_fact, reads, dst, stream, sink, c_emission.cmat_schedule)
        note_cmat_param_qualifiers(c_emission, computation, cmat_bindings(dst, reads))
        return cmat_inline_projection_for_computation(computation, cmat_bindings(dst, reads))
    end

    local function cmat_scatter_reduce_kernel(c_emission, kplan, loop_fact, effect)
        local projection = cmat_point_projection(kplan, producer_from_loop(c_emission, loop_fact), { effect.value, effect.index })
        local reads = cmat_read_bindings(projection)
        local expr = effect.value:lower_c_stencil_point(projection)
        local scatter_index = effect.index:lower_c_stencil_point(projection)
        local dst = cmat_access_binding_for_lane(effect.dst, "dst", Stencil.StencilAccessReadWrite)
        local reducer = effect.reducer
        local value_stream = Stencil.StencilStreamDef(Stencil.StencilStreamId("value"), reducer.result_ty, Stencil.StencilStreamMap(expr, {}))
        local index_stream = Stencil.StencilStreamDef(Stencil.StencilStreamId("index"), Code.CodeTyIndex, Stencil.StencilStreamMap(scatter_index, {}))
        local sink = Stencil.StencilSinkDef(Stencil.StencilSinkId("scatter_fold"), Stencil.StencilSinkOpScatterFold(dst.access, Stencil.StencilStreamRef(index_stream.id), Stencil.StencilStreamRef(value_stream.id), reducer, Stencil.StencilScatterReduceSequential))
        local accesses, streams = { dst.source }, { value_stream, index_stream }
        for _, access in ipairs(reads) do accesses[#accesses + 1] = access.source end
        local computation = Stencil.StencilComputation(
            Stencil.StencilMetastencilId("cmat:" .. sanitize(kplan.id.text) .. ":scatter_fold"),
            producer_from_loop(c_emission, loop_fact), accesses, streams, { sink },
            Stencil.StencilFusionLegality({}, {}, {}), c_emission.cmat_schedule or default_stencil_schedule(),
            kplan.body.equivalence and kplan.body.equivalence.proofs or {})
        note_cmat_param_qualifiers(c_emission, computation, cmat_bindings(dst, reads))
        return cmat_inline_projection_for_computation(computation, cmat_bindings(dst, reads))
    end

    local function cmat_control_kernel(c_emission, kplan, loop_fact, result, op_name)
        local projection = cmat_point_projection(kplan, producer_from_loop(c_emission, loop_fact), { result.src })
        local reads = cmat_read_bindings(projection)
        local expr = result.src:lower_c_stencil_point(projection)
        local stream = Stencil.StencilStreamDef(Stencil.StencilStreamId("control"), result.src:lower_c_stencil_point_ty(projection), Stencil.StencilStreamMap(expr, {}))
        local stream_ref = Stencil.StencilStreamRef(stream.id)
        local op = op_name == "any" and Stencil.StencilSinkOpAny(stream_ref, result.pred)
            or (op_name == "find" and Stencil.StencilSinkOpFind(stream_ref, result.pred) or Stencil.StencilSinkOpAll(stream_ref, result.pred))
        local sink = Stencil.StencilSinkDef(Stencil.StencilSinkId(op_name or "all"), op)
        local accesses = {}
        for _, access in ipairs(reads) do accesses[#accesses + 1] = access.source end
        local computation = Stencil.StencilComputation(
            Stencil.StencilMetastencilId("cmat:" .. sanitize(kplan.id.text) .. ":" .. sanitize(op_name or "all")),
            producer_from_loop(c_emission, loop_fact), accesses, { stream }, { sink },
            Stencil.StencilFusionLegality({}, {}, {}), c_emission.cmat_schedule or default_stencil_schedule(),
            kplan.body.equivalence and kplan.body.equivalence.proofs or {})
        note_cmat_param_qualifiers(c_emission, computation, reads)
        return cmat_inline_projection_for_computation(computation, reads)
    end

    local function cmat_control_compare_kernel(c_emission, kplan, loop_fact, result)
        local projection = cmat_point_projection(kplan, producer_from_loop(c_emission, loop_fact), { result.left, result.right })
        local reads = cmat_read_bindings(projection)
        local left = result.left:lower_c_stencil_point(projection)
        local right = result.right:lower_c_stencil_point(projection)
        local expr = Stencil.StencilPointCompare(result.cmp, left, right, Code.CodeTyBool8)
        local stream = Stencil.StencilStreamDef(Stencil.StencilStreamId("control"), Code.CodeTyBool8, Stencil.StencilStreamMap(expr, {}))
        local sink = Stencil.StencilSinkDef(Stencil.StencilSinkId("all"), Stencil.StencilSinkOpAll(Stencil.StencilStreamRef(stream.id), Stencil.StencilPredNonZero))
        local accesses = {}
        for _, access in ipairs(reads) do accesses[#accesses + 1] = access.source end
        local computation = Stencil.StencilComputation(
            Stencil.StencilMetastencilId("cmat:" .. sanitize(kplan.id.text) .. ":all_compare"),
            producer_from_loop(c_emission, loop_fact), accesses, { stream }, { sink },
            Stencil.StencilFusionLegality({}, {}, {}), c_emission.cmat_schedule or default_stencil_schedule(),
            kplan.body.equivalence and kplan.body.equivalence.proofs or {})
        note_cmat_param_qualifiers(c_emission, computation, reads)
        return cmat_inline_projection_for_computation(computation, reads)
    end

    function Kernel.KernelEffect:lower_c_emit_inline_cmat(_c_emission, _kplan, _loop_fact, _index_atom)
        error("lower_to_c: KernelEffect has no inline CMat materialization", 2)
    end
    function Kernel.KernelEffectFold:lower_c_emit_inline_cmat(_c_emission, _kplan, _loop_fact, _index_atom)
        error("lower_to_c: reductions must use CMat reduction materialization, not KernelEffectFold direct emission", 2)
    end
    function Kernel.KernelEffectStore:lower_c_emit_inline_cmat(c_emission, kplan, loop_fact, index_atom)
        local cmat = cmat_store_kernel(c_emission, kplan, loop_fact, self)
        cmat.computation:lower_c_inline_computation(c_emission, cmat, index_atom)
    end
    function Kernel.KernelEffectScan:lower_c_emit_inline_cmat(c_emission, kplan, loop_fact, index_atom)
        local cmat = cmat_scan_kernel(c_emission, kplan, loop_fact, self)
        cmat = cmat:with_accumulator(cid(self.reduction.accumulator))
        cmat.computation:lower_c_inline_computation(c_emission, cmat, index_atom)
    end
    function Kernel.KernelEffectCopy:lower_c_emit_inline_cmat(c_emission, kplan, loop_fact, index_atom)
        local cmat = cmat_copy_kernel(c_emission, kplan, loop_fact, self)
        cmat.computation:lower_c_inline_computation(c_emission, cmat, index_atom)
    end
    function Kernel.KernelEffectScatterReduce:lower_c_emit_inline_cmat(c_emission, kplan, loop_fact, index_atom)
        local cmat = cmat_scatter_reduce_kernel(c_emission, kplan, loop_fact, self)
        cmat.computation:lower_c_inline_computation(c_emission, cmat, index_atom)
    end

    function Kernel.KernelEffect:lower_c_updates_reduction(_reduction) return false end
    function Kernel.KernelEffectScan:lower_c_updates_reduction(reduction) return self.reduction == reduction end
    function Kernel.KernelEffectFold:lower_c_updates_reduction(_reduction) return false end
    local function reduction_updated_by_effect(kplan, reduction)
        if reduction == nil then return false end
        for _, effect in ipairs(kplan.body.effects or {}) do if effect:lower_c_updates_reduction(reduction) then return true end end
        return false
    end

    local function emit_inline_cmat_effect(c_emission, kplan, loop_fact, effect, index_atom)
        return effect:lower_c_emit_inline_cmat(c_emission, kplan, loop_fact, index_atom)
    end

    function Kernel.KernelExpr:lower_c_is_data_body_expr(_bindings) return false end
    function Kernel.KernelExprLaneLoad:lower_c_is_data_body_expr(_bindings) return true end
    function Kernel.KernelExprAlgebra:lower_c_is_data_body_expr(bindings) return self.expr:lower_c_is_data_body_expr(bindings) end
    function Kernel.KernelExprKernelValue:lower_c_is_data_body_expr(bindings)
        local binding = bindings and bindings[self.value.text]
        return binding ~= nil and binding.expr:lower_c_is_data_body_expr(bindings) or false
    end
    function Value.ValueExpr:lower_c_is_data_body_expr(_bindings) return false end
    function Value.ValueExprValue:lower_c_is_data_body_expr(bindings)
        local binding = bindings and bindings["kval:" .. self.value.text]
        return binding ~= nil and binding.expr:lower_c_is_data_body_expr(bindings) or false
    end
    function Value.ValueExprUnary:lower_c_is_data_body_expr(bindings) return self.value:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprCast:lower_c_is_data_body_expr(bindings) return self.value:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprAdd:lower_c_is_data_body_expr(bindings) return self.a:lower_c_is_data_body_expr(bindings) or self.b:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprSub:lower_c_is_data_body_expr(bindings) return self.a:lower_c_is_data_body_expr(bindings) or self.b:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprMul:lower_c_is_data_body_expr(bindings) return self.a:lower_c_is_data_body_expr(bindings) or self.b:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprDiv:lower_c_is_data_body_expr(bindings) return self.a:lower_c_is_data_body_expr(bindings) or self.b:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprRem:lower_c_is_data_body_expr(bindings) return self.a:lower_c_is_data_body_expr(bindings) or self.b:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprBinary:lower_c_is_data_body_expr(bindings) return self.a:lower_c_is_data_body_expr(bindings) or self.b:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprSelect:lower_c_is_data_body_expr(bindings) return self.cond:lower_c_is_data_body_expr(bindings) or self.t:lower_c_is_data_body_expr(bindings) or self.f:lower_c_is_data_body_expr(bindings) end
    function Value.ValueExprCmp:lower_c_is_data_body_expr(bindings) return self.a:lower_c_is_data_body_expr(bindings) or self.b:lower_c_is_data_body_expr(bindings) end

    local function binding_index_for_body(kplan)
        local out = {}
        for _, binding in ipairs(kplan.body.bindings or {}) do out[binding.id.text] = binding end
        return out
    end

    local function bind_control_values(c_emission, bindings, bindings_by_block, block_id)
        for _, binding in ipairs(bindings_by_block[block_id.text] or {}) do
            if not binding.expr:lower_c_is_data_body_expr(bindings) then bind_kernel_value(c_emission, binding) end
        end
    end

    function Kernel.KernelResult:lower_c_reduction_fact() return nil end
    function Kernel.KernelResultReduction:lower_c_reduction_fact() return self.reduction end

    function Kernel.KernelResult:lower_c_control_state(_c_emission, _kplan, _loop_fact) return nil end
    function Kernel.KernelResultAll:lower_c_control_state(c_emission, kplan, loop_fact)
        return { result = self, cmat = cmat_control_kernel(c_emission, kplan, loop_fact, self, "all") }
    end
    function Kernel.KernelResultAllCompare:lower_c_control_state(c_emission, kplan, loop_fact)
        return { result = self, cmat = cmat_control_compare_kernel(c_emission, kplan, loop_fact, self) }
    end
    function Kernel.KernelResultAny:lower_c_control_state(c_emission, kplan, loop_fact)
        return { result = self, cmat = cmat_control_kernel(c_emission, kplan, loop_fact, self, "any") }
    end
    function Kernel.KernelResultFind:lower_c_control_state(c_emission, kplan, loop_fact)
        return { result = self, cmat = cmat_control_kernel(c_emission, kplan, loop_fact, self, "find") }
    end

    local function reduction_state_for_kernel(c_emission, kplan, loop_fact)
        local reduction = kplan.body.result:lower_c_reduction_fact()
        if reduction == nil then return nil end
        local acc = cid(reduction.accumulator)
        return { reduction = reduction, acc = acc, cmat = cmat_reduce_kernel(c_emission, kplan, loop_fact, reduction), updated_by_effect = reduction_updated_by_effect(kplan, reduction) }
    end

    local function reduction_arg_or_atom(reduction_state, arg)
        if reduction_state ~= nil and arg ~= nil then
            local acc = reduction_state.reduction.accumulator
            if arg.src == acc or arg.dst_param == acc then return C.CBackendAtomLocal(reduction_state.acc) end
        end
        return atom(arg.src)
    end

    local function edge_args_with_reduction(reduction_state, edge_fact)
        local args = {}
        for _, arg in ipairs(edge_fact and edge_fact.args or {}) do args[#args + 1] = reduction_arg_or_atom(reduction_state, arg) end
        return args
    end

    local function emit_reduction_update(c_emission, reduction_state, index_atom)
        if reduction_state == nil or reduction_state.updated_by_effect then return end
        local cmat = reduction_state.cmat:with_accumulator(reduction_state.acc)
        cmat.computation:lower_c_inline_computation(c_emission, cmat, index_atom)
    end

    local function emit_scalar_kernel_fragment(c_emission, graph, flow, kernels, fragment, sched)
        c_emission.cmat_schedule = sched  -- nil means default_stencil_schedule
        local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
        if kplan == nil then error("lower_to_c: kernel strategy references missing kernel " .. fragment.strategy.kernel.text, 2) end
        local loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, cond, loop_fact = loop_partition(c_emission, graph, flow, kplan)
        local bindings_by_block, effects_by_block = place_bindings_effects(c_emission, kplan)
        local reduction_state = reduction_state_for_kernel(c_emission, kplan, loop_fact)
        local control_state = kplan.body.result:lower_c_control_state(c_emission, kplan, loop_fact)
        local control_emitted = false
        local data_bindings = binding_index_for_body(kplan)
        local header_block = c_emission.block_by_id[loop.header.block.text]
        c_emission.current_code_block_id = loop.header.block
        c_emission.stmts = { C.CBackendComment("semantic scalar CMat kernel " .. kplan.id.text) }
        if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, loop.header.block) end
        bind_control_values(c_emission, data_bindings, bindings_by_block, loop.header.block)
        if control_state ~= nil then
            for _, block in ipairs(c_emission.code_func.blocks or {}) do
                if block.id == loop.header.block or (body_set[block.id.text] and block.id ~= loop.header.block) then
                    for _, inst in ipairs(block.insts or {}) do
                        if asdl.classof(inst.op) == Code.CodeInstLoad and asdl.classof(inst.op.place) == Code.CodePlaceField then
                            local place = inst.op.place:lower_code_place_to_c(c_emission)
                            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendPlaceLoad(cid(inst.op.dst), place)
                        end
                    end
                end
            end
            local counter = atom(kplan.body.domain.counter)
            local counted = loop_fact and loop_fact.counted
            local stop_id = counted and counted.stop
            local stop_val = stop_id and atom(stop_id) or C.CBackendAtomLiteral(c_ty(c_emission, Code.CodeTyIndex), Core.LitInt("0"))
            local domain_exit = tmp(c_emission, "cmat_domain_exit", Code.CodeTyBool8)
            c_emission.stmts[#c_emission.stmts + 1] = C.CBackendAssign(domain_exit, C.CBackendRCompare(Core.CmpEq, c_ty(c_emission, Code.CodeTyIndex), counter, cast_to(c_emission, stop_val, Code.CodeTyIndex, Code.CodeTyIndex, "cmat_stop_cast")))
            local result = control_state.result
            c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, header_block), c_emission.stmts,
                C.CBackendIfGoto(C.CBackendAtomLocal(domain_exit), clabel(result.success), edge_args_with_reduction(reduction_state, edge_facts[loop.header.block.text .. "\0" .. result.success.text]), clabel(body_successor), edge_args_with_reduction(reduction_state, edge_facts[loop.header.block.text .. "\0" .. body_successor.text])))
        else
            c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(loop.header.block), c_block_params(c_emission, header_block), c_emission.stmts,
                C.CBackendIfGoto(atom(cond), clabel(body_successor), edge_args_with_reduction(reduction_state, edge_facts[exit_edge.from.block.text .. "\0" .. body_successor.text]), clabel(exit_edge.to.block), edge_args_with_reduction(reduction_state, edge_facts[exit_edge.from.block.text .. "\0" .. exit_edge.to.block.text])))
        end
        for _, block in ipairs(c_emission.code_func.blocks or {}) do
            if body_set[block.id.text] and block.id ~= loop.header.block then
                c_emission.current_code_block_id = block.id
                c_emission.stmts = { C.CBackendComment("semantic scalar CMat kernel body " .. kplan.id.text) }
                if semantic_fragment_prelude ~= nil then semantic_fragment_prelude(c_emission, graph, fragment, block.id) end
                bind_control_values(c_emission, data_bindings, bindings_by_block, block.id)
                for _, e in ipairs(effects_by_block[block.id.text] or {}) do emit_inline_cmat_effect(c_emission, kplan, loop_fact, e, atom(kplan.body.domain.counter)) end
                if block.id == latch_edge.from.block then emit_reduction_update(c_emission, reduction_state, atom(kplan.body.domain.counter)) end
                local term_op = block.term and block.term.op or nil
                local term
                if control_state ~= nil and asdl.classof(term_op) == Code.CodeTermBranch then
                    local cmat = control_state.cmat
                    local control_pred = cmat.computation:lower_c_inline_computation(c_emission, cmat, atom(kplan.body.domain.counter)):lower_c_control_predicate()
                    control_emitted = true
                    term = C.CBackendIfGoto(control_pred, clabel(term_op.then_dest), edge_args_with_reduction(reduction_state, edge_facts[block.id.text .. "\0" .. term_op.then_dest.text]), clabel(term_op.else_dest), edge_args_with_reduction(reduction_state, edge_facts[block.id.text .. "\0" .. term_op.else_dest.text]))
                elseif block.id == latch_edge.from.block then
                    term = C.CBackendGoto(clabel(loop.header.block), edge_args_with_reduction(reduction_state, edge_facts[latch_edge.from.block.text .. "\0" .. latch_edge.to.block.text]))
                else
                    local next_edge = nil
                    for _, fg in ipairs(graph.funcs or {}) do if fg.func == loop.func then for _, edge in ipairs(fg.edges or {}) do if edge.from.block == block.id and body_set[edge.to.block.text] then next_edge = edge end end end end
                    if next_edge == nil then error("lower_to_c: scalar kernel body block has no in-loop successor", 2) end
                    if control_state ~= nil and not control_emitted then
                        local cmat = control_state.cmat
                        local control_pred = cmat.computation:lower_c_inline_computation(c_emission, cmat, atom(kplan.body.domain.counter)):lower_c_control_predicate()
                        local result = control_state.result
                        control_emitted = true
                        term = C.CBackendIfGoto(control_pred, clabel(next_edge.to.block), edge_args_with_reduction(reduction_state, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]), clabel(result.failure), edge_args_with_reduction(reduction_state, edge_facts[block.id.text .. "\0" .. result.failure.text]))
                    else
                        term = C.CBackendGoto(clabel(next_edge.to.block), edge_args_with_reduction(reduction_state, edge_facts[next_edge.from.block.text .. "\0" .. next_edge.to.block.text]))
                    end
                end
                c_emission.blocks[#c_emission.blocks + 1] = C.CBackendBlock(clabel(block.id), c_block_params(c_emission, block), c_emission.stmts, term)
            end
        end
        c_emission.current_code_block_id = nil
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
        local scheds = schedule_index(fragment_emit.schedules)
        local sched = resolve_schedule(fragment_emit.fragment.strategy.kernel, scheds)
        emit_scalar_kernel_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.fragment, sched)
    end

    function Lower.LowerEmitVectorKernel:emit_to_c(c_emission, fragment_emit)
        local scheds = schedule_index(fragment_emit.schedules)
        local sched = resolve_schedule(fragment_emit.fragment.strategy.kernel, scheds)
        -- If no vector schedule resolved, fall back to scalar (nil → default_stencil_schedule)
        -- Vector scheduling is now a CMat policy, not a separate direct
        -- KernelEffect emitter. Until CMat vector bodies are richer, emit the
        -- same inline CMat SOAC body and let the C compiler see the canonical
        -- stencil computation instead of falling back to the old lane unroller.
        emit_scalar_kernel_fragment(c_emission, fragment_emit.graph, fragment_emit.flow, fragment_emit.kernels, fragment_emit.fragment, sched)
    end

    function Lower.LowerEmitMissingSchedule:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: " .. tostring(self.reason), 2)
    end

    function Lower.LowerEmitUnsupported:emit_to_c(c_emission, fragment_emit)
        error("lower_to_c: " .. tostring(self.reason), 2)
    end

    function C.CBackendType:lower_c_with_param_qualifiers(_qual) return self end
    function C.CBackendDataPtr:lower_c_with_param_qualifiers(qual)
        if not (qual and qual.restrict_ptr) then return self end
        return C.CBackendQualifiedDataPtr(self.pointee, false, true, false)
    end
    function C.CBackendQualifiedDataPtr:lower_c_with_param_qualifiers(qual)
        if not (qual and qual.restrict_ptr) then return self end
        return C.CBackendQualifiedDataPtr(self.pointee, self.const_pointee, true, self.volatile_pointee)
    end

    local function apply_c_param_qualifiers(c_emission, params)
        if c_emission.c_param_qualifiers == nil then return params end
        local out = {}
        for i, p in ipairs(params or {}) do
            local q = c_emission.c_param_qualifiers[p.id.text]
            if q ~= nil then out[i] = C.CBackendLocal(p.id, p.name, p.ty:lower_c_with_param_qualifiers(q)) else out[i] = p end
        end
        return out
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
        c_emission.c_param_qualifiers = {}
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

        -- Apply kernel rewrite transformations for provable fragments
        -- These emit replacement CBackend blocks before the normal fragment loop
        local rewrite_applications = {}
        local rewritten_fragment_ids = {}
        for _, fragment in ipairs(ordered_fragments_for_func(code_func, func_plan, graph_loops)) do
            local strategy = fragment.strategy
            if strategy ~= nil and asdl.classof(strategy) == "LowerStrategyClosedForm" then
                local kplan = kernel_by_id(kernels)[strategy.kernel.text]
                if kplan ~= nil then
                    local application = LowerKernelRewrite.apply(kplan, fragment, graph, flow, c_emission)
                    if application ~= nil then
                        rewrite_applications[#rewrite_applications + 1] = application
                        rewritten_fragment_ids[ fragment.id.text ] = true
                    end
                end
            end
        end
        c_emission.rewrite_applications = rewrite_applications

        -- Emit remaining fragments via the normal LowerEmitSelection dispatch
        for _, fragment in ipairs(ordered_fragments_for_func(code_func, func_plan, graph_loops)) do
            if not rewritten_fragment_ids[fragment.id.text] then
                local selection = lower_emit_candidate(fragment, schedules_by_id):select_lower_emit()
                selection:emit_to_c(c_emission, Lower.LowerCEmitInput(graph, flow, kernels, schedules, code_func, fragment, baseline_blocks))
            end
        end

        -- Build CBackendFuncAnnotations from kernel/flow facts
        local func_spine = C.CBackendAnnotationSpine(c_func.name)
        local func_loops, func_pointers, func_branches = {}, {}, {}
        for _, fragment in ipairs(ordered_fragments_for_func(code_func, func_plan, graph_loops)) do
            local strategy_class = asdl.classof(fragment.strategy)
            if strategy_class == "LowerStrategyKernel" then
            local kplan = kernel_by_id(kernels)[fragment.strategy.kernel.text]
            if kplan ~= nil then
                local loop_by_id = {}
                for _, gl in ipairs(graph_loops or {}) do loop_by_id[gl.id.text] = gl end
                local sched = resolve_schedule(fragment.strategy.kernel, schedules_by_id)
                local graph_loop = loop_by_id[fragment.cover.loop and fragment.cover.loop.text or ""]
                if graph_loop ~= nil then
                    local header_label = clabel(graph_loop.header.block)
                    local body_labels = {}
                    for _, bid in ipairs(graph_loop.body or {}) do body_labels[#body_labels + 1] = clabel(bid) end
                    local back_edge_label = nil
                    for _, latch in ipairs(graph_loop.latches or {}) do
                        back_edge_label = back_edge_label or clabel(latch.to.block)
                    end
                    local exit_labels = {}
                    for _, ex in ipairs(graph_loop.exits or {}) do exit_labels[#exit_labels + 1] = clabel(ex.to.block) end
                    local vectorizable = sched ~= nil and asdl.classof(sched) == Schedule.ScheduleVector
                    local tail_plan = C.CBackendTailNone
                    local unroll_hint, interleave_hint = nil, nil
                    if vectorizable and sched ~= nil then
                        if sched.unroll ~= nil then unroll_hint = sched.unroll end
                        if sched.interleave ~= nil then interleave_hint = sched.interleave end
                        if asdl.classof(sched.tail or C.CBackendTailNone) == "TailPeel" then
                            tail_plan = C.CBackendTailPeel(sched.tail.elems)
                        end
                    end
                    local trip_rvalue = nil
                    local domain = kplan.body.domain
                    if domain ~= nil and asdl.classof(domain) == Kernel.KernelDomainFlow then
                        local tc = domain.trip_count
                        if tc ~= nil and tc.trip_expr ~= nil then
                            trip_rvalue = lower_value_expr(c_emission, tc.trip_expr)
                        end
                    end
                    local induction_local, induction_ty = nil, nil
                    if domain ~= nil and domain.counter ~= nil then
                        induction_local = cid(domain.counter)
                        induction_ty = c_ty(c_emission, Code.CodeTyIndex)
                    end
                    local direction = C.CBackendLoopUnknown()
                    if graph_loop ~= nil then
                        -- infer direction from flow facts if available
                    end
                    func_loops[#func_loops + 1] = C.CBackendLoopAnnotation(
                        func_spine, header_label, body_labels,
                        back_edge_label or header_label, exit_labels,
                        induction_local, induction_ty, trip_rvalue,
                        direction, vectorizable,
                        unroll_hint, interleave_hint, tail_plan
                    )
                end

                -- Pointer annotations from KernelLane.backend_info
                for _, lane in ipairs(kplan.body.lanes or {}) do
                    for _, info in ipairs(lane.backend_info or {}) do
                        local align = info.alignment
                        if align ~= nil then
                            local align_fact = align:lower_c_alignment_fact()
                            local ptr_local = cid(info.access)
                            local restrict_ann = false
                            local non_trapping = asdl.classof(info.trap) == "MemNonTrapping"
                            func_pointers[#func_pointers + 1] = C.CBackendPointerAnnotation(
                                func_spine, ptr_local, align_fact, restrict_ann, non_trapping, nil
                            )
                        end
                    end
                end

                -- Branch annotations from flow loop facts
                local flow_loop_facts = flow and flow.loops or {}
                for _, flf in ipairs(flow_loop_facts) do
                    if flf.loop ~= nil and graph_loop ~= nil and flf.loop.text == graph_loop.id.text then
                        for _, induction in ipairs(flf.inductions or {}) do
                            if graph_loop.exits and #graph_loop.exits > 0 then
                                func_branches[#func_branches + 1] = C.CBackendBranchAnnotation(
                                    func_spine,
                                    clabel(graph_loop.exits[1].from.block),
                                    nil,
                                    C.CBackendBranchUnlikely(),
                                    "loop exit edge with upper bound"
                                )
                            end
                            if graph_loop.latches and #graph_loop.latches > 0 then
                                func_branches[#func_branches + 1] = C.CBackendBranchAnnotation(
                                    func_spine,
                                    clabel(graph_loop.latches[1].from.block),
                                    nil,
                                    C.CBackendBranchLikely,
                                    "loop back-edge"
                                )
                            end
                        end
                    end
                end
            end
            end
        end
        c_emission.func_annotations = C.CBackendFuncAnnotations(func_spine, func_loops, func_pointers, func_branches)

        return C.CBackendFunc(
            mutable_func.name,
            mutable_func.symbol,
            mutable_func.visibility,
            mutable_func.sig,
            apply_c_param_qualifiers(c_emission, mutable_func.params),
            mutable_func.locals,
            C.CBackendBodyBlocks(clabel(code_func.blocks[1].id), c_emission.blocks)
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
        local schedules = CodeSchedulePlan.plan(code_module, kernels, flow, value, mem, effect, opts and (opts.target_model or opts.backend_target_model))
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
        for _, fp in ipairs(lower.funcs or {}) do
            for _, frag in ipairs(fp.fragments or {}) do
                if semantic_strategy(frag) then has_semantic = true end
            end
        end
        local code_to_c_opts = {}
        for k, v in pairs(opts or {}) do code_to_c_opts[k] = v end
        local unit = CodeToC.module(code_module, code_to_c_opts)
        if not has_semantic then return unit end

        local base_func_by_name = {}; for _, f in ipairs(unit.funcs or {}) do base_func_by_name[f.symbol] = f end
        local plans = {}; for _, fp in ipairs(lower.funcs or {}) do plans[fp.func.text] = fp end
        local funcs = func_by_id(code_module)
        local graph_loops = graph_indexes(graph)
        local cfuncs = {}
        local c_emission = {
            unit = unit,
            c_type_projection = make_c_type_projection(code_module, nil),
            helper_by_key = {},
            next_helper = 0,
            next_tmp = 0,
            mem = mem,
            flow = flow,
            mem_projection = CodeMemFacts.access_projection(mem),
        }
        for _, h in ipairs(unit.helpers or {}) do c_emission.helper_by_key[h.id.text] = h end

        local cfuncs_by_name = {}
        for _, code_func in ipairs(code_module.funcs or {}) do
            local fp = plans[code_func.id.text]
            local base = base_func_by_name[code_func.name]
            if fp ~= nil then
                local semantic = false
                for _, frag in ipairs(fp.fragments or {}) do if semantic_strategy(frag) then semantic = true end end
                if semantic then
                    local new_func = lower_semantic_func(c_emission, graph, flow, kernels, schedules, code_func, base, fp, graph_loops, c_block_body(base))
                    cfuncs[#cfuncs + 1] = new_func
                    cfuncs_by_name[new_func.name.text] = c_emission.func_annotations
                else cfuncs[#cfuncs + 1] = base end
            else
                cfuncs[#cfuncs + 1] = base
            end
        end
        local result = C.CBackendUnit(unit.module_name, unit.target, unit.sigs, unit.types, unit.globals, unit.externs, unit.helpers, cfuncs)
        rawset(result, "_func_annotations", cfuncs_by_name)
        return result
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
