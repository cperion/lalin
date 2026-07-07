# Map old implementation files to receiver types 
Comprehensive mapping of existing lalin implementation files to their ASDL receiver types, phases, and impl/ migration targets.
**Workflow ID**: wf-ac8df9fc
**Started**: 2026-07-07 08:56:11
---

## Scout Output — 2026-07-07 09:00:10

Now I have thorough data. Let me compile the comprehensive mapping.

## Files Retrieved

The following is the full mapping of all Lalin implementation files (excluding schema/, schema_v2/, dsl/, syntax/, error/) with receiver types, phases, patterns, and migration targets.

---

## Comprehensive Mapping: Old Implementation Files → Receiver Types & Phases

### FRONTEND PIPELINE PHASES

---

**1. `lua/lalin/frontend_pipeline.lua`** (267 lines)
- **Role**: Composition/driver file; orchestrates all frontend phases
- **What it does**: Binds all phase modules into a single context T, then calls them in sequence: SurfaceResolve → ClosureConvert → Typecheck → Layout → TreeLower → CodeValidate (optionally Graph → Flow → Value → Mem → Effect → Kernel → Schedule → Lower → ToC → CValidate)
- **Phases**: All frontend phases (typecheck through C emission)
- **Clean mapping?** Yes, this is the top-level orchestrator. Maps to `impl/` files concept but via composition rather than directly.
- **Needs refactoring?** Keep as orchestrator; the impl/ files will provide the per-phase method installations it calls.

---

**2. `lua/lalin/surface_resolve.lua`** (137 lines)
- **Receiver types**: `LalinType` leaf types (TNamed, THandle, TPtr, TArray, TSlice, TView, TLease, TOwned, TAccess, TFunc, TClosure), `LalinTree.ModuleHeader/ModuleTyped/ModuleSem/ModuleCode`
- **Phase**: Surface resolution (resolves local type refs → global refs)
- **Pattern**: Uses `resolve_any` recursive walk; few method installations. Mostly functional with `asdl.classof` dispatch via recursive walk.
- **Clean mapping?** Maps to `impl/tree_surface.lua` — :surface_resolve() on LalinTree types
- **Needs refactoring?** The recursive `resolve_any` walk with `asdl.classof` dispatch could be problematic. Need leaf methods on Tree types.

---

**3. `lua/lalin/closure_convert.lua`** (819 lines)
- **Receiver types**: `Ty.Type`, `Ty.TScalar`, `Ty.TPtr`, `Ty.TFunc`, `Ty.TClosure` (`:closure_size_align()`), `B.ValueRef`, `B.ValueRefName` (`:closure_is_name_ref()`, `:closure_captured_name()`)
- **Phase**: Closure conversion (captures free variables, creates closure environments)
- **Pattern**: Method installations on Ty.Type union, plus helper functions. Has some leaf method dispatch.
- **Clean mapping?** Maps to `impl/tree_closure.lua` — :closure_convert() on LalinTree types
- **Needs refactoring?** Mostly clean; some helpers could be leaf methods.

---

**4. `lua/lalin/tree_typecheck.lua`** (1951 lines)
- **Role**: Composition file — orchestrates typecheck sub-phases
- **What it does**: Wires together `tree_typecheck_type`, `tree_typecheck_layout`, `tree_typecheck_fact`, plus defines `Tr.View:typecheck_tree_elem()` and `Tr.Module:typecheck_modules()` entry points
- **Receiver types**: `Tr.View` (`:typecheck_tree_elem()`), `Tr.Module` (`:typecheck_modules()`)
- **Phase**: Typecheck orchestration
- **Clean mapping?** Maps to `impl/tree_check.lua` — :typecheck() on LalinTree types
- **Needs refactoring?** Yes — sub-files should be inlined; entry method pattern is correct.

---

**5. `lua/lalin/tree_typecheck_type.lua`** (565 lines)
- **Receiver types**: `Core.Scalar` leaf types (`:typecheck_tree_is_bool()`, `:typecheck_tree_is_integer_scalar()`, `:typecheck_tree_is_float_scalar()`, `:typecheck_tree_is_numeric_scalar()`, `:typecheck_tree_is_void_scalar()`), `Ty.Type` leaf types (same predicates), `Ty.TNamed`, `Ty.TFunc`, `Ty.TClosure`, etc. for canonicalization
- **Phase**: Type canonicalization & classification
- **Pattern**: Leaf method installations on Core.Scalar and Ty.Type unions. Clean ASDL method dispatch.
- **Clean mapping?** Should be part of `impl/tree_check.lua`
- **Needs refactoring?** Inline into impl/tree_check.lua

---

**6. `lua/lalin/tree_typecheck_expr.lua`** (628 lines)
- **Receiver types**: `Ty.Type` (`:typecheck_tree_field_lookup_base()`), `Ty.TPtr`, `Ty.TAccess`, `Ty.TLease`, `Tr.ExprHeader`, `Tr.ExprTyped`, `Tr.PlaceHeader`
- **Phase**: Expression typechecking
- **Pattern**: Method installations + closure-based `type_expr` dispatch
- **Clean mapping?** Should be part of `impl/tree_check.lua`
- **Needs refactoring?** Inline into impl/tree_check.lua

---

**7. `lua/lalin/tree_typecheck_stmt.lua`** (852 lines)
- **Receiver types**: `Tr.RegionInvokeTarget`, `Tr.TypeModuleFacts`, `Tr.RegionContWire`, `Tr.BlockLabel`, plus expression/stmt typecheck methods
- **Phase**: Statement typechecking
- **Pattern**: Method installations + uses `asdl.classof` for some dispatch
- **Clean mapping?** Should be part of `impl/tree_check.lua`
- **Needs refactoring?** Yes — contains some `asdl.classof` dispatch that should be leaf methods

