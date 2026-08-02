package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema_v2")
local asdl = require("lalin.asdl")
local Code, Mem = T.LalinCode, T.LalinMem
require("lalin.impl.code_mem")
assert(Code.CodeContractWindowFootprint == nil)
assert(Mem.MemContractWindowFootprintEntry == nil)
assert(Mem.MemWindowFootprintProjection == nil)

local mid = Code.CodeModuleId("mem-contract")
local fid = Code.CodeFuncId("f")
local a, b, n = Code.CodeValueId("a"), Code.CodeValueId("b"), Code.CodeValueId("n")
local origin = Code.CodeOriginGenerated("test")
local place = Code.CodePlaceDeref(a, Code.CodeTyInt(32, Code.CodeSigned), nil)
local expr = Code.CodeContractPlaceLoad(place)
local facts = Code.CodeContractFactSet(mid, {
  Code.CodeFuncContractFact(fid, Code.CodeContractBounds(a, n), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractProjectionBounds(expr, Code.CodeContractValueRef(n)), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractDisjoint(a, b), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractSameLen(a, b), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractNoAlias(a), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractReadonly(a), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractWriteonly(b), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractProjectionReadonly(expr), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractProjectionWriteonly(expr), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractRejected("bad contract"), origin),
})

local projection = facts:project_memory_contract()
assert(asdl.isa(projection, Mem.MemContractProjection))
assert(#projection.bounds == 1 and projection.bounds[1].base == a)
assert(#projection.projection_bounds == 1 and asdl.isa(projection.projection_bounds[1].base, Mem.MemContractPlaceKey))
assert(#projection.disjoint == 1 and #projection.same_lengths == 1)
assert(#projection.noalias == 1 and #projection.readonly == 1 and #projection.writeonly == 1)
assert(#projection.projection_readonly == 1 and #projection.projection_writeonly == 1)
assert(#projection.rejected == 1)

local aid = Mem.MemAccessId("missing")
local access_projection = Mem.MemAccessProjection({}, {}, {}, {})
assert(asdl.isa(access_projection:mem_access(aid), Mem.MemAccessMissing))
assert(asdl.isa(access_projection:object_for_access(aid), Mem.MemObjectMissing))
assert(asdl.isa(access_projection:backend_for_access(aid), Mem.MemBackendMissing))
assert(asdl.isa(access_projection:proof_for_access(aid), Mem.MemProofMissing))

local ok = pcall(function() Mem.MemContractProjectInput({ source = facts.facts[1] }) end)
assert(not ok, "project input rejects loose records")
print("test_code_mem_contract_projection: ok")
