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

-- Per-op classes own their exact selection (no quote_base/learner_name
-- dispatch in the V2 leaf path). The factory methods keep the projection's
-- call shape; each concrete class installs its own append_v2.
local GettableOccurrence = class()
local SettableOccurrence = class()
local GettabupOccurrence = class()
local SettabupOccurrence = class()
local SelfOccurrence = class()
local NewtableOccurrence = class()
for _, k in ipairs({ GettableOccurrence, SettableOccurrence, GettabupOccurrence,
                     SettabupOccurrence, SelfOccurrence, NewtableOccurrence }) do
    k.__index = k
    setmetatable(k, { __index = GenericTableOccurrence })
end

-- GETTABLE (12): R[A] = R[B][R[C]] — target, receiver, runtime key.
function GenericTableOccurrence.gettable(pc, target, receiver, key)
    local o = base_occurrence(GettableOccurrence, pc, 12)
    o.target, o.receiver, o.key = target, receiver, key
    o.learner_name = "gettable"
    return o
end

-- SETTABLE (16): R[A][R[B]] = R[C] — receiver, runtime key, source.
function GenericTableOccurrence.settable(pc, receiver, key, source)
    local o = base_occurrence(SettableOccurrence, pc, 16)
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
    local o = base_occurrence(GettabupOccurrence, pc, 15)
    o.target, o.upvalue, o.const = target, upvalue, const_facts(constant)
    o.learner_name = "gettabup"
    return o
end

-- SETTABUP (11): UpValue[A][K[B]] = R[C] — upvalue, constant key, source.
function GenericTableOccurrence.settabup(pc, upvalue, constant, source)
    local o = base_occurrence(SettabupOccurrence, pc, 11)
    o.upvalue, o.const, o.source = upvalue, const_facts(constant), source
    o.learner_name = "settabup"
    return o
end

-- SELF (20): R[A+1] = R[B]; R[A] = R[B][K[C]].
function GenericTableOccurrence.self(pc, target, receiver, constant)
    local o = base_occurrence(SelfOccurrence, pc, 20)
    o.target, o.object, o.receiver = target, target + 1, receiver
    o.const = const_facts(constant)
    o.learner_name = "self"
    return o
end

-- NEWTABLE (19): R[A] = fresh table (array_cap, field_cap).
function GenericTableOccurrence.newtable(pc, target, array_cap, field_cap)
    local o = base_occurrence(NewtableOccurrence, pc, 19)
    o.target, o.array_cap, o.field_cap = target, array_cap, field_cap
    o.learner_name = "newtable"
    return o
end

local TableAddISuperOccurrence = {}
TableAddISuperOccurrence.__index = TableAddISuperOccurrence
function TableAddISuperOccurrence.new(gettable, addi, settable)
    return setmetatable({
        pc = gettable.pc, target = gettable.target, receiver = gettable.receiver,
        key = gettable.key, imm = addi.imm, fallthrough_pc = settable.pc + 1,
        learner_name = "super_table_addi",
    }, TableAddISuperOccurrence)
end

function GettableOccurrence:project_superinstruction(middle, last)
    local project = middle and middle.project_gettable_addi_super
    if not project then return nil end
    return project(middle, self, last)
end

function SettableOccurrence:project_table_addi_super(gettable, addi)
    if self.pc ~= addi.fallthrough_pc or self.receiver ~= gettable.receiver
        or self.key ~= gettable.key
        or self.const_value ~= nil or self.source ~= addi.target then return nil end
    return TableAddISuperOccurrence.new(gettable, addi, self)
end

function SettableOccurrence:project_numeric_for_cycle(boundary, terminal)
    return terminal:project_settable_cycle(boundary, self)
end

local GlobalConstCallSuperOccurrence = {}
GlobalConstCallSuperOccurrence.__index = GlobalConstCallSuperOccurrence
local GlobalMoveCallSuperOccurrence = {}
GlobalMoveCallSuperOccurrence.__index = GlobalMoveCallSuperOccurrence
local MethodCallSuperOccurrence = {}
MethodCallSuperOccurrence.__index = MethodCallSuperOccurrence

