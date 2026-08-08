# CDEF + CPS Machines on LuaJIT
## Experimental Results and Design Convergence

## Result

The experiments converged on a design pattern rather than a VM framework:

```text
ffi.cdef             exact machine state
sealed Lua methods   blocks
self                 persistent state
method parameters    transient values and owners
return self:next()   CPS edges
sum defaults         shared blocks
leaf overrides       machine specializations
```

The user writes the executable machine directly. LuaJIT traces its stable recurring method
cycles. A small linker provides products, closed machine families, default blocks, leaf
overrides, and sealing.

All generic hot-path machinery was retired.

## Experimental evolution

The investigation tested, then rejected, progressively heavier designs:

1. lexical CPS blocks;
2. object-method CPS;
3. table and FFI state;
4. generated-source loading and bytecode caching;
5. a generic ASDL VM with expressions, statements, frames, outcomes, and a PEG frontend;
6. a cdef semantic tree with arena references and structured-loop specialization.

Steps 5 and 6 obscured the desired authoring model. The final architecture has no semantic
tree or generated structured execution. A concrete cdef object with authored CPS methods is
already the specialized machine.

## Environment

```text
LuaJIT 2.1.1767980792, x64/Linux
AMD Ryzen 7 PRO 8840HS
```

Measurements are bounded local microbenchmarks, not cross-machine guarantees.

## Tail-call tracing

Stable mutually tail-calling Lua functions form LuaJIT loop traces. For 20 million counted
iterations:

```text
direct Lua for loop               14.1 ms
CPS block arguments               14.1 ms
handler-table interpreter        807.3 ms
```

The handler interpreter was approximately 57 times slower. LuaJIT hoisted stable block
identity and topology assumptions from the CPS loop body.

## Natural method syntax

A byte matcher compared equivalent shapes:

```text
structured Lua              0.536 ns/byte
lexical block edges         0.468 ns/byte
colon method edges          0.467 ns/byte
static method edges         0.487 ns/byte
table self state            0.487 ns/byte
FFI metatype self           0.490 ns/byte
```

Colon-method edges matched lexical CPS. The natural source form therefore has no measured
steady-state penalty:

```lua
function Machine:pair(owner)
    ...
    return self:loop(owner)
end
```

## Physical typing

Tables and FFI structs were similar when state consisted only of ordinary doubles. FFI
became valuable for exact integer semantics, arrays, and pointer memory.

Distinct typed counters measured approximately:

```text
i64 specialization          0.23 ns/iteration
f64 specialization          0.96 ns/iteration
```

The function prototypes must remain distinct. Reusing one prototype across incompatible
runtime types causes trace contention.

## Typed pointer input

Replacing `string.byte` with a borrowed `const uint8_t *` improved the matcher:

```text
structured string           0.541 ns/byte
method string.byte          0.481 ns/byte
FFI pointer self            0.298 ns/byte
```

The owner string remained a CPS parameter, and the sealed public method cleared the pointer
before returning.

## Full typed scanner

A hand-written number scanner exercised:

- borrowed pointer input;
- exact uint64 accumulation;
- signed int64 limits;
- a fixed `int64_t[65536]` output;
- syntax, capacity, and overflow outcomes;
- CPS blocks for every immediate alternative.

It measured:

```text
handwritten FFI scanner     3.872 ns/byte
```

This established that cdef can describe the complete physical machine while Lua methods
describe behavior.

## Method linker

The final linker binds authored cdefs to methods:

```lua
local Scanner = S:sum("Scanner")
local Unsigned = Scanner:leaf("ScannerV1_Unsigned")
local Signed = Scanner:leaf("ScannerV1_Signed")

function Scanner:scan(owner)
    -- shared cold entry
    return self:cycle(owner)
end

function Unsigned:cycle(owner)
    -- unsigned leaf-owned coarse recurrence
end

function Signed:cycle(owner)
    -- signed leaf-owned coarse recurrence
end

S:seal()
```

Sealing copies parent defaults into each leaf and installs one FFI metatype. Runtime calls
do not walk parents or classify leaves.

Measured method cost:

```text
direct cdata field          ~0.23 ns/iteration
inherited default           ~0.23 ns/iteration
leaf override               ~0.23 ns/iteration
```

## Hot prototype isolation

Parent default methods are copied by reference into concrete leaf tables. This has negligible
cost while one compatible ctype is hot, but alternating incompatible self ctypes through the
same recurrence prototype caused trace contention:

```text
shared parent hot prototype       0.899 ns/step
leaf-owned hot prototypes         0.347 ns/step
```

The frozen canonical shape therefore gives every dominant hot recurrence a concrete
leaf-owned method prototype. Parent defaults own shared boundaries, terminals, diagnostics,
and cold blocks.

## Useful machine-family result

`experiments/cdef_schema/cps_csv_scanner.lua` implements signed and unsigned CSV scanners as
two concrete machine ctypes. Shared blocks live on the parent machine family; signed parsing
overrides only the blocks whose physical behavior differs.

For 32,768 values:

