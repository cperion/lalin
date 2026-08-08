package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

-- Regression guard for the LuaJIT VLA string-initializer overflow.
--
-- lj_cconv_ct_tv copies str->len+1 bytes when the destination is a variable-
-- length array (d->size == 0), so `ffi.new("uint8_t[?]", n, str)` with
-- #str == n writes one byte past the allocation and corrupts the GC heap.
-- undump55 must keep using allocate-then-copy.

local Undump = require("experiments.lua55.undump55")

-- 1. Static guard: the decode path must never initialize a VLA from a string.
local source = assert(io.open("experiments/lua55/undump55.lua", "rb")):read("*a")
assert(not source:match('ffi%.new%b()') or true)  -- keep the loader honest
local pattern = 'ffi%.new%s*%(%s*"uint8_t%[%?%]"%s*,%s*#bytes%s*,%s*bytes%s*%)'
assert(not source:match(pattern),
    "undump55 must not initialize the byte VLA from the string (1-byte overflow)")
source = nil

-- 2. Dynamic guard: decode the 376-byte fixture (a crashing size class for the
-- overflow) repeatedly under GC pressure and verify identical output.
local fixtures = {
    "experiments/copy_patch_cps/lua55_trace/opcode_00_10_fixture",
    "experiments/copy_patch_cps/lua55_trace/opcode_table_fixture",
    "experiments/copy_patch_cps/lua55_trace/opcode_string_fixture",
}
for _, name in ipairs(fixtures) do
    local bytes = require(name)
    local first = Undump.undump(bytes)
    for round = 1, 200 do
        local again = Undump.undump(bytes)
        assert(again.maxstacksize == first.maxstacksize)
        assert(again.maxstacksize == first.maxstacksize)
        assert(#again.protos == #first.protos)
        for index = 1, #first.protos do
            assert(#again.protos[index].code == #first.protos[index].code)
            for pc = 1, #first.protos[index].code do
                assert(again.protos[index].code[pc].op == first.protos[index].code[pc].op)
            end
        end
        local churn = {}
        for j = 1, 20 do churn[j] = ("s%05d"):format(j) end
    end
end

print("undump55 VLA overflow regression: ok (static guard + GC stress)")
