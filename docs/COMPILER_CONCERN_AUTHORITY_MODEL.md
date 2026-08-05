# Compiler Concern and Authority Model

Status: Step 3 closed for the ground-up Lua-ASDL compiler model.
Prerequisites:

- `docs/COMPILER_SEMANTIC_OBLIGATIONS.md`
- `docs/COMPILER_ENTITY_IDENTITY_MODEL.md`

This document assigns every compiler decision to one concern authority. It does not define
replacement ASDL declarations, spines, facets, worlds, machine products, requests, result sums,
phase order, or implementation. Existing files and products are evidence only.

The outcome is a closed authority graph, not a renamed pass pipeline.

---

## 1. Concern test

A concern is admitted only when it owns a distinct semantic or physical operation. Candidate
boundaries were tested for independent:

1. operation;
2. lifetime and invalidation;
3. diagnostic/rejection ownership;
4. consumed capabilities and downstream consumers.

Identity creation is an additional hard boundary: the concern that creates an entity must own
the creation decision even when the projection is total and cannot reject.

Chronology and file placement are not evidence of ownership. Several operations may be
sequenced together without becoming one concern. Conversely, two decisions implemented in one
file do not become one authority.

A concern label in this document does not imply an empty `FooMachine` record. Step 7 will select
the honest distinguished ASDL receiver for each concern.

---

## 2. Closed concern set

The minimum closed set has thirty-two compiler concern authorities and one host-resource
boundary authority.

### Authored and checked semantics

1. Authored program materialization
2. Staged synthesis
3. Declaration resolution
4. Nominal declaration semantics
5. Type meaning
6. Scalar and machine-operation meaning
7. Expression, place, and statement checking
8. Control legality
9. Contract meaning
10. Ownership and access semantics
11. Constant evaluation
12. Capture discovery
13. Target-dependent layout
14. Callable ABI
15. Closure representation
16. Open-region expansion
17. Sealed-region call semantics

### Code and semantic analysis

18. Monomorphic code construction
19. Code structural validation
20. Control topology
21. Flow and induction semantics
22. Value and algebra semantics
23. Memory-object and access semantics
24. Effect semantics

### Planning and physical realization

25. Kernel recognition
26. Schedule selection
27. Fused computation projection
28. Memory-coordinate materialization
29. Lowering-strategy commitment
30. Fragment materialization and assembly
31. Backend-unit construction
32. C validation and serialization

### Host-resource boundary

33. GCC artifact and loaded-session boundary

Cross-cutting laws and coordinators are deliberately absent from this set; Sections 8 and 9
name them separately.

---

## 3. Full obligation-to-authority ledger

Each row assigns the atomic decisions inside an obligation. A composite obligation may delegate
different atomic decisions, but no atomic decision has two owners.

