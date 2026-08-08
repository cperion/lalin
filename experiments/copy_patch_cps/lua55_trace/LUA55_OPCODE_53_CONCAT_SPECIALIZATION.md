# LUA55 Opcode 53 Specialization: CONCAT

Frozen matrix for string concatenation.

## Format

`CONCAT A B` — `R[A] := R[A] .. R[A+1] .. ... .. R[A+B-1]` (B operands,
left to right, result overwriting `R[A]`).

## Closed subset

- Every operand must be a string (short or long). **Number operands
  reject** to the host — the `%.14g` tostring conversion and the
  `__concat` metamethod path are the visible boundary (future work:
  inline `lua_number2str`).
- The result is a **fresh guest-heap string** bumped from the native
  region: `Lua55GuestStringV1` with the bytes inline, short (≤ 40 =
  `LUA_MINSTR`) or long by total length. Interning dedup is skipped (the
  closed subset compares strings by content); each run materializes a
  distinct object.

## Learner

Checks all B operands are strings, sums the lengths, bumps the result,
copies the bytes in order, sets the target tag (short/long) + reference,
and records one slot.

## Residual

Re-checks the operands and **recomputes the full concatenation** from the
current values each run — a fresh string per run, no recorded
per-element assumptions (self-consistent, like SETLIST).

## Learner/residual summary

- 1 learner (`lua55_learn_concat`), 1 residual (`lua55_residual_concat`)
- Holes: target register, base register A, count B, quote base, resume pc.
