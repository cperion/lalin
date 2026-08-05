# Compiler Semantic Obligations

Status: requirements ledger for ground-up ASDL modeling.

This document records what the compiler must mean and preserve. It deliberately does
not prescribe replacement ASDL products, machine names, phase boundaries, or migration
adapters. Existing schema and implementation names are cited only as evidence.

The future model must account for every obligation here before implementation begins.
If an obligation has no unique semantic owner, explicit inputs, persistent output,
alignment identity, rejection alternatives, and proving tests, the model is incomplete.

## Reading Rules

For every obligation, distinguish:

- authored fact: supplied by source or the builder;
- decision: a semantic choice made by exactly one concern;
- persistent fact: a decision retained for later consumers;
- projection: a derived immutable view of earlier facts;
- physical fact: an ABI, storage, address, or emitted-artifact decision;
- boundary failure: malformed external input or failed host IO;
- semantic rejection: a typed compiler-domain alternative.

Temporary indexing used while deriving an immutable result is not itself a semantic fact.
A repeated index becomes schema pressure when several concerns reconstruct it, depend on
its ordering, or use it to carry decisions not present in the persistent result.

## Global Invariants

These apply across all obligations:

1. One semantic decision has one authority.
2. Concrete variants own case-specific behavior.
3. Persistent facts are immutable and schema-visible.
4. Derived facts retain explicit provenance to the facts they were derived from.
5. Identity is never reconstructed from encoded names when a typed identity exists.
6. Rejection is represented by a typed alternative, not nil, booleans, exceptions, or
   count-only messages.
7. A coordinator owns sequencing only; it does not reproduce child decisions.
8. Backend optimization never weakens source semantics or fabricates memory evidence.
9. The emitted-C/GCC route is the sole native-performance path.
10. Every accepted function has structurally valid terminating control flow.

## Lifetime Classes

The eventual schema must assign each fact to one of these semantic lifetimes:

- document lifetime: source bytes, positions, parsed forms, host-evaluation boundaries;
- authored-program lifetime: declarations and authored identities;
- checked-program lifetime: resolved types, layouts, bindings, contracts, regions;
- code lifetime: monomorphic functions, blocks, values, instructions, and control topology;
- analysis lifetime: flow, value, memory, effect, and proof facts for one code generation;
- planning lifetime: kernel, schedule, fusion, and lowering decisions;
- materialization lifetime: coordinates, fragments, helpers, and backend assembly;
- artifact lifetime: emitted C, headers, shared objects, and loaded symbols.

A change in an earlier lifetime invalidates every derived later lifetime. Independent facts
within one lifetime may still have different owners and invalidation conditions.

---

## O01 — Document ingestion and source anchoring

**Inputs**

- source bytes or an ordered builder declaration sequence;
- source name and origin;
- LLBL/Lua host-evaluation capability at explicitly allowed bracket/splice boundaries.

**Decision**

Recognize a declaration document, preserve declaration order and source locations, and
reject forms that are not legal document roots.

**Persistent output**

An ordered authored declaration representation with sufficient origin information for
later diagnostics. Host-evaluated values must enter through declared typed boundaries.

**Identity and alignment**

Document identity, declaration order, and source ranges. Generated declarations require
origins distinguishable from directly authored declarations.

**Rejections**

Lexical failure, malformed declaration, illegal root form, malformed bracket evaluation,
unsupported host value, and failed top-level declaration splice.

**Consumers**

Declaration materialization, diagnostics, tooling, and builder/document convergence.

**Evidence**

`lua/lalin/loader.lua`, `lua/lalin/syntax/document.lua`, `lua/lalin/syntax/*`,
`tests/frontend/`, `tests/schema/test_parsed_*`, and loader fresh-process tests.

## O02 — Builder and document convergence

**Inputs**

Parsed declarations or builder-produced declarations.

**Decision**

Materialize both authoring surfaces into the same authored semantic program without a
second compiler model, parser recovery layer, or compatibility representation.

**Persistent output**

One canonical ordered authored-program representation.

**Identity and alignment**

Equivalent declarations must receive equivalent semantic identity and origin policy while
retaining whether their source was parsed or generated when diagnostics require it.

**Rejections**

Builder payload with an invalid typed value, unresolved generated reference, malformed
declaration body, or unsupported declaration category.

**Consumers**

Resolution, checking, and all later compilation concerns.

**Evidence**

`lua/lalin/dsl/`, `lua/lalin/syntax/document.lua`, parsed/builder GCC parity tests, and
`tests/c_backend/test_lalin_extern_builder_hosteval_gcc.lua`.

## O03 — Declaration identity and namespace resolution

**Inputs**

An authored program, declaration names, qualifications, host-spliced bindings, and language
namespace rules. `.lln` has no source-level import declaration.

**Decision**

Establish declaration identity and resolve every legal reference to its declaration or
binding. Detect conflicting, missing, or illegal references.

**Persistent output**

Resolved declaration and binding facts sufficient for checking and lowering. Resolution
must not depend on later string reconstruction.

**Identity and alignment**

Module, item, type, field, value, function, region, and component identities where those
are semantically durable. Lexical spelling is not automatically semantic identity.

**Rejections**

Duplicate declaration, missing name, wrong namespace, invalid qualification, illegal
shadowing, invalid field, and incompatible declaration category.

**Consumers**

Typing, layout, closure analysis, region calculus, contracts, and code construction.

**Evidence**

`lua/lalin/impl/tree_surface.lua`, `tree_check/scope.lua`, module environment construction,
qualified handle/variant tests, and frontend completeness tests.

## O04 — Type meaning

**Inputs**

Resolved authored types, type declarations, fields, variants, handles, arrays, views, slices,
pointers, functions, and scalar definitions.

**Decision**

Determine target-independent type equality, callable shape, field and variant membership,
legal type operations, canonical type form, and nominal relationships.

**Persistent output**

Checked type-meaning facts independent of physical target layout.

**Identity and alignment**

Named type, field, variant, handle-domain, and function-signature identity.

**Rejections**

Unknown type, invalid recursive meaning, duplicate field or variant, illegal array extent,
incompatible type, and unsupported semantic type operation.

**Consumers**

Expression checking, closure capture analysis, layout projection, memory semantics, ABI
planning, and code construction.

**Evidence**

`lua/lalin/schema/type.lua`, target-independent methods in `impl/tree_check/type.lua`, type
classification tests, typecheck tests, nominal-type tests, and qualified handle/variant tests.

Target-dependent size, alignment, offsets, discriminants, and physical representation belong
to O37, not to type meaning.

## O05 — Expression, place, and statement checking

**Inputs**

Resolved authored program, binding scope, expected types where applicable, checked type
facts, and exact control/region capabilities.

**Decision**

