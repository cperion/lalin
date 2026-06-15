package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local moon = require("moonlift")

local ok_clock = pcall(function()
    ffi.cdef[[
        typedef long time_t;
        struct timespec { time_t tv_sec; long tv_nsec; };
        int clock_gettime(int clk_id, struct timespec *tp);
    ]]
end)
local CLOCK_MONOTONIC = 1
local ts = ok_clock and ffi.new("struct timespec[1]") or nil

local function now()
    if ok_clock and ffi.C.clock_gettime(CLOCK_MONOTONIC, ts) == 0 then
        return tonumber(ts[0].tv_sec) + tonumber(ts[0].tv_nsec) * 1e-9
    end
    return os.clock()
end

local function getenv_number(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    return assert(tonumber(v), "bad numeric env " .. name .. "=" .. tostring(v))
end

local function getenv_string(name, default)
    local v = os.getenv(name)
    if v == nil or v == "" then return default end
    return v
end

local mode = arg and arg[1] or "quick"
local quick = mode ~= "full"
local optimized_shared_cflags = "-std=c99 -O3 -fPIC -shared -Wl,-z,noexecstack"

local cfg = {
    mode = mode,
    inner_n = getenv_number("MOONLIFT_BENCH_BACKEND_INNER_N", quick and 10000 or 50000),
    runtime_calls = getenv_number("MOONLIFT_BENCH_BACKEND_RUNTIME_CALLS", quick and 500 or 1000),
    runtime_warmups = getenv_number("MOONLIFT_BENCH_BACKEND_RUNTIME_WARMUPS", quick and 3 or 8),
    runtime_samples = getenv_number("MOONLIFT_BENCH_BACKEND_RUNTIME_SAMPLES", quick and 7 or 15),
    compile_reps = getenv_number("MOONLIFT_BENCH_BACKEND_COMPILE_REPS", quick and 3 or 10),
    c_runner = getenv_string("MOONLIFT_BENCH_C_RUNNER", "both"),
    c_compiler = getenv_string("MOONLIFT_BENCH_C_CC", getenv_string("MOONLIFT_C_CC", "cc")),
    cflags = os.getenv("MOONLIFT_BENCH_CFLAGS"),
}

local function c_variants()
    if cfg.c_runner == "both" then
        return {
            {
                key = "c_libtcc",
                label = "c/libtcc",
                runner = "libtcc",
                cc = cfg.c_compiler,
                cflags = nil,
                note = "default JIT C path / compile-smoke; not a runtime optimizer",
            },
            {
                key = "c_shared_o3",
                label = "c/shared-O3",
                runner = "shared",
                cc = cfg.c_compiler,
                cflags = cfg.cflags or optimized_shared_cflags,
                note = "optimized C performance reference",
            },
        }
    end
    return {
        {
            key = "c",
            label = "c/" .. cfg.c_runner,
            runner = cfg.c_runner,
            cc = cfg.c_compiler,
            cflags = cfg.cflags or (cfg.c_runner == "shared" and optimized_shared_cflags or nil),
            note = (cfg.c_runner == "libtcc" or cfg.c_runner == "tcc") and "default JIT C path / compile-smoke; not a runtime optimizer" or "selected C runner",
        },
    }
end

local BACKENDS = { { key = "cranelift", label = "cranelift", backend = "cranelift", runner = "cranelift" } }
for _, v in ipairs(c_variants()) do BACKENDS[#BACKENDS + 1] = v end

local function sorted_copy(xs)
    local out = {}
    for i = 1, #xs do out[i] = xs[i] end
    table.sort(out)
    return out
end

local function stats(xs)
    local s = sorted_copy(xs)
    local n = #s
    local sum = 0
    for i = 1, n do sum = sum + s[i] end
    return {
        min = s[1],
        median = (n % 2 == 1) and s[(n + 1) / 2] or ((s[n / 2] + s[n / 2 + 1]) * 0.5),
        max = s[n],
        mean = sum / n,
        samples = xs,
    }
end

local function fmt_ms(x) return x * 1000.0 end
local function fmt_us(x) return x * 1e6 end
local function fmt_ns(x) return x * 1e9 end

local function make_arrays(n)
    local a = ffi.new("int32_t[?]", n + 16)
    local b = ffi.new("int32_t[?]", n + 16)
    local out = ffi.new("int32_t[?]", n + 16)
    for i = 0, n + 15 do
        a[i] = (i * 17 + 3) % 2048 - 1024
        b[i] = (i * 31 + 7) % 2048 - 1024
        out[i] = 0
    end
    return a, b, out
end

local CASES = {
    {
        name = "sum_loop",
        work = function() return cfg.inner_n end,
        src = [[func bench_sum_loop(n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + i)
    end
end]],
        args = function() return cfg.inner_n end,
    },
    {
        name = "ptr_sum",
        work = function() return cfg.inner_n end,
        src = [[func bench_ptr_sum(p: ptr(i32), n: i32) -> i32
    return block loop(i: i32 = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + p[i])
    end
end]],
        setup = function(arrays) return arrays.a end,
        args = function(a) return a, cfg.inner_n end,
    },
    {
        name = "view_sum",
        work = function() return cfg.inner_n end,
        src = [[func bench_view_sum(p: ptr(i32), n: index) -> i32
    let v: view(i32) = view(p, n)
    return block loop(i: index = 0, acc: i32 = 0) -> i32
        if i >= n then yield acc end
        jump loop(i = i + 1, acc = acc + v[i])
    end
end]],
        setup = function(arrays) return arrays.b end,
        args = function(b) return b, cfg.inner_n end,
    },
    {
        name = "triad_store",
        work = function() return cfg.inner_n end,
        src = [[func bench_triad_store(out: ptr(i32), a: ptr(i32), b: ptr(i32), k: i32, n: i32) -> i32
    block loop(i: i32 = 0)
        if i >= n then return 0 end
        out[i] = a[i] + b[i] * k
        jump loop(i = i + 1)
    end
end]],
        setup = function(arrays) return arrays.out, arrays.a, arrays.b end,
        args = function(out, a, b) return out, a, b, 3, cfg.inner_n end,
        check = function(_, out) return tonumber(out[0] + out[cfg.inner_n - 1]) end,
    },
}

local function compile_callable(case, spec)
    local f = moon.func(case.src)
    local opts
    if spec.key == "cranelift" then
        opts = { backend = "cranelift" }
    else
        opts = { backend = "c", runner = spec.runner, cc = spec.cc, cflags = spec.cflags }
    end
    local compiled = f:compile(opts)
    return f, compiled
end

local function measure_compile(case, spec)
    local times = {}
    for i = 1, cfg.compile_reps do
        collectgarbage("collect")
        local t0 = now()
        local f, compiled = compile_callable(case, spec)
        times[i] = now() - t0
        if compiled and compiled.free then compiled:free() end
        f:free()
    end
    return stats(times)
end

local function measure_runtime(case, spec, arrays)
    collectgarbage("collect")
    local setup_values = case.setup and { case.setup(arrays) } or {}
    local f, compiled = compile_callable(case, spec)
    local args = { case.args(unpack(setup_values)) }
    local checksum = 0

    local function checked_call()
        local ret = tonumber(compiled(unpack(args)))
        if case.check then return case.check(ret, unpack(setup_values)) end
        return ret
    end

    for _ = 1, cfg.runtime_warmups do checksum = checksum + checked_call() end

    local times = {}
    for sample = 1, cfg.runtime_samples do
        local sample_sum = 0
        local t0 = now()
        for _ = 1, cfg.runtime_calls do sample_sum = sample_sum + checked_call() end
        times[sample] = now() - t0
        checksum = checksum + sample_sum
    end

    if compiled and compiled.free then compiled:free() end
    f:free()
    return stats(times), checksum
end

local function safe(fn)
    local ok, a, b = pcall(fn)
    if not ok then return nil, tostring(a) end
    return a, b
end

local function print_header()
    print(string.format(
        "moonlift backend benchmark mode=%s runtime_samples=%d runtime_calls=%d inner_n=%d compile_reps=%d c_runner=%s c_cc=%s cflags=%s",
        cfg.mode, cfg.runtime_samples, cfg.runtime_calls, cfg.inner_n, cfg.compile_reps,
        cfg.c_runner, cfg.c_compiler, tostring(cfg.cflags or "<runner default>")
    ))
    print("policy: default reports both C meanings: c/libtcc is the JIT C path; c/shared-O3 is the optimized-C performance reference")
    print("runtime: reports median/min over samples; us_per_call includes LuaJIT FFI call overhead; ns_per_item divides by inner loop work")
    print("compile: reports median/min full compile+load time for each backend")
    for _, spec in ipairs(BACKENDS) do
        if spec.note then print("backend-note " .. spec.label .. ": " .. spec.note) end
    end
    print("")
end

local exit_status = 0

local function report_case(case, results)
    print("case " .. case.name)
    for _, spec in ipairs(BACKENDS) do
        local r = results[spec.key]
        if r.err then
            print(string.format("  %-12s ERROR %s", spec.label, r.err))
        else
            local calls = cfg.runtime_calls
            local items = calls * case.work()
            print(string.format(
                "  %-12s compile_ms median=%9.3f min=%9.3f runtime_us_per_call median=%9.3f min=%9.3f ns_per_item median=%9.3f min=%9.3f checksum=%d",
                spec.label,
                fmt_ms(r.compile.median), fmt_ms(r.compile.min),
                fmt_us(r.runtime.median / calls), fmt_us(r.runtime.min / calls),
                fmt_ns(r.runtime.median / items), fmt_ns(r.runtime.min / items),
                r.checksum
            ))
            print(string.format(
                "RESULT case=%s backend=%s runner=%s compile_median_s=%.9f compile_min_s=%.9f runtime_median_s=%.9f runtime_min_s=%.9f calls=%d items=%d checksum=%d",
                case.name, spec.key, spec.runner,
                r.compile.median, r.compile.min, r.runtime.median, r.runtime.min, calls, items, r.checksum
            ))
        end
    end

    local cl = results.cranelift
    if cl and not cl.err then
        for _, spec in ipairs(BACKENDS) do
            if spec.key ~= "cranelift" then
                local r = results[spec.key]
                if r and not r.err then
                    if r.checksum ~= cl.checksum then
                        exit_status = 1
                        print(string.format("  INVALID checksum_mismatch backend=%s cranelift=%d other=%d", spec.key, cl.checksum, r.checksum))
                    else
                        print(string.format("  ratio_%s_vs_cranelift runtime_median=%.3f runtime_min=%.3f compile_median=%.3f",
                            spec.key,
                            r.runtime.median / cl.runtime.median,
                            r.runtime.min / cl.runtime.min,
                            r.compile.median / cl.compile.median))
                    end
                end
            end
        end
    end
    print("")
end

print_header()
local arrays = {}
arrays.a, arrays.b, arrays.out = make_arrays(cfg.inner_n)

for _, case in ipairs(CASES) do
    local results = {}
    for _, spec in ipairs(BACKENDS) do
        local compile_stats, compile_err = safe(function() return measure_compile(case, spec) end)
        if not compile_stats then
            results[spec.key] = { err = "compile: " .. tostring(compile_err) }
        else
            local runtime_stats, checksum_or_err = safe(function() return measure_runtime(case, spec, arrays) end)
            if not runtime_stats then
                results[spec.key] = { err = "runtime: " .. tostring(checksum_or_err), compile = compile_stats }
            else
                results[spec.key] = { compile = compile_stats, runtime = runtime_stats, checksum = checksum_or_err }
            end
        end
    end
    report_case(case, results)
end

if exit_status ~= 0 then os.exit(exit_status) end
