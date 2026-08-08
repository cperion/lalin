package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Arith = require("experiments.copy_patch_cps.lua55_trace.opcode_arith")

local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_arith_fixture")
local main = Undump.undump(bytes)
local proto = assert(main.protos[1])

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_arith/bank.lua"))

-- Path [0, 28): ADD SUB MUL IDIV MOD DIV BAND BOR BXOR SHRI SHRI SHLI ADDI MULK
local path = Projection.project(proto, 0, 28)
assert(#path.occurrences == 14, "arithmetic path occurrence count changed")
local program = path:new_program(28, bank)

local function run(a, b)
    local frame = program:new_frame():set_integer(0, a):set_integer(1, b)
    local status = program:execute(frame)
    assert(status == bank.status.completed, "arithmetic path did not complete")
    return frame
end

-- (7, 3): all int results except DIV and MULK(2.5).
do
    local frame = run(7, 3)
    local expected = {
        [2] = 10, [3] = 4, [4] = 21, [5] = 2, [6] = 1,       -- + - * // % 
        [8] = 3, [9] = 7, [10] = 4,                            -- & | ~
        [11] = 28, [12] = 1, [13] = 256, [14] = 12,            -- <<2 >>2 2<<a +5
    }
    for reg, value in pairs(expected) do
        assert(frame:tag(reg) == bank.tags.integer, ("reg %d tag"):format(reg))
        assert(tonumber(frame:integer(reg)) == value, ("reg %d value"):format(reg))
    end
    assert(frame:tag(7) == bank.tags.floating and frame:floating(7) == 7.0 / 3.0)
    assert(frame:tag(15) == bank.tags.floating and frame:floating(15) == 7.0 * 2.5)
end

-- Re-execution follows the same path.
for _ = 1, 100 do
    local frame = run(9, 4)
    assert(tonumber(frame:integer(2)) == 13)
end

-- Guard: tag change between learn and residual fails at the first arithmetic pc.
do
    local frame = program:new_frame():set_float(0, 7):set_integer(1, 3)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 0)
end

-- Integer zero divisor exits at the IDIV pc (6) with COMPLETED, no state change.
do
    local frame = program:new_frame():set_integer(0, 7):set_integer(1, 0)
    assert(program:execute(frame) == bank.status.completed)
    assert(frame.frame.resume_pc == 6)
end

program:free()

-- Leaf-level differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 arith oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_eval(expr)
    local script = "local r = " .. expr .. "; if type(r) == \"number\" and math.type(r) == \"integer\" then print(\"i\", r) else print(\"d\", string.format(\"%.17g\", r)) end"
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_arith.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_arith.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    local kind, value = out:match("^(%a)%s+(%S+)")
    assert(kind, "unparseable stock output: " .. out)
    if kind == "i" then return { t = "int", v = tonumber(value) } end
    return { t = "dbl", v = tonumber(value) }
end

local ALL_ONES = Native.ffi.cast("uint64_t", -1)
local MININT = Native.ffi.cast("int64_t", ALL_ONES - ALL_ONES / 2)
local MAXINT = Native.ffi.cast("int64_t", ALL_ONES / 2)

local function set_value(frame, index, v)
    if v.t == "int" then return frame:set_integer(index, v.v) end
    return frame:set_float(index, v.v)
end

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

local function native_value(frame, index)
    local tag = tonumber(frame:tag(index))
    if tag == 3 then return { t = "int", v = tonumber(frame:integer(index)) } end
    return { t = "dbl", v = tonumber(frame:floating(index)) }
end

local function equal_value(a, b)
    if a.t ~= b.t then return false end
    if a.t == "int" then return a.v == b.v end
    if a.v ~= a.v and b.v ~= b.v then return true end   -- NaN == NaN
    return a.v == b.v
end

