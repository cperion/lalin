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
    if T._moonlift_api_cache.lower_to_back ~= nil then return T._moonlift_api_cache.lower_to_back end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Mem = T.MoonMem
    local Kernel = T.MoonKernel
    local Lower = T.MoonLower
    local Back = T.MoonBack
    local CodeToBack = require("moonlift.code_to_back").Define(T)

    local api = {}

    local function bid(id) return Back.BackValId(id.text) end
    local function func_id(id) return Back.BackFuncId(tostring(id.text):gsub("^fn:", "", 1)) end
    local function sig_id(id) return Back.BackSigId(id.text) end
    local function shape_scalar(s) return Back.BackShapeScalar(s) end
    local function shape_vec(v) return Back.BackShapeVec(v) end

    local function shape(ty)
        local s = CodeToBack.scalar(ty)
        if s == nil then error("lower_to_back: unsupported scalar type", 3) end
        return Back.BackShapeScalar(s), s
    end

    local function scalar_bytes(s)
        if s == Back.BackI8 or s == Back.BackU8 or s == Back.BackBool then return 1 end
        if s == Back.BackI16 or s == Back.BackU16 then return 2 end
        if s == Back.BackI32 or s == Back.BackU32 or s == Back.BackF32 then return 4 end
        return 8
    end

    local function int_op(op)
        if op == Core.BinAdd then return Back.BackIntAdd end
        if op == Core.BinSub then return Back.BackIntSub end
        if op == Core.BinMul then return Back.BackIntMul end
        if op == Core.BinDiv then return Back.BackIntSDiv end
        if op == Core.BinRem then return Back.BackIntSRem end
        return nil
    end

    local function bit_op(op)
        if op == Core.BinBitAnd then return Back.BackBitAnd end
        if op == Core.BinBitOr then return Back.BackBitOr end
        if op == Core.BinBitXor then return Back.BackBitXor end
        return nil
    end

    local function vec_op(op)
        if op == Core.BinAdd then return Back.BackVecIntAdd end
        if op == Core.BinSub then return Back.BackVecIntSub end
        if op == Core.BinMul then return Back.BackVecIntMul end
        if op == Core.BinBitAnd then return Back.BackVecBitAnd end
        if op == Core.BinBitOr then return Back.BackVecBitOr end
        if op == Core.BinBitXor then return Back.BackVecBitXor end
        return nil
    end

    local function cmp_op(op, ty)
        local cls = pvm.classof(ty)
        local unsigned = ty == Code.CodeTyIndex or (cls == Code.CodeTyInt and ty.signedness == Code.CodeUnsigned)
        local float = cls == Code.CodeTyFloat
        if op == Core.CmpEq then return float and Back.BackFCmpEq or Back.BackIcmpEq end
        if op == Core.CmpNe then return float and Back.BackFCmpNe or Back.BackIcmpNe end
        if op == Core.CmpLt then return float and Back.BackFCmpLt or (unsigned and Back.BackUIcmpLt or Back.BackSIcmpLt) end
        if op == Core.CmpLe then return float and Back.BackFCmpLe or (unsigned and Back.BackUIcmpLe or Back.BackSIcmpLe) end
        if op == Core.CmpGt then return float and Back.BackFCmpGt or (unsigned and Back.BackUIcmpGt or Back.BackSIcmpGt) end
        if op == Core.CmpGe then return float and Back.BackFCmpGe or (unsigned and Back.BackUIcmpGe or Back.BackSIcmpGe) end
        return nil
    end

    local function vec_cmp_op(op, ty)
        if pvm.classof(ty) == Code.CodeTyFloat then return nil end
        local cls = pvm.classof(ty)
        local unsigned = ty == Code.CodeTyIndex or (cls == Code.CodeTyInt and ty.signedness == Code.CodeUnsigned)
        if op == Core.CmpEq then return Back.BackVecIcmpEq end
        if op == Core.CmpNe then return Back.BackVecIcmpNe end
        if op == Core.CmpLt then return unsigned and Back.BackVecUIcmpLt or Back.BackVecSIcmpLt end
        if op == Core.CmpLe then return unsigned and Back.BackVecUIcmpLe or Back.BackVecSIcmpLe end
        if op == Core.CmpGt then return unsigned and Back.BackVecUIcmpGt or Back.BackVecSIcmpGt end
        if op == Core.CmpGe then return unsigned and Back.BackVecUIcmpGe or Back.BackVecSIcmpGe end
        return nil
    end

    local function defs_for(func)
        local defs = { view_values = {} }
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local cls = pvm.classof(k)
                if cls == Code.CodeInstConst then defs[k.dst.text] = { cls = cls, const = k.const }
                elseif cls == Code.CodeInstAlias then defs[k.dst.text] = { cls = cls, src = k.src, ty = k.ty }
                elseif cls == Code.CodeInstBinary then defs[k.dst.text] = { cls = cls, op = k.op, ty = k.ty, semantics = k.semantics, lhs = k.lhs, rhs = k.rhs }
                elseif cls == Code.CodeInstView then
                    defs[k.dst.text] = { cls = cls, data = k.data, len = k.len, stride = k.stride, ty = k.ty }
                    defs.view_values[k.dst.text] = { data = k.data, len = k.len, stride = k.stride }
                elseif cls == Code.CodeInstViewData then
                    defs[k.dst.text] = { cls = cls, view = k.view, ptr_ty = k.ptr_ty, view_ty = k.view_ty }
                elseif cls == Code.CodeInstLoad then
                    defs[k.dst.text] = { cls = cls, place = k.place, access = k.access }
                    if pvm.classof(k.access.ty) == Code.CodeTyView and pvm.classof(k.place) == Code.CodePlaceLocal then
                        defs.view_values[k.dst.text] = defs.view_values[k.place["local"].text]
                    end
                elseif cls == Code.CodeInstStore then
                    if pvm.classof(k.access.ty) == Code.CodeTyView and pvm.classof(k.place) == Code.CodePlaceLocal then
                        defs.view_values[k.place["local"].text] = defs.view_values[k.value.text]
                    end
                end
            end
        end
        return defs
    end

    local function const_raw(defs, value)
        local def = value and defs[value.text]
        if def == nil or def.cls ~= Code.CodeInstConst or pvm.classof(def.const) ~= Code.CodeConstLiteral then return nil end
        return def.const.literal and def.const.literal.raw or nil
    end

    local function mem_base_value(base)
        local cls = pvm.classof(base)
        if cls == Mem.MemBaseValue then return base.value end
        if cls == Mem.MemBaseArgument then return base.value end
        if cls == Mem.MemBaseDerived then return mem_base_value(base.base) end
        return nil
    end

    local function semantic_index(semantics)
        if semantics == nil then return nil end
        local idx = { nontrap = {}, movable = {}, deref = {}, align = {}, readonly_access = {} }
        for _, safety in ipairs(semantics.safety or {}) do
            local cls = pvm.classof(safety)
            if cls == Mem.MemAccessNonTrap then idx.nontrap[safety.access.text] = true
            elseif cls == Mem.MemAccessMovable then idx.movable[safety.access.text] = true
            elseif cls == Mem.MemAccessDerefBytes then idx.deref[safety.access.text] = safety.bytes
            elseif cls == Mem.MemAccessAlignKnown then idx.align[safety.access.text] = safety.bytes end
        end
        local readonly_object = {}
        for _, effect in ipairs(semantics.effects or {}) do
            if pvm.classof(effect) == Mem.MemObjectReadonly then
                readonly_object[effect.object.text] = true
            end
        end
        for _, interval in ipairs(semantics.intervals or {}) do
            if readonly_object[interval.object.text] then
                idx.readonly_access[interval.access.text] = true
            end
        end
        return idx
    end

    local function stream_access_id(stream)
        local first = stream and stream.accesses and stream.accesses[1] or nil
        return first and first.text or nil
    end

    local function memory_info_for_stream(stem, tag, stream, bytes, mode, sem_idx)
        local access_id = stream_access_id(stream)
        local align = Back.BackAlignUnknown
        local trap = Back.BackMayTrap
        local motion = Back.BackMayNotMove
        local deref = Back.BackDerefBytes(bytes, "kernel memory access")
        if sem_idx ~= nil and access_id ~= nil then
            if sem_idx.align[access_id] ~= nil then align = Back.BackAlignKnown(sem_idx.align[access_id]) end
            if sem_idx.deref[access_id] ~= nil then deref = Back.BackDerefBytes(bytes, "normalized semantic dereference proof") end
            if sem_idx.nontrap[access_id] then trap = Back.BackNonTrapping("normalized semantic nontrap proof") end
            if sem_idx.movable[access_id] then motion = Back.BackCanMove("normalized semantic movement proof") end
            if mode == Back.BackAccessRead and sem_idx.readonly_access[access_id] then mode = Back.BackAccessReadonly end
        end
        return Back.BackMemoryInfo(Back.BackAccessId("kernel:" .. stem .. ":" .. tag), align, deref, trap, motion, mode)
    end

    local function kernel_body_commands(func, plan, sem_idx)
        if pvm.classof(plan.subject) ~= Kernel.KernelSubjectFunc then return nil end
        local body = plan.body
        if pvm.classof(body) ~= Kernel.KernelBodyCounted then return nil end
        local reduction
        local stores = {}
        for _, effect in ipairs(body.effects or {}) do
            local ecls = pvm.classof(effect)
            if ecls == Kernel.KernelEffectFold and reduction == nil then reduction = effect.fold
            elseif ecls == Kernel.KernelEffectStore then stores[#stores + 1] = effect.store end
        end
        if reduction == nil and #stores == 0 then return nil end
        local counter = body.counter
        local counter_value = counter and counter.value or nil
        local defs = defs_for(func)
        local function resolve_memory_base(value, seen)
            if value == nil then return nil end
            seen = seen or {}
            if seen[value.text] then return value end
            seen[value.text] = true
            local def = defs[value.text]
            if def ~= nil then
                if def.cls == Code.CodeInstAlias then return resolve_memory_base(def.src, seen) end
                if def.cls == Code.CodeInstViewData then
                    local parts = defs.view_values[def.view.text]
                    if parts ~= nil and parts.data ~= nil then return resolve_memory_base(parts.data, seen) end
                end
            end
            return value
        end
        local rshape, rscalar = reduction and shape(reduction.ty) or nil, nil
        if reduction ~= nil then rshape, rscalar = shape(reduction.ty) end
        local counter_shape, counter_scalar = shape((body.loop.inductions and body.loop.inductions[1] and body.loop.inductions[1].ty) or Code.CodeTyIndex)
        local domain = body.loop.domain and body.loop.domain.counted
        if domain == nil then return nil end
        local start_raw, step_raw = const_raw(defs, domain.start), const_raw(defs, domain.step)
        if start_raw == nil or step_raw == nil then return nil end

        local stem = sanitize(func.name)
        local function block(s) return Back.BackBlockId("kernel:" .. stem .. ":" .. s) end
        local function val(s) return Back.BackValId("kernel:" .. stem .. ":" .. s) end
        local params = {}
        for i = 1, #(func.params or {}) do params[i] = bid(func.params[i].value) end

        local function lower_value(cmds, value, env, expected_scalar)
            if env[value.text] ~= nil then return env[value.text] end
            local raw = const_raw(defs, value)
            if raw ~= nil then
                local v = val("const." .. sanitize(value.text) .. "." .. tostring(#cmds))
                cmds[#cmds + 1] = Back.CmdConst(v, expected_scalar, Back.BackLitInt(raw))
                env[value.text] = v
                return v
            end
            for _, param in ipairs(func.params or {}) do if param.value == value then return bid(value) end end
            return bid(value)
        end

        local function byte_offset_for_index(cmds, index_value, elem_size)
            local idx = index_value
            if counter_scalar ~= Back.BackIndex then
                idx = val("idx64." .. tostring(#cmds))
                cmds[#cmds + 1] = Back.CmdCast(idx, Back.BackSextend, Back.BackIndex, index_value)
            end
            local sz, off = val("elem.size." .. tostring(#cmds)), val("byte.off." .. tostring(#cmds))
            cmds[#cmds + 1] = Back.CmdConst(sz, Back.BackIndex, Back.BackLitInt(tostring(elem_size)))
            cmds[#cmds + 1] = Back.CmdIntBinary(off, Back.BackIntMul, Back.BackIndex, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), idx, sz)
            return off
        end

        local tmp_counter = 0
        local function tmp(tag)
            tmp_counter = tmp_counter + 1
            return val(tag .. "." .. tostring(tmp_counter))
        end

        local kernel_expr_ty
        local lower_scalar_expr
        lower_scalar_expr = function(cmds, expr, env, expected_ty)
            local cls = pvm.classof(expr)
            if cls == Kernel.KernelExprValue then return lower_value(cmds, expr.value, env, CodeToBack.scalar(expected_ty)) end
            if cls == Kernel.KernelExprConst then
                local _, s = shape(expr.const.ty)
                local v = tmp("kconst")
                local raw = expr.const.literal and expr.const.literal.raw or "0"
                cmds[#cmds + 1] = Back.CmdConst(v, s, Back.BackLitInt(raw))
                return v
            end
            if cls == Kernel.KernelExprLoad then
                local base_value = resolve_memory_base(mem_base_value(expr.stream.base))
                if base_value == nil then error("lower_to_back: unsupported kernel load base", 3) end
                local _, load_scalar = shape(expr.stream.elem_ty)
                local off = byte_offset_for_index(cmds, env[counter_value.text], scalar_bytes(load_scalar))
                local dst = tmp("load")
                local mem = memory_info_for_stream(stem, "load:" .. tostring(tmp_counter), expr.stream, scalar_bytes(load_scalar), Back.BackAccessRead, sem_idx)
                cmds[#cmds + 1] = Back.CmdLoadInfo(dst, shape_scalar(load_scalar), Back.BackAddress(Back.BackAddrValue(bid(base_value)), off, Back.BackProvArg(base_value.text), Back.BackPtrBoundsUnknown), mem)
                return dst
            end
            if cls == Kernel.KernelExprBinary then
                local _, s = shape(expr.ty)
                local lhs = lower_scalar_expr(cmds, expr.lhs, env, expr.ty)
                local rhs = lower_scalar_expr(cmds, expr.rhs, env, expr.ty)
                local dst = tmp("bin")
                local iop, bop = int_op(expr.op), bit_op(expr.op)
                if iop then cmds[#cmds + 1] = Back.CmdIntBinary(dst, iop, s, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), lhs, rhs)
                elseif bop then cmds[#cmds + 1] = Back.CmdBitBinary(dst, bop, s, lhs, rhs)
                else error("lower_to_back: unsupported kernel binary op", 3) end
                return dst
            end
            if cls == Kernel.KernelExprCompare then
                local shp = shape(expr.ty)
                local lhs = lower_scalar_expr(cmds, expr.lhs, env, expr.ty)
                local rhs = lower_scalar_expr(cmds, expr.rhs, env, expr.ty)
                local op = cmp_op(expr.op, expr.ty)
                if op == nil then error("lower_to_back: unsupported kernel compare op", 3) end
                local dst = tmp("cmp")
                cmds[#cmds + 1] = Back.CmdCompare(dst, op, shp, lhs, rhs)
                return dst
            end
            if cls == Kernel.KernelExprSelect then
                local ty = expected_ty or kernel_expr_ty(expr.then_value)
                local shp = shape(ty)
                local cond = lower_scalar_expr(cmds, expr.cond, env, Code.CodeTyBool8)
                local then_value = lower_scalar_expr(cmds, expr.then_value, env, ty)
                local else_value = lower_scalar_expr(cmds, expr.else_value, env, ty)
                local dst = tmp("select")
                cmds[#cmds + 1] = Back.CmdSelect(dst, shp, cond, then_value, else_value)
                return dst
            end
            error("lower_to_back: unsupported kernel scalar expr", 3)
        end

        local function lower_vec_expr(cmds, expr, env, vec_ty, expected_ty)
            local cls = pvm.classof(expr)
            if cls == Kernel.KernelExprLoad then
                local base_value = resolve_memory_base(mem_base_value(expr.stream.base))
                if base_value == nil then error("lower_to_back: unsupported kernel vector load base", 3) end
                local _, load_scalar = shape(expr.stream.elem_ty)
                local off = byte_offset_for_index(cmds, env[counter_value.text], scalar_bytes(load_scalar))
                local dst = tmp("vload")
                local mem = memory_info_for_stream(stem, "vload:" .. tostring(tmp_counter), expr.stream, scalar_bytes(load_scalar) * vec_ty.lanes, Back.BackAccessRead, sem_idx)
                cmds[#cmds + 1] = Back.CmdLoadInfo(dst, shape_vec(vec_ty), Back.BackAddress(Back.BackAddrValue(bid(base_value)), off, Back.BackProvArg(base_value.text), Back.BackPtrBoundsUnknown), mem)
                return dst
            elseif cls == Kernel.KernelExprConst then
                local scalar = lower_scalar_expr(cmds, expr, env, expr.const.ty)
                local splat = tmp("splat.const")
                cmds[#cmds + 1] = Back.CmdVecSplat(splat, vec_ty, scalar)
                return splat
            elseif cls == Kernel.KernelExprValue then
                local scalar = lower_scalar_expr(cmds, expr, env, expected_ty or (reduction and reduction.ty) or Code.CodeTyIndex)
                local splat = tmp("splat.value")
                cmds[#cmds + 1] = Back.CmdVecSplat(splat, vec_ty, scalar)
                return splat
            elseif cls == Kernel.KernelExprBinary then
                local lhs = lower_vec_expr(cmds, expr.lhs, env, vec_ty, expr.ty)
                local rhs = lower_vec_expr(cmds, expr.rhs, env, vec_ty, expr.ty)
                local op = vec_op(expr.op)
                if op == nil then error("lower_to_back: unsupported kernel vector binary op", 3) end
                local dst = tmp("vbin")
                cmds[#cmds + 1] = Back.CmdVecBinary(dst, op, vec_ty, lhs, rhs)
                return dst
            elseif cls == Kernel.KernelExprCompare then
                local lhs = lower_vec_expr(cmds, expr.lhs, env, vec_ty, expr.ty)
                local rhs = lower_vec_expr(cmds, expr.rhs, env, vec_ty, expr.ty)
                local op = vec_cmp_op(expr.op, expr.ty)
                if op == nil then error("lower_to_back: unsupported kernel vector compare op", 3) end
                local dst = tmp("vcmp")
                cmds[#cmds + 1] = Back.CmdVecCompare(dst, op, vec_ty, lhs, rhs)
                return dst
            elseif cls == Kernel.KernelExprSelect then
                local cond = lower_vec_expr(cmds, expr.cond, env, vec_ty, Code.CodeTyBool8)
                local then_value = lower_vec_expr(cmds, expr.then_value, env, vec_ty, expected_ty or kernel_expr_ty(expr.then_value))
                local else_value = lower_vec_expr(cmds, expr.else_value, env, vec_ty, expected_ty or kernel_expr_ty(expr.else_value))
                local dst = tmp("vselect")
                cmds[#cmds + 1] = Back.CmdVecSelect(dst, vec_ty, cond, then_value, else_value)
                return dst
            end
            error("lower_to_back: unsupported kernel vector expr", 3)
        end

        local function store_base(store)
            local base_value = resolve_memory_base(mem_base_value(store.dst.base))
            if base_value == nil then error("lower_to_back: unsupported kernel store base", 3) end
            return base_value
        end

        local function emit_vec_store(cmds, store, env, vec_ty)
            local base_value = store_base(store)
            local _, store_scalar = shape(store.dst.elem_ty)
            if store_scalar ~= vec_ty.elem then error("lower_to_back: mixed vector store scalar", 3) end
            local off = byte_offset_for_index(cmds, env[counter_value.text], scalar_bytes(store_scalar))
            local value = lower_vec_expr(cmds, store.value, env, vec_ty, store.dst.elem_ty)
            local mem = memory_info_for_stream(stem, "vstore:" .. tostring(tmp_counter), store.dst, scalar_bytes(store_scalar) * vec_ty.lanes, Back.BackAccessWrite, sem_idx)
            cmds[#cmds + 1] = Back.CmdStoreInfo(shape_vec(vec_ty), Back.BackAddress(Back.BackAddrValue(bid(base_value)), off, Back.BackProvArg(base_value.text), Back.BackPtrBoundsUnknown), value, mem)
        end

        local function emit_scalar_store(cmds, store, env)
            local base_value = store_base(store)
            local _, store_scalar = shape(store.dst.elem_ty)
            local off = byte_offset_for_index(cmds, env[counter_value.text], scalar_bytes(store_scalar))
            local value = lower_scalar_expr(cmds, store.value, env, store.dst.elem_ty)
            local mem = memory_info_for_stream(stem, "store:" .. tostring(tmp_counter), store.dst, scalar_bytes(store_scalar), Back.BackAccessWrite, sem_idx)
            cmds[#cmds + 1] = Back.CmdStoreInfo(shape_scalar(store_scalar), Back.BackAddress(Back.BackAddrValue(bid(base_value)), off, Back.BackProvArg(base_value.text), Back.BackPtrBoundsUnknown), value, mem)
        end

        kernel_expr_ty = function(expr)
            local cls = pvm.classof(expr)
            if cls == Kernel.KernelExprConst then return expr.const.ty end
            if cls == Kernel.KernelExprLoad then return expr.stream.elem_ty end
            if cls == Kernel.KernelExprBinary then return expr.ty end
            if cls == Kernel.KernelExprCompare then return Code.CodeTyBool8 end
            if cls == Kernel.KernelExprSelect then return kernel_expr_ty(expr.then_value) end
            if cls == Kernel.KernelExprValue and reduction ~= nil then return reduction.ty end
            return Code.CodeTyIndex
        end

        local function emit_kernel_return(cmds, result_sem, env, fold_value)
            local cls = pvm.classof(result_sem)
            if cls == Kernel.KernelResultFold then
                if fold_value == nil then return false end
                cmds[#cmds + 1] = Back.CmdReturnValue(fold_value)
                return true
            elseif cls == Kernel.KernelResultVoid then
                cmds[#cmds + 1] = Back.CmdReturnVoid
                return true
            elseif cls == Kernel.KernelResultExpr then
                local value = lower_scalar_expr(cmds, result_sem.value, env or {}, kernel_expr_ty(result_sem.value))
                cmds[#cmds + 1] = Back.CmdReturnValue(value)
                return true
            elseif cls == Kernel.KernelResultClosedForm then
                local expr = result_sem.closed_form.value
                local value = lower_scalar_expr(cmds, expr, env or {}, kernel_expr_ty(expr))
                cmds[#cmds + 1] = Back.CmdReturnValue(value)
                return true
            end
            return false
        end

        local function closed_form_result()
            local result_cls = pvm.classof(body.result)
            if #stores ~= 0 or (result_cls ~= Kernel.KernelResultExpr and result_cls ~= Kernel.KernelResultClosedForm) then return nil end
            local entry = block("closed.entry")
            local cmds = {
                Back.CmdBeginFunc(func_id(func.id)),
                Back.CmdCreateBlock(entry),
                Back.CmdSwitchToBlock(entry),
                Back.CmdBindEntryParams(entry, params),
            }
            if not emit_kernel_return(cmds, body.result, {}, nil) then return nil end
            cmds[#cmds + 1] = Back.CmdSealBlock(entry)
            cmds[#cmds + 1] = Back.CmdFinishFunc(func_id(func.id))
            return cmds
        end

        local closed_form = closed_form_result()
        if closed_form ~= nil then return closed_form end

        local function vector_reduction()
            if start_raw ~= "0" or step_raw ~= "1" then return nil end
            if #(body.streams or {}) == 0 then return nil end
            local schedule = plan.schedule
            if pvm.classof(schedule) ~= Kernel.KernelScheduleVector or pvm.classof(schedule.shape) ~= Kernel.KernelLaneVector then return nil end
            local lanes = schedule.shape.lanes
            local vop = reduction and vec_op(reduction.op) or nil
            local vec_scalar = rscalar
            if vec_scalar == nil and stores[1] ~= nil then local _, ss = shape(stores[1].dst.elem_ty); vec_scalar = ss end
            if lanes == nil or lanes < 2 or vec_scalar == nil then return nil end
            if reduction ~= nil and vop == nil then return nil end
            local vec_ty = Back.BackVec(vec_scalar, lanes)
            local entry, loop, body_block, exitv, tail, tail_body, ret = block("vreduce.entry"), block("vreduce.loop"), block("vreduce.body"), block("vreduce.exit"), block("vreduce.tail"), block("vreduce.tail.body"), block("vreduce.ret")
            local li, lacc, bi, bacc, ei, eacc, ti, tacc, tbi, tbacc, result = val("v.li"), val("v.lacc"), val("v.bi"), val("v.bacc"), val("v.ei"), val("v.eacc"), val("v.ti"), val("v.tacc"), val("v.tbi"), val("v.tbacc"), val("v.result")
            local cmds = {
                Back.CmdBeginFunc(func_id(func.id)),
                Back.CmdCreateBlock(entry), Back.CmdCreateBlock(loop), Back.CmdCreateBlock(body_block), Back.CmdCreateBlock(exitv), Back.CmdCreateBlock(tail), Back.CmdCreateBlock(tail_body), Back.CmdCreateBlock(ret),
                Back.CmdAppendBlockParam(loop, li, counter_shape),
                Back.CmdAppendBlockParam(body_block, bi, counter_shape),
                Back.CmdAppendBlockParam(exitv, ei, counter_shape),
                Back.CmdAppendBlockParam(tail, ti, counter_shape),
                Back.CmdAppendBlockParam(tail_body, tbi, counter_shape),
                Back.CmdSwitchToBlock(entry), Back.CmdBindEntryParams(entry, params),
            }
            local stop = lower_value(cmds, domain.stop, {}, counter_scalar)
            if reduction ~= nil then
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(loop, lacc, shape_vec(vec_ty))
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(body_block, bacc, shape_vec(vec_ty))
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(exitv, eacc, shape_vec(vec_ty))
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(tail, tacc, rshape)
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(tail_body, tbacc, rshape)
                cmds[#cmds + 1] = Back.CmdAppendBlockParam(ret, result, rshape)
            end
            local zero_i, identity, stride, rem, main_stop, zero_vec = val("v.zero.i"), val("v.identity"), val("v.stride"), val("v.rem"), val("v.main.stop"), val("v.zero.vec")
            cmds[#cmds + 1] = Back.CmdConst(zero_i, counter_scalar, Back.BackLitInt("0"))
            if reduction ~= nil then cmds[#cmds + 1] = Back.CmdConst(identity, rscalar, Back.BackLitInt(reduction.identity)) end
            cmds[#cmds + 1] = Back.CmdConst(stride, counter_scalar, Back.BackLitInt(tostring(lanes)))
            cmds[#cmds + 1] = Back.CmdIntBinary(rem, Back.BackIntSRem, counter_scalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), stop, stride)
            cmds[#cmds + 1] = Back.CmdIntBinary(main_stop, Back.BackIntSub, counter_scalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), stop, rem)
            local loop_init = { zero_i }
            if reduction ~= nil then
                cmds[#cmds + 1] = Back.CmdVecSplat(zero_vec, vec_ty, identity)
                loop_init[#loop_init + 1] = zero_vec
            end
            cmds[#cmds + 1] = Back.CmdJump(loop, loop_init)
            cmds[#cmds + 1] = Back.CmdSealBlock(entry)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(loop)
            local cond = val("v.cond")
            cmds[#cmds + 1] = Back.CmdCompare(cond, Back.BackSIcmpLt, counter_shape, li, main_stop)
            local body_args, exit_args = { li }, { li }
            if reduction ~= nil then body_args[#body_args + 1], exit_args[#exit_args + 1] = lacc, lacc end
            cmds[#cmds + 1] = Back.CmdBrIf(cond, body_block, body_args, exitv, exit_args)
            cmds[#cmds + 1] = Back.CmdSealBlock(body_block)
            cmds[#cmds + 1] = Back.CmdSealBlock(exitv)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(body_block)
            local body_env = { [counter_value.text] = bi }
            for _, store in ipairs(stores) do emit_vec_store(cmds, store, body_env, vec_ty) end
            local next_args = {}
            local next_i = val("v.next.i")
            if reduction ~= nil then
                local vcontrib = lower_vec_expr(cmds, reduction.value, body_env, vec_ty, reduction.ty)
                local next_acc = val("v.next.acc")
                cmds[#cmds + 1] = Back.CmdVecBinary(next_acc, vop, vec_ty, bacc, vcontrib)
                next_args[#next_args + 1] = next_acc
            end
            cmds[#cmds + 1] = Back.CmdIntBinary(next_i, Back.BackIntAdd, counter_scalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), bi, stride)
            table.insert(next_args, 1, next_i)
            cmds[#cmds + 1] = Back.CmdJump(loop, next_args)
            cmds[#cmds + 1] = Back.CmdSealBlock(loop)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(exitv)
            local tail_init = { ei }
            if reduction ~= nil then
                local reduced = identity
                for lane = 0, lanes - 1 do
                    local lane_v = val("v.lane." .. tostring(lane))
                    cmds[#cmds + 1] = Back.CmdVecExtractLane(lane_v, rscalar, eacc, lane)
                    local next_reduced = val("v.hreduce." .. tostring(lane))
                    local iop, bop = int_op(reduction.op), bit_op(reduction.op)
                    if iop then cmds[#cmds + 1] = Back.CmdIntBinary(next_reduced, iop, rscalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), reduced, lane_v)
                    elseif bop then cmds[#cmds + 1] = Back.CmdBitBinary(next_reduced, bop, rscalar, reduced, lane_v)
                    else return nil end
                    reduced = next_reduced
                end
                tail_init[#tail_init + 1] = reduced
            end
            cmds[#cmds + 1] = Back.CmdJump(tail, tail_init)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(tail)
            local tail_cond = val("v.tail.cond")
            cmds[#cmds + 1] = Back.CmdCompare(tail_cond, Back.BackSIcmpLt, counter_shape, ti, stop)
            local tail_body_args, ret_args = { ti }, {}
            if reduction ~= nil then tail_body_args[#tail_body_args + 1], ret_args[#ret_args + 1] = tacc, tacc end
            cmds[#cmds + 1] = Back.CmdBrIf(tail_cond, tail_body, tail_body_args, ret, ret_args)
            cmds[#cmds + 1] = Back.CmdSealBlock(tail_body)
            cmds[#cmds + 1] = Back.CmdSealBlock(ret)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(tail_body)
            local tail_env = { [counter_value.text] = tbi }
            for _, store in ipairs(stores) do emit_scalar_store(cmds, store, tail_env) end
            local next_tail_args = {}
            local one, tail_next_i = val("v.one"), val("v.tail.next.i")
            if reduction ~= nil then
                local tail_contrib = lower_scalar_expr(cmds, reduction.value, tail_env, reduction.ty)
                local tail_next_acc = val("v.tail.next.acc")
                local iop, bop = int_op(reduction.op), bit_op(reduction.op)
                if iop then cmds[#cmds + 1] = Back.CmdIntBinary(tail_next_acc, iop, rscalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), tbacc, tail_contrib)
                elseif bop then cmds[#cmds + 1] = Back.CmdBitBinary(tail_next_acc, bop, rscalar, tbacc, tail_contrib)
                else return nil end
                next_tail_args[#next_tail_args + 1] = tail_next_acc
            end
            cmds[#cmds + 1] = Back.CmdConst(one, counter_scalar, Back.BackLitInt("1"))
            cmds[#cmds + 1] = Back.CmdIntBinary(tail_next_i, Back.BackIntAdd, counter_scalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), tbi, one)
            table.insert(next_tail_args, 1, tail_next_i)
            cmds[#cmds + 1] = Back.CmdJump(tail, next_tail_args)
            cmds[#cmds + 1] = Back.CmdSealBlock(tail)

            cmds[#cmds + 1] = Back.CmdSwitchToBlock(ret)
            if not emit_kernel_return(cmds, body.result, {}, reduction and result or nil) then return nil end
            cmds[#cmds + 1] = Back.CmdFinishFunc(func_id(func.id))
            return cmds
        end
        local vector = vector_reduction()
        if vector ~= nil then return vector end

        local entry, loop, body, exit = block("entry"), block("loop"), block("body"), block("exit")
        local li, lacc, bi, bacc, eacc = val("li"), val("lacc"), val("bi"), val("bacc"), val("eacc")
        local cmds = {
            Back.CmdBeginFunc(func_id(func.id)),
            Back.CmdCreateBlock(entry), Back.CmdCreateBlock(loop), Back.CmdCreateBlock(body), Back.CmdCreateBlock(exit),
            Back.CmdAppendBlockParam(loop, li, counter_shape), Back.CmdAppendBlockParam(loop, lacc, rshape),
            Back.CmdAppendBlockParam(body, bi, counter_shape), Back.CmdAppendBlockParam(body, bacc, rshape),
            Back.CmdAppendBlockParam(exit, eacc, rshape),
            Back.CmdSwitchToBlock(entry), Back.CmdBindEntryParams(entry, params),
        }
        local start, init = val("start"), val("identity")
        cmds[#cmds + 1] = Back.CmdConst(start, counter_scalar, Back.BackLitInt(start_raw))
        cmds[#cmds + 1] = Back.CmdConst(init, rscalar, Back.BackLitInt(reduction.identity))
        cmds[#cmds + 1] = Back.CmdJump(loop, { start, init })

        cmds[#cmds + 1] = Back.CmdSealBlock(entry)
        cmds[#cmds + 1] = Back.CmdSwitchToBlock(loop)
        local stop = lower_value(cmds, domain.stop, { [counter_value.text] = li }, counter_scalar)
        local cond = val("cond")
        cmds[#cmds + 1] = Back.CmdCompare(cond, Back.BackSIcmpLt, counter_shape, li, stop)
        cmds[#cmds + 1] = Back.CmdBrIf(cond, body, { li, lacc }, exit, { lacc })
        cmds[#cmds + 1] = Back.CmdSealBlock(body)
        cmds[#cmds + 1] = Back.CmdSealBlock(exit)

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(body)
        local body_env = { [counter_value.text] = bi }
        local contribution = lower_scalar_expr(cmds, reduction.value, body_env, reduction.ty)
        local next_acc = val("next.acc")
        local iop, bop = int_op(reduction.op), bit_op(reduction.op)
        if iop then cmds[#cmds + 1] = Back.CmdIntBinary(next_acc, iop, rscalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), bacc, contribution)
        elseif bop then cmds[#cmds + 1] = Back.CmdBitBinary(next_acc, bop, rscalar, bacc, contribution)
        else return nil end
        local step, next_i = val("step"), val("next.i")
        cmds[#cmds + 1] = Back.CmdConst(step, counter_scalar, Back.BackLitInt(step_raw))
        cmds[#cmds + 1] = Back.CmdIntBinary(next_i, Back.BackIntAdd, counter_scalar, Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose), bi, step)
        cmds[#cmds + 1] = Back.CmdJump(loop, { next_i, next_acc })
        cmds[#cmds + 1] = Back.CmdSealBlock(loop)

        cmds[#cmds + 1] = Back.CmdSwitchToBlock(exit)
        cmds[#cmds + 1] = Back.CmdReturnValue(eacc)
        cmds[#cmds + 1] = Back.CmdFinishFunc(func_id(func.id))
        return cmds
    end

    local function lower_func_by_id(lower_module)
        local out, has_kernel = {}, false
        for _, item in ipairs(lower_module and lower_module.funcs or {}) do
            local cls = pvm.classof(item)
            if cls == Lower.LowerFuncCode then
                out[item.func.text] = item
            elseif cls == Lower.LowerFuncKernel then
                local func = item.plan and item.plan.subject and item.plan.subject.func or nil
                if func ~= nil then out[func.text] = item; has_kernel = true end
            end
        end
        return out, has_kernel
    end

    local function append_all(out, xs)
        for i = 1, #(xs or {}) do out[#out + 1] = xs[i] end
    end

    local function module(code_module, lower_module, opts)
        opts = opts or {}
        local kernel_semantics = lower_module and lower_module.kernels and lower_module.kernels.memory_semantics or nil
        -- Prefer ASDL-carried semantics.  The opts fallback exists only for
        -- direct legacy tests/callers that have not rebuilt a KernelModulePlan.
        local sem_idx = semantic_index(kernel_semantics or opts.mem_semantics or opts.memory_semantics)
        local by_func, has_kernel = lower_func_by_id(lower_module)
        if not has_kernel then return CodeToBack.module(code_module, opts) end

        local cmds = {}
        append_all(cmds, CodeToBack.module_prelude_commands(code_module, opts))
        for _, func in ipairs(code_module.funcs or {}) do cmds[#cmds + 1] = CodeToBack.function_declare(func) end
        for _, func in ipairs(code_module.funcs or {}) do
            local item = by_func[func.id.text]
            if item ~= nil and pvm.classof(item) == Lower.LowerFuncKernel then
                local body_cmds = kernel_body_commands(func, item.plan, sem_idx)
                if body_cmds == nil then error("lower_to_back: unsupported whole-function kernel " .. tostring(func.name), 2) end
                append_all(cmds, body_cmds)
            else
                append_all(cmds, CodeToBack.function_body_commands(code_module, func))
            end
        end
        cmds[#cmds + 1] = Back.CmdFinalizeModule
        return Back.BackProgram(cmds)
    end

    api.module = module
    api.program = module

    T._moonlift_api_cache.lower_to_back = api
    return api
end

return M
