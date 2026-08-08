# LUA55 Opcodes 11/12/15/16/19/20 Specialization: generic tables

Frozen matrix for generic table access, extending the fixed-key table
batch (13/14/17/18). Metatable-absent fast path with identity + shape +
**runtime-key guards**; metatables (`__index`/`__newindex`/`__call`/`__len`)
are a visible rejection boundary (host runs the metamethod path).

## Formats

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 12 | `GETTABLE` | A B C | `R[A] := R[B][R[C]]` — runtime key in a register |
| 16 | `SETTABLE` | A B C | `R[A][R[B]] := R[C]` — runtime key |
| 15 | `GETTABUP` | A B C | `R[A] := UpValue[B][K[C]]` — constant key |
| 11 | `SETTABUP` | A B C | `UpValue[A][K[B]] := R[C]` — constant key |
| 20 | `SELF` | A B C | `R[A+1] := R[B]; R[A] := R[B][K[C]]` |
| 19 | `NEWTABLE` | A vB vC k | `R[A] := {}` — vB = log2(hash)+1, vC = array; next instruction is always `EXTRAARG` |

## Runtime keys (GETTABLE/SETTABLE)

The key is a register value, so the learner records it: the key's tag goes
into `slot->expected_state` and the key value (int64 or interned-string
reference) into the new `slot->key_bits` field of `Lua55RecordingSlotV1`.
Install patches both into the residual, which **re-guards the key every
run** (exact integer equality / string reference identity) before reading
or writing the recorded cell. A changed key is a guard exit to the opcode
pc. Integer keys hit the fixed array part (`1 ≤ k ≤ array_capacity`);
out-of-range writes reject (host resizes); string keys resolve through the
field part (fixed linear storage, interned keys).

## Upvalue receivers (GETTABUP/SETTABUP)

The receiver is read from the upvalue cell (open slot or closed value);
the residual guards the cell's state and generation (patched from the
slot) plus the table identity. The key is a **constant** (patched), so no
runtime key guard is needed — the recorded cell pointer is the whole
effect. The projection interns string constants through the guest heap.

## SELF

Copies the receiver into `R[A+1]` and reads the constant-key field into
`R[A]` under the same table + cell guards.

## NEWTABLE — native bump allocation

The heap's `Lua55GuestHeapV1` gains a native bump region
(`table_region/table_region_end/table_next`, mmap'd at heap creation). The
stencil's `new_table` bumps a table struct plus its array/field storage
inline, zero-initialized, with a **minimum capacity of 1** so `{}`
followed by writes works. The learner and the residual each bump a
**fresh table per run** (non-moving, stable references); the
`EXTRAARG`-extended array size is folded by the projection. Subsequent ops
in the same path guard the fresh table's reference, so a re-entered path
guard-fails once and the driver re-learns (one bounded re-execution).

## Variants (quote = `opcode << 16 | variant`)

| opcode | variants | residual family |
|--------|----------|------------------|
| 12 GETTABLE | 1–7 int hits, 8 int miss, 9–15 str hits, 16 str miss | `gettable_i_*`, `gettable_s_*` |
| 16 SETTABLE | 1–7 int, 9–15 str | `settable_i_*`, `settable_s_*` |
| 15 GETTABUP | 1–8, 9–16 | `gettabup_i_*`, `gettabup_s_*` |
| 11 SETTABUP | 1–7, 9–15 | `settabup_i_*`, `settabup_s_*` |
| 20 SELF | 9–15 hits, 16 miss | `self_*` |
| 19 NEWTABLE | 1 | `newtable` |

## Learner/residual summary

- 6 learners, 69 residuals (bank 3,995 / 11,125 bytes)
- Key guards: recorded tag + value re-checked each run; upvalue
  state/generation guarded for the TABUP ops; table identity + storage
  generation + collection epoch + metatable absence guarded throughout.
