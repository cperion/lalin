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

local out = "target/copy_patch_cps/lua55_trace/opcode_string"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/opcode_string_stencils.c"),
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
    reference = "\239\205\171\086\071\056\041\016",
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

local function quote(opcode, variant) return opcode * 65536 + variant end
local LOAD = { target_tag = 1, target_payload = 1, reference = 1 }
local MOVE = {
    target_tag = 1, target_payload = 1, source_tag = 1, source_payload = 1, resume = 1,
}

local learners = {
    loadk_short_string = record(
        "lua55_learn_loadk_short_string", "lua55_learn_next", LOAD),
    loadk_long_string = record(
        "lua55_learn_loadk_long_string", "lua55_learn_next", LOAD),
    loadkx_short_string = record(
        "lua55_learn_loadkx_short_string", "lua55_learn_next", LOAD),
    loadkx_long_string = record(
        "lua55_learn_loadkx_long_string", "lua55_learn_next", LOAD),
}

local quotes = {
    [quote(0, 6)] = record(
        "lua55_residual_move_short_string", "lua55_residual_next", MOVE),
    [quote(0, 7)] = record(
        "lua55_residual_move_long_string", "lua55_residual_next", MOVE),
    [quote(3, 6)] = record(
        "lua55_residual_loadk_short_string", "lua55_residual_next", LOAD),
    [quote(3, 7)] = record(
        "lua55_residual_loadk_long_string", "lua55_residual_next", LOAD),
    [quote(4, 6)] = record(
        "lua55_residual_loadkx_short_string", "lua55_residual_next", LOAD),
    [quote(4, 7)] = record(
        "lua55_residual_loadkx_long_string", "lua55_residual_next", LOAD),
}

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
print(("Lua55 string bank: learners=4/%d bytes quotes=6/%d bytes"):format(
    learner_bytes, quote_bytes))
