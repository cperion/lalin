# The Lalin Design Bible

## Object-machines are the center of gravity

**Status:** design canon for Lua ASDL systems and compiled Lalin systems.

The entire method begins with one law:

> **One concern → one object-machine → one semantic authority.**

A system is a composition of objects that own meaning. Each object-machine owns one
concern: its persistent facts, identities, operations, protocols, diagnostics, stores,
invalidation rules, and derived projections. Objects communicate through typed values and
typed control. No concern is smeared across helpers, side tables, drivers, callbacks, or
parallel representations.

Everything else in this book follows from that law:

```text
persistent fact       → object frame or owned store
durable identity      → entity or handle
immediate decision    → region continuation
case-specific behavior→ concrete ASDL/Lalin leaf method
derived fact          → readonly projection
shared alignment      → spine
one semantic plane    → facet
reusable domain state → world
stored/queued choice  → encoded boundary record + one consumer
external boundary     → sealed function, artifact, or bridge
family variation      → Lua factory
```

This is not class-oriented object programming. There is no inheritance tree, universal
base object, vtable culture, or getter/setter shell. An object is an explicit owner of a
semantic concern and the operations that give its facts meaning.

---

# 1. The object-machine law

## 1.1 What an object-machine owns

An object-machine may own:

- durable entity identity;
- a retained frame or store, when the concern genuinely retains state;
- exact capacities and storage lifetimes;
- methods and regions implementing its operations;
- resolver regions for handles in its identity domain;
- diagnostics and rejection vocabulary;
- generations, epochs, and invalidation authority;
- readonly projections published to other objects;
- one instruction language, when the concern consumes stored commands;
- one physical boundary image, when serialization or ABI portability requires one.

It does not automatically need all of these. A stateless compiler concern may own only an
operation over immutable ASDL values. A store may own identity, bytes, generations, and
resolver protocols. A serializer may own no durable state at all.

Do not invent state to make something look object-oriented. The point is ownership, not
ceremony.

## 1.2 One fact, one owner

Every persistent semantic fact has exactly one authority that may establish its meaning.
Other objects may consume or project the fact. They may not reinterpret it, maintain a
synchronized copy, or silently strengthen it.

Examples:

- the type concern owns type equality; a backend consumes the decision;
- the memory concern owns alias and bounds evidence; a C emitter may not infer `restrict`;
- the layout concern owns geometry; a renderer consumes rectangles;
- the terminal diff concern owns patches; the ANSI encoder consumes them;
- a store owns handle liveness; callers receive access through its resolver protocol.

If two modules both answer the same semantic question, the design has duplicate authority.
If no value or object clearly owns the answer, the design has missing authority.

## 1.3 One operation, one owner

An operation belongs to the object whose invariants it interprets or changes.

A coordinator may sequence operations:

```text
resolve → check → project → materialize
```

but it may not duplicate child validation, inspect child encodings, or modify child stores.
A coordinator owns ordering only.

## 1.4 When to split objects

Split one proposed machine into two when the concerns have genuinely independent:

- semantic decisions;
- retained state or storage;
- identity domains;
- invalidation conditions;
- diagnostics;
- capabilities;
- consumers;
- lifetimes;
- performance or trust boundaries.

Do not split because two operations run at different times or live in different files.
Chronology is not ownership.

Merge proposed objects when one cannot be understood, validated, or changed without the
other and their boundary merely forwards the same facts and outcomes. That boundary is a
pass-through abstraction, not a concern.

## 1.5 Objects form a graph, not a hierarchy

Objects reference, borrow from, project to, and invoke one another. Their structure is a
graph of explicit authorities:

```text
AuthoredProgram
    │ readonly input
    ▼
TypeMachine ──publishes──> TypedProgram
    │                         │
    │ invokes                 │ consumed by
    ▼                         ▼
LayoutMachine             CodeMachine
```

No object becomes a universal context. No root object owns every child fact merely because
it coordinates the system.

---

# 2. Two realizations of the same model

Lalin has a bootstrap/compiler realization in Lua ASDL and a compiled realization in Lalin.
They are architecturally isomorphic.

## 2.1 Lua ASDL realization

Lua ASDL is not compiled Lalin, and its “object” is not necessarily a mutable runtime
instance or a product named `FooMachine`. In Lua ASDL, an object-machine is a closed semantic
family organized around one distinguished ASDL receiver:

