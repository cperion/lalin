-- Lua Interpreter VM — Dispatch instruction region
-- Single region: fetch instruction, switch on opcode, emit handler.

-- This is a hand-written region, not generated. If opcodes change,
-- update the switch arms and handler effects here.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

-- Build values table for all opcode constants
local I = {}
for k, v in pairs(const.Op) do I["OP_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end

local dispatch_instruction = host.region {
    OP_MOVE = I.OP_MOVE, OP_LOADK = I.OP_LOADK, OP_LOADBOOL = I.OP_LOADBOOL,
    OP_LOADNIL = I.OP_LOADNIL, OP_GETUPVAL = I.OP_GETUPVAL,
    OP_GETGLOBAL = I.OP_GETGLOBAL, OP_GETTABLE = I.OP_GETTABLE,
    OP_SETGLOBAL = I.OP_SETGLOBAL, OP_SETUPVAL = I.OP_SETUPVAL,
    OP_SETTABLE = I.OP_SETTABLE, OP_NEWTABLE = I.OP_NEWTABLE,
    OP_SELF = I.OP_SELF, OP_ADD = I.OP_ADD, OP_SUB = I.OP_SUB,
    OP_MUL = I.OP_MUL, OP_DIV = I.OP_DIV, OP_MOD = I.OP_MOD,
    OP_POW = I.OP_POW, OP_UNM = I.OP_UNM, OP_NOT = I.OP_NOT,
    OP_LEN = I.OP_LEN, OP_CONCAT = I.OP_CONCAT, OP_JMP = I.OP_JMP,
    OP_EQ = I.OP_EQ, OP_LT = I.OP_LT, OP_LE = I.OP_LE,
    OP_TEST = I.OP_TEST, OP_TESTSET = I.OP_TESTSET,
    OP_CALL = I.OP_CALL, OP_TAILCALL = I.OP_TAILCALL,
    OP_RETURN = I.OP_RETURN, OP_FORLOOP = I.OP_FORLOOP,
    OP_FORPREP = I.OP_FORPREP, OP_TFORLOOP = I.OP_TFORLOOP,
    OP_SETLIST = I.OP_SETLIST, OP_CLOSE = I.OP_CLOSE,
    OP_CLOSURE = I.OP_CLOSURE, OP_VARARG = I.OP_VARARG,
    ERR_BAD_OPCODE = I.ERR_BAD_OPCODE,
} [[
region dispatch_instruction(
    L: ptr(LuaThread),
    cur_frame: ptr(Frame),
    cur_pc: index,
    cur_base: index,
    cur_top: index;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    returned: cont(nres: i32),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
entry decode()
    let cl: ptr(LClosure) = as(ptr(LClosure), cur_frame.closure.bits)
    let code_ptr: ptr(Instr) = cl.proto.code + cur_pc
    let instr: Instr = *code_ptr
    let a: u16 = instr.a
    let b: u16 = instr.b
    let c: u16 = instr.c
    let bx: u32 = instr.bx
    let sbx: i32 = instr.sbx
    switch instr.op do
    case 0 then
        emit op_move(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next)
    case 1 then
        emit op_loadk(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next)
    case 2 then
        emit op_loadbool(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next)
    case 3 then
        emit op_loadnil(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next)
    case 4 then
        emit op_getupval(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next)
    case 5 then
        emit op_getglobal(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 6 then
        emit op_gettable(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 7 then
        emit op_setglobal(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 8 then
        emit op_setupval(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next)
    case 9 then
        emit op_settable(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 10 then
        emit op_newtable(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, oom = dispatch_oom)
    case 11 then
        emit op_self(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 12 then
        emit op_add(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error)
    case 13 then
        emit op_sub(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error)
    case 14 then
        emit op_mul(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error)
    case 15 then
        emit op_div(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error)
    case 16 then
        emit op_mod(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error)
    case 17 then
        emit op_pow(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error)
    case 18 then
        emit op_unm(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error)
    case 19 then
        emit op_not(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next)
    case 20 then
        emit op_len(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 21 then
        emit op_concat(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 22 then
        emit op_jmp(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; do_jump = forward_jump)
    case 23 then
        emit op_eq(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 24 then
        emit op_lt(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 25 then
        emit op_le(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 26 then
        emit op_test(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump)
    case 27 then
        emit op_testset(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump)
    case 28 then
        emit op_call(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 29 then
        emit op_tailcall(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 30 then
        emit op_return(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; resume_parent = dispatch_resume, finished = dispatch_finished, error = dispatch_error, oom = dispatch_oom)
    case 31 then
        emit op_forloop(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, error = dispatch_error)
    case 32 then
        emit op_forprep(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; do_jump = forward_jump, error = dispatch_error)
    case 33 then
        emit op_tforloop(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, do_jump = forward_jump, enter_lua = dispatch_lua, enter_native = dispatch_native, yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom)
    case 34 then
        emit op_setlist(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, oom = dispatch_oom)
    case 35 then
        emit op_close(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, oom = dispatch_oom)
    case 36 then
        emit op_closure(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, error = dispatch_error, oom = dispatch_oom)
    case 37 then
        emit op_vararg(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, bx, sbx; next = do_next, error = dispatch_error, oom = dispatch_oom)
    default then
        jump error(code = @{ERR_BAD_OPCODE})
    end
end
-- Continuation forwarding blocks
block do_next(frame: ptr(Frame), pc: index, base: index, top: index)
    jump next(frame = frame, pc = pc, base = base, top = top)
end
block forward_jump(frame: ptr(Frame), pc: index, base: index, top: index)
    jump do_jump(frame = frame, pc = pc, base = base, top = top)
end
block dispatch_lua(child: ptr(Frame))
    jump enter_lua(child = child)
end
block dispatch_native(cl: ptr(CClosure))
    jump enter_native(cl = cl)
end
block dispatch_returned(nres: i32)
    jump returned(nres = nres)
end
block dispatch_yielded(nres: i32)
    jump yielded(nres = nres)
end
block dispatch_error(code: i32)
    jump error(code = code)
end
block dispatch_oom()
    jump oom()
end
block dispatch_finished(nres: i32)
    jump returned(nres = nres)
end
block dispatch_resume(parent: ptr(Frame), pc: index, base: index, top: index)
    jump next(frame = parent, pc = pc, base = base, top = top)
end
end
]]

-- opcodes metadata (still useful for other tooling)
local opcodes = {
    { name = "MOVE",     mode = "ABC",  handler = "op_move",     effects = {"next"} },
    { name = "LOADK",    mode = "ABx",  handler = "op_loadk",    effects = {"next"} },
    { name = "LOADBOOL", mode = "ABC",  handler = "op_loadbool", effects = {"next"} },
    { name = "LOADNIL",  mode = "ABC",  handler = "op_loadnil",  effects = {"next"} },
    { name = "GETUPVAL", mode = "ABC",  handler = "op_getupval", effects = {"next"} },
    { name = "GETGLOBAL",mode = "ABx",  handler = "op_getglobal",effects = {"next", "call", "error", "oom"} },
    { name = "GETTABLE", mode = "ABC",  handler = "op_gettable", effects = {"next", "call", "yield", "error", "oom"} },
    { name = "SETGLOBAL",mode = "ABx",  handler = "op_setglobal",effects = {"next", "error", "oom"} },
    { name = "SETUPVAL", mode = "ABC",  handler = "op_setupval", effects = {"next"} },
    { name = "SETTABLE", mode = "ABC",  handler = "op_settable", effects = {"next", "call", "yield", "error", "oom"} },
    { name = "NEWTABLE", mode = "ABC",  handler = "op_newtable", effects = {"next", "oom"} },
    { name = "SELF",     mode = "ABC",  handler = "op_self",     effects = {"next", "call", "yield", "error", "oom"} },
    { name = "ADD",      mode = "ABC",  handler = "op_add",      effects = {"next", "call", "yield", "error"} },
    { name = "SUB",      mode = "ABC",  handler = "op_sub",      effects = {"next", "call", "yield", "error"} },
    { name = "MUL",      mode = "ABC",  handler = "op_mul",      effects = {"next", "call", "yield", "error"} },
    { name = "DIV",      mode = "ABC",  handler = "op_div",      effects = {"next", "call", "yield", "error"} },
    { name = "MOD",      mode = "ABC",  handler = "op_mod",      effects = {"next", "call", "yield", "error"} },
    { name = "POW",      mode = "ABC",  handler = "op_pow",      effects = {"next", "call", "yield", "error"} },
    { name = "UNM",      mode = "ABC",  handler = "op_unm",      effects = {"next", "call", "yield", "error"} },
    { name = "NOT",      mode = "ABC",  handler = "op_not",      effects = {"next"} },
    { name = "LEN",      mode = "ABC",  handler = "op_len",      effects = {"next", "call", "yield", "error", "oom"} },
    { name = "CONCAT",   mode = "ABC",  handler = "op_concat",   effects = {"next", "call", "yield", "error", "oom"} },
    { name = "JMP",      mode = "AsBx", handler = "op_jmp",      effects = {"jump"} },
    { name = "EQ",       mode = "ABC",  handler = "op_eq",       effects = {"next", "jump", "call", "yield", "error"} },
    { name = "LT",       mode = "ABC",  handler = "op_lt",       effects = {"next", "jump", "call", "yield", "error"} },
    { name = "LE",       mode = "ABC",  handler = "op_le",       effects = {"next", "jump", "call", "yield", "error"} },
    { name = "TEST",     mode = "ABC",  handler = "op_test",     effects = {"next", "jump"} },
    { name = "TESTSET",  mode = "ABC",  handler = "op_testset",  effects = {"next", "jump"} },
    { name = "CALL",     mode = "ABC",  handler = "op_call",     effects = {"next", "call", "yield", "error", "oom"} },
    { name = "TAILCALL", mode = "ABC",  handler = "op_tailcall", effects = {"next", "call", "yield", "error", "oom"} },
    { name = "RETURN",   mode = "ABC",  handler = "op_return",   effects = {"return", "finished", "error", "oom"} },
    { name = "FORLOOP",  mode = "AsBx", handler = "op_forloop",  effects = {"next", "jump", "error"} },
    { name = "FORPREP",  mode = "AsBx", handler = "op_forprep",  effects = {"jump", "error"} },
    { name = "TFORLOOP", mode = "ABC",  handler = "op_tforloop", effects = {"next", "jump", "call", "yield", "error", "oom"} },
    { name = "SETLIST",  mode = "ABC",  handler = "op_setlist",  effects = {"next", "oom"} },
    { name = "CLOSE",    mode = "A",    handler = "op_close",    effects = {"next", "oom"} },
    { name = "CLOSURE",  mode = "ABx",  handler = "op_closure",  effects = {"next", "oom"} },
    { name = "VARARG",   mode = "ABC",  handler = "op_vararg",   effects = {"next", "oom"} },
}

return {
    dispatch_instruction = dispatch_instruction,
    opcodes = opcodes,
}
