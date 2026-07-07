# Lalin Target Schema — Architectural Rebuild

This document describes the complete target ASDL schema after architectural repair.
Every type in the old schema is either kept, replaced, refactored, or deleted — with explicit reasons.

**Schema modules are listed in dependency order.** Each module's target shape is given
in full ASDL notation. Where the target shape differs from the old, the old types are named
and the reason for change is stated.

---

## 0. TOTAL INVENTORY

| Category | Old count | Target count | Delta |
|----------|-----------|-------------|-------|
| Schema modules | 37 | 30 | −7 removed |
| Products | ~400+ | ~290 | −110+ removed/merged |
| Unions | ~180+ | ~140 | −40+ refactored |
| Union leaves | ~700+ | ~550 | −150+ removed/refactored |
| Boolean-in-products | 50+ | 0 | eliminated |
| `reason [str]` fields | 70+ | <10 | stringly→typed |
| Catch-all leaves | 15+ | 0 | eliminated |
| Duplicate type families | 3 pairs | 0 | merged |

**Removed modules:** `LalinCodeBackend` (duplicate), `LalinTreeLower` (duplicate),
native stencil generator types from `LalinNative` (split to own module), 4 speculative
modules are merged.

**Deferred (not redesigned here):** `LalinNative` (3736 lines, experimental, needs
its own focused review), `LalinLuaJIT` (backend-specific), `LalinLuaTrace`
(backend-specific), `LalinHost` (FFI bridge, needs separate review).

---

## 1. LOWERING REVIEW

Before the target schema, the phase boundaries are audited.

### 1.1 Phase pipeline (C path)

```
LalinTree.Module                    ← authored source
  │
  ├─[SurfaceResolve.module]        Tree.Module → Tree.Module (surface-resolved)
  ├─[ClosureConvert.module]        Tree.Module → Tree.Module (closure-converted)
  ├─[Typecheck.check_module]       Tree.Module → Tree.TypeModuleResult
  │    input: Tree.Module + opts{layout_env, target}
  │    output: TypeModuleResult { module:Tree.Module, issues:TypeIssue[] }
  │
  ├─[Layout.module]                Tree.Module → Tree.Module (layout-resolved)
  │
  ├─[TreeToCode.module_with_contracts]
  │    input: Tree.Module + {layout_env, target}
  │    output: (Code.CodeModule, CodeFuncContractFact[])
  │
  ├─[CodeGraph.graph]              CodeModule → Graph.CodeGraph
  ├─[CodeFlowFacts.facts]          (CodeModule,Graph) → Flow.FlowFactSet
  ├─[CodeValueFacts.facts]         (CodeModule,Graph,Flow) → Value.ValueFactSet
  ├─[CodeMemFacts.semantic_facts]  (CodeModule,Graph,Flow,Value,contracts) → Mem.MemSemanticFactSet
  ├─[CodeEffectFacts.facts]        (CodeModule,Graph,Mem,contracts) → Effect.EffectFactSet
  │
  ├─[CodeKernelPlan.plan]          (CodeModule,Graph,Flow,Value,Mem,Effect) → Kernel.KernelModulePlan
  ├─[CodeSchedulePlan.plan]        (CodeModule,Kernels,Flow,Value,Mem,Effect,target) → Schedule.ScheduleModulePlan
  ├─[CodeLowerPlan.plan]           (CodeModule,Graph,Kernels,Schedules,LowerTarget) → Lower.LowerModule
  │
  ├─[LowerToC.module]              (CodeModule,LowerModule) → C.CBackendUnit
  │    └──[CodeToC.module]         (CodeModule) → baseline CBackendUnit
  │    └── lower_semantic_func     applies kernel rewrites to semantic fragments
  │
  ├─[EmitCEmit.emit_artifact]      CBackendUnit → {source,header,support,combined} (text)
  └─[emit_c_compile]               C text → GCC → shared object → dlopen/dlsym
```

### 1.2 What the old schema leaked across phase boundaries

| Old leak | Where | Fix |
|----------|-------|-----|
| `TreeCodeModuleFacts` in `tree.lua` | Code-generation state in source tree module | Move to `LalinCode` as projection |
| `TreeCodeFuncState` in `tree.lua` | Lowering state bag in source tree | Move to `LalinLower` as `CodeLoweringState` |
| `TreeCodeExprResult.ty [CodeType]` | Code types referenced from source tree products | Legitimate — code lowering input carries Code types |
| `TreeTypeModuleFacts` with `layout_env`, `target`, `const_env` | Frontend carries backend facts | Split: frontend produces `CheckedModule`; backend facts are a separate spine |
| `TreeLower*` duplicate of `TreeCode*` | Two lowering paths with identical shapes | Eliminate one path |
| `CodeBackend*` duplicate of `CodeBack*` | Same family with different naming | Eliminate one path |
| `StencilMachineKernelInput` with 17 booleans | All phase facts collapsed into one bag | Decompose into capability/loop/result products |
| `reason [str]` on 70+ leaves | Semantic reject facts as strings | Typed reject leaves |

### 1.3 Lowering target — what each phase genuinely needs

| Phase | Consumes world | Produces world | World change rule |
|-------|---------------|-----------------|-------------------|
| SurfaceResolve | `SourceModule` | `SurfaceResolvedModule` | Changes when any identifier spelling/scope changes |
| ClosureConvert | `SurfaceResolvedModule` | `ClosureConvertedModule` | Changes when any capture set or closure structure changes |
| Typecheck | `ClosureConvertedModule` | `CheckedModule` | Changes when any type assignment or binding resolution changes |
| Layout | `CheckedModule` | `LayoutedModule` | Changes when any type layout (field count/offset/size) changes |
| TreeToCode | `LayoutedModule` | `CodeModule` + contracts | Changes when any typed expression/statement lowering changes or any new binding is introduced |
| Graph | `CodeModule` | `CodeGraph` | Changes when any block/edge/terminator changes |
| FlowFacts | `CodeModule` + `CodeGraph` | `FlowFactSet` | Changes when any loop structure, domain, or induction changes |
| ValueFacts | `CodeModule` + `CodeGraph` + `FlowFactSet` | `ValueFactSet` | Changes when any value expression, reduction, or closed-form derivation changes |
| MemFacts | `CodeModule` + `CodeGraph` + `FlowFactSet` + `ValueFactSet` | `MemSemanticFactSet` | Changes when any memory access pattern, object, dependence, or alias fact changes |
| EffectFacts | `CodeModule` + `CodeGraph` + `MemSemanticFactSet` | `EffectFactSet` | Changes when any call effect or side effect changes |
| KernelPlan | All fact sets | `KernelModulePlan` | Changes when any kernel candidate eligibility changes |
| SchedulePlan | `KernelModulePlan` + all facts + target | `ScheduleModulePlan` | Changes when schedule assignment or target facts change |
| LowerPlan | `CodeModule` + `Graph` + `KernelModulePlan` + `ScheduleModulePlan` | `LowerModule` | Changes when any fragment coverage, carrier plan, or address plan changes |
| LowerToC | `CodeModule` + `LowerModule` | `CBackendUnit` | Changes when any baseline C block, kernel rewrite application, or ABI lowering changes |
| EmitC | `CBackendUnit` | C text strings | Changes when C text formatting, helper insertion, or declaration order changes |

---

## 2. TARGET SCHEMA — MODULE BY MODULE

### 2.1 `LalinCore` (KEPT, minimal changes)

All products and unions are **kept as-is** except:

- `OpenSym` (6-field bag) is **split**: the `SymRole` union already expresses the role.
  The `OpenSym` type is retained but renamed to `UnresolvedSymFact` and carries only
  `role [SymRole], key [str], name [str], symbol [str]` — the phase that has resolved
  it produces a `ResolvedSym { role: leaf-specific variant }`.

**Target:**
```
schema. LalinCore {
  product. Name { interned, text [str] }
  product. Path { interned, parts [many [LalinCore.Name]] }
  product. Id { interned, text [str] }
  product. ModuleId { interned, text [str] }
  product. ItemId { interned, text [str] }
  product. FieldId { interned, text [str] }

  sum. Phase { PhaseSurface, PhaseTyped, PhaseOpen, PhaseSem, PhaseCode }
  sum. Visibility { VisibilityLocal, VisibilityExport }

  sum. Scalar {
    ScalarVoid, ScalarBool,
    ScalarI8, ScalarI16, ScalarI32, ScalarI64,
    ScalarU8, ScalarU16, ScalarU32, ScalarU64,
    ScalarF32, ScalarF64, ScalarRawPtr, ScalarIndex
  }

  sum. ScalarFamily {
    ScalarFamilyVoid, ScalarFamilyBool,
    ScalarFamilySignedInt, ScalarFamilyUnsignedInt,
    ScalarFamilyFloat, ScalarFamilyRawPtr, ScalarFamilyIndex
  }

  product. ScalarBits { interned, bits [number] }
  product. ScalarInfo { interned, family [ScalarFamily], bits [ScalarBits] }

  sum. Literal {
    LitInt { variant_unique, raw [str] }
    LitFloat { variant_unique, raw [str] }
    LitBool { variant_unique, field. value [bool] }
    LitString { variant_unique, bytes [str] }
    LitNil
  }

  sum. UnaryOp { UnaryNeg, UnaryNot, UnaryBitNot }
  sum. BinaryOp {
    BinAdd, BinSub, BinMul, BinDiv, BinRem,
    BinBitAnd, BinBitOr, BinBitXor, BinShl, BinLShr, BinAShr
  }
  sum. CmpOp { CmpEq, CmpNe, CmpLt, CmpLe, CmpGt, CmpGe }
  sum. LogicOp { LogicAnd, LogicOr }

  sum. SurfaceCastOp {
    SurfaceCast, SurfaceTrunc, SurfaceZExt, SurfaceSExt,
    SurfaceBitcast, SurfaceSatCast
  }
  sum. MachineCastOp {
    MachineCastIdentity, MachineCastBitcast,
    MachineCastIreduce, MachineCastSextend, MachineCastUextend,
    MachineCastFpromote, MachineCastFdemote,
    MachineCastSToF, MachineCastUToF, MachineCastFToS, MachineCastFToU
  }

  sum. Intrinsic {
    IntrinsicPopcount, IntrinsicClz, IntrinsicCtz, IntrinsicRotl, IntrinsicRotr,
    IntrinsicBswap, IntrinsicFma, IntrinsicSqrt, IntrinsicAbs,
    IntrinsicFloor, IntrinsicCeil, IntrinsicTruncFloat, IntrinsicRound,
    IntrinsicTrap, IntrinsicAssume
  }

  sum. AtomicOrdering { AtomicSeqCst }
  sum. AtomicRmwOp {
    AtomicRmwAdd, AtomicRmwSub, AtomicRmwAnd, AtomicRmwOr,
    AtomicRmwXor, AtomicRmwXchg
  }

  sum. UnaryOpFamily { UnaryFamilyArithmetic, UnaryFamilyLogical, UnaryFamilyBitwise }
  sum. BinaryOpFamily {
    BinaryFamilyArithmetic, BinaryFamilyDivision, BinaryFamilyRemainder,
    BinaryFamilyBitwise, BinaryFamilyShift
  }
  sum. CmpOpFamily { CmpFamilyEquality, CmpFamilyOrdering }
  sum. IntrinsicFamily {
    IntrinsicFamilyBit, IntrinsicFamilyFloat, IntrinsicFamilyFused, IntrinsicFamilyControl
  }

  product. TypeSym { interned, key [str], field. name [str] }
  product. FuncSym { interned, key [str], field. name [str] }
  product. ExternSym { interned, key [str], field. name [str], symbol [str] }
  product. ConstSym { interned, key [str], field. name [str] }
  product. StaticSym { interned, key [str], field. name [str] }
  product. DataId { interned, text [str] }

  sum. SymRole { SymKindFunc, SymKindExtern, SymKindConst, SymKindStatic, SymKindType }

  product. UnresolvedSymFact {
    interned, role [SymRole], key [str], field. name [str], symbol [str]
  }
}
```