---

**8. `lua/lalin/tree_typecheck_fact.lua`** (708 lines)
- **Receiver types**: `Tr.TypeValueScope` (`:typecheck_tree_add_value()`, `:typecheck_tree_add_params()`, `:typecheck_tree_with_layouts()`, `:typecheck_tree_lookup_value()`)
- **Phase**: Type fact construction
- **Pattern**: Method installations
- **Clean mapping?** Should be part of `impl/tree_check.lua`
- **Needs refactoring?** Inline into impl/tree_check.lua

---

**9. `lua/lalin/tree_typecheck_layout.lua`** (43 lines)
- **Receiver types**: Minimal — layout methods on typecheck types
- **Phase**: Layout resolution (small, likely a stub)
- **Clean mapping?** Should be part of `impl/tree_check.lua`

---

**10. `lua/lalin/tree_control_facts.lua`** (473 lines)
- **Role**: Helper for typecheck — computes control flow facts (statement termination, reachability)
- **Receiver types**: No direct ASDL method installations — uses `schema.classof` dispatch with functional pattern
- **Phase**: Typecheck (control flow analysis)
- **Pattern**: `schema.classof` dispatch — **FORBIDDEN PATTERN**
- **Clean mapping?** Should be part of `impl/tree_check.lua` with proper leaf methods
- **Needs refactoring?** Yes — heavy `schema.classof` usage

---

**11. `lua/lalin/tree_contract_facts.lua`** (169 lines)
- **Role**: Helper for typecheck — computes contract facts (readonly, writeonly, etc.)
- **Receiver types**: Uses `schema.classof` dispatch, no method installations
- **Phase**: Typecheck (contract fact extraction)
- **Pattern**: `schema.classof` dispatch — **FORBIDDEN PATTERN**
- **Clean mapping?** Should be part of `impl/tree_check.lua`
- **Needs refactoring?** Yes — uses `schema.classof`

---

**12. `lua/lalin/const_eval.lua`** (608 lines)
- **Receiver types**: `Sem.ConstExprResult`, `Sem.ConstKnown`, `Sem.ConstStmtFlow`, `Sem.ConstFallsThrough`, `Sem.ConstValue`, `Sem.ConstInt`, `Sem.ConstBool` — all Sem union leaves
- **Phase**: Constant evaluation (part of typecheck)
- **Pattern**: Leaf method installations on Sem union types. Clean.
- **Clean mapping?** Should be part of `impl/tree_check.lua`
- **Needs refactoring?** Mostly clean, just needs to be inlined.

---

**13. `lua/lalin/tree_module_type.lua`** (365 lines)
- **Receiver types**: `Tr.ModuleHeader`, `Tr.ModuleTyped`, `Tr.ModuleSem`, `Tr.ModuleCode`, `Tr.ModuleSurface` (`:tree_module_name()`), `Ty.Type` leaf types (`:tree_module_canonicalize()`), `Tr.Func` leaf types (`:tree_module_func_entry()`), `Tr.ExternFunc`, `Tr.ConstItem`, `Tr.StaticItem`, `Tr.TypeDecl` leaf types, `Tr.Item` leaf types
- **Phase**: Module type environment construction
- **Pattern**: Leaf method installations on Tree and Type types. Clean ASDL method dispatch.
- **Clean mapping?** Should be part of `impl/tree_check.lua`
- **Needs refactoring?** Clean, just inline.

---

### LAYOUT & TREE→CODE LOWERING

---

**14. `lua/lalin/layout_resolve.lua`** (678 lines)
- **Receiver types**: `Tr.Expr` types, `Tr.Stmt` types, `Tr.Place` types, `Tr.Module` types (via `:sem_layout_resolve()`)
- **Phase**: Layout resolution (resolves memory layouts for types)
- **Pattern**: Uses `schema.with()`, closure-based `resolve_expr` dispatch; some `schema.classof` usage
- **Clean mapping?** Maps to layout methods on Tree types (part of tree_check or separate)
- **Needs refactoring?** Mixed — some method installations, some schema.classof

---

**15. `lua/lalin/tree_lower.lua`** (3067 lines) — **CRITICAL**
- **Receiver types**: **Tr.Module** leaf types (`:tree_code_module_name()`), **Core.Scalar** leaf types (`:tree_code_is_void_scalar()`), **Ty.Type** leaf types (`:tree_code_is_void_type()`, `:tree_code_source_access_base()`, `:tree_code_named_type_name()`, `:tree_code_index_elem_type()`), **Tr.TypeDecl** leaf types (`:tree_code_add_variant_defs()`), **Tr.ExprHeader/ExprTyped** (`:tree_code_expr_type()`), **Tr.PlaceHeader/PlaceTyped** (`:tree_code_place_type()`), **Tr.IndexBase** leaf types (`:tree_code_index_base_elem_type()`), **Code.CodeType** leaf types (`:tree_code_is_float_type()`, `:tree_code_is_aggregate_type()`, `:tree_code_is_view_type()`, `:tree_code_index_cast_op()`), **Bind.Binding** (`:tree_code_binding_key()`), **Bind.ValueRef** leaf types (`:tree_code_mark_addressed_binding()`, `:tree_code_lookup_binding()`, `:tree_code_lookup_value()`, `:tree_code_direct_call_target()`, `:tree_code_contract_value()`, `:tree_code_contract_place()`), **Bind.BindingRole** leaf types (`:tree_code_lookup_value()`, `:tree_code_direct_call_target()`, `:tree_code_global_place()`), **TL.TreeLowerInput** (`:tree_code_expr_result()`, `:tree_code_place_result()`, etc.)
- **Phase**: Tree→Code lowering (the main lowering pass)
- **Pattern**: **METHOD INSTALLATION FILE** — 3000+ lines of leaf methods on Tree, Type, Bind, Code, and TL types. Some uses of `unsupported()` error for missing overrides.
- **Clean mapping?** Maps to `impl/tree_code.lua` — :lower_to_code() on LalinTree types
- **Needs refactoring?** The Code.CodeType method installations (`tree_code_is_float_type` etc.) are on Code types but installed during tree_lower phase — these should move to impl/code_graph or similar. The Bind.* method installations should be on Bind types directly.

