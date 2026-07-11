local S = require("lalin.schema.dsl")
S.use()

return schema. LalinTreeLower {
  product. TreeLowerModuleFacts {
    interned,
    module_name [str],
    layout_env [LalinSem.LayoutEnv],
    target [optional [LalinC.CBackendTarget]],
    const_env [LalinBind.ConstEnv],
    variant_defs [many [LalinTreeLower.TreeLowerVariantDefEntry]],
  },
  sum. TreeLowerCodeSigRequirement {
    TreeLowerFunctionSigRequirement,
    TreeLowerExternSigRequirement,
    TreeLowerDirectCallSigRequirement,
    TreeLowerIndirectCallSigRequirement,
    TreeLowerClosureSigRequirement,
    TreeLowerHelperSigRequirement,
  },
  product. TreeLowerSigEntry {
    interned,
    sig_id [LalinCode.CodeSigId],
    sig [LalinCode.CodeSig],
    requirement [LalinTreeLower.TreeLowerCodeSigRequirement],
  },
  product. TreeLowerModuleSigState {
    module_name [str],
    code_sigs [many [LalinTreeLower.TreeLowerSigEntry]],
    code_sig_order [many [LalinCode.CodeSig]],
  },
  product. TreeLowerCallTargetResult {
    target [LalinCode.CodeCallTarget],
    sig [LalinCode.CodeSigId],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerFunctionRegistrationEntry {
    interned,
    func_name [str],
    registration [LalinTreeLower.TreeLowerFunctionRegistration],
  },
  product. TreeLowerExternEntry {
    interned,
    extern_name [str],
    extern [LalinCode.CodeExtern],
  },
  product. TreeLowerModuleRegistrationState {
    funcs [many [LalinTreeLower.TreeLowerFunctionRegistrationEntry]],
    externs [many [LalinTreeLower.TreeLowerExternEntry]],
    extern_order [many [LalinCode.CodeExtern]],
  },
  product. TreeLowerModuleEmissionState {
    generated_data [many [LalinCode.CodeData]],
    counters [many [LalinTreeLower.TreeLowerCounterEntry]],
  },
  product. TreeLowerFunctionRegistration {
    interned,
    field. id [LalinCode.CodeFuncId],
    sig [LalinCode.CodeSigId],
  },
  product. TreeLowerVariant {
    interned,
    field. name [str],
    tag [number],
    payload [LalinType.Type],
    fields [many [LalinType.FieldDecl]],
  },
  product. TreeLowerVariantEntry {
    interned,
    variant_name [str],
    variant [LalinTreeLower.TreeLowerVariant],
  },
  product. TreeLowerVariantDef {
    interned,
    owner [LalinType.Type],
    variants [many [LalinTreeLower.TreeLowerVariantEntry]],
  },
  product. TreeLowerVariantDefEntry {
    interned,
    type_name [str],
    def [LalinTreeLower.TreeLowerVariantDef],
  },
  product. TreeLowerBindingValueEntry {
    interned,
    binding_name [str],
    field. value [LalinCode.CodeValueId],
  },
  product. TreeLowerLocalBindingEntry {
    interned,
    binding_name [str],
    binding [LalinTreeLower.TreeLowerLocalBinding],
  },
  product. TreeLowerBindingSnapshot {
    bindings [many [LalinTreeLower.TreeLowerBindingValueEntry]],
    locals_by_key [many [LalinTreeLower.TreeLowerLocalBindingEntry]],
  },
  product. TreeLowerLocalBinding {
    interned,
    field. id [LalinCode.CodeLocalId],
    field. ty [LalinCode.CodeType],
    source_ty [LalinType.Type],
  },
  product. TreeLowerBlockBuilder {
    field. id [LalinCode.CodeBlockId],
    field. name [str],
    params [many [LalinCode.CodeParam]],
    insts [many [LalinCode.CodeInst]],
    origin [LalinCode.CodeOrigin],
  },
  sum. TreeLowerControlRegion {
    TreeLowerExprControlRegion {
      variant_unique,
      exit_id [LalinCode.CodeBlockId],
      targets [many [LalinTreeLower.TreeLowerControlTargetEntry]],
    },
    TreeLowerStmtControlRegion {
      variant_unique,
      exit_id [LalinCode.CodeBlockId],
      targets [many [LalinTreeLower.TreeLowerControlTargetEntry]],
    },
  },
  product. TreeLowerControlTarget {
    interned,
    field. id [LalinCode.CodeBlockId],
    params [many [LalinCode.CodeParam]],
  },
  product. TreeLowerControlTargetEntry {
    interned,
    label_name [str],
    target [LalinTreeLower.TreeLowerControlTarget],
  },
  product. TreeLowerBindingState {
    values_by_key [many [LalinTreeLower.TreeLowerBindingValueEntry]],
    locals_by_key [many [LalinTreeLower.TreeLowerLocalBindingEntry]],
  },
  product. TreeLowerBindingPresenceEntry {
    interned,
    binding_name [str],
  },
  product. TreeLowerResidenceFacts {
    addressed_by_key [many [LalinTreeLower.TreeLowerBindingPresenceEntry]],
    mutable_by_key [many [LalinTreeLower.TreeLowerBindingPresenceEntry]],
  },
  product. TreeLowerEmissionState {
    locals [many [LalinCode.CodeLocal]],
    blocks [many [LalinCode.CodeBlock]],
    current_blocks [many [LalinTreeLower.TreeLowerBlockBuilder]],
  },
  product. TreeLowerCounterState {
    values_by_name [many [LalinTreeLower.TreeLowerCounterEntry]],
  },
  product. TreeLowerCounterEntry {
    interned,
    counter_name [str],
    next_value [number],
  },
  product. TreeLowerAlphaRenameEntry {
    interned,
    binding_name [str],
    renamed [str],
  },
  product. TreeLowerAlphaState {
    renamed_by_key [many [LalinTreeLower.TreeLowerAlphaRenameEntry]],
    current_suffix_by_slot [many [LalinTreeLower.TreeLowerAlphaSuffixEntry]],
    seq [number],
  },
  product. TreeLowerAlphaSuffixEntry {
    interned,
    slot_name [str],
    suffix [str],
  },
  product. TreeLowerControlRegionSlot {
    interned,
    slot_name [str],
    region [LalinTreeLower.TreeLowerControlRegion],
  },
  product. TreeLowerControlFlag {
    interned,
    flag_name [str],
    enabled [bool],
  },
  product. TreeLowerControlState {
    current_regions [many [LalinTreeLower.TreeLowerControlRegionSlot]],
    flags [many [LalinTreeLower.TreeLowerControlFlag]],
  },
  product. TreeLowerFunctionFacts {
    module_facts [LalinTreeLower.TreeLowerModuleFacts],
    registrations [LalinTreeLower.TreeLowerModuleRegistrationState],
    func_name [str],
  },
  product. TreeLowerFunctionAbiFacet {
    sigs [LalinTreeLower.TreeLowerModuleSigState],
  },
  product. TreeLowerFunctionState {
    bindings [LalinTreeLower.TreeLowerBindingState],
    residence [LalinTreeLower.TreeLowerResidenceFacts],
    emission [LalinTreeLower.TreeLowerEmissionState],
    counters [LalinTreeLower.TreeLowerCounterState],
    alpha [LalinTreeLower.TreeLowerAlphaState],
    control [LalinTreeLower.TreeLowerControlState],
    abi [LalinTreeLower.TreeLowerFunctionAbiFacet],
    module_emission [LalinTreeLower.TreeLowerModuleEmissionState],
  },
  product. TreeLowerFunctionLoweringStart {
    facts [LalinTreeLower.TreeLowerFunctionFacts],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerModuleParts {
    module_facts [LalinTreeLower.TreeLowerModuleFacts],
    sigs [LalinTreeLower.TreeLowerModuleSigState],
    registrations [LalinTreeLower.TreeLowerModuleRegistrationState],
    emission [LalinTreeLower.TreeLowerModuleEmissionState],
  },
  product. TreeLowerTypeTransitionResult {
    field. ty [LalinCode.CodeType],
    sigs [LalinTreeLower.TreeLowerModuleSigState],
  },
  product. TreeLowerSigTransitionResult {
    field. sig [LalinCode.CodeSigId],
    sigs [LalinTreeLower.TreeLowerModuleSigState],
  },
  product. TreeLowerFreshStringDataResult {
    field. id [LalinCode.CodeDataId],
    length [number],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerModuleRegistrationFacet {
    sigs [LalinTreeLower.TreeLowerModuleSigState],
    registrations [LalinTreeLower.TreeLowerModuleRegistrationState],
  },
  product. TreeLowerItemAccumulationFacet {
    funcs [many [LalinCode.CodeFunc]],
    data [many [LalinCode.CodeData]],
    globals [many [LalinCode.CodeGlobal]],
  },
  product. TreeLowerItemRegisterResult {
    registration [LalinTreeLower.TreeLowerModuleRegistrationFacet],
  },
  product. TreeLowerFunctionLowerResult {
    func [LalinCode.CodeFunc],
    abi [LalinTreeLower.TreeLowerFunctionAbiFacet],
    emission [LalinTreeLower.TreeLowerModuleEmissionState],
  },
  product. TreeLowerGlobalLowerResult {
    global [LalinCode.CodeGlobal],
    abi [LalinTreeLower.TreeLowerFunctionAbiFacet],
    emission [LalinTreeLower.TreeLowerModuleEmissionState],
  },
  product. TreeLowerItemLowerResult {
    registration [LalinTreeLower.TreeLowerModuleRegistrationFacet],
    emission [LalinTreeLower.TreeLowerModuleEmissionState],
    accumulation [LalinTreeLower.TreeLowerItemAccumulationFacet],
  },
  product. TreeLowerModuleLowerResult {
    code_module [LalinCode.CodeModule],
    contracts [LalinCode.CodeContractFactSet],
    parts [LalinTreeLower.TreeLowerModuleParts],
  },
  product. TreeLowerItemRegisterInput {
    module_facts [LalinTreeLower.TreeLowerModuleFacts],
    registration [LalinTreeLower.TreeLowerModuleRegistrationFacet],
  },
  product. TreeLowerContractState {
    sigs [LalinTreeLower.TreeLowerModuleSigState],
    facts [many [LalinCode.CodeFuncContractFact]],
  },
  product. TreeLowerItemContractsInput {
    module_facts [LalinTreeLower.TreeLowerModuleFacts],
    registrations [LalinTreeLower.TreeLowerModuleRegistrationState],
    state [LalinTreeLower.TreeLowerContractState],
  },
  sum. TreeLowerItemContractsResult {
    TreeLowerItemContractsUnsupported { state [LalinTreeLower.TreeLowerContractState] },
    TreeLowerItemContractsAccumulated { state [LalinTreeLower.TreeLowerContractState] },
  },
  product. TreeLowerItemLowerInput {
    module_facts [LalinTreeLower.TreeLowerModuleFacts],
    registration [LalinTreeLower.TreeLowerModuleRegistrationFacet],
    emission [LalinTreeLower.TreeLowerModuleEmissionState],
    accumulation [LalinTreeLower.TreeLowerItemAccumulationFacet],
    mod_name [str],
  },
  sum. TreeLowerInput {
    TreeLowerExprInput {
      variant_unique,
      facts [LalinTreeLower.TreeLowerFunctionFacts],
      state [LalinTreeLower.TreeLowerFunctionState],
    },
    TreeLowerPlaceInput {
      variant_unique,
      facts [LalinTreeLower.TreeLowerFunctionFacts],
      state [LalinTreeLower.TreeLowerFunctionState],
    },
    TreeLowerStmtInput {
      variant_unique,
      facts [LalinTreeLower.TreeLowerFunctionFacts],
      state [LalinTreeLower.TreeLowerFunctionState],
    },
    TreeLowerControlInput {
      variant_unique,
      facts [LalinTreeLower.TreeLowerFunctionFacts],
      state [LalinTreeLower.TreeLowerFunctionState],
    },
  },
  product. TreeLowerContractInput {
    module_facts [LalinTreeLower.TreeLowerModuleFacts],
    sigs [LalinTreeLower.TreeLowerModuleSigState],
    func_name [str],
    func_id [LalinCode.CodeFuncId],
  },
  sum. TreeLowerContractValueProjection {
    TreeLowerContractValueSupported { field. value [LalinCode.CodeValueId] },
    TreeLowerContractValueUnsupported { reason [str] },
  },
  sum. TreeLowerContractExprProjection {
    TreeLowerContractExprSupported { field. expr [LalinCode.CodeContractExpr] },
    TreeLowerContractExprUnsupported { reason [str] },
  },
  sum. TreeLowerContractPlaceProjection {
    TreeLowerContractPlaceSupported { field. place [LalinCode.CodePlace] },
    TreeLowerContractPlaceUnsupported { reason [str] },
  },
  product. TreeLowerStateResult {
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerCounterResult {
    field. value [number],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerBindingKeyResult {
    binding_name [str],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerValueIdResult {
    field. value [LalinCode.CodeValueId],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerInstIdResult {
    field. id [LalinCode.CodeInstId],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerTermIdResult {
    field. id [LalinCode.CodeTermId],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerBlockIdResult {
    field. id [LalinCode.CodeBlockId],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerTermResult {
    field. term [LalinCode.CodeTerm],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerLocalResult {
    field. id [LalinCode.CodeLocalId],
    field. ty [LalinCode.CodeType],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerAlphaResult {
    renamed_by_key [many [LalinTreeLower.TreeLowerAlphaRenameEntry]],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerControlExitResult {
    saw_exit [bool],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerFallthroughResult {
    falls [bool],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerExprResult {
    interned,
    field. value [optional [LalinCode.CodeValueId]],
    field. ty [LalinCode.CodeType],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerPlaceResult {
    interned,
    place [LalinCode.CodePlace],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerIndexPlaceResult {
    place [LalinCode.CodePlace],
    index [LalinCode.CodeValueId],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerViewPartsResult {
    data [LalinCode.CodeValueId],
    len [LalinCode.CodeValueId],
    stride [LalinCode.CodeValueId],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerStmtResult {
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerParamResult {
    field. param [LalinCode.CodeParam],
    field. ty [LalinCode.CodeType],
    state [LalinTreeLower.TreeLowerFunctionState],
  },
  product. TreeLowerFunctionParts {
    interned,
    field. name [str],
    linkage [LalinCode.CodeLinkage],
    params [many [LalinType.Param]],
    result [LalinType.Type],
    body [many [LalinTree.Stmt]],
  },
  product. TreeLowerContractResult {
    interned,
    fact [LalinCode.CodeFuncContractFact],
  },
}
