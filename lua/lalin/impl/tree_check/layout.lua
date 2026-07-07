-- impl/tree_check/layout.lua
-- Type layout matching leaf methods.

require("lalin.schema_v2")
local Ty  = require("lalin.schema_v2.type")
local Sem = require("lalin.schema_v2.sem")

function Ty.Type:tree_check_match_layout(env, target) return false end
function Ty.TScalar:tree_check_match_layout(env, target)
  local r = self:tree_check_layout(env, target)
  return r and r.layout ~= nil
end
function Ty.TPtr:tree_check_match_layout(env, target)
  return self.elem:tree_check_match_layout(env, target)
end
function Ty.TNamed:tree_check_match_layout(env, target)
  for _, layout in ipairs(env.layouts or {}) do
    if layout.module_name and layout.type_name == self.ref:tree_code_type_ref_name() then
      return true
    end
  end
  return false
end
