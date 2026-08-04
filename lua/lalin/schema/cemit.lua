local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCEmit {
  product. CEmitHelperEntry {
    interned,
    helper_key [str],
    helper [LalinCEmit.CEmitHelper],
  },
  product. CEmitHelper {
    interned,
    field. id [str],
    source [str],
  },
  product. CEmitCSigEntry {
    interned,
    c_key [str],
    csig [LalinC.CBackendFuncSig],
  },
  product. CEmitMachine {
    interned,
    spine [LalinLower.LowerBackSpine],
    c_sigs [many [LalinCEmit.CEmitCSigEntry]],
    c_sig_order [many [LalinC.CBackendFuncSig]],
    helpers [many [LalinCEmit.CEmitHelperEntry]],
    helper_order [many [LalinCEmit.CEmitHelperEntry]],
  },
  product. CEmitBlockProjection {
    interned,
    blocks [many [LalinC.CBackendBlock]],
  },
  sum. CEmitBlockLookup {
    CEmitBlockFound { variant_unique, block [LalinC.CBackendBlock], },
    CEmitBlockMissing { variant_unique, label [LalinC.CBackendLabel], },
  },
  sum. CEmitIssue {
    CEmitIssueMissingSig { variant_unique, sig [LalinCode.CodeSigId], },
    CEmitIssueUnsupportedType {
      variant_unique,
      ty [LalinCode.CodeType],
      reason [str],
    },
    CEmitIssueUnsupportedOp {
      variant_unique,
      op [str],
      reason [str],
    },
    CEmitIssueHelperError { variant_unique, helper [str], reason [str], },
    CEmitIssueInternal { variant_unique, reason [str], },
  },
  sum. CEmitModuleResult {
    CEmitOk {
      variant_unique,
      field. unit [LalinC.CBackendUnit],
    },
    CEmitFailed {
      variant_unique,
      issues [many [LalinCEmit.CEmitIssue]],
    },
  },
  product. CEmitFuncResult {
    interned,
    source [str],
    func_name [str],
    helpers [many [LalinCEmit.CEmitHelperEntry]],
  },
}