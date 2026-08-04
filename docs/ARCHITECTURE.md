# Lalin Architecture

This document describes the active architecture. Historical backend designs and
completed migration assessments are intentionally not retained in `docs/`.

## System model

LLBL is the extensible language workbench. Lalin is its compiled language
member. Lua owns staging and genericity; Lalin programs are monomorphic typed
declarations lowered through checked ASDL.

The two supported authoring paths are:

```text
.lln declaration document
  -> lalin.loader / lalin.syntax.document
  -> LalinTree ASDL

Lua builder API
  -> LLBL staged heads
  -> declaration values
  -> LalinTree ASDL
```

Both paths converge on the same compiler:

```text
LalinTree
  -> type checking
  -> LalinCode
  -> graph / flow / value / memory / effect facts
  -> kernel and schedule plans
  -> Stencil kernel projection
  -> CMat materialization
  -> LOWER function/module assembly
  -> CBackendUnit
  -> emit_c
  -> GCC shared object or user-owned AOT build
```

The canonical C backend boundary is
`lua/lalin/compiler_schema_c_backend.lua:code_result_to_c`. Public compile
APIs route through `lua/lalin/impl/compiler_api.lua`.

## Backend policy

Fused emitted C compiled by GCC at `-O3` is the performance path. The same C
artifact is the AOT path. Stencil and CMat name the deterministic fused-C shape
contract; they are not binary templates.

LuaJIT bytecode emission is removed: the compiled artifact is always emitted C,
cooked with GCC for local JIT-like execution or handed to a user-owned AOT
build. The public surface exposes only the `compile_c_gcc` / emit-C paths.

Binary copy-patch banks, native template installers, and the former Rust /
Cranelift route are deleted. They are not supported, historical, or planned
backend surfaces.

## Semantic phase ownership

ASDL is the compiler's semantic type system. Source, checked, lower, and backend
schemas have different jobs:

- `lua/lalin/schema/code.lua` owns typed code and declarations.
- `graph.lua` and `flow.lua` own control topology and iteration facts.
- `value.lua`, `mem.lua`, and `effect.lua` own semantic analysis facets.
- `kernel.lua` owns selected computation plans.
- `schedule.lua` owns execution-plan choices.
- `stencil.lua` owns fused region semantics and exact provenance.
- `c_materialize.lua` owns deterministic CMat and C-fragment shape contracts.
- `lower.lua` owns consumed lowering decisions and immutable assembly facts.
- `c.lua` owns emitted C backend values, places, blocks, functions, and units.

Concrete ASDL leaves own semantic behavior. Inputs and results are named ASDL
products or unions. Semantic side maps, class/tag dispatch, generic context
bags, nil protocols, and ad hoc result tables are architecture bugs.

The ownership inventory and executable duplicate guard are documented in
The ownership inventory and executable duplicate guard are documented in the
"Schema ownership" section of this document. The binding doctrine is `docs/ASDL_GUIDE.md`.

## Region expansion ownership

`emit` and `call` are distinct typed operations. `emit` is open CFG expansion;
`call` is a sealed function/frame boundary returning a generated result variant.
They do not share an expansion result shape.

Open expansion is owned by the `RegionEmit*` ASDL vocabulary. Every invocation
projects a `RegionEmitEnvironment` with a block-aligned environment facet. Region
data parameters and caller wire captures become explicit block parameters,
splice-entry arguments, and internal-jump forwarding arguments. A block facet
omits data parameters shadowed by that block's own parameters. Continuation
payload markers remain values produced by the callee exit; other wire expressions
are captures evaluated at the emit site and carried through the emitted CFG.

The first typecheck establishes region protocols and source facts. Expansion
constructs fresh invocation-local block topology and local binding identities.
A second authoritative typecheck resolves every expression and place against that
final topology. Resolved place leaves recursively rebuild their bases; pass-one
region bindings are never accepted as lowering identities.

Sealed calls instead use `RegionCallExpansion`: a real function call, generated
result value, and caller-side variant dispatch. Neither emit environments nor
caller wire captures are smuggled into the sealed call frame.

## Kernel, Stencil, and CMat

Kernel planning identifies typed lanes, bindings, effects, counted domains,
results, and equivalence facts. Stencil projection turns those facts into a
fused computation with an exact iteration and provenance facet. CMat chooses a
deterministic materialized shape. LOWER builds the external-value, memory, exit,
coverage, and namespace environment before CMat emits a C fragment.

Function assembly is immutable: it removes exactly covered baseline blocks,
injects the original replacement-block parameters, preserves predecessor
arguments, retains exits and metadata, and returns typed rejection when the
splice contract cannot be proven.

Multiple sinks are emitted in deterministic computation order. `restrict` is
derived only from declared exact noalias evidence; pointer shape never implies
noalias.

