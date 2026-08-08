-- Runtime-created fused array kernels.
--
-- The operation objects exist only while the exotype is staged. Each concrete
-- operation leaf contributes directly to one specialized C loop. Native execution
-- receives pointers, a count, and a parameter array; no operation objects survive.

local P = require("experiments.exotype_c_emit.protocol")

local Kernel = {}

local Abi = {}
Abi.__index = Abi
local ModuleQuote = {}
ModuleQuote.__index = ModuleQuote

Kernel.Abi = Abi
Kernel.ModuleQuote = ModuleQuote
Kernel.AbiProperty = P.property("KernelAbi", Abi)
Kernel.ModuleProperty = P.property("KernelCModule", ModuleQuote)

local F32 = {}
local F64 = {}
F32.__index = F32
F64.__index = F64
Kernel.f32 = setmetatable({}, F32)
Kernel.f64 = setmetatable({}, F64)

function F32:key() return "f32" end
function F32:c_type() return "float" end
function F32:ffi_type() return "float" end
function F32:literal(value)
    local text = ("%.9g"):format(value)
    if not text:find("[%.eE]") then text = text .. ".0" end
    return text .. "f"
end

function F64:key() return "f64" end
function F64:c_type() return "double" end
function F64:ffi_type() return "double" end
function F64:literal(value) return ("%.17g"):format(value) end

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

local function finite_number(value)
    assert(type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge, "kernel constant must be finite")
    return value
end

local function parameter_index(value)
    assert(type(value) == "number" and value >= 0 and value == math.floor(value),
        "kernel parameter index must be a nonnegative integer")
    return value
end

function Kernel.add(value) return setmetatable({ value = finite_number(value) }, AddConstant) end
function Kernel.multiply(value) return setmetatable({ value = finite_number(value) }, MultiplyConstant) end
function Kernel.add_parameter(index) return setmetatable({ index = parameter_index(index) }, AddParameter) end
function Kernel.multiply_parameter(index)
    return setmetatable({ index = parameter_index(index) }, MultiplyParameter)
end
function Kernel.square() return setmetatable({}, Square) end

function AddConstant:key() return ("add:%.17g"):format(self.value) end
function MultiplyConstant:key() return ("multiply:%.17g"):format(self.value) end
function AddParameter:key() return "add_parameter:" .. self.index end
function MultiplyParameter:key() return "multiply_parameter:" .. self.index end
function Square:key() return "square" end

function AddConstant:parameter_count() return 0 end
function MultiplyConstant:parameter_count() return 0 end
function AddParameter:parameter_count() return self.index + 1 end
function MultiplyParameter:parameter_count() return self.index + 1 end
function Square:parameter_count() return 0 end

function AddConstant:emit(lines, element)
    lines[#lines + 1] = "        value += " .. element:literal(self.value) .. ";"
end

function MultiplyConstant:emit(lines, element)
    lines[#lines + 1] = "        value *= " .. element:literal(self.value) .. ";"
end

function AddParameter:emit(lines)
    lines[#lines + 1] = ("        value += parameters[%d];"):format(self.index)
end

function MultiplyParameter:emit(lines)
    lines[#lines + 1] = ("        value *= parameters[%d];"):format(self.index)
end

function Square:emit(lines) lines[#lines + 1] = "        value *= value;" end

function Abi:ffi_declaration(symbol)
    return ("void %s(%s *output, const %s *input, uint64_t count, const %s *parameters);"):format(
        symbol, self.ffi_type, self.ffi_type, self.ffi_type)
end

local function structural_token(value)
    local hash = 0
    for index = 1, #value do hash = (hash * 131 + value:byte(index)) % 4294967296 end
    return ("%08x"):format(hash)
end

local constructor_cache = {}
local owner_count = 0

function Kernel.type(element, operations)
    assert(element == Kernel.f32 or element == Kernel.f64, "kernel requires the f32 or f64 element leaf")
    assert(type(operations) == "table" and #operations > 0, "kernel requires at least one operation")

    local keys = { element:key() }
    local parameter_count = 0
    for index = 1, #operations do
        local operation = operations[index]
        assert(type(operation.key) == "function" and type(operation.emit) == "function",
            "kernel operation must be a concrete operation leaf")
        keys[#keys + 1] = operation:key()
        parameter_count = math.max(parameter_count, operation:parameter_count())
    end
    local key = table.concat(keys, ",")
    if constructor_cache[key] ~= nil then return constructor_cache[key] end

    owner_count = owner_count + 1
    local token = structural_token(key)
    local symbol = "exotype_array_kernel_" .. token
    local owner
    local properties = {}

    properties[Kernel.AbiProperty] = function()
        return setmetatable({
            ffi_type = element:ffi_type(),
            element_size = element == Kernel.f32 and 4 or 8,
            parameter_count = parameter_count,
        }, Abi)
    end

    properties[Kernel.ModuleProperty] = function(compiler)
        local abi = P.query(compiler, owner, Kernel.AbiProperty)
        local c_type = element:c_type()
        local lines = {
            "#include <stdint.h>",
            ("void %s(%s *restrict output, const %s *restrict input,"):format(
                symbol, c_type, c_type),
            ("        uint64_t count, const %s *restrict parameters) {"):format(c_type),
            "    for (uint64_t index = 0; index < count; index++) {",
            ("        %s value = input[index];"):format(c_type),
        }
        for index = 1, #operations do operations[index]:emit(lines, element) end
        lines[#lines + 1] = "        output[index] = value;"
        lines[#lines + 1] = "    }"
        lines[#lines + 1] = "}"
        return setmetatable({
            source = table.concat(lines, "\n"),
            symbol = symbol,
            token = token,
            abi = abi,
            operation_count = #operations,
        }, ModuleQuote)
    end

    owner = P.owner("ArrayKernel" .. owner_count, properties, operations)
    owner.artifact_key = token
    constructor_cache[key] = owner
    return owner
end

return Kernel
