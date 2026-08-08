package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local backend = assert(arg[1], "backend must be cdef or asdl")
local item_count = tonumber(arg[2]) or 20
local aggressive = arg[3] == "hot"
local shape = arg[4] or "bindings"

local source
if shape == "expression" then
    local parts = { "return 1" }
    for index = 2, item_count do
        local operator = index % 3 == 0 and " * " or index % 3 == 1 and " - " or " + "
        parts[#parts + 1] = operator
        parts[#parts + 1] = tostring(index)
    end
    parts[#parts + 1] = ";"
    source = table.concat(parts)
elseif shape == "bindings" then
    local lines = { "let v0 = 1;" }
    for index = 1, item_count - 1 do
        lines[#lines + 1] = ("let v%d = v%d + %d * %d;"):format(
            index, index - 1, index + 1, index + 2)
    end
    lines[#lines + 1] = ("return v%d;"):format(item_count - 1)
    source = table.concat(lines, "\n")
else
    error("shape must be bindings or expression")
end

local compile
if backend == "cdef" then
    local Machine = require("experiments.retained_compiler.machine")
    local compiler = Machine.Compiler()
    compile = function()
        compiler:compile(source)
        return compiler:succeeded(), compiler.artifact.length
    end
elseif backend == "asdl" then
    local Machine = require("experiments.retained_compiler.asdl_machine")
    compile = function()
        local result = Machine.compile(source)
        return result:succeeded(), #result:artifact_text()
    end
else
    error("backend must be cdef or asdl")
end

if aggressive and require("jit").status() then
    require("jit.opt").start("hotloop=1", "hotexit=1", "loopunroll=1000", "callunroll=1000")
end

local function trace_count()
    if not require("jit").status() then return 0 end
    local util = require("jit.util")
    local count = 0
    for trace = 1, 65535 do
        if util.traceinfo(trace) == nil then break end
        count = count + 1
    end
    return count
end

local traces_before = trace_count()
collectgarbage()
local started = os.clock()
local ok, artifact_length = compile()
local elapsed = os.clock() - started
local traces_after = trace_count()
assert(ok, "one-shot compilation rejected")

print(("backend=%s shape=%s items=%d bytes=%d mode=%s one_shot_us=%.3f new_traces=%d artifact=%d")
    :format(backend, shape, item_count, #source, aggressive and "hot" or "default", elapsed * 1000000,
        traces_after - traces_before, artifact_length))
