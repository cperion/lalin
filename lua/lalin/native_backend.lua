local asdl = require("lalin.asdl")

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

    local function require_typed(value, class, name)
        require_value(value, name)
        if not asdl.isa(value, class) then boundary_error(name .. " must be a typed " .. tostring(class)) end
        return value
    end

    local function manifest_matches(left, right)
        return left ~= nil and right ~= nil and left.id == right.id and left.support_domain == right.support_domain and left.total_count == right.total_count
    end

    local function require_manifest_cardinality(manifest, entry_count, subject_name)
        require_typed(manifest, Native.NativeTemplateSourceManifest, subject_name .. " manifest")
        if manifest.total_count ~= entry_count then
            boundary_error(subject_name .. " manifest total_count " .. tostring(manifest.total_count) .. " does not match entry count " .. tostring(entry_count))
        end
        return manifest
    end

    local function require_bank(bank, target, expected_manifest)
        require_typed(bank, Native.NativeTemplateBank, "NativeTemplateBank")
        if target ~= nil and bank.target ~= target then boundary_error("NativeTemplateBank target does not match compile target") end
        require_manifest_cardinality(bank.manifest, #(bank.entries or {}), "NativeTemplateBank")
        if expected_manifest ~= nil and not manifest_matches(bank.manifest, expected_manifest) then
            boundary_error("NativeTemplateBank manifest does not match expected native template manifest")
        end
        return bank
    end

    local function require_embedded_bank(embedded, expected_manifest)
        require_typed(embedded, Native.NativeEmbeddedTemplateBank, "NativeEmbeddedTemplateBank")
        require_manifest_cardinality(embedded.manifest, #(embedded.entries or {}), "NativeEmbeddedTemplateBank")
        if expected_manifest ~= nil and not manifest_matches(embedded.manifest, expected_manifest) then
            boundary_error("NativeEmbeddedTemplateBank manifest does not match expected native template manifest")
        end
        return embedded
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

    local function native_request(subject, target, runtime, bank, expected_manifest)
        target = require_typed(target, Native.NativeTarget, "NativeTarget")
        return Native.NativeCompileRequest(
            require_value(subject, "NativeCompileSubject"),
            target,
            require_typed(runtime, Native.NativeRuntime, "NativeRuntime"),
            require_bank(bank, target, expected_manifest)
        )
    end

    local function compile_subject(subject, target, runtime, bank, expected_manifest)
        return native_request(subject, target, runtime, bank, expected_manifest):compile_native()
    end

    local function bank_from_embedded(embedded, expected_manifest)
        embedded = require_embedded_bank(embedded, expected_manifest)
        return Native.NativeEmbeddedBankImportRequest(embedded):import_native_bank():required_native_bank()
    end

    function api.import_embedded_bank(embedded, expected_manifest)
        embedded = require_embedded_bank(embedded, expected_manifest)
        return Native.NativeEmbeddedBankImportRequest(embedded):import_native_bank()
    end

    function api.require_imported_bank(embedded, expected_manifest)
        return bank_from_embedded(embedded, expected_manifest)
    end

    function api.require_native_bank(bank, target, expected_manifest)
        return require_bank(bank, target, expected_manifest)
    end

    function api.bank_manifest(bank)
        return require_bank(bank).manifest
    end

    function api.embedded_bank_manifest(embedded)
        return require_embedded_bank(embedded).manifest
    end

    function api.runtime(symbols)
        return Native.NativeRuntime(symbols or {})
    end

    function api.compile_subject(subject, target, runtime, bank, expected_manifest)
        return compile_subject(subject, target, runtime, bank, expected_manifest)
    end

    function api.compile_subject_with_embedded_bank(subject, target, runtime, embedded, expected_manifest)
        return compile_subject(subject, target, runtime, bank_from_embedded(embedded, expected_manifest), expected_manifest)
    end

    function api.compile_subject_with_runtime_symbols(subject, target, symbols, bank, expected_manifest)
        return compile_subject(subject, target, api.runtime(symbols), bank, expected_manifest)
    end

    function api.compile_subject_executable(subject, target, runtime, bank, expected_manifest)
        return compile_subject(subject, target, runtime, bank, expected_manifest):native_executable()
    end

    function api.compile_subject_with_embedded_bank_executable(subject, target, runtime, embedded, expected_manifest)
        return compile_subject(subject, target, runtime, bank_from_embedded(embedded, expected_manifest), expected_manifest):native_executable()
    end

    function api.code_module_subject(module)
        return Native.NativeCompileCodeModule(require_value(module, "CodeModule"))
    end

    function api.code_func_subject(func, signature)
        return Native.NativeCompileCodeFunc(require_value(func, "CodeFunc"), require_value(signature, "CodeSig"))
    end

    function api.kernel_plan_subject(plan, lowering)
        return Native.NativeCompileKernelPlan(require_value(plan, "KernelPlan"), require_value(lowering, "NativeKernelLoweringInput"))
    end

    function api.stencil_instance_subject(instance)
        return Native.NativeCompileStencilInstance(require_value(instance, "StencilInstance"))
    end

    function api.compile_code_module(module, target, runtime, bank, expected_manifest)
        return compile_subject(api.code_module_subject(module), target, runtime, bank, expected_manifest)
    end

    function api.compile_code_module_with_embedded_bank(module, target, runtime, embedded, expected_manifest)
        return compile_subject(api.code_module_subject(module), target, runtime, bank_from_embedded(embedded, expected_manifest), expected_manifest)
    end

    function api.compile_code_func(func, signature, target, runtime, bank, expected_manifest)
        return compile_subject(api.code_func_subject(func, signature), target, runtime, bank, expected_manifest)
    end

    function api.compile_code_func_with_embedded_bank(func, signature, target, runtime, embedded, expected_manifest)
        return compile_subject(api.code_func_subject(func, signature), target, runtime, bank_from_embedded(embedded, expected_manifest), expected_manifest)
    end

    function api.compile_code_func_with_runtime_symbols(func, signature, target, symbols, bank, expected_manifest)
        return compile_subject(api.code_func_subject(func, signature), target, api.runtime(symbols), bank, expected_manifest)
    end

    function api.compile_kernel_plan(plan, lowering, target, runtime, bank)
        return compile_subject(api.kernel_plan_subject(plan, lowering), target, runtime, bank)
    end

    function api.compile_kernel_plan_with_embedded_bank(plan, lowering, target, runtime, embedded)
        return compile_subject(api.kernel_plan_subject(plan, lowering), target, runtime, bank_from_embedded(embedded))
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

    function api.compile_code_func_on_host(func, signature, bank)
        return compile_subject(api.code_func_subject(func, signature), api.host_target(), api.empty_runtime(), bank)
    end

    function api.compile_code_func_with_embedded_bank_on_host(func, signature, embedded)
        return compile_subject(api.code_func_subject(func, signature), api.host_target(), api.empty_runtime(), bank_from_embedded(embedded))
    end

    function api.compile_kernel_plan_on_host(plan, lowering, bank)
        return compile_subject(api.kernel_plan_subject(plan, lowering), api.host_target(), api.empty_runtime(), bank)
    end

    function api.compile_kernel_plan_with_embedded_bank_on_host(plan, lowering, embedded)
        return compile_subject(api.kernel_plan_subject(plan, lowering), api.host_target(), api.empty_runtime(), bank_from_embedded(embedded))
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
