# Composed State Machines on LuaJIT

## Exact state, sealed behavior, CPS control, structural lifetime, and generated specialization

### Consolidated architecture and experimental report

## Abstract

This paper presents one coherent way to build stateful systems on LuaJIT: model each concern as a
concrete state machine and compose machines through physical ownership and direct continuation-
passing control. Persistent physical state is declared exactly with `ffi.cdef` when the domain is
C-representable. Sealed FFI metatypes attach stable behavior to concrete ctypes. Named public
entries establish ownership and borrowing. Coarse developer-authored methods are control states,
and proper-tail calls are control edges. Parent machines own child machines by value and synchronize
them through stable unbound continuations.

The same state-machine view has a generated realization. Generated CPS Specialization (GCPS) decodes
a fixed foreign program, resolves its constants and control graph, and materializes one monomorphic
host CPS function per foreign instruction occurrence. Lazy exotype-shaped owner queries materialize
only reached residual closures plus readable listing and aligned projection facets. LuaJIT then
specializes dynamic values and recurring paths. WebAssembly adds an important refinement: statically
validated transient state should travel as CPS arguments rather than be reified in a runtime operand stack.

The architecture is not a framework, actor runtime, command interpreter, universal scheduler, generic
VM, or native backend. It is a compositional view: state is represented in the form that matches its
lifetime; behavior belongs to the concrete state owner; immediate decisions are control edges; derived
facts are projections; and fixed facts are specialized before LuaJIT tracing begins.

## 1. The thesis

The complete idea is:

```text
stateful concern
  → exact persistent state
  → named public entry
  → concrete control blocks
  → direct proper-tail transitions
  → explicit outcomes or projections
  → structural composition with other concern machines
  → LuaJIT specializes the resulting monomorphic path
```

Its compact rule is:

> **State is physical. Behavior is local. Control is CPS. Composition is ownership plus continuation
> wiring. Specialization removes every fact already known.**

A machine can be read conceptually as:

```text
Machine = Frame + Entries + Blocks + Edges + Outcomes + Projections
```

This equation is a design vocabulary, not a generic runtime object. Every real machine uses its own
domain names, fields, entries, methods, and outcomes.

## 2. The state-machine view

For an authored CDEF machine:

```text
persistent state       = exact CDEF fields
machine instance       = one concrete cdata object
public operation       = named entry method
control state          = coarse Lua method
local decision         = direct if/elseif inside that method
control edge           = proper-tail method call
immediate alternative  = named terminal or continuation
transient value        = Lua argument or local
derived fact           = explicit readonly projection or output
specialization         = concrete ctype and leaf-owned prototype
execution              = ordinary LuaJIT
```

For a generated foreign machine:

```text
persistent guest state       = generated `self` with exact guest-owned structures
validated transient state    = CPS arguments
instruction occurrence       = unique residual host function
known control edge           = direct proper-tail call
fixed operand or constant    = literal or immutable binding
runtime value specialization = LuaJIT guards and traces
```

The shared principle is not that every state value must be C data. The principle is that persistent
state has an exact owner and representation. A scanner's positions and pointers fit CDEF. A Lua 5.5
guest register holding arbitrary Lua values belongs in an exact Lua-owned register structure. Do not
force dynamic host values through unsafe C pointers merely to make the representations look alike.

## 3. Put facts in the form that matches their lifetime

The architecture distinguishes five kinds of fact:

```text
persistent fact       → machine field or owned store
transient fact        → local or CPS argument
immediate alternative → direct named control edge
derived fact          → readonly projection
portable delayed fact → exact encoded record owned by one consumer
```

This classification prevents one mutable context object from becoming state, event, result, command,
cache, and continuation at once.

### 3.1 Persistent state

A fact belongs in the frame only when it must survive the current transition. Examples include:

- positions, counters, capacities, and accumulators;
- owned child machines;
- borrowed pointers while a sealed entry is active;
- domain stacks and buffers intrinsic to the machine;
- pending suspension identity and generation;
- exact typed reports that cross a boundary.

### 3.2 Transient state

Values used only by the current path remain locals or parameters. WebAssembly operand-stack values
are the strongest example: validation fixes their topology, so flattened residual CPS carries them
directly on edges instead of storing `self.stack` and `self.sp`.

### 3.3 Immediate alternatives

If the caller acts on an alternative now, the alternative is control:

```text
changed   → synchronize dependent concern
ignored   → complete current epoch
rejected  → diagnostic terminal
suspended → publish durable request
```

Do not allocate `{ action = ... }`, `{ ok = ... }`, command lists, handler names, or continuation
records only to switch on them immediately.

### 3.4 Derived facts

Layout, render plans, indexes, query views, diagnostics, and schedules are projections. A projection
has an owner and an invalidation sentence. It is not a side table keyed by a machine pointer.