---

### CODE ANALYSIS PHASES

---

**16. `lua/lalin/code_validate.lua`** (840 lines)
- **Receiver types**: Code type validation — internal Machine wrapper with `:sig()`, `:data()`, `:global()`, `:func()`, `:extern()`, `:has_reloc()`, `:with_issue()`, `:with_reloc()`
- **Phase**: Code IR validation
- **Pattern**: Internal Machine object (mutable wrapper), not ASDL-based. Functions take `code_module` and return a report.
- **Clean mapping?** Maps to `impl/code_validate.lua` — :validate() on CodeModule types
- **Needs refactoring?** Yes — the Machine is a mutable context bag pattern. Should model validation state as ASDL products.

---

**17. `lua/lalin/code_graph.lua`** (396 lines) — **CRITICAL**
- **Receiver types**: **Code.CodePlace** leaf types (`:code_graph_append_uses()` — Deref, Index, Field, Bytes), **Code.CodeCallTarget** leaf types (`:code_graph_append_uses()` — Indirect, Closure), **Code.CodeInstOp** leaf types (`:code_graph_dst()`, `:code_graph_append_uses()` — Alias, Unary, variant leaves for Const, Binary, Cast, Load, Store, Call, Atomic, etc.)
- **Phase**: Graph construction (Code → Graph)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Code types for graph edges, uses, and params.
- **Clean mapping?** Maps to `impl/code_graph.lua` — :build_graph() on LalinCode types
- **Needs refactoring?** Clean leaf method dispatch. Good pattern.

---

**18. `lua/lalin/code_flow_facts.lua`** (555 lines) — **CRITICAL**
- **Receiver types**: Flow.FlowTripCount leaf types, Flow.FlowLoop leaf types, Flow.FlowCarrier leaf types, Flow.FlowLoopKind union — method installations for flow domain computation, loop classification, carrier step computation
- **Phase**: Flow fact computation (loop, carrier, trip count analysis)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Flow union types plus auxiliary FactSet construction functions.
- **Clean mapping?** Maps to `impl/code_flow.lua` — :compute_flow() on LalinGraph types (or on Flow fact types)
- **Needs refactoring?** Clean leaf method dispatch.

---

**19. `lua/lalin/code_value_facts.lua`** (625 lines) — **CRITICAL**
- **Receiver types**: **Core.BinaryOp** leaf types (`:code_value_int_expr()` — BinAdd, BinSub, BinMul, etc.), **Core.UnaryOp** leaf types, **Core.CmpOp** leaf types, **Code.CodeInstOp** leaf types, **Value.ValueExpr** leaf types
- **Phase**: Value fact computation (symbolic value expressions, arithmetic series, reductions)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Core operator types and Code inst types.
- **Clean mapping?** Maps to `impl/code_value.lua` — :compute_values() on LalinGraph types
- **Needs refactoring?** Clean leaf method dispatch.

---

**20. `lua/lalin/reduction_algebra.lua`** (212 lines)
- **Receiver types**: `Value.Reduction` leaf types (`:reduction_identity_value()`, `:reduction_apply()`)
- **Phase**: Value facts (reduction algebra — part of code_value)
- **Pattern**: Leaf method installations on Value.Reduction union.
- **Clean mapping?** Should be inlined into `impl/code_value.lua`

---

**21. `lua/lalin/code_mem_facts.lua`** (752 lines) — **CRITICAL**
- **Receiver types**: **Mem.MemProof** leaf types (`:code_mem_projection_index()`), **Mem.MemAccessProjection** (`:mem_access()`, `:object_for_access()`, `:backend_for_access()`, `:proof_for_access()`), code type method installations for memory access classification
- **Phase**: Memory fact computation (access projection, object tracking, proof indexing)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Mem types plus access projection.
- **Clean mapping?** Maps to `impl/code_mem.lua` — :compute_mem() on LalinGraph types
- **Needs refactoring?** Clean leaf method dispatch.

---

**22. `lua/lalin/code_effect_facts.lua`** (183 lines)
- **Receiver types**: Effect-related method installations, contract fact conversion to effect facts
- **Phase**: Effect fact computation (read/write/escape analysis from contracts)
- **Pattern**: Functional with `asdl.classof` dispatch on contract classes.
- **Clean mapping?** Maps to `impl/code_effect.lua` — :compute_effects() on LalinGraph types
- **Needs refactoring?** Contains `asdl.classof` dispatch on contract classes — needs leaf methods.

---

**23. `lua/lalin/code_kernel_plan.lua`** (1625 lines) — **CRITICAL**
- **Receiver types**: **Kernel.KernelPlan** leaf types (`:kernel_plan_rejects()`, `:select_kernel_loop_plan()`, etc.), **Kernel.KernelSkeletonSelection** leaf types (`:kernel_skeleton_effects()`, `:kernel_skeleton_result()`, `:kernel_skeleton_handles_dependences()`), **Kernel.KernelFunctionSkeletonSelection** leaf types (`:add_function_skeleton_plan()`), **Flow.FlowTripCount** leaf types (`:kernel_plan_closed_form_trip_unknown_proof()`), **Code.CodeConst** leaf types (`:kernel_carrier_const_amount()`), **Code.CodeInstOp** leaf types (`:kernel_carrier_note_def()`, `:kernel_carrier_const_amount()`, `:kernel_carrier_step_from_def()`), **Code.CodePlace** leaf types (`:kernel_address_base_available()`)
- **Phase**: Kernel plan (identifies loop candidates, maps to stencil kernels)
- **Pattern**: **METHOD INSTALLATION FILE** — rich leaf method dispatch on Kernel, Code, and Flow types.
- **Clean mapping?** Maps to `impl/kernel_plan.lua` — :plan_kernels() on fact set types
- **Needs refactoring?** Clean leaf method dispatch pattern. Good.

