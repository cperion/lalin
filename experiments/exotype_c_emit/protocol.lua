-- Minimal local exotype protocol for the emitted-C experiment.
--
-- This is intentionally not a general exotype library.  It contains only the
-- identity and property machinery shared by this one experiment.

local Protocol = {}

local next_property_id = 0
local next_owner_id = 0

function Protocol.property(name, result_class)
    next_property_id = next_property_id + 1
    return { id = next_property_id, name = name, result_class = result_class }
end

function Protocol.owner(name, properties, parameters)
    next_owner_id = next_owner_id + 1
    return {
        id = next_owner_id,
        name = name,
        properties = properties,
        parameters = parameters,
        values = {},
        stats = { queries = 0 },
    }
end

function Protocol.query(compiler, owner, property)
    local key = owner.id .. ":" .. property.id
    local value = owner.values[property]
    if value ~= nil then return value end

    if compiler.active[key] then
        local trace = {}
        for index = 1, #compiler.stack do trace[index] = compiler.stack[index] end
        trace[#trace + 1] = owner.name .. "." .. property.name
        error("cyclic exotype property query: " .. table.concat(trace, " -> "), 2)
    end

    local implementation = owner.properties[property]
    assert(implementation, owner.name .. " does not implement " .. property.name)
    compiler.active[key] = true
    compiler.stack[#compiler.stack + 1] = owner.name .. "." .. property.name
    local result = { pcall(implementation, compiler, owner) }
    compiler.stack[#compiler.stack] = nil
    compiler.active[key] = nil
    if not result[1] then error(result[2], 2) end

    value = result[2]
    assert(getmetatable(value) == property.result_class,
        owner.name .. "." .. property.name .. " returned the wrong property type")
    owner.values[property] = value
    owner.stats.queries = owner.stats.queries + 1
    return value
end

return Protocol