Assign meaning and type to expressions and places; validate assignments, calls, returns,
casts, indexing, field access, variant operations, statement sequencing, and context-pinned
literal adaptation. Integer/float/nil/host literals adopt only types admitted by their exact
context; an omitted `let` initializer denotes the zero value of the declared binding type.

**Persistent output**

A checked program in which every expression/place/statement carries sufficient declared
semantic facts for later lowering.

**Identity and alignment**

Binding identity and authored-node origin must survive checking. Expected-type adaptation
must not create an unrelated identity.

**Rejections**

Unbound value, type mismatch, invalid place, invalid call, illegal cast, invalid return,
unsupported operation, malformed variant use, and ownership/access violation.

**Consumers**

Control validation, region expansion, closure conversion where ordered earlier, contracts,
and code construction.

**Evidence**

`lua/lalin/impl/tree_check/{expr,stmt,type,module}.lua`, `tree_check/layout.lua`, typecheck
feature tests, variant tests, parsed expression tests, literal-sugar tests, and negative
diagnostic tests. There is no `tree_check/place.lua`.

## O06 — Closure and capture semantics

**Inputs**

Resolved authored functions, nested functions, and binding identities. Capture discovery
must not assume a target layout or a particular ordering relative to type checking.

**Decision**

Identify captures, distinguish capture roles, preserve original binding identity, and produce
a target-independent capture projection. Environment representation is a separate O38
decision.

**Persistent output**

A capture projection or explicit unchanged/unsupported result.

**Identity and alignment**

Captured binding identity remains tied to the original declaration.

**Rejections**

Unsupported capture, impossible environment layout, illegal escape, unresolved capture,
and unsupported nested function shape.

**Consumers**

Environment representation, checking, code construction, and ownership analysis.

**Evidence**

`lua/lalin/impl/tree_closure.lua` and closure schema/capture tests. Current tests prove
structural conversion only; no active GCC test executes a captured closure end to end.

## O07 — Control legality and termination

**Inputs**

Checked statements, function result type, block/continuation declarations, and region
control capabilities.

**Decision**

Ensure every path terminates correctly; validate branches, switches, jumps, continuation
arguments, returns, entry-parameter dataflow, and absence of forbidden source control forms.
Implicit passthrough is limited to current-block parameters: precedence is explicit argument,
then continuation payload, then same-name block-parameter passthrough. It never captures
`let`/`var`, region data, or outer scope by convention.

**Persistent output**

Explicit valid control structure or typed control rejection. Control decisions required by
later lowering must remain schema-visible.

**Identity and alignment**

Control target identity, block parameter identity, authored order, and source origin.

**Rejections**

Missing terminator, unreachable or duplicate target, missing switch default, wrong jump or
continuation arguments, missing/extra/type-mismatched passthrough, entry parameter without a
same-name source value, illegal fallthrough, invalid return path, forbidden source control,
and unsupported transfer.

**Consumers**

Region calculus, code construction, graph construction, and diagnostics.

**Evidence**

`lua/lalin/impl/tree_check/control.lua`, statement checking, control schema tests, region
wiring tests, and code validation tests.

## O08 — Contract meaning

**Inputs**

Checked function declarations, typed contract expressions, bindings, memory-bearing
parameters, and declared bounds/readonly/writeonly/noalias/invalidation facts.

**Decision**

Validate and canonicalize each contract against exact checked bindings/places. Contracts are
evidence, not optimization hints; absent evidence remains absent. Mapping a checked contract
subject to a later memory-object identity belongs to O17.

**Persistent output**

Canonical checked contract facts that later memory/effect/planning concerns consume
without reinterpreting authored syntax.

**Identity and alignment**

Function identity, checked binding/place subject identity, and explicit pairwise subject
identity for noalias evidence.

**Rejections**

Malformed contract, non-memory subject, invalid bound expression, contradictory contract,
unknown subject, and unsupported contract form.

**Consumers**

Memory safety, effects, fusion admission, restrict qualification, and diagnostics.

**Evidence**

`impl/tree_check/contract.lua`, tree-to-code contract lowering, memory contract projection,
effect contract tests, fusion admission tests, and restrict-declaration tests.

## O09 — Open-region expansion

**Inputs**

Checked region definition, invocation arguments, continuation wiring, explicit typed
environment, caller captures, target block parameters, and expansion state.

**Decision**

Splice an open region's control graph into its caller, rename owned identities, forward
only admitted environment values, bind target parameters, and retarget continuations.

**Persistent output**

An expanded authored/checkable program plus explicit expansion facts and typed issues.

**Identity and alignment**

Definition identity, invocation identity, cloned block/value identity, caller capture
identity, continuation identity, and origin linking generated nodes to the invocation.

**Rejections**

Missing definition, argument mismatch, missing continuation, continuation signature
mismatch, capture admission failure, duplicate generated identity, and unsupported body.

**Consumers**

Authoritative post-expansion checking and code construction.

**Evidence**

`lua/lalin/impl/tree_region.lua`, explicit emit-environment schema,
`tests/c_backend/test_lalin_emit_environment_gcc.lua`, region expansion and wiring tests.

## O10 — Sealed-region call and frame semantics

**Inputs**

Checked sealed region, call arguments, continuation protocol, caller state, and target ABI.

**Decision**

Create a real function/frame boundary, materialize the sealed body once, invoke it with
typed arguments, and route its typed continuation result back to caller targets. A proposed
RegionBundle optimization would group compatible sealed regions for intra-bundle transfer,
but current production always constructs an empty bundle projection; bundle behavior is
speculative and is not a required semantic obligation until a real consumer exists.

**Persistent output**

Materialized callable region facts and caller-side call expansion with explicit continuation
routing.

**Identity and alignment**

Seal identity, generated function identity, frame parameter identity, continuation result
identity, and source origin.

**Rejections**

Missing seal, incompatible protocol, argument mismatch, continuation mismatch, unsupported
frame value, recursive materialization failure, and ABI incompatibility.

**Consumers**

Post-expansion checking, code construction, ABI planning, and C emission.

**Evidence**

Region seal/materialization methods, parsed region protocol GCC tests, sealed call tests,
and region schema contract tests.

## O11 — Post-expansion authority

**Inputs**

Expanded program and accumulated region issues.

**Decision**

Coordinate the post-expansion transaction by invoking the same authoritative checking
concerns over the expanded structure. This is not a second checking authority. Expansion
must produce a structure admissible to ordinary checking, and no unexpanded fallback exists.

**Persistent output**

One accepted expanded checked program or typed rejection retaining all issues.

**Identity and alignment**

Expanded origins must align diagnostics with authored definitions and invocation sites.

**Rejections**

The transaction propagates O04–O08 rejections; it owns only transaction-level failure to
produce or retain the expanded checked program.

**Consumers**

Code construction only. No unexpanded fallback is permitted.

**Evidence**

