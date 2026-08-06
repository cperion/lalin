# Compiler Semantic Facet Model

Status: Step 5 closed, including the F07/F34 ownership split exposed by Step 6; receiver/operation
alignment continues in `docs/COMPILER_RECEIVER_OPERATION_RESULT_MODEL.md`.
Prerequisites:

- `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`
- `docs/COMPILER_ENTITY_IDENTITY_MODEL.md`
- `docs/COMPILER_CONCERN_AUTHORITY_MODEL.md`
- `docs/COMPILER_SPINE_MODEL.md`

This document assigns persistent derived semantic facts to the eight closed structural spines. It
defines conceptual facet families, density, producers, exact input frontiers, and consumers. It does
not define ASDL fields, worlds, machine products, requests, result sums, phase order, implementation,
migration, or compatibility layers.

Current fact bags, products named `Facet`, pass outputs, and tests that assert their field shape are
evidence only.

---

## 1. Facet admission test

A fact family is a facet only when all conditions hold:

1. **Derived persistence:** immutable facts survive the producing operation for later consumers.
2. **Sole producer:** exactly one closed concern authority produces the facts.
3. **One primary spine:** every fact aligns to exactly one S1–S8 allocation. References to other
   spines are typed evidence/provenance, never second alignment.
4. **Semantic content:** the family carries concern meaning, not identity, topology, order, origin,
   containment, or addressability already owned by a spine.
5. **Reuse need:** at least two consumers, or one consumer across an independent invalidation/lifetime
   boundary, needs the facts.
6. **Explicit invalidation:** its exact input frontier is stated. Families with different frontiers
   are separate even when aligned to the same spine; a non-structural reusable projection may share
   its spine's generation without becoming spine content.
7. **Named minimality:** it contains one concern's facts; keyed relations are named entries, never a
   generic map or context bag.
8. **No copied evidence:** facts owned by another concern are referenced with typed provenance, not
   retyped or cached under new authority.
9. **Honest density:** dense and sparse invariants are explicit; absence is never semantic `nil`.
10. **Necessary split:** different producer, primary spine, density, input frontier, or consumer set
    requires a different facet.

A facet is not admitted merely because a current pass returns a product, several operations need a
temporary index, or an old schema names a value `Facet`.

---

## 2. Dense and sparse alignment

### 2.1 Dense

A dense facet has exactly one entry for every member of a structurally determined eligible
subpopulation. Missing, duplicate, or ambiguous entries are defects.

Examples in this model:

- one checked-meaning entry per S1 expression/place/statement occurrence;
- one flow-loop interpretation per S3 natural-loop occurrence;
- one memory-access semantic entry per S4 access occurrence;
- one coordinate per S7 materialized-use occurrence.

A typed subpopulation may be narrower than the whole spine. “Dense over S2 scalar-operation
occurrences” is precise; “dense over whatever the producer happened to visit” is not.

### 2.2 Sparse

A sparse facet contains only qualifying facts. Each entry explicitly names its spine occurrence or
ordered occurrence tuple. Presence is semantic; omission cannot silently mean success, failure,
unknown, or default. Later lookup behavior must use typed alternatives.

Examples:

- contracts on the S1 subjects that declare them;
- reductions over the S3 loops that contain one;
- pairwise S4 noalias/dependence evidence;
- selected schedules for S5 kernels;
- `restrict` qualifications for S7 use groups that satisfy exact evidence.

### 2.3 Relations

A relation aligns to the spine whose subject population determines the relation. Other endpoints are
typed cross-spine references. Pairwise relations use ordered/canonical typed pairs and retain exact
proof provenance. No relation is keyed by reconstructed text.

---

## 3. Exact invalidation law

Every facet family declares:

- its producing authority;
- its exact aligned spine allocation;
- its input frontier: every authored fact, derived fact, intrinsic value, request value, and
  capability consumed to derive it.

A facet allocation is valid if and only if:

1. its aligned spine allocation remains the same generation; and
2. every member of its declared input frontier remains the same valid generation/value.

Nothing else invalidates it. A callee-summary change does not invalidate memory alias evidence. A
calling-convention change does not invalidate nominal layout. A coordinate change does not remint S7
use identity. A target change does not invalidate target-independent capture membership.

Borrowed evidence is referenced. Replacing it invalidates only facts whose frontier cites it; it does
not authorize the borrower to recompute or strengthen the evidence.

Cross-generation structural equality never grants validity.

---

## 4. Closed facet set

The model admits 34 conceptual facet families:

| Spine | Facets |
|---|---|
| S1 Semantic program | F01–F13 |
| S2 Monomorphic code | F14–F18 |
| S3 Control topology | F19–F23 |
| S4 Memory object/access | F24–F27, F34 |
| S5 Kernel | F28–F29 |
| S6 Fused computation | F30 |
| S7 Materialized memory use | F31–F33 |
| S8 Physical backend | none; physical meaning is backend-entity content |

