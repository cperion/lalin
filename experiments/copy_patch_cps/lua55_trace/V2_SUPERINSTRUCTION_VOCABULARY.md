# Lua 5.5 V2 Superinstruction Vocabulary (evidence-based)

Status: implemented + validated. All eight evidence-backed families are
projected as exact shapes, learn per-occurrence products in the separate
learning image, and publish one exact residual family per occurrence. The
numeric-for store-cycle (FORPREP + SETTABLE-const + FORLOOP) covers the
sieve inner loop and array-initializer loops. The five/six-leaf dictionary
accumulation (GETFIELD GETFIELD GETTABLE [GETFIELD] ADD SETTABLE) covers
totals[key] = totals[key] + value with the key read once.
Gates: 64-shape numeric-for matrix (ADDI + ADD accumulators), field/table
RMW loops, store cycles (six const kinds x both signs), call alternatives,
accumulation (key x acc x src kinds x register/field source), deliberate
mismatch rejections, JIT/-joff differential byte-identical to stock, no
call/ret in the super/call sections. Whole programs (pinned): sieve ~1.9x
stock (was 0.87x), orders ~1.25x (was 0.91x), particle ~1.5x,
bytecode shapes."* The vocabulary is chosen from the fixed Lua 5.5 compiler's
emission patterns across a **diverse corpus** (1,661 real Lua files from the
repository), NOT from any single workload, so it cannot overfit the
benchmarks.

## Methodology

`lua55_superinstruction_profiler.lua`:
- compiles every corpus file with the stock `luac`,
- walks every proto recursively,
- counts opcode sequences, loop bodies (via FORLOOP's 17-bit Bx back
  distance), read-modify-write windows, and call-argument assembly,
- ranks by **universality** (files containing the pattern) and **hotness**
  (occurrences inside numeric-for bodies).

A pattern is a fusion candidate only if it is (a) language-level (the
compiler emits it for a common source construct), (b) present in hundreds of
files, and (c) hot (inside loops) or a high-traffic boundary (calls).

## Evidence (1,661 files)

### Universal single shapes
| opcode | files | count |
|---|---|---|
| GETTABUP | 1635 | 115165 |
| GETFIELD | 1585 | 164908 |
| CALL | 1595 | 155346 |
| SETFIELD | 1510 | 55219 |
| MOVE | 1501 | 130509 |
| NEWTABLE | 1495 | 38734 |
| CONCAT | 1189 | 8122 |
| TEST/EQK/EQ | 1008/985/958 | 22898/17838/12294 |

### Numeric-for bodies (888 files, 6,586 loops)
| opcode | files | count |
|---|---|---|
| GETFIELD | 711 | 18244 |
| CALL | 787 | 12093 |
| MOVE | 720 | 11974 |
| GETTABLE | 738 | 8504 |
| SETTABLE | 613 | 4893 |
| ADDI (+owned MMBINI) | 533 | 3548 |
| GETTABUP | 605 | 5969 |
| LEN / EQ / TEST | 421/413/317 | 3055/2112/2565 |

### Call sites (opcode immediately before CALL)
GETTABUP (1612 files), LOADK (1608), MOVE (1485), GETFIELD (1467),
SELF (1006), GETUPVAL (967).

### Read-modify-write windows (read → write within 6 ops)
| pattern | files | count |
|---|---|---|
| GETFIELD → SETFIELD | 1245 | 17305 |
| GETTABUP → SETFIELD | 1033 | 4437 |
| GETFIELD → SETTABLE | 474 | 9276 |
| GETTABLE → SETTABLE | 397 | 2180 |
| GETUPVAL → SETUPVAL | 131 | 590 |

### Already fused
Compare + owned JMP (TEST/EQK/EQ/LT/LE + JMP): the V2 runner already
patches the compare's taken edge directly to the JMP's target; the JMP
instruction never executes. This is a closed superinstruction.

## Ranked fusion vocabulary

