package.path = "./?.lua;./?/init.lua;" .. package.path

local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

local function command(text)
    local ok, reason, status = os.execute(text)
    assert(ok, ("command failed (%s %s): %s"):format(
        tostring(reason), tostring(status), text))
end

local function capture(text)
    local pipe = assert(io.popen(text, "r"))
    local output = pipe:read("*a")
    local ok, reason, status = pipe:close()
    assert(ok, ("command failed (%s %s): %s"):format(
        tostring(reason), tostring(status), text))
    return output
end

local function read_all(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

assert(capture("uname -m"):match("^x86_64%s*$"),
    "F64MapPipelineV1 bank requires x86-64")
local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local out = "target/copy_patch_cps/vector"
local object = out .. "/vector_stencils.o"
command("mkdir -p " .. quote(out))

local flags = table.concat({
    "-O3", "-mavx2", "-mfma", "-fno-pic", "-ffunction-sections",
    "-fno-stack-protector", "-fno-asynchronous-unwind-tables",
    "-fno-unwind-tables",
}, " ")
command(("gcc %s -c %s -o %s"):format(
    flags, quote(base .. "vector_stencils.c"), quote(object)))
command(("objdump -drwC %s > %s"):format(
    quote(object), quote(out .. "/vector_stencils.asm")))

local relocations, current = {}, nil
local relocation_text = capture("readelf -rW " .. quote(object))
for line in relocation_text:gmatch("[^\n]+") do
    local section = line:match("^Relocation section '([^']+)'")
    if section ~= nil then
        current = section
        relocations[current] = relocations[current] or {}
    elseif current ~= nil then
        local at, kind, symbol, sign, addend = line:match(
            "^%s*([%da-fA-F]+)%s+[%da-fA-F]+%s+(R_%S+)%s+[%da-fA-F]+%s+(%S+)%s+([+-])%s+([%da-fA-F]+)")
        if at ~= nil then
            relocations[current][#relocations[current] + 1] = {
                at = assert(tonumber(at, 16)), kind = kind, symbol = symbol,
                addend = (sign == "-" and -1 or 1) * assert(tonumber(addend, 16)),
            }
        end
    end
end

local function section(stencil)
    local path = out .. "/" .. stencil .. ".bin"
    os.remove(path)
    command(("objcopy --dump-section %s=%s %s"):format(
        quote(".text." .. stencil), quote(path), quote(object)))
    return read_all(path)
end

local function exact(stencil, symbols)
    local found = assert(relocations[".rela.text." .. stencil],
        "missing relocations for " .. stencil)
    assert(#found == #symbols, stencil .. " relocation count changed")
    local offsets = {}
    for index = 1, #symbols do
        local item = found[index]
        assert(item.kind == "R_X86_64_PLT32", stencil .. " relocation kind changed")
        assert(item.symbol == symbols[index], stencil .. " relocation order changed")
        assert(item.addend == -4, stencil .. " relocation addend changed")
        offsets[index] = item.at
    end
    return offsets
end

local VZEROUPPER = "\197\248\119"

local function tail(stencil, symbol)
    local bytes = section(stencil)
    local relocation = exact(stencil, { symbol })[1]
    assert(relocation + 4 == #bytes, stencil .. " successor jump is not terminal")
    assert(bytes:byte(relocation) == 0xe9, stencil .. " successor is not E9 rel32")
    assert(not bytes:find(VZEROUPPER, 1, true), stencil .. " contains vzeroupper")
    return bytes, relocation
end

local function prefix(stencil, symbol)
    local bytes, relocation = tail(stencil, symbol)
    return bytes:sub(1, relocation - 1)
end

local entry_code, entry = tail("cpv_stencil_entry", "cpv_entry_next")
local vector_test_code = section("cpv_stencil_vector_test")
local vector_test = exact("cpv_stencil_vector_test", { "cpv_vector_full", "cpv_vector_tail" })
local vector_load_prefix = prefix("cpv_stencil_vector_load", "cpv_vector_load_next")
local vector_store_code, vector_store = tail(
    "cpv_stencil_vector_store", "cpv_vector_store_next")
local scalar_test_code = section("cpv_stencil_scalar_test")
local scalar_test = exact("cpv_stencil_scalar_test", { "cpv_scalar_some", "cpv_scalar_done" })
local scalar_load_prefix = prefix("cpv_stencil_scalar_load", "cpv_scalar_load_next")
local scalar_store_code, scalar_store = tail(
    "cpv_stencil_scalar_store", "cpv_scalar_store_next")

local add0 = prefix("cpv_stencil_add0", "cpv_add0_next")
local add1 = prefix("cpv_stencil_add1", "cpv_add1_next")
local add2 = prefix("cpv_stencil_add2", "cpv_add2_next")
local add3 = prefix("cpv_stencil_add3", "cpv_add3_next")
local mul0 = prefix("cpv_stencil_mul0", "cpv_mul0_next")
local mul1 = prefix("cpv_stencil_mul1", "cpv_mul1_next")
local mul2 = prefix("cpv_stencil_mul2", "cpv_mul2_next")
local mul3 = prefix("cpv_stencil_mul3", "cpv_mul3_next")
local square = prefix("cpv_stencil_square", "cpv_square_next")
local finish_code = section("cpv_stencil_finish")

for label, bytes in pairs({
    vector_test = vector_test_code, scalar_test = scalar_test_code,
}) do
    assert(not bytes:find(VZEROUPPER, 1, true), label .. " contains vzeroupper")
end
assert(finish_code == VZEROUPPER .. "\195",
    "finish stencil is not exactly vzeroupper; ret")

local gcc = capture("gcc --version | head -n 1"):gsub("%s+$", "")
local file = assert(io.open(out .. "/vector_bank.lua", "wb"))
file:write("local Linker = require(\"experiments.copy_patch_cps.vector_linker\")\n")
file:write("return Linker.Bank {\n")
local function field(name, value)
    file:write(("  %s = %q,\n"):format(name, value))
end
local function number(name, value)
    file:write(("  %s = %d,\n"):format(name, value))
end
field("gcc", gcc)
field("entry_code", entry_code); number("entry_next", entry)
field("vector_test_code", vector_test_code)
number("vector_full", vector_test[1]); number("vector_tail", vector_test[2])
field("vector_load_prefix", vector_load_prefix)
field("vector_store_code", vector_store_code); number("vector_store_next", vector_store)
field("scalar_test_code", scalar_test_code)
number("scalar_some", scalar_test[1]); number("scalar_done", scalar_test[2])
field("scalar_load_prefix", scalar_load_prefix)
field("scalar_store_code", scalar_store_code); number("scalar_store_next", scalar_store)
field("add0_prefix", add0); field("add1_prefix", add1)
field("add2_prefix", add2); field("add3_prefix", add3)
field("mul0_prefix", mul0); field("mul1_prefix", mul1)
field("mul2_prefix", mul2); field("mul3_prefix", mul3)
field("square_prefix", square); field("finish_code", finish_code)
file:write("}\n")
file:close()

print(("F64MapPipelineV1 bank: entry=%d vector_test=%d scalar_test=%d op=%d gcc=%s"):format(
    #entry_code, #vector_test_code, #scalar_test_code, #square, gcc))