---

**24. `lua/lalin/code_schedule_plan.lua`** (180 lines)
- **Receiver types**: **Schedule.SchedulePlanInput** (`:select_kernel_schedule()`), **Schedule.SchedulePlanSelection** leaf types (`:to_kernel_schedule()`)
- **Phase**: Schedule plan (chooses schedule form — scalar/vector/closed-form)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Schedule types.
- **Clean mapping?** Maps to `impl/schedule_plan.lua` — :plan_schedules() on kernel plan types
- **Needs refactoring?** Clean.

---

**25. `lua/lalin/kernel_emit_support.lua`** (395 lines)
- **Helper file for schedule planning**: provides target capability checking, reject reason helpers, and kernel emission compatibility testing.
- **Receiver types**: No method installations — functional helpers only.
- **Clean mapping?** Should be inlined into `impl/schedule_plan.lua`

---

**26. `lua/lalin/kernel_validate.lua`** (261 lines)
- **Receiver types**: Validation logic for kernel plans — uses `asdl.classof` dispatch extensively
- **Phase**: Kernel validation
- **Pattern**: `asdl.classof` dispatch — **FORBIDDEN PATTERN**
- **Clean mapping?** Should be part of `impl/kernel_plan.lua` or a separate validate phase
- **Needs refactoring?** Yes — heavy `asdl.classof` usage

---

**27. `lua/lalin/code_lower_plan.lua`** (462 lines) — **CRITICAL**
- **Receiver types**: **Schedule.KernelSchedule** leaf types (`:lower_plan_fragment_candidate()`), **Kernel.KernelResult** leaf types (`:lower_plan_closed_form_fact()`), **Lower.LowerFragmentCandidate** leaf types (`:select_lower_fragment()`), **Lower.LowerFragmentSelection** leaf types (`:lower_plan_add_loop_fragment()`), **Flow.FlowCarrierTransfer** (`:lower_plan_matches_edge()`), **Flow.FlowCarrierThread** (`:lower_plan_transfer_for_edge()`, `:lower_plan_block_param()`, `:lower_plan_recompute_edge_source()`, `:lower_plan_edge_transfer()`, `:lower_plan_carrier()`), **Flow.FlowCarrierStep** leaf types (`:lower_plan_edge_source()`), **Kernel.KernelLane** (`:lower_plan_address_lane_use()`), **Kernel.KernelPlan/KernelPlanned** (`:lower_plan_address_lane_uses()`), **Flow.FlowAddressUse** (`:lower_plan_inst_use()`), **Flow.FlowAddressThread** (`:lower_plan_inst_uses()`, `:lower_plan_address()`), **Lower.LowerCarrierBlockParam** (`:lower_plan_address_block_param()`), **Lower.LowerCarrierEdgeSource** leaf types, **Lower.LowerCarrierEdgeTransfer**, **Lower.LowerCarrierPlan**
- **Phase**: Lower plan (selects lowering strategy per loop fragment)
- **Pattern**: **METHOD INSTALLATION FILE** — rich leaf method dispatch on Schedule, Kernel, Lower, and Flow types.
- **Clean mapping?** Maps to `impl/lower_plan.lua` — :plan_lowering() on code + graph + kernel types
- **Needs refactoring?** Clean method dispatch. But note: Flow.* methods installed during lower_plan phase — these are Flow type methods used by lowering.

---

**28. `lua/lalin/exec_plan.lua`** (224 lines)
- **Receiver types**: **Kernel.KernelPlan/KernelPlanned** (`:exec_kernel_plan_id()`), **Stencil.StencilSelection/StencilSelected** (`:select_exec_stencil()`, `:exec_plan_artifact()`, `:exec_plan_missing_artifact_reason()`), **Exec.ExecStencilSelection** leaf types (`:add_exec_stencil()`)
- **Phase**: Execution plan (maps kernel plans to concrete execution fragments)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Kernel, Stencil, and Exec types.
- **Clean mapping?** Maps to exec plan logic; may need its own impl/exec_plan.lua
- **Needs refactoring?** Clean leaf method dispatch.

---

### C EMISSION PHASES

---

**29. `lua/lalin/code_to_c.lua`** (1358 lines) — **CRITICAL**
- **Receiver types**: **Code.CodeType** leaf types (`:code_to_c_variant_payload_union_id()`, `:code_to_c_without_lease()`, `:code_to_c_view_elem_type()`, `:code_to_c_slice_elem_type()`), **Code.CodeConst** leaf types (`:lower_code_const_to_c_atom()`), **Code.CodePlace** leaf types (`:code_to_c_is_deref()`, `:lower_code_place_to_c()`, `:code_to_c_materialize_place()`), **Code.CodeValueId** (`:code_to_c_materialize_atom()`), **Code.CodeInstOp** leaf types (`:code_to_c_materialize_base_value()`), **Code.CodeGlobalRef** leaf types (`:lower_code_global_ref_to_c_name()`, `:lower_code_global_ref_to_c_sig()`, `:lower_code_global_ref_to_c_assign()`), **Code.CodeIntOverflow** leaf types, and many more C emission method installations
- **Phase**: Code→C materialization (emits C source from Code IR)
- **Pattern**: **METHOD INSTALLATION FILE** — extensive leaf method dispatch on Code types for C emission.
- **Clean mapping?** Maps to `impl/lower_emit_c.lua` — :emit_c() on LowerModule types (or on CodeModule types directly)
- **Needs refactoring?** Clean leaf method pattern but very large. Should be split by receiver type.

