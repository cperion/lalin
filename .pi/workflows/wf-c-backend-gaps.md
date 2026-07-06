# C Backend Lowering Gaps — Semantic Fact Consumption Survey 
Survey of the C backend lowering pipeline to find where semantic facts available in upstream ASDL layers are lost or incompletely lowered, informed by machine-code analysis of the Lua VM demo dispatch loop.
**Workflow ID**: wf-c-backend-gaps
**Started**: 2026-07-06 20:01:38
---

## Scout Output — 2026-07-06 20:05:09

Now I have a thorough picture. Here is my comprehensive report:

---

## Files Retrieved

1. `/home/cedric/dev/lalin/lua/lalin/schema/c.lua` (lines 1-660) — C backend ASDL: defines `CBackendSwitchGoto`, `CBackendIfGoto`, `CBackendQualifiedDataPtr`, `CBackendTerminator`, and all C IR types
2. `/home/cedric/dev/lalin/lua/lalin/lower_to_c.lua` (lines 1-2199) — The main lowering pipeline: semantic kernel → CMat inline → CBackendBlock emission for the `emit_c` path; contains both the `code_to_c` path and `emit_c` path dispatch
3. `/home/cedric/dev/lalin/lua/lalin/code_to_c.lua` (lines 1-1359) — Baseline C lowering from `CodeFunc` → `CBackendFunc` with carrier/address plan consumption (the non-semantic path)
4. `/home/cedric/dev/lalin/lua/lalin/emit_c_lower.lua` (lines 1-1284) — Final C text emission helpers (`c_emit_func`, `c_emit_term`, etc.) including block deduplication and copy propagation
5. `/home/cedric/dev/lalin/lua/lalin/stencil_c.lua` (lines 1-1555) — The handwritten C stencil compiler that generates C with `__builtin_assume_aligned`, `C.restrict`, and loop nests
6. `/home/cedric/dev/lalin/lua/lalin/exec_plan.lua` (lines 1-226) — Execution fragment planning for the stencil artifact path
7. `/home/cedric/dev/lalin/lua/lalin/schema/code.lua` (lines 1-450) — Code IR ASDL: defines `CodeTermBranch`, `CodeTermSwitch`, `CodeTermVariantSwitch`, `CodeMemoryAccess`, trip count facts in `CodeContractFact`
8. `/home/cedric/dev/lalin/lua/lalin/schema/lower.lua` (lines 1-225) — Lower IR ASDL: `LowerCarrierPlan`, `LowerAddressPlan`, `LowerCarrierEdgeSource` variants
9. `/home/cedric/dev/lalin/lua/lalin/schema/kernel.lua` (lines 1-275) — Kernel plan ASDL: kernel domains, trip counts, and skeleton selections
10. `/home/cedric/dev/lalin/lua/lalin/schema/flow.lua` (lines 1-315) — Flow facts ASDL: `FlowTripCount`, `FlowTripCountExact`, `FlowCountedDomain`, flow loop facts
11. `/home/cedric/dev/lalin/lua/lalin/schema/value.lua` (lines 1-195) — Value facts ASDL: `ValueRange`, `ValueRangeInt`, `ClosedFormFact`, `ValueFactSet`
12. `/home/cedric/dev/lalin/lua/lalin/schema/stencil.lua` (lines 1-700) — Stencil ASDL: `StencilTripCountFact`, `StencilSchedule`, `StencilVectorizationFacts`, `StencilAlignmentFact`
13. `/home/cedric/dev/lalin/lua/lalin/schema/c_materialize.lua` (lines 1-120) — CMat materialization ASDL: `CMatVectorPolicy`, `CMatTailPolicy`, `CMatLoopNest`
14. `/home/cedric/dev/lalin/lua/llbl/c.lua` (lines 300-420) — The `llbl.c` LLBL C module that emits `__builtin_assume_aligned`, `restrict`, and manages C expression generation

---

## Key Code & Findings

### 1. Dispatch Strategy: Region Bundle Entry Block → `CBackendIfGoto` Chains vs `CBackendSwitchGoto`

**The schema supports both paths:**
- `c.lua:589` — `CBackendSwitchGoto` exists as a full ASDL sum leaf with value, cases, and default destination
- `c.lua:581` — `CBackendIfGoto` exists for binary condition dispatch

**Code IR preserves switch semantics:**
- `code.lua:380-396` — `CodeTermSwitch` and `CodeTermVariantSwitch` are both sum leaves in `CodeTermOp` with per-case destinations and arg lists

**Both lowering pipelines faithfully pass through the term shapes:**
- `code_to_c.lua:690-706` — `CodeTermSwitch` → `CBackendSwitchGoto`, `CodeTermBranch` → `CBackendIfGoto` (direct 1:1 translation)
- `lower_to_c.lua:461-463` — Identical 1:1 translation: `CodeTermSwitch` → `CBackendSwitchGoto`, `CodeTermVariantSwitch` → `CBackendSwitchGoto`

**GAP: No `CBackendSwitchGoto` used for region entry block dispatch in the CMat kernel path.** The inline CMat kernel path (`emit_scalar_kernel_fragment`) explicitly uses only `CBackendIfGoto`/`CBackendGoto`:
- `lower_to_c.lua:1484-1508` — loop header dispatch is `CBackendIfGoto` (at line 1487, 1490, 1508, 1522)

**GAP: `CBackendSwitchGoto` exists but is never created by any lowering logic** — it's only produced by the direct 1:1 translation of `CodeTermSwitch` and `CodeTermVariantSwitch`. If the source program doesn't use switch/variant-switch, no `CBackendSwitchGoto` is ever emitted. The kernel loop dispatch (region entry) is always lowered to `CBackendIfGoto` chains regardless of case count.

**GAP: The `CodeTermBranch` → `CBackendIfGoto` path has no optimization for if/else-if chains.** When a region entry block performs dispatch over N cases, the Code IR may produce a chain of `CodeTermBranch` terminators across N blocks. Each becomes a separate `CBackendIfGoto`. There is no pass that re-synthesizes these into a `CBackendSwitchGoto` even when the conditions are all equality checks against a small integer tag.

**Additionally, the `stencil_c.lua` path completely bypasses both `CBackendIfGoto` and `CBackendSwitchGoto`.** It generates loops using `C.for_`, `C.if_`, etc. from `llbl.c` — these are NOT `CBackendIfGoto`/`CBackendSwitchGoto` at all but direct C AST nodes emitted through a separate channel.

---

### 2. Branch Hints / Profile

**GAP: No `__builtin_expect`, `likely`, `unlikely`, or branch probability anywhere in the pipeline.**

Searched across all ~25 lua files in `lua/lalin/` — only hit was `error/suggest.lua` which is a suggestion engine for error messages, not compiler lowering.

The `stencil_c.lua` uses GNU C builtins (`C.builtin.assume_aligned`, `C.builtin.isnan`, etc.) but never `__builtin_expect`. The `emit_c_lower.lua` `CBackendIfGoto:c_emit_term` emits a plain `if (...) {...} else {...}` with no hint attributes.

**GAP: No `cold` attribute on error/unreachable paths.** `CBackendTrap:c_emit_term` emits `abort();` with no `__attribute__((cold))` or `__builtin_unreachable()` annotation to tell GCC the path is cold.

**GAP: The ASDL has no branch-frequency or dispatch-policy facts.** There is no sum/product in `code.lua`, `c.lua`, or any other schema that records branch probabilities, expected case frequencies, or dispatch heuristics. The `StencilSchedule` has `StencilOptLevel` but that governs compiler flags, not per-branch hints.

---

### 3. Alignment Facts

