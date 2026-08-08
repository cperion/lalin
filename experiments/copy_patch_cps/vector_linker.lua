local ffi = require("ffi")
assert(ffi.os == "Linux" and ffi.arch == "x64",
    "F64MapPipelineV1 requires Linux x86-64 SysV")

ffi.cdef[[
typedef struct CopyPatchF64MapFrameV1 {
    const double *input;
    double *output;
    uint64_t count;
    double scalar0;
    double scalar1;
    double scalar2;
    double scalar3;
} CopyPatchF64MapFrameV1;

void *mmap(void *addr, size_t length, int prot, int flags, int fd, long offset);
int mprotect(void *addr, size_t len, int prot);
int munmap(void *addr, size_t length);
const char *strerror(int errnum);
typedef void (*CopyPatchF64MapEntry)(CopyPatchF64MapFrameV1 *frame);
typedef struct CopyPatchF32MapFrameV1 {
    const float *input; float *output; uint64_t count;
    float scalar0; float scalar1; float scalar2; float scalar3;
} CopyPatchF32MapFrameV1;
typedef void (*CopyPatchF32MapEntry)(CopyPatchF32MapFrameV1 *frame);
]]

local PROT_READ, PROT_WRITE, PROT_EXEC = 0x1, 0x2, 0x4
local MAP_PRIVATE, MAP_ANONYMOUS = 0x02, 0x20
local MAP_FAILED = ffi.cast("void *", -1)

local Bank = {}
Bank.__index = Bank

local VectorLayout = {}
VectorLayout.__index = VectorLayout

local NativeProgram = {}
NativeProgram.__index = NativeProgram

