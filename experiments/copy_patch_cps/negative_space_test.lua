package.path = "./?.lua;./?/init.lua;" .. package.path
local L = require("experiments.copy_patch_cps.negative_space_linker")
local ffi = L.ffi
local bank = dofile("target/copy_patch_cps/negative_space/bank.lua")
local suite = bank:link()

do
    local input = ffi.new("double[19]")
    local expected = 0
    for index = 0, 18 do input[index] = index - 9; expected = expected + input[index] end
    local frame = ffi.new("F64ReductionV1Frame", { input, 19, 0 })
    suite:run_reduction(frame); assert(tonumber(frame.result) == expected)
end

do
    local input = ffi.new("uint8_t[70]")
    for index = 0, 69 do input[index] = index % 251 end
    input[47] = 255
    local frame = ffi.new("U8ScanV1Frame", { input, 70, 255, 0 })
    suite:run_scan(frame); assert(tonumber(frame.found) == 47)
    frame.needle = 254; suite:run_scan(frame); assert(tonumber(frame.found) == 70)
end

do
    local left, right = ffi.new("double[11]"), ffi.new("double[11]")
    local output = ffi.new("double[11]")
    for index = 0, 10 do left[index], right[index] = index, 10 - index end
    local frame = ffi.new("F64ZipMapV1Frame", { left, right, output, 11, 0.5 })
    suite:run_zip(frame)
    for index = 0, 10 do assert(output[index] == left[index] * 0.5 + right[index]) end
end

do
    local input, output = ffi.new("float[13]"), ffi.new("float[13]")
    for index = 0, 12 do input[index] = index / 8 end
    local frame = ffi.new("F32MapPipelineV1Frame", { input, output, 13, 1, 2, 3, 4 })
    suite:run_f32(frame)
    for index = 0, 12 do
        local value = tonumber(input[index]); value = (value + 1) * 2; value = (value + 3) * 4
        local expected = ffi.new("float", value * value)
        assert(output[index] == expected)
    end
end

local U64_2_32 = ffi.new("uint64_t", 4294967296)
local function u64(hex)
    local high = assert(tonumber(hex:sub(1, 8), 16))
    local low = assert(tonumber(hex:sub(9, 16), 16))
    return ffi.new("uint64_t", high) * U64_2_32 + low
end

do
    local inputs = {
        "0000000000000000", "0123456789abcdef", "ffffffffffffffff",
        "8000000000000000", "123456789abcdef0", "0000000000000000",
        "0123456789abcdef", "ffffffffffffffff", "8000000000000000",
    }
    local expected = {
        "0000000000002b00", "91a2b3c4d5e6d380", "0000000000002b80",
        "0000000000002b40", "1a2b3c4d5e6f5309", "0000000000002b00",
        "91a2b3c4d5e6d380", "0000000000002b80", "0000000000002b40",
    }
    local input, output = ffi.new("uint64_t[9]"), ffi.new("uint64_t[9]")
    for index = 0, 8 do input[index] = u64(inputs[index + 1]) end
    local frame = ffi.new("U64BulkV1Frame", { input, output, 9, 3, 0x55, 7 })
    suite:run_u64(frame)
    for index = 0, 8 do
        assert(output[index] == u64(expected[index + 1]))
    end
end

local bytes = suite.size
local released_frame = ffi.new("F64ReductionV1Frame")
suite:free()
local callable = pcall(function() suite:run_reduction(released_frame) end)
assert(not callable, "released negative-space suite remained callable")
print(("negative-space V1 suite: ok bytes=%d gcc=%s"):format(bytes, bank.gcc))
