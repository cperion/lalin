package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local O = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
local Q = O.quote_id
local I64_MIN = O.ffi.cast("int64_t", 0x8000000000000000ULL)
local I64_MAX = O.ffi.cast("int64_t", 0x7fffffffffffffffULL)

local function assert_integer(frame, index, value)
    assert(frame:tag(index) == bank.tags.integer)
    assert(frame:integer(index) == O.ffi.new("int64_t", value))
end

local function assert_float(frame, index, value)
    assert(frame:tag(index) == bank.tags.floating)
    assert(frame:floating(index) == value)
end

do
    local occurrences = {
        O.LoadIOccurrence.new(0, 0, -65535),
        O.LoadFOccurrence.new(1, 1, 65536),
        O.MoveOccurrence.new(2, 2, 0),
        O.LoadFalseOccurrence.new(3, 3),
        O.LoadFalseSkipOccurrence.new(4, 4),
        O.LoadTrueOccurrence.new(6, 5),
        O.LoadNilOccurrence.new(7, 6, 3),
        O.LoadKOccurrence.new(8, 9, O.NilConstant.new()),
        O.LoadKOccurrence.new(9, 10, O.FalseConstant.new()),
        O.LoadKOccurrence.new(10, 11, O.TrueConstant.new()),
        O.LoadKOccurrence.new(11, 12, O.IntegerConstant.new(I64_MIN)),
        O.LoadKOccurrence.new(12, 13, O.FloatConstant.new(-0.0)),
        O.LoadKXOccurrence.new(13, 14, O.NilConstant.new()),
        O.LoadKXOccurrence.new(15, 15, O.FalseConstant.new()),
        O.LoadKXOccurrence.new(17, 16, O.TrueConstant.new()),
        O.LoadKXOccurrence.new(19, 17, O.IntegerConstant.new(I64_MAX)),
        O.LoadKXOccurrence.new(21, 18, O.FloatConstant.new(1.5)),
    }
    local program = O.Program.new(occurrences, 19, 23, bank)
    local frame = program:new_frame()
    assert(program.learner:permissions():sub(1, 3) == "r-x")
    assert(program:execute(frame) == bank.status.completed)
    assert(program.recordings == 1 and program.residual)
    assert(program.residual:permissions():sub(1, 3) == "r-x")
    assert(frame.frame.slot_cursor == #occurrences and frame.frame.resume_pc == 23)

    local expected_quotes = {
        Q(1, 1), Q(2, 1), Q(0, 4), Q(5, 1), Q(6, 1), Q(7, 1), Q(8, 1),
        Q(3, 1), Q(3, 2), Q(3, 3), Q(3, 4), Q(3, 5),
        Q(4, 1), Q(4, 2), Q(4, 3), Q(4, 4), Q(4, 5),
    }
    for index = 1, #expected_quotes do
        assert(frame.slots[index - 1].quote == expected_quotes[index])
    end
    assert(frame.slots[2].expected_tag == bank.tags.integer)

    assert_integer(frame, 0, -65535)
    assert_float(frame, 1, 65536)
    assert_integer(frame, 2, -65535)
    assert(frame:tag(3) == bank.tags.false_value)
    assert(frame:tag(4) == bank.tags.false_value)
    assert(frame:tag(5) == bank.tags.true_value)
    for index = 6, 9 do assert(frame:tag(index) == bank.tags.nil_value) end
    assert(frame:tag(10) == bank.tags.false_value)
    assert(frame:tag(11) == bank.tags.true_value)
    assert_integer(frame, 12, I64_MIN)
    assert_float(frame, 13, -0.0)
    assert(frame:tag(14) == bank.tags.nil_value)
    assert(frame:tag(15) == bank.tags.false_value)
    assert(frame:tag(16) == bank.tags.true_value)
    assert_integer(frame, 17, I64_MAX)
    assert_float(frame, 18, 1.5)

    for index = 0, 18 do frame:set_true(index) end
    assert(program:execute(frame) == bank.status.completed)
    assert(program.recordings == 1 and frame.frame.resume_pc == 23)
    assert_integer(frame, 0, -65535)
    assert_integer(frame, 2, -65535)
    assert_float(frame, 18, 1.5)

    for _ = 1, 1000 do assert(program:execute(frame) == bank.status.completed) end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 10000 do assert(program:execute(frame) == bank.status.completed) end
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    assert(growth < 8, ("recurring opcode residual calls allocated %.3f KiB"):format(growth))

    program:free()
    local ok, message = pcall(function() program:execute(frame) end)
    assert(not ok and message:match("released"))
end

local setters = {
    function(frame) frame:set_nil(0) end,
    function(frame) frame:set_false(0) end,
    function(frame) frame:set_true(0) end,
    function(frame) frame:set_integer(0, -17) end,
    function(frame) frame:set_float(0, 3.25) end,
}

for expected_tag = 0, 4 do
    local program = O.Program.new({ O.MoveOccurrence.new(7, 1, 0) }, 2, 8, bank)
    local frame = program:new_frame()
    setters[expected_tag + 1](frame)
    frame:set_integer(1, 99)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame:tag(1) == expected_tag)
    assert(frame.slots[0].quote == Q(0, expected_tag + 1))
    assert(frame.slots[0].expected_tag == expected_tag)

    frame:set_true(0):set_integer(1, 99)
    if expected_tag == bank.tags.true_value then frame:set_false(0) end
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 7)
    assert_integer(frame, 1, 99)
    assert(program.recordings == 1)
    program:free()
