# Lua 5.5 Opcode Implementation Status

Audited against `.vendor/Lua/lopcodes.h` and `.vendor/Lua/lvm.c`.
Updated after quickening removal.

## Legend

| Status | Meaning |
|--------|---------|
| `implemented` | Primary path works; tested |
| `partial` | Handler exists but has known gaps (metamethod fallbacks, GC, etc.) |
| `stub` | Handler exists, always errors/jumps to runtime error |
| `untested` | Handler exists, no focused opcode-semantics test |

## Status Matrix

| # | Opcode | Args | Handler | Status | Tests | Gaps |
|---|--------|------|---------|--------|-------|------|
| 0 | MOVE | A B | `op_move` in op_handlers.lua:312 | implemented | e2e (implicit) | copies Value by-value |
| 1 | LOADI | A sBx | `op_loadi` in op_handlers.lua:342 | implemented | e2e | none |
| 2 | LOADF | A sBx | `op_loadf` in op_handlers.lua:351 | implemented | — | none |
| 3 | LOADK | A Bx | `op_loadk` in op_handlers.lua:321 | implemented | e2e (LOADK+RETURN) | copies Value by-value |
| 4 | LOADKX | A | `op_loadkx` in op_handlers.lua:331 | implemented | opcode_semantics | reads EXTRAARG Instr by-value |
| 5 | LOADFALSE | A | `op_loadfalse` in op_handlers.lua:360 | implemented | — | none |
| 6 | LFALSESKIP | A | `op_lfalseskip` in op_handlers.lua:378 | implemented | — | pc+2 skip |
| 7 | LOADTRUE | A | `op_loadtrue` in op_handlers.lua:369 | implemented | — | none |
| 8 | LOADNIL | A B | `op_loadnil` in op_handlers.lua:433 | implemented | opcode_semantics | copies Value by-value in loop |
| 9 | GETUPVAL | A B | `op_getupval` in op_handlers.lua:401 | implemented | — | copies Value by-value |
| 10 | SETUPVAL | A B | `op_setupval` in op_handlers.lua:412 | implemented | — | copies Value by-value |
| 11 | GETTABUP | A B C | `op_gettabup` in op_handlers.lua:628 | partial | — | table MM infra incomplete; reloads Instr for k |
| 12 | GETTABLE | A B C | `op_gettable` in op_handlers.lua:653 | partial | — | table MM infra incomplete |
| 13 | GETI | A B C | `op_geti` in op_handlers.lua:676 | partial | — | table MM infra incomplete |
| 14 | GETFIELD | A B C | `op_getfield` in op_handlers.lua:699 | partial | — | table MM infra incomplete |
| 15 | SETTABUP | A B C | `op_settabup` in op_handlers.lua:723 | partial | — | table MM infra; reloads Instr for k |
| 16 | SETTABLE | A B C | `op_settable` in op_handlers.lua:756 | partial | — | table MM infra incomplete |
| 17 | SETI | A B C | `op_setti` in op_handlers.lua:779 | partial | — | table MM infra; reloads Instr for k |
| 18 | SETFIELD | A B C | `op_setfield` in op_handlers.lua:807 | partial | — | table MM infra; reloads Instr for k |
| 19 | NEWTABLE | A vB vC k | `op_newtable` in op_handlers.lua:836 | stub | — | jumps to oom; no allocation infra |
| 20 | SELF | A B C | `op_self` in op_handlers.lua:846 | partial | — | depends on table_get infra |
| 21 | ADDI | A B sC | `op_addi` arith_handlers:225 | implemented | opcode_semantics | string-generated body |
| 22 | ADDK | A B C | `op_addk` arith_handlers:228 | implemented | opcode_semantics | string-generated body |
| 23 | SUBK | A B C | `op_subk` arith_handlers:229 | implemented | — | string-generated body |
| 24 | MULK | A B C | `op_mulk` arith_handlers:230 | implemented | — | string-generated body |
| 25 | MODK | A B C | `op_modk` arith_handlers:231 | stub | — | jump to ERR_ARITH |
| 26 | POWK | A B C | `op_powk` arith_handlers:232 | stub | — | jump to ERR_ARITH |
| 27 | DIVK | A B C | `op_divk` arith_handlers:233 | implemented | — | string-generated body |
| 28 | IDIVK | A B C | `op_idivk` arith_handlers:234 | stub | — | jump to ERR_ARITH |
| 29 | BANDK | A B C | `op_bandk` arith_handlers:240 | implemented | — | string-generated body |
| 30 | BORK | A B C | `op_bork` arith_handlers:241 | implemented | — | string-generated body |
| 31 | BXORK | A B C | `op_bxork` arith_handlers:242 | implemented | — | string-generated body |
| 32 | SHLI | A B sC | `op_shli` arith_handlers:226 | implemented | — | string-generated body; y<<x order |
| 33 | SHRI | A B sC | `op_shri` arith_handlers:227 | implemented | — | string-generated body |
| 34 | ADD | A B C | `op_add` arith_handlers:218 | implemented | — | string-generated body; followed by MMBIN |
| 35 | SUB | A B C | `op_sub` arith_handlers:219 | implemented | — | string-generated body |
| 36 | MUL | A B C | `op_mul` arith_handlers:220 | implemented | — | string-generated body |
| 37 | MOD | A B C | `op_mod` arith_handlers:221 | stub | — | jump to ERR_ARITH |
| 38 | POW | A B C | `op_pow` arith_handlers:223 | stub | — | jump to ERR_ARITH |
| 39 | DIV | A B C | `op_div` arith_handlers:224 | partial | — | float-only (no integer path) |
| 40 | IDIV | A B C | `op_idiv` arith_handlers:222 | stub | — | jump to ERR_ARITH |
| 41 | BAND | A B C | `op_band` arith_handlers:235 | implemented | — | string-generated body |
| 42 | BOR | A B C | `op_bor` arith_handlers:236 | implemented | — | string-generated body |
| 43 | BXOR | A B C | `op_bxor` arith_handlers:237 | implemented | — | string-generated body |
| 44 | SHL | A B C | `op_shl` arith_handlers:238 | implemented | — | string-generated body |
| 45 | SHR | A B C | `op_shr` arith_handlers:239 | implemented | — | string-generated body |
| 46 | MMBIN | A B C | `op_mmbin` in op_handlers.lua:263 | stub | — | jump to ERR_RUNTIME |
| 47 | MMBINI | A sB C k | `op_mmbini` in op_handlers.lua:278 | stub | — | jump to ERR_RUNTIME |
| 48 | MMBINK | A B C k | `op_mmbink` in op_handlers.lua:293 | stub | — | jump to ERR_RUNTIME |
| 49 | UNM | A B | `op_unm` arith_handlers:243 | implemented | — | string-generated body |
| 50 | BNOT | A B | `op_bnot` arith_handlers:244 | implemented | — | string-generated body |
| 51 | NOT | A B | `op_not` in op_handlers.lua:387 | implemented | — | copies Value by-value |
| 52 | LEN | A B | `op_len` in op_handlers.lua:1081 | stub | — | jump to ERR_RUNTIME |
| 53 | CONCAT | A B | `op_concat` in op_handlers.lua:1090 | stub | — | jump to ERR_RUNTIME |
| 54 | CLOSE | A | `op_close` in op_handlers.lua:498 | partial | — | depends on close_upvalues infra |
| 55 | TBC | A | `op_tbc` in op_handlers.lua:517 | partial | — | sets tbc_head; close chain not yet wired |
| 56 | JMP | sJ | `op_jmp` in op_handlers.lua:449 | implemented | — | none |
| 57 | EQ | A B k | `op_eq` in op_handlers.lua:893 | partial | — | call_mm stub; uses a to invert |
| 58 | LT | A B k | `op_lt` in op_handlers.lua:923 | partial | — | call_mm stub |
| 59 | LE | A B k | `op_le` in op_handlers.lua:953 | partial | — | call_mm stub |
| 60 | EQK | A B k | `op_eqk` in op_handlers.lua:984 | partial | — | reloads Instr for k |
| 61 | EQI | A sB k | `op_eqi` in op_handlers.lua:1063 | partial | — | reloads Instr for k; generated via make_cmp_imm_handler |
| 62 | LTI | A sB k | `op_lti` in op_handlers.lua:1064 | partial | — | reloads Instr for k |
| 63 | LEI | A sB k | `op_lei` in op_handlers.lua:1065 | partial | — | reloads Instr for k |
| 64 | GTI | A sB k | `op_gti` in op_handlers.lua:1066 | partial | — | reloads Instr for k |
| 65 | GEI | A sB k | `op_gei` in op_handlers.lua:1067 | partial | — | reloads Instr for k |
| 66 | TEST | A k | `op_test` in op_handlers.lua:460 | implemented | — | uses (c==0) for k inversion |
| 67 | TESTSET | A B k | `op_testset` in op_handlers.lua:478 | implemented | — | copies Value by-value |
| 68 | CALL | A B C | `op_call` in op_handlers.lua:1111 | partial | — | native-call path not wired; prepare_call+adjust_results infra |
| 69 | TAILCALL | A B C k | `op_tailcall` in op_handlers.lua:1174 | partial | — | full sem not yet implemented |
| 70 | RETURN | A B C k | `op_return` in op_handlers.lua:1222 | implemented | e2e (LOADK+RETURN) | reloads Instr for k; tbc_close_chain incomplete |
| 71 | RETURN0 | — | `op_return0` in op_handlers.lua:1277 | implemented | e2e (implicit) | reloads Instr for k |
| 72 | RETURN1 | A | `op_return1` in op_handlers.lua:1321 | implemented | opcode_semantics | reloads Instr for k |
| 73 | FORLOOP | A Bx | `op_forloop` in op_handlers.lua:1370 | implemented | — | copies Value by-value for idx/limit/step |
| 74 | FORPREP | A Bx | `op_forprep` in op_handlers.lua:1411 | implemented | — | copies Value by-value |
| 75 | TFORPREP | A Bx | `op_tforprep` in op_handlers.lua:1439 | implemented | — | minimal (just pc+=sBx) |
| 76 | TFORCALL | A C | `op_tforcall` in op_handlers.lua:1449 | stub | — | jump to ERR_RUNTIME |
| 77 | TFORLOOP | A Bx | `op_tforloop` in op_handlers.lua:1458 | implemented | — | copies Value by-value |
| 78 | SETLIST | A vB vC k | `op_setlist` in op_handlers.lua:870 | stub | — | jump to oom |
| 79 | CLOSURE | A Bx | `op_closure` in op_handlers.lua:1478 | stub | — | jump to ERR_RUNTIME |
| 80 | VARARG | A B C k | `op_vararg` in op_handlers.lua:1489 | stub | — | jump to ERR_RUNTIME |
| 81 | GETVARG | A B C | `op_getvarg` in op_handlers.lua:1500 | stub | — | jump to ERR_RUNTIME |
| 82 | ERRNNIL | A Bx | `op_errnnil` in op_handlers.lua:1511 | implemented | — | copies Value by-value |
| 83 | VARARGPREP | — | `op_varargprep` in op_handlers.lua:1526 | implemented | — | minimal (just advances pc) |
| 84 | EXTRAARG | Ax | `op_extraarg` in op_handlers.lua:424 | implemented | opcode_semantics (via LOADKX) | nop |

