# Lalin Compiler Completion and ASDL Migration — Master Plan

> **Status:** Single source of truth for compiler completion, regression repair, and the clean ASDL + leaf-method migration.
> **Baseline:** `8630bc808` (2026-07-10).
> **Primary path:** parsed `.lln` / builder declarations → typed ASDL → Code facts → `CBackendUnit` → `emit_c` → GCC.
> **Authority:** `docs/ASDL_GUIDE.md` is binding. `docs/LANGUAGE_REFERENCE.md` defines the promised language surface.
> **Historical input:** `docs/SCHEMA_V2_MIGRATION_GAP.md` is an older assessment, not the current tracker.

## How to Use This Plan

This file is the distribution and tracking authority for all pack work.

- The pack lead assigns work-package IDs from this file.
- Workers must report branch/base, files changed, checks run, blockers, and readiness to integrate.
- Mark `[x]` only after the acceptance checks pass on the integration branch.
- Use `[~]` only while a package has an active owner; return it to `[ ]` if work stops.
- Add newly discovered work under the owning package; do not create parallel private roadmaps.
- Do not edit or rely on `.pi/workflows/*` for this program.
- Do not add compatibility shims, generic context bags, semantic side tables, manual variant dispatch, or ad hoc result records.
- Schema changes precede semantic implementation changes whenever the current ASDL vocabulary cannot express the contract.
- Public IO/process option tables are boundary plumbing; compiler facts and decisions are not.

## Definition of Done

- [ ] Every supported `docs/LANGUAGE_REFERENCE.md` feature has a parsed `.lln` end-to-end test.
- [ ] Applicable tests exercise parsing → typed ASDL → Code IR → C emission → GCC execution.
- [ ] Builder DSL and HostEval paths converge on the same typed compiler pipeline.
- [ ] Semantic dispatch belongs to concrete ASDL leaves, with typed inputs and typed results.
- [ ] No semantic facts live in Lua node/string-keyed side tables or ad hoc records.
- [ ] Unsupported surface forms produce deterministic typed diagnostics.
- [ ] The default suite is green.
- [ ] Slow and experimental-backend tests are classified and green in their declared profiles.
- [ ] Documentation describes tested behavior rather than intended behavior.

## Status Snapshot

### Completed reconnaissance

- [x] Read `docs/ASDL_GUIDE.md` completely and audit schema/method ownership.
- [x] Read `docs/LANGUAGE_REFERENCE.md` completely and build a feature coverage matrix.
- [x] Audit implementation anti-patterns in compiler/backend paths.
- [x] Capture default, slow, frontend, schema, code-IR, compiler-process, and C-backend baselines.
- [x] Identify the region expansion constructor crash root cause.

### Test baseline at `8630bc808`

| Profile | Result |
|---|---|
| `luajit tests/run.lua` | 89 passed, 1 skipped, 46 failed |
| `LALIN_RUN_SLOW=1 luajit tests/run.lua` | 89 passed, 47 failed |
| `luajit tests/run.lua frontend` | 12 passed, 1 failed |
| `luajit tests/run.lua schema` | 9 passed, 1 failed |
| `luajit tests/run.lua code_ir` | 31 passed, 1 skipped, 26 failed |
| `luajit tests/run.lua compiler_process` | 4 passed, 3 failed |
| C backend | 9 passed, 12 failed |

Healthy focused C checks include `test_emit_c_compile.lua`, `test_emit_c_lower.lua`, `test_emit_c_validate.lua`, `test_emit_c_tcc.lua`, parsed extern, and parsed union emission.

## Milestone 0 — Failure Ledger and Reproducible Baseline

### M0.1 Failure classification

- [ ] Record every baseline failure under exactly one root-cause cluster.
- [ ] Classify each cluster as main compiler regression, incomplete advertised feature, experimental backend, obsolete test, or harness defect.
- [ ] Give every cluster one minimal focused reproducer.
- [ ] Record tests unblocked when a cluster lands.
- [ ] Ensure experimental native work is not described as the default backend.

