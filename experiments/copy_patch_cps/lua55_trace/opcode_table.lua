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
    patch_many(arena, offset, record.holes[role .. "_base"], base, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_tag"], base, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_payload"], base + 8, patch_i32)
end

local function patch_resume(arena, offset, record, pc)
    patch_many(arena, offset, record.holes.resume, pc, patch_i32)
end

local function append_learner(arena, record, occurrence)
    local offset = arena:append(record)
    if occurrence.target then patch_value_index(arena, offset, record, "target", occurrence.target) end
    if occurrence.source then patch_value_index(arena, offset, record, "source", occurrence.source) end
    patch_value_index(arena, offset, record, "receiver", occurrence.receiver)
    if occurrence.integer_key then
        patch_many(arena, offset, record.holes.integer_key, occurrence.integer_key, patch_i32)
    end
    if occurrence.key_owner then
        patch_many(arena, offset, record.holes.key_reference,
            occurrence.key_owner:reference(), patch_u64)
    end
    patch_resume(arena, offset, record, occurrence.pc)
end

local function append_residual(arena, record, occurrence, table_slot)
    local offset = arena:append(record)
    if occurrence.target then patch_value_index(arena, offset, record, "target", occurrence.target) end
    if occurrence.source then patch_value_index(arena, offset, record, "source", occurrence.source) end
    patch_value_index(arena, offset, record, "receiver", occurrence.receiver)
    patch_many(arena, offset, record.holes.table_reference,
        table_slot.expected_reference, patch_u64)
    patch_many(arena, offset, record.holes.slot_reference, table_slot.slot_reference, patch_u64)
    patch_many(arena, offset, record.holes.storage_generation,
        tonumber(table_slot.expected_storage_generation), patch_i32)
    patch_many(arena, offset, record.holes.collection_epoch,
        tonumber(table_slot.expected_collection_epoch), patch_i32)
    patch_resume(arena, offset, record, occurrence.pc)
end

local function class()
    local result = {}
    result.__index = result
    return result
end

local GetIOccurrence = class()
function GetIOccurrence.new(pc, target, receiver, integer_key)
    assert(integer_key >= 1 and integer_key <= 255, "GETI key is outside bytecode range")
    return setmetatable({
        pc = pc, target = target, receiver = receiver, integer_key = integer_key, table_frame = true,
    }, GetIOccurrence)
end
function GetIOccurrence:append_learner(bank, arena)
    append_learner(arena, bank.learners.geti, self)
end
function GetIOccurrence:append_residual(bank, slot, arena, table_slot)
    local quote = tonumber(slot.quote)
    assert(quote >= Native.quote_id(13, 1) and quote <= Native.quote_id(13, 9),
        "GETI quotation is outside the closed value subset")
    append_residual(arena, assert(bank.quotes[quote]), self, table_slot)
end

local GetFieldOccurrence = class()
function GetFieldOccurrence.new(pc, target, receiver, key_owner)
    return setmetatable({
        pc = pc, target = target, receiver = receiver, key_owner = key_owner,
        table_frame = true, learner_name = "getfield",
    }, GetFieldOccurrence)
end
function GetFieldOccurrence:append_learner(bank, arena)
    append_learner(arena, bank.learners.getfield, self)
end
function GetFieldOccurrence:append_residual(bank, slot, arena, table_slot)
    local quote = tonumber(slot.quote)
    assert(quote >= Native.quote_id(14, 1) and quote <= Native.quote_id(14, 10),
        "GETFIELD quotation is outside the closed value subset")
    append_residual(arena, assert(bank.quotes[quote]), self, table_slot)
end

local FieldAddISuperOccurrence = {}
FieldAddISuperOccurrence.__index = FieldAddISuperOccurrence
function FieldAddISuperOccurrence.new(getfield, addi, setfield)
    return setmetatable({
        pc = getfield.pc, target = getfield.target, receiver = getfield.receiver,
        key_owner = getfield.key_owner, imm = addi.imm,
        fallthrough_pc = setfield.pc + 1, learner_name = "super_field_addi",
    }, FieldAddISuperOccurrence)
end

function GetFieldOccurrence:project_superinstruction(middle, last)
    local project = middle and middle.project_getfield_addi_super
    if not project then return nil end
    return project(middle, self, last)
end

