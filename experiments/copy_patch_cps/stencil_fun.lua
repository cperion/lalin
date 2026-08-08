local fun = require("fun")
local VectorPipeline = require("experiments.copy_patch_cps.vector_pipeline")
local VectorLinker = require("experiments.copy_patch_cps.vector_linker")
local ffi = VectorLinker.ffi

local F64Chain = {}
F64Chain.__index = F64Chain
local F64StoreProgram = {}
F64StoreProgram.__index = F64StoreProgram
local F64ReductionSource = {}
F64ReductionSource.__index = F64ReductionSource
local U8Source = {}
U8Source.__index = U8Source
local F64ZipSource = {}
F64ZipSource.__index = F64ZipSource
local F32Chain = {}
F32Chain.__index = F32Chain
local F32CanonicalSource = F32Chain
local U64BulkSource = {}
U64BulkSource.__index = U64BulkSource

local function exact_count(value)
    assert(type(value) == "number" and value >= 0 and value == math.floor(value),
        "StencilFun count must be a nonnegative integer")
    return value
end

local function append_operation(chain, operation)
    local operations = {}
    for index = 1, #chain.operations do operations[index] = chain.operations[index] end
    operations[#operations + 1] = operation
    return setmetatable({
        input = chain.input, count = chain.count, operations = operations, owner = chain,
    }, F64Chain)
end

local function take_count(source, count)
    count = exact_count(count)
    return math.min(source.count, count)
end

function F64Chain:take(count)
    return setmetatable({
        input = self.input, count = take_count(self, count),
        operations = self.operations, owner = self,
    }, F64Chain)
end

function F64Chain:drop(count)
    count = math.min(self.count, exact_count(count))
    return setmetatable({
        input = ffi.cast("const double *", self.input) + count,
        count = self.count - count, operations = self.operations, owner = self,
    }, F64Chain)
end

local function append_f32_operation(chain, operation)
    local operations = {}
    for index = 1, #chain.operations do operations[index] = chain.operations[index] end
    operations[#operations + 1] = operation
    return setmetatable({
        input = chain.input, count = chain.count, operations = operations, owner = chain,
    }, F32Chain)
end

function F32Chain:take(count)
    return setmetatable({
        input = self.input, count = take_count(self, count),
        operations = self.operations, owner = self,
    }, F32Chain)
end

function F32Chain:drop(count)
    count = math.min(self.count, exact_count(count))
    return setmetatable({
        input = ffi.cast("const float *", self.input) + count,
        count = self.count - count, operations = self.operations, owner = self,
    }, F32Chain)
end

function F32Chain:map(operation) return append_f32_operation(self, operation) end

function F64Chain:map(operation)
    return append_operation(self, operation)
end

function F64Chain:compile_store(bank)
    local program = VectorPipeline.compile(bank, self.operations)
    return setmetatable({ chain = self, program = program }, F64StoreProgram)
end

function F64StoreProgram:new_separate_frame(output, parameters)
    return self.program:new_separate_frame(
        self.chain.input, output, self.chain.count, parameters)
end

function F32Chain:compile_store(bank)
    local program = VectorPipeline.compile_f32(bank, self.operations)
    return setmetatable({ chain = self, program = program }, F64StoreProgram)
end

function F64StoreProgram:new_in_place_frame(parameters)
    return self.program:new_in_place_frame(
        self.chain.input, self.chain.count, parameters)
end

function F64StoreProgram:free() self.program:free() end

local function install_single_view_methods(class, ctype)
    function class:take(count)
        return setmetatable({
            input = self.input, count = take_count(self, count), owner = self,
        }, class)
    end
    function class:drop(count)
        count = math.min(self.count, exact_count(count))
        return setmetatable({
            input = ffi.cast(ctype, self.input) + count,
            count = self.count - count, owner = self,
        }, class)
    end
end

install_single_view_methods(F64ReductionSource, "const double *")
install_single_view_methods(U8Source, "const uint8_t *")
install_single_view_methods(U64BulkSource, "const uint64_t *")

function F64ZipSource:take(count)
    return setmetatable({
        left = self.left, right = self.right, count = take_count(self, count), owner = self,
    }, F64ZipSource)
end

function F64ZipSource:drop(count)
    count = math.min(self.count, exact_count(count))
    return setmetatable({
        left = ffi.cast("const double *", self.left) + count,
        right = ffi.cast("const double *", self.right) + count,
        count = self.count - count, owner = self,
    }, F64ZipSource)
end

local function f64_generator(param, state)
    if state >= param.count then return nil end
    return state + 1, tonumber(param.input[state])
end

function F64Chain:luafun(parameters)
    local iterator = fun.wrap(f64_generator, {
        input = ffi.cast("const double *", self.input), count = self.count,
    }, 0)
    for index = 1, #self.operations do
        local operation = self.operations[index]
        iterator = iterator:map(function(value)
            return VectorPipeline.evaluate({ operation }, value, parameters)
        end)
    end
    return iterator
end

function F64ReductionSource:min_number(suite)
    local frame = ffi.new("F64ReductionV1Frame", { self.input, self.count, 0 })
    suite:run_min_number(frame)
    return tonumber(frame.result)
end

function F64ReductionSource:max_number(suite)
    local frame = ffi.new("F64ReductionV1Frame", { self.input, self.count, 0 })
    suite:run_max_number(frame)
    return tonumber(frame.result)
end

function F64ReductionSource:sum_fixed(suite)
    local frame = ffi.new("F64ReductionV1Frame", { self.input, self.count, 0 })
    suite:run_reduction(frame)
    return tonumber(frame.result)
end

local function u8_set_frame(source, needle0, needle1, needle2, needle3)
    return ffi.new("U8ScanSetV1Frame", {
        source.input, source.count, needle0 or 0, needle1 or 0, needle2 or 0, needle3 or 0, 0,
    })
end

function U8Source:find_any2(suite, needle0, needle1)
    local frame = u8_set_frame(self, needle0, needle1)
    suite:run_find_any2(frame)
    return tonumber(frame.result)
end

function U8Source:find_any4(suite, needle0, needle1, needle2, needle3)
    local frame = u8_set_frame(self, needle0, needle1, needle2, needle3)
    suite:run_find_any4(frame)
    return tonumber(frame.result)
end

function U8Source:count_byte(suite, needle)
    local frame = u8_set_frame(self, needle)
    suite:run_count_byte(frame)
    return tonumber(frame.result)
end

function U8Source:all_equal(suite, needle)
    local frame = u8_set_frame(self, needle)
    suite:run_all_equal(frame)
    return frame.result ~= 0
end

function U8Source:any_equal(suite, needle)
    return self:find_byte(suite, needle) < self.count
end

function U8Source:find_byte(suite, needle)
    local frame = ffi.new("U8ScanV1Frame", { self.input, self.count, needle, 0 })
    suite:run_scan(frame)
    return tonumber(frame.found)
end

local function run_zip(source, suite, output, entry, scale)
    local frame = ffi.new("F64ZipMapV1Frame", {
        source.left, source.right, output, source.count, scale or 0,
    })
    entry(suite, frame)
    return source
end

function F64ZipSource:add(suite, output)
    return run_zip(self, suite, output, suite.run_zip_add)
end

function F64ZipSource:multiply(suite, output)
    return run_zip(self, suite, output, suite.run_zip_multiply)
end

function F64ZipSource:scale_add(suite, output, scale)
    local frame = ffi.new("F64ZipMapV1Frame", {
        self.left, self.right, output, self.count, scale,
    })
    suite:run_zip(frame)
    return self
end

local function f32_generator(param, state)
    if state >= param.count then return nil end
    return state + 1, tonumber(param.input[state])
end

function F32Chain:luafun(parameters)
    local iterator = fun.wrap(f32_generator, {
        input = ffi.cast("const float *", self.input), count = self.count,
    }, 0)
    local rounded = ffi.new("float[1]")
    for index = 1, #self.operations do
        local operation = self.operations[index]
        iterator = iterator:map(function(value)
            rounded[0] = VectorPipeline.evaluate({ operation }, value, parameters)
            return tonumber(rounded[0])
        end)
    end
    return iterator
end

function F32Chain:store(suite, output, scalar0, scalar1, scalar2, scalar3)
    local frame = ffi.new("F32MapPipelineV1Frame", {
        self.input, output, self.count, scalar0, scalar1, scalar2, scalar3,
    })
    suite:run_f32(frame)
    return self
end

function U64BulkSource:store(suite, output, addend, xor_value, rotate)
    local frame = ffi.new("U64BulkV1Frame", {
        self.input, output, self.count, addend, xor_value, rotate,
    })
    suite:run_u64(frame)
    return self
end

local StencilFun = {
    add = VectorPipeline.add,
    multiply = VectorPipeline.multiply,
    add_parameter = VectorPipeline.add_parameter,
    multiply_parameter = VectorPipeline.multiply_parameter,
    square = VectorPipeline.square,
}

function StencilFun.f64(input, count)
    return setmetatable({ input = input, count = exact_count(count), operations = {} }, F64Chain)
end

function StencilFun.f64_reduction(input, count)
    return setmetatable({ input = input, count = exact_count(count) }, F64ReductionSource)
end

function StencilFun.u8(input, count)
    return setmetatable({ input = input, count = exact_count(count) }, U8Source)
end

function StencilFun.zip_f64(left, right, count)
    return setmetatable({
        left = left, right = right, count = exact_count(count),
    }, F64ZipSource)
end

function StencilFun.f32(input, count)
    return setmetatable({
        input = input, count = exact_count(count), operations = {},
    }, F32Chain)
end

function StencilFun.f32_canonical(input, count)
    return StencilFun.f32(input, count)
end

function StencilFun.u64_bulk(input, count)
    return setmetatable({ input = input, count = exact_count(count) }, U64BulkSource)
end

return StencilFun
