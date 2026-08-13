local ffi = require("ffi")

ffi.cdef[[
void *mmap(void *, size_t, int, int, int, long);
int mprotect(void *, size_t, int);
int munmap(void *, size_t);

typedef union Lua55ValuePayloadV1 {
    int64_t integer;
    double floating;
    uintptr_t reference;
} Lua55ValuePayloadV1;

typedef struct Lua55ValueV1 {
    uint32_t tag;
    uint32_t reserved;
    Lua55ValuePayloadV1 payload;
} Lua55ValueV1;

typedef struct Lua55GuestObjectHeaderV1 {
    uint32_t kind;
    uint32_t generation;
} Lua55GuestObjectHeaderV1;

typedef struct Lua55GuestStringV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t length;
    uint32_t hash;
    const uint8_t *bytes;
} Lua55GuestStringV1;

typedef struct Lua55GuestHeapV1 {
    uint32_t generation;
    uint32_t collection_epoch;
    uint32_t object_count;
    uint32_t barrier_epoch;
    /* native table bump region (NEWTABLE) */
    uintptr_t table_region;
    uintptr_t table_region_end;
    uintptr_t table_next;
} Lua55GuestHeapV1;

typedef struct Lua55GuestFieldV1 {
    uintptr_t key_reference;
    Lua55ValueV1 value;
    uint32_t occupied;
    uint32_t reserved;
} Lua55GuestFieldV1;

typedef struct Lua55GuestTableV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t storage_generation;
    uint32_t array_capacity;
    uint32_t field_capacity;
    uint32_t barrier_count;
    uintptr_t metatable_reference;
    Lua55ValueV1 *array_values;
    Lua55GuestFieldV1 *field_values;
    Lua55GuestHeapV1 *heap;
    uint32_t site_id;
    uint32_t learn_reserved;
} Lua55GuestTableV1;


typedef struct Lua55RecordingSlotV1 {
    uint32_t quote;
    uint32_t expected_tag;
    uint32_t expected_state;
    uint32_t expected_generation;
    uint64_t key_bits;
} Lua55RecordingSlotV1;

typedef struct Lua55TableRecordingV1 {
    uint32_t expected_storage_generation;
    uint32_t expected_collection_epoch;
    uintptr_t expected_reference;
    uintptr_t slot_reference;
    uintptr_t expected_metatable;
} Lua55TableRecordingV1;

typedef struct Lua55UpvalueCellV1 {
    Lua55ValueV1 *open_slot;
    Lua55ValueV1 closed_value;
    uint32_t state;
    uint32_t generation;
} Lua55UpvalueCellV1;

typedef struct Lua55GuestBuiltinV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t builtin_id;
} Lua55GuestBuiltinV1;

typedef struct Lua55GuestClosureV1 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t proto_index;
    uint32_t upvalue_count;
    uint32_t maxstacksize;
    uint32_t numparams;
    uint32_t is_vararg;
    Lua55UpvalueCellV1 cells[4];
} Lua55GuestClosureV1;

typedef void (*Lua55OpcodeEntryV1)(struct Lua55LearnFrameV1 *);

typedef struct Lua55LearnFrameV1 {
    Lua55ValueV1 *values;
    Lua55RecordingSlotV1 *slots;
    Lua55UpvalueCellV1 *upvalues;
    Lua55GuestHeapV1 *heap;
    uint32_t value_count;
    uint32_t slot_count;
    uint32_t slot_cursor;
    uint32_t resume_pc;
    uint32_t status;
    uint32_t upvalue_count;
    uint32_t vararg_count;
    struct Lua55LearnFrameV1 *dest_frame;
    uint32_t dest_base;
    int32_t dest_count;
    uint32_t top;
    uint32_t result_count;
    Lua55OpcodeEntryV1 *function_table;
} Lua55LearnFrameV1;

typedef struct Lua55TableLearnFrameV1 {
    Lua55LearnFrameV1 base;
    Lua55TableRecordingV1 *table_slots;
} Lua55TableLearnFrameV1;
]]

local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
local MAP_PRIVATE, MAP_ANONYMOUS = 0x02, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local function patch_i32(memory, offset, value)
    assert(value >= -0x80000000 and value <= 0x7fffffff)
    ffi.cast("int32_t *", memory + offset)[0] = value
end

local function patch_rel32(memory, displacement_offset, target_offset)
    patch_i32(memory, displacement_offset, target_offset - (displacement_offset + 4))
end

local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
end

local function patch_all(memory, base, offsets, value)
    if offsets == nil then return end
    for index = 1, #offsets do patch_i32(memory, base + offsets[index], value) end
end

local function integer_bits(value)
    return ffi.cast("uint64_t", ffi.new("int64_t", value))
end

local function float_bits(value)
    local holder = ffi.new("double[1]", value)
    return ffi.cast("uint64_t *", holder)[0]
end

local NativeCode = {}
NativeCode.__index = NativeCode

function NativeCode:execute(frame)
    assert(self.entry ~= false, "Lua55 opcode code was released")
    self.entry(frame)
end

