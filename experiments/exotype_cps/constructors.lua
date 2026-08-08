local Exotype = require("experiments.exotype_cps.exotype")

local Constructors = {}
local unpack = unpack or table.unpack

local function compile_source(source, environment)
    local chunk, message = loadstring("return " .. source)
    assert(chunk, message)
    if environment ~= nil then setfenv(chunk, environment) end
    return chunk()
end

local function method_property(expression, statements, compile)
    return { expression = expression, statements = statements, compile = compile }
end

local function record_key(fields)
    local parts = {}
    for index = 1, #fields do
        parts[index] = fields[index].name .. ":" .. fields[index].ctype
    end
    return table.concat(parts, ",")
end

Constructors.Record = Exotype.memoize(record_key, function(fields)
    local copied, stats = {}, { entries = 0, methods = {} }
    for index = 1, #fields do
        local field = fields[index]
        Exotype.identifier(field.name, "record field")
        assert(field.ctype == "int64_t", "the experiment record supports exact int64_t fields")
        copied[index] = { name = field.name, ctype = field.ctype }
    end

    local owner
    owner = Exotype.new {
        name = "Record" .. tostring(#fields),
        constructor = "Record",
        parameters = copied,
        stats = stats,
        properties = {
            __getentries = function(_compiler, _self)
                stats.entries = stats.entries + 1
                return copied
            end,
            __getmethod = function(_compiler, _self, name)
                stats.methods[name] = (stats.methods[name] or 0) + 1
                if name == "sum" then
                    local function expression(_cc, object)
                        local terms = {}
                        for index = 1, #copied do
                            terms[index] = ("%s.%s"):format(object, copied[index].name)
                        end
                        return "(" .. table.concat(terms, " + ") .. ")"
                    end
                    return method_property(expression, nil, function(compiler)
                        local body = expression(compiler, "self")
                        local source = "function(self) return " .. body .. " end"
                        return compile_source(source), source
                    end)
                elseif name == "scale" then
                    local function statements(_cc, object, factor)
                        local lines = {}
                        for index = 1, #copied do
                            local access = ("%s.%s"):format(object, copied[index].name)
                            lines[index] = ("%s = %s * %s"):format(access, access, factor)
                        end
                        return lines
                    end
                    return method_property(nil, statements, function(compiler)
                        local lines = statements(compiler, "self", "factor")
                        lines[#lines + 1] = "return completed(self)"
                        local source = "function(self, factor, completed) "
                            .. table.concat(lines, "; ") .. " end"
                        return compile_source(source), source
                    end)
                end
            end,
        },
    }
    return owner
end)

local array_cache = {}
function Constructors.Array(element, count)
    assert(Exotype.is(element), "Array element must be an exotype")
    assert(type(count) == "number" and count >= 1 and count == math.floor(count),
        "Array count must be a positive integer")
    local key = element.id .. ":" .. count
    if array_cache[key] ~= nil then return array_cache[key] end

    local stats = { entries = 0, methods = {} }
    local owner
    owner = Exotype.new {
        name = "Array" .. count .. "Of" .. element.name,
        constructor = "Array",
        parameters = { element = element, count = count },
        stats = stats,
        properties = {
            __getentries = function(_compiler, _self)
                stats.entries = stats.entries + 1
                return {
                    { name = "items", exotype = element, count = count },
                    { name = "transitions", ctype = "uint64_t" },
                }
            end,
            __getmethod = function(compiler, _self, name)
                stats.methods[name] = (stats.methods[name] or 0) + 1
                if name == "sum" then
                    local element_sum = assert(compiler:query(element, "__getmethod", "sum"))
                    local function expression(cc, object)
                        local terms = {}
                        for index = 0, count - 1 do
                            terms[#terms + 1] = element_sum.expression(
                                cc, ("%s.items[%d]"):format(object, index))
                        end
                        return "(" .. table.concat(terms, " + ") .. ")"
                    end
                    return method_property(expression, nil, function(cc)
                        local source = "function(self) return " .. expression(cc, "self") .. " end"
                        return compile_source(source), source
                    end)
                elseif name == "scale" then
                    local element_scale = assert(compiler:query(element, "__getmethod", "scale"))
                    local function statements(cc, object, factor)
                        local lines = {}
                        for index = 0, count - 1 do
                            local nested = element_scale.statements(
                                cc, ("%s.items[%d]"):format(object, index), factor)
                            for nested_index = 1, #nested do lines[#lines + 1] = nested[nested_index] end
                        end
                        return lines
                    end
                    return method_property(nil, statements, function(cc)
                        local lines = statements(cc, "self", "factor")
                        lines[#lines + 1] = "return completed(self)"
                        local source = "function(self, factor, completed) "
                            .. table.concat(lines, "; ") .. " end"
                        return compile_source(source), source
                    end)
                elseif name == "scaled" then
                    return method_property(nil, nil, function()
                        local source = "function(self) self.transitions = self.transitions + 1; return self end"
                        return compile_source(source), source
                    end)
                elseif name == "run" then
                    compiler:query(owner, "__getmethod", "scale")
                    compiler:query(owner, "__getmethod", "scaled")
                    return method_property(nil, nil, function(_cc, _owner, _descriptor, installed)
                        local scale, scaled = assert(installed.scale), assert(installed.scaled)
                        return function(self, factor) return scale(self, factor, scaled) end,
                            "function(self, factor) return scale(self, factor, scaled) end"
                    end)
                end
            end,
        },
    }
    array_cache[key] = owner
    return owner
end

return Constructors
