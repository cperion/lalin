# Concrete libgccjit driver machines

This isolated experiment tests whether one exact CDEF machine can drive libgccjit's opaque construction
protocol and produce another exact runtime machine. It is not a replacement for Lalin's canonical
`CBackendUnit -> emit_c -> GCC` path.

## Shape

```text
GccJitDriverV1_Driver
├── ForeignOwner
│   ├── gcc_jit_context *
│   ├── gcc_jit_result *
│   └── executable entry pointer
├── TypeProjection
├── FunctionProjection
├── Diagnostic
├── Metrics
├── AcquireMachine
├── TypeMachine
├── BlockGraphMachine
├── TailGraphMachine
└── CompileMachine
```

The foreign context owns GCC objects. The CDEF root owns exact typed pointers to those objects for the
context lifetime. After compilation, the context is released; the result owner retains executable code
until explicit `Driver:free()`.

## Control graph

```text
Driver:cook_blocks | Driver:cook_tail
  → AcquireMachine:run
  → TypeMachine:run
  → BlockGraphMachine:run | TailGraphMachine:run
  → CompileMachine:blocks | CompileMachine:tail
  → Driver:completed | Driver:reject
```

Stable unbound machine methods are the construction continuations. There is no generic JIT node, wrapper
object graph, visitor, handler map, or Lua pointer table.

## Generated machines

Both generated functions consume the same reviewed physical state:

```c
typedef struct {
    int64_t cursor;
    int64_t limit;
    int64_t accumulator;
} GccJitDriverV1_RuntimeState;
```

The block shape emits a four-block loop with jumps. The tail shape emits a self-call in tail position and
marks it with `gcc_jit_rvalue_set_bool_require_tail_call`. GCC must either satisfy that contract or reject
the compilation.

## Results

The sealed construction driver is 808 bytes and contains 38 Lua bytecode `CALLT` edges. GCC 16.1.1
accepts both generated forms under JIT and `-joff`. At `-O3`, each form becomes the same 15-instruction
native loop modulo labels: one load group, `imul`, increment, accumulation, comparison, backedge, final
state stores, and return. The required recursive call does not survive as a call.

At `-O0`, the tail form ends its body with:

```asm
popq %rbp
jmp gccjit_tail_sum.localalias
```

Thus `gcc_jit_rvalue_set_bool_require_tail_call` is a checked physical contract even without optimization.
GCC later recognizes the complete recurrence as a loop at higher optimization levels.

Representative 11-sample `-O3` medians were:

```text
host mode  shape    total cook   GCC compile   driver work   invoke(100)   native step
JIT        blocks     23.764 ms     23.573 ms      41 us        24.441 ns      0.214 ns
JIT        tail       24.597 ms     24.314 ms      42 us        24.642 ns      0.212 ns
-joff      blocks     23.469 ms     23.407 ms      29 us       252.650 ns      0.216 ns
-joff      tail       24.686 ms     24.610 ms      35 us       259.364 ns      0.215 ns
```

`invoke(100)` includes a Lua loop, state reset, FFI call, and 100 generated iterations. The `-joff`
difference is host overhead, not generated-code speed. `native step` measures one two-million-step generated
invocation and is identical under both host modes. Direct driver construction is tens of microseconds; GCC
compilation, near 24 ms of monotonic wall time, dominates. Earlier CPU-time measurements incorrectly
excluded libgccjit's assembler/driver waits and reported roughly 10 ms.

Explicit context and result release does not immediately return all GCC memory to the operating system. In
one process, resident memory grew from about 11 MB after loading to 42 MB after one compile, 234 MB after
100, 325 MB after 200, and 344 MB after 500. Growth slowed substantially after roughly 200 compilations but
did not disappear after `malloc_trim`. This is foreign GCC process state, not retained CDEF state, and is an
important constraint for a long-lived fine-grained JIT. `rss_bench.lua` reproduces the measurement.

## One compiler self

`compiler_machine.lua` replaces the separate retained backend driver with one explicit compilation-session
owner:

```text
GccJitCompilerV1_Compiler
├── RetainedCompilerV1_Compiler retained
├── ForeignOwner gcc
│   ├── gcc_jit_context *
│   ├── gcc_jit_result *
│   └── entry pointer
├── TypeProjection
├── FunctionProjection → gcc_jit_rvalue * registers[8192]
├── BackendProgress
├── Diagnostic
└── Metrics
```

The 1,281,448-byte root owns frontend/lower state and all foreign backend lifetime. Its implementation has
49 `CALLT` edges. Root stages use `self`; there is no `ctx` parameter:

```lua
function Compiler:gcc_type_ready()
    return self:gcc_declare_function(Compiler.gcc_function_ready)
end

function Compiler:gcc_project_next()
    return self.retained.instructions.items[self.backend.cursor]:project_gccjit(
        self, Compiler.gcc_instruction_projected)
end
```

Only concrete instruction leaves receive the compiler explicitly because their `self` is the leaf:

