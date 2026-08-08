package.path = "./?.lua;./?/init.lua;" .. package.path

local bit = require("bit")
local function q(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function run(command)
    local ok, why, status = os.execute(command)
    assert(ok, ("command failed (%s %s): %s"):format(tostring(why), tostring(status), command))
end
local function capture(command)
    local pipe = assert(io.popen(command, "r")); local value = pipe:read("*a")
    assert(pipe:close()); return value
end
local function read(path)
    local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value
end

local out = "target/copy_patch_cps/lua55_trace/opcode_generic_table"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -fno-jump-tables -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/opcode_generic_table_stencils.c"), "-c -o", q(object),
}, " "))
run(("objdump -drwC %s > %s"):format(q(object), q(out .. "/stencils.asm")))

local relocations, current = {}, false
for line in capture("readelf -rW " .. q(object)):gmatch("[^\n]+") do
    local section = line:match("^Relocation section '([^']+)'")
    if section then current = section; relocations[current] = {}
    elseif current then
        local at, kind, symbol, sign, addend = line:match(
            "^%s*([%da-fA-F]+)%s+[%da-fA-F]+%s+(R_%S+)%s+[%da-fA-F]+%s+(%S+)%s+([+-])%s+([%da-fA-F]+)")
        if at then relocations[current][#relocations[current] + 1] = {
            at = tonumber(at, 16), kind = kind, symbol = symbol,
            addend = (sign == "-" and -1 or 1) * tonumber(addend, 16),
        } end
    end
end

local function section(name)
    local path = out .. "/" .. name .. ".bin"; os.remove(path)
    run(("objcopy --dump-section %s=%s %s"):format(
        q(".text." .. name), q(path), q(object)))
    return read(path)
end

local function positions(code, bytes)
    local values, cursor = {}, 1
    while true do
        local at = code:find(bytes, cursor, true)
        if not at then break end
        values[#values + 1] = at - 1
        cursor = at + 1
    end
    return values
end

local patterns = {
    target_tag = "\016\017\000\000",
    target_payload = "\024\017\000\000",
    target_reserved = "\020\017\000\000",
    source_tag = "\032\034\000\000",
    source_payload = "\040\034\000\000",
    source_reserved = "\036\034\000\000",
    upvalue_open = "\096\102\000\000",
    upvalue_closed = "\104\102\000\000",
    upvalue_cell_state = "\120\102\000\000",
    upvalue_cell_gen = "\124\102\000\000",
    receiver_tag = "\064\068\000\000",
    receiver_payload = "\072\068\000\000",
    receiver_reserved = "\068\068\000\000",
    key_tag = "\080\085\000\000",
    key_payload = "\088\085\000\000",
    key_reserved = "\084\085\000\000",
    object_tag = "\128\136\000\000",
    object_payload = "\136\136\000\000",
    object_reserved = "\132\136\000\000",
    int_key = "\120\119\118\117\116\115\114\113",
    key_ref = "\120\135\116\133\114\131\112\129",
    table_reference = "\147\151\083\089\083\088\065\049",
    slot_reference = "\069\144\040\133\040\024\039\039",
    storage_generation = "\141\107\124\090",
    collection_epoch = "\074\091\108\125",
    quote_base = "\060\045\030\015",
    resume = "\153\136\119\102",
    const_tag = "\057\058\059\060",
    const_int = "\040\039\038\037\036\035\034\033",
    const_ref = "\121\086\052\018\240\222\188\010",
    array_cap = "\013\012\011\010",
    field_cap = "\029\028\027\026",
    upvalue_state = "\045\044\043\042",
    upvalue_gen = "\061\060\059\058",
}

local function record(name, successor)
    local code = section(name)
    local found = relocations[".rela.text." .. name] or {}
    local successors = {}
    for index = 1, #found do
        local item = found[index]
        assert(item.kind == "R_X86_64_PLT32" and item.symbol == successor and item.addend == -4,
            name .. " successor relocation changed")
        successors[#successors + 1] = item.at
    end
    local holes = {}
    for kind, pattern in pairs(patterns) do
        local ats = positions(code, pattern)
        if #ats > 0 then holes[kind] = ats end
    end
    return { code = code, holes = holes, successors = successors }
end

local learners = {}
local quotes = {}
local function add_learner(name)
    learners[name] = record("lua55_learn_" .. name, "lua55_learn_next")
end
local function add_quote(opcode, variant, name)
    quotes[opcode * 65536 + variant] = record("lua55_residual_" .. name, "lua55_residual_next")
end

for _, name in ipairs({ "gettable", "settable", "gettabup", "settabup", "self", "newtable" }) do
    add_learner(name)
end

local tags = { "nil", "false", "true", "integer", "float", "short_string", "long_string" }
-- GETTABLE (12): int hits 1-7, int miss 8, str hits 9-15, str miss 16
for i, tag in ipairs(tags) do add_quote(12, i, "gettable_i_" .. tag) end
add_quote(12, 8, "gettable_i_missing")
for i, tag in ipairs(tags) do add_quote(12, 9 + i - 1, "gettable_s_" .. tag) end
add_quote(12, 16, "gettable_s_missing")
-- SETTABLE (16): int 1-7, str 9-15
for i, tag in ipairs(tags) do add_quote(16, i, "settable_i_" .. tag) end
for i, tag in ipairs(tags) do add_quote(16, 9 + i - 1, "settable_s_" .. tag) end
-- GETTABUP (15): int 1-8, str 9-16
for i, tag in ipairs(tags) do add_quote(15, i, "gettabup_i_" .. tag) end
add_quote(15, 8, "gettabup_i_missing")
for i, tag in ipairs(tags) do add_quote(15, 9 + i - 1, "gettabup_s_" .. tag) end
add_quote(15, 16, "gettabup_s_missing")
add_quote(15, 17, "gettabup_s_closure")
add_quote(15, 18, "gettabup_s_table")
-- SETTABUP (11): int 1-7, str 9-15
for i, tag in ipairs(tags) do add_quote(11, i, "settabup_i_" .. tag) end
for i, tag in ipairs(tags) do add_quote(11, 9 + i - 1, "settabup_s_" .. tag) end
-- SELF (20): str hits 9-15, missing 16
for i, tag in ipairs(tags) do add_quote(20, 9 + i - 1, "self_" .. tag) end
add_quote(20, 16, "self_missing")
-- NEWTABLE (19): variant 1
add_quote(19, 1, "newtable")

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local extension = { learners = learners, quotes = quotes }
local function literal(value) return string.format("%q", value) end
local function serialize(value, indent)
    indent = indent or ""
    if type(value) == "string" then return literal(value) end
    if type(value) == "number" then return tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "{" }
    for _, key in ipairs(keys) do
        local rendered = type(key) == "number" and "[" .. key .. "]" or ("[" .. string.format("%q", key) .. "]")
        parts[#parts + 1] = "\n" .. indent .. "  " .. rendered .. " = " .. serialize(value[key], indent .. "  ") .. ","
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
print(("Lua55 generic-table bank: learners=%d/%d bytes quotes=%d/%d bytes"):format(
    count_keys(learners), learner_bytes, count_keys(quotes), quote_bytes))
