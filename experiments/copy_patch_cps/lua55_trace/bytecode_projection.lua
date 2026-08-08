local T = require("experiments.copy_patch_cps.lua55_trace.model")
local Runtime = require("experiments.copy_patch_cps.lua55_trace.recorder")
local Plan = T.IntegerAddForLoopPlan

local function identity(pc) return T.InstructionIdentity(pc) end
local function register(index) return T.RegisterIdentity(index) end


function Plan:new_frame(sum, init, limit, step, generation)
    assert(step ~= 0, "IntegerAddForLoopPlan requires a nonzero step")
    local frame = Runtime.FrameOwner.new(self.register_count, generation)
    frame:set_integer(self.sum.index, sum)
    frame:set_integer(self.limit.index, limit)
    frame:set_integer(self.step.index, step)
    frame:set_integer(self.index.index, init)
    return frame
end

function Plan:new_positive_frame(sum, init, limit, step, generation)
    assert(step > 0 and init <= limit,
        "IntegerAddForLoopPlan positive frame requires a nonempty positive-step loop")
    return self:new_frame(sum, init, limit, step, generation)
end

local function project(proto, forprep_pc)
    assert(type(proto) == "table" and type(proto.code) == "table",
        "Lua55 trace projection requires a decoded prototype")
    assert(type(forprep_pc) == "number" and forprep_pc >= 0 and forprep_pc == math.floor(forprep_pc),
        "Lua55 trace projection requires an exact FORPREP PC")

    local forprep_index = forprep_pc + 1
    local forprep = assert(proto.code[forprep_index], "missing FORPREP instruction")
    assert(forprep.name == "FORPREP", "trace root is not FORPREP")

    local body_index = forprep_index + 1
    local body = assert(proto.code[body_index], "missing numeric-for body")
    assert(body.name == "ADD" and body.A == body.B,
        "numeric-for body is not an accumulating ADD")

    local companion_index = body_index + 1
    local companion = assert(proto.code[companion_index], "missing ADD metamethod companion")
    assert(companion.name == "MMBIN" and companion.A == body.B and companion.B == body.C,
        "ADD metamethod companion shape changed")

    local forloop_index = forprep_index + forprep.Bx + 1
    local forloop = assert(proto.code[forloop_index], "missing FORLOOP instruction")
    assert(forloop.name == "FORLOOP" and forloop.A == forprep.A,
        "numeric-for closing instruction shape changed")
    assert(forloop_index + 1 - forloop.Bx == body_index,
        "FORLOOP does not return to the accumulating ADD")
    assert(body.C == forprep.A + 2,
        "accumulating ADD does not consume the numeric-for index")

    return T.IntegerAddForLoopPlan(
        proto.maxstacksize,
        identity(forprep_pc), identity(body_index - 1), identity(companion_index - 1),
        identity(forloop_index - 1), register(body.A), register(forprep.A + 2),
        register(forprep.A), register(forprep.A + 1), forloop_index)
end

return { project = project, Trace = T }
