package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_fixture")
local Q = Native.quote_id

local main, consumed, total = Undump.undump(bytes)
assert(consumed == total and #main.protos == 1)
local proto = main.protos[1]
assert(proto.maxstacksize == 15 and #proto.upvals == 5 and #proto.code == 26)
assert(proto.code[1].name == "MOVE" and proto.code[2].sBx == 42)
assert(proto.code[3].name == "LOADF" and proto.code[3].sBx == 3)
assert(proto.code[4].name == "LOADK" and proto.k[1].t == "flt" and proto.k[1].v == 2.5)

local path = Projection.project(proto, 0, 24)
assert(getmetatable(path) == Projection.DecodedPath)
assert(#path.occurrences == 24 and path.start_pc == 0 and path.stop_pc == 24)

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_09_10/bank.lua"))
local program = path:new_program(24, bank)
local frame = program:new_frame()

local function close_integer_upvalue(index, register, value, generation)
    frame:set_integer(register, value)
    frame:open_upvalue(index, register, generation - 1):close_upvalue(index, generation)
end

close_integer_upvalue(0, 8, 0, 100)
close_integer_upvalue(1, 9, 0, 101)
frame:set_false(10):open_upvalue(2, 10, 101):close_upvalue(2, 102)
frame:set_true(11):open_upvalue(3, 11, 102):close_upvalue(3, 103)
frame:set_nil(12):open_upvalue(4, 12, 103):close_upvalue(4, 104)

local function assert_integer(index, value)
    assert(frame:tag(index) == bank.tags.integer)
    assert(frame:integer(index) == Native.ffi.new("int64_t", value))
end

local function assert_results(input)
    assert_integer(1, input)
    assert_integer(2, 42)
    assert(frame:tag(3) == bank.tags.floating and frame:floating(3) == 3.0)
    assert(frame:tag(4) == bank.tags.floating and frame:floating(4) == 2.5)
    assert(frame:tag(5) == bank.tags.false_value)
    assert(frame:tag(6) == bank.tags.true_value)
    assert(frame:tag(7) == bank.tags.nil_value)
    assert_integer(8, input)
    assert_integer(9, 42)
    assert(frame:tag(10) == bank.tags.floating and frame:floating(10) == 3.0)
    assert(frame:tag(11) == bank.tags.floating and frame:floating(11) == 2.5)
    assert(frame:tag(12) == bank.tags.false_value)
    assert(frame:tag(13) == bank.tags.true_value)
    assert(frame:tag(14) == bank.tags.nil_value)
end

frame:set_integer(0, 12)
assert(program:execute(frame) == bank.status.completed)
assert(program.recordings == 1 and frame.frame.resume_pc == 24)
assert_results(12)

local expected_quotes = {
    Q(0, 4), Q(1, 1), Q(2, 1), Q(3, 5), Q(5, 1), Q(7, 1), Q(8, 1),
    Q(10, 9), Q(9, 9), Q(10, 10), Q(9, 10), Q(10, 7), Q(9, 7),
    Q(10, 8), Q(9, 8), Q(10, 6), Q(9, 6),
    Q(0, 4), Q(0, 4), Q(0, 5), Q(0, 5), Q(0, 2), Q(0, 3), Q(0, 1),
}
assert(#expected_quotes == #path.occurrences)
for index = 1, #expected_quotes do
    assert(frame.slots[index - 1].quote == expected_quotes[index],
        ("quote mismatch at decoded pc %d"):format(index - 1))
end

frame:set_integer(0, -9)
assert(program:execute(frame) == bank.status.completed)
assert(program.recordings == 1)
assert_results(-9)

frame:set_float(0, 1.25):set_integer(1, 777)
assert(program:execute(frame) == bank.status.guard_failed)
assert(frame.frame.resume_pc == 0)
assert_integer(1, 777)

-- RETURN (70) is now a native terminal: the path [0, 25) projects with
-- the RETURN as its last occurrence.
local returned_path = Projection.project(proto, 0, 25)
assert(getmetatable(returned_path) == Projection.DecodedPath)
local last = returned_path.occurrences[#returned_path.occurrences]
assert(last.pc == 24 and last.learner_name == "return")

do
    local classes = Undump.OPCODE_CLASSES
    local constants = Undump.CONSTANT_CLASSES
    local synthetic = {
        maxstacksize = 1, upvals = {},
        k = { setmetatable({ t = "int", v = Native.ffi.new("int64_t", 7) }, constants.Integer) },
        code = {
            setmetatable({ name = "LOADKX", A = 0 }, classes[4]),
            setmetatable({ name = "EXTRAARG", Ax = 0 }, classes[84]),
        },
    }
    local projected = Projection.project(synthetic, 0, 2)
    assert(getmetatable(projected) == Projection.DecodedPath)
    assert(#projected.occurrences == 1)
end

do
    local classes = Undump.OPCODE_CLASSES
    local synthetic = {
        maxstacksize = 1, upvals = {}, k = {},
        code = {
            setmetatable({ name = "LFALSESKIP", A = 0 }, classes[6]),
            setmetatable({ name = "LOADTRUE", A = 0 }, classes[7]),
        },
    }
    local projected = Projection.project(synthetic, 0, 2)
    assert(getmetatable(projected) == Projection.DecodedPath)
    assert(#projected.occurrences == 1)
end

do
    local classes = Undump.OPCODE_CLASSES
    local malformed = {
        maxstacksize = 1, upvals = {}, k = {},
        code = {
            setmetatable({ name = "LOADKX", A = 0 }, classes[4]),
            setmetatable({ name = "LOADTRUE", A = 0 }, classes[7]),
        },
    }
    local rejected_loadkx = Projection.project(malformed, 0, 2)
    assert(Projection.ProjectionRejected:is(rejected_loadkx))
    assert(Projection.failures.MalformedLoadKX:is(rejected_loadkx.failure))

    local constants = Undump.CONSTANT_CLASSES
    local string_constant = {
        maxstacksize = 1, upvals = {},
        k = { setmetatable({ t = "str", v = "not rooted" }, constants.ShortString) },
        code = { setmetatable({ name = "LOADK", A = 0, Bx = 0 }, classes[3]) },
    }
    local rejected_string = Projection.project(string_constant, 0, 1)
    assert(Projection.ProjectionRejected:is(rejected_string))
    assert(Projection.failures.UnsupportedConstant:is(rejected_string.failure))
end

program:free()
print("Lua55 decoded opcodes 0-10: ok real Proto -> native learner -> guarded RX residual")
