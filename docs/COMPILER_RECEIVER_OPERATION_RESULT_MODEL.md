# Compiler Receiver, Operation, and Result Model

Status: Step 7 closed for the ground-up Lua-ASDL compiler model.
Prerequisites:

- `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`
- `docs/COMPILER_ENTITY_IDENTITY_MODEL.md`
- `docs/COMPILER_CONCERN_AUTHORITY_MODEL.md`
- `docs/COMPILER_SPINE_MODEL.md`
- `docs/COMPILER_FACET_MODEL.md`
- `docs/COMPILER_WORLD_MODEL.md`

This document assigns each of the thirty-two compiler authorities and the GCC/session boundary one
distinguished semantic receiver family, its publication/decision operations, narrow typed input
frontiers, outcome classes, and continuation ownership. It is a conceptual ASDL model: names identify
required type families, but fields, constructor order, files, implementation, migration, and
compatibility are deliberately deferred.

The closed result is:

- thirty-two compiler receiver families plus one host-boundary receiver family;
- zero generic compiler machines, mutable compiler frames, worlds, or phase receivers;
- concrete subject/request leaves as case owners;
- authority-specific result sums only where control alternatives exist;
- direct products for total projections;
- concern-local typed rejection reasons and leaf-owned continuations.

---

## 1. Receiver admission

A distinguished receiver family is admitted only when:

1. it is the intrinsic semantic subject, a narrow request for a genuinely relational decision, an
   immutable transition subject, or a result leaf continuing an operation;
2. its methods collectively own exactly one concern authority;
3. concrete union leaves own semantic cases;
4. removing it would force free-function dispatch, a context bag, or hidden coordination;
5. it is not named merely after a phase or concern.

A receiver **family** may be a sum whose leaves have different exact frontiers. This is how one
authority owns several independently invalidated operations without creating several authorities or
one optional-soup request.

Rejected receiver shapes include:

- empty `FooMachine` products;
- `ModuleSurface`, `ModuleTyped`, `ModuleSem`, and similar chronological headers;
- a universal `Compiler` receiver;
- an analysis, lowering, or backend world disguised as a request;
- a result leaf whose only method returns a tag for external dispatch.

### 1.1 Intrinsic subject receiver

Use an intrinsic entity/value/union leaf when the operation interprets that subject's invariants:
type forms, operator leaves, expressions, control sites, contract forms, S1/S2/S3 allocations,
callables, and artifacts.

### 1.2 Request-owned receiver

Use a request product or request sum when the decision is a relation among several peer values and
no peer honestly owns the whole operation. Every request leaf has one exact frontier. Request sums
are used for flow, algebra, ownership, memory, effects, coordinates, strategy, and fragment realization.
A32 uses the intrinsic `GnuCEmitter` leaf plus S8 entity leaf methods; A33 is a host-boundary leaf
family.

### 1.3 Explicit authority receiver

No compiler concern requires a mutable or retained authority product. The concrete C-emitter leaf is
an intrinsic capability authority, not an empty machine. The loaded session is a real host resource
outside pure compiler semantics.

---

## 2. Input law

Every semantic method has either no extra input or one named ASDL input value.

An input value contains only facts not already intrinsic to the receiver and exactly those facts in
the operation's invalidation frontier. It may contain typed references to several spines/facets; that
does not permit copying them into a bag.

Forbidden inputs:

- `ctx`, `env`, `state`, option bags, loose tables, or positional tuples;
- maps or side tables keyed by nodes, names, IDs, or classes;
- copied spine/facet populations;
- target, policy, layout, or evidence fields not consumed by that exact request leaf;
- nullable fields selecting which operation the request means.

When two operations of one authority have different frontiers, they receive different request leaves.
They do not share a superset request.

---

## 3. Result and continuation law

### 3.1 Six distinct outcome classes

1. **Publication:** a spine, facet, entity, gate, artifact, intrinsic value, boundary value, or host
   resource becomes available.
2. **Conservative outcome:** typed weakening evidence either publishes a dense/sparse conservative entry
   or explicitly creates no sparse entry. It continues compilation and never means rejection.