| Obligation | Decision authority | Binding ownership statement |
|---|---|---|
| O01 Document ingestion | Authored program materialization | Recognizes each legal Lalin authoring input, preserves order/origin, and rejects malformed roots or role adaptation. LLBL owns generic lexing/HostEval delivery; Lalin owns adaptation into authored declarations. |
| O02 Builder/document convergence | Authored program materialization + convergence law | Parsed and builder input leaves construct one authored program. Convergence is a law on that one authority, not a reconciliation pass. |
| O03 Declaration identity/resolution | Declaration resolution | Populates semantic namespaces and resolves existing authored declaration/binding occurrences. Names are keys; resolution does not remint declarations. |
| O04 Type meaning | Type meaning, consuming nominal declaration semantics | Type meaning owns equality, canonical structural form, callable shape, and type operations. Nominal semantics alone owns declared fields/variants/constructors/handles. |
| O05 Expression/place/statement checking | Checking, delegating ownership-role cases | Checking owns use-site typing and meaning. Ownership/access owns copy, transfer, lease, retention, and invalidation violations. |
| O06 Capture semantics | Capture discovery | Establishes captures and roles while preserving original binding identity; no target layout is consulted. |
| O07 Control legality | Control legality | Owns termination, transfer, switch/default, continuation argument, passthrough, and source-control legality. It consumes checked expression facts rather than retyping them. |
| O08 Contract meaning | Contract meaning | Canonicalizes authored contracts to exact checked subjects. Memory alone later maps subjects to memory objects; effects consume rather than reinterpret contracts. |
| O09 Open-region expansion | Open-region expansion | Owns CFG splicing, generated occurrence identity, explicit environment admission, cloning, forwarding, and continuation retargeting. |
| O10 Sealed-region calls | Sealed-region call semantics, delegating physical feasibility to ABI | Owns semantic seal/function/frame/result protocol and caller routing. Callable ABI owns physical passing feasibility. |
| O11 Post-expansion authority | Post-expansion coordinator | Sequences ordinary resolution/checking over expanded output. It is not a semantic concern and owns no second checking verdict. |
| O12 Code construction | Monomorphic code construction | Creates code occurrences and target-neutral typed initializers/relocation relations. Layout, ABI, and ownership-erasure facts are consumed, not re-decided. |
| O13 Code validation | Code structural validation | Owns the accepted/rejected structural gate over references, signatures, transfers, definitions, initializers, and relocations. |
| O14 Control topology | Control topology | Totally derives block order, edges, edge-argument wiring, definitions, uses, natural loops, and loop identity from accepted code. |
| O15 Flow/induction | Flow and induction semantics | Sole owner of induction, direction, domains, ranges, edge-value recurrence interpretation, and trip evidence. Structural edge-argument wiring remains topology. |
| O16 Value/algebra | Value and algebra semantics | Owns value-copy canonicalization, pointwise algebra, ranges, reductions, and closed forms under scalar meaning and flow facts. It never fabricates trip facts. |
| O17 Memory semantics | Memory-object and access semantics | Owns objects, subobject provenance, accesses, indexes, bounds, alignment provenance, traps, alias/noalias, dependence, and memory-based movement legality. |
| O18 Effects | Effect semantics | Owns operation/call effects, volatility/atomic/trap behavior, contract-derived read/write/noescape/invalidate/preserve consequences, and function summaries. |
| O19 Kernel recognition | Kernel recognition | Owns transformability, kernel identity, lanes, bindings, result shape, and exact no-plan reasons. It borrows all proofs. |
| O20 Schedule selection | Schedule selection | Chooses form/tail/policy from kernel facts plus externally declared target/emitter capabilities. It cannot assert its own emitter support. |
| O21 Fused computation | Fused computation projection | Owns semantic iteration/producer/stream/access/sink/result shape and its shape rejection. It cannot revise memory or trip evidence. |
| O22 Coordinates | Memory-coordinate materialization | Creates materialized memory-use occurrences and owns coordinate, basis, cursor, window, addressing, and `restrict` qualification derived from exact evidence. |
| O23 Fragment materialization | Fragment materialization and assembly | Creates materialized fragments and proves realization, dominance, adapters, exact coverage feasibility, splice contribution, helpers, and baseline preservation. |
| O24 Backend construction | Backend-unit construction | Creates physical backend functions/data/globals/externs/helpers/symbol projections and one complete unit from accepted code and selected realizations. |
| O25 C validation/serialization | C validation and serialization | Validates the complete C-semantic unit, then deterministically serializes it without changing any decision. |
| O26 GCC/session | GCC artifact and loaded-session boundary | Owns host cooking, files, shared object, `dlopen`/`dlsym`, live session, and release. Failures are host-boundary failures. ABI owns requested callable conformance. |
| O27 Diagnostics | Concern-local rejection ownership + diagnostic law | Every authority creates and explains its own typed rejection. Diagnostic leaves own rendering; coordinators only preserve and route them. |
| O28 Target/policy propagation | Target law + intrinsic target/capability values | The compilation request selects one target/policy generation. Each physical authority consumes narrow projections; there is no generic target machine. |
| O29 Constant evaluation | Constant evaluation; physical initialization delegated | Constant evaluation owns the compile-time subset and semantic value. Code owns typed initializer relations; backend construction owns target-dependent bytes/storage/relocations. |
| O30 Nominal data/variant/handle | Nominal declaration semantics; checking for use sites | Nominal semantics owns child identities/order, constructors, payloads, patterns, handle domain/target, and entity kind. Checking validates occurrences of their use. |
| O31 ABI/linkage | Callable ABI | Owns physical signatures, parameter/result passing, calling convention, linkage, visibility, and semantic-function-to-symbol projection. It consumes ownership erasure. |
| O32 Scalar/machine operations | Scalar and machine-operation meaning; backend construction consumes | Intrinsic scalar/operator leaves own arithmetic, cast, overflow, float, pointer, atomic, volatility, and ordering meaning. Backend only realizes that meaning in C. |
| O33 Ownership/access/erasure | Ownership and access semantics | Sole owner of owned-value transfer/discharge, lease liveness, noescape/retention, invalidation, control transitions, and erasure authorization. |
| O34 Lowering strategy | Lowering-strategy commitment + optimization law | Sole owner of baseline/kernel/closed-form commitment, intended coverage, rejected alternatives, and fallback. Realizers report feasibility; strategy decides fallback. |
| O35 Determinism/isolation | Determinism law + generation boundaries | Each creator owns deterministic order in its output. Request and host boundaries create compilation/session generations; no determinism machine audits the compiler. |
| O36 Meta-properties/synthesis | Staged synthesis | Owns hook lookup/invocation, recursion bounds, and generated result selection. Canonical Lalin role adaptation remains authored-program authority. |
| O37 Layout | Target-dependent layout | Sole owner of size, alignment, offsets, tags, payload/handle storage, and aggregate storage classification for one target generation. |
| O38 Closure environment | Closure representation | Owns environment field/order, captured-access representation, closure callable construction, and representation rejection; consumes capture, layout, ABI, and ownership facts. |
| O39 Handle Domain/trusted crossing | Ownership/access, consuming nominal and layout facts | Domain resolver lease grant and trusted crossing are ownership capabilities. Nominal semantics owns declared domain/target; layout owns representation width. |
| O40 Unique declaration | Nominal semantics + ownership/access + memory semantics | Nominal semantics owns value-versus-entity kind; ownership owns copy/equality/transfer legality; memory owns identities of allocated storage objects. |

No obligation remains mapped to `LalinPhase`, `LalinExec`, RegionBundle, the standalone
Stencil descriptor path, dead `Type.Abi*` plans, `CodeBack*`, or any other speculative
vocabulary.

---

## 4. Authority dossiers — authored and checked semantics

### 4.1 Authored program materialization

**Operation:** construct one ordered authored Lalin program from document, builder, or generated
declaration inputs. Parsed/builder forms are input alternatives, not separate semantic programs.

**Consumes:** source/builder values, source origin, LLBL delivery, canonical Lalin role adaptation.

**Owns:** program/declaration/binding/region occurrence creation, authored order, source/generated
origin, Lalin root legality, surface normalization, and ordinary HostEval role adaptation.

**Rejects:** lexical/syntactic failure as delivered by LLBL, illegal document root, malformed
declaration/body, invalid builder payload, unsupported host value/role, and failed splice.

**Invalidated by:** any source, builder, splice, or generated-declaration input change.

**Consumers:** resolution, synthesis insertion, diagnostics, and tooling.

Surface sugar normalization belongs here, not in resolution. Resolution must not change authored
declaration category or normalize export/local forms.

### 4.2 Staged synthesis

**Operation:** resolve and invoke declared compile-time hooks and select a finite generated result.

**Consumes:** meta-property query, declared hook, schema context, staged Lua capability, and the
authorship concern's canonical role adapter.

