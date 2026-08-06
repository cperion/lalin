# Compiler Structural Spine Model

Status: Step 4 closed; semantic alignment continues in `docs/COMPILER_FACET_MODEL.md`.
Prerequisites:

- `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`
- `docs/COMPILER_ENTITY_IDENTITY_MODEL.md`
- `docs/COMPILER_CONCERN_AUTHORITY_MODEL.md`

This document identifies the minimum stable structural coordinate systems shared by the closed
compiler concerns. It defines spine domains in prose only. It does not define ASDL declarations,
facets, worlds, machine objects, operations, result sums, implementation, or migration.

Current products named `Spine`, repeated IDs, phase bags, and pass outputs are evidence only.

---

## 1. Spine admission test

A candidate is a spine only when all conditions hold:

1. **Multi-concern alignment:** at least two concern authorities must refer to the same structural
   population and require one coordinate system.
2. **Structural content only:** the candidate carries identity, topology, order, addressability,
   origin, ranges, or structural relations—never type, layout, proof, schedule, effect, bounds,
   coordinates, policy, or other concern meaning.
3. **One authoritative allocation:** one immutable spine value exists per generation.
4. **New structural domain:** the boundary creates a genuinely new entity or occurrence family,
   not a typed wrapper or re-listing of existing identity.
5. **No duplicate topology:** no other spine or later concern recreates its containment, order,
   CFG, parent/child, or structural relations.
6. **Typed provenance:** every preserved or newly created occurrence points to its cause without
   parsing an encoded name.
7. **Falsifiability:** removing the spine must demonstrably force at least two concerns to rebuild
   identity/topology/order or coordinate through hidden conventions.

A new generation is not automatically a new spine domain. The same spine family may have a new
allocation when an operation creates new occurrences in that same structural vocabulary.

An entity is not automatically a spine. A direct entity or projection is preferable when no
several-concern alignment exists.

---

## 2. Closed spine set

The minimum model contains eight spine domains:

1. Semantic program spine
2. Monomorphic code spine
3. Control-topology spine
4. Memory-object/access spine
5. Kernel spine
6. Fused-computation spine
7. Materialized memory-use spine
8. Physical backend spine

These are distinct identity domains. There is no universal compiler spine.

---

## 3. Spine graph

```text
request target/policy generation                         (value, not spine)
        │
        ▼
S1 Semantic program spine @ authored generation
        │
        ├── closure/open/sealed operations may create
        │   a new S1 allocation with preserved + generated occurrences
        ▼
S2 Monomorphic code spine
        │
        ▼
S3 Control-topology spine ───────────────┐
        │                                │
        ▼                                ▼
S4 Memory-object/access spine       S5 Kernel spine
        │                                │
        └──────────────┬─────────────────┘
                       ▼
                S6 Fused-computation spine
                       │
                       ▼
                S7 Materialized memory-use spine
                       │
                       │  fragment entities contribute realized content
                       ▼
                S8 Physical backend spine
                       │
                       ▼
              validated C source/header                    (artifact values)
                       │
                       ▼
               GCC / loaded session                        (host boundary)
```

Arrows mean typed provenance and consumption. They do not mean that one spine copies the prior
spine. Each later spine carries only its own structural population and references prior occurrences.

Fragments are direct entities between S3/S6/S7 and S8; they are not another spine.

---

## 4. S1 — Semantic program spine

### 4.1 Why it exists

Resolution, nominal/type semantics, checking, control legality, contracts, ownership, constant
evaluation, capture, layout, region calculus, code construction, diagnostics, and tooling must all
refer to the same authored or generated declaration/body occurrences.

Without one program spine, those concerns recreate declaration order, binding identity, control
containment, and origin using strings such as `arg_<fn>_<name>`, `region:param:*`,
`emit:local:*`, or source offsets.

### 4.2 Structural population

The spine carries only:

- program identity and generation;
- ordered declaration occurrences;
- declaration containment;
- ordered nominal child occurrences: fields and variants;
- function/region parameter and binding occurrences;
- ordered statement, expression, place, and pattern occurrence slots;
- authored control-region entry/block/parameter/continuation occurrences;
- region invocation and wiring occurrence slots;
- source/generated origin for each occurrence;
- deterministic containment and order;
- authored namespace/name keys only where needed for addressability, never as identity.

