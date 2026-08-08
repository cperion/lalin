package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Jmp = require("experiments.copy_patch_cps.lua55_trace.opcode_jmp")

local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_jmp_fixture")
local main = Undump.undump(bytes)
local proto = assert(main.protos[1])
-- while loop: LOADI, LT(owned JMP), ADDI(owned MMBINI), standalone JMP
assert(proto.code[1].name == "LOADI" and proto.code[2].name == "LT")
assert(proto.code[3].name == "JMP" and proto.code[4].name == "ADDI")
assert(proto.code[5].name == "MMBINI" and proto.code[6].name == "JMP")

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_jmp/bank.lua"))

-- Path [1, 6): the loop head+body. LT(1, owned JMP at 2) ADDI(3, owned MMBINI
-- at 4) JMP(5, back-edge to pc 1). The standalone JMP's target: 5 + (-5) + 1 = 1.
local path = Projection.project(proto, 1, 6)
assert(getmetatable(path) == Projection.DecodedPath and #path.occurrences == 3)
local jmp = path.occurrences[3]
assert(jmp.pc == 5 and jmp.target == 1, ("back-edge target %d"):format(jmp.target))

local EXIT = 6
local program = path:new_program(EXIT, bank)
local frame = program:new_frame():set_integer(0, 3):set_integer(1, 0)

-- Drive the loop from the host: each execute is one native pass; the
-- back-edge JMP returns COMPLETED at pc 1; the LT exit branch returns at
-- pc 6. Loop until the exit pc is reached.
local function run_loop(program, frame)
    local steps = 0
    while true do
        local status = program:execute(frame)
        assert(status == bank.status.completed, "loop pass did not complete")
        if frame.frame.resume_pc == EXIT then return steps end
        steps = steps + 1
        assert(steps < 10000, "loop did not terminate")
    end
end

local steps = run_loop(program, frame)
assert(steps == 3, ("loop steps %d"):format(steps))   -- x: 0->1->2->3
assert(tonumber(frame:integer(1)) == 3)

-- Re-enter with a fresh frame for repeated loops on the installed residual.
for _, a in ipairs({ 0, 1, 5, 100 }) do
    local f = program:new_frame():set_integer(0, a):set_integer(1, 0)
    run_loop(program, f)
    assert(tonumber(f:integer(1)) == a, ("while x<%d -> x=%s"):format(a, tostring(f:integer(1))))
end

-- Guard: a float 'a' fails at the LT guard pc (1) on re-entry.
do
    local f = program:new_frame():set_float(0, 3):set_integer(1, 0)
    assert(program:execute(f) == bank.status.guard_failed)
    assert(f.frame.resume_pc == 1)
end
program:free()

-- ---------------------------------------------------------------------
-- Leaf: a standalone JMP occurrence is a terminal that stores its target.
for _, target in ipairs({ 2, 4, 0 }) do
    local program = Native.Program.new({ Jmp.JmpOccurrence.new(0, target) }, 2, 1, bank)
    local frame = program:new_frame():set_integer(0, 7)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame.frame.resume_pc == target, ("jmp target %d got %d"):format(target, frame.frame.resume_pc))
    assert(program.recordings == 1)
    program:free()
end

-- A JMP mid-path stops the learner; install links only recorded occurrences
-- and the not-taken fallthrough terminal keeps the host coherent.
do
    local program = Native.Program.new({
        Native.MoveOccurrence.new(0, 2, 1), Jmp.JmpOccurrence.new(1, 4),
        Native.MoveOccurrence.new(2, 3, 0),
    }, 4, 3, bank)
    local frame = program:new_frame():set_integer(0, 7):set_integer(1, 9)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame.frame.resume_pc == 4)
    assert(tonumber(frame:integer(2)) == 9)   -- MOVE before the JMP ran
    assert(tonumber(frame:integer(3)) == 0)   -- occurrence after the JMP never ran
    program:free()
end

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5: same while loop, same results.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 jmp oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_while(a)
    local script = table.concat({
        "local x = 0",
        "while x < ", tostring(a), " do x = x + 1 end",
        "print(x)",
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_jmp.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_jmp.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    return tonumber(out:match("(%d+)"))
end

local cases = { 0, 1, 2, 7, -3, 100, 1000 }
for _, a in ipairs(cases) do
    local program = path:new_program(EXIT, bank)
    local f = program:new_frame():set_integer(0, a):set_integer(1, 0)
    run_loop(program, f)
    local native = tonumber(f:integer(1))
    local expected = stock_while(a)
    assert(native == expected,
        ("while x<%d: native=%d stock=%d"):format(a, native, expected))
    program:free()
end
print(("Lua55 jmp: ok terminal residual + %d loop cases native == stock"):format(#cases))
