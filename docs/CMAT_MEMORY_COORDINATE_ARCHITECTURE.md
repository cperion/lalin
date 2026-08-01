# CMat Memory Coordinate Architecture

## Status

This document defines the schema-first replacement for the disconnected
`FlowCarrier` / `FlowAddress` / `LowerCarrierPlan` / `LowerAddressPlan`
machinery in schema v2. It is the design authority for fused memory addressing.
Gates 1–3 and the deletion sweep are complete: exact memory uses project to
exact coordinates and then to executable C address plans.

## Semantic center

A fused memory operation is a **memory use with a coordinate**. Address
strength reduction is a later executable realization of that coordinate; it is
not an intrinsic property of a lane or access.

For fused-loop ordinal `o`:

```text
counter(o) = start + direction * o * step

address(use, o) =
  root
  + counter(o) * index_scale_bytes
  + use_offset_bytes
```

A cursor realization factors the same equation:

```text
cursor(0)   = root + start * index_scale_bytes
cursor(o+1) = cursor(o) + direction * step * index_scale_bytes

address(use, o) = cursor(o) + use_offset_bytes
```

The architecture keeps these axes independent:

1. **Memory root** — the `MemBase` that owns the addressed storage.
2. **Authored coordinate** — the exact `MemIndex` of the source memory fact.
3. **Iteration coordinate** — the counted Stencil iteration and its ordinal.
4. **Use displacement** — the constant or dynamic displacement of one load or
   store occurrence.
5. **Addressing realization** — absolute indexing or a moving cursor.
6. **Memory capabilities** — bounds, alignment, alias, mutability, and
   `restrict`; these remain orthogonal to coordinate realization.

## Machine sentence

The coordinate lowerer consumes a fused CMat memory-use spine aligned with
canonical memory and Stencil iteration facts, proves one exact coordinate for
every use, and produces a closed C address plan whose leaves emit absolute or
cursor-based places.

## World line

```text
CodeModule + CodeGraph
  -> FlowFactSet
  -> MemSemanticFactSet                       exact MemBase / MemIndex
  -> KernelModulePlan
  -> StencilKernelComputationProjection       exact iteration and use semantics
  -> CMatFusedKernel + CMatMemoryUseSpine     fused memory-use identity/order
  -> LowerCMatCoordinateFacet                 proven use coordinates
  -> CMatCAddressPlan                         absolute/cursor/dynamic realization
  -> CBackend blocks, cursor locals, and places
  -> emitted C -> GCC -O3
```

### Reuse boundaries

- `MemSemanticFactSet` changes when memory decomposition, induction evidence,
  layout, effects, or contracts change.
- `CMatMemoryUseSpine` changes when fused streams, sinks, or their index
  semantics change.
- `LowerCMatCoordinateFacet` changes when the memory-use spine, canonical
  memory facts, Stencil iteration, or exact window domain provenance changes.
- `CMatCAddressPlan` changes when the coordinate facet, C target, or selected
  CMat schedule changes.

## Window coordinate units

Window dimensions are explicit element-space values:

```lua
product. StencilElementDistance { elements [number] }
product. StencilWindowExtent {
  before [StencilElementDistance],
  after [StencilElementDistance],
}
product. StencilWindowAxis {
  extent [StencilWindowExtent],
  boundary [StencilWindowBoundary],
}
product. StencilWindowOffset {
  axis [StencilAxisRef],
  distance [StencilElementDistance],
}
```

A distance is independent of loop stride and direction. The projection validates
that extents are nonnegative integers and that each distance is a finite integer
inside the declared extent. Invalid evidence rejects the complete coordinate
facet.

## Gate 1 — memory-use spine

A memory access can have multiple uses with different coordinates. Addressing
cannot therefore be selected only by `StencilAccessRef`.

```lua
sum. CMatMemoryUseId {
  CMatStreamMemoryUse { stream [StencilStreamRef] },
  CMatWindowMemoryUse { stream [StencilStreamRef], ordinal [number] },
  CMatSinkMemoryUse { sink [StencilSinkRef] },
}

sum. CMatMemoryUseRole {
  CMatMemoryLoad,
  CMatMemoryStore,
}

sum. CMatMemoryUseIndex {
  CMatMemorySelectedIndex { selection [StencilIndexSelection] },
  CMatMemoryWindowOffset { offset [StencilWindowOffset] },
}

product. CMatMemoryUse {
  id [CMatMemoryUseId],
  access [StencilAccessRef],
  role [CMatMemoryUseRole],
  index [CMatMemoryUseIndex],
}

product. CMatMemoryUseSpine {
  uses [many [CMatMemoryUse]],
}
```

`StencilSinkOpStore` must retain a `StencilIndexSelection`. Construction of an
elementwise store may select `StencilIndexProducer` only after the original
`KernelEffectStore.index` is proven equal to the projected kernel counter. The
index must not be dropped by convention.

