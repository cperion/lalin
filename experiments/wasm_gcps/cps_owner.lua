local bit = require("bit")
local Wasm = require("experiments.wasm_gcps.wasm")

local MATERIALIZING, READY, REJECTED = 1, 2, 3

local function bind_upvalue(fn, wanted, value)
    for index = 1, math.huge do
        local name = debug.getupvalue(fn, index)
        if name == nil then break end
        if name == wanted then
            debug.setupvalue(fn, index, value)
            return
        end
    end
    error("missing residual upvalue " .. wanted)
end

local function private_occurrence(fn, label)
    local dump = string.dump(fn)
    local clone, message = loadstring(dump, "@wasm-owner:" .. label)
    assert(clone, message)
    for index = 1, math.huge do
        local name, value = debug.getupvalue(fn, index)
        if name == nil then break end
        assert(debug.getupvalue(clone, index) == name, "private occurrence upvalue mismatch")
        debug.setupvalue(clone, index, value)
    end
    return clone, #dump
end

local function occurrence_name(instruction)
    return ("pc_%d_%s"):format(instruction.pc, instruction.name:lower())
end

local function stack_arguments(height)
    local result = {}
    for index = 1, height do result[index] = "v" .. index end
    return result
end

local function append(values, value)
    local result = {}
    for index = 1, #values do result[index] = values[index] end
    result[#result + 1] = value
    return result
end

local function prefix(values, count)
    local result = {}
    for index = 1, count do result[index] = values[index] end
    return result
end

local function call_source(target, values)
    local suffix = #values > 0 and ", " .. table.concat(values, ", ") or ""
    return ("return %s(self%s)"):format(occurrence_name(target), suffix)
end

local function listing(instruction, text)
    local arguments = stack_arguments(instruction.stack_height)
    local suffix = #arguments > 0 and ", " .. table.concat(arguments, ", ") or ""
    return ("%s = function(self%s) %s end"):format(
        occurrence_name(instruction), suffix, text)
end

local function successor_pc(instruction)
    return instruction and instruction.pc or nil
end

local function facet(instruction, operands, successors, text)
    return {
        operands = operands or {},
        successors = successors or {},
        source = listing(instruction, text),
    }
end

local function require_height(instruction, maximum)
    local height = instruction.stack_height
    assert(height >= 0 and height <= maximum,
        ("unsupported stack height %d for %s at pc %d"):format(
            height, instruction.name, instruction.pc))
    return height
end

local function push_template(height, value)
    local NEXT, VALUE = nil, value
    if height == 0 then
        return function(self) return NEXT(self, VALUE) end
    elseif height == 1 then
        return function(self, v1) return NEXT(self, v1, VALUE) end
    elseif height == 2 then
        return function(self, v1, v2) return NEXT(self, v1, v2, VALUE) end
    end
    error("unsupported push stack height")
end

local function local_get_template(height, index)
    local NEXT, INDEX = nil, index
    if height == 0 then
        return function(self) return NEXT(self, self.locals[INDEX]) end
    elseif height == 1 then
        return function(self, v1) return NEXT(self, v1, self.locals[INDEX]) end
    elseif height == 2 then
        return function(self, v1, v2) return NEXT(self, v1, v2, self.locals[INDEX]) end
    end
    error("unsupported local.get stack height")
end

local function local_set_template(height, index)
    local NEXT, INDEX = nil, index
    if height == 1 then
        return function(self, v1)
            self.locals[INDEX] = v1
            return NEXT(self)
        end
    elseif height == 2 then
        return function(self, v1, v2)
            self.locals[INDEX] = v2
            return NEXT(self, v1)
        end
    elseif height == 3 then
        return function(self, v1, v2, v3)
            self.locals[INDEX] = v3
            return NEXT(self, v1, v2)
        end
    end
    error("unsupported local.set stack height")
end

local function pass_template(height)
    local NEXT
    if height == 0 then
        return function(self) return NEXT(self) end
    elseif height == 1 then
        return function(self, v1) return NEXT(self, v1) end
    elseif height == 2 then
        return function(self, v1, v2) return NEXT(self, v1, v2) end
    elseif height == 3 then
        return function(self, v1, v2, v3) return NEXT(self, v1, v2, v3) end
    end
    error("unsupported pass stack height")
end

local function i32_add_template(height)
    local NEXT
    if height == 2 then
        return function(self, v1, v2) return NEXT(self, bit.tobit(v1 + v2)) end
    elseif height == 3 then
        return function(self, v1, v2, v3) return NEXT(self, v1, bit.tobit(v2 + v3)) end
    end
    error("unsupported i32.add stack height")
end

local function i32_gt_s_template(height)
    local NEXT
    if height == 2 then
        return function(self, v1, v2) return NEXT(self, v1 > v2 and 1 or 0) end
    elseif height == 3 then
        return function(self, v1, v2, v3) return NEXT(self, v1, v2 > v3 and 1 or 0) end
    end
    error("unsupported i32.gt_s stack height")
end

local function f64_add_template(height)
    local NEXT
    if height == 2 then
        return function(self, v1, v2) return NEXT(self, v1 + v2) end
    elseif height == 3 then
        return function(self, v1, v2, v3) return NEXT(self, v1, v2 + v3) end
    end
    error("unsupported f64.add stack height")
end

local function f64_mul_template(height)
    local NEXT
    if height == 2 then
        return function(self, v1, v2) return NEXT(self, v1 * v2) end
    elseif height == 3 then
        return function(self, v1, v2, v3) return NEXT(self, v1, v2 * v3) end
    end
    error("unsupported f64.mul stack height")
end

local function convert_template(height)
    local NEXT
    if height == 1 then
        return function(self, v1) return NEXT(self, v1 + 0.0) end
    elseif height == 2 then
        return function(self, v1, v2) return NEXT(self, v1, v2 + 0.0) end
    elseif height == 3 then
        return function(self, v1, v2, v3) return NEXT(self, v1, v2, v3 + 0.0) end
    end
    error("unsupported conversion stack height")
end

local function bind_next(instruction, compiler, fn)
    bind_upvalue(fn, "NEXT", compiler:entry(assert(instruction.next, "missing fallthrough")))
end

local Owners = {}

local function owner(name)
    local value = {}
    value.__index = value
    Owners[name] = value
    return value
end

local I32_CONST = owner("I32_CONST")
function I32_CONST:analyze(height) return height + 1 end
function I32_CONST:make()
    local height = require_height(self, 2)
    return push_template(height, self.value),
        facet(self, { value = self.value }, { successor_pc(self.next) },
            call_source(self.next, append(stack_arguments(height), tostring(self.value))))
end
function I32_CONST:bind(compiler, fn) bind_next(self, compiler, fn) end

local F64_CONST = owner("F64_CONST")
function F64_CONST:analyze(height) return height + 1 end
function F64_CONST:make()
    local height = require_height(self, 2)
    return push_template(height, self.value),
        facet(self, { value = self.value }, { successor_pc(self.next) },
            call_source(self.next, append(stack_arguments(height),
                ("%.17g"):format(self.value))))
end
function F64_CONST:bind(compiler, fn) bind_next(self, compiler, fn) end

local LOCAL_GET = owner("LOCAL_GET")
function LOCAL_GET:analyze(height) return height + 1 end
function LOCAL_GET:make()
    local height = require_height(self, 2)
    return local_get_template(height, self.local_index),
        facet(self, { local_index = self.local_index }, { successor_pc(self.next) },
            call_source(self.next, append(stack_arguments(height),
                ("self.locals[%d]"):format(self.local_index))))
end
function LOCAL_GET:bind(compiler, fn) bind_next(self, compiler, fn) end

local LOCAL_SET = owner("LOCAL_SET")
function LOCAL_SET:analyze(height)
    assert(height >= 1, "Wasm operand-stack underflow")
    return height - 1
end
function LOCAL_SET:make()
    local height = require_height(self, 3)
    return local_set_template(height, self.local_index),
        facet(self, { local_index = self.local_index }, { successor_pc(self.next) },
            ("self.locals[%d] = v%d; %s"):format(self.local_index, height,
                call_source(self.next, prefix(stack_arguments(height), height - 1))))
end
function LOCAL_SET:bind(compiler, fn) bind_next(self, compiler, fn) end

local function binary_analyze(_self, height)
    assert(height >= 2, "Wasm operand-stack underflow")
    return height - 1
end

local I32_ADD = owner("I32_ADD")
function I32_ADD:analyze(height) return binary_analyze(self, height) end
function I32_ADD:make()
    local height = require_height(self, 3)
    return i32_add_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, append(prefix(stack_arguments(height), height - 2),
                ("bit.tobit(v%d + v%d)"):format(height - 1, height))))
