local pvm = require("moonlift.pvm")

local M = {}

function M.Define(T)
    T._moonlift_api_cache = T._moonlift_api_cache or {}
    if T._moonlift_api_cache.code_lower_plan ~= nil then return T._moonlift_api_cache.code_lower_plan end

    local Kernel = T.MoonKernel
    local Lower = T.MoonLower

    local api = {}

    local function kernel_plan_by_func(kernel_module)
        local out = {}
        for _, func_plan in ipairs(kernel_module and kernel_module.funcs or {}) do
            out[func_plan.func.text] = func_plan.plan
        end
        return out
    end

    local function choose_func_lower(func, plan)
        if plan ~= nil and pvm.classof(plan) == Kernel.KernelPlanned
            and pvm.classof(plan.subject) == Kernel.KernelSubjectFunc
            and plan.subject.func == func.id then
            return Lower.LowerFuncKernel(plan)
        end
        return Lower.LowerFuncCode(func.id)
    end

    local function module(code_module, kernel_module, opts)
        opts = opts or {}
        local target = opts.target or Lower.LowerTargetCode
        local by_func = kernel_plan_by_func(kernel_module)
        local funcs = {}
        for i = 1, #(code_module.funcs or {}) do
            local func = code_module.funcs[i]
            funcs[#funcs + 1] = choose_func_lower(func, by_func[func.id.text])
        end
        return Lower.LowerModule(code_module.id, target, kernel_module, funcs)
    end

    api.module = module
    api.plan = module

    T._moonlift_api_cache.code_lower_plan = api
    return api
end

return M