**Owns:** hook selection/invocation, method/entry-missing policy, recursion/bounds, and causal
generated origin. A generated result becomes a declaration entity only when accepted by
authorship.

**Rejects:** unknown hook, role mismatch, unsupported result, unbounded recursion, and attempted
dynamic fallback in compiled code.

**Invalidated by:** hook assignment, query, schema context, or staged input change.

**Consumers:** authored program materialization.

### 4.3 Declaration resolution

**Operation:** establish semantic namespace occupancy and resolve references.

**Consumes:** one authored generation and lexical/qualification rules.

**Owns:** duplicate/conflict verdicts, value/type/region namespace lookup, lexical binding
relations, qualification, shadowing legality, and resolved-reference provenance.

**Rejects:** duplicate declaration, missing name, wrong namespace, invalid qualification, illegal
shadowing, and incompatible declaration category.

**Invalidated by:** any authored declaration, binding, containment, or qualification change.

**Consumers:** type/nominal meaning, checking, contracts, capture, regions, and code construction.

Fields and variants are not a second namespace authority here. Nominal semantics owns child
membership; resolution supplies the nominal declaration reference.

### 4.4 Nominal declaration semantics

**Operation:** establish the target-independent meaning of authored nominal declarations.

**Consumes:** resolved struct/union/handle/unique declarations and child occurrences.

**Owns:** declared field/variant identity and order, payload shape, constructor and pattern meaning,
handle domain/target relation, and value-product versus unique-entity kind.

**Rejects:** duplicate child, invalid nominal recursion/category, malformed payload, invalid handle
target, and unique declaration without an identity authority.

**Invalidated by:** nominal declaration or child change; never by target change.

**Consumers:** type meaning, checking, ownership, layout, memory, ABI, and backend construction.

The query “does nominal N declare child C?” has one answer here. Type meaning consumes that answer.

### 4.5 Type meaning

**Operation:** establish target-independent structural and nominal type meaning.

**Consumes:** resolved type forms and nominal declaration facts.

**Owns:** structural equality/canonical form, nominal-reference equality, callable semantic shape,
legal type compositions, element/pointee/result relationships, and type-level operation
admissibility.

**Rejects:** unknown type, invalid recursive meaning, illegal extent/composition, incompatible type,
and unsupported type operation.

**Invalidated by:** type or nominal meaning change; never by target/layout change.

**Consumers:** checking, scalar meaning, constant evaluation, capture, layout, ABI, code, and memory.

### 4.6 Scalar and machine-operation meaning

**Operation:** define exact language meaning of scalar, pointer, cast, atomic, comparison, and
machine operations.

**Consumes:** operand types and declared arithmetic/float/overflow/alignment/volatility/ordering
contracts.

**Owns:** result-type rule, signedness/width behavior, overflow contract, floating contract, cast
legality, pointer arithmetic, shift/division conditions, and atomic ordering meaning.

**Rejects:** illegal operation/type pair, undefined width/shift, unavailable overflow semantics,
incompatible floating contract, illegal cast, pointer operation, or atomic ordering.

**Invalidated by:** operation/type/declared-semantic change, not by backend emitter choice.

**Consumers:** checking, constant evaluation, flow/value/memory analysis, kernel recognition, and
backend construction.

Constant folding and value analysis must invoke these intrinsic operation semantics; neither may
reimplement host-Lua or accidental-C arithmetic.

### 4.7 Expression, place, and statement checking

**Operation:** assign use-site meaning and types to authored expressions, places, and statements.

**Consumes:** resolved references, type/nominal/scalar meaning, expected types, and exact control/
ownership/region capabilities.

**Owns:** contextual literal adaptation, expression/place type, assignment/call/return-value/cast/
index/field/constructor use, statement sequencing, and omitted-initializer zero semantics.

**Rejects:** type mismatch, invalid place/call/return-value/cast/index/use, unsupported operation,
and malformed nominal use. It propagates, rather than re-issues, resolution and ownership rejects.

**Invalidated by:** authored body, resolved relation, type meaning, or expected capability change.

**Consumers:** control legality, contracts, regions, capture, code construction, and diagnostics.

### 4.8 Control legality

**Operation:** prove authored control is complete, typed, terminating, and protocol-correct.

**Consumes:** checked statement facts, function result, blocks/continuations, and region/control
capabilities.

**Owns:** every-path termination, transfer target/argument validity, switch default/no-fallthrough,
continuation protocol, passthrough precedence, entry-parameter flow, and forbidden source control.

**Rejects:** missing terminator/default/target, duplicate target, invalid return path, illegal
fallthrough, bad transfer arguments/passthrough, unreachable transfer, and forbidden control.

**Invalidated by:** any control node, block signature, or continuation protocol change.

**Consumers:** open/sealed region concerns, code construction, and diagnostics.

Checking owns return-value typing; control legality owns whether the path returns correctly.

### 4.9 Contract meaning

**Operation:** canonicalize declared semantic evidence against exact checked subjects.

**Consumes:** checked bindings/places, type meaning, and contract expressions.

**Owns:** subject validity, bounds/readonly/writeonly/preserve/invalidate facts, exact pairwise
noalias/disjoint relations, contradiction detection, and canonical checked evidence.

**Rejects:** malformed/contradictory contract, non-memory subject, invalid bound, missing subject,
or unsupported contract form.

**Invalidated by:** checked subject, contract expression, or subject-identity change.

**Consumers:** ownership, memory, effects, kernel/fusion admission, coordinates, ABI, diagnostics.

It terminates at checked subjects. Only memory semantics maps those subjects to memory objects.

### 4.10 Ownership and access semantics

**Operation:** track authority and temporary access through typed control and authorize erasure.

**Consumes:** nominal entity/handle facts, checked bindings/control/calls/regions, contracts, capture
facts, and memory/effect evidence where storage identity is required.

