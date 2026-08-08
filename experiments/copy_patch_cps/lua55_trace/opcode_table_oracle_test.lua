package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

-- Differential oracle for the closed table subset (GETI/GETFIELD/SETI/SETFIELD)
-- against stock Lua 5.5. The native side runs the compiled fixture through the
-- learner and residual; the stock side runs the same operation sequence with
-- the reference interpreter. Every accepted composition must have exact native
-- lowering AND a differential oracle; this test is that oracle for the closed
-- scalar/string value subset on fixed-storage tables.

local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.opcode_00_10_projection")
local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local Heap = require("experiments.copy_patch_cps.lua55_trace.guest_heap_v1")
local ffi = Native.ffi

local STOCK_LUA = "/tmp/lua-5.5.0/src/lua"
local stock = io.open(STOCK_LUA, "r")
if not stock then
    print("Lua55 table oracle: SKIPPED (stock lua 5.5 interpreter missing)")
    os.exit(0)
end
stock:close()

local LONG = "this string is deliberately longer than forty bytes to force the long string tag"

-- value kinds: missing | nil | false | true | int | dbl | str
local initial_a = { "missing", "false", { t = "int", v = 5 }, { t = "dbl", v = 2.5 }, { t = "str", v = "alpha" } }
local initial_f = { "missing", "nil", { t = "int", v = 42 }, { t = "str", v = "sf" } }
local write_v = { "nil", "true", { t = "int", v = -3 }, { t = "dbl", v = 2.25 }, { t = "str", v = "v1" }, { t = "str", v = LONG } }

