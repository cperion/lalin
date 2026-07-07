# Lalin Target Phase Architecture

> ⚠️ **ASPIRATIONAL** — This document describes a target organizational model that differs from the current codebase. Many file names and schema conventions described here do not yet match the active tree. See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for current-state documentation.

This documents the target architecture for Lalin's ASDL schema and method
organization, designed around the compiler's actual phase pipeline. Every
artifact — schema product, implementation file, and method — is placed in the
phase it belongs to, with naming that reflects its semantic role.

The architecture derives from `docs/ASDL_GUIDE.md` and the audited violations
across the codebase (wf-249c33d5). It is the reference design; implementation
is measured against it.

---

## Compiler Phase Pipeline

The compiler has these phases in order. Each phase is a typed boundary:
a method on an ASDL receiver consumes a typed input and produces a typed output.

```
source text
  │
  ▼
[0. Parse]          source text → LalinTree.Module
  │
  ▼
[1. Surface Resolve]  Module → resolved Module
  │                    (names, paths, module references)
  ▼
[2. Closure Convert]  resolved Module → closed Module
  │                    (lambdas are lifted, captures resolved)
  ▼
[3. Typecheck]        closed Module → TypeModuleResult { module, issues }
  │                    (expressions typed, contracts checked)
  ▼
[4. Layout Resolve]   typed Module → layout-resolved Module
  │                    (memory layouts assigned to types)
  ▼
[5. Tree Lowering]    layout-resolved Module → CodeResult { code_module, contracts, layout_env }
  │                    (LalinTree → Code IR)
  ▼
[6. Code Validate]    CodeModule → CodeValidateReport
  │
  ▼
[7. Code Graph]       CodeModule → CodeGraph
  │
  ▼
[8. Flow Facts]       CodeModule + CodeGraph → FlowFactSet + FlowSemanticFactSet
  │
  ▼
[9. Value Facts]      CodeModule + CodeGraph + FlowFactSet → ValueFactSet
  │
  ▼
[10. Memory Facts]    CodeModule + CodeGraph + Flow + Value + Contracts → MemFactSet + MemSemanticFactSet
  │
  ▼
[11. Effect Facts]    CodeModule + CodeGraph + Mem + Contracts → EffectFactSet
  │
  ▼
[12. Kernel Plan]     CodeModule + CodeGraph + Flow + Value + Mem + Effect → KernelModulePlan
  │
  ▼
[13. Schedule Plan]   CodeModule + KernelPlan + Flow + Value + Mem + Effect + Target → ScheduleModulePlan
  │
  ▼
[14. Kernel Validate] All plans → KernelValidateReport
  │
  ▼
[15. Code Lower Plan] CodeModule + CodeGraph + KernelPlan + SchedulePlan → LowerPlan
  │
  ▼
[16. C Backend Emit]  CodeModule + LowerPlan → CBackendUnit
  │                    (Code IR → C source text)
  ▼
[17. C Validate]      CBackendUnit → CValidateReport
  │
  ▼
[18. C Compile]       CBackendUnit → compiled shared object / AOT artifact
  │                    (GCC/TCC over emit_c output)
  ▼
function pointers via FFI / AOT artifact
```

---

## Schema File Organization

Every schema file lives under `lua/lalin/schema/`. Files are named for the
phase or cross-cutting concern they serve.

### Phase Schema Files

