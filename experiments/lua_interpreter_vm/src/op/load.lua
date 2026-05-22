-- Moonlift VM — Load/store opcode handlers.
-- Dispatch is scalarized; Value stores currently use aggregate assignment where
-- the backend does not yet accept multiple scalar field stores to the same slot.

local B = require("experiments.lua_interpreter_vm.src.op._init")
local R, H = B.R, B.H

local op_move = R([[
region op_move(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = L.stack[base + as(index, b)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadi = R([[
region op_loadi(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_INTEGER}, aux = 0, bits = as(u64, as(i64, sbx)) }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadf = R([[
region op_loadf(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_NUM}, aux = 0, bits = as(u64, as(f64, as(i64, sbx))) }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadk = R([[
region op_loadk(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    L.stack[base + as(index, a)] = cl.proto.constants[bx]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadkx = R([[
region op_loadkx(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let extra: ptr(Instr) = cl.proto.code + (pc + 1)
    L.stack[base + as(index, a)] = cl.proto.constants[extra.bx]
    jump next(frame = frame, pc = pc + 2, base = base, top = top)
end
end
]])

local op_loadfalse = R([[
region op_loadfalse(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_loadtrue = R([[
region op_loadtrue(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_TRUE}, aux = 0, bits = 0 }
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_lfalseskip = R([[
region op_lfalseskip(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    L.stack[base + as(index, a)] = { tag = @{TAG_FALSE}, aux = 0, bits = 0 }
    jump next(frame = frame, pc = pc + 2, base = base, top = top)
end
end
]])

local op_loadnil = R([[
region op_loadnil(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    let first: index = base + as(index, a)
    let last: index = first + as(index, b)
    jump loop(i = first, last = last, ret_pc = pc + 1, ret_base = base, ret_top = top)
end
block loop(i: index, last: index, ret_pc: index, ret_base: index, ret_top: index)
    if i > last then jump next(frame = frame, pc = ret_pc, base = ret_base, top = ret_top) end
    L.stack[i] = { tag = @{TAG_NIL}, aux = 0, bits = 0 }
    jump loop(i = i + 1, last = last, ret_pc = ret_pc, ret_base = ret_base, ret_top = ret_top)
end
end
]])

local op_getupval = R([[
region op_getupval(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    L.stack[base + as(index, a)] = *uv.v
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_setupval = R([[
region op_setupval(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    let cl: ptr(LClosure) = as(ptr(LClosure), frame.closure.bits)
    let uv: ptr(UpVal) = cl.upvals[b]
    let p: ptr(Value) = uv.v
    p[0] = L.stack[base + as(index, a)]
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

local op_extraarg = R([[
region op_extraarg(]] .. H .. [[;]] .. B.next_only .. [[)
entry start()
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
end
]])

return {
    op_move = op_move, op_loadi = op_loadi, op_loadf = op_loadf,
    op_loadk = op_loadk, op_loadkx = op_loadkx,
    op_loadfalse = op_loadfalse, op_loadtrue = op_loadtrue, op_lfalseskip = op_lfalseskip,
    op_loadnil = op_loadnil,
    op_getupval = op_getupval, op_setupval = op_setupval,
    op_extraarg = op_extraarg,
}
