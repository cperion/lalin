local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local ffi = Native.ffi

local function patch_i32(memory, offset, value)
    assert(value >= -0x80000000 and value <= 0x7fffffff,
        ("patch_i32 out of range: %s at %d"):format(tostring(value), offset))
    ffi.cast("int32_t *", memory + offset)[0] = value
end

local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
end

local function patch_many(arena, offset, holes, value, patch)
    if holes == nil then return end
    for index = 1, #holes do patch(arena.memory, offset + holes[index], value) end
end

-- SETLIST (78): R[A][C+i] := R[A+i] for 1 <= i <= B. The learner writes
-- the elements once and records the table identity; the residual re-writes
-- the current register values under the table guards each run.
local function append_occurrence(arena, record, occurrence, with_quote, table_slot)
    local offset = arena:append(record)
    patch_many(arena, offset, record.holes.base_reg, occurrence.A, patch_i32)
    patch_many(arena, offset, record.holes.count, occurrence.B, patch_i32)
    patch_many(arena, offset, record.holes.key_last, occurrence.C, patch_i32)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    if table_slot ~= nil then
        patch_many(arena, offset, record.holes.table_reference,
            tonumber(table_slot.expected_reference), patch_u64)
        patch_many(arena, offset, record.holes.storage_generation,
            tonumber(table_slot.expected_storage_generation), patch_i32)
        patch_many(arena, offset, record.holes.collection_epoch,
            tonumber(table_slot.expected_collection_epoch), patch_i32)
    end
    return offset
end

local SetListOccurrence = {}
SetListOccurrence.__index = SetListOccurrence

function SetListOccurrence.new(pc, A, B, C)
    return setmetatable({
        pc = pc, A = A, B = B, C = C,
        fallthrough_pc = pc + 1, quote_base = 78 * 65536,
        learner_name = "setlist", table_frame = true,
    }, SetListOccurrence)
end

function SetListOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.setlist, self, true)
end

function SetListOccurrence:append_residual(bank, slot, arena, table_slot)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "setlist quotation is absent")
    append_occurrence(arena, record, self, false, table_slot)
end


local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

-- ---- Native CPS Frame V2 leaf -----------------------------------------
function SetListOccurrence:append_v2(machine)
    -- Array capacity is mutable data; NeedGrow is an operation-owned exit.
    machine:emit_need_grow(machine.bank.residual.setlist_inbounds,
        "setlist_grow", {
        base_disp = value_disp(self.A),
        setlist_count = self.B,
        setlist_key = tonumber(self.C),
    })
    for slot = 1, self.B do
        machine:emit(assert(machine.bank.residual.setlist_slot,
            "cps v2: missing residual setlist_slot"), {
            base_disp = value_disp(self.A),
            source_disp = value_disp(self.A + slot),
            array_disp = (tonumber(self.C) + slot - 1) * ffi.sizeof("Lua55ValueV2"),
        })
    end
end

return {
    SetListOccurrence = SetListOccurrence,
    ffi = ffi,
}
