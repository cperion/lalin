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

-- FORLOOP (73): a terminal like the JMP. The host FORPREP boundary prepared
-- the cells (integer: R[A]=count, R[A+1]=step, R[A+2]=idx; float:
-- R[A]=limit, R[A+1]=step, R[A+2]=idx). The occurrence stores the resolved
-- back-edge pc and falls through (fallthrough_pc) when the loop ends.
local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_many(arena, offset, record.holes.base_index, occurrence.A, patch_i32)
    patch_many(arena, offset, record.holes.back_edge, occurrence.back_edge, patch_i32)
    patch_many(arena, offset, record.holes.fallthrough, occurrence.fallthrough_pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local ForLoopOccurrence = {}
ForLoopOccurrence.__index = ForLoopOccurrence

function ForLoopOccurrence.new(pc, A, back_edge)
    return setmetatable({
        pc = pc, A = A, back_edge = back_edge,
        fallthrough_pc = pc + 1,
        quote_base = 73 * 65536, learner_name = "forloop",
    }, ForLoopOccurrence)
end

function ForLoopOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.forloop, self, true)
end

function ForLoopOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "forloop quotation is absent")
    append_occurrence(arena, record, self, false)
end


-- ---- Native CPS Frame V2 leaves ---------------------------------------
function ForLoopOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[73], {
        base_index = self.A,
        ["link:link"] = self.back_edge,
        ["link:fall_link"] = self.fallthrough_pc,
    })
end

return {
    ForLoopOccurrence = ForLoopOccurrence,
    ffi = ffi,
}
