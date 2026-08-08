local ffi = require("ffi")

ffi.cdef [[
typedef struct HandwrittenNumberOutput {
    int64_t values[65536];
    uint32_t count;
} HandwrittenNumberOutput;

typedef struct HandwrittenNumberError {
    uint32_t position;
    uint32_t code;
} HandwrittenNumberError;

typedef union HandwrittenNumberPayload {
    HandwrittenNumberOutput output;
    HandwrittenNumberError error;
} HandwrittenNumberPayload;

typedef struct HandwrittenNumberReport {
    uint8_t kind;
    HandwrittenNumberPayload payload;
} HandwrittenNumberReport;

typedef struct HandwrittenNumberScanner {
    const uint8_t *input;
    uint32_t length;
    uint32_t position;
    uint64_t magnitude;
    int8_t sign;
    HandwrittenNumberReport report;
} HandwrittenNumberScanner;
 ]]

local RESULT_OK = 1
local RESULT_SYNTAX = 2
local RESULT_CAPACITY = 3
local RESULT_OVERFLOW = 4
local ERROR_EXPECTED_NUMBER = 1
local ERROR_EXPECTED_SEPARATOR = 2
local CAPACITY = 65536
local POSITIVE_LIMIT = 0x7fffffffffffffffULL
local NEGATIVE_LIMIT = 0x8000000000000000ULL

local ReportMethods = {}

function ReportMethods:is_ok() return self.kind == RESULT_OK end
function ReportMethods:is_syntax() return self.kind == RESULT_SYNTAX end
function ReportMethods:is_capacity() return self.kind == RESULT_CAPACITY end
function ReportMethods:is_overflow() return self.kind == RESULT_OVERFLOW end

function ReportMethods:kind_name()
    if self.kind == RESULT_OK then return "ok" end
    if self.kind == RESULT_SYNTAX then return "syntax" end
    if self.kind == RESULT_CAPACITY then return "capacity" end
    if self.kind == RESULT_OVERFLOW then return "overflow" end
    return "invalid"
end

function ReportMethods:count()
    assert(self.kind == RESULT_OK, "number report is not successful")
    return tonumber(self.payload.output.count)
end

function ReportMethods:value(index)
    assert(self.kind == RESULT_OK, "number report is not successful")
    assert(index >= 1 and index <= self.payload.output.count, "number index out of bounds")
    return self.payload.output.values[index - 1]
end

function ReportMethods:error_position()
    assert(self.kind ~= RESULT_OK, "successful number report has no error")
    return tonumber(self.payload.error.position)
end

ffi.metatype("HandwrittenNumberReport", { __index = ReportMethods })

local Methods = {}

local function whitespace(value)
    return value == 32 or value == 9 or value == 10 or value == 13
end

function Methods:initial(owner)
    if self.position >= self.length then return self:completed(owner) end
    if whitespace(self.input[self.position]) then
        self.position = self.position + 1
        return self:initial(owner)
    end
    return self:begin_number(owner)
end

function Methods:after_comma(owner)
    if self.position >= self.length then
        return self:syntax(owner, ERROR_EXPECTED_NUMBER)
    end
    if whitespace(self.input[self.position]) then
        self.position = self.position + 1
        return self:after_comma(owner)
    end
    return self:begin_number(owner)
end

function Methods:begin_number(owner)
    if self.report.payload.output.count >= CAPACITY then return self:capacity(owner) end
    self.sign = 1
    self.magnitude = 0
    local value = self.input[self.position]
    if value == 45 then
        self.sign = -1
        self.position = self.position + 1
    elseif value == 43 then
        self.position = self.position + 1
    end
    return self:digit_required(owner)
end

function Methods:digit_required(owner)
    if self.position >= self.length then return self:syntax(owner, ERROR_EXPECTED_NUMBER) end
    local value = self.input[self.position]
    if value < 48 or value > 57 then return self:syntax(owner, ERROR_EXPECTED_NUMBER) end
    return self:digits(owner)
end

function Methods:digits(owner)
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

function Methods:finish_number(owner)
    local output = self.report.payload.output
    local index = output.count
    if self.sign < 0 then
        output.values[index] = -self.magnitude
    else
        output.values[index] = self.magnitude
    end
    output.count = index + 1
    return self:after_number(owner)
end

function Methods:after_number(owner)
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
    return self:syntax(owner, ERROR_EXPECTED_SEPARATOR)
end

function Methods:completed(_owner)
    self.report.kind = RESULT_OK
    return self.report
end

function Methods:syntax(_owner, code)
    self.report.kind = RESULT_SYNTAX
    self.report.payload.error.position = self.position
    self.report.payload.error.code = code
    return self.report
end

function Methods:capacity(_owner)
    self.report.kind = RESULT_CAPACITY
    self.report.payload.error.position = self.position
    self.report.payload.error.code = 0
    return self.report
end

function Methods:overflow(_owner)
    self.report.kind = RESULT_OVERFLOW
    self.report.payload.error.position = self.position
    self.report.payload.error.code = 0
    return self.report
end

function Methods:scan(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    self.length = #owner
    self.position = 0
    self.magnitude = 0
    self.sign = 1
    self.report.kind = 0
    self.report.payload.output.count = 0
    local report = self:initial(owner)
    self.input = nil
    return report
end

local Scanner = ffi.metatype("HandwrittenNumberScanner", { __index = Methods })

return {
    Scanner = Scanner,
    capacity = CAPACITY,
    result_ok = RESULT_OK,
    result_syntax = RESULT_SYNTAX,
    result_capacity = RESULT_CAPACITY,
    result_overflow = RESULT_OVERFLOW,
}