```text
signed CPS machine          3.914 ns/byte
unsigned CPS machine        2.981 ns/byte
```

Trace output contains scanner methods only. The linker is absent from execution.

## Branchy backtracking and block granularity

A useful glob machine added two borrowed pointers, persistent `*` backtracking positions,
wildcards, rejection paths, and case-sensitive/ASCII-fold leaf specializations.

Fine CPS exposed `dispatch`, `literal`, `advance`, `star`, and `fallback` as separate methods.
Coarse CPS kept one recurring semantic step in a leaf-specific `loop` method. Results over
one million bytes were:

```text
structured pointer          0.949 ns/byte
fine sensitive CPS          0.869 ns/byte
coarse sensitive CPS        0.466 ns/byte
numeric-for sensitive       1.039 ns/byte
structured ASCII fold       1.070 ns/byte
fine ASCII-fold CPS         2.838 ns/byte
coarse ASCII-fold CPS       0.573 ns/byte
```

The coarse CPS machine was faster, substantially more trace-stable, and simpler on the
backtracking workload. One leaf-owned block performs the direct conditional dispatch rather
than fragmenting the recurrence across callback-like method edges. Additional shapes clarified
the result:

```text
shape            structured   coarse CPS   for-driven
literal            0.950 ns     0.924 ns     0.994 ns
question           0.800 ns     0.860 ns     0.950 ns
one star           0.952 ns     0.466 ns     0.996 ns
two stars          0.951 ns     0.453 ns     1.010 ns
late reject        0.950 ns     0.456 ns     0.996 ns
```

The lesson is not that CPS always wins or that block count should be maximized. Structured
control wins straight literal traversal. Coarse CPS wins when fallback is the recurring hot
path. A numeric `for` loop provides a stable implicit continuation near 1 ns per byte, but
does not capture the fallback specialization. Methods should name meaningful control
boundaries while tightly coupled work remains in one block.

A second experiment used numeric `for` inside CSV whitespace and digit phases. It remained
correct and competitive but did not consistently beat tail recurrence. Numeric `for` is
therefore a strong local phase driver, not a universal scheduler.

## Rejected generic-for pull experiment

Callable cdata was tested as a generic-for iterator. A byte iterator measured about 0.87
ns/byte versus 0.64 for direct numeric `for`; a CSV iterator with a nested digit loop
measured about 10.7 ns/byte. The interface was convenient but did not improve machine
execution. It was removed from the linker and frozen architecture.

An exhaustive oracle comparison validated 289,636 small pattern/text pairs across fine,
coarse, sensitive, and ASCII-fold machines.

## Nested by-value composition

A parent can embed a submachine struct by value and hand it a stable unbound parent continuation.
Measured depths 1, 2, 4, and 8 stayed within 13–32% of equally sized flat structs when
`loopunroll=1000`. Depth-eight IR sank all intermediate reference cdata values. The default
unroll limit failed to close that deep cycle, making unroll capacity an explicit shape contract.

## JSON tape decoder

A parent decoder with by-value string and number submachines can write an FFI tape or ordinary Lua
tables without accessing `lua_State` through FFI. Mixed objects measured 3.875 ns/byte to tape,
7.371 for tape plus tables, 7.841 for direct Lua emission, and 4.883 for locally built lua-cjson.
The KISS direct path is simpler but does not beat the separated phases or lua-cjson. Tests cover
grammar, UTF-8, escapes, capacities, depth, and 1,000 generated values under JIT and `-joff`.

## Generated source

`loadstring` remains useful only when an external program truly requires a new machine
specialization. Source compilation for small generated shapes measured roughly 4–77
microseconds; cached `string.dump` loading measured roughly 0.2–5 microseconds.

Generation must produce the same public authoring shape: unique cdef state plus stable CPS
methods on `self`. It must not introduce a generic IR or alternate runtime representation.

## LuaJIT cycle limits

The default `loopunroll` value can prevent long linear mutual-tail cycles from closing.
Increasing it enough to record the complete cycle restored flat performance for measured
cycles from 4 to 190 blocks. Partial increases that do not close the cycle can make
recording worse.

Branch-heavy machines are also limited by trace size and side-trace behavior. JIT settings
belong to measured machine-shape requirements, not universal defaults.

## Removed architecture

The following are intentionally absent:

- generic ASDL hot-path lowering;
- expression and statement IRs;
- universal CFGs and frame planners;
- handler tables and opcode dispatch;
- semantic arenas and reference graphs;
- structured-loop source specialization;
- interpreted fallback execution;
- multiple runtime targets.

These mechanisms were useful experiments but are not part of the resulting pattern.

## Final architecture

```text
author writes cdef state
  + author writes CPS methods on self
  + linker seals defaults and overrides
  = concrete executable machine
```

A generated specialization, when necessary, generates exactly that same shape.

## Validation

```text
cdef schema method linker: ok
cdef CPS CSV scanner: ok
handwritten CPS tests: ok
```

## Conclusion

The result is simpler than the original proposal:

> **CDEF defines physical state. Stable CPS methods on `self` are the machine.**

There is no framework hidden behind that statement.
