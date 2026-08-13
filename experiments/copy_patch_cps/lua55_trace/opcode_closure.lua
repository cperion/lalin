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

-- CLOSURE (79): R[A] := closure(proto Bx, upvalues). The upvalue
-- descriptors (isinstack, idx) are patched per upvalue (bounded at 4).
local function patch_value_index(arena, offset, record, role, index)
    local base = index * ffi.sizeof("Lua55ValueV1")
    patch_many(arena, offset, record.holes[role .. "_tag"], base, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_payload"], base + 8, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_reserved"], base + 4, patch_i32)
end

local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "target", occurrence.target)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    patch_many(arena, offset, record.holes.proto_index, occurrence.proto_index, patch_i32)
    local descriptors = occurrence.descriptors or {}
    patch_many(arena, offset, record.holes.nupvals, #descriptors, patch_i32)
    local names = { "instack0", "idx0", "instack1", "idx1", "instack2", "idx2", "instack3", "idx3" }
    for index = 1, math.min(#descriptors, 4) do
        local descriptor = descriptors[index]
        patch_many(arena, offset, record.holes[names[(index - 1) * 2 + 1]], descriptor.instack, patch_i32)
        patch_many(arena, offset, record.holes[names[(index - 1) * 2 + 2]], descriptor.idx, patch_i32)
    end
    return offset
end

local ClosureOccurrence = {}
ClosureOccurrence.__index = ClosureOccurrence

function ClosureOccurrence.new(pc, target, proto_index, descriptors)
    return setmetatable({
        pc = pc, target = target, proto_index = proto_index,
        descriptors = descriptors or {},
        fallthrough_pc = pc + 1, quote_base = 79 * 65536,
        learner_name = "closure",
    }, ClosureOccurrence)
end

function ClosureOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.closure, self, true)
end

function ClosureOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "closure quotation is absent")
    append_occurrence(arena, record, self, false)
end


local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

-- ---- Native CPS Frame V2 leaf -----------------------------------------
function ClosureOccurrence:append_v2(machine)
    -- the capture vector is projection-proven; the exact leaf bakes the
    -- count and owns only its capture holes (no runtime nupvals branch)
    local descriptors = self.descriptors or {}
    local n = #descriptors
    assert(n <= 4, "cps v2: unsupported closure capture count " .. tostring(n))
    local product = {
        target_disp = value_disp(self.target),
        proto_index = self.proto_index,
    }
    for i = 0, n - 1 do
        local descriptor = descriptors[i + 1]
        product["instack" .. i] = descriptor.instack
        product["idx" .. i] = descriptor.idx
    end
    machine:emit(assert(machine.bank.residual["closure_" .. n],
        "cps v2: missing residual closure_" .. n), product)
end

return {
    ClosureOccurrence = ClosureOccurrence,
    ffi = ffi,
}
