package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Close = require("experiments.copy_patch_cps.lua55_trace.opcode_close")

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_close/bank.lua"))

-- CLOSE (54): a pass-through (the closed subset has no to-be-closed vars).
do
    local program = Native.Program.new({
        Close.CloseOccurrence.new(0), Close.CloseOccurrence.new(1),
    }, 2, 2, bank)
    local frame = Native.FrameOwner.new(2, 2, 0, nil, false)
    frame:set_integer(0, 7)
    assert(program:execute(frame) == bank.status.completed)
    -- the frame state is untouched
    assert(tonumber(frame:integer(0)) == 7)
    -- re-execution on the residual
    assert(program:execute(frame) == bank.status.completed)
    program:free()
end

-- TBC (55): the <close> contract is a visible rejection.
do
    local program = Native.Program.new({
        Close.TbcOccurrence.new(0, 1),
    }, 2, 1, bank)
    local frame = Native.FrameOwner.new(2, 1, 0, nil, false)
    frame:set_integer(1, 7)
    assert(program:execute(frame) == bank.status.rejected)
    program:free()
end

-- ERRNNIL (82): passes through when R[A] is nil; rejects when non-nil
-- ("global already defined").
do
    local program = Native.Program.new({
        Close.ErrnnilOccurrence.new(0, 0),
    }, 2, 1, bank)
    local frame = Native.FrameOwner.new(2, 1, 0, nil, false)
    frame:set_nil(0)
    assert(program:execute(frame) == bank.status.completed)
    -- residual recompute: a non-nil register guard-fails
    frame:set_integer(0, 7)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 0)
    program:free()
end
do
    local program = Native.Program.new({
        Close.ErrnnilOccurrence.new(0, 0),
    }, 2, 1, bank)
    local frame = Native.FrameOwner.new(2, 1, 0, nil, false)
    frame:set_integer(0, 7)
    assert(program:execute(frame) == bank.status.rejected)
    program:free()
end

print("Lua55 close/tbc/errnnil: ok pass-through close, <close> rejection, errnnil nil-check")
