local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_lower_plan_rules ~= nil then return T._lalin_api_cache.code_lower_plan_rules end

    local api = {
        kind = {
            closed_form = "closed_form",
            kernel = "kernel",
            fallback = "fallback",
            none = "none",
        },
    }

    local function select_lower_fragment(fragment)
        if fragment.has_kernel then
            if fragment.schedule_planned then
                if fragment.schedule_closed_form then
                    if fragment.has_closed_form then
                        return { kind = api.kind.closed_form, closed_form = fragment.closed_form }
                    end
                    return { kind = api.kind.fallback, reason = fragment.closed_form_missing_reason }
                end
                return { kind = api.kind.kernel }
            end
            return { kind = api.kind.fallback, reason = fragment.no_schedule_reason }
        end
        if fragment.has_kernel_no_plan then
            return { kind = api.kind.fallback, reason = fragment.kernel_no_plan_reason }
        end
        return { kind = api.kind.none }
    end

    function api:run(relation, input, _output_key, missing)
        if relation ~= "select_lower_fragment" then return nil, missing or ("unknown lower-plan relation " .. tostring(relation)) end
        local fragment = input and input.fragment
        if fragment == nil then return nil, missing or "missing lower-plan fragment input" end
        return select_lower_fragment(fragment)
    end

    T._lalin_api_cache.code_lower_plan_rules = api
    return api
end

return bind_context
