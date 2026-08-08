package.path = "./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local byte = string.byte
local string_matcher = require("experiments.cps_luajit_vm.matcher")
local PointerMatcher = require("experiments.cps_luajit_vm.pointer_matcher")

local PAIRS = tonumber(arg[1]) or 500000
local SAMPLES = tonumber(arg[2]) or 5
local input = string.rep("ab", PAIRS) .. "d"
local pointer_matcher = PointerMatcher()

local function structured(value)
    local position = 0
    local length = #value
    local seen = false
    while position + 1 < length do
        local first, second = byte(value, position + 1, position + 2)
        if first ~= 97 or (second ~= 98 and second ~= 99) then break end
        position = position + 2
        seen = true
    end
    return seen and position + 1 == length and byte(value, position + 1) == 100
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(name, operation)
    jit.flush()
    for _ = 1, 3 do assert(operation()) end
    local values = {}
    for sample = 1, SAMPLES do
        collectgarbage("collect")
        local t0 = os.clock()
        assert(operation())
        values[sample] = os.clock() - t0
    end
    local seconds = median(values)
    print(string.format("%-24s %8.3f ms %8.3f ns/byte",
        name, seconds * 1e3, seconds * 1e9 / #input))
end

print(string.format("%s %s/%s; bytes=%d samples=%d",
    jit.version, jit.arch, jit.os, #input, SAMPLES))
measure("structured string", function() return structured(input) end)
measure("method string.byte", function() return string_matcher:match(input) end)
measure("FFI pointer self", function() return pointer_matcher:match(input) end)

