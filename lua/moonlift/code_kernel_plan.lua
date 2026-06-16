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
    if T._moonlift_api_cache.code_kernel_plan ~= nil then return T._moonlift_api_cache.code_kernel_plan end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Flow = T.MoonFlow
    local Mem = T.MoonMem
    local Kernel = T.MoonKernel
    local Back = T.MoonBack
    local BackTargetModel = require("moonlift.back_target_model").Define(T)

    local api = {}

    local function func_by_id(module)
        local out = {}
        for _, func in ipairs(module.funcs or {}) do out[func.id.text] = func end
        return out
    end

    local function block_set(blocks)
        local out = {}
        for _, block in ipairs(blocks or {}) do out[block.text] = true end
        return out
    end

    local function mem_by_func(memory)
        local out, by_id = {}, {}
        for _, access in ipairs(memory and memory.accesses or {}) do
            out[access.func.text] = out[access.func.text] or {}
            out[access.func.text][#out[access.func.text] + 1] = access
            by_id[access.id.text] = access
        end
        return out, by_id
    end

    local function store_values(module)
        local out = {}
        for _, func in ipairs(module.funcs or {}) do
            for _, block in ipairs(func.blocks or {}) do
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    local cls = pvm.classof(k)
                    if cls == Code.CodeInstStore or cls == Code.CodeInstAtomicStore or cls == Code.CodeInstAtomicRmw then
                        out[inst.id.text] = k.value
                    elseif cls == Code.CodeInstAtomicCas then
                        out[inst.id.text] = k.replacement
                    end
                end
            end
        end
        return out
    end

    local function func_blocks(func)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do out[block.id.text] = block end
        return out
    end

    local function func_value_defs(func)
        local defs = {}
        for _, block in ipairs(func.blocks or {}) do
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                local cls = pvm.classof(k)
                if cls == Code.CodeInstConst then defs[k.dst.text] = { cls = cls, inst = inst, const = k.const }
                elseif cls == Code.CodeInstAlias then defs[k.dst.text] = { cls = cls, inst = inst, ty = k.ty, src = k.src }
                elseif cls == Code.CodeInstBinary then defs[k.dst.text] = { cls = cls, inst = inst, op = k.op, ty = k.ty, semantics = k.semantics, lhs = k.lhs, rhs = k.rhs }
                elseif cls == Code.CodeInstFloatBinary then defs[k.dst.text] = { cls = cls, inst = inst, op = k.op, ty = k.ty, mode = k.mode, lhs = k.lhs, rhs = k.rhs }
                elseif cls == Code.CodeInstCompare then defs[k.dst.text] = { cls = cls, inst = inst, op = k.op, ty = Code.CodeTyBool8, operand_ty = k.operand_ty, lhs = k.lhs, rhs = k.rhs }
                elseif cls == Code.CodeInstSelect then defs[k.dst.text] = { cls = cls, inst = inst, ty = k.ty, cond = k.cond, then_value = k.then_value, else_value = k.else_value }
                elseif cls == Code.CodeInstLoad then defs[k.dst.text] = { cls = cls, inst = inst, place = k.place, access = k.access }
                end
            end
        end
        return defs
    end


    local function stream_kind(access)
        if access.kind == Mem.MemLoad or access.kind == Mem.MemAtomicLoad then return Kernel.KernelStreamRead end
        if access.kind == Mem.MemStore or access.kind == Mem.MemAtomicStore then return Kernel.KernelStreamWrite end
        return Kernel.KernelStreamReadWrite
    end

    local function is_atomic(access)
        return access.kind == Mem.MemAtomicLoad or access.kind == Mem.MemAtomicStore or access.kind == Mem.MemAtomicRmw or access.kind == Mem.MemAtomicCas
    end

    local function is_kernel_stream_access(access)
        -- View descriptor locals are compiler-carried aggregate values. Back lowering
        -- aliases their parts instead of emitting user-memory loads/stores, so they
        -- must not become kernel streams or safety blockers.
        return not (pvm.classof(access.access.ty) == Code.CodeTyView and pvm.classof(access.place) == Code.CodePlaceLocal)
    end

    local function offset_for(index)
        local cls = pvm.classof(index)
        if cls == Mem.MemIndexInduction then return Kernel.KernelOffsetInduction(index.induction) end
        if cls == Mem.MemIndexValue then return Kernel.KernelOffsetValue(index.value) end
        return Kernel.KernelOffsetZero
    end

    local function counter_for(loop)
        local induction = loop.inductions and loop.inductions[1] or nil
        if induction == nil then return nil, Kernel.KernelRejectUnsupportedLoop(loop.id, "loop has no primary induction") end
        local cls = pvm.classof(induction.ty)
        local proofs = { Kernel.KernelProofFlow(loop.id, "FlowLoopFacts primary induction") }
        if induction.ty == Code.CodeTyIndex then return Kernel.KernelCounterIndex(induction.value, proofs), nil end
        if cls == Code.CodeTyInt and induction.ty.bits == 32 then return Kernel.KernelCounterI32(induction.value, proofs), nil end
        if cls == Code.CodeTyDataPtr then return Kernel.KernelCounterPointer(induction.value, 1, proofs), nil end
        return nil, Kernel.KernelRejectUnsupportedLoop(loop.id, "unsupported induction counter type")
    end

    local function stream_for(access, loop)
        return Kernel.KernelStream(
            Kernel.KernelStreamId("stream:" .. sanitize(access.id.text)),
            stream_kind(access),
            access.base,
            access.access.ty,
            offset_for(access.index),
            Kernel.KernelLenLoopDomain(loop.id),
            access.pattern,
            access.alignment,
            access.bounds,
            { access.id }
        )
    end

    local function access_lookup(accesses)
        local out = {}
        for _, access in ipairs(accesses) do out[access.id.text] = access end
        return out
    end

    local function stream_lookup(streams)
        local out = {}
        for _, stream in ipairs(streams) do
            for _, id in ipairs(stream.accesses or {}) do out[id.text] = stream end
        end
        return out
    end

    local function semantic_index(semantics)
        if semantics == nil then return nil end
        local idx = { inbounds = {}, nontrap = {}, movable = {}, deref = {}, align = {}, no_dependence = {}, read_read = {} }
        for _, safety in ipairs(semantics.safety or {}) do
            local cls = pvm.classof(safety)
            if cls == Mem.MemAccessInBounds then idx.inbounds[safety.interval.access.text] = safety.proof
            elseif cls == Mem.MemAccessNonTrap then idx.nontrap[safety.access.text] = safety.proof
            elseif cls == Mem.MemAccessMovable then idx.movable[safety.access.text] = safety.proof
            elseif cls == Mem.MemAccessDerefBytes then idx.deref[safety.access.text] = safety.proof
            elseif cls == Mem.MemAccessAlignKnown then idx.align[safety.access.text] = safety.proof end
        end
        for _, dep in ipairs(semantics.dependences or {}) do
            local cls = pvm.classof(dep)
            if cls == Mem.MemNoDependence or cls == Mem.MemNoLoopCarriedDependence or cls == Mem.MemDependenceDistance then
                idx.no_dependence[dep.before.text .. "\0" .. dep.after.text] = dep
                idx.no_dependence[dep.after.text .. "\0" .. dep.before.text] = dep
            elseif cls == Mem.MemReadReadIndependent then
                idx.read_read[dep.a.text .. "\0" .. dep.b.text] = dep
                idx.read_read[dep.b.text .. "\0" .. dep.a.text] = dep
            end
        end
        return idx
    end

    local function stream_read_only(stream)
        return stream ~= nil and stream.kind == Kernel.KernelStreamRead
    end

    local function add_memory_rejections(func_id, access, stream, semantic_idx, rejects, assumptions, proofs)
        if access.access.volatile then rejects[#rejects + 1] = Kernel.KernelRejectVolatile(access.id, "volatile access cannot be scheduled as a kernel stream") end
        if is_atomic(access) then rejects[#rejects + 1] = Kernel.KernelRejectAtomic(access.id, "atomic access cannot be reordered or vectorized") end
        local inbounds = semantic_idx and semantic_idx.inbounds[access.id.text] or nil
        local nontrap = semantic_idx and semantic_idx.nontrap[access.id.text] or nil
        if inbounds == nil then
            rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "normalized in-bounds fact is missing")
        else
            proofs[#proofs + 1] = Kernel.KernelProofMemory(inbounds, "normalized in-bounds access interval")
        end
        if nontrap == nil then
            rejects[#rejects + 1] = Kernel.KernelRejectTrap(access.id, "normalized nontrap fact is missing")
        else
            proofs[#proofs + 1] = Kernel.KernelProofMemory(nontrap, "normalized nontrap memory access")
        end
        if access.pattern == Mem.MemAccessUnknown or access.pattern == Mem.MemAccessGather or access.pattern == Mem.MemAccessScatter then
            rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedMemory(access.id, "memory access pattern is not a simple scalar/contiguous stream")
        end
    end

    local function add_alias_dependence_rejections(func_id, streams_by_access, memory, semantic_idx, rejects, assumptions, proofs)
        for _, fact in ipairs(memory.aliases or {}) do
            local cls = pvm.classof(fact)
            local a_id, b_id = fact.a, fact.b
            if a_id ~= nil and b_id ~= nil and streams_by_access[a_id.text] ~= nil and streams_by_access[b_id.text] ~= nil then
                local a, b = streams_by_access[a_id.text], streams_by_access[b_id.text]
                if stream_read_only(a) and stream_read_only(b) then
                    -- Read/read aliasing is harmless for the stream plans this pass builds.
                elseif cls == Mem.MemNoAlias or cls == Mem.MemSameBaseSameIndexSafe then
                    proofs[#proofs + 1] = Kernel.KernelProofAlias(fact, "memory alias fact")
                elseif semantic_idx ~= nil and semantic_idx.no_dependence[a_id.text .. "\0" .. b_id.text] ~= nil then
                    proofs[#proofs + 1] = Kernel.KernelProofDependence(semantic_idx.no_dependence[a_id.text .. "\0" .. b_id.text], "normalized no-dependence makes write-related aliasing schedulable")
                else
                    rejects[#rejects + 1] = Kernel.KernelRejectAlias(fact, "normalized no-alias/no-dependence fact is missing for write-related streams")
                end
            end
        end
        for _, fact in ipairs(memory.dependences or {}) do
            local cls = pvm.classof(fact)
            local before, after = fact.before, fact.after
            if before ~= nil and after ~= nil and streams_by_access[before.text] ~= nil and streams_by_access[after.text] ~= nil then
                local a, b = streams_by_access[before.text], streams_by_access[after.text]
                if stream_read_only(a) and stream_read_only(b) then
                    -- There should be no write-related dependence for read/read pairs.
                elseif cls == Mem.MemNoDependence or cls == Mem.MemNoLoopCarriedDependence then
                    proofs[#proofs + 1] = Kernel.KernelProofDependence(fact, "memory dependence fact")
                elseif semantic_idx ~= nil and semantic_idx.no_dependence[before.text .. "\0" .. after.text] ~= nil then
                    proofs[#proofs + 1] = Kernel.KernelProofDependence(semantic_idx.no_dependence[before.text .. "\0" .. after.text], "normalized dependence fact")
                else
                    rejects[#rejects + 1] = Kernel.KernelRejectDependence(fact, "normalized write-related no-dependence fact is missing")
                end
            end
        end
    end

    local function back_scalar_for(ty)
        local cls = pvm.classof(ty)
        if ty == Code.CodeTyIndex then return Back.BackIndex end
        if ty == Code.CodeTyBool8 then return Back.BackBool end
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return ty.signedness == Code.CodeUnsigned and Back.BackU8 or Back.BackI8 end
            if ty.bits == 16 then return ty.signedness == Code.CodeUnsigned and Back.BackU16 or Back.BackI16 end
            if ty.bits == 32 then return ty.signedness == Code.CodeUnsigned and Back.BackU32 or Back.BackI32 end
            if ty.bits == 64 then return ty.signedness == Code.CodeUnsigned and Back.BackU64 or Back.BackI64 end
        elseif cls == Code.CodeTyFloat then
            if ty.bits == 32 then return Back.BackF32 end
            if ty.bits == 64 then return Back.BackF64 end
        end
        return nil
    end

    local function vector_op_class(op)
        if op == Core.BinAdd or op == Core.BinSub or op == Core.BinMul then return "int_binary" end
        if op == Core.BinBitAnd or op == Core.BinBitOr or op == Core.BinBitXor then return "bit_binary" end
        return nil
    end

    local function collect_expr_op_classes(expr, out)
        if expr == nil then return out end
        out = out or {}
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprBinary then
            local op_class = vector_op_class(expr.op)
            if op_class ~= nil then out[op_class] = true end
            collect_expr_op_classes(expr.lhs, out)
            collect_expr_op_classes(expr.rhs, out)
        elseif cls == Kernel.KernelExprCompare then
            out.compare_select = true
            collect_expr_op_classes(expr.lhs, out)
            collect_expr_op_classes(expr.rhs, out)
        elseif cls == Kernel.KernelExprSelect then
            out.compare_select = true
            collect_expr_op_classes(expr.cond, out)
            collect_expr_op_classes(expr.then_value, out)
            collect_expr_op_classes(expr.else_value, out)
        elseif cls == Kernel.KernelExprLoad or cls == Kernel.KernelExprConst or cls == Kernel.KernelExprValue or cls == Kernel.KernelExprKernelValue then
            return out
        end
        return out
    end

    local function vec_key(vec)
        return tostring(vec.elem.kind or vec.elem) .. ":" .. tostring(vec.lanes)
    end

    local function target_vector_choice(target_model, elem_ty, required_classes)
        target_model = target_model or BackTargetModel.default_native()
        local elem = back_scalar_for(elem_ty)
        if elem == nil then return nil, nil end
        local supported, op_support, preferred, masked_tail = {}, {}, {}, false
        for _, fact in ipairs(target_model.facts or {}) do
            local cls = pvm.classof(fact)
            if cls == Back.BackTargetSupportsShape and pvm.classof(fact.shape) == Back.BackShapeVec then
                local vec = fact.shape.vec
                if vec.elem == elem and vec.lanes > 1 then supported[#supported + 1] = vec end
            elseif cls == Back.BackTargetSupportsVectorOp then
                op_support[vec_key(fact.vec)] = op_support[vec_key(fact.vec)] or {}
                op_support[vec_key(fact.vec)][fact.op_class] = true
            elseif cls == Back.BackTargetPrefersUnroll and pvm.classof(fact.shape) == Back.BackShapeVec then
                local vec = fact.shape.vec
                preferred[vec_key(vec)] = preferred[vec_key(vec)] or { unroll = fact.unroll, rank = fact.rank }
                if fact.rank > preferred[vec_key(vec)].rank then preferred[vec_key(vec)] = { unroll = fact.unroll, rank = fact.rank } end
            elseif cls == Back.BackTargetSupportsMaskedTail then
                masked_tail = true
            end
        end
        local best, best_pref
        for _, vec in ipairs(supported) do
            local ok = true
            for class in pairs(required_classes or {}) do
                if op_support[vec_key(vec)] == nil or not op_support[vec_key(vec)][class] then ok = false; break end
            end
            if ok then
                local pref = preferred[vec_key(vec)] or { unroll = 1, rank = 0 }
                if best == nil or pref.rank > best_pref.rank or (pref.rank == best_pref.rank and vec.lanes > best.lanes) then
                    best, best_pref = vec, pref
                end
            end
        end
        return best, best_pref, masked_tail
    end

    local function schedule_for(streams, proofs, rejected, required_classes, target_model)
        local elem_ty = streams[1] and streams[1].elem_ty or Code.CodeTyIndex
        local vector_ok = #streams > 0
        for _, stream in ipairs(streams) do
            if stream.pattern ~= Mem.MemAccessContiguous then vector_ok = false end
        end
        if vector_ok then
            local vec, pref = target_vector_choice(target_model, elem_ty, required_classes)
            if vec ~= nil then
                return Kernel.KernelScheduleVector(Kernel.KernelLaneVector(elem_ty, vec.lanes), pref.unroll or 1, 1, Kernel.KernelTailScalar, proofs), rejected
            end
            rejected[#rejected + 1] = Kernel.KernelRejectSchedule("target model has no supported vector shape/op-class combination for streams")
        else
            rejected[#rejected + 1] = Kernel.KernelRejectSchedule("vector schedule requires contiguous streams")
        end
        return Kernel.KernelScheduleScalarIndex(proofs), rejected
    end

    local function literal_raw(defs, value)
        local def = value and defs[value.text] or nil
        if def == nil or def.cls ~= Code.CodeInstConst or pvm.classof(def.const) ~= Code.CodeConstLiteral then return nil end
        local lit = def.const.literal
        return lit and lit.raw or nil
    end

    local function reduction_identity(op)
        if op == Core.BinAdd or op == Core.BinBitOr or op == Core.BinBitXor then return "0" end
        if op == Core.BinMul then return "1" end
        return nil
    end

    local function kernel_expr_for(value, defs, stream_by_inst, seen)
        if value == nil then return Kernel.KernelExprValue(Code.CodeValueId("unknown")) end
        seen = seen or {}
        if seen[value.text] then return Kernel.KernelExprValue(value) end
        seen[value.text] = true
        local function branch_seen()
            local out = {}
            for k, v in pairs(seen) do out[k] = v end
            return out
        end
        local def = defs[value.text]
        if def == nil then return Kernel.KernelExprValue(value) end
        if def.cls == Code.CodeInstAlias then return kernel_expr_for(def.src, defs, stream_by_inst, seen) end
        if def.cls == Code.CodeInstConst then return Kernel.KernelExprConst(def.const) end
        if def.cls == Code.CodeInstLoad then
            local stream = def.inst and stream_by_inst[def.inst.id.text] or nil
            if stream ~= nil then return Kernel.KernelExprLoad(stream, stream.offset) end
            return Kernel.KernelExprValue(value)
        end
        if def.cls == Code.CodeInstBinary then
            return Kernel.KernelExprBinary(def.op, def.ty, def.semantics, nil, kernel_expr_for(def.lhs, defs, stream_by_inst, branch_seen()), kernel_expr_for(def.rhs, defs, stream_by_inst, branch_seen()))
        end
        if def.cls == Code.CodeInstFloatBinary then
            return Kernel.KernelExprBinary(def.op, def.ty, nil, def.mode, kernel_expr_for(def.lhs, defs, stream_by_inst, branch_seen()), kernel_expr_for(def.rhs, defs, stream_by_inst, branch_seen()))
        end
        if def.cls == Code.CodeInstCompare then
            return Kernel.KernelExprCompare(def.op, def.operand_ty, kernel_expr_for(def.lhs, defs, stream_by_inst, branch_seen()), kernel_expr_for(def.rhs, defs, stream_by_inst, branch_seen()))
        end
        if def.cls == Code.CodeInstSelect then
            return Kernel.KernelExprSelect(kernel_expr_for(def.cond, defs, stream_by_inst, branch_seen()), kernel_expr_for(def.then_value, defs, stream_by_inst, branch_seen()), kernel_expr_for(def.else_value, defs, stream_by_inst, branch_seen()))
        end
        return Kernel.KernelExprValue(value)
    end

    local function successor_args_to(block, dest)
        local term = block and block.term and block.term.kind or nil
        local cls = pvm.classof(term)
        if cls == Code.CodeTermJump and term.dest == dest then return term.args or {} end
        if cls == Code.CodeTermBranch then
            if term.then_dest == dest then return term.then_args or {} end
            if term.else_dest == dest then return term.else_args or {} end
        elseif cls == Code.CodeTermSwitch then
            if term.default_dest == dest then return term.default_args or {} end
            for _, case in ipairs(term.cases or {}) do if case.dest == dest then return case.args or {} end end
        elseif cls == Code.CodeTermVariantSwitch then
            if term.default_dest == dest then return term.default_args or {} end
            for _, case in ipairs(term.cases or {}) do if case.dest == dest then return case.args or {} end end
        end
        return {}
    end

    local function propagate_known(dest_block, args, known)
        local next_known = {}
        for k, v in pairs(known or {}) do next_known[k] = v end
        for i, arg in ipairs(args or {}) do
            local param = dest_block and dest_block.params and dest_block.params[i] or nil
            if param ~= nil and known[arg.text] then next_known[param.value.text] = true end
        end
        return next_known
    end

    local function loop_exit_returns(func, loop, seed_known)
        local blocks = func_blocks(func)
        local in_loop = block_set(loop.body_blocks)
        local queue, seen, returns = {}, {}, {}
        for _, exit in ipairs(loop.exits or {}) do
            if exit.to ~= nil and not in_loop[exit.to.text] then
                local pred = blocks[exit.from.text]
                local dest = blocks[exit.to.text]
                local known = propagate_known(dest, successor_args_to(pred, exit.to), seed_known or {})
                queue[#queue + 1] = { block = exit.to, known = known }
            end
        end
        while #queue > 0 do
            local item = table.remove(queue, 1)
            local block = blocks[item.block.text]
            if block ~= nil then
                local key_bits = {}
                for k in pairs(item.known) do key_bits[#key_bits + 1] = k end
                table.sort(key_bits)
                local seen_key = item.block.text .. "\0" .. table.concat(key_bits, "\0")
                if not seen[seen_key] then
                    seen[seen_key] = true
                    local known = {}
                    for k, v in pairs(item.known) do known[k] = v end
                    for _, inst in ipairs(block.insts or {}) do
                        local k = inst.kind
                        if pvm.classof(k) == Code.CodeInstAlias and known[k.src.text] then known[k.dst.text] = true end
                    end
                    local term = block.term and block.term.kind or nil
                    local cls = pvm.classof(term)
                    if cls == Code.CodeTermReturn then
                        returns[#returns + 1] = { values = term.values or {}, known = known }
                    elseif cls == Code.CodeTermJump then
                        if not in_loop[term.dest.text] then queue[#queue + 1] = { block = term.dest, known = propagate_known(blocks[term.dest.text], term.args or {}, known) } end
                    elseif cls == Code.CodeTermBranch then
                        if not in_loop[term.then_dest.text] then queue[#queue + 1] = { block = term.then_dest, known = propagate_known(blocks[term.then_dest.text], term.then_args or {}, known) } end
                        if not in_loop[term.else_dest.text] then queue[#queue + 1] = { block = term.else_dest, known = propagate_known(blocks[term.else_dest.text], term.else_args or {}, known) } end
                    end
                end
            end
        end
        return returns
    end

    local function function_returns_value_from_loop_exit(func, loop, value)
        local returns = loop_exit_returns(func, loop, { [value.text] = true })
        if #returns == 0 then return false end
        for _, ret in ipairs(returns) do
            if #ret.values ~= 1 or ret.known[ret.values[1].text] ~= true then return false end
        end
        return true
    end

    local function simple_result_from_loop_exit(func, loop, defs, stream_by_inst)
        local returns = loop_exit_returns(func, loop, {})
        if #returns == 0 then return nil end
        local first_key, first_value
        for _, ret in ipairs(returns) do
            if #ret.values == 0 then
                if first_key == nil then first_key = "void" elseif first_key ~= "void" then return nil end
            elseif #ret.values == 1 then
                local v = ret.values[1]
                local key = "value:" .. v.text
                local raw = literal_raw(defs, v)
                if raw ~= nil then key = "const:" .. raw end
                if first_key == nil then first_key, first_value = key, v elseif first_key ~= key then return nil end
            else
                return nil
            end
        end
        if first_key == "void" then return Kernel.KernelResultVoid end
        return Kernel.KernelResultExpr(kernel_expr_for(first_value, defs, stream_by_inst))
    end

    local function backedge_value_for(func, loop, value)
        local blocks = func_blocks(func)
        local source = loop.source
        if pvm.classof(source) ~= Flow.FlowLoopFromCode then return nil end
        local header, latch = blocks[source.header.text], blocks[source.backedge.text]
        if header == nil or latch == nil then return nil end
        local param_index
        for i, param in ipairs(header.params or {}) do if param.value == value then param_index = i end end
        if param_index == nil then return nil end
        local term = latch.term and latch.term.kind or nil
        if pvm.classof(term) ~= Code.CodeTermJump or term.dest ~= header.id then return nil end
        return term.args[param_index]
    end

    local function int_const_expr(ty, raw)
        return Kernel.KernelExprConst(Code.CodeConstLiteral(ty, Core.LitInt(tostring(raw))))
    end

    local function int_bin(op, ty, semantics, lhs, rhs)
        return Kernel.KernelExprBinary(op, ty, semantics, nil, lhs, rhs)
    end

    local function arithmetic_series_closed_form(loop, counter, reduction, contribution_value, update_def, defs)
        if counter == nil or contribution_value == nil or update_def == nil then return nil end
        if reduction == nil or reduction.op ~= Core.BinAdd or reduction.identity ~= "0" then return nil end
        if contribution_value ~= counter.value then return nil end
        local domain = loop.domain and loop.domain.counted
        if domain == nil then return nil end
        if literal_raw(defs, domain.start) ~= "0" or literal_raw(defs, domain.step) ~= "1" or domain.stop_exclusive ~= true then return nil end
        local ty = reduction.ty
        local ty_cls = pvm.classof(ty)
        if ty_cls ~= Code.CodeTyInt or ty.signedness ~= Code.CodeSigned then return nil end
        local semantics = update_def.semantics or Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount)
        if semantics.overflow ~= Code.CodeIntWrap then return nil end

        local n = Kernel.KernelExprValue(domain.stop)
        local zero = int_const_expr(ty, "0")
        local one = int_const_expr(ty, "1")
        local two = int_const_expr(ty, "2")
        local n_minus_one = int_bin(Core.BinSub, ty, semantics, n, one)
        local n_le_zero = Kernel.KernelExprCompare(Core.CmpLe, ty, n, zero)
        local n_even = Kernel.KernelExprCompare(Core.CmpEq, ty, int_bin(Core.BinBitAnd, ty, semantics, n, one), zero)
        local even_part = int_bin(Core.BinMul, ty, semantics, int_bin(Core.BinDiv, ty, semantics, n, two), n_minus_one)
        local odd_part = int_bin(Core.BinMul, ty, semantics, n, int_bin(Core.BinDiv, ty, semantics, n_minus_one, two))
        local positive_sum = Kernel.KernelExprSelect(n_even, even_part, odd_part)
        local value = Kernel.KernelExprSelect(n_le_zero, zero, positive_sum)
        local kind = Kernel.KernelClosedFormArithmeticSeries(reduction.op, ty, domain)
        return Kernel.KernelClosedForm(kind, reduction, value, {
            Kernel.KernelProofClosedForm(kind, "arithmetic series closed form under wrapping integer semantics")
        })
    end

    local function complete_reduction_for_func(func, loop, counter, stream_by_inst, defs)
        defs = defs or func_value_defs(func)
        for _, induction in ipairs(loop.inductions or {}) do
            if counter ~= nil and induction.value ~= (loop.inductions[1] and loop.inductions[1].value) then
                local back = backedge_value_for(func, loop, induction.value)
                local def = back and defs[back.text] or nil
                if def ~= nil and def.cls == Code.CodeInstBinary then
                    local contribution
                    if def.lhs == induction.value then contribution = def.rhs
                    elseif def.rhs == induction.value then contribution = def.lhs end
                    local identity = contribution and reduction_identity(def.op) or nil
                    if identity ~= nil and literal_raw(defs, induction.init) == identity and function_returns_value_from_loop_exit(func, loop, induction.value) then
                        local proofs = { Kernel.KernelProofReduction("whole-function counted reduction returns final accumulator") }
                        local fold = Kernel.KernelFold(
                            Kernel.KernelValueId("fold:" .. sanitize(induction.value.text)),
                            def.op,
                            def.ty,
                            kernel_expr_for(induction.init, defs, stream_by_inst),
                            kernel_expr_for(contribution, defs, stream_by_inst),
                            identity,
                            proofs,
                            induction.value
                        )
                        return fold, arithmetic_series_closed_form(loop, counter, fold, contribution, def, defs)
                    end
                end
            end
        end
        return nil
    end

    local function plan_loop(func, loop, memory, semantic_idx, func_accesses, store_value_by_inst, target_model)
        local rejects, assumptions, proofs = {}, {}, { Kernel.KernelProofFlow(loop.id, "flow loop facts") }
        if pvm.classof(loop.domain) ~= Flow.FlowDomainCounted then
            rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedLoop(loop.id, "loop is not counted")
        end
        for _, reject in ipairs(loop.rejects or {}) do
            rejects[#rejects + 1] = Kernel.KernelRejectUnsupportedLoop(loop.id, reject.reason or "flow rejected loop")
        end
        local counter, counter_reject = counter_for(loop)
        if counter_reject ~= nil then rejects[#rejects + 1] = counter_reject end

        local covered = block_set(loop.body_blocks)
        local accesses = {}
        for _, access in ipairs(func_accesses or {}) do
            if covered[access.block.text] and is_kernel_stream_access(access) then accesses[#accesses + 1] = access end
        end
        local streams, stores, stream_by_inst = {}, {}, {}
        local defs = func_value_defs(func)
        for _, access in ipairs(accesses) do
            local stream = stream_for(access, loop)
            streams[#streams + 1] = stream
            if access.inst ~= nil then stream_by_inst[access.inst.text] = stream end
            add_memory_rejections(func.id, access, stream, semantic_idx, rejects, assumptions, proofs)
        end
        for _, access in ipairs(accesses) do
            local stream = access.inst and stream_by_inst[access.inst.text] or nil
            if stream ~= nil and (stream.kind == Kernel.KernelStreamWrite or stream.kind == Kernel.KernelStreamReadWrite) then
                local value = access.inst and store_value_by_inst[access.inst.text] or nil
                stores[#stores + 1] = Kernel.KernelStore(stream, stream.offset, kernel_expr_for(value or Code.CodeValueId("unknown:" .. access.id.text), defs, stream_by_inst))
            end
        end
        add_alias_dependence_rejections(func.id, stream_lookup(streams), memory, semantic_idx, rejects, assumptions, proofs)

        local subject = Kernel.KernelSubjectLoop(func.id, loop.id)
        if #rejects > 0 or counter == nil then return Kernel.KernelNoPlan(subject, rejects) end
        local safety = (#assumptions > 0) and Kernel.KernelSafetyAssumed(proofs, assumptions) or Kernel.KernelSafetyProven(proofs)
        local effects = {}
        local required_vector_classes = {}
        for _, store in ipairs(stores) do
            collect_expr_op_classes(store.value, required_vector_classes)
            effects[#effects + 1] = Kernel.KernelEffectStore(store)
        end
        local reduction, closed_form = complete_reduction_for_func(func, loop, counter, stream_by_inst, defs)
        if reduction ~= nil then
            local op_class = vector_op_class(reduction.op)
            if op_class ~= nil then required_vector_classes[op_class] = true end
            collect_expr_op_classes(reduction.value, required_vector_classes)
            effects[#effects + 1] = Kernel.KernelEffectFold(reduction)
        end
        local rejected_schedules = {}
        local schedule = schedule_for(streams, proofs, rejected_schedules, required_vector_classes, target_model)
        local result = closed_form and Kernel.KernelResultClosedForm(closed_form) or (reduction and Kernel.KernelResultFold(reduction.id) or simple_result_from_loop_exit(func, loop, defs, stream_by_inst))
        if result ~= nil and (#effects > 0 or reduction ~= nil) then
            local body = Kernel.KernelBodyCounted(loop, counter, streams, {}, effects, result, safety)
            return Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(func.name) .. ":function"), Kernel.KernelSubjectFunc(func.id), body, schedule, rejected_schedules)
        end
        local body = Kernel.KernelBodyCounted(loop, counter, streams, {}, effects, Kernel.KernelResultVoid, safety)
        return Kernel.KernelPlanned(Kernel.KernelId("kernel:" .. sanitize(func.name) .. ":" .. sanitize(loop.id.text)), subject, body, schedule, rejected_schedules)
    end

    local function plan(module, flow, memory, contracts, flow_semantics, mem_semantics, opts)
        -- Compatibility: older callers passed memory semantics as the fifth
        -- argument.  The ASDL plan owns both semantic fact sets now, so new
        -- callers should pass flow_semantics, mem_semantics explicitly.
        if mem_semantics == nil and flow_semantics ~= nil and pvm.classof(flow_semantics) == Mem.MemSemanticFactSet then
            mem_semantics = flow_semantics
            flow_semantics = nil
        end
        opts = opts or {}
        local funcs = func_by_id(module)
        local accesses_by_func = mem_by_func(memory)
        local sem_idx = semantic_index(mem_semantics)
        local store_value_by_inst = store_values(module)
        local target_model = opts.target_model or opts.back_target_model or BackTargetModel.default_native()
        local plan_by_func = {}
        for _, loop in ipairs(flow and flow.loops or {}) do
            local func_id = loop.source and loop.source.func or nil
            local func = func_id and funcs[func_id.text] or nil
            if func ~= nil and plan_by_func[func.id.text] == nil then
                plan_by_func[func.id.text] = plan_loop(func, loop, memory or Mem.MemFactSet(module.id, {}, {}, {}, {}), sem_idx, accesses_by_func[func.id.text] or {}, store_value_by_inst, target_model)
            end
        end
        local out = {}
        for _, func in ipairs(module.funcs or {}) do
            if plan_by_func[func.id.text] ~= nil then
                out[#out + 1] = Kernel.KernelFuncPlan(func.id, plan_by_func[func.id.text])
            end
        end
        return Kernel.KernelModulePlan(module.id, flow or Flow.FlowFactSet(module.id, {}, {}, {}, {}), memory or Mem.MemFactSet(module.id, {}, {}, {}, {}), out, flow_semantics, mem_semantics)
    end

    api.plan = plan
    api.module = plan

    T._moonlift_api_cache.code_kernel_plan = api
    return api
end

return M
