local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_kernel_plan_rules ~= nil then return T._lalin_api_cache.code_kernel_plan_rules end

    local api = {}

    local function select_loop_kernel_plan(loop)
        if not loop.counted then
            return { kind = "no_plan", rejects = loop.not_counted_rejects }
        end
        if not loop.has_func_id then
            return { kind = "no_plan", rejects = loop.no_owner_rejects }
        end
        if loop.has_rejects then
            return { kind = "no_plan", rejects = loop.rejects }
        end
        if loop.has_func and loop.has_closed_form then
            return {
                kind = "planned",
                result_kind = "closed_form",
                closed_form = loop.closed_form,
                add_trip_unknown_proof = loop.closed_form_trip_unknown,
            }
        end
        if loop.has_func and loop.has_reduction then
            return {
                kind = "planned",
                result_kind = "reduction",
                reduction = loop.reduction,
                add_trip_unknown_proof = false,
            }
        end
        if loop.has_func and loop.has_skeleton_result then
            return {
                kind = "planned",
                result_kind = "skeleton",
                skeleton_result = loop.skeleton_result,
                add_trip_unknown_proof = false,
            }
        end
        return {
            kind = "planned",
            result_kind = "original_control",
            add_trip_unknown_proof = false,
        }
    end

    function api:run(relation, input, _output_key, missing)
        if relation ~= "select_loop_kernel_plan" then return nil, missing or ("unknown kernel-plan relation " .. tostring(relation)) end
        local loop = input and input.loop
        if loop == nil then return nil, missing or "missing kernel-plan loop input" end
        return select_loop_kernel_plan(loop)
    end

    T._lalin_api_cache.code_kernel_plan_rules = api
    return api
end

return bind_context
