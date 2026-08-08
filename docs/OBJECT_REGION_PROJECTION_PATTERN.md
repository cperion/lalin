# Object–Region–Projection

> A general object-machine pattern for explicit systems in Lalin

## Abstract

Object–Region–Projection (ORP) is a general pattern for systems that retain
state, execute repeatedly, derive reusable facts, own resources, expose multiple
outcomes, or cross a performance boundary. It applies equally to parsers, stores,
schedulers, virtual machines, compiler phases, services, simulations, and user
interfaces.

The pattern has four operational elements:

1. An **object** owns persistent state, identity, resources, diagnostics, and
   invalidation authority.
2. Qualified **regions** own transitions and expose semantic alternatives as
   named continuations.
3. Readonly **projections** derive facts, views, plans, reports, or artifacts from
   object state at explicit reuse frontiers.
4. Continuation wiring composes object-machines without callbacks, handler tables,
   boxed result protocols, or hidden dispatch.

The compact rule is:

```text
persistent fact       → object/frame field
immediate decision    → region continuation
derived fact          → readonly projection/world
queued/portable fact  → encoded boundary record + one consumer region
durable identity      → unique struct or qualified handle
temporary access      → lease granted by an owning region
family variation      → Lua factory producing monomorphic declarations
```

ORP is not a framework, a universal interpreter, an actor runtime, or a UI
library. It is the compiled-Lalin mirror of the project’s ASDL doctrine: the
semantic thing owns its data, behavior, control protocol, and derived worlds.

---

## 1. The problem

Conventional designs routinely separate facts that must be understood together:

- state in one object;
- behavior in unrelated functions;
- alternatives in result objects;
- routing in handler maps;
- derived facts in caches keyed by arbitrary identity;
- invalidation in conventions;
- effects in callbacks;
- ownership in comments.

This produces two recurring failures.

First, control becomes data. A parser returns `Token | Eof | Error`; a queue
returns a boolean plus an output slot; an actor returns a command list; a compiler
pass returns a tagged report. The caller immediately decodes the returned value
and chooses another operation. The stored result existed only because an ordinary
function had one return edge.

Second, derived knowledge loses its owner. Layout facts, type facts, schedules,
indexes, reports, and render plans accumulate in side tables or mutable context
bags. Nobody can state precisely when they are valid or what mutation invalidates
them.

Lalin already has the missing vocabulary:

- structs and unique structs for products and entities;
- qualified functions for ordinary owned operations;
- qualified regions for typed control protocols;
- continuations for immediate alternatives;
- handles and leases for durable identity and temporary access;
- explicit phase products for projections and worlds;
- Lua factories for build-time families;
- emitted C for the operational implementation.

ORP is the discipline for using those pieces as one local reasoning boundary.

---

## 2. The core pattern

An ORP object-machine is a semantic object with retained state and owned
protocols:

```text
ObjectMachine
├── frame/state product
├── qualified transition regions
├── qualified readonly projections
├── continuation protocol
├── identity and access policy
├── diagnostics
└── generation/invalidation authority
```

The object does not need an inheritance hierarchy, vtable, dynamic method lookup,
mailbox, or framework base class. A Lalin struct plus qualified declarations is
the object model.

A canonical declaration family has this conceptual shape:

```lln
struct Parser
  source [slice [u8]]
  pos [index]
  generation [u32]
end

region Parser.next(self [ptr [Parser]];
  token(tok [Token]),
  eof,
  syntax(at [index], code [i32])
)
  entry start()
    -- inspect and update self, then select exactly one continuation
    jump eof
  end
end

region Parser.index(
  self [readonly [ptr [Parser]]],
  out [ptr [IndexWriter]];
  done,
  full(required [index])
)
  entry start()
    -- derive an index without changing Parser
    jump done
  end
end
```

`Parser.next` owns transition control. `Parser.index` owns a derived projection.
The frame contains only persistent parser facts. There is no external token-result
dispatcher and no node-keyed index side table.

### 2.1 The four questions

For every proposed value or API, ask in order:

1. **Must this survive the current transition?**
   Store it in the owning object’s frame or in an owned store.
2. **Will the caller act on this alternative immediately?**
   Make it a continuation; do not box it as a result value.
