# Lalin Schema v2 — Complete Audit Report

## Audited against `TARGET-SCHEMA.md`, old `lua/lalin/schema/`, and ASDL doctrine.

**Date:** 2026-07-07
**Scope:** All 28 files in `lua/lalin/schema_v2/`

---

## 1. EXECUTIVE SUMMARY

The v2 schema is **~90% faithful** to the target architecture. The three largest wins are:

1. **Phase discipline** — The `LalinTree` → `LalinTree` + `LalinCheck` + `LalinTreeCode` split is airtight. No source-tree type carries later-phase facts.
2. **Duplicate elimination** — `LalinCodeBackend` and `LalinTreeLower` are gone. All 60+ types correctly absorbed into `LalinCode` and `LalinTreeCode`.
3. **MemProof refactoring** — 9 typed guarantee unions replace 9 × `reason [str]`. This is the doctrinal centerpiece.

**Defects found:** 3 high-severity, 4 medium-severity, 8 low-severity in v2. An additional 12 issues are identified in the target specification itself.

All defects are itemised below with concrete ASDL shapes for correction.

---

## 2. MODULE-LEVEL MATRIX

| Module file | Target name | Present? | Matches target? | Notes |
|---|---|---|---|---|
| `core.lua` | LalinCore | ✅ | ✅ | `UnresolvedSymFact` rename done. **Missing `ResolvedSym`** — see §3.1. |
| `parse.lua` | LalinParse | ✅ | ✅ | Two-type module, unchanged. |
| `source.lua` | LalinSource | ✅ | ✅ | `AnchorUnclassified` rename, `SourceRangeFailure` union present. |
| `type.lua` | LalinType | ✅ | ⚠️ | Structure matches but has stringly `AbiParamRejected`, `AbiResultRejected`. Target says "unchanged." See §4.1. |
| `bind.lua` | LalinBind | ✅ | ✅ | Clean. |
| `sem.lua` | LalinSem | ✅ | ⚠️ | `ClosureHelperVariant` fix present. `ConstExprResult` still has stringly `reason [str]` on two leaves. See §4.2. |
| `tree.lua` | LalinTree | ✅ | ✅ | Source nodes only. `SwitchKeyDecision` deleted. `ControlRejectReason`, `RegionInvokeReject` typed. |
| `check.lua` | LalinCheck | ✅ | ✅ | New module. Full typecheck product set present. `SwitchKeyClass` replaces `SwitchKeyDecision`. |
| `tree_code.lua` | LalinTreeCode | ✅ | ✅ | New module. All `TreeCode*` products extracted from old `tree.lua`. |
| `code.lua` | LalinCode | ✅ | ✅ | `CodeInstIntrinsic` split. `RelocFailure`, `CodeUnsupportedContext` typed. `CodeBack*` types canonicalised. |
| `graph.lua` | LalinGraph | ✅ | ✅ | `EdgeKind`, `UseRole` unions. |
| `flow.lua` | LalinFlow | ✅ | ✅ | `FlowProofAuthoritative`, `FlowBoundDerivationKey`, `FlowTripCountReject` typed. |
| `value.lua` | LalinValue | ✅ | ✅ | `AlgebraProof` guarantees typed. |
| `mem.lua` | LalinMem | ✅ | ⚠️ | Major refactoring present. **Extra `MemObjectFieldPointer`** — see §3.2. `MemBaseUnknown`, `MemBoundsUnknown` etc. retain terminal `reason [str]`. |
| `effect.lua` | LalinEffect | ✅ | ⚠️ | `EffectAtomic` fix done. `EffectObjectUnknown`, `EffectUnknown` catch-alls remain. See §4.8. |
| `kernel.lua` | LalinKernel | ✅ | ✅ | Skeleton collapse, equivalence typed, rewrite split, result reject typed. |
| `stencil.lua` | LalinStencil | ✅ | ✅ | Access layout axis split, vectorization facts split, schedule mismatch typed. |
| `stencil_machine.lua` | LalinStencilMachine | ✅ | ⚠️ | 17-boolean → 4-product decomposition correct. **`not_found_minus_one [bool]`** — see §3.3. |
| `lower.lua` | LalinLower | ✅ | ✅ | `LowerIssueGap`, `LowerIssueFallback` typed. `LowerFallbackKind` present. |
| `schedule.lua` | LalinSchedule | ✅ | ⚠️ | `ScheduleEmitterKind` typed. `executable [bool]` remains — see §4.10. |
| `backend.lua` | LalinBackend | ✅ | ⚠️ | `TargetHeuristicReason` present. `BackFeatureUnknown` catch-all, `BackTargetSupportsVectorOp { op_class [str] }` remain. See §4.5. |
| `c.lua` | LalinC | ✅ | ❌ | Target claims "cleanest." **`COpaque`, `CBackendOpaqueDecl` catch-alls.** See §3.4. |
| `cemit.lua` | LalinCEmit | ✅ | ✅ | Clean emission module. |
| `compiler.lua` | LalinCompiler | ✅ | ✅ | Clean. |
| `code_validation.lua` | LalinCodeValidation | ✅ | ✅ | Clean. |
| `exec.lua` | LalinExec | ✅ | ⚠️ | `ExecFragmentTrap`, `ExecStencilDecision` with `reason [str]`. Terminal diagnostics. |
| `phase.lua` | LalinPhase | ✅ | ⚠️ | `capabilities` now typed. **Shadows `TypeRef` name** from `LalinType` — see §4.4. |
| `project.lua` | LalinProject | ✅ | ✅ | Clean. |

