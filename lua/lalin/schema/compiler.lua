local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCompiler {
  sum. CodeResultIssue {
    CodeResultIssueUnexpectedValue {
      variant_unique,
      expected [str],
      actual [str],
    },
    CodeResultIssueInvalidField {
      variant_unique,
      field. name [str],
      expected [str],
      actual [str],
    },
    CodeResultIssueInvalidCode {
      variant_unique,
      issue [LalinCode.CodeIssue],
    },
  },

  product. CodeResultReport {
    interned,
    issues [many [LalinCompiler.CodeResultIssue]],
  },

  product. CodeResult {
    interned,
    field. module [LalinCode.CodeModule],
    contracts [many [LalinCode.CodeFuncContractFact]],
    layout_env [LalinSem.LayoutEnv],
  },

  product. CompilerCBackendResult {
    interned,
    unit [LalinC.CBackendUnit],
    report [LalinC.CBackendValidationReport],
  },

  sum. TreeCodeImplementation {
    TreeCodeCanonicalImplementation,
  },

  product. CompilerImplementationRegistry {
    interned,
    tree_code [LalinCompiler.TreeCodeImplementation],
  },

  product. CompilerImplementationOwner { interned, },
}
