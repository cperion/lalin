package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local schema = require("cdefschema")

local S = schema.context {
    name = "prototype-isolation",
    version = 1,
    prefix = "PrototypeIsolationV1_",
}

S:cdef [[
typedef struct { int64_t current, limit, total; } PrototypeIsolationV1_SharedA;
typedef struct { int64_t current, limit, total; } PrototypeIsolationV1_SharedB;
typedef struct { int64_t current, limit, total; } PrototypeIsolationV1_OwnedA;
typedef struct { int64_t current, limit, total; } PrototypeIsolationV1_OwnedB;
 ]]

local Machine = S:sum("Machine")
local SharedA = Machine:leaf("PrototypeIsolationV1_SharedA")
local SharedB = Machine:leaf("PrototypeIsolationV1_SharedB")
local OwnedA = Machine:leaf("PrototypeIsolationV1_OwnedA")
local OwnedB = Machine:leaf("PrototypeIsolationV1_OwnedB")

function Machine:run(limit)
    self.current = 0
    self.limit = limit
    self.total = 0
    return self:cycle()
end

function Machine:cycle()
    if self.current < self.limit then
        self.total = self.total + self.current
        self.current = self.current + 1
        return self:cycle()
    end
    return self.total
end

function OwnedA:cycle()
    if self.current < self.limit then
        self.total = self.total + self.current
        self.current = self.current + 1
        return self:cycle()
    end
    return self.total
end

function OwnedB:cycle()
    if self.current < self.limit then
        self.total = self.total + self.current
        self.current = self.current + 1
        return self:cycle()
    end
    return self.total
end

S:seal()

local shared_a, shared_b = SharedA(), SharedB()
local owned_a, owned_b = OwnedA(), OwnedB()
local RUNS = tonumber(arg[1]) or 20000
local STEPS = tonumber(arg[2]) or 1000
local SAMPLES = tonumber(arg[3]) or 7
local expected = STEPS * (STEPS - 1) / 2

local function alternating(first, second, runs)
    local result
    for run = 1, runs do
        if run % 2 == 0 then result = first:run(STEPS) else result = second:run(STEPS) end
    end
    assert(tonumber(result) == expected)
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(name, operation)
    jit.flush()
    operation(100)
    local times = {}
    for sample = 1, SAMPLES do
        local t0 = os.clock()
        operation(RUNS)
        times[sample] = os.clock() - t0
    end
    local seconds = median(times)
    print(string.format("%-26s %8.3f ms %8.3f ns/step",
        name, seconds * 1e3, seconds * 1e9 / (RUNS * STEPS)))
end

print(string.format("%s %s/%s; runs=%d steps=%d samples=%d",
    jit.version, jit.arch, jit.os, RUNS, STEPS, SAMPLES))
measure("shared hot prototype", function(runs) alternating(shared_a, shared_b, runs) end)
measure("leaf-owned prototypes", function(runs) alternating(owned_a, owned_b, runs) end)