---

### 2.2 `LalinParse` (KEPT, unchanged)

Trivial two-type module. No changes.

---

### 2.3 `LalinSource` (REFACTORED, minor)

- `AnchorOpaque { variant_unique, name [str] }` → `AnchorUnclassified { variant_unique, name [str] }`
  Rename to make clear this is a transient unknown, not a permanent escape hatch.
- `SourceIssueInvalidRange { reason [str] }` → `SourceIssueInvalidRange { field [SourceRange], failure [SourceRangeFailure] }`
  where `SourceRangeFailure` is a union of typed reasons.

**Target (changes only):**
```
sum. AnchorRole {
  AnchorDocument, AnchorLuaOpaque, AnchorKeyword, AnchorScalarType,
  AnchorStructName, AnchorFieldName, AnchorFieldUse,
  AnchorFunctionName, AnchorFunctionUse, AnchorMethodName,
  AnchorParamName, AnchorLocalName, AnchorBindingDef, AnchorBindingUse,
  AnchorRegionName, AnchorExprName, AnchorContinuationName,
  AnchorContinuationUse, AnchorBuiltinName, AnchorPackedAlign,
  AnchorDiagnostic, AnchorExposeName, AnchorModuleName,
  AnchorUnclassified { variant_unique, field. name [str] }
}

sum. SourceRangeFailure {
  SourceRangeOutOfBounds { offset [number] }
  SourceRangeBackwards { start [number], stop [number] }
  SourceRangeTruncated { field. length [number], expected [number] }
}
```

---

### 2.4 `LalinType` (KEPT, unchanged)

Clean. The `Type`/`TypeShape` duplication is deliberate (structural vs. identity-bearing).

---

### 2.5 `LalinTree` (REFACTORED — SPLIT INTO THREE)

**OLD PROBLEMS:**
- `tree.lua` (1496 lines) carries source tree nodes, typecheck products,
  AND Code-generation state machines (`TreeCodeFuncState`, `TreeCodeEmissionState`, etc.)
- `SwitchKeyDecision` is a delayed-control union with stringly `reason [str]`
- `ControlReject` has `ControlRejectIrreducible { reason [str] }` and
  `ControlRejectUnknownVariant { reason [str] }` — stringly typed

**TARGET SPLIT:**

1. **`LalinTree`** — source tree nodes ONLY (Expr, Stmt, Func, Item, Module, Place, View, Region, etc.)
2. **`LalinCheck`** — typecheck input/output products (TypeExprInput, TypeExprResult, etc.)
   and TypeIssue, TypeUnaryIssueReason
3. **`LalinTreeCode`** — tree-to-code lowering state (renamed from TreeCode* to TreeCode*)
   — KEPT but MOVED to its own module

**Source tree nodes — target (key parts only, all existing Expr/Stmt/Func/Item/Module/Place leaves kept):**

Fixes inside `LalinTree`:

- `SwitchKeyDecision` → **DELETED**. This is a typecheck classification. Replaced by
  leaf methods on `Expr` that return a `SwitchKeyClass` typed result.

- `ControlReject` → each leaf gets a typed `ControlRejectReason` union instead of `reason [str]`.

- `RegionInvokeReject.RegionInvokeCallFrameUnsupported` → gains typed payload:
  `RegionInvokeCallFrameUnsupported { target [RegionInvokeTarget], frame_kind [str] }`

**Target (new types in LalinTree):**
```
sum. SwitchKeyClass {
  SwitchConstKeyClass { keys [many [SwitchKey]] }
  SwitchExprKeyClass { keys [many [SwitchKey]] }
  SwitchCompareKeyClass { keys [many [SwitchKey]], comparison [CmpOp] }
}

sum. ControlRejectReason {
  ControlIrreducibleLoop { backedge_blocks [many [BlockLabel]] }
  ControlIrreducibleMultiEntry { header_blocks [many [BlockLabel]] }
  ControlIrreducibleBranch { reason [str] }
    -- terminal: irreducible with no structured reason
}

sum. RegionInvokeReject {
  RegionInvokeMissingTarget { target [RegionInvokeTarget] }
  RegionInvokeArgCount { target [RegionInvokeTarget], expected [number], actual [number] }
  RegionInvokeMissingWire { target [RegionInvokeTarget], cont [RegionCont] }
  RegionInvokeExtraWire { target [RegionInvokeTarget], name [str] }
  RegionInvokeDuplicateWire { target [RegionInvokeTarget], name [str] }
  RegionInvokeCallFrameUnsupported {
    target [RegionInvokeTarget],
    frame_kind [str],
    reason [str]
  }
}
```

**`LalinCheck` — new module (extracted from LalinTree):**

