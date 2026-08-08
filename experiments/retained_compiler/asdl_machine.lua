local schema_context = require("lalin.schema_context")

local T = schema_context.NewContext {}

schema_context.define(T, {
    { name = "RetainedAsdlV1.Operator", type = { kind = "sum", constructors = {
        { name = "RetainedAsdlV1.Add" },
        { name = "RetainedAsdlV1.Subtract" },
        { name = "RetainedAsdlV1.Multiply" },
    } } },
    { name = "RetainedAsdlV1.Expr", type = { kind = "sum", constructors = {
        { name = "RetainedAsdlV1.IntegerExpr", fields = {
            { name = "value", type = "number" },
            { name = "id", type = "number" },
            { name = "offset", type = "number" },
        } },
        { name = "RetainedAsdlV1.NameExpr", fields = {
            { name = "spelling", type = "string" },
            { name = "id", type = "number" },
            { name = "offset", type = "number" },
        } },
        { name = "RetainedAsdlV1.BinaryExpr", fields = {
            { name = "left", type = "RetainedAsdlV1.Expr" },
            { name = "right", type = "RetainedAsdlV1.Expr" },
            { name = "operator", type = "RetainedAsdlV1.Operator" },
            { name = "id", type = "number" },
            { name = "offset", type = "number" },
        } },
    } } },
    { name = "RetainedAsdlV1.Binding", type = { kind = "product", fields = {
        { name = "name", type = "string" },
        { name = "value", type = "RetainedAsdlV1.Expr" },
        { name = "offset", type = "number" },
    } } },
    { name = "RetainedAsdlV1.Program", type = { kind = "product", fields = {
        { name = "bindings", type = "RetainedAsdlV1.Binding", list = true },
        { name = "returned", type = "RetainedAsdlV1.Expr" },
        { name = "expressions", type = "RetainedAsdlV1.Expr", list = true },
    } } },
    { name = "RetainedAsdlV1.Resolution", type = { kind = "sum", constructors = {
        { name = "RetainedAsdlV1.NoResolution", fields = {
            { name = "expression_id", type = "number" },
        } },
        { name = "RetainedAsdlV1.BindingResolution", fields = {
            { name = "expression_id", type = "number" },
            { name = "binding_index", type = "number" },
        } },
    } } },
    { name = "RetainedAsdlV1.ResolutionFacet", type = { kind = "product", fields = {
        { name = "entries", type = "RetainedAsdlV1.Resolution", list = true },
    } } },
    { name = "RetainedAsdlV1.TypeKind", type = { kind = "sum", constructors = {
        { name = "RetainedAsdlV1.I64" },
    } } },
    { name = "RetainedAsdlV1.TypeEntry", type = { kind = "product", fields = {
        { name = "expression_id", type = "number" },
        { name = "type_kind", type = "RetainedAsdlV1.TypeKind" },
    } } },
    { name = "RetainedAsdlV1.TypeFacet", type = { kind = "product", fields = {
        { name = "entries", type = "RetainedAsdlV1.TypeEntry", list = true },
    } } },
    { name = "RetainedAsdlV1.LowerEntry", type = { kind = "product", fields = {
        { name = "expression_id", type = "number" },
        { name = "register_index", type = "number" },
    } } },
    { name = "RetainedAsdlV1.LowerFacet", type = { kind = "product", fields = {
        { name = "entries", type = "RetainedAsdlV1.LowerEntry", list = true },
    } } },
    { name = "RetainedAsdlV1.Instruction", type = { kind = "sum", constructors = {
        { name = "RetainedAsdlV1.ConstInstruction", fields = {
            { name = "target", type = "number" },
            { name = "value", type = "number" },
        } },
        { name = "RetainedAsdlV1.BinaryInstruction", fields = {
            { name = "target", type = "number" },
            { name = "left", type = "number" },
            { name = "right", type = "number" },
            { name = "operator", type = "RetainedAsdlV1.Operator" },
        } },
        { name = "RetainedAsdlV1.ReturnInstruction", fields = {
            { name = "value", type = "number" },
        } },
    } } },
    { name = "RetainedAsdlV1.InstructionStore", type = { kind = "product", fields = {
        { name = "items", type = "RetainedAsdlV1.Instruction", list = true },
    } } },
    { name = "RetainedAsdlV1.Artifact", type = { kind = "product", fields = {
        { name = "text", type = "string" },
    } } },
    { name = "RetainedAsdlV1.DiagnosticCode", type = { kind = "sum", constructors = {
        { name = "RetainedAsdlV1.SourceCapacity" },
        { name = "RetainedAsdlV1.Syntax" },
        { name = "RetainedAsdlV1.ExpressionCapacity" },
        { name = "RetainedAsdlV1.BindingCapacity" },
        { name = "RetainedAsdlV1.DuplicateBinding" },
        { name = "RetainedAsdlV1.UnresolvedName" },
        { name = "RetainedAsdlV1.TypeError" },
        { name = "RetainedAsdlV1.InstructionCapacity" },
        { name = "RetainedAsdlV1.ArtifactCapacity" },
        { name = "RetainedAsdlV1.MissingReturn" },
    } } },
    { name = "RetainedAsdlV1.Fault", type = { kind = "product", fields = {
        { name = "code", type = "RetainedAsdlV1.DiagnosticCode" },
        { name = "offset", type = "number" },
    } } },
    { name = "RetainedAsdlV1.CompileResult", type = { kind = "sum", constructors = {
        { name = "RetainedAsdlV1.Compilation", fields = {
            { name = "program", type = "RetainedAsdlV1.Program" },
            { name = "resolutions", type = "RetainedAsdlV1.ResolutionFacet" },
            { name = "types", type = "RetainedAsdlV1.TypeFacet" },
            { name = "lower", type = "RetainedAsdlV1.LowerFacet" },
            { name = "instructions", type = "RetainedAsdlV1.InstructionStore" },
            { name = "artifact", type = "RetainedAsdlV1.Artifact" },
        } },
        { name = "RetainedAsdlV1.CompileRejected", fields = {
            { name = "fault", type = "RetainedAsdlV1.Fault" },
        } },
    } } },
})