### M0.2 Regression gates

- [ ] Preserve the healthy scalar GCC path throughout the program.
- [ ] Prevent focused tests from depending on unrelated broken stages.
- [ ] Run the relevant category suite after each package.
- [ ] Run the default suite after each integration merge.
- [ ] Run the slow profile when binary/native or long-running behavior changes.

## Milestone 1 — Restore Broken Main-Path Infrastructure

### RGN-1 — Region invocation expansion

**Status:** integrated at `82ec214af`; independently approved.
**Scope:** `lua/lalin/tree_typecheck_stmt.lua`, region-focused tests.
**Root cause:** commit `c5c1e3cbe` deleted `expansion_input_for_entry`, `expansion_input_for_block`, and `append_splice_blocks`. Missing globals resolve as tables and corrupt the typed input. `RegionInvokeExpandInput.scope [TypeValueScope]` is already correct.

- [x] Verify `lua/lalin/schema/tree.lua:201-204` requires `TypeValueScope`.
- [x] Verify calls at `tree_typecheck_stmt.lua:718,728` should pass a real `stmt_input.scope`.
- [x] Restore `expansion_input_for_entry`.
- [x] Restore `expansion_input_for_block`.
- [x] Restore `append_splice_blocks`.
- [x] Keep the existing narrow `RegionInvokeExpandInput` schema.
- [x] Do not weaken the constructor or coerce plain tables.
- [x] Pass `tests/code_ir/test_region_expansion_helpers.lua`.
- [ ] Pass `tests/code_ir/test_region_emit_expansion.lua` (now reaches missing `StencilMachineSkeletonInput`).
- [ ] Pass `tests/c_backend/test_emit_c_region_main.lua` (now reaches LAY-1).
- [ ] Pass `tests/c_backend/test_emit_c_region_call.lua` (now reaches LAY-1).
- [x] Add entry-parameter, block-parameter, nested-splice, and sealed-call coverage.
- [ ] Add parsed `.lln` → C → GCC runtime coverage.

### STN-1 — Stencil semantic construction

**Status:** integrated at `35c1ce5a3`; independently approved.
**Failure cluster:** stale semantic parents and missing local helper capture in `lua/lalin/stencil_artifact_plan.lua`.

- [x] Replace nonexistent semantic parents with concrete `StencilStoreSemantics` and `StencilReductionSemantics` leaf ownership.
- [x] Attach defaults to canonical `StencilAccessLayout` and `StencilAlignmentFact` parents.
- [x] Repair local typed validator capture without global-table fallback.
- [x] Repair construction without nil defaults or option bags.
- [x] Pass `tests/schema/test_schema_stencil.lua`.
- [x] Pass the full schema suite (10/10).
- [x] Pass focused ND scan rejection and native stencil checks.
- [ ] Restore remaining LuaJIT/stencil tests (blocked by STN-SCHED and missing `StencilMachineSkeletonInput`).
- [x] Prove copy, reduce, scan, and SOAC C paths.

### STN-SCHED — Typed schedule selection

**Status:** integrated at `d66eff0b6`; independently approved.
**Depends on:** STN-1.

- [x] Define selected, explicitly-unscheduled, and rejected alternatives in ASDL.
- [x] Ensure every descriptor producer supplies a typed selection.
- [x] Put scalar/vector/lane/tail and realization matching on concrete leaves.
- [x] Remove absent-schedule scalar/autovector/unroll defaults.
- [x] Check feature, lane policy/type/count, unroll, interleave, and tail exactly.
- [x] Add scheduled, explicitly-unscheduled, rejected, exact-match, and mismatch tests.
- [ ] Complete LuaJIT stencil artifact construction (now blocked by LJBC-STENCIL payload mismatch).

### LAY-1 — Layout projection and resolution

