local pvm = require("moonlift.pvm")

local M = {}

local function class_name(x)
    local cls = pvm.classof(x) or x
    return tostring(cls):match("Class%((.-)%)") or tostring(cls)
end

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_to_back ~= nil then return T._moonlift_api_cache.code_to_back end

    local Core = T.MoonCore
    local Code = T.MoonCode
    local Back = T.MoonBack
    local CodeValidate = require("moonlift.code_validate").Define(T)

    local api = {}

    local function unsupported(x)
        error("code_to_back: unsupported " .. class_name(x), 3)
    end

    local function bid(id) return Back.BackValId(id.text) end
    local function block_id(id) return Back.BackBlockId(id.text) end
    local function func_id(id)
        local text = tostring(id.text)
        return Back.BackFuncId(text:gsub("^fn:", "", 1))
    end
    local function extern_id(id) return Back.BackExternId(id.text) end
    local function data_id(id) return Back.BackDataId(id.text) end
    local function sig_id(id) return Back.BackSigId(id.text) end

    local function scalar(ty)
        if ty == Code.CodeTyVoid then return Back.BackVoid end
        if ty == Code.CodeTyBool8 then return Back.BackBool end
        if ty == Code.CodeTyIndex then return Back.BackIndex end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt then
            if ty.bits == 8 then return ty.signedness == Code.CodeSigned and Back.BackI8 or Back.BackU8 end
            if ty.bits == 16 then return ty.signedness == Code.CodeSigned and Back.BackI16 or Back.BackU16 end
            if ty.bits == 32 then return ty.signedness == Code.CodeSigned and Back.BackI32 or Back.BackU32 end
            if ty.bits == 64 then return ty.signedness == Code.CodeSigned and Back.BackI64 or Back.BackU64 end
        elseif cls == Code.CodeTyFloat then
            if ty.bits == 32 then return Back.BackF32 end
            if ty.bits == 64 then return Back.BackF64 end
        elseif cls == Code.CodeTyDataPtr or cls == Code.CodeTyCodePtr or cls == Code.CodeTyImportedCFuncPtr then
            return Back.BackPtr
        end
        return nil
    end

    local function shape(ty)
        local s = scalar(ty)
        if s == nil then unsupported(ty) end
        return Back.BackShapeScalar(s)
    end

    local function literal(lit)
        local cls = pvm.classof(lit)
        if cls == Core.LitInt then return Back.BackLitInt(lit.raw) end
        if cls == Core.LitFloat then return Back.BackLitFloat(lit.raw) end
        if cls == Core.LitBool then return Back.BackLitBool(lit.value) end
        if cls == Core.LitNil then return Back.BackLitNull end
        unsupported(lit)
    end

    local function const_literal(k)
        local cls = pvm.classof(k)
        if cls == Code.CodeConstLiteral then return literal(k.literal) end
        if cls == Code.CodeConstNull then return Back.BackLitNull end
        if cls == Code.CodeConstUndef then return Back.BackLitInt("0") end
        unsupported(k)
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

    local function shift_op(op)
        if op == Core.BinShl then return Back.BackShiftLeft end
        if op == Core.BinLShr then return Back.BackShiftLogicalRight end
        if op == Core.BinAShr then return Back.BackShiftArithmeticRight end
        return nil
    end

    local function float_op(op)
        if op == Core.BinAdd then return Back.BackFloatAdd end
        if op == Core.BinSub then return Back.BackFloatSub end
        if op == Core.BinMul then return Back.BackFloatMul end
        if op == Core.BinDiv then return Back.BackFloatDiv end
        return nil
    end

    local function unary_op(op)
        if op == Core.UnaryNeg then return Back.BackUnaryIneg end
        if op == Core.UnaryFNeg then return Back.BackUnaryFneg end
        if op == Core.UnaryBitNot then return Back.BackUnaryBnot end
        if op == Core.UnaryNot then return Back.BackUnaryBoolNot end
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
        unsupported(op)
    end

    local function cast_op(op)
        if op == Core.CastBitcast or op == Core.MachineCastBitcast or op == Core.MachineCastIdentity then return Back.BackBitcast end
        if op == Core.CastTrunc or op == Core.MachineCastIreduce then return Back.BackIreduce end
        if op == Core.CastSExt or op == Core.MachineCastSextend then return Back.BackSextend end
        if op == Core.CastZExt or op == Core.MachineCastUextend then return Back.BackUextend end
        if op == Core.CastFPExt or op == Core.MachineCastFpromote then return Back.BackFpromote end
        if op == Core.CastFPTrunc or op == Core.MachineCastFdemote then return Back.BackFdemote end
        if op == Core.CastSIToFP or op == Core.MachineCastSToF then return Back.BackSToF end
        if op == Core.CastUIToFP or op == Core.MachineCastUToF then return Back.BackUToF end
        if op == Core.CastFPToSI or op == Core.MachineCastFToS then return Back.BackFToS end
        if op == Core.CastFPToUI or op == Core.MachineCastFToU then return Back.BackFToU end
        unsupported(op)
    end

    local function int_semantics(k)
        return Back.BackIntSemantics(Back.BackIntWrap, Back.BackIntMayLose)
    end

    local function float_semantics(k)
        return Back.BackFloatStrict
    end

    local function zero(ctx)
        ctx.next_tmp = (ctx.next_tmp or 0) + 1
        local v = Back.BackValId("code_to_back.zero." .. tostring(ctx.next_tmp))
        ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(v, Back.BackIndex, Back.BackLitInt("0"))
        return v
    end

    local function note_value(ctx, id, ty)
        if id ~= nil and ty ~= nil then ctx.value_types[id.text] = ty end
    end

    local function index_value(ctx, id)
        local ty = ctx.value_types[id.text]
        if ty == Code.CodeTyIndex then return bid(id) end
        local cls = pvm.classof(ty)
        if cls == Code.CodeTyInt and ty.bits < 64 then
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local v = Back.BackValId("code_to_back.index." .. tostring(ctx.next_tmp))
            local op = ty.signedness == Code.CodeSigned and Back.BackSextend or Back.BackUextend
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCast(v, op, Back.BackIndex, bid(id))
            return v
        elseif ty == Code.CodeTyBool8 then
            ctx.next_tmp = (ctx.next_tmp or 0) + 1
            local v = Back.BackValId("code_to_back.index." .. tostring(ctx.next_tmp))
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCast(v, Back.BackUextend, Back.BackIndex, bid(id))
            return v
        end
        return bid(id)
    end

    local function value_as(ctx, id, ty)
        if ty == Code.CodeTyIndex then return index_value(ctx, id) end
        return bid(id)
    end

    local function access_mode(mode)
        if mode == Code.CodeMemoryWrite then return Back.BackAccessWrite end
        if mode == Code.CodeMemoryReadWrite then return Back.BackAccessReadWrite end
        return Back.BackAccessRead
    end

    local function memory_info(ctx, access, tag)
        local s = scalar(access.ty) or Back.BackPtr
        local bytes = 8
        if s == Back.BackI8 or s == Back.BackU8 or s == Back.BackBool then bytes = 1
        elseif s == Back.BackI16 or s == Back.BackU16 then bytes = 2
        elseif s == Back.BackI32 or s == Back.BackU32 or s == Back.BackF32 then bytes = 4 end
        return Back.BackMemoryInfo(
            Back.BackAccessId("code:" .. tag),
            Back.BackAlignKnown(access.align or 1),
            Back.BackDerefBytes(bytes, "CodeMemoryAccess"),
            Back.BackMayTrap,
            Back.BackMayNotMove,
            access_mode(access.mode)
        )
    end

    local function addr_from_place(ctx, place)
        local cls = pvm.classof(place)
        if cls == Code.CodePlaceDeref then
            return Back.BackAddress(Back.BackAddrValue(bid(place.addr)), zero(ctx), Back.BackProvUnknown, Back.BackPtrBoundsUnknown)
        elseif cls == Code.CodePlaceGlobal then
            return Back.BackAddress(Back.BackAddrData(data_id(place.global)), zero(ctx), Back.BackProvData(data_id(place.global)), Back.BackPtrInBounds("global"))
        elseif cls == Code.CodePlaceData then
            return Back.BackAddress(Back.BackAddrData(data_id(place.data)), zero(ctx), Back.BackProvData(data_id(place.data)), Back.BackPtrInBounds("data"))
        elseif cls == Code.CodePlaceIndex then
            local base = addr_from_place(ctx, place.base)
            local ptr = Back.BackValId("code_to_back.addr." .. place.index.text)
            local index = index_value(ctx, place.index)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(ptr, base.base, index, place.elem_size, 0, Back.BackProvDerived("index"), Back.BackPtrBoundsUnknown)
            return Back.BackAddress(Back.BackAddrValue(ptr), zero(ctx), Back.BackProvDerived("index"), Back.BackPtrBoundsUnknown)
        end
        unsupported(place)
    end

    local function data_init(ctx, init, data)
        local cls = pvm.classof(init)
        if cls == Code.CodeDataZero then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDataInitZero(data, init.offset, init.size)
        elseif cls == Code.CodeDataScalar then
            local s = scalar(init.ty); if s == nil then unsupported(init.ty) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDataInit(data, init.offset, s, literal(init.literal))
        elseif cls == Code.CodeDataBytes then
            for i = 1, #init.bytes do
                ctx.cmds[#ctx.cmds + 1] = Back.CmdDataInit(data, init.offset + i - 1, Back.BackU8, Back.BackLitInt(tostring(init.bytes:byte(i))))
            end
        else
            unsupported(init)
        end
    end

    local function inst_dst_type(ctx, k)
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then return k.dst, k.const.ty end
        if cls == Code.CodeInstAlias then return k.dst, k.ty end
        if cls == Code.CodeInstUnary then return k.dst, k.ty end
        if cls == Code.CodeInstBinary then return k.dst, k.ty end
        if cls == Code.CodeInstFloatBinary then return k.dst, k.ty end
        if cls == Code.CodeInstCompare then return k.dst, Code.CodeTyBool8 end
        if cls == Code.CodeInstCast then return k.dst, k.to end
        if cls == Code.CodeInstSelect then return k.dst, k.ty end
        if cls == Code.CodeInstAddrOf then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstGlobalRef then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstPtrOffset then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstLoad then return k.dst, k.access.ty end
        if cls == Code.CodeInstViewData then return k.dst, k.ptr_ty end
        if cls == Code.CodeInstViewLen or cls == Code.CodeInstViewStride then return k.dst, Code.CodeTyIndex end
        if cls == Code.CodeInstCall then
            local sig = k.sig and ctx.sigs[k.sig.text] or nil
            if sig and sig.results[1] then return k.dst, sig.results[1] end
        end
        return nil, nil
    end

    local function view_parts(ctx, id)
        local v = ctx.view_values and ctx.view_values[id.text] or nil
        if v == nil then unsupported(id) end
        return v
    end

    local function is_view_ty(ty)
        return pvm.classof(ty) == Code.CodeTyView
    end

    local function inst(ctx, i)
        local k = i.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeInstConst then
            local s = scalar(k.const.ty); if s == nil then unsupported(k.const.ty) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdConst(bid(k.dst), s, const_literal(k.const))
        elseif cls == Code.CodeInstAlias then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), bid(k.src))
        elseif cls == Code.CodeInstUnary then
            local op = unary_op(k.op); if op == nil then unsupported(k.op) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdUnary(bid(k.dst), op, shape(k.ty), bid(k.value))
        elseif cls == Code.CodeInstBinary then
            local s = scalar(k.ty); if s == nil then unsupported(k.ty) end
            local iop, bop, sop = int_op(k.op), bit_op(k.op), shift_op(k.op)
            local lhs, rhs = value_as(ctx, k.lhs, k.ty), value_as(ctx, k.rhs, k.ty)
            if iop then ctx.cmds[#ctx.cmds + 1] = Back.CmdIntBinary(bid(k.dst), iop, s, int_semantics(k), lhs, rhs)
            elseif bop then ctx.cmds[#ctx.cmds + 1] = Back.CmdBitBinary(bid(k.dst), bop, s, lhs, rhs)
            elseif sop then ctx.cmds[#ctx.cmds + 1] = Back.CmdShift(bid(k.dst), sop, s, lhs, rhs)
            else unsupported(k.op) end
        elseif cls == Code.CodeInstFloatBinary then
            local s = scalar(k.ty); local op = float_op(k.op); if not s or not op then unsupported(k) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdFloatBinary(bid(k.dst), op, s, float_semantics(k), bid(k.lhs), bid(k.rhs))
        elseif cls == Code.CodeInstCompare then
            local lhs, rhs = value_as(ctx, k.lhs, k.operand_ty), value_as(ctx, k.rhs, k.operand_ty)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCompare(bid(k.dst), cmp_op(k.op, k.operand_ty), shape(k.operand_ty), lhs, rhs)
        elseif cls == Code.CodeInstCast then
            local s = scalar(k.to); if s == nil then unsupported(k.to) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCast(bid(k.dst), cast_op(k.op), s, bid(k.value))
        elseif cls == Code.CodeInstSelect then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSelect(bid(k.dst), shape(k.ty), bid(k.cond), bid(k.then_value), bid(k.else_value))
        elseif cls == Code.CodeInstAddrOf then
            local pcls = pvm.classof(k.place)
            if pcls == Code.CodePlaceGlobal then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.place.global))
            elseif pcls == Code.CodePlaceData then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.place.data))
            else unsupported(k.place) end
        elseif cls == Code.CodeInstGlobalRef then
            local rcls = pvm.classof(k.ref)
            if rcls == Code.CodeGlobalRefFunc then ctx.cmds[#ctx.cmds + 1] = Back.CmdFuncAddr(bid(k.dst), func_id(k.ref.func))
            elseif rcls == Code.CodeGlobalRefExtern then ctx.cmds[#ctx.cmds + 1] = Back.CmdExternAddr(bid(k.dst), extern_id(k.ref["extern"]))
            elseif rcls == Code.CodeGlobalRefData then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.ref.data))
            elseif rcls == Code.CodeGlobalRefGlobal then ctx.cmds[#ctx.cmds + 1] = Back.CmdDataAddr(bid(k.dst), data_id(k.ref.global))
            else unsupported(k.ref) end
        elseif cls == Code.CodeInstPtrOffset then
            local index = index_value(ctx, k.index)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdPtrOffset(bid(k.dst), Back.BackAddrValue(bid(k.base)), index, k.elem_size, k.const_offset, Back.BackProvDerived("CodePtrOffset"), Back.BackPtrBoundsUnknown)
        elseif cls == Code.CodeInstView then
            ctx.view_values[k.dst.text] = { data = k.data, len = k.len, stride = k.stride }
        elseif cls == Code.CodeInstViewData then
            local v = view_parts(ctx, k.view)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), bid(v.data))
        elseif cls == Code.CodeInstViewLen then
            local v = view_parts(ctx, k.view)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), bid(v.len))
        elseif cls == Code.CodeInstViewStride then
            local v = view_parts(ctx, k.view)
            ctx.cmds[#ctx.cmds + 1] = Back.CmdAlias(bid(k.dst), bid(v.stride))
        elseif cls == Code.CodeInstLoad then
            if is_view_ty(k.access.ty) and pvm.classof(k.place) == Code.CodePlaceLocal then
                ctx.view_values[k.dst.text] = view_parts(ctx, k.place["local"])
            else
                local addr = addr_from_place(ctx, k.place)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdLoadInfo(bid(k.dst), shape(k.access.ty), addr, memory_info(ctx, k.access, i.id.text))
            end
        elseif cls == Code.CodeInstStore then
            if is_view_ty(k.access.ty) and pvm.classof(k.place) == Code.CodePlaceLocal then
                ctx.view_values[k.place["local"].text] = view_parts(ctx, k.value)
            else
                local addr = addr_from_place(ctx, k.place)
                ctx.cmds[#ctx.cmds + 1] = Back.CmdStoreInfo(shape(k.access.ty), addr, bid(k.value), memory_info(ctx, k.access, i.id.text))
            end
        elseif cls == Code.CodeInstCall then
            local target_cls = pvm.classof(k.target)
            local target
            if target_cls == Code.CodeCallDirect then target = Back.BackCallDirect(func_id(k.target.func))
            elseif target_cls == Code.CodeCallExtern then target = Back.BackCallExtern(extern_id(k.target["extern"]))
            elseif target_cls == Code.CodeCallIndirect then target = Back.BackCallIndirect(bid(k.target.callee))
            else unsupported(k.target) end
            local sig = ctx.sigs[k.sig.text]
            local result = Back.BackCallStmt
            if k.dst ~= nil then
                local s = sig and sig.results[1] and scalar(sig.results[1]) or nil
                if s == nil then unsupported(k) end
                result = Back.BackCallValue(bid(k.dst), s)
            end
            local args = {}; for n = 1, #k.args do args[n] = bid(k.args[n]) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCall(result, target, sig_id(k.sig), args)
        else
            unsupported(k)
        end
        note_value(ctx, inst_dst_type(ctx, k))
    end

    local function term(ctx, t)
        local k = t.kind
        local cls = pvm.classof(k)
        if cls == Code.CodeTermJump then
            local args = {}; for i = 1, #k.args do args[i] = bid(k.args[i]) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdJump(block_id(k.dest), args)
        elseif cls == Code.CodeTermBranch then
            local ta, ea = {}, {}
            for i = 1, #k.then_args do ta[i] = bid(k.then_args[i]) end
            for i = 1, #k.else_args do ea[i] = bid(k.else_args[i]) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdBrIf(bid(k.cond), block_id(k.then_dest), ta, block_id(k.else_dest), ea)
        elseif cls == Code.CodeTermSwitch then
            local cases = {}
            for i = 1, #k.cases do cases[i] = Back.BackSwitchCase(k.cases[i].literal.raw or tostring(k.cases[i].literal.value), block_id(k.cases[i].dest)) end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchInt(bid(k.value), Back.BackI32, cases, block_id(k.default_dest))
        elseif cls == Code.CodeTermReturn then
            if #k.values == 0 then ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnVoid else ctx.cmds[#ctx.cmds + 1] = Back.CmdReturnValue(bid(k.values[1])) end
        elseif cls == Code.CodeTermTrap or cls == Code.CodeTermUnreachable then
            ctx.cmds[#ctx.cmds + 1] = Back.CmdTrap
        else
            unsupported(k)
        end
    end

    local function func(ctx, f)
        ctx.value_types = {}
        ctx.view_values = {}
        for i = 1, #(f.params or {}) do note_value(ctx, f.params[i].value, f.params[i].ty) end
        for i = 1, #(f.blocks or {}) do
            for j = 1, #(f.blocks[i].params or {}) do note_value(ctx, f.blocks[i].params[j].value, f.blocks[i].params[j].ty) end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdBeginFunc(func_id(f.id))
        for i = 1, #f.blocks do ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateBlock(block_id(f.blocks[i].id)) end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            for j = 1, #b.params do ctx.cmds[#ctx.cmds + 1] = Back.CmdAppendBlockParam(block_id(b.id), bid(b.params[j].value), shape(b.params[j].ty)) end
        end
        for i = 1, #f.blocks do
            local b = f.blocks[i]
            ctx.cmds[#ctx.cmds + 1] = Back.CmdSwitchToBlock(block_id(b.id))
            if b.id == f.entry then
                local params = {}; for j = 1, #f.params do params[j] = bid(f.params[j].value) end
                ctx.cmds[#ctx.cmds + 1] = Back.CmdBindEntryParams(block_id(b.id), params)
            end
            for j = 1, #b.insts do inst(ctx, b.insts[j]) end
            term(ctx, b.term)
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdFinishFunc(func_id(f.id))
    end

    local function module(code_module, opts)
        opts = opts or {}
        local report = CodeValidate.validate(code_module, opts.collector)
        if opts.validate ~= false and #report.issues > 0 then
            error("code_to_back: CodeModule failed validation with " .. tostring(#report.issues) .. " issue(s)", 2)
        end
        local ctx = { cmds = {}, sigs = {}, next_tmp = 0 }
        for i = 1, #code_module.sigs do ctx.sigs[code_module.sigs[i].id.text] = code_module.sigs[i] end
        for i = 1, #code_module.sigs do
            local s = code_module.sigs[i]
            local params, results = {}, {}
            for j = 1, #s.params do local bs = scalar(s.params[j]); if bs == nil then unsupported(s.params[j]) end; params[j] = bs end
            for j = 1, #s.results do local bs = scalar(s.results[j]); if bs == nil then unsupported(s.results[j]) end; results[j] = bs end
            ctx.cmds[#ctx.cmds + 1] = Back.CmdCreateSig(sig_id(s.id), params, results)
        end
        for i = 1, #(code_module.data or {}) do
            local d = code_module.data[i]
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDeclareData(data_id(d.id), d.size, d.align)
            for j = 1, #d.inits do data_init(ctx, d.inits[j], data_id(d.id)) end
        end
        for i = 1, #(code_module.globals or {}) do
            local g = code_module.globals[i]
            ctx.cmds[#ctx.cmds + 1] = Back.CmdDeclareData(data_id(g.id), g.size or 8, g.align or 1)
            for j = 1, #g.inits do data_init(ctx, g.inits[j], data_id(g.id)) end
        end
        for i = 1, #(code_module.externs or {}) do ctx.cmds[#ctx.cmds + 1] = Back.CmdDeclareExtern(extern_id(code_module.externs[i].id), code_module.externs[i].symbol, sig_id(code_module.externs[i].sig)) end
        local replacements = opts.replacement_funcs or {}
        for i = 1, #(code_module.funcs or {}) do
            local f = code_module.funcs[i]
            if replacements[f.name] == nil then
                local vis = (f.linkage == Code.CodeLinkageExport) and Core.VisibilityExport or Core.VisibilityLocal
                ctx.cmds[#ctx.cmds + 1] = Back.CmdDeclareFunc(vis, func_id(f.id), sig_id(f.sig))
            end
        end
        for name, cmds in pairs(replacements) do
            for i = 1, #cmds do ctx.cmds[#ctx.cmds + 1] = cmds[i] end
        end
        for i = 1, #(code_module.funcs or {}) do
            if replacements[code_module.funcs[i].name] == nil then func(ctx, code_module.funcs[i]) end
        end
        ctx.cmds[#ctx.cmds + 1] = Back.CmdFinalizeModule
        return Back.BackProgram(ctx.cmds)
    end

    api.module = module
    api.scalar = scalar

    T._moonlift_api_cache.code_to_back = api
    return api
end

return M
