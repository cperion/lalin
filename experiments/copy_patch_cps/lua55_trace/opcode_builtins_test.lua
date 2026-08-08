package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local GTable = require("experiments.copy_patch_cps.lua55_trace.opcode_generic_table")
local ffi = Native.ffi

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_string/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_generic_table/bank.lua"))

local heap = Heap.GuestHeap.new(23)

-- select / rawget / rawset markers (ids 5/6/7) in the env table.
local SELECT = heap:builtin_value(5)
local RAWGET = heap:builtin_value(6)
local RAWSET = heap:builtin_value(7)
local env = heap:table(0, 4)
local function set_builtin(key_text, owner)
    local value = env:field_value(heap:short_string(key_text), true)
    value.tag, value.reserved = 8, 0
    value.payload.reference = owner.reference
    env.object[0].barrier_count = env.object[0].barrier_count + 1
end
set_builtin("select", SELECT)
set_builtin("rawget", RAWGET)
set_builtin("rawset", RAWSET)

local function builtin_id(value)
    if tonumber(value.tag) ~= bank.tags.closure_value then return nil end
    local ref = tonumber(value.payload.reference)
    if not ref or ref == 0 then return nil end
    local obj = ffi.cast("Lua55GuestObjectHeaderV1 *", ref)
    if tonumber(obj[0].kind) ~= 5 then return nil end
    return tonumber(ffi.cast("Lua55GuestBuiltinV1 *", ref)[0].builtin_id)
end

local function set_closure(frame, index, reference)
    frame.values[index].tag, frame.values[index].reserved = 8, 0
    frame.values[index].payload.reference = reference
end

-- Reusable native rawget / rawset programs (the generic-table leaves).
local rawget_program = Native.Program.new({
    GTable.GenericTableOccurrence.gettable(0, 2, 0, 1),
}, 4, 1, bank, 16384, 0, heap)
local rawset_program = Native.Program.new({
    GTable.GenericTableOccurrence.settable(0, 0, 1, 2),
}, 4, 1, bank, 16384, 0, heap)

-- A synthetic caller frame for the builtin CALL dispatch: R0 = the builtin
-- marker, R1..Rn = the args.
local function call_frame(nargs)
    local frame = Native.FrameOwner.new(8, 1, 0, heap, true)
    return frame
end

-- The host CALL dispatch for the select/rawget/rawset markers.
local function dispatch(frame, A, B)
    local callee = builtin_id(frame.values[A])
    if callee == 5 then   -- select
        local first = frame.values[A + 1]
        if tonumber(first.tag) == bank.tags.short_string and
            ffi.cast("Lua55GuestStringV1 *", tonumber(first.payload.reference))[0].length == 1 and
            ffi.cast("Lua55GuestStringV1 *", tonumber(first.payload.reference))[0].bytes[0] == 35 then
            -- select("#", ...) -> the count (args after the "#")
            frame:set_integer(A, B - 2)
        else
            -- select(i, ...) -> the ith vararg (1-based, the first is R[A+2])
            local i = tonumber(first.payload.integer)
            assert(i >= 1 and i <= B - 2, "select index out of range")
            frame.values[A] = frame.values[A + 1 + i]
        end
    elseif callee == 6 then   -- rawget(t, k)
        local prog = Native.Program.new({
            GTable.GenericTableOccurrence.gettable(0, 2, 0, 1),
        }, 4, 1, bank, 16384, 0, heap)
        local rg = prog:new_frame()
        rg.values[0] = frame.values[A + 1]
        rg.values[1] = frame.values[A + 2]
        local rgst = prog:execute(rg)
        prog:free()
        assert(rgst == bank.status.completed, ("rawget status %d"):format(tonumber(rgst)))
        frame.values[A] = rg.values[2]
    elseif callee == 7 then   -- rawset(t, k, v)
        local prog = Native.Program.new({
            GTable.GenericTableOccurrence.settable(0, 0, 1, 2),
        }, 4, 1, bank, 16384, 0, heap)
        local rs = prog:new_frame()
        rs.values[0] = frame.values[A + 1]
        rs.values[1] = frame.values[A + 2]
        rs.values[2] = frame.values[A + 3]
        local rsst = prog:execute(rs)
        prog:free()
        assert(rsst == bank.status.completed, ("rawset status %d"):format(tonumber(rsst)))
    else
        error("unhandled builtin " .. tostring(callee))
    end
end

-- select("#", ...) -> the count.
do
    local frame = call_frame()
    set_closure(frame, 0, SELECT.reference)
    frame:set_short_string(1, heap:short_string("#"))
    frame:set_integer(2, 10):set_integer(3, 20):set_integer(4, 30)
    dispatch(frame, 0, 5)   -- B = 5 -> 3 args after the "#"
    assert(tonumber(frame:integer(0)) == 3)
end
-- select(2, ...) -> the 2nd vararg.
do
    local frame = call_frame()
    set_closure(frame, 0, SELECT.reference)
    frame:set_integer(1, 2)
    frame:set_integer(2, 10):set_integer(3, 20):set_integer(4, 30)
    dispatch(frame, 0, 5)
    assert(tonumber(frame:integer(0)) == 20)
end

-- rawget(t, k) via the native gettable leaf.
do
    local t = heap:table(3, 2)
    t:set_array_integer(1, 41):set_array_integer(2, 52)
    t:set_field_integer(heap:short_string("k"), 63)
    local frame = call_frame()
    set_closure(frame, 0, RAWGET.reference)
    frame:set_table(1, t)
    frame:set_integer(2, 2)
    dispatch(frame, 0, 3)
    assert(tonumber(frame:integer(0)) == 52)
    local frame2 = call_frame()
    set_closure(frame2, 0, RAWGET.reference)
    frame2:set_table(1, t)
    frame2:set_short_string(2, heap:short_string("k"))
    dispatch(frame2, 0, 3)
    assert(tonumber(frame2:integer(0)) == 63)
end

-- rawset(t, k, v) via the native settable leaf.
do
    local t = heap:table(3, 2)
    t:set_array_integer(1, 1)
    local frame = call_frame()
    set_closure(frame, 0, RAWSET.reference)
    frame:set_table(1, t)
    frame:set_integer(2, 2)
    frame:set_integer(3, 99)
    dispatch(frame, 0, 4)
    assert(tonumber(t:array_value(2).payload.integer) == 99)
end

-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 builtins oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_select(args)
    local script = table.concat({
        "print(select(\"#\", ", table.concat(args, ", "), "))",
        "print(select(2, ", table.concat(args, ", "), "))",
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_builtins.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_builtins.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    local numbers = {}
    for n in out:gmatch("(-?%d+)") do numbers[#numbers + 1] = tonumber(n) end
    return numbers
end

for _, args in ipairs({ { "10", "20", "30" }, { "7" }, { "1", "2", "3", "4" } }) do
    local frame = call_frame()
    set_closure(frame, 0, SELECT.reference)
    frame:set_short_string(1, heap:short_string("#"))
    for i = 2, #args + 1 do frame:set_integer(i, tonumber(args[i - 1])) end
    dispatch(frame, 0, #args + 2)
    local native_count = tonumber(frame:integer(0))
    local expected = stock_select(args)
    assert(native_count == expected[1], ("select # %s"):format(table.concat(args, ",")))
end

rawget_program:free()
rawset_program:free()
heap:free()
print("Lua55 builtins: ok select/rawget/rawset + 3 differential cases native == stock")
