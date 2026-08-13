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
function AddOccurrence:project_numeric_for_cycle(boundary, terminal)
    return terminal:project_add_cycle(boundary, self)
end

-- Dictionary accumulation: `t[o.k] = t[o.k] + v` compiles to two GETFIELD
-- reads of the same field (the write key must survive), one GETTABLE, one
-- reg-reg ADD, one SETTABLE, and optionally a source-field GETFIELD before
-- the ADD. The fused leaf reads the key once and the source from either the
-- register (already computed) or the field table.
local SuperAccumulateFieldOccurrence = {}
SuperAccumulateFieldOccurrence.__index = SuperAccumulateFieldOccurrence
function SuperAccumulateFieldOccurrence.new(g1, g2, gt, add, st, src)
    return setmetatable({
        pc = g1.pc, field_receiver = g1.receiver, key_owner = g1.key_owner,
        table_receiver = gt.receiver, source = add.right, src_field = src,
        k1 = g1.target, k2 = g2.target, target = gt.target,
        fallthrough_pc = st.pc + 1, learner_name = "super_accumulate_field",
    }, SuperAccumulateFieldOccurrence)
end

function AddOccurrence:project_accumulate_field(g1, g2, gt, src, st)
    if not (g2.pc == g1.pc + 1 and g2.receiver == g1.receiver
        and g2.key_owner and g1.key_owner
        and g2.key_owner:reference() == g1.key_owner:reference()) then return nil end
    if not (gt.pc == g2.pc + 1 and gt.key == g2.target) then return nil end
    if src then
        -- the source value comes from a third GETFIELD of the same table
        if not (src.pc == gt.pc + 1 and self.pc == src.pc + 1
            and src.receiver == g1.receiver and self.right == src.target
            and src.key_owner
            and src.key_owner:reference() ~= g1.key_owner:reference()) then return nil end
        if src.target == g1.target or src.target == gt.target then return nil end
    else
        if not (self.pc == gt.pc + 1) then return nil end
    end
    if not (self.target == gt.target and self.left == gt.target) then return nil end
    if not (st.pc == self.fallthrough_pc and st.receiver == gt.receiver
        and st.key == g1.target and st.source == self.target
        and st.const_value == nil) then return nil end
    -- the write key (K1) must survive and the two reads must be distinct;
    -- the gettable target may equal the second key copy (K2 == V is the
    -- compiler's in-place register reuse).
    if g1.target == g2.target or gt.target == g1.target then return nil end
    return SuperAccumulateFieldOccurrence.new(g1, g2, gt, self, st, src)
end
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

-- ADDI owns the only currently closed numeric-for body shape. It delegates
-- topology validation to the concrete FORLOOP terminal leaf; no staging
-- opcode-name dispatch selects the superinstruction.
function AddIOccurrence:project_numeric_for_cycle(boundary, terminal)
    return terminal:project_addi_cycle(boundary, self)
end
function AddIOccurrence:project_getfield_addi_super(getfield, setter)
    if self.pc ~= getfield.pc + 1 or self.target ~= getfield.target
        or self.left ~= getfield.target then return nil end
    local project = setter and setter.project_field_addi_super
    if not project then return nil end
    return project(setter, getfield, self)
end

function AddIOccurrence:project_gettable_addi_super(gettable, setter)
    if self.pc ~= gettable.pc + 1 or self.target ~= gettable.target
        or self.left ~= gettable.target then return nil end
    local project = setter and setter.project_table_addi_super
    if not project then return nil end
    return project(setter, gettable, self)
end
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
    klass.__index = klass
    setmetatable(klass, { __index = ArithOccurrence })
    classes[#classes + 1] = klass
end

-- ---- Native CPS Frame V2 leaves -----------------------------------------
-- Batch 3: exact operand-product leaves. Operand tags are learned in the
-- separate learning invocation; the residual pass selects one exact leaf per
-- observed product (IntegerInteger/IntegerFloat/FloatInteger/FloatFloat).
-- Each concrete occurrence class owns its family; shared helpers only carry
-- the common emit mechanics.

local TAG_INT, TAG_FLT = 3, 4

local function facts_of(machine, slot)
    local f = machine.facts[assert(slot, "cps v2: arith slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: arithmetic occurrence slot " .. tostring(slot)
            .. " was never observed in the learning pass (cold path);"
            .. " refusing to publish a generic fallback", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: arithmetic occurrence slot " .. tostring(slot)
            .. " observed conflicting operand tags;"
            .. " refusing to publish a generic fallback", 0)
    end
    return f
end

local function side(tag) return tag == TAG_INT and "i" or "f" end
local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

local function learn_emit(machine, self)
    local product = { target_disp = value_disp(self.target), left_disp = value_disp(self.left),
        occ_slot = assert(self.learn_slot, "cps v2: arith slot unassigned") }
    if self.right ~= nil then product.right_disp = value_disp(self.right) end
    if self.imm ~= nil then
        product["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm))
    end
    if self.const ~= nil then
        product.const_tag = self.const.tag
        product["u64::const_int"] = self.const.int_bits
        product["u64::const_flt"] = self.const.flt_bits
    end
    machine:emit(machine.bank.learning[assert(self.learner_name,
        "cps v2: arith learner missing")], product)
end

local function reg_reg_leaf(klass, family)
    function klass:append_v2(machine)
        if machine.mode == "learning" then learn_emit(machine, self) return end
        local f = facts_of(machine, self.learn_slot)
        local name = family .. "_" .. side(f.key_tag) .. side(f.value_tag)
        machine:emit(assert(machine.bank.residual[name],
            "cps v2: missing residual " .. name), {
            target_disp = value_disp(self.target), left_disp = value_disp(self.left),
            right_disp = value_disp(self.right),
        })
    end
end

local function reg_imm_leaf(klass, family)
    function klass:append_v2(machine)
        if machine.mode == "learning" then learn_emit(machine, self) return end
        local f = facts_of(machine, self.learn_slot)
        local name = family .. "_" .. side(f.key_tag) .. "i"
        machine:emit(assert(machine.bank.residual[name],
            "cps v2: missing residual " .. name), {
            target_disp = value_disp(self.target), left_disp = value_disp(self.left),
            ["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm)),
        })
    end
end

local function reg_const_leaf(klass, family)
    function klass:append_v2(machine)
        if machine.mode == "learning" then learn_emit(machine, self) return end
        local f = facts_of(machine, self.learn_slot)
        local ct = self.const.tag == TAG_INT and "i" or "f"
        local name = family .. "_" .. side(f.key_tag) .. ct
        local product = { target_disp = value_disp(self.target),
            left_disp = value_disp(self.left) }
        if ct == "i" then
            product["u64::const_int"] = self.const.int_bits
        else
            product["u64::const_flt"] = self.const.flt_bits
        end
        machine:emit(assert(machine.bank.residual[name],
            "cps v2: missing residual " .. name), product)
    end
end

reg_reg_leaf(AddOccurrence, "add")
reg_reg_leaf(SubOccurrence, "sub")
reg_reg_leaf(MulOccurrence, "mul")
reg_reg_leaf(ModOccurrence, "mod")
reg_reg_leaf(DivOccurrence, "div")
reg_reg_leaf(IDivOccurrence, "idiv")
reg_reg_leaf(BandOccurrence, "band")
reg_reg_leaf(BorOccurrence, "bor")
reg_reg_leaf(BXorOccurrence, "bxor")
reg_reg_leaf(ShlOccurrence, "shl")
reg_reg_leaf(ShrOccurrence, "shr")
reg_imm_leaf(AddIOccurrence, "addi")
reg_imm_leaf(ShlIOccurrence, "shli")
reg_imm_leaf(ShrIOccurrence, "shri")
reg_const_leaf(AddKOccurrence, "addk")
reg_const_leaf(SubKOccurrence, "subk")
reg_const_leaf(MulKOccurrence, "mulk")
reg_const_leaf(ModKOccurrence, "modk")
reg_const_leaf(IDivKOccurrence, "idivk")
reg_const_leaf(DivKOccurrence, "divk")
reg_const_leaf(BandKOccurrence, "bandk")
reg_const_leaf(BorKOccurrence, "bork")
reg_const_leaf(BXorKOccurrence, "bxork")

function SuperAccumulateFieldOccurrence:append_v2(machine)
    local product = {
        field_receiver = self.field_receiver,
        receiver_index = self.table_receiver, source_index = self.source,
        key_index = self.k1, accum_key2 = self.k2,
        target_index = self.target,
        ["u64::key_ref"] = self.key_owner:reference(),
    }
    if self.src_field then
        product["u64::source_key_ref"] = self.src_field.key_owner:reference()
    end
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot, "cps v2: accumulate slot unassigned")
        local learner = self.src_field and "super_accumulate_field_field"
            or "super_accumulate_field"
        machine:emit(assert(machine.bank.learning[learner],
            "cps v2: missing accumulate learner"), product)
        return
    end
    local f = machine.facts[assert(self.learn_slot, "cps v2: accumulate slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: accumulate was never observed; refusing generic publication", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: accumulate observed conflicting shapes; refusing generic publication", 0)
    end
    local key_kind = f.key_tag == 3 and "int" or "str"
    local acc_kind = f.value_tag == 3 and "int" or "flt"
    local src_kind = (f.max_array_index % 4294967296) == 3 and "int" or "flt"
    machine:emit(assert(machine.bank.residual[
        (self.src_field and "super_accumulate_field_f_" or "super_accumulate_field_r_")
        .. key_kind .. "_" .. acc_kind .. "_" .. src_kind],
        "cps v2: missing exact accumulate residual"), product)
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
    SuperAccumulateFieldOccurrence = SuperAccumulateFieldOccurrence,
    ffi = ffi,
}
