# Closed stencil vocabulary and specialization model

This document freezes the copy-and-patch experiment around one principle:

> Use a fixed, closed, domain-owned stencil vocabulary. Resolve every stable fact at the earliest stage that knows it.
> When a fact is learned only during native initialization and remains loop-invariant, install a specialized recurrence
> once and remove the learner from the backedge.

Lua owns descriptions, staging, executable ownership, and terminal entry. GCC builds the controlled stencil bank.
Recurring numerical and scanning work executes in copied native code.

## Non-goals

This is not a generic native IR, arbitrary Lua Fun compiler, universal register machine, or optimizing JIT framework.
The compiler does not inspect arbitrary Lua callbacks or silently fall back to Lua. Behavior outside the closed grammar
is rejected before native linking.

## Closed authored vocabulary

### Sources

```text
F64Array
F32Array
U64Array
U8Array
F64Zip2
```

### Structural source projections

```text
Take
Drop
```

`Take` and `Drop` adjust typed pointer/count projections. They do not introduce recurring native dispatch.

### F64 and F32 map operations

```text
AddConstant
MultiplyConstant
AddParameter
MultiplyParameter
Square
```

### U64 map operations

```text
Add
Xor
And
Or
ShiftLeft
ShiftRight
RotateLeft
```

### F64 zip operations

```text
Add
Multiply
ScaleAdd
```

### Reductions

```text
FixedTreeSum
MinNumber
MaxNumber
```

Floating reductions have explicit schedules and NaN/signed-zero policies. `FixedTreeSum` does not claim source-order
floating-point addition.

### U8 scans

```text
FindByte
FindAny2
FindAny4
CountByte
AllEqual
AnyEqual
```

### Terminals

```text
Store
Reduce
FindFirst
Count
All
Any
```

Every valid source/operation/terminal composition must have a native lowering and a Lua Fun differential oracle.
Arbitrary Lua Fun callbacks are outside the vocabulary.

## Physical register protocols

### F64 map

```text
rdi      frame
rsi      input
rdx      output
rcx      remaining
ymm0     current f64x4 value
ymm1–4   scalar slots 0–3
```

### F32 map

```text
rdi      frame
rsi      input
rdx      output
rcx      remaining
ymm0     current f32x8 value
ymm1–4   scalar slots 0–3
```

### U64 learned loop

```text
frame    input/output/count/addend/xor/rotate
ymm0     current u64x4 value
immediates patched for invariant rotate counts
```

Each domain owns its ABI. There is no universal stencil calling convention.

## Specialization stages

### 1. Build-time stencil generation

Known facts:

```text
target architecture
compiler and object flags
instruction family
successor ABI
relocation alternatives
maximum variant sizes
```

GCC emits one function section per concrete stencil. Extraction validates symbol boundaries, relocations, terminal
jumps, instruction encodings, and immediate-hole sentinels. Unsupported object shapes fail the bank build.

### 2. Description-time specialization

Known facts:

```text
typed source
operation sequence
terminal
authored constants
scalar operand occurrence count
floating-point contraction policy
```

Actions:

```text
select semantic stencil leaves
bind scalar slots
concatenate straight-line snippets
strip validated fallthrough jumps
reject unsupported compositions
```

No operation dispatch survives recurring execution.

### 3. Link-time specialization

Known facts:

```text
reached control graph
code layout
successor addresses
immutable constant bits
selected structural variants
```

Actions:

```text
publish every code offset
patch successor rel32 holes
patch immediate/data holes
copy only reached stencils
change completed code from RW to RX
```

### 4. Frame-time specialization

Known facts:

```text
concrete pointers
count and remainder
alignment
alias topology
runtime scalar values
stride
```

Facts already visible to Lua should normally be resolved before native entry. A frame captures a stable entry once.

### 5. Native initialization-time specialization

This is the R-style runtime specialization stage. It is used only when a fact is unavailable during linking but is
cheaply learned by native initialization and proven invariant for the recurrence.

```text
generic/native learner
→ classify invariant frame or object facts
→ select a prepatched variant
→ make an inactive page-isolated slot RW
→ copy the complete recurrence
→ patch remaining immediate holes
→ clear the instruction cache
→ make the slot RX
→ publish and enter the specialized recurrence
```

The learner runs once. Subsequent executions enter the specialized slot directly.


## Hole vocabulary

```text
SuccessorRel32
Immediate8
Immediate32
Immediate64
FrameDisplacement32
RelativeData32
NearExternal32
FarExternalIndirect
```

Currently validated and implemented holes are:

```text
R_X86_64_PLT32 successor with addend -4
terminal E9 rel32 fallthrough/control transfer
U64 rotate Immediate8 fields
```

Instruction-byte holes require complete architecture-specific encoding validation. The linker never searches for an
untyped byte value and assumes it is patchable.

## Domain specialization matrix

### F64/F32 maps

| Fact | Earliest stage | Variant/action |
|---|---|---|
| Element type | Description | Separate F64/F32 bank and ABI |
| Operation sequence | Description | Concatenated operation snippets |
| Scalar slot count 0–4 | Description | EntryScalars0–4 |
| Count remainder | Frame | NoTail or Tail1–3 |
| Exact small count | Frame | Fixed unrolled recurrence |
| Alignment | Frame | Aligned or unaligned load/store |
| In-place/disjoint | Frame | Exact memory topology variant when schedules differ |
| Dynamic storage representation | Native initialization | Install typed recurrence |

