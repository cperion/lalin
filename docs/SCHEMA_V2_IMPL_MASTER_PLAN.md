# Schema-v2 Compiler Plan

**Status:** active queue only. Completed migration ledgers and superseded design
drafts were removed during documentation consolidation.

**Primary path:** `.lln` / builder declarations -> typed ASDL -> Code facts ->
Stencil/CMat -> LOWER -> `CBackendUnit` -> `emit_c` -> GCC `-O3`.

**Authority:** `docs/ASDL_GUIDE.md` is binding. Public language behavior is
defined by `docs/LANGUAGE_REFERENCE.md`; current compiler composition is defined
by `docs/ARCHITECTURE.md`.

## Integrated baseline

The active tree includes:

- canonical graph, flow, value, memory, effect, kernel, and schedule facts;
- exact Kernel -> Stencil provenance and typed rejection;
- canonical CMat counted, window, and control fragments;
- typed external-value, access, exit, target, and namespace environments;
- immutable CMat-preserving function/module assembly;
- GCC `-O3` execution coverage for scalar, control, window, assembly, and
  multi-sink fragments;
- exact declared-noalias projection to `restrict`;
- conservative induction preservation as `MemIndexInduction`;
- exact CMat memory-use and coordinate facets;
- executable absolute, iteration, dynamic-window, and shared-cursor C address
  plans with typed lookup/rejection;
- cursor preheader initialization and signed fused-loop advancement;
- deletion of native copy-patch runtime, banks, schemas, tests, and APIs.

Current validation baseline:

```text
schema_v2: 57 passed
c_backend: 31 passed
embedded binary: passing
```

Counts are informative, not completion criteria.

## P0 — CMat memory coordinates

Design authority: `docs/CMAT_MEMORY_COORDINATE_ARCHITECTURE.md`.

The old Flow/LOWER carrier and address plans are disconnected from canonical
fused C and must not be revived.

### Gate A — memory-use spine — complete

- preserve the exact index of `KernelEffectStore` through Stencil;
- define stable CMat identities for stream, window-offset, and sink memory uses;
- derive one ordered `CMatMemoryUseSpine` from each fused computation;
- prove load/store/window occurrence identity with focused schema tests.

### Gate B — coordinate facet — complete

- align every memory use with canonical `MemAccessFact` and Stencil iteration;
- derive exact absolute or iteration-affine coordinates;
- reject contradictory or missing facts through typed projection results;
- share structurally equal address bases without semantic side maps.

### Gate C — executable C address plan — complete

- materialize explicit absolute/cursor addressing leaves;
- emit one preheader seed and one signed step per shared cursor basis;
- keep per-use displacement separate from the cursor basis;
- support forward, backward, non-unit, nonzero-start, and constant-offset cases;
- preserve bounds, alignment, alias, mutability, and trap facts unchanged;
- add equation and GCC `-O3` execution tests.

### Gate D — delete obsolete vocabulary — complete

`FlowCarrier*`, `FlowAddress*`, `LowerCarrier*`, `LowerAddress*`, synthetic
carrier/address edge state, `sem_addr_*` generation, and the per-access projected
source variant have been removed from both schema trees and all emitters. Legacy
non-CMat Code emission now retains ordinary indexed places for GCC optimization.

## P1 — window coordinate generalization — complete

Window semantics now use named `StencilElementDistance` and
`StencilWindowExtent` products. The coordinate facet retains exact extent and
boundary provenance in distinct relative and dynamic window-coordinate leaves.
Centered window uses select shared cursors; transformed clamp/wrap/zero uses
select dynamic addressing; unsupported reject-boundary displacement rejects the
whole projection. Forward, backward, unit, and non-unit element-distance behavior
executes through GCC `-O3` tests. No loose metric tuples or inferred relative
coordinates remain.

## P1 — CMat materialization and access contracts — complete

CMat access admission is now the exact conjunction of preserved backend facts:

- bounds must be `MemBoundsInObject`, `MemBoundsRange`, or an explicit
  `MemBoundsAssumed`; unknown bounds reject;
- the access must be `MemNonTrapping` and `MemMovementMovable`; checked,
  potentially trapping, or pinned accesses reject;
- alignment, bounds, trap, and movement evidence are carried into each fragment
  binding and validated against the exact provenance lane;
- mutability remains derived from the authored Stencil access role;
- `restrict` remains derived only from exact declared pairwise noalias facts.

No pointer-shape inference, aggregate option bag, or fallback legality protocol is
introduced. Unsupported combinations reject through typed LOWER/CMat results.

