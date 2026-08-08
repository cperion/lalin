# WebAssembly lazy-owner CPS residualization

This experiment applies the same canonical lazy-owner pattern as the Lua 5.5 implementation to
WebAssembly stack bytecode. Concrete opcode owners analyze validated stack shape, lazily materialize
private occurrence prototypes, publish cyclic identity, emit projection facets, and bind direct CPS
successors.

## Pipeline

```text
Wasm binary
  → decode type/function/export/code sections
  → resolve block, loop, br, and br_if targets
  → concrete opcode-owner stack analysis
  → lazy owner query per reached instruction occurrence
      → private occurrence prototype and memoized closure
      → readable source/control/operand projection
      → publish before cyclic successor binding
  → validated operand stack passed as CPS arguments
  → prepare/seal reachable graph
  → LuaJIT traces the residual machine
```

The canonical residual specializes the statically known stack shape into CPS parameters:

```lua
pc_12_i32_add = function(self, v1, v2)
    return pc_13_local_set(self, bit.tobit(v1 + v2))
end
```

At a merge or loop header, the residual function parameters are the validated Wasm stack signature.
They act as CPS phi inputs. A Wasm `br_if` passes the appropriate prefix directly to either its
resolved label target or fallthrough. There is no runtime operand-stack table, stack pointer, Wasm
opcode dispatch, or program counter in the flattened residual.

## Bounded semantic slice

The 154-byte fixture exports:

- `sum(i32) -> i32`;
- `mixed(i32) -> f64`.

The decoder and owner protocol currently support only the instructions required by these functions:

```text
block loop end br br_if
local.get local.set
i32.const i32.gt_s i32.add
f64.const f64.add f64.mul f64.convert_i32_s
```

Blocks have empty result types and fixture branch targets have operand-stack height zero. General
Wasm validation, value-carrying branches, calls, memory, tables, imports, traps, and the remaining
instruction set are not claimed.

## Files

- `sample.wat` — two numerical Wasm functions.
- `wasm.lua` — minimal binary decoder and structured-label linker.
- `cps_owner.lua` — canonical lazy owner, stack projection, residualizer, and projection foundry;
- `test.lua` — formula and generated-shape tests under JIT and `-joff`.
- `bench.lua` — lazy-owner CPS and same-source LuaJIT benchmark;
- `native_bench.js` — native V8 WebAssembly benchmark.
- `tcc_jit.lua`, `tcc_shapes.lua` — in-memory libtcc functions and CPS boundary shapes.
- `TCC_FFI.md` — native-leaf boundary experiment and measurements.

## Run

```sh
luajit -Oloopunroll=1000 experiments/wasm_gcps/test.lua
luajit -joff experiments/wasm_gcps/test.lua

luajit -Oloopunroll=1000 experiments/wasm_gcps/bench.lua owner_sum 5000 1000 7
luajit -Oloopunroll=1000 experiments/wasm_gcps/bench.lua owner_mixed 5000 1000 7

wat2wasm experiments/wasm_gcps/sample.wat -o /tmp/gcps-sample.wasm
node experiments/wasm_gcps/native_bench.js /tmp/gcps-sample.wasm sum 5000 1000 7
node experiments/wasm_gcps/native_bench.js /tmp/gcps-sample.wasm mixed 5000 1000 7

wasmtime run --invoke sum /tmp/gcps-sample.wasm 1000
wasmtime run --invoke mixed /tmp/gcps-sample.wasm 1000
```

## Results

Nine isolated-process medians for the canonical owner path, with retained historical comparisons:

```text
shape                 integer sum   mixed sum
lazy-owner flattened     3.501 ns    0.883 ns
historical eager flat    4.632 ns    0.996 ns
direct LuaJIT             0.641 ns    0.645 ns
V8 WebAssembly            0.232 ns    0.654 ns
```

The loop body crosses 13 residual functions for integer sum and 16 for mixed sum, so benchmarks use
`loopunroll=1000` to give LuaJIT enough recurrence capacity.

Flattening removes all operand-stack table traffic. The exact-i32 path remains trace-sensitive: nine
lazy-owner runs ranged from 0.748 to 3.761 ns. The mixed path ranged from 0.771 to 3.769 ns, with a
0.883 ns median. The owner migration changes staging ownership and prototype isolation; it does not
remove LuaJIT trace-shape sensitivity.

The result identifies the Wasm-specific trick: do not merely monomorphize opcode dispatch. Project
Wasm validation facts into residual CPS signatures so the transient operand stack remains virtual.

## Optional TCC native leaves

[`TCC_FFI.md`](TCC_FFI.md) tests immutable typed calls into in-memory `libtcc` code. Fine FFI
boundaries remain opaque and lose on the mixed loop. One whole native region measures 0.552 ns per
integer iteration but 2.488 ns per mixed iteration. TCC construction costs 152.895 microseconds per
module. The useful rule is coarse native leaves only; LuaJIT does not trace through their C bodies.

## Pattern evidence

The implementation confirms that GCPS is not specific to register bytecode:

```text
Lua 5.5     registers + relative edges  → lazy semantic owners → private residual CPS
WebAssembly operand stack + label depth → lazy semantic owners → flattened private residual CPS
```

The same pattern invariants now survive in both implementations: concrete semantic owners, lazy reached
occurrences, private prototypes, publish-before-bind cycles, named projection facets, explicit sealing,
resolved proper-tail edges, no runtime dispatcher, and JIT-independent correctness. Wasm adds a useful
refinement: statically validated transient state can travel on CPS edges rather than being reified
inside `self`.