F34 was appended after the Step-6 audit exposed the static/storage ownership cycle; the existing
F08–F33 references remain stable. Numbers identify conceptual families, not chronological order.

“None” for S8 is deliberate. Backend construction creates the physical object model. Validation
returns a gate result; serialization returns artifact values. Neither justifies a second semantic
plane over the backend entities.

---

## 5. S1 facets — semantic program

### F01 — Resolution relations

- **Producer:** declaration resolution.
- **Alignment/density:** dense over S1 declarations/bindings requiring namespace occupancy and dense
  over name-reference occurrences requiring a target; relation entries explicitly name both ends.
- **Facts:** namespace occupancy, declaration/binding target, qualification, shadowing relation, and
  resolved-reference provenance.
- **Input frontier:** S1 names, namespace categories, containment, qualifications, and lexical rules.
- **Consumers:** nominal/type meaning, checking, contracts, capture, region concerns, code construction.
- **Excludes:** declaration/binding identity and order (S1); duplicate/missing-name rejection outcomes;
  threaded scope stacks such as `Bind.Env` and `TypeValueScope`.

### F02 — Nominal meaning

- **Producer:** nominal declaration semantics.
- **Alignment/density:** dense over S1 nominal declarations and their typed child subpopulations.
- **Facts:** struct/union/handle/unique semantic category, field/variant membership, payload shape,
  constructor/pattern meaning, semantic discriminant, handle domain/target, and value-product versus
  unique-entity kind.
- **Input frontier:** S1 nominal declarations/children and F01 resolved nominal references.
- **Consumers:** type meaning, checking, ownership, layout, memory, ABI, backend construction.
- **Excludes:** child identity/order (S1) and physical tag/payload storage (F10).

### F03 — Type meaning

- **Producer:** type meaning.
- **Alignment/density:** sparse S1 entries keyed by type-bearing occurrences and canonical structural
  type values used by the generation.
- **Facts:** canonical form, structural/nominal equality meaning, callable semantic shape, legal
  composition, element/pointee/result relations, and type-operation admissibility.
- **Input frontier:** resolved type forms and F02 nominal meaning.
- **Consumers:** checking, scalar meaning, constants, capture, layout, ABI, code, memory.
- **Excludes:** intrinsic behavior that can remain directly on a type leaf and all target/layout facts.

### F04 — Checked meaning

- **Producer:** expression/place/statement checking.
- **Alignment/density:** dense over every S1 expression, place, statement, and binding occurrence that
  requires checked meaning.
- **Facts:** use-site type, expression/place meaning, contextual literal adaptation, assignment/call/
  return/cast/index/field/constructor interpretation, statement sequencing, and omitted-initializer
  zero meaning.
- **Input frontier:** authored occurrence, F01, F02, F03, intrinsic scalar semantics, expected type,
  and exact region/control/ownership capability supplied to the check.
- **Consumers:** control legality, contracts, ownership, regions, capture, code, diagnostics.
- **Excludes:** control-path legality, contract evidence, ownership liveness, and result/rejection lists.

### F05 — Control legality

- **Producer:** control legality.
- **Alignment/density:** dense over the S1 control-site subpopulation: functions, control blocks,
  transfers, switches, continuations, and region-control occurrences.
- **Facts:** termination/path completeness, transfer target and argument meaning, switch default and
  no-fallthrough, continuation protocol, passthrough resolution, entry-parameter flow, and source-
  control admissibility.
- **Input frontier:** S1 control structure, F04 checked meaning, function/block signatures, and region
  protocols.
- **Consumers:** open/sealed region concerns, code construction, diagnostics.
- **Excludes:** CFG edges/loops (S3), statement typing (F04), and old `ControlFactSet` vocabulary.

### F06 — Contract evidence

- **Producer:** contract meaning.
- **Alignment/density:** sparse over S1 checked subjects; pairwise facts use explicit ordered subject
  pairs.
- **Facts:** canonical bounds/window bounds, readonly/writeonly/preserve/invalidate declarations,
  same-length/SoA relations, exact pairwise noalias/disjoint evidence, and contradiction-free checked
  subject provenance.
- **Input frontier:** authored contract forms, F01 subjects, F03 types, and F04 checked places/bindings.
- **Consumers:** ownership, memory contract realization, effects, kernel/fusion admission, coordinate
  qualification, ABI, diagnostics.
- **Excludes:** mapping a subject to an S4 object (F27) and observable effect consequences (F16/F17).

### F07 — Static ownership, access, and erasure

