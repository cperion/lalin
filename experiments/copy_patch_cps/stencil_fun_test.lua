package.path = "./lua/?.lua;./?.lua;./?/init.lua;" .. package.path

local VectorLinker = require("experiments.copy_patch_cps.vector_linker")
local NegativeLinker = require("experiments.copy_patch_cps.negative_space_linker")
local StencilFun = require("experiments.copy_patch_cps.stencil_fun")
local ffi = VectorLinker.ffi
local vector_bank = dofile("target/copy_patch_cps/vector/vector_bank.lua")
local f32_vector_bank = dofile("target/copy_patch_cps/f32_vector/f32_vector_bank.lua")
local negative_bank = dofile("target/copy_patch_cps/negative_space/bank.lua")
local suite = negative_bank:link()

do
    local count = 37
    local input, output = ffi.new("double[?]", count), ffi.new("double[?]", count)
    for index = 0, count - 1 do input[index] = index / 8 - 2 end
    local description = StencilFun.f64(input, count):drop(2):take(31)
        :map(StencilFun.add(1.25))
        :map(StencilFun.multiply_parameter(0))
        :map(StencilFun.square())
    local compiled = description:compile_store(vector_bank)
    compiled:new_separate_frame(output, { 1.5 }):execute()
    local oracle = description:luafun({ 1.5 }):totable()
    for index = 0, description.count - 1 do assert(output[index] == oracle[index + 1]) end
    compiled:free()
end

do
    local values = ffi.new("double[19]")
    local expected = 0
    for index = 0, 18 do values[index] = index - 4; expected = expected + values[index] end
    local source = StencilFun.f64_reduction(values, 19)
    assert(source:sum_fixed(suite) == expected)
    assert(source:min_number(suite) == -4 and source:max_number(suite) == 14)
    local zeros = ffi.new("double[3]", 0/0, -0.0, 0.0)
    local zero_source = StencilFun.f64_reduction(zeros, 3)
    assert(1 / zero_source:min_number(suite) == -math.huge)
    assert(1 / zero_source:max_number(suite) == math.huge)
end

do
    local bytes = ffi.new("uint8_t[40]")
    for index = 0, 39 do bytes[index] = 7 end
    bytes[33] = 91
    local source = StencilFun.u8(bytes, 40)
    assert(source:find_byte(suite, 91) == 33)
    assert(source:find_any2(suite, 3, 91) == 33)
    assert(source:find_any4(suite, 2, 3, 7, 91) == 0)
    assert(source:count_byte(suite, 7) == 39)
    assert(source:any_equal(suite, 91) and not source:all_equal(suite, 7))
end

do
    local left, right, output = ffi.new("double[7]"), ffi.new("double[7]"), ffi.new("double[7]")
    for index = 0, 6 do left[index], right[index] = index, 6 - index end
    StencilFun.zip_f64(left, right, 7):scale_add(suite, output, 2)
    for index = 0, 6 do assert(output[index] == left[index] * 2 + right[index]) end
    StencilFun.zip_f64(left, right, 7):add(suite, output)
    for index = 0, 6 do assert(output[index] == left[index] + right[index]) end
    StencilFun.zip_f64(left, right, 7):multiply(suite, output)
    for index = 0, 6 do assert(output[index] == left[index] * right[index]) end
end

do
    local input, output = ffi.new("float[9]"), ffi.new("float[9]")
    for index = 0, 8 do input[index] = index end
    StencilFun.f32_canonical(input, 9):store(suite, output, 1, 2, 3, 4)
    assert(output[0] == 400 and output[8] == 7056)
    local description = StencilFun.f32(input, 9)
        :map(StencilFun.add(1)):map(StencilFun.multiply(2)):map(StencilFun.square())
    local compiled = description:compile_store(f32_vector_bank)
    compiled:new_separate_frame(output):execute()
    local oracle = description:luafun():totable()
    for index = 0, 8 do assert(output[index] == oracle[index + 1]) end
    compiled:free()
end

do
    local input, output = ffi.new("uint64_t[5]"), ffi.new("uint64_t[5]")
    for index = 0, 4 do input[index] = index end
    StencilFun.u64_bulk(input, 5):store(suite, output, 1, 0, 1)
    for index = 0, 4 do assert(tonumber(output[index]) == (index + 1) * 2) end
end

suite:free()
print("StencilFunV1 LuaFun surface: ok")
