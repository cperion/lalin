package.path = "./?.lua;./?/init.lua;" .. package.path

local Prepatched = require("experiments.copy_patch_cps.u64_prepatched_variants")
local RuntimeSlot = require("experiments.copy_patch_cps.u64_runtime_slot")
local bank = dofile("target/copy_patch_cps/u64_runtime/variant_bank.lua")
local library = Prepatched.Library.new(bank)

local maximum = 0
for addend = 0, 1 do
    for xor_value = 0, 1 do
        for rotate = 0, 63 do
            maximum = math.max(maximum, library:select(addend, xor_value, rotate).size)
        end
    end
end

local slot = RuntimeSlot.Slot.new(maximum)
assert(slot:permissions():sub(1, 3) == "rw-")

local generations = 0
for _, facts in ipairs({
    { 0, 0, 0 }, { 9, 0, 0 }, { 0, 7, 0 }, { 9, 7, 0 },
    { 0, 0, 1 }, { 9, 0, 17 }, { 0, 7, 31 }, { 9, 7, 63 },
}) do
    local variant = library:select(facts[1], facts[2], facts[3])
    slot:install(variant)
    generations = generations + 1
    assert(slot.generation == generations)
    assert(slot.variant == variant)
    assert(slot:permissions():sub(1, 3) == "r-x")
    assert(slot:bytes():sub(1, variant.size) == variant:bytes())
end

slot.borrowed = true
local blocked = pcall(function() slot:install(library:select(0, 0, 0)) end)
assert(not blocked, "borrowed U64 runtime slot was replaced")
slot.borrowed = false

slot:free()
local reusable = pcall(function() slot:install(library:select(0, 0, 0)) end)
assert(not reusable, "released U64 runtime slot was reused")
print(("U64 runtime slot: ok capacity=%d generations=%d W^X=true"):format(
    maximum, generations))
