-- impl/tree_closure.lua
-- Closure conversion leaf methods.

require("lalin.schema_v2")
local C   = require("lalin.schema_v2.core")
local Ty  = require("lalin.schema_v2.type")
local B   = require("lalin.schema_v2.bind")
local Sem = require("lalin.schema_v2.sem")
local Tr  = require("lalin.schema_v2.tree")

-- Free variable detection
local function find_free_vars(body, params, captures, seen)
  if type(body) ~= "table" then return end
  if seen[body] then return end; seen[body] = true
  local param_set = {}
  for _, p in ipairs(params or {}) do param_set[p.name] = true end
  for _, stmt in ipairs(body or {}) do
    if stmt then
      find_free_vars(stmt.body or {}, params, captures, seen)
      if stmt.init then find_free_vars({stmt.init}, params, captures, seen) end
    end
  end
end

function Tr.ExprClosure:closure_convert(input)
  local captures, seen = {}, {}
  find_free_vars(self.body, self.params, captures, seen)
  -- Build capture entries
  local capture_entries, offset = {}, 0
  for name, ty in pairs(captures) do
    capture_entries[#capture_entries+1] = Sem.CaptureEntry(name, ty, offset, 8)
    offset = offset + 8
  end
  return self
end

function Tr.Module:closure_convert_module()
  local input = Sem.ClosureRewriteInput(self:tree_code_module_name(), "anon", 0, {})
  for _, item in ipairs(self.items or {}) do item:closure_convert_item(input) end
  return self
end

function Tr.Item:closure_convert_item(input) end
function Tr.ItemFunc:closure_convert_item(input) end
