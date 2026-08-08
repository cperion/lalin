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

local function patch_value_index(arena, offset, record, role, index)
    local base = index * ffi.sizeof("Lua55ValueV1")
    patch_many(arena, offset, record.holes[role .. "_tag"], base, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_payload"], base + 8, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_reserved"], base + 4, patch_i32)
end

-- CLOSE (54) / TBC (55) / ERRNNIL (82).
local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    if occurrence.target ~= nil then
        patch_value_index(arena, offset, record, "target", occurrence.target)
    end
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local CloseOccurrence = {}
CloseOccurrence.__index = CloseOccurrence

function CloseOccurrence.new(pc, A)
    return setmetatable({
        pc = pc, target = A or 0, A = A or 0,
        fallthrough_pc = pc + 1, quote_base = 54 * 65536,
        learner_name = "close",
    }, CloseOccurrence)
end

function CloseOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.close, self, true)
end

function CloseOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "close quotation is absent")
    append_occurrence(arena, record, self, false)
end

local TbcOccurrence = {}
TbcOccurrence.__index = TbcOccurrence

function TbcOccurrence.new(pc, target)
    return setmetatable({
        pc = pc, target = target,
        fallthrough_pc = pc + 1, quote_base = 55 * 65536,
        learner_name = "tbc",
    }, TbcOccurrence)
end

function TbcOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.tbc, self, true)
end

function TbcOccurrence:append_residual(bank, slot, arena)
    -- never reached: the learner always rejects the <close> contract
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "tbc quotation is absent")
    append_occurrence(arena, record, self, false)
end

local ErrnnilOccurrence = {}
ErrnnilOccurrence.__index = ErrnnilOccurrence

function ErrnnilOccurrence.new(pc, target)
    return setmetatable({
        pc = pc, target = target,
        fallthrough_pc = pc + 1, quote_base = 82 * 65536,
        learner_name = "errnnil",
    }, ErrnnilOccurrence)
end

function ErrnnilOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.errnnil, self, true)
end

function ErrnnilOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "errnnil quotation is absent")
    append_occurrence(arena, record, self, false)
end


-- ---- Native CPS Frame V2 leaves ---------------------------------------
function CloseOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[54], { call_a = self.A or self.target })
end
function TbcOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[55], { call_a = self.target })
end


function ErrnnilOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[82], {
        call_a = self.target,
        call_pc = self.pc,
    })
end

return {
    CloseOccurrence = CloseOccurrence,
    TbcOccurrence = TbcOccurrence,
    ErrnnilOccurrence = ErrnnilOccurrence,
    ffi = ffi,
}
