local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local ffi = Native.ffi

local function patch_i32(memory, offset, value)
    assert(value >= -0x80000000 and value <= 0x7fffffff)
    ffi.cast("int32_t *", memory + offset)[0] = value
end

local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
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

-- A comparison occurrence owns its following JMP. The taken branch stores
-- the exact target PC and returns (host resumes there); the not-taken path
-- falls through to the next occurrence. All facts are patched by hole kind,
-- so one generic appender serves every leaf in the family.
local function append_occurrence(arena, record, occurrence)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "left", occurrence.left)
    if occurrence.right ~= nil then
        patch_value_index(arena, offset, record, "right", occurrence.right)
    end
    patch_many(arena, offset, record.holes.target_pc, occurrence.target_pc, patch_i32)
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    if occurrence.imm ~= nil then
        patch_many(arena, offset, record.holes.int_imm,
            ffi.cast("uint64_t", ffi.new("int64_t", occurrence.imm)), patch_u64)
    end
    if occurrence.const ~= nil then
        patch_many(arena, offset, record.holes.const_int,
            occurrence.const.int_bits, patch_u64)
        patch_many(arena, offset, record.holes.const_flt,
            occurrence.const.flt_bits, patch_u64)
        patch_many(arena, offset, record.holes.const_ref,
            occurrence.const.ref, patch_u64)
    end
    return offset
end

local function class()
    local result = {}
    result.__index = result
    return result
end

local CompareOccurrence = class()

function CompareOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners[self.learner_name], self)
end

function CompareOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "comparison quotation is absent")
    append_occurrence(arena, record, self)
end

local function base_occurrence(klass, pc, left, right, k, target_pc, opcode)
    return setmetatable({
        pc = pc, left = left, right = right, k = k, target_pc = target_pc,
        fallthrough_pc = pc + 2,   -- the owned JMP is at pc + 1
        quote_base = opcode * 65536, learner_name = nil,
    }, klass)
end

local function int64_bits(value)
    return ffi.cast("uint64_t", ffi.new("int64_t", value))
end

local function float_bits(value)
    local holder = ffi.new("double[1]", value)
    return ffi.cast("uint64_t *", holder)[0]
end

local EqOccurrence = class()
function EqOccurrence.new(pc, left, right, k, target_pc)
    local occurrence = base_occurrence(EqOccurrence, pc, left, right, k, target_pc, 57)
    occurrence.learner_name = "eq_k" .. k
    return occurrence
end

local LtOccurrence = class()
function LtOccurrence.new(pc, left, right, k, target_pc)
    local occurrence = base_occurrence(LtOccurrence, pc, left, right, k, target_pc, 58)
    occurrence.learner_name = "lt_k" .. k
    return occurrence
end

local LeOccurrence = class()
function LeOccurrence.new(pc, left, right, k, target_pc)
    local occurrence = base_occurrence(LeOccurrence, pc, left, right, k, target_pc, 59)
    occurrence.learner_name = "le_k" .. k
    return occurrence
end

local function constant_facts(constant, heap_owner)
    -- constant is a decoded 5.5 constant leaf (nil/false/true/int/float/short/long str)
    local tag = constant.t == "int" and 3 or constant.t == "flt" and 4
        or constant.t == "nil" and 0 or constant.t == "false" and 1
        or constant.t == "true" and 2 or constant.t == "str" and nil
    if tag == nil then return false end
    local facts = { tag = tag, int_bits = 0, flt_bits = 0, ref = 0 }
    if constant.t == "int" then
        facts.int_bits = int64_bits(constant.v)
    elseif constant.t == "flt" then
        facts.flt_bits = float_bits(constant.v)
    elseif constant.t == "str" then
        assert(heap_owner, "EQK string constant requires a guest heap")
        local owner = constant.v == constant.v and heap_owner:short_string(constant.v) or nil
        -- decoded ShortString/LongString classes are distinguishable by metatable
        local kind = getmetatable(constant).name
        owner = kind == "LongStringConstant" and heap_owner:long_string(constant.v)
            or heap_owner:short_string(constant.v)
        facts.tag = kind == "LongStringConstant" and 6 or 5
        facts.ref = owner:reference()
    end
    return facts
end