| File | Phase | Content |
|------|-------|---------|
| `parse_schema.lua` | 0 | ParseResult, ParseIssue |
| `source_schema.lua` | 0 | SourceDoc, Anchor, Position, SourceEdit |
| `tree_schema.lua` | 1-5 | LalinTree source nodes: Expr, Stmt, TypeDecl, Module, Item, all source-only products |
| `tree_schema.lua` | 3 | Typecheck inputs/outputs: TypeValueScope, TypeModuleFacts, TypeExprInput, TypeExprResult, TypeStmtInput, TypeStmtResult, TypeFuncResult, TypeItemResult, TypeModuleResult |
| `tree_lower_schema.lua` | 5 | Tree→Code lowering products: TreeLowerFunctionFacts, TreeLowerFunctionState, TreeLowerInput, TreeLowerExprResult, TreeLowerStmtResult, all TreeLower* entry products |
| `code_schema.lua` | 5-16 | Code IR: CodeModule, CodeFunc, CodeBlock, CodeInst, CodeTerm, CodeType, CodeSig, CodeExtern, CodeData, CodeGlobal, CodeConst, CodeOrigin |
| `code_graph_schema.lua` | 7 | CodeGraph, GraphEdge, GraphDef, GraphUse, GraphLoop |
| `code_flow_schema.lua` | 8 | FlowDomain, FlowInduction, FlowCarrier, FlowAddress, FlowFactSet, FlowSemanticFactSet |
| `code_value_schema.lua` | 9 | ValueExpr, ValueRange, ValueReduction, ValueClosedForm, ValueFactSet, ValueFactProjection |
| `code_mem_schema.lua` | 10 | MemObject, MemAccess, MemAlias, MemDependence, MemFactSet, MemSemanticFactSet, MemAccessProjection |
| `code_effect_schema.lua` | 11 | EffectObject, CallSummary, EffectFactSet |
| `code_kernel_schema.lua` | 12 | KernelPlan, KernelLane, KernelDomain, KernelModulePlan |
| `code_schedule_schema.lua` | 13 | ScheduleForm, ScheduleProof, ScheduleEmitterCapability, ScheduleModulePlan |
| `code_backend_schema.lua` | 6-16 | Code→Backend products: CodeBackendModuleMachine, CodeBackendFunctionState, CodeBackendInstInput, CodeBackendStateResult, CodeBackendValueResult, all CodeBackend* entry products |
| `code_validate_schema.lua` | 6 | CodeValidationMachine, CodeValidateResult, CodeIssue |
| `lower_plan_schema.lua` | 15 | LowerFragment, LowerCarrierPlan, LowerAddressPlan, LowerBackEmitInput, LowerCEmitInput, LowerModule |
| `emit_c_schema.lua` | 16-18 | CBackendType, CBackendExpr, CBackendStmt, CBackendUnit, CBackendBlock, CBackendTarget, CEmitMachine |
| `backend_schema.lua` | 16 | Backend IR: BackCmd, BackScalar, BackVal, BackAddress, BackMemoryInfo |
| `emit_c_materialize_schema.lua` | 16 | Stencil→C materialization: CMatAccessBinding, CMatVectorPolicy, CMatMaterialization |
| `stencil_schema.lua` | exp | Stencil descriptors, producers, accesses, sinks, metastencil |
| `stencil_machine_schema.lua` | exp | Stencil→backend machine plan, StencilMachineKernelConfig (union), StencilMachinePointInput (union) |
| `emit_native_schema.lua` | exp | Native copy-patch backend |
| `emit_luajit_schema.lua` | exp | LuaJIT backend |
| `emit_luatrace_schema.lua` | exp | LuaTrace backend |

### Cross-Cutting Schema Files

| File | Content |
|------|---------|
| `core_schema.lua` | Scalars, ops, syms, phase enum, AtomicOrdering |
| `bind_schema.lua` | Bindings, residence, value refs, env, const env |
| `semantic_schema.lua` | Field refs, layout env, const eval, flow outcome |
| `type_schema.lua` | Source types, type shapes, ABI plans, handle facts, lease origin |
| `host_schema.lua` | Host boundary layouts, accessors, exports |
| `phase_schema.lua` | Phase world, machine, plan, package |
| `project_schema.lua` | Task graph |
| `compiler_schema.lua` | CodeResult, CodeResultIssue |
| `link_schema.lua` | Link toolchain, platform, arch, format |
| `exec_schema.lua` | Exec fragments, stencil decisions |

---

## Implementation File Organization

Implementation files live under `lua/lalin/`. Each file corresponds to the
phase it implements.

### Phase Implementation Files

| File | Phase | Content |
|------|-------|---------|
| `parse_surface.lua` | 0 | Parse `.lln` documents into LalinTree.Module |
| `surface_resolve.lua` | 1 | Resolve module names, paths, imports |
| `closure_convert.lua` | 2 | Lambda lifting, capture resolution |
| `typecheck.lua` | 3 | Typecheck orchestration: check_module, scope building, item typecheck |
| `typecheck_expr.lua` | 3 | Leaf methods: Expr*:typecheck → TypeExprResult |
| `typecheck_stmt.lua` | 3 | Leaf methods: Stmt*:typecheck → TypeStmtResult |
| `typecheck_type.lua` | 3 | Leaf methods: Type*:typecheck_* (type operations) |
| `typecheck_fact.lua` | 3 | Leaf methods: typecheck facts, scope derivation |
| `typecheck_layout.lua` | 3 | Leaf methods: typecheck layout queries |
| `layout_resolve.lua` | 4 | Resolve memory layouts for typed module |
| `tree_lower.lua` | 5 | Tree→Code lowering: Func*:lower, Stmt*:lower, Expr*:lower → TreeLower*Result |
| `tree_contract_facts.lua` | 5 | Leaf methods: Contract*:contract_fact → ContractFact |
| `tree_control_facts.lua` | 5 | Leaf methods: ControlFact*:control_decide → ControlDecision |
| `tree_expr_type.lua` | 5 | Leaf methods: Expr*:expr_type → Type |
| `tree_module_type.lua` | 5 | Leaf methods: Module/TypeDecl*:module_type_* |
| `tree_place_type.lua` | 5 | Leaf methods: Place*:place_type → Type |
| `tree_stmt_type.lua` | 5 | Leaf methods: Stmt*:stmt_type → StmtTypeResult |
| `code_validate.lua` | 6 | Methods on CodeValidationMachine: validate, check_reloc, validate_func |
| `code_graph.lua` | 7 | Methods on CodeModule: build_graph → CodeGraph |
| `code_flow_facts.lua` | 8 | Methods on CodeModule: flow_facts → FlowFactSet, semantic_facts → FlowSemanticFactSet |
| `code_value_facts.lua` | 9 | Methods on CodeModule: value_facts → ValueFactSet |
| `code_mem_facts.lua` | 10 | Methods on CodeModule: memory_facts → MemFactSet, semantic_facts → MemSemanticFactSet |
| `code_effect_facts.lua` | 11 | Methods on CodeModule: effect_facts → EffectFactSet |
| `code_kernel_plan.lua` | 12 | Methods: plan → KernelModulePlan |
| `code_schedule_plan.lua` | 13 | Methods: plan → ScheduleModulePlan |
| `kernel_validate.lua` | 14 | Methods: validate → KernelValidateReport |
| `code_lower_plan.lua` | 15 | Methods: plan → LowerPlan |
| `emit_c_lower.lua` | 16 | Methods: module → CBackendUnit; lower_func, emit_c |
| `emit_c_helpers.lua` | 16 | C helper code emission |
| `emit_c_validate.lua` | 17 | Methods on CEmitValidateMachine: validate → CValidateReport |
| `emit_c_coverage.lua` | 17 | C phase-boundary coverage checks |
| `emit_c_compile.lua` | 18 | GCC shared-object compilation (was c_gcc.lua) |
| `emit_c_tcc.lua` | 18 | TCC compilation (was c_tcc.lua) |
| `emit_c_materialize.lua` | 16 | Stencil→C fused kernel materialization |

