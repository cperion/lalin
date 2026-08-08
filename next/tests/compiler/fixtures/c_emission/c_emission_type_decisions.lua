local Compiler = require("lalin.compiler.schema")
local fixtures = require("compiler.support.fixtures")

local function emit(leaf, input, expected)
  return { leaf = leaf, status = "EMIT", input = input, input_type = Compiler.C.Type, expected = expected }
end

local function reject(leaf, reason)
  return { leaf = leaf, status = "REJECT", reason = reason }
end

local decisions = {
  emit("Types.Type.Bool", fixtures.c_type(fixtures.bool(), 1, 1), "bool"),
  emit("Types.Type.Float", fixtures.c_type(fixtures.float(32), 4, 4), "float"),
  emit("Types.Type.Index", fixtures.c_type(fixtures.index(), 8, 8), "int64_t"),
  emit("Types.Type.ImportedC", fixtures.c_type(fixtures.imported_c("intptr_t"), 8, 8), "intptr_t"),
  emit("Types.Type.Pointer", fixtures.c_type(fixtures.pointer(fixtures.i32()), 8, 8), "int32_t*"),
  emit("Types.Type.RawPointer", fixtures.c_type(fixtures.raw_pointer(), 8, 8), "void*"),
  emit("Types.Type.SignedInteger", fixtures.c_i32_type(), "int32_t"),
  emit("Types.Type.UnsignedInteger", fixtures.c_u32_type(), "uint32_t"),
  emit("Types.Type.Void", fixtures.c_void_type(), "void"),

  reject("Types.Type.Array", "array declarator spelling requires layout/extent policy fixture"),
  reject("Types.Type.Closure", "closure representation is pinned by semantic_to_code and target_layout_abi"),
  reject("Types.Type.Function", "function type spelling belongs to C.Signature, not C.Type"),
  reject("Types.Type.Handle", "handle representation is pinned by target_layout_abi"),
  reject("Types.Type.Lease", "ownership erasure must remove lease wrapper before C emission"),
  reject("Types.Type.Owned", "ownership erasure must remove owned wrapper before C emission"),
  reject("Types.Type.Qualified", "access qualifiers are parameter/place facts, not standalone C type spelling"),
  reject("Types.Type.Slice", "slice struct spelling must be pinned before C emission"),
  reject("Types.Type.Struct", "struct layout/name spelling is pinned by target_layout_abi"),
  reject("Types.Type.Union", "union layout/name spelling is pinned by target_layout_abi"),
  reject("Types.Type.UniqueStruct", "unique struct layout/name spelling is pinned by target_layout_abi"),
  reject("Types.Type.View", "view struct spelling must be pinned before C emission"),
}

local leaves = {}
for _, decision in ipairs(decisions) do leaves[#leaves + 1] = decision.leaf end
table.sort(leaves)

return {
  key = "c_emission_type_decisions",
  boundary = "C.Type semantic Types.Type -> C type spelling or typed rejection",
  leaves = leaves,
  decisions = decisions,
  expected_c = "next/tests/compiler/golden/c_emission/type_decisions.txt",
}