- **Producer:** ownership and access semantics.
- **Alignment/density:** sparse over S1 ownership-bearing bindings, uses, transfers, calls, control
  transitions, handle crossings, and resolver sites.
- **Facts:** owned transfer/discharge, copy/drop/equality legality, lexically provable lease/noescape
  admissibility, Domain resolver/trusted-crossing authority, and sole physical-erasure authorization.
- **Input frontier:** F02 entity/handle kind, F04 checked uses, F05 control, F06 declared contracts, F09
  capture, F10 representation facts required by trusted crossing, and declared call semantics.
- **Consumers:** checking, contracts, closure representation, code construction, memory, ABI, F34
  storage refinement, and backend construction through exact authorization references.
- **Excludes:** any conclusion requiring S4 object/access identity or F16/F17 composed effects, and
  optional “pending” flags. O33/O39 gaps remain missing behavior or typed rejections until implemented.

### F08 — Constant values

- **Producer:** constant evaluation.
- **Alignment/density:** sparse over S1 constant declarations and foldable expression occurrences.
- **Facts:** exact semantic constant value, decoded string-slice length, and provenance to referenced
  constants and scalar semantics.
- **Input frontier:** F04 checked expression, F03 type meaning, intrinsic scalar semantics, and
  referenced F08 entries.
- **Consumers:** checking and code construction.
- **Excludes:** evaluator environments/stacks, target bytes, relocation placement, and trailing-NUL
  policy.

### F09 — Capture relations

- **Producer:** capture discovery.
- **Alignment/density:** sparse S1 relations from nested function/body occurrence to original binding.
- **Facts:** capture membership, role, original-binding provenance, and capture-shape classification.
- **Input frontier:** F01 lexical binding relations and authored/checked nested body occurrences.
- **Consumers:** ownership and closure representation.
- **Excludes:** environment fields, offsets, layout, ABI, and target representation.

### F10 — Target-dependent layout

- **Producer:** target-dependent layout.
- **Alignment/density:** sparse S1 entries keyed by canonical type/nominal occurrence and exact target
  generation.
- **Facts:** size, alignment, field offsets, variant tag/payload storage, handle representation,
  aggregate storage classification, and layout-overflow evidence.
- **Input frontier:** F02, F03, target representation, and layout policy.
- **Consumers:** physical field checking, closure representation, memory, ABI, coordinates, code and
  backend construction.
- **Excludes:** callable passing/linkage (F11), copies embedded in code/backend fact bags, and target-
  independent nominal meaning.

### F11 — Callable ABI and linkage

- **Producer:** callable ABI.
- **Alignment/density:** sparse over S1 function, extern, closure, and sealed-callable occurrences,
  keyed by exact target/convention generation.
- **Facts:** physical parameter/result passing, aggregate calling shape, calling convention, linkage,
  visibility, semantic-callable-to-symbol projection, and requested callable conformance.
- **Input frontier:** F03 callable shape, F07 erasure authorization, F10 layout, target/convention, and
  linkage declaration.
- **Consumers:** sealed-call feasibility, closure representation, code/backend construction, C
  validation, GCC symbol requests.
- **Excludes:** ownership erasure decisions and backend entity identity.

### F12 — Closure representation

- **Producer:** closure representation.
- **Alignment/density:** sparse over the derived S1 allocation's closure/environment/helper occurrences,
  with references to original F09 captures.
- **Facts:** environment field assignment/order meaning, captured-access rewrite, environment
  representation, and closure callable representation.
- **Input frontier:** F09 capture, F07 ownership/noescape, F10 layout, F11 ABI, and target.
- **Consumers:** code and backend construction.
- **Excludes:** capture discovery and generated occurrence identity/order, which belong to S1.

### F13 — Sealed region boundary meaning

- **Producer:** sealed-region call semantics.
- **Alignment/density:** sparse over S1 seals, sealed invocations, and generated callable/result/frame
  occurrences.
- **Facts:** materialize-once meaning, semantic frame arguments, result alternatives, callee-exit
  meaning, and caller continuation routing.
- **Input frontier:** checked seal/body/protocol, invocation/wiring, caller state, F05, and F11 ABI
  feasibility.
- **Consumers:** post-expansion checking, code construction, ABI and backend.
- **Excludes:** generated identity/order/origin (derived S1), expansion state, and speculative bundles.

---

## 6. S2 facets — monomorphic code

### F14 — Scalar-operation attribution

- **Producer:** scalar and machine-operation meaning.
- **Alignment/density:** dense over S2 scalar, pointer, cast, comparison, atomic, and memory-operation
  occurrences.
- **Facts:** exact integer overflow/division/shift semantics, float mode, cast/pointer rules, trap
  contract, atomic ordering, volatility, and operation result semantics.