## 4. Authored physical machines: CDEF plus coarse CPS

The authored form uses `ffi.cdef` as the only persistent physical field language:

```c
typedef struct {
    const uint8_t *input;
    uint32_t length;
    uint32_t position;
    int64_t accumulator;
} CsvV1_Signed;
```

One concrete cdata object is the machine. Developer-authored methods are its behavior:

```lua
function Signed:scan(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    self.length = #owner
    self.position = 0

    local report = self:cycle(owner)

    self.input = nil
    return report
end

function Signed:cycle(owner)
    if recurring_case then
        -- Mutate exact machine state.
        return self:cycle(owner)
    elseif completed then
        return self:completed(owner)
    end
    return self:rejected(owner)
end
```

The entry names the operation and seals the borrow. The leaf-owned cycle names the hot recurrence.
Terminals name semantic outcomes. No semantic tree, program counter, handler map, or generic driver is
required.

### 4.1 Why coarse blocks

An authored block should own one meaningful recurring semantic step. Branch arms participating in the
same recurrence stay together. Turning every branch into a micro-method lengthens mutual-tail cycles
and creates callback-like control.

Create another block only for a real boundary:

- another recurring phase;
- a child-machine handoff;
- completion or rejection;
- a diagnostic or cold exception;
- a sealed performance or ownership boundary.

Generated VMs use finer residual functions for a different reason: each foreign instruction
occurrence needs a unique control identity so fixed dispatch disappears before tracing. Authored
coarse machines and generated instruction residuals are sibling realizations, not contradictory
granularity rules.

## 5. C declarations and sealed metatypes

C declarations define representation:

- exact field types and offsets;
- struct nesting and arrays;
- pointer constness and ABI shape;
- capacities and domain-specific buffers;
- one allocation for a by-value machine tree.

An FFI metatype defines the behavioral surface:

```lua
ffi.metatype(ConcreteType, {
    __index = sealed_methods,
})
```

The minimal declaration linker provides only:

- closed nominal families;
- parent defaults for genuinely shared behavior;
- concrete leaf overrides;
- stable method projection;
- one-time FFI metatype sealing.

### 5.1 The library boundary

The declaration linker is the reusable library. It exists because asking every machine author to
repeat safe descriptor construction and `ffi.metatype` assembly would add noise and invite subtle
inconsistencies.

The library absorbs only mechanical boilerplate:

```text
context name, version, and C prefix checks
  → ffi.cdef submission
  → ctype binding and duplicate ownership checks
  → product or closed-family registration
  → parent-default and leaf-override collection
  → concrete constructor and membership operations
  → one-time metatype assembly and sealing
```

The user still owns every semantic choice:

```text
exact C fields and capacities
named public entries
borrowed owners and cleanup
coarse recurring methods
child-machine fields
stable continuation wiring
terminal outcomes
projections and reports
```

The library must not grow a universal `Machine` base, hidden frame, generic state tree, command
protocol, scheduler, lifecycle convention, or control dispatcher. It removes declaration ceremony;
it does not author the machine.

At seal time, parent defaults are copied into concrete leaf method tables. Runtime calls use the
concrete metatype directly. There is no dynamic parent lookup, class tag, visitor, or rule engine in
the hot path.

Metatypes do not make arbitrary C access safe. Declared fields remain writable, pointers do not retain
owners automatically, C code can mutate memory, and GC finalizers are not deterministic release. The
behavioral seal must be combined with entry ownership and disciplined pointer use.

The division of authority is:

```text
ffi.cdef       → physical representation
metatype       → stable behavioral vocabulary
module closure → private capabilities and projected continuations
public entry   → initialization, ownership, cleanup
CPS methods    → legal control graph
```

## 6. Physical and control composition

Composition has independent physical and behavioral axes:

```text
physical composition = nested state by value
control composition  = parent/child continuation handoff
lifetime composition = parent owns child
concern synchronization = root owns transition order
```

### 6.1 Static machine tree

```c
typedef struct {
    ButtonMachine save;
    ButtonMachine close;
} ToolbarMachine;

typedef struct {
    ToolbarMachine toolbar;
    SceneMachine scene;
    StatusMachine status;
} UiMachine;
```

This machine tree has one allocation, one root owner, exact static offsets, and no generic node type.
The C struct tree is the ownership tree.

### 6.2 Parent/child handoff

```lua
local after_child = Parent.after_child

function Parent:cycle(owner)
    return self.child:cycle(owner, self, after_child)
end

function Child:cycle(owner, parent, completed)
    -- Child owns its transition.
    return completed(parent, owner)
end

function Parent:after_child(owner)
    return self:next_concern(owner)
end
```

The continuation is stable and unbound. It is not allocated per transition, stored in CDEF state, or
hidden in a callback registry. The parent owns what a child outcome means next.

