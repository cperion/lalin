-- moonlift.mem
--
-- Host-side memory ceremony DSL.
--
-- This module is intentionally a small staged API, not a hidden runtime memory
-- system. It lets Lua declare memory topology and protocol-shaped operations,
-- while producing inspectable Moonlift-shaped declarations.
--
-- Canonical grammar:
--   noun "name" { declaration }
--   owner:verb { request } { outcomes }
--   borrowed { dynamic_extent }

local M = { _VERSION = "moonlift.mem 0.1.0" }

local Decl = {}
Decl.__index = Decl

local World = {}
World.__index = function(self, k)
    return World[k] or self.scopes[k]
end

local Scope = {}
Scope.__index = function(self, k)
    return Scope[k] or self.entries[k]
end

local Store = {}
Store.__index = Store

local Arena = {}
Arena.__index = Arena

local ResourceTable = {}
ResourceTable.__index = ResourceTable

local Operation = {}
Operation.__index = Operation

local Borrowed = {}
Borrowed.__index = Borrowed

M.World = World
M.Scope = Scope
M.Store = Store
M.Arena = Arena
M.ResourceTable = ResourceTable
M.Operation = Operation
M.Borrowed = Borrowed

local function fail(msg, level)
    error("moonlift.mem: " .. msg, (level or 1) + 1)
end

local function is_array_slot(k)
    return type(k) == "number" and k >= 1 and k % 1 == 0
end

local function assert_name(name, what)
    if type(name) ~= "string" or name == "" then
        fail((what or "name") .. " must be a non-empty string", 3)
    end
end

local function shallow_copy(t)
    local out = {}
    if t then for k, v in pairs(t) do out[k] = v end end
    return out
end

