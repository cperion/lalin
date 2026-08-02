local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCMat {
  product. CMatKernelId { interned, text [str], },
  product. CMatLocalId { interned, text [str], },

  sum. CMatAccessMutability {
    CMatAccessReadOnly,
    CMatAccessWriteOnly,
    CMatAccessReadWrite,
    CMatAccessReduce,
  },

  product. CMatAccessBinding {
    interned,
    access [LalinStencil.StencilAccessRef],
    source [LalinStencil.StencilAccess],
    local_id [LalinCMat.CMatLocalId],
    field. ty [LalinCode.CodeType],
    layout [LalinStencil.StencilAccessLayout],
    mutability [LalinCMat.CMatAccessMutability],
    restrict_eligible [bool],
    const_eligible [bool],
    alignment [LalinStencil.StencilAlignmentFact],
  },

  product. CMatKernelBindingEntry {
    interned,
    field. id [LalinKernel.KernelValueId],
    binding [LalinKernel.KernelBinding],
  },
  product. CMatCodeBindingEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    binding [LalinKernel.KernelBinding],
  },
  sum. CMatBindingLookup {
    CMatBindingFound { variant_unique, binding [LalinKernel.KernelBinding], },
    CMatBindingMissing { variant_unique, reason [str], },
  },
  product. CMatBindingProjection {
    interned,
    kernel_bindings [many [LalinCMat.CMatKernelBindingEntry]],
    code_bindings [many [LalinCMat.CMatCodeBindingEntry]],
  },
  product. CMatLaneDiscovery {
    interned,
    lanes [many [LalinKernel.KernelLane]],
  },
  product. CMatReadAccessEntry {
    interned,
    lane [LalinKernel.KernelLane],
    access [LalinCMat.CMatAccessBinding],
  },
  sum. CMatReadAccessLookup {
    CMatReadAccessFound { variant_unique, access [LalinCMat.CMatAccessBinding], },
    CMatReadAccessMissing { variant_unique, lane [LalinKernel.KernelLane], reason [str], },
  },
  sum. CMatWindowCounter {
    CMatWindowNoCounter,
    CMatWindowCounterValue { variant_unique, field. value [LalinCode.CodeValueId], },
  },
  sum. CMatWindowLayout {
    CMatWindowLayoutNone,
    CMatWindowLayout1D {
      variant_unique,
      axis [LalinStencil.StencilProducerAxis],
      window [LalinStencil.StencilWindowAxis],
      counter [LalinCMat.CMatWindowCounter],
    },
    CMatWindowLayoutRejected { variant_unique, reason [str], },
  },
  sum. CMatWindowOffset {
    CMatWindowNotIndexed { variant_unique, reason [str], },
    CMatWindowOffsetKnown { variant_unique, offset [number], },
    CMatWindowOffsetRejected { variant_unique, reason [str], },
  },
  sum. CMatLiteralInt {
    CMatLiteralIntKnown { variant_unique, raw [str], },
    CMatLiteralIntMissing,
  },
  product. CMatPointProjection {
    interned,
    bindings [LalinCMat.CMatBindingProjection],
    reads [many [LalinCMat.CMatReadAccessEntry]],
    window [LalinCMat.CMatWindowLayout],
  },
  product. CMatAccessNameEntry {
    interned,
    field. name [str],
    binding [LalinCMat.CMatAccessBinding],
  },
  sum. CMatAccessLookup {
    CMatAccessFound { variant_unique, binding [LalinCMat.CMatAccessBinding], },
    CMatAccessMissing { variant_unique, access [LalinStencil.StencilAccessRef], reason [str], },
  },
  product. CMatStreamEntry {
    interned,
    field. id [LalinStencil.StencilStreamId],
    stream [LalinStencil.StencilStreamDef],
  },
  sum. CMatStreamLookup {
    CMatStreamFound { variant_unique, stream [LalinStencil.StencilStreamDef], },
    CMatStreamMissing { variant_unique, stream [LalinStencil.StencilStreamId], reason [str], },
  },
  sum. CMatInlineAccumulator {
    CMatInlineNoAccumulator,
    CMatInlineAccumulatorLocal { variant_unique, local_id [LalinC.CBackendLocalId], },
  },
  product. CMatInlineProjection {
    interned,
    kernel [LalinCMat.CMatFusedKernel],
    computation [LalinStencil.StencilComputation],
    accesses [many [LalinCMat.CMatAccessNameEntry]],
    streams [many [LalinCMat.CMatStreamEntry]],
    window [LalinCMat.CMatWindowLayout],
    accumulator [LalinCMat.CMatInlineAccumulator],
  },
  sum. CMatInlineSinkResult {
    CMatInlineNoControl,
    CMatInlineControl { variant_unique, predicate [LalinC.CBackendAtom], },
  },

  sum. CMatLoopOrder {
    CMatLoopForward,
    CMatLoopBackward,
  },

  product. CMatLoopAxis {
    interned,
    axis [LalinStencil.StencilAxisRef],
    index [LalinCMat.CMatLocalId],
    index_ty [LalinCode.CodeType],
    start_param [optional [LalinCMat.CMatLocalId]],
    stop_param [optional [LalinCMat.CMatLocalId]],
    step [number],
    order [LalinCMat.CMatLoopOrder],
  },

  sum. CMatTailPolicy {
    CMatTailScalar,
    CMatTailMask,
    CMatTailOverreadProvenSafe,
  },

  sum. CMatVectorPolicy {
    CMatVectorNone,
    CMatVectorAutovec {
      variant_unique,
      lanes [optional [number]],
      tail [LalinCMat.CMatTailPolicy],
    },
    CMatVectorExplicit {
      variant_unique,
      lanes [number],
      tail [LalinCMat.CMatTailPolicy],
    },
  },

  product. CMatLoopNest {
    interned,
    axes [many [LalinCMat.CMatLoopAxis]],
    unroll [number],
    interleave [number],
    vector [LalinCMat.CMatVectorPolicy],
  },

  sum. CMatStreamMaterialization {
    CMatStreamInline {
      variant_unique,
      stream [LalinStencil.StencilStreamRef],
      field. ty [LalinCode.CodeType],
    },
    CMatStreamLocal {
      variant_unique,
      stream [LalinStencil.StencilStreamRef],
      local_id [LalinCMat.CMatLocalId],
      field. ty [LalinCode.CodeType],
    },
  },

  sum. CMatSinkMaterialization {
    CMatSinkInline { variant_unique, sink [LalinStencil.StencilSinkRef], },
    CMatSinkLocalResult {
      variant_unique,
      sink [LalinStencil.StencilSinkRef],
      local_id [LalinCMat.CMatLocalId],
      field. ty [LalinCode.CodeType],
    },
    CMatSinkControlResult {
      variant_unique,
      sink [LalinStencil.StencilSinkRef],
    },
  },

  product. CMatFusedKernel {
    interned,
    field. id [LalinCMat.CMatKernelId],
    computation [LalinStencil.StencilComputation],
    loop [LalinCMat.CMatLoopNest],
    accesses [many [LalinCMat.CMatAccessBinding]],
    streams [many [LalinCMat.CMatStreamMaterialization]],
    sinks [many [LalinCMat.CMatSinkMaterialization]],
    schedule [LalinStencil.StencilSchedule],
    proofs [many [LalinKernel.KernelProof]],
  },

  sum. CMatMaterializationIssue {
    CMatIssueUnsupportedProducer { variant_unique, producer [LalinStencil.StencilProducerShape], reason [str], },
    CMatIssueUnsupportedAccess { variant_unique, access [LalinStencil.StencilAccess], reason [str], },
  },

  sum. CMatMaterialization {
    CMatMaterializedFused { variant_unique, kernel [LalinCMat.CMatFusedKernel], },
    CMatRejectedKernel {
      variant_unique,
      computation [optional [LalinStencil.StencilComputation]],
      issues [many [LalinCMat.CMatMaterializationIssue]],
    },
  },

  product. CMatModule {
    interned,
    field. module [LalinCode.CodeModuleId],
    kernels [many [LalinCMat.CMatMaterialization]],
  },
}
