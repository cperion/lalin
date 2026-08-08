local spec = require("support.spec")
local impl_style = require("compiler.support.impl_style")

local describe, it = spec.describe, spec.it

describe("compiler implementation style", function()
  it("does not use manual tag/kind dispatch in next compiler implementation files", function()
    local violations = impl_style.violations("next/lua/lalin/compiler/impl")
    spec.assert_equal(table.concat(violations, "\n"), "", "forbidden implementation dispatch")
  end)
end)
