# Lua 5.5 opcodes 13, 14, 17, and 18: frozen table subset

Status: implemented native learner and residual bank for fixed-capacity `GuestTableV1`.

## Scope

This subset implements:

```text
GETI      R[A] = R[B][C]
GETFIELD  R[A] = R[B][K[C]]
SETI      R[A][B] = R[C]        when k = 0
SETFIELD  R[A][K[B]] = R[C]     when k = 0
```

Integer keys and constant indexes are static bytecode operands. `GETFIELD` and `SETFIELD` require a decoded
short-string constant rooted in the same `GuestHeapV1`. Constant-sourced `RK(C)` writes (`k = 1`) remain a named
projection rejection rather than an accidental register interpretation.

## Table storage owner

```text
GuestTableV1
├── immutable object identity and generation
├── owning GuestHeapV1
├── storage generation
├── fixed array capacity and stable array pointer
├── fixed field capacity and stable field pointer
├── exact metatable reference
└── collectable-write barrier count
```

Array keys are one-based and must fit the fixed array capacity. Fields use a bounded stable vector keyed by interned
short-string identity. There is no resize or rehash fallback. A new field consumes a vacant slot and increments the
storage generation.

The implemented primitive value subset is closed:

```text
nil, false, true, integer, float, short string, long string
```

Table-valued slots and writes remain rejected until cyclic guest-object and collector traversal contracts are frozen.

## Read quotation matrix

`GETI` owns seven hit quotations:

```text
Q(13,1)..Q(13,7) = nil through long string
```

`GETFIELD` distinguishes structural absence from an occupied nil slot:

```text
Q(14,1) = missing field -> nil
Q(14,2) = occupied nil
Q(14,3)..Q(14,8) = false through long string
```

This distinction is required because a missing residual guards only storage generation, while an occupied nil residual
also guards the direct slot tag.

## Write quotation matrix

Register-sourced writes select by the observed source tag:

```text
Q(17,1)..Q(17,7) = SETI nil through long string
Q(18,1)..Q(18,7) = SETFIELD nil through long string
```

Payloads remain dynamic frame reads. Integer values, floating values, and references are not specialization axes.
The residual guards the source tag and then copies the complete value into the exact stable slot.

Short- and long-string writes execute an explicit barrier action:

```text
table.barrier_count++
heap.barrier_epoch++
```

The current heap is non-collecting, but collectable writes still make barrier activity explicit. No no-barrier assumption
is hidden in the stencil.

## Table recording facet

The scalar `Lua55LearnFrameV1` ABI remains unchanged. Programs containing table occurrences demand a concrete
`Lua55TableLearnFrameV1` extension whose base frame is first and whose table-recording slots carry only table facts.
Non-table programs do not allocate or expose this facet.

## Learner mutation and final shape

`SETFIELD` can consume a vacant field slot during first execution. That changes the storage generation after earlier
table occurrences have recorded their facts. The concrete `SETFIELD` learner therefore updates earlier recording slots
for the same exact table identity to the final post-insertion generation before publication. This is local table-shape
stabilization, not a generic trace pass.

## Residual guards

Every installed table residual guards:

1. receiver value tag is table;
2. receiver reference is the exact learned table;
3. frame heap is present and is the table's owning heap;
4. collection epoch equals the recorded epoch;
5. object kind is table;
6. storage generation equals the final recorded generation;
7. metatable reference is absent;
8. direct read slot tag or write source tag equals the selected quotation.

A failure sets the exact bytecode resume PC before any write effect. Installed residuals never resize, allocate, invoke a
metamethod, or call Lua.

## Visible rejection

The learner rejects:

- non-table receivers;
- foreign or absent heaps;
- any metatable;
- integer keys outside fixed array capacity;
- field insertion without vacant capacity;
- table-valued or unknown read/write tags.

Projection rejects missing or non-short field constants, missing heap ownership, and constant-sourced writes.

## Physical bank

```text
4 learner stencils    1,363 bytes
29 residual stencils  3,747 bytes
```

The test fixture is an official Lua 5.5.0 chunk containing:

```text
GETI -> GETFIELD -> SETI -> SETFIELD -> MOVE -> MOVE
```

`opcode_table_test.lua` validates first-run effects, final-shape stabilization, varying same-tag writes, exact receiver,
source-tag, generation, collection-epoch, and metatable failures, missing-field invalidation, write barriers, bounded
recurring allocation, explicit ownership release, and JIT-on/`-joff` execution.
