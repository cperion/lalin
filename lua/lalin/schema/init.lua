-- Canonical LalinSchema package loader.
--
-- Runtime schema source is Lua/LalinSchema data under lua/lalin/schema/*.lua.
-- Compact .asdl text is not an active source path.

local Dsl = require("lalin.schema.dsl")

local M = {}

local SCHEMA_MODULES = {
    "lalin.schema_v2.core",
    "backend_schema",
    "c",
    "c_materialize",
    "luajit",
    "luatrace",
    "link",
    "lalin.schema_v2.type",
    "lalin.schema_v2.bind",
    "lalin.schema_v2.sem",
    "lalin.schema_v2.tree",
    "lalin.schema_v2.check",
    "code",
    "code_backend",
    "code_validate_schema",
    "tree_lower",
    "graph",
    "flow",
    "value",
    "mem",
    "effect",
    "kernel",
    "stencil",
    "stencil_machine",
    "native",
    "lalin.schema_v2.exec",
    "schedule",
    "lower",
    "emit_c",
    "compiler",
    "lalin.schema_v2.parse",
    "host",
    "lalin.schema_v2.source",
}

local function append(dst, src)
    for i = 1, #(src or {}) do dst[#dst + 1] = src[i] end
end

local function load_schema_module(name)
    local mod_path = name:find(".", 1, true) and name or ("lalin.schema." .. name)
    local mod = require(mod_path)
    if not Dsl.is_schema_value(mod, "Module") and mod_path:match("^lalin%.schema_v2%.") then
        local declarations = package.loaded["lalin.schema_v2.declarations"]
        mod = declarations and declarations[name:match("([^.]+)$")] or mod
    end
    if not Dsl.is_schema_value(mod, "Module") then
        error("lalin.schema: module " .. mod_path .. " did not return a LalinSchema module", 2)
    end
    return mod
end

function M.modules_for_test()
    local copy = {}
    for i, name in ipairs(SCHEMA_MODULES) do copy[i] = name:match("([^.]+)$") end
    return copy
end

function M.schema_modules_for_test()
    return M.modules_for_test()
end

function M.load_modules(names)
    names = names or SCHEMA_MODULES
    local out = {}
    for _, name in ipairs(names) do out[#out + 1] = load_schema_module(name) end
    return out
end

function M.schema(T)
    return Dsl.to_asdl_schema(T, M.load_modules())
end

local function bind_context(T)
    if T._lalin_canonical_schema_defined then return T end
    Dsl.define(T, M.load_modules())
    require("lalin.compiler_implementation").install_canonical(T)
    T._lalin_canonical_schema_defined = true
    return T
end

M.dsl = Dsl
M.use = Dsl.use
M.define = Dsl.define
M.to_asdl_schema = Dsl.to_asdl_schema

return setmetatable(M, {
    __call = function(_, ...)
        return bind_context(...)
    end,
})
