local Exotype = {}

local next_id = 0
local Owner = {}
Owner.__index = Owner

local function identifier(value, what)
    assert(type(value) == "string" and value:match("^[_%a][_%w]*$"),
        what .. " must be a C identifier")
    return value
end

function Exotype.new(spec)
    assert(type(spec) == "table", "exotype specification must be a table")
    next_id = next_id + 1
    local owner = setmetatable({
        id = next_id,
        name = identifier(assert(spec.name, "exotype name is required"), "exotype name"),
        properties = assert(spec.properties, "exotype properties are required"),
        constructor = spec.constructor,
        parameters = spec.parameters,
        stats = spec.stats or {},
        ctype_prefix = ("ExotypeCpsV1_T%d_"):format(next_id),
    }, Owner)
    owner.ctype_name = owner.ctype_prefix .. owner.name
    return owner
end

function Exotype.is(value) return getmetatable(value) == Owner end

function Owner:property(name) return rawget(self.properties, name) end
function Owner:typename() return self.name end
function Owner:__tostring() return ("<exotype %s#%d>"):format(self.name, self.id) end

function Exotype.memoize(key_of, construct)
    local cache = {}
    return function(...)
        local key = key_of(...)
        local value = cache[key]
        if value == nil then
            value = construct(...)
            cache[key] = value
        end
        return value
    end
end

Exotype.identifier = identifier
return Exotype
