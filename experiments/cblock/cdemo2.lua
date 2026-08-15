local C = require("cblock")

local csrc, errors = C.compile(function()
    local clamp = region(
        param: x (i32),
        param: lo (i32),
        param: hi (i32)
    )(i32)(function(p)
        return if_(lt(p.x, p.lo), p.lo, if_(gt(p.x, p.hi), p.hi, p.x))
    end)

    local fib
    fib = func (param: n (i32)) (i32) (function(p)
        return if_(lt(p.n, 2), p.n, fib(p.n - 1) + fib(p.n - 2))
    end)

    local max3 = func
        (param: a (f64), param: b (f64), param: c (f64))
        (f64)
        (function(p)
            local ab = if_(lt(p.a, p.b), p.b, p.a)
            return if_(lt(ab, p.c), p.c, ab)
        end)

    local demo = func
        (param: x (i32), param: y (i32))
        (i32)
        (function(p)
            local largest = if_(lt(p.x, p.y), p.y, p.x)
            local bounded = clamp(largest, 10, 100)
            return if_(eq(p.y, 0), -1, bounded + p.x / p.y)
        end)

    local clamp_called = func (param: x (i32)) (i32)
        (function(p) return call(clamp)(p.x, 10, 100) end)

    -- alternatives belong to regions; funcs consume them into one return
    local checked_div = region(
        param: a (i32),
        param: d (i32),
        cont: divided (i32),
        cont: zero ()
    )(function(p, c)
        return if_(eq(p.d, 0), c:zero(), c:divided(p.a / p.d))
    end)

    local divide = func
        (param: a (i32), param: d (i32))
        (i32)
        (function(p, r)
            local on_value = function(q) return r(q) end
            local on_zero  = function() return r(-1) end
            return checked_div(p.a, p.d) { divided = on_value, zero = on_zero }
        end)

    return {
        fib = fib, max3 = max3, demo = demo,
        clamp_called = clamp_called, divide = divide,
    }
end)

if not csrc then error(table.concat(errors, "\n")) end

local f = assert(io.open("out.c", "w"))
f:write(csrc, [[

#include <stdio.h>
int main(void) {
    int32_t q = 0;
    printf("fib(25)      = %d\n", fib(25));
    printf("demo(7,3)    = %d\n", demo(7, 3));
    printf("demo(500,0)  = %d\n", demo(500, 0));
    printf("max3         = %g\n", max3(1.5, 9.25, 3.0));
    printf("clamp call   = %d\n", clamp_called(500));
    printf("checked div  = %d\n", divide(8, 2));
    printf("checked zero = %d\n", divide(8, 0));
    return 0;
}
]])
f:close()
assert(os.execute("cc -O2 -o out out.c && ./out"))
