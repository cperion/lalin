local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonKernel {
  product. KernelId { interned, text [str], },
  product. KernelValueId { interned, text [str], },
  product. KernelStreamId { interned, text [str], },
  sum. KernelSubject {
    KernelSubjectFunction { variant_unique, func [ty "MoonCode.CodeFuncId"], },
    KernelSubjectLoop { variant_unique, loop [ty "MoonGraph.GraphLoopId"], },
    KernelSubjectDomain { variant_unique, domain [ty "MoonFlow.FlowDomain"], },
    KernelSubjectFragment {
      variant_unique,
      func [ty "MoonCode.CodeFuncId"],
      entry [ty "MoonCode.CodeBlockId"],
      exit [ty "MoonCode.CodeBlockId"],
    },
  },
  sum. KernelReject {
    KernelRejectNoFacts { variant_unique, subject [ty "MoonKernel.KernelSubject"], reason [str], },
    KernelRejectUnsupportedSubject {
      variant_unique,
      subject [ty "MoonKernel.KernelSubject"],
      reason [str],
    },
    KernelRejectUnsupportedExpr {
      variant_unique,
      field "value" [ty "MoonCode.CodeValueId"],
      reason [str],
    },
    KernelRejectUnsupportedMemory {
      variant_unique,
      access [ty "MoonMem.MemAccessId"],
      reason [str],
    },
    KernelRejectEffect { variant_unique, effect [ty "MoonEffect.OpEffect"], reason [str], },
    KernelRejectIncompleteFunction {
      variant_unique,
      func [ty "MoonCode.CodeFuncId"],
      reason [str],
    },
  },
  sum. KernelProof {
    KernelProofFlow { variant_unique, domain [ty "MoonFlow.FlowDomain"], reason [str], },
    KernelProofValue { variant_unique, proof [ty "MoonValue.AlgebraProof"], reason [str], },
    KernelProofMemory { variant_unique, proof [ty "MoonMem.MemProof"], reason [str], },
    KernelProofEffect { variant_unique, effect [ty "MoonEffect.OpEffect"], reason [str], },
    KernelProofFunctionEquivalence { variant_unique, reason [str], },
  },
  sum. KernelDomain {
    KernelDomainFlow {
      variant_unique,
      domain [ty "MoonFlow.FlowDomain"],
      trip_count [ty "MoonFlow.FlowTripCount"],
      counter [optional [ty "MoonCode.CodeValueId"]],
    },
  },
  product. KernelStream {
    interned,
    field "id" [ty "MoonKernel.KernelStreamId"],
    object [ty "MoonMem.MemObjectId"],
    accesses [many [ty "MoonMem.MemAccessId"]],
    base [ty "MoonMem.MemBase"],
    elem_ty [ty "MoonCode.CodeType"],
    pattern [ty "MoonMem.MemAccessPattern"],
    backend_info [many [ty "MoonMem.MemBackendAccessInfo"]],
  },
  sum. KernelExpr {
    KernelExprValue { variant_unique, field "value" [ty "MoonCode.CodeValueId"], },
    KernelExprAlgebra { variant_unique, field "expr" [ty "MoonValue.ValueExpr"], },
    KernelExprLoad {
      variant_unique,
      stream [ty "MoonKernel.KernelStream"],
      index [ty "MoonValue.ValueExpr"],
    },
    KernelExprKernelValue { variant_unique, field "value" [ty "MoonKernel.KernelValueId"], },
  },
  product. KernelBinding {
    interned,
    field "id" [ty "MoonKernel.KernelValueId"],
    field "ty" [ty "MoonCode.CodeType"],
    field "expr" [ty "MoonKernel.KernelExpr"],
  },
  sum. KernelEffect {
    KernelEffectStore {
      variant_unique,
      dst [ty "MoonKernel.KernelStream"],
      index [ty "MoonValue.ValueExpr"],
      field "value" [ty "MoonKernel.KernelExpr"],
    },
    KernelEffectFold { variant_unique, reduction [ty "MoonValue.ReductionFact"], },
    KernelEffectCall { variant_unique, call [ty "MoonEffect.CallSummary"], },
  },
  sum. KernelResult {
    KernelResultVoid,
    KernelResultValue { variant_unique, field "expr" [ty "MoonKernel.KernelExpr"], },
    KernelResultReduction { variant_unique, reduction [ty "MoonValue.ReductionFact"], },
    KernelResultClosedForm { variant_unique, closed_form [ty "MoonValue.ClosedFormFact"], },
    KernelResultOriginalControl { variant_unique, reason [str], },
  },
  sum. KernelEquivalence {
    KernelEquivalenceProof { variant_unique, proofs [many [ty "MoonKernel.KernelProof"]], },
    KernelEquivalenceRejected { variant_unique, rejects [many [ty "MoonKernel.KernelReject"]], },
  },
  product. KernelBody {
    interned,
    domain [ty "MoonKernel.KernelDomain"],
    streams [many [ty "MoonKernel.KernelStream"]],
    bindings [many [ty "MoonKernel.KernelBinding"]],
    effects [many [ty "MoonKernel.KernelEffect"]],
    result [ty "MoonKernel.KernelResult"],
    equivalence [ty "MoonKernel.KernelEquivalence"],
  },
  sum. KernelPlan {
    KernelNoPlan {
      variant_unique,
      subject [ty "MoonKernel.KernelSubject"],
      rejects [many [ty "MoonKernel.KernelReject"]],
    },
    KernelPlanned {
      variant_unique,
      field "id" [ty "MoonKernel.KernelId"],
      subject [ty "MoonKernel.KernelSubject"],
      body [ty "MoonKernel.KernelBody"],
    },
  },
  product. KernelModulePlan {
    interned,
    field "module" [ty "MoonCode.CodeModuleId"],
    flow [ty "MoonFlow.FlowFactSet"],
    field "value" [ty "MoonValue.ValueFactSet"],
    mem [ty "MoonMem.MemSemanticFactSet"],
    effect [ty "MoonEffect.EffectFactSet"],
    plans [many [ty "MoonKernel.KernelPlan"]],
  },
}
