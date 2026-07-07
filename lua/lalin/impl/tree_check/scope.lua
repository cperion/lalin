-- impl/tree_check/scope.lua
-- Type scope management leaf methods.

require("lalin.schema_v2")
local B      = require("lalin.schema_v2.bind")
local LCheck = require("lalin.schema_v2.check")

function LCheck.TypeValueScope:typecheck_tree_lookup_value(name)
  for _, e in ipairs(self.entries or {}) do
    if e.name == name then return e end
  end
  return nil
end

function LCheck.TypeValueScope:typecheck_tree_add_value(name, ty, binding)
  local entries = {}
  for _, e in ipairs(self.entries or {}) do entries[#entries+1] = e end
  entries[#entries+1] = B.ValueEntry(name, binding or B.Binding(nil, name, ty, B.BindingRoleLocalValue))
  return LCheck.TypeValueScope(entries)
end

function LCheck.TypeValueScope:typecheck_tree_add_type(name, ty) return self end
