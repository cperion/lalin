package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local jit = require("jit")
local Glob = require("experiments.cdef_schema.cps_glob")

local SIZE = tonumber(arg[1]) or 500000
local SAMPLES = tonumber(arg[2]) or 7
local MODE = arg[3] or "coarse"
local pattern = "ab*cd?ef*xyz"
local text = "ab" .. string.rep("q", SIZE) .. "cdZef" .. string.rep("r", SIZE) .. "xyz"
local folded_pattern = "AB*CD?EF*XYZ"
local sensitive = Glob.Sensitive()
local folded = Glob.AsciiFold()
local coarse_sensitive = Glob.CoarseSensitive()
local coarse_folded = Glob.CoarseAsciiFold()
local driven_sensitive = Glob.DrivenSensitive()
local NO_STAR = 0xffffffff

local function structured(pattern_owner, text_owner)
    local pattern_bytes = ffi.cast("const uint8_t *", pattern_owner)
    local text_bytes = ffi.cast("const uint8_t *", text_owner)
    local pattern_length, text_length = #pattern_owner, #text_owner
    local pattern_position, text_position = 0, 0
    local star_pattern, star_text = NO_STAR, 0

    while text_position < text_length do
        if pattern_position < pattern_length and pattern_bytes[pattern_position] == 42 then
            star_pattern = pattern_position
            pattern_position = pattern_position + 1
            star_text = text_position
        elseif pattern_position < pattern_length
            and (pattern_bytes[pattern_position] == 63
                or pattern_bytes[pattern_position] == text_bytes[text_position]) then
            pattern_position = pattern_position + 1
            text_position = text_position + 1
        elseif star_pattern ~= NO_STAR and star_text < text_length then
            star_text = star_text + 1
            text_position = star_text
            pattern_position = star_pattern + 1
        else
            return false
        end
    end

    while pattern_position < pattern_length and pattern_bytes[pattern_position] == 42 do
        pattern_position = pattern_position + 1
    end
    return pattern_position == pattern_length
end

local function fold_ascii(value)
    if value >= 65 and value <= 90 then return value + 32 end
    return value
end

local function structured_fold(pattern_owner, text_owner)
    local pattern_bytes = ffi.cast("const uint8_t *", pattern_owner)
    local text_bytes = ffi.cast("const uint8_t *", text_owner)
    local pattern_length, text_length = #pattern_owner, #text_owner
    local pattern_position, text_position = 0, 0
    local star_pattern, star_text = NO_STAR, 0

    while text_position < text_length do
        local pattern_value = pattern_position < pattern_length
            and pattern_bytes[pattern_position] or -1
        if pattern_value == 42 then
            star_pattern = pattern_position
            pattern_position = pattern_position + 1
            star_text = text_position
        elseif pattern_position < pattern_length
            and (pattern_value == 63
                or fold_ascii(pattern_value) == fold_ascii(text_bytes[text_position])) then
            pattern_position = pattern_position + 1
            text_position = text_position + 1
        elseif star_pattern ~= NO_STAR and star_text < text_length then
            star_text = star_text + 1
            text_position = star_text
            pattern_position = star_pattern + 1
        else
            return false
        end
    end

    while pattern_position < pattern_length and pattern_bytes[pattern_position] == 42 do
        pattern_position = pattern_position + 1
    end
    return pattern_position == pattern_length
end

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(name, operation)
    jit.flush()
    for _ = 1, 3 do assert(operation()) end
    local times = {}
    for sample = 1, SAMPLES do
        local t0 = os.clock()
        assert(operation())
        times[sample] = os.clock() - t0
    end
    local seconds = median(times)
    print(string.format("%-24s %8.3f ms %8.3f ns/byte",
        name, seconds * 1e3, seconds * 1e9 / #text))
end

print(string.format("%s %s/%s; bytes=%d samples=%d",
    jit.version, jit.arch, jit.os, #text, SAMPLES))
local operations = {
    structured = { "structured pointer", function() return structured(pattern, text) end },
    fine = { "fine sensitive CPS", function() return sensitive:match(pattern, text) end },
    coarse = { "coarse sensitive CPS", function() return coarse_sensitive:match(pattern, text) end },
    driven = { "for-driven sensitive", function() return driven_sensitive:match(pattern, text) end },
    structured_fold = {
        "structured ASCII fold", function() return structured_fold(folded_pattern, text) end,
    },
    fine_fold = {
        "fine ASCII-fold CPS", function() return folded:match(folded_pattern, text) end,
    },
    coarse_fold = {
        "coarse ASCII-fold CPS", function() return coarse_folded:match(folded_pattern, text) end,
    },
}
local selected = assert(operations[MODE], "unknown mode: " .. MODE)
measure(selected[1], selected[2])

