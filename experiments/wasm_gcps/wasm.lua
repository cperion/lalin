local ffi = require("ffi")
local bit = require("bit")

local OPCODE = {
    [0x02] = "BLOCK",
    [0x03] = "LOOP",
    [0x0b] = "END",
    [0x0c] = "BR",
    [0x0d] = "BR_IF",
    [0x20] = "LOCAL_GET",
    [0x21] = "LOCAL_SET",
    [0x41] = "I32_CONST",
    [0x44] = "F64_CONST",
    [0x4a] = "I32_GT_S",
    [0x6a] = "I32_ADD",
    [0xa0] = "F64_ADD",
    [0xa2] = "F64_MUL",
    [0xb7] = "F64_CONVERT_I32_S",
}

local Reader = {}
Reader.__index = Reader

function Reader.new(bytes, first, last)
    return setmetatable({ data = bytes, position = first or 1, limit = last or #bytes }, Reader)
end

function Reader:byte()
    assert(self.position <= self.limit, "unexpected end of Wasm binary")
    local value = self.data:byte(self.position)
    self.position = self.position + 1
    return value
end

function Reader:bytes(count)
    assert(self.position + count - 1 <= self.limit, "unexpected end of Wasm binary")
    local value = self.data:sub(self.position, self.position + count - 1)
    self.position = self.position + count
    return value
end

function Reader:uleb()
    local value, scale = 0, 1
    while true do
        local byte = self:byte()
        value = value + bit.band(byte, 0x7f) * scale
        if bit.band(byte, 0x80) == 0 then return value end
        scale = scale * 128
        assert(scale <= 2 ^ 35, "oversized Wasm uleb")
    end
end

function Reader:sleb32()
    local value, shift, byte = 0, 0
    repeat
        byte = self:byte()
        value = value + bit.band(byte, 0x7f) * 2 ^ shift
        shift = shift + 7
    until bit.band(byte, 0x80) == 0
    if shift < 32 and bit.band(byte, 0x40) ~= 0 then value = value - 2 ^ shift end
    return bit.tobit(value)
end

function Reader:name() return self:bytes(self:uleb()) end

function Reader:f64()
    local bytes = self:bytes(8)
    local buffer = ffi.new("uint8_t[8]")
    ffi.copy(buffer, bytes, 8)
    return tonumber(ffi.cast("double *", buffer)[0])
end

local function vector(reader, read_item)
    local result = {}
    for index = 1, reader:uleb() do result[index] = read_item(reader) end
    return result
end

local function read_type(reader)
    assert(reader:byte() == 0x60, "unsupported Wasm type form")
    return {
        params = vector(reader, Reader.byte),
        results = vector(reader, Reader.byte),
    }
end

local function decode_body(reader, signature)
    local local_types = {}
    for _ = 1, reader:uleb() do
        local count, value_type = reader:uleb(), reader:byte()
        for _ = 1, count do local_types[#local_types + 1] = value_type end
    end

    local instructions, labels, branches = {}, {}, {}
    while true do
        local opcode = reader:byte()
        local instruction = {
            opcode = opcode,
            name = assert(OPCODE[opcode], ("unsupported Wasm opcode 0x%02x"):format(opcode)),
        }
        instructions[#instructions + 1] = instruction
        instruction.pc = #instructions - 1

        if opcode == 0x02 or opcode == 0x03 then
            assert(reader:byte() == 0x40, "only empty Wasm block types are supported")
            local label = {
                kind = opcode == 0x03 and "loop" or "block",
                instruction = instruction,
                index = #instructions,
                stack_height = 0,
            }
            instruction.label = label
            labels[#labels + 1] = label
        elseif opcode == 0x0c or opcode == 0x0d then
            instruction.depth = reader:uleb()
            instruction.label = assert(labels[#labels - instruction.depth],
                "Wasm branch depth outside active labels")
            branches[#branches + 1] = instruction
        elseif opcode == 0x20 or opcode == 0x21 then
            instruction.local_index = reader:uleb()
        elseif opcode == 0x41 then
            instruction.value = reader:sleb32()
        elseif opcode == 0x44 then
            instruction.value = reader:f64()
        elseif opcode == 0x0b then
            if #labels == 0 then
                instruction.function_end = true
                break
            end
            local label = table.remove(labels)
            label.end_instruction = instruction
            label.end_index = #instructions
        end
    end

    for index, instruction in ipairs(instructions) do
        instruction.next = instructions[index + 1]
    end
    for _, instruction in ipairs(branches) do
        local label = instruction.label
        if label.kind == "loop" then
            instruction.target = instructions[label.index + 1]
        else
            instruction.target = instructions[label.end_index + 1]
        end
        instruction.target_height = label.stack_height
    end

    return {
        signature = signature,
        local_types = local_types,
        instructions = instructions,
    }
end

local M = {}

function M.decode(bytes)
    local reader = Reader.new(bytes)
    assert(reader:bytes(4) == "\0asm", "not a Wasm module")
    assert(reader:bytes(4) == "\1\0\0\0", "unsupported Wasm version")

    local types, function_types, bodies, exports = {}, {}, {}, {}
    while reader.position <= reader.limit do
        local section_id, size = reader:byte(), reader:uleb()
        local section_end = reader.position + size - 1
        local section = Reader.new(bytes, reader.position, section_end)
        if section_id == 1 then
            types = vector(section, read_type)
        elseif section_id == 3 then
            function_types = vector(section, Reader.uleb)
        elseif section_id == 7 then
            exports = vector(section, function(r)
                local name, kind, index = r:name(), r:byte(), r:uleb()
                return { name = name, kind = kind, index = index }
            end)
        elseif section_id == 10 then
            bodies = vector(section, function(r)
                local body_size = r:uleb()
                local body = Reader.new(bytes, r.position, r.position + body_size - 1)
                r.position = r.position + body_size
                return body
            end)
        end
        assert(section.position == section_end + 1 or section_id ~= 1
            and section_id ~= 3 and section_id ~= 7 and section_id ~= 10,
            "Wasm section was not consumed exactly")
        reader.position = section_end + 1
    end

    assert(#function_types == #bodies, "Wasm function/code count mismatch")
    local functions = {}
    for index, body_reader in ipairs(bodies) do
        local signature = assert(types[function_types[index] + 1], "missing Wasm function type")
        functions[index] = decode_body(body_reader, signature)
        assert(body_reader.position == body_reader.limit + 1, "Wasm body was not consumed exactly")
    end

    local exported = {}
    for _, export in ipairs(exports) do
        if export.kind == 0 then exported[export.name] = assert(functions[export.index + 1]) end
    end
    return { types = types, functions = functions, exports = exported }
end

function M.loadfile(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return M.decode(bytes)
end

M.OPCODE = OPCODE
M.I32 = 0x7f
M.F64 = 0x7c

return M

