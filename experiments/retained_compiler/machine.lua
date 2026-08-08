local ffi = require("ffi")
local bit = require("bit")
local State = require("experiments.retained_compiler.state")

local S = State.Context
local ExprRef = State.ExprRef
local IntegerExpr = State.IntegerExpr
local NameExpr = State.NameExpr
local BinaryExpr = State.BinaryExpr
local ExpressionStore = State.ExpressionStore
local SymbolStore = State.SymbolStore
local Scanner = State.Scanner
local Parser = State.Parser
local Resolver = State.Resolver
local Typechecker = State.Typechecker
local Lowerer = State.Lowerer
local ConstInstruction = State.ConstInstruction
local BinaryInstruction = State.BinaryInstruction
local ReturnInstruction = State.ReturnInstruction
local Instruction = State.Instruction
local InstructionStore = State.InstructionStore
local Emitter = State.Emitter
local Compiler = State.Compiler

local CAP = State.capacity

local STATUS_READY = 0
local STATUS_SUCCEEDED = 1
local STATUS_REJECTED = 2

local EXPR_INTEGER = 1
local EXPR_NAME = 2
local EXPR_BINARY = 3

local OP_ADD = 1
local OP_SUBTRACT = 2
local OP_MULTIPLY = 3

local INSTRUCTION_CONST = 1
local INSTRUCTION_BINARY = 2
local INSTRUCTION_RETURN = 3

local TYPE_I64 = 1

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

local DIAG_NONE = 0
local DIAG_SOURCE_CAPACITY = 1
local DIAG_SYNTAX = 2
local DIAG_EXPRESSION_CAPACITY = 3
local DIAG_BINDING_CAPACITY = 4
local DIAG_DUPLICATE_BINDING = 5
local DIAG_UNRESOLVED_NAME = 6
local DIAG_TYPE = 7
local DIAG_INSTRUCTION_CAPACITY = 8
local DIAG_ARTIFACT_CAPACITY = 9
local DIAG_MISSING_RETURN = 10
local DIAG_INVALID_REFERENCE = 11

local function is_alpha(byte)
    return byte == 95 or byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122
end

local function is_digit(byte) return byte >= 48 and byte <= 57 end
local function is_alnum(byte) return is_alpha(byte) or is_digit(byte) end

local function span_equals_literal(source, span, literal)
    if span.length ~= #literal then return false end
    for index = 0, #literal - 1 do
        if source.bytes[span.start + index] ~= literal:byte(index + 1) then return false end
    end
    return true
end


local function precedence(token)
    if token == TOKEN_STAR then return 2 end
    if token == TOKEN_PLUS or token == TOKEN_MINUS then return 1 end
    return 0
end

local function token_operator(token)
    if token == TOKEN_PLUS then return OP_ADD end
    if token == TOKEN_MINUS then return OP_SUBTRACT end
    return OP_MULTIPLY
end

local function expression_ref(kind, index, id)
    local ref = ExprRef()
    ref.kind, ref.index, ref.id = kind, index, id
    return ref
end

local INVALID = 0xffffffff

local function symbol_hash(source, span)
    local hash = 5381
    for index = 0, span.length - 1 do
        hash = bit.band(hash * 33 + source.bytes[span.start + index], 0x7fffffff)
    end
    return hash
end

function SymbolStore:initialize()
    self.text_count, self.entry_count = 0, 0
    return self
end

function SymbolStore:intern(cc, span)
    local hash = symbol_hash(cc.source, span)
    local bucket_index = hash % CAP.symbol_buckets
    local bucket = self.buckets[bucket_index]
    local entry_index = INVALID
    if bucket.generation == cc.generation then entry_index = tonumber(bucket.head) end
    while entry_index ~= INVALID do
        local entry = self.entries[entry_index]
        if entry.hash == hash and entry.text_length == span.length then
            local equal = true
            for index = 0, span.length - 1 do
                if self.text[entry.text_offset + index] ~= cc.source.bytes[span.start + index] then
                    equal = false
                    break
                end
            end
            if equal then return entry_index end
        end
        entry_index = tonumber(entry.next_in_bucket)
    end
    if self.entry_count >= CAP.symbols or self.text_count + span.length > CAP.symbol_text then
        return INVALID
    end
    local index = self.entry_count
    local entry = self.entries[index]
    entry.hash = hash
    entry.text_offset, entry.text_length = self.text_count, span.length
    entry.next_in_bucket = bucket.generation == cc.generation and bucket.head or INVALID
    ffi.copy(self.text + self.text_count, cc.source.bytes + span.start, span.length)
    self.text_count = self.text_count + span.length
    self.entry_count = index + 1
    bucket.head, bucket.generation = index, cc.generation
    return index