**Owns:** owned-value transfer/discharge, copy/drop/equality legality, lease origin/liveness/escape,
noescape and retaining-call rules, invalidation conflicts, handle Domain resolver lease contract,
trusted representation permission, and the sole physical-erasure authorization.

**Rejects:** illegal copy/drop/double discharge, `var owned`, durable lease, lease escape, retaining
call, conflicting invalidation, use outside lifetime, invalid resolver/grant/crossing, and premature
erasure.

**Invalidated by:** typed control, binding, call contract, capture, or memory provenance change.

**Consumers:** checking, contracts, capture/closure representation, memory/effects, ABI, backend.

O33/O39 enforcement is pending. Assignment here is ownership, not false implementation credit.

### 4.11 Constant evaluation

**Operation:** evaluate exactly the declared compile-time subset.

**Consumes:** checked expression, type meaning, scalar operation meaning, and referenced constants.

**Owns:** foldability, cycle handling, semantic constant value, exact arithmetic rejection, and
decoded string-slice length. It does not create target bytes or a trailing NUL.

**Rejects:** non-constant expression, recursive evaluation, unavailable semantic operation,
unresolved constant, unsupported host value, and arithmetic rejection.

**Invalidated by:** expression, referenced constant, type, or scalar semantic change.

**Consumers:** checking and code construction.

### 4.12 Capture discovery

**Operation:** identify lexical captures independent of representation.

**Consumes:** resolved functions/bindings and authored/checked nested bodies.

**Owns:** capture membership, role, original binding provenance, and unsupported capture shape.

**Rejects:** unresolved capture, illegal escape visible at capture time, unsupported capture/nested
function shape.

**Invalidated by:** binding, scope, or nested body change; not target/layout change.

**Consumers:** ownership and closure representation.

### 4.13 Target-dependent layout

**Operation:** derive physical storage geometry for one exact target.

**Consumes:** type/nominal meaning, target representation, and layout policy.

**Owns:** size, alignment, field offsets, variant tag/payload storage, handle representation,
aggregate storage classification, and overflow checks.

**Rejects:** incomplete recursive layout, unrepresentable field/payload, invalid alignment, target
width mismatch, unsupported aggregate storage, and layout overflow.

**Invalidated by:** type/nominal meaning, target, or layout-policy change.

**Consumers:** checking only where physical field access is required, closure representation, code,
memory, ABI, coordinates, backend construction.

### 4.14 Callable ABI

**Operation:** derive physical callable and linkage semantics.

**Consumes:** semantic callable type, layout, target/calling convention, linkage declaration, and
ownership erasure authorization.

**Owns:** physical parameter/result passing, aggregate calling shape, calling convention, linkage/
visibility, extern/public symbol projection, and requested symbol conformance.

**Rejects:** unrepresentable parameter/result, unsupported convention, incompatible redeclaration,
signature collision, missing symbol policy, invalid visibility, and ABI target mismatch.

**Invalidated by:** semantic signature, layout, target, linkage, or erasure change.

**Consumers:** sealed call physical validation, closure representation, backend construction, C
validation, GCC symbol requests.

### 4.15 Closure representation

**Operation:** realize captures as a callable closure without changing captured identity.

**Consumes:** capture facts, layout, callable ABI, ownership/noescape facts, and target.

**Owns:** deterministic environment field order, environment representation, captured-reference
rewrite/projection, closure callable representation, and generated environment/helper occurrences.

**Rejects:** impossible environment layout, illegal escape/lease storage, unsupported capture
representation/nested shape, target or ABI incompatibility.

**Invalidated by:** capture, layout, ABI, ownership, or target change.

**Consumers:** code and backend construction.

### 4.16 Open-region expansion

**Operation:** splice an open region into caller control.

**Consumes:** checked region definition/protocol, invocation/wiring, exact typed environment, caller
captures, target block parameters, and expansion generation.

**Owns:** invocation-generated block/binding/value identity, cloning, environment admission/
shadowing/forwarding, target binding, nested expansion, and continuation retargeting.

**Rejects:** missing definition, argument/wiring/protocol mismatch, capture admission failure,
duplicate generated identity, and unsupported body.

**Invalidated by:** definition, protocol, invocation, wiring, caller environment, or target control
change.

**Consumers:** post-expansion coordinator and ordinary checking.

### 4.17 Sealed-region call semantics

**Operation:** establish one semantic callable boundary for a sealed region and route its result.

**Consumes:** checked seal/protocol/body, invocation/wiring, caller state, and ABI feasibility.

**Owns:** semantic seal, generated callable/result nominal occurrences, materialize-once decision,
typed frame arguments/result alternatives, callee exits, and caller continuation routing.

**Rejects:** missing seal, argument/protocol/wiring mismatch, unsupported semantic frame value,
recursive materialization, and delegated ABI rejection.

**Invalidated by:** seal/body/protocol/invocation or ABI feasibility change.

**Consumers:** post-expansion coordinator, checking, code construction, ABI/backend.

Open and sealed regions remain separate authorities: splicing versus a real callable boundary have
different identity creation, invalidation, capabilities, and failure contracts. RegionBundle has no
authority.

---

## 5. Authority dossiers — code and analysis

### 5.1 Monomorphic code construction

**Operation:** construct complete monomorphic code from accepted expanded checked semantics.

**Consumes:** checked program, origins, contracts, type/layout facts needed for code shape, closure/
region representations, semantic callable shapes, and ownership facts.

**Owns:** code function/block/instruction/terminator/value/local/data/global/extern occurrences and
order, typed instructions/initializers, relocation relations, and checked-to-code provenance.

**Rejects:** unsupported checked construct, missing required representation, illegal initializer/
relocation creation, unbound lowered value, malformed body, and unrepresentable code type.

**Invalidated by:** accepted checked generation or consumed representation change.

**Consumers:** structural validation only; later concerns consume accepted code.

It does not own physical C symbols, C locals, target bytes, or callable ABI decisions.

### 5.2 Code structural validation