Scalar values do not automatically remove floating operations. Transformations such as `+0`, `*1`, or FMA contraction
require explicit semantics because of NaNs, signed zero, rounding, and floating-point exceptions.

### F64 reductions

| Fact | Earliest stage | Variant/action |
|---|---|---|
| Reduction operation/policy | Description | Sum, MinNumber, or MaxNumber |
| Count class | Frame | Empty, scalar-small, or vector recurrence |
| Accumulator schedule | Frame | One or four vector accumulators |
| Tail size | Frame | Exact Tail0–15 |
| Alignment | Frame | Aligned or unaligned loads |

NaN presence and value ranges are data-dependent scans, not invariant specialization facts.

### U8 scans

| Fact | Earliest stage | Variant/action |
|---|---|---|
| Scan terminal | Description | Find, count, all, or any |
| Needle cardinality | Description | Byte, Any2, or Any4 |
| Count class | Frame | Scalar-small or vector scan |
| Tail size | Frame | Exact Tail0–31 |
| Alignment | Frame | Aligned or unaligned loads |

Match location and match density are not invariant and do not select baseline variants.

### F64 zip maps

| Fact | Earliest stage | Variant/action |
|---|---|---|
| Zip operation | Description | Add, multiply, or scale-add |
| Alias topology | Frame | Disjoint, aliases-left, aliases-right, or directional overlap |
| Count/remainder | Frame | NoTail or exact tail |
| Three-pointer alignment | Frame | Aligned or unaligned schedule |
| FMA permission | Description | Explicit contracted leaf only |

Partial overlap remains rejected until forward/backward variants are implemented and validated.

### U64 bulk loops

| Fact | Earliest stage | Variant/action |
|---|---|---|
| Addend is zero | Native initialization | Remove packed add |
| XOR value is zero | Native initialization | Remove packed XOR |
| Rotate is zero | Native initialization | Remove rotate |
| Rotate is 1–63 | Native initialization | Patch two Immediate8 shift counts |
| Count/remainder | Frame | NoTail or exact tail |
| Alignment | Frame | Aligned or unaligned loads/stores |

The implemented U64 structural variants are:

```text
Copy
Add
Xor
AddXor
RotateImmediate
AddRotateImmediate
XorRotateImmediate
AddXorRotateImmediate
```

For rotation `r`, the learner patches:

```text
left shift immediate  = r
right shift immediate = (64 - r) mod 64
```

## U64 runtime specialization lifecycle

The current end-to-end experiment implements:

```text
12 extracted operation variants
4 validated Immediate8 templates
256 prepatched operation selections
32 whole-loop recurrence variants (8 operation shapes × 4 exact remainders)
230-byte maximum recurrence
one page-isolated runtime slot per active owner
native add/xor/rotate/remainder classification
native RW installation
instruction-cache synchronization
native RX publication
first-call execution through the learner
direct recurring specialized execution
```

Generation behavior is exact:

```text
before first call     generation 0
after learning        generation 1
all recurring calls   generation 1
```

The recurrence is never reinstalled unless an explicit new frame/generation is created.

Representative direct-entry measurements for `AddXorRotateImmediate` are:

```text
256 elements       1.23x over generic variable shifts
4,096 elements     1.12x over generic variable shifts
1,048,576 elements 1.03x over generic variable shifts
```

The runtime caller must capture the specialized entry once. Re-entering through a Lua phase method obscures gains on
small buffers with avoidable host dispatch overhead.

## Runtime replacement and W^X

Each mutable recurrence slot occupies its own page and is inactive while writable.

```text
learner code page       RX and executing
recurrence slot page    RW while inactive
recurrence slot page    RX before transfer
```

A borrowed or executing slot cannot be replaced or released. Concurrent activations never share one mutable slot.
Prepatched auxiliary variants live in non-executable memory.

## Completeness criterion

A vocabulary is complete only when:

1. every grammar production has a native lowering;
2. every valid composition has deterministic projection;
3. every terminal has a Lua Fun oracle;
4. empty, scalar-tail, vector, alias, capacity, and rejection paths pass;
5. every physical stencil and hole alternative is exercised;
6. JIT and `-joff` produce identical semantics;
7. all foreign pointers have explicit owners;
8. released or borrowed executable memory rejects invalid operations;
9. unsupported facts reject before entering native code;
10. no recurring generic dispatcher or learner remains.

## Implementation status

| Vocabulary | Status |
|---|---|
| F64 compositional map | Implemented and closure-tested |
| F32 compositional map | Implemented with the five closed map operations |
| U64 runtime-learned recurrence | Add/XOR/rotate and exact Tail0–3 specialization implemented |
| F64 zip map | Add, Multiply, and ScaleAdd implemented |
| F64 reduction | FixedTreeSum, MinNumber, and MaxNumber implemented |
| U8 scan | FindByte, FindAny2/4, CountByte, AllEqual, and AnyEqual implemented |
| Typed Take/Drop | Implemented for all current typed sources |
| StencilFun closed surface | Implemented as facade; full closure pending |

The fixed vocabulary is frozen by this document. New leaves require a concrete workload, exact semantics, object-shape
validation, and closure tests.