function GetFieldOccurrence:project_accumulate_super(g2, gt, add, src, st)
    local project = add and add.project_accumulate_field
    if not project then return nil end
    return project(add, self, g2, gt, src, st)
end
local SetIOccurrence = class()
function SetIOccurrence.new(pc, receiver, integer_key, source)
    assert(integer_key >= 1 and integer_key <= 255, "SETI key is outside bytecode range")
    return setmetatable({
        pc = pc, receiver = receiver, integer_key = integer_key, source = source, table_frame = true,
    }, SetIOccurrence)
end
function SetIOccurrence:append_learner(bank, arena)
    append_learner(arena, bank.learners.seti, self)
end
function SetIOccurrence:append_residual(bank, slot, arena, table_slot)
    local quote = tonumber(slot.quote)
    assert(quote >= Native.quote_id(17, 1) and quote <= Native.quote_id(17, 9),
        "SETI quotation is outside the closed value subset")
    append_residual(arena, assert(bank.quotes[quote]), self, table_slot)
end

local SetFieldOccurrence = class()
function SetFieldOccurrence.new(pc, receiver, key_owner, source)
    return setmetatable({
        pc = pc, receiver = receiver, key_owner = key_owner, source = source,
        table_frame = true, learner_name = "setfield",
    }, SetFieldOccurrence)
end
function SetFieldOccurrence:append_learner(bank, arena)
    append_learner(arena, bank.learners.setfield, self)
end
function SetFieldOccurrence:append_residual(bank, slot, arena, table_slot)
    local quote = tonumber(slot.quote)
    assert(quote >= Native.quote_id(18, 1) and quote <= Native.quote_id(18, 9),
        "SETFIELD quotation is outside the closed value subset")
    append_residual(arena, assert(bank.quotes[quote]), self, table_slot)
end

function SetFieldOccurrence:project_field_addi_super(getfield, addi)
    if self.pc ~= addi.fallthrough_pc or self.receiver ~= getfield.receiver
        or self.source ~= addi.target
        or self.key_owner:reference() ~= getfield.key_owner:reference() then
        return nil
    end
    return FieldAddISuperOccurrence.new(getfield, addi, self)
end

-- ---- Native CPS Frame V2 leaves ---------------------------------------
-- Exact selection: SETI/SETFIELD keys are projection-proven immediates or
-- string constants, so the key domain needs no learning. Const values select
-- exact value leaves; register values copy any cell. In the learning pass the
-- same occurrences emit learner records that additionally track NEWTABLE
-- site capacity. Hot in-bounds leaves tail-transfer to cold grow leaves.

local VALUE_KIND = {
    [0] = "nil", [1] = "false", [2] = "true", [3] = "int", [4] = "flt",
    [5] = "str", [6] = "str",
}

local function const_product(self)
    local product = {}
    if self.const_value then
        local kind = VALUE_KIND[self.const_value.tag]
        if kind == "int" then
            product["u64::const_int"] = self.const_value.int_bits
        elseif kind == "flt" then
            product["u64::const_flt"] = self.const_value.flt_bits
        elseif kind == "str" then
            product.const_tag = self.const_value.tag
            product["u64::const_ref"] = self.const_value.ref
        end
    end
    return product
end

local function field_location_fact(machine, occurrence)
    local slot = assert(occurrence.learn_slot,
        "cps v2: constant-field location slot unassigned")
    local fact = machine.facts[slot]
    if not fact or fact.field_state == 0 then
        error("cps v2: constant-field location was never observed", 0)
    end
    if fact.field_state == 3 then
        error("cps v2: constant-field location observations conflict", 0)
    end
    local capacity = fact.field_layout_capacity
    local site = fact.field_site_id
    local site_fact = site and site > 0 and machine.facts[site] or nil
    local high_water = site_fact and site_fact.max_field_count or 0
    if high_water > 1 then
        local projected = 1
        while projected < high_water do projected = projected * 2 end
        capacity = math.max(capacity, projected)
    end
    return fact, capacity
end

