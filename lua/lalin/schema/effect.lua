local S = require("lalin.schema.dsl")
S.use()

return schema. LalinEffect {
  product. EffectId { interned, text [str], },
  sum. EffectEvidence {
    EffectEvidenceMemory { variant_unique, proof [LalinMem.MemProof], },
    EffectEvidenceContract { variant_unique, source [LalinCode.CodeFuncContractFact], proof [LalinMem.MemProof], },
    EffectEvidenceDeclared { variant_unique, reason [str], },
    EffectEvidenceConservative { variant_unique, reason [str], },
  },
  sum. EffectObject {
    EffectObjectMem { variant_unique, object [LalinMem.MemObjectId], },
    EffectObjectStore { variant_unique, store_value [LalinCode.CodeValueId], },
    EffectObjectUnknown { variant_unique, reason [str], },
  },
  sum. OpEffect {
    EffectRead { variant_unique, object [LalinEffect.EffectObject], evidence [LalinEffect.EffectEvidence], },
    EffectWrite { variant_unique, object [LalinEffect.EffectObject], evidence [LalinEffect.EffectEvidence], },
    EffectInvalidate { variant_unique, object [LalinEffect.EffectObject], evidence [LalinEffect.EffectEvidence], },
    EffectRetain { variant_unique, field. value [LalinCode.CodeValueId], evidence [LalinEffect.EffectEvidence], },
    EffectNoEscape { variant_unique, field. value [LalinCode.CodeValueId], evidence [LalinEffect.EffectEvidence], },
    EffectMayTrap { variant_unique, evidence [LalinEffect.EffectEvidence], },
    EffectNoTrap { variant_unique, evidence [LalinEffect.EffectEvidence], },
    EffectVolatile { variant_unique, evidence [LalinEffect.EffectEvidence], },
    EffectAtomic { variant_unique, ordering [LalinCore.AtomicOrdering], evidence [LalinEffect.EffectEvidence], },
    EffectUnknown { variant_unique, evidence [LalinEffect.EffectEvidence], },
  },

  sum. FunctionEffectClassification {
    FunctionEffectPure { variant_unique, evidence [LalinEffect.EffectEvidence], },
    FunctionEffectful { variant_unique, effects [many [LalinEffect.OpEffect]], },
    FunctionEffectUnresolved { variant_unique, evidence [LalinEffect.EffectEvidence], },
  },
  product. FunctionEffectEntry { interned, func [LalinCode.CodeFuncId], classification [LalinEffect.FunctionEffectClassification], },
  product. FunctionEffectProjection { functions [many [LalinEffect.FunctionEffectEntry]], },
  sum. FunctionEffectLookup {
    FunctionEffectFound { variant_unique, entry [LalinEffect.FunctionEffectEntry], },
    FunctionEffectMissing { variant_unique, func [LalinCode.CodeFuncId], },
  },

  product. ContractEffectInput { source [LalinCode.CodeFuncContractFact], },
  sum. ContractEffectResult {
    ContractEffects { variant_unique, effects [many [LalinEffect.OpEffect]], },
    ContractNoEffect { variant_unique, evidence [LalinEffect.EffectEvidence], },
  },
  product. ContractEffectEntry { interned, func [LalinCode.CodeFuncId], result [LalinEffect.ContractEffectResult], },
  product. ContractEffectProjection { entries [many [LalinEffect.ContractEffectEntry]], },

  product. CallSummaryInput { field. module [LalinCode.CodeModule], functions [LalinEffect.FunctionEffectProjection], },
  sum. CallSummary {
    CallSummaryDirect { variant_unique, callee [LalinCode.CodeFuncId], classification [LalinEffect.FunctionEffectClassification], effects [many [LalinEffect.OpEffect]], },
    CallSummaryExtern { variant_unique, extern [LalinCode.CodeExternId], symbol [str], effects [many [LalinEffect.OpEffect]], },
    CallSummaryIndirect { variant_unique, callee [LalinCode.CodeValueId], sig [LalinCode.CodeSigId], effects [many [LalinEffect.OpEffect]], },
    CallSummaryClosure { variant_unique, closure [LalinCode.CodeValueId], sig [LalinCode.CodeSigId], effects [many [LalinEffect.OpEffect]], },
  },
  product. InstEffect { interned, inst [LalinCode.CodeInstId], effects [many [LalinEffect.OpEffect]], },
  product. TermEffect { interned, block [LalinCode.CodeBlockId], effects [many [LalinEffect.OpEffect]], },
  product. EffectAccessEffects { effects [many [LalinEffect.OpEffect]], },

  product. EffectInstructionInput {
    field. module [LalinCode.CodeModule],
    func [LalinCode.CodeFunc],
    block [LalinCode.CodeBlock],
    inst [LalinCode.CodeInst],
    memory [LalinMem.MemAccessProjection],
    functions [LalinEffect.FunctionEffectProjection],
  },
  sum. EffectInstructionResult {
    EffectInstructionNone,
    EffectInstructionEffects { variant_unique, effect [LalinEffect.InstEffect], },
    EffectInstructionCall { variant_unique, summary [LalinEffect.CallSummary], effect [LalinEffect.InstEffect], },
  },
  product. EffectTermInput { func [LalinCode.CodeFunc], block [LalinCode.CodeBlock], term [LalinCode.CodeTerm], contracts [LalinEffect.ContractEffectProjection], },
  sum. EffectTermResult { EffectTermNone, EffectTermEffects { variant_unique, effect [LalinEffect.TermEffect], }, },
  sum. FunctionEffectAccumulation {
    FunctionEffectEmpty { variant_unique, evidence [LalinEffect.EffectEvidence], },
    FunctionEffectsAccumulated { variant_unique, effects [many [LalinEffect.OpEffect]], },
  },
  product. EffectFunctionComposition { calls [many [LalinEffect.CallSummary]], insts [many [LalinEffect.InstEffect]], terms [many [LalinEffect.TermEffect]], accumulation [LalinEffect.FunctionEffectAccumulation], },
  product. EffectAnalysisRequest { field. module [LalinCode.CodeModule], graph [LalinGraph.CodeGraph], memory [LalinMem.MemSemanticFactSet], contracts [LalinCode.CodeContractFactSet], },
  product. EffectFactSet { interned, field. module [LalinCode.CodeModuleId], calls [many [LalinEffect.CallSummary]], insts [many [LalinEffect.InstEffect]], terms [many [LalinEffect.TermEffect]], },
  product. EffectAnalysisResult { facts [LalinEffect.EffectFactSet], functions [LalinEffect.FunctionEffectProjection], },
}
