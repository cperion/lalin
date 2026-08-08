package.path = "./?.lua;./?/init.lua;" .. package.path

local RuntimeSlot = require("experiments.copy_patch_cps.u64_runtime_slot")
local Learned = require("experiments.copy_patch_cps.u64_learned_loop_library")
local Negative = require("experiments.copy_patch_cps.negative_space_linker")
local ffi = Learned.ffi

ffi.cdef[[
typedef struct U64LearnedLoopFrame {
    const uint64_t *input; uint64_t *output; uint64_t count;
    uint64_t addend; uint64_t xor_value; uint64_t rotate;
} U64LearnedLoopFrame;
typedef void (*U64LearnedLoopEntry)(U64LearnedLoopFrame *);
]]

local bank = dofile("target/copy_patch_cps/u64_runtime/learned_loop_bank.lua")
local library = Learned.Library.new(bank)
local slot = RuntimeSlot.Slot.new(library.maximum)
local generic_bank = dofile("target/copy_patch_cps/negative_space/bank.lua")
local generic = generic_bank:link()

local input = ffi.new("uint64_t[19]")
for index = 0, 18 do
    input[index] = ffi.new("uint64_t", index * 0x10001) + index
end

local cases = {
    { 0, 0, 0 }, { 7, 0, 0 }, { 0, 0x55, 0 }, { 7, 0x55, 0 },
    { 0, 0, 1 }, { 7, 0, 17 }, { 0, 0x55, 31 }, { 7, 0x55, 63 },
}

local selections = 0
for index = 1, #cases do
    local facts = cases[index]
    for count = 16, 19 do
        local actual, expected = ffi.new("uint64_t[19]"), ffi.new("uint64_t[19]")
        local selected = library:select(facts[1], facts[2], facts[3], count % 4)
        slot:install(selected)
        local learned_frame = ffi.new("U64LearnedLoopFrame", {
            input, actual, count, facts[1], facts[2], facts[3],
        })
        local generic_frame = ffi.new("U64BulkV1Frame", {
            input, expected, count, facts[1], facts[2], facts[3],
        })
        slot.borrowed = true
        ffi.cast("U64LearnedLoopEntry", slot.memory)(learned_frame)
        slot.borrowed = false
        generic:run_u64(generic_frame)
        for element = 0, count - 1 do
            assert(actual[element] == expected[element],
                ("learned loop mismatch case=%d count=%d element=%d"):format(
                    index, count, element))
        end
        selections = selections + 1
    end
end

local capacity, generations = slot.capacity, slot.generation
generic:free(); slot:free()
print(("U64 learned loops: ok variants=%d capacity=%d generations=%d"):format(
    selections, capacity, generations))
