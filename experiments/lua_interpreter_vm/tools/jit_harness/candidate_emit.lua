-- candidate_emit.lua
-- Emits low-level Moonlift kernels from candidate descriptions
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.10

local M = {}

-- Template for a code stencil kernel
M.KERNEL_TEMPLATE = [[
-- Auto-generated stencil kernel: %s
-- Implements: %s
-- Arity: %d
-- Generated: %s

func stencil_%s() -> i32
    return 0
end
]]

-- Emit a candidate kernel in Moonlift source format
function M.emit_candidate_kernel(candidate, config)
    config = config or {}

    -- Generate kernel name from candidate ID
    local kernel_name = string.gsub(candidate.id or "kernel", "[^%w_]", "_")

    -- Generate kernel source
    local source = string.format(M.KERNEL_TEMPLATE,
        kernel_name,
        candidate.id or "unknown",
        candidate.arity or 1,
        os.date(),
        kernel_name)

    local kernel = {
        id = kernel_name,
        name = kernel_name,
        source = source,
        path = config.output_dir and (config.output_dir .. "/" .. kernel_name .. ".mlua") or nil,
        candidate_id = candidate.id,
        arity = candidate.arity or 1,
    }

    return kernel
end

-- Emit a code stencil kernel (same as regular kernel for now)
function M.emit_code_stencil_kernel(candidate, config)
    return M.emit_candidate_kernel(candidate, config)
end

-- Emit a rewrite stencil specification
function M.emit_rewrite_stencil_spec(candidate, config)
    -- Rewrite stencils are plan-level transformations, not code
    return {
        id = candidate.id or "rewrite",
        type = "rewrite",
        pattern = candidate.pattern or {},
        required_facts = candidate.facts or {},
        replacement = candidate.replacement or {},
        proof = candidate.proof or "unproven",
    }
end

-- Write kernel source to disk
function M.write_kernel_source(kernel, output_dir)
    if not output_dir then
        return nil, "output_dir required"
    end

    os.execute("mkdir -p " .. output_dir)

    local path = output_dir .. "/" .. kernel.name .. ".mlua"
    local f = io.open(path, "w")
    if not f then
        return nil, "cannot write to " .. path
    end

    f:write(kernel.source)
    f:close()

    return path
end

-- Batch emit multiple kernels
function M.emit_kernel_batch(candidates, config)
    config = config or {}

    local kernels = {}
    local written = 0

    for _, candidate in ipairs(candidates) do
        local kernel = M.emit_candidate_kernel(candidate, config)

        if config.output_dir then
            local path, err = M.write_kernel_source(kernel, config.output_dir)
            if path then
                written = written + 1
            elseif not config.ignore_errors then
                return nil, err
            end
        end

        table.insert(kernels, kernel)
    end

    return {
        kernels = kernels,
        emitted = #kernels,
        written = written,
    }
end

-- Report emission results
function M.report_emission(result)
    print("\n=== Kernel Emission ===")
    print(string.format("Emitted: %d kernels", result.emitted or 0))
    print(string.format("Written: %d files", result.written or 0))
end

return M
