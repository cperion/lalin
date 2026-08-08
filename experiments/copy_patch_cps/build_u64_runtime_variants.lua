package.path = "./?.lua;./?/init.lua;" .. package.path

local function q(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function run(command)
    local ok, why, status = os.execute(command)
    assert(ok, ("command failed (%s %s): %s"):format(
        tostring(why), tostring(status), command))
end
local function capture(command)
    local pipe = assert(io.popen(command, "r")); local output = pipe:read("*a")
    local ok, why, status = pipe:close()
    assert(ok, ("command failed (%s %s): %s"):format(
        tostring(why), tostring(status), command))
    return output
end
local function read(path)
    local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value
end

local out = "target/copy_patch_cps/u64_runtime"
local object = out .. "/variants.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -mavx2 -fno-pic -ffunction-sections",
    "-fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/u64_runtime_variants.c"),
    "-c -o", q(object),
}, " "))
run(("objdump -drwC %s > %s"):format(q(object), q(out .. "/variants.asm")))

local relocation_text = capture("readelf -rW " .. q(object))
local ordinary = {
    "u64_copy", "u64_add", "u64_xor", "u64_add_xor",
    "u64_rotate", "u64_add_rotate", "u64_xor_rotate", "u64_add_xor_rotate",
}
local immediate = {
    "u64_rotate_imm", "u64_add_rotate_imm",
    "u64_xor_rotate_imm", "u64_add_xor_rotate_imm",
}

local function section(name)
    local path = out .. "/" .. name .. ".bin"; os.remove(path)
    run(("objcopy --dump-section %s=%s %s"):format(
        q(".text." .. name), q(path), q(object)))
    return read(path)
end

local RIGHT_SENTINEL = "\197\213\115\208\047"
local LEFT_SENTINEL = "\197\253\115\240\017"
local records = {}

local function validate_tail(name, code)
    local count = 0
    for line in relocation_text:gmatch("[^\n]+") do
        if line:match("R_X86_64_PLT32%s+.*" .. name .. "_next%s+%- 4") then count = count + 1 end
    end
    assert(count == 1, name .. " must have one typed tail relocation")
    assert(code:byte(#code - 4) == 0xe9, name .. " tail is not terminal E9 rel32")
end

for index = 1, #ordinary do
    local name = ordinary[index]; local code = section(name); validate_tail(name, code)
    records[#records + 1] = { name = name, code = code }
end
for index = 1, #immediate do
    local name = immediate[index]; local code = section(name); validate_tail(name, code)
    local right = assert(code:find(RIGHT_SENTINEL, 1, true), name .. " missing right Immediate8 hole")
    local left = assert(code:find(LEFT_SENTINEL, 1, true), name .. " missing left Immediate8 hole")
    assert(not code:find(RIGHT_SENTINEL, right + 1, true), name .. " has duplicate right hole")
    assert(not code:find(LEFT_SENTINEL, left + 1, true), name .. " has duplicate left hole")
    records[#records + 1] = {
        name = name, code = code, right = right + 3, left = left + 3,
    }
end

local file = assert(io.open(out .. "/variant_bank.lua", "wb"))
file:write("return {\n")
for index = 1, #records do
    local record = records[index]
    file:write(("  { name = %q, code = %q"):format(record.name, record.code))
    if record.left then file:write((", left = %d, right = %d"):format(record.left, record.right)) end
    file:write(" },\n")
end
file:write("}\n"); file:close()
print(("U64 runtime variants: ok structural=%d immediate=%d total=%d"):format(
    #ordinary, #immediate, #records))
