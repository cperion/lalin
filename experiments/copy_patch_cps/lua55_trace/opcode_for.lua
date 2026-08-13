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

-- FORLOOP (73): a terminal like the JMP. The host FORPREP boundary prepared
-- the cells (integer: R[A]=count, R[A+1]=step, R[A+2]=idx; float:
-- R[A]=limit, R[A+1]=step, R[A+2]=idx). The occurrence stores the resolved
-- back-edge pc and falls through (fallthrough_pc) when the loop ends.
local function append_occurrence(arena, record, occurrence, with_quote)
    local offset = arena:append(record)
    patch_many(arena, offset, record.holes.base_index, occurrence.A, patch_i32)
    patch_many(arena, offset, record.holes.back_edge, occurrence.back_edge, patch_i32)
    patch_many(arena, offset, record.holes.fallthrough, occurrence.fallthrough_pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    return offset
end

local ForLoopOccurrence = {}
ForLoopOccurrence.__index = ForLoopOccurrence

function ForLoopOccurrence.new(pc, A, back_edge)
    return setmetatable({
        pc = pc, A = A, back_edge = back_edge,
        fallthrough_pc = pc + 1,
        quote_base = 73 * 65536, learner_name = "forloop",
    }, ForLoopOccurrence)
end

-- Named structural products for numeric-for planning. A boundary names the
-- fixed compiler shape. A ForAddICycleOccurrence is one exact superinstruction
-- candidate: FORPREP, one ADDI+MMBINI body, and the matching FORLOOP.
local NumericForBoundary = {}
NumericForBoundary.__index = NumericForBoundary
function NumericForBoundary.new(pc, A, body_pc, skip_pc)
    return setmetatable({ pc = pc, A = A, body_pc = body_pc, skip_pc = skip_pc },
        NumericForBoundary)
end

local ForAddICycleOccurrence = {}
ForAddICycleOccurrence.__index = ForAddICycleOccurrence
function ForAddICycleOccurrence.new(boundary, addi, terminal)
    return setmetatable({
        pc = boundary.pc, A = boundary.A, body_pc = boundary.body_pc,
        skip_pc = boundary.skip_pc, accumulator = addi.target, imm = addi.imm,
        terminal_pc = terminal.pc, learner_name = "super_for_addi",
    }, ForAddICycleOccurrence)
end

local ForAddCycleOccurrence = {}
ForAddCycleOccurrence.__index = ForAddCycleOccurrence
function ForAddCycleOccurrence.new(boundary, add, terminal)
    return setmetatable({
        pc = boundary.pc, A = boundary.A, body_pc = boundary.body_pc,
        skip_pc = boundary.skip_pc, accumulator = add.target,
        terminal_pc = terminal.pc, learner_name = "super_for_add",
    }, ForAddCycleOccurrence)
end

-- The terminal leaf validates the exact cycle topology. The ADDI leaf owns
-- operand-shape validation and delegates here; no opcode-name dispatch selects
-- a sibling superinstruction.
function ForLoopOccurrence:project_addi_cycle(boundary, addi)
    if self.A ~= boundary.A or self.back_edge ~= boundary.body_pc
        or self.fallthrough_pc ~= boundary.skip_pc
        or addi.pc ~= boundary.body_pc or addi.fallthrough_pc ~= self.pc
        or addi.target ~= addi.left
        or (addi.target >= boundary.A and addi.target <= boundary.A + 2) then
        return nil
    end
    return ForAddICycleOccurrence.new(boundary, addi, self)
end

function ForLoopOccurrence:project_add_cycle(boundary, add)
    if self.A ~= boundary.A or self.back_edge ~= boundary.body_pc
        or self.fallthrough_pc ~= boundary.skip_pc
        or add.pc ~= boundary.body_pc or add.fallthrough_pc ~= self.pc
        or add.target ~= add.left or add.right ~= boundary.A + 2
        or (add.target >= boundary.A and add.target <= boundary.A + 2) then
        return nil
    end
    return ForAddCycleOccurrence.new(boundary, add, self)
end

-- Numeric-for with a single constant-value SETTABLE body: `for k = a, b, s
-- do t[k] = const end`. The key register is the induction register (A+2);
-- the const is projection-proven from the bytecode RK operand.
local ForSettableCycleOccurrence = {}
ForSettableCycleOccurrence.__index = ForSettableCycleOccurrence
function ForSettableCycleOccurrence.new(boundary, settable, terminal)
    return setmetatable({
        pc = boundary.pc, A = boundary.A, body_pc = boundary.body_pc,
        skip_pc = boundary.skip_pc, receiver = settable.receiver,
        const_value = settable.const_value, terminal_pc = terminal.pc,
        learner_name = "super_for_settable",
    }, ForSettableCycleOccurrence)
end

function ForLoopOccurrence:project_settable_cycle(boundary, settable)
    if self.A ~= boundary.A or self.back_edge ~= boundary.body_pc
        or self.fallthrough_pc ~= boundary.skip_pc
        or settable.pc ~= boundary.body_pc or settable.fallthrough_pc ~= self.pc
        or settable.key ~= boundary.A + 2 or settable.const_value == nil then
        return nil
    end
    local tag = settable.const_value.tag
    if tag == nil or tag > 6 then return nil end
    return ForSettableCycleOccurrence.new(boundary, settable, self)
end
function ForLoopOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners.forloop, self, true)
end

function ForLoopOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "forloop quotation is absent")
    append_occurrence(arena, record, self, false)
