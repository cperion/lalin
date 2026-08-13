local Native = require("experiments.copy_patch_cps.lua55_trace.opcode_00_08")
local ffi = Native.ffi
local bit = require("bit")

local KIND_SHORT_STRING, KIND_LONG_STRING = 1, 2

local StringOwner = {}
StringOwner.__index = StringOwner

function StringOwner:reference()
    assert(self.object ~= false, "Lua55 guest string was released")
    return ffi.cast("uintptr_t", self.object)
end

function StringOwner:length() return #self.text end
function StringOwner:bytes() return self.text end
function StringOwner:generation() return tonumber(self.object[0].header.generation) end
function StringOwner:assert_native_ownership()
    assert(self.heap_owner:owns_native_span(self.object, ffi.sizeof("Lua55GuestStringV1")),
        "guest string object is outside the mmap heap")
    assert(self.heap_owner:owns_native_span(self.object[0].bytes, math.max(#self.text, 1)),
        "guest string bytes are outside the mmap heap")
    return self
end
function StringOwner:release_storage()
    self.object = false
    self.byte_owner = false
end

local TableOwner = {}
TableOwner.__index = TableOwner

function TableOwner:reference()
    assert(self.object ~= false, "Lua55 guest table was released")
    return ffi.cast("uintptr_t", self.object)
end

function TableOwner:generation() return tonumber(self.object[0].header.generation) end
function TableOwner:storage_generation() return tonumber(self.object[0].storage_generation) end
function TableOwner:barrier_count() return tonumber(self.object[0].barrier_count) end

function TableOwner:assert_native_ownership()
    assert(self.heap_owner:owns_native_span(self.object, ffi.sizeof("Lua55GuestTableV1")),
        "guest table object is outside the mmap heap")
    assert(self.heap_owner:owns_native_span(self.array_values,
        ffi.sizeof("Lua55ValueV1") * math.max(tonumber(self.object[0].array_capacity), 1)),
        "guest table array is outside the mmap heap")
    assert(self.heap_owner:owns_native_span(self.field_values,
        ffi.sizeof("Lua55GuestFieldV1") * math.max(tonumber(self.object[0].field_capacity), 1)),
        "guest table fields are outside the mmap heap")
    assert(self.object[0].heap == self.heap_owner.heap,
        "guest table heap pointer changed")
    return self
end

local function clear_value(value)
    value.tag, value.reserved = 0, 0
    value.payload.reference = 0
end

local function set_integer(value, payload)
    value.tag, value.reserved = 3, 0
    value.payload.integer = ffi.new("int64_t", payload)
end

local function set_float(value, payload)
    value.tag, value.reserved = 4, 0
    value.payload.floating = payload
end

local function set_string(table_owner, value, owner, tag)
    assert(owner.heap_owner == table_owner.heap_owner, "table string belongs to another guest heap")
    value.tag, value.reserved = tag, 0
    value.payload.reference = owner:reference()
    table_owner.object[0].barrier_count = table_owner.object[0].barrier_count + 1
    table_owner.heap_owner.heap[0].barrier_epoch =
        table_owner.heap_owner.heap[0].barrier_epoch + 1
end

local function set_boolean(value, payload)
    value.tag, value.reserved = payload, 0
    value.payload.reference = 0
end

function TableOwner:array_value(key)
    assert(key >= 1 and key <= tonumber(self.object[0].array_capacity),
        "array key is outside fixed capacity")
    return self.array_values[key - 1]
end

function TableOwner:set_array_nil(key) clear_value(self:array_value(key)); return self end
function TableOwner:set_array_false(key) set_boolean(self:array_value(key), 1); return self end
function TableOwner:set_array_true(key) set_boolean(self:array_value(key), 2); return self end
function TableOwner:set_array_integer(key, value) set_integer(self:array_value(key), value); return self end
function TableOwner:set_array_float(key, value) set_float(self:array_value(key), value); return self end
function TableOwner:set_array_short_string(key, owner)
    set_string(self, self:array_value(key), owner, 5); return self
end
function TableOwner:set_array_long_string(key, owner)
    set_string(self, self:array_value(key), owner, 6); return self
end

function TableOwner:field_value(key_owner, create)
    assert(key_owner.heap_owner == self.heap_owner and key_owner.kind == KIND_SHORT_STRING,
        "table field key must be a short string in the same guest heap")
    local reference = key_owner:reference()
    local vacant = false
    for index = 0, tonumber(self.object[0].field_capacity) - 1 do
        local field = self.field_values[index]
        if field.occupied ~= 0 and field.key_reference == reference then return field.value end
        if field.occupied == 0 and vacant == false then vacant = index end
    end
    if not create then return false end
    assert(vacant ~= false, "table field storage capacity exceeded")
    local field = self.field_values[vacant]
    field.key_reference, field.occupied, field.reserved = reference, 1, 0
    clear_value(field.value)
    self.object[0].storage_generation = self.object[0].storage_generation + 1
    return field.value
end

function TableOwner:set_field_nil(key) clear_value(self:field_value(key, true)); return self end
function TableOwner:set_field_false(key) set_boolean(self:field_value(key, true), 1); return self end
function TableOwner:set_field_true(key) set_boolean(self:field_value(key, true), 2); return self end
function TableOwner:set_field_integer(key, value)
    set_integer(self:field_value(key, true), value); return self
end
function TableOwner:set_field_float(key, value) set_float(self:field_value(key, true), value); return self end
function TableOwner:set_field_short_string(key, owner)
    set_string(self, self:field_value(key, true), owner, 5); return self
end
function TableOwner:set_field_long_string(key, owner)
    set_string(self, self:field_value(key, true), owner, 6); return self
end

function TableOwner:set_metatable(owner)
    assert(owner == nil or owner.heap_owner == self.heap_owner, "metatable belongs to another guest heap")
    self.object[0].metatable_reference = owner and owner:reference() or 0
    self.object[0].storage_generation = self.object[0].storage_generation + 1
    return self
end

function TableOwner:release_storage()
    self.object = false
    self.array_values = false
    self.field_values = false
end

local GuestHeap = {}
GuestHeap.__index = GuestHeap

local function hash_string(text)
    local hash = 5381
    for index = 1, #text do
        hash = bit.tobit(hash * 33 + text:byte(index))
    end
    return ffi.cast("uint32_t", hash)
end

local function align16_address(address)
    local remainder = tonumber(address % 16)
    return remainder == 0 and address or address + (16 - remainder)
end

local function bump_storage(heap, size)
    local next_ = heap.heap[0].table_next
    local aligned = align16_address(next_)
    assert(aligned + size <= heap.heap[0].table_region_end,
        "guest heap bump region exhausted")
    heap.heap[0].table_next = aligned + size
    local storage = ffi.cast("uint8_t *", aligned)
    ffi.fill(storage, size, 0)
    return storage
end

function GuestHeap.new(generation, region_size)
    -- The heap header and every native-visible guest object share one
    -- nonmoving mmap allocation. Lua wrappers retain descriptions and
    -- interning indexes only; native code never points into LuaJIT cdata.
    region_size = region_size or bit.lshift(1, 20)
    local raw = ffi.C.mmap(nil, region_size,
        bit.bor(1, 2), 0x22, -1, 0)  -- PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS
    assert(raw ~= ffi.cast("void *", -1), "Lua55 guest heap mmap failed")
    local heap = ffi.cast("Lua55GuestHeapV1 *", raw)
    local payload_begin = align16_address(
        ffi.cast("uintptr_t", raw) + ffi.sizeof("Lua55GuestHeapV1"))
    local region_end = ffi.cast("uintptr_t", raw) + region_size
    assert(payload_begin < region_end, "Lua55 guest heap region is too small")
    heap[0].generation = generation or 1
    heap[0].collection_epoch = 1
    heap[0].object_count = 0
    heap[0].barrier_epoch = 1
    heap[0].table_region = payload_begin
    heap[0].table_region_end = region_end
    heap[0].table_next = payload_begin
    return setmetatable({
        heap = heap, entries = {}, artifact_count = 0, live = true,
        region = raw, region_size = region_size,
    }, GuestHeap)
end

function GuestHeap:owns_native_span(address, size)
    if not self.live or address == nil then return false end
    local first = ffi.cast("uintptr_t", address)
    local begin = ffi.cast("uintptr_t", self.region)
    local limit = begin + self.region_size
    return first >= begin and first + size <= limit
end

function GuestHeap:assert_native_ownership()
    assert(self:owns_native_span(self.heap, ffi.sizeof("Lua55GuestHeapV1")),
        "guest heap header is outside its mmap owner")
    for index = 1, #self.entries do
        self.entries[index]:assert_native_ownership()
    end
    return self
end

function GuestHeap:retain_artifact()
    assert(self.live, "Lua55 guest heap was released")
    self.artifact_count = self.artifact_count + 1
end

function GuestHeap:release_artifact()
    assert(self.artifact_count > 0, "Lua55 guest heap artifact count underflow")
    self.artifact_count = self.artifact_count - 1
end

function GuestHeap:collection_epoch()
    assert(self.live, "Lua55 guest heap was released")
    return tonumber(self.heap[0].collection_epoch)
end

function GuestHeap:advance_collection_epoch()
    assert(self.live, "Lua55 guest heap was released")
    self.heap[0].collection_epoch = self.heap[0].collection_epoch + 1
    return tonumber(self.heap[0].collection_epoch)
end

local function find_string(heap, kind, text)
    for index = 1, #heap.entries do
        local owner = heap.entries[index]
        if owner.kind == kind and owner.text == text then return owner end
    end
    return false
end

local function make_string(heap, kind, text)
    assert(heap.live, "Lua55 guest heap was released")
    local existing = find_string(heap, kind, text)
    if existing then return existing end

    local object = ffi.cast("Lua55GuestStringV1 *",
        bump_storage(heap, ffi.sizeof("Lua55GuestStringV1")))
    local byte_count = math.max(#text, 1)
    local bytes = bump_storage(heap, byte_count)
    if #text > 0 then ffi.copy(bytes, text, #text) end
    local generation = tonumber(heap.heap[0].object_count) + 1
    object[0].header.kind = kind
    object[0].header.generation = generation
    object[0].length = #text
    object[0].hash = hash_string(text)
    object[0].bytes = bytes
    heap.heap[0].object_count = generation
    local owner = setmetatable({
        heap_owner = heap, object = object, byte_owner = bytes, kind = kind, text = text,
    }, StringOwner)
    heap.entries[#heap.entries + 1] = owner
    return owner
end

function GuestHeap:table(array_capacity, field_capacity)
    assert(self.live, "Lua55 guest heap was released")
    assert(array_capacity >= 0 and field_capacity >= 0, "negative table capacity")
    local arrays = ffi.cast("Lua55ValueV1 *",
        bump_storage(self, ffi.sizeof("Lua55ValueV1") * math.max(array_capacity, 1)))
    local fields = ffi.cast("Lua55GuestFieldV1 *",
        bump_storage(self, ffi.sizeof("Lua55GuestFieldV1") * math.max(field_capacity, 1)))
    local object = ffi.cast("Lua55GuestTableV1 *",
        bump_storage(self, ffi.sizeof("Lua55GuestTableV1")))
    local generation = tonumber(self.heap[0].object_count) + 1
    object[0].header.kind = 3
    object[0].header.generation = generation
    object[0].storage_generation = 1
    object[0].array_capacity = array_capacity
    object[0].field_capacity = field_capacity
    object[0].barrier_count = 0
    object[0].metatable_reference = 0
    object[0].array_values = arrays
    object[0].field_values = fields
    object[0].heap = self.heap
    object[0].site_id = 0
    object[0].learn_reserved = 0
    self.heap[0].object_count = generation
    local owner = setmetatable({
        heap_owner = self, object = object, array_values = arrays, field_values = fields,
    }, TableOwner)
    self.entries[#self.entries + 1] = owner
    return owner
end

function GuestHeap:short_string(text) return make_string(self, KIND_SHORT_STRING, text) end
function GuestHeap:long_string(text) return make_string(self, KIND_LONG_STRING, text) end

-- A native builtin marker (1=next 2=ipairs-iter 3=pairs 4=ipairs): a
-- closure-tagged guest object the host dispatches on.
function GuestHeap:builtin(builtin_id)
    assert(self.live, "Lua55 guest heap was released")
    local size = ffi.sizeof("Lua55GuestBuiltinV1")
    local object = ffi.cast("Lua55GuestBuiltinV1 *", bump_storage(self, size))
    object[0].header.kind = 5
    object[0].header.generation = tonumber(self.heap[0].object_count) + 1
    object[0].builtin_id = builtin_id
    self.heap[0].object_count = object[0].header.generation
    return ffi.cast("uintptr_t", object)
end

function GuestHeap:builtin_value(builtin_id)
    local reference = self:builtin(builtin_id)
    return setmetatable({ heap_owner = self, reference = reference }, {
        __index = function(t, k)
            if k == "reference" then return reference end
        end,
    })
end

function GuestHeap:free()
    if not self.live then return end
    assert(self.artifact_count == 0, "Lua55 guest heap still has RX artifacts")
    self.live = false
    for index = 1, #self.entries do self.entries[index]:release_storage() end
    self.entries = false
    if self.region then
        assert(ffi.C.munmap(self.region, self.region_size) == 0)
        self.region, self.region_size = false, false
    end
    self.heap = false
end

return {
    GuestHeap = GuestHeap, StringOwner = StringOwner, TableOwner = TableOwner,
    KIND_SHORT_STRING = KIND_SHORT_STRING, KIND_LONG_STRING = KIND_LONG_STRING,
    KIND_TABLE = 3,
}
