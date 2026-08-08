# Proposal: CDEF + CPS Machines on LuaJIT

## Summary

Define executable machines directly with two native LuaJIT mechanisms:

```text
ffi.cdef                    exact persistent state
named public method         machine entry and ownership boundary
leaf-owned coarse method    hot conditional dispatch and recurrence
self                        concrete machine identity
method parameters           transient values and borrowed owners
return self:next()          proper-tail CPS control edge
```

A tiny method linker restores the useful class experience: products, closed machine
families, parent defaults, leaf overrides, and one-time sealing. It does not define a
second field language or runtime.

The machine author writes the executable blocks. There is no bytecode interpreter, semantic
tree, arena, generic IR, visitor, handler map, or structured-loop emitter. The complete frozen
authoring pattern is documented in `experiments/cdef_schema/ARCHITECTURE.md`.

## Authoring shape

```lua
local ffi = require("ffi")
local schema = require("cdefschema")
local S = schema.context {
    name = "matcher",
    version = 1,
    prefix = "MatcherV1_",
}

S:cdef [[
typedef struct {
    const uint8_t *input;
    uint32_t length;
    uint32_t position;
} MatcherV1_Machine;
 ]]

local Machine = S:product("MatcherV1_Machine")

function Machine:run(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    self.length = #owner
    self.position = 0
    local result = self:cycle(owner)
    self.input = nil
    return result
end

function Machine:cycle(owner)
    if self.position < self.length then
        -- Direct local if/elseif dispatch stays in this coarse cycle.
        self.position = self.position + 1
        return self:cycle(owner)
    end
    return self:completed(owner)
end

S:seal()

local machine = Machine()
```

This source is simultaneously the machine definition, control-flow graph, executable Lua,
and LuaJIT input.

## Physical and behavioral typing

CDEF owns the physical world:

- exact integers and casts;
- pointers and borrowed views;
- fixed arrays and typed stacks;
- structs and ABI results;
- compact mutable state;
- C interoperability.

Lua methods own behavior:

- blocks;
- branches;
- loop cycles;
- immediate alternatives;
- completion and rejection;
- public ownership boundaries.

CDEF does not type method signatures. Stable authored methods and LuaJIT trace guards
specialize transient method parameters dynamically. Persistent values requiring exact
semantics belong in `self`.

## Closed machine families

A sum is a family of concrete physical specializations:

```lua
local Scanner = S:sum("Scanner")
local Unsigned = Scanner:leaf("ScannerV1_Unsigned")
local Signed = Scanner:leaf("ScannerV1_Signed")

function Scanner:scan(owner)
    -- shared cold entry and ownership boundary
    return self:cycle(owner)
end

function Scanner:completed(owner)
    -- shared terminal behavior
end

function Unsigned:cycle(owner)
    -- unsigned leaf-owned coarse hot recurrence
end

function Signed:cycle(owner)
    -- signed leaf-owned coarse hot recurrence
end

S:seal()
```

At sealing, parent methods are copied into each concrete leaf method table. Leaf methods
override defaults. Every leaf receives one FFI metatype. Runtime lookup is direct and has
no parent walk or variant dispatch.

Different leaves can have different cdef layouts. Shared defaults may use only the field
protocol genuinely shared by those layouts.

## Specialization

A concrete ctype plus its stable method graph is a specialization:

```text
exact state layout
  + exact constants
  + exact CPS blocks
  = specialized machine
```

Hand-written machines state this directly. If an external pattern or guest program truly
requires generation, it generates the same form: a uniquely named cdef machine plus readable
CPS methods on `self`. `loadstring` loads that module. Incompatible specializations receive
distinct function prototypes so their traces cannot compete.

Generated source is optional. It is not a different execution architecture. `string.dump`
is only a cache image of generated source.

## Runtime ownership

A sealed public method establishes and releases borrowed resources:

```lua
function Machine:run(owner)
    self.input = ffi.cast("const uint8_t *", owner)
    self.length = #owner
    self.position = 0
    local result = self:loop(owner)
    self.input = nil
    return result
end
```

