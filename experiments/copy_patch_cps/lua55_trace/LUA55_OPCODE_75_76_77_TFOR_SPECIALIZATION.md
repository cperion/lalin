# LUA55 Opcodes 75–77 Specialization: generic for

Frozen matrix for the iterator protocol.

## Formats

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 75 | `TFORPREP` | A Bx | swap closing/control; jump to the TFORCALL (first iteration) |
| 76 | `TFORCALL` | A C | `f(s, var)` — iterator dispatch, C results |
| 77 | `TFORLOOP` | A Bx | control non-nil → back to the body; else exit |

## Register layout (R[A..A+4])

R[A] = iterator f, R[A+1] = state s, R[A+2] = closing, R[A+3] = control
var, R[A+4] = value. `TFORPREP` swaps R[A+2]/R[A+3] (the explist's
initial var and closing); a non-nil closing rejects (`<close>`/TBC
contract — future work).

## TFORPREP (75)

Swaps the closing/control registers (recompute each run), rejects a
non-nil closing, and is a **terminal**: `resume_pc = pc + Bx + 1` (the
TFORCALL pc), COMPLETED — the first iteration runs the iterator
immediately, skipping the body (stock's layout).

## TFORCALL (76)

A **host iterator dispatch** boundary (like CALL): the driver invokes the
iterator's own native plan with args `s` (R[A+1]) and `var` (R[A+3]),
then copies C results into `R[A+3..A+3+C-1]` from the iterator's return
registers. The iterator closure is resolved host-side (the CLOSURE
materialized it).

## TFORLOOP (77)

Tests R[A+3] (the control var): non-nil → **terminal** to the body start
(`pc - Bx + 1`); nil → falls through (the loop exits).

## Learner/residual summary

- 2 learners (`lua55_learn_tforprep`, `lua55_learn_tforloop`), 2
  residuals; TFORCALL is host metadata (no native stencil).
- Holes: base register A, target pc (TFORCALL pc / body start), quote
  base, resume pc.
- The plan builder cuts blocks at the TFOR* boundaries and skips `CLOSE`
  (the closed subset's closings are nil); `MOVE` now carries closure
  values (variant 9).