`Tr.Module:typecheck_region_expanded`, region re-typecheck tests, public compile boundary,
and emitted-environment regression tests.

## O12 — Monomorphic code construction

**Inputs**

Accepted expanded checked program, exact target representation, checked contracts, type
layouts, declarations, functions, globals, externs, and constants.

**Decision**

Construct monomorphic code functions, signatures, blocks, parameters, values, locals,
instructions, terminators, data, globals, externs, and relocations.

**Persistent output**

One complete lower code program plus canonical contract facts and exact origin metadata.

**Identity and alignment**

Program, function, signature, block, instruction, terminator, value, local, type, data,
global, extern, and relocation identities. Their creation authority must be singular.

**Rejections**

Unsupported checked construct, missing layout, illegal relocation, unrepresentable type,
unbound lowered value, malformed code body, and target incompatibility.

**Consumers**

Code validation, topology, semantic analyses, planning, and backend construction.

**Evidence**

`lua/lalin/impl/tree_code.lua`, `schema/tree_code.lua`, terms/aggregate lowering tests,
code-signature tests, data/extern GCC tests, and tree-to-code result tests.

## O13 — Code structural validation

**Inputs**

Constructed code program and exact signature/type/global/function relations.

**Decision**

Validate identity uniqueness, references, signatures, block parameters, definitions, uses,
terminators, memory operation shape, data initializers, and relocation integrity.

**Persistent output**

Accepted code program or complete typed structural issue list.

**Identity and alignment**

All code identities from O12 and their defining/using relations.

**Rejections**

Duplicate or missing identity, invalid signature, undefined value, invalid block target,
wrong edge arguments, malformed instruction, illegal initializer, and invalid relocation.

**Consumers**

All semantic analyses and backend work. Invalid code cannot enter planning.

**Evidence**

`lua/lalin/impl/code_validate.lua`, code validation schema/tests, compiler CodeResult tests,
and C-backend negative tests.

## O14 — Control topology projection

**Inputs**

Validated code functions and blocks.

**Decision**

Totally derive edges, definitions, uses, loops, headers, latches, exits, and stable structural
ordering from structurally validated code. This is a projection, not an independent policy
decision.

**Persistent output**

One authoritative topology projection for the exact code generation.

**Identity and alignment**

Function, block, instruction, terminator, value, edge, and loop identity. Topology must
retain provenance to the exact code program.

**Rejections**

None for accepted O13 input. Any impossible topology indicates an O13 validation defect and
must not be represented by assertion, nil, or a second topology policy.

**Consumers**

Flow, value, memory, effects, kernel recognition, scheduling, and lowering.

**Evidence**

`lua/lalin/impl/code_graph.lua`, graph schema, `test_code_effect_pipeline.lua`, and downstream
analysis tests. Current coverage has no dedicated test deriving loop topology from a real
authored loop; most loop fixtures are hand-built.

## O15 — Flow and induction semantics

**Inputs**

Validated code and authoritative control topology.

**Decision**

Derive edge argument transfer, loop domains, induction variables, directions, trip evidence,
ranges, exits, native domain shape, intent, and rejection reasons.

**Persistent output**

Flow facts for one exact code/topology generation.

**Identity and alignment**

Edge, block parameter, value, loop, axis, and domain identity.

**Rejections**

Non-counted loop, missing latch/header/condition, ambiguous induction, unsupported recurrence,
contradictory direction, invalid domain, and unprovable trip fact.

**Consumers**

Value semantics, memory semantics, kernel recognition, scheduling, stencil projection,
and conservative lowering.

**Evidence**

`lua/lalin/impl/code_flow.lua`, flow schema, loop/domain tests, kernel canonical analysis,
scan/window/traversal tests, and grid/tile tests.

## O16 — Value and algebra semantics

**Inputs**

Validated code, control topology, and flow facts.

**Decision**

Derive constant/range expressions, value-copy canonicalization, integer semantics, floating
mode, reductions, closed forms, and algebraic proof evidence. “Value-copy canonicalization”
is distinct from O17 memory aliasing. Backend lowerability is not a value-semantic fact.

**Persistent output**

Value-semantic facts aligned to exact code values and loops.

**Identity and alignment**

Code value, defining instruction/block, loop, reduction accumulator, and proof identity.

**Rejections**

Unsupported expression, ambiguous recurrence, unsafe arithmetic semantics, incompatible
floating mode, non-associative reduction, and unavailable proof.

**Consumers**

Memory address reasoning, kernel recognition, fusion, schedule selection, and lowering.

**Evidence**

`lua/lalin/impl/code_value.lua`, value schema, reduction/fold/scan tests, kernel analysis,
and closed-form lowering tests.

## O17 — Memory-object and access semantics

**Inputs**

Validated code, topology, flow/value facts, checked contracts, types/layouts, and every
memory-bearing instruction/place.

**Decision**

Identify memory objects and provenance; classify accesses, indexes, extents, strides,
alignment, bounds, traps, alias relations, dependences, movement legality, and exact proof
evidence. Effect summaries belong to O18; physical address/backend choices belong to O22–O24.

**Persistent output**

Memory facts aligned to exact objects, accesses, instructions, values, and loops.

**Identity and alignment**

Memory object, base, access, code instruction/place/value, loop, contract subject, and proof
identity. Pairwise relations require explicit pair identity.

**Rejections**

Unresolved place, unknown provenance, unavailable extent/stride, unproven bounds, possible
trap, ambiguous alias, incomparable dependence, illegal movement, and contract contradiction.

**Consumers**

Effects, kernel admission, schedule legality, fusion, coordinate materialization, restrict
qualification, and conservative backend emission.

**Evidence**

`lua/lalin/impl/code_mem.lua`, memory schema/tests, dependence tests, CMat memory-use spine
tests, fusion contract tests, and restrict evidence tests.

## O18 — Effect semantics

**Inputs**

Validated code, topology, memory facts, contracts, calls, instructions, and terminators.

**Decision**

Classify reads, writes, calls, traps, volatility, allocation or external behavior, summarize
function effects, and compose callee effects.

**Persistent output**

Per-operation and per-function effect facts with evidence and unresolved alternatives.

**Identity and alignment**

Function, call site, instruction, terminator, memory object/access, and contract identity.

**Rejections**

Unknown callee, unresolved external effect, contradictory contract, unsafe effect for a
requested transformation, and incomplete summary.

**Consumers**

Kernel admission, scheduling, fusion, movement legality, and backend qualifiers.

**Evidence**

`lua/lalin/impl/code_effect.lua`, effect schema/tests, contract-call tests, and kernel tests.

## O19 — Kernel recognition

**Inputs**

One coherent generation of code topology, flow, value, memory, and effect facts.

**Decision**

Recognize transformable loop computations, lanes, counters, accesses, reductions, scans,
all/any/comparison/find results, trip evidence, and exact rejection causes.

