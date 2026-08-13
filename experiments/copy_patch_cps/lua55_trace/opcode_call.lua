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

-- A return occurrence is a terminal: it records one quote, stores the
-- return pc (patched), completes, and returns. The host reads (A, B) from
-- the occurrence to extract the callee's results across the call boundary.
local function append_occurrence(arena, record, occurrence)
    local offset = arena:append(record)
    patch_many(arena, offset, record.holes.return_pc, occurrence.pc, patch_i32)
    if occurrence.quote_base ~= nil then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local function class()
    local result = {}
    result.__index = result
    return result
end

local ReturnOccurrence = class()

function ReturnOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners[self.learner_name], self)
end

function ReturnOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "return quotation is absent")
    append_occurrence(arena, record, self)
end

-- RETURN (70): A B — B-1 results at R[A .. A+B-2].
function ReturnOccurrence.new(pc, A, B)
    return setmetatable({
        pc = pc, A = A, B = B or 0,
        fallthrough_pc = pc + 1,
        quote_base = 70 * 65536, learner_name = "return",
    }, ReturnOccurrence)
end

-- RETURN0 (71): no results.
local Return0Occurrence = class()

function Return0Occurrence.new(pc)
    return setmetatable({
        pc = pc, A = 0, B = 0,
        fallthrough_pc = pc + 1,
        quote_base = 71 * 65536, learner_name = "return0",
    }, Return0Occurrence)
end

Return0Occurrence.append_learner = ReturnOccurrence.append_learner
Return0Occurrence.append_residual = ReturnOccurrence.append_residual
Return0Occurrence.__index = ReturnOccurrence

-- RETURN1 (72): one result at R[A].
local Return1Occurrence = class()

function Return1Occurrence.new(pc, A)
    return setmetatable({
        pc = pc, A = A, B = 2,
        fallthrough_pc = pc + 1,
        quote_base = 72 * 65536, learner_name = "return1",
    }, Return1Occurrence)
end

Return1Occurrence.append_learner = ReturnOccurrence.append_learner
Return1Occurrence.append_residual = ReturnOccurrence.append_residual
Return1Occurrence.__index = ReturnOccurrence


-- ---- Native CPS Frame V2 leaf -----------------------------------------
function ReturnOccurrence:append_v2(machine)
    -- RETURN B==0 consumes the genuinely dynamic top. Fixed RETURN, RETURN0,
    -- and RETURN1 compose one exact source fragment per authored result.
    if self.B == 0 and self.quote_base == 70 * 65536 then
        machine:emit(assert(machine.bank.residual.ret_all,
            "cps v2: missing residual ret_all"), {
            call_a = self.A, call_pc = self.pc,
            base_disp = self.A * ffi.sizeof("Lua55ValueV2"),
        })
        return
    end
    local nres = self.B == 0 and 0 or self.B - 1
    if nres == 1 then
        machine:emit(assert(machine.bank.residual.ret_fixed_one,
            "cps v2: missing exact one-result RETURN residual"), {
            source_disp = self.A * ffi.sizeof("Lua55ValueV2"),
            call_pc = self.pc,
        })
        return
    end
    machine:emit(assert(machine.bank.residual.ret_fixed_begin,
        "cps v2: missing residual ret_fixed_begin"), {
        span = nres, call_pc = self.pc,
    })
    for slot = 0, nres - 1 do
        machine:emit(assert(machine.bank.residual.ret_fixed_slot,
            "cps v2: missing residual ret_fixed_slot"), {
            source_disp = (self.A + slot) * ffi.sizeof("Lua55ValueV2"),
            span = slot,
        })
    end
    machine:emit(assert(machine.bank.residual.ret_fixed_finish,
        "cps v2: missing residual ret_fixed_finish"), { span = nres })
end

return {
    ReturnOccurrence = ReturnOccurrence,
    Return0Occurrence = Return0Occurrence,
    Return1Occurrence = Return1Occurrence,
    ffi = ffi,
}
