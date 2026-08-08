local Undump = require("experiments.lua55.undump55")
local Projection = require("experiments.copy_patch_cps.lua55_trace.bytecode_projection")
local Runtime = require("experiments.copy_patch_cps.lua55_trace.recorder")
local Emitter = require("experiments.copy_patch_cps.lua55_trace.emitter")
local Model = require("experiments.copy_patch_cps.lua55_trace.model")

local ColdSite = {}
local InstalledSite = {}
local ReleasedSite = {}
local Program = {}
Program.__index = Program

local function exact_positive_integer(value)
    assert(type(value) == "number" and value >= 1 and value <= 0x1fffffffffffff
        and value == math.floor(value),
        "Lua55 integer AddForLoop trace requires an exact positive limit")
    return value
end

local function initialize(program, limit)
    local frame = program.frame
    frame:set_integer(program.plan.sum.index, 0)
    frame:set_integer(program.plan.limit.index, limit)
    frame:set_integer(program.plan.step.index, 1)
    frame:set_integer(program.plan.index.index, 1)
    frame.frame.resume_pc = 0
end

function ColdSite:call(program, limit)
    initialize(program, limit)
    local recorder = Runtime.Recorder.new_plan(
        program.plan, program.frame, Emitter.NativeArena.new(program.bank, program.capacity))
    local outcome = recorder:record_plan()
    assert(Model.TraceRecorded:is(outcome),
        "Lua55 AddForLoop recording did not reach its first backedge")
    program.native = recorder.native
    program.recordings = program.recordings + 1
    program.phase = InstalledSite
    program.native:execute(program.frame.frame)
    return tonumber(program.frame:integer(program.plan.sum.index))
end

function InstalledSite:call(program, limit)
    initialize(program, limit)
    program.native:execute(program.frame.frame)
    return tonumber(program.frame:integer(program.plan.sum.index))
end

function ReleasedSite:call() error("Lua55 trace program was released", 2) end

function ColdSite:free(program) program.phase = ReleasedSite end
function InstalledSite:free(program)
    program.native:free()
    program.native = false
    program.phase = ReleasedSite
end
function ReleasedSite:free() end

function Program.new(plan, bank, capacity)
    return setmetatable({
        plan = plan, bank = bank, capacity = capacity or 4096,
        frame = Runtime.FrameOwner.new(plan.register_count),
        phase = ColdSite, native = false, recordings = 0,
    }, Program)
end

function Program:call(limit)
    return self.phase.call(self.phase, self, exact_positive_integer(limit))
end

function Program:free() return self.phase.free(self.phase, self) end

local function load(bytes, child_index, forprep_pc, bank, capacity)
    local prototype = Undump.undump(bytes)
    local child = assert(prototype.protos[child_index], "missing Lua55 trace child prototype")
    return Program.new(Projection.project(child, forprep_pc), bank, capacity), prototype
end

local function loadfile(path, child_index, forprep_pc, bank, capacity)
    local file = assert(io.open(path, "rb")); local bytes = file:read("*a"); file:close()
    return load(bytes, child_index, forprep_pc, bank, capacity)
end

return { Program = Program, load = load, loadfile = loadfile }