---

**30. `lua/lalin/emit_c_lower.lua`** (1415 lines) — **CRITICAL**
- **Receiver types**: **Core.Scalar** leaf types (`:c_emit_scalar_name()`), **Core.Literal** leaf types (`:c_emit_literal()`), **Core.CmpOp** leaf types (`:c_emit_cmp_op()`, `:c_helper_suffix()`), **Exec.ExecFragmentBody** leaf types (`:c_emit_exec_symbol()`, `:c_emit_exec_prototype()`), plus numerous type-declaration, function-emission, and atom/place/rvalue leaf methods on Core + C types
- **Phase**: C emission (generates C text from C IR — lower-level than code_to_c)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Core and Exec types for C emission.
- **Clean mapping?** Maps to `impl/cemit_emit.lua` — :emit_artifact() on CEmitMachine types (or `impl/lower_emit_c.lua` for the higher-level part)
- **Needs refactoring?** Clean leaf method pattern. Two levels of C emission (code_to_c for Code→C IR, emit_c_lower for C IR→C text).

---

**31. `lua/lalin/lower_to_c.lua`** (2437 lines) — **CRITICAL**
- **Receiver types**: **Schedule.ScheduleForm** leaf types (`:lower_emit_kernel_selection()`), **Lower.LowerStrategy** leaf types (`:lower_emit_candidate()`), **Lower.LowerEmitCandidate** leaf types (`:select_lower_emit()`), plus many Loop, Fragment, and Value-related method installations for C-specific lowering decisions
- **Phase**: Lower-to-C — combines lower plan + code module → CBackendUnit
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Schedule, Lower, and Kernel types for C emission routing.
- **Clean mapping?** Maps to `impl/lower_emit_c.lua` — :emit_c() on LowerModule types
- **Needs refactoring?** Clean leaf method dispatch but interleaves with code_to_c.

---

**32. `lua/lalin/emit_c_materialize.lua`** (259 lines)
- **Helper for lower_to_c**: materializes C values/places into C emission context
- **Clean mapping?** Inline into `impl/lower_emit_c.lua`

---

**33. `lua/lalin/lower_kernel_rewrite.lua`** (285 lines)
- **Receiver types**: `Value.Reduction` leaf types (`:display_name()`), `Stencil.StencilScan` leaf types (`:display_name()`)
- **Phase**: Kernel rewrite for C emission (replaces kernel-proven loop bodies with C IR)
- **Pattern**: Method installations + functional helpers
- **Clean mapping?** Inline into `impl/lower_emit_c.lua`

---

**34. `lua/lalin/emit_c_validate.lua`** (470 lines)
- **Receiver types**: C emission validation — validates CBackendUnit
- **Phase**: C validation
- **Pattern**: Functional — validates C IR produces proper C.
- **Clean mapping?** Inline into `impl/lower_emit_c.lua` or separate `impl/cemit_validate.lua`

---

**35. `lua/lalin/emit_c_coverage.lua`** (348 lines)
- **Receiver types**: C phase-unreachable variant tracking
- **Pattern**: Coverage tracking tables — functional, not method installation
- **Clean mapping?** Utility — keep as helper, not an impl/ file.

---

**36. `lua/lalin/emit_c_compile.lua`** (258 lines)
- **Role**: GCC runner — takes C text, compiles, dlopens, returns function pointers
- **Not an impl/ phase**: This is the runtime execution layer. Not ASDL method installation.
- **Clean mapping?** Keep as runtime. Not an impl/ file.

---

**37. `lua/lalin/emit_c_tcc.lua`** (365 lines)
- **Role**: TCC (Tiny C Compiler) runner for fast compilation
- **Not an impl/ phase**: Runtime execution.
- **Clean mapping?** Keep as runtime.

---

**38. `lua/lalin/emit_c_helpers.lua`** (3 lines)
- **Trivial**: Probably empty or re-export

---

### BACKEND PHASES (LuaJIT, Native)

---

**39. `lua/lalin/luajit_backend.lua`** (297 lines)
- **Role**: Backend driver — composes LuaJIT lowering + emission + stencil artifact planning
- **Phases**: LuaJIT backend (lowering → emission → bytecode/artifact)
- **Pattern**: Composition/driver; orchestrates Lower → Emit → StencilArtifactPlan modules
- **Clean mapping?** Maps to `impl/backend_emit.lua` with LuaJIT-specific lowering
- **Needs refactoring?** Clean composition pattern.

---

**40. `lua/lalin/luajit_lower.lua`** (2133 lines) — **CRITICAL**
- **Receiver types**: Code types, Value types, Stencil types, Mem types — method installations for LuaJIT-specific lowering
- **Phase**: LuaJIT lowering (Code IR → LuaJIT IR)
- **Pattern**: **METHOD INSTALLATION FILE** — extensive methods on Code/Value/Stencil types; uses `asdl.classof` dispatch heavily
- **Clean mapping?** Maps to LuaJIT-specific impl/ file (maybe `impl/luajit_lower.lua`)
- **Needs refactoring?** Yes — heavy `asdl.classof` usage

---

**41. `lua/lalin/luajit_emit.lua`** (1292 lines)
- **Receiver types**: Method installations for emitting LuaJIT bytecode/IR
- **Phase**: LuaJIT emission
- **Pattern**: Method installations + functional helpers
- **Clean mapping?** Inline into `impl/backend_emit.lua` or separate `impl/luajit_emit.lua`

