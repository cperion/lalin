local M = {}

local pvm = require("moonlift.pvm")

local Api = {}
Api.__index = Api

local function moon_tree_class_kind(node)
    local cls = pvm.classof(node)
    if cls and cls.kind then return cls.kind end
    local raw = tostring(cls)
    return raw:match("^Class%(MoonTree%.(.+)%)$") or raw
end

function Api:run(relation, input, output_name, missing)
    local result, err = self.engine:run(relation, input)
    if result == nil then return nil, err and err.message or missing or ("no Llisle result for " .. tostring(relation)) end
    if output_name == nil then return result.output, nil end
    return result.output[output_name], nil
end

function Api:run_candidate(relation, candidate, output_name, missing)
    return self:run(relation, { candidate = candidate }, output_name or "selection", missing)
end

function Api:run_tree_class(relation, node, output_name, missing)
    return self:run_candidate(relation, { kind = moon_tree_class_kind(node) }, output_name or "selection", missing)
end

function M.new(rules, engine, extra)
    local api = setmetatable({
        rules = rules,
        engine = engine,
    }, Api)
    if extra then
        for k, v in pairs(extra) do api[k] = v end
    end
    return api
end

return M
