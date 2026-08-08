local Compiler = require("lalin.compiler.schema")
local fixtures = require("compiler.support.fixtures")

local i32 = fixtures.i32()
local direct_code_fn = fixtures.code_function("sig_direct", fixtures.code_signature({ i32, i32 }, i32))
local void_code_fn = fixtures.code_function("sig_void", fixtures.code_signature({ i32 }, fixtures.void()))

return {
  key = "c_emission_signature_spelling",
  boundary = "C.Signature -> C function declarator spelling",
  leaves = {
    "C.AbiResultSlot.DirectSlot",
    "C.AbiResultSlot.IndirectSlot",
    "C.AbiResultSlot.VoidSlot",
    "C.ParameterSource.CodeParameter",
    "C.ParameterSource.GeneratedParameter",
  },
  cases = {
    {
      name = "i32_i32_to_i32",
      input = fixtures.c_signature_for_function(
        direct_code_fn,
        { Compiler.Types.Direct(i32), Compiler.Types.Direct(i32) },
        Compiler.Types.DirectResult(i32)),
      input_type = Compiler.C.Signature,
      expected = "int32_t (*)(int32_t, int32_t)",
    },
    {
      name = "void_i32",
      input = fixtures.c_signature_for_function(
        void_code_fn,
        { Compiler.Types.Direct(i32) },
        Compiler.Types.VoidResult()),
      input_type = Compiler.C.Signature,
      expected = "void (*)(int32_t)",
    },
  },
  expected_c = "next/tests/compiler/golden/c_emission/signature_spelling.txt",
}