local values = {
    { t = "int", v = 7 }, { t = "int", v = -3 }, { t = "int", v = 0 },
    { t = "int", v = MININT }, { t = "int", v = MAXINT },
    { t = "int", v = 3 }, { t = "int", v = 6 },
    { t = "dbl", v = 3.0 }, { t = "dbl", v = 2.5 }, { t = "dbl", v = -2.5 },
    { t = "dbl", v = 1e300 }, { t = "dbl", v = 0.0 }, { t = "dbl", v = -0.0 },
}
local shifts = {
    { t = "int", v = -1 }, { t = "int", v = 0 }, { t = "int", v = 1 },
    { t = "int", v = 62 }, { t = "int", v = 63 }, { t = "int", v = 64 }, { t = "int", v = 65 },
    { t = "dbl", v = 2.0 }, { t = "dbl", v = 62.5 },
}

local rr_ops = {
    { 34, Arith.AddOccurrence, "+", false, false }, { 35, Arith.SubOccurrence, "-", false, false },
    { 36, Arith.MulOccurrence, "*", false, false }, { 37, Arith.ModOccurrence, "%", true, false },
    { 39, Arith.DivOccurrence, "/", false, false }, { 40, Arith.IDivOccurrence, "//", true, false },
    { 41, Arith.BandOccurrence, "&", false, true }, { 42, Arith.BorOccurrence, "|", false, true },
    { 43, Arith.BXorOccurrence, "~", false, true },
}
local ri_ops = {
    { 21, Arith.AddIOccurrence, "+ 5", false }, { 32, Arith.ShlIOccurrence, nil, false },
    { 33, Arith.ShrIOccurrence, nil, false },
}
local rk_ops = {
    { 22, Arith.AddKOccurrence, "+ 5", false }, { 23, Arith.SubKOccurrence, "- 5", false },
    { 24, Arith.MulKOccurrence, "* 2.5", false }, { 27, Arith.DivKOccurrence, "/ 2.5", false },
    { 28, Arith.IDivKOccurrence, "// 5", true }, { 25, Arith.ModKOccurrence, "% 5", true },
    { 29, Arith.BandKOccurrence, "& 6", false }, { 30, Arith.BorKOccurrence, "| 6", false },
    { 31, Arith.BXorKOccurrence, "~ 6", false },
}

local leaf_count = 0
local function check(name, a, b, expr, native_result, zero_expect, resume_pc)
    if zero_expect then
        if a.t == "int" and b.t == "int" and b.v == 0 then
            assert(native_result == "zero", ("%s(%s,%s): expected zero exit"):format(name, fmt(a), fmt(b)))
            assert(resume_pc == 0, ("%s zero exit pc"):format(name))
            return
        end
    end
    if native_result == "zero" then
        error(("%s(%s,%s): unexpected zero exit"):format(name, fmt(a), fmt(b)))
    end
    local stock_result = stock_eval(expr)
    if not equal_value(native_result, stock_result) then
        print("MISMATCH expr=" .. expr)
        print("  a=", a.t, a.v, "b=", b.t, b.v)
        print("  native=", native_result.t, native_result.v, "stock=", stock_result.t, stock_result.v)
    end
    assert(equal_value(native_result, stock_result),
        ("%s %s %s: native=%s:%s stock=%s:%s"):format(name, fmt(a), fmt(b),
            native_result.t, tostring(native_result.v), stock_result.t, tostring(stock_result.v)))
    leaf_count = leaf_count + 1
end