---

**42. `lua/lalin/luajit_expr.lua`** (277 lines)
- **Receiver types**: LuaJIT-specific expression lowering helpers
- **Pattern**: Uses `asdl.classof` dispatch heavily
- **Needs refactoring?** Yes

---

**43. `lua/lalin/luajit_ctype.lua`** (375 lines)
- **Receiver types**: C type mapping for LuaJIT FFI
- **Pattern**: Functional helpers

---

**44. `lua/lalin/luajit_measure.lua`** (156 lines)
- **Role**: LuaJIT IR size measurement

---

**45. `lua/lalin/residual_luatrace.lua`** (1651 lines)
- **Receiver types**: LuaJIT bytecode trace emission
- **Phase**: LuaJIT bytecode artifact generation
- **Pattern**: Method installations + functional

---

**46. `lua/lalin/residual_bc.lua`** (118 lines)
- **Role**: LuaJIT bytecode helpers

---

**47. `lua/lalin/native_backend.lua`** (216 lines)
- **Role**: Backend driver — composes native, native_mc, native_code_methods, native_kernel_methods, native_stencil_methods
- **Phases**: Native backend (template source → machine code)
- **Pattern**: Composition/driver
- **Clean mapping?** Maps to `impl/backend_emit.lua`

---

**48. `lua/lalin/native.lua`** (1997 lines) — **CRITICAL**
- **Receiver types**: `Native.NativeAxis` leaf types, `Native.NativeCompileResult`, etc. — method installations for native bank operations
- **Phase**: Native bank operations (load, compile, patch, install)
- **Pattern**: **METHOD INSTALLATION FILE** — leaf methods on Native types
- **Clean mapping?** Maps to native-specific impl/ file

---

**49. `lua/lalin/native_code_methods.lua`** (3926 lines) — **CRITICAL**
- **Receiver types**: Code type → native template lowering (Code types → Native template IR)
- **Phase**: Code→Native lowering
- **Pattern**: **METHOD INSTALLATION FILE** — extensive methods on Code types
- **Clean mapping?** Maps to native-specific impl/ file

---

**50. `lua/lalin/native_kernel_methods.lua`** (1587 lines)
- **Receiver types**: Kernel type → native template lowering
- **Phase**: Kernel→Native lowering
- **Pattern**: **METHOD INSTALLATION FILE**

---

**51. `lua/lalin/native_stencil_methods.lua`** (976 lines)
- **Receiver types**: Stencil type → native template lowering
- **Phase**: Stencil→Native lowering
- **Pattern**: **METHOD INSTALLATION FILE**

---

**52. `lua/lalin/native_template_sources.lua`** (6674 lines)
- **Role**: Native C template source strings — data, not implementation logic
- **Pattern**: Data file (template source code)

---

**53. `lua/lalin/native_template_support.lua`** (2006 lines)
- **Role**: Native template support — parsing, validation, source decomposition

---

**54. `lua/lalin/native_mc.lua`** (1164 lines)
- **Receiver types**: Native machine-code operations — patching, assembly, code generation
- **Pattern**: **METHOD INSTALLATION FILE** on Native types

---

**55. `lua/lalin/native_object.lua`** (397 lines)
- **Receiver types**: `Native.NativeTemplateBytes` (`:parse_native_object()`)
- **Pattern**: Method installation

---

### STENCIL PHASES

---

**56. `lua/lalin/stencil_artifact_plan.lua`** (2767 lines) — **CRITICAL**
- **Receiver types**: **Code.CodeTy** leaf types (`:stencil_artifact_type_name()`, `:stencil_artifact_c_type()`, `:stencil_artifact_is_code_scalar()`, etc.), **Value.Reduction** leaf types (`:stencil_artifact_name()`), **Code.CodeType** leaf types (`:stencil_artifact_is_int()`, `:stencil_artifact_is_integer_like()`, `:stencil_artifact_is_float()`), plus many Stencil, Schedule, Kernel, and Mem type method installations
- **Phase**: Stencil artifact planning (generates stencil artifacts for different backends)
- **Pattern**: **METHOD INSTALLATION FILE** — extensive leaf methods on Code, Value, Stencil, Schedule, Kernel, and Mem types.
- **Clean mapping?** Cross-cutting — methods span multiple receiver modules. Should be split across multiple impl/ files by receiver type.

---

**57. `lua/lalin/stencil_methods.lua`** (931 lines)
- **Receiver types**: **SM.StencilMachinePointInput** leaf types (`:point_ty()`, `:point_elem_ty()`, `:point_layout()`, `:point_role()`, `:point_is_primary()`, etc.), **Code.CodeConst/CodeConstLiteral** (`:stencil_const_int()`), **Value.ValueExpr/ValueExprConst** (`:stencil_const_int()`, `:stencil_const_ty()`), **Core.UnaryOp** leaf types (`:stencil_unary_op()`), **Core.BinaryOp** leaf types (`:stencil_binary_op()`), **Code.CodeType** leaf types (`:stencil_supported_type()`)
- **Phase**: Stencil method definitions (type classification for stencil planning)
- **Pattern**: **METHOD INSTALLATION FILE** — clean leaf methods on SM, Code, Value, and Core types.
- **Clean mapping?** Should be split: SM methods → impl/stencil_machine.lua, Code/Value/Core methods → phase-specific impl/ files

---

**58. `lua/lalin/stencil_metastencil.lua`** (743 lines)
- **Receiver types**: `Stencil.StencilDescriptor` (`:metastencil_access_named()`), `Stencil.StencilReduceScope` leaf types (`:metastencil_dst_name()`)
- **Phase**: Metastencil (stencil composition/instantiation)
- **Pattern**: **METHOD INSTALLATION FILE**

---