**Operation:** certify that a code generation is structurally self-consistent.

**Consumes:** constructed code and its exact typed relations.

**Owns:** uniqueness/reference/signature/definition/transfer/memory-operation/initializer/
relocation integrity verdict.

**Rejects:** duplicate/missing occurrence, undefined value, signature/type/arity mismatch, invalid
target/transfer/memory op/initializer/relocation, and unterminated block.

**Invalidated by:** any code reconstruction.

**Consumers:** topology, analyses, planning, and backend construction.

Construction creates; validation certifies. Neither may self-certify the other's decision.

### 5.3 Control topology

**Operation:** totally establish reusable code structure and loop identity.

**Consumes:** structurally accepted code.

**Owns:** function/block/instruction order, edges and arms, positional/named edge-argument wiring,
definitions, uses, block ownership, natural loops, headers/latches/exits, and loop identity.

**Rejects:** none. Impossible topology is a structural-validation defect.

**Invalidated by:** code block/instruction/terminator reconstruction or splitting.

**Consumers:** flow, value, memory, effects, kernel, strategy, fragment dominance/coverage.

Downstream concerns must consume this topology instead of rebuilding def/use/block indexes.

### 5.4 Flow and induction semantics

**Operation:** interpret control cycles and edge transfer as domains and trips.

**Consumes:** accepted code, authoritative topology, scalar operation meaning, and exact code
definitions/constants needed to interpret steps and conditions.

**Owns:** induction/recurrence role, primary counter, direction, start/stop/step, inclusive/exclusive
convention, domain shape/intent, ranges, exits, and the sole trip evidence.

**Rejects:** non-counted loop, missing structural premise, ambiguous/unsupported induction,
contradictory direction, invalid domain, and unprovable trip.

**Invalidated by:** topology, relevant code definition, or scalar/value premise change.

**Consumers:** value algebra, memory, kernel, scheduling, fused projection, coordinates, strategy.

Value algebra consumes flow facts and may derive closed forms, but cannot create a competing trip
projection. The current flow/value trip merge is deleted conceptually.

### 5.5 Value and algebra semantics

**Operation:** derive algebraic meaning of code values under exact scalar and flow meaning.

**Consumes:** accepted code, topology, scalar operation meaning, and flow facts.

**Owns:** value-copy canonicalization, constant/range expressions over code values, no-wrap/float
analysis evidence, reductions, closed forms, affine expressions, and algebraic proofs.

**Rejects:** unsupported expression/recurrence, unsafe arithmetic analysis, non-associative
reduction, unavailable premise/proof, and analysis incompatible with declared scalar semantics.

**Invalidated by:** code definition, topology/flow, or scalar semantic change.

**Consumers:** memory, kernel, fused projection, coordinate/fragment realization, strategy.

“Value alias” means copy canonicalization only. Storage aliasing belongs solely to memory.

### 5.6 Memory-object and access semantics

**Operation:** establish storage identity, access meaning, and memory safety/dependence evidence.

**Consumes:** accepted code/topology, flow/value facts, canonical contracts, type/layout facts, and
ownership/storage facts.

**Owns:** memory-object/access identity, root/subobject provenance, place-to-object relation, index/
extent/stride, access mode, bounds, alignment with layout provenance, trap, same-store/alias/
noalias/disjoint, dependence, dereference width, and memory-based movement legality.

**Rejects:** unresolved place/provenance, unknown extent/stride/alignment, unproven bounds, possible
trap, ambiguous alias, incomparable dependence, illegal memory movement, and contract contradiction.

**Invalidated by:** code access, flow/value, contract, layout, ownership, or storage-provenance change.

**Consumers:** effects, ownership refinement, kernel, fused projection, coordinates, backend.

Readonly/writeonly/invalidate observable consequences belong to effects; memory owns only their
subject/object relation and memory evidence.

### 5.7 Effect semantics

**Operation:** classify and compose observable operation and callable behavior.

**Consumes:** accepted code/topology, canonical contracts, memory objects/accesses, and callee/extern
effect declarations.

**Owns:** reads, writes, preserve/invalidate, retain/noescape, traps, volatility, atomicity, calls,
external/allocation behavior, per-operation facts, and function/callee summaries.

**Rejects:** unknown callee/external effect, contradictory effect contract, incomplete summary, and
unsafe effect capability for a requested transformation.

**Invalidated by:** operation, contract, memory subject mapping, callee, or external declaration
change. A callee-summary change does not invalidate memory alias proofs.

**Consumers:** ownership, kernel, scheduling/fusion admission, strategy, backend qualifiers.

---

## 6. Authority dossiers — planning and realization

### 6.1 Kernel recognition

**Operation:** recognize transformable semantic computations from analyzed loop subjects.

**Consumes:** topology loop, flow/trip, value algebra, memory, effect, and exact proof evidence.

**Owns:** kernel identity, candidate admission, counter, lanes, bindings, semantic effects, result
shape, reduction/scan/find/all/any/all-compare recognition, and no-plan reasons.

**Rejects:** unsupported control/domain/result/expression/effect, unsafe memory, missing proof/trip,
ambiguous lane, and incomplete computation.

**Invalidated by:** topology or any consumed analysis/evidence change.

**Consumers:** schedule, fused projection, strategy, diagnostics.

Kernel recognition is entered by a coordinator/request, never as a method pretending memory owns
the concern.

### 6.2 Schedule selection

**Operation:** select an executable schedule form and tail policy for an admitted kernel.

**Consumes:** kernel, memory/effect legality, compiler policy, target platform capabilities, and
backend-emitter capability facts.

**Owns:** candidate order, form/tail selection, policy/profit decision, capability consumption, and
rejected-alternative history.

**Rejects:** unsupported target/emitter/form/tail/result, insufficient proof, illegal movement, and
policy rejection.

**Invalidated by:** kernel, policy, target capability, or emitter capability change.

