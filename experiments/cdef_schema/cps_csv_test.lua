package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Csv = require("experiments.cdef_schema.cps_csv_scanner")

local signed = Csv.Signed()
local driven = Csv.ForDrivenSigned()
local report = signed:scan(" -12, 0, +34, 9223372036854775807, -9223372036854775808 ")
assert(report:is_ok() and report:count() == 5)
assert(tonumber(report:value(1)) == -12)
assert(tonumber(report:value(2)) == 0)
assert(tonumber(report:value(3)) == 34)
assert(tostring(report:value(4)) == "9223372036854775807LL")
assert(tostring(report:value(5)) == "-9223372036854775808LL")
assert(signed.input == nil, "borrowed input pointer escaped scan")
report = driven:scan(" -12, 0, +34, 9223372036854775807, -9223372036854775808 ")
assert(report:is_ok() and report:count() == 5)
assert(tostring(report:value(5)) == "-9223372036854775808LL")
assert(driven.input == nil, "for-driven input pointer escaped scan")
assert(signed:scan("9223372036854775808"):is_overflow())
assert(signed:scan("-9223372036854775809"):is_overflow())
assert(signed:scan("1, nope"):is_syntax())
assert(driven:scan("9223372036854775808"):is_overflow())
assert(driven:scan("1, nope"):is_syntax())

local unsigned = Csv.Unsigned()
report = unsigned:scan("0, 12, 9223372036854775807")
assert(report:is_ok() and report:count() == 3)
assert(unsigned:scan("-1"):is_syntax())
assert(Csv.Machine:is(signed) and Csv.Machine:is(unsigned))

local capacity_input = string.rep("0,", Csv.capacity) .. "0"
assert(unsigned:scan(capacity_input):is_capacity())

print("cdef CPS CSV scanner: ok")