**The ASDL pipeline has rich alignment data:**
- `code.lua:213-217` — `CodePlaceField` and `CodePlaceDeref` carry `align [optional [number]]`
- `code.lua:228-230` — `CodeMemoryAccess` carries `align [number]`
- `c.lua:93-98` — `CBackendQualifiedDataPtr` carries `const_pointee`, `restrict_ptr`, `volatile_pointee`
- `c.lua:245-250` — `CBackendPlaceDeref` carries `align [optional [number]]`
- `stencil.lua:429-431` — `StencilAlignmentFact` enum: `StencilAlignmentKnown { bytes [number] }`
- `stencil.lua:465-468` — `StencilAccessVectorFact.alignment` carries this fact

**Alignment flows through the CMat pipeline in `stencil_c.lua`:**
- `stencil_c.lua:99-103` — `access_alignment_bytes` extracts known alignment from artifact facts
- `stencil_c.lua:414-419` — `assume_aligned_stmts` generates `C.assign(cn(name), C.builtin.assume_aligned { cn(name), bytes })` for each pointer access — this emits `ptr = __builtin_assume_aligned(ptr, N)`
- This is used at 11 call sites for each artifact shape (lines 1178, 1189, 1248, etc.)

**GAP: Alignment from `CodePlaceField.align` and `CodeMemoryAccess.align` is stored in CBackendPlace but never emitted as `__builtin_assume_aligned` in the `emit_c_lower.lua` path.** The field `PlaceDeref.align` is stored but `c_emit_place` and `c_emit_place_typed` ignore it. It's only used for ABI classification (`type_abi_classify.lua`).

**GAP: `CBackendQualifiedDataPtr.align` does not exist.** Despite `CodePlaceField` carrying `align`, the CBackend pointer types have `const_pointee`, `restrict_ptr`, and `volatile_pointee` but no `alignment` field. There's no way for the backend to express "this pointer is known to be N-byte aligned" as a type qualifier.

**GAP: `CBackendQualifiedDataPtr` is never produced by `code_type_to_c`** — only `CBackendDataPtr` is. `CBackendQualifiedDataPtr` is exclusively produced in `lower_to_c.lua:1770-1775` via `lower_c_with_param_qualifiers`, which is the CMat `restrict` path. The non-CMat baseline code path never generates qualified pointers.

---

### 4. Trip Count / Range Facts

**The ASDL pipeline has extensive trip count and range data:**
- `flow.lua:88-98` — `FlowTripCount`: `FlowTripCountExact { count [CodeValueId] }`, `FlowTripCountNonNegative { count [CodeValueId] }`, `FlowTripCountUnknown`
- `flow.lua:262-264` — `FlowLoopNormalizedCounted` carries `trip_count [FlowTripCount]`
- `value.lua:89-97` — `ValueRange`: `ValueRangeInt` with lo/hi/inclusive_hi
- `code.lua:403-412` — `CodeContractBounds`, `CodeContractWindowBounds` carry explicit value-range bounds
- `code.lua:347-349` — `CodeIntAssumeNoOverflow { reason [str] }` carries overflow assumption facts
- `kernel.lua:54` — `KernelDomainFlow` carries `trip_count [FlowTripCount]`

**Trip count is consumed in the kernel plan layer:**
- `code_kernel_plan.lua:190-194` — `semantic_trip_counts` extracts `FlowTripCount` from `FlowLoopNormalizedCounted` facts
- `code_kernel_plan.lua:1229` — Passes trip count into `KernelDomainFlow`
- `code_kernel_plan.lua:1312` — Falls back to `FlowTripCountUnknown("no semantic trip-count fact")`

**The CMat C path consumes `FlowCountedDomain.start`/`stop`/`step`:**
- `lower_to_c.lua:1160-1168` — `producer_for_kplan` extracts `counted.start`, `counted.stop`, `counted.step` to build `StencilProducer`
- `lower_to_c.lua:1480-1484` — `emit_scalar_kernel_fragment` uses `counted.stop` to compute the domain exit condition: `counter == stop`

**GAP: Trip count is consumed structurally (start/stop/step) but `FlowTripCount` itself is NOT lowered to C pragmas or `__builtin_assume`.** When `FlowTripCountExact(count)` exists, nothing emits `__builtin_assume(counter < count)` or any loop-count pragma that GCC could use for loop optimization.

**GAP: `ValueRange` facts are not lowered to C.** `ValueRangeInt` with lo/hi exists in the value fact layer (`value.lua:91-97`) and is used by the kernel plan builder, but nothing in `lower_to_c.lua` or `emit_c_lower.lua` reads these and emits `__builtin_assume(v >= lo && v <= hi)`.

**GAP: `CodeIntAssumeNoOverflow` exists** and is lowered through the helper signature (`CBackendIntAssumeNoOverflow`), but the helper body just emits `return a + b` without any `__builtin_assume` hint — it relies on `-fwrapv` or `-fno-strict-overflow` flags. The `IntrinsicAssume` helper checks and aborts, it doesn't hint.

**GAP: `StencilTripCountFact` (from stencil.lua:414-418) with `StencilTripCountExact` and `StencilTripCountMultipleOf` exists in the stencil facts but is consumed only by the native/residual path. In `stencil_c.lua`, the loop is emitted with `C.for_` and the trip count fact is never used for pragma or peel hints.**

---

### 5. Vectorization Hints

**The stencil C pipeline (`stencil_c.lua`) emits `__builtin_assume_aligned` and `restrict` but NO `#pragma` directives, `ivdep`, `omp simd`, or `__attribute__((optimize(...)))`.**

The handwritten stencil compiler generates:
- `__builtin_assume_aligned` (line 419) — alignment hints on pointers
- `C.restrict[ptr_ty]` (line 732) — restrict qualifier when noalias is proven
- `C.builtin.trap` (lines 882, 900, 906, 1270) — for error/unreachable paths

But there are ZERO:
- `#pragma GCC ivdep`
- `#pragma omp simd`
- `#pragma clang loop vectorize(enable)`
- `__attribute__((optimize("O3")))` on hot functions
- `#pragma unroll`
- `__attribute__((aligned(N)))` on types or variables

**The `CMat` schema has vectorization policy types:**
- `c_materialize.lua:58-73` — `CMatVectorPolicy`: `CMatVectorAutovec` (with lanes/tail), `CMatVectorExplicit` (with lanes/tail), `CMatVectorNone`
- `c_materialize.lua:52-56` — `CMatTailPolicy`: `CMatTailScalar`, `CMatTailMask`, `CMatTailOverreadProvenSafe`
- `c_materialize.lua:76-82` — `CMatLoopNest` carries `vector [CMatVectorPolicy]`, `unroll [number]`, `interleave [number]`

**GAP: `CMatVectorPolicy` and `CMatLoopNest` exist in the schema but are NOT used in the inline CMat emission path.** The `emit_c_materialize.lua` materializes `CMatFusedKernel` but `lower_to_c.lua:1754-1756` says:
> "Vector scheduling is now a CMat policy, not a separate direct KernelEffect emitter. Until CMat vector bodies are richer, emit the same inline CMat SOAC body and let the C compiler see the canonical stencil computation"

This means vector lane count, unroll factor, and interleave from `StencilScheduleVector` are DISCARDED when lowering to inline C (the `emit_c` path). The handwritten `stencil_c.lua` path (residual artifact path) does use these facts, but the `lower_to_c.lua`/`code_to_c.lua` pipeline does not.

**GAP: No `#pragma` or GCC attribute is ever emitted for any helper function.** Each helper is `static inline` with no optimization attributes.

---

### 6. Redundant Code / Tail Merging

**`emit_c_lower.lua` has two deduplication/optimization passes on CBackend blocks, but no tail merging:**

