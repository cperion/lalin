-- Benchmark equivalent loop kernels through GCC and Moonlift's current
-- MoonCode native pipeline. This stays on the public MoonCode/LowerToBack
-- path rather than any retired direct tree lowering path.

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local pvm = require("moonlift.pvm")
local A = require("moonlift.asdl")

local Pipeline = require("moonlift.frontend_pipeline")
local Cranelift = require("moonlift.back_jit")

local mode = arg and arg[1] or nil
local quick = mode == "quick"
local N = tonumber(os.getenv("MOONLIFT_BENCH_N") or (quick and "262144" or "1048576"))
local STRIDE = tonumber(os.getenv("MOONLIFT_BENCH_STRIDE") or "2")
local ITERS = tonumber(os.getenv("MOONLIFT_BENCH_ITERS") or (quick and "3" or "5"))
local WARMUP = tonumber(os.getenv("MOONLIFT_BENCH_WARMUP") or (quick and "2" or "4"))

local CSRC = [[
int fib_i32(int n) {
    int a = 0, b = 1, i = 0, t = 0;
    while (i < n) { t = a; a = b; b = t + b; i++; }
    return a;
}
int sum_stride_i32(const int* xs, int n, int stride) {
    int acc = 0, i = 0;
    while (i < n) { acc += xs[i * stride]; i++; }
    return acc;
}
int dot_stride_i32(const int* a, const int* b, int n, int stride) {
    int acc = 0, i = 0;
    while (i < n) { acc += a[i * stride] * b[i * stride]; i++; }
    return acc;
}
int fill_stride_i32(int* dst, int n, int stride, int value) {
    int i = 0;
    while (i < n) { dst[i * stride] = value; i++; }
    return 0;
}
]]

local MLSRC = [[
func fib_i32(n: i32): i32
    return block loop(i: i32 = 0, a: i32 = 0, b: i32 = 1): i32
        if i >= n then yield a end
        jump loop(i = i + 1, a = b, b = a + b)
    end
end

func sum_stride_i32(xs: ptr(i32), n: i32, stride: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + xs[i * stride])
    end
end

func dot_stride_i32(a: ptr(i32), b: ptr(i32), n: i32, stride: i32): i32
    return block loop(i: i32 = 0, acc: i32 = 0): i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + a[i * stride] * b[i * stride])
    end
end

func fill_stride_i32(dst: ptr(i32), n: i32, stride: i32, value: i32): i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        dst[i * stride] = value
        jump loop(i = i + 1)
    end
end
]]

-- Compile with GCC
local function gcc_compile(csrc, soname)
    local cfile = os.tmpname() .. ".c"
    local f = io.open(cfile, "w"); f:write(csrc); f:close()
    local cmd = string.format("gcc -O3 -fPIC -shared -o %s -x c %s 2>&1", soname, cfile)
    local h = io.popen(cmd)
    local out = h:read("*a"); h:close()
    if #out > 0 then error("gcc: " .. out) end
    os.remove(cfile)
end

-- Build GCC .so
local gcc_so = os.tmpname() .. ".so"
local gcc_t0 = os.clock()
gcc_compile(CSRC, gcc_so)
local gcc_t = os.clock() - gcc_t0

-- Load GCC .so via FFI
ffi.cdef[[
int fib_i32(int n);
int sum_stride_i32(const int* xs, int n, int stride);
int dot_stride_i32(const int* a, const int* b, int n, int stride);
int fill_stride_i32(int* dst, int n, int stride, int value);
]]
local gcc_lib = ffi.load(gcc_so)

-- Build Moonlift C frontend
local T = pvm.context()
A.Define(T)
local Frontend = Pipeline.Define(T)
local cranelift_api = Cranelift.Define(T)
local B = T.MoonBack

