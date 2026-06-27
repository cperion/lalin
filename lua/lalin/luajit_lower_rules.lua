local function bind_context(T)
    T._lalin_api_cache = T._lalin_api_cache or {}
    if T._lalin_api_cache.luajit_lower_rules ~= nil then return T._lalin_api_cache.luajit_lower_rules end

    local api = {
        kind = {
            stencil_reduce = "stencil_reduce",
            stencil_store = "stencil_store",
            stencil_skeleton = "stencil_skeleton",
            no_plan = "no_plan",
            skeleton_scan = "skeleton_scan",
            skeleton_find = "skeleton_find",
            skeleton_partition = "skeleton_partition",
            skeleton_copy = "skeleton_copy",
            skeleton_scatter_reduce = "skeleton_scatter_reduce",
        },
    }

    local function common_kernel_ready(kernel)
        return kernel.loop_plan
            and kernel.owns_loop
            and kernel.planned
            and kernel.counted_positive
    end

    local function select_kernel_lowering(kernel)
        if common_kernel_ready(kernel)
            and kernel.has_skeleton_provider
            and kernel.stencil_skeleton_ready then
            return { kind = api.kind.stencil_skeleton }
        end
        if common_kernel_ready(kernel)
            and kernel.has_store_provider
            and kernel.returns_void
            and kernel.single_store
            and kernel.store_dst_base
            and not kernel.stencil_skeleton_ready
            and kernel.stencil_store_ready then
            return { kind = api.kind.stencil_store }
        end
        if common_kernel_ready(kernel)
            and kernel.has_reduce_provider
            and kernel.result_reduction
            and kernel.returns_reduction
            and not kernel.stencil_skeleton_ready
            and kernel.stencil_reduce_ready then
            return { kind = api.kind.stencil_reduce }
        end
        return { kind = api.kind.no_plan, reason = kernel.reject_reason }
    end

    local function select_skeleton_lowering(skeleton)
        if skeleton.scan_ready then
            return { kind = api.kind.skeleton_scan, planned = skeleton.scan_plan }
        end
        if skeleton.find_ready then
            return { kind = api.kind.skeleton_find, planned = skeleton.find_plan }
        end
        if skeleton.partition_ready then
            return { kind = api.kind.skeleton_partition, planned = skeleton.partition_plan }
        end
        if skeleton.copy_ready then
            return { kind = api.kind.skeleton_copy, planned = skeleton.copy_plan }
        end
        if skeleton.scatter_reduce_ready then
            return { kind = api.kind.skeleton_scatter_reduce, planned = skeleton.scatter_reduce_plan }
        end
        return { kind = api.kind.no_plan, reason = skeleton.reject_reason }
    end

    function api:run(relation, input, _output_key, missing)
        if relation == "select_kernel_lowering" then
            local kernel = input and input.kernel
            if kernel == nil then return nil, missing or "missing LuaJIT kernel lowering input" end
            return select_kernel_lowering(kernel)
        end
        if relation == "select_skeleton_lowering" then
            local skeleton = input and input.skeleton
            if skeleton == nil then return nil, missing or "missing LuaJIT skeleton lowering input" end
            return select_skeleton_lowering(skeleton)
        end
        return nil, missing or ("unknown LuaJIT lowering relation " .. tostring(relation))
    end

    T._lalin_api_cache.luajit_lower_rules = api
    return api
end

return bind_context