```text
distinguished ASDL receiver
  + precise input products
  + immutable frames/projections when needed
  + result sums
  + methods on concrete variant leaves
```

The receiver is the semantic entrypoint for the concern. It may have one of three shapes.

### Request-owned operation

A stateless compiler concern is often best represented by a request product:

```lua
product. FlowRequest {
  code [Code.Program],
  topology [Control.Topology],
}

sum. FlowResult {
  FlowProjected { projection [Flow.Projection] },
  FlowRejected { issues [many [Flow.Issue]] },
}

function FlowRequest:project()
  return self.code:project_flow(FlowInput(self.topology))
end
```

The request is the transaction boundary and concern-level receiver. No retained machine
instance is required.

### Explicit authority product

Use an explicit machine product when the concern genuinely retains configuration, policy,
capability, identity, or a reusable service boundary:

```lua
product. LayoutMachine {
  target [Target.Model],
  policy [Layout.Policy],
}

product. LayoutRequest {
  program [Typed.Program],
}

function LayoutMachine:project(request)
  return request.program:project_layout(LayoutInput(self.target, self.policy))
end
```

Do not create empty `*Machine` products everywhere merely to satisfy terminology.

### Immutable frame transition

When a concern genuinely accumulates state, represent the state as an explicit ASDL frame
and return a new frame from each transition:

```lua
product. WriterFrame {
  generation [Generation],
  nodes [many [Node]],
  scopes [many [Scope]],
}

sum. WriterOpenResult {
  WriterOpened { frame [WriterFrame], identity [NodeIdentity] },
  WriterFull { frame [WriterFrame], capacity [Capacity] },
}
```

ASDL semantic methods do not mutate hidden Lua fields. The previous frame remains an ASDL
value; the result carries the next frame.

### Concern owner and case owner

The distinguished receiver owns the complete operation. Concrete ASDL leaves own individual
semantic cases:

```lua
function TypeCheckRequest:execute()
  return self.program:typecheck(TypeProgramInput(self.target))
end

function ExprInt:typecheck(input)
  return TypeExprChecked(input.expected, self)
end

function ExprCall:typecheck(input)
  return self.callee:check_call(TypeCallInput(input.scope, self.args))
end
```

Wrong:

```lua
local handlers = { ExprInt = check_int, ExprCall = check_call }
return handlers[node.kind](node, ctx)
```

Therefore the Lua-ASDL form of the central law is:

> **One concern → one distinguished ASDL semantic receiver → one authority.**

That receiver may be a request, explicit authority, immutable frame transition, intrinsic
entity, or result leaf continuing an operation. “Object-machine” names this ownership shape;
it does not force a mutable object, an OO class, or a `Machine` suffix.
## 2.2 Compiled Lalin realization

```text
ASDL product          → struct
ASDL unique product   → unique struct
ASDL sum leaf         → union leaf or encoded physical record
Lua method            → qualified function
typed operation result→ qualified region protocol when consumed immediately
identity reference    → qualified handle
retained machine      → struct/unique struct with owned methods and regions
```

Use Lua ASDL for bootstrap semantics, schema tooling, staging, and family generation. Use
compiled Lalin when the semantic object itself must execute as fast monomorphic code.

## 2.3 The rule for alternatives

There is no contradiction between ASDL sums and Lalin protocols. They serve different
execution media.

### Immediate alternatives in compiled Lalin

When a producer chooses and the caller acts immediately, use a region protocol:

```lln
region Store.borrow(self [ptr [Store]], ref [StoreRef];
  borrowed(record [lease [ptr [Record]]]),
  stale,
  missing
 )
```

The caller wires continuations. It does not receive and switch on a boxed result.

### Alternatives in bootstrap Lua ASDL

Lua has no typed CFG continuation system. A named ASDL result sum is the typed encoding of
the operation outcome. Its concrete leaves own the next behavior:

```lua
function ResolveFound:continue_check(input)
  return self.value:check(input)
end

function ResolveMissing:continue_check(input)
  return TypeRejected(TypeIssueMissing(self.name))
end
```

The caller invokes the result method; it does not manually inspect `kind`, `tag`, or class.

### Stored or portable alternatives

A queued event, AST node, bytecode instruction, wire message, or ABI result is stored data.
Encode it physically, then give the encoding exactly one named consumer object/region.
The encoding is not the semantic authority; the consumer is.

Therefore:

