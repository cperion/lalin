package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local ffi = require("ffi")
local Machine = require("experiments.retained_compiler.machine")

local iterations = tonumber(arg[1]) or 100000
local source = "let x = 40; let y = x + 2 * 3; return y - 1;"
local compiler = Machine.Compiler()

for _ = 1, 1000 do compiler:compile(source) end
assert(compiler:succeeded(), compiler:diagnostic_text())

collectgarbage()
local started = os.clock()
for _ = 1, iterations do compiler:compile(source) end
local elapsed = os.clock() - started
assert(compiler:succeeded(), compiler:diagnostic_text())

print(("retained compiler root=%d iterations=%d us_per_compile=%.3f"):format(
    ffi.sizeof(compiler), iterations, elapsed * 1000000 / iterations))
