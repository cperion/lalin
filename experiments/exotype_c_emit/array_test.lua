package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local Kernel = require("experiments.exotype_c_emit.array_kernel")
local Compiler = require("experiments.exotype_c_emit.array_compiler")

local operations = {
    Kernel.multiply(1.5),
    Kernel.add_parameter(0),
    Kernel.square(),
    Kernel.multiply_parameter(1),
}
local Type = Kernel.type(Kernel.f64, operations)
assert(Kernel.type(Kernel.f64, {
    Kernel.multiply(1.5),
    Kernel.add_parameter(0),
    Kernel.square(),
    Kernel.multiply_parameter(1),
}) == Type)

local program = Compiler.new():compile(Type)
assert(Type.stats.queries == 2)
assert(program.abi.element_size == 8)
assert(program.abi.parameter_count == 2)
assert(program.module.operation_count == 4)

local count = 4096
local input = program:new_buffer(count)
local output = program:new_buffer(count)
local parameters = program:new_parameters()
parameters[0], parameters[1] = 2.25, 0.75
for index = 0, count - 1 do input[index] = index / 16 end

local run = program:entry()
run(output, input, count, parameters)

local function expected(index)
    local value = input[index] * 1.5 + parameters[0]
    return value * value * parameters[1]
end
for _, index in ipairs { 0, 1, 127, 2048, 4095 } do
    local difference = math.abs(tonumber(output[index]) - expected(index))
    assert(difference < 1e-9, ("wrong output at %d: %.17g"):format(index, output[index]))
end

-- A different element type and operation sequence creates a different owner and
-- ABI, while using the same Lua-owned buffer lifetime convention.
local F32Type = Kernel.type(Kernel.f32, {
    Kernel.add_parameter(0), Kernel.square(), Kernel.multiply(2)
})
assert(F32Type ~= Type)
local f32_program = Compiler.new():compile(F32Type)
assert(f32_program.abi.element_size == 4)
local f32_input = f32_program:new_buffer(4)
local f32_output = f32_program:new_buffer(4)
local f32_parameters = f32_program:new_parameters()
f32_parameters[0] = 2
for index = 0, 3 do f32_input[index] = index end
f32_program:entry()(f32_output, f32_input, 4, f32_parameters)
for index = 0, 3 do assert(tonumber(f32_output[index]) == (index + 2) ^ 2 * 2) end

print(("ok fused array kernel element=%d params=%d operations=%d count=%d"):format(
    program.abi.element_size, program.abi.parameter_count, program.module.operation_count, count))
