local C = require("cblock")

local csrc, errors = C.compile(function()
    local choose = region(
        param: x (i32)
    )(i32)(function(p)
        local x = p.x
        -- chained conditional: if_(cond):then_(v):else_(v)
        return if_(gt(x, 0)):then_(10):else_(20)
    end)

    local checked_div = region(
        param: a (i32),
        param: d (i32),
        cont: divided (i32),
        cont: zero ()
    )(function(p, c)
        return if_(eq(p.d, 0), c:zero(), c:divided(p.a / p.d))
    end)

    -- A named protocol forwards without wrapper closures. Sealing the outer
    -- region proves that c.name survives inline wiring into a real frame.
    local forwarded_div = region(
        param: a (i32),
        param: d (i32),
        cont: divided (i32),
        cont: zero ()
    )(function(p, c)
        return checked_div(p.a, p.d) {
            divided = c.divided,
            zero = c.zero,
        }
    end)

    local emitted = func
        (param: x (i32))
        (i32)
        (function(p) return choose(p.x) end)
    local named = func
        (param: x (i32))
        (i32)
        (function(p) return choose { x = p.x } end)
    local called = func
        (param: x (i32))
        (i32)
        (function(p) return call(choose) { x = p.x } end)
    local chain = func
        (param: x (i32))
        (i32)
        (function(p)
            return if_(gt(p.x, 0)):then_(10):else_(20)
        end)

    -- alternatives belong to regions; funcs consume them into one return
    local divide_emit = func
        (param: a (i32), param: d (i32))
        (i32)
        (function(p, r)
            local on_value = function(q) return r(q) end
            local on_zero  = function() return r(-1) end
            return checked_div { a = p.a, d = p.d } {
                divided = on_value, zero = on_zero,
            }
        end)
    local divide_call = func
        (param: a (i32), param: d (i32))
        (i32)
        (function(p, r)
            local on_value = function(q) return r(q) end
            local on_zero  = function() return r(-1) end
            return call(checked_div) { a = p.a, d = p.d } {
                divided = on_value, zero = on_zero,
            }
        end)
    local divide_forward = func
        (param: a (i32), param: d (i32))
        (i32)
        (function(p, r)
            return call(forwarded_div)(p.a, p.d) {
                divided = function(q) return r(q) end,
                zero = function() return r(-1) end,
            }
        end)

    local api = {
        choice = { emit = emitted, named = named, call = called, chain = chain },
        div_emit = divide_emit, div_call = divide_call,
        div_forward = divide_forward,
    }
    assert(api.choice.emit == emitted, "Lua table must own the declaration")
    return api
end)

if not csrc then error(table.concat(errors, "\n")) end
assert(csrc:find("static ", 1, true))

local base = os.tmpname()
os.remove(base)
local cpath, exe = base .. ".c", base .. ".out"
local f = assert(io.open(cpath, "w"))
f:write(csrc, [[

int main(void) {
    int32_t out = 0;
    if (choice_emit(1) != 10 || choice_emit(0) != 20) return 1;
    if (choice_named(1) != 10 || choice_named(0) != 20) return 8;
    if (choice_call(1) != 10 || choice_call(0) != 20) return 2;
    if (choice_chain(1) != 10 || choice_chain(0) != 20) return 7;
    if (div_emit(8, 2) != 4 || div_emit(8, 0) != -1) return 3;
    if (div_call(8, 2) != 4 || div_call(8, 0) != -1) return 4;
    if (div_forward(8, 2) != 4 || div_forward(8, 0) != -1) return 5;
    return 0;
}
]])
f:close()
local ok, why, code = os.execute(("cc -O2 -o %s %s && %s"):format(exe, cpath, exe))
os.remove(cpath) os.remove(exe)
assert(ok == true or ok == 0, ("surface test failed: %s %s"):format(why, code))

assert(csrc:find("choice_emit", 1, true))
assert(not csrc:find("cblock_func_", 1, true),
    "generated construction names must not leak into exported C names")


print("cblock direct values + named exit protocols: ok")