local A = T.RetainedAsdlV1
local class = T.definitions

local Add = class["RetainedAsdlV1.Add"]
local Subtract = class["RetainedAsdlV1.Subtract"]
local Multiply = class["RetainedAsdlV1.Multiply"]
local IntegerExpr = class["RetainedAsdlV1.IntegerExpr"]
local NameExpr = class["RetainedAsdlV1.NameExpr"]
local BinaryExpr = class["RetainedAsdlV1.BinaryExpr"]
local ConstInstruction = class["RetainedAsdlV1.ConstInstruction"]
local BinaryInstruction = class["RetainedAsdlV1.BinaryInstruction"]
local ReturnInstruction = class["RetainedAsdlV1.ReturnInstruction"]
local Compilation = class["RetainedAsdlV1.Compilation"]
local CompileRejected = class["RetainedAsdlV1.CompileRejected"]
local SourceCapacity = class["RetainedAsdlV1.SourceCapacity"]
local Syntax = class["RetainedAsdlV1.Syntax"]
local ExpressionCapacity = class["RetainedAsdlV1.ExpressionCapacity"]
local BindingCapacity = class["RetainedAsdlV1.BindingCapacity"]
local DuplicateBinding = class["RetainedAsdlV1.DuplicateBinding"]
local UnresolvedName = class["RetainedAsdlV1.UnresolvedName"]
local TypeError = class["RetainedAsdlV1.TypeError"]
local InstructionCapacity = class["RetainedAsdlV1.InstructionCapacity"]
local ArtifactCapacity = class["RetainedAsdlV1.ArtifactCapacity"]
local MissingReturn = class["RetainedAsdlV1.MissingReturn"]

local SOURCE_CAPACITY = 65536
local EXPRESSION_CAPACITY = 4096
local BINDING_CAPACITY = 1024
local INSTRUCTION_CAPACITY = 8192
local ARTIFACT_CAPACITY = 262144

local TOKEN_EOF = 0
local TOKEN_INVALID = 1
local TOKEN_LET = 2
local TOKEN_RETURN = 3
local TOKEN_IDENTIFIER = 4
local TOKEN_INTEGER = 5
local TOKEN_PLUS = 6
local TOKEN_MINUS = 7
local TOKEN_STAR = 8
local TOKEN_EQUAL = 9
local TOKEN_LPAREN = 10
local TOKEN_RPAREN = 11
local TOKEN_SEMICOLON = 12