### Cross-Cutting Implementation Files

| File | Content |
|------|---------|
| `const_eval.lua` | Constant evaluation: leaf methods on TypeShape*, ConstExpr→ConstExprResult |
| `switch_decide.lua` | Switch decision: leaf methods on SwitchKey* → SwitchDecision |
| `type_classify.lua` | Type classification: leaf methods on Type* → TypeClass |
| `type_abi_classify.lua` | ABI classification: leaf methods on TypeShape* → AbiClass |
| `func_abi_plan.lua` | Function ABI plan: leaf methods on Type* → FuncAbiPlan |
| `type_size_align.lua` | Type size/alignment: leaf methods on TypeShape* → SizeAlign |
| `type_to_backend_scalar.lua` | Type→Backend scalar: leaf methods on TypeShape* → BackendScalarResult |
| `backend_inspect.lua` | Backend IR inspection |
| `backend_program.lua` | Backend program building |
| `backend_target_model.lua` | Backend target model: host target detection |
| `backend_validate.lua` | Backend IR validation |
| `compiler_driver.lua` | Public compile/lower entrypoints |
| `compiler_machines.lua` | Hosted machine implementations |
| `compiler_model.lua` | Compiler world model binding |
| `compiler_package.lua` | Compiler phase package definition |
| `compiler_abi.lua` | ABI helpers |
| `frontend_pipeline.lua` | Complete frontend pipeline orchestration |
| `init.lua` | Module entrypoint |
| `asdl.lua` | ASDL runtime |
| `triplet.lua` | Target triplet |
| `store.lua` | Store/artifact management |

### Stencil Implementation Files (experimental)

| File | Content |
|------|---------|
| `stencil_methods.lua` | Stencil plan/readiness methods |
| `stencil_metastencil.lua` | Metastencil legality/descriptor/candidate |
| `stencil_artifact_plan.lua` | Stencil artifact plan |
| `stencil_c.lua` | Stencil C lowering |

---

## Naming Conventions

### File Names

- Use lowercase with `_` to separate words.
- Phase files: `<phase>_<role>.lua` — e.g., `tree_lower.lua`, `emit_c_lower.lua`.
- Schema files: `<phase>_schema.lua` — e.g., `tree_lower_schema.lua`, `code_schema.lua`.
- Cross-cutting: `<concern>.lua` — e.g., `const_eval.lua`, `type_classify.lua`.

### Product Names

- Full words, no abbreviations: `Function`, not `Func`; `Backend`, not `Back`.
- Exception for conventional compiler abbreviations: `Expr`, `Stmt`, `Inst`,
  `Ty` (as a prefix), `Sig`, `Param` — these are standard across compiler
  literature.
- Phase prefix where helpful: `TypeExprResult`, `TreeLowerFunctionState`,
  `CodeBackendModuleMachine`.
- No `TreeCode*` — that was the old ambiguous name. Use `TreeLower*` for
  tree→code lowering.
- No `CodeBack*` — use `CodeBackend*`.

### Sum vs Product Naming

- Products: descriptive noun phrases — `TypeValueScope`, `TreeLowerFunctionState`,
  `CodeBackendModuleMachine`.
