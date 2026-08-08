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

local out = "target/copy_patch_cps/lua55_trace/opcode_table"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/opcode_table_stencils.c"),
    "-c -o", q(object),
}, " "))
run(("objdump -drwC %s > %s"):format(q(object), q(out .. "/stencils.asm")))

local relocations, current = {}, false
for line in capture("readelf -rW " .. q(object)):gmatch("[^\n]+") do
    local section_name = line:match("^Relocation section '([^']+)'")
    if section_name then current = section_name; relocations[current] = {}
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
    run(("objcopy --dump-section %s=%s %s"):format(q(".text." .. name), q(path), q(object)))
    return read(path)
end

local patterns = {
    target_base = "\016\017\000\000", target_payload = "\024\017\000\000",
    source_base = "\032\034\000\000", source_payload = "\040\034\000\000",
    receiver_tag = "\064\068\000\000", receiver_payload = "\072\068\000\000",
    integer_key = "\136\119\102\085",
    key_reference = "\080\118\152\186\220\254\052\018",
    table_reference = "\147\151\088\083\038\089\065\049",
    slot_reference = "\069\144\069\040\024\040\024\039",
    storage_generation = "\141\124\107\090",
    collection_epoch = "\125\108\091\074",
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

local function record(name, expected)
    local code = section(name)
    local found = assert(relocations[".rela.text." .. name], "missing relocation for " .. name)
    assert(#found == 1, name .. " relocation count changed")
    local relocation = found[1]
    local successor = name:find("_learn_", 1, true) and "lua55_learn_next" or "lua55_residual_next"
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

local GETI_LEARN = { target_base=1, receiver_tag=1, receiver_payload=1, integer_key=2, resume=1 }
local GETFIELD_LEARN = {
    target_base=2, target_payload=1, receiver_tag=1, receiver_payload=1, key_reference=2, resume=1,
}
local SETI_LEARN = {
    source_base=3, receiver_tag=1, receiver_payload=1, integer_key=2, resume=1,
}
local SETFIELD_LEARN = {
    source_base=3, receiver_tag=1, receiver_payload=1, key_reference=2, resume=1,
}
local GET_RESIDUAL = {
    target_base=1, receiver_tag=1, receiver_payload=1, table_reference=1,
    slot_reference=1, storage_generation=1, collection_epoch=1, resume=1,
}
local GET_MISSING = {
    target_base=1, target_payload=1, receiver_tag=1, receiver_payload=1, table_reference=1,
    storage_generation=1, collection_epoch=1, resume=1,
}
local SET_RESIDUAL = {
    source_base=2, receiver_tag=1, receiver_payload=1, table_reference=1,
    slot_reference=1, storage_generation=1, collection_epoch=1, resume=1,
}

local learners = {
    geti = record("lua55_learn_geti", GETI_LEARN),
    getfield = record("lua55_learn_getfield", GETFIELD_LEARN),
    seti = record("lua55_learn_seti", SETI_LEARN),
    setfield = record("lua55_learn_setfield", SETFIELD_LEARN),
}

local names = { "nil", "false", "true", "integer", "float", "short_string", "long_string" }
local function quote(opcode, variant) return opcode * 65536 + variant end
local quotes = {}
for variant, name in ipairs(names) do
    quotes[quote(13, variant)] = record("lua55_residual_geti_" .. name, GET_RESIDUAL)
end
quotes[quote(14, 1)] = record("lua55_residual_getfield_missing", GET_MISSING)
for index, name in ipairs(names) do
    quotes[quote(14, index + 1)] = record("lua55_residual_getfield_" .. name, GET_RESIDUAL)
end
for _, opcode in ipairs({ 17, 18 }) do
    local prefix = opcode == 17 and "seti" or "setfield"
    for variant, name in ipairs(names) do
        quotes[quote(opcode, variant)] = record(
            "lua55_residual_" .. prefix .. "_" .. name, SET_RESIDUAL)
    end
end

-- the closure variant (tag 8): GETI (13, 9), GETFIELD (14, 10) (the
-- missing occupies (14, 1)), SETI (17, 9), SETFIELD (18, 9)
quotes[quote(13, 9)] = record("lua55_residual_geti_closure", GET_RESIDUAL)
quotes[quote(14, 10)] = record("lua55_residual_getfield_closure", GET_RESIDUAL)
quotes[quote(17, 9)] = record("lua55_residual_seti_closure", SET_RESIDUAL)
quotes[quote(18, 9)] = record("lua55_residual_setfield_closure", SET_RESIDUAL)

local extension = { learners = learners, quotes = quotes }
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
print(("Lua55 table bank: learners=4/%d bytes quotes=%d/%d bytes"):format(
    learner_bytes, 29, quote_bytes))
