local Compiler = require("lalin.compiler.schema")
local fixtures = require("compiler.support.fixtures")

return {
  key = "c_emission_scalar_types",
  boundary = "C.Type -> C type spelling",
  leaves = {},
  cases = {
    { name = "i32", input = fixtures.c_i32_type(), input_type = Compiler.C.Type, expected = "int32_t" },
    { name = "u32", input = fixtures.c_u32_type(), input_type = Compiler.C.Type, expected = "uint32_t" },
    { name = "void", input = fixtures.c_void_type(), input_type = Compiler.C.Type, expected = "void" },
  },
  expected_c = "next/tests/compiler/golden/c_emission/scalar_types.txt",
}