**59. `lua/lalin/stencil_c.lua`** (1554 lines)
- **Receiver types**: C-specific stencil emission
- **Phase**: Stencil C artifact generation
- **Pattern**: Method installations + functional

---

### COMPILER COMPOSITION / INFRASTRUCTURE

---

**60. `lua/lalin/init.lua`** (936 lines)
- **Role**: Public facade for Lalin. Exposes all modules. Contains `loadstring`, `loadfile`, `compile_c_gcc`, `compile`, etc.
- **Not an impl/ phase**: Public API.

---

**61. `lua/lalin/compiler_driver.lua`** (41 lines)
- **Role**: Public `lower_module` entrypoint using compiler_package + phase_plan + phase_execute
- **Not an impl/ phase**: Public API.

---

**62. `lua/lalin/compiler_package.lua`** (111 lines)
- **Role**: Defines compiler worlds, machines, phases, and roots in DSL syntax for PhasePlan
- **Not an impl/ phase**: Public API.

---

**63. `lua/lalin/compiler_machines.lua`** (71 lines)
- **Role**: Machine implementations for compiler_package (hosted_typecheck, hosted_checked_to_c_code, hosted_c_code_to_c)
- **Not an impl/ phase**: Wire-up code.

---

**64. `lua/lalin/compiler_model.lua`** (19 lines)
- **Role**: Requires LalinCompiler schema into context T
- **Not an impl/ phase**: Schema loading.

---

**65. `lua/lalin/compiler_abi.lua`** (96 lines)
- **Receiver types**: CodeResult validation
- **Phase**: ABI boundary validation
- **Clean mapping?** Maps to `impl/compiler_result.lua`

---

**66. `lua/lalin/backend_target_model.lua`** (70 lines)
- **Role**: Default target model construction (native, host)
- **Not an impl/ phase**: Factory/helper.

---

**67. `lua/lalin/code_type.lua`** (533 lines)
- **Role**: Code type helpers — type_to_code conversion, type classification, C target defaults
- **Pattern**: Functional helpers (no method installations on ASDL types unless called indirectly)
- **Clean mapping?** Utility — should be inlined into relevant impl/ files or kept as shared helpers.

---

**68. `lua/lalin/type_size_align.lua`** (286 lines)
- **Role**: Size/alignment computation for types
- **Pattern**: Functional helpers

---

**69. `lua/lalin/type_classify.lua`** (180 lines)
- **Role**: Type classification (uses `schema.classof`)
- **Pattern**: `schema.classof` — **FORBIDDEN**

---

**70. `lua/lalin/type_abi_classify.lua`** (148 lines)
- **Role**: ABI classification for types
- **Pattern**: `schema.classof` — **FORBIDDEN**

---

**71. `lua/lalin/type_to_backend_scalar.lua`** (132 lines)
- **Role**: Type → backend scalar conversion

---

**72. `lua/lalin/core_scalar.lua`** (184 lines)
- **Role**: Core scalar methods (uses `schema.classof` dispatch)
- **Pattern**: `schema.classof` — **FORBIDDEN**

---

**73. `lua/lalin/core_operator.lua`** (225 lines)
- **Role**: Core operator classification (uses `schema.classof` dispatch)
- **Pattern**: `schema.classof` — **FORBIDDEN**

---

**74. `lua/lalin/switch_decide.lua`** (111 lines)
- **Role**: Switch decision helpers

---

**75. `lua/lalin/func_abi_plan.lua`** (80 lines)
- **Role**: Function ABI planning

---

**76. `lua/lalin/code_aggregate_abi.lua`** (154 lines)
- **Role**: Aggregate ABI helpers

---

**77. `lua/lalin/value_proxy.lua`** (178 lines)
- **Role**: Value proxy helpers

---

**78. `lua/lalin/triplet.lua`** (1179 lines)
- **Role**: Triplet (architecture tuple) database

---

**79. `lua/lalin/quote.lua`** (153 lines)
- **Role**: Code quoting helpers

---

**80-99. Phase/link/source/other infrastructure files**:
- `phase_dsl.lua` (432), `phase_execute.lua` (222), `phase_model.lua` (23), `phase_plan.lua` (279), `phase_validate.lua` (292) — Phase infrastructure (NOT impl/ targets)
- `link_command_plan.lua` (156), `link_execute.lua` (99), `link_plan_validate.lua` (171), `link_target_model.lua` (49) — Link infrastructure
- `source_anchor_index.lua` (154), `source_position_index.lua` (221), `source_text_apply.lua` (167), `source_analysis.lua` (59) — Source utilities
- `project_asdl.lua` (23), `project_ready_facts.lua` (121), `project_report.lua` (87) — Project utilities
- `schema_context.lua` (865), `schema_emit_types.lua` (141), `schema_projection.lua` (22), `schema_projection_model.lua` (142), `schema_runtime.lua` (70), `schema_types.lua` (78), `context_define_schema.lua` (126) — Schema infrastructure
- `asdl.lua` (575), `ast.lua` (1131), `loader.lua` (151), `store.lua` (210), `exotype.lua` (362), `cli.lua` (72) — Framework/support
- `bind_machine_binding.lua` (78), `bind_residence_decide.lua` (121), `bind_residence_gather.lua` (629) — Bind utilities

---

## Key Code: Critical Method Installation Files by Proposed impl/ Target

