local ffi = require("ffi")

ffi.cdef[[
void *mmap(void *, size_t, int, int, int, long);
int mprotect(void *, size_t, int);
int munmap(void *, size_t);
typedef union Lua55TraceNumericPayloadV1 {
    int64_t integer;
    double floating;
} Lua55TraceNumericPayloadV1;
typedef struct Lua55TraceNumericValueV1 {
    uint32_t tag;
    uint32_t reserved;
    Lua55TraceNumericPayloadV1 payload;
} Lua55TraceNumericValueV1;
typedef struct Lua55TraceNumericFrameV1 {
    Lua55TraceNumericValueV1 *values;
    uint32_t count;
    uint32_t top;
    uint32_t resume_pc;
    uint32_t generation;
    uint32_t learned;
} Lua55TraceNumericFrameV1;
typedef void (*Lua55TraceNativeEntryV1)(Lua55TraceNumericFrameV1 *);
]]

local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
local MAP_PRIVATE, MAP_ANONYMOUS = 0x02, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local function patch_u64(memory, offset, value)
    ffi.cast("uint64_t *", memory + offset)[0] = value
end

local function patch_i32(memory, offset, value)
    assert(value >= -0x80000000 and value <= 0x7fffffff)
    ffi.cast("int32_t *", memory + offset)[0] = value
end

local function patch_all(memory, base, offsets, value)
    for index = 1, #offsets do patch_i32(memory, base + offsets[index], value) end
end

local function register_tag(index) return index * 16 end
local function register_payload(index) return index * 16 + 8 end

local NativeProgram = {}
NativeProgram.__index = NativeProgram

function NativeProgram:execute(frame)
    assert(self.entry ~= false, "Lua55 native trace was released")
    self.entry(frame)
end

function NativeProgram:permissions()
    assert(self.entry ~= false, "Lua55 native trace was released")
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
    error("Lua55 native trace mapping not found")
end

function NativeProgram:machine_code()
    assert(self.entry ~= false, "Lua55 native trace was released")
    return ffi.string(self.memory, self.size)
end

function NativeProgram:free()
    if self.entry == false then return end
    local memory = self.memory
    ffi.gc(memory, nil)
    self.entry, self.memory = false, false
    assert(ffi.C.munmap(memory, self.mapping_size) == 0)
end

local NativeArena = {}
NativeArena.__index = NativeArena

function NativeArena.new(bank, capacity)
    capacity = capacity or 4096
    local mapping_size = math.floor((capacity + 4095) / 4096) * 4096
    local raw = ffi.C.mmap(nil, mapping_size, PROT_READ + PROT_WRITE,
        MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    assert(raw ~= MAP_FAILED, "Lua55 trace mmap RW failed")
    local memory = ffi.cast("uint8_t *", raw)
    return setmetatable({
        bank = bank, memory = memory, mapping_size = mapping_size,
        capacity = capacity, cursor = 0, sealed = false,
    }, NativeArena)
end

function NativeArena:append(record)
    assert(not self.sealed, "Lua55 trace arena is sealed")
    local offset, required = self.cursor, self.cursor + #record.code
    assert(required <= self.capacity, "Lua55 trace arena capacity exceeded")
    ffi.copy(self.memory + offset, record.code, #record.code)
    self.cursor = required
    return offset, #record.code
end

local function patch_plan_registers(memory, offset, record, plan)
    patch_all(memory, offset, record.index_tag, register_tag(plan.index.index))
    patch_all(memory, offset, record.limit_tag, register_tag(plan.limit.index))
    patch_all(memory, offset, record.step_tag, register_tag(plan.step.index))
    patch_all(memory, offset, record.index_payload, register_payload(plan.index.index))
    patch_all(memory, offset, record.limit_payload, register_payload(plan.limit.index))
    patch_all(memory, offset, record.step_payload, register_payload(plan.step.index))
    patch_all(memory, offset, record.sum_tag, register_tag(plan.sum.index))
    patch_all(memory, offset, record.sum_payload, register_payload(plan.sum.index))
end

function NativeArena:append_learn_integer_add_forloop(plan)
    local record = self.bank.learn_integer_add_forloop
    local offset, size = self:append(record)
    patch_plan_registers(self.memory, offset, record, plan)
    for index = 1, #record.resume do
        patch_i32(self.memory, offset + record.resume[index], plan.exit_pc)
    end
    return offset, size
end

function NativeArena:append_integer_add_forloop_plan(plan)
    local record = self.bank.fused_integer_loop
    local offset, size = self:append(record)
    patch_plan_registers(self.memory, offset, record, plan)
    for index = 1, #record.resume do
        patch_i32(self.memory, offset + record.resume[index], plan.exit_pc)
    end
    return offset, size
end

function NativeArena:seal_complete(root_offset)
    assert(not self.sealed, "Lua55 trace arena is sealed")
    self.sealed = true
    assert(ffi.C.mprotect(self.memory, self.mapping_size, PROT_READ + PROT_EXEC) == 0,
        "Lua55 trace mprotect RX failed")
    local raw, mapping_size = self.memory, self.mapping_size
    self.memory = false
    local memory = ffi.gc(raw, function(pointer) ffi.C.munmap(pointer, mapping_size) end)
    return setmetatable({
        memory = memory, mapping_size = mapping_size, size = self.cursor,
        entry = ffi.cast("Lua55TraceNativeEntryV1", memory + root_offset),
    }, NativeProgram)
end

function NativeArena:free()
    if self.memory == false then return end
    local memory = self.memory
    self.memory = false
    assert(ffi.C.munmap(memory, self.mapping_size) == 0)
end

return { NativeArena = NativeArena, NativeProgram = NativeProgram, ffi = ffi }