1. **Transfer equivalence** (`compute_transfer_equivalence`, lines 773-812): This is a local value numbering / congruence analysis that canonicalizes block parameters. If all predecessors of a block pass the same value to a parameter, it unifies the name. This is a form of value equivalence, not block merging.

2. **Copy propagation + dead copy elimination** (lines 663-750): `copy_propagate_block` and `remove_dead_copy_assigns` run within a single block to eliminate redundant copies.

3. **Field hoisting** (`plan_field_hoists`, lines 814-865): Hoists repeated `ptr->field` loads to a local when used ≥3 times from a parameter base. This is load hoisting, not tail merging.

**GAP: No tail merging.** If two blocks end with the same sequence of statements and the same terminator, they are emitted as separate label blocks. No pass looks for identical block suffixes and merges them via a shared label.

**GAP: Error paths don't share code.** When a kernel body has multiple blocks that all lower to `CBackendTrap`, each gets its own label block emitting `abort();`. There is no `marge_trap_blocks` pass that would have all trap-returning blocks jump to a single shared trap label.

**GAP: Edge transfer blocks** (`edge_transfer_blocks` in `lower_to_c.lua:1996-2006`) create synthetic blocks for carrier/address arg computation when preambles are needed. These are never deduplicated — if two edges need the same computation, they each get their own block.

---

### 7. Carrier/Address Plan Consumption

**The ASDL schema has a rich set of carrier/address plan variants:**
- `lower.lua:97-121` — `LowerCarrierEdgeSource`: `Recompute`, `CarrySame`, `CarryConst`, `CarryDynamic`
- `lower.lua:143-157` — `LowerAddressEdgeSource`: `RecomputeFromCarrier`, `CarrySame`, `CarryConstBytes`, `CarryDynamicBytes`

**Both `lower_to_c.lua` and `code_to_c.lua` fully consume these plans:**
- `lower_to_c.lua:1866-1909` — All four `LowerCarrierEdgeSource` variants have leaf methods producing `CBackendAtom` + preamble stmts
- `lower_to_c.lua:1920-1952` — All four `LowerAddressEdgeSource` variants have leaf methods
- `code_to_c.lua:747-803` — Identical parallel implementation

**GAP: `CarryConst` and `CarryDynamic` always recompute eagerly.** Both produce `carrier_next = carrier + amount` via `CBackendHelperCall` at every edge transfer point. There is no recognition that GCC would optimize this better if the induction were restructured: `CarryConst` with `amount=1` is exactly a `for (i = start; i < stop; i++)` pattern. The carrier plan lowers this as `i_next = i + 1; goto header`, which GCC can see through, but a direct `i++` in the loop header would produce better debug info and be more idiomatic.

**GAP: `Recompute` variants compute `base + index * elem_size` at every edge transfer point.** When multiple edges from the same block share the same carrier/address and bridge to different destinations, the same recomputation is done independently for each edge. The `edge_transfer_dest` mechanism creates synthetic blocks that each independently recompute, with no CSE across them.

**GAP: No invariant hoisting from `Recompute`.** If the base pointer and element size are loop-invariant (which they always are for a single kernel lane), `Recompute` still recomputes `base + index * elem_size` inside the loop body or edge transfer block. The `plan_field_hoists` pass could theoretically hoist the constant part but it only operates on `ptr->field` loads, not on `RPtrOffset` computations.

---

### 8. Aliasing Facts

**The ASDL pipeline has comprehensive aliasing data:**
- `c.lua:93-98` — `CBackendQualifiedDataPtr` has `restrict_ptr [bool]`, `const_pointee [bool]`, `volatile_pointee [bool]`
- `code.lua:414-416` — `CodeContractNoAlias`, `CodeContractDisjoint` provide source-level aliasing contracts
- `stencil.lua:420-422` — `StencilAliasFact`: `StencilAliasUnknown`, `StencilAliasNoAlias`, `StencilAliasMayAlias`
- `stencil.lua:455-458` — `StencilAccessAliasFact` pairs access refs with alias relations
- `c_materialize.lua:28` — `CMatAccessBinding.restrict_eligible [bool]`

**The CMat path consumes noalias facts and emits `restrict`:**
- `lower_to_c.lua:810-819` — `lower_c_access_noalias` checks `StencilFusionAccessAliasRelation` facts
- `lower_to_c.lua:822-838` — `lower_c_access_restrict_proven` checks all-against-all pairwise noalias, then sets `restrict_ptr = true` in `c_param_qualifiers`
- `lower_to_c.lua:1768-1777` — `CBackendDataPtr:lower_c_with_param_qualifiers` upgrades to `CBackendQualifiedDataPtr(pointee, false, true, false)` when `restrict_ptr` is set
- `emit_c_lower.lua:94-100` — `CBackendQualifiedDataPtr:c_emit_type` emits `const T*`, `volatile T*`, or `T* restrict`

**GAP: `CBackendQualifiedDataPtr` is never produced by the baseline `code_to_c.lua` / `code_type_to_c.lua` path.** Only `CBackendDataPtr` is produced. The `QualifiedDataPtr` variant is exclusively created via `apply_c_param_qualifiers` in `lower_to_c.lua`, which only runs in the CMat kernel path. When lowering a regular non-kernel function through `code_to_c.lua`, all pointers are plain `T*` — no restrict, no const, no volatile, even when source-level `noalias` contracts exist.

**GAP: `const` is never set on read-only pointers in the baseline path.** `CBackendQualifiedDataPtr.const_pointee` is always `false` in practice. The CMat path sets `restrict_ptr` via `lower_c_with_param_qualifiers` but never sets `const_pointee`. The stencil artifacts path (`stencil_c.lua`) does use `const` for read-only inputs, but that's a separate handwritten compiler path.

**GAP: The `CodeMemoryAccess` in `code.lua:228` carries `volatile [bool]` but this is never lowered to a volatile-qualified pointer type.** The `c_access` function in `code_to_c.lua:105-107` constructs `CBackendMemoryAccess` with `volatile` but only helper calls use this; actual C pointer types (`CBackendDataPtr`) never get volatile qualification from this.

**GAP: `CBackendQualifiedDataPtr` has no `alignment` field.** As noted in (3), there's no way to express "this restrict pointer is known to be 16-byte aligned" as a single C type.

---

## Relationships — Data Flow Summary

```
Source .lln
  → tree_typecheck → Tree IR
  → tree_lower → CodeModule (CodeFunc, CodeBlock, CodeTerm)
  → code_to_c.lua → CBackendUnit (baseline, plain pointers)
  └──→ lower_to_c.lua → lower semantic funcs (CMat inline path)
         ├─ code_to_c.lua first (baseline CBackendUnit)
         ├─ emit_scalar_kernel_fragment: replaces baseline blocks with CMat-inline blocks
         ├─ emit_closed_form_fragment: replaces with closed-form expression
         └─ apply_lower_c_carriers: weaves carrier/address plans into terminators

Then:
  CBackendUnit → emit_c_lower.lua → emit_c.c source text
    ├─ copy_propagate_blocks
    ├─ remove_dead_copy_assigns
    ├─ compute_transfer_equivalence
    ├─ plan_field_hoists
    └─ c_emit_func → per-block c_emit_term

Separate path:
  StencilArtifact → stencil_c.lua → llbl.c → C source text
    (handwritten stencil with __builtin_assume_aligned, restrict)
```

The critical lossy boundary is between **kernel plan facts** (trip count, alignment, noalias, vector lane policy) and the **inline CMat emission** (`lower_to_c.lua`). The schema has all this data structured precisely, but the `emit_scalar_kernel_fragment` and `emit_c_lower.lua` paths consume only a subset: loop bounds (start/stop), restrict-eligibility through the CMat bindings, and nothing from `FlowTripCount`, `ValueRange`, `StencilTripCountFact`, or `CMatVectorPolicy`.

