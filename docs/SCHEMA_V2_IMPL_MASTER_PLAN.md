# Lalin Compiler Completion and ASDL Migration — Master Plan

> **Status:** Single source of truth for compiler completion, regression repair, and the clean ASDL + leaf-method migration.
> **Planning evidence baseline:** `main@15117196ad0f456c18b1df2e916639f9b4bc6f35` (2026-07-11), merged into this worktree after completed integration history. The historical failure ledger below remains anchored at `8630bc808` until M0 refreshes it after CMP-1.
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

### Refreshed test baseline at `af80ae43`

The tested compiler source is identical through the subsequent documentation-only commits.

| Profile | Refreshed result | Baseline `8630bc808` |
|---|---:|---:|
| `luajit tests/run.lua` | 112 passed, 1 skipped, 28 failed | 89 passed, 1 skipped, 46 failed |
| `LALIN_RUN_SLOW=1 luajit tests/run.lua` | 112 passed, 29 failed | 89 passed, 47 failed |
| `luajit tests/run.lua frontend` | 13 passed, 1 failed | 12 passed, 1 failed |
| `luajit tests/run.lua schema` | 11 passed, 0 failed | 9 passed, 1 failed |
| `luajit tests/run.lua schema_v2` | 14 passed, 0 failed | 12 passed, 0 failed |
| `luajit tests/run.lua compiler_process` | 7 passed, 0 failed | 4 passed, 3 failed |
| `luajit tests/run.lua c_backend` | 20 passed, 1 failed | 9 passed, 12 failed |
| `luajit tests/run.lua code_ir` | 36 passed, 1 skipped, 24 failed | 31 passed, 1 skipped, 26 failed |
| `luajit tests/run.lua core` | 16 passed, 2 failed | 16 passed, 2 failed |
| `luajit tests/run.lua runtime` | 4 passed, 0 failed | 3 passed, 1 failed |

The default suite gained 23 passes and removed 18 failures. No previously passing test regressed. Scalar GCC, region main/call, and inline CMat copy/reduce/scan/SOAC runtime checks pass.

### Refreshed failure clusters

| Count | Class | Cluster | Owner |
|---:|---|---|---|
| 1 | stale harness | C helper registration test passes loose `{helpers={}}` instead of typed `CEmitMachine` | CLOW-1 |
| 1 | main compiler | closure module-name methods are not installed at conversion entry | AUX-CLOSURE-NAME |
| 17 | excluded LuaJIT | removed `StencilMachineSkeletonInput` | deferred |
| 3 | excluded LuaJIT | stale `CodeInstIntrinsic` schema | deferred |
| 1 | excluded LuaJIT | fixture omits typed schedule selection | deferred |
| 1 | experimental native | removed readonly projection | deferred |
| 1 | abandoned LuaTrace | stale stencil payload | stopped |
| 1 | stale harness | `Back`/`Backend` typo in function ABI test | AUX-FUNC-ABI |
| 1 | stale harness | reversed canonical type-to-C test arguments | AUX-TYPE-C |
| 1 | main compiler | builder/compiler-driver binding role identity mismatch | LNG-EXT-C |

The slow profile adds one deferred embedded-binary module-name collision. Excluded LuaTrace/LuaJIT/native failures are not main-C release priorities.

## Milestone 0 — Failure Ledger and Reproducible Baseline

**Status:** complete at the refreshed integration baseline.

### M0.1 Failure classification

- [x] Record every baseline failure under exactly one root-cause cluster.
- [x] Classify each cluster as main compiler, excluded backend, stale harness, or deferred packaging work.
- [x] Give every active cluster a minimal focused reproducer.
- [x] Record the 18 previously failing tests and five new tests now passing.
- [x] Keep experimental native and abandoned LuaTrace work outside the main backend.

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

**Status:** integrated at `ae2a8e164`; independently approved.
**Root cause:** canonical check-stage vocabulary remained under `LalinTree`; the apparent lower failure came from incorrectly binding legacy `tree_lower.lua` to the schema_v2 context.

- [x] Move canonical check inputs/results/facts, issues, reasons, and explanations to `LalinCheck`.
- [x] Preserve separate canonical `LalinTreeLower` and schema_v2 `LalinTreeCode` ownership.
- [x] Remove duplicate `LalinTree` check ownership without compatibility aliases or probes.
- [x] Pass direct context-load, focused canonical compiler, schema, and ownership tests.

### CMP-1 — Compiler process typed contracts

**Status:** integrated at `7b983824`; independently approved.

- [x] Replace string/schedule-emitter capabilities with typed `MachineCapability` leaves.
- [x] Select canonical `tree_lower` versus schema_v2 `impl.tree_code` through typed implementation ownership.
- [x] Make concrete `MachineImpl` leaves execute typed requests without class/string dispatch or require probing.
- [x] Define typed phase values, diagnostics, step reports, progress, run artifacts, and execution reports.
- [x] Make canonical and schema_v2 C backends return typed `CompilerCBackendResult`.
- [x] Consume immutable typed module-lowering results without multi-return wrappers or nil normalization.
- [x] Pass `compiler_process` 7/7, schema 11/11, isolation, target projection, and scalar GCC runtime checks.

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

**Status:** integrated at `f7ba18a`; independently approved.
**Root cause:** ambient module-level lowering state leaked signatures and generated facts across compilation units.

- [x] Replace mutable `module_sig_state` with immutable typed transitions.
- [x] Split registration, ABI, emission, accumulation, and contract facts into narrow facets/results.
- [x] Make compiler/frontend APIs consume one typed module-lowering result.
- [x] Remove multi-return wrappers, lowering aliases, classof dispatch, and nil/`{}` contract protocols.
- [x] Preserve deterministic signature, registration, generated-data, and function ordering.
- [x] Add alternating A → B → A and repeated-unit tests.
- [x] Add partial-lowering-failure → success isolation tests.
- [x] Prove no facts leak between public compile sessions.
- [x] Pass frontend 14/14, schema, ABI-SIG, isolation, and GCC checks.

### LJBC-STENCIL — Deferred / not for integration

**Status:** stopped by project-owner decision. LuaTrace is abandoned; LuaJIT bytecode remains explicit and low priority rather than a main compiler milestone.

- Branch `pack/ljbc-stencil` is intentionally not integrated.
- Do not schedule LuaTrace or LuaJIT stencil work while main C compiler milestones remain.
- Reopen only on an explicit project-owner request.

### Deferred baseline clusters

The native `CodeBackendReadonlyProjection` failure, slow embedded binary profile, LuaTrace, LuaJIT stencil/region repair, and experimental native copy-patch are not priorities in this plan. Reopen them only by explicit project-owner decision. The main path remains GCC over `emit_c`.

## Milestone 2 — Bounded Language and Main-C AUX Packages

**Evidence baseline:** current `main` at `15117196ad0f456c18b1df2e916639f9b4bc6f35`, validated 2026-07-11. The package order is intentional: harness-only AUX first, narrow infrastructure second, independent C coverage third, control/expression fourth, and richer dependent surfaces last.

### Language/AUX assignment order