### 6.3 Dynamic children

Use the narrowest physical form required by the domain:

```text
fixed heterogeneous children → named by-value fields
bounded homogeneous children → exact C array + count
relocatable dynamic children → typed index or generation handle
shared independent lifetime  → explicit owner + pointer or handle
```

A heterogeneous tagged union is admitted only when the alternative must genuinely persist in physical
storage. One domain machine owns decoding that tag. Do not turn it into a universal machine-node
dispatcher.

### 6.4 Tree versus graph

The ownership structure is often a tree. The control structure is a graph: it can branch, recur,
join, suspend, and return to parents. Do not force the control graph into stored parent/child tags.
Physical nesting answers lifetime; CPS answers execution.

## 7. Lifetime follows composition

The model gives each lifetime one visible representation:

```text
root machine        → Lua owner of one concrete cdata allocation
owned child         → embedded struct with root lifetime
temporary value     → local or CPS argument
borrowed Lua memory → C pointer plus forwarded Lua owner
dynamic entity      → typed handle resolved by owning store
suspended work      → durable identity, generation, and payload
external resource   → explicit release with finalizer only as fallback
```

A borrowed input entry has one safe shape:

```lua
function Machine:run(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    local result = self:cycle(owner)
    self.input = nil
    return result
end
```

The Lua owner crosses every CPS edge, so the GC cannot reclaim the borrowed allocation. The public
entry clears the pointer before return. Every terminal outcome returns through that boundary.

By-value children need no independent allocator or destructor. Pointer-owned children are reserved for
intrinsic sharing or dynamic lifetime. A temporary resolved pointer or lease cannot survive suspension;
the durable handle can.

The pattern does not magically make arbitrary pointers safe. It makes ownership mistakes visible by
requiring a representation choice.

## 8. Synchronized concern machines: MVU without command interpretation

A root can synchronize several state machines for separate concerns:

```c
typedef struct {
    InputMachine input;
    ModelMachine model;
    SelectionMachine selection;
    LayoutMachine layout;
    PaintMachine paint;
    uint64_t epoch;
} AppMachine;
```

The application machine owns deterministic order:

```text
external event
  → input concern
  → model concern
  → selection concern
  → layout projection
  → paint projection
  → commit epoch
```

Conceptually:

```lua
function App:dispatch(owner, event)
    self.epoch = self.epoch + 1
    return self.input:apply(owner, event, self, after_input)
end

function App:after_input(owner, change)
    return self.model:synchronize(owner, change, self, after_model)
end

function App:after_model(owner, model_view)
    return self.layout:project(owner, model_view, self, after_layout)
end

function App:after_layout(owner, layout_view)
    return self.paint:commit(owner, layout_view)
end
```

This resembles Elm's deterministic model/update/view discipline, but immediate commands are direct
control edges. There is no generic command value, command interpreter, feedback mailbox, or universal
scheduler.

An immediate external effect is an explicit capability edge. A delayed effect must survive and
therefore becomes an exact physical request carrying object identity, continuation identity, payload,
and generation. That record is not a universal command language; one effect machine owns its decoding
and resumption.

Concern machines own facts. The root owns synchronization. A concern does not secretly route into
another concern through callbacks.

## 9. Projections and reuse frontiers

Transitions mutate owned machine state. Projections observe it and derive the next semantic world:

```text
component state
  → view declarations
  → measured layout projection
  → render projection
  → backend submission
```

For an ECS:

```text
component/archetype state
  → query projection
  → system transition
  → visibility projection
  → render extraction
```

Each projection states what invalidates it. If layout depends on model geometry and viewport size,
those facts belong in the layout input. Unrelated paint color should not falsely invalidate geometry.

A projection can be a caller-owned CDEF buffer, a typed report, an immutable Lua value, or another
exact domain product. It is not a generic cache map.

A staging owner may act as a projection foundry: one semantic query can produce aligned executable,
layout, control, diagnostic, and backend facets. When durable compiler facts are involved, the bundle
belongs in precise ASDL products/unions/spines/facets with stable identity. Lazy demand order is not
backend order; deterministic consumers project through stable source or spine order.

### 9.1 Reusable retained UI: local state, parent joins, and parallel projections

A retained UI is a strong exotyped-machine example because it combines runtime-created component topology, reusable
local behavior, nested ownership, input routing, responsive layout, ordered rendering, external resources, and a host
event loop. The LÖVE component implementation uses the Elm ownership idea without importing Elm's runtime mechanics.
There is no universal component interface, boxed `Msg`, message wrapping, `Cmd` list, virtual DOM, or
generic update dispatcher.

The host constructs first-class component owners with ordinary no-parentheses Lua table calls:

```lua
local Card = Ui.MetricCard { bar = Ui.SparkBar {}, count = 10 }
local Grid = Ui.CardGrid { card = Card, count = 12 }
local Dashboard = Ui.Dashboard {
    toolbar = Ui.Toolbar { button = Ui.Button {}, count = 4 },
    sidebar = Ui.Sidebar { button = Ui.Button {}, count = 7 },
    workspace = Ui.Workspace { header = Ui.Header {}, grid = Grid },
    status = Ui.StatusBar {},
}
```

Equivalent descriptions intern to one immutable owner. `LuaShape` recursively composes child factory quotations into
exact Lua classes and constructors. `RuntimeProgram` binds the UI-specific CPS graph and seals those classes. Neither
owner descriptions nor property queries survive in component instances. CDEF and GCC are absent from this UI path.

The generated Lua ownership tree is concrete:

```text
DashboardState
├── ToolbarState
│   └── ButtonState[4]
├── SidebarState
│   └── ButtonState[7]
├── WorkspaceState
│   ├── HeaderState
│   └── CardGridState
│       └── MetricCardState[12]
│           └── SparkBarState[10]
└── StatusBarState
```

A parallel layout tree owns the corresponding derived geometry:

```text
DashboardLayout
├── ToolbarLayout
│   └── ButtonLayout[4]
├── SidebarLayout
│   └── ButtonLayout[7]
├── WorkspaceLayout
│   ├── HeaderLayout
│   └── CardGridLayout
│       └── MetricCardLayout[12]
│           └── SparkBarLayout[10]
└── StatusBarLayout
```

These are exact generated Lua classes, not instances of a generic `Component` node. Reuse comes from composing the
same concrete leaf factory into several concrete parents. Toolbar and sidebar both own button arrays, but each parent
assigns different meaning to activation. The ownership tree answers lifetime; it does not encode behavioral dispatch.

#### 9.1.1 Leaf-local updates

A leaf owns every mutation of its local state. Its operation receives the concrete parent, root
computation, and stable peer exits:

```lua
function Button:set_hovered(value, parent, dashboard, cc, changed, unchanged)
    value = value and 1 or 0
    if self.hovered == value then
        return unchanged(parent, dashboard, cc, self)
    end
    self.hovered = value
    self.revision = self.revision + 1
    return changed(parent, dashboard, cc, self)
end
```

`changed` and `unchanged` are immediate alternatives, so they are control edges rather than durable
message values. Activation uses the same shape. A button does not know whether it is a toolbar action or
navigation item. The parent continuation gives that outcome its domain meaning.

Selection demonstrates the ownership rule in both directions. The newly activated button selects itself.
If the old sibling must be deselected, the parent does not write the sibling's fields. It tail-calls the
old button's `set_selected` operation and joins at a named `old_selection_cleared` continuation. The leaf
owns local mutation; the parent owns sibling coordination and the next transition.

#### 9.1.2 Routing without a message runtime

The LÖVE boundary classifies external events and calls named application entries. Pointer routing then
walks the known component concerns in deterministic order:

```text
Dashboard:pointer_moved
  → Toolbar:pointer_moved
  → Dashboard:toolbar_pointer_changed|unchanged
  → Sidebar:pointer_moved
  → Dashboard:sidebar_pointer_changed|unchanged
  → CardGrid:pointer_moved
  → Dashboard:grid_pointer_changed|unchanged
  → Dashboard:pointer_routed
```

Walking every relevant concern clears stale hover state without a generic bubbling or capture protocol.
The dashboard stores only facts that must survive transitions: current and target concern, pressed
concern and index, and recurrence cursors. A synchronous pointer coordinate remains in the exact input
facet. Press and release route through the durable pressed identity so activation remains correct even
when release is a distinct host callback.

This is not a claim that all UIs must route this way. A dynamic scene may require a typed hit projection
or generation handles. The rule is narrower: routing topology and durable identities must be exact domain
facts, not string tags, boxed messages, or a generic component registry.

#### 9.1.3 Recursive projection and flattening

Component state is not submitted directly to LÖVE. The root owns a one-way projection pipeline:

```text
nested component state
  → responsive nested layout projection
  → recursive paint projection
  → ordered backend frame facets
  → LÖVE resource owner
```

Layout mirrors state structurally, so a card projects against its corresponding card layout and a spark
bar against its corresponding bar layout. Responsive column count, visibility, scrolling, and clipping
are layout facts. They do not bloat button or card source state.

Projection order is a direct CPS graph:

```text
Dashboard:project
  → Toolbar:project → Button:project recurrence
  → Sidebar:project → Button:project recurrence
  → StatusBar:project
  → Header:project
  → CardGrid:project → MetricCard:project recurrence
                     → SparkBar:project recurrence
  → Dashboard:grid_projected
  → Application:paint_ready
```