- **Input frontier:** S2 operation/type, F03 type meaning, and authored declared scalar contracts.
- **Consumers:** flow/value/memory analysis, kernel recognition, and backend construction.
- **Excludes:** backend emitter choice and copied default-policy tables owned by code construction.

### F15 — Code-value algebra

- **Producer:** value and algebra semantics.
- **Alignment/density:** sparse over S2 value-definition occurrences.
- **Facts:** copy canonicalization, constant/affine/range expressions, no-wrap and floating evidence,
  and algebraic proofs not specific to one loop.
- **Input frontier:** S2 definitions, S3 def/use provenance, F14, and referenced F19/F20 flow evidence.
- **Consumers:** memory, kernel, fused projection, coordinate/fragment realization, strategy.
- **Excludes:** storage aliasing, trip evidence, loop reduction identity, and string-keyed lookup copies.

### F16 — Operation effects

- **Producer:** effect semantics.
- **Alignment/density:** dense over S2 instruction, terminator, call-site, and extern-operation
  occurrences; a pure/no-observable-effect leaf is still an entry.
- **Facts:** reads, writes, preserve/invalidate, retain/noescape, trap, volatility, atomicity, calls,
  allocation/external behavior, and exact S4 object/access references.
- **Input frontier:** S2 operation, F06 contracts, F25/F27 memory subject mapping/safety, and declared
  callee/extern effects where local interpretation requires them.
- **Consumers:** F34 storage-refined ownership, kernel, scheduling/fusion admission, strategy, and
  backend qualifiers.
- **Excludes:** memory alias/bounds decisions and function-level composition.

### F17 — Callable effect summaries

- **Producer:** effect semantics.
- **Alignment/density:** dense over S2 function/extern/callable occurrences.
- **Facts:** composed callable effect classification and precise read/write/trap/retain/external summary.
- **Input frontier:** F16 operation effects, call graph relations from S2/S3, callee F17 summaries, and
  extern declarations.
- **Consumers:** F34 storage-refined ownership, call checking where required, kernel, schedule/fusion,
  and strategy.
- **Excludes:** per-operation facts. A callee-summary change never invalidates F24–F27 memory facts.

### F18 — Baseline realization

- **Producer:** lowering-strategy commitment.
- **Alignment/density:** dense over S2 function occurrences.
- **Facts:** existence of a legal baseline realization, complete baseline coverage, and the preservation
  requirement that any optional replacement must satisfy.
- **Input frontier:** accepted S2/S3 structure and backend baseline capabilities.
- **Consumers:** optimization commitment/fallback, realization coordination, backend construction, and
  diagnostics.
- **Excludes:** optimization choice per loop/subject (F22), selected fragments, final assembly, fragment
  feasibility, and backend entities.

---

## 7. S3 facets — control topology

### F19 — Loop flow meaning

- **Producer:** flow and induction semantics.
- **Alignment/density:** dense over S3 natural-loop occurrences.
- **Facts:** counted/uncounted interpretation, primary counter reference, direction, start/stop/step,
  inclusive/exclusive convention, domain shape/intent, exits, induction range summary, and sole trip
  evidence.
- **Input frontier:** exact S3 loop/edge/definition structure, S2 definitions/constants, F14 scalar
  meaning, and authored loop-domain provenance through S1/S2.
- **Consumers:** value algebra, memory, kernel, schedule, fused projection, coordinates, strategy.
- **Excludes:** copied body-block lists, optional counted fields, value-owned closed forms, and kernel/
  fused trip copies.

### F20 — Induction relations

- **Producer:** flow and induction semantics.
- **Alignment/density:** sparse S3 relations from loop occurrences to S2 values/parameters participating
  as induction/recurrence values.
- **Facts:** recurrence role, init/step relation, direction, range, edge-transfer provenance, and link to
  the owning F19 loop meaning.
- **Input frontier:** S3 edge-argument/parameter wiring and definitions, S2 scalar definitions, F14.
- **Consumers:** value algebra, memory index classification, kernel counter selection, coordinates.
- **Excludes:** structural edge wiring (S3) and independently reimplemented copy-alias fixpoints.

### F21 — Loop algebra

- **Producer:** value and algebra semantics.
- **Alignment/density:** sparse over S3 loop occurrences and explicit loop/value tuples.
- **Facts:** reductions, recurrence algebra, closed forms, associative/ordering evidence, and affine
  loop expressions.
- **Input frontier:** F19/F20, F15 value expressions, F14 scalar meaning, and S3 def/use.
- **Consumers:** kernel recognition, fused result shape, lowering strategy and closed-form realization.
- **Excludes:** trip/domain ownership; proofs reference F19 instead of retyping trips.

### F22 — Optimization commitment

