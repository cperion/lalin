local bit = require("bit")
local jit = require("jit")
local opt = require("jit.opt")
local codegen = require("experiments.cps_luajit_vm.codegen")

assert(jit.status(), "LuaJIT must be enabled for this performance experiment")

local MAX_DIAMONDS = tonumber(arg[1]) or 16
local TARGET_BRANCHES = tonumber(arg[2]) or 1000000
local SAMPLES = tonumber(arg[3]) or 3
local LOOPUNROLL = tonumber(arg[4]) or 512

opt.start("hotloop=20", "hotexit=2", "loopunroll=" .. tostring(LOOPUNROLL))

local trace_totals = { start = 0, stop = 0, abort = 0 }
jit.attach(function(what)
    if trace_totals[what] ~= nil then
        trace_totals[what] = trace_totals[what] + 1
    end
end, "trace")

local function trace_snapshot()
    return { start = trace_totals.start, stop = trace_totals.stop, abort = trace_totals.abort }
end

local function trace_delta(before)
    return trace_totals.stop - before.stop, trace_totals.abort - before.abort
end

local function median(values)
    local sorted = {}
    for i = 1, #values do sorted[i] = values[i] end
    table.sort(sorted)
    return sorted[math.floor((#sorted + 1) / 2)]
end

local function make_direct(diamonds)
    return codegen.instantiate(codegen.emit_direct(diamonds),
        "@cps-scale-direct-" .. diamonds, bit)
end

local function make_cps(diamonds)
    return codegen.instantiate(codegen.emit_cps(diamonds),
        "@cps-scale-cps-" .. diamonds, bit)
end

local function time_one(fn, n, expected)
    jit.flush()
    collectgarbage("collect")
    local before = trace_snapshot()
    local warm_n = math.min(n, 20000)
    local warm_result
    for _ = 1, 3 do warm_result = fn(warm_n) end
    local stops, aborts = trace_delta(before)

    local times = {}
    local result
    for sample = 1, SAMPLES do
        collectgarbage("collect")
        local t0 = os.clock()
        result = fn(n)
        times[sample] = os.clock() - t0
        if expected ~= nil then assert(result == expected, "result mismatch") end
    end
    return median(times), stops, aborts, result, warm_result
end

local scales = { 1, 2, 4, 8, 16, 24, 32, 48, 64 }
print(string.format("LuaJIT: %s %s/%s", jit.version, jit.arch, jit.os))
print(string.format("target branches=%d samples=%d loopunroll=%d",
    TARGET_BRANCHES, SAMPLES, LOOPUNROLL))
print(string.format("%-8s %-10s %11s %11s %9s %8s",
    "diamonds", "blocks/cyc", "direct ns", "CPS ns", "CPS/direct", "traces"))

for _, diamonds in ipairs(scales) do
    if diamonds <= MAX_DIAMONDS then
        local n = math.max(20000, math.floor(TARGET_BRANCHES / diamonds))
        local branches = n * diamonds
        local direct = make_direct(diamonds)
        local cps = make_cps(diamonds)
        local direct_time, _, _, expected = time_one(direct, n)
        local cps_time, stops, aborts = time_one(cps, n, expected)
        local direct_ns = direct_time * 1e9 / branches
        local cps_ns = cps_time * 1e9 / branches
        print(string.format("%-8d %-10d %11.3f %11.3f %9.3f %3d/%-3d",
            diamonds, 1 + 2 * diamonds, direct_ns, cps_ns, cps_ns / direct_ns,
            stops, aborts))
    end
end

