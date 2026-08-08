local Compiler = require("lalin.compiler.schema")
local spec = require("support.spec")
local coverage = require("compiler.support.coverage")

local describe, it = spec.describe, spec.it

local SPEC_DIR = "next/tests/compiler/spec"
local FIXTURE_ROOT = "next/tests/compiler/fixtures"

describe("compiler schema specification gate", function()
  it("has a data-only compiler spec template", function()
    local file = assert(io.open(SPEC_DIR .. "/_template.lua", "r"))
    file:close()
  end)

  it("all compiler spec files have schema-valid inventories", function()
    local specs = coverage.load_phase_specs(SPEC_DIR)
    for _, cfg in pairs(specs) do
      coverage.validate_phase_spec(Compiler, cfg)
    end
  end)

  it("fixtures cannot start a boundary without a compiler spec", function()
    local specs = coverage.load_phase_specs(SPEC_DIR)
    local fixtures = coverage.scan_fixture_dirs(FIXTURE_ROOT)
    for key in pairs(fixtures) do
      local cfg = specs[key]
      spec.assert_truthy(cfg, key .. " has fixtures but no compiler spec")
      spec.assert_truthy(cfg.status ~= "planned", key .. " has fixtures but spec is still planned")
    end
  end)

  it("green compiler specs have full declared leaf fixture coverage", function()
    local specs = coverage.load_phase_specs(SPEC_DIR)
    for _, cfg in pairs(specs) do
      if cfg.status == "green" then
        coverage.validate_phase_spec(Compiler, cfg)
        coverage.assert_phase_coverage(Compiler, cfg, cfg.fixtures)
      end
    end
  end)
end)