- **Producer:** lowering-strategy commitment.
- **Alignment/density:** sparse over S3 loop/control subjects considered for replacement.
- **Facts:** final baseline/closed-form/fused commitment, intended covered subject, proof references,
  rejected-alternative history, fallback reason, and selected fragment reference.
- **Input frontier:** S3 subject, F18 baseline, F21, F28/F29/F30, F31–F33, backend capabilities,
  and typed fragment feasibility outcomes.
- **Consumers:** function realization/assembly, backend construction, diagnostics/remarks.
- **Excludes:** attempt sequencing, coordinate/fragment decisions, and coverage feasibility.

### F23 — Dominance

- **Producer:** fragment materialization and assembly.
- **Alignment/density:** sparse explicit S3 block-pair relations, grouped by S2 function provenance.
- **Facts:** dominance needed for replacement entry, value availability, incoming argument, and adapter
  feasibility.
- **Input frontier:** exact S2 function and S3 edge/definition topology.
- **Consumers:** repeated fragment attempts, entry/value/exit adapter construction, final assembly.
- **Excludes:** CFG topology itself, strategy intent, and fragment feasibility verdicts.

---

## 8. S4 facets — memory objects and accesses

### F24 — Memory-object semantics

- **Producer:** memory-object and access semantics.
- **Alignment/density:** dense over S4 object/subobject occurrences.
- **Facts:** storage kind, element/type interpretation, extent, stride, layout provenance, and semantic
  storage-root properties not already structural lineage.
- **Input frontier:** S4 root/lineage, S2 storage definitions, F03, F10, F07 static storage authority, and
  relevant F19/F20/F15 premises.
- **Consumers:** F25/F26, effects, kernel lanes, fused projection, coordinates, backend.
- **Excludes:** object identity/root-parent topology (S4) and observable effect conclusions.

### F25 — Memory-access semantics

- **Producer:** memory-object and access semantics.
- **Alignment/density:** dense over S4 access occurrences.
- **Facts:** access mode, selected index interpretation, extent/stride use, bounds, alignment with
  provenance, trap status, dereference width, and movement legality.
- **Input frontier:** S4 access anchor/object relation, F24, F19/F20, F15, F06/F27 contracts, F10 layout,
  and F07 static ownership authority.
- **Consumers:** effects, kernel/fused admission, coordinates, fragment/backend realization.
- **Excludes:** access identity/order (S4), pairwise relations (F26), and duplicated backend-info records.

### F26 — Memory relations and proofs

- **Producer:** memory-object and access semantics.
- **Alignment/density:** sparse explicit S4 object/access pairs and S3-loop provenance for dependence.
- **Facts:** same-store, subobject overlap interpretation, alias/may-alias/noalias/disjoint, dependence,
  loop-carried dependence, and exact proof provenance.
- **Input frontier:** S4 lineage/access population, F24/F25, F19/F20, F06/F27 exact pair evidence, and
  layout/ownership premises used by the proof.
- **Consumers:** F34 storage refinement, effects, kernel/fusion admission, scheduling, qualification.
- **Excludes:** inferred `restrict`, observable read/write effects, and duplicate alias vocabulary.

### F27 — Contract realization

- **Producer:** memory-object and access semantics.
- **Alignment/density:** sparse over S4 objects/accesses with typed references back to F06 S1 subjects
  and subject pairs.
- **Facts:** canonical contract-subject-to-object/access relation and the exact contract evidence
  applicable to that storage occurrence.
- **Input frontier:** F06, S1→S2 provenance, S4 root/access structure, and F24 object interpretation.
- **Consumers:** F25/F26, effects, kernel/fusion admission, F33 qualification, F34 storage refinement,
  and diagnostics.
- **Excludes:** reinterpreting contract syntax and deriving readonly/writeonly/invalidate effects.

### F34 — Storage-refined ownership

- **Producer:** ownership and access semantics.
- **Alignment/density:** sparse over S4 objects/accesses and explicit S1 use/call/control references
  whose ownership verdict requires storage identity or composed observable effects.
- **Facts:** storage-mapped lease origin/liveness/escape, retaining-call/noescape consequences,
  invalidation conflicts, use-after-storage-invalidation, and storage-specific discharge evidence.
- **Input frontier:** F07 static authority, S4 provenance, F24–F27 memory facts, F16/F17 effects, and
  referenced S1/S2/S3 call/control occurrences.
- **Consumers:** final ownership acceptance, backend safety realization, and diagnostics.
- **Excludes:** re-deciding static copy/transfer/erasure authority, memory alias/bounds truth, effect
  summaries, or nullable pending-state flags.

---

## 9. S5 facets — kernels and schedules

### F28 — Kernel meaning

- **Producer:** kernel recognition.
- **Alignment/density:** dense over accepted S5 kernels and their lane/binding/result subpopulations.
- **Facts:** recognized computation kind, counter/domain reference, lane roles, binding expressions,
  semantic result shape/protocol, equivalence requirement, and typed references to F14/F15/F19/F21/
  F24–F26/F16–F17 evidence.
