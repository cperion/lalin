# `StencilFunV1`

`StencilFunV1` organizes the native vocabularies as a typed, terminal-driven iterator language inspired by Lua Fun.
Lua Fun remains the semantic oracle and ordinary dynamic iterator implementation. Native execution requires exact
source, operation, and terminal leaves.

## Closed surface

```text
typed_source → (Take | Drop)* → terminal
f64 → map(AddConstant | MultiplyConstant | AddParameter | MultiplyParameter | Square)* → compile_store
f64_reduction → SumFixed | MinNumber | MaxNumber
u8 → FindByte | FindAny2 | FindAny4 | CountByte | AllEqual | AnyEqual
zip_f64 → Add | Multiply | ScaleAdd
f32 → map(AddConstant | MultiplyConstant | AddParameter | MultiplyParameter | Square)* → compile_store
u64_bulk → Store(AddXorRotate operands)
```

The `f64` map chain is compositionally closed. Typed slicing, reductions, scans, and zip terminals are complete for
the frozen V1 leaves. F32 is compositionally closed over the same five map leaves. U64 still exposes its canonical
whole-region terminal while its authored compositional chain remains open.

## Why Lua Fun is not decoded directly

A Lua Fun map stores an arbitrary callback inside nested generic parameter tables. After composition, the iterator does
not retain an exact typed semantic quotation. Recovering one would require callback identity checks, closure inspection,
and manual dispatch.

`StencilFunV1` copies the useful authored algebra while retaining exact operation values. Its `luafun()` method lowers
the same `f64` description through real `lua/fun.lua` for differential validation. Unsupported native behavior is a
missing typed method or visible rejection; there is no silent fallback.

## Example

```lua
local description = StencilFun.f64(input, count)
    :map(StencilFun.add(1.25))
    :map(StencilFun.multiply_parameter(0))
    :map(StencilFun.square())

local compiled = description:compile_store(vector_bank)
compiled:new_separate_frame(output, { 1.5 }):execute()

local oracle = description:luafun({ 1.5 }):totable()
```

Descriptions are immutable. Compilation and Lua Fun execution derive from the same exact operation sequence.
