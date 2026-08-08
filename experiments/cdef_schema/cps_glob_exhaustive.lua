package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Glob = require("experiments.cdef_schema.cps_glob")

local function strings(alphabet, maximum)
    local result = { "" }
    local frontier = { "" }
    for _ = 1, maximum do
        local next_frontier = {}
        for _, prefix in ipairs(frontier) do
            for _, symbol in ipairs(alphabet) do
                local value = prefix .. symbol
                result[#result + 1] = value
                next_frontier[#next_frontier + 1] = value
            end
        end
        frontier = next_frontier
    end
    return result
end

local function fold(value) return value:lower() end

local function oracle(pattern, text, folded)
    local memo = {}
    local function visit(pattern_position, text_position)
        local key = pattern_position * (#text + 1) + text_position
        if memo[key] ~= nil then return memo[key] end
        local answer
        if pattern_position > #pattern then
            answer = text_position > #text
        else
            local symbol = pattern:sub(pattern_position, pattern_position)
            if symbol == "*" then
                answer = visit(pattern_position + 1, text_position)
                    or (text_position <= #text and visit(pattern_position, text_position + 1))
            elseif text_position > #text then
                answer = false
            else
                local value = text:sub(text_position, text_position)
                answer = symbol == "?"
                    or (folded and fold(symbol) == fold(value))
                    or (not folded and symbol == value)
                answer = answer and visit(pattern_position + 1, text_position + 1)
            end
        end
        memo[key] = answer
        return answer
    end
    return visit(1, 1)
end

local sensitive = Glob.Sensitive()
local coarse_sensitive = Glob.CoarseSensitive()
local driven_sensitive = Glob.DrivenSensitive()
local patterns = strings({ "a", "b", "*", "?" }, 5)
local texts = strings({ "a", "b" }, 6)
local checked = 0

for _, pattern in ipairs(patterns) do
    for _, text in ipairs(texts) do
        local expected = oracle(pattern, text, false)
        assert(sensitive:match(pattern, text) == expected, "fine mismatch: " .. pattern .. "/" .. text)
        assert(coarse_sensitive:match(pattern, text) == expected,
            "coarse mismatch: " .. pattern .. "/" .. text)
        assert(driven_sensitive:match(pattern, text) == expected,
            "driven mismatch: " .. pattern .. "/" .. text)
        checked = checked + 1
    end
end

local folded = Glob.AsciiFold()
local coarse_folded = Glob.CoarseAsciiFold()
local folded_patterns = strings({ "a", "B", "*", "?" }, 4)
local folded_texts = strings({ "a", "b", "A", "B" }, 4)

for _, pattern in ipairs(folded_patterns) do
    for _, text in ipairs(folded_texts) do
        local expected = oracle(pattern, text, true)
        assert(folded:match(pattern, text) == expected, "fine fold mismatch: " .. pattern .. "/" .. text)
        assert(coarse_folded:match(pattern, text) == expected,
            "coarse fold mismatch: " .. pattern .. "/" .. text)
        checked = checked + 1
    end
end

print(string.format("cdef CPS glob exhaustive: ok (%d pairs)", checked))