| Order | ID | Outcome | Dependencies |
|---:|---|---|---|
| 1 | AUX-FUNC-ABI | Repair/classify the stale core ABI test | none |
| 2 | AUX-TYPE-C | Test the canonical typed machine/type-to-C contract | ABI-SIG, ABI-STATE vocabulary |
| 3 | AUX-CLOSURE-NAME | Install the existing module-name leaf contract at closure entry | canonical Tree schema |
| 4 | LNG-DIAG | Deterministic unsupported-control diagnostics | none |
| 5 | LNG-LOOP-C | Parsed loop/data-parallel GCC runtime matrix | STN-1, STN-SCHED, LAY-1, ABI-STATE |
| 6 | LNG-EXT-C | Extern, builder, HostEval, and method GCC runtime | AUX-FUNC-ABI, AUX-TYPE-C, ABI-STATE |
| 7 | LNG-REG-C | Complete main-C region protocol coverage | RGN-1, LAY-1, ABI-STATE |
| 8 | LNG-EXPR-C | Close expression parser/lowering mismatches | LNG-DIAG if rejection is selected |
| 9 | LNG-VAR-C | Parsed variants, switch, identity decision, GCC runtime | LNG-EXPR-C only if grammar overlaps |
| 10 | LNG-OWN-C | Ownership/domain runtime and typed escape rejection | LNG-REG-C only for resolver-region fixtures |

Orders 1–6 may run concurrently where owned files do not overlap. Serialize `LNG-DIAG` with expression-parser edits, `LNG-EXPR-C` with variant grammar edits, and any region resolver fixture shared by `LNG-REG-C`/`LNG-OWN-C`.

### AUX-FUNC-ABI — Core function ABI test repair

**Evidence:** `tests/core/test_func_abi_plan.lua:27` fails. The test declares `local Back = T.LalinBackend` but then uses global `Backend`; direct inspection shows the produced `BackValId`, `BackIndex`, and bindings are valid. This is a harness defect unless the corrected test exposes a production defect.

**ASDL/leaf contract:** retain `FuncAbiPlan`; `AbiParamScalar`, `AbiParamView`, `AbiParamRejected`; `AbiResultVoid`, `AbiResultScalar`, `AbiResultView`, `AbiResultRejected`. No aliases or compatibility constructors.

**Owned files:** primarily `tests/core/test_func_abi_plan.lua`; `lua/lalin/func_abi_plan.lua`, `schema/type.lua`, and `schema/backend_schema.lua` are review-only unless a corrected assertion proves a real defect.

**Work/acceptance:**

- [ ] Correct `Back`/`Backend`; add value-ID text assertions and scalar/index/view/aggregate/array/rejected parameter coverage.
- [ ] Cover void/scalar/view/rejected results and zero-based role indices.
- [ ] Run `luajit tests/core/test_func_abi_plan.lua`.
- [ ] Run `luajit tests/core/test_type_abi_classify.lua` and `luajit tests/core/test_type_to_backend_scalar.lua`.
- [ ] Run `luajit tests/run.lua core` and the default-suite no-regression gate.

**Out of scope:** full `func_abi_plan.lua` leaf migration, platform aggregate ABI, variadics, native calling conventions. Completion evidence must classify the root cause and keep production unchanged unless independently justified.

### AUX-TYPE-C — Canonical type-to-C contract

**Evidence:** `tests/core/test_type_to_c.lua:24` calls `api.code_type_to_c(code_ty, {})`; the current contract at `code_type.lua:579-580` is `(machine, ty)`, so `{}` is misclassified as the Code type. `tests/code_ir/test_code_type.lua` passes with the proper contract.

**ASDL/leaf contract:** concrete `CodeTy* :code_to_c_backend_type(...) -> CBackendType`; use the typed C emission machine/projection when registration is required. Do not restore reversed arguments or accept a loose `{}` state.

**Owned files:** primarily `tests/core/test_type_to_c.lua`; review-only `lua/lalin/code_type.lua`, `impl/lower_emit_c/code_to_c.lua`, `schema/cemit_machine.lua`, and `schema/c.lua`.

**Work/acceptance:**

- [ ] Test `(machine, ty)` and prefer direct concrete leaf methods when accumulation is unnecessary.
- [ ] Cover scalar/nullary, data/code/imported pointers, arrays, slices, views, closures, named/imported C types, handles, leases, vectors, callable signature registration, and `ArrayLenExpr` rejection.
- [ ] Run `luajit tests/core/test_type_to_c.lua`, `luajit tests/code_ir/test_code_type.lua`, and `luajit tests/schema_v2/test_complex_types.lua`.
- [ ] Run relevant core/code-IR suites and the default-suite no-regression gate.

**Out of scope:** new C ABI policy, generic convenience APIs, native representation, and LuaJIT ctype projection. Evidence must show the current `unsupported CodeType ... table` failure is gone without a shim.

### AUX-CLOSURE-NAME — Closure module-name binding

**Evidence:** `tests/code_ir/test_closure_escape.lua` fails at `closure_convert.lua:779` with `attempt to call method 'tree_module_name'`; `test_closure_convert.lua` passes because it installs `tree_module_type(T)`. Implementations already exist at `tree_module_type.lua:55-72`.

**ASDL/leaf contract:** `ModuleHeader:tree_module_name() -> str`, implemented by `ModuleSurface`, `ModuleTyped`, `ModuleSem`, and `ModuleCode`. The closure entrypoint installs the owning implementation before calling it.

**Owned files:** `lua/lalin/closure_convert.lua`, `tree_module_type.lua`, `tests/code_ir/test_closure_escape.lua`, and `test_closure_convert.lua`.

**Work/acceptance:**

- [ ] Bind the canonical methods at the owning API boundary; test surface/typed names and deterministic helper names.
- [ ] Run both closure tests and `luajit tests/run.lua code_ir`; apply the default-suite no-regression gate.

**Out of scope:** the CLO migration below, capture redesign, new escape semantics, and LuaJIT/native closure work. No LuaJIT backend file may change.

### LNG-DIAG — Unsupported control diagnostics

**Evidence:** `syntax/stmt.lua:346-355` falls into generic expression parsing. `break` reaches `emit_c` and reports `missing explainer for phase: backend`; `continue` becomes unresolved; `while` produces an unrelated parse/document error.

**ASDL/leaf contract:** the parser boundary returns a canonical LLBL or typed diagnostic carrying the `while`/`break`/`continue` alternative, source origin, function/region context, stable code, and message. If represented in Tree ASDL, each unsupported form is a concrete leaf returning a typed issue.

**Owned files:** `lua/lalin/syntax/stmt.lua`, syntax origin/diagnostic support, `schema/check.lua`, `error/catalog.lua`, and a new `tests/frontend/test_lalin_unsupported_control_diagnostics.lua`.

**Work/acceptance:**

- [ ] Test three forms in both function and region contexts and preserve the dedicated `for` → `loop` diagnostic.
- [ ] Prove none reaches type lowering or backend explanation.
- [ ] Run the focused test, `luajit tests/run.lua frontend`, and the default-suite no-regression gate.

**Out of scope:** implementing `while`, `break`, or `continue`, hidden-jump rewrites, and backend explanations for forms rejected earlier.

### LNG-LOOP-C — Loop and data-parallel C completeness

**Evidence:** inline CMat copy/reduce/scan and SOAC-map tests pass. A current-main ad hoc parsed source compile returned `dot([2,3],[4,5],2) == 23`, but no committed parsed-loop GCC matrix exists.

**ASDL/leaf contract:** retain typed range/grid/tiled/window producers; fold/scan/store/copy/reduce/SOAC sinks; schedule selection; stencil descriptors; precise reject leaves. New failures must not create mode strings, `{kind=...}` plans, or text indexes.

**Owned files:** `syntax/stmt.lua`, `syntax/for_to_loop.lua`, `tree_typecheck_stmt.lua`, `tree_lower.lua`, `impl/tree_code.lua`, `impl/stencil_plan.lua`, `impl/lower_emit_c/materialize.lua`, and new `tests/c_backend/test_lalin_parsed_loops_gcc.lua`.

**Work/acceptance:**

