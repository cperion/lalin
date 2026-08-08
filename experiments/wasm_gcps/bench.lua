package.path = "./?.lua;./?/init.lua;" .. package.path

local Owner = require("experiments.wasm_gcps.cps_owner")

local mode = arg[1] or "owner_sum"
local calls = tonumber(arg[2]) or 5000
local trip_count = tonumber(arg[3]) or 1000
local samples = tonumber(arg[4]) or 7

local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local wasm_path = os.tmpname() .. ".wasm"
local status = os.execute(("wat2wasm %q -o %q"):format(base .. "sample.wat", wasm_path))
assert(status == true or status == 0, "wat2wasm failed")
local exports = Owner.loadfile(wasm_path)
os.remove(wasm_path)

local function native_sum(n)
    local result = 0
    for index = 1, n do result = result + index end
    return result
end

local function native_mixed(n)
    local result = 0.0
    for index = 1, n do result = result + index * 1.5 end
    return result
end

local operations = {
    owner_sum = exports.sum,
    owner_mixed = exports.mixed,
    native_sum = native_sum,
    native_mixed = native_mixed,
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
print(("LuaJIT %s mode=%s calls=%d trip=%d samples=%d"):format(
    jit.version:match("%d.*"), mode, calls, trip_count, samples))
print(("%8.3f ms  %8.3f ns/iteration  checksum=%.1f"):format(
    seconds * 1000, seconds * 1e9 / (calls * trip_count), checksum))

