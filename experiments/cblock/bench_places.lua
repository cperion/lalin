local C = require("cblock")

-- Do places/let make TCC code faster? Two targeted workloads where the
-- mechanism should actually matter:
--   1) wide struct churn : immutable rebuilds an 8-field state every step,
--      mutable stores fields in place.
--   2) let reuse inside one hot C loop : a shared subexpression used 4x.

local loops = tonumber(arg[1]) or 4000000
local rounds = tonumber(arg[2]) or 7

local immutable, runtime_i = C.jit(function()
    local State = struct {
        field: a (f64), field: b (f64), field: c (f64), field: d (f64),
        field: e (f64), field: f (f64), field: g (f64), field: h (f64),
    }
    local run = region(
        cont: done (f64),
        cont: trapped ()
    )
        (function(p, c)
            local done, trapped = c.done, c.trapped
            local dispatch
        dispatch = block(State)(function(s)
            local next = State {
                a = s.a + 1.0, b = s.b + 1.0, c = s.c + 1.0, d = s.d + 1.0,
                e = s.e + 1.0, f = s.f + 1.0, g = s.g + 1.0, h = s.h + 1.0,
            }
            return if_(lt(s.a, 4000000), dispatch(next),
                done(s.a + s.b + s.c + s.d
                    + s.e + s.f + s.g + s.h))
        end)
        return dispatch(State {
            a = 0, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0 })
    end)
    local run_fn = call(run)
    return { machine = { run = run_fn } }
end)

local mutable, runtime_m = C.jit(function()
    local State = struct {
        field: a (f64), field: b (f64), field: c (f64), field: d (f64),
        field: e (f64), field: f (f64), field: g (f64), field: h (f64),
    }
    local run = region(
        cont: done (f64),
        cont: trapped ()
    )
        (function(p, c)
            local done, trapped = c.done, c.trapped
            local frame = var(State, State {
            a = 0, b = 0, c = 0, d = 0, e = 0, f = 0, g = 0, h = 0 })
        local dispatch
        dispatch = block()(function()
            return if_(lt(load(frame).a, 4000000),
                seq(
                    store(frame.a, load(frame).a + 1.0),
                    store(frame.b, load(frame).b + 1.0),
                    store(frame.c, load(frame).c + 1.0),
                    store(frame.d, load(frame).d + 1.0),
                    store(frame.e, load(frame).e + 1.0),
                    store(frame.f, load(frame).f + 1.0),
                    store(frame.g, load(frame).g + 1.0),
                    store(frame.h, load(frame).h + 1.0),
                    dispatch()),
                done(load(frame).a + load(frame).b + load(frame).c + load(frame).d
                    + load(frame).e + load(frame).f + load(frame).g + load(frame).h))
        end)
        return dispatch()
    end)
    local run_fn = call(run)
    return { machine = { run = run_fn } }
end)

-- let reuse inside one hot C loop
local plain, runtime_p = C.jit(function()
    local f = region(
        param: n (i64),
        cont: done (i64),
        cont: trapped ()
    )
        (function(p, c)
            local n = p.n
            local done, trapped = c.done, c.trapped
            local dispatch
        dispatch = block(i64, i64)(function(i, acc)
            local x = i * 3 + 1
            local y = i * 3 + 2
            local z = i * 3 + 3
            local w = i * 3 + 4
            return if_(lt(i, n), dispatch(i + 1, acc + x + y + z + w),
                done(acc))
        end)
        return dispatch(0, 0)
    end)
    local f_fn = call(f)
    return { machine = { f = f_fn } }
end)
local bound, runtime_b = C.jit(function()
    local f = region(
        param: n (i64),
        cont: done (i64),
        cont: trapped ()
    )
        (function(p, c)
            local n = p.n
            local done, trapped = c.done, c.trapped
            local dispatch
        dispatch = block(i64, i64)(function(i, acc)
            local base = let(i * 3)
            return if_(lt(i, n),
                dispatch(i + 1, acc + base + 1 + base + 2 + base + 3 + base + 4),
                done(acc))
        end)
        return dispatch(0, 0)
    end)
    local f_fn = call(f)
    return { machine = { f = f_fn } }
end)

local function median(samples)
    table.sort(samples)
    return samples[math.floor(#samples / 2) + 1]
end
local function measure(fn, n)
    local samples = {}
    for i = 1, n do
        collectgarbage("collect")
        local t0 = os.clock()
        local value = fn()
        samples[i] = os.clock() - t0
    end
    return median(samples)
end

local _, vi = immutable.machine.run()
local _, vm = mutable.machine.run()
assert(tonumber(vi) == tonumber(vm))
local _, pv = plain.machine.f(1000)
local _, bv = bound.machine.f(1000)
assert(tonumber(pv) == tonumber(bv))

local t_imm = measure(function()
    local exit, v = immutable.machine.run()
    assert(exit == "done" and tonumber(v) == 32000000)
    return v
end, rounds)
local t_mut = measure(function()
    local exit, v = mutable.machine.run()
    assert(exit == "done" and tonumber(v) == 32000000)
    return v
end, rounds)

local t_plain = measure(function()
    local exit, v = plain.machine.f(loops)
    assert(exit == "done")
    return v
end, rounds)
local t_bound = measure(function()
    local exit, v = bound.machine.f(loops)
    assert(exit == "done")
    return v
end, rounds)

local function ms(t) return t * 1000.0 end
print("TCC wide-struct churn: immutable rebuild vs in-place mutation")
print(("  iterations:   %d"):format(4000000))
print(("  immutable:    %8.3f ms"):format(ms(t_imm)))
print(("  mutable:      %8.3f ms"):format(ms(t_mut)))
print(("  speedup:      %8.2fx"):format(t_imm / t_mut))
print("")
print("TCC let reuse inside hot loop")
print(("  iterations:   %d"):format(loops))
print(("  plain (4x):   %8.3f ms"):format(ms(t_plain)))
print(("  let:          %8.3f ms"):format(ms(t_bound)))
print(("  speedup:      %8.2fx"):format(t_plain / t_bound))

immutable:free()
mutable:free()
plain:free()
bound:free()
