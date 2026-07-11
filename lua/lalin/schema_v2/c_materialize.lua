local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCMat {
  product. CMatKernelId { interned, text [str], },
  product. CMatLocalId { interned, text [str], },

  sum. CMatConstCapability {
    CMatConstEligible,
    CMatConstIneligible { variant_unique, reason [str], },
  },
  sum. CMatRestrictCapability {
    CMatRestrictEligible,
    CMatRestrictIneligible { variant_unique, reason [str], },
  },
  sum. CMatLaneCapability {
    CMatLaneFromTarget,
    CMatLaneNative,
    CMatLaneFixed { variant_unique, lanes [number], },
  },
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
    restrict_capability [LalinCMat.CMatRestrictCapability],
    const_capability [LalinCMat.CMatConstCapability],
    alignment [LalinStencil.StencilAlignmentFact],
  },
  product. CMatAccessBindingInput { interned, local_id [LalinCMat.CMatLocalId], },
  sum. CMatAccessBindingResult {
    CMatAccessBound { variant_unique, binding [LalinCMat.CMatAccessBinding], },
    CMatAccessBindingRejected { variant_unique, issue [LalinCMat.CMatMaterializationIssue], },
  },
  sum. CMatAccessCollection {
    CMatAccessCollectionReady { variant_unique, bindings [many [LalinCMat.CMatAccessBinding]], },
    CMatAccessCollectionRejected { variant_unique, issues [many [LalinCMat.CMatMaterializationIssue]], },
  },

  sum. CMatLoopOrder { CMatLoopForward, CMatLoopBackward, },
  product. CMatLoopAxis {
    interned,
    axis [LalinStencil.StencilAxisRef],
    index [LalinCMat.CMatLocalId],
    index_ty [LalinCode.CodeType],
    step [number],
    order [LalinCMat.CMatLoopOrder],
  },
  sum. CMatTailPolicy { CMatTailScalar, CMatTailMask, CMatTailOverreadProvenSafe, },
  sum. CMatVectorPolicy {
    CMatVectorNone,
    CMatVectorAutovec { variant_unique, lanes [LalinCMat.CMatLaneCapability], tail [LalinCMat.CMatTailPolicy], },
    CMatVectorExplicit { variant_unique, lanes [LalinCMat.CMatLaneCapability], tail [LalinCMat.CMatTailPolicy], },
  },
  product. CMatSchedulePolicy {
    interned,
    unroll [number],
    interleave [number],
    vector [LalinCMat.CMatVectorPolicy],
  },
  product. CMatLoopNest {
    interned,
    axes [many [LalinCMat.CMatLoopAxis]],
    policy [LalinCMat.CMatSchedulePolicy],
  },
  sum. CMatLoopPlan {
    CMatLoopPlanned { variant_unique, axes [many [LalinCMat.CMatLoopAxis]], },
    CMatLoopRejected { variant_unique, issue [LalinCMat.CMatMaterializationIssue], },
  },

  sum. CMatStreamMaterialization {
    CMatStreamInline { variant_unique, stream [LalinStencil.StencilStreamRef], field. ty [LalinCode.CodeType], },
    CMatStreamLocal {
      variant_unique,
      stream [LalinStencil.StencilStreamRef],
      local_id [LalinCMat.CMatLocalId],
      field. ty [LalinCode.CodeType],
    },
  },
  sum. CMatSinkMaterialization {
    CMatSinkInline { variant_unique, sink [LalinStencil.StencilSinkRef], },
    CMatSinkValueResult {
      variant_unique,
      sink [LalinStencil.StencilSinkRef],
      local_id [LalinCMat.CMatLocalId],
      field. ty [LalinCode.CodeType],
    },
    CMatSinkStoreResult { variant_unique, sink [LalinStencil.StencilSinkRef], dst [LalinStencil.StencilAccessRef], },
    CMatSinkControlResult { variant_unique, sink [LalinStencil.StencilSinkRef], },
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
    CMatIssueUnsupportedSchedule { variant_unique, schedule [LalinStencil.StencilSchedule], reason [str], },
    CMatIssueUnsupportedSink { variant_unique, sink [LalinStencil.StencilSinkDef], reason [str], },
    CMatIssueMissingProof { variant_unique, requirement [LalinStencil.StencilProofRequirement], reason [str], },
  },
  product. CMatMaterializationInput { interned, kernel [LalinCMat.CMatKernelId], },
  sum. CMatMaterialization {
    CMatMaterializedFused { variant_unique, kernel [LalinCMat.CMatFusedKernel], },
    CMatRejectedComputation {
      variant_unique,
      computation [LalinStencil.StencilComputation],
      issues [many [LalinCMat.CMatMaterializationIssue]],
    },
  },
  product. CMatModule {
    interned,
    field. module [LalinCode.CodeModuleId],
    kernels [many [LalinCMat.CMatMaterialization]],
  },
}
