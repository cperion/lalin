package.path = "./?.lua;./?/init.lua;" .. package.path

local Learned = require("experiments.copy_patch_cps.u64_learned_loop_library")
local NativeLearner = require("experiments.copy_patch_cps.u64_native_learner")
local Negative = require("experiments.copy_patch_cps.negative_space_linker")
local ffi = Learned.ffi

local count = tonumber(arg[1]) or 1048576
local iterations = tonumber(arg[2]) or 100
local samples = tonumber(arg[3]) or 7
local loop_bank = dofile("target/copy_patch_cps/u64_runtime/learned_loop_bank.lua")
local library = Learned.Library.new(loop_bank)
local generic = dofile("target/copy_patch_cps/negative_space/bank.lua"):link()

local input = ffi.new("uint64_t[?]", count)
local learned_output = ffi.new("uint64_t[?]", count)
local generic_output = ffi.new("uint64_t[?]", count)
for index = 0, count - 1 do input[index] = index * 0x10001 + 7 end

local addend, xor_value, rotate = 3, 0x55, 17
local owner = NativeLearner.Owner.new(
    library, input, learned_output, count, addend, xor_value, rotate)
local generic_frame = ffi.new("U64BulkV1Frame", {
    input, generic_output, count, addend, xor_value, rotate,
})

local learn_start = os.clock()
owner:execute()
local learn_seconds = os.clock() - learn_start
generic:run_u64(generic_frame)
for index = 0, count - 1 do assert(learned_output[index] == generic_output[index]) end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end
local function measure(action)
    local values = {}
    for sample = 1, samples do
        local start = os.clock()
        for _ = 1, iterations do action() end
        values[sample] = os.clock() - start
    end
    return median(values)
end

local learned_entry = ffi.cast("U64LearnedLoopEntry", owner.slot.memory)
local learned_frame = owner.state.frame
local generic_entry = generic.u64
local learned_seconds = measure(function() learned_entry(learned_frame) end)
local generic_seconds = measure(function() generic_entry(generic_frame) end)
local elements = count * iterations

print(("U64 native learner count=%d iterations=%d samples=%d learn_us=%.3f slot=%d"):format(
    count, iterations, samples, learn_seconds * 1e6, owner.slot.capacity))
print(("learned immediate %8.3f ms %8.3f ns/element"):format(
    learned_seconds * 1000, learned_seconds * 1e9 / elements))
print(("generic variable   %8.3f ms %8.3f ns/element speedup=%.2fx"):format(
    generic_seconds * 1000, generic_seconds * 1e9 / elements,
    generic_seconds / learned_seconds))

owner:free(); generic:free()