**Status:** integrated at `00303c45b`; independently approved.
**Depends on:** STN-1 contract analysis.
**Root cause:** a shadowed `resolve_expr` closure plus semantic behavior outside ASDL leaves.

- [x] Restore the correct lexical phase function.
- [x] Define typed `TypeLayoutLookup`, `FieldLayoutLookup`, and `LayoutValueType` alternatives.
- [x] Move layout matching, field lookup, dot projection, size/alignment, and IndexBase behavior to concrete leaves.
- [x] Remove `schema.classof`, raw-header variant dispatch, `maybe_one`, and semantic nil signaling from active layout resolution.
- [x] Bind schema_v2 to the canonical layout implementation.
- [x] Add focused exact-value layout projection tests.
- [x] Pass region main/call C tests.
- [x] Pass inline CMat copy/reduce/scan/SOAC C tests.
- [x] Pass runtime and schema suites.

### TYP-1 — Typed frontend target projection

**Status:** integrated at `1750e4ce5`; independently approved.

- [x] Normalize raw `c_target` to typed `CBackendTarget` before semantic use.
- [x] Project `HostTargetModel`, `CBackendTarget`, and `BackTargetModel` through owned methods.
- [x] Put C/backend endian conversion on concrete endian leaves.
- [x] Preserve pointer width, index width, endian, and target-option precedence.
- [x] Carry the effective `HostTargetModel` in `TypeModuleResult`.
- [x] Prove 32-bit pointer, 16-bit index, and big-endian behavior through public `lalin.emit_c`.
- [x] Pass focused target projection and schema tests.
- [ ] Pass `tests/frontend/test_dsl_lua_owned.lua` (layout now passes; blocked by ABI-SIG missing CodeSig facts).

### TYP-OWN — Check/lower schema ownership

**Failure cluster:** `tree_typecheck_type.lua:556` still looks for `TypeIssue` under `LalinTree`; correcting that exposes missing `LalinTreeLower` / `TreeLowerInput` ownership at `tree_lower.lua:20,142`.

- [ ] Move issue construction to canonical `LalinCheck.TypeIssue` ownership.
- [ ] Define or use the canonical typed tree-lowering input/result vocabulary.
- [ ] Remove duplicate old/new ownership assumptions without a compatibility alias.
- [ ] Restore focused artifact/compiler reproductions.

### CMP-1 — Compiler process typed contracts

- [ ] Identify the compiler-process ASDL constructor mismatch.
- [ ] Correct the producer/consumer contract without boundary-to-semantic table leakage.
- [ ] Pass all `compiler_process` tests.

### ABI-SIG — Required code signature projection

**Status:** integrated at `c95973fd5`; independently approved.
**Failure cluster:** CodeResult validation lacked typed required-signature facts.

- [x] Trace ownership of required function, extern, call, closure, and helper signatures.
- [x] Model requirements and signature collection as named typed ASDL projections.
- [x] Align canonical `LalinTreeLower` and schema_v2 `LalinTreeCode` ownership without fallback constructors.
- [x] Replace nullable signature lookup with typed found/missing alternatives.
- [x] Ensure every concrete producer contributes its required `CodeSig`.
- [x] Remove string-keyed signature lookup from this slice.
- [x] Pass direct binding and pipeline-load smoke tests.
- [x] Pass focused code-type/code-validation producer tests.
- [x] Preserve nested callable-pointer signature validation.
- [ ] Re-run `test_dsl_lua_owned.lua` after ABI-STATE.

### ABI-STATE — Cross-unit lowering isolation

**Failure cluster:** module-level signature/lowering state leaks declarations across alternating compilation units; this is separate from signature projection vocabulary.

- [ ] Replace mutable `module_sig_state` upvalue with narrow typed module/item/function inputs and results.
- [ ] Preserve deterministic signature, registration, generated-data, and function ordering.
- [ ] Add alternating A → B → A and repeated-unit tests.
- [ ] Add failure-then-success isolation tests.
- [ ] Prove no facts leak between public compile sessions.

