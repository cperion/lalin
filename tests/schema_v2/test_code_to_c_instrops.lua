package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")

-- Initialize schema context
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")

local Core  = require("lalin.schema_v2.core")
local Code  = require("lalin.schema_v2.code")
local C     = require("lalin.schema_v2.c")

local function assert_ok(cond, msg)
  if not cond then error("FAIL: " .. tostring(msg), 2) end
end

local function assert_eq(a, b, msg)
  if a ~= b then error("FAIL: " .. (msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2) end
end

local function make_vid(text) return Code.CodeValueId(text) end
local function make_lid(text) return Code.CodeLocalId(text) end

print("=== test_code_to_c_instrops ===")

----------------------------------------------------------------------
-- Test 1: CodeInstUnary (negate)
----------------------------------------------------------------------
print("\nTest 1: CodeInstUnary (negate)")
do
  local dst = make_vid("v1")
  local val = make_vid("v0")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local unary_op = Code.CodeInstUnary(dst, Core.UnaryNeg, ty, val)
  local inst = Code.CodeInst(Code.CodeInstId("inst1"), unary_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "unary: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendHelperCall, "unary: helper call stmt")
  assert_eq(#lowered.helpers, 1, "unary: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperUnary, "unary: helper spec")
  assert_eq(helper.spec.op, Core.UnaryNeg, "unary: negate op")
  print("  PASS: CodeInstUnary negate → CBackendHelperCall")
end

-- Test 1b: Unary bitnot
print("\nTest 1b: CodeInstUnary (bitnot)")
do
  local dst = make_vid("v2")
  local val = make_vid("v1")
  local ty = Code.CodeTyInt(16, Code.CodeUnsigned)
  local unary_op = Code.CodeInstUnary(dst, Core.UnaryBitNot, ty, val)
  local inst = Code.CodeInst(Code.CodeInstId("inst2"), unary_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "bitnot: 1 stmt")
  local helper = lowered.helpers[1]
  assert_eq(helper.spec.op, Core.UnaryBitNot, "bitnot: op is BitNot")
  print("  PASS: CodeInstUnary bitnot → CBackendHelperCall")
end

----------------------------------------------------------------------
-- Test 2: CodeInstCast
----------------------------------------------------------------------
print("\nTest 2: CodeInstCast")
do
  local dst = make_vid("v2")
  local val = make_vid("v1")
  local from_ty = Code.CodeTyInt(32, Code.CodeSigned)
  local to_ty = Code.CodeTyInt(64, Code.CodeSigned)
  local cast_op = Code.CodeInstCast(dst, Core.MachineCastSextend, from_ty, to_ty, val)
  local inst = Code.CodeInst(Code.CodeInstId("inst_cast"), cast_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "cast: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAssign, "cast: assign stmt")
  assert_eq(asdl.classof(stmt.rhs), C.CBackendRCast, "cast: RCast rvalue")
  assert_eq(stmt.rhs.op, Core.MachineCastSextend, "cast: sextend op")
  print("  PASS: CodeInstCast → CBackendAssign + CBackendRCast")
end

----------------------------------------------------------------------
-- Test 3: CodeInstCompare
----------------------------------------------------------------------
print("\nTest 3: CodeInstCompare")
do
  local dst = make_vid("v3")
  local lhs = make_vid("v1")
  local rhs = make_vid("v2")
  local operand_ty = Code.CodeTyInt(32, Code.CodeSigned)
  local cmp_op = Code.CodeInstCompare(dst, Core.CmpEq, operand_ty, lhs, rhs)
  local inst = Code.CodeInst(Code.CodeInstId("inst_cmp"), cmp_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "cmp: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAssign, "cmp: assign stmt")
  assert_eq(asdl.classof(stmt.rhs), C.CBackendRCompare, "cmp: RCompare rvalue")
  assert_eq(stmt.rhs.op, Core.CmpEq, "cmp: EQ op")
  print("  PASS: CodeInstCompare EQ → CBackendAssign + CBackendRCompare")
end

-- Test 3b: LT compare
print("\nTest 3b: CodeInstCompare (LT)")
do
  local dst = make_vid("v4")
  local lhs = make_vid("v1")
  local rhs = make_vid("v2")
  local operand_ty = Code.CodeTyFloat(64)
  local cmp_op = Code.CodeInstCompare(dst, Core.CmpLt, operand_ty, lhs, rhs)
  local inst = Code.CodeInst(Code.CodeInstId("inst_lt"), cmp_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  local stmt = lowered.stmts[1]
  assert_eq(stmt.rhs.op, Core.CmpLt, "LT op")
  print("  PASS: CodeInstCompare LT → CBackendRCompare")
end

----------------------------------------------------------------------
-- Test 4: CodeInstSelect
----------------------------------------------------------------------
print("\nTest 4: CodeInstSelect")
do
  local dst = make_vid("v4")
  local cond = make_vid("v1")
  local then_v = make_vid("v2")
  local else_v = make_vid("v3")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local sel_op = Code.CodeInstSelect(dst, ty, cond, then_v, else_v)
  local inst = Code.CodeInst(Code.CodeInstId("inst_sel"), sel_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "sel: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAssign, "sel: assign stmt")
  assert_eq(asdl.classof(stmt.rhs), C.CBackendRSelect, "sel: RSelect rvalue")
  print("  PASS: CodeInstSelect → CBackendAssign + CBackendRSelect")
end

----------------------------------------------------------------------
-- Test 5: CodeInstFloatBinary
----------------------------------------------------------------------
print("\nTest 5: CodeInstFloatBinary")
do
  local dst = make_vid("v4")
  local lhs = make_vid("v2")
  local rhs = make_vid("v3")
  local ty = Code.CodeTyFloat(64)
  local fbin_op = Code.CodeInstFloatBinary(dst, Core.BinAdd, ty,
    Code.CodeFloatStrict, lhs, rhs)
  local inst = Code.CodeInst(Code.CodeInstId("inst_fbin"), fbin_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "fbin: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendHelperCall, "fbin: helper call")
  assert_eq(#lowered.helpers, 1, "fbin: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperFloatBinary, "fbin: float binary spec")
  assert_eq(helper.spec.op, Core.BinAdd, "fbin: Add op")
  print("  PASS: CodeInstFloatBinary → CBackendHelperCall")
end

----------------------------------------------------------------------
-- Test 6: CodeInstLoad
----------------------------------------------------------------------
print("\nTest 6: CodeInstLoad")
do
  local dst = make_vid("v1")
  local lid = make_lid("ptr")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local place = Code.CodePlaceLocal(lid, ty)
  local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, ty, 4, Code.CodeMayTrap, false, nil)
  local load_op = Code.CodeInstLoad(dst, place, access)
  local inst = Code.CodeInst(Code.CodeInstId("inst_load"), load_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "load: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "load: PlaceLoad stmt")
  assert_eq(stmt.place.local_id.text, "ptr", "load: correct local id")
  print("  PASS: CodeInstLoad → CBackendPlaceLoad")
end

----------------------------------------------------------------------
-- Test 7: CodeInstStore
----------------------------------------------------------------------
print("\nTest 7: CodeInstStore")
do
  local val = make_vid("v1")
  local lid = make_lid("ptr")
  local ty = Code.CodeTyInt(64, Code.CodeSigned)
  local place = Code.CodePlaceLocal(lid, ty)
  local access = Code.CodeMemoryAccess(Code.CodeMemoryWrite, ty, 8, Code.CodeMayTrap, false, nil)
  local store_op = Code.CodeInstStore(place, val, access)
  local inst = Code.CodeInst(Code.CodeInstId("inst_store"), store_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "store: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceStore, "store: PlaceStore stmt")
  assert_eq(stmt.place.local_id.text, "ptr", "store: correct local id")
  print("  PASS: CodeInstStore → CBackendPlaceStore")
end

----------------------------------------------------------------------
-- Test 8: CodeInstAddrOf
----------------------------------------------------------------------
print("\nTest 8: CodeInstAddrOf")
do
  local dst = make_vid("v2")
  local lid = make_lid("x")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local ptr_ty = Code.CodeTyDataPtr(ty)
  local place = Code.CodePlaceLocal(lid, ty)
  local addr_op = Code.CodeInstAddrOf(dst, ptr_ty, place)
  local inst = Code.CodeInst(Code.CodeInstId("inst_addr"), addr_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "addr: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAssign, "addr: assign stmt")
  assert_eq(asdl.classof(stmt.rhs), C.CBackendRAddrOfPlace, "addr: RAddrOfPlace")
  print("  PASS: CodeInstAddrOf → CBackendAssign + CBackendRAddrOfPlace")
end

----------------------------------------------------------------------
-- Test 9: CodeInstPtrOffset
----------------------------------------------------------------------
print("\nTest 9: CodeInstPtrOffset")
do
  local dst = make_vid("v3")
  local base = make_vid("v1")
  local idx = make_vid("v2")
  local ptr_ty = Code.CodeTyDataPtr(Code.CodeTyInt(8, Code.CodeUnsigned))
  local off_op = Code.CodeInstPtrOffset(dst, ptr_ty, base, idx, 1, 0)
  local inst = Code.CodeInst(Code.CodeInstId("inst_off"), off_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "off: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAssign, "off: assign stmt")
  assert_eq(asdl.classof(stmt.rhs), C.CBackendRPtrOffset, "off: RPtrOffset")
  assert_eq(stmt.rhs.elem_size, 1, "off: elem_size")
  assert_eq(stmt.rhs.const_offset, 0, "off: const_offset")
  print("  PASS: CodeInstPtrOffset → CBackendAssign + CBackendRPtrOffset")
end

----------------------------------------------------------------------
-- Test 10: CodeInstGlobalRef (func ref)
----------------------------------------------------------------------
print("\nTest 10: CodeInstGlobalRef (func)")
do
  local dst = make_vid("v4")
  local func_id = Code.CodeFuncId("my_func")
  local ref = Code.CodeGlobalRefFunc(func_id)
  local ptr_ty = Code.CodeTyCodePtr(Code.CodeSigId("my_func_sig"))
  local gref_op = Code.CodeInstGlobalRef(dst, ref, ptr_ty)
  local inst = Code.CodeInst(Code.CodeInstId("inst_gref"), gref_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "gref: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendAssign, "gref: assign stmt")
  assert_eq(asdl.classof(stmt.rhs), C.CBackendRFuncAddr, "gref: RFuncAddr")
  assert_eq(stmt.rhs.func.text, "my_func", "gref: correct func name")
  print("  PASS: CodeInstGlobalRef (func) → CBackendAssign + CBackendRFuncAddr")
end

-- Test 10b: extern ref
print("\nTest 10b: CodeInstGlobalRef (extern)")
do
  local dst = make_vid("v5")
  local extern_id = Code.CodeExternId("printf")
  local ref = Code.CodeGlobalRefExtern(extern_id)
  local ptr_ty = Code.CodeTyCodePtr(Code.CodeSigId("printf_sig"))
  local gref_op = Code.CodeInstGlobalRef(dst, ref, ptr_ty)
  local inst = Code.CodeInst(Code.CodeInstId("inst_eref"), gref_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "eref: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt.rhs), C.CBackendRExternAddr, "eref: RExternAddr")
  assert_eq(stmt.rhs.extern.text, "printf", "eref: correct extern name")
  print("  PASS: CodeInstGlobalRef (extern) → CBackendAssign + CBackendRExternAddr")
end

----------------------------------------------------------------------
-- Test 11: CodeInstCall (direct)
----------------------------------------------------------------------
print("\nTest 11: CodeInstCall (direct)")
do
  local dst = make_vid("v6")
  local func_id = Code.CodeFuncId("my_func")
  local target = Code.CodeCallDirect(func_id)
  local sig = Code.CodeSigId("my_func_sig")
  local arg1 = make_vid("v1")
  local arg2 = make_vid("v2")
  local call_op = Code.CodeInstCall(dst, target, sig, { arg1, arg2 })
  local inst = Code.CodeInst(Code.CodeInstId("inst_call"), call_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "call: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendCall, "call: Call stmt")
  assert_eq(asdl.classof(stmt.target), C.CBackendCallDirect, "call: direct target")
  assert_eq(stmt.target.func.text, "my_func", "call: correct func")
  assert_eq(#stmt.args, 2, "call: 2 args")
  print("  PASS: CodeInstCall (direct) → CBackendCall")
end

-- Test 11b: void call (no dst)
print("\nTest 11b: CodeInstCall (void)")
do
  local extern_id = Code.CodeExternId("puts")
  local target = Code.CodeCallExtern(extern_id)
  local sig = Code.CodeSigId("puts_sig")
  local arg1 = make_vid("v1")
  local call_op = Code.CodeInstCall(nil, target, sig, { arg1 })
  local inst = Code.CodeInst(Code.CodeInstId("inst_vcall"), call_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "vcall: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(stmt.dst, nil, "vcall: no dst")
  assert_eq(asdl.classof(stmt.target), C.CBackendCallExtern, "vcall: extern target")
  print("  PASS: CodeInstCall (void extern) → CBackendCall")
end

----------------------------------------------------------------------
-- Test 12: CodeInstIntrinsicValue (trap)
----------------------------------------------------------------------
print("\nTest 12: CodeInstIntrinsicValue (trap)")
do
  local dst = make_vid("v7")
  local ty = Code.CodeTyVoid
  local intr_op = Code.CodeInstIntrinsicValue(dst, Core.IntrinsicTrap, ty, {})
  local inst = Code.CodeInst(Code.CodeInstId("inst_trap"), intr_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "trap: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendHelperCall, "trap: helper call")
  assert_eq(#lowered.helpers, 1, "trap: 1 helper")
  local helper = lowered.helpers[1]
  assert_eq(asdl.classof(helper.spec), C.CBackendHelperIntrinsic, "trap: intrinsic spec")
  assert_eq(helper.spec.intrinsic, Core.IntrinsicTrap, "trap: Trap intrinsic")
  print("  PASS: CodeInstIntrinsicValue (trap) → CBackendHelperCall")
end

-- Test 12b: IntrinsicVoid
print("\nTest 12b: CodeInstIntrinsicVoid (trap)")
do
  local ty = Code.CodeTyVoid
  local intr_op = Code.CodeInstIntrinsicVoid(Core.IntrinsicTrap, ty, {})
  local inst = Code.CodeInst(Code.CodeInstId("inst_void_trap"), intr_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "void_trap: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(stmt.dst, nil, "void_trap: no dst")
  local helper = lowered.helpers[1]
  assert_eq(helper.spec.intrinsic, Core.IntrinsicTrap, "void_trap: Trap")
  print("  PASS: CodeInstIntrinsicVoid (trap) → CBackendHelperCall (no dst)")
end

----------------------------------------------------------------------
-- Test 13: CodeInstLoad via deref place
----------------------------------------------------------------------
print("\nTest 13: CodeInstLoad via deref place")
do
  local dst = make_vid("v3")
  local addr = make_vid("v2")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local deref_place = Code.CodePlaceDeref(addr, ty, 4)
  local access = Code.CodeMemoryAccess(Code.CodeMemoryRead, ty, 4, Code.CodeMayTrap, false, nil)
  local load_op = Code.CodeInstLoad(dst, deref_place, access)
  local inst = Code.CodeInst(Code.CodeInstId("inst_deref_load"), load_op, Code.CodeOrigin("test"))
  local lowered = { stmts = {}, helpers = {} }
  inst:lower_to_c_backend(lowered)

  assert_eq(#lowered.stmts, 1, "deref_load: 1 stmt")
  local stmt = lowered.stmts[1]
  assert_eq(asdl.classof(stmt), C.CBackendPlaceLoad, "deref_load: PlaceLoad")
  assert_eq(asdl.classof(stmt.place), C.CBackendPlaceDeref, "deref_load: PlaceDeref")
  print("  PASS: CodeInstLoad (deref) → CBackendPlaceLoad + CBackendPlaceDeref")
end

-- Test 14: PlaceBytes lowering
print("\nTest 14: CodePlaceBytes")
do
  local base = make_vid("base_ptr")
  local ty = Code.CodeTyInt(8, Code.CodeUnsigned)
  local bytes_place = Code.CodePlaceBytes(base, 0, ty, 1, 1)
  local cplace = bytes_place:lower_code_place_to_c(nil)
  assert_eq(asdl.classof(cplace), C.CBackendPlaceBytes, "bytes: CBackendPlaceBytes")
  print("  PASS: CodePlaceBytes → CBackendPlaceBytes")
end

-- Test 15: PlaceGlobal lowering
print("\nTest 15: CodePlaceGlobal")
do
  local gid = Code.CodeGlobalId("my_global")
  local ty = Code.CodeTyInt(32, Code.CodeSigned)
  local gplace = Code.CodePlaceGlobal(gid, ty)
  local cplace = gplace:lower_code_place_to_c(nil)
  assert_eq(asdl.classof(cplace), C.CBackendPlaceGlobal, "global: CBackendPlaceGlobal")
  print("  PASS: CodePlaceGlobal → CBackendPlaceGlobal")
end

-- Test 16: PlaceData lowering
print("\nTest 16: CodePlaceData")
do
  local did = Code.CodeDataId("my_data")
  local ty = Code.CodeTyInt(64, Code.CodeUnsigned)
  local dplace = Code.CodePlaceData(did, ty)
  local cplace = dplace:lower_code_place_to_c(nil)
  assert_eq(asdl.classof(cplace), C.CBackendPlaceGlobal, "data: CBackendPlaceGlobal")
  print("  PASS: CodePlaceData → CBackendPlaceGlobal")
end

print("\n=== ALL TESTS PASSED ===")
