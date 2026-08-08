local ffi = require("ffi")
assert(ffi.os == "Linux" and ffi.arch == "x64", "negative-space V1 requires Linux x86-64")
ffi.cdef[[
typedef struct {
    const double *input; uint64_t count; double result;
} F64ReductionV1Frame;
typedef struct {
    const uint8_t *input; uint64_t count; uint8_t needle; uint64_t found;
} U8ScanV1Frame;
typedef struct {
    const uint8_t *input; uint64_t count;
    uint8_t needle0; uint8_t needle1; uint8_t needle2; uint8_t needle3;
    uint64_t result;
} U8ScanSetV1Frame;
typedef struct {
    const double *left; const double *right; double *output;
    uint64_t count; double scale;
} F64ZipMapV1Frame;
typedef struct {
    const float *input; float *output; uint64_t count;
    float scalar0; float scalar1; float scalar2; float scalar3;
} F32MapPipelineV1Frame;
typedef struct {
    const uint64_t *input; uint64_t *output; uint64_t count;
    uint64_t addend; uint64_t xor_value; uint64_t rotate;
} U64BulkV1Frame;
void *mmap(void *, size_t, int, int, int, long);
int mprotect(void *, size_t, int);
int munmap(void *, size_t);
typedef void (*F64ReductionV1Entry)(F64ReductionV1Frame *);
typedef void (*U8ScanV1Entry)(U8ScanV1Frame *);
typedef void (*U8ScanSetV1Entry)(U8ScanSetV1Frame *);
typedef void (*F64ZipMapV1Entry)(F64ZipMapV1Frame *);
typedef void (*F32MapPipelineV1Entry)(F32MapPipelineV1Frame *);
typedef void (*U64BulkV1Entry)(U64BulkV1Frame *);
]]