3. **Is this derived from existing semantic facts?**
   Make it a readonly projection/world with an explicit invalidation rule.
4. **Must it be queued, stored, serialized, or cross an ABI?**
   Encode it physically and name exactly one consumer region that restores
   semantic control.

These questions prevent persistent facts, control facts, derived facts, and
boundary encodings from collapsing into one generic data model.

---

## 3. Formal vocabulary

### Object

An object is a struct or unique struct that owns a repeated semantic machine.
Use a plain struct when equal fields mean equal values. Use a unique struct or
qualified handle when identity must survive mutation, allocation, compaction, or
serialization.

### Frame

A frame is the object’s complete persistent state. A region block’s parameter
product is its complete transient state. Facts absent from both places do not
exist semantically.

### Region

A region is a typed control protocol:

```text
region(input product; continuation set)
```

The data before `;` is what is known on entry. Each continuation after `;` names
a distinct outcome and the additional facts known on that edge.

### Block and jump

Blocks are explicit machine states. Jumps are transitions. Every jump assigns the
target block or continuation product completely. Hidden capture is not part of
the model.

### Projection

A projection is a readonly derivation of a later semantic shape: an index, layout,
schedule, query view, diagnostic report, render plan, compiled artifact, or other
phase fact. A projection does not mutate its source object and does not hide
semantic state in a cache.

### World

A world is the named domain state at a reuse frontier. A phase consumes one world
and produces another:

```text
SourceWorld → validate → ValidWorld → plan → PlannedWorld
```

The world name says what exists now. The phase name says what transformation
happened.

### Encoding

An encoding is stored physical data with a scalar discriminator or opcode. It is
admitted only when the fact must survive, queue, serialize, or cross an ABI. One
named consumer region owns the encoding. Other semantic code uses that region’s
continuations and never switches on the discriminator.

---

## 4. Laws

### Law 1 — Object ownership

A repeated system’s retained state, identity namespace, resources, diagnostics,
and invalidation authority belong to its object-machine.

A side table keyed by nodes, names, pointers, or handles is not an alternative
ownership model.

### Law 2 — Protocol ownership

Every immediate “or” is presumed to be a continuation protocol. The protocol
belongs to the consumer: preserve only distinctions callers act upon.

A stored tag is allowed only when storage is real and one consumer region owns
its decoding.

### Law 3 — Projection purity

Transitions may change object state. Projections may only observe it. A projection
cannot execute host effects, mutate the source object, or depend on hidden ambient
state.

### Law 4 — Direction

The controlling direction never reverses:

```text
object transition
  → projection
  → consumer/artifact
  → reported physical identity
  → next object transition
```

A renderer cannot invoke application callbacks. An index cannot mutate its AST.
A scheduler report cannot alter the scheduler. A compiler emitter cannot secretly
rewrite the source world it consumes.

### Law 5 — Totality

Every region path terminates. Every jump supplies its target product. Every emit
or call wires all continuations. Missing behavior is a type/checking failure, not
a runtime fallback.

### Law 6 — Seal discipline

Use:

- `emit` for local control abstraction that should become part of the caller CFG;
- `call` for a real sealed frame, recursion, independent actor, instrumentation,
  or stable performance boundary;
- `fn` for an ordinary single-result operation or ABI seal.

Do not force internal multi-outcome protocols through function result objects.

### Law 7 — World/reuse discipline

Each reusable semantic boundary has one invalidation sentence:

```text
This world changes exactly when __________________ can no longer be reused.
```

Two failures test the design:

- **false invalidation:** the world changed although the next product is identical;
- **stale reuse:** the world remained identical although the next product must
  change.

Fix the world shape, identity, or missing epoch rather than adding cache exceptions.

### Law 8 — Identity and access

Durable association uses typed handles or unique identity. Temporary access is a
lease granted by the owning object’s resolver region. Handles may escape; leases
may not. Invalidating operations cannot overlap live leases from the same domain.

### Law 9 — Family discipline

Runtime programs are monomorphic. Lua factories own genericity and generate
concrete structs, regions, projections, capacities, and physical profiles.
Instantiate only the families actually used.

### Law 10 — Depth

