package.path = "./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local NumberScanner = require("experiments.cps_luajit_vm.number_scanner")

local COUNT = tonumber(arg[1]) or 32768
local SAMPLES = tonumber(arg[2]) or 7
assert(COUNT <= NumberScanner.capacity)

local parts = {}
for i = 1, COUNT do parts[i] = tostring((i % 2001) - 1000) end
local input = table.concat(parts, ",")
local scanner = NumberScanner.Scanner()

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

jit.flush()
for _ = 1, 3 do assert(scanner:scan(input):is_ok()) end

local times = {}
local report
for sample = 1, SAMPLES do
    collectgarbage("collect")
    local t0 = os.clock()
    report = scanner:scan(input)
    times[sample] = os.clock() - t0
    assert(report:is_ok() and report:count() == COUNT)
end

local seconds = median(times)
print(string.format("%s %s/%s; bytes=%d values=%d samples=%d",
    jit.version, jit.arch, jit.os, #input, COUNT, SAMPLES))
print(string.format("handwritten FFI scanner  %8.3f ms %8.3f ns/byte",
    seconds * 1e3, seconds * 1e9 / #input))

