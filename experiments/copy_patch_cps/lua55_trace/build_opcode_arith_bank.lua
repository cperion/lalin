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

local out = "target/copy_patch_cps/lua55_trace/opcode_arith"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -fno-jump-tables -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/opcode_arith_stencils.c"), "-c -o", q(object),
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
    left_tag = "\032\034\000\000",
    left_payload = "\040\034\000\000",
    right_tag = "\048\051\000\000",
    right_payload = "\056\051\000\000",
    quote_base = "\060\045\030\015",
    int_imm = "\024\023\022\021\020\019\018\017",
    const_tag = "\057\058\059\060",
    const_int = "\040\039\038\037\036\035\034\033",
    const_flt = "\240\222\188\154\120\086\052\018",
    resume = "\153\136\119\102",
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
local function add_learner(name, key)
    learners[key] = record("lua55_learn_" .. name, "lua55_learn_next")
end
local function add_quote(opcode, variant, name)
    quotes[opcode * 65536 + variant] = record("lua55_residual_" .. name, "lua55_residual_next")
end

local pairs4 = { "ii", "if", "fi", "ff" }
local imm2 = { "int", "flt" }
local const_bit2 = { "i", "f" }

-- register-register family
local rr = {
    { 34, "add" }, { 35, "sub" }, { 36, "mul" }, { 37, "mod" },
    { 39, "div" }, { 40, "idiv" }, { 41, "band" }, { 42, "bor" },
    { 43, "bxor" }, { 44, "shl" }, { 45, "shr" },
}
for _, item in ipairs(rr) do
    local opcode, name = item[1], item[2]
    add_learner(name, name)
    for leaf, pair in ipairs(pairs4) do
        add_quote(opcode, leaf, name .. "_" .. pair)
    end
end

-- register-immediate family
local ri = { { 21, "addi" }, { 32, "shli" }, { 33, "shri" } }
for _, item in ipairs(ri) do
    local opcode, name = item[1], item[2]
    add_learner(name, name)
    for leaf, suffix in ipairs(imm2) do
        add_quote(opcode, leaf, name .. "_" .. suffix)
    end
end

-- register-constant family (binary)
local rk = {
    { 22, "addk" }, { 23, "subk" }, { 24, "mulk" }, { 25, "modk" },
    { 27, "divk" }, { 28, "idivk" },
}
for _, item in ipairs(rk) do
    local opcode, name = item[1], item[2]
    add_learner(name, name)
    for leaf, pair in ipairs(pairs4) do
        add_quote(opcode, leaf, name .. "_" .. pair)
    end
end

-- register-constant family (bitwise; constant is always an integer)
local rkb = { { 29, "bandk" }, { 30, "bork" }, { 31, "bxork" } }
for _, item in ipairs(rkb) do
    local opcode, name = item[1], item[2]
    add_learner(name, name)
    for leaf, suffix in ipairs(const_bit2) do
        add_quote(opcode, leaf, name .. "_" .. suffix)
    end
end

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
print(("Lua55 arith bank: learners=%d/%d bytes quotes=%d/%d bytes"):format(
    count_keys(learners), learner_bytes, count_keys(quotes), quote_bytes))
