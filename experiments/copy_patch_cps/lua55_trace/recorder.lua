local ffi = require("ffi")
local T = require("experiments.copy_patch_cps.lua55_trace.model")
local Emitter = require("experiments.copy_patch_cps.lua55_trace.emitter")


local TAG_INTEGER, TAG_FLOAT = 1, 2
local LEARNED_BACKEDGE, LEARNED_COMPLETED, LEARNED_REJECTED = 1, 2, 3

local function integer(frame, register)
    local value = frame.values[register.index]
    if value.tag ~= TAG_INTEGER then return false end
    return value.payload.integer
end

local function floating(frame, register)
    local value = frame.values[register.index]
    if value.tag ~= TAG_FLOAT then return false end
    return value.payload.floating
end

local function store_integer(frame, register, value)
    local target = frame.values[register.index]
    target.tag = TAG_INTEGER
    target.payload.integer = value
end

local function store_float(frame, register, value)
    local target = frame.values[register.index]
    target.tag = TAG_FLOAT
    target.payload.floating = value
end

local Recorder = {}
Recorder.__index = Recorder

function Recorder.new_plan(plan, frame_owner, arena)
    assert(arena, "Lua55 trace recorder requires an emission arena")
    return setmetatable({
        plan = plan, frame_owner = frame_owner, frame = frame_owner.frame,
        arena = arena, code_cursor = 0, native = false,
    }, Recorder)
end

-- Recording is native: the C learner executes the first fused backedge and
-- writes learned = backedge | completed | rejected into the frame. Lua only
-- links the residual quotation for the backedge case.
function Recorder:record_plan()
    local plan = self.plan
    local offset = self.arena:append_learn_integer_add_forloop(plan)
    local learner = self.arena:seal_complete(offset)
    learner:execute(self.frame)
    local learned = tonumber(self.frame.learned)
    if learned == LEARNED_BACKEDGE then
        local residual_arena = Emitter.NativeArena.new(self.arena.bank, self.arena.capacity)
        local roffset, rsize = residual_arena:append_integer_add_forloop_plan(plan)
        self.native = residual_arena:seal_complete(roffset)
        self.code_cursor = rsize
        learner:free()
        return T.TraceRecorded(T.PlanTraceProjection(plan, self.native.size))
    end
    learner:free()
    if learned == LEARNED_COMPLETED then
        return T.TraceLoopCompleted(plan.exit_pc)
    end
    return T.TraceRecordingRejected(T.UnsupportedInstruction(plan.forloop))
end

local FrameOwner = {}
FrameOwner.__index = FrameOwner

function FrameOwner.new(count, generation)
    local values = ffi.new("Lua55TraceNumericValueV1[?]", count)
    local frame = ffi.new("Lua55TraceNumericFrameV1", {
        values, count, 0, 0, generation or 1, 0,
    })
    return setmetatable({ values = values, frame = frame }, FrameOwner)
end

function FrameOwner:set_integer(index, value)
    store_integer(self.frame, T.RegisterIdentity(index), ffi.new("int64_t", value))
    return self
end

function FrameOwner:set_float(index, value)
    store_float(self.frame, T.RegisterIdentity(index), value)
    return self
end

function FrameOwner:integer(index)
    return integer(self.frame, T.RegisterIdentity(index))
end

function FrameOwner:floating(index)
    return floating(self.frame, T.RegisterIdentity(index))
end

return {
    ffi = ffi,
    TAG_INTEGER = TAG_INTEGER,
    TAG_FLOAT = TAG_FLOAT,
    Recorder = Recorder,
    FrameOwner = FrameOwner,
    Trace = T,
}
