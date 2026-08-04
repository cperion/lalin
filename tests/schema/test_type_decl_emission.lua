-- tests/schema/test_type_decl_emission.lua
-- Test: CBackendTypeDecl emission (struct, union, opaque, typedef) via CEmitMachine.
-- Verifies Phase 1 (CBackendTypeDecl → C source text).

package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

require("lalin.schema")
require("lalin.impl.cemit_emit")

local Cemit = require("lalin.schema.cemit")
local C     = require("lalin.schema.c")
local Core  = require("lalin.schema.core")
local Code  = require("lalin.schema.code")
local Graph = require("lalin.schema.graph")
local Lower = require("lalin.schema.lower")
local asdl  = require("lalin.asdl")

-- ============================================================
-- Helpers
-- ============================================================

local i32_ty = C.CBackendScalar(Core.ScalarI32)
local f32_ty = C.CBackendScalar(Core.ScalarF32)
local ptr_ty = C.CBackendDataPtr(nil)

local function field(name, ty, off, sz, al)
  return C.CBackendField(C.CBackendName(name), ty, off, sz, al)
end

local function mk_spine(mod_name)
  local dummy_id = Code.CodeModuleId(mod_name)
  local dummy_origin = Code.CodeOriginUnknown
  local dummy_code_module = Code.CodeModule(dummy_id, {}, {}, {}, {}, {}, {}, dummy_origin)
  local dummy_graph = Graph.CodeGraph(dummy_id, {})
  local target = C.CBackendTarget(C.CBackendC99, C.CBackendHostedNative, 64, 64, C.CBackendLittleEndian, true)
  return Lower.LowerBackSpine(dummy_code_module, dummy_graph, target)
end

local function emit_source(c_unit)
  local spine = mk_spine(c_unit.module_name)
  local machine = Cemit.CEmitMachine(spine, {}, {}, {}, {})
  local artifact = machine:emit_module(c_unit)
  return artifact.source
end

local function assert_contains(source, pattern, label)
  if not source:match(pattern) then
    error("FAIL: " .. (label or pattern) .. " not found in source\nSource:\n" .. source)
  end
  print("PASS: " .. (label or pattern))
end

local function assert_not_contains(source, pattern, label)
  if source:match(pattern) then
    error("FAIL: " .. (label or pattern) .. " should NOT be in source\nSource:\n" .. source)
  end
  print("PASS-NEG: " .. (label or pattern))
end

