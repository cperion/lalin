package.path = "./?.lua;./?/init.lua;" .. package.path

local Prepatched = require("experiments.copy_patch_cps.u64_prepatched_variants")
local bank = dofile("target/copy_patch_cps/u64_runtime/variant_bank.lua")
local library = Prepatched.Library.new(bank)

local function expected_name(addend, xor_value, rotate)
    local suffix = rotate % 64 == 0 and "" or "_rotate_imm"
    if addend == 0 and xor_value == 0 then return "u64" .. (suffix == "" and "_copy" or suffix) end
    if addend ~= 0 and xor_value == 0 then return "u64_add" .. suffix end
    if addend == 0 and xor_value ~= 0 then return "u64_xor" .. suffix end
    return "u64_add_xor" .. suffix
end

local selections = 0
for _, addend in ipairs({ 0, 7 }) do
    for _, xor_value in ipairs({ 0, 0x55 }) do
        for rotate = 0, 63 do
            local selected = library:select(addend, xor_value, rotate)
            assert(selected.name == expected_name(addend, xor_value, rotate))
            assert(#selected:bytes() == selected.size)
            if rotate == 0 then
                assert(selected.rotate == nil)
            else
                assert(selected.rotate == rotate)
                local record_index = addend == 0 and (xor_value == 0 and 9 or 11)
                    or (xor_value == 0 and 10 or 12)
                local record = bank[record_index]
                local bytes = selected:bytes()
                assert(bytes:byte(record.left + 1) == rotate)
                assert(bytes:byte(record.right + 1) == (64 - rotate) % 64)
            end
            selections = selections + 1
        end
    end
end

assert(selections == 256)
print("U64 prepatched variants: ok selections=256 executable=false")
