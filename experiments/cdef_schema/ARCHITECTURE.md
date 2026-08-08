# CDEF + coarse CPS machine design pattern

**Frozen experimental baseline.** This document defines the complete authored-CDEF contract.
The broader composed state-machine vision is
[`../../composed_state_machines_whitepaper.md`](../../composed_state_machines_whitepaper.md).
Experiments may measure this pattern, but must not grow it into a VM framework or alternate compiler
backend.

## Intent

A machine is one concrete LuaJIT FFI object whose exact physical state is declared by
`ffi.cdef`. User-authored Lua methods are its executable behavior. Proper tail method calls
are its semantic control edges.

```text
exact concrete ctype
  -> named public machine entry
  -> leaf-owned coarse CPS cycle
       -> direct if/elseif dispatch inside the cycle
       -> tail recurrence to the same cycle
       -> tail transition to another real phase
       -> named completion, rejection, or diagnostic
  -> typed or primitive result
```

There is no semantic tree, arena, interpreter, generic IR, visitor, opcode loop, handler map,
frame planner, or structured-loop emitter. The ctype and its methods are already the machine.

## Vocabulary

```text
ffi.cdef fields        exact persistent physical state
concrete cdata self    machine identity and mutable state
entry method           ownership, initialization, and result boundary
coarse cycle method    hot recurrence and direct conditional dispatch
other cycle method     a genuinely distinct recurring phase
terminal method        completion, rejection, or diagnostic
method parameters      transient values and Lua owners of borrowed memory
return self:next(...)  proper-tail semantic control edge
parent default         shared cold or boundary behavior
leaf override          physical or behavioral specialization
```

A block is coarse when it owns one meaningful recurring semantic step. Coarse does not mean
putting an entire application in one function. It means branch arms that participate in one
hot recurrence stay together instead of becoming callback-like micro-methods.

## Complete authoring shape

```lua
local ffi = require("ffi")
local schema = require("cdefschema")

local S = schema.context {
    name = "glob",
    version = 1,
    prefix = "GlobV1_",
}

S:cdef [[
typedef struct {
    const uint8_t *pattern;
    const uint8_t *text;
    uint32_t pattern_length;
    uint32_t text_length;
    uint32_t pattern_position;
    uint32_t text_position;
    uint32_t star_pattern;
    uint32_t star_text;
} GlobV1_Sensitive;
 ]]

local Glob = S:sum("Glob")
local Sensitive = Glob:leaf("GlobV1_Sensitive")
local NO_STAR = 0xffffffff

-- The public machine entry owns initialization and borrowed-memory sealing.
function Glob:match(pattern_owner, text_owner)
    self.pattern = ffi.cast("const uint8_t *", pattern_owner)
    self.text = ffi.cast("const uint8_t *", text_owner)
    self.pattern_length = #pattern_owner
    self.text_length = #text_owner
    self.pattern_position = 0
    self.text_position = 0
    self.star_pattern = NO_STAR
    self.star_text = 0

    local matched = self:cycle(pattern_owner, text_owner)

    self.pattern = nil
    self.text = nil
    return matched
end

-- This leaf owns its hot prototype and performs direct conditional dispatch.
function Sensitive:cycle(pattern_owner, text_owner)
    if self.text_position >= self.text_length then
        return self:finish(pattern_owner, text_owner)
    end

    local pattern_position = self.pattern_position
    if pattern_position < self.pattern_length
        and self.pattern[pattern_position] == 42 then
        self.star_pattern = pattern_position
        self.star_text = self.text_position
        self.pattern_position = pattern_position + 1
        return self:cycle(pattern_owner, text_owner)
    end

    if pattern_position < self.pattern_length
        and (self.pattern[pattern_position] == 63
            or self.pattern[pattern_position] == self.text[self.text_position]) then
        self.pattern_position = pattern_position + 1
        self.text_position = self.text_position + 1
        return self:cycle(pattern_owner, text_owner)
    end

    if self.star_pattern ~= NO_STAR and self.star_text < self.text_length then
        self.star_text = self.star_text + 1
        self.text_position = self.star_text
        self.pattern_position = self.star_pattern + 1
        return self:cycle(pattern_owner, text_owner)
    end

    return self:rejected(pattern_owner, text_owner)
end

-- Shared cold/default behavior belongs on the family parent.
function Glob:finish(pattern_owner, text_owner)
    while self.pattern_position < self.pattern_length
        and self.pattern[self.pattern_position] == 42 do
        self.pattern_position = self.pattern_position + 1
    end
    if self.pattern_position == self.pattern_length then
        return self:accepted(pattern_owner, text_owner)
    end
    return self:rejected(pattern_owner, text_owner)
end

function Glob:accepted(_pattern_owner, _text_owner) return true end
function Glob:rejected(_pattern_owner, _text_owner) return false end

S:seal()

local machine = Sensitive()
assert(machine:match("a*", "abc"))
```