end
function I32_ADD:bind(compiler, fn) bind_next(self, compiler, fn) end

local I32_GT_S = owner("I32_GT_S")
function I32_GT_S:analyze(height) return binary_analyze(self, height) end
function I32_GT_S:make()
    local height = require_height(self, 3)
    return i32_gt_s_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, append(prefix(stack_arguments(height), height - 2),
                ("v%d > v%d and 1 or 0"):format(height - 1, height))))
end
function I32_GT_S:bind(compiler, fn) bind_next(self, compiler, fn) end

local F64_ADD = owner("F64_ADD")
function F64_ADD:analyze(height) return binary_analyze(self, height) end
function F64_ADD:make()
    local height = require_height(self, 3)
    return f64_add_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, append(prefix(stack_arguments(height), height - 2),
                ("v%d + v%d"):format(height - 1, height))))
end
function F64_ADD:bind(compiler, fn) bind_next(self, compiler, fn) end

local F64_MUL = owner("F64_MUL")
function F64_MUL:analyze(height) return binary_analyze(self, height) end
function F64_MUL:make()
    local height = require_height(self, 3)
    return f64_mul_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, append(prefix(stack_arguments(height), height - 2),
                ("v%d * v%d"):format(height - 1, height))))
end
function F64_MUL:bind(compiler, fn) bind_next(self, compiler, fn) end

