-- llbl.syntax.registry
-- Scope-agnostic registry for parsed-channel languages.  A driver may layer
-- scope/import policy on top; this module only records language specs.

local Registry = {}
Registry.__index = Registry

local global = setmetatable({ languages = {}, namespaces = {}, direct = {} }, Registry)

local function set(list)
  local out = {}
  for _, v in ipairs(list or {}) do out[v] = true end
  return out
end

function Registry.new(parent)
  return setmetatable({ languages = {}, namespaces = {}, direct = {}, parent = parent }, Registry)
end

function Registry:register(spec)
  assert(type(spec) == "table", "syntax language spec must be a table")
  assert(type(spec.name) == "string", "syntax language spec requires name")
  assert(type(spec.parse_entry) == "function" or type(spec.statement) == "function" or type(spec.expression) == "function", "syntax language spec requires parser callbacks")

  spec.entrypoint_set = set(spec.entrypoints or {})
  self.languages[spec.name] = spec
  self.namespaces[spec.name] = spec
  if spec.owner and type(spec.owner) == "string" then self.namespaces[spec.owner] = spec end

  if spec.direct_entrypoints then
    for _, e in ipairs(spec.direct_entrypoints) do
      if self.direct[e] and self.direct[e] ~= spec then
        error("conflicting LLBL parsed-channel entrypoint `" .. e .. "`", 0)
      end
      self.direct[e] = spec
    end
  end
  return spec
end

function Registry:language(name)
  return self.languages[name] or (self.parent and self.parent:language(name))
end

function Registry:namespace(name)
  return self.namespaces[name] or (self.parent and self.parent:namespace(name))
end

function Registry:direct_entry(name)
  return self.direct[name] or (self.parent and self.parent:direct_entry(name))
end

function Registry:resolve_namespaced(first, second)
  local spec = self:namespace(first)
  if spec and spec.entrypoint_set[second] then return spec, second end
  return nil
end

function Registry:resolve_direct(name)
  local spec = self:direct_entry(name)
  if spec then return spec, name end
  return nil
end

local M = {}

function M.global() return global end
function M.new(parent) return Registry.new(parent or global) end
function M.register(spec) return global:register(spec) end
function M.language(name) return global:language(name) end
function M.namespace(name) return global:namespace(name) end
function M.resolve_namespaced(first, second) return global:resolve_namespaced(first, second) end
function M.resolve_direct(name) return global:resolve_direct(name) end

return M
