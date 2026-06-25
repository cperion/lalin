-- Benchmark non-scalar copy-patch MC stencils against hand-written GCC -O3 C.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("lalin.pvm")
local Schema = require("lalin.schema")
local Measure = require("lalin.luajit_measure")

local T = pvm.context()
Schema(T)

local Code = T.LalinCode
local C = T.LalinC
local Stencil = T.LalinStencil
local Ty = T.LalinType
local Plan = require("lalin.stencil_artifact_plan")(T)
local CopyPatchMC = require("lalin.copy_patch_mc")(T)

local mode = arg and arg[1] or "quick"
local full = mode == "full"
local n = tonumber(os.getenv("LALIN_LJ_NONSCALAR_BENCH_N") or (full and "1000000" or "120000"))
local samples = tonumber(os.getenv("LALIN_LJ_NONSCALAR_BENCH_SAMPLES") or (full and "5" or "3"))
local rounds = tonumber(os.getenv("LALIN_LJ_NONSCALAR_BENCH_ROUNDS") or (full and "3" or "2"))
local cc = os.getenv("LALIN_LJ_NONSCALAR_BENCH_CC") or os.getenv("CC") or "gcc"
local cflags = os.getenv("LALIN_LJ_NONSCALAR_BENCH_CFLAGS") or "-std=c99 -O3 -march=native"
local with_gcc = os.getenv("LALIN_LJ_NONSCALAR_BENCH_GCC") ~= "0"

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local function stencil_object_cflags()
    return cflags .. " -ffunction-sections -fno-pic -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -c"
end

local function compile_artifacts(artifacts, opts)
    opts = opts or {}
    opts.cc = opts.cc or cc
    opts.cflags = opts.cflags or stencil_object_cflags()
    local bank, bank_err, source = CopyPatchMC.build_mc_bank(artifacts, opts)
    if bank == nil then return nil, bank_err, source end
    local realization, realize_err = CopyPatchMC.realize_mc_artifacts(artifacts, {
        mc_bank = bank,
        preamble = opts.preamble,
        ffi_preamble = opts.ffi_preamble,
    })
    if realization == nil then return nil, realize_err, source end
    return { symbols = realization.symbols, source = source }, nil, source
end

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local ptr_i32 = Code.CodeTyDataPtr(i32)
local pair_ty = Code.CodeTyNamed("Demo", "Pair", Ty.TNamed(Ty.TypeRefGlobal("Demo", "Pair")))
local imported_pair_ty = Code.CodeTyImportedC(C.CTypeId("Host", "HostPair"))
local slice_i32 = Code.CodeTySlice(i32)
local view_i32 = Code.CodeTyView(i32)
local bytespan_ty = Code.CodeTyByteSpan

