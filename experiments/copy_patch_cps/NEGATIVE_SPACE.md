# Negative-space V1 superstencils

This suite establishes exact native leaves in every high-value LuaJIT negative-space domain. It uses whole-region
superstencils for closed terminal operations and retains separate compositional vocabularies where required. All entries
are compiled with AVX2 and copied into one W^X-owned executable region.

## Leaves

### `F64ReductionV1.FixedTreeSum`

Four independent `f64x4` accumulators consume sixteen elements per recurrence. Finalization uses a fixed pairwise tree,
then processes the tail in scalar order. Its result is deterministic for this physical schedule but is not source-order
floating-point addition.

`MinNumber` and `MaxNumber` ignore NaNs when a numeric value exists, return a quiet NaN for empty/all-NaN inputs, and
select `-0` for minimum and `+0` for maximum.

### `U8ScanV1.FindByte`

Each recurrence compares 32 bytes, extracts a mask, and uses the first set bit. The durable result is the first matching
index or `count` when no byte matches. `FindAny2`, `FindAny4`, `CountByte`, `AllEqual`, and `AnyEqual` complete the
frozen scan terminal set.

### `F64ZipMapV1.ScaleAdd`

```text
output[i] = left[i] * scale + right[i]
```

`Add` and `Multiply` are separate exact zip leaves.

`-ffp-contract=off` preserves separate multiply and add rounding. Inputs and output are expected to be valid,
contiguous, and disjoint for the complete count.

### `F32MapPipelineV1.CanonicalFive`

Eight `f32` lanes execute:

```text
add scalar0 → multiply scalar1 → add scalar2 → multiply scalar3 → square
```

This first leaf mirrors the canonical `f64` pipeline. Runtime composition is not yet claimed for `f32`.

### `U64BulkV1.AddXorRotate`

Four `u64` lanes execute wrapping addition, XOR, and rotate-left. Rotation is masked to `0..63`. This gives exact
integer semantics without Lua number conversion.

## Object and ownership contract

The bank generator rejects code relocations in all five function sections. Internal branches remain valid when an
The linker copies complete sections, aligns each entry to 32 bytes, and changes the complete executable allocation
from RW to RX before publishing typed entry pointers.

The caller owns each typed frame and every borrowed input/output buffer across the native call. No leaf allocates, calls
Lua, suspends, or reaches a safepoint.

## Deliberate limits

The F32 canonical and U64 bulk leaves remain vocabulary seeds. F32 still needs its compositional quotation. U64 has
runtime-learned add/XOR/rotate and exact-tail recurrences, while a general authored U64 operation chain remains open.
Zip partial-overlap schedules remain rejected.