```lua
function ConstInstruction:project_gccjit(compiler, completed)
    return compiler:gcc_project_constant(self, completed)
end
```

The compiler root is not a context bag or process singleton. Every compilation session has one independently
owned root. This retained-lower adapter is separate from the standalone exotype experiment; it is not the
exotype type system or its compilation path.
Foreign GCC pointers remain compilation-instance-local and never enter an exotype property cache.

The exact register projection reconstructs dependency structure without parsing the textual artifact. For:

```text
let x = 2 + 3;
let y = x * 4;
return y - 5;
```

the GCC graph becomes:

```c
return ((__int64_t)2 + (__int64_t)3) * (__int64_t)4 - (__int64_t)5;
```

and `-O3` emits only `movl $15, %eax; ret`.

Seven-sample monotonic wall-time medians for the compiler-self implementation were:

```text
terms   compiler-self+libgccjit   retained+external C/GCC   backend work
20                   21.022 ms                    34.674 ms         81 us
100                  22.413 ms                    35.219 ms         85 us
500                  22.112 ms                    36.684 ms         68 us
1000                 21.713 ms                    36.437 ms        114 us
2000                 22.451 ms                    38.661 ms        155 us
```

The external comparator compiles an equivalent C expression through `lalin.emit_c_compile`; it includes
file output, process creation, GCC, assembly, linking, and `dlopen`. It is not a `CBackendUnit` equivalence
test. Libgccjit retains a roughly 22 ms fixed cooking cost.

With LuaJIT disabled, the 2,000-term backend projection is approximately 6 ms. Foreign code quality is
unchanged. Under JIT, the recurring binary projection directly performs `XLOAD`, foreign `CALLXS`, and
`XSTORE`; there is one intentional libgccjit construction call per lower instruction.

## LuaJIT FFI tail bridge

The 896-byte `TailBridgeV1_Driver` tests the language boundary directly. Its 40-byte runtime state crosses
LuaJIT FFI by pointer. Both concrete Lua entry methods end in bytecode `CALLT`:

```lua
function Driver:turn(runtime)
    return self.owner.entry(runtime)
end

function Driver:callback_turn(runtime, callback)
    return self.owner.callback_entry(runtime, callback)
end
```

The generated native region has three non-inlined functions. Required tail calls emit:

```asm
tail_bridge_entry:
    jmp tail_bridge_run

tail_bridge_run:
    # retained state loop
    jmp tail_bridge_complete
```

The reverse terminal boundary is an indirect required tail call into a stable LuaJIT callback:

```asm
tail_bridge_callback:
    addq $1, 24(%rdi)
    jmp *%rsi
```

This proves both halves: Lua has a semantic proper-tail FFI entry, and GCC can physically tail-jump into the
LuaJIT callback trampoline. Representative JIT timings are 25.6 ns for one Lua driver tail entry plus 100
native transitions, 24.5 ns through the raw entry pointer, and 246.8 ns for one native tail-jump into a
terminal Lua callback.

The outbound entry loop records as a LuaJIT trace containing `CALLXS`. The callback loop is deliberately
blacklisted at the callback call site; the callback body can trace independently, but repeated native/Lua
ping-pong is not one fused trace. Therefore callbacks are terminal exits only. Native CPS recurrence stays
inside the generated region and returns to a new bounded Lua driver turn.

See [`TAIL_BRIDGE.md`](TAIL_BRIDGE.md) for the exact stack/control interpretation.

## Local library

The experiment loads `libgccjit` from the system, `LIBGCCJIT_PATH`, or:

```text
target/libgccjit/usr/lib64/libgccjit.so.0
```

On Fedora without root access, the latter can be prepared with:

```sh
mkdir -p target/libgccjit-rpm target/libgccjit
cd target/libgccjit-rpm
dnf download --arch=x86_64 libgccjit libgccjit-devel
cd ../libgccjit
for rpm in ../libgccjit-rpm/libgccjit-*.x86_64.rpm; do rpm2cpio "$rpm" | cpio -idm; done
```

## Run

```sh
luajit experiments/gccjit_driver/test.lua
luajit -joff experiments/gccjit_driver/test.lua
luajit experiments/gccjit_driver/bench.lua blocks 11 3
luajit experiments/gccjit_driver/bench.lua tail 11 3
luajit experiments/gccjit_driver/compiler_test.lua
luajit -joff experiments/gccjit_driver/compiler_test.lua
luajit experiments/gccjit_driver/retained_bench.lua gccjit 2000 7 3
luajit experiments/gccjit_driver/retained_bench.lua gcc-c 2000 7 3
luajit experiments/gccjit_driver/tail_bridge_test.lua
luajit -joff experiments/gccjit_driver/tail_bridge_test.lua
luajit experiments/gccjit_driver/tail_bridge_bench.lua 1000000
luajit experiments/gccjit_driver/rss_bench.lua 100 25
```

Inspection artifacts are written to `target/gccjit_driver`: C-like context dumps, Graphviz CFGs, and
assembler output for the block, tail-CPS, compiler-self, and FFI-bridge machine shapes.
