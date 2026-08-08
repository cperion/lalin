local Compiler = require("lalin.compiler.schema")
local spec = require("support.spec")
local fixture_cases = require("compiler.support.fixture_cases")

local describe, it = spec.describe, spec.it

describe("c_emission schema-shaped fixtures", function()
  it("loads c_emission fixtures and their goldens", function()
    local cases = fixture_cases.load_dir("next/tests/compiler/fixtures/c_emission")
    spec.assert_truthy(#cases > 0, "expected at least one c_emission fixture")
    for _, case in ipairs(cases) do
      fixture_cases.assert_common(spec, Compiler, case)
      spec.assert_truthy(case.input or case.cases or case.decisions,
        "c_emission fixture must provide input, cases, or decisions")
    end
  end)
end)
