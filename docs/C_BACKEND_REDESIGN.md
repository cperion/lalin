# C Backend Lowering — Target Architecture

This document specifies the target architecture for the Lalin C backend lowering
pipeline. It replaces the current design where semantic facts proven by analysis
are discarded at the C emission boundary — the "fidelity cliff" — with a
coherent, ASDL-first design where every fact flows through typed ASDL
products/sums from analysis to C output.

## Diagnosis

The fidelity cliff is a systematic architecture gap at the boundary between
proven semantic facts and C emission decisions. It manifests at multiple discard
points:

| Discard Point | What's Proven | What's Lost | Source |
|---|---|---|---|
| Flow analysis | `CountedDomain(start, stop, step)` — trip count computable | `FlowTripCountUnknown` always emitted | `code_flow_facts.lua` |
| Mem analysis → Kernel plan | `MemAlignmentKnown(N)`, bounds, non-trapping | Hardcoded `StencilAlignmentUnknown` | `cmat_access_binding_for_lane()` |
| Schedule plan → CMat | `ScheduleVector(lanes, unroll, interleave, tail)` | `default_stencil_schedule()` always scalar | `computation_for_body()` |
| CMat → CBackend | `CMatLoopNest` with vector policy | Inline emitter never reads it | `lower_c_inline_computation()` |
| CBackend → emission | `CBackendBlock` flat goto chains | No loop structure, no alignment, no branch hints | `emit_c_lower.lua` |

Each discard point is a **missing ASDL wire**, not a wrong boundary. The right
boxes exist; the connections between them are incomplete.

## Design Principles

1. **ASDL owns the vocabulary** — every semantic fact proven by analysis must be
   representable as a typed ASDL product or sum. If the Lua code can't wire a
   fact, the schema is incomplete.

2. **Projection, not mutation** — lower layers consume higher-layer ASDL and
   produce their own projections. No layer mutates another layer's ASDL nodes.
   Kernel rewrites produce `LowerRewriteApplication` projections; they do not
   mutate `CodeModule` in place.

3. **Leaf methods own dispatch** — `LowerEmitSelection` sum leaves route to
   implementation. No Lua handler maps, `kind` strings, or selector tables.

4. **Crisp layer boundaries**:
   - **Flow / Value / Mem** — *what facts are proven?* (analysis)
   - **Kernel** — *what equivalences are proven?* (proofs)
   - **Schedule** — *what execution policy?* (decisions)
   - **Lower** — *how will Code IR transform?* (rewrite + fragment selection)
   - **CBackend** — *what structural C shape?* (language-agnostic annotations)
   - **Emission** — *what compiler-specific output?* (GCC/Clang pragmas, builtins)

5. **No side tables or context bags** — all decision state flows through explicit
   ASDL fields or sibling facet products.

6. **Backward-compatible CBackend IR** — `CBackendBlock`, `CBackendTerminator`,
   and `CBackendFunc` stay unchanged. Structural annotations are a sibling facet
   (`CBackendUnitAnnotations`), not embedded in the block IR.

---

## Layer 1: Flow Facts — Trip Count Root Cause

### Problem

`FlowTripCountExact { count [CodeValueId] }` exists in the schema but is never
produced because `semantic_facts()` can't materialize a `CodeValueId` for the
trip count expression. The phase ordering puts Value registration after Flow
analysis, so the trip count value doesn't exist yet.

### Design

The trip count expression `(stop - start + adjustment) / step` is a **Flow
fact**, not a Value fact. The schema carries the expression itself as a
`ValueExpr` so downstream consumers can evaluate it without waiting for Value
registration.

### Schema changes — `schema/flow.lua`