The parent carries durable `projection_cursor` and `bar_cursor` fields where recurrence spans proper-tail
edges. These fields are not a universal program counter. Each cursor names one exact bounded relation
owned by its concrete container. Local regular work may still use an ordinary bounded loop when it does
not cross a semantic handoff.

The completed projection fills exact-capacity Lua arrays for vertices, indices, two geometry batches, retained text,
images, and one clip. The residual draw function directly submits shell geometry, shell text, clip push, workspace
geometry, images, remaining text, and clip pop. No generic segment-kind stream or renderer dispatcher survives.

#### 9.1.4 Resource and host ownership

Component state, layout, paint arrays, metrics, and the driver remain Lua-owned. Numeric content and resource handles
identify LÖVE values; the Lua resource owner resolves them and lazily caches retained `Text`, `Mesh`, images, shaders,
canvases, and quads. Resource materialization is separate from exotype property evaluation, which finishes first.

The generated Lua driver owns the application and metrics. One bounded `Driver:turn` drains events, samples
authoritative logical and drawable dimensions, DPI, focus, visibility, and time, selects render or idle, presents,
records metrics, and returns to LÖVE. The `love.run` closure captures that stable entry once.

#### 9.1.5 What is retained from Elm

| Elm idea | Exotyped Lua+CPS realization |
|---|---|
| local model ownership | child object constructed by the parent factory |
| local update | generated concrete leaf method |
| parent message wrapping | parent-owned named continuation |
| `update` result alternative | changed/unchanged/activated/rejected control exit |
| view tree | parallel generated layout and paint projections |
| command value | direct capability edge, or exact durable request if suspended |
| runtime dispatch | none; concrete method and direct CPS edge |
| virtual DOM diff | none; revisioned retained arrays |

The reusable unit is therefore not `Component<Model, Msg, View>`. It is the conjunction of one concrete
owned state product, its leaf-local operations, its corresponding projection product, and the parent
continuations that assign outcomes meaning.

#### 9.1.6 Granularity and applicability

CPS belongs at child completion, container recurrence, concern synchronization, projection completion,
and rejection. Arithmetic for a rectangle, color choice, and one renderer append remain ordinary local
work. This avoids replacing a component runtime with callback-shaped micro-CPS.

The pattern fits a stable retained interface whose topology is reused enough to justify materialization. Different
cardinalities create different factories and exact paint capacities. Truly changing documents should use a separate
dynamic ownership model rather than generating a fresh exotype for each edit. In both cases, local state mutates at
its owner, parents own coordination, projections flow outward, and known edges execute directly.

The reference implementation is:

```text
lua/ui/backends/love/component_state.lua    exotype constructors and Lua shape quotations
lua/ui/backends/love/component_machine.lua  UI behavior quotation binder and CPS composition
lua/ui/backends/love/components.lua         no-parentheses default composition
demo/love_components/                       interactive LÖVE 11.5 application
tests/ui/test_ui_love_component_state.lua   owner, factory, capacity, and sealing checks
tests/ui/test_ui_love_component_machine.lua transition and projection checks
```

## 10. ECS and data-oriented composition

CDEF naturally describes archetype chunks and component columns:

```c
typedef struct {
    Position *position;
    Velocity *velocity;
    uint32_t count;
} MovingChunk;
```

A concrete system machine processes substantial work inside one leaf and hands off at a phase
boundary:

```text
movement chunk
  → collision concern
  → lifetime concern
  → visibility concern
  → render extraction
```

The granularity rule is critical: process entities inside a coarse leaf; use CPS between systems,
chunks, real phases, and exceptional outcomes. One continuation transition per component access would
recreate callback overhead rather than composition.

A fixed application pipeline does not require a generic scheduler. If scheduling is genuinely dynamic,
the scheduler is its own exact machine with owned queues and typed handles.

## 11. Generated CPS Specialization

GCPS is the generated realization of the same state-machine view:

```text
fixed foreign bytecode
  → decode and validate
  → resolve constants and control edges
  → query concrete lazy owners
      → memoized occurrence closure
      → readable listing projection
      → control/operand projection
  → bind direct successor upvalues once
  → LuaJIT specializes runtime values and recurring paths
```

Every reached instruction occurrence receives a unique residual closure. Known successors are direct
tail calls. Metatable or owner dispatch occurs only while staging the occurrence; the recurring VM path
has no opcode dispatch or program counter.

Specialization remains split deliberately:

```text
fixed program/control facts → lazy owner residualization
dynamic value/path facts    → LuaJIT tracing
```

The same owner query produces executable and descriptive facets. A readable source listing remains
available for diagnostics and inspection without maintaining or loading a second source generator.
Publishing occurrence identity before dependency binding closes cycles. Add a prepare/seal boundary
when runtime first-hit allocation is unacceptable.

