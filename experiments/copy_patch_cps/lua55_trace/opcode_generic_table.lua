local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local ffi = Native.ffi

local function patch_i32(memory, offset, value)
    assert(value >= -0x80000000 and value <= 0x7fffffff,
        ("patch_i32 out of range: %s at %d"):format(tostring(value), offset))
    ffi.cast("int32_t *", memory + offset)[0] = value
end

local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
end

local function patch_many(arena, offset, holes, value, patch)
    if holes == nil then return end
    for index = 1, #holes do
        local ok, err = pcall(patch, arena.memory, offset + holes[index], value)
        assert(ok, ("patch failed at hole %d (value %s): %s"):format(
            holes[index], tostring(value), err))
    end
end

local function patch_value_index(arena, offset, record, role, index)
    local base = index * ffi.sizeof("Lua55ValueV1")
    patch_many(arena, offset, record.holes[role .. "_tag"], base, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_payload"], base + 8, patch_i32)
    patch_many(arena, offset, record.holes[role .. "_reserved"], base + 4, patch_i32)
end

-- The generic table operations record their runtime key in the slot:
-- slot.key_bits (value), slot.expected_state (the key tag for register
-- keys / the upvalue state for TABUP ops). The table identity facts come
-- from the table recording slot (Lua55TableRecordingV1) at install time.
local function append_occurrence(arena, record, occurrence, with_quote, slot, table_slot)
    local offset = arena:append(record)
    patch_value_index(arena, offset, record, "target", occurrence.target)
    if occurrence.receiver ~= nil then
        patch_value_index(arena, offset, record, "receiver", occurrence.receiver)
    end
    if occurrence.key ~= nil then
        patch_value_index(arena, offset, record, "key", occurrence.key)
    end
    if occurrence.source ~= nil then
        patch_value_index(arena, offset, record, "source", occurrence.source)
    end
    if occurrence.object ~= nil then
        patch_value_index(arena, offset, record, "object", occurrence.object)
    end
    if occurrence.upvalue ~= nil then
        local base = occurrence.upvalue * ffi.sizeof("Lua55UpvalueCellV1")
        patch_many(arena, offset, record.holes.upvalue_open, base, patch_i32)
        patch_many(arena, offset, record.holes.upvalue_closed, base + 8, patch_i32)
        patch_many(arena, offset, record.holes.upvalue_cell_state, base + 24, patch_i32)
        patch_many(arena, offset, record.holes.upvalue_cell_gen, base + 28, patch_i32)
    end
    patch_many(arena, offset, record.holes.resume, occurrence.pc, patch_i32)
    if with_quote then
        patch_many(arena, offset, record.holes.quote_base, occurrence.quote_base, patch_i32)
    end
    if occurrence.const ~= nil then
        patch_many(arena, offset, record.holes.const_tag, occurrence.const.tag, patch_i32)
        patch_many(arena, offset, record.holes.const_int, occurrence.const.int_bits, patch_u64)
        patch_many(arena, offset, record.holes.const_ref, occurrence.const.ref_bits, patch_u64)
    end
    if occurrence.array_cap ~= nil then
        patch_many(arena, offset, record.holes.array_cap, occurrence.array_cap, patch_i32)
        patch_many(arena, offset, record.holes.field_cap, occurrence.field_cap, patch_i32)
    end
    if slot ~= nil then
        patch_many(arena, offset, record.holes.int_key, tonumber(slot.key_bits), patch_u64)
        patch_many(arena, offset, record.holes.key_ref, tonumber(slot.key_bits), patch_u64)
    end
    if table_slot ~= nil then
        patch_many(arena, offset, record.holes.table_reference,
            tonumber(table_slot.expected_reference), patch_u64)
        patch_many(arena, offset, record.holes.slot_reference,
            tonumber(table_slot.slot_reference), patch_u64)
        patch_many(arena, offset, record.holes.storage_generation,
            tonumber(table_slot.expected_storage_generation), patch_i32)
        patch_many(arena, offset, record.holes.collection_epoch,
            tonumber(table_slot.expected_collection_epoch), patch_i32)
    end
    if slot ~= nil then
        patch_many(arena, offset, record.holes.upvalue_state,
            tonumber(slot.expected_state), patch_i32)
        patch_many(arena, offset, record.holes.upvalue_gen,
            tonumber(slot.expected_generation), patch_i32)
    end
    return offset
end

local function class()
    local result = {}
    result.__index = result
    return result
end

local GenericTableOccurrence = class()

function GenericTableOccurrence:append_learner(bank, arena)
    append_occurrence(arena, bank.learners[self.learner_name], self, true)
end

function GenericTableOccurrence:append_residual(bank, slot, arena, table_slot)
    local quote = tonumber(slot.quote)
    local record = assert(bank.quotes[quote], "generic-table quotation is absent")
    append_occurrence(arena, record, self, false, slot, table_slot)
end

local function base_occurrence(klass, pc, opcode)
    return setmetatable({
        pc = pc, target = 0, receiver = nil, key = nil, source = nil,
        object = nil, upvalue = nil, const = nil, array_cap = nil, field_cap = nil,
        fallthrough_pc = pc + 1, quote_base = opcode * 65536, learner_name = nil,
        table_frame = true,
    }, klass)
end

-- GETTABLE (12): R[A] = R[B][R[C]] — target, receiver, runtime key.
function GenericTableOccurrence.gettable(pc, target, receiver, key)
    local o = base_occurrence(GenericTableOccurrence, pc, 12)
    o.target, o.receiver, o.key = target, receiver, key
    o.learner_name = "gettable"
    return o
end

-- SETTABLE (16): R[A][R[B]] = R[C] — receiver, runtime key, source.
function GenericTableOccurrence.settable(pc, receiver, key, source)
    local o = base_occurrence(GenericTableOccurrence, pc, 16)
    o.receiver, o.key, o.source = receiver, key, source
    o.learner_name = "settable"
    return o
end

local function int64_bits(value)
    return ffi.cast("uint64_t", ffi.new("int64_t", value))
end

local function const_facts(constant)
    if constant.t == "int" then
        return { tag = 3, int_bits = int64_bits(constant.v), ref_bits = 0 }
    end
    -- string constant: the interned reference (resolved by the projection)
    local tag = constant.t == "long" and 6 or 5
    return { tag = tag, int_bits = 0, ref_bits = ffi.cast("uint64_t", constant.reference or 0) }
end

-- GETTABUP (15): R[A] = UpValue[B][K[C]] — target, upvalue, constant key.
function GenericTableOccurrence.gettabup(pc, target, upvalue, constant)
    local o = base_occurrence(GenericTableOccurrence, pc, 15)
    o.target, o.upvalue, o.const = target, upvalue, const_facts(constant)
    o.learner_name = "gettabup"
    return o
end

-- SETTABUP (11): UpValue[A][K[B]] = R[C] — upvalue, constant key, source.
function GenericTableOccurrence.settabup(pc, upvalue, constant, source)
    local o = base_occurrence(GenericTableOccurrence, pc, 11)
    o.upvalue, o.const, o.source = upvalue, const_facts(constant), source
    o.learner_name = "settabup"
    return o
end

-- SELF (20): R[A+1] = R[B]; R[A] = R[B][K[C]].
function GenericTableOccurrence.self(pc, target, receiver, constant)
    local o = base_occurrence(GenericTableOccurrence, pc, 20)
    o.target, o.object, o.receiver = target, target + 1, receiver
    o.const = const_facts(constant)
    o.learner_name = "self"
    return o
end

-- NEWTABLE (19): R[A] = fresh table (array_cap, field_cap).
function GenericTableOccurrence.newtable(pc, target, array_cap, field_cap)
    local o = base_occurrence(GenericTableOccurrence, pc, 19)
    o.target, o.array_cap, o.field_cap = target, array_cap, field_cap
    o.learner_name = "newtable"
    return o
end


-- ---- Native CPS Frame V2 leaves ---------------------------------------
function GenericTableOccurrence:append_v2(machine)
    local opcode = math.floor(self.quote_base / 65536)
    -- the historical V1 quote convention swapped GETTABUP/SETTABUP; the
    -- real bytecode numbers are GETTABUP=11, SETTABUP=15
    if self.learner_name == "gettabup" then opcode = 11
    elseif self.learner_name == "settabup" then opcode = 15 end
    if opcode == 12 then            -- GETTABLE
        machine:emit(machine.bank.v2[12], {
            target_index = self.target,
            receiver_index = self.receiver,
            key_index = self.key,
        })
    elseif opcode == 16 then        -- SETTABLE
        local record = self.const_value and machine.bank.variants.settable_const
            or machine.bank.v2[16]
        local product = {
            receiver_index = self.receiver,
            key_index = self.key,
            source_index = self.source,
        }
        if self.const_value then
            product.source_index = nil
            product.const_tag = self.const_value.tag
            product["u64::const_int"] = self.const_value.int_bits
            product["u64::const_flt"] = self.const_value.flt_bits
            product["u64::const_ref"] = self.const_value.ref
        end
        machine:emit(record, product)
    elseif opcode == 11 then        -- GETTABUP
        machine:emit(machine.bank.v2[11], {
            target_index = self.target,
            upvalue_index = self.upvalue,
            ["u64::key_ref"] = self.const and self.const.ref_bits or 0,
        })
    elseif opcode == 15 then        -- SETTABUP
        machine:emit(machine.bank.v2[15], {
            upvalue_index = self.upvalue,
            source_index = self.source,
            ["u64::key_ref"] = self.const and self.const.ref_bits or 0,
        })
    elseif opcode == 20 then        -- SELF
        machine:emit(machine.bank.v2[20], {
            target_index = self.target,
            object_target = self.object,
            receiver_index = self.receiver,
            ["u64::key_ref"] = self.const and self.const.ref_bits or 0,
        })
    elseif opcode == 19 then        -- NEWTABLE
        machine:emit(machine.bank.v2[19], {
            target_index = self.target,
            array_cap = self.array_cap or 0,
            field_cap = self.field_cap or 0,
        })
    else
        error("cps v2: generic-table opcode " .. opcode .. " has no V2 leaf", 0)
    end
end

return {
    GenericTableOccurrence = GenericTableOccurrence,
    ffi = ffi,
}
