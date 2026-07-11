-- lalin/schema_v2/init.lua
-- Bootstrap: instantiates all schema_v2 declarations into ASDL runtime classes
-- and patches package.loaded so impl files get actual type constructors.
--
-- After this module loads:
--   local Tree = require("lalin.schema_v2.tree")   → T.LalinTree
--   Tree.ExprLit, Tree.Module, Tree.StmtLet  etc.  → actual ASDL classes
--
-- This must be loaded before any impl/ file.

local S = require("lalin.schema.dsl")
local asdl = require("lalin.asdl")

-- All 28 schema_v2 files in dependency order (must match cross-module references)
local files = {
  "core", "parse", "source",
  "type", "c", "bind", "sem",
  "tree", "check", "tree_code",
  "code", "graph", "flow", "value", "mem", "effect",
  "kernel", "stencil", "stencil_machine",
  "lower", "schedule",
  "backend", "cemit",
  "compiler", "code_validation", "exec",
  "phase", "project",
}

-- Step 1: Load all schema modules (schema_v2 + old LalinHost)
local modules = {}

-- Schema_v2 modules
for _, name in ipairs(files) do
  local mod_path = "lalin.schema_v2." .. name
  local decl = require(mod_path)
  modules[#modules + 1] = decl
end

-- Old LalinHost module (referenced by sem.lua via LalinHost.HostFieldRep)
local host_decl = require("lalin.schema.host")
modules[#modules + 1] = host_decl

-- Old LalinLuaJIT module (referenced by stencil_machine.lua)
local luajit_decl = require("lalin.schema.luajit")
modules[#modules + 1] = luajit_decl



-- Step 2: Create ASDL context and instantiate all modules at once
local T = asdl.context()
S.define(T, modules)

require("lalin.compiler_implementation").install_schema_v2(T)

-- Step 3: Patch package.loaded so impl files get typed namespaces
-- Map schema module name → T namespace
local name_to_path = {}
for _, name in ipairs(files) do
  local mod_path = "lalin.schema_v2." .. name
  local decl = package.loaded[mod_path]
  if decl and decl.name then
    name_to_path[decl.name] = mod_path
  end
end

for ns_name, ns_table in pairs(T.namespaces) do
  local mod_path = name_to_path[ns_name]
  if mod_path then
    package.loaded[mod_path] = ns_table
  end
end

-- Also expose the full context for advanced use
return T
