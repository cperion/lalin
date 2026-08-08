package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Glob = require("experiments.cdef_schema.cps_glob")
local sensitive = Glob.Sensitive()
local folded = Glob.AsciiFold()
local coarse_sensitive = Glob.CoarseSensitive()
local coarse_folded = Glob.CoarseAsciiFold()
local driven_sensitive = Glob.DrivenSensitive()

local matches = {
    { "", "" },
    { "*", "" },
    { "*", "anything" },
    { "?", "x" },
    { "a?c", "abc" },
    { "ab*cd?ef*xyz", "abqqqcdZefrrxyz" },
    { "a*b*c", "axybzzc" },
    { "***", "abc" },
}

local rejects = {
    { "", "x" },
    { "?", "" },
    { "abc", "ab" },
    { "abc", "abd" },
    { "a*d", "abc" },
    { "ab*cd?ef*xyz", "abqqqcdZegrrxyz" },
}

for _, example in ipairs(matches) do
    assert(sensitive:match(example[1], example[2]),
        "expected fine glob match: " .. example[1] .. " / " .. example[2])
    assert(coarse_sensitive:match(example[1], example[2]),
        "expected coarse glob match: " .. example[1] .. " / " .. example[2])
    assert(driven_sensitive:match(example[1], example[2]),
        "expected driven glob match: " .. example[1] .. " / " .. example[2])
end

for _, example in ipairs(rejects) do
    assert(not sensitive:match(example[1], example[2]),
        "expected fine glob rejection: " .. example[1] .. " / " .. example[2])
    assert(not coarse_sensitive:match(example[1], example[2]),
        "expected coarse glob rejection: " .. example[1] .. " / " .. example[2])
    assert(not driven_sensitive:match(example[1], example[2]),
        "expected driven glob rejection: " .. example[1] .. " / " .. example[2])
end

assert(folded:match("ab*CD?ef*XYZ", "ABqqqcdZEFrrxyz"))
assert(coarse_folded:match("ab*CD?ef*XYZ", "ABqqqcdZEFrrxyz"))
assert(not sensitive:match("ab*CD?ef*XYZ", "ABqqqcdZEFrrxyz"))
assert(sensitive.pattern == nil and sensitive.text == nil)
assert(coarse_sensitive.pattern == nil and coarse_sensitive.text == nil)
assert(Glob.Machine:is(sensitive) and Glob.Machine:is(coarse_folded))

print("cdef CPS glob matcher: ok")

