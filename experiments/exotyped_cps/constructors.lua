local K = require("experiments.exotyped_cps.kernel")

local C = {}

C.Sum = K.operation("Sum", "expression")
C.ScaleEffect = K.operation("ScaleEffect", "effect")
C.RunScale = K.operation("RunScale", "cps")
C.Scaled = K.operation("Scaled", "cps")

local record_cache = {}
function C.Record(fields)
    local key_parts = {}
    for index = 1, #fields do
        key_parts[index] = fields[index].name .. ":" .. fields[index].ctype
    end
    local key = table.concat(key_parts, ",")
    if record_cache[key] ~= nil then return record_cache[key] end

    local copied, stats = {}, { layout = 0, operations = {} }
    for index = 1, #fields do
        assert(fields[index].ctype == "int64_t", "Record fields must be exact int64_t values")
        copied[index] = { name = fields[index].name, ctype = fields[index].ctype }
    end
    local operations = {}
    operations[C.Sum] = function(_compiler, owner)
        stats.operations.Sum = (stats.operations.Sum or 0) + 1
        return K.expression({}, function(object)
            local terms = {}
            for index = 1, #copied do
                terms[index] = ("%s.%s"):format(object, copied[index].name)
            end
            return "(" .. table.concat(terms, " + ") .. ")"
        end)
    end
    operations[C.ScaleEffect] = function(_compiler, owner)
        stats.operations.ScaleEffect = (stats.operations.ScaleEffect or 0) + 1
        return K.effect({ "factor" }, function(object)
            local statements = {}
            for index = 1, #copied do
                local access = ("%s.%s"):format(object, copied[index].name)
                statements[index] = ("%s = %s * factor"):format(access, access)
            end
            return statements
        end)
    end

    local owner = K.owner {
        name = "Record" .. #copied, parameters = copied, operations = operations, stats = stats,
        layout = function()
            stats.layout = stats.layout + 1
            return copied
        end,
    }
    record_cache[key] = owner
    return owner
end

