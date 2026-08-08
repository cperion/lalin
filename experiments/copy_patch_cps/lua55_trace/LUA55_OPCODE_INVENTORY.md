# Lua 5.5.0 Opcode Inventory

Status: phase 1, authoritative semantic inventory. No residual stencil matrix is implied yet.

## Baseline

This inventory is frozen against the official Lua 5.5.0 release:

```text
https://www.lua.org/ftp/lua-5.5.0.tar.gz
SHA-256 57ccc32bbbd005cab75bcc52444052535af691789dba2b9016d5c50640d68b3d
```

The authorities are `src/lopcodes.h`, `src/lopcodes.c`, `src/lvm.c`, and the helpers called by `lvm.c`.
Lua 5.5.0 has exactly **85 opcodes**, numbered 0 through 84. The order matches
`experiments/lua55/undump55.lua`.

## Inventory rules

For each opcode we separate three things:

1. **Static operands** are known from the loaded prototype. They become register displacements, constants, successor
   offsets, or other patch holes. They are not learned facts.
2. **Finite runtime alternatives** select residual stencil quotations. Examples are integer versus float arithmetic,
   table fast hit versus metamethod exit, and taken versus untaken control.
3. **Runtime values** remain frame loads or guarded immediates. We do not create one stencil per integer, pointer,
   register number, or program counter.

Every finite semantic family must eventually contain an exact terminal rejection or side-exit leaf. Therefore
“full monomorphisation” means complete coverage of the declared finite alternatives, not every heap state.

## Quotation identity

Residual identities are opcode-local:

```text
Q(opcode, variant) = opcode << 16 | variant
```

Each concrete opcode owns its variant numbering. Independent banks can add alternatives without renumbering another
opcode or maintaining a global sequential registry. `Q(0,6)`, for example, is short-string `MOVE`.

## Instruction encodings

| Mode | Layout after the 7-bit opcode | Use |
|---|---|---|
| `iABC` | `A:8, k:1, B:8, C:8` | Most register, immediate, and constant operations |
| `ivABC` | `A:8, k:1, vB:6, vC:10` | `NEWTABLE`, `SETLIST` |
| `iABx` | `A:8, Bx:17` | Constants, closures, and loops |
| `iAsBx` | `A:8, sBx:17 excess-65535` | Integer and float immediate loads |
| `iAx` | `Ax:25` | `EXTRAARG` |
| `isJ` | `sJ:25 excess-16777215` | `JMP` |

`B`, `C`, `sB`, and `sC` share the normal eight-bit fields. `sB` and `sC` use excess 127.
`vB` and `vC` are not aliases for normal `B` and `C`; the decoder must expose both layouts.

## Structural protocols

These bytecode relationships are part of opcode semantics:

- Arithmetic and bitwise opcodes are followed by `MMBIN`, `MMBINI`, or `MMBINK`. A successful primitive operation
  skips its companion. A failed primitive operation executes the companion.
- `LOADKX` consumes the following `EXTRAARG`.
- `NEWTABLE` always consumes the following `EXTRAARG`, even when its `k` bit is clear.
- `SETLIST` consumes `EXTRAARG` when `k` is set.
- Comparisons and tests assume the following instruction is `JMP`. The pair owns the two successors.
- `TFORPREP`, `TFORCALL`, and `TFORLOOP` form one generic-for protocol.
- `CALL`, `TAILCALL`, `RETURN`, `VARARG`, and `SETLIST` can participate in the open-top protocol.
- `EXTRAARG` is structural data and must never become an independently executable residual opcode.

## Complete opcode inventory

### 0–10: movement, constants, and upvalues

| # | Opcode | Format and static action | Runtime specialization axes | Protocol role |
|---:|---|---|---|---|
| 0 | `MOVE` | `iABC A B`; copy `R[B]` to `R[A]` | Source value representation if kept unboxed | Ordinary effect |
| 1 | `LOADI` | `iAsBx A sBx`; load integer | None | Ordinary effect |
| 2 | `LOADF` | `iAsBx A sBx`; load float | None | Ordinary effect |
| 3 | `LOADK` | `iABx A Bx`; load `K[Bx]` | Constant tag is static; collectable ownership | Ordinary effect |
| 4 | `LOADKX` | `iABx A`; load constant indexed by `EXTRAARG` | Constant tag; collectable ownership | Consumes next |
| 5 | `LOADFALSE` | `iABC A`; load false | None | Ordinary effect |
| 6 | `LFALSESKIP` | `iABC A`; load false and skip next | None | Fixed control |
| 7 | `LOADTRUE` | `iABC A`; load true | None | Ordinary effect |
| 8 | `LOADNIL` | `iABC A B`; clear `R[A..A+B]` | None | Range effect |
| 9 | `GETUPVAL` | `iABC A B`; read upvalue `B` | Open/closed cell, value tag, closure identity | Upvalue effect |
| 10 | `SETUPVAL` | `iABC A B`; write upvalue `B` | Open/closed cell, value tag, GC barrier | Upvalue effect |