- [ ] GCC runtime: plain loop, copy, fold reducers `add/mul/min/max`, scan, 2D grid, tiled ND, window/clamp edge, reduce, SOAC, zero-trip, and one-trip.
- [ ] Run the new test and existing `test_emit_c_inline_cmat_copy.lua`, `...reduce.lua`, `...scan.lua`, and `test_emit_c_inline_soac_map.lua`.
- [ ] Run frontend/C-backend suites and the default-suite no-regression gate.

**Out of scope:** LuaJIT parity, LuaTrace, native copy-patch, scheduling optimization, and vectorization policy.

### LNG-EXT-C — Extern, builder, HostEval, and methods

**Evidence:** parsed extern, HostEval-role, method-syntax, and Lua-owned DSL tests pass only their current parse/staging checks; no dedicated four-surface GCC runtime matrix exists.

**ASDL/leaf contract:** `ItemExtern -> CodeExtern -> C extern`; builder `Decl`, HostEval declaration streams, and qualified methods converge on the same canonical Tree items and statically resolved functions. No new schema is expected.

**Owned files:** `syntax/document.lua`, `syntax/role_adapter.lua`, `syntax/to_tree.lua`, `dsl/*`, `frontend_pipeline.lua`, `init.lua`, `emit_c_compile.lua`, and new C tests.

**Work/acceptance:**

- [ ] Link/run a real extern (for example libc `abs`), including explicit symbol spelling.
- [ ] Compile/run builder declarations, a HostEval-generated declaration, and a qualified method with explicit/injected receiver.
- [ ] Add `test_lalin_extern_builder_hosteval_gcc.lua` and `test_lalin_qualified_method_gcc.lua`.
- [ ] Run existing surface tests, new tests, frontend/C-backend suites, and the default-suite no-regression gate.

**Out of scope:** dynamic method lookup, a new FFI subsystem, LuaJIT callable modules, and native symbol patching.

### LNG-REG-C — Regions and control protocols

**Evidence:** `test_emit_c_region_main.lua`, `test_emit_c_region_call.lua`, and `test_region_expansion_helpers.lua` pass. `test_region_emit_expansion.lua` fails only after entering excluded LuaJIT code at `luajit_lower.lua:90`.

**ASDL/leaf contract:** `RegionInvokeTarget`; `RegionWireTarget` leaves; `RegionInvokeMissingTarget`, `RegionInvokeArgCount`, `RegionInvokeMissingWire`, `RegionInvokeExtraWire`, `RegionInvokeDuplicateWire`, `RegionInvokeCallFrameUnsupported`; `RegionInvokeExpandInput`; `RegionInvokeExpanded/Rejected`; `ControlReject*`; `TypeIssueRegionInvoke`. Every reject leaf owns explanation.

**Owned files:** `schema/tree.lua`, `schema/check.lua`, `tree_typecheck_stmt.lua`, `tree_control_facts.lua`, `tree_lower.lua`, `impl/tree_code.lua`, `syntax/stmt.lua`, and region C tests.

**Work/acceptance:**

- [ ] Parsed nested/parameterized regions; positional/named target application; block/continuation wiring; exact reject-leaf tests.
- [ ] Compile/run one nested protocol in new `test_lalin_parsed_region_protocols_gcc.lua`.
- [ ] Run the three passing focused tests, new test, frontend/C-backend suites, and default-suite no-regression gate.

**Out of scope:** `StencilMachineSkeletonInput`, LuaJIT region optimization, native continuation stencils, and broad region migration.

### LNG-EXPR-C — Expression completeness

**Evidence:** `syntax/expr.lua:189,191` accepts `//` and `^`; `syntax/to_tree.lua:37-42` maps neither, so both fail as `parsed_to_tree: unsupported expression tag BinOp`. `ExprSizeOf` exists but lacks parsed GCC coverage.

**ASDL/leaf contract:** for each operator, either add a concrete `BinaryOp` leaf with leaf-owned typecheck/lowering/C behavior or reject during parsing with a typed diagnostic. Specify negative-operand semantics for supported `//`. Retain `ExprCast`, `ExprSizeOf`, `ExprIndex`, `ExprDot`, `ExprAgg`, and `ExprArray`.

**Owned files:** `syntax/expr.lua`, `syntax/to_tree.lua`, `schema/core.lua`, `schema/tree.lua`, `impl/tree_check/expr.lua`, `impl/tree_code.lua`, `impl/lower_emit_c/code_to_c.lua`, and expression tests.

**Work/acceptance:**

- [ ] Remove both parser/lowering mismatches; test invalid operands.
- [ ] GCC runtime for `sizeof` scalar/struct/array, casts, pointer indexing, field load/store, named records, and positional arrays.
- [ ] Add `test_lalin_expression_operator_contract.lua` and `test_lalin_parsed_expressions_gcc.lua`; run frontend/C-backend suites and default-suite no-regression gate.

**Out of scope:** generic math libraries, arbitrary precision, vector expansion, LuaJIT lowering, and broad optimization.

### LNG-VAR-C — Variants and identity

**Evidence:** `test_lalin_parsed_union_emit_c.lua` passes emitted-text checks only. `syntax/stmt.lua:212-236` parses scalar cases; `syntax/to_tree.lua` maps calls to `ExprCall`, not `ExprCtor`. Lowering already has variant constructor/tag/payload/switch nodes; multi-field payload lowering is explicitly unsupported.

**ASDL/leaf contract:** reuse `ExprCtor`, `SwitchVariantStmtArm`, `SwitchVariantExprArm`, typed variant refs, `CodeInstVariantCtor/Tag/Payload`, and `CodeTermVariantSwitch`. Syntax projects directly to these values. `unique` becomes real ASDL identity or a precise unsupported diagnostic.

**Owned files:** `syntax/expr.lua`, `syntax/stmt.lua`, `syntax/to_tree.lua`, `schema/tree.lua`, `schema/tree_lower.lua`, `tree_typecheck_expr.lua`, `tree_lower.lua`, `impl/tree_check/expr.lua`, `impl/tree_code.lua`, lower-emit-C variant files, and union tests.

**Work/acceptance:**

- [ ] Define constructor spelling; parse nullary/one-payload constructors and variant arms with payload binds.
- [ ] GCC runtime for nullary/payload/default cases; exact unknown-variant/invalid-bind issues; explicit `unique` decision.
- [ ] Add `test_lalin_parsed_variant_surface.lua` and `test_lalin_parsed_variant_gcc.lua`; run existing union test, frontend/C-backend suites, and default-suite no-regression gate.

**Out of scope:** silent multi-field flattening, hidden identity maps, dynamic reflection, and native variant stencils.

### LNG-OWN-C — Ownership and domains

**Evidence:** `test_lalin_domain_contract.lua` passes typechecking only. Typed lease-escape/domain reasons exist, but there is no parsed ownership GCC runtime test.

**ASDL/leaf contract:** `TypeAccess` leaves; `TAccess`, `TLease`, `LeaseOrigin`; `TypeUnaryLeaseEscape*`; `TypeUnaryHandle*`; `TypeIssueInvalidUnary`; `TypeIssueDomainContract`. New outcomes are precise leaves, never booleans or mode strings.

**Owned files:** `schema/type.lua`, `schema/check.lua`, `tree_typecheck_type.lua`, `tree_typecheck.lua`, `tree_typecheck_expr.lua`, `tree_lower.lua`, `impl/tree_check/*`, `impl/tree_code.lua`, and ownership tests.

**Work/acceptance:**

- [ ] Parsed GCC success for readonly/writeonly/preserve/noescape/lease/view and handle/domain resolver behavior; assert legal C erasure.
- [ ] Exact return/store/aggregate/call/durable escape and invalidating-call-while-live issue leaves.
- [ ] Add `test_lalin_ownership_rejections.lua` and `test_lalin_ownership_erasure_gcc.lua`; run domain, frontend/C-backend suites, and default-suite no-regression gate.