local array_cache = {}
function C.Array(element, count)
    assert(K.is_owner(element), "Array element must be an exotype")
    assert(count >= 1 and count == math.floor(count), "Array count must be positive")
    local key = element.id .. ":" .. count
    if array_cache[key] ~= nil then return array_cache[key] end

    local operations = {}
    operations[C.Sum] = function(compiler)
        local element_sum = compiler:operation(element, C.Sum)
        return K.expression({}, function(object)
            local terms = {}
            for index = 0, count - 1 do
                terms[#terms + 1] = element_sum.emit_expression(
                    ("%s.items[%d]"):format(object, index), {})
            end
            return "(" .. table.concat(terms, " + ") .. ")"
        end)
    end
    operations[C.ScaleEffect] = function(compiler)
        local element_scale = compiler:operation(element, C.ScaleEffect)
        return K.effect({ "factor" }, function(object)
            local statements = {}
            for index = 0, count - 1 do
                local nested = element_scale.emit_statements(
                    ("%s.items[%d]"):format(object, index), { "factor" })
                for item = 1, #nested do statements[#statements + 1] = nested[item] end
            end
            return statements
        end)
    end
    local owner
    operations[C.Scaled] = function()
        return K.cps({}, {}, function(_resolve, object)
            return { object .. ".transitions = " .. object .. ".transitions + 1", "return " .. object }
        end)
    end
    operations[C.RunScale] = function(compiler)
        local scale = compiler:operation(owner, C.ScaleEffect)
        local scaled = K.dependency(owner, C.Scaled)
        return K.cps({ "factor" }, { scaled }, function(resolve, object)
            local statements = scale.emit_statements(object, { "factor" })
            statements[#statements + 1] = "return " .. resolve(scaled) .. "(" .. object .. ")"
            return statements
        end)
    end
    owner = K.owner {
        name = "Array" .. count .. "Of" .. element.name,
        parameters = { element = element, count = count }, operations = operations,
        layout = function()
            return {
                { name = "items", owner = element, count = count },
                { name = "transitions", ctype = "uint64_t" },
            }
        end,
    }
    array_cache[key] = owner
    return owner
end

local pipeline_id = 0
local pipeline_cache = {}
function C.Pipeline(stage_specs)
    assert(type(stage_specs) == "table" and #stage_specs > 0,
        "Pipeline requires at least one stage")
    local stages, key_parts = {}, {}
    for index = 1, #stage_specs do
        local stage = stage_specs[index]
        assert(stage.kind == "add" or stage.kind == "multiply" or stage.kind == "reject_above",
            "unsupported pipeline stage " .. tostring(stage.kind))
        assert(type(stage.value) == "number" and stage.value == math.floor(stage.value),
            "pipeline stage value must be an integer")
        stages[index] = { kind = stage.kind, value = stage.value }
        key_parts[index] = stage.kind .. ":" .. stage.value
    end
    local cache_key = table.concat(key_parts, ",")
    if pipeline_cache[cache_key] ~= nil then return pipeline_cache[cache_key] end
    pipeline_id = pipeline_id + 1
    local operations, stage_operations = {}, {}
    local owner
    local Run = K.operation("Run", "cps")
    local Loop = K.operation("Loop", "cps")
    local Completed = K.operation("Completed", "cps")
    local Rejected = K.operation("Rejected", "cps")
    for index = 1, #stages do stage_operations[index] = K.operation("Stage" .. index, "cps") end

    operations[Run] = function()
        local first = K.dependency(owner, stage_operations[1])
        local completed = K.dependency(owner, Completed)
        return K.cps({ "input", "rounds" }, { first, completed }, function(resolve, object)
            return {
                object .. ".value = input",
                object .. ".remaining = rounds",
                "if rounds == 0 then return " .. resolve(completed) .. "(" .. object .. ") end",
                "return " .. resolve(first) .. "(" .. object .. ")",
            }
        end)
    end

    for index = 1, #stages do
        local stage_index = index
        local stage, operation = stages[stage_index], stage_operations[stage_index]
        operations[operation] = function()
            local next_operation = stage_index == #stages and Loop or stage_operations[stage_index + 1]
            local next_dependency = K.dependency(owner, next_operation)
            local rejected = K.dependency(owner, Rejected)
            local dependencies = { next_dependency }
            if stage.kind == "reject_above" then dependencies[#dependencies + 1] = rejected end
            return K.cps({}, dependencies, function(resolve, object)
                local body = { object .. ".transitions = " .. object .. ".transitions + 1" }
                if stage.kind == "add" then
                    body[#body + 1] = object .. ".value = " .. object .. ".value + " .. stage.value
                elseif stage.kind == "multiply" then
                    body[#body + 1] = object .. ".value = " .. object .. ".value * " .. stage.value
                elseif stage.kind == "reject_above" then
                    body[#body + 1] = "if " .. object .. ".value > " .. stage.value
                        .. " then return " .. resolve(rejected) .. "(" .. object .. ") end"
                else
                    error("unsupported pipeline stage " .. tostring(stage.kind))
                end
                body[#body + 1] = "return " .. resolve(next_dependency) .. "(" .. object .. ")"
                return body
            end)
        end
    end

    operations[Loop] = function()
        local first = K.dependency(owner, stage_operations[1])
        local completed = K.dependency(owner, Completed)
        return K.cps({}, { first, completed }, function(resolve, object)
            return {
                object .. ".remaining = " .. object .. ".remaining - 1",
                "if " .. object .. ".remaining > 0 then return "
                    .. resolve(first) .. "(" .. object .. ") end",
                "return " .. resolve(completed) .. "(" .. object .. ")",
            }
        end)
    end
    operations[Completed] = function()
        return K.cps({}, {}, function(_resolve, object)
            return { object .. ".completed = " .. object .. ".completed + 1", "return " .. object }
        end)
    end
    operations[Rejected] = function()
        return K.cps({}, {}, function(_resolve, object)
            return { object .. ".rejected = " .. object .. ".rejected + 1", "return " .. object }
        end)
    end

    owner = K.owner {
        name = "Pipeline" .. pipeline_id, parameters = stages, operations = operations,
        layout = function()
            return {
                { name = "value", ctype = "int32_t" },
                { name = "transitions", ctype = "uint32_t" },
                { name = "completed", ctype = "uint32_t" },
                { name = "rejected", ctype = "uint32_t" },
                { name = "remaining", ctype = "uint32_t" },
            }
        end,
    }
    owner.Run, owner.Loop = Run, Loop
    owner.Completed, owner.Rejected = Completed, Rejected
    owner.stage_operations = stage_operations
    pipeline_cache[cache_key] = owner
    return owner
end

return C