**Persistent output**

Kernel plans or explicit no-plan facts for candidate subjects.

**Identity and alignment**

Loop/subject, kernel, lane, value, access, memory object, result, and proof identity.

**Rejections**

Unsupported control, unsafe memory, missing proof, unsupported expression/effect, invalid
trip shape, ambiguous lane, unsupported result, and non-transformable candidate.

**Consumers**

Scheduling, stencil/fused-shape projection, and conservative lowering fallback.

**Evidence**

`lua/lalin/impl/kernel_plan.lua`, kernel schema/tests, canonical analysis, leaf-ownership
tests, fold/scan/traversal GCC tests, and no-plan fallback assertions.

## O20 — Schedule selection

**Inputs**

Kernel plans, target capabilities, legal transformations, memory/effect proofs, and compiler
policy.

**Decision**

Select an executable schedule form and tail/lane strategy or retain exact rejection of each
alternative. Selection cannot claim an emitter capability that does not exist.

**Persistent output**

A schedule per planned kernel with proof and rejected alternatives.

**Identity and alignment**

Kernel, schedule, target capability, lane, tail, and proof identity.

**Rejections**

Unsupported target, missing emitter, illegal vector/tail form, insufficient proof, invalid
memory movement, unsupported result shape, and policy rejection.

**Consumers**

Fused-shape projection and lowering strategy selection.

**Evidence**

`lua/lalin/impl/schedule_plan.lua`, schedule capability tests, lower schedule projection
tests, and emitted fusion tests.

## O21 — Fused computation projection

**Inputs**

Kernel, schedule, flow/value/memory/effect evidence, target policy, and exact computation
shape.

**Decision**

Project a kernel into a deterministic fused computation: iteration, streams, accesses,
producers, sinks, result protocol, provenance, and declared memory guarantees.

**Persistent output**

A fused computation projection or precise rejection. This is still semantic shape, not C.

**Identity and alignment**

Kernel, iteration axis, stream, access, producer, sink, result, memory object, and provenance
identity.

**Rejections**

Unsupported domain/result/operator, missing bounds or noalias evidence, unsafe access,
incompatible schedule, unsupported window/tail, and capacity/shape contradiction.

**Consumers**

Memory-use construction and materialization.

**Evidence**

`lua/lalin/impl/stencil_kernel.lua`, stencil schema/tests, kernel-stencil canonical tests,
access-layout tests, and source fusion tests.

## O22 — Memory-coordinate materialization

**Inputs**

Accepted fused computation, iteration shape, memory-object/access evidence, element layouts,
windows, strides, offsets, and target representation.

**Decision**

Establish one ordered memory-use topology and derive coordinates, address bases, cursors,
window behavior, dereference widths, bounds behavior, and pointer qualification. Admission
requires known bounds, nontrapping or proven-safe access, movable memory effects, exact
provenance, and exact declared pairwise noalias before `restrict`. Pinned or checked-trapping
accesses do not silently proceed.

**Persistent output**

A memory-use alignment, coordinate facts, and physical address plan or typed rejection.

**Identity and alignment**

Memory-use occurrence, stream/access, object/base, iteration axis, coordinate, cursor, and
address identity. A width or noalias property must trace to declared/proven evidence.

**Rejections**

Coordinate disagreement, unknown stride/extent, invalid window, unsafe dereference, missing
alignment, contradictory alias evidence, unsupported multidimensional form, overflow, pinned
or immovable access, potentially trapping access, and missing exact noalias provenance.
Reject-boundary windows are never emitted as unchecked loads; a nonzero reject displacement
requires a narrow affine interior-domain proof.

**Consumers**

C fragment materialization and backend validation.

**Evidence**

`CMatMemoryUseSpine`, `LowerCMatCoordinateFacet`, coordinate/address-plan implementations,
CMat coordinate/environment tests, restrict tests, and counted-fragment GCC tests.

## O23 — Fragment materialization and assembly

**Inputs**

Accepted fused shape, memory coordinates/address plan, schedule, baseline code function,
control topology, coverage, and target.

**Decision**

Materialize deterministic C-shaped fragments, splice them only where dominance and coverage
permit, preserve uncovered baseline behavior, assemble locals/helpers/blocks, and reject
partial or conflicting contributions. Fusion/admission is decided once upstream; assembly
may close coordinates and validate contributions but may not construct a second fusion verdict
or duplicate access, alias, proof, sink-index, or write facts.

**Persistent output**

A complete backend-function assembly or typed assembly rejection.

**Identity and alignment**

Function, fragment, covered block/loop, local, helper, materialized use, and emitted block
identity.

**Rejections**

Invalid coverage, dominance failure, duplicate contribution, missing coordinate, unsupported
closed form, fragment emission failure, helper conflict, and incomplete assembly.

**Consumers**

Backend-unit construction.

**Evidence**

`lua/lalin/impl/lower_emit_c/{materialize,coordinates,address_plan,fragment,assembly}.lua`,
lower CMat assembly/environment tests, closed-form rejection tests, and fusion GCC tests.

## O24 — Backend-unit construction

**Inputs**

Validated code, target, lowering plans, baseline functions, accepted materializations,
types, globals, data, externs, signatures, and helpers.

**Decision**

Construct one complete deterministic C backend unit with exact physical types, signatures,
storage, symbols, statements, terms, helpers, and linkage.

**Persistent output**

A backend unit or typed lowering rejection. No textual C decision belongs here unless it is
a physical C-semantic fact.

**Identity and alignment**

Backend module, function, signature, type, symbol, block, local, helper, global, data, and
extern identity, each related explicitly to its semantic source where required.

**Rejections**

Unrepresentable type/ABI, missing symbol, invalid assembly, illegal storage/linkage, target
mismatch, unresolved helper, and backend validation issue.

**Consumers**

C validation and serialization.

**Evidence**

`lua/lalin/impl/lower_emit_c.lua`, `schema/c.lua`, lower/C backend tests, target propagation
tests, and CBackendUnit nonempty tests.

## O25 — C validation and serialization

**Inputs**

Complete backend unit and its exact target.

**Decision**

Validate C-level signatures, references, blocks, memory accesses, helpers, and terminators;
then serialize deterministic C source and header text without changing semantic decisions.

**Persistent output**

Validated emitted C source/header or typed C validation/emission rejection.

**Identity and alignment**

Backend identities and symbol names. Serialization order must be deterministic and derived
from declared backend order, not table iteration.

**Rejections**

Invalid backend reference, signature mismatch, illegal C type, malformed control, invalid
memory access, unsupported emitter leaf, and helper conflict.

**Consumers**

Artifact construction and external C toolchain.

**Evidence**

`lua/lalin/impl/lower_emit_c/validate.lua`, `impl/cemit_emit.lua`, CEmit tests, backend
negative tests, helper-signature tests, and emitted-C snapshots.

