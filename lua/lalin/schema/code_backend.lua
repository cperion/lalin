local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCodeBackend {
  product. CodeBackendSigAbi {
    interned,
    sret [bool],
    result_ty [optional [LalinCode.CodeType]],
    params [many [LalinBackend.BackScalar]],
    results [many [LalinBackend.BackScalar]],
  },
  product. CodeBackendLocalSlot {
    interned,
    slot [LalinBackend.BackStackSlotId],
    field. ty [LalinCode.CodeType],
    size [number],
    align [number],
  },
  product. CodeBackendReadonlyProjection {
    readonly_by_inst [many [LalinCodeBackend.CodeReadonlyByInstEntry]],
  },
  sum. CodeBackendReadonly {
    CodeBackendReadonly,
    CodeBackendReadWrite,
  },
  product. CodeReadonlyByInstEntry {
    interned,
    inst_key [str],
    readonly [LalinCodeBackend.CodeBackendReadonly],
  },
  product. CodeSigByIdEntry {
    interned,
    sig_key [str],
    sig [LalinCode.CodeSig],
  },
  product. CodeSigAbiBySigEntry {
    interned,
    sig_key [str],
    abi [LalinCodeBackend.CodeBackendSigAbi],
  },
  product. CodeMemBackendByInstEntry {
    interned,
    inst_key [str],
    backend [LalinMem.MemBackendAccessInfo],
  },
  product. CodeEffectByInstEntry {
    interned,
    inst_key [str],
    effect [LalinEffect.InstEffect],
  },
  product. CodeBackendModuleMachine {
    sigs [many [LalinCodeBackend.CodeSigByIdEntry]],
    sig_abi_by_sig [many [LalinCodeBackend.CodeSigAbiBySigEntry]],
    mem_backend_by_inst [many [LalinCodeBackend.CodeMemBackendByInstEntry]],
    effect_by_inst [many [LalinCodeBackend.CodeEffectByInstEntry]],
    readonly [LalinCodeBackend.CodeBackendReadonlyProjection],
    layout_env [optional [LalinSem.LayoutEnv]],
    target [optional [LalinBackend.BackTarget]],
  },
  product. CodeTypeByValueEntry {
    interned,
    value_key [str],
    field. ty [LalinCode.CodeType],
  },
  product. CodeParamsByBlockEntry {
    interned,
    block_key [str],
    params [many [LalinCode.CodeParam]],
  },
  product. CodeBackendFunctionFacts {
    func [LalinCode.CodeFuncId],
    current_return_sret [optional [LalinBackend.BackValId]],
    value_types [many [LalinCodeBackend.CodeTypeByValueEntry]],
    block_params [many [LalinCodeBackend.CodeParamsByBlockEntry]],
  },
  product. CodeLocalAddrByValueEntry {
    interned,
    value_key [str],
    addr [LalinBackend.BackValId],
  },
  product. CodeValueAddrByValueEntry {
    interned,
    value_key [str],
    addr [LalinBackend.BackValId],
  },
  product. CodeValueSizeByValueEntry {
    interned,
    value_key [str],
    size [number],
  },
  product. CodeBackendAggregateState {
    local_addr_by_value [many [LalinCodeBackend.CodeLocalAddrByValueEntry]],
    value_addr_by_value [many [LalinCodeBackend.CodeValueAddrByValueEntry]],
    value_size_by_value [many [LalinCodeBackend.CodeValueSizeByValueEntry]],
  },
  product. CodeCaptureByValueEntry {
    interned,
    value_key [str],
    has_captures [bool],
  },
  product. CodeBackendClosureState {
    has_captures_by_value [many [LalinCodeBackend.CodeCaptureByValueEntry]],
  },
  product. CodeSlotByLocalEntry {
    interned,
    local_key [str],
    slot [LalinCodeBackend.CodeBackendLocalSlot],
  },
  product. CodeBackendLocalSlotState {
    slot_by_local [many [LalinCodeBackend.CodeSlotByLocalEntry]],
  },
  product. CodeBackendTempState {
    tmp_index [number],
    next_tmp [number],
  },
  product. CodeBackendFunctionState {
    aggregates [LalinCodeBackend.CodeBackendAggregateState],
    closures [LalinCodeBackend.CodeBackendClosureState],
    local_slots [LalinCodeBackend.CodeBackendLocalSlotState],
    temps [LalinCodeBackend.CodeBackendTempState],
  },
  product. CodeBackendInstInput {
    field. module [LalinCodeBackend.CodeBackendModuleMachine],
    func [LalinCodeBackend.CodeBackendFunctionFacts],
    state [LalinCodeBackend.CodeBackendFunctionState],
    inst [LalinCode.CodeInstId],
  },
  product. CodeBackendTermInput {
    field. module [LalinCodeBackend.CodeBackendModuleMachine],
    func [LalinCodeBackend.CodeBackendFunctionFacts],
    state [LalinCodeBackend.CodeBackendFunctionState],
    term [LalinCode.CodeTermId],
  },
  product. CodeBackendPlaceInput {
    field. module [LalinCodeBackend.CodeBackendModuleMachine],
    func [LalinCodeBackend.CodeBackendFunctionFacts],
    state [LalinCodeBackend.CodeBackendFunctionState],
    owner [LalinCode.CodeInstId],
    access [optional [LalinMem.MemBackendAccessInfo]],
  },
  product. CodeBackendStateResult {
    state [LalinCodeBackend.CodeBackendFunctionState],
  },
  product. CodeBackendValueResult {
    field. value [LalinBackend.BackValId],
    state [LalinCodeBackend.CodeBackendFunctionState],
  },
  product. CodeBackendAddressResult {
    address [LalinBackend.BackAddress],
    state [LalinCodeBackend.CodeBackendFunctionState],
  },
  product. CodeBackendMemoryInfoResult {
    memory [LalinBackend.BackMemoryInfo],
    state [LalinCodeBackend.CodeBackendFunctionState],
  },
  product. CodeBackendPlaceResult {
    address [LalinBackend.BackAddress],
    state [LalinCodeBackend.CodeBackendFunctionState],
  },
}
