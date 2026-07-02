local S = require("lalin.schema.dsl")
S.use()

return schema. LalinNative {
  product. NativeTargetId { interned, text [str], },
  product. NativeRuntimeSymbolId { interned, text [str], },
  product. NativeTemplateId { interned, text [str], },
  product. NativeTemplateFamilyId { interned, text [str], },
  product. NativeTemplateNodeId { interned, text [str], },
  product. NativeTemplateValueId { interned, text [str], },
  product. NativePatchHoleId { interned, text [str], },
  product. NativeExecutableId { interned, text [str], },
  product. NativeBankId { interned, text [str], },
  product. NativeRegisterId { interned, text [str], },
  product. NativeTemplateSupportDomainId { interned, text [str], },
  product. NativeFrameSlotId { interned, text [str], },
  product. NativeContinuationSymbolId { interned, text [str], },

  sum. NativeArch {
    NativeArchX64,
    NativeArchAArch64,
  },

  sum. NativeOs {
    NativeOsLinux,
    NativeOsDarwin,
    NativeOsWindows,
  },

  sum. NativeAbiKind {
    NativeAbiSysV,
    NativeAbiWin64,
    NativeAbiAapcs64,
  },

  sum. NativeEndian {
    NativeLittleEndian,
    NativeBigEndian,
  },

  sum. NativeMachineScalarRep {
    NativeScalarBool8,
    NativeScalarInt {
      variant_unique,
      field. bits [number],
      field. signedness [LalinCode.CodeIntSignedness],
    },
    NativeScalarIndex { variant_unique, field. bits [number], },
    NativeScalarPointer { variant_unique, field. bits [number], },
    NativeScalarFloat { variant_unique, field. bits [number], },
  },

  sum. NativeRegisterClass {
    NativeRegisterClassGpr,
    NativeRegisterClassPointer,
    NativeRegisterClassFloat,
    NativeRegisterClassVector,
    NativeRegisterClassFlags,
  },

  product. NativeRegister {
    interned,
    field. id [LalinNative.NativeRegisterId],
    field. target [LalinNative.NativeTarget],
    field. class [LalinNative.NativeRegisterClass],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. machine_name [str],
  },

  product. NativeStackSlot {
    interned,
    field. offset [number],
    field. size [number],
    field. alignment [number],
  },

  product. NativeFrameSlot {
    interned,
    field. id [LalinNative.NativeFrameSlotId],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. offset [number],
    field. size [number],
    field. alignment [number],
  },

  product. NativeFrameLayout {
    interned,
    field. slots [many [LalinNative.NativeFrameSlot]],
    field. size [number],
    field. alignment [number],
  },

  product. NativeContinuationSymbol {
    interned,
    field. id [LalinNative.NativeContinuationSymbolId],
    field. name [str],
  },

  sum. NativeExtensionPolicy {
    NativeSignExtend,
    NativeZeroExtend,
    NativeTruncateToWidth,
    NativePreserveLowerBits,
  },

  sum. NativeScratchRole {
    NativeScratchGeneral,
    NativeScratchAddress,
    NativeScratchInteger,
    NativeScratchFloat,
    NativeScratchVector,
  },

  sum. NativeAccumulatorRole {
    NativeAccumulatorGeneral,
    NativeAccumulatorInteger,
    NativeAccumulatorFloat,
    NativeAccumulatorPredicate,
  },

  sum. NativeValueLocation {
    NativeValueRegisterLocation { field. register [LalinNative.NativeRegister], },
    NativeValueStackSlotLocation { field. slot [LalinNative.NativeStackSlot], },
    NativeValueFrameSlotLocation { field. slot [LalinNative.NativeFrameSlot], },
    NativeValueRuntimeParamLocation {
      field. param_index [number],
      field. scalar [LalinNative.NativeMachineScalarRep],
      field. extension [LalinNative.NativeExtensionPolicy],
    },
    NativeValuePatchCoordinateLocation { field. coordinate [LalinNative.NativePatchCoordinate], },
    NativeValueAccumulatorLocation {
      field. role [LalinNative.NativeAccumulatorRole],
      field. register [LalinNative.NativeRegister],
    },
    NativeValueMemoryAddressLocation {
      field. base [LalinNative.NativeTemplateValueId],
      field. offset [LalinNative.NativePatchCoordinate],
      field. address_scalar [LalinNative.NativeMachineScalarRep],
    },
  },

  product. NativeValuePlacement {
    interned,
    field. value [LalinNative.NativeTemplateValueId],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. location [LalinNative.NativeValueLocation],
  },

  product. NativeAbiParamPlacement {
    interned,
    field. param_index [number],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. location [LalinNative.NativeValueLocation],
    field. extension [LalinNative.NativeExtensionPolicy],
  },

  product. NativeAbiResultPlacement {
    interned,
    field. result_index [number],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. location [LalinNative.NativeValueLocation],
    field. extension [LalinNative.NativeExtensionPolicy],
  },

  product. NativeScalarSupport {
    interned,
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. code_type [LalinCode.CodeType],
    field. extension [LalinNative.NativeExtensionPolicy],
  },

  sum. NativeRegisterUse {
    NativeRegisterUseParam,
    NativeRegisterUseResult,
    NativeRegisterUseScratch { field. role [LalinNative.NativeScratchRole], },
    NativeRegisterUseAccumulator { field. role [LalinNative.NativeAccumulatorRole], },
  },

  product. NativeRegisterSupport {
    interned,
    field. register [LalinNative.NativeRegister],
    field. scalars [many [LalinNative.NativeMachineScalarRep]],
    field. uses [many [LalinNative.NativeRegisterUse]],
  },

  product. NativeAbiScalarConvention {
    interned,
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. params [many [LalinNative.NativeAbiParamPlacement]],
    field. results [many [LalinNative.NativeAbiResultPlacement]],
  },

  product. NativeTemplateSupportDomain {
    interned,
    field. id [LalinNative.NativeTemplateSupportDomainId],
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
    field. scalars [many [LalinNative.NativeScalarSupport]],
    field. registers [many [LalinNative.NativeRegisterSupport]],
    field. abi [many [LalinNative.NativeAbiScalarConvention]],
    field. call_protocols [many [LalinNative.NativeCallProtocol]],
    field. register_protocols [many [LalinNative.NativeRegisterProtocol]],
    field. scratch_roles [many [LalinNative.NativeScratchRole]],
    field. accumulator_roles [many [LalinNative.NativeAccumulatorRole]],
    field. vector_lanes [many [number]],
    field. ranks [many [number]],
    field. unroll_factors [many [number]],
  },

  product. NativeTemplateSourceBuildInput {
    interned,
    field. domain [LalinNative.NativeTemplateSupportDomain],
  },

  product. NativeScalarTemplateSourceBuildInput {
    interned,
    field. domain [LalinNative.NativeTemplateSupportDomain],
    field. support [LalinNative.NativeScalarSupport],
  },

  product. NativeCodeValuePlacementEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    field. placement [LalinNative.NativeValuePlacement],
  },

  product. NativeCodeGraphBuilderState {
    field. nodes [many [LalinNative.NativeTemplateNode]],
    field. control_edges [many [LalinNative.NativeControlEdge]],
    field. value_edges [many [LalinNative.NativeValueEdge]],
    field. placements [many [LalinNative.NativeCodeValuePlacementEntry]],
    field. frame_slots [many [LalinNative.NativeFrameSlot]],
    field. next_frame_offset [number],
  },

  product. NativeCodeGraphBuildInput {
    field. plan [LalinNative.NativePlanInput],
    field. state [LalinNative.NativeCodeGraphBuilderState],
  },

  product. NativeTarget {
    interned,
    field. id [LalinNative.NativeTargetId],
    field. arch [LalinNative.NativeArch],
    field. os [LalinNative.NativeOs],
    field. abi [LalinNative.NativeAbiKind],
    field. pointer_bits [number],
    field. endian [LalinNative.NativeEndian],
  },

  product. NativeRuntimeSymbol {
    interned,
    field. id [LalinNative.NativeRuntimeSymbolId],
    field. name [str],
    field. c_signature [str],
  },

  product. NativeRuntime {
    interned,
    field. symbols [many [LalinNative.NativeRuntimeSymbol]],
  },

  sum. NativeCompileSubject {
    NativeCompileCodeModule { field. module [LalinCode.CodeModule], },
    NativeCompileCodeFunc { field. func [LalinCode.CodeFunc], },
    NativeCompileKernelPlan { field. plan [LalinKernel.KernelPlan], },
    NativeCompileStencilInstance { field. instance [LalinStencil.StencilInstance], },
  },

  product. NativeCompileRequest {
    interned,
    field. subject [LalinNative.NativeCompileSubject],
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
    field. bank [LalinNative.NativeTemplateBank],
  },

  product. NativePlanInput {
    interned,
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
    field. bank [LalinNative.NativeTemplateBank],
  },

  product. NativeCompileResult {
    interned,
    field. executable [LalinNative.NativeExecutable],
  },

  sum. NativeTemplateExtraction {
    NativeExtractStandaloneCallable,
    NativeExtractEntryCallable {
      field. frame_bytes [LalinNative.NativePatchCoordinate],
      field. first_continuation [LalinNative.NativeContinuationSymbol],
    },
    NativeExtractContinuationFragment {
      field. successors [many [LalinNative.NativeContinuationSymbol]],
    },
    NativeExtractTerminalContinuation,
  },

  product. NativeTemplateSource {
    interned,
    field. id [LalinNative.NativeTemplateId],
    field. family [LalinNative.NativeTemplateFamily],
    field. extraction [LalinNative.NativeTemplateExtraction],
    field. entry_symbol [str],
    field. c_text [str],
    field. declared_holes [many [LalinNative.NativeHoleLayout]],
  },

  product. NativeTemplateCompileInput {
    interned,
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
  },

  product. NativeTemplateBytes {
    interned,
    field. bytes [str],
    field. size [number],
  },

  product. NativeTextSection {
    interned,
    field. bytes [LalinNative.NativeTemplateBytes],
    field. alignment [number],
  },

  product. NativeSymbol {
    interned,
    field. name [str],
    field. offset [number],
    field. size [number],
  },

  sum. NativeRelocation {
    NativeRelocationRel32 {
      field. offset [number],
      field. symbol [str],
      field. addend [number],
    },
    NativeRelocationAbs64 {
      field. offset [number],
      field. symbol [str],
      field. addend [number],
    },
    NativeRelocationRuntimeSymbol {
      field. offset [number],
      field. symbol [LalinNative.NativeRuntimeSymbolId],
      field. addend [number],
    },
    NativeRelocationContinuation {
      field. offset [number],
      field. symbol [LalinNative.NativeContinuationSymbol],
      field. addend [number],
    },
  },

  product. NativeCompiledTemplate {
    interned,
    field. id [LalinNative.NativeTemplateId],
    field. family [LalinNative.NativeTemplateFamily],
    field. target [LalinNative.NativeTarget],
    field. text [LalinNative.NativeTextSection],
    field. symbols [many [LalinNative.NativeSymbol]],
    field. relocations [many [LalinNative.NativeRelocation]],
    field. holes [many [LalinNative.NativeHoleLayout]],
  },

  sum. NativeTemplateCompileResult {
    NativeTemplateCompiled {
      field. template [LalinNative.NativeCompiledTemplate],
    },
    NativeTemplateCompileRejected {
      field. rejects [many [LalinNative.NativeTemplateBuildReject]],
    },
  },

  sum. NativeTemplateBuildReject {
    NativeBuildRejectEmptySource {
      field. source [LalinNative.NativeTemplateId],
      field. reason [str],
    },
    NativeBuildRejectCompileError {
      field. source [LalinNative.NativeTemplateId],
      field. reason [str],
    },
    NativeBuildRejectEmptyText {
      field. source [LalinNative.NativeTemplateId],
      field. reason [str],
    },
    NativeBuildRejectMissingEntrySymbol {
      field. source [LalinNative.NativeTemplateId],
      field. symbol [str],
    },
    NativeBuildRejectUnsupportedRelocation {
      field. source [LalinNative.NativeTemplateId],
      field. offset [number],
      field. relocation_name [str],
      field. reason [str],
    },
    NativeBuildRejectHoleOutOfRange {
      field. source [LalinNative.NativeTemplateId],
      field. hole [LalinNative.NativePatchHoleId],
      field. offset [number],
      field. width [number],
    },
    NativeBuildRejectMissingHole {
      field. source [LalinNative.NativeTemplateId],
      field. hole [LalinNative.NativePatchHoleId],
      field. symbol [str],
    },
    NativeBuildRejectUnexpectedSymbol {
      field. source [LalinNative.NativeTemplateId],
      field. symbol [str],
      field. reason [str],
    },
    NativeBuildRejectRoleMismatch {
      field. source [LalinNative.NativeTemplateId],
      field. reason [str],
    },
  },

  product. NativeTemplateBankRequest {
    interned,
    field. id [LalinNative.NativeBankId],
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
    field. sources [many [LalinNative.NativeTemplateSource]],
  },

  sum. NativeTemplateBankBuildResult {
    NativeTemplateBankBuilt {
      field. bank [LalinNative.NativeTemplateBank],
    },
    NativeTemplateBankBuildRejected {
      field. rejects [many [LalinNative.NativeTemplateBuildReject]],
    },
  },

  product. NativeTemplateBank {
    interned,
    field. id [LalinNative.NativeBankId],
    field. target [LalinNative.NativeTarget],
    field. entries [many [LalinNative.NativeTemplateBankEntry]],
  },

  product. NativeTemplateBankEntry {
    interned,
    field. family [LalinNative.NativeTemplateFamily],
    S.field("compiled", LalinNative.NativeCompiledTemplate),
  },

  product. NativeTemplateSelectionInput {
    interned,
    field. target [LalinNative.NativeTarget],
    field. family [LalinNative.NativeTemplateFamily],
  },

  sum. NativeTemplateSelectionResult {
    NativeTemplateSelected {
      field. entry [LalinNative.NativeTemplateBankEntry],
    },
    NativeTemplateSelectionRejected {
      field. rejects [many [LalinNative.NativeTemplateSelectionReject]],
    },
    NativeTemplateSelectionAmbiguous {
      field. family [LalinNative.NativeTemplateFamily],
      field. entries [many [LalinNative.NativeTemplateBankEntry]],
    },
  },

  sum. NativeTemplateSelectionReject {
    NativeSelectionRejectTargetMismatch {
      field. expected [LalinNative.NativeTarget],
      field. actual [LalinNative.NativeTarget],
    },
    NativeSelectionRejectFamilyMismatch {
      field. requested [LalinNative.NativeTemplateFamily],
      field. entry [LalinNative.NativeTemplateFamily],
    },
    NativeSelectionRejectMissingBankEntry {
      field. family [LalinNative.NativeTemplateFamily],
    },
  },

  product. NativeEmbeddedTemplate {
    interned,
    field. family [LalinNative.NativeTemplateFamily],
    field. text [LalinNative.NativeTextSection],
    field. symbols [many [LalinNative.NativeSymbol]],
    field. relocations [many [LalinNative.NativeRelocation]],
    field. holes [many [LalinNative.NativeHoleLayout]],
  },

  product. NativeEmbeddedTemplateBank {
    interned,
    field. id [LalinNative.NativeBankId],
    field. target [LalinNative.NativeTarget],
    field. entries [many [LalinNative.NativeEmbeddedTemplate]],
  },

  product. NativeEmbeddedBankImportRequest {
    interned,
    field. embedded [LalinNative.NativeEmbeddedTemplateBank],
  },

  sum. NativeEmbeddedBankImportResult {
    NativeEmbeddedBankImported {
      field. bank [LalinNative.NativeTemplateBank],
    },
    NativeEmbeddedBankRejected {
      field. rejects [many [LalinNative.NativeTemplateBuildReject]],
    },
  },

  product. NativeTemplateFamily {
    interned,
    field. id [LalinNative.NativeTemplateFamilyId],
    field. role [LalinNative.NativeTemplateRole],
    field. axes [many [LalinNative.NativeTemplateAxis]],
    field. protocol [LalinNative.NativeTemplateProtocol],
  },

  sum. NativeTemplateRole {
    NativeRoleCodeFunc,
    NativeRoleCodeBlock,
    NativeRoleCodeInst,
    NativeRoleCodeTerm,
    NativeRoleCodePlace,
    NativeRoleCodeConst,
    NativeRoleKernelDomain,
    NativeRoleKernelExpr,
    NativeRoleKernelEffect,
    NativeRoleKernelResult,
    NativeRoleStencilProducer,
    NativeRoleStencilAccess,
    NativeRoleStencilPoint,
    NativeRoleStencilBody,
    NativeRoleStencilSink,
    NativeRoleStencilSchedule,
    NativeRoleControlEdge,
    NativeRoleRuntimeCall,
  },

  sum. NativeTemplateAxis {
    NativeAxisTarget { field. target [LalinNative.NativeTarget], },
    NativeAxisCodeInst { field. axis [LalinNative.NativeCodeInstAxis], },
    NativeAxisCodeTerm { field. axis [LalinNative.NativeCodeTermAxis], },
    NativeAxisCodePlace { field. axis [LalinNative.NativeCodePlaceAxis], },
    NativeAxisCodeConst { field. axis [LalinNative.NativeCodeConstAxis], },
    NativeAxisCodeType { field. ty [LalinCode.CodeType], },
    NativeAxisCodeSig { field. sig [LalinCode.CodeSig], },
    NativeAxisKernel { field. axis [LalinNative.NativeKernelAxis], },
    NativeAxisStencilProducer { field. axis [LalinNative.NativeStencilProducerAxis], },
    NativeAxisStencilAccess { field. axis [LalinNative.NativeStencilAccessAxis], },
    NativeAxisStencilPoint { field. axis [LalinNative.NativeStencilPointAxis], },
    NativeAxisStencilSink { field. axis [LalinNative.NativeStencilSinkAxis], },
    NativeAxisStencilSchedule { field. axis [LalinNative.NativeStencilScheduleAxis], },
    NativeAxisAbi { field. protocol [LalinNative.NativeCallProtocol], },
    NativeAxisRegisterProtocol { field. protocol [LalinNative.NativeRegisterProtocol], },
    NativeAxisMachineScalar { field. scalar [LalinNative.NativeMachineScalarRep], },
    NativeAxisRegisterClass { field. class [LalinNative.NativeRegisterClass], },
    NativeAxisValuePlacement { field. placement [LalinNative.NativeValuePlacement], },
    NativeAxisAbiParam { field. placement [LalinNative.NativeAbiParamPlacement], },
    NativeAxisAbiResult { field. placement [LalinNative.NativeAbiResultPlacement], },
  },

  product. NativeTemplateProtocol {
    interned,
    field. call [LalinNative.NativeCallProtocol],
    field. registers [LalinNative.NativeRegisterProtocol],
  },

  sum. NativeCodeInstAxis {
    NativeCodeInstConstAxis { field. ty [LalinCode.CodeType], },
    NativeCodeInstAliasAxis { field. ty [LalinCode.CodeType], },
    NativeCodeInstUnaryAxis { field. op [LalinCore.UnaryOp], ty [LalinCode.CodeType], },
    NativeCodeInstBinaryAxis {
      field. op [LalinCore.BinaryOp],
      field. ty [LalinCode.CodeType],
      field. semantics [LalinCode.CodeIntSemantics],
    },
    NativeCodeInstFloatBinaryAxis {
      field. op [LalinCore.BinaryOp],
      field. ty [LalinCode.CodeType],
      field. mode [LalinCode.CodeFloatMode],
    },
    NativeCodeInstCompareAxis {
      field. cmp [LalinCore.CmpOp],
      field. operand_ty [LalinCode.CodeType],
    },
    NativeCodeInstCastAxis {
      field. op [LalinCore.MachineCastOp],
      field. from [LalinCode.CodeType],
      field. to [LalinCode.CodeType],
    },
    NativeCodeInstSelectAxis { field. ty [LalinCode.CodeType], },
    NativeCodeInstIntrinsicAxis {
      field. intrinsic [LalinCore.Intrinsic],
      field. ty [LalinCode.CodeType],
    },
    NativeCodeInstAddrOfAxis { field. ptr_ty [LalinCode.CodeType], },
    NativeCodeInstGlobalRefAxis { field. ptr_ty [LalinCode.CodeType], },
    NativeCodeInstPtrOffsetAxis {
      field. ptr_ty [LalinCode.CodeType],
      field. elem_size [number],
      field. const_offset [number],
    },
    NativeCodeInstLoadAxis { field. access [LalinCode.CodeMemoryAccess], },
    NativeCodeInstStoreAxis { field. access [LalinCode.CodeMemoryAccess], },
    NativeCodeInstAggregateAxis { field. ty [LalinCode.CodeType], },
    NativeCodeInstArrayAxis { field. ty [LalinCode.CodeType], },
    NativeCodeInstViewMakeAxis { field. elem_ty [LalinCode.CodeType], },
    NativeCodeInstViewDataAxis,
    NativeCodeInstViewLenAxis,
    NativeCodeInstViewStrideAxis,
    NativeCodeInstSliceMakeAxis { field. elem_ty [LalinCode.CodeType], },
    NativeCodeInstSliceDataAxis,
    NativeCodeInstSliceLenAxis,
    NativeCodeInstByteSpanMakeAxis,
    NativeCodeInstByteSpanDataAxis,
    NativeCodeInstByteSpanLenAxis,
    NativeCodeInstClosureAxis { field. ty [LalinCode.CodeType], sig [LalinCode.CodeSigId], },
    NativeCodeInstVariantCtorAxis { field. ty [LalinCode.CodeType], variant [LalinCode.CodeVariantRef], },
    NativeCodeInstVariantTagAxis { field. tag_ty [LalinCode.CodeType], },
    NativeCodeInstVariantPayloadAxis { field. variant [LalinCode.CodeVariantRef], },
    NativeCodeInstCallAxis { field. target [LalinCode.CodeCallTarget], sig [LalinCode.CodeSigId], },
    NativeCodeInstAtomicLoadAxis {
      field. access [LalinCode.CodeMemoryAccess],
      field. ordering [LalinCore.AtomicOrdering],
    },
    NativeCodeInstAtomicStoreAxis {
      field. access [LalinCode.CodeMemoryAccess],
      field. ordering [LalinCore.AtomicOrdering],
    },
    NativeCodeInstAtomicRmwAxis {
      field. op [LalinCore.AtomicRmwOp],
      field. access [LalinCode.CodeMemoryAccess],
      field. ordering [LalinCore.AtomicOrdering],
    },
    NativeCodeInstAtomicCasAxis {
      field. access [LalinCode.CodeMemoryAccess],
      field. ordering [LalinCore.AtomicOrdering],
    },
    NativeCodeInstAtomicFenceAxis { field. ordering [LalinCore.AtomicOrdering], },
  },

  sum. NativeCodeTermAxis {
    NativeCodeTermJumpAxis,
    NativeCodeTermBranchAxis,
    NativeCodeTermSwitchAxis,
    NativeCodeTermVariantSwitchAxis,
    NativeCodeTermReturnAxis { field. results [many [LalinCode.CodeType]], },
    NativeCodeTermTrapAxis,
    NativeCodeTermUnreachableAxis,
  },

  sum. NativeCodePlaceAxis {
    NativeCodePlaceLocalAxis { field. ty [LalinCode.CodeType], },
    NativeCodePlaceGlobalAxis { field. ty [LalinCode.CodeType], },
    NativeCodePlaceDataAxis { field. ty [LalinCode.CodeType], },
    NativeCodePlaceDerefAxis { field. ty [LalinCode.CodeType], align [number], },
    NativeCodePlaceFieldAxis { field. ty [LalinCode.CodeType], offset [number], align [number], },
    NativeCodePlaceIndexAxis { field. ty [LalinCode.CodeType], elem_size [number], },
    NativeCodePlaceBytesAxis { field. ty [LalinCode.CodeType], size [number], align [number], },
  },

  sum. NativeCodeConstAxis {
    NativeCodeConstLiteralAxis { field. ty [LalinCode.CodeType], },
    NativeCodeConstNullAxis { field. ty [LalinCode.CodeType], },
    NativeCodeConstUndefAxis { field. ty [LalinCode.CodeType], },
  },

  sum. NativeKernelAxis {
    NativeKernelDomainFlowAxis,
    NativeKernelExprValueAxis,
    NativeKernelExprAlgebraAxis,
    NativeKernelExprLaneLoadAxis { field. elem_ty [LalinCode.CodeType], },
    NativeKernelExprKernelValueAxis,
    NativeKernelEffectStoreAxis { field. elem_ty [LalinCode.CodeType], },
    NativeKernelEffectScanAxis {
      field. reduction [LalinValue.ReductionFact],
      field. mode [LalinStencil.StencilScanMode],
    },
    NativeKernelEffectPartitionAxis { field. semantics [LalinStencil.StencilPartitionSemantics], },
    NativeKernelEffectCopyAxis { field. semantics [LalinStencil.StencilCopySemantics], },
    NativeKernelEffectScatterReduceAxis { field. reducer [LalinStencil.StencilReducer], },
    NativeKernelEffectFoldAxis { field. reduction [LalinValue.ReductionFact], },
    NativeKernelEffectCallAxis { field. call [LalinEffect.CallSummary], },
    NativeKernelResultVoidAxis,
    NativeKernelResultValueAxis,
    NativeKernelResultFindAxis { field. pred [LalinStencil.StencilPredicate], },
    NativeKernelResultReductionAxis { field. reduction [LalinValue.ReductionFact], },
    NativeKernelResultClosedFormAxis { field. closed_form [LalinValue.ClosedFormFact], },
    NativeKernelResultOriginalControlAxis,
  },

  sum. NativeStencilProducerAxis {
    NativeStencilRange1DAxis {
      field. index_ty [LalinCode.CodeType],
      field. step [number],
      field. order [LalinStencil.StencilProducerOrder],
    },
    NativeStencilRangeNDAxis { field. rank [number], },
    NativeStencilWindowNDAxis { field. rank [number], windows [many [LalinStencil.StencilWindowAxis]], },
    NativeStencilTiledNDAxis { field. rank [number], tile_sizes [many [number]], },
  },

  sum. NativeStencilAccessAxis {
    NativeStencilLayoutScalarAxis { field. ty [LalinCode.CodeType], },
    NativeStencilLayoutContiguousAxis { field. ty [LalinCode.CodeType], },
    NativeStencilLayoutIndexedAxis { field. ty [LalinCode.CodeType], index_ty [LalinCode.CodeType], },
    NativeStencilLayoutAffine1DAxis { field. ty [LalinCode.CodeType], scale [number], },
    NativeStencilLayoutAffineNDAxis { field. ty [LalinCode.CodeType], rank [number], },
    NativeStencilLayoutFieldProjectionAxis { field. record_ty [LalinCode.CodeType], field_name [str], },
    NativeStencilLayoutSoAComponentAxis { field. record_ty [LalinCode.CodeType], field_name [str], },
    NativeStencilLayoutSliceDescriptorAxis { field. ty [LalinCode.CodeType], },
    NativeStencilLayoutByteSpanDescriptorAxis { field. ty [LalinCode.CodeType], },
    NativeStencilLayoutViewDescriptorAxis { field. ty [LalinCode.CodeType], },
  },

  sum. NativeStencilPointAxis {
    NativeStencilPointInputAxis,
    NativeStencilPointWindowInputAxis { field. offset_count [number], },
    NativeStencilPointConstAxis { field. ty [LalinCode.CodeType], },
    NativeStencilPointUnaryAxis {
      field. op [LalinStencil.StencilUnaryOp],
      field. result_ty [LalinCode.CodeType],
    },
    NativeStencilPointBinaryAxis {
      field. op [LalinStencil.StencilBinaryOp],
      field. result_ty [LalinCode.CodeType],
    },
    NativeStencilPointCastAxis {
      field. op [LalinCore.MachineCastOp],
      field. from [LalinCode.CodeType],
      field. to [LalinCode.CodeType],
    },
    NativeStencilPointPredicateAxis {
      field. pred [LalinStencil.StencilPredicate],
      field. result_ty [LalinCode.CodeType],
    },
    NativeStencilPointCompareAxis {
      field. cmp [LalinCore.CmpOp],
      field. result_ty [LalinCode.CodeType],
    },
    NativeStencilPointSelectAxis {
      field. pred [LalinStencil.StencilPredicate],
      field. result_ty [LalinCode.CodeType],
    },
  },

  sum. NativeStencilSinkAxis {
    NativeStencilSinkStoreAxis { field. semantics [LalinStencil.StencilStoreSemantics], },
    NativeStencilSinkReduceAxis {
      field. result_ty [LalinCode.CodeType],
      field. scope [LalinStencil.StencilReduceScope],
      field. semantics [LalinStencil.StencilReductionSemantics],
    },
    NativeStencilSinkScanAxis {
      field. reducer [LalinStencil.StencilReducer],
      field. mode [LalinStencil.StencilScanMode],
      field. result_ty [LalinCode.CodeType],
    },
    NativeStencilSinkScatterReduceAxis {
      field. reducer [LalinStencil.StencilReducer],
      field. conflicts [LalinStencil.StencilScatterReduceConflictSemantics],
      field. result_ty [LalinCode.CodeType],
    },
  },

  sum. NativeStencilScheduleAxis {
    NativeStencilScheduleScalarAxis { field. compiler [LalinStencil.StencilCompilerPolicy], },
    NativeStencilScheduleAutoVectorAxis { field. facts [LalinStencil.StencilVectorizationFacts], },
    NativeStencilScheduleUnrolledAxis {
      field. factor [number],
      field. facts [LalinStencil.StencilVectorizationFacts],
    },
    NativeStencilScheduleVectorAxis {
      field. feature [LalinStencil.StencilVectorFeatureRequirement],
      field. lane_policy [LalinStencil.StencilLanePolicy],
      field. required_alignment [LalinStencil.StencilVectorAlignmentPolicy],
      field. tail [LalinStencil.StencilVectorTailPolicy],
      field. reduction [LalinStencil.StencilVectorReductionStrategy],
      field. vector_unroll [number],
      field. interleave [number],
      field. facts [LalinStencil.StencilVectorizationFacts],
    },
  },

  product. NativeTemplateGraph {
    interned,
    field. target [LalinNative.NativeTarget],
    field. protocol [LalinNative.NativeCallProtocol],
    field. frame_layout [LalinNative.NativeFrameLayout],
    field. nodes [many [LalinNative.NativeTemplateNode]],
    field. control_edges [many [LalinNative.NativeControlEdge]],
    field. value_edges [many [LalinNative.NativeValueEdge]],
    field. entry [LalinNative.NativeTemplateNodeId],
    field. exits [many [LalinNative.NativeTemplateNodeId]],
  },

  product. NativeTemplateNode {
    interned,
    field. id [LalinNative.NativeTemplateNodeId],
    field. entry [LalinNative.NativeTemplateBankEntry],
    field. inputs [many [LalinNative.NativeValuePlacement]],
    field. outputs [many [LalinNative.NativeValuePlacement]],
    field. bindings [many [LalinNative.NativePatchBinding]],
  },

  sum. NativeControlEdge {
    NativeFallthroughEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
    },
    NativeConditionalBranchEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. then_to [LalinNative.NativeTemplateNodeId],
      field. else_to [LalinNative.NativeTemplateNodeId],
      field. condition [LalinNative.NativeTemplateValueId],
    },
    NativeLoopBackedgeEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
    },
    NativeExitEdge {
      field. from [LalinNative.NativeTemplateNodeId],
    },
    NativeContinuationEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. symbol [LalinNative.NativeContinuationSymbol],
    },
    NativeRuntimeCallReturnEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. symbol [LalinNative.NativeRuntimeSymbolId],
    },
  },

  sum. NativeValueEdge {
    NativeRegisterValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. scalar [LalinNative.NativeMachineScalarRep],
      field. register [LalinNative.NativeRegister],
    },
    NativeStackSlotValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. scalar [LalinNative.NativeMachineScalarRep],
      field. slot [LalinNative.NativeStackSlot],
    },
    NativeFrameSlotValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. scalar [LalinNative.NativeMachineScalarRep],
      field. slot [LalinNative.NativeFrameSlot],
    },
    NativeRuntimeParamValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. placement [LalinNative.NativeAbiParamPlacement],
    },
    NativePatchCoordinateValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. scalar [LalinNative.NativeMachineScalarRep],
      field. coordinate [LalinNative.NativePatchCoordinate],
    },
    NativeAccumulatorValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. scalar [LalinNative.NativeMachineScalarRep],
      field. role [LalinNative.NativeAccumulatorRole],
      field. register [LalinNative.NativeRegister],
    },
    NativeMemoryAddressValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. address_scalar [LalinNative.NativeMachineScalarRep],
      field. base [LalinNative.NativeTemplateValueId],
      field. offset [LalinNative.NativePatchCoordinate],
    },
  },

  product. NativeCodeLayoutNode {
    interned,
    field. node [LalinNative.NativeTemplateNodeId],
    field. offset [number],
  },

  product. NativeCodeLayout {
    interned,
    field. nodes [many [LalinNative.NativeCodeLayoutNode]],
    field. size [number],
    field. alignment [number],
  },

  product. NativeCopyPlan {
    interned,
    field. graph [LalinNative.NativeTemplateGraph],
    field. layout [LalinNative.NativeCodeLayout],
    field. frame_layout [LalinNative.NativeFrameLayout],
    field. bindings [many [LalinNative.NativePatchBinding]],
    field. protocol [LalinNative.NativeCallProtocol],
  },

  product. NativeCopyPlanSelectionInput {
    interned,
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
  },

  product. NativeHoleLayout {
    interned,
    field. id [LalinNative.NativePatchHoleId],
    field. symbol [str],
    field. offset [number],
    field. width [number],
    field. hole [LalinNative.NativePatchHole],
  },

  product. NativePatchBinding {
    interned,
    field. hole [LalinNative.NativePatchHoleId],
    field. coordinate [LalinNative.NativePatchCoordinate],
  },

  sum. NativePatchCoordinate {
    NativePatchImmediateI32 { field. value [number], },
    NativePatchImmediateI64 { field. value [number], },
    NativePatchPointer64 { field. address [number], },
    NativePatchFieldOffset { field. field_name [str], offset [number], },
    NativePatchComponentIndex { field. field_name [str], component_index [number], },
    NativePatchStride { field. stride [number], },
    NativePatchAffineCoeff { field. axis_index [number], coeff [LalinValue.ValueExpr], },
    NativePatchAffineOffset { field. offset [LalinValue.ValueExpr], },
    NativePatchWindowOffset { field. axis_index [number], offset [number], },
    NativePatchBranchTarget { field. node [LalinNative.NativeTemplateNodeId], },
    NativePatchCallTarget { field. symbol [LalinNative.NativeRuntimeSymbolId], },
    NativePatchFrameOffset { field. offset [number], },
    NativePatchFrameSize { field. size [number], },
    NativePatchScalarConst {
      field. value [LalinValue.ValueExpr],
      field. ty [LalinCode.CodeType],
    },
  },

  sum. NativePatchHole {
    NativePatchImm32,
    NativePatchImm64,
    NativePatchPtr64,
    NativePatchRel32,
    NativePatchBranchRel32,
    NativePatchCallRel32,
    NativePatchFieldOffset32,
    NativePatchComponentIndex32,
    NativePatchStride32,
    NativePatchFrameOffset32,
    NativePatchFrameSize32,
  },

  sum. NativeRegisterProtocol {
    NativeRegisterProtocolNone,
    NativeRegisterProtocolX64SysV,
    NativeRegisterProtocolX64Win64,
    NativeRegisterProtocolAArch64,
  },

  sum. NativeCallProtocol {
    NativeCallVoid,
    NativeCallReturnI32,
    NativeCallReturnI64,
    NativeCallReturnF64,
    NativeCallReturnScalar { variant_unique, field. scalar [LalinNative.NativeMachineScalarRep], },
    NativeCallCodeSig { field. sig [LalinCode.CodeSig], },
    NativeCallStencilAbi { field. abi [LalinStencil.StencilAbi], },
  },

  sum. NativeExecutableAllocator {
    NativeExecutableAllocatorMmap,
    NativeExecutableAllocatorVirtualAlloc,
  },

  product. NativeInstallInput {
    interned,
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
    field. allocator [LalinNative.NativeExecutableAllocator],
  },

  product. NativePatchApplyInput {
    interned,
    field. base_address [number],
    field. layout [LalinNative.NativeHoleLayout],
    field. binding [LalinNative.NativePatchBinding],
  },

  product. NativeExecutable {
    interned,
    field. id [LalinNative.NativeExecutableId],
    field. target [LalinNative.NativeTarget],
    field. base_address [number],
    field. entry_address [number],
    field. size [number],
    field. protocol [LalinNative.NativeCallProtocol],
  },

  sum. NativeInstallResult {
    NativeInstallSucceeded {
      field. executable [LalinNative.NativeExecutable],
    },
    NativeInstallRejected {
      field. rejects [many [LalinNative.NativeInstallReject]],
    },
  },

  sum. NativeInstallReject {
    NativeInstallRejectMissingBinding { field. hole [LalinNative.NativePatchHoleId], },
    NativeInstallRejectDuplicateBinding { field. hole [LalinNative.NativePatchHoleId], },
    NativeInstallRejectWrongCoordinate {
      field. hole [LalinNative.NativePatchHoleId],
      field. coordinate [LalinNative.NativePatchCoordinate],
    },
    NativeInstallRejectPatchOutOfRange {
      field. hole [LalinNative.NativePatchHoleId],
      field. offset [number],
      field. width [number],
      field. code_size [number],
    },
    NativeInstallRejectMissingContinuationTarget {
      field. node [LalinNative.NativeTemplateNodeId],
      field. symbol [LalinNative.NativeContinuationSymbol],
    },
    NativeInstallRejectUnsupportedRelocation {
      field. node [LalinNative.NativeTemplateNodeId],
      field. offset [number],
      field. reason [str],
    },
    NativeInstallRejectAllocation { field. reason [str], },
  },

  product. NativeExecutableCallInput {
    interned,
    field. executable [LalinNative.NativeExecutable],
    field. args [many [LalinNative.NativeCallArg]],
  },

  sum. NativeCallArg {
    NativeCallArgI32 { field. value [number], },
    NativeCallArgI64 { field. value [number], },
    NativeCallArgF64 { field. value [number], },
    NativeCallArgPtr { field. address [number], },
  },

  sum. NativeExecutableCallResult {
    NativeCallReturnedVoid,
    NativeCallReturnedI32 { field. value [number], },
    NativeCallReturnedI64 { field. value [number], },
    NativeCallReturnedF64 { field. value [number], },
  },
}
