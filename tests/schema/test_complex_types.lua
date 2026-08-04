package.path = "tests/?.lua;./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

----------------------------------------------------------------------
-- test_complex_types.lua
-- Verifies Phase 2: CodeType → CBackendType conversions for
-- CodeTyNamed, CodeTyArray, CodeTyCodePtr, CodeTySlice, CodeTyView
----------------------------------------------------------------------

require("lalin.schema")
local Type  = require("lalin.schema.type")
local Code = require("lalin.schema.code")
local C    = require("lalin.schema.c")
local Core = require("lalin.schema.core")
local asdl = require("lalin.asdl")

require("lalin.impl.lower_emit_c.code_to_c")

----------------------------------------------------------------------
-- Test 1: CodeTyNamed → CBackendNamed
----------------------------------------------------------------------
print("Test 1: CodeTyNamed → CBackendNamed")
local named_ty = Code.CodeTyNamed("mymod", "MyStruct", Type.TScalar(Core.ScalarI32))
local cty1 = named_ty:code_to_c_backend_type()
assert(asdl.classof(cty1) == C.CBackendNamed,
  "expected CBackendNamed, got " .. tostring(asdl.classof(cty1)))
assert(cty1.id.module_name == "mymod", "got module_name=" .. cty1.id.module_name)
assert(cty1.id.spelling == "MyStruct", "got spelling=" .. cty1.id.spelling)
print("  PASS: CBackendNamed { module_name='mymod', spelling='MyStruct' }")

----------------------------------------------------------------------
-- Test 2: CodeTyArray → CBackendArray
----------------------------------------------------------------------
print("Test 2: CodeTyArray → CBackendArray")
local i32_ty = Code.CodeTyInt(32, Code.CodeSigned)
local arr_ty = Code.CodeTyArray(i32_ty, 10)
local cty2 = arr_ty:code_to_c_backend_type()
assert(asdl.classof(cty2) == C.CBackendArray,
  "expected CBackendArray, got " .. tostring(asdl.classof(cty2)))
assert(cty2.count == 10, "expected count=10, got " .. tostring(cty2.count))
assert(asdl.classof(cty2.elem) == C.CBackendScalar,
  "expected elem=Scalar, got " .. tostring(asdl.classof(cty2.elem)))
print("  PASS: CBackendArray { count=10, elem=ScalarI32 }")

----------------------------------------------------------------------
-- Test 3: CodeTyCodePtr → CBackendCodePtr
----------------------------------------------------------------------
print("Test 3: CodeTyCodePtr → CBackendCodePtr")
local sig_id = Code.CodeSigId("my_sig")
local codeptr_ty = Code.CodeTyCodePtr(sig_id)
local cty3 = codeptr_ty:code_to_c_backend_type()
assert(asdl.classof(cty3) == C.CBackendCodePtr,
  "expected CBackendCodePtr, got " .. tostring(asdl.classof(cty3)))
assert(cty3.sig.text == "my_sig", "got sig=" .. cty3.sig.text)
print("  PASS: CBackendCodePtr { sig='my_sig' }")

----------------------------------------------------------------------
-- Test 4: CodeTySlice → CBackendSliceDescriptor
----------------------------------------------------------------------
print("Test 4: CodeTySlice → CBackendSliceDescriptor")
local slice_ty = Code.CodeTySlice(i32_ty)
local cty4 = slice_ty:code_to_c_backend_type()
assert(asdl.classof(cty4) == C.CBackendSliceDescriptor,
  "expected CBackendSliceDescriptor, got " .. tostring(asdl.classof(cty4)))
assert(asdl.classof(cty4.elem) == C.CBackendScalar,
  "expected elem=Scalar, got " .. tostring(asdl.classof(cty4.elem)))
-- Slice descriptor should be a pointer type
assert(cty4:code_to_c_is_pointer_type(),
  "expected slice descriptor to be a pointer type")
print("  PASS: CBackendSliceDescriptor { elem=ScalarI32, is_pointer=true }")

----------------------------------------------------------------------
-- Test 5: CodeTyView → CBackendViewDescriptor
----------------------------------------------------------------------
print("Test 5: CodeTyView → CBackendViewDescriptor")
local f64_ty = Code.CodeTyFloat(64)
local view_ty = Code.CodeTyView(f64_ty)
local cty5 = view_ty:code_to_c_backend_type()
assert(asdl.classof(cty5) == C.CBackendViewDescriptor,
  "expected CBackendViewDescriptor, got " .. tostring(asdl.classof(cty5)))
assert(asdl.classof(cty5.elem) == C.CBackendScalar,
  "expected elem=Scalar, got " .. tostring(asdl.classof(cty5.elem)))
-- View descriptor should be a pointer type
assert(cty5:code_to_c_is_pointer_type(),
  "expected view descriptor to be a pointer type")
print("  PASS: CBackendViewDescriptor { elem=ScalarF64, is_pointer=true }")

----------------------------------------------------------------------
-- Test 6: CBackendType name queries work on new types
----------------------------------------------------------------------
print("Test 6: code_to_c_type_name queries")
assert(Code.CodeTyNamed("m", "Foo", Type.TScalar(Core.ScalarI32)):code_to_c_type_name() == "Foo",
  "named type name should be 'Foo'")
assert(Code.CodeTyArray(i32_ty, 4):code_to_c_type_name() == "int32_t[4]",
  "array name: " .. Code.CodeTyArray(i32_ty, 4):code_to_c_type_name())
assert(Code.CodeTySlice(i32_ty):code_to_c_type_name() == "slice_t",
  "slice name: " .. Code.CodeTySlice(i32_ty):code_to_c_type_name())
assert(Code.CodeTyView(f64_ty):code_to_c_type_name() == "view_t",
  "view name: " .. Code.CodeTyView(f64_ty):code_to_c_type_name())
print("  PASS: all code_to_c_type_name queries correct")

print("\n=== All Phase 2 complex type tests passed ===")
