local S = require("lalin.schema.dsl")
S.use()

return schema. LalinFlow {
  product. FlowDomainId { interned, text [str], },
  sum. FlowDomain {
    FlowDomainLoop { variant_unique, loop [LalinGraph.GraphLoopId], },
    FlowDomainBlockRange {
      variant_unique,
      func [LalinCode.CodeFuncId],
      entry [LalinCode.CodeBlockId],
      exit [LalinCode.CodeBlockId],
    },
    FlowDomainFunction { variant_unique, func [LalinCode.CodeFuncId], },
  },

  sum. FlowDomainOrder { FlowDomainForward, FlowDomainBackward, },
  product. FlowDomainAxis {
    interned,
    index_ty [LalinCode.CodeType],
    start [optional [LalinValue.ValueExpr]],
    stop [optional [LalinValue.ValueExpr]],
    step [number],
    order [LalinFlow.FlowDomainOrder],
    index_name [optional [str]],
  },

  sum. FlowWindowBoundary {
    FlowWindowBoundaryReject,
    FlowWindowBoundaryClamp,
    FlowWindowBoundaryWrap,
    FlowWindowBoundaryZero,
  },
  product. FlowWindowAxis {
    interned,
    before [number],
    after [number],
    boundary [LalinFlow.FlowWindowBoundary],
  },

  sum. FlowDomainShape {
    FlowDomainShapeRange1D {
      variant_unique,
      index_ty [LalinCode.CodeType],
      start [optional [LalinValue.ValueExpr]],
      stop [optional [LalinValue.ValueExpr]],
      step [number],
      order [LalinFlow.FlowDomainOrder],
    },
    FlowDomainShapeRangeND { variant_unique, axes [many [LalinFlow.FlowDomainAxis]], },
    FlowDomainShapeWindowND {
      variant_unique,
      axes [many [LalinFlow.FlowDomainAxis]],
      windows [many [LalinFlow.FlowWindowAxis]],
    },
    FlowDomainShapeTiledND {
      variant_unique,
      axes [many [LalinFlow.FlowDomainAxis]],
      tile_sizes [many [number]],
    },
  },

  sum. FlowProofSource {
    FlowProofAuthor,
    FlowProofFrontendPass,
    FlowProofBackendGuarantee,
  },
  sum. FlowProof {
    FlowProofDomain { variant_unique, domain [LalinFlow.FlowDomain], reason [str], },
    FlowProofMemory { variant_unique, proof [LalinMem.MemProof], reason [str], },
    FlowProofAuthoritative {
      variant_unique,
      source [LalinFlow.FlowProofSource],
      reason [str],
    },
  },

  sum. FlowFactOrigin {
    FlowFactCheckerDerived,
    FlowFactAuthorAsserted { variant_unique, reason [str], },
    FlowFactFrontendFact { variant_unique, reason [str], },
  },
  product. FlowDomainShapeFact {
    interned,
    domain [LalinFlow.FlowDomain],
    shape [LalinFlow.FlowDomainShape],
    proofs [many [LalinFlow.FlowProof]],
    origin [LalinFlow.FlowFactOrigin],
  },
  sum. FlowDomainIntent {
    FlowDomainIntentGeneric,
    FlowDomainIntentNativeLoop { variant_unique, reason [str], },
  },
  product. FlowDomainIntentFact {
    interned,
    domain [LalinFlow.FlowDomain],
    intent [LalinFlow.FlowDomainIntent],
    proofs [many [LalinFlow.FlowProof]],
    origin [LalinFlow.FlowFactOrigin],
  },

  sum. FlowTripCountReject {
    FlowTripCountNotLoop { subject_description [str], },
    FlowTripCountInductionNotMonotonic { induction_value [LalinCode.CodeValueId], },
    FlowTripCountNonConstantStep { step_value [LalinCode.CodeValueId], },
    FlowTripCountUnboundedRange {
      start [LalinCode.CodeValueId],
      stop [LalinCode.CodeValueId],
    },
    FlowTripCountIrregularExit { exit_block [LalinCode.CodeBlockId], },
    FlowTripCountNotMaterialized { reason [str], },
  },
  sum. FlowTripCount {
    FlowTripCountExact {
      variant_unique,
      count [LalinCode.CodeValueId],
      trip_expr [optional [LalinValue.ValueExpr]],
      proof [optional [LalinMem.MemProof]],
    },
    FlowTripCountNonNegative {
      variant_unique,
      count [LalinCode.CodeValueId],
      trip_expr [optional [LalinValue.ValueExpr]],
      proof [optional [LalinMem.MemProof]],
    },
    FlowTripCountRejected {
      variant_unique,
      reject [LalinFlow.FlowTripCountReject],
      trip_expr [optional [LalinValue.ValueExpr]],
    },
  },

  product. FlowEdgeArg {
    interned,
    src [LalinCode.CodeValueId],
    dst_param [LalinCode.CodeValueId],
  },
  product. FlowEdgeFact {
    interned,
    edge [LalinGraph.GraphEdge],
    args [many [LalinFlow.FlowEdgeArg]],
  },

  sum. FlowReject {
    FlowRejectIrreducible { variant_unique, func [LalinCode.CodeFuncId], reason [str], },
    FlowRejectNotCounted { variant_unique, loop [LalinGraph.GraphLoopId], reason [str], },
    FlowRejectUnsupportedTerminator {
      variant_unique,
      block [LalinGraph.GraphBlockId],
      term [LalinCode.CodeTermOp],
    },
    FlowRejectUnsupportedInduction {
      variant_unique,
      loop [LalinGraph.GraphLoopId],
      field. value [LalinCode.CodeValueId],
      reason [str],
    },
    FlowRejectUnknownValue {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      reason [str],
    },
  },

  sum. FlowBoundDerivationKey {
    FlowBoundFromTripCount { domain [LalinFlow.FlowDomain], },
    FlowBoundFromParam { param_name [str], },
    FlowBoundFromConst { field. value [LalinCore.Literal], },
    FlowBoundFromBinary {
      op [LalinCore.BinaryOp],
      left [LalinCode.CodeValueId],
      right [LalinCode.CodeValueId],
    },
  },
  sum. FlowBound {
    FlowBoundUnknown,
    FlowBoundConst { variant_unique, raw [str], },
    FlowBoundValue { variant_unique, field. value [LalinCode.CodeValueId], },
    FlowBoundDerived {
      variant_unique,
      key [LalinFlow.FlowBoundDerivationKey],
      deps [many [LalinCode.CodeValueId]],
    },
  },

  sum. FlowValueRange {
    FlowRangeUnknown { variant_unique, field. value [LalinCode.CodeValueId], },
    FlowRangeExact {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      bound [LalinFlow.FlowBound],
    },
    FlowRangeUnsigned {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      min [LalinFlow.FlowBound],
      max [LalinFlow.FlowBound],
    },
    FlowRangeSigned {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      min [LalinFlow.FlowBound],
      max [LalinFlow.FlowBound],
    },
    FlowRangeDerived {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      min [LalinFlow.FlowBound],
      max [LalinFlow.FlowBound],
      reason [str],
    },
  },

  sum. FlowStopConvention { FlowStopExclusive, FlowStopInclusive, },
  sum. FlowLoopDirection { FlowLoopIncreasing, FlowLoopDecreasing, FlowLoopDirectionUnknown, },
  product. FlowCountedDomain {
    interned,
    start [LalinCode.CodeValueId],
    stop [LalinCode.CodeValueId],
    step [LalinCode.CodeValueId],
    stop_convention [LalinFlow.FlowStopConvention],
    direction [LalinFlow.FlowLoopDirection],
  },
  sum. FlowInductionRole {
    FlowPrimaryInduction,
    FlowDerivedInduction { variant_unique, base [LalinCode.CodeValueId], },
    FlowPointerInduction {
      variant_unique,
      base [LalinCode.CodeValueId],
      elem_size [number],
    },
  },
  product. FlowInduction {
    interned,
    field. value [LalinCode.CodeValueId],
    field. ty [LalinCode.CodeType],
    init [LalinCode.CodeValueId],
    step [LalinCode.CodeValueId],
    role [LalinFlow.FlowInductionRole],
    range [LalinFlow.FlowValueRange],
  },

  product. FlowCarrierId { interned, text [str], },
  product. FlowAddressId { interned, text [str], },
  product. FlowAddressBase {
    interned,
    base [LalinMem.MemBase],
    elem_ty [LalinCode.CodeType],
    elem_size [number],
  },
  product. FlowAddressUse {
    interned,
    inst [LalinGraph.GraphInstRef],
    index [LalinCode.CodeValueId],
  },

  sum. FlowCarrierStep {
    FlowCarrierStepSame,
    FlowCarrierStepConst { variant_unique, amount [number], },
    FlowCarrierStepDynamic { variant_unique, step [LalinCode.CodeValueId], },
    FlowCarrierStepRecompute { variant_unique, index [LalinCode.CodeValueId], },
  },
  product. FlowCarrierTransfer {
    interned,
    edge [LalinGraph.GraphEdge],
    step [LalinFlow.FlowCarrierStep],
  },
  product. FlowCarrierThread {
    interned,
    field. id [LalinFlow.FlowCarrierId],
    func [LalinCode.CodeFuncId],
    domain [LalinFlow.FlowDomain],
    index [LalinCode.CodeValueId],
    init [LalinCode.CodeValueId],
    value_ty [LalinCode.CodeType],
    blocks [many [LalinGraph.GraphBlockId]],
    transfers [many [LalinFlow.FlowCarrierTransfer]],
    proofs [many [LalinFlow.FlowProof]],
  },
  product. FlowAddressThread {
    interned,
    field. id [LalinFlow.FlowAddressId],
    carrier [LalinFlow.FlowCarrierId],
    func [LalinCode.CodeFuncId],
    domain [LalinFlow.FlowDomain],
    base [LalinFlow.FlowAddressBase],
    accesses [many [LalinMem.MemAccessId]],
    uses [many [LalinFlow.FlowAddressUse]],
    proofs [many [LalinFlow.FlowProof]],
  },

  product. FlowLoopExit {
    interned,
    from [LalinGraph.GraphBlockId],
    to [LalinGraph.GraphBlockId],
    condition [optional [LalinCode.CodeValueId]],
  },
  product. FlowLoopFacts {
    interned,
    loop [LalinGraph.GraphLoopId],
    domain [LalinFlow.FlowDomain],
    counted [optional [LalinFlow.FlowCountedDomain]],
    body_blocks [many [LalinGraph.GraphBlockId]],
    inductions [many [LalinFlow.FlowInduction]],
    exits [many [LalinFlow.FlowLoopExit]],
    rejects [many [LalinFlow.FlowReject]],
  },
  product. FlowInductionRangeFact {
    interned,
    loop [LalinGraph.GraphLoopId],
    field. value [LalinCode.CodeValueId],
    min [LalinFlow.FlowBound],
    max [LalinFlow.FlowBound],
    max_exclusive [bool],
    reason [str],
  },

  sum. FlowLoopSemanticFact {
    FlowLoopNormalizedCounted {
      variant_unique,
      loop [LalinGraph.GraphLoopId],
      domain [LalinFlow.FlowCountedDomain],
      direction [LalinFlow.FlowLoopDirection],
      trip_count [LalinFlow.FlowTripCount],
    },
    FlowLoopInductionRange { variant_unique, range [LalinFlow.FlowInductionRangeFact], },
    FlowLoopInductionNoWrap {
      variant_unique,
      loop [LalinGraph.GraphLoopId],
      field. value [LalinCode.CodeValueId],
      reason [str],
    },
  },
  product. FlowSemanticFactSet {
    interned,
    field. module [LalinCode.CodeModuleId],
    facts [many [LalinFlow.FlowLoopSemanticFact]],
  },

  product. FlowFactSet {
    interned,
    field. module [LalinCode.CodeModuleId],
    domains [many [LalinFlow.FlowDomain]],
    edges [many [LalinFlow.FlowEdgeFact]],
    loops [many [LalinFlow.FlowLoopFacts]],
    ranges [many [LalinFlow.FlowValueRange]],
    domain_shapes [many [LalinFlow.FlowDomainShapeFact]],
    domain_intents [many [LalinFlow.FlowDomainIntentFact]],
    carriers [many [LalinFlow.FlowCarrierThread]],
    addresses [many [LalinFlow.FlowAddressThread]],
    rejects [many [LalinFlow.FlowReject]],
  },
}
