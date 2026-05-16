-- MOM Assembly infrastructure
-- Loads compiler source modules and assembles them into a unified Moonlift module object.

local Host = require("moonlift.mlua_run")
local Manifest = require("moonlift.mom.build.manifest")

local A = {}
local MomAssembly = {}
MomAssembly.__index = MomAssembly

local function is_type_value(v)
    return type(v) == "table" and (
        v.kind == "struct" or v.kind == "union" or v.kind == "struct_draft"
    )
end

-- Create a new assembly context
function A.new(opts)
    opts = opts or {}
    local carrier, rt = Host.loadfile(Manifest.compiler_sources[1])
    local api = rt.session:api()
    local module = api.module(opts.name or "mom")
    local self = setmetatable({
        rt = rt,
        api = api,
        module = module,
        names = {},
        types = {},
        funcs = {},
        exports = {},
        externs = {},
    }, MomAssembly)
    return self, carrier
end

function MomAssembly:reserve(name, kind)
    assert(type(name) == "string" and name ~= "", "MOM item needs a name")
    local prior = self.names[name]
    assert(prior == nil, "duplicate MOM item " .. name .. " as " .. kind .. ", previous " .. tostring(prior))
    self.names[name] = kind
end

function MomAssembly:type(name, value)
    self:reserve(name, "type")
    self.types[#self.types + 1] = value
    self.module:add_type(value)
    self[name] = value
    return value
end

function MomAssembly:local_func(name, value)
    self:reserve(name, "local_func")
    self.funcs[#self.funcs + 1] = value
    self.module:add_func(value)
    self[name] = value
    return value
end

function MomAssembly:export_func(name, value)
    self:reserve(name, "export_func")
    self.exports[name] = true
    self.funcs[#self.funcs + 1] = value
    self.module:add_func(value)
    self[name] = value
    return value
end

function MomAssembly:extern_func(name, value)
    self:reserve(name, "extern_func")
    self.externs[#self.externs + 1] = value
    self.module:add_func(value)
    self[name] = value
    return value
end

-- Load all compiler sources and install into assembly
function A.load(opts)
    opts = opts or {}
    local assembly, first_carrier = A.new(opts)

    for i, path in ipairs(Manifest.compiler_sources) do
        local carrier
        if i == 1 then
            carrier = first_carrier
        else
            carrier = assert(Host.loadfile(path, { runtime = assembly.rt }))
        end
        local installer = carrier()
        assert(type(installer) == "function", path .. " must return function(M) ... return M end")
        local returned = installer(assembly)
        assert(returned == assembly, path .. " did not return the assembly object")
    end

    return assembly
end

-- Emit precompiled object
function A.emit_object(opts)
    opts = opts or {}
    local assembly = A.load({ name = opts.name or "mom" })
    return assembly.module:emit_object({ module_name = opts.module_name or "libmom_precompiled" })
end

return A
