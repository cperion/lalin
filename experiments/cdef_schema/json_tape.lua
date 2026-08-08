local ffi = require("ffi")
local schema = require("cdefschema")

local S = schema.context {
    name = "json-tape",
    version = 1,
    prefix = "JsonTapeV1_",
}

S:cdef [[
typedef struct {
    uint8_t kind;
    uint8_t flags;
    uint16_t reserved;
    uint32_t start;
    uint32_t length;
    uint32_t match;
    double number;
} JsonTapeV1_Token;

typedef struct {
    uint32_t start_token;
    uint8_t kind;
    uint8_t reserved[3];
} JsonTapeV1_Frame;

typedef struct {
    uint32_t source_start;
    uint32_t source_length;
    uint32_t output_start;
    uint32_t output_length;
    uint8_t decoded;
    uint8_t reserved[3];
} JsonTapeV1_StringMachine;

typedef struct {
    uint32_t start;
    uint32_t length;
    double value;
} JsonTapeV1_NumberMachine;

typedef struct {
    JsonTapeV1_StringMachine string_machine;
    JsonTapeV1_NumberMachine number_machine;
    const uint8_t *input;
    JsonTapeV1_Token *tape;
    uint8_t *strings;
    JsonTapeV1_Frame *stack;
    uint32_t input_length;
    uint32_t tape_capacity;
    uint32_t string_capacity;
    uint32_t stack_capacity;
    uint32_t position;
    uint32_t token_count;
    uint32_t string_length;
    uint32_t depth;
    uint32_t root_token;
    uint8_t expect;
    uint8_t reserved[3];
} JsonTapeV1_Decoder;

typedef struct {
    uint8_t code;
    uint8_t reserved[3];
    uint32_t position;
    uint32_t token_count;
    uint32_t string_length;
    uint32_t root_token;
} JsonTapeV1_Report;
 ]]

local Token = S:product("JsonTapeV1_Token")
local Frame = S:product("JsonTapeV1_Frame")
local StringMachine = S:product("JsonTapeV1_StringMachine")
local NumberMachine = S:product("JsonTapeV1_NumberMachine")
local Decoder = S:product("JsonTapeV1_Decoder")
local Report = S:product("JsonTapeV1_Report")

local TokenArray = ffi.typeof("JsonTapeV1_Token[?]")
local FrameArray = ffi.typeof("JsonTapeV1_Frame[?]")
local ByteArray = ffi.typeof("uint8_t[?]")
local BytePointer = ffi.typeof("uint8_t *")
local StringMachinePointer = ffi.typeof("JsonTapeV1_StringMachine *")
local NumberMachinePointer = ffi.typeof("JsonTapeV1_NumberMachine *")
local NUMBER_MACHINE_OFFSET = ffi.offsetof("JsonTapeV1_Decoder", "number_machine")

local NULL = 1
local FALSE = 2
local TRUE = 3
local NUMBER = 4
local STRING = 5
local ARRAY_START = 6
local ARRAY_END = 7
local OBJECT_START = 8
local OBJECT_END = 9

local OK = 0
local SYNTAX = 1
local TAPE_CAPACITY = 2
local STRING_CAPACITY = 3
local DEPTH_CAPACITY = 4
local UTF8 = 5

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
local DECODED_STRING = 1
local NO_MATCH = 0xffffffff

local function is_digit(byte) return byte >= 48 and byte <= 57 end

local function hex_value(byte)
    if byte >= 48 and byte <= 57 then return byte - 48 end
    if byte >= 65 and byte <= 70 then return byte - 55 end
    if byte >= 97 and byte <= 102 then return byte - 87 end
    return -1
end

