package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema")
require("lalin.impl.cemit_emit")
local C = require("lalin.schema.c")
local Core = require("lalin.schema.core")

local i32 = C.CBackendScalar(Core.ScalarI32)
local access = C.CBackendMemoryAccess(i32, 4, C.CBackendMayTrap, false, nil)
local specs = {
  C.CBackendHelperUnary(Core.UnaryNeg, i32),
  C.CBackendHelperBoolNormalize(i32),
  C.CBackendHelperCast(Core.MachineCastIdentity, i32, i32),
  C.CBackendHelperPtrOffset(i32, 4, false),
  C.CBackendHelperIntBinary(Core.BinAdd, i32, C.CBackendIntWrap),
  C.CBackendHelperFloatBinary(Core.BinAdd, i32),
  C.CBackendHelperDivRem(Core.BinDiv, i32, C.CBackendDivTrapOnZeroOrOverflow),
  C.CBackendHelperShift(Core.BinShl, i32, C.CBackendShiftMaskCount),
  C.CBackendHelperIntrinsic(Core.IntrinsicAbs, i32),
  C.CBackendHelperLoad(access), C.CBackendHelperStore(access),
  C.CBackendHelperAtomicLoad(access), C.CBackendHelperAtomicStore(access),
  C.CBackendHelperAtomicRmw(Core.AtomicRmwAdd, access),
  C.CBackendHelperAtomicCas(access, Core.AtomicSeqCst, Core.AtomicSeqCst),
  C.CBackendHelperAtomicFence(Core.AtomicSeqCst),
  C.CBackendHelperMemcpy, C.CBackendHelperTypedMemcpy(i32, 4, 4),
  C.CBackendHelperMemset, C.CBackendHelperTypedMemset(i32, 4, 4),
  C.CBackendHelperMemcmp,
  C.CBackendHelperLayoutAssert(C.CBackendLayoutAssertion(C.CTypeId("m", "T"), 4, 4)),
  C.CBackendHelperRequireFeature(C.CBackendFeatureHostedRuntime, "test"),
  C.CBackendHelperScan(i32, true, Core.BinAdd, 4),
  C.CBackendHelperFind(i32, Core.CmpEq, 4),
  C.CBackendHelperReduce(i32, Core.BinAdd, true, 4),
  C.CBackendHelperTrap,
}
for i = 1, #specs do
  local signature = specs[i]:c_helper_signature()
  assert(asdl.classof(signature) == C.CBackendHelperSignature, "helper signature must be typed")
  assert(type(signature.params) == "table" and signature.result ~= nil)
end
local use = C.CBackendHelperUse(C.CBackendHelperId("h"), specs[1])
assert(asdl.classof(use:c_helper_signature()) == C.CBackendHelperSignature)
assert(not pcall(function() return C.CBackendHelperSignature({ i32 }, { kind = "raw" }) end), "raw helper signature result must be rejected")
io.write("schema typed C helper signatures ok\n")
