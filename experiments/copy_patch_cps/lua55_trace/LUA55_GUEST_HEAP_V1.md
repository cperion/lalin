# Lua 5.5 Guest Heap V1

Status: immutable strings and bounded fixed-storage tables implemented.

## Purpose

Native residuals cannot retain raw LuaJIT GC pointers. `GuestHeapV1` provides non-moving C-representable guest objects
whose Lua owners are retained across every FFI call and by every RX artifact that embeds an object reference.

## Heap contract

```text
GuestHeapV1
├── heap generation
├── collection epoch
├── object count
├── barrier epoch
├── immutable short strings
├── immutable long strings
├── fixed-storage tables
└── artifact retain count
```

The current owner allocates C data through LuaJIT FFI but retains every owning cdata object in the heap owner. Native
frames and stencils contain only raw native addresses. Those addresses do not retain their owners; the explicit heap
and program references do.

A program retains the heap when its learner RX artifact is published and releases it when the program is freed. The
heap rejects explicit release while any RX artifact remains.

## String objects

```text
GuestStringV1
├── object kind
├── immutable generation
├── byte length
├── deterministic hash
└── stable byte pointer
```

Short and long strings are distinct owners because Lua bytecode preserves that distinction. Interning is exact within
one heap and uses byte equality, including embedded zero bytes. String addresses remain stable until explicit heap
release.

## Frame values

The value vocabulary now includes:

```text
ShortStringValue(tag=5, stable reference)
LongStringValue(tag=6, stable reference)
```

The physical bank implements:

```text
Q(0,6)  guarded short-string MOVE
Q(0,7)  guarded long-string MOVE
Q(3,6)  short-string LOADK
Q(3,7)  long-string LOADK
Q(4,6)  short-string LOADKX
Q(4,7)  long-string LOADKX
```

The shared `MOVE` learner observes both tags and selects the corresponding residual quotation. `LOADK` and `LOADKX`
constants are allocated and rooted during decoded-prototype projection, not discovered during first execution.

## Tables and collection epochs

`GuestTableV1` owns stable fixed-capacity array and field storage, an exact storage generation, a metatable reference,
and a barrier counter. Field insertion increments storage generation. String writes increment both the table barrier
counter and heap barrier epoch.

All direct table residuals guard the collection epoch. Immutable string references survive epoch changes, but an
installed table residual exits because direct slot assumptions belong to the recorded heap epoch. V1 performs no
collection; these guards and barriers establish the physical boundary needed before collection is introduced.

## Validation

`opcode_string_test.lua` uses an official Lua 5.5.0 chunk containing one short and one long string. It validates:

- concrete decoded short/long constant leaves;
- visible rejection when no guest heap is supplied;
- exact interning and stable references;
- real-prototype `LOADK` projection;
- native first-run quotation selection;
- guarded short/long `MOVE`;
- coherent tag-guard failure;
- collection-epoch survival for immutable strings;
- artifact retention and explicit release;
- JIT-on and `-joff` execution.

## Next table boundary

The implemented first subset is frozen in `LUA55_OPCODE_13_14_17_18_SPECIALIZATION.md`. Next table work can add
constant-sourced writes or the general `GETTABLE`/`SETTABLE` families. Table-valued slots, collector traversal,
metamethod execution, and resizing remain explicit prerequisites rather than hidden fallbacks.