local function utf8_width(input, position, length)
    local first = input[position]
    if first < 0x80 then return 1 end
    if first >= 0xc2 and first <= 0xdf then
        if position + 1 < length then
            local second = input[position + 1]
            if second >= 0x80 and second <= 0xbf then return 2 end
        end
        return 0
    end
    if first >= 0xe0 and first <= 0xef then
        if position + 2 >= length then return 0 end
        local second, third = input[position + 1], input[position + 2]
        if third < 0x80 or third > 0xbf then return 0 end
        if first == 0xe0 then
            if second >= 0xa0 and second <= 0xbf then return 3 end
        elseif first == 0xed then
            if second >= 0x80 and second <= 0x9f then return 3 end
        elseif second >= 0x80 and second <= 0xbf then
            return 3
        end
        return 0
    end
    if first >= 0xf0 and first <= 0xf4 then
        if position + 3 >= length then return 0 end
        local second = input[position + 1]
        local third, fourth = input[position + 2], input[position + 3]
        if third < 0x80 or third > 0xbf or fourth < 0x80 or fourth > 0xbf then return 0 end
        if first == 0xf0 then
            if second >= 0x90 and second <= 0xbf then return 4 end
        elseif first == 0xf4 then
            if second >= 0x80 and second <= 0x8f then return 4 end
        elseif second >= 0x80 and second <= 0xbf then
            return 4
        end
    end
    return 0
end

function Report:is_ok() return self.code == OK end
function Report:is_syntax() return self.code == SYNTAX end
function Report:is_tape_capacity() return self.code == TAPE_CAPACITY end
function Report:is_string_capacity() return self.code == STRING_CAPACITY end
function Report:is_depth_capacity() return self.code == DEPTH_CAPACITY end
function Report:is_utf8() return self.code == UTF8 end
function Report:error_position() return tonumber(self.position) end
function Report:tokens() return tonumber(self.token_count) end

function Decoder:failed(_input_owner, _tape_owner, _string_owner, _stack_owner, code, position)
    return Report {
        code = code,
        position = position,
        token_count = self.token_count,
        string_length = self.string_length,
        root_token = self.root_token,
    }
end

function Decoder:completed(_input_owner, _tape_owner, _string_owner, _stack_owner)
    return Report {
        code = OK,
        position = self.position,
        token_count = self.token_count,
        string_length = self.string_length,
        root_token = self.root_token,
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

local decoder_after_string_value
local decoder_after_key
local decoder_after_number

function Decoder:after_string_value(input_owner, tape_owner, string_owner, stack_owner)
    if self.token_count >= self.tape_capacity then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner,
            TAPE_CAPACITY, self.position)
    end
    local index = self.token_count
    local token = self.tape + index
    local string_machine = ffi.cast(StringMachinePointer, self)
    token.kind = STRING
    token.flags = string_machine.decoded ~= 0 and DECODED_STRING or 0
    if string_machine.decoded ~= 0 then
        token.start = string_machine.output_start
        token.length = string_machine.output_length
    else
        token.start = string_machine.source_start
        token.length = string_machine.source_length
    end
    self.token_count = index + 1
    set_after_value(self)
    return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
end

function Decoder:after_key(input_owner, tape_owner, string_owner, stack_owner)
    if self.token_count >= self.tape_capacity then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner,
            TAPE_CAPACITY, self.position)
    end
    local index = self.token_count
    local token = self.tape + index
    local string_machine = ffi.cast(StringMachinePointer, self)
    token.kind = STRING
    token.flags = string_machine.decoded ~= 0 and DECODED_STRING or 0
    if string_machine.decoded ~= 0 then
        token.start = string_machine.output_start
        token.length = string_machine.output_length
    else
        token.start = string_machine.source_start
        token.length = string_machine.source_length
    end
    self.token_count = index + 1
    self.expect = OBJECT_COLON
    return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
end

function Decoder:after_number(input_owner, tape_owner, string_owner, stack_owner)
    if self.token_count >= self.tape_capacity then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner,
            TAPE_CAPACITY, self.position)
    end
    local index = self.token_count
    local token = self.tape + index
    local number_machine = ffi.cast(NumberMachinePointer,
        ffi.cast(BytePointer, self) + NUMBER_MACHINE_OFFSET)
    token.kind = NUMBER
    token.number = number_machine.value
    self.token_count = index + 1
    set_after_value(self)
    return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
