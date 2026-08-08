package.path = "./?.lua;./?/init.lua;" .. package.path

local function q(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function run(command)
    local ok, why, status = os.execute(command)
    assert(ok, ("command failed (%s %s): %s"):format(tostring(why), tostring(status), command))
end
local function capture(command)
    local pipe = assert(io.popen(command, "r"))
    local value = pipe:read("*a")
    assert(pipe:close())
    return value
end
local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local out = "target/copy_patch_cps/lua55_trace/opcode_09_10"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/opcode_09_10_stencils.c"),
    "-c -o", q(object),
}, " "))
run(("objdump -drwC %s > %s"):format(q(object), q(out .. "/stencils.asm")))

local relocations, current = {}, false
for line in capture("readelf -rW " .. q(object)):gmatch("[^\n]+") do
    local section = line:match("^Relocation section '([^']+)'")
    if section then
        current = section
        relocations[current] = {}
    elseif current then
        local at, kind, symbol, sign, addend = line:match(
            "^%s*([%da-fA-F]+)%s+[%da-fA-F]+%s+(R_%S+)%s+[%da-fA-F]+%s+(%S+)%s+([+-])%s+([%da-fA-F]+)")
        if at then
            relocations[current][#relocations[current] + 1] = {
                at = tonumber(at, 16), kind = kind, symbol = symbol,
                addend = (sign == "-" and -1 or 1) * tonumber(addend, 16),
            }
        end
    end
end

local function section(name)
    local path = out .. "/" .. name .. ".bin"
    os.remove(path)
    run(("objcopy --dump-section %s=%s %s"):format(
        q(".text." .. name), q(path), q(object)))
    return read(path)
end

local patterns = {
    target_tag = "\016\017\000\000",
    target_payload = "\024\017\000\000",
    source_tag = "\032\034\000\000",
    source_payload = "\040\034\000\000",
    upvalue_open = "\096\102\000\000",
    upvalue_closed_tag = "\104\102\000\000",
    upvalue_closed_payload = "\112\102\000\000",
    upvalue_state = "\120\102\000\000",
    upvalue_generation = "\124\102\000\000",
    expected_generation = "\119\102\085\068",
    resume = "\153\136\119\102",
}

local function positions(code, bytes)
    local result, cursor = {}, 1
    while true do
        local at = code:find(bytes, cursor, true)
        if not at then return result end
        result[#result + 1] = at - 1
        cursor = at + 1
    end
end

local function record(name, successor, expected)
    local code = section(name)
    local found = assert(relocations[".rela.text." .. name], "missing relocation for " .. name)
    assert(#found == 1, name .. " relocation count changed")
    local relocation = found[1]
    assert(relocation.kind == "R_X86_64_PLT32" and relocation.symbol == successor
        and relocation.addend == -4, name .. " successor relocation changed")
    local holes = {}
    for kind, pattern in pairs(patterns) do
        local values = positions(code, pattern)
        local count = expected[kind] or 0
        assert(#values == count,
            ("%s %s hole count changed: expected %d, got %d"):format(name, kind, count, #values))
        if count > 0 then holes[kind] = values end
    end
    return { code = code, holes = holes, successors = { relocation.at } }
end

local LEARN_GET = {
    target_tag = 1, upvalue_open = 1, upvalue_closed_tag = 2,
    upvalue_state = 1, upvalue_generation = 1, resume = 1,
}
local LEARN_SET = {
    source_tag = 2, upvalue_open = 1, upvalue_closed_tag = 1,
    upvalue_state = 1, upvalue_generation = 1, resume = 1,
}

local function residual_shape(open, payload, target)
    local result = {
        upvalue_state = 1, upvalue_generation = 1, expected_generation = 1, resume = 1,
    }
    if open then result.upvalue_open = 1 else result.upvalue_closed_tag = 1 end
    if target then result.target_tag = 1 else result.source_tag = 1 end
    if payload then
        if target then result.target_payload = 1 else result.source_payload = 1 end
        if not open then result.upvalue_closed_payload = 1 end
    end
    return result
end

local learners = {
    getupval = record("lua55_learn_getupval", "lua55_learn_next", LEARN_GET),
    setupval = record("lua55_learn_setupval", "lua55_learn_next", LEARN_SET),
}

local function quote(opcode, variant) return opcode * 65536 + variant end
local quote_names = {
    [quote(9, 1)] = "getupval_open_nil", [quote(9, 2)] = "getupval_open_false",
    [quote(9, 3)] = "getupval_open_true", [quote(9, 4)] = "getupval_open_integer",
    [quote(9, 5)] = "getupval_open_float", [quote(9, 6)] = "getupval_closed_nil",
    [quote(9, 7)] = "getupval_closed_false", [quote(9, 8)] = "getupval_closed_true",
    [quote(9, 9)] = "getupval_closed_integer", [quote(9, 10)] = "getupval_closed_float",
    [quote(9, 11)] = "getupval_open_closure", [quote(9, 12)] = "getupval_closed_closure",
    [quote(10, 1)] = "setupval_open_nil", [quote(10, 2)] = "setupval_open_false",
    [quote(10, 3)] = "setupval_open_true", [quote(10, 4)] = "setupval_open_integer",
    [quote(10, 5)] = "setupval_open_float", [quote(10, 6)] = "setupval_closed_nil",
    [quote(10, 7)] = "setupval_closed_false", [quote(10, 8)] = "setupval_closed_true",
    [quote(10, 9)] = "setupval_closed_integer", [quote(10, 10)] = "setupval_closed_float",
}

local quotes = {}
local closure_shapes = {
    [quote(9, 11)] = residual_shape(true, true, true),    -- getupval_open_closure
    [quote(9, 12)] = residual_shape(false, true, true),   -- getupval_closed_closure
}
for quote_id, name in pairs(quote_names) do
    local opcode = math.floor(quote_id / 65536)
    local variant = quote_id % 65536
    local is_get = opcode == 9
    local within = variant - 1
    local open = within < 5
    local tag = within % 5
    quotes[quote_id] = record("lua55_residual_" .. name, "lua55_residual_next",
        closure_shapes[quote_id] or residual_shape(open, tag >= 3, is_get))
end

local extension = { learners = learners, quotes = quotes, states = { open = 1, closed = 2 } }

local function literal(value) return string.format("%q", value) end
local function serialize(value, indent)
    indent = indent or ""
    if type(value) == "string" then return literal(value) end
    if type(value) == "number" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        if type(left) == type(right) then return left < right end
        return tostring(left) < tostring(right)
    end)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        local rendered = type(key) == "number" and "[" .. key .. "]" or key
        parts[#parts + 1] = "\n" .. indent .. "  " .. rendered .. " = "
            .. serialize(value[key], indent .. "  ") .. ","
    end
    parts[#parts + 1] = "\n" .. indent .. "}"
    return table.concat(parts)
end

local file = assert(io.open(out .. "/bank.lua", "wb"))
file:write("return ", serialize(extension), "\n")
file:close()

local learner_bytes, quote_bytes = 0, 0
for _, item in pairs(learners) do learner_bytes = learner_bytes + #item.code end
for _, item in pairs(quotes) do quote_bytes = quote_bytes + #item.code end
print(("Lua55 opcode 9-10 bank: learners=2/%d bytes quotes=20/%d bytes"):format(
    learner_bytes, quote_bytes))