```
schema. LalinCheck {
  -- Typecheck input products
  product. TypeValueScope {
    interned, module_name [str],
    values [many [LalinBind.ValueEntry]],
    types [many [LalinBind.TypeEntry]],
    layouts [many [LalinSem.TypeLayout]],
    facts [LalinTree.TypeModuleFacts]
  }

  product. TypeExprInput { interned, scope [TypeValueScope] }
  product. TypeExpectedExprInput { interned, scope [TypeValueScope], expected [LalinType.Type] }
  product. TypeValueRefInput { interned, scope [TypeValueScope] }
  product. TypePlaceInput { interned, scope [TypeValueScope] }
  product. TypeIndexBaseInput { interned, scope [TypeValueScope] }
  product. TypeViewInput { interned, scope [TypeValueScope] }
  product. TypeStmtInput { interned, scope [TypeValueScope], return_ty [LalinType.Type], yield [TypeYieldResult] }
  product. TypeControlInput { interned, stmt [TypeStmtInput], region_id [str] }
  product. TypeFuncInput { interned, scope [TypeValueScope] }
  product. TypeItemInput { interned, scope [TypeValueScope] }
  product. TypePolicyInput { interned, site [str] }
  product. TypeCanonicalInput { interned, names [TypeNameScope] }
  product. TypeBinaryInput { interned, op [LalinCore.BinaryOp], rhs [LalinType.Type] }
  product. TypeCompareInput { interned, op [LalinCore.CmpOp], rhs [LalinType.Type] }

  -- Typecheck result products/unions
  sum. TypeExprResult {
    TypeExprResult { variant_unique, expr [LalinTree.Expr], ty [LalinType.Type], issues [many [TypeIssue]] }
  }
  sum. TypePlaceResult {
    TypePlaceResult { variant_unique, place [LalinTree.Place], ty [LalinType.Type], issues [many [TypeIssue]] }
  }
  sum. TypeStmtResult {
    TypeStmtResult { variant_unique, state [TypeStmtInput], stmts [many [LalinTree.Stmt]], issues [many [TypeIssue]] }
  }
  sum. TypeFuncResult {
    TypeFuncResult { variant_unique, func [LalinTree.Func], issues [many [TypeIssue]] }
  }
  sum. TypeItemResult {
    TypeItemResult { variant_unique, items [many [LalinTree.Item]], issues [many [TypeIssue]] }
  }
  sum. TypeModuleResult {
    TypeModuleResult { variant_unique, module [LalinTree.Module], issues [many [TypeIssue]] }
  }
  sum. TypeViewResult {
    TypeViewResult { variant_unique, view [LalinTree.View], issues [many [TypeIssue]] }
  }
  sum. TypeIndexBaseResult {
    TypeIndexBaseResult { variant_unique, base [LalinTree.IndexBase], elem [LalinType.Type], issues [many [TypeIssue]] }
  }
  sum. TypeControlStmtRegionResult {
    TypeControlStmtRegionResult { variant_unique, region [LalinTree.ControlStmtRegion], issues [many [TypeIssue]] }
  }
  sum. TypeControlExprRegionResult {
    TypeControlExprRegionResult { variant_unique, region [LalinTree.ControlExprRegion], issues [many [TypeIssue]] }
  }

  product. TypeValueRefResult { interned, ref [LalinBind.ValueRef], ty [LalinType.Type], issues [many [TypeIssue]] }
  product. TypePolicyResult { interned, issues [many [TypeIssue]] }
  product. TypeCanonicalResult { interned, ty [LalinType.Type] }
  product. TypeBinaryResult { interned, ty [LalinType.Type], issues [many [TypeIssue]] }
  product. TypeCompareResult { interned, ty [LalinType.Type], issues [many [TypeIssue]] }
  product. TypeScopeChange { interned, scope [TypeValueScope] }
  product. TypeNameScope { interned, types [many [LalinBind.TypeEntry]] }

  product. TypeYieldResult {
    TypeYieldNone, TypeYieldVoid, TypeYieldValue { variant_unique, ty [LalinType.Type] }
  }

  product. TypeVariantCase {
    interned, name [str], tag [number], payload [LalinType.Type], fields [many [LalinType.FieldDecl]]
  }
  product. TypeVariantDef { interned, type_name [str], ty [LalinType.Type], variants [many [TypeVariantCase]] }
  product. TypeHandleDef {
    interned, name [str], ty [LalinType.Type],
    repr [LalinType.HandleRepr], invalid [LalinType.HandleInvalid],
    domain [optional [LalinType.TypeRef]], target [optional [LalinType.TypeRef]]
  }
  product. TypeFuncEffect {
    interned, name [str], params [many [LalinType.Param]],
    readonly [many [str]], preserve [many [str]], invalidate [many [str]]
  }
  product. TypeModuleFacts {
    interned,
    variants [many [TypeVariantDef]], handles [many [TypeHandleDef]],
    effects [many [TypeFuncEffect]], regions [many [LalinTree.TypeRegionDef]],
    region_protocols [many [LalinTree.RegionProtocol]],
    region_seals [many [LalinTree.RegionSeal]],
    region_bundles [many [LalinTree.RegionBundle]]
  }
  product. TypeModuleFactsInput { interned, module_name [str] }

  -- Type issues — all leaves kept, stringly reasons fixed
  sum. TypeUnaryIssueReason {
    TypeUnaryInvalidOperator { op [str] }
    TypeUnaryLeaseEscapeReturn
    TypeUnaryLeaseEscapeYield
    TypeUnaryLeaseEscapeStore
    TypeUnaryLeaseEscapeCall
    TypeUnaryLeaseInvalidatingCall
    TypeUnaryLeaseEscapeAggregate
    TypeUnaryRegionCallLeasePayload
    TypeUnaryLeaseEscapeDurable
    TypeUnaryOwnedDropped
    TypeUnaryOwnedUseAfterMove
    TypeUnaryOwnedObservedWithoutTransfer
    TypeUnaryOwnedCapturedDurable
    TypeUnaryOwnedBranchMismatch
    TypeUnaryOwnedVarCellUnsupported
    TypeUnaryOwnedRegionCallPayload
    TypeUnaryOwnedEmitTargetMismatch
    TypeUnaryOwnedInvalidComposition
    TypeUnaryHandleCast
    TypeUnaryHandleRepr
    TypeUnaryHandleTargetMismatch
    TypeUnaryHandleDomainMissing
    TypeUnaryHandleDomainAccess
    TypeUnaryHandleLeaseOriginMissing
    TypeUnaryHandleLeaseOriginMismatch
    TypeUnaryAtomicRmwPointerOp
    TypeUnaryAtomicRmwBoolAddSub
    TypeUnaryAtomicInvalidValue { site [str] }
  }

  sum. TypeIssue {
    TypeIssueUnresolvedValue { name [str] }
    TypeIssueUnresolvedPath { path [LalinCore.Path] }
    TypeIssueExpected { site [str], expected [LalinType.Type], actual [LalinType.Type] }
    TypeIssueArgCount { site [str], expected [number], actual [number] }
    TypeIssueNotCallable { ty [LalinType.Type] }
    TypeIssueNotIndexable { ty [LalinType.Type] }
    TypeIssueNotPointer { ty [LalinType.Type] }
    TypeIssueInvalidUnary { reason [TypeUnaryIssueReason], ty [LalinType.Type] }
    TypeIssueInvalidBinary { op [str], lhs [LalinType.Type], rhs [LalinType.Type] }
    TypeIssueInvalidCompare { op [str], lhs [LalinType.Type], rhs [LalinType.Type] }
    TypeIssueInvalidLogic { op [str], lhs [LalinType.Type], rhs [LalinType.Type] }
    TypeIssueMissingJumpTarget { region_id [str], label [LalinTree.BlockLabel] }
    TypeIssueMissingJumpArg { region_id [str], label [LalinTree.BlockLabel], name [str] }
    TypeIssueExtraJumpArg { region_id [str], label [LalinTree.BlockLabel], name [str] }
    TypeIssueDuplicateJumpArg { region_id [str], label [LalinTree.BlockLabel], name [str] }
    TypeIssueUnexpectedYield { site [str] }
    TypeIssueInvalidControl { region_id [str], reject [LalinTree.ControlReject] }
    TypeIssueRegionInvoke { reject [LalinTree.RegionInvokeReject] }
    TypeIssueUnknownVariant { type_name [str], variant_name [str] }
    TypeIssueVariantPayloadMismatch { type_name [str], variant_name [str], expected [LalinType.Type], actual [LalinType.Type] }
    TypeIssueDuplicateVariant { type_name [str], variant_name [str] }
    TypeIssueDomainContract { handle [str], domain [str], reason [str] }
  }

  product. TypeIssueExplanation {
    interned, code [str], phase_context [str], primary [str],
    notes [many [str]], suggestions [many [str]]
  }
}
```

**`LalinTreeCode` — extracted from old LalinTree (moved, not changed):**

All `TreeCode*` products from old `LalinTree` (lines ~1150-1496) move to this module.
This includes `TreeCodeModuleFacts`, `TreeCodeFuncState`, `TreeCodeBindingState`,
`TreeCodeEmissionState`, `TreeCodeExprResult`, etc.

No structural changes in this extraction — just module boundary discipline.
These will be audited separately when the `LalinTreeLower` duplicate is removed.

---

### 2.6 `LalinBind` (KEPT, unchanged)

All types clean.

---

### 2.7 `LalinSem` (KEPT, minor fix)

- `ClosureRewriteInput.helpers [many [LalinTree.Item]]` → `helpers [many [ClosureHelperItem]]`
  where `ClosureHelperItem` is a smaller product (wraps the relevant Item variant fields).

**Target (change only):**
```
product. ClosureHelperItem {
  interned, func_or_extern [ClosureHelperVariant]
}
sum. ClosureHelperVariant {
  ClosureHelperFunc { name [str], params [many [LalinType.Param]], result [LalinType.Type], body [many [LalinTree.Stmt]] }
  ClosureHelperExtern { name [str], symbol [str], params [many [LalinType.Param]], result [LalinType.Type] }
}
```

All other types in `LalinSem` remain unchanged.

---

### 2.8 `LalinCode` (REFACTORED, minor fixes)

**Fixes:**

- `CodeInstIntrinsic.dst [optional [CodeValueId]]` →
  Split into two leaves: `CodeInstIntrinsicVoid { op [Core.Intrinsic], ty [CodeType], args [many [CodeValueId]] }`
  and `CodeInstIntrinsicValue { dst [CodeValueId], op [Core.Intrinsic], ty [CodeType], args [many [CodeValueId]] }`

- `CodeInstCall.dst [optional [CodeValueId]]` →
  Keep `optional` — this is legitimate because void calls and value calls share identical
  semantics in every other field. The optional dst is a local absence, not a semantic branch.
  Callers check `if call.dst then ...` which is mechanical, not architectural.

- `CodeIssueInvalidReloc { reason [str] }` →
  `CodeIssueInvalidReloc { reloc [CodeReloc], failure [RelocFailure] }`
  where `RelocFailure` is a union of typed reasons.

- `CodeIssueUnsupportedSource { reason [str] }` →
  `CodeIssueUnsupportedSource { site [str], context [CodeUnsupportedContext] }`
  where `CodeUnsupportedContext` is a union of typed contexts.

**Target (partial — new types only):**
```
sum. CodeInstOp {
  -- ... all existing leaves kept ...

  CodeInstIntrinsicVoid {
    variant_unique, op [LalinCore.Intrinsic], ty [CodeType], args [many [CodeValueId]]
  }
  CodeInstIntrinsicValue {
    variant_unique, dst [CodeValueId], op [LalinCore.Intrinsic], ty [CodeType], args [many [CodeValueId]]
  }
}

sum. RelocFailure {
  RelocTargetUndefined { target_name [str] }
  RelocAddendOverflow { addend [number], max [number] }
  RelocOffsetOutOfRange { offset [number], section_size [number] }
  RelocUnsupportedTargetKind { target_kind [str] }
}

sum. CodeUnsupportedContext {
  CodeUnsupportedLoopForm { loop_id [str] }
  CodeUnsupportedControlStructure { structure_kind [str] }
  CodeUnsupportedTypeCast { from [CodeType], to [CodeType] }
  CodeUnsupportedAtomicSize { ty [CodeType], size [number] }
  CodeUnsupportedIntrinsic { intrinsic [LalinCore.Intrinsic], reason [str] }
    -- terminal: some intrinsics are genuinely unsupported on certain targets
}
```

All other types in `LalinCode` (CodeModule, CodeFunc, CodeBlock, CodeInst, CodeTerm,
CodeSig, CodeType, CodePlace, CodeIssue) remain unchanged.

---

### 2.9 `LalinGraph` (REFACTORED — stringly→typed)

**Fixes:**
- `GraphEdge.kind [str]` → `kind [EdgeKind]` with a proper union
- `GraphUse.role [str]` → `role [UseRole]` with a proper union

**Target (new types):**
```
sum. EdgeKind {
  EdgeKindBranch           -- conditional branch
  EdgeKindFallthrough      -- unconditional fall-through
  EdgeKindJump             -- explicit jump with args
  EdgeKindReturn           -- return edge (to virtual exit)
  EdgeKindBackedge         -- loop backedge
  EdgeKindRegionExit       -- region continuation exit
}

sum. UseRole {
  UseRoleOperand           -- instruction operand
  UseRoleIndex             -- index into aggregate/array
  UseRoleBase              -- base address for load/store
  UseRoleLen               -- length bound for view/slice
  UseRoleStride            -- stride for view
  UseRoleCondition         -- branch/switch condition
  UseRoleJumpArg           -- jump/phi argument
}
```

---

### 2.10 `LalinFlow` (REFACTORED — stringly→typed)

**Fixes:**
- `FlowProofAuthorAsserted { reason [str] }` + `FlowProofFrontendFact { reason [str] }` →
  Collapse to `FlowProofAuthoritative { source [FlowProofSource], reason [str] }` where
  `FlowProofSource` is a small union.
- `FlowBoundDerived { key [str], deps [...] }` → `key [FlowBoundDerivationKey]` typed union.
- `FlowTripCountUnknown { reason [str] }` → use `FlowTripCountReject` with a typed reject union.

