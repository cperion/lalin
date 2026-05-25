-- export_runtime.lua
-- Exports the runtime stencil library
-- Per LUA_STENCIL_HARNESS_DESIGN.md §4.16

local M = {}

-- Export runtime stencil library from layers
function M.export_runtime_library(layers, selector, config)
    config = config or {}

    local library = {
        timestamp = os.time(),
        version = config.version or "1.0",
        layers = #layers,
        stencils = {},
        selector = selector,
        metadata = {
            source = config.source or "harness",
            target_cpu = config.target_cpu or "x86_64",
            aot_compiled = true,
        }
    }

    -- Collect all stencils from all layers
    for layer_id, layer in ipairs(layers) do
        for _, cand in ipairs(layer.candidates or {}) do
            table.insert(library.stencils, {
                id = cand.id or "unknown",
                layer = layer_id,
                arity = cand.arity or 1,
                size = cand.size or (cand.cost and cand.cost.estimated_size) or 0,
                holes = cand.holes or {},
                relocs = cand.relocs or {},
                bytes = cand.bytes or nil,  -- Would be binary data in production
            })
        end
    end

    return library
end

-- Write runtime library in C header format
function M.write_c_header(lib, output_dir)
    local header = [[
#pragma once
/* Auto-generated stencil library header */

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t id;
    uint8_t* bytes;
    size_t size;
    uint32_t hole_count;
    uint32_t reloc_count;
} StencilHeader;

]]

    header = header .. string.format("/* Library version %s, generated %s */\n\n", lib.version, os.date())
    header = header .. string.format("/* Total stencils: %d */\n", #lib.stencils)

    -- Generate stencil declarations
    header = header .. "\nStencilHeader stencil_library[] = {\n"

    for i, stencil in ipairs(lib.stencils) do
        header = header .. string.format("    { .id = %d, .size = %d },  /* %s */\n",
            i, stencil.size, stencil.id)
    end

    header = header .. "    { .id = 0 }  /* end marker */\n"
    header = header .. "};\n"

    local path = output_dir .. "/stencil_library.h"
    local f = io.open(path, "w")
    if not f then
        return nil, "cannot write to " .. path
    end

    f:write(header)
    f:close()
    return path
end

-- Write runtime library in binary blob format
function M.write_binary_blob(lib, output_dir)
    -- In production, this would emit actual machine code bytes
    -- For now, generate a manifest

    local manifest = "{\n"
    manifest = manifest .. '  "version": "' .. lib.version .. '",\n'
    manifest = manifest .. '  "timestamp": ' .. lib.timestamp .. ",\n"
    manifest = manifest .. '  "stencil_count": ' .. #lib.stencils .. ",\n"
    manifest = manifest .. '  "stencils": [\n'

    for i, stencil in ipairs(lib.stencils) do
        manifest = manifest .. '    {\n'
        manifest = manifest .. '      "id": "' .. stencil.id .. '",\n'
        manifest = manifest .. '      "layer": ' .. stencil.layer .. ',\n'
        manifest = manifest .. '      "arity": ' .. stencil.arity .. ',\n'
        manifest = manifest .. '      "size": ' .. stencil.size .. ',\n'
        manifest = manifest .. '      "holes": ' .. #stencil.holes .. ',\n'
        manifest = manifest .. '      "relocs": ' .. #stencil.relocs .. '\n'
        manifest = manifest .. '    }' .. (i < #lib.stencils and "," or "") .. '\n'
    end

    manifest = manifest .. '  ]\n'
    manifest = manifest .. '}\n'

    local path = output_dir .. "/stencil_manifest.json"
    local f = io.open(path, "w")
    if not f then
        return nil, "cannot write to " .. path
    end

    f:write(manifest)
    f:close()
    return path
end

-- Write runtime library manifest (metadata only)
function M.write_manifest(lib, output_dir)
    local manifest = "# Runtime Stencil Library Manifest\n\n"
    manifest = manifest .. string.format("Version: %s\n", lib.version)
    manifest = manifest .. string.format("Generated: %s\n", os.date())
    manifest = manifest .. string.format("Total stencils: %d\n", #lib.stencils)
    manifest = manifest .. string.format("Layers: %d\n\n", lib.layers)

    manifest = manifest .. "## Stencil Summary\n\n"
    manifest = manifest .. "| ID | Layer | Arity | Size | Holes | Relocs |\n"
    manifest = manifest .. "|-------|-------|-------|--------|-------|--------|\n"

    for _, stencil in ipairs(lib.stencils) do
        manifest = manifest .. string.format("| %s | L%d | %d | %d | %d | %d |\n",
            stencil.id, stencil.layer, stencil.arity, stencil.size,
            #stencil.holes, #stencil.relocs)
    end

    local path = output_dir .. "/stencil_manifest.md"
    local f = io.open(path, "w")
    if not f then
        return nil, "cannot write to " .. path
    end

    f:write(manifest)
    f:close()
    return path
end

-- Export runtime library and write all artifacts
function M.write_runtime_library(lib, output_dir)
    output_dir = output_dir or "build/runtime_library"
    os.execute("mkdir -p " .. output_dir)

    local result = {
        output_dir = output_dir,
        artifacts = {},
    }

    -- Write C header
    local header_path = M.write_c_header(lib, output_dir)
    if header_path then
        table.insert(result.artifacts, header_path)
    end

    -- Write binary manifest
    local manifest_path = M.write_binary_blob(lib, output_dir)
    if manifest_path then
        table.insert(result.artifacts, manifest_path)
    end

    -- Write metadata manifest
    local md_path = M.write_manifest(lib, output_dir)
    if md_path then
        table.insert(result.artifacts, md_path)
    end

    return result
end

-- Report export results
function M.report_export(result)
    print("\n=== Export Results ===")
    print(string.format("Output directory: %s", result.output_dir))
    print(string.format("Artifacts: %d", #result.artifacts))

    for _, artifact in ipairs(result.artifacts) do
        print(string.format("  ✓ %s", artifact))
    end
end

return M
