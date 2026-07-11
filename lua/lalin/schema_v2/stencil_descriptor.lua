local S = require("lalin.schema.dsl")
S.use()

return schema. LalinStencilDescriptor {
  sum. StencilDescriptorSchedule {
    StencilDescriptorScheduled { variant_unique, schedule [LalinStencil.StencilSchedule], },
    StencilDescriptorExplicitlyUnscheduled { variant_unique, reason [str], },
  },
  sum. StencilDescriptorResult {
    StencilDescriptorValueResult { variant_unique, field. ty [LalinCode.CodeType], },
    StencilDescriptorStoreResult { variant_unique, dst [LalinStencil.StencilAccessRef], },
    StencilDescriptorControlResult { variant_unique, field. ty [LalinCode.CodeType], },
  },
  product. StencilDescriptorSpine {
    interned,
    field. id [LalinStencil.StencilMetastencilId],
    producer [LalinStencil.StencilProducer],
    accesses [many [LalinStencil.StencilAccess]],
    streams [many [LalinStencil.StencilStreamDef]],
    legality [LalinStencil.StencilFusionLegality],
    proofs [many [LalinKernel.KernelProof]],
    schedule [LalinStencilDescriptor.StencilDescriptorSchedule],
  },
  sum. StencilMachineDescriptor {
    StencilDescriptorStore {
      variant_unique,
      spine [LalinStencilDescriptor.StencilDescriptorSpine],
      sink [LalinStencil.StencilSinkDef],
      result [LalinStencilDescriptor.StencilDescriptorStoreResult],
    },
    StencilDescriptorReduce {
      variant_unique,
      spine [LalinStencilDescriptor.StencilDescriptorSpine],
      sink [LalinStencil.StencilSinkDef],
      result [LalinStencilDescriptor.StencilDescriptorValueResult],
    },
    StencilDescriptorScan {
      variant_unique,
      spine [LalinStencilDescriptor.StencilDescriptorSpine],
      sink [LalinStencil.StencilSinkDef],
      result [LalinStencilDescriptor.StencilDescriptorStoreResult],
    },
    StencilDescriptorFind {
      variant_unique,
      spine [LalinStencilDescriptor.StencilDescriptorSpine],
      sink [LalinStencil.StencilSinkDef],
      result [LalinStencilDescriptor.StencilDescriptorControlResult],
    },
    StencilDescriptorPartition {
      variant_unique,
      spine [LalinStencilDescriptor.StencilDescriptorSpine],
      sink [LalinStencil.StencilSinkDef],
      result [LalinStencilDescriptor.StencilDescriptorStoreResult],
    },
    StencilDescriptorCount {
      variant_unique,
      spine [LalinStencilDescriptor.StencilDescriptorSpine],
      sink [LalinStencil.StencilSinkDef],
      result [LalinStencilDescriptor.StencilDescriptorValueResult],
    },
    StencilDescriptorScatterReduce {
      variant_unique,
      spine [LalinStencilDescriptor.StencilDescriptorSpine],
      sink [LalinStencil.StencilSinkDef],
      result [LalinStencilDescriptor.StencilDescriptorStoreResult],
    },
  },
  product. StencilDescriptorProjectionInput {
    interned,
    field. id [LalinStencil.StencilMetastencilId],
    producer [LalinStencil.StencilProducer],
    accesses [many [LalinStencil.StencilAccess]],
    streams [many [LalinStencil.StencilStreamDef]],
    sinks [many [LalinStencil.StencilSinkDef]],
    legality [LalinStencil.StencilFusionLegality],
    proofs [many [LalinKernel.KernelProof]],
  },
  sum. StencilDescriptorProjectionIssue {
    StencilDescriptorProjectionUnscheduled { variant_unique, reason [str], },
    StencilDescriptorProjectionInvalidResult { variant_unique, reason [str], },
  },
  sum. StencilDescriptorProjection {
    StencilDescriptorProjected { variant_unique, computation [LalinStencil.StencilComputation], },
    StencilDescriptorProjectionRejected {
      variant_unique,
      descriptor [LalinStencilDescriptor.StencilMachineDescriptor],
      issues [many [LalinStencilDescriptor.StencilDescriptorProjectionIssue]],
    },
  },
}
