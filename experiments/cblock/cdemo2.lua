local C = require("cblock")

local csrc, errors = C.compile(function()
    local clamp = region(i32, i32, i32, cont(i32))(function(x, lo, hi)
        return if_(lt(x, lo), lo, if_(gt(x, hi), hi, x))
    end)

    local fib
    fib = func(i32, ret(i32))(function(n)
        return if_(lt(n, 2), n, fib(n - 1) + fib(n - 2))
    end)

    local max3 = func(f64, f64, f64, ret(f64))(function(a, b, c)
        local ab = if_(lt(a, b), b, a)
        return if_(lt(ab, c), c, ab)
    end)

    local demo = func(i32, i32, ret(i32))(function(x, y)
        local largest = if_(lt(x, y), y, x)
        local bounded = clamp(largest, 10, 100)
        return if_(eq(y, 0), -1, bounded + x / y)
    end)

    local clamp_called = func(i32, ret(i32))(function(x)
        return call(clamp)(x, 10, 100)
    end)

    -- alternatives belong to regions; funcs consume them into one ret
    local checked_div = region(i32, i32, cont(i32), cont())
        (function(a, d, ok, zero)
            return if_(eq(d, 0), zero(), ok(a / d))
        end)

    local divide = func(i32, i32, ret(i32))(function(a, d, ret)
        local on_value = function(q) return ret(q) end
        local on_zero  = function() return ret(-1) end
        return checked_div(a, d)(on_value, on_zero)
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
