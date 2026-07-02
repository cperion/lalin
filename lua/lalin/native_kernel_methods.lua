local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_kernel_methods ~= nil then return T._lalin_api_cache.native_kernel_methods end

    local api = {}

    T._lalin_api_cache.native_kernel_methods = api
    return api
end

return bind_context