## O26 — GCC artifact and loaded-session boundary

**Inputs**

Validated emitted C, compile policy, output directory, compiler executable, symbol requests,
and host FFI/dynamic-loader capability.

**Decision**

Cook C with GCC, construct a shared object, load it, resolve explicitly requested symbols,
and release resources. Release is idempotent; symbol access after release fails at the host
boundary. ABI conformance of requested symbol types belongs to O31.

**Persistent output**

Artifact paths/source and a live loaded session until explicit release.

**Identity and alignment**

Artifact generation, randomized isolation path, exported symbol identity, and requested C type.

**Rejections**

Compiler unavailable, C compilation failure, dlopen failure, missing symbol, incompatible
host FFI cast, and symbol access after release. These are host-boundary failures, not
ordinary semantic result alternatives.

**Consumers**

User code and tests. Host failures remain boundary failures rather than compiler semantics.

**Evidence**

`lua/lalin/impl/compiler_api.lua`, `emit_c_compile.lua`, fresh-process tests, session
isolation tests, symbol execution tests, and all GCC regressions.

## O27 — Diagnostics and origin preservation

**Inputs**

Every authored, generated, checked, analyzed, planned, materialized, and physical operation.

**Decision**

Attach precise domain diagnostics to the concern that rejected the operation and project
them to users without discarding code, origin, explanation, or nested cause.

**Persistent output**

Typed diagnostic values throughout semantic compilation and a faithful external rendering
at API boundaries.

**Identity and alignment**

Diagnostic identity, concern/stage, source/generated origin, subject identity, and nested
rejection identity.

**Rejections**

Diagnostics themselves must reject malformed rendering inputs only at the external boundary;
semantic code must not replace typed issues with strings or issue counts.

**Consumers**

Compiler API, CLI, tests, tooling, and users.

**Evidence**

Typed issue/reject sums across schema modules and origin products. Current unmet boundary
sites are `impl/compiler_api.lua` and `compiler_c_backend.lua`, which flatten typed issues to
strings or counts; tests pin both the typed inner path and these lossy public paths.

## O28 — Target and policy propagation

**Inputs**

Selected C target, host representation, schedule/emitter capabilities, optimization policy,
and explicitly declared compiler options.

**Decision**

Project only the target facts required by each concern and ensure every physical decision
uses the same authoritative target generation.

**Persistent output**

Exact target/capability projections attached to affected layouts, schedules, plans, and
backend artifacts.

**Identity and alignment**

Target identity and policy identity across layout, code construction, scheduling, CMat,
backend construction, serialization, and GCC invocation.

**Rejections**

Unsupported target, inconsistent pointer/index width, endian mismatch, unavailable emitter,
unsupported optimization policy, and incompatible ABI.

**Consumers**

Type layout, closure representation, code construction, schedule, materialization, backend,
and artifact cooking.

**Evidence**

Target propagation tests, host-target projection, schedule capability tests, backend target
schema tests, and fresh-process GCC tests.

---

## O29 — Constant evaluation

**Inputs**

Typed literals and expressions, constant declarations, type meaning, and exact arithmetic
semantics.

**Decision**

Evaluate the declared compile-time subset exactly without executing target code in the host
compiler. A string literal denotes a `slice[u8]` whose length is the decoded byte count.
Any trailing NUL in backend storage is a physical representation choice and is not part of
the semantic slice length.

**Persistent output**

Typed constant values with source/generated provenance.

**Identity and alignment**

Constant declaration, expression occurrence, referenced binding, and source origin.

**Rejections**

Non-constant expression, arithmetic rejection under declared semantics, unresolved constant
subject, recursive evaluation, and unsupported host value.

**Consumers**

Checking, code construction, and physical initializer construction in O12/O24.

**Evidence**

`lua/lalin/impl/tree_check/const.lua`, `lua/lalin/const_eval.lua`, string-literal lowering in
`tree_code.lua`, `tests/runtime/test_const_eval.lua`, literal-sugar tests, and data GCC tests.

Construction of initializer bytes, data segments, and relocations belongs to O12 and O24
because it additionally depends on physical target layout.

## O30 — Nominal data, variant, and handle semantics

**Inputs**

Authored structs, unions/variants, handles, fields, constructors, payload patterns, qualified
names, and target layout facts.

**Decision**

Establish nominal identity, field and variant membership/order, payload shape, constructor
meaning, pattern-bind meaning, and handle domain/target declarations. Physical discriminant
and handle representation belong to O37/O31.

**Persistent output**

Checked nominal declarations and exact constructor/access/pattern facts, with physical
layout kept separate from semantic membership.

**Identity and alignment**

Nominal type, field, variant, payload binding, constructor occurrence, handle domain, and
handle target identity.

**Rejections**

Duplicate field/variant, unknown constructor, wrong payload arity/type, incomplete variant
switch, invalid payload bind, illegal nominal conversion, invalid handle target, and layout
failure.

**Consumers**

Expression/control checking, code construction, memory semantics, ABI planning, backend
type construction, and C serialization.

**Evidence**

Variant/union/handle schema leaves, parsed variant tests, multifield variant GCC tests,
qualified-handle tests, complex-type tests, type-declaration emission tests, and aggregate
lowering tests.

## O31 — ABI, foreign linkage, and callable boundary semantics

**Inputs**

Typed functions and externs, linkage/visibility declarations, calling convention, target
representation, parameter/result types, ownership erasure rules, and explicit external symbol
spelling.

**Decision**

Determine physical callable signatures, parameter/result passing, aggregate handling, symbol
visibility, external binding, and explicit symbol projection. Ownership/access erasure is
owned by O33; ABI construction consumes that decision rather than re-deciding it.

**Persistent output**

Canonical callable ABI facts and symbol/linkage projections used consistently by code
construction, backend construction, C declarations, and loaded symbol requests.

**Identity and alignment**

Semantic function/extern identity, signature identity, physical signature identity, exported
symbol identity, and target identity.

**Rejections**

Unrepresentable parameter/result, unsupported calling convention, incompatible redeclaration,
missing external symbol spelling, invalid visibility, signature collision, and target ABI
mismatch.

**Consumers**

Calls, sealed regions, code construction, backend functions/externs, C emission, GCC linking,
and user symbol lookup.

**Evidence**

Code-signature tests, extern builder/HostEval GCC test, ownership-erasure GCC test, qualified
method GCC test, helper-signature tests, type classification utilities, and target ABI tests.
Current production ABI lowering is primarily flattened descriptor construction; several
declared `Type.Abi*` and `CBackendFuncAbi` products are unused and are not requirements.

## O32 — Scalar and machine-operation semantics

**Inputs**

Typed integer, float, bit, comparison, cast, pointer, atomic, and machine operations plus
declared signedness, width, overflow, floating, alignment, volatility, and ordering facts.