local function code(value, name)
    assert(type(value) == "string" and #value > 0, name .. " must contain code")
    return value
end

local function offset(value, name)
    assert(type(value) == "number" and value >= 0 and value == math.floor(value),
        name .. " must be a nonnegative integer")
    return value
end

local function new_bank(spec)
    return setmetatable({
        gcc = assert(spec.gcc),
        entry_type = spec.entry_type or "CopyPatchF64MapEntry",
        entry_code = code(spec.entry_code, "entry_code"),
        entry_next = offset(spec.entry_next, "entry_next"),
        vector_test_code = code(spec.vector_test_code, "vector_test_code"),
        vector_full = offset(spec.vector_full, "vector_full"),
        vector_tail = offset(spec.vector_tail, "vector_tail"),
        vector_load_prefix = code(spec.vector_load_prefix, "vector_load_prefix"),
        vector_store_code = code(spec.vector_store_code, "vector_store_code"),
        vector_store_next = offset(spec.vector_store_next, "vector_store_next"),
        scalar_test_code = code(spec.scalar_test_code, "scalar_test_code"),
        scalar_some = offset(spec.scalar_some, "scalar_some"),
        scalar_done = offset(spec.scalar_done, "scalar_done"),
        scalar_load_prefix = code(spec.scalar_load_prefix, "scalar_load_prefix"),
        scalar_store_code = code(spec.scalar_store_code, "scalar_store_code"),
        scalar_store_next = offset(spec.scalar_store_next, "scalar_store_next"),
        add0_prefix = code(spec.add0_prefix, "add0_prefix"),
        add1_prefix = code(spec.add1_prefix, "add1_prefix"),
        add2_prefix = code(spec.add2_prefix, "add2_prefix"),
        add3_prefix = code(spec.add3_prefix, "add3_prefix"),
        mul0_prefix = code(spec.mul0_prefix, "mul0_prefix"),
        mul1_prefix = code(spec.mul1_prefix, "mul1_prefix"),
        mul2_prefix = code(spec.mul2_prefix, "mul2_prefix"),
        mul3_prefix = code(spec.mul3_prefix, "mul3_prefix"),
        square_prefix = code(spec.square_prefix, "square_prefix"),
        finish_code = code(spec.finish_code, "finish_code"),
    }, Bank)
end

local avx2_available

local function assert_avx2()
    if avx2_available then return end
    local file = assert(io.open("/proc/cpuinfo", "r"))
    local text = file:read("*a")
    file:close()
    local flags = text:match("\nflags%s*:%s*([^\n]+)")
    assert(flags and flags:match("%f[%w]avx%f[%W]")
        and flags:match("%f[%w]avx2%f[%W]"),
        "F64MapPipelineV1 requires OS-enabled AVX and AVX2")
    avx2_available = true
end

local function align(value, alignment)
    return math.floor((value + alignment - 1) / alignment) * alignment
end

local function image_builder()
    local pieces, cursor = {}, 0
    local function append(bytes, alignment)
        local start = align(cursor, alignment or 1)
        if start > cursor then pieces[#pieces + 1] = string.rep("\x90", start - cursor) end
        pieces[#pieces + 1] = bytes
        cursor = start + #bytes
        return start
    end
    local function finish() return table.concat(pieces), cursor end
    return append, finish
end

local function mmap_error(operation)
    local errno = ffi.errno()
    error(operation .. " failed: " .. ffi.string(ffi.C.strerror(errno)), 3)
end

local function patch_rel32(memory, patch_offset, target_offset)
    local displacement = target_offset - (patch_offset + 4)
    assert(displacement >= -0x80000000 and displacement <= 0x7fffffff,
        "x86-64 rel32 successor is out of range")
    ffi.cast("int32_t *", memory + patch_offset)[0] = displacement
end

local function release(memory, size)
    if memory ~= nil and ffi.C.munmap(memory, size) ~= 0 then mmap_error("munmap") end
end

function Bank:link(bound_operations)
    assert_avx2()
    local append, finish_image = image_builder()

    local entry = append(self.entry_code, 32)
    local vector_test = append(self.vector_test_code, 16)
    local vector_body = append(self.vector_load_prefix, 16)
    for index = 1, #bound_operations do
        append(bound_operations[index]:prefix(self))
    end
    local vector_store = append(self.vector_store_code)

    local scalar_test = append(self.scalar_test_code, 16)
    local scalar_body = append(self.scalar_load_prefix, 16)
    for index = 1, #bound_operations do
        append(bound_operations[index]:prefix(self))
    end
    local scalar_store = append(self.scalar_store_code)
    local finish = append(self.finish_code, 16)

    local image, size = finish_image()
    local layout = setmetatable({
        entry = entry,
        vector_test = vector_test,
        vector_body = vector_body,
        vector_store = vector_store,
        scalar_test = scalar_test,
        scalar_body = scalar_body,
        scalar_store = scalar_store,
        finish = finish,
        size = size,
    }, VectorLayout)

    local raw = ffi.C.mmap(nil, size, PROT_READ + PROT_WRITE,
        MAP_PRIVATE + MAP_ANONYMOUS, -1, 0)
    if raw == MAP_FAILED then mmap_error("mmap RW") end
    local memory = ffi.cast("uint8_t *", raw)
    ffi.copy(memory, image, size)

    -- Every offset is published before either native recurrence is bound.
    patch_rel32(memory, entry + self.entry_next, vector_test)
    patch_rel32(memory, vector_test + self.vector_full, vector_body)
    patch_rel32(memory, vector_test + self.vector_tail, scalar_test)
    patch_rel32(memory, vector_store + self.vector_store_next, vector_test)
    patch_rel32(memory, scalar_test + self.scalar_some, scalar_body)
    patch_rel32(memory, scalar_test + self.scalar_done, finish)
    patch_rel32(memory, scalar_store + self.scalar_store_next, scalar_test)

    if ffi.C.mprotect(memory, size, PROT_READ + PROT_EXEC) ~= 0 then
        release(memory, size)
        mmap_error("mprotect RX")
    end

    local owned = ffi.gc(memory, function(pointer) release(pointer, size) end)
    return setmetatable({
        memory = owned,
        entry = ffi.cast(self.entry_type, owned + entry),
        layout = layout,
        size = size,
        gcc = self.gcc,
    }, NativeProgram)
end

function NativeProgram:execute(state)
    assert(self.entry ~= false, "F64MapPipelineV1 native program was released")
    self.entry(state)
    return self
end

function NativeProgram:machine_code()
    assert(self.entry ~= false, "F64MapPipelineV1 native program was released")
    return ffi.string(self.memory, self.size)
end

function NativeProgram:free()
    if self.entry == false then return end
    local memory = self.memory
    ffi.gc(memory, nil)
    self.entry = false
    self.memory = false
    release(memory, self.size)
end

return {
    ffi = ffi,
    Bank = new_bank,
    NativeProgram = NativeProgram,
}
