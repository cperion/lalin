package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local vmdef = require("jit.vmdef")
local util = require("jit.util")
local Conventions = require("experiments.cdef_schema.call_conventions")

local shape = arg[1] or "explicit"
local depth = tonumber(arg[2]) or 8
local cycles = tonumber(arg[3]) or 10000
local samples = tonumber(arg[4]) or 5
local loopunroll = tonumber(arg[5]) or 1000

assert(shape == "tail" or shape == "host" or shape == "explicit"
    or shape == "suspended", "shape must be tail, host, explicit, or suspended")
assert(cycles >= 1 and samples >= 1)
jit.opt.start("hotloop=10", "hotexit=2", "loopunroll=" .. loopunroll)

local machines = Conventions.build(depth)
local machine = machines[shape == "suspended" and "explicit" or shape]
local trace = { starts = 0, stops = 0, aborts = 0, reasons = {} }

local function on_trace(what, _tr, _fn, _pc, error_code)
    if what == "start" then trace.starts = trace.starts + 1
    elseif what == "stop" then trace.stops = trace.stops + 1
    elseif what == "abort" then
        trace.aborts = trace.aborts + 1
        local reason = vmdef.traceerr[error_code] or tostring(error_code)
        trace.reasons[reason] = (trace.reasons[reason] or 0) + 1
    end
end

local function run_once()
    if shape == "tail" then
        return tonumber(machine.run(cycles))
    elseif shape == "host" then
        local enters, unwinds = machine.run(cycles)
        return tonumber(enters) + tonumber(unwinds)
    elseif shape == "explicit" then
        return tonumber(machine.run(cycles)) * 2
    else
        machine.start_suspended(cycles)
        local result
        for _ = 1, cycles do result = machine.resume() end
        return tonumber(result) * 2
    end
end

jit.flush()
jit.attach(on_trace, "trace")
for _ = 1, 3 do run_once() end

local execution = "jit"
if trace.aborts > 100 and trace.aborts > trace.stops * 10 then
    -- Stop pathological retry storms after the diagnostic warmup. Correctness
    -- remains identical; the report still preserves all warmup abort reasons.
    jit.off()
    execution = "interpreter"
end

local times = {}
local transitions = 0
collectgarbage(); collectgarbage(); collectgarbage("stop")
local heap_before = collectgarbage("count")
for sample = 1, samples do
    local started = os.clock()
    transitions = run_once()
    times[sample] = os.clock() - started
end
local heap_growth = collectgarbage("count") - heap_before
collectgarbage("restart")
jit.attach(on_trace)

table.sort(times)
local elapsed = times[math.floor((#times + 1) / 2)]
local trace_count, loop_count, nins = 0, 0, 0
for trace_number = 1, 10000 do
    local info = util.traceinfo(trace_number)
    if info == nil then break end
    trace_count = trace_count + 1
    nins = nins + (info.nins or 0)
    if info.linktype == "loop" or info.linktype == "tail-recursion"
        or info.linktype == "up-recursion" or info.linktype == "down-recursion"
        or info.link == trace_number then loop_count = loop_count + 1 end
end

local reasons = {}
for reason, count in pairs(trace.reasons) do reasons[#reasons + 1] = reason .. ":" .. count end
table.sort(reasons)

print(("shape=%s depth=%d cycles=%d loopunroll=%d execution=%s transitions=%d median_ms=%.3f ns_per_transition=%.3f heap_kb=%.3f"):format(
    shape, depth, cycles, loopunroll, execution, transitions, elapsed * 1000,
    elapsed * 1e9 / transitions, heap_growth))
print(("traces=%d loops=%d nins=%d starts=%d stops=%d aborts=%d reasons=%s"):format(
    trace_count, loop_count, nins, trace.starts, trace.stops, trace.aborts,
    #reasons == 0 and "none" or table.concat(reasons, ",")))