3. **Immediate decision continuation:** a transient typed result chooses the next exact request without
   pretending to be a persistent fact. Strategy attempts and identity-preserving unchanged decisions live
   here.
4. **Terminal semantic rejection:** an authority-specific typed reason ends the semantic transaction.
5. **Optional realization outcome:** no-plan, unavailable, or unrealizable evidence returns to lowering
   strategy and preserves a correct baseline.
6. **Host failure:** GCC/filesystem/loader/FFI/resource failure. It is never a compiler rejection.

These classes must not share a generic `Success/Failure` union.

### 3.2 When a result sum exists

Use a named authority-specific result sum when the caller acts differently on immediate outcomes.
Each publication, conservative, immediate-decision, rejection, optional-realization, or host-failure
alternative is a concrete leaf.
A provably total projection, such as S3 topology after O13, returns its product directly.

A result leaf carries only its authority's product or exact typed reason/provenance. Success leaves
never carry trailing issue lists. Optional candidate history belongs in F29/F22 decisions, not in a
generic result wrapper.

### 3.3 Leaf-owned continuation

Every immediate result leaf owns its transaction continuation:

- semantic success publishes its value and constructs/invokes the next exact request;
- a conservative outcome publishes its typed weakening entry or records a typed no-entry outcome, then
  continues without strengthening;
- an immediate decision continuation constructs exactly the request named by its concrete leaf;
- terminal semantic rejection preserves the typed cause and stops the transaction;
- optional no-plan/unrealizable leaves return to lowering strategy;
- host failures route to the Host API as host errors.

Coordinators invoke these methods. They do not inspect class, `kind`, tags, reason strings, or booleans.
A persistent publication may have several later consumers; its immediate result leaf continues to the
sequencing coordinator, which constructs those consumers' exact requests without semantic branching.

### 3.4 Rejection is the diagnostic

Every rejection reason leaf names its typed subject, origin, exact domain reason, and typed nested
cause when propagating another authority's rejection. Rendering is behavior on the reason leaf.
Transaction aggregation may preserve ordered rejection values but may not flatten them into strings,
counts, or one generic diagnostics bag.

Generation/provenance mismatch is never a generic fallback. The consuming authority returns its own
typed coherence rejection naming the expected and actual allocations; it does not reinterpret the
upstream facts or turn the mismatch into an optional no-plan.

---

## 4. Closed receiver ledger — authored and checked semantics

`A01`–`A17` correspond to authorities 1–17 in the concern model.