---

## Observations

1. **Two worlds, one schema**: The `stencil_c.lua` (handwritten residual artifact) path and the `lower_to_c.lua` (inline CMat) path share the same ASDL vocabulary but consume it very differently. The residual path emits `__builtin_assume_aligned` and `restrict`; the inline path emits neither (except restrict via `apply_c_param_qualifiers`).

2. **`CBackendSwitchGoto` is dead code in the CMat path**: It's perfectly lowered from `CodeTermSwitch` but no kernel or loop lowering ever produces one. It's only reachable if a user-written `.lln` source happens to contain a variant switch.

3. **Branch hints are completely absent** — no `__builtin_expect`, `likely`/`unlikely`, or cold attributes anywhere. The C backend trusts GCC/O3 entirely.

4. **Vectorization and trip-count facts are collected but discarded** in the inline C path. The `CMatVectorPolicy`, `CMatTailPolicy`, `CMatLoopNest`, `StencilTripCountFact`, and `StencilVectorizationFacts` are all computed upstream but `emit_scalar_kernel_fragment` ignores them except the loop bounds.

5. **The `ValueFactSet` containing `ValueRange` and `ClosedFormFact` is passed to `lower_to_c.lua:normalize_args` but never accessed** by any method in `lower_to_c.lua` after that point. The value facts flow into kernel/schedule planning but the C lowering never reads them back.

6. **The `mem` (MemSemanticFactSet) is used only for `CodeMemFacts.access_projection(mem)`** to query access backend info in the CMat path. The richer alignment and access pattern facts from `MemMemAccessFact` are consumed by kernel plan but not by C lowering.

7. **`compute_transfer_equivalence` is a genuine value-numbering optimization** but it only canonicalizes names — it doesn't merge identical blocks or share tail code. It's a local equivalence pass, not a global merge.

8. **Error handling is cold but not marked cold**: `CBackendTrap` → `abort()`, `IntrinsicAssume` → `if (!a1) abort()`. Neither has `__builtin_unreachable()` after the abort, nor `__attribute__((cold))` on the helper functions.

9. **The `restrict` on pointer params is the most sophisticated lowering that reaches C output** in the CMat inline path — it requires pairwise noalias proofs across all access pairs, and when successful, upgrades `CBackendDataPtr` to `CBackendQualifiedDataPtr` with `restrict_ptr=true`. This is a real optimization that GCC can exploit.

## Scout Output — 2026-07-06 20:12:40

The scout has performed a comprehensive survey of the Lalin C backend lowering pipeline. The findings confirm that while the ASDL schema is rich and captures a wide array of semantic facts (alignment, trip counts, value ranges, vectorization policies), the actual lowering to C text is largely "lossy." Most of these facts are either discarded or used only for structural control flow rather than being emitted as performance hints (pragmas, built-ins) for the C compiler.

## Files Retrieved
1. `lua/lalin/schema/c.lua` (lines 1-660) — Defines the C IR, including `CBackendSwitchGoto` and `CBackendQualifiedDataPtr`.
2. `lua/lalin/lower_to_c.lua` (lines 1-2199) — The main lowering pipeline. Confirms that kernel dispatch is lowered to `CBackendIfGoto` chains.
3. `lua/lalin/code_to_c.lua` (lines 1-1359) — Baseline C lowering. 1:1 translation of `CodeTermSwitch` to `CBackendSwitchGoto`.
4. `lua/lalin/emit_c_lower.lua` (lines 1-1284) — Final C emission. Confirms the absence of branch hints and the use of plain `abort()` for traps.
5. `lua/lalin/stencil_c.lua` (lines 1-1555) — A separate, handwritten path that *does* emit `__builtin_assume_aligned` and `restrict`.
6. `lua/lalin/schema/code.lua`, `lower.lua`, `kernel.lua`, `flow.lua`, `value.lua`, `stencil.lua` — ASDL definitions confirming the existence of alignment, trip count, and range facts.

## Key Code & Gaps

### 1. Dispatch Strategy
- **Observation**: `CBackendSwitchGoto` exists in the schema and is produced by 1:1 translation of `CodeTermSwitch`.
- **Gap**: In the CMat kernel path (`emit_scalar_kernel_fragment` in `lower_to_c.lua`), loop header and region entry dispatch is always lowered to `CBackendIfGoto` chains. There is no logic to synthesize a `CBackendSwitchGoto` from these chains, even if they are simple integer tag checks.

### 2. Branch Hints / Profile
- **Observation**: Total absence of `__builtin_expect`, `likely`/`unlikely`, or `__attribute__((cold))`.
- **Gap**: `CBackendTrap` emits `abort()`, but does not mark the path as cold or unreachable, missing an opportunity to optimize the hot path.

### 3. Alignment Facts
- **Observation**: `CBackendPlaceDeref` stores `align`, and `stencil_c.lua` emits `__builtin_assume_aligned`.
- **Gap**: The main `emit_c_lower.lua` path ignores `PlaceDeref.align`. Alignment facts from `CodeMemoryAccess` are stored but never emitted as C hints.

### 4. Trip Count / Range Facts
- **Observation**: `FlowTripCount` and `ValueRangeInt` are available in the ASDL.
- **Gap**: These are used to structure the loop (start/stop), but aren't emitted as `__builtin_assume` hints. The C compiler doesn't know the exact trip count or value ranges of induction variables.

### 5. Vectorization Hints
- **Observation**: `CMatVectorPolicy` and `CMatLoopNest` (with `unroll`, `interleave`) exist in the schema.
- **Gap**: The inline CMat emission path expressly discards these policies, relying on the C compiler's autovectorizer. No `#pragma` or `ivdep` hints are emitted.

### 6. Redundant Code / Tail Merging
- **Observation**: `emit_c_lower.lua` implements local value numbering and copy propagation.
- **Gap**: No global tail merging. Identical blocks (e.g., multiple blocks ending in `abort()`) are emitted as separate labels.

### 7. Carrier/Address Plans
- **Observation**: `LowerCarrierPlan` variants (`CarryConst`, `CarryDynamic`) are fully consumed.
- **Gap**: They are lowered to eager recomputations (`i_next = i + 1`) rather than idiomatic C loop increments, which may hinder certain GCC optimizations or debuggability.

### 8. Aliasing Facts
- **Observation**: `CBackendQualifiedDataPtr` supports `restrict_ptr`. This is utilized in the CMat path via `lower_c_with_param_qualifiers`.
- **Gap**: The baseline `code_to_c.lua` path never produces qualified pointers, meaning `noalias` contracts for non-kernel functions are lost.

## Relationships
The primary tension is between the **High-Fidelity ASDL** (which knows exactly how many times a loop runs and how pointers are aligned) and the **Low-Fidelity C Emission** (which emits plain C and trusts the compiler). The `stencil_c.lua` path proves that emitting these hints is possible, but that logic is not integrated into the general `lower_to_c` $\to$ `emit_c_lower` pipeline.

## Observations
- **The "Two Worlds" Problem**: There is a stark difference between the "Residual Artifact" path (`stencil_c.lua`) and the "Inline CMat" path (`lower_to_c.lua`). The former is highly optimized; the latter is structural.
- **Schema Underutilization**: The ASDL is "over-engineered" relative to the current C backend; it collects a wealth of data that is simply dropped during the final translation to C text.

## Scout Output — 2026-07-06 20:17:16

The Lalin C backend lowering pipeline is not a simple linear translation, but a **multi-stage evidence-gathering engine**. It transforms a high-level region declaration into C code by first structuralizing the program, then performing a series of "projections" to discover semantic facts, and finally attempting to "lift" these facts into a high-level execution plan.

## The End-to-End Pipeline