local function valid_global_call(gettabup, argument, call)
    return call and not call.tail and call.B == 2 and call.pc
        and gettabup.target == call.A and gettabup.pc + 1 == argument.pc
        and argument.target == call.A + 1 and argument.pc + 1 == call.pc
end

function GettabupOccurrence:project_call_super(argument, call)
    local project = argument and argument.project_gettabup_call
    if not project then return nil end
    return project(argument, self, call)
end

function GettabupOccurrence:project_constant_call(argument, call)
    if not valid_global_call(self, argument, call) then return nil end
    return setmetatable({ gettabup = self, argument = argument, call = call,
        pc = self.pc, learner_name = "super_global_const_call" },
        GlobalConstCallSuperOccurrence)
end

function GettabupOccurrence:project_move_call(argument, call)
    if not valid_global_call(self, argument, call) then return nil end
    return setmetatable({ gettabup = self, argument = argument, call = call,
        pc = self.pc, learner_name = "super_global_move_call" },
        GlobalMoveCallSuperOccurrence)
end

function SelfOccurrence:project_call_super(_argument, call)
    if not call or call.tail or call.B ~= 2 or not call.pc
        or self.target ~= call.A or self.object ~= call.A + 1
        or self.pc + 1 ~= call.pc then return nil end
    return setmetatable({ self_occurrence = self, call = call, pc = self.pc,
        learner_name = "super_method_call" }, MethodCallSuperOccurrence)
end

-- ---- Native CPS Frame V2 leaves ---------------------------------------
-- GETTABLE/SETTABLE key domains are learned in a separate first invocation
-- (family-specific learners write per-occurrence shape products). The
-- residual pass selects exact leaves from those products. NEWTABLE learners
-- record their site slot; write learners track the site's high-water array
-- index so the residual NEWTABLE preallocates the guarded capacity floor.

local VALUE_KIND = {
    [0] = "nil", [1] = "false", [2] = "true", [3] = "int", [4] = "flt",
    [5] = "str", [6] = "str",
}

local function key_kind_from_facts(machine, slot)
    local facts = machine.facts
    local f = facts and facts[slot]
    local key_tag = f and f.key_tag or 0
    if key_tag == 3 then return "int" end
    if key_tag == 5 or key_tag == 6 then return "str" end
    if key_tag == 0 then
        error("cps v2: table occurrence slot " .. tostring(slot)
            .. " was never observed in the learning pass (cold path);"
            .. " refusing to publish a generic fallback", 0)
    end
    if key_tag == 0xFFFFFFFF then
        error("cps v2: table occurrence slot " .. tostring(slot)
            .. " observed conflicting key domains;"
            .. " refusing to publish a generic fallback", 0)
    end
    error("cps v2: table occurrence slot " .. tostring(slot)
        .. " observed unsupported key tag " .. tostring(key_tag), 0)
end

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

local function next_pow2_ge(n)
    if n <= 1 then return 0 end
    local p = 1
    while p < n do p = p * 2 end
    return p
end

local function learned_key_kind(machine, slot)
    local facts = machine.facts
    local f = facts and facts[slot]
    local key_tag = f and f.key_tag or 0
    if key_tag == 3 then return "int" end
    if key_tag == 5 or key_tag == 6 then return "str" end
    if key_tag == 0 then
        error("cps v2: table occurrence slot " .. tostring(slot)
            .. " was never observed in the learning pass (cold path);"
            .. " refusing to publish a generic fallback", 0)
    end
    if key_tag == 0xFFFFFFFF then
        error("cps v2: table occurrence slot " .. tostring(slot)
            .. " observed conflicting key domains;"
            .. " refusing to publish a generic fallback", 0)
    end
    error("cps v2: table occurrence slot " .. tostring(slot)
        .. " observed unsupported key tag " .. tostring(key_tag), 0)