| ID | Distinguished receiver family | Publication/decision operation | Exact additional frontier | Exhaustive immediate outcomes | Produces |
|---|---|---|---|---|---|
| A01 | `ProgramInput` leaves: document, builder declarations, generated-declaration admission | `materialize_authored` | source/generated origin, LLBL delivery, canonical Lalin role adaptation | one new S1 allocation for the exact input/admission; lexical/syntax delivery failure; illegal root; malformed declaration/body; invalid builder/host value; splice rejection | S1; never mutates a prior allocation |
| A02 | concrete `MetaPropertyQuery` leaves | `synthesize` | declared hook, schema value, staged Lua capability, recursion bound, requested role | generated declarations; unknown hook; role mismatch; unsupported result; recursion rejection; dynamic-fallback rejection | generated declaration values and causal origin, not S1 identity |
| A03 | S1 semantic-program allocation | `resolve_namespaces` | lexical/qualification rules | F01 published; duplicate/conflict; missing name; wrong namespace; bad qualification/shadowing/category | F01 |
| A04 | concrete nominal declaration/child leaves | `establish_nominal_meaning` | F01 nominal references | F02 published; duplicate child; invalid recursion/category/payload/handle target/unique authority | F02 |
| A05 | concrete type-form leaves | `establish_type_meaning` | F01/F02 references and legal composition | F03 published; unknown/recursive/extent/composition/equality/operation rejection | F03 and canonical structural values |
| A06 | intrinsic scalar/pointer/cast/atomic/operator leaves; separate `CodeOperationAttributionRequest` | `interpret_intrinsic`; `attribute_code_operation` | intrinsic: exact operand types/contracts; attribution: one accepted S2 operation + intrinsic meaning | intrinsic meaning or typed semantic rejection; F14 publication or code/meaning incoherence rejection | intrinsic operation values and F14 |
| A07 | `CheckRequest` leaves for expression, place, and statement subjects | `check` | F01–F03, expected type where required, exact control/ownership/region capability | checked F04 entry; concern-specific type/place/call/return/cast/index/nominal rejection; propagated cause | F04 |
| A08 | concrete control-bearing body/site leaves | `prove_control_legality` | F04, function/block signatures, region protocol/capability | F05 entry; termination/target/default/fallthrough/transfer/passthrough/source-control rejection | F05 |
| A09 | concrete contract-form leaves | `canonicalize_contract` | F01 subjects, F03 types, F04 checked places/bindings | F06 entry; malformed/non-memory/missing/bounds/contradiction/unsupported rejection | F06 |
| A10 | `OwnershipRequest` sum: static occurrence request or storage-refinement request | `derive_static_ownership`; `refine_storage_ownership` | static: F02/F04/F05/F06/F09/F10 and declared calls; storage: F07 + S4/F24–F27/F16/F17 and S1–S3 references | F07 or concern rejection; F34 or storage-specific rejection | F07 and F34 |
| A11 | checked constant-expression leaves | `evaluate_constant` | F03/F04, scalar meaning, referenced constants | F08 value; nonconstant/cycle/unavailable-operation/unresolved/host-value/arithmetic rejection | F08 |
| A12 | nested callable/body occurrence | `discover_captures` | F01 lexical binding relation and checked nested body | F09 relation; unresolved/escape/shape rejection | F09 |
| A13 | `LayoutRequest` for one canonical type/nominal and target generation | `project_layout` | F02/F03, target representation, layout policy | F10 entry; recursion/representation/alignment/target/classification/overflow rejection | F10 |
| A14 | `CallableAbiRequest` for one callable occurrence | `project_callable_abi` | F03/F07/F10, target convention, linkage/visibility | F11 entry; parameter/result/convention/redeclaration/collision/symbol/visibility/target rejection | F11 |
| A15 | `ClosureRepresentationRequest` leaves: captured representation or no-capture unchanged decision | `represent_closure`; `preserve_uncaptured_callable` | captured: F09/F07/F10/F11 and target; unchanged: exact empty F09 relation | represented derived S1+F12; typed unchanged continuation; environment/escape/storage/shape/target-ABI rejection | derived S1 and F12 only for represented closures |
| A16 | open-region invocation leaf | `expand_open_region` | checked definition/protocol, wiring, typed environment, caller captures, target parameters, generation | derived S1; definition/argument/continuation/capture/identity/body rejection | derived S1 |
| A17 | `SealedRegionRequest` leaves for seal materialization and invocation routing | `materialize_seal`; `route_sealed_call` | materialize: checked seal/body/protocol + F05/F11; route: materialized seal + invocation/wiring/caller state | derived seal/call S1+F13; missing seal; argument/protocol/continuation/frame/recursion/delegated-ABI rejection | derived S1 and F13 |

### 4.1 Frontend case ownership

A01 input leaves own surface adaptation. A04 nominal leaves, A05 type leaves, A06 operator leaves, A07
expression/place/statement leaves, A08 control leaves, and A09 contract leaves own their cases. Parent
methods may share defaults but never select child behavior.

A10 is one authority with two request leaves because F07 and F34 have different primary spines and
frontiers. F07 never reads S4/F16/F17. F34 cannot re-decide static copy/transfer/erasure authority.

A16 and A17 remain separate receiver families and result sums: open `emit` splices caller CFG; sealed
`call` creates a callable/frame/result boundary. Neither uses RegionBundle or encoded-name recovery.

---

## 5. Closed receiver ledger — code and semantic analysis

