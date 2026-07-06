# Workflow 
Deep architecture design for C backend — gather all facts about current schema, lowering, and emission layers
**Workflow ID**: wf-c-backend-deep-arch
**Started**: 2026-07-06 20:38:06
---

## Scout Output — 2026-07-06 20:40:23

I have gathered thorough coverage of all six schema files and the key lowering/emission files. Let me produce the comprehensive report now.

---

## Files Retrieved

### Schema Files

1. **`/home/cedric/dev/lalin/lua/lalin/schema/c.lua`** (full file, ~500 lines) — The complete LalinC ASDL vocabulary: C types, backend IR (Unit, Func, Block, Stmt, Terminator, Place, Atom, RValue), helpers, ABI layering, validation, exec sites.

2. **`/home/cedric/dev/lalin/lua/lalin/schema/lower.lua`** (full file, ~180 lines) — LowerStrategy, LowerFragment, LowerCarrierPlan, LowerAddressPlan, LowerFuncPlan, LowerModule, and all decision/selection union types.

3. **`/home/cedric/dev/lalin/lua/lalin/schema/schedule.lua`** (full file, ~90 lines) — KernelSchedule, ScheduleForm, LaneShape, TailPlan, ScheduleProof, ScheduleReject.

4. **`/home/cedric/dev/lalin/lua/lalin/schema/flow.lua`** (full file, ~230 lines) — FlowTripCount, FlowInduction, FlowCarrierThread, FlowAddressThread, FlowLoopFacts, FlowLoopSemanticFact, FlowDomainShape.

5. **`/home/cedric/dev/lalin/lua/lalin/schema/mem.lua`** (full file, ~280 lines) — MemBackendAccessInfo, MemProof, MemAccessFact, MemAlignment, MemBounds, MemDependenceFact, MemObjectFact.

6. **`/home/cedric/dev/lalin/lua/lalin/schema/kernel.lua`** (full file, ~240 lines) — KernelPlan, KernelBody, KernelResult, KernelEffect, KernelEquivalence, KernelLoopCandidate, skeleton selections.

7. **`/home/cedric/dev/lalin/lua/lalin/schema/emit_c.lua`** (full file, ~55 lines) — CEmitMachine, CEmitHelper, CEmitModuleResult — thin schema, mainly a pass-through to CBackendUnit.

### Lowering/Emission Files

8. **`/home/cedric/dev/lalin/lua/lalin/lower_to_c.lua`** (lines 1-2199) — The central lower-to-C module. Contains `bind_context`, `loop_partition`, `emit_scalar_kernel_fragment`, `emit_closed_form_fragment`, `prepare_func_emission`, `apply_lower_c_carriers`, `lower_emit_candidate`, `select_lower_emit`, `module()` entry point.

9. **`/home/cedric/dev/lalin/lua/lalin/code_kernel_plan.lua`** (lines 1-1626) — Kernel planning: `lanes_for_accesses`, `build_kernel_body`, skeleton inference (`infer_scan_skeleton`, `infer_copy_skeleton`, `infer_scatter_reduce_skeleton`, `infer_find_skeleton`, `infer_all_skeleton`, `infer_partition_skeleton`), `function_plans`, kernel module entry point `plan()`.

10. **`/home/cedric/dev/lalin/lua/lalin/emit_c_lower.lua`** (lines 1-1284) — C text emission engine: type formatting, atom/place/rvalue emission, optimizer passes (copy propagation, dead-store elimination, field hoisting, transfer equivalence), helper body generation.

---

## Key Code — Exhaustive Type Catalog

### CBackend Schema (`c.lua`)

**C Type System:**
- `CTypeId` — interning key for named types
- `CTypeShape` (sum): CVoid, CScalar, CPointer, CEnum, CArray, CStruct, CUnion, COpaque, CFuncPtr
- `CTypeFact` — resolved type with optional size/align
- `CFieldLayout` — per-field layout info
- `CLayoutFact` — aggregate layout fact
- `CFuncSigId`, `CFuncSig`, `CExternFunc`, `CLibrary`

**Backend Names:** `CBackendName`, `CBackendLabel`, `CBackendLocalId`, `CBackendGlobalId`, `CBackendHelperId`, `CBackendFuncSigId`

**Backend Target Configuration:**
- `CBackendDialect` (sum): CBackendC99, CBackendC11, CBackendGnuC, CBackendClangC
- `CBackendPlatform` (sum): CBackendHostedNative, CBackendFreestanding, CBackendWasmCapable, CBackendEmbedded
- `CBackendEndian` (sum): CBackendLittleEndian, CBackendBigEndian
- `CBackendTarget` — aggregates dialect, platform, pointer_bits, index_bits, endian, hosted

**Backend Type System (CBackendType sum, comprehensive):**
- CBackendVoid, CBackendBool8, CBackendScalar, CBackendIndex
- CBackendDataPtr (single-level pointer, optional pointee)
- CBackendQualifiedDataPtr (const/restrict/volatile pointee)
- CBackendCodePtr, CBackendNamed, CBackendArray
- CBackendSliceDescriptor, CBackendByteSpanDescriptor, CBackendViewDescriptor
- CBackendClosureDescriptor (sig + optional ctx)
- CBackendAbiHiddenOutPtr, CBackendImportedCodePtr
- CBackendVector (elem, lanes)

**ABI Layering:**
- `CBackendFuncLinkage` (sum): Internal, Export, Extern, Decl, Wrapper, Indirect
- `CBackendAbiParamRole`, `CBackendAbiResultRole` — parameter/result lowering roles
- `CBackendAbiParam`, `CBackendAbiResult`, `CBackendFuncAbi` — full ABI description
- `CBackendParam`, `CBackendFuncSig`, `CBackendField`
- `CBackendTypeDecl` (sum): Typedef, StructDecl, UnionDecl, OpaqueDecl

**Memory Model:**
- `CBackendResidence` (sum): Value, Addressed, Aggregate, Descriptor
- `CBackendLocalInitState` (sum): Uninitialized, ZeroInitialized, Initialized

**Backend Places (CBackendPlace sum):**
- CBackendPlaceLocal, CBackendPlaceGlobal
- CBackendPlaceDeref (addr + ty + optional align)
- CBackendPlaceField (base + field + offset + size + optional align)
- CBackendPlaceIndex (base-place + index-atom + elem_size)
- CBackendPlacePtrIndex (base-atom + index-atom + elem_size)
- CBackendPlaceBytes (base-atom + offset + size + align)

**Backend IR — Atoms & RValues:**
- `CBackendAtom` (sum): Local, Global, Literal(ty + literal), Null(ty)
- `CBackendRValue` (sum): RAtom, RCompare, RCast, RSelect, RFuncAddr, RExternAddr, RPtrOffset(base+index+elem_size+const_offset), RAddrOfPlace
- `CBackendRelocTarget`, `CBackendDataInit` (sum: Zero, Bytes, Scalar, Reloc)
- `CBackendGlobal`, `CBackendExtern`

**Statements (CBackendStmt sum):**
- CBackendAssign(dst, rhs), CBackendHelperCall(dst?, helper, args)
- CBackendLoad(dst, addr, access), CBackendStore(addr, value, access)
- CBackendPlaceLoad(dst, place), CBackendPlaceStore(place, value)
- CBackendZeroInit(place, ty, size)
- CBackendAggregateInit(place, ty, fields), CBackendArrayInit(place, ty, elems)
- CBackendCall(dst?, target, args), CBackendComment(text)

**Call Targets:** CBackendCallDirect, CBackendCallExtern, CBackendCallIndirect(callee+sig), CBackendCallClosure(closure+sig)

**Terminators (CBackendTerminator sum):**
- CBackendGoto(dest, args), CBackendIfGoto(cond, then_dest, then_args, else_dest, else_args)
- CBackendSwitchGoto(value, cases, default_dest, default_args), CBackendSwitchCase(literal, dest, args)
- CBackendReturnVoid, CBackendReturn(value), CBackendTrap

**Block Structure:**
- `CBackendBlockParam(local_id, ty)`, `CBackendBlock(label, params, stmts, term)`

**Exec Sites:**
- `CBackendExecArg(name, atom, ty)`
- `CBackendExecResult` (sum): Void, Local(dst, ty)
- `CBackendExecEmission` (sum): Inline, Function, ExternCall
- `CBackendExecSite(fragment, emission, args, result)`

**Function Bodies (CBackendFuncBody sum):**
- CBackendBodyBlocks(entry, blocks)
- CBackendBodyExec(fragment) — exec-only body
- CBackendBodyMixed(entry, blocks, fragments) — blocks + exec sites

**Unit & Validation:**
- `CBackendUnit(module_name, target, sigs, types, globals, externs, helpers, funcs)`
- Extensive `CBackendValidationIssue` sum (~25 variants)
- `CBackendStorageRecord`, `CBackendValidationInput`, `CBackendValidationReport`

