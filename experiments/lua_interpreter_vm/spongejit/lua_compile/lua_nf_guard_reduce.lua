-- lua_nf_guard_reduce.lua -- redundant guard reduction.

local M = {}
function M.reduce(guards)
  local seen, out = {}, {}
  for _, g in ipairs(guards or {}) do
    local k = tostring(g.kind) .. ":" .. tostring(g.subject and g.subject.kind) .. ":" .. tostring(g.predicate and g.predicate.kind)
    if not seen[k] then seen[k] = true; out[#out + 1] = g end
  end
  return out
end
return M