### LJBC-STENCIL — Deferred / not for integration

**Status:** stopped by project-owner decision. LuaTrace is abandoned; LuaJIT bytecode remains explicit and low priority rather than a main compiler milestone.

- Branch `pack/ljbc-stencil` is intentionally not integrated.
- Do not schedule LuaTrace or LuaJIT stencil work while main C compiler milestones remain.
- Reopen only on an explicit project-owner request.

### AUX-1 — Remaining baseline clusters

- [ ] Fix closure-escape missing `tree_module_name`.
- [ ] Fix native value `CodeBackendReadonlyProjection` construction.
- [ ] Fix core `func_abi_plan` failures.
- [ ] Fix core `type_to_c` failures.
- [ ] Classify and repair the slow binary failure.

## Milestone 2 — Complete the Documented Language Surface

### LNG-REG — Regions and control protocols

**Depends on:** RGN-1.

- [x] Region emit compile/run.
- [x] Region call compile/run.
- [ ] Jump and target-application coverage.
- [ ] Nested and parameterized regions.
- [ ] Typed rejection for missing targets, wires, and unsupported frames.

### LNG-LOOP — Loop and data-parallel forms

**Depends on:** STN-1 and LAY-1.

- [ ] Plain loop compile/run.
- [ ] Fold compile/run.
- [ ] Scan compile/run.
- [ ] Grid, tiled, and window behavior.
- [ ] Copy, reduce, and SOAC C execution.
- [ ] Verify LuaJIT and C modes agree where both are explicitly supported.

### LNG-EXPR — Expression completeness

- [ ] Decide and model `//` as an ASDL operator, or reject it during parsing.
- [ ] Decide and model `^` as an ASDL operator, or reject it during parsing.
- [ ] Eliminate parser-accepts/lowering-rejects mismatches.
- [ ] Add focused `sizeof` tests.
- [ ] Cover casts, indexing, fields, records, and arrays through GCC.

### LNG-AGG — Aggregates, variants, and identity

- [ ] Parsed union constructor coverage.
- [ ] Parsed variant-switch coverage.
- [ ] Tagged-union GCC runtime test.
- [ ] Design and implement parsed `unique` structure identity, or expose a deterministic unsupported diagnostic.
- [ ] Keep unique identity in ASDL rather than hidden Lua identity tables.

### LNG-OWN — Ownership and domains

- [ ] Successful parsed ownership-to-C runtime test.
- [ ] Lease/access/view runtime tests.
- [ ] Escape rejection tests.
- [ ] Handle/domain contract runtime coverage.
- [ ] Verify backend erasure preserves checked semantics.

### LNG-EXT — Extern, builder, and HostEval surfaces

- [ ] Actual extern symbol link/run test.
- [ ] Builder DSL → C → GCC runtime test.
- [ ] HostEval-generated declaration → C runtime test.
- [ ] Qualified method runtime test.

### LNG-UNSUP — Explicit unsupported diagnostics

- [ ] Focused deterministic rejection test for source `while`.
- [ ] Focused deterministic rejection test for source `break`.
- [ ] Focused deterministic rejection test for source `continue`.
- [ ] Cover rejection in function and region contexts.

## Milestone 3 — Complete the ASDL + Leaf-Method Migration

### ASDL-CLOSURE — Closure conversion

- [ ] Replace the mutable Lua rewrite input in `impl/tree_closure.lua`.
- [ ] Replace scope, capture, helper, and capture-environment maps with precise ASDL relations.
- [ ] Do not replace the Lua context bag with one broad ASDL context bag.
- [ ] Define narrow traversal inputs and typed step/results before implementation.
- [ ] Put behavior on every relevant concrete Expr, Place, IndexBase, View, Stmt, Func, and Item leaf.
- [ ] Return a typed unsupported result for `ExprClosure` where support is intentionally absent.
- [ ] Preserve all focused closure-conversion tests.

