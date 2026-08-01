package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema_v2")
local asdl = require("lalin.asdl")
local Code, Core, Flow, Graph, Mem =
  T.LalinCode, T.LalinCore, T.LalinFlow, T.LalinGraph, T.LalinMem
require("lalin.impl.code_mem")

local origin = Code.CodeOriginGenerated("mem transfer test")
local fid, bid = Code.CodeFuncId("f"), Code.CodeBlockId("entry")
local lid, oid = Code.CodeLocalId("slot"), Mem.MemObjectId("slot-object")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local place = Code.CodePlaceLocal(lid, i32)
local access = Code.CodeMemoryAccess(Code.CodeMemoryReadWrite, i32, 4, Code.CodeMustNotTrap, false, nil)
local term = Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({}), origin)
local block = Code.CodeBlock(bid, "entry", {}, {}, term, origin)
local func = Code.CodeFunc(fid, "f", Code.CodeLinkageLocal, Code.CodeSigId("sig"), {}, {}, bid, { block }, origin)
local object = Mem.MemObjectFact(oid, fid, Mem.MemObjectLocal, Mem.MemProvLocal(lid), i32, Mem.MemExtentBytes(4, Mem.MemExtentByConstruction), Mem.MemStrideUnit)
local facet = Mem.MemTransferFacet({}, { Mem.MemLocalObjectEntry(lid, oid) }, {}, {}, {}, { object }, {}, {}, {}, {}, {}, {}, {}, {})
local inductions = Flow.FlowInductionProjection({})

local ops = {
  Code.CodeInstLoad(Code.CodeValueId("load"), place, access),
  Code.CodeInstStore(place, Code.CodeValueId("v"), access),
  Code.CodeInstAtomicLoad(Code.CodeValueId("aload"), place, access, Core.AtomicSeqCst),
  Code.CodeInstAtomicStore(place, Code.CodeValueId("v"), access, Core.AtomicSeqCst),
  Code.CodeInstAtomicRmw(Code.CodeValueId("rmw"), Core.AtomicRmwAdd, place, Code.CodeValueId("v"), access, Core.AtomicSeqCst),
  Code.CodeInstAtomicCas(Code.CodeValueId("cas"), place, Code.CodeValueId("e"), Code.CodeValueId("r"), access, Core.AtomicSeqCst),
}
local current = facet
local c2 = Code.CodeInstConst(Code.CodeValueId("c2"), Code.CodeConstLiteral(i32, Core.LitInt("2")))
local c3 = Code.CodeInstConst(Code.CodeValueId("c3"), Code.CodeConstLiteral(i32, Core.LitInt("3")))
for index, op in ipairs({ c2, c3 }) do
  local ci = Code.CodeInst(Code.CodeInstId("c" .. index), op, origin)
  current = op:transfer_memory(Mem.MemInstructionTransferInput(
    func, block, ci, nil, {}, {}, inductions, current)):next_facet()
end
local mul = Code.CodeInstBinary(Code.CodeValueId("stride"), Core.BinMul, i32, Code.CodeIntSemantics(Code.CodeIntWrap, Code.CodeDivTrapOnZero, Code.CodeShiftMaskCount), Code.CodeValueId("c2"), Code.CodeValueId("c3"))
local mi = Code.CodeInst(Code.CodeInstId("mul"), mul, origin)
current = mul:transfer_memory(Mem.MemInstructionTransferInput(
  func, block, mi, nil, {}, {}, inductions, current)):next_facet()
assert(#current.constants == 2 and #current.scaled_strides == 1)
assert(asdl.isa(current.scaled_strides[1].stride, Mem.MemScaledStrideKnown) and current.scaled_strides[1].stride.elems == 6)
for i, op in ipairs(ops) do
  local inst = Code.CodeInst(Code.CodeInstId("i" .. i), op, origin)
  local result = op:transfer_memory(Mem.MemInstructionTransferInput(
    func, block, inst, nil, {}, {}, inductions, current))
  assert(asdl.isa(result, Mem.MemTransferUpdated))
  current = result:next_facet()
end
assert(#current.accesses == 6 and #current.dependence_accesses == 6 and #current.backend == 6)
assert(Mem.MemLoad:access_mode() == Mem.MemAccessModeRead)
assert(Mem.MemStore:access_mode() == Mem.MemAccessModeWrite)
assert(Mem.MemAtomicCas:access_mode() == Mem.MemAccessModeReadWrite)

local unary = Code.CodeInstUnary(Code.CodeValueId("u"), Core.UnaryNeg, i32, Code.CodeValueId("v"))
local ui = Code.CodeInst(Code.CodeInstId("u"), unary, origin)
assert(asdl.isa(unary:transfer_memory(Mem.MemInstructionTransferInput(
  func, block, ui, nil, {}, {}, inductions, current)),
  Mem.MemTransferUnchanged))
print("test_code_mem_instruction_leaves: ok")