A binding is an occurrence in this spine, not a separate binding spine. A field/variant is a child
occurrence, not a nominal/type spine.

### 4.3 Allocations and creators

The initial allocation is created by authored program materialization. Staged synthesis supplies
generated inputs and causal origin, but a declaration becomes a program occurrence only when
authorship admits it.

An operation that creates new semantic-program occurrences creates a new allocation of the same
spine domain:

- closure representation, if it introduces environment declarations/helpers into the semantic
  program;
- open-region expansion, for cloned blocks/bindings/values;
- sealed-region semantics, for generated callables/result nominals/frame occurrences.

Unchanged occurrences preserve typed identity. New occurrences carry `caused-by` and
`derived-from` provenance. A new allocation never aliases the previous allocation merely because
equal ASDL values were interned.

The post-expansion coordinator may sequence contributions, but occurrence creation remains owned
by closure/open/sealed concern leaves.

### 4.4 Invalidation

An initial S1 allocation remains valid until source, builder, splice, synthesis result, or authored
origin changes.

A derived S1 allocation remains valid until its predecessor, capture representation, region
definition/protocol/invocation/wiring, caller environment, or ABI-dependent generated shape changes.

Checking does not create a new spine. Rechecking a derived S1 allocation publishes new semantic
facts aligned to the same structural occurrences.

### 4.5 Consumers

- declaration resolution;
- nominal declaration and type meaning;
- scalar/checking/control/contract/ownership/constant concerns;
- capture and closure representation;
- layout and ABI where they refer to nominal entities;
- open/sealed region concerns;
- code construction;
- diagnostics and compiler tooling.

### 4.6 Exclusions

The S1 spine contains no resolved namespace relation, type, layout, checked header, contract,
capture, ownership, constant, diagnostic, closure representation payload, or region expansion
decision. Those are concern-owned facts or operation outcomes.

---

## 5. S2 — Monomorphic code spine

### 5.1 Why it exists

Code construction establishes the first structural domain independent of authored tree shape.
Validation, topology, all analyses, planning, fragments, backend construction, and diagnostics refer
to the same function/block/instruction/value occurrences.

### 5.2 Structural population

The spine carries only:

- code-generation identity and provenance to the accepted S1 allocation;
- ordered function occurrences;
- ordered type-declaration, data, global, and extern occurrences where they are code entities;
- per-function parameter, local, block, and value-definition occurrences;
- per-block ordered instruction occurrences and one terminator occurrence;
- typed target references encoded by control terminators;
- deterministic construction order;
- origin/provenance to checked declarations, bindings, constants, and generated causes.

Function signatures and structural types are values referenced by occurrences. They are not entity
identity. Relocations are typed relation occurrences, not a separate spine.

### 5.3 Creator and identity

Monomorphic code construction creates the S2 allocation and the code function/block/instruction/
terminator/value/local/data/global/extern occurrence family.

Code identities are generation-scoped slots/references. They are not C names or globally interned
text. Nominal type references preserve S1 nominal identity by provenance.

### 5.4 Invalidation

S2 remains valid until the accepted semantic program generation or a consumed representation
decision changes. Rebuilding code creates a new allocation even when emitted text would be equal.

### 5.5 Consumers

- code structural validation;
- control topology;
- flow/value/memory/effect concerns;
- kernel recognition and lowering strategy;
- fragment coverage/materialization;
- backend construction;
- diagnostics.

### 5.6 Exclusions

The S2 spine contains no validation result, control edge population, natural loop, flow/value
fact, memory fact, effect, kernel, schedule, layout, ABI decision, lowering strategy, or C fact.

Code construction order is the sole order of functions, blocks, parameters, locals, and
instructions. Later topology borrows this order and may establish edge/loop order; it does not
remint a competing block/instruction order.

---

## 6. S3 — Control-topology spine

### 6.1 Why it exists