end

function Scanner:initialize()
    self.position, self.token_kind = 0, TOKEN_EOF
    self.token_span.start, self.token_span.length = 0, 0
    self.integer_value, self.token_count = 0, 0
    return self
end

function Scanner:next(cc)
    local source = cc.source
    local position = self.position
    while position < source.length do
        local byte = source.bytes[position]
        if byte ~= 32 and byte ~= 9 and byte ~= 10 and byte ~= 13 then break end
        position = position + 1
    end
    self.token_span.start = position
    self.integer_value = 0
    if position >= source.length then
        self.position, self.token_kind = position, TOKEN_EOF
        self.token_span.length = 0
        self.token_count = self.token_count + 1
        return self
    end

    local byte = source.bytes[position]
    if is_alpha(byte) then
        local finish = position + 1
        while finish < source.length and is_alnum(source.bytes[finish]) do finish = finish + 1 end
        self.token_span.length = finish - position
        self.position = finish
        if span_equals_literal(source, self.token_span, "let") then
            self.token_kind = TOKEN_LET
        elseif span_equals_literal(source, self.token_span, "return") then
            self.token_kind = TOKEN_RETURN
        else
            self.token_kind = TOKEN_IDENTIFIER
        end
    elseif is_digit(byte) then
        local finish, value = position, 0
        while finish < source.length and is_digit(source.bytes[finish]) do
            value = value * 10 + source.bytes[finish] - 48
            finish = finish + 1
        end
        self.token_span.length = finish - position
        self.position, self.integer_value = finish, value
        self.token_kind = TOKEN_INTEGER
    else
        self.position = position + 1
        self.token_span.length = 1
        if byte == 43 then self.token_kind = TOKEN_PLUS
        elseif byte == 45 then self.token_kind = TOKEN_MINUS
        elseif byte == 42 then self.token_kind = TOKEN_STAR
        elseif byte == 61 then self.token_kind = TOKEN_EQUAL
        elseif byte == 40 then self.token_kind = TOKEN_LPAREN
        elseif byte == 41 then self.token_kind = TOKEN_RPAREN
        elseif byte == 59 then self.token_kind = TOKEN_SEMICOLON
        else self.token_kind = TOKEN_INVALID end
    end
    self.token_count = self.token_count + 1
    return self
end

function ExpressionStore:initialize()
    self.integer_count, self.name_count = 0, 0
    self.binary_count, self.order_count = 0, 0
    return self
end

function ExpressionStore:add_integer(value, offset)
    local index, id = self.integer_count, self.order_count
    local node = self.integers[index]
    node.value, node.id, node.offset = value, id, offset
    local ref = expression_ref(EXPR_INTEGER, index, id)
    self.order[id] = ref
    self.integer_count, self.order_count = index + 1, id + 1
    return ref
end

function ExpressionStore:add_name(symbol, offset)
    local index, id = self.name_count, self.order_count
    local node = self.names[index]
    node.symbol, node.id, node.offset = symbol, id, offset
    local ref = expression_ref(EXPR_NAME, index, id)
    self.order[id] = ref
    self.name_count, self.order_count = index + 1, id + 1
    return ref
end

function ExpressionStore:add_binary(left, right, operator_kind, offset)
    local index, id = self.binary_count, self.order_count
    local node = self.binaries[index]
    node.left, node.right = left, right
    node.id, node.operator_kind, node.offset = id, operator_kind, offset
    local ref = expression_ref(EXPR_BINARY, index, id)
    self.order[id] = ref
    self.binary_count, self.order_count = index + 1, id + 1
    return ref
end

function Parser:initialize()
    self.current_symbol = INVALID
    self.current_name_offset, self.operand_count, self.operator_count = 0, 0, 0
    self.statement_count = 0
    return self
