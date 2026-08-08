package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Tree = require("experiments.cdef_schema.concern_tree")

local mode = arg[1] or "update"
local transitions = tonumber(arg[2]) or 10000000
local samples = tonumber(arg[3]) or 7

local app = Tree.App()
app:initialize(0, 100, 50, 100)

local function update_pair(machine)
    machine:increment()
    return machine:decrement()
end

local resize_width = 100
local function resize_once(machine)
    resize_width = resize_width == 100 and 101 or 100
    return machine:resize(resize_width)
end

local bounded = Tree.App()
bounded:initialize(50, 50, 50, 100)
local function ignored_once(machine) return machine:increment() end

local operation, machine, operations_per_call
if mode == "update" then operation, machine, operations_per_call = update_pair, app, 2
elseif mode == "resize" then operation, machine, operations_per_call = resize_once, app, 1
elseif mode == "ignored" then operation, machine, operations_per_call = ignored_once, bounded, 1
else error("unknown mode: " .. tostring(mode)) end

local calls = math.floor(transitions / operations_per_call)
local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

jit.flush()
for _ = 1, 100 do operation(machine) end

local elapsed, checksum = {}, 0
for sample = 1, samples do
    local start = os.clock()
    local result = 0
    for _ = 1, calls do result = result + operation(machine) end
    elapsed[sample] = os.clock() - start
    checksum = result
end

local seconds = median(elapsed)
local measured_transitions = calls * operations_per_call
print(("LuaJIT %s concern-tree mode=%s transitions=%d samples=%d"):format(
    jit.version:match("%d.*"), mode, measured_transitions, samples))
print(("%8.3f ms  %8.3f ns/transition  checksum=%.1f"):format(
    seconds * 1000, seconds * 1e9 / measured_transitions, checksum))

