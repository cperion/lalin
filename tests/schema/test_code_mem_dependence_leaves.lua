package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema")
local asdl = require("lalin.asdl")
local Code, Graph, Mem = T.LalinCode, T.LalinGraph, T.LalinMem
require("lalin.impl.code_mem")

local fid, bid = Code.CodeFuncId("f"), Code.CodeBlockId("b")
local oid, other = Mem.MemObjectId("a"), Mem.MemObjectId("b")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local lid = Code.CodeLocalId("slot")
local place = Code.CodePlaceLocal(lid, i32)
local access = Code.CodeMemoryAccess(Code.CodeMemoryReadWrite, i32, 4, Code.CodeMustNotTrap, false, nil)
local function fact(name, op)
  local aid = Mem.MemAccessId(name)
  return Mem.MemAccessFact(aid, fid, Graph.GraphBlockId(fid, bid), Code.CodeInstId(name), op, place, access, Mem.MemBaseLocal(lid), Mem.MemIndexNone, Mem.MemAccessScalar, Mem.MemAlignKnown(4), Mem.MemBoundsInObject("test"), Mem.MemNonTrapping("test"))
end
local a = Mem.MemDependenceAccess(fact("read-a", Mem.MemLoad), Mem.MemObjectFound(oid), nil, Mem.MemAccessSafetyProven("bounded"), 1)
local b = Mem.MemDependenceAccess(fact("read-b", Mem.MemLoad), Mem.MemObjectFound(oid), nil, Mem.MemAccessSafetyProven("bounded"), 2)
local result = Mem.MemDependenceRequest(a, b, Mem.MemRelationProjection({}, {}, {}, {})):classify()
assert(asdl.isa(result, Mem.MemDependenceClassified))
assert(asdl.isa(result.decision, Mem.MemObjectPairIndependent))
assert(asdl.isa(result.fact, Mem.MemNoDependence))

local write = Mem.MemDependenceAccess(fact("write", Mem.MemStore), Mem.MemObjectFound(oid), Graph.GraphLoopId("loop"), Mem.MemAccessSafetyProven("bounded"), 3)
local read = Mem.MemDependenceAccess(fact("read", Mem.MemLoad), Mem.MemObjectFound(oid), Graph.GraphLoopId("loop"), Mem.MemAccessSafetyProven("bounded"), 4)
local dependent = Mem.MemDependenceRequest(write, read, Mem.MemRelationProjection({}, {}, {}, {})):classify()
assert(asdl.isa(dependent.decision, Mem.MemObjectPairDependent))
assert(asdl.isa(dependent.fact, Mem.MemLoopCarriedDependence))

local src_fact = Code.CodeFuncContractFact(fid, Code.CodeContractNoAlias(Code.CodeValueId("bytes")), Code.CodeOriginUnknown)
local proof = Mem.MemProofObject(other, Mem.MemObjectBaseAddressStable)
local distinct_read = Mem.MemDependenceAccess(fact("other", Mem.MemLoad), Mem.MemObjectFound(other), nil, Mem.MemAccessSafetyProven("bounded"), 5)
local independent = Mem.MemDependenceRequest(write, distinct_read, Mem.MemRelationProjection({}, { Mem.MemDisjointEntry(oid, other, proof) }, {}, {})):classify()
assert(asdl.isa(independent.decision, Mem.MemObjectPairIndependent))

local noalias_proof = Mem.MemProofContract(src_fact, Mem.MemContractNoAlias("noalias", "bytes"))
local noalias_access = Mem.MemDependenceAccess(fact("noalias", Mem.MemLoad), Mem.MemObjectFound(other), nil, Mem.MemAccessSafetyProven("bounded"), 6)
local noalias_independent = Mem.MemDependenceRequest(a, noalias_access, Mem.MemRelationProjection({}, {}, { Mem.MemNoAliasEntry(other, noalias_proof) }, {})):classify()
assert(asdl.isa(noalias_independent.decision, Mem.MemObjectPairIndependent))
assert(asdl.isa(noalias_independent.fact, Mem.MemNoDependence))
assert(asdl.isa(noalias_independent.fact.proof, Mem.MemProofContract))

assert(asdl.isa(Mem.MemNonTrapping("ok"):movement_decision(access, Mem.MemLoad, Mem.MemAccessSafetyProven("bounded")), Mem.MemMovementMovable))
local volatile_access = Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 4, Code.CodeMustNotTrap, true, nil)
assert(asdl.isa(Mem.MemNonTrapping("ok"):movement_decision(volatile_access, Mem.MemLoad, Mem.MemAccessSafetyProven("bounded")), Mem.MemMovementPinned))
assert(asdl.isa(Mem.MemNonTrapping("ok"):movement_decision(access, Mem.MemAtomicLoad, Mem.MemAccessSafetyProven("bounded")), Mem.MemMovementPinned))
print("test_code_mem_dependence_leaves: ok")
