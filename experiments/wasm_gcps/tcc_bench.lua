package.path = "./?.lua;./?/init.lua;" .. package.path

local Shapes = require("experiments.wasm_gcps.tcc_shapes")

local mode = arg[1] or "region_sum"
local calls = tonumber(arg[2]) or 5000
local trip_count = tonumber(arg[3]) or 1000
local samples = tonumber(arg[4]) or 7

local shapes = Shapes.new()
local operations = {
    opcode_sum = shapes.opcode_sum,
    opcode_mixed = shapes.opcode_mixed,
    step_sum = shapes.step_sum,
    step_mixed = shapes.step_mixed,
    region_sum = shapes.region_sum,
    region_mixed = shapes.region_mixed,
}
local operation = assert(operations[mode], "unknown mode: " .. tostring(mode))

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

jit.flush()
for _ = 1, 20 do operation(trip_count) end

local elapsed, checksum = {}, 0
for sample = 1, samples do
    local start = os.clock()
    local result = 0
    for _ = 1, calls do result = result + operation(trip_count) end
    elapsed[sample] = os.clock() - start
    checksum = result
end

local seconds = median(elapsed)
print(("LuaJIT %s TCC-FFI mode=%s calls=%d trip=%d samples=%d"):format(
    jit.version:match("%d.*"), mode, calls, trip_count, samples))
print(("%8.3f ms  %8.3f ns/iteration  %8.3f ns/public-call  checksum=%.1f"):format(
    seconds * 1000, seconds * 1e9 / (calls * trip_count),
    seconds * 1e9 / calls, checksum))

shapes:free()

