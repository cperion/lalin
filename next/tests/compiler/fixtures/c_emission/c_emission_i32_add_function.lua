local Compiler = require("lalin.compiler.schema")
local fixtures = require("compiler.support.fixtures")

return {
  key = "c_emission_i32_add_function",
  boundary = "C.FunctionDefinition -> emitted C definition",
  leaves = {
    "C.Operation.BinaryOp",
    "C.Terminator.ReturnValue",
    "C.Value.LocalValue",
    "C.Value.ParameterValue",
    "C.LocalSource.GeneratedLocal",
    "C.ParameterSource.GeneratedParameter",
    "C.AbiResultSlot.DirectSlot",
  },
  input = fixtures.c_i32_add_function_definition(),
  input_type = Compiler.C.FunctionDefinition,
  expected_c = "next/tests/compiler/golden/c_emission/i32_add.c",
}