### 1. Structural Lowering: `LalinTree` $\to$ `Code IR`
**Primary File**: `lua/lalin/tree_lower.lua`
The pipeline begins by lowering the `LalinTree` (the result of typechecking) into **Code IR**. 
- **What happens**: High-level constructs (like `ExprControl`, `View`, and `Slices`) are shattered into a basic-block representation (`CodeFunc`, `CodeBlock`, `CodeInst`, `CodeTerm`).
- **Key Decision**: This layer handles the transition from "names" to "value IDs" and establishes the initial memory residence (whether a variable is a value or must be addressed in memory).
- **Tradeoff**: It is a lossy structural transformation. The high-level "intent" of a loop or a view is replaced by explicit pointer arithmetic and branch instructions.

### 2. Graph Construction: `Code IR` $\to$ `CodeGraph`
**Primary File**: `lua/lalin/code_graph.lua`
Before any analysis, the Code IR is converted into a formal graph.
- **What happens**: It builds Use-Def chains and a Control Flow Graph (CFG). Crucially, it implements a **natural loop detector** to find loop headers and latches.
- **Role**: This graph is the substrate for all subsequent "fact builders."

### 3. Semantic Projection: The "Fact" Layers
Instead of mutating the IR, Lalin uses a **Projection System**. It runs a series of passes that generate side-tables of facts about the Code IR.
- **Flow Facts (`code_flow_facts.lua`)**: Analyzes the graph to find **Counted Loops**. It identifies the induction variable, the step magnitude, and the loop range (start/stop).
- **Value/Mem/Effect Facts**: (Implied via `frontend_pipeline.lua`) These layers analyze value ranges, memory access patterns (e.g., identifying a "strided" access), and side-effect properties.
- **The Elegance**: This is the most sophisticated part of the architecture. By treating analysis as a "projection" (mapping IR $\to$ Facts), Lalin avoids the "phase ordering" problem where one optimization destroys the information needed for another.

### 4. Intent Recovery: `Kernel Plan`
**Primary File**: `lua/lalin/code_kernel_plan.lua`
This layer attempts to "reverse" the structural lowering. It looks at the gathered facts to see if a low-level loop matches a known **Kernel Skeleton**.
- **Skeleton Matching**: It searches for patterns like `Array Copy`, `Prefix Scan`, `Find`, or `Scatter-Reduce`.
- **Proof System**: If a loop is identified as a "Copy," the plan includes a `KernelProof` (e.g., `KernelProofFunctionEquivalence`), documenting *why* the compiler believes this loop is actually a copy.
- **Result**: The output is a `KernelPlan`, which marks which parts of the function are "special" kernels and which are just "scalar blocks."

### 5. Final Dispatch: `Exec Plan` $\to$ `C Backend`
**Primary Files**: `lua/lalin/exec_plan.lua`, `lua/lalin/lower_to_c.lua`
The `ExecPlan` decides the final realization of the kernels.
- **Stencil Path**: If a kernel is a stencil and a corresponding "native artifact" exists, it is routed to the highly optimized `stencil_c.lua` path (which emits `restrict` and `__builtin_assume_aligned`).
- **Scalar Path**: If no special artifact exists, the `ExecPlan` falls back to `ExecFragmentScalarBlocks`, which simply emits the original Code IR blocks via `lower_to_c.lua`.

## Architectural Summary

| Stage | Input | Output | Nature |
| :--- | :--- | :--- | :--- |
| **Tree Lower** | `LalinTree` | `Code IR` | Structural Shattering |
| **Graph** | `Code IR` | `CodeGraph` | Topological Analysis |
| **Projections** | `CodeGraph` | `FactSets` | Semantic Discovery |
| **Kernel Plan** | `FactSets` | `KernelPlan` | Intent Recovery |
| **Exec Plan** | `KernelPlan` | `ExecPlan` | Dispatch/Realization |

### The "Real Story" (Observations)
- **The Elegant**: The **Projection System** is a masterclass in compiler design. By separating "what the code does" (Facts) from "how it's written" (IR), Lalin can perform complex kernel recovery without breaking the underlying code.
- **The Gap**: There is a stark "fidelity cliff" at the end of the pipeline. The `KernelPlan` does the hard work of proving a loop is a `Prefix Scan`, but the `C Backend` often ignores this, emitting the raw scalar blocks and relying on GCC to "re-discover" the same facts the Lalin compiler already proved.
- **The Tension**: The system is built for "native stencil" excellence (where the facts are fully exploited), but the general-purpose C lowering remains basic. The pipeline is an "over-engineered" engine currently driving a "basic" C-emission car.

## Knowledge-builder Output — 2026-07-06 20:19:30

### What Matters Most for This Problem

The core tension in this problem is not a "lack of features" (the facts are already in the ASDL), but a **representation mismatch** between the **Analysis Phase** (which operates on a high-level semantic Graph) and the **Emission Phase** (which operates on a low-level basic-block Graph).

To fix the gaps, one must bridge the gap between *semantic intent* (e.g., "this is a counted loop") and *structural output* (e.g., "this is a sequence of `if/goto` blocks"). The risk is that attempting to "pass facts" into the emitter might destroy the very "decoupling" that the Projection System was designed to achieve.

---

### Non-Obvious Observations

#### 1. The "Representation Mismatch" as the Root Cause of the Cliff
The fidelity cliff exists because the C backend is a **Graph-to-C translator**, not a **Loop-to-C translator**. 
- `CBackendBlock` is a basic block. It has no concept of a "loop," "induction variable," or "trip count." It only knows about instructions and a terminator.
- To emit a `#pragma omp simd` or a `__builtin_assume`, the emitter needs to know it is inside a loop. But the emitter is processing a flat list of blocks.
- **The Insight**: The "fidelity cliff" is a structural requirement of the current `CBackendUnit` design. To fix the gaps, the backend would either need to move from a "Block-based" emission to a "Structured-Control-Flow" emission, or the `CBackendBlock` ASDL would need to be bloated with "facet" data from the projections.

#### 2. The "Replacement" Opportunity vs. "Hinting"
The scout noted that `code_kernel_plan.lua` produces `KernelProofFunctionEquivalence`. This is a massive over-investment if the goal is merely to provide "hints" to GCC.
- **The Insight**: The proof system wasn't built to "hint" the C compiler; it was built to **replace** the code. If the compiler proves a loop is equivalent to a `Prefix Scan`, it doesn't need to emit a `goto` graph and hope GCC sees it—it can emit a call to a highly optimized `lalin_prefix_scan()` primitive.
- **The Tension**: The current "Symmetry of the Two Worlds" (Stencil path vs. Scalar path) shows that the system is currently used for *replacement* (Stencil) but the *fallback* (Scalar) is just a raw dump. The "gap" is that there is no "Middle Ground" where a proven kernel is emitted as a specialized C-template without being a full "native artifact."

#### 3. The Projection System's "Anti-Phase" Constraint
The Projection System (IR $\to$ Graph $\to$ Facts) is designed to avoid phase-ordering problems. If the `emit_c_lower.lua` path starts consuming `FlowTripCount` facts, it creates a **back-dependency** on the `CodeGraph` and the `FactSet`.
- **The Insight**: If you fix the gaps by passing the `FactSet` into the emitter, you effectively turn the emitter into another "projection" phase. This means any change to how loops are analyzed would require a corresponding change to how basic blocks are emitted, potentially re-introducing the coupling the architecture sought to avoid.

