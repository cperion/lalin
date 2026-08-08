package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local backend = assert(arg[1], "backend must be cdef or asdl")
local term_count = tonumber(arg[2]) or 2000

local parts = { "return 1" }
for index = 2, term_count do
    local operator = index % 3 == 0 and " * " or index % 3 == 1 and " - " or " + "
    parts[#parts + 1] = operator
    parts[#parts + 1] = tostring(index)
end
parts[#parts + 1] = ";"
local source = table.concat(parts)

collectgarbage()
local started = os.clock()
local ok, artifact_length
if backend == "cdef" then
    local Machine = require("experiments.retained_compiler.machine")
    local compiler = Machine.Compiler()
    compiler:compile(source)
    ok, artifact_length = compiler:succeeded(), compiler.artifact.length
elseif backend == "asdl" then
    local Machine = require("experiments.retained_compiler.asdl_machine")
    local result = Machine.compile(source)
    ok, artifact_length = result:succeeded(), #result:artifact_text()
else
    error("backend must be cdef or asdl")
end
local elapsed = os.clock() - started
assert(ok, "end-to-end compilation rejected")

print(("backend=%s terms=%d bytes=%d end_to_end_us=%.3f artifact=%d"):format(
    backend, term_count, #source, elapsed * 1000000, artifact_length))
