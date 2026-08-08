package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Pow = require("experiments.copy_patch_cps.lua55_trace.opcode_pow")

local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_pow_fixture")
local main = Undump.undump(bytes)
local proto = assert(main.protos[1])
assert(proto.code[1].name == "POW" and proto.code[2].name == "MMBIN")
assert(proto.code[3].name == "POWK" and proto.code[4].name == "MMBINK")

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_pow/bank.lua"))

-- Path [0, 6): POW(0, owns MMBIN at 1) POWK(2, owns MMBINK at 3) MOVE MOVE.
local path = Projection.project(proto, 0, 6)
assert(getmetatable(path) == Projection.DecodedPath and #path.occurrences == 4)
local program = path:new_program(6, bank)
local frame = program:new_frame():set_integer(0, 2):set_integer(1, 3)

assert(program:execute(frame) == bank.status.completed)
assert(frame:tag(2) == bank.tags.floating and frame:floating(2) == 8.0)  -- 2^3
assert(frame:tag(3) == bank.tags.floating and frame:floating(3) == 4.0)  -- 2^2 (a*a fast path)

-- Re-execution follows the same residual (same int-int leaf).
for _ = 1, 100 do
    local f = program:new_frame():set_integer(0, 2):set_integer(1, 3)
    assert(program:execute(f) == bank.status.completed)
    assert(f:floating(2) == 8.0 and f:floating(3) == 4.0)
end

-- Guard: a float base fails at the POW pc (0) on re-entry (int-int leaf).
do
    local f = program:new_frame():set_float(0, 2.5):set_integer(1, 2)
    assert(program:execute(f) == bank.status.guard_failed)
    assert(f.frame.resume_pc == 0)
end

-- Guard: a string base fails at the POW pc (0) on re-entry.
do
    local h = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1").GuestHeap.new(7)
    local s = h:short_string("x")
    local p2 = Native.Program.new({
        Pow.PowOccurrence.new(0, 2, 0, 1), Pow.PowKOccurrence.new(2, 3, 0, { t = "int", v = 2 }),
        Native.MoveOccurrence.new(4, 4, 2), Native.MoveOccurrence.new(5, 5, 3),
    }, 6, 6, bank, 16384, 0, h)
    local f = p2:new_frame():set_integer(0, 2):set_integer(1, 3)
    assert(p2:execute(f) == bank.status.completed)
    f:set_short_string(0, s):set_integer(1, 2)
    assert(p2:execute(f) == bank.status.guard_failed)
    assert(f.frame.resume_pc == 0)
    p2:free()
    h:free()
end
program:free()

-- Rejection: non-numeric operands reject at learn time (host __pow).
do
    local h = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1").GuestHeap.new(11)
    local s = h:short_string("x")
    local reject_program = Native.Program.new({
        Pow.PowOccurrence.new(0, 2, 0, 1), Pow.PowKOccurrence.new(2, 3, 0, { t = "int", v = 2 }),
        Native.MoveOccurrence.new(4, 4, 2), Native.MoveOccurrence.new(5, 5, 3),
    }, 6, 6, bank, 16384, 0, h)
    local f = reject_program:new_frame():set_short_string(0, s):set_integer(1, 2)
    assert(reject_program:execute(f) == bank.status.rejected)
    reject_program:free()
    h:free()
end

-- ---------------------------------------------------------------------
-- Leaf-level differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 pow oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_eval(expr)
    local script = "local r = " .. expr .. "; if type(r) == \"number\" and math.type(r) == \"integer\" then print(\"i\", r) else print(\"d\", string.format(\"%.17g\", r)) end"
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_pow.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_pow.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    local kind, value = out:match("^(%a)%s+(%S+)")
    assert(kind, "unparseable stock output: " .. out)
    if kind == "i" then return { t = "int", v = tonumber(value) } end
    return { t = "dbl", v = tonumber(value) }
end

local ALL_ONES = Native.ffi.cast("uint64_t", -1)
local MININT = Native.ffi.cast("int64_t", ALL_ONES - ALL_ONES / 2)
local MAXINT = Native.ffi.cast("int64_t", ALL_ONES / 2)

local function fmt(v)
    if v.t ~= "int" then
        local text = ("%.17g"):format(v.v)
        if not text:find("[.eE]") and not text:find("[a-zA-Z]") then text = text .. ".0" end
        return "(" .. text .. ")"
    end
    if v.v == MININT then return "(-9223372036854775807 - 1)" end
    if type(v.v) == "cdata" then
        local text = tostring(v.v):gsub("L+$", "")
        return "(" .. text .. ")"
    end
    return ("(%d)"):format(v.v)
end

local function set_value(frame, index, v)
    if v.t == "int" then return frame:set_integer(index, v.v) end
    return frame:set_float(index, v.v)
end

local function equal_value(a, b)
    if a.t ~= b.t then return false end
    if a.t == "int" then return a.v == b.v end
    if a.v ~= a.v and b.v ~= b.v then return true end
    return a.v == b.v
end

local values = {
    { t = "int", v = 7 }, { t = "int", v = -3 }, { t = "int", v = 0 },
    { t = "int", v = 2 }, { t = "int", v = MININT }, { t = "int", v = MAXINT },
    { t = "dbl", v = 3.0 }, { t = "dbl", v = 2.5 }, { t = "dbl", v = -2.5 },
    { t = "dbl", v = 0.5 }, { t = "dbl", v = 0.0 }, { t = "dbl", v = -0.0 },
    { t = "dbl", v = 1e300 }, { t = "dbl", v = 1e-300 },
}

local leaf_count = 0
local function check(name, a, b, expr, result, status)
    if status ~= bank.status.completed then
        assert(status == bank.status.rejected,
            ("%s %s: unexpected status"):format(name, tostring(a.v)))
        return
    end
    local stock_result = stock_eval(expr)
    assert(equal_value(result, stock_result),
        ("%s %s ^ %s: native=%s:%s stock=%s:%s"):format(name, fmt(a), fmt(b),
            result.t, tostring(result.v), stock_result.t, tostring(stock_result.v)))
    leaf_count = leaf_count + 1
end

local function leaf_native(frame)
    if frame:tag(1) == bank.tags.floating then return { t = "dbl", v = tonumber(frame:floating(1)) } end
    return { t = "int", v = tonumber(frame:integer(1)) }
end

-- POW (38): register-register leaves.
for _, a in ipairs(values) do
    for _, b in ipairs(values) do
        local occurrence = Pow.PowOccurrence.new(0, 1, 0, 1)
        local program = Native.Program.new({ occurrence }, 3, 2, bank, 16384, 0, nil)
        local frame = program:new_frame()
        set_value(frame, 0, a); set_value(frame, 1, b)
        local status = program:execute(frame)
        check("pow", a, b, fmt(a) .. "^" .. fmt(b), leaf_native(frame), status)
        program:free()
    end
end

-- POWK (26): register-constant leaves (constants include int and float).
local constants = {
    { t = "int", v = 2 }, { t = "int", v = -1 }, { t = "int", v = 3 },
    { t = "flt", v = 2.5 }, { t = "flt", v = 0.5 },
}
for _, c in ipairs(constants) do
    for _, a in ipairs(values) do
        local occurrence = Pow.PowKOccurrence.new(0, 1, 0, c)
        local program = Native.Program.new({ occurrence }, 3, 2, bank, 16384, 0, nil)
        local frame = program:new_frame()
        set_value(frame, 0, a)
        local status = program:execute(frame)
        local expr = fmt(a) .. "^" .. fmt(c)
        check("powk", a, c, expr, leaf_native(frame), status)
        program:free()
    end
end

print(("Lua55 pow: ok patched libm pow + %d leaf cases native == stock"):format(leaf_count))