A good region hides substantial machinery behind a precise input product and
meaningful continuation set. A region that merely forwards every input and every
outcome is not composition; it is indirection and should be deleted.

---

## 5. Relationship to familiar architectures

ORP is general. MVC, MVU, and actors are useful readings of one ORP object, not
competing foundations.

### 5.1 MVC

```text
Model       = typed frame
Controller  = qualified transition regions
View        = qualified readonly projections
```

Unlike route-first MVC, these parts are not separate registries joined by strings.
One semantic object owns all three.

### 5.2 MVU

```text
Model    = typed frame/world
Update   = transition region
View     = readonly projection
Command  = effect continuation
Message  = routed physical input decoded by one owner
```

MVU correctly identifies state transition plus derived view. ORP sharpens its
control and ownership: a large message/action switch becomes typed region wiring;
an immediate command becomes a continuation; a delayed command becomes a physical
effect record carrying a continuation identity.

### 5.3 Actors

```text
Actor identity  = unique object or frame handle
Actor state     = typed frame
Actor behavior  = qualified regions
Actor reply     = continuation payload
Scheduling      = explicit deterministic pump or scheduler
Mailbox         = optional physical queue with one decoder
```

Actor semantics do not require threads, allocated mailboxes, callback registries,
or nondeterministic scheduling. Those are runtime choices. The semantic actor is
an object plus its protocol.

### 5.4 ASDL methods

ORP is the compiled mirror of the bootstrap ASDL pattern:

| ASDL/Lua | Compiled Lalin |
|---|---|
| product | struct |
| unique product | unique struct or qualified handle |
| leaf method | qualified function/region |
| semantic result | named world or continuation |
| phase projection | projection struct/world |
| interned identity | unique object/handle |

In both forms, behavior belongs to the semantic receiver instead of an external
handler table.

---

## 6. Composition

### Static nesting

A parent object may contain child frames. The parent owns their lifetime and wires
their continuations.

### Sealed actor composition

A child with an independent frame boundary is invoked through `call`:

```lln
call Child.step(child;
  changed = child_changed,
  completed = child_completed,
  ignored = continue_parent
)
```

The child selects an outcome. The parent decides locally how that outcome
continues.

### Open control composition

Use `emit` when a region is a local protocol abstraction and should be spliced
into the enclosing CFG. This preserves typed continuations without paying a real
call boundary.

### Parallel composition

A scheduler or pump may own many frame handles and deterministically resume them
from a physical queue. Queue opcodes remain private to the queue decoder; resumed
objects receive semantic continuation edges.

### Service machines

Separate objects are warranted when authority is genuinely separate. A parser and
its source store, a scheduler and its worker backend, or a UI component and its
layout kernel own different resources and instruction languages. They compose
through typed protocols without absorbing each other’s state.

---

## 7. Effects and suspension

Effects cross from semantic execution into an external host: file IO, timers,
clipboard access, network requests, process execution, GPU submission, or another
runtime service.

An immediate effect is a continuation:

```text
machine transition → effect(request) → host bridge
```

If completion is delayed, the request must survive. It becomes an encoded physical
record containing:

- effect opcode;
- typed payload bytes or resource handles;
- requesting object identity;
- continuation identity;
- generation needed to reject stale completion.

One EffectMachine decoder owns the opcode. Completion returns through the pump,
resolves the requesting object, and resumes the saved continuation.

Only durable facts survive suspension. A temporary lease cannot be stored in the
request or frame. Hidden closure state cannot carry semantics across the boundary.

This is the typed form of what callbacks, promises, async/await, and Elm commands
encode indirectly.

---

## 8. Worlds, projections, and incremental systems

ORP treats an incremental system as a sequence of explicit object worlds:

```text
WorldA → phase_a → WorldB → phase_b → WorldC
```

Worlds are selected at reuse frontiers, not at arbitrary chronological steps.
A world can contain aligned lanes for partial reuse while remaining one complete
semantic input to its next phase.

Examples:

### Compiler

```text
typed module
  → flow facts
  → memory/effect facts
  → kernel plan
  → backend unit
  → emitted C
```

Each product is a projection with an explicit owner and invalidation rule.


### Parser and indexer

```text
source/parser frame
  → parsed syntax world
  → resolved symbol world
  → index projection
  → diagnostics/report
```