```text
immediate compiled choice → protocol
bootstrap typed outcome   → ASDL result sum with leaf-owned behavior
stored/queued choice      → encoded fact + one consumer
ABI choice                → encoded boundary + decoder/consumer
```

---

# 3. The anatomy of an object-machine

## 3.1 Entity

An entity is a stable user- or compiler-visible thing with identity. Identity is warranted
when references must survive copying, movement, phase projection, reuse, or time.

Examples: a declaration, function, component, memory object, terminal session, store slot,
or compiled artifact.

Do not assign identity to every record. Values that are fully described by their fields are
products, not entities.

## 3.2 Frame

A frame is the precise retained state of one machine. It contains only facts intrinsic to
that machine's continued operation.

A frame is not:

- a compiler-wide context;
- an option bag;
- a collection of every downstream fact;
- a place to cache facts owned by other machines;
- a mutable table hidden behind an ASDL constructor.

For pure compiler operations, the input and output worlds may make a retained frame
unnecessary.

## 3.3 Store

A store owns bytes, capacity, liveness, and an identity namespace. If stable external
references exist, the store owns their handles, generation facts, resolver protocols, and
invalidation operations.

```text
Store object
  owns records and capacity
  owns slot/generation liveness
  resolves StoreRef
  grants temporary leases
  invalidates leases on reset/free/compact/reuse
```

## 3.4 Operation

An operation is a method or region attached to the object or semantic leaf that owns its
meaning.

Operation inputs must be narrow and named. Results must be typed outcomes. If an operation
requires a broad `ctx`, `env`, `state`, or options product, the concern boundary is probably
wrong.

## 3.5 Diagnostic authority

Each machine owns diagnostics for decisions it makes. A later machine may wrap a rejection
with provenance, but it must not replace the original typed reason with a string or generic
failure.

Public rendering may format diagnostics. Formatting is not semantic ownership.

## 3.6 Generation and invalidation

A machine that retains or publishes reusable facts owns their generation or epoch. It must
state exactly what invalidates them.

```text
This projection remains valid until __________________ changes.
```

If that sentence cannot be completed, the projection is not designed.

---

# 4. Object–Region–Projection

The canonical systems pattern is:

> **Persistent fact → object frame**
> **Decision → region continuation**
> **Derived fact → readonly projection**
> **Queued or portable fact → encoded boundary record with one consumer**

## 4.1 Persistent fact belongs to the object

State that survives an operation is a field of the owning object frame or store. It is not a
Lua upvalue, side table, global, or convention between calls.

## 4.2 Decision belongs to control

A decision that is consumed now is control. In compiled Lalin, expose it as named region
continuations. In Lua ASDL, expose it as a named result sum whose leaves continue behavior.

Do not collapse semantic alternatives into:

- `nil`;
- booleans;
- status integers;
- optional soup;
- `{ ok = ..., reason = ... }`;
- exceptions between ordinary semantic operations.

## 4.3 Derived fact belongs to a projection

A projection is immutable evidence derived from an authoritative input. It names:

- its source identity or spine;
- the facts it derives;
- enough provenance to reject stale or misaligned use;
- no unrelated concern.

Do not mutate source objects to attach later-phase facts.

## 4.4 Portable fact belongs to a boundary

Serialization, queues, arrays, command buffers, source files, and ABIs require stored
representations. Their tags, offsets, and payload encodings are physical facts. One decoder
or consumer owns their meaning.

A boundary image is justified by portability, sharing, storage, or ABI shape—not by a desire
to make the whole system look like a virtual machine.

---

# 5. Spines and facets

Spines and facets are how concern-owned objects share structure without merging authority.

## 5.1 Spine

A spine is a stable alignment product. It carries only facts that several semantic planes
must share:

- identity;
- topology;
- order;
- addressability;
- origin;
- ranges or structural relations.

A spine does not own all facts about its entities. It is the structural coordinate system.

### Spine laws

1. One generation has one authoritative spine allocation/value.
2. A spine is immutable within that generation.
3. A later concern borrows or references the spine; it does not casually copy its topology.
4. Identity resolution has one owner.
5. A new spine is created only when a projection establishes genuinely new structural
   identity.
6. A spine never becomes a giant lower node containing every semantic plane.

## 5.2 Facet

A facet is one semantic plane aligned to a spine and produced by one concern.

Examples: type, style, geometry, effect, memory safety, ownership, schedule, glyph, or
backend-coordinate facts.

