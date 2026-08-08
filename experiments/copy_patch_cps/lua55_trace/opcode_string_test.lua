package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_string_fixture")
local Q = Native.quote_id

local main = Undump.undump(bytes)
local proto = assert(main.protos[1])
assert(#proto.k == 2 and proto.k[1].t == "str" and proto.k[2].t == "str")
assert(getmetatable(proto.k[1]) == Undump.CONSTANT_CLASSES.ShortString)
assert(getmetatable(proto.k[2]) == Undump.CONSTANT_CLASSES.LongString)

local rejected = Projection.project(proto, 0, 6)
assert(Projection.ProjectionRejected:is(rejected))
assert(Projection.failures.UnsupportedConstant:is(rejected.failure))

local heap = Heap.GuestHeap.new(17)
local path = Projection.project(proto, 0, 6, heap)
assert(getmetatable(path) == Projection.DecodedPath and #path.occurrences == 6)

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_string/bank.lua"))
local program = path:new_program(6, bank)
local frame = program:new_frame()
assert(frame.heap_owner == heap and frame.frame.heap == heap.heap)

assert(program:execute(frame) == bank.status.completed)
assert(program.recordings == 1 and heap.artifact_count == 1)
local short = heap:short_string("field")
local long = heap:long_string(
    "this string is deliberately longer than forty bytes for Lua 5.5")
assert(heap:short_string("field") == short)
assert(heap:long_string(long:bytes()) == long)
assert(short:length() == 5 and long:length() > 40)

local expected_tags = {
    bank.tags.short_string, bank.tags.long_string,
    bank.tags.short_string, bank.tags.long_string,
    bank.tags.short_string, bank.tags.long_string,
}
local expected_references = {
    short:reference(), long:reference(), short:reference(),
    long:reference(), short:reference(), long:reference(),
}
for index = 0, 5 do
    assert(frame:tag(index) == expected_tags[index + 1])
    assert(frame:reference(index) == expected_references[index + 1])
end

local expected_quotes = {
    Q(3, 6), Q(3, 7), Q(0, 6), Q(0, 7), Q(0, 6), Q(0, 7),
}
for index = 1, #expected_quotes do
    assert(frame.slots[index - 1].quote == expected_quotes[index])
end

heap:advance_collection_epoch()
assert(program:execute(frame) == bank.status.completed)
for index = 0, 5 do
    assert(frame:reference(index) == expected_references[index + 1])
end

local free_ok, free_message = pcall(function() heap:free() end)
assert(not free_ok and free_message:match("RX artifacts"))

local move_program = Native.Program.new(
    { Native.MoveOccurrence.new(20, 1, 0) }, 2, 21, bank, nil, 0, heap)
local move_frame = move_program:new_frame():set_short_string(0, short):set_nil(1)
assert(move_program:execute(move_frame) == bank.status.completed)
assert(move_frame:tag(1) == bank.tags.short_string)
assert(move_frame:reference(1) == short:reference())
move_frame:set_long_string(0, long):set_nil(1)
assert(move_program:execute(move_frame) == bank.status.guard_failed)
assert(move_frame.frame.resume_pc == 20 and move_frame:tag(1) == bank.tags.nil_value)

move_program:free()
program:free()
assert(heap.artifact_count == 0)
heap:free()
local owner_ok, owner_message = pcall(function() short:reference() end)
assert(not owner_ok and owner_message:match("released"))

print("Lua55 strings: ok rooted guest heap -> LOADK/LOADKX/MOVE RX residuals")