---

## 3. HIGH-SEVERITY DEFECTS (v2 implementation errors)

### 3.1 MISSING TYPE: `ResolvedSym` in `LalinCore`

`lua/lalin/schema_v2/core.lua:137` declares in a comment:

> the phase that resolves this fact produces a ResolvedSym instead of mutating the product.

But **`ResolvedSym` does not exist anywhere in the v2 schema**.  The `UnresolvedSymFact` resolution story has no ASDL target type.  The comment is a design intent that was never transcribed into the schema.

**Required addition (in `LalinCore`):**

```lua
-- ResolvedSym: the product of resolving an UnresolvedSymFact.
-- Each leaf carries the role-specific resolution data.
sum. ResolvedSym {
  ResolvedTypeSym    { sym [LalinCore.TypeSym],    ty [LalinType.Type] },
  ResolvedFuncSym    { sym [LalinCore.FuncSym],    func [LalinTree.Func] },
  ResolvedExternSym  { sym [LalinCore.ExternSym],  extern [LalinTree.ExternFunc] },
  ResolvedConstSym   { sym [LalinCore.ConstSym],   value [LalinSem.ConstValue] },
  ResolvedStaticSym  { sym [LalinCore.StaticSym],  value [LalinSem.ConstValue] },
}
```

### 3.2 EXTRA LEAF: `MemObjectFieldPointer` in `MemObjectForm`

`lua/lalin/schema_v2/mem.lua:77` carries `MemObjectFieldPointer` as a leaf between `MemObjectElement` and `MemObjectLease`.  This leaf is **not present in the target's `MemObjectForm`** and was carried over from the old schema.

The target's Derived split explicitly produces four concrete leaves: `MemObjectFieldProjection`, `MemObjectPtrOffset`, `MemObjectBytes`, `MemObjectElement`.  `MemObjectFieldPointer` appears to duplicate or overlap with `MemObjectFieldProjection`.

**Required action:** Either:

1. **Delete** `MemObjectFieldPointer` and absorb its semantics into `MemObjectFieldProjection`, which already carries `{ owner, field, byte_offset }` — sufficient to model a pointer to a field, OR
2. **Define and justify** the semantic difference: if `MemObjectFieldPointer` models "a pointer value that happens to point to a field" while `MemObjectFieldProjection` models "a sub-object created by field projection," the distinction must be made explicit in the target and the invariant stated.

Without justification, the safe correction is:

```lua
-- DELETE:
-- MemObjectFieldPointer,
--
-- MemObjectFieldProjection already models field-addressed sub-objects:
--   MemObjectFieldProjection { owner, field, byte_offset }
```

### 3.3 BOOLEAN PROTOCOL: `not_found_minus_one [bool]`