local F64_CONVERT_I32_S = owner("F64_CONVERT_I32_S")
function F64_CONVERT_I32_S:analyze(height)
    assert(height >= 1, "Wasm operand-stack underflow")
    return height
end
function F64_CONVERT_I32_S:make()
    local height = require_height(self, 3)
    return convert_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, append(prefix(stack_arguments(height), height - 1),
                ("v%d + 0.0"):format(height))))
end
function F64_CONVERT_I32_S:bind(compiler, fn) bind_next(self, compiler, fn) end

local BLOCK = owner("BLOCK")
function BLOCK:analyze(height) self.label.stack_height = height; return height end
function BLOCK:make()
    local height = require_height(self, 3)
    return pass_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, stack_arguments(height)))
end
function BLOCK:bind(compiler, fn) bind_next(self, compiler, fn) end

local LOOP = owner("LOOP")
function LOOP:analyze(height) self.label.stack_height = height; return height end
function LOOP:make()
    local height = require_height(self, 3)
    return pass_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, stack_arguments(height)))
end
function LOOP:bind(compiler, fn) bind_next(self, compiler, fn) end

local BR = owner("BR")
function BR:analyze(_height) return self.label.stack_height end
function BR:make()
    assert(self.target_height == 0, "only empty Wasm branch signatures are supported")
    local TARGET
    return function(self) return TARGET(self) end,
        facet(self, { depth = self.depth }, { successor_pc(self.target) },
            ("return %s(self)"):format(occurrence_name(self.target)))
end
function BR:bind(compiler, fn)
    bind_upvalue(fn, "TARGET", compiler:entry(self.target))
