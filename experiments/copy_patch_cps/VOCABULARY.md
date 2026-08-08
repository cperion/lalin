# `F64MapPipelineV1` stencil vocabulary

`F64MapPipelineV1` is the first useful copy-and-patch domain. It targets runtime-composed contiguous `f64` maps because
LuaJIT does not vectorize them. The scalar sum graph remains only a relocation and W^X proof.

## Authored semantic leaves

```text
AddConstant(value)
MultiplyConstant(value)
AddParameter(index)
MultiplyParameter(index)
Square
```

Constants and supplied parameter values must be finite. Operations execute in authored order. There is no reassociation,
implicit contraction, or fast-math behavior. FMA is not part of V1.

Every add or multiply occurrence consumes one scalar slot. `Square` consumes none. V1 has exactly four slots:

```text
Scalar0 → frame.scalar0 → ymm1
Scalar1 → frame.scalar1 → ymm2
Scalar2 → frame.scalar2 → ymm3
Scalar3 → frame.scalar3 → ymm4
```

A fifth scalar-consuming occurrence is rejected before native linking. Repeated values are not deduplicated in V1.

## Runtime frame

```c
typedef struct CopyPatchF64MapFrameV1 {
    const double *input;
    double *output;
    uint64_t count;
    double scalar0;
    double scalar1;
    double scalar2;
    double scalar3;
} CopyPatchF64MapFrameV1;
```

The Lua frame owner retains input and output storage across the complete native call. `InPlaceFrame` uses identical
pointers. `SeparateFrame` requires disjoint byte ranges. Partial overlap is rejected.

## Native ABI

```text
rdi      frame
rsi      current input
rdx      current output
rcx      remaining count
ymm0     current packed value
ymm1–4   Scalar0–Scalar3 broadcasts
```

Entry broadcasts all four scalar fields once. Unused slots contain zero.

## Structural stencil leaves

```text
Entry
VectorTest
VectorLoad
VectorStoreAdvance
ScalarTest
ScalarLoad
ScalarStoreAdvance
Finish
```

`VectorTest` enters the packed body while at least four elements remain. `ScalarTest` handles the final zero to three.
`ScalarLoad` broadcasts one input value into `ymm0`; consequently the same packed operation snippets implement both
the vector body and scalar tail. `Finish` is exactly `vzeroupper; ret`.

## Physical operation leaves

```text
AddScalar0    AddScalar1    AddScalar2    AddScalar3
MulScalar0    MulScalar1    MulScalar2    MulScalar3
Square
```

Every physical operation leaves the current value in `ymm0` and preserves the complete successor ABI.

## Native control graph

```text
Entry → VectorTest
VectorTest.full → VectorLoad → operation sequence → VectorStoreAdvance → VectorTest
VectorTest.tail → ScalarTest
ScalarTest.some → ScalarLoad → operation sequence → ScalarStoreAdvance → ScalarTest
ScalarTest.done → Finish
```

## Relocation alternatives

V1 accepts only `R_X86_64_PLT32` with addend `-4` on an `E9 rel32` jump.

A straight-line successor must be the final five bytes of its stencil. The linker validates and removes that jump, then
places the successor bytes immediately after the prefix. A control successor retains its jump and receives a signed
rel32 patch after all graph offsets have been published.

There are no data relocations. Scalar values travel through the frame and persistent YMM slots.

## ISA and object contract

```text
host              Linux x86-64 SysV
required feature  OS-enabled AVX and AVX2
GCC flags         -O3 -mavx2 -mfma -fno-pic -ffunction-sections
loads/stores      unaligned
element type      f64
maximum ops       64
```

No operation, load, store, or control stencil may contain `vzeroupper`. The finish stencil must contain it. Unsupported
relocation counts, symbols, addends, or terminal instruction shapes reject bank generation.

## Ownership and executable memory

The linker allocates one RW region, copies all reached snippets, publishes every block offset, patches both native
cycles, and changes the complete region to RX. The entry function pointer is borrowed from the native program owner.
The region is never writable and executable simultaneously.

## Explicitly outside V1

```text
f32
reductions and dot products
gathers, scatters, and non-unit strides
partial aliasing
more than four scalar operand occurrences
FMA or floating-point reassociation
callbacks, allocation, exceptions, and safepoints
non-x86-64 architectures
```
