package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Unary = require("experiments.copy_patch_cps.lua55_trace.opcode_unary")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")

local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_unary_fixture")
local main = Undump.undump(bytes)
local proto = assert(main.protos[1])
assert(proto.code[1].name == "UNM" and proto.code[2].name == "BNOT")
assert(proto.code[3].name == "NOT" and proto.code[4].name == "LEN")
assert(proto.code[5].name == "LEN")

local heap = Heap.GuestHeap.new(23)
local table_owner = heap:table(4, 0)
table_owner:set_array_integer(1, 10)
table_owner:set_array_integer(2, 20)
table_owner:set_array_integer(3, 30)
local str_owner = heap:short_string("hello")

local path = Projection.project(proto, 0, 10, heap)
assert(getmetatable(path) == Projection.DecodedPath and #path.occurrences == 10)

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_unary/bank.lua"))
local program = path:new_program(10, bank)
local frame = program:new_frame():set_integer(0, 7)
    :set_short_string(1, str_owner):set_table(2, table_owner)

assert(program:execute(frame) == bank.status.completed)
assert(frame:tag(3) == bank.tags.integer and tonumber(frame:integer(3)) == -7)
assert(frame:tag(4) == bank.tags.integer and tonumber(frame:integer(4)) == -8)
assert(frame:tag(5) == bank.tags.false_value)
assert(frame:tag(6) == bank.tags.integer and tonumber(frame:integer(6)) == 5)
assert(frame:tag(7) == bank.tags.integer and tonumber(frame:integer(7)) == 3)

-- Re-execution follows the same residual; LEN recomputes the current length.
for _ = 1, 100 do
    local f = program:new_frame():set_integer(0, 9)
        :set_short_string(1, str_owner):set_table(2, table_owner)
    assert(program:execute(f) == bank.status.completed)
    assert(tonumber(f:integer(3)) == -9 and tonumber(f:integer(4)) == -10)
    assert(tonumber(f:integer(7)) == 3)
end

-- Table LEN recomputes: extend the array, length follows.
do
    table_owner:set_array_integer(4, 40)
    local f = program:new_frame():set_integer(0, 7)
        :set_short_string(1, str_owner):set_table(2, table_owner)
    assert(program:execute(f) == bank.status.completed)
    assert(tonumber(f:integer(7)) == 4)
end

-- Guard: source tag change fails at the first unary pc (0).
do
    local f = program:new_frame():set_float(0, 7)
        :set_short_string(1, str_owner):set_table(2, table_owner)
    assert(program:execute(f) == bank.status.guard_failed)
    assert(f.frame.resume_pc == 0)
end

-- A same-shape table in the register is a legit new input: LEN recomputes
-- the current table's length (shape decision, not identity).
do
    local alien = heap:table(2, 0):set_array_integer(1, 1)
    local f = program:new_frame():set_integer(0, 7)
        :set_short_string(1, str_owner):set_table(2, alien)
    assert(program:execute(f) == bank.status.completed)
    assert(tonumber(f:integer(7)) == 1)
end
program:free()

-- Rejection: the same unary program with a string in x rejects at pc 0.
do
    local reject_program = Native.Program.new({
        Unary.UnmOccurrence.new(0, 3, 0), Unary.BnotOccurrence.new(1, 4, 0),
        Unary.NotOccurrence.new(2, 5, 0), Unary.LenOccurrence.new(3, 6, 0),
        Unary.LenOccurrence.new(4, 7, 1),
        Native.MoveOccurrence.new(5, 8, 3), Native.MoveOccurrence.new(6, 9, 4),
        Native.MoveOccurrence.new(7, 10, 5), Native.MoveOccurrence.new(8, 11, 6),
        Native.MoveOccurrence.new(9, 12, 7),
    }, 13, 10, bank, 16384, 0, heap)
    local f = reject_program:new_frame():set_short_string(0, str_owner)
        :set_short_string(1, str_owner):set_table(2, table_owner)
    assert(reject_program:execute(f) == bank.status.rejected)
    reject_program:free()
end
heap:free()

-- ---------------------------------------------------------------------
-- Leaf-level differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 unary oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_eval(expr)
    local script = table.concat({
        "local r = ", expr,
        " if type(r) == \"number\" and math.type(r) == \"integer\" then print(\"i\", r)",
        " elseif type(r) == \"boolean\" then print(\"b\", tostring(r))",
        " else print(\"d\", string.format(\"%.17g\", r)) end",
    })
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_unary.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_unary.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    local kind, value = out:match("^(%a)%s+(%S+)")
    assert(kind, "unparseable stock output: " .. out)
    if kind == "i" then return { t = "int", v = tonumber(value) } end
    if kind == "b" then return { t = value == "true", is_bool = true } end
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
    if v.t == "nil" then return frame:set_nil(index) end
    if v.t == "false" then return frame:set_false(index) end
    if v.t == "true" then return frame:set_true(index) end
    return frame:set_float(index, v.v)
end

local leaf_count = 0
local function run_leaf(klass, source, heap_owner)
    local occurrence = klass.new(0, 1, 0)
    local program = Native.Program.new({ occurrence }, 2, 1, bank, 16384, 0, heap_owner)
    local frame = program:new_frame()
    set_value(frame, 0, source)
    local status = program:execute(frame)
    local result = { status = status, frame = frame }
    program:free()
    return result
end

local function leaf_native(frame)
    if frame:tag(1) == bank.tags.integer then
        return { t = "int", v = tonumber(frame:integer(1)) }
    end
    if frame:tag(1) == bank.tags.floating then
        return { t = "dbl", v = tonumber(frame:floating(1)) }
    end
    local tag = tonumber(frame:tag(1))
    if tag == bank.tags.false_value then return { t = false, is_bool = true } end
    if tag == bank.tags.true_value then return { t = true, is_bool = true } end
    error("unexpected leaf tag " .. tag)
end

local function equal_value(a, b)
    if a.is_bool or b.is_bool then return a.t == b.t end
    if a.t ~= b.t then return false end
    if a.t == "int" then return a.v == b.v end
    if a.v ~= a.v and b.v ~= b.v then return true end
    return a.v == b.v
end

local function check(name, source, expr, result, heap_owner)
    if result.status ~= bank.status.completed then
        assert(result.status == bank.status.rejected,
            ("%s %s: unexpected status %d"):format(name, tostring(source.v), tonumber(result.status)))
        return -- stock raises/uses a metamethod; the native reject matches
    end
    local native = leaf_native(result.frame)
    local stock_result = stock_eval(expr)
    if not equal_value(native, stock_result) then
        print("MISMATCH expr=" .. expr)
        print("  source=", source.t, tostring(source.v))
        print("  native=", native.t, tostring(native.v),
            "stock=", stock_result.t, tostring(stock_result.v))
    end
    assert(equal_value(native, stock_result),
        ("%s %s: native=%s:%s stock=%s:%s"):format(name, fmt(source),
            native.t, tostring(native.v), stock_result.t, tostring(stock_result.v)))
    leaf_count = leaf_count + 1
end

local numbers = {
    { t = "int", v = 7 }, { t = "int", v = -3 }, { t = "int", v = 0 },
    { t = "int", v = MININT }, { t = "int", v = MAXINT },
    { t = "dbl", v = 3.0 }, { t = "dbl", v = 2.5 }, { t = "dbl", v = -2.5 },
    { t = "dbl", v = 1e300 }, { t = "dbl", v = 0.0 }, { t = "dbl", v = -0.0 },
}

-- UNM: numeric values negate (int wraps); everything else rejects (host __unm).
for _, v in ipairs(numbers) do
    check("unm", v, "-" .. fmt(v), run_leaf(Unary.UnmOccurrence, v))
end
for _, tag in ipairs({ "nil", "false", "true" }) do
    local r = run_leaf(Unary.UnmOccurrence, { t = tag, v = 0 })
    assert(r.status == bank.status.rejected, ("unm(%s) rejected"):format(tag))
end

-- BNOT: integers and integral floats complement; else reject (host __bnot).
for _, v in ipairs(numbers) do
    check("bnot", v, "~" .. fmt(v), run_leaf(Unary.BnotOccurrence, v))
end

-- NOT: total; every value maps to its truthiness.
do
    for _, v in ipairs(numbers) do
        check("not", v, "not " .. fmt(v), run_leaf(Unary.NotOccurrence, v))
    end
    for _, tag in ipairs({ "nil", "false", "true" }) do
        local expr = tag == "true" and "true" or tag
        check("not", { t = tag, v = 0 }, "not " .. expr, run_leaf(Unary.NotOccurrence, { t = tag, v = 0 }))
    end
end

-- LEN: strings and metatable-free tables; everything else rejects (host raises).
do
    local h2 = Heap.GuestHeap.new(31)
    local short = h2:short_string("hello")
    local long = h2:long_string("a longer string")
    local strings = { { "hello", 5 }, { "a longer string", 15 }, { "", 0 } }
    for _, item in ipairs(strings) do
        local text, expected = item[1], item[2]
        local owner = text:len() <= 40 and h2:short_string(text) or h2:long_string(text)
        local program = Native.Program.new(
            { Unary.LenOccurrence.new(0, 1, 0) }, 2, 1, bank, 16384, 0, h2)
        local frame = program:new_frame()
        if #text <= 40 then frame:set_short_string(0, owner)
        else frame:set_long_string(0, owner) end
        assert(program:execute(frame) == bank.status.completed)
        assert(frame:tag(1) == bank.tags.integer and tonumber(frame:integer(1)) == expected)
        local s = stock_eval("#" .. string.format("%q", text))
        assert(s.t == "int" and s.v == expected, ("len(%q) stock"):format(text))
        program:free()
        leaf_count = leaf_count + 1
    end
    -- Table lengths: empty, sequential, holes (first boundary), non-int values.
    local tables = {
        { "{}", 0 }, { "{10}", 1 }, { "{10,20,30}", 3 },
        { "{10,nil,30}", 1 }, { "{nil,20}", 0 }, { "{10,20,nil,40}", 2 },
        { "{10,20,30,40,50}", 5 }, { "{2.5}", 1 }, { "{true}", 1 },
        { "{10,20,30,40}", 4 },
    }
    for _, item in ipairs(tables) do
        local expr, expected = item[1], item[2]
        local program = Native.Program.new(
            { Unary.LenOccurrence.new(0, 1, 0) }, 2, 1, bank, 16384, 0, h2)
        local frame = program:new_frame()
        local guest = h2:table(16, 0)
        local inner = expr:sub(2, -2)
        local n = 0
        for entry in inner:gmatch("([^,]+)") do
            n = n + 1
            local e = entry:gsub("%s+", "")
            if e ~= "nil" then
                local number = tonumber(e)
                if number then guest:set_array_integer(n, number)
                elseif e == "true" then guest:set_array_true(n)
                elseif e == "false" then guest:set_array_false(n)
                elseif e == "2.5" then guest:set_array_float(n, 2.5) end
            end
        end
        frame:set_table(0, guest)
        assert(program:execute(frame) == bank.status.completed)
        assert(frame:tag(1) == bank.tags.integer, ("len(%s) tag"):format(expr))
        assert(tonumber(frame:integer(1)) == expected,
            ("len(%s) native=%s stock=%s"):format(expr, tonumber(frame:integer(1)), expected))
        local s = stock_eval("#" .. expr)
        assert(s.t == "int" and s.v == expected, ("len(%s) stock"):format(expr))
        program:free()
        leaf_count = leaf_count + 1
    end
    -- Metatable present: __len path -> reject.
    local meta = h2:table(1, 0)
    local with_meta = h2:table(2, 0):set_array_integer(1, 9):set_metatable(meta)
    local program = Native.Program.new(
        { Unary.LenOccurrence.new(0, 1, 0) }, 2, 1, bank, 16384, 0, h2)
    local frame = program:new_frame():set_table(0, with_meta)
    assert(program:execute(frame) == bank.status.rejected, "len(metatable) rejected")
    program:free()
    -- Non-string/table sources reject (host raises).
    for _, tag in ipairs({ "nil", "false", "true" }) do
        local p = Native.Program.new(
            { Unary.LenOccurrence.new(0, 1, 0) }, 2, 1, bank, 16384, 0, h2)
        local f = p:new_frame()
        if tag == "nil" then f:set_nil(0)
        elseif tag == "false" then f:set_false(0)
        else f:set_true(0) end
        assert(p:execute(f) == bank.status.rejected, ("len(%s) rejected"):format(tag))
        p:free()
    end
    h2:free()
end

-- Guards: tag change between learn and residual fails at the unary pc.
do
    local h3 = Heap.GuestHeap.new(41)
    local program = Native.Program.new(
        { Unary.UnmOccurrence.new(0, 1, 0) }, 2, 1, bank, 16384, 0, h3)
    local frame = program:new_frame():set_integer(0, 7)
    assert(program:execute(frame) == bank.status.completed)
    frame:set_float(0, 7)
    assert(program:execute(frame) == bank.status.guard_failed)
    assert(frame.frame.resume_pc == 0)
    program:free()
    h3:free()
end

print(("Lua55 unary: ok owned residuals + %d leaf cases native == stock"):format(leaf_count))
