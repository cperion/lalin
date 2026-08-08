# LUA55 Opcodes 26/38 Specialization: POWK, POW

Frozen matrix completing the arithmetic family. Stock semantics
(`lobject.c:luaO_rawarith` `LUA_OPPOW`, "operate only on floats"):
both operands convert to double (`tonumberns`), the result is **always a
float** — even `2^3` is `8.0`, never an integer. `luai_numpow`
(`llimits.h`) has a fast path: `b == 2.0` computes `a*a` instead of
calling `pow`. Non-numeric operands take the `__pow` metamethod path
(REJECT to the host).

## Formats

| opcode | name | format | semantics |
|--------|------|--------|-----------|
| 38 | `POW` | A B C | `R[A] := R[B] ^ R[C]` |
| 26 | `POWK` | A B C | `R[A] := R[B] ^ K[C]` |

Each owns its companion (`MMBIN` / `MMBINK`); a numeric success skips it
(fallthrough at pc + 2), non-numeric is the companion path.

## External symbol: libm pow()

`pow(double, double)` is resolved once at extension time via
`ffi.cdef("double pow(double, double);")` + `ffi.C.pow`, cast to a
`uintptr_t`. The stencils call it through an **absolute-address hole**
(`POW_ADDRESS_HOLE = 0x5152535455565758`) loaded with an `asm volatile`
and invoked as an indirect call — a plain immediate in the instruction
stream, so the bank carries **no relocations to external symbols**. The
hole is patched with the resolved address in every learner and residual.
The `b == 2.0` fast path uses a bit compare against
`0x4000000000000000` (no rodata constant → no PC32 relocation).

IEEE semantics come from libm itself: `pow(NaN, 0) = 1`,
`pow(inf, 0) = 1`, `pow(-2, 0.5) = NaN`, `pow(0, -1) = inf`.

## Variants (quote = `opcode << 16 | variant`)

| opcode | variant | leaf | result |
|--------|---------|------|--------|
| 38 POW | 1 | ii | `pow(i, i)` float |
| 38 POW | 2 | if | `pow(i, f)` float |
| 38 POW | 3 | fi | `pow(f, i)` float |
| 38 POW | 4 | ff | `pow(f, f)` float |
| 26 POWK | 1 | reg int, const int | float |
| 26 POWK | 2 | reg int, const float | float |
| 26 POWK | 3 | reg float, const int | float |
| 26 POWK | 4 | reg float, const float | float |

## Learner/residual summary

- 2 learners (`lua55_learn_pow`, `lua55_learn_powk`), 8 residuals
  (`lua55_residual_pow_*`, `lua55_residual_powk_*`)
- Residuals guard the operand tags (a changed tag is a guard exit to the
  primitive PC) and re-compute the float result each run; the pow address
  and constant facts are patched at install time.
