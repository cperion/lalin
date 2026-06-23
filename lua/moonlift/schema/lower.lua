local S = require("moonlift.schema.dsl")
S.use()

return schema. MoonLower {
  product. LowerFragmentId { interned, text [str], },
  sum. LowerTarget { LowerTargetBack, LowerTargetC, },
  sum. LowerCover {
    LowerCoverFunction { variant_unique, func [ty "MoonCode.CodeFuncId"], },
    LowerCoverLoop { variant_unique, loop [ty "MoonGraph.GraphLoopId"], },
    LowerCoverBlock {
      variant_unique,
      func [ty "MoonCode.CodeFuncId"],
      block [ty "MoonCode.CodeBlockId"],
    },
    LowerCoverBlockRange {
      variant_unique,
      func [ty "MoonCode.CodeFuncId"],
      entry [ty "MoonCode.CodeBlockId"],
      exit [ty "MoonCode.CodeBlockId"],
    },
  },
  sum. LowerStrategy {
    LowerStrategyCode { variant_unique, reason [str], },
    LowerStrategyKernel {
      variant_unique,
      kernel [ty "MoonKernel.KernelId"],
      schedule [ty "MoonSchedule.ScheduleId"],
    },
    LowerStrategyClosedForm {
      variant_unique,
      kernel [ty "MoonKernel.KernelId"],
      fact [ty "MoonValue.ClosedFormFact"],
    },
  },
  sum. LowerProof {
    LowerProofCoverage { variant_unique, reason [str], },
    LowerProofKernel { variant_unique, kernel [ty "MoonKernel.KernelId"], reason [str], },
    LowerProofSchedule { variant_unique, schedule [ty "MoonSchedule.ScheduleId"], reason [str], },
    LowerProofFallback { variant_unique, reason [str], },
  },
  sum. LowerIssue {
    LowerIssueOverlap {
      variant_unique,
      a [ty "MoonLower.LowerFragmentId"],
      b [ty "MoonLower.LowerFragmentId"],
    },
    LowerIssueGap { variant_unique, func [ty "MoonCode.CodeFuncId"], reason [str], },
    LowerIssueFallback { variant_unique, cover [ty "MoonLower.LowerCover"], reason [str], },
  },
  product. LowerFragment {
    interned,
    field "id" [ty "MoonLower.LowerFragmentId"],
    cover [ty "MoonLower.LowerCover"],
    strategy [ty "MoonLower.LowerStrategy"],
    proofs [many [ty "MoonLower.LowerProof"]],
    issues [many [ty "MoonLower.LowerIssue"]],
  },
  product. LowerFuncPlan {
    interned,
    func [ty "MoonCode.CodeFuncId"],
    fragments [many [ty "MoonLower.LowerFragment"]],
  },
  product. LowerModule {
    interned,
    field "module" [ty "MoonCode.CodeModuleId"],
    target [ty "MoonLower.LowerTarget"],
    kernels [ty "MoonKernel.KernelModulePlan"],
    schedules [ty "MoonSchedule.ScheduleModulePlan"],
    funcs [many [ty "MoonLower.LowerFuncPlan"]],
    issues [many [ty "MoonLower.LowerIssue"]],
  },
  product. LowerValidationReport { interned, issues [many [ty "MoonLower.LowerIssue"]], },
}
