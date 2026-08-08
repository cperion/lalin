package.path = "./?.lua;./?/init.lua;" .. package.path

local calls = tonumber(arg[1]) or 200000
local trip_count = tonumber(arg[2]) or 1000
local samples = tonumber(arg[3]) or 7

local bank = dofile("target/copy_patch_cps/bank.lua")
local link_start = os.clock()
local program = bank:link()
local link_seconds = os.clock() - link_start
local frame = program:new_frame()
local expected = trip_count * (trip_count + 1) / 2

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

for _ = 1, 100 do program:execute(frame, trip_count) end
assert(tonumber(frame.result) == expected)

local elapsed = {}
local checksum
for sample = 1, samples do
    local start = os.clock()
    for _ = 1, calls do program:execute(frame, trip_count) end
    elapsed[sample] = os.clock() - start
    checksum = tonumber(frame.result) * calls
end

local seconds = median(elapsed)
local iterations = calls * trip_count
print(("copy-patch native CPS calls=%d trip=%d samples=%d bytes=%d link_us=%.3f"):format(
    calls, trip_count, samples, program.size, link_seconds * 1e6))
print(("%8.3f ms  %8.3f ns/iteration  checksum=%.1f"):format(
    seconds * 1000, seconds * 1e9 / iterations, checksum))
program:free()