Control topology creates natural-loop identity and publishes structural relations consumed by
flow, value, memory, effects, kernel recognition, scheduling, lowering strategy, dominance, and
fragment coverage.

A separate S3 is required because:

- loops are new generation-scoped entities;
- topology has narrower invalidation than code identity;
- a facet may not recreate CFG topology;
- downstream analyses currently rebuild edges, definitions, uses, and block indexes independently.

### 6.2 Structural population

The spine carries only:

- topology-generation identity and reference to its exact S2 allocation;
- edge occurrences or typed edge relations, including arm/duplicate slots where distinction matters;
- structural edge-argument-to-block-parameter wiring;
- definition relations from code values to parameters/instructions;
- use occurrence relations from values to instructions/terminators, with slots where duplicates
  matter;
- natural-loop occurrences;
- loop header, body, latch, exit, and nesting/containment relations where present;
- deterministic edge/use/loop order;
- provenance to S2 blocks, instructions, terminators, and values.

Graph blocks are typed references to S2 blocks. S3 never creates a second block, instruction, or
value identity class.

### 6.3 Creator and identity

Control topology creates the S3 allocation, all loop identities, and any duplicate edge/use
occurrence slots. Edges, definitions, and uses that need no occurrence distinction remain typed
structural relations.

### 6.4 Invalidation

S3 remains valid until code blocks, instructions, terminators, value definitions, or control
targets are reconstructed or split. A topology rebuild creates new loop identity while preserving
typed provenance to surviving S2 occurrences.

### 6.5 Consumers

- flow and induction semantics;
- value and algebra semantics;
- memory and effect semantics;
- kernel and schedule concerns;
- fused projection;
- lowering strategy;
- fragment dominance/coverage;
- backend construction where baseline control is retained.

### 6.6 Exclusions

S3 contains no counted-loop decision, induction, domain, trip, range, algebra, memory, effect,
kernel, schedule, dominance result, or coverage decision.

Current `CodeGraph` is evidence for this domain but not authoritative target shape. Its block/inst
wrapper IDs and text loop IDs must not survive.

---

## 7. S4 — Memory-object/access spine

### 7.1 Why it exists

Memory semantics creates storage entities independent of the value/place that first revealed them
and creates access occurrences that may be one-to-many per code operation. Effects, ownership,
kernel lanes, fused accesses, coordinates, restrict qualification, and backend construction must
share those identities.

### 7.2 Structural population

The spine carries only:

- memory-analysis generation and exact S2/S3 provenance;
- ordered memory-object occurrences;
- root-object and subobject occurrence identity;
- structural root/parent lineage and typed storage-provenance paths;
- ordered memory-access occurrences;
- each access's S2 operation anchor plus access ordinal;
- structural object/access anchoring required for addressability;
- deterministic object/access order;
- provenance to parameters, locals, globals, data, views/slices, and code operations.

The access ordinal distinguishes multiple equal-looking accesses in one operation. Object identity
does not depend on which access first exposed the object.

### 7.3 Creator and identity

Memory-object and access semantics creates the S4 allocation, object/subobject identity, and
access occurrence identity. It is the only creator of memory storage topology.

### 7.4 Invalidation

S4 remains structurally valid until its exact S2/S3 provenance, object/access population, order,
root/subobject lineage, or access anchors change. Bounds, alias, effect, layout, and other semantic
facts may invalidate independently without reminting S4 occurrences.

### 7.5 Consumers

- effect semantics;
- ownership/access refinement;
- checked-contract subject mapping;
- kernel recognition and lane provenance;
- fused computation projection;
- memory-coordinate materialization;
- backend memory realization and diagnostics.

### 7.6 Exclusions

S4 contains no element type meaning, extent, stride, bound, alignment amount, trap decision, alias/
noalias, disjointness, dependence, movement legality, readonly/writeonly effect, proof, or backend
addressing. Same-store/slice/dependence relations that carry semantic conclusions remain outside
the spine.

---

## 8. S5 — Kernel spine

### 8.1 Why it exists