end

local function next_pow2_ge(n)
    if n <= 1 then return 0 end
    local p = 1
    while p < n do p = p * 2 end
    return p
end

function GettableOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        machine:emit(machine.bank.learning.gettable, {
            target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
            receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
            key_disp = self.key * ffi.sizeof("Lua55ValueV2"),
            occ_slot = assert(self.learn_slot, "cps v2: gettable slot unassigned"),
        })
        return
    end
    local kind = learned_key_kind(machine, self.learn_slot)
    machine:emit(machine.bank.residual["gettable_" .. kind], {
        target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
        receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
        key_disp = self.key * ffi.sizeof("Lua55ValueV2"),
    })
end

function SettableOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        local record = self.const_value
            and machine.bank.learning.settable_const
            or machine.bank.learning.settable
        local product = {
            receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
            key_disp = self.key * ffi.sizeof("Lua55ValueV2"),
            occ_slot = assert(self.learn_slot, "cps v2: settable slot unassigned"),
        }
        if self.const_value then
            product.const_tag = self.const_value.tag
            product["u64::const_int"] = self.const_value.int_bits
            product["u64::const_flt"] = self.const_value.flt_bits
            product["u64::const_ref"] = self.const_value.ref
        else
            product.source_disp = self.source * ffi.sizeof("Lua55ValueV2")
        end
        machine:emit(record, product)
        return
    end
    local kind = learned_key_kind(machine, self.learn_slot)
    local vkind = self.const_value
        and ("const_" .. (self.const_value.tag == 3 and "int"
            or self.const_value.tag == 4 and "flt"
            or self.const_value.tag == 5 or self.const_value.tag == 6 and "str"
            or "nil")) or "reg"
    local base = "settable_" .. kind .. "_" .. vkind
    local hot_suffix = kind == "int" and "_inbounds" or "_existing"
    local cold_suffix = kind == "int" and "_grow" or "_create"
    local hot = assert(machine.bank.residual[base .. hot_suffix],
        "cps v2: missing residual " .. base .. hot_suffix)
    local cold_name = base .. cold_suffix
    assert(machine.bank.residual[cold_name], "cps v2: missing residual " .. cold_name)
    local product = {
        receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
        key_disp = self.key * ffi.sizeof("Lua55ValueV2"),
    }
    if self.const_value then
        local t = self.const_value.tag
        if t == 3 then product["u64::const_int"] = self.const_value.int_bits
        elseif t == 4 then product["u64::const_flt"] = self.const_value.flt_bits
        elseif t == 5 or t == 6 then
            product.const_tag = t
            product["u64::const_ref"] = self.const_value.ref
        end
    else
        product.source_disp = self.source * ffi.sizeof("Lua55ValueV2")
    end
    if kind == "int" then
        machine:emit_need_grow(hot, cold_name, product)
    else
        machine:emit_need_create(hot, cold_name, product)
    end
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

function GettabupOccurrence:append_v2(machine)
    local product = {
        target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
        upvalue_index = self.upvalue,
        ["u64::key_ref"] = self.const and self.const.ref_bits or 0,
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot,
            "cps v2: GETTABUP location slot unassigned")
        machine:emit(machine.bank.v2[11], product)
        return
    end
    local fact, layout_capacity = field_location_fact(machine, self)
    product.field_layout_capacity = layout_capacity
    if fact.field_state == 1 then
        product.field_slot = fact.field_slot
        machine:emit(machine.bank.residual.gettabup_slot, product)
    else
        machine:emit(machine.bank.residual.gettabup_missing, product)
    end
end

