# Compiler World Model

Status: Step 6 closed for the ground-up Lua-ASDL compiler model.
Prerequisites:

- `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`
- `docs/COMPILER_ENTITY_IDENTITY_MODEL.md`
- `docs/COMPILER_CONCERN_AUTHORITY_MODEL.md`
- `docs/COMPILER_SPINE_MODEL.md`
- `docs/COMPILER_FACET_MODEL.md`

This document determines whether the compiler needs immutable worlds. It defines world-admission and
no-world verdicts in prose only. It does not define ASDL fields/products, machines, operations,
requests, result sums, phase order, caching, implementation, migration, or compatibility layers.

The closed result is intentionally minimal: the current compiler requires **zero worlds**.

---

## 1. World admission test

A candidate is a world only when all conditions hold:

1. **Real reuse frontier:** distinct consumers run later or independently and require one shared
   readonly snapshot. Immediate next-operation consumption inside one transaction is not enough.
2. **One spine:** the candidate contains exactly one S1–S8 allocation plus facets aligned to that
   allocation. Cross-spine facts remain typed references.
3. **Coherent full consumption:** every consumer needs the entire bundled frontier. If any consumer
   needs only a strict subset, the bundle is a context bag.
4. **One exact validity sentence:** the world completes, without qualifications:
   “This world changes exactly when ______ can no longer be reused.”
5. **No false invalidation:** every republication changes at least one consumer's next product.
6. **No stale reuse:** every change that requires a consumer's next product to change republishes the
   world or is consumed independently as a facet/value.
7. **Readonly frame publication:** an authority genuinely retains private domain state and must expose
   a snapshot rather than its frame. Pure request/projection operations have no frame to publish.
8. **Falsifiability:** removing the world would force multiple consumers to reconstruct a coherent
   fact set, coordinate identity through hidden convention, or observe mutable private state.
9. **No wrappers:** the candidate contains no diagnostics bag, cache knobs, coordinator state, target
   copy, nested world, operation result, direct entity collection, artifact, or host resource.

A spine or facet may have many consumers without becoming a world. Those values already are immutable
publications with exact generation/provenance. A world must add coherent snapshot semantics beyond
renaming them.

---

## 2. Closed result — no compiler worlds

The current compiler is one compilation transaction composed of stateless or request-owned semantic
operations over immutable values. It has:

- no retained semantic machine frame;
- no cross-compilation semantic cache;
- no independently scheduled analysis consumer;
- no public incremental semantic snapshot API;
- no consumer that requires an entire multi-facet bundle with one common frontier.

Therefore no candidate passes conditions 1, 3, 7, and 8 together.

Publication is already represented directly by:

- S1–S8 spine allocations with exact generation and provenance;
- F01–F34 facets with exact alignment and input frontiers;
- typed gate/outcome values consumed by coordinator continuations;
- direct fragments and backend entities;
- one-consumer encoded boundary records;
- C artifacts and live host resources at their respective boundaries.

Adding a `World` shell would create identity without new semantic knowledge.

---

## 3. Why “several consumers” is insufficient

The weaker argument “several consumers use this value, therefore it is a world” would create a world
for nearly every spine and facet. That contradicts the doctrine that worlds are optional publication/
reuse frontiers.

Consumers usually need different subsets:

- topology consumes S2 but not F14 scalar meaning;
- flow consumes F14 but not F16/F17 effects;
- effects consume F25/F27 but not every S4 memory facet;
- kernel recognition consumes F28 premises but schedule selection adds target/emitter capability;
- address planning consumes F31/F32 but not F33 qualification;
- backend construction consumes selected fragments and ownership/ABI facts, not a synthetic plan world.

Typed spine/facet references provide coherence without forcing these consumers through a shared bag.

---

## 4. Candidate verdict matrix

