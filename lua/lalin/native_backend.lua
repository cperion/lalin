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
        return left ~= nil
            and right ~= nil
            and left.id == right.id
            and left.support_domain == right.support_domain
            and left.total_count == right.total_count
    end

    local function require_manifest_cardinality(manifest, template_count, subject_name)
        require_typed(manifest, Native.NativeTemplateSourceManifest, subject_name .. " manifest")
        if manifest.total_count ~= template_count then
            boundary_error(subject_name .. " manifest total_count " .. tostring(manifest.total_count) .. " does not match C template count " .. tostring(template_count))
        end
        return manifest
    end

    local function require_artifact(artifact, target, expected_manifest)
        require_typed(artifact, Native.NativeBankArtifact, "NativeBankArtifact")
        if target ~= nil and artifact.target ~= target then boundary_error("NativeBankArtifact target does not match compile target") end
        require_manifest_cardinality(artifact.manifest, artifact.template_count, "NativeBankArtifact")
        if expected_manifest ~= nil and not manifest_matches(artifact.manifest, expected_manifest) then
            boundary_error("NativeBankArtifact manifest does not match expected native template manifest")
        end
        if artifact.api_symbol == nil or artifact.api_symbol == "" then boundary_error("NativeBankArtifact is missing its C API symbol") end
        if artifact.selector_symbol == nil or artifact.selector_symbol == "" then boundary_error("NativeBankArtifact is missing its C selector symbol") end
        if artifact.installer_symbol == nil or artifact.installer_symbol == "" then boundary_error("NativeBankArtifact is missing its C installer symbol") end
        return artifact
    end

    local function reject_summary(rejects)
        local count = #(rejects or {})
        if count == 0 then return "no typed rejects supplied" end
        return tostring(count) .. " typed reject(s); first reject: " .. tostring(rejects[1])
    end

    function Native.NativeCompileResult:native_executable()
        return self.executable
    end

    local function load_result_required(result)
        return result:required_native_bank()
    end

    local function require_loaded_bank(bank, target, expected_manifest, shared_object_path)
        require_value(bank, "NativeLoadedBank or NativeBankArtifact")
        if asdl.isa(bank, Native.NativeLoadedBank) then
            if shared_object_path ~= nil then boundary_error("shared object path can only be supplied with a NativeBankArtifact descriptor") end
            require_artifact(bank.artifact, target, expected_manifest)
            if bank.handle_address == nil or bank.handle_address == 0 then boundary_error("NativeLoadedBank has no C bank handle address") end
            return bank
        end
        if asdl.isa(bank, Native.NativeBankArtifact) then
            local artifact = require_artifact(bank, target, expected_manifest)
            return load_result_required(Native.NativeBankLoadRequest(artifact, shared_object_path):load_native_bank())
        end
        boundary_error("native bank must be a C-owned NativeLoadedBank or NativeBankArtifact descriptor")
    end

    local function artifact_for(value)
        require_value(value, "NativeLoadedBank or NativeBankArtifact")
        if asdl.isa(value, Native.NativeLoadedBank) then return value.artifact end
        if asdl.isa(value, Native.NativeBankArtifact) then return value end
        boundary_error("native bank descriptor must be NativeBankArtifact or NativeLoadedBank")
    end

    local function native_request(subject, target, runtime, bank, expected_manifest, shared_object_path)
        target = require_typed(target, Native.NativeTarget, "NativeTarget")
        return Native.NativeCompileRequest(
            require_value(subject, "NativeCompileSubject"),
            target,
            require_typed(runtime, Native.NativeRuntime, "NativeRuntime"),
            require_loaded_bank(bank, target, expected_manifest, shared_object_path)
        )
    end

    local function compile_subject(subject, target, runtime, bank, expected_manifest, shared_object_path)
        return native_request(subject, target, runtime, bank, expected_manifest, shared_object_path):compile_native()
    end

    function api.load_native_bank(artifact, shared_object_path, target, expected_manifest)
        artifact = require_artifact(artifact, target, expected_manifest)
        return Native.NativeBankLoadRequest(artifact, shared_object_path):load_native_bank()
    end

    function api.require_native_bank(bank, target, expected_manifest, shared_object_path)
        return require_loaded_bank(bank, target, expected_manifest, shared_object_path)
    end

    function api.require_loaded_bank(bank, target, expected_manifest, shared_object_path)
        return require_loaded_bank(bank, target, expected_manifest, shared_object_path)
    end

    function api.require_bank_artifact(artifact, target, expected_manifest)
        return require_artifact(artifact, target, expected_manifest)
    end

    function api.bank_manifest(bank)
        return require_artifact(artifact_for(bank)).manifest
    end

    function api.runtime(symbols)
        return Native.NativeRuntime(symbols or {})
    end

    function api.compile_subject(subject, target, runtime, bank, expected_manifest, shared_object_path)
        return compile_subject(subject, target, runtime, bank, expected_manifest, shared_object_path)
    end

    function api.compile_subject_with_runtime_symbols(subject, target, symbols, bank, expected_manifest, shared_object_path)
        return compile_subject(subject, target, api.runtime(symbols), bank, expected_manifest, shared_object_path)
    end

    function api.compile_subject_executable(subject, target, runtime, bank, expected_manifest, shared_object_path)
        return compile_subject(subject, target, runtime, bank, expected_manifest, shared_object_path):native_executable()
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

    function api.compile_code_module(module, target, runtime, bank, expected_manifest, shared_object_path)
        return compile_subject(api.code_module_subject(module), target, runtime, bank, expected_manifest, shared_object_path)
    end

    function api.compile_code_func(func, signature, target, runtime, bank, expected_manifest, shared_object_path)
        return compile_subject(api.code_func_subject(func, signature), target, runtime, bank, expected_manifest, shared_object_path)
    end

    function api.compile_code_func_with_runtime_symbols(func, signature, target, symbols, bank, expected_manifest, shared_object_path)
        return compile_subject(api.code_func_subject(func, signature), target, api.runtime(symbols), bank, expected_manifest, shared_object_path)
    end

    function api.compile_kernel_plan(plan, lowering, target, runtime, bank, expected_manifest, shared_object_path)
        return compile_subject(api.kernel_plan_subject(plan, lowering), target, runtime, bank, expected_manifest, shared_object_path)
    end

    function api.compile_stencil_instance(instance, target, runtime, bank, expected_manifest, shared_object_path)
        return compile_subject(api.stencil_instance_subject(instance), target, runtime, bank, expected_manifest, shared_object_path)
    end

    function api.host_target()
        return Support.host_target()
    end

    function api.empty_runtime()
        return Support.empty_runtime()
    end

    function api.compile_subject_on_host(subject, bank, shared_object_path)
        return compile_subject(subject, api.host_target(), api.empty_runtime(), bank, nil, shared_object_path)
    end

    function api.compile_code_module_on_host(module, bank, shared_object_path)
        return compile_subject(api.code_module_subject(module), api.host_target(), api.empty_runtime(), bank, nil, shared_object_path)
    end

    function api.compile_code_func_on_host(func, signature, bank, shared_object_path)
        return compile_subject(api.code_func_subject(func, signature), api.host_target(), api.empty_runtime(), bank, nil, shared_object_path)
    end

    function api.compile_kernel_plan_on_host(plan, lowering, bank, shared_object_path)
        return compile_subject(api.kernel_plan_subject(plan, lowering), api.host_target(), api.empty_runtime(), bank, nil, shared_object_path)
    end

    function api.compile_stencil_instance_on_host(instance, bank, shared_object_path)
        return compile_subject(api.stencil_instance_subject(instance), api.host_target(), api.empty_runtime(), bank, nil, shared_object_path)
    end

    T._lalin_api_cache.native_backend = api
    return api
end

return bind_context
