package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Direct = require("experiments.cdef_schema.json_direct")
local Tape = require("experiments.cdef_schema.json_tape")

local function deep_equal(actual, expected, path)
    path = path or "$"
    if type(expected) ~= "table" or expected == Tape.null then
        assert(actual == expected, path .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
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
    "null", "false", "true", "0", "-12.5e2", '"plain"',
    '"\\u20ac"', '"\\ud83d\\ude00"',
    "[]", "{}",
    '[null,true,false,3.5,"x"]',
    '{"name":"lalin","items":[1,2,{"ok":true}],"none":null}',
}

for _, source in ipairs(valid) do
    local direct = Direct.decode(source, 64)
    local tape = Tape.decode(source, 64)
    assert(direct:is_ok(), "direct decode failed: " .. source)
    assert(tape:is_ok(), "tape decode failed: " .. source)
    deep_equal(direct:materialize(), tape:materialize())
end

local malformed = {
    "", " ", "nul", "true false", "[", "[1,]", "[1 2]",
    "{", '{"a" 1}', '{"a":}', '{"a":1,}', "{1:2}",
    '"unterminated', '"bad\\x"', '"\\ud800"', "01", "1.", "1e",
    '"\192\128"',
}

for _, source in ipairs(malformed) do
    assert(not Direct.decode(source, 64):is_ok(), "expected direct rejection: " .. source)
end

local nested = string.rep("[", 8) .. "0" .. string.rep("]", 8)
assert(not Direct.decode(nested, 7):is_ok())
assert(Direct.decode(nested, 8):is_ok())

math.randomseed(24680)
for _ = 1, 1000 do
    local id = math.random(-100000, 100000)
    local score = math.random(-10000, 10000) / 10
    local enabled = math.random(2) == 1 and "true" or "false"
    local source = string.format(
        '{"id":%d,"score":%.1f,"enabled":%s,"name":"v%d\\n","items":[null,%d,%d]}',
        id, score, enabled, math.random(9999), math.random(9999), math.random(9999))
    local direct = Direct.decode(source, 32)
    local tape = Tape.decode(source, 32)
    assert(direct:is_ok() and tape:is_ok(), "generated direct decode failed")
    deep_equal(direct:materialize(), tape:materialize())
end

local workspace = Direct.workspace(64, 8)
local result = workspace:decode('{"ok":true}')
assert(result:is_ok() and result:materialize().ok == true)
assert(workspace.decoder.input == nil
    and workspace.decoder.strings == nil
    and workspace.decoder.stack == nil)

print("nested CDEF CPS direct JSON table decoder: ok")

