local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCodeValidation {
  product. CodeFunctionIdEntry {
    interned,
    field. id [LalinCode.CodeFuncId],
    func [LalinCode.CodeFunc],
  },
  product. CodeExternIdEntry {
    interned,
    field. id [LalinCode.CodeExternId],
    field. extern [LalinCode.CodeExtern],
  },
  product. CodeGlobalIdEntry {
    interned,
    field. id [LalinCode.CodeGlobalId],
    global [LalinCode.CodeGlobal],
  },
  product. CodeDataIdEntry {
    interned,
    field. id [LalinCode.CodeDataId],
    data [LalinCode.CodeData],
  },
  product. CodeBlockIdEntry {
    interned,
    field. id [LalinCode.CodeBlockId],
    block [LalinCode.CodeBlock],
  },
  product. CodeLocalIdEntry {
    interned,
    field. id [LalinCode.CodeLocalId],
    local_value [LalinCode.CodeLocal],
  },
  product. CodeValueTypeEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    ty [LalinCode.CodeType],
  },
  product. CodeInstIdEntry {
    interned,
    field. id [LalinCode.CodeInstId],
    inst [LalinCode.CodeInst],
  },
  product. CodeTermIdEntry {
    interned,
    field. id [LalinCode.CodeTermId],
    term [LalinCode.CodeTerm],
  },
  product. CodeRelocIdEntry {
    interned,
    field. id [LalinCode.CodeRelocId],
    reloc [LalinCode.CodeReloc],
  },
  product. CodeRelocProjection {
    interned,
    entries [many [LalinCodeValidation.CodeRelocIdEntry]],
  },
  product. CodeRelocProjectionResult {
    interned,
    projection [LalinCodeValidation.CodeRelocProjection],
    issues [many [LalinCode.CodeIssue]],
  },

  product. CodeValidationModuleProjection {
    interned,
    field. module [LalinCode.CodeModule],
    signatures [LalinCode.CodeSigProjection],
    functions [many [LalinCodeValidation.CodeFunctionIdEntry]],
    externs [many [LalinCodeValidation.CodeExternIdEntry]],
    globals [many [LalinCodeValidation.CodeGlobalIdEntry]],
    data [many [LalinCodeValidation.CodeDataIdEntry]],
    relocs [many [LalinCodeValidation.CodeRelocIdEntry]],
  },
  product. CodeValidationFunctionProjection {
    interned,
    func [LalinCode.CodeFunc],
    blocks [many [LalinCodeValidation.CodeBlockIdEntry]],
    locals [many [LalinCodeValidation.CodeLocalIdEntry]],
    values [many [LalinCodeValidation.CodeValueTypeEntry]],
    insts [many [LalinCodeValidation.CodeInstIdEntry]],
    terms [many [LalinCodeValidation.CodeTermIdEntry]],
  },

  product. CodeValidationModuleInput {
    interned,
    projection [LalinCodeValidation.CodeValidationModuleProjection],
  },
  product. CodeValidationFunctionInput {
    interned,
    module_projection [LalinCodeValidation.CodeValidationModuleProjection],
    function_projection [LalinCodeValidation.CodeValidationFunctionProjection],
  },
  product. CodeValidationBlockInput {
    interned,
    module_projection [LalinCodeValidation.CodeValidationModuleProjection],
    function_projection [LalinCodeValidation.CodeValidationFunctionProjection],
    block [LalinCode.CodeBlock],
  },
  product. CodeValidationInstructionInput {
    interned,
    module_projection [LalinCodeValidation.CodeValidationModuleProjection],
    function_projection [LalinCodeValidation.CodeValidationFunctionProjection],
    block [LalinCode.CodeBlock],
    inst [LalinCode.CodeInst],
  },
  product. CodeValidationTermInput {
    interned,
    module_projection [LalinCodeValidation.CodeValidationModuleProjection],
    function_projection [LalinCodeValidation.CodeValidationFunctionProjection],
    block [LalinCode.CodeBlock],
    term [LalinCode.CodeTerm],
  },
  product. CodeValidationStep {
    interned,
    issues [many [LalinCode.CodeIssue]],
  },
  product. CodeValidationProjectionResult {
    interned,
    projection [LalinCodeValidation.CodeValidationModuleProjection],
    issues [many [LalinCode.CodeIssue]],
  },

  sum. CodeValidationDefinition {
    CodeValidationNoDefinition { variant_unique, },
    CodeValidationDefinesValue {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      ty [LalinCode.CodeType],
    },
  },
  sum. CodeValueTypeLookup {
    CodeValueTypeFound { variant_unique, entry [LalinCodeValidation.CodeValueTypeEntry], },
    CodeValueTypeMissing { variant_unique, field. value [LalinCode.CodeValueId], },
  },
  sum. CodeBlockLookup {
    CodeBlockFound { variant_unique, entry [LalinCodeValidation.CodeBlockIdEntry], },
    CodeBlockMissing { variant_unique, field. id [LalinCode.CodeBlockId], },
  },
  sum. CodeLocalLookup {
    CodeLocalFound { variant_unique, entry [LalinCodeValidation.CodeLocalIdEntry], },
    CodeLocalMissing { variant_unique, field. id [LalinCode.CodeLocalId], },
  },
  sum. CodeFunctionLookup {
    CodeFunctionFound { variant_unique, entry [LalinCodeValidation.CodeFunctionIdEntry], },
    CodeFunctionMissing { variant_unique, field. id [LalinCode.CodeFuncId], },
  },
  sum. CodeExternLookup {
    CodeExternFound { variant_unique, entry [LalinCodeValidation.CodeExternIdEntry], },
    CodeExternMissing { variant_unique, field. id [LalinCode.CodeExternId], },
  },
  sum. CodeGlobalLookup {
    CodeGlobalFound { variant_unique, entry [LalinCodeValidation.CodeGlobalIdEntry], },
    CodeGlobalMissing { variant_unique, field. id [LalinCode.CodeGlobalId], },
  },
  sum. CodeDataLookup {
    CodeDataFound { variant_unique, entry [LalinCodeValidation.CodeDataIdEntry], },
    CodeDataMissing { variant_unique, field. id [LalinCode.CodeDataId], },
  },

  sum. CodeValidateResult {
    CodeValidateOk {
      variant_unique,
      field. module [LalinCode.CodeModule],
      projection [LalinCodeValidation.CodeValidationModuleProjection],
    },
    CodeValidateFailed {
      variant_unique,
      issues [many [LalinCode.CodeIssue]],
      projection [LalinCodeValidation.CodeValidationModuleProjection],
    },
  },
}