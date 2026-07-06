local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCodeValidation {
  product. CodeBackendSpine {
    interned,
    field. module [LalinCode.CodeModule],
    graph [LalinGraph.CodeGraph],
    target [optional [LalinC.CBackendTarget]],
    layout_env [optional [LalinSem.LayoutEnv]],
  },
  product. CodeRelocCheckEntry {
    interned,
    reloc_key [str],
    checked [bool],
  },
  product. CodeValidationMachine {
    interned,
    field. module [LalinCode.CodeModule],
    graph [LalinGraph.CodeGraph],
    spine [LalinCodeValidation.CodeBackendSpine],
    issues [many [LalinCode.CodeIssue]],
    relocs [many [LalinCodeValidation.CodeRelocCheckEntry]],
  },
  sum. CodeValidateResult {
    CodeValidateOk {
      variant_unique,
      field. module [LalinCode.CodeModule],
    },
    CodeValidateFailed {
      variant_unique,
      issues [many [LalinCode.CodeIssue]],
    },
  },
}