**Consumers:** fused projection and lowering strategy.

Target leaves own platform capabilities. C realization owns the declaration of forms it can
actually emit. Scheduling consumes their intersection; it must not manufacture either fact.

### 6.3 Fused computation projection

**Operation:** project kernel plus schedule into one deterministic semantic fused shape.

**Consumes:** kernel, schedule, authoritative flow/value/memory/effect evidence, and policy.

**Owns:** semantic iteration, axes, producers, streams, accesses, sinks, result protocol, declared
guarantee provenance, and fused child occurrence identity.

**Rejects:** unsupported domain/result/operator/window/tail, incompatible schedule, unsafe or
unproven required access, and shape/capacity contradiction.

**Invalidated by:** kernel, schedule, semantic evidence, or policy change.

**Consumers:** coordinate materialization and fragment attempts.

It may reject its own semantic shape. It cannot issue coordinate-generation rejections, rederive
trip facts, or construct a second memory-admission truth.

### 6.4 Memory-coordinate materialization

**Operation:** create one deterministic physical-use topology and exact address realization.

**Consumes:** accepted fused shape, memory facts, iteration/domain facts, type/layout, schedule, and
target representation.

**Owns:** memory-use occurrence identity/order, stream/access/sink provenance, coordinate per use,
basis, displacement, windows, cursors, dereference width, physical addressing, and pointer
qualification including `restrict`.

**Rejects:** use/provenance mismatch, coordinate/induction disagreement, unknown stride/extent/
alignment, invalid/unsafe window, overflow, unsafe dereference, trapping/pinned access, and absent
exact pairwise noalias for requested `restrict`.

**Invalidated by:** fused-use topology, iteration, memory evidence, layout, schedule, or target change.

**Consumers:** fragment materialization.

This concern may later publish independently reusable structural and coordinate projections; that is
a Step 4/5 question, not a reason to split authority here.

### 6.5 Lowering-strategy commitment

**Operation:** commit each candidate subject to baseline, closed-form, or realized fused lowering.

**Consumes:** accepted code/topology, kernel/schedule/fused alternatives, backend capabilities, and
typed coordinate/fragment attempt outcomes.

**Owns:** attempt order, intended covered subject, final strategy commitment, proof references,
rejected alternatives, fallback reason, and baseline-preservation decision.

**Rejects:** malformed mandatory strategy or absence of any legal baseline/backend realization.
Optional candidate rejection is retained but does not reject the program.

**Invalidated by:** candidate/proof/capability/realization or baseline change.

**Consumers:** backend-unit construction and diagnostics/remarks.

Strategy may request coordinate and fragment realization before final commitment. Realizers report
typed feasibility; the strategy-result continuation alone chooses fallback. This prevents a failed
optional materialization from becoming a program rejection.

### 6.6 Fragment materialization and assembly

**Operation:** realize one requested semantic strategy as a complete substitutable C-shaped
fragment contribution.

**Consumes:** strategy attempt, fused/closed-form meaning, coordinates/address plan, baseline code/
topology, target, and exact value/access/exit environments.

**Owns:** materialized-fragment identity, realization support, fragment blocks/locals/helpers,
dominance, intended-coverage feasibility, entry/value/access/exit adapters, contribution conflicts,
replacement/elimination relation, and exact baseline-preserving splice result.

**Rejects:** unsupported realization/value/closed form, invalid coverage/dominance/adapter/exit,
missing coordinate/value/access, namespace/helper conflict, incomplete or conflicting contribution.

**Invalidated by:** strategy attempt, coordinates, baseline topology, dominance, target, or helper/
namespace policy change.

**Consumers:** strategy continuation and backend construction.

Fusion is decided upstream. This concern validates realizability and coverage feasibility; it cannot
revise kernel/fusion/memory truth. Strategy owns intended coverage and fallback; fragment assembly
owns whether that intended coverage is realizable.

### 6.7 Backend-unit construction

**Operation:** construct the complete physical backend model from accepted code and committed
realizations.

**Consumes:** accepted code, layout, ABI, scalar operation requirements, selected strategies,
materialized fragments/assembly, target, globals/data/externs/constants, and linkage.

**Owns:** backend function/global/data/extern/helper entities, physical blocks/locals/labels, storage,
target-dependent initializer bytes and relocation placement, physical operation construction, symbol
keys from ABI projection, deterministic unit order, and the complete backend unit.

**Rejects:** unrepresentable type/operation/storage/initializer/ABI, missing symbol/helper, illegal
linkage, invalid assembly contribution, and target mismatch.

**Invalidated by:** code, layout, ABI, strategy/materialization, target, or physical policy change.

**Consumers:** C validation and serialization.

It cannot infer memory evidence, change scalar semantics, retry optional strategy, or serialize text.

### 6.8 C validation and serialization

**Operation:** establish C-language conformance and produce deterministic C source/header.

**Consumes:** one complete backend unit, exact target, and declared emitter capabilities/order.

**Owns:** C-level reference/signature/type/control/access/helper/feature validation, emitter
capability declaration, deterministic syntax selection, escaping/formatting, and source/header text.

**Rejects:** invalid backend reference/signature/type/control/memory access/helper, unsupported target
feature or emitter leaf, and serialization boundary failure.

**Invalidated by:** backend unit, target, emitter implementation/capability, or serialization policy
change.

**Consumers:** AOT users and GCC artifact boundary.

Validation and serialization remain one concern: the validation result has no independent semantic
consumer, both share one C-artifact lifetime, and serialization introduces no new compiler decision.

### 6.9 GCC artifact and loaded-session boundary

**Operation:** cook emitted C and manage live host resources.

**Consumes:** validated emitted C, compiler/output policy, host filesystem/process/FFI/loader
capabilities, and ABI-backed symbol requests.

**Owns:** compiler selection, command execution, physical paths, shared-object construction, load
handle, live session identity, symbol capability, idempotent release, and use-after-release guard.

