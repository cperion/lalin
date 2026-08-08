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

-- TFORPREP (75) / TFORLOOP (77): terminal occurrences with a patched
-- resume pc (the TFORCALL pc / the body start).
local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_many(arena, offset, record.holes.base_reg, occurrence.A, patch_i32)
    patch_many(arena, offset, record.holes.target_pc, occurrence.target_pc, patch_i32)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local TForPrepOccurrence = {}
TForPrepOccurrence.__index = TForPrepOccurrence

function TForPrepOccurrence.new(pc, A, tforcall_pc)
    return setmetatable({
        pc = pc, A = A, target_pc = tforcall_pc,
        fallthrough_pc = pc + 1, quote_base = 75 * 65536,
        learner_name = "tforprep",
    }, TForPrepOccurrence)
end

function TForPrepOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.tforprep, self, true)
end

function TForPrepOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "tforprep quotation is absent")
    append_occurrence(arena, record, self, false)
end

local TForLoopOccurrence = {}
TForLoopOccurrence.__index = TForLoopOccurrence

function TForLoopOccurrence.new(pc, A, body_pc)
    return setmetatable({
        pc = pc, A = A, target_pc = body_pc,
        fallthrough_pc = pc + 1, quote_base = 77 * 65536,
        learner_name = "tforloop",
    }, TForLoopOccurrence)
end

function TForLoopOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.tforloop, self, true)
end

function TForLoopOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "tforloop quotation is absent")
    append_occurrence(arena, record, self, false)
end

-- TFORCALL (76): host-mediated iterator dispatch metadata only (no native
-- stencil). The plan builder records it as a call boundary; the driver
-- invokes the iterator f(s, var) and copies C results into R[A+3..].
local TForCallOccurrence = {}
TForCallOccurrence.__index = TForCallOccurrence

function TForCallOccurrence.new(pc, A, C)
    return setmetatable({
        pc = pc, A = A, C = C,
        fallthrough_pc = pc + 1, quote_base = 76 * 65536,
        learner_name = "tforcall",
    }, TForCallOccurrence)
end

function TForCallOccurrence:append_learner(_bank, _arena)
end

function TForCallOccurrence:append_residual(_bank, _slot, _arena)
end


-- ---- Native CPS Frame V2 leaves ---------------------------------------
function TForPrepOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[75], {
        base_index = self.A,
        ["link:taken_link"] = self.target_pc,
    })
end
function TForLoopOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[77], {
        base_index = self.A,
        ["link:body_link"] = self.target_pc,
    })
end

return {
    TForPrepOccurrence = TForPrepOccurrence,
    TForLoopOccurrence = TForLoopOccurrence,
    TForCallOccurrence = TForCallOccurrence,
    ffi = ffi,
}