**Notable Gaps:**
- No loop construct in the CBackend IR — loops are lowered to CFG with Goto/IfGoto
- No alignment annotation on most Place variants beyond CBackendPlaceDeref and CBackendPlaceField
- No branch probability / __builtin_expect annotations
- No inline pragma / `__attribute__((always_inline))` annotations
- No packed/alignment attribute on struct fields beyond `CBackendField.align`
- No CBackendVectorLoad/CBackendVectorStore — vector ops only exist as scalar Place loads indexed by lane
- No restrict qualifier on params in the CBackend schema (only on QualifiedDataPtr types)
- StructDecl/UnionDecl have `size` and `align` but these come from `CTypeFact`, not from explicit user pragmas

**Helper Specs (CBackendHelperSpec sum, 22 variants):**
- Unary, BoolNormalize, Cast, PtrOffset
- IntBinary(with overflow mode), FloatBinary, DivRem, Shift
- Intrinsic, Load, Store, AtomicLoad, AtomicStore, AtomicRmw, AtomicCas, AtomicFence
- Memcpy, TypedMemcpy, Memset, TypedMemset, Memcmp
- LayoutAssert, RequireFeature, Trap

**Policy Types:**
- `CBackendTrapPolicy`, `CBackendMemoryAccess` (ty, align, trap, volatile, ordering)
- `CBackendIntOverflow` (Wrap, TrapOnOverflow, AssumeNoOverflow)
- `CBackendDivPolicy`, `CBackendShiftPolicy`
- `CBackendTargetFeature` (8 features: C11Atomics, Libm, BuiltinOverflow, BuiltinBitops, UnalignedAccess, StaticAssert, HostedRuntime)

---

### Lower Schema (`lower.lua`)

**Core Types:**
- `LowerFragmentId`, `LowerTarget` (Back, C)
- `LowerCover` (sum): Function, Loop, Block, BlockRange
- `LowerStrategy` (sum): Code, Kernel(kernel+schedule), ClosedForm(kernel+ClosedFormFact)
- `LowerProof` (sum): Coverage, Kernel, Schedule, Fallback
- `LowerIssue` (sum): Overlap, Gap, Fallback

**Fragment Candidates (LowerFragmentCandidate sum):**
- ClosedFormCandidate, ClosedFormMissing, KernelCandidate(kernel+schedule), NoSchedule, KernelRejected, NoCandidate

**Fragment Selection (LowerFragmentSelection sum):**
- SelectClosedForm, SelectKernel, SelectFallback, SelectNone

**Emit Candidates (LowerEmitCandidate sum):**
- CodeCandidate, ClosedFormCandidate, KernelCandidate(schedule), MissingScheduleCandidate, UnsupportedCandidate

**Emit Selection (LowerEmitSelection sum):**
- EmitCode, EmitClosedForm, EmitScalarKernel, EmitVectorKernel, EmitMissingSchedule, EmitUnsupported

**Carrier & Address Lowering:**
- `LowerCarrierStrategy` (sum): Carry, Reject
- `LowerCarrierBlockParam`, `LowerCarrierEdgeSource` (sum: Recompute, CarrySame, CarryConst, CarryDynamic)
- `LowerCarrierEdgeTransfer`, `LowerCarrierPlan`
- `LowerAddressLaneUse`, `LowerAddressInstUse`
- `LowerAddressStrategy` (sum): CarryProjected, Reject
- `LowerAddressBlockParam`, `LowerAddressEdgeSource` (sum: RecomputeFromCarrier, CarrySame, CarryConstBytes, CarryDynamicBytes)
- `LowerAddressEdgeTransfer`, `LowerAddressPlan`

**Module-level:**
- `LowerFragment(id, cover, strategy, proofs, issues)`
- `LowerFuncPlan(func, fragments)`
- `LowerModule(module, target, kernels, schedules, carriers, addresses, funcs, issues)`
- `LowerBackSpine`, `LowerBackEmitInput`, `LowerCEmitInput`

**Observations:** `LowerEmitSelection` captures the fidelity cliff: `EmitScalarKernel` and `EmitVectorKernel` both exist, but `LowerEmitVectorKernel:emit_to_c` currently delegates to `emit_scalar_kernel_fragment` (fidelity loss).

---

### Schedule Schema (`schedule.lua`)

- `ScheduleId`, `ScheduleTarget`
- `LaneShape` (sum): Scalar, Vector(elem_ty, lanes)
- `TailPlan` (sum): None, Scalar, Masked, Peel(elems)
- `ScheduleForm` (sum): ScalarIndex, ScalarPointer, Vector(lanes, unroll, interleave, tail), ClosedForm
- `ScheduleProof` (sum): Target, Memory(proof), Algebra(proof), Profit
- `ScheduleReject` (sum): Target, Memory, Algebra, Profit
- `ScheduleEmitterCapability` — per-schedule-form capability
- `SchedulePlanInput` — vector/scalar form + capabilities
- `SchedulePlanSelection` (sum): NoPlan, Planned
- `KernelSchedule` (sum): NoPlan(kernel, rejects), Planned(id, kernel, form, proofs, rejected_alternatives)
- `ScheduleModulePlan`

**Observations:** The schedule system has `ScheduleVector` with `unroll`, `interleave`, `tail` fields — rich vectorization policy — but `lower_to_c.lua` note at line ~1650: "Vector scheduling is now a CMat policy, not a separate direct KernelEffect emitter."

---

### Flow Schema (`flow.lua`)

**Domain & Trip Count:**
- `FlowDomainId`, `FlowDomain` (sum): Loop, BlockRange, Function
- `FlowDomainOrder` (sum): Forward, Backward
- `FlowDomainAxis`, `FlowDomainShape` (sum: Range1D, RangeND, WindowND, TiledND)
- `FlowTripCount` (sum): Exact(count+proof), NonNegative(count+proof), Unknown(reason) — **THIS IS THE FIDELITY CLIFF POINT**
- `FlowCountedDomain` — start, stop, step, stop_exclusive

**Induction:**
- `FlowLoopDirection` (sum): Increasing, Decreasing, Unknown
- `FlowInductionRole` (sum): PrimaryInduction, DerivedInduction(base), PointerInduction(base, elem_size)
- `FlowInduction(value, ty, init, step, role, range)`
- `FlowValueRange` (sum): Unknown, Exact, Unsigned, Signed, Derived

**Carrier Thread (how induction propagates):**
- `FlowCarrierId`, `FlowCarrierStep` (sum): Same, Const, Dynamic, Recompute
- `FlowCarrierTransfer`, `FlowCarrierThread` — maps how an index value propagates through edges
- `FlowAddressId`, `FlowAddressBase(base, elem_ty, elem_size)`
- `FlowAddressUse`, `FlowAddressThread` — maps address projections through loops

**Loop Facts:**
- `FlowLoopExit`, `FlowLoopFacts(loop, domain, counted, body_blocks, inductions, exits, rejects)`
- `FlowInductionRangeFact`
- `FlowLoopSemanticFact` (sum): NormalizedCounted, InductionRange, InductionNoWrap
- `FlowSemanticFactSet`, `FlowFactSet`

**Proof/Reject:**
- `FlowProof` (sum): Domain, Memory, AuthorAsserted, FrontendFact
- `FlowReject` (sum): Irreducible, NotCounted, UnsupportedTerminator, UnsupportedInduction, UnknownValue

**Observations:** `FlowTripCountUnknown` is the critical fallback — when trip count isn't known, vectorization and loop optimization cannot reason about bounds. The `FlowLoopNormalizedCounted` fact carries both trip_count and direction but depends on Flow producing these automatically.

---

### Mem Schema (`mem.lua`)

**Access Facts:**
- `MemAccessId`, `MemAccessOp` (sum): Load, Store, Atomic variants
- `MemAccessFact` — `func, block, inst, op, place, access, base, index, pattern, alignment, bounds, trap`
- `MemAccessInterval` — `access, object, loop, start, length_elems, elem_size, const_byte_offset`
- `MemAccessSafetyFact` (sum): InBounds, NonTrap, Movable, DerefBytes, AlignKnown

**Objects:**
- `MemObjectId`, `MemBase` (sum): Value, Local, Global, Data, Argument, Projection, Unknown
- `MemObjectForm`, `MemProjectionStep`, `MemObjectProvenance` (extensive sum)
- `MemObjectFact` — `form, provenance, elem_ty, extent, stride`
- `MemLeaseGrant`

**Alignment & Bounds:**
- `MemAlignment` (sum): Unknown, Known(bytes), AtLeast(bytes), Assumed(bytes+proof)
- `MemBounds` (sum): Unknown, InObject, Range(start+len), Assumed
- `MemTrap` (sum): MayTrap, NonTrapping, CheckedTrap
- `MemIndex` (sum): None, Value(value+elem_size+const_offset), Induction(induction+elem_size+const_offset)
- `MemAccessPattern` (sum): Scalar, Contiguous, Strided, Gather, Scatter, Unknown
- `MemObjectStride` (sum): Unknown, Unit, ConstElems, Value