`lua/lalin/schema_v2/stencil_machine.lua:433` in `StencilMachineFindSelectionFacts`:

```
not_found_minus_one [bool],
```

This is a semantic choice — "what sentinel value means 'not found'" — encoded as a boolean.  The value `-1` is a convention, not a universal fact.  A different convention (e.g., `0xFFFFFFFF` for unsigned, or a user-supplied sentinel) is semantically distinct.

**Required replacement:**

```lua
sum. FindNotFoundSentinel {
  FindNotFoundMinusOne,                                          -- use -1
  FindNotFoundSentinelConst { value [LalinValue.ValueExpr] },    -- user-supplied sentinel
}

-- In StencilMachineFindSelectionFacts, replace:
--   not_found_minus_one [bool],
-- with:
--   not_found [LalinStencilMachine.FindNotFoundSentinel],
```

---

## 4. MEDIUM-SEVERITY DEFECTS

### 4.1 TARGET DEFECT: Stringly `AbiParamRejected` / `AbiResultRejected`

`lua/lalin/schema_v2/type.lua` lines 119, 130:

```lua
AbiParamRejected  { variant_unique, field.name [str], field.ty [LalinType.Type], reason [str] },
AbiResultRejected { variant_unique, field.ty [LalinType.Type], reason [str] },
```

The target says `LalinType` is "kept, unchanged."  But `reason [str]` on a rejected ABI classification is stringly-typed — the rejection reason is a semantic alternative (unsupported type, too large, needs descriptor, etc.), not free text.

**Recommended fix:**

```lua
sum. AbiRejectReason {
  AbiRejectUnsupportedType    { ty [LalinType.Type] },
  AbiRejectTooLarge           { layout [LalinSem.MemLayout], max_size [number] },
  AbiRejectNeedsDescriptor    { layout [LalinSem.MemLayout] },
  AbiRejectInvalidCombination { description [str] },  -- terminal
}

-- AbiParamRejected becomes:
AbiParamRejected {
  variant_unique,
  field.name [str],
  field.ty   [LalinType.Type],
  reject     [LalinType.AbiRejectReason],
},
```

### 4.2 TARGET DEFECT: Stringly `ConstExprResult` leaves

`lua/lalin/schema_v2/sem.lua` lines 74-75:

```lua
ConstNotFoldable { variant_unique, reason [str] },
ConstRejected   { variant_unique, reason [str] },
```

"Not foldable" and "rejected" have structured reasons.  There are specific reasons an expression cannot be folded (side effects, external call, volatile access, etc.).

**Recommended fix:**

```lua
sum. ConstFoldReject {
  ConstFoldSideEffect      { effect_description [str] },
  ConstFoldExternalCall    { callee_name [str] },
  ConstFoldVolatileAccess  { access_description [str] },
  ConstFoldDivergent       { reason_description [str] },
  ConstFoldUnsupportedOp   { op_description [str] },
}

sum. ConstExprResult {
  ConstKnown      { variant_unique, field.value [LalinSem.ConstValue] },
  ConstNotFoldable { variant_unique, reject [LalinSem.ConstFoldReject] },
}
```

(`ConstRejected` and `ConstNotFoldable` are semantically identical — both mean "cannot fold."  Collapse to one leaf with a typed reject.)

### 4.3 TARGET DEFECT: `AbiUnknown` in `AbiClass`

`lua/lalin/schema_v2/type.lua` line 93:

```lua
AbiUnknown { variant_unique, shape [LalinType.TypeShape] },
```

This is a catch-all variant in a 5-leaf union.  The target says catch-all variants should be 0.  If the ABI classification genuinely cannot classify a type shape, that fact should carry a typed reason:

```lua
AbiUnclassifiable {
  variant_unique,
  shape  [LalinType.TypeShape],
  reason [LalinType.AbiRejectReason],
},
```

### 4.4 TARGET DEFECT: `TypeRef` name shadowing in `LalinPhase`

`lua/lalin/schema_v2/phase.lua` lines 11-14 define a `TypeRef` sum with leaves `TypeRef`, `TypeRefAny`, `TypeRefValue`.  This shadows the unrelated `LalinType.TypeRef` (which has `TypeRefPath`, `TypeRefGlobal`, `TypeRefLocal`).  Two different `TypeRef` types with different semantics in the same schema namespace.

