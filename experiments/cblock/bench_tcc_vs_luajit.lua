local ffi = require("ffi")
local C = require("cblock")

local module, runtime = assert(C.jit(function()
    local Machine = struct {
        field: input (i64),
        field: limit (i64),
        field: value (i64),
        field: transitions (i64),
        field: checksum (i64),
    }

    Machine: classify (
        cont: halted (Machine), cont: even (Machine), cont: odd (Machine)
    )(function(p, c)
            local self = p.self
            local halted, even, odd = c.halted, c.even, c.odd
            return if_(eq(self.value, 1), halted(self),
                if_(eq(self.value % 2, 0), even(self), odd(self)))
        end)

    Machine: execute_even () (Machine) (function(p)
        local self = p.self
        return Machine {
            input = self.input,
            limit = self.limit,
            value = self.value / 2,
            transitions = self.transitions + 1,
            checksum = self.checksum,
        }
    end)

    Machine: execute_odd () (Machine) (function(p)
        local self = p.self
        return Machine {
            input = self.input,
            limit = self.limit,
            value = self.value * 3 + 1,
            transitions = self.transitions + 1,
            checksum = self.checksum,
        }
    end)

    Machine: next_input () (Machine) (function(p)
        local self = p.self
        local next = self.input + 1
        return Machine {
            input = next,
            limit = self.limit,
            value = next,
            transitions = 0,
            checksum = self.checksum + self.transitions,
        }
    end)

    local checksum = region(
        param: limit (i64),
        cont: done (i64),
        cont: trapped ()
    )
        (function(p, c)
            local limit = p.limit
            local done, trapped = c.done, c.trapped
            local dispatch, execute_even, execute_odd, advance

        dispatch = block(Machine)(function(machine)
            return machine:classify() {
                halted = advance, even = execute_even, odd = execute_odd,
            }
        end)

        execute_even = block(Machine)(function(machine)
            return dispatch(machine:execute_even())
        end)

        execute_odd = block(Machine)(function(machine)
            return dispatch(machine:execute_odd())
        end)

        advance = block(Machine)(function(machine)
            local next = machine:next_input()
            return if_(gt(next.input, next.limit), done(next.checksum), dispatch(next))
        end)

        return dispatch(Machine {
            input = 1,
            limit = limit,
            value = 1,
            transitions = 0,
            checksum = 0,
        })
    end)

    local saxpy = func
        (param: dst (ptr(f64)), param: xs (ptr(f64)), param: ys (ptr(f64)),
         param: count (i64), param: a (f64))
        (void)
        (function(p)
            local each = range(0, p.count)
            return zip(each:load(p.xs), each:load(p.ys)):map(function(x, y)
                return p.a * x + y
            end):store(p.dst)
        end)

    local checksum_fn = call(checksum)

    return {
        hailstone = { Machine = Machine, checksum = checksum_fn },
        numeric = { saxpy = saxpy },
    }
end))

local function lua_checksum(limit)
    local checksum = 0
    for input = 1, limit do
        local value = input
        local transitions = 0
        while value ~= 1 do
            if value % 2 == 0 then
                value = value / 2
            else
                value = value * 3 + 1
            end
            transitions = transitions + 1
        end
        checksum = checksum + transitions
    end
    return checksum
end

