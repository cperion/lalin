package.path = "./?.lua;./?/init.lua;" .. package.path

local Exotyped = require("experiments.lua55.cps_exotype_codegen")

local module_count = tonumber(arg[1]) or 20
local calls = tonumber(arg[2]) or 200
local trip_count = tonumber(arg[3]) or 1000
local samples = tonumber(arg[4]) or 5

local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local functions = {}
for module = 1, module_count do
    local main = Exotyped.loadfile(base .. "sample_5.5.luac")
    local sum, mixed = main()
    functions[#functions + 1] = sum
    functions[#functions + 1] = mixed
end

local function run()
    local checksum = 0
    for _ = 1, calls do
        for _, fn in ipairs(functions) do checksum = checksum + fn(trip_count) end
    end
    return checksum
end

for _ = 1, 10 do run() end
jit.flush()
for _ = 1, 20 do run() end

local elapsed, checksum = {}, 0
for sample = 1, samples do
    local start = os.clock()
    checksum = run()
    elapsed[sample] = os.clock() - start
end
table.sort(elapsed)
local seconds = elapsed[math.floor((#elapsed + 1) / 2)]
local iterations = calls * trip_count * #functions

print(("private exotype blocks modules=%d functions=%d calls=%d trip=%d samples=%d"):format(
    module_count, #functions, calls, trip_count, samples))
print(("%8.3f ms  %8.3f ns/guest-iteration  checksum=%.1f"):format(
    seconds * 1000, seconds * 1e9 / iterations, checksum))