## Summary

| Status | Count |
|--------|-------|
| implemented | 47 |
| partial | 19 |
| stub | 19 |
| untested | 0 |

## Known Architectural Issues (across all opcodes)

All handlers that are string-generated use Lua template functions (`_body_int`, `_body_both`, `_body_float`, `_body_imm_both`, `_body_imm_int`, `_body_k_both`, `_body_k_int`, `_body_unary`, `_body_unary_int`). See ARCHITECTURE_FIX_PLAN.md §3.

All handlers copy `Value` products by-value from the stack, which bakes avoidable memory traffic into the hot path. See ARCHITECTURE_FIX_PLAN.md §2.

Dispatch copies the 20-byte `Instr` product by-value. See ARCHITECTURE_FIX_PLAN.md §2.2.

The following handlers reload `Instr` from `cl.proto.code[pc]` to read the `k` field:
- `op_return` (line 1237)
- `op_return0` (line 1282)
- `op_return1` (line 1327)
- `op_eqk` (lines 991, 1001, 1009)
- `op_settabup` (line 731, via `resolve_rk` for k)
- `op_setti` (line 784, via `resolve_rk` for k)
- `op_setfield` (line 812, via `resolve_rk` for k)
- All `make_cmp_imm_handler` handlers (EQI, LTI, LEI, GTI, GEI) at line 1044

## Total

**85 opcodes** (0–84 inclusive). Quickened pseudo-opcodes (LOADK_FAST=100, MOVE_FAST=101, ADD_NUM=102) **removed** per ARCHITECTURE_FIX_PLAN.md §4.
