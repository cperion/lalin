package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local jit = require("jit")
local Nested = require("experiments.cdef_schema.nested_machine")

local MODE = arg[1] or "nested1"
local STEPS = tonumber(arg[2]) or 2000000
local SAMPLES = tonumber(arg[3]) or 7

local constructors = {
    flat1 = Nested.Flat1,
    nested1 = Nested.Nested1,
    flat2 = Nested.Flat2,
    nested2 = Nested.Nested2,
    flat4 = Nested.Flat4,
    nested4 = Nested.Nested4,
    flat8 = Nested.Flat8,
    nested8 = Nested.Nested8,
    pointer1 = Nested.PointerRoot,
}

local constructor = assert(constructors[MODE], "unknown mode: " .. MODE)
local machine = constructor()
local pointer_owner
if MODE == "pointer1" then
    pointer_owner = Nested.PointerChild()
    machine.child = pointer_owner
end

local function operation(steps)
    local result = machine:run(steps)
    assert(tonumber(result) == steps)
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

jit.flush()
operation(2000)

collectgarbage()
collectgarbage()
collectgarbage("stop")
local heap_before = collectgarbage("count")
operation(STEPS)
local heap_growth = collectgarbage("count") - heap_before
collectgarbage("restart")
collectgarbage()

local times = {}
for sample = 1, SAMPLES do
    local t0 = os.clock()
    operation(STEPS)
    times[sample] = os.clock() - t0
end

local seconds = median(times)
print(string.format(
    "%s %-8s size=%d steps=%d  %8.3f ms  %8.3f ns/step  heap=%7.3f KB",
    jit.version, MODE, ffi.sizeof(machine), STEPS, seconds * 1e3,
    seconds * 1e9 / STEPS, heap_growth))

