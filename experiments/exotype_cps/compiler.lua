local schema = require("cdefschema")
local Exotype = require("experiments.exotype_cps.exotype")

local Compiler = {}
Compiler.__index = Compiler

local NIL = {}

local function argument_key(value)
    if Exotype.is(value) then return "T" .. value.id end
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" or kind == "nil" then
        return kind .. ":" .. tostring(value)
    end
    return kind .. ":" .. tostring(value)
end

local function query_key(owner, property, arguments)
    local parts = { tostring(owner.id), property }
    for index = 1, #arguments do parts[#parts + 1] = argument_key(arguments[index]) end
    return table.concat(parts, "|")
end

function Compiler.new()
    return setmetatable({
        cache = {},
        active = {},
        stack = {},
        requested = {},
        generated = {},
        max_query_depth = 64,
    }, Compiler)
end

function Compiler:request_method(owner, name, property)
    local request = self.requested[owner]
    if request == nil then
        request = { order = {}, values = {} }
        self.requested[owner] = request
    end
    if request.values[name] == nil then
        request.order[#request.order + 1] = name
        request.values[name] = property
    end
end

function Compiler:query(owner, property, ...)
    assert(Exotype.is(owner), "property owner must be an exotype")
    local arguments = { ... }
    local key = query_key(owner, property, arguments)
    local cached = self.cache[key]
    if cached ~= nil then return cached == NIL and nil or cached end
    if self.active[key] then
        local trace = {}
        for index = 1, #self.stack do trace[index] = self.stack[index] end
        trace[#trace + 1] = owner.name .. "." .. property
        error("cyclic exotype property query: " .. table.concat(trace, " -> "), 2)
    end
    if #self.stack >= self.max_query_depth then
        error("exotype property query depth exceeded " .. self.max_query_depth, 2)
    end

    local implementation = owner:property(property)
    if implementation == nil then
        self.cache[key] = NIL
        return nil
    end

    self.active[key] = true
    self.stack[#self.stack + 1] = owner.name .. "." .. property
    local result = { pcall(implementation, self, owner, ...) }
    self.stack[#self.stack] = nil
    self.active[key] = nil
    if not result[1] then error(result[2], 2) end
    local value = result[2]
    self.cache[key] = value == nil and NIL or value
    if property == "__getmethod" and value ~= nil then
        self:request_method(owner, arguments[1], value)
    end
    return value
end

local function field_declaration(compiler, entry)
    Exotype.identifier(entry.name, "field name")
    local field_type
    if entry.exotype ~= nil then
        assert(Exotype.is(entry.exotype), "aggregate field type must be an exotype")
        field_type = entry.exotype.ctype_name
    else
        field_type = assert(entry.ctype, "field requires ctype or exotype")
    end
    local count = entry.count
    if count ~= nil then
        assert(type(count) == "number" and count >= 1 and count == math.floor(count),
            "field count must be a positive integer")
        return ("    %s %s[%d];"):format(field_type, entry.name, count)
    end
    return ("    %s %s;"):format(field_type, entry.name)
end

function Compiler:collect_layout(owner, order, seen)
    if seen[owner] then return end
    seen[owner] = true
    local entries = assert(self:query(owner, "__getentries"),
        owner.name .. " has no __getentries property")
    for index = 1, #entries do
        local dependency = entries[index].exotype
        if dependency ~= nil then self:collect_layout(dependency, order, seen) end
    end
    order[#order + 1] = { owner = owner, entries = entries }
end

function Compiler:materialize(item)
    local owner, entries = item.owner, item.entries
    if owner.descriptor ~= nil then return owner.descriptor end

    local context = schema.context {
        name = owner.name,
        version = 1,
        prefix = owner.ctype_prefix,
    }
    local declarations = { ("typedef struct %s {"):format(owner.ctype_name) }
    for index = 1, #entries do
        declarations[#declarations + 1] = field_declaration(self, entries[index])
    end
    declarations[#declarations + 1] = ("} %s;"):format(owner.ctype_name)
    context:cdef(table.concat(declarations, "\n"))
    local descriptor = context:product(owner.ctype_name)

    local request = self.requested[owner]
    local installed = {}
    if request ~= nil then
        for index = 1, #request.order do
            local name = request.order[index]
            local property = request.values[name]
            assert(type(property) == "table" and type(property.compile) == "function",
                owner.name .. ".__getmethod(" .. name .. ") did not return a method property")
            local implementation, listing = property.compile(self, owner, descriptor, installed)
            assert(type(implementation) == "function", "method property did not compile a function")
            descriptor[name] = implementation
            installed[name] = implementation
            self.generated[owner] = self.generated[owner] or {}
            self.generated[owner][name] = listing
        end
    end

    context:seal()
    owner.context = context
    owner.descriptor = descriptor
    owner.compiled_methods = installed
    return descriptor
end

function Compiler:compile(owner, method_names)
    assert(Exotype.is(owner), "compile expects an exotype")
    if owner.descriptor ~= nil then
        for index = 1, #(method_names or {}) do
            local name = method_names[index]
            assert(owner.compiled_methods[name] ~= nil,
                owner.name .. " is sealed without method " .. name .. "; construct a new exotype")
        end
        return owner.descriptor
    end

    for index = 1, #(method_names or {}) do
        local name = method_names[index]
        assert(self:query(owner, "__getmethod", name) ~= nil,
            owner.name .. " has no method " .. name)
    end

    local order = {}
    self:collect_layout(owner, order, {})
    for index = 1, #order do self:materialize(order[index]) end
    return owner.descriptor
end

return Compiler
