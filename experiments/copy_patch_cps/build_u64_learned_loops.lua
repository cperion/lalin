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
local object = out .. "/learned_loops.o"
run("mkdir -p " .. q(out))
run(table.concat({
    "gcc -O3 -mavx2 -fno-pic -ffunction-sections",
    "-fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables",
    q("experiments/copy_patch_cps/u64_learned_loop_stencils.c"),
    "-c -o", q(object),
}, " "))
run(("objdump -drwC %s > %s"):format(q(object), q(out .. "/learned_loops.asm")))
assert(not capture("readelf -rW " .. q(object)):match("%.rela%.text%.u64_"),
    "U64 learned loop unexpectedly contains a code relocation")

local bases = {
    "u64_learn_copy", "u64_learn_add", "u64_learn_xor", "u64_learn_add_xor",
    "u64_learn_rotate_imm", "u64_learn_add_rotate_imm",
    "u64_learn_xor_rotate_imm", "u64_learn_add_xor_rotate_imm",
}
local names = {}
for base = 1, #bases do
    for tail = 0, 3 do names[#names + 1] = bases[base] .. "_tail" .. tail end
end
local RIGHT = "\115\208\047"
local LEFT = "\115\240\017"
local records, maximum = {}, 0

for index = 1, #names do
    local name = names[index]
    local path = out .. "/" .. name .. ".bin"; os.remove(path)
    run(("objcopy --dump-section %s=%s %s"):format(
        q(".text." .. name), q(path), q(object)))
    local code = read(path); maximum = math.max(maximum, #code)
    local record = { name = name, code = code }
    local base_index = math.floor((index - 1) / 4) + 1
    if base_index >= 5 then
        local right = assert(code:find(RIGHT, 1, true), name .. " missing right Immediate8 hole")
        local left = assert(code:find(LEFT, 1, true), name .. " missing left Immediate8 hole")
        assert(not code:find(RIGHT, right + 1, true), name .. " duplicate right hole")
        assert(not code:find(LEFT, left + 1, true), name .. " duplicate left hole")
        record.right, record.left = right + 1, left + 1
    end
    records[index] = record
end

local file = assert(io.open(out .. "/learned_loop_bank.lua", "wb"))
file:write("return { maximum = " .. maximum .. ", variants = {\n")
for index = 1, #records do
    local record = records[index]
    file:write(("  { name = %q, code = %q"):format(record.name, record.code))
    if record.left then file:write((", left = %d, right = %d"):format(record.left, record.right)) end
    file:write(" },\n")
end
file:write("} }\n"); file:close()
print(("U64 learned loop bank: ok variants=%d maximum=%d"):format(#records, maximum))
