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
        pc = pc, target = target, receiver = receiver, key_owner = key_owner, table_frame = true,
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
        pc = pc, receiver = receiver, key_owner = key_owner, source = source, table_frame = true,
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


-- ---- Native CPS Frame V2 leaves ---------------------------------------
function GetIOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[13], {
        target_index = self.target,
        receiver_index = self.receiver,
        int_key = tonumber(self.integer_key),
    })
end
function GetFieldOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[14], {
        target_index = self.target,
        receiver_index = self.receiver,
        ["u64::key_ref"] = self.key_owner:reference(),
    })
end
function SetIOccurrence:append_v2(machine)
    local record, product
    if self.const_value then
        record = machine.bank.variants.seti_const
        product = {
            receiver_index = self.receiver,
            int_key = tonumber(self.integer_key),
        }
    else
        record = machine.bank.v2[17]
        product = {
            receiver_index = self.receiver,
            source_index = self.source,
            int_key = tonumber(self.integer_key),
        }
    end
    if self.const_value then
        product.const_tag = self.const_value.tag
        product["u64::const_int"] = self.const_value.int_bits
        product["u64::const_flt"] = self.const_value.flt_bits
        product["u64::const_ref"] = self.const_value.ref
    end
    machine:emit(record, product)
end
function SetFieldOccurrence:append_v2(machine)
    local record, product
    if self.const_value then
        record = machine.bank.variants.setfield_const
        product = {
            receiver_index = self.receiver,
            ["u64::key_ref"] = self.key_owner:reference(),
        }
    else
        record = machine.bank.v2[18]
        product = {
            receiver_index = self.receiver,
            source_index = self.source,
            ["u64::key_ref"] = self.key_owner:reference(),
        }
    end
    if self.const_value then
        product.const_tag = self.const_value.tag
        product["u64::const_int"] = self.const_value.int_bits
        product["u64::const_flt"] = self.const_value.flt_bits
        product["u64::const_ref"] = self.const_value.ref
    end
    machine:emit(record, product)
end

return {
    GetIOccurrence = GetIOccurrence, GetFieldOccurrence = GetFieldOccurrence,
    SetIOccurrence = SetIOccurrence, SetFieldOccurrence = SetFieldOccurrence,
}
