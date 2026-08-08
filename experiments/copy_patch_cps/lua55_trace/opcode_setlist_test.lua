package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_table/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_generic_table/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_setlist/bank.lua"))

local heap = Heap.GuestHeap.new(23)

local main = Undump.undump(require("experiments.copy_patch_cps.lua55_trace.opcode_setlist_fixture"))
local proto = assert(main.protos[1])
assert(proto.code[1].name == "NEWTABLE" and proto.code[2].name == "EXTRAARG")
assert(proto.code[7].name == "SETLIST")

local path = Projection.project(proto, 0, 9, heap)
assert(getmetatable(path) == Projection.DecodedPath and #path.occurrences == 8)

local function program_frame()
    return Native.FrameOwner.new(proto.maxstacksize, #path.occurrences, #proto.upvals, heap, true)
end

-- The NEWTABLE bumps a fresh table each run, so the residual's SETLIST/
-- SETI guards fail on re-entry once; the driver re-learns (bounded).
local function run_block(frame)
    local program = path:new_program(9, bank)
    local status = program:execute(frame)
    if status == bank.status.guard_failed then
        program:free()
        program = path:new_program(9, bank)
        status = program:execute(frame)
    end
    program:free()
    return status
end

local ffi = Native.ffi
local refs = {}
for _, v in ipairs({ 5, -7, 42 }) do
    local f = program_frame()
    f:set_integer(0, v)
    assert(run_block(f) == bank.status.completed)
    -- the table is R1: array {1, 2, 3, v}
    local table_ref = tonumber(f:reference(1))
    local tt = ffi.cast("Lua55GuestTableV1 *", table_ref)
    for _, seen in ipairs(refs) do assert(seen ~= table_ref, "NEWTABLE reused a table") end
    refs[#refs + 1] = table_ref
    local values = {}
    for i = 1, 4 do
        values[i] = tonumber(ffi.cast("Lua55ValueV1 *",
            ffi.cast("uintptr_t", tt[0].array_values) + (i - 1) * 16).payload.integer)
    end
    assert(values[1] == 1 and values[2] == 2 and values[3] == 3 and values[4] == v,
        ("SETLIST values: %s"):format(table.concat(values, ",")))
end
assert(#refs == 3)

-- The table produced by NEWTABLE has min capacity: array_capacity >= 4.
do
    local f = program_frame()
    f:set_integer(0, 9)
    assert(run_block(f) == bank.status.completed)
    local tt = ffi.cast("Lua55GuestTableV1 *", tonumber(f:reference(1)))
    assert(tonumber(tt[0].array_capacity) >= 4)
end

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 setlist oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_literal(v)
    local script = table.concat({
        "local function build(v) local t = {1, 2, 3}; t[4] = v; return t end",
        "local t = build(", tostring(v), ")",
        "print(t[1], t[2], t[3], t[4])",
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_setlist.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_setlist.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    local numbers = {}
    for n in out:gmatch("(-?%d+)") do numbers[#numbers + 1] = tonumber(n) end
    return numbers
end

for _, v in ipairs({ 5, -7, 42, 1000 }) do
    local f = program_frame()
    f:set_integer(0, v)
    assert(run_block(f) == bank.status.completed)
    local tt = ffi.cast("Lua55GuestTableV1 *", tonumber(f:reference(1)))
    local native = {}
    for i = 1, 4 do
        native[i] = tonumber(ffi.cast("Lua55ValueV1 *", ffi.cast("uintptr_t", tt[0].array_values) + (i - 1) * 16).payload.integer)
    end
    local expected = stock_literal(v)
    for i = 1, 4 do
        assert(native[i] == expected[i],
            ("SETLIST differential v=%d slot %d: native=%d stock=%d"):format(v, i, native[i], expected[i]))
    end
end

heap:free()
print("Lua55 setlist: ok fresh-table literals + 4 differential cases native == stock")
