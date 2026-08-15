local ffi = require("ffi")
local C = require("cblock")

ffi.cdef [[ typedef int32_t (*CBlockTestBinary)(int32_t, int32_t); ]]

local host_mul = ffi.cast("CBlockTestBinary", function(a, b) return a * b end)

local module, runtime = C.jit(function()
    local host_mul_decl = extern
        (param: a (i32), param: b (i32))
        (i32)

    local Pair = struct {
        field: left (i32),
        field: right (i32),
    }

    local add = func
        (param: a (i32), param: b (i32))
        (i32)
        (function(p) return p.a + p.b end)

    local host_twice = func
        (param: value (i32))
        (i32)
        (function(p) return host_mul_decl(p.value, 2) end)

    local swap = func
        (param: pair (Pair))
        (Pair)
        (function(p)
            return Pair { left = p.pair.right, right = p.pair.left }
        end)

    local checked_div = region(
        param: a (i32), param: b (i32),
        cont: divided (i32),
        cont: zero ()
    )(function(p, c)
        return if_(eq(p.b, 0), c:zero(), c:divided(p.a / p.b))
    end)
    -- export the sealed alternative protocol for host multi-exit calls
    local checked_div_fn = call(checked_div)

    return {
        host_mul = host_mul_decl,
        Pair = Pair,
        math = {
            add = add, host_twice = host_twice,
            swap = swap, checked_div = checked_div_fn,
        },
    }
end, { symbols = { host_mul = host_mul } })

assert(module, runtime)
assert(runtime.session == nil, "C.jit must be lazy")

assert(module.math.add(20, 22) == 42)
assert(module.math.add { a = 20, b = 22 } == 42)
assert(runtime.session ~= nil, "first func invocation must cook the module")
local cooked = runtime.session
assert(module.math.add(1, 2) == 3 and runtime.session == cooked)
assert(module.math.host_twice(21) == 42)

local pair = module.Pair { left = 10, right = 32 }
local swapped = module.math.swap(pair)
assert(swapped.left == 32 and swapped.right == 10)

local exit, quotient = module.math.checked_div(84, 2)
assert(exit == "divided" and quotient == 42)
exit, quotient = module.math.checked_div(84, 0)
assert(exit == "zero" and quotient == nil)

module:free()
host_mul:free()
print("cblock funcs: lazy first-call TCC + cached native invocation ok")