Kernel recognition creates computations semantically distinct from topology loops and may admit
more than one candidate for a subject. Schedule selection, fused projection, strategy, and
diagnostics must share kernel-local lane/binding identity without reconstructing the kernel body.

A bare loop reference is insufficient; the current `kernel:<loop-text>` echo hides the missing
entity boundary.

### 8.2 Structural population

The spine carries only:

- kernel-generation identity and deterministic kernel order;
- kernel occurrence identity and subject provenance to S3;
- kernel-local lane occurrence identity/order;
- kernel-local binding occurrence identity/order;
- kernel-local result/protocol occurrence slots where cross-referenced;
- provenance from lanes/bindings to S4 accesses/objects and S2 values.

### 8.3 Creator and identity

Kernel recognition creates S5 and all kernel/lane/binding occurrences. Rejected candidates do not
become fake kernels; their rejections remain aligned to S3 candidate subjects.

### 8.4 Invalidation

S5 remains structurally valid until its exact source-spine provenance or kernel/lane/binding
population, containment, order, or source alignment changes. Analysis evidence may invalidate
independently when it does not alter that structural population.

### 8.5 Consumers

- schedule selection;
- fused computation projection;
- lowering strategy;
- kernel diagnostics and planning policy.

### 8.6 Exclusions

S5 contains no domain, trip, algebraic expression, bounds, effect conclusion, kernel-admission
proof, result semantics, schedule, tail, target capability, or no-plan rejection.

---

## 9. S6 — Fused-computation spine

### 9.1 Why it exists

Fused projection establishes a new child occurrence family—iteration axes, producers, streams,
fused accesses, sinks, and result protocol—used by coordinate and fragment concerns. Without S6,
CMat and fragment code reconstruct axes, loop nests, streams, and sink topology.

### 9.2 Structural population

The spine carries only:

- fused-generation and computation occurrence identity;
- deterministic axis occurrence identity/order;
- producer occurrence slots and containment;
- stream occurrence identity/order;
- fused-access occurrence identity/order;
- sink occurrence identity/order;
- result/protocol occurrence identity/order;
- structural stream/access/producer/sink relations;
- provenance to S5 kernels/lanes/bindings and S4 memory accesses.

Flow loop/domain identity is referenced, not copied. Start/stop/step/trip are not structural spine
content.

### 9.3 Creator and identity

Fused computation projection creates S6 and its child occurrences. A rejected fused candidate
does not create an accepted spine allocation; its rejection refers to S5/S3 subjects.

### 9.4 Invalidation

S6 remains structurally valid until its exact source-spine provenance or fused axis/producer/stream/
access/sink/result population, containment, order, or alignment changes. Schedule/evidence changes
that leave this structure unchanged invalidate their own facts rather than reminting S6.

### 9.5 Consumers

- memory-coordinate materialization;
- fragment materialization and assembly;
- lowering-strategy attempt/commitment;
- diagnostics for physical realization.

### 9.6 Exclusions

S6 contains no schedule form, flow trip/domain value, index expression, memory guarantee, alias
proof, fusion legality proof, operator semantics, coordinate, address, fragment, or C shape.

Current `StencilComputation` and `CMatFusedKernel` mix structural and semantic planes and duplicate
iteration/stream topology. They are evidence to decompose, not target spines.

---

## 10. S7 — Materialized memory-use spine

### 10.1 Why it exists

One fused access may produce several physical uses with different coordinates, especially window
occurrences and duplicate offsets. Coordinate derivation requires exactly one entry per use; a
fused access reference alone cannot identify the occurrence.

This is the strongest already-demonstrated spine pattern in the active compiler.

### 10.2 Structural population

The spine carries only:

- materialization-generation identity and exact S6 provenance;
- ordered materialized memory-use occurrences;
- occurrence ordinal, including distinct ordinals for equal window offsets;
- provenance to the fused access/stream/sink/result occurrence that caused each use;
- deterministic use order and grouping/containment required for lookup.

Load/store role, selected index, window displacement, coordinate, cursor, basis, bounds, alignment,
trap, movement, alias, `restrict`, and address are not spine content.

### 10.3 Creator and identity

