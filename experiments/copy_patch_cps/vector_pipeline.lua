local Linker = require("experiments.copy_patch_cps.vector_linker")
local ffi = Linker.ffi

local Slot0, Slot1, Slot2, Slot3 = {}, {}, {}, {}

function Slot0:store(state, value) state.scalar0 = value end
function Slot1:store(state, value) state.scalar1 = value end
function Slot2:store(state, value) state.scalar2 = value end
function Slot3:store(state, value) state.scalar3 = value end

function Slot0:add_prefix(bank) return bank.add0_prefix end
function Slot1:add_prefix(bank) return bank.add1_prefix end
function Slot2:add_prefix(bank) return bank.add2_prefix end
function Slot3:add_prefix(bank) return bank.add3_prefix end

function Slot0:multiply_prefix(bank) return bank.mul0_prefix end
function Slot1:multiply_prefix(bank) return bank.mul1_prefix end
function Slot2:multiply_prefix(bank) return bank.mul2_prefix end
function Slot3:multiply_prefix(bank) return bank.mul3_prefix end

local slots = { Slot0, Slot1, Slot2, Slot3 }

local AddConstant = {}
AddConstant.__index = AddConstant
local MultiplyConstant = {}
MultiplyConstant.__index = MultiplyConstant
local AddParameter = {}
AddParameter.__index = AddParameter
local MultiplyParameter = {}
MultiplyParameter.__index = MultiplyParameter
local Square = {}
Square.__index = Square

local BoundAdd = {}
BoundAdd.__index = BoundAdd
local BoundMultiply = {}
BoundMultiply.__index = BoundMultiply
local BoundSquare = {}
BoundSquare.__index = BoundSquare

local ConstantBinding = {}
ConstantBinding.__index = ConstantBinding
local ParameterBinding = {}
ParameterBinding.__index = ParameterBinding

local Compiler = {}
Compiler.__index = Compiler
local Program = {}
Program.__index = Program
local InPlaceFrame = {}
InPlaceFrame.__index = InPlaceFrame
local SeparateFrame = {}
SeparateFrame.__index = SeparateFrame

local function finite_number(value, label)
    assert(type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge, label .. " must be finite")
    return value
end

local function parameter_index(value)
    assert(type(value) == "number" and value >= 0 and value == math.floor(value),
        "parameter index must be a nonnegative integer")
    return value
end

function AddConstant:bind(compiler)
    compiler.bound[#compiler.bound + 1] = setmetatable({
        slot = compiler:claim_constant(self.value),
    }, BoundAdd)
end

function MultiplyConstant:bind(compiler)
    compiler.bound[#compiler.bound + 1] = setmetatable({
        slot = compiler:claim_constant(self.value),
    }, BoundMultiply)
end

function AddParameter:bind(compiler)
    compiler.bound[#compiler.bound + 1] = setmetatable({
        slot = compiler:claim_parameter(self.index),
    }, BoundAdd)
end

function MultiplyParameter:bind(compiler)
    compiler.bound[#compiler.bound + 1] = setmetatable({
        slot = compiler:claim_parameter(self.index),
    }, BoundMultiply)
end

