local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.lower_to_c ~= nil then return T._moonlift_api_cache.lower_to_c end

    local CodeToC = require("moonlift.code_to_c").Define(T)

    local api = {}

    local function module(code_module, lower_module, opts)
        -- C lowering is intentionally a pure CodeToC projection for now.
        -- MoonLower/MoonKernel are accepted so the frontend can use the same
        -- pipeline shape as Back, but this path must not install partial
        -- point optimizations.  When C kernel lowering exists, it should
        -- consume the generic KernelBody semantics rather than special-casing
        -- individual reductions or benchmark shapes.
        return CodeToC.module(code_module, opts)
    end

    api.module = module
    api.unit = module

    T._moonlift_api_cache.lower_to_c = api
    return api
end

return M