#### 4. The "Accidental Kernel" Edge Case
The current architecture handles "accidental kernels" exceptionally well. 
- Because it shatters everything into blocks and then *rediscovers* intent, a user could write a bizarre, non-standard loop structure that doesn't look like a "loop" at the source level, but the `CodeGraph` natural loop detector and `FlowFacts` will still find the induction variable and trip count.
- **The Insight**: A simpler design (e.g., lowering `LalinTree` $\to$ `C-Loop`) would lose this. The "Shatter $\to$ Rediscover" pipeline allows the compiler to optimize code that the programmer didn't even know was a kernel.

#### 5. The "Symmetry" of the Two Worlds is a Lie
The `stencil_c.lua` path is a **Template Compiler** (Intent $\to$ C), while `lower_to_c.lua` is a **Graph Lowerer** (CFG $\to$ C).
- **The Insight**: They are not two paths of the same pipeline; they are two entirely different compiler philosophies. The "fidelity cliff" is the boundary where the system stops being a "Template Compiler" and starts being a "Graph Lowerer." Attempting to "merge" them by adding hints to the Graph Lowerer is a category error—you cannot "hint" a graph into a loop without performing a full structural recovery (which is exactly what `code_kernel_plan.lua` does, but the output of which is discarded).

---

### Knowledge Gaps

1. **Structural Recovery**: Does `CBackendUnit` have any mechanism to reconstruct high-level loop structures from the `CBackendBlock` graph, or is it strictly a forward-only emission?
2. **Primitive Library**: Is there a set of C-primitives (like `lalin_prefix_scan`) that the `KernelProof` system is intended to target, or is "replacement" currently only envisioned for the Stencil native path?
3. **CMat Policy Consumption**: Why exactly does `lower_to_c.lua:1754` claim that "CMat vector bodies are not yet richer"? Does this imply there is a planned `CMat` ASDL evolution that would bridge the fidelity cliff?

## Knowledge-builder Output — 2026-07-06 20:20:31

### What Matters Most for This Problem

The "fidelity cliff" is not a failure of analysis, but a **structural mismatch** between the **Recovery Engine** and the **Emission Engine**.

1.  **Structural Loss**: The pipeline is designed as: `LalinTree` (Structured) $\to$ `Code IR` (Flat Blocks) $\to$ `CBackendUnit` (Flat Blocks) $\to$ `C Source`.
2.  **The Recovery Paradox**: `CodeGraph`, `FlowFacts`, and `KernelPlan` are "Recovery" layers. They spend immense effort reconstructing the lost structure (loops, induction variables, trip counts) from the flat `Code IR`.
3.  **The Cliff**: Once the structure is recovered, it is used *only* to decide if a loop can be **replaced** by a specialized kernel. If it cannot be replaced, the recoverable facts (trip counts, align, etc.) are simply discarded, and the emitter falls back to the original flat `Code IR` blocks.

The core constraint is that **`CBackendUnit` is a flat-block IR**. It has no vocabulary to carry structural "facets" (like "this block is the header of a loop with trip count X") into the final emitter.

---

### Non-Obvious Observations

#### 1. Recovery for Replacement, not Augmentation
The most critical insight is that the current architecture uses the Projection System for **Replacement** (e.g., replacing a loop with `lalin_prefix_scan`) but not for **Augmentation** (e.g., adding `#pragma omp simd` to a loop). 
- If a `KernelProof` is found, the loop is replaced.
- If no proof is found, the system reverts to the "Shattered" blocks.
- There is no "Middle Ground" where the recovered facts are used to decorate the blocks.

#### 2. The "Shatter $\to$ Rediscover" Resilience
The decision to shatter the `LalinTree` into blocks immediately (`tree_lower.lua`) is a deliberate design for **extreme resilience**. 
- Because the system rediscovers loops via `code_graph.lua`'s natural loop detector, it can optimize loops that are structurally "ugly" or non-standard in the source but semantically simple in the CFG.
- This makes the "cliff" a necessary tradeoff: by destroying the structure to gain resilience, the system must explicitly "carry" recovered facts if it wants to use them in the backend.

#### 3. Type-Based vs. Structural Hints
The `restrict` qualifier (via `CBackendQualifiedDataPtr`) is the only semantic fact that successfully survives the cliff. 
- **Why?** Because `restrict` is a **Type Qualifier**. It can be attached to a pointer variable in the `CBackendUnit`'s local list.
- **Constraint**: Alignment and trip counts are **Structural/Contextual**. They aren't properties of a variable, but properties of a *location* in the code (a loop header or a memory access).
- Since `emit_c_lower.lua` processes blocks linearly, it has no "Structural Context" to know which loop it's currently inside.

#### 4. The "Trivial" Alignment Gap
The code reveals that alignment facts are actually *already* in the `CBackendUnit`, but are ignored.
- `lower_to_c.lua` creates `CBackendPlaceDeref` with an `align` field.
- `emit_c_lower.lua`'s `c_emit_place()` simply ignores this field.
- **Observation**: Adding `__builtin_assume_aligned` is a trivial local change. However, adding loop-level hints (like trip counts) would require a **global change** to how the emitter tracks a "Loop Stack" or "Context Frame."

#### 5. Dead Logic in Dispatch
The `CBackendSwitchGoto` is a "ghost" in the machine.
- It is faithfully lowered from `CodeTermSwitch`.
- However, the `emit_scalar_kernel_fragment` in `lower_to_c.lua` deliberately generates `CBackendIfGoto` chains for kernel dispatch.
- This means the backend is capable of emitting high-efficiency C switches, but the kernel recovery path refuses to use them, opting for a chain of binary branches instead.

---

### Knowledge Gaps

1.  **Symmetry of the Two Worlds**: I see `stencil_c.lua` (the "Template" path) and `lower_to_c.lua` (the "Graph" path). Is there any intention to unify these, or is the "Graph" path intended to be a permanent, low-fidelity fallback?
2.  **CMat Policy Implementation**: `CMatVectorPolicy` and `CMatLoopNest` exist in the ASDL. Is there any code (perhaps in a different module) that actually consumes these for the inline C path, or are they truly dead storage?
3.  **Generic C-Primitives**: Does the project have a intended library of `lalin_...` C primitives that the `KernelProof` system should target if a full "Native Artifact" is unavailable?

## Knowledge-builder Output — 2026-07-06 20:25:43



Here is the granular, code-level analysis of all six files:

---

## 1. `code_kernel_plan.lua` — Skeleton Matching & `KernelProof`

### Skeleton Matching Functions (local functions)

| Function | Line | What it does |
|----------|------|--------------|
| `infer_scan_skeleton` | ~920 | Matches `KernelEffectScan`: looks for `KernelEffectStore` + `KernelEffectFold` where store updates match the reduction. Emits `Kernel.KernelSkeletonScan`. |
| `infer_copy_skeleton` | ~943 | Matches `KernelSkeletonCopy`: looks for store-to-primary-index where value is a `KernelExprLaneLoad` from primary-index. Checks type and dependence. Emits `Kernel.KernelSkeletonCopy`. |
| `infer_scatter_reduce_skeleton` | ~1050 | Matches `KernelSkeletonScatterReduce`: looks for store to non-primary index where value is a `ValueExprAdd`/`ValueExprMul`/select op, with one operand reading back the same destination at the same index. Emits `Kernel.KernelSkeletonScatterReduce`. |
| `infer_find_skeleton` | ~1090 | Matches `KernelSkeletonFind`: requires exactly 2 graph loop exits, where one returns the primary induction (hit) and the other returns `-1` (not-found). The hit edge must have a predicate from a branch comparing a lane-load against a const. |
| `infer_all_skeleton` | ~1131 | Matches `KernelSkeletonAll`: requires exactly 2 graph loop exits. Checks branch polarity from header → success vs body → failure. Identifies compare-based predicate. |

### Skeleton Result constructors

| ASDL Constructor | Line (approx) |
|-----------------|---------------|
| `Kernel.KernelSkeletonScan` | ~936 |
| `Kernel.KernelSkeletonCopy` | ~960 |
| `Kernel.KernelSkeletonScatterReduce` | ~1073 |
| `Kernel.KernelSkeletonFind` | ~1118 |
| `Kernel.KernelSkeletonAll` | (constructed implicitly via branch-polarity pattern, exact line ~1170) |

### `KernelProof` constructors used

| Proof | Line (approx) | Context |
|-------|---------------|---------|
| `Kernel.KernelProofFunctionEquivalence` | ~936, ~960, ~1073, ~1118 | Every skeleton inference creates one with a string explanation. |
| `Kernel.KernelProofValue` | ~106 | `KernelLoopPlanClosedForm:add_selected_loop_plan` adds proof for closed-form justification. |
| `Kernel.KernelProofFlow` | ~110 | `KernelLoopPlanClosedForm` adds proof when trip-count is unknown (uses start/stop/step directly). |
| `Kernel.KernelProofMemory` | ~730 | `lanes_for_accesses` iterates `backend.proofs` and wraps each in `KernelProofMemory`. |
| `Kernel.KernelProofEffect` | ~741 | `loop_effects` wraps proven effects as `KernelProofEffect`. |

### Key supporting functions

| Function | Line | Purpose |
|----------|------|---------|
| `first_effect` | ~866 | Finds first `KernelEffect` of a given class; rejects if multiple. |
| `reduction_update_matches` | ~890 | Dispatches to `reduction.op:kernel_plan_update_matches_expr()` to check if a ValueExpr is the reduction update pattern (accumulator ⊕ contribution). |
| `same_load_expr` | ~903 | Checks two `KernelExprLaneLoad` for same lane + same index. |
| `copy_dependence_semantics` | ~908 | Determines `Stencil.StencilCopyMemMove` vs `Stencil.StencilCopyNoOverlap` from dependence rejects. |
| `scatter_reduce_op` | ~1044 | Dispatches `expr:kernel_plan_scatter_reduce_op()` to find reduction operator from ValueExpr. |
| `scatter_reduce_contribution` | ~1048 | Identifies which operand of a binary is a lane-load from the same lane at the same index (the "read-back"), and returns the other operand as the contribution. |
| `scatter_reduce_select_op` | ~1062 | Recognizes `select(cmp, t, f)` as min/max when `t` or `f` matches one of the compare operands. |

---

## 2. `code_flow_facts.lua` — Loop Induction Variable Detection & Trip Count

### Induction Variable Detection

| Function | Line | Details |
|----------|------|---------|
| `analyze_loop` | ~242 | Main loop analysis. Iterates `header_block.params`, finds each parameter that has both an `init` (non-latch incoming arg) and a `back` (latch backedge arg). Calls `induction_step()` to check if the backedge value is `param + step` or `param - step`. |
| `induction_step` | ~193 | Checks if `back_value`'s definition is `CodeInstBinary` with `Core.BinAdd` or `Core.BinSub`. Verifies one operand is canonically the header param, returns the other operand as the step constant. |
| `compare_stop` | ~204 | Checks if the latch condition is a `CodeInstCompare` involving the induction variable. Returns the stop value and whether the comparison is exclusive (`<` / `>=`). |
| `range_for_induction` | ~213 | Constructs `Flow.FlowRangeDerived` from init (min) and stop (max). |

### Trip Count Extraction

| Function | Line | Details |
|----------|------|---------|
| `semantic_facts` | ~305 | **Public API**. Iterates `FlowFactSet.loops`, filters for `loop.counted ~= nil`. For each counted loop, calls `primary_induction()` to find the `FlowPrimaryInduction`. Iterates and produces `Flow.FlowLoopNormalizedCounted(loop.loop, loop.counted, direction, Flow.FlowTripCountUnknown("no explicit trip-count CodeValueId is available"))`. **Key observation: the trip count is always `FlowTripCountUnknown` currently.** |

### Edge Cases

- `canonical_value` (~183): Resolves transitive alias chains for values — used to handle loop-carried renames.
- `same_canonical_value` (~190): Compares two values after canonicalization. Used in `induction_step` to verify the recurrence is `param + step`.
- `incoming_arg_for` (~170): Finds the value passed to a header param from non-latch edges (the initial value).
- `backedge_arg_for` (~178): Finds the value passed to a header param from the latch backedge.

---

## 3. `tree_lower.lua` — Region Lowering & Specific Method Names

### Region Lowering

The region lowering is in `tree_lower.lua` starting from line ~963. The key methods are:

| Method | Line | Purpose |
|--------|------|---------|
| `Tr.ExprControl:lower_tree_expr_to_code` | ~1540 | Top-level entry for `region.` expressions. Creates blocks for entry + each region block. |
| `Tr.StmtControl:lower_tree_stmt_to_code` | ~2620 | Statement-level region lowering. |
| `tree_code_lower_region_blocks` | ~1700 | (local) Iterates `self.region.blocks`, calls `tree_code_lower_region_block_entry` for each. |
| `tree_code_lower_region_block_entry` | ~1740 | (local) Lowers a single region `.entry` or `.block` to Code IR — handles yield → block exit, branch → terminator, etc. |
| `Tr.StmtRegionEmit:lower_tree_stmt_to_code` | ~2100 | Emits args to the region entry block. |
| `Tr.StmtRegionCall:lower_tree_stmt_to_code` | ~2120 | Calls a region. |
| `Tr.StmtJump:lower_tree_stmt_to_code` | ~2160 | Lowers `goto label` — looks up label via `tree_code_control_target`, emits `CodeTermJump`. |
| `Tr.StmtJumpCont:lower_tree_stmt_to_code` | ~2175 | Similar to jump but for continue-style labels. |

### Control Region Tracking

| Method | Line | Purpose |
|--------|------|---------|
| `TL.TreeLowerFunctionState:tree_code_enter_control_region` | ~772 | Pushes a control region onto the stack. Creates a `TreeLowerControlRegionSlot` and `TreeLowerControlFlag`. |
| `TL.TreeLowerFunctionState:tree_code_leave_control_region` | ~780 | Pops a control region. Returns whether an exit was seen (`saw_exit`). |
| `TL.TreeLowerFunctionState:tree_code_current_control_region` | ~789 | Returns the current top-of-stack control region, for label resolution. |
| `TL.TreeLowerFunctionState:tree_code_note_control_exit` | ~796 | Marks the "exit seen" flag on the current region. |
| `TL.TreeLowerFunctionState:tree_code_control_target` | ~802 | Looks up a label within the current control region via `label_key(label)`. |

### Address-Taken Collection

| Method | Line | Purpose |
|--------|------|---------|
| `collect_address_taken_stmts` | ~702 | Walks a statement list, calling `tree_code_collect_address_taken_stmt` on each. |
| `Tr.ExprAddrOf:tree_code_collect_address_taken_expr` | ~743 | Calls `place:tree_code_mark_addressed_place` — marks the binding as address-taken. |
| `Tr.ExprControl:tree_code_collect_address_taken_expr` | ~799 | Recursively collects address-taken info from region entry + all region blocks. |
| `Tr.StmtControl:tree_code_collect_address_taken_stmt` | ~869 | Same for statement-level control. |

---

## 4. `lower_to_c.lua` (lines 1200-1600) — `emit_scalar_kernel_fragment` Lowering

### `emit_scalar_kernel_fragment` (line ~1373)

**Signature**: `emit_scalar_kernel_fragment(c_emission, graph, flow, kernels, fragment)`

**Step-by-step lowering:**