**Target (new types):**
```
sum. FlowProofSource { FlowProofAuthor, FlowProofFrontendPass, FlowProofBackendGuarantee }

sum. FlowProof {
  FlowProofDomain { domain [FlowDomain], reason [str] }
  FlowProofMemory { proof [LalinMem.MemProof], reason [str] }
  FlowProofAuthoritative { source [FlowProofSource], reason [str] }
}

sum. FlowBoundDerivationKey {
  FlowBoundFromTripCount { domain [FlowDomain] }
  FlowBoundFromParam { param_name [str] }
  FlowBoundFromConst { value [LalinCore.Literal] }
  FlowBoundFromBinary { op [LalinCore.BinaryOp], left [CodeValueId], right [CodeValueId] }
}

sum. FlowTripCountReject {
  FlowTripCountNotLoop { subject_description [str] }
  FlowTripCountInductionNotMonotonic { induction_value [LalinCode.CodeValueId] }
  FlowTripCountNonConstantStep { step_value [LalinCode.CodeValueId] }
  FlowTripCountUnboundedRange { start [LalinCode.CodeValueId], stop [LalinCode.CodeValueId] }
  FlowTripCountIrregularExit { exit_block [LalinCode.CodeBlockId] }
}

sum. FlowTripCount {
  FlowTripCountExact { count [LalinCode.CodeValueId], trip_expr [optional [LalinValue.ValueExpr]], proof [optional [LalinMem.MemProof]] }
  FlowTripCountNonNegative { count [LalinCode.CodeValueId], trip_expr [optional [LalinValue.ValueExpr]], proof [optional [LalinMem.MemProof]] }
  FlowTripCountRejected { reject [FlowTripCountReject], trip_expr [optional [LalinValue.ValueExpr]] }
}
```

All other types in `LalinFlow` remain unchanged.

---

### 2.11 `LalinValue` (REFACTORED — minor)

**Fix:** `ValueExprAffine` (pass-through wrapper) → `ValueExprAffine { affine [AffineExpr] }`
is **kept** — it is NOT a pass-through wrapper but a legitimate instantiation of
`AffineExpr` into the `ValueExpr` domain. The `AffineExpr` type carries terms+constant;
`ValueExprAffine` says "this expression is exactly this affine form." The distinction is
the semantic guarantee, not data wrapping. **No change.**

The only change: `AlgebraProof` leaves with bare `reason [str]` → typed.

**Target (new types in LalinValue):**
```
sum. AlgebraProof {
  AlgebraProofFlow { domain [LalinFlow.FlowDomain], guarantee [AlgebraProofFlowGuarantee] }
  AlgebraProofNoWrap { value [LalinCode.CodeValueId], semantics [LalinCode.CodeIntSemantics], guarantee [AlgebraProofNoWrapGuarantee] }
  AlgebraProofIdentity { identity_kind [AlgebraIdentityKind] }
  AlgebraProofReduction { fact [ReductionFact], guarantee [AlgebraProofReductionGuarantee] }
  AlgebraProofComposite { proofs [many [AlgebraProof]], rationale [str] }
}

sum. AlgebraProofFlowGuarantee {
  AlgebraFlowCounted { trip_count [LalinFlow.FlowTripCount] }
  AlgebraFlowMonotonic { direction [LalinFlow.FlowLoopDirection] }
  AlgebraFlowUnrolled { unroll_factor [number] }
}

sum. AlgebraProofNoWrapGuarantee {
  AlgebraNoWrapTypeRange { ty [LalinCode.CodeType] }
  AlgebraNoWrapConstBounds { min [ValueExpr], max [ValueExpr] }
  AlgebraNoWrapNarrowingCast { from [LalinCore.Scalar], to [LalinCore.Scalar] }
}

sum. AlgebraIdentityKind {
  AlgebraIdentityAddZero
  AlgebraIdentityMulOne
  AlgebraIdentityAndAllOnes
  AlgebraIdentityOrZero
  AlgebraIdentityXorZero
}

sum. AlgebraProofReductionGuarantee {
  AlgebraReductionAssociativeProven { op [ReductionOp] }
  AlgebraReductionCommutativeProven { op [ReductionOp] }
  AlgebraReductionFloatReassocAllowed { mode [LalinCode.CodeFloatMode] }
}
```

---

### 2.12 `LalinMem` (REFACTORED — stringly→typed, catch-all elimination)

This is the largest refactor. The memory module has 9 `MemProof` leaves and several
"unknown" catch-all variants.

**Fixes:**
- `MemObjectForm.MemObjectUnknown` → kept (genuine transient unknown at analysis time)
- `MemObjectForm.MemObjectDerived` → split into `MemObjectFieldProjection`, `MemObjectPtrOffset`, `MemObjectBytes`, `MemObjectElement`
- `MemProjectionStep.MemProjectUnknown { reason [str] }` → `MemProjectUnknown { reason [MemProjectionUnknownReason] }`
- `MemObjectExtent.* { reason [str] }` → typed reason leaves
- `MemObjectStride.MemStrideUnknown { reason [str] }` → typed
- `MemProof` leaves with `reason [str]` → typed guarantee unions
- `MemAliasFact` leaves with `reason [str]` → typed

**Target (partial — new and changed types):**
```
sum. MemObjectForm {
  MemObjectParam
  MemObjectLocal
  MemObjectGlobal
  MemObjectData
  MemObjectView
  MemObjectSlice
  MemObjectByteSpan
  MemObjectContract
  MemObjectFieldProjection { owner [MemObjectId], field [LalinSem.FieldRef], byte_offset [number] }
  MemObjectPtrOffset { owner [MemObjectId], index_expr [MemIndex], elem_size [number] }
  MemObjectBytes { owner [MemObjectId], byte_offset [number], byte_length [number] }
  MemObjectElement { owner [MemObjectId], elem_index [number], elem_size [number] }
  MemObjectLease
  MemObjectUnknown { reason [MemObjectUnknownReason] }
}

sum. MemObjectUnknownReason {
  MemObjectUnresolvedPointer { value [LalinCode.CodeValueId] }
  MemObjectIndirectCallReturn { call_site [str] }
  MemObjectExternalBuffer { buffer_name [str] }
  MemObjectOpaqueType { ty [LalinCode.CodeType] }
}

sum. MemProjectionStep {
  MemProjectField
  MemProjectBytes
  MemProjectPtrOffset
  MemProjectViewData
  MemProjectSlice
  MemProjectWindow
  MemProjectElement
  MemProjectUnknown { reason [MemProjectionUnknownReason] }
}

sum. MemProjectionUnknownReason {
  MemProjectOpaqueFieldAccess { field_name [str], owner_ty [LalinCode.CodeType] }
  MemProjectDynamicOffset { base [MemObjectId] }
  MemProjectUntypedCast { from_ty [LalinCode.CodeType], to_ty [LalinCode.CodeType] }
}

sum. MemObjectExtent {
  MemExtentElements { len [LalinCode.CodeValueId], elem_ty [LalinCode.CodeType], guarantee [MemExtentGuarantee] }
  MemExtentBytes { bytes [number], guarantee [MemExtentGuarantee] }
  MemExtentContract { fact [LalinCode.CodeFuncContractFact], guarantee [MemExtentGuarantee] }
  MemExtentUnknown { reason [MemExtentUnknownReason] }
}

sum. MemExtentGuarantee {
  MemExtentByConstruction        -- parameter/global: type defines extent
  MemExtentConstLength           -- length derived from constant
  MemExtentLengthFromParam       -- length from a function parameter
  MemExtentLengthFromContract    -- length guaranteed by contract
  MemExtentAssumedByAuthor { assertion_site [str] }
}

sum. MemExtentUnknownReason {
  MemExtentDynamicAllocation
  MemExtentOpaquePointer { value_name [str] }
  MemExtentCircularDependence
}

sum. MemObjectStride {
  MemStrideUnit
  MemStrideConstElems { elems [number] }
  MemStrideValue { value [LalinCode.CodeValueId] }
  MemStrideUnknown { reason [MemStrideUnknownReason] }
}

sum. MemStrideUnknownReason {
  MemStrideDynamicView { view_value [LalinCode.CodeValueId] }
  MemStrideNonUniformAccess
  MemStrideIndirectionChain
}

sum. MemProof {
  MemProofBounds { guarantee [MemBoundsGuarantee] }
  MemProofAlignment { guarantee [MemAlignGuarantee] }
  MemProofAlias { fact [MemAliasFact], guarantee [MemAliasGuarantee] }
  MemProofNoDependence { accesses [many [MemAccessId]], guarantee [MemDependenceGuarantee] }
  MemProofContract { fact [LalinCode.CodeFuncContractFact], guarantee [MemContractGuarantee] }
  MemProofFlow { loop [LalinGraph.GraphLoopId], guarantee [MemFlowGuarantee] }
  MemProofObject { object [MemObjectId], guarantee [MemObjectGuarantee] }
  MemProofInterval { interval [MemAccessInterval], guarantee [MemIntervalGuarantee] }
  MemProofBackend { access [MemAccessId], guarantee [MemBackendGuarantee] }
}

sum. MemBoundsGuarantee {
  MemBoundsTypeCheck { ty [LalinCode.CodeType], size [number] }
  MemBoundsContractAssert { contract_name [str] }
  MemBoundsLoopRange { loop [LalinGraph.GraphLoopId] }
  MemBoundsConstLength { length [number] }
}

sum. MemAlignGuarantee {
  MemAlignTypeDefined { ty [LalinCode.CodeType], alignment [number] }
  MemAlignAllocationSite { allocation_site [str], alignment [number] }
  MemAlignPlatformRequired { platform [str], alignment [number] }
}

sum. MemAliasGuarantee {
  MemAliasByConstruction { reason_description [str] }
  MemAliasDistinctTypes { a_ty [LalinCode.CodeType], b_ty [LalinCode.CodeType] }
  MemAliasDistinctAllocs { a_site [str], b_site [str] }
  MemAliasRestrictQualified { value_name [str] }
}

sum. MemDependenceGuarantee {
  MemNoDependenceDisjointAccesses { a [MemAccessId], b [MemAccessId] }
  MemNoDependenceReadOnly { access [MemAccessId] }
  MemNoDependenceLoopLevel { loop [LalinGraph.GraphLoopId] }
  MemNoDependenceDistanceProven { distance [number], loop [LalinGraph.GraphLoopId] }
}

sum. MemContractGuarantee {
  MemContractBounds { contract_name [str] }
  MemContractNoAlias { contract_name [str], value_name [str] }
  MemContractReadonly { contract_name [str], value_name [str] }
}

sum. MemFlowGuarantee {
  MemFlowCounted { trip_count [LalinFlow.FlowTripCount] }
  MemFlowMonotonicAddress { induction [LalinFlow.FlowInduction] }
  MemFlowLoopInvariant { value [LalinCode.CodeValueId] }
}

sum. MemObjectGuarantee {
  MemObjectSizeKnown { size [number] }
  MemObjectBaseAddressStable
  MemObjectNotEscaped { scope_description [str] }
}

sum. MemIntervalGuarantee {
  MemIntervalWithinObject { object [MemObjectId] }
  MemIntervalConstLength { length [number] }
  MemIntervalLoopBounded { loop [LalinGraph.GraphLoopId] }
}

sum. MemBackendGuarantee {
  MemBackendNativeAlignment { bytes [number] }
  MemBackendHostEndianness
  MemBackendNoTrapOnAligned { access_description [str] }
}
```

