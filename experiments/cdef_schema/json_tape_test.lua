package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Json = require("experiments.cdef_schema.json_tape")

local function deep_equal(actual, expected, path)
    path = path or "$"
    if type(expected) ~= "table" or expected == Json.null then
        assert(actual == expected, path .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
        return
    end
    assert(type(actual) == "table", path .. ": expected table")
    for key, value in pairs(expected) do
        deep_equal(actual[key], value, path .. "." .. tostring(key))
    end
    for key in pairs(actual) do
        assert(expected[key] ~= nil, path .. ": unexpected key " .. tostring(key))
    end
end

local valid = {
    { "null", Json.null },
    { "false", false },
    { "true", true },
    { "0", 0 },
    { "-0", 0 },
    { "123", 123 },
    { "-12.5", -12.5 },
    { "1.25e2", 125 },
    { "1E-2", 0.01 },
    { '"plain"', "plain" },
    { '"\\\"\\\\\\/\\b\\f\\n\\r\\t"', '"\\/\b\f\n\r\t' },
    { '"\\u20ac"', "\226\130\172" },
    { '"\\ud83d\\ude00"', "\240\159\152\128" },
    { '"caf\195\169"', "caf\195\169" },
    { "[]", {} },
    { "{}", {} },
    { " [ null, true, false, 3.5, \"x\" ] ",
        { Json.null, true, false, 3.5, "x" } },
    { '{"name":"lalin","items":[1,2,{"ok":true}],"none":null}',
        { name = "lalin", items = { 1, 2, { ok = true } }, none = Json.null } },
}

for _, case in ipairs(valid) do
    local result = Json.decode(case[1], 64)
    assert(result:is_ok(), "expected valid JSON at " .. result:error_position() .. ": " .. case[1])
    deep_equal(result:materialize(), case[2])
end

local malformed = {
    "", " ", "nul", "truth", "true false",
    "[", "[1,]", "[1 2]", "[,1]",
    "{", '{"a" 1}', '{"a":}', '{"a":1,}', "{1:2}",
    "]", "}", '"unterminated', '"bad\\x"', '"bad\1"',
    '"\\u12x4"', '"\\ud800"', '"\\ud800\\u0041"', '"\\udc00"',
    "01", "-01", "1.", "1e", "1e+", "--1", ".1",
    '"\192\128"', '"\237\160\128"', '"\244\144\128\128"',
}

for _, source in ipairs(malformed) do
    local result = Json.decode(source, 64)
    assert(not result:is_ok(), "expected malformed JSON: " .. string.format("%q", source))
end

local nested = string.rep("[", 8) .. "0" .. string.rep("]", 8)
local depth_failure = Json.decode(nested, 7)
assert(depth_failure.report:is_depth_capacity())
local depth_success = Json.decode(nested, 8)
assert(depth_success:is_ok())

local array_result = Json.decode('[1,{"x":[2,3]}]')
assert(array_result:is_ok())
local tape = array_result.tape
assert(tape[0].kind == Json.kinds.array_start)
assert(tape[tape[0].match].kind == Json.kinds.array_end)
local object_index = 2
assert(tape[object_index].kind == Json.kinds.object_start)
assert(tape[tape[object_index].match].kind == Json.kinds.object_end)

local decoder = Json.Decoder()
local tiny_tape = ffi.new("JsonTapeV1_Token[1]")
local tiny_strings = ffi.new("uint8_t[1]")
local tiny_stack = ffi.new("JsonTapeV1_Frame[1]")
local tape_failure = decoder:decode("[0]", tiny_tape, 1, tiny_strings, 1, tiny_stack, 1)
assert(tape_failure:is_tape_capacity())
assert(decoder.input == nil and decoder.tape == nil and decoder.strings == nil and decoder.stack == nil)

local string_failure = decoder:decode('"\\u20ac"', tiny_tape, 1,
    tiny_strings, 1, tiny_stack, 1)
assert(string_failure:is_string_capacity())

local function encode_string(value)
    return '"' .. value:gsub('["\\\b\f\n\r\t]', {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
        ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
    }) .. '"'
end

local function encode(value)
    if value == Json.null then return "null" end
    local kind = type(value)
    if kind == "boolean" or kind == "number" then return tostring(value) end
    if kind == "string" then return encode_string(value) end
    local pieces = {}
    if value[1] ~= nil then
        for index = 1, #value do pieces[index] = encode(value[index]) end
        return "[" .. table.concat(pieces, ",") .. "]"
    end
    for key, item in pairs(value) do
        pieces[#pieces + 1] = encode_string(key) .. ":" .. encode(item)
    end
    table.sort(pieces)
    return "{" .. table.concat(pieces, ",") .. "}"
end

math.randomseed(12345)
local function generated(depth)
    local choice = math.random(depth > 0 and 7 or 5)
    if choice == 1 then return Json.null end
    if choice == 2 then return math.random(2) == 1 end
    if choice == 3 then return math.random(-100000, 100000) / 10 end
    if choice == 4 then return "s" .. math.random(0, 999) .. "\n" end
    if choice == 5 then return "plain" end
    if choice == 6 then
        local output = {}
        for index = 1, math.random(0, 4) do output[index] = generated(depth - 1) end
        return output
    end
    local output = {}
    for index = 1, math.random(0, 4) do output["k" .. index] = generated(depth - 1) end
    return output
end

for _ = 1, 1000 do
    local expected = generated(4)
    local source = encode(expected)
    local result = Json.decode(source, 32)
    assert(result:is_ok(), "generated decode failed: " .. source)
    deep_equal(result:materialize(), expected)
end

print("nested CDEF CPS JSON tape decoder: ok")