**Fails at boundary:** compiler/file/process/dlopen/dlsym/FFI failure and released-session access.
These are not semantic program rejections.

**Invalidated by:** artifact content/policy/host change; session ends on release.

**Consumers:** user code and tests.

The two current GCC/session implementations are duplicate authority. The closed model admits one.

---

## 7. Identity-creation authority

| Entity/occurrence class | Sole creation authority |
|---|---|
| Authored program, declaration, binding, region/block/continuation occurrence | Authored program materialization |
| Generated synthesis result occurrence and causal origin | Staged synthesis; declaration identity begins only when authorship accepts it |
| Resolved reference | Declaration resolution (relation identity, not reminted declaration identity) |
| Field, variant, nominal handle/unique child occurrence | Authored program materialization; nominal semantics owns meaning/order |
| Capture relation | Capture discovery; original binding identity is preserved |
| Closure environment field/helper occurrence | Closure representation |
| Open-expansion block/binding/value occurrence | Open-region expansion |
| Sealed callable/result nominal/frame occurrence | Sealed-region call semantics |
| Code function/block/instruction/terminator/value/local/data/global/extern occurrence | Monomorphic code construction |
| Topology loop and duplicate edge/use slot where needed | Control topology |
| Memory object, subobject, and access occurrence | Memory-object and access semantics |
| Kernel and kernel-local lane/binding occurrence | Kernel recognition |
| Fused stream/access/producer/sink/result occurrence | Fused computation projection |
| Materialized memory-use and cursor occurrence | Memory-coordinate materialization |
| Materialized fragment and fragment-local occurrence | Fragment materialization and assembly |
| Physical callable-signature decision | Callable ABI |
| Backend function/global/data/extern/helper and physical local/label coordinate | Backend-unit construction |
| Emitted source/header | C serialization produces artifact values, not entity identity |
| Shared-object session and resolved symbol capability | GCC artifact/session boundary |
| Diagnostic/rejection occurrence | The concern whose decision rejected |

No authority creates identity by composing or reparsing text. Display names and physical symbol
spellings are projections of typed identity and policy.

---

## 8. Cross-cutting laws — explicitly not concerns

### 8.1 Typed diagnostics

The rejecting concern owns the typed alternative, subject, origin, explanation, nested cause, and
diagnostic identity. A coordinator may preserve order and aggregate outcomes. Rendering is behavior
on diagnostic leaves. No generic diagnostic concern may reinterpret or flatten child decisions.

### 8.2 Target consistency

One compilation request selects one target and policy generation. Intrinsic target leaves own their
platform facts; C realization owns declared emitter support. Every physical authority consumes a
narrow projection aligned to that generation. There is no target-propagation machine.

### 8.3 Optimization equivalence

Optional optimization may not weaken semantics. Missing proof or failed coordinate/fragment
realization returns to lowering-strategy authority, which retains the correct baseline when one
exists. Only absence of any legal implementation rejects the program.

### 8.4 Determinism and isolation

Each authority's output depends only on declared input and uses explicit order. Generation validity
prevents stale mixing. Randomized filesystem paths isolate loader instances and do not affect
semantic output. There is no determinism auditor or process-global semantic counter.

### 8.5 Provenance

Every entity creator records source/causal provenance. In particular code construction owns
checked-to-code provenance; later authorities preserve or extend it. Origin is never reconstructed
from emitted names.

### 8.6 Structural termination

Checking/control legality and code validation together ensure every accepted function terminates
structurally. Topology is total only after that gate.

### 8.7 Evidence discipline

Contracts, trips, layouts, memory facts, effects, ABI facts, and emitter capabilities have one
producer each. Consumers may weaken or reject a candidate but may not strengthen, infer, or
fabricate upstream evidence. `restrict` requires exact declared pairwise noalias evidence.

### 8.8 Native path

C validation/serialization followed by GCC is the only native-performance route. No concern may
introduce a binary patcher, copy-patch bank, alternate native backend, or implicit LuaJIT path.

---

## 9. Coordinators — zero semantic decisions

### 9.1 Compilation transaction

Routes one request through concern operations, preserves typed results, creates transaction
generation, and chooses the next operation by result-leaf continuation. It must not inspect hidden
encodings or flatten semantic diagnostics.

### 9.2 Post-expansion transaction

Sequences initial checking, region expansion, and authoritative resolution/checking of generated
output; aggregates issues deterministically. It owns only transaction failure to retain a coherent
expanded checked result.

### 9.3 Analysis coordinator

Constructs exact requests for topology, flow, value, memory, and effects and routes their typed
outcomes. It publishes no analysis fact and owns no lookup/merge policy.

### 9.4 Planning coordinator

Sequences kernel recognition, scheduling, fused projection, and lowering candidate attempts. It
does not recognize kernels, assert capabilities, merge trips, or admit fusion.

### 9.5 Realization coordinator

Routes strategy attempts through coordinate/fragment realization, returns outcomes to strategy,
then invokes backend and C realization. It does not choose fallback, coverage, coordinates,
physical operations, or emitted syntax.

### 9.6 Host API coordinator

Selects source/builder request leaf, target/policy, emit-only versus GCC boundary, and routes typed
or boundary outcomes to the user. It does not own compiler semantics.

---

## 10. Contested-boundary verdicts

