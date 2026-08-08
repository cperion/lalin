package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local now = require("lalin.luajit_measure").now
local State = require("experiments.gccjit_driver.machine")

local shape = arg[1] or "blocks"
local iterations = tonumber(arg[2]) or 11
local optimization = tonumber(arg[3]) or 3
assert(shape == "blocks" or shape == "tail", "shape must be blocks or tail")

local compile_samples = {}
local driver_samples = {}
local total_samples = {}
for index = 1, iterations do
    collectgarbage("collect")
    local driver = State.Driver()
    local started = now()
    if shape == "blocks" then driver:cook_blocks(optimization) else driver:cook_tail(optimization) end
    local total = now() - started
    assert(driver:succeeded(), driver:diagnostic_text())
    total_samples[index] = total * 1000000
    compile_samples[index] = tonumber(driver.metrics.compile_ns) / 1000
    driver_samples[index] = tonumber(driver.metrics.acquire_ns + driver.metrics.type_ns
        + driver.metrics.graph_ns + driver.metrics.lookup_ns) / 1000
    local runtime = State.RuntimeStateArray()
    runtime[0].limit = 1000
    assert(driver:invoke(runtime) == 332833500)
    driver:free()
end

table.sort(total_samples)
table.sort(compile_samples)
table.sort(driver_samples)
local middle = math.floor((iterations + 1) / 2)

local driver = State.Driver()
if shape == "blocks" then driver:cook_blocks(optimization) else driver:cook_tail(optimization) end
assert(driver:succeeded(), driver:diagnostic_text())
local entry = driver:entrypoint()
local runtime = State.RuntimeStateArray()
local calls = 1000000
local started = now()
for index = 1, calls do
    runtime[0].cursor, runtime[0].limit, runtime[0].accumulator = 0, 100, 0
    entry(runtime)
end
local invocation_ns = (now() - started) * 1000000000 / calls

local native_steps = 2000000
local native_samples = {}
for index = 1, iterations do
    runtime[0].cursor, runtime[0].limit, runtime[0].accumulator = 0, native_steps, 0
    started = now()
    entry(runtime)
    native_samples[index] = (now() - started) * 1000000000 / native_steps
    assert(runtime[0].cursor == native_steps)
end
table.sort(native_samples)
driver:free()

print(("shape=%s opt=%d samples=%d total_us=%.3f compile_us=%.3f driver_us=%.3f "
    .. "invoke100_ns=%.3f native_ns_per_step=%.3f"):format(
    shape, optimization, iterations, total_samples[middle], compile_samples[middle],
    driver_samples[middle], invocation_ns, native_samples[middle]))
