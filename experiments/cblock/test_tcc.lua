local ffi = require("ffi")
local C = require("cblock")

ffi.cdef [[ typedef int32_t (*CBlockTestBinary)(int32_t, int32_t); ]]

local host_mul = ffi.cast("CBlockTestBinary", function(a, b) return a * b end)

local module, runtime = C.jit(function()
    local host_mul_decl = extern(i32, i32, ret(i32))

    local Pair = struct {
        field: left (i32),
        field: right (i32),
    }

    local add = func(i32, i32, ret(i32))(function(a, b)
        return a + b
    end)

    local host_twice = func(i32, ret(i32))(function(value)
        return host_mul_decl(value, 2)
    end)

    local swap = func(Pair, ret(Pair))(function(pair)
        return Pair { left = pair.right, right = pair.left }
    end)

    local checked_div = region(i32, i32, cont(i32), cont())
        (function(a, b, divided, zero)
            return if_(eq(b, 0), zero(), divided(a / b))
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
assert(runtime.session ~= nil, "first func invocation must cook the module")
local cooked = runtime.session
assert(module.math.add(1, 2) == 3 and runtime.session == cooked)
assert(module.math.host_twice(21) == 42)

local pair = module.Pair { left = 10, right = 32 }
local swapped = module.math.swap(pair)
assert(swapped.left == 32 and swapped.right == 10)

local exit, quotient = module.math.checked_div(84, 2)
assert(exit == 1 and quotient == 42)
exit, quotient = module.math.checked_div(84, 0)
assert(exit == 2 and quotient == nil)

module:free()
host_mul:free()
print("cblock funcs: lazy first-call TCC + cached native invocation ok")
