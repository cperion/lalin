package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local jit = require("jit")
local Glob = require("experiments.cdef_schema.cps_glob")

local SIZE = tonumber(arg[1]) or 500000
local SAMPLES = tonumber(arg[2]) or 5
local NO_STAR = 0xffffffff
local machine = Glob.CoarseSensitive()
local driven = Glob.DrivenSensitive()

local function structured(pattern_owner, text_owner)
    local pattern = ffi.cast("const uint8_t *", pattern_owner)
    local text = ffi.cast("const uint8_t *", text_owner)
    local pattern_length, text_length = #pattern_owner, #text_owner
    local p, t, star_p, star_t = 0, 0, NO_STAR, 0
    while t < text_length do
        if p < pattern_length and pattern[p] == 42 then
            star_p, p, star_t = p, p + 1, t
        elseif p < pattern_length and (pattern[p] == 63 or pattern[p] == text[t]) then
            p, t = p + 1, t + 1
        elseif star_p ~= NO_STAR and star_t < text_length then
            star_t, t, p = star_t + 1, star_t + 1, star_p + 1
        else
            return false
        end
    end
    while p < pattern_length and pattern[p] == 42 do p = p + 1 end
    return p == pattern_length
end

local cases = {
    { "literal", string.rep("a", SIZE) .. "b", string.rep("a", SIZE) .. "b", true },
    { "question", string.rep("?", SIZE), string.rep("a", SIZE), true },
    { "one star", "a*z", "a" .. string.rep("q", SIZE) .. "z", true },
    { "two stars", "a*b*c", "a" .. string.rep("q", SIZE) .. "b"
        .. string.rep("r", SIZE) .. "c", true },
    { "late reject", "a*z", "a" .. string.rep("q", SIZE) .. "y", false },
}

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(operation, pattern, text, expected)
    jit.flush()
    for _ = 1, 3 do assert(operation(pattern, text) == expected) end
    local times = {}
    for sample = 1, SAMPLES do
        local t0 = os.clock()
        assert(operation(pattern, text) == expected)
        times[sample] = os.clock() - t0
    end
    return median(times) * 1e9 / #text
end

print(string.format("%s %s/%s; base=%d samples=%d",
    jit.version, jit.arch, jit.os, SIZE, SAMPLES))
print(string.format("%-14s %12s %12s %12s",
    "shape", "structured", "coarse CPS", "for-driven"))
for _, case in ipairs(cases) do
    local structured_ns = measure(structured, case[2], case[3], case[4])
    local cps_ns = measure(function(pattern, text) return machine:match(pattern, text) end,
        case[2], case[3], case[4])
    local driven_ns = measure(function(pattern, text) return driven:match(pattern, text) end,
        case[2], case[3], case[4])
    print(string.format("%-14s %9.3f ns %9.3f ns %9.3f ns",
        case[1], structured_ns, cps_ns, driven_ns))
end