local function reject(code, offset) error(A.Fault(code, offset), 0) end

local Scanner = {}
Scanner.__index = Scanner

local function is_alpha(byte)
    return byte == 95 or byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122
end

local function is_digit(byte) return byte >= 48 and byte <= 57 end
local function is_alnum(byte) return is_alpha(byte) or is_digit(byte) end

function Scanner.new(source)
    return setmetatable({
        source = source, position = 1, kind = TOKEN_EOF, text = "", value = 0, offset = 0,
    }, Scanner)
end

function Scanner:next()
    local source, length, position = self.source, #self.source, self.position
    while position <= length do
        local byte = source:byte(position)
        if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then break end
        position = position + 1
    end
    self.offset, self.value = position - 1, 0
    if position > length then
        self.position, self.kind, self.text = position, TOKEN_EOF, ""
        return self
    end
    local byte = source:byte(position)
    if is_alpha(byte) then
        local finish = position + 1
        while finish <= length and is_alnum(source:byte(finish)) do finish = finish + 1 end
        local text = source:sub(position, finish - 1)
        self.text, self.position = text, finish
        if text == "let" then self.kind = TOKEN_LET
        elseif text == "return" then self.kind = TOKEN_RETURN
        else self.kind = TOKEN_IDENTIFIER end
    elseif is_digit(byte) then
        local finish, value = position, 0
        while finish <= length and is_digit(source:byte(finish)) do
            value = value * 10 + source:byte(finish) - 48
            finish = finish + 1
        end
        self.text, self.value, self.position = source:sub(position, finish - 1), value, finish
        self.kind = TOKEN_INTEGER
    else
        self.text, self.position = source:sub(position, position), position + 1
        if byte == 43 then self.kind = TOKEN_PLUS
        elseif byte == 45 then self.kind = TOKEN_MINUS
        elseif byte == 42 then self.kind = TOKEN_STAR
        elseif byte == 61 then self.kind = TOKEN_EQUAL
        elseif byte == 40 then self.kind = TOKEN_LPAREN
        elseif byte == 41 then self.kind = TOKEN_RPAREN
        elseif byte == 59 then self.kind = TOKEN_SEMICOLON
        else self.kind = TOKEN_INVALID end
    end
    return self
end

local Parser = {}
Parser.__index = Parser

function Parser.new(source)
    return setmetatable({ scanner = Scanner.new(source), expressions = {}, bindings = {} }, Parser)
end