**Recommended fix:** Rename `LalinPhase.TypeRef` to `LalinPhase.WorldType`:

```lua
sum. WorldType {
  WorldTypeNamed   { module_name [str], type_name [str] },
  WorldTypeAny,
  WorldTypeValue   { field.name [str] },
}

product. World {
  interned,
  field.id  [LalinPhase.WorldId],
  field.ty  [LalinPhase.WorldType],
},
```

---

## 5. LOW-SEVERITY DEFECTS

### 5.1 Catch-all: `COpaque` in `LalinC`

`lua/lalin/schema_v2/c.lua:14`.  The target calls `LalinC` "the cleanest module in the schema" but `COpaque` is a genuine catch-all C type variant.  If there are specific reasons a C type cannot be classified (incomplete type, forward declaration, system header type), those should be leaves of a typed union.  If `COpaque` truly means "we don't know the shape yet" (a temporary analysis state), it should be renamed to `CTypeUnknown { reason [CTypeUnknownReason] }`.

### 5.2 Catch-all: `CBackendOpaqueDecl` in `LalinC`

`lua/lalin/schema_v2/c.lua:201`. Same issue as above — a catch-all backend declaration variant.

### 5.3 Catch-all: `BackFeatureUnknown` in `LalinBackend`

`lua/lalin/schema_v2/backend.lua` line 44: `BackFeatureUnknown { variant_unique, field.name [str] }`.  The target doesn't mention this.  If genuinely open-ended (new CPU features appear), it's a terminal diagnostic.  If the set of features is closed at build time, it should be exhaustive.

### 5.4 Stringly: `BackTargetSupportsVectorOp { op_class [str] }`

`lua/lalin/schema_v2/backend.lua` line 79.  `op_class` is a string where a union of operation classes belongs:

```lua
sum. BackVectorOpClass {
  BackVecOpArithmetic,
  BackVecOpBitwise,
  BackVecOpShift,
  BackVecOpCompare,
  BackVecOpMask,
  BackVecOpGather,
  BackVecOpScatter,
}
```

### 5.5 Stringly: `BackCommandCount.command_kind [str]`

`lua/lalin/schema_v2/backend.lua:725`.  In an inspection/reporting product.  Low impact, but still stringly.

### 5.6 Boolean protocol: `add_trip_unknown_proof [bool]`

`lua/lalin/schema_v2/kernel.lua:229`.  Present in the target.  This boolean answers "should we add a proof because the trip count is unknown?" — a protocol decision, not a structural fact.  If the closed form is valid regardless, the proof should be `optional [MemProof]`.  If the closed form is only valid with the proof, there should be two alternatives.

### 5.7 Fuzzy boolean: `ScheduleEmitterCapability.executable [bool]`

`lua/lalin/schema_v2/schedule.lua:50`.  Present in the target.  "Executable" is vague — does it mean "backend available," "all proofs satisfied," "target supports it"?  A typed capability union is clearer.

### 5.8 Stringly: `tag [str]` in stencil machine descriptors

`StencilMachineStoreNDescriptor`, `StencilMachineReduceNDescriptor`, `StencilMachineScatterReduceNDescriptor` carry `tag [str]` — human-facing disambiguation labels.  Low impact but should be typed if these tags carry semantic meaning for dispatch or selection.

---

## 6. REMAINING STRINGLY `reason [str]` INVENTORY

The target claims `< 10` remaining `reason [str]` fields after all fixes.  The actual count across v2 is approximately 50.  The discrepancy is explained by the target only counting the specific refactorings it performed (MemProof, RelocFailure, etc.) and not counting terminal diagnostic/reject leaves.

The remaining `reason [str]` fields fall into these categories:

