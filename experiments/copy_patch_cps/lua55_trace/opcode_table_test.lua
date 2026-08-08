package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local TableOps = require("experiments.copy_patch_cps.lua55_trace.opcode_table")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_table_fixture")
local Q = Native.quote_id

local main = Undump.undump(bytes)
local proto = assert(main.protos[1])
assert(proto.code[1].name == "GETI" and proto.code[2].name == "GETFIELD")
assert(proto.code[3].name == "SETI" and proto.code[4].name == "SETFIELD")

local no_heap = Projection.project(proto, 1, 2)
assert(Projection.ProjectionRejected:is(no_heap))
assert(Projection.failures.UnsupportedConstant:is(no_heap.failure))

local heap = Heap.GuestHeap.new(23)
local field_key = heap:short_string("field")
local other_key = heap:short_string("other")
proto.code[3].k = 1
-- RK constant values are now resolved into the occurrence (V2 supports
-- constant-value table writes natively)
local constant_write = Projection.project(proto, 2, 3, heap)
assert(getmetatable(constant_write) == Projection.DecodedPath,
    "SETI with a constant value must project to a native occurrence")
assert(#constant_write.occurrences == 1)
assert(constant_write.occurrences[1].const_value ~= nil,
    "SETI constant value facts are attached to the occurrence")
proto.code[3].k = 0
local table_owner = heap:table(2, 2)
table_owner:set_array_integer(1, 41)
table_owner:set_field_integer(field_key, 52)

local path = Projection.project(proto, 0, 6, heap)
assert(getmetatable(path) == Projection.DecodedPath and #path.occurrences == 6)
local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_table/bank.lua"))
local program = path:new_program(6, bank)
local frame = program:new_frame():set_table(0, table_owner):set_integer(1, 99)

assert(program:execute(frame) == bank.status.completed)
assert(program.recordings == 1)
assert(frame:tag(2) == bank.tags.integer and frame:integer(2) == 41)
assert(frame:tag(3) == bank.tags.integer and frame:integer(3) == 52)
assert(frame:integer(4) == 41 and frame:integer(5) == 52)
assert(table_owner:array_value(2).payload.integer == 99)
assert(table_owner:field_value(other_key, false).payload.integer == 99)

local expected_quotes = { Q(13, 4), Q(14, 5), Q(17, 4), Q(18, 4), Q(0, 4), Q(0, 4) }
for index = 1, #expected_quotes do assert(frame.slots[index - 1].quote == expected_quotes[index]) end

frame:set_integer(1, 100)
assert(program:execute(frame) == bank.status.completed)
assert(table_owner:array_value(2).payload.integer == 100)
assert(table_owner:field_value(other_key, false).payload.integer == 100)

for _ = 1, 1000 do assert(program:execute(frame) == bank.status.completed) end
collectgarbage("collect")
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, 10000 do assert(program:execute(frame) == bank.status.completed) end
local growth = collectgarbage("count") - before
collectgarbage("restart")
assert(growth < 8, ("recurring table residual calls allocated %.3f KiB"):format(growth))

frame:set_float(1, 3.5)
assert(program:execute(frame) == bank.status.guard_failed)
assert(frame.frame.resume_pc == 2)
assert(table_owner:array_value(2).payload.integer == 100)
assert(table_owner:field_value(other_key, false).payload.integer == 100)

local alien = heap:table(2, 2):set_array_integer(1, 41):set_field_integer(field_key, 52)
frame:set_table(0, alien):set_integer(1, 101)
assert(program:execute(frame) == bank.status.guard_failed and frame.frame.resume_pc == 0)
frame:set_table(0, table_owner)

heap:advance_collection_epoch()
assert(program:execute(frame) == bank.status.guard_failed and frame.frame.resume_pc == 0)

local metatable_owner = heap:table(0, 0)
local metatable_table = heap:table(1, 0):set_array_integer(1, 1):set_metatable(metatable_owner)
local metatable_program = Native.Program.new({
    TableOps.GetIOccurrence.new(25, 0, 1, 1),
}, 2, 26, bank, nil, 0, heap)
local metatable_frame = metatable_program:new_frame():set_nil(0):set_table(1, metatable_table)
assert(metatable_program:execute(metatable_frame) == bank.status.rejected)
assert(metatable_frame.frame.resume_pc == 25 and metatable_program.recordings == 0)

local missing_table = heap:table(0, 1)
local missing_program = Native.Program.new({
    TableOps.GetFieldOccurrence.new(30, 0, 1, field_key),
}, 2, 31, bank, nil, 0, heap)
local missing_frame = missing_program:new_frame():set_nil(0):set_table(1, missing_table)
assert(missing_program:execute(missing_frame) == bank.status.completed)
assert(missing_frame:tag(0) == bank.tags.nil_value)
assert(missing_frame.slots[0].quote == Q(14, 1))
missing_table:set_field_integer(field_key, 7)
assert(missing_program:execute(missing_frame) == bank.status.guard_failed)
assert(missing_frame.frame.resume_pc == 30)

local barrier_table = heap:table(1, 0)
local barrier_program = Native.Program.new({
    TableOps.SetIOccurrence.new(40, 0, 1, 1),
}, 2, 41, bank, nil, 0, heap)
local barrier_frame = barrier_program:new_frame()
    :set_table(0, barrier_table):set_short_string(1, field_key)
local barrier_before = tonumber(heap.heap[0].barrier_epoch)
assert(barrier_program:execute(barrier_frame) == bank.status.completed)
assert(barrier_table:barrier_count() == 1)
assert(tonumber(heap.heap[0].barrier_epoch) == barrier_before + 1)
assert(barrier_program:execute(barrier_frame) == bank.status.completed)
assert(barrier_table:barrier_count() == 2)
assert(tonumber(heap.heap[0].barrier_epoch) == barrier_before + 2)

metatable_program:free()
barrier_program:free()
missing_program:free()
program:free()
assert(heap.artifact_count == 0)
heap:free()

print("Lua55 tables: ok GETI/GETFIELD/SETI/SETFIELD -> guarded fixed-storage RX residuals")
