local ffi = require("ffi")
local schema = require("cdefschema")

local S = schema.context {
    name = "cps-glob",
    version = 1,
    prefix = "CpsGlobV1_",
}

S:cdef [[
typedef struct {
    const uint8_t *pattern;
    const uint8_t *text;
    uint32_t pattern_length;
    uint32_t text_length;
    uint32_t pattern_position;
    uint32_t text_position;
    uint32_t star_pattern;
    uint32_t star_text;
} CpsGlobV1_Sensitive;

typedef struct {
    const uint8_t *pattern;
    const uint8_t *text;
    uint32_t pattern_length;
    uint32_t text_length;
    uint32_t pattern_position;
    uint32_t text_position;
    uint32_t star_pattern;
    uint32_t star_text;
} CpsGlobV1_AsciiFold;

typedef struct {
    const uint8_t *pattern;
    const uint8_t *text;
    uint32_t pattern_length;
    uint32_t text_length;
    uint32_t pattern_position;
    uint32_t text_position;
    uint32_t star_pattern;
    uint32_t star_text;
} CpsGlobV1_CoarseSensitive;

typedef struct {
    const uint8_t *pattern;
    const uint8_t *text;
    uint32_t pattern_length;
    uint32_t text_length;
    uint32_t pattern_position;
    uint32_t text_position;
    uint32_t star_pattern;
    uint32_t star_text;
} CpsGlobV1_CoarseAsciiFold;

typedef struct {
    const uint8_t *pattern;
    const uint8_t *text;
    uint32_t pattern_length;
    uint32_t text_length;
    uint32_t pattern_position;
    uint32_t text_position;
    uint32_t star_pattern;
    uint32_t star_text;
} CpsGlobV1_DrivenSensitive;
 ]]

local NO_STAR = 0xffffffff
local Machine = S:sum("Machine")
local Sensitive = Machine:leaf("CpsGlobV1_Sensitive")
local AsciiFold = Machine:leaf("CpsGlobV1_AsciiFold")
local CoarseSensitive = Machine:leaf("CpsGlobV1_CoarseSensitive")
local CoarseAsciiFold = Machine:leaf("CpsGlobV1_CoarseAsciiFold")
local DrivenSensitive = Machine:leaf("CpsGlobV1_DrivenSensitive")

function Machine:loop(pattern_owner, text_owner)
    if self.text_position < self.text_length then
        return self:dispatch(pattern_owner, text_owner)
    end
    return self:finish_pattern(pattern_owner, text_owner)
end

function Machine:dispatch(pattern_owner, text_owner)
    if self.pattern_position >= self.pattern_length then
        return self:fallback(pattern_owner, text_owner)
    end
    local value = self.pattern[self.pattern_position]
    if value == 42 then return self:star(pattern_owner, text_owner) end
    if value == 63 then return self:advance(pattern_owner, text_owner) end
    return self:literal(pattern_owner, text_owner)
end

function Machine:literal(pattern_owner, text_owner)
    if self.pattern[self.pattern_position] == self.text[self.text_position] then
        return self:advance(pattern_owner, text_owner)
    end
    return self:fallback(pattern_owner, text_owner)
end

local function fold_ascii(value)
    if value >= 65 and value <= 90 then return value + 32 end
    return value
end

function CoarseSensitive:loop(pattern_owner, text_owner)
    if self.text_position < self.text_length then
        local pattern_position = self.pattern_position
        if pattern_position < self.pattern_length then
            local value = self.pattern[pattern_position]
            if value == 42 then
                self.star_pattern = pattern_position
                self.pattern_position = pattern_position + 1
                self.star_text = self.text_position
                return self:loop(pattern_owner, text_owner)
            end
            if value == 63 or value == self.text[self.text_position] then
                self.pattern_position = pattern_position + 1
                self.text_position = self.text_position + 1
                return self:loop(pattern_owner, text_owner)
            end
        end
        if self.star_pattern ~= NO_STAR and self.star_text < self.text_length then
            self.star_text = self.star_text + 1
            self.text_position = self.star_text
            self.pattern_position = self.star_pattern + 1
            return self:loop(pattern_owner, text_owner)
        end
        return self:rejected(pattern_owner, text_owner)
    end
    if self.pattern_position < self.pattern_length
        and self.pattern[self.pattern_position] == 42 then
        self.pattern_position = self.pattern_position + 1
        return self:loop(pattern_owner, text_owner)
    end
    if self.pattern_position == self.pattern_length then
        return self:accepted(pattern_owner, text_owner)
    end
    return self:rejected(pattern_owner, text_owner)
end

