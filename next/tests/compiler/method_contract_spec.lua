local Compiler = require("lalin.compiler.schema")
local spec = require("support.spec")
local coverage = require("compiler.support.coverage")

local describe, it = spec.describe, spec.it

describe("compiler boundary method contracts", function()
  it("all declared method owners and implementation-order entries are schema-valid", function()
    local specs = coverage.load_phase_specs("next/tests/compiler/spec")
    for _, cfg in pairs(specs) do
      coverage.validate_phase_spec(Compiler, cfg)
    end
  end)

  it("c_emission implementation order covers each declared method exactly once", function()
    local cfg = coverage.load_phase_specs("next/tests/compiler/spec").c_emission
    local declared = {}
    for _, contract in ipairs(cfg.methods or {}) do
      declared[contract.owner .. ":" .. contract.method] = true
    end
    local ordered = {}
    for _, key in ipairs(cfg.implementation_order or {}) do
      spec.assert_truthy(declared[key], "implementation order key has no method contract: " .. key)
      spec.assert_nil(ordered[key], "duplicate implementation order key: " .. key)
      ordered[key] = true
    end
    for key in pairs(declared) do
      spec.assert_truthy(ordered[key], "method contract missing from implementation order: " .. key)
    end
  end)
end)