### Facet laws

1. Every facet has one producer machine.
2. A facet contains one concern.
3. A facet explicitly aligns to its spine or spine generation.
4. Dense facets state one-entry-per-spine-item alignment.
5. Sparse facets carry explicit spine identity or slot.
6. A facet cannot recreate parent/child or CFG topology.
7. Independent invalidation requires independent facets.
8. Consumers cannot mutate another machine's facet.

## 5.3 Dense and sparse facets

Dense:

```text
spine[i] ↔ type_facet[i]
```

Every spine item has one corresponding fact.

Sparse:

```text
text_entries = { { node = 4, ... }, { node = 9, ... } }
```

Only relevant entities have entries, and every entry names its alignment explicitly.

## 5.4 Why the separation matters

Without a spine, each concern tends to rebuild its own tree or CFG. Without facets, one
giant node accumulates source, type, layout, control, memory, and backend fields. Both shapes
create synchronized copies and unclear invalidation.

The law is:

> **Spine owns shared structure. Facet owns one concern's meaning. Machine owns the facet.**

---

# 6. Worlds and projections

A world is an immutable domain state published at a real semantic or reuse boundary.
It is not the center of the architecture. The object-machine is the authority.

## 6.1 When a world is justified

Create a world when:

- several consumers need the same coherent set of facts;
- the set has one explainable validity boundary;
- the product is reusable or publishable;
- the machine must expose a readonly snapshot instead of its private frame.

Do not create a world after every chronological step. Do not use worlds to rename pass
plumbing.

## 6.2 World contents

A world may contain:

- one spine;
- facets currently valid for that spine;
- source generation/provenance;
- target facts that alter semantics;
- exact publication identity.

It must not contain unrelated knobs, caches, diagnostics from every phase, or another
machine's mutable frame.

## 6.3 Reuse frontier

A reusable world must complete:

```text
This world changes exactly when __________________ can no longer be reused.
```

Two tests expose bad worlds:

```text
false invalidation: world changed but all consumers would produce the same result
stale reuse:         world stayed equal but some consumer must produce a new result
```

Fix the product or ownership boundary. Do not patch it with ambient cache keys.

## 6.4 Projection chain versus pass pile

A sequence of projections is valid when each arrow answers a distinct semantic question.
It is a pass pile when boundaries merely mirror execution order and no new owned knowledge
can be named.

Ask at every arrow:

- Which object owns this decision?
- What becomes known?
- Why must the result persist?
- Who consumes it?
- What invalidates it?

If these questions have no precise answers, remove or redraw the boundary.

---

# 7. Typed control: regions, blocks, emits, calls, and seals

## 7.1 Region

A region is an object-owned control operation: input product plus named continuation
protocol.

```text
region = input product + output protocol → one selected continuation payload
```

A protocol belongs to its consumers. Expose only distinctions callers act on. Payloads carry
facts learned on that path.

## 7.2 Block

A block is a state whose parameter list is its complete live product. Nothing survives a
jump unless the next block names it.

This forbids hidden mutable control state and makes state machines structural.

## 7.3 Jump

A jump constructs the complete target state. There is no fallthrough. Every path terminates
explicitly.

## 7.4 Emit

`emit` composes an open region by checked CFG splicing. The caller fills every continuation.
Use it for local composition when no frame is semantically required.

## 7.5 Region call

`call` creates a real sealed frame boundary for a region. Use it for recursion, profiling,
debugging, instrumentation, or independently visible activation.

Open expansion and sealed invocation are different operations and require different typed
results.

## 7.6 Function seal

A function is product-to-product and is appropriate for:

- external ABI boundaries;
- ordinary mathematical product-return operations;
- the substrate beneath a sealed region call.

Do not prematurely seal protocol-rich internal operations and then reconstruct their exits
with status codes or result objects.

## 7.7 Control laws

1. Every declared continuation is filled.
2. Every fill payload type-checks.
3. Every jump assigns all target parameters.
4. Every path terminates.
5. `emit` owns open graph expansion.
6. `call` owns sealed frame invocation.
7. Functions seal only where product-return semantics are honest.

---

# 8. Identity, memory, and access

Memory management is ordinary object ownership.

```text
stores own bytes
handles name durable identity
resolver regions grant temporary access
leases embody that access
protocols name failed resolution
invalidating operations belong to the store object
```

## 8.1 Handles

