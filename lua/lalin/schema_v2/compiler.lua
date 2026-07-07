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

  product. CompilerSession {
    interned,
    source_text [str],
    source_name [str],
  },

  sum. CompilerArtifact {
    CompilerArtifactC { source [str], header [str] },
    CompilerArtifactError { message [str] },
  },
}