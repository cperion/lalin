local ffi = require("ffi")

local Variant = {}
Variant.__index = Variant
local Library = {}
Library.__index = Library

local function variant(record, rotate)
    local storage = ffi.new("uint8_t[?]", #record.code)
    ffi.copy(storage, record.code, #record.code)
    if rotate then
        storage[record.left] = rotate
        storage[record.right] = (64 - rotate) % 64
    end
    return setmetatable({
        storage = storage, size = #record.code, name = record.name, rotate = rotate,
    }, Variant)
end

local function rotation_family(record)
    local values = {}
    for rotate = 1, 63 do values[rotate] = variant(record, rotate) end
    return values
end

function Library.new(bank)
    local families = {}
    for kind = 0, 7 do
        families[kind + 1] = {}
        for tail = 0, 3 do
            local record = bank.variants[kind * 4 + tail + 1]
            if kind >= 4 then
                families[kind + 1][tail + 1] = rotation_family(record)
            else
                families[kind + 1][tail + 1] = variant(record)
            end
        end
    end
    return setmetatable({ maximum = bank.maximum, families = families }, Library)
end

function Library:select(addend, xor_value, rotate, remainder)
    rotate = rotate % 64
    remainder = remainder % 4
    local kind = (addend ~= 0 and 1 or 0) + (xor_value ~= 0 and 2 or 0)
    if rotate == 0 then return self.families[kind + 1][remainder + 1] end
    return self.families[kind + 5][remainder + 1][rotate]
end

function Variant:bytes() return ffi.string(self.storage, self.size) end

return { ffi = ffi, Library = Library }