| ID | Distinguished receiver family | Publication/decision operation | Exact additional frontier | Exhaustive immediate outcomes | Produces |
|---|---|---|---|---|---|
| A18 | accepted expanded S1 allocation | `construct_monomorphic_code` | F06–F08/F10–F13 and exact target-neutral representation references | S2 constructed; unsupported construct/missing representation/initializer/relocation/unbound value/body/code-type rejection | S2 |
| A19 | constructed S2 allocation | `validate_code_structure` | S2's exact typed relations only | accepted-code gate; typed duplicate/reference/signature/definition/transfer/memory/initializer/relocation/termination rejection | O13 gate |
| A20 | accepted-code result leaf | `derive_control_topology` | none | direct total S3 publication; no reject alternative | S3 |
| A21 | `FlowRequest` sum: loop-meaning request or induction-relation request | `derive_loop_meaning`; `derive_induction_relations` | loop: S3 loop/edges + S2 definitions/constants + F14 + S1 provenance; induction: S3 wiring + S2 definitions + F14 + owning F19 | F19 counted/uncounted meaning; F20 relation publication or typed relation-unavailable outcome; typed generation/provenance rejection | F19 and F20 |
| A22 | `AlgebraRequest` sum: code-value or loop-algebra request | `derive_value_algebra`; `derive_loop_algebra` | value: S2 definition + S3 def/use + F14/F19/F20; loop: S3 tuple + F15/F14/F19/F20 | derived entry or typed unavailable evidence; scalar/provenance incoherence rejection only | F15 and F21 |
| A23 | `MemorySemanticsRequest` sum with spine, object, contract, access, and relation leaves | operations in §5.1 | exact frontier per leaf in §5.1 | structural S4 publication or rejection; dense/sparse fact publication with explicit conservative alternatives; typed coherence/contract-mapping rejection | S4 and F24–F27 |
| A24 | `EffectRequest` sum: operation, acyclic callable, or recursive callable-component composition | `classify_operation_effect`; `compose_callable_effects`; `compose_recursive_component_effects` | operation: S2 op + F06/F25/F27 + declarations; callable: F16 + direct S2 call relations + callee F17/extern declarations; recursive: one typed callable component + its exact direct call edges | dense effect/summary publication with pure/conservative alternatives; typed declaration/provenance contradiction rejection | F16 and F17 |

### 5.1 Memory operation decomposition

Memory authority is one receiver family with five request leaves. A single `MemoryAnalysisInput`
superset would destroy facet invalidation and recreate `MemSemanticFactSet`. The required order is:

1. **Spine construction:** accepted S2 memory anchors plus S3 structural provenance create S4 object,
   subobject, and access occurrences. Failure means unresolved structural provenance or malformed
   accepted code—not “unknown optimization evidence.”
2. **Object meaning:** S4 objects plus F03/F10/F07 and relevant F19/F20/F15 premises produce dense
   F24. Unknown but legal geometry is an explicit object-meaning alternative, never absent/nil.
3. **Contract realization:** F06 plus S1→S2 provenance, S4, and F24 produce sparse F27 or a typed
   subject/object mapping rejection.
4. **Access meaning:** S4 accesses plus F24/F27/F19/F20/F15/F10/F07 produce dense F25. Bounds,
   trap, alignment, and movement are explicit proven/unproven/unknown/may-trap/pinned alternatives.
5. **Relations:** S4 pairs plus F24/F25/F27/F19/F20, exact F06 pair evidence, and the direct F10
   layout/F07 ownership premises used by each proof produce sparse F26.
   May-alias, incomparable, unknown dependence, and loop-carried dependence are facts, not pass failure.

Observable reads/writes/preserve/invalidate remain A24 facts. F34 remains A10 storage refinement.

### 5.2 Productive analysis versus rejection

After O13, inability to prove an optimization premise is not a program rejection:

- an uncounted loop is a dense F19 alternative;
- an unavailable algebraic form is an A22 result and creates no sparse entry;
- may-alias/unproven-bounds/may-trap/immovable are F25/F26 alternatives;
- pure, external-conservative, or incomplete-call effects are explicit F16/F17 alternatives.