| Category | Count | Legitimate? |
|---|---|---|
| **Terminal diagnostic / reject leaves** (`MemBaseUnknown`, `MemProvUnknown`, `MemBoundsUnknown`, `MemNonTrapping`, `MemCheckedTrap`, `EffectUnknown`, `LowerProof.*`, `LowerEmit*`, `CodeTermTrap`, `CodeTermUnreachable`, `CodeConstUndef`, `StencilReject.*`, `StencilFusionReject.*`, etc.) | ~30 | Generally yes — these are genuinely open-ended or human-facing |
| **Asserted facts / author claims** (`FlowFactAuthorAsserted`, `FlowFactFrontendFact`, `StencilProducerAuthorAsserted`, `StencilProducerFrontendFact`) | ~4 | Yes — these are human-authored assertions |
| **Schedule proof/reject** (`ScheduleProofTarget`, `ScheduleProofProfit`, `ScheduleReject*`) | ~8 | Questionable — could be typed |
| **Exec module decisions** (`ExecStencilDecision`, `ExecFragmentTrap`, `ExecStencilInput.*`) | ~6 | Yes — execution-level terminal decisions |
| **Const expr results** (`ConstNotFoldable`, `ConstRejected`) | ~2 | Should be typed — see §4.2 |
| **ABI rejects** (`AbiParamRejected`, `AbiResultRejected`) | ~2 | Should be typed — see §4.1 |
| **Miscellaneous** (`CodeOriginGenerated`, `SourcePositionMiss`, `SourceOffsetMiss`, `FlowProofDomain`, `FlowProofMemory`, etc.) | ~5 | Mixed — some terminal, some improvable |

**Net assessment:** The target's claim of "< 10" is inaccurate by a factor of 5×, but the majority are in legitimate terminal-diagnostic positions.  The 4 items flagged in §4.1–4.3 above are the material ones that should be typed.

---

## 7. DEFECTS IN THE TARGET SPECIFICATION ITSELF

These are problems in `TARGET-SCHEMA.md` that the v2 implementation faithfully reproduced, and should be corrected in both the target and the schema.

### 7.1 Target omits `ResolvedSym`

The target's `LalinCore` section introduces `UnresolvedSymFact` and says "the phase that has resolved it produces a `ResolvedSym`" — but never defines `ResolvedSym`.  The v2 schema reproduces this omission.  See §3.1 for the correction.

### 7.2 Target omits `MemObjectFieldPointer` from `MemObjectForm`

The target lists 14 leaves for `MemObjectForm` but the old schema has 15.  `MemObjectFieldPointer` is the missing one.  The target should either include it with justification or explicitly mark it for absorption into `MemObjectFieldProjection`.

### 7.3 Target claims `LalinC` is "the cleanest" but has catch-alls

`COpaque` and `CBackendOpaqueDecl` are genuine catch-all variants.  The target's own rule (section 3: "Catch-all/Opaque variants … 0") contradicts this claim.

### 7.4 Target claims `LalinType` is "unchanged" but has stringly ABI rejects

`AbiParamRejected` and `AbiResultRejected` carry `reason [str]`.  The target should have flagged these for typing.

### 7.5 Target claims `LalinSem` has "minor fix" only but misses `ConstExprResult`

`ConstNotFoldable` and `ConstRejected` with `reason [str]` are stringly-typed results that should have been addressed.

### 7.6 Target claims "0" catch-all variants but `BackFeatureUnknown`, `AbiUnknown`, `EffectObjectUnknown`, `EffectUnknown` remain

These are in modules the target says are "kept" or "minor."  The "0" count is aspirational, not actual.

### 7.7 Target claims "< 10 reason [str]" but actual count is ~50

The target only counted the specific `reason [str]` fields it replaced, not the terminal diagnostic ones.  The claim should be revised or qualified.

### 7.8 `add_trip_unknown_proof [bool]` is Boolean Protocol

The target's `KernelLoopPlanClosedForm` carries `add_trip_unknown_proof [bool]` — a protocol decision in a boolean.  The target's boolean elimination claim says "< 5" remaining, but this is one of them and should be acknowledged.

### 7.9 `not_found_minus_one [bool]` is Boolean Protocol

The target's `StencilMachineFindSelectionFacts` carries this boolean.  Same issue — a sentinel convention encoded as a boolean.

### 7.10 `ScheduleEmitterCapability.executable [bool]` is fuzzy