local cases = {}
for _, a in ipairs(initial_a) do
    for _, f in ipairs(initial_f) do
        for _, v in ipairs(write_v) do
            cases[#cases + 1] = { a = a, f = f, v = v }
        end
    end
end

-- Stock driver: embed the same cases as literals and print canonical results.
local function literal(value)
    if value == "missing" then return "{t=\"missing\"}" end
    if value == "nil" then return "{t=\"nil\"}" end
    if value == "false" then return "{t=\"false\"}" end
    if value == "true" then return "{t=\"true\"}" end
    if value.t == "int" then return ("{t=\"int\", v=%d}"):format(value.v) end
    if value.t == "dbl" then return ("{t=\"dbl\", v=%s}"):format(string.format("%.17g", value.v)) end
    return ("{t=\"str\", v=%q}"):format(value.v)
end

local parts = { "local cases = {" }
for index = 1, #cases do
    local c = cases[index]
    parts[#parts + 1] = ("{a=%s, f=%s, v=%s},"):format(
        literal(c.a), literal(c.f), literal(c.v))
end
parts[#parts + 1] = "}"
table.insert(parts, [[
local function mk(x)
  if x.t == "nil" then return nil end
  if x.t == "false" then return false end
  if x.t == "true" then return true end
  if x.t == "int" or x.t == "dbl" then return x.v end
  return x.v
end
local function ser(x)
  if x == nil then return "n" end
  if x == false then return "f" end
  if x == true then return "t" end
  if type(x) == "number" then
    if math.type(x) == "integer" then
      return "i:" .. tostring(x)
    end
    return "d:" .. string.format("%.17g", x)
  end
  return "s:" .. x
end
for i = 1, #cases do
  local c = cases[i]
  local t = {}
  if c.a.t ~= "missing" then t[1] = mk(c.a) end
  if c.f.t ~= "missing" then t.field = mk(c.f) end
  local v = mk(c.v)
  local a = t[1]
  local b = t.field
  t[2] = v
  t.other = v
  print(i .. "|" .. ser(a) .. "|" .. ser(b) .. "|" .. ser(t[2]) .. "|" .. ser(t.other))
end
]])
local script = table.concat(parts, "\n")
local script_path = "target/copy_patch_cps/lua55_trace/oracle_stock.lua"
local file = assert(io.open(script_path, "wb")); file:write(script); file:close()

local pipe = assert(io.popen(([[%s %s]]):format(STOCK_LUA, script_path), "r"))
local output = assert(pipe:read("*a")); pipe:close()
local expected = {}
for line in output:gmatch("[^\n]+") do
    local index, rest = line:match("^(%d+)%|(.*)$")
    assert(index, "unparseable stock oracle line: " .. line)
    local fields = {}
    for token in rest:gmatch("([^|]+)") do fields[#fields + 1] = token end
    assert(#fields == 4, "stock oracle field count changed: " .. line)
    expected[tonumber(index)] = fields
end
assert(#expected == #cases, "stock oracle case count mismatch")

-- Native side.
local heap = Heap.GuestHeap.new(31)
local bytes = require("experiments.copy_patch_cps.lua55_trace.opcode_table_fixture")
local main = Undump.undump(bytes)
local proto = assert(main.protos[1])
local path = Projection.project(proto, 0, 6, heap)
assert(#path.occurrences == 6)

local bank = dofile("target/copy_patch_cps/lua55_trace/opcode_00_08/bank.lua")
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_table/bank.lua"))
Native.extend_bank(bank, dofile("target/copy_patch_cps/lua55_trace/opcode_string/bank.lua"))

local field_key = heap:short_string("field")
local other_key = heap:short_string("other")

local function apply_initial(owner, setter, value)
    if value == "missing" or value == "nil" then return setter("nil") end
    if value == "false" then return setter("false") end
    if value == "true" then return setter("true") end
    if value.t == "int" then return setter("int", value.v) end
    if value.t == "dbl" then return setter("dbl", value.v) end
    return setter("str", heap:short_string(value.v))
end

local function set_array(table_owner, value)
    return apply_initial(table_owner, function(kind, payload)
        if kind == "nil" then return table_owner:set_array_nil(1) end
        if kind == "false" then return table_owner:set_array_false(1) end
        if kind == "true" then return table_owner:set_array_true(1) end
        if kind == "int" then return table_owner:set_array_integer(1, payload) end
        if kind == "dbl" then return table_owner:set_array_float(1, payload) end
        return table_owner:set_array_short_string(1, payload)
    end, value)
end

local function set_field(table_owner, value)
    if value == "missing" then return table_owner end
    return apply_initial(table_owner, function(kind, payload)
        if kind == "nil" then return table_owner:set_field_nil(field_key) end
        if kind == "false" then return table_owner:set_field_false(field_key) end
        if kind == "true" then return table_owner:set_field_true(field_key) end
        if kind == "int" then return table_owner:set_field_integer(field_key, payload) end
        if kind == "dbl" then return table_owner:set_field_float(field_key, payload) end
        return table_owner:set_field_short_string(field_key, payload)
    end, value)
end

local function set_frame_value(frame, value)
    if value == "nil" then return frame:set_nil(1) end
    if value == "false" then return frame:set_false(1) end
    if value == "true" then return frame:set_true(1) end
    if value.t == "int" then return frame:set_integer(1, value.v) end
    if value.t == "dbl" then return frame:set_float(1, value.v) end
    local owner = heap:short_string(value.v)
    return frame:set_short_string(1, owner)
end

local function native_serialize(value)
    local tag = tonumber(value.tag)
    if tag == 0 then return "n" end
    if tag == 1 then return "f" end
    if tag == 2 then return "t" end
    if tag == 3 then return "i:" .. tostring(tonumber(value.payload.integer)) end
    if tag == 4 then return "d:" .. string.format("%.17g", tonumber(value.payload.floating)) end
    if tag == 5 or tag == 6 then
        local ref = tonumber(value.payload.reference)
        for _, owner in ipairs(heap.entries) do
            if owner.text and owner.object
                and tonumber(ffi.cast("uintptr_t", owner.object)) == ref then
                return "s:" .. owner.text
            end
        end
        error("unresolved guest string reference")
    end
    error("unexpected guest tag " .. tostring(tag))
end

local mismatches = 0
for index = 1, #cases do
    local c = cases[index]
    local table_owner = heap:table(2, 2)
    set_array(table_owner, c.a)
    set_field(table_owner, c.f)
    local program = path:new_program(6, bank)
    local frame = program:new_frame():set_table(0, table_owner)
    set_frame_value(frame, c.v)
    assert(program:execute(frame) == bank.status.completed, "native residual rejected a closed case")
    local actual = {
        native_serialize(frame.values[2]),
        native_serialize(frame.values[3]),
        native_serialize(table_owner:array_value(2)),
        native_serialize(table_owner:field_value(other_key, false)),
    }
    local want = expected[index]
    for slot = 1, 4 do
        if actual[slot] ~= want[slot] then
            mismatches = mismatches + 1
            print(("case %d slot %d: native=%q stock=%q (a=%s f=%s v=%s)")
                :format(index, slot, actual[slot], want[slot],
                    literal(c.a), literal(c.f), literal(c.v)))
        end
    end
    program:free()
end

heap:free()
assert(mismatches == 0, ("Lua55 table oracle found %d mismatches"):format(mismatches))
print(("Lua55 table oracle: ok %d cases native == stock Lua 5.5 (JIT: %s)")
    :format(#cases, tostring(require("jit").status())))
