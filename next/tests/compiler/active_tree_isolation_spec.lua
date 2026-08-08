local spec = require("support.spec")

local describe, it = spec.describe, spec.it

local function rg(pattern, path)
  local command = "rg -n " .. string.format("%q", pattern) .. " " .. path .. " 2>/dev/null"
  local pipe = io.popen(command)
  local out = {}
  if pipe then
    for line in pipe:lines() do out[#out + 1] = line end
    pipe:close()
  end
  return out
end

describe("active compiler tree isolation", function()
  it("does not wire active lua/lalin modules to next", function()
    local hits = rg("next/|next%.lua|lalin%.compiler%.schema|lalin/compiler/schema", "lua/lalin")
    spec.assert_equal(table.concat(hits, "\n"), "", "active tree references next compiler")
  end)

  it("resolves next compiler modules before active compiler modules", function()
    local found = assert(package.searchpath("lalin.compiler.schema", package.path))
    spec.assert_equal(found, "./next/lua/lalin/compiler/schema.lua", "schema module resolves to next tree")
  end)

  it("does not import active lalin modules from next compiler modules", function()
    local hits = rg("require%([\"']lalin%.[^c]", "next/lua/lalin/compiler")
    spec.assert_equal(table.concat(hits, "\n"), "", "next compiler imports active lalin module")
  end)
end)
