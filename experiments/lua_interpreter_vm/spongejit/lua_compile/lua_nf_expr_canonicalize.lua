-- lua_nf_expr_canonicalize.lua -- arithmetic/value canonical forms.

local B = require("lua_compile.builders")
local T = B.T
local Sem, NF = T.LuaSem, T.LuaNF

local M = {}

local function atom_key(a)
  if a.kind == "SrcSlotI64" then return "S" .. a.slot.id end
  if a.kind == "ImmI64" then return "I" .. a.imm.value end
  if a.kind == "ConstI64" then return "K" .. a.k.id end
  if a.kind == "VarargI64" then return "V" .. a.base.id .. ":" .. a.index.value end
  return tostring(a.kind)
end

function M.affine(terms, constant)
  local by_key, atoms = {}, {}
  for _, t in ipairs(terms or {}) do
    local k = atom_key(t.atom)
    by_key[k] = (by_key[k] or 0) + t.coefficient
    atoms[k] = t.atom
  end
  local keys, out = {}, {}
  for k, c in pairs(by_key) do if c ~= 0 then keys[#keys + 1] = k end end
  table.sort(keys)
  for _, k in ipairs(keys) do out[#out + 1] = NF.I64Term(by_key[k], atoms[k]) end
  return NF.CanonAffineI64(out, constant or 0)
end

return M
