local ffi = require("ffi")

local PrepatchedVariant = {}
PrepatchedVariant.__index = PrepatchedVariant

local AddZero, AddValue = {}, {}
AddZero.__index, AddValue.__index = AddZero, AddValue
local XorZero, XorValue = {}, {}
XorZero.__index, XorValue.__index = XorZero, XorValue
local RotateZero, RotateImmediate = {}, {}
RotateZero.__index, RotateImmediate.__index = RotateZero, RotateImmediate

local Library = {}
Library.__index = Library

local function owned_variant(record, rotate)
    local storage = ffi.new("uint8_t[?]", #record.code)
    ffi.copy(storage, record.code, #record.code)
    if rotate ~= nil then
        storage[record.left] = rotate
        storage[record.right] = (64 - rotate) % 64
    end
    return setmetatable({
        storage = storage, size = #record.code, rotate = rotate, name = record.name,
    }, PrepatchedVariant)
end

local function exact_record(bank, index, name, immediate)
    local record = assert(bank[index])
    assert(record.name == name, "U64 variant bank order changed at " .. index)
    assert((record.left ~= nil) == immediate, name .. " immediate-hole shape changed")
    return record
end

local function rotation_family(record)
    local family = {}
    for rotate = 1, 63 do family[rotate] = owned_variant(record, rotate) end
    return family
end

function Library.new(bank)
    local copy = exact_record(bank, 1, "u64_copy", false)
    local add = exact_record(bank, 2, "u64_add", false)
    local xor = exact_record(bank, 3, "u64_xor", false)
    local add_xor = exact_record(bank, 4, "u64_add_xor", false)
    local rotate = exact_record(bank, 9, "u64_rotate_imm", true)
    local add_rotate = exact_record(bank, 10, "u64_add_rotate_imm", true)
    local xor_rotate = exact_record(bank, 11, "u64_xor_rotate_imm", true)
    local add_xor_rotate = exact_record(bank, 12, "u64_add_xor_rotate_imm", true)
    return setmetatable({
        copy = owned_variant(copy),
        add = owned_variant(add),
        xor = owned_variant(xor),
        add_xor = owned_variant(add_xor),
        rotate = rotation_family(rotate),
        add_rotate = rotation_family(add_rotate),
        xor_rotate = rotation_family(xor_rotate),
        add_xor_rotate = rotation_family(add_xor_rotate),
    }, Library)
end

function RotateZero:copy(library) return library.copy end
function RotateZero:add(library) return library.add end
function RotateZero:xor(library) return library.xor end
function RotateZero:add_xor(library) return library.add_xor end

function RotateImmediate:copy(library) return library.rotate[self.value] end
function RotateImmediate:add(library) return library.add_rotate[self.value] end
function RotateImmediate:xor(library) return library.xor_rotate[self.value] end
function RotateImmediate:add_xor(library) return library.add_xor_rotate[self.value] end

function XorZero:without_add(rotate, library) return rotate:copy(library) end
function XorZero:with_add(rotate, library) return rotate:add(library) end
function XorValue:without_add(rotate, library) return rotate:xor(library) end
function XorValue:with_add(rotate, library) return rotate:add_xor(library) end

function AddZero:select(xor_fact, rotate, library)
    return xor_fact:without_add(rotate, library)
end
function AddValue:select(xor_fact, rotate, library)
    return xor_fact:with_add(rotate, library)
end

local function add_fact(value)
    if value == 0 then return setmetatable({}, AddZero) end
    return setmetatable({}, AddValue)
end
local function xor_fact(value)
    if value == 0 then return setmetatable({}, XorZero) end
    return setmetatable({}, XorValue)
end
local function rotate_fact(value)
    value = value % 64
    if value == 0 then return setmetatable({}, RotateZero) end
    return setmetatable({ value = value }, RotateImmediate)
end

function Library:select(addend, xor_value, rotate)
    return add_fact(addend):select(xor_fact(xor_value), rotate_fact(rotate), self)
end

function PrepatchedVariant:bytes()
    return ffi.string(self.storage, self.size)
end

return { Library = Library }
