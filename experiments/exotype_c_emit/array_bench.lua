package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local Kernel = require("experiments.exotype_c_emit.array_kernel")
local Compiler = require("experiments.exotype_c_emit.array_compiler")
local now = require("lalin.luajit_measure").now

local count = tonumber(arg[1]) or 1000000
local repetitions = tonumber(arg[2]) or 100
local samples = tonumber(arg[3]) or 7

local Type = Kernel.type(Kernel.f64, {
    Kernel.multiply(1.5),
    Kernel.add_parameter(0),
    Kernel.square(),
    Kernel.multiply_parameter(1),
    Kernel.add(3.0),
})

local cook_started = now()
local program = Compiler.new():compile(Type)
local cook_seconds = now() - cook_started
local input = program:new_buffer(count)
local output = program:new_buffer(count)
local parameters = program:new_parameters()
parameters[0], parameters[1] = 2.25, 0.75
for index = 0, count - 1 do input[index] = index * 0.001 end

local run = program:entry()
for _ = 1, 10 do run(output, input, count, parameters) end

local times = {}
for sample = 1, samples do
    local started = now()
    for _ = 1, repetitions do run(output, input, count, parameters) end
    times[sample] = now() - started
end
table.sort(times)
local elapsed = times[math.floor((samples + 1) / 2)]
local elements = count * repetitions
local bytes = elements * program.abi.element_size * 2
local checksum = tonumber(output[0]) + tonumber(output[math.floor(count / 2)]) + tonumber(output[count - 1])

print(("fused-array-kernel count=%d repetitions=%d operations=%d"):format(
    count, repetitions, program.module.operation_count))
print(("cook_ms=%.3f ns_per_element=%.3f effective_gb_s=%.3f checksum=%.6f"):format(
    cook_seconds * 1000, elapsed * 1e9 / elements, bytes / elapsed / 1e9, checksum))