**Dependence & Alias:**
- `MemAliasFact` (sum): Unknown, MayAlias, NoAlias, SameBaseSameIndexSafe, AliasScope
- `MemDependenceFact` (sum): Unknown, ReadReadIndependent, NoDependence, NoLoopCarriedDependence, DependenceDistance, LoopCarriedDependence
- `MemObjectRelation` (sum): SameLen, WindowOf, SliceOf, SameStore
- `MemProof` (sum): Bounds, Alignment, Alias, NoDependence, Contract, Flow, Object, Interval, Backend

**Backend Access Info (critical pass-through):**
```lua
product. MemBackendAccessInfo {
   access [MemAccessId],
   trap [MemTrap],
   alignment [MemAlignment],
   bounds [MemBounds],
   deref_bytes [optional [number]],
   movable [bool],
   proofs [many [MemProof]],
}
```

**Observations:** `MemBackendAccessInfo` is the key carrier of alignment/bounds/trap facts from the memory analysis to the backend. It flows through `KernelLane.backend_info` into kernel planning. The `MemProofBackend` variant explicitly connects backend access to proof tracking.

---

### Kernel Schema (`kernel.lua`)

**Planning Objects:**
- `KernelId`, `KernelValueId`, `KernelLaneId`
- `KernelSubject` (sum): Function, Loop, Domain, Fragment
- `KernelReject` (sum): NoFacts, UnsupportedSubject, UnsupportedExpr, UnsupportedMemory, Effect, IncompleteFunction
- `KernelProof` (sum): Flow, Value, Memory, Effect, FunctionEquivalence

**Kernel Lanes:**
```lua
product. KernelLane {
   id [KernelLaneId],
   object [MemObjectId],
   accesses [many [MemAccessId]],
   base [MemBase],
   elem_ty [CodeType],
   pattern [MemAccessPattern],
   backend_info [many [MemBackendAccessInfo]],
}
```
Lanes carry `backend_info` — the memory access facts that flow to the backend.

**Kernel Expressions:**
- `KernelExpr` (sum): Value, Algebra, LaneLoad(lane+index), KernelValue
- `KernelBinding(id, ty, expr)`
- `KernelExprProjection` — indexes bindings by kernel value name

**Kernel Effects:**
```lua
sum. KernelEffect {
   KernelEffectStore { dst [KernelLane], index [ValueExpr], value [KernelExpr] },
   KernelEffectScan { dst, index, reduction, mode, axis },
   KernelEffectPartition { dst, src, pred, semantics },
   KernelEffectCopy { dst, src, semantics },
   KernelEffectScatterReduce { dst, index, value, reducer },
   KernelEffectFold { reduction },
   KernelEffectCall { call },
}
```

**Kernel Results:**
```lua
sum. KernelResult {
   KernelResultVoid,
   KernelResultValue { expr },
   KernelResultFind { src, pred, not_found },
   KernelResultAll { src, pred, success, failure },
   KernelResultAllCompare { left, right, cmp, success, failure },
   KernelResultAny { src, pred, success, failure },
   KernelResultReduction { reduction },
   KernelResultClosedForm { closed_form },
   KernelResultOriginalControl { reason },
}
```

**Skeleton Selection:**
- `KernelSkeletonSelection` (sum): Scan, Copy, ScatterReduce, Find
- `KernelFunctionSkeletonSelection` (sum): Partition, NoSelection

**Equivalence & Plan:**
- `KernelEquivalence` (sum): Proof, Rejected
- `KernelBody(domain, lanes, bindings, effects, result, equivalence)`
- `KernelPlan` (sum): NoPlan(subject, rejects), Planned(id, subject, body)

**Loop Candidates:**
- `KernelLoopCandidate` (sum): NotCounted, MissingOwner, RejectedFacts, ClosedFormCandidate, ReductionCandidate, SkeletonCandidate, OriginalControlCandidate
- `KernelLoopPlanSelection` (sum): NoPlan, PlanClosedForm, PlanReduction, PlanSkeleton, PlanOriginalControl
- `KernelLoopPlanBuild` — the shared state carried through candidate selection

**Observations:** The kernel plan carries full semantic intent (effects + results + proofs) but `lower_to_c.lua` only uses a subset: `KernelEffectStore` → CMat store kernel, `KernelEffectFold` → reduction materialization, `KernelEffectScan/Copy/ScatterReduce/Partition` → corresponding CMat constructs. `KernelEffectCall` has no lower_c pathway. `KernelResult` drives control flow synthesis (closed-form, reduction, control, original control).

---

### Lower-to-C (`lower_to_c.lua`) — Data Flow Summary

**Entry Point: `module(code_module, lower_module, opts)`** (line ~2050):
1. Normalizes args through `normalize_args()` — if no `lower_module`, computes graph/flow/value/mem/effect/kernels/schedules/lower on the fly
2. Runs `CodeToC.module()` to get baseline `CBackendUnit` (non-semantic loops)
3. For each function with semantic fragments, calls `lower_semantic_func()`
4. Returns updated `CBackendUnit`

**`lower_semantic_func()`** (line ~1975):
1. `prepare_func_emission()` — pre-scans all blocks, notes instruction dst types, builds kernel_value_local/block/code_id mappings
2. `ordered_fragments_for_func()` — topological order of fragments by block order
3. For each fragment: `lower_emit_candidate()` → `select_lower_emit()` → `emit_to_c()`
4. `apply_lower_c_carriers()` — threads carrier/address block params through terminator edges

**`emit_scalar_kernel_fragment()`** (line ~1120):
1. `loop_partition()` — finds loop, body blocks, exit/latch edges, condition
2. `active_addresses_for_kernel()` — filters address plans serving this kernel's lanes
3. `place_bindings_effects()` — groups effects into blocks
4. `reduction_state_for_kernel()` / `control_state` — materializes CMat reductions/control
5. For header block: outputs CMat stmts + IfGoto (condition or domain exit)
6. For body blocks: outputs CMat effects + terminator (carries reduction accumulator through edges)
7. Latch block: emits `emit_reduction_update()`

**Fidelity Cliff — Where Kernel Facts Are Discarded:**
1. **Closed-form lowering** (`emit_closed_form_fragment`, line ~370): Uses only `fragment.strategy.fact.expr` and `reduction.accumulator` — all other kernel facts (lanes, backend_info, equivalence proofs) are discarded.
2. **Reduction state** (`reduction_state_for_kernel`, line ~1090): Only `kplan.body.result:lower_c_reduction_fact()` is used — lane access patterns, alignment from `MemBackendAccessInfo`, and dependence facts are not plumbed through.
3. **Control state** (`KernelResult:lower_c_control_state`): Builds CMat computation but discards all `backend_info` from lanes — alignment/trap/bounds from Mem never reach the C emitter.
4. **Vector kernel** (`emit_to_c` for `EmitVectorKernel`, line ~1915): "Vector scheduling is now a CMat policy, not a separate direct KernelEffect emitter. Until CMat vector bodies are richer, emit the same inline CMat SOAC body." — vector lanes, unroll, interleave, tail plan from Schedule are **completely discarded**.
5. **Carrier edge args** (`edge_args_with_reduction`): Only knows about the reduction accumulator — other kernel state (scan state, copy semantics, scatter-reduce identity values) is not threaded through CFG edges.
6. **Address plans in kernel emission** (`address_place_for_lane`): Uses address place for lane loads but doesn't thread alignment or restrict qualifiers through.

---

### code_kernel_plan.lua — Kernel Plan Matching

**`function_plans()` (line ~1440)** — Main planning loop:
1. For each `FlowLoopFacts` loop: determines if counted, then calls `lanes_for_accesses()` to group memory accesses into kernel lanes
2. Builds kernel body via `build_kernel_body()` — walks loop blocks, converts instructions to KernelExpr/KernelEffect
3. Calls `infer_loop_skeleton()` — tries scan → scatter-reduce → find → all → copy
4. Matches reduction facts (`reductions_for_domain`) and closed-form facts
5. Produces `KernelLoopCandidate` → `select_kernel_loop_plan()` → `add_selected_loop_plan()`
6. Also tries `infer_partition_skeleton()` for function-level partition plans

**`lanes_for_accesses()` (line ~200)**: Groups memory accesses by (object, base, pattern). Each group becomes a `KernelLane` with `backend_info` from `MemBackendAccessInfo`. Checks for non-trapping and bounds-known as prerequisites.

**`build_kernel_body()` (line ~350)**: Maps Code instructions to kernel expressions — loads become `KernelExprLaneLoad`, stores become `KernelEffectStore`, value computations become `KernelExprAlgebra`. Skips side-effecting instructions (atomics, calls).

**Skeleton Inference Priority Order** (in `infer_loop_skeleton`, line ~1250):
1. `infer_scan_skeleton` — prefix scan (one reduction + one store matching reduction update)
2. `infer_scatter_reduce_skeleton` — index-modifying store with reduction semantics
3. `infer_find_skeleton` — early-exit primary-index search
4. `infer_all_skeleton` — early-exit all-predicate check
5. `infer_copy_skeleton` — same-index load/store pair

