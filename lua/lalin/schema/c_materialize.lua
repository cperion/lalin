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
    CMatIssueMissingProof { variant_unique, requirement [LalinStencil.StencilProofRequirement], reason [str], },
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