end

function Parser:run(cc)
    self:initialize()
    cc.scanner:initialize():next(cc)
    return self:statement(cc)
end

local binding_expression_ready
local return_expression_ready

function Parser:statement(cc)
    local token = cc.scanner.token_kind
    if token == TOKEN_LET then
        if cc.program.has_return ~= 0 then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
        if cc.program.binding_count >= CAP.bindings then
            return cc:rejected(DIAG_BINDING_CAPACITY, cc.scanner.token_span.start)
        end
        cc.scanner:next(cc)
        if cc.scanner.token_kind ~= TOKEN_IDENTIFIER then
            return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
        end
        self.current_symbol = cc.symbols:intern(cc, cc.scanner.token_span)
        if self.current_symbol == INVALID then
            return cc:rejected(DIAG_BINDING_CAPACITY, cc.scanner.token_span.start)
        end
        self.current_name_offset = cc.scanner.token_span.start
        cc.scanner:next(cc)
        if cc.scanner.token_kind ~= TOKEN_EQUAL then
            return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
        end
        cc.scanner:next(cc)
        return self:expression(cc, binding_expression_ready)
    elseif token == TOKEN_RETURN then
        if cc.program.has_return ~= 0 then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
        cc.scanner:next(cc)
        return self:expression(cc, return_expression_ready)
    elseif token == TOKEN_EOF then
        return cc:rejected(DIAG_MISSING_RETURN, cc.source.length)
    end
    return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
end

function Parser:reduce_one(cc)
    local right = self.operands[self.operand_count - 1]
    local left = self.operands[self.operand_count - 2]
    local token = self.operators[self.operator_count - 1]
    self.operand_count = self.operand_count - 2
    self.operator_count = self.operator_count - 1
    local combined = cc.expressions:add_binary(
        left, right, token_operator(token), cc.scanner.token_span.start)
    self.operands[self.operand_count] = combined
    self.operand_count = self.operand_count + 1
end

function Parser:expression(cc, completed)
    self.operand_count, self.operator_count = 0, 0
    local expecting_operand = true
    while cc.scanner.token_kind ~= TOKEN_SEMICOLON and cc.scanner.token_kind ~= TOKEN_EOF do
        local token = cc.scanner.token_kind
        if token == TOKEN_INTEGER or token == TOKEN_IDENTIFIER then
            if not expecting_operand then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
            if cc.expressions.order_count >= CAP.expressions then
                return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
            end
            local ref
            if token == TOKEN_INTEGER then
                if cc.expressions.integer_count >= CAP.expressions then
                    return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
                end
                ref = cc.expressions:add_integer(cc.scanner.integer_value, cc.scanner.token_span.start)
            else
                if cc.expressions.name_count >= CAP.expressions then
                    return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
                end
                local symbol = cc.symbols:intern(cc, cc.scanner.token_span)
                if symbol == INVALID then
                    return cc:rejected(DIAG_BINDING_CAPACITY, cc.scanner.token_span.start)
                end
                ref = cc.expressions:add_name(symbol, cc.scanner.token_span.start)
            end
            if self.operand_count >= CAP.operators then
                return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
            end
            self.operands[self.operand_count] = ref
            self.operand_count = self.operand_count + 1
            expecting_operand = false
            cc.scanner:next(cc)
        elseif token == TOKEN_LPAREN then
            if not expecting_operand or self.operator_count >= CAP.operators then
                return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
            end
            self.operators[self.operator_count] = token
            self.operator_count = self.operator_count + 1
            cc.scanner:next(cc)
        elseif token == TOKEN_RPAREN then
            if expecting_operand then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
            while self.operator_count > 0
                and self.operators[self.operator_count - 1] ~= TOKEN_LPAREN do
                if self.operand_count < 2 or cc.expressions.binary_count >= CAP.expressions
                    or cc.expressions.order_count >= CAP.expressions then
                    return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
                end
                self:reduce_one(cc)
            end
            if self.operator_count == 0 then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
            self.operator_count = self.operator_count - 1
            expecting_operand = false
            cc.scanner:next(cc)
        elseif token == TOKEN_PLUS or token == TOKEN_MINUS or token == TOKEN_STAR then
            if expecting_operand then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
            while self.operator_count > 0
                and self.operators[self.operator_count - 1] ~= TOKEN_LPAREN
                and precedence(self.operators[self.operator_count - 1]) >= precedence(token) do
                if self.operand_count < 2 or cc.expressions.binary_count >= CAP.expressions
                    or cc.expressions.order_count >= CAP.expressions then
                    return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
                end
                self:reduce_one(cc)
            end
            if self.operator_count >= CAP.operators then
                return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
            end
            self.operators[self.operator_count] = token
            self.operator_count = self.operator_count + 1
            expecting_operand = true
            cc.scanner:next(cc)
        else
            return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
        end
    end

    if expecting_operand then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
    while self.operator_count > 0 do
        if self.operators[self.operator_count - 1] == TOKEN_LPAREN then
            return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
        end
        if self.operand_count < 2 or cc.expressions.binary_count >= CAP.expressions
            or cc.expressions.order_count >= CAP.expressions then
            return cc:rejected(DIAG_EXPRESSION_CAPACITY, cc.scanner.token_span.start)
        end
        self:reduce_one(cc)
    end
    if self.operand_count ~= 1 then return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start) end
    if cc.scanner.token_kind ~= TOKEN_SEMICOLON then
        return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
    end
    local result = self.operands[0]
    cc.scanner:next(cc)
    return completed(self, cc, result)