local function milliseconds(seconds) return seconds * 1000.0 end
local function median(samples)
    table.sort(samples)
    return samples[math.floor(#samples / 2) + 1]
end

local function measure(operation, rounds)
    local samples, result = {}
    for i = 1, rounds do
        collectgarbage("collect")
        local begin = os.clock()
        result = operation()
        samples[i] = os.clock() - begin
    end
    return median(samples), result, samples
end

local limit = tonumber(arg[1]) or 250000
local rounds = tonumber(arg[2]) or 5

-- Cook with a trivial invocation so compile latency is not conflated with a full run.
local begin = os.clock()
local cook_exit, cook_checksum = module.hailstone.checksum(1)
local cook_elapsed = os.clock() - begin
assert(cook_exit == "done" and tonumber(cook_checksum) == 0)

-- Warm LuaJIT until the hot loops have compiled before measuring them.
local warm_limit = math.min(limit, 100000)
local warm_expected
for _ = 1, 3 do warm_expected = lua_checksum(warm_limit) end
assert(warm_expected > 0)

local tcc_elapsed, tcc_checksum = measure(function()
    local exit, value = module.hailstone.checksum(limit)
    assert(exit == "done")
    return tonumber(value)
end, rounds)

local lua_elapsed, lua_result = measure(function()
    return lua_checksum(limit)
end, rounds)

assert(tcc_checksum == lua_result,
    ("checksum mismatch: TCC=%s LuaJIT=%s"):format(tcc_checksum, lua_result))

local transitions = lua_result
local function rate(elapsed) return transitions / elapsed / 1000000.0 end

print("CBlock/TCC vs LuaJIT — Hailstone machine population")
local jit_enabled = jit and select(1, jit.status())
print(("  LuaJIT:       %s"):format(jit_enabled and "enabled" or "disabled"))
print(("  inputs:       %d"):format(limit))
print(("  transitions:  %d"):format(transitions))
print(("  rounds:       %d (median CPU time)"):format(rounds))
print(("  lazy cook:    %8.3f ms  (compile + relocate + resolve)"):format(milliseconds(cook_elapsed)))
print(("  CBlock/TCC:   %8.3f ms  %8.1f M transitions/s"):format(
    milliseconds(tcc_elapsed), rate(tcc_elapsed)))
print(("  LuaJIT:       %8.3f ms  %8.1f M transitions/s"):format(
    milliseconds(lua_elapsed), rate(lua_elapsed)))
print(("  TCC/LuaJIT:   %8.3fx time"):format(tcc_elapsed / lua_elapsed))

local count = 1024 * 1024
local xs = ffi.new("double[?]", count)
local ys = ffi.new("double[?]", count)
local tcc_dst = ffi.new("double[?]", count)
local lua_dst = ffi.new("double[?]", count)
for i = 0, count - 1 do
    xs[i], ys[i] = i * 0.25, i * 0.5
end

local function lua_saxpy(dst, left, right, n, a)
    for i = 0, n - 1 do dst[i] = a * left[i] + right[i] end
end

module.numeric.saxpy(tcc_dst, xs, ys, count, 1.5)
for _ = 1, 3 do lua_saxpy(lua_dst, xs, ys, count, 1.5) end

local kernel_rounds = math.max(rounds, 9)
local tcc_kernel_elapsed = measure(function()
    module.numeric.saxpy(tcc_dst, xs, ys, count, 1.5)
    return tcc_dst[count - 1]
end, kernel_rounds)
local lua_kernel_elapsed = measure(function()
    lua_saxpy(lua_dst, xs, ys, count, 1.5)
    return lua_dst[count - 1]
end, kernel_rounds)
assert(tcc_dst[count - 1] == lua_dst[count - 1])

local bytes = count * 8 * 3
local function bandwidth(elapsed) return bytes / elapsed / 1000000000.0 end
print("")
print("Fused SAXPY over LuaJIT FFI arrays")
print(("  elements:     %d"):format(count))
print(("  rounds:       %d (median CPU time)"):format(kernel_rounds))
print(("  CBlock/TCC:   %8.3f ms  %8.2f GB/s"):format(
    milliseconds(tcc_kernel_elapsed), bandwidth(tcc_kernel_elapsed)))
print(("  LuaJIT:       %8.3f ms  %8.2f GB/s"):format(
    milliseconds(lua_kernel_elapsed), bandwidth(lua_kernel_elapsed)))
print(("  TCC/LuaJIT:   %8.3fx time"):format(
    tcc_kernel_elapsed / lua_kernel_elapsed))
module:free()