All other types in `LalinMem` remain unchanged.

---

### 2.13 `LalinEffect` (REFACTORED — minor)

**Fix:** `OpEffect.EffectAtomic { ordering [str] }` → `ordering [LalinCore.AtomicOrdering]`

---

### 2.14 `LalinKernel` (REFACTORED — skeleton axis split)

**Fixes:**
- `KernelSkeletonSelection` 4 leaves with identical payload → one product + skeleton kind field
- `KernelEquivalence.KernelEquivalenceRejected { rejects [many [KernelReject]] }` → typed alternatives
- `KernelRewriteNone` → split: `KernelRewriteKeepOriginal` (no rewrite needed) vs.
  `KernelRewriteCouldNotPlan { rejects [many [KernelReject]] }`
- `KernelResultOriginalControl { reason [str] }` → typed reject

**Target (changes only):**
```
sum. KernelSkeletonKind {
  KernelSkeletonKindScan, KernelSkeletonKindCopy,
  KernelSkeletonKindScatterReduce, KernelSkeletonKindFind
}

product. KernelSkeletonSelectionResult {
  interned, kind [KernelSkeletonKind], effects [many [KernelEffect]], result [KernelResult]
}

sum. KernelSkeletonSelection {
  KernelSkeletonSelection { skeleton [KernelSkeletonSelectionResult] }
  KernelSkeletonNoSelection { rejects [many [KernelReject]] }
}

sum. KernelEquivalence {
  KernelEquivalenceProof { proofs [many [KernelProof]] }
  KernelEquivalenceRejected { failures [many [KernelEquivalenceFailure]] }
}

sum. KernelEquivalenceFailure {
  KernelEquivLoopNotCounted { loop [LalinGraph.GraphLoopId] }
  KernelEquivMemoryEffectMismatch { expected [LalinEffect.OpEffect], actual [LalinEffect.OpEffect] }
  KernelEquivValueNotEquivalent { value [LalinCode.CodeValueId], reason_description [str] }
  KernelEquivAliasUnknown { a [LalinMem.MemAccessId], b [LalinMem.MemAccessId] }
}

sum. KernelRewriteKind {
  KernelRewriteClosedForm { expression [LalinValue.ValueExpr], accumulator [optional [KernelExpr]] }
  KernelRewriteMemcpy { dst_base [LalinCode.CodeValueId], src_base [LalinCode.CodeValueId], elem_size [number], semantics [LalinMem.MemDependenceFact] }
  KernelRewriteScan { dst [KernelLane], src [KernelLane], reduction [LalinValue.ReductionFact], mode [LalinStencil.StencilScanMode], trip_count [LalinValue.ValueExpr] }
  KernelRewriteFind { src [KernelLane], predicate [KernelExpr], result_local [LalinCode.CodeValueId], trip_count [LalinValue.ValueExpr] }
  KernelRewriteReduce { reduction [LalinValue.ReductionFact], identity [LalinValue.ValueExpr], result_local [LalinCode.CodeValueId], trip_count [LalinValue.ValueExpr] }
  KernelRewriteKeepOriginal
  KernelRewriteCouldNotPlan { rejects [many [KernelReject]] }
}

sum. KernelResult {
  KernelResultVoid
  KernelResultValue { expr [KernelExpr] }
  KernelResultFind { src [KernelExpr], pred [LalinStencil.StencilPredicate], not_found [LalinValue.ValueExpr] }
  KernelResultAll { src [KernelExpr], pred [LalinStencil.StencilPredicate], success_block [LalinCode.CodeBlockId], failure_block [LalinCode.CodeBlockId] }
  KernelResultAllCompare { left [KernelExpr], right [KernelExpr], cmp [LalinCore.CmpOp], success_block [LalinCode.CodeBlockId], failure_block [LalinCode.CodeBlockId] }
  KernelResultAny { src [KernelExpr], pred [LalinStencil.StencilPredicate], success_block [LalinCode.CodeBlockId], failure_block [LalinCode.CodeBlockId] }
  KernelResultReduction { reduction [LalinValue.ReductionFact] }
  KernelResultClosedForm { closed_form [LalinValue.ClosedFormFact] }
  KernelResultOriginalControl { reject [KernelResultOriginalControlReject] }
}

sum. KernelResultOriginalControlReject {
  KernelOriginalNoCountedLoop
  KernelOriginalNonReducibleCFG { reason [str] }
  KernelOriginalUnsupportedMemoryPattern { access [LalinMem.MemAccessId] }
  KernelOriginalNoAlgebraicForm { value [LalinCode.CodeValueId] }
}
```

---

### 2.15 `LalinStencil` (REFACTORED — axis split, facts bag repair)

**Fixes:**
- `StencilAccessLayout` 12-leaf union → split into two unions:
  `StencilAccessLayoutBase` (6 leaves: Scalar, Contiguous, Indexed, Affine1D, AffineND, FieldProjection, SoAComponent)
  and `StencilAccessDescriptor` (4 leaves: SliceDescriptor, ByteSpanDescriptor, ViewDescriptor)
  plus a wrapper product `StencilAccessLayout { base [StencilAccessLayoutBase], descriptor [optional [StencilAccessDescriptor]] }`.
  This is because "what kind of memory layout do I have" and "am I accessing through a descriptor"
  are orthogonal axes.

- `StencilVectorizationFacts` → split into `StencilAccessFacts` + `StencilAliasFacts` + `StencilTripCountFact` + `StencilArithmeticFacts` — four independent fact products, not one bag.

- `StencilScheduleRejectRequestedRealizedMismatch { reason [str] }` → typed mismatch.

**Target (partial):**
```
sum. StencilAccessLayoutBase {
  StencilLayoutScalar { value [optional [LalinValue.ValueExpr]] }
  StencilLayoutContiguous { stride [number] }
  StencilLayoutIndexed { parent [StencilAccessLayoutBase], index [StencilAccessRef], index_ty [LalinCode.CodeType], stride [number] }
  StencilLayoutAffine1D { parent [StencilAccessLayoutBase], scale [number], offset [optional [LalinValue.ValueExpr]] }
  StencilLayoutAffineND { parent [StencilAccessLayoutBase], terms [many [StencilAffineAxisTerm]], offset [optional [LalinValue.ValueExpr]] }
  StencilLayoutFieldProjection { parent [StencilAccessLayoutBase], record_ty [LalinCode.CodeType], field_name [str], field_offset [number] }
  StencilLayoutSoAComponent { parent [StencilAccessLayoutBase], record_ty [LalinCode.CodeType], field_name [str], component_index [number] }
}

sum. StencilAccessDescriptor {
  StencilLayoutSliceDescriptor { slice [LalinCode.CodeValueId], data [LalinCode.CodeValueId], len [LalinCode.CodeValueId] }
  StencilLayoutByteSpanDescriptor { span [LalinCode.CodeValueId], data [LalinCode.CodeValueId], len [LalinCode.CodeValueId] }
  StencilLayoutViewDescriptor { view [LalinCode.CodeValueId], data [LalinCode.CodeValueId], len [LalinCode.CodeValueId], stride [LalinCode.CodeValueId], stride_const [optional [number]] }
  StencilLayoutForeignBuffer { buffer_name [str], data [LalinCode.CodeValueId], len [LalinCode.CodeValueId] }
}

product. StencilAccessLayout {
  interned, base [StencilAccessLayoutBase], descriptor [optional [StencilAccessDescriptor]]
}

product. StencilAccessFacts {
  interned, facts [many [StencilAccessVectorFact]]
}
product. StencilAliasFacts {
  interned, facts [many [StencilAccessAliasFact]]
}
product. StencilArithmeticFacts {
  interned, reduction_reassociable [bool], int_semantics [optional [LalinCode.CodeIntSemantics]], float_mode [optional [LalinCode.CodeFloatMode]]
}
product. StencilTripCountFactSet {
  interned, trip_count [StencilTripCountFact]
}
```

---

### 2.16 `LalinStencilMachine` (REFACTORED — the Boolean Apocalypse)

**This is the worst module in the old schema.** `StencilMachineKernelInput` has 17 booleans,
and `StencilMachineReduceSelectionFacts`/`StencilMachineStorePlanInput`/`StencilMachineReducePlanInput`
have 5-6 more booleans each. The `-- Transitional` comment in the old schema is an admission.

**Target decomposition:**

The 17 booleans encode these semantic axes:
1. **Provider availability** (has_reduce_provider, has_store_provider, has_skeleton_provider)
2. **Loop classification** (loop_plan, owns_loop, counted_positive, single_store)
3. **Result shape** (returns_void, returns_reduction, result_reduction)
4. **Readiness gates** (stencil_reduce_ready, stencil_store_ready, stencil_skeleton_ready, store_dst_base)