### ASDL-STENCIL — Stencil planning and materialization

- [ ] Replace `{kind=...}` producer and codegen-plan records in `impl/stencil_plan.lua`.
- [ ] Replace `{valid=true,...}` validation records with a result union.
- [ ] Replace policy/control/materialization records in `impl/lower_emit_c/materialize.lua`.
- [ ] Remove generic `input or {}` semantic protocols.
- [ ] Put selection and materialization behavior on concrete leaves.

### ASDL-MEM — Memory analysis

- [ ] Replace `contract_index` with named typed relation entries.
- [ ] Move `CodeContractFact` indexing behavior to concrete leaves.
- [ ] Move `CodePlace` object resolution to concrete leaves.
- [ ] Move `CodeInstOp` memory transfer behavior to concrete leaves.
- [ ] Replace ad hoc `access_records` with a named facet/product.
- [ ] Model alias, bounds, dependence, contract, and backend facts explicitly.
- [ ] Remove semantic nil signaling.
- [ ] Add leaf-level tests before replacing orchestration.

### ASDL-EFFECT — Effect analysis

- [ ] Remove raw-field instruction and terminator classification.
- [ ] Stop reconstructing memory projections as Lua maps.
- [ ] Move effect production to concrete instruction and call-target leaves.
- [ ] Return typed effect facts or typed rejects.

### ASDL-KERNEL — Kernel and schedule planning

- [ ] Move candidate selection to concrete `KernelLoopCandidate` leaves.
- [ ] Move selection consumption to concrete `KernelLoopPlanSelection` leaves.
- [ ] Replace loop-text semantic indexes.
- [ ] Replace executable booleans and string modes with typed alternatives.
- [ ] Remove raw probing from schedule and lower-plan paths.

### ASDL-VALIDATE-C — Validation and C lowering

- [ ] Remove `classof` routing from `impl/code_validate.lua`.
- [ ] Replace helper-signature Lua records in `impl/code_to_c.lua:729-770`.
- [ ] Remove the `classof` branch in `impl/cemit_emit.lua:786-790`.
- [ ] Audit semantic maps in graph, validation, and C lowering.
- [ ] Keep GCC/TCC process options confined to true IO boundaries.

### ASDL-DESC — Optional-soup descriptors

- [ ] Split stencil-machine descriptors into complete alternatives.
- [ ] Refine loop annotations into explicit facets/unions.
- [ ] Refine pointer capabilities and proofs into typed alternatives.
- [ ] Replace semantic booleans with typed decisions.

## Milestone 4 — Canonical Schema Ownership

### SCH-1 — Inventory and ownership

- [ ] Inventory all 24 same-named modules under `schema/` and `schema_v2/`.
- [ ] Assign one canonical owner for every compiler vocabulary.
- [ ] Document legitimate Host and LuaJIT boundary imports.
- [ ] Detect ambiguous duplicate constructors/method attachments in tests.

### SCH-2 — Migration

- [ ] Migrate active consumers one semantic boundary at a time.
- [ ] Keep source ASDL separate from lower projections/facets.
- [ ] Route the public compile facade through the canonical typed compiler pipeline.
- [ ] Prove GCC compile/run after every migrated boundary.
- [ ] Remove old modules only after all consumers migrate.
- [ ] Add no old-to-new compatibility wrappers.

## Milestone 5 — Validation, Documentation, and Release Gates

For every work package:

- [ ] Focused regression tests pass.
- [ ] Relevant category suite passes.
- [ ] Default suite gains no failures.
- [ ] Slow suite runs when relevant.
- [ ] Emitted C compiles under GCC where applicable.
- [ ] Runtime values are asserted; artifact existence alone is insufficient.
- [ ] An independent reviewer checks ASDL ownership and doctrine compliance.
- [ ] Integrated changes are synchronized into all active worktrees.

