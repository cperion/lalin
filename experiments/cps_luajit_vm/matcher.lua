local byte = string.byte

local Matcher = {}
Matcher.__index = Matcher

function Matcher:loop(input, position, length, seen)
    if position + 1 < length then
        return self:pair(input, position, length, seen)
    end
    return self:done(input, position, length, seen)
end

function Matcher:pair(input, position, length, seen)
    local first, second = byte(input, position + 1, position + 2)
    if first == 97 and (second == 98 or second == 99) then
        return self:loop(input, position + 2, length, true)
    end
    return false
end

function Matcher:done(input, position, length, seen)
    return seen and position + 1 == length and byte(input, position + 1) == 100
end

function Matcher:match(input)
    return self:loop(input, 0, #input, false)
end

return setmetatable({}, Matcher)

