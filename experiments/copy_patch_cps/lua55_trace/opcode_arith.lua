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

-- An arithmetic occurrence owns its companion (MMBIN/MMBINI/MMBINK): a numeric
-- success skips it (fallthrough at pc + 2). MOD/IDIV integer zero-divisor
-- exits at the primitive PC with status COMPLETED; the host re-executes and
-- raises. Tag changes are guard exits to the primitive PC.
local function append_occurrence(arena, record, occurrence)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "target", occurrence.target)
    patch_value_index(arena, offset, record, "left", occurrence.left)
    if occurrence.right ~= nil then
        patch_value_index(arena, offset, record, "right", occurrence.right)
    end
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    if occurrence.imm ~= nil then
        patch_many(arena, offset, record.holes.int_imm,
            ffi.cast("uint64_t", ffi.new("int64_t", occurrence.imm)), patch_u64)
    end
    if occurrence.const ~= nil then
        patch_many(arena, offset, record.holes.const_tag, occurrence.const.tag, patch_i32)
        patch_many(arena, offset, record.holes.const_int, occurrence.const.int_bits, patch_u64)
        patch_many(arena, offset, record.holes.const_flt, occurrence.const.flt_bits, patch_u64)
    end
    return offset
end

local function class()
    local result = {}
    result.__index = result
    return result
end

local ArithOccurrence = class()

function ArithOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners[self.learner_name], self)
end

function ArithOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "arithmetic quotation is absent")
    append_occurrence(arena, record, self)
end

local function base_occurrence(klass, pc, target, left, right, opcode)
    return setmetatable({
        pc = pc, target = target, left = left, right = right,
        fallthrough_pc = pc + 2,   -- skip the owned companion
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

local function number_constant_facts(constant)
    -- decoded 5.5 number constant (int or float)
    if constant.t == "int" then
        return { tag = 3, int_bits = int64_bits(constant.v), flt_bits = 0 }
    end
    return { tag = 4, int_bits = 0, flt_bits = float_bits(constant.v) }
end

local function reg_reg_occurrence(klass, opcode, pc, target, left, right)
    local occurrence = base_occurrence(klass, pc, target, left, right, opcode)
    occurrence.learner_name = nil
    return occurrence
end

local function make_rr(name, opcode)
    local klass = class()
    function klass.new(pc, target, left, right)
        local occurrence = reg_reg_occurrence(klass, opcode, pc, target, left, right)
        occurrence.learner_name = name
        return occurrence
    end
    return klass
end

local AddOccurrence = make_rr("add", 34)
local SubOccurrence = make_rr("sub", 35)
local MulOccurrence = make_rr("mul", 36)
local ModOccurrence = make_rr("mod", 37)
local DivOccurrence = make_rr("div", 39)
local IDivOccurrence = make_rr("idiv", 40)
local BandOccurrence = make_rr("band", 41)
local BorOccurrence = make_rr("bor", 42)
local BXorOccurrence = make_rr("bxor", 43)
local ShlOccurrence = make_rr("shl", 44)
local ShrOccurrence = make_rr("shr", 45)

local function reg_imm_occurrence(klass, opcode, pc, target, left, imm)
    local occurrence = base_occurrence(klass, pc, target, left, nil, opcode)
    occurrence.imm = imm
    occurrence.learner_name = nil
    return occurrence
end

local function make_ri(name, opcode)
    local klass = class()
    function klass.new(pc, target, left, imm)
        local occurrence = reg_imm_occurrence(klass, opcode, pc, target, left, imm)
        occurrence.learner_name = name
        return occurrence
    end
    return klass
end

local AddIOccurrence = make_ri("addi", 21)
local ShlIOccurrence = make_ri("shli", 32)
local ShrIOccurrence = make_ri("shri", 33)

local function reg_const_occurrence(klass, opcode, pc, target, left, constant)
    local occurrence = base_occurrence(klass, pc, target, left, nil, opcode)
    occurrence.const = number_constant_facts(constant)
    occurrence.learner_name = nil
    return occurrence
end

local function make_rk(name, opcode)
    local klass = class()
    function klass.new(pc, target, left, constant)
        local occurrence = reg_const_occurrence(klass, opcode, pc, target, left, constant)
        occurrence.learner_name = name
        return occurrence
    end
    return klass
end

local AddKOccurrence = make_rk("addk", 22)
local SubKOccurrence = make_rk("subk", 23)
local MulKOccurrence = make_rk("mulk", 24)
local ModKOccurrence = make_rk("modk", 25)
local DivKOccurrence = make_rk("divk", 27)
local IDivKOccurrence = make_rk("idivk", 28)
local BandKOccurrence = make_rk("bandk", 29)
local BorKOccurrence = make_rk("bork", 30)
local BXorKOccurrence = make_rk("bxork", 31)

local classes = {}
for _, klass in ipairs({ AddOccurrence, SubOccurrence, MulOccurrence, ModOccurrence,
    DivOccurrence, IDivOccurrence, BandOccurrence, BorOccurrence, BXorOccurrence,
    ShlOccurrence, ShrOccurrence, AddIOccurrence, ShlIOccurrence, ShrIOccurrence,
    AddKOccurrence, SubKOccurrence, MulKOccurrence, ModKOccurrence, DivKOccurrence,
    IDivKOccurrence, BandKOccurrence, BorKOccurrence, BXorKOccurrence }) do
    klass.__index = ArithOccurrence
    classes[#classes + 1] = klass
end


-- ---- Native CPS Frame V2 leaf -----------------------------------------
function ArithOccurrence:append_v2(machine)
    local opcode = math.floor(self.quote_base / 65536)
    local product = {
        target_index = self.target,
        left_index = self.left,
        right_index = self.right,
    }
    if self.imm ~= nil then
        product["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm))
    end
    if self.const ~= nil then
        product.const_tag = self.const.tag
        product["u64::const_int"] = self.const.int_bits
        product["u64::const_flt"] = self.const.flt_bits
    end
    machine:emit(machine.bank.v2[opcode], product)
end

return {
    AddOccurrence = AddOccurrence, SubOccurrence = SubOccurrence, MulOccurrence = MulOccurrence,
    ModOccurrence = ModOccurrence, DivOccurrence = DivOccurrence, IDivOccurrence = IDivOccurrence,
    BandOccurrence = BandOccurrence, BorOccurrence = BorOccurrence, BXorOccurrence = BXorOccurrence,
    ShlOccurrence = ShlOccurrence, ShrOccurrence = ShrOccurrence,
    AddIOccurrence = AddIOccurrence, ShlIOccurrence = ShlIOccurrence, ShrIOccurrence = ShrIOccurrence,
    AddKOccurrence = AddKOccurrence, SubKOccurrence = SubKOccurrence, MulKOccurrence = MulKOccurrence,
    ModKOccurrence = ModKOccurrence, DivKOccurrence = DivKOccurrence, IDivKOccurrence = IDivKOccurrence,
    BandKOccurrence = BandKOccurrence, BorKOccurrence = BorKOccurrence, BXorKOccurrence = BXorKOccurrence,
    ffi = ffi,
}
