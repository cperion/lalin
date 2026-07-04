local S = require("lalin.schema.dsl")
S.use()

return schema. LalinNative {
  product. NativeTargetId { interned, text [str], },
  product. NativeRuntimeSymbolId { interned, text [str], },
  product. NativeTemplateId { interned, text [str], },
  product. NativeTemplateFamilyId { interned, text [str], },
  product. NativeTemplateNodeId { interned, text [str], },
  product. NativeTemplateInstanceId { interned, text [str], },
  product. NativeTemplateValueId { interned, text [str], },
  product. NativePatchHoleId { interned, text [str], },
  product. NativeExecutableId { interned, text [str], },
  product. NativeBankId { interned, text [str], },
  product. NativeRegisterId { interned, text [str], },
  product. NativeTemplateSupportDomainId { interned, text [str], },
  product. NativeFrameSlotId { interned, text [str], },
  product. NativeContinuationSymbolId { interned, text [str], },
  product. NativeStencilGeneratorId { interned, text [str], },
  product. NativeStencilMetavarId { interned, text [str], },
  product. NativeStencilConfigurationId { interned, text [str], },
  product. NativeTemplateManifestId { interned, text [str], },
  product. NativeHoleOrdinalId { interned, text [str], },
  product. NativeConstantPoolEntryId { interned, text [str], },
  product. NativeObjectSectionId { interned, text [str], },
  product. NativeObjectSymbolId { interned, text [str], },
  product. NativeObjectRelocationId { interned, text [str], },

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

  product. NativeDescriptorRepresentationField {
    interned,
    field. field_name [str],
    field. offset [number],
    field. representation [LalinNative.NativeValueRepresentation],
  },

  product. NativeVariantRepresentationCase {
    interned,
    field. variant_name [str],
    field. tag_value [number],
    field. payload [LalinNative.NativeValueRepresentation],
  },

  sum. NativeCodeAddressTarget {
    NativeCodeRawDataAddressTarget {
      field. data [LalinCode.CodeDataId],
      field. size [number],
      field. alignment [number],
    },
    NativeCodeDataAddressTarget {
      field. data [LalinCode.CodeDataId],
      field. ty [LalinCode.CodeType],
    },
    NativeCodeGlobalAddressTarget {
      field. global [LalinCode.CodeGlobalId],
      field. ty [LalinCode.CodeType],
    },
    NativeCodeFuncAddressTarget {
      field. func [LalinCode.CodeFuncId],
      field. sig [LalinCode.CodeSigId],
    },
    NativeCodeExternAddressTarget {
      field. extern [LalinCode.CodeExternId],
    },
    NativeCodeLocalAddressTarget {
      field. local_id [LalinCode.CodeLocalId],
      field. ty [LalinCode.CodeType],
    },
    NativeCodePlaceAddressTarget {
      field. place [LalinCode.CodePlace],
    },
  },

  sum. NativeValueRepresentation {
    NativeScalarValueRepresentation { field. scalar [LalinNative.NativeMachineScalarRep], },
    NativeAddressValueRepresentation {
      field. address_scalar [LalinNative.NativeMachineScalarRep],
      field. target [LalinNative.NativeCodeAddressTarget],
    },
    NativeOpaquePointerValueRepresentation {
      field. address_scalar [LalinNative.NativeMachineScalarRep],
      field. pointee [LalinCode.CodeType],
    },
    NativeUntypedPointerValueRepresentation {
      field. address_scalar [LalinNative.NativeMachineScalarRep],
    },
    NativeDescriptorValueRepresentation {
      field. layout [LalinSem.TypeLayout],
      field. fields [many [LalinNative.NativeDescriptorRepresentationField]],
    },
    NativeObjectStorageRepresentation {
      field. source_ty [LalinCode.CodeType],
      field. size [number],
      field. alignment [number],
    },
    NativeAggregateStorageRepresentation {
      field. source_ty [LalinCode.CodeType],
      field. elements [many [LalinNative.NativeValueRepresentation]],
      field. element_count [number],
      field. size [number],
      field. alignment [number],
    },
    NativeVectorStorageRepresentation {
      field. source_ty [LalinCode.CodeType],
      field. element [LalinNative.NativeValueRepresentation],
      field. lanes [number],
      field. size [number],
      field. alignment [number],
    },
    NativeVariantStorageRepresentation {
      field. source_ty [LalinCode.CodeType],
      field. tag [LalinNative.NativeMachineScalarRep],
      field. cases [many [LalinNative.NativeVariantRepresentationCase]],
      field. size [number],
      field. alignment [number],
    },
  },

  product. NativeStorageLayout {
    interned,
    field. representation [LalinNative.NativeValueRepresentation],
    field. size [number],
    field. alignment [number],
  },

  sum. NativeCodeNamedLayoutKey {
    NativeCodeNamedLayoutByTypeId {
      field. type_id [LalinCode.CodeTypeId],
      field. ty [LalinCode.CodeType],
    },
    NativeCodeNamedLayoutByName {
      field. module_name [str],
      field. type_name [str],
      field. source_ty [LalinType.Type],
    },
  },

  sum. NativeCodeFieldLayoutRef {
    NativeCodeSemFieldLayoutRef { field. field [LalinSem.FieldRef], },
    NativeCodeCFieldLayoutRef { field. field [LalinC.CFieldLayout], },
    NativeCodeSyntheticFieldLayoutRef { field. field_name [str], },
  },

  product. NativeCodeFieldStorageLayout {
    interned,
    field. field_name [str],
    field. field_ref [LalinNative.NativeCodeFieldLayoutRef],
    field. offset [number],
    field. size [number],
    field. alignment [number],
    field. representation [LalinNative.NativeValueRepresentation],
  },

  product. NativeCodeNamedLayoutEntry {
    interned,
    field. key [LalinNative.NativeCodeNamedLayoutKey],
    field. ty [LalinCode.CodeType],
    field. sem_layout [LalinSem.TypeLayout],
    field. storage [LalinNative.NativeStorageLayout],
    field. fields [many [LalinNative.NativeCodeFieldStorageLayout]],
  },

  product. NativeCodeImportedCLayoutEntry {
    interned,
    field. c_type [LalinC.CTypeId],
    field. ty [LalinCode.CodeType],
    field. c_layout [LalinC.CLayoutFact],
    field. storage [LalinNative.NativeStorageLayout],
    field. fields [many [LalinNative.NativeCodeFieldStorageLayout]],
  },

  product. NativeCodeVariantCaseLayout {
    interned,
    field. variant [LalinCode.CodeVariantRef],
    field. tag_value [number],
    field. payload_offset [number],
    field. payload [optional [LalinNative.NativeStorageLayout]],
    field. total_size [number],
    field. total_alignment [number],
  },

  product. NativeCodeVariantLayoutEntry {
    interned,
    field. owner_ty [LalinCode.CodeType],
    field. tag_storage [LalinNative.NativeStorageLayout],
    field. tag_offset [number],
    field. cases [many [LalinNative.NativeCodeVariantCaseLayout]],
    field. storage [LalinNative.NativeStorageLayout],
  },

  product. NativeCodeTypeLayoutPlan {
    field. named [many [LalinNative.NativeCodeNamedLayoutEntry]],
    field. imported_c [many [LalinNative.NativeCodeImportedCLayoutEntry]],
    field. variants [many [LalinNative.NativeCodeVariantLayoutEntry]],
  },

  product. NativeFrameSlot {
    interned,
    field. id [LalinNative.NativeFrameSlotId],
    field. representation [LalinNative.NativeValueRepresentation],
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

  sum. NativeAbiByRefMutability {
    NativeAbiByRefReadonly,
    NativeAbiByRefMutable,
  },

  product. NativeAbiDescriptorField {
    interned,
    field. field_name [str],
    field. offset [number],
    field. value [LalinNative.NativeAbiProjection],
  },

  sum. NativeAbiProjection {
    NativeAbiVoidResult,
    NativeAbiScalarValue {
      field. scalar [LalinNative.NativeMachineScalarRep],
      field. extension [LalinNative.NativeExtensionPolicy],
    },
    NativeAbiPointerValue {
      field. scalar [LalinNative.NativeMachineScalarRep],
    },
    NativeAbiDescriptorValue {
      field. layout [LalinSem.TypeLayout],
      field. fields [many [LalinNative.NativeAbiDescriptorField]],
    },
    NativeAbiByRefValue {
      field. pointee_ty [LalinCode.CodeType],
      field. mutability [LalinNative.NativeAbiByRefMutability],
      field. alignment [number],
    },
    NativeAbiSRetResult {
      field. result_ty [LalinCode.CodeType],
      field. pointer_param [LalinNative.NativeAbiParamProjection],
    },
  },

  product. NativeAbiParamProjection {
    interned,
    field. param_index [number],
    field. source_ty [LalinCode.CodeType],
    field. abi [LalinNative.NativeAbiProjection],
  },

  product. NativeAbiResultProjection {
    interned,
    field. source_ty [optional [LalinCode.CodeType]],
    field. abi [LalinNative.NativeAbiProjection],
  },

  product. NativeAbiFunctionProjection {
    interned,
    field. target [LalinNative.NativeTarget],
    field. params [many [LalinNative.NativeAbiParamProjection]],
    field. result [LalinNative.NativeAbiResultProjection],
  },

  sum. NativeRuntimeAddressCapability {
    NativeRuntimeAddressSupplied { field. address [number], },
    NativeRuntimeAddressLinkerSymbol { field. symbol_name [str], },
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
    NativeValueContinuationArgLocation {
      field. arg_index [number],
      field. representation [LalinNative.NativeValueRepresentation],
    },
    NativeValueConstantPoolLocation {
      field. entry [LalinNative.NativeConstantPoolEntryId],
      field. representation [LalinNative.NativeValueRepresentation],
    },
    NativeValueRuntimeParamLocation {
      field. param_index [number],
      field. representation [LalinNative.NativeValueRepresentation],
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
      field. representation [LalinNative.NativeValueRepresentation],
    },
  },

  product. NativeValuePlacement {
    interned,
    field. value [LalinNative.NativeTemplateValueId],
    field. representation [LalinNative.NativeValueRepresentation],
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

  product. NativeFrameStackLimit {
    interned,
    field. max_bytes [number],
    field. alignment [number],
  },

  sum. NativeTemplateChunkClass {
    NativeChunkFrameEntry,
    NativeChunkPublicAbiAdapter,
    NativeChunkTerminalContinuation,
    NativeChunkEdgeCopy,
    NativeChunkParallelCopy,
    NativeChunkConstantLoad,
    NativeChunkUnaryOp,
    NativeChunkBinaryOp,
    NativeChunkCompareOp,
    NativeChunkCastOp,
    NativeChunkSelectOp,
    NativeChunkAddressMemoryOp,
    NativeChunkDescriptorOp,
    NativeChunkAggregateVariantOp,
    NativeChunkCallOp,
    NativeChunkControlOp,
    NativeChunkKernelOp,
    NativeChunkStencilOp,
    NativeChunkSupertemplate,
    NativeChunkStandaloneCallable,
  },

  sum. NativeStencilValueLocationClass {
    NativeStencilContinuationArgLocationClass,
    NativeStencilFrameSlotLocationClass,
    NativeStencilConstantPoolLocationClass,
    NativeStencilImmediateLocationClass,
    NativeStencilStackSlotLocationClass,
    NativeStencilRuntimeParamLocationClass,
  },

  sum. NativeStencilPassthroughClass {
    NativeStencilPassthroughIntLike,
    NativeStencilPassthroughFloatLike,
  },

  sum. NativeStencilControlShape {
    NativeStencilControlNext,
    NativeStencilControlThenElse,
    NativeStencilControlCaseDefault,
    NativeStencilControlCallReturn,
    NativeStencilControlTerminal,
  },

  sum. NativeConstantPoolEntryKind {
    NativeConstantPoolScalarConst { field. scalar [LalinNative.NativeMachineScalarRep], },
    NativeConstantPoolPointerConst,
    NativeConstantPoolBytes { field. size [number], alignment [number], },
  },

  product. NativeConstantPoolSupport {
    interned,
    field. max_entries [number],
    field. max_bytes [number],
    field. entry_kinds [many [LalinNative.NativeConstantPoolEntryKind]],
  },

  sum. NativeTemplateRelocationKind {
    NativeTemplateRelocationRel32,
    NativeTemplateRelocationAbs64,
    NativeTemplateRelocationRuntimeSymbol,
    NativeTemplateRelocationContinuation,
    NativeTemplateRelocationHoleOrdinal,
    NativeTemplateRelocationConstantPool,
  },

  sum. NativeAtomicCodegenCapability {
    NativeAtomicNoCodegen,
    NativeAtomicGccBuiltins,
  },

  sum. NativePatchFormula {
    NativePatchSym32,
    NativePatchSym64,
    NativePatchPcRel32,
  },

  product. NativeHoleOrdinal {
    interned,
    field. id [LalinNative.NativeHoleOrdinalId],
    field. ordinal [number],
    field. symbol [str],
    field. hole [LalinNative.NativePatchHole],
  },

  product. NativeContinuationOrdinal {
    interned,
    field. ordinal [number],
    field. symbol [LalinNative.NativeContinuationSymbol],
  },

  product. NativeExternHoleSymbol {
    interned,
    field. ordinal [LalinNative.NativeHoleOrdinal],
    field. c_symbol [str],
  },

  product. NativeStencilGenerator {
    interned,
    field. id [LalinNative.NativeStencilGeneratorId],
    field. owner_family [LalinNative.NativeTemplateFamily],
    field. chunk_class [LalinNative.NativeTemplateChunkClass],
    field. metavars [many [LalinNative.NativeStencilMetavar]],
  },

  sum. NativeStencilMetavar {
    NativeStencilScalarMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. values [many [LalinNative.NativeMachineScalarRep]],
    },
    NativeStencilLocationClassMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. values [many [LalinNative.NativeStencilValueLocationClass]],
    },
    NativeStencilPassthroughIntCountMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. counts [many [number]],
    },
    NativeStencilPassthroughFloatCountMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. counts [many [number]],
    },
    NativeStencilControlShapeMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. shapes [many [LalinNative.NativeStencilControlShape]],
    },
    NativeStencilCodeInstMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeCodeInstAxis]],
    },
    NativeStencilCodeTermMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeCodeTermAxis]],
    },
    NativeStencilKernelMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeKernelAxis]],
    },
    NativeStencilProducerMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeStencilProducerAxis]],
    },
    NativeStencilAccessMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeStencilAccessAxis]],
    },
    NativeStencilPointMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeStencilPointAxis]],
    },
    NativeStencilSinkMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeStencilSinkAxis]],
    },
    NativeStencilScheduleMetavar {
      field. id [LalinNative.NativeStencilMetavarId],
      field. axes [many [LalinNative.NativeStencilScheduleAxis]],
    },
  },

  sum. NativeStencilMetavarValue {
    NativeStencilScalarMetavarValue { field. scalar [LalinNative.NativeMachineScalarRep], },
    NativeStencilLocationClassMetavarValue { field. location [LalinNative.NativeStencilValueLocationClass], },
    NativeStencilPassthroughIntCountMetavarValue { field. count [number], },
    NativeStencilPassthroughFloatCountMetavarValue { field. count [number], },
    NativeStencilControlShapeMetavarValue { field. shape [LalinNative.NativeStencilControlShape], },
    NativeStencilCodeInstMetavarValue { field. axis [LalinNative.NativeCodeInstAxis], },
    NativeStencilCodeTermMetavarValue { field. axis [LalinNative.NativeCodeTermAxis], },
    NativeStencilKernelMetavarValue { field. axis [LalinNative.NativeKernelAxis], },
    NativeStencilProducerMetavarValue { field. axis [LalinNative.NativeStencilProducerAxis], },
    NativeStencilAccessMetavarValue { field. axis [LalinNative.NativeStencilAccessAxis], },
    NativeStencilPointMetavarValue { field. axis [LalinNative.NativeStencilPointAxis], },
    NativeStencilSinkMetavarValue { field. axis [LalinNative.NativeStencilSinkAxis], },
    NativeStencilScheduleMetavarValue { field. axis [LalinNative.NativeStencilScheduleAxis], },
  },

  product. NativeStencilMetavarBinding {
    interned,
    field. metavar [LalinNative.NativeStencilMetavarId],
    field. value [LalinNative.NativeStencilMetavarValue],
  },

  product. NativeStencilConfiguration {
    interned,
    field. id [LalinNative.NativeStencilConfigurationId],
    field. generator [LalinNative.NativeStencilGeneratorId],
    field. bindings [many [LalinNative.NativeStencilMetavarBinding]],
  },

  product. NativeStencilFrameParam {
    interned,
    field. scalar [LalinNative.NativeMachineScalarRep],
  },

  product. NativeStencilPassthrough {
    interned,
    field. index [number],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. class [LalinNative.NativeStencilPassthroughClass],
  },

  product. NativeStencilOperand {
    interned,
    field. index [number],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. location [LalinNative.NativeStencilValueLocationClass],
  },

  product. NativeStencilContinuationParam {
    interned,
    field. index [number],
    field. scalar [LalinNative.NativeMachineScalarRep],
    field. location [LalinNative.NativeStencilValueLocationClass],
  },

  product. NativeStencilContinuationSignature {
    interned,
    field. ordinal [LalinNative.NativeContinuationOrdinal],
    field. params [many [LalinNative.NativeStencilContinuationParam]],
  },

  product. NativeStencilSignature {
    interned,
    field. frame_param [LalinNative.NativeStencilFrameParam],
    field. passthroughs [many [LalinNative.NativeStencilPassthrough]],
    field. operands [many [LalinNative.NativeStencilOperand]],
    field. continuations [many [LalinNative.NativeStencilContinuationSignature]],
  },

  product. NativeTemplateManifestEntry {
    interned,
    field. source [LalinNative.NativeTemplateId],
    field. family [LalinNative.NativeTemplateFamily],
    field. generator [LalinNative.NativeStencilGenerator],
    field. configuration [LalinNative.NativeStencilConfiguration],
    field. signature [LalinNative.NativeStencilSignature],
    field. extraction [LalinNative.NativeTemplateExtraction],
    field. declared_hole_ordinals [many [LalinNative.NativeHoleOrdinal]],
    field. declared_continuation_ordinals [many [LalinNative.NativeContinuationOrdinal]],
    field. declared_relocation_kinds [many [LalinNative.NativeTemplateRelocationKind]],
  },

  product. NativeTemplateManifestGroup {
    interned,
    field. generator [LalinNative.NativeStencilGenerator],
    field. chunk_class [LalinNative.NativeTemplateChunkClass],
    field. entries [many [LalinNative.NativeTemplateManifestEntry]],
    field. total_count [number],
  },

  product. NativeTemplateSourceManifest {
    interned,
    field. id [LalinNative.NativeTemplateManifestId],
    field. support_domain [LalinNative.NativeTemplateSupportDomainId],
    field. groups [many [LalinNative.NativeTemplateManifestGroup]],
    field. total_count [number],
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
    field. passthrough_int_limit [number],
    field. passthrough_float_limit [number],
    field. frame_stack_limit [LalinNative.NativeFrameStackLimit],
    field. public_abi_adapters [many [LalinNative.NativeAbiFunctionProjection]],
    field. continuation_signatures [many [LalinNative.NativeStencilSignature]],
    field. constant_pool_support [LalinNative.NativeConstantPoolSupport],
    field. atomic_codegen [LalinNative.NativeAtomicCodegenCapability],
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

  product. NativeCodeAddressProjection {
    interned,
    field. target [LalinNative.NativeCodeAddressTarget],
    field. representation [LalinNative.NativeValueRepresentation],
    field. capability [LalinNative.NativeCodeAddressCapability],
  },

  sum. NativeCodeAddressCapability {
    NativeCodeAddressBankSymbol { field. symbol_name [str], },
    NativeCodeAddressRuntimeSymbol { field. symbol [LalinNative.NativeRuntimeSymbolId], },
    NativeCodeAddressPatchable { field. coordinate [LalinNative.NativePatchCoordinate], },
    NativeCodeAddressFrameSlot { field. slot [LalinNative.NativeFrameSlotId], },
    NativeCodeAddressFrameSlotOffset {
      field. slot [LalinNative.NativeFrameSlotId],
      field. offset [number],
    },
    NativeCodeAddressValueOffset {
      field. value [LalinCode.CodeValueId],
      field. offset [number],
    },
    NativeCodeAddressPlaceOffset {
      field. base [LalinCode.CodePlace],
      field. offset [number],
    },
    NativeCodeAddressPlaceIndexOffset {
      field. base [LalinCode.CodePlace],
      field. index [LalinCode.CodeValueId],
      field. elem_size [number],
      field. const_offset [number],
    },
    NativeCodeAddressConstantPoolEntry { field. entry [LalinNative.NativeConstantPoolEntryId], },
    NativeCodeAddressWritableDataRuntime { field. capability [LalinNative.NativeWritableDataRuntimeCapability], },
  },

  product. NativeModuleDataAddressEntry {
    interned,
    field. data [LalinCode.CodeDataId],
    field. projection [LalinNative.NativeCodeAddressProjection],
  },

  product. NativeModuleGlobalAddressEntry {
    interned,
    field. global [LalinCode.CodeGlobalId],
    field. projection [LalinNative.NativeCodeAddressProjection],
  },

  product. NativeModuleFuncAddressEntry {
    interned,
    field. func [LalinCode.CodeFuncId],
    field. projection [LalinNative.NativeCodeAddressProjection],
  },

  product. NativeModuleExternAddressEntry {
    interned,
    field. extern [LalinCode.CodeExternId],
    field. projection [LalinNative.NativeCodeAddressProjection],
  },

  product. NativeLocalAddressEntry {
    interned,
    field. local_id [LalinCode.CodeLocalId],
    field. projection [LalinNative.NativeCodeAddressProjection],
  },

  product. NativePlaceAddressEntry {
    interned,
    field. place [LalinCode.CodePlace],
    field. projection [LalinNative.NativeCodeAddressProjection],
  },

  product. NativeModuleAddressPlan {
    field. data [many [LalinNative.NativeModuleDataAddressEntry]],
    field. globals [many [LalinNative.NativeModuleGlobalAddressEntry]],
    field. funcs [many [LalinNative.NativeModuleFuncAddressEntry]],
    field. externs [many [LalinNative.NativeModuleExternAddressEntry]],
    field. locals [many [LalinNative.NativeLocalAddressEntry]],
    field. places [many [LalinNative.NativePlaceAddressEntry]],
  },

  sum. NativeCodeModulePlanOrigin {
    NativeCodeModulePlanFromCodeModule { field. module [LalinCode.CodeModuleId], },
    NativeCodeModulePlanForSingleFunction { field. func [LalinCode.CodeFuncId], },
  },

  product. NativeCodeSignaturePlanEntry {
    interned,
    field. sig [LalinCode.CodeSigId],
    field. signature [LalinCode.CodeSig],
    field. abi [LalinNative.NativeAbiFunctionProjection],
  },

  product. NativeCodeFunctionSignaturePlanEntry {
    interned,
    field. func [LalinCode.CodeFuncId],
    field. sig [LalinCode.CodeSigId],
  },

  sum. NativeCodeStaticMutability {
    NativeCodeStaticReadOnly,
    NativeCodeStaticWritable,
  },

  sum. NativeCodeStaticRelocationFormula {
    NativeCodeStaticRelocAbs64,
    NativeCodeStaticRelocRel32,
  },

  product. NativeCodeStaticRelocation {
    interned,
    field. reloc [LalinCode.CodeRelocId],
    field. offset [number],
    field. target [LalinCode.CodeGlobalRef],
    field. addend [number],
    field. formula [LalinNative.NativeCodeStaticRelocationFormula],
  },

  sum. NativeCodeStaticInit {
    NativeCodeStaticZeroInit { field. offset [number], field. size [number], },
    NativeCodeStaticBytesInit { field. offset [number], field. bytes [str], },
    NativeCodeStaticScalarInit {
      field. offset [number],
      field. ty [LalinCode.CodeType],
      field. literal [LalinCore.Literal],
      field. storage [LalinNative.NativeStorageLayout],
    },
    NativeCodeStaticRelocationInit { field. relocation [LalinNative.NativeCodeStaticRelocation], },
  },

  product. NativeWritableDataRuntimeCapability {
    interned,
    field. symbol_name [str],
    field. size [number],
    field. alignment [number],
  },

  sum. NativeCodeStaticStorageBacking {
    NativeCodeStaticConstantPoolBacking { field. entry [LalinNative.NativeConstantPoolEntry], },
    NativeCodeStaticWritableRuntimeBacking { field. capability [LalinNative.NativeWritableDataRuntimeCapability], },
  },

  product. NativeCodeDataStoragePlanEntry {
    interned,
    field. data [LalinCode.CodeDataId],
    field. name [str],
    field. linkage [LalinCode.CodeLinkage],
    field. size [number],
    field. alignment [number],
    field. mutability [LalinNative.NativeCodeStaticMutability],
    field. backing [LalinNative.NativeCodeStaticStorageBacking],
    field. inits [many [LalinNative.NativeCodeStaticInit]],
    field. relocations [many [LalinNative.NativeCodeStaticRelocation]],
    field. address [LalinNative.NativeCodeAddressProjection],
  },

  product. NativeCodeGlobalStoragePlanEntry {
    interned,
    field. global [LalinCode.CodeGlobalId],
    field. name [str],
    field. ty [LalinCode.CodeType],
    field. linkage [LalinCode.CodeLinkage],
    field. storage [LalinNative.NativeStorageLayout],
    field. size [number],
    field. alignment [number],
    field. mutability [LalinNative.NativeCodeStaticMutability],
    field. backing [LalinNative.NativeCodeStaticStorageBacking],
    field. inits [many [LalinNative.NativeCodeStaticInit]],
    field. relocations [many [LalinNative.NativeCodeStaticRelocation]],
    field. address [LalinNative.NativeCodeAddressProjection],
  },

  product. NativeCodeExternRuntimePlanEntry {
    interned,
    field. extern [LalinCode.CodeExternId],
    field. symbol_name [str],
    field. sig [LalinCode.CodeSigId],
    field. runtime_symbol [LalinNative.NativeRuntimeSymbolId],
    field. abi [LalinNative.NativeAbiFunctionProjection],
  },

  product. NativeCodeValueTypePlanEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    field. ty [LalinCode.CodeType],
    field. storage [LalinNative.NativeStorageLayout],
  },

  product. NativeCodeBlockParamPlanEntry {
    interned,
    field. block [LalinCode.CodeBlockId],
    field. params [many [LalinCode.CodeParam]],
  },

  product. NativeCodeLocalStoragePlanEntry {
    interned,
    field. local_id [LalinCode.CodeLocalId],
    field. name [str],
    field. ty [LalinCode.CodeType],
    field. residence [LalinCode.CodeResidence],
    field. storage [LalinNative.NativeStorageLayout],
  },

  product. NativeCodeFunctionPlan {
    interned,
    field. func [LalinCode.CodeFuncId],
    field. sig [LalinCode.CodeSigId],
    field. value_types [many [LalinNative.NativeCodeValueTypePlanEntry]],
    field. block_params [many [LalinNative.NativeCodeBlockParamPlanEntry]],
    field. local_storage [many [LalinNative.NativeCodeLocalStoragePlanEntry]],
  },

  product. NativeCodeModulePlan {
    interned,
    field. origin [LalinNative.NativeCodeModulePlanOrigin],
    field. type_layouts [LalinNative.NativeCodeTypeLayoutPlan],
    field. addresses [LalinNative.NativeModuleAddressPlan],
    field. signatures [many [LalinNative.NativeCodeSignaturePlanEntry]],
    field. function_signatures [many [LalinNative.NativeCodeFunctionSignaturePlanEntry]],
    field. data_storage [many [LalinNative.NativeCodeDataStoragePlanEntry]],
    field. global_storage [many [LalinNative.NativeCodeGlobalStoragePlanEntry]],
    field. extern_runtime [many [LalinNative.NativeCodeExternRuntimePlanEntry]],
    field. functions [many [LalinNative.NativeCodeFunctionPlan]],
  },

  product. NativeCodeLoweringInput {
    interned,
    field. module [LalinNative.NativeCodeModulePlan],
    field. active_func [LalinNative.NativeCodeFunctionPlan],
  },

  product. NativeCodeValuePlacementEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    field. representation [LalinNative.NativeValueRepresentation],
    field. placement [LalinNative.NativeValuePlacement],
  },

  product. NativeValueLocationPlan {
    field. entries [many [LalinNative.NativeCodeValuePlacementEntry]],
    field. addresses [LalinNative.NativeModuleAddressPlan],
  },

  product. NativeFrameValueSlotEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    field. representation [LalinNative.NativeValueRepresentation],
    field. slot [LalinNative.NativeFrameSlot],
  },

  product. NativeFrameBlockSlotEntry {
    interned,
    field. block [LalinCode.CodeBlockId],
    field. slots [many [LalinNative.NativeFrameSlot]],
  },

  product. NativeFrameLayoutPlan {
    field. value_slots [many [LalinNative.NativeFrameValueSlotEntry]],
    field. block_slots [many [LalinNative.NativeFrameBlockSlotEntry]],
    field. slots [many [LalinNative.NativeFrameSlot]],
    field. next_frame_offset [number],
  },

  product. NativeControlBlockEntry {
    interned,
    field. block [LalinCode.CodeBlockId],
    field. entry_node [LalinNative.NativeTemplateNodeId],
    field. exit_nodes [many [LalinNative.NativeTemplateNodeId]],
  },

  product. NativeControlPlan {
    field. nodes [many [LalinNative.NativeTemplateNode]],
    field. edges [many [LalinNative.NativeControlEdge]],
    field. blocks [many [LalinNative.NativeControlBlockEntry]],
    field. exits [many [LalinNative.NativeTemplateNodeId]],
  },

  product. NativeEdgeCopyValue {
    interned,
    field. source_value [LalinCode.CodeValueId],
    field. dest_value [LalinCode.CodeValueId],
    field. placement [LalinNative.NativeValuePlacement],
  },

  product. NativeEdgeCopyEntry {
    interned,
    field. from_block [LalinCode.CodeBlockId],
    field. to_block [LalinCode.CodeBlockId],
    field. values [many [LalinNative.NativeEdgeCopyValue]],
  },

  product. NativeEdgeCopyPlan {
    field. entries [many [LalinNative.NativeEdgeCopyEntry]],
  },

  product. NativeCodeGraphBuilderState {
    field. value_locations [LalinNative.NativeValueLocationPlan],
    field. frame_layout_plan [LalinNative.NativeFrameLayoutPlan],
    field. control_plan [LalinNative.NativeControlPlan],
    field. edge_copy_plan [LalinNative.NativeEdgeCopyPlan],
    field. value_edges [many [LalinNative.NativeValueEdge]],
  },

  product. NativeCodeGraphBuildInput {
    field. plan [LalinNative.NativePlanInput],
    field. lowering [LalinNative.NativeCodeLoweringInput],
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
    field. abi [LalinNative.NativeAbiFunctionProjection],
    field. address [optional [LalinNative.NativeRuntimeAddressCapability]],
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
    NativeExtractPublicAbiAdapter {
      field. abi_projection [LalinNative.NativeAbiFunctionProjection],
      field. frame_size_hole [LalinNative.NativeHoleOrdinal],
      field. frame_alignment [number],
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
    field. generator [LalinNative.NativeStencilGenerator],
    field. configuration [LalinNative.NativeStencilConfiguration],
    field. signature [LalinNative.NativeStencilSignature],
    field. extraction [LalinNative.NativeTemplateExtraction],
    field. entry_symbol [str],
    field. c_text [str],
    field. declared_holes [many [LalinNative.NativeHoleLayout]],
    field. declared_hole_ordinals [many [LalinNative.NativeHoleOrdinal]],
    field. declared_continuation_ordinals [many [LalinNative.NativeContinuationOrdinal]],
    field. declared_relocation_kinds [many [LalinNative.NativeTemplateRelocationKind]],
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

  sum. NativeObjectFileFormat {
    NativeObjectFormatElf64X64,
  },

  sum. NativeObjectSectionFlag {
    NativeObjectSectionAlloc,
    NativeObjectSectionExecutable,
    NativeObjectSectionWritable,
    NativeObjectSectionRelocations,
  },

  sum. NativeObjectSymbolBinding {
    NativeObjectSymbolLocal,
    NativeObjectSymbolGlobal,
    NativeObjectSymbolWeak,
    NativeObjectSymbolExtern,
  },

  sum. NativeObjectSymbolKind {
    NativeObjectSymbolNoType,
    NativeObjectSymbolFunction,
    NativeObjectSymbolObject,
    NativeObjectSymbolSection,
    NativeObjectSymbolFile,
  },

  sum. NativeObjectRelocationKind {
    NativeObjectRelocX64Pc32,
    NativeObjectRelocX64Plt32,
    NativeObjectRelocX64Abs64,
    NativeObjectRelocX64Abs32,
    NativeObjectRelocX64Abs32S,
  },

  product. NativeObjectSection {
    interned,
    field. id [LalinNative.NativeObjectSectionId],
    field. name [str],
    field. bytes [LalinNative.NativeTemplateBytes],
    field. file_offset [number],
    field. size [number],
    field. alignment [number],
    field. flags [many [LalinNative.NativeObjectSectionFlag]],
  },

  product. NativeObjectSymbol {
    interned,
    field. id [LalinNative.NativeObjectSymbolId],
    field. name [str],
    field. binding [LalinNative.NativeObjectSymbolBinding],
    field. kind [LalinNative.NativeObjectSymbolKind],
    field. section [optional [LalinNative.NativeObjectSectionId]],
    field. value [number],
    field. size [number],
  },

  product. NativeObjectRelocation {
    interned,
    field. id [LalinNative.NativeObjectRelocationId],
    field. section [LalinNative.NativeObjectSectionId],
    field. offset [number],
    field. kind [LalinNative.NativeObjectRelocationKind],
    field. symbol [LalinNative.NativeObjectSymbolId],
    field. addend [number],
  },

  product. NativeObjectFile {
    interned,
    field. format [LalinNative.NativeObjectFileFormat],
    field. target [LalinNative.NativeTarget],
    field. bytes [LalinNative.NativeTemplateBytes],
    field. sections [many [LalinNative.NativeObjectSection]],
    field. symbols [many [LalinNative.NativeObjectSymbol]],
    field. relocations [many [LalinNative.NativeObjectRelocation]],
  },

  product. NativeTextSection {
    interned,
    field. bytes [LalinNative.NativeTemplateBytes],
    field. alignment [number],
  },

  product. NativeConstantPoolEntry {
    interned,
    field. id [LalinNative.NativeConstantPoolEntryId],
    field. bytes [LalinNative.NativeTemplateBytes],
    field. alignment [number],
    field. kind [LalinNative.NativeConstantPoolEntryKind],
  },

  product. NativeConstantPoolLayoutEntry {
    interned,
    field. entry [LalinNative.NativeConstantPoolEntry],
    field. offset [number],
  },

  product. NativeConstantPoolLayout {
    interned,
    field. entries [many [LalinNative.NativeConstantPoolLayoutEntry]],
    field. size [number],
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
    NativeRelocationHoleOrdinal {
      field. offset [number],
      field. ordinal [LalinNative.NativeHoleOrdinal],
      field. formula [LalinNative.NativePatchFormula],
      field. addend [number],
    },
    NativeRelocationConstantPool {
      field. offset [number],
      field. entry [LalinNative.NativeConstantPoolEntryId],
      field. formula [LalinNative.NativePatchFormula],
      field. addend [number],
    },
  },

  product. NativeCompiledTemplate {
    interned,
    field. id [LalinNative.NativeTemplateId],
    field. family [LalinNative.NativeTemplateFamily],
    field. target [LalinNative.NativeTarget],
    field. extraction [LalinNative.NativeTemplateExtraction],
    field. signature [LalinNative.NativeStencilSignature],
    field. text [LalinNative.NativeTextSection],
    field. symbols [many [LalinNative.NativeSymbol]],
    field. relocations [many [LalinNative.NativeRelocation]],
    field. holes [many [LalinNative.NativeHoleLayout]],
    field. hole_ordinals [many [LalinNative.NativeHoleOrdinal]],
    field. relocation_declarations [many [LalinNative.NativeTemplateRelocationKind]],
    field. constant_pool_layout [LalinNative.NativeConstantPoolLayout],
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
    NativeBuildRejectMalformedObject {
      field. source [LalinNative.NativeTemplateId],
      field. reason [str],
    },
    NativeBuildRejectMissingHoleOrdinal {
      field. source [LalinNative.NativeTemplateId],
      field. ordinal [number],
      field. symbol [str],
    },
    NativeBuildRejectDuplicateHoleOrdinal {
      field. source [LalinNative.NativeTemplateId],
      field. ordinal [number],
      field. symbol [str],
    },
    NativeBuildRejectMissingContinuationRelocation {
      field. source [LalinNative.NativeTemplateId],
      field. symbol [LalinNative.NativeContinuationSymbol],
    },
    NativeBuildRejectExtraUnresolvedSymbol {
      field. source [LalinNative.NativeTemplateId],
      field. symbol [str],
      field. reason [str],
    },
    NativeBuildRejectUnsupportedObjectFormat {
      field. source [LalinNative.NativeTemplateId],
      field. format [str],
      field. reason [str],
    },
    NativeBuildRejectUnsupportedConstantPoolRelocation {
      field. source [LalinNative.NativeTemplateId],
      field. offset [number],
      field. relocation_name [str],
      field. reason [str],
    },
  },

  product. NativeTemplateBankRequest {
    interned,
    field. id [LalinNative.NativeBankId],
    field. target [LalinNative.NativeTarget],
    field. runtime [LalinNative.NativeRuntime],
    field. manifest [LalinNative.NativeTemplateSourceManifest],
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
    field. manifest [LalinNative.NativeTemplateSourceManifest],
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
    field. extraction [LalinNative.NativeTemplateExtraction],
    field. signature [LalinNative.NativeStencilSignature],
    field. text [LalinNative.NativeTextSection],
    field. symbols [many [LalinNative.NativeSymbol]],
    field. relocations [many [LalinNative.NativeRelocation]],
    field. holes [many [LalinNative.NativeHoleLayout]],
    field. hole_ordinals [many [LalinNative.NativeHoleOrdinal]],
    field. relocation_declarations [many [LalinNative.NativeTemplateRelocationKind]],
    field. constant_pool_layout [LalinNative.NativeConstantPoolLayout],
  },

  product. NativeEmbeddedTemplateBank {
    interned,
    field. id [LalinNative.NativeBankId],
    field. target [LalinNative.NativeTarget],
    field. manifest [LalinNative.NativeTemplateSourceManifest],
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

  sum. NativeCodeAggregateStorageKind {
    NativeCodeAggregateObjectStorage,
    NativeCodeArrayElementStorage,
  },

  sum. NativeCodeAddressMaterializationKind {
    NativeCodeAddressMaterializeModuleSymbol,
    NativeCodeAddressMaterializeFrameSlot,
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
    NativeCodeInstPointerOffsetAxis {
      field. pointer [LalinNative.NativeMachineScalarRep],
      field. index [LalinNative.NativeMachineScalarRep],
    },
    NativeCodeInstLoadAxis { field. access [LalinCode.CodeMemoryAccess], },
    NativeCodeInstStoreAxis { field. access [LalinCode.CodeMemoryAccess], },
    NativeCodeInstLayoutFieldStoreAxis {
      field. storage [LalinNative.NativeCodeAggregateStorageKind],
      field. scalar [LalinNative.NativeMachineScalarRep],
    },
    NativeCodeInstLayoutFieldLoadAxis {
      field. storage [LalinNative.NativeCodeAggregateStorageKind],
      field. scalar [LalinNative.NativeMachineScalarRep],
    },
    NativeCodeInstAddressMaterializeAxis {
      field. kind [LalinNative.NativeCodeAddressMaterializationKind],
      field. pointer [LalinNative.NativeMachineScalarRep],
    },
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
    NativeCodeInstVariantScalarCtorAxis {
      field. tag [LalinNative.NativeMachineScalarRep],
      field. payload [LalinNative.NativeMachineScalarRep],
    },
    NativeCodeInstVariantScalarTagAxis { field. tag [LalinNative.NativeMachineScalarRep], },
    NativeCodeInstVariantScalarPayloadAxis { field. payload [LalinNative.NativeMachineScalarRep], },
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
    field. addresses [LalinNative.NativeModuleAddressPlan],
    field. entry [LalinNative.NativeTemplateNodeId],
    field. exits [many [LalinNative.NativeTemplateNodeId]],
  },

  product. NativeTemplateNode {
    interned,
    field. id [LalinNative.NativeTemplateNodeId],
    field. instance [LalinNative.NativeTemplateInstanceId],
    field. entry [LalinNative.NativeTemplateBankEntry],
    field. inputs [many [LalinNative.NativeValuePlacement]],
    field. outputs [many [LalinNative.NativeValuePlacement]],
    field. bindings [many [LalinNative.NativePatchBinding]],
  },

  sum. NativeControlEdge {
    NativeFallthroughEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. symbol [LalinNative.NativeContinuationSymbol],
    },
    NativeConditionalBranchEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. then_to [LalinNative.NativeTemplateNodeId],
      field. then_symbol [LalinNative.NativeContinuationSymbol],
      field. else_to [LalinNative.NativeTemplateNodeId],
      field. else_symbol [LalinNative.NativeContinuationSymbol],
      field. condition [LalinNative.NativeTemplateValueId],
    },
    NativeLoopBackedgeEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. symbol [LalinNative.NativeContinuationSymbol],
    },
    NativeExitEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. symbol [LalinNative.NativeContinuationSymbol],
    },
    NativeContinuationEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. symbol [LalinNative.NativeContinuationSymbol],
    },
    NativeRuntimeCallReturnEdge {
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. runtime_symbol [LalinNative.NativeRuntimeSymbolId],
      field. return_symbol [LalinNative.NativeContinuationSymbol],
    },
  },

  sum. NativeValueEdge {
    NativeRegisterValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. representation [LalinNative.NativeValueRepresentation],
      field. register [LalinNative.NativeRegister],
    },
    NativeStackSlotValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. representation [LalinNative.NativeValueRepresentation],
      field. slot [LalinNative.NativeStackSlot],
    },
    NativeFrameSlotValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. from [LalinNative.NativeTemplateNodeId],
      field. to [LalinNative.NativeTemplateNodeId],
      field. representation [LalinNative.NativeValueRepresentation],
      field. slot [LalinNative.NativeFrameSlot],
    },
    NativeRuntimeParamValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. placement [LalinNative.NativeAbiParamPlacement],
    },
    NativePatchCoordinateValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. representation [LalinNative.NativeValueRepresentation],
      field. coordinate [LalinNative.NativePatchCoordinate],
    },
    NativeAccumulatorValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. representation [LalinNative.NativeValueRepresentation],
      field. role [LalinNative.NativeAccumulatorRole],
      field. register [LalinNative.NativeRegister],
    },
    NativeMemoryAddressValueEdge {
      field. value [LalinNative.NativeTemplateValueId],
      field. representation [LalinNative.NativeValueRepresentation],
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
    field. constant_pool_layout [LalinNative.NativeConstantPoolLayout],
    field. addresses [LalinNative.NativeModuleAddressPlan],
    field. total_size [number],
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

  sum. NativePatchBindingTarget {
    NativePatchBindingHoleId { field. hole [LalinNative.NativePatchHoleId], },
    NativePatchBindingHoleOrdinal { field. ordinal [LalinNative.NativeHoleOrdinalId], },
  },

  product. NativePatchBinding {
    interned,
    field. node [LalinNative.NativeTemplateNodeId],
    field. instance [LalinNative.NativeTemplateInstanceId],
    field. target [LalinNative.NativePatchBindingTarget],
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
    NativePatchCodeDataAddress { field. data [LalinCode.CodeDataId], },
    NativePatchCodeGlobalAddress { field. global [LalinCode.CodeGlobalId], },
    NativePatchCodeFuncAddress { field. func [LalinCode.CodeFuncId], },
    NativePatchCodeExternAddress { field. extern [LalinCode.CodeExternId], },
    NativePatchFrameOffset { field. offset [number], },
    NativePatchFrameSize { field. size [number], },
    NativePatchScalarConst {
      field. value [LalinValue.ValueExpr],
      field. ty [LalinCode.CodeType],
    },
    NativePatchConstantPoolEntry {
      field. entry [LalinNative.NativeConstantPoolEntryId],
      field. bytes [LalinNative.NativeTemplateBytes],
      field. ty [optional [LalinCode.CodeType]],
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
    -- Legacy scalar smoke protocols are test/host-boundary conveniences only;
    -- graph ABI inference must use NativeAbiFunctionProjection below.
    NativeCallReturnScalar { variant_unique, field. scalar [LalinNative.NativeMachineScalarRep], },
    NativeCallCodeSig { field. projection [LalinNative.NativeAbiFunctionProjection], },
    NativeCallStencilAbi { field. projection [LalinNative.NativeAbiFunctionProjection], },
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
    field. runtime [LalinNative.NativeRuntime],
    field. constant_pool_layout [LalinNative.NativeConstantPoolLayout],
    field. graph [LalinNative.NativeTemplateGraph],
    field. code_layout [LalinNative.NativeCodeLayout],
    field. module_addresses [LalinNative.NativeModuleAddressPlan],
    field. node_address [optional [number]],
    field. branch_target_address [optional [number]],
    field. addend [number],
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
