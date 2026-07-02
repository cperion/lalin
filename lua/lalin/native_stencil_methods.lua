local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_stencil_methods ~= nil then return T._lalin_api_cache.native_stencil_methods end

    local Stencil = T.LalinStencil
    local api = {}

    function Stencil.StencilInstance:plan_native_copy(input)
        return self.descriptor:select_native_template_graph(input)
    end

    T._lalin_api_cache.native_stencil_methods = api
    return api
end

return bind_context
