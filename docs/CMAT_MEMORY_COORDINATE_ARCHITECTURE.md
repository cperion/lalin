# CMat Memory Coordinate Architecture

## Status

This document defines the schema-first replacement for the disconnected
`FlowCarrier` / `FlowAddress` / `LowerCarrierPlan` / `LowerAddressPlan`
machinery in schema v2. It is the design authority for fused memory addressing.
Implementation proceeds only through the gates named below. Gate 1 is complete;
Gate 2 coordinate projection remains the next implementation boundary.

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
  -> CMatCAddressPlan                         absolute/cursor realization
  -> CBackend blocks, cursor locals, and places
  -> emitted C -> GCC -O3
```

### Reuse boundaries

- `MemSemanticFactSet` changes when memory decomposition, induction evidence,
  layout, effects, or contracts change.
- `CMatMemoryUseSpine` changes when fused streams, sinks, or their index
  semantics change.
- `LowerCMatCoordinateFacet` changes when the memory-use spine, canonical
  memory facts, or Stencil iteration changes.
- `CMatCAddressPlan` changes when the coordinate facet, C target, or selected
  CMat schedule changes.

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
    index [CMatMemoryUseIndex],
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
  entries [many [LowerCMatUseCoordinateEntry]],
}

sum. LowerCMatCoordinateProjection {
  LowerCMatCoordinatesProjected { facet [LowerCMatCoordinateFacet] },
  LowerCMatCoordinatesRejected { issues [many [LowerIssue]] },
}
```

An affine coordinate is constructed only when `MemIndexInduction` and
`StencilKernelIteration` agree exactly on counter, initialization, and step.
The basis excludes per-use constant offsets so centered, field, and constant
window uses can share one cursor.

General or dynamically transformed uses remain absolute. A disagreement
between facts about the same fused use is a rejection, not an absolute
fallback.

## Gate 3 — executable C address plan

Absolute and cursor addressing are true executable alternatives. Concrete
leaves own place emission.

```lua
product. CMatCAddressCursorId { interned, text [str] }

product. CMatCAddressCursor {
  interned,
  id [CMatCAddressCursorId],
  basis [LowerCMatAddressBasis],
  local [CBackendLocal],
  step_bytes [number],
}

sum. CMatCUseAddressing {
  CMatCAbsoluteAddressing {
    root [CBackendLocal],
    index [CMatMemoryUseIndex],
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
- A constant window offset is a use displacement only after its boundary
  transformation proves that representation.
- Clamp, wrap, zero, or other dynamically transformed windows stay absolute
  until a typed relative-coordinate result exists.
- Backward and non-unit loops require no new semantic alternative: they change
  the signed `step_bytes` of the cursor.
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

## Retired vocabulary

The schema-v2 cutover deletes rather than revives:

- `FlowCarrierThread`, `FlowCarrierTransfer`, and `FlowCarrierStep`;
- `FlowAddressThread`, `FlowAddressUse`, and their `FlowFactSet` fields;
- `LowerCarrierPlan` and its block/edge vocabulary;
- `LowerAddressPlan`, synthetic address block parameters, edge transfers, lane
  lookups, and instruction-use projections;
- per-access `CMatCFragmentAccessAddressProjected`.

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
`StencilIndexProducer`; later C emission rejects explicit stores until Gate 3.

No method may inspect a child class, return a selector string, use nil as an
outcome, or carry semantic state in a Lua map.

## Validation gates

1. **Spine tests** — exact load/store/window occurrence identity and order;
   store index preservation; no hidden producer-index convention.
2. **Coordinate tests** — exact induction alignment, contradiction rejection,
   absolute relation retention, and basis sharing.
3. **Plan tests** — one cursor per structural basis, mixed absolute/cursor uses,
   deterministic identities, and typed lookup failures.
4. **Equation tests** — absolute and cursor forms produce identical byte
   addresses for forward, backward, non-unit, nonzero-start, and constant-offset
   cases.
5. **GCC tests** — centered reads and stores, shared cursors, mixed uses, early
   exits, and no double indexing under `-O3`.
6. **Deletion sweep** — no schema-v2 carrier/address-transfer vocabulary or
   synthetic `sem_addr_*` local generation remains.
