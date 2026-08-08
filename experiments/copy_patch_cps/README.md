# Isolated GCC `-O3` copy-and-patch CPS experiment

This experiment keeps Lua in the staging/linking layer and executes recurring control entirely in copied native
stencils. It is isolated from the production Lalin backend.

Current direction:

- `lua55_trace/NATIVE_CPS_V2_COMPLETE_MIGRATION_DESIGN.md` defines the binding
  standalone Native CPS V2 architecture and exact-residual completion gates.
- `lua55_trace/V2_RESIDUAL_SPECIALIZATION_INVENTORY.md` audits every opcode and
  requires published residuals to contain one guarded semantic implementation,
  never generic tag/kind/key/callee dispatch.
- `LUA55_TRACE_RECORDER_DESIGN.md` defines the earlier bounded one-shot CPS
  recorder pattern.
- `PROJECT_SCOPE.md` defines the revised project layers, stopped work, and
  decision gates.

## Exact x86-64 SysV protocol

```text
rdi  CopyPatchCpsFrame *
rsi  accumulator
rdx  limit
rcx  step
r8   index
r9   reserved
```

The four concrete stencil leaves are:

```text
EntryStencil   initialize registers → LoopStencil
LoopStencil    index <= limit → BodyStencil | FinishStencil
BodyStencil    add and advance → LoopStencil
FinishStencil  store result → native return
```

The loop/body edges form a direct native cycle. Lua enters once through an FFI function pointer and regains control
only when `FinishStencil` returns.

## Build-time stencil bank

`stencils.c` is compiled with:

```text
gcc -O3 -fno-pic -ffunction-sections -fno-stack-protector
```

Every CPS successor is an unresolved typed C function. `build_bank.lua` consumes the resulting ELF relocation records,
requires `R_X86_64_PLT32` with addend `-4`, and verifies that every successor relocation belongs to an `E9 rel32`
tail jump. Unsupported or changed shapes are rejected.

## Runtime linker

The Lua linker:

1. allocates RW memory;
2. copies the four reached code sections;
3. publishes all offsets;
4. patches the cyclic rel32 successor graph;
5. changes the complete allocation to RX;
6. exposes one Lua-owned FFI entry pointer.

No memory is simultaneously writable and executable. Raw function pointers remain borrowed from the `Program` owner.

## Current result

With GCC 16.1.1 on x86-64, the bank contains:

```text
EntryStencil    21 bytes
LoopStencil     21 bytes
BodyStencil     11 bytes
FinishStencil    5 bytes
linked graph    85 bytes including alignment
```

Representative linking takes approximately 19–20 microseconds. A 1,000-iteration sum loop measures approximately
0.61–0.65 ns per native iteration, including one LuaJIT FFI entry and return per complete loop. Host JIT mode does not
affect native recurrence semantics.
## `F64MapPipelineV1` vector vocabulary

The first useful vocabulary targets an operation LuaJIT does not perform: AVX2 vectorization of runtime-composed
`f64` array pipelines. It supports four scalar operand occurrences, assigned to slots `0` through `3`, and these
operation leaves:

```text
AddConstant
MultiplyConstant
AddParameter
MultiplyParameter
Square
```

The linker strips terminal jumps between straight-line snippets, so load, operations, and store execute by fallthrough.
Only vector/scalar loop control retains patched jumps. Arbitrary element counts use a four-lane AVX2 loop followed by
a zero-to-three-element scalar tail that reuses the same packed operation snippets.

The canonical five-operation graph is 212 bytes. Representative results are approximately:

```text
warm shape linking       10–20 microseconds
native AVX2 execution     0.29 ns/element
LuaJIT scalar execution   0.43 ns/element
whole-region GCC          0.29 ns/element
```

See `CLOSED_STENCIL_VOCABULARY.md` for the frozen cross-domain vocabulary and specialization timing.
See `VOCABULARY.md` for the original F64 map semantic, physical, relocation, and memory contracts.

## Negative-space superstencil suite

Five additional closed leaves cover the first useful slice of each remaining measured domain:

```text
F64ReductionV1     FixedTreeSum
U8ScanV1           FindByte
F64ZipMapV1        ScaleAdd
F32MapPipelineV1   canonical five-operation map
U64BulkV1          AddXorRotate
```

These are whole-region superstencils with internal relative control and no ELF code relocations. They are copied into
one 2,700-byte RX suite. This is a breadth baseline, not a claim that each domain vocabulary is complete. See
`NEGATIVE_SPACE.md`.

## Run

```sh
# Scalar relocation/control proof
luajit experiments/copy_patch_cps/build_bank.lua
luajit experiments/copy_patch_cps/test.lua
luajit -joff experiments/copy_patch_cps/test.lua

# F64MapPipelineV1
luajit experiments/copy_patch_cps/build_vector_bank.lua
luajit experiments/copy_patch_cps/vector_test.lua
luajit experiments/copy_patch_cps/vector_closure_test.lua
luajit -joff experiments/copy_patch_cps/vector_test.lua
luajit experiments/copy_patch_cps/vector_bench.lua 1048576 100 7

# First leaf in each remaining negative-space domain
luajit experiments/copy_patch_cps/build_negative_space_bank.lua
luajit experiments/copy_patch_cps/negative_space_test.lua
luajit -joff experiments/copy_patch_cps/negative_space_test.lua

# Typed Lua Fun-inspired terminal surface
luajit experiments/copy_patch_cps/stencil_fun_test.lua
luajit -joff experiments/copy_patch_cps/stencil_fun_test.lua
```

Generated object files, section binaries, disassembly, and bank metadata stay beneath `target/copy_patch_cps/`.
