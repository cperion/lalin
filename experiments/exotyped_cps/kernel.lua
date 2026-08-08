local Kernel = {}

local next_owner_id = 0
local next_operation_id = 0

local Owner = {}
Owner.__index = Owner
local Operation = {}
Operation.__index = Operation

local ExpressionQuote = {}
ExpressionQuote.__index = ExpressionQuote
local EffectQuote = {}
EffectQuote.__index = EffectQuote
local CpsQuote = {}
CpsQuote.__index = CpsQuote

local function identifier(value, what)
    assert(type(value) == "string" and value:match("^[_%a][_%w]*$"),
        what .. " must be an identifier")
    return value
end

function Kernel.owner(spec)
    next_owner_id = next_owner_id + 1
    local owner = setmetatable({
        id = next_owner_id,
        name = identifier(assert(spec.name), "owner name"),
        layout_property = assert(spec.layout, "owner requires a layout property"),
        operation_properties = spec.operations or {},
        parameters = spec.parameters,
        stats = spec.stats or { layout = 0, operations = {} },
        operation_values = {},
        ctype_prefix = ("ExotypedCpsV1_T%d_"):format(next_owner_id),
    }, Owner)
    owner.ctype_name = owner.ctype_prefix .. owner.name
    return owner
end

function Kernel.operation(name, quote_kind)
    next_operation_id = next_operation_id + 1
    return setmetatable({
        id = next_operation_id,
        name = identifier(name, "operation name"),
        quote_kind = quote_kind,
    }, Operation)
end

function Kernel.dependency(owner, operation)
    assert(getmetatable(owner) == Owner, "dependency owner must be an exotype")
    assert(getmetatable(operation) == Operation, "dependency operation must be an operation")
    return { owner = owner, operation = operation }
end

function Kernel.expression(parameters, emit_expression)
    return setmetatable({
        parameters = parameters or {},
        emit_expression = assert(emit_expression),
    }, ExpressionQuote)
end

function Kernel.effect(parameters, emit_statements)
    return setmetatable({
        parameters = parameters or {},
        emit_statements = assert(emit_statements),
    }, EffectQuote)
end

function Kernel.cps(parameters, dependencies, emit_body)
    return setmetatable({
        parameters = parameters or {},
        dependencies = dependencies or {},
        emit_body = assert(emit_body),
    }, CpsQuote)
end

local function function_head(parameters)
    if #parameters == 0 then return "function(self)" end
    return "function(self, " .. table.concat(parameters, ", ") .. ")"
end

function ExpressionQuote:source(_resolve)
    return function_head(self.parameters) .. " return "
        .. self.emit_expression("self", self.parameters) .. " end"
end

function EffectQuote:source(_resolve)
    local statements = self.emit_statements("self", self.parameters)
    return function_head(self.parameters) .. " " .. table.concat(statements, "; ")
        .. "; return self end"
end

function CpsQuote:source(resolve)
    local body = self.emit_body(resolve, "self", self.parameters)
    return function_head(self.parameters) .. " " .. table.concat(body, "; ") .. " end"
end

function Kernel.quote_kind(value)
    local metatable = getmetatable(value)
    if metatable == ExpressionQuote then return "expression" end
    if metatable == EffectQuote then return "effect" end
    if metatable == CpsQuote then return "cps" end
end

function Kernel.is_owner(value) return getmetatable(value) == Owner end
function Kernel.is_operation(value) return getmetatable(value) == Operation end

function Owner:operation_property(operation) return self.operation_properties[operation] end
function Owner:__tostring() return ("<exotype %s#%d>"):format(self.name, self.id) end
function Operation:__tostring() return ("<operation %s#%d>"):format(self.name, self.id) end

function Kernel.memoize(key_of, construct)
    local cache = {}
    return function(...)
        local key = key_of(...)
        if cache[key] == nil then cache[key] = construct(...) end
        return cache[key]
    end
end

Kernel.Owner = Owner
Kernel.Operation = Operation
Kernel.ExpressionQuote = ExpressionQuote
Kernel.EffectQuote = EffectQuote
Kernel.CpsQuote = CpsQuote
Kernel.identifier = identifier
return Kernel