Memory-coordinate materialization creates the S7 allocation and each physical-use occurrence.
It allocates S7 once, before deriving coordinates. Equal independently derived lists do not count as
the same allocation through interning.

### 10.4 Invalidation

The structural S7 allocation remains valid until the S6 use-producing topology changes. Memory
evidence, layout, schedule, or target changes that alter only coordinates/addressing do not by
themselves change S7 occurrence identity; they invalidate later derived facts instead.

If such a change alters which uses exist or their order, a new S7 allocation is required.

### 10.5 Consumers

- coordinate/address derivation;
- fragment materialization;
- lowering-strategy realization outcomes;
- backend construction through accepted fragments;
- diagnostics aligned to an exact use.

### 10.6 Exclusions

S7 contains no coordinate or address plan. Coordinates are facts aligned one-for-one to uses;
cursors are plan-local occurrences inside address realization; address bases are structural values.

The current `CMatMemoryUseSpine` survives only as behavioral evidence. Its embedded role/index facts
must not be copied into the target spine.

---

## 11. S8 — Physical backend spine

### 11.1 Why it exists

Backend construction establishes a physical identity domain with an independent lifetime. C
validation, serialization, AOT users, symbol/relocation projection, and diagnostics must share one
ordered physical unit/function/block/local topology.

Without S8, validation and serialization independently index/reconstruct backend functions, blocks,
locals, labels, helpers, globals, and symbol addressability.

### 11.2 Structural population

The spine carries only:

- backend-generation and translation-unit occurrence identity;
- deterministic ordered physical function, global, data, extern, helper, and signature-entry
  occurrences;
- per-function ordered parameter/local/block/label/statement/terminator occurrence slots required
  for physical addressability;
- physical block/control structural relations;
- containment and order;
- provenance to S2 code occurrences and accepted fragment contributions;
- typed addressability relation from backend entities to ABI-owned symbol keys, without treating
  symbol spelling as entity identity.

### 11.3 Creator and identity

Backend-unit construction creates S8 and all final backend physical entities/coordinates. Fragment
materialization creates fragment-local planned occurrences only; it does not mint final backend
locals/labels. Backend construction maps accepted contributions into S8 with typed provenance.

This resolves the current dual-coordinate risk where CMat code directly allocates `CBackendLocal`
objects before final backend construction.

### 11.4 Invalidation

S8 remains structurally valid until its physical entity/coordinate population, containment, order,
control relations, addressability, or provenance changes. Layout, ABI, target, and strategy facts may
invalidate independently when they leave the physical structure unchanged.

### 11.5 Consumers

- C validation;
- deterministic C source/header serialization;
- AOT artifact users;
- GCC symbol and relocation boundary;
- backend diagnostics.

### 11.6 Exclusions

S8 contains no C text, validation report, type/layout semantics, scalar semantics, memory proof,
strategy decision, fragment feasibility fact, ABI passing rule, linkage policy, target capability,
annotation meaning, or loaded-session state.

The backend spine is the structural core of the physical backend model, not a second complete
backend IR beside it.

---

## 12. Disjoint topology proof

Every structural relation has one home:

| Structural relation | Sole spine owner |
|---|---|
| semantic declaration/body/control containment and authored/generated order | S1 |
| monomorphic function/block/instruction/value containment and construction order | S2 |
| CFG edges, edge arguments, definitions, uses, natural-loop containment and loop order | S3 |
| memory root/subobject lineage and code-anchored access occurrence order | S4 |
| kernel-to-lane/binding containment and order | S5 |
| fused axis/producer/stream/access/sink/result containment and order | S6 |
| materialized physical-use occurrence order and fused provenance | S7 |
| final backend unit/function/block/local/label/helper containment and order | S8 |

Relations crossing domains are typed provenance, not copied topology:

- S2 occurrence → S1 checked/generated cause;
- S3 loop/edge/use → S2 blocks/instructions/values;
- S4 object/access → S2 storage root/operation and S3 loop where relevant;
- S5 kernel/lane/binding → S3 loop, S4 access/object, S2 value;
- S6 fused child → S5 lane/binding and S4 access;
- S7 physical use → S6 access/stream/sink;
- fragment entity → S2/S3 covered subject and S6/S7 realization inputs;
- S8 physical entity → S2 code entity or accepted fragment contribution;
- symbol key → S8 backend entity plus ABI/linkage policy.