The production glob and CSV examples contain more exact diagnostics and boundary types, but
they preserve this shape.

## The machine entry

The public entry is conceptually the machine entry. It has four responsibilities:

1. validate or accept Lua-owned arguments;
2. establish borrowed pointers and initialize persistent state;
3. enter the leaf-owned cycle while forwarding owners through every edge;
4. clear borrowed pointers and return the final result.

Use a domain name such as `match`, `scan`, or `run`. A named entry makes ownership and purpose
visible and permits a machine to expose more than one operation.

The frozen pattern uses named entries. `__call` would add only call-site sugar while hiding the
domain operation and requiring special metatype treatment, so the minimal linker does not install
it. It is not a recurrence, generic-for iterator, scheduler, or second control model.

## The coarse cycle

The leaf-owned cycle is the normal hot shape:

```lua
function Concrete:cycle(owner)
    if recurring_case_a then
        -- mutate exact domain state
        return self:cycle(owner)
    elseif recurring_case_b then
        -- mutate exact domain state
        return self:cycle(owner)
    elseif real_phase_change then
        return self:other_phase(owner)
    elseif completed then
        return self:completed(owner)
    end
    return self:rejected(owner)
end
```

The cycle directly performs `if`/`elseif` dispatch. Do not create `dispatch`, `literal`,
`advance`, `fallback`, or similar methods merely to name each branch arm. That fragmentation
creates callback-like control and makes LuaJIT record a longer mutual-tail cycle.

Create another method only when it names a real boundary:

- a public entry;
- a distinct recurring phase with its own stable cycle;
- completion or rejection;
- a diagnostic path;
- a cold exceptional operation.

The current glob measurements show the reason:

```text
fine sensitive CPS          0.869 ns/byte
coarse sensitive CPS        0.466 ns/byte
numeric-for whole driver    1.039 ns/byte
fine ASCII-fold CPS         2.838 ns/byte
coarse ASCII-fold CPS       0.573 ns/byte
```

Across additional shapes:

```text
shape            structured   coarse CPS   for-driven
literal            0.950 ns     0.924 ns     0.994 ns
question           0.800 ns     0.860 ns     0.950 ns
one star           0.952 ns     0.466 ns     0.996 ns
two stars          0.951 ns     0.453 ns     1.010 ns
late reject        0.950 ns     0.456 ns     0.996 ns
```

CPS is not universally faster than structured Lua. The selected cycle must match the actual
recurrence. For the irregular fallback recurrence, the coarse CPS block is both faster and
cleaner.

## CPS control rules

1. A semantic edge is a direct proper-tail method call.
2. Recurrence returns to the owning leaf cycle.
3. A real phase transition tail-calls the next coarse phase.
4. Immediate completion or failure tail-calls a named terminal method.
5. Do not return action tags, handler names, program counters, or continuation records.
6. Do not use handler maps, visitor tables, or `kind` dispatch.
7. Do not allocate capturing continuation closures per transition.
8. Correctness must be identical with the JIT disabled.

CPS names the semantic graph. Direct conditionals inside a coarse block implement the local
decision tree; they are not a second dispatch architecture.

## Persistent and transient state

A concrete ctype contains only domain-required values that persist across blocks or calls:

- borrowed pointers;
- lengths, positions, and counters;
- exact numeric accumulators;
- capacities and domain-specific buffers;
- backtracking state required by that machine;
- typed stored reports or results.

Values used only inside one coarse cycle invocation remain Lua locals. Values forwarded to
another block remain method parameters unless they must survive later recurrence.

Forbidden generic state includes:

- machine headers;
- generic frames or stacks;
- register files;
- action or program-counter fields;
- context bags;
- untyped semantic side tables.

A domain-specific stack or buffer is valid only when that concrete machine intrinsically
requires it, and its exact layout belongs in `ffi.cdef`. CDEF is the only persistent field
definition language.

## Borrowed memory and ownership

A pointer derived from a Lua string or cdata owner is valid only while that owner remains live.
The entry establishes the pointer, forwards the owner through the complete CPS cycle, and
clears the pointer before returning:

```lua
function Machine:run(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    self.length = #owner
    local result = self:cycle(owner)
    self.input = nil
    return result
end
```

The owner parameter is not generic machine context. It is the specific lifetime capability
for the borrowed memory. Do not store Lua GC references as untracked C pointers. Early public
returns must pass through the sealed entry so no borrowed pointer escapes.

## Families, defaults, and sealing

A closed sum names a family of concrete physical specializations:

```lua
local Scanner = S:sum("Scanner")
local Unsigned = Scanner:leaf("ScannerV1_Unsigned")
local Signed = Scanner:leaf("ScannerV1_Signed")

function Scanner:scan(owner) ... end       -- shared entry
function Scanner:completed(owner) ... end  -- shared terminal
function Unsigned:cycle(owner) ... end     -- unique hot prototype
function Signed:cycle(owner) ... end       -- unique hot prototype

S:seal()
```

At sealing, parent methods are copied into each concrete leaf method table. Leaf methods
replace defaults. Runtime calls use the concrete FFI metatype directly. There is no dynamic
parent lookup, tag switch, handler map, or schema operation in a machine trace.

A physical C union is registered separately with `context:union(ctype_name)`. Concrete sum leaves may
be embedded in that union by value and retain their leaf metatypes. The abstract sum itself has no C
size or alignment and therefore cannot be a field. The authored CDEF owns any enclosing tag and union
fields; the linker does not invent representation or dispatch.

Different leaves may have different layouts. A shared parent method may use only the physical
field protocol actually shared by those layouts. The linker does not invent a common frame.

## Prototype ownership

LuaJIT specializes traces by Lua function prototype and observed types. Reusing one hot parent
function across alternating incompatible ctypes causes trace contention:

```text
shared parent hot prototype   0.899 ns/step
leaf-owned hot prototypes     0.347 ns/step
```

Therefore:

- hot cycles are concrete-leaf methods with distinct function prototypes;
- shared parent methods are entries, terminals, diagnostics, and cold behavior;
- physically incompatible specializations do not alternate through one hot prototype.

Even textually identical hot leaf methods should be separate authored or generated function
definitions when their physical self types are incompatible.

## Nested by-value composition

A parent may physically own a submachine by embedding its ctype by value:

```c
typedef struct {
    uint32_t position;
    uint32_t count;
} Child;

typedef struct {
    Child child;
    uint32_t remaining;
} Parent;
```

The complete machine tree remains one contiguous cdata allocation. Control is composed by
passing the parent and a stable unbound parent continuation as transient arguments:

```lua
local after_child

function Parent:after_child(owner)
    return self:cycle(owner)
end

after_child = Parent.after_child

function Parent:cycle(owner)
    if self.remaining == 0 then return self:completed(owner) end
    self.remaining = self.remaining - 1
    return self.child:cycle(owner, self, after_child)
end

function Child:cycle(owner, parent, completed)
    self.count = self.count + 1
    return completed(parent, owner)
end
```

The continuation is never stored in CDEF state and is never wrapped in a closure or table. The
local alias is important with the minimal linker: it projects the authored method once instead of
running descriptor lookup inside every hot iteration.

A depth experiment compared flat structs with nested-by-value structs. Every level mutated its own
counter and handed control back through the parent continuations. Nine isolated processes used
`-Oloopunroll=1000`:

```text
depth    flat       nested     median overhead
1        0.566 ns   0.637 ns   13%
2        0.643 ns   0.848 ns   32%
4        0.887 ns   1.062 ns   20%
8        1.347 ns   1.598 ns   19%
```

At depth eight, trace IR marked all seven intermediate reference-cdata values as sunk. With GC
stopped, one million transitions grew the heap by about 1.2 KB, so there is no per-transition
allocation. The flat and nested representations have identical sizes at every measured depth.

