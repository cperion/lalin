package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local Csv = require("experiments.cdef_schema.cps_csv_scanner")

local COUNT = tonumber(arg[1]) or 32768
local SAMPLES = tonumber(arg[2]) or 7
assert(COUNT <= Csv.capacity)

local signed_parts, unsigned_parts = {}, {}
for index = 1, COUNT do
    signed_parts[index] = tostring((index % 2001) - 1000)
    unsigned_parts[index] = tostring(index % 1001)
end
local signed_input = table.concat(signed_parts, ",")
local unsigned_input = table.concat(unsigned_parts, ",")
local signed = Csv.Signed()
local unsigned = Csv.Unsigned()
local driven = Csv.ForDrivenSigned()

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(name, machine, input)
    jit.flush()
    for _ = 1, 3 do assert(machine:scan(input):is_ok()) end
    local times = {}
    for sample = 1, SAMPLES do
        local t0 = os.clock()
        local report = machine:scan(input)
        times[sample] = os.clock() - t0
        assert(report:is_ok() and report:count() == COUNT)
    end
    local seconds = median(times)
    print(string.format("%-24s %8.3f ms %8.3f ns/byte",
        name, seconds * 1e3, seconds * 1e9 / #input))
end

print(string.format("%s %s/%s; values=%d samples=%d",
    jit.version, jit.arch, jit.os, COUNT, SAMPLES))
measure("signed CPS machine", signed, signed_input)
measure("for-driven signed", driven, signed_input)
measure("unsigned CPS machine", unsigned, unsigned_input)

