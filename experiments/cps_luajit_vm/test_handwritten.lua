package.path = "./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Counter = require("experiments.cps_luajit_vm.counter")
local matcher = require("experiments.cps_luajit_vm.matcher")
local PointerMatcher = require("experiments.cps_luajit_vm.pointer_matcher")
local pointer_matcher = PointerMatcher()
local NumberScanner = require("experiments.cps_luajit_vm.number_scanner")
local number_scanner = NumberScanner.Scanner()

local counter = Counter()
assert(tonumber(counter:run(ffi.new("int64_t", 100000))) == 4999950000)

for _, input in ipairs({ "abd", "acd", "abacabd" }) do
    assert(matcher:match(input), "expected string match: " .. input)
    assert(pointer_matcher:match(input), "expected pointer match: " .. input)
end
for _, input in ipairs({ "", "ab", "abac", "abacad" }) do
    assert(not matcher:match(input), "expected string rejection: " .. input)
    assert(not pointer_matcher:match(input), "expected pointer rejection: " .. input)
end
assert(pointer_matcher.input == nil, "borrowed input pointer escaped match")

local numbers = number_scanner:scan(" -12, 0, +34, 9223372036854775807, -9223372036854775808 ")
assert(numbers:is_ok() and numbers:count() == 5)
assert(tonumber(numbers:value(1)) == -12)
assert(tonumber(numbers:value(2)) == 0)
assert(tonumber(numbers:value(3)) == 34)
assert(tostring(numbers:value(4)) == "9223372036854775807LL")
assert(tostring(numbers:value(5)) == "-9223372036854775808LL")
assert(number_scanner.input == nil, "number scanner input pointer escaped scan")

local syntax = number_scanner:scan("1, nope")
assert(syntax:is_syntax() and syntax:error_position() == 3)
local overflow = number_scanner:scan("9223372036854775808")
assert(overflow:is_overflow())
assert(number_scanner:scan("-9223372036854775809"):is_overflow())
assert(number_scanner:scan(""):is_ok())
local capacity_input = string.rep("0,", NumberScanner.capacity) .. "0"
assert(number_scanner:scan(capacity_input):is_capacity())

print("handwritten CPS tests: ok")

