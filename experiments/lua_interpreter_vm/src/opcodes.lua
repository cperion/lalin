-- Lua Interpreter VM — Dispatch instruction (Lua 5.5)
-- Explicit switch: every case arm written directly in the Moonlift source.
-- No template-based generation; each opcode is grep-shaped.

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")
local handlers = require("experiments.lua_interpreter_vm.src.op_handlers")

-- Build switch arms as explicit Moonlift case blocks.
-- Each arm is a visible string in the dispatch source.
local arms = {}
local function arm(op_num, handler_name, conts)
    arms[#arms + 1] = string.format([[
    case %d then
        emit %s(L, cur_frame, cur_pc, cur_base, cur_top, a, b, c, k, bx, sbx;
            %s)]], op_num, handler_name, conts)
end

-- All 85 opcodes with literal continuation routing.
arm(0,  "op_move",       "next = do_next")
arm(1,  "op_loadi",      "next = do_next")
arm(2,  "op_loadf",      "next = do_next")
arm(3,  "op_loadk",      "next = do_next")
arm(4,  "op_loadkx",     "next = do_next")
arm(5,  "op_loadfalse",  "next = do_next")
arm(6,  "op_lfalseskip", "next = do_next")
arm(7,  "op_loadtrue",   "next = do_next")
arm(8,  "op_loadnil",    "next = do_next")
arm(9,  "op_getupval",   "next = do_next")
arm(10, "op_setupval",   "next = do_next")
arm(11, "op_gettabup",   [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(12, "op_gettable",   [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(13, "op_geti",       [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(14, "op_getfield",   [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(15, "op_settabup",   [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(16, "op_settable",   [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(17, "op_setti",      [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(18, "op_setfield",   [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(19, "op_newtable",   [[next = do_next,
            oom = dispatch_oom]])
arm(20, "op_self",       [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(21, "op_addi",       [[next = do_next,
            error = dispatch_error]])
arm(22, "op_addk",       [[next = do_next,
            error = dispatch_error]])
arm(23, "op_subk",       [[next = do_next,
            error = dispatch_error]])
arm(24, "op_mulk",       [[next = do_next,
            error = dispatch_error]])
arm(25, "op_modk",       [[next = do_next,
            error = dispatch_error]])
arm(26, "op_powk",       [[next = do_next,
            error = dispatch_error]])
arm(27, "op_divk",       [[next = do_next,
            error = dispatch_error]])
arm(28, "op_idivk",      [[next = do_next,
            error = dispatch_error]])
arm(29, "op_bandk",      [[next = do_next,
            error = dispatch_error]])
arm(30, "op_bork",       [[next = do_next,
            error = dispatch_error]])
arm(31, "op_bxork",      [[next = do_next,
            error = dispatch_error]])
arm(32, "op_shli",       [[next = do_next,
            error = dispatch_error]])
arm(33, "op_shri",       [[next = do_next,
            error = dispatch_error]])
arm(34, "op_add",        [[next = do_next,
            error = dispatch_error]])
arm(35, "op_sub",        [[next = do_next,
            error = dispatch_error]])
arm(36, "op_mul",        [[next = do_next,
            error = dispatch_error]])
arm(37, "op_mod",        [[next = do_next,
            error = dispatch_error]])
arm(38, "op_pow",        [[next = do_next,
            error = dispatch_error]])
arm(39, "op_div",        [[next = do_next,
            error = dispatch_error]])
arm(40, "op_idiv",       [[next = do_next,
            error = dispatch_error]])
arm(41, "op_band",       [[next = do_next,
            error = dispatch_error]])
arm(42, "op_bor",        [[next = do_next,
            error = dispatch_error]])
arm(43, "op_bxor",       [[next = do_next,
            error = dispatch_error]])
arm(44, "op_shl",        [[next = do_next,
            error = dispatch_error]])
arm(45, "op_shr",        [[next = do_next,
            error = dispatch_error]])
arm(46, "op_mmbin",      [[enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(47, "op_mmbini",     [[enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(48, "op_mmbink",     [[enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(49, "op_unm",        [[next = do_next,
            error = dispatch_error]])
arm(50, "op_bnot",       [[next = do_next,
            error = dispatch_error]])
arm(51, "op_not",        "next = do_next")
arm(52, "op_len",        [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(53, "op_concat",     [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(54, "op_close",      [[next = do_next,
            oom = dispatch_oom]])
arm(55, "op_tbc",        [[next = do_next,
            error = dispatch_error, oom = dispatch_oom]])
arm(56, "op_jmp",        "do_jump = forward_jump")
arm(57, "op_eq",         [[next = do_next, do_jump = forward_jump,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            error = dispatch_error, oom = dispatch_oom]])
arm(58, "op_lt",         [[next = do_next, do_jump = forward_jump,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            error = dispatch_error, oom = dispatch_oom]])
arm(59, "op_le",         [[next = do_next, do_jump = forward_jump,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            error = dispatch_error, oom = dispatch_oom]])
arm(60, "op_eqk",        "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(61, "op_eqi",        "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(62, "op_lti",        "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(63, "op_lei",        "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(64, "op_gti",        "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(65, "op_gei",        "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(66, "op_test",       "next = do_next, do_jump = forward_jump")
arm(67, "op_testset",    "next = do_next, do_jump = forward_jump")
arm(68, "op_call",       [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(69, "op_tailcall",   [[next = do_next,
            enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(70, "op_return",     "resume_parent = dispatch_resume, finished = dispatch_finished, error = dispatch_error, oom = dispatch_oom")
arm(71, "op_return0",    "resume_parent = dispatch_resume, finished = dispatch_finished, error = dispatch_error, oom = dispatch_oom")
arm(72, "op_return1",    "resume_parent = dispatch_resume, finished = dispatch_finished, error = dispatch_error, oom = dispatch_oom")
arm(73, "op_forloop",    "next = do_next, do_jump = forward_jump, error = dispatch_error")
arm(74, "op_forprep",    "do_jump = forward_jump, error = dispatch_error")
arm(75, "op_tforprep",   "do_jump = forward_jump")
arm(76, "op_tforcall",   [[enter_lua = dispatch_lua, enter_native = dispatch_native,
            yielded = dispatch_yielded, error = dispatch_error, oom = dispatch_oom]])
arm(77, "op_tforloop",   "next = do_next, do_jump = forward_jump")
arm(78, "op_setlist",    "next = do_next, oom = dispatch_oom")
arm(79, "op_closure",    "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(80, "op_vararg",     "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(81, "op_getvarg",    "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(82, "op_errnnil",    "next = do_next, error = dispatch_error, oom = dispatch_oom")
arm(83, "op_varargprep", "next = do_next, oom = dispatch_oom")
arm(84, "op_extraarg",   "next = do_next")

-- Build values table
local VALS = {}
for k, v in pairs(const.Tag) do VALS["TAG_" .. k] = moon.int(v) end
for k, v in pairs(const.Err) do VALS["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Op) do VALS["OP_" .. k] = moon.int(v) end
for k, v in pairs(const.Resume) do VALS["RESUME_" .. k] = moon.int(v) end
for k, v in pairs(const.ProtoFlag) do VALS["PF_" .. k] = moon.int(v) end

local dispatch_src = [[
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
    let ip: ptr(Instr) = cl.proto.code + cur_pc
    let op: u16 = ip.op
    let a: u16 = ip.a
    let b: u16 = ip.b
    let c: u16 = ip.c
    let k: u8 = ip.k
    let bx: u32 = ip.bx
    let sbx: i32 = ip.sbx
    switch op do
]] .. table.concat(arms, "\n") .. [[
    default then
        jump error(code = @{ERR_BAD_OPCODE})
    end
end
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

local dispatch_instruction = host.region(VALS)(dispatch_src)

-- Opcode metadata (for tooling, disassembly, etc.)
local opcodes_meta = {}
for name, val in pairs(const.Op) do if val <= 84 then
    local hname = "op_" .. name:lower()
    if name == "SETI" then hname = "op_setti" end
    local entry = { name = name, op = val, handler = hname }
    if name == "MOVE"       then entry.mode = "ABC" elseif name == "LOADI"      then entry.mode = "AsBx"
    elseif name == "LOADF"   then entry.mode = "AsBx" elseif name == "LOADK"     then entry.mode = "ABx"
    elseif name == "LOADKX"  then entry.mode = "ABx"  elseif name == "LOADFALSE" then entry.mode = "A"
    elseif name == "LFALSESKIP" then entry.mode = "A" elseif name == "LOADTRUE" then entry.mode = "A"
    elseif name == "LOADNIL" then entry.mode = "AB"   elseif name == "GETUPVAL"  then entry.mode = "ABC"
    elseif name == "SETUPVAL" then entry.mode = "ABC" elseif name == "GETTABUP"  then entry.mode = "ABC"
    elseif name == "GETTABLE" then entry.mode = "ABC" elseif name == "GETI"      then entry.mode = "ABC"
    elseif name == "GETFIELD" then entry.mode = "ABC" elseif name == "SETTABUP"  then entry.mode = "ABC"
    elseif name == "SETTABLE" then entry.mode = "ABC" elseif name == "SETTI"     then entry.mode = "ABC"
    elseif name == "SETFIELD" then entry.mode = "ABC" elseif name == "NEWTABLE"  then entry.mode = "ABC"
    elseif name == "SELF"    then entry.mode = "ABC"  elseif name == "ADDI"      then entry.mode = "ABC"
    elseif name == "ADDK"    then entry.mode = "ABx"  elseif name == "SUBK"      then entry.mode = "ABx"
    elseif name == "MULK"    then entry.mode = "ABx"  elseif name == "MODK"      then entry.mode = "ABx"
    elseif name == "POWK"    then entry.mode = "ABx"  elseif name == "DIVK"      then entry.mode = "ABx"
    elseif name == "IDIVK"   then entry.mode = "ABx"  elseif name == "BANDK"     then entry.mode = "ABx"
    elseif name == "BORK"    then entry.mode = "ABx"  elseif name == "BXORK"     then entry.mode = "ABx"
    elseif name == "SHLI"    then entry.mode = "ABC"  elseif name == "SHRI"      then entry.mode = "ABC"
    elseif name == "ADD"     then entry.mode = "ABC"  elseif name == "SUB"       then entry.mode = "ABC"
    elseif name == "MUL"     then entry.mode = "ABC"  elseif name == "MOD"       then entry.mode = "ABC"
    elseif name == "POW"     then entry.mode = "ABC"  elseif name == "DIV"       then entry.mode = "ABC"
    elseif name == "IDIV"    then entry.mode = "ABC"  elseif name == "BAND"      then entry.mode = "ABC"
    elseif name == "BOR"     then entry.mode = "ABC"  elseif name == "BXOR"      then entry.mode = "ABC"
    elseif name == "SHL"     then entry.mode = "ABC"  elseif name == "SHR"       then entry.mode = "ABC"
    elseif name == "MMBIN"   then entry.mode = "ABC"  elseif name == "MMBINI"    then entry.mode = "ABC"
    elseif name == "MMBINK"  then entry.mode = "ABx"  elseif name == "UNM"       then entry.mode = "ABC"
    elseif name == "BNOT"    then entry.mode = "ABC"  elseif name == "NOT"       then entry.mode = "ABC"
    elseif name == "LEN"     then entry.mode = "ABC"  elseif name == "CONCAT"    then entry.mode = "ABC"
    elseif name == "CLOSE"   then entry.mode = "A"    elseif name == "TBC"       then entry.mode = "A"
    elseif name == "JMP"     then entry.mode = "AsBx" elseif name == "EQ"        then entry.mode = "ABC"
    elseif name == "LT"      then entry.mode = "ABC"  elseif name == "LE"        then entry.mode = "ABC"
    elseif name == "EQK"     then entry.mode = "ABx"  elseif name == "EQI"       then entry.mode = "AsBx"
    elseif name == "LTI"     then entry.mode = "AsBx" elseif name == "LEI"       then entry.mode = "AsBx"
    elseif name == "GTI"     then entry.mode = "AsBx" elseif name == "GEI"       then entry.mode = "AsBx"
    elseif name == "TEST"    then entry.mode = "ABC"  elseif name == "TESTSET"   then entry.mode = "ABC"
    elseif name == "CALL"    then entry.mode = "ABC"  elseif name == "TAILCALL"  then entry.mode = "ABC"
    elseif name == "RETURN"  then entry.mode = "ABC"  elseif name == "RETURN0"   then entry.mode = "A"
    elseif name == "RETURN1" then entry.mode = "A"    elseif name == "FORLOOP"   then entry.mode = "AsBx"
    elseif name == "FORPREP" then entry.mode = "AsBx" elseif name == "TFORPREP"  then entry.mode = "AsBx"
    elseif name == "TFORCALL" then entry.mode = "ABC" elseif name == "TFORLOOP"  then entry.mode = "ABC"
    elseif name == "SETLIST" then entry.mode = "ABC"  elseif name == "CLOSURE"   then entry.mode = "ABx"
    elseif name == "VARARG"  then entry.mode = "ABC"  elseif name == "GETVARG"   then entry.mode = "ABC"
    elseif name == "ERRNNIL" then entry.mode = "AsBx" elseif name == "VARARGPREP" then entry.mode = "A"
    elseif name == "EXTRAARG" then entry.mode = "Ax"  end
    opcodes_meta[val] = entry
end end

return {
    dispatch_instruction = dispatch_instruction,
    opcodes = opcodes_meta,
}
