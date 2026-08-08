package.path = "./?.lua;./?/init.lua;" .. package.path

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

local out = "target/copy_patch_cps/lua55_trace/opcode_closure"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -fno-jump-tables -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/opcode_closure_stencils.c"), "-c -o", q(object),
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
    quote_base = "\060\045\030\015",
    target_tag = "\016\017\000\000",
    target_payload = "\024\017\000\000",
    target_reserved = "\020\017\000\000",
    resume = "\153\136\119\102",
    proto_index = "\016\015\014\013",
    nupvals = "\032\031\030\029",
    instack0 = "\048\047\046\045",
    idx0 = "\064\063\062\061",
    instack1 = "\080\079\078\077",
    idx1 = "\096\095\094\093",
    instack2 = "\112\111\110\109",
    idx2 = "\128\127\126\125",
    instack3 = "\144\143\142\141",
    idx3 = "\160\159\158\157",
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

local learners = {
    closure = record("lua55_learn_closure", "lua55_learn_next"),
}
local quotes = {
    [79 * 65536 + 1] = record("lua55_residual_closure", "lua55_residual_next"),
}

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
print(("Lua55 closure bank: learners=%d/%d bytes quotes=%d/%d bytes"):format(
    count_keys(learners), learner_bytes, count_keys(quotes), quote_bytes))
