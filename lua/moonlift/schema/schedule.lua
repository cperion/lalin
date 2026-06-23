local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonSchedule {
  product. ScheduleId { interned, text [str], },
  product. ScheduleTarget { interned, target [ty "MoonBack.BackTargetModel"], },
  sum. LaneShape {
    LaneScalar,
    LaneVector { variant_unique, elem_ty [ty "MoonCode.CodeType"], lanes [number], },
  },
  sum. TailPlan { TailNone, TailScalar, TailMasked, TailPeel { variant_unique, elems [number], }, },
  sum. ScheduleKind {
    ScheduleScalarIndex,
    ScheduleScalarPointer,
    ScheduleVector {
      variant_unique,
      lanes [ty "MoonSchedule.LaneShape"],
      unroll [number],
      interleave [number],
      tail [ty "MoonSchedule.TailPlan"],
    },
    ScheduleClosedForm,
  },
  sum. ScheduleProof {
    ScheduleProofTarget { variant_unique, reason [str], },
    ScheduleProofMemory { variant_unique, proof [ty "MoonMem.MemProof"], },
    ScheduleProofAlgebra { variant_unique, proof [ty "MoonValue.AlgebraProof"], },
    ScheduleProofProfit { variant_unique, reason [str], },
  },
  sum. ScheduleReject {
    ScheduleRejectTarget { variant_unique, reason [str], },
    ScheduleRejectMemory { variant_unique, reason [str], },
    ScheduleRejectAlgebra { variant_unique, reason [str], },
    ScheduleRejectProfit { variant_unique, reason [str], },
  },
  sum. KernelSchedule {
    ScheduleNoPlan {
      variant_unique,
      kernel [ty "MoonKernel.KernelId"],
      rejects [many [ty "MoonSchedule.ScheduleReject"]],
    },
    SchedulePlanned {
      variant_unique,
      field "id" [ty "MoonSchedule.ScheduleId"],
      kernel [ty "MoonKernel.KernelId"],
      kind [ty "MoonSchedule.ScheduleKind"],
      proofs [many [ty "MoonSchedule.ScheduleProof"]],
      rejected_alternatives [many [ty "MoonSchedule.ScheduleReject"]],
    },
  },
  product. ScheduleModulePlan {
    interned,
    field "module" [ty "MoonCode.CodeModuleId"],
    target [ty "MoonSchedule.ScheduleTarget"],
    schedules [many [ty "MoonSchedule.KernelSchedule"]],
  },
}
