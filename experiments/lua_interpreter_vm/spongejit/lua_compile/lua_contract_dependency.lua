-- lua_contract_dependency.lua -- epoch/dependency extraction.

local M = {}
function M.collect_from_facts(facts)
  local seen, out = {}, {}
  for _, f in ipairs(facts or {}) do for _, d in ipairs(f.deps or {}) do if not seen[d] then seen[d] = true; out[#out + 1] = d end end end
  return out
end
return M
