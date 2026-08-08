package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local Runtime = require("experiments.copy_patch_cps.lua55_trace.recorder")
local Emitter = require("experiments.copy_patch_cps.lua55_trace.emitter")
local T = Runtime.Trace
local bank = dofile("target/copy_patch_cps/lua55_trace/bank.lua")
local function arena() return Emitter.NativeArena.new(bank, 4096) end

local function register(index) return T.RegisterIdentity(index) end
local function identity(pc) return T.InstructionIdentity(pc) end

local function fused_plan()
    local sum, limit, step, index = register(0), register(1), register(2), register(3)
    return T.IntegerAddForLoopPlan(
        4, identity(10), identity(10), identity(11), identity(11),
        sum, index, limit, step, 12)
end

do
    local plan = fused_plan()
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_integer(1, 3):set_integer(2, 1):set_integer(3, 1)
    local recorder = Runtime.Recorder.new_plan(plan, frame, arena())
    local outcome = recorder:record_plan()
    assert(T.TraceRecorded:is(outcome))
    assert(outcome.projection.plan == plan and outcome.projection.code_size == recorder.native.size)
    assert(recorder.native:permissions():sub(1, 3) == "r-x")
    recorder.native:execute(frame.frame)
    assert(tonumber(frame:integer(0)) == 6 and tonumber(frame:integer(3)) == 4)
    assert(frame.frame.resume_pc == 12)
    recorder.native:free()
end

do
    local plan = fused_plan()
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_integer(1, 0):set_integer(2, 1):set_integer(3, 1)
    local recorder = Runtime.Recorder.new_plan(plan, frame, arena())
    local outcome = recorder:record_plan()
    assert(T.TraceLoopCompleted:is(outcome))
    assert(outcome.exit_pc == 12)
    recorder.arena:free()
end

do
    local plan = fused_plan()
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_float(1, 3):set_integer(2, 1):set_integer(3, 1)
    local recorder = Runtime.Recorder.new_plan(plan, frame, arena())
    local outcome = recorder:record_plan()
    assert(T.TraceRecordingRejected:is(outcome))
    assert(T.UnsupportedInstruction:is(outcome.failure))
    recorder.arena:free()
end

do
    -- negative step: sum = 10 + 9 + ... + 1
    local plan = fused_plan()
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_integer(1, 1):set_integer(2, -1):set_integer(3, 10)
    local recorder = Runtime.Recorder.new_plan(plan, frame, arena())
    local outcome = recorder:record_plan()
    assert(T.TraceRecorded:is(outcome))
    recorder.native:execute(frame.frame)
    assert(tonumber(frame:integer(0)) == 55 and tonumber(frame:integer(3)) == 0)
    assert(frame.frame.resume_pc == 12)
    recorder.native:free()
end

do
    -- zero trip, negative step (init below limit): complete without recording
    local plan = fused_plan()
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_integer(1, 5):set_integer(2, -1):set_integer(3, 0)
    local recorder = Runtime.Recorder.new_plan(plan, frame, arena())
    local outcome = recorder:record_plan()
    assert(T.TraceLoopCompleted:is(outcome))
    recorder.arena:free()
end

do
    -- zero step rejects
    local plan = fused_plan()
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_integer(1, 3):set_integer(2, 0):set_integer(3, 1)
    local recorder = Runtime.Recorder.new_plan(plan, frame, arena())
    local outcome = recorder:record_plan()
    assert(T.TraceRecordingRejected:is(outcome))
    recorder.arena:free()
end

do
    -- runtime zero-trip guard: the installed residual completes without
    -- touching sum or index when a later execution is out of range.
    local plan = fused_plan()
    local frame = Runtime.FrameOwner.new(4)
        :set_integer(0, 0):set_integer(1, 3):set_integer(2, 1):set_integer(3, 1)
    local recorder = Runtime.Recorder.new_plan(plan, frame, arena())
    assert(T.TraceRecorded:is(recorder:record_plan()))
    recorder.native:execute(frame.frame)
    assert(tonumber(frame:integer(0)) == 6)
    -- now drive the same residual with an out-of-range initial index
    frame:set_integer(0, 0):set_integer(3, 5)
    recorder.native:execute(frame.frame)
    assert(tonumber(frame:integer(0)) == 0 and tonumber(frame:integer(3)) == 5)
    assert(frame.frame.resume_pc == 12)
    recorder.native:free()
end

print("Lua55 trace recorder: ok plan-owned record -> RX fused recurrence")