"Executable" conflates multiple semantic axes (backend availability, proof satisfaction, target support).  The target should refine this.

### 7.11 `LalinPhase.TypeRef` shadows `LalinType.TypeRef`

Two unrelated types with the same name in different modules.  See §4.4.

### 7.12 `BackTargetSupportsVectorOp { op_class [str] }` is stringly

The target says `LalinBackend` is "kept, minor" but missed this stringly field.

---

## 8. THE BEST QUALITY TARGET ASDL — CORRECTIONS

Below are the concrete corrections that, applied to the target spec and the v2 schema, would bring this to doctrinal purity.  Only the *changed* declarations are shown.  Unchanged modules (LalinParse, LalinBind, LalinGraph, LalinValue, LalinEffect, LalinLower, LalinCEmit, LalinCompiler, LalinCodeValidation, LalinExec, LalinProject) are omitted — they are already adequate.

### 8.1 LalinCore — add `ResolvedSym`

```lua
-- Add after UnresolvedSymFact:

-- ResolvedSym: produced by the resolution phase.
-- Each leaf carries the role-specific data that was resolved.
sum. ResolvedSym {
  ResolvedTypeSym   { sym [LalinCore.TypeSym],   ty [LalinType.Type] },
  ResolvedFuncSym   { sym [LalinCore.FuncSym],   func [LalinTree.Func] },
  ResolvedExternSym { sym [LalinCore.ExternSym], extern [LalinTree.ExternFunc] },
  ResolvedConstSym  { sym [LalinCore.ConstSym],  value [LalinSem.ConstValue] },
  ResolvedStaticSym { sym [LalinCore.StaticSym], value [LalinSem.ConstValue] },
}
```

### 8.2 LalinType — fix ABI rejects

```lua
-- Add typed reject reason:
sum. AbiRejectReason {
  AbiRejectUnsupportedType    { ty [LalinType.Type] },
  AbiRejectTooLarge           { layout [LalinSem.MemLayout], max_size [number] },
  AbiRejectNeedsDescriptor    { layout [LalinSem.MemLayout] },
  AbiRejectInvalidCombination { description [str] },  -- terminal
}

-- Fix AbiParamPlan:
sum. AbiParamPlan {
  AbiParamScalar   { ... },    -- unchanged
  AbiParamView     { ... },    -- unchanged
  AbiParamRejected {
    variant_unique,
    field.name [str],
    field.ty   [LalinType.Type],
    reject     [LalinType.AbiRejectReason],
  },
}

-- Fix AbiResultPlan:
sum. AbiResultPlan {
  AbiResultVoid,
  AbiResultScalar    { ... },  -- unchanged
  AbiResultView      { ... },  -- unchanged
  AbiResultRejected {
    variant_unique,
    field.ty [LalinType.Type],
    reject   [LalinType.AbiRejectReason],
  },
}

-- Fix AbiClass:
sum. AbiClass {
  AbiIgnore,
  AbiDirect      { ... },  -- unchanged
  AbiIndirect    { ... },  -- unchanged
  AbiDescriptor  { ... },  -- unchanged
  AbiUnclassifiable {
    variant_unique,
    shape  [LalinType.TypeShape],
    reason [LalinType.AbiRejectReason],
  },
}
```

### 8.3 LalinSem — fix ConstExprResult

```lua
sum. ConstFoldReject {
  ConstFoldSideEffect      { effect_description [str] },
  ConstFoldExternalCall    { callee_name [str] },
  ConstFoldVolatileAccess  { access_description [str] },
  ConstFoldDivergent       { reason_description [str] },
  ConstFoldUnsupportedOp   { op_description [str] },
}

-- Replace ConstNotFoldable + ConstRejected with single leaf:
sum. ConstExprResult {
  ConstKnown       { variant_unique, field.value [LalinSem.ConstValue] },
  ConstNotFoldable { variant_unique, reject [LalinSem.ConstFoldReject] },
}
```

### 8.4 LalinMem — delete `MemObjectFieldPointer`

