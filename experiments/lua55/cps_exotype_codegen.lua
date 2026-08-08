-- Lua 5.5 bytecode -> proper exotypes -> fused residual CPS -> LuaJIT.
--
-- This file deliberately explains the staging boundaries in detail.  The code
-- that runs the guest is small and direct; most of this module exists only while
-- turning runtime-loaded bytecode into that code.

local Undump = require("experiments.lua55.undump55")

local OP = {}
for opcode, name in pairs(Undump.OPNAMES) do OP[name] = opcode end

-- ---------------------------------------------------------------------------
-- First-class properties and exotype owners
-- ---------------------------------------------------------------------------

-- A property is an identity, not a string command.  An owner can implement a
-- property with a Lua function.  The compiler evaluates that function once and
-- memoizes the result.  This is the meta-object protocol from the exotype paper.
local next_property_id = 0
local next_owner_id = 0

local function Property(name, accepts)
    next_property_id = next_property_id + 1
    return { id = next_property_id, name = name, accepts = accepts }
end

local Owner = {}
Owner.__index = Owner

local function new_owner(name, properties, payload)
    next_owner_id = next_owner_id + 1
    return setmetatable({
        id = next_owner_id,
        name = name,
        properties = properties,
        payload = payload,
        values = {},
    }, Owner)
end

-- Exact property result alternatives.  Layout, instruction effects, control
-- transfers, and complete block code are different things, so they are different
-- classes rather than one record with many optional fields.
local FrameLayout = {}
FrameLayout.__index = FrameLayout

local EffectQuote = {}
EffectQuote.__index = EffectQuote
local JumpQuote = {}
JumpQuote.__index = JumpQuote
local ForPrepQuote = {}
ForPrepQuote.__index = ForPrepQuote
local ForLoopQuote = {}
ForLoopQuote.__index = ForLoopQuote
local ReturnQuote = {}
ReturnQuote.__index = ReturnQuote
local ClosureQuote = {}
ClosureQuote.__index = ClosureQuote
local RejectQuote = {}
RejectQuote.__index = RejectQuote
local BlockQuote = {}
BlockQuote.__index = BlockQuote
local function instance_of(class, value) return getmetatable(value) == class end

local function exact(class)
    return function(value) return instance_of(class, value) end
end

local function instruction_quote(value)
    local class = getmetatable(value)
    return class == EffectQuote or class == JumpQuote or class == ForPrepQuote
        or class == ForLoopQuote or class == ReturnQuote or class == ClosureQuote
        or class == RejectQuote
end

local FRAME_LAYOUT = Property("FrameLayout", exact(FrameLayout))
local EMIT_INSTRUCTION = Property("EmitInstruction", instruction_quote)
local EXECUTE_BLOCK = Property("ExecuteBlock", exact(BlockQuote))

-- ---------------------------------------------------------------------------
-- Small source helpers
-- ---------------------------------------------------------------------------

local function constant_value(constant)
    if constant.t == "nil" then return nil end
    if constant.t == "false" then return false end
    if constant.t == "true" then return true end
    if constant.t == "int" then return tonumber(constant.v) end
    if constant.t == "flt" or constant.t == "str" then return constant.v end
    error("unsupported Lua 5.5 constant tag: " .. tostring(constant.t))
end

local function literal(value)
    if type(value) == "string" then return string.format("%q", value) end
    if value == nil then return "nil" end
    if value == true then return "true" end
    if value == false then return "false" end
    if value ~= value then return "(0/0)" end
    if value == math.huge then return "math.huge" end
    if value == -math.huge then return "-math.huge" end
    return ("%.17g"):format(value)
end

local function label(instruction)
    return ("pc_%d_%s"):format(instruction.pc, instruction.name:lower())
end

local function bind_upvalue(fn, name, value)
    for index = 1, math.huge do
        local upvalue_name = debug.getupvalue(fn, index)
        if upvalue_name == nil then break end
        if upvalue_name == name then
            debug.setupvalue(fn, index, value)
            return
        end
    end
    error("generated block has no upvalue named " .. tostring(name))
end

-- ---------------------------------------------------------------------------
-- Block quotation builder
-- ---------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

function Builder.new(start)
    return setmetatable({
        start = start,
        finish = start,
        lines = {},
        instructions = {},
        edges = {},
        children = {},
    }, Builder)
end

