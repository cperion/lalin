local Compiler = require("lalin.compiler.schema")
local fixtures = require("compiler.support.fixtures")

local unit = fixtures.empty_c_unit("c-emission-empty-unit")

return {
  key = "c_emission_empty_unit",
  boundary = "C.Unit -> emitted C text",
  leaves = {},
  input = unit,
  input_type = Compiler.C.Unit,
  expected_c = "next/tests/compiler/golden/c_emission/empty_unit.c",
}
