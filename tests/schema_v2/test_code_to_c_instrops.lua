package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema_v2")
require("lalin.impl.lower_emit_c")

local Core = require("lalin.schema_v2.core")
local Code = require("lalin.schema_v2.code")
local C = require("lalin.schema_v2.c")
local Lower = require("lalin.schema_v2.lower")

local instruction_leaves = {
  Code.CodeInstConst, Code.CodeInstAlias, Code.CodeInstUnary, Code.CodeInstBinary,
  Code.CodeInstFloatBinary, Code.CodeInstCompare, Code.CodeInstCast, Code.CodeInstSelect,
  Code.CodeInstIntrinsicVoid, Code.CodeInstIntrinsicValue, Code.CodeInstAddrOf,
  Code.CodeInstGlobalRef, Code.CodeInstPtrOffset, Code.CodeInstLoad, Code.CodeInstStore,
  Code.CodeInstAggregate, Code.CodeInstArray, Code.CodeInstViewMake, Code.CodeInstViewData,
  Code.CodeInstViewLen, Code.CodeInstViewStride, Code.CodeInstSliceMake, Code.CodeInstSliceData,
  Code.CodeInstSliceLen, Code.CodeInstByteSpanMake, Code.CodeInstByteSpanData,
  Code.CodeInstByteSpanLen, Code.CodeInstClosure, Code.CodeInstVariantCtor,
  Code.CodeInstVariantTag, Code.CodeInstVariantPayload, Code.CodeInstCall,
  Code.CodeInstAtomicLoad, Code.CodeInstAtomicStore, Code.CodeInstAtomicRmw,
  Code.CodeInstAtomicCas, Code.CodeInstAtomicFence,
}
for i = 1, #instruction_leaves do
  assert(instruction_leaves[i].lower_code_inst_to_c ~= nil)
  assert(instruction_leaves[i].lower_code_inst_to_c ~= Code.CodeInstOp.lower_code_inst_to_c, "instruction leaf must own C lowering")
end

local term_leaves = { Code.CodeTermJump, Code.CodeTermBranch, Code.CodeTermSwitch, Code.CodeTermVariantSwitch, Code.CodeTermReturn, Code.CodeTermTrap, Code.CodeTermUnreachable }
for i = 1, #term_leaves do assert(term_leaves[i].lower_code_term_to_c ~= nil, "terminator leaf must own C lowering") end

local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local source = Code.CodeValueId("source")
local source_local = C.CBackendLocal(C.CBackendLocalId("source"), C.CBackendName("source"), i32:code_to_c_backend_type())
local values = Lower.LowerCValueTypeProjection({ Lower.LowerCValueTypeEntry(source, i32, source_local) })
local signatures = Lower.LowerCSignatureProjection({})
local input = Lower.LowerCInstructionInput(signatures, Lower.LowerCExternProjection({}), values)

local unary = Code.CodeInst(Code.CodeInstId("unary"), Code.CodeInstUnary(Code.CodeValueId("neg"), Core.UnaryNeg, i32, source), Code.CodeOriginSource("test"))
local unary_result = unary:lower_to_c_backend(input)
assert(asdl.classof(unary_result) == Lower.LowerCInstEmission)
assert(#unary_result.stmts == 1 and #unary_result.helpers == 1 and #unary_result.definitions == 1)
assert(asdl.classof(unary_result.stmts[1]) == C.CBackendHelperCall)
assert(unary_result.definitions[1].code_ty == i32)

local cast = Code.CodeInst(Code.CodeInstId("cast"), Code.CodeInstCast(Code.CodeValueId("casted"), Core.MachineCastIdentity, i32, i32, source), Code.CodeOriginSource("test"))
local cast_result = cast:lower_to_c_backend(input)
assert(asdl.classof(cast_result) == Lower.LowerCInstEmission)
assert(asdl.classof(cast_result.stmts[1]) == C.CBackendAssign)
assert(asdl.classof(cast_result.stmts[1].rhs) == C.CBackendRCast)

local ret = Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ source }), Code.CodeOriginSource("test"))
local term_result = ret:lower_to_c_backend_term(Lower.LowerCTermInput(values))
assert(asdl.classof(term_result) == Lower.LowerCTermEmission)
assert(asdl.classof(term_result.term) == C.CBackendReturn)

local local_place = Code.CodePlaceLocal(Code.CodeLocalId("slot"), i32)
assert(asdl.classof(local_place:lower_code_place_to_c(input)) == C.CBackendPlaceLocal)
local global_place = Code.CodePlaceGlobal(Code.CodeGlobalId("g"), i32)
assert(asdl.classof(global_place:lower_code_place_to_c(input)) == C.CBackendPlaceGlobal)
local data_place = Code.CodePlaceData(Code.CodeDataId("d"), i32)
assert(asdl.classof(data_place:lower_code_place_to_c(input)) == C.CBackendPlaceGlobal)

io.write("schema_v2 typed code-to-C instruction lowering ok\n")