function SettabupOccurrence:append_v2(machine)
    local VALUE_KIND = { [0] = "nil", [1] = "false", [2] = "true", [3] = "int",
        [4] = "flt", [5] = "str", [6] = "str" }
    local product = {
        upvalue_index = self.upvalue,
        ["u64::key_ref"] = self.const and self.const.ref_bits or 0,
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot,
            "cps v2: SETTABUP location slot unassigned")
        if self.const_value then
            product.const = self.const_value
            machine:emit(machine.bank.learning.settabup_const, product)
        else
            product.source_disp = self.source * ffi.sizeof("Lua55ValueV2")
            machine:emit(machine.bank.learning.settabup, product)
        end
        return
    end
    local fact, layout_capacity = field_location_fact(machine, self)
    assert(fact.field_state == 1,
        "cps v2: SETTABUP learner did not produce a found field slot")
    product.field_slot = fact.field_slot
    product.field_layout_capacity = layout_capacity
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
        machine:emit_need_create(
            machine.bank.residual["settabup_const_" .. kind .. "_existing"],
            "settabup_const_" .. kind .. "_create", product)
    else
        product.source_disp = self.source * ffi.sizeof("Lua55ValueV2")
        machine:emit_need_create(machine.bank.residual.settabup_existing,
            "settabup_create", product)
    end
end

function SelfOccurrence:append_v2(machine)
    local product = {
        target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
        object_disp = self.object * ffi.sizeof("Lua55ValueV2"),
        receiver_disp = self.receiver * ffi.sizeof("Lua55ValueV2"),
        ["u64::key_ref"] = self.const and self.const.ref_bits or 0,
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot,
            "cps v2: SELF location slot unassigned")
        machine:emit(machine.bank.v2[20], product)
        return
    end
    local fact, layout_capacity = field_location_fact(machine, self)
    product.field_layout_capacity = layout_capacity
    if fact.field_state == 1 then
        product.field_slot = fact.field_slot
        machine:emit(machine.bank.residual.self_slot, product)
    else
        machine:emit(machine.bank.residual.self_missing, product)
    end
end

function NewtableOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        machine:emit(machine.bank.learning.newtable, {
            target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
            array_cap = self.array_cap or 0,
            field_cap = self.field_cap or 0,
            site_id = assert(self.learn_slot, "cps v2: newtable site unassigned"),
        })
        return
    end
    local facts = machine.facts
    local f = facts and facts[self.learn_slot]
    local learned_array = f and f.max_array_index or 0
    local learned_field = f and f.max_field_count or 0
    machine:emit(machine.bank.residual.newtable, {
        target_disp = self.target * ffi.sizeof("Lua55ValueV2"),
        array_cap = math.max(self.array_cap or 0, next_pow2_ge(learned_array)),
        field_cap = math.max(self.field_cap or 0, next_pow2_ge(learned_field)),
    })
end