local EqKOccurrence = class()
function EqKOccurrence.new(pc, left, constant, k, target_pc, heap_owner)
    local occurrence = base_occurrence(EqKOccurrence, pc, left, nil, k, target_pc, 60)
    occurrence.const = constant_facts(constant, heap_owner)
    occurrence.learner_name = "eqk_k" .. k
    return occurrence
end

local function reg_imm_occurrence(klass, opcode, pc, left, imm, k, target_pc)
    local occurrence = base_occurrence(klass, pc, left, nil, k, target_pc, opcode)
    occurrence.imm = imm
    return occurrence
end

local EqIOccurrence = class()
function EqIOccurrence.new(pc, left, imm, k, target_pc)
    local occurrence = reg_imm_occurrence(EqIOccurrence, 61, pc, left, imm, k, target_pc)
    occurrence.learner_name = "eqi_k" .. k
    return occurrence
end

local LtIOccurrence = class()
function LtIOccurrence.new(pc, left, imm, k, target_pc)
    local occurrence = reg_imm_occurrence(LtIOccurrence, 62, pc, left, imm, k, target_pc)
    occurrence.learner_name = "lti_k" .. k
    return occurrence
end

local LeIOccurrence = class()
function LeIOccurrence.new(pc, left, imm, k, target_pc)
    local occurrence = reg_imm_occurrence(LeIOccurrence, 63, pc, left, imm, k, target_pc)
    occurrence.learner_name = "lei_k" .. k
    return occurrence
end

local GtIOccurrence = class()
function GtIOccurrence.new(pc, left, imm, k, target_pc)
    local occurrence = reg_imm_occurrence(GtIOccurrence, 64, pc, left, imm, k, target_pc)
    occurrence.learner_name = "gti_k" .. k
    return occurrence
end

local GeIOccurrence = class()
function GeIOccurrence.new(pc, left, imm, k, target_pc)
    local occurrence = reg_imm_occurrence(GeIOccurrence, 65, pc, left, imm, k, target_pc)
    occurrence.learner_name = "gei_k" .. k
    return occurrence
end

local TestOccurrence = class()
function TestOccurrence.new(pc, left, k, target_pc)
    local occurrence = base_occurrence(TestOccurrence, pc, left, nil, k, target_pc, 66)
    occurrence.learner_name = "test_k" .. k
    return occurrence
end

local TestSetOccurrence = class()
function TestSetOccurrence.new(pc, left, right, k, target_pc)
    local occurrence = base_occurrence(TestSetOccurrence, pc, left, right, k, target_pc, 67)
    occurrence.learner_name = "teskset_k" .. k
    return occurrence
end

-- all concrete leaves inherit the shared append behaviour
for _, klass in ipairs({ EqOccurrence, LtOccurrence, LeOccurrence, EqKOccurrence,
    EqIOccurrence, LtIOccurrence, LeIOccurrence, GtIOccurrence, GeIOccurrence,
    TestOccurrence, TestSetOccurrence }) do
    klass.__index = CompareOccurrence
end


-- ---- Native CPS Frame V2 leaf -----------------------------------------
function CompareOccurrence:append_v2(machine)
    local opcode = math.floor(self.quote_base / 65536)
    local product = {
        target_index = self.left,   -- compares use 0x111 for the left register
        k = self.k,
    }
    if self.right ~= nil then product.right_index = self.right end
    if self.imm ~= nil then
        product["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm))
    end
    if self.const ~= nil then
        product.const_tag = self.const.tag
        product["u64::const_int"] = self.const.int_bits
        product["u64::const_flt"] = self.const.flt_bits
        product["u64::const_ref"] = self.const.ref
    end
    if self.target_pc ~= nil then product["link:taken_link"] = self.target_pc end
    machine:emit(machine.bank.v2[opcode], product)
end

return {
    EqOccurrence = EqOccurrence, LtOccurrence = LtOccurrence, LeOccurrence = LeOccurrence,
    EqKOccurrence = EqKOccurrence, EqIOccurrence = EqIOccurrence,
    LtIOccurrence = LtIOccurrence, LeIOccurrence = LeIOccurrence,
    GtIOccurrence = GtIOccurrence, GeIOccurrence = GeIOccurrence,
    TestOccurrence = TestOccurrence, TestSetOccurrence = TestSetOccurrence,
    ffi = ffi,
}
