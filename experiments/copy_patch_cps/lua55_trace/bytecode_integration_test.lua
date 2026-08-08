package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Undump = require("experiments.lua55.undump55")
local Exotype = require("experiments.lua55.cps_exotype_codegen")
local Program = require("experiments.copy_patch_cps.lua55_trace.program")
local Projection = require("experiments.copy_patch_cps.lua55_trace.bytecode_projection")
local Runtime = require("experiments.copy_patch_cps.lua55_trace.recorder")
local Emitter = require("experiments.copy_patch_cps.lua55_trace.emitter")
local Model = require("experiments.copy_patch_cps.lua55_trace.model")

local path = "experiments/lua55/sample_5.5.luac"
local file = assert(io.open(path, "rb")); local bytes = file:read("*a"); file:close()
local prototype = Undump.undump(bytes)
local integer_child = assert(prototype.protos[1])
local plan = Projection.project(integer_child, 4)

assert(plan.body.pc == 5 and plan.companion.pc == 6 and plan.forloop.pc == 7)
assert(plan.sum.index == 1 and plan.limit.index == 2)
assert(plan.step.index == 3 and plan.index.index == 4 and plan.exit_pc == 8)

local count = 10000
local frame = plan:new_positive_frame(0, 1, count, 1)
local bank = dofile("target/copy_patch_cps/lua55_trace/bank.lua")
local recorder = Runtime.Recorder.new_plan(
    plan, frame, Emitter.NativeArena.new(bank, 4096))
local outcome = recorder:record_plan()
assert(Model.TraceRecorded:is(outcome))
assert(outcome.projection.plan == plan and recorder.native.size == 160)
recorder.native:execute(frame.frame)

local expected = count * (count + 1) / 2
assert(tonumber(frame:integer(plan.sum.index)) == expected)
assert(frame.frame.resume_pc == plan.exit_pc)

local root = Exotype.load(bytes, "@lua55_trace_bytecode")
local sum_function = root()
assert(sum_function(count) == expected)

recorder.native:free()

local installed = Program.load(bytes, 1, 4, bank)
for _, limit in ipairs({ 10, 100, 1000 }) do
    assert(installed:call(limit) == sum_function(limit))
end
assert(installed.recordings == 1 and installed.native:permissions():sub(1, 3) == "r-x")
installed:free()
assert(not pcall(function() installed:call(10) end))

print("Lua55 bytecode trace: ok decoded FORPREP plan -> stable fused RX recurrence")
