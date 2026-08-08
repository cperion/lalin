package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local O = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
local extension = dofile("target/copy_patch_cps/lua55_trace/opcode_09_10/bank.lua")
O.extend_bank(bank, extension)
local Q = O.quote_id

local setters = {
    function(frame, index) frame:set_nil(index) end,
    function(frame, index) frame:set_false(index) end,
    function(frame, index) frame:set_true(index) end,
    function(frame, index) frame:set_integer(index, -123456789) end,
    function(frame, index) frame:set_float(index, 9.25) end,
}

local function assert_value(frame, index, tag)
    assert(frame:tag(index) == tag)
    if tag == bank.tags.integer then
        assert(frame:integer(index) == O.ffi.new("int64_t", -123456789))
    elseif tag == bank.tags.floating then
        assert(frame:floating(index) == 9.25)
    end
end

local function assert_upvalue(frame, index, tag)
    assert(frame:upvalue_tag(index) == tag)
    if tag == bank.tags.integer then
        assert(frame:upvalue_integer(index) == O.ffi.new("int64_t", -123456789))
    elseif tag == bank.tags.floating then
        assert(frame:upvalue_floating(index) == 9.25)
    end
end

for tag = 0, 4 do
    local program = O.Program.new({ O.GetUpvalueOccurrence.new(10, 1, 0) }, 2, 11, bank, nil, 1)
    local frame = program:new_frame()
    setters[tag + 1](frame, 0)
    frame:set_integer(1, 77):open_upvalue(0, 0, 19)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame.slots[0].quote == Q(9, tag + 1))
    assert(frame.slots[0].expected_tag == tag)
    assert(frame.slots[0].expected_state == extension.states.open)
    assert(frame.slots[0].expected_generation == 19)
    assert_value(frame, 1, tag)
    assert(program.learner:permissions():sub(1, 3) == "r-x")
    assert(program.residual:permissions():sub(1, 3) == "r-x")

    setters[tag + 1](frame, 0)
    frame:set_integer(1, 77)
    assert(program:execute(frame) == bank.status.completed)
    assert_value(frame, 1, tag)

    frame:close_upvalue(0, 20):set_integer(1, 77)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 10)
    assert(frame:tag(1) == bank.tags.integer and frame:integer(1) == 77)
    assert(program.recordings == 1)
    program:free()
end

for tag = 0, 4 do
    local program = O.Program.new({ O.GetUpvalueOccurrence.new(20, 1, 0) }, 2, 21, bank, nil, 1)
    local frame = program:new_frame()
    setters[tag + 1](frame, 0)
    frame:open_upvalue(0, 0, 4):close_upvalue(0, 5)
    frame:set_integer(0, 88):set_integer(1, 77)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame.slots[0].quote == Q(9, tag + 6))
    assert(frame.slots[0].expected_state == extension.states.closed)
    assert(frame.slots[0].expected_generation == 5)
    assert_value(frame, 1, tag)

    frame.upvalues[0].generation = 6
    frame:set_integer(1, 77)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 20)
    assert(frame:tag(1) == bank.tags.integer and frame:integer(1) == 77)
    program:free()
end

for tag = 0, 4 do
    local program = O.Program.new({ O.SetUpvalueOccurrence.new(30, 1, 0) }, 2, 31, bank, nil, 1)
    local frame = program:new_frame():set_integer(0, 88)
    frame:open_upvalue(0, 0, 31)
    setters[tag + 1](frame, 1)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame.slots[0].quote == Q(10, tag + 1))
    assert(frame.slots[0].expected_tag == tag)
    assert(frame.slots[0].expected_state == extension.states.open)
    assert_upvalue(frame, 0, tag)

    setters[tag + 1](frame, 1)
    assert(program:execute(frame) == bank.status.completed)
    assert_upvalue(frame, 0, tag)

    frame:set_integer(1, 17)
    if tag == bank.tags.integer then frame:set_float(1, 17) end
    local old_tag = frame:upvalue_tag(0)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 30 and frame:upvalue_tag(0) == old_tag)
    program:free()
end

for tag = 0, 4 do
    local program = O.Program.new({ O.SetUpvalueOccurrence.new(40, 1, 0) }, 2, 41, bank, nil, 1)
    local frame = program:new_frame():set_integer(0, 88)
    frame:open_upvalue(0, 0, 41):close_upvalue(0, 42)
    setters[tag + 1](frame, 1)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame.slots[0].quote == Q(10, tag + 6))
    assert(frame.slots[0].expected_state == extension.states.closed)
    assert(frame.slots[0].expected_generation == 42)
    assert_upvalue(frame, 0, tag)

    setters[tag + 1](frame, 1)
    assert(program:execute(frame) == bank.status.completed)
    assert_upvalue(frame, 0, tag)
    program:free()
end

do
    local occurrences = {
        O.LoadIOccurrence.new(50, 0, 7),
        O.SetUpvalueOccurrence.new(51, 0, 0),
        O.GetUpvalueOccurrence.new(52, 1, 0),
    }
    local program = O.Program.new(occurrences, 2, 53, bank, nil, 1)
    local frame = program:new_frame():set_integer(1, 0)
    frame:open_upvalue(0, 1, 71)
    assert(program:execute(frame) == bank.status.completed)
    local function assert_integer_seven()
        assert(frame:tag(0) == bank.tags.integer and frame:integer(0) == 7)
        assert(frame:tag(1) == bank.tags.integer and frame:integer(1) == 7)
        assert(frame:upvalue_tag(0) == bank.tags.integer and frame:upvalue_integer(0) == 7)
    end
    assert_integer_seven()
    assert(frame.slots[0].quote == Q(1, 1))
    assert(frame.slots[1].quote == Q(10, 4))
    assert(frame.slots[2].quote == Q(9, 4))

    for _ = 1, 100 do assert(program:execute(frame) == bank.status.completed) end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 10000 do assert(program:execute(frame) == bank.status.completed) end
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    assert(growth < 8, ("recurring upvalue calls allocated %.3f KiB"):format(growth))
    assert(program.recordings == 1)
    program:free()
end

do
    local program = O.Program.new({ O.GetUpvalueOccurrence.new(55, 1, 0) }, 2, 56, bank, nil, 1)
    local frame = program:new_frame():set_integer(0, 9):set_integer(1, 77)
    frame:open_upvalue(0, 0, 3)
    assert(program:execute(frame) == bank.status.completed)
    frame:set_float(0, 9):set_integer(1, 77)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 55)
    assert(frame:tag(1) == bank.tags.integer and frame:integer(1) == 77)
    program:free()
end

do
    local program = O.Program.new({ O.GetUpvalueOccurrence.new(60, 1, 0) }, 2, 61, bank, nil, 1)
    local frame = program:new_frame():set_integer(1, 0)
    frame.upvalues[0].state = 0
    assert(program:execute(frame) == bank.status.rejected)
    assert(frame.frame.resume_pc == 60)
    program:free()
end

do
    local program = O.Program.new({ O.SetUpvalueOccurrence.new(70, 1, 0) }, 2, 71, bank, nil, 1)
    local frame = program:new_frame():set_integer(0, 0)
    frame:open_upvalue(0, 0, 1)
    frame.values[1].tag = 5
    assert(program:execute(frame) == bank.status.rejected)
    assert(frame.frame.resume_pc == 70)
    program:free()
end

print("Lua55 opcodes 9-10: ok open/closed scalar upvalues -> guarded RX residual")