```lua
sum. MemObjectForm {
  MemObjectParam,
  MemObjectLocal,
  MemObjectGlobal,
  MemObjectData,
  MemObjectView,
  MemObjectSlice,
  MemObjectByteSpan,
  MemObjectContract,
  -- Derived split:
  MemObjectFieldProjection { variant_unique, owner [LalinMem.MemObjectId], field [LalinSem.FieldRef], byte_offset [number] },
  MemObjectPtrOffset       { variant_unique, owner [LalinMem.MemObjectId], index_expr [LalinMem.MemIndex], elem_size [number] },
  MemObjectBytes           { variant_unique, owner [LalinMem.MemObjectId], byte_offset [number], byte_length [number] },
  MemObjectElement         { variant_unique, owner [LalinMem.MemObjectId], elem_index [number], elem_size [number] },
  -- DELETE: MemObjectFieldPointer — subsumed by MemObjectFieldProjection
  MemObjectLease,
  MemObjectUnknown { variant_unique, reason [LalinMem.MemObjectUnknownReason] },
}
```

### 8.5 LalinStencilMachine — fix `not_found_minus_one`

```lua
sum. FindNotFoundSentinel {
  FindNotFoundMinusOne,
  FindNotFoundSentinelConst { value [LalinValue.ValueExpr] },
}

-- In StencilMachineFindSelectionFacts:
product. StencilMachineFindSelectionFacts {
  interned,
  producer          [LalinStencil.StencilProducer],
  step_num          [number],
  start             [LalinCode.CodeValueId],
  stop              [LalinCode.CodeValueId],
  start_expr        [LalinLuaJIT.LJExpr],
  stop_expr         [LalinLuaJIT.LJExpr],
  pred              [LalinStencil.StencilPredicate],
  not_found         [LalinStencilMachine.FindNotFoundSentinel],     -- was: not_found_minus_one [bool]
  point_facts       [LalinStencilMachine.StencilMachinePointExprFacts],
}
```

### 8.6 LalinC — fix catch-all variants

```lua
-- COpaque → CTypeTransient with typed reason:
sum. CTypeUnknownReason {
  CTypeIncompleteForwardDecl { type_name [str] },
  CTypeSystemHeaderType      { header [str], type_name [str] },
  CTypeNotYetResolved,
}

sum. CTypeShape {
  CVoid,
  CScalar   { ... },
  CPointer  { ... },
  CEnum     { ... },
  CArray    { ... },
  CStruct,
  CUnion,
  CUnknown  { variant_unique, reason [LalinC.CTypeUnknownReason] },
  CFuncPtr  { ... },
}
```

### 8.7 LalinPhase — rename `TypeRef` to `WorldType`

```lua
sum. WorldType {
  WorldTypeNamed   { module_name [str], type_name [str] },
  WorldTypeAny,
  WorldTypeValue   { field.name [str] },
}

product. World {
  interned,
  field.id  [LalinPhase.WorldId],
  field.ty  [LalinPhase.WorldType],
}
```

### 8.8 LalinBackend — fix `BackTargetSupportsVectorOp`

```lua
sum. BackVectorOpClass {
  BackVecOpArithmetic,
  BackVecOpBitwise,
  BackVecOpShift,
  BackVecOpCompare,
  BackVecOpMask,
  BackVecOpGather,
  BackVecOpScatter,
}

-- Replace:
--   BackTargetSupportsVectorOp { variant_unique, vec [LalinBackend.BackVec], op_class [str] },
-- with:
BackTargetSupportsVectorOp {
  variant_unique,
  vec      [LalinBackend.BackVec],
  op_class [LalinBackend.BackVectorOpClass],
},
```

### 8.9 LalinKernel — fix `add_trip_unknown_proof`

```lua
-- Replace:
--   KernelLoopPlanClosedForm { closed_form, add_trip_unknown_proof [bool] },
-- with:
sum. KernelClosedFormTripProof {
  KernelClosedFormTripCountKnown,
  KernelClosedFormTripCountAssumed { proof_added [LalinMem.MemProof] },
}

KernelLoopPlanClosedForm {
  variant_unique,
  closed_form   [LalinValue.ClosedFormFact],
  trip_proof    [LalinKernel.KernelClosedFormTripProof],
},
```

### 8.10 LalinSchedule — clarify `executable`