end

decoder_after_string_value = Decoder.after_string_value
decoder_after_key = Decoder.after_key
decoder_after_number = Decoder.after_number

function StringMachine:scan(input_owner, tape_owner, string_owner, stack_owner, parent, completed)
    self.source_start = parent.position + 1
    self.source_length = 0
    self.output_start = parent.string_length
    self.output_length = 0
    self.decoded = 0

    local position = parent.position + 1
    while position < parent.input_length do
        local byte = parent.input[position]
        if byte == 34 then
            if self.decoded ~= 0 then
                self.output_length = parent.string_length - self.output_start
            else
                self.source_length = position - self.source_start
            end
            parent.position = position + 1
            return completed(parent, input_owner, tape_owner, string_owner, stack_owner)
        elseif byte < 32 then
            return parent:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        elseif byte == 92 then
            if self.decoded == 0 then
                local prefix_length = position - self.source_start
                if parent.string_length + prefix_length > parent.string_capacity then
                    return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                        STRING_CAPACITY, position)
                end
                ffi.copy(parent.strings + parent.string_length,
                    parent.input + self.source_start, prefix_length)
                self.output_start = parent.string_length
                parent.string_length = parent.string_length + prefix_length
                self.decoded = 1
            end

            position = position + 1
            if position >= parent.input_length then
                return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                    SYNTAX, position)
            end
            local escaped = parent.input[position]
            local output_byte
            if escaped == 34 or escaped == 92 or escaped == 47 then
                output_byte = escaped
            elseif escaped == 98 then
                output_byte = 8
            elseif escaped == 102 then
                output_byte = 12
            elseif escaped == 110 then
                output_byte = 10
            elseif escaped == 114 then
                output_byte = 13
            elseif escaped == 116 then
                output_byte = 9
            elseif escaped == 117 then
                if position + 4 >= parent.input_length then
                    return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                        SYNTAX, position)
                end
                local h1 = hex_value(parent.input[position + 1])
                local h2 = hex_value(parent.input[position + 2])
                local h3 = hex_value(parent.input[position + 3])
                local h4 = hex_value(parent.input[position + 4])
                if h1 < 0 or h2 < 0 or h3 < 0 or h4 < 0 then
                    return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                        SYNTAX, position)
                end
                local codepoint = ((h1 * 16 + h2) * 16 + h3) * 16 + h4
                position = position + 4
                if codepoint >= 0xd800 and codepoint <= 0xdbff then
                    if position + 6 >= parent.input_length
                        or parent.input[position + 1] ~= 92
                        or parent.input[position + 2] ~= 117 then
                        return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                            SYNTAX, position)
                    end
                    local l1 = hex_value(parent.input[position + 3])
                    local l2 = hex_value(parent.input[position + 4])
                    local l3 = hex_value(parent.input[position + 5])
                    local l4 = hex_value(parent.input[position + 6])
                    if l1 < 0 or l2 < 0 or l3 < 0 or l4 < 0 then
                        return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                            SYNTAX, position)
                    end
                    local low = ((l1 * 16 + l2) * 16 + l3) * 16 + l4
                    if low < 0xdc00 or low > 0xdfff then
                        return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                            SYNTAX, position)
                    end
                    codepoint = 0x10000 + (codepoint - 0xd800) * 0x400 + (low - 0xdc00)
                    position = position + 6
                elseif codepoint >= 0xdc00 and codepoint <= 0xdfff then
                    return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                        SYNTAX, position)
                end

                local width = codepoint < 0x80 and 1
                    or (codepoint < 0x800 and 2 or (codepoint < 0x10000 and 3 or 4))
                if parent.string_length + width > parent.string_capacity then
                    return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                        STRING_CAPACITY, position)
                end
                local output = parent.string_length
                if width == 1 then
                    parent.strings[output] = codepoint
                elseif width == 2 then
                    parent.strings[output] = 0xc0 + math.floor(codepoint / 0x40)
                    parent.strings[output + 1] = 0x80 + codepoint % 0x40
                elseif width == 3 then
                    parent.strings[output] = 0xe0 + math.floor(codepoint / 0x1000)
                    parent.strings[output + 1] = 0x80 + math.floor(codepoint / 0x40) % 0x40
                    parent.strings[output + 2] = 0x80 + codepoint % 0x40
                else
                    parent.strings[output] = 0xf0 + math.floor(codepoint / 0x40000)
                    parent.strings[output + 1] = 0x80 + math.floor(codepoint / 0x1000) % 0x40
                    parent.strings[output + 2] = 0x80 + math.floor(codepoint / 0x40) % 0x40
                    parent.strings[output + 3] = 0x80 + codepoint % 0x40
                end
                parent.string_length = output + width
                position = position + 1
            else
                return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                    SYNTAX, position)
            end

            if output_byte ~= nil then
                if parent.string_length >= parent.string_capacity then
                    return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                        STRING_CAPACITY, position)
                end
                parent.strings[parent.string_length] = output_byte
                parent.string_length = parent.string_length + 1
                position = position + 1
            end
        else
            local width = 1
            if byte >= 128 then
                width = utf8_width(parent.input, position, parent.input_length)
            end
            if width == 0 then
                return parent:failed(input_owner, tape_owner, string_owner, stack_owner, UTF8, position)
            end
            if self.decoded ~= 0 then
                if parent.string_length + width > parent.string_capacity then
                    return parent:failed(input_owner, tape_owner, string_owner, stack_owner,
                        STRING_CAPACITY, position)
                end
                ffi.copy(parent.strings + parent.string_length, parent.input + position, width)
                parent.string_length = parent.string_length + width
            end
            position = position + width
        end
    end

    return parent:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