**Out of scope:** runtime GC/borrow tracking, hidden lease state in C, general memory-analysis migration, and LuaJIT ownership.

## Milestone 3 — Bounded ASDL and Leaf-Method Migration Packages

**Planning corrections:** there are **25** duplicate schema module names, not 24. Ad hoc C helper signatures are in `lua/lalin/impl/cemit_emit.lua:734-770`. The active schema-v2 C path lacks `LalinCMat`; `schema_v2/stencil_machine.lua` contains `LalinLuaJIT.LJExpr` and is excluded from the neutral main-C design.

### Dependency graph

```text
CLO-1 -> CLO-2 -> CLO-3

MEM-1 -> MEM-2 -> MEM-3 -> MEM-4 -> EFF-1 -> EFF-2
                                           `-> KRN-1 -> SCH-1 -> SCH-2

CMAT-1 -+-> STN-PLAN -+-> DESC-2 -+-> CMAT-2 -> CMAT-3
         `-> DESC-1 ----'           |
VAL-1 ------------------------------+-> CLOW-1 -> CVAL-2
CVAL-1 -> CEMIT-1 ------------------'

OWN-0 starts independently; OWN-FRONT/ANALYSIS/STENCIL/C/META follow
their completed semantic chains; all converge at OWN-CUTOVER.
```

### CLO-1 — Closure semantic vocabulary

**Evidence:** `schema_v2/sem.lua:126-142` has unused/incomplete capture products; `impl/tree_closure.lua:25-79,614-684` uses mutable loose scope/capture/name/helper state, nil capture modes, fixed eight-byte layouts, and multiple returns.

**Define/leaf ownership:** `ClosureBinding`, `ClosureScopeFrame/Stack`, `ClosureCaptureCandidate/Set/Layout/Environment`, `ClosureNameSupply`, narrow `ClosureTraversalInput`, `ClosureLookup = Found|Missing`, and `ClosureConvertResult = Converted|Unchanged|Unsupported`. `ValueRefName:closure_lookup`; other refs return missing; type leaves own capture layout; scope/result leaves own transitions.

**Owned files:** `schema_v2/sem.lua`; new `test_closure_semantic_schema.lua`. **Dependencies:** none. **Out of scope:** traversal, rewriting, helper insertion, C ABI, compatibility.

**Checks/acceptance:** `luajit tests/schema_v2/test_closure_semantic_schema.lua`; schema suite. Constructors reject loose tables; unsupported is typed; no broad ClosureContext.

### CLO-2 — Capture collection and layout leaves

**Evidence:** `impl/tree_closure.lua:101-286` uses `classof`, ad hoc capture records, copied Lua scope maps, and fixed layouts; equivalent old-path state remains in `closure_convert.lua`.

**Define/leaf ownership:** `ClosureCollectInput/Result`, `ClosureCaptureLayoutInput/Result`, `ClosureScopeTransition`. Every concrete `Expr`, `Place`, `IndexBase`, `View`, and `Stmt` implements `closure_collect`; binding statements return typed transitions; type leaves own size/alignment.

**Owned files:** `impl/tree_closure.lua`; narrow additions to `schema_v2/sem.lua`; new capture-leaf tests. **Dependencies:** CLO-1. **Out of scope:** rewriting/helper insertion and adapting old `closure_convert.lua`.

**Checks/acceptance:** closure capture leaf test and schema-v2 closure test; no `classof`, locals/seen/scope/capture maps, fixed eight-byte assumption, or uncovered concrete leaf.

### CLO-3 — Typed closure rewriting and helper transitions

**Evidence:** `impl/tree_closure.lua:299-600,690-792` manually dispatches, mutates module/item/function state, returns multiple values, and throws unsupported; the current test expects that throw.

**Define/leaf ownership:** typed `ClosureExpr/Place/View/StmtRewriteResult`; `ClosureFuncResult = Converted|Unchanged|Unsupported`; `ClosureItemResult = Converted|Unchanged|Rejected`. Every relevant concrete expression/place/index/view/statement leaf owns `closure_rewrite`; every Func/Item leaf owns conversion; module composition returns typed transitions.

**Owned files:** `impl/tree_closure.lua`, `impl/compiler_api.lua`, closure schema-v2 tests. **Dependencies:** CLO-2. **Out of scope:** LuaJIT/native lowering and runtime escape policy.

**Checks/acceptance:** closure convert/frontend-complete/frontend suite; no mutable bag, multiple semantic returns, parent dispatch, hidden helper list, or thrown unsupported result.

### MEM-1 — Typed memory contract/access projections

**Evidence:** `impl/code_mem.lua:31-67,171-223` mutates `many` fields as maps, signals missing via nil, and builds `contract_index`; `code_effect.lua` rebuilds the same maps.

**Define/leaf ownership:** named bounds/window/same-length/disjoint/noalias/readonly/writeonly relation entries; `MemContractProjection`; typed access/object/backend/proof lookup unions. Every `CodeContractFact:project_memory_contract`; contract value/place-load leaves own expression projection; proof leaves emit entries; projection lookup returns unions.

**Owned files:** `schema_v2/mem.lua`, `impl/code_mem.lua`, new contract-projection test. **Dependencies:** none. **Out of scope:** place resolution, transfer, alias decisions.

**Checks/acceptance:** focused test and schema suite; remove `contract_index`, string-key mutation, and semantic nil; effect consumes the projection.

### MEM-2 — CodePlace memory resolution

**Evidence:** `impl/code_mem.lua:502+` selects by raw field presence and returns multiple values/nil.

**Define/leaf ownership:** `MemPlaceResolveInput`; `MemPlaceResolved`, `MemPlaceUnresolved`, `MemPlaceResolveResult`; `MemPlaceDiscoveries`; `MemAccessSafetyDecision = Proven|Unproven`. Every concrete `CodePlace* :resolve_memory_place`; object-form/extent leaves own safety proof.

**Owned files:** `schema_v2/mem.lua`, `impl/code_mem.lua`, new place-leaf test. **Dependencies:** MEM-1. **Out of scope:** instruction scanning and dependence pairs.

**Checks/acceptance:** remove `object_for_place`; no raw-field dispatch, nil, or multiple returns; resolved/unresolved tests for every place leaf.

### MEM-3 — Instruction memory-transfer facet

**Evidence:** `impl/code_mem.lua:424-456,695-736` keeps value/local/load/stride/store side maps and ad hoc boolean/string-key access records.

**Define/leaf ownership:** named value/local/constant/loaded-place/scaled-stride entries; `MemTransferFacet`; `MemInstructionTransferInput/Result`; `MemDependenceAccess`. Every `CodeInstOp:transfer_memory`; memory leaves own access facts; non-memory leaves return typed unchanged; `MemAccessOp` leaves classify.

**Owned files:** `schema_v2/mem.lua`, `impl/code_mem.lua`, new instruction-leaf test. **Dependencies:** MEM-2. **Out of scope:** pairwise dependence.

**Checks/acceptance:** remove access records/raw chains and semantic booleans; direct load/store/atomic coverage.

### MEM-4 — Alias, dependence, and backend decisions

**Evidence:** `MemBackendAccessInfo.movable [bool]` and same-store/movement/alias facts are booleans and Lua maps.

**Define/leaf ownership:** `MemMovementDecision = Movable|Pinned`; `MemObjectPairDecision = Independent|Dependent|Unproven`; named same-store/disjoint/access-mode entries; typed dependence request/result. Trap and safety leaves own movement; access/dependence leaves own pair classification; contracts produce access/alias relations.

