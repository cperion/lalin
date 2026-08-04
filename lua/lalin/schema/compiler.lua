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
    contracts [LalinCode.CodeContractFactSet],
    layout_env [LalinSem.LayoutEnv],
  },
  product. CompilerCBackendResult {
    interned,
    unit [LalinC.CBackendUnit],
    report [LalinC.CBackendValidationReport],
  },
  sum. CompilerCBackendOutcome {
    CompilerCBackendEmitted {
      variant_unique,
      backend [LalinCompiler.CompilerCBackendResult],
      emitter [LalinCEmit.CEmitMachine],
    },
    CompilerCBackendRejected {
      variant_unique,
      issues [many [LalinLower.LowerIssue]],
    },
  },
  product. CompilerCBackendEmissionInput {
    interned,
    spine [LalinLower.LowerBackSpine],
  },
  product. CompilerCodeGenerationInput {
    field. module [LalinCode.CodeModule],
    contracts [LalinCode.CodeContractFactSet],
    target [LalinC.CBackendTarget],
  },
  product. CompilerCCodegenRequest {
    interned,
    result [LalinCompiler.CodeResult],
    target [LalinC.CBackendTarget],
    compiler [LalinStencil.StencilCompilerPolicy],
  },

  sum. TreeCodeImplementation {
    TreeCodeSchemaV2Implementation,
  },

  product. CompilerImplementationRegistry {
    interned,
    tree_code [LalinCompiler.TreeCodeImplementation],
  },

  product. CompilerImplementationOwner { interned, },

  product. CompilerSession {
    interned,
    source_text [str],
    source_name [str],
  },
  -- Typed compile inputs for the public session boundary.  The loader and
  -- builder surfaces converge here as named ASDL alternatives: a parsed
  -- document, a parsed decl array, or an already-built LalinTree module.
  -- Each leaf owns producing the LalinTree.Module for the phase pipeline;
  -- there is no source recovery and no adapter to an untyped AST.
  sum. CompilerModuleInput {
    CompilerModuleInputParsedDocument {
      variant_unique,
      document [LalinParse.ParsedDocument],
      source_name [str],
    },
    CompilerModuleInputParsedDecls {
      variant_unique,
      field. decls [many [LalinParse.ParsedDecl]],
      source_name [str],
    },
    CompilerModuleInputTree {
      variant_unique,
      field. module [LalinTree.Module],
      source_name [str],
    },
  },

  product. CompilerParsedSession {
    interned,
    input [LalinCompiler.CompilerModuleInput],
  },

  sum. CompilerArtifact {
    CompilerArtifactC { source [str], header [str], unit [LalinC.CBackendUnit] },
    CompilerArtifactError { message [str] },
  },
}