A23/A24 may still reject contradictory declarations, impossible provenance alignment, or malformed
accepted relations. Those are typed semantic/coherence rejections, not “optimization unavailable.”
This distinction preserves both the Step-1 rejection ledger and baseline fallback.

### 5.3 Total topology gate law

Only `CodeAccepted` may invoke A20. A20 returns S3 directly because impossible topology is an A19
validation defect. No `TopologyResult`, bool gate, validation world, or second graph reconstruction is
admitted.

---

## 6. Closed receiver ledger — planning, realization, and host boundary

| ID | Distinguished receiver family | Publication/decision operation | Exact additional frontier | Exhaustive immediate outcomes | Produces |
|---|---|---|---|---|---|
| A25 | `KernelRecognitionRequest` for one S3 candidate | `recognize_kernel` | F14/F15/F16/F17/F19–F21/F24–F27 and exact proofs | admitted S5+F28; typed no-plan; evidence-coherence rejection | S5 and F28 only for admitted candidates |
| A26 | `ScheduleSelectionRequest` for one S5 kernel | `select_schedule` | F28/F25/F26/F16/F17, policy, target capabilities, A32 emitter capability | selected F29; typed no-plan | F29 only for selected schedules |
| A27 | `FusedProjectionRequest` for one scheduled S5 kernel | `project_fused_computation` | F28/F29/F19/F21/F24–F27/F16/F17 and policy | admitted S6+F30; typed shape unavailable; evidence-coherence rejection | S6 and F30 only for admitted projections |
| A28 | `MemoryUseRequest` sum: three candidate derivations, S7/F31/F32 publication, pointer qualification, address record | operations in §6.1 | exact frontier per leaf | transient candidate records; separately published S7, F31, F32; F33 entry or typed unqualified outcome; typed unrealizable outcomes | S7 and F31–F33 plus one-consumer address records |
| A29 | `LoweringStrategyRequest` sum: baseline admission, subject selection, exact realization resumption, final commitment | operations in §6.2 | baseline: S2/S3 + A32 baseline capability; selection/commitment: S3 subject + F18/F21/F28/F29/F30/F31–F33 + A32 capabilities + exact typed A28/A30 outcome | F18 or `NoLegalBaseline`; transient `AttemptClosedForm`/`AttemptFused`; final F22 baseline/fragment commitment; `NoLegalStrategy` | F18 and final F22 |
| A30 | `FragmentRealizationRequest` sum: dominance publication or fragment contribution | `derive_dominance`; `realize_fragment_contribution` | dominance: accepted S2/S3; fragment: strategy attempt + F21/F30/F31–F33/address record/F23/baseline/target/environments | direct F23; realized fragment contribution; typed unrealizable contribution | F23 and direct fragment entities/results |
| A31 | `BackendConstructionRequest` | `construct_backend_unit` | accepted S2, F07/F34/F10/F11/F14/F16/F18/F22, selected fragment contributions, initializers/relocations, target/linkage | S8 unit; type/operation/storage/initializer/ABI/symbol/linkage/contribution/target rejection | S8 |
| A32 | intrinsic `GnuCEmitter` leaf plus concrete S8 entity leaves | `declare_capability`; `validate_and_serialize_c`; entity `validate_c`/`emit_c` methods | capability input: target; emission input: S8 + same target/capability/order | intrinsic capability value; C artifact; typed C reference/type/control/access/helper/feature/serialization rejection | emitter capability and C source/header artifact |
| A33 | `GccBoundaryReceiver` leaves: cook request, live session, released session | `cook_and_load`; `resolve_symbol`; `release` | C artifact + host policy/capabilities; live session + F11 symbol request; session liveness | live session or typed host failure; symbol capability or host failure; released/already-released | artifact paths, loaded session, symbol capabilities, liveness transition |

### 6.1 Materialized-use operation decomposition

A28 uses eight narrow request leaves. The first three produce one-consumer candidate records, not semantic
spine/facet publications. This permits exact independent frontiers while ensuring a failed optional
coordinate attempt cannot create fake S7 identity:

1. **Use-population candidate:** S6/F30 deterministically enumerate ordered proposed uses or return a
   typed candidate-unrealizable result. The record carries candidate ordinals and provenance, not S7 IDs.
2. **Use-meaning candidate:** the population candidate plus F30/F25 produce typed F31 candidate meaning
   or a terminal coherence rejection.
3. **Coordinate candidate:** the meaning candidate plus F19/F20/F24/F25/F10/F29/target produce exactly
   one proposed coordinate per candidate use or a typed candidate-unrealizable result.
4. **S7 admission:** coherent population/meaning/coordinate candidates create S7 identity only after all
   optional candidate derivations succeed.
5. **F31 publication:** S7 plus the meaning candidate publish dense F31 under the F31 frontier.
6. **F32 publication:** S7 plus the coordinate candidate publish dense F32 under the F32 frontier. Thus
   every accepted S7 use has exactly one F31 and F32 entry and every rejected attempt has no S7.
7. **Pointer qualification:** S7/F31 plus exact F06/F26/F27 pair evidence and target C rules produce
   sparse F33. Missing exact declared noalias is an explicit conservative no-entry outcome; a realization
   requiring qualification receives a typed optional outcome. F33 never depends on F32.
8. **Address record:** S7/F32 plus target and the exact realization environment produce a one-consumer
   address record or typed optional outcome. Address records/cursors cannot mint S8 locals or labels.

### 6.2 Strategy continuation discipline

A29 cannot publish F22 before optional realization succeeds. Its leaf behavior is:

1. baseline admission publishes dense F18 or terminal `NoLegalBaseline`;
2. subject commitment selects an immediate typed attempt: closed-form, fused, or baseline;
3. closed-form/fused attempt leaves construct exact A28/A30 requests;
4. A28/A30 unrealizable leaves return their typed reasons to A29;
5. A29 selects another attempt or baseline;
6. only an accepted fragment or deliberate baseline choice publishes final F22;
7. `NoLegalStrategy` is terminal only when no correct baseline/backend realization exists.

Rejected-alternative history and fallback reason are F22 content. They are not coordinator state, a
mutable strategy frame, or an issues list. The immediate result chain carries only the exact prior
attempt and typed realizer outcome needed for the next A29 request.

### 6.3 Fragment authority discipline

F23 is derived once per exact S2/S3 generation and reused by fragment attempts. A30 receives a
strategy **attempt**, not a prematurely committed F22. It creates fragment-local occurrences and a
substitutable contribution; only A31 creates final S8 locals, labels, functions, or storage.

Realized contributions return to A29, which publishes F22 selecting one. Unrealizable contributions
also return to A29. A30 owns feasibility/dominance/adapters/splice validity, never strategy intent or
fusion truth.

### 6.4 Emitter capability and host boundary

A32's intrinsic `GnuCEmitter` leaf declares capabilities before scheduling and baseline admission.
Concrete S8 entity leaves own their C validation and serialization behavior; the emitter sequences them
in declared S8 order and never dispatches by class or string. A26/A29 consume the declared capability
value and cannot manufacture support. A future emitter requires a new modeled leaf and coverage row.

A33's closed receiver family has cook-request, live-session, and released-session leaves. The cook
leaf owns host construction; the live leaf owns symbol/release behavior; the released leaf owns
idempotent release and typed use-after-release failure. It is the sole impure boundary. Its ASDL
requests/results remain typed, while filesystem/process/FFI/loader handles stay private to the host
resource implementation and never enter compiler ASDL through `any` or userdata escape fields.
Semantic ABI conformance remains A14/F11.

---

## 7. Canonical continuation graph

