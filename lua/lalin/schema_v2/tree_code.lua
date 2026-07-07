local S = require("lalin.schema.dsl")
S.use()

return schema. LalinTreeCode {
  product. TreeCodeModuleFacts {
    interned,
    module_name [str],
    layout_env [LalinSem.LayoutEnv],
    target [optional [LalinC.CBackendTarget]],
    const_env [LalinBind.ConstEnv],
    variant_defs [many [LalinTreeCode.TreeCodeVariantDefEntry]],
  },
  product. TreeCodeSigEntry {
    interned,
    sig_name [str],
    sig [LalinCode.CodeSig],
  },
  product. TreeCodeModuleSigState {
    module_name [str],
    code_sigs [many [LalinTreeCode.TreeCodeSigEntry]],
    code_sig_order [many [LalinCode.CodeSig]],
  },
  product. TreeCodeFuncRegistrationEntry {
    interned,
    func_name [str],
    registration [LalinTreeCode.TreeCodeFuncRegistration],
  },
  product. TreeCodeExternEntry {
    interned,
    extern_name [str],
    extern [LalinCode.CodeExtern],
  },
  product. TreeCodeModuleRegistrationState {
    funcs [many [LalinTreeCode.TreeCodeFuncRegistrationEntry]],
    externs [many [LalinTreeCode.TreeCodeExternEntry]],
    extern_order [many [LalinCode.CodeExtern]],
  },
  product. TreeCodeModuleEmissionState {
    generated_data [many [LalinCode.CodeData]],
    counters [many [LalinTreeCode.TreeCodeCounterEntry]],
  },
  product. TreeCodeFuncRegistration {
    interned,
    field. id [LalinCode.CodeFuncId],
    sig [LalinCode.CodeSigId],
  },
  product. TreeCodeVariant {
    interned,
    field. name [str],
    tag [number],
    payload [LalinType.Type],
    fields [many [LalinType.FieldDecl]],
  },
  product. TreeCodeVariantEntry {
    interned,
    variant_name [str],
    variant [LalinTreeCode.TreeCodeVariant],
  },
  product. TreeCodeVariantDef {
    interned,
    owner [LalinType.Type],
    variants [many [LalinTreeCode.TreeCodeVariantEntry]],
  },
  product. TreeCodeVariantDefEntry {
    interned,
    type_name [str],
    def [LalinTreeCode.TreeCodeVariantDef],
  },
  product. TreeCodeBindingValueEntry {
    interned,
    binding_name [str],
    field. value [LalinCode.CodeValueId],
  },
  product. TreeCodeLocalBindingEntry {
    interned,
    binding_name [str],
    binding [LalinTreeCode.TreeCodeLocalBinding],
  },
  product. TreeCodeBindingSnapshot {
    bindings [many [LalinTreeCode.TreeCodeBindingValueEntry]],
    locals_by_key [many [LalinTreeCode.TreeCodeLocalBindingEntry]],
  },
  product. TreeCodeLocalBinding {
    interned,
    field. id [LalinCode.CodeLocalId],
    field. ty [LalinCode.CodeType],
    source_ty [LalinType.Type],
  },
  product. TreeCodeBlockBuilder {
    field. id [LalinCode.CodeBlockId],
    field. name [str],
    params [many [LalinCode.CodeParam]],
    insts [many [LalinCode.CodeInst]],
    origin [LalinCode.CodeOrigin],
  },
  sum. TreeCodeControlRegion {
    TreeCodeExprControlRegion {
      variant_unique,
      exit_id [LalinCode.CodeBlockId],
      targets [many [LalinTreeCode.TreeCodeControlTargetEntry]],
    },
    TreeCodeStmtControlRegion {
      variant_unique,
      exit_id [LalinCode.CodeBlockId],
      targets [many [LalinTreeCode.TreeCodeControlTargetEntry]],
    },
  },
  product. TreeCodeControlTarget {
    interned,
    field. id [LalinCode.CodeBlockId],
    params [many [LalinCode.CodeParam]],
  },
  product. TreeCodeControlTargetEntry {
    interned,
    label_name [str],
    target [LalinTreeCode.TreeCodeControlTarget],
  },
  product. TreeCodeBindingState {
    values_by_key [many [LalinTreeCode.TreeCodeBindingValueEntry]],
    locals_by_key [many [LalinTreeCode.TreeCodeLocalBindingEntry]],
  },
  product. TreeCodeBindingPresenceEntry {
    interned,
    binding_name [str],
  },
  product. TreeCodeResidenceFacts {
    addressed_by_key [many [LalinTreeCode.TreeCodeBindingPresenceEntry]],
    mutable_by_key [many [LalinTreeCode.TreeCodeBindingPresenceEntry]],
  },
  product. TreeCodeEmissionState {
    locals [many [LalinCode.CodeLocal]],
    blocks [many [LalinCode.CodeBlock]],
    current_blocks [many [LalinTreeCode.TreeCodeBlockBuilder]],
  },
  product. TreeCodeCounterState {
    values_by_name [many [LalinTreeCode.TreeCodeCounterEntry]],
  },
  product. TreeCodeCounterEntry {
    interned,
    counter_name [str],
    next_value [number],
  },
  product. TreeCodeAlphaRenameEntry {
    interned,
    binding_name [str],
    renamed [str],
  },
  product. TreeCodeAlphaState {
    renamed_by_key [many [LalinTreeCode.TreeCodeAlphaRenameEntry]],
    current_suffix_by_slot [many [LalinTreeCode.TreeCodeAlphaSuffixEntry]],
    seq [number],
  },
  product. TreeCodeAlphaSuffixEntry {
    interned,
    slot_name [str],
    suffix [str],
  },
  product. TreeCodeControlRegionSlot {
    interned,
    slot_name [str],
    region [LalinTreeCode.TreeCodeControlRegion],
  },
  product. TreeCodeControlFlag {
    interned,
    flag_name [str],
    enabled [bool],
  },
  product. TreeCodeControlState {
    current_regions [many [LalinTreeCode.TreeCodeControlRegionSlot]],
    flags [many [LalinTreeCode.TreeCodeControlFlag]],
  },
  product. TreeCodeFuncFacts {
    module_facts [LalinTreeCode.TreeCodeModuleFacts],
    sigs [LalinTreeCode.TreeCodeModuleSigState],
    registrations [LalinTreeCode.TreeCodeModuleRegistrationState],
    module_emission [LalinTreeCode.TreeCodeModuleEmissionState],
    func_name [str],
  },
  product. TreeCodeFuncState {
    bindings [LalinTreeCode.TreeCodeBindingState],
    residence [LalinTreeCode.TreeCodeResidenceFacts],
    emission [LalinTreeCode.TreeCodeEmissionState],
    counters [LalinTreeCode.TreeCodeCounterState],
    alpha [LalinTreeCode.TreeCodeAlphaState],
    control [LalinTreeCode.TreeCodeControlState],
  },
  product. TreeCodeFuncLoweringStart {
    facts [LalinTreeCode.TreeCodeFuncFacts],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeModuleParts {
    module_facts [LalinTreeCode.TreeCodeModuleFacts],
    sigs [LalinTreeCode.TreeCodeModuleSigState],
    registrations [LalinTreeCode.TreeCodeModuleRegistrationState],
    emission [LalinTreeCode.TreeCodeModuleEmissionState],
  },
  product. TreeCodeItemRegisterInput {
    interned,
    module_facts [LalinTreeCode.TreeCodeModuleFacts],
    sigs [LalinTreeCode.TreeCodeModuleSigState],
    registrations [LalinTreeCode.TreeCodeModuleRegistrationState],
  },
  product. TreeCodeItemContractsInput {
    interned,
    module_facts [LalinTreeCode.TreeCodeModuleFacts],
    sigs [LalinTreeCode.TreeCodeModuleSigState],
    registrations [LalinTreeCode.TreeCodeModuleRegistrationState],
    emission [LalinTreeCode.TreeCodeModuleEmissionState],
    contract_facts [many [LalinCode.CodeFuncContractFact]],
  },
  product. TreeCodeItemLowerInput {
    -- NOTE: NOT interned - must create fresh instance per compilation to
    -- avoid state leaks through shared mutable funcs/data/globals tables.

    module_facts [LalinTreeCode.TreeCodeModuleFacts],
    sigs [LalinTreeCode.TreeCodeModuleSigState],
    registrations [LalinTreeCode.TreeCodeModuleRegistrationState],
    emission [LalinTreeCode.TreeCodeModuleEmissionState],
    mod_name [str],
    funcs [many [LalinCode.CodeFunc]],
    data [many [LalinCode.CodeData]],
    globals [many [LalinCode.CodeGlobal]],
  },
  sum. TreeCodeInput {
    TreeCodeExprInput {
      variant_unique,
      facts [LalinTreeCode.TreeCodeFuncFacts],
      state [LalinTreeCode.TreeCodeFuncState],
    },
    TreeCodePlaceInput {
      variant_unique,
      facts [LalinTreeCode.TreeCodeFuncFacts],
      state [LalinTreeCode.TreeCodeFuncState],
    },
    TreeCodeStmtInput {
      variant_unique,
      facts [LalinTreeCode.TreeCodeFuncFacts],
      state [LalinTreeCode.TreeCodeFuncState],
    },
    TreeCodeControlInput {
      variant_unique,
      facts [LalinTreeCode.TreeCodeFuncFacts],
      state [LalinTreeCode.TreeCodeFuncState],
    },
  },
  product. TreeCodeContractInput {
    interned,
    module_facts [LalinTreeCode.TreeCodeModuleFacts],
    sigs [LalinTreeCode.TreeCodeModuleSigState],
    func_name [str],
    func_id [LalinCode.CodeFuncId],
  },
  product. TreeCodeStateResult {
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeCounterResult {
    field. value [number],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeBindingKeyResult {
    binding_name [str],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeValueIdResult {
    field. value [LalinCode.CodeValueId],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeInstIdResult {
    field. id [LalinCode.CodeInstId],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeTermIdResult {
    field. id [LalinCode.CodeTermId],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeBlockIdResult {
    field. id [LalinCode.CodeBlockId],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeTermResult {
    field. term [LalinCode.CodeTerm],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeLocalResult {
    field. id [LalinCode.CodeLocalId],
    field. ty [LalinCode.CodeType],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeAlphaResult {
    renamed_by_key [many [LalinTreeCode.TreeCodeAlphaRenameEntry]],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeControlExitResult {
    saw_exit [bool],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeFallthroughResult {
    falls [bool],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeExprResult {
    interned,
    field. value [optional [LalinCode.CodeValueId]],
    field. ty [LalinCode.CodeType],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodePlaceResult {
    interned,
    place [LalinCode.CodePlace],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeIndexPlaceResult {
    place [LalinCode.CodePlace],
    index [LalinCode.CodeValueId],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeViewPartsResult {
    data [LalinCode.CodeValueId],
    len [LalinCode.CodeValueId],
    stride [LalinCode.CodeValueId],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeStmtResult {
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeParamResult {
    field. param [LalinCode.CodeParam],
    field. ty [LalinCode.CodeType],
    state [LalinTreeCode.TreeCodeFuncState],
  },
  product. TreeCodeFuncParts {
    interned,
    field. name [str],
    linkage [LalinCode.CodeLinkage],
    params [many [LalinType.Param]],
    result [LalinType.Type],
    body [many [LalinTree.Stmt]],
  },
  product. TreeCodeContractResult {
    interned,
    fact [LalinCode.CodeFuncContractFact],
  },
}