end

function Parser:binding_expression_ready(cc, value)
    local index = cc.program.binding_count
    local binding = cc.program.bindings[index]
    binding.symbol, binding.value = self.current_symbol, value
    binding.offset, binding.declaration_order = self.current_name_offset, index
    cc.program.binding_count = index + 1
    self.statement_count = self.statement_count + 1
    return self:statement(cc)
end

function Parser:return_expression_ready(cc, value)
    cc.program.returned = value
    cc.program.has_return = 1
    self.statement_count = self.statement_count + 1
    if cc.scanner.token_kind ~= TOKEN_EOF then
        return cc:rejected(DIAG_SYNTAX, cc.scanner.token_span.start)
    end
    return cc:parsed()
end

binding_expression_ready = Parser.binding_expression_ready
return_expression_ready = Parser.return_expression_ready

function NameExpr:resolve(cc, resolver, completed)
    local lookup = cc.resolutions.by_symbol[self.symbol]
    if lookup.generation == cc.generation then
        local binding = cc.program.bindings[lookup.binding]
        if binding.value.id < self.id then
            local fact = cc.resolutions.by_expression[self.id]
            fact.binding, fact.generation = lookup.binding, cc.generation
            return completed(resolver, cc, self)
        end
    end
    return cc:rejected(DIAG_UNRESOLVED_NAME, self.offset)
end

local name_resolved

function Resolver:run(cc)
    self.cursor, self.resolved_count = 0, 0
    for index = 0, cc.program.binding_count - 1 do
        local binding = cc.program.bindings[index]
        local lookup = cc.resolutions.by_symbol[binding.symbol]
        if lookup.generation == cc.generation then
            return cc:rejected(DIAG_DUPLICATE_BINDING, binding.offset)
        end
        lookup.binding, lookup.generation = index, cc.generation
    end
    return self:next_name(cc)
end

function Resolver:next_name(cc)
    if self.cursor >= cc.expressions.name_count then
        cc.resolutions.revision = cc.resolutions.revision + 1
        return cc:resolved()
    end
    return cc.expressions.names[self.cursor]:resolve(cc, self, name_resolved)
end

function Resolver:name_resolved(cc)
    self.cursor = self.cursor + 1
    self.resolved_count = self.resolved_count + 1
    return self:next_name(cc)
end

name_resolved = Resolver.name_resolved

function IntegerExpr:typecheck(ref, cc, machine, completed)
    local fact = cc.types.by_expression[ref.id]
    fact.type_kind, fact.generation = TYPE_I64, cc.generation
    return completed(machine, cc, ref)
end

