package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local bit = require("bit")
local util = require("jit.util")
local vmdef = require("jit.vmdef")
local K = require("experiments.exotyped_cps.kernel")
local Compiler = require("experiments.exotyped_cps.compiler")
local C = require("experiments.exotyped_cps.constructors")

local function last_opcode(fn)
    local last
    for pc = 1, 10000 do
        local instruction = util.funcbc(fn, pc)
        if instruction == nil then break end
        local opcode = bit.band(instruction, 255)
        last = vmdef.bcnames:sub(opcode * 6 + 1, opcode * 6 + 6):match("^%s*(.-)%s*$")
    end
    return last
end

local compiler = Compiler.new()

-- Composition and fusion: the root demand asks only for Array.Sum.
local Point = C.Record {
    { name = "x", ctype = "int64_t" },
    { name = "y", ctype = "int64_t" },
    { name = "z", ctype = "int64_t" },
}
local Batch = C.Array(Point, 4)
local sum_program = compiler:compile(Batch, C.Sum)
local sum = sum_program:entry()
local batch = sum_program:new()
local expected = 0
for item = 0, 3 do
    batch.items[item].x = item + 1
    batch.items[item].y = (item + 1) * 2
    batch.items[item].z = (item + 1) * 3
    expected = expected + (item + 1) * 6
end
assert(ffi.sizeof(Point.ctype_name) == 24)
assert(ffi.sizeof(Batch.ctype_name) == 104)
assert(tonumber(sum(batch)) == expected)
assert(sum_program.listing:match("self%.items%[3%]%.z"))
assert(not sum_program.listing:match("for%s"))
assert(Point.stats.layout == 1 and Point.stats.operations.Sum == 1)
assert(Point.stats.operations.ScaleEffect == nil)

-- A later behavioral program reuses the sealed physical type and requests new operations.
local scale_program = compiler:compile(Batch, C.RunScale)
local run_scale = scale_program:entry()
run_scale(batch, 3)
assert(tonumber(sum(batch)) == expected * 3)
assert(tonumber(batch.transitions) == 1)
assert(last_opcode(run_scale) == "CALLT")
assert(last_opcode(scale_program:operation(Batch, C.Scaled)) ~= "CALLT")
assert(Point.stats.operations.ScaleEffect == 1)

-- A cyclic residual CPS graph is valid even though cyclic property evaluation is not.
local Pipeline = C.Pipeline {
    { kind = "add", value = 2 },
    { kind = "multiply", value = 3 },
    { kind = "reject_above", value = 100 },
}
assert(C.Pipeline {
    { kind = "add", value = 2 },
    { kind = "multiply", value = 3 },
    { kind = "reject_above", value = 100 },
} == Pipeline)
local pipeline_program = compiler:compile(Pipeline, Pipeline.Run)
local run = pipeline_program:entry()
local machine = pipeline_program:new()
run(machine, 1, 2)
assert(tonumber(machine.value) == 33)
assert(tonumber(machine.transitions) == 6)
assert(tonumber(machine.completed) == 1 and tonumber(machine.rejected) == 0)
run(machine, 1, 3)
assert(tonumber(machine.value) == 105)
assert(tonumber(machine.rejected) == 1)
assert(last_opcode(run) == "CALLT")
assert(pipeline_program.listing:match("remaining > 0 then return operation_"))
assert(last_opcode(pipeline_program:operation(Pipeline, Pipeline.stage_operations[1])) == "CALLT")
assert(last_opcode(pipeline_program:operation(Pipeline, Pipeline.Loop)) == "CALLT")
local second_pipeline_program = Compiler.new():compile(Pipeline, Pipeline.Run)
assert(second_pipeline_program.listing == pipeline_program.listing)
assert(ffi.typeof(second_pipeline_program:new()) == ffi.typeof(machine))

local allocation_machine = pipeline_program:new()
for index = 1, 1000 do run(allocation_machine, index, 2) end
collectgarbage("collect")
collectgarbage("stop")
local allocation_before = collectgarbage("count")
for index = 1, 10000 do run(allocation_machine, index, 2) end
local allocation_growth = (collectgarbage("count") - allocation_before) * 1024
collectgarbage("restart")
assert(allocation_growth < 4096, "residual CPS transitions allocated " .. allocation_growth .. " bytes")

-- True property recursion remains an error.
local BadOperation = K.operation("Bad", "expression")
local Bad
Bad = K.owner {
    name = "Bad", layout = function() return { { name = "value", ctype = "int64_t" } } end,
    operations = {
        [BadOperation] = function(cc) return cc:operation(Bad, BadOperation) end,
    },
}
local ok, message = pcall(function() Compiler.new():compile(Bad, BadOperation) end)
assert(not ok and tostring(message):match("cyclic exotype property query"))

print(("ok exotyped cps point=%d batch=%d pipeline=%d operations=%d result=%d"):format(
    ffi.sizeof(Point.ctype_name), ffi.sizeof(Batch.ctype_name), ffi.sizeof(Pipeline.ctype_name),
    #pipeline_program.ordered, tonumber(machine.value)))
