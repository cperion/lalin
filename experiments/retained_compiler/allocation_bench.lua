package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local backend = assert(arg[1], "backend must be cdef or asdl")
local iterations = tonumber(arg[2]) or 1000
local source = "let x = 40; let y = x + 2 * 3; return y - 1;"
local compile

if backend == "cdef" then
    local Machine = require("experiments.retained_compiler.machine")
    local compiler = Machine.Compiler()
    compile = function() compiler:compile(source) end
elseif backend == "asdl" then
    local Machine = require("experiments.retained_compiler.asdl_machine")
    compile = function() Machine.compile(source) end
else
    error("backend must be cdef or asdl")
end

for _ = 1, 1000 do compile() end
collectgarbage()
collectgarbage("stop")
local before = collectgarbage("count")
for _ = 1, iterations do compile() end
local growth = collectgarbage("count") - before
collectgarbage("restart")

print(("backend=%s iterations=%d stopped_gc_kb_per_compile=%.3f"):format(
    backend, iterations, growth / iterations))