**Owned files:** `schema_v2/mem.lua`, `impl/code_mem.lua`, consumers of `movable`. **Dependencies:** MEM-3. **Out of scope:** kernel policy.

**Checks/acceptance:** dependence leaf test and code-IR suite; no same-store/disjoint/access-mode maps or `(bool, reason)` decisions.

### EFF-1 — Effect evidence, contracts, and call summaries

**Evidence:** `schema_v2/effect.lua:31-36` has paired optional call fields; `impl/code_effect.lua:33-129` mutates contract arrays and a purity map.

**Define/leaf ownership:** `EffectEvidence`; complete direct/extern/indirect/closure `CallSummary` leaves; `FunctionEffectClassification`; `ContractEffectResult`. Every contract fact owns `contract_effect`; every call target owns summary; function/call-summary leaves own consumption.

**Owned files:** `schema_v2/effect.lua`, `impl/code_effect.lua`, direct kernel consumers. **Dependencies:** MEM-1, preferably MEM-4. **Out of scope:** instruction/terminator traversal.

**Checks/acceptance:** focused contract/call test; no optional-pair summary, contract output map, or purity map; all target alternatives tested.

### EFF-2 — Instruction and terminator effect leaves

**Evidence:** `impl/code_effect.lua:132-205` rebuilds maps, probes fields, and represents no effects by empty arrays.

**Define/leaf ownership:** `EffectAnalysisRequest`, `EffectInstructionInput`, instruction result alternatives, term result alternatives, analysis result. Every `CodeInstOp:compute_effect`; call delegates to target; every `CodeTermOp:compute_term_effect`; graph composes.

**Owned files:** `schema_v2/effect.lua`, `impl/code_effect.lua`, `impl/compiler_api.lua`, new effect tests. **Dependencies:** EFF-1, MEM-4. **Out of scope:** kernel/schedule policy and C emission.

**Checks/acceptance:** instruction/pipeline tests and code-IR suite; no raw classification, rebuilt maps, nil, or multiple results.

### KRN-1 — Kernel candidate projection and leaf consumption

**Evidence:** `impl/kernel_plan.lua:181-252` uses loop-text indexes/raw selection probing; closed form drops real trip facts; `KernelLoopPlanClosedForm` has `add_trip_unknown_proof [bool]`.

**Define/leaf ownership:** named reduction/closed-form-by-loop entries; `KernelLoopFactProjection`; `KernelLoopPlanRequest`; `KernelTripEvidence = Known|Unavailable`. Candidate leaves select plans; plan-selection leaves materialize; flow trip-count leaves convert evidence; planned/no-plan leaves own eligibility.

**Owned files:** `schema_v2/kernel.lua`, `impl/kernel_plan.lua`, new kernel tests. **Dependencies:** MEM-4, EFF-2. **Out of scope:** stencil reconstruction, schedule selection, lower-plan lookup.

**Checks/acceptance:** kernel leaf/module/add-compile tests; no raw probing/text index; every candidate tested; no cross-loop contamination; real trip fact retained.

### SCH-1 — Schedule candidates and capabilities

**Evidence:** `ScheduleEmitterCapability.executable [bool]`, paired optionals, and `impl/schedule_plan.lua` boolean/raw probing.

**Define/leaf ownership:** executable/rejected capability alternatives; vector/scalar/closed-form candidate alternatives; retain typed `SchedulePlanSelection`. Capability, candidate, kernel-plan, schedule-form, and target-fact leaves own selection/contribution.

**Owned files:** `schema_v2/schedule.lua`, `impl/schedule_plan.lua`, capability tests. **Dependencies:** KRN-1. **Out of scope:** vector emitter, stencil schedules, lower lookup.

**Checks/acceptance:** capability/add-compile tests; no executable bool, paired optionals, or rawget; rejection evidence survives fallback.

### SCH-2 — Typed kernel/schedule relations for lower planning

**Evidence:** `impl/lower_emit_c/schedule_form.lua:48-130` uses nil/text indexes; `impl/lower_plan.lua:310-446` uses loop/kernel/schedule maps.

**Define/leaf ownership:** `LowerScheduleByKernelEntry/Projection/Lookup`; `LowerLoopByIdEntry`; `LowerKernelByLoopEntry/Lookup`. Projection lookup, lookup-result, schedule, and lower-strategy leaves own behavior.

**Owned files:** `schema_v2/lower.lua`, `impl/lower_plan.lua`, `impl/lower_emit_c/schedule_form.lua`, new projection test. **Dependencies:** KRN-1, SCH-1. **Out of scope:** carrier/address redesign and instruction lowering.

**Checks/acceptance:** projection/module-wiring tests; no nil or text-key maps; scalar/vector/closed/no-plan are typed.

### CMAT-1 — Canonical schema-v2 C materialization vocabulary

**Evidence:** old bootstrap owns `c_materialize`; schema-v2 omits it while loading the materializer, forcing loose results.

**Define:** checked CMat IDs, loop order/tail/axis/nest, stream/sink/fused/module products; const/restrict/lane capability alternatives; `CMatMaterialization = MaterializedFused|RejectedComputation`.

**Owned files:** new `schema_v2/c_materialize.lua`, `schema_v2/init.lua`, new schema test. **Dependencies:** existing Code, Kernel, Stencil schemas. **Out of scope:** old schema, implementation, LuaJIT/native materializers.

**Checks/acceptance:** schema test and grep for LuaJIT/LuaTrace; checked success/reject constructors; no loose payloads, eligibility booleans, optional computation, or backend imports.

### STN-PLAN — Typed stencil planning and validation

This ID deliberately replaces the planning report's `STN-1`; `STN-1` is already completed/integrated history.

**Evidence:** `impl/stencil_plan.lua:165-190` returns ad hoc producer/validation/codegen records; descriptor building uses loose arguments and stale selections.

**Define/leaf ownership:** typed producer-analysis input/result; descriptor-build/validation inputs; valid/invalid result; codegen-plan input; `StencilCodegenPlan = CMat|Rejected`. Four producer-shape leaves analyze; sink leaves build; access/descriptor/sink leaves validate; selected/no-selection leaves own codegen.

**Owned files:** `schema_v2/stencil.lua`, `impl/stencil_plan.lua`, new methods test. **Dependencies:** CMAT-1. **Out of scope:** materialization and C emission.

**Checks/acceptance:** stencil methods and schedule-selection tests; no kind/valid records, loose input, nil, or fake success; invalid cases are typed.

### DESC-1 — C-neutral access descriptor alternatives

**Evidence:** `schema_v2/stencil.lua:166-233` combines base with optional descriptor and nullable stride facts.

**Define/leaf ownership:** `StencilAccessLayout = Direct|Described`; `StencilStrideFact = Dynamic|Known`. Layout, descriptor, and base leaves own validation, CMat binding, offsets, and layout behavior.

**Owned files:** `schema_v2/stencil.lua`, descriptor portions of `impl/stencil_plan.lua`, `impl/stencil_metastencil.lua`, new tests. **Dependencies:** CMAT-1. **Out of scope:** `stencil_machine.lua` and all `LJExpr` fields.

**Checks/acceptance:** access-layout test; impossible direct/described combinations unconstructable; direct/slice/view/byte/foreign leaves covered.

### DESC-2 — Boundary-neutral machine descriptor spine

**Evidence:** store/reduce/scan/partition/scatter/skeleton products in `schema_v2/stencil_machine.lua` contain optional soup and excluded LuaJIT values.

**Define/leaf ownership:** new neutral `StencilMachineDescriptor` union with complete store/reduce/scan/find/partition/count/scatter leaves; scheduled/explicitly-unscheduled alternatives; value/store/control result alternatives. Each descriptor, schedule, and result leaf validates/projects to `StencilComputation`.

