-- mlui_build_c.lua — Build the MLUI C artifact.
--
-- This is a build orchestrator.  It loads all MLUI modules and provides
-- hooks for C emission.  Full C backend emission requires moon.emit_c
-- which is not yet in the public API; this file documents the intent
-- and provides the module bundle that a build script would use.

local M = {}

local function find_mlui_files()
    local dir = "experiments/mlui"
    local names = {
        "mlui_types.mlua", "mlui_memory.mlua", "mlui_kernel_store.mlua",
        "mlui_resource_store.mlua", "mlui_program_validate.mlua",
        "mlui_program_import.mlua", "mlui_compose_expand.mlua",
        "mlui_style_resolve.mlua", "mlui_scene_lower.mlua",
        "mlui_measure.mlua", "mlui_solve.mlua", "mlui_render_ops.mlua",
        "mlui_runtime_report.mlua", "mlui_interact.mlua", "mlui_abi.mlua",
    }
    local files = {}
    for _, name in ipairs(names) do
        local path = dir .. "/" .. name
        local f = io.open(path, "r")
        if f then f:close(); files[#files + 1] = path end
    end
    return files
end

-- Load all MLUI modules and return the ABI module table.
-- All modules must compile.
function M.load_all()
    local moon = require("moonlift")
    local files = find_mlui_files()
    -- Load in dependency order
    local bundles = {}
    for _, path in ipairs(files) do
        local ch = moon.loadfile(path)
        bundles[path] = ch()
    end
    return bundles
end

-- Verify all modules load without error.
function M.verify()
    local ok, err = pcall(M.load_all)
    if not ok then
        return false, tostring(err)
    end
    return true, "all " .. #find_mlui_files() .. " modules load"
end

-- Emit a C source blob for the MLUI kernel.
-- In the current API, this requires the internal C backend:
--   local CEmit = require("moonlift.c_emit")
--   local c_src = CEmit.Define(T).emit(program, opts)
-- For now, this is a documentation placeholder.
function M.emit_c_source()
    error("moon.emit_c is not in the public API yet. " ..
          "Use the internal C backend via require('moonlift.c_emit') " ..
          "once the MLUI program is compiled through the frontend pipeline.")
end

-- Smoke test: verify all modules load.
local ok, msg = M.verify()
print("MLUI build: " .. msg)

return M