Ranking = universality × hotness × per-fusion savings (frame round-trips
eliminated; register residency across a cycle).

### 1. Numeric-for loop-cycle (highest value)
`FORPREP … [bounded register-only body] … FORLOOP` (888 files, 6,586 loops).
The induction variable and step are register-resident across the whole loop;
the body's accumulator arithmetic (ADDI/ADD/MULK on a loop-carried register)
runs in native registers. Frame state is written once at loop exit. This is
the projected generalization of the original `Add+ForLoop` proof (0.218
ns/iter vs 1.77 ns/iter for the current scalar V2 chain — an 8x gap).
Exact projections (closed, finite):
- `forprep_int_pos|neg + ADDI(accumulator) + forloop_int`
- `forprep_int_pos|neg + ADD(accumulator, index) + forloop_int`
- `forprep_int_pos|neg + MULK + ADD(accumulator) + forloop_int`
- float-protocol analogues.
Guards: the exact protocol/sign (learned), the exact body opcode set, no
call/table/control ops in the body.

### 2. Global call
`GETTABUP + LOADK/MOVE + CALL` (1,443/1,400 files). The callee fetch from the
env upvalue + constant/local argument placement + call boundary in one leaf.
The callee kind (native closure / host builtin) is learned; the arg registers
are placed once instead of frame-written then frame-read.

### 3. Method call
`SELF + CALL` (1,006 files). The method field fetch (exact string key) +
receiver copy + call boundary in one leaf.

### 4. Field read-modify-write
`GETFIELD + ADDI/ADD/SUB + SETFIELD` on the same table register (1,245
files). `t.x = t.x + k` in one leaf: read the field, apply the arithmetic,
write back — no intermediate frame round-trip.

### 5. Table read-modify-write
`GETTABLE/GETI + arith + SETTABLE/SETI` on the same key (397/26 files).
`t[k] = f(t[k])` — the dynamic-key analogue of (4).

### Deferred (cold or low value)
- `NEWTABLE + EXTRAARG + SETFIELD/SETLIST` table literals: executed once,
  not hot. Keep the exact per-op leaves.
- `LOADK + CALL` without a preceding GETTABUP: the callee is a local closure;
  the MOVE/CALL fusion is marginal.

## Fusion contract (each superinstruction)

1. **Exact projection product**: a named shape with the exact opcode set,
   register facts, const facts, protocol/sign facts, and learned callee
   facts. Selected only when the exact shape holds (guards validate it).
2. **Register residency**: the leaf holds loop-carried values (count, index,
   step, accumulator) in native registers; frame state is coherent at exit.
3. **No generic machinery**: no trace IR, SSA, scheduler, or deoptimizer. The
   bytecode is the plan; the superinstruction is a closed semantic leaf.
4. **Differential oracles**: every fused leaf is checked byte-identical
   against stock Lua 5.5 on a corpus of diverse programs (not just the
   benchmarks), under JIT and `-joff`.
5. **Guard mismatch**: a shape that no longer holds publishes the typed
   `SpecializationMismatchV2`; the ordinary per-op leaves remain correct.
6. **Measurement**: cold construction vs retained execution reported
   separately; a fusion is retained only if it beats the scalar chain by a
   measured margin on the corpus distribution, not on one benchmark.

## Implementation order

1. Numeric-for loop-cycle (highest value, best understood: the original
   proof).
2. Global call `GETTABUP + LOADK/MOVE + CALL`.
3. Method call `SELF + CALL`.
4. Field RMW `GETFIELD + arith + SETFIELD`.
5. Table RMW `GETTABLE/GETI + arith + SETTABLE/SETI`.

Each step lands with: the projection product, the fused leaf(s), guards,
differential corpus tests, JIT/-joff gates, the ABI gate, and cold/retained
measurements. The inventory's exact-residual gates remain the correctness
floor; superinstructions add performance only where the corpus evidence
justifies them.