## Memory coordinates

Fused address strength reduction is designed around memory-use coordinates, not
the disconnected carrier/address plans that remain to be deleted. The governing
equation, type forest, gates, and deletion boundary are defined in
equation, type forest, gates, and deletion boundary are defined in the
"CMat memory-coordinate architecture" section of this document.

The active sequence is:

1. preserve every fused load/store occurrence and its index in a CMat memory-use
   spine;
2. derive an exact coordinate facet from memory and Stencil iteration facts;
3. materialize absolute or cursor-based C addressing as explicit CMat C plan
   alternatives;
4. delete the obsolete Flow/LOWER carrier and synthetic-address vocabulary.

Bounds, alignment, alias capability, mutability, and trap/movement facts remain
orthogonal to address realization.

## LLBL bootstrap

`lua/llbl.lua` is the stage-0 kernel. `lua/llbl/bootstrap.lua` builds the
stage-1 `llbl` dialect and public `llbl.grammar`; the preserved stage-0 grammar
is `llbl.kernel.grammar`. LLBL owns generic regions, heads, fragments, origins,
diagnostics, formatting, indexing, and language composition. Dialects own
semantic meaning.

Hand-written `.lln` files are declaration documents. Types are Lua-evaluated
values in brackets, function bodies use `do ... end`, and top-level Lua chunk
forms are rejected. The language surface is specified in
`docs/LANGUAGE_REFERENCE.md`; workbench mechanics are in `docs/LLBL_GUIDE.md`.

## Repository map

```text
lua/llbl.lua                         LLBL stage-0 workbench
lua/llbl/                            LLBL bootstrap and syntax machinery
lua/lalin/dsl/                       Lalin builder heads
lua/lalin/schema/                 canonical typed schemas
lua/lalin/impl/                      phase and backend methods
lua/lalin/impl/lower_emit_c/         CMat environment, fragment, and assembly
lua/lalin/compiler_schema_c_backend.lua
                                      canonical C backend composition
lua/lalin/impl/compiler_api.lua      public compiler API implementation
lua/lalin/impl/cemit_emit.lua        CBackendUnit C emission
tests/schema/                     typed semantic boundary tests
tests/c_backend/                     emitted-C and GCC execution tests
```

## Validation

Primary gates are:

```sh
luajit tests/run.lua schema
luajit tests/run.lua c_backend
luajit tests/c_backend/test_compile_c_gcc_fresh_process.lua
```

Focused tests must construct ASDL inputs and assert ASDL outputs. GCC tests prove
the final typed C boundary; they do not replace local semantic tests.

## Authoritative documentation

- `docs/ASDL_GUIDE.md` — binding compiler/schema doctrine.
- `docs/DESIGN_BIBLE.md` — long-form design method.
- `docs/LANGUAGE_REFERENCE.md` — public language surface.
- `docs/LLBL_GUIDE.md` — LLBL workbench and region model.
- `docs/CONVENTIONS.md` — repository and naming conventions.
- `docs/LLBL_GUIDE.md` — LLBL workbench, region model, and role-directed bracket evaluation.

## CMat memory-coordinate architecture

_Merged from the former CMAT_MEMORY_COORDINATE_ARCHITECTURE.md: the fused memory-coordinate design authority for the emitted-C shape contract._


### Status

This document defines the schema-first replacement for the disconnected
`FlowCarrier` / `FlowAddress` / `LowerCarrierPlan` / `LowerAddressPlan`
machinery in the schema. It is the design authority for fused memory addressing.
Gates 1–3 and the deletion sweep are complete: exact memory uses project to
exact coordinates and then to executable C address plans.

### Semantic center

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

### Machine sentence

The coordinate lowerer consumes a fused CMat memory-use spine aligned with
canonical memory and Stencil iteration facts, proves one exact coordinate for
every use, and produces a closed C address plan whose leaves emit absolute or
cursor-based places.

### World line

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

### Window coordinate units

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

### Gate 1 — memory-use spine

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

### Gate 2 — coordinate facet

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

### Gate 3 — executable C address plan

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

### Store and window semantics

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

### Orthogonal capabilities

Address realization must not derive or alter:

- `CMatRestrictCapability`;
- alignment evidence;
- bounds proofs;
- trap/movement decisions;
- read/write mutability.

These remain fields of their existing memory/access facets. In particular, a
derived cursor local is never independently declared `restrict`.

### Fusion contract admission

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

Window footprints are derived language facts, not authored backend contracts. The
source window domain already owns iteration range, order, step, extent, and boundary
policy; each indexed expression contributes its exact displacement, while ordinary
`bounds(base)(len)` supplies the authored logical memory extent. The compiler never
asks the author to repeat those facts in a `window_footprint` assertion.

