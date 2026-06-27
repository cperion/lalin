local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.exec_plan_rules ~= nil then return T._lalin_api_cache.exec_plan_rules end

    local api = {
        kind = {
            stencil = "stencil",
            skip = "skip",
        },
    }

    local function select_exec_fragment(fragment)
        if not fragment.stencil_selected then
            return { kind = api.kind.skip, reason = fragment.unselected_reason }
        end
        if not fragment.has_artifact then
            return { kind = api.kind.skip, reason = fragment.missing_artifact_reason }
        end
        if not fragment.has_func then
            return { kind = api.kind.skip, reason = fragment.missing_func_reason }
        end
        return { kind = api.kind.stencil, reason = fragment.selected_reason }
    end

    function api:run(relation, input, _output_key, missing)
        if relation ~= "select_exec_fragment" then return nil, missing or ("unknown exec-plan relation " .. tostring(relation)) end
        local fragment = input and input.fragment
        if fragment == nil then return nil, missing or "missing exec-plan fragment input" end
        return select_exec_fragment(fragment)
    end

    T._lalin_api_cache.exec_plan_rules = api
    return api
end

return bind_context