- **Input frontier:** S3 candidate, F14/F15, F19–F21, F24–F27, F16/F17, and exact proof premises.
- **Consumers:** schedule selection, fused projection, strategy, diagnostics.
- **Excludes:** copied trips/reductions/memory/effects, kernel/lane/binding identity/order (S5), and
  rejected-candidate result values.

### F29 — Selected schedule

- **Producer:** schedule selection.
- **Alignment/density:** sparse over S5 kernels for which a schedule is selected.
- **Facts:** form, tail, policy/profit decision, target-capability reference, emitter-capability
  reference, proof references, and rejected-alternative history retained with the selected decision.
- **Input frontier:** F28, F25/F26, F16/F17, compiler policy, intrinsic target capabilities, and
  C-emitter-declared capabilities.
- **Consumers:** fused projection and lowering strategy.
- **Excludes:** target copies, locally manufactured emitter support, candidate cursors, and module wrappers.

---

## 10. S6 facet — fused computation

### F30 — Fused meaning and guarantee provenance

- **Producer:** fused computation projection.
- **Alignment/density:** dense over an accepted S6 computation and its axis/producer/stream/access/sink/
  result subpopulations.
- **Facts:** semantic iteration reference, producer/operator meaning, stream operation, access role/
  layout meaning, sink operation, result protocol meaning, schedule relation, and declared guarantee
  provenance.
- **Input frontier:** F28, F29, F19/F21, F24–F27, F16/F17, and fusion policy.
- **Consumers:** materialized-use creation, coordinates, fragment attempts, strategy diagnostics.
- **Excludes:** S6 child identity/topology/order, rederived trips/domains, coordinate decisions, and
  fusion-rejection result values.

---

## 11. S7 facets — physical memory uses

### F31 — Materialized-use meaning

- **Producer:** memory-coordinate materialization.
- **Alignment/density:** dense over S7 materialized-use occurrences.
- **Facts:** load/store/sink role, selected semantic index/window relation, access/stream/sink meaning,
  and exact typed references to S6/F25 evidence.
- **Input frontier:** S7 provenance, F30 fused meaning, and referenced F25 access semantics.
- **Consumers:** coordinate derivation, qualification, fragment materialization, diagnostics.
- **Excludes:** use identity/order/ordinal/grouping (S7) and coordinates.

### F32 — Use coordinates

- **Producer:** memory-coordinate materialization.
- **Alignment/density:** dense, exactly one coordinate entry per S7 use.
- **Facts:** absolute/iteration-affine/window-relative/window-dynamic coordinate, basis, displacement,
  scale, window relation, and provenance to exact induction/memory/layout premises.
- **Input frontier:** S7, F31, F19/F20, F24/F25, F10, F29 schedule, and target representation.
- **Consumers:** address-plan construction, fragment feasibility/materialization, diagnostics.
- **Excludes:** copied iteration records, final C locals, cursors, address-plan state, and S8 addresses.

### F33 — Pointer qualification

- **Producer:** memory-coordinate materialization.
- **Alignment/density:** sparse over S7 use/base groups for which a physical pointer qualification is
  requested and provable.
- **Facts:** `restrict` or other pointer qualification with exact declaration/proof provenance.
- **Input frontier:** S7 grouping, F31, F06 exact declared pairwise noalias, F26 entries preserving that
  exact declared provenance, F27 mapping, and target C representation rules.
- **Consumers:** fragment materialization and backend pointer realization.
- **Excludes:** inferred noalias, movement reclassification, and coordinate facts.

---

## 12. Why S8 has no facet

Backend-unit construction creates S8 and the physical backend entities themselves. Their physical
operation payloads, storage, initializer bytes, relocation placement, helper bodies, callable
signature references, and linkage realization are persistent entity content owned by backend
construction—not a derived plane over an independently meaningful backend object.

C validation produces an accepted/rejected gate. C serialization produces deterministic source and
header artifact values. AOT and GCC consume the validated S8 object and artifacts. Creating a
“backend facet” or “C-conformance facet” would wrap the backend entity model or retain an operation
result as a parallel semantic authority.

ABI-owned symbol/signature facts remain F11 and are referenced by S8. S8 owns physical entity
addressability and typed provenance, not ABI policy.

---

## 13. Explicit non-facets

