# Canonical Schema-v2 Gap Analysis

Status: binding pre-implementation analysis for the canonical migration.

## Conclusion

The migration cannot proceed by reconnecting canonical code to the old compiler. The current schema-v2 model is incomplete at several phase boundaries, while focused tests mostly prove isolated constructors and leaf methods. The public C/GCC path remains green because it still executes old frontend, region, kernel, inline CMat, and semantic-emission implementations.

Old code is frozen behavioral evidence only. No new implementation may import, invoke, wrap, alias, or extend the old typechecker, region expander, kernel planner, inline CMat path, or lowerer. Missing semantics must first be named in schema-v2, then implemented on canonical concrete leaves.

## Observed architecture

There are currently two compiler ownership islands:

1. `lua/lalin/schema/init.lua` builds the old schema and installs `TreeCodeCanonicalImplementation`, which calls `surface_resolve.lua`, `closure_convert.lua`, `tree_typecheck.lua`, `tree_lower.lua`, and `compiler_canonical_c_backend.lua`.
2. `lua/lalin/schema_v2/init.lua` creates a separate singleton context, patches `package.loaded`, and installs `TreeCodeSchemaV2Implementation`. Its implementations live under `lua/lalin/impl/`.

The main schema-v2 bootstrap still imports old `LalinHost` and excluded `LalinLuaJIT`; it loads `stencil_machine.lua`, which carries LuaJIT values into the supposedly neutral main schema. `schema_v2/phase.lua` is currently an alias to the old phase declaration. These are ownership violations, not acceptable final wiring.

The failed `OWN-FRONT` attempt demonstrated that deleting old declarations before semantic parity leaves casts, fields, regions, variant bindings, and layout decisions unconsumed. Reconnecting the old typechecker would only conceal the missing canonical model.

## Schema-v2 gaps

### 1. Canonical bootstrap and frontend vocabulary

Schema-v2 is not yet a closed main-C vocabulary.

Missing or divergent frontend alternatives include:

- `StmtVariantSwitchSource` and its parsed variant-arm source shape are present only in the old tree schema.
- `TypeIssueVariantBindCount` is present only in the old check schema.
- phase/project/exec ownership is split or aliased rather than declared once canonically.
- main schema-v2 imports excluded LuaJIT stencil-machine declarations.

Required schema work:

- Add the missing parsed-source and diagnostic alternatives directly to schema-v2.
- Give phase/project/exec one real canonical declaration; remove the alias.
- Split excluded LuaJIT/native schema profiles from the canonical main-C bootstrap.
- Retain `LalinHost` only as an explicit, non-duplicated platform boundary.
- Add a schema guard that canonical main-C modules cannot reference `LalinLuaJIT`, LuaTrace, native stencil values, or old frontend namespaces.

### 2. Region semantics

The existing region vocabulary names definitions, protocols, seals, bundles, wires, expansion input, splice, and reject leaves. It does not name the immutable state and projections required to implement complete expansion. The old implementation fills the gap with mutable arrays, callbacks, searches, and helper-local scope conventions.

Required schema additions:

- `RegionProtocolKey` and typed protocol contribution/lookup alternatives.
- `RegionFactProjection` containing definitions, protocols, seals, and bundles as named relations.
- definition, seal, continuation, and wire lookup result unions.
- `RegionCallCaptureEntry` and `RegionCallCaptureProjection` for captured wire arguments.
- `RegionStmtExpansionInput/Result` carrying the narrow statement input, active region identity, emitted statements, additional blocks, next typed statement input, and issues.
- `RegionBodyExpansionInput/Result` for immutable sequential scope threading.
- `RegionBlockExpansionInput/Result` for entry/block parameters and lexical isolation.
- `RegionModuleExpansion` success/rejection alternatives, so expanded control is an explicit projection rather than a convention inside typecheck.

Concrete statement, wire-target, continuation, protocol, seal, and bundle leaves must own the operations. No callback such as `add_capture`, mutable `extra_blocks`, string protocol table, or nil lookup is allowed.

### 3. Kernel analysis

`KernelModulePlanRequest` currently carries flow/value/memory/effect facts but not the `CodeModule` or `CodeGraph` required to relate loops to instructions and functions. `KernelLoopPlanRequest` accepts lanes, bindings, effects, and proofs, but `plan_kernels()` always constructs it with four empty arrays. Consequently focused candidate tests pass while real kernel facts are absent.