**Skeleton Result Handling:**
- `KernelResultClosedForm` — for algebraic closed-form expressions
- `KernelResultReduction` — for fold/reduce loops
- `KernelResultOriginalControl` — fallback when no skeleton matches
- `KernelResultVoid` — copy/scatter-reduce produce void results

**Carrier/Address Planning** (in `address_threads`, line ~1580): Discovers address projections by finding contiguous-pattern memory accesses whose index values form a carrier recurrence through the loop's edge facts. Produces `FlowCarrierThread` and `FlowAddressThread` facts.

---

### emit_c_lower.lua — C Text Emission

**Type Emission:** `c_emit_type()` → `c_emit_decl()`, with implicit descriptor/closure type collection. The `CBackendType` sum has ~20 variant leaves, each with leaf methods for naming.

**Optimizer Passes (in order within `c_emit_func`):**
1. **Transfer equivalence** (`compute_transfer_equivalence`): Canonicalizes block parameters that are always the same across all predecessors — a form of SSA optimization.
2. **Field hoisting** (`plan_field_hoists`): Hoists repeated field loads from pointer parameters into local variables at function entry. Threshold: 3+ loads of same field from same canonical base local.
3. **Copy propagation** (`copy_propagate_blocks`): Forward propagation of single-assignment copies. Invalidation on reassignment.
4. **Dead copy elimination** (`remove_dead_copy_assigns`): Removes copy-assigns where the destination is unused.
5. **Inline expression** (`emit_block_stmts_and_term`): Final emission merges single-use expressions directly into terminator lines (like `if (x + y * 3)`).

**Helper Generation:**
- `CBackendHelperSpec:c_emit_helper_lines_with_id()` — produces C function body for each helper spec
- Helper naming: `ml_<type_suffix>_<op_suffix>_<mode_suffix>`
- Atomic helpers use C11 `_Atomic(...)` with `memory_order_seq_cst`
- Float helpers use explicit casts

**Main Entry Points:**
- `CBackendFunc:c_emit_func(sigs, out)` — emits one function
- Descriptor types, closure types, type decls, globals are emitted separately

---

## Relationships — Data Flow Map

```
CodeModule
  → CodeGraph.graph(module)            [graph structure]
  → CodeFlowFacts.facts(module, graph)  [FlowFactSet: loops, domains, edges, carriers]
  → CodeValueFacts.facts(...)           [ValueFactSet: value exprs, reductions, closed forms]
  → CodeMemFacts.semantic_facts(...)     [MemSemanticFactSet: objects, accesses with alignment/bounds/trap]
  → CodeEffectFacts.facts(...)          [EffectFactSet: side effects]
  → CodeKernelPlan.plan(...)            [KernelModulePlan: per-loop KernelPlan with lanes/effects/results]
  → CodeSchedulePlan.plan(...)          [ScheduleModulePlan: per-kernel Schedule with vector policy]
  → CodeLowerPlan.plan(...)             [LowerModule: per-function LowerFuncPlan with fragments]
  → lower_to_c.module(...)              [Lower-to-C: merges baseline CodeToC with semantic lowering]
     → CodeToC.module(code_module)      [baseline CBackendUnit with code-only blocks]
     → lower_semantic_func() for each semantic fragment:
        → emit_closed_form_fragment()   [uses only closed-form expr, discards lanes/proofs/backend_info]
        → emit_scalar_kernel_fragment() [uses CMat inline for effects, discards alignment/trap]
        → emit_vector_kernel_fragment() [delegates to scalar via CMat, discards Schedule unroll/interleave]
     → apply_lower_c_carriers()         [threads carrier/address params through edges]
  → emit_c_lower (text emission)        [CBackendUnit → C source string]
```

**Fidelity Loss Points:**

| Stage | What's Available | What's Used | What's Discarded |
|-------|-----------------|-------------|------------------|
| Mem→Kernel | Alignment, bounds, trap, dependence | All flow into KernelLane.backend_info | — |
| Kernel→Schedule | Lanes, bindings, effects, results, proofs | Lanes, effects, results | Most proofs |
| Schedule→Lower | Vector lanes, unroll, interleave, tail | Scalar form | **All vector policy** |
| Lower→C Emit | CMat kernel context | Inline point expressions | **Alignment from backend_info, trap policy, bounds** |
| C Emit→Text | CBackendUnit | All | — |

---

## Observations

1. **The CBackend schema is rich but under-annotated:** Structs have `align` but no `packed` flag; vector types exist but have no load/store operations; branch probabilities, inline pragmas, and restrict annotations lack CBackend-level representation.

2. **Vectorization is a dead letter:** `ScheduleVector` with `unroll`, `interleave`, `tail` exists, but `EmitVectorKernel:emit_to_c()` explicitly says "until CMat vector bodies are richer" and falls back to scalar. The entire Schedule→Emit pathway loses vectorization.

3. **Alignment facts vanish at CMat boundary:** `MemBackendAccessInfo` carries alignment from memory analysis through `KernelLane.backend_info`, but `lower_to_c.lua` never reads these fields when emitting CMat loads/stores. The CMat `CBackendPlacePtrIndex` has no alignment field.

4. **Trap policy from Mem never reaches C emission:** `MemTrap` (MayTrap, NonTrapping, CheckedTrap) flows through `MemBackendAccessInfo.trap` into kernel lanes, but the C emission never generates different code for trapping vs non-trapping loads.

5. **Bounds checks are absent from the emission path:** `MemBounds` (Unknown, InObject, Range, Assumed) exists in `MemAccessFact` and `MemBackendAccessInfo` but has no representation in CBackendPlace or CBackendLoad/CBackendStore — no bounds-checking emission.

6. **Reduction identity values aren't tracked through edges:** `edge_args_with_reduction` only knows about the accumulator — other kernel state (scan accumulators, copy semantics, scatter indices) is not carried across CFG edges.

7. **`KernelEffectCall` has no `lower_c` pathway:** The schema has `KernelEffectCall { call [CallSummary] }` but `Kernel.KernelEffect:lower_c_place_effect` errors for this variant, meaning function calls inside kernel loops cannot be lowered.

8. **No loop-level fusion or interchange:** The lowering pipeline processes one kernel fragment at a time. There's no mechanism for fusing two kernel fragments into a single loop, even though the schedule schema can represent multi-effect computations.

9. **The emit_c_lower optimizer pipeline is sophisticated but local:** Copy propagation, field hoisting, transfer equivalence, and inline expression all operate on a per-function basis. There's no cross-function or loop-nest optimization in the text emission phase.

10. **`FlowTripCountUnknown` is a critical gate:** When Flow can't compute a trip count, the entire kernel/schedule/lower pipeline degrades — it can still produce a `KernelPlan` with `FlowTripCountUnknown`, but vectorization and many optimizations are blocked.

## Scout Output — 2026-07-06 20:42:21

I now have complete data for all 7 questions. Here is the comprehensive report:

---

## 1. How `code_flow_facts.lua` Computes Trip Counts

**File:** `/home/cedric/dev/lalin/lua/lalin/code_flow_facts.lua`

### Where `FlowTripCount` is produced

In the `semantic_facts()` function (lines ~245-270), **every** counted loop gets `FlowTripCountUnknown`:

```lua
-- line ~258
out[#out + 1] = Flow.FlowLoopNormalizedCounted(loop.loop, loop.counted, direction,
    Flow.FlowTripCountUnknown("no explicit trip-count CodeValueId is available"))
```

There is **no code path** that produces `FlowTripCountExact`. The trip count is always `Unknown` with the literal reason `"no explicit trip-count CodeValueId is available"`.

### The analyze_loop function (lines ~130-175)

The loop analysis successfully computes:
- **Induction variables**: finds header params where the latch backedge is a binary recurrence (`param + step` or `param - step`) — `induction_step()` at lines ~100-108
- **Counted domain**: `FlowCountedDomain(init, stop, step, exclusive)` at line ~167
- **Range**: `FlowRangeDerived(value, min, max, ...)` at lines ~158-160
- **Direction**: derived in `direction_for()` from step constant sign

But none of these facts produce a `FlowTripCountExact` — the trip count itself (e.g. `(stop - start) / step`) is never computed as an expression. The semantic facts function has all the inputs (`counted.start`, `counted.stop`, `counted.step`) but doesn't materialize a trip-count value expression.

### What causes `FlowTripCountUnknown`

**Single root cause**: `semantic_facts()` at lines ~255-258 always writes `FlowTripCountUnknown(...)`. The counted domain exists (`FlowCountedDomain` with init/stop/step/exclusive), range exists, induction exists, direction exists — but the trip count expression is never built.

### How to fix

At line ~258 of `code_flow_facts.lua`, after confirming the loop is counted with a primary induction, compute `trip = (stop - start + (exclusive ? 0 : step)) / step` as a `ValueExpr` and produce `FlowTripCountExact(trip_count_value, proof)` instead of `FlowTripCountUnknown`.

---

## 2. How `code_to_c.lua` Lowers Baseline Code IR

**File:** `/home/cedric/dev/lalin/lua/lalin/code_to_c.lua` (1359 lines)

### Architecture