end


local function value_disp(index) return index * ffi.sizeof("Lua55ValueV2") end

-- ---- Native CPS Frame V2 leaves ---------------------------------------
function ForLoopOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        machine:emit(machine.bank.learning.forloop, {
            base_disp = value_disp(self.A),
            ["link:link"] = self.back_edge,
            ["link:fall_link"] = self.fallthrough_pc,
            occ_slot = assert(self.learn_slot, "cps v2: forloop slot unassigned"),
        })
        return
    end
    local f = machine.facts[assert(self.learn_slot,
        "cps v2: forloop slot unassigned")]
    local name
    if f.key_tag == 3 then
        name = "forloop_int"
    else
        name = f.value_tag == 0 and "forloop_flt_pos" or "forloop_flt_neg"
    end
    machine:emit(assert(machine.bank.residual[name],
        "cps v2: missing residual " .. name), {
        base_disp = value_disp(self.A),
        ["link:link"] = self.back_edge,
        ["link:fall_link"] = self.fallthrough_pc,
    })
end

local function super_facts(machine, slot)
    local f = machine.facts[assert(slot, "cps v2: super-for slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: super-for occurrence was never observed; refusing generic publication", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: super-for occurrence observed conflicting shapes; refusing generic publication", 0)
    end
    return f
end

local function tag_char(tag)
    if tag == 3 then return "i" end
    if tag == 4 then return "f" end
    error("cps v2: unsupported super-for learned tag " .. tostring(tag), 0)
end

local CONST_KIND = { [0] = "nil", [1] = "false", [2] = "true", [3] = "int",
    [4] = "flt", [5] = "str", [6] = "str" }

function ForSettableCycleOccurrence:append_v2(machine)
    local product = {
        base_index = self.A, receiver_index = self.receiver,
        ["link:skip_link"] = self.skip_pc,
    }
    if machine.mode == "learning" then
        product.const = self.const_value
        product.occ_slot = assert(self.learn_slot, "cps v2: super-settable slot unassigned")
        machine:emit(assert(machine.bank.learning.super_for_settable,
            "cps v2: missing super-settable learner"), product)
        return
    end
    local f = super_facts(machine, self.learn_slot)
    if f.key_tag ~= 3 then
        error("cps v2: super-settable cycle requires the integer protocol", 0)
    end
    local sign = f.value_tag == 0 and "_pos" or "_neg"
    local kind = assert(CONST_KIND[self.const_value.tag], "cps v2: const kind")
    if kind == "int" then product["u64::const_int"] = self.const_value.int_bits
    elseif kind == "flt" then product["u64::const_flt"] = self.const_value.flt_bits
    elseif kind == "str" then
        product.const_tag = self.const_value.tag
        product["u64::const_ref"] = self.const_value.ref
    end
    machine:emit(assert(machine.bank.residual[
        "super_for_settable_" .. kind .. sign]), product)
end

function ForAddICycleOccurrence:append_v2(machine)
    local product = {
        base_index = self.A, target_index = self.accumulator,
        ["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm)),
        ["link:skip_link"] = self.skip_pc,
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot, "cps v2: super-for slot unassigned")
        machine:emit(assert(machine.bank.learning.super_for_addi,
            "cps v2: missing super-for learner"), product)
        return
    end
    local f = super_facts(machine, self.learn_slot)
    local packed = f.max_array_index
    local step_tag = packed % 4294967296
    local accumulator_tag = math.floor(packed / 4294967296)
    local sign = f.max_field_count
    if sign ~= 0 and sign ~= 1 then
        error("cps v2: unsupported super-for learned sign " .. tostring(sign), 0)
    end
    local name = "super_for_addi_" .. tag_char(f.key_tag)
        .. tag_char(f.value_tag) .. tag_char(step_tag)
        .. "_" .. tag_char(accumulator_tag) .. (sign == 0 and "_pos" or "_neg")
    machine:emit(assert(machine.bank.residual[name],
        "cps v2: missing exact super-for residual " .. name), product)
end

function ForAddCycleOccurrence:append_v2(machine)
    local product = {
        base_index = self.A, target_index = self.accumulator,
        ["link:skip_link"] = self.skip_pc,
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot, "cps v2: super-for-add slot unassigned")
        machine:emit(assert(machine.bank.learning.super_for_add,
            "cps v2: missing super-for-add learner"), product)
        return
    end
    local f = super_facts(machine, self.learn_slot)
    local packed = f.max_array_index
    local step_tag = packed % 4294967296
    local accumulator_tag = math.floor(packed / 4294967296)
    local sign = f.max_field_count
    if sign ~= 0 and sign ~= 1 then
        error("cps v2: unsupported super-for-add learned sign " .. tostring(sign), 0)
    end
    local name = "super_for_add_" .. tag_char(f.key_tag)
        .. tag_char(f.value_tag) .. tag_char(step_tag)
        .. "_" .. tag_char(accumulator_tag) .. (sign == 0 and "_pos" or "_neg")
    machine:emit(assert(machine.bank.residual[name],
        "cps v2: missing exact super-for-add residual " .. name), product)
end

return {
    ForLoopOccurrence = ForLoopOccurrence,
    NumericForBoundary = NumericForBoundary,
    ForAddICycleOccurrence = ForAddICycleOccurrence,
    ForAddCycleOccurrence = ForAddCycleOccurrence,
    ForSettableCycleOccurrence = ForSettableCycleOccurrence,
    ffi = ffi,
}