- Sums: the abstract category, with leaves as concrete alternatives —
  `CodeLinkage` with `CodeLinkageLocal` / `CodeLinkageExport` / `CodeLinkageImport`.
- Result unions: `<Noun>Result` — `TypeExprResult`, `CodeValidateResult`,
  `ConstEvalResult`.
- Reject leaves: `<Noun>Reject` with `reason [str]` — `LowerCarrierReject`,
  `ScheduleReject`.

---

## Schema Products by Phase

### Phase 0: Parse

```
LalinParse
  ParseResult — sum: ParseOk { module }, ParseFailed { issues }
  ParseIssue { message [str], offset, line, col }

LalinSource
  SourceDoc { text, anchors, edits }
  SourcePos { line, byte_col, utf16_col }
  Anchor { role [AnchorRole], start, end, ... }
  AnchorRole — sum of ~26 concrete roles (AnchorOpaque kept as terminal)
  LanguageId — sum: LangLalin, LangUnknown { name [str] }
```

### Phase 3: Typecheck

These live in `LalinTree` alongside source nodes. They are the typecheck
phase's input/output products, not source AST.

```
LalinTree
  -- Typecheck machine
  TypeModuleFacts { variants, handles, effects, regions, region_protocols, region_seals, region_bundles }
  TypeNameScope { types [many TypeEntry] }
  TypeValueScope { module_name, values, types, layouts, facts }
  TypeScopeChange { scope }

  -- Inputs (typed per operation)
  TypeExprInput { scope }
  TypeExpectedExprInput { scope, expected [Type] }
  TypeValueRefInput { scope }
  TypePlaceInput { scope }
  TypeIndexBaseInput { scope }
  TypeViewInput { scope }
  TypeStmtInput { scope, return_ty, yield }
  TypeControlInput { stmt, region_id }
  TypeFuncInput { scope }
  TypeItemInput { scope }
  TypePolicyInput { site }
  TypeCanonicalInput { names }
  TypeBinaryInput { op, rhs }
  TypeCompareInput { op, rhs }

  -- Results (typed per operation)
  TypeExprResult — sum { expr, ty, issues }
  TypePlaceResult — sum { place, ty, issues }
  TypeStmtResult — sum { state, stmts, issues }
  TypeFuncResult — sum { func, issues }
  TypeItemResult — sum { items, issues }
  TypeModuleResult — sum { module, issues }
  TypeValueRefResult { ref, ty, issues }
  TypePolicyResult { issues }
  TypeCanonicalResult { ty }
  TypeBinaryResult { ty, issues }
  TypeCompareResult { ty, issues }
  TypeViewResult — sum { view, issues }
  TypeIndexBaseResult — sum { base, elem, issues }
  TypeControlStmtRegionResult — sum { region, issues }
  TypeControlExprRegionResult — sum { region, issues }
  TypeYieldResult — sum: TypeYieldPresent, TypeYieldAbsent
```

### Phase 5: Tree Lowering

These are extracted from `LalinTree` into a new `LalinTreeLower` module.

