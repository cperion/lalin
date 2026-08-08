package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local jit = require("jit")
local byte = string.byte

local PAIRS = tonumber(arg[1]) or 500000
local SAMPLES = tonumber(arg[2]) or 5
local input = string.rep("ab", PAIRS) .. "d"

local function final_match(value, position, length, seen)
    return seen and position + 1 == length and byte(value, position + 1) == 100
end

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
    return final_match(value, position, length, seen)
end

local LexicalLoop, LexicalPair, LexicalDone
LexicalLoop = function(self, value, position, length, seen)
    if position + 1 < length then
        return LexicalPair(self, value, position, length, seen)
    end
    return LexicalDone(self, value, position, length, seen)
end
LexicalPair = function(self, value, position, length, seen)
    local first, second = byte(value, position + 1, position + 2)
    if first == 97 and (second == 98 or second == 99) then
        return LexicalLoop(self, value, position + 2, length, true)
    end
    return false
end
LexicalDone = function(_self, value, position, length, seen)
    return final_match(value, position, length, seen)
end
local Lexical = {}
function Lexical:match(value) return LexicalLoop(self, value, 0, #value, false) end

local Colon = {}
Colon.__index = Colon
function Colon:loop(value, position, length, seen)
    if position + 1 < length then return self:pair(value, position, length, seen) end
    return self:done(value, position, length, seen)
end
function Colon:pair(value, position, length, seen)
    local first, second = byte(value, position + 1, position + 2)
    if first == 97 and (second == 98 or second == 99) then
        return self:loop(value, position + 2, length, true)
    end
    return false
end
function Colon:done(value, position, length, seen)
    return final_match(value, position, length, seen)
end
function Colon:match(value) return self:loop(value, 0, #value, false) end
local colon = setmetatable({}, Colon)

local Static = {}
Static.__index = Static
function Static:loop(value, position, length, seen)
    if position + 1 < length then return Static.pair(self, value, position, length, seen) end
    return Static.done(self, value, position, length, seen)
end
function Static:pair(value, position, length, seen)
    local first, second = byte(value, position + 1, position + 2)
    if first == 97 and (second == 98 or second == 99) then
        return Static.loop(self, value, position + 2, length, true)
    end
    return false
end
function Static:done(value, position, length, seen)
    return final_match(value, position, length, seen)
end
function Static:match(value) return Static.loop(self, value, 0, #value, false) end
local static = setmetatable({}, Static)

local Stateful = {}
Stateful.__index = Stateful
function Stateful:loop(value)
    if self.position + 1 < self.length then return self:pair(value) end
    return self:done(value)
end
function Stateful:pair(value)
    local first, second = byte(value, self.position + 1, self.position + 2)
    if first == 97 and (second == 98 or second == 99) then
        self.position = self.position + 2
        self.seen = true
        return self:loop(value)
    end
    return false
end
function Stateful:done(value)
    return final_match(value, self.position, self.length, self.seen)
end
function Stateful:match(value)
    self.position = 0
    self.length = #value
    self.seen = false
    return self:loop(value)
end
local stateful = setmetatable({}, Stateful)

ffi.cdef [[
typedef struct CpsVmMethodShapeState {
    int32_t position;
    int32_t length;
    uint8_t seen;
} CpsVmMethodShapeState;
 ]]

local FfiMethods = {}
function FfiMethods:loop(value)
    if self.position + 1 < self.length then return self:pair(value) end
    return self:done(value)
end
function FfiMethods:pair(value)
    local first, second = byte(value, self.position + 1, self.position + 2)
    if first == 97 and (second == 98 or second == 99) then
        self.position = self.position + 2
        self.seen = 1
        return self:loop(value)
    end
    return false
end
function FfiMethods:done(value)
    return self.seen ~= 0 and self.position + 1 == self.length
        and byte(value, self.position + 1) == 100
end
function FfiMethods:match(value)
    self.position = 0
    self.length = #value
    self.seen = 0
    return self:loop(value)
end
local FfiMachine = ffi.metatype("CpsVmMethodShapeState", { __index = FfiMethods })
local ffi_machine = FfiMachine()

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
measure("structured Lua", function() return structured(input) end)
measure("lexical block edges", function() return Lexical:match(input) end)
measure("colon method edges", function() return colon:match(input) end)
measure("static method edges", function() return static:match(input) end)
measure("table self state", function() return stateful:match(input) end)
measure("FFI metatype self", function() return ffi_machine:match(input) end)

