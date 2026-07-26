local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCMat {
  product. CMatKernelId { interned, text [str], },
  product. CMatLocalId { interned, text [str], },

  sum. CMatConstCapability {
    CMatConstEligible,
    CMatConstIneligible { variant_unique, reason [str], },
  },
  sum. CMatRestrictCapability {
    CMatRestrictEligible,
    CMatRestrictIneligible { variant_unique, reason [str], },
  },
  sum. CMatLaneCapability {
    CMatLaneFromTarget,
    CMatLaneNative,
    CMatLaneFixed { variant_unique, lanes [number], },
  },
  sum. CMatAccessMutability {
    CMatAccessReadOnly,
    CMatAccessWriteOnly,
    CMatAccessReadWrite,
    CMatAccessReduce,
  },

  product. CMatAccessBinding {
    interned,
    access [LalinStencil.StencilAccessRef],
    source [LalinStencil.StencilAccess],
    local_id [LalinCMat.CMatLocalId],
    field. ty [LalinCode.CodeType],
    layout [LalinStencil.StencilAccessLayout],
    mutability [LalinCMat.CMatAccessMutability],
    restrict_capability [LalinCMat.CMatRestrictCapability],
    const_capability [LalinCMat.CMatConstCapability],
    alignment [LalinStencil.StencilAlignmentFact],
  },
  product. CMatAccessBindingInput { interned, local_id [LalinCMat.CMatLocalId], },
  sum. CMatAccessBindingResult {
    CMatAccessBound { variant_unique, binding [LalinCMat.CMatAccessBinding], },
    CMatAccessBindingRejected { variant_unique, issue [LalinCMat.CMatMaterializationIssue], },
  },
  sum. CMatAccessCollection {
    CMatAccessCollectionReady { variant_unique, bindings [many [LalinCMat.CMatAccessBinding]], },
    CMatAccessCollectionRejected { variant_unique, issues [many [LalinCMat.CMatMaterializationIssue]], },
  },

  sum. CMatLoopOrder { CMatLoopForward, CMatLoopBackward, },
  product. CMatLoopAxis {
    interned,
    axis [LalinStencil.StencilAxisRef],
    index [LalinCMat.CMatLocalId],
    index_ty [LalinCode.CodeType],
    step [number],
    order [LalinCMat.CMatLoopOrder],
  },
  sum. CMatTailPolicy { CMatTailScalar, CMatTailMask, CMatTailOverreadProvenSafe, },
  sum. CMatVectorPolicy {
    CMatVectorNone,
    CMatVectorAutovec { variant_unique, lanes [LalinCMat.CMatLaneCapability], tail [LalinCMat.CMatTailPolicy], },
    CMatVectorExplicit { variant_unique, lanes [LalinCMat.CMatLaneCapability], tail [LalinCMat.CMatTailPolicy], },
  },
  product. CMatSchedulePolicy {
    interned,
    unroll [number],
    interleave [number],
    vector [LalinCMat.CMatVectorPolicy],
  },
  product. CMatLoopNest {
    interned,
    axes [many [LalinCMat.CMatLoopAxis]],
    policy [LalinCMat.CMatSchedulePolicy],
  },
  sum. CMatLoopPlan {
    CMatLoopPlanned { variant_unique, axes [many [LalinCMat.CMatLoopAxis]], },
    CMatLoopRejected { variant_unique, issue [LalinCMat.CMatMaterializationIssue], },
  },

  sum. CMatStreamMaterialization {
    CMatStreamInline { variant_unique, stream [LalinStencil.StencilStreamRef], field. ty [LalinCode.CodeType], },
    CMatStreamLocal {
      variant_unique,
      stream [LalinStencil.StencilStreamRef],
      local_id [LalinCMat.CMatLocalId],
      field. ty [LalinCode.CodeType],
    },
  },
  sum. CMatSinkMaterialization {
    CMatSinkInline { variant_unique, sink [LalinStencil.StencilSinkRef], },
    CMatSinkValueResult {
      variant_unique,
      sink [LalinStencil.StencilSinkRef],
      local_id [LalinCMat.CMatLocalId],
      field. ty [LalinCode.CodeType],
    },
    CMatSinkStoreResult { variant_unique, sink [LalinStencil.StencilSinkRef], dst [LalinStencil.StencilAccessRef], },
    CMatSinkControlResult { variant_unique, sink [LalinStencil.StencilSinkRef], },
  },

  product. CMatFusedKernel {
    interned,
    field. id [LalinCMat.CMatKernelId],
    computation [LalinStencil.StencilComputation],
    loop [LalinCMat.CMatLoopNest],
    accesses [many [LalinCMat.CMatAccessBinding]],
    streams [many [LalinCMat.CMatStreamMaterialization]],
    sinks [many [LalinCMat.CMatSinkMaterialization]],
    schedule [LalinStencil.StencilSchedule],
    proofs [many [LalinKernel.KernelProof]],
  },
  sum. CMatMaterializationIssue {
    CMatIssueUnsupportedProducer { variant_unique, producer [LalinStencil.StencilProducerShape], reason [str], },
    CMatIssueUnsupportedAccess { variant_unique, access [LalinStencil.StencilAccess], reason [str], },
    CMatIssueUnsupportedSchedule { variant_unique, schedule [LalinStencil.StencilSchedule], reason [str], },
    CMatIssueUnsupportedSink { variant_unique, sink [LalinStencil.StencilSinkDef], reason [str], },
    CMatIssueMissingProof { variant_unique, requirement [LalinStencil.StencilProofRequirement], reason [str], },
  },
  product. CMatMaterializationInput { interned, kernel [LalinCMat.CMatKernelId], },
  product. CMatKernelMaterializationInput { interned, kernel [LalinCMat.CMatKernelId], },
  sum. CMatMaterialization {
    CMatMaterializedFused { variant_unique, kernel [LalinCMat.CMatFusedKernel], },
    CMatMaterializedKernelFragment {
      variant_unique,
      kernel [LalinCMat.CMatFusedKernel],
      provenance [LalinStencil.StencilKernelProvenanceFacet],
    },
    CMatRejectedComputation {
      variant_unique,
      computation [LalinStencil.StencilComputation],
      issues [many [LalinCMat.CMatMaterializationIssue]],
    },
    CMatRejectedKernelFragment {
      variant_unique,
      computation [LalinStencil.StencilComputation],
      provenance [LalinStencil.StencilKernelProvenanceFacet],
      issues [many [LalinCMat.CMatMaterializationIssue]],
    },
  },
  product. CMatCEmissionInput {
    interned,
    module_name [str],
    symbol [str],
    target [LalinC.CBackendTarget],
  },
  sum. CMatCEmissionIssue {
    CMatCEmissionMaterializationIssue { variant_unique, issue [LalinCMat.CMatMaterializationIssue], },
    CMatCEmissionUnsupportedProducer { variant_unique, producer [LalinStencil.StencilProducerShape], reason [str], },
    CMatCEmissionUnsupportedAccess { variant_unique, access [LalinStencil.StencilAccess], reason [str], },
    CMatCEmissionUnsupportedStream { variant_unique, stream [LalinStencil.StencilStreamDef], reason [str], },
    CMatCEmissionUnsupportedSink { variant_unique, sink [LalinStencil.StencilSinkDef], reason [str], },
    CMatCEmissionUnsupportedPoint { variant_unique, field. expr [LalinStencil.StencilPointExpr], reason [str], },
    CMatCEmissionUnsupportedValue { variant_unique, field. value [LalinValue.ValueExpr], reason [str], },
    CMatCEmissionInvalidKernel { variant_unique, reason [str], },
    CMatCEmissionMissingValue { variant_unique, field. value [LalinCode.CodeValueId], },
    CMatCEmissionMissingAccess { variant_unique, access [LalinStencil.StencilAccessRef], },
    CMatCEmissionMissingExit { variant_unique, role [LalinCMat.CMatCExitRole], },
    CMatCEmissionValidationRejected { variant_unique, issues [many [LalinC.CBackendValidationIssue]], },
  },
  sum. CMatCEmission {
    CMatCEmitted { variant_unique, field. unit [LalinC.CBackendUnit], },
    CMatCRejected { variant_unique, issues [many [LalinCMat.CMatCEmissionIssue]], },
  },

  product. CMatCAccessCEntry {
    interned,
    access [LalinStencil.StencilAccessRef],
    binding [LalinCMat.CMatAccessBinding],
    param [LalinC.CBackendLocal],
    stride [number],
  },
  product. CMatCAccessCProjection { interned, entries [many [LalinCMat.CMatCAccessCEntry]], },
  sum. CMatCAccessCLookup {
    CMatCAccessCFound { variant_unique, entry [LalinCMat.CMatCAccessCEntry], },
    CMatCAccessCMissing { variant_unique, access [LalinStencil.StencilAccessRef], },
  },
  sum. CMatCAccessCBindingResult {
    CMatCAccessCBindingReady { variant_unique, entry [LalinCMat.CMatCAccessCEntry], },
    CMatCAccessCBindingRejected { variant_unique, issue [LalinCMat.CMatCEmissionIssue], },
  },
  sum. CMatCAccessCCollection {
    CMatCAccessCCollectionReady { variant_unique, entries [many [LalinCMat.CMatCAccessCEntry]], },
    CMatCAccessCCollectionRejected { variant_unique, issues [many [LalinCMat.CMatCEmissionIssue]], },
  },

  product. CMatCStreamDefEntry { interned, stream [LalinStencil.StencilStreamRef], def [LalinStencil.StencilStreamDef], },
  product. CMatCStreamDefProjection { interned, entries [many [LalinCMat.CMatCStreamDefEntry]], },
  sum. CMatCStreamDefLookup {
    CMatCStreamDefFound { variant_unique, entry [LalinCMat.CMatCStreamDefEntry], },
    CMatCStreamDefMissing { variant_unique, stream [LalinStencil.StencilStreamRef], },
  },
  product. CMatCSinkDefEntry { interned, sink [LalinStencil.StencilSinkRef], def [LalinStencil.StencilSinkDef], },
  product. CMatCSinkDefProjection { interned, entries [many [LalinCMat.CMatCSinkDefEntry]], },
  sum. CMatCSinkDefLookup {
    CMatCSinkDefFound { variant_unique, entry [LalinCMat.CMatCSinkDefEntry], },
    CMatCSinkDefMissing { variant_unique, sink [LalinStencil.StencilSinkRef], },
  },
  product. CMatCStreamValueEntry {
    interned,
    field. name [str],
    stream [LalinStencil.StencilStreamRef],
    local_id [LalinC.CBackendLocalId],
    field. ty [LalinC.CBackendType],
  },
  product. CMatCStreamValueProjection { interned, entries [many [LalinCMat.CMatCStreamValueEntry]], },
  sum. CMatCStreamValueLookup {
    CMatCStreamValueFound { variant_unique, entry [LalinCMat.CMatCStreamValueEntry], },
    CMatCStreamValueMissing { variant_unique, field. name [str], },
  },

  product. CMatCFunctionState {
    interned,
    index [LalinC.CBackendLocalId],
    index_ty [LalinC.CBackendType],
    accesses [LalinCMat.CMatCAccessCProjection],
    stream_defs [LalinCMat.CMatCStreamDefProjection],
    sink_defs [LalinCMat.CMatCSinkDefProjection],
    values [LalinCMat.CMatCStreamValueProjection],
    locals [many [LalinC.CBackendLocal]],
    entry_stmts [many [LalinC.CBackendStmt]],
    body_stmts [many [LalinC.CBackendStmt]],
    helpers [many [LalinC.CBackendHelperUse]],
    next_local [number],
  },
  product. CMatCLocalAllocation { interned, state [LalinCMat.CMatCFunctionState], c_local [LalinC.CBackendLocal], },
  product. CMatCHelperAllocation { interned, state [LalinCMat.CMatCFunctionState], helper [LalinC.CBackendHelperId], },
  product. CMatCDefProjections {
    interned,
    streams [LalinCMat.CMatCStreamDefProjection],
    sinks [LalinCMat.CMatCSinkDefProjection],
  },
  sum. CMatCStateStep {
    CMatCStateReady { variant_unique, state [LalinCMat.CMatCFunctionState], },
    CMatCStateRejected { variant_unique, issues [many [LalinCMat.CMatCEmissionIssue]], },
  },
  sum. CMatCPointEmission {
    CMatCPointEmitted {
      variant_unique,
      state [LalinCMat.CMatCFunctionState],
      atom [LalinC.CBackendAtom],
      field. ty [LalinC.CBackendType],
    },
    CMatCPointRejected { variant_unique, issues [many [LalinCMat.CMatCEmissionIssue]], },
  },
  sum. CMatCAtomEmission {
    CMatCAtomEmitted { variant_unique, atom [LalinC.CBackendAtom], field. ty [LalinC.CBackendType], },
    CMatCAtomRejected { variant_unique, issue [LalinCMat.CMatCEmissionIssue], },
  },
  sum. CMatCBinarySelection {
    CMatCBinarySelected { variant_unique, spec [LalinC.CBackendHelperSpec], },
    CMatCBinaryRejected { variant_unique, reason [str], },
  },
  product. CMatCLoopDirectionPlan {
    interned,
    compare [LalinCore.CmpOp],
    step_op [LalinCore.BinaryOp],
  },
  sum. CMatCSinkEmission {
    CMatCSinkVoidEmitted { variant_unique, state [LalinCMat.CMatCFunctionState], },
    CMatCSinkValueEmitted {
      variant_unique,
      state [LalinCMat.CMatCFunctionState],
      atom [LalinC.CBackendAtom],
      field. ty [LalinC.CBackendType],
    },
    CMatCSinkRejected { variant_unique, issues [many [LalinCMat.CMatCEmissionIssue]], },
  },

  product. CMatCExternalValueBindingEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    c_local [LalinC.CBackendLocal],
  },
  product. CMatCExternalValueBindingProjection {
    interned,
    entries [many [LalinCMat.CMatCExternalValueBindingEntry]],
  },
  sum. CMatCExternalValueBindingLookup {
    CMatCExternalValueBindingFound { variant_unique, entry [LalinCMat.CMatCExternalValueBindingEntry], },
    CMatCExternalValueBindingMissing { variant_unique, field. value [LalinCode.CodeValueId], },
  },
  sum. CMatCFragmentAccessSource {
    CMatCFragmentAccessDirect { variant_unique, base [LalinC.CBackendLocal], },
    CMatCFragmentAccessAddressProjected {
      variant_unique,
      address [LalinFlow.FlowAddressId],
      base [LalinC.CBackendLocal],
    },
  },
  product. CMatCFragmentAccessBindingEntry {
    interned,
    access [LalinStencil.StencilAccessRef],
    lane [LalinKernel.KernelLaneId],
    mem_access [LalinMem.MemAccessId],
    source [LalinCMat.CMatCFragmentAccessSource],
    elem_size [number],
    stride [number],
    alignment [LalinMem.MemAlignment],
  },
  product. CMatCFragmentAccessBindingProjection {
    interned,
    entries [many [LalinCMat.CMatCFragmentAccessBindingEntry]],
  },
  sum. CMatCFragmentAccessBindingLookup {
    CMatCFragmentAccessBindingFound { variant_unique, entry [LalinCMat.CMatCFragmentAccessBindingEntry], },
    CMatCFragmentAccessBindingMissing { variant_unique, access [LalinStencil.StencilAccessRef], },
  },
  sum. CMatCExitRole {
    CMatCExitNormal,
    CMatCExitSuccess,
    CMatCExitFailure,
    CMatCExitFound,
    CMatCExitNotFound,
  },
  product. CMatCExitBindingEntry {
    interned,
    role [LalinCMat.CMatCExitRole],
    source [LalinCode.CodeBlockId],
    label [LalinC.CBackendLabel],
    args [many [LalinC.CBackendAtom]],
  },
  product. CMatCExitBindingProjection {
    interned,
    entries [many [LalinCMat.CMatCExitBindingEntry]],
  },
  sum. CMatCExitBindingLookup {
    CMatCExitBindingFound { variant_unique, entry [LalinCMat.CMatCExitBindingEntry], },
    CMatCExitBindingMissing { variant_unique, role [LalinCMat.CMatCExitRole], },
  },
  product. CMatCFragmentNamespace { interned, prefix [str], },
  sum. CMatCBlockAlignment {
    CMatCBlockEliminated { variant_unique, source [LalinCode.CodeBlockId], },
    CMatCBlockReplacementEntry {
      variant_unique,
      source [LalinCode.CodeBlockId],
      replacement [LalinC.CBackendLabel],
    },
  },
  product. CMatCValueMapping { interned, field. value [LalinCode.CodeValueId], c_local [LalinC.CBackendLocal], },
  sum. CMatCControlResult {
    CMatCControlNone,
    CMatCControlValue { variant_unique, atom [LalinC.CBackendAtom], field. ty [LalinC.CBackendType], },
    CMatCControlBranch { variant_unique, success [LalinC.CBackendLabel], failure [LalinC.CBackendLabel], },
  },
  product. CMatCFragmentInput {
    interned,
    materialization [LalinCMat.CMatMaterialization],
    code_func [LalinCode.CodeFunc],
    covered_blocks [many [LalinCode.CodeBlockId]],
    target [LalinC.CBackendTarget],
    values [LalinCMat.CMatCExternalValueBindingProjection],
    accesses [LalinCMat.CMatCFragmentAccessBindingProjection],
    exits [LalinCMat.CMatCExitBindingProjection],
    namespace [LalinCMat.CMatCFragmentNamespace],
  },
  product. CMatCFragment {
    interned,
    entry [LalinC.CBackendLabel],
    blocks [many [LalinC.CBackendBlock]],
    locals [many [LalinC.CBackendLocal]],
    helpers [many [LalinC.CBackendHelperUse]],
    block_alignments [many [LalinCMat.CMatCBlockAlignment]],
    value_mappings [many [LalinCMat.CMatCValueMapping]],
    control [LalinCMat.CMatCControlResult],
  },
  sum. CMatCFragmentEmission {
    CMatCFragmentEmitted { variant_unique, fragment [LalinCMat.CMatCFragment], },
    CMatCFragmentRejected { variant_unique, issues [many [LalinCMat.CMatCEmissionIssue]], },
  },
  product. CMatWindowIndexInput {
    interned,
    boundary [LalinStencil.StencilWindowBoundary],
    index [LalinC.CBackendAtom],
    lower [LalinC.CBackendAtom],
    upper [LalinC.CBackendAtom],
    field. ty [LalinC.CBackendType],
  },
  sum. CMatWindowIndexDecision {
    CMatWindowIndexInBounds { variant_unique, index [LalinC.CBackendAtom], },
    CMatWindowIndexClamped { variant_unique, index [LalinC.CBackendAtom], },
    CMatWindowIndexWrapped { variant_unique, index [LalinC.CBackendAtom], },
    CMatWindowIndexZero { variant_unique, field. value [LalinC.CBackendAtom], },
    CMatWindowIndexRejected { variant_unique, issue [LalinCMat.CMatCEmissionIssue], },
  },

  product. CMatModule {
    interned,
    field. module [LalinCode.CodeModuleId],
    kernels [many [LalinCMat.CMatMaterialization]],
  },
}
