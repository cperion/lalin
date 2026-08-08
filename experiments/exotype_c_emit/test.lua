package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local Pipeline = require("experiments.exotype_c_emit.pipeline")
local Compiler = require("experiments.exotype_c_emit.compiler")

-- Pretend this text arrived from a database, network protocol, or user file.
-- Parsing is dynamic; the resulting stage objects are concrete semantic leaves.
local stage_constructors = {
    add = Pipeline.add,
    multiply = Pipeline.multiply,
    reject_above = Pipeline.reject_above,
}

local function parse(description)
    local stages = {}
    for name, value in description:gmatch("([_%a][_%w]*):([%-]?%d+)") do
        stages[#stages + 1] = assert(stage_constructors[name], "unknown stage " .. name)(tonumber(value))
    end
    return stages
end

local stages = parse("add:2,multiply:3,reject_above:100")
local Type = Pipeline.type(stages)
assert(Pipeline.type(parse("add:2,multiply:3,reject_above:100")) == Type)

local compiler = Compiler.new()
local program = compiler:compile(Type)
assert(Type.stats.queries == 2)
assert(program:sizeof() == 40)

local state = program:new()
assert(program:run(state, 1, 2) == 1)
assert(tonumber(state.value) == 33)
assert(tonumber(state.transitions) == 6)
assert(tonumber(state.completed) == 1)
assert(tonumber(state.rejected) == 0)
for index = 0, 2 do assert(tonumber(state.stage_hits[index]) == 2) end

assert(program:run(state, 1, 3) == 0)
assert(tonumber(state.value) == 105)
assert(tonumber(state.transitions) == 15)
assert(tonumber(state.completed) == 1)
assert(tonumber(state.rejected) == 1)
for index = 0, 2 do assert(tonumber(state.stage_hits[index]) == 5) end


local Single = Pipeline.type { Pipeline.add(7) }
local single_program = Compiler.new():compile(Single)
assert(single_program:sizeof() == 32)
local single = single_program:new()
assert(single_program:run(single, 5, 4) == 1)
assert(tonumber(single.value) == 33)
assert(tonumber(single.stage_hits[0]) == 4)

print(("ok exotype emitted-c state=%d stages=%d queries=%d result=%d"):format(
    program:sizeof(), program.module.stage_count, Type.stats.queries, tonumber(state.value)))
