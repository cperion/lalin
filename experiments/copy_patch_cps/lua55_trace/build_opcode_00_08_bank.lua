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

local out = "target/copy_patch_cps/lua55_trace/opcode_00_08"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/opcode_00_08_stencils.c"),
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

local function terminal_prefix(name, successor)
    local code = section(name)
    local found = assert(relocations[".rela.text." .. name], "missing relocation for " .. name)
    assert(#found == 1, name .. " relocation count changed")
    local item = found[1]
    assert(item.kind == "R_X86_64_PLT32" and item.symbol == successor and item.addend == -4,
        name .. " successor relocation changed")
    assert(item.at + 4 == #code and code:byte(item.at) == 0xe9,
        name .. " successor is not terminal E9 rel32")
    return code:sub(1, item.at - 1)
end

local patterns = {
    target_tag = "\016\017\000\000",
    target_payload = "\024\017\000\000",
    source_tag = "\032\034\000\000",
    source_payload = "\040\034\000\000",
    target_index = "\017\001\000\000",
    span = "\119\007\000\000",
    integer = "\136\119\102\085\068\051\034\017",
    floating = "\017\034\051\068\085\102\119\136",
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
    local code = terminal_prefix(name, successor)
    local holes = {}
    for kind, pattern in pairs(patterns) do
        local found = positions(code, pattern)
        local count = expected[kind] or 0
        assert(#found == count,
            ("%s %s hole count changed: expected %d, got %d"):format(name, kind, count, #found))
        if count > 0 then holes[kind] = found end
    end
    return { code = code, holes = holes }
end

local TARGET = { target_tag = 1 }
local INTEGER = { target_tag = 1, target_payload = 1, integer = 1 }
local FLOAT = { target_tag = 1, target_payload = 1, floating = 1 }
local MOVE_SMALL = { target_tag = 1, source_tag = 1, resume = 1 }
local MOVE_PAYLOAD = {
    target_tag = 1, target_payload = 1, source_tag = 1, source_payload = 1, resume = 1,
}

local learners = {
    move = record("lua55_learn_move", "lua55_learn_next", {
        target_tag = 1, source_tag = 2, resume = 1,
    }),
    loadi = record("lua55_learn_loadi", "lua55_learn_next", INTEGER),
    loadf = record("lua55_learn_loadf", "lua55_learn_next", FLOAT),
    loadk_nil = record("lua55_learn_loadk_nil", "lua55_learn_next", TARGET),
    loadk_false = record("lua55_learn_loadk_false", "lua55_learn_next", TARGET),
    loadk_true = record("lua55_learn_loadk_true", "lua55_learn_next", TARGET),
    loadk_integer = record("lua55_learn_loadk_integer", "lua55_learn_next", INTEGER),
    loadk_float = record("lua55_learn_loadk_float", "lua55_learn_next", FLOAT),
    loadkx_nil = record("lua55_learn_loadkx_nil", "lua55_learn_next", TARGET),
    loadkx_false = record("lua55_learn_loadkx_false", "lua55_learn_next", TARGET),
    loadkx_true = record("lua55_learn_loadkx_true", "lua55_learn_next", TARGET),
    loadkx_integer = record("lua55_learn_loadkx_integer", "lua55_learn_next", INTEGER),
    loadkx_float = record("lua55_learn_loadkx_float", "lua55_learn_next", FLOAT),
    loadfalse = record("lua55_learn_loadfalse", "lua55_learn_next", TARGET),
    lfalseskip = record("lua55_learn_lfalseskip", "lua55_learn_next", TARGET),
    loadtrue = record("lua55_learn_loadtrue", "lua55_learn_next", TARGET),
    loadnil = record("lua55_learn_loadnil", "lua55_learn_next", {
        target_index = 2, span = 1,
    }),
}

local function quote(opcode, variant) return opcode * 65536 + variant end
local quotes = {
    [quote(0, 1)] = record("lua55_residual_move_nil", "lua55_residual_next", MOVE_SMALL),
    [quote(0, 2)] = record("lua55_residual_move_false", "lua55_residual_next", MOVE_SMALL),
    [quote(0, 3)] = record("lua55_residual_move_true", "lua55_residual_next", MOVE_SMALL),
    [quote(0, 4)] = record("lua55_residual_move_integer", "lua55_residual_next", MOVE_PAYLOAD),
    [quote(0, 5)] = record("lua55_residual_move_float", "lua55_residual_next", MOVE_PAYLOAD),
    [quote(0, 8)] = record("lua55_residual_move_table", "lua55_residual_next", MOVE_PAYLOAD),
    [quote(0, 9)] = record("lua55_residual_move_closure", "lua55_residual_next", MOVE_PAYLOAD),
    [quote(1, 1)] = record("lua55_residual_loadi", "lua55_residual_next", INTEGER),
    [quote(2, 1)] = record("lua55_residual_loadf", "lua55_residual_next", FLOAT),
    [quote(3, 1)] = record("lua55_residual_loadk_nil", "lua55_residual_next", TARGET),
    [quote(3, 2)] = record("lua55_residual_loadk_false", "lua55_residual_next", TARGET),
    [quote(3, 3)] = record("lua55_residual_loadk_true", "lua55_residual_next", TARGET),
    [quote(3, 4)] = record("lua55_residual_loadk_integer", "lua55_residual_next", INTEGER),
    [quote(3, 5)] = record("lua55_residual_loadk_float", "lua55_residual_next", FLOAT),
    [quote(4, 1)] = record("lua55_residual_loadkx_nil", "lua55_residual_next", TARGET),
    [quote(4, 2)] = record("lua55_residual_loadkx_false", "lua55_residual_next", TARGET),
    [quote(4, 3)] = record("lua55_residual_loadkx_true", "lua55_residual_next", TARGET),
    [quote(4, 4)] = record("lua55_residual_loadkx_integer", "lua55_residual_next", INTEGER),
    [quote(4, 5)] = record("lua55_residual_loadkx_float", "lua55_residual_next", FLOAT),
    [quote(5, 1)] = record("lua55_residual_loadfalse", "lua55_residual_next", TARGET),
    [quote(6, 1)] = record("lua55_residual_lfalseskip", "lua55_residual_next", TARGET),
    [quote(7, 1)] = record("lua55_residual_loadtrue", "lua55_residual_next", TARGET),
    [quote(8, 1)] = record("lua55_residual_loadnil_one", "lua55_residual_next", TARGET),
}

local finish = section("lua55_opcode_finish")
assert(finish:sub(-1) == "\195", "opcode finish does not end in ret")
assert(relocations[".rela.text.lua55_opcode_finish"] == nil, "opcode finish gained relocations")
local finish_resume = positions(finish, patterns.resume)
assert(#finish_resume == 1, "opcode finish resume hole count changed")

local bank = {
    learners = learners,
    quotes = quotes,
    finish = { code = finish, resume = finish_resume[1] },
    tags = {
        nil_value = 0, false_value = 1, true_value = 2, integer = 3, floating = 4,
        short_string = 5, long_string = 6, table_value = 7, closure_value = 8,
    },
    status = { executing = 0, completed = 1, guard_failed = 2, rejected = 3 },
}

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
file:write("return ", serialize(bank), "\n")
file:close()

local learner_bytes, quote_bytes = 0, 0
for _, item in pairs(learners) do learner_bytes = learner_bytes + #item.code end
for _, item in pairs(quotes) do quote_bytes = quote_bytes + #item.code end
print(("Lua55 opcode 0-8 bank: learners=%d/%d bytes quotes=%d/%d bytes"):format(
    17, learner_bytes, 21, quote_bytes))
