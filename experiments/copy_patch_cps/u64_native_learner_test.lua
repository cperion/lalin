package.path = "./?.lua;./?/init.lua;" .. package.path

local Learned = require("experiments.copy_patch_cps.u64_learned_loop_library")
local NativeLearner = require("experiments.copy_patch_cps.u64_native_learner")
local Negative = require("experiments.copy_patch_cps.negative_space_linker")
local ffi = Learned.ffi

local loop_bank = dofile("target/copy_patch_cps/u64_runtime/learned_loop_bank.lua")
local library = Learned.Library.new(loop_bank)
local generic_bank = dofile("target/copy_patch_cps/negative_space/bank.lua")
local generic = generic_bank:link()

local cases = {
    { 0, 0, 0 }, { 3, 0, 0 }, { 0, 0x55, 0 }, { 3, 0x55, 0 },
    { 0, 0, 1 }, { 3, 0, 17 }, { 0, 0x55, 31 }, { 3, 0x55, 63 },
}

for case_index = 1, #cases do
    local facts = cases[case_index]
    local count = 19 + case_index
    local input = ffi.new("uint64_t[27]")
    local actual, expected = ffi.new("uint64_t[27]"), ffi.new("uint64_t[27]")
    for index = 0, count - 1 do input[index] = index * 0x1000001 + case_index end

    local owner = NativeLearner.Owner.new(
        library, input, actual, count, facts[1], facts[2], facts[3])
    local reference = ffi.new("U64BulkV1Frame", {
        input, expected, count, facts[1], facts[2], facts[3],
    })

    assert(owner.state.generation == 0 and owner.slot.generation == 0)
    owner:execute()
    assert(owner.state.generation == 1 and owner.slot.generation == 1)
    assert(owner.slot:permissions():sub(1, 3) == "r-x")
    generic:run_u64(reference)
    for index = 0, count - 1 do assert(actual[index] == expected[index]) end

    ffi.fill(actual, ffi.sizeof(actual), 0)
    owner:execute()
    assert(owner.state.generation == 1 and owner.slot.generation == 1,
        "specialized recurrence reinstalled on recurring execution")
    for index = 0, count - 1 do assert(actual[index] == expected[index]) end
    owner:free()
end

generic:free()
print("U64 native one-shot learner: ok operation_variants=8 remainder_variants=4 reinstall=false W^X=true")
