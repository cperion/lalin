local S = require("lalin.schema.dsl")
S.use()

return schema. LalinSchedule {
  product. ScheduleId { interned, text [str], },
  product. ScheduleTarget { interned, target [LalinBackend.BackTargetModel], },
  sum. LaneShape {
    LaneScalar,
    LaneVector { variant_unique, elem_ty [LalinCode.CodeType], lanes [number], },
  },
  sum. TailPlan { TailNone, TailScalar, TailMasked, TailPeel { variant_unique, elems [number], }, },
  sum. ScheduleForm {
    ScheduleScalarIndex,
    ScheduleScalarPointer,
    ScheduleVector {
      variant_unique,
      lanes [LalinSchedule.LaneShape],
      unroll [number],
      interleave [number],
      tail [LalinSchedule.TailPlan],
    },
    ScheduleClosedForm,
  },
  sum. ScheduleProof {
    ScheduleProofTarget { variant_unique, reason [str], },
    ScheduleProofMemory { variant_unique, proof [LalinMem.MemProof], },
    ScheduleProofAlgebra { variant_unique, proof [LalinValue.AlgebraProof], },
    ScheduleProofProfit { variant_unique, reason [str], },
  },
  sum. ScheduleReject {
    ScheduleRejectTarget { variant_unique, reason [str], },
    ScheduleRejectMemory { variant_unique, reason [str], },
    ScheduleRejectAlgebra { variant_unique, reason [str], },
    ScheduleRejectProfit { variant_unique, reason [str], },
  },
  sum. ScheduleEmitterKind {
    ScheduleEmitterScalar,
    ScheduleEmitterVector { feature [LalinStencil.StencilVectorFeatureRequirement] },
    ScheduleEmitterClosedForm,
    ScheduleEmitterFallback { reason [LalinSchedule.EmitterFallbackReason] },
  },
  sum. EmitterFallbackReason {
    EmitterFallbackUnsupportedType { ty [LalinCode.CodeType] },
    EmitterFallbackUnsupportedOp { op_description [str] },
    EmitterFallbackTargetMissing { feature [LalinStencil.StencilVectorFeatureRequirement] },
  },
  sum. ScheduleEmitterCapability {
    ScheduleEmitterExecutable {
      variant_unique,
      kind [LalinSchedule.ScheduleEmitterKind],
      reason [str],
      proofs [many [LalinSchedule.ScheduleProof]],
    },
    ScheduleEmitterRejected {
      variant_unique,
      kind [LalinSchedule.ScheduleEmitterKind],
      rejects [many [LalinSchedule.ScheduleReject]],
    },
  },
  sum. ScheduleCandidate {
    ScheduleVectorCandidate {
      variant_unique,
      form [LalinSchedule.ScheduleForm],
      capability [LalinSchedule.ScheduleEmitterCapability],
    },
    ScheduleScalarCandidate {
      variant_unique,
      form [LalinSchedule.ScheduleForm],
      capability [LalinSchedule.ScheduleEmitterCapability],
    },
    ScheduleClosedFormCandidate {
      variant_unique,
      capability [LalinSchedule.ScheduleEmitterCapability],
    },
  },
  product. ScheduleCandidateCursor {
    interned,
    candidates [many [LalinSchedule.ScheduleCandidate]],
    ordinal [number],
    rejects [many [LalinSchedule.ScheduleReject]],
  },
  sum. ScheduleCandidateDecision {
    ScheduleCandidateSelected {
      variant_unique,
      form [LalinSchedule.ScheduleForm],
      capability [LalinSchedule.ScheduleEmitterExecutable],
      rejected_alternatives [many [LalinSchedule.ScheduleReject]],
    },
    ScheduleCandidateRejected {
      variant_unique,
      rejects [many [LalinSchedule.ScheduleReject]],
    },
  },
  product. SchedulePlanInput {
    interned,
    kernel [LalinKernel.KernelPlanned],
    candidates [many [LalinSchedule.ScheduleCandidate]],
  },
  sum. SchedulePlanSelection {
    ScheduleSelectionNoPlan { variant_unique, rejects [many [LalinSchedule.ScheduleReject]], },
    ScheduleSelectionPlanned {
      variant_unique,
      form [LalinSchedule.ScheduleForm],
      capability [LalinSchedule.ScheduleEmitterExecutable],
      rejected_alternatives [many [LalinSchedule.ScheduleReject]],
    },
  },
  sum. ScheduleTargetFactContribution {
    ScheduleTargetFactIgnored,
    ScheduleTargetVectorShape { variant_unique, shape [LalinBackend.BackShape], },
    ScheduleTargetUnrollPreference { variant_unique, unroll [number], },
  },
  product. ScheduleTargetProjection { contributions [many [LalinSchedule.ScheduleTargetFactContribution]], },
  sum. ScheduleVectorLaneEvidence {
    ScheduleVectorLaneAvailable { variant_unique, lane [LalinKernel.KernelLane], },
    ScheduleVectorLaneUnavailable { variant_unique, reason [str], },
  },
  sum. ScheduleCandidateContribution {
    ScheduleCandidateContributed { variant_unique, candidate [LalinSchedule.ScheduleCandidate], },
    ScheduleCandidateNotContributed,
  },
  sum. KernelSchedule {
    ScheduleNoPlan {
      variant_unique,
      kernel [LalinKernel.KernelId],
      rejects [many [LalinSchedule.ScheduleReject]],
    },
    ScheduleKernelRejected {
      variant_unique,
      subject [LalinKernel.KernelSubject],
      rejects [many [LalinKernel.KernelReject]],
    },
    SchedulePlanned {
      variant_unique,
      field. id [LalinSchedule.ScheduleId],
      kernel [LalinKernel.KernelId],
      form [LalinSchedule.ScheduleForm],
      proofs [many [LalinSchedule.ScheduleProof]],
      rejected_alternatives [many [LalinSchedule.ScheduleReject]],
    },
  },
  product. ScheduleModulePlan {
    interned,
    field. module [LalinCode.CodeModuleId],
    target [LalinSchedule.ScheduleTarget],
    schedules [many [LalinSchedule.KernelSchedule]],
  },
}