function NameExpr:typecheck(ref, cc, machine, completed)
    local resolution = cc.resolutions.by_expression[ref.id]
    if resolution.generation ~= cc.generation then return cc:rejected(DIAG_TYPE, self.offset) end
    local value = cc.program.bindings[resolution.binding].value
    local source_type = cc.types.by_expression[value.id]
    if source_type.generation ~= cc.generation or source_type.type_kind ~= TYPE_I64 then
        return cc:rejected(DIAG_TYPE, self.offset)
    end
    local fact = cc.types.by_expression[ref.id]
    fact.type_kind, fact.generation = source_type.type_kind, cc.generation
    return completed(machine, cc, ref)
end

function BinaryExpr:typecheck(ref, cc, machine, completed)
    local left = cc.types.by_expression[self.left.id]
    local right = cc.types.by_expression[self.right.id]
    if left.generation ~= cc.generation or right.generation ~= cc.generation
        or left.type_kind ~= TYPE_I64 or right.type_kind ~= TYPE_I64 then
        return cc:rejected(DIAG_TYPE, self.offset)
    end
    local fact = cc.types.by_expression[ref.id]
    fact.type_kind, fact.generation = TYPE_I64, cc.generation
    return completed(machine, cc, ref)
end

function ExprRef:typecheck(cc, machine, completed)
    if self.kind == EXPR_INTEGER and self.index < cc.expressions.integer_count then
        return cc.expressions.integers[self.index]:typecheck(self, cc, machine, completed)
    elseif self.kind == EXPR_NAME and self.index < cc.expressions.name_count then
        return cc.expressions.names[self.index]:typecheck(self, cc, machine, completed)
    elseif self.kind == EXPR_BINARY and self.index < cc.expressions.binary_count then
        return cc.expressions.binaries[self.index]:typecheck(self, cc, machine, completed)
    end
    return cc:rejected(DIAG_INVALID_REFERENCE, 0)
end

local expression_typed

function Typechecker:run(cc)
    self.cursor, self.typed_count = 0, 0
    return self:next_expression(cc)
end

function Typechecker:next_expression(cc)
    if self.cursor >= cc.expressions.order_count then
        cc.types.revision = cc.types.revision + 1
        return cc:typed()
    end
    return cc.expressions.order[self.cursor]:typecheck(cc, self, expression_typed)
end

function Typechecker:expression_typed(cc)
    self.cursor = self.cursor + 1
    self.typed_count = self.typed_count + 1
    return self:next_expression(cc)
end

expression_typed = Typechecker.expression_typed

function InstructionStore:initialize()
    self.count = 0
    return self
end

function InstructionStore:add_const(target, value)
    local instruction = self.items[self.count]
    instruction.kind = INSTRUCTION_CONST
    instruction.payload.constant.target = target
    instruction.payload.constant.value = value
    self.count = self.count + 1
end

function InstructionStore:add_binary(target, left, right, operator_kind)
    local instruction = self.items[self.count]
    instruction.kind = INSTRUCTION_BINARY
    local payload = instruction.payload.binary
    payload.target, payload.left, payload.right = target, left, right
    payload.operator_kind = operator_kind
    self.count = self.count + 1
end

function InstructionStore:add_return(value)
    local instruction = self.items[self.count]
    instruction.kind = INSTRUCTION_RETURN
    instruction.payload.returned.value = value
    self.count = self.count + 1
end

function IntegerExpr:lower(ref, cc, machine, completed)
    if cc.instructions.count >= CAP.instructions then
        return cc:rejected(DIAG_INSTRUCTION_CAPACITY, self.offset)
    end
    local register_index = machine.next_register
    machine.next_register = register_index + 1
    cc.instructions:add_const(register_index, self.value)
    local fact = cc.lower.by_expression[ref.id]
    fact.register_index, fact.generation = register_index, cc.generation
    return completed(machine, cc, ref)
end

function NameExpr:lower(ref, cc, machine, completed)
    local resolution = cc.resolutions.by_expression[ref.id]
    local value = cc.program.bindings[resolution.binding].value
    local source = cc.lower.by_expression[value.id]
    if source.generation ~= cc.generation then return cc:rejected(DIAG_TYPE, self.offset) end
    local fact = cc.lower.by_expression[ref.id]
    fact.register_index, fact.generation = source.register_index, cc.generation
    return completed(machine, cc, ref)
end

