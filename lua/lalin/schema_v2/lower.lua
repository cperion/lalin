local S = require("lalin.schema.dsl")
S.use()

return schema. LalinLower {
  product. LowerFragmentId { interned, text [str], },
  sum. LowerTarget { LowerTargetBack, LowerTargetC, },
  sum. LowerCover {
    LowerCoverFunction { variant_unique, func [LalinCode.CodeFuncId], },
    LowerCoverLoop { variant_unique, loop [LalinGraph.GraphLoopId], },
    LowerCoverBlock {
      variant_unique,
      func [LalinCode.CodeFuncId],
      block [LalinCode.CodeBlockId],
    },
    LowerCoverBlockRange {
      variant_unique,
      func [LalinCode.CodeFuncId],
      entry [LalinCode.CodeBlockId],
      exit [LalinCode.CodeBlockId],
    },
  },
  sum. LowerStrategy {
    LowerStrategyCode { variant_unique, reason [str], },
    LowerStrategyKernel {
      variant_unique,
      kernel [LalinKernel.KernelId],
      schedule [LalinSchedule.ScheduleId],
    },
    LowerStrategyClosedForm {
      variant_unique,
      kernel [LalinKernel.KernelId],
      fact [LalinValue.ClosedFormFact],
    },
  },
  sum. LowerProof {
    LowerProofCoverage { variant_unique, reason [str], },
    LowerProofKernel { variant_unique, kernel [LalinKernel.KernelId], reason [str], },
    LowerProofSchedule { variant_unique, schedule [LalinSchedule.ScheduleId], reason [str], },
    LowerProofFallback { variant_unique, reason [str], },
  },
  sum. LowerFallbackKind {
    LowerFallbackNoKernel { reason_description [str] },
    LowerFallbackUnschedulable { reason_description [str] },
    LowerFallbackComplexControlFlow { blocks [many [LalinCode.CodeBlockId]] },
    LowerFallbackExternalCall { call_site [str] },
  },
  sum. LowerIssue {
    LowerIssueOverlap { variant_unique, a [LalinLower.LowerFragmentId], b [LalinLower.LowerFragmentId], },
    LowerIssueGap { variant_unique, func [LalinCode.CodeFuncId], uncovered_blocks [many [LalinCode.CodeBlockId]], },
    LowerIssueFallback { variant_unique, cover [LalinLower.LowerCover], fallback_kind [LalinLower.LowerFallbackKind], },
    LowerIssueKernelRejected { variant_unique, cover [LalinLower.LowerCover], rejects [many [LalinKernel.KernelReject]], },
    LowerIssueScheduleRejected { variant_unique, cover [LalinLower.LowerCover], rejects [many [LalinSchedule.ScheduleReject]], },
    LowerIssueFragmentRejected { variant_unique, fragment [LalinLower.LowerFragmentId], reason [str], },
    LowerIssueCMatRejected {
      variant_unique,
      fragment [LalinLower.LowerFragmentId],
      issue [LalinCMat.CMatCEmissionIssue],
    },
    LowerIssueCoverageRejected {
      variant_unique,
      cover [LalinLower.LowerCover],
      reason [str],
    },
    LowerIssueAssemblyCollision {
      variant_unique,
      fragment [LalinLower.LowerFragmentId],
      field. name [str],
    },
    LowerIssueExternalPredecessor {
      variant_unique,
      fragment [LalinLower.LowerFragmentId],
      block [LalinCode.CodeBlockId],
    },
    LowerIssueValueUnavailable {
      variant_unique,
      field. value [LalinCode.CodeValueId],
      reason [str],
    },
    LowerIssueValueEnvironmentRejected {
      variant_unique,
      func [LalinCode.CodeFuncId],
      reason [str],
    },
    LowerIssueAccessRejected {
      variant_unique,
      access [LalinStencil.StencilAccessRef],
      reason [str],
    },
    LowerIssueExitRejected {
      variant_unique,
      role [LalinCMat.CMatCExitRole],
      destination [LalinCode.CodeBlockId],
      reason [str],
    },
    LowerIssueExitShapeRejected { variant_unique, reason [str], },
    LowerIssuePreparationModuleMismatch {
      variant_unique,
      expected [LalinCode.CodeModuleId],
      actual [LalinCode.CodeModuleId],
    },
    LowerIssuePreparationFacetRejected { variant_unique, reason [str], },
    LowerIssueDominanceRejected {
      variant_unique,
      func [LalinCode.CodeFuncId],
      reason [str],
    },
    LowerIssueEntryAdapterRejected {
      variant_unique,
      func [LalinCode.CodeFuncId],
      block [LalinCode.CodeBlockId],
      reason [str],
    },
    LowerIssueCMatCoordinateRejected {
      variant_unique,
      fragment [LalinLower.LowerFragmentId],
      issue [LalinLower.LowerCMatCoordinateIssue],
    },
    LowerIssueCMatAddressPlanRejected {
      variant_unique,
      fragment [LalinLower.LowerFragmentId],
      issue [LalinCMat.CMatCAddressIssue],
    },
    LowerIssueClosedFormUnsupported {
      variant_unique,
      fragment [LalinLower.LowerFragmentId],
    },
  },
  product. LowerScheduleByKernelEntry {
    interned,
    kernel [LalinKernel.KernelId],
    schedule [LalinSchedule.KernelSchedule],
  },
  sum. LowerScheduleRelationContribution {
    LowerScheduleRelationEntry { variant_unique, entry [LalinLower.LowerScheduleByKernelEntry], },
    LowerScheduleRelationOutsideKernel,
  },
  product. LowerScheduleByKernelProjection { entries [many [LalinLower.LowerScheduleByKernelEntry]], },
  sum. LowerScheduleByKernelLookup {
    LowerScheduleByKernelFound { variant_unique, entry [LalinLower.LowerScheduleByKernelEntry], },
    LowerScheduleByKernelMissing { variant_unique, kernel [LalinKernel.KernelId], },
  },
  product. LowerLoopByIdEntry {
    interned,
    field. id [LalinGraph.GraphLoopId],
    loop [LalinGraph.GraphLoop],
  },
  product. LowerLoopByIdProjection { entries [many [LalinLower.LowerLoopByIdEntry]], },
  sum. LowerLoopByIdLookup {
    LowerLoopByIdFound { variant_unique, entry [LalinLower.LowerLoopByIdEntry], },
    LowerLoopByIdMissing { variant_unique, field. id [LalinGraph.GraphLoopId], },
  },
  product. LowerOrderedLoop { interned, loop [LalinGraph.GraphLoop], ordinal [number], },
  sum. LowerCodeFuncGraphLookup {
    LowerCodeFuncGraphFound { variant_unique, graph [LalinGraph.CodeFuncGraph], },
    LowerCodeFuncGraphMissing { variant_unique, func [LalinCode.CodeFuncId], },
  },
  sum. LowerKernelRelationContribution {
    LowerKernelRelationEntry { variant_unique, entry [LalinLower.LowerKernelByLoopEntry], },
    LowerKernelRelationOutsideLoop,
  },
  product. LowerKernelByLoopEntry {
    interned,
    loop [LalinGraph.GraphLoopId],
    plan [LalinKernel.KernelPlan],
  },
  product. LowerKernelByLoopProjection { entries [many [LalinLower.LowerKernelByLoopEntry]], },
  sum. LowerKernelByLoopLookup {
    LowerKernelByLoopFound { variant_unique, entry [LalinLower.LowerKernelByLoopEntry], },
    LowerKernelByLoopMissing { variant_unique, loop [LalinGraph.GraphLoopId], },
  },
  sum. LowerFragmentCandidate {
    LowerFragmentClosedFormCandidate { variant_unique, closed_form [LalinValue.ClosedFormFact], kernel [LalinKernel.KernelPlanned], schedule [LalinSchedule.SchedulePlanned], },
    LowerFragmentClosedFormMissing { variant_unique, reason [str], },
    LowerFragmentKernelCandidate {
      variant_unique,
      kernel [LalinKernel.KernelPlanned],
      schedule [LalinSchedule.SchedulePlanned],
    },
    LowerFragmentNoSchedule { variant_unique, rejects [many [LalinSchedule.ScheduleReject]], },
    LowerFragmentMissingSchedule { variant_unique, kernel [LalinKernel.KernelId], },
    LowerFragmentKernelRejected { variant_unique, rejects [many [LalinKernel.KernelReject]], },
    LowerFragmentNoCandidate { variant_unique, loop [LalinGraph.GraphLoopId], },
  },
  sum. LowerClosedFormLookup {
    LowerClosedFormFound { variant_unique, fact [LalinValue.ClosedFormFact], },
    LowerClosedFormMissing { variant_unique, reason [str], },
  },
  sum. LowerFragmentSelection {
    LowerSelectClosedForm { variant_unique, closed_form [LalinValue.ClosedFormFact], kernel [LalinKernel.KernelId], schedule [LalinSchedule.ScheduleId], },
    LowerSelectKernel { variant_unique, kernel [LalinKernel.KernelId], schedule [LalinSchedule.ScheduleId], },
    LowerSelectFallback { variant_unique, reason [str], },
    LowerSelectKernelRejected { variant_unique, rejects [many [LalinKernel.KernelReject]], },
    LowerSelectScheduleRejected { variant_unique, rejects [many [LalinSchedule.ScheduleReject]], },
    LowerSelectNone { variant_unique, reason [str], },
  },
  product. LowerLoopFragmentInput {
    interned,
    func [LalinCode.CodeFuncId],
    loop [LalinGraph.GraphLoop],
    cover [LalinLower.LowerCover],
  },
  product. LowerLoopFragmentResult {
    interned,
    fragment [LalinLower.LowerFragment],
    covered_blocks [many [LalinCode.CodeBlockId]],
    issues [many [LalinLower.LowerIssue]],
  },
  product. LowerFuncPlanState {
    fragments [many [LalinLower.LowerFragment]],
    covered_blocks [many [LalinCode.CodeBlockId]],
    issues [many [LalinLower.LowerIssue]],
  },
  product. LowerFunctionPlanResult {
    plan [LalinLower.LowerFuncPlan],
    issues [many [LalinLower.LowerIssue]],
  },
  sum. LowerCMatInductionAlignmentAxis {
    LowerCMatAlignmentRole,
    LowerCMatAlignmentCounter,
    LowerCMatAlignmentType,
    LowerCMatAlignmentInit,
    LowerCMatAlignmentStep,
  },
  sum. LowerCMatCoordinateIssue {
    LowerCMatCoordinateAccessMissing {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      access [LalinStencil.StencilAccessRef],
    },
    LowerCMatCoordinateAccessAmbiguous {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      access [LalinStencil.StencilAccessRef],
      count [number],
    },
    LowerCMatCoordinateLaneMemoryMissing {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      field. lane [LalinKernel.KernelLaneId],
    },
    LowerCMatCoordinateLaneMemoryAmbiguous {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      field. lane [LalinKernel.KernelLaneId],
      count [number],
    },
    LowerCMatCoordinateMemoryFactMissing {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      access [LalinMem.MemAccessId],
    },
    LowerCMatCoordinateMemoryFactAmbiguous {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      access [LalinMem.MemAccessId],
      count [number],
    },
    LowerCMatCoordinateRootDisagreement {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      lane_root [LalinMem.MemBase],
      memory_root [LalinMem.MemBase],
    },
    LowerCMatCoordinateIndexMissing {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
    },
    LowerCMatCoordinateInductionMissing {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      index [LalinMem.MemIndex],
    },
    LowerCMatCoordinateInductionDisagreement {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      induction [LalinFlow.FlowInduction],
      iteration [LalinStencil.StencilKernelIteration],
      axis [LalinLower.LowerCMatInductionAlignmentAxis],
    },
    LowerCMatCoordinateInvalidScale {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      bytes [number],
    },
    LowerCMatCoordinateWindowAxisDisagreement {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      offset [LalinStencil.StencilWindowOffset],
    },
    LowerCMatCoordinateWindowDomainMissing {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      domain [LalinStencil.StencilKernelDomainProvenance],
    },
    LowerCMatCoordinateWindowExtentInvalid {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      extent [LalinStencil.StencilWindowExtent],
    },
    LowerCMatCoordinateWindowDistanceInvalid {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      distance [LalinStencil.StencilElementDistance],
    },
    LowerCMatCoordinateWindowDistanceOutsideExtent {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      provenance [LalinLower.LowerCMatWindowCoordinateProvenance],
    },
    LowerCMatCoordinateWindowBoundaryUnsupported {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      provenance [LalinLower.LowerCMatWindowCoordinateProvenance],
    },
    LowerCMatCoordinateMaterializationUnavailable {
      variant_unique,
      materialization [LalinCMat.CMatMaterialization],
    },
  },
  product. LowerCMatAddressBasis {
    interned,
    root [LalinMem.MemBase],
    induction [LalinFlow.FlowInduction],
    index_scale_bytes [number],
  },
  product. LowerCMatWindowCoordinateProvenance {
    interned,
    offset [LalinStencil.StencilWindowOffset],
    extent [LalinStencil.StencilWindowExtent],
    boundary [LalinStencil.StencilWindowBoundary],
  },
  sum. LowerCMatUseCoordinate {
    LowerCMatAbsoluteCoordinate {
      variant_unique,
      root [LalinMem.MemBase],
      index [LalinStencil.StencilIndexExpr],
      index_scale_bytes [number],
      const_offset_bytes [number],
    },
    LowerCMatIterationAffineCoordinate {
      variant_unique,
      basis [LalinLower.LowerCMatAddressBasis],
      use_offset_bytes [number],
    },
    LowerCMatWindowRelativeCoordinate {
      variant_unique,
      basis [LalinLower.LowerCMatAddressBasis],
      provenance [LalinLower.LowerCMatWindowCoordinateProvenance],
      use_offset_bytes [number],
    },
    LowerCMatWindowDynamicCoordinate {
      variant_unique,
      basis [LalinLower.LowerCMatAddressBasis],
      provenance [LalinLower.LowerCMatWindowCoordinateProvenance],
      const_offset_bytes [number],
    },
  },
  product. LowerCMatUseCoordinateEntry {
    interned,
    use [LalinCMat.CMatMemoryUseId],
    coordinate [LalinLower.LowerCMatUseCoordinate],
  },
  product. LowerCMatCoordinateFacet {
    interned,
    spine [LalinCMat.CMatMemoryUseSpine],
    iteration [LalinStencil.StencilKernelIteration],
    entries [many [LalinLower.LowerCMatUseCoordinateEntry]],
  },
  sum. LowerCMatCoordinateProjection {
    LowerCMatCoordinatesProjected {
      variant_unique,
      facet [LalinLower.LowerCMatCoordinateFacet],
    },
    LowerCMatCoordinatesRejected {
      variant_unique,
      issues [many [LalinLower.LowerCMatCoordinateIssue]],
    },
  },
  product. LowerCMatCoordinateInput {
    interned,
    iteration [LalinStencil.StencilKernelIteration],
    domain [LalinStencil.StencilKernelDomainProvenance],
    provenance [LalinStencil.StencilAccessByKernelLaneProjection],
    memory [LalinMem.MemAccessProjection],
  },
  product. LowerCMatLaneCoordinateInput {
    interned,
    use [LalinCMat.CMatMemoryUse],
    iteration [LalinStencil.StencilKernelIteration],
    domain [LalinStencil.StencilKernelDomainProvenance],
    memory [LalinMem.MemAccessProjection],
  },
  product. LowerCMatUseMemoryFact {
    interned,
    use [LalinCMat.CMatMemoryUse],
    iteration [LalinStencil.StencilKernelIteration],
    domain [LalinStencil.StencilKernelDomainProvenance],
    provenance [LalinStencil.StencilAccessByKernelLaneEntry],
    memory [LalinMem.MemAccessFact],
  },
  product. LowerCMatIndexCoordinateInput {
    interned,
    use [LalinCMat.CMatMemoryUse],
    iteration [LalinStencil.StencilKernelIteration],
    domain [LalinStencil.StencilKernelDomainProvenance],
    memory [LalinMem.MemAccessFact],
    index [LalinMem.MemIndex],
  },
  product. LowerCMatInductionAlignmentInput {
    interned,
    use [LalinCMat.CMatMemoryUse],
    root [LalinMem.MemBase],
    iteration [LalinStencil.StencilKernelIteration],
    induction [LalinFlow.FlowInduction],
    index_scale_bytes [number],
    use_offset_bytes [number],
  },
  product. LowerCMatWindowCoordinateInput {
    interned,
    use [LalinCMat.CMatMemoryUse],
    root [LalinMem.MemBase],
    iteration [LalinStencil.StencilKernelIteration],
    index [LalinMem.MemIndexInduction],
    offset [LalinStencil.StencilWindowOffset],
  },
  product. LowerCMatWindowAlignmentInput {
    interned,
    use [LalinCMat.CMatMemoryUse],
    root [LalinMem.MemBase],
    iteration [LalinStencil.StencilKernelIteration],
    induction [LalinFlow.FlowInduction],
    index_scale_bytes [number],
    const_offset_bytes [number],
    provenance [LalinLower.LowerCMatWindowCoordinateProvenance],
  },
  product. LowerCMatAlignedWindowCoordinateInput {
    interned,
    use [LalinCMat.CMatMemoryUse],
    basis [LalinLower.LowerCMatAddressBasis],
    const_offset_bytes [number],
    provenance [LalinLower.LowerCMatWindowCoordinateProvenance],
  },
  sum. LowerCMatUseCoordinateResult {
    LowerCMatUseCoordinateProduced {
      variant_unique,
      entry [LalinLower.LowerCMatUseCoordinateEntry],
    },
    LowerCMatUseCoordinateRejected {
      variant_unique,
      issue [LalinLower.LowerCMatCoordinateIssue],
    },
  },
  sum. LowerCMatCoordinateAssembly {
    LowerCMatCoordinateCollecting {
      variant_unique,
      spine [LalinCMat.CMatMemoryUseSpine],
      iteration [LalinStencil.StencilKernelIteration],
      entries [many [LalinLower.LowerCMatUseCoordinateEntry]],
    },
    LowerCMatCoordinateAssemblyRejected {
      variant_unique,
      spine [LalinCMat.CMatMemoryUseSpine],
      issues [many [LalinLower.LowerCMatCoordinateIssue]],
    },
  },
  sum. LowerCMatUseCoordinateLookup {
    LowerCMatUseCoordinateFound {
      variant_unique,
      entry [LalinLower.LowerCMatUseCoordinateEntry],
    },
    LowerCMatUseCoordinateMissing {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
    },
    LowerCMatUseCoordinateAmbiguous {
      variant_unique,
      use [LalinCMat.CMatMemoryUseId],
      count [number],
    },
  },
  product. LowerKernelCMatStateInput {
    interned,
    kernel [LalinKernel.KernelId],
    memory [LalinMem.MemAccessProjection],
  },
  product. LowerKernelCMatMaterializationInput {
    interned,
    projection [LalinStencil.StencilKernelComputationProjection],
    memory [LalinMem.MemAccessProjection],
  },
  product. LowerCMatCoordinateContributionInput {
    interned,
    assembly [LalinLower.LowerCFragmentAssemblyInput],
    materialization [LalinCMat.CMatMaterialization],
  },
  product. LowerCMatMaterializationContributionInput {
    interned,
    assembly [LalinLower.LowerCFragmentAssemblyInput],
    coordinates [LalinLower.LowerCMatCoordinateFacet],
  },

  sum. LowerKernelCMatState {
    LowerKernelCMatReady {
      variant_unique,
      projection [LalinStencil.StencilKernelComputationProjection],
      materialization [LalinCMat.CMatMaterialization],
      coordinates [LalinLower.LowerCMatCoordinateProjection],
    },
    LowerKernelCMatRejected {
      variant_unique,
      rejects [many [LalinStencil.StencilKernelProjectionReject]],
    },
    LowerKernelCMatUnavailable { variant_unique, reason [str], },
  },
  product. LowerKernelCMatEntry {
    interned,
    kernel [LalinKernel.KernelId],
    state [LalinLower.LowerKernelCMatState],
  },
  product. LowerKernelCMatProjection {
    interned,
    entries [many [LalinLower.LowerKernelCMatEntry]],
  },
  sum. LowerKernelCMatLookup {
    LowerKernelCMatFound { variant_unique, entry [LalinLower.LowerKernelCMatEntry], },
    LowerKernelCMatMissing { variant_unique, kernel [LalinKernel.KernelId], },
    LowerKernelCMatAmbiguous { variant_unique, kernel [LalinKernel.KernelId], count [number], },
  },
  product. LowerKernelCMatPreparationInput {
    interned,
    field. module [LalinCode.CodeModule],
    graph [LalinGraph.CodeGraph],
    kernels [LalinKernel.KernelModulePlan],
    schedules [LalinSchedule.ScheduleModulePlan],
    semantics [LalinFlow.FlowSemanticFactSet],
    compiler [LalinStencil.StencilCompilerPolicy],
  },
  sum. LowerKernelCMatPreparation {
    LowerKernelCMatPrepared {
      variant_unique,
      projection [LalinLower.LowerKernelCMatProjection],
    },
    LowerKernelCMatPreparationRejected {
      variant_unique,
      expected [LalinCode.CodeModuleId],
      actual [LalinCode.CodeModuleId],
    },
    LowerKernelCMatPreparationFacetRejected { variant_unique, reason [str], },
  },
  product. LowerCPreparedModuleInput {
    interned,
    spine [LalinLower.LowerBackSpine],
    plan [LalinLower.LowerModule],
  },
  sum. LowerFragmentCoverageOrigin {
    LowerCoverageFunction,
    LowerCoverageLoop { variant_unique, loop [LalinGraph.GraphLoop], },
    LowerCoverageBlock,
    LowerCoverageBlockRange,
  },
  product. LowerFragmentCoverage {
    interned,
    func [LalinCode.CodeFuncId],
    origin [LalinLower.LowerFragmentCoverageOrigin],
    covered_blocks [many [LalinCode.CodeBlockId]],
    replacement_source [LalinCode.CodeBlockId],
  },
  product. LowerFragmentCoverageInput {
    interned,
    code_func [LalinCode.CodeFunc],
    loops [LalinLower.LowerLoopByIdProjection],
  },
  sum. LowerFragmentCoverageResolution {
    LowerFragmentCoverageResolved {
      variant_unique,
      coverage [LalinLower.LowerFragmentCoverage],
    },
    LowerFragmentCoverageRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  sum. LowerCBlockCoverageDecision {
    LowerCBlockCovered,
    LowerCBlockOutsideCoverage,
  },
  product. LowerCTermEdgeOrigin {
    interned,
    source [LalinCode.CodeBlockId],
    term [LalinCode.CodeTermId],
  },
  sum. LowerCTermEdgeOccurrence {
    LowerCTermEdgeOnly,
    LowerCTermEdgeThen,
    LowerCTermEdgeElse,
    LowerCTermEdgeCase { variant_unique, ordinal [number], },
    LowerCTermEdgeDefault,
  },
  product. LowerCIncomingEdgeArguments {
    interned,
    origin [LalinLower.LowerCTermEdgeOrigin],
    occurrence [LalinLower.LowerCTermEdgeOccurrence],
    destination [LalinCode.CodeBlockId],
    args [many [LalinCode.CodeValueId]],
  },
  product. LowerCIncomingEdgeProjection {
    interned,
    entries [many [LalinLower.LowerCIncomingEdgeArguments]],
  },
  product. LowerCBlockParamEntry {
    interned,
    block [LalinCode.CodeBlockId],
    ordinal [number],
    field. value [LalinLower.LowerCValueTypeEntry],
    parameter [LalinC.CBackendBlockParam],
  },
  product. LowerCBlockParamProjection {
    interned,
    entries [many [LalinLower.LowerCBlockParamEntry]],
  },
  sum. LowerCSourceValueEvidence {
    LowerCSourceFunctionParam,
    LowerCSourceDominates {
      variant_unique,
      dominator [LalinCode.CodeBlockId],
      block [LalinCode.CodeBlockId],
    },
  },
  product. LowerCIncomingBlockArgument {
    interned,
    edge [LalinLower.LowerCIncomingEdgeArguments],
    ordinal [number],
    field. value [LalinLower.LowerCValueTypeEntry],
    definition [LalinLower.LowerCValueDefinitionSite],
    evidence [LalinLower.LowerCSourceValueEvidence],
  },
  product. LowerCIncomingArgumentInput {
    interned,
    func [LalinCode.CodeFuncId],
    replacement [LalinCode.CodeBlockId],
    edge [LalinLower.LowerCIncomingEdgeArguments],
    ordinal [number],
    field. value [LalinLower.LowerCValueTypeEntry],
    definition [LalinLower.LowerCValueDefinitionSite],
    dominance [LalinLower.LowerCDominanceProjection],
  },
  product. LowerCDominatingIncomingArgumentInput {
    interned,
    request [LalinLower.LowerCIncomingArgumentInput],
    dominator [LalinCode.CodeBlockId],
  },
  sum. LowerCIncomingArgumentResolution {
    LowerCIncomingArgumentResolved {
      variant_unique,
      argument [LalinLower.LowerCIncomingBlockArgument],
    },
    LowerCIncomingArgumentRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  sum. LowerCIncomingArgumentCollection {
    LowerCIncomingArgumentsCollecting {
      variant_unique,
      entries [many [LalinLower.LowerCIncomingBlockArgument]],
    },
    LowerCIncomingArgumentsRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCAdapterFinishInput {
    interned,
    request [LalinLower.LowerCReplacementEntryAdapterInput],
    block [LalinCode.CodeBlock],
    parameters [many [LalinLower.LowerCBlockParamEntry]],
  },
  product. LowerCReplacementParamAdapter {
    interned,
    parameter [LalinLower.LowerCBlockParamEntry],
    incoming [many [LalinLower.LowerCIncomingBlockArgument]],
  },
  product. LowerCReplacementEntryProjection {
    interned,
    source [LalinCode.CodeFunc],
    block [LalinCode.CodeBlockId],
    entries [many [LalinLower.LowerCReplacementParamAdapter]],
  },
  product. LowerCReplacementEntryAdapterInput {
    interned,
    code_func [LalinCode.CodeFunc],
    baseline [LalinLower.LowerCFunctionEmission],
    replacement [LalinCode.CodeBlockId],
    dominance [LalinLower.LowerCDominanceProjection],
  },
  sum. LowerCReplacementEntryAdapterConstruction {
    LowerCReplacementEntryAdapterReady {
      variant_unique,
      projection [LalinLower.LowerCReplacementEntryProjection],
    },
    LowerCReplacementEntryAdapterRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCDominatorEntry {
    interned,
    block [LalinCode.CodeBlockId],
    dominators [many [LalinCode.CodeBlockId]],
  },
  product. LowerCDominanceProjection {
    interned,
    source [LalinCode.CodeFunc],
    graph [LalinGraph.CodeFuncGraph],
    entries [many [LalinLower.LowerCDominatorEntry]],
  },
  product. LowerCDominanceConstructionInput {
    interned,
    code_func [LalinCode.CodeFunc],
    graph [LalinGraph.CodeFuncGraph],
  },
  sum. LowerCDominanceConstruction {
    LowerCDominanceReady {
      variant_unique,
      dominance [LalinLower.LowerCDominanceProjection],
    },
    LowerCDominanceRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCDominanceQuery {
    interned,
    dominator [LalinCode.CodeBlockId],
    block [LalinCode.CodeBlockId],
  },
  sum. LowerCDominanceLookup {
    LowerCDominates,
    LowerCDoesNotDominate,
    LowerCDominanceMissing { variant_unique, reason [str], },
  },
  sum. LowerCEntryValueSource {
    LowerCEntryFunctionParam,
    LowerCEntryDominatingBlockParam {
      variant_unique,
      block [LalinCode.CodeBlockId],
    },
    LowerCEntryReplacementBlockParam {
      variant_unique,
      adapter [LalinLower.LowerCReplacementParamAdapter],
    },
    LowerCEntryDominatingInstruction {
      variant_unique,
      block [LalinCode.CodeBlockId],
      inst [LalinCode.CodeInstId],
    },
  },
  product. LowerCEntryValueBinding {
    interned,
    field. value [LalinLower.LowerCValueTypeEntry],
    source [LalinLower.LowerCEntryValueSource],
  },
  product. LowerCEntryValueProjection {
    interned,
    entries [many [LalinLower.LowerCEntryValueBinding]],
  },
  product. LowerCEntryAvailabilityCandidate {
    interned,
    field. value [LalinLower.LowerCValueTypeEntry],
    site [LalinLower.LowerCValueDefinitionSite],
    replacement [LalinCode.CodeBlockId],
    adapters [LalinLower.LowerCReplacementEntryProjection],
  },
  product. LowerCMatValueCollection {
    interned,
    entries [many [LalinCMat.CMatCExternalValueBindingEntry]],
    availability [many [LalinLower.LowerCEntryValueBinding]],
  },
  product. LowerCMatValueEnvironmentInput {
    interned,
    code_func [LalinCode.CodeFunc],
    baseline [LalinLower.LowerCFunctionEmission],
    coverage [LalinLower.LowerFragmentCoverage],
    dominance [LalinLower.LowerCDominanceProjection],
    adapters [LalinLower.LowerCReplacementEntryProjection],
  },
  sum. LowerCMatValueEnvironment {
    LowerCMatValuesReady {
      variant_unique,
      values [LalinCMat.CMatCExternalValueBindingProjection],
      availability [LalinLower.LowerCEntryValueProjection],
    },
    LowerCMatValuesRejected { variant_unique, issue [LalinLower.LowerIssue], },
  },
  product. LowerCMatAccessFact {
    interned,
    binding [LalinCMat.CMatAccessBinding],
    provenance [LalinStencil.StencilAccessByKernelLaneEntry],
    mem_access [LalinMem.MemAccessId],
    alignment [LalinMem.MemAlignment],
    bounds [LalinMem.MemBounds],
    trap [LalinMem.MemTrap],
    movement [LalinMem.MemMovementDecision],
    elem_size [number],
    stride [number],
  },
  product. LowerCMatAccessSourceInput {
    interned,
    fact [LalinLower.LowerCMatAccessFact],
    values [LalinCMat.CMatCExternalValueBindingProjection],
  },
  sum. LowerCMatAccessSourceResolution {
    LowerCMatAccessSourceReady {
      variant_unique,
      source [LalinCMat.CMatCFragmentAccessSource],
    },
    LowerCMatAccessSourceRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCMatDirectAccessInput {
    interned,
    access [LalinStencil.StencilAccessRef],
    values [LalinCMat.CMatCExternalValueBindingProjection],
    expected [LalinC.CBackendType],
  },
  product. LowerCMatAccessCollection {
    interned,
    entries [many [LalinCMat.CMatCFragmentAccessBindingEntry]],
  },
  product. LowerCMatAccessFinishInput {
    interned,
    fact [LalinLower.LowerCMatAccessFact],
    collection [LalinLower.LowerCMatAccessCollection],
  },
  sum. LowerCMatAccessBuildStep {
    LowerCMatAccessBuildReady {
      variant_unique,
      collection [LalinLower.LowerCMatAccessCollection],
    },
    LowerCMatAccessBuildRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  sum. LowerCMatAccessRelationValidation {
    LowerCMatAccessRelationValid,
    LowerCMatAccessRelationRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCMatAccessEvidence {
    interned,
    request [LalinLower.LowerCMatAccessBuildRequest],
    binding [LalinCMat.CMatAccessBinding],
    provenance [LalinStencil.StencilAccessByKernelLaneEntry],
    mem_access [LalinMem.MemAccessId],
    backend [LalinMem.MemBackendAccessInfo],
    elem_size [number],
    stride [number],
    collection [LalinLower.LowerCMatAccessCollection],
    next_index [number],
  },
  sum. LowerCMatAccessPatternAdmission {
    LowerCMatAccessPatternAdmitted,
    LowerCMatAccessPatternRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  sum. LowerCMatAccessContractAdmission {
    LowerCMatAccessContractAdmitted,
    LowerCMatAccessContractRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCMatAccessBuildRequest {
    interned,
    bindings [many [LalinCMat.CMatAccessBinding]],
    provenance [LalinStencil.StencilAccessByKernelLaneProjection],
    values [LalinCMat.CMatCExternalValueBindingProjection],
    target [LalinC.CBackendTarget],
  },
  product. LowerCMatAccessFoldInput {
    interned,
    request [LalinLower.LowerCMatAccessBuildRequest],
    index [number],
  },
  product. LowerCMatAccessEnvironmentInput {
    interned,
    materialization [LalinCMat.CMatMaterializedKernelFragment],
    values [LalinCMat.CMatCExternalValueBindingProjection],
    target [LalinC.CBackendTarget],
  },
  sum. LowerCMatAccessEnvironment {
    LowerCMatAccessesReady {
      variant_unique,
      accesses [LalinCMat.CMatCFragmentAccessBindingProjection],
    },
    LowerCMatAccessesRejected { variant_unique, issue [LalinLower.LowerIssue], },
  },
  sum. LowerCMatExitArgumentPlan {
    LowerCMatExitNoArguments,
    LowerCMatExitControlValue,
    LowerCMatExitSourceEdge {
      variant_unique,
      source [LalinCode.CodeBlockId],
    },
  },
  product. LowerCMatExitRequirement {
    interned,
    role [LalinCMat.CMatCExitRole],
    destination [LalinCode.CodeBlockId],
    argument_plan [LalinLower.LowerCMatExitArgumentPlan],
  },
  product. LowerCMatSourceExitInput {
    interned,
    source [LalinCode.CodeBlockId],
    destination [LalinCode.CodeBlockId],
  },
  sum. LowerCMatExitArgumentResolution {
    LowerCMatExitArgumentsResolved {
      variant_unique,
      args [many [LalinCode.CodeValueId]],
    },
    LowerCMatExitArgumentsRejected { variant_unique, reason [str], },
  },
  product. LowerCMatExitRequirementProjection {
    interned,
    entries [many [LalinLower.LowerCMatExitRequirement]],
  },
  product. LowerCMatExitCollection {
    interned,
    entries [many [LalinCMat.CMatCExitBindingEntry]],
  },
  product. LowerCMatExitBuildInput {
    interned,
    requirement [LalinLower.LowerCMatExitRequirement],
    code_func [LalinCode.CodeFunc],
    collection [LalinLower.LowerCMatExitCollection],
  },
  sum. LowerCMatExitBuildStep {
    LowerCMatExitBuildReady {
      variant_unique,
      collection [LalinLower.LowerCMatExitCollection],
    },
    LowerCMatExitBuildRejected { variant_unique, issue [LalinLower.LowerIssue], },
  },
  product. LowerCMatExitFoldInput {
    interned,
    requirements [LalinLower.LowerCMatExitRequirementProjection],
    code_func [LalinCode.CodeFunc],
    index [number],
  },
  sum. LowerCMatExitRequirements {
    LowerCMatExitRequirementsReady {
      variant_unique,
      requirements [LalinLower.LowerCMatExitRequirementProjection],
    },
    LowerCMatExitRequirementsRejected {
      variant_unique,
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCMatExitEnvironmentInput {
    interned,
    provenance [LalinStencil.StencilKernelProvenanceFacet],
    coverage [LalinLower.LowerFragmentCoverage],
    code_func [LalinCode.CodeFunc],
  },
  sum. LowerCMatExitEnvironment {
    LowerCMatExitsReady {
      variant_unique,
      exits [LalinCMat.CMatCExitBindingProjection],
    },
    LowerCMatExitsRejected { variant_unique, issue [LalinLower.LowerIssue], },
  },
  product. LowerCMatAddressEnvironmentInput {
    interned,
    environment [LalinLower.LowerCMatEnvironmentInput],
    values [LalinLower.LowerCMatValuesReady],
    accesses [LalinLower.LowerCMatAccessesReady],
  },
  product. LowerCMatAddressPlanReadyInput {
    interned,
    environment [LalinLower.LowerCMatAddressEnvironmentInput],
    plan [LalinCMat.CMatCAddressPlan],
  },
  product. LowerCMatEnvironmentInput {
    interned,
    fragment [LalinLower.LowerFragment],
    materialization [LalinCMat.CMatMaterializedKernelFragment],
    coordinates [LalinLower.LowerCMatCoordinateFacet],
    coverage [LalinLower.LowerFragmentCoverage],
    code_func [LalinCode.CodeFunc],
    baseline [LalinLower.LowerCFunctionEmission],
    dominance [LalinLower.LowerCDominanceProjection],
    adapters [LalinLower.LowerCReplacementEntryProjection],
    namespace [LalinCMat.CMatCFragmentNamespace],
    reserved_labels [many [LalinC.CBackendLabel]],
    target [LalinC.CBackendTarget],
  },
  sum. LowerCMatEnvironment {
    LowerCMatEnvironmentReady {
      variant_unique,
      request [LalinCMat.CMatCFragmentInput],
    },
    LowerCMatEnvironmentRejected { variant_unique, issue [LalinLower.LowerIssue], },
  },
  sum. LowerCEmittedFragment {
    LowerCCodeFragment {
      variant_unique,
      fragment [LalinLower.LowerFragment],
      coverage [LalinLower.LowerFragmentCoverage],
    },
    LowerCKernelCMatFragment {
      variant_unique,
      fragment [LalinLower.LowerFragment],
      coverage [LalinLower.LowerFragmentCoverage],
      cmat [LalinCMat.CMatCFragment],
    },
    LowerCRejectedFragment {
      variant_unique,
      fragment [LalinLower.LowerFragmentId],
      issue [LalinLower.LowerIssue],
    },
  },
  product. LowerCFragmentAssemblyInput {
    interned,
    fragment [LalinLower.LowerFragment],
    coverage [LalinLower.LowerFragmentCoverage],
    code_func [LalinCode.CodeFunc],
    baseline [LalinLower.LowerCFunctionEmission],
    materializations [LalinLower.LowerKernelCMatProjection],
    dominance [LalinLower.LowerCDominanceProjection],
    adapters [LalinLower.LowerCReplacementEntryProjection],
    namespace [LalinCMat.CMatCFragmentNamespace],
    reserved_labels [many [LalinC.CBackendLabel]],
    target [LalinC.CBackendTarget],
  },
  product. LowerCFunctionAssembly {
    interned,
    code_func [LalinCode.CodeFunc],
    baseline [LalinLower.LowerCFunctionEmission],
    fragments [many [LalinLower.LowerCEmittedFragment]],
    blocks [many [LalinC.CBackendBlock]],
    locals [many [LalinC.CBackendLocal]],
    helpers [many [LalinC.CBackendHelperUse]],
  },
  sum. LowerCFunctionAssemblyResult {
    LowerCFunctionAssemblyReady {
      variant_unique,
      assembly [LalinLower.LowerCFunctionAssembly],
    },
    LowerCFunctionAssemblyRejected {
      variant_unique,
      func [LalinCode.CodeFuncId],
      issues [many [LalinLower.LowerIssue]],
    },
  },
  product. LowerCFunctionAssemblyInput {
    interned,
    spine [LalinLower.LowerBackSpine],
    code_func [LalinCode.CodeFunc],
    plan [LalinLower.LowerFuncPlan],
    baseline [LalinLower.LowerCFunctionEmission],
    materializations [LalinLower.LowerKernelCMatProjection],
  },
  product. LowerBackSpine {
    interned,
    code_module [LalinCode.CodeModule],
    graph [LalinGraph.CodeGraph],
    target [LalinC.CBackendTarget],
  },
  product. LowerCModuleInput {
    interned,
    spine [LalinLower.LowerBackSpine],
    plan [LalinLower.LowerModule],
    materializations [LalinLower.LowerKernelCMatProjection],
  },
  product. LowerCSignatureEntry {
    interned,
    code_sig [LalinCode.CodeSigId],
    code_signature [LalinCode.CodeSig],
    c_sig_id [LalinC.CBackendFuncSigId],
    c_sig [LalinC.CBackendFuncSig],
  },
  product. LowerCSignatureProjection {
    interned,
    entries [many [LalinLower.LowerCSignatureEntry]],
  },
  sum. LowerCSignatureLookup {
    LowerCSignatureFound { variant_unique, entry [LalinLower.LowerCSignatureEntry], },
    LowerCSignatureMissing { variant_unique, sig [LalinCode.CodeSigId], },
  },
  product. LowerCValueTypeEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    code_ty [LalinCode.CodeType],
    c_local [LalinC.CBackendLocal],
  },
  product. LowerCValueTypeProjection {
    interned,
    entries [many [LalinLower.LowerCValueTypeEntry]],
  },
  sum. LowerCValueTypeLookup {
    LowerCValueTypeFound { variant_unique, entry [LalinLower.LowerCValueTypeEntry], },
    LowerCValueTypeMissing { variant_unique, field. value [LalinCode.CodeValueId], },
  },
  sum. LowerCValueDefinitionSite {
    LowerCFunctionParamSite,
    LowerCBlockParamSite { variant_unique, block [LalinCode.CodeBlockId], },
    LowerCInstructionSite {
      variant_unique,
      block [LalinCode.CodeBlockId],
      inst [LalinCode.CodeInstId],
    },
  },
  product. LowerCValueSiteEntry {
    interned,
    field. value [LalinCode.CodeValueId],
    site [LalinLower.LowerCValueDefinitionSite],
  },
  product. LowerCValueSiteProjection {
    interned,
    entries [many [LalinLower.LowerCValueSiteEntry]],
  },
  product. LowerCValueAvailabilityInput {
    interned,
    coverage [LalinLower.LowerFragmentCoverage],
    field. value [LalinLower.LowerCValueTypeEntry],
    dominance [LalinLower.LowerCDominanceProjection],
    adapters [LalinLower.LowerCReplacementEntryProjection],
  },
  sum. LowerCValueAvailabilityContribution {
    LowerCValueAvailable {
      variant_unique,
      binding [LalinLower.LowerCEntryValueBinding],
    },
    LowerCValueUnavailable,
  },
  product. LowerCInstructionInput {
    interned,
    signatures [LalinLower.LowerCSignatureProjection],
    values [LalinLower.LowerCValueTypeProjection],
  },
  product. LowerCInstEmission {
    interned,
    stmts [many [LalinC.CBackendStmt]],
    helpers [many [LalinC.CBackendHelperUse]],
    locals [many [LalinC.CBackendLocal]],
    definitions [many [LalinLower.LowerCValueTypeEntry]],
  },
  product. LowerCTermInput {
    interned,
    values [LalinLower.LowerCValueTypeProjection],
  },
  product. LowerCBlockInput {
    interned,
    signatures [LalinLower.LowerCSignatureProjection],
    values [LalinLower.LowerCValueTypeProjection],
  },
  product. LowerCBlockEmission {
    interned,
    block [LalinC.CBackendBlock],
    helpers [many [LalinC.CBackendHelperUse]],
    locals [many [LalinC.CBackendLocal]],
    values [LalinLower.LowerCValueTypeProjection],
    value_sites [many [LalinLower.LowerCValueSiteEntry]],
  },
  product. LowerCTermEmission {
    interned,
    term [LalinC.CBackendTerminator],
  },
  product. LowerCFunctionInput {
    interned,
    signatures [LalinLower.LowerCSignatureProjection],
  },
  product. LowerCFunctionEmission {
    interned,
    func [LalinC.CBackendFunc],
    helpers [many [LalinC.CBackendHelperUse]],
    value_types [LalinLower.LowerCValueTypeProjection],
    value_sites [LalinLower.LowerCValueSiteProjection],
    source [LalinCode.CodeFunc],
    block_params [LalinLower.LowerCBlockParamProjection],
  },
  product. LowerCModuleEmission {
    interned,
    unit [LalinC.CBackendUnit],
    signatures [LalinLower.LowerCSignatureProjection],
    functions [many [LalinLower.LowerCFunctionEmission]],
  },
  sum. LowerCModuleResult {
    LowerCModuleEmitted {
      variant_unique,
      emission [LalinLower.LowerCModuleEmission],
    },
    LowerCModuleRejected {
      variant_unique,
      issues [many [LalinLower.LowerIssue]],
    },
  },
  product. LowerFragment {
    interned,
    field. id [LalinLower.LowerFragmentId],
    cover [LalinLower.LowerCover],
    strategy [LalinLower.LowerStrategy],
    proofs [many [LalinLower.LowerProof]],
    issues [many [LalinLower.LowerIssue]],
  },
  product. LowerFuncPlan {
    interned,
    func [LalinCode.CodeFuncId],
    fragments [many [LalinLower.LowerFragment]],
  },
  product. LowerFunctionPlanEntry {
    interned,
    func [LalinCode.CodeFuncId],
    plan [LalinLower.LowerFuncPlan],
  },
  product. LowerFunctionPlanProjection {
    interned,
    entries [many [LalinLower.LowerFunctionPlanEntry]],
  },
  sum. LowerFunctionPlanLookup {
    LowerFunctionPlanFound { variant_unique, entry [LalinLower.LowerFunctionPlanEntry], },
    LowerFunctionPlanMissing { variant_unique, func [LalinCode.CodeFuncId], },
  },
  product. LowerModule {
    interned,
    field. module [LalinCode.CodeModuleId],
    target [LalinLower.LowerTarget],
    kernels [LalinKernel.KernelModulePlan],
    schedules [LalinSchedule.ScheduleModulePlan],
    funcs [LalinLower.LowerFunctionPlanProjection],
    issues [many [LalinLower.LowerIssue]],
  },
}