1. **Line ~1374**: Resolves `kplan` from `fragment.strategy.kernel`.
2. **Line ~1375**: Calls `loop_partition(c_emission, graph, flow, kplan)` → returns `loop, body_set, edge_facts, exit_edge, latch_edge, body_successor, cond, loop_fact`.
3. **Line ~1377-1378**: Swaps `c_emission.active_address_plans` for kernel-specific addresses.
4. **Line ~1379**: Calls `place_bindings_effects(c_emission, kplan)` → `bindings_by_block, effects_by_block`.
5. **Line ~1381**: Calls `reduction_state_for_kernel(c_emission, kplan, loop_fact)` — builds reduction CMat state.
6. **Line ~1382**: Calls `kplan.body.result:lower_c_control_state(...)` — builds control CMat state (all/find/any).
7. **Line ~1385**: Starts emitting header block. Sets `c_emission.stmts = { C.CBackendComment(...) }`.
8. **Line ~1386**: If `semantic_fragment_prelude`, calls it.
9. **Line ~1387**: Calls `bind_control_values(c_emission, data_bindings, bindings_by_block, loop.header.block)` — emits non-data-body bindings as locals.

### Header block dispatch (lines ~1394-1419)

10. **Line ~1398-1405** (control kernel path): Creates `C.CBackendIfGoto` comparing `counter == stop` to decide between `result.success` and `body_successor`.
11. **Line ~1410-1415** (non-control path): Creates `C.CBackendIfGoto` using `atom(cond)` to decide between `body_successor` and `exit_edge.to.block`.
12. **Edge args**: Uses `edge_args_with_reduction(reduction_state, edge_facts[key])` to resolve reduction accumulator across edges.

### Body block iteration (lines ~1422-1469)

13. **Line ~1423**: Iterates all code blocks where `body_set[block.id.text]` and `block.id ~= loop.header.block`.
14. **Line ~1426-1427**: Emits `C.CBackendComment("semantic scalar CMat kernel body ...")` and calls prelude.
15. **Line ~1428**: Calls `bind_control_values` for this block.
16. **Line ~1429**: Iterates `effects_by_block[block.id.text]` — calls `emit_inline_cmat_effect(...)` for each.
17. **Line ~1430**: If this is the latch block, calls `emit_reduction_update` to emit the reduction fold.

18. **Line ~1432** — Terminator selection logic:
   - **Line ~1433**: If control kernel and `CodeTermBranch` → emits sink CMat, creates `C.CBackendIfGoto` with `cmat.control_pred`.
   - **Line ~1442**: If latch block → `C.CBackendGoto` back to header.
   - **Line ~1444**: Otherwise → finds next in-loop edge, emits `C.CBackendGoto` (or conditional `C.CBackendIfGoto` if still awaiting control sink).

**Key observation**: ALL terminators are `C.CBackendIfGoto` or `C.CBackendGoto` — never `C.CBackendSwitchGoto`, even for multi-way dispatch patterns.

### Supporting CMat builders (lines 1200-1370)

| Function | Line | What CMat sink it creates |
|----------|------|---------------------------|
| `cmat_store_kernel` | ~1202 | `Stencil.StencilSinkOpStore` |
| `cmat_copy_kernel` | ~1212 | `Stencil.StencilSinkOpStore(store_mode: Stencil.StencilStoreCopy)` |
| `cmat_reduce_kernel` | ~1222 | `Stencil.StencilSinkOpFold` |
| `cmat_scan_kernel` | ~1234 | `Stencil.StencilSinkOpScan` |
| `cmat_scatter_reduce_kernel` | ~1252 | `Stencil.StencilSinkOpScatterFold` |
| `cmat_control_kernel` | ~1284 | `Stencil.StencilSinkOpAny` / `Stencil.StencilSinkOpFind` / `Stencil.StencilSinkOpAll` |
| `cmat_control_compare_kernel` | ~1301 | `Stencil.StencilSinkOpAll` with `StencilPointCompare` stream |

---

## 5. `code_graph.lua` — Natural Loop Detector

### Function Names & Lines

| Function | Line | Purpose |
|----------|------|---------|
| `natural_loop(header_key, latch_key, preds)` | ~312 | Post-order walk from latch, collecting all blocks that reach the latch without passing through the header. Returns a `set` of block keys. |
| `detect_natural_loops(func, blocks, order, edges)` | ~326 | Iterates all back-edges (where `order[to] <= order[from]`), calls `natural_loop()` to compute body set, extracts exits (from body to outside), constructs `Graph.GraphLoop`. |
| `Code.CodeFunc:code_graph_func()` | ~345 | Public entry. Builds `block_by_id`, `edges`, `defs`, `uses`, and calls `detect_natural_loops()`. Returns `Graph.CodeFuncGraph`. |
| `Code.CodeModule:code_graph_module()` | ~364 | Public module-level entry. Returns `Graph.CodeGraph`. |

### The `natural_loop` algorithm (line ~312)
1. Initialize `set = { header, latch }`.
2. Push `latch` onto stack.
3. While stack non-empty: pop, iterate `preds[node]`, if pred not in set, add to set and push (unless pred is the header, to stop propagation).
4. Result is the set of blocks in the natural loop.

### Key `code_graph_append_*` methods

| Leaf method | Line | Adds edges/uses for |
|-------------|------|-------------------|
| `Code.CodeTermJump:code_graph_append_edges` | ~271 | Single outgoing edge |
| `Code.CodeTermBranch:code_graph_append_edges` | ~275 | Two outgoing edges (then/else) |
| `Code.CodeTermSwitch:code_graph_append_edges` | ~280 | N-case + default edges |
| `Code.CodeTermVariantSwitch:code_graph_append_edges` | ~288 | N-variant + default edges |

---

## 6. `emit_c_lower.lua` (lines 750-870) — Optimizer Passes

### Pass 1: `compute_transfer_equivalence` (line ~773)

**What it does**: Value-numbering across transfer edges. If all predecessors of a block pass the same underlying value to a parameter, it aliases the parameter to that canonical name.

| Line | Detail |
|------|--------|
| 777-780 | Initialize `alias` map: func params and locals are self-aliasing. |
| 781-784 | Block params are self-aliasing. |
| 785-788 | `root()` with path compression. |
| 789 | Build `by_dest` index of transfer edges. |
| 791-808 | Iterative unification: for each block param, check if all predecessor edges pass the same canonical source. If so, alias → merge names. |
| 809 | Returns `root` function. |

### Pass 2: `plan_field_hoists` (line ~814)

**What it does**: Hoists repeated `ptr->field` loads to a local when used ≥3 times from a parameter base.

| Line | Detail |
|------|--------|
| 815 | Calls `compute_transfer_equivalence` to resolve canonical names first. |
| 816-819 | Setup `state` table with helper methods. |
| 820-823 | Initialize `param_locals` and `existing` name sets. |
| 824-827 | Walk all block stmts, collecting field-hoist candidates via `stmt:c_emit_collect_field_hoist_state(state)`. |
| 828 | Collect call-arg root locals (can't hoist if base is a call arg). |
| 829-838 | For each candidate with `count >= 3`, if param-local base and not blocked, create a fresh local + `CBackendPlaceLoad` init. |
| 839-848 | Rewrite blocks: insert hoist inits at block 0, replace field loads with hoist local via `stmt:c_emit_apply_field_hoists(by_key, canonical)`. |

### The pass stack in `c_emit_func` (line ~855)

| Line | Pass |
|------|------|
| 864 | `f_blocks, hoist_locals = plan_field_hoists(self, f_blocks)` — field hoisting |
| 869 | `f_blocks = remove_dead_copy_assigns(copy_propagate_blocks(f_blocks, local_types))` — copy propagation + dead copy elimination (only after hoisting) |

**Note**: `copy_propagate_blocks` and `remove_dead_copy_assigns` are defined at lines 663-750 (earlier in the file, outside the requested range).