The default `loopunroll` limit could not close the depth-eight cycle: it fell to roughly 1,300
ns/step and allocated about 187 MB per million transitions. A limit of 20 was sufficient to close
this measured cycle; the benchmark uses 1000 to remove the limit as a variable.

A stable pointer-owned child was not catastrophically slower in this reduced workload: about
0.635 ns/step versus 0.534 for a depth-one by-value child. By-value composition is still the
default because it preserves one owner, one allocation, exact lifetime, compact size, and static
field offsets. Use a pointer only when sharing or dynamic lifetime is intrinsic to the domain.

Alternating two parents through one shared child prototype measured 0.660 ns/step versus 0.618
for composition-specific child prototypes. The parent cycles remained distinct trace roots, so
the shared child was inlined rather than becoming a contended recurring root. Composition-specific
prototypes remain slightly faster and more stable, but nested composition does not recreate the
earlier shared-parent hot-prototype failure.

Nesting is for a genuine owned stateful component or phase. Do not turn branch arms into nested
submachines. Deep chains also lengthen the tail cycle and therefore require an explicit measured
`loopunroll` contract.

## Retained UI moved to Lua exotypes

The retained LÖVE component experiment no longer belongs to this authored-CDEF architecture. It was rewritten as a
Lua-owned exotype application in:

```text
lua/ui/backends/love/component_state.lua
lua/ui/backends/love/component_machine.lua
lua/ui/backends/love/components.lua
```

Stable component descriptions now produce interned owners, recursively composed Lua factories, exact paint
capacities, and bound Lua CPS behavior. It does not generate CDEF and does not reuse this linker. See
`exotyped_cps_machines.md` for the binding architecture and focused validation commands.

## JSON tape workload

The JSON experiment applies the complete pattern to a useful branch-heavy decoder:

```text
borrowed UTF-8 input
  -> coarse parent syntax cycle
       -> nested string machine
       -> nested number machine
       -> domain-specific container-frame array
  -> caller-owned FFI token tape
  -> optional ordinary-Lua table materialization
```

`json_tape.lua` validates JSON strings, escapes, UTF-8, UTF-16 surrogate pairs, numbers,
literals, arrays, objects, separators, depth, and output capacities. The decoder returns an exact
report and clears all borrowed pointers. A Lua result wrapper owns the input and FFI buffers; it
does not place Lua references in CDEF state or access `lua_State` through FFI.

Seven-process medians used 500 KB inputs, `-Oloopunroll=1000`, and locally built lua-cjson
2.1.0.10 as the native-C direct-table comparison:

```text
shape                    direct Lua table   lua-cjson table
large unescaped string       1.414 ns           2.506 ns
short strings                4.518 ns           2.068 ns
numbers                      5.232 ns           3.026 ns
literals                     6.958 ns           3.104 ns
mixed nested objects         7.841 ns           4.883 ns
```

For the mixed-object shape, all available output paths measured:

```text
FFI tape only                3.875 ns/byte
tape then Lua tables         7.371 ns/byte
direct Lua tables            7.841 ns/byte
lua-cjson direct tables      4.883 ns/byte
```

The direct decoder is deliberately small: the same nested string and number machines feed a
concrete Lua builder containing only the current container and object-key stacks. It creates Lua
tables with ordinary Lua operations and never accesses `lua_State` through FFI.

Direct emission removed the tape, but did not improve the mixed-object result. Interleaving table
mutation with parsing measured about 6% slower than the two coherent tape and materialization
passes, and about 61% slower than lua-cjson's native-C table builder. It won the single-large-string
shape, while lua-cjson won dense short values and objects. The FFI tape remains the fastest result
when its physical representation is directly useful. lua-cjson does not provide exactly the same
UTF-8 validation and typed capacity reports.

The literal shape initially fell to roughly 380 ns/byte even with a high unroll limit. A
whitespace `while` at the top of the parent cycle forced the recorder through an inner-loop exit.
Moving whitespace scanning behind a direct branch and returning to the parent cycle restored a
single tail-recursive root and roughly 0.9 ns/byte. This is further evidence that exact authored
trace shape matters more than a general control-style label.