### 11–20: tables, fields, allocation, and method lookup

| # | Opcode | Format and static action | Runtime specialization axes | Protocol role |
|---:|---|---|---|---|
| 11 | `GETTABUP` | `iABC A B C`; upvalue table, short-string `K[C]` | Cell, receiver, shape, hit/miss, `__index`, result tag | Guarded access |
| 12 | `GETTABLE` | `iABC A B C`; `R[B][R[C]]` | Receiver, key class, shape, hit/miss, `__index`, result tag | Guarded access |
| 13 | `GETI` | `iABC A B C`; integer key `C` | Receiver, shape, array/hash hit, `__index`, result tag | Guarded access |
| 14 | `GETFIELD` | `iABC A B C`; short-string `K[C]` | Receiver, shape, slot hit/miss, `__index`, result tag | Guarded access |
| 15 | `SETTABUP` | `iABC A B C`; short key `K[B]`, value `RK(C)` | Cell, receiver, shape, slot, `__newindex`, barrier, rehash | Guarded write |
| 16 | `SETTABLE` | `iABC A B C`; `R[A][R[B]] = RK(C)` | Receiver, key class, shape, slot, `__newindex`, barrier, rehash | Guarded write |
| 17 | `SETI` | `iABC A B C`; integer key `B`, value `RK(C)` | Receiver, shape, array/hash slot, `__newindex`, barrier, resize | Guarded write |
| 18 | `SETFIELD` | `iABC A B C`; short key `K[B]`, value `RK(C)` | Receiver, shape, slot, `__newindex`, barrier, rehash | Guarded write |
| 19 | `NEWTABLE` | `ivABC A vB vC k`; allocate sized table | Allocation, GC, resize result | Always consumes `EXTRAARG` |
| 20 | `SELF` | `iABC A B C`; copy receiver and get method field | Receiver, shape, hit/miss, `__index`, result tag | Two-register effect |

A table “shape” must eventually name all assumptions needed by a direct slot access: exact table identity or layout
contract, array/hash storage generation, metatable identity, and metamethod absence. First-iteration success alone is
not proof that a slot remains stable.

### 21–48: arithmetic, bitwise operations, and metamethod companions

| # | Opcode | Operand form | Primitive residual alternatives | Companion |
|---:|---|---|---|---|
| 21 | `ADDI` | `R[B] + sC` | integer, float, primitive failure | `MMBINI` |
| 22 | `ADDK` | `R[B] + K[C]` | integer/integer, numeric float, failure | `MMBINK` |
| 23 | `SUBK` | `R[B] - K[C]` | integer/integer, numeric float, failure | `MMBINK` |
| 24 | `MULK` | `R[B] * K[C]` | integer/integer, numeric float, failure | `MMBINK` |
| 25 | `MODK` | `R[B] % K[C]` | integer, float, zero error, failure | `MMBINK` |
| 26 | `POWK` | `R[B] ^ K[C]` | numeric-to-float, failure | `MMBINK` |
| 27 | `DIVK` | `R[B] / K[C]` | numeric-to-float, failure | `MMBINK` |
| 28 | `IDIVK` | `R[B] // K[C]` | integer, numeric float, zero error, failure | `MMBINK` |
| 29 | `BANDK` | `R[B] & K[C]` | integer, integral-float coercion, failure | `MMBINK` |
| 30 | `BORK` | `R[B] \| K[C]` | integer, integral-float coercion, failure | `MMBINK` |
| 31 | `BXORK` | `R[B] ~ K[C]` | integer, integral-float coercion, failure | `MMBINK` |
| 32 | `SHLI` | `sC << R[B]` | integer, integral-float coercion, failure | `MMBINI` |
| 33 | `SHRI` | `R[B] >> sC` | integer, integral-float coercion, failure | `MMBINI` |
| 34 | `ADD` | `R[B] + R[C]` | integer/integer, numeric float, failure | `MMBIN` |
| 35 | `SUB` | `R[B] - R[C]` | integer/integer, numeric float, failure | `MMBIN` |
| 36 | `MUL` | `R[B] * R[C]` | integer/integer, numeric float, failure | `MMBIN` |
| 37 | `MOD` | `R[B] % R[C]` | integer, numeric float, zero error, failure | `MMBIN` |
| 38 | `POW` | `R[B] ^ R[C]` | numeric-to-float, failure | `MMBIN` |
| 39 | `DIV` | `R[B] / R[C]` | numeric-to-float, failure | `MMBIN` |
| 40 | `IDIV` | `R[B] // R[C]` | integer, numeric float, zero error, failure | `MMBIN` |
| 41 | `BAND` | `R[B] & R[C]` | integer/coercible pair, failure | `MMBIN` |
| 42 | `BOR` | `R[B] \| R[C]` | integer/coercible pair, failure | `MMBIN` |
| 43 | `BXOR` | `R[B] ~ R[C]` | integer/coercible pair, failure | `MMBIN` |
| 44 | `SHL` | `R[B] << R[C]` | integer/coercible pair, failure | `MMBIN` |
| 45 | `SHR` | `R[B] >> R[C]` | integer/coercible pair, failure | `MMBIN` |
| 46 | `MMBIN` | registers plus metamethod event `C` | metamethod absence/presence, callee kind, result or exit | Failure companion |
| 47 | `MMBINI` | register, signed `B`, event `C`, flip `k` | metamethod identity, callee kind, result or exit | Failure companion |
| 48 | `MMBINK` | register, `K[B]`, event `C`, flip `k` | metamethod identity, callee kind, result or exit | Failure companion |