`code_to_c.lua` is a **direct 1-to-1 translation layer** from `Code.` ASDL IR to `C.` CBackend ASDL IR. It produces a `CBackendUnit` with code-only blocks (no kernel lowering). Every `Code.CodeInstOp` leaf and `Code.CodeTermOp` leaf has a `lower_code_inst_to_c_stmts()` / `lower_code_term_to_c()` method.

### Key conversion points

**Instructions → CBackendStmt arrays** (lines ~345-520):
- `CodeInstConst` → `CBackendAssign(dst, CBackendRAtom(const_atom))`
- `CodeInstBinary` → `CBackendHelperCall(dst, helper, {lhs, rhs})` via `binary_helper_spec()` which routes div/rem/shift to specialized helpers
- `CodeInstCompare` → `CBackendAssign(dst, CBackendRCompare(op, ty, lhs, rhs))`
- `CodeInstLoad` → `CBackendPlaceLoad(dst, place_to_c(place))`
- `CodeInstStore` → `CBackendPlaceStore(place, atom(value))`
- `CodeInstCall` → `CBackendCall(dst?, target:lower_code_call_target_to_c(), atoms(args))`
- `CodeInstAtomicLoad/Store/Rmw/Cas/Fence` → specialized helper calls with `atomic_place_addr_stmts()` for address extraction
- `CodeInstAggregate` → `CBackendAggregateInit(...)`
- `CodeInstVariantCtor` → tag field init + optional payload store

**Terminators → CBackendTerminator** (lines ~550-590):
- `CodeTermJump` → `CBackendGoto(label, atoms(args))`
- `CodeTermBranch` → `CBackendIfGoto(cond, then_label, then_args, else_label, else_args)`
- `CodeTermSwitch` → `CBackendSwitchGoto(value, cases, default_label, default_args)`
- `CodeTermReturn` → `CBackendReturn(value)` or `CBackendReturnVoid`
- `CodeTermTrap` → `CBackendTrap`

**Place → CBackendPlace** (lines ~200-270):
- `CodePlaceLocal` → `CBackendPlaceLocal(local_id, ty)`
- `CodePlaceDeref` → `CBackendPlaceDeref(atom(addr), ty, align)` — **alignment is preserved here**
- `CodePlaceField` → `CBackendPlaceField(base_place, name, ty, offset, size, align)` — **alignment + size flow through**
- `CodePlaceIndex` → `CBackendPlaceIndex(base_place, index, ty, elem_size)` — **NO alignment on index**
- `CodePlaceBytes` → `CBackendPlaceBytes(base_atom, offset, ty, size, align)` — **alignment + size flow through**

**Carrier/Address edge threading** (lines ~670-760):
- `edge_carrier_args()`, `edge_address_args()` — walk `c_emission.lower_carriers`/`lower_addresses` to thread block params through edges
- `CBackendGoto:code_to_c_apply_carrier_edges()` — appends carrier+address args to goto
- `CBackendIfGoto:code_to_c_apply_carrier_edges()` — creates edge_transfer blocks if pre-stmts needed

**Module entry point** (lines ~1100+):
```lua
-- builds CBackendUnit from CodeModule
-- for each func: builds locals, blocks (stmts from insts, terminator from term)
-- applies carrier edges
-- gathers helpers, types, globals, externs
```

---

## 3. CMat (Stencil Materialization) — How It Works

### CMat Schema

**File:** `/home/cedric/dev/lalin/lua/lalin/schema/c_materialize.lua` (129 lines)

Key types:
- **`CMatAccessBinding`** — maps a `StencilAccessRef` to a C local variable: carries `local_id`, `ty`, `mutability`, `restrict_eligible`, `const_eligible`, `alignment`
- **`CMatLoopNest`** — loop structure: axes, unroll factor, interleave factor, `CMatVectorPolicy`
- **`CMatVectorPolicy`** (sum): `CMatVectorNone` | `CMatVectorAutovec(lanes?, tail)` | `CMatVectorExplicit(lanes, tail)`
- **`CMatTailPolicy`** (sum): `CMatTailScalar` | `CMatTailMask` | `CMatTailOverreadProvenSafe`
- **`CMatFusedKernel`** — fused computation: loop nest + access bindings + stream materializations + sink materializations
- **`CMatMaterialization`** (sum): `CMatMaterializedFused(kernel)` | `CMatRejectedKernel(issues)`
- **`CMatModule`** — module-level collection of materializations

### `StencilComputation` → `cmat_materialize()`

**File:** `/home/cedric/dev/lalin/lua/lalin/emit_c_materialize.lua`

`StencilComputation:cmat_materialize()` at line ~220:
1. Creates `CMatAccessBinding` for each access (with `restrict_eligible`, `const_eligible` from role + layout)
2. Creates `CMatStreamMaterialization` for each stream (default: `CMatStreamInline`)
3. Creates `CMatSinkMaterialization` for each sink (default: `CMatSinkInline`, control results: `CMatSinkControlResult`)
4. Builds `CMatLoopNest` from schedule: axes from producer shape, unroll/interleave/vector policy from schedule
5. Returns `CMatMaterializedFused(CMatFusedKernel(...))`

### `lower_c_emit_inline_cmat` — The bridge from kernel to CMat

**File:** `/home/cedric/dev/lalin/lua/lalin/lower_to_c.lua`

Each `KernelEffect` leaf has a `lower_c_emit_inline_cmat()` method (lines ~1100-1170):
- `KernelEffectStore` → `cmat_store_kernel()`: builds `StencilComputation` with read-accesses as inputs, store effect as `StencilSinkOpStore`, then calls `computation:lower_c_inline_computation()`
- `KernelEffectScan` → `cmat_scan_kernel()`: similar but with `StencilSinkOpScan`
- `KernelEffectCopy` → `cmat_copy_kernel()`: uses `StencilStoreCopy` semantics
- `KernelEffectScatterReduce` → `cmat_scatter_reduce_kernel()`: builds `StencilSinkOpScatterFold`
- `KernelEffectFold` → **errors**: "reductions must use CMat reduction materialization, not KernelEffectFold direct emission"
- `KernelEffectPartition`, `KernelEffectCall` → **no `lower_c_emit_inline_cmat` leaf** (errors via parent)

The bridge function `cmat_store_kernel()` (lines ~1080):
1. Calls `cmat_state_for_kernel(kplan)` to index kernel bindings
2. Converts `KernelExpr` → `StencilPointExpr` via `lower_c_stencil_point()` on the store value
3. Converts lane reads to `StencilPointInput` with `cmat_access_binding_for_lane()`
4. Constructs `StencilComputation` via `computation_for_body()`
5. Calls `note_cmat_param_qualifiers()` for restrict annotation
6. Returns a `cmat_context_for_computation()` with `access_by_name` lookup table

### `StencilComputation:lower_c_inline_computation()`

**File:** `/home/cedric/dev/lalin/lua/lalin/lower_to_c.lua`, lines ~1030-1040

This is the **SOAC → inline scalar C emitter bridge**:
```lua
function Stencil.StencilComputation:lower_c_inline_computation(c_emission, cmat, index_atom)
    cmat.computation = self
    cmat.stream_by_id = {}
    for _, stream in ipairs(self.streams or {}) do cmat.stream_by_id[stream.id.text] = stream end
    for _, sink in ipairs(self.sinks or {}) do sink:lower_c_inline_sink(c_emission, cmat, index_atom) end
end
```

Each sink drives emission:
- `StencilSinkOpStore:lower_c_inline_sink()` → loads stream value at index, then calls `dst_binding:lower_c_inline_store(index_atom, value)` — which emits `CBackendPlaceStore(CBackendPlacePtrIndex(...), value)`
- `StencilSinkOpFold:lower_c_inline_sink()` → loads stream, calls `reducer.reduction:lower_c_inline_reduce_update(cmat.acc, value)` — emits `CBackendHelperCall(acc, binary_helper, {acc, value})`
- `StencilSinkOpScan` → like fold + conditional store for exclusive/inclusive mode
- `StencilSinkOpScatterFold` → loads old value at scatter_index, reduces with new value, stores back
- `StencilSinkOpAll/Any/Find` → sets `cmat.control_pred` for control-flow splitting

### Key observation — Inline CMat is SOAC without vectorization

The inline CMat path emits **scalar loads/stores/computes** inside the loop. The `CMatLoopNest` with its `vector` policy is constructed but **not used** by the inline emitter — it only matters when the `stencil_c.lua` AOT helper-generator path is taken. The inline path is essentially "SOAC expressed in C, let the C compiler auto-vectorize."

---

## 4. `stencil_c.lua` — Generated C Stencil Helpers

**File:** `/home/cedric/dev/lalin/lua/lalin/stencil_c.lua` (1555 lines)

### What it does

`stencil_c.lua` generates **standalone C helper functions** from `StencilComputation` trees. It uses the LLBL C DSL (`llbl.c`) to build C AST nodes programmatically. This is the AOT path — generating C source files that can be compiled separately.

### How stencil helpers are generated