end

local BR_IF = owner("BR_IF")
function BR_IF:analyze(height)
    assert(height >= 1, "Wasm operand-stack underflow")
    return height - 1
end
function BR_IF:make()
    assert(self.stack_height == 1 and self.target_height == 0,
        "only empty Wasm br_if signatures are supported")
    local TARGET, NEXT
    return function(self, condition)
        if condition ~= 0 then return TARGET(self) end
        return NEXT(self)
    end, facet(self, { depth = self.depth },
        { successor_pc(self.target), successor_pc(self.next) },
        ("if v1 ~= 0 then return %s(self) end; return %s(self)"):format(
            occurrence_name(self.target), occurrence_name(self.next)))
end
function BR_IF:bind(compiler, fn)
    bind_upvalue(fn, "TARGET", compiler:entry(self.target))
    bind_upvalue(fn, "NEXT", compiler:entry(self.next))
end

local END = owner("END")
function END:analyze(height) return height end
function END:make()
    local height = require_height(self, 3)
    if self.function_end then
        assert(#self._function.signature.results == 0 or height == 1,
            "unsupported Wasm function result stack")
        if #self._function.signature.results == 0 then
            return function(_self) end, facet(self, {}, {}, "return")
        end
        return function(_self, result) return result end,
            facet(self, {}, {}, "return v1")
    end
    return pass_template(height),
        facet(self, {}, { successor_pc(self.next) },
            call_source(self.next, stack_arguments(height)))
end
function END:bind(compiler, fn)
    if not self.function_end then bind_next(self, compiler, fn) end
end

local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(func, label, function_index)
    local self = setmetatable({
        func = func,
        label = label,
        function_index = function_index,
        entries = {},
        states = {},
        records = {},
        rejections = {},
        compile_order = {},
        sealed = false,
        stats = { compiled = 0, private_clones = 0, private_dump_bytes = 0 },
    }, Compiler)

    local height = 0
    for _, instruction in ipairs(func.instructions) do
        setmetatable(instruction, assert(Owners[instruction.name],
            "missing Wasm owner for " .. instruction.name))
        instruction._function = func
        instruction.stack_height = height
        height = instruction:analyze(height)
        instruction.stack_after = height
    end
    for _, instruction in ipairs(func.instructions) do
        if instruction.target then
            instruction.target_height = instruction.label.stack_height
            assert(instruction.target.stack_height == instruction.target_height,
                "unsupported Wasm branch stack signature")
        end
    end
    return self
end

function Compiler:key(instruction)
    return ("%s:func%d:pc%d"):format(self.label, self.function_index, instruction.pc)
end

