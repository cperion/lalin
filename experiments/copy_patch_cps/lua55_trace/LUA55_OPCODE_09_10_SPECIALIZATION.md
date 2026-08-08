# Lua 5.5 Opcodes 9–10: Frozen Upvalue Specialization Matrix

Status: semantic freeze and scalar native implementation.

Scope: `GETUPVAL` and `SETUPVAL`.

## Exact cell ownership

An upvalue is one stable cell with one of two physical states:

```text
OpenUpvalueCell(open_slot, generation)
ClosedUpvalueCell(closed_value, generation)
```

The implemented C representation is:

```text
Lua55UpvalueCellV1
├── open_slot       pointer into the exact guest value frame
├── closed_value    cell-owned value storage
├── state           Open or Closed
└── generation      changes when location ownership changes
```

The frame owner retains the value array and cell array across every native call. An open pointer therefore cannot
outlive its value owner. Closing copies the current value into the cell, clears the open pointer, changes the state,
and advances the generation.

This is guest-owned C memory. It does not contain a LuaJIT GC pointer.

## Recording slot

Both opcodes record:

```text
UpvalueRecordingSlot
├── selected residual quotation
├── expected scalar value tag
├── expected Open or Closed state
└── expected cell generation
```

The opcode occurrence already owns its static upvalue index, source or destination register, and exact resume PC.
Those fields are patch payloads, not learned facts.

## GETUPVAL matrix

`GETUPVAL A B` reads cell `B` into register `A`.

| State | Nil | False | True | Integer | Float |
|---|---:|---:|---:|---:|---:|
| Open | `Q(9,1)` | `Q(9,2)` | `Q(9,3)` | `Q(9,4)` | `Q(9,5)` |
| Closed | `Q(9,6)` | `Q(9,7)` | `Q(9,8)` | `Q(9,9)` | `Q(9,10)` |

Every residual quotation guards:

1. the expected cell state;
2. the expected cell generation;
3. the expected current upvalue value tag.

All guards execute before modifying the destination register. Failure leaves the frame coherent and resumes at the
exact `GETUPVAL` PC.

The learner executes the real first-read semantics, records the state, generation, and value tag, then copies the
value into the destination.

## SETUPVAL matrix

`SETUPVAL A B` writes register `A` into cell `B`.

| State | Nil | False | True | Integer | Float |
|---|---:|---:|---:|---:|---:|
| Open | `Q(10,1)` | `Q(10,2)` | `Q(10,3)` | `Q(10,4)` | `Q(10,5)` |
| Closed | `Q(10,6)` | `Q(10,7)` | `Q(10,8)` | `Q(10,9)` | `Q(10,10)` |

Every residual quotation guards:

1. the expected cell state;
2. the expected cell generation;
3. the expected source-register tag.

The guard runs before changing either open stack storage or closed cell storage. Scalar writes require no GC barrier.
Collectable writes remain explicit rejected alternatives until the guest heap supplies an exact barrier contract.

## State transitions

Open and closed are not interchangeable fast paths. If an installed residual expects an open cell and the cell closes,
its state or generation guard exits at the opcode PC. The installed artifact remains immutable and valid for future
activations that satisfy its original contract.

A cell must never change its open target without advancing its generation. Stack movement in a future growable guest
stack must update the cell through its owner and advance or otherwise preserve the exact generation contract.

## Native implementation

Files:

```text
opcode_value_v1.h
opcode_09_10_stencils.c
build_opcode_09_10_bank.lua
opcode_09_10_test.lua
```

The shared value header extends recording slots with state and generation and adds the exact upvalue projection to the
activation frame. The opcode extension contains:

```text
2 learner stencils       314 bytes total
20 residual stencils   1,662 bytes total
```

Learner successor relocations can occur before internal rejection blocks. The extractor therefore preserves the full
function section and records its exact successor relocation. The linker patches that direct successor when it appends
the next concrete opcode. No runtime opcode dispatch is introduced.

## Validation

Tests cover:

- all five scalar tags for open `GETUPVAL`;
- all five scalar tags for closed `GETUPVAL`;
- all five scalar tags for open `SETUPVAL`;
- all five scalar tags for closed `SETUPVAL`;
- exact quote, state, tag, and generation recording;
- state-transition guard failure;
- generation guard failure;
- source-tag guard failure before a write;
- invalid state and unsupported tag rejection;
- mixed `LOADI → SETUPVAL → GETUPVAL` linking across both banks;
- immutable RX learner and residual ownership;
- one recording generation;
- no recurring allocation after warmup;
- JIT-on and `-joff` execution.

## Decoded-prototype checkpoint

`opcode_00_10_projection.lua` attaches projection methods to the concrete opcode and constant classes created by the
Lua 5.5 decoder. A checked-in official Lua 5.5.0 chunk now drives a real 24-instruction opcode 0–10 path through native
learning and residual installation. Register indexes, upvalue indexes, scalar constants, PCs, `LOADKX` companions,
`LFALSESKIP`, malformed companions, unsupported constants, and unsupported opcodes are validated without an
operational trace IR.

## Next boundary

Before opcodes 11–20, the experiment must freeze guest collectable ownership: stable references, roots retained by RX
artifacts and activations, table storage generations, metatable identity, and write-barrier exits. Table stencils must
not be written against raw LuaJIT GC pointers.
