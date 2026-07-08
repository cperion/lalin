package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")

-- Initialize schema context
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")

local Core  = require("lalin.schema_v2.core")
local Code  = require("lalin.schema_v2.code")
local Sem   = require("lalin.schema_v2.sem")
local Type  = require("lalin.schema_v2.type")
local C     = require("lalin.schema_v2.c")

local function assert_ok(cond, msg)
  if not cond then error("FAIL: " .. tostring(msg), 2) end
end

local function assert_eq(a, b, msg)
  if a ~= b then error("FAIL: " .. (msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end

local function make_vid(text) return Code.CodeValueId(text) end
local function make_lid(text) return Code.CodeLocalId(text) end

print("=== test_aggregate_lowering ===")

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function new_lowered()
  return { stmts = {}, helpers = {}, locals = {}, sigs = {} }
end

----------------------------------------------------------------------
-- Test 1: CodeInstAggregate (struct init with named fields)
----------------------------------------------------------------------
print("\nTest 1: CodeInstAggregate")
do
  local dst = make_vid("agg1")
  local struct_ty = Code.CodeTyNamed("mymod", "MyStruct", Type.TScalar(Core.ScalarI32))
  local field1 = Sem.FieldByName("x", Type.TScalar(Core.ScalarI32))
  local field2 = Sem.FieldByName("y", Type.TScalar(Core.ScalarI32))
  local fv1 = Code.CodeFieldValue(field1, make_vid("v1"))
  local fv2 = Code.CodeFieldValue(field2, make_vid("v2"))

  local agg_op = Code.CodeInstAggregate(dst, struct_ty, { fv1, fv2 })
  local inst = Code.CodeInst(Code.CodeInstId("inst_agg"), agg_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "aggregate: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAggregateInit, "aggregate: CBackendAggregateInit")
  assert_eq(#stmt.fields, 2, "aggregate: 2 fields")
  assert_eq(stmt.fields[1].field.text, "x", "aggregate: field[1] = x")
  assert_eq(stmt.fields[2].field.text, "y", "aggregate: field[2] = y")
  print("  PASS: CodeInstAggregate → CBackendAggregateInit (2 fields)")
end

----------------------------------------------------------------------
-- Test 2: CodeInstArray (array init with indexed elements)
----------------------------------------------------------------------
print("\nTest 2: CodeInstArray")
do
  local dst = make_vid("arr1")
  local arr_ty = Code.CodeTyArray(Code.CodeTyInt(32, Code.CodeSigned), 3)
  local ev1 = Code.CodeArrayValue(0, make_vid("v1"))
  local ev2 = Code.CodeArrayValue(1, make_vid("v2"))
  local ev3 = Code.CodeArrayValue(2, make_vid("v3"))

  local arr_op = Code.CodeInstArray(dst, arr_ty, { ev1, ev2, ev3 })
  local inst = Code.CodeInst(Code.CodeInstId("inst_arr"), arr_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "array: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendArrayInit, "array: CBackendArrayInit")
  assert_eq(#stmt.elems, 3, "array: 3 elems")
  assert_eq(stmt.elems[1].index, 0, "array: elem[1] idx=0")
  assert_eq(stmt.elems[2].index, 1, "array: elem[2] idx=1")
  assert_eq(stmt.elems[3].index, 2, "array: elem[3] idx=2")
  print("  PASS: CodeInstArray → CBackendArrayInit (3 elems)")
end

----------------------------------------------------------------------
-- Test 3: CodeInstViewMake
----------------------------------------------------------------------
print("\nTest 3: CodeInstViewMake")
do
  local dst = make_vid("v1")
  local elem_ty = Code.CodeTyInt(32, Code.CodeSigned)
  local data = make_vid("ptr")
  local len = make_vid("n")
  local stride = make_vid("s")

  local view_op = Code.CodeInstViewMake(dst, elem_ty, data, len, stride)
  local inst = Code.CodeInst(Code.CodeInstId("inst_view"), view_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "view_make: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAggregateInit, "view_make: AggregateInit")
  assert_eq(asdl.classof(stmt.ty), C.CBackendViewDescriptor, "view_make: ViewDescriptor type")
  assert_eq(#stmt.fields, 3, "view_make: 3 fields (data, len, stride)")
  assert_eq(stmt.fields[1].field.text, "data", "view_make: field[1] = data")
  assert_eq(stmt.fields[2].field.text, "len", "view_make: field[2] = len")
  assert_eq(stmt.fields[3].field.text, "stride", "view_make: field[3] = stride")
  print("  PASS: CodeInstViewMake → CBackendAggregateInit (ViewDescriptor)")
end

----------------------------------------------------------------------
-- Test 4: CodeInstViewData
----------------------------------------------------------------------
print("\nTest 4: CodeInstViewData")
do
  local dst = make_vid("vdata")
  local view = make_vid("myview")

  local vdata_op = Code.CodeInstViewData(dst, view)
  local inst = Code.CodeInst(Code.CodeInstId("inst_vdata"), vdata_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "view_data: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "view_data: PlaceLoad")
  local field = stmt.place
  assert_eq(asdl.classof(field), C.CBackendPlaceField, "view_data: field access")
  assert_eq(field.field.text, "data", "view_data: data field")
  print("  PASS: CodeInstViewData → CBackendPlaceLoad (field=date)")
end

----------------------------------------------------------------------
-- Test 5: CodeInstViewLen
----------------------------------------------------------------------
print("\nTest 5: CodeInstViewLen")
do
  local dst = make_vid("vlen")
  local view = make_vid("myview")

  local vlen_op = Code.CodeInstViewLen(dst, view)
  local inst = Code.CodeInst(Code.CodeInstId("inst_vlen"), vlen_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "view_len: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "view_len: PlaceLoad")
  local field = stmt.place
  assert_eq(field.field.text, "len", "view_len: len field")
  print("  PASS: CodeInstViewLen → CBackendPlaceLoad (field=len)")
end

----------------------------------------------------------------------
-- Test 6: CodeInstViewStride
----------------------------------------------------------------------
print("\nTest 6: CodeInstViewStride")
do
  local dst = make_vid("vstride")
  local view = make_vid("myview")

  local vs_op = Code.CodeInstViewStride(dst, view)
  local inst = Code.CodeInst(Code.CodeInstId("inst_vs"), vs_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "view_stride: 1 stmt")
  local stmt = lowered.stmts[1]
  local field = stmt.place
  assert_eq(field.field.text, "stride", "view_stride: stride field")
  print("  PASS: CodeInstViewStride → CBackendPlaceLoad (field=stride)")
end

----------------------------------------------------------------------
-- Test 7: CodeInstSliceMake
----------------------------------------------------------------------
print("\nTest 7: CodeInstSliceMake")
do
  local dst = make_vid("s1")
  local elem_ty = Code.CodeTyFloat(64)
  local data = make_vid("ptr")
  local len = make_vid("n")

  local slice_op = Code.CodeInstSliceMake(dst, elem_ty, data, len)
  local inst = Code.CodeInst(Code.CodeInstId("inst_slice"), slice_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "slice_make: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAggregateInit, "slice_make: AggregateInit")
  assert_eq(asdl.classof(stmt.ty), C.CBackendSliceDescriptor, "slice_make: SliceDescriptor type")
  assert_eq(#stmt.fields, 2, "slice_make: 2 fields (data, len)")
  assert_eq(stmt.fields[1].field.text, "data", "slice_make: field[1] = data")
  assert_eq(stmt.fields[2].field.text, "len", "slice_make: field[2] = len")
  print("  PASS: CodeInstSliceMake → CBackendAggregateInit (SliceDescriptor)")
end

----------------------------------------------------------------------
-- Test 8: CodeInstSliceData
----------------------------------------------------------------------
print("\nTest 8: CodeInstSliceData")
do
  local dst = make_vid("sdata")
  local slice = make_vid("myslice")

  local sdata_op = Code.CodeInstSliceData(dst, slice)
  local inst = Code.CodeInst(Code.CodeInstId("inst_sdata"), sdata_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "slice_data: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "slice_data: PlaceLoad")
  local field = stmt.place
  assert_eq(field.field.text, "data", "slice_data: data field")
  print("  PASS: CodeInstSliceData → CBackendPlaceLoad (field=data)")
end

----------------------------------------------------------------------
-- Test 9: CodeInstSliceLen
----------------------------------------------------------------------
print("\nTest 9: CodeInstSliceLen")
do
  local dst = make_vid("slen")
  local slice = make_vid("myslice")

  local slen_op = Code.CodeInstSliceLen(dst, slice)
  local inst = Code.CodeInst(Code.CodeInstId("inst_slen"), slen_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "slice_len: 1 stmt")
  local stmt = lowered.stmts[1]
  local field = stmt.place
  assert_eq(field.field.text, "len", "slice_len: len field")
  print("  PASS: CodeInstSliceLen → CBackendPlaceLoad (field=len)")
end

----------------------------------------------------------------------
-- Test 10: CodeInstByteSpanMake
----------------------------------------------------------------------
print("\nTest 10: CodeInstByteSpanMake")
do
  local dst = make_vid("bs1")
  local data = make_vid("buf")
  local len = make_vid("n")

  local bs_op = Code.CodeInstByteSpanMake(dst, data, len)
  local inst = Code.CodeInst(Code.CodeInstId("inst_bs"), bs_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "bytespan_make: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAggregateInit, "bytespan_make: AggregateInit")
  assert_eq(#stmt.fields, 2, "bytespan_make: 2 fields")
  assert_eq(stmt.fields[1].field.text, "data", "bytespan_make: field[1] = data")
  assert_eq(stmt.fields[2].field.text, "len", "bytespan_make: field[2] = len")
  print("  PASS: CodeInstByteSpanMake → CBackendAggregateInit")
end

----------------------------------------------------------------------
-- Test 11: CodeInstByteSpanData
----------------------------------------------------------------------
print("\nTest 11: CodeInstByteSpanData")
do
  local dst = make_vid("bsdata")
  local span = make_vid("myspan")

  local bsd_op = Code.CodeInstByteSpanData(dst, span)
  local inst = Code.CodeInst(Code.CodeInstId("inst_bsd"), bsd_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "bytespan_data: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "bytespan_data: PlaceLoad")
  local field = stmt.place
  assert_eq(field.field.text, "data", "bytespan_data: data field")
  -- Check data type is uint8_t*
  assert_eq(asdl.classof(field.ty), C.CBackendDataPtr, "bytespan_data: DataPtr type")
  print("  PASS: CodeInstByteSpanData → CBackendPlaceLoad (field=data)")
end

----------------------------------------------------------------------
-- Test 12: CodeInstByteSpanLen
----------------------------------------------------------------------
print("\nTest 12: CodeInstByteSpanLen")
do
  local dst = make_vid("bslen")
  local span = make_vid("myspan")

  local bsl_op = Code.CodeInstByteSpanLen(dst, span)
  local inst = Code.CodeInst(Code.CodeInstId("inst_bsl"), bsl_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "bytespan_len: 1 stmt")
  local stmt = lowered.stmts[1]
  local field = stmt.place
  assert_eq(field.field.text, "len", "bytespan_len: len field")
  print("  PASS: CodeInstByteSpanLen → CBackendPlaceLoad (field=len)")
end

----------------------------------------------------------------------
-- Test 13: CodeInstClosure
----------------------------------------------------------------------
print("\nTest 13: CodeInstClosure")
do
  local dst = make_vid("c1")
  local fn_vid = make_vid("fn_ptr")
  local ctx_vid = make_vid("env_ptr")
  local sig_id = Code.CodeSigId("my_closure_sig")
  local closure_ty = Code.CodeTyClosure(sig_id)

  local closure_op = Code.CodeInstClosure(dst, closure_ty, fn_vid, ctx_vid, sig_id)
  local inst = Code.CodeInst(Code.CodeInstId("inst_closure"), closure_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "closure: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAggregateInit, "closure: AggregateInit")
  assert_eq(#stmt.fields, 2, "closure: 2 fields (fn, ctx)")
  assert_eq(stmt.fields[1].field.text, "fn", "closure: field[1] = fn")
  assert_eq(stmt.fields[2].field.text, "ctx", "closure: field[2] = ctx")
  print("  PASS: CodeInstClosure → CBackendAggregateInit (fn + ctx)")
end

----------------------------------------------------------------------
-- Test 14: CodeInstVariantCtor (with payload)
----------------------------------------------------------------------
print("\nTest 14: CodeInstVariantCtor (with payload)")
do
  local dst = make_vid("v1")
  local owner_ty = Code.CodeTyNamed("mymod", "MyVariant", Type.TScalar(Core.ScalarI32))
  local payload_ty = Code.CodeTyInt(32, Code.CodeSigned)
  local variant_ref = Code.CodeVariantRef(owner_ty, "Some", 0, payload_ty)
  local var_ty = Code.CodeTyNamed("mymod", "MyVariant", Type.TScalar(Core.ScalarI32))

  local vctor_op = Code.CodeInstVariantCtor(dst, var_ty, variant_ref, make_vid("p1"))
  local inst = Code.CodeInst(Code.CodeInstId("inst_vctor"), vctor_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  -- Expect: 1 aggregate init (tag) + 1 place store (payload) = 2 stmts
  assert_eq(#lowered.stmts, 2, "variant_ctor: 2 stmts (tag + payload)")
  -- First stmt is tag aggregate init
  local tag_stmt = lowered.stmts[1]
  assert_eq(asdl.classof(tag_stmt), C.CBackendAggregateInit, "variant_ctor: stmt1 = AggregateInit (tag)")
  assert_eq(#tag_stmt.fields, 1, "variant_ctor: 1 field in tag init")
  assert_eq(tag_stmt.fields[1].field.text, "__tag", "variant_ctor: __tag field")
  -- Second stmt is payload store
  local pl_stmt = lowered.stmts[2]
  assert_eq(asdl.classof(pl_stmt), C.CBackendPlaceStore, "variant_ctor: stmt2 = PlaceStore (payload)")
  -- Check the variant-specific place path: __payload.Some
  local variant_place = pl_stmt.place
  assert_eq(asdl.classof(variant_place), C.CBackendPlaceField, "variant_ctor: payload is PlaceField")
  assert_eq(variant_place.field.text, "Some", "variant_ctor: payload field name = Some")
  print("  PASS: CodeInstVariantCtor (tag + payload)")
end

----------------------------------------------------------------------
-- Test 15: CodeInstVariantCtor (no payload)
----------------------------------------------------------------------
print("\nTest 15: CodeInstVariantCtor (no payload)")
do
  local dst = make_vid("v2")
  local owner_ty = Code.CodeTyNamed("mymod", "MyVariant", Type.TScalar(Core.ScalarI32))
  local variant_ref = Code.CodeVariantRef(owner_ty, "None", 1, nil)

  local vctor_op = Code.CodeInstVariantCtor(dst, owner_ty, variant_ref, nil)
  local inst = Code.CodeInst(Code.CodeInstId("inst_vctor_none"), vctor_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  -- No payload, so only 1 stmt (tag init)
  assert_eq(#lowered.stmts, 1, "variant_ctor_none: 1 stmt (tag only)")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAggregateInit, "variant_ctor_none: AggregateInit")
  assert_eq(stmt.fields[1].field.text, "__tag", "variant_ctor_none: __tag field")
  print("  PASS: CodeInstVariantCtor (no payload, tag only)")
end

----------------------------------------------------------------------
-- Test 16: CodeInstVariantTag
----------------------------------------------------------------------
print("\nTest 16: CodeInstVariantTag")
do
  local dst = make_vid("tag1")
  local tag_ty = Code.CodeTyInt(32, Code.CodeUnsigned)
  local value = make_vid("variant_val")

  local vtag_op = Code.CodeInstVariantTag(dst, tag_ty, value)
  local inst = Code.CodeInst(Code.CodeInstId("inst_vtag"), vtag_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  lowered.value_types = { [value.text] = Code.CodeTyNamed("mymod", "MyVariant", Type.TScalar(Core.ScalarI32)) }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "variant_tag: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "variant_tag: PlaceLoad")
  local field = stmt.place
  assert_eq(asdl.classof(field), C.CBackendPlaceField, "variant_tag: field access")
  assert_eq(field.field.text, "__tag", "variant_tag: __tag field")
  print("  PASS: CodeInstVariantTag → CBackendPlaceLoad (__tag)")
end

----------------------------------------------------------------------
-- Test 17: CodeInstVariantPayload
----------------------------------------------------------------------
print("\nTest 17: CodeInstVariantPayload")
do
  local dst = make_vid("pl1")
  local owner_ty = Code.CodeTyNamed("mymod", "MyVariant", Type.TScalar(Core.ScalarI32))
  local payload_ty = Code.CodeTyInt(32, Code.CodeSigned)
  local variant_ref = Code.CodeVariantRef(owner_ty, "Some", 0, payload_ty)
  local value = make_vid("variant_val")

  local vpl_op = Code.CodeInstVariantPayload(dst, variant_ref, value)
  local inst = Code.CodeInst(Code.CodeInstId("inst_vpl"), vpl_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "variant_payload: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "variant_payload: PlaceLoad")
  -- Should navigate to __payload.Some
  local variant_place = stmt.place
  assert_eq(asdl.classof(variant_place), C.CBackendPlaceField, "variant_payload: PlaceField")
  assert_eq(variant_place.field.text, "Some", "variant_payload: field name = Some")
  print("  PASS: CodeInstVariantPayload → CBackendPlaceLoad (__payload.Some)")
end

----------------------------------------------------------------------
-- Test 18: CodeInstAtomicLoad (via deref place)
----------------------------------------------------------------------
print("\nTest 18: CodeInstAtomicLoad (deref place)")
do
  local dst = make_vid("a1")
  local addr = make_vid("atomic_ptr")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local deref_place = Code.CodePlaceDeref(addr, ty, 4)
  local access = Code.CodeMemoryAccess(
    Code.CodeMemoryRead, ty, 4,
    Code.CodeMayTrap, false, Core.AtomicSeqCst
  )

  local aload_op = Code.CodeInstAtomicLoad(dst, deref_place, access, Core.AtomicSeqCst)
  local inst = Code.CodeInst(Code.CodeInstId("inst_aload"), aload_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.helpers, 1, "atomic_load: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperAtomicLoad, "atomic_load: AtomicLoad spec")
  assert_eq(#lowered.stmts, 1, "atomic_load: 1 stmt (helper call)")
  assert_eq(asdl.classof(lowered.stmts[1]), C.CBackendHelperCall, "atomic_load: HelperCall")
  print("  PASS: CodeInstAtomicLoad (deref) → CBackendHelperCall")
end

----------------------------------------------------------------------
-- Test 19: CodeInstAtomicStore (via deref place)
----------------------------------------------------------------------
print("\nTest 19: CodeInstAtomicStore (deref place)")
do
  local addr = make_vid("atomic_ptr")
  local val = make_vid("new_val")
  local ty = Code.CodeTyInt(64, Code.CodeSigned)
  local deref_place = Code.CodePlaceDeref(addr, ty, 8)
  local access = Code.CodeMemoryAccess(
    Code.CodeMemoryWrite, ty, 8,
    Code.CodeMayTrap, false, Core.AtomicSeqCst
  )

  local astore_op = Code.CodeInstAtomicStore(deref_place, val, access, Core.AtomicSeqCst)
  local inst = Code.CodeInst(Code.CodeInstId("inst_astore"), astore_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.helpers, 1, "atomic_store: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperAtomicStore, "atomic_store: AtomicStore spec")
  assert_eq(#lowered.stmts, 1, "atomic_store: 1 stmt")
  assert_eq(asdl.classof(lowered.stmts[1]), C.CBackendHelperCall, "atomic_store: HelperCall")
  -- The helper call should have no dst (void)
  assert_eq(lowered.stmts[1].dst, nil, "atomic_store: no dst on helper call")
  print("  PASS: CodeInstAtomicStore (deref) → CBackendHelperCall")
end

----------------------------------------------------------------------
-- Test 20: CodeInstAtomicRmw (via deref place)
----------------------------------------------------------------------
print("\nTest 20: CodeInstAtomicRmw (deref place)")
do
  local dst = make_vid("a2")
  local addr = make_vid("atomic_ptr")
  local val = make_vid("delta")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local deref_place = Code.CodePlaceDeref(addr, ty, 4)
  local access = Code.CodeMemoryAccess(
    Code.CodeMemoryReadWrite, ty, 4,
    Code.CodeMayTrap, false, Core.AtomicSeqCst
  )

  local armw_op = Code.CodeInstAtomicRmw(dst, Core.AtomicRmwAdd, deref_place, val, access, Core.AtomicSeqCst)
  local inst = Code.CodeInst(Code.CodeInstId("inst_armw"), armw_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.helpers, 1, "atomic_rmw: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperAtomicRmw, "atomic_rmw: AtomicRmw spec")
  assert_eq(helper.spec.op, Core.AtomicRmwAdd, "atomic_rmw: Add op")
  assert_eq(#lowered.stmts, 1, "atomic_rmw: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendHelperCall, "atomic_rmw: HelperCall")
  -- Should have dst (returns old value)
  assert_ok(stmt.dst ~= nil, "atomic_rmw: has dst")
  print("  PASS: CodeInstAtomicRmw (deref) → CBackendHelperCall")
end

----------------------------------------------------------------------
-- Test 21: CodeInstAtomicCas (via deref place)
----------------------------------------------------------------------
print("\nTest 21: CodeInstAtomicCas (deref place)")
do
  local dst = make_vid("a3")
  local addr = make_vid("atomic_ptr")
  local expected = make_vid("old_val")
  local replacement = make_vid("new_val")
  local ty = Code.CodeTyInt(32, Code.CodeUnsigned)
  local deref_place = Code.CodePlaceDeref(addr, ty, 4)
  local access = Code.CodeMemoryAccess(
    Code.CodeMemoryReadWrite, ty, 4,
    Code.CodeMayTrap, false, Core.AtomicSeqCst
  )

  local acas_op = Code.CodeInstAtomicCas(dst, deref_place, expected, replacement, access, Core.AtomicSeqCst)
  local inst = Code.CodeInst(Code.CodeInstId("inst_acas"), acas_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.helpers, 1, "atomic_cas: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperAtomicCas, "atomic_cas: AtomicCas spec")
  -- CAS needs expected-address temp local + helper call (+ possibly addr temp for non-deref)
  -- For deref: 1 assign (expected addr) + 1 helper call = 2 stmts
  -- Plus 1 local for expected_addr
  assert_ok(#lowered.stmts >= 2, "atomic_cas: at least 2 stmts")
  assert_ok(#lowered.locals >= 1, "atomic_cas: at least 1 local")
  -- Helper call should be the last stmt
  local last_stmt = lowered.stmts[#lowered.stmts]
  assert_eq(asdl.classof(last_stmt), C.CBackendHelperCall, "atomic_cas: last stmt is HelperCall")
  assert_eq(#last_stmt.args, 3, "atomic_cas: 3 args (addr, expected_addr, replacement)")
  print("  PASS: CodeInstAtomicCas (deref) → CBackendHelperCall")
end

----------------------------------------------------------------------
-- Test 22: CodeInstAtomicFence
----------------------------------------------------------------------
print("\nTest 22: CodeInstAtomicFence")
do
  local afence_op = Code.CodeInstAtomicFence(Core.AtomicSeqCst)
  local inst = Code.CodeInst(Code.CodeInstId("inst_afence"), afence_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.helpers, 1, "atomic_fence: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperAtomicFence, "atomic_fence: AtomicFence spec")
  assert_eq(helper.spec.ordering, Core.AtomicSeqCst, "atomic_fence: SeqCst ordering")
  assert_eq(#lowered.stmts, 1, "atomic_fence: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendHelperCall, "atomic_fence: HelperCall")
  assert_eq(stmt.dst, nil, "atomic_fence: no dst")
  print("  PASS: CodeInstAtomicFence → CBackendHelperCall (void)")
end

----------------------------------------------------------------------
-- Test 23: CodeInstAtomicLoad (non-deref place — needs addr temp)
----------------------------------------------------------------------
print("\nTest 23: CodeInstAtomicLoad (non-deref place)")
do
  local dst = make_vid("a4")
  local lid = make_lid("my_int")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local local_place = Code.CodePlaceLocal(lid, ty)
  local access = Code.CodeMemoryAccess(
    Code.CodeMemoryRead, ty, 4,
    Code.CodeMayTrap, false, Core.AtomicSeqCst
  )

  local aload_op = Code.CodeInstAtomicLoad(dst, local_place, access, Core.AtomicSeqCst)
  local inst = Code.CodeInst(Code.CodeInstId("inst_aload2"), aload_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.helpers, 1, "atomic_load_local: 1 helper")
  -- Non-deref: needs addr temp assign + helper call = 2 stmts, 1 local
  assert_ok(#lowered.stmts >= 2, "atomic_load_local: at least 2 stmts (addr assign + helper call)")
  assert_ok(#lowered.locals >= 1, "atomic_load_local: at least 1 local (addr temp)")
  -- First stmt should be address-of assign
  local first_stmt = lowered.stmts[1]
  assert_eq(asdl.classof(first_stmt), C.CBackendAssign, "atomic_load_local: addr assign")
  -- Last stmt should be helper call
  local last_stmt = lowered.stmts[#lowered.stmts]
  assert_eq(asdl.classof(last_stmt), C.CBackendHelperCall, "atomic_load_local: helper call")
  print("  PASS: CodeInstAtomicLoad (local place) → addr assign + HelperCall")
end

----------------------------------------------------------------------
-- Test 24: Aggregate with empty fields
----------------------------------------------------------------------
print("\nTest 24: CodeInstAggregate (empty fields)")
do
  local dst = make_vid("empty_agg")
  local struct_ty = Code.CodeTyNamed("mymod", "EmptyStruct", Type.TScalar(Core.ScalarI32))

  local agg_op = Code.CodeInstAggregate(dst, struct_ty, {})
  local inst = Code.CodeInst(Code.CodeInstId("inst_empty"), agg_op, Code.CodeOrigin("test"))
  local lowered = new_lowered()
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "empty_agg: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAggregateInit, "empty_agg: AggregateInit")
  assert_eq(#stmt.fields, 0, "empty_agg: 0 fields")
  print("  PASS: CodeInstAggregate (empty) → CBackendAggregateInit (0 fields)")
end

print("\n=== ALL TESTS PASSED ===")