local artifacts = {
    ptr_copy = Plan.copy_array_artifact({ elem_ty = ptr_i32, step_num = 1 }),
    ptr_gather = Plan.gather_array_artifact({ elem_ty = ptr_i32, index_ty = i32, step_num = 1, noalias = true }),
    ptr_gather_u4 = Plan.gather_array_artifact({ elem_ty = ptr_i32, index_ty = i32, step_num = 1, unroll = 4, noalias = true }),
    ptr_gather_u8 = Plan.gather_array_artifact({ elem_ty = ptr_i32, index_ty = i32, step_num = 1, unroll = 8, noalias = true }),
    ptr_scatter = Plan.scatter_array_artifact({ elem_ty = ptr_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, noalias = true }),
    ptr_scatter_u4 = Plan.scatter_array_artifact({ elem_ty = ptr_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, unroll = 4, noalias = true }),
    ptr_scatter_u8 = Plan.scatter_array_artifact({ elem_ty = ptr_i32, index_ty = i32, conflicts = Stencil.StencilScatterUniqueIndices, step_num = 1, unroll = 8, noalias = true }),
    named_copy = Plan.copy_array_artifact({ elem_ty = pair_ty, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    named_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = pair_ty, result_ty = pair_ty, step_num = 1 }),
    imported_copy = Plan.copy_array_artifact({ elem_ty = imported_pair_ty, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    slice_copy = Plan.copy_array_artifact({ elem_ty = slice_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    slice_identity = Plan.map_array_artifact(Stencil.StencilUnaryIdentity, { elem_ty = slice_i32, result_ty = slice_i32, step_num = 1 }),
    view_copy = Plan.copy_array_artifact({ elem_ty = view_i32, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
    bytespan_copy = Plan.copy_array_artifact({ elem_ty = bytespan_ty, semantics = Stencil.StencilCopyMemMove, step_num = 1 }),
}

local artifact_list = {}
for _, artifact in pairs(artifacts) do artifact_list[#artifact_list + 1] = artifact end

local preamble = [[
typedef struct { int32_t left; int32_t right; } Demo_Pair;
typedef struct { int32_t left; int32_t right; } HostPair;
typedef HostPair Host_HostPair;
typedef struct { int32_t* data; intptr_t len; } ml_slice_CBackendScalar_ScalarI32;
typedef struct { int32_t* data; intptr_t len; intptr_t stride; } ml_view_CBackendScalar_ScalarI32;
typedef struct { uint8_t* data; intptr_t len; } ml_bytespan;
]]

ffi.cdef(preamble)

local build, err, src = compile_artifacts(artifact_list, {
    stem = "bench_luajit_stencil_nonscalar",
    preamble = preamble,
})
assert(build ~= nil, tostring(err) .. "\n" .. tostring(src))

local function sym(name)
    local artifact = assert(artifacts[name], name)
    return assert(build.symbols[artifact.symbol.text], artifact.symbol.text)
end

local ints = ffi.new("int32_t[?]", n + 8)
local ptrs = ffi.new("int32_t *[?]", n)
local ptr_out = ffi.new("int32_t *[?]", n)
local idx = ffi.new("int32_t[?]", n)
local pairs = ffi.new("Demo_Pair[?]", n)
local pair_out = ffi.new("Demo_Pair[?]", n)
local host_pairs = ffi.new("Host_HostPair[?]", n)
local host_out = ffi.new("Host_HostPair[?]", n)
local slices = ffi.new("ml_slice_CBackendScalar_ScalarI32[?]", n)
local slice_out = ffi.new("ml_slice_CBackendScalar_ScalarI32[?]", n)
local views = ffi.new("ml_view_CBackendScalar_ScalarI32[?]", n)
local view_out = ffi.new("ml_view_CBackendScalar_ScalarI32[?]", n)
local spans = ffi.new("ml_bytespan[?]", n)
local span_out = ffi.new("ml_bytespan[?]", n)
local bytes = ffi.new("uint8_t[?]", n + 8)

for i = 0, n - 1 do
    ints[i] = i
    ptrs[i] = ints + i
    idx[i] = n - 1 - i
    pairs[i].left, pairs[i].right = i, i * 3
    host_pairs[i].left, host_pairs[i].right = i + 7, i * 5
    slices[i].data, slices[i].len = ints + i, 1
    views[i].data, views[i].len, views[i].stride = ints + i, 1, 1
    bytes[i] = i % 251
    spans[i].data, spans[i].len = bytes + i, 1
end

local mid = math.floor(n / 2)
local function ptr_checksum(a) return tonumber(ffi.cast("intptr_t", a[mid] - ints)) end
local function pair_checksum(a) return tonumber(a[mid].left + a[mid].right) end
local function slice_checksum(a) return tonumber(a[mid].len + (a[mid].data - ints)) end
local function view_checksum(a) return tonumber(a[mid].len + a[mid].stride + (a[mid].data - ints)) end
local function span_checksum(a) return tonumber(a[mid].len + (a[mid].data - bytes)) end

local cases = {
    { name = "mc ptr_copy", fn = function() sym("ptr_copy")(ptr_out, ffi.cast("int32_t * const *", ptrs), 0, n); return ptr_checksum(ptr_out) end },
    { name = "mc ptr_gather", fn = function() sym("ptr_gather")(ptr_out, ffi.cast("int32_t * const *", ptrs), idx, 0, n); return ptr_checksum(ptr_out) end },
    { name = "mc ptr_gather_u4", fn = function() sym("ptr_gather_u4")(ptr_out, ffi.cast("int32_t * const *", ptrs), idx, 0, n); return ptr_checksum(ptr_out) end },
    { name = "mc ptr_gather_u8", fn = function() sym("ptr_gather_u8")(ptr_out, ffi.cast("int32_t * const *", ptrs), idx, 0, n); return ptr_checksum(ptr_out) end },
    { name = "mc ptr_scatter", fn = function() sym("ptr_scatter")(ptr_out, ffi.cast("int32_t * const *", ptrs), idx, 0, n); return ptr_checksum(ptr_out) end },
    { name = "mc ptr_scatter_u4", fn = function() sym("ptr_scatter_u4")(ptr_out, ffi.cast("int32_t * const *", ptrs), idx, 0, n); return ptr_checksum(ptr_out) end },
    { name = "mc ptr_scatter_u8", fn = function() sym("ptr_scatter_u8")(ptr_out, ffi.cast("int32_t * const *", ptrs), idx, 0, n); return ptr_checksum(ptr_out) end },
    { name = "mc named_copy", fn = function() sym("named_copy")(pair_out, pairs, 0, n); return pair_checksum(pair_out) end },
    { name = "mc named_identity", fn = function() sym("named_identity")(pair_out, pairs, 0, n); return pair_checksum(pair_out) end },
    { name = "mc imported_copy", fn = function() sym("imported_copy")(host_out, host_pairs, 0, n); return pair_checksum(host_out) end },
    { name = "mc slice_copy", fn = function() sym("slice_copy")(slice_out, slices, 0, n); return slice_checksum(slice_out) end },
    { name = "mc slice_identity", fn = function() sym("slice_identity")(slice_out, slices, 0, n); return slice_checksum(slice_out) end },
    { name = "mc view_copy", fn = function() sym("view_copy")(view_out, views, 0, n); return view_checksum(view_out) end },
    { name = "mc bytespan_copy", fn = function() sym("bytespan_copy")(span_out, spans, 0, n); return span_checksum(span_out) end },
}

print(string.format("LuaJIT non-scalar MC stencil benchmark mode=%s n=%d samples=%d rounds=%d", mode, n, samples, rounds))
for _, result in ipairs(Measure.measure(cases, {
    samples = samples,
    rounds = rounds,
    warmup = full and 4 or 2,
    jit_opts = { "hotloop=3", "hotexit=2" },
})) do print(Measure.format_result(result)) end

if with_gcc then
    os.execute("mkdir -p target/luajit_bench")
    local c_path = "target/luajit_bench/stencil_nonscalar_baseline.c"
    local exe_path = "target/luajit_bench/stencil_nonscalar_baseline"
    local c = [=[
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct { int32_t left; int32_t right; } Demo_Pair;
typedef struct { int32_t left; int32_t right; } Host_HostPair;
typedef struct { int32_t* data; intptr_t len; } ml_slice_CBackendScalar_ScalarI32;
typedef struct { int32_t* data; intptr_t len; intptr_t stride; } ml_view_CBackendScalar_ScalarI32;
typedef struct { uint8_t* data; intptr_t len; } ml_bytespan;

static double now_s(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
    return (double)clock() / (double)CLOCKS_PER_SEC;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da > db) - (da < db);
}

static intptr_t ptr_copy(int32_t **out, int32_t * const *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid] - xs[0];
}

static intptr_t ptr_gather(int32_t **out, int32_t * const *xs, const int32_t *idx, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[idx[i]];
    return out[mid] - xs[0];
}

static intptr_t ptr_scatter(int32_t **out, int32_t * const *xs, const int32_t *idx, int n, int mid) {
    for (int i = 0; i < n; i++) out[idx[i]] = xs[i];
    return out[mid] - xs[0];
}

static int32_t named_copy(Demo_Pair *out, const Demo_Pair *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid].left + out[mid].right;
}

static int32_t named_identity(Demo_Pair *out, const Demo_Pair *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid].left + out[mid].right;
}

static int32_t imported_copy(Host_HostPair *out, const Host_HostPair *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid].left + out[mid].right;
}

static intptr_t slice_copy(ml_slice_CBackendScalar_ScalarI32 *out, const ml_slice_CBackendScalar_ScalarI32 *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid].len + (out[mid].data - xs[0].data);
}

static intptr_t slice_identity(ml_slice_CBackendScalar_ScalarI32 *out, const ml_slice_CBackendScalar_ScalarI32 *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid].len + (out[mid].data - xs[0].data);
}

static intptr_t view_copy(ml_view_CBackendScalar_ScalarI32 *out, const ml_view_CBackendScalar_ScalarI32 *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid].len + out[mid].stride + (out[mid].data - xs[0].data);
}

static intptr_t bytespan_copy(ml_bytespan *out, const ml_bytespan *xs, int n, int mid) {
    for (int i = 0; i < n; i++) out[i] = xs[i];
    return out[mid].len + (out[mid].data - xs[0].data);
}

typedef intptr_t (*BenchFn)(void);
typedef struct { const char *name; BenchFn fn; } BenchCase;

static int n, mid;
static int32_t *ints;
static int32_t **ptrs;
static int32_t **ptr_out;
static int32_t *idx;
static Demo_Pair *pairs, *pair_out;
static Host_HostPair *host_pairs, *host_out;
static ml_slice_CBackendScalar_ScalarI32 *slices, *slice_out;
static ml_view_CBackendScalar_ScalarI32 *views, *view_out;
static ml_bytespan *spans, *span_out;
static uint8_t *bytes;

static intptr_t run_ptr_copy(void) { return ptr_copy(ptr_out, ptrs, n, mid); }
static intptr_t run_ptr_gather(void) { return ptr_gather(ptr_out, ptrs, idx, n, mid); }
static intptr_t run_ptr_scatter(void) { return ptr_scatter(ptr_out, ptrs, idx, n, mid); }
static intptr_t run_named_copy(void) { return named_copy(pair_out, pairs, n, mid); }
static intptr_t run_named_identity(void) { return named_identity(pair_out, pairs, n, mid); }
static intptr_t run_imported_copy(void) { return imported_copy(host_out, host_pairs, n, mid); }
static intptr_t run_slice_copy(void) { return slice_copy(slice_out, slices, n, mid); }
static intptr_t run_slice_identity(void) { return slice_identity(slice_out, slices, n, mid); }
static intptr_t run_view_copy(void) { return view_copy(view_out, views, n, mid); }
static intptr_t run_bytespan_copy(void) { return bytespan_copy(span_out, spans, n, mid); }

int main(int argc, char **argv) {
    n = argc > 1 ? atoi(argv[1]) : 120000;
    int samples = argc > 2 ? atoi(argv[2]) : 3;
    int rounds = argc > 3 ? atoi(argv[3]) : 2;
    mid = n / 2;
    ints = calloc((size_t)n + 8, sizeof(int32_t));
    ptrs = calloc((size_t)n, sizeof(int32_t*));
    ptr_out = calloc((size_t)n, sizeof(int32_t*));
    idx = calloc((size_t)n, sizeof(int32_t));
    pairs = calloc((size_t)n, sizeof(Demo_Pair));
    pair_out = calloc((size_t)n, sizeof(Demo_Pair));
    host_pairs = calloc((size_t)n, sizeof(Host_HostPair));
    host_out = calloc((size_t)n, sizeof(Host_HostPair));
    slices = calloc((size_t)n, sizeof(ml_slice_CBackendScalar_ScalarI32));
    slice_out = calloc((size_t)n, sizeof(ml_slice_CBackendScalar_ScalarI32));
    views = calloc((size_t)n, sizeof(ml_view_CBackendScalar_ScalarI32));
    view_out = calloc((size_t)n, sizeof(ml_view_CBackendScalar_ScalarI32));
    spans = calloc((size_t)n, sizeof(ml_bytespan));
    span_out = calloc((size_t)n, sizeof(ml_bytespan));
    bytes = calloc((size_t)n + 8, sizeof(uint8_t));
    double *times = calloc((size_t)samples, sizeof(double));
    if (!ints || !ptrs || !ptr_out || !idx || !pairs || !pair_out || !host_pairs || !host_out || !slices || !slice_out || !views || !view_out || !spans || !span_out || !bytes || !times) abort();
    for (int i = 0; i < n; i++) {
        ints[i] = i;
        ptrs[i] = ints + i;
        idx[i] = n - 1 - i;
        pairs[i].left = i; pairs[i].right = i * 3;
        host_pairs[i].left = i + 7; host_pairs[i].right = i * 5;
        slices[i].data = ints + i; slices[i].len = 1;
        views[i].data = ints + i; views[i].len = 1; views[i].stride = 1;
        bytes[i] = (uint8_t)(i % 251);
        spans[i].data = bytes + i; spans[i].len = 1;
    }
    BenchCase cases[] = {
        { "gcc ptr_copy", run_ptr_copy },
        { "gcc ptr_gather", run_ptr_gather },
        { "gcc ptr_scatter", run_ptr_scatter },
        { "gcc named_copy", run_named_copy },
        { "gcc named_identity", run_named_identity },
        { "gcc imported_copy", run_imported_copy },
        { "gcc slice_copy", run_slice_copy },
        { "gcc slice_identity", run_slice_identity },
        { "gcc view_copy", run_view_copy },
        { "gcc bytespan_copy", run_bytespan_copy },
    };
    int case_count = (int)(sizeof(cases) / sizeof(cases[0]));
    for (int ci = 0; ci < case_count; ci++) {
        intptr_t first = 0;
        for (int s = 0; s < samples; s++) {
            intptr_t value = 0;
            double t0 = now_s();
            for (int r = 0; r < rounds; r++) value = cases[ci].fn();
            times[s] = now_s() - t0;
            if (s == 0) first = value;
            if (value != first) abort();
        }
        qsort(times, (size_t)samples, sizeof(double), cmp_double);
        printf("%-28s median=%8.3fms result=%lld\n", cases[ci].name, times[samples / 2] * 1000.0, (long long)first);
    }
    return 0;
}
]=]
    write_file(c_path, c)
    local cmd = table.concat({ shell_quote(cc), cflags, shell_quote(c_path), "-o", shell_quote(exe_path) }, " ")
    local ok = os.execute(cmd)
    if ok == true or ok == 0 then
        local pipe = io.popen(table.concat({ shell_quote(exe_path), tostring(n), tostring(samples), tostring(rounds) }, " "), "r")
        if pipe ~= nil then
            io.write("\nGCC command: " .. cmd .. "\n")
            io.write(pipe:read("*a"))
            pipe:close()
        end
    else
        io.stderr:write("skipping GCC baseline; compile failed: " .. cmd .. "\n")
    end
end
