local S = require("lalin.schema.dsl")
S.use()

return schema. LalinCheck {
  -- SwitchKeyClass: typed classification of switch key expressions.
  -- Replaces the old SwitchKeyDecision delayed-control union.
  -- Produced by leaf methods on Expr instead of a standalone dispatch.
  sum. SwitchKeyClass {
    SwitchConstKeyClass { keys [many [LalinTree.SwitchKey]], },
    SwitchExprKeyClass { keys [many [LalinTree.SwitchKey]], },
    SwitchCompareKeyClass { keys [many [LalinTree.SwitchKey]], comparison [LalinCore.CmpOp], },
  },

  -- Typecheck input products
  product. TypeValueScope {
    interned,
    module_name [str],
    values [many [LalinBind.ValueEntry]],
    types [many [LalinBind.TypeEntry]],
    layouts [many [LalinSem.TypeLayout]],
    facts [LalinCheck.TypeModuleFacts],
  },
  sum. TypeValueLookup {
    TypeValueLookupFound { variant_unique, binding [LalinBind.Binding], },
    TypeValueLookupMissing { variant_unique, field. name [str], },
  },
  sum. TypeEntryLookup {
    TypeEntryLookupFound { variant_unique, field. ty [LalinType.Type], },
    TypeEntryLookupMissing { variant_unique, field. fallback [LalinType.Type], },
  },
  sum. TypeVariantDefLookup {
    TypeVariantDefLookupFound { variant_unique, def [LalinCheck.TypeVariantDef], },
    TypeVariantDefLookupMissing { variant_unique, type_name [str], field. ty [LalinType.Type], },
  },
  sum. TypeVariantCaseLookup {
    TypeVariantCaseLookupFound { variant_unique, def [LalinCheck.TypeVariantDef], case [LalinCheck.TypeVariantCase], },
    TypeVariantCaseLookupMissing { variant_unique, type_name [str], variant_name [str], field. ty [LalinType.Type], },
  },
  -- TypeRef leaf-name projection: every TypeRef projects to its last path
  -- segment; the lookup leaves own the found/missing decision (no nil).
  sum. TypeRefLeafLookup {
    TypeRefLeafFound { variant_unique, field. name [str], },
    TypeRefLeafMissing { variant_unique, field. ref [LalinType.TypeRef], },
  },
  -- Named-ref projection: which TypeRef a type names for layout matching.
  sum. TypeNamedRefLookup {
    TypeNamedRefFound { variant_unique, field. ref [LalinType.TypeRef], },
    TypeNamedRefMissing { variant_unique, field. ty [LalinType.Type], },
  },
  sum. TypeVariantPayloadLookup {
    TypeVariantPayloadNone,
    TypeVariantPayloadFields { variant_unique, fields [many [LalinType.FieldDecl]], },
  },
  product. TypeVariantArmResult { interned, arm [LalinTree.SwitchVariantStmtArm], issues [many [LalinCheck.TypeIssue]], },
  product. TypeScopeChange { interned, scope [LalinCheck.TypeValueScope], },
  product. TypeNameScope { interned, types [many [LalinBind.TypeEntry]], },
  product. TypeExprInput { interned, scope [LalinCheck.TypeValueScope], },
  product. TypeExpectedExprInput {
    interned,
    scope [LalinCheck.TypeValueScope],
    expected [LalinType.Type],
  },
  product. TypeValueRefInput { interned, scope [LalinCheck.TypeValueScope], },
  product. TypeValueRefResult {
    interned,
    field. ref [LalinBind.ValueRef],
    field. ty [LalinType.Type],
    issues [many [LalinCheck.TypeIssue]],
  },
  product. TypePlaceInput { interned, scope [LalinCheck.TypeValueScope], },
  product. TypeIndexBaseInput { interned, scope [LalinCheck.TypeValueScope], },
  product. TypeViewInput { interned, scope [LalinCheck.TypeValueScope], },
  product. TypeStmtInput {
    interned,
    scope [LalinCheck.TypeValueScope],
    return_ty [LalinType.Type],
    yield [LalinCheck.TypeYieldResult],
  },
  product. TypeControlInput { interned, stmt [LalinCheck.TypeStmtInput], region_id [str], },
  product. TypeFuncInput { interned, scope [LalinCheck.TypeValueScope], },
  product. TypeItemInput { interned, scope [LalinCheck.TypeValueScope], },
  product. TypePolicyInput { interned, site [str], },
  product. TypePolicyResult { interned, issues [many [LalinCheck.TypeIssue]], },
  product. TypeCanonicalInput { interned, names [LalinCheck.TypeNameScope], },
  product. TypeCanonicalResult { interned, field. ty [LalinType.Type], },
  product. TypeBinaryInput { interned, op [LalinCore.BinaryOp], rhs [LalinType.Type], },
  product. TypeBinaryResult { interned, field. ty [LalinType.Type], issues [many [LalinCheck.TypeIssue]], },
  product. TypeCompareInput { interned, op [LalinCore.CmpOp], rhs [LalinType.Type], },
  product. TypeCompareResult { interned, field. ty [LalinType.Type], issues [many [LalinCheck.TypeIssue]], },

  -- Typecheck result sums
  sum. TypeViewResult {
    TypeViewResult {
      variant_unique,
      view [LalinTree.View],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypeIndexBaseResult {
    TypeIndexBaseResult {
      variant_unique,
      base [LalinTree.IndexBase],
      elem [LalinType.Type],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypeControlStmtRegionResult {
    TypeControlStmtRegionResult {
      variant_unique,
      region [LalinTree.ControlStmtRegion],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypeControlExprRegionResult {
    TypeControlExprRegionResult {
      variant_unique,
      region [LalinTree.ControlExprRegion],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypeExprResult {
    TypeExprResult {
      variant_unique,
      field. expr [LalinTree.Expr],
      field. ty [LalinType.Type],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypePlaceResult {
    TypePlaceResult {
      variant_unique,
      place [LalinTree.Place],
      field. ty [LalinType.Type],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  -- Aggregate field init: the resolved FieldInit plus any issues raised
  -- during field layout/offset resolution.
  product. TypeAggFieldInit {
    interned,
    init [LalinTree.FieldInit],
    issues [many [LalinCheck.TypeIssue]],
  },
  sum. TypeStmtResult {
    TypeStmtResult {
      variant_unique,
      state [LalinCheck.TypeStmtInput],
      stmts [many [LalinTree.Stmt]],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypeFuncResult {
    TypeFuncResult {
      variant_unique,
      func [LalinTree.Func],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypeItemResult {
    TypeItemResult {
      variant_unique,
      items [many [LalinTree.Item]],
      issues [many [LalinCheck.TypeIssue]],
    },
  },
  sum. TypeModuleResult {
    TypeModuleResult {
      variant_unique,
      field. module [LalinTree.Module],
      issues [many [LalinCheck.TypeIssue]],
      target [LalinHost.HostTargetModel],
    },
  },

  -- Yield result classification
  sum. TypeYieldResult {
    TypeYieldNone,
    TypeYieldVoid,
    TypeYieldValue { variant_unique, field. ty [LalinType.Type], },
  },

  -- Type facts accumulated during typecheck
  product. TypeVariantCase {
    interned,
    field. name [str],
    tag [number],
    fields [many [LalinType.FieldDecl]],
  },
  product. TypeVariantDef {
    interned,
    type_name [str],
    field. ty [LalinType.Type],
    variants [many [LalinCheck.TypeVariantCase]],
  },
  product. TypeHandleDef {
    interned,
    field. name [str],
    field. ty [LalinType.Type],
    repr [LalinType.HandleRepr],
    invalid [LalinType.HandleInvalid],
    domain [optional [LalinType.TypeRef]],
    target [optional [LalinType.TypeRef]],
  },
  product. TypeFuncEffect {
    interned,
    field. name [str],
    params [many [LalinType.Param]],
    readonly [many [str]],
    preserve [many [str]],
    invalidate [many [str]],
  },
  product. TypeModuleFacts {
    interned,
    variants [many [LalinCheck.TypeVariantDef]],
    handles [many [LalinCheck.TypeHandleDef]],
    effects [many [LalinCheck.TypeFuncEffect]],
    region [LalinTree.RegionFactProjection],
  },
  product. TypeModuleFactsInput { interned, module_name [str], },

  -- Type issues: all leaves preserved, references updated to LalinCheck
  sum. TypeUnaryIssueReason {
    TypeUnaryInvalidOperator { variant_unique, op [str], },
    TypeUnaryLeaseEscapeReturn,
    TypeUnaryLeaseEscapeYield,
    TypeUnaryLeaseEscapeStore,
    TypeUnaryLeaseEscapeCall,
    TypeUnaryLeaseInvalidatingCall,
    TypeUnaryLeaseEscapeAggregate,
    TypeUnaryRegionCallLeasePayload,
    TypeUnaryLeaseEscapeDurable,
    TypeUnaryOwnedDropped,
    TypeUnaryOwnedUseAfterMove,
    TypeUnaryOwnedObservedWithoutTransfer,
    TypeUnaryOwnedCapturedDurable,
    TypeUnaryOwnedBranchMismatch,
    TypeUnaryOwnedVarCellUnsupported,
    TypeUnaryOwnedRegionCallPayload,
    TypeUnaryOwnedEmitTargetMismatch,
    TypeUnaryOwnedInvalidComposition,
    TypeUnaryHandleCast,
    TypeUnaryHandleRepr,
    TypeUnaryHandleTargetMismatch,
    TypeUnaryHandleDomainMissing,
    TypeUnaryHandleDomainAccess,
    TypeUnaryHandleLeaseOriginMissing,
    TypeUnaryHandleLeaseOriginMismatch,
    TypeUnaryAtomicRmwPointerOp,
    TypeUnaryAtomicRmwBoolAddSub,
    TypeUnaryAtomicInvalidValue { variant_unique, site [str], },
  },
  sum. TypeIssue {
    TypeIssueUnresolvedValue { variant_unique, field. name [str], },
    TypeIssueUnresolvedPath { variant_unique, path [LalinCore.Path], },
    TypeIssueExpected {
      variant_unique,
      site [str],
      expected [LalinType.Type],
      actual [LalinType.Type],
    },
    TypeIssueArgCount { variant_unique, site [str], expected [number], actual [number], },
    TypeIssueNotCallable { variant_unique, field. ty [LalinType.Type], },
    TypeIssueNotIndexable { variant_unique, field. ty [LalinType.Type], },
    TypeIssueNotPointer { variant_unique, field. ty [LalinType.Type], },
    TypeIssueInvalidUnary {
      variant_unique,
      reason [LalinCheck.TypeUnaryIssueReason],
      field. ty [LalinType.Type],
    },
    TypeIssueInvalidBinary {
      variant_unique,
      op [str],
      lhs [LalinType.Type],
      rhs [LalinType.Type],
    },
    TypeIssueInvalidCompare {
      variant_unique,
      op [str],
      lhs [LalinType.Type],
      rhs [LalinType.Type],
    },
    TypeIssueInvalidLogic {
      variant_unique,
      op [str],
      lhs [LalinType.Type],
      rhs [LalinType.Type],
    },
    TypeIssueMissingJumpTarget {
      variant_unique,
      region_id [str],
      label [LalinTree.BlockLabel],
    },
    TypeIssueMissingJumpArg {
      variant_unique,
      region_id [str],
      label [LalinTree.BlockLabel],
      field. name [str],
    },
    TypeIssueExtraJumpArg {
      variant_unique,
      region_id [str],
      label [LalinTree.BlockLabel],
      field. name [str],
    },
    TypeIssueDuplicateJumpArg {
      variant_unique,
      region_id [str],
      label [LalinTree.BlockLabel],
      field. name [str],
    },
    TypeIssueUnexpectedYield { variant_unique, site [str], },
    TypeIssueInvalidControl {
      variant_unique,
      region_id [str],
      reject [LalinTree.ControlReject],
    },
    TypeIssueRegionInvoke { variant_unique, reject [LalinTree.RegionInvokeReject], },
    TypeIssueUnknownVariant { variant_unique, type_name [str], variant_name [str], },
    TypeIssueVariantBindCount {
      variant_unique,
      type_name [str],
      variant_name [str],
      expected [number],
      actual [number],
    },
    TypeIssueVariantPayloadMismatch {
      variant_unique,
      type_name [str],
      variant_name [str],
      expected [LalinType.Type],
      actual [LalinType.Type],
    },
    TypeIssueDuplicateVariant { variant_unique, type_name [str], variant_name [str], },
    TypeIssueDomainContract {
      variant_unique,
      handle [str],
      domain [str],
      reason [str],
    },
  },
  product. TypeIssueExplanation {
    interned,
    code [str],
    phase_context [str],
    primary [str],
    notes [many [str]],
    suggestions [many [str]],
  },
}