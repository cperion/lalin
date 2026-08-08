package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local Compiler = require("experiments.exotyped_cps.compiler")
local C = require("experiments.exotyped_cps.constructors")

local iterations = tonumber(arg[1]) or 1000000
local compiler = Compiler.new()
local Pipeline = C.Pipeline {
    { kind = "add", value = 2 },
    { kind = "multiply", value = 3 },
    { kind = "add", value = 5 },
}
local program = compiler:compile(Pipeline, Pipeline.Run)
local run = program:entry()
local machine = program:new()

for _ = 1, 100 do run(machine, 1, 4) end
local started = os.clock()
local checksum = 0
for index = 1, iterations do
    run(machine, index, 4)
    checksum = checksum + tonumber(machine.value)
end
local elapsed = os.clock() - started

print(("exotyped-cps iterations=%d ns_per_run=%.3f operations=%d type_bytes=%d checksum=%.0f"):format(
    iterations, elapsed * 1e9 / iterations, #program.ordered,
    require("ffi").sizeof(machine), checksum))