```
LalinTreeLower
  -- Module-level facts (the lowering spine)
  TreeLowerModuleFacts { module_name, layout_env, target [optional CBackendTarget], const_env, variant_defs }
  TreeLowerModuleSigState { module_name, code_sigs, code_sig_order }
  TreeLowerModuleRegistrationState { funcs, externs, extern_order }
  TreeLowerModuleEmissionState { generated_data, counters }

  -- Function-level state (the lowering machine, explicitly threaded)
  TreeLowerFunctionFacts { module_facts, sigs, registrations, module_emission, func_name }
  TreeLowerFunctionState {
    bindings [TreeLowerBindingState],
    residence [TreeLowerResidenceFacts],
    emission [TreeLowerEmissionState],
    counters [TreeLowerCounterState],
    alpha [TreeLowerAlphaState],
    control [TreeLowerControlState],
  }
  TreeLowerFunctionStart { facts, state }

  -- State sub-components
  TreeLowerBindingState { values_by_key, locals_by_key }
  TreeLowerResidenceFacts { addressed_by_key, mutable_by_key }
  TreeLowerEmissionState { locals, blocks, current_blocks }
  TreeLowerCounterState { values_by_name }
  TreeLowerAlphaState { renamed_by_key, current_suffix_by_slot, seq }
  TreeLowerControlState { current_regions, flags }

  -- Entry products (keyed relations, not side tables)
  TreeLowerBindingValueEntry { binding_name, value [CodeValueId] }
  TreeLowerLocalBindingEntry { binding_name, binding [TreeLowerLocalBinding] }
  TreeLowerCounterEntry { counter_name, next_value }
  TreeLowerAlphaRenameEntry { binding_name, renamed [str] }
  TreeLowerAlphaSuffixEntry { slot_name, suffix [str] }
  TreeLowerControlRegionSlot { slot_name, region [TreeLowerControlRegion] }
  TreeLowerBindingSnapshot { bindings, locals_by_key }

  -- Control regions
  TreeLowerControlRegion — sum: TreeLowerExprControlRegion, TreeLowerStmtControlRegion
  TreeLowerControlTarget { id, params }
  TreeLowerControlTargetEntry { label_name, target }
  TreeLowerBlockBuilder { id, name, params, insts, origin }

  -- Variant definitions (from source type declarations)
  TreeLowerVariantDef { owner, variants }
  TreeLowerVariantDefEntry { type_name, def }
  TreeLowerVariant { name, tag, payload, fields }
  TreeLowerVariantEntry { variant_name, variant }

  -- Function registration
  TreeLowerFunctionRegistration { id, sig }
  TreeLowerFunctionRegistrationEntry { func_name, registration }

  -- Sig/bookkeeping entries
  TreeLowerSigEntry { sig_name, sig }
  TreeLowerExternEntry { extern_name, extern }
  TreeLowerLocalBinding { id, ty, source_ty }

  -- Inputs (typed per operation)
  TreeLowerInput — sum:
    TreeLowerExprInput { facts, state },
    TreeLowerPlaceInput { facts, state },
    TreeLowerStmtInput { facts, state },
    TreeLowerControlInput { facts, state }
  TreeLowerContractInput { module_facts, sigs, func_name, func_id }

  -- Results (all thread state)
  TreeLowerStateResult { state }
  TreeLowerCounterResult { value, state }
  TreeLowerBindingKeyResult { binding_name, state }
  TreeLowerValueIdResult { value, state }
  TreeLowerInstIdResult { id, state }
  TreeLowerTermIdResult { id, state }
  TreeLowerBlockIdResult { id, state }
  TreeLowerTermResult { term, state }
  TreeLowerLocalResult { id, ty, state }
  TreeLowerAlphaResult { renamed_by_key, state }
  TreeLowerControlExitResult — sum: TreeLowerSawExit { state }, TreeLowerNoExit { state }
  TreeLowerFallthroughResult — sum: TreeLowerFellThrough { state }, TreeLowerNoFall { state }
  TreeLowerExprResult { value [optional CodeValueId], ty, state }
  TreeLowerPlaceResult { place, state }
  TreeLowerIndexPlaceResult { place, index, state }
  TreeLowerViewPartsResult { data, len, stride, state }
  TreeLowerStmtResult { state }
  TreeLowerParamResult { param, ty, state }
  TreeLowerFunctionParts { name, linkage, params, result, body }
  TreeLowerContractResult { fact }

  -- Module-level phase bundles
  TreeLowerModuleParts { module_facts, sigs, registrations, emission }
  TreeLowerItemRegisterInput { module_facts, sigs, registrations }
  TreeLowerItemContractsInput { module_facts, sigs, registrations, emission, contract_facts }
  TreeLowerItemLowerInput { module_facts, sigs, registrations, emission, mod_name, funcs, data, globals }
```

### Phase 6: Code Validation

```
LalinCodeValidation
  CodeValidationMachine {
    module [CodeModule],
    graph [CodeGraph],
    spine [CodeBackendSpine],
    issues [many CodeIssue],
    relocs [many CodeRelocCheckEntry],
  }
  CodeValidateResult — sum:
    CodeValidateOk { module [CodeModule] },
    CodeValidateFailed { issues [many CodeIssue] }
  CodeIssue — sum:
    CodeIssueMissingSig { sig },
    CodeIssueMissingValue { value },
    CodeIssueMissingGlobal { global },
    CodeIssueInvalidReloc { reloc, reason [str] },
    ...
```

### Phase 7: Code Graph

```
LalinCodeGraph
  CodeGraph { edges, defs, uses, loops }
  GraphEdge { from, to, kind [GraphEdgeKind] }
  GraphEdgeKind — sum: GraphEdgeFlow, GraphEdgeControl, GraphEdgeData
  GraphDef { value, inst [optional GraphInstRef], param [optional CodeValueId] }
  GraphUse { value, inst [optional GraphInstRef], term_block [optional GraphBlockId], role [GraphUseRole] }
  GraphUseRole — sum: GraphUseOperand, GraphUseArgument, GraphUseResult, ...
  GraphLoop { header, blocks, exits }
```

### Phases 8-11: Fact Sets