```text
[any terminal A01–A19 outcome] ---------------------> semantic transaction rejection
ProgramInput materialized
  -> resolve / nominal / type / check / control / contract / static ownership
  -> constant / capture / layout / ABI / closure / region expansion
  -> authoritative post-expansion re-resolution and checking
  -> S1 code construction
  -> S2 validation
       rejected -------------------------------------> semantic transaction rejection
       accepted -> total S3 topology + A06 code-operation attribution F14
                  -> flow -> algebra -> memory -> effects -> storage ownership
                  -> baseline admission + dominance publication
                  -> kernel recognition
                       no-plan -----------------------> strategy baseline
                       admitted -> schedule
                            no-plan ------------------> strategy baseline
                            selected -> fused projection
                                 unavailable --------> strategy baseline
                                 admitted -> strategy attempt
                                      -> uses / coordinates / qualification
                                           unrealizable -> strategy resume
                                      -> fragment realization
                                           unrealizable -> strategy resume
                                           realized ----> strategy commits F22
                                      -> baseline ------> strategy commits F22
                  -> backend S8
                  -> C validation/serialization
                       semantic rejection -----------> semantic transaction rejection
                       artifact -> emit-only user
                                -> GCC cook/load -> live session
                                     host failure ----> host-boundary error
                                     symbol/release --> host-boundary outcome
```

Every arrow selected by an operation outcome is behavior on that concrete result leaf. The diagram is
not a phase object, plan, or LLBL process.

---

## 8. Coordinator contracts

### 8.1 Compilation transaction

Creates one transaction generation, invokes child operations, and preserves typed outcomes. It owns
no type, control, ownership, analysis, planning, realization, or backend decision.

### 8.2 Post-expansion transaction

Sequences initial checking, region expansion, and authoritative re-resolution/rechecking of every
derived S1 allocation, then accepts only one coherent expanded generation.
Its failure contains ordered child rejections, not a second checking verdict.

### 8.3 Analysis coordinator

Constructs exact A06 code-attribution and A20–A24 request leaves in dependency order. It publishes no
facts, builds no lookup policy, and does not turn conservative evidence into program rejection.

### 8.4 Planning coordinator

Routes A25–A27 outcomes into A29. It does not recognize kernels, assert capabilities, project fused
shape, or choose fallback.

### 8.5 Realization coordinator

Routes A29 attempts through A28/A30 and returns their exact outcomes to A29. It does not commit
strategy, coordinates, coverage, fragments, physical operations, or syntax.

### 8.6 Host API coordinator

Its input is a sum of document/builder and emit-only/GCC request alternatives, not mode booleans. It
faithfully exposes semantic rejection envelopes, emitted artifacts, live sessions, and host failures.

No coordinator is a semantic receiver family in the A01–A33 set.

---

## 9. Cross-cutting laws have no receivers

| Law | Enforcement |
|---|---|
| Typed diagnostics | every concern-local rejection leaf owns reason/origin/rendering; coordinators preserve |
| Target consistency | one request generation; every physical request references it exactly |
| Optimization equivalence | all optional no-plan/unrealizable leaves return to A29; F18 baseline preserved |
| Determinism/isolation | explicit order and generation in every creator; no ambient counters or table order |
| Provenance | every entity/spine creator records typed source/causal predecessor |
| Structural termination | A08 success is required by A18; A19 gate precedes total A20 |
| Evidence discipline | consumers reference F06/F11/F14/F19/F26/capabilities and never strengthen them |
| Native path | A31 → A32 → A33 is the sole native route; no binary patcher or alternate native result leaf |

---

## 10. Publication coverage

