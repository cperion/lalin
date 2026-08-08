# LUA55 Opcodes 80/81/83 Specialization: VARARG, GETVARG, VARARGPREP

Frozen matrix for vararg functions.

## Formats

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 80 | `VARARG` | A B C k | `R[A..A+C-2] := varargs` (`C == 0` → all) |
| 81 | `GETVARG` | A B C | `R[A] := R[B][R[C]]` — vararg at index `R[C]`, or the count for "n" |
| 83 | `VARARGPREP` | — | adjust varargs |

## Host-arranged frame

`VARARGPREP` is a **host-setup boundary**: the plan builder skips it and
the host arranges the callee frame before its first block — the extra
args live in `R[numparams .. numparams+count-1]` and the new
`Lua55LearnFrameV1.vararg_count` field carries the count. (The stock
tuple-table / hidden-args distinction collapses to this one model.)

## VARARG (80)

The learner/residual copy `min(C-1, vararg_count)` values from
`R[numparams..]` into `R[A..]` with a **backward copy** (destination may
overlap the source registers). No recorded per-element assumptions — the
copy recomputes from the current frame each run.

## GETVARG (81)

`R[A]` := the vararg at the runtime index `R[C]`:
- integer `n`, `1 ≤ n ≤ count` → `R[numparams + n - 1]`;
- integer out of range → nil;
- the string "n" (checked by content: length 1, byte 'n') → the count;
- anything else → nil.

Recomputes from the current frame each run.

## Learner/residual summary

- 2 learners (`lua55_learn_vararg`, `lua55_learn_getvarg`), 2 residuals
- Holes: target register, key register (GETVARG), numparams, wanted
  (VARARG: `C-1` or all), base register, quote base, resume pc.
