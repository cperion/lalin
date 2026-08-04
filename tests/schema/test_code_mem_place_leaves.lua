package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema")
local asdl = require("lalin.asdl")
local Code, Flow, Mem, Sem = T.LalinCode, T.LalinFlow, T.LalinMem, T.LalinSem
require("lalin.impl.code_mem")

local fid = Code.CodeFuncId("f")
local lid, gid, did = Code.CodeLocalId("l"), Code.CodeGlobalId("g"), Code.CodeDataId("d")
local ptr, index = Code.CodeValueId("ptr"), Code.CodeValueId("i")
local lo, go, dobj, pobj = Mem.MemObjectId("lo"), Mem.MemObjectId("go"), Mem.MemObjectId("do"), Mem.MemObjectId("po")
local induction = Flow.FlowInduction(
  index, Code.CodeTyIndex, Code.CodeValueId("init"), Code.CodeValueId("step"),
  Flow.FlowPrimaryInduction, Flow.FlowRangeUnknown(index))
local inductions = Flow.FlowInductionProjection({ induction })
local flow = Flow.FlowFactSet(Code.CodeModuleId("m"), {}, {}, {}, {}, {}, {}, {})
local input = Mem.MemPlaceResolveInput(
  fid, { Mem.MemValueObjectEntry(ptr, pobj) },
  { Mem.MemLocalObjectEntry(lid, lo) },
  { Mem.MemGlobalObjectEntry(gid, go) },
  { Mem.MemDataObjectEntry(did, dobj) }, {}, inductions, {}, flow)
local i32 = Code.CodeTyInt(32, Code.CodeSigned)

local places = {
  Code.CodePlaceLocal(lid, i32),
  Code.CodePlaceGlobal(gid, i32),
  Code.CodePlaceData(did, i32),
  Code.CodePlaceDeref(ptr, i32, 4),
  Code.CodePlaceIndex(Code.CodePlaceDeref(ptr, i32, 4), index, i32, 4),
  Code.CodePlaceField(Code.CodePlaceDeref(ptr, i32, 4), Sem.FieldRef("Pair", "x", 0), i32, 0, 4, 4),
  Code.CodePlaceBytes(ptr, 4, i32, 4, 4),
}
for _, place in ipairs(places) do
  local result = place:resolve_memory_place(input)
  assert(asdl.isa(result, Mem.MemPlaceResolved), tostring(place))
end
local indexed = places[5]:resolve_memory_place(input)
assert(asdl.isa(indexed.index, Mem.MemIndexInduction))
assert(indexed.index.induction == induction)
local ordinary = inductions:classify_memory_index(
  Mem.MemIndexClassifyInput(Code.CodeValueId("ordinary"), 4, 0, {}, flow))
assert(asdl.isa(ordinary, Mem.MemIndexValue))

local missing = Code.CodePlaceDeref(Code.CodeValueId("missing"), i32, nil):resolve_memory_place(input)
assert(asdl.isa(missing, Mem.MemPlaceUnresolved))
local nested_missing = Code.CodePlaceField(Code.CodePlaceDeref(Code.CodeValueId("missing2"), i32, nil), Sem.FieldRef("Pair", "x", 0), i32, 0, 4, 4):resolve_memory_place(input)
assert(asdl.isa(nested_missing, Mem.MemPlaceUnresolved))

local local_fact = Mem.MemObjectFact(lo, fid, Mem.MemObjectLocal, Mem.MemProvLocal(lid), i32, Mem.MemExtentUnknown(Mem.MemExtentDynamicAllocation), Mem.MemStrideUnit)
assert(asdl.isa(local_fact:access_safety(), Mem.MemAccessSafetyProven))
local unknown_fact = Mem.MemObjectFact(Mem.MemObjectId("u"), fid, Mem.MemObjectUnknown(Mem.MemObjectUnresolvedPointer(ptr)), Mem.MemProvUnknown("test"), nil, Mem.MemExtentUnknown(Mem.MemExtentDynamicAllocation), Mem.MemStrideUnknown(Mem.MemStrideNonUniformAccess))
assert(asdl.isa(unknown_fact:access_safety(), Mem.MemAccessSafetyUnproven))
print("test_code_mem_place_leaves: ok")