function BinaryExpr:lower(ref, cc, machine, completed)
    if cc.instructions.count >= CAP.instructions then
        return cc:rejected(DIAG_INSTRUCTION_CAPACITY, self.offset)
    end
    local left = cc.lower.by_expression[self.left.id]
    local right = cc.lower.by_expression[self.right.id]
    if left.generation ~= cc.generation or right.generation ~= cc.generation then
        return cc:rejected(DIAG_TYPE, self.offset)
    end
    local register_index = machine.next_register
    machine.next_register = register_index + 1
    cc.instructions:add_binary(register_index, left.register_index, right.register_index, self.operator_kind)
    local fact = cc.lower.by_expression[ref.id]
    fact.register_index, fact.generation = register_index, cc.generation
    return completed(machine, cc, ref)
end

function ExprRef:lower(cc, machine, completed)
    if self.kind == EXPR_INTEGER and self.index < cc.expressions.integer_count then
        return cc.expressions.integers[self.index]:lower(self, cc, machine, completed)
    elseif self.kind == EXPR_NAME and self.index < cc.expressions.name_count then
        return cc.expressions.names[self.index]:lower(self, cc, machine, completed)
    elseif self.kind == EXPR_BINARY and self.index < cc.expressions.binary_count then
        return cc.expressions.binaries[self.index]:lower(self, cc, machine, completed)
    end
    return cc:rejected(DIAG_INVALID_REFERENCE, 0)
end

local expression_lowered

function Lowerer:run(cc)
    self.cursor, self.next_register, self.lowered_count = 0, 0, 0
    cc.instructions:initialize()
    return self:next_expression(cc)
end

function Lowerer:next_expression(cc)
    if self.cursor >= cc.expressions.order_count then
        local returned = cc.lower.by_expression[cc.program.returned.id]
        if returned.generation ~= cc.generation then return cc:rejected(DIAG_TYPE, 0) end
        if cc.instructions.count >= CAP.instructions then
            return cc:rejected(DIAG_INSTRUCTION_CAPACITY, 0)
        end
        cc.instructions:add_return(returned.register_index)
        cc.instructions.revision = cc.instructions.revision + 1
        cc.lower.revision = cc.lower.revision + 1
        return cc:lowered()
    end
    return cc.expressions.order[self.cursor]:lower(cc, self, expression_lowered)
end

function Lowerer:expression_lowered(cc)
    self.cursor = self.cursor + 1
    self.lowered_count = self.lowered_count + 1
    return self:next_expression(cc)
end

expression_lowered = Lowerer.expression_lowered

function Emitter:initialize()
    self.cursor, self.emitted_count = 0, 0
    return self
end

function Emitter:append(text, cc, completed)
    local length = #text
    if cc.artifact.length + length > CAP.artifact then
        return cc:rejected(DIAG_ARTIFACT_CAPACITY, 0)
    end
    ffi.copy(cc.artifact.bytes + cc.artifact.length, text, length)
    cc.artifact.length = cc.artifact.length + length
    return completed(self, cc)
end

function ConstInstruction:project_gccjit(compiler, completed)
    return compiler:gcc_project_constant(self, completed)
end

function BinaryInstruction:project_gccjit(compiler, completed)
    return compiler:gcc_project_binary(self, completed)
end

function ReturnInstruction:project_gccjit(compiler, completed)
    return compiler:gcc_project_return(self, completed)
end

function Instruction:project_gccjit(compiler, completed)
    if self.kind == INSTRUCTION_CONST then
        return self.payload.constant:project_gccjit(compiler, completed)
    elseif self.kind == INSTRUCTION_BINARY then
        return self.payload.binary:project_gccjit(compiler, completed)
    elseif self.kind == INSTRUCTION_RETURN then
        return self.payload.returned:project_gccjit(compiler, completed)
    end
    return compiler:invalid_retained_instruction()
end

function ConstInstruction:emit(cc, emitter, completed)
    local line = ("r%d = const %s\n"):format(self.target, tostring(tonumber(self.value)))
    return emitter:append(line, cc, completed)
end

function BinaryInstruction:emit(cc, emitter, completed)
    local operator = self.operator_kind == OP_ADD and "add"
        or self.operator_kind == OP_SUBTRACT and "sub" or "mul"
    local line = ("r%d = %s r%d, r%d\n"):format(self.target, operator, self.left, self.right)
    return emitter:append(line, cc, completed)