**Owned files:** new `schema_v2/stencil_descriptor.lua` and C-facing tests/producer code. **Dependencies:** STN-PLAN, DESC-1. **Out of scope:** `impl/stencil_machine.lua`, legacy LuaJIT adapters/arguments, compatibility wrappers.

**Checks/acceptance:** descriptor test and no-LuaJIT grep; main C imports no descriptor carrying `LJExpr`; every operation is a complete leaf.

### CMAT-2 — Typed stencil-to-C materialization plan

**Evidence:** `impl/lower_emit_c/materialize.lua:93-299` uses loose access/axis/selector/stream/sink/result records and `input = input or {}`.

**Define/leaf ownership:** `CMatMaterializationInput`, typed loop-policy/access-binding results as needed. Access-role, producer direction/shape, schedule, sink, and computation leaves own complete typed materialization.

**Owned files:** `impl/lower_emit_c/materialize.lua`, new materialization-method test. **Dependencies:** CMAT-1, STN-PLAN, DESC-1. **Out of scope:** CBackend statement emission.

**Checks/acceptance:** focused test; no empty bag, selector strings, semantic booleans, ad hoc records, or permissive parent defaults; success/rejection typed.

### CMAT-3 — CBackend stencil emission and GCC runtime

**Evidence:** `impl/stencil_c.lua` is a placeholder/second path; no schema-v2 planner→CMat→CBackend test exists.

**Define/leaf ownership:** `CMatCEmissionInput`; `CMatCEmission = Emitted|Rejected`. Materialized/rejected, producer, stream, and sink leaves emit typed CBackend nodes. Initial closed scope: range-1D, scalar contiguous access, point expressions, store, and domain fold.

**Owned files:** new `impl/lower_emit_c/stencil.lua`, lower-emit init/assembly, reduce old placeholder to loader, new CMat/CBackend/GCC tests. **Dependencies:** CMAT-2, CLOW-1 typed function result. **Out of scope:** vector and LuaJIT/native materialization.

**Checks/acceptance:** CMat-to-CBackend and GCC tests; validate before emit; assert map/store/fold values; no C text/comments in semantic leaves.

### VAL-1 — Leaf-owned Code IR structural validation

**Evidence:** `schema_v2/code_validation.lua:17-24` is broad/optional; `impl/code_validate.lua` uses classof/string indexes and omits old tested behavior.

**Define/leaf ownership:** named function/block/value ID entries and module projection; function/block inputs and validation step. Module/function/block/instruction wrappers delegate to every concrete op/terminator/type/place leaf.

**Owned files:** `schema_v2/code_validation.lua`, issue-only `schema_v2/code.lua`, `impl/code_validate.lua`, new tests. **Dependencies:** existing signature projection. **Out of scope:** graph/CBackend validation.

**Checks/acceptance:** leaf and existing validation tests; duplicate/missing ID, arity, type, relocation, signature, alignment; no classof, optional machine, or string index; final `Ok|Failed`.

### CVAL-1 — Typed C helper signatures

**Evidence:** `impl/cemit_emit.lua:734-770` returns `{params=..., result=...}` and validator consumes it.

**Define/leaf ownership:** `CBackendHelperSignature { params, result }`; every helper-spec leaf owns `c_helper_signature`, including integer/unary/cast/pointer/div/rem/shift/intrinsic/load/store/memory/trap/atomic helpers.

**Owned files:** `schema_v2/c.lua`, `impl/cemit_emit.lua`, canonical validator, new helper-signature tests. **Dependencies:** none. **Out of scope:** helper bodies and unary rendering.

**Checks/acceptance:** helper-signature and validator tests; no loose signatures; constructor rejects raw records; validator compares typed values.

### CEMIT-1 — Unary operation leaf emission

**Evidence:** `impl/cemit_emit.lua:786-790` branches on `classof(self.op)`.

**Define/leaf ownership:** no semantic selector; `UnaryNeg`, `UnaryNot`, and `UnaryBitNot` own expression formatting; helper unary delegates. Optional `CEmitExpression` only if reused.

**Owned files:** `impl/cemit_emit.lua`, new unary tests. **Dependencies:** CVAL-1 because both edit helper code. **Out of scope:** other operators/signatures.

**Checks/acceptance:** unary leaf test; no classof branch; generated `-`, `!`, `~` C compiles.

### CLOW-1 — Typed C instruction/function lowering results

**Evidence:** lower-emit uses loose accumulators/results, text maps, and a variant value-type side map.

**Define/leaf ownership:** `LowerCInstEmission`, `LowerCFunctionEmission`, named signature/value-type entries/projections. Every instruction/terminator leaf lowers; function and module roots compose typed results.

**Owned files:** `schema_v2/lower.lua`, `schema_v2/c.lua`, `impl/lower_emit_c.lua`, `impl/lower_emit_c/code_to_c.lua`, new tests. **Dependencies:** VAL-1, CVAL-1, CEMIT-1. **Out of scope:** advanced vector/stencil and process execution.

**Checks/acceptance:** lowering/module/instrop tests; no loose accumulators/text semantic maps; scalar GCC runtime value.

### CVAL-2 — Canonical CBackend validation

**Evidence:** `impl/lower_emit_c/validate.lua` traverses nonexistent fields and constructs a nonexistent result while the real validation input/report is in `schema_v2/c.lua`.

**Define/leaf ownership:** retain `CBackendValidationInput/Report/Issue`; named signature/function/global/extern/helper/local/label relations. Unit/body/type/atom/place/rvalue/statement/target/term/helper/data/relocation leaves own validation.

**Owned files:** `schema_v2/c.lua`, canonical validator, remove/stop loading stale validator, new tests. **Dependencies:** CVAL-1, CLOW-1, OWN-0. **Out of scope:** GCC/TCC execution and annotations.

**Checks/acceptance:** validator and canonical-context tests; one validator/report, no string semantic state; negative assertions and GCC smoke.

## Milestone 4 — Canonical Schema Ownership Packages

### OWN-0 — Ownership inventory and ambiguity guard

**Evidence:** old/v2 bootstraps coexist; public facades route separate compilers; `tests/run.lua` omits schema-v2. Exactly **25** names are duplicated: `bind check c code compiler core effect exec flow graph init kernel lower mem parse phase project schedule sem source stencil stencil_machine tree type value`.

**Define/ownership:** repository ownership metadata, not semantic ASDL. Own new `docs/SCHEMA_OWNERSHIP.md`, inventory test, and `tests/run.lua`. **Dependencies:** none; start immediately. **Out of scope:** moving/deleting modules.

**Checks/acceptance:** ownership inventory and schema suite; assert 25, one intended owner per namespace, legitimate Host boundary, explicit LuaJIT/LuaTrace exclusion, and failure on new ambiguity.

### OWN-FRONT — Canonical frontend/closure ownership

**Evidence/target:** old and v2 modules define the same frontend namespaces, and without cutover closure semantics require two implementations. Canonical target is schema-v2 `core parse source type bind sem tree check tree_code`; completed CLO methods attach only to canonical concrete classes. No old→new conversion methods.

**Owned files:** corresponding schema pairs, frontend wiring/imports, closure tests, ownership manifest. **Dependencies:** CLO-3, OWN-0, typed check ownership. **Out of scope:** analysis, stencil, C, Host.

**Checks/acceptance:** frontend-complete, closure, frontend suite; one constructor identity; parsed/builder convergence; remove old only after zero consumers; no wrappers/mixed contexts.

### OWN-ANALYSIS — Canonical code-analysis ownership

**Evidence/target:** every `code graph flow value mem effect kernel schedule lower` namespace is duplicated; active implementations import schema-v2 while old code-IR tests still instantiate `require("lalin.schema")`. MEM/EFF/KRN/SCH methods and projection identities become canonical on one set of concrete leaves.

