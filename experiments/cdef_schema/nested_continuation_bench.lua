package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local jit = require("jit")
local Nested = require("experiments.cdef_schema.nested_machine")

local MODE = arg[1] or "shared"
local RUNS = tonumber(arg[2]) or 10000
local STEPS = tonumber(arg[3]) or 1000
local SAMPLES = tonumber(arg[4]) or 7

local first, second
if MODE == "shared" then
    first, second = Nested.SharedA(), Nested.SharedB()
elseif MODE == "owned" then
    first, second = Nested.OwnedA(), Nested.OwnedB()
else
    error("unknown mode: " .. MODE)
end

local function alternating(runs)
    local result
    for run = 1, runs do
        if run % 2 == 0 then
            result = first:run(STEPS)
        else
            result = second:run(STEPS)
        end
    end
    assert(tonumber(result) == STEPS)
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

jit.flush()
alternating(100)

collectgarbage()
collectgarbage()
collectgarbage("stop")
local heap_before = collectgarbage("count")
alternating(RUNS)
local heap_growth = collectgarbage("count") - heap_before
collectgarbage("restart")
collectgarbage()

local times = {}
for sample = 1, SAMPLES do
    local t0 = os.clock()
    alternating(RUNS)
    times[sample] = os.clock() - t0
end

local seconds = median(times)
local transitions = RUNS * STEPS
print(string.format(
    "%s %-6s size=%d runs=%d steps=%d  %8.3f ms  %8.3f ns/step  heap=%7.3f KB",
    jit.version, MODE, ffi.sizeof(first), RUNS, STEPS, seconds * 1e3,
    seconds * 1e9 / transitions, heap_growth))