Use a handle when a reference must survive movement, reuse, serialization, compaction, or
time. A handle names an identity in one store/domain. It is not implicitly dereferenceable.

Handles may escape.

## 8.2 Leases

A successful resolver continuation may grant `lease ptr(T)` or `lease view(T)`. The lease
is a temporary access fact valid only within the granted dynamic extent and declared
noescape calls.

Leases may not escape.

## 8.3 Store authority

One store object owns:

- storage;
- capacity;
- handle namespace;
- generation/liveness facts;
- resolver operations;
- mutation and destruction operations;
- lease invalidation authority.

If these facts live in several helper modules or side maps, the store has lost ownership.

## 8.4 Raw pointers

A raw pointer is an address, not ownership, bounds, provenance, or liveness. Keep raw
pointers at ABIs, inside owning stores, or in hot kernels receiving explicit contracts.

## 8.5 Invalidating operations

Reset, free, compact, clear, publish, retire, destroy, close, and slot reuse are named
operations. An invalidating operation cannot run while conflicting leases from the same
store remain live.

## 8.6 Compiler memory evidence

Optimization consumes exact declared or derived memory evidence. It does not infer stronger
facts because an optimization would benefit.

In particular:

- no inferred `restrict`;
- no fabricated pairwise noalias;
- no dropped bounds/trap conditions;
- no movement across unresolved effects;
- no reinterpretation of a contract by each backend.

---

# 9. Composition between machines

Machines communicate through four shapes:

```text
typed input product
typed result/protocol
readonly projection/world
explicit boundary image
```

## 9.1 No foreign mutation

A machine cannot mutate another machine's frame or facet. It requests an operation or
consumes a published projection.

Pointer reachability does not grant semantic authority.

## 9.2 No generic context

A context bag hides ownership. If an operation needs five facts, determine whether:

- those facts form one real input product;
- a published world already represents their coherent state;
- the operation crosses several concerns and belongs in a coordinator;
- the proposed machine is actually several machines.

Do not solve the problem by naming the bag `Context`, `Environment`, `State`, or `Options`.

## 9.3 Keyed relations

Do not hide compiler facts in Lua maps. Model a keyed relation as a named entry product
carried under `many`. The relation owner may build a temporary index during one pure
operation, but persistent semantics remain in ASDL.

Temporary acceleration is not semantic state. It becomes schema pressure when consumers
depend on the index's order, retain it, or reconstruct the same semantic relation repeatedly.

## 9.4 Coordinator

A coordinator has one concern: sequencing a transaction across machines. It may:

- invoke child operations;
- route typed outcomes;
- construct the next exact request;
- publish the final transaction result.

It may not:

- inspect child variant tags manually;
- duplicate child validation;
- strengthen child facts;
- mutate child stores directly;
- retain a compiler-wide semantic bag.

---

# 10. Lua owns families; Lalin receives monomorphic objects

Genericity is a build-time concern. Lua factories generate concrete ASDL/Lalin families.
Compiled Lalin remains monomorphic.

A good factory parameter represents a genuine family axis: type, capacity, target platform,
or selected capability. A bad factory parameter exists for one instance or recreates runtime
option soup.

```text
generality belongs to the family design
specialization belongs to each generated object-machine
```

Instantiate only what is used. Do not pre-generate speculative matrices.

Dynamic host values cross through explicit bridge objects. Raw Lua C API calls are substrate,
not architecture. A bridge owns registry handles, stack discipline, protected calls, borrowed
strings, error decoding, and cleanup protocols.

---

# 11. The design procedure

Design is completed before implementation bodies become authoritative.

## Step 1 — State the concern

Write one sentence:

```text
This object owns __________________ and provides __________________.
```

If the sentence contains two independent nouns joined by “and,” test whether it is two
objects.

## Step 2 — Build the semantic obligation ledger

List every required behavior without copying current pass or API shapes:

- inputs;
- decision;
- persistent output;
- identities and alignment;
- rejection alternatives;
- lifetime and invalidation;
- consumers;
- proving tests.

This ledger is the completeness contract.

## Step 3 — Harvest entities and values

Identify durable entities separately from plain values. For every entity answer:

- who creates its identity;
- how long it lives;
- which references survive movement or time;
- which store/domain resolves it;
- which projections preserve it;
- which boundaries establish new identity.

## Step 4 — Assign one authority per concern

For every decision in the ledger, name exactly one owning object-machine. Find duplicate
authority and missing authority before defining fields.

