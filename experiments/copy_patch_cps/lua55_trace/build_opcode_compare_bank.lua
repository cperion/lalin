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

local out = "target/copy_patch_cps/lua55_trace/opcode_compare"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -fno-jump-tables -ffunction-sections -fno-stack-protector",
    q("experiments/copy_patch_cps/lua55_trace/opcode_compare_stencils.c"), "-c -o", q(object),
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
    left_tag = "\016\017\000\000",
    left_payload = "\024\017\000\000",
    right_tag = "\032\034\000\000",
    right_payload = "\040\034\000\000",
    target_pc = "\064\048\032\016",
    resume = "\153\136\119\102",
    quote_base = "\060\045\030\015",
    int_imm = "\024\023\022\021\020\019\018\017",
    const_int = "\040\039\038\037\036\035\034\033",
    const_flt = "\240\222\188\154\120\086\052\018",
    const_ref = "\121\086\052\018\240\222\188\010",
    const_tag = "\057\058\059\060",
}

local inspect = arg[1] == "inspect"
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
    if inspect then
        local counts = {}
        for kind, ats in pairs(holes) do counts[#counts + 1] = kind .. "=" .. #ats end
        table.sort(counts)
        print(("%-44s %4d  %s"):format(name, #code, table.concat(counts, " ")))
    end
    return { code = code, holes = holes, successors = successors }
end

local learners = {}
local quotes = {}

local function add_learner(name, kind)
    learners[kind] = record("lua55_learn_" .. name, "lua55_learn_next")
end
local function add_quote(opcode, variant, name)
    quotes[opcode * 65536 + variant] = record("lua55_residual_" .. name, "lua55_residual_next")
end

local pairs11 = { "ii", "if", "fi", "ff", "ss", "sl", "ls", "ll", "nn", "bb", "tt", "neq" }
local pairs8 = { "ii", "if", "fi", "ff", "ss", "sl", "ls", "ll" }
local pairs5 = { "ii", "ff", "if", "fi", "ss", "ls", "sl", "ll", "nn", "bb", "tt" }
local imm2 = { "int", "flt" }

-- EQ (57)
add_learner("eq_k0", "eq_k0"); add_learner("eq_k1", "eq_k1")
for leaf, pair in ipairs(pairs11) do
    add_quote(57, bit.bor(bit.lshift(leaf, 1), 0), "eq_" .. pair .. "_k0")
    add_quote(57, bit.bor(bit.lshift(leaf, 1), 1), "eq_" .. pair .. "_k1")
end
-- LT (58) / LE (59)
add_learner("lt_k0", "lt_k0"); add_learner("lt_k1", "lt_k1")
add_learner("le_k0", "le_k0"); add_learner("le_k1", "le_k1")
for _, opcode in ipairs({ 58, 59 }) do
    local prefix = opcode == 58 and "lt" or "le"
    for leaf, pair in ipairs(pairs8) do
        add_quote(opcode, bit.bor(bit.lshift(leaf, 1), 0), prefix .. "_" .. pair .. "_k0")
        add_quote(opcode, bit.bor(bit.lshift(leaf, 1), 1), prefix .. "_" .. pair .. "_k1")
    end
end
-- EQK (60)
add_learner("eqk_k0", "eqk_k0"); add_learner("eqk_k1", "eqk_k1")
for leaf, pair in ipairs(pairs5) do
    add_quote(60, bit.bor(bit.lshift(leaf, 1), 0), "eqk_" .. pair .. "_k0")
    add_quote(60, bit.bor(bit.lshift(leaf, 1), 1), "eqk_" .. pair .. "_k1")
end
-- EQI (61) / LTI (62) / LEI (63) / GTI (64) / GEI (65)
local imm_names = { "eqi", "lti", "lei", "gti", "gei" }
for opcode = 61, 65 do
    local prefix = imm_names[opcode - 60]
    add_learner(prefix .. "_k0", prefix .. "_k0")
    add_learner(prefix .. "_k1", prefix .. "_k1")
    for leaf, pair in ipairs(imm2) do
        add_quote(opcode, bit.bor(bit.lshift(leaf, 1), 0), prefix .. "_" .. pair .. "_k0")
        add_quote(opcode, bit.bor(bit.lshift(leaf, 1), 1), prefix .. "_" .. pair .. "_k1")
    end
end
-- TEST (66) / TESTSET (67)
add_learner("test_k0", "test_k0"); add_learner("test_k1", "test_k1")
add_learner("teskset_k0", "teskset_k0"); add_learner("teskset_k1", "teskset_k1")
add_quote(66, 2, "test_k0"); add_quote(66, 3, "test_k1")
add_quote(67, 2, "teskset_k0"); add_quote(67, 3, "teskset_k1")

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
if inspect then
    local learner_bytes, quote_bytes = 0, 0
    for _, item in pairs(learners) do learner_bytes = learner_bytes + #item.code end
    for _, item in pairs(quotes) do quote_bytes = quote_bytes + #item.code end
    print(("learners=%d/%d bytes quotes=%d/%d bytes"):format(
        count_keys(learners), learner_bytes, count_keys(quotes), quote_bytes))
    return
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
        local rendered = type(key) == "number" and "[" .. key .. "]" or key
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
print(("Lua55 compare bank: learners=%d/%d bytes quotes=%d/%d bytes"):format(
    count_keys(learners), learner_bytes, count_keys(quotes), quote_bytes))
