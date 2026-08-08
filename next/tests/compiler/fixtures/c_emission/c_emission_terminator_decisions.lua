local names = {
  "Branch",
  "Jump",
  "ReturnValue",
  "ReturnVoid",
  "Switch",
  "Trap",
  "Unreachable",
  "VariantSwitch",
}

local leaves = {}
local decisions = {}
for _, name in ipairs(names) do
  local leaf = "C.Terminator." .. name
  leaves[#leaves + 1] = leaf
  decisions[#decisions + 1] = { leaf = leaf, status = "EMIT" }
end

table.sort(leaves)

return {
  key = "c_emission_terminator_decisions",
  boundary = "C.Terminator -> C control statement",
  leaves = leaves,
  decisions = decisions,
}
