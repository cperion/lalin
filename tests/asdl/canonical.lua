-- tests/asdl/canonical.lua
-- Shared ASDL test fixture: build a fresh ASDL context defined from the
-- canonical schema module set (the same declarations the main bootstrap
-- loads), without installing compiler implementations.  Used by ASDL
-- runtime-mechanics tests that need isolated contexts.

local asdl = require("lalin.asdl")
local S = require("lalin.schema.dsl")

local files = {
  "core", "parse", "source", "type", "c", "bind", "sem",
  "tree", "check", "tree_code", "code", "graph", "flow", "value", "mem",
  "effect", "kernel", "stencil", "c_materialize", "lower", "schedule",
  "backend", "cemit", "compiler", "code_validation", "exec", "phase", "project",
}

local M = {}

function M.context()
  local T = asdl.context()
  local modules = {}
  for i = 1, #files do
    modules[#modules + 1] = require("lalin.schema." .. files[i])
  end
  modules[#modules + 1] = require("lalin.schema.host")
  S.define(T, modules)
  return T
end

return M