| Candidate | Verdict |
|---|---|
| Authored program content | owning S1 entity/program state, not a derived facet |
| Staged synthesis result | operation result; accepted declarations enter S1 |
| Open-region expansion | creates derived S1; environments/splices are operation state/results |
| Monomorphic code construction | creates S2 and code entity content |
| Code structural certification | gate result over S2, not a reusable semantic plane |
| Control topology | S3 spine content |
| Kernel/fusion rejection | typed operation result; strategy may retain its provenance |
| Address plan/cursors | encoded realization record with one fragment consumer |
| Fragment | direct entity with local content and typed S2/S3/S6/S7 provenance |
| Fragment feasibility | entity-local/result; only F23 dominance is separately reusable |
| Backend physical payload | S8 entity content |
| C validation report | gate result |
| C source/header | artifact values |
| Target/emitter capabilities | intrinsic/request values, never a target facet |
| GCC artifact/session/symbol | host artifacts/resources with liveness |
| Diagnostics | concern-local result leaves plus cross-cutting law |
| Determinism/provenance/optimization equivalence | laws, not facets |

---

## 14. Cross-spine evidence law

Every consuming facet names one primary spine. Cross-spine facts are referenced as evidence:

- F12/F13 preserve original S1 occurrence provenance in a derived S1 allocation;
- F15 references S3 flow evidence without becoming S3-aligned;
- F16/F17 reference S4 objects/accesses without owning memory truth;
- F20/F21 reference S2 values while aligning to S3 loops;
- F22 references S5/S6/S7/direct fragments while aligning to S3 subjects;
- F24–F27 and F34 reference S1 contracts/types and S2/S3 causes while aligning to S4;
- F28 references S2/S3/S4 evidence while aligning to S5;
- F30 references S3/S4/S5 facts while aligning to S6;
- F31–F33 reference S4/S6 facts while aligning to S7;
- S8 references F07/F34/F10/F11/F14/F16/F18/F22/direct fragments without copying their decisions.

A consumer may project a narrow view from an authoritative facet. It may not publish a second stored
copy such as kernel trips, stencil domains, memory backend-info mirrors, code-layout copies, or
backend alias classifications.

---

## 15. Current bag disposition

| Current vocabulary | Closed disposition |
|---|---|
| `TypeModuleFacts` | decompose into F02/F05 and exact region/nominal inputs; remove empty handles/effects and the wrapper |
| `LayoutEnv` copies | one F10 generation keyed by target; all consumers reference it |
| `CodeResult`/tree-code module fact bags | S2 plus narrow references; do not copy layout/contracts |
| `CodeContractFactSet` | delete as a re-encoded authority; F27 maps F06 subjects through typed S1→S2 provenance |
| `CodeTypeDecl` embedded layout copies | physical consumers reference F10; code retains semantic type/provenance only |
| `Bind.Residence*` / code/backend residence triplication | delete as competing facts; ownership authorizes, code states semantic storage need, S8 realizes |
| `CodeGraph` wrappers | decompose into S3; no topology facet |
| `FlowFactSet` + `FlowSemanticFactSet` | F19/F20; one O15 trip authority, no second trip pass |
| `ValueFactSet`/string projection | F15/F21; typed spine references, no rebuilt text index |
| `MemTransferFacet` | operation-local accumulation protocol; does not survive |
| `MemSemanticFactSet` | S4 + F24–F27; move effects to F16/F17 and storage ownership refinement to F34 |
| `EffectFactSet` | F16/F17; no direct reinterpretation of authored contracts |
| `KernelModulePlan`/request bags | S5 + F28; reference authoritative evidence instead of wrapping four analyses |
| `KernelTripProjection` | delete; F28 references F19 |
| `ScheduleModulePlan` | F29 entries; target/capabilities remain values |
| `StencilComputation` | S6 + F30; remove copied iteration/domain/trip and mixed legality/result state |
| `CMatMemoryUseSpine` | S7 only; move role/index to F31 |
| `LowerCMatCoordinateFacet` | F32 exemplar after removing copied iteration payload |
| `CMatCAddressPlan`/cursor state | one-consumer boundary record, not a facet; it cannot mint S8 locals |
| `LowerModule`/`LowerBackSpine` | delete context/world bags |
| `LowerFragment` mixed plan | F18 baseline + F22 optimization facts + direct fragment + typed issues/results |
| `LowerDominanceProjection` | F23, built once per exact S2/S3 generation and reused |
| `CBackendUnit` | S8 physical object model, not a facet bag |
| `CEmitMachine` | remove spine/context retention; C realization consumes exact validated S8 |
| `CBackendAnnotationSpine`, `LalinPhase`, `LalinExec` | no admitted fact family; delete rather than adapt |

Dead `MemAliasFact`, `MemLeaseGrant`, `MemAccessInterval`, `MemAccessSafetyFact`, `MemBaseId`,
`MemScopeId`, `MemProofId`, `MemLeaseId`, unused flow ranges, dead ABI plans, standalone stencil
descriptor/artifact vocabulary, and the duplicate GCC runner receive no facet home.