-- ============================================================
-- Test 1: CBackendStructDecl → typedef struct { fields } name;
-- ============================================================
do
  local my_struct_id  = C.CTypeId("mymod", "Pair")
  local field_x = field("x", i32_ty)
  local field_y = field("y", f32_ty)
  local struct_decl = C.CBackendStructDecl(my_struct_id, {field_x, field_y}, nil, nil)

  local c_unit = C.CBackendUnit(
    "test_struct", mk_spine("test_struct").target,
    {}, {struct_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  assert_contains(source, "typedef struct mymod_Pair {", "struct typedef start")
  assert_contains(source, "int32_t x;", "struct field x")
  assert_contains(source, "float y;", "struct field y")
  assert_contains(source, "} mymod_Pair;", "struct typedef end")
  print("PASS: Test 1 — CBackendStructDecl emits correct typedef struct")
end

-- ============================================================
-- Test 2: CBackendStructDecl with size/align assertions
-- ============================================================
do
  local my_struct_id = C.CTypeId("mymod", "Aligned")
  local field_f = field("val", i32_ty)
  local struct_decl = C.CBackendStructDecl(my_struct_id, {field_f}, 4, 4)

  local c_unit = C.CBackendUnit(
    "test_aligned", mk_spine("test_aligned").target,
    {}, {struct_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  assert_contains(source, "typedef struct mymod_Aligned {", "aligned struct start")
  assert_contains(source, "ml_assert_size_mymod_Aligned", "size assertion")
  assert_contains(source, "ml_assert_align_mymod_Aligned", "align assertion")
  print("PASS: Test 2 — size/align assertions emitted")
end

-- ============================================================
-- Test 3: CBackendUnionDecl → typedef union { fields } name;
-- ============================================================
do
  local my_union_id = C.CTypeId("mymod", "Variant")
  local field_i = field("as_int", i32_ty)
  local field_f = field("as_float", f32_ty)
  local union_decl = C.CBackendUnionDecl(my_union_id, {field_i, field_f}, nil, nil)

  local c_unit = C.CBackendUnit(
    "test_union", mk_spine("test_union").target,
    {}, {union_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  assert_contains(source, "typedef union mymod_Variant {", "union typedef start")
  assert_contains(source, "int32_t as_int;", "union field as_int")
  assert_contains(source, "float as_float;", "union field as_float")
  assert_contains(source, "} mymod_Variant;", "union typedef end")
  print("PASS: Test 3 — CBackendUnionDecl emits correct typedef union")
end

-- ============================================================
-- Test 4: CBackendOpaqueDecl → typedef struct name name;
-- ============================================================
do
  local opaque_id = C.CTypeId("mymod", "Handle")
  local opaque_decl = C.CBackendOpaqueDecl(opaque_id)

  local c_unit = C.CBackendUnit(
    "test_opaque", mk_spine("test_opaque").target,
    {}, {opaque_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  assert_contains(source, "typedef struct mymod_Handle mymod_Handle;", "opaque typedef")
  print("PASS: Test 4 — CBackendOpaqueDecl emits typedef struct name name;")
end

-- ============================================================
-- Test 5: CBackendTypedef → typedef underlying_type name;
-- ============================================================
do
  local typdef_id = C.CTypeId("mymod", "MyInt")
  local typdef_decl = C.CBackendTypedef(typdef_id, i32_ty)

  local c_unit = C.CBackendUnit(
    "test_typedef", mk_spine("test_typedef").target,
    {}, {typdef_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  assert_contains(source, "typedef int32_t mymod_MyInt;", "typedef emission")
  print("PASS: Test 5 — CBackendTypedef emits typedef aliased_type name;")
end

-- ============================================================
-- Test 6: Multiple type decls in emission order
-- ============================================================
do
  local struct_id = C.CTypeId("mymod", "Foo")
  local union_id  = C.CTypeId("mymod", "Bar")
  local struct_decl = C.CBackendStructDecl(struct_id, {field("x", i32_ty)})
  local union_decl  = C.CBackendUnionDecl(union_id, {field("y", f32_ty)})

  local c_unit = C.CBackendUnit(
    "test_multi", mk_spine("test_multi").target,
    {}, {struct_decl, union_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  -- Both types should appear
  assert_contains(source, "mymod_Foo", "multi: struct Foo appears")
  assert_contains(source, "mymod_Bar", "multi: union Bar appears")

  -- Struct should come before union (declaration order)
  local foo_pos = source:find("mymod_Foo")
  local bar_pos = source:find("mymod_Bar")
  if foo_pos and bar_pos and foo_pos >= bar_pos then
    error("FAIL: mymod_Foo should appear before mymod_Bar in emission order")
  end
  print("PASS: Test 6 — multiple type decls emitted in order")
end

-- ============================================================
-- Test 7: Type declarations appear in emit_source output
-- ============================================================
do
  local typ_id = C.CTypeId("mymod", "Dummy")
  local typ_decl = C.CBackendOpaqueDecl(typ_id)

  local c_unit = C.CBackendUnit(
    "test_order", mk_spine("test_order").target,
    {}, {typ_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  -- Type declarations section exists
  assert_contains(source, "/%* type declarations %*/", "type declarations section")
  -- Section appears before any function helpers (none in this test, so just check presence)
  print("PASS: Test 7 — type declarations section emitted")
end

-- ============================================================
-- Test 8: Type declarations in header too
-- ============================================================
do
  local typ_id = C.CTypeId("mymod", "HdrType")
  local typ_decl = C.CBackendOpaqueDecl(typ_id)

  local spine = mk_spine("test_header")
  local c_unit = C.CBackendUnit(
    "test_header", spine.target,
    {}, {typ_decl}, {}, {}, {}, {}
  )

  local machine = Cemit.CEmitMachine(spine, {}, {}, {}, {})
  local artifact = machine:emit_module(c_unit)
  local header = artifact.header

  assert_contains(header, "/%* type declarations %*/", "header: type declarations section")
  assert_contains(header, "typedef struct mymod_HdrType mymod_HdrType;", "header: opaque typedef")
  print("PASS: Test 8 — type declarations in header")
end

-- ============================================================
-- Test 9: CBackendNamed uses module_prefix in type name
-- ============================================================
do
  local named_ty = C.CBackendNamed(C.CTypeId("mymod", "Pair"))
  local emitted = named_ty:c_emit_type()
  assert(emitted == "mymod_Pair", "CBackendNamed emits module_name_type_name, got: " .. emitted)

  local decl = named_ty:c_emit_decl("p")
  assert(decl == "mymod_Pair p", "c_emit_decl on named: " .. decl)
  print("PASS: Test 9 — CBackendNamed uses module prefix")
end

-- ============================================================
-- Test 10: Field with alignment hint
-- ============================================================
do
  local cfield = C.CBackendField(C.CBackendName("x"), i32_ty, nil, nil, 8)
  local decl = cfield:c_emit_field_decl()
  assert_contains(decl, "__attribute__", "field with align 8 has attribute")
  assert_contains(decl, "aligned%(8%)", "field with align 8 has aligned(8)")
  print("PASS: Test 10 — field with alignment emits attribute")
end

-- ============================================================
-- Test 11: Struct with Named field type (CBackendNamed → full name)
-- ============================================================
do
  local inner_id = C.CTypeId("mymod", "Inner")
  local inner_decl = C.CBackendOpaqueDecl(inner_id)

  local outer_id = C.CTypeId("mymod", "Outer")
  local inner_named = C.CBackendNamed(inner_id)
  -- Field of type Inner (pointer)
  local field_inner = field("inner", C.CBackendDataPtr(inner_named))
  local outer_decl = C.CBackendStructDecl(outer_id, {field_inner})

  local c_unit = C.CBackendUnit(
    "test_struct_named", mk_spine("test_struct_named").target,
    {}, {inner_decl, outer_decl}, {}, {}, {}, {}
  )

  local source = emit_source(c_unit)
  assert_contains(source, "mymod_Inner%* inner;", "struct field uses full name for Inner")
  -- inner opaque decl should appear before outer struct
  local inner_pos = source:find("mymod_Inner")
  local outer_pos = source:find("mymod_Outer")
  if inner_pos and outer_pos and inner_pos > outer_pos then
    error("FAIL: mymod_Inner should appear before mymod_Outer (dependency ordering)")
  end
  print("PASS: Test 11 — struct with Named field type uses module-prefixed name")
end

print("\n=== All type_decl_emission tests passed ===")