function NativeCode:permissions()
    assert(self.entry ~= false, "Lua55 opcode code was released")
    local address = tonumber(ffi.cast("uintptr_t", self.memory))
    local file = assert(io.open("/proc/self/maps", "r"))
    for line in file:lines() do
        local first, last, permissions = line:match("^(%x+)%-(%x+)%s+(....)")
        if first then
            local low, high = tonumber(first, 16), tonumber(last, 16)
            if address >= low and address < high then
                file:close()
                return permissions
            end
        end
    end
    file:close()
    error("Lua55 opcode mapping not found")
end

function NativeCode:free()
    if self.entry == false then return end
    local memory = self.memory
    ffi.gc(memory, nil)
    self.entry, self.memory = false, false
    assert(ffi.C.munmap(memory, self.mapping_size) == 0)
end

local Arena = {}
Arena.__index = Arena

function Arena.new(capacity)
    capacity = capacity or 16384
    local mapping_size = math.floor((capacity + 4095) / 4096) * 4096
    local raw = ffi.C.mmap(nil, mapping_size, PROT_READ + PROT_WRITE,
        MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    assert(raw ~= MAP_FAILED, "Lua55 opcode mmap RW failed")
    return setmetatable({
        memory = ffi.cast("uint8_t *", raw), mapping_size = mapping_size,
        capacity = capacity, cursor = 0, sealed = false, pending = {},
    }, Arena)
end

function Arena:append(record)
    assert(not self.sealed, "Lua55 opcode arena is sealed")
    local offset, required = self.cursor, self.cursor + #record.code
    assert(required <= self.capacity, "Lua55 opcode arena capacity exceeded")
    for index = 1, #self.pending do
        patch_rel32(self.memory, self.pending[index], offset)
    end
    ffi.copy(self.memory + offset, record.code, #record.code)
    self.pending = {}
    if record.successors then
        for index = 1, #record.successors do
            self.pending[index] = offset + record.successors[index]
        end
    end
    self.cursor = required
    return offset
end

function Arena:seal()
    assert(not self.sealed, "Lua55 opcode arena is sealed")
    assert(#self.pending == 0, "Lua55 opcode arena has an unbound successor")
    self.sealed = true
    assert(ffi.C.mprotect(self.memory, self.mapping_size, PROT_READ + PROT_EXEC) == 0,
        "Lua55 opcode mprotect RX failed")
    local raw, mapping_size = self.memory, self.mapping_size
    self.memory = false
    local memory = ffi.gc(raw, function(pointer) ffi.C.munmap(pointer, mapping_size) end)
    return setmetatable({
        memory = memory, mapping_size = mapping_size, size = self.cursor,
        entry = ffi.cast("Lua55OpcodeEntryV1", memory),
    }, NativeCode)
end

function Arena:free()
    if self.memory == false then return end
    local memory = self.memory
    self.memory = false
    assert(ffi.C.munmap(memory, self.mapping_size) == 0)
end

local function patch_target(arena, offset, record, target)
    patch_all(arena.memory, offset, record.holes.target_tag, target * 16)
    patch_all(arena.memory, offset, record.holes.target_payload, target * 16 + 8)
end

local function patch_source(arena, offset, record, source)
    patch_all(arena.memory, offset, record.holes.source_tag, source * 16)
    patch_all(arena.memory, offset, record.holes.source_payload, source * 16 + 8)
end

local function patch_resume(arena, offset, record, resume_pc)
    patch_all(arena.memory, offset, record.holes.resume, resume_pc)
end

local function patch_upvalue(arena, offset, record, upvalue)
    local base = upvalue * 32
    patch_all(arena.memory, offset, record.holes.upvalue_open, base)
    patch_all(arena.memory, offset, record.holes.upvalue_closed_tag, base + 8)
    patch_all(arena.memory, offset, record.holes.upvalue_closed_payload, base + 16)
    patch_all(arena.memory, offset, record.holes.upvalue_state, base + 24)
    patch_all(arena.memory, offset, record.holes.upvalue_generation, base + 28)
end

local function patch_generation(arena, offset, record, generation)
    patch_all(arena.memory, offset, record.holes.expected_generation, generation)
end

local function append_tagged(arena, record, target)
    local offset = arena:append(record)
    patch_target(arena, offset, record, target)
    return offset
end

local function append_integer(arena, record, target, value)
    local offset = append_tagged(arena, record, target)
    local holes, bits = record.holes.integer, integer_bits(value)
    for index = 1, #holes do patch_u64(arena.memory, offset + holes[index], bits) end
    return offset
end

local function append_float(arena, record, target, value)
    local offset = append_tagged(arena, record, target)
    local holes = record.holes.floating
    if holes then
        local bits = float_bits(value)
        for index = 1, #holes do patch_u64(arena.memory, offset + holes[index], bits) end
    end
    return offset
end

local function append_reference(arena, record, target, owner)
    local offset = append_tagged(arena, record, target)
    local reference = owner:reference()
    for index = 1, #record.holes.reference do
        patch_u64(arena.memory, offset + record.holes.reference[index], reference)
    end
    return offset
end

local function append_finish(arena, bank, resume_pc)
    local offset = arena:append(bank.finish)
    patch_i32(arena.memory, offset + bank.finish.resume, resume_pc)
end

local function quote_id(opcode, variant) return opcode * 65536 + variant end

local function class()
    local result = {}
    result.__index = result
    return result
end

local MoveOccurrence = class()
function MoveOccurrence.new(pc, target, source)
    return setmetatable({ pc = pc, target = target, source = source }, MoveOccurrence)
end
function MoveOccurrence:append_learner(bank, arena)
    local record = bank.learners.move
    local offset = arena:append(record)
    patch_target(arena, offset, record, self.target)
    patch_source(arena, offset, record, self.source)
    patch_resume(arena, offset, record, self.pc)
end
function MoveOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local expected = quote_id(0, tonumber(slot.expected_tag) + 1)
    local tag = tonumber(slot.expected_tag)
    assert(quote == expected and (tag <= 6 or tag == 7 or tag == 8),
        "MOVE learner tag and quotation disagree")
    local record = assert(bank.quotes[quote], "MOVE quotation is absent")
    local offset = arena:append(record)
    patch_target(arena, offset, record, self.target)
    patch_source(arena, offset, record, self.source)
    patch_resume(arena, offset, record, self.pc)
end

function MoveOccurrence:project_gettabup_call(gettabup, call)
    return gettabup:project_move_call(self, call)
end

local LoadIOccurrence = class()
function LoadIOccurrence.new(pc, target, value)
    return setmetatable({ pc = pc, target = target, value = value }, LoadIOccurrence)
end
function LoadIOccurrence:append_learner(bank, arena)
    append_integer(arena, bank.learners.loadi, self.target, self.value)
end
function LoadIOccurrence:append_residual(bank, slot, arena)
    local quote = quote_id(1, 1)
    assert(tonumber(slot.quote) == quote, "LOADI learner selected the wrong quotation")
    append_integer(arena, bank.quotes[quote], self.target, self.value)
end

local LoadFOccurrence = class()
function LoadFOccurrence.new(pc, target, value)
    return setmetatable({ pc = pc, target = target, value = value }, LoadFOccurrence)
end
function LoadFOccurrence:append_learner(bank, arena)
    append_float(arena, bank.learners.loadf, self.target, self.value)
end
function LoadFOccurrence:append_residual(bank, slot, arena)
    local quote = quote_id(2, 1)
    assert(tonumber(slot.quote) == quote, "LOADF learner selected the wrong quotation")
    append_float(arena, bank.quotes[quote], self.target, self.value)
end

local NilConstant = class()
function NilConstant.new() return setmetatable({}, NilConstant) end
function NilConstant:append_loadk(bank, arena, target)
    append_tagged(arena, bank.learners.loadk_nil, target)
end
function NilConstant:append_loadk_residual(bank, slot, arena, target)
    local quote = quote_id(3, 1)
    assert(tonumber(slot.quote) == quote, "LOADK nil quotation changed")
    append_tagged(arena, bank.quotes[quote], target)
end
function NilConstant:append_loadkx(bank, arena, target)
    append_tagged(arena, bank.learners.loadkx_nil, target)
end
function NilConstant:append_loadkx_residual(bank, slot, arena, target)
    local quote = quote_id(4, 1)
    assert(tonumber(slot.quote) == quote, "LOADKX nil quotation changed")
    append_tagged(arena, bank.quotes[quote], target)
end

local FalseConstant = class()
function FalseConstant.new() return setmetatable({}, FalseConstant) end
function FalseConstant:append_loadk(bank, arena, target)
    append_tagged(arena, bank.learners.loadk_false, target)
end
function FalseConstant:append_loadk_residual(bank, slot, arena, target)
    local quote = quote_id(3, 2)
    assert(tonumber(slot.quote) == quote, "LOADK false quotation changed")
    append_tagged(arena, bank.quotes[quote], target)
end
function FalseConstant:append_loadkx(bank, arena, target)
    append_tagged(arena, bank.learners.loadkx_false, target)
end
function FalseConstant:append_loadkx_residual(bank, slot, arena, target)
    local quote = quote_id(4, 2)
    assert(tonumber(slot.quote) == quote, "LOADKX false quotation changed")
    append_tagged(arena, bank.quotes[quote], target)
end

local TrueConstant = class()
function TrueConstant.new() return setmetatable({}, TrueConstant) end
function TrueConstant:append_loadk(bank, arena, target)
    append_tagged(arena, bank.learners.loadk_true, target)
end
function TrueConstant:append_loadk_residual(bank, slot, arena, target)
    local quote = quote_id(3, 3)
    assert(tonumber(slot.quote) == quote, "LOADK true quotation changed")
    append_tagged(arena, bank.quotes[quote], target)
end
function TrueConstant:append_loadkx(bank, arena, target)
    append_tagged(arena, bank.learners.loadkx_true, target)
end
function TrueConstant:append_loadkx_residual(bank, slot, arena, target)
    local quote = quote_id(4, 3)
    assert(tonumber(slot.quote) == quote, "LOADKX true quotation changed")
    append_tagged(arena, bank.quotes[quote], target)
end

local IntegerConstant = class()
function IntegerConstant.new(value)
    return setmetatable({ value = ffi.new("int64_t", value) }, IntegerConstant)
end
function IntegerConstant:append_loadk(bank, arena, target)
    append_integer(arena, bank.learners.loadk_integer, target, self.value)
end
function IntegerConstant:append_loadk_residual(bank, slot, arena, target)
    local quote = quote_id(3, 4)
    assert(tonumber(slot.quote) == quote, "LOADK integer quotation changed")
    append_integer(arena, bank.quotes[quote], target, self.value)
end
function IntegerConstant:append_loadkx(bank, arena, target)
    append_integer(arena, bank.learners.loadkx_integer, target, self.value)
end
function IntegerConstant:append_loadkx_residual(bank, slot, arena, target)
    local quote = quote_id(4, 4)
    assert(tonumber(slot.quote) == quote, "LOADKX integer quotation changed")
    append_integer(arena, bank.quotes[quote], target, self.value)
end

local FloatConstant = class()
function FloatConstant.new(value) return setmetatable({ value = value }, FloatConstant) end
function FloatConstant:append_loadk(bank, arena, target)
    append_float(arena, bank.learners.loadk_float, target, self.value)
end
function FloatConstant:append_loadk_residual(bank, slot, arena, target)
    local quote = quote_id(3, 5)
    assert(tonumber(slot.quote) == quote, "LOADK float quotation changed")
    append_float(arena, bank.quotes[quote], target, self.value)
end
function FloatConstant:append_loadkx(bank, arena, target)
    append_float(arena, bank.learners.loadkx_float, target, self.value)
end
function FloatConstant:append_loadkx_residual(bank, slot, arena, target)
    local quote = quote_id(4, 5)
    assert(tonumber(slot.quote) == quote, "LOADKX float quotation changed")
    append_float(arena, bank.quotes[quote], target, self.value)
end

local ShortStringConstant = class()
function ShortStringConstant.new(owner)
    return setmetatable({ owner = owner }, ShortStringConstant)
end
function ShortStringConstant:append_loadk(bank, arena, target)
    append_reference(arena, bank.learners.loadk_short_string, target, self.owner)
end
function ShortStringConstant:append_loadk_residual(bank, slot, arena, target)
    local quote = quote_id(3, 6)
    assert(tonumber(slot.quote) == quote, "LOADK short-string quotation changed")
    append_reference(arena, bank.quotes[quote], target, self.owner)
end
function ShortStringConstant:append_loadkx(bank, arena, target)
    append_reference(arena, bank.learners.loadkx_short_string, target, self.owner)
end
function ShortStringConstant:append_loadkx_residual(bank, slot, arena, target)
    local quote = quote_id(4, 6)
    assert(tonumber(slot.quote) == quote, "LOADKX short-string quotation changed")
    append_reference(arena, bank.quotes[quote], target, self.owner)
end

local LongStringConstant = class()
function LongStringConstant.new(owner)
    return setmetatable({ owner = owner }, LongStringConstant)
end
function LongStringConstant:append_loadk(bank, arena, target)
    append_reference(arena, bank.learners.loadk_long_string, target, self.owner)
end
function LongStringConstant:append_loadk_residual(bank, slot, arena, target)
    local quote = quote_id(3, 7)
    assert(tonumber(slot.quote) == quote, "LOADK long-string quotation changed")
    append_reference(arena, bank.quotes[quote], target, self.owner)
end
function LongStringConstant:append_loadkx(bank, arena, target)
    append_reference(arena, bank.learners.loadkx_long_string, target, self.owner)
end
function LongStringConstant:append_loadkx_residual(bank, slot, arena, target)
    local quote = quote_id(4, 7)
    assert(tonumber(slot.quote) == quote, "LOADKX long-string quotation changed")
    append_reference(arena, bank.quotes[quote], target, self.owner)
end

-- Concrete constant leaves own their physical poly-hole projection.
function NilConstant:patch_poly(cc) return cc:nil_value() end
function FalseConstant:patch_poly(cc) return cc:false_value() end
function TrueConstant:patch_poly(cc) return cc:true_value() end
function IntegerConstant:patch_poly(cc) return cc:integer(self.value) end
function FloatConstant:patch_poly(cc) return cc:floating(self.value) end
function ShortStringConstant:patch_poly(cc) return cc:short_string(self.owner) end
function LongStringConstant:patch_poly(cc) return cc:long_string(self.owner) end

function NilConstant:global_call_kind() return "nil" end
function FalseConstant:global_call_kind() return "false" end
function TrueConstant:global_call_kind() return "true" end
function IntegerConstant:global_call_kind() return "int" end
function FloatConstant:global_call_kind() return "flt" end
function ShortStringConstant:global_call_kind() return "str" end
function LongStringConstant:global_call_kind() return "str" end

local LoadKOccurrence = class()
function LoadKOccurrence.new(pc, target, constant)
    return setmetatable({ pc = pc, target = target, constant = constant }, LoadKOccurrence)
end
function LoadKOccurrence:append_learner(bank, arena)
    self.constant:append_loadk(bank, arena, self.target)
end
function LoadKOccurrence:append_residual(bank, slot, arena)
    self.constant:append_loadk_residual(bank, slot, arena, self.target)
end

function LoadKOccurrence:project_gettabup_call(gettabup, call)
    return gettabup:project_constant_call(self, call)
end

local LoadKXOccurrence = class()
function LoadKXOccurrence.new(pc, target, constant)
    return setmetatable({ pc = pc, target = target, constant = constant }, LoadKXOccurrence)
end
function LoadKXOccurrence:append_learner(bank, arena)
    self.constant:append_loadkx(bank, arena, self.target)
end
function LoadKXOccurrence:append_residual(bank, slot, arena)
    self.constant:append_loadkx_residual(bank, slot, arena, self.target)
end

local LoadFalseOccurrence = class()
function LoadFalseOccurrence.new(pc, target)
    return setmetatable({ pc = pc, target = target }, LoadFalseOccurrence)
end
function LoadFalseOccurrence:append_learner(bank, arena)
    append_tagged(arena, bank.learners.loadfalse, self.target)
end
function LoadFalseOccurrence:append_residual(bank, slot, arena)
    local quote = quote_id(5, 1)
    assert(tonumber(slot.quote) == quote, "LOADFALSE quotation changed")
    append_tagged(arena, bank.quotes[quote], self.target)
end

local LoadFalseSkipOccurrence = class()
function LoadFalseSkipOccurrence.new(pc, target)
    return setmetatable({ pc = pc, target = target }, LoadFalseSkipOccurrence)
end
function LoadFalseSkipOccurrence:append_learner(bank, arena)
    append_tagged(arena, bank.learners.lfalseskip, self.target)
end
function LoadFalseSkipOccurrence:append_residual(bank, slot, arena)
    local quote = quote_id(6, 1)
    assert(tonumber(slot.quote) == quote, "LFALSESKIP quotation changed")
    append_tagged(arena, bank.quotes[quote], self.target)
end

local LoadTrueOccurrence = class()
function LoadTrueOccurrence.new(pc, target)
    return setmetatable({ pc = pc, target = target }, LoadTrueOccurrence)
end
function LoadTrueOccurrence:append_learner(bank, arena)
    append_tagged(arena, bank.learners.loadtrue, self.target)
end
function LoadTrueOccurrence:append_residual(bank, slot, arena)
    local quote = quote_id(7, 1)
    assert(tonumber(slot.quote) == quote, "LOADTRUE quotation changed")
    append_tagged(arena, bank.quotes[quote], self.target)
end

local GetUpvalueOccurrence = class()
function GetUpvalueOccurrence.new(pc, target, upvalue)
    return setmetatable({ pc = pc, target = target, upvalue = upvalue }, GetUpvalueOccurrence)
end
function GetUpvalueOccurrence:append_learner(bank, arena)
    local record = assert(bank.learners.getupval, "GETUPVAL learner bank is absent")
    local offset = arena:append(record)
    patch_target(arena, offset, record, self.target)
    patch_upvalue(arena, offset, record, self.upvalue)
    patch_resume(arena, offset, record, self.pc)
end
function GetUpvalueOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local variant = (tonumber(slot.expected_state) - 1) * 5 + tonumber(slot.expected_tag) + 1
    local expected = quote_id(9, variant)
    if quote ~= expected then
        -- the learner selects the closure variants (9, 11) / (9, 12) directly
        assert(tonumber(slot.expected_tag) == 8
            and (quote == quote_id(9, 11) or quote == quote_id(9, 12)),
            "GETUPVAL learner facts disagree")
    end
    local record = assert(bank.quotes[quote], "GETUPVAL quotation is absent")
    local offset = arena:append(record)
    patch_target(arena, offset, record, self.target)
    patch_upvalue(arena, offset, record, self.upvalue)
    patch_generation(arena, offset, record, tonumber(slot.expected_generation))
    patch_resume(arena, offset, record, self.pc)
end

local SetUpvalueOccurrence = class()
function SetUpvalueOccurrence.new(pc, source, upvalue)
    return setmetatable({ pc = pc, source = source, upvalue = upvalue }, SetUpvalueOccurrence)
end
function SetUpvalueOccurrence:append_learner(bank, arena)
    local record = assert(bank.learners.setupval, "SETUPVAL learner bank is absent")
    local offset = arena:append(record)
    patch_source(arena, offset, record, self.source)
    patch_upvalue(arena, offset, record, self.upvalue)
    patch_resume(arena, offset, record, self.pc)
end
function SetUpvalueOccurrence:append_residual(bank, slot, arena)
    local quote = tonumber(slot.quote)
    local variant = (tonumber(slot.expected_state) - 1) * 5 + tonumber(slot.expected_tag) + 1
    local expected = quote_id(10, variant)
    assert(quote == expected and variant >= 1 and variant <= 10,
        "SETUPVAL learner facts disagree")
    local record = assert(bank.quotes[quote], "SETUPVAL quotation is absent")
    local offset = arena:append(record)
    patch_source(arena, offset, record, self.source)
    patch_upvalue(arena, offset, record, self.upvalue)
    patch_generation(arena, offset, record, tonumber(slot.expected_generation))
    patch_resume(arena, offset, record, self.pc)
end

local LoadNilOccurrence = class()
function LoadNilOccurrence.new(pc, target, span)
    assert(span >= 1 and span <= 256 and span == math.floor(span), "LOADNIL span is invalid")
    return setmetatable({ pc = pc, target = target, span = span }, LoadNilOccurrence)
end
function LoadNilOccurrence:append_learner(bank, arena)
    local record = bank.learners.loadnil
    local offset = arena:append(record)
    patch_all(arena.memory, offset, record.holes.target_index, self.target)
    patch_all(arena.memory, offset, record.holes.span, self.span)
end
function LoadNilOccurrence:append_residual(bank, slot, arena)
    local quote = quote_id(8, 1)
    assert(tonumber(slot.quote) == quote, "LOADNIL quotation changed")
    for index = 0, self.span - 1 do
        append_tagged(arena, bank.quotes[quote], self.target + index)
    end
end

local FrameOwner = {}
FrameOwner.__index = FrameOwner

function FrameOwner.new(value_count, slot_count, upvalue_count, heap_owner, table_frame)
    upvalue_count = upvalue_count or 0
    assert(value_count > 0 and slot_count > 0 and upvalue_count >= 0)
    local values = ffi.new("Lua55ValueV1[?]", value_count)
    local slots = ffi.new("Lua55RecordingSlotV1[?]", slot_count)
    local table_slots = table_frame and ffi.new("Lua55TableRecordingV1[?]", slot_count) or false
    local upvalues = ffi.new("Lua55UpvalueCellV1[?]", math.max(upvalue_count, 1))
    local heap = heap_owner and heap_owner.heap or ffi.cast("Lua55GuestHeapV1 *", 0)
    local frame_storage, frame
    if table_frame then
        frame_storage = ffi.new("Lua55TableLearnFrameV1")
        frame_storage.base = ffi.new("Lua55LearnFrameV1", {
            values, slots, upvalues, heap, value_count, slot_count, 0, 0, 0, upvalue_count, 0,
        })
        frame_storage.table_slots = table_slots
        frame = frame_storage.base
    else
        frame = ffi.new("Lua55LearnFrameV1", {
            values, slots, upvalues, heap, value_count, slot_count, 0, 0, 0, upvalue_count, 0,
        })
    end
    return setmetatable({
        values = values, slots = slots, table_slots = table_slots, upvalues = upvalues, frame = frame,
        frame_storage = frame_storage, heap_owner = heap_owner,
    }, FrameOwner)
end

function FrameOwner:set_nil(index)
    self.values[index].tag, self.values[index].reserved = 0, 0
    return self
end
function FrameOwner:set_false(index)
    self.values[index].tag, self.values[index].reserved = 1, 0
    return self
end
function FrameOwner:set_true(index)
    self.values[index].tag, self.values[index].reserved = 2, 0
    return self
end
function FrameOwner:set_integer(index, value)
    self.values[index].tag, self.values[index].reserved = 3, 0
    self.values[index].payload.integer = ffi.new("int64_t", value)
    return self
end
function FrameOwner:set_float(index, value)
    self.values[index].tag, self.values[index].reserved = 4, 0
    self.values[index].payload.floating = value
    return self
end

function FrameOwner:set_short_string(index, owner)
    assert(self.heap_owner == owner.heap_owner, "short string belongs to another guest heap")
    self.values[index].tag, self.values[index].reserved = 5, 0
    self.values[index].payload.reference = owner:reference()
    return self
end

function FrameOwner:set_long_string(index, owner)
    assert(self.heap_owner == owner.heap_owner, "long string belongs to another guest heap")
    self.values[index].tag, self.values[index].reserved = 6, 0
    self.values[index].payload.reference = owner:reference()
    return self
end

function FrameOwner:set_table(index, owner)
    assert(self.heap_owner == owner.heap_owner, "table belongs to another guest heap")
    self.values[index].tag, self.values[index].reserved = 7, 0
    self.values[index].payload.reference = owner:reference()
    return self
end

function FrameOwner:tag(index) return tonumber(self.values[index].tag) end
function FrameOwner:integer(index) return self.values[index].payload.integer end
function FrameOwner:floating(index) return self.values[index].payload.floating end
function FrameOwner:reference(index) return self.values[index].payload.reference end


function FrameOwner:open_upvalue(index, register, generation)
    assert(index >= 0 and index < self.frame.upvalue_count)
    assert(register >= 0 and register < self.frame.value_count)
    local cell = self.upvalues[index]
    cell.open_slot = self.values + register
    cell.state = 1
    cell.generation = generation or 1
    return self
end

function FrameOwner:close_upvalue(index, generation)
    assert(index >= 0 and index < self.frame.upvalue_count)
    local cell = self.upvalues[index]
    assert(cell.state == 1, "upvalue is not open")
    cell.closed_value = cell.open_slot[0]
    cell.open_slot = nil
    cell.state = 2
    cell.generation = generation or (tonumber(cell.generation) + 1)
    return self
end

function FrameOwner:set_varargs(count)
    assert(count >= 0 and count <= self.frame.value_count)
    self.frame.vararg_count = count
    return self
end

function FrameOwner:upvalue_tag(index)
    local cell = self.upvalues[index]
    local value = cell.state == 1 and cell.open_slot or cell.closed_value
    return tonumber(value.tag)
end

function FrameOwner:upvalue_integer(index)
    local cell = self.upvalues[index]
    local value = cell.state == 1 and cell.open_slot or cell.closed_value
    return value.payload.integer
end

function FrameOwner:upvalue_floating(index)
    local cell = self.upvalues[index]
    local value = cell.state == 1 and cell.open_slot or cell.closed_value
    return value.payload.floating
end

local ColdSite, InstalledSite, RejectedSite, ReleasedSite = {}, {}, {}, {}
local Program = {}
Program.__index = Program

local function reset(frame_owner, bank)
    local frame = frame_owner.frame
    frame.slot_cursor = 0
    frame.resume_pc = 0
    frame.status = bank.status.executing
end

local function extend_bank(bank, extension)
    for name, record in pairs(extension.learners) do
        assert(bank.learners[name] == nil, "duplicate Lua55 learner quotation")
        bank.learners[name] = record
    end
    for quote, record in pairs(extension.quotes) do
        assert(bank.quotes[quote] == nil, "duplicate Lua55 residual quotation")
        bank.quotes[quote] = record
    end
    bank.states = extension.states
    if extension.polys then
        bank.polys = bank.polys or {}
        for opcode, record in pairs(extension.polys) do
            assert(bank.polys[opcode] == nil, "duplicate Lua55 poly residual")
            bank.polys[opcode] = record
        end
    end
    if extension.cps then
        bank.cps = bank.cps or {}
        for name, record in pairs(extension.cps) do
            assert(bank.cps[name] == nil, "duplicate Lua55 cps residual")
            bank.cps[name] = record
        end
    end
    return bank
end

local function build_learner(program)
    local arena = Arena.new(program.capacity)
    local ok, message = pcall(function()
        for index = 1, #program.occurrences do
            program.occurrences[index]:append_learner(program.bank, arena)
        end
        append_finish(arena, program.bank, program.exit_pc)
    end)
    if not ok then arena:free(); error(message, 0) end
    return arena:seal()
end

local function install(program, frame_owner)
    local arena = Arena.new(program.capacity)
    local ok, message = pcall(function()
        local recorded = tonumber(frame_owner.frame.slot_cursor)
        for index = 1, recorded do
            local table_slot = program.table_frame and frame_owner.table_slots[index - 1] or nil
            program.occurrences[index]:append_residual(
                program.bank, frame_owner.slots[index - 1], arena, table_slot)
        end
        if recorded < #program.occurrences then
            -- the learner stopped at a taken branch: the not-taken path resumes
            -- at the branching occurrence's fallthrough PC
            append_finish(arena, program.bank,
                program.occurrences[recorded].fallthrough_pc or program.exit_pc)
        else
            append_finish(arena, program.bank, program.exit_pc)
        end
    end)
    if not ok then arena:free(); error(message, 0) end
    program.residual = arena:seal()
end

function ColdSite:execute(program, frame_owner)
    reset(frame_owner, program.bank)
    program.learner:execute(frame_owner.frame)
    local frame = frame_owner.frame
    if frame.status == program.bank.status.rejected then
        program.phase = RejectedSite
        return tonumber(frame.status)
    end
    assert(frame.status == program.bank.status.completed, "learner did not complete")
    assert(frame.slot_cursor <= #program.occurrences, "learner occurrence count changed")
    install(program, frame_owner)
    program.recordings = program.recordings + 1
    program.phase = InstalledSite
    return tonumber(frame.status)
end

function InstalledSite:execute(program, frame_owner)
    reset(frame_owner, program.bank)
    program.residual:execute(frame_owner.frame)
    return tonumber(frame_owner.frame.status)
end

function RejectedSite:execute()
    error("Lua55 opcode site was rejected during learning")
end

function ReleasedSite:execute() error("Lua55 opcode program was released") end

function Program.new(occurrences, value_count, exit_pc, bank, capacity, upvalue_count, heap_owner)
    assert(#occurrences > 0, "Lua55 opcode program is empty")
    local table_frame = false
    for index = 1, #occurrences do
        if occurrences[index].table_frame then table_frame = true end
    end
    local program = setmetatable({
        occurrences = occurrences, value_count = value_count, exit_pc = exit_pc,
        bank = bank, capacity = capacity or 16384, upvalue_count = upvalue_count or 0,
        table_frame = table_frame,
        heap_owner = heap_owner, phase = ColdSite, learner = false, residual = false, recordings = 0,
    }, Program)
    program.learner = build_learner(program)
    if heap_owner then heap_owner:retain_artifact() end
    return program
end

function Program:new_frame()
    return FrameOwner.new(
        self.value_count, #self.occurrences, self.upvalue_count, self.heap_owner, self.table_frame)
end
function Program:execute(frame_owner)
    assert(frame_owner.frame.value_count == self.value_count, "Lua55 opcode value count changed")
    assert(frame_owner.frame.slot_count >= #self.occurrences, "Lua55 opcode slot count changed")
    assert(frame_owner.frame.upvalue_count == self.upvalue_count, "Lua55 opcode upvalue count changed")
    assert(frame_owner.heap_owner == self.heap_owner, "Lua55 opcode heap owner changed")
    return self.phase.execute(self.phase, self, frame_owner)
end

function Program:free()
    if self.phase == ReleasedSite then return end
    self.learner:free()
    if self.residual then self.residual:free() end
    if self.heap_owner then self.heap_owner:release_artifact() end
    self.phase = ReleasedSite
end


-- ---- Native CPS Frame V2 leaves (leaf-owned patch products) ------------
local function value_disp(index)
    return index * ffi.sizeof("Lua55ValueV2")
end
function MoveOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[0], {
        target_disp = value_disp(self.target), source_disp = value_disp(self.source),
    })
end
function LoadIOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[1], {
        target_disp = value_disp(self.target),
        ["u64::integer"] = ffi.cast("uint64_t", ffi.new("int64_t", self.value)),
    })
end
function LoadFOccurrence:append_v2(machine)
    local holder = ffi.new("double[1]", self.value)
    machine:emit(machine.bank.v2[2], {
        target_disp = value_disp(self.target),
        ["u64::floating"] = ffi.cast("uint64_t *", holder)[0],
    })
end
function LoadKOccurrence:append_v2(machine)
    self.constant:append_loadk_v2(machine, self.target)
end
function LoadKXOccurrence:append_v2(machine)
    self.constant:append_loadk_v2(machine, self.target)
end
function LoadFalseOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[5], { target_disp = value_disp(self.target) })
end
function LoadFalseSkipOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[6], { target_disp = value_disp(self.target) })
end
function LoadTrueOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[7], { target_disp = value_disp(self.target) })
end
function LoadNilOccurrence:append_v2(machine)
    -- span is projection-proven; the exact leaf unrolls the nil stores
    assert(self.span >= 1 and self.span <= 8,
        "cps v2: unsupported LOADNIL span " .. tostring(self.span))
    machine:emit(machine.bank.residual["loadnil_" .. self.span],
        { target_disp = value_disp(self.target) })
end
function GetUpvalueOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[9], {
        target_disp = value_disp(self.target), upvalue_index = self.upvalue,
    })
end
function SetUpvalueOccurrence:append_v2(machine)
    machine:emit(machine.bank.v2[10], {
        source_disp = value_disp(self.source), upvalue_index = self.upvalue,
    })
end


-- ---- Native CPS Frame V2: exact constant leaves -------------------------
-- Each constant kind selects exactly one residual (no tag dispatch inside
-- the published record). Strings share one leaf; the exact string kind is a
-- patched value hole (5 short / 6 long), not a classification.
local function emit_loadk_v2(machine, target, record_name, extra)
    local product = { target_disp = value_disp(target) }
    for key, value in pairs(extra or {}) do product[key] = value end
    machine:emit(machine.bank.residual[record_name], product)
end
function NilConstant:append_loadk_v2(machine, target)
    emit_loadk_v2(machine, target, "loadk_nil")
end
function FalseConstant:append_loadk_v2(machine, target)
    emit_loadk_v2(machine, target, "loadk_false")
end
function TrueConstant:append_loadk_v2(machine, target)
    emit_loadk_v2(machine, target, "loadk_true")
end
function IntegerConstant:append_loadk_v2(machine, target)
    emit_loadk_v2(machine, target, "loadk_int", {
        ["u64::const_int"] = ffi.cast("uint64_t", self.value),
    })
end
function FloatConstant:append_loadk_v2(machine, target)
    local holder = ffi.new("double[1]", self.value)
    emit_loadk_v2(machine, target, "loadk_flt", {
        ["u64::const_flt"] = ffi.cast("uint64_t *", holder)[0],
    })
end
function ShortStringConstant:append_loadk_v2(machine, target)
    emit_loadk_v2(machine, target, "loadk_str", {
        const_tag = 5,
        ["u64::const_ref"] = self.owner:reference(),
    })
end
function LongStringConstant:append_loadk_v2(machine, target)
    emit_loadk_v2(machine, target, "loadk_str", {
        const_tag = 6,
        ["u64::const_ref"] = self.owner:reference(),
    })
end

return {
    Arena = Arena, append_finish = append_finish,
    Program = Program, FrameOwner = FrameOwner,
    MoveOccurrence = MoveOccurrence, LoadIOccurrence = LoadIOccurrence,
    LoadFOccurrence = LoadFOccurrence, LoadKOccurrence = LoadKOccurrence,
    LoadKXOccurrence = LoadKXOccurrence, LoadFalseOccurrence = LoadFalseOccurrence,
    LoadFalseSkipOccurrence = LoadFalseSkipOccurrence, LoadTrueOccurrence = LoadTrueOccurrence,
    LoadNilOccurrence = LoadNilOccurrence,
    GetUpvalueOccurrence = GetUpvalueOccurrence, SetUpvalueOccurrence = SetUpvalueOccurrence,
    NilConstant = NilConstant, FalseConstant = FalseConstant, TrueConstant = TrueConstant,
    IntegerConstant = IntegerConstant, FloatConstant = FloatConstant,
    ShortStringConstant = ShortStringConstant, LongStringConstant = LongStringConstant,
    extend_bank = extend_bank, quote_id = quote_id, ffi = ffi,
}