local function snake_to_pascal(s)
    assert_name(s, "identifier")
    local out = {}
    for part in s:gmatch("[^_%-%s]+") do
        out[#out + 1] = part:sub(1, 1):upper() .. part:sub(2)
    end
    return table.concat(out)
end

local function pascal_to_snake(s)
    s = tostring(s)
    s = s:gsub("Handle$", "")
    s = s:gsub("(%u)(%u%l)", "%1_%2")
    s = s:gsub("(%l)(%u)", "%1_%2")
    return s:lower()
end

local function singular_name(name)
    if name:match("ies$") then return name:gsub("ies$", "y") end
    if name:match("ses$") then return name:gsub("es$", "") end
    if name:match("s$") then return name:gsub("s$", "") end
    return name
end

local function type_name(x)
    if type(x) == "string" then return x end
    if type(x) == "table" then
        if type(x.name) == "string" then return x.name end
        if type(x.type_name) == "string" then return x.type_name end
        if type(x.moonlift_name) == "string" then return x.moonlift_name end
    end
    return tostring(x)
end

local function append(out, line)
    out[#out + 1] = line or ""
end

local function is_decl(x, kind)
    return type(x) == "table" and getmetatable(x) == Decl and (kind == nil or x.kind == kind)
end

local function make_decl(kind, name)
    assert_name(name, kind .. " name")
    return setmetatable({ kind = kind, name = name }, Decl)
end

local function check_body_table(body, kind)
    if type(body) ~= "table" then
        fail(kind .. " body must be a table", 3)
    end
end

local function collect_children(body, parent_kind)
    check_body_table(body, parent_kind)
    local children = {}
    for i, v in ipairs(body) do
        if not is_decl(v) then
            fail(parent_kind .. " child " .. tostring(i) .. " is not a mem declaration", 4)
        end
        children[#children + 1] = v
    end
    return children
end

local function collect_config(body, kind)
    check_body_table(body, kind)
    local cfg = {}
    for k, v in pairs(body) do
        if not is_array_slot(k) then cfg[k] = v end
    end
    return cfg
end

local function store_base_name(store)
    if store.config.base then return tostring(store.config.base) end
    if store.config.handle then return tostring(store.config.handle):gsub("Handle$", "") end
    return snake_to_pascal(singular_name(store.name))
end

local function store_names(store)
    local base = store_base_name(store)
    return {
        base = base,
        handle = store.config.handle or (base .. "Handle"),
        owner = store.config.owner or (base .. "StoreOwner"),
        input = store.config.borrow_input or ("Borrow" .. base .. "Input"),
        output = store.config.borrow_output or ("Borrow" .. base .. "Output"),
        region = store.config.borrow_region or ("borrow_" .. pascal_to_snake(base)),
        record = type_name(store.config.record or store.config.of or (base .. "Record")),
        borrowed = store.config.borrowed or ("ptr(" .. type_name(store.config.record or store.config.of or (base .. "Record")) .. ")"),
    }
end

local function arena_names(arena)
    local scope_prefix = arena.scope and snake_to_pascal(arena.scope.name) or "Memory"
    local base = arena.config.base or (scope_prefix .. snake_to_pascal(arena.name) .. "Arena")
    local snake = pascal_to_snake(base)
    return {
        base = base,
        owner = arena.config.owner or (base .. "Owner"),
        reserve_input = arena.config.reserve_input or ("Reserve" .. base .. "Input"),
        reserve_output = arena.config.reserve_output or ("Reserve" .. base .. "Output"),
        reserve_region = arena.config.reserve_region or ("reserve_" .. snake),
        reset_input = arena.config.reset_input or ("Reset" .. base .. "Input"),
        reset_output = arena.config.reset_output or ("Reset" .. base .. "Output"),
        reset_region = arena.config.reset_region or ("reset_" .. snake),
    }
end

local function resource_names(resource)
    local base = resource.config.base or snake_to_pascal(singular_name(resource.name))
    return {
        base = base,
        handle = resource.config.handle or (base .. "Handle"),
        owner = resource.config.owner or (base .. "ResourceTableOwner"),
        close_input = resource.config.close_input or ("Close" .. base .. "ResourceInput"),
        close_output = resource.config.close_output or ("Close" .. base .. "ResourceOutput"),
        close_region = resource.config.close_region or ("close_" .. pascal_to_snake(base) .. "_resource"),
    }
end

local function finalize_world(decl, body)
    local children = collect_children(body, "world")
    local world = setmetatable({
        kind = "world",
        name = decl.name,
        children = children,
        scopes = {},
        order = {},
    }, World)

    for _, child in ipairs(children) do
        if child.kind ~= "scope" then fail("world children must be scopes, got " .. child.kind, 3) end
        local scope = child:finalize(world)
        if world.scopes[scope.name] then fail("duplicate scope `" .. scope.name .. "`", 3) end
        world.scopes[scope.name] = scope
        world.order[#world.order + 1] = scope
    end

    return world
end

local function finalize_scope(decl, world, body)
    local children = collect_children(body or decl.body, "scope")
    local scope = setmetatable({
        kind = "scope",
        name = decl.name,
        world = world,
        children = children,
        entries = {},
        order = {},
        rules = {},
    }, Scope)

    for _, child in ipairs(children) do
        local entry = child:finalize(world, scope)
        if entry.kind == "rule" then
            scope.rules[#scope.rules + 1] = entry.name
        else
            if scope.entries[entry.name] then fail("duplicate entry `" .. entry.name .. "` in scope `" .. scope.name .. "`", 3) end
            scope.entries[entry.name] = entry
            scope.order[#scope.order + 1] = entry
        end
    end

    return scope
end

local function finalize_store(decl, world, scope, body)
    local cfg = collect_config(body or decl.body or {}, "store")
    return setmetatable({ kind = "store", name = decl.name, world = world, scope = scope, config = cfg }, Store)
end

local function finalize_arena(decl, world, scope, body)
    local cfg = collect_config(body or decl.body or {}, "arena")
    return setmetatable({ kind = "arena", name = decl.name, world = world, scope = scope, config = cfg }, Arena)
end

local function finalize_resource_table(decl, world, scope, body)
    local cfg = collect_config(body or decl.body or {}, "resource_table")
    return setmetatable({ kind = "resource_table", name = decl.name, world = world, scope = scope, config = cfg }, ResourceTable)
end

function Decl:finalize(world, scope)
    if self.kind == "world" then return finalize_world(self, self.body) end
    if self.kind == "scope" then return finalize_scope(self, world, self.body) end
    if self.kind == "store" then return finalize_store(self, world, scope, self.body) end
    if self.kind == "arena" then return finalize_arena(self, world, scope, self.body) end
    if self.kind == "resource_table" then return finalize_resource_table(self, world, scope, self.body) end
    if self.kind == "rule" then return { kind = "rule", name = self.name, world = world, scope = scope } end
    fail("unknown declaration kind `" .. tostring(self.kind) .. "`", 2)
end

function Decl:__call(body)
    if self.kind == "rule" then
        if body ~= nil then fail("rule does not take a body", 2) end
        return self
    end
    check_body_table(body, self.kind)
    self.body = body
    if self.kind == "world" then return self:finalize(nil, nil) end
    return self
end

local function word(kind)
    return function(name)
        return make_decl(kind, name)
    end
end

function M.words()
    return {
        world = word("world"),
        scope = word("scope"),
        store = word("store"),
        arena = word("arena"),
        resource_table = word("resource_table"),
        rule = word("rule"),
    }
end

local function store_decl_record(store)
    local n = store_names(store)
    return {
        kind = "store",
        scope = store.scope and store.scope.name or nil,
        name = store.name,
        names = n,
        config = shallow_copy(store.config),
    }
end

local function arena_decl_record(arena)
    local n = arena_names(arena)
    return {
        kind = "arena",
        scope = arena.scope and arena.scope.name or nil,
        name = arena.name,
        names = n,
        config = shallow_copy(arena.config),
    }
end

local function resource_decl_record(resource)
    local n = resource_names(resource)
    return {
        kind = "resource_table",
        scope = resource.scope and resource.scope.name or nil,
        name = resource.name,
        names = n,
        config = shallow_copy(resource.config),
    }
end

function World:declarations()
    local out = {}
    for _, scope in ipairs(self.order) do
        out[#out + 1] = { kind = "scope", name = scope.name, rules = shallow_copy(scope.rules) }
        for _, entry in ipairs(scope.order) do
            if entry.kind == "store" then out[#out + 1] = store_decl_record(entry)
            elseif entry.kind == "arena" then out[#out + 1] = arena_decl_record(entry)
            elseif entry.kind == "resource_table" then out[#out + 1] = resource_decl_record(entry)
            end
        end
    end
    return out
end

function World:summary()
    local out = { world = self.name, scopes = {} }
    for _, scope in ipairs(self.order) do
        local s = { name = scope.name, rules = shallow_copy(scope.rules), entries = {} }
        for _, entry in ipairs(scope.order) do
            s.entries[#s.entries + 1] = { kind = entry.kind, name = entry.name }
        end
        out.scopes[#out.scopes + 1] = s
    end
    return out
end

local function emit_store(out, store)
    local n = store_names(store)
    append(out, "struct " .. n.handle)
    append(out, "    index: u32")
    if store.config.generation ~= false then append(out, "    generation: u32") end
    append(out, "end")
    append(out)

    append(out, "struct " .. n.owner)
    append(out, "    records: ptr(" .. n.record .. ")")
    append(out, "    capacity: index")
    if store.config.generation ~= false then append(out, "    generation: u64") end
    append(out, "end")
    append(out)

    append(out, "struct " .. n.input)
    append(out, "    owner: ptr(" .. n.owner .. ")")
    append(out, "    handle: " .. n.handle)
    append(out, "end")
    append(out)

    append(out, "union " .. n.output)
    append(out, "    borrowed(value: " .. n.borrowed .. ")")
    if store.config.generation ~= false then append(out, "  | stale(handle: " .. n.handle .. ")") end
    append(out, "  | missing(handle: " .. n.handle .. ")")
    append(out, "end")
    append(out)

    append(out, "region " .. n.region .. "(input: " .. n.input .. "; output: " .. n.output .. ")")
    append(out)
end

local function emit_arena(out, arena)
    local n = arena_names(arena)
    append(out, "struct " .. n.owner)
    append(out, "    data: ptr(u8)")
    append(out, "    capacity: index")
    append(out, "    offset: index")
    append(out, "    generation: u64")
    append(out, "end")
    append(out)

    append(out, "struct " .. n.reserve_input)
    append(out, "    owner: ptr(" .. n.owner .. ")")
    append(out, "    bytes: index")
    append(out, "    align: index")
    append(out, "end")
    append(out)

    append(out, "union " .. n.reserve_output)
    append(out, "    reserved(memory: BorrowedBytes)")
    append(out, "  | full(requested: index, available: index)")
    append(out, "  | invalid_alignment(align: index)")
    append(out, "  | closed")
    append(out, "end")
    append(out)

    append(out, "region " .. n.reserve_region .. "(input: " .. n.reserve_input .. "; output: " .. n.reserve_output .. ")")
    append(out)

    append(out, "struct " .. n.reset_input)
    append(out, "    owner: ptr(" .. n.owner .. ")")
    append(out, "end")
    append(out)

    append(out, "union " .. n.reset_output)
    append(out, "    reset")
    append(out, "  | closed")
    append(out, "end")
    append(out)

    append(out, "region " .. n.reset_region .. "(input: " .. n.reset_input .. "; output: " .. n.reset_output .. ")")
    append(out)
end

local function emit_resource_table(out, resource)
    local n = resource_names(resource)
    append(out, "struct " .. n.handle)
    append(out, "    index: u32")
    append(out, "    generation: u32")
    append(out, "end")
    append(out)

    append(out, "struct " .. n.owner)
    append(out, "    capacity: index")
    append(out, "    generation: u64")
    append(out, "end")
    append(out)

    append(out, "struct " .. n.close_input)
    append(out, "    owner: ptr(" .. n.owner .. ")")
    append(out, "    handle: " .. n.handle)
    append(out, "end")
    append(out)

    append(out, "union " .. n.close_output)
    append(out, "    closed")
    append(out, "  | stale(handle: " .. n.handle .. ")")
    append(out, "  | missing(handle: " .. n.handle .. ")")
    append(out, "  | already_closed(handle: " .. n.handle .. ")")
    append(out, "end")
    append(out)

    append(out, "region " .. n.close_region .. "(input: " .. n.close_input .. "; output: " .. n.close_output .. ")")
    append(out)
end

function World:moonlift_declarations()
    local out = {}
    append(out, "-- generated memory declarations for " .. self.name)
    append(out)
    for _, scope in ipairs(self.order) do
        append(out, "-- scope " .. scope.name)
        for _, rule in ipairs(scope.rules) do append(out, "-- rule " .. rule) end
        for _, entry in ipairs(scope.order) do
            if entry.kind == "store" then emit_store(out, entry)
            elseif entry.kind == "arena" then emit_arena(out, entry)
            elseif entry.kind == "resource_table" then emit_resource_table(out, entry)
            end
        end
    end
    return table.concat(out, "\n")
end

World.moonlift = World.moonlift_declarations
World.emit_moonlift = World.moonlift_declarations

function Store:moonlift_names()
    return store_names(self)
end

function Arena:moonlift_names()
    return arena_names(self)
end

function ResourceTable:moonlift_names()
    return resource_names(self)
end

local function operation_record(owner, verb, request, handlers)
    return setmetatable({
        kind = "operation",
        owner = owner,
        verb = verb,
        request = request or {},
        handlers = handlers,
    }, Operation)
end

function Operation:__call(handlers)
    if type(handlers) ~= "table" then fail("operation handlers must be a table", 2) end
    self.handlers = handlers

    local runtime = self.owner.runtime
    local driver = runtime and runtime[self.verb]
    if driver ~= nil then
        local outcome, payload = driver(self.owner, self.request)
        local handler = handlers[outcome]
        if type(handler) ~= "function" then fail("missing handler for outcome `" .. tostring(outcome) .. "`", 2) end
        return handler(payload)
    end

    return self
end

function Operation:lowered_names()
    if self.owner.kind == "store" and self.verb == "borrow" then return store_names(self.owner) end
    if self.owner.kind == "arena" and self.verb == "reserve" then return arena_names(self.owner) end
    if self.owner.kind == "resource_table" and self.verb == "close" then return resource_names(self.owner) end
    return {}
end

function Store:bind_runtime(runtime)
    self.runtime = runtime
    return self
end

function Store:borrow(request)
    if type(request) ~= "table" then fail("borrow request must be a table", 2) end
    return operation_record(self, "borrow", request)
end

function Arena:bind_runtime(runtime)
    self.runtime = runtime
    return self
end

function Arena:reserve(request)
    if type(request) ~= "table" then fail("reserve request must be a table", 2) end
    return operation_record(self, "reserve", request)
end

function Arena:mark(body)
    if type(body) ~= "table" then fail("mark body must be a table", 2) end
    local fn = body[1]
    if type(fn) ~= "function" then fail("mark body must contain a function as slot 1", 2) end
    return fn(self)
end

function ResourceTable:bind_runtime(runtime)
    self.runtime = runtime
    return self
end

function ResourceTable:close(request)
    if type(request) ~= "table" then fail("close request must be a table", 2) end
    return operation_record(self, "close", request)
end

function M.borrowed(payload, opts)
    opts = opts or {}
    if type(payload) ~= "table" then fail("borrowed payload must be a table", 2) end
    return setmetatable({ kind = "borrowed", payload = payload, name = opts.name, active = true }, Borrowed)
end

function Borrowed:__call(body)
    if not self.active then fail("borrowed value used outside its dynamic extent", 2) end
    if type(body) ~= "table" then fail("borrowed call body must be a table", 2) end
    local fn = body[1]
    if type(fn) ~= "function" then fail("borrowed call body must contain a function as slot 1", 2) end

    local ok, a, b, c, d, e, f = pcall(fn, self.payload)
    self.active = false
    if not ok then error(a, 0) end
    return a, b, c, d, e, f
end

function Borrowed:peek()
    if not self.active then fail("borrowed value used outside its dynamic extent", 2) end
    return self.payload
end

function M.describe(world)
    if type(world) ~= "table" or getmetatable(world) ~= World then fail("describe expects a mem world", 2) end
    return world:summary()
end

return M
