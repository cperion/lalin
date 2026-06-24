local pvm = require("moonlift.pvm")

local function class_name(value)
    local cls = pvm.classof(value) or value
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

local function sanitize(s)
    s = tostring(s or "x"):gsub("[^%w_]", "_")
    if s == "" then s = "x" end
    if s:match("^%d") then s = "_" .. s end
    return s
end

local function bind_context(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.luajit_lower ~= nil then return T._moonlift_api_cache.luajit_lower end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Flow = T.MoonFlow
    local Value = T.MoonValue
    local Mem = T.MoonMem
    local Kernel = T.MoonKernel
    local LJ = T.MoonLuaJIT
    local Stencil = T.MoonStencil

    local CType = require("moonlift.luajit_ctype")(T)
    local Expr = require("moonlift.luajit_expr")(T)
    local CodeGraph = require("moonlift.code_graph")(T)
    local CodeFlowFacts = require("moonlift.code_flow_facts")(T)
    local CodeValueFacts = require("moonlift.code_value_facts")(T)
    local CodeMemFacts = require("moonlift.code_mem_facts")(T)
    local CodeEffectFacts = require("moonlift.code_effect_facts")(T)
    local CodeKernelPlan = require("moonlift.code_kernel_plan")(T)

    local api = {}

    local function vid(id) return LJ.LJValueId((id.text or ""):gsub("^v:", "")) end
    local function bid(id) return LJ.LJBlockId(id.text) end
    local function fid(id) return LJ.LJFuncId(id.text) end
    local function sigid(id) return LJ.LJFuncSigId(id.text) end

    local function physical(ctx, ty)
        return CType.physical_type(ty, ctx)
    end

    local function literal_expr(ctx, ty, raw)
        return LJ.LJExprLiteral(Core.LitInt(tostring(raw)), physical(ctx, ty))
    end

    local function code_sigs(module)
        local out = {}
        for _, sig in ipairs(module.sigs or {}) do out[sig.id.text] = sig end
        return out
    end

    local function block_index(func)
        local out = {}
        for _, block in ipairs(func.blocks or {}) do out[block.id.text] = block end
        return out
    end

    local function func_index(module)
        local out = {}
        for _, func in ipairs(module.funcs or {}) do out[func.id.text] = func end
        return out
    end

    local function value_defs(func)
        local defs = {}
        for _, param in ipairs(func.params or {}) do defs[param.value.text] = { param = param, ty = param.ty } end
        for _, block in ipairs(func.blocks or {}) do
            for _, param in ipairs(block.params or {}) do defs[param.value.text] = { param = param, ty = param.ty } end
            for _, inst in ipairs(block.insts or {}) do
                local k = inst.kind
                if k.dst ~= nil then defs[k.dst.text] = { inst = inst, kind = k } end
            end
        end
        return defs
    end

    local function value_type(ctx, id)
        local ty = ctx.value_types and id and ctx.value_types[id.text] or nil
        if ty ~= nil then return ty end
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        if def == nil then return Code.CodeTyIndex end
        if def.ty ~= nil then return def.ty end
        local k = def.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then return k.const.ty end
        if cls == Code.CodeInstAlias or cls == Code.CodeInstUnary or cls == Code.CodeInstBinary or cls == Code.CodeInstFloatBinary or cls == Code.CodeInstSelect or cls == Code.CodeInstAggregate or cls == Code.CodeInstArray then return k.ty end
        if cls == Code.CodeInstCompare then return Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.to end
        if cls == Code.CodeInstLoad then return k.access.ty end
        if cls == Code.CodeInstViewMake then return Code.CodeTyView(k.elem_ty) end
        if cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then return Code.CodeTyIndex end
        if cls == Code.CodeInstViewData then return Code.CodeTyDataPtr(nil) end
        if cls == Code.CodeInstAddrOf or cls == Code.CodeInstGlobalRef or cls == Code.CodeInstPtrOffset then return k.ptr_ty end
        if cls == Code.CodeInstVariantTag then return k.tag_ty end
        if cls == Code.CodeInstVariantPayload then return k.variant.payload_ty or Code.CodeTyVoid end
        return Code.CodeTyIndex
    end

    local function value_id_expr(ctx, id)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        if def ~= nil and pvm.classof(def.kind) == Code.CodeInstConst and pvm.classof(def.kind.const) == Code.CodeConstLiteral then
            return LJ.LJExprLiteral(def.kind.const.literal, physical(ctx, def.kind.const.ty))
        end
        return LJ.LJExprValue(vid(id))
    end

    local value_expr
    value_expr = function(ctx, expr)
        local cls = pvm.classof(expr)
        if cls == Value.ValueExprConst then
            return Expr.const_expr(ctx, expr.const)
        elseif cls == Value.ValueExprValue then
            return value_id_expr(ctx, expr.value)
        elseif cls == Value.ValueExprUnary then
            return LJ.LJExprUnary(expr.op, physical(ctx, expr.ty), value_expr(ctx, expr.value))
        elseif cls == Value.ValueExprCast then
            return LJ.LJExprCast(expr.op, physical(ctx, expr.from), physical(ctx, expr.to), value_expr(ctx, expr.value))
        elseif cls == Value.ValueExprAdd or cls == Value.ValueExprSub or cls == Value.ValueExprMul or cls == Value.ValueExprDiv then
            local op = (cls == Value.ValueExprAdd and Core.BinAdd)
                or (cls == Value.ValueExprSub and Core.BinSub)
                or (cls == Value.ValueExprMul and Core.BinMul)
                or Core.BinDiv
            return LJ.LJExprIntBinary(op, physical(ctx, expr.ty), expr.sem, value_expr(ctx, expr.a), value_expr(ctx, expr.b))
        end
        error("luajit_lower: unsupported ValueExpr " .. class_name(expr), 3)
    end

    local function note_params(ctx, params)
        for _, param in ipairs(params or {}) do
            ctx.value_types[param.value.text] = param.ty
        end
    end

    local function lower_param(ctx, param)
        return LJ.LJParam(vid(param.value), param.name, physical(ctx, param.ty))
    end

    local function lower_params(ctx, params)
        local out = {}
        for i, param in ipairs(params or {}) do out[i] = lower_param(ctx, param) end
        return out
    end

    local function lower_term(ctx, term)
        local k = term.kind
        local cls = pvm.classof(k)
        local function exprs(ids)
            local out = {}
            for i, id in ipairs(ids or {}) do out[i] = value_id_expr(ctx, id) end
            return out
        end
        if cls == Code.CodeTermJump then
            return LJ.LJTermJump(bid(k.dest), exprs(k.args))
        elseif cls == Code.CodeTermBranch then
            return LJ.LJTermBranch(value_id_expr(ctx, k.cond), bid(k.then_dest), exprs(k.then_args), bid(k.else_dest), exprs(k.else_args))
        elseif cls == Code.CodeTermSwitch then
            local cases = {}
            for i, case in ipairs(k.cases or {}) do cases[i] = LJ.LJCase(case.literal, bid(case.dest), exprs(case.args)) end
            return LJ.LJTermSwitch(value_id_expr(ctx, k.value), cases, bid(k.default_dest), exprs(k.default_args))
        elseif cls == Code.CodeTermVariantSwitch then
            local cases = {}
            for i, case in ipairs(k.cases or {}) do
                cases[i] = LJ.LJCase(Core.LitInt(tostring(case.variant.tag_value)), bid(case.dest), exprs(case.args))
            end
            return LJ.LJTermSwitch(value_id_expr(ctx, k.tag), cases, bid(k.default_dest), exprs(k.default_args))
        elseif cls == Code.CodeTermReturn then
            return LJ.LJTermReturn(exprs(k.values))
        elseif cls == Code.CodeTermTrap then
            return LJ.LJTermTrap(k.reason)
        elseif cls == Code.CodeTermUnreachable then
            return LJ.LJTermTrap(k.reason or "unreachable")
        end
        error("luajit_lower: unsupported CodeTerm " .. class_name(k), 3)
    end

    local function lower_block(ctx, block)
        note_params(ctx, block.params)
        local stmts = {}
        for i, inst in ipairs(block.insts or {}) do stmts[i] = Expr.inst_to_stmt(ctx, inst) end
        return LJ.LJBlock(bid(block.id), lower_params(ctx, block.params), stmts, lower_term(ctx, block.term))
    end

    local function graph_loop_index(graph)
        local by_loop, by_func = {}, {}
        for _, fg in ipairs(graph and graph.funcs or {}) do
            for _, loop in ipairs(fg.loops or {}) do
                by_loop[loop.id.text] = loop
                by_func[loop.id.text] = fg.func
            end
        end
        return by_loop, by_func
    end

    local function flow_loop_index(flow)
        local out = {}
        for _, loop in ipairs(flow and flow.loops or {}) do out[loop.loop.text] = loop end
        return out
    end

    local function mem_access_index(mem)
        local out = {}
        for _, access in ipairs(mem and mem.accesses or {}) do out[access.id.text] = access end
        return out
    end

    local function is_luajit_scalar_reduction(kind)
        return kind == Value.ReductionAdd
            or kind == Value.ReductionMul
            or kind == Value.ReductionAnd
            or kind == Value.ReductionOr
            or kind == Value.ReductionXor
            or kind == Value.ReductionMin
            or kind == Value.ReductionMax
    end

    local function is_float_stencil_reduction(kind)
        return kind == Value.ReductionAdd
            or kind == Value.ReductionMul
            or kind == Value.ReductionMin
            or kind == Value.ReductionMax
    end

    local function const_int_value(ctx, id)
        local def = ctx.defs and id and ctx.defs[id.text] or nil
        local k = def and def.kind
        if pvm.classof(k) ~= Code.CodeInstConst or pvm.classof(k.const) ~= Code.CodeConstLiteral or pvm.classof(k.const.literal) ~= Core.LitInt then return nil end
        return tonumber(k.const.literal.raw)
    end

    local function term_args_to_dest(term, dest)
        local k = term and term.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeTermJump and k.dest == dest then return k.args or {} end
        if cls == Code.CodeTermBranch then
            if k.then_dest == dest then return k.then_args or {} end
            if k.else_dest == dest then return k.else_args or {} end
        elseif cls == Code.CodeTermSwitch then
            for _, case in ipairs(k.cases or {}) do if case.dest == dest then return case.args or {} end end
            if k.default_dest == dest then return k.default_args or {} end
        elseif cls == Code.CodeTermVariantSwitch then
            for _, case in ipairs(k.cases or {}) do if case.dest == dest then return case.args or {} end end
            if k.default_dest == dest then return k.default_args or {} end
        end
        return nil
    end

    local function function_returns_reduction(func, graph_loop, reduction)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 1 then return false end
        local blocks = block_index(func)
        local edge = graph_loop.exits[1]
        local from = blocks[edge.from.block.text]
        local exit = blocks[edge.to.block.text]
        if from == nil or exit == nil then return false end
        local ret = exit.term and exit.term.kind or nil
        if pvm.classof(ret) ~= Code.CodeTermReturn or #(ret.values or {}) ~= 1 then return false end
        if ret.values[1] == reduction.accumulator then return true end
        for i, param in ipairs(exit.params or {}) do
            if ret.values[1] == param.value then
                local args = term_args_to_dest(from.term, exit.id)
                return args ~= nil and args[i] == reduction.accumulator
            end
        end
        return false
    end

    local function find_load_inst(func, loop_fact, value)
        local loop_blocks = {}
        for _, gb in ipairs(loop_fact and loop_fact.body_blocks or {}) do loop_blocks[gb.block.text] = true end
        for _, block in ipairs(func.blocks or {}) do
            if loop_blocks[block.id.text] then
                for _, inst in ipairs(block.insts or {}) do
                    local k = inst.kind
                    if pvm.classof(k) == Code.CodeInstLoad and k.dst == value then return block, inst, k end
                end
            end
        end
        return nil, nil, nil
    end

    local function stream_has_load_access(kernel, load_inst)
        local accesses = mem_access_index(kernel.mem)
        for _, plan in ipairs(kernel.plans or {}) do
            if pvm.classof(plan) == Kernel.KernelPlanned then
                for _, stream in ipairs(plan.body.streams or {}) do
                    for _, aid in ipairs(stream.accesses or {}) do
                        local access = accesses[aid.text]
                        if access ~= nil and access.inst == load_inst.id then return true end
                    end
                end
            end
        end
        return false
    end

    local function lower_kernel_vector_reduce(ctx, func, plan, graph_loop, loop_fact, kernel, opts)
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultReduction then return nil, "kernel result is not a reduction" end
        local reduction = result.reduction
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the kernel reduction" end
        if not is_luajit_scalar_reduction(reduction.kind) then return nil, "LuaJIT vector reduce currently supports add/mul/min/max/bitwise reductions only" end
        local ty_cls = pvm.classof(reduction.ty)
        local fallback_supported = ty_cls == Code.CodeTyInt and (reduction.ty.bits == 8 or reduction.ty.bits == 16 or reduction.ty.bits == 32)
        local stencil_requested = opts.stencil_artifact_for ~= nil
        if ty_cls ~= Code.CodeTyInt and ty_cls ~= Code.CodeTyFloat then return nil, "LuaJIT vector reduce supports scalar integer/float reductions only" end
        if ty_cls == Code.CodeTyFloat and not is_float_stencil_reduction(reduction.kind) then return nil, "LuaJIT float vector reduce supports add/mul/min/max only" end
        if not fallback_supported and not stencil_requested then return nil, "LuaJIT vector reduce scalar fallback currently supports 8/16/32-bit integer reductions only" end
        if ty_cls == Code.CodeTyInt and (reduction.kind == Value.ReductionAdd or reduction.kind == Value.ReductionMul) and (reduction.int_semantics == nil or reduction.int_semantics.overflow ~= Code.CodeIntWrap) then
            return nil, "LuaJIT vector reduce add/mul requires wrapping integer semantics"
        end
        local contrib = reduction.contribution
        if pvm.classof(contrib) ~= Value.ValueExprValue then return nil, "reduction contribution is not a single Code value" end
        local _, load_inst, load = find_load_inst(func, loop_fact, contrib.value)
        if load == nil then return nil, "reduction contribution is not a loop-local load" end
        if not stream_has_load_access(kernel, load_inst) then return nil, "load is not part of a planned kernel stream" end
        local place = load.place
        if pvm.classof(place) ~= Code.CodePlaceIndex then return nil, "load is not indexed array access" end
        local base = place.base
        if pvm.classof(base) ~= Code.CodePlaceDeref then return nil, "indexed load base is not a data pointer dereference" end
        local found_induction = false
        for _, induction in ipairs(loop_fact.inductions or {}) do
            if place.index == induction.value and induction.kind == Flow.FlowPrimaryInduction then found_induction = true end
        end
        if not found_induction then return nil, "indexed load is not driven by the primary induction" end
        if loop_fact.counted == nil then return nil, "loop is not counted" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "LuaJIT vector reduce scalar fallback requires a positive constant step" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":vreduce:" .. sanitize(loop_fact.loop.text))
        local artifact = nil
        if opts.stencil_artifact_for ~= nil then
            artifact = opts.stencil_artifact_for(func, reduction, plan, {
                array = base.addr,
                start = loop_fact.counted.start,
                stop = loop_fact.counted.stop,
                step = loop_fact.counted.step,
                step_num = step_num,
                elem_ty = load.access.ty,
                result_ty = reduction.ty,
                init = reduction.init,
            })
        end
        if artifact ~= nil then
            return LJ.LJMachine(
                id,
                LJ.LJMachineStencilCall(
                    artifact,
                    {
                        value_id_expr(ctx, base.addr),
                        value_id_expr(ctx, loop_fact.counted.start),
                        value_id_expr(ctx, loop_fact.counted.stop),
                        value_expr(ctx, reduction.init),
                    },
                    physical(ctx, reduction.ty)
                ),
                physical(ctx, reduction.ty),
                LJ.LJStateScalar,
                LJ.LJTraceHot
            ), nil
        end
        if not fallback_supported then return nil, "LuaJIT vector reduce requires a stencil artifact for this scalar type" end
        return LJ.LJMachine(
            id,
            LJ.LJMachineVectorReduceArray(
                vid(base.addr),
                value_id_expr(ctx, loop_fact.counted.start),
                value_id_expr(ctx, loop_fact.counted.stop),
                value_id_expr(ctx, loop_fact.counted.step),
                physical(ctx, load.access.ty),
                physical(ctx, reduction.ty),
                reduction.kind,
                reduction.int_semantics,
                value_expr(ctx, reduction.init),
                opts.vector_lanes or 8,
                opts.vector_unroll or 1
            ),
            physical(ctx, reduction.ty),
            LJ.LJStateScalar,
            LJ.LJTraceHot
        ), nil
    end

    local function function_returns_void_from_loop(func, graph_loop)
        if graph_loop == nil or #(graph_loop.exits or {}) ~= 1 then return false end
        local blocks = block_index(func)
        local exit = blocks[graph_loop.exits[1].to.block.text]
        local ret = exit and exit.term and exit.term.kind or nil
        return pvm.classof(ret) == Code.CodeTermReturn and #(ret.values or {}) == 0
    end

    local function stream_base_value(stream)
        local base = stream and stream.base or nil
        if pvm.classof(base) == Mem.MemBaseValue then return base.value end
        return nil
    end

    local function binding_index(body)
        local out = {}
        for _, binding in ipairs(body and body.bindings or {}) do out[binding.id.text] = binding end
        return out
    end

    local function stencil_unary_op(op)
        if op == Core.UnaryNeg then return Stencil.StencilUnaryNeg end
        if op == Core.UnaryBitNot then return Stencil.StencilUnaryBitNot end
        if op == Core.UnaryNot then return Stencil.StencilUnaryBoolNot end
        return nil
    end

    local function stencil_binary_op(op)
        if op == Core.BinAdd then return Stencil.StencilBinaryAdd end
        if op == Core.BinSub then return Stencil.StencilBinarySub end
        if op == Core.BinMul then return Stencil.StencilBinaryMul end
        if op == Core.BinBitAnd then return Stencil.StencilBinaryAnd end
        if op == Core.BinBitOr then return Stencil.StencilBinaryOr end
        if op == Core.BinBitXor then return Stencil.StencilBinaryXor end
        return nil
    end

    local function same_code_type(a, b)
        if a == b then return true end
        local ac, bc = pvm.classof(a), pvm.classof(b)
        if ac ~= bc then return false end
        if ac == Code.CodeTyInt then return a.bits == b.bits and a.signedness == b.signedness end
        if ac == Code.CodeTyFloat then return a.bits == b.bits end
        return false
    end

    local function primary_induction(loop_fact)
        for _, induction in ipairs(loop_fact and loop_fact.inductions or {}) do
            if induction.kind == Flow.FlowPrimaryInduction then return induction.value end
        end
        return nil
    end

    local function expr_is_value(expr, id)
        return id ~= nil and pvm.classof(expr) == Value.ValueExprValue and expr.value == id
    end

    local function expr_is_primary(expr, loop_fact)
        return expr_is_value(expr, primary_induction(loop_fact))
    end

    local function is_zero_const(expr)
        return pvm.classof(expr) == Value.ValueExprConst
            and pvm.classof(expr.const) == Code.CodeConstLiteral
            and pvm.classof(expr.const.literal) == Core.LitInt
            and tonumber(expr.const.literal.raw) == 0
    end

    local function predicate_from_cmp_const(op, cexpr, const_on_left)
        if pvm.classof(cexpr) ~= Value.ValueExprConst then return nil end
        if const_on_left then
            if op == Core.CmpLt then op = Core.CmpGt
            elseif op == Core.CmpLe then op = Core.CmpGe
            elseif op == Core.CmpGt then op = Core.CmpLt
            elseif op == Core.CmpGe then op = Core.CmpLe end
        end
        if op == Core.CmpEq then return Stencil.StencilPredEqConst(cexpr) end
        if op == Core.CmpNe then return Stencil.StencilPredNeConst(cexpr) end
        if op == Core.CmpLt then return Stencil.StencilPredLtConst(cexpr) end
        if op == Core.CmpLe then return Stencil.StencilPredLeConst(cexpr) end
        if op == Core.CmpGt then return Stencil.StencilPredGtConst(cexpr) end
        if op == Core.CmpGe then return Stencil.StencilPredGeConst(cexpr) end
        return nil
    end

    local function classify_store_expr(expr, bindings, seen)
        if expr == nil then return nil, "missing store value" end
        seen = seen or {}
        local cls = pvm.classof(expr)
        if cls == Kernel.KernelExprKernelValue then
            if seen[expr.value.text] then return nil, "cyclic kernel binding" end
            seen[expr.value.text] = true
            local binding = bindings[expr.value.text]
            if binding == nil then return nil, "missing kernel binding " .. expr.value.text end
            return classify_store_expr(binding.expr, bindings, seen)
        elseif cls == Kernel.KernelExprLoad then
            return { kind = "load", stream = expr.stream, index = expr.index }, nil
        elseif cls == Kernel.KernelExprAlgebra then
            local v = expr.expr
            local vcls = pvm.classof(v)
            if vcls == Value.ValueExprConst then
                return { kind = "fill", value = v }, nil
            elseif vcls == Value.ValueExprValue then
                local kid = Kernel.KernelValueId("kval:" .. v.value.text)
                local binding = bindings[kid.text]
                if binding ~= nil then
                    if seen[kid.text] then return nil, "cyclic kernel binding" end
                    seen[kid.text] = true
                    return classify_store_expr(binding.expr, bindings, seen)
                end
                return { kind = "fill", value = v }, nil
            elseif vcls == Value.ValueExprUnary then
                local inner, reason = classify_store_expr(Kernel.KernelExprAlgebra(v.value), bindings, seen)
                if inner == nil then return nil, reason end
                if inner.kind ~= "load" then return nil, "unary map operand is not a load" end
                local op = stencil_unary_op(v.op)
                if op == nil then return nil, "unsupported unary map op" end
                return { kind = "map", op = op, stream = inner.stream, index = inner.index, result_ty = v.ty }, nil
            elseif vcls == Value.ValueExprCast then
                local inner, reason = classify_store_expr(Kernel.KernelExprAlgebra(v.value), bindings, seen)
                if inner == nil then return nil, reason end
                if inner.kind ~= "load" then return nil, "cast map operand is not a load" end
                return { kind = "cast", op = v.op, stream = inner.stream, index = inner.index, src_ty = v.from, result_ty = v.to }, nil
            elseif vcls == Value.ValueExprAdd or vcls == Value.ValueExprSub or vcls == Value.ValueExprMul then
                local lhs, lhs_reason = classify_store_expr(Kernel.KernelExprAlgebra(v.a), bindings, seen)
                if lhs == nil then return nil, lhs_reason end
                local rhs, rhs_reason = classify_store_expr(Kernel.KernelExprAlgebra(v.b), bindings, seen)
                if rhs == nil then return nil, rhs_reason end
                if lhs.kind ~= "load" or rhs.kind ~= "load" then return nil, "zip map operands must be loads" end
                local bop = vcls == Value.ValueExprAdd and Core.BinAdd or vcls == Value.ValueExprSub and Core.BinSub or Core.BinMul
                local op = stencil_binary_op(bop)
                if op == nil then return nil, "unsupported zip map op" end
                return { kind = "zip_map", op = op, lhs = lhs.stream, rhs = rhs.stream, lhs_index = lhs.index, rhs_index = rhs.index, result_ty = v.ty }, nil
            elseif vcls == Value.ValueExprCmp then
                local lhs, lhs_reason = classify_store_expr(Kernel.KernelExprAlgebra(v.a), bindings, seen)
                if lhs == nil then return nil, lhs_reason end
                local rhs, rhs_reason = classify_store_expr(Kernel.KernelExprAlgebra(v.b), bindings, seen)
                if rhs == nil then return nil, rhs_reason end
                if lhs.kind == "load" and rhs.kind == "fill" then
                    local pred = predicate_from_cmp_const(v.op, rhs.value, false)
                    if pred == nil then return nil, "compare map predicate is not a supported constant predicate" end
                    return { kind = "compare", pred = pred, stream = lhs.stream, index = lhs.index, result_ty = Code.CodeTyBool8 }, nil
                elseif lhs.kind == "fill" and rhs.kind == "load" then
                    local pred = predicate_from_cmp_const(v.op, lhs.value, true)
                    if pred == nil then return nil, "compare map predicate is not a supported constant predicate" end
                    return { kind = "compare", pred = pred, stream = rhs.stream, index = rhs.index, result_ty = Code.CodeTyBool8 }, nil
                elseif lhs.kind == "load" and rhs.kind == "load" then
                    return { kind = "zip_compare", cmp = v.op, lhs = lhs.stream, rhs = rhs.stream, lhs_index = lhs.index, rhs_index = rhs.index, result_ty = Code.CodeTyBool8 }, nil
                end
                return nil, "compare operands are not stencil loads/constants"
            end
        end
        return nil, "unsupported store stencil expression"
    end

    local function single_store_effect(body)
        local store = nil
        for _, effect in ipairs(body and body.effects or {}) do
            local cls = pvm.classof(effect)
            if cls == Kernel.KernelEffectStore then
                if store ~= nil then return nil, "multiple stores in kernel" end
                store = effect
            elseif cls ~= Kernel.KernelEffectFold then
                return nil, "non-store effect in kernel"
            end
        end
        if store == nil then return nil, "kernel has no store effect" end
        return store, nil
    end

    local function index_stream_for(expr, bindings)
        local classified = classify_store_expr(Kernel.KernelExprAlgebra(expr), bindings)
        if classified ~= nil and classified.kind == "load" then return classified end
        return nil
    end

    local function lower_kernel_stencil_store(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_store_artifact_for == nil then return nil, "no store stencil artifact provider" end
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        if not function_returns_void_from_loop(func, graph_loop) then return nil, "store stencil requires loop exit to return void" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "store stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "store stencil requires a positive constant step" end
        local store, store_reason = single_store_effect(plan.body)
        if store == nil then return nil, store_reason end
        local dst_base = stream_base_value(store.dst)
        if dst_base == nil then return nil, "store destination stream has no value base" end
        local bindings = binding_index(plan.body)
        local classified, reason = classify_store_expr(store.value, bindings)
        if classified == nil then return nil, reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local dst_expr = value_id_expr(ctx, dst_base)
        local store_index_is_primary = expr_is_primary(store.index, loop_fact)
        local store_index_stream = store_index_is_primary and nil or index_stream_for(store.index, bindings)
        local info = {
            step_num = step_num,
            elem_ty = store.dst.elem_ty,
            result_ty = store.dst.elem_ty,
            dst = dst_base,
            start = loop_fact.counted.start,
            stop = loop_fact.counted.stop,
        }
        local artifact, args
        if classified.kind == "fill" then
            info.value = classified.value
            if not store_index_is_primary then return nil, "fill store index is not primary induction" end
            artifact = opts.stencil_store_artifact_for(func, Stencil.StencilFillArray, nil, plan, info)
            args = { dst_expr, start_expr, stop_expr, value_expr(ctx, classified.value) }
        elseif classified.kind == "load" then
            local src = stream_base_value(classified.stream)
            if src == nil then return nil, "copy source stream has no value base" end
            if store_index_is_primary and expr_is_primary(classified.index, loop_fact) then
                info.src = src
                info.elem_ty = classified.stream.elem_ty
                artifact = opts.stencil_store_artifact_for(func, Stencil.StencilCopyArray, nil, plan, info)
                args = { dst_expr, value_id_expr(ctx, src), start_expr, stop_expr }
            elseif store_index_is_primary then
                local idx = index_stream_for(classified.index, bindings)
                if idx == nil or not expr_is_primary(idx.index, loop_fact) then return nil, "gather index is not a primary-indexed stream load" end
                local idx_base = stream_base_value(idx.stream)
                if idx_base == nil then return nil, "gather index stream has no value base" end
                info.src = src
                info.index = idx_base
                info.elem_ty = classified.stream.elem_ty
                info.index_ty = idx.stream.elem_ty
                artifact = opts.stencil_store_artifact_for(func, Stencil.StencilGatherArray, nil, plan, info)
                args = { dst_expr, value_id_expr(ctx, src), value_id_expr(ctx, idx_base), start_expr, stop_expr }
            elseif store_index_stream ~= nil and expr_is_primary(store_index_stream.index, loop_fact) and expr_is_primary(classified.index, loop_fact) then
                local idx_base = stream_base_value(store_index_stream.stream)
                if idx_base == nil then return nil, "scatter index stream has no value base" end
                info.src = src
                info.index = idx_base
                info.elem_ty = classified.stream.elem_ty
                info.index_ty = store_index_stream.stream.elem_ty
                info.conflicts = Stencil.StencilScatterUniqueIndices
                artifact = opts.stencil_store_artifact_for(func, Stencil.StencilScatterArray, nil, plan, info)
                args = { dst_expr, value_id_expr(ctx, src), value_id_expr(ctx, idx_base), start_expr, stop_expr }
            else
                return nil, "load store indexes do not match copy/gather/scatter stencil shape"
            end
        elseif classified.kind == "map" then
            local src = stream_base_value(classified.stream)
            if src == nil then return nil, "map source stream has no value base" end
            if not store_index_is_primary or not expr_is_primary(classified.index, loop_fact) then return nil, "map indexes are not primary induction" end
            info.src = src
            info.elem_ty = classified.stream.elem_ty
            info.result_ty = classified.result_ty
            if src == dst_base and same_code_type(info.elem_ty, store.dst.elem_ty) then
                artifact = opts.stencil_store_artifact_for(func, Stencil.StencilInPlaceMapArray, classified.op, plan, info)
                args = { dst_expr, start_expr, stop_expr }
            else
                artifact = opts.stencil_store_artifact_for(func, Stencil.StencilMapArray, classified.op, plan, info)
                args = { dst_expr, value_id_expr(ctx, src), start_expr, stop_expr }
            end
        elseif classified.kind == "cast" then
            local src = stream_base_value(classified.stream)
            if src == nil then return nil, "cast source stream has no value base" end
            if not store_index_is_primary or not expr_is_primary(classified.index, loop_fact) then return nil, "cast indexes are not primary induction" end
            info.src = src
            info.src_ty = classified.src_ty
            info.dst_ty = classified.result_ty
            artifact = opts.stencil_store_artifact_for(func, Stencil.StencilCastArray, classified.op, plan, info)
            args = { dst_expr, value_id_expr(ctx, src), start_expr, stop_expr }
        elseif classified.kind == "compare" then
            local src = stream_base_value(classified.stream)
            if src == nil then return nil, "compare source stream has no value base" end
            if not store_index_is_primary or not expr_is_primary(classified.index, loop_fact) then return nil, "compare indexes are not primary induction" end
            info.src = src
            info.elem_ty = classified.stream.elem_ty
            info.result_ty = store.dst.elem_ty
            info.pred = classified.pred
            artifact = opts.stencil_store_artifact_for(func, Stencil.StencilCompareArray, classified.pred, plan, info)
            args = { dst_expr, value_id_expr(ctx, src), start_expr, stop_expr }
        elseif classified.kind == "zip_map" then
            local lhs, rhs = stream_base_value(classified.lhs), stream_base_value(classified.rhs)
            if lhs == nil or rhs == nil then return nil, "zip map source stream has no value base" end
            if not store_index_is_primary or not expr_is_primary(classified.lhs_index, loop_fact) or not expr_is_primary(classified.rhs_index, loop_fact) then return nil, "zip map indexes are not primary induction" end
            info.lhs = lhs
            info.rhs = rhs
            info.lhs_ty = classified.lhs.elem_ty
            info.rhs_ty = classified.rhs.elem_ty
            info.result_ty = classified.result_ty
            artifact = opts.stencil_store_artifact_for(func, Stencil.StencilZipMapArray, classified.op, plan, info)
            args = { dst_expr, value_id_expr(ctx, lhs), value_id_expr(ctx, rhs), start_expr, stop_expr }
        elseif classified.kind == "zip_compare" then
            local lhs, rhs = stream_base_value(classified.lhs), stream_base_value(classified.rhs)
            if lhs == nil or rhs == nil then return nil, "zip compare source stream has no value base" end
            if not store_index_is_primary or not expr_is_primary(classified.lhs_index, loop_fact) or not expr_is_primary(classified.rhs_index, loop_fact) then return nil, "zip compare indexes are not primary induction" end
            info.lhs = lhs
            info.rhs = rhs
            info.lhs_ty = classified.lhs.elem_ty
            info.rhs_ty = classified.rhs.elem_ty
            info.result_ty = store.dst.elem_ty
            artifact = opts.stencil_store_artifact_for(func, Stencil.StencilZipCompareArray, classified.cmp, plan, info)
            args = { dst_expr, value_id_expr(ctx, lhs), value_id_expr(ctx, rhs), start_expr, stop_expr }
        end
        if artifact == nil then return nil, "store stencil artifact provider did not select an artifact" end
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_store:" .. sanitize(loop_fact.loop.text))
        return LJ.LJMachine(id, LJ.LJMachineStencilEffect(artifact, args), nil, LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function select_reduction_artifact(opts, func, vocab, op, reduction, plan, info)
        if opts.stencil_reduce_artifact_for ~= nil then return opts.stencil_reduce_artifact_for(func, vocab, op, reduction, plan, info) end
        if vocab == Stencil.StencilReduceArray and opts.stencil_artifact_for ~= nil then return opts.stencil_artifact_for(func, reduction, plan, info) end
        return nil
    end

    local function lower_kernel_stencil_reduce(ctx, func, plan, graph_loop, loop_fact, opts)
        if opts.stencil_reduce_artifact_for == nil and opts.stencil_artifact_for == nil then return nil, "no reduction stencil artifact provider" end
        if pvm.classof(plan) ~= Kernel.KernelPlanned then return nil, "kernel is not planned" end
        local result = plan.body.result
        if pvm.classof(result) ~= Kernel.KernelResultReduction then return nil, "kernel result is not a reduction" end
        local reduction = result.reduction
        if not function_returns_reduction(func, graph_loop, reduction) then return nil, "function return is not the kernel reduction" end
        if loop_fact == nil or loop_fact.counted == nil then return nil, "reduction stencil requires counted loop" end
        local step_num = const_int_value(ctx, loop_fact.counted.step)
        if step_num == nil or step_num <= 0 then return nil, "reduction stencil requires a positive constant step" end
        local classified, reason = classify_store_expr(Kernel.KernelExprAlgebra(reduction.contribution), binding_index(plan.body))
        if classified == nil then return nil, reason end
        local start_expr, stop_expr = value_id_expr(ctx, loop_fact.counted.start), value_id_expr(ctx, loop_fact.counted.stop)
        local init_expr = value_expr(ctx, reduction.init)
        local id = LJ.LJMachineId("machine:" .. sanitize(func.name) .. ":stencil_reduce:" .. sanitize(loop_fact.loop.text))
        local info = {
            step_num = step_num,
            result_ty = reduction.ty,
            init = reduction.init,
        }
        local artifact, args
        if classified.kind == "load" then
            if not expr_is_primary(classified.index, loop_fact) then return nil, "reduce load index is not primary induction" end
            local src = stream_base_value(classified.stream)
            if src == nil then return nil, "reduce source stream has no value base" end
            info.array = src
            info.elem_ty = classified.stream.elem_ty
            artifact = select_reduction_artifact(opts, func, Stencil.StencilReduceArray, nil, reduction, plan, info)
            args = { value_id_expr(ctx, src), start_expr, stop_expr, init_expr }
        elseif classified.kind == "map" then
            if not expr_is_primary(classified.index, loop_fact) then return nil, "map-reduce source index is not primary induction" end
            local src = stream_base_value(classified.stream)
            if src == nil then return nil, "map-reduce source stream has no value base" end
            info.array = src
            info.elem_ty = classified.stream.elem_ty
            info.mapped_ty = classified.result_ty
            artifact = select_reduction_artifact(opts, func, Stencil.StencilMapReduceArray, classified.op, reduction, plan, info)
            args = { value_id_expr(ctx, src), start_expr, stop_expr, init_expr }
        elseif classified.kind == "zip_map" then
            if not expr_is_primary(classified.lhs_index, loop_fact) or not expr_is_primary(classified.rhs_index, loop_fact) then return nil, "zip-reduce source indexes are not primary induction" end
            local lhs, rhs = stream_base_value(classified.lhs), stream_base_value(classified.rhs)
            if lhs == nil or rhs == nil then return nil, "zip-reduce source stream has no value base" end
            info.lhs = lhs
            info.rhs = rhs
            info.lhs_ty = classified.lhs.elem_ty
            info.rhs_ty = classified.rhs.elem_ty
            info.mapped_ty = classified.result_ty
            artifact = select_reduction_artifact(opts, func, Stencil.StencilZipReduceArray, classified.op, reduction, plan, info)
            args = { value_id_expr(ctx, lhs), value_id_expr(ctx, rhs), start_expr, stop_expr, init_expr }
        elseif classified.kind == "compare" then
            if reduction.kind ~= Value.ReductionAdd or not is_zero_const(reduction.init) then return nil, "count stencil requires add reduction with zero init" end
            local i32 = Code.CodeTyInt(32, Code.CodeSigned)
            if not same_code_type(reduction.ty, i32) then return nil, "count stencil currently returns i32" end
            if not expr_is_primary(classified.index, loop_fact) then return nil, "count source index is not primary induction" end
            local src = stream_base_value(classified.stream)
            if src == nil then return nil, "count source stream has no value base" end
            info.array = src
            info.elem_ty = classified.stream.elem_ty
            info.pred = classified.pred
            artifact = select_reduction_artifact(opts, func, Stencil.StencilCountArray, classified.pred, reduction, plan, info)
            args = { value_id_expr(ctx, src), start_expr, stop_expr }
        else
            return nil, "unsupported reduction stencil contribution"
        end
        if artifact == nil then return nil, "reduction stencil artifact provider did not select an artifact" end
        return LJ.LJMachine(id, LJ.LJMachineStencilCall(artifact, args, physical(ctx, reduction.ty)), physical(ctx, reduction.ty), LJ.LJStateScalar, LJ.LJTraceHot), nil
    end

    local function lower_blocks_func(ctx, func)
        local blocks = {}
        for i, block in ipairs(func.blocks or {}) do blocks[i] = lower_block(ctx, block) end
        return {}, LJ.LJBodyBlocks(bid(func.entry), blocks)
    end

    local function lower_func(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts)
        local ctx = {
            code_sigs = module_ctx.code_sigs,
            value_types = {},
            defs = value_defs(func),
        }
        note_params(ctx, func.params)
        for _, block in ipairs(func.blocks or {}) do note_params(ctx, block.params) end
        local params = lower_params(ctx, func.params)
        local machines, body = nil, nil
        for _, plan in ipairs(kernel.plans or {}) do
            local subject = plan.subject
            if pvm.classof(subject) == Kernel.KernelSubjectLoop and loop_func[subject.loop.text] == func.id then
                local machine, reason = lower_kernel_stencil_reduce(ctx, func, plan, graph_loops[subject.loop.text], flow_loops[subject.loop.text], opts)
                if machine == nil then
                    machine, reason = lower_kernel_vector_reduce(ctx, func, plan, graph_loops[subject.loop.text], flow_loops[subject.loop.text], kernel, opts)
                end
                if machine == nil and opts.stencil_store_artifact_for ~= nil then
                    machine, reason = lower_kernel_stencil_store(ctx, func, plan, graph_loops[subject.loop.text], flow_loops[subject.loop.text], opts)
                end
                if machine ~= nil then
                    machines = { machine }
                    body = LJ.LJBodyMachine(machine.id, LJ.LJTerminalFirst(nil))
                    break
                elseif opts.collect_rejects ~= nil then
                    opts.collect_rejects[#opts.collect_rejects + 1] = { func = func.id, loop = subject.loop, reason = reason }
                end
            end
        end
        if body == nil then machines, body = lower_blocks_func(ctx, func) end
        return LJ.LJFunc(fid(func.id), func.id, func.name, sigid(func.sig), params, {}, machines, body, LJ.LJTraceHot)
    end

    local function build_kernel(module, opts)
        local graph = opts.graph or CodeGraph.graph(module)
        local flow = opts.flow or CodeFlowFacts.facts(module, graph)
        local value = opts.value or CodeValueFacts.facts(module, graph, flow)
        local mem = opts.mem or CodeMemFacts.semantic_facts(module, graph, flow, value, opts.contracts)
        local effect = opts.effect or CodeEffectFacts.facts(module, graph, mem, opts.contracts)
        local kernel = opts.kernel or CodeKernelPlan.plan(module, graph, flow, value, mem, effect)
        return graph, flow, value, mem, effect, kernel
    end

    local function lower_module(module, opts)
        opts = opts or {}
        local graph, flow, value, mem, effect, kernel = build_kernel(module, opts)
        local graph_loops, loop_func = graph_loop_index(graph)
        local flow_loops = flow_loop_index(flow)
        local module_ctx = { code_sigs = code_sigs(module) }
        local funcs = {}
        for i, func in ipairs(module.funcs or {}) do funcs[i] = lower_func(module_ctx, func, kernel, graph_loops, flow_loops, loop_func, opts) end
        return LJ.LJModule(module.id, funcs, {}, {}, {}), {
            graph = graph,
            flow = flow,
            value = value,
            mem = mem,
            effect = effect,
            kernel = kernel,
        }
    end

    api.lower_module = lower_module
    api.module = lower_module
    api.build_kernel = build_kernel

    T._moonlift_api_cache.luajit_lower = api
    return api
end

return bind_context
