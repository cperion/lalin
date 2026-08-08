package.path = "./?.lua;./?/init.lua;" .. package.path

local Linker = require("experiments.copy_patch_cps.vector_linker")
local Pipeline = require("experiments.copy_patch_cps.vector_pipeline")
local ffi = Linker.ffi
local bank = dofile("target/copy_patch_cps/vector/vector_bank.lua")

local operations = {
    Pipeline.add(1.25),
    Pipeline.multiply(0.5),
    Pipeline.add_parameter(0),
    Pipeline.multiply_parameter(1),
    Pipeline.square(),
}

local program = Pipeline.compile(bank, operations)
assert(program.native.size < 512, "unexpectedly large F64MapPipelineV1 program")

local function close_enough(actual, expected)
    local scale = math.max(1, math.abs(expected))
    return math.abs(actual - expected) <= scale * 1e-12
end

for count = 0, 257 do
    local capacity = math.max(1, count)
    local input = ffi.new("double[?]", capacity)
    local output = ffi.new("double[?]", capacity)
    for index = 0, count - 1 do input[index] = index * 0.125 - 7 end

    local parameters = { 2.5, 1.75 }
    local frame = program:new_separate_frame(input, output, count, parameters)
    frame:execute()
    for index = 0, count - 1 do
        local expected = Pipeline.evaluate(operations, tonumber(input[index]), parameters)
        assert(close_enough(tonumber(output[index]), expected),
            ("separate result mismatch count=%d index=%d"):format(count, index))
    end
end

do
    local count = 259
    local values = ffi.new("double[?]", count)
    local original = {}
    for index = 0, count - 1 do
        values[index] = index / 11 - 3
        original[index + 1] = tonumber(values[index])
    end
    local parameters = { -0.25, 2.0 }
    local frame = program:new_in_place_frame(values, count, parameters)
    frame:execute()
    for index = 0, count - 1 do
        local expected = Pipeline.evaluate(operations, original[index + 1], parameters)
        assert(close_enough(tonumber(values[index]), expected),
            "in-place result mismatch at " .. index)
    end
end

do
    local square_program = Pipeline.compile(bank, { Pipeline.square() })
    local values = ffi.new("double[5]", { -2, -1, 0, 1, 2 })
    local frame = square_program:new_in_place_frame(values, 5)
    values = nil
    collectgarbage("collect")
    frame:execute()
    assert(tonumber(frame.state.output[0]) == 4)
    assert(tonumber(frame.state.output[4]) == 4)
    square_program:free()
end

do
    local too_many = pcall(function()
        Pipeline.compile(bank, {
            Pipeline.add(1), Pipeline.add(2), Pipeline.add(3),
            Pipeline.add(4), Pipeline.add(5),
        })
    end)
    assert(not too_many, "five scalar operands unexpectedly compiled")
end

do
    local storage = ffi.new("double[8]")
    local overlap = pcall(function()
        program:new_separate_frame(storage, storage + 1, 4, { 1, 1 })
    end)
    assert(not overlap, "partially overlapping ranges unexpectedly compiled")
end

do
    local values = ffi.new("double[17]")
    local recurring = program:new_in_place_frame(values, 17, { 1, 1 })
    for _ = 1, 100 do recurring:execute() end
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 10000 do recurring:execute() end
    local growth = collectgarbage("count") - before
    collectgarbage("restart")
    assert(growth < 4, ("recurring vector calls allocated %.3f KiB"):format(growth))
end

local values = ffi.new("double[1]", 1)
local frame = program:new_in_place_frame(values, 1, { 1, 1 })
local size = program.native.size
program:free()
local callable = pcall(function() frame:execute() end)
assert(not callable, "released vector program remained callable")

print(("F64MapPipelineV1: ok bytes=%d gcc=%s"):format(size, bank.gcc))
