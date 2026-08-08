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

-- CONCAT (53): R[A] := R[A] .. R[A+1] .. ... (string / integer / float
-- operands; the number converters come from the shared fmt library).
ffi.cdef("int lua55_dtoa_g14(double x, char *buf);")
ffi.cdef("int lua55_itoa_ll(int64_t v, char *buf);")
local FMT = ffi.load("target/copy_patch_cps/lua55_trace/liblua55fmt.so")
local DTOA_ADDR = tonumber(ffi.cast("uintptr_t", ffi.cast("void *", FMT.lua55_dtoa_g14)))
local ITOA_ADDR = tonumber(ffi.cast("uintptr_t", ffi.cast("void *", FMT.lua55_itoa_ll)))

local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
end

local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "target", occurrence.target)
    patch_many(arena, offset, record.holes.base_reg, occurrence.base, patch_i32)
    patch_many(arena, offset, record.holes.count, occurrence.count, patch_i32)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    patch_many(arena, offset, record.holes.dtoa_addr, DTOA_ADDR, patch_u64)
    patch_many(arena, offset, record.holes.itoa_addr, ITOA_ADDR, patch_u64)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local ConcatOccurrence = {}
ConcatOccurrence.__index = ConcatOccurrence

function ConcatOccurrence.new(pc, target, base, count)
    return setmetatable({
        pc = pc, target = target, base = base, count = count,
        fallthrough_pc = pc + 1, quote_base = 53 * 65536,
        learner_name = "concat",
    }, ConcatOccurrence)
end

function ConcatOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.concat, self, true)
end

function ConcatOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "concat quotation is absent")
    append_occurrence(arena, record, self, false)
end


-- ---- Native CPS Frame V2 leaf -----------------------------------------
function ConcatOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[53], {
        target_index = self.target,
        setlist_base = self.base,
        setlist_count = self.count,
        ["u64::itoa_addr"] = ITOA_ADDR,
        ["u64::dtoa_addr"] = DTOA_ADDR,
    })
end

return {
    ConcatOccurrence = ConcatOccurrence,
    FMT = FMT,
    ffi = ffi,
}