---

## 16. Obligation coverage

| Obligations | Facet disposition |
|---|---|
| O01 | S1 creation; no facet |
| O02 | authorship convergence law over S1; no facet |
| O03 | F01 |
| O04 | F02/F03 |
| O05 | F04 |
| O06 | F09 |
| O07 | F05 |
| O08 | F06 |
| O09 | derived S1; no facet |
| O10 | derived S1 + F13 |
| O11 | coordinator; no facet |
| O12 | S2 creation; no facet |
| O13 | gate result; no facet |
| O14 | S3 creation; no facet |
| O15 | F19/F20 |
| O16 | F15/F21 |
| O17 | S4 + F24–F27 |
| O18 | F16/F17 |
| O19 | S5 + F28 |
| O20 | F29 |
| O21 | S6 + F30 |
| O22 | S7 + F31–F33; address plan is a boundary record |
| O23 | F23 + direct fragment entities/results |
| O24 | S8 physical entities; no facet |
| O25 | gate/artifact values; no facet |
| O26 | host boundary; no facet |
| O27 | diagnostic law and concern-local results |
| O28 | intrinsic/request values; no facet |
| O29 | F08 |
| O30 | F02 |
| O31 | F11 |
| O32 | intrinsic leaf meaning + F14 |
| O33 | F07 static authority + F34 storage refinement |
| O34 | F18/F22 |
| O35 | determinism/isolation law |
| O36 | synthesis result enters S1; no facet |
| O37 | F10 |
| O38 | F12 |
| O39 | F07 consuming F02/F10; storage-specific consequences enter F34 |
| O40 | F02 entity kind + F07 static legality + F34 storage refinement + S4 allocation identity; no unique-specific facet |

All forty obligations have a facet, spine/entity, result/artifact, value, host-resource, coordinator,
or law disposition. None remains in a generic facts bag.

---

## 17. Required proof obligations before cutover

The facet model adds these focused regression requirements to the earlier obligation/identity list:

1. dense F04 covers every authored expression/place/statement occurrence exactly once;
2. dense F05 covers every accepted control site exactly once;
3. one target-keyed F10 generation is consumed consistently by checking, code, memory, ABI, and
   backend construction;
4. F19 is the only trip producer; kernel/fused/coordinate paths preserve the same typed reference;
5. F16/F17 are the only producers of observable contract consequences;
6. F24/F25 dense counts equal the exact S4 object/access populations;
7. F26 exact pairwise noalias is the only evidence capable of supporting F33 `restrict`;
8. F28 references rather than copies F14/F15/F19–F21/F24–F27/F16/F17 evidence;
9. F32 has exactly one entry per S7 use and rejects missing/duplicate/ambiguous alignment;
10. F23 dominance is derived once per exact topology generation and reused by all fragment attempts;
11. failed optional coordinate/fragment realization returns to F22 strategy before F18 final coverage;
12. no S8 local/label identity is minted by an address cursor or fragment plan;
13. no emitted/backend name is parsed to recover any facet alignment;
14. a captured closure executes through GCC and proves F09/F12/F11 separation;
15. authored loop code derives S3/F19/F20 without hand-built topology fixtures;
16. F07 can authorize code/memory construction without S4, while F34 alone owns storage-refined
    O33 consequences; neither uses nullable pending fields.

Tests pinning old bag constructors or positional empty lists are schema-shape evidence only and must
not force those bags into the replacement model.

---

## 18. Step 5 closure proof

Step 5 is closed because:

- every persistent derived fact family has one producer and one primary spine;
- the admitted set contains 34 facets across S1–S7 and no universal analysis/backend facet;
- dense and sparse populations are explicit;
- every facet states its exact input frontier and consumers;
- independent invalidation splits static/storage ownership, layout/ABI, checking/control/contracts,
  flow/value, operation/function effects, memory objects/accesses/relations/contracts, baseline/
  optimization, and use meaning/coordinates/qualification;
  use meaning/coordinates/qualification;
- topology, identity, order, and origin remain solely in S1–S8;
- trip, contract-effect, memory, layout, scalar, and capability authority are not duplicated;
- open expansion, validation, fragments, address plans, backend entities, artifacts, target values,
  diagnostics, and sessions have explicit no-facet classifications;
- all current fact bags have decompose/delete/entity/result dispositions rather than renamed wrappers;
- O01–O40 coverage is complete;
- no ASDL fields, worlds, machines, requests, result sums, implementation, migration, or compatibility
  layer has been defined.

## Step 6 world result

`docs/COMPILER_WORLD_MODEL.md` admits zero compiler worlds. S1–S8 and F01–F34 already provide direct
immutable publication with exact generation/provenance; every proposed world is either a thin wrapper
or an independently-invalidated context bag.
