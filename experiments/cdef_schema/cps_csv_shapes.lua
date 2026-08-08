package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local Csv = require("experiments.cdef_schema.cps_csv_scanner")

local COUNT = tonumber(arg[1]) or 20000
local SAMPLES = tonumber(arg[2]) or 5
local SHAPE = tonumber(arg[3]) or 1
assert(COUNT <= Csv.capacity)
local tail = Csv.Signed()
local driven = Csv.ForDrivenSigned()

local function repeated(value)
    local parts = {}
    for index = 1, COUNT do parts[index] = value end
    return table.concat(parts, ",")
end

local cases = {
    { "one digit", repeated("1") },
    { "six chars", repeated("-12345") },
    { "18 digits", repeated("123456789012345678") },
    { "whitespace", repeated("   12345   ") },
}

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(machine, input)
    jit.flush()
    for _ = 1, 3 do assert(machine:scan(input):count() == COUNT) end
    local times = {}
    for sample = 1, SAMPLES do
        local t0 = os.clock()
        assert(machine:scan(input):count() == COUNT)
        times[sample] = os.clock() - t0
    end
    return median(times) * 1e9 / #input
end

print(string.format("%s %s/%s; values=%d samples=%d",
    jit.version, jit.arch, jit.os, COUNT, SAMPLES))
print(string.format("%-12s %12s %12s", "shape", "tail CPS", "for-driven"))
local case = assert(cases[SHAPE], "shape must be 1..4")
local tail_ns = measure(tail, case[2])
local driven_ns = measure(driven, case[2])
print(string.format("%-12s %9.3f ns %9.3f ns", case[1], tail_ns, driven_ns))

