package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local now = require("lalin.luajit_measure").now
local State = require("experiments.gccjit_driver.tail_bridge_machine")

local calls = tonumber(arg[1]) or 1000000
local driver = State.Driver()
driver:cook(3)
assert(driver:succeeded(), driver:diagnostic_text())

local runtime = State.RuntimeStateArray()
local started = now()
for index = 1, calls do
    runtime[0].cursor, runtime[0].limit, runtime[0].accumulator = 0, 100, 0
    driver:turn(runtime)
end
local tail_entry_ns = (now() - started) * 1000000000 / calls

local entry = driver.owner.entry
started = now()
for index = 1, calls do
    runtime[0].cursor, runtime[0].limit, runtime[0].accumulator = 0, 100, 0
    entry(runtime)
end
local direct_entry_ns = (now() - started) * 1000000000 / calls

local callback_calls = 0
local callback = ffi.cast("TailBridgeV1_Callback", function(state)
    callback_calls = callback_calls + 1
    return state[0].accumulator
end)
local callback_iterations = math.max(10000, math.floor(calls / 10))
started = now()
for index = 1, callback_iterations do
    driver:callback_turn(runtime, callback)
end
local callback_ns = (now() - started) * 1000000000 / callback_iterations
assert(callback_calls == callback_iterations)

callback:free()
driver:free()
print(("calls=%d tail_entry_ns=%.3f direct_entry_ns=%.3f terminal_callback_ns=%.3f"):format(
    calls, tail_entry_ns, direct_entry_ns, callback_ns))