The file works through a series of **name → C DSL expression** translators:
- `type_name(ty)` → `"i32"`, `"f64"`, `"index"`, `"bool8"`
- `c_type(ty)` → C type node (`C.i32`, `C.f64`, etc.)
- `binary_name(op)` → `"add"`, `"sub"`, `"mul"`, `"min"`, `"max"`, etc.
- `reduction_name(kind)` → `"add"`, `"mul"`, `"and"`, `"or"`, `"xor"`, `"min"`, `"max"`
- `pred_name(pred)` → `"nonzero"`, `"lt"`, `"range_lt_le"`, `"and3"`, etc.

### Generated C structure

A stencil helper function is parameterized by:
1. **Access parameters**: typed pointers or scalars for each `StencilAccess`
2. **Producer loop bounds**: `start`/`stop` params for each axis
3. **Affine offset params**: for `Affine1D`/`AffineND` layouts
4. **Stride params**: for view descriptors

The body is a **nested loop nest** matching the producer shape:
- Range1D: simple `for (i = start; i < stop; i += stride)`
- RangeND: nested loops with linearized index computation
- WindowND: nested loops with boundary handling (clamp/wrap/zero/reject)
- TiledND: tile loops + point loops

### Generated C expression examples

- `access_c_expr()` → `base[index]` or `base[index].field_name`
- `c_binary_expr()` → typed arithmetic with trapping div/rem/mod
- `c_shift_expr()` → `stmt_expr` with bounds checking
- `c_predicate_expr()` → C comparison nodes
- `c_divrem_expr()` → traps on zero division and signed overflow
- `c_window_input_expr()` → boundary-handling expressions with `select()`

### `assume_aligned` support

```lua
local function assume_aligned_stmts(artifact, names)  -- line ~290
    -- emits __builtin_assume_aligned(name, bytes) for proven alignments
end
```

The alignment facts come from `access_vector_fact()` which queries `StencilVectorizationFacts.access_facts[].alignment` — alignment is used in the AOT path.

### `artifact_shape` integration

Uses `ArtifactPlan` (from `stencil_artifact_plan.lua`) to handle:
- `descriptor_accesses()` — access list from a descriptor
- `access_named()` — lookup by name
- `stride_param_name()`, `affine_offset_param_name()` — dynamic parameter naming
- `window_axis_coord()` — boundary computation

---

## 5. `emit_c_materialize.lua` — `default_stencil_schedule()` and `CMatVectorPolicy`

**File:** `/home/cedric/dev/lalin/lua/lalin/emit_c_materialize.lua` (240 lines)

### `default_stencil_schedule()`

Defined in `lower_to_c.lua` line ~1036:
```lua
local function default_stencil_schedule()
    return Stencil.StencilScheduleScalar(Stencil.StencilCompilerPolicy(
        Stencil.StencilCompilerGcc, Stencil.StencilOptO3,
        Stencil.StencilMachineNative, {}))
end
```

This produces a **scalar schedule with GCC/O3/native** — no vectorization, no unrolling, no interleaving. It's used by all the `cmat_*_kernel()` builder functions when constructing `StencilComputation`.

### `CMatVectorPolicy` — How it works in emit_c_materialize.lua

The `emit_c_materialize.lua` file defines the bridge from `StencilSchedule` to `CMatVectorPolicy`:

```lua
-- StencilSchedule → CMatVectorPolicy
StencilSchedule:cmat_vector_policy() → CMatVectorNone
StencilScheduleAutoVector:cmat_vector_policy() → CMatVectorAutovec(nil, CMatTailScalar)
StencilScheduleVector:cmat_vector_policy() → CMatVectorExplicit(
    self.lane_policy:cmat_lane_count() or self.vector_unroll,
    self.tail:cmat_tail_policy()
)

-- StencilLanePolicy → lane count
StencilLaneFixed:cmat_lane_count() → self.lanes

-- StencilVectorTailPolicy → CMatTailPolicy
StencilVectorScalarTail:cmat_tail_policy() → CMatTailScalar
StencilVectorMaskTail:cmat_tail_policy() → CMatTailMask
StencilVectorOverreadProvenSafe:cmat_tail_policy() → CMatTailOverreadProvenSafe
```

The `computation_loop_nest()` function constructs the `CMatLoopNest`:
```lua
local function computation_loop_nest(computation)
    local schedule = computation.schedule
    return CMat.CMatLoopNest(
        computation.producer.shape:cmat_loop_axes(),
        schedule:cmat_unroll(),     -- defaults to 1
        schedule:cmat_interleave(), -- defaults to 1
        schedule:cmat_vector_policy()
    )
end
```

**Critical**: The `CMatVectorPolicy` is attached to the `CMatLoopNest` but the **inline CMat emitter in lower_to_c.lua never reads it**. It's there for the AOT stencil helper generation path. The inline path always emits scalar code.

---

## 6. `LowerCEmitInput` — Definition and Usage

**File:** `/home/cedric/dev/lalin/lua/lalin/schema/lower.lua`, lines 183-190

### Schema definition:
```lua
product. LowerCEmitInput {
    graph [LalinGraph.CodeGraph],
    flow [LalinFlow.FlowFactSet],
    kernels [LalinKernel.KernelModulePlan],
    schedules [LalinSchedule.ScheduleModulePlan],
    code_func [LalinCode.CodeFunc],
    fragment [LalinLower.LowerFragment],
    baseline_blocks [many [LalinC.CBackendBlock]],
}
```

### Where it's populated

**Single construction site:** `lower_to_c.lua` line 2067:
```lua
selection:emit_to_c(c_emission, Lower.LowerCEmitInput(
    graph, flow, kernels, schedules, code_func, fragment, baseline_blocks))
```

### What each field carries

| Field | Origin | Purpose |
|-------|--------|---------|
| `graph` | `CodeGraph.graph(code_module)` or from `lower_module` | Loop structure, edges — used by `loop_partition()`, `graph_loop_by_id()` |
| `flow` | `CodeFlowFacts.facts()` or from `lower_module` | Edge args, loop facts, conditions — used by `emit_closed_form_fragment()`, `loop_partition()` |
| `kernels` | `CodeKernelPlan.plan()` or from `lower_module` | Kernel plans — looked up by `kernel_by_id()` in all emit functions |
| `schedules` | `CodeSchedulePlan.plan()` or from `lower_module` | Schedule plans — indexed by `schedule_by_id()` for emit candidate selection |
| `code_func` | The `CodeFunc` being lowered in the current iteration | Block structure — used by `prepare_func_emission()`, `cover_blocks()` |
| `fragment` | The current `LowerFragment` from `ordered_fragments_for_func()` | Cover, strategy, proofs — drives which emit function is called |
| `baseline_blocks` | The `CBackendBlock` list from the baseline `CodeToC` output | Non-semantic blocks — `EmitCode` copies them verbatim; semantic emitters replace them |

### Important: `LowerBackEmitInput` also exists

Lines 173-182 for a generic backend input, but C backend uses `LowerCEmitInput`.

---

## 7. `KernelLane.backend_info` — Does any code in lower_to_c.lua read alignment/bounds from it?

### Short answer: **No. It is carried along but never read.**

### The grep is definitive:
```
$ grep -n "backend_info" lua/lalin/lower_to_c.lua
(no matches)
```

`lower_to_c.lua` **never references `backend_info`**. Not once. Zero usage.

### Where `backend_info` IS used:

1. **`code_kernel_plan.lua`** (lines ~260-290): Used as a **gate** during lane construction:
   - Rejects accesses with missing `MemBackendAccessInfo`
   - Rejects accesses where `backend.trap` is not `MemNonTrapping`
   - Rejects accesses where `backend.bounds` is `MemBoundsUnknown`
   - Collects `g.backend` array and packs it into `KernelLane(..., g.backend)`

2. **`kernel_validate.lua`** (lines ~116-117): Validation check that lane cites valid `MemBackendAccessInfo`.

3. **`code_mem_facts.lua`** (line ~628): Constructs `MemBackendAccessInfo(id, trap, align, bounds, deref, movable, {proof})`.

### What this means for the fidelity cliff

`MemBackendAccessInfo` carries:
- `trap` (NonTrapping, MayTrap, CheckedTrap)
- `alignment` (Unknown, Known(bytes), AtLeast(bytes), Assumed(bytes, proof))
- `bounds` (Unknown, InObject, Range, Assumed)
- `deref_bytes` (optional number — how many bytes proven safe to dereference)
- `movable` (bool — can this load be hoisted?)

These flow through `KernelLane.backend_info` → `lower_to_c.lua` receives them in the `kplan` parameter but **never reads any lane's `backend_info`**.

This means:
- **Alignment**: `CMatAccessBinding` always gets `Stencil.StencilAlignmentUnknown` at construction time (line ~670 of `lower_to_c.lua`: `Stencil.StencilAlignmentUnknown`)
- **Trap policy**: Different trap modes don't affect code generation
- **Bounds**: No bounds-check insertion
- **Deref_bytes**: No hoisting decisions based on safe-deref range
- **Movable**: No load-hoisting based on this flag

