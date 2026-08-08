# The Lalin Design Bible

## Values, machines, and named control are the center of gravity

**Status:** design canon for Lua ASDL systems and compiled Lalin systems.

The bootstrap Lua model keeps three things distinct:

```text
ASDL     the universe of durable values
objects  the state of computations in progress
methods  behavior on values and static control nodes on machines
```

ASDL values carry persistent semantic meaning. Concrete ASDL leaf methods own behavior
that depends on value kind. A named machine object owns one running computation. Its
named methods are the control graph and tail calls are the edges. A machine does not
become the semantic owner of every ASDL value it carries.

Everything else in this book follows from that law:

```text
persistent fact       → ASDL value, owned store, spine, facet, or projection
durable identity      → entity or handle
immediate decision    → peer named exits on a running machine
value-kind behavior   → concrete ASDL/Lalin leaf method
computation state     → named machine object
static control node   → named machine method
control edge          → strict tail call
variable destination  → stable named method stored on the machine
stored/queued choice  → encoded boundary record + one consumer
external boundary     → sealed function, artifact, or bridge
family variation      → Lua factory
```

This is not class-oriented object programming. There is no universal base object, vtable
culture, getter/setter shell, machine hierarchy, or control runtime. Semantic authority
and running computation are related but distinct ownership roles.

---

# 1. Ownership and machine law

## 1.1 What values, authorities, and machines own

A durable semantic value or authority may own:

- entity identity, facts, diagnostics, generations, invalidation, stores, and readonly
  projections;
- methods that interpret those durable values;
- one physical boundary image when serialization or ABI portability requires it.

A running machine object may own:

- the cursor, builders, services, and pending work of one computation in progress;
- named methods that form that computation's static control graph;
- one stored named destination only when a join or suspension genuinely varies.

Neither owner automatically needs every feature. Do not invent durable identity for a
transient machine, and do not turn a durable ASDL value into a mutable control object.
The point is exact ownership, not ceremony.

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

Value-kind behavior belongs to the ASDL leaf whose invariants it interprets. Sequencing
belongs to the named machine whose computation is in progress. A machine may sequence:

```text
resolve → check → project → materialize
```

but it may not duplicate child semantics, inspect child encodings, or modify published
facts. The machine owns ordering and evolving computation state only.
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

Lua bootstrap semantics has three independent axes:

```text
ASDL value or request  durable semantic vocabulary
ASDL leaf method       behavior for one value case
Lua machine object     one computation in progress
machine method         one named static control node
```

A total value operation returns its exact value directly. A multi-exit value operation
receives the running machine and stable unbound exit methods from that machine class:

```lua
function FlowRequest:project(machine, on_projected, on_rejected)
  return self.code:project_flow(
    FlowInput(self.topology), machine, on_projected, on_rejected)
end

function FlowMachine:flow_projected(facet)
  self.flow = facet
  return self:begin_induction()
end
```

The producer forwards `machine` unchanged and selects one peer exit. The selected method
already names its successor; it receives no further continuation parameter.

A request is an ASDL value that names one semantic frontier. It is not the running
machine. A machine is an ordinary Lua object with a coherent evolving computation. Do
not create empty machine objects, universal phase machines, or anonymous callback
contexts. Create a machine when state genuinely survives calls or several named control
nodes belong to one running computation.

Concrete ASDL leaves continue to own semantic cases:

```lua
function ExprInt:typecheck(input, machine, on_typed, _on_rejected)
  return on_typed(machine, TypedIntegerExpression(input.expected, self))
end

function ExprCall:typecheck(input, machine, on_typed, on_rejected)
  return self.callee:check_call(
    TypeCallInput(input.scope, self.args), machine, on_typed, on_rejected)
end
```

Manual handler maps remain forbidden. The ASDL leaf is behavioral dispatch; the machine
method selected by the exit is control dispatch.

Therefore the bootstrap form has two ownership laws:

> **One durable semantic concern → one ASDL authority.**

> **One computation in progress → one named machine object.**


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

There is no contradiction between ASDL sums and region protocols. They represent
different lifetimes.

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

### Immediate alternatives in bootstrap Lua

Bootstrap Lua passes the running machine and its stable unbound exit methods:

```lua
function Store:borrow(reference, machine, on_borrowed, on_stale, on_missing)
  local record = self:find(reference)
  if record then return on_borrowed(machine, record) end
  if self:is_stale(reference) then return on_stale(machine) end
  return on_missing(machine)
end

function BorrowMachine:borrowed(record)
  return self:check_record(record)
end

function BorrowMachine:stale()
  return self:reject_stale()
end

function BorrowMachine:missing()
  return self:reject_missing()
end

function BorrowMachine:begin(reference)
  return self.store:borrow(reference, self,
    BorrowMachine.borrowed, BorrowMachine.stale, BorrowMachine.missing)
end
```

The exit functions are allocated once as methods. `BorrowMachine` is the computation in
progress, not opaque caller state or a continuation wrapper. Its methods name successors
directly. No runtime wiring object or conformance registry is required.

### Stored or portable alternatives

A queued event, AST node, bytecode instruction, wire message, or ABI result is
stored data. Encode it physically, then give the encoding exactly one named
consumer object or region. The encoding is not the semantic authority.

Therefore:

```text
immediate compiled choice -> Lalin region
immediate bootstrap choice -> peer named exits on a running machine
stored or queued choice    -> ASDL sum or encoded fact + one consumer
ABI choice                 -> encoded boundary + decoder or consumer
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

A decision that is consumed now is control. Compiled Lalin uses named region
continuations. Bootstrap Lua tail-calls one stable continuation function supplied by
the caller.

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

This section describes compiled Lalin control. Bootstrap compiler control uses ordinary
Lua methods and stable direct continuation functions; it has no block/jump/emit control
IR.

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

For each machine operation, write exact inputs and every semantic outcome. Use stable
direct continuation functions for an immediate Lua choice. Use a compiled region for
an immediate Lalin choice. Use an ASDL sum only when the outcome must persist or cross
a sealed boundary.

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

For bootstrap Lua, the control side is only the authored method signatures and stable
continuation functions. There is no separate control graph or descriptor IR.
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

Lua code uses `classof`/`kind` to branch over a result sum. Pass stable direct
continuation functions instead; the concrete semantic leaf selects the exit and the
caller owns the continuation behavior.

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

- [ ] Are all immediate choices compiled regions or stable direct Lua continuations?
- [ ] Are per-call closures, mandatory `k` objects, and universal frame families absent?
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
 5. Immediate choices use region protocols in compiled Lalin and stable direct
    continuation functions in bootstrap Lua.
 6. Durable alternatives are ASDL sums or precise boundary encodings.
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