Window footprint authorship is part of the window language, not a separate compiler
contract. The window producer supplies range, order, step, extent, and boundary; each
memory use supplies its displacement; `bounds(base)(len)` supplies the logical memory
extent. `CodeContractWindowFootprint` and its LOWER projection are retired. Clamp,
wrap, and zero preserve dynamic realization when coverage is not derived, while
nonzero reject-boundary uses remain typed rejections until narrow affine coverage can
establish that the authored iteration domain is interior to the declared bounds.

Fusion has one boundary: successful Stencil-to-CMat materialization. The resulting
`CMatMaterializedFused`/`CMatMaterializedKernelFragment` is the typed admission
result. LOWER does not recompute fusion or duplicate access, use, alias, write, and
proof planes into a whole-fusion contract. Missing optimization capabilities select
conservative scalar C: noalias alone controls `restrict`, and generic proof
obligations never gate CMat materialization.

## P1.5 — public schema-v2 compiler convergence — typed 1D window and sum-fold gates complete

The explicit public `lalin.compile_v2` path preserves parsed function bodies and
executes scalar and one-dimensional clamp/wrap/zero windows, centered reject windows,
window arithmetic streams, deterministic multisink stores, and one-dimensional integer
sum folds through `.lln -> schema-v2 Tree -> Code -> Flow -> Stencil -> CMat -> LOWER
-> emitted C -> GCC -O3`. Parsed loops, axes, windows, reducers, and sinks cross the
`ParsedStmt` boundary as ASDL values. Tree loop domains are projected through
`CodeOriginLoopDomain`; Flow consumes that typed origin directly. Encoded block-name
domain recovery has been deleted. LOWER rejection now crosses the compiler backend
as `CompilerCBackendRejected` and becomes a typed `CompilerArtifactError` only at the
artifact boundary; it does not escape `CompilerSession:compile()` as a Lua error.
Nonzero `boundary = reject` displacement remains conservative until ordinary memory
extent and authored-domain evidence can prove a narrow affine interior. Wrap realization
is covered for distances larger than the domain extent. Integer division, remainder, and
shift helpers emit their declared guards and operations; unsupported helper leaves fail
during emission instead of silently returning the first operand. Canonical and schema-v2
registry paths now return `CompilerCBackendOutcome`; phase execution carries that exact
outcome, while successful schema-v2 artifacts enforce C validation before source is
accepted. Static data and slice descriptors are covered through GCC execution. Sum folds
use `ExprDomainControl` and an exact `StmtBranchJump` terminator so loop-carried values
remain typed edge arguments. The C emitter performs parallel edge transfer into block
parameters; zero-, one-, and many-trip seeded arithmetic folds execute through CMat when
bounds evidence is present, while missing optimization evidence retains correct scalar C.

The default `lalin.compile_c_gcc` path is not switched yet. Schema-v2 intentionally
rejects parsed scan, non-add fold reducers, tiled, multi-axis, backward, nonzero-start, and
non-unit-step lowering until those alternatives have complete typed projections and
execution coverage.
coverage. No raw-loop adapter, cross-context constructor adapter, encoded-name
fallback, or fallback to the legacy C backend is permitted.

## P2 — schema ownership cutover

The duplicate-owner guard remains authoritative. Domain cutovers are serialized
and may resume only when canonical fresh-process parity exists for that domain.

The `LalinPhase` exception is closed: one precise no-`any` declaration remains
owned by `schema/phase.lua`, and schema v2 consumes that declaration as data before
instantiating it in its own context. Phase diagnostics, determinism, external
capabilities, and value-type references are typed; the ownership and legacy schema
suites are green.

For each cutover:

1. establish the schema-v2 owner and leaf methods;
2. move all canonical consumers;
3. run local, suite, and fresh-process tests;
4. delete the old owner and imports;
5. update `docs/SCHEMA_OWNERSHIP.md`;
6. do not add re-export or constructor compatibility shims.

The final old-tree retirement is blocked until every ownership domain is closed.

## Non-goals

- no native copy-patch or binary-bank revival;
- no Cranelift/Rust backend revival;
- no inferred noalias;
- no LuaJIT parity work unless explicitly scheduled;
- no side maps, handler tables, generic contexts, nil semantic protocols, or
  ad hoc result records;
- no broad optimization work before typed semantic contracts are complete.

## Required validation per gate

```sh
luajit tests/run.lua schema_v2
luajit tests/run.lua c_backend
luajit tests/code_ir/test_lalin_binary.lua
git diff --check
```

Add focused tests for every new semantic boundary and a GCC test whenever the
boundary changes emitted C behavior.

