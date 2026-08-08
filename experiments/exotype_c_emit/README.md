# Exotype-specialized emitted C

This experiment keeps application control in Lua and cooks only selected kernels with GCC:

```text
Lua-owned runtime structure
  → first-class exotype owner
  → lazy ABI/layout and C-module properties
  → disposable specialized C string
  → spawned GCC -O3
  → shared object loaded through LuaJIT FFI
  → stable function pointer
```

Property lookup, operation objects, source generation, and GCC disappear before recurring execution. Emitted C is
transient compiler input with no readability or stable-shape contract.

## Stateful pipeline probe

`pipeline.lua` creates a physical state type after receiving a runtime stage sequence. Equivalent sequences are
interned. `StateLayout` chooses an exact `stage_hits[N]` array, while `CModule` emits the selected transitions.

Concrete stage leaves own generation:

```text
AddStage
MultiplyStage
RejectAboveStage
```

The generated module starts with several ordinary C functions because the source semantics are CPS. Those functions
are not binary boundaries. Unrestricted GCC `-O3` can inline, fuse, clone, or erase them.

## Fused array kernel

`array_kernel.lua` is the intended application shape. Lua owns input, output, parameter buffers, configuration, and
the loaded module. A runtime operation sequence creates an `f32` or `f64` kernel owner.

```lua
local Type = Kernel.type(Kernel.f64, {
    Kernel.multiply(1.5),
    Kernel.add_parameter(0),
    Kernel.square(),
    Kernel.multiply_parameter(1),
    Kernel.add(3.0),
})
```

Concrete operation leaves contribute directly to one specialized array loop:

```text
AddConstant
MultiplyConstant
AddParameter
MultiplyParameter
Square
```

The recurring ABI is:

```text
kernel(output, input, element_count, parameters)
```

The function uses `restrict` input, output, and parameter pointers. Owners must therefore provide distinct
non-overlapping buffers for one call. Operation objects and exotype properties do not survive into native execution.

The canonical five-operation `f64` kernel measured:

```text
GCC cook                  approximately 35 ms
recurring execution       approximately 0.291 ns/element
effective read/write      approximately 55 GB/s
```

The fixed cooking cost is why this path is for coarse kernels rather than scalar operations.

## Ownership

Each `Program` retains its `ffi.load` handle. A captured entry function must not outlive that owner. LuaJIT FFI cdata
owns the exact input, output, and parameter buffers passed to native code.

## Files

```text
protocol.lua         local owner/property/query protocol
pipeline.lua         stateful pipeline exotype
compiler.lua         pipeline GCC cooker and FFI owner
test.lua             pipeline behavior and layout checks
bench.lua            pipeline function-pointer benchmark
array_kernel.lua     fused array-kernel constructor and operation leaves
array_compiler.lua   array-kernel GCC cooker and FFI owner
array_test.lua       f32/f64 ABI, ownership, interning, and behavior checks
array_bench.lua      fused native-kernel benchmark
```

## Run

```sh
luajit experiments/exotype_c_emit/test.lua
luajit -joff experiments/exotype_c_emit/test.lua
luajit experiments/exotype_c_emit/bench.lua 1000000 7

luajit experiments/exotype_c_emit/array_test.lua
luajit -joff experiments/exotype_c_emit/array_test.lua
luajit experiments/exotype_c_emit/array_bench.lua 1000000 100 7
```

Artifacts are written beneath `target/exotype_c_emit/`:

```text
pipeline_TOKEN_PID.c
pipeline_TOKEN_PID.so
pipeline_TOKEN_PID.log
array_TOKEN_PID.c
array_TOKEN_PID.so
array_TOKEN_PID.log
```
