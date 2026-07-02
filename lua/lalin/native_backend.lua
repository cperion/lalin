local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.native_backend ~= nil then return T._lalin_api_cache.native_backend end

    require("lalin.native")(T)
    require("lalin.native_mc")(T)
    require("lalin.native_code_methods")(T)
    require("lalin.native_kernel_methods")(T)
    require("lalin.native_stencil_methods")(T)

    local Native = T.LalinNative
    local Support = require("lalin.native_template_support")(T)
    local api = {}

    local function boundary_error(message)
        error("lalin.native_backend: " .. message, 3)
    end

    local function require_value(value, name)
        if value == nil then boundary_error("missing " .. name) end
        return value
    end

    local function reject_summary(rejects)
        local count = #(rejects or {})
        if count == 0 then return "no typed rejects supplied" end
        return tostring(count) .. " typed reject(s); first reject: " .. tostring(rejects[1])
    end

    function Native.NativeEmbeddedBankImported:required_native_bank()
        return self.bank
    end

    function Native.NativeEmbeddedBankRejected:required_native_bank()
        boundary_error("embedded native bank import rejected: " .. reject_summary(self.rejects))
    end

    function Native.NativeCompileResult:native_executable()
        return self.executable
    end

    local function native_request(subject, target, runtime, bank)
        return Native.NativeCompileRequest(
            require_value(subject, "NativeCompileSubject"),
            require_value(target, "NativeTarget"),
            require_value(runtime, "NativeRuntime"),
            require_value(bank, "NativeTemplateBank")
        )
    end

    local function compile_subject(subject, target, runtime, bank)
        return native_request(subject, target, runtime, bank):compile_native()
    end

    local function bank_from_embedded(embedded)
        return Native.NativeEmbeddedBankImportRequest(
            require_value(embedded, "NativeEmbeddedTemplateBank")
        ):import_native_bank():required_native_bank()
    end

    function api.import_embedded_bank(embedded)
        return Native.NativeEmbeddedBankImportRequest(
            require_value(embedded, "NativeEmbeddedTemplateBank")
        ):import_native_bank()
    end

    function api.require_imported_bank(embedded)
        return bank_from_embedded(embedded)
    end

    function api.compile_subject(subject, target, runtime, bank)
        return compile_subject(subject, target, runtime, bank)
    end

    function api.compile_subject_with_embedded_bank(subject, target, runtime, embedded)
        return compile_subject(subject, target, runtime, bank_from_embedded(embedded))
    end

    function api.compile_subject_executable(subject, target, runtime, bank)
        return compile_subject(subject, target, runtime, bank):native_executable()
    end

    function api.compile_subject_with_embedded_bank_executable(subject, target, runtime, embedded)
        return compile_subject(subject, target, runtime, bank_from_embedded(embedded)):native_executable()
    end

    function api.code_module_subject(module)
        return Native.NativeCompileCodeModule(require_value(module, "CodeModule"))
    end

    function api.code_func_subject(func)
        return Native.NativeCompileCodeFunc(require_value(func, "CodeFunc"))
    end

    function api.kernel_plan_subject(plan)
        return Native.NativeCompileKernelPlan(require_value(plan, "KernelPlan"))
    end

    function api.stencil_instance_subject(instance)
        return Native.NativeCompileStencilInstance(require_value(instance, "StencilInstance"))
    end

    function api.compile_code_module(module, target, runtime, bank)
        return compile_subject(api.code_module_subject(module), target, runtime, bank)
    end

    function api.compile_code_module_with_embedded_bank(module, target, runtime, embedded)
        return compile_subject(api.code_module_subject(module), target, runtime, bank_from_embedded(embedded))
    end

    function api.compile_code_func(func, target, runtime, bank)
        return compile_subject(api.code_func_subject(func), target, runtime, bank)
    end

    function api.compile_code_func_with_embedded_bank(func, target, runtime, embedded)
        return compile_subject(api.code_func_subject(func), target, runtime, bank_from_embedded(embedded))
    end

    function api.compile_kernel_plan(plan, target, runtime, bank)
        return compile_subject(api.kernel_plan_subject(plan), target, runtime, bank)
    end

    function api.compile_kernel_plan_with_embedded_bank(plan, target, runtime, embedded)
        return compile_subject(api.kernel_plan_subject(plan), target, runtime, bank_from_embedded(embedded))
    end

    function api.compile_stencil_instance(instance, target, runtime, bank)
        return compile_subject(api.stencil_instance_subject(instance), target, runtime, bank)
    end

    function api.compile_stencil_instance_with_embedded_bank(instance, target, runtime, embedded)
        return compile_subject(api.stencil_instance_subject(instance), target, runtime, bank_from_embedded(embedded))
    end

    function api.host_target()
        return Support.host_target()
    end

    function api.empty_runtime()
        return Support.empty_runtime()
    end

    function api.compile_subject_on_host(subject, bank)
        return compile_subject(subject, api.host_target(), api.empty_runtime(), bank)
    end

    function api.compile_subject_with_embedded_bank_on_host(subject, embedded)
        return compile_subject(subject, api.host_target(), api.empty_runtime(), bank_from_embedded(embedded))
    end

    function api.compile_code_module_on_host(module, bank)
        return compile_subject(api.code_module_subject(module), api.host_target(), api.empty_runtime(), bank)
    end

    function api.compile_code_module_with_embedded_bank_on_host(module, embedded)
        return compile_subject(api.code_module_subject(module), api.host_target(), api.empty_runtime(), bank_from_embedded(embedded))
    end

    function api.compile_code_func_on_host(func, bank)
        return compile_subject(api.code_func_subject(func), api.host_target(), api.empty_runtime(), bank)
    end

    function api.compile_code_func_with_embedded_bank_on_host(func, embedded)
        return compile_subject(api.code_func_subject(func), api.host_target(), api.empty_runtime(), bank_from_embedded(embedded))
    end

    function api.compile_kernel_plan_on_host(plan, bank)
        return compile_subject(api.kernel_plan_subject(plan), api.host_target(), api.empty_runtime(), bank)
    end

    function api.compile_kernel_plan_with_embedded_bank_on_host(plan, embedded)
        return compile_subject(api.kernel_plan_subject(plan), api.host_target(), api.empty_runtime(), bank_from_embedded(embedded))
    end

    function api.compile_stencil_instance_on_host(instance, bank)
        return compile_subject(api.stencil_instance_subject(instance), api.host_target(), api.empty_runtime(), bank)
    end

    function api.compile_stencil_instance_with_embedded_bank_on_host(instance, embedded)
        return compile_subject(api.stencil_instance_subject(instance), api.host_target(), api.empty_runtime(), bank_from_embedded(embedded))
    end

    T._lalin_api_cache.native_backend = api
    return api
end

return bind_context