function DrivenSensitive:loop(pattern_owner, text_owner)
    for _ = 1, 256 do
        if self.text_position < self.text_length then
            local pattern_position = self.pattern_position
            if pattern_position < self.pattern_length then
                local value = self.pattern[pattern_position]
                if value == 42 then
                    self.star_pattern = pattern_position
                    self.pattern_position = pattern_position + 1
                    self.star_text = self.text_position
                elseif value == 63 or value == self.text[self.text_position] then
                    self.pattern_position = pattern_position + 1
                    self.text_position = self.text_position + 1
                elseif self.star_pattern ~= NO_STAR and self.star_text < self.text_length then
                    self.star_text = self.star_text + 1
                    self.text_position = self.star_text
                    self.pattern_position = self.star_pattern + 1
                else
                    return self:rejected(pattern_owner, text_owner)
                end
            elseif self.star_pattern ~= NO_STAR and self.star_text < self.text_length then
                self.star_text = self.star_text + 1
                self.text_position = self.star_text
                self.pattern_position = self.star_pattern + 1
            else
                return self:rejected(pattern_owner, text_owner)
            end
        elseif self.pattern_position < self.pattern_length
            and self.pattern[self.pattern_position] == 42 then
            self.pattern_position = self.pattern_position + 1
        elseif self.pattern_position == self.pattern_length then
            return self:accepted(pattern_owner, text_owner)
        else
            return self:rejected(pattern_owner, text_owner)
        end
    end
    return self:loop(pattern_owner, text_owner)
end

function CoarseAsciiFold:loop(pattern_owner, text_owner)
    if self.text_position < self.text_length then
        local pattern_position = self.pattern_position
        if pattern_position < self.pattern_length then
            local value = self.pattern[pattern_position]
            if value == 42 then
                self.star_pattern = pattern_position
                self.pattern_position = pattern_position + 1
                self.star_text = self.text_position
                return self:loop(pattern_owner, text_owner)
            end
            if value == 63
                or fold_ascii(value) == fold_ascii(self.text[self.text_position]) then
                self.pattern_position = pattern_position + 1
                self.text_position = self.text_position + 1
                return self:loop(pattern_owner, text_owner)
            end
        end
        if self.star_pattern ~= NO_STAR and self.star_text < self.text_length then
            self.star_text = self.star_text + 1
            self.text_position = self.star_text
            self.pattern_position = self.star_pattern + 1
            return self:loop(pattern_owner, text_owner)
        end
        return self:rejected(pattern_owner, text_owner)
    end
    if self.pattern_position < self.pattern_length
        and self.pattern[self.pattern_position] == 42 then
        self.pattern_position = self.pattern_position + 1
        return self:loop(pattern_owner, text_owner)
    end
    if self.pattern_position == self.pattern_length then
        return self:accepted(pattern_owner, text_owner)
    end
    return self:rejected(pattern_owner, text_owner)
end

function AsciiFold:literal(pattern_owner, text_owner)
    local pattern_value = fold_ascii(self.pattern[self.pattern_position])
    local text_value = fold_ascii(self.text[self.text_position])
    if pattern_value == text_value then
        return self:advance(pattern_owner, text_owner)
    end
    return self:fallback(pattern_owner, text_owner)
end

function Machine:advance(pattern_owner, text_owner)
    self.pattern_position = self.pattern_position + 1
    self.text_position = self.text_position + 1
    return self:loop(pattern_owner, text_owner)
end

function Machine:star(pattern_owner, text_owner)
    self.star_pattern = self.pattern_position
    self.pattern_position = self.pattern_position + 1
    self.star_text = self.text_position
    return self:loop(pattern_owner, text_owner)
end

function Machine:fallback(pattern_owner, text_owner)
    if self.star_pattern ~= NO_STAR and self.star_text < self.text_length then
        self.star_text = self.star_text + 1
        self.text_position = self.star_text
        self.pattern_position = self.star_pattern + 1
        return self:loop(pattern_owner, text_owner)
    end
    return self:rejected(pattern_owner, text_owner)
end
function Machine:finish_pattern(pattern_owner, text_owner)
    if self.pattern_position < self.pattern_length
        and self.pattern[self.pattern_position] == 42 then
        self.pattern_position = self.pattern_position + 1
        return self:finish_pattern(pattern_owner, text_owner)
    end
    if self.pattern_position == self.pattern_length then
        return self:accepted(pattern_owner, text_owner)
    end
    return self:rejected(pattern_owner, text_owner)
end

function Machine:accepted(_pattern_owner, _text_owner) return true end
function Machine:rejected(_pattern_owner, _text_owner) return false end

function Machine:match(pattern_owner, text_owner)
    self.pattern = ffi.cast("const uint8_t *", pattern_owner)
    self.text = ffi.cast("const uint8_t *", text_owner)
    self.pattern_length = #pattern_owner
    self.text_length = #text_owner
    self.pattern_position = 0
    self.text_position = 0
    self.star_pattern = NO_STAR
    self.star_text = 0
    local matched = self:loop(pattern_owner, text_owner)
    self.pattern = nil
    self.text = nil
    return matched
end

S:seal()

return {
    Sensitive = Sensitive,
    AsciiFold = AsciiFold,
    CoarseSensitive = CoarseSensitive,
    CoarseAsciiFold = CoarseAsciiFold,
    DrivenSensitive = DrivenSensitive,
    Machine = Machine,
}