end

function ReturnInstruction:emit(cc, emitter, completed)
    return emitter:append(("return r%d\n"):format(self.value), cc, completed)
end

function Instruction:emit(cc, emitter, completed)
    if self.kind == INSTRUCTION_CONST then
        return self.payload.constant:emit(cc, emitter, completed)
    elseif self.kind == INSTRUCTION_BINARY then
        return self.payload.binary:emit(cc, emitter, completed)
    elseif self.kind == INSTRUCTION_RETURN then
        return self.payload.returned:emit(cc, emitter, completed)
    end
    return cc:rejected(DIAG_INVALID_REFERENCE, 0)
end

local instruction_emitted

function Emitter:run(cc)
    self:initialize()
    cc.artifact.length = 0
    return self:next_instruction(cc)
end

function Emitter:next_instruction(cc)
    if self.cursor >= cc.instructions.count then
        cc.artifact.revision = cc.artifact.revision + 1
        return cc:emitted()
    end
    return cc.instructions.items[self.cursor]:emit(cc, self, instruction_emitted)
end

function Emitter:instruction_emitted(cc)
    self.cursor = self.cursor + 1
    self.emitted_count = self.emitted_count + 1
    return self:next_instruction(cc)
end

instruction_emitted = Emitter.instruction_emitted

function Compiler:compile(source)
    assert(type(source) == "string", "compiler source must be a string")
    self.status = STATUS_READY
    self.generation = self.generation + 1
    if self.generation == 0 then self.generation = 1 end
    self.diagnostic.code, self.diagnostic.offset = DIAG_NONE, 0
    self.artifact.length = 0
    if #source > CAP.source then return self:rejected(DIAG_SOURCE_CAPACITY, CAP.source) end
    self.source.length = #source
    ffi.copy(self.source.bytes, source, #source)
    self.symbols:initialize()
    self.expressions:initialize()
    self.program.binding_count, self.program.has_return = 0, 0
    return self.parser:run(self)
end

function Compiler:parsed() return self.resolver:run(self) end
function Compiler:resolved() return self.typechecker:run(self) end
function Compiler:typed() return self.lowerer:run(self) end
function Compiler:lowered() return self.emitter:run(self) end
function Compiler:emitted() return self:completed() end

function Compiler:completed()
    self.status = STATUS_SUCCEEDED
    self.revision = self.revision + 1
    return self
end

function Compiler:rejected(code, offset)
    self.status = STATUS_REJECTED
    self.diagnostic.code, self.diagnostic.offset = code, offset
    self.revision = self.revision + 1
    return self
end

function Compiler:succeeded() return self.status == STATUS_SUCCEEDED end
function Compiler:artifact_text() return ffi.string(self.artifact.bytes, self.artifact.length) end

function Compiler:diagnostic_text()
    local code = self.diagnostic.code
    if code == DIAG_NONE then return "none"
    elseif code == DIAG_SOURCE_CAPACITY then return "source capacity exhausted"
    elseif code == DIAG_SYNTAX then return "syntax error"
    elseif code == DIAG_EXPRESSION_CAPACITY then return "expression capacity exhausted"
    elseif code == DIAG_BINDING_CAPACITY then return "binding capacity exhausted"
    elseif code == DIAG_DUPLICATE_BINDING then return "duplicate binding"
    elseif code == DIAG_UNRESOLVED_NAME then return "unresolved name"
    elseif code == DIAG_TYPE then return "type error"
    elseif code == DIAG_INSTRUCTION_CAPACITY then return "instruction capacity exhausted"
    elseif code == DIAG_ARTIFACT_CAPACITY then return "artifact capacity exhausted"
    elseif code == DIAG_MISSING_RETURN then return "missing return"
    end
    return "invalid physical reference"
end

S:seal()

State.constants = {
    status = { ready = STATUS_READY, succeeded = STATUS_SUCCEEDED, rejected = STATUS_REJECTED },
    expression = { integer = EXPR_INTEGER, name = EXPR_NAME, binary = EXPR_BINARY },
    operator = { add = OP_ADD, subtract = OP_SUBTRACT, multiply = OP_MULTIPLY },
    type = { i64 = TYPE_I64 },
}

return State