| Publication | Sole receiver/operation family |
|---|---|
| S1 exact input/admission allocation | A01; derived allocations A15/A16/A17 with exact provenance |
| O13 accepted-code gate | A19 validation; consumed once by A20 |
| S2 | A18 code construction |
| S3 | A20 total topology |
| S4 | A23 memory-spine request |
| S5 | A25 admitted kernel |
| S6 | A27 admitted fused projection |
| S7 | A28 admitted use materialization |
| S8 | A31 backend construction |
| F01/F02/F03/F04/F05/F06 | A03/A04/A05/A07/A08/A09 respectively |
| F07/F34 | A10 static/storage request leaves |
| F08/F09/F10/F11/F12/F13 | A11/A12/A13/A14/A15/A17 respectively |
| F14 | A06 code-attribution request leaf |
| F15/F21 | A22 value/loop request leaves |
| F16/F17 | A24 operation/callable request leaves |
| F18/F22 | A29 baseline/final-commitment request leaves |
| F19/F20 | A21 loop/induction request leaves |
| F23 | A30 dominance request leaf |
| F24–F27 | A23 object/access/relation/contract request leaves |
| F28 | A25 admitted kernel |
| F29 | A26 selected schedule |
| F30 | A27 admitted fused projection |
| F31/F32/F33 | A28 admitted-use/qualification request leaves; candidate/address records are direct boundary values |
| O25 C acceptance | A32 success path; authorization is consumed in producing the artifact |
| C artifact | A32 accepted C realization |
| session/symbol capability | A33 host boundary |

No rejected kernel/fused/use candidate creates S5/S6/S7 identity. No result leaf copies another
authority's publication.

---

## 11. Current vocabulary disposition

| Current shape | Step-7 disposition |
|---|---|
| `Type*Result` success plus `issues` | replace with concern-specific success/reject leaves |
| string `reason`/`site` fields selecting semantics | replace with precise typed reason leaves |
| `CodeResult(module, contracts, layout_env)` | decompose into S2 and exact references |
| `FlowFactSet` + `FlowSemanticFactSet` | replace with A21 operations publishing F19/F20 |
| `ValueFactSet` | decompose into F15/F21 plus typed per-request unavailable outcomes |
| `MemSemanticFactSet`/`MemFactSet` | decompose into A23 S4/F24–F27 operations |
| `EffectFactSet`/analysis wrappers | decompose into A24 F16/F17 operations |
| `KernelModulePlan`/`ScheduleModulePlan` | delete bags; A25/A26 results and F28/F29 remain |
| `StencilKernelModuleProjection` | direct A27 S6/F30, no wrapper |
| `LowerModule`, `LowerBackSpine`, `LowerCModuleInput` | delete context/pass/world bags |
| mixed `LowerFragment` plan | split A29 intent/F22 from A30 feasibility/direct fragment |
| `CEmitMachine` retaining unit/context | replace with concrete A32 emitter leaf + exact request |
| `CompilerArtifactError(message)` | replace with typed semantic envelope or A33 boundary-failure leaf |
| duplicate GCC/session implementations | one A33 boundary |
| `LalinPhase`, `LalinExec`, generic `Machine/World/Plan` | delete; no receiver authority |

These are modeling dispositions, not a migration sequence or compatibility plan.

---

## 12. Step 7 closure

Step 7 is closed because:

- all thirty-two compiler concerns and the host boundary have one distinguished receiver family;
- every independently invalidated publication operation has a narrow request leaf;
- every result alternative is a publication, conservative outcome, immediate decision continuation,
  semantic rejection, optional realization outcome, or host failure—never nil/boolean/optional soup;
- terminal versus fallback behavior is explicit;
- F07/F34, F16/F17, F18/F22, F19/F20, F15/F21, S4/F24–F27, F23/fragment, and
  F31/F32/F33 preserve their independent frontiers through typed one-consumer A28 candidate records;
- strategy cannot publish F22 before realizer outcomes return;
- emitter capabilities exist before schedule/baseline decisions;
- total topology follows the validation gate without a second result wrapper;
- open expansion and sealed invocation remain separate authorities;
- every spine/facet/artifact/resource publication has one owning operation family;
- coordinators and laws own zero child semantics;
- no schema fields, implementation, migration, compatibility bridge, side table, world, or LLBL process
  has been introduced.

## Step 8 behavior-coverage result

`docs/COMPILER_BEHAVIOR_COVERAGE_MODEL.md` enumerates the closed semantic constructor/case sets, every
A01–A33 operation and result family, reason ownership, continuation classes, O01–O40 reachability,
required regressions, and falsifiable no-gap/no-overlap invariants. It also records the exact required
but currently unimplemented O33/O39/O40 methods without claiming false implementation credit.