Required schema changes:

- Add `CodeModule` and `CodeGraph` to the module planning request.
- Add `KernelLoopAnalysisInput` naming the function graph, loop, flow facts, value facts, memory facet, and effect facet needed for one loop.
- Add named lane-by-access, binding-by-code-value, effect-by-instruction, and proof contribution entries/projections with typed lookup unions.
- Add `KernelLoopAnalysis = Ready | Rejected`; `Ready` owns a complete `KernelLoopPlanBuild`.
- Replace optional counter/accumulator fields with explicit counter and rewrite alternatives.
- Represent copy, scan, reduction, find, all, all-compare, scatter, and original-control selection as concrete typed alternatives, not an enum-like kind plus externally interpreted payload.

A kernel plan is acceptable only when end-to-end fixtures assert its non-empty lanes/bindings/effects/proofs where semantically required and prove no cross-loop contamination.

### 4. Kernel-to-stencil/CMat projection

The canonical stencil schema has useful producer, window-boundary, point-expression, sink, and computation vocabulary. However, no active method projects `KernelPlanned` plus schedule/memory facts into a `StencilComputation`. Existing CMat tests construct standalone computations directly.

The stencil schema also contains substantial optional soup: optional producer bounds, indexes, arithmetic modes, strides, schedules, accesses, results, graph links, and semantic booleans such as readonly/unit-stride/reassociation. These fields must not become the basis of the canonical bridge.

Required schema work for the main C path:

- `StencilKernelProjectionInput` with the planned kernel, selected schedule, code/graph facts, memory lanes, and target-neutral proofs.
- `StencilKernelProjection = ProjectedComputation | RejectedKernel` with precise reject leaves.
- Explicit producer-bound, index, arithmetic-semantics, stride, access-capability, and reassociation alternatives replacing option/boolean clusters used by this path.
- Reuse the existing window-boundary and point-expression sums; do not recreate old inline Lua records.

### 5. CMat fragment emission

Current schema-v2 CMat materializes and emits a standalone `CBackendUnit`. The public semantic path requires a typed fragment that replaces selected blocks inside an existing function. The old `CMatInline*` vocabulary must not be copied as loose compatibility state, but the underlying concepts need canonical names.

Required schema additions:

- `CMatCFragmentInput` containing the materialized kernel, owning function, lower cover, target, carrier/address projections, and validated C signature/value relations.
- `CMatCFragmentEmission = Emitted | Rejected`.
- The emitted leaf carries replacement CBackend blocks, locals, helpers, block mappings, value/result mappings, and control-result mapping as named ASDL products.
- Typed window-index and boundary decisions that emit clamp/wrap/zero/reject behavior from `StencilWindowBoundary` leaves.
- Typed store, fold, scan, all, all-compare, any, and find result alternatives.

Standalone CMat-to-unit emission may remain a distinct artifact boundary, but it cannot substitute for fragment emission.

### 6. Lower-plan consumption

`LowerModule` stores per-function fragments and selected `LowerStrategy` values. `impl/lower_emit_c.lua` ignores them and lowers every `CodeFunc` directly. `schedule_form.lua` therefore contains dead selection methods and several forbidden nil/multiple-result protocols.

Required schema changes:

- `LowerFunctionPlanEntry/Projection/Lookup` to resolve one function plan.
- `LowerFragmentEmissionInput` carrying the lower spine, function, fragment, and canonical target.
- `LowerFragmentEmission` alternatives for ordinary code, closed form, kernel/CMat, and typed rejection.
- `LowerFunctionEmissionState/Result` for immutable fragment composition and coverage.
- `LowerCModuleInput` carrying `LowerModule`, `CodeModule`, `CodeGraph`, and the exact `CBackendTarget`.
- Typed carrier/address lookup and place-resolution alternatives replacing nil/error pairs.

`LowerStrategyCode`, `LowerStrategyClosedForm`, and `LowerStrategyKernel` concrete leaves must perform emission dispatch. A test must prove that changing the selected strategy changes the emitted CBackend structure.

### 7. C target propagation

A typed `CompilerCStageInput` already exists, but the target is dropped when code results enter schema-v2 C lowering. `LowerModule:lower_c_module` hard-codes C99/64-bit/little-endian/hosted. `CompilerSession` independently hard-codes another target. The `CBackendTarget` product also duplicates platform meaning with a `hosted` boolean.