**Owned files:** corresponding pairs; graph/flow/value/mem/effect/kernel/schedule/lower implementations; test imports. **Dependencies:** MEM-4, EFF-2, KRN-1, SCH-2, OWN-0. **Out of scope:** C materialization/public facade.

**Checks/acceptance:** code-IR suite and add-compile; one identity per fact, no adapters, port old tests before removal, scalar GCC remains green.

### OWN-STENCIL — Canonical stencil/CMat ownership

**Evidence/target:** the old schema alone owns `LalinCMat`, schema-v2 materialization returns a parallel untyped model, and `stencil_machine` mixes excluded LuaJIT values with semantic descriptors. Canonical target is `schema_v2/stencil.lua`, neutral DESC-2, and `schema_v2/c_materialize.lua`; planning/materialization/emission methods attach only there.

**Owned files:** old/new stencil/CMat schemas, C-facing implementations/tests, ownership manifest. **Dependencies:** STN-PLAN, DESC-1, DESC-2, CMAT-3, OWN-0. **Out of scope:** LuaJIT/LuaTrace adapters.

**Checks/acceptance:** stencil-plan, CMat-materialize, GCC tests; one neutral main-C vocabulary, no backend imports, old CMat removed only after migration, runtime values asserted.

### OWN-C — Canonical Code validation and C lowering ownership

**Evidence/target:** public and v2 pipelines instantiate different `LalinCode`/`LalinC` classes, with duplicate validators/lowerers and incompatible result assumptions. Canonical target is `code code_validation c cemit backend compiler exec`; VAL/CLOW/CVAL/CEMIT behavior attaches only to canonical concrete leaves, while process execution remains IO-boundary plumbing.

**Owned files:** corresponding schema pairs, validators/lowering, compiler wiring, C tests. **Dependencies:** VAL-1, CVAL-2, CLOW-1, OWN-0. **Out of scope:** process-option redesign, LuaJIT/native.

**Checks/acceptance:** module wiring, validator, C-backend suite; one `LalinCode`/`LalinC`, no old implementation in canonical context, no aliases, GCC value after cutover.

### OWN-META — Phase/project ownership

**Evidence/target:** duplicated phase/project/exec are not prerequisites. Add no semantic type unless migration exposes a precise missing union; concrete canonical leaves retain behavior.

**Owned files:** schema pairs, phase/project/exec implementations, compiler-process tests. **Dependencies:** OWN-0; after compiler/C contracts stabilize. **Out of scope:** compiler-process implementation changes beyond imports.

**Checks/acceptance:** phase plan/validate/execute tests; one identity, no mixed contexts/adapters.

### OWN-CUTOVER — Public facade and old-tree retirement

**Evidence:** public old-schema and explicit v2 pipelines remain separate ownership islands.

**Owned files:** `init.lua`, compiler facade/wiring, public GCC tests, final bootstrap consolidation, architecture/status docs. **Dependencies:** OWN-FRONT, OWN-ANALYSIS, OWN-STENCIL, OWN-C, OWN-META. **Out of scope:** LuaJIT/LuaTrace/native.

**Checks/acceptance:** add-compile, aggregate-lowering, default suite, public scalar and aggregate/union GCC runtime; parsed/builder convergence; no separate v2 island; one bootstrap; delete old only after zero consumers; no wrappers.

### Parallel execution and mandatory serialization

Safe independent starts after the refreshed M0 gate: `OWN-0`, `CLO-1`, `MEM-1`, `CMAT-1`, `VAL-1`, and `CVAL-1`. Closure, memory/effect, validation, and helper-emission chains can proceed independently. `STN-PLAN` and `DESC-1` may overlap only with explicit line ownership.

| Serialize | Shared ownership |
|---|---|
| CLO-1/2/3 | `schema_v2/sem.lua`, `impl/tree_closure.lua` |
| MEM-1/2/3/4 | `schema_v2/mem.lua`, `impl/code_mem.lua` |
| EFF-1/2 | `schema_v2/effect.lua`, `impl/code_effect.lua` |
| KRN-1/SCH-1/SCH-2 | kernel/schedule/lower method contracts |
| CMAT-1/bootstrap | `schema_v2/init.lua` |
| STN-PLAN/DESC-1 | `schema_v2/stencil.lua`, `impl/stencil_plan.lua` |
| DESC-1/CMAT-2/CMAT-3 | materializer and CMat method contracts |
| CVAL-1/CEMIT-1 | `impl/cemit_emit.lua` |
| CLOW-1/CVAL-2 | C/lower schemas and validation contracts |
| OWN-* | corresponding completed semantic package |
| OWN-CUTOVER | all ownership migrations and bootstraps |

Ownership packages may prepare in parallel after interfaces freeze, but final imports, deletions, and bootstrap edits are serialized.

### Exact focused command matrix

Bare package summaries above do not replace these assignment commands. Each package also runs its relevant category suite and the default-suite no-regression gate.

| Package | Focused commands |
|---|---|
| CLO-1 | `luajit tests/schema_v2/test_closure_semantic_schema.lua`; `luajit tests/run.lua schema` |
| CLO-2 | `luajit tests/schema_v2/test_closure_capture_leaves.lua`; `luajit tests/schema_v2/test_closure_convert.lua` |
| CLO-3 | `luajit tests/schema_v2/test_closure_convert.lua`; `luajit tests/schema_v2/test_frontend_complete.lua`; `luajit tests/run.lua frontend` |
| MEM-1 | `luajit tests/schema_v2/test_code_mem_contract_projection.lua`; `luajit tests/run.lua schema` |
| MEM-2 | `luajit tests/schema_v2/test_code_mem_place_leaves.lua` |
| MEM-3 | `luajit tests/schema_v2/test_code_mem_instruction_leaves.lua` |
| MEM-4 | `luajit tests/schema_v2/test_code_mem_dependence_leaves.lua`; `luajit tests/run.lua code_ir` |
| EFF-1 | `luajit tests/schema_v2/test_code_effect_contract_call_leaves.lua` |
| EFF-2 | `luajit tests/schema_v2/test_code_effect_instruction_leaves.lua`; `luajit tests/schema_v2/test_code_effect_pipeline.lua`; `luajit tests/run.lua code_ir` |
| KRN-1 | `luajit tests/schema_v2/test_kernel_plan_leaf_ownership.lua`; `luajit tests/schema_v2/test_kernel_plan_module.lua`; `luajit tests/schema_v2/test_add_compile.lua` |
| SCH-1 | `luajit tests/schema_v2/test_schedule_capability_leaves.lua`; `luajit tests/schema_v2/test_add_compile.lua` |
| SCH-2 | `luajit tests/schema_v2/test_lower_schedule_projection.lua`; `luajit tests/schema_v2/test_module_emit_wiring.lua` |
| CMAT-1 | `luajit tests/schema_v2/test_cmat_schema.lua`; `rg -n 'LalinLuaJIT\|LuaTrace' lua/lalin/schema_v2/c_materialize.lua` |
| STN-PLAN | `luajit tests/schema_v2/test_stencil_plan_methods.lua`; `luajit tests/code_ir/test_stencil_schedule_selection.lua` |
| DESC-1 | `luajit tests/schema_v2/test_stencil_access_layout_alternatives.lua` |
| DESC-2 | `luajit tests/schema_v2/test_stencil_descriptor_alternatives.lua`; `rg -n 'LalinLuaJIT\|LuaTrace' lua/lalin/schema_v2/stencil_descriptor.lua` |
| CMAT-2 | `luajit tests/schema_v2/test_cmat_materialize_methods.lua` |
| CMAT-3 | `luajit tests/schema_v2/test_cmat_to_cbackend.lua`; `luajit tests/c_backend/test_stencil_c_gcc.lua` |
| VAL-1 | `luajit tests/schema_v2/test_code_validate_leaves.lua`; `luajit tests/code_ir/test_code_validate.lua` |
| CVAL-1 | `luajit tests/schema_v2/test_c_helper_signatures.lua`; `luajit tests/c_backend/test_emit_c_validate.lua` |
| CEMIT-1 | `luajit tests/schema_v2/test_cemit_unary_leaves.lua` |
| CLOW-1 | `luajit tests/schema_v2/test_c_lowering_results.lua`; `luajit tests/schema_v2/test_module_emit_wiring.lua`; `luajit tests/schema_v2/test_code_to_c_instrops.lua` |
| CVAL-2 | `luajit tests/c_backend/test_emit_c_validate.lua`; `luajit tests/schema_v2/test_cbackend_validation.lua` |
| OWN-0 | `luajit tests/schema/test_schema_ownership_inventory.lua`; `luajit tests/run.lua schema` |
| OWN-FRONT | `luajit tests/schema_v2/test_frontend_complete.lua`; `luajit tests/schema_v2/test_closure_convert.lua`; `luajit tests/run.lua frontend` |
| OWN-ANALYSIS | `luajit tests/run.lua code_ir`; `luajit tests/schema_v2/test_add_compile.lua` |
| OWN-STENCIL | `luajit tests/schema_v2/test_stencil_plan_methods.lua`; `luajit tests/schema_v2/test_cmat_materialize_methods.lua`; `luajit tests/c_backend/test_stencil_c_gcc.lua` |
| OWN-C | `luajit tests/schema_v2/test_module_emit_wiring.lua`; `luajit tests/c_backend/test_emit_c_validate.lua`; `luajit tests/run.lua c_backend` |
| OWN-META | `luajit tests/compiler_process/test_phase_plan.lua`; `luajit tests/compiler_process/test_phase_validate.lua`; `luajit tests/compiler_process/test_phase_execute.lua` |
| OWN-CUTOVER | `luajit tests/schema_v2/test_add_compile.lua`; `luajit tests/schema_v2/test_aggregate_lowering.lua`; `luajit tests/run.lua`; public scalar and aggregate/union `compile_c_gcc` runtime tests |