| Proposed impl/ file | Old file(s) | Receiver types | Clean? |
|---|---|---|---|
| `impl/tree_surface.lua` | `surface_resolve.lua` | Ty.Type leaves, Tr.ModuleHeader leaves | Recursive walk with classof |
| `impl/tree_closure.lua` | `closure_convert.lua` | Ty.Type leaves, B.ValueRef leaves | Leaf methods + helpers |
| `impl/tree_check.lua` | `tree_typecheck.lua` + all sub-files (`tree_typecheck_type/expr/stmt/fact/layout.lua`, `tree_control_facts.lua`, `tree_contract_facts.lua`, `const_eval.lua`, `tree_module_type.lua`) | Tr.*, Ty.*, Core.Scalar, Sem.*, B.* | Some classof dispatch |
| `impl/tree_code.lua` | `tree_lower.lua` (3067 lines) | Tr.*, Ty.*, Core.Scalar, Code.*, Bind.*, TL.* | Clean leaf methods |
| `impl/code_graph.lua` | `code_graph.lua` | Code.CodePlace leaves, Code.CodeCallTarget leaves, Code.CodeInstOp leaves | Clean |
| `impl/code_flow.lua` | `code_flow_facts.lua` | Flow.* types | Clean |
| `impl/code_value.lua` | `code_value_facts.lua`, `reduction_algebra.lua` | Core.BinaryOp/UnaryOp/CmpOp leaves, Value.Reduction leaves | Clean |
| `impl/code_mem.lua` | `code_mem_facts.lua` | Mem.* types | Clean |
| `impl/code_effect.lua` | `code_effect_facts.lua` | Effect.* types, contract conversion | classof on contracts |
| `impl/kernel_plan.lua` | `code_kernel_plan.lua` (1625 lines) | Kernel.*, Code.*, Flow.* | Clean |
| `impl/schedule_plan.lua` | `code_schedule_plan.lua`, `kernel_emit_support.lua` | Schedule.* types | Clean |
| `impl/lower_plan.lua` | `code_lower_plan.lua` | Schedule.*, Kernel.*, Lower.*, Flow.* | Clean |
| `impl/lower_emit_c.lua` | `lower_to_c.lua` (2437 lines), `code_to_c.lua` (1358 lines), `emit_c_materialize.lua`, `lower_kernel_rewrite.lua` | Code.*, Lower.*, Schedule.*, Kernel.*, Flow.* | Clean leaf methods, very large |
| `impl/cemit_emit.lua` | `emit_c_lower.lua` (1415 lines) | Core.Scalar/Literal/CmpOp leaves, Exec.* leaves, C types | Clean |
| `impl/code_validate.lua` | `code_validate.lua` | Code.* validation (Machine pattern) | Machine context bag |
| `impl/backend_emit.lua` | `luajit_backend.lua`, `native_backend.lua` + all sub-files | Backend-specific types | Varies |
| `impl/compiler_result.lua` | `compiler_abi.lua` | CodeResult validation | Clean |

---

## Observations

1. **The pipeline is functional and well-structured**: `frontend_pipeline.lua` provides a clean composition layer. Each phase module is a `bind_context(T)` function that installs methods on ASDL types. The `T._lalin_api_cache` pattern provides lazy singleton memoization.

2. **Method installation is the dominant pattern**: The vast majority of implementation files install leaf methods on ASDL union types. This aligns perfectly with the proposed impl/ organization.

3. **Forbidden patterns exist in specific areas**:
   - `tree_control_facts.lua` and `tree_contract_facts.lua` use `schema.classof` dispatch
   - `const_eval.lua` uses manual handlers internally
   - `code_effect_facts.lua` uses `asdl.classof` on contract types
   - `kernel_validate.lua` uses `asdl.classof` extensively
   - `luajit_lower.lua` uses `asdl.classof` heavily
   - Several helper files (`core_scalar.lua`, `core_operator.lua`, `type_classify.lua`, `type_abi_classify.lua`) use `schema.classof`

4. **Code.CodeType methods are scattered across phases**: Methods like `tree_code_is_float_type()` (in tree_lower.lua), `stencil_artifact_type_name()` (in stencil_artifact_plan.lua), `code_to_c_variant_payload_union_id()` (in code_to_c.lua), and `stencil_supported_type()` (in stencil_methods.lua) are all on Code.CodeType but installed by different phase files. The proposed impl/ files should group these by receiver module.

5. **Massive files need splitting**: `tree_lower.lua` (3067 lines), `stencil_artifact_plan.lua` (2767 lines), `lower_to_c.lua` (2437 lines), `luajit_lower.lua` (2133 lines), `native_code_methods.lua` (3926 lines), `native_template_sources.lua` (6674 lines). The proposed impl/ scheme will help but some files install methods across multiple receiver modules.

6. **The `CodeType` receiver is the most overloaded**: Methods on Code.CodeType are installed by: `tree_lower.lua`, `code_to_c.lua`, `stencil_artifact_plan.lua`, `stencil_methods.lua`, `code_kernel_plan.lua`. A single `impl/code_type_methods.lua` might be needed.

7. **Schema infrastructure files are NOT impl/ targets**: `schema_context.lua`, `schema_projection.lua`, `schema_runtime.lua`, `schema_types.lua`, `context_define_schema.lua`, `asdl.lua` are the ASDL runtime and should remain as infrastructure.

8. **Phase infrastructure is separate**: `phase_dsl.lua`, `phase_execute.lua`, `phase_model.lua`, `phase_plan.lua`, `phase_validate.lua` implement the compiler package/phase/machine protocol. These are NOT impl/ targets.

9. **Backend-specific files are large but follow the same pattern**: LuaJIT (`luajit_lower.lua`, `luajit_emit.lua`) and Native (`native_code_methods.lua`, `native_kernel_methods.lua`, `native_stencil_methods.lua`) backends install methods on Code/Kernel/Stencil types specific to each backend. These map to separate impl/ files per backend.

10. **`stencil_artifact_plan.lua` is cross-cutting**: It installs methods on Code, Value, Stencil, Schedule, Kernel, Mem, and other types for artifact planning. This would need to be split across multiple impl/ files by receiver module.
