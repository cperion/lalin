package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Compare = require("experiments.copy_patch_cps.lua55_trace.opcode_compare")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")

local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_compare_fixture")
local main = Undump.undump(bytes)
local proto = assert(main.protos[1])

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_compare/bank.lua"))

-- Path [0, 16): LT+JMP, LFALSESKIP, LOADTRUE, LE+JMP, LFALSESKIP, LOADTRUE,
-- EQ(k1)+JMP, LFALSESKIP, LOADTRUE, EQ(k0)+JMP, LFALSESKIP, LOADTRUE
local heap = Heap.GuestHeap.new(53)
local path = Projection.project(proto, 0, 16, heap)
assert(#path.occurrences == 8, "comparison path occurrence count changed")
local program = path:new_program(16, bank)

local function run(x, y)
    local frame = program:new_frame():set_integer(0, x):set_integer(1, y)
    local status = program:execute(frame)
    assert(status == bank.status.completed, "comparison path did not complete")
    return frame, tonumber(frame.frame.resume_pc)
end

-- (5, 3): all comparisons false; the final EQ(k=0) takes its branch to pc 15.
do
    local frame, resume = run(5, 3)
    assert(resume == 15, "EQ k=0 branch target")
    assert(frame:tag(2) == bank.tags.false_value and frame:tag(3) == bank.tags.false_value)
    assert(frame:tag(4) == bank.tags.false_value)
    assert(frame:tag(5) == bank.tags.nil_value)  -- exit happened before LOADTRUE 15
end

-- (3, 5): LT is true; k=1 branch taken to pc 3.
do
    local frame, resume = run(3, 5)
    assert(resume == 3, "LT k=1 branch target")
    assert(frame:tag(2) == bank.tags.nil_value)
end

-- (5, 5): LT false, LE true; exit at pc 7.
do
    local frame, resume = run(5, 5)
    assert(resume == 7, "LE k=1 branch target")
    assert(frame:tag(2) == bank.tags.false_value and frame:tag(3) == bank.tags.nil_value)
end

-- Re-execution after install follows the same path.
for _ = 1, 100 do
    local frame, resume = run(5, 3)
    assert(resume == 15)
end

-- Guard: changing operand tags between learn and residual fails at the LT pc.
do
    local frame = program:new_frame():set_float(0, 5):set_integer(1, 3)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 0)
end

program:free()

-- Leaf-level differential oracle: branch decision must match stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local values = {
    { t = "int", v = 3 }, { t = "int", v = -7 }, { t = "int", v = 2 },
    { t = "dbl", v = 3.0 }, { t = "dbl", v = 2.5 }, { t = "dbl", v = -2.5 },
    { t = "int", v = 4503599627370496 },   -- 2^52 edge
    { t = "int", v = 9007199254740993 },   -- 2^53 + 1 (not float-exact)
    { t = "dbl", v = 1e300 },
    { t = "str", v = "abc" }, { t = "str", v = "abd" }, { t = "str", v = "" },
    { t = "nil" }, { t = "false" }, { t = "true" },
}
local ops = { { 57, "EQ", "==" }, { 58, "LT", "<" }, { 59, "LE", "<=" } }

local function stock_line(a, b, op)
    local function lua(v)
        if v.t == "nil" then return "nil" end
        if v.t == "false" then return "false" end
        if v.t == "true" then return "true" end
        if v.t == "int" then return tostring(v.v) end
        if v.t == "dbl" then return string.format("%.17g", v.v) end
        return ("%q"):format(v.v)
    end
    local script = ("local a = %s; local b = %s; print(a %s b)"):format(
        lua(a), lua(b), op)
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_cmp.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_cmp.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    if out:match("^true") then return true end
    if out:match("^false") then return false end
    error("unexpected stock oracle output: " .. out)
end

local function set_value(frame, index, v)
    if v.t == "nil" then return frame:set_nil(index) end
    if v.t == "false" then return frame:set_false(index) end
    if v.t == "true" then return frame:set_true(index) end
    if v.t == "int" then return frame:set_integer(index, v.v) end
    if v.t == "dbl" then return frame:set_float(index, v.v) end
    local owner = heap:short_string(v.v)
    return frame:set_short_string(index, owner)
end

local leaf_count = 0
for _, op in ipairs(ops) do
    local opcode, name, symbol = op[1], op[2], op[3]
    for _, a in ipairs(values) do
        for _, b in ipairs(values) do
            for k = 0, 1 do
                -- LT/LE require both numeric or both string (stock errors otherwise)
                local a_num = a.t == "int" or a.t == "dbl"
                local b_num = b.t == "int" or b.t == "dbl"
                local a_str = a.t == "str"
                local b_str = b.t == "str"
                if opcode == 57 or (a_num and b_num) or (a_str and b_str) then
                    local occurrence
                    if opcode == 57 then
                        occurrence = Compare.EqOccurrence.new(0, 0, 1, k, 2)
                    elseif opcode == 58 then
                        occurrence = Compare.LtOccurrence.new(0, 0, 1, k, 2)
                    else
                        occurrence = Compare.LeOccurrence.new(0, 0, 1, k, 2)
                    end
                    local leaf = Native.Program.new({ occurrence }, 2, 9, bank, nil, 0, heap)
                    local frame = leaf:new_frame()
                    set_value(frame, 0, a)
                    set_value(frame, 1, b)
                    assert(leaf:execute(frame) == bank.status.completed)
                    local taken = frame.frame.resume_pc == 2
                    local stock = stock_line(a, b, symbol)
                    local expected = (stock == true and k == 1) or (stock == false and k == 0)
                    if taken ~= expected then
                        error(("%s %s %s k=%d: native taken=%s stock=%s"):format(
                            name, tostring(a.t), tostring(b.t), k, tostring(taken), tostring(stock)))
                    end
                    leaf_count = leaf_count + 1
                    leaf:free()
                end
            end
        end
    end
end

heap:free()
print(("Lua55 comparisons: ok owned-JMP residuals + %d leaf cases native == stock"):format(leaf_count))