### Scheduler

```text
scheduler frame
  → runnable plan
  → worker assignment projection
  → execution report
```

### User interface

```text
component frames
  → readonly view declarations
  → measured/layout world
  → render/report commands
```

UI is one realization, not the definition of ORP.

Caches, when needed, are themselves owned products/stores with typed key products,
epochs, and hit/miss/stale protocols. “Memoize this function by all its arguments”
is not a semantic design.

---

## 9. Boundary images and virtual machines

A dense byte image is optional. It is useful when a program must be portable,
streamed, persisted, sandboxed, or sealed behind a compact ABI.

The bytecode is a projection of the object-machine, not its source model.

```text
typed objects/regions/worlds
  → validated encoded image
  → one decoder/interpreter object
  → typed continuations and projected artifacts
```

The image schema, encoder, validator, C header, interpreter constants, debug
dumper, and version fingerprint must derive from one authority. Numeric tags are
physical facts owned by the decoder region.

A native emitted-C realization and a bytecode realization can be tested
differentially: the same initial objects and physical input sequence must produce
equivalent object worlds, effects, reports, and artifacts.

---

## 10. Worked realizations

### 10.1 Parser

The parser frame retains source and position. `Parser.next` exposes `token`, `eof`,
and `syntax` continuations. `Parser.index` is readonly. There is no
`ParserNextResult` object consumed by a switch.

### 10.2 Store

A store object owns records and a handle namespace. `Store.borrow` exposes
`borrowed(lease)`, `stale`, and `missing`. Preserving and invalidating operations
are visible in their access types. No client manually decodes generations or
stores nullable pointers.

### 10.3 Scheduler

A scheduler object owns queues, workers, and lifecycle state. Regions expose
`got`, `empty`, `stolen`, `parked`, `draining`, and `stopped` according to what
callers distinguish. Observability is a readonly projection, not mutation through
a monitoring API.

### 10.4 Terminal application

A terminal component object owns its typed frame. Input bytes are decoded once and
routed by identity. Controller regions transition the frame. A readonly projection
emits layout declarations. A small layout object produces cells; a backend diffs
the current and previous grids and writes ANSI.

The terminal is useful because it demonstrates the complete ORP cycle without a
GPU: transitions, effects, projections, layout, reports, and physical output.

### 10.5 Web UI

The same component objects can project declarations into a richer layout kernel.
Solved geometry becomes a flat command stream consumed by WebGL. GPU resources
belong to the backend object. Component semantics remain unchanged.

---

## 11. Counterpatterns

### Boxed control

```text
operation → Result(tag,payload) → switch → next operation
```

If the result is consumed immediately, replace it with continuations. If it must
be stored, name the encoding and its single consumer.

### Boolean/status protocols

A boolean or integer cannot express what is now known on each edge. Replace it
with named continuations carrying minimal payloads.

### Callback registries

Callbacks make the control graph indirect and permit missing outcomes. Replace
registration and string lookup with explicit continuation wiring.

### Generic reducers

A giant `switch action.kind` centralizes unrelated object behavior. Move each
transition to the object that owns the frame and protocol. Keep opcode switching
only in the physical decoder that owns queued input.

### Side tables

A table keyed by an object/node to carry semantic facts indicates a missing field,
projection, facet, or world. Backend resource caches are legitimate only when
owned by the backend object with explicit lifetime and invalidation.

### Context bags

A large `ctx/env/state/options` product hides why facts are present. Replace it
with a domain world whose fields are exactly what the next phase requires.

### Optional soup

Mutually exclusive fields, mode strings, and booleans encode a missing protocol
or precise stored encoding. Name the decision and its owner.

### Step regions

A region named only after chronology—`step1`, `run_phase`, `process`—often exposes
no knowledge boundary. Name regions by the decision or authority they own.

### Pass-through objects

An object or region that owns no state, authority, diagnostics, or decisions and
forwards every operation is not an object-machine. Delete it.

---

## 12. When not to use ORP

ORP earns its ceremony when a subsystem has repeated execution, retained state,
multiple meaningful outcomes, resource authority, diagnostics, incremental reuse,
serialization, multiple implementations, or a performance budget.

It is not automatically appropriate for:

- a short throwaway script;
- a fixed external API that cannot express richer protocols;
- early exploration before the domain alternatives are understood;
- a pure scalar helper with no retained state or semantic alternatives.

The failure to avoid is beautifully typed wrongness: declaring elaborate objects
and continuations before understanding what the system means.

---

## 13. Review checklist

### Object

- Can the system be stated as “consumes X, produces Y, by repeatedly doing Z”?
- Does one object own the repeated state and authority?
- Are plain values distinguished from identity-bearing entities?
- Are durable references handles rather than accidental pointers or strings?
- Are diagnostics and invalidation authority owned?

### Frame

- Does every stored field genuinely persist across transitions?
- Is derived data absent from the source frame?
- Is transient block state explicit in block parameters?
- Is any semantic state hidden in globals, upvalues, callbacks, or side tables?

### Regions

- Is every immediate alternative a named continuation?
- Do payloads state exactly what becomes known?
- Are all continuations wired at every invocation?
- Does every path terminate?
- Is the region deep enough to justify its signature?
- Should the boundary be `emit`, `call`, or `fn`?

### Projections and worlds

- Is the projection readonly?
- What exact fact invalidates it?
- Can its invalidation sentence be completed without “and anything else”?
- Does the world contain every semantic dependency?
- Does it contain irrelevant facts causing false invalidation?
- Are partial-reuse lanes aligned through typed identity?

### Ownership

- Who owns every byte buffer, store, queue, image, and resource?
- Does every handle have a resolving authority?
- Can leases escape or survive suspension?
- Are preserving and invalidating operations visible in signatures?
- Are owned obligations discharged on every CFG path?

### Encodings

- Must the encoded fact genuinely be stored or cross a boundary?
- Which single region owns its opcode/tag?
- Can any other semantic module switch on that tag?
- Are encoder, decoder, validator, ABI, and debugger derived from one schema?

### Effects

- Is the effect outside projections?
- Is immediate control a continuation rather than a command object?
- Does delayed completion carry object identity, continuation identity, and
  freshness facts?
- Can cancellation and failure be wired explicitly?

### Families

- Is runtime variation truly per-instance, or should Lua decide it at build time?
- Does each factory produce monomorphic, distinctly named declarations?
- Are only used family instances generated?

### Obviousness

- Can a reader reconstruct the control graph from declarations?
- Are there words needed to explain behavior that appear in no type or region
  signature?
- Could strings, tags, callbacks, or conventions be hiding a missing declaration?

---

## 14. Summary

Object–Region–Projection is the common Lalin pattern beneath stateful services,
compilers, stores, schedulers, VMs, parsers, and interfaces:

```text
object      owns durable semantic state and authority
region      owns transition control and immediate alternatives
projection  owns readonly derived knowledge at reuse boundaries
wiring      composes machines through total typed continuations
encoding    exists only where facts must persist or cross a boundary
```

Its deepest rule is not syntactic:

> Put each fact in the form that matches its lifetime and meaning.

Persistent facts belong to objects. Decisions belong to regions. Derived facts
belong to projections. Portable facts belong to owned encodings. When those forms
remain distinct, the type forest, control graph, object world, and emitted artifact
describe one system instead of four loosely synchronized implementations.

---

## Repository references

- `docs/ASDL_GUIDE.md` — schema ownership, leaf behavior, products, projections,
  facets, and the pure-Lalin mirror.
- `docs/LUA_OBJECT_REGIONS.md` — bootstrap Lua regions with direct static
  continuation parameters and no immediate result allocation.
- `docs/DESIGN_BIBLE.md` — type forest/control graph, object-machine stack, worlds,
  reuse frontiers, region algebra, ownership, and review doctrine.
- `docs/LANGUAGE_REFERENCE.md` — structs, qualified functions/regions/handles,
  continuations, `emit`, `call`, leases, and ownership.
- `docs/ARCHITECTURE.md` — the compiler’s concrete world and emitted-C pipeline.
- `demo/lua_vm.lln` — physical opcode dispatch owned by one VM region.
- `demo/ui.lln` — a compact machine/frame/continuation/projection realization.
- `examples/ui/lalin_ui.lln` — a complete UI realization of ORP, not the definition
  of the general pattern.
