local ffi = require("ffi")
local schema = require("cdefschema")
local TapeJson = require("experiments.cdef_schema.json_tape")

local S = schema.context {
    name = "json-direct",
    version = 1,
    prefix = "JsonDirectV1_",
}

S:cdef [[
typedef struct {
    JsonTapeV1_StringMachine string_machine;
    JsonTapeV1_NumberMachine number_machine;
    const uint8_t *input;
    uint8_t *strings;
    JsonTapeV1_Frame *stack;
    uint32_t input_length;
    uint32_t string_capacity;
    uint32_t stack_capacity;
    uint32_t position;
    uint32_t string_length;
    uint32_t depth;
    uint8_t expect;
    uint8_t reserved[3];
} JsonDirectV1_Decoder;
 ]]

local Decoder = S:product("JsonDirectV1_Decoder")
local FrameArray = ffi.typeof("JsonTapeV1_Frame[?]")
local ByteArray = ffi.typeof("uint8_t[?]")
local BytePointer = ffi.typeof("uint8_t *")
local StringMachinePointer = ffi.typeof("JsonTapeV1_StringMachine *")
local NumberMachinePointer = ffi.typeof("JsonTapeV1_NumberMachine *")
local NUMBER_MACHINE_OFFSET = ffi.offsetof("JsonDirectV1_Decoder", "number_machine")

local OK = TapeJson.errors.ok
local SYNTAX = TapeJson.errors.syntax
local STRING_CAPACITY = TapeJson.errors.string_capacity
local DEPTH_CAPACITY = TapeJson.errors.depth_capacity

local ROOT_VALUE = 1
local ARRAY_FIRST = 2
local ARRAY_VALUE = 3
local ARRAY_AFTER = 4
local OBJECT_FIRST = 5
local OBJECT_KEY = 6
local OBJECT_COLON = 7
local OBJECT_VALUE = 8
local OBJECT_AFTER = 9
local DONE = 10

local FRAME_ARRAY = 1
local FRAME_OBJECT = 2

local function is_digit(byte) return byte >= 48 and byte <= 57 end

function Decoder:failed(_input_owner, _builder, _string_owner, _stack_owner, code, position)
    return TapeJson.Report {
        code = code,
        position = position,
        token_count = 0,
        string_length = self.string_length,
        root_token = 0,
    }
end

function Decoder:completed(_input_owner, _builder, _string_owner, _stack_owner)
    return TapeJson.Report {
        code = OK,
        position = self.position,
        token_count = 0,
        string_length = self.string_length,
        root_token = 0,
    }
end

local function set_after_value(self)
    if self.depth == 0 then
        self.expect = DONE
    elseif self.stack[self.depth - 1].kind == FRAME_ARRAY then
        self.expect = ARRAY_AFTER
    else
        self.expect = OBJECT_AFTER
    end
end