Required schema work:

- `CompilerCCodegenRequest { result, target }` as the semantic C code-generation boundary.
- `LowerCModuleInput` as described above; no option table or default target.
- Replace the target `hosted` boolean with platform/capability leaf behavior or an explicit platform alternative if additional distinction is real.
- Dialect/platform leaves own target-feature decisions such as C11 atomics.
- Validation consumes the exact target embedded in the emitted unit.

The original public `Decl:lower` C11 request must preserve identity through phase execution, lower planning, emission, and validation.

## Canonical target pipeline

The intended canonical object chain is:

```text
Canonical source module
  -> SurfaceResolutionResult
  -> ClosureConvertResult
  -> TypeModuleResult
  -> RegionModuleExpansion
  -> LayoutProjection
  -> TreeCodeModuleResult
  -> CodeValidationResult
  -> AnalysisBundle(graph, flow, value, memory, effect)
  -> KernelModulePlan
  -> ScheduleModulePlan
  -> StencilKernelProjection
  -> CMatMaterialization
  -> LowerModule
  -> LowerCModuleInput:emit()
       LowerStrategyCode   -> ordinary typed Code-to-C fragment
       LowerStrategyKernel -> typed CMat fragment
       LowerStrategyClosedForm -> typed closed-form fragment
  -> CBackendValidationReport
  -> CEmit artifact
```

Every arrow has an ASDL receiver, named ASDL input, and named ASDL result. IO/process code may catch failures, but semantic methods do not return loose records, nil protocols, or multiple values.

## Required implementation order

Implementation must not begin at the old behavior files. The order is:

1. **V2-BOOT-SCHEMA** — close the canonical bootstrap; add missing frontend leaves; remove profile contamination and aliases.
2. **V2-REGION-SCHEMA** and **V2-TARGET-SCHEMA** — define region projections/results and typed target/codegen requests.
3. **V2-KERNEL-SCHEMA** — define complete loop-analysis projections/results.
4. **V2-STENCIL-CMAT-SCHEMA** — normalize main-path alternatives and define kernel-to-stencil plus CMat-fragment vocabulary.
5. **V2-LOWER-SCHEMA** — define function/fragment emission projections and target-carrying module input.
6. Run constructor, forbidden-import, optional-soup, and schema-ownership tests. No semantic implementation package starts before these schema gates pass.
7. Implement canonical region leaves and typed target propagation.
8. Implement kernel projection, kernel-to-stencil projection, CMat fragment emission, then lower-fragment consumption in that dependency order.
9. Run canonical-only end-to-end tests in fresh processes that load schema-v2 and assert forbidden old modules were never loaded.
10. Only then resume ownership deletion and public cutover.

## Acceptance and anti-shortcut gates

Before any ownership cutover:

- Canonical tests must start from the schema-v2 bootstrap and execute the full C/GCC path.
- A forbidden-import test must reject canonical implementation dependencies on `tree_typecheck.lua`, `tree_typecheck_stmt.lua`, `tree_typecheck_fact.lua`, `code_kernel_plan.lua`, `lower_to_c.lua`, old CMat implementation modules, and old frontend schema namespaces.
- Main-C schema tests must prove no `LalinLuaJIT`, LuaTrace, or native descriptor dependency.
- Schema tests must reject newly introduced optional/boolean protocol soup in the region/kernel/stencil/CMat/lower path.
- End-to-end fixtures must inspect intermediate ASDL values, not only final runtime numbers.
- Old code receives no fixes or new semantics. It is removed only after canonical tests establish parity and consumer scans reach zero.

## Current status correction

`KRN-CANON` now produces real typed lanes, bindings, effects, counters, results, proofs, and rejects. End-to-end analysis of the next bridge disproved the prior claim that its schema was complete. `KernelBody` does not retain an exact iteration projection (step, stop convention, and index type), `StencilKernelProjectionInput` requires an already-converted `StencilSchedule` instead of accepting the canonical selected `LalinSchedule.KernelSchedule`, and the bridge has no immutable ASDL construction state/contribution results for accumulating accesses, streams, sinks, and rejects. `V2-KERNEL-STENCIL-BRIDGE` is therefore reopened as lead-owned schema work. `KERNEL-STENCIL-CANON` remains blocked; these facts must not be encoded with Lua tables, semantic nil, or hardcoded producer/schedule values.