function Parser:append(expression)
    if #self.expressions >= EXPRESSION_CAPACITY then reject(A.ExpressionCapacity, self.scanner.offset) end
    self.expressions[#self.expressions + 1] = expression
    return expression
end

function Parser:primary()
    local scanner = self.scanner
    if scanner.kind == TOKEN_INTEGER then
        local value, offset, id = scanner.value, scanner.offset, #self.expressions
        scanner:next()
        return self:append(A.IntegerExpr(value, id, offset))
    elseif scanner.kind == TOKEN_IDENTIFIER then
        local spelling, offset, id = scanner.text, scanner.offset, #self.expressions
        scanner:next()
        return self:append(A.NameExpr(spelling, id, offset))
    elseif scanner.kind == TOKEN_LPAREN then
        scanner:next()
        local expression = self:additive()
        if scanner.kind ~= TOKEN_RPAREN then reject(A.Syntax, scanner.offset) end
        scanner:next()
        return expression
    end
    reject(A.Syntax, scanner.offset)
end

function Parser:multiplicative()
    local left = self:primary()
    while self.scanner.kind == TOKEN_STAR do
        local offset = self.scanner.offset
        self.scanner:next()
        local right = self:primary()
        left = self:append(A.BinaryExpr(left, right, A.Multiply, #self.expressions, offset))
    end
    return left
end

function Parser:additive()
    local left = self:multiplicative()
    while self.scanner.kind == TOKEN_PLUS or self.scanner.kind == TOKEN_MINUS do
        local token, offset = self.scanner.kind, self.scanner.offset
        self.scanner:next()
        local right = self:multiplicative()
        local operator = token == TOKEN_PLUS and A.Add or A.Subtract
        left = self:append(A.BinaryExpr(left, right, operator, #self.expressions, offset))
    end
    return left
end

function Parser:expression()
    local expression = self:additive()
    if self.scanner.kind ~= TOKEN_SEMICOLON then reject(A.Syntax, self.scanner.offset) end
    self.scanner:next()
    return expression
end

function Parser:program()
    if #self.scanner.source > SOURCE_CAPACITY then reject(A.SourceCapacity, SOURCE_CAPACITY) end
    self.scanner:next()
    while self.scanner.kind == TOKEN_LET do
        if #self.bindings >= BINDING_CAPACITY then reject(A.BindingCapacity, self.scanner.offset) end
        self.scanner:next()
        if self.scanner.kind ~= TOKEN_IDENTIFIER then reject(A.Syntax, self.scanner.offset) end
        local name, offset = self.scanner.text, self.scanner.offset
        self.scanner:next()
        if self.scanner.kind ~= TOKEN_EQUAL then reject(A.Syntax, self.scanner.offset) end
        self.scanner:next()
        self.bindings[#self.bindings + 1] = A.Binding(name, self:expression(), offset)
    end
    if self.scanner.kind ~= TOKEN_RETURN then reject(A.MissingReturn, self.scanner.offset) end
    self.scanner:next()
    local returned = self:expression()
    if self.scanner.kind ~= TOKEN_EOF then reject(A.Syntax, self.scanner.offset) end
    return A.Program(self.bindings, returned, self.expressions)
end

function IntegerExpr:resolve(_program) return A.NoResolution(self.id) end
function BinaryExpr:resolve(_program) return A.NoResolution(self.id) end

function NameExpr:resolve(program)
    for index = 1, #program.bindings do
        local binding = program.bindings[index]
        if binding.value.id < self.id and binding.name == self.spelling then
            return A.BindingResolution(self.id, index)
        end
    end
    reject(A.UnresolvedName, self.offset)
end

local function resolve(program)
    for index = 1, #program.bindings do
        for previous = 1, index - 1 do
            if program.bindings[index].name == program.bindings[previous].name then
                reject(A.DuplicateBinding, program.bindings[index].offset)
            end
        end
    end
    local entries = {}
    for index = 1, #program.expressions do entries[index] = program.expressions[index]:resolve(program) end
    return A.ResolutionFacet(entries)
end

function IntegerExpr:typecheck(_program, _resolutions, _types)
    return A.TypeEntry(self.id, A.I64)
end

function NameExpr:typecheck(program, resolutions, types)
    local resolution = resolutions.entries[self.id + 1]
    local binding = program.bindings[resolution.binding_index]
    local source_type = types[binding.value.id + 1]
    if source_type == nil or source_type.type_kind ~= A.I64 then reject(A.TypeError, self.offset) end
    return A.TypeEntry(self.id, source_type.type_kind)
end

function BinaryExpr:typecheck(_program, _resolutions, types)
    local left, right = types[self.left.id + 1], types[self.right.id + 1]
    if left == nil or right == nil or left.type_kind ~= A.I64 or right.type_kind ~= A.I64 then
        reject(A.TypeError, self.offset)
    end
    return A.TypeEntry(self.id, A.I64)
end

local function typecheck(program, resolutions)
    local entries = {}
    for index = 1, #program.expressions do
        entries[index] = program.expressions[index]:typecheck(program, resolutions, entries)
    end
    return A.TypeFacet(entries)
end

local Lowerer = {}
Lowerer.__index = Lowerer

function Lowerer.new(program, resolutions)
    return setmetatable({
        program = program, resolutions = resolutions, entries = {}, instructions = {}, next_register = 0,
    }, Lowerer)
end

function Lowerer:register(expression_id, register_index)
    self.entries[expression_id + 1] = A.LowerEntry(expression_id, register_index)
end

function IntegerExpr:lower(machine)
    local register_index = machine.next_register
    machine.next_register = register_index + 1
    machine:register(self.id, register_index)
    machine.instructions[#machine.instructions + 1] = A.ConstInstruction(register_index, self.value)
end

function NameExpr:lower(machine)
    local resolution = machine.resolutions.entries[self.id + 1]
    local binding = machine.program.bindings[resolution.binding_index]
    local source = machine.entries[binding.value.id + 1]
    if source == nil then reject(A.TypeError, self.offset) end
    machine:register(self.id, source.register_index)
end

function BinaryExpr:lower(machine)
    local left, right = machine.entries[self.left.id + 1], machine.entries[self.right.id + 1]
    if left == nil or right == nil then reject(A.TypeError, self.offset) end
    local register_index = machine.next_register
    machine.next_register = register_index + 1
    machine:register(self.id, register_index)
    machine.instructions[#machine.instructions + 1] =
        A.BinaryInstruction(register_index, left.register_index, right.register_index, self.operator)
end

local function lower(program, resolutions)
    local machine = Lowerer.new(program, resolutions)
    for index = 1, #program.expressions do program.expressions[index]:lower(machine) end
    local returned = machine.entries[program.returned.id + 1]
    if returned == nil then reject(A.TypeError, program.returned.offset) end
    if #machine.instructions >= INSTRUCTION_CAPACITY then reject(A.InstructionCapacity, 0) end
    machine.instructions[#machine.instructions + 1] = A.ReturnInstruction(returned.register_index)
    return A.LowerFacet(machine.entries), A.InstructionStore(machine.instructions)
end

function Add:mnemonic() return "add" end
function Subtract:mnemonic() return "sub" end
function Multiply:mnemonic() return "mul" end

function ConstInstruction:emit_line()
    return ("r%d = const %s\n"):format(self.target, tostring(self.value))
end

function BinaryInstruction:emit_line()
    return ("r%d = %s r%d, r%d\n"):format(
        self.target, self.operator:mnemonic(), self.left, self.right)
end

function ReturnInstruction:emit_line() return ("return r%d\n"):format(self.value) end

local function emit(instructions)
    local lines, length = {}, 0
    for index = 1, #instructions.items do
        local line = instructions.items[index]:emit_line()
        length = length + #line
        if length > ARTIFACT_CAPACITY then reject(A.ArtifactCapacity, 0) end
        lines[index] = line
    end
    return A.Artifact(table.concat(lines))
end

local function compile_unchecked(source)
    local program = Parser.new(source):program()
    local resolutions = resolve(program)
    local types = typecheck(program, resolutions)
    local lower_facet, instructions = lower(program, resolutions)
    local artifact = emit(instructions)
    return A.Compilation(program, resolutions, types, lower_facet, instructions, artifact)
end

local function compile(source)
    assert(type(source) == "string", "compiler source must be a string")
    local ok, result = pcall(compile_unchecked, source)
    if ok then return result end
    if A.Fault:isclassof(result) then return A.CompileRejected(result) end
    error(result, 0)
end

function Compilation:succeeded() return true end
function Compilation:artifact_text() return self.artifact.text end
function Compilation:diagnostic_text() return "none" end

function CompileRejected:succeeded() return false end
function CompileRejected:artifact_text() return "" end

function SourceCapacity:diagnostic_text() return "source capacity exhausted" end
function Syntax:diagnostic_text() return "syntax error" end
function ExpressionCapacity:diagnostic_text() return "expression capacity exhausted" end
function BindingCapacity:diagnostic_text() return "binding capacity exhausted" end
function DuplicateBinding:diagnostic_text() return "duplicate binding" end
function UnresolvedName:diagnostic_text() return "unresolved name" end
function TypeError:diagnostic_text() return "type error" end
function InstructionCapacity:diagnostic_text() return "instruction capacity exhausted" end
function ArtifactCapacity:diagnostic_text() return "artifact capacity exhausted" end
function MissingReturn:diagnostic_text() return "missing return" end

function CompileRejected:diagnostic_text() return self.fault.code:diagnostic_text() end

return {
    Context = T,
    Schema = A,
    compile_unchecked = compile_unchecked,
    compile = compile,
    capacity = { source = SOURCE_CAPACITY, expressions = EXPRESSION_CAPACITY,
        bindings = BINDING_CAPACITY, instructions = INSTRUCTION_CAPACITY, artifact = ARTIFACT_CAPACITY },
}
