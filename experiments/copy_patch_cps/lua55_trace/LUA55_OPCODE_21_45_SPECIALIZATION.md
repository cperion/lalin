# Lua 5.5 opcodes 21–45: arithmetic, bitwise, and shifts (POW deferred)

Status: frozen matrix; implementation in progress.

## Scope

The primitive arithmetic family and its owned companions:

```text
ADDI(21)  ADDK(22) SUBK(23) MULK(24) MODK(25) DIVK(27) IDIVK(28)
BANDK(29) BORK(30) BXORK(31) SHLI(32) SHRI(33)
ADD(34) SUB(35) MUL(36) MOD(37) DIV(39) IDIV(40)
BAND(41) BOR(42) BXOR(43) SHL(44) SHR(45)
```

Each primitive owns its companion (`MMBIN` for register-register,
`MMBINI` for register-immediate, `MMBINK` for register-constant). A numeric
success skips the companion (the projection advances by 2). A non-numeric
operand is the companion path: metamethod territory, rejected at learn time;
a changed tag is a runtime guard exit to the primitive PC.

**POW(38) and POWK(26) are deferred**: they require libm `pow`, an external
symbol; a named rejection leaf until external-symbol patching exists.

## Exact semantics (from lvm.c)

### ADD/SUB/MUL (and ADDI/ADDK/SUBK/MULK)

| pair | result |
|---|---|
| int op int | `intop` unsigned wrap (C `(uint64)a op (uint64)b` reinterpreted) |
| any numeric with a float | double `+ - *` |

`ADDI`: immediate `sC`; int operand → `intop(i, sC)`, float operand →
`nb + (double)sC`. `ADDK`-family: constant is a number; register pair rules.

### DIV (and DIVK)

Both operands numeric → double division (Inf/NaN propagate, no error).
Result is always float.

### IDIV / MOD (and IDIVK / MODK)

Integer pair:

```text
IDIV: n == 0  -> error "attempt to divide by zero" (host exit at primitive PC)
      n == -1 -> 0 - m  (avoid 0x8000..//-1 overflow)
      else    -> floor division (C division, adjust when (m^n)<0 and m%n!=0)
MOD : n == 0  -> error "attempt to perform 'n%0'" (host exit at primitive PC)
      n == -1 -> 0
      else    -> floor modulo (adjust when r!=0 and (r^n)<0)
```

Numeric pair with a float: `IDIV` → `floor(m / n)`; `MOD` → `fmod(m, n)`
(no zero error; `fmod(x, 0)` is NaN).

The integer zero-divisor exits are the only error paths in this batch: the
residual stores `resume_pc = primitive pc`, `status = COMPLETED`, and
returns; the host re-executes and raises.

### BAND / BOR / BXOR (and K variants)

Both operands must convert via `tointegerns` (`F2Ieq`: int direct, float
only if integral and in range). Result is integer. A non-convertible float
or non-number is the companion path (rejected).

### SHL / SHR / SHLI / SHRI

```c
luaV_shiftl(x, y):  y < 0      -> (y <= -64) ? 0 : x >> -y
                    y >= 64    -> 0
                    else       -> x << y
```

`SHL`: `shiftl(R[B], R[C])`. `SHR`: `shiftl(R[B], -R[C])`.
`SHLI`: `shiftl(sC, R[B])` (immediate is the left operand). `SHRI`:
`shiftl(R[B], -sC)`. Operands coerce via `F2Ieq`; non-coercible → companion.

## Quotation identity

```text
Q(opcode, variant), variant = leaf (no accept bit in this family)
```

Register-register and register-constant leaves: `ii`, `if`, `fi`, `ff`
(register tag pair; for K variants the second tag is the constant tag).
Register-immediate leaves: `int`, `flt`. One learner per opcode selects the
leaf by runtime tags and records `base | leaf`.

## Residual contract

1. guard the learned operand tags (and constant tag for K variants);
2. integer-zero-divisor check for MOD/IDIV integer leaves → host exit at the
   primitive PC (status COMPLETED, no state change);
3. compute the exact result into the target register;
4. fall through to the occurrence after the owned companion.

A tag-guard failure stores `resume_pc = primitive pc`, `status = GUARD_FAILED`;
the host re-executes the primitive, which falls into the companion path.

## Projection

Opcodes 21–45 (except 26/38) consume two instructions: the primitive and its
owned companion; the projection advances by 2 on success. The companion's
opcode class must match the primitive form (`MMBIN`/`MMBINI`/`MMBINK`); a
mismatch or missing companion is a malformed rejection.

## Validation

A differential oracle compares the native result register for every leaf
against stock Lua 5.5 over a numeric matrix: int wrap edges (`minint`,
`maxint`), mixed int/float, `±2.5`, `1e300`, `0.0`, `-0.0`, `1/3`, bitwise
integral-float coercion edges (`2^53+1`, `2.5`), shift counts `-1, 0, 1, 63,
64, 65`, and MOD/IDIV zero and `-1` divisors.