local function attach_value(self, builder, value)
    local depth = self.depth
    if depth == 0 then
        builder.root = value
    elseif self.stack[depth - 1].kind == FRAME_ARRAY then
        local container = builder.containers[depth]
        container[#container + 1] = value
    else
        local key = builder.keys[depth]
        builder.containers[depth][key] = value
        builder.keys[depth] = nil
    end
end

local function decoded_string(self, input_owner, string_owner)
    local string_machine = ffi.cast(StringMachinePointer, self)
    if string_machine.decoded ~= 0 then
        return ffi.string(ffi.cast("const char *", string_owner) + string_machine.output_start,
            string_machine.output_length)
    end
    return input_owner:sub(string_machine.source_start + 1,
        string_machine.source_start + string_machine.source_length)
end

local after_string_value
local after_key
local after_number

function Decoder:after_string_value(input_owner, builder, string_owner, stack_owner)
    local value = decoded_string(self, input_owner, string_owner)
    local depth = self.depth
    if depth == 0 then
        builder.root = value
        self.expect = DONE
    elseif self.stack[depth - 1].kind == FRAME_ARRAY then
        local container = builder.containers[depth]
        container[#container + 1] = value
        self.expect = ARRAY_AFTER
    else
        builder.containers[depth][builder.keys[depth]] = value
        builder.keys[depth] = nil
        self.expect = OBJECT_AFTER
    end
    return self:cycle(input_owner, builder, string_owner, stack_owner)
end

function Decoder:after_key(input_owner, builder, string_owner, stack_owner)
    builder.keys[self.depth] = decoded_string(self, input_owner, string_owner)
    self.expect = OBJECT_COLON
    return self:cycle(input_owner, builder, string_owner, stack_owner)
end

function Decoder:after_number(input_owner, builder, string_owner, stack_owner)
    local number_machine = ffi.cast(NumberMachinePointer,
        ffi.cast(BytePointer, self) + NUMBER_MACHINE_OFFSET)
    local value = tonumber(number_machine.value)
    local depth = self.depth
    if depth == 0 then
        builder.root = value
        self.expect = DONE
    elseif self.stack[depth - 1].kind == FRAME_ARRAY then
        local container = builder.containers[depth]
        container[#container + 1] = value
        self.expect = ARRAY_AFTER
    else
        builder.containers[depth][builder.keys[depth]] = value
        builder.keys[depth] = nil
        self.expect = OBJECT_AFTER
    end
    return self:cycle(input_owner, builder, string_owner, stack_owner)
end

after_string_value = Decoder.after_string_value
after_key = Decoder.after_key
after_number = Decoder.after_number

function Decoder:cycle(input_owner, builder, string_owner, stack_owner)
    local position = self.position
    if position < self.input_length then
        local byte = self.input[position]
        if byte == 32 or byte == 9 or byte == 10 or byte == 13 then
            repeat
                position = position + 1
                if position >= self.input_length then
                    self.position = position
                    return self:cycle(input_owner, builder, string_owner, stack_owner)
                end
                byte = self.input[position]
            until byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13
            self.position = position
            return self:cycle(input_owner, builder, string_owner, stack_owner)
        end
    end

    local expect = self.expect
    if expect == DONE then
        if position == self.input_length then
            return self:completed(input_owner, builder, string_owner, stack_owner)
        end
        return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
    end

    if expect == ARRAY_FIRST then
        if position < self.input_length and self.input[position] == 93 then
            return self:close_array(input_owner, builder, string_owner, stack_owner)
        end
        self.expect = ARRAY_VALUE
        return self:cycle(input_owner, builder, string_owner, stack_owner)
    end

    if expect == OBJECT_FIRST then
        if position < self.input_length and self.input[position] == 125 then
            return self:close_object(input_owner, builder, string_owner, stack_owner)
        end
        self.expect = OBJECT_KEY
        return self:cycle(input_owner, builder, string_owner, stack_owner)
    end

    if expect == OBJECT_KEY then
        if position >= self.input_length or self.input[position] ~= 34 then
            return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
        end
        local string_machine = ffi.cast(StringMachinePointer, self)
        return string_machine:scan(input_owner, builder, string_owner, stack_owner, self, after_key)
    end

    if expect == OBJECT_COLON then
        if position >= self.input_length or self.input[position] ~= 58 then
            return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
        end
        self.position = position + 1
        self.expect = OBJECT_VALUE
        return self:cycle(input_owner, builder, string_owner, stack_owner)
    end

    if expect == ARRAY_AFTER then
        if position < self.input_length and self.input[position] == 44 then
            self.position = position + 1
            self.expect = ARRAY_VALUE
            return self:cycle(input_owner, builder, string_owner, stack_owner)
        end
        if position < self.input_length and self.input[position] == 93 then
            return self:close_array(input_owner, builder, string_owner, stack_owner)
        end
        return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
    end

    if expect == OBJECT_AFTER then
        if position < self.input_length and self.input[position] == 44 then
            self.position = position + 1
            self.expect = OBJECT_KEY
            return self:cycle(input_owner, builder, string_owner, stack_owner)
        end
        if position < self.input_length and self.input[position] == 125 then
            return self:close_object(input_owner, builder, string_owner, stack_owner)
        end
        return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
    end

    if position >= self.input_length then
        return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
    end

    local byte = self.input[position]
    if byte == 34 then
        local string_machine = ffi.cast(StringMachinePointer, self)
        return string_machine:scan(input_owner, builder, string_owner, stack_owner,
            self, after_string_value)
    end
    if byte == 45 or is_digit(byte) then
        local number_machine = ffi.cast(NumberMachinePointer,
            ffi.cast(BytePointer, self) + NUMBER_MACHINE_OFFSET)
        return number_machine:scan(input_owner, builder, string_owner, stack_owner,
            self, after_number)
    end

    if byte == 110 then
        if position + 3 >= self.input_length
            or self.input[position + 1] ~= 117
            or self.input[position + 2] ~= 108
            or self.input[position + 3] ~= 108 then
            return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
        end
        local depth = self.depth
        if depth == 0 then
            builder.root = TapeJson.null
            self.expect = DONE
        elseif self.stack[depth - 1].kind == FRAME_ARRAY then
            local container = builder.containers[depth]
            container[#container + 1] = TapeJson.null
            self.expect = ARRAY_AFTER
        else
            builder.containers[depth][builder.keys[depth]] = TapeJson.null
            builder.keys[depth] = nil
            self.expect = OBJECT_AFTER
        end
        self.position = position + 4
        return self:cycle(input_owner, builder, string_owner, stack_owner)
    end

    if byte == 116 then
        if position + 3 >= self.input_length
            or self.input[position + 1] ~= 114
            or self.input[position + 2] ~= 117
            or self.input[position + 3] ~= 101 then
            return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
        end
        local depth = self.depth
        if depth == 0 then
            builder.root = true
            self.expect = DONE
        elseif self.stack[depth - 1].kind == FRAME_ARRAY then
            local container = builder.containers[depth]
            container[#container + 1] = true
            self.expect = ARRAY_AFTER
        else
            builder.containers[depth][builder.keys[depth]] = true
            builder.keys[depth] = nil
            self.expect = OBJECT_AFTER
        end
        self.position = position + 4
        return self:cycle(input_owner, builder, string_owner, stack_owner)
    end

    if byte == 102 then
        if position + 4 >= self.input_length
            or self.input[position + 1] ~= 97
            or self.input[position + 2] ~= 108
            or self.input[position + 3] ~= 115
            or self.input[position + 4] ~= 101 then
            return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
        end
        local depth = self.depth
        if depth == 0 then
            builder.root = false
            self.expect = DONE
        elseif self.stack[depth - 1].kind == FRAME_ARRAY then
            local container = builder.containers[depth]
            container[#container + 1] = false
            self.expect = ARRAY_AFTER
        else
            builder.containers[depth][builder.keys[depth]] = false
            builder.keys[depth] = nil
            self.expect = OBJECT_AFTER
        end
        self.position = position + 5
        return self:cycle(input_owner, builder, string_owner, stack_owner)
    end

    if byte == 91 or byte == 123 then
        if self.depth >= self.stack_capacity then
            return self:failed(input_owner, builder, string_owner, stack_owner,
                DEPTH_CAPACITY, position)
        end
        local depth = self.depth
        local value = {}
        attach_value(self, builder, value)
        builder.containers[depth + 1] = value
        if byte == 91 then
            self.stack[depth].kind = FRAME_ARRAY
            self.expect = ARRAY_FIRST
        else
            self.stack[depth].kind = FRAME_OBJECT
            self.expect = OBJECT_FIRST
        end
        self.depth = depth + 1
        self.position = position + 1
        return self:cycle(input_owner, builder, string_owner, stack_owner)
    end

    return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
end

function Decoder:close_array(input_owner, builder, string_owner, stack_owner)
    local position = self.position
    if self.depth == 0 or self.stack[self.depth - 1].kind ~= FRAME_ARRAY then
        return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
    end
    builder.containers[self.depth] = nil
    builder.keys[self.depth] = nil
    self.depth = self.depth - 1
    self.position = position + 1
    set_after_value(self)
    return self:cycle(input_owner, builder, string_owner, stack_owner)
end

function Decoder:close_object(input_owner, builder, string_owner, stack_owner)
    local position = self.position
    if self.depth == 0 or self.stack[self.depth - 1].kind ~= FRAME_OBJECT then
        return self:failed(input_owner, builder, string_owner, stack_owner, SYNTAX, position)
    end
    builder.containers[self.depth] = nil
    builder.keys[self.depth] = nil
    self.depth = self.depth - 1
    self.position = position + 1
    set_after_value(self)
    return self:cycle(input_owner, builder, string_owner, stack_owner)
end

function Decoder:decode(input_owner, builder, string_owner, string_capacity, stack_owner, stack_capacity)
    self.input = ffi.cast("const uint8_t *", input_owner)
    self.strings = ffi.cast("uint8_t *", string_owner)
    self.stack = ffi.cast("JsonTapeV1_Frame *", stack_owner)
    self.input_length = #input_owner
    self.string_capacity = string_capacity
    self.stack_capacity = stack_capacity
    self.position = 0
    self.string_length = 0
    self.depth = 0
    self.expect = ROOT_VALUE
    builder.root = TapeJson.null

    local report = self:cycle(input_owner, builder, string_owner, stack_owner)

    self.input = nil
    self.strings = nil
    self.stack = nil
    return report
end

S:seal()

local Result = {}
Result.__index = Result
function Result:is_ok() return self.report:is_ok() end
function Result:error_position() return self.report:error_position() end
function Result:materialize()
    assert(self:is_ok(), "cannot materialize failed direct JSON decode")
    return self.value
end

local Workspace = {}
Workspace.__index = Workspace

function Workspace:decode(input)
    assert(type(input) == "string", "JSON input must be a string")
    assert(#input <= self.max_bytes, "JSON input exceeds workspace capacity")
    local builder = { root = TapeJson.null, containers = {}, keys = {} }
    local report = self.decoder:decode(input, builder, self.strings, self.string_capacity,
        self.stack, self.stack_capacity)
    return setmetatable({ report = report, value = builder.root }, Result)
end

local M = { null = TapeJson.null, Decoder = Decoder, Report = TapeJson.Report }

function M.workspace(max_bytes, max_depth)
    assert(type(max_bytes) == "number" and max_bytes >= 0)
    max_depth = max_depth or 1024
    assert(type(max_depth) == "number" and max_depth >= 1)
    local string_capacity = math.max(1, max_bytes + 1)
    return setmetatable({
        decoder = Decoder(),
        strings = ffi.new(ByteArray, string_capacity),
        stack = ffi.new(FrameArray, max_depth),
        string_capacity = string_capacity,
        stack_capacity = max_depth,
        max_bytes = max_bytes,
    }, Workspace)
end

function M.decode(input, max_depth)
    return M.workspace(#input, max_depth):decode(input)
end

return M

