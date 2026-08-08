local Compiler = require("lalin.compiler.schema")
local spec = require("support.spec")
local diagnostic_origin = require("compiler.support.diagnostic_origin")

local describe, it = spec.describe, spec.it

describe("diagnostic origin reachability", function()
  it("matches the reviewed diagnostic origin classification golden", function()
    local path = "next/tests/compiler/golden/schema/diagnostic_origin.txt"
    local actual = diagnostic_origin.classification(Compiler)
    if os.getenv("LALIN_REGEN_DIAGNOSTIC_ORIGIN") == "1" then
      diagnostic_origin.write_file(path, actual)
    end
    local expected = diagnostic_origin.read_file(path)
    spec.assert_equal(actual, expected, "diagnostic origin classification")
  end)
end)