end

function NumberMachine:scan(input_owner, tape_owner, string_owner, stack_owner, parent, completed)
    local position = parent.position
    local start = position
    local sign = 1
    if parent.input[position] == 45 then
        sign = -1
        position = position + 1
        if position >= parent.input_length then
            return parent:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
    end

    local value = 0
    local byte = parent.input[position]
    if byte == 48 then
        position = position + 1
    elseif byte >= 49 and byte <= 57 then
        repeat
            value = value * 10 + (parent.input[position] - 48)
            position = position + 1
        until position >= parent.input_length or not is_digit(parent.input[position])
    else
        return parent:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
    end

    if position < parent.input_length and parent.input[position] == 46 then
        position = position + 1
        if position >= parent.input_length or not is_digit(parent.input[position]) then
            return parent:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
        local scale = 0.1
        repeat
            value = value + (parent.input[position] - 48) * scale
            scale = scale * 0.1
            position = position + 1
        until position >= parent.input_length or not is_digit(parent.input[position])
    end

    if position < parent.input_length
        and (parent.input[position] == 101 or parent.input[position] == 69) then
        position = position + 1
        local exponent_sign = 1
        if position < parent.input_length and parent.input[position] == 43 then
            position = position + 1
        elseif position < parent.input_length and parent.input[position] == 45 then
            exponent_sign = -1
            position = position + 1
        end
        if position >= parent.input_length or not is_digit(parent.input[position]) then
            return parent:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
        local exponent = 0
        repeat
            if exponent < 10000 then exponent = exponent * 10 + (parent.input[position] - 48) end
            position = position + 1
        until position >= parent.input_length or not is_digit(parent.input[position])
        value = value * (10 ^ (exponent_sign * exponent))
    end

    self.start = start
    self.length = position - start
    self.value = sign * value
    parent.position = position
    return completed(parent, input_owner, tape_owner, string_owner, stack_owner)
