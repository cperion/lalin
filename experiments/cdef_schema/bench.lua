package.path = "./lua/?.lua;./lua/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local jit = require("jit")
local schema = require("cdefschema")

local S = schema.context {
    name = "cdef-schema-bench",
    version = 2,
    prefix = "CdefSchemaBench",
}
S:cdef [[
typedef struct { int64_t value; } CdefSchemaBenchDefault;
typedef struct { int64_t value; } CdefSchemaBenchOverride;
 ]]

local Counter = S:sum("Counter")
local Default = Counter:leaf("CdefSchemaBenchDefault")
local Override = Counter:leaf("CdefSchemaBenchOverride")

function Counter:step()
    self.value = self.value + 1
end

function Override:step()
    self.value = self.value + 2
end

S:seal()

local ITERATIONS = tonumber(arg[1]) or 20000000
local SAMPLES = tonumber(arg[2]) or 7

local function median(values)
    table.sort(values)
    return values[math.floor((#values + 1) / 2)]
end

local function measure(name, operation)
    jit.flush()
    for _ = 1, 3 do operation(10000) end
    local values = {}
    local result
    for sample = 1, SAMPLES do
        local t0 = os.clock()
        result = operation(ITERATIONS)
        values[sample] = os.clock() - t0
    end
    local seconds = median(values)
    print(string.format("%-24s %8.3f ms %8.3f ns/iteration result=%s",
        name, seconds * 1e3, seconds * 1e9 / ITERATIONS, tostring(result)))
end

measure("direct cdata field", function(iterations)
    local value = Default { value = 0 }
    for _ = 1, iterations do value.value = value.value + 1 end
    return value.value
end)

measure("inherited default", function(iterations)
    local value = Default { value = 0 }
    for _ = 1, iterations do value:step() end
    return value.value
end)

measure("leaf override", function(iterations)
    local value = Override { value = 0 }
    for _ = 1, iterations do value:step() end
    return value.value
end)

