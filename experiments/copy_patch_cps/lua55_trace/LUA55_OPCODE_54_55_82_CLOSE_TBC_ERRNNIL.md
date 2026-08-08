# LUA55 Opcodes 54/55/82 Specialization: CLOSE, TBC, ERRNNIL

Frozen matrix completing the opcode inventory's standalone semantics.

## Formats

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 54 | `CLOSE` | A | close to-be-closed variables up to R[A] |
| 55 | `TBC` | A | mark R[A] as to-be-closed |
| 82 | `ERRNNIL` | A Bx | error "global already defined" if R[A] is non-nil |

## CLOSE (54)

The closed subset never creates to-be-closed variables: `TFORPREP`
rejects non-nil closings and `TBC` rejects outright. CLOSE is therefore a
**pass-through** — it records a slot, advances, and leaves the frame
untouched (a residual recompute, so it is idempotent on re-entry).

## TBC (55)

The `<close>`/`__close` contract is a **visible rejection**: the learner
always rejects, and the host marks the value to-be-closed with the real
runtime.

## ERRNNIL (82)

The global-redefinition check: passes through when R[A] is nil; rejects
("global already defined") when non-nil. The residual recomputes (a
non-nil register on re-entry is a guard exit).

## Learner/residual summary

- 3 learners (`lua55_learn_close`, `lua55_learn_tbc`,
  `lua55_learn_errnnil`), 2 residuals (CLOSE and ERRNNIL; TBC's residual
  is never reached because the learner always rejects).
