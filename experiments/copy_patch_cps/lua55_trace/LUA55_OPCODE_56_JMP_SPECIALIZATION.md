# LUA55 Opcode 56 Specialization: JMP

Frozen matrix for the standalone unconditional jump. The comparison/test
batch (57–67) already consumes the JMP that immediately follows each
compare (`owned_jmp_target`); this batch covers every **other** JMP:
loop back-edges (`while`/`repeat`), `and`/`or` short-circuit continuations,
and forward branches.

## Format

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 56 | `JMP` | sJ | `pc += sJ` (target = pc + sJ + 1) |

Stock (`lvm.c:dojump`): with `pc` already advanced past the current
instruction, `pc += GETARG_sJ(i)`, so the 0-based target is `pc + sJ + 1`.
The projection resolves the target from the decoded instruction's `sJ`.

## Terminal semantics

A JMP occurrence is **terminal**: it records one quote, stores the exact
target pc in `frame->resume_pc`, sets `status = COMPLETED`, and returns.
The learner never calls `lua55_learn_next`; the residual never calls
`lua55_residual_next`. The chain ends and the host resumes at the stored
pc. `install` links only the recorded occurrences and appends the
fallthrough-PC terminal (unreachable, but required to seal the arena).

- No guards: JMP is unconditional.
- No state changes: the target pc is the entire effect.
- The target is patched into both the learner and the residual from the
  same hole (`0x10203040`), so re-entry runs the identical branch.

## Frame coherence

A loop back-edge returns `COMPLETED` at the loop head pc; the host
re-enters the native program, which re-runs the recorded occurrences with
the preserved frame (loop counters survive in the frame's values). The
exit branch (the compare at the loop head taking its owned JMP) returns at
the exit pc and the host leaves the loop.

## Learner/residual summary

- 1 learner (`lua55_learn_jmp`), 1 residual (`lua55_residual_jmp`)
- The learner records `quote = 56 << 16 | 1`; both store the patched target.