### The only place alignment IS used in the C pipeline

The **`stencil_c.lua`** AOT path uses alignment (`access_alignment_bytes()` at line ~118) through `assume_aligned_stmts()` — but this is the **generated stencil helper** path, not the inline CMat path.

---

## Summary — The Full Picture

```
MemBackendAccessInfo (trap, align, bounds, deref, movable)
  │
  ▼ code_kernel_plan.lua — acts as GATE (rejects if missing/unproven)
  │
  ▼ KernelLane.backend_info — CARRIES the data (never read beyond this point)
  │
  ▼ lower_to_c.lua — builds CMatAccessBinding with alignment=Unknown
  │                    emits CBackendPlacePtrIndex (NO alignment field)
  │                    never reads backend_info
  │
  ▼ emit_c text — no __builtin_assume_aligned, no restrict from alignment
```

The pipeline **proves** alignment/bounds/trap facts in Mem analysis, **filters** at kernel planning (rejects unsafe loops), then **discards** the proven facts at C emission. The inline CMat path could use:
- `backend_info.alignment` → `__builtin_assume_aligned` hints or alignment-qualified pointer types
- `backend_info.movable` → loop-invariant load hoisting
- `backend_info.trap` → indicate to the C compiler that loads are non-trapping (affects loop vectorization)
- `backend_info.deref_bytes` → proven safe range for prefetch or contiguous load forms

## Knowledge-builder Output — 2026-07-06 20:47:51

Now I have the full picture. Here is the second-order analysis.

---

## What Matters Most for This Problem

Given the explicit goal is a **deep architecture redesign** of the C backend lowering, the most relevant dimensions are:

1. **Fidelity integrity** — the analysis pipeline proves facts (alignment, bounds, trap policy, trip count) but the lowering pipeline discards them. This is not a bug cluster; it's a systematic architectural gap at the boundary between semantic proofs and emission decisions.

2. **ASDL schema completeness** — under the project's doctrine, unwired facts are schema defects. Where facts exist in Lua side-tables or are hardcoded to constants (like `StencilAlignmentUnknown`), the ASDL vocabulary is incomplete.

3. **Layer boundary correctness** — the boundaries between Mem→Kernel→Schedule→Lower→CMat→CBackend are drawn but the contracts at each boundary are underspecified. Some layers produce facts that the next layer is supposed to consume but doesn't.

4. **Minimal change surface** — the overall architecture is sound. The right boxes exist, the dispatch is wired correctly through ASDL leaf methods, and the projection-facet pattern is respected. The problems are unwired connections and missing fields on existing types, not wrong boundaries.

---

## Non-Obvious Observations

### 1. The fidelity cliff has TWO distinct root causes, not one

The scout reports that `KernelLane.backend_info` is never read by `lower_to_c.lua`. This is true but incomplete. There are actually **two independent discard points**:

**Discard point A — `cmat_access_binding_for_lane` (line ~670):** This function receives a full `KernelLane` with `backend_info` but hardcodes `StencilAlignmentUnknown`. It doesn't read `lane.backend_info` because there's no conversion from `Mem.MemAlignment` → `Stencil.StencilAlignmentFact`. This is a pure Lua code gap — zero schema changes needed, just a conversion function.

**Discard point B — `computation_for_body` (line ~1080):** Every `cmat_*_kernel()` function calls `computation_for_body()` which calls `default_stencil_schedule()` — producing `StencilScheduleScalar`. The `ScheduleModulePlan` carrying the actual `ScheduleVector` with unroll/interleave/tail is available in `LowerCEmitInput.schedules` but is **never looked up** in the `emit_scalar_kernel_fragment` code path. The schedule is passed through the dispatch chain (`LowerEmitKernelCandidate(schedule) → LowerEmitVectorKernel`) but the `emit_scalar_kernel_fragment` function constructs a brand-new `StencilComputation` with a hardcoded scalar schedule — completely ignoring the `fragment_emit.schedules` that the dispatch received.

These are distinct problems with different fixes. Discard point A is a missing conversion. Discard point B is a missing wire — the schedule exists in the input but the code path that should use it builds its own instead.

### 2. The inline CMat path uses `StencilComputation` but doesn't need its AOT machinery

Look at what `cmat_store_kernel` actually does:

```lua
local computation = computation_for_body(kplan, loop_fact, reads, dst, stream, sink)
note_cmat_param_qualifiers(c_emission, computation, ...)
return cmat_context_for_computation(computation, access_by_name)
```

And `cmat_context_for_computation`:

```lua
local function cmat_context_for_computation(computation, access_by_name)
    local materialized = computation:cmat_materialize()
    return { kernel = materialized.kernel, computation = computation, access_by_name = access_by_name }
end
```

The `materialized.kernel` is a `CMatFusedKernel` — it carries the full `CMatLoopNest` with vector policy, all `CMatAccessBinding`s with their (hardcoded `Unknown`) alignment, and stream/sink materializations. But in the inline emission path, only `cmat.access_by_name` and `cmat.computation` are used. `cmat.kernel` — with its loop nest and vector policy — is **dead data** in the inline path.

This means the `StencilComputation` abstraction is doing double duty: it serves both the AOT stencil helper path (which needs the full mathematical model) and the inline CMat path (which only needs access bindings and sink definitions). The AOT path consumes `CMatFusedKernel.loop.vector`; the inline path doesn't. This dual-use creates a false impression that the vector policy is "wired" — it's constructed, stored, and present in the data structure, but the inline emitter's code path never reads it.

### 3. `FlowTripCountExact` expects a `CodeValueId` from a phase that hasn't run yet

This is the deepest architectural tension I found. The schema says:

```lua
FlowTripCountExact { count [CodeValueId], proof [optional [MemProof]] }
```

But the code in `semantic_facts()` (line ~478) always produces `FlowTripCountUnknown` because:

> "no explicit trip-count CodeValueId is available"

The ingredient for the trip count exists: `loop.counted` carries `start`, `stop`, `step`, and `stop_exclusive`. You can trivially compute `(stop - start + adjustment) / step`. But the result needs to be a `CodeValueId` — an entry in the `CodeValueFactSet`.

Here's the phase-ordering problem: `code_flow_facts.semantic_facts()` runs during the Flow analysis phase. It produces `FlowSemanticFactSet`. The `CodeValueFactSet` is produced by `code_value_facts.facts()` — a different pass. Flow semantics don't (currently) have access to Value facts. And even if they did, the trip count expression hasn't been registered as a `CodeValue` because no source instruction computes it — it's a synthetic computation discovered by the loop analysis.

The options for resolving this reveal a real architectural tension:

- **Option A: Have Flow produce a `ValueExpr` directly.** Change `FlowTripCountExact` to carry `expr [ValueExpr]` instead of (or in addition to) `count [CodeValueId]`. The Flow pass computes the trip count arithmetic as a `ValueExpr`, stores it in the Flow fact. Downstream consumers can evaluate it. This keeps Flow self-contained but mixes Value expressions into Flow facts.

- **Option B: Create a synthetic `CodeValue` during Flow analysis.** Have `code_flow_facts.lua` call into `code_value_facts` to register a synthetic `CodeValueSynthetic(expr, ty)` and get back a `CodeValueId`, then use it in `FlowTripCountExact`. This preserves the existing schema but introduces a reverse dependency (Flow→Value).

- **Option C: Add a new trip-count fact to the Value phase.** Produce `ValueTripCount(loop_id, expr)` as a value fact. Have the Flow pass reference it. This keeps phases cleanly separated but requires a new Value fact type and coordination between passes.

The ASDL doctrine pushes toward Option A: "If a fact is needed but not in ASDL, the schema is incomplete." The fact that Flow analyzed a counted loop and computed the trip count expression **is a Flow fact**, not a Value fact. It should be expressible in Flow schema. The `ValueExpr` type already exists in `LalinValue` and is importable. Adding `trip_expr [optional [ValueExpr]]` to `FlowLoopNormalizedCounted` (or changing `FlowTripCountExact` to carry `expr [ValueExpr]` instead of `count [CodeValueId]`) is a one-field schema addition.

### 4. restrict is wired through a param-qualifier backchannel; alignment has no such channel

Trace the restrict path in `lower_to_c.lua`:

1. `cmat_access_binding_for_lane` sets `restrict_eligible = true` on `CMatAccessBinding`
2. `note_cmat_param_qualifiers` reads `binding.restrict_eligible` and sets `q.restrict_ptr = true` on a mutable Lua table keyed by `local_id`
3. `apply_c_param_qualifiers` (line ~1778) reads this table and calls `param.ty:lower_c_with_param_qualifiers(q)`
4. `CBackendDataPtr:lower_c_with_param_qualifiers` promotes to `CBackendQualifiedDataPtr(self.pointee, false, true, false)`

This is a **Lua side-channel** that threads semantic facts (restrict eligibility) through CBackend type construction. It works because:
- The fact attaches to a `CBackendLocalId` (stable identity)
- The param types are rewritten just before `CBackendFunc` construction
- The rewrite doesn't mutate the original ASDL — it produces new types