```
LalinCodeFlow
  FlowFactSet { module, domains, edges, loops, ranges, domain_shapes, domain_intents, carriers, addresses, rejects }
  FlowSemanticFactSet { ... }
  FlowDomain { axes, shape, intent, ... }
  FlowDomainAxis { index_ty, start [optional], stop [optional], step, order, index_name [optional str] }
  FlowCarrier { ... }
  FlowAddress { ... }
  FlowInduction { param, step, ... }

LalinCodeValue
  ValueFactSet { module, values, reductions, closed_forms }
  ValueExpr — sum: ValueExprConst, ValueExprValue, ValueExprUnary, ValueExprCast,
    ValueExprAdd, ValueExprSub, ValueExprMul, ValueExprDiv, ValueExprRem,
    ValueExprBinary, ValueExprSelect, ValueExprCmp, ValueExprAffine
  ValueRange — sum: ValueRangeUnknown, ValueRangeInt
  ReductionFact { id, domain, accumulator, op, init, contribution, ty, ... }
  ClosedFormFact { id, reduction, expr, proof }
  ValueFact — sum: ValueExprFact, ValueRangeFact, ValueNoWrapFact, ValueFloatModeFact
  ValueFactProjection { expr_by_value, proof_by_value, no_wrap_by_value, float_mode_by_value }
  ValueExprByValueEntry { value_name, expr }
  ValueProofByValueEntry { value_name, proof }
  ValueIntSemanticsByValueEntry { value_name, sem }
  ValueFloatModeByValueEntry { value_name, mode }

LalinCodeMem
  MemFactSet { module, accesses, aliases, dependences, proofs }
  MemSemanticFactSet { module, objects, leases, accesses, intervals, safety, effects, dependences, relations, backend_info, proofs }
  MemObject { ... }
  MemAccess { ... }
  MemAlias { ... }
  MemAccessProjection { access_by_id, object_by_access, backend_by_access, proof_by_access }

LalinCodeEffect
  EffectFactSet { module, calls, insts, terms }
  EffectObject — sum: EffectObjectKnown, EffectObjectUnknown
  CallSummary { ... }
  EffectAtomic { ordering [LalinCore.AtomicOrdering] }
    -- note: ordering is typed AtomicOrdering, not [str]
```

### Phase 12-15: Planning

```
LalinCodeKernel
  KernelModulePlan { module, flow, value, mem, effect, plans }
  KernelPlan { ... }
  KernelLane { ... }

LalinCodeSchedule
  ScheduleModulePlan { ... }
  ScheduleForm { ... }
  ScheduleEmitterCapability { kind [ScheduleCapabilityKind], executable, reason, rejects }
  ScheduleCapabilityKind — sum (was [str])

LalinLowerPlan
  LowerPlan { carriers, addresses, funcs, issues }
  LowerFragment { id, cover, strategy, proofs, issues }
  LowerCarrierPlan { carrier, index, value_ty, strategy, blocks, transfers, proofs }
  LowerAddressPlan { address, carrier, base, strategy, blocks, transfers, lanes, insts, proofs }

  -- Emit inputs (spine + optional cache)
  LowerBackSpine { code_module, graph, target }
  LowerBackCache { flow [optional], value_facts [optional], mem [optional], effect [optional], kernels [optional], schedules [optional] }
  LowerBackEmitInput { spine, fragment, cache [optional] }
  LowerCEmitInput { graph, flow, kernels, schedules, code_func, fragment, baseline_blocks }
```

### Phase 16-18: C Emit

```
LalinC
  CBackendUnit { ... }
  CBackendType — sum of C type shapes
  CBackendExpr — sum of C expression forms
  CBackendStmt — sum of C statement forms
  CBackendTarget { dialect, platform, pointer_bits, index_bits, endian, hosted, ... }
  CBackendValidationInput { unit, storage, abi_issues }
  CBackendBlock { ... }

LalinCEmit  (new)
  CEmitMachine {
    spine [LowerBackSpine],
    sigs [many CodeSigByIdEntry],
    helpers [many CEmitHelperEntry],
    sig_order [many CodeSig],
    helper_order [many CEmitHelperEntry],
  }
  CEmitModuleResult — sum:
    CEmitOk { unit [CBackendUnit] },
    CEmitFailed { issues [many CEmitIssue] }
  CEmitFuncResult { source [str], func_name, helpers }
  CEmitHelperEntry { ... }

LalinCodeBackend
  CodeBackendSpine { module, graph, target, layout_env }
  CodeBackendModuleMachine {
    spine,
    sigs [many CodeSigByIdEntry],
    sig_abi [many CodeSigAbiBySigEntry],
    mem_backend [many CodeMemBackendByInstEntry],
    value_semantics [CodeValueSemanticsProjection],
    effects [many CodeEffectByInstEntry],
    readonly [CodeBackReadonlyProjection],
  }
  CodeBackendFunctionState {
    cmds [many BackCmd],
    aggregates [CodeBackendAggregateState],
    closures [CodeBackendClosureState],
    local_slots [CodeBackendLocalSlotState],
    temps [CodeBackendTempState],
  }
  CodeBackendInstInput { module, func, state, inst }
  CodeBackendTermInput { module, func, state, term }
  CodeBackendPlaceInput { module, func, state, owner, access [optional] }
  CodeBackendStateResult { state }
  CodeBackendValueResult { value, state }
  CodeBackendAddressResult { address, state }
  CodeBackendMemoryInfoResult { memory, state }
  CodeBackendPlaceResult { address, state }

  -- Entry products
  CodeSigByIdEntry { sig_key, sig }
  CodeSigAbiBySigEntry { sig_key, abi }
  CodeMemBackendByInstEntry { inst_key, backend }
  CodeEffectByInstEntry { inst_key, effect }
  CodeTypeByValueEntry { value_key, ty }
  CodeParamsByBlockEntry { block_key, params }
  CodeLocalAddrByValueEntry { value_key, addr }
  CodeValueAddrByValueEntry { value_key, addr }
  CodeValueSizeByValueEntry { value_key, size }
  CodeCaptureByValueEntry { value_key, has_captures }
  CodeSlotByLocalEntry { local_key, slot }
```

