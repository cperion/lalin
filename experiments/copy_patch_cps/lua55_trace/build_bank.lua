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

local out = "target/copy_patch_cps/lua55_trace"
local object = out .. "/stencils.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -fno-pic -ffunction-sections -fno-stack-protector",
    "-fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/lua55_trace/stencils.c"), "-c -o", q(object),
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

local function positions(code, bytes, expected, label)
    local values, cursor = {}, 1
    while true do
        local at = code:find(bytes, cursor, true)
        if not at then break end
        values[#values + 1] = at - 1
        cursor = at + 1
    end
    assert(#values == expected, label .. " hole count changed")
    return values
end

local learn_integer_add_forloop = section("lua55_trace_learn_integer_add_forloop")
local learn_relocations = relocations[".rela.text.lua55_trace_learn_integer_add_forloop"] or {}
assert(#learn_relocations == 0, "learner must be a single self-contained block")

local fused_integer_loop = section("lua55_trace_integer_add_forloop")
local fused_relocations = relocations[".rela.text.lua55_trace_integer_add_forloop"] or {}
assert(#fused_relocations == 0, "fused recurrence must be a single self-contained block")

local bank = {
    learn_integer_add_forloop = {
        code = learn_integer_add_forloop,
        index_tag = positions(learn_integer_add_forloop, "\016\017\000\000", 1, "learn index tag"),
        limit_tag = positions(learn_integer_add_forloop, "\064\068\000\000", 1, "learn limit tag"),
        step_tag = positions(learn_integer_add_forloop, "\080\085\000\000", 1, "learn step tag"),
        sum_tag = positions(learn_integer_add_forloop, "\096\102\000\000", 1, "learn sum tag"),
        index_payload = positions(learn_integer_add_forloop, "\024\017\000\000", 2, "learn index"),
        limit_payload = positions(learn_integer_add_forloop, "\072\068\000\000", 1, "learn limit"),
        step_payload = positions(learn_integer_add_forloop, "\088\085\000\000", 1, "learn step"),
        sum_payload = positions(learn_integer_add_forloop, "\104\102\000\000", 1, "learn sum payload"),
        resume = positions(learn_integer_add_forloop, "\153\136\119\102", 1, "learn resume"),
    },
    fused_integer_loop = {
        code = fused_integer_loop,
        index_tag = {}, limit_tag = {}, step_tag = {},
        index_payload = positions(fused_integer_loop, "\024\017\000\000", 2, "fused index"),
        limit_payload = positions(fused_integer_loop, "\072\068\000\000", 1, "fused limit"),
        step_payload = positions(fused_integer_loop, "\088\085\000\000", 1, "fused step"),
        sum_tag = positions(fused_integer_loop, "\096\102\000\000", 1, "fused sum tag"),
        sum_payload = positions(fused_integer_loop, "\104\102\000\000", 2, "fused sum payload"),
        resume = positions(fused_integer_loop, "\153\136\119\102", 2, "fused resume"),
    },
}

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
file:write("return ", serialize(bank), "\n")
file:close()
print(("Lua55 trace stencil bank: fused_integer_loop=%d bytes"):format(#fused_integer_loop))