**Target:**
```
-- Capability: what providers are available
sum. StencilMachineProviderCapability {
  StencilMachineCapReduce
  StencilMachineCapStore
  StencilMachineCapSkeleton
  StencilMachineCapNone { reason [StencilMachineUnavailableReason] }
}

sum. StencilMachineUnavailableReason {
  StencilMachineNoReduceProvider { kernel_description [str] }
  StencilMachineNoStoreProvider { kernel_description [str] }
  StencilMachineNoSkeletonProvider { kernel_description [str] }
  StencilMachineUncountedLoop { loop [LalinGraph.GraphLoopId] }
  StencilMachineNonPositiveCounter { induction [LalinFlow.FlowInduction] }
}

product. StencilMachineProviderSet {
  interned, capabilities [many [StencilMachineProviderCapability]]
}

-- Loop classification: what kind of loop is this?
sum. StencilMachineLoopKind {
  StencilMachineLoopCountedPositive { trip_count [LalinFlow.FlowTripCount] }
  StencilMachineLoopMaybeEmpty { trip_count [optional [LalinFlow.FlowTripCount]] }
  StencilMachineLoopUncounted { loop [LalinGraph.GraphLoopId], reason [str] }
  StencilMachineNoLoop
}

-- Result shape: what does this kernel produce?
sum. StencilMachineResultShape {
  StencilMachineResultVoid
  StencilMachineResultReduction { reduction [LalinValue.ReductionFact] }
  StencilMachineResultStoreValue { dst_base_present [bool], store_single [bool] }
    -- NOTE: dst_base_present and store_single remain booleans because they are
    -- shape characteristics of the store itself, not semantic alternatives.
    -- They answer "does the result store to a user-supplied base pointer?"
    -- and "is there exactly one store?", which are simple structural facts.
}

-- Replacement for StencilMachineKernelInput:
product. StencilMachineKernelInput {
  interned,
  providers [StencilMachineProviderSet],
  loop_kind [StencilMachineLoopKind],
  result_shape [StencilMachineResultShape],
  planned [StencilMachinePlanReadiness],
  reject [optional [StencilMachineKernelReject]]
}

-- Plan readiness: is this kernel ready for stencil planning?
sum. StencilMachinePlanReadiness {
  StencilMachineReadyForReduce
  StencilMachineReadyForStore
  StencilMachineReadyForSkeleton
  StencilMachineNotReady { missing_providers [many [StencilMachineProviderCapability]], missing_facts [many [str]] }
}

sum. StencilMachineKernelReject {
  StencilMachineRejectNoProviders
  StencilMachineRejectEmptyBody
  StencilMachineRejectExternalCall { call [LalinEffect.CallSummary] }
  StencilMachineRejectVolatileAccess { access [LalinMem.MemAccessId] }
  StencilMachineRejectAtomicAccess { access [LalinMem.MemAccessId] }
  StencilMachineRejectUnknownEffect { effect [LalinEffect.OpEffect] }
}

-- Kernel selection result:
sum. StencilMachineKernelSelection {
  StencilMachineKernelReduce
  StencilMachineKernelStore
  StencilMachineKernelSkeleton
  StencilMachineKernelNoPlan { rejects [many [StencilMachineKernelReject]] }
}

-- Reduce selection facts (was full of booleans):
sum. StencilMachineReduceSemantics {
  StencilMachineReduceScalar
  StencilMachineReduceAdditive { init_zero [bool] }
    -- NOTE: init_zero stays boolean: "is the initial accumulator zero?"
    -- This is a simple structural fact, not a semantic branch.
  StencilMachineReduceI32Result
}

product. StencilMachineReduceSelectionFacts {
  interned,
  producer [LalinStencil.StencilProducer],
  step_num [number],
  result_ty [LalinCode.CodeType],
  init [LalinValue.ValueExpr],
  init_expr [LalinLuaJIT.LJExpr],
  start [LalinCode.CodeValueId],
  stop [LalinCode.CodeValueId],
  start_expr [LalinLuaJIT.LJExpr],
  stop_expr [LalinLuaJIT.LJExpr],
  reduction_op [LalinValue.ReductionOp],
  semantics [StencilMachineReduceSemantics],
  point_facts [StencilMachinePointExprFacts]
}

product. StencilMachineStoreSelectionFacts {
  interned,
  producer [LalinStencil.StencilProducer],
  step_num [number],
  dst_elem_ty [LalinCode.CodeType],
  dst [LalinCode.CodeValueId],
  dst_expr [LalinLuaJIT.LJExpr],
  dst_layout [optional [LalinStencil.StencilAccessLayout]],
  start [LalinCode.CodeValueId],
  stop [LalinCode.CodeValueId],
  start_expr [LalinLuaJIT.LJExpr],
  stop_expr [LalinLuaJIT.LJExpr],
  store_index_primary [bool],
  store_index_lane [optional [StencilMachineIndexLane]],
  scatter_conflicts [LalinStencil.StencilScatterConflictSemantics],
  copy_semantics [optional [LalinStencil.StencilCopySemantics]],
  point_facts [StencilMachinePointExprFacts]
}
```

---

### 2.17 `LalinLower` (REFACTORED — minor stringly fixes)

**Fixes:**
- `LowerIssueGap { reason [str] }` → `LowerIssueGap { func [LalinCode.CodeFuncId], uncovered_blocks [many [LalinCode.CodeBlockId]] }`
- `LowerIssueFallback { reason [str] }` → `LowerIssueFallback { cover [LowerCover], fallback_kind [LowerFallbackKind] }`

**Target (new types):**
```
sum. LowerFallbackKind {
  LowerFallbackNoKernel { reason_description [str] }
  LowerFallbackUnschedulable { reason_description [str] }
  LowerFallbackComplexControlFlow { blocks [many [LalinCode.CodeBlockId]] }
  LowerFallbackExternalCall { call_site [str] }
}
```

---

### 2.18 `LalinBackend` (KEPT, minor)

- `BackTargetPrefersUnroll.rank [number]` → add `reason [TargetHeuristicReason]`:
```
sum. TargetHeuristicReason {
  TargetHeuristicLoopSize { instruction_count [number] }
  TargetHeuristicCachePressure { estimated_bytes [number] }
  TargetHeuristicVectorizationBenefit { lanes [number] }
  TargetHeuristicUserOverride
}
```

---

### 2.19 `LalinC` (KEPT, unchanged)

The cleanest module in the schema.

---

### 2.20 `LalinSchedule` (REFACTORED — stringly→typed)

**Fix:** `ScheduleEmitterCapability.kind [str]` → `kind [ScheduleEmitterKind]`

**Target:**
```
sum. ScheduleEmitterKind {
  ScheduleEmitterScalar
  ScheduleEmitterVector { feature [LalinStencil.StencilVectorFeatureRequirement] }
  ScheduleEmitterClosedForm
  ScheduleEmitterFallback { reason [EmitterFallbackReason] }
}

sum. EmitterFallbackReason {
  EmitterFallbackUnsupportedType { ty [LalinCode.CodeType] }
  EmitterFallbackUnsupportedOp { op_description [str] }
  EmitterFallbackTargetMissing { feature [LalinStencil.StencilVectorFeatureRequirement] }
}
```

---

### 2.21 `LalinExec`, `LalinCEmit`, `LalinCompiler`, `LalinCodeValidation` (KEPT)

All clean or minor, no structural changes needed beyond those already described.

---

### 2.22 `LalinPhase` (KEPT but INTEGRATED)

- `Machine.capabilities [many [str]]` → `capabilities [many [LalinSchedule.ScheduleEmitterKind]]`
  Now it references the typed emitter kind union.

---

### 2.23 `LalinProject` (KEPT, unchanged)

Minor task-management types. No changes.

---

## 3. TYPES REMOVED ENTIRELY (DEAD/FLUFFY/DUPLICATE)

| Old type | Module | Reason for removal |
|----------|--------|--------------------|
| `LalinCodeBackend.CodeBackendSigAbi` | code_backend.lua | Duplicate of `LalinCode.CodeBackSigAbi`. Both defined same shape but one in `code.lua` and one in separate module. |
| `LalinCodeBackend.CodeBackendLocalSlot` | code_backend.lua | Duplicate of `LalinCode.CodeBackLocalSlot` |
| `LalinCodeBackend.CodeBackendReadonlyProjection` | code_backend.lua | Duplicate of `LalinCode.CodeBackReadonlyProjection` |
| `LalinCodeBackend.CodeReadonlyByInstEntry` | code_backend.lua | Duplicate of `LalinCode.CodeReadonlyByInstEntry` |
| `LalinCodeBackend.CodeSigByIdEntry` | code_backend.lua | Duplicate of `LalinCode.CodeSigByIdEntry` |
| `LalinCodeBackend.CodeSigAbiBySigEntry` | code_backend.lua | Duplicate of `LalinCode.CodeSigAbiBySigEntry` |
| `LalinCodeBackend.CodeMemBackendByInstEntry` | code_backend.lua | Duplicate of `LalinCode.CodeMemBackendByInstEntry` |
| `LalinCodeBackend.CodeEffectByInstEntry` | code_backend.lua | Duplicate of `LalinCode.CodeEffectByInstEntry` |
| `LalinCodeBackend.CodeBackendModuleMachine` | code_backend.lua | Duplicate of `LalinCode.CodeBackModuleFacts` (structurally identical, different name) |
| `LalinCodeBackend.CodeTypeByValueEntry` | code_backend.lua | Duplicate of `LalinCode.CodeTypeByValueEntry` |
| `LalinCodeBackend.CodeParamsByBlockEntry` | code_backend.lua | Duplicate of `LalinCode.CodeParamsByBlockEntry` |
| `LalinCodeBackend.CodeBackendFunctionFacts` | code_backend.lua | Duplicate of `LalinCode.CodeBackFunctionFacts` |
| `LalinCodeBackend.CodeLocalAddrByValueEntry` | code_backend.lua | Duplicate of `LalinCode.CodeLocalAddrByValueEntry` |
| `LalinCodeBackend.CodeValueAddrByValueEntry` | code_backend.lua | Duplicate of `LalinCode.CodeValueAddrByValueEntry` |
| `LalinCodeBackend.CodeValueSizeByValueEntry` | code_backend.lua | Duplicate of `LalinCode.CodeValueSizeByValueEntry` |
| `LalinCodeBackend.CodeBackendAggregateState` | code_backend.lua | Duplicate of `LalinCode.CodeBackAggregateState` |
| `LalinCodeBackend.CodeCaptureByValueEntry` | code_backend.lua | Duplicate of `LalinCode.CodeCaptureByValueEntry` |
| `LalinCodeBackend.CodeBackendClosureState` | code_backend.lua | Duplicate of `LalinCode.CodeBackClosureState` |
| `LalinCodeBackend.CodeSlotByLocalEntry` | code_backend.lua | Duplicate of `LalinCode.CodeSlotByLocalEntry` |
| `LalinCodeBackend.CodeBackendLocalSlotState` | code_backend.lua | Duplicate of `LalinCode.CodeBackLocalSlotState` |
| `LalinCodeBackend.CodeBackendTempState` | code_backend.lua | Duplicate of `LalinCode.CodeBackTempState` |
| `LalinCodeBackend.CodeBackendFunctionState` | code_backend.lua | Duplicate of `LalinCode.CodeBackFunctionState` |
| `LalinCodeBackend.CodeBackendInstInput` | code_backend.lua | Duplicate of `LalinCode.CodeBackInstInput` |
| `LalinCodeBackend.CodeBackendTermInput` | code_backend.lua | Duplicate of `LalinCode.CodeBackTermInput` |
| `LalinCodeBackend.CodeBackendPlaceInput` | code_backend.lua | Duplicate of `LalinCode.CodeBackPlaceInput` |
| `LalinCodeBackend.CodeBackendStateResult` | code_backend.lua | Duplicate of `LalinCode.CodeBackStateResult` |
| `LalinCodeBackend.CodeBackendValueResult` | code_backend.lua | Duplicate of `LalinCode.CodeBackValueResult` |
| `LalinCodeBackend.CodeBackendAddressResult` | code_backend.lua | Duplicate of `LalinCode.CodeBackAddressResult` |
| `LalinCodeBackend.CodeBackendMemoryInfoResult` | code_backend.lua | Duplicate of `LalinCode.CodeBackMemoryInfoResult` |
| `LalinCodeBackend.CodeBackendPlaceResult` | code_backend.lua | Duplicate of `LalinCode.CodeBackPlaceResult` |
| `LalinTreeLower.*` (entire module) | tree_lower.lua | Full duplicate of `TreeCode*` family in `tree.lua`. Same 34 products, slightly different names. |
| `SwitchKeyDecision` union | tree.lua | Delayed control — replaced by leaf methods on Expr returning `SwitchKeyClass` |
| `KernelSkeletonSelection` (4 identical leaves) | kernel.lua | Axis mixing — replaced by `KernelSkeletonKind` field + single product |
| `StencilMachineKernelInput` (17 booleans) | stencil_machine.lua | Boolean soup — decomposed into capability/loop/result products |
| `TreeCodeModuleFacts` (phase pollution) | tree.lua | Code-gen types in source module — moved to `LalinTreeCode` |
| `TreeCodeFuncState` (state bag) | tree.lua | Lowering state in source module — moved to `LalinTreeCode` |
| ~30 `reason [str]` fields on reject/unknown leaves | various | All replaced with typed reason unions |