No concern may rebuild another spine's topology into a fact bag or side index that becomes
semantic authority.

---

## 13. Generation and invalidation summary

| Spine | Creator | New identity | Valid until |
|---|---|---|---|
| S1 Semantic program | Authorship initially; closure/open/sealed concern for a derived allocation | declarations, bindings, authored/generated nodes and control occurrences | program occurrence population/order/origin or generating provenance changes |
| S2 Code | Monomorphic code construction | code function/block/inst/term/value/local/data/global/extern occurrences | code occurrence population/order/containment/origin or source generation changes |
| S3 Control topology | Control topology | loops and duplicate edge/use occurrence slots | CFG/def-use/loop structure or exact S2 provenance changes |
| S4 Memory | Memory semantics | objects, subobjects, accesses | object/access population, lineage, anchors, order, or exact source-spine provenance changes |
| S5 Kernel | Kernel recognition | kernels, lanes, bindings | kernel-child population/order/alignment or exact source-spine provenance changes |
| S6 Fused | Fused projection | fused computation/axes/streams/accesses/sinks/results | fused-child population/order/alignment or exact source-spine provenance changes |
| S7 Memory use | Coordinate materialization | physical-use occurrences | use-producing fused topology changes |
| S8 Backend | Backend construction | physical backend entities and coordinates | physical population/topology/order/addressability/provenance changes |

Cross-generation equality never grants validity. A typed reference from one allocation cannot enter
an unrelated allocation through process-global interning or equal text.

---

## 14. Explicit non-spines

### 14.1 Document/source index

Source bytes, spans, and positions are document-lifetime values/coordinates. S1 stores their origin
relation. Tooling indexes are outside the compiler model.

### 14.2 Nominal/type spine

Nominal child occurrences already live in S1. Structural types and signatures are values. A new
type spine would either duplicate S1 containment or smuggle type/layout facts into structure.

### 14.3 Checked spine

Resolution, checking, contracts, ownership, constants, and layout create facts but no new
structural occurrence. A checked generation aligns to S1. Typed module headers and phase flags are
not spine evidence.

### 14.4 Capture or closure spine

Capture membership is a relation over S1 bindings. Closure environment fields/helpers either enter
a derived S1 allocation or remain a direct representation projection consumed by code construction.
No separate several-concern coordinate system is required.

### 14.5 Region spine

Region declarations, blocks, continuations, invocations, clones, and sealed generated declarations
are S1 occurrences. Expansion environments/splices are operation state/results, not spines.

### 14.6 Validation spine

Code and C validation certify S2 and S8 respectively. Reports create no structural identity or
population.

### 14.7 Flow/value/effect spine

Flow, induction, range, trip, algebra, reductions, closed forms, proofs, and effects are derived
semantic values aligned to S2/S3/S4. They create no structural occurrence family.

### 14.8 Schedule spine

A schedule is a decision aligned to S5 kernel identity. Form, tail, capability, policy, proofs, and
rejected alternatives are values, not topology.

### 14.9 Coordinate/cursor spine

Coordinates align to S7 uses; a coordinate is not an entity. Cursors are local occurrences in one
address plan with a sole realization consumer. Address bases are structural values.

### 14.10 Fragment/lowering spine

A materialized fragment is a direct generation-local entity with provenance to S2/S3/S6/S7.
Strategy and backend reference it directly. No several-plane fragment coordinate system exists.
Coverage intent and coverage feasibility remain separate concern decisions.

### 14.11 ABI/signature/symbol spine

Signatures are structural values, symbols are physical namespace keys, and relocations are typed
relations. Their projection graph is not a structural population.

### 14.12 C/artifact/session spine

Emitted C is a deterministic artifact value. Compiled artifact paths are host values. A loaded
session is a live host resource entity. None is a compiler alignment population.

### 14.13 Target/policy spine

