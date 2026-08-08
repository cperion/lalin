local ffi = require("ffi")
assert(ffi.os == "Linux" and ffi.arch == "x64",
    "U64 runtime slot requires Linux x86-64")

ffi.cdef[[
void *mmap(void *, size_t, int, int, int, long);
int mprotect(void *, size_t, int);
int munmap(void *, size_t);
]]

local PROT_READ, PROT_WRITE, PROT_EXEC = 1, 2, 4
local MAP_PRIVATE, MAP_ANONYMOUS = 0x02, 0x20
local MAP_FAILED = ffi.cast("void *", -1)
local PAGE_SIZE = 4096

local WritableSlot = {}
WritableSlot.__index = WritableSlot
local ExecutableSlot = {}
ExecutableSlot.__index = ExecutableSlot
local ReleasedSlot = {}
ReleasedSlot.__index = ReleasedSlot
local Slot = {}
Slot.__index = Slot

local function protect(slot, permissions)
    assert(ffi.C.mprotect(slot.memory, PAGE_SIZE, permissions) == 0,
        "U64 runtime slot mprotect failed")
end

function WritableSlot:install(slot, variant)
    assert(variant.size <= slot.capacity, "U64 variant exceeds reserved slot capacity")
    ffi.fill(slot.memory, slot.capacity, 0x90)
    ffi.copy(slot.memory, variant.storage, variant.size)
    protect(slot, PROT_READ + PROT_EXEC)
    slot.phase = ExecutableSlot
    slot.variant = variant
    slot.generation = slot.generation + 1
    return slot
end

function ExecutableSlot:install(slot, variant)
    assert(not slot.borrowed, "cannot replace a borrowed U64 runtime slot")
    protect(slot, PROT_READ + PROT_WRITE)
    slot.phase = WritableSlot
    return WritableSlot:install(slot, variant)
end

function ReleasedSlot:install() error("U64 runtime slot was released", 2) end

function Slot.new(capacity)
    assert(capacity > 0 and capacity <= PAGE_SIZE, "invalid U64 runtime slot capacity")
    local raw = ffi.C.mmap(nil, PAGE_SIZE, PROT_READ + PROT_WRITE,
        MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    assert(raw ~= MAP_FAILED, "U64 runtime slot mmap failed")
    local memory = ffi.cast("uint8_t *", raw)
    return setmetatable({
        memory = memory, capacity = capacity, phase = WritableSlot,
        generation = 0, variant = false, borrowed = false,
    }, Slot)
end

function Slot:install(variant) return self.phase:install(self, variant) end

function Slot:native_installed(variant)
    assert(self.borrowed, "native U64 installation must hold the slot borrow")
    self.phase = ExecutableSlot
    self.variant = variant
    self.generation = self.generation + 1
    return self
end

function Slot:permissions()
    local address = tonumber(ffi.cast("uintptr_t", self.memory))
    local file = assert(io.open("/proc/self/maps", "r"))
    for line in file:lines() do
        local first, last, permissions = line:match("^(%x+)%-(%x+)%s+(....)")
        if first then
            local low, high = tonumber(first, 16), tonumber(last, 16)
            if address >= low and address < high then file:close(); return permissions end
        end
    end
    file:close(); error("U64 runtime slot mapping not found")
end

function Slot:bytes()
    assert(self.phase ~= ReleasedSlot, "U64 runtime slot was released")
    return ffi.string(self.memory, self.capacity)
end

function Slot:free()
    if self.phase == ReleasedSlot then return end
    assert(not self.borrowed, "cannot release a borrowed U64 runtime slot")
    assert(ffi.C.munmap(self.memory, PAGE_SIZE) == 0, "U64 runtime slot munmap failed")
    self.memory = false
    self.phase = ReleasedSlot
end

return { Slot = Slot }