Release-level gates:

- [ ] Default suite passes with zero failures.
- [ ] Experimental profiles have explicit commands and expected results.
- [ ] `emit_c` coverage declarations match executable tests.
- [ ] `LANGUAGE_REFERENCE.md` status notes match proven support.
- [ ] `ARCHITECTURE.md` describes GCC-over-`emit_c` as the main backend.

## Work-Package Queue

| ID | Priority | Dependencies | Suggested scope | Status | Owner/branch |
|---|---:|---|---|---|---|
| RGN-1 | P0 | none | Region helper restoration + focused tests | integrated | `82ec214af`; approved by `w4:p14` |
| STN-1 | P0 | none | Stencil semantic construction | integrated | `35c1ce5a3`; approved by `w4:p16` |
| STN-SCHED | P0 | STN-1 | Typed schedule selection | integrated | `d66eff0b6`; approved by `w4:p16` |
| LAY-1 | P0 | STN-1 analysis | Typed leaf-owned layout resolution | integrated | `00303c45b`; approved by `w4:p14` |
| TYP-1 | P0 | none | Typed frontend target projection | integrated | `1750e4ce5`; approved by `w4:p6` |
| TYP-OWN | P0 | none | Check/lower schema ownership | working | `pack/typ-own` (`w4:p1C`) |
| ABI-SIG | P0 | LAY-1 | Required code signature projection | integrated | `c95973fd5`; approved by `w4:p6` |
| ABI-STATE | P0 | ABI-SIG vocabulary | Cross-unit lowering isolation | working | `pack/abi-state` (`w4:p1B`) |
| LJBC-STENCIL | deferred | — | Abandoned LuaTrace / low-priority LuaJIT work | stopped | branch not integrated |
| CMP-1 | P1 | none | Compiler-process contracts | ready | — |
| M0.1 | P0 | none | Failure ledger and focused reproducers | ready | — |
| ASDL-CLOSURE | P1 | baseline stabilization | Closure state and leaf-method migration | planned | — |
| ASDL-STENCIL | P1 | STN-1 | Typed stencil/materialization results | planned | — |
| ASDL-MEM | P1 | baseline stabilization | Memory facets and leaf methods | planned | — |
| LNG-* | P1/P2 | owning infrastructure packages | Documented language completion | planned | — |
| SCH-* | P2 | stable canonical path | Schema ownership consolidation | planned | — |

## Distribution Protocol

Every assignment must include:

```text
WORK_PACKAGE: <ID>
GOAL: <bounded outcome>
WORKTREE: <path>
BRANCH: <branch>
BASE: <integration branch and commit>
FILES/SCOPE: <owned paths>
DEPENDENCIES: <packages/commits or none>
CONSTRAINTS: ASDL guide; no shims; no unrelated edits; ignore .pi/workflows
ACCEPTANCE CHECKS: <exact commands>
REPORT: summary, files, checks, risks, status, commit, ready-to-integrate
```

After integration, all active implementation branches must merge or rebase the integration branch and rerun focused checks.

## Decision Log

- **2026-07-10:** The active compiler has substantial ASDL vocabulary but retains nominal-ASDL manual dispatch and semantic Lua state in important passes.
- **2026-07-10:** Region input schema is correct. The P0 crash comes from three accidentally deleted helpers, not from `RegionInvokeExpandInput.scope`.
- **2026-07-10:** Restore the failing main path before broad semantic migrations, while designing each repair under the ASDL doctrine.
- **2026-07-10:** Closure conversion is the smallest high-impact migration laboratory; memory analysis is the most central larger migration.
- **2026-07-10:** This file, not `.pi/workflows/*`, is the tracking authority.
- **2026-07-11:** LuaTrace is abandoned. LuaJIT bytecode remains explicit but low priority; do not invest in LuaJIT stencil work ahead of the C compiler.