local Bank = {}; Bank.__index = Bank
local Suite = {}; Suite.__index = Suite
local function exact(value, name) assert(type(value) == "string" and #value > 0, name); return value end
local function new_bank(spec)
    return setmetatable({
        gcc = assert(spec.gcc),
        reduction = exact(spec.ns_f64_reduction, "missing reduction"),
        min_number = exact(spec.ns_f64_min_number, "missing min number"),
        max_number = exact(spec.ns_f64_max_number, "missing max number"),
        scan = exact(spec.ns_u8_scan, "missing scan"),
        find_any2 = exact(spec.ns_u8_find_any2, "missing find any2"),
        find_any4 = exact(spec.ns_u8_find_any4, "missing find any4"),
        count_byte = exact(spec.ns_u8_count_byte, "missing count byte"),
        all_equal = exact(spec.ns_u8_all_equal, "missing all equal"),
        zip_add = exact(spec.ns_f64_zip_add, "missing zip add"),
        zip_multiply = exact(spec.ns_f64_zip_multiply, "missing zip multiply"),
        zip = exact(spec.ns_f64_zip_map, "missing zip"),
        f32 = exact(spec.ns_f32_map, "missing f32 map"),
        u64 = exact(spec.ns_u64_bulk, "missing u64 bulk"),
    }, Bank)
end
local function align(value) return math.floor((value + 31) / 32) * 32 end
local function avx2()
    local file = assert(io.open("/proc/cpuinfo")); local text = file:read("*a"); file:close()
    local flags = text:match("\nflags%s*:%s*([^\n]+)")
    assert(flags and flags:match("%f[%w]avx2%f[%W]"), "negative-space V1 requires AVX2")
end

function Bank:link()
    avx2()
    local reduction = 0
    local min_number = align(reduction + #self.reduction)
    local max_number = align(min_number + #self.min_number)
    local scan = align(max_number + #self.max_number)
    local find_any2 = align(scan + #self.scan)
    local find_any4 = align(find_any2 + #self.find_any2)
    local count_byte = align(find_any4 + #self.find_any4)
    local all_equal = align(count_byte + #self.count_byte)
    local zip_add = align(all_equal + #self.all_equal)
    local zip_multiply = align(zip_add + #self.zip_add)
    local zip = align(zip_multiply + #self.zip_multiply)
    local f32 = align(zip + #self.zip)
    local u64 = align(f32 + #self.f32)
    local size = u64 + #self.u64
    local raw = ffi.C.mmap(nil, size, 3, 0x22, -1, 0)
    assert(raw ~= ffi.cast("void *", -1), "negative-space mmap RW failed")
    local memory = ffi.cast("uint8_t *", raw)
    ffi.fill(memory, size, 0x90)
    ffi.copy(memory + reduction, self.reduction, #self.reduction)
    ffi.copy(memory + min_number, self.min_number, #self.min_number)
    ffi.copy(memory + max_number, self.max_number, #self.max_number)
    ffi.copy(memory + scan, self.scan, #self.scan)
    ffi.copy(memory + find_any2, self.find_any2, #self.find_any2)
    ffi.copy(memory + find_any4, self.find_any4, #self.find_any4)
    ffi.copy(memory + count_byte, self.count_byte, #self.count_byte)
    ffi.copy(memory + all_equal, self.all_equal, #self.all_equal)
    ffi.copy(memory + zip_add, self.zip_add, #self.zip_add)
    ffi.copy(memory + zip_multiply, self.zip_multiply, #self.zip_multiply)
    ffi.copy(memory + zip, self.zip, #self.zip)
    ffi.copy(memory + f32, self.f32, #self.f32)
    ffi.copy(memory + u64, self.u64, #self.u64)
    assert(ffi.C.mprotect(memory, size, 5) == 0, "negative-space mprotect RX failed")
    local owned = ffi.gc(memory, function(pointer) ffi.C.munmap(pointer, size) end)
    return setmetatable({
        memory = owned, size = size, gcc = self.gcc,
        reduction = ffi.cast("F64ReductionV1Entry", owned + reduction),
        min_number = ffi.cast("F64ReductionV1Entry", owned + min_number),
        max_number = ffi.cast("F64ReductionV1Entry", owned + max_number),
        scan = ffi.cast("U8ScanV1Entry", owned + scan),
        find_any2 = ffi.cast("U8ScanSetV1Entry", owned + find_any2),
        find_any4 = ffi.cast("U8ScanSetV1Entry", owned + find_any4),
        count_byte = ffi.cast("U8ScanSetV1Entry", owned + count_byte),
        all_equal = ffi.cast("U8ScanSetV1Entry", owned + all_equal),
        zip_add = ffi.cast("F64ZipMapV1Entry", owned + zip_add),
        zip_multiply = ffi.cast("F64ZipMapV1Entry", owned + zip_multiply),
        zip = ffi.cast("F64ZipMapV1Entry", owned + zip),
        f32 = ffi.cast("F32MapPipelineV1Entry", owned + f32),
        u64 = ffi.cast("U64BulkV1Entry", owned + u64),
    }, Suite)
end

local function live(suite)
    assert(suite.memory ~= false, "negative-space V1 suite was released")
end

function Suite:run_reduction(frame) live(self); self.reduction(frame) end
function Suite:run_min_number(frame) live(self); self.min_number(frame) end
function Suite:run_max_number(frame) live(self); self.max_number(frame) end
function Suite:run_scan(frame) live(self); self.scan(frame) end
function Suite:run_find_any2(frame) live(self); self.find_any2(frame) end
function Suite:run_find_any4(frame) live(self); self.find_any4(frame) end
function Suite:run_count_byte(frame) live(self); self.count_byte(frame) end
function Suite:run_all_equal(frame) live(self); self.all_equal(frame) end
function Suite:run_zip_add(frame) live(self); self.zip_add(frame) end
function Suite:run_zip_multiply(frame) live(self); self.zip_multiply(frame) end
function Suite:run_zip(frame) live(self); self.zip(frame) end
function Suite:run_f32(frame) live(self); self.f32(frame) end
function Suite:run_u64(frame) live(self); self.u64(frame) end
function Suite:free()
    if self.memory == false then return end
    local memory = self.memory; ffi.gc(memory, nil); ffi.C.munmap(memory, self.size)
    self.memory = false
    self.reduction, self.min_number, self.max_number, self.scan = false, false, false, false
    self.find_any2, self.find_any4, self.count_byte, self.all_equal = false, false, false, false
    self.zip_add, self.zip_multiply, self.zip = false, false, false
    self.f32, self.u64 = false, false
end
return { ffi = ffi, Bank = new_bank }
