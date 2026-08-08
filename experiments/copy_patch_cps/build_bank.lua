package.path = "./?.lua;./?/init.lua;" .. package.path

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

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

local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
assert(capture("uname -m"):match("^x86_64%s*$"),
    "copy-patch CPS bank currently requires x86-64")
local out = "target/copy_patch_cps"
local object = out .. "/stencils.o"
command("mkdir -p " .. shell_quote(out))

local flags = table.concat({
    "-O3", "-fno-pic", "-ffunction-sections", "-fno-stack-protector",
    "-fno-asynchronous-unwind-tables", "-fno-unwind-tables",
}, " ")
command(("gcc %s -c %s -o %s"):format(
    flags, shell_quote(base .. "stencils.c"), shell_quote(object)))
command(("objdump -drwC %s > %s"):format(
    shell_quote(object), shell_quote(out .. "/stencils.asm")))

local function dump_section(stencil)
    local path = out .. "/" .. stencil .. ".bin"
    os.remove(path)
    command(("objcopy --dump-section %s=%s %s"):format(
        shell_quote(".text." .. stencil), shell_quote(path), shell_quote(object)))
    return read_all(path)
end

local relocations = {}
local current
local relocation_text = capture("readelf -rW " .. shell_quote(object))
for line in relocation_text:gmatch("[^\n]+") do
    local section = line:match("^Relocation section '([^']+)'")
    if section ~= nil then
        current = section
        relocations[current] = relocations[current] or {}
    elseif current ~= nil then
        local offset, kind, symbol, sign, addend = line:match(
            "^%s*([%da-fA-F]+)%s+[%da-fA-F]+%s+(R_%S+)%s+[%da-fA-F]+%s+(%S+)%s+([+-])%s+([%da-fA-F]+)")
        if offset ~= nil then
            relocations[current][#relocations[current] + 1] = {
                offset = assert(tonumber(offset, 16)),
                kind = kind,
                symbol = symbol,
                addend = (sign == "-" and -1 or 1) * assert(tonumber(addend, 16)),
            }
        end
    end
end

local function exact_relocations(section, expected)
    local found = assert(relocations[".rela.text." .. section],
        "missing relocation section for " .. section)
    assert(#found == #expected, section .. " has an unexpected relocation count")
    local offsets = {}
    for index = 1, #expected do
        local relocation = found[index]
        assert(relocation.kind == "R_X86_64_PLT32",
            section .. " has unsupported relocation " .. tostring(relocation.kind))
        assert(relocation.symbol == expected[index],
            section .. " relocation order changed: " .. tostring(relocation.symbol))
        assert(relocation.addend == -4, section .. " successor addend is not -4")
        offsets[index] = relocation.offset
    end
    return offsets
end

local entry_code = dump_section("copy_patch_stencil_entry")
local loop_code = dump_section("copy_patch_stencil_loop")
local body_code = dump_section("copy_patch_stencil_body")
local finish_code = dump_section("copy_patch_stencil_finish")

local entry = exact_relocations(
    "copy_patch_stencil_entry", { "copy_patch_entry_next" })
local loop = exact_relocations(
    "copy_patch_stencil_loop", { "copy_patch_loop_repeat", "copy_patch_loop_exit" })
local body = exact_relocations(
    "copy_patch_stencil_body", { "copy_patch_body_next" })
assert(relocations[".rela.text.copy_patch_stencil_finish"] == nil,
    "finish stencil unexpectedly has relocations")

local function assert_tail_jump(code, relocation, label)
    assert(relocation >= 1 and code:byte(relocation) == 0xe9,
        label .. " successor is not an x86-64 direct tail jump")
end
assert_tail_jump(entry_code, entry[1], "entry")
assert_tail_jump(loop_code, loop[1], "loop repeat")
assert_tail_jump(loop_code, loop[2], "loop exit")
assert_tail_jump(body_code, body[1], "body")
assert(finish_code:byte(#finish_code) == 0xc3, "finish stencil does not return")

local gcc = capture("gcc --version | head -n 1"):gsub("%s+$", "")
local bank_path = out .. "/bank.lua"
local bank = assert(io.open(bank_path, "wb"))
bank:write("local Linker = require(\"experiments.copy_patch_cps.linker\")\n")
bank:write("return Linker.Bank {\n")
bank:write(("  gcc = %q,\n"):format(gcc))
bank:write(("  entry_code = %q, entry_next = %d,\n"):format(entry_code, entry[1]))
bank:write(("  loop_code = %q, loop_repeat = %d, loop_exit = %d,\n"):format(
    loop_code, loop[1], loop[2]))
bank:write(("  body_code = %q, body_next = %d,\n"):format(body_code, body[1]))
bank:write(("  finish_code = %q,\n"):format(finish_code))
bank:write("}\n")
bank:close()

print(("copy-patch stencil bank: %s entry=%d loop=%d body=%d finish=%d"):format(
    gcc, #entry_code, #loop_code, #body_code, #finish_code))