| Candidate | Verdict | Decisive reason |
|---|---|---|
| Authored program | S1 spine, not world | Initial S1 is consumed within authorship/resolution/checking; no snapshot beyond the spine |
| Checked program | direct S1 + facets | Consumers require different F01–F13 subsets; F10–F13 are target/representation-sensitive and F34 is later S4-aligned |
| Represented/expanded program | new S1 allocation | Closure/open/sealed transformations republish S1; another world kind would mirror chronology |
| Monomorphic code | S2 spine + direct F14 | Topology consumes S2 without F14; a wrapper adds no knowledge |
| Validated code | gate over S2 | O13 is consumed once and creates no reusable domain state |
| Topology | S3 spine | Edges/defs/uses/loops are already the shared structural publication |
| Analyzed program | rejected multi-spine bag | S2/S3/S4 facts have different producers, consumers, and invalidation |
| Memory | S4 + direct F24–F27/F34 | Consumer sets and frontiers differ; one memory world falsely invalidates unaffected consumers |
| Kernel | S5 + direct F28 | One spine/facet pair already publishes exact kernel meaning |
| Scheduled kernel | direct F29 over S5 | Schedule is a sparse decision facet; failed/no-plan paths are results, and consumer sets do not define a retained snapshot |
| Fused computation | S6 + direct F30 | Pure projection with spine-aligned facet; no retained frame or independent reuse lifetime |
| Coordinate/materialized use | S7 + direct F31/F32 | Address planning needs F31/F32 while qualification has an independent frontier |
| Qualified use | direct F33 | One sparse facet is not a world |
| Strategy/plan | F18/F22 + direct references | Honest content spans S2/S3 and includes decision outcomes/direct fragments |
| Fragment | direct entity + results/F23 | No fragment spine or several-plane fragment domain exists |
| Backend | S8 direct physical object | S8 has no facets; O25 is one gate/serialization concern |
| C artifact | artifact value | Portable boundary image, not reusable compiler-domain state |
| Loaded session | host resource | Mutable liveness and release boundary, not immutable semantic state |
| Target/policy/capability | intrinsic/request values | Constrained by target-consistency law, never a world |
| Diagnostics | concern-local results/law | A diagnostics world would flatten and duplicate child ownership |

---

## 5. Strong rejected candidate — checked-program world

A checked-program world appears attractive because many concerns refer to S1. It fails full-consumer
coherence:

- region expansion needs resolution/checking/control/contract facts but not target layout or ABI;
- layout needs F02/F03 but not every checked-body/control fact;
- ABI needs F03/F07/F10 but not constants or all control facts;
- code construction consumes a broader explicit set;
- diagnostics/tooling consume selected origins and typed facts;
- F34 storage-refined ownership cannot exist until S4/F16/F17 exist.

Bundling F01–F13 would make target/convention changes republish target-independent checking and
capture facts for consumers that produce identical results. Omitting F10–F13 creates a partial bundle
whose only purpose is to label “checking completed.” Neither shape passes the test.

The final accepted or represented program is an S1 allocation plus explicitly requested facets, not a
world. Generated closure/region occurrences create a new allocation of the same domain.

---

## 6. Strong rejected candidate — validated-code world

A validated-code wrapper would contain S2, F14, and an O13 certificate. It fails because:

- validation is a typed gate consumed once by the compilation continuation;
- topology needs S2 but not F14;
- scalar-aware analyses need S2+F14;
- later value/effect/baseline facets have independent S3/S4/capability frontiers;
- no authority retains a private code frame requiring snapshot publication.

S2 already has allocation identity, order, provenance to S1, and all structural content. The gate
authorizes the next operation; it does not become ambient state.

`CodeResult(module, contracts, layout_env)` is evidence of pass plumbing, not a world. Contracts stay
F06/F27; layout stays F10; accepted code stays S2.

---

## 7. Strong rejected candidate — analysis world

An analysis world would combine:

- S2 with F14–F18;
- S3 with F19–F23;
- S4 with F24–F27/F34;
- often S5/F28/F29 in current plan bags.

It violates the one-spine law immediately. It also has no validity sentence: a callee-summary change
must invalidate F17 but not F26 memory proofs; a contract mapping change may invalidate F27 without
reminting S4; a target capability change may invalidate F29 without changing F28.

The active `KernelModulePlan` referential-instance guard is not evidence for a world. Exact allocation
and provenance references on S3/S4/S5 and their facets replace instance-bundle equality.

---

## 8. Strong rejected candidates — S5, S6, and S7 worlds

### 8.1 Kernel/schedule

S5+F28 is already the immutable kernel publication. F29 is sparse and independently target/policy/
emitter-invalidated. Fused projection requires a selected schedule; strategy also consumes typed
rejections/no-plan outcomes that cannot enter a successful world. A combined kernel/schedule world
would either omit required result alternatives or retain them as ambient diagnostics.

### 8.2 Fused computation

S6+F30 is the exact output of one pure projection and already carries provenance to S5/S4 and its
premises. Removing a world shell does not force any consumer to reconstruct fused structure or
meaning; consumers receive S6 and F30 directly. Therefore the shell fails falsifiability.

### 8.3 Materialized uses

S7, F31, F32, and F33 do not have coincident consumers or frontiers:

- F31 use meaning follows fused-use semantics;
- F32 coordinate facts also depend on induction, memory, layout, schedule, and target;
- F33 qualification depends on exact declared pairwise noalias but not on coordinate arithmetic;
- address planning consumes F31/F32 and is a one-consumer boundary;
- fragment/backend qualification consumes F33 through accepted fragments.