for _, op in ipairs(rr_ops) do
    local opcode, klass, symbol, zero, coerce = op[1], op[2], op[3], op[4], op[5]
    for _, a in ipairs(values) do
        for _, b in ipairs(values) do
            local function coercible(v)
                return v == math.floor(v) and v >= -9223372036854775808.0 and v < 9223372036854775808.0
            end
            if coerce and ((a.t == "dbl" and not coercible(a.v))
                or (b.t == "dbl" and not coercible(b.v))) then goto continue end
            if (a.t == "dbl" or b.t == "dbl") and zero then
                if type(a.v) ~= "number" or type(b.v) ~= "number" then goto continue end
                if math.abs(a.v / b.v) >= 4503599627370496 then goto continue end
            end
            local occurrence = klass.new(0, 2, 0, 1)
            local leaf = Native.Program.new({ occurrence }, 3, 9, bank)
            local frame = leaf:new_frame()
            set_value(frame, 0, a); set_value(frame, 1, b)
            local st = leaf:execute(frame)
            if st ~= bank.status.completed then
                print("EXEC FAIL", symbol, a.t, tostring(a.v), b.t, tostring(b.v), "status", tonumber(st))
                os.exit(1)
            end
            local result, resume = native_value(frame, 2), frame.frame.resume_pc
            if a.t == "int" and b.t == "int" and b.v == 0 and zero then result = "zero" end
            if (a.t == "dbl" or b.t == "dbl") and zero
                and type(a.v) == "number" and type(b.v) == "number"
                and math.abs(a.v / b.v) >= 4503599627370496 then goto continue end
            check(("%s(rr)"):format(symbol), a, b, fmt(a) .. symbol .. fmt(b), result, zero, resume)
            leaf:free()
            ::continue::
        end
    end
end

for _, op in ipairs(rk_ops) do
    local opcode, klass, expr = op[1], op[2], op[3]
    local symbol = expr:match("^%s*(%S+)")
    local zero_k = symbol == "//" or symbol == "%"
    local coerce_k = symbol == "&" or symbol == "|" or symbol == "~"
    for _, a in ipairs(values) do
        local constant = expr:find("2.5") and { t = "flt", v = 2.5 } or { t = "int", v = 5 }
        if expr:find("6") then constant = { t = "int", v = 6 } end
        if coerce_k and a.t == "dbl" then
            if a.v ~= math.floor(a.v) or a.v >= 9223372036854775808.0 or a.v < -9223372036854775808.0 then goto continue end
        end
        if zero_k and (a.t == "dbl" or constant.t == "dbl") then
            if type(a.v) ~= "number" or math.abs(a.v / constant.v) >= 4503599627370496 then goto continue end
        end
        local occurrence = klass.new(0, 2, 0, constant)
        local leaf = Native.Program.new({ occurrence }, 3, 9, bank)
        local frame = leaf:new_frame()
        set_value(frame, 0, a)
        local st = leaf:execute(frame)
        if st ~= bank.status.completed then
            print("RK EXEC FAIL", symbol, a.t, tostring(a.v), "status", tonumber(st))
            os.exit(1)
        end
        local result = native_value(frame, 2)
        check(("%s(k)"):format(symbol), a, constant, fmt(a) .. expr, result, false, nil)
        leaf:free()
        ::continue::
    end
end

-- shifts (register-register + immediate)
for _, count in ipairs(shifts) do
    for _, a in ipairs({ { t = "int", v = 7 }, { t = "int", v = -7 }, { t = "dbl", v = 7.0 } }) do
        local occ_s = Arith.ShlOccurrence.new(0, 2, 0, 1)
        local leaf = Native.Program.new({ occ_s }, 3, 9, bank)
        local frame = leaf:new_frame()
        set_value(frame, 0, a); set_value(frame, 1, count)
        local ok = leaf:execute(frame) == bank.status.completed
        if ok then
            local result = native_value(frame, 2)
            check("<<", a, count, fmt(a) .. " << " .. fmt(count), result, false, nil)
        end
        leaf:free()
        local occ_r = Arith.ShrOccurrence.new(0, 2, 0, 1)
        leaf = Native.Program.new({ occ_r }, 3, 9, bank)
        frame = leaf:new_frame()
        set_value(frame, 0, a); set_value(frame, 1, count)
        ok = leaf:execute(frame) == bank.status.completed
        if ok then
            local result = native_value(frame, 2)
            check(">>", a, count, fmt(a) .. " >> " .. fmt(count), result, false, nil)
        end
        leaf:free()
    end
end

print(("Lua55 arithmetic: ok owned-companion residuals + %d leaf cases native == stock"):format(leaf_count))