**Decision**

Assign exact arithmetic and comparison meaning, preserve overflow and floating contracts,
classify legal casts, and lower operations without replacing language semantics with host Lua
or accidental C behavior.

**Persistent output**

Operation semantics attached to checked/code values and exact physical operation choices at
the backend boundary.

**Identity and alignment**

Operation occurrence, operand/result value, scalar type, target representation, and proof
identity where optimization depends on arithmetic facts.

**Rejections**

Unsupported operation/type pair, illegal cast, undefined shift/width, unavailable overflow
semantics, unsupported atomic ordering, incompatible pointer arithmetic, and backend inability.

**Consumers**

Checking, value analysis, flow recurrence analysis, memory indexing, kernel recognition,
backend construction, and serialization.

**Evidence**

Core scalar/operator tests, expression operator contracts, type classification tests,
code-to-C instruction tests, unary emitter tests, parsed expression GCC tests, and code-value
analysis.

## O33 — Ownership, access, and erasure semantics

**Status**

Required by the language model; current production proves physical erasure but does not yet
enforce the complete ownership/lease rules below.

**Inputs**

Authored ownership/access roles, handles, pointers/views/slices, bindings, calls, assignments,
returns, regions, contracts, store effects, and ABI boundaries.

**Decision**

Track owned obligations and temporary access through typed control; establish when access is
preserved or invalidated; and produce one explicit erasure projection after all semantic
consumers have used the facts. ABI construction consumes that projection.

**Normative rules**

- `var owned T` is rejected; owned authority moves through explicit bindings, returns, jumps,
  continuations, and consuming operations.
- An owned value is discharged or transferred exactly once. It is not copied as plain `T`,
  placed in durable storage by accident, or cleaned up by an implicit destructor.
- Leases are rejected in struct fields, stored union payloads, const/statics, arrays,
  closure-like durable aggregates, function results, and encoded sealed-region result objects.
- A lease cannot be passed to a retaining plain pointer/view parameter; the callee requires
  a lease/noescape contract.
- Preserve/readonly operations retain access validity. Explicit invalidate operations revoke
  it; an unannotated mutable pointer/view operation is conservatively invalidating.
- An invalidating operation cannot run while conflicting leases from the same store are live.
- Anonymous boundary leases and store-origin leases remain distinct; a store lease names its
  domain-origin parameter.

**Persistent output**

Typed ownership/access facts, live-owned-set transitions, lease-origin/effect facts, and one
explicit erasure projection at the physical ABI/backend boundary.

**Identity and alignment**

Binding, value, handle, store/domain, memory object, access occurrence, lease origin, control
edge, call boundary, and erased physical value identity.

**Rejections**

Illegal copy or drop of owned authority, double discharge, `var owned`, durable lease
position, lease escape, retaining call, conflicting invalidation, incompatible transfer, use
outside lifetime, invalid handle operation, and premature physical erasure.

**Consumers**

Checking, closure conversion, contracts, memory/effect semantics, ABI planning, and backend
construction.

**Evidence**

Binding/handle vocabulary, qualified-handle tests, memory provenance and contract tests, and
`test_lalin_ownership_erasure_gcc.lua`. The GCC test proves only ABI erasure; it does not
prove the pending borrow/owned enforcement rules.

## O34 — Lowering strategy selection

**Inputs**

Validated baseline code, optional semantic proofs, candidate kernel/schedule/fusion or
closed-form decisions, and target emitter capabilities.

**Decision**

Select baseline, kernel/fused, or closed-form lowering strategy after complete typed
admission, and retain rejected alternatives. This concern commits to a strategy; it does not
own the semantic proofs used for admission.

**Cross-cutting law**

An optional optimization may not weaken semantics. Failed optional admission preserves the
correct baseline whenever one exists. Program rejection occurs only when the language
requires a specialized semantic form or no correct baseline/backend lowering exists.

**Persistent output**

An explicit selected strategy with proof references, rejection history, covered control, and
a complete baseline path where legal.

**Identity and alignment**

Candidate subject, baseline region, selected strategy, covered control, referenced proof, and
fallback reason identity.

**Rejections**

Unproven optimization, unsupported emitter, incomplete coverage, unsafe memory/effect,
unsupported shape, or failed materialization. These reject the optional strategy, not
automatically the program.

**Consumers**

Fragment assembly, backend construction, diagnostics/remarks, and conformance testing.

**Evidence**

Kernel/schedule no-plan behavior, lower strategy selection, fold/window rejection tests,
grid/tiled non-fusion assertions, conservative scalar paths, and active GCC conformance tests.
Experiments do not define this obligation.

## O35 — Determinism and compilation isolation

**Inputs**

A complete compilation request, source/builder input, target and schedule capabilities, output
policy, and process-local compiler services.

**Decision**

Ensure semantic result and emitted-C content depend only on declared input; prevent identities,
interned values, helper order, diagnostics, or mutable state from leaking between sessions.
Artifact filesystem paths may be randomized for dynamic-loader isolation and are not part of
semantic determinism.

**Persistent output**

A compilation generation whose semantic worlds and artifact are isolated from every other
request.

**Identity and alignment**

Compilation/session generation, schema context, program identity, deterministic declaration/
function/helper order, emitted-C content identity, and loaded-session identity.

**Rejections**

Cross-session value admission, stale generation, nondeterministic duplicate identity, output
collision, symbol use after release, and hidden ambient-state dependency.

**Consumers**

Every concern, test harnesses, parallel/fresh-process compilation, and artifact users.

**Evidence**

Compile-session isolation tests, fresh-process loader/compiler/kernel tests, deterministic
UI spine test, module emission ordering tests, and repeated GCC compilation tests.

Typed-diagnostic preservation (O27), target consistency (O28), optimization equivalence (O34),
and determinism (O35) are cross-cutting laws. They constrain owning concerns and must not be
turned into generic diagnostics/target/optimization/determinism machines.

## O36 — Type meta-properties and staged synthesis

**Inputs**

A type meta-property query, exact role, host hook assignment, schema context, and staged Lua
capability.

**Decision**

Resolve and invoke declared hooks such as `__typename`, `__getentries`, `__getdecls`,
`__getmethod`, `__methodmissing`, `__entrymissing`, `__apply`, and `__cast`; adapt the result
to the requested role; and materialize ordinary declarations, fragments, ASDL values, or a
typed diagnostic. A compiled method call is always a statically materialized artifact, never
a runtime method-missing branch.

**Persistent output**

Generated authored declarations/fragments with generated origin and exact schema-context
provenance.

**Rejections**

Unknown hook, unresolved top-level hook assignment, unsupported hook result, role mismatch,
recursive/unbounded synthesis, and attempted dynamic fallback in compiled code.

**Evidence**

Type meta-property and top-level assignment surfaces in the language reference and DSL,
HostEval role tests, builder/HostEval GCC tests, and current method-synthesis implementation.