## Step 5 — Draw ownership and invocation

Draw objects and arrows: owns, borrows, invokes, projects, resolves, seals. Do not draw
inheritance. The graph must show where identity, mutation, and diagnostics live.

## Step 6 — Identify spines

Find stable structures used by several concerns. Define the minimal shared alignment:
identity, topology, order, origin, and addressability only.

Do not start from current parallel arrays or pass outputs. Start from the structural facts
that must remain common.

## Step 7 — Identify facets

For each derived semantic plane, name:

- producing machine;
- spine alignment;
- dense or sparse shape;
- invalidation source;
- consumers.

If two planes have different producers or invalidation, they are different facets.

## Step 8 — Define operations and outcomes

For each machine operation, write exact inputs and every semantic outcome. In Lua ASDL use
named result sums with leaf-owned continuation behavior. In compiled Lalin use regions for
immediate alternatives.

No nil, boolean, string action, optional soup, or loose multi-return protocol.

## Step 9 — Define frames, stores, and worlds

Only now decide what persists:

- private machine frame;
- owned store;
- published projection;
- reusable world;
- encoded boundary image.

Do not turn every intermediate into a world. Do not expose private builder state.

## Step 10 — Wire composition

Write the object call/emit graph. Coordinators route outcomes but own no child semantics.
Choose `emit`, region `call`, function seal, or host boundary deliberately.

## Step 11 — Design twice

For every arguable boundary, draft at least two ownership/protocol shapes. Judge them by:

- authority clarity;
- interface depth;
- number of concepts callers must know;
- invalidation explainability;
- ability to delete states or outcomes by strengthening inputs;
- absence of duplicated facts.

## Step 12 — Prove completeness

Before bodies:

- map every semantic obligation to one owner;
- map every entity to one creation authority;
- map every persistent fact to one frame/projection/facet;
- map every rejection to one protocol/result;
- map every test to one obligation;
- classify every legacy type as required, duplicate, plumbing, speculative, or physical;
- prove there is no compatibility bridge or parallel pipeline.

## Step 13 — Transcribe implementation

Implement leaf methods and machine coordinators. When a body needs hidden state, manual
dispatch, side maps, or generic inputs, stop and repair the schema.

## Step 14 — Cut over coherently

Do not layer the new model over the old one. For each coherent boundary:

1. install the complete new schema;
2. move leaf-owned behavior;
3. move all callers;
4. delete replaced schema and implementation;
5. run focused, affected, and full suites.

No adapters, aliases, fallback dispatch, or dual semantic authorities.

---

# 12. Supporting design lenses

The following theories help evaluate the object model. They are lenses, not competing
centers.

## 12.1 Type forest and control graph

Every machine has two checked structures:

```text
type forest   → what facts, entities, frames, spines, and facets exist
control graph → what operations, decisions, transitions, and outcomes occur
```

The object-machine owns the relevant part of both. Products without an owner become data
soup. Control without an owner becomes callbacks, handlers, and orchestration soup.

## 12.2 Ousterhout: depth and information hiding

A deep object exposes a small precise protocol while hiding substantial implementation.
Its interface cost is the facts and outcomes every caller must understand.

Information hiding means:

- encoding belongs to one consumer;
- state shape belongs to one object;
- algorithm belongs behind owned operations;
- derived facts are published without exposing private builders;
- callers cannot reach through the object and mutate internals.

A pass-through machine that merely forwards another machine's interface is shallow. Delete
it unless it owns a real policy, invariant, or boundary.

## 12.3 UML as disposable discovery

Use diagrams to discover nouns, ownership, interactions, and states:

```text
class/entity       → product, unique entity, or store
association        → value, handle, or lease
method             → owned function or region
state              → block with complete state product
transition         → jump
sequence message   → method call or emit
alternative        → protocol/result outcome
component boundary → machine authority
```

Then discard or regenerate the diagram. The checked ASDL/Lalin declarations are the design
artifact.

## 12.4 Caching as an invalidation test

Caching does not define the architecture. It tests whether published worlds and projections
have honest identity and dependencies. A bad cache often reveals a bad ownership boundary.

## 12.5 Performance as structural consequence

Performance comes from:

- monomorphic generated objects;
- direct leaf methods;
- open-region CFG composition;
- bounded stores;
- explicit layouts and memory evidence;
- immutable projections;
- emitted C shaped for GCC optimization.

