package.path = "./?.lua;./?/init.lua;" .. package.path

local Exotyped = require("experiments.lua55.cps_exotype_codegen")

local mode = arg[1] or "sum"
local calls = tonumber(arg[2]) or 20000
local trip_count = tonumber(arg[3]) or 1000
local samples = tonumber(arg[4]) or 7

local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local main = Exotyped.loadfile(base .. "sample_5.5.luac")
local sum, mixed = main()

local functions = { sum = sum, mixed = mixed }
local operation = assert(functions[mode], "unknown mode: " .. tostring(mode))

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

jit.flush()
for _ = 1, 20 do operation(trip_count) end

local elapsed = {}
local checksum
for sample = 1, samples do
    local start = os.clock()
    local result = 0
    for _ = 1, calls do result = result + operation(trip_count) end
    elapsed[sample] = os.clock() - start
    checksum = result
end

local seconds = median(elapsed)
local iterations = calls * trip_count
print(("LuaJIT %s mode=%s calls=%d trip=%d samples=%d"):format(
    jit.version:match("%d.*"), mode, calls, trip_count, samples))
print(("%8.3f ms  %8.3f ns/guest-iteration  checksum=%.1f"):format(
    seconds * 1000, seconds * 1e9 / iterations, checksum))

