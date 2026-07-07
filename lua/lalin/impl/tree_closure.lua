-- impl/tree_closure.lua
--
-- INCOMPLETE: Closure conversion is a stub.
-- Current implementation: 44 lines (old: 819 lines).
-- Status: find_free_vars() does not detect free variables; capture lists are always empty.
-- Impact: Any code using lambdas/closures will compile incorrectly.
-- TODO: Port full AST traversal from old lua/lalin/closure_convert.lua
-- Estimated work: 1 week (700+ lines).
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
  error("Closures not supported in schema_v2 pipeline yet (tree_closure.lua is stub)")
end

function Tr.Module:closure_convert()
  local input = Sem.ClosureRewriteInput(self:tree_code_module_name(), "anon", 0, {})
  for _, item in ipairs(self.items or {}) do item:closure_convert_item(input) end
  return self
end

function Tr.Item:closure_convert_item(input) end
function Tr.ItemFunc:closure_convert_item(input) end
