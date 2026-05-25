-- candidate_compile.lua
-- Compiles candidate kernels through the Moonlift/Cranelift path
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.11

local M = {}

-- Compile a single kernel through Moonlift
function M.compile_kernel(kernel, config)
    config = config or {}

    -- In production, would invoke: moonlift --emit-object kernel.mlua -o kernel.o
    -- For now, return a mock compiled object

    return {
        id = kernel.id,
        kernel_id = kernel.id,
        input_path = kernel.path,
        output_path = config.output_dir and (config.output_dir .. "/" .. kernel.id .. ".o") or nil,
        compiled = true,
        size_bytes = math.random(100, 1000),  -- Placeholder
        symbol = "stencil_" .. kernel.id,
    }
end

-- Compile a batch of kernels
function M.compile_kernel_batch(kernels, config)
    config = config or {}

    local results = {}
    local failed = 0
    local succeeded = 0

    for _, kernel in ipairs(kernels) do
        local result = M.compile_kernel(kernel, config)

        if result.compiled then
            succeeded = succeeded + 1
        else
            failed = failed + 1
        end

        table.insert(results, result)
    end

    return {
        results = results,
        total = #kernels,
        succeeded = succeeded,
        failed = failed,
    }
end

-- Dump compiled object to output directory
function M.dump_candidate_object(obj, output_dir)
    output_dir = output_dir or "build/candidate_objects"
    os.execute("mkdir -p " .. output_dir)

    -- In production, would copy .o file or extract from cache
    -- For now, create a metadata file

    local manifest = "{\n"
    manifest = manifest .. '  "id": "' .. obj.id .. '",\n'
    manifest = manifest .. '  "kernel_id": "' .. obj.kernel_id .. '",\n'
    manifest = manifest .. '  "symbol": "' .. obj.symbol .. '",\n'
    manifest = manifest .. '  "size_bytes": ' .. obj.size_bytes .. ",\n"
    manifest = manifest .. '  "timestamp": ' .. os.time() .. "\n"
    manifest = manifest .. "}\n"

    local path = output_dir .. "/" .. obj.id .. ".json"
    local f = io.open(path, "w")
    if not f then
        return nil, "cannot write to " .. path
    end

    f:write(manifest)
    f:close()

    return {
        output_dir = output_dir,
        manifest = path,
        object = obj,
    }
end

-- Report compilation results
function M.report_compilation(batch_result)
    print("\n=== Compilation Results ===")
    print(string.format("Compiled: %d", batch_result.succeeded or 0))
    print(string.format("Failed: %d", batch_result.failed or 0))

    if batch_result.failed and batch_result.failed > 0 then
        print("\n  Failed kernels:")
        for _, result in ipairs(batch_result.results or {}) do
            if not result.compiled then
                print(string.format("    - %s", result.id or "unknown"))
            end
        end
    end
end

return M
