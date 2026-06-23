local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonFlow {
  product. FlowDomainId { interned, text [str], },
  sum. FlowDomain {
    FlowDomainLoop { variant_unique, loop [ty. MoonGraph.GraphLoopId], },
    FlowDomainBlockRange {
      variant_unique,
      func [ty. MoonCode.CodeFuncId],
      entry [ty. MoonCode.CodeBlockId],
      exit [ty. MoonCode.CodeBlockId],
    },
    FlowDomainFunction { variant_unique, func [ty. MoonCode.CodeFuncId], },
  },
  sum. FlowTripCount {
    FlowTripCountExact {
      variant_unique,
      count [ty. MoonCode.CodeValueId],
      proof [optional [ty. MoonMem.MemProof]],
    },
    FlowTripCountNonNegative {
      variant_unique,
      count [ty. MoonCode.CodeValueId],
      proof [optional [ty. MoonMem.MemProof]],
    },
    FlowTripCountUnknown { variant_unique, reason [str], },
  },
  product. FlowEdgeArg {
    interned,
    src [ty. MoonCode.CodeValueId],
    dst_param [ty. MoonCode.CodeValueId],
  },
  product. FlowEdgeFact {
    interned,
    edge [ty. MoonGraph.GraphEdge],
    args [many [ty. MoonFlow.FlowEdgeArg]],
  },
  sum. FlowReject {
    FlowRejectIrreducible { variant_unique, func [ty. MoonCode.CodeFuncId], reason [str], },
    FlowRejectNotCounted { variant_unique, loop [ty. MoonGraph.GraphLoopId], reason [str], },
    FlowRejectUnsupportedTerminator {
      variant_unique,
      block [ty. MoonGraph.GraphBlockId],
      term [ty. MoonCode.CodeTermKind],
    },
    FlowRejectUnsupportedInduction {
      variant_unique,
      loop [ty. MoonGraph.GraphLoopId],
      field. value [ty. MoonCode.CodeValueId],
      reason [str],
    },
    FlowRejectUnknownValue {
      variant_unique,
      field. value [ty. MoonCode.CodeValueId],
      reason [str],
    },
  },
  sum. FlowBound {
    FlowBoundUnknown,
    FlowBoundConst { variant_unique, raw [str], },
    FlowBoundValue { variant_unique, field. value [ty. MoonCode.CodeValueId], },
    FlowBoundDerived { variant_unique, key [str], deps [many [ty. MoonCode.CodeValueId]], },
  },
  sum. FlowValueRange {
    FlowRangeUnknown { variant_unique, field. value [ty. MoonCode.CodeValueId], },
    FlowRangeExact {
      variant_unique,
      field. value [ty. MoonCode.CodeValueId],
      bound [ty. MoonFlow.FlowBound],
    },
    FlowRangeUnsigned {
      variant_unique,
      field. value [ty. MoonCode.CodeValueId],
      min [ty. MoonFlow.FlowBound],
      max [ty. MoonFlow.FlowBound],
    },
    FlowRangeSigned {
      variant_unique,
      field. value [ty. MoonCode.CodeValueId],
      min [ty. MoonFlow.FlowBound],
      max [ty. MoonFlow.FlowBound],
    },
    FlowRangeDerived {
      variant_unique,
      field. value [ty. MoonCode.CodeValueId],
      min [ty. MoonFlow.FlowBound],
      max [ty. MoonFlow.FlowBound],
      reason [str],
    },
  },
  product. FlowCountedDomain {
    interned,
    start [ty. MoonCode.CodeValueId],
    stop [ty. MoonCode.CodeValueId],
    step [ty. MoonCode.CodeValueId],
    stop_exclusive [bool],
  },
  sum. FlowLoopDirection { FlowLoopIncreasing, FlowLoopDecreasing, FlowLoopDirectionUnknown, },
  sum. FlowInductionKind {
    FlowPrimaryInduction,
    FlowDerivedInduction { variant_unique, base [ty. MoonCode.CodeValueId], },
    FlowPointerInduction { variant_unique, base [ty. MoonCode.CodeValueId], elem_size [number], },
  },
  product. FlowInduction {
    interned,
    field. value [ty. MoonCode.CodeValueId],
    field. ty [ty. MoonCode.CodeType],
    init [ty. MoonCode.CodeValueId],
    step [ty. MoonCode.CodeValueId],
    kind [ty. MoonFlow.FlowInductionKind],
    range [ty. MoonFlow.FlowValueRange],
  },
  product. FlowLoopExit {
    interned,
    from [ty. MoonGraph.GraphBlockId],
    to [ty. MoonGraph.GraphBlockId],
    condition [optional [ty. MoonCode.CodeValueId]],
  },
  product. FlowLoopFacts {
    interned,
    loop [ty. MoonGraph.GraphLoopId],
    domain [ty. MoonFlow.FlowDomain],
    counted [optional [ty. MoonFlow.FlowCountedDomain]],
    body_blocks [many [ty. MoonGraph.GraphBlockId]],
    inductions [many [ty. MoonFlow.FlowInduction]],
    exits [many [ty. MoonFlow.FlowLoopExit]],
    rejects [many [ty. MoonFlow.FlowReject]],
  },
  product. FlowInductionRangeFact {
    interned,
    loop [ty. MoonGraph.GraphLoopId],
    field. value [ty. MoonCode.CodeValueId],
    min [ty. MoonFlow.FlowBound],
    max [ty. MoonFlow.FlowBound],
    max_exclusive [bool],
    reason [str],
  },
  sum. FlowLoopSemanticFact {
    FlowLoopNormalizedCounted {
      variant_unique,
      loop [ty. MoonGraph.GraphLoopId],
      domain [ty. MoonFlow.FlowCountedDomain],
      direction [ty. MoonFlow.FlowLoopDirection],
      trip_count [ty. MoonFlow.FlowTripCount],
    },
    FlowLoopInductionRange { variant_unique, range [ty. MoonFlow.FlowInductionRangeFact], },
    FlowLoopInductionNoWrap {
      variant_unique,
      loop [ty. MoonGraph.GraphLoopId],
      field. value [ty. MoonCode.CodeValueId],
      reason [str],
    },
  },
  product. FlowSemanticFactSet {
    interned,
    field. module [ty. MoonCode.CodeModuleId],
    facts [many [ty. MoonFlow.FlowLoopSemanticFact]],
  },
  product. FlowFactSet {
    interned,
    field. module [ty. MoonCode.CodeModuleId],
    domains [many [ty. MoonFlow.FlowDomain]],
    edges [many [ty. MoonFlow.FlowEdgeFact]],
    loops [many [ty. MoonFlow.FlowLoopFacts]],
    ranges [many [ty. MoonFlow.FlowValueRange]],
    rejects [many [ty. MoonFlow.FlowReject]],
  },
}
