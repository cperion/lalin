package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local asdl = require("lalin.asdl")
require("lalin.schema")
require("lalin.impl.code_validate")
local Code = require("lalin.schema.code")
local CV = require("lalin.schema.code_validation")
local Core = require("lalin.schema.core")

local origin = Code.CodeOriginSource("validation-test")
local i32 = Code.CodeTyInt(32, Code.CodeSigned)
local function module_with(block, locals, data)
  local sig_id = Code.CodeSigId("sig")
  local func = Code.CodeFunc(Code.CodeFuncId("f"), "f", Code.CodeLinkageExport, sig_id, {}, locals or {}, block.id, { block }, origin)
  return Code.CodeModule(Code.CodeModuleId("m"), { Code.CodeSig(sig_id, {}, { i32 }) }, {}, data or {}, {}, {}, { func }, origin)
end
local function has_issue(result, class)
  if asdl.classof(result) ~= CV.CodeValidateFailed then return false end
  for i = 1, #result.issues do if asdl.classof(result.issues[i]) == class then return true end end
  return false
end

local value = Code.CodeValueId("v")
local const = Code.CodeInst(Code.CodeInstId("const"), Code.CodeInstConst(value, Code.CodeConstLiteral(i32, Core.LitInt("7"))), origin)
local block = Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, { const }, Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ value }), origin), origin)
local valid = module_with(block):code_validate()
assert(asdl.classof(valid) == CV.CodeValidateOk)
assert(asdl.classof(valid.projection) == CV.CodeValidationModuleProjection)

local missing = Code.CodeValueId("missing")
block = Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, {}, Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ missing }), origin), origin)
assert(has_issue(module_with(block):code_validate(), Code.CodeIssueMissingValue))

local duplicate_a = Code.CodeInst(Code.CodeInstId("a"), Code.CodeInstConst(value, Code.CodeConstLiteral(i32, Core.LitInt("1"))), origin)
local duplicate_b = Code.CodeInst(Code.CodeInstId("b"), Code.CodeInstConst(value, Code.CodeConstLiteral(i32, Core.LitInt("2"))), origin)
block = Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, { duplicate_a, duplicate_b }, Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ value }), origin), origin)
assert(has_issue(module_with(block):code_validate(), Code.CodeIssueDuplicateValue))

local slot = Code.CodeLocal(Code.CodeLocalId("slot"), "slot", i32, Code.CodeResidenceAddressed, origin)
local load = Code.CodeInst(Code.CodeInstId("load"), Code.CodeInstLoad(value, Code.CodePlaceLocal(slot.id, i32), Code.CodeMemoryAccess(Code.CodeMemoryRead, i32, 3, Code.CodeMayTrap, false, nil)), origin)
block = Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, { load }, Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ value }), origin), origin)
assert(has_issue(module_with(block, { slot }):code_validate(), Code.CodeIssueInvalidMemoryAccess))

local reloc = Code.CodeReloc(Code.CodeRelocId("r"), 4, Code.CodeGlobalRefData(Code.CodeDataId("absent")), 0, origin)
local segment = Code.CodeData(Code.CodeDataId("segment"), "segment", Code.CodeLinkageLocal, 8, 8, { Code.CodeDataReloc(reloc) }, origin)
local reloc_module = module_with(Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, { const }, Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ value }), origin), origin), {}, { segment })
assert(has_issue(reloc_module:code_validate(), Code.CodeIssueMissingData))
local duplicate_segment = Code.CodeData(Code.CodeDataId("dupe_relocs"), "dupe_relocs", Code.CodeLinkageLocal, 16, 8, { Code.CodeDataReloc(reloc), Code.CodeDataReloc(reloc) }, origin)
assert(has_issue(module_with(Code.CodeBlock(Code.CodeBlockId("entry"), "entry", {}, { const }, Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({ value }), origin), origin), {}, { duplicate_segment }):code_validate(), Code.CodeIssueInvalidReloc))

local inst_leaves = {
  Code.CodeInstConst, Code.CodeInstAlias, Code.CodeInstUnary, Code.CodeInstBinary, Code.CodeInstFloatBinary, Code.CodeInstCompare, Code.CodeInstCast, Code.CodeInstSelect, Code.CodeInstIntrinsicVoid, Code.CodeInstIntrinsicValue, Code.CodeInstAddrOf, Code.CodeInstGlobalRef, Code.CodeInstPtrOffset, Code.CodeInstLoad, Code.CodeInstStore, Code.CodeInstAggregate, Code.CodeInstArray, Code.CodeInstViewMake, Code.CodeInstViewData, Code.CodeInstViewLen, Code.CodeInstViewStride, Code.CodeInstSliceMake, Code.CodeInstSliceData, Code.CodeInstSliceLen, Code.CodeInstByteSpanMake, Code.CodeInstByteSpanData, Code.CodeInstByteSpanLen, Code.CodeInstClosure, Code.CodeInstVariantCtor, Code.CodeInstVariantTag, Code.CodeInstVariantPayload, Code.CodeInstCall, Code.CodeInstAtomicLoad, Code.CodeInstAtomicStore, Code.CodeInstAtomicRmw, Code.CodeInstAtomicCas, Code.CodeInstAtomicFence,
}
for i = 1, #inst_leaves do assert(inst_leaves[i].code_validate ~= Code.CodeInstOp.code_validate, "validation must be leaf-owned") end
io.write("schema leaf-owned Code IR validation ok\n")
