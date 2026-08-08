package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local Pipeline = require("experiments.exotype_c_emit.pipeline")
local Compiler = require("experiments.exotype_c_emit.compiler")

local iterations = tonumber(arg[1]) or 1000000
local samples = tonumber(arg[2]) or 7
local Type = Pipeline.type {
    Pipeline.add(2),
    Pipeline.multiply(3),
    Pipeline.add(5),
}
local program = Compiler.new():compile(Type)
local run = program:entry()
local state = program:new()

for index = 1, 1000 do run(state, index, 4) end
local times, checksum = {}, 0
for sample = 1, samples do
    local started = os.clock()
    local result = 0
    for index = 1, iterations do
        run(state, index, 4)
        result = result + tonumber(state.value)
    end
    times[sample] = os.clock() - started
    checksum = result
end
table.sort(times)
local elapsed = times[math.floor((samples + 1) / 2)]

print(("exotype-c-emit iterations=%d ns_per_call=%.3f state_bytes=%d checksum=%.0f"):format(
    iterations, elapsed * 1e9 / iterations, program:sizeof(), checksum))
