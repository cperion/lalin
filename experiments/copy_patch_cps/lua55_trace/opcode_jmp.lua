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

-- A JMP occurrence is a terminal: it stores the resolved target pc and
-- completes. The projection resolves target = pc + sJ + 1 (lvm.c:dojump).
local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_many(arena, offset, record.holes.target_pc, occurrence.target, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local JmpOccurrence = {}
JmpOccurrence.__index = JmpOccurrence

function JmpOccurrence.new(pc, target)
    return setmetatable({
        pc = pc, target = target,
        fallthrough_pc = pc + 1,   -- sequential successor; never taken
        quote_base = 56 * 65536, learner_name = "jmp",
    }, JmpOccurrence)
end

function JmpOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.jmp, self, true)
end

function JmpOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "jmp quotation is absent")
    append_occurrence(arena, record, self, false)
end


-- ---- Native CPS Frame V2 leaf -----------------------------------------
function JmpOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[56], {
        ["link:link"] = self.target,
    })
end

return {
    JmpOccurrence = JmpOccurrence,
    ffi = ffi,
}
