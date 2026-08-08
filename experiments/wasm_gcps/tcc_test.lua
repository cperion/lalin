package.path = "./?.lua;./?/init.lua;" .. package.path

local bit = require("bit")
local Shapes = require("experiments.wasm_gcps.tcc_shapes")

local shapes = Shapes.new()
local operations = {
    shapes.opcode_sum, shapes.opcode_mixed,
    shapes.step_sum, shapes.step_mixed,
    shapes.region_sum, shapes.region_mixed,
}

for n = 0, 1000 do
    local expected_sum = n * (n + 1) / 2
    assert(shapes.opcode_sum(n) == expected_sum)
    assert(shapes.step_sum(n) == expected_sum)
    assert(shapes.region_sum(n) == expected_sum)
    assert(shapes.opcode_mixed(n) == expected_sum * 1.5)
    assert(shapes.step_mixed(n) == expected_sum * 1.5)
    assert(shapes.region_mixed(n) == expected_sum * 1.5)
end

local wrapped_n = 65536
local wrapped_sum = bit.tobit(wrapped_n * (wrapped_n + 1) / 2)
assert(shapes.opcode_sum(wrapped_n) == wrapped_sum)
assert(shapes.step_sum(wrapped_n) == wrapped_sum)
assert(shapes.region_sum(wrapped_n) == wrapped_sum)

for _, operation in ipairs(operations) do assert(operation(-1) == 0) end

shapes:free()
print("libtcc FFI CPS boundary shapes: ok")

