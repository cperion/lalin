local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.lower_strategy_emit_rules ~= nil then return T._lalin_api_cache.lower_strategy_emit_rules end

    local api = {
        kind = {
            code = "code",
            closed_form = "closed_form",
            scalar_kernel = "scalar_kernel",
            vector_kernel = "vector_kernel",
            missing_schedule = "missing_schedule",
            unsupported = "unsupported",
        },
    }

    local function select_lower_emit(emit)
        if emit.strategy_code then return { kind = api.kind.code } end
        if emit.strategy_closed_form then return { kind = api.kind.closed_form } end
        if emit.strategy_kernel then
            if not emit.has_schedule then
                return { kind = api.kind.missing_schedule, reason = emit.missing_schedule_reason }
            end
            return { kind = emit.schedule_vector and api.kind.vector_kernel or api.kind.scalar_kernel }
        end
        return { kind = api.kind.unsupported, reason = emit.unsupported_reason }
    end

    function api:run(relation, input, _output_key, missing)
        if relation ~= "select_lower_emit" then return nil, missing or ("unknown lower-emit relation " .. tostring(relation)) end
        local emit = input and input.emit
        if emit == nil then return nil, missing or "missing lower-emit input" end
        return select_lower_emit(emit)
    end

    T._lalin_api_cache.lower_strategy_emit_rules = api
    return api
end

return bind_context
