local ffi = require("ffi")

ffi.cdef [[
typedef struct HandwrittenCpsPointerMatcher {
    const uint8_t *input;
    uint32_t length;
    uint32_t position;
    uint8_t seen;
} HandwrittenCpsPointerMatcher;
 ]]

local Methods = {}

function Methods:loop(owner)
    if self.position + 1 < self.length then
        return self:pair(owner)
    end
    return self:done(owner)
end

function Methods:pair(owner)
    local position = self.position
    local first = self.input[position]
    local second = self.input[position + 1]
    if first == 97 and (second == 98 or second == 99) then
        self.position = position + 2
        self.seen = 1
        return self:loop(owner)
    end
    return false
end

function Methods:done(owner)
    return self.seen ~= 0 and self.position + 1 == #owner
        and self.length == #owner and self.input[self.position] == 100
end

function Methods:match(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    self.length = #owner
    self.position = 0
    self.seen = 0
    local matched = self:loop(owner)
    self.input = nil
    return matched
end

return ffi.metatype("HandwrittenCpsPointerMatcher", { __index = Methods })