One S7 world would falsely invalidate coordinate-only consumers on qualification changes. Separate
worlds would be individual facets wearing world names.

---

## 9. Strong rejected candidate — backend world

S8 is a complete physical object domain: functions, blocks, locals, labels, globals, data, externs,
helpers, storage, initializers, relocations, physical operations, addressability, order, and provenance.
Step 5 deliberately admits no S8 facet.

C validation and serialization are one concern. Validation is a gate and serialization yields artifact
values. AOT/GCC consume emitted artifacts; the loaded session is a host resource. A world containing
S8 plus the gate would be a renamed physical object plus its operation result.

---

## 10. Direct publication and coherence law

Without worlds, coherence is established by the values themselves:

1. every spine allocation names its compilation generation and exact predecessor provenance;
2. every facet names one aligned spine allocation and its exact input-frontier generations;
3. every cross-spine reference is typed and generation-scoped;
4. a consumer receives only the exact spines/facets/values its concern requires;
5. mismatched allocation/provenance is a typed rejection, never pointer-instance comparison, name
   parsing, or ambient coordinator state;
6. coordinators sequence values but mint no aggregate semantic identity.

A consumer cannot use structural interning or equal text to establish coherence.

---

## 11. Existing world vocabulary disposition

| Current vocabulary | Disposition |
|---|---|
| `LalinPhase.World`, `WorldId`, `Phase`, `Plan`, `PlanStep`, `Machine` | delete; generic execution framework with no active semantic owner |
| `DiagnosticsWorld` | delete; diagnostics remain typed concern-local outcomes |
| `ModuleSurface/Typed/Sem/Code` headers | delete as chronological pseudo-worlds/pseudo-spines |
| `CodeResult` | decompose into S2 plus exact references/results |
| `KernelModulePlan` | decompose into S5/F28 plus evidence references |
| `ScheduleModulePlan` | F29 entries plus request capability references |
| `StencilKernelModuleProjection` | typed S6/F30 projection, not world |
| `LowerModule`, `LowerBackSpine`, `LowerCModuleInput` | delete context/world/pass-through bags |
| `CMatFusedKernel` | decompose into S6/F30 and realization records |
| `CMatMemoryUseSpine` | S7 structural evidence; not wrapped in a world |
| `CompilerArtifactC` | external artifact bundle, not semantic world |
| `LalinExec` | delete speculative generic execution vocabulary |

Tests that pin these shapes are schema-shape evidence and cannot force their retention.

---

## 12. S1–S8 and F01–F34 coverage

| Spine | Publication disposition | Facet disposition |
|---|---|---|
| S1 | direct spine allocation, including derived closure/region generations | F01–F13 direct |
| S2 | direct accepted spine after O13 gate | F14–F18 direct |
| S3 | direct topology spine | F19–F23 direct |
| S4 | direct memory spine | F24–F27 and F34 direct |
| S5 | direct kernel spine | F28/F29 direct |
| S6 | direct fused spine | F30 direct |
| S7 | direct materialized-use spine | F31–F33 direct |
| S8 | direct physical backend object | no facets |

No spine or facet lacks a publication disposition. “Direct” means an immutable ASDL value with exact
generation/provenance, not a Lua table, side cache, or untyped argument bundle.

---

## 13. Future world admission

A future incremental compiler, daemon, IDE semantic snapshot, persistent build cache, or independently
scheduled analysis service may create a real retained frame and reuse frontier. That is not a reason
to predeclare worlds now.

Such a feature must rerun the admission test with concrete consumers and exact invalidation. It must
not retrofit `LalinPhase.World`, wrap the current pass graph, or introduce a compatibility bridge.

---

## 14. Step 6 closure proof

Step 6 is closed because:

- every plausible S1–S8 candidate has an explicit world/no-world verdict;
- the admitted world count is exactly zero;
- spines, facets, gates, direct entities, boundary records, artifacts, values, laws, and host resources
  remain distinct;
- no multi-spine analysis or planning bundle is admitted;
- no spine/facet pair receives a thin world wrapper;
- independent facet invalidation is preserved;
- publication coherence is generation/provenance-based rather than bundle-instance equality;
- all current `World`/phase/plan vocabulary has a delete/decompose/non-world disposition;
- future incremental reuse must prove a real boundary instead of being anticipated;
- no ASDL fields, machines, operations, requests, result sums, caching, implementation, migration, or
  compatibility layer has been defined.

## Next step — Semantic receivers, operations, and outcomes

Step 7 will assign each closed concern its distinguished Lua-ASDL receiver shape, exact typed inputs,
semantic operation, and complete result alternatives. It must use result-leaf continuation behavior
rather than manual dispatch and must not reintroduce generic contexts or chronological pass machines.