The Lua owner remains a live method parameter throughout the CPS cycle. Borrowed pointers
are cleared before the public call returns. Lua GC objects are never stored as untracked C
pointers.

## Why CPS

A conventional interpreter repeatedly decodes a program counter or opcode. The authored
CPS machine exposes its topology directly:

```text
method identity       block identity
tail method call      edge
method argument       transient edge value
self field            durable machine value
```

LuaJIT can trace recurring method cycles. Stable method lookup and topology guards are
normally hoisted from the loop body, leaving the machine computation in the hot trace.

## Measured results

On LuaJIT 2.1.1767980792, x64/Linux, AMD Ryzen 7 PRO 8840HS:

```text
20 million counted iterations
direct Lua                         14.1 ms
CPS block arguments               14.1 ms
handler-table interpreter        807.3 ms

one-million-byte matcher
structured Lua                   0.536 ns/byte
lexical CPS                      0.468 ns/byte
colon-method CPS                 0.467 ns/byte
FFI metatype self                0.490 ns/byte

typed input matcher
string.byte method               0.481 ns/byte
const uint8_t* FFI self          0.298 ns/byte

CDEF + CPS CSV machine
signed scanner                   3.914 ns/byte
unsigned scanner                 2.981 ns/byte

backtracking-heavy glob
structured pointer               0.949 ns/byte
fine sensitive CPS               0.869 ns/byte
coarse sensitive CPS             0.466 ns/byte
numeric-for sensitive            1.039 ns/byte
structured ASCII fold            1.070 ns/byte
fine ASCII-fold CPS              2.838 ns/byte
coarse ASCII-fold CPS            0.573 ns/byte
```


The method linker benchmark measured inherited defaults and leaf overrides at approximately
0.23 ns per call cycle, equal to direct metatype methods within measurement noise.

## LuaJIT constraints

### Stable identity

Block methods and method tables must remain stable. Replacing methods in a hot machine
invalidates assumptions and damages trace quality. The linker therefore rejects method
declarations after sealing.

### Cycle recording

Long linear mutual-tail cycles can require a larger `loopunroll` setting before LuaJIT can
close the root trace. Raising it only enough to close the complete recurring cycle is useful;
partial unrolling can be worse than the default. Branch-heavy graphs remain constrained by
trace size and side traces.

### Numeric `for` drivers

LuaJIT's numeric `for` loop is a powerful implicit continuation and trace anchor. It can
drive a regular bounded phase or a fixed batch of machine transitions inside a leaf-owned
method. A 256-transition glob driver stayed near 1 ns per byte across literal, wildcard,
fallback, and rejection shapes.

It was not universally fastest: the coarse fallback CPS cycle reached roughly 0.46 ns per
byte, and phase-local CSV `for` loops did not consistently beat tail recurrence. Numeric
`for` is a local phase tool, not a universal scheduler or replacement for semantic CPS
edges.

### Rejected generic-for pull driver

Callable cdata was tested as a generic-for iterator. A one-transition byte iterator measured
about 0.87 ns per byte versus 0.64 ns for direct numeric `for`, while a CSV iterator with an
inner digit loop measured about 10.7 ns per byte. It did not improve the machine shape and
is not part of the frozen architecture. CPS remains the semantic control representation.

### Prototype isolation

Different runtime type specializations need distinct Lua function prototypes. Reusing one
generic prototype for incompatible i64, f64, pointer, or layout shapes creates trace
contention. Alternating two exact leaf ctypes measured:

```text
shared parent hot prototype       0.899 ns/step
leaf-owned hot prototypes         0.347 ns/step
```

Parent defaults should own shared boundaries and cold behavior. Dominant hot recurrence
methods should be concrete leaf overrides.

### Nested by-value composition

A parent can embed a concrete submachine ctype by value and hand the child a stable unbound
parent continuation. The machine tree remains one cdata allocation; no parent pointer, stored
closure, or continuation frame is required. At measured depths 1, 2, 4, and 8, nested cycles
remained within 13–32% of equally sized flat cycles when `loopunroll` was high enough to record
the complete handoff chain. Depth-eight IR sank all intermediate reference cdata.

