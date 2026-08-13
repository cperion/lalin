local C = require("cblock")

local csrc, errors = C.compile(function()
    local choose = region(i32, cont(i32))(function(x)
        -- chained conditional: if_(cond):then_(v):else_(v)
        return if_(gt(x, 0)):then_(10):else_(20)
    end)

    local checked_div = region(i32, i32, cont(i32), cont())
        (function(a, d, ok, zero)
            return if_(eq(d, 0), zero(), ok(a / d))
        end)

    local emitted = func(i32, ret(i32))(function(x) return choose(x) end)
    local called = func(i32, ret(i32))(function(x) return call(choose)(x) end)
    local chain = func(i32, ret(i32))(function(x)
        return if_(gt(x, 0)):then_(10):else_(20)
    end)

    -- alternatives belong to regions; funcs consume them into one ret
    local divide_emit = func(i32, i32, ret(i32))(function(a, d, ret)
        local on_value = function(q) return ret(q) end
        local on_zero  = function() return ret(-1) end
        return checked_div(a, d)(on_value, on_zero)
    end)
    local divide_call = func(i32, i32, ret(i32))(function(a, d, ret)
        local on_value = function(q) return ret(q) end
        local on_zero  = function() return ret(-1) end
        return call(checked_div)(a, d)(on_value, on_zero)
    end)

    local api = {
        choice = { emit = emitted, call = called, chain = chain },
        div_emit = divide_emit, div_call = divide_call,
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
    if (choice_call(1) != 10 || choice_call(0) != 20) return 2;
    if (choice_chain(1) != 10 || choice_chain(0) != 20) return 7;
    if (div_emit(8, 2) != 4 || div_emit(8, 0) != -1) return 3;
    if (div_call(8, 2) != 4 || div_call(8, 0) != -1) return 4;
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

print("cblock direct values + plural exits: ok")
