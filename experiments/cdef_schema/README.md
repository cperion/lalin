# CDEF + coarse CPS machine experiment

The consolidated vision is [`../../composed_state_machines_whitepaper.md`](../../composed_state_machines_whitepaper.md).
The canonical authored pattern is documented in [`ARCHITECTURE.md`](ARCHITECTURE.md). The reusable
declaration and metatype linker is [`../../lua/cdefschema.lua`](../../lua/cdefschema.lua):

```text
exact ffi.cdef state
  -> named public machine entry
  -> leaf-owned coarse CPS cycle
       -> direct if/elseif dispatch
       -> proper-tail recurrence or phase transition
       -> named terminal outcome
```

The user authors the executable machine directly. Lua methods are blocks, `self` is the
concrete machine, and parent defaults provide shared cold behavior. There is no arena, semantic
tree, interpreter, generic IR, handler map, or structured-loop emitter.

## Composed concern-machine tree

`concern_tree.lua` applies the complete composition pattern to one 104-byte root cdata:

```text
App
├── Input
├── Model
├── Layout
└── Paint
```

The root owns all children by value. Input selects a model transition; the model selects changed or
unchanged parent exits; changed state flows through layout and paint; resize synchronizes layout and
paint directly. The durable two-command paint projection is the only encoded output. There are no
command values, callback registries, generic nodes, or scheduler.

```sh
luajit -Oloopunroll=1000 experiments/cdef_schema/concern_tree_test.lua
luajit -joff experiments/cdef_schema/concern_tree_test.lua
```

Nine isolated-process medians over ten million transitions:

```text
model → layout → paint     1.483 ns/transition
layout → paint             1.487 ns/transition
unchanged named exit       0.643 ns/transition
```

With GC stopped after warmup, 200,000 through ten million transitions all added the same 20.46 KB,
showing no per-transition allocation.

## Trace-capacity probe

`loopunroll_probe.lua` demonstrates that `loopunroll` can be raised to `2147483647`, but cannot be
literally uncapped. With trace storage capacities raised near LuaJIT's hard 16-bit representations,
this synthetic CPS chain closes through depth 496 and fails at depth 512 from snapshot/trace limits.
See [`LOOPUNROLL.md`](LOOPUNROLL.md).

## Call conventions

`call_conventions.lua` separates direct tail transfer, synchronous Lua host frames, and durable
explicit CDEF frames. Bytecode inspection confirms `CALLT` for CPS entry/resume edges and `CALL` for
host-framed invocation. The host stack avoids the `loopunroll` threshold for bounded synchronous
nesting, while explicit frames support suspension and re-entry. See
[`CALL_CONVENTIONS.md`](CALL_CONVENTIONS.md).

## Useful machine

`cps_csv_scanner.lua` defines signed and unsigned CSV integer scanners. Both are concrete
FFI ctypes in one closed machine family. Parent methods provide shared entries, terminals, and
cold phase boundaries; concrete leaves own their specialized recurrence methods.

```lua
local Csv = require("experiments.cdef_schema.cps_csv_scanner")

local scanner = Csv.Signed()
local report = scanner:scan("-12, 0, 34")
assert(report:is_ok())
```

The machine uses borrowed pointer input, exact integer state, a fixed typed output array,
and typed syntax/capacity/overflow results.

Measured over 32,768 values:

```text
signed CPS machine          3.914 ns/byte
unsigned CPS machine        2.981 ns/byte
```

LuaJIT traces only the authored CPS methods. The schema linker is absent from execution.

## Hot prototype isolation

Parent defaults are excellent for shared boundaries and cold blocks. A hot recurrence must
be leaf-owned when incompatible ctype specializations alternate:

```text
shared parent hot prototype       0.899 ns/step
leaf-owned hot prototypes         0.347 ns/step
```

The leaf-owned forms use identical source logic but distinct Lua function prototypes.

## Branchy backtracking machine

`cps_glob.lua` implements byte glob matching with `*`, `?`, backtracking state, two
borrowed pointers, and case-sensitive/ASCII-fold machine leaves. It compares fine block
factoring with one coarse recurring CPS block:

```text
structured pointer          0.949 ns/byte
fine sensitive CPS          0.869 ns/byte
coarse sensitive CPS        0.466 ns/byte
numeric-for sensitive       1.039 ns/byte
structured ASCII fold       1.070 ns/byte
fine ASCII-fold CPS         2.838 ns/byte
coarse ASCII-fold CPS       0.573 ns/byte
```

The coarse leaf-specific cycle is faster and more trace-stable on the backtracking-heavy
shape. It also avoids callback-like fragmentation: one leaf-owned block performs the direct
conditional dispatch and tail-calls only named terminal or phase boundaries.

Additional shapes show that this is workload-dependent:

```text
shape            structured   coarse CPS   for-driven
literal            0.950 ns     0.924 ns     0.994 ns
question           0.800 ns     0.860 ns     0.950 ns
one star           0.952 ns     0.466 ns     0.996 ns
two stars          0.951 ns     0.453 ns     1.010 ns
late reject        0.950 ns     0.456 ns     0.996 ns
```

Structured control wins a straight literal walk. Coarse CPS wins when the recurring path
is star backtracking. The numeric-for driver remains close to 1 ns per byte across shapes:
it is a stable local driver, but it does not preserve the specialized fallback advantage.
Trace shape, not CPS or `for` by itself, determines the result.

An exhaustive differential test checks 289,636 small pattern/text pairs against a recursive
oracle.


## Nested machine composition

`nested_machine.lua` validates by-value physical composition and handed parent continuations.
With `-Oloopunroll=1000`, nested structs remained within 13–32% of equally sized flat structs
through depths 1, 2, 4, and 8. Depth-eight trace IR sank every intermediate reference cdata; one
million transitions grew the stopped-GC heap by only about 1.2 KB.

The default unroll limit did not close the depth-eight cycle. This is a trace-cycle contract, not
a storage allocation problem. Nested submachines are reserved for genuine owned stateful
components, not branch-level decomposition.

## JSON decoders

`json_tape.lua` is a developer-authored JSON decoder with nested string and number machines, a
domain-specific frame array, a preallocated FFI tape, decoded-string storage, typed reports, and
optional Lua-table materialization. It validates escapes, UTF-8, surrogate pairs, numbers,
containers, capacities, and depth without accessing `lua_State` through FFI.

Seven-process mixed-object medians against locally built lua-cjson 2.1.0.10:

```text
FFI tape only             3.875 ns/byte
tape then Lua tables      7.371 ns/byte
direct Lua tables         7.841 ns/byte
lua-cjson direct tables   4.883 ns/byte
```

`json_direct.lua` is the KISS one-pass table variant. It uses ordinary Lua table operations and a
narrow container/key builder passed through the same CPS graph. It avoids the tape but is about 6%
slower than the two-pass path on mixed objects; separating parsing and materialization gives each
phase a cleaner trace. lua-cjson remains about 1.6x faster for mixed table output. The direct
decoder wins the single-large-string shape.
The JSON tests pass in JIT and `-joff` modes and include 1,000 generated round trips.

## Retained LÖVE components

The retained component experiment has moved out of the authored-CDEF architecture. It now uses runtime-created Lua
exotypes, composed Lua instance factories, exact topology-derived paint capacities, and bound Lua CPS behavior. No
component CDEF or `cdefschema` linker survives in that path. See `exotyped_cps_machines.md` and:

```text
lua/ui/backends/love/component_state.lua
lua/ui/backends/love/component_machine.lua
lua/ui/backends/love/components.lua
```

Focused validation:

```sh
luajit tests/ui/test_ui_love_component_state.lua
luajit -joff tests/ui/test_ui_love_component_state.lua
luajit tests/ui/test_ui_love_component_machine.lua
luajit -joff tests/ui/test_ui_love_component_machine.lua
LOVE_CPS_SMOKE=1 LOVE_CPS_RESIZE_SMOKE=1 love demo/love_components
```

Run:

```sh
luajit tests/test_cdefschema.lua
luajit experiments/cdef_schema/cps_csv_test.lua
luajit experiments/cdef_schema/bench.lua
luajit experiments/cdef_schema/cps_csv_bench.lua
luajit experiments/cdef_schema/cps_csv_shapes.lua 20000 7 1
luajit experiments/cdef_schema/cps_glob_test.lua
luajit experiments/cdef_schema/cps_glob_exhaustive.lua
luajit experiments/cdef_schema/cps_glob_bench.lua
luajit experiments/cdef_schema/cps_glob_shapes.lua
luajit experiments/cdef_schema/prototype_isolation_bench.lua
luajit experiments/cdef_schema/nested_machine_test.lua
luajit -Oloopunroll=1000 experiments/cdef_schema/nested_machine_bench.lua nested8
luajit -Oloopunroll=1000 experiments/cdef_schema/nested_continuation_bench.lua shared
luajit -Oloopunroll=1000 experiments/cdef_schema/json_tape_test.lua
luajit -Oloopunroll=1000 experiments/cdef_schema/json_direct_test.lua
luajit -Oloopunroll=1000 experiments/cdef_schema/json_tape_bench.lua 1000000 7 tape object
luajit -Oloopunroll=1000 experiments/cdef_schema/json_tape_bench.lua 1000000 7 direct object
# Optional lua-cjson comparison after a local Lua 5.1 rock install:
# luajit -Oloopunroll=1000 experiments/cdef_schema/json_tape_bench.lua 1000000 7 cjson object
```

The experiment remains an isolated candidate architecture rather than a maintained Lalin compiler backend.
The LÖVE component machine is its maintained reference consumer for authored application composition.