---

## 4. SUMMARY TABLE — OLD → TARGET

| Old type | Old module | Target type | Target module | Reason |
|----------|-----------|-------------|---------------|--------|
| `OpenSym` (6-field bag) | Core | `UnresolvedSymFact` | Core | Renamed, tightened: explicit "this is unresolved" |
| `AnchorOpaque` | Source | `AnchorUnclassified` | Source | Renamed: not a permanent escape hatch |
| `SourceIssueInvalidRange { reason [str] }` | Source | `SourceIssueInvalidRange { field, failure [SourceRangeFailure] }` | Source | Stringly → typed |
| `SwitchKeyDecision` (union) | Tree | `SwitchKeyClass` (product, returned by leaf method) | Tree | Delayed control → ASDL result from leaf method |
| `ControlRejectIrreducible { reason [str] }` | Tree | `ControlRejectIrreducible { reason [ControlRejectReason] }` | Tree | Stringly → typed |
| `ControlRejectUnknownVariant { reason [str] }` | Tree | Typed leaves in `ControlRejectReason` | Tree | Stringly → typed |
| `RegionInvokeCallFrameUnsupported` (nullary) | Tree | Gains `{ target, frame_kind, reason }` payload | Tree | Nullary reject → typed reject |
| `TypeModuleResult`, `TypeExprResult`, etc. | Tree | Same types, moved | **LalinCheck** (new) | Module boundary: source tree vs. typecheck |
| `TypeIssue`, `TypeUnaryIssueReason` | Tree | Same types, moved | **LalinCheck** (new) | Phase discipline |
| `TypeModuleFacts` | Tree | Same, moved + cleaned | **LalinCheck** (new) | Phase discipline |
| `TreeCodeModuleFacts` | Tree | Same, moved | **LalinTreeCode** (new) | Phase discipline: codegen types in codegen module |
| `TreeCodeFuncState` | Tree | Same, moved | **LalinTreeCode** (new) | Phase discipline |
| `TreeCodeExprResult`, etc. | Tree | Same, moved | **LalinTreeCode** (new) | Phase discipline |
| `CodeInstIntrinsic { dst [optional] }` | Code | `CodeInstIntrinsicVoid` + `CodeInstIntrinsicValue` | Code | Optional soup → two leaves |
| `CodeIssueInvalidReloc { reason [str] }` | Code | `CodeIssueInvalidReloc { reloc, failure [RelocFailure] }` | Code | Stringly → typed |
| `CodeIssueUnsupportedSource { reason [str] }` | Code | `CodeIssueUnsupportedSource { site, context [CodeUnsupportedContext] }` | Code | Stringly → typed |
| `GraphEdge.kind [str]` | Graph | `kind [EdgeKind]` | Graph | Stringly → typed union |
| `GraphUse.role [str]` | Graph | `role [UseRole]` | Graph | Stringly → typed union |
| `FlowProofAuthorAsserted { reason [str] }` | Flow | `FlowProofAuthoritative { source [FlowProofSource], reason [str] }` | Flow | Two identical leaves merged |
| `FlowProofFrontendFact { reason [str] }` | Flow | (merged into above) | Flow | Duplicate leaf — merged |
| `FlowBoundDerived { key [str] }` | Flow | `key [FlowBoundDerivationKey]` | Flow | Stringly → typed |
| `FlowTripCountUnknown { reason [str] }` | Flow | `FlowTripCountRejected { reject [FlowTripCountReject] }` | Flow | Stringly → typed |
| `AlgebraProof.* { reason [str] }` (3 leaves) | Value | Each gets a typed `guarantee` field | Value | Stringly → typed |
| `MemObjectForm.MemObjectDerived` | Mem | Split into 4 concrete leaves | Mem | Catch-all → typed |
| `MemProjectionStep.MemProjectUnknown { reason [str] }` | Mem | `reason [MemProjectionUnknownReason]` | Mem | Stringly → typed |
| `MemObjectExtent.* { reason [str] }` (3 leaves) | Mem | Each gets a typed `guarantee` field | Mem | Stringly → typed |
| `MemObjectStride.MemStrideUnknown { reason [str] }` | Mem | `reason [MemStrideUnknownReason]` | Mem | Stringly → typed |
| `MemProof.* { reason [str] }` (9 leaves) | Mem | Each gets a typed `guarantee` union | Mem | Stringly → typed (largest single fix) |
| `MemAliasFact.* { reason [str] }` (4 leaves) | Mem | Each gets a typed `guarantee` union | Mem | Stringly → typed |
| `OpEffect.EffectAtomic { ordering [str] }` | Effect | `ordering [LalinCore.AtomicOrdering]` | Effect | Stringly → typed |
| `KernelSkeletonSelection` (4 identical leaves) | Kernel | `KernelSkeletonSelection` (single leaf + kind field) | Kernel | Axis mixing → split |
| `KernelEquivalenceRejected { rejects ... }` | Kernel | `{ failures [many [KernelEquivalenceFailure]] }` | Kernel | Stringly → typed failures |
| `KernelRewriteNone` | Kernel | `KernelRewriteKeepOriginal` + `KernelRewriteCouldNotPlan` | Kernel | Ambiguous nullary → two alternatives |
| `KernelResultOriginalControl { reason [str] }` | Kernel | `{ reject [KernelResultOriginalControlReject] }` | Kernel | Stringly → typed |
| `StencilAccessLayout` (12 leaves, fused axes) | Stencil | Split into `StencilAccessLayoutBase` + `StencilAccessDescriptor` + wrapper | Stencil | Fused axes → orthogonal axes |
| `StencilVectorizationFacts` (bag, 5 sub-products) | Stencil | Split into 4 independent products | Stencil | Bag → facets |
| `StencilScheduleRejectRequestedRealizedMismatch { reason [str] }` | Stencil | Typed mismatch union | Stencil | Stringly → typed |
| `StencilMachineKernelInput` (17 booleans) | StencilMachine | `StencilMachineKernelInput` (providers + loop_kind + result_shape + readiness) | StencilMachine | Boolean soup → capability/loop/result products |
| `StencilMachineReduceSelectionFacts.reduction_add [bool]` | StencilMachine | `semantics [StencilMachineReduceSemantics]` | StencilMachine | Boolean → typed alternative |
| `StencilMachineReducePlanInput` (5 booleans) | StencilMachine | Cleaned: essential fields + selection | StencilMachine | Deleted redundant boolean gate fields |
| `StencilMachineStorePlanInput` (6 booleans) | StencilMachine | Cleaned: essential fields + selection | StencilMachine | Deleted redundant boolean gate fields |
| `LowerIssueGap { reason [str] }` | Lower | `LowerIssueGap { func, uncovered_blocks }` | Lower | Stringly → structured |
| `LowerIssueFallback { reason [str] }` | Lower | `LowerIssueFallback { cover, fallback_kind [LowerFallbackKind] }` | Lower | Stringly → typed |
| `BackTargetPrefersUnroll.rank [number]` | Backend | Add `reason [TargetHeuristicReason]` | Backend | Magic number → typed heuristic |
| `ScheduleEmitterCapability.kind [str]` | Schedule | `kind [ScheduleEmitterKind]` | Schedule | Stringly → typed |
| `Machine.capabilities [many [str]]` | Phase | `capabilities [many [ScheduleEmitterKind]]` | Phase | Stringly → typed |
| All 29 types in `LalinCodeBackend` | code_backend.lua | DELETED — use `LalinCode.CodeBack*` family | LalinCode | Duplicate module |
| All 34 types in `LalinTreeLower` | tree_lower.lua | DELETED — use `LalinTree.TreeCode*` family | LalinTreeCode | Duplicate module |

---

## 5. NET EFFECT

### Module count: 37 → 30

| Removed | Reason |
|---------|--------|
| `code_backend.lua` (160 lines) | Duplicate of CodeBack* in code.lua |
| `tree_lower.lua` (341 lines) | Duplicate of TreeCode* in tree.lua |
| 5 speculative modules merged/absorbed | |

### New modules

| New | Grown from |
|-----|-----------|
| `LalinCheck` | Extracted from `LalinTree` (typecheck input/output products) |
| `LalinTreeCode` | Extracted from `LalinTree` (code generation state) |

### Quality improvements

| Metric | Before | After |
|--------|--------|-------|
| Booleans in product fields | 50+ | < 5 (structural only) |
| `reason [str]` fields | 70+ | < 10 (terminal diagnostics only) |
| Catch-all/Opaque variants | 15+ | 0 |
| Duplicate type families | 3 pairs | 0 (merged) |
| Fused-axis unions | 3 | 0 (split into orthogonal axes) |
| Bag products | 10+ | 0 (all split into facets) |
| Stringly-typed kind/tag fields | 6 | 0 (all unionized) |
| Optional dst in instruction ops | 2 | 0 (split into void/value leaves) |

---

## 6. DEFERRED MODULES

These modules need focused architectural reviews but are deferred from this document:

1. **`LalinNative`** (3736 lines) — The experimental native copy-patch backend. Its schema
   is enormous but marked as experimental in AGENTS.md. Needs its own focused review
   once the main pipeline is stable.

2. **`LalinLuaJIT`** (651 lines) — Backend-specific LuaJIT emission types. Well-typed but
   has `LJRegisterRep` with conditional optional fields (`optional [LalinCode.CodeType]`).
   Deferred pending LuaJIT path review.

3. **`LalinLuaTrace`** (215 lines) — LuaTrace access plan with many optional/boolean fields
   in `LTAccessPlanEntry` (10+). Needs similar treatment to `StencilMachineKernelInput`.

4. **`LalinHost`** (233 lines) — FFI bridge schema. Has `HostFieldAttr` with stringly
   `HostFieldAttrOpaque { name [str] }`. Deferred.

5. **`LalinLink`** (138 lines) — Clean linker schema. `LinkRuntimePath` is a proper union.
   No changes needed.

6. **`LalinCMat`** (132 lines) — Clean fusion kernel materialization schema. Uses
   proper unions for vector policy and loop order. No changes needed.

---
# YOUR TASK — Code IR & Analysis Facts (6 modules + 1 removed)

## Goal
Port the middle layer of the ASDL schema — the Code IR and all analysis fact modules — into `lua/lalin/schema_v2/`. This is a full port plus the largest stringly→typed refactor (Mem module, 9 MemProof leaves).

## Target subfolder
`lua/lalin/schema_v2/`

## Modules to port (6 modules + 1 removed)

| # | New module | Old source to read | Changes |
|---|-----------|-------------------|---------|
| 1 | `code.lua` | `lua/lalin/schema/code.lua` | Minor: `CodeInstIntrinsic` optional dst → two leaves (CodeInstIntrinsicVoid + CodeInstIntrinsicValue), `CodeIssueInvalidReloc` stringly→`RelocFailure` union, `CodeIssueUnsupportedSource` stringly→`CodeUnsupportedContext` union |
| 2 | `graph.lua` | `lua/lalin/schema/graph.lua` | Stringly→typed: `EdgeKind` union, `UseRole` union |
| 3 | `flow.lua` | `lua/lalin/schema/flow.lua` | Stringly→typed: `FlowProofSource`, `FlowBoundDerivationKey`, `FlowTripCountReject`. Merge `FlowProofAuthorAsserted` + `FlowProofFrontendFact` → `FlowProofAuthoritative` |
| 4 | `value.lua` | `lua/lalin/schema/value.lua` | Minor: `AlgebraProof` leaves get typed guarantee unions instead of `reason [str]` |
| 5 | `mem.lua` | `lua/lalin/schema/mem.lua` | **LARGEST REFACTOR**: `MemObjectForm.MemObjectDerived` → split into 4 concrete leaves. `MemProjectionStep.MemProjectUnknown` → typed reason. `MemObjectExtent` leaves → typed guarantee. `MemObjectStride` → typed reason. All 9 `MemProof` leaves → typed guarantee unions. All 4 `MemAliasFact` leaves → typed guarantee. See target doc sections for full shapes. |
| 6 | `effect.lua` | `lua/lalin/schema/effect.lua` | Minor: `OpEffect.EffectAtomic { ordering [str] }` → `ordering [LalinCore.AtomicOrdering]` |
| — | **REMOVED** | `lua/lalin/schema/code_backend.lua` | **Do not port.** All 29 types are duplicates of `LalinCode.CodeBack*` family. Just skip this file entirely. |

## Files you MUST read before writing anything

```
lua/lalin/schema/code.lua          — full read
lua/lalin/schema/code_backend.lua  — read to confirm duplicates, then SKIP
lua/lalin/schema/graph.lua         — full read
lua/lalin/schema/flow.lua          — full read
lua/lalin/schema/value.lua         — full read
lua/lalin/schema/mem.lua           — FULL read (largest schema file, most changes)
lua/lalin/schema/effect.lua        — full read
/tmp/lalin-target-schema.md        — sections 2.8 through 2.13 for target shapes
/tmp/plan-a-foundation.md          — know what Plan A produces (module names you'll reference)
```

## Specific target shapes

### code.lua
- `CodeInstIntrinsicVoid { variant_unique, op [LalinCore.Intrinsic], ty [CodeType], args [many [CodeValueId]] }` replaces optional dst
- `CodeInstIntrinsicValue { variant_unique, dst [CodeValueId], op [LalinCore.Intrinsic], ty [CodeType], args [many [CodeValueId]] }`
- `CodeInstCall.dst [optional [CodeValueId]]` → **KEPT** (legitimate: void calls and value calls share identical semantics otherwise)
- New: `RelocFailure` union — `RelocTargetUndefined`, `RelocAddendOverflow`, `RelocOffsetOutOfRange`, `RelocUnsupportedTargetKind`
- New: `CodeUnsupportedContext` union — `CodeUnsupportedLoopForm`, `CodeUnsupportedControlStructure`, `CodeUnsupportedTypeCast`, `CodeUnsupportedAtomicSize`, `CodeUnsupportedIntrinsic`
- Everything else (CodeModule, CodeFunc, CodeBlock, CodeInst, CodeTerm, CodeSig, CodeType, CodePlace, CodeIssue): port as-is

### graph.lua
- New: `EdgeKind` union — `EdgeKindBranch`, `EdgeKindFallthrough`, `EdgeKindJump`, `EdgeKindReturn`, `EdgeKindBackedge`, `EdgeKindRegionExit`
- New: `UseRole` union — `UseRoleOperand`, `UseRoleIndex`, `UseRoleBase`, `UseRoleLen`, `UseRoleStride`, `UseRoleCondition`, `UseRoleJumpArg`
- `GraphEdge.kind` → `kind [EdgeKind]`
- `GraphUse.role` → `role [UseRole]`
- Everything else: port as-is

### flow.lua
- New: `FlowProofSource` union — `FlowProofAuthor`, `FlowProofFrontendPass`, `FlowProofBackendGuarantee`
- `FlowProofAuthorAsserted` + `FlowProofFrontendFact` → merged into `FlowProofAuthoritative { source [FlowProofSource], reason [str] }`
- New: `FlowBoundDerivationKey` union — `FlowBoundFromTripCount`, `FlowBoundFromParam`, `FlowBoundFromConst`, `FlowBoundFromBinary`
- `FlowBoundDerived.key` → `key [FlowBoundDerivationKey]`
- New: `FlowTripCountReject` union — `FlowTripCountNotLoop`, `FlowTripCountInductionNotMonotonic`, `FlowTripCountNonConstantStep`, `FlowTripCountUnboundedRange`, `FlowTripCountIrregularExit`
- `FlowTripCountUnknown { reason [str] }` → `FlowTripCountRejected { reject [FlowTripCountReject], trip_expr [optional [ValueExpr]] }`
- Everything else: port as-is

### value.lua
- `AlgebraProof` leaves: each gets a typed `guarantee` field instead of bare `reason [str]`
  - `AlgebraProofFlow` → `{ guarantee [AlgebraProofFlowGuarantee] }`
  - `AlgebraProofNoWrap` → `{ guarantee [AlgebraProofNoWrapGuarantee] }`
  - `AlgebraProofIdentity` → `{ identity_kind [AlgebraIdentityKind] }`
  - `AlgebraProofReduction` → `{ guarantee [AlgebraProofReductionGuarantee] }`
  - `AlgebraProofComposite` → `{ rationale [str] }` (terminal)
- New unions: `AlgebraProofFlowGuarantee`, `AlgebraProofNoWrapGuarantee`, `AlgebraIdentityKind`, `AlgebraProofReductionGuarantee`
- See target doc section 2.11 for full shapes
- `ValueExprAffine` → **KEPT** (it IS a semantic guarantee, not a pass-through)
- Everything else: port as-is

### mem.lua — THE BIG ONE
- `MemObjectForm.MemObjectDerived` → **DELETED**, replaced by 4 concrete leaves:
  - `MemObjectFieldProjection { owner, field, byte_offset }`
  - `MemObjectPtrOffset { owner, index_expr, elem_size }`
  - `MemObjectBytes { owner, byte_offset, byte_length }`
  - `MemObjectElement { owner, elem_index, elem_size }`
- `MemObjectForm.MemObjectUnknown` → stays, but gains `reason [MemObjectUnknownReason]`
- New: `MemObjectUnknownReason` union
- `MemProjectionStep.MemProjectUnknown` → gains `reason [MemProjectionUnknownReason]`
- New: `MemProjectionUnknownReason` union
- `MemObjectExtent` leaves: each gets a typed `guarantee [MemExtentGuarantee]`
- New: `MemExtentGuarantee` union, `MemExtentUnknownReason` union
- `MemObjectStride.MemStrideUnknown` → gains `reason [MemStrideUnknownReason]`
- New: `MemStrideUnknownReason` union
- **All 9 MemProof leaves**: each gets a typed `guarantee` union
  - `MemProofBounds` → `guarantee [MemBoundsGuarantee]`
  - `MemProofAlignment` → `guarantee [MemAlignGuarantee]`
  - `MemProofAlias` → `guarantee [MemAliasGuarantee]`
  - etc.
- New guarantee unions: `MemBoundsGuarantee`, `MemAlignGuarantee`, `MemAliasGuarantee`, `MemDependenceGuarantee`, `MemContractGuarantee`, `MemFlowGuarantee`, `MemObjectGuarantee`, `MemIntervalGuarantee`, `MemBackendGuarantee`
- `MemAliasFact` (4 leaves): each gets a typed `guarantee` union
- See target doc section 2.12 for FULL shapes — this is the largest set of new types

### effect.lua
- `OpEffect.EffectAtomic` → `ordering [LalinCore.AtomicOrdering]` instead of `ordering [str]`
- Everything else: port as-is

## REMOVED
- **`code_backend.lua`** — DO NOT PORT. All 29 types are duplicates. If any code references them, it should use the `LalinCode.CodeBack*` equivalents.

## Dependencies
References Plan A modules: `LalinCore.*`, `LalinCode.*` (internal), `LalinGraph.*` (internal), etc.
Does NOT depend on Plan C modules.

## Success criteria
- 6 new files in `lua/lalin/schema_v2/`
- No `reason [str]` on MemProof, MemObjectExtent, MemObjectStride, MemAliasFact leaves
- No MemObjectDerived catch-all
- No code_backend.lua exists
- EdgeKind + UseRole are typed unions, not strings
- FlowTripCountReject is a typed union, not a bare string