## O37 — Target-dependent layout projection

**Inputs**

Target-independent type meaning, nominal declarations, target representation, and exact ABI
layout policy.

**Decision**

Derive size, alignment, field offsets, variant discriminant/payload representation, handle
representation, aggregate ABI shape, and target-dependent physical classification.

**Persistent output**

A layout projection explicitly tied to type identity and target identity.

**Rejections**

Incomplete recursive layout, unrepresentable field/payload, invalid alignment, target width
mismatch, unsupported aggregate ABI, and layout overflow.

**Consumers**

Closure environment representation, code construction, constants/data initialization, ABI
planning, memory semantics, and backend types.

**Evidence**

Layout methods in `tree_check/module.lua` and `tree_check/layout.lua`, type size/alignment
tests, aggregate tests, target propagation, and backend type tests.

## O38 — Closure environment representation

**Inputs**

O06 capture projection, O37 layout projection, target identity, and callable ABI facts.

**Decision**

Assign deterministic environment field order and representation, rewrite captured accesses,
and construct the callable closure representation without changing captured binding identity.

**Persistent output**

Closure-converted/unchanged program plus environment representation or typed unsupported
result.

**Rejections**

Impossible environment layout, unsupported capture representation, illegal escape, target
incompatibility, and unsupported nested function shape.

**Evidence**

`impl/tree_closure.lua`, closure conversion/capture/schema tests. No active GCC test currently
executes a captured closure; this is a behavioral coverage gap.

## O39 — Handle-domain contract and trusted representation crossing

**Status**

Documented requirement; core declaration-time domain enforcement and `repr`/`from_repr`
trusted crossing are not implemented in the active checker.

**Inputs**

A handle declaration with domain and target, candidate resolver operation, success protocol,
and any trusted physical representation crossing.

**Decision**

Require `Domain(A,H)`: handle `H` names domain `A` and target `R`; `A` provides an owned
resolver taking `(self,H)` whose successful outcome grants `lease("self", ptr[R])`. Safe
casts never convert handles to or from raw scalars. Only explicit trusted representation
operations may cross that boundary.

**Rejections**

Missing resolver, wrong resolver subject, missing lease grant, target mismatch, unsafe scalar
cast, invalid representation width, and untrusted `repr`/`from_repr` use.

**Evidence**

Language-reference Domain/handle rules and qualified-handle/erasure tests. Existing tests
prove parsing, nominal identity, and erasure—not declaration-time Domain enforcement.

## O40 — Unique entity declaration

**Status**

Documented semantic distinction; direct parsed lowering is currently pending.

**Inputs**

A plain or `unique` struct declaration and the storage/allocation domain that establishes
entity identity.

**Decision**

Distinguish value products compared/copied by fields from unique entities identified by
allocation/canonical handle. A unique declaration does not invent implicit global allocation
or pointer identity.

**Persistent output**

Nominal entity-kind fact consumed by storage, handle, comparison, and projection concerns.

**Rejections**

Unique declaration without an identity authority, illegal value-style copy/equality, and
unsupported direct lowering.

**Evidence**

Language-reference unique-struct status and current handles/stores guidance. No active parsed
unique lowering test exists.

---
## Test-Suite Scope

The semantic ledger covers the active Lalin compiler and its direct substrate contracts.
The repository currently contains 174 Lua files under `tests`, of which `tests/run.lua`
discovers 149 active tests; fixtures and helper files are not conformance tests.

- **Direct compiler conformance:** `tests/frontend`, `tests/schema`, `tests/code_ir`,
  `tests/compiler_process`, and `tests/c_backend`. Every active test in these directories
  must map to one or more obligations.
- **Compiler primitive evidence:** scalar/type/ABI/source-index tests under `tests/core` and
  constant evaluation under `tests/runtime`.
- **ASDL substrate evidence:** `tests/asdl`; these constrain the schema runtime but are not
  language/compiler semantic obligations.
- **LLBL workbench evidence:** LLBL tests under `tests/core` and
  `tests/c_backend/test_llbl_c.lua`; these constrain generic grammar, HostEval, region, C-text,
  formatting, indexing, and process substrate beneath Lalin, not the Lalin compiler model.
- **Independent application systems:** `tests/ui`, `tests/mlui`, and `tests/hyper`; these are
  not compiler obligations, though they exercise the compiler when they compile Lalin code.
- **Experimental evidence:** `tests/experiments`; no experiment defines compiler semantics
  by itself. A behavior becomes required only when an active compiler contract or production
  test also claims it.

The completed test audit maps all active direct compiler-conformance tests to obligations.
Structural shape tests are evidence about the current implementation, not automatic semantic
requirements. In particular, `test_bootstrap_boundaries.lua` pins unused LalinPhase/Exec/
Project vocabulary; exact-field tests for Lower/Kernel/Stencil/CMat/Region/Closure pin current
representations and must be reconsidered during cutover rather than copied.

Behavioral coverage gaps found by the audit:

- O06/O38: no captured closure is compiled and executed through GCC;
- O14: no dedicated test derives loop topology from authored code;
- O15: induction derivation is tested indirectly through GCC behavior but mostly asserted on
  hand-built fixtures;
- O27: public compiler diagnostics remain count/string flattened;
- O07: forbidden `for`/`while`/`break`/`continue` rejection lacks focused coverage.

`test_source_text_apply.lua` is source-editor/tooling behavior outside this compiler ledger.
Fresh-process tests that only assert retired modules are absent are ownership hygiene, not
language semantics. Documented-but-pending features O33/O39/O40 remain explicit requirements
with pending status rather than being falsely credited to existing tests.

## Active Schema Classification Outcome

The schema audit classified current vocabulary as evidence, not as the replacement design.

**Required semantic evidence:** active authored/checking/code/control/flow/value/memory/effect/
kernel/schedule/fused-shape/materialization/backend facts corresponding to O01–O40. Their
behavior must survive, but their current products and namespace boundaries are not presumed
correct.

**Duplicated representation:**

- `Bind.Env` versus live checking scope/environment facts;
- `Bind.Residence*`, code residence, and backend residence;
- dead `Type.Abi*`/`CBackendFuncAbi` plans versus live flattened signature construction;
- dead `CodeBack*` projections versus active lower/C backend facts;
- dead kernel-rewrite decisions versus active lowering strategy;
- dead stencil artifact/producer-execution vocabulary versus active CMat materialization;
- dead tree control facts versus active checking/control diagnostics.

**Speculative or unwired vocabulary:**

- generic `LalinPhase` machine/plan/world execution model;
- `LalinExec` fragment plan and its uncalled implementation;
- retired `LalinBackend.Cmd` program/tape model;
- broad unused `LalinHost` declaration/layout model;
- backend annotation vocabulary never constructed;
- metastencil graph, realized vector schedules, and artifact vocabulary with no producer;
- empty RegionBundle projection;
- unused lease/interval/proof subsets that current memory analysis never constructs.

