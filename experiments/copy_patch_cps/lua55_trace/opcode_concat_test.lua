package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local ffi = Native.ffi

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_string/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_call/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_concat/bank.lua"))

local heap = Heap.GuestHeap.new(23)

local main = Undump.undump(require("experiments.copy_patch_cps.lua55_trace.opcode_concat_fixture"))
local proto = assert(main.protos[1])
assert(proto.code[4].name == "CONCAT")

local path = Projection.project(proto, 0, 6, heap)
assert(#path.occurrences == 6)

local function program_frame()
    return Native.FrameOwner.new(proto.maxstacksize, #path.occurrences, #proto.upvals, heap, false)
end

local function string_text(ref)
    local s = ffi.cast("Lua55GuestStringV1 *", ref)
    return ffi.string(s[0].bytes, s[0].length)
end

local function run_with(a, b, c)
    local program = path:new_program(6, bank)
    local frame = program_frame()
    frame:set_short_string(0, a):set_short_string(1, b):set_short_string(2, c)
    local status = program:execute(frame)
    program:free()
    assert(status == bank.status.completed)
    return frame
end

-- Basic concat: "foo" .. "bar" .. "baz" = "foobarbaz".
do
    local frame = run_with(heap:short_string("foo"), heap:short_string("bar"), heap:short_string("baz"))
    assert(frame:tag(3) == bank.tags.short_string)
    assert(string_text(frame:reference(3)) == "foobarbaz")
end

-- Residual recompute: different operands produce a fresh string each run.
local seen = {}
for i = 1, 5 do
    local frame = run_with(heap:short_string("x" .. i), heap:short_string("-"), heap:short_string("y" .. i))
    assert(string_text(frame:reference(3)) == ("x%d-y%d"):format(i, i))
    local ref = tonumber(frame:reference(3))
    for _, r in ipairs(seen) do assert(r ~= ref, "concat reused a string") end
    seen[#seen + 1] = ref
end

-- Long string: > 40 chars yields a LONG string.
do
    local long = heap:long_string(("z"):rep(50))
    local frame = run_with(heap:short_string("a"), long, heap:short_string("b"))
    assert(frame:tag(3) == bank.tags.long_string)
    assert(string_text(frame:reference(3)) == ("a" .. ("z"):rep(50) .. "b"))
end

-- Numbers convert inline: "a" .. 7 .. "b" = "a7b"; "a" .. 2.5 .. "b" = "a2.5b".
local function run_number(a, b, c)
    local program = path:new_program(6, bank)
    local frame = program_frame()
    local function set(index, operand)
        if type(operand) == "string" then
            frame:set_short_string(index, heap:short_string(operand))
        elseif operand.t == "int" then
            frame:set_integer(index, operand.v)
        else
            frame:set_float(index, operand.v)
        end
    end
    set(0, a); set(1, b); set(2, c)
    assert(program:execute(frame) == bank.status.completed)
    program:free()
    return string_text(frame:reference(3))
end
assert(run_number("a", { t = "int", v = 7 }, "b") == "a7b")
assert(run_number("a", { t = "flt", v = 2.5 }, "b") == "a2.5b")
assert(run_number({ t = "int", v = -42 }, { t = "flt", v = 1e300 }, "!") == "-421e+300!")

-- ---------------------------------------------------------------------
-- Differential oracle vs stock Lua 5.5.
local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then print("Lua55 concat oracle: SKIPPED (stock lua missing)"); os.exit(0) end
stock:close()

local function stock_concat(a, b, c)
    local script = table.concat({
        "local s = ", string.format("%q", a), " .. ", string.format("%q", b),
        " .. ", string.format("%q", c),
        " print(#s, s)",
    })
    local file = assert(io.open("target/copy_patch_cps/lua55_trace/oracle_concat.lua", "wb"))
    file:write(script); file:close()
    local pipe = assert(io.popen(([[%s target/copy_patch_cps/lua55_trace/oracle_concat.lua]]):format(STOCK_LUA), "r"))
    local out = pipe:read("*a"); pipe:close()
    return out
end

local cases = {
    { "foo", "bar", "baz" },
    { "hello", " ", "world" },
    { "", "a", "b" },
    { "x", "y", "z" },
}
-- number operands: build the frame values by tag
local number_cases = {
    { "a", { t = "int", v = 7 }, "b" },
    { "a", { t = "flt", v = 2.5 }, "b" },
    { { t = "int", v = -42 }, { t = "flt", v = 1e300 }, "!" },
    { { t = "flt", v = 0.1 }, { t = "flt", v = 1e-300 }, "end" },
    { { t = "int", v = 9007199254740992LL }, { t = "flt", v = -2.5 }, { t = "int", v = 3 } },
}
local function set_operand(frame, index, operand)
    if type(operand) == "string" then
        frame:set_short_string(index, heap:short_string(operand))
    elseif operand.t == "int" then
        frame:set_integer(index, operand.v)
    else
        frame:set_float(index, operand.v)
    end
end
local function operand_text(operand)
    if type(operand) == "string" then return operand end
    if operand.t == "int" then return tostring(operand.v) end
    return string.format("%.14g", operand.v)
end
-- the stock's integer tostringbuff uses %lld (exact), not %.14g
local ALL_ONES2 = Native.ffi.cast("uint64_t", -1)
local function exact_int_text(v)
    local text = tostring(v):gsub("LL$", "")
    return text
end
local function number_text(operand)
    if type(operand) == "string" then return operand end
    if operand.t == "int" then return exact_int_text(operand.v) end
    return string.format("%.14g", operand.v)
end
for _, item in ipairs(number_cases) do
    local program = path:new_program(6, bank)
    local frame = program_frame()
    for i, operand in ipairs(item) do set_operand(frame, i - 1, operand) end
    assert(program:execute(frame) == bank.status.completed)
    program:free()
    local native = string_text(frame:reference(3))
    local expected = number_text(item[1]) .. number_text(item[2]) .. number_text(item[3])
    assert(native == expected,
        ("concat numbers: native=%q expected=%q"):format(native, expected))
end
for _, item in ipairs(cases) do
    local frame = run_with(heap:short_string(item[1]), heap:short_string(item[2]), heap:short_string(item[3]))
    local native = string_text(frame:reference(3))
    local expected = stock_concat(item[1], item[2], item[3]):match("^%d+%s+(.-)%s*$") or ""
    assert(native == expected,
        ("concat %q..%q..%q: native=%q stock=%q"):format(item[1], item[2], item[3], native, expected))
end

heap:free()
print("Lua55 concat: ok fresh-string concat + 4 differential cases native == stock")