function Compiler:entry(instruction)
    local slot = instruction.pc + 1
    local state = self.states[slot]
    if state == READY or state == MATERIALIZING then return self.entries[slot] end
    if state == REJECTED then error(self.rejections[slot], 0) end
    if self.sealed then error("sealed Wasm graph does not contain " .. self:key(instruction)) end

    self.states[slot] = MATERIALIZING
    local ok, result = pcall(function()
        local authored, projection = instruction:make(self)
        local fn, dump_bytes = private_occurrence(authored, self:key(instruction))
        self.entries[slot] = fn
        self.stats.compiled = self.stats.compiled + 1
        self.stats.private_clones = self.stats.private_clones + 1
        self.stats.private_dump_bytes = self.stats.private_dump_bytes + dump_bytes

        projection.label = occurrence_name(instruction)
        projection.key = self:key(instruction)
        projection.function_index = self.function_index
        projection.pc = instruction.pc
        projection.name = instruction.name
        projection.opcode = instruction.opcode
        projection.status = "materializing"
        self.records[slot] = projection
        self.compile_order[#self.compile_order + 1] = projection.key

        instruction:bind(self, fn)
        projection.status = "ready"
        self.states[slot] = READY
        return fn
    end)
    if ok then return result end

    local message = tostring(result)
    self.states[slot] = REJECTED
    self.rejections[slot] = message
    if self.records[slot] then self.records[slot].status = "rejected" end
    error(message, 0)
end

function Compiler:prepare()
    local entry = self:entry(assert(self.func.instructions[1], "empty Wasm function"))
    self.sealed = true
    return entry
end

local function public_entry(compiler)
    assert(#compiler.func.signature.params == 1, "fixture owner supports one Wasm parameter")
    assert(#compiler.func.local_types == 2, "fixture owner supports two Wasm locals")
    local first, second = compiler.func.local_types[1], compiler.func.local_types[2]
    local ENTRY, COMPILER, STATE = nil, compiler, { locals = {} }
    local authored
    if first == Wasm.F64 and second == Wasm.I32 then
        authored = function(argument)
            if ENTRY == nil then ENTRY = COMPILER:prepare() end
            local locals = STATE.locals
            locals[0], locals[1], locals[2] = argument, 0.0, 0
            return ENTRY(STATE)
        end
    elseif first == Wasm.I32 and second == Wasm.I32 then
        authored = function(argument)
            if ENTRY == nil then ENTRY = COMPILER:prepare() end
            local locals = STATE.locals
            locals[0], locals[1], locals[2] = argument, 0, 0
            return ENTRY(STATE)
        end
    else
        error("unsupported Wasm local shape")
    end
    local fn, bytes = private_occurrence(authored, compiler.label .. ":public" .. compiler.function_index)
    compiler.stats.private_clones = compiler.stats.private_clones + 1
    compiler.stats.private_dump_bytes = compiler.stats.private_dump_bytes + bytes
    return fn
end

local Artifact = {}
Artifact.__index = Artifact

function Artifact:prepare()
    for index, compiler in ipairs(self.compilers) do
        local entry = compiler:prepare()
        bind_upvalue(self.public_entries[index], "ENTRY", entry)
    end
    return self
end

function Artifact:projection()
    local result = {
        functions = {},
        by_key = {},
        compile_order = {},
        rejections = {},
        stats = { compiled = 0, private_clones = 0, private_dump_bytes = 0 },
    }
    for _, compiler in ipairs(self.compilers) do
        result.stats.compiled = result.stats.compiled + compiler.stats.compiled
        result.stats.private_clones = result.stats.private_clones + compiler.stats.private_clones
        result.stats.private_dump_bytes =
            result.stats.private_dump_bytes + compiler.stats.private_dump_bytes
        for _, instruction in ipairs(compiler.func.instructions) do
            local record = compiler.records[instruction.pc + 1]
            if record then
                result.functions[#result.functions + 1] = record
                result.by_key[record.key] = record
            end
        end
        for _, key in ipairs(compiler.compile_order) do
            result.compile_order[#result.compile_order + 1] = key
        end
        for slot, message in pairs(compiler.rejections) do
            result.rejections[#result.rejections + 1] = {
                key = compiler:key(compiler.func.instructions[slot]),
                message = message,
            }
        end
    end
    return result
end

local M = {}

function M.compile(module, label)
    label = label or "module"
    local artifact = setmetatable({ compilers = {}, public_entries = {} }, Artifact)
    local by_function = {}
    for index, func in ipairs(module.functions) do
        local compiler = Compiler.new(func, label, index - 1)
        artifact.compilers[index] = compiler
        artifact.public_entries[index] = public_entry(compiler)
        by_function[func] = index
    end

    local exports = {}
    for export_name, func in pairs(module.exports) do
        exports[export_name] = artifact.public_entries[assert(by_function[func])]
    end
    return exports, artifact
end

function M.load(bytes, label)
    local module = Wasm.decode(bytes)
    local exports, artifact = M.compile(module, label)
    return exports, module, artifact
end

function M.loadfile(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return M.load(bytes, path)
end

M.Owners = Owners
M.Compiler = Compiler
M.Artifact = Artifact

return M

