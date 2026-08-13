local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local ffi = Native.ffi

-- Resolve the external libm pow() once: the stencils call it through a
-- patched absolute-address hole (dlsym-equivalent via ffi).
ffi.cdef("double pow(double, double);")
local POW_ADDRESS = tonumber(ffi.cast("uintptr_t", ffi.cast("void *", ffi.C.pow)))
assert(POW_ADDRESS ~= nil and POW_ADDRESS ~= 0, "libm pow unresolved")

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
    patch_many(arena, offset, record.holes[role .. "_reserved"], base + 4, patch_i32)
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
    patch_many(arena, offset, record.holes.pow_address, POW_ADDRESS, patch_u64)
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

local PowOccurrence = class()

function PowOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners[self.learner_name], self)
end

function PowOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "pow quotation is absent")
    append_occurrence(arena, record, self)
end

local function int64_bits(value)
    return ffi.cast("uint64_t", ffi.new("int64_t", value))
end

local function float_bits(value)
    local holder = ffi.new("double[1]", value)
    return ffi.cast("uint64_t *", holder)[0]
end

local function number_constant_facts(constant)
    if constant.t == "int" then
        return { tag = 3, int_bits = int64_bits(constant.v), flt_bits = 0 }
    end
    return { tag = 4, int_bits = 0, flt_bits = float_bits(constant.v) }
end

local function base_occurrence(klass, pc, target, left, right, const, opcode)
    return setmetatable({
        pc = pc, target = target, left = left, right = right, const = const,
        fallthrough_pc = pc + 2,   -- skip the owned companion
        quote_base = opcode * 65536, learner_name = nil,
    }, klass)
end

function PowOccurrence.new(pc, target, left, right)
    local occurrence = base_occurrence(PowOccurrence, pc, target, left, right, nil, 38)
    occurrence.learner_name = "pow"
    return occurrence
end

local PowKOccurrence = class()

function PowKOccurrence.new(pc, target, left, constant)
    local occurrence = base_occurrence(PowKOccurrence, pc, target, left, nil,
        number_constant_facts(constant), 26)
    occurrence.learner_name = "powk"
    return occurrence
end

PowKOccurrence.__index = PowOccurrence

-- ---- Native CPS Frame V2 leaves -----------------------------------------
-- Batch 3: exact operand-product leaves (POW is float-result arithmetic).

local TAG_INT = 3

local function pow_facts(machine, slot)
    local f = machine.facts[assert(slot, "cps v2: pow slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: pow occurrence slot " .. tostring(slot)
            .. " was never observed in the learning pass (cold path);"
            .. " refusing to publish a generic fallback", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: pow occurrence slot " .. tostring(slot)
            .. " observed conflicting operand tags;"
            .. " refusing to publish a generic fallback", 0)
    end
    return f
end

local function side(tag) return tag == TAG_INT and "i" or "f" end
local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

local function pow_learn(machine, self)
    local product = { target_disp = value_disp(self.target),
        left_disp = value_disp(self.left), ["u64::pow_addr"] = POW_ADDRESS,
        occ_slot = assert(self.learn_slot, "cps v2: pow slot unassigned") }
    if self.right ~= nil then product.right_disp = value_disp(self.right) end
    if self.const ~= nil then
        product.const_tag = self.const.tag
        product["u64::const_int"] = self.const.int_bits
        product["u64::const_flt"] = self.const.flt_bits
    end
    machine:emit(machine.bank.learning[assert(self.learner_name,
        "cps v2: pow learner missing")], product)
end

function PowOccurrence:append_v2(machine)
    if machine.mode == "learning" then pow_learn(machine, self) return end
    local f = pow_facts(machine, self.learn_slot)
    local name = "pow_" .. side(f.key_tag) .. side(f.value_tag)
    machine:emit(assert(machine.bank.residual[name],
        "cps v2: missing residual " .. name), {
        target_disp = value_disp(self.target), left_disp = value_disp(self.left),
        right_disp = value_disp(self.right),
        ["u64::pow_addr"] = POW_ADDRESS,
    })
end

function PowKOccurrence:append_v2(machine)
    if machine.mode == "learning" then pow_learn(machine, self) return end
    local f = pow_facts(machine, self.learn_slot)
    local ct = self.const.tag == TAG_INT and "i" or "f"
    local name = "powk_" .. side(f.key_tag) .. ct
    local product = { target_disp = value_disp(self.target),
        left_disp = value_disp(self.left), ["u64::pow_addr"] = POW_ADDRESS }
    if ct == "i" then
        product["u64::const_int"] = self.const.int_bits
    else
        product["u64::const_flt"] = self.const.flt_bits
    end
    machine:emit(assert(machine.bank.residual[name],
        "cps v2: missing residual " .. name), product)
end

return {
    PowOccurrence = PowOccurrence, PowKOccurrence = PowKOccurrence,
    ffi = ffi,
}
