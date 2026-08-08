local bank = dofile("target/copy_patch_cps/u64_runtime/variant_bank.lua")

local immediate = 0
for index = 1, #bank do
    local variant = bank[index]
    if variant.left ~= nil then
        immediate = immediate + 1
        assert(variant.code:byte(variant.left + 1) == 0x11)
        assert(variant.code:byte(variant.right + 1) == 0x2f)
        for rotate = 0, 63 do
            local bytes = { variant.code:byte(1, #variant.code) }
            bytes[variant.left + 1] = rotate
            bytes[variant.right + 1] = (64 - rotate) % 64
            local patched = string.char(unpack(bytes))
            assert(patched:byte(variant.left + 1) == rotate)
            assert(patched:byte(variant.right + 1) == (64 - rotate) % 64)
            assert(#patched == #variant.code)
        end
    end
end
assert(immediate == 4)
print("U64 Immediate8 holes: ok variants=4 rotations=64")