function Builder:add_instruction(instruction)
    self.finish = instruction
    self.instructions[#self.instructions + 1] = instruction
end

function Builder:add_line(line) self.lines[#self.lines + 1] = line end

function Builder:edge(role, target)
    assert(target, "generated CPS edge has no target")
    local name = "EDGE_" .. (#self.edges + 1)
    self.edges[#self.edges + 1] = { name = name, role = role, target = target }
    return name
end

function Builder:child(index)
    local name = "CHILD_" .. (#self.children + 1)
    self.children[#self.children + 1] = { name = name, index = index }
    return name
end

-- An effect can be fused with its successor only when that successor has no
-- other predecessor.  Join points stay separate CPS functions.
function EffectQuote:compose(builder)
    for index = 1, #self.lines do builder:add_line(self.lines[index]) end
    if self.next._exo_predecessors == 1 then return self.next end
    local successor = builder:edge("next", self.next)
    builder:add_line("return " .. successor .. "(self)")
end

function JumpQuote:compose(builder)
    builder:add_line("return " .. builder:edge("target", self.target) .. "(self)")
end

function ForPrepQuote:compose(builder)
    local body = builder:edge("body", self.body)
    local exit = builder:edge("exit", self.exit)
    local A = self.A
    builder:add_line(("local init, limit, step = r[%d], r[%d], r[%d]"):format(A, A + 1, A + 2))
    builder:add_line("if step == 0 then error(\"'for' step is zero\") end")
    builder:add_line("if step > 0 and init > limit or step < 0 and init < limit then")
    builder:add_line("  return " .. exit .. "(self)")
    builder:add_line("end")
    builder:add_line(("r[%d], r[%d], r[%d] = limit, step, init"):format(A, A + 1, A + 2))
    builder:add_line("return " .. body .. "(self)")
end

function ForLoopQuote:compose(builder)
    local repeated = builder:edge("repeat_target", self.repeat_target)
    local exit = builder:edge("exit", self.exit)
    local A = self.A
    builder:add_line(("local step = r[%d]"):format(A + 1))
    builder:add_line(("local index = r[%d] + step"):format(A + 2))
    builder:add_line(("r[%d] = index"):format(A + 2))
    builder:add_line(("if step > 0 and index <= r[%d] or step < 0 and index >= r[%d] then"):format(A, A))
    builder:add_line("  return " .. repeated .. "(self)")
    builder:add_line("end")
    builder:add_line("return " .. exit .. "(self)")
end

function ReturnQuote:compose(builder)
    if self.count == 0 then builder:add_line("return"); return end
    local values = {}
    for index = 0, self.count - 1 do values[#values + 1] = ("r[%d]"):format(self.A + index) end
    builder:add_line("return " .. table.concat(values, ", "))
end

function ClosureQuote:compose(builder)
    local child = builder:child(self.child_index)
    local successor = builder:edge("next", self.next)
    builder:add_line(("r[%d] = %s"):format(self.A, child))
    builder:add_line("return " .. successor .. "(self)")
end

function RejectQuote:compose(builder)
    builder:add_line("error(" .. string.format("%q", self.message) .. ")")
end

function BlockQuote:source()
    local upvalues = {}
    for index = 1, #self.edges do upvalues[#upvalues + 1] = self.edges[index].name end
    for index = 1, #self.children do upvalues[#upvalues + 1] = self.children[index].name end
    local out = {}
    if #upvalues > 0 then out[#out + 1] = "local " .. table.concat(upvalues, ", ") end
    out[#out + 1] = "return function(self)"
    out[#out + 1] = "  local r = self.r"
    for index = 1, #self.lines do out[#out + 1] = "  " .. self.lines[index] end
    out[#out + 1] = "end"
    return table.concat(out, "\n")
end


-- ---------------------------------------------------------------------------
-- Concrete opcode leaves
-- ---------------------------------------------------------------------------

-- Each decoded instruction receives one concrete leaf.  Dispatch happens once
-- while linking bytecode.  Semantic behavior then belongs to the leaf method;
-- the hot VM never switches on an opcode number.
local Opcode = {}
Opcode.__index = Opcode

function Opcode:emit(instruction)
    return setmetatable({
        message = ("unsupported Lua 5.5 opcode %s at pc %d"):format(
            instruction.name, instruction.pc),
    }, RejectQuote)
end

local function effect_leaf(make_lines)
    local leaf = setmetatable({}, Opcode)
    leaf.__index = leaf
    function leaf:emit(instruction, compiler)
        return setmetatable({ lines = make_lines(instruction, compiler), next = instruction.next }, EffectQuote)
    end
    return leaf
end

local MOVE = effect_leaf(function(i) return { ("r[%d] = r[%d]"):format(i.A, i.B) } end)
local LOADI = effect_leaf(function(i) return { ("r[%d] = %d"):format(i.A, i.sBx) } end)
local LOADF = effect_leaf(function(i) return { ("r[%d] = %s"):format(i.A, literal(i.sBx + 0.0)) } end)
local LOADK = effect_leaf(function(i, compiler)
    return { ("r[%d] = %s"):format(i.A, literal(compiler.constants[i.Bx + 1])) }
end)
local VARARGPREP = effect_leaf(function() return {} end)

local function binary_leaf(operator)
    return effect_leaf(function(i)
        return { ("r[%d] = r[%d] %s r[%d]"):format(i.A, i.B, operator, i.C) }
    end)
end

local function constant_binary_leaf(operator)
    return effect_leaf(function(i)
        return { ("r[%d] = r[%d] %s %s"):format(i.A, i.B, operator, literal(i.constant)) }
    end)
end

local JMP = setmetatable({}, Opcode)
JMP.__index = JMP
function JMP:emit(i) return setmetatable({ target = i.target }, JumpQuote) end

local FORPREP = setmetatable({}, Opcode)
FORPREP.__index = FORPREP
function FORPREP:emit(i)
    return setmetatable({ A = i.A, body = i.body, exit = i.exit }, ForPrepQuote)
end

local FORLOOP = setmetatable({}, Opcode)
FORLOOP.__index = FORLOOP
function FORLOOP:emit(i)
    return setmetatable({ A = i.A, repeat_target = i.repeat_target, exit = i.exit }, ForLoopQuote)
end

local CLOSURE = setmetatable({}, Opcode)
CLOSURE.__index = CLOSURE
function CLOSURE:emit(i)
    return setmetatable({ A = i.A, child_index = i.Bx + 1, next = i.next }, ClosureQuote)
end

local RETURN = setmetatable({}, Opcode)
RETURN.__index = RETURN
function RETURN:emit(i)
    local count = i.B - 1
    assert(count >= 0, "exotyped CPS requires a fixed RETURN")
    return setmetatable({ A = i.A, count = count }, ReturnQuote)
end

local RETURN0 = setmetatable({}, Opcode)
RETURN0.__index = RETURN0
function RETURN0:emit() return setmetatable({ A = 0, count = 0 }, ReturnQuote) end

local RETURN1 = setmetatable({}, Opcode)
RETURN1.__index = RETURN1
function RETURN1:emit(i) return setmetatable({ A = i.A, count = 1 }, ReturnQuote) end

local LEAVES = {
    MOVE = MOVE, LOADI = LOADI, LOADF = LOADF, LOADK = LOADK,
    ADD = binary_leaf("+"), SUB = binary_leaf("-"),
    MUL = binary_leaf("*"), DIV = binary_leaf("/"),
    ADDK = constant_binary_leaf("+"), SUBK = constant_binary_leaf("-"),
    MULK = constant_binary_leaf("*"), DIVK = constant_binary_leaf("/"),
    JMP = JMP, FORPREP = FORPREP, FORLOOP = FORLOOP,
    CLOSURE = CLOSURE, VARARGPREP = VARARGPREP,
    RETURN = RETURN, RETURN0 = RETURN0, RETURN1 = RETURN1,
}

-- ---------------------------------------------------------------------------
-- Cold bytecode linking
-- ---------------------------------------------------------------------------

local EDGE_ROLES = {
    "next", "target", "taken", "fallthrough", "matched", "skipped",
    "body", "exit", "repeat_target",
}

local function link_proto(proto)
    if proto._exotype_cps_linked then return end
    proto._exotype_cps_linked = true
    local code = proto.code

    local constants = {}
    for index = 1, #proto.k do constants[index] = constant_value(proto.k[index]) end
    proto._exotype_constants = constants

    for index, instruction in ipairs(code) do
        instruction.pc = index - 1
        instruction._exotype_leaf = LEAVES[instruction.name] or Opcode
        instruction._exo_predecessors = 0
        local opcode = instruction.op
        if opcode == OP.ADDK or opcode == OP.SUBK or opcode == OP.MULK or opcode == OP.DIVK then
            instruction.constant = constants[instruction.C + 1]
        end
    end

    local function edge(instruction, role, target)
        assert(target, ("missing %s edge at pc %d"):format(role, instruction.pc))
        instruction[role] = target
    end

    for index, instruction in ipairs(code) do
        local opcode = instruction.op
        if opcode == OP.RETURN or opcode == OP.RETURN0 or opcode == OP.RETURN1
            or opcode == OP.MMBIN or opcode == OP.MMBINI or opcode == OP.MMBINK then
            -- Terminal or deliberately unsupported fallback.
        elseif opcode == OP.JMP then
            edge(instruction, "target", code[index + 1 + instruction.sJ])
        elseif opcode == OP.EQ or opcode == OP.LT or opcode == OP.LE then
            local jump = code[index + 1]
            edge(instruction, "taken", code[index + 2 + jump.sJ])
            edge(instruction, "fallthrough", code[index + 2])
        elseif opcode == OP.TEST then
            edge(instruction, "matched", code[index + 1])
            edge(instruction, "skipped", code[index + 2])
        elseif opcode == OP.FORPREP then
            edge(instruction, "body", code[index + 1])
            edge(instruction, "exit", code[index + instruction.Bx + 2])
        elseif opcode == OP.FORLOOP then
            edge(instruction, "repeat_target", code[index + 1 - instruction.Bx])
            edge(instruction, "exit", code[index + 1])
        elseif opcode == OP.LFALSESKIP or opcode == OP.NEWTABLE
            or opcode == OP.ADDK or opcode == OP.SUBK or opcode == OP.MULK
            or opcode == OP.DIVK or opcode == OP.ADD or opcode == OP.SUB
            or opcode == OP.MUL or opcode == OP.DIV then
            edge(instruction, "next", code[index + 2])
        else
            edge(instruction, "next", code[index + 1])
        end
    end

    for _, instruction in ipairs(code) do
        for _, role in ipairs(EDGE_ROLES) do
            local target = instruction[role]
            if target ~= nil then target._exo_predecessors = target._exo_predecessors + 1 end
        end
    end
    code[1]._exo_predecessors = code[1]._exo_predecessors + 1
end

-- ---------------------------------------------------------------------------
-- Exotype compiler
-- ---------------------------------------------------------------------------

local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(proto, label_name, stats)
    link_proto(proto)
    local compiler = setmetatable({
        proto = proto,
        label = label_name,
        stats = stats,
        constants = proto._exotype_constants,
        query_cache = {},
        active = {},
        query_stack = {},
        instruction_owners = {},
        block_owners = {},
        entries = {},
        children = {},
    }, Compiler)

    compiler.prototype_owner = new_owner(label_name .. ":prototype", {
        [FRAME_LAYOUT] = function()
            return setmetatable({ register_count = proto.maxstacksize }, FrameLayout)
        end,
    }, proto)
    return compiler
end

function Compiler:query(owner, property)
    local key = owner.id .. ":" .. property.id
    local cached = self.query_cache[key] or owner.values[property]
    if cached ~= nil then return cached end
    if self.active[key] then
        local trace = {}
        for index = 1, #self.query_stack do trace[index] = self.query_stack[index] end
        trace[#trace + 1] = owner.name .. "." .. property.name
        error("cyclic exotype property query: " .. table.concat(trace, " -> "))
    end
    local implementation = owner.properties[property]
    assert(implementation, owner.name .. " does not implement " .. property.name)
    self.active[key] = true
    self.query_stack[#self.query_stack + 1] = owner.name .. "." .. property.name
    local result = { pcall(implementation, self, owner) }
    self.query_stack[#self.query_stack] = nil
    self.active[key] = nil
    if not result[1] then error(result[2], 2) end
    local value = result[2]
    assert(property.accepts(value),
        owner.name .. "." .. property.name .. " returned the wrong property type")
    owner.values[property] = value
    self.query_cache[key] = value
    self.stats.property_queries = self.stats.property_queries + 1
    return value
end

function Compiler:instruction_owner(instruction)
    local slot = instruction.pc + 1
    local owner = self.instruction_owners[slot]
    if owner ~= nil then return owner end
    owner = new_owner(self.label .. ":instruction:" .. instruction.pc, {
        [EMIT_INSTRUCTION] = function(cc)
            return instruction._exotype_leaf:emit(instruction, cc)
        end,
    }, instruction)
    self.instruction_owners[slot] = owner
    return owner
end

function Compiler:block_owner(instruction)
    local slot = instruction.pc + 1
    local owner = self.block_owners[slot]
    if owner ~= nil then return owner end

    owner = new_owner(self.label .. ":block:" .. instruction.pc, {
        [EXECUTE_BLOCK] = function(cc)
            local builder = Builder.new(instruction)
            local current = instruction
            while current ~= nil do
                builder:add_instruction(current)
                local quote = cc:query(cc:instruction_owner(current), EMIT_INSTRUCTION)
                current = quote:compose(builder, cc)
            end
            return setmetatable({
                start = builder.start, finish = builder.finish,
                lines = builder.lines, instructions = builder.instructions,
                edges = builder.edges, children = builder.children,
            }, BlockQuote)
        end,
    }, instruction)
    self.block_owners[slot] = owner
    return owner
end

local function projected_operands(instruction)
    return {
        A = instruction.A, B = instruction.B, C = instruction.C,
        Bx = instruction.Bx, sBx = instruction.sBx, k = instruction.k,
        constant = instruction.constant,
    }
end

function Compiler:record(owner, quote, source)
    local instructions = {}
    for index = 1, #quote.instructions do
        local instruction = quote.instructions[index]
        instructions[index] = {
            pc = instruction.pc, opcode = instruction.name,
            operands = projected_operands(instruction),
        }
    end
    local successors = {}
    for index = 1, #quote.edges do
        local edge = quote.edges[index]
        successors[index] = { role = edge.role, pc = edge.target.pc, opcode = edge.target.name }
    end
    local entry = {
        key = owner.name,
        name = ("block_%d_%d"):format(quote.start.pc, quote.finish.pc),
        start_pc = quote.start.pc, end_pc = quote.finish.pc,
        instructions = instructions, successors = successors, source = source,
    }
    local projection = self.stats.projection
    projection.blocks[#projection.blocks + 1] = entry
    projection.by_key[entry.key] = entry
    projection.compile_order[#projection.compile_order + 1] = entry.key
    self.stats.lines[#self.stats.lines + 1] = source
end

function Compiler:compile_baseline(slot, owner, quote)
    local source = quote:source()
    local chunk, message = loadstring(source, "@lua55-exotype:" .. owner.name)
    assert(chunk, message)
    local fn = chunk()

    -- Publish before following successors so ordinary control cycles close.
    self.entries[slot] = fn
    self.stats.compiled_blocks = self.stats.compiled_blocks + 1
    self.stats.fused_instructions = self.stats.fused_instructions + #quote.instructions
    self.stats.generated_bytes = self.stats.generated_bytes + #source
    self:record(owner, quote, source)

    for index = 1, #quote.edges do
        local edge = quote.edges[index]
        bind_upvalue(fn, edge.name, self:entry(edge.target))
    end
    for index = 1, #quote.children do
        local child = quote.children[index]
        bind_upvalue(fn, child.name, self:child(child.index))
    end
    return fn
end


function Compiler:entry(instruction)
    local slot = instruction.pc + 1
    local existing = self.entries[slot]
    if existing ~= nil then return existing end

    local owner = self:block_owner(instruction)
    local quote = self:query(owner, EXECUTE_BLOCK)
    return self:compile_baseline(slot, owner, quote)
end

local compile_proto

function Compiler:child(index)
    local child = self.children[index]
    if child ~= nil then return child end
    child = compile_proto(self.proto.protos[index], self.label .. ":child" .. index, self.stats)
    self.children[index] = child
    return child
end

local Program = {}
Program.__index = Program

function Program:prepare()
    local compiler = self.compiler
    if compiler.layout == nil then
        compiler.layout = compiler:query(compiler.prototype_owner, FRAME_LAYOUT)
        compiler.state = { r = {}, top = 0 }
    end
    if self.root == nil then self.root = compiler:entry(compiler.proto.code[1]) end
    return self
end

function Program:call(...)
    self:prepare()
    local compiler = self.compiler
    local layout = compiler.layout
    local state, registers = compiler.state, compiler.state.r
    for register = 0, layout.register_count - 1 do registers[register] = nil end
    local count = select("#", ...)
    for index = 1, count do registers[index - 1] = select(index, ...) end
    state.top = count
    return self.root(state)
end

function Program:entrypoint() return self.public_entry end

compile_proto = function(proto, label_name, stats)
    local compiler = Compiler.new(proto, label_name, stats)
    local program = setmetatable({ compiler = compiler }, Program)
    program.public_entry = function(...) return program:call(...) end
    return program.public_entry, program
end

local M = {}


function M.compile(proto, label_name)
    local stats = {
        compiled_blocks = 0,
        fused_instructions = 0,
        generated_bytes = 0,
        property_queries = 0,
        lines = {},
        projection = { blocks = {}, by_key = {}, compile_order = {} },
    }
    local fn, program = compile_proto(proto, label_name or "prototype", stats)
    program.stats = stats
    return fn, program, stats
end

function M.load(bytes, label_name)
    local proto = Undump.undump(bytes)
    local fn, program, stats = M.compile(proto, label_name)
    return fn, proto, program, stats
end

function M.loadfile(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return M.load(bytes, path)
end

function M.source(stats) return table.concat(stats.lines, "\n\n") end
function M.projection(stats) return stats.projection end

M.properties = {
    FrameLayout = FRAME_LAYOUT, EmitInstruction = EMIT_INSTRUCTION,
    ExecuteBlock = EXECUTE_BLOCK,
}

return M