This is the broader staging lesson: dynamic owner methods may produce bundles of named residual facets,
but hot consumers receive direct code and facts only. In migrated Lalin compiler code, ASDL leaf
methods own these queries and durable bundles are schema products/facets rather than Lua side tables.

There is no generic optimization IR, structured-control reconstruction, static value-type inference
pass, register allocator, duplicate template/source materializer, or native emitter.

### 11.1 Forward-compatible Lua

A practical application is a modern Lua compatibility layer:

```text
Lua 5.5 bytecode
  → version-specific decoder and opcode semantics
  → residual Lua CPS
  → LuaJIT
```

This bypasses LuaJIT's Lua 5.1 parser and bytecode format while retaining its tracing backend. Full
compatibility still requires exact integers, calls, closures, `_ENV`, varargs, metamethods, errors,
to-be-closed values, coroutines, and standard-library behavior. Native Lua 5.5 C modules have a
different C API and ABI and are not solved by bytecode execution.

## 12. Validated transient-state flattening

The WebAssembly experiment showed that control monomorphization alone is insufficient for a stack VM.
An explicit residual stack retained facts already known by validation:

```text
self.stack + self.sp
```

The better residual projects stack topology into function signatures:

```lua
pc_12_i32_add = function(self, v1, v2)
    return pc_13_local_set(self, bit.tobit(v1 + v2))
end
```

At branches and loop headers, CPS parameters are natural phi inputs. The flattened residual has no
runtime operand-stack table or stack pointer.

This generalizes beyond Wasm:

> If transient topology is statically known, represent values on control edges rather than in mutable
> machine state.

The rule applies to validated expression stacks, parser captures, query columns, layout intermediates,
and fixed synchronization payloads.

## 13. The specialization stack

The complete architecture has several independent specialization opportunities:

```text
1. Physical specialization
   concrete CDEF layout + concrete leaf metatype

2. Control specialization
   exact authored coarse graph or generated residual CFG

3. Operand specialization
   literal constants, indices, successor functions, capacities

4. Transient-topology specialization
   validated stack/dataflow values become CPS arguments

5. Runtime specialization
   LuaJIT observes concrete values, branches, pointers, and recurring paths
```

Do not duplicate LuaJIT's job with a speculative static type-inference system. Specialize what is
actually fixed; let the tracer guard what remains dynamic.

## 14. LuaJIT trace-shape discipline

The architecture exposes good traces but does not guarantee them automatically.

### 14.1 Leaf-owned hot prototypes

LuaJIT associates traces with Lua function prototypes. Alternating incompatible ctypes through one
shared hot parent prototype creates trace contention. Hot recurrence belongs to concrete leaves;
shared methods remain entries, terminals, diagnostics, and cold behavior.

### 14.2 Recurrence depth

Nested handoffs and generated instruction chains must fit LuaJIT's trace capacity. A depth-eight
nested experiment failed catastrophically under the default `loopunroll` limit and closed with a
measured higher limit. A synthetic generated-CPS probe accepts `loopunroll=2147483647` and closes
with raised storage capacities through depth 496, but fails at depth 512 from snapshot and trace
ceilings. LuaJIT's IR references, snapshot counts, and trace numbers retain hard 16-bit boundaries.
Raising behavioral retry and instability limits to `INT32_MAX` is pathological rather than useful.
Deep composition therefore has an explicit measured trace-capacity contract, not a truly uncapped
mode.

### 14.3 Structured loops inside CPS

Ordinary `if`, `elseif`, and bounded local loops are valid inside a coarse block. A poorly placed
inner `while` can force the recorder through an inner-loop exit and destroy the intended recurrence.
Trace shape must be inspected and benchmarked, not inferred from labels such as 'CPS' or 'structured'.

### 14.4 JIT-independent semantics

Every machine must remain correct with `-joff`. Tracing is an optimization, never semantic control.

## 15. Optional native leaves

An in-memory `libtcc` experiment tested FFI calls at three granularities: per opcode, per guest
iteration, and per whole region. LuaJIT can close a trace containing immutable typed C function calls,
but it cannot trace through or inline the C body.

The result was conditional: a whole integer region measured 0.552 ns per iteration, while a whole
mixed floating-point region measured 2.488 ns versus the then-current eager flattened Lua CPS at 0.996
ns. TCC construction
also cost 152.895 microseconds per module. The chosen lazy owner costs approximately 19 microseconds
for setup and 106 microseconds for setup plus first reach with private occurrence cloning. Historical
source and template prototypes cost about 88 and 46 microseconds and were removed after the lazy owner
path matched their hot throughput and subsumed their artifacts.

Therefore TCC is not part of the canonical architecture. The default backend is LuaJIT itself. A native
leaf is justified only when profiling proves a coarse dense region, its call boundary is amortized,
and its semantics do not require C-to-Lua callbacks.

