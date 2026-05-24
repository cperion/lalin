-- Lua Interpreter VM — Proto validation trust boundary (Lua 5.5)

local moon = require("moonlift")
local host = require("moonlift.host")
local const = require("experiments.lua_interpreter_vm.src.constants")

local I = {}
for k, v in pairs(const.Err) do I["ERR_" .. k] = moon.int(v) end
for k, v in pairs(const.Op) do I["OP_" .. k] = moon.int(v) end

-- validate_proto: verify Proto is safe to execute
local validate_proto = host.region {
    ERR_RUNTIME = I.ERR_RUNTIME, ERR_BAD_OPCODE = I.ERR_BAD_OPCODE,
    OP_EXTRAARG = I.OP_EXTRAARG, OP_LOADK = I.OP_LOADK, OP_LOADKX = I.OP_LOADKX,
    OP_CLOSURE = I.OP_CLOSURE, OP_JMP = I.OP_JMP,
    OP_FORLOOP = I.OP_FORLOOP, OP_FORPREP = I.OP_FORPREP,
    OP_LOADI = I.OP_LOADI,
} [[
region validate_proto(L: ptr(LuaThread), p: ptr(Proto);
                      ok: cont(), invalid: cont(code: i32), oom: cont())
entry start()
    if p == nil then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if p.code_len == 0 then
        jump ok()
    end
    jump loop(pc = as(index, 0))
end
block loop(pc: index)
    if pc >= p.code_len then
        jump ok()
    end
    let word: u32 = p.code[pc].word
    let op: u16 = as(u16, word & 127)
    let a: u16 = as(u16, (word >> 7) & 255)
    let bx: u32 = (word >> 15) & 131071
    let sbx: i32 = as(i32, bx) - 65535
    if op > @{OP_EXTRAARG} then
        jump invalid(code = @{ERR_BAD_OPCODE})
    end
    if a >= p.maxstack then
        jump invalid(code = @{ERR_RUNTIME})
    end
    if op == @{OP_LOADK} or op == @{OP_LOADKX} then
        if as(index, bx) >= p.constants_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_LOADI} then
        -- LOADI uses sBx as immediate value, no constant table check needed
    end
    if op == @{OP_CLOSURE} then
        if as(index, bx) >= p.children_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    if op == @{OP_JMP} or op == @{OP_FORLOOP} or op == @{OP_FORPREP} then
        let target: i32 = as(i32, pc) + sbx
        if target < 0 or as(index, target) >= p.code_len then
            jump invalid(code = @{ERR_RUNTIME})
        end
    end
    jump loop(pc = pc + 1)
end
end
]]

return {
    validate_proto = validate_proto,
}