function Square:bind(compiler)
    compiler.bound[#compiler.bound + 1] = setmetatable({}, BoundSquare)
end

function AddConstant:apply(value) return value + self.value end
function MultiplyConstant:apply(value) return value * self.value end
function AddParameter:apply(value, parameters) return value + parameters[self.index + 1] end
function MultiplyParameter:apply(value, parameters) return value * parameters[self.index + 1] end
function Square:apply(value) return value * value end

function BoundAdd:prefix(bank) return self.slot:add_prefix(bank) end
function BoundMultiply:prefix(bank) return self.slot:multiply_prefix(bank) end
function BoundSquare:prefix(bank) return bank.square_prefix end

function ConstantBinding:install(state) self.slot:store(state, self.value) end
function ParameterBinding:install(state, parameters)
    local value = assert(parameters and parameters[self.index + 1],
        "missing F64MapPipelineV1 parameter " .. self.index)
    self.slot:store(state, finite_number(value, "pipeline parameter"))
end

local function claim_slot(compiler)
    local index = #compiler.bindings + 1
    assert(index <= 4, "F64MapPipelineV1 supports scalar operand slots 0 through 3")
    return slots[index], index
end

function Compiler:claim_constant(value)
    local slot, index = claim_slot(self)
    self.bindings[index] = setmetatable({ slot = slot, value = value }, ConstantBinding)
    return slot
end

function Compiler:claim_parameter(parameter)
    local slot, index = claim_slot(self)
    self.bindings[index] = setmetatable({ slot = slot, index = parameter }, ParameterBinding)
    return slot
end

local function exact_count(value)
    assert(type(value) == "number" and value >= 0
        and value <= 0x1fffffffffffff and value == math.floor(value),
        "element count must be an exact nonnegative integer")
    return value
end

local function pointer_address(value)
    return tonumber(ffi.cast("uintptr_t", ffi.cast("const void *", value)))
end

local function new_state(program, input, output, count, parameters)
    local state = ffi.new(program.frame_type)
    state.input = ffi.cast(program.input_type, input)
    state.output = ffi.cast(program.output_type, output)
    state.count = exact_count(count)
    state.scalar0, state.scalar1, state.scalar2, state.scalar3 = 0, 0, 0, 0
    for index = 1, #program.bindings do
        program.bindings[index]:install(state, parameters)
    end
    return state
end

function Program:new_in_place_frame(values, count, parameters)
    local state = new_state(self, values, values, count, parameters)
    return setmetatable({
        program = self, state = state, values_owner = values,
    }, InPlaceFrame)
end

function Program:new_separate_frame(input, output, count, parameters)
    count = exact_count(count)
    local input_start = pointer_address(input)
    local output_start = pointer_address(output)
    local bytes = count * self.element_size
    assert(input_start + bytes <= output_start or output_start + bytes <= input_start,
        self.no_alias_label .. " ranges overlap")
    local state = new_state(self, input, output, count, parameters)
    return setmetatable({
        program = self, state = state, input_owner = input, output_owner = output,
    }, SeparateFrame)
end

function InPlaceFrame:execute()
    self.program.native:execute(self.state)
    return self
end

function SeparateFrame:execute()
    self.program.native:execute(self.state)
    return self
end

function Program:free() self.native:free() end

local Pipeline = {}

function Pipeline.add(value)
    return setmetatable({ value = finite_number(value, "add constant") }, AddConstant)
end

function Pipeline.multiply(value)
    return setmetatable({ value = finite_number(value, "multiply constant") }, MultiplyConstant)
end

function Pipeline.add_parameter(index)
    return setmetatable({ index = parameter_index(index) }, AddParameter)
end

function Pipeline.multiply_parameter(index)
    return setmetatable({ index = parameter_index(index) }, MultiplyParameter)
end

function Pipeline.square() return setmetatable({}, Square) end

local F64Config = {
    frame_type = "CopyPatchF64MapFrameV1", input_type = "const double *",
    output_type = "double *", element_size = 8, no_alias_label = "SeparateNoAliasF64",
}
local F32Config = {
    frame_type = "CopyPatchF32MapFrameV1", input_type = "const float *",
    output_type = "float *", element_size = 4, no_alias_label = "SeparateNoAliasF32",
}

local function compile(bank, operations, config)
    assert(type(operations) == "table" and #operations <= 64,
        "map pipeline supports at most 64 operations")
    local compiler = setmetatable({ bindings = {}, bound = {} }, Compiler)
    for index = 1, #operations do operations[index]:bind(compiler) end
    local native = bank:link(compiler.bound)
    return setmetatable({
        native = native, bindings = compiler.bindings, operations = operations,
        frame_type = config.frame_type, input_type = config.input_type,
        output_type = config.output_type, element_size = config.element_size,
        no_alias_label = config.no_alias_label,
    }, Program)
end

function Pipeline.compile(bank, operations) return compile(bank, operations, F64Config) end
function Pipeline.compile_f32(bank, operations) return compile(bank, operations, F32Config) end

function Pipeline.evaluate(operations, value, parameters)
    for index = 1, #operations do value = operations[index]:apply(value, parameters) end
    return value
end

return Pipeline
