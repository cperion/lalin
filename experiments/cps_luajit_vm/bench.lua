local bit = require("bit")
local jit = require("jit")
local opt = require("jit.opt")

assert(jit.status(), "LuaJIT must be enabled for this performance experiment")

local N = tonumber(arg[1]) or 3000000
local SAMPLES = tonumber(arg[2]) or 5
local WARM_N = math.min(N, 200000)

opt.start("hotloop=20", "hotexit=2", "loopunroll=256")

local trace_totals = { start = 0, stop = 0, abort = 0 }
jit.attach(function(what)
    if trace_totals[what] ~= nil then
        trace_totals[what] = trace_totals[what] + 1
    end
end, "trace")

local function trace_snapshot()
    return {
        start = trace_totals.start,
        stop = trace_totals.stop,
        abort = trace_totals.abort,
    }
end

local function trace_delta(before)
    return trace_totals.stop - before.stop, trace_totals.abort - before.abort,
        trace_totals.start - before.start
end

local function median(values)
    local sorted = {}
    for i = 1, #values do sorted[i] = values[i] end
    table.sort(sorted)
    return sorted[math.floor((#sorted + 1) / 2)]
end

local function branch_oracle(n, mask)
    local acc = 0
    for i = 0, n - 1 do
        if bit.band(i, mask) == 0 then
            acc = acc + i
        else
            acc = acc - i
        end
    end
    return acc
end

local function call_oracle(n)
    local cycles = math.floor(n / 256)
    local remain = n - cycles * 256
    return cycles * 32640 + remain * (remain - 1) / 2
end

local function make_direct_branch(mask)
    local source = string.format([[
local bit = ...
return function(n)
    local acc = 0
    for i = 0, n - 1 do
        if bit.band(i, %d) == 0 then
            acc = acc + i
        else
            acc = acc - i
        end
    end
    return acc
end
    ]], mask)
    return assert(loadstring(source, "@cps-core-direct-" .. mask))(bit)
end

local function make_cps_branch(mask)
    local source = string.format([[
local bit = ...
local Loop, Take, Skip
Loop = function(vm, i, n, acc)
    if i >= n then return acc end
    if bit.band(i, %d) == 0 then
        return Take(vm, i, n, acc)
    end
    return Skip(vm, i, n, acc)
end
Take = function(vm, i, n, acc)
    return Loop(vm, i + 1, n, acc + i)
end
Skip = function(vm, i, n, acc)
    return Loop(vm, i + 1, n, acc - i)
end
return function(n) return Loop(false, 0, n, 0) end
    ]], mask)
    return assert(loadstring(source, "@cps-core-args-" .. mask))(bit)
end

local function make_cps_vm(mask, escape)
    local source = string.format([[
local bit = ...
local escaped_state
local Loop, Take, Skip
Loop = function(vm)
    local i = vm.i
    if i >= vm.n then return vm.acc end
    if bit.band(i, %d) == 0 then return Take(vm) end
    return Skip(vm)
end
Take = function(vm)
    local i = vm.i
    vm.acc = vm.acc + i
    vm.i = i + 1
    return Loop(vm)
end
Skip = function(vm)
    local i = vm.i
    vm.acc = vm.acc - i
    vm.i = i + 1
    return Loop(vm)
end
return function(n)
    local vm = { i = 0, n = n, acc = 0 }
    if %s then escaped_state = vm end
    local result = Loop(vm)
    if %s then assert(escaped_state.acc == result) end
    return result
end
    ]], mask, tostring(escape), tostring(escape))
    return assert(loadstring(source,
        "@cps-core-vm-" .. mask .. "-" .. tostring(escape)))(bit)
end

local function inline_guest(n)
    local acc = 0
    for i = 0, n - 1 do
        acc = acc + bit.band(i, 255)
    end
    return acc
end

local function guest_step(i, acc)
    return acc + bit.band(i, 255)
end

local function host_call_guest(n)
    local acc = 0
    for i = 0, n - 1 do
        acc = guest_step(i, acc)
    end
    return acc
end

local FixedLoop, FixedGuest, FixedResume
FixedLoop = function(vm, i, n, acc)
    if i >= n then return acc end
    return FixedGuest(vm, i, n, acc)
end
FixedGuest = function(vm, i, n, acc)
    return FixedResume(vm, i, n, acc + bit.band(i, 255))
end
FixedResume = function(vm, i, n, acc)
    return FixedLoop(vm, i + 1, n, acc)
end

local function fixed_cps_guest(n)
    return FixedLoop(false, 0, n, 0)
end

local DynamicLoop, DynamicGuest, DynamicResume
DynamicLoop = function(vm, i, n, acc)
    if i >= n then return acc end
    return DynamicGuest(vm, i, n, acc, DynamicResume)
end
DynamicGuest = function(vm, i, n, acc, returned)
    return returned(vm, i, n, acc + bit.band(i, 255))
end
DynamicResume = function(vm, i, n, acc)
    return DynamicLoop(vm, i + 1, n, acc)
end

local function continuation_cps_guest(n)
    return DynamicLoop(false, 0, n, 0)
end

local CASE_IDS = {
    "branch-1-direct", "branch-1-cps",
    "branch-15-direct", "branch-15-cps",
    "branch-1023-direct", "branch-1023-cps",
    "state-cps", "state-vm-local", "state-vm-escaped",
    "call-inline", "call-host", "call-fixed", "call-continuation",
}

local ONLY = arg[3]

if not ONLY then
    print(string.format("LuaJIT: %s %s/%s", jit.version, jit.arch, jit.os))
    print(string.format(
        "iterations=%d samples=%d warmup=%d loopunroll=256; each row is a fresh process",
        N, SAMPLES, WARM_N))
    print(string.format("%-14s %-18s %11s %11s %8s",
        "family", "variant", "median ns", "best ns", "traces S/A"))
    for _, case_id in ipairs(CASE_IDS) do
        local command = string.format("luajit %q %d %d %q",
            arg[0], N, SAMPLES, case_id)
        local pipe = assert(io.popen(command))
        local result_line
        for line in pipe:lines() do
            if line:sub(1, 7) == "RESULT\t" then result_line = line:sub(8) end
        end
        pipe:close()
        assert(result_line, "child benchmark failed: " .. case_id)
        print(result_line)
    end
    os.exit(0)
end

local rows = {}

local function benchmark(family, name, fn, warm_expected, expected)
    jit.flush()
    collectgarbage("collect")
    local before = trace_snapshot()
    local got
    for _ = 1, 3 do got = fn(WARM_N) end
    assert(got == warm_expected, name .. " warmup result mismatch")
    local stops, aborts, starts = trace_delta(before)

    local times = {}
    for sample = 1, SAMPLES do
        collectgarbage("collect")
        local t0 = os.clock()
        got = fn(N)
        times[sample] = os.clock() - t0
        assert(got == expected, name .. " result mismatch")
    end

    local best = math.huge
    for i = 1, #times do best = math.min(best, times[i]) end
    rows[#rows + 1] = {
        family = family, name = name,
        median_ns = median(times) * 1e9 / N,
        best_ns = best * 1e9 / N,
        starts = starts, stops = stops, aborts = aborts,
    }
end

local function selected(case_id)
    return ONLY == case_id
end

local masks = { 1, 15, 1023 }
for _, mask in ipairs(masks) do
    local direct_id = "branch-" .. mask .. "-direct"
    local cps_id = "branch-" .. mask .. "-cps"
    if selected(direct_id) or selected(cps_id) then
        local warm_expected = branch_oracle(WARM_N, mask)
        local expected = branch_oracle(N, mask)
        local family = "branch/" .. tostring(mask)
        if selected(direct_id) then
            benchmark(family, "direct", make_direct_branch(mask), warm_expected, expected)
        else
            benchmark(family, "cps args", make_cps_branch(mask), warm_expected, expected)
        end
    end
end

if ONLY:sub(1, 6) == "state-" then
    local mask = 15
    local warm_expected = branch_oracle(WARM_N, mask)
    local expected = branch_oracle(N, mask)
    if selected("state-cps") then
        benchmark("state/15", "cps args", make_cps_branch(mask), warm_expected, expected)
    elseif selected("state-vm-local") then
        benchmark("state/15", "vm local", make_cps_vm(mask, false), warm_expected, expected)
    elseif selected("state-vm-escaped") then
        benchmark("state/15", "vm escaped", make_cps_vm(mask, true), warm_expected, expected)
    end
end

if ONLY:sub(1, 5) == "call-" then
    local warm_expected = call_oracle(WARM_N)
    local expected = call_oracle(N)
    if selected("call-inline") then
        benchmark("guest-call", "inline loop", inline_guest, warm_expected, expected)
    elseif selected("call-host") then
        benchmark("guest-call", "host call/return", host_call_guest, warm_expected, expected)
    elseif selected("call-fixed") then
        benchmark("guest-call", "fixed CPS edge", fixed_cps_guest, warm_expected, expected)
    elseif selected("call-continuation") then
        benchmark("guest-call", "continuation arg", continuation_cps_guest, warm_expected, expected)
    end
end

assert(#rows == 1, "unknown benchmark case: " .. tostring(ONLY))
local row = rows[1]
print("RESULT\t" .. string.format("%-14s %-18s %11.3f %11.3f %3d/%-3d",
    row.family, row.name, row.median_ns, row.best_ns, row.stops, row.aborts))

