# Lua 5.5 opcodes 56–67: comparisons, tests, and the owned JMP

Status: frozen matrix; implementation pending.

## Scope

```text
EQ      R[A] == R[B]            (raw; __eq only via metatables, rejected)
LT      R[A] <  R[B]            (raw; __lt rejected)
LE      R[A] <= R[B]            (raw; __le rejected)
EQK     R[A] == K[Bx]           (raw constant equality; no __eq)
EQI     R[A] == sB              (integer immediate)
LTI     R[A] <  sB              (integer immediate)
LEI     R[A] <= sB              (integer immediate)
GTI     R[A] >  sB              (integer immediate, flipped __lt)
GEI     R[A] >= sB              (integer immediate, flipped __le)
TEST    truthy(R[A])
TESTSET truthy(R[B]) ? R[A] = R[B]
JMP     sJ relative jump (owned by its preceding test/comparison)
```

Every comparison/test in this range is immediately followed by a `JMP` whose
relative offset is static. The comparison occurrence **owns** the JMP: a
taken branch is a terminal native exit that stores the exact target PC
(`target = jmp_pc + sJ + 1`) and returns; the not-taken path falls through to
the instruction after the JMP. There is no internal native control graph in
this batch — branches exit to the host at the exact PC, matching the
frame-coherence rule that a residual stops at its exact return PC.

## Value semantics (exact stock 5.5, from lvm.c)

`cond` is the primitive result; the accept bit `k` is static per instruction.
The branch is taken iff `cond == k`.

### EQ / EQK (luaV_equalobj / luaV_rawequalobj, primitive subset)

| left tag | right tag | cond |
|---|---|---|
| nil/false/true | same tag | 1 |
| int | int | `a == b` |
| float | float | `a == b` (raw double) |
| int | float | `flt_to_int(f, F2Ieq) && i == f` |
| float | int | symmetric |
| short/long str | short/long str | byte equality (any variant mix) |
| any different supported tags | any different | 0 (stock returns false; metamethods only via tables, rejected) |

`F2Ieq`: float is integral, in `[-2^63, 2^63]`, and `(double)(int64_t)f == f`.

### LT / LE (LTnum / LEnum, exact)

| pair | cond |
|---|---|
| int, int | `a < b` / `a <= b` |
| float, float | `a < b` / `a <= b` (raw double) |
| int, float | `LTintfloat` / `LEintfloat` |
| float, int | `LTfloatint` / `LEfloatint` |
| str, str | byte lexicographic |
| other | reject (metamethod) |

`LTintfloat(i, f)`: if `i` fits exactly as a float (`[-2^52, 2^52]`) compare
as doubles; else `i < ceil(f)` via `F2Iceil`, or `f > 0` when the conversion
fails. `LEintfloat`: `i <= floor(f)` via `F2Ifloor`, or `f > 0`.
`LTfloatint`: `floor(f) < i`, or `f < 0`. `LEfloatint`: `ceil(f) <= i`, or
`f < 0`. NaN compares false in every case.

### EQI / LTI / LEI / GTI / GEI (op_orderI)

| register tag | cond |
|---|---|
| int | `i op sB` |
| float | `f op (double)sB` (raw double) |
| other | reject (metamethod, flipped for GTI/GEI) |

### TEST / TESTSET

`truthy(x) = not (nil or false)`. `TEST`: cond = truthy(R[A]).
`TESTSET`: if truthy(R[B]) != k the JMP is skipped; otherwise R[A] = R[B]
(copy) and the JMP is taken. The copy happens only on the taken branch and
before the exit store (frame coherence).

## Quotation identity

```text
Q(opcode, variant) with variant = (leaf << 1) | k
```

Per-opcode leaf numbering: EQ 12 leaves (the 11 pairs plus one
"different supported tags" leaf with cond=0), LT/LE 8, EQK 11,
EQI/LTI/LEI/GTI/GEI 2 each, TEST/TESTSET 1 each. `k` is a static accept bit, so each (leaf, k)
pair is a separate residual with a hardcoded branch — no patched accept
immediate, no ambiguous extraction.

## Residual contract

Every comparison residual:

1. guards the learned operand tags (except TEST/TESTSET, which are total);
2. computes `cond` exactly as above;
3. on `cond == k`: (TESTSET copies first) stores `resume_pc = target_pc`,
   `status = COMPLETED`, and returns;
4. otherwise falls through to the next occurrence via the standard successor.

A tag-guard failure stores `resume_pc = occurrence pc`, `status = GUARD_FAILED`
and returns; the host re-executes from the comparison PC.

## Rejections (visible)

- metatable-bearing operands (`__eq`, `__lt`, `__le`) — no metamethod leaves;
- table operands in EQ/LT/LE/EQK (identity/`__eq` contract not yet frozen);
- a comparison whose following instruction is not `JMP` (malformed);
- any immediate-comparison with a non-numeric register value.

## Projection

`project_native_path` for opcodes 57–67 consumes two instructions (comparison
plus owned JMP) and advances by 2. A standalone `JMP` (not owned) projects as
a terminal occurrence that exits at `pc + sJ + 1`.

## Validation

The differential oracle compares branch outcomes (taken target PC vs
fallthrough) for all leaf pairs against stock Lua 5.5, including the exact
int/float boundary cases (`2^63 - 1`, `2^63`, `-2^63`, NaN, `2^52` edges,
long/short string equality, embedded-NUL strings).
