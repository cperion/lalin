package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local util = require("jit.util")
local vmdef = require("jit.vmdef")
local Exotype = require("experiments.exotype_cps.exotype")
local Compiler = require("experiments.exotype_cps.compiler")
local Constructors = require("experiments.exotype_cps.constructors")

local function parse_schema(text)
    local fields = {}
    for name, kind in text:gmatch("([_%a][_%w]*):([_%a][_%w]*)") do
        assert(kind == "i64", "unsupported test field type " .. kind)
        fields[#fields + 1] = { name = name, ctype = "int64_t" }
    end
    assert(#fields > 0, "schema has no fields")
    return fields
end

local function last_opcode(fn)
    local last
    for pc = 1, 10000 do
        local instruction = util.funcbc(fn, pc)
        if instruction == nil then break end
        local opcode = bit.band(instruction, 255)
        last = vmdef.bcnames:sub(opcode * 6 + 1, opcode * 6 + 6):match("^%s*(.-)%s*$")
    end
    return last
end

-- This information is available only after the host program has started.
local runtime_schema = parse_schema("x:i64,y:i64,z:i64")
local Point = Constructors.Record(runtime_schema)
local PointAgain = Constructors.Record(parse_schema("x:i64,y:i64,z:i64"))
assert(PointAgain == Point, "type constructor must memoize equal structural arguments")

local Batch = Constructors.Array(Point, 4)
local compiler = Compiler.new()
local BatchType = compiler:compile(Batch, { "sum", "run" })

assert(ffi.sizeof(Point.descriptor()) == 24)
assert(ffi.sizeof(BatchType()) == 104)
assert(Point.stats.entries == 1 and Batch.stats.entries == 1)
assert(Point.stats.methods.sum == 1 and Point.stats.methods.scale == 1)
assert(Batch.stats.methods.sum == 1 and Batch.stats.methods.run == 1)
assert(Batch.stats.methods.scale == 1 and Batch.stats.methods.scaled == 1)
assert(Batch.stats.methods.unused == nil)
assert(compiler.generated[Batch].sum:match("self%.items%[3%]%.z"))
assert(not compiler.generated[Batch].sum:match("for%s"))
assert(compiler.generated[Batch].scale:match("return completed%(self%)"))

local batch = BatchType()
local expected = 0
for item = 0, 3 do
    batch.items[item].x = item + 1
    batch.items[item].y = (item + 1) * 2
    batch.items[item].z = (item + 1) * 3
    expected = expected + (item + 1) * 6
end
assert(tonumber(batch:sum()) == expected)

batch:run(3)
assert(tonumber(batch:sum()) == expected * 3)
assert(tonumber(batch.transitions) == 1)
assert(last_opcode(Batch.compiled_methods.scale) == "CALLT")
assert(last_opcode(Batch.compiled_methods.run) == "CALLT")

compiler:compile(Batch, { "sum", "run" })
local sealed_ok, sealed_error = pcall(function() compiler:compile(Batch, { "unused" }) end)
assert(not sealed_ok and tostring(sealed_error):match("sealed without method unused"))

local OneField = Constructors.Record(parse_schema("value:i64"))
local OneFieldType = compiler:compile(OneField, { "sum" })
assert(ffi.sizeof(OneFieldType()) == 8)
assert(not ffi.istype(ffi.typeof(Point.ctype_name), OneFieldType()))

local Bad
Bad = Exotype.new {
    name = "BadCycle",
    properties = {
        __getentries = function(cc) return cc:query(Bad, "__getentries") end,
    },
}
local cycle_ok, cycle_error = pcall(function() Compiler.new():compile(Bad, {}) end)
assert(not cycle_ok and tostring(cycle_error):match("cyclic exotype property query"))

print(("ok exotype cps point=%d batch=%d queries=%d sum=%d transitions=%d"):format(
    ffi.sizeof(Point.descriptor()), ffi.sizeof(BatchType()),
    Point.stats.entries + Batch.stats.entries, tonumber(batch:sum()),
    tonumber(batch.transitions)))