end

function Decoder:cycle(input_owner, tape_owner, string_owner, stack_owner)
    local position = self.position
    if position < self.input_length then
        local byte = self.input[position]
        if byte == 32 or byte == 9 or byte == 10 or byte == 13 then
            repeat
                position = position + 1
                if position >= self.input_length then
                    self.position = position
                    return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
                end
                byte = self.input[position]
            until byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13
            self.position = position
            return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
        end
    end

    local expect = self.expect
    if expect == DONE then
        if position == self.input_length then
            return self:completed(input_owner, tape_owner, string_owner, stack_owner)
        end
        return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
    end

    if expect == ARRAY_FIRST then
        if position < self.input_length and self.input[position] == 93 then
            return self:close_array(input_owner, tape_owner, string_owner, stack_owner)
        end
        self.expect = ARRAY_VALUE
        return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
    end

    if expect == OBJECT_FIRST then
        if position < self.input_length and self.input[position] == 125 then
            return self:close_object(input_owner, tape_owner, string_owner, stack_owner)
        end
        self.expect = OBJECT_KEY
        return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
    end

    if expect == OBJECT_KEY then
        if position >= self.input_length or self.input[position] ~= 34 then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
        local string_machine = ffi.cast(StringMachinePointer, self)
        return string_machine:scan(input_owner, tape_owner, string_owner, stack_owner,
            self, decoder_after_key)
    end

    if expect == OBJECT_COLON then
        if position >= self.input_length or self.input[position] ~= 58 then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
        self.position = position + 1
        self.expect = OBJECT_VALUE
        return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
    end

    if expect == ARRAY_AFTER then
        if position < self.input_length and self.input[position] == 44 then
            self.position = position + 1
            self.expect = ARRAY_VALUE
            return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
        end
        if position < self.input_length and self.input[position] == 93 then
            return self:close_array(input_owner, tape_owner, string_owner, stack_owner)
        end
        return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
    end

    if expect == OBJECT_AFTER then
        if position < self.input_length and self.input[position] == 44 then
            self.position = position + 1
            self.expect = OBJECT_KEY
            return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
        end
        if position < self.input_length and self.input[position] == 125 then
            return self:close_object(input_owner, tape_owner, string_owner, stack_owner)
        end
        return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
    end

    if position >= self.input_length then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
    end

    local byte = self.input[position]
    if byte == 34 then
        local string_machine = ffi.cast(StringMachinePointer, self)
        return string_machine:scan(input_owner, tape_owner, string_owner, stack_owner,
            self, decoder_after_string_value)
    end
    if byte == 45 or is_digit(byte) then
        local number_machine = ffi.cast(NumberMachinePointer,
            ffi.cast(BytePointer, self) + NUMBER_MACHINE_OFFSET)
        return number_machine:scan(input_owner, tape_owner, string_owner, stack_owner,
            self, decoder_after_number)
    end

    if byte == 110 then
        if position + 3 >= self.input_length
            or self.input[position + 1] ~= 117
            or self.input[position + 2] ~= 108
            or self.input[position + 3] ~= 108 then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
        if self.token_count >= self.tape_capacity then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner,
                TAPE_CAPACITY, position)
        end
        local token = self.tape + self.token_count
        token.kind = NULL
        self.token_count = self.token_count + 1
        self.position = position + 4
        set_after_value(self)
        return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
    end

    if byte == 116 then
        if position + 3 >= self.input_length
            or self.input[position + 1] ~= 114
            or self.input[position + 2] ~= 117
            or self.input[position + 3] ~= 101 then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
        if self.token_count >= self.tape_capacity then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner,
                TAPE_CAPACITY, position)
        end
        local token = self.tape + self.token_count
        token.kind = TRUE
        self.token_count = self.token_count + 1
        self.position = position + 4
        set_after_value(self)
        return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
    end

    if byte == 102 then
        if position + 4 >= self.input_length
            or self.input[position + 1] ~= 97
            or self.input[position + 2] ~= 108
            or self.input[position + 3] ~= 115
            or self.input[position + 4] ~= 101 then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
        end
        if self.token_count >= self.tape_capacity then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner,
                TAPE_CAPACITY, position)
        end
        local token = self.tape + self.token_count
        token.kind = FALSE
        self.token_count = self.token_count + 1
        self.position = position + 5
        set_after_value(self)
        return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
    end

    if byte == 91 or byte == 123 then
        if self.depth >= self.stack_capacity then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner,
                DEPTH_CAPACITY, position)
        end
        if self.token_count >= self.tape_capacity then
            return self:failed(input_owner, tape_owner, string_owner, stack_owner,
                TAPE_CAPACITY, position)
        end
        local token_index = self.token_count
        local token = self.tape + token_index
        local frame = self.stack + self.depth
        if byte == 91 then
            token.kind = ARRAY_START
            frame.kind = FRAME_ARRAY
            self.expect = ARRAY_FIRST
        else
            token.kind = OBJECT_START
            frame.kind = FRAME_OBJECT
            self.expect = OBJECT_FIRST
        end
        token.match = NO_MATCH
        frame.start_token = token_index
        self.token_count = token_index + 1
        self.depth = self.depth + 1
        self.position = position + 1
        return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
    end

    return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
