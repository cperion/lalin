package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Cdef = require("experiments.retained_compiler.machine")
local Asdl = require("experiments.retained_compiler.asdl_machine")

local cdef = Cdef.Compiler()

local valid = {
    "return 1;",
    "return 2 + 3 * 4;",
    "return (2 + 3) * 4;",
    "let x = 40; let y = x + 2 * 3; return y - 1;",
    "let base = 7; let doubled = base * 2; return doubled + base;",
}

local operators = { "+", "-", "*" }
for index = 1, 64 do
    local operator1 = operators[index % 3 + 1]
    local operator2 = operators[(index + 1) % 3 + 1]
    valid[#valid + 1] = ("let x = %d; let y = x %s %d * %d; return y %s %d;"):format(
        index * 3 + 1, operator1, index * 5 + 2, index % 17 + 3, operator2, index % 11 + 1)
end

for _, source in ipairs(valid) do
    local physical = cdef:compile(source)
    local symbolic = Asdl.compile(source)
    assert(physical:succeeded(), physical:diagnostic_text())
    assert(symbolic:succeeded(), symbolic:diagnostic_text())
    assert(physical:artifact_text() == symbolic:artifact_text(),
        source .. "\nCDEF:\n" .. physical:artifact_text() .. "ASDL:\n" .. symbolic:artifact_text())
end

local invalid = {
    "return missing;",
    "let x = 1; let x = 2; return x;",
    "let x = 1 + ; return x;",
    "let x = 1;",
}

for _, source in ipairs(invalid) do
    local physical = cdef:compile(source)
    local symbolic = Asdl.compile(source)
    assert(not physical:succeeded())
    assert(not symbolic:succeeded())
    assert(physical:diagnostic_text() == symbolic:diagnostic_text(),
        source .. ": " .. physical:diagnostic_text() .. " ~= " .. symbolic:diagnostic_text())
end

print("ok retained compiler CDEF/ASDL differential")