```lua
-- Trip count carries both a CodeValueId (if materialized) and a ValueExpr (synthetic)
sum FlowTripCount {
  FlowTripCountExact {
    count [CodeValueId],
    trip_expr [ValueExpr],    -- NEW: the synthetic expression
    proof [optional [MemProof]],
  },
  FlowTripCountNonNegative {
    count [CodeValueId],
    trip_expr [ValueExpr],    -- NEW
    proof [optional [MemProof]],
  },
  FlowTripCountUnknown {
    reason [str],
    trip_expr [optional [ValueExpr]],  -- NEW: expression may be available even when unresolved
  },
}
```

### Implementation — `code_flow_facts.lua`

`semantic_facts()` computes the trip expression from `FlowCountedDomain`:

```
stop - start         (exclusive, step = 1)
(stop - start) / step   (non-unit step)
stop - start + step  (inclusive, step = 1)
```

The result is placed in `FlowTripCountExact.trip_expr`. If the expression can't
be resolved to a `CodeValueId`, it still goes into `FlowTripCountUnknown.trip_expr`
for downstream consumers.

### Impact

Every downstream consumer that has `CountedDomain` now has the actual trip count
expression. Kernel planning, scheduling, memcpy rewrites, and loop emission all
gain access to iteration bounds.

---

## Layer 2: Kernel Proof → Code IR Rewrite

### Problem

