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

## P1 — window coordinate generalization

Forward unit-step window emission remains canonical. Before widening:

- define named element-space distance and extent products;
- retain exact boundary transformation provenance;
- choose absolute or relative coordinates per window use;
- prove clamp, wrap, and zero behavior with GCC tests;
- do not pass loose metric tuples or infer relative coordinates.

## P1 — fusion contract recomputation

After coordinate/fusion changes:

- recompute bounds, alias, alignment, mutability, and movement contracts;
- retain exact noalias evidence requirements for `restrict`;
- generalize multi-sink and supported window fusion only through typed plans;
- reject unsupported combinations rather than installing fallback protocols.

## P2 — schema ownership cutover

The duplicate-owner guard remains authoritative. Domain cutovers are serialized
and may resume only when canonical fresh-process parity exists for that domain.

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