---

## Method Architecture

### Principle: Methods Belong to ASDL Leaves

Every union operation is implemented as methods on concrete leaves.
The `if/elseif` dispatch in the current phase files
(`tree_contract_facts`, `tree_control_facts`, `tree_expr_type`,
`tree_module_type`, `tree_place_type`, `tree_stmt_type`, `sem_layout_resolve`,
`type_classify`, `type_abi_classify`) is replaced.

**Before** (auto-generated dispatch, forbidden):
```lua
function contract_fact(node, ...)
  local cls = schema.classof(node)
  if schema.isa(node, Tr.ContractBounds) then
    return (function(self) ... end)(node, ...)
  elseif schema.isa(node, Tr.ContractWindowBounds) then
    ...
  else
    error("phase: no handler for " .. tostring(cls), 2)
  end
end
```

**After** (leaf methods, correct):
```lua
function Tr.ContractBounds:contract_fact()
  local base, len = ... self.base, self.len
  if base == nil or len == nil then return Tr.ContractFactExprBounds(self.base, self.len) end
  return Tr.ContractFactBounds(base, len)
end

function Tr.ContractWindowBounds:contract_fact()
  ...
end
```

Each file keeps the `bind_context(T) -> api` contract and
`T._lalin_api_cache` memoization. The `api` object delegates to leaf methods:
```lua
api.contract_fact = function(node) return node:contract_fact() end
```

### Principle: Pure Methods on Machines

Methods that accumulate state return a **new machine**, not mutate in place:

```lua
-- Wrong: mutation
function CodeValidationMachine:add_issue(issue)
  table.insert(self.issues, issue)
end

-- Correct: derivation
function CodeValidationMachine:with_issue(issue)
  return CodeValidationMachine(
    self.module, self.graph, self.spine,
    append(self.issues, issue),
    self.relocs
  )
end
```

### Principle: Fact Passes Are Module Methods

Free functions with `(module, graph, flow, value, mem, effect)` bundles
become methods on `CodeModule` or on a fact spine:

```lua
-- Before:
local flow = CodeFlowFacts.facts(code_module, graph)

-- After:
local flow = code_module:flow_facts()
-- Or:
local spine = CodeFactSpine(code_module, graph)
local flow = spine:flow_facts()
```

The `CodeFactSpine` carries the minimum identity needed to recompute any
fact set:

```
product CodeFactSpine {
  module [CodeModule],
  graph [CodeGraph],
}
function CodeFactSpine:flow_facts() -> FlowFactSet
function CodeFactSpine:value_facts() -> ValueFactSet  -- internally calls flow_facts()
function CodeFactSpine:mem_facts(contracts) -> MemSemanticFactSet
function CodeFactSpine:effect_facts(contracts) -> EffectFactSet
```

When a fact set is precomputed and passed across phases, it is wrapped as
an optional cache, not threaded as an opaque input bag:

```
product CodeFactCache {
  flow [optional FlowFactSet],
  value [optional ValueFactSet],
  mem [optional MemSemanticFactSet],
  effect [optional EffectFactSet],
}
```

### Principle: `sem_call_decide` Is Deleted

`sem_call_decide.lua` returns ad hoc `{kind=...}` records but is required
only by one test file. The real lowering path in `tree_lower.lua` already
produces typed `CodeCallTarget` via leaf methods. Delete the file.

---

## What Not to Change

| Artifact | Reason |
|----------|--------|
| `tree_lower.lua` (tree_to_code.lua) leaf-method pattern | Reference implementation — 0 classof dispatch, ASDL inputs/results, state threading |
| `switch_decide.lua` (sem_switch_decide.lua) | Correct leaf methods on SwitchKey |
| `const_eval.lua` (sem_const_eval.lua) | Correct parent-default + leaf-override nil passthrough |
| `type_size_align.lua` | Correct leaf methods on TypeShape |
| `code_graph.lua` | Correct leaf methods on CodeGraph nodes |
| `code_lower_plan.lua` | Correct leaf methods |
| `TypeValueScope` / `TypeExprInput` / `TypeExprResult` shapes | Well-designed typecheck inputs/results — minor rename only |
| `TreeLowerFunctionState` + entry products + result threading | Well-designed state threading — rename TreeCode→TreeLower only |
| `ModuleHeader` sum (`ModuleSurface/Typed/Sem/Code`) | Deliberate phase spine — not bloat |
| GCC/TCC session objects (`self._handle` / `self._freed`) | Runtime IO boundary — exempt from purity |
| Schema DSL `FORBIDDEN_TYPE_NAMES` | Already blocks `any`/`table`/`map` |
| `interned` / `variant_unique` | Correct identity-in-schema pattern |