Target and policy identify one request generation and are projected narrowly to physical concerns.
They are values constrained by the target-consistency law.

### 14.14 Diagnostic spine

Each rejection remains owned by the concern that made the decision and references its subject's
spine occurrence. Diagnostics do not form a structural compiler topology.

---

## 15. Current `Spine` vocabulary disposition

### Remove as a spine: `LowerBackSpine`

The current product combines an entire code module, a graph projection, and target facts. It is a
context/world bag, not structural alignment. Target is a request value; code and control belong to
S2/S3. Consumers require narrow typed inputs, not this bundle.

### Preserve only as behavioral evidence: `CMatMemoryUseSpine`

Its tests prove the need for S7 and dense use alignment. The target S7 contains identity/order/
provenance only; current role/index semantics do not belong in the spine.

### Remove as a spine: `CBackendAnnotationSpine`

It is a one-field encoded function-name key for speculative/unwired annotation vocabulary, not a
multi-concern structural domain. Any future annotation aligns to a typed S8 function occurrence.

### Decompose: `CodeGraph`

Graph block/inst wrapper IDs are duplicate keys and text loop IDs are invalid. S3 owns the true
structural edge/def/use/loop relations by typed S2 references.

### Remove phase-header pseudo-spines

`ModuleSurface`/`ModuleTyped`/`ModuleSem`/`ModuleCode` headers identify chronological states, not
new structural domains.

---

## 16. Obligation alignment

| Obligations | Structural alignment |
|---|---|
| O01–O03, O30, O36, O40 | S1 declaration/child/binding/origin structure |
| O04–O08, O29, O33, O37–O39 | facts and decisions aligned to S1; no new spine |
| O09–O11 | new S1 allocation for cloned/generated occurrences; rechecking preserves it |
| O12 | creates S2 |
| O13 | certifies S2 |
| O14 | creates S3 from S2 |
| O15–O16 | align to S2/S3 |
| O17 | creates S4 |
| O18 | aligns to S2/S4 |
| O19 | creates S5 |
| O20 | aligns schedule decision to S5 |
| O21 | creates S6 |
| O22 | creates S7, then derives coordinate/address facts aligned to it |
| O23 | creates direct fragment entities with S2/S3/S6/S7 provenance |
| O24 | creates S8 |
| O25 | certifies/serializes S8 without new spine |
| O26 | host boundary, no spine |
| O27 | diagnostics reference exact spine subjects; no diagnostic spine |
| O28 | target/policy request value, no spine |
| O31–O32 | ABI/scalar facts consumed by S8 construction; no spine |
| O34 | strategy aligns to S3/S5 and references S6/S7/fragment outcomes |
| O35 | generation/isolation law constrains all S1–S8 allocations |

All forty obligations have a structural destination or an explicit no-spine verdict.

---

## 17. Step 4 closure proof

Step 4 is closed because:

- every candidate structural domain has a keep/reject verdict;
- each kept spine is shared by several concern authorities;
- each kept spine contains only identity/topology/order/origin/addressability/structural relations;
- every Step-2 entity-creation boundary maps to exactly one spine or an explicitly direct entity;
- S1 explicitly permits new allocations of the same domain for generated semantic programs;
- S2 construction order and S3 topology order are not duplicated;
- S3, rather than a semantic fact bag, owns all CFG/loop/def/use structure;
- memory accesses are anchored to S2 operations but receive S4 occurrence identity;
- schedule remains a value aligned to S5 rather than a fake entity/spine;
- fused and memory-use occurrence families have distinct S6/S7 identity;
- fragments remain direct entities and backend final coordinates belong only to S8;
- backend physical identity is independent of code identity and shared by C validation/serialization;
- current false `LowerBackSpine`/annotation/phase-header shapes are rejected;
- no facet, world, ASDL product, machine receiver, operation, result sum, or implementation has been
  defined.

## Step 5 facet result

`docs/COMPILER_FACET_MODEL.md` assigns persistent derived facts to 33 concern-owned facet families
across S1–S7, gives every family an exact density and input frontier, and explicitly admits no S8
facet because physical backend meaning belongs to S8 entities.
