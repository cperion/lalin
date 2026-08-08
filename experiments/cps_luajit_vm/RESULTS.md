# CPS-on-LuaJIT results

Environment:

```text
LuaJIT 2.1.1767980792, x64/Linux
AMD Ryzen 7 PRO 8840HS
```

These are bounded local microbenchmarks.

## Tail-call result

Stable mutual tail calls form LuaJIT loop traces:

```text
direct Lua, 20M iterations        14.1 ms
CPS block arguments               14.1 ms
handler-table interpreter        807.3 ms
```

Long linear cycles require enough `loopunroll` to close the recurring cycle. Branch-heavy
graphs remain constrained by trace size and side traces.

## Method authoring

```text
structured Lua              0.536 ns/byte
lexical block edges         0.468 ns/byte
colon method edges          0.467 ns/byte
static method edges         0.487 ns/byte
table self state            0.487 ns/byte
FFI metatype self           0.490 ns/byte
```

Colon methods matched lexical CPS. The selected authoring form is therefore methods as
blocks and proper tail method calls as edges.

## Typed physical state

Exact pointer input improved the matcher:

```text
structured string           0.541 ns/byte
method string.byte          0.481 ns/byte
FFI pointer self            0.298 ns/byte
```

The complete hand-written typed number scanner measured:

```text
handwritten FFI scanner     3.872 ns/byte
```

It covered borrowed ownership, exact int64 limits, fixed output, syntax errors, overflow,
capacity, and CPS alternatives.

## Method linker

The CDEF linker adds parent defaults, leaf overrides, closed machine families, and sealing
without entering execution:

```text
direct cdata method         ~0.23 ns/iteration
inherited default           ~0.23 ns/iteration
leaf override               ~0.23 ns/iteration
```

Alternating incompatible leaf ctypes through one inherited hot recurrence exposed prototype
contention:

```text
shared parent hot prototype       0.899 ns/step
leaf-owned hot prototypes         0.347 ns/step
```

Hot cycles should be leaf-owned. Parent defaults remain appropriate for entries, terminals,
diagnostics, and cold shared behavior.

The useful signed/unsigned CSV machine family measured:

```text
signed CPS machine          3.914 ns/byte
unsigned CPS machine        2.981 ns/byte
```

## Branchy backtracking

The glob machine tested fine and coarse CPS granularity:

```text
structured pointer          0.949 ns/byte
fine sensitive CPS          0.869 ns/byte
coarse sensitive CPS        0.466 ns/byte
numeric-for sensitive       1.039 ns/byte
structured ASCII fold       1.070 ns/byte
fine ASCII-fold CPS         2.838 ns/byte
coarse ASCII-fold CPS       0.573 ns/byte
```

Coarse leaf-specific recurrence was faster, more stable, and cleaner than splitting each
primitive operation into callback-like method edges. Shape measurements were:

```text
shape            structured   coarse CPS   for-driven
literal            0.950 ns     0.924 ns     0.994 ns
question           0.800 ns     0.860 ns     0.950 ns
one star           0.952 ns     0.466 ns     0.996 ns
two stars          0.951 ns     0.453 ns     1.010 ns
late reject        0.950 ns     0.456 ns     0.996 ns
```

CPS won the fallback-heavy paths but not straight literal traversal. The numeric-for driver
was stable near 1 ns per byte but gave up the fallback-specific gain. Phase-local numeric
loops in the CSV scanner did not consistently beat tail recurrence. Use `for` as a bounded
local phase driver, not a universal scheduler. Exhaustive differential testing covered
289,636 pattern/text pairs.

Generic-for callable cdata was also tested and rejected as a core shape. It measured 0.872
ns/byte for a byte iterator versus 0.640 for direct numeric `for`; a nested-loop CSV iterator
measured about 10.7 ns/byte. CPS remains the machine control representation.

## Nested by-value composition

Parent structs can embed child machines by value and pass stable parent continuations as transient
arguments. With `loopunroll=1000`, depths 1, 2, 4, and 8 measured 0.637, 0.848, 1.062, and
1.598 ns/step, within 13–32% of equally sized flat structs. Depth-eight trace IR sank all seven
intermediate reference cdata values. The default unroll limit did not close the depth-eight cycle.

## JSON tape decoder

A nested CDEF CPS decoder writes either a preallocated FFI token tape or ordinary Lua tables
directly. On mixed objects, tape measured 3.875 ns/byte, tape plus materialization 7.371, direct
Lua tables 7.841, and locally built lua-cjson 4.883. The one-pass direct variant was about 6%
slower than the two coherent tape/materialization phases and about 61% slower than lua-cjson.
Across large-string, short-string, number, literal, and object shapes, direct emission measured
1.414, 4.518, 5.232, 6.958, and 7.841 ns/byte versus lua-cjson's 2.506, 2.068, 3.026, 3.104,
and 4.883 ns/byte.
The grammar, UTF-8, capacity, depth, and 1,000 generated-roundtrip tests pass with JIT and `-joff`.

## Loading

Small generated source shapes compiled in approximately 4–77 microseconds. Cached
`string.dump` images loaded in approximately 0.2–5 microseconds. Generation is reserved for
real external specializations and must produce cdef state plus CPS methods on `self`.

## Final decision

The architecture is:

```text
state          = exact ffi.cdef machine
behavior       = authored Lua methods
control edges  = return self:next(...)
shared blocks  = sealed sum defaults
specialization = concrete leaf ctype and stable method graph
generation     = optional production of the same shape
```

Removed experiments include the generic ASDL VM, universal CFG, expression IR, frame
planner, semantic arena, typed query tree, and structured-loop emitter. None belongs to the
runtime or authoring API.

