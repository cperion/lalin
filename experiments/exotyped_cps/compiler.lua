local schema = require("cdefschema")
local K = require("experiments.exotyped_cps.kernel")

local Compiler = {}
Compiler.__index = Compiler
local Program = {}
Program.__index = Program

local function operation_key(owner, operation)
    return owner.id .. ":" .. operation.id
end

local function load_generated(source)
    local chunk, message = loadstring(source)
    assert(chunk, message)
    return chunk()
end

function Compiler.new()
    return setmetatable({
        layout_cache = {},
        operation_cache = {},
        active = {},
        stack = {},
        max_query_depth = 128,
        physical_units = {},
    }, Compiler)
end

function Compiler:enter_query(key, label)
    if self.active[key] then
        local trace = {}
        for index = 1, #self.stack do trace[index] = self.stack[index] end
        trace[#trace + 1] = label
        error("cyclic exotype property query: " .. table.concat(trace, " -> "), 3)
    end
    assert(#self.stack < self.max_query_depth, "exotype property query depth exceeded")
    self.active[key] = true
    self.stack[#self.stack + 1] = label
end

function Compiler:leave_query(key)
    self.stack[#self.stack] = nil
    self.active[key] = nil
end

function Compiler:layout(owner)
    assert(K.is_owner(owner), "layout owner must be an exotype")
    if self.layout_cache[owner] ~= nil then return self.layout_cache[owner] end
    if owner.layout_value ~= nil then
        self.layout_cache[owner] = owner.layout_value
        return owner.layout_value
    end
    local key, label = "layout:" .. owner.id, owner.name .. ".layout"
    self:enter_query(key, label)
    local result = { pcall(owner.layout_property, self, owner) }
    self:leave_query(key)
    if not result[1] then error(result[2], 2) end
    assert(type(result[2]) == "table", owner.name .. " layout property must return entries")
    owner.layout_value = result[2]
    self.layout_cache[owner] = result[2]
    return result[2]
end

function Compiler:operation(owner, operation)
    assert(K.is_owner(owner), "operation owner must be an exotype")
    assert(K.is_operation(operation), "operation query requires an operation identity")
    local key = operation_key(owner, operation)
    if self.operation_cache[key] ~= nil then return self.operation_cache[key] end
    if owner.operation_values[operation] ~= nil then
        self.operation_cache[key] = owner.operation_values[operation]
        return owner.operation_values[operation]
    end
    local property = owner:operation_property(operation)
    assert(type(property) == "function", owner.name .. " does not implement " .. operation.name)
    self:enter_query("operation:" .. key, owner.name .. "." .. operation.name)
    local result = { pcall(property, self, owner, operation) }
    self:leave_query("operation:" .. key)
    if not result[1] then error(result[2], 2) end
    local quotation = result[2]
    assert(K.quote_kind(quotation) == operation.quote_kind,
        owner.name .. "." .. operation.name .. " returned the wrong quotation kind")
    owner.operation_values[operation] = quotation
    self.operation_cache[key] = quotation
    return quotation
end

local function field_declaration(entry)
    K.identifier(entry.name, "field name")
    local ctype
    if entry.owner ~= nil then
        assert(K.is_owner(entry.owner), "field owner must be an exotype")
        ctype = entry.owner.ctype_name
    else
        ctype = assert(entry.ctype, "field requires ctype or owner")
    end
    if entry.count ~= nil then
        assert(entry.count >= 1 and entry.count == math.floor(entry.count),
            "field count must be a positive integer")
        return ("    %s %s[%d];"):format(ctype, entry.name, entry.count)
    end
    return ("    %s %s;"):format(ctype, entry.name)
end

function Compiler:collect_physical(owner, order, seen)
    if seen[owner] then return end
    seen[owner] = true
    local entries = self:layout(owner)
    for index = 1, #entries do
        if entries[index].owner ~= nil then
            self:collect_physical(entries[index].owner, order, seen)
        end
    end
    order[#order + 1] = { owner = owner, entries = entries }
end

function Compiler:materialize_physical(owner)
    if self.physical_units[owner] ~= nil then return self.physical_units[owner] end
    if owner.physical_unit ~= nil then
        self.physical_units[owner] = owner.physical_unit
        return owner.physical_unit
    end
    local order = {}
    self:collect_physical(owner, order, {})
    for index = 1, #order do
        local item = order[index]
        if self.physical_units[item.owner] == nil and item.owner.physical_unit ~= nil then
            self.physical_units[item.owner] = item.owner.physical_unit
        elseif self.physical_units[item.owner] == nil then
            local context = schema.context {
                name = item.owner.name, version = 1, prefix = item.owner.ctype_prefix,
            }
            local declaration = { ("typedef struct %s {"):format(item.owner.ctype_name) }
            for field = 1, #item.entries do
                declaration[#declaration + 1] = field_declaration(item.entries[field])
            end
            declaration[#declaration + 1] = ("} %s;"):format(item.owner.ctype_name)
            context:cdef(table.concat(declaration, "\n"))
            local descriptor = context:product(item.owner.ctype_name)
            context:seal()
            local unit = {
                owner = item.owner, context = context, descriptor = descriptor,
                declaration = table.concat(declaration, "\n"),
            }
            item.owner.physical_unit = unit
            self.physical_units[item.owner] = unit
        end
    end
    return self.physical_units[owner]
end

function Compiler:compile(root_owner, root_operation)
    assert(K.is_owner(root_owner) and K.is_operation(root_operation),
        "compile requires a root owner and operation")

    local queue = { K.dependency(root_owner, root_operation) }
    local requested, ordered = {}, {}
    local cursor = 1
    while cursor <= #queue do
        local request = queue[cursor]
        cursor = cursor + 1
        local key = operation_key(request.owner, request.operation)
        if requested[key] == nil then
            local quotation = self:operation(request.owner, request.operation)
            local item = {
                key = key, owner = request.owner, operation = request.operation, quotation = quotation,
            }
            requested[key] = item
            ordered[#ordered + 1] = item
            if getmetatable(quotation) == K.CpsQuote then
                for index = 1, #quotation.dependencies do
                    queue[#queue + 1] = quotation.dependencies[index]
                end
            end
        end
    end

    local physical_seen = {}
    for index = 1, #ordered do
        local owner = ordered[index].owner
        if not physical_seen[owner] then
            self:materialize_physical(owner)
            physical_seen[owner] = true
        end
    end

    local names = {}
    for index = 1, #ordered do names[ordered[index].key] = "operation_" .. index end
    local source = { "return function()" }
    if #ordered > 0 then
        local declarations = {}
        for index = 1, #ordered do declarations[index] = names[ordered[index].key] end
        source[#source + 1] = "local " .. table.concat(declarations, ", ")
    end
    local function resolve(dependency)
        local name = names[operation_key(dependency.owner, dependency.operation)]
        assert(name ~= nil, "quotation references an undeclared operation dependency")
        return name
    end
    for index = 1, #ordered do
        local item = ordered[index]
        source[#source + 1] = names[item.key] .. " = " .. item.quotation:source(resolve)
    end
    local returned = {}
    for index = 1, #ordered do returned[index] = names[ordered[index].key] end
    source[#source + 1] = "return { " .. table.concat(returned, ", ") .. " }"
    source[#source + 1] = "end"
    local listing = table.concat(source, "\n")
    local functions = load_generated(listing)()

    local program = setmetatable({
        compiler = self, root_owner = root_owner, root_operation = root_operation,
        ordered = ordered, functions = functions, by_key = {}, listing = listing,
    }, Program)
    for index = 1, #ordered do program.by_key[ordered[index].key] = functions[index] end
    return program
end

function Program:operation(owner, operation)
    local implementation = self.by_key[operation_key(owner, operation)]
    assert(implementation ~= nil, "operation is not in this program's demand closure")
    return implementation
end

function Program:entry() return self:operation(self.root_owner, self.root_operation) end
function Program:new(owner)
    owner = owner or self.root_owner
    return self.compiler.physical_units[owner].descriptor()
end

return Compiler
