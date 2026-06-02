-- lua_contract_projection.lua -- exit projection obligations.

local B = require("lua_compile.builders")
local C = B.LuaContract

local function append_unique(out, seen, xs)
  for _, p in ipairs(xs or {}) do
    local key = tostring(p.kind) .. ":" .. tostring(p.slot and p.slot.id or "")
    if not seen[key] then seen[key] = true; out[#out + 1] = p end
  end
end

local M = {}
function M.from_exit(exit)
  if exit.kind == "TestSetExit" then
    local out, seen = {}, {}
    append_unique(out, seen, exit.taken_projection or {})
    append_unique(out, seen, exit.fallthrough_projection or {})
    return C.ProjectionObligation(exit, out)
  end
  return C.ProjectionObligation(exit, exit.projection or {})
end
return M