---

## Implementation Sequence

The work is ordered by dependency: each step builds on the prior one without
breaking the compiler.

1. **Schema extraction** — move TreeCode* from `tree_schema.lua` →
   `tree_lower_schema.lua`; move CodeBackend* from `code_schema.lua` →
   `code_backend_schema.lua`. Update `schema/init.lua`. Rename products:
   `TreeCode`→`TreeLower`, `CodeBack`→`CodeBackend`.

2. **Delete `sem_call_decide`** — verify test covers only behavior present in
   `tree_lower.lua`. Remove file and test.

3. **Fix nil-passthrough** — `back_scalar` → `TypeBackScalarUnavailable`,
   `known_layout` → `TypeMemLayoutUnknown`, `value_type` → typed issue return.

4. **Leaf-methodify phase dispatch** — rewrite `tree_contract_facts`,
   `tree_control_facts`, `tree_expr_type`, `tree_module_type`,
   `tree_place_type`, `tree_stmt_type`, `layout_resolve` (sem_layout_resolve),
   `type_classify`, `type_abi_classify` to leaf methods.

5. **Fix entry-product construction** — `ValueFactProjection`, `MemAccessProjection`
   construct actual entry products, not empty tables.

6. **Introduce CodeFactSpine** — code_module:flow/value/mem/effect fact methods,
   optional CodeFactCache.

7. **Introduce CodeValidationMachine** — replace ctx/fctx bags in
   `code_validate.lua`.

8. **Introduce CEmitMachine** — replace ctx bags in `emit_c_lower.lua`,
   `code_type.lua`.

9. **Split LowerBackEmitInput** — spine + cache, fact-recompute methods.

10. **Fix string discriminators** — `GraphEdgeKind`, `GraphUseRole`,
    `ScheduleCapabilityKind`, `AtomicOrdering`.

11. **Fix boolean protocol flags** — `TreeLowerControlExitResult` and
    `TreeLowerFallthroughResult` sums; `CodeReadonly` sum.

12. **Rename files** — `tree_to_code.lua`→`tree_lower.lua`,
    `sem_layout_resolve.lua`→`layout_resolve.lua`,
    `sem_const_eval.lua`→`const_eval.lua`,
    `sem_switch_decide.lua`→`switch_decide.lua`,
    `type_func_abi_plan.lua`→`func_abi_plan.lua`,
    `type_to_back_scalar.lua`→`type_to_backend_scalar.lua`,
    `c_emit.lua`→`emit_c_lower.lua`,
    `c_gcc.lua`→`emit_c_compile.lua`,
    `c_tcc.lua`→`emit_c_tcc.lua`,
    `c_validate.lua`→`emit_c_validate.lua`,
    `c_helpers.lua`→`emit_c_helpers.lua`,
    `c_coverage.lua`→`emit_c_coverage.lua`,
    `c_materialize.lua`→`emit_c_materialize.lua`,
    `back_*` files → `backend_*`,
    `lower_to_c.lua` → integrated into `emit_c_lower.lua`.

13. **Stencil cleanup** (last — experimental) — boolean soup → union of
    `StencilMachineKernelConfig` leaves, per-shape readiness methods.

---

## Non-Negotiable Rules

1. **No new `classof`/`isa` dispatch.** Every per-variant behavior is a leaf
   method.

2. **No new context bags.** Accumulator state → named ASDL product with methods.

3. **No new `{kind=...}` records.** Alternatives → ASDL sum.

4. **No new side tables.** Keyed facts → entry products under `many`.

5. **No new `nil` passthrough** except parent default "not supported" contracts.

6. **No new `optional` soup.** Optionality-as-alternative → ASDL sum.

7. **Schema first.** Implementation pressure → add the ASDL type, then write Lua.

8. **Full words in product names.** `Function` not `Func`, `Backend` not `Back`.
   Exception: conventional compiler abbreviations (`Expr`, `Stmt`, `Inst`,
   `Ty`, `Sig`, `Param`).

9. **Phase prefix on cross-phase products.** `TypeExprResult`, not just
   `ExprResult`; `TreeLowerFunctionState`, not `TreeCodeFuncState`;
   `CodeBackendModuleMachine`, not `CodeBackModuleFacts`.
