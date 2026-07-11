local S = require("lalin.schema.dsl")
S.use()

return schema. LalinParse {
  sum. ParseControlDiagnosticOwner {
    ParseFunctionControlOwner,
    ParseRegionControlOwner,
  },
  sum. ParseUnsupportedControl {
    ParseUnsupportedWhile,
    ParseUnsupportedBreak,
    ParseUnsupportedContinue,
  },
  sum. ParsedCallProjection {
    ParsedRegularCall,
    ParsedVariantConstructorCall { variant_unique, type_name [str], variant_name [str], },
  },
  product. ParseIssue { interned, message [str], offset [number], line [number], col [number], },
  sum. ParseResult {
    ParseResult {
      variant_unique,
      field. module [LalinTree.Module],
      issues [many [LalinParse.ParseIssue]],
    },
  },
}
