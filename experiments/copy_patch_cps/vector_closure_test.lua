package.path = "./?.lua;./?/init.lua;" .. package.path

local Linker = require("experiments.copy_patch_cps.vector_linker")
local Pipeline = require("experiments.copy_patch_cps.vector_pipeline")
local ffi = Linker.ffi
local bank = dofile("target/copy_patch_cps/vector/vector_bank.lua")

local EmptyPipeline = {}
local AddAllSlots = {
    Pipeline.add(0.25),
    Pipeline.add(0.5),
    Pipeline.add(0.75),
    Pipeline.add(1.0),
}
local MultiplyAllSlots = {
    Pipeline.multiply(1.25),
    Pipeline.multiply(0.5),
    Pipeline.multiply(2.0),
    Pipeline.multiply(0.75),
}
local MixedAllSlots = {
    Pipeline.add_parameter(0),
    Pipeline.multiply_parameter(1),
    Pipeline.add(3.0),
    Pipeline.multiply(0.125),
    Pipeline.square(),
}
local SquareOnly = { Pipeline.square() }

local cases = {
    { operations = EmptyPipeline, parameters = {} },
    { operations = AddAllSlots, parameters = {} },
    { operations = MultiplyAllSlots, parameters = {} },
    { operations = MixedAllSlots, parameters = { -2.0, 1.5 } },
    { operations = SquareOnly, parameters = {} },
}

local function close_enough(actual, expected)
    return math.abs(actual - expected) <= math.max(1, math.abs(expected)) * 1e-12
end

for case_index = 1, #cases do
    local case = cases[case_index]
    local first = Pipeline.compile(bank, case.operations)
    local second = Pipeline.compile(bank, case.operations)
    assert(first.native:machine_code() == second.native:machine_code(),
        "machine projection is not deterministic for closure case " .. case_index)
    assert(first.native.size == second.native.size)

    for count = 0, 35 do
        local capacity = math.max(1, count)
        local input = ffi.new("double[?]", capacity)
        local output = ffi.new("double[?]", capacity)
        for index = 0, count - 1 do input[index] = (index - 11) * 0.0625 end
        local frame = first:new_separate_frame(input, output, count, case.parameters)
        frame:execute()
        for index = 0, count - 1 do
            local expected = Pipeline.evaluate(
                case.operations, tonumber(input[index]), case.parameters)
            assert(close_enough(tonumber(output[index]), expected),
                ("closure mismatch case=%d count=%d index=%d"):format(
                    case_index, count, index))
        end
    end

    first:free()
    second:free()
end

do
    local operations = {}
    for _ = 1, 64 do operations[#operations + 1] = Pipeline.square() end
    local maximum = Pipeline.compile(bank, operations)
    assert(maximum.native.size > 0)
    maximum:free()
    operations[#operations + 1] = Pipeline.square()
    local accepted = pcall(function() Pipeline.compile(bank, operations) end)
    assert(not accepted, "65-operation pipeline unexpectedly compiled")
end

print(("F64MapPipelineV1 closure: ok semantic_cases=%d physical_ops=9"):format(#cases))