local function moonlift_compile_src(src)
    local t0 = os.clock()
    local lowered = Frontend.parse_and_lower(src, { site = "bench_c_frontend_vs_gcc" })
    local program = lowered.program
    assert(#lowered.back_report.issues == 0, lowered.back_report.issues[1] and lowered.back_report.issues[1].message)
    local frontend_t = os.clock() - t0
    local compile_t0 = os.clock()
    local jit = cranelift_api.jit()
    local artifact = jit:compile(program)
    local compile_t = os.clock() - compile_t0
    return artifact, frontend_t, compile_t, program, jit
end

local ml_artifact, ml_frontend_t, ml_compile_t, ml_program, ml_jit = moonlift_compile_src(MLSRC)
local function mptr(name) return ml_artifact:getpointer(B.BackFuncId(name)) end
local ml = {
    fib_i32 = ffi.cast("int32_t (*)(int32_t)", mptr("fib_i32")),
    sum_stride_i32 = ffi.cast("int32_t (*)(const int32_t*, int32_t, int32_t)", mptr("sum_stride_i32")),
    dot_stride_i32 = ffi.cast("int32_t (*)(const int32_t*, const int32_t*, int32_t, int32_t)", mptr("dot_stride_i32")),
    fill_stride_i32 = ffi.cast("int32_t (*)(int32_t*, int32_t, int32_t, int32_t)", mptr("fill_stride_i32")),
}

-- Fill test arrays
local function fill_arrays(n, stride)
    local len = n * stride + 8
    local a = ffi.new("int32_t[?]", len)
    local b = ffi.new("int32_t[?]", len)
    local out = ffi.new("int32_t[?]", len)
    for i = 0, len - 1 do
        a[i] = ((i * 17 + 3) % 2048) - 1024
        b[i] = ((i * 31 + 7) % 2048) - 1024
        out[i] = 0
    end
    return a, b, out
end

local function best_of(fn)
    for _ = 1, WARMUP do fn() end
    local best = math.huge
    local check
    for _ = 1, ITERS do
        local t0 = os.clock()
        check = fn()
        local dt = os.clock() - t0
        if dt < best then best = dt end
    end
    return best, check
end

-- Correctness check
local a_small, b_small, out_small_g = fill_arrays(64, STRIDE)
local _, _, out_small_m = fill_arrays(64, STRIDE)
assert(gcc_lib.fib_i32(32) == ml.fib_i32(32),
       string.format("fib: gcc=%d ml=%d", gcc_lib.fib_i32(32), ml.fib_i32(32)))
assert(gcc_lib.sum_stride_i32(a_small, 64, STRIDE) == ml.sum_stride_i32(a_small, 64, STRIDE))
assert(gcc_lib.dot_stride_i32(a_small, b_small, 64, STRIDE) == ml.dot_stride_i32(a_small, b_small, 64, STRIDE))
gcc_lib.fill_stride_i32(out_small_g, 64, STRIDE, 9)
ml.fill_stride_i32(out_small_m, 64, STRIDE, 9)
assert(out_small_g[0] == out_small_m[0] and out_small_g[63*STRIDE] == out_small_m[63*STRIDE])

local a, b, out_g = fill_arrays(N, STRIDE)
local _, _, out_m = fill_arrays(N, STRIDE)

local cases = {
    { name="fib_i32",
      g=function() return gcc_lib.fib_i32(N) end,
      m=function() return ml.fib_i32(N) end },
    { name="sum_stride_i32",
      g=function() return gcc_lib.sum_stride_i32(a, N, STRIDE) end,
      m=function() return ml.sum_stride_i32(a, N, STRIDE) end },
    { name="dot_stride_i32",
      g=function() return gcc_lib.dot_stride_i32(a, b, N, STRIDE) end,
      m=function() return ml.dot_stride_i32(a, b, N, STRIDE) end },
    { name="fill_stride_i32",
      g=function() return gcc_lib.fill_stride_i32(out_g, N, STRIDE, 123) end,
      m=function() return ml.fill_stride_i32(out_m, N, STRIDE, 123) end,
      check=function() return out_g[0]+out_g[(N-1)*STRIDE], out_m[0]+out_m[(N-1)*STRIDE] end },
}

io.write("Moonlift source benchmark: MoonCode native pipeline vs GCC -O3\n")
io.write(string.format("C_source_bytes %d\n", #CSRC))
io.write(string.format("Moonlift_source_bytes %d\n", #MLSRC))
io.write(string.format("moonlift_back_cmds %d\n", #ml_program.cmds))
io.write(string.format("N %d\nSTRIDE %d\nITERS %d\nWARMUP %d\n\n", N, STRIDE, ITERS, WARMUP))
io.write("compile_seconds\n")
io.write(string.format("  gcc_O3_compile                  %.9f\n", gcc_t))
io.write(string.format("  moonlift_frontend_mooncode      %.9f\n", ml_frontend_t))
io.write(string.format("  moonlift_backend_compile        %.9f\n", ml_compile_t))
io.write(string.format("  moonlift_back_cmds              %d\n\n", #ml_program.cmds))

io.write(string.format("%-18s %12s %12s %12s %12s\n", "kernel", "gcc_O3_s", "moonlift_s", "ml/gcc", "check"))
for _, case in ipairs(cases) do
    local gt = best_of(case.g)
    local mt = best_of(case.m)
    local ck_g, ck_m
    if case.check then ck_g, ck_m = case.check() else ck_g, ck_m = case.g(), case.m() end
    local ok = ck_g == ck_m and tostring(ck_m) or ("MISMATCH " .. tostring(ck_g) .. "/" .. tostring(ck_m))
    io.write(string.format("%-18s %12.9f %12.9f %12.3f %12s\n", case.name, gt, mt, mt / gt, ok))
end

ml_artifact:free()
ml_jit:free()
os.remove(gcc_so)
