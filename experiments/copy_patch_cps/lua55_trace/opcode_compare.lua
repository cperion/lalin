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
        or constant.t == "true" and 2 or constant.t == "str" and 5
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
    klass.__index = klass
    setmetatable(klass, { __index = CompareOccurrence })
end


-- ---- Native CPS Frame V2 leaves -----------------------------------------
-- Batch 3: exact operand-product leaves. Operand tag pairs are learned in the
-- separate learning invocation; each comparison class selects its exact leaf
-- from the observed pair and the projection-proven const/imm side. TEST and
-- TESTSET stay green (truthiness is the operation's data result).

local TAG_INT, TAG_FLT, TAG_STR, TAG_LSTR = 3, 4, 5, 6
local TAG_TABLE, TAG_CLOSURE, TAG_NIL, TAG_FALSE, TAG_TRUE = 7, 8, 0, 1, 2

local function compare_facts(machine, slot)
    local f = machine.facts[assert(slot, "cps v2: compare slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: comparison occurrence slot " .. tostring(slot)
            .. " was never observed in the learning pass (cold path);"
            .. " refusing to publish a generic fallback", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: comparison occurrence slot " .. tostring(slot)
            .. " observed conflicting operand tags;"
            .. " refusing to publish a generic fallback", 0)
    end
    return f
end

local function side(tag) return tag == TAG_INT and "i" or "f" end
local function is_num(t) return t == TAG_INT or t == TAG_FLT end
local function is_str(t) return t == TAG_STR or t == TAG_LSTR end
local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

local function base_product(self)
    local product = { left_disp = value_disp(self.left),
        ["link:taken_link"] = self.target_pc }
    if self.right ~= nil then product.right_disp = value_disp(self.right) end
    if self.imm ~= nil then
        product["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm))
    end
    if self.const ~= nil then
        product.const_tag = self.const.tag
        product["u64::const_int"] = self.const.int_bits
        product["u64::const_flt"] = self.const.flt_bits
        product["u64::const_ref"] = self.const.ref
    end
    return product
end

local function learn_emit(machine, self)
    local product = base_product(self)
    product.k = self.k
    product.occ_slot = assert(self.learn_slot, "cps v2: compare slot unassigned")
    local base = self.learner_name:gsub("_k%d+$", "")
    machine:emit(machine.bank.learning[assert(base,
        "cps v2: compare learner missing")], product)
end

local function emit_residual(machine, self, name, extra)
    local product = base_product(self)
    for key, value in pairs(extra or {}) do product[key] = value end
    local selected = name .. "_k" .. tostring(self.k)
    machine:emit(assert(machine.bank.residual[selected],
        "cps v2: missing residual " .. selected), product)
end

-- eq: numeric products, string-string, ref identity, same primitive,
-- mixed-false
function EqOccurrence:append_v2(machine)
    if machine.mode == "learning" then learn_emit(machine, self) return end
    local f = compare_facts(machine, self.learn_slot)
    local lt, rt = f.key_tag, f.value_tag
    local name
    if is_num(lt) and is_num(rt) then
        name = "eq_" .. side(lt) .. side(rt)
    elseif is_str(lt) and is_str(rt) then
        name = "eq_ss"
    elseif lt == rt and (lt == TAG_TABLE or lt == TAG_CLOSURE) then
        name = "eq_rr"
    elseif lt == rt and lt <= TAG_TRUE then
        name = "eq_sp"
    else
        name = "eq_mx"
    end
    emit_residual(machine, self, name)
end

-- lt / le (reg-reg)
local function order_leaf(klass, family)
    function klass:append_v2(machine)
        if machine.mode == "learning" then learn_emit(machine, self) return end
        local f = compare_facts(machine, self.learn_slot)
        local lt, rt = f.key_tag, f.value_tag
        local name
        if is_num(lt) and is_num(rt) then
            name = family .. "_" .. side(lt) .. side(rt)
        elseif is_str(lt) and is_str(rt) then
            name = family .. "_ss"
        else
            error("cps v2: comparison slot " .. tostring(self.learn_slot)
                .. " observed unsupported operand pair " .. lt .. "/" .. rt, 0)
        end
        emit_residual(machine, self, name)
    end
end
order_leaf(LtOccurrence, "lt")
order_leaf(LeOccurrence, "le")

-- lti/lei/gti/gei: immediate right is an integer
local function order_imm_leaf(klass, family)
    function klass:append_v2(machine)
        if machine.mode == "learning" then learn_emit(machine, self) return end
        local f = compare_facts(machine, self.learn_slot)
        local name = family .. "_" .. side(f.key_tag) .. "i"
        emit_residual(machine, self, name)
    end
end
order_imm_leaf(LtIOccurrence, "lti")
order_imm_leaf(LeIOccurrence, "lei")
order_imm_leaf(GtIOccurrence, "gti")
order_imm_leaf(GeIOccurrence, "gei")

-- eqi: immediate right is an integer; mixed left yields false
function EqIOccurrence:append_v2(machine)
    if machine.mode == "learning" then learn_emit(machine, self) return end
    local f = compare_facts(machine, self.learn_slot)
    local name
    if f.key_tag == TAG_INT then name = "eqi_ii"
    elseif f.key_tag == TAG_FLT then name = "eqi_fi"
    else name = "eqi_mx" end
    emit_residual(machine, self, name)
end

-- eqk: the constant kind is projection-proven
function EqKOccurrence:append_v2(machine)
    if machine.mode == "learning" then learn_emit(machine, self) return end
    local f = compare_facts(machine, self.learn_slot)
    local ct = self.const and self.const.tag
    local lt = f.key_tag
    local name
    if ct == TAG_INT then
        if lt == TAG_INT then name = "eqk_int_ii"
        elseif lt == TAG_FLT then name = "eqk_int_fi"
        else name = "eqk_int_mx" end
    elseif ct == TAG_FLT then
        if lt == TAG_INT then name = "eqk_flt_if"
        elseif lt == TAG_FLT then name = "eqk_flt_ff"
        else name = "eqk_flt_mx" end
    elseif is_str(ct) then
        if is_str(lt) then name = "eqk_str_ss" else name = "eqk_str_mx" end
    elseif ct == TAG_NIL then name = "eqk_nil"
    elseif ct == TAG_FALSE then name = "eqk_false"
    elseif ct == TAG_TRUE then name = "eqk_true"
    else
        error("cps v2: eqk unsupported constant kind " .. tostring(ct), 0)
    end
    emit_residual(machine, self, name)
end

-- TEST/TESTSET stay green: truthiness is the operation's data result.
function TestOccurrence:append_v2(machine)
    local name = "test_k" .. tostring(self.k)
    machine:emit(assert(machine.bank.residual[name]), {
        left_disp = value_disp(self.left),
        ["link:taken_link"] = self.target_pc,
    })
end
function TestSetOccurrence:append_v2(machine)
    local name = "testset_k" .. tostring(self.k)
    machine:emit(assert(machine.bank.residual[name]), {
        left_disp = value_disp(self.left), target_disp = value_disp(self.right),
        ["link:taken_link"] = self.target_pc,
    })
end

return {
    EqOccurrence = EqOccurrence, LtOccurrence = LtOccurrence, LeOccurrence = LeOccurrence,
    EqKOccurrence = EqKOccurrence, EqIOccurrence = EqIOccurrence,
    LtIOccurrence = LtIOccurrence, LeIOccurrence = LeIOccurrence,
    GtIOccurrence = GtIOccurrence, GeIOccurrence = GeIOccurrence,
    TestOccurrence = TestOccurrence, TestSetOccurrence = TestSetOccurrence,
    ffi = ffi,
}