The primitive opcode and its companion form one semantic owner. A numeric success records a quotation that bypasses
the companion. A primitive failure records the companion path or a terminal metamethod exit. The companion must not
be emitted after a successful specialized arithmetic stencil.

### 49–56: unary operations, concatenation, closing, and jump

| # | Opcode | Format and static action | Runtime specialization axes | Protocol role |
|---:|---|---|---|---|
| 49 | `UNM` | `iABC A B`; unary minus | integer, numeric float, `__unm` | Guarded unary |
| 50 | `BNOT` | `iABC A B`; bitwise not | integer, integral float, `__bnot` | Guarded unary |
| 51 | `NOT` | `iABC A B`; logical not | falsey versus truthy | Direct guarded value |
| 52 | `LEN` | `iABC A B`; length | string, table boundary, `__len`, unsupported | Guarded unary |
| 53 | `CONCAT` | `iABC A B`; concatenate `B` values from `R[A]` | operand classes, allocation, coercion, `__concat` | Range effect |
| 54 | `CLOSE` | `iABC A`; close upvalues and to-be-closed values | open cells, close methods, errors/yield | Closing boundary |
| 55 | `TBC` | `iABC A`; mark to-be-closed variable | value closability, cell creation, allocation | Closing boundary |
| 56 | `JMP` | `isJ sJ`; direct relative jump | None; successor is static | Direct control |

### 57–67: comparisons and tests

| # | Opcode | Operand form | Runtime specialization axes | Protocol role |
|---:|---|---|---|---|
| 57 | `EQ` | `R[A] == R[B]`, accept bit `k` | tag pair, primitive equality, `__eq`, branch result | Owns following `JMP` |
| 58 | `LT` | `R[A] < R[B]`, accept bit `k` | integer pair, numeric pair, strings, `__lt`, branch | Owns following `JMP` |
| 59 | `LE` | `R[A] <= R[B]`, accept bit `k` | integer pair, numeric pair, strings, `__le`, branch | Owns following `JMP` |
| 60 | `EQK` | `R[A] == K[B]`, accept bit `k` | register tag and raw equality result; no `__eq` | Owns following `JMP` |
| 61 | `EQI` | `R[A] == sB`, accept bit `k` | integer, float, other, branch result | Owns following `JMP` |
| 62 | `LTI` | `R[A] < sB`, accept bit `k` | integer, float, `__lt`, branch result | Owns following `JMP` |
| 63 | `LEI` | `R[A] <= sB`, accept bit `k` | integer, float, `__le`, branch result | Owns following `JMP` |
| 64 | `GTI` | `R[A] > sB`, accept bit `k` | integer, float, flipped `__lt`, branch result | Owns following `JMP` |
| 65 | `GEI` | `R[A] >= sB`, accept bit `k` | integer, float, flipped `__le`, branch result | Owns following `JMP` |
| 66 | `TEST` | truthiness of `R[A]`, accept bit `k` | falsey versus truthy, branch result | Owns following `JMP` |
| 67 | `TESTSET` | test `R[B]`; conditionally copy to `R[A]` | falsey/truthy, copy/no-copy, branch | Owns following `JMP` |