For every migrated semantic boundary, audit owned files with `rg -n 'classof|rawget|return \{| or \{\}|executable \[bool\]' <owned-files>`. Every remaining match must be demonstrated to be formatting/IO-only. C-affecting packages validate `CBackendUnit`, emit C, compile with GCC, execute, and assert a value.


## Milestone 5 — Validation, Documentation, and Release Gates

For every work package:

- [ ] Its focused regression checks pass.
- [ ] Its relevant category suite passes.
- [ ] The default suite is run and gains no failures relative to the refreshed M0 ledger.
- [ ] Before M0 is green, unrelated known failures remain ledgered rather than becoming the package's responsibility.
- [ ] Slow/experimental profiles run only when the package explicitly owns them; current LuaTrace/LuaJIT/native exclusions are not release priorities.
- [ ] Emitted C is validated, compiled with GCC, executed, and checked for runtime values where applicable.
- [ ] An independent reviewer checks ASDL ownership/doctrine compliance.
- [ ] Integrated changes are synchronized into active worktrees.

Release-level gates:

- [ ] Default suite passes with zero failures.
- [ ] Experimental profiles have explicit commands and expected results.
- [ ] `emit_c` coverage declarations match executable tests.
- [ ] `LANGUAGE_REFERENCE.md` status notes match proven support.
- [ ] `ARCHITECTURE.md` describes GCC-over-`emit_c` as the main backend.

## Work-Package Queue

| Order | ID | Priority | Dependencies | Scope | Status/owner |
|---:|---|---:|---|---|---|
| history | RGN-1 | P0 | none | Region helper restoration | integrated `82ec214af`; approved |
| history | STN-1 | P0 | none | Stencil semantic construction | integrated `35c1ce5a3`; approved |
| history | STN-SCHED | P0 | STN-1 | Typed schedule selection | integrated `d66eff0b6`; approved |
| history | LAY-1 | P0 | STN-1 | Layout projection | integrated `00303c45b`; approved |
| history | TYP-1 | P0 | none | Frontend target projection | integrated `1750e4ce5`; approved |
| history | TYP-OWN | P0 | none | Canonical check ownership | integrated `ae2a8e164`; approved |
| history | ABI-SIG | P0 | LAY-1 | Required signatures | integrated `c95973fd5`; approved |
| history | ABI-STATE | P0 | ABI-SIG | Cross-unit isolation | integrated `f7ba18a`; approved |
| history | CMP-1 | P1 | none | Compiler-process contracts | integrated `7b983824`; approved |
| history | M0.1 | P0 | CMP-1 | Refreshed failure ledger/baseline | complete at `af80ae43` source |
| current-A | AUX-FUNC-ABI | P1 | M0 refresh | ABI harness classification | working `w4:p1K` |
| current-B | AUX-TYPE-C | P1 | M0 refresh | Canonical type-to-C test | review `bfbdf4569` by `w4:p6` |
| current-C | AUX-CLOSURE-NAME | P1 | M0 refresh | Module-name method binding | working `w4:p1M` |
| 4 | LNG-DIAG | P1 | M0 refresh | Unsupported control diagnostics | planned |
| 5 | LNG-LOOP-C | P1 | integrated stencil/layout | Parsed loop GCC matrix | planned |
| 6 | LNG-EXT-C | P1 | AUX ABI/type | Extern/builder/HostEval GCC | planned |
| 7 | LNG-REG-C | P1 | RGN-1, LAY-1 | Region protocol GCC | planned |
| 8 | LNG-EXPR-C | P1 | optional LNG-DIAG | Expressions through GCC | planned |
| 9 | LNG-VAR-C | P2 | optional LNG-EXPR-C | Variants/identity | planned |
| 10 | LNG-OWN-C | P2 | optional LNG-REG-C | Ownership/domain runtime | planned |
| M3-A | CLO-1→3 | P1 | M0 refresh | Closure vocabulary/collection/rewrite | planned |
| M3-B | MEM-1→4→EFF-1→2 | P1 | M0 refresh | Memory/effect facets and leaves | planned |
| M3-C | KRN-1→SCH-1→2 | P1 | MEM/EFF | Kernel/schedule leaves | planned |
| M3-D | CMAT-1→STN-PLAN/DESC-1→DESC-2→CMAT-2→3 | P1 | M0 refresh | Neutral stencil/CMat C path | planned |
| M3-E | VAL-1 + CVAL-1→CEMIT-1→CLOW-1→CVAL-2 | P1 | M0 refresh | Validation/C lowering | planned |
| M4 | OWN-0→OWN-FRONT/ANALYSIS/STENCIL/C/META→CUTOVER | P2 | completed M3 boundaries | Canonical ownership | planned |
| deferred | LJBC-STENCIL/native/slow binary | — | owner decision | Explicit non-main profiles | stopped/not scheduled |

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
- **2026-07-11:** Milestones 2–4 are assigned as bounded packages with explicit ASDL vocabulary, leaf ownership, files, dependencies, exclusions, and tests; the planned stencil package is `STN-PLAN` because `STN-1` is completed history.
- **2026-07-11:** Schema ownership inventory counts 25 duplicate names. C helper signature evidence is `impl/cemit_emit.lua:734-770`.
- **2026-07-11:** After CMP-1, M0 baseline refresh is the next gate. Until M0 is green, package gates require focused tests, the relevant suite, and no default-suite regression—not repair of unrelated failures.