```lua
-- Replace:
--   product. ScheduleEmitterCapability { ..., executable [bool], ... }
-- with:
sum. ScheduleEmitterStatus {
  ScheduleEmitterAvailable  { reason [str] },
  ScheduleEmitterUnavailable { reason [str] },
}

product. ScheduleEmitterCapability {
  interned,
  kind     [LalinSchedule.ScheduleEmitterKind],
  status   [LalinSchedule.ScheduleEmitterStatus],
  rejects  [many [LalinSchedule.ScheduleReject]],
}
```

---

## 9. SUMMARY OF ALL DEFECTS

| # | Severity | Category | Location | Description |
|---|----------|----------|----------|-------------|
| 1 | **HIGH** | Missing type | `core.lua` | `ResolvedSym` not declared. Comment promises it. |
| 2 | **HIGH** | Extra leaf | `mem.lua:77` | `MemObjectFieldPointer` not in target — overlap with `MemObjectFieldProjection`. |
| 3 | **HIGH** | Boolean protocol | `stencil_machine.lua:433` | `not_found_minus_one [bool]` — sentinel choice as boolean. |
| 4 | MEDIUM | Stringly (target) | `type.lua:119,130` | `AbiParamRejected`, `AbiResultRejected` carry `reason [str]`. |
| 5 | MEDIUM | Stringly (target) | `sem.lua:74-75` | `ConstNotFoldable`, `ConstRejected` carry `reason [str]`. |
| 6 | MEDIUM | Catch-all (target) | `type.lua:93` | `AbiUnknown` catch-all variant. |
| 7 | MEDIUM | Name shadowing | `phase.lua:11` | `TypeRef` in `LalinPhase` shadows `LalinType.TypeRef`. |
| 8 | LOW | Catch-all | `c.lua:14,201` | `COpaque`, `CBackendOpaqueDecl` catch-all variants. |
| 9 | LOW | Catch-all | `backend.lua:44` | `BackFeatureUnknown` catch-all. |
| 10 | LOW | Stringly (target) | `backend.lua:79` | `BackTargetSupportsVectorOp { op_class [str] }`. |
| 11 | LOW | Stringly | `backend.lua:725` | `BackCommandCount.command_kind [str]`. |
| 12 | LOW | Boolean protocol | `kernel.lua:229` | `add_trip_unknown_proof [bool]`. |
| 13 | LOW | Fuzzy boolean | `schedule.lua:50` | `ScheduleEmitterCapability.executable [bool]`. |
| 14 | LOW | Stringly | `stencil_machine.lua:90,107,193` | `tag [str]` disambiguation labels. |
| 15 | LOW | Target inaccuracy | TARGET-SCHEMA.md | Claims "< 10 reason [str]" — actual count ~50. |
| 16 | LOW | Target inaccuracy | TARGET-SCHEMA.md | Claims LalinC "cleanest" — has catch-alls. |
| 17 | LOW | Target inaccuracy | TARGET-SCHEMA.md | Claims "0 catch-all variants" — has 4+. |
| 18 | LOW | Target omission | TARGET-SCHEMA.md | `MemObjectFieldPointer` not accounted for in `MemObjectForm`. |

---

## 10. NET VERDICT

**The v2 schema passes.**  Every major refactoring mandated by the target is correctly implemented.  The three high-severity defects are concrete, fixable, and localised.  The medium-severity defects are primarily in the target specification itself — the v2 implementation faithfully reproduces what the target specified.

The target specification has 12 identifiable weaknesses (false claims about stringly counts, catch-all elimination, module cleanliness, and several missed typing opportunities).  These should be corrected in the target first, then propagated to the schema.

**The ASDL discipline is holding.**  No handler maps, no side tables, no `kind`-string dispatch, no `classof` branches, no generic context bags, no `map`/`table`/`any` escape hatches, and no ad hoc Lua constructor payloads were found in the v2 schema.  The leaf-method doctrine is respected — union leaves own their behavior through the ASDL type system, not through external dispatch.

The MemProof guarantee cascade (9 unions × 3–4 typed leaves each) is the strongest single piece of evidence that the doctrine is working.  Every memory proof now carries a typed guarantee that localises the meaning.