Do not trade ownership clarity for speculative micro-architecture. Once authority is local,
hot machine objects can be translated from Lua ASDL to compiled Lalin without changing the
model.

---

# 13. Compact worked example

Consider a terminal UI component.

The wrong center is a widget record with callbacks plus global layout/render/input services
mutating parallel trees.

The object-centered model is:

```text
ComponentMachine
  owns component identity and model frame
  owns update/focus/activation protocols
  publishes authored node declarations

DeclarationMachine
  owns authored node spine and primitive facets

StyleMachine
  consumes authored spine/facets
  publishes resolved-style facet

MeasureMachine
  consumes spine + resolved style + text facts
  publishes measurement facet

LayoutMachine
  consumes spine + measurements + constraints
  publishes geometry facet

RenderMachine
  consumes spine + geometry + decoration
  publishes renderable world and report geometry

InputMachine
  consumes semantic input + previous committed report
  invokes component continuations

TerminalRasterMachine
  consumes renderable world
  publishes terminal cell spine/facets

TerminalDiffMachine
  consumes committed and candidate cell worlds
  publishes patch world

AnsiEncodeMachine
  consumes patch world
  publishes output bytes

TerminalSessionMachine
  owns transactional write state and committed generation
```

Each object has one concern. The node spine supplies shared identity/topology. Style, measure,
layout, decoration, and report geometry are facets, not fields on one giant node. Components
never observe ANSI bytes or terminal cells. The terminal cannot rewrite semantic layout.
A partial write cannot advance the committed cell generation.

The same structure applies to compilers: source entities, checked semantics, control topology,
memory facts, plans, materialization, and physical emission are separate authorities aligned
through explicit identities and projections—not one giant pass context.

---

# 14. Anti-pattern catalog

## Universal context

One product carries unrelated scopes, layouts, diagnostics, target facts, caches, plans, and
backend state. Split by semantic authority.

## Pass pile

Modules are named after chronological steps and hand large bags to the next step. Re-cut at
owned knowledge boundaries.

## Parallel trees

Style, layout, rendering, or analyses each rebuild the same topology. Establish one spine and
owner-aligned facets.

## Giant node

One record accumulates optional source, checked, layout, control, memory, and backend fields.
Use phase-appropriate entities/projections and facets.

## Side map

A Lua table keyed by nodes, symbols, strings, or handles stores persistent compiler meaning.
Move it into a named relation, projection, facet, or owner frame.

## Handler map

Behavior is selected by `kind`, class, action string, visitor table, or callback registry.
Move behavior onto concrete leaves or an owning consumer region.

## Result object in compiled control

An immediate compiled decision is boxed, returned, and switched. Use a region protocol.

## Manual ASDL result dispatch

Lua code uses `classof`/`kind` to branch over a result sum. Put continuation behavior on the
result leaves.

## Optional soup

One product represents alternatives with nullable fields, booleans, and mode strings. Use a
sum/protocol with precise leaves/outcomes.

## No-owner fact

Several modules consume a fact but no machine establishes its meaning or validity.
Name the concern and owner.

## Duplicate authority

Two machines compute or validate the same semantic decision. Select one owner and make the
other consume its result.

## Foreign mutation

A machine reaches into another frame/store and mutates fields. Invoke the owning operation.

## World-per-step

Every chronological pass creates a wrapper world with no reuse or publication meaning.
Delete boundaries that do not answer a semantic question.

## Object wrapper

A nominal machine merely stores pointers to old pass modules and forwards every call. That
is an adapter, not a model.

## Premature physical image

A tape, bytecode, command buffer, or generic row format becomes the internal architecture
without a real storage/portability/ABI need.

## Encoded identity

Names such as `"fn_" .. name` are later parsed to recover semantic identity. Carry typed
identity and explicit symbol projection.

## Count-only diagnostic

Typed issues are collapsed to “N errors.” Preserve typed reasons and origins to the public
diagnostic boundary.

## Speculative vocabulary

Schema types exist without a producer, consumer, or operation. Delete them until a real
semantic obligation requires them.

---

# 15. Design review

## Concern and authority

- [ ] Can every machine state its concern in one sentence?
- [ ] Does every semantic decision have exactly one owner?
- [ ] Does every persistent fact have exactly one owner?
- [ ] Are coordinators limited to sequencing and routing?
- [ ] Are independently invalidated concerns separate?
- [ ] Are pass-through objects removed?

