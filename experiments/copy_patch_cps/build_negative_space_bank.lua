package.path = "./?.lua;./?/init.lua;" .. package.path

local function q(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function command(text)
    local ok, why, status = os.execute(text)
    assert(ok, ("command failed (%s %s): %s"):format(tostring(why), tostring(status), text))
end
local function capture(text)
    local pipe = assert(io.popen(text, "r")); local output = pipe:read("*a")
    local ok, why, status = pipe:close()
    assert(ok, ("command failed (%s %s): %s"):format(tostring(why), tostring(status), text))
    return output
end
local function read(path)
    local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value
end

assert(capture("uname -m"):match("^x86_64%s*$"), "negative-space bank requires x86-64")
local base = debug.getinfo(1, "S").source:match("^@(.*/)") or ""
local out = "target/copy_patch_cps/negative_space"
local object = out .. "/stencils.o"
command("mkdir -p " .. q(out))
local flags = table.concat({
    "-O3", "-mavx2", "-mfma", "-ffp-contract=off", "-fno-pic",
    "-ffunction-sections", "-fno-stack-protector",
    "-fno-asynchronous-unwind-tables", "-fno-unwind-tables",
}, " ")
command(("gcc %s -c %s -o %s"):format(
    flags, q(base .. "negative_space_stencils.c"), q(object)))
command(("objdump -drwC %s > %s"):format(object, q(out .. "/stencils.asm")))

local relocation_text = capture("readelf -rW " .. q(object))
assert(not relocation_text:match("%.rela%.text%.ns_"),
    "negative-space superstencil unexpectedly contains a code relocation")

local function section(name)
    local path = out .. "/" .. name .. ".bin"; os.remove(path)
    command(("objcopy --dump-section %s=%s %s"):format(
        q(".text." .. name), q(path), q(object)))
    local bytes = read(path)
    assert(bytes:find("\195", 1, true), name .. " does not contain a return")
    return bytes
end

local names = {
    "ns_f64_reduction", "ns_f64_min_number", "ns_f64_max_number",
    "ns_u8_scan", "ns_u8_find_any2", "ns_u8_find_any4",
    "ns_u8_count_byte", "ns_u8_all_equal",
    "ns_f64_zip_add", "ns_f64_zip_multiply", "ns_f64_zip_map",
    "ns_f32_map", "ns_u64_bulk",
}
local values = {}
for index = 1, #names do values[index] = section(names[index]) end
local gcc = capture("gcc --version | head -n 1"):gsub("%s+$", "")
local file = assert(io.open(out .. "/bank.lua", "wb"))
file:write("local L = require(\"experiments.copy_patch_cps.negative_space_linker\")\n")
file:write("return L.Bank {\n")
file:write(("  gcc = %q,\n"):format(gcc))
for index = 1, #names do file:write(("  %s = %q,\n"):format(names[index], values[index])) end
file:write("}\n"); file:close()
print(("negative-space superstencil bank: entries=%d bytes=%d"):format(
    #values, (function() local sum = 0; for i = 1, #values do sum = sum + #values[i] end; return sum end)()))
