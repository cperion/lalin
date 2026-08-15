local C = require("cblock")

local csrc, errors = C.compile(function()
    local saxpy = region(
        param: dst (ptr(f64)),
        param: xs (ptr(f64)),
        param: ys (ptr(f64)),
        param: n (i64),
        param: a (f64)
    )(void)(function(p)
        local each = range(0, p.n)
        local values = zip(each:load(p.xs), each:load(p.ys)):map(function(x, y)
            return p.a * x + y
        end)
        return values:store(p.dst)
    end)

    local dot = region(
        param: xs (ptr(f64)),
        param: ys (ptr(f64)),
        param: n (i64)
    )(f64)(function(p)
        local each = range(0, p.n)
        local products = zip(each:load(p.xs), each:load(p.ys)):map(function(x, y)
            return x * y
        end)
        return products:reduce(add, 0.0)
    end)

    local run_saxpy = func
        (param: dst (ptr(f64)), param: xs (ptr(f64)), param: ys (ptr(f64)),
         param: n (i64), param: a (f64))
        (void)
        (function(p) return saxpy(p.dst, p.xs, p.ys, p.n, p.a) end)
    local dot_emit = func
        (param: xs (ptr(f64)), param: ys (ptr(f64)), param: n (i64))
        (f64)
        (function(p) return dot(p.xs, p.ys, p.n) end)
    local dot_call = func
        (param: xs (ptr(f64)), param: ys (ptr(f64)), param: n (i64))
        (f64)
        (function(p) return call(dot)(p.xs, p.ys, p.n) end)

    return { run_saxpy = run_saxpy, dot_emit = dot_emit, dot_call = dot_call }
end)

if not csrc then error(table.concat(errors, "\n")) end
assert(not csrc:find("map", 1, true))
assert(not csrc:find("zip", 1, true))

local base = os.tmpname()
os.remove(base)
local cpath, object, exe, report =
    base .. ".c", base .. ".o", base .. ".out", base .. ".vec"
local f = assert(io.open(cpath, "w"))
f:write(csrc)
f:close()

-- Compile the generated unit alone: any vectorization report must come from
-- CBlock's loops rather than from the test harness.
local vector_command =
    ("cc -O3 -ffast-math -fopt-info-vec-optimized=%s -c -o %s %s")
    :format(report, object, cpath)
local ok, why, code = os.execute(vector_command)
if not (ok == true or ok == 0) then
    error(("pipeline C compile failed: %s %s"):format(why, code))
end
local rf = io.open(report, "r")
local vectorized = rf and rf:read("*a") or ""
if rf then rf:close() end
assert(vectorized:find("vectorized", 1, true),
    "GCC did not report a vectorized CBlock loop\n" .. vectorized)

f = assert(io.open(cpath, "a"))
f:write([[

#include <math.h>
int main(void) {
    double xs[1024], ys[1024], dst[1024];
    for (int i = 0; i < 1024; ++i) { xs[i] = i; ys[i] = 2 * i; }
    run_saxpy(dst, xs, ys, 1024, 3.0);
    for (int i = 0; i < 1024; ++i)
        if (dst[i] != 5.0 * i) return 1;
    double a = dot_emit(xs, ys, 1024);
    double b = dot_call(xs, ys, 1024);
    if (fabs(a - b) > 1e-9 || a <= 0.0) return 2;
    return 0;
}
]])
f:close()

local run_command = ("cc -O3 -ffast-math -o %s %s && %s")
    :format(exe, cpath, exe)
ok, why, code = os.execute(run_command)
os.remove(cpath)
os.remove(object)
os.remove(exe)
os.remove(report)
assert(ok == true or ok == 0,
    ("pipeline execution failed: %s %s"):format(why, code))
print("cblock pipeline: fused and GCC-vectorizable")
