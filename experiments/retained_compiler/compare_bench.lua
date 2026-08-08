package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local backend = assert(arg[1], "backend must be cdef or asdl")
local workload = arg[2] or "same"
local iterations = tonumber(arg[3]) or 10000

local corpus = {}
local operators = { "+", "-", "*" }
for index = 1, 64 do
    local a, b = index * 3 + 1, index * 5 + 2
    local c, d = index % 17 + 3, index % 11 + 1
    local op1 = operators[index % 3 + 1]
    local op2 = operators[(index + 1) % 3 + 1]
    corpus[index] = ("let x = %d; let y = x %s %d * %d; return y %s %d;"):format(
        a, op1, b, c, op2, d)
end
if workload == "same" then corpus = { corpus[1] } end

local compile
if backend == "cdef" then
    local Machine = require("experiments.retained_compiler.machine")
    local compiler = Machine.Compiler()
    compile = function(source)
        compiler:compile(source)
        return compiler:succeeded(), compiler.artifact.length
    end
elseif backend == "asdl" or backend == "asdl-unchecked" then
    local Machine = require("experiments.retained_compiler.asdl_machine")
    local compile_asdl = backend == "asdl" and Machine.compile or Machine.compile_unchecked
    compile = function(source)
        local result = compile_asdl(source)
        return result:succeeded(), #result:artifact_text()
    end
else
    error("backend must be cdef or asdl")
end

local checksum = 0
for index = 1, 1000 do
    local ok, length = compile(corpus[(index - 1) % #corpus + 1])
    assert(ok)
    checksum = checksum + length
end

collectgarbage()
local heap_before = collectgarbage("count")
local started = os.clock()
for index = 1, iterations do
    local ok, length = compile(corpus[(index - 1) % #corpus + 1])
    if not ok then error("benchmark compilation rejected") end
    checksum = checksum + length
end
local elapsed = os.clock() - started
local heap_after = collectgarbage("count")

print(("backend=%s workload=%s corpus=%d iterations=%d us_per_compile=%.3f heap_delta_kb=%.3f checksum=%d")
    :format(backend, workload, #corpus, iterations, elapsed * 1000000 / iterations,
        heap_after - heap_before, checksum))