end

do
    local program = O.Program.new({ O.MoveOccurrence.new(30, 0, 0) }, 1, 31, bank)
    local frame = program:new_frame():set_float(0, 12.5)
    assert(program:execute(frame) == bank.status.completed)
    assert(program:execute(frame) == bank.status.completed)
    assert_float(frame, 0, 12.5)
    program:free()
end

do
    local program = O.Program.new({ O.LoadNilOccurrence.new(40, 0, 256) }, 256, 41, bank)
    local frame = program:new_frame()
    for index = 0, 255 do frame:set_integer(index, index) end
    assert(program:execute(frame) == bank.status.completed)
    for index = 0, 255 do assert(frame:tag(index) == bank.tags.nil_value) end
    for index = 0, 255 do frame:set_integer(index, index) end
    assert(program:execute(frame) == bank.status.completed)
    for index = 0, 255 do assert(frame:tag(index) == bank.tags.nil_value) end
    program:free()
end

do
    local program = O.Program.new({ O.MoveOccurrence.new(50, 1, 0) }, 2, 51, bank)
    local frame = program:new_frame()
    frame.values[0].tag = 7
    frame.values[0].payload.reference = 0x1234
    assert(program:execute(frame) == bank.status.completed)
    assert(frame:tag(1) == bank.tags.table_value and frame:reference(1) == 0x1234)
    -- the residual guards the table leaf: a closure tag guard-fails
    frame.values[0].tag = 8
    assert(program:execute(frame) == bank.status.guard_failed)
    program:free()
    -- a fresh program learns the closure leaf
    local program2 = O.Program.new({ O.MoveOccurrence.new(50, 1, 0) }, 2, 51, bank)
    local frame2 = program2:new_frame()
    frame2.values[0].tag = 8
    frame2.values[0].payload.reference = 0x5678
    assert(program2:execute(frame2) == bank.status.completed)
    assert(frame2:tag(1) == bank.tags.closure_value and frame2:reference(1) == 0x5678)
    program2:free()
end

do
    local ok, message = pcall(function()
        O.Program.new({ O.LoadIOccurrence.new(60, 0, 1) }, 1, 61, bank, 1)
    end)
    assert(not ok and message:match("capacity exceeded"))
end

print("Lua55 opcodes 0-8: ok native first-run learning -> monomorphic RX residual")