The recorded branch direction is not a permanent fact. The residual quotation must guard the condition on every
execution and exit at the exact untaken successor when the recorded direction changes.

### 68–84: calls, returns, loops, aggregates, closures, and varargs

| # | Opcode | Format and static action | Runtime specialization axes | Protocol role |
|---:|---|---|---|---|
| 68 | `CALL` | `iABC A B C`; call with fixed/open arguments and results | callee class/identity, arity, frame, result count, yield/error | Call boundary |
| 69 | `TAILCALL` | `iABC A B C k`; tail call | callee, arity, vararg correction, close state, result path | Terminal call |
| 70 | `RETURN` | `iABC A B C k`; fixed/open return range | result count, close state, vararg correction, caller contract | Terminal return |
| 71 | `RETURN0` | `iABC`; return no values | caller requested result count, hook state | Terminal return |
| 72 | `RETURN1` | `iABC A`; return one value | result tag, caller requested count, hook state | Terminal return |
| 73 | `FORLOOP` | `iABx A Bx`; update normalized numeric loop | integer-count versus float mode, continue/done | Loop backedge |
| 74 | `FORPREP` | `iABx A Bx`; normalize init/limit/step | integer mode, float mode, zero trip, conversion error | Loop entry |
| 75 | `TFORPREP` | `iABx A Bx`; swap control/closing values and mark TBC | closing value, TBC allocation/error | Generic-for entry |
| 76 | `TFORCALL` | `iABC A C`; call iterator for `C` results | iterator class/identity, call behavior, result tags | Generic-for call |
| 77 | `TFORLOOP` | `iABx A Bx`; continue when new control is non-nil | nil/non-nil result, copied control value | Generic-for backedge |
| 78 | `SETLIST` | `ivABC A vB vC k`; append registers to table | fixed/open count, table capacity, resize, barrier | Optional `EXTRAARG` |
| 79 | `CLOSURE` | `iABx A Bx`; instantiate child prototype | capture modes, existing/new cells, allocation, GC | Closure allocation |
| 80 | `VARARG` | `iABC A B C k`; fetch fixed/all varargs | fixed/open count, hidden args versus table, stack growth | May set top |
| 81 | `GETVARG` | `iABC A B C`; index varargs using `R[C]` | integral in-range, string `"n"`, miss; argument value tag | Vararg access |
| 82 | `ERRNNIL` | `iABx A Bx`; error when `R[A]` is not nil | nil/no-op versus non-nil/error; optional global name | Error boundary |
| 83 | `VARARGPREP` | `iABC`; adjust vararg frame | hidden args versus vararg table, allocation, hooks, stack move | Function entry |
| 84 | `EXTRAARG` | `iAx Ax`; extended operand bits | None | Structural only |

## Family totals

| Family | Opcodes | Count |
|---|---|---:|
| Movement and constants | 0–8 | 9 |
| Upvalues | 9–10 | 2 |
| Tables and method lookup | 11–20 | 10 |
| Arithmetic, bitwise, and companions | 21–48 | 28 |
| Unary, concat, closing, and jump | 49–56 | 8 |
| Comparisons and tests | 57–67 | 11 |
| Calls and returns | 68–72 | 5 |
| Numeric and generic loops | 73–77 | 5 |
| Aggregate, closure, vararg, error, structural | 78–84 | 7 |
| **Total** | **0–84** | **85** |

## Recorder consequence

The first native recorder should not emit a generic fact tuple. Each concrete opcode learner should write its selected
residual quotation and that quotation's exact patch payload into the opcode occurrence's bounded recording slot.
The static bytecode occurrence remains the owner.

```text
OpcodeOccurrenceOwner
├── static bytecode operands
├── exact learner stencil
└── recording slot
    ├── selected residual quotation
    ├── patch payload
    ├── guard payload
    └── taken successor

matching backedge
→ loop owner validates all populated occurrence slots
→ loop owner applies exact superinstruction quotations
→ installer emits a fresh RW residual
→ installer seals RX and publishes
```

The residual alternatives for opcodes 0–10 are frozen in `LUA55_OPCODE_00_08_SPECIALIZATION.md` and
`LUA55_OPCODE_09_10_SPECIALIZATION.md`. The next checkpoint constructs those owners from real decoded prototypes.