function TableAddISuperOccurrence:append_v2(machine)
    local product = {
        target_index = self.target, receiver_index = self.receiver, key_index = self.key,
        ["u64::int_imm"] = ffi.cast("uint64_t", ffi.new("int64_t", self.imm)),
    }
    if machine.mode == "learning" then
        product.occ_slot = assert(self.learn_slot, "cps v2: table-rmw slot unassigned")
        machine:emit(machine.bank.learning.super_table_addi, product)
        return
    end
    local f = machine.facts[assert(self.learn_slot, "cps v2: table-rmw slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: table-rmw was never observed; refusing generic publication", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: table-rmw observed conflicting shapes; refusing generic publication", 0)
    end
    local key_kind = f.key_tag == 3 and "int"
        or ((f.key_tag == 5 or f.key_tag == 6) and "str" or nil)
    local value_kind = f.value_tag == 3 and "int" or (f.value_tag == 4 and "flt" or nil)
    assert(key_kind and value_kind, "cps v2: unsupported table-rmw learned product")
    machine:emit(assert(machine.bank.residual[
        "super_table_addi_" .. key_kind .. "_" .. value_kind]), product)
end

local function learned_call_family(machine, slot, family)
    local f = machine.facts[assert(slot, "cps v2: " .. family .. " slot unassigned")]
    if not f or f.seen == 0 then
        error("cps v2: " .. family .. " was never observed; refusing generic publication", 0)
    end
    if f.key_tag == 0xFFFFFFFF then
        error("cps v2: " .. family .. " observed conflicting callee shapes", 0)
    end
    if f.key_tag == 1 then return f.value_tag == 0 and "native_fixed" or "native_vararg" end
    if f.key_tag == 2 then return "host" end
    error("cps v2: " .. family .. " observed unsupported callee class "
        .. tostring(f.key_tag), 0)
end

local function learn_super_call(machine, occurrence, prelude)
    if occurrence.gettabup then occurrence.gettabup.learn_slot = occurrence.learn_slot end
    if occurrence.self_occurrence then
        occurrence.self_occurrence.learn_slot = occurrence.learn_slot
    end
    prelude(occurrence, machine)
    occurrence.call.learn_slot = occurrence.learn_slot
    machine:emit_call(occurrence.call, occurrence.call.pc)
end

function GlobalConstCallSuperOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        return learn_super_call(machine, self, function(subject, cc)
            subject.gettabup:append_v2(cc); subject.argument:append_v2(cc)
        end)
    end
    local family = learned_call_family(machine, self.learn_slot, "global-const-call")
    local kind = self.argument.constant:global_call_kind()
    machine:emit_fused_call(assert(machine.bank.residual[
        "super_global_" .. kind .. "_" .. family]), self.call, self.call.pc, {
        call_a = self.call.A, call_b = self.call.B, call_c = self.call.C,
        call_pc = self.call.pc, upvalue_index = self.gettabup.upvalue,
        ["u64::key_ref"] = self.gettabup.const.ref_bits,
        const = self.argument.constant, host_exit = true,
    })
end

function GlobalMoveCallSuperOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        return learn_super_call(machine, self, function(subject, cc)
            subject.gettabup:append_v2(cc); subject.argument:append_v2(cc)
        end)
    end
    local family = learned_call_family(machine, self.learn_slot, "global-move-call")
    machine:emit_fused_call(assert(machine.bank.residual[
        "super_global_move_" .. family]), self.call, self.call.pc, {
        call_a = self.call.A, call_b = self.call.B, call_c = self.call.C,
        call_pc = self.call.pc, upvalue_index = self.gettabup.upvalue,
        source_index = self.argument.source,
        ["u64::key_ref"] = self.gettabup.const.ref_bits, host_exit = true,
    })
end

function MethodCallSuperOccurrence:append_v2(machine)
    if machine.mode == "learning" then
        return learn_super_call(machine, self, function(subject, cc)
            subject.self_occurrence:append_v2(cc)
        end)
    end
    local family = learned_call_family(machine, self.learn_slot, "method-call")
    machine:emit_fused_call(assert(machine.bank.residual[
        "super_method_" .. family]), self.call, self.call.pc, {
        call_a = self.call.A, call_b = self.call.B, call_c = self.call.C,
        call_pc = self.call.pc, receiver_index = self.self_occurrence.receiver,
        ["u64::key_ref"] = self.self_occurrence.const.ref_bits, host_exit = true,
    })
end

return {
    GenericTableOccurrence = GenericTableOccurrence,
    GettableOccurrence = GettableOccurrence,
    SettableOccurrence = SettableOccurrence,
    GettabupOccurrence = GettabupOccurrence,
    SettabupOccurrence = SettabupOccurrence,
    SelfOccurrence = SelfOccurrence,
    NewtableOccurrence = NewtableOccurrence,
    TableAddISuperOccurrence = TableAddISuperOccurrence,
    GlobalConstCallSuperOccurrence = GlobalConstCallSuperOccurrence,
    GlobalMoveCallSuperOccurrence = GlobalMoveCallSuperOccurrence,
    MethodCallSuperOccurrence = MethodCallSuperOccurrence,
    ffi = ffi,
}
