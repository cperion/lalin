local ffi = require("ffi")

local M = {}
local ContextMethods = {}
local TypeMethods = {}

local function fail(level, message)
    error("cdefschema: " .. message, level + 1)
end

local function require_open(context, operation)
    if context._sealed then
        fail(3, operation .. " is not allowed after sealing context " .. context._name)
    end
end

local function require_kind(value, expected, operation)
    if value._kind ~= expected then
        fail(3, operation .. " requires a " .. expected .. ", got " .. value._kind)
    end
end

local function require_prefix(context, ctype_name)
    if ctype_name:sub(1, #context._prefix) ~= context._prefix then
        fail(3, "ctype " .. ctype_name .. " must use context prefix " .. context._prefix)
    end
end

local DescriptorMetatable = {
    __index = function(self, key)
        local api_method = TypeMethods[key]
        if api_method ~= nil then return api_method end
        local declared = rawget(self, "_declared_methods")[key]
        if declared ~= nil then return declared end
        local parent = rawget(self, "_parent")
        if parent ~= nil then return parent._declared_methods[key] end
    end,

    __newindex = function(self, key, value)
        require_open(self._context, "method declaration")
        if type(key) ~= "string" or type(value) ~= "function" then
            fail(2, "types accept only named method declarations")
        end
        if TypeMethods[key] ~= nil then
            fail(2, "method name is reserved by the schema API: " .. key)
        end
        self._declared_methods[key] = value
    end,

    __call = function(self, ...)
        if self._kind == "sum" then fail(2, "a sum is not constructible: " .. self._name) end
        if not self._context._sealed then
            fail(2, "construction requires sealed context " .. self._context._name)
        end
        return ffi.new(self._ctype, ...)
    end,
}

local function descriptor(context, kind, name, ctype, parent)
    return setmetatable({
        _context = context,
        _kind = kind,
        _name = name,
        _ctype = ctype,
        _parent = parent,
        _declared_methods = {},
        _leaves = kind == "sum" and {} or nil,
    }, DescriptorMetatable)
end

local function bind_ctype(context, kind, ctype_name, parent)
    require_open(context, kind .. " declaration")
    require_prefix(context, ctype_name)
    local ctype = ffi.typeof(ctype_name)
    local identity = tostring(ctype)
    if context._ctype_owners[identity] then
        fail(3, "ctype is already registered: " .. ctype_name)
    end
    local value = descriptor(context, kind, ctype_name, ctype, parent)
    context._ctype_owners[identity] = value
    context._concrete[#context._concrete + 1] = value
    return value
end

function M.context(options)
    assert(type(options) == "table", "context requires an options table")
    assert(type(options.name) == "string" and options.name ~= "", "context name is required")
    assert(type(options.version) == "number", "context version is required")
    assert(type(options.prefix) == "string" and options.prefix ~= "", "context prefix is required")
    return setmetatable({
        _name = options.name,
        _version = options.version,
        _prefix = options.prefix,
        _sealed = false,
        _concrete = {},
        _sum_names = {},
        _ctype_owners = {},
    }, { __index = ContextMethods })
end

function ContextMethods:cdef(source)
    require_open(self, "cdef declaration")
    ffi.cdef(source)
    return self
end

function ContextMethods:product(ctype_name)
    return bind_ctype(self, "product", ctype_name)
end

function ContextMethods:union(ctype_name)
    return bind_ctype(self, "union", ctype_name)
end

function ContextMethods:sum(name)
    require_open(self, "sum declaration")
    if self._sum_names[name] then fail(2, "sum is already declared: " .. name) end
    local value = descriptor(self, "sum", name)
    self._sum_names[name] = value
    return value
end

function ContextMethods:seal()
    require_open(self, "seal")
    for _, concrete in ipairs(self._concrete) do
        local methods = {}
        if concrete._parent then
            for name, implementation in pairs(concrete._parent._declared_methods) do
                methods[name] = implementation
            end
        end
        for name, implementation in pairs(concrete._declared_methods) do
            methods[name] = implementation
        end
        ffi.metatype(concrete._ctype, { __index = methods })
    end
    self._sealed = true
    return self
end

function TypeMethods:name() return self._name end

function TypeMethods:leaf(ctype_name)
    require_kind(self, "sum", "leaf declaration")
    local leaf = bind_ctype(self._context, "leaf", ctype_name, self)
    self._leaves[#self._leaves + 1] = leaf
    return leaf
end

function TypeMethods:is(value)
    if type(value) ~= "cdata" then return false end
    if self._kind == "sum" then
        for _, leaf in ipairs(self._leaves) do
            if ffi.istype(leaf._ctype, value) then return true end
        end
        return false
    end
    return ffi.istype(self._ctype, value)
end

return M

