# LUA55 Opcode 78 Specialization: SETLIST

Frozen matrix for table-literal filling.

## Format (ivABC layout)

`SETLIST A vB vC k` — `R[A][C+i] := R[A+i]` for `1 <= i <= B`. Unlike the
`iABC` ops, the operands use the 5.5 `ivABC` layout: **`vB` is 6 bits**
(`POS_vB = 16`), **`vC` is 10 bits** (`POS_vC = 22`). The decoded `vB`/`vC`
fields come from the undump's ivABC decode. The `k` flag folds the next
`EXTRAARG`'s high key bits: `C += Ax * (MAXARG_vC + 1) = Ax * 1024`.

## Closed subset

- `B == 0` (the "up to top" form) rejects (host adjusts to `top`).
- Any write `C+i > array_capacity` rejects (fixed storage; host resizes).
- Elements with tags beyond the closed value subset (tables, closures)
  reject.
- The table must be metatable-free (identity + heap guarded, as in the
  generic-table batch).

## Learner

Reads the table from `R[A]` (patched base register), validates the shape,
checks all B element tags, writes the elements once (array part, keys
`C+1..C+B`), bumps the string barrier, and records the table identity +
storage generation in the table recording slot.

## Residual

Guards the table identity (reference, heap, kind, storage generation,
collection epoch, metatable absence) and **re-writes the current register
values** into the array each run — no recorded element assumptions (the
write is self-consistent), so a tag change between runs simply stores the
new value. String elements bump the barrier (matching SETI).

## Learner/residual summary

- 1 learner (`lua55_learn_setlist`), 1 residual (`lua55_residual_setlist`)
- Holes: base register, count `B`, key base `C`, table identity
  (reference/storage generation/collection epoch), resume pc.
