package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_vararg/bank.lua"))

local heap = Heap.GuestHeap.new(23)

-- The vararg function: VARARGPREP + VARARG + MOVEs + RETURN. The host
-- arranges the frame (extra args in R[numparams..], vararg_count set);
-- the path starts after the VARARGPREP boundary.
local main = Undump.undump(require("experiments.copy_patch_cps.lua55_trace.opcode_vararg_fixture"))
local proto = assert(main.protos[1])
assert(proto.code[1].name == "VARARGPREP" and proto.code[2].name == "VARARG")
local path = Projection.project(proto, 1, 6, heap)
assert(#path.occurrences == 5)

local function vararg_frame(args)
    local frame = Native.FrameOwner.new(proto.maxstacksize, #path.occurrences,
        #proto.upvals, heap, false)
    frame:set_varargs(#args)
    for i = 1, #args do
        if args[i].t == "int" then frame:set_integer(i - 1, args[i].v)
        else frame:set_float(i - 1, args[i].v) end
    end
    return frame
end

local function run_vararg(args)
    local program = path:new_program(6, bank)
    local frame = vararg_frame(args)
    local status = program:execute(frame)
    program:free()
    assert(status == bank.status.completed)
    return frame
end

-- VARARG copies min(2, count) varargs into R1, R2; the returns carry them.
do
    local frame = run_vararg({ { t = "int", v = 10 }, { t = "int", v = 20 }, { t = "int", v = 30 } })
    assert(tonumber(frame:integer(1)) == 10 and tonumber(frame:integer(2)) == 20)
    assert(tonumber(frame:integer(3)) == 10 and tonumber(frame:integer(4)) == 20)
end
do
    -- only one vararg: b stays nil
    local frame = run_vararg({ { t = "int", v = 7 } })
    assert(tonumber(frame:integer(1)) == 7)
    assert(frame:tag(2) == bank.tags.nil_value)
end
do
    -- float varargs flow through
    local frame = run_vararg({ { t = "flt", v = 2.5 }, { t = "int", v = 3 } })
    assert(frame:tag(1) == bank.tags.floating and frame:floating(1) == 2.5)
    assert(tonumber(frame:integer(2)) == 3)
end

-- Re-execution on the residual recomputes from the current frame.
do
    local program = path:new_program(6, bank)
    local frame = vararg_frame({ { t = "int", v = 1 }, { t = "int", v = 2 } })
    assert(program:execute(frame) == bank.status.completed)
    frame:set_integer(1, 11)  -- the vararg source R1 itself changes
    assert(program:execute(frame) == bank.status.completed)
    assert(tonumber(frame:integer(1)) == 1 and tonumber(frame:integer(2)) == 11)
    program:free()
end

-- GETVARG leaf: R[A] = the vararg at the runtime index R[C], or the count
-- for the "n" string; out-of-range / other keys produce nil.
do
    local getvarg = require("experiments.copy_patch_cps.lua55_trace.opcode_vararg").GetVargOccurrence
    local function leaf(args, key_set, nfix)
        local program = Native.Program.new({ getvarg.new(0, 1, nfix, 3) }, 4, 1, bank, 16384, 0, heap)
        local frame = Native.FrameOwner.new(4, 1, 0, heap, false)
        frame:set_varargs(#args)
        for i = 1, #args do frame:set_integer(i - 1, args[i]) end
        if key_set == "n" then frame:set_short_string(3, heap:short_string("n"))
        else frame:set_integer(3, key_set) end
        assert(program:execute(frame) == bank.status.completed)
        program:free()
        return frame
    end
    -- nth vararg
    local lf = leaf({ 10, 20, 30 }, 1, 0)
    assert(tonumber(lf:integer(1)) == 10, ("leaf(1): %s"):format(tostring(lf:integer(1))))
    local lf3 = leaf({ 10, 20, 30 }, 3, 0)
    assert(tonumber(lf3:integer(1)) == 30, ("leaf(3): %s"):format(tostring(lf3:integer(1))))
    assert(leaf({ 10, 20, 30 }, 5, 0):tag(1) == bank.tags.nil_value)  -- out of range
    -- the "n" count
    assert(tonumber(leaf({ 10, 20, 30 }, "n", 0):integer(1)) == 3)
    -- fixed params: nfix shifts the vararg base
    assert(tonumber(leaf({ 10, 20, 30 }, 1, 1):integer(1)) == 20)
end

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 vararg oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_vararg(values)
    local script = table.concat({
        "local function f(...) local a, b = ... return a, b end",
        "print(f(", table.concat(values, ", "), "))",
    }, "\n")
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_vararg.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_vararg.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    local numbers = {}
    for n in out:gmatch("(-?%d+)") do numbers[#numbers + 1] = tonumber(n) end
    return numbers
end

local cases = {
    { "10", "20", "30" },
    { "7" },
    { "1", "2" },
    { "5", "6", "7", "8" },
}
for _, values in ipairs(cases) do
    local args = {}
    for i, v in ipairs(values) do args[i] = { t = "int", v = tonumber(v) } end
    local frame = run_vararg(args)
    local native_a = tonumber(frame:integer(1))
    local native_b = frame:tag(2) == bank.tags.integer and tonumber(frame:integer(2)) or nil
    local expected = stock_vararg(values)
    local exp_a, exp_b = expected[1], expected[2]
    assert(native_a == exp_a and native_b == exp_b,
        ("vararg(%s): native=%s,%s stock=%s,%s"):format(table.concat(values, ","),
            tostring(native_a), tostring(native_b), tostring(exp_a), tostring(exp_b)))
end

heap:free()
print("Lua55 vararg: ok host-arranged varargs + GETVARG leaf + 4 differential cases native == stock")