The spine is a derived CMat projection. Every concrete stream and sink leaf owns
an explicit contribution method; there is no parent empty default that can hide
a new memory-bearing alternative. Centered accesses, gathers, stores, scans, and
scatter sinks preserve `StencilIndexSelection`; nested point-window expressions
contribute through immutable expression assembly. `StencilFoldStores` carries its
exact selection. Non-memory leaves explicitly contribute none. Window offsets
receive occurrence identity through `(stream, ordinal)`, including duplicate
offset values.

## Gate 2 — coordinate facet

The coordinate facet aligns exactly one relation with every memory use.
`NotApplicable` is not stored semantic state. A use has either an exact
absolute coordinate or an exact iteration-affine coordinate. Contradictory or
missing source facts reject the projection as a whole through typed issues.

```lua
product. LowerCMatAddressBasis {
  interned,
  root [MemBase],
  induction [FlowInduction],
  index_scale_bytes [number],
}

sum. LowerCMatUseCoordinate {
  LowerCMatAbsoluteCoordinate {
    root [MemBase],
    index [StencilIndexExpr],
    index_scale_bytes [number],
    const_offset_bytes [number],
  },
  LowerCMatIterationAffineCoordinate {
    basis [LowerCMatAddressBasis],
    use_offset_bytes [number],
  },
}

product. LowerCMatUseCoordinateEntry {
  use [CMatMemoryUseId],
  coordinate [LowerCMatUseCoordinate],
}

product. LowerCMatCoordinateFacet {
  spine [CMatMemoryUseSpine],
  iteration [StencilKernelIteration],
  entries [many [LowerCMatUseCoordinateEntry]],
}

sum. LowerCMatCoordinateProjection {
  LowerCMatCoordinatesProjected { facet [LowerCMatCoordinateFacet] },
  LowerCMatCoordinatesRejected { issues [many [LowerCMatCoordinateIssue]] },
}
```

The projection resolves each `StencilAccessRef` through the exact provenance
entry, its single `KernelLane` memory-access identity, and the corresponding
`MemAccessFact`. Missing, ambiguous, root-disagreeing, or iteration-disagreeing
relations reject the whole facet/address plan.

An affine coordinate is constructed only for producer-selected or window uses
whose `MemIndexInduction` agrees with `StencilKernelIteration` on primary role,
counter, index type, initialization, and step. The scale is the positive
`MemIndexInduction.elem_size`. The structurally interned basis excludes constant
offsets; `use_offset_bytes` is the memory fact's constant byte offset plus any
window element offset multiplied by the scale. Centered, field, and constant
window uses can therefore share one basis.

Explicit `StencilIndexExpr` uses remain absolute and retain the memory fact's
scale and constant byte offset. Window uses additionally retain a
`LowerCMatWindowCoordinateProvenance` containing their exact typed distance,
extent, and boundary. Centered window transformations produce
`LowerCMatWindowRelativeCoordinate`; nonzero clamp/wrap/zero transformations
produce `LowerCMatWindowDynamicCoordinate`. Reject-boundary displacement without
proof rejects the facet. A producer or window use backed only by `MemIndexValue`
is contradictory evidence and rejects rather than silently falling back.
falling back to absolute addressing.

## Gate 3 — executable C address plan

Plan production is closed over absolute, cursor, and dynamic-window addressing.
Iteration-affine stream and sink uses always select a cursor; there is no separate
unproduced indexed-iteration leaf. Concrete leaves own place emission.

```lua
product. CMatCAddressCursorId { interned, text [str] }

product. CMatCAddressCursor {
  interned,
  id [CMatCAddressCursorId],
  basis [LowerCMatAddressBasis],
  base [CBackendLocal],
  cursor_local [CBackendLocal],
  start [CodeValueId],
  step_bytes [number],
}

sum. CMatCUseAddressing {
  CMatCAbsoluteAddressing {
    base [CBackendLocal],
    index [StencilIndexExpr],
    index_scale_bytes [number],
    const_offset_bytes [number],
  },
  CMatCDynamicWindowAddressing {
    base [CBackendLocal],
    index_scale_bytes [number],
    const_offset_bytes [number],
  },
  CMatCCursorAddressing {
    cursor [CMatCAddressCursorId],
    displacement_bytes [number],
  },
}

product. CMatCUseAddressingEntry {
  interned,
  use [CMatMemoryUseId],
  addressing [CMatCUseAddressing],
}

product. CMatCAddressPlan {
  interned,
  spine [CMatMemoryUseSpine],
  iteration [StencilKernelIteration],
  cursors [many [CMatCAddressCursor]],
  uses [many [CMatCUseAddressingEntry]],
}
```

One structurally interned address basis produces one cursor entry. Reuse is an
explicit typed relation in the plan, never a side table and never a scan of
fragment locals.

The cursor projection owns:

- one preheader initialization per basis;
- one signed advancement per loop step;
- deterministic backend-local identity;
- typed lookup by cursor identity.

The use-addressing leaves own:

- absolute index/place emission;
- cursor lookup and displaced place emission;
- typed invariant rejection for missing or ambiguous plan relations.

