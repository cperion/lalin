local ffi = require("ffi")
local schema = require("cdefschema")

local S = schema.context {
    name = "cps-csv-scanner",
    version = 1,
    prefix = "CpsCsvV1_",
}

S:cdef [[
typedef struct { int64_t values[65536]; uint32_t count; } CpsCsvV1_Output;
typedef struct { uint32_t position; uint32_t code; } CpsCsvV1_Error;
typedef union { CpsCsvV1_Output output; CpsCsvV1_Error error; } CpsCsvV1_Payload;
typedef struct { uint8_t kind; CpsCsvV1_Payload payload; } CpsCsvV1_Report;

typedef struct {
    const uint8_t *input;
    uint32_t length;
    uint32_t position;
    uint64_t magnitude;
    CpsCsvV1_Report report;
} CpsCsvV1_UnsignedMachine;

typedef struct {
    const uint8_t *input;
    uint32_t length;
    uint32_t position;
    uint64_t magnitude;
    int8_t sign;
    CpsCsvV1_Report report;
} CpsCsvV1_SignedMachine;

typedef struct {
    const uint8_t *input;
    uint32_t length;
    uint32_t position;
    uint64_t magnitude;
    int8_t sign;
    CpsCsvV1_Report report;
} CpsCsvV1_ForDrivenSignedMachine;
 ]]

local OK, SYNTAX, CAPACITY, OVERFLOW = 1, 2, 3, 4
local EXPECTED_NUMBER, EXPECTED_SEPARATOR = 1, 2
local LIMIT = 65536
local POSITIVE_LIMIT = 0x7fffffffffffffffULL
local NEGATIVE_LIMIT = 0x8000000000000000ULL

local Report = S:product("CpsCsvV1_Report")
local Machine = S:sum("Machine")
local Unsigned = Machine:leaf("CpsCsvV1_UnsignedMachine")
local Signed = Machine:leaf("CpsCsvV1_SignedMachine")
local ForDrivenSigned = Machine:leaf("CpsCsvV1_ForDrivenSignedMachine")

function Report:is_ok() return self.kind == OK end
function Report:is_syntax() return self.kind == SYNTAX end
function Report:is_capacity() return self.kind == CAPACITY end
function Report:is_overflow() return self.kind == OVERFLOW end
function Report:count()
    assert(self.kind == OK, "scanner report is not successful")
    return tonumber(self.payload.output.count)
end
function Report:value(index)
    assert(self.kind == OK, "scanner report is not successful")
    assert(index >= 1 and index <= self.payload.output.count, "number index out of bounds")
    return self.payload.output.values[index - 1]
end
function Report:error_position()
    assert(self.kind ~= OK, "successful report has no error")
    return tonumber(self.payload.error.position)
end

local function whitespace(value)
    return value == 32 or value == 9 or value == 10 or value == 13
end

function ForDrivenSigned:initial(owner)
    for position = self.position, self.length - 1 do
        self.position = position
        if not whitespace(self.input[position]) then return self:begin_number(owner) end
    end
    self.position = self.length
    return self:completed(owner)
end

function ForDrivenSigned:after_comma(owner)
    for position = self.position, self.length - 1 do
        self.position = position
        if not whitespace(self.input[position]) then return self:begin_number(owner) end
    end
    self.position = self.length
    return self:syntax(owner, EXPECTED_NUMBER)
end

function Machine:initial(owner)
    if self.position >= self.length then return self:completed(owner) end
    if whitespace(self.input[self.position]) then
        self.position = self.position + 1
        return self:initial(owner)
    end
    return self:begin_number(owner)
end

function Machine:after_comma(owner)
    if self.position >= self.length then return self:syntax(owner, EXPECTED_NUMBER) end
    if whitespace(self.input[self.position]) then
        self.position = self.position + 1
        return self:after_comma(owner)
    end
    return self:begin_number(owner)
end

function Machine:begin_number(owner)
    if self.report.payload.output.count >= LIMIT then return self:capacity(owner) end
    self.magnitude = 0
    return self:digit_required(owner)
end

function Signed:begin_number(owner)
    if self.report.payload.output.count >= LIMIT then return self:capacity(owner) end
    self.magnitude = 0
    self.sign = 1
    local value = self.input[self.position]
    if value == 45 then
        self.sign = -1
        self.position = self.position + 1
    elseif value == 43 then
        self.position = self.position + 1
    end
    return self:digit_required(owner)
end

