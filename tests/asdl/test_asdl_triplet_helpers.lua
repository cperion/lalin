package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")

local function same_array(actual, expected)
    assert(#actual == #expected, "array length mismatch")
    for i = 1, #expected do
        assert(actual[i] == expected[i], "array item mismatch at " .. i)
    end
end

local function trip(fn, ...)
    return { fn(...) }
end

same_array(asdl.drain(asdl.seq({ 1, 2, 3 })), { 1, 2, 3 })
same_array(asdl.drain(asdl.seq({ 1, 2, 3 }, 2)), { 1, 2 })

local out = { 0 }
local g, p, c = asdl.seq({ 1, 2 })
asdl.drain_into(g, p, c, out)
same_array(out, { 0, 1, 2 })

assert(asdl.one(asdl.once("x")) == "x")

local ok_empty, err_empty = pcall(function()
    asdl.one(asdl.empty())
end)
assert(not ok_empty)
assert(tostring(err_empty):match("expected exactly 1 element"))

local ok_many, err_many = pcall(function()
    asdl.one(asdl.seq({ "a", "b" }))
end)
assert(not ok_many)
assert(tostring(err_many):match("expected exactly 1 element"))

local a = trip(asdl.seq, { 1 })
local b = trip(asdl.seq, { 2, 3 })
same_array(asdl.drain(asdl.concat2(a[1], a[2], a[3], b[1], b[2], b[3])), { 1, 2, 3 })

local c1 = trip(asdl.seq, { 1 })
local c2 = trip(asdl.empty)
local c3 = trip(asdl.seq, { 2 })
same_array(asdl.drain(asdl.concat3(c1[1], c1[2], c1[3], c2[1], c2[2], c2[3], c3[1], c3[2], c3[3])), { 1, 2 })
same_array(asdl.drain(asdl.concat_all({
    trip(asdl.seq, { "a" }),
    trip(asdl.seq, { "b", "c" }),
})), { "a", "b", "c" })

local function duplicate(v)
    return asdl.seq({ v, v })
end
same_array(asdl.drain(asdl.children(duplicate, { 1, 2, 3 })), { 1, 1, 2, 2, 3, 3 })

local fg, fp, fc = asdl.seq({ 1, 2, 3 })
local sum = asdl.fold(fg, fp, fc, 0, function(acc, v)
    return acc + v
end)
assert(sum == 6)

local seen = {}
local eg, ep, ec = asdl.seq({ "x", "y" })
asdl.each(eg, ep, ec, function(v)
    seen[#seen + 1] = v
end)
same_array(seen, { "x", "y" })

print("lalin asdl triplet helpers ok")
