package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Runtime = require("experiments.copy_patch_cps.lua55_trace.recorder")
local Emitter = require("experiments.copy_patch_cps.lua55_trace.emitter")
local Exotype = require("experiments.lua55.cps_exotype_codegen")
local T = Runtime.Trace
local bank = dofile("target/copy_patch_cps/lua55_trace/bank.lua")

local count = tonumber(arg[1]) or 1000
local iterations = tonumber(arg[2]) or 10000
local samples = tonumber(arg[3]) or 7
local function reg(index) return T.RegisterIdentity(index) end
local function pc(value) return T.InstructionIdentity(value) end

local sum, limit, step, index = reg(0), reg(1), reg(2), reg(3)
local plan = T.IntegerAddForLoopPlan(
    4, pc(10), pc(10), pc(11), pc(11), sum, index, limit, step, 12)
local frame = Runtime.FrameOwner.new(4)
    :set_integer(0, 0):set_integer(1, count):set_integer(2, 1):set_integer(3, 1)
local recorder = Runtime.Recorder.new_plan(plan, frame, Emitter.NativeArena.new(bank, 4096))
local outcome = recorder:record_plan()
assert(T.TraceRecorded:is(outcome))
local native = recorder.native

local exotype_root = Exotype.loadfile("experiments/lua55/sample_5.5.luac")
local exotype_sum = exotype_root()

local function lua_sum()
    local value = 0
    for item = 1, count do value = value + item end
    return value
end
local expected = lua_sum()

local function native_sum()
    frame.values[0].payload.integer = 0
    frame.values[3].payload.integer = 1
    native:execute(frame.frame)
    return frame.values[0].payload.integer
end
assert(tonumber(native_sum()) == expected)

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end
local function measure(action)
    local values = {}
    for sample = 1, samples do
        local started = os.clock()
        local result
        for _ = 1, iterations do result = action() end
        assert(tonumber(result) == expected)
        values[sample] = os.clock() - started
    end
    return median(values)
end

local native_seconds = measure(native_sum)
local exotype_seconds = measure(function() return exotype_sum(count) end)
local lua_seconds = measure(lua_sum)
local guest_iterations = count * iterations
print(("Lua55 trace count=%d calls=%d code=%d record=%d"):format(
    count, iterations, native.size, recorder.code_cursor))
print(("fused trace  %8.3f ns/guest code=%d"):format(
    native_seconds * 1e9 / guest_iterations, native.size))
print(("exotype Lua %8.3f ns/guest ratio=%.2fx"):format(
    exotype_seconds * 1e9 / guest_iterations, exotype_seconds / native_seconds))
print(("Lua baseline %8.3f ns/guest ratio=%.2fx"):format(
    lua_seconds * 1e9 / guest_iterations, lua_seconds / native_seconds))
native:free()
