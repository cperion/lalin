package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")

local function load_proto(name, nested)
    local main = Undump.undump(require("experiments.copy_patch_cps.lua55_trace." .. name))
    if nested then return assert(main.protos[1].protos[1]) end
    return assert(main.protos[1])
end

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_table/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_generic_table/bank.lua"))

local heap = Heap.GuestHeap.new(23)

local function program_frame(path)
    return Native.FrameOwner.new(path.proto.maxstacksize, #path.occurrences,
        #path.proto.upvals, heap, true)
end

local function run_block(path, stop, frame)
    local program = path:new_program(stop, bank)
    local status = program:execute(frame)
    if status == bank.status.guard_failed then
        -- a NEWTABLE in the path bumps a fresh table: re-learn once
        program:free()
        program = path:new_program(stop, bank)
        status = program:execute(frame)
    end
    program:free()
    return status
end

-- ---------------------------------------------------------------------
-- GETTABLE/SETTABLE with runtime keys (12/16).
local gtable_proto = load_proto("opcode_generic_table_gtable_fixture")
assert(gtable_proto.code[1].name == "GETTABLE" and gtable_proto.code[5].name == "SETTABLE")
local gtable_path = Projection.project(gtable_proto, 0, 10, heap)
assert(#gtable_path.occurrences == 9)

local t = heap:table(4, 2)
t:set_array_integer(1, 10):set_array_integer(2, 20):set_array_integer(3, 30)
t:set_field_integer(heap:short_string("name"), 5)

local frame = program_frame(gtable_path)
frame:set_table(0, t):set_integer(1, 1):set_short_string(2, heap:short_string("name"))
assert(run_block(gtable_path, 10, frame) == bank.status.completed)
-- a = t[1] = 10, b = t.name = 5; t[1] = 11, t.name = 5
assert(frame:tag(5) == bank.tags.integer and tonumber(frame:integer(5)) == 10)
assert(frame:tag(6) == bank.tags.integer and tonumber(frame:integer(6)) == 5)
assert(tonumber(t:array_value(1).payload.integer) == 11)
assert(tonumber(t:field_value(heap:short_string("name"), false).payload.integer) == 5)

-- Re-execution on the residual: reads the mutated table.
local frame2 = program_frame(gtable_path)
frame2:set_table(0, t):set_integer(1, 1):set_short_string(2, heap:short_string("name"))
assert(run_block(gtable_path, 10, frame2) == bank.status.completed)
assert(tonumber(frame2:integer(5)) == 11)   -- t[1] was 11
assert(tonumber(t:array_value(1).payload.integer) == 12)

-- An int key beyond the fixed array capacity: the GETTABLE would return
-- nil, but the path's SETTABLE would need to resize the table — the closed
-- subset rejects out-of-bounds writes visibly (host resizes).
do
    local f = program_frame(gtable_path)
    f:set_table(0, t):set_integer(1, 9):set_short_string(2, heap:short_string("name"))
    local program = gtable_path:new_program(10, bank)
    assert(program:execute(f) == bank.status.rejected)
    program:free()
end

-- Guard: a changed runtime key fails at the first GETTABLE pc (0).
do
    local f = program_frame(gtable_path)
    f:set_table(0, t):set_integer(1, 2):set_short_string(2, heap:short_string("name"))
    local program = gtable_path:new_program(10, bank)
    assert(program:execute(f) == bank.status.completed)   -- learns with key 2
    f:set_integer(1, 3)
    assert(program:execute(f) == bank.status.guard_failed)  -- residual key guard
    assert(f.frame.resume_pc == 0)
    program:free()
end

-- Rejection: a non-int/string key (nil) rejects at learn time.
do
    local f = program_frame(gtable_path)
    f:set_table(0, t):set_nil(1):set_short_string(2, heap:short_string("name"))
    local program = gtable_path:new_program(10, bank)
    assert(program:execute(f) == bank.status.rejected)
    program:free()
end

-- ---------------------------------------------------------------------
-- GETTABUP/SETTABUP (15/11): upvalue receiver + constant key.
local gup_proto = load_proto("opcode_generic_table_gup2_fixture", true)
assert(gup_proto.code[1].name == "GETTABUP" and gup_proto.code[4].name == "SETTABUP")
local gup_path = Projection.project(gup_proto, 0, 5, heap)
assert(#gup_path.occurrences == 4)

local up_table = heap:table(2, 2)
up_table:set_field_integer(heap:short_string("x"), 10)

local function gup_frame()
    local frame = program_frame(gup_path)
    frame:set_integer(0, 3)
    frame:open_upvalue(0, 1, 1)
    frame:set_table(1, up_table)
    frame:close_upvalue(0, 2)
    return frame
end

local f3 = gup_frame()
assert(run_block(gup_path, 5, f3) == bank.status.completed)
assert(tonumber(up_table:field_value(heap:short_string("x"), false).payload.integer) == 13)

local f4 = gup_frame()   -- fresh frame, same closed upvalue: residual runs
assert(run_block(gup_path, 5, f4) == bank.status.completed)
assert(tonumber(up_table:field_value(heap:short_string("x"), false).payload.integer) == 16)

-- Guard: a different upvalue table fails at the GETTABUP pc (0).
do
    local alien = heap:table(2, 2)
    alien:set_field_integer(heap:short_string("x"), 1)
    local f = program_frame(gup_path)
    f:set_integer(0, 1)
    f:open_upvalue(0, 1, 1)
    f:set_table(1, alien)
    f:close_upvalue(0, 2)
    local program = gup_path:new_program(5, bank)
    assert(program:execute(f) == bank.status.completed)
    f:open_upvalue(0, 1, 3)   -- change the upvalue generation
    assert(program:execute(f) == bank.status.guard_failed)
    program:free()
end

-- ---------------------------------------------------------------------
-- SELF (20): R[A+1] = receiver; R[A] = receiver[K[C]].
local gself_proto = load_proto("opcode_generic_table_gself_fixture")
assert(gself_proto.code[1].name == "SELF")
local gself_path = Projection.project(gself_proto, 0, 2, heap)
assert(#gself_path.occurrences == 2)

local obj = heap:table(2, 2)
obj:set_field_integer(heap:short_string("get"), 42)
do
    local f = program_frame(gself_path)
    f:set_table(0, obj)
    assert(run_block(gself_path, 2, f) == bank.status.completed)
    assert(f:tag(1) == bank.tags.integer and tonumber(f:integer(1)) == 42,  -- the method
        ("self R1 tag=%s val=%s"):format(tostring(f:tag(1)), tostring(f:integer(1))))
    assert(f:tag(2) == bank.tags.table_value,                                      -- the object
        ("self R2 tag=%s ref=%s obj=%s"):format(tostring(f:tag(2)), tostring(f:reference(2)), tostring(obj:reference())))
    assert(f:reference(2) == obj:reference())
end

-- ---------------------------------------------------------------------
-- NEWTABLE (19): a fresh guest table each run, with min capacity.
local gnew_proto = load_proto("opcode_generic_table_gnew2_fixture")
assert(gnew_proto.code[1].name == "NEWTABLE" and gnew_proto.code[2].name == "EXTRAARG")
local gnew_path = Projection.project(gnew_proto, 0, 6, heap)
assert(#gnew_path.occurrences == 5)

local refs = {}
for _ = 1, 5 do
    local f = program_frame(gnew_path)
    f:set_integer(0, 5)
    assert(run_block(gnew_path, 6, f) == bank.status.completed)
    assert(f:tag(2) == bank.tags.integer and tonumber(f:integer(2)) == 5)
    local table_ref = tonumber(f:reference(1))
    for _, seen in ipairs(refs) do assert(seen ~= table_ref, "NEWTABLE reused a table") end
    refs[#refs + 1] = table_ref
end
assert(#refs == 5)

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 generic-table oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_eval(body)
    local script = table.concat({
        "local function gtable(t, i, s) local a = t[i]; local b = t[s]; t[i] = a + 1; t[s] = b; return a, b end",
        "local function gup2() local t = {x = 10} return function(i) t.x = t.x + i end end",
        body,
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_gt.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_gt.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    return out
end

-- gtable differential: fn(t, 1, "name") twice, compare the table state.
do
    local stock_out = stock_eval([[
local t = {10, 20, 30}; t.name = 5
local a, b = gtable(t, 1, "name")
local a2, b2 = gtable(t, 1, "name")
print(a, b, a2, b2, t[1], t.name)]])
    local native = {}
    local tt = heap:table(4, 2)
    tt:set_array_integer(1, 10):set_array_integer(2, 20):set_array_integer(3, 30)
    tt:set_field_integer(heap:short_string("name"), 5)
    local f = program_frame(gtable_path)
    f:set_table(0, tt):set_integer(1, 1):set_short_string(2, heap:short_string("name"))
    run_block(gtable_path, 10, f)
    native[1], native[2] = tonumber(f:integer(5)), tonumber(f:integer(6))
    local f2 = program_frame(gtable_path)
    f2:set_table(0, tt):set_integer(1, 1):set_short_string(2, heap:short_string("name"))
    run_block(gtable_path, 10, f2)
    native[3], native[4] = tonumber(f2:integer(5)), tonumber(f2:integer(6))
    native[5] = tonumber(tt:array_value(1).payload.integer)
    native[6] = tonumber(tt:field_value(heap:short_string("name"), false).payload.integer)
    local numbers = {}
    for n in stock_out:gmatch("(-?%d+)") do numbers[#numbers + 1] = tonumber(n) end
    assert(#numbers == 6, ("stock numbers: %d"):format(#numbers))
    for i = 1, 6 do
        assert(numbers[i] == native[i], ("gtable differential slot %d"):format(i))
    end
end

-- gup2 differential: the closure increments t.x.
do
    local stock_out = stock_eval([[
local f = gup2()
f(3); f(7); f(-2)
print((function() local t = {x = 10} local g = function(i) t.x = t.x + i end; g(3); g(7); g(-2); return t.x end)())]])
    local expected = tonumber(stock_out:match("(-?%d+)"))
    up_table:set_field_integer(heap:short_string("x"), 10)
    for _, i in ipairs({ 3, 7, -2 }) do
        local f = gup_frame()
        f:set_integer(0, i)
        assert(run_block(gup_path, 5, f) == bank.status.completed)
    end
    local native_x = tonumber(up_table:field_value(heap:short_string("x"), false).payload.integer)
    assert(native_x == expected, ("gup2 native=%s stock=%s"):format(native_x, expected))
end

heap:free()
print("Lua55 generic tables: ok GETTABLE/SETTABLE/GETTABUP/SETTABUP/SELF/NEWTABLE")