local function emit_table_set_leaf(machine, family, self, extra, emit_data_exit)
    local kind = self.const_value
        and ("const_" .. VALUE_KIND[self.const_value.tag]) or "reg"
    local suffix = family == "seti" and "_inbounds" or "_existing"
    local cold_suffix = family == "seti" and "_grow" or "_create"
    local base = family .. "_" .. kind
    local hot = assert(machine.bank.residual[base .. suffix],
        "cps v2: missing residual " .. base .. suffix)
    local cold_name = base .. cold_suffix
    assert(machine.bank.residual[cold_name], "cps v2: missing residual " .. cold_name)
    local product = extra or {}
    if self.const_value then product.source_disp = nil end
    for key, value in pairs(const_product(self)) do product[key] = value end
    emit_data_exit(machine, hot, cold_name, product)
end

function GetIOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[13], {
        target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
        receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
        int_key = tonumber(self.integer_key),
    })
end
function GetFieldOccurrence:append_v2(machine)
    local product = {
        target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
        receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
        ["u64::key_ref"] = self.key_owner:reference(),
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot,
            "cps v2: GETFIELD location slot unassigned")
        machine:emit(machine.bank.v2[14], product)
        return
    end
    local fact, layout_capacity = field_location_fact(machine, self)
    product.field_layout_capacity = layout_capacity
    if fact.field_state == 1 then
        product.field_slot = fact.field_slot
        machine:emit(machine.bank.residual.getfield_slot, product)
    else
        machine:emit(machine.bank.residual.getfield_missing, product)
    end
end
function SetIOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        if self.const_value then
            machine:emit(machine.bank.learning.seti_const, {
                receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
                int_key = tonumber(self.integer_key),
                const = self.const_value,
            })
        else
            machine:emit(machine.bank.learning.seti, {
                receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
                source_disp = self.source * ffi.sizeof("Lua55ValueV2"),
                int_key = tonumber(self.integer_key),
            })
        end
        return
    end
    local product = {
        receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
        int_key = tonumber(self.integer_key),
    }
    if not self.const_value then
        product.source_disp = self.source * ffi.sizeof("Lua55ValueV2")
    end
    emit_table_set_leaf(machine, "seti", self, product, machine.emit_need_grow)
end
function SetFieldOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        if self.const_value then
            machine:emit(machine.bank.learning.setfield_const, {
                receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
                ["u64::key_ref"] = self.key_owner:reference(),
                occ_slot = assert(self.learn_slot,
                    "cps v2: SETFIELD location slot unassigned"),
                const = self.const_value,
            })
        else
            machine:emit(machine.bank.learning.setfield, {
                receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
                source_disp = self.source * ffi.sizeof("Lua55ValueV2"),
                ["u64::key_ref"] = self.key_owner:reference(),
                occ_slot = assert(self.learn_slot,
                    "cps v2: SETFIELD location slot unassigned"),
            })
        end
        return
    end
    local fact, layout_capacity = field_location_fact(machine, self)
    assert(fact.field_state == 1,
        "cps v2: SETFIELD learner did not produce a found field slot")
    emit_table_set_leaf(machine, "setfield", self, {
        receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
        ["u64::key_ref"] = self.key_owner:reference(),
        source_disp = self.source * ffi.sizeof("Lua55ValueV2"),
        field_slot = fact.field_slot,
        field_layout_capacity = layout_capacity,
    }, machine.emit_need_create)
end

local function super_value_facts(machine, slot, family)
    local f = machine.facts[assert(slot, "cps v2: " .. family .. " slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: " .. family .. " was never observed; refusing generic publication", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: " .. family .. " observed conflicting shapes; refusing generic publication", 0)
    end
    return f
end

function FieldAddISuperOccurrence:append_v2(machine)
    local product = {
        target_index = self.target, receiver_index = self.receiver,
        ["u64::key_ref"] = self.key_owner:reference(),
        ["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm)),
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot, "cps v2: field-rmw slot unassigned")
        machine:emit(machine.bank.learning.super_field_addi, product)
        return
    end
    local f = super_value_facts(machine, self.learn_slot, "field-rmw")
    local kind = f.key_tag == 3 and "int" or (f.key_tag == 4 and "flt" or nil)
    assert(kind, "cps v2: unsupported field-rmw value tag " .. tostring(f.key_tag))
    machine:emit(assert(machine.bank.residual["super_field_addi_" .. kind]), product)
end

return {
    GetIOccurrence = GetIOccurrence, GetFieldOccurrence = GetFieldOccurrence,
    SetIOccurrence = SetIOccurrence, SetFieldOccurrence = SetFieldOccurrence,
    FieldAddISuperOccurrence = FieldAddISuperOccurrence,
}
