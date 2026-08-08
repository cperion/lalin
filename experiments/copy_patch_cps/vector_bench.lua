package.path = "./?.lua;./?/init.lua;" .. package.path

local Linker = require("experiments.copy_patch_cps.vector_linker")
local Pipeline = require("experiments.copy_patch_cps.vector_pipeline")
local ffi = Linker.ffi
local bank = dofile("target/copy_patch_cps/vector/vector_bank.lua")

local count = tonumber(arg[1]) or 1048576
local iterations = tonumber(arg[2]) or 200
local samples = tonumber(arg[3]) or 7

local operations = {
    Pipeline.add(1.25),
    Pipeline.multiply(0.5),
    Pipeline.add_parameter(0),
    Pipeline.multiply_parameter(1),
    Pipeline.square(),
}
local parameters = { 2.5, 1.75 }

local input = ffi.new("double[?]", count)
local native_output = ffi.new("double[?]", count)
local lua_output = ffi.new("double[?]", count)
for index = 0, count - 1 do input[index] = index % 1024 * 0.001 - 0.5 end

local link_start = os.clock()
local program = Pipeline.compile(bank, operations)
local cold_link_seconds = os.clock() - link_start
local warm_link_start = os.clock()
local warm_program = Pipeline.compile(bank, operations)
local warm_link_seconds = os.clock() - warm_link_start
warm_program:free()
local frame = program:new_separate_frame(input, native_output, count, parameters)

local function lua_kernel()
    for index = 0, count - 1 do
        local value = input[index]
        value = value + 1.25
        value = value * 0.5
        value = value + parameters[1]
        value = value * parameters[2]
        value = value * value
        lua_output[index] = value
    end
end

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

for _ = 1, 10 do frame:execute(); lua_kernel() end
local native_seconds = measure(function() frame:execute() end)
local lua_seconds = measure(lua_kernel)

for index = 0, count - 1 do
    local actual = tonumber(native_output[index])
    local expected = tonumber(lua_output[index])
    assert(math.abs(actual - expected) <= math.max(1, math.abs(expected)) * 1e-12,
        "benchmark result mismatch at " .. index)
end

local elements = count * iterations
print(("F64MapPipelineV1 count=%d iterations=%d samples=%d bytes=%d cold_link_us=%.3f warm_link_us=%.3f"):format(
    count, iterations, samples, program.native.size,
    cold_link_seconds * 1e6, warm_link_seconds * 1e6))
print(("native AVX2  %8.3f ms  %8.3f ns/element"):format(
    native_seconds * 1000, native_seconds * 1e9 / elements))
print(("LuaJIT scalar %8.3f ms  %8.3f ns/element  speedup=%.2fx"):format(
    lua_seconds * 1000, lua_seconds * 1e9 / elements, lua_seconds / native_seconds))
program:free()
