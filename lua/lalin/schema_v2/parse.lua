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

  -- Parsed intermediate types: carry unresolved type-annotation source text.
  -- to_module evaluates ty_source fields in the dsl env to produce Ty.Type.

  product. ParsedField {
    interned,
    field. name [str],
    field. ty_source [str],
    field. anonymous [bool],
    field. implicit [bool],
  },

  product. ParsedVariant {
    interned,
    field. name [str],
    fields [many [LalinParse.ParsedField]],
  },

  product. ParsedExit {
    interned,
    field. name [str],
    fields [many [LalinParse.ParsedField]],
  },

  product. ParsedEntryBlock {
    interned,
    field. kind [str],
    field. name [str],
    state [many [LalinParse.ParsedField]],
    body [many [LalinParse.ParsedStmt]],
  },

  product. ParsedMetaRef {
    interned,
    path [many [LalinCore.Name]],
  },

  sum. ParsedStmt {
    StmtKnown { variant_unique, field. stmt [LalinTree.Stmt], },
    StmtLetParsed { variant_unique, field. name [str], field. ty_source [str], field. init [LalinTree.Expr], },
    StmtVarParsed { variant_unique, field. name [str], field. ty_source [str], field. init [LalinTree.Expr], },
    StmtRequiresParsed { variant_unique, exprs [many [LalinTree.Expr]], },
  },


  sum. ParsedDecl {
    ParsedFunc {
      variant_unique,
      field. name [str],
      qualifier [many [LalinCore.Name]],
      field. implicit_self [bool],
      params [many [LalinParse.ParsedField]],
      field. result_source [str],
      body [many [LalinParse.ParsedStmt]],
      field. has_control [bool],
    },
    ParsedStruct {
      variant_unique,
      field. name [str],
      fields [many [LalinParse.ParsedField]],
    },
    ParsedExtern {
      variant_unique,
      field. name [str],
      qualifier [many [LalinCore.Name]],
      params [many [LalinParse.ParsedField]],
      field. result_source [str],
      field. symbol [str],
    },
    ParsedUnion {
      variant_unique,
      field. name [str],
      variants [many [LalinParse.ParsedVariant]],
    },
    ParsedHandle {
      variant_unique,
      field. name [str],
      qualifier [many [LalinCore.Name]],
      field. repr_source [str],
      field. invalid [str],
      field. domain_source [str],
      field. target_source [str],
    },
    ParsedMetaAssign {
      variant_unique,
      target [many [LalinCore.Name]],
      field. value_source [str],
      meta_ref [LalinParse.ParsedMetaRef],
    },
    ParsedExprFragment {
      variant_unique,
      field. expr [LalinTree.Expr],
    },
    ParsedStmtFragment {
      variant_unique,
      body [many [LalinParse.ParsedStmt]],
    },
  },

  product. ParsedDocument {
    interned,
    body [many [LalinParse.ParsedDecl]],
    field. source [str],
    field. chunkname [str],
  },
}