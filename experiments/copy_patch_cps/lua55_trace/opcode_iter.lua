local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local ffi = Native.ffi

local function patch_i32(memory, offset, value)
    assert(value >= -0x80000000 and value <= 0x7fffffff)
    ffi.cast("int32_t *", memory + offset)[0] = value
end

local function patch_many(arena, offset, holes, value, patch)
    if holes == nil then return end
    for index = 1, #holes do patch(arena.memory, offset + holes[index], value) end
end

-- Native iterators: the stencils use fixed registers (R0=t, R1=k,
-- R2=key, R3=value); only the quote base and resume pc are patched.
local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local NextIterOccurrence = {}
NextIterOccurrence.__index = NextIterOccurrence

function NextIterOccurrence.new(pc)
    return setmetatable({
        pc = pc, fallthrough_pc = pc + 1, quote_base = 128 * 65536,
        learner_name = "next_iter",
    }, NextIterOccurrence)
end

function NextIterOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.next_iter, self, true)
end

function NextIterOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "next_iter quotation is absent")
    append_occurrence(arena, record, self, false)
end

local IPairsIterOccurrence = {}
IPairsIterOccurrence.__index = IPairsIterOccurrence

function IPairsIterOccurrence.new(pc)
    return setmetatable({
        pc = pc, fallthrough_pc = pc + 1, quote_base = 129 * 65536,
        learner_name = "ipairs_iter",
    }, IPairsIterOccurrence)
end

function IPairsIterOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.ipairs_iter, self, true)
end

function IPairsIterOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "ipairs_iter quotation is absent")
    append_occurrence(arena, record, self, false)
end

return {
    NextIterOccurrence = NextIterOccurrence,
    IPairsIterOccurrence = IPairsIterOccurrence,
    ffi = ffi,
}