## ASDL and leaf behavior

- [ ] Are products precise and free of generic bags?
- [ ] Are alternatives sums/protocols rather than optional soup?
- [ ] Does every concrete variant leaf own its case behavior?
- [ ] Is there any `classof`, `kind`, tag, action, visitor, or handler dispatch?
- [ ] Do semantic operations return named ASDL values rather than nil or loose multi-return?
- [ ] Are constructors composed only from ASDL values and declared primitives?

## Entities and memory

- [ ] Does each durable entity justify identity?
- [ ] Does one authority create each identity?
- [ ] Are stable references handles rather than raw pointers?
- [ ] Does one store own handle domain, liveness, and invalidation?
- [ ] Are leases temporary and nonescaping?
- [ ] Are raw pointers confined to explicit trust/performance boundaries?

## Spines and facets

- [ ] Is shared topology represented once?
- [ ] Does each spine contain only structural alignment facts?
- [ ] Does each facet contain one concern?
- [ ] Does each facet name its producer and alignment?
- [ ] Are dense/sparse invariants explicit?
- [ ] Can any machine mutate a foreign facet?
- [ ] Are generations/provenance sufficient to reject stale alignment?

## Worlds and projections

- [ ] Is every world a real domain/publication/reuse state?
- [ ] Can its invalidation sentence be completed?
- [ ] Are false invalidation and stale reuse both excluded?
- [ ] Are private builder states kept private?
- [ ] Does any world merely wrap chronological pass inputs?

## Control

- [ ] Are immediate compiled choices protocols?
- [ ] Are bootstrap result sums consumed through leaf methods?
- [ ] Are stored encodings owned by one consumer?
- [ ] Are block parameters complete state?
- [ ] Are emit fills and jumps total?
- [ ] Is `emit` versus `call` versus function seal deliberate?

## Composition

- [ ] Do machines communicate only through typed operations/projections/boundaries?
- [ ] Is there any foreign frame mutation?
- [ ] Is persistent semantic meaning hidden in a side map?
- [ ] Is a generic context compensating for a wrong boundary?
- [ ] Does a coordinator duplicate child validation or facts?

## Completeness and cutover

- [ ] Does every semantic obligation map to an owner?
- [ ] Does every behavior test map to an obligation?
- [ ] Is every schema type required, physical, duplicate, plumbing, or speculative?
- [ ] Is the new model complete before implementation starts?
- [ ] Does cutover delete replaced schema and implementation?
- [ ] Are adapters, aliases, fallback paths, and dual pipelines absent?

---

# 16. The doctrine

```text
 1. One concern, one object-machine, one authority.
 2. The machine owns the concern; concrete leaves own the cases.
 3. Persistent facts live in the owning frame or store.
 4. Durable identity is an entity or handle, never an encoded-name convention.
 5. Immediate compiled choices are protocols.
 6. Bootstrap alternatives are ASDL sums with leaf-owned continuation behavior.
 7. Stored choices are encoded facts with one named consumer.
 8. Regions are object-owned typed control operations.
 9. Blocks carry complete state; jumps construct it totally.
10. Emit splices open control; call creates a sealed frame; functions seal ABI/product edges.
11. Derived facts are immutable projections, never mutations of source objects.
12. Spines own shared structure; facets own one semantic plane.
13. Every facet has one producer machine.
14. Worlds are justified publication or reuse frontiers, not mandatory pass wrappers.
15. Coordinators own sequencing only.
16. Machines never mutate foreign frames or facets.
17. Generic contexts and semantic side maps signal missing ownership.
18. Stores own bytes and liveness; resolver regions grant leases.
19. Handles may escape; leases may not.
20. Optimization consumes exact evidence and never invents it.
21. Lua generates families; compiled Lalin runs monomorphic objects.
22. Dense images exist only for storage, portability, sharing, or ABI boundaries.
23. Diagnostics remain typed until their external rendering boundary.
24. Model completely, then cut over coherently; never layer a new model over the old pile.
```

The architecture is not the file tree, pass order, UML diagram, callback graph, or pile of
records. It is the graph of semantic authorities: object-machines, their identities and
frames, their owned protocols and methods, and the spines/facets/projections through which
they compose.

When that graph is correct, implementation becomes local transcription. When implementation
pressure demands hidden state, manual dispatch, side maps, compatibility adapters, or broad
contexts, stop. The model is incomplete. Fix the ownership graph first.