Clamp, wrap, and zero are total language operations. If a displaced use may cross the
window domain, LOWER preserves a dynamic boundary realization. A centered use may
share the ordinary affine cursor. Reject-boundary uses require compiler-derived
coverage; until the narrow affine coverage recognizer proves a nonzero displacement,
they reject with `LowerCMatCoordinateWindowBoundaryUnsupported`. Missing optimization
knowledge therefore preserves correct dynamic behavior rather than manufacturing
safety.

### Fusion boundary

Fusion is decided once, when a `StencilComputation` materializes as a
`CMatMaterializedFused`/`CMatMaterializedKernelFragment`. That successful CMat value is
the admission result; LOWER does not construct a second fusion verdict or duplicate
access, use, alias, proof, and write facts into an aggregate contract. LOWER only
closes exact coordinates and admitted accesses into an address plan and emits the
already-fused CMat shape.

Missing optimization capabilities do not prevent scalar fusion. Absent noalias
evidence disables `restrict`; unknown alignment, dynamic trip counts, and non-unit
stride select conservative emitted C. Provided kernel equivalence facts remain facts
of the materialized kernel, but generic proof obligations are not CMat admission
tokens. Only a typed structural or semantic contradiction may reject materialization.
Multi-sink accesses retain deterministic spine order even when they may alias.

### Retired vocabulary

The CMat/LOWER cutover deleted rather than revived:

- `FlowCarrierThread`, `FlowCarrierTransfer`, and `FlowCarrierStep`;
- `FlowAddressThread`, `FlowAddressUse`, and their `FlowFactSet` fields;
- `LowerCarrierPlan` and its block/edge vocabulary;
- `LowerAddressPlan`, synthetic address block parameters, edge transfers, lane
  lookups, and instruction-use projections;
- per-access `CMatCFragmentAccessAddressProjected`.

Both old and schema declarations are gone. The remaining legacy Code emitter
uses ordinary indexed places when it does not enter canonical CMat; GCC owns
strength reduction for that fallback path.

Those declarations mix checked recurrence analysis, eliminated-CFG transport,
and backend locals into a false spine. The fused loop and its memory-use spine
are the real owners.

`MemIndexInduction` remains the canonical proof that an authored memory index
is an exact flow induction.

### Method ownership

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

### Validation gates

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
6. **Deletion sweep — complete**: old and schema Flow/LOWER carrier/address
   transfer vocabulary, synthetic address locals, and projected CMat access
   sources are gone.

## Schema ownership

_Merged from the former SCHEMA_OWNERSHIP.md. The v1/v2 cutover is complete; schema-v2 vocabulary is the sole schema, and ownership remains the guard against re-introducing parallel implementations._


This is the executable ownership inventory for the canonical schema.
The guard is `tests/schema/test_schema_ownership_inventory.lua`.

### Rules

- A compiler namespace has exactly one intended owner.
- The schema owns every compiler namespace; the legacy schema is deleted.
- A new duplicate is a failing test, not an implicit migration decision.
- The schema owns duplicated compiler namespaces except `LalinPhase`, whose
  canonical owner is `lua/lalin/schema/phase.lua`.
- `lua/lalin/schema/host.lua` is the single Host boundary declaration.
- Cutovers delete old owners after all canonical consumers move; they do not add
  re-export or constructor compatibility shims.

### Current duplicate set

```text
bind check c c_materialize code compiler core effect exec flow graph init
kernel lower mem parse phase project schedule sem source stencil tree type value
```

Intended owners are `lua/lalin/schema/<name>.lua`, with two exceptions:

- `init` is bootstrap ownership in `lua/lalin/schema/init.lua`, not an ASDL
  namespace.
- `phase` is owned by `lua/lalin/schema/phase.lua`.

### Current status

`LalinPhase` now has one precise, no-`any` declaration owned by
`lua/lalin/schema/phase.lua`. The schema consumes that declaration directly and
instantiates it in its own context; there is no constructor adapter or duplicate
phase vocabulary.

### Shared and excluded boundaries

`lua/lalin/schema/host.lua` is consumed directly by the schema bootstrap.

The following explicit non-main backend schemas remain outside the neutral C
ownership cutover:

- `lua/lalin/schema/luajit.lua` — explicit LuaJIT bytecode boundary;
- `lua/lalin/schema/luatrace.lua` — excluded legacy LuaTrace vocabulary.

The native copy-patch schema is deleted and must remain absent.

### Cutover procedure

For each ownership package:

1. move canonical consumers to the intended schema owner;
2. run focused, suite, and fresh-process parity tests;
3. delete the old owner and its imports;
4. update the 25-name closed set and this inventory;
5. reject aliases, re-export shims, and constructor adapters.

The inventory is complete only when the duplicate set is empty.