| Candidate boundary | Verdict | Reason |
|---|---|---|
| Document ingestion vs builder convergence | Merge as authorship | Same semantic output, lifetime, identity policy, and consumers; input leaves own surface-specific cases. A split creates two authored programs or a reconciler. |
| Authorship vs staged synthesis | Split | Synthesis invokes hooks with recursion/staged capability; authorship validates and admits the generated declaration. |
| Resolution split by value/type/region namespace | Merge | One authored namespace generation and one duplicate/qualification authority; projections may differ later. |
| Type meaning vs nominal declaration semantics | Split | Structural type operations differ from declaration child identity/constructor/domain meaning; type meaning consumes nominal membership. |
| Type/nominal meaning vs layout | Split | Target-independent versus target-invalidated physical geometry. |
| Layout vs ABI | Split | Storage representation versus callable passing/linkage; a calling-convention change must not invalidate field offsets. |
| Checking vs control legality | Split | Use-site typing versus path/transfer/termination protocol; distinct rejection vocabulary and consumers. |
| Checking vs contracts | Split | Contract canonical evidence has direct memory/effect/fusion consumers and must not be reinterpreted. |
| Checking vs ownership | Split | Structural/type legality versus linear authority, liveness, invalidation, and erasure. |
| Capture vs closure representation | Split | Capture is target-independent; representation consumes layout/ABI/ownership and creates new representation occurrences. |
| Open emit vs sealed call | Split | CFG splicing versus real callable/frame boundary; different identity, invalidation, capabilities, and rejection. |
| Post-expansion checking as a concern | Reject | It is a coordinator invoking the same authorities, not a second checker. |
| Code construction vs validation | Split | Identity creation/translation versus independent structural certification. |
| Validation vs topology | Split | Rejecting gate versus total structure/loop-identity projection; topology has downstream consumers beyond validation. |
| Topology vs flow | Split | Structural loops/edges versus semantic induction/domain/trip interpretation. |
| Flow vs value | Split | Control recurrence/domain/trips versus algebra of code values/reductions/closed forms. Trip authority remains flow. |
| Memory vs effects | Split | Per-object/access/proof lifetime versus callee-composed observable behavior; extern changes need not invalidate alias proofs. |
| Kernel vs schedule | Split | Semantic computation recognition versus target/emitter/policy choice. |
| Kernel vs fused projection | Split | Kernel answers what computation exists; fusion establishes deterministic stream/producer/sink shape under schedule. |
| Schedule vs lowering strategy | Split | Kernel-local execution form versus function/control-local baseline/replacement commitment and fallback. |
| Fused projection vs coordinates | Split | Semantic streams/accesses versus new physical-use identity and address truth. |
| Coordinates vs fragment materialization | Split | Address truth versus C-shaped realization/coverage feasibility; emission cannot revise coordinates. |
| Strategy vs fragment assembly | Split with result continuation | Strategy owns intended coverage/commit/fallback; fragment owns feasibility/dominance/splice. Fragment rejection returns to strategy. |
| Fragment assembly vs backend construction | Split | Substitutable fragment contribution versus creation of complete physical backend functions/unit. |
| Backend construction vs C realization | Split | Physical backend model versus external C conformance/text boundary. |
| C validation vs serialization | Merge as C realization | Same unit/artifact lifetime and sole consumer; serialization is mechanical after validation and has no independent semantic authority. |
| Compiler semantics vs GCC/session | Split | GCC/files/dlopen are host resources and boundary failures, not semantic program decisions. |
| O39 Handle Domain as a separate concern | Merge into ownership | Resolver lease grant/trusted crossing specialize the same store/lease/access authority; nominal and layout facts remain inputs. |
| O40 Unique as a separate concern | Merge into nominal/ownership | Entity kind is a nominal fact; copy/transfer enforcement is ownership; allocation identity is memory. A separate concern owns no operation. |
| Diagnostics, target propagation, determinism | Laws, not concerns | Turning them into generic machines duplicates every child authority. |

---

## 11. Current authority defects exposed by Step 3

The new model must not preserve these defects:

1. authored duplicate detection is missing;
2. surface normalization and resolution are conflated;
3. binding and generated identities are coordinated through text;
4. closure capture and physical environment representation are one premature pass;
5. layout is recomputed under inconsistent targets;
6. tree-level termination is incompletely enforced;
7. open/sealed region identity is encoded in names;
8. trip evidence is reconstructed/merged by flow, value, and kernel paths;
9. downstream analyses rebuild topology/def-use indexes;
10. memory and effect both derive contract read/write consequences;
11. scheduling asserts its own emitter capabilities;
12. fused projection re-derives flow iteration facts;
13. coordinate-preparation rejections leak onto fused-projection leaves;
14. lowering commits before optional realization failure has returned to fallback authority;
15. fragment coverage intent and feasibility are conflated;
16. backend/result leaves construct serializer state owned by the C boundary;
17. two GCC cooking/session implementations compete;
18. semantic issues are flattened to strings/counts at public boundaries;
19. constant evaluation is installed twice and reimplements scalar arithmetic;
20. pending ownership, Domain, and unique semantics have no active implementation;
21. speculative Exec/Phase/RegionBundle/descriptor/ABI vocabulary claims no real authority.

These are source evidence for later deletion and cutover, not implementation tasks for Step 3.

---

## 12. Step 3 closure proof

Step 3 is closed because:

- all forty obligations map to one authority, law, coordinator, or host boundary;
- every atomic semantic decision has one owner;
- every Step-2 entity class has one creation authority;
- contested membership, trip, effect, ABI, capability, coverage, and erasure ownership is resolved;
- open expansion and sealed call remain distinct;
- topology creates loops and flow alone interprets trips/domains;
- memory alone owns alias/bounds and effects alone owns observable summaries;
- kernel, schedule, fused shape, strategy, coordinates, and fragment realization remain distinct;
- optional realization failure returns to strategy instead of rejecting a valid baseline program;
- laws and coordinators have explicit zero-decision contracts;
- pending O33/O39/O40 behavior has an owner without receiving false implementation credit;
- dead and speculative schema vocabulary owns no obligation;
- no replacement ASDL declaration, spine, facet, world, machine object, or result sum has been
  proposed.

## Next step — Spines

Step 4 asks only where multiple closed concerns align to stable shared structure and where a later
boundary creates genuinely new structural identity. It will derive candidate spines from this
authority graph and the Step-2 identity model, not from current fact bags or pass products.
