local S = require("lalin.schema.dsl")
S.use()

return schema. LalinMem {
  -- Identity types
  product. MemAccessId { interned, text [str], },
  product. MemObjectId { interned, text [str], },
  product. MemBaseId { interned, text [str], },
  product. MemScopeId { interned, text [str], },
  product. MemProofId { interned, text [str], },
  product. MemLeaseId { interned, text [str], },

  sum. MemAccessOp {
    MemLoad,
    MemStore,
    MemAtomicLoad,
    MemAtomicStore,
    MemAtomicRmw,
    MemAtomicCas,
  },
  sum. MemAccessMode { MemAccessModeRead, MemAccessModeWrite, MemAccessModeReadWrite, },

  -- MemBase: root memory identity
  sum. MemBase {
    MemBaseValue { variant_unique, field. value [LalinCode.CodeValueId], },
    MemBaseLocal { variant_unique, field. local_id [LalinCode.CodeLocalId], },
    MemBaseGlobal { variant_unique, global [LalinCode.CodeGlobalId], },
    MemBaseData { variant_unique, data [LalinCode.CodeDataId], },
    MemBaseArgument {
      variant_unique,
      field. name [str],
      field. value [LalinCode.CodeValueId],
    },
    MemBaseProjection {
      variant_unique,
      base [LalinMem.MemBase],
      projection [LalinMem.MemProjectionStep],
      byte_offset [number],
    },
    MemBaseUnknown { variant_unique, reason [str], },
  },

  -- MemObjectForm: REFACTORED — MemObjectDerived split into 4 concrete leaves
  sum. MemObjectForm {
    MemObjectParam,
    MemObjectLocal,
    MemObjectGlobal,
    MemObjectData,
    MemObjectView,
    MemObjectSlice,
    MemObjectByteSpan,
    MemObjectContract,
    -- SPLIT from MemObjectDerived:
    MemObjectFieldProjection {
      variant_unique,
      owner [LalinMem.MemObjectId],
      field. field [LalinSem.FieldRef],
    },
    MemObjectPtrOffset {
      variant_unique,
      owner [LalinMem.MemObjectId],
      index_expr [LalinMem.MemIndex],
      elem_size [number],
    },
    MemObjectBytes {
      variant_unique,
      owner [LalinMem.MemObjectId],
      byte_offset [number],
      byte_length [number],
    },
    MemObjectElement {
      variant_unique,
      owner [LalinMem.MemObjectId],
      elem_index [number],
      elem_size [number],
    },
    MemObjectFieldPointer,
    MemObjectLease,
    -- Gains typed reason
    MemObjectUnknown { variant_unique, reason [LalinMem.MemObjectUnknownReason], },
  },

  sum. MemObjectUnknownReason {
    MemObjectUnresolvedPointer { field. value [LalinCode.CodeValueId], },
    MemObjectIndirectCallReturn { call_site [str], },
    MemObjectExternalBuffer { buffer_name [str], },
    MemObjectOpaqueType { ty [LalinCode.CodeType], },
  },

  -- MemProjectionStep: gains typed reason on Unknown
  sum. MemProjectionStep {
    MemProjectField,
    MemProjectBytes,
    MemProjectPtrOffset,
    MemProjectViewData,
    MemProjectSlice,
    MemProjectWindow,
    MemProjectElement,
    MemProjectUnknown { variant_unique, reason [LalinMem.MemProjectionUnknownReason], },
  },

  sum. MemProjectionUnknownReason {
    MemProjectOpaqueFieldAccess { field_name [str], owner_ty [LalinCode.CodeType], },
    MemProjectDynamicOffset { base [LalinMem.MemObjectId], },
    MemProjectUntypedCast { from_ty [LalinCode.CodeType], to_ty [LalinCode.CodeType], },
  },

  -- MemObjectProvenance
  sum. MemObjectProvenance {
    MemProvValue { variant_unique, field. value [LalinCode.CodeValueId], },
    MemProvLocal { variant_unique, field. local_id [LalinCode.CodeLocalId], },
    MemProvGlobal { variant_unique, global [LalinCode.CodeGlobalId], },
    MemProvData { variant_unique, data [LalinCode.CodeDataId], },
    MemProvView {
      variant_unique,
      view [LalinCode.CodeValueId],
      data [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
      stride [optional [LalinCode.CodeValueId]],
    },
    MemProvSlice {
      variant_unique,
      slice [LalinCode.CodeValueId],
      data [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
    },
    MemProvByteSpan {
      variant_unique,
      span [LalinCode.CodeValueId],
      data [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
    },
    MemProvContract { variant_unique, fact [LalinCode.CodeFuncContractFact], },
    MemProvLease { variant_unique, lease [LalinMem.MemLeaseId], },
    MemProvProjection {
      variant_unique,
      parent [LalinMem.MemObjectId],
      projection [LalinMem.MemProjectionStep],
      byte_offset [number],
    },
    MemProvFieldPointer {
      variant_unique,
      owner [LalinMem.MemObjectId],
      ptr_field [LalinSem.FieldRef],
      ptr_value [LalinCode.CodeValueId],
      owner_value [LalinCode.CodeValueId],
    },
    MemProvUnknown { variant_unique, reason [str], },
  },

  -- MemObjectExtent: REFACTORED — typed guarantees replace reason [str]
  sum. MemExtentGuarantee {
    MemExtentByConstruction,
    MemExtentConstLength,
    MemExtentLengthFromParam,
    MemExtentLengthFromContract,
    MemExtentAssumedByAuthor { assertion_site [str], },
  },
  sum. MemExtentUnknownReason {
    MemExtentDynamicAllocation,
    MemExtentOpaquePointer { value_name [str], },
    MemExtentCircularDependence,
  },
  sum. MemObjectExtent {
    MemExtentUnknown { variant_unique, reason [LalinMem.MemExtentUnknownReason], },
    MemExtentElements {
      variant_unique,
      len [LalinCode.CodeValueId],
      elem_ty [LalinCode.CodeType],
      guarantee [LalinMem.MemExtentGuarantee],
    },
    MemExtentBytes {
      variant_unique,
      bytes [number],
      guarantee [LalinMem.MemExtentGuarantee],
    },
    MemExtentContract {
      variant_unique,
      fact [LalinCode.CodeFuncContractFact],
      guarantee [LalinMem.MemExtentGuarantee],
    },
  },

  -- MemObjectStride: REFACTORED — typed reason on Unknown
  sum. MemStrideUnknownReason {
    MemStrideDynamicView { view_value [LalinCode.CodeValueId], },
    MemStrideNonUniformAccess,
    MemStrideIndirectionChain,
  },
  sum. MemObjectStride {
    MemStrideUnknown { variant_unique, reason [LalinMem.MemStrideUnknownReason], },
    MemStrideUnit,
    MemStrideConstElems { variant_unique, elems [number], },
    MemStrideValue { variant_unique, field. value [LalinCode.CodeValueId], },
  },

  -- MemObjectFact
  product. MemObjectFact {
    interned,
    field. id [LalinMem.MemObjectId],
    func [optional [LalinCode.CodeFuncId]],
    form [LalinMem.MemObjectForm],
    provenance [LalinMem.MemObjectProvenance],
    elem_ty [optional [LalinCode.CodeType]],
    extent [LalinMem.MemObjectExtent],
    stride [LalinMem.MemObjectStride],
  },

  -- MemLeaseGrant
  product. MemLeaseGrant {
    interned,
    field. id [LalinMem.MemLeaseId],
    domain [optional [LalinFlow.FlowDomain]],
    lease_value [LalinCode.CodeValueId],
    handle [optional [LalinCode.CodeValueId]],
    object [LalinMem.MemObjectId],
    base [LalinMem.MemBase],
    extent [LalinMem.MemObjectExtent],
    stride [LalinMem.MemObjectStride],
    proof [LalinMem.MemProof],
  },

  -- MemIndex
  sum. MemIndex {
    MemIndexNone,
    MemIndexValue {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      elem_size [number],
      const_offset [number],
    },
    MemIndexInduction {
      variant_unique,
      induction [LalinFlow.FlowInduction],
      field. value [LalinCode.CodeValueId],
      elem_size [number],
      const_offset [number],
      element_offset [number],
    },
  },

  -- MemAccessPattern / MemAlignment / MemBounds / MemTrap
  sum. MemAccessPattern {
    MemAccessScalar,
    MemAccessContiguous,
    MemAccessStrided { variant_unique, stride_elems [number], },
    MemAccessGather,
    MemAccessScatter,
    MemAccessUnknown,
  },
  sum. MemAlignment {
    MemAlignUnknown,
    MemAlignKnown { variant_unique, bytes [number], },
    MemAlignAtLeast { variant_unique, bytes [number], },
    MemAlignAssumed { variant_unique, bytes [number], proof [LalinMem.MemProof], },
  },
  sum. MemBounds {
    MemBoundsUnknown { variant_unique, reason [str], },
    MemBoundsInObject { variant_unique, reason [str], },
    MemBoundsRange {
      variant_unique,
      start [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
      reason [str],
    },
    MemBoundsAssumed { variant_unique, proof [LalinMem.MemProof], },
  },
  sum. MemTrap {
    MemMayTrap,
    MemNonTrapping { variant_unique, reason [str], },
    MemCheckedTrap { variant_unique, reason [str], },
  },

  -- MemAccessFact
  product. MemAccessFact {
    interned,
    field. id [LalinMem.MemAccessId],
    func [LalinCode.CodeFuncId],
    block [LalinGraph.GraphBlockId],
    inst [optional [LalinCode.CodeInstId]],
    op [LalinMem.MemAccessOp],
    place [LalinCode.CodePlace],
    access [LalinCode.CodeMemoryAccess],
    base [LalinMem.MemBase],
    index [LalinMem.MemIndex],
    pattern [LalinMem.MemAccessPattern],
    alignment [LalinMem.MemAlignment],
    bounds [LalinMem.MemBounds],
    trap [LalinMem.MemTrap],
  },

  -- MemAccessInterval
  product. MemAccessInterval {
    interned,
    access [LalinMem.MemAccessId],
    object [LalinMem.MemObjectId],
    loop [optional [LalinGraph.GraphLoopId]],
    start [LalinMem.MemIndex],
    length_elems [LalinFlow.FlowBound],
    elem_size [number],
    const_byte_offset [number],
    reason [str],
  },

  -- MemAccessSafetyFact
  sum. MemAccessSafetyFact {
    MemAccessInBounds {
      variant_unique,
      interval [LalinMem.MemAccessInterval],
      proof [LalinMem.MemProof],
    },
    MemAccessNonTrap {
      variant_unique,
      access [LalinMem.MemAccessId],
      proof [LalinMem.MemProof],
    },
    MemAccessMovable {
      variant_unique,
      access [LalinMem.MemAccessId],
      proof [LalinMem.MemProof],
    },
    MemAccessDerefBytes {
      variant_unique,
      access [LalinMem.MemAccessId],
      bytes [number],
      proof [LalinMem.MemProof],
    },
    MemAccessAlignKnown {
      variant_unique,
      access [LalinMem.MemAccessId],
      bytes [number],
      proof [LalinMem.MemProof],
    },
  },

  -- MemObjectEffectFact
  sum. MemObjectEffectFact {
    MemObjectReadonly {
      variant_unique,
      object [LalinMem.MemObjectId],
      proof [LalinMem.MemProof],
    },
    MemObjectWriteonly {
      variant_unique,
      object [LalinMem.MemObjectId],
      proof [LalinMem.MemProof],
    },
  },

  -- MemObjectRelation
  sum. MemObjectRelation {
    MemObjectsSameLen {
      variant_unique,
      a [LalinMem.MemObjectId],
      b [LalinMem.MemObjectId],
      proof [LalinMem.MemProof],
    },
    MemObjectWindowOf {
      variant_unique,
      window [LalinMem.MemObjectId],
      parent [LalinMem.MemObjectId],
      start [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
      proof [LalinMem.MemProof],
    },
    MemObjectSliceOf {
      variant_unique,
      slice [LalinMem.MemObjectId],
      parent [LalinMem.MemObjectId],
      start [LalinCode.CodeValueId],
      len [LalinCode.CodeValueId],
      proof [LalinMem.MemProof],
    },
    MemObjectSameStore {
      variant_unique,
      a [LalinMem.MemObjectId],
      b [LalinMem.MemObjectId],
      proof [LalinMem.MemProof],
    },
  },

  -- MemAliasFact: REFACTORED — typed guarantee unions replace reason [str]
  sum. MemAliasGuarantee {
    MemAliasByConstruction { reason_description [str], },
    MemAliasDistinctTypes { a_ty [LalinCode.CodeType], b_ty [LalinCode.CodeType], },
    MemAliasDistinctAllocs { a_site [str], b_site [str], },
    MemAliasRestrictQualified { value_name [str], },
  },
  sum. MemAliasFact {
    MemAliasUnknown {
      variant_unique,
      a [LalinMem.MemAccessId],
      b [LalinMem.MemAccessId],
      reason [str],
    },
    MemMayAlias {
      variant_unique,
      a [LalinMem.MemAccessId],
      b [LalinMem.MemAccessId],
      reason [str],
    },
    MemNoAlias {
      variant_unique,
      a [LalinMem.MemAccessId],
      b [LalinMem.MemAccessId],
      proof [LalinMem.MemProof],
    },
    MemSameBaseSameIndexSafe {
      variant_unique,
      a [LalinMem.MemAccessId],
      b [LalinMem.MemAccessId],
      proof [LalinMem.MemProof],
    },
    MemAliasScope {
      variant_unique,
      access [LalinMem.MemAccessId],
      scope [LalinMem.MemScopeId],
    },
  },

  -- MemDependenceFact
  sum. MemDependenceFact {
    MemDependenceUnknown {
      variant_unique,
      before [LalinMem.MemAccessId],
      after [LalinMem.MemAccessId],
      reason [str],
    },
    MemReadReadIndependent {
      variant_unique,
      a [LalinMem.MemAccessId],
      b [LalinMem.MemAccessId],
      reason [str],
    },
    MemNoDependence {
      variant_unique,
      before [LalinMem.MemAccessId],
      after [LalinMem.MemAccessId],
      proof [LalinMem.MemProof],
    },
    MemNoLoopCarriedDependence {
      variant_unique,
      before [LalinMem.MemAccessId],
      after [LalinMem.MemAccessId],
      loop [LalinGraph.GraphLoopId],
      proof [LalinMem.MemProof],
    },
    MemDependenceDistance {
      variant_unique,
      before [LalinMem.MemAccessId],
      after [LalinMem.MemAccessId],
      loop [LalinGraph.GraphLoopId],
      distance_elems [str],
      proof [LalinMem.MemProof],
    },
    MemLoopCarriedDependence {
      variant_unique,
      before [LalinMem.MemAccessId],
      after [LalinMem.MemAccessId],
      loop [LalinGraph.GraphLoopId],
      reason [str],
    },
  },

  -- MemProof: REFACTORED — ALL 9 leaves get typed guarantee unions
  sum. MemBoundsGuarantee {
    MemBoundsTypeCheck { ty [LalinCode.CodeType], size [number], },
    MemBoundsContractAssert { contract_name [str], },
    MemBoundsLoopRange { loop [LalinGraph.GraphLoopId], },
    MemBoundsConstLength { length [number], },
  },
  sum. MemAlignGuarantee {
    MemAlignTypeDefined { ty [LalinCode.CodeType], alignment [number], },
    MemAlignAllocationSite { allocation_site [str], alignment [number], },
    MemAlignPlatformRequired { platform [str], alignment [number], },
  },
  sum. MemDependenceGuarantee {
    MemNoDependenceDisjointAccesses { a [LalinMem.MemAccessId], b [LalinMem.MemAccessId], },
    MemNoDependenceReadOnly { access [LalinMem.MemAccessId], },
    MemNoDependenceLoopLevel { loop [LalinGraph.GraphLoopId], },
    MemNoDependenceDistanceProven { distance [number], loop [LalinGraph.GraphLoopId], },
  },
  sum. MemContractGuarantee {
    MemContractBounds { contract_name [str], },
    MemContractNoAlias { contract_name [str], value_name [str], },
    MemContractReadonly { contract_name [str], value_name [str], },
  },
  sum. MemFlowGuarantee {
    MemFlowCounted { trip_count [LalinFlow.FlowTripCount], },
    MemFlowMonotonicAddress { induction [LalinFlow.FlowInduction], },
    MemFlowLoopInvariant { field. value [LalinCode.CodeValueId], },
  },
  sum. MemObjectGuarantee {
    MemObjectSizeKnown { size [number], },
    MemObjectBaseAddressStable,
    MemObjectNotEscaped { scope_description [str], },
  },
  sum. MemIntervalGuarantee {
    MemIntervalWithinObject { object [LalinMem.MemObjectId], },
    MemIntervalConstLength { length [number], },
    MemIntervalLoopBounded { loop [LalinGraph.GraphLoopId], },
  },
  sum. MemBackendGuarantee {
    MemBackendNativeAlignment { bytes [number], },
    MemBackendHostEndianness,
    MemBackendNoTrapOnAligned { access_description [str], },
  },

  sum. MemProof {
    MemProofBounds {
      variant_unique,
      guarantee [LalinMem.MemBoundsGuarantee],
    },
    MemProofAlignment {
      variant_unique,
      guarantee [LalinMem.MemAlignGuarantee],
    },
    MemProofAlias {
      variant_unique,
      fact [LalinMem.MemAliasFact],
      guarantee [LalinMem.MemAliasGuarantee],
    },
    MemProofNoDependence {
      variant_unique,
      accesses [many [LalinMem.MemAccessId]],
      guarantee [LalinMem.MemDependenceGuarantee],
    },
    MemProofContract {
      variant_unique,
      fact [LalinCode.CodeFuncContractFact],
      guarantee [LalinMem.MemContractGuarantee],
    },
    MemProofFlow {
      variant_unique,
      loop [LalinGraph.GraphLoopId],
      guarantee [LalinMem.MemFlowGuarantee],
    },
    MemProofObject {
      variant_unique,
      object [LalinMem.MemObjectId],
      guarantee [LalinMem.MemObjectGuarantee],
    },
    MemProofInterval {
      variant_unique,
      interval [LalinMem.MemAccessInterval],
      guarantee [LalinMem.MemIntervalGuarantee],
    },
    MemProofBackend {
      variant_unique,
      access [LalinMem.MemAccessId],
      guarantee [LalinMem.MemBackendGuarantee],
    },
  },

  sum. MemMovementDecision {
    MemMovementMovable { variant_unique, reason [str], },
    MemMovementPinned { variant_unique, reason [str], },
  },
  sum. MemDerefBytes { MemDerefBytesKnown { variant_unique, bytes [number], }, MemDerefBytesUnavailable, },
  -- MemBackendAccessInfo
  product. MemBackendAccessInfo {
    interned,
    access [LalinMem.MemAccessId],
    trap [LalinMem.MemTrap],
    alignment [LalinMem.MemAlignment],
    bounds [LalinMem.MemBounds],
    deref_bytes [LalinMem.MemDerefBytes],
    movement [LalinMem.MemMovementDecision],
    proofs [many [LalinMem.MemProof]],
  },

  -- Immutable contract projection. Keyed relations are named entries under many.
  sum. MemContractExprKey {
    MemContractValueKey { variant_unique, field. value [LalinCode.CodeValueId], },
    MemContractPlaceKey { variant_unique, place [LalinCode.CodePlace], },
  },
  sum. MemContractLengthLookup {
    MemContractLengthFound { variant_unique, field. value [LalinCode.CodeValueId], },
    MemContractLengthMissing,
  },
  product. MemContractProjectInput { source [LalinCode.CodeFuncContractFact], },
  product. MemContractBoundsEntry { interned, func [LalinCode.CodeFuncId], base [LalinCode.CodeValueId], len [LalinCode.CodeValueId], source [LalinCode.CodeFuncContractFact], },
  product. MemContractProjectionBoundsEntry { interned, func [LalinCode.CodeFuncId], base [LalinMem.MemContractExprKey], len [LalinMem.MemContractExprKey], source [LalinCode.CodeFuncContractFact], },
  product. MemContractWindowEntry { interned, func [LalinCode.CodeFuncId], base [LalinCode.CodeValueId], base_len [LalinCode.CodeValueId], start [LalinCode.CodeValueId], len [LalinCode.CodeValueId], source [LalinCode.CodeFuncContractFact], },
  product. MemContractPairEntry { interned, func [LalinCode.CodeFuncId], a [LalinCode.CodeValueId], b [LalinCode.CodeValueId], source [LalinCode.CodeFuncContractFact], },
  product. MemContractSoAEntry { interned, func [LalinCode.CodeFuncId], base [LalinCode.CodeValueId], record_ty [LalinCode.CodeType], field_name [str], component_index [number], source [LalinCode.CodeFuncContractFact], },
  product. MemContractValueEntry { interned, func [LalinCode.CodeFuncId], base [LalinCode.CodeValueId], source [LalinCode.CodeFuncContractFact], },
  product. MemContractProjectionEntry { interned, func [LalinCode.CodeFuncId], base [LalinMem.MemContractExprKey], source [LalinCode.CodeFuncContractFact], },
  product. MemContractRejectedEntry { interned, func [LalinCode.CodeFuncId], reason [str], source [LalinCode.CodeFuncContractFact], },
  product. MemContractContribution {
    bounds [many [LalinMem.MemContractBoundsEntry]],
    projection_bounds [many [LalinMem.MemContractProjectionBoundsEntry]],
    windows [many [LalinMem.MemContractWindowEntry]],
    same_lengths [many [LalinMem.MemContractPairEntry]],
    disjoint [many [LalinMem.MemContractPairEntry]],
    soa [many [LalinMem.MemContractSoAEntry]],
    noalias [many [LalinMem.MemContractValueEntry]],
    readonly [many [LalinMem.MemContractValueEntry]],
    writeonly [many [LalinMem.MemContractValueEntry]],
    projection_readonly [many [LalinMem.MemContractProjectionEntry]],
    projection_writeonly [many [LalinMem.MemContractProjectionEntry]],
    projection_noalias [many [LalinMem.MemContractProjectionEntry]],
    invalidates [many [LalinMem.MemContractValueEntry]],
    preserves [many [LalinMem.MemContractValueEntry]],
    rejected [many [LalinMem.MemContractRejectedEntry]],
  },
  product. MemContractProjection {
    bounds [many [LalinMem.MemContractBoundsEntry]],
    projection_bounds [many [LalinMem.MemContractProjectionBoundsEntry]],
    windows [many [LalinMem.MemContractWindowEntry]],
    same_lengths [many [LalinMem.MemContractPairEntry]],
    disjoint [many [LalinMem.MemContractPairEntry]],
    soa [many [LalinMem.MemContractSoAEntry]],
    noalias [many [LalinMem.MemContractValueEntry]],
    readonly [many [LalinMem.MemContractValueEntry]],
    writeonly [many [LalinMem.MemContractValueEntry]],
    projection_readonly [many [LalinMem.MemContractProjectionEntry]],
    projection_writeonly [many [LalinMem.MemContractProjectionEntry]],
    projection_noalias [many [LalinMem.MemContractProjectionEntry]],
    invalidates [many [LalinMem.MemContractValueEntry]],
    preserves [many [LalinMem.MemContractValueEntry]],
    rejected [many [LalinMem.MemContractRejectedEntry]],
  },

  -- Access projection lookups never use nil as a semantic result.
  product. MemAccessByIdEntry { interned, access [LalinMem.MemAccessFact], },
  product. MemObjectByAccessEntry { interned, access [LalinMem.MemAccessId], object [LalinMem.MemObjectId], },
  product. MemBackendByAccessEntry { interned, access [LalinMem.MemAccessId], backend [LalinMem.MemBackendAccessInfo], },
  product. MemProofByAccessEntry { interned, access [LalinMem.MemAccessId], proof [LalinMem.MemProof], },
  product. MemAccessProjection {
    access_by_id [many [LalinMem.MemAccessByIdEntry]],
    object_by_access [many [LalinMem.MemObjectByAccessEntry]],
    backend_by_access [many [LalinMem.MemBackendByAccessEntry]],
    proof_by_access [many [LalinMem.MemProofByAccessEntry]],
  },
  sum. MemAccessLookup { MemAccessFound { variant_unique, access [LalinMem.MemAccessFact], }, MemAccessMissing { variant_unique, access [LalinMem.MemAccessId], }, },
  sum. MemObjectLookup { MemObjectFound { variant_unique, object [LalinMem.MemObjectId], }, MemObjectMissing { variant_unique, access [LalinMem.MemAccessId], }, },
  sum. MemBackendLookup { MemBackendFound { variant_unique, backend [LalinMem.MemBackendAccessInfo], }, MemBackendMissing { variant_unique, access [LalinMem.MemAccessId], }, },
  sum. MemProofLookup { MemProofFound { variant_unique, proof [LalinMem.MemProof], }, MemProofMissing { variant_unique, access [LalinMem.MemAccessId], }, },
  sum. MemProofAccessProjection { MemProofAccessNone, MemProofAccessEntry { variant_unique, entry [LalinMem.MemProofByAccessEntry], }, },

  -- CodePlace resolution is leaf-owned and returns one typed result.
  product. MemValueObjectEntry { interned, field. value [LalinCode.CodeValueId], object [LalinMem.MemObjectId], },
  product. MemLocalObjectEntry { interned, field. local_id [LalinCode.CodeLocalId], object [LalinMem.MemObjectId], },
  product. MemGlobalObjectEntry { interned, global [LalinCode.CodeGlobalId], object [LalinMem.MemObjectId], },
  product. MemDataObjectEntry { interned, data [LalinCode.CodeDataId], object [LalinMem.MemObjectId], },
  sum. MemValueObjectLookup { MemValueObjectFound { variant_unique, object [LalinMem.MemObjectId], }, MemValueObjectMissing { variant_unique, field. value [LalinCode.CodeValueId], }, },
  sum. MemPlaceObjectLookup { MemPlaceObjectFound { variant_unique, object [LalinMem.MemObjectId], }, MemPlaceObjectMissing { variant_unique, reason [str], }, },
  product. MemPlaceDiscoveries {
    objects [many [LalinMem.MemObjectFact]],
    relations [many [LalinMem.MemObjectRelation]],
    proofs [many [LalinMem.MemProof]],
  },
  product. MemIndexOffsetEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    base [LalinCode.CodeValueId],
    element_offset [number],
  },
  product. MemIndexClassifyInput {
    interned,
    field. value [LalinCode.CodeValueId],
    elem_size [number],
    const_offset [number],
    offsets [many [LalinMem.MemIndexOffsetEntry]],
    flow [LalinFlow.FlowFactSet],
  },
  product. MemPlaceResolveInput {
    func [LalinCode.CodeFuncId],
    values [many [LalinMem.MemValueObjectEntry]],
    locals [many [LalinMem.MemLocalObjectEntry]],
    globals [many [LalinMem.MemGlobalObjectEntry]],
    data [many [LalinMem.MemDataObjectEntry]],
    objects [many [LalinMem.MemObjectFact]],
    inductions [LalinFlow.FlowInductionProjection],
    index_offsets [many [LalinMem.MemIndexOffsetEntry]],
    flow [LalinFlow.FlowFactSet],
  },
  sum. MemPlaceResolveResult {
    MemPlaceResolved { variant_unique, object [LalinMem.MemObjectId], base [LalinMem.MemBase], index [LalinMem.MemIndex], discoveries [LalinMem.MemPlaceDiscoveries], },
    MemPlaceUnresolved { variant_unique, base [LalinMem.MemBase], index [LalinMem.MemIndex], reason [str], discoveries [LalinMem.MemPlaceDiscoveries], },
  },
  sum. MemAccessSafetyDecision {
    MemAccessSafetyProven { variant_unique, reason [str], },
    MemAccessSafetyUnproven { variant_unique, reason [str], },
  },

  -- Immutable instruction-transfer facet.
  product. MemConstantEntry { interned, field. value [LalinCode.CodeValueId], number_value [number], },
  sum. MemConstantProjection { MemConstantKnown { variant_unique, number_value [number], }, MemConstantUnavailable, },
  product. MemLoadedPlaceEntry { interned, place [LalinCode.CodePlace], field. value [LalinCode.CodeValueId], },
  sum. MemScaledStride { MemScaledStrideKnown { variant_unique, elems [number], }, MemScaledStrideDynamic, },
  product. MemScaledStrideEntry { interned, field. value [LalinCode.CodeValueId], stride [LalinMem.MemScaledStride], },
  product. MemDependenceAccess {
    access [LalinMem.MemAccessFact],
    object [LalinMem.MemObjectLookup],
    loop [optional [LalinGraph.GraphLoopId]],
    safety [LalinMem.MemAccessSafetyDecision],
    order [number],
  },
  product. MemTransferFacet {
    values [many [LalinMem.MemValueObjectEntry]],
    locals [many [LalinMem.MemLocalObjectEntry]],
    constants [many [LalinMem.MemConstantEntry]],
    index_offsets [many [LalinMem.MemIndexOffsetEntry]],
    loaded_places [many [LalinMem.MemLoadedPlaceEntry]],
    scaled_strides [many [LalinMem.MemScaledStrideEntry]],
    objects [many [LalinMem.MemObjectFact]],
    accesses [many [LalinMem.MemAccessFact]],
    dependence_accesses [many [LalinMem.MemDependenceAccess]],
    intervals [many [LalinMem.MemAccessInterval]],
    safety [many [LalinMem.MemAccessSafetyFact]],
    relations [many [LalinMem.MemObjectRelation]],
    backend [many [LalinMem.MemBackendAccessInfo]],
    proofs [many [LalinMem.MemProof]],
  },
  product. MemInstructionTransferInput {
    func [LalinCode.CodeFunc],
    block [LalinCode.CodeBlock],
    inst [LalinCode.CodeInst],
    loop [optional [LalinGraph.GraphLoopId]],
    globals [many [LalinMem.MemGlobalObjectEntry]],
    data [many [LalinMem.MemDataObjectEntry]],
    inductions [LalinFlow.FlowInductionProjection],
    flow [LalinFlow.FlowFactSet],
    contracts [LalinMem.MemContractProjection],
    facet [LalinMem.MemTransferFacet],
  },
  sum. MemInstructionTransferResult {
    MemTransferUpdated { variant_unique, facet [LalinMem.MemTransferFacet], },
    MemTransferUnchanged { variant_unique, facet [LalinMem.MemTransferFacet], },
  },
  product. MemModuleObjects { objects [many [LalinMem.MemObjectFact]], globals [many [LalinMem.MemGlobalObjectEntry]], data [many [LalinMem.MemDataObjectEntry]], },
  product. MemDependenceAccumulation { facts [many [LalinMem.MemDependenceFact]], proofs [many [LalinMem.MemProof]], },
  -- Alias/dependence relations and decisions are typed alternatives.
  product. MemSameStoreEntry { interned, a [LalinMem.MemObjectId], b [LalinMem.MemObjectId], proof [LalinMem.MemProof], },
  product. MemDisjointEntry { interned, a [LalinMem.MemObjectId], b [LalinMem.MemObjectId], proof [LalinMem.MemProof], },
  product. MemNoAliasEntry { interned, object [LalinMem.MemObjectId], proof [LalinMem.MemProof], },
  product. MemAccessModeEntry { interned, object [LalinMem.MemObjectId], mode [LalinMem.MemAccessMode], proof [LalinMem.MemProof], },
  product. MemRelationProjection { same_store [many [LalinMem.MemSameStoreEntry]], disjoint [many [LalinMem.MemDisjointEntry]], noalias [many [LalinMem.MemNoAliasEntry]], access_modes [many [LalinMem.MemAccessModeEntry]], },
  sum. MemObjectPairDecision {
    MemObjectPairIndependent { variant_unique, proof [LalinMem.MemProof], reason [str], },
    MemObjectPairDependent { variant_unique, reason [str], },
    MemObjectPairUnproven { variant_unique, reason [str], },
  },
  product. MemDependenceRequest { before [LalinMem.MemDependenceAccess], after [LalinMem.MemDependenceAccess], relations [LalinMem.MemRelationProjection], },
  sum. MemDependenceResult {
    MemDependenceClassified { variant_unique, fact [LalinMem.MemDependenceFact], decision [LalinMem.MemObjectPairDecision], },
    MemDependenceNotComparable { variant_unique, reason [str], },
  },

  sum. MemRelationContribution { MemRelationNone, MemRelationSameStore { variant_unique, entry [LalinMem.MemSameStoreEntry], }, },
  product. MemSemanticFactSet {
    interned,
    field. module [LalinCode.CodeModuleId],
    objects [many [LalinMem.MemObjectFact]],
    leases [many [LalinMem.MemLeaseGrant]],
    accesses [many [LalinMem.MemAccessFact]],
    intervals [many [LalinMem.MemAccessInterval]],
    safety [many [LalinMem.MemAccessSafetyFact]],
    effects [many [LalinMem.MemObjectEffectFact]],
    dependences [many [LalinMem.MemDependenceFact]],
    relations [many [LalinMem.MemObjectRelation]],
    backend_info [many [LalinMem.MemBackendAccessInfo]],
    proofs [many [LalinMem.MemProof]],
  },
  product. MemFactSet {
    interned,
    field. module [LalinCode.CodeModuleId],
    accesses [many [LalinMem.MemAccessFact]],
    aliases [many [LalinMem.MemAliasFact]],
    dependences [many [LalinMem.MemDependenceFact]],
    proofs [many [LalinMem.MemProof]],
  },
}
