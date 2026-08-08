package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local Compiler = require("experiments.exotype_cps.compiler")
local Constructors = require("experiments.exotype_cps.constructors")

local iterations = tonumber(arg[1]) or 1000000
local fields = {}
for index = 1, 6 do fields[index] = { name = "v" .. index, ctype = "int64_t" } end
local Row = Constructors.Record(fields)
local Batch = Constructors.Array(Row, 8)
local BatchType = Compiler.new():compile(Batch, { "sum", "run" })
local value = BatchType()
local generic, field_names = {}, {}
for field = 1, 6 do field_names[field] = "v" .. field end
for row = 0, 7 do
    generic[row + 1] = {}
    for field = 1, 6 do
        local field_name = field_names[field]
        value.items[row][field_name] = row + field
        generic[row + 1][field_name] = row + field
    end
end

local function generic_sum(rows, names)
    local result = 0
    for row = 1, #rows do
        for field = 1, #names do result = result + rows[row][names[field]] end
    end
    return result
end

for _ = 1, 100 do value:run(1); value:sum(); generic_sum(generic, field_names) end
local started = os.clock()
local exotype_checksum = 0
for _ = 1, iterations do
    value.items[0].v1 = value.items[0].v1 + 1
    exotype_checksum = exotype_checksum + tonumber(value:sum())
end
local exotype_elapsed = os.clock() - started

started = os.clock()
local generic_checksum = 0
for _ = 1, iterations do
    generic[1].v1 = generic[1].v1 + 1
    generic_checksum = generic_checksum + generic_sum(generic, field_names)
end
local generic_elapsed = os.clock() - started
assert(exotype_checksum == generic_checksum)

local exotype_ns = exotype_elapsed * 1e9 / iterations
local generic_ns = generic_elapsed * 1e9 / iterations
print(("exotype-cps iterations=%d exotype_ns=%.3f generic_ns=%.3f speedup=%.2fx "
    .. "checksum=%.0f type_bytes=%d transitions=%d"):format(
    iterations, exotype_ns, generic_ns, generic_ns / exotype_ns, exotype_checksum,
    require("ffi").sizeof(value), tonumber(value.transitions)))