**Tooling outside the compiler model:** `LalinSource` editor indexing/versioned edits and
`LalinProject` task tracking. These may remain valid tools but do not dictate compiler objects.

**Physical boundary evidence:** active `CBackend*`, C validation/emission, compiler artifact,
GCC, dynamic-loader, and FFI session values. Their physical facts remain boundary-owned.

**Accidental plumbing:** free-function semantic libraries, class/tag dispatch in document/
surface/module coordinators, repeated temporary semantic indexes, count-only diagnostics, and
large pass-shaped input/state records. These are behavioral archaeology, not target vocabulary.

No replacement type is justified merely because an item above exists today.

## Obligation Separation Review

The ledger currently records requirements, not final concern boundaries. The following pairs
must remain separate during review even if the eventual model assigns one coordinating
machine:

- document ingestion versus builder/document convergence;
- nominal semantic membership versus target-dependent physical layout;
- checking versus post-region authoritative rechecking;
- open expansion versus sealed call/frame materialization;
- code construction versus structural validation;
- control topology versus flow interpretation;
- flow recurrence facts versus algebraic/value facts;
- memory safety/alias facts versus effect summaries;
- kernel recognition versus schedule selection;
- fused semantic projection versus physical coordinate materialization;
- coordinate materialization versus fragment assembly;
- backend-unit construction versus C serialization;
- compiler semantics versus GCC/dynamic-loader boundary behavior.

Combining any pair requires proof that it has one operation, lifetime, invalidation frontier,
diagnostic authority, and consumer contract. File proximity or current pass order is not
sufficient evidence.

## Cross-Obligation Identity Questions

These must be answered before defining spines:

1. Which authored identities survive checking unchanged?
2. Does code construction preserve function identity or establish a new physical identity?
3. Are block, instruction, terminator, and value identities one structural family?
4. Is loop identity intrinsic to control topology or created by flow interpretation?
5. Does a memory object have identity independent of the value/place that revealed it?
6. Is a memory access a code occurrence, a semantic event, or both?
7. At what boundary does a kernel become a new entity rather than a projection of a loop?
8. Does a schedule have durable identity or is it only a decision facet of a kernel?
9. Does fused materialization preserve kernel/access identities or create physical-use
   identities with provenance links?
10. Which backend identities are required externally, and which are internal serialization
    addresses?

## Cross-Obligation Ownership Review

These conclusions constrain Step 2 but do not yet prescribe ASDL products:

1. **Name resolution:** one declaration-identity concern publishes separate value/type, field,
   and region-target projections from one authored namespace generation. No evidence currently
   requires independently invalidated resolution machines.
2. **Layout:** target-dependent layout is O37, separate from target-independent O04 type
   meaning.
3. **Post-region checking:** O11 is a region transaction invoking the same checking authority,
   not a second type machine.
4. **Topology and flow:** O14 is a total structural projection of O13-validated code; O15 owns
   interpretation of loops, inductions, domains, and trips.
5. **Value-copy versus recurrence:** O16 owns value-copy canonicalization and algebraic facts;
   O15 owns induction/recurrence interpretation. Memory aliasing remains O17.
6. **Contracts:** O08 terminates in canonical checked subjects. O17 alone maps those subjects
   to memory-object evidence; O18 consumes canonical contract/memory facts rather than
   reinterpreting authored syntax.
7. **Trip facts:** O15 owns trip/domain evidence. Kernel, schedule, and fused computation borrow
   or project that evidence without inventing a new trip authority.
8. **Kernel versus fused computation:** O19 recognizes semantic kernels; O21 projects an
   admitted kernel/schedule into a fused computation shape. They have different decisions and
   rejection authority.
9. **Coordinates versus fragments:** O22 owns address/coordinate facts; O23 consumes them to
   materialize and assemble fragments. Emission cannot revise coordinate truth.
10. **Artifact cooking:** O26 is a host-boundary object, not a compiler semantic machine.
11. **Authored ingestion:** O01 and O02 are two input surfaces of one authored-program concern;
   they must converge without separate semantic programs.
12. **Cross-cutting laws:** O27, O28, optimization equivalence within O34, and O35 constrain all
   owners and must not become generic machines.

The unresolved questions above are identity questions, intentionally deferred to Step 2.

## Known Documentation Conflicts

Step 1 resolved the intended obligation where active architecture and older prose disagree:

1. A semantically valid source loop may retain conservative baseline control when optional
   kernel/fusion admission fails. Missing optimization proof is not by itself a language
   rejection. Language-reference prose requiring every unrecognized producer/sink loop to
   reject is stale and must be corrected.
2. Domain(A,H), complete lease/owned enforcement, trusted handle `repr` crossing, and parsed
   `unique` lowering are documented requirements but are not implemented. O33/O39/O40 mark
   them pending instead of pretending existing erasure tests prove them.
3. RegionBundle is speculative vocabulary with an always-empty projection, not a current
   language/compiler obligation.
4. LLBL owns generic HostEval delivery and role algebra; Lalin owns adaptation into Lalin
   semantic roles. Older LLBL migration prose describing a dual HostEscape path is stale.
5. Architecture references to `compiler_schema_c_backend.lua` and a nonexistent
   `test_schema_ownership_inventory.lua` are stale. The active backend entry is
   `lua/lalin/compiler_c_backend.lua`; the ownership guard still needs to be built.

These documentation defects are follow-up edits. They do not become replacement-schema
requirements by accident.

## Step 1 Exit Verdict

The semantic-obligation step is complete enough to begin Step 2 because:

- forty obligations now cover active behavior and documented pending semantics;
- each decision class is assigned to a concern or identified as a cross-cutting law;
- active direct compiler tests were mapped and structural-only tests classified;
- behavioral test gaps are explicit rather than hidden;
- every active schema namespace/cluster is classified as required evidence, duplicate,
  plumbing, speculative/unwired, tooling, or physical boundary;
- ownership collisions discovered by review were split or assigned one authority;
- current implementation order and product names are not treated as the new model;
- no replacement ASDL type, spine, facet, world, or machine has yet been proposed.

Step 1 does not answer which identities survive or where new identity is created. That is the
purpose of Step 2.

## Next Step — Fundamental entities and identity

For every candidate entity, Step 2 must establish:

- whether it is an entity or a field-described value;
- its creation authority;
- its lifetime and invalidation boundary;
- whether identity survives each semantic projection;
- whether references require handles, direct contained identity, or temporary access;
- whether a later boundary preserves identity or creates a new entity with provenance;
- which current IDs are semantic, physical, duplicated, or encoded-name artifacts.

No machine, spine, facet, or replacement phase product is defined until that identity model
is reviewed and closed.