The default unroll limit failed at depth eight, so deep composition carries an explicit measured
trace-cycle contract. Nested components must represent genuine owned stateful phases, not branch
arms.

### JSON tape decoder

A developer-authored JSON workload embeds string and number machines by value inside one decoder,
uses a domain-specific container-frame array, and writes a caller-owned FFI tape. It validates
the full JSON grammar, UTF-8, escapes, surrogate pairs, capacities, and depth. A second KISS
decoder writes Lua tables directly with ordinary Lua operations and no `lua_State` FFI access.
Mixed objects measured 3.875 ns/byte to tape, 7.371 through tape plus materialization, 7.841
through direct Lua emission, and 4.883 through locally built lua-cjson. Direct emission was simpler
than the tape path but did not beat either the two-pass trace shape or lua-cjson's native table
builder.

The workload also exposes a real composition boundary: child references sink when the entire
handoff is one root, but string and number loops can become independent trace roots and materialize
one small reference cdata per phase. This remains a measured tradeoff between physical nesting and
flattening, not a reason for generic runtime machinery.

### Correctness

Machine correctness cannot depend on tracing. The same CPS methods must execute correctly
in the LuaJIT interpreter and with JIT compilation disabled.

## Minimal linker

```text
schema.context { name, version, prefix }
context:cdef(source)
context:product(ctype_name)
context:sum(name)
sum:leaf(ctype_name)
context:seal()

Type { ... }
Sum:is(value)
```

The linker owns nominal relationships and metatype installation only. CDEF remains the sole
field vocabulary.

## Non-goals

This proposal does not include:

- an ASDL compatibility layer;
- a generic CPS IR;
- an opcode interpreter;
- a semantic node graph;
- arenas or reference handles;
- visitors, handlers, or rule tables;
- a universal VM context;
- a structured source emitter;
- multiple runtime representations;
- a replacement for Lalin's maintained emitted-C/GCC backend.

## Reference implementation

The bounded implementation is under `experiments/cdef_schema/`:

- `lua/cdefschema.lua` — canonical declaration and metatype linker;
- `cps_csv_scanner.lua` — useful signed/unsigned CPS machine family;
- `cps_csv_test.lua` — exact integer, error, capacity, and ownership tests;
- `cps_csv_bench.lua` — scanner benchmark;
- `cps_csv_shapes.lua` — phase-local numeric-for comparison;
- `prototype_isolation_bench.lua` — shared versus leaf-owned hot prototypes;
- `cps_glob.lua` — branchy backtracking machine and block-granularity comparison;
- `cps_glob_exhaustive.lua` — 289,636-pair differential test;
- `cps_glob_bench.lua` — fine/coarse CPS benchmark;
- `cps_glob_shapes.lua` — literal, wildcard, fallback, and rejection shapes;
- `nested_machine.lua` — flat, by-value nested, pointer, and continuation-prototype shapes;
- `nested_machine_test.lua` — JIT-independent composition correctness;
- `nested_machine_bench.lua` — isolated depth and allocation benchmark;
- `nested_continuation_bench.lua` — shared versus composition-specific child prototypes;
- `json_tape.lua` — nested CDEF CPS JSON decoder, tape, and Lua materializer;
- `json_direct.lua` — KISS one-pass ordinary-Lua table decoder;
- `json_tape_test.lua` — grammar, UTF-8, capacity, depth, and generated-roundtrip tests;
- `json_direct_test.lua` — direct/tape differential and interpreter-mode tests;
- `json_tape_bench.lua` — isolated tape, direct-table, two-pass, and lua-cjson benchmark;
- `ARCHITECTURE.md` — binding experiment design.

Foundational trace and loading probes remain under `experiments/cps_luajit_vm/`.

## Thesis

The architecture is not a VM framework. It is an authoring discipline:

> **CDEF defines the machine's physical world. CPS methods on `self` define its behavior.**