## Store and window semantics

- Centered loads and stores may use an iteration-affine cursor.
- Stores retain their exact index selection in Stencil and their use identity
  in CMat.
- Window distance, extent, and boundary transformation remain explicit typed
  provenance through LOWER.
- Centered window uses are relative cursor coordinates. Nonzero clamp, wrap, and
  zero boundaries use dynamic transformed coordinates; reject-boundary
  displacement is rejected without an exact proof.
- Backward and non-unit loops use the same element-distance semantics. Loop order
  changes cursor stepping and domain bounds, never the meaning of window distance.
- Early exits need no special address transfer. Cursor advancement belongs to
  the fused loop's common step block, not to the eliminated source CFG.

## Orthogonal capabilities

Address realization must not derive or alter:

- `CMatRestrictCapability`;
- alignment evidence;
- bounds proofs;
- trap/movement decisions;
- read/write mutability.

These remain fields of their existing memory/access facets. In particular, a
derived cursor local is never independently declared `restrict`.

## Fusion contract admission

Every CMat fragment access binding carries the exact alignment, bounds, trap, and
movement facts from its provenance lane. Admission is leaf-owned and conservative:

- unknown bounds reject; object/range/explicitly-assumed bounds proceed;
- potentially trapping or checked-trapping accesses reject;
- pinned accesses reject; only `MemMovementMovable` proceeds;
- fragment validation requires one exact matching provenance contract;
- mutability remains the authored Stencil role;
- `restrict` still requires exact declared pairwise noalias evidence.

Address realization may consume these facts but cannot strengthen them. Window
boundary transformation and fused scheduling therefore never manufacture safety
or alias evidence.

This gate validates exact contract presence and provenance, not a numeric aggregate
window footprint. Existing `MemBounds` alternatives do not name the fused lower,
upper, extent, step, and boundary relation. A future footprint guarantee must model
that relation explicitly in ASDL; emitted clamp/wrap/zero code is not proof.

## Retired vocabulary

The CMat/LOWER cutover deleted rather than revived:

- `FlowCarrierThread`, `FlowCarrierTransfer`, and `FlowCarrierStep`;
- `FlowAddressThread`, `FlowAddressUse`, and their `FlowFactSet` fields;
- `LowerCarrierPlan` and its block/edge vocabulary;
- `LowerAddressPlan`, synthetic address block parameters, edge transfers, lane
  lookups, and instruction-use projections;
- per-access `CMatCFragmentAccessAddressProjected`.

Both old and schema-v2 declarations are gone. The remaining legacy Code emitter
uses ordinary indexed places when it does not enter canonical CMat; GCC owns
strength reduction for that fallback path.

Those declarations mix checked recurrence analysis, eliminated-CFG transport,
and backend locals into a false spine. The fused loop and its memory-use spine
are the real owners.

`MemIndexInduction` remains the canonical proof that an authored memory index
is an exact flow induction.

## Method ownership

Signatures are designed before bodies:

```text
Stencil `ValueExpr` index-selection leaf
  :stencil_index_selection(StencilKernelIndexSelectionInput)
  -> StencilIndexSelection


Stencil stream/sink operation leaf
  :cmat_memory_uses(definition)
  -> CMatMemoryUseContribution

CMatMemoryUseSpine
  :lower_coordinates(input)
  -> LowerCMatCoordinateProjection

LowerCMatUseCoordinate leaf
  :materialize_c_addressing(input)
  -> typed C address-plan assembly

CMatCAddressCursor projection
  :emit_preheader(input)
  :emit_step(input)
  -> CMat fragment state result

CMatCUseAddressing leaf
  :emit_place(input)
  -> CMat fragment place result
```

Every closed `ValueExpr` alternative is representable as `StencilIndexPoint`, so
the projection preserves non-counter indexes explicitly rather than inventing an
unsupported alternative. Only an exact counter identity selects
`StencilIndexProducer`; executable explicit stores are admitted through the
Gate 3 absolute addressing leaf.

No method may inspect a child class, return a selector string, use nil as an
outcome, or carry semantic state in a Lua map.

## Validation gates

1. **Spine tests — complete**: exact load/store/window occurrence identity and
   order; store index preservation; no hidden producer-index convention.
2. **Coordinate tests — complete**: exact induction alignment, contradiction
   rejection, absolute relation retention, and basis sharing.
3. **Plan tests — complete**: one cursor per structural basis, mixed
   absolute/cursor/dynamic-window uses, deterministic identities, and typed
   lookup failures.
4. **Equation tests — complete at the plan boundary**: forward, backward,
   non-unit, nonzero-start, and constant-offset cursor equations.
5. **GCC tests — active**: cursor preheader/step execution, centered loads and
   stores, multi-sink uses, windows, folds, and early exits execute under `-O3`.
6. **Deletion sweep — complete**: old and schema-v2 Flow/LOWER carrier/address
   transfer vocabulary, synthetic address locals, and projected CMat access
   sources are gone.
