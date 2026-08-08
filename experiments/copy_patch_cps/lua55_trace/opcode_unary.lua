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
end

-- A unary occurrence is standalone: Lua 5.5 emits no MMBIN companion for
-- UNM/BNOT/NOT/LEN (lcode.c:codeunexpval), so the native path falls
-- through at pc + 1 and rejects the non-primitive shapes to the host.
local function append_occurrence(arena, record, occurrence)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "target", occurrence.target)
    patch_value_index(arena, offset, record, "source", occurrence.source)
    patch_many(arena, offset, record.holes.target_reserved,
        occurrence.target * ffi.sizeof("Lua55ValueV1") + 4, patch_i32)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    return offset
end

local function class()
    local result = {}
    result.__index = result
    return result
end

local UnaryOccurrence = class()

function UnaryOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners[self.learner_name], self)
end

function UnaryOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "unary quotation is absent")
    append_occurrence(arena, record, self)
end

local function base_occurrence(klass, pc, target, source, opcode)
    return setmetatable({
        pc = pc, target = target, source = source,
        fallthrough_pc = pc + 1,   -- standalone: no owned companion
        quote_base = opcode * 65536, learner_name = nil,
    }, klass)
end

local function make_unary(name, opcode)
    local klass = class()
    function klass.new(pc, target, source)
        local occurrence = base_occurrence(klass, pc, target, source, opcode)
        occurrence.learner_name = name
        return occurrence
    end
    return klass
end

local UnmOccurrence = make_unary("unm", 49)
local BnotOccurrence = make_unary("bnot", 50)
local NotOccurrence = make_unary("not", 51)
local LenOccurrence = make_unary("len", 52)

for _, klass in ipairs({ UnmOccurrence, BnotOccurrence, NotOccurrence, LenOccurrence }) do
    klass.__index = UnaryOccurrence
end


-- ---- Native CPS Frame V2 leaf -----------------------------------------
function UnaryOccurrence:append_v2(machine)
    local opcode = math.floor(self.quote_base / 65536)
    machine:emit(machine.bank.v2[opcode], {
        target_index = self.target, source_index = self.source,
    })
end

return {
    UnmOccurrence = UnmOccurrence,
    BnotOccurrence = BnotOccurrence,
    NotOccurrence = NotOccurrence,
    LenOccurrence = LenOccurrence,
    ffi = ffi,
}