Nested reference cdata are fully sunk when the parent-child handoff belongs to one closed root.
JSON string and number loops can become independent trace roots, so their child pointer must be
materialized at the trace boundary. The string-rich mixed workload grew the stopped-GC heap by
about 3.9 MB per 1 MB parse, approximately one small reference cdata per string or number phase.
This does not affect correctness or tape ownership, but it is the next measured optimization
boundary. Flattening the child state or moving that phase onto the parent would trade physical
composition for fewer trace-boundary allocations and must be compared rather than assumed.

The test suite covers fixed valid and malformed cases, capacity failures, invalid UTF-8, surrogate
handling, depth limits, tape matching, 1,000 generated round trips, normal JIT execution, and
`-joff`.

## Local structured control

Ordinary Lua control inside a coarse method is allowed and expected. `if`/`elseif` is the
direct local decision tree. A numeric `for` may implement a naturally regular bounded subphase
inside the block.

Do not promote `for` into:

- a universal driver;
- a scheduler or fuel protocol;
- a program-counter dispatcher;
- a generic iterator-machine ABI.

Measured numeric-for drivers stayed stable near 1 ns/byte but did not beat the coarse fallback
cycle. Phase-local CSV loops also did not consistently beat tail recurrence. Use a loop only
when it makes the concrete coarse block simpler or measurably better.

## Specialization

A specialization is exactly:

```text
exact cdef state layout
  + exact stable Lua method prototypes
  + exact constants and coarse block graph
  = concrete machine
```

Authored machines in this experiment define their specialization directly. They do not acquire a generic schema,
machine plan, or control IR.


## Minimal linker

The linker provides only nominal family relationships and one-time FFI metatype sealing:

```text
schema.context { name, version, prefix }
context:cdef(source)
context:product(ctype_name)
context:union(ctype_name)
context:sum(name)
sum:leaf(ctype_name)
context:seal()

Type { ... }
Type.method                 stable unbound authored method
Sum:is(value)
```

It does not define fields, execute control, inspect machine state, emit source, plan frames,
or choose implementations. Lua authoring and FFI cdefs already provide those facilities.

## Non-goals

The pattern explicitly excludes:

- ASDL or semantic-tree hot-path lowering;
- generic CFGs, IR nodes, and visitors;
- arenas, references, and semantic side tables;
- opcode or string-action dispatch;
- universal stacks, frames, registers, and machine headers;
- generic query or typed-reference frameworks;
- structured-loop source emitters;
- interpreted fallback execution;
- multiple runtime representations;
- LuaJIT bytecode as a source language;
- integration with Lalin's maintained emitted-C/GCC backend.

This remains an isolated LuaJIT experiment.

## Author checklist

Before sealing a machine, verify:

1. Every persistent field is exact and declared in `ffi.cdef`.
2. The concrete ctype contains no generic machine infrastructure.
3. The public entry initializes state, keeps owners live, and clears borrows.
4. Each hot recurrence is one leaf-owned coarse method.
5. The cycle uses direct conditionals rather than callback-like micro-methods.
6. Separate methods correspond only to real entries, phases, terminals, or diagnostics.
7. Every inter-block semantic edge is a proper tail call.
8. Hot incompatible leaves have distinct Lua function prototypes.
9. Results and durable diagnostics use exact domain types.
10. JIT and `-joff` executions produce identical results.
11. Differential or exhaustive tests cover irregular control paths.
12. Benchmarks run in isolated processes when trace contamination is possible.
13. Nested submachines are by value unless sharing or dynamic lifetime is intrinsic.
14. Deep tail cycles declare and test the `loopunroll` needed to close the full cycle.

## Current validation

```text
cdef schema method linker: ok
cdef CPS CSV scanner: ok
cdef CPS glob matcher: ok
cdef CPS glob exhaustive: ok (289636 pairs)
handwritten CPS tests: ok
nested by-value CPS machines: ok
nested CDEF CPS JSON tape decoder: ok
nested CDEF CPS direct JSON table decoder: ok
composed CDEF concern machine tree: ok
```

The glob, nested-machine, JSON, and concern-tree suites pass with normal JIT execution and with `-joff`. The
prototype-isolation, nested-depth, JSON-shape, concern-synchronization, and isolated glob benchmarks provide the
current performance evidence.