When `KernelPlan` proves a loop is equivalent to a closed-form expression, a
memcpy, a scan, or a find, the current `lower_to_c.lua` still emits the original
loop as flat gotos. Kernel proofs are used for stencil artifact selection (the
native loop as flat gotos. Kernel proofs drive CMat fragment eligibility and fusion in the emitted-C path: exact emitted C plus declared memory/noalias/bounds facts make fusion a typed decision, and contracts are recomputed after fusion.

### Design

Kernel equivalence proofs drive **Code IR projection** — not mutation. For each
proven kernel, the lower layer produces a `LowerRewriteApplication` that maps old
block IDs to replacement `CodeBlock` sets. The C backend then lowers the
rewritten blocks as if they were the original program.

### Schema changes — `schema/kernel.lua`

```lua
-- What rewrite the kernel proof justifies
sum KernelRewriteKind {
  KernelRewriteClosedForm {     -- Replace loop with expression + jump
    expression [ValueExpr],
    accumulator [optional [KernelExpr]],
  },
  KernelRewriteMemcpy {         -- Replace loop with memcpy/memmove call
    dst_base [CodeValueId],
    src_base [CodeValueId],
    elem_size [number],
    semantics [MemDependenceFact],  -- memcpy vs memmove
  },
  KernelRewriteScan {           -- Replace loop with scan helper call
    dst [KernelLane],
    src [KernelLane],
    reduction [ReductionFact],
    mode [KernelScanMode],
    trip_count [ValueExpr],
  },
  KernelRewriteFind {           -- Replace loop with find helper call
    src [KernelLane],
    predicate [KernelExpr],
    result_local [CodeValueId],
    trip_count [ValueExpr],
  },
  KernelRewriteReduce {         -- Replace loop with reduce helper
    reduction [ReductionFact],
    identity [ValueExpr],
    result_local [CodeValueId],
    trip_count [ValueExpr],
  },
  KernelRewriteNone,            -- No rewrite possible, emit original control
}

-- Rewrite plan attached to the kernel fragment
product KernelRewritePlan {
  kind [KernelRewriteKind],
  loop_header_block [CodeBlockId],
  loop_exit_blocks [many [CodeBlockId]],
  covered_blocks [many [CodeBlockId]],
  proofs [many [KernelProof]],
}
```

### Schema changes — `schema/lower.lua`

```lua
-- Projection mapping original blocks to replacement blocks
product LowerRewriteApplication {
  fragment [LowerFragment],
  rewrite_plan [KernelRewritePlan],
  replacement_blocks [many [CodeBlock]],
  block_mappings [many [LowerBlockMapping]],
}

sum LowerBlockMapping {
  LowerBlockEliminated { block [CodeBlockId] },       -- block removed
  LowerBlockRewritten { block [CodeBlockId], replacement [CodeBlock] },
}
```

### New leaf methods on `KernelResult`

Each `KernelResult` leaf produces a `KernelRewritePlan`:

```lua
function KernelResultClosedForm:lower_rewrite_plan(kernel_id, kplan)
  return KernelRewritePlan(
    KernelRewriteClosedForm(self.closed_form.expr, nil),
    kplan.body.domain.header_block,
    ...  -- exit blocks, covered blocks, proofs from kplan
  )
end

function KernelResultFind:lower_rewrite_plan(kernel_id, kplan)
  -- build KernelRewriteFind from find result data, trip count, lanes
end
```

### New file — `lua/lalin/lower_kernel_rewrite.lua`

Produces `LowerRewriteApplication` from `KernelRewritePlan`:

- `lower_rewrite_closed_form()` — emits a single `CodeBlock` evaluating the
  closed-form expression, then jumping to loop exit blocks.
- `lower_rewrite_memcpy()` — emits a `CodeBlock` computing `dst_base`, `src_base`,
  `bytes = trip_count * elem_size`, calling `memcpy`/`memmove`.
- `lower_rewrite_scan()`, `lower_rewrite_find()`, `lower_rewrite_reduce()` —
  emit `CodeBlock` chains calling typed helper functions.

The replacement blocks are pure `CodeBlock` nodes with `CodeInst` sequences and
`CodeTermJump` terminators. They look like normal Code IR to `CodeToC.module()`,
which is correct — the kernel proof has already proven equivalence.

### C helper functions

For memcpy, scan, find, and reduce rewrites, the Code IR contains `CodeInstCall`
to helper functions. New helper specs in `emit_c_helpers.lua`:

```lua
CBackendHelperSpec.Scan { mode [KernelScanMode], reduction [ReductionFact] }
CBackendHelperSpec.Find { predicate [KernelPredicate] }
CBackendHelperSpec.Reduce { reduction [ReductionFact] }
```

These helpers are generated with `restrict` and `__builtin_assume_aligned`
annotations using the existing `stencil_c.lua` infrastructure.

### Flow

```
lower_semantic_func()
  → for each fragment with KernelRewriteKind != None:
      → lower_kernel_rewrite.apply() → LowerRewriteApplication
  → collect all replacement_blocks → rewritten CodeFunc
  → CodeToC.func(rewritten_func) → CBackendFunc
  → for fragments with KernelRewriteNone:
      → existing CMat inline lowering
```

---

## Layer 3: CBackend Annotation Facet

### Problem

`CBackend` models flat goto-control-flow with no awareness of loops, alignment on
indexed access, branch probability, or vectorization. These are structural C
facts (not compiler-specific) and belong in the CBackend vocabulary.

### Design

Add a **sibling facet** `CBackendUnitAnnotations` keyed by block labels and local
IDs. The flat goto IR stays unchanged. The facet is populated by the lowering
layer and consumed by a hint-injection pass in the emission layer.

### Schema changes — `schema/c.lua`

```lua
-- ============================================================
-- Structural annotation facet
-- Carries loop structure, pointer semantics, and branch hints
-- that flat goto IR cannot represent directly.
-- ============================================================

product CBackendAnnotationSpine {
  interned,
  func_name [CBackendName],
}

-- Loop annotation: reconstructs structured loop from flat goto pattern
product CBackendLoopAnnotation {
  interned,
  spine [CBackendAnnotationSpine],
  header_label [CBackendLabel],
  body_labels [many [CBackendLabel]],
  back_edge_label [CBackendLabel],
  exit_labels [many [CBackendLabel]],
  induction_local [optional [CBackendLocalId]],
  induction_ty [optional [CBackendType]],
  trip_count [optional [CBackendRValue]],   -- (stop-start)/step expression
  direction [CBackendLoopDirection],
  vectorizable [bool],                      -- proven no loop-carried dependence
  unroll_hint [optional [number]],          -- from ScheduleVector.unroll
  interleave_hint [optional [number]],      -- from ScheduleVector.interleave
  tail_plan [CBackendLoopTailPlan],
}

sum CBackendLoopDirection {
  CBackendLoopForward,
  CBackendLoopBackward,
  CBackendLoopUnknown,
}

sum CBackendLoopTailPlan {
  CBackendTailNone,
  CBackendTailScalar,
  CBackendTailMasked,
  CBackendTailPeel { count [number] },
}

-- Pointer annotation: alignment, aliasing, bounds on a local pointer
product CBackendPointerAnnotation {
  interned,
  spine [CBackendAnnotationSpine],
  local_ptr [CBackendLocalId],
  alignment [CBackendAlignmentFact],
  restrict [bool],              -- proven no-alias
  non_trapping [bool],          -- proven non-trapping loads
  bounds_range [optional [CBackendBoundsFact]],
}

sum CBackendAlignmentFact {
  CBackendAlignmentUnknown,
  CBackendAlignmentKnown { bytes [number] },
  CBackendAlignmentAssumed { bytes [number], level [str] },
}

product CBackendBoundsFact {
  start_offset [number],
  length_bytes [number],
}

-- Branch annotation: expected direction of a conditional jump
product CBackendBranchAnnotation {
  interned,
  spine [CBackendAnnotationSpine],
  block_label [CBackendLabel],
  condition_local [optional [CBackendLocalId]],
  polarity [CBackendBranchPolarity],
  reason [str],
}

sum CBackendBranchPolarity {
  CBackendBranchLikely,
  CBackendBranchUnlikely,
}

product CBackendFuncAnnotations {
  interned,
  spine [CBackendAnnotationSpine],
  loops [many [CBackendLoopAnnotation]],
  pointers [many [CBackendPointerAnnotation]],
  branches [many [CBackendBranchAnnotation]],
}

product CBackendUnitAnnotations {
  interned,
  module_name [str],
  funcs [many [CBackendFuncAnnotations]],
}
```

### `CBackendPlacePtrIndex` — alignment field

The `CBackendPlacePtrIndex` variant (used for `base[index]` array access) gains
an alignment field so annotation-less facts can flow through the place hierarchy:

```lua
CBackendPlacePtrIndex {
  base [CBackendAtom],
  index [CBackendAtom],
  ty [CBackendType],
  elem_size [number],
  align [optional [number]],   -- NEW
}
```

### `CBackendRValueBuiltin` — builtins in C IR

The hint-injection pass needs `__builtin_assume_aligned` and
`__builtin_expect` as first-class IR nodes:

```lua
CBackendRValueBuiltin {
  builtin [CBackendBuiltinKind],
  args [many [CBackendRValue]],
}

sum CBackendBuiltinKind {
  CBackendBuiltinAssumeAligned,   -- __builtin_assume_aligned(ptr, N)
  CBackendBuiltinExpect,          -- __builtin_expect(expr, expected)
  CBackendBuiltinAssume,          -- __builtin_assume(cond)
}
```

---

## Layer 4: Alignment Bridge — MemAnalysis → CMat → CBackend

### Problem

`cmat_access_binding_for_lane()` hardcodes `StencilAlignmentUnknown`. The
`KernelLane.backend_info` carries `MemAlignment` (with proofs) but there's no
conversion path.

### Design

Add leaf methods on `MemAlignment` for conversion to both CBackend alignment
and Stencil alignment.

### Schema changes — `schema/mem.lua`

```lua
-- Conversion to CBackend alignment fact
function MemAlignment:lower_c_alignment_fact()
  return CBackendAlignmentUnknown()
end

function MemAlignmentKnown:lower_c_alignment_fact()
  return CBackendAlignmentKnown(self.bytes)
end

function MemAlignmentAtLeast:lower_c_alignment_fact()
  return CBackendAlignmentKnown(self.bytes)  -- conservative: use minimum
end

function MemAlignmentAssumed:lower_c_alignment_fact()
  return CBackendAlignmentAssumed(self.bytes, "mem proof")
end

-- Conversion to Stencil alignment (for CMat)
function MemAlignment:lower_cmat_alignment_fact()
  return StencilAlignmentUnknown()
end

function MemAlignmentKnown:lower_cmat_alignment_fact()
  return StencilAlignmentKnown(self.bytes)
end

function MemAlignmentAtLeast:lower_cmat_alignment_fact()
  return StencilAlignmentKnown(self.bytes)
end
```

### Implementation — `lower_to_c.lua`

`cmat_access_binding_for_lane()` changes from:

```lua
alignment = StencilAlignmentUnknown(),
```

To:

```lua
alignment = lane_backend_alignment(lane),
```

Where `lane_backend_alignment()` reads `lane.backend_info[].alignment` and calls
`lower_cmat_alignment_fact()`.

---

## Layer 5: Schedule → CMat Vector Policy Bridge

### Problem

`computation_for_body()` always calls `default_stencil_schedule()` → scalar.
`ScheduleVector` with lanes, unroll, interleave, and tail policies is never
consumed.

### Design

The `emit_to_c()` path looks up the schedule by kernel ID from
`LowerCEmitInput.schedules` and passes it to `computation_for_body()`.
`CMatLoopNest.vector` carries the real policy. The emission layer reads it from
`CBackendLoopAnnotation` and generates pragmas.

### Implementation — `lower_to_c.lua`

```lua
function LowerEmitScalarKernel:emit_to_c(c_emission, fragment_emit)
  local sched = resolve_schedule(fragment_emit.fragment.strategy.kernel,
                                 schedule_index(fragment_emit.schedules))
  emit_kernel_fragment(c_emission, fragment_emit, sched or default_schedule())
end

function LowerEmitVectorKernel:emit_to_c(c_emission, fragment_emit)
  local sched = resolve_schedule(...)
  if sched and sched.form == ScheduleVector then
    emit_kernel_fragment(c_emission, fragment_emit, sched)
  else
    emit_kernel_fragment(c_emission, fragment_emit, default_schedule())
  end
end
```

`computation_for_body()` receives the real schedule and passes it to
`StencilComputation`. `CMatLoopNest.vector` now carries the actual policy.

---

## Layer 6: Emission — `c_inject_hints()` Pass

### Design

A new pass at the start of the `emit_c_lower.lua` pipeline reads
`CBackendFuncAnnotations` and injects compiler-specific pragmas and builtins into
the flat goto blocks. This runs **before** any optimizer pass that might rename
or reorder blocks.

### Pipeline order

```
CBackendFunc
  → c_inject_hints(annotations)        -- NEW: inject pragmas/builtins
  → compute_transfer_equivalence       -- existing: phi-node canonicalization
  → plan_field_hoists                  -- existing: repeated field access caching
  → copy_propagate_blocks              -- existing: copy propagation
  → remove_dead_copy_assigns           -- existing: dead copy elimination
  → emit_block_stmts_and_term          -- existing: inline + emit
  → C source text
```

### What `c_inject_hints()` does

**Pointer alignment**: For each `CBackendPointerAnnotation` with `Known(N)`:
```c
ptr = __builtin_assume_aligned(ptr, N);
```
Injected as a `CBackendRValueBuiltin` assignment at the first block that defines
the pointer.

**Loop pragmas**: For each `CBackendLoopAnnotation` with `vectorizable`:
```c
#pragma GCC ivdep
#pragma clang loop vectorize(enable)
```
Injected as `CBackendComment` pragma nodes on the loop header block.

**Unroll**: For each annotation with `unroll_hint`:
```c
#pragma GCC unroll N
#pragma clang loop unroll(count=N)
```

**Branch hints**: For each `CBackendBranchAnnotation`, wraps the condition of
`CBackendIfGoto`:
```c
if (__builtin_expect(cond, 0)) { ... }
```

**Tail merging**: For annotations with `TailPeel(count)` or `TailScalar`, the
pass injects peel/tail blocks before or after the loop body. These are standard
`CBackendBlock` chains — no new terminator types.

### Pragma emission

`CBackendComment` nodes that begin with `#pragma` are emitted directly (without
the `//` prefix). All other comments are emitted as `// comment`.

---

## Layer 7: Benchmark Hot Path — What Changes

### ADD dispatch (unchanged)

The ADD opcode in `LuaVM.dispatch` is already optimal: 9 instructions, field
hoisting keeps `proto→code`, `frame→regs`, and `self→tables` in registers. No
kernel proof applies (it's a dispatch loop, not a data loop). The `CBackend`
annotation facet doesn't apply to non-loop code.

### LuaString.eq byte loop

**Before**: Scalar byte loop with no alignment hints. GCC can't autovectorize.

**After**: The memory analysis proves alignment on the stack-allocated byte
arrays. `CBackendPointerAnnotation(alignment=Known(8))` → `__builtin_assume_aligned`.
If the string is long, `#pragma GCC ivdep` + branch hints on the loop exit.
GCC can autovectorize.

### LuaVM.dispatch opcode chain

**Before**: Linear `cmp/je` chain. No branch hints.

**After**: The lowering layer identifies the region entry block as a dispatch
pattern. `CBackendBranchAnnotation` with `Unlikely` polarity on the default/error
branch, `Likely` on the hot opcode branches. GCC emits forward conditional jumps
for unlikely paths, fallthrough for likely paths.

---

## Fact Flow — Before and After

### Alignment

```
Before:
  MemAnalysis: alignment=16, bounds=[0,1024], trap=NonTrapping
    → KernelLane.backend_info (facts attached, but NEVER READ)
    → cmat_access_binding_for_lane() (hardcodes StencilAlignmentUnknown)
    → CBackendPlacePtrIndex (no align field)
    → C emission: ptr[i] — no hints at all

After:
  MemAnalysis: alignment=16, bounds=[0,1024], trap=NonTrapping
    → KernelLane.backend_info
    → MemAlignmentKnown(16):lower_cmat_alignment_fact() → StencilAlignmentKnown(16)
    → CMatAccessBinding.alignment
    → CBackendPlacePtrIndex(align=16) + CBackendPointerAnnotation(Known(16))
    → c_inject_hints(): ptr = __builtin_assume_aligned(ptr, 16)
    → C emission: ptr = __builtin_assume_aligned(ptr, 16); ... ptr[i]
```

### Vectorization

```
Before:
  Schedule: Vector(lanes=4, unroll=2, interleave=1, tail=Scalar)
    → LowerEmitVectorKernel selected
    → emit_to_c() delegates to scalar
    → default_stencil_schedule() → Scalar
    → CMatLoopNest.vector = CMatVectorNone
    → C emission: plain scalar loop

After:
  Schedule: Vector(lanes=4, unroll=2, interleave=1, tail=Scalar)
    → LowerEmitVectorKernel selected
    → resolve_schedule(kernel_id) → ScheduleVector
    → computation_for_body(schedule) → real schedule
    → CMatLoopNest.vector = CMatVectorAutovec(lanes=4, tail=Scalar)
    → CBackendLoopAnnotation(vectorizable=true, unroll=2, tail=Scalar)
    → c_inject_hints(): #pragma GCC ivdep, #pragma GCC unroll 2
    → tail merging: inject scalar tail block
    → C emission: vectorized loop with scalar tail
```

### Trip count

```
Before:
  CountedDomain: start=0, stop=N, step=1, exclusive=true
    → semantic_facts(): FlowTripCountUnknown("no explicit trip-count CodeValueId")
    → Kernel planning: unknown trip count (can't compute bounds)
    → Lower: no trip count for memcpy/find rewrites
    → C emission: while(i < N) { ... } — flat goto

After:
  CountedDomain: start=0, stop=N, step=1, exclusive=true
    → semantic_facts(): trip_expr = ValueExprBinary("sub", N, Zero)
    → FlowTripCountExact(trip_value_id, trip_expr, proof)
    → Kernel planning: exact trip count known
    → Lower: KernelRewriteMemcpy(bytes = trip_count * elem_size)
    → Code IR rewrite: replaces loop with memcpy call
    → C emission: memcpy(dst, src, N * sizeof(T))
```

---

## Files Changed

| File | Changes |
|---|---|
| `schema/flow.lua` | Add `trip_expr` to `FlowTripCount` variants |
| `schema/mem.lua` | Add `lower_c_alignment_fact()` and `lower_cmat_alignment_fact()` leaf methods |
| `schema/kernel.lua` | Add `KernelRewriteKind` sum, `KernelRewritePlan` product, `lower_rewrite_plan()` methods on `KernelResult` leaves |
| `schema/lower.lua` | Add `LowerRewriteApplication`, `LowerBlockMapping` |
| `schema/c.lua` | Add annotation facet types, `CBackendRValueBuiltin`, alignment field on `CBackendPlacePtrIndex` |
| `schema/c_materialize.lua` | No changes — receives real alignment via wiring |
| `code_flow_facts.lua` | Compute trip count expression in `semantic_facts()` |
| `lower_kernel_rewrite.lua` | **New file** — Code IR rewrite for proven kernels |
| `lower_to_c.lua` | Wire alignment, schedule, annotations; apply kernel rewrites |
| `emit_c_lower.lua` | Add `c_inject_hints()` pass, pragma emission, `CBackendRValueBuiltin` handling |
| `emit_c_helpers.lua` | New helpers for scan/find/reduce with restrict + assume_aligned |

## What Does NOT Change

- `CBackendUnit` shape — still `sigs, types, globals, externs, helpers, funcs`
- `CBackendFunc` shape — still `name, sig, params, locals, body`
- `CBackendBlock` — still `label, params, stmts, term`
- `CBackendTerminator` — still `Goto, IfGoto, SwitchGoto, ReturnVoid, Return, Trap`
- `CodeToC.module()` — pure 1:1 translation, no added intelligence
- `code_kernel_plan.lua` — kernel matching unchanged; only adds `lower_rewrite_plan()` methods
- All existing tests — the CBackend IR is backward-compatible (new fields are optional, new annotations are additive)

## SOAC Materialization Rules

> **Note:** This section consolidates the content previously in the standalone
> `C_BACKEND_SOAC_MATERIALIZATION.md` document, now folded into this redesign
> document as a dedicated section.

The main C backend must not rediscover loop semantics during C lowering. The
SOAC/metastencil graph is the semantic optimization contract; CMat is only the
C-facing materialization of that graph.

### Required pipeline shape

```text
CodeModule
  -> graph / flow / value / memory / effect facts
  -> KernelModulePlan
  -> StencilComputation
       finite producer domain
       + typed access projections
       + pure point/stream expressions
       + algebraic sinks
       + legality/proof facts
  -> CMatFusedKernel
  -> inline StencilStreamOp / StencilSinkOp leaf emission
  -> LalinC.CBackendUnit
  -> emit_c
  -> gcc -O3 / AOT C source
```

`emit_c` output remains the C contract, but it must be produced from a typed
SOAC composition, not from direct kernel-effect emission and not from legacy
`StencilArtifact*` body shapes.

### Ownership

- `LalinStencil` owns computation meaning: producers, accesses, streams, sinks,
  point expressions, predicates, reducers, schedules, legality, proofs, and
  fusion inputs.
- `LalinCMat` owns C materialization decisions: loop axes, loop order, vector
  policy, unroll/interleave, access bindings, stream/sink materialization, and
  fused-kernel records.
- `LalinC` owns final C mechanics: ABI, C types, locals, helpers, labels,
  functions, globals, and final statement forms.
- `emit_c` prints `LalinC`; it is not an optimizer.

### Method doctrine

The active C path is leaf-owned by the SOAC graph:

```lua
function Stencil.StencilStreamMap:lower_c_inline_stream(input) ... end
function Stencil.StencilSinkOpStore:lower_c_inline_sink(input) ... end
function Stencil.StencilSinkOpFold:lower_c_inline_sink(input) ... end
function Stencil.StencilSinkOpScan:lower_c_inline_sink(input) ... end
```

`CMatFusedKernel` keeps the source `StencilComputation` as the contract. There is
no `CMatBody*` compatibility layer and no artifact-to-CMat materialization API.
If a new SOAC shape needs C behavior, add the missing ASDL leaf and install the
method on that leaf.

Outlined `ml_stencil_*` C functions are not the main `emit_c` lowering shape.
The default path is inline SOAC/CMat so GCC sees surrounding control, access
facts, and the data body in one optimization unit.

### Enforced hard-yank rule

Forbidden active paths:

```text
LowerStrategyKernel -> direct KernelEffectStore/Fold/Scan emission
LowerStrategyKernel -> StencilArtifactShape -> CMatBody* -> CBackend blocks
```

Required active path:

```text
LowerStrategyKernel -> StencilComputation -> CMatFusedKernel -> StencilStreamOp/StencilSinkOp leaves -> CBackend blocks
```

`Store`, `Copy`, `Reduce/Fold`, `Scan`, and `ScatterFold` must exercise this path
in tests. `KernelEffectFold` is represented as a fold sink on the computation;
it is not emitted as a direct side effect.

---

## Separation of Concerns

```
┌───────────────────────────────────────────────────────────────┐
│ LAYER: Analysis (Flow / Value / Mem / Effect)                 │
│ Question: What facts are proven?                              │
│ Types:   FlowTripCount, MemAlignment, FlowInduction,         │
│          MemBounds, MemDependence, ValueExpr                  │
│ Owners:  MemAlignment:lower_c_alignment()                     │
├───────────────────────────────────────────────────────────────┤
│ LAYER: Kernel (Proofs)                                        │
│ Question: What equivalences are proven?                       │
│ Types:   KernelResult, KernelEquivalence,                    │
│          KernelRewritePlan                                    │
│ Owners:  KernelResult:lower_rewrite_plan()                    │
├───────────────────────────────────────────────────────────────┤
│ LAYER: Lower (Decisions + Rewrites)                           │
│ Question: How should Code IR transform?                       │
│ Types:   LowerFragment, LowerStrategy,                       │
│          LowerRewriteApplication                              │
│ Action:  Produces rewritten CodeBlocks (projection, not mut.) │
│ Owners:  LowerEmitSelection:emit_to_c(),                     │
│          LowerBlockMapping → replacement CodeBlock            │
├───────────────────────────────────────────────────────────────┤
│ LAYER: CBackend (Structural C Facts)                          │
│ Question: What C code shape?                                  │
│ IR:      CBackendBlock (flat gotos)                           │
│ Facet:   CBackendFuncAnnotations                              │
│          CBackendLoopAnnotation                               │
│          CBackendPointerAnnotation                            │
│          CBackendBranchAnnotation                             │
│ Rule:    Language-agnostic structural facts only              │
│          No GCC-specific pragmas — those belong in emission   │
├───────────────────────────────────────────────────────────────┤
│ LAYER: Emission (Compiler-Specific)                           │
│ Question: What compiler output?                               │
│ Types:   CBackendRValueBuiltin                               │
│ Pragmas: #pragma GCC ivdep, __builtin_expect,                │
│          __builtin_assume_aligned                             │
│ Passes:  inject_hints → transfer_eq → field_hoist            │
│          → copy_prop → dead_copy → inline_emit               │
└───────────────────────────────────────────────────────────────┘
```
