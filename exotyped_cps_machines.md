# Exotyped CPS Machines

## Abstract

An exotyped CPS machine is a state machine whose concrete type is created after a host program learns stable
structural information. The host uses that information to generate an exact state representation and a direct
continuation-passing control graph. Instances then execute without consulting the type generator, property system,
or compiler.

The central idea is simple:

```text
learn the shape late, generate the machine once, run the concrete result many times
```

This paper explains the pattern from first principles. It assumes familiarity with ordinary Lua functions and
records, but it does not assume prior knowledge of exotypes, staged programming, CDEF, residualization, or CPS.

The reference implementations are:

```text
experiments/exotyped_cps/
experiments/lua55/cps_exotype_codegen.lua
experiments/exotype_c_emit/
lua/ui/backends/love/component_state.lua
```

The pattern is more important than either implementation. It is not a proposal for a universal runtime framework.

## How to read this paper

If exotypes, staging, and CPS are all new, read sections 1 through 8 in order. They introduce the problem, define
the vocabulary, and separate the three graphs. Sections 9 through 18 explain construction details. Sections 19 and
20 are concrete examples. Sections 21 through 26 cover applicability, mistakes, validation, and implementation.
The glossary in section 27 can be used independently.

A shorter path is:

```text
problem → essential terms → combined idea → three graphs → running example → summary
```

Important sections:

- [The problem](#1-the-problem)
- [Essential terms](#2-essential-terms)
- [The combined idea](#3-the-combined-idea)
- [The four main roles](#4-the-four-main-roles)
- [Three different graphs](#7-three-different-graphs)
- [Binding-time discipline](#8-binding-time-discipline)
- [Composition and fusion](#11-composition-and-fusion)
- [Publish before bind](#14-publish-before-bind)
- [A design pattern, not a universal library](#17-a-design-pattern-not-a-universal-library)
- [Running example lifecycle](#19-running-example-lifecycle)
- [Concrete examples](#20-concrete-examples)
- [Implementation checklist](#26-implementation-checklist)
- [Glossary](#27-glossary)

## 1. The problem

Programs often discover useful structure only after they have started.

Examples include:

- a database schema loaded from a file;
- the fields in a network packet description;
- the topology of a component tree;
- the bytecode instructions in a loaded function;
- a parser grammar selected by a user;
- the dimensions and element type of a numerical kernel;
- the states and transitions in a device protocol.

A conventional static implementation requires this information before the host program is built. A conventional
dynamic implementation keeps the information in tables and interprets it every time an instance runs.

Consider a small arithmetic pipeline described at runtime:

```lua
local stages = {
    { operation = "add", value = 2 },
    { operation = "multiply", value = 3 },
    { operation = "reject_above", value = 100 },
}
```

A direct interpreter might execute it like this:

```lua
for _, stage in ipairs(stages) do
    if stage.operation == "add" then
        value = value + stage.value
    elseif stage.operation == "multiply" then
        value = value * stage.value
    elseif stage.operation == "reject_above" and value > stage.value then
        return "rejected"
    end
end
```

This is flexible, but every execution retains:

- the stage array;
- operation-name lookup;
- a loop over the description;
- branches selecting stage behavior;
- generic result conventions.

The structure of `stages` does not change while the pipeline runs. Reinterpreting it is unnecessary work.

Exotyped CPS moves that work to a staging step. The generated result can look like:

```lua
local function completed(self)
    self.completed = self.completed + 1
    return self
end

local function rejected(self)
    self.rejected = self.rejected + 1
    return self
end

local function stage3(self)
    self.transitions = self.transitions + 1
    if self.value > 100 then
        return rejected(self)
    end
    return completed(self)
end

local function stage2(self)
    self.transitions = self.transitions + 1
    self.value = self.value * 3
    return stage3(self)
end

local function stage1(self)
    self.transitions = self.transitions + 1
    self.value = self.value + 2
    return stage2(self)
end

local function run(self, input)
    self.value = input
    return stage1(self)
end
```

The dynamic stage description has disappeared. The residual program contains only the work needed by this
pipeline.

## 2. Essential terms

### 2.1 Host stage

The host stage is ordinary Lua code that reads files, inspects schemas, decodes bytecode, builds type owners, and
generates executable functions or physical declarations.

The host stage is allowed to use tables, strings, loops, reflection, and allocation. Its work happens before the
generated machine enters its steady-state execution.

### 2.2 Runtime stage

The runtime stage is the generated machine. It should contain exact state and direct functions. It should not
perform property lookup or interpret the structural description used to generate it.

### 2.3 Staged programming

Staged programming divides a computation into phases. An earlier phase constructs code for a later phase.

In this pattern:

```text
Lua host computation → generated Lua/CDEF machine → repeated machine execution
```

### 2.4 Residualization

Residualization means performing known work now and leaving behind a simpler program for later.

For the pipeline, the host already knows that stage one adds `2`. It therefore emits:

```lua
self.value = self.value + 2
```

It does not leave behind:

```lua
if stage.operation == "add" then ...
```

The generated function is called the residual program.

### 2.5 Exotype

An exotype is a first-class type whose representation and behavior are described programmatically. The host can
create a new exotype after reading runtime information, then compile code that uses that type.

An exotype is not a dynamically dispatched runtime object. Property functions execute during staging. Generated
instances have fixed layouts and statically selected behavior.

The idea comes from *First-class Runtime Generation of High-performance Types using Exotypes* by DeVito,
Ritchie, Fisher, Aiken, and Hanrahan.

### 2.6 CDEF

LuaJIT's FFI accepts C declarations through `ffi.cdef`. These declarations can describe compact products, arrays,
unions, pointers, and scalar fields. A generated CDEF type gives machine instances a known physical representation.

CDEF is one possible representation target. It is not mandatory. The Lua 5.5 experiment uses a Lua-owned register
frame because registers must retain arbitrary Lua values.

### 2.7 State machine

A state machine has durable state and transitions. Durable state survives between transitions. A transition reads
or changes that state and chooses what happens next.

### 2.8 Continuation-passing style

A continuation is a function representing the next computation. In continuation-passing style, a transition calls
its successor explicitly:

```lua
local function parse(self)
    -- Parse one unit.
    return validate(self)
end
```

The form `return validate(self)` is a proper-tail call. It transfers control without requiring the current function
to resume afterward.

CPS makes the machine's control graph visible as function references:

```text
parse → validate → lower → completed
                   └────→ rejected
```

There is no requirement for a scheduler, queue, or universal continuation object.

## 3. The combined idea

Exotypes decide the concrete machine type late. CPS expresses that machine's residual control graph.

```text
stable runtime-discovered facts
  → exotype constructor
  → lazy property queries
  → exact representation
  → direct CPS functions
  → concrete instances
```

The exotype is the staging owner. The concrete state value is the runtime machine.

## 4. The four main roles

### 4.1 Constructor

A constructor receives stable structural parameters and returns a type owner.

```lua
local PipelineType = Pipeline(stages)
local BatchType = Array(RecordType, 8)
```

Equivalent arguments should normally return the same owner. This is interning or constructor memoization.

### 4.2 Owner

The owner is the first-class identity of one generated type. It retains:

- constructor arguments;
- property functions;
- memoized property results;
- a stable name or identity;
- materialized physical information, when applicable.

It does not retain mutable state belonging to a machine instance.

### 4.3 Compiler or materializer

The compiler asks owners for properties and turns their answers into concrete artifacts. It owns temporary work:

- the active property-query stack;
- diagnostics;
- generated names;
- dependency ordering;
- source or quotation buffers;
- the demanded operation closure.

The compiler is the computation in progress. A separate generic `ctx` bag is unnecessary.

### 4.4 Instance

An instance owns runtime values:

```text
current value
registers
counters
child states
handles
durable alternatives
```

Many instances can share one exotype owner and one set of generated functions.

## 5. Properties

A property is a question the compiler can ask a type owner.

Typical questions are:

```text
What is your physical layout?
How do you execute?
How do you sum your fields?
How do you route an event?
Which function is your rejection exit?
```

Properties are evaluated lazily. The compiler asks only questions required by the program being generated.

A property query is identified by:

```text
owner identity + property identity + property arguments
```

Its result is memoized. Asking the same question again returns the same result.

This matters because the order of requests is controlled by compilation, not by the type author.

## 6. Why properties are lazy

Suppose a tree stores an array of more trees:

```text
Tree
├── value
└── children: Array(Tree)
```

The layout of `Tree` depends on the layout of `Array(Tree)`. The behavior of `Array(Tree).print` depends on
`Tree.print`. If the compiler tries to finish every property of one type before touching another, it can create a
false cycle.

Lazy properties permit the useful order:

```text
Array(Tree).layout
→ Tree.layout
→ Tree.print
→ Array(Tree).print
```

Only the required property is resolved at each step.

Lazy properties also support an open set of operations. An owner does not need to enumerate every possible method
before any code is compiled.

## 7. Three different graphs

The pattern becomes easier to reason about when three graphs are kept separate.

### 7.1 Property graph

The property graph exists during staging.

```text
Array4.Sum
  → Record.Sum
  → Record.Layout
Array4.Layout
  → Record.Layout
```

Its nodes are property queries. Nested queries form its edges. A query that recursively requires its own unfinished
result is an error.

### 7.2 Ownership graph

The ownership graph describes physical runtime state.

```text
Batch
├── items[4] by value
│   └── Record { x, y, z }
└── transitions
```

For CDEF, this graph determines fields, offsets, arrays, unions, pointers, and stores.

### 7.3 Control graph

The control graph describes runtime behavior.

```text
run → stage1 → stage2 → stage3 → completed
                                 └→ rejected
```

Its edges are stable proper-tail function references.

A cycle in the control graph is normal:

```text
loop_body → loop_header → loop_body
```

A cycle in property evaluation is usually an error. These are not the same kind of cycle.

## 8. Binding-time discipline

Every fact should be placed at the stage where it becomes stable.

| Fact | Representation |
|---|---|
| Known while writing the constructor | Constructor code |
| Stable when creating a generated family | Exotype parameter |
| Stable while compiling one operation | Generated code |
| Durable per instance | State field |
| Immediate runtime choice | CPS exit |
| Shared variable-cardinality object | Typed handle or store |

Examples of useful exotype parameters:

- field names and field types;
- fixed component topology;
- bytecode opcode and operands;
- function arity;
- fixed array length;
- parser grammar;
- continuation identities.

Examples that should usually remain runtime values:

- mouse coordinates;
- current register values;
- current source position;
- frequently changing lengths;
- individual messages;
- transient errors.

A useful question is:

> Will this fact remain stable long enough, and be reused enough, to justify generating a type or function for it?

## 9. Layout properties

A layout property describes runtime representation. It does not necessarily mean CDEF.

Possible layout results include:

```text
C data product
C union
tagged C union
pointer-based recursive record
Lua-owned frame
handle-backed resource record
```

For a fixed batch, a C product might become:

```c
typedef struct {
    Record items[4];
    uint32_t transitions;
} Batch4;
```

For a Lua bytecode function, the layout might instead say:

```text
Lua frame
├── register table sized for maxstacksize
└── top index
```

The representation should match the values it must own. A C array cannot directly retain arbitrary Lua tables,
strings, and functions safely, so CDEF is not automatically the best target.

## 10. Behavior properties and quotations

A behavior property does not execute the runtime operation. It produces a description of the operation for the
next stage.

This staged description is called a quotation.

The exact quotation vocabulary should be local to the domain. A useful small distinction is:

### Expression quotation

Produces a value and can be nested into another expression.

```text
Record.Sum → self.x + self.y + self.z
```

### Effect quotation

Produces ordered mutations.

```text
Record.Scale → multiply x, y, and z by factor
```

### CPS quotation

Produces a function with explicit successor dependencies.

```text
Pipeline.Run → initialize value, then tail-call Stage1
```

These alternatives should not be represented by one table with unrelated optional fields. An expression and a
control transfer obey different composition rules.

Quotations are not a generic runtime IR. They are temporary, target-specific staging values that disappear after
code generation.

## 11. Composition and fusion

Exotype constructors compose by querying child properties.

Suppose `Array(Record, 4).Sum` asks `Record.Sum` for its expression. The array property can splice that expression
four times:

```lua
return self.items[0].x + self.items[0].y + self.items[0].z
     + self.items[1].x + self.items[1].y + self.items[1].z
     + self.items[2].x + self.items[2].y + self.items[2].z
     + self.items[3].x + self.items[3].y + self.items[3].z
```

The loop over four elements runs during staging. Runtime receives one fused expression.

The same idea applies to bytecode. Several straight-line instructions can compose into one basic-block function,
while branches and loop headers remain explicit CPS boundaries.

## 12. Demand closure

Compilation begins with one root request:

```text
Application.Run
Prototype.Entry
Serializer.Write
Parser.Parse
```

That property declares or queries other operations. Those operations declare more dependencies. The compiler
continues until no new operations are required.

This finite set is the demand closure.

Only operations in the demand closure are generated. Unused behavior remains unqueried.

This is important for large or open operation sets. It also makes missing behavior visible at the exact request
that needs it.

## 13. Querying versus depending

Composition and control dependency are different actions.

### Query now

A property queries another property when it needs the result to construct its own result:

```text
Array.Sum queries Record.Sum to splice its expression.
```

A recursive query for the same unfinished property is rejected.

### Depend for later control

A CPS quotation declares a dependency when generated code will transfer to another operation:

```text
Loop depends on Stage1 and Completed.
```

Declaring that dependency does not need to evaluate the target recursively at that instant. The compiler can first
publish function identities, then bind their bodies.

This distinction permits cyclic runtime control without permitting cyclic property computation.

## 14. Publish before bind

Consider a loop:

```text
header → body → header
```

If compiling `header` recursively compiles `body`, and compiling `body` recursively compiles `header`, naive code
generation never finishes.

The solution is publish before bind:

```text
1. create the header function identity
2. publish it in the compiler's cache
3. compile body
4. bind body's backedge to the published header
```

For generated Lua source, an entire group can be declared before definitions are assigned:

```lua
local header, body

header = function(self)
    if self.done then return self end
    return body(self)
end

body = function(self)
    self.index = self.index + 1
    return header(self)
end
```

For lazy block generation, a function can be created and cached before successor upvalues are bound.

This work is staging work. Runtime sees direct function references.

## 15. Physical tree, behavioral graph

Physical ownership and behavioral control answer different questions.

A physical tree answers:

```text
Who owns this state?
How long does it live?
Where is it stored?
```

A CPS graph answers:

```text
What happens next?
Where do success and rejection go?
Where does a loop return?
```

A child can be embedded by value in a parent while control moves between parent and child operations in a graph.

Do not force control topology to match memory nesting.

## 16. Physical and behavioral lifetime

Physical layout and generated behavior have different extension rules.

A CDEF type is immutable after declaration and metatype sealing. Incompatible physical facts require a new owner.

Behavior can remain extensible if generated operations are standalone stable functions over the sealed layout. A
later compilation can request another operation without patching the physical type.

This suggests a useful split:

```text
physical unit
  → exact representation and constructor

behavioral program
  → demanded stable functions and listing
```

A caller captures functions once:

```lua
local run = program:entry()
local machine = program:new()

run(machine, input)
```

The hot path does not repeatedly ask `program` to select an operation.

## 17. A design pattern, not a universal library

Exotyped CPS should first be treated as a design pattern.

Different domains need different layout and quotation vocabularies:

- Lua bytecode needs Lua-value frames and basic-block quotations;
- a CDEF component tree needs exact child fields and routing quotations;
- a serializer needs field and buffer-write quotations;
- a parser needs token, diagnostic, and region operations.

Trying to unify all of these into one API can create a generic IR, plugin framework, or runtime abstraction that
the pattern is intended to remove.

A small staging helper may eventually be useful for:

- owner identity;
- constructor memoization;
- property memoization;
- active-query cycle detection;
- query traces.

Even that helper should be extracted only after several independent implementations repeat the same code.

The layout vocabulary, quotation leaves, and materializer should remain concrete to their domain.

## 18. Minimal local implementation shape

A domain implementation needs surprisingly little protocol machinery.

```lua
local function query(compiler, owner, property)
    local key = owner.id .. ":" .. property.id

    if compiler.cache[key] then
        return compiler.cache[key]
    end

    if compiler.active[key] then
        error("cyclic property query: " .. compiler:trace(key))
    end

    compiler.active[key] = true
    compiler.stack[#compiler.stack + 1] = key

    local result = owner.properties[property](compiler, owner)

    compiler.stack[#compiler.stack] = nil
    compiler.active[key] = nil
    compiler.cache[key] = result
    return result
end
```

Production code must also clean up active state when a property raises an error and must distinguish a cached
absent result from an unqueried result. The example shows the essential control flow.

Everything else can remain local:

```text
domain owner classes
domain property identities
domain quotation leaves
domain materializer
domain diagnostics
```

## 19. Running example lifecycle

The complete arithmetic-pipeline lifecycle is:

```text
host reads three stage descriptions
→ constructor interns that stage sequence
→ constructor publishes Pipeline owner identity
→ compiler requests Pipeline.Run
→ Run declares Stage1 and Completed dependencies
→ stage properties declare following stages and rejection
→ compiler reaches a seven-operation demand closure
→ layout property produces a 20-byte state product
→ compiler declares all function identities
→ compiler binds stage, loop, completion, and rejection bodies
→ caller allocates state
→ caller captures Run
→ repeated execution uses only state and direct functions
```

In the reference experiment, the generated physical state is:

```text
Pipeline state: 20 bytes
├── value: int32
├── transitions: uint32
├── completed: uint32
├── rejected: uint32
└── remaining: uint32
```

The stage description, property cache, compiler, and quotation objects are not part of those 20 bytes.

## 20. Concrete examples

### 20.1 Lua 5.5 behavior exotype

The Lua 5.5 experiment demonstrates a behavior-focused exotype application.

A loaded prototype creates:

```text
prototype owner
instruction-occurrence owners
basic-block owners
```

The local first-class properties are:

```text
FrameLayout
EmitInstruction
ExecuteBlock
```

Concrete opcode leaves produce exact quotations such as:

```text
EffectQuote
ForPrepQuote
ForLoopQuote
ReturnQuote
ClosureQuote
RejectQuote
```

A block owner composes straight-line effect quotations. A control instruction terminates the block and names CPS
successors.

For the bundled sample:

```text
23 reached instructions → 9 residual blocks
```

The canonical sample runs at approximately 1.013 ns per integer guest iteration and 0.870 ns per mixed guest
iteration under LuaJIT. With tracing disabled, the measurements are approximately 22.1 ns and 26.6 ns. Better
staging architecture does not guarantee ideal machine code, so trace shape must still be inspected.


### 20.2 Specialized emitted C

`experiments/exotype_c_emit/` demonstrates a physical and behavioral exotype that cooks a native module without
implementing a machine-code assembler.

A runtime stage sequence creates a pipeline owner. Its `StateLayout` property generates an exact C struct with one
`stage_hits[N]` array. Its `CModule` property emits ordinary static C functions for stages, looping, completion,
rejection, and public entry.

```text
runtime stages
→ exotype owner
→ exact C layout and specialized CPS functions
→ GCC shared object
→ LuaJIT FFI function pointer
```

Every C transition is in return position, but generated function boundaries are not an artifact contract. GCC `-O3`
is free to inline, fuse, clone, or erase them. Emitted C is transient compiler input rather than a readable output.
The test validates exact layout and behavior under JIT and `-joff`.

For three stages, the generated state is 40 bytes and the native function-pointer boundary plus four-round pipeline
execution measures approximately 4.9 ns per call on the development machine.

The companion fused-array example keeps buffers and orchestration in Lua. A runtime `f32` or `f64` operation sequence
creates a kernel owner whose properties emit one disposable specialized C module. After an approximately 35 ms GCC
cook, its five-operation `f64` kernel measures approximately 0.291 ns per element and 55 GB/s of effective input/output
traffic. Only the stable FFI pointer, loaded-module owner, and Lua-owned buffers remain during recurring execution.
### 20.3 Exotyped retained UI

The LÖVE retained component backend constructs its component types programmatically at host startup. Its authoring
surface uses ordinary Lua calls whose sole argument is a table, so parentheses are unnecessary:

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

These calls return immutable interned owners rather than component instances. Child types and cardinalities are
structural parameters. Hover state, selection, content handles, scrolling, dimensions, revisions, and animation values
remain instance fields.

The UI-local properties and quotation alternatives are:

```text
LuaShape → ComponentShapeQuote | ApplicationShapeQuote | DriverShapeQuote
RuntimeProgram → RuntimeProgramQuote
```

Every concrete owner leaf answers `LuaShape` by composing child factory quotations. The result contains exact Lua
classes and constructors for one state/layout ownership tree. `RuntimeProgramQuote` binds the UI-specific CPS graph,
publishes cyclic joins, and seals the generated classes.

The UI deliberately does not use CDEF or GCC. Component state, layout, host state, paint buffers, metrics, and the
driver are Lua-owned because they interact with LÖVE resources and change through Lua control. The exotype derives
exact paint capacities from topology: the default owner allocates 592 vertex slots, 888 index slots, 26 text slots,
and 12 image slots instead of inheriting a generic backend bank.

The default demand closure evaluates 13 property queries and binds a behavior graph containing 130 Lua bytecode
`CALLT` edges. Tests also materialize a different owner with two toolbar buttons, three navigation buttons, five
cards, and four spark bars; its exact vertex capacity is 140.

Paint projection no longer emits a generic segment-kind stream. The residual driver submits the known shell, text,
clip, workspace, image, and remaining-text order directly to the Lua LÖVE resource owner. After materialization,
component descriptions, property lookup, active-query tracking, and factory composition are absent from recurring
execution. The same behavior passes with LuaJIT enabled and disabled.

## 21. When the pattern is useful

Exotyped CPS is a good fit when:

- structural information arrives after the host starts;
- that structure remains stable for many operations or instances;
- interpreting the structure repeatedly is costly;
- direct control edges can replace runtime dispatch;
- generated layout or fusion provides a meaningful advantage.

Good candidate domains include:

- serializers and deserializers;
- packet codecs;
- parser families;
- fixed component trees;
- bytecode residualizers;
- numerical kernels;
- device protocols;
- foreign ABI adapters.

## 22. When not to use it

Do not create a new exotype for every transient value.

Poor candidates include:

- individual events;
- mouse positions;
- short-lived messages;
- values that change every turn;
- structures executed only once;
- shapes so numerous that generated type and trace caches cannot be bounded.

LuaJIT FFI types and traces are effectively long-lived. Excessive specialization causes type accumulation, trace
proliferation, compilation latency, and poor reuse.

A generic loop can be better than generating thousands of rarely reused types.

## 23. Common mistakes

### Leaving property lookup in the hot path

Wrong:

```lua
function run(self, operation_name)
    return self.owner.properties[operation_name](self)
end
```

Right:

```lua
local run = compiled_program:entry()
run(machine)
```

### Confusing property cycles with control cycles

A property needing its own unfinished result is an error. A generated loop tail-calling itself is ordinary control.

### Generating one type per value

Specialize on stable shape, not changing data.

### Attaching every possible operation eagerly

Request a root operation and calculate its demand closure.

### Using one optional quotation record

Use exact local quotation alternatives so each composition rule is clear.

### Building a universal runtime

The staging system should disappear. Runtime should not contain generic owner, property, command, or scheduler
objects.

### Assuming generated code is faster

Inspect bytecode, traces, allocations, and physical size. Residual code can still have a worse optimization shape.

## 24. Validation

A serious implementation should test both staging and runtime.

### Staging checks

- equivalent constructor arguments return the same owner;
- each property is evaluated once;
- unused properties remain unqueried;
- true query cycles report a useful trace;
- generated listings are deterministic;
- missing behavior fails visibly;
- physical dependency order is stable.

### Physical checks

- `ffi.sizeof` matches the expected layout;
- by-value children and arrays have correct offsets;
- incompatible layouts create different owner identities;
- borrowed resources remain owned across calls;
- physical types are not patched after sealing.

### Control checks

- generated edges end in proper-tail calls;
- loops close without wrappers or stack growth;
- completion and rejection are distinct exits;
- no per-transition closures are allocated;
- runtime performs no property or opcode dispatch.

### Execution checks

- behavior produces exact expected results;
- tests pass with LuaJIT enabled and disabled;
- stopped-GC runs detect recurring allocation;
- setup latency and first-reach latency are measured separately;
- traced and interpreter performance are both reported.

## 25. Cost model

Materialization has costs:

```text
property evaluation
layout generation
source or closure generation
CDEF parsing when used
Lua function compilation
trace construction
long-lived type and code cache entries
```

Execution can save:

```text
schema interpretation
opcode dispatch
generic loops
boxing
field-name lookup
dynamic method forwarding
unnecessary branches
per-transition allocation
```

Useful metrics include:

- generated owner count;
- property-query count;
- demanded operation count;
- generated function count;
- source or listing bytes;
- materialization time;
- first-reach time;
- instance size;
- trace count and machine-code size;
- runtime cost versus a generic implementation.

The correct specialization granularity is empirical.

## 26. Implementation checklist

A new exotyped CPS application can follow this sequence:

1. Identify stable structural input.
2. Define the owner identity and constructor key.
3. Define the runtime representation needed by instances.
4. Define a small local property vocabulary.
5. Define exact local quotation alternatives.
6. Implement memoized queries with active-cycle reporting.
7. Seed compilation from one root operation.
8. Compute only the demanded operation closure.
9. Publish function identities before binding cyclic edges.
10. Materialize physical representation, if needed.
11. Produce a deterministic listing from the same semantic properties.
12. Capture the root function once.
13. Test JIT and non-JIT execution.
14. Measure setup, first reach, allocation, trace shape, and steady state.
15. Keep the implementation local until repeated designs justify extracting a helper.

## 27. Glossary

**Binding time** — The phase when a fact becomes known and can be fixed.

**Constructor** — A host function that maps structural parameters to an interned type owner.

**Continuation** — A function representing the next computation.

**CPS** — Continuation-passing style; control is transferred by explicitly calling the next function.

**Demand closure** — The complete finite set of operations reachable from one root property request.

**Exotype** — A programmatically defined type whose layout and behavior are supplied by staged properties.

**Host stage** — The Lua computation that reads structure and generates the machine.

**Instance** — One concrete runtime state value created from a materialized owner.

**Owner** — The first-class identity and property provider for one generated type.

**Ownership graph** — The physical relation between runtime state values.

**Property** — A lazily evaluated, memoized question asked of an owner during staging.

**Property graph** — The dependency graph between property queries.

**Proper-tail call** — A call in return position that transfers control without retaining the caller.

**Quotation** — A staged representation of code to be generated for the next phase.

**Residual program** — The concrete program left after known structural work has been performed.

**Residualization** — The act of performing known work early and generating the remaining computation.

**Runtime stage** — Execution of concrete machine instances after staging.

**Staging** — Dividing computation into phases so an earlier phase generates work for a later phase.

## 28. Summary

Exotyped CPS combines two independent ideas:

1. Exotypes create concrete types after stable structure becomes known.
2. CPS turns each generated machine's control flow into direct, explicit successor functions.

The pattern's promise is not abstraction at runtime. Its promise is that high-level, dynamic host code can generate
small, concrete runtime machines.

```text
dynamic description at staging time
  → exact ownership and behavior
  → no dynamic description at execution time
```

Treat this as a design pattern first. Let each domain keep its own precise layout and quotation vocabulary. Extract
only small staging mechanics after multiple implementations prove that the mechanics are truly identical.
