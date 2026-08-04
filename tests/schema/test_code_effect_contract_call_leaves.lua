package.path = "./?.lua;./?/init.lua;./lua/?.lua;./lua/?/init.lua;" .. package.path

local T = require("lalin.schema")
local asdl = require("lalin.asdl")
local Code, Effect = T.LalinCode, T.LalinEffect
require("lalin.impl.code_effect")

local origin = Code.CodeOriginGenerated("effect test")
local mid, fid = Code.CodeModuleId("m"), Code.CodeFuncId("f")
local sig = Code.CodeSigId("sig")
local bid = Code.CodeBlockId("entry")
local term = Code.CodeTerm(Code.CodeTermId("ret"), Code.CodeTermReturn({}), origin)
local block = Code.CodeBlock(bid, "entry", {}, {}, term, origin)
local func = Code.CodeFunc(fid, "f", Code.CodeLinkageLocal, sig, {}, {}, bid, { block }, origin)
local extid = Code.CodeExternId("abs")
local ext = Code.CodeExtern(extid, "abs", "abs", sig, origin)
local module = Code.CodeModule(mid, {}, {}, {}, {}, { ext }, { func }, origin)
local evidence = Effect.EffectEvidenceDeclared("pure fixture")
local functions = Effect.FunctionEffectProjection({ Effect.FunctionEffectEntry(fid, Effect.FunctionEffectPure(evidence)) })
local input = Effect.CallSummaryInput(module, functions)

local summaries = {
  Code.CodeCallDirect(fid):effect_summary(input),
  Code.CodeCallExtern(extid):effect_summary(input),
  Code.CodeCallIndirect(Code.CodeValueId("fp"), sig):effect_summary(input),
  Code.CodeCallClosure(Code.CodeValueId("cl"), sig):effect_summary(input),
}
assert(asdl.isa(summaries[1], Effect.CallSummaryDirect) and asdl.isa(summaries[1].classification, Effect.FunctionEffectPure))
assert(asdl.isa(summaries[2], Effect.CallSummaryExtern) and summaries[2].symbol == "abs")
assert(asdl.isa(summaries[3], Effect.CallSummaryIndirect))
assert(asdl.isa(summaries[4], Effect.CallSummaryClosure))
for _, summary in ipairs(summaries) do assert(#summary.effects == 1) end

local a, n = Code.CodeValueId("a"), Code.CodeValueId("n")
local contracts = Code.CodeContractFactSet(mid, {
  Code.CodeFuncContractFact(fid, Code.CodeContractBounds(a, n), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractReadonly(a), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractWriteonly(a), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractNoAlias(a), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractInvalidate(a), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractPreserve(a), origin),
  Code.CodeFuncContractFact(fid, Code.CodeContractRejected("bad"), origin),
})
local projection = contracts:project_contract_effects()
assert(#projection.entries == 7)
assert(asdl.isa(projection.entries[1].result, Effect.ContractNoEffect))
for i = 2, #projection.entries do assert(asdl.isa(projection.entries[i].result, Effect.ContractEffects)) end
print("test_code_effect_contract_call_leaves: ok")