```text
Lua CPS owns dynamic and compositional control.
Optional native code owns only a proven coarse leaf.
```

## 16. Two realization forms, one view

The authored and generated forms share the same conceptual core but retain different implementation
contracts:

| Concern | Authored CDEF machine | Generated residual machine |
|---|---|---|
| Persistent state | exact concrete cdata | exact guest-owned `self` representation |
| Behavior | sealed metatype methods | lexical residual functions |
| Normal block granularity | coarse semantic recurrence | one unique foreign occurrence |
| Edge | proper-tail method call | proper-tail residual call |
| Fixed facts | ctype, constants, leaf prototype | bytecode operands, constants, successors |
| Transient facts | locals and method arguments | residual CPS arguments |
| Composition | nested by value + stable continuation | bound children + direct successor graph |
| Native execution | LuaJIT | LuaJIT |

They must not be collapsed into one generic machine API. The commonality is a design pattern, not an
imported runtime.

## 17. Architectural laws

### Law 1 — Exact ownership

Every persistent fact has one exact owner. Side tables and hidden pointer conventions are not an
ownership model.

### Law 2 — Direct control

Known semantic edges are direct proper-tail calls. Immediate alternatives are named exits, not boxed
actions.

### Law 3 — Structural composition

Parents own child lifetime physically and child outcome meaning behaviorally.

### Law 4 — Lifetime representation

Nesting expresses ownership, parameters express temporary access, and handles express durable
external identity.

### Law 5 — Specialize fixed facts

Do not ask the runtime dispatcher or tracing JIT to rediscover operands, constants, successors, or
validated transient topology already known before execution.

### Law 6 — Concrete hot behavior

Incompatible physical types and control occurrences receive distinct hot function identities.

### Law 7 — Projection direction

Transitions mutate state; projections observe state; consumers do not callback into projections to
mutate their source.

### Law 8 — Explicit suspension

Only durable facts cross suspension. Borrows, temporary pointers, and hidden closure state do not.

### Law 9 — No universal runtime

Do not introduce generic machine nodes, state bags, command interpreters, handler registries,
schedulers, opcode APIs, or optimizer frameworks merely because several domains share the pattern.

### Law 10 — Measured execution

Correctness is differential and JIT-independent. Performance claims require isolated-process
benchmarks and trace inspection.

## 18. Counterpatterns

### Generic machine node

```text
MachineNode { kind, state, children, handlers, options }
```

This erases exact ownership and moves behavior into manual dispatch.

### Command-return architecture

```text
transition → { action = "layout" } → command switch → layout
```

If the command is consumed now, call the layout continuation directly. Encode only genuinely delayed
portable effects.

### Callback tree

Callbacks reverse ownership and hide missing outcomes. A child selects one complete continuation; the
parent wires every outcome.

### Runtime operand stack for validated topology

If validation fixes the stack signature, mutable stack storage duplicates static dataflow facts.

### Per-entity or per-field CPS

CPS between meaningful phases composes. CPS around every tiny operation becomes callback overhead.

### Shared hot prototype

One recurring function alternating incompatible ctypes or program occurrences invites trace contention.

### Fine FFI bouncing

Lua → C → Lua per opcode does not let LuaJIT optimize through C. Use a coarse native leaf only when
measurement proves it.

### Framework extraction

A generic VM/UI/ECS framework built before several independent domains prove the same exact helper
would replace a clear pattern with indirect plumbing.

## 19. Evidence

The current evidence is broad enough to establish the recurring architecture, but not broad enough to
claim universal performance.

### 19.1 Authored CDEF machines

```text
prototype isolation
  shared hot parent prototype       0.899 ns/step
  leaf-owned hot prototypes         0.347 ns/step

nested by-value handoff
  depth 1                           0.637 ns/step
  depth 8                           1.598 ns/step

synchronized concern tree
  model → layout → paint            1.483 ns/transition
  layout → paint                    1.487 ns/transition
  unchanged named exit              0.643 ns/transition

JSON mixed objects
  FFI tape only                     3.875 ns/byte
  tape then Lua tables              7.371 ns/byte
  direct Lua tables                 7.841 ns/byte
  lua-cjson direct tables           4.883 ns/byte
```

The glob matcher passed 289,636 exhaustive pattern/text pairs under JIT and `-joff`. The 104-byte
concern-tree root embeds Input, Model, Layout, and Paint machines by value; its synchronized paths
allocate no memory per transition after trace warmup.

The retained LÖVE component machine adds a larger runtime-generated composition result:

```text
default property demand closure          13 queries
default vertex/index capacities       592 / 888
default text/image capacities           26 / 12
alternate vertex capacity                   140
component-machine CALLT edges                130
```

