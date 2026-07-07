-- impl/tree_check/scope.lua
-- Type scope management leaf methods.

require("lalin.schema_v2")
local B      = require("lalin.schema_v2.bind")
local LCheck = require("lalin.schema_v2.check")
local Sem    = require("lalin.schema_v2.sem")

function LCheck.TypeValueScope:typecheck_tree_lookup_value(name)
  for _, e in ipairs(self.values or {}) do
    if e.name == name then return e end
  end
  return nil
end

function LCheck.TypeValueScope:typecheck_tree_add_value(name, ty, binding)
  local values = {}
  for _, e in ipairs(self.values or {}) do values[#values+1] = e end
  local b = binding or B.Binding(nil, name, ty, B.BindingRoleLocalValue)
  values[#values+1] = B.ValueEntry(name, b)
  return LCheck.TypeValueScope(self.module_name or "", values, self.types or {}, self.layouts or {}, self.facts or LCheck.TypeModuleFacts({}, {}, {}, {}, {}, {}, {}))
end

function LCheck.TypeValueScope:typecheck_tree_add_type(name, ty)
  local types = {}
  for _, e in ipairs(self.types or {}) do types[#types+1] = e end
  types[#types+1] = B.TypeEntry(name, ty)
  return LCheck.TypeValueScope(self.module_name or "", self.values or {}, types, self.layouts or {}, self.facts or LCheck.TypeModuleFacts({}, {}, {}, {}, {}, {}, {}))
end

function LCheck.TypeValueScope:typecheck_tree_add_type(name, ty) return self end
