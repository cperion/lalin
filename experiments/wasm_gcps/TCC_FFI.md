# libtcc FFI boundaries inside Lua CPS

## Question

Can a LuaJIT CPS machine accelerate selected regions by calling functions compiled in memory with
`libtcc`?

## Shapes

`tcc_jit.lua` compiles 1,316 bytes of C directly into memory and projects precisely typed function
pointers through LuaJIT FFI. No shared object, executable file, or C-to-Lua callback is used.

Three boundary granularities are measured:

```text
opcode boundary  Lua CPS → 2–3 tiny C calls per guest iteration → Lua CPS
step boundary    Lua CPS → 1 state-mutating C call per guest iteration → Lua CPS
region boundary  Lua     → 1 C call containing 1,000 guest iterations → Lua
```

The opcode and step forms remain proper-tail Lua CPS. Traces close around their FFI calls, but the C
bodies remain opaque operations to LuaJIT.

## Correctness

All six shapes match the integer and mixed formulas for bounds 0–1,000 under JIT and `-joff`. The
integer paths also validate wrapping i32 addition at bound 65,536.

```sh
luajit -Oloopunroll=1000 experiments/wasm_gcps/tcc_test.lua
luajit -joff experiments/wasm_gcps/tcc_test.lua
```

## Runtime results

Nine isolated-process medians, with 5,000 public calls of 1,000 iterations:

```text
boundary              integer sum   mixed sum
TCC call per opcode       3.302 ns     5.053 ns
TCC call per iteration    3.657 ns     2.614 ns
TCC whole region          0.552 ns     2.488 ns
flattened Lua CPS         4.632 ns     0.996 ns
direct LuaJIT             0.641 ns     0.645 ns
V8 WebAssembly            0.232 ns     0.654 ns
```

The integer flattened-CPS result is trace-sensitive; its measured range is 1.122–4.664 ns. The TCC
opcode result is more stable, but it is not a general win.

With LuaJIT disabled, whole-region TCC remains 0.600 ns per integer iteration and 2.600 ns per mixed
iteration. Fine Lua CPS/FFI recurrence falls to 88–131 ns per iteration because its control remains
interpreted.

## Construction

Nine isolated construction medians:

```text
materialization       microseconds/module
LuaJIT template CPS          43.757
Lua source CPS               85.927
libtcc C                    152.895
```

The TCC module owns its `TCCState` until every projected function pointer is dead. Explicit `free()`
removes the FFI finalizer and deletes that state.

## Interpretation

The literal answer is **yes, but LuaJIT races around C rather than through it**.

- LuaJIT can close a CPS trace containing immutable typed FFI calls.
- It cannot inspect, inline, or optimize the TCC body.
- Per-opcode FFI calls lose badly on the mixed loop.
- A state-mutating step call adds memory traffic and is not automatically better.
- A whole integer region amortizes the boundary and beats direct LuaJIT in this test.
- TCC's unoptimized floating-point loop is 2.5x slower than flattened Lua CPS and 3.8x slower than
  V8 WebAssembly.

TCC does not perform useful inlining here. Native region source must contain final arithmetic
directly; calling tiny C helpers from the generated C loop made the region much slower.

## Rule

```text
Lua CPS owns dynamic and compositional control.
TCC owns only a coarse dense region with enough work to amortize FFI.
The transition is a one-way call and return, never a C-to-Lua callback.
```

This is a useful optional leaf strategy, not a replacement for GCPS. Whether it wins depends on both
boundary frequency and TCC's code quality for the region.