end

function Decoder:close_array(input_owner, tape_owner, string_owner, stack_owner)
    local position = self.position
    if self.depth == 0 or self.stack[self.depth - 1].kind ~= FRAME_ARRAY then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
    end
    if self.token_count >= self.tape_capacity then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner,
            TAPE_CAPACITY, position)
    end
    local start_index = self.stack[self.depth - 1].start_token
    local end_index = self.token_count
    local token = self.tape + end_index
    token.kind, token.match = ARRAY_END, start_index
    self.tape[start_index].match = end_index
    self.token_count = end_index + 1
    self.depth = self.depth - 1
    self.position = position + 1
    set_after_value(self)
    return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
end

function Decoder:close_object(input_owner, tape_owner, string_owner, stack_owner)
    local position = self.position
    if self.depth == 0 or self.stack[self.depth - 1].kind ~= FRAME_OBJECT then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner, SYNTAX, position)
    end
    if self.token_count >= self.tape_capacity then
        return self:failed(input_owner, tape_owner, string_owner, stack_owner,
            TAPE_CAPACITY, position)
    end
    local start_index = self.stack[self.depth - 1].start_token
    local end_index = self.token_count
    local token = self.tape + end_index
    token.kind, token.match = OBJECT_END, start_index
    self.tape[start_index].match = end_index
    self.token_count = end_index + 1
    self.depth = self.depth - 1
    self.position = position + 1
    set_after_value(self)
    return self:cycle(input_owner, tape_owner, string_owner, stack_owner)
end

function Decoder:decode(input_owner, tape_owner, tape_capacity, string_owner, string_capacity,
        stack_owner, stack_capacity)
    self.input = ffi.cast("const uint8_t *", input_owner)
    self.tape = ffi.cast("JsonTapeV1_Token *", tape_owner)
    self.strings = ffi.cast("uint8_t *", string_owner)
    self.stack = ffi.cast("JsonTapeV1_Frame *", stack_owner)
    self.input_length = #input_owner
    self.tape_capacity = tape_capacity
    self.string_capacity = string_capacity
    self.stack_capacity = stack_capacity
    self.position = 0
    self.token_count = 0
    self.string_length = 0
    self.depth = 0
    self.root_token = 0
    self.expect = ROOT_VALUE

    local report = self:cycle(input_owner, tape_owner, string_owner, stack_owner)

    self.input = nil
    self.tape = nil
    self.strings = nil
    self.stack = nil
    return report
end

