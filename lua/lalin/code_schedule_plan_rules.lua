local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.code_schedule_plan_rules ~= nil then return T._lalin_api_cache.code_schedule_plan_rules end

    local api = {}

    local function select_kernel_schedule(schedule)
        if schedule.has_vector_schedule and schedule.vector_executable then
            return {
                kind = "planned",
                schedule_kind = schedule.vector_kind,
                capability = schedule.vector_capability,
                rejected_alternatives = {},
            }
        end
        if schedule.has_vector_schedule and not schedule.vector_executable and schedule.scalar_executable then
            return {
                kind = "planned",
                schedule_kind = schedule.scalar_kind,
                capability = schedule.scalar_capability,
                rejected_alternatives = schedule.vector_rejects,
            }
        end
        if not schedule.has_vector_schedule and schedule.scalar_executable then
            return {
                kind = "planned",
                schedule_kind = schedule.scalar_kind,
                capability = schedule.scalar_capability,
                rejected_alternatives = {},
            }
        end
        return {
            kind = "no_plan",
            rejects = schedule.scalar_rejects,
        }
    end

    function api:run(relation, input, _output_key, missing)
        if relation ~= "select_kernel_schedule" then return nil, missing or ("unknown schedule-plan relation " .. tostring(relation)) end
        local schedule = input and input.schedule
        if schedule == nil then return nil, missing or "missing schedule-plan input" end
        return select_kernel_schedule(schedule)
    end

    T._lalin_api_cache.code_schedule_plan_rules = api
    return api
end

return bind_context
