package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi = require("ffi")
local State = require("experiments.gccjit_driver.compiler_machine")

local compiler = State.Compiler()
compiler:inspect([[
let x = 2 + 3;
let y = x * 4;
return y - 5;
 ]], 3)
assert(compiler:succeeded(), compiler:diagnostic_text())
assert(compiler.retained.instructions.count == 8)
assert(compiler.input_instruction_count == compiler.retained.instructions.count)
assert(compiler.backend.projected_count == compiler.retained.instructions.count)
assert(compiler:invoke() == 15)
assert(compiler.gcc.context == nil and compiler.gcc.result ~= nil)

compiler:compile("return 1 + 2 + 3 + 4;", 3)
assert(compiler:succeeded(), compiler:diagnostic_text())
assert(compiler:invoke() == 10)
assert(compiler.generation == 2)

local input_instruction_count = tonumber(compiler.input_instruction_count)
local projection_us = tonumber(compiler.metrics.projection_ns) / 1000
local compile_us = tonumber(compiler.metrics.compile_ns) / 1000

compiler:lower("return missing;")
assert(not compiler:lowered())
assert(compiler.status == State.constants.status.rejected)
assert(compiler:diagnostic_text() == "unresolved name")
assert(compiler.input_instruction_count == 0)

compiler:free()
assert(compiler.status == State.constants.status.released)
print(("ok gccjit compiler-self root=%d instructions=%d projection_us=%.3f compile_us=%.3f"):format(
    ffi.sizeof(compiler), input_instruction_count,
    projection_us, compile_us))
