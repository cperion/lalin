local ffi = require("ffi")
assert(ffi.os == "Linux" and ffi.arch == "x64",
    "copy-patch CPS currently requires Linux x86-64 SysV")

ffi.cdef[[
typedef struct CopyPatchCpsFrame {
    int64_t limit;
    int64_t result;
} CopyPatchCpsFrame;

void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
int mprotect(void *addr, size_t len, int prot);
int munmap(void *addr, size_t length);
const char *strerror(int errnum);
typedef void (*CopyPatchCpsEntry)(CopyPatchCpsFrame *frame);
]]

local PROT_READ, PROT_WRITE, PROT_EXEC = 0x1, 0x2, 0x4
local MAP_PRIVATE, MAP_ANONYMOUS = 0x02, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local Bank = {}
Bank.__index = Bank

local NativeLayout = {}
NativeLayout.__index = NativeLayout

local Program = {}
Program.__index = Program

local function exact_integer(value, name)
    assert(type(value) == "number" and value >= 0 and value == math.floor(value),
        name .. " must be a nonnegative integer")
    return value
end

local function exact_code(value, name)
    assert(type(value) == "string" and #value > 0, name .. " must contain code")
    return value
end

local function new_bank(spec)
    return setmetatable({
        gcc = assert(spec.gcc),
        entry_code = exact_code(spec.entry_code, "entry_code"),
        entry_next = exact_integer(spec.entry_next, "entry_next"),
        loop_code = exact_code(spec.loop_code, "loop_code"),
        loop_repeat = exact_integer(spec.loop_repeat, "loop_repeat"),
        loop_exit = exact_integer(spec.loop_exit, "loop_exit"),
        body_code = exact_code(spec.body_code, "body_code"),
        body_next = exact_integer(spec.body_next, "body_next"),
        finish_code = exact_code(spec.finish_code, "finish_code"),
    }, Bank)
end

local function align(value, alignment)
    return math.floor((value + alignment - 1) / alignment) * alignment
end

function Bank:layout()
    local entry = 0
    local loop = align(entry + #self.entry_code, 16)
    local body = align(loop + #self.loop_code, 16)
    local finish = align(body + #self.body_code, 16)
    local size = finish + #self.finish_code
    return setmetatable({
        entry = entry, loop = loop, body = body, finish = finish, size = size,
    }, NativeLayout)
end

local function mmap_error(operation)
    local errno = ffi.errno()
    error(operation .. " failed: " .. ffi.string(ffi.C.strerror(errno)), 3)
end

local function copy_at(memory, offset, code)
    ffi.copy(memory + offset, code, #code)
end

local function patch_rel32(memory, patch_offset, target_offset)
    local displacement = target_offset - (patch_offset + 4)
    assert(displacement >= -0x80000000 and displacement <= 0x7fffffff,
        "x86-64 rel32 successor is out of range")
    ffi.cast("int32_t *", memory + patch_offset)[0] = displacement
end

local function protect_rx(memory, size)
    if ffi.C.mprotect(memory, size, PROT_READ + PROT_EXEC) ~= 0 then
        mmap_error("mprotect RX")
    end
end

local function release(memory, size)
    if memory ~= nil and ffi.C.munmap(memory, size) ~= 0 then
        mmap_error("munmap")
    end
end

function Bank:link()
    local layout = self:layout()
    local raw = ffi.C.mmap(
        nil, layout.size, PROT_READ + PROT_WRITE,
        MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    if raw == MAP_FAILED then mmap_error("mmap RW") end
    local memory = ffi.cast("uint8_t *", raw)

    copy_at(memory, layout.entry, self.entry_code)
    copy_at(memory, layout.loop, self.loop_code)
    copy_at(memory, layout.body, self.body_code)
    copy_at(memory, layout.finish, self.finish_code)

    -- Publish every code offset before binding the cyclic CPS graph.
    patch_rel32(memory, layout.entry + self.entry_next, layout.loop)
    patch_rel32(memory, layout.loop + self.loop_repeat, layout.body)
    patch_rel32(memory, layout.loop + self.loop_exit, layout.finish)
    patch_rel32(memory, layout.body + self.body_next, layout.loop)

    protect_rx(memory, layout.size)
    local owned = ffi.gc(memory, function(pointer) release(pointer, layout.size) end)
    return setmetatable({
        memory = owned,
        size = layout.size,
        layout = layout,
        entry = ffi.cast("CopyPatchCpsEntry", owned + layout.entry),
        gcc = self.gcc,
    }, Program)
end

function Program:new_frame()
    return ffi.new("CopyPatchCpsFrame")
end

function Program:execute(frame, limit)
    assert(self.entry ~= false, "copy-patch program was released")
    frame.limit = limit
    frame.result = 0
    self.entry(frame)
    return self
end

function Program:free()
    if self.entry == false then return end
    local memory = self.memory
    ffi.gc(memory, nil)
    self.entry = false
    self.memory = false
    release(memory, self.size)
end

return {
    Bank = new_bank,
    Program = Program,
}