S:seal()

local null = setmetatable({}, { __tostring = function() return "json.null" end })

local Result = {}
Result.__index = Result

function Result:is_ok() return self.report:is_ok() end
function Result:error_position() return self.report:error_position() end
function Result:token_count() return self.report:tokens() end

function Result:string_at(index)
    local token = self.tape[index]
    local pointer
    if token.flags == DECODED_STRING then
        pointer = ffi.cast("const char *", self.strings) + token.start
    else
        pointer = ffi.cast("const char *", self.input) + token.start
    end
    return ffi.string(pointer, token.length)
end

local function materialize_at(result, index)
    local token = result.tape[index]
    local kind = token.kind
    if kind == NULL then return null, index + 1 end
    if kind == FALSE then return false, index + 1 end
    if kind == TRUE then return true, index + 1 end
    if kind == NUMBER then return tonumber(token.number), index + 1 end
    if kind == STRING then return result:string_at(index), index + 1 end
    if kind == ARRAY_START then
        local output = {}
        local next_index = index + 1
        local finish = tonumber(token.match)
        while next_index < finish do
            local value
            value, next_index = materialize_at(result, next_index)
            output[#output + 1] = value
        end
        return output, finish + 1
    end
    if kind == OBJECT_START then
        local output = {}
        local next_index = index + 1
        local finish = tonumber(token.match)
        while next_index < finish do
            local key = result:string_at(next_index)
            local value
            value, next_index = materialize_at(result, next_index + 1)
            output[key] = value
        end
        return output, finish + 1
    end
    error("invalid JSON tape token kind: " .. tonumber(kind))
end

function Result:materialize()
    assert(self:is_ok(), "cannot materialize failed JSON decode")
    local value, next_index = materialize_at(self, tonumber(self.report.root_token))
    assert(next_index == self.report.token_count)
    return value
end

local Workspace = {}
Workspace.__index = Workspace

function Workspace:decode(input)
    assert(type(input) == "string", "JSON input must be a string")
    assert(#input <= self.max_bytes, "JSON input exceeds workspace capacity")
    local report = self.decoder:decode(input, self.tape, self.tape_capacity,
        self.strings, self.string_capacity, self.stack, self.stack_capacity)
    return setmetatable({
        report = report,
        input = input,
        tape = self.tape,
        strings = self.strings,
        workspace = self,
    }, Result)
end

local M = {
    null = null,
    kinds = {
        null = NULL, false_value = FALSE, true_value = TRUE, number = NUMBER, string = STRING,
        array_start = ARRAY_START, array_end = ARRAY_END,
        object_start = OBJECT_START, object_end = OBJECT_END,
    },
    errors = {
        ok = OK, syntax = SYNTAX, tape_capacity = TAPE_CAPACITY,
        string_capacity = STRING_CAPACITY, depth_capacity = DEPTH_CAPACITY, utf8 = UTF8,
    },
    Decoder = Decoder, Report = Report, Token = Token, Frame = Frame,
    StringMachine = StringMachine, NumberMachine = NumberMachine,
}

function M.workspace(max_bytes, max_depth)
    assert(type(max_bytes) == "number" and max_bytes >= 0)
    max_depth = max_depth or 1024
    assert(type(max_depth) == "number" and max_depth >= 1)
    local tape_capacity = math.max(1, max_bytes + 1)
    local string_capacity = math.max(1, max_bytes + 1)
    return setmetatable({
        decoder = Decoder(),
        tape = ffi.new(TokenArray, tape_capacity),
        strings = ffi.new(ByteArray, string_capacity),
        stack = ffi.new(FrameArray, max_depth),
        tape_capacity = tape_capacity,
        string_capacity = string_capacity,
        stack_capacity = max_depth,
        max_bytes = max_bytes,
    }, Workspace)
end

function M.decode(input, max_depth)
    return M.workspace(#input, max_depth):decode(input)
end

return M

