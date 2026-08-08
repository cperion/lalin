local RuntimeSlot = require("experiments.copy_patch_cps.u64_runtime_slot")
local ffi = require("ffi")

ffi.cdef[[
typedef struct U64LearnedLoopFrame {
    const uint64_t *input; uint64_t *output; uint64_t count;
    uint64_t addend; uint64_t xor_value; uint64_t rotate;
} U64LearnedLoopFrame;
typedef struct U64NativeVariant { const uint8_t *code; uint64_t size; } U64NativeVariant;
typedef struct U64NativeLearner {
    U64LearnedLoopFrame frame;
    uint8_t *slot;
    uint64_t capacity;
    U64NativeVariant variants[8][4][64];
    uint64_t generation;
} U64NativeLearner;
typedef void (*U64LearnedLoopEntry)(U64LearnedLoopFrame *);
int u64_native_learn_and_execute(U64NativeLearner *learner);
]]

local support = ffi.load("target/copy_patch_cps/u64_runtime/native_learner.so")
local ColdFrame, SpecializedFrame = {}, {}
ColdFrame.__index, SpecializedFrame.__index = ColdFrame, SpecializedFrame
local Owner = {}
Owner.__index = Owner

local function install_variant_table(state, library)
    for kind = 0, 7 do
        local addend = bit.band(kind, 1) ~= 0 and 1 or 0
        local xor_value = bit.band(kind, 2) ~= 0 and 1 or 0
        local rotating = bit.band(kind, 4) ~= 0
        for remainder = 0, 3 do
            for rotate = 0, 63 do
                if rotating == (rotate ~= 0) then
                    local variant = library:select(addend, xor_value, rotate, remainder)
                    state.variants[kind][remainder][rotate].code = variant.storage
                    state.variants[kind][remainder][rotate].size = variant.size
                end
            end
        end
    end
end

function Owner.new(library, input, output, count, addend, xor_value, rotate)
    local slot = RuntimeSlot.Slot.new(library.maximum)
    local state = ffi.new("U64NativeLearner")
    state.frame.input, state.frame.output, state.frame.count = input, output, count
    state.frame.addend, state.frame.xor_value, state.frame.rotate = addend, xor_value, rotate
    state.slot, state.capacity = slot.memory, slot.capacity
    install_variant_table(state, library)
    return setmetatable({
        library = library, slot = slot, state = state,
        input_owner = input, output_owner = output, phase = ColdFrame,
    }, Owner)
end

function ColdFrame:execute(owner)
    owner.slot.borrowed = true
    local status = support.u64_native_learn_and_execute(owner.state)
    if status ~= 0 then
        owner.slot.borrowed = false
        error("U64 native learner failed with status " .. status)
    end
    owner.slot:native_installed(owner.library:select(
        tonumber(owner.state.frame.addend), tonumber(owner.state.frame.xor_value),
        tonumber(owner.state.frame.rotate), tonumber(owner.state.frame.count % 4)))
    owner.slot.borrowed = false
    owner.phase = SpecializedFrame
    return owner
end

function SpecializedFrame:execute(owner)
    owner.slot.borrowed = true
    ffi.cast("U64LearnedLoopEntry", owner.slot.memory)(owner.state.frame)
    owner.slot.borrowed = false
    return owner
end

function Owner:execute() return self.phase:execute(self) end
function Owner:free() self.slot:free() end

return { Owner = Owner }