function ForDrivenSigned:begin_number(owner)
    if self.report.payload.output.count >= LIMIT then return self:capacity(owner) end
    self.magnitude = 0
    self.sign = 1
    local value = self.input[self.position]
    if value == 45 then
        self.sign = -1
        self.position = self.position + 1
    elseif value == 43 then
        self.position = self.position + 1
    end
    return self:digit_required(owner)
end

function Machine:digit_required(owner)
    if self.position >= self.length then return self:syntax(owner, EXPECTED_NUMBER) end
    local value = self.input[self.position]
    if value < 48 or value > 57 then return self:syntax(owner, EXPECTED_NUMBER) end
    return self:digits(owner)
end

function Machine:digits(owner)
    if self.position >= self.length then return self:finish_number(owner) end
    local value = self.input[self.position]
    if value < 48 or value > 57 then return self:finish_number(owner) end
    local digit = value - 48
    if self.magnitude > (POSITIVE_LIMIT - digit) / 10 then return self:overflow(owner) end
    self.magnitude = self.magnitude * 10 + digit
    self.position = self.position + 1
    return self:digits(owner)
end

function Signed:digits(owner)
    if self.position >= self.length then return self:finish_number(owner) end
    local value = self.input[self.position]
    if value < 48 or value > 57 then return self:finish_number(owner) end
    local digit = value - 48
    local limit = self.sign < 0 and NEGATIVE_LIMIT or POSITIVE_LIMIT
    if self.magnitude > (limit - digit) / 10 then return self:overflow(owner) end
    self.magnitude = self.magnitude * 10 + digit
    self.position = self.position + 1
    return self:digits(owner)
end

function ForDrivenSigned:digits(owner)
    local limit = self.sign < 0 and NEGATIVE_LIMIT or POSITIVE_LIMIT
    for position = self.position, self.length - 1 do
        local value = self.input[position]
        if value < 48 or value > 57 then
            self.position = position
            return self:finish_number(owner)
        end
        local digit = value - 48
        if self.magnitude > (limit - digit) / 10 then
            self.position = position
            return self:overflow(owner)
        end
        self.magnitude = self.magnitude * 10 + digit
    end
    self.position = self.length
    return self:finish_number(owner)
end

function Machine:finish_number(owner)
    local output = self.report.payload.output
    local index = output.count
    output.values[index] = self.magnitude
    output.count = index + 1
    return self:after_number(owner)
end

function Signed:finish_number(owner)
    local output = self.report.payload.output
    local index = output.count
    output.values[index] = self.sign < 0 and -self.magnitude or self.magnitude
    output.count = index + 1
    return self:after_number(owner)
end

function ForDrivenSigned:finish_number(owner)
    local output = self.report.payload.output
    local index = output.count
    output.values[index] = self.sign < 0 and -self.magnitude or self.magnitude
    output.count = index + 1
    return self:after_number(owner)
end

function ForDrivenSigned:after_number(owner)
    for position = self.position, self.length - 1 do
        local value = self.input[position]
        if not whitespace(value) then
            self.position = position
            if value == 44 then
                self.position = position + 1
                return self:after_comma(owner)
            end
            return self:syntax(owner, EXPECTED_SEPARATOR)
        end
    end
    self.position = self.length
    return self:completed(owner)
end

function Machine:after_number(owner)
    if self.position >= self.length then return self:completed(owner) end
    local value = self.input[self.position]
    if whitespace(value) then
        self.position = self.position + 1
        return self:after_number(owner)
    end
    if value == 44 then
        self.position = self.position + 1
        return self:after_comma(owner)
    end
    return self:syntax(owner, EXPECTED_SEPARATOR)
end

function Machine:completed(_owner)
    self.report.kind = OK
    return self.report
end

function Machine:syntax(_owner, code)
    self.report.kind = SYNTAX
    self.report.payload.error.position = self.position
    self.report.payload.error.code = code
    return self.report
end

function Machine:capacity(_owner)
    self.report.kind = CAPACITY
    self.report.payload.error.position = self.position
    self.report.payload.error.code = 0
    return self.report
end

function Machine:overflow(_owner)
    self.report.kind = OVERFLOW
    self.report.payload.error.position = self.position
    self.report.payload.error.code = 0
    return self.report
end

function Machine:scan(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    self.length = #owner
    self.position = 0
    self.magnitude = 0
    self.report.kind = 0
    self.report.payload.output.count = 0
    local report = self:initial(owner)
    self.input = nil
    return report
end

S:seal()

return {
    Signed = Signed,
    ForDrivenSigned = ForDrivenSigned,
    Unsigned = Unsigned,
    Machine = Machine,
    capacity = LIMIT,
}