At 1,000 × 650, a dirty frame projects 12 cards and 120 spark bars into two geometry batches, 12 image
draws, 26 retained-text draws, one clip, and 40 actual draws. After warmup, the measured dirty benchmark
reported no mesh or retained-text rebuilds. Representative LÖVE 11.5 measurements on the Radeon 780M
were approximately 52 microseconds of active idle-turn work, 0.50 milliseconds of active dirty-turn work under JIT,
and 0.65 milliseconds of active dirty-turn work with `-joff`. Presentation remained a separate VSync-dominated cost.
These are implementation observations, not universal UI performance claims.

The owner/factory, machine, resize smoke, and graphical smoke tests pass under normal JIT execution and with `-joff`.

### 19.2 Lua 5.5 GCPS

```text
integer loop    1.013 ns/guest iteration
mixed loop      0.870 ns/guest iteration
```

The sample residualizes 23 reached instructions as nine exotype-owned blocks. Setup measures approximately
21 microseconds per module; setup plus first reach measures approximately 152 microseconds in the active
100-module benchmark. Twenty modules with 40 alternating child functions measure approximately 0.975 ns
per guest iteration. Frame, instruction, and block properties disappear after residualization.

### 19.3 WebAssembly GCPS

```text
shape                     integer sum   mixed sum
historical explicit stack     5.417 ns    5.129 ns
historical eager flat         4.632 ns    0.996 ns
canonical lazy-owner flat     3.501 ns    0.883 ns
direct LuaJIT                  0.641 ns    0.645 ns
V8 WebAssembly                0.232 ns    0.654 ns
```

Wasm retains its concrete lazy occurrence owners and private prototypes. Lua 5.5 now uses proper prototype,
instruction, and block exotypes with fused block quotations. Both publish identities before cyclic binding and
execute only direct residual CPS, but they deliberately keep domain-specific quotation and representation rules.
The exact-i32 result remains trace-sensitive at 0.748–3.761 ns; mixed ranged from 0.771–3.769 ns.

### 19.4 TCC boundary experiment

```text
boundary              integer sum   mixed sum
TCC call per opcode       3.302 ns     5.053 ns
TCC call per iteration    3.657 ns     2.614 ns
TCC whole region          0.552 ns     2.488 ns
```

This evidence keeps native leaves optional rather than architectural.

## 20. Applicability

The composed state-machine view is promising for:

- parsers, scanners, protocol engines, and decoders;
- retained UI interaction, layout, and rendering concerns;
- ECS systems, chunk pipelines, and query projections;
- animation, workflow, and deterministic service machines;
- compatibility VMs and fixed bytecode languages;
- query, pattern, and embedded DSL machines.

It is less suitable for a pure scalar helper, a short throwaway script, constantly changing code that
never amortizes construction, or a domain whose control and ownership alternatives are not yet
understood.

## 21. What is and is not consolidated

This paper consolidates the coherent design vision. The implementation contracts remain deliberately
separate:

- `experiments/cdef_schema/ARCHITECTURE.md` — binding authored CDEF+CPS machine pattern;
- `exotyped_cps_machines.md` — beginner-oriented Exotyped CPS design pattern;
- `generated_cps_specialization_whitepaper.md` — foreign-bytecode specialization report;
- `experiments/lua55/ARCHITECTURE.md` — Lua 5.5 generated implementation contract;
- `experiments/wasm_gcps/README.md` — Wasm stack-flattening experiment;
- `experiments/wasm_gcps/TCC_FFI.md` — optional native-leaf boundary experiment;
- `docs/OBJECT_REGION_PROJECTION_PATTERN.md` — compiled object/region/projection vocabulary.

ASDL is not required to model the runtime machine tree. CDEF already models physical ownership. ASDL
becomes appropriate only if a durable authored source model must generate several artifacts such as
CDEF layout, wiring, diagnostics, and projections. Even then, the runtime artifact remains the exact
machine rather than an ASDL interpreter.

## 22. Conclusion

The coherent architecture is a composed state-machine view of stateful software on LuaJIT:

```text
exact owned state
  + sealed concrete behavior
  + proper-tail control
  + structural lifetime
  + direct concern synchronization
  + explicit projections
  + cold specialization of fixed facts
  + runtime specialization by LuaJIT
```

CDEF gives physical truth for authored scalar machines. Metatype sealing attaches stable behavior.
Coarse CPS exposes domain control. By-value nesting turns ownership into layout and lifetime. Stable
continuations synchronize child machines and independent concerns without commands or callback
registries. GCPS projects fixed foreign programs into the same executable control view. Validated
transient-state flattening prevents static dataflow from becoming mutable runtime state.

The deepest rule is simple:

> **Represent each fact according to its lifetime, let its owner define its behavior, and make every
> known control edge executable directly.**