Alignment could use the **exact same mechanism**:
- `cmat_access_binding_for_lane` reads `lane.backend_info[1].alignment` → converts to `StencilAlignmentFact`
- `CMatAccessBinding` already has `alignment [StencilAlignmentFact]` (currently hardcoded to `Unknown`)
- `note_cmat_param_qualifiers` reads `binding.alignment` → adds `align` to the qualifiers table
- `apply_c_param_qualifiers` applies alignment to the pointer type
- A new `CBackendType:lower_c_with_alignment(bytes)` method annotates the pointer type

But here's the tension: restrict is a **type qualifier** in C (`int *restrict p`), so rewriting `CBackendDataPtr → CBackendQualifiedDataPtr` is the correct semantic. Alignment is NOT a type qualifier — it's an **attribute** (`int *__attribute__((aligned(16))) p`). The CBackend schema doesn't currently have attribute annotations on types or locals. Adding alignment as a type rewrite would conflate qualifiers with attributes.

The proper ASDL approach: add alignment to `CBackendLocalStorage` (the local variable declaration record) or add an optional `align` field to `CBackendDataPtr`/`CBackendPlacePtrIndex`. The text emitter then emits `__attribute__((aligned(N)))` on the declaration or `__builtin_assume_aligned` at the point of use.

### 5. There are TWO parallel alignment type hierarchies with no bridge

```lua
-- Mem schema (richer, has proofs):
MemAlignment = Unknown | Known(bytes) | AtLeast(bytes) | Assumed(bytes, proof)

-- Stencil schema (simpler, no proofs):
StencilAlignmentFact = Unknown | Known(bytes)
```

Every function in `lower_to_c.lua` that constructs a `CMatAccessBinding` hardcodes `StencilAlignmentUnknown`. The `KernelLane.backend_info` carries `MemAlignment` facts that are richer than what `StencilAlignmentFact` can represent. Any bridge would lose `AtLeast` and `Assumed` provenance.

This suggests a hidden design decision: should the CMat layer carry the richer `MemAlignment` type, or should it retain the simpler `StencilAlignmentFact`? The Stencil schema is meant to be a mathematical abstraction — it doesn't need to carry "at least N bytes with this proof." But the CMat layer is a materialization layer — it DOES need that information to generate correct code.

The tension is that `CMatAccessBinding.alignment` currently uses `StencilAlignmentFact` (the mathematical type), but at materialization time, the richer `MemAlignment` would be more useful. Switching to `MemAlignment` would be a cross-schema dependency (CMat→Mem). Keeping `StencilAlignmentFact` and bridging would lose information.

### 6. The `LowerEmitVectorKernel` dead letter is actually correctly dispatched

The scout frames this as a bug: "`LowerEmitVectorKernel:emit_to_c()` delegates to scalar." But looking at the dispatch chain:

```
ScheduleVector:lower_emit_kernel_selection() → LowerEmitVectorKernel  ✓
LowerEmitKernelCandidate(schedule):select_lower_emit() → schedule:lower_emit_kernel_selection() → ScheduleVector → LowerEmitVectorKernel  ✓
LowerEmitVectorKernel:emit_to_c() → emit_scalar_kernel_fragment()  ✗
```

The dispatch is **correct all the way down** until the leaf method. The ASDL distinction between `LowerEmitScalarKernel` and `LowerEmitVectorKernel` already exists in the schema. The problem is purely in the leaf method body — it should call a different function (or the same function with different parameters) rather than delegating to scalar.

But the deeper issue is that `emit_scalar_kernel_fragment` doesn't accept a schedule parameter. It takes `(c_emission, graph, flow, kernels, fragment)` — the `fragment.strategy.kernel` identifies the kernel plan, but the schedule is in `fragment_emit.schedules` which is NOT passed to `emit_scalar_kernel_fragment`. The function signature would need to change to accept schedules, or the vector kernel path would need to construct the `StencilComputation` differently.

### 7. The `CBackendPlacePtrIndex` alignment gap is a symptom, not the root cause

The scout notes that `CBackendPlacePtrIndex` has no `align` field while `CBackendPlaceDeref`, `CBackendPlaceField`, and `CBackendPlaceBytes` all do. This is true — line 188 of `emit_c_lower.lua` emits `base[index]` with no alignment annotation.

But adding `align` to `CBackendPlacePtrIndex` would only help if something sets it. The inline `CMatAccessBinding:lower_c_inline_load` (line ~843) constructs a `CBackendPlacePtrIndex` with hardcoded `1` for `elem_size` and no alignment:

```lua
local place = C.CBackendPlacePtrIndex(
    C.CBackendAtomLocal(C.CBackendLocalId(self.local_id.text)),
    index_atom, c_ty(c_emission, self.ty), 1)
```

The fix needs to happen at TWO levels simultaneously:
1. `CMatAccessBinding` must carry the real alignment (from `KernelLane.backend_info`)
2. `CBackendPlacePtrIndex` needs an `align` field to receive it

Without both changes, the alignment fact remains stranded. This is a coupled change across two schema layers (CMat + CBackend).

### 8. The optimizer passes in `emit_c_lower.lua` have no access to semantic facts

Copy propagation, dead-store elimination, field hoisting, and transfer equivalence all operate on `CBackendUnit` — purely structural IR with no semantic annotations. They don't know which blocks are loop headers, which pointers are aligned, or which loads are proven non-trapping.

This means even if alignment were threaded through to `CBackendPlacePtrIndex`, the optimizer passes would need to be taught to **preserve** alignment annotations when rewriting. Currently, `c_emit_rewrite_aliases` on `CBackendPlacePtrIndex` (line 209) preserves `ty` and `elem_size` but would need to also preserve `align`. This is a minor change but indicates that alignment annotations add a preservation burden to every optimizer pass.

### 9. `TailPlan` has five levels of death

The tail handling is dead at **five distinct architectural points**:

1. **Schedule layer**: `ScheduleVector` carries `tail [TailPlan]` — alive here
2. **Lower dispatch**: `LowerEmitVectorKernel` is selected — alive here
3. **Emit method**: delegates to scalar — dead here
4. **CMat construction**: `default_stencil_schedule()` ignores the vector schedule — doubly dead
5. **Inline emission**: emitted as flat gotos, no loop construct to split — triply dead

Making tail handling work would require:
- Trip count to be known (fix the Flow trip count bug)
- `LowerEmitVectorKernel` to emit a vector loop + scalar tail
- CBackend IR to represent two loops with a tail
- The text emitter to generate both loops

This is fundamentally a **loop fission** problem: splitting one counted loop into a vector loop and a scalar tail loop. The current flat-goto IR can represent both loops (they're just two different `CBackendBlock` chains), but the emitter needs to compute the split point: `vector_iters = (trip_count / lanes) * lanes; tail_start = vector_iters`.

### 10. The `StencilComputation` carries a schedule field that is always the default when constructed from kernels

Look at `computation_for_body` (line ~1080):

```lua
local function computation_for_body(kplan, loop_fact, reads, dst, body_stream, sink)
    ...
    return Stencil.StencilComputation(
        ...
        default_stencil_schedule(),  -- ALWAYS scalar
        kplan.body.equivalence and kplan.body.equivalence.proofs or {}
    )
end
```

And compare with `emit_c_materialize.lua` line ~82-91 where `StencilAccess:cmat_binding(input)` also hardcodes `StencilAlignmentUnknown`.

The `StencilComputation` has a `schedule` field that is used by the AOT path (`stencil_c.lua`) but the inline path never even passes it through. Every `cmat_*_kernel()` function builds a new `StencilComputation` from scratch, overriding whatever schedule information existed.

The fix for discard point B: instead of calling `default_stencil_schedule()`, these functions should receive the actual schedule from `LowerCEmitInput.schedules` and construct the `StencilComputation` with it. Then `computation_loop_nest()` would produce a `CMatLoopNest` with real vector policy, and the inline emitter could be taught to consume it.

---

## Knowledge Gaps

1. **How `code_schedule_plan.lua` schedules kernels** — the scout confirmed it produces `ScheduleVector` with unroll/interleave/tail, but I need to understand the exact data flow from `ScheduleModulePlan` to `LowerCEmitInput.schedules` to confirm that the schedule is reachable from `emit_scalar_kernel_fragment`. I can see that `fragment_emit.schedules` is the `ScheduleModulePlan` in `LowerCEmitInput`, but I haven't verified that the `schedules_by_id` lookup in `lower_emit_candidate` produces a `SchedulePlanned` with the right form.

2. **The exact `schedule_by_id` function** — I see `lower_emit_schedule` at line ~1718 that looks up `schedules_by_id[fragment.strategy.kernel.text]`, but I haven't verified that this returns a `SchedulePlanned` with `ScheduleVector` form. If the schedule pipeline produces `NoPlan` for some kernels, the vector path would never be taken regardless of the emit method fix.

3. **Whether there are existing tests that would catch alignment/trip count regressions** — I should verify the test coverage around the fidelity cliff to understand the safety net for changes.
