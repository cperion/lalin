# Moonlift Lua VM — PUC Lua 5.5 Delta

**Document type**: Architectural delta.  
**Baseline**: `experiments/lua_interpreter_vm/README.md` — the Lua 5.1-based VM design.  
**Target**: PUC Lua 5.5 compliance, Moonlift-idiomatic throughout.  
**Audience**: An implementer who has read the README and needs a complete picture of every structural change, with no gaps to fill by reading PUC source.

This document records every architectural decision made to move from the current design to 5.5 compliance. It is not a rewrite of the README. Read both together. Where this document is silent, the README governs.

---

## Table of contents

1. [Value type — integer/float split](#1-value-type--integerfloat-split)
2. [Instruction struct — k-bit](#2-instruction-struct--k-bit)
3. [Proto struct — flag field](#3-proto-struct--flag-field)
4. [Opcode set — 38 → 85](#4-opcode-set--38--85)
5. [MMBIN dispatch pattern — the key invariant](#5-mmbin-dispatch-pattern--the-key-invariant)
6. [VARARGPREP replaces call-site vararg adjustment](#6-varargprep-replaces-call-site-vararg-adjustment)
7. [TBC: to-be-closed locals and raise_error](#7-tbc-to-be-closed-locals-and-raise_error)
8. [Loader contract — EXTRAARG folding](#8-loader-contract--extraarg-folding)
9. [Lua generator schema update](#9-lua-generator-schema-update)
10. [What does NOT change](#10-what-does-not-change)

---

## 1. Value type — integer/float split

### Current state

`src/constants.lua` defines a single `TAG_NUM = 4` (f64). The `Value` struct stores all numbers as f64 in `bits`. Every numerical operation goes through a single `value_as_number` region.

### Decision

PUC 5.5 distinguishes `LUA_VNUMINT` and `LUA_VNUMFLT` at the type-tag level (`lobject.h`: `makevariant(LUA_TNUMBER, 0)` vs `makevariant(LUA_TNUMBER, 1)`). The VM must track this distinction because integer and float semantics differ: integer division (`//`), bitwise operations, and the metamethod dispatch path all depend on knowing which subtype is in use.

### Tag renumbering

Replace the single `TAG_NUM = 4` with two tags. All tags that were `≥ 4` shift up by one.

```lua
-- src/constants.lua — revised Tag block
Tag.NIL      = 0
Tag.FALSE    = 1
Tag.TRUE     = 2
Tag.LIGHTUD  = 3
Tag.INTEGER  = 4   -- NEW: Lua integer (i64)
Tag.NUM      = 5   -- was 4; now float (f64)
Tag.STR      = 6   -- was 5
Tag.TABLE    = 7   -- was 6
Tag.LCLOSURE = 8   -- was 7
Tag.CCLOSURE = 9   -- was 8
Tag.USERDATA = 10  -- was 9
Tag.THREAD   = 11  -- was 10
Tag.PROTO    = 12  -- was 11
```

All constant integers in `src/constants.lua` and every hard-coded tag comparison anywhere in the codebase must be updated to the new numbering.

### Value struct — `bits` is dual-use

The `Value` struct definition in `src/products.lua` does not change shape:

```moonlift
struct Value
    tag: u32
    aux: u32
    bits: u64
end
```

Encoding rules change:

| `tag` | `bits` interpretation |
|---|---|
| `TAG_INTEGER` | `as(i64, bits)` — a 64-bit signed integer |
| `TAG_NUM` | `as(f64, bits)` — a 64-bit IEEE 754 float |
| all others | unchanged from README |

`aux` remains reserved/zero for both number types.

### New helper regions

Replace `value_as_number` with three explicit regions:

```moonlift
region value_as_integer(v: Value;
    integer: cont(n: i64),
    not_integer: cont())

region value_as_float(v: Value;
    float: cont(n: f64),
    not_float: cont())

region value_to_number(v: Value;
    integer: cont(n: i64),
    float: cont(n: f64),
    not_number: cont())
```

`value_to_number` is the replacement for the old single-arm `value_as_number`. It exposes both arms. Callers that genuinely need only a float (e.g. `FORLOOP` with a float step) use `value_as_float` directly.

Old `value_as_number` is removed. Every caller must be migrated to one of the three new regions.

### New constructor expressions

```moonlift
expr make_integer(n: i64) -> Value
    -- result.tag = TAG_INTEGER, result.bits = as(u64, n)

expr make_float(n: f64) -> Value
    -- result.tag = TAG_NUM, result.bits = as(u64, n)
```

These replace ad-hoc `Value` construction at every number-producing site.

### Propagation to existing regions

The following existing regions must grow a two-arm number fast path:

| Region | Change |
|---|---|
| `binop_dispatch` | `fast_number(x: f64, y: f64)` → `fast_integer(x: i64, y: i64)` + `fast_float(x: f64, y: f64)` |
| `unop_dispatch` | `fast_number(x: f64)` → `fast_integer(x: i64)` + `fast_float(x: f64)` |
| `value_equal`, `value_less_than`, `value_less_equal` | fast path must compare same-type pairs; cross-type integer/float comparison promotes integer to float |
| `op_forloop`, `op_forprep` | must handle integer and float loop variants as separate fast paths |

The `BinopDispatch` protocol from the README changes from:

```text
BinopDispatch = fast_number(x: f64, y: f64) | call_mm(mm) | type_error()
```

to:

```text
BinopDispatch =
    fast_integer(x: i64, y: i64)
  | fast_float(x: f64, y: f64)
  | call_mm(mm)
  | type_error()
```

Existing slow paths and metamethod arms are unchanged.

---

## 2. Instruction struct — k-bit

### Current state

`src/products.lua`:

```moonlift
struct Instr
    op: u16
    a: u16
    b: u16
    c: u16
    bx: u32
    sbx: i32
end
```

The PUC 5.5 wire format encodes a 1-bit `k` flag at bit position 15 of a packed 32-bit instruction (`lopcodes.h`: `#define POS_k (POS_A + SIZE_A)`, i.e. bit 15). It is used by multiple opcodes with different semantics.

### Decision

Add `k: u8` to the decoded `Instr` struct. The loader decodes the wire bit into this field. The VM loop sees it as a clean boolean (0 or 1); it never re-reads packed bits.

```moonlift
struct Instr
    op: u16
    a: u16
    b: u16
    c: u16
    k: u8      -- NEW: decoded from wire bit 15
    bx: u32
    sbx: i32
end
```

### Semantics per opcode family

`k` is not globally uniform. Its meaning is opcode-specific:

| Opcode family | `k` meaning |
|---|---|
| `SETTABUP`, `SETTABLE`, `SETTI`, `SETFIELD` | `1` → C operand is a constant index `K[C]`; `0` → C is a register `R[C]` |
| `EQ`, `LT`, `LE` | condition sense inversion: `1` → skip if result is `false`; `0` → skip if `true` |
| `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI` | same condition sense as above |
| `TEST`, `TESTSET` | test polarity |
| `TAILCALL`, `RETURN` | `1` → function builds upvalues that may need closing; C encodes hidden vararg parameters |
| `VARARG` | `1` → function has a vararg table at `R[B]` |
| `MMBINI`, `MMBINK` | `1` → arguments were flipped (constant is first operand) |
| `NEWTABLE` | `1` → array size uses EXTRAARG extension |
| `SETLIST` | `1` → C uses EXTRAARG extension for large list index |
| `JMP` | unused; always 0 |

### New helper region — `resolve_rk`

Opcodes with a C operand that may be either a register or a constant index use this region:

```moonlift
region resolve_rk(
    L: ptr(LuaThread),
    base: index,
    k: u8,
    c: u16,
    constants: ptr(Value);
    value: cont(v: Value))
entry start()
    if k == 1 then
        jump value(v = constants[as(index, c)])
    end
    jump value(v = L.stack[base + as(index, c)])
end
```

`resolve_rk` is used by: `op_settabup`, `op_settable`, `op_setti`, `op_setfield`, `op_mmbini`, `op_mmbink`, and the store side of comparisons where C encodes a constant.

---

## 3. Proto struct — flag field

### Current state

`src/products.lua` `Proto` uses `is_vararg: u8` as a boolean.

### Decision

Replace `is_vararg: u8` with `flag: u8` to match PUC 5.5 `Proto.flag` (`lobject.h`: `lu_byte flag`). The flag field encodes three bit constants:

```lua
-- src/constants.lua — new Proto flag constants
local ProtoFlag = {}
ProtoFlag.PF_VAHID = 1   -- function has hidden vararg arguments (set by VARARGPREP at call entry)
ProtoFlag.PF_VATAB = 2   -- vararg passed as table (cleared after VARARGPREP runs)
ProtoFlag.PF_FIXED = 4   -- prototype has parts in fixed memory (loader sets this; VM treats it as read-only hint)
```

```moonlift
struct Proto
    gc: GCHeader
    code: ptr(Instr)
    code_len: index
    constants: ptr(Value)
    constants_len: index
    children: ptr(ptr(Proto))
    children_len: index
    lineinfo: ptr(i32)
    lineinfo_len: index
    locvars: ptr(LocVar)
    locvars_len: index
    upvals: ptr(UpValDesc)
    upvals_len: index
    source: ptr(String)
    linedefined: i32
    lastlinedefined: i32
    numparams: u8
    flag: u8     -- replaces is_vararg; use ProtoFlag.PF_VAHID to test vararg
    maxstack: u16
end
```

Every site that tested `proto.is_vararg != 0` must instead test `proto.flag & ProtoFlag.PF_VAHID`. The `isvararg` predicate at the region level is:

```moonlift
expr proto_is_vararg(p: ptr(Proto)) -> bool
    (p.flag & 3) != 0   -- PF_VAHID | PF_VATAB
end
```

`PF_FIXED` is a loader/memory-management hint. The VM execution engine does not branch on it.

---

## 4. Opcode set — 38 → 85

### Current state

`src/constants.lua` defines 38 opcodes (0–37), Lua 5.1 order. Three quickened pseudo-opcodes exist outside that range (100–102) for optional specialization.

### Decision

Replace the entire `Op` table with the PUC 5.5 canonical ordering (85 opcodes, 0–84). `GETGLOBAL` (was 5) and `SETGLOBAL` (was 7) are removed entirely; their function is subsumed by `GETTABUP` / `SETTABUP`.

```lua
-- src/constants.lua — complete revised Op block
local Op = {}
Op.MOVE        = 0
Op.LOADI       = 1
Op.LOADF       = 2
Op.LOADK       = 3
Op.LOADKX      = 4
Op.LOADFALSE   = 5
Op.LFALSESKIP  = 6
Op.LOADTRUE    = 7
Op.LOADNIL     = 8
Op.GETUPVAL    = 9
Op.SETUPVAL    = 10
Op.GETTABUP    = 11
Op.GETTABLE    = 12
Op.GETI        = 13
Op.GETFIELD    = 14
Op.SETTABUP    = 15
Op.SETTABLE    = 16
Op.SETTI       = 17
Op.SETFIELD    = 18
Op.NEWTABLE    = 19
Op.SELF        = 20
Op.ADDI        = 21
Op.ADDK        = 22
Op.SUBK        = 23
Op.MULK        = 24
Op.MODK        = 25
Op.POWK        = 26
Op.DIVK        = 27
Op.IDIVK       = 28
Op.BANDK       = 29
Op.BORK        = 30
Op.BXORK       = 31
Op.SHLI        = 32
Op.SHRI        = 33
Op.ADD         = 34
Op.SUB         = 35
Op.MUL         = 36
Op.MOD         = 37
Op.POW         = 38
Op.DIV         = 39
Op.IDIV        = 40
Op.BAND        = 41
Op.BOR         = 42
Op.BXOR        = 43
Op.SHL         = 44
Op.SHR         = 45
Op.MMBIN       = 46
Op.MMBINI      = 47
Op.MMBINK      = 48
Op.UNM         = 49
Op.BNOT        = 50
Op.NOT         = 51
Op.LEN         = 52
Op.CONCAT      = 53
Op.CLOSE       = 54
Op.TBC         = 55
Op.JMP         = 56
Op.EQ          = 57
Op.LT          = 58
Op.LE          = 59
Op.EQK         = 60
Op.EQI         = 61
Op.LTI         = 62
Op.LEI         = 63
Op.GTI         = 64
Op.GEI         = 65
Op.TEST        = 66
Op.TESTSET     = 67
Op.CALL        = 68
Op.TAILCALL    = 69
Op.RETURN      = 70
Op.RETURN0     = 71
Op.RETURN1     = 72
Op.FORLOOP     = 73
Op.FORPREP     = 74
Op.TFORPREP    = 75
Op.TFORCALL    = 76
Op.TFORLOOP    = 77
Op.SETLIST     = 78
Op.CLOSURE     = 79
Op.VARARG      = 80
Op.GETVARG     = 81
Op.ERRNNIL     = 82
Op.VARARGPREP  = 83
Op.EXTRAARG    = 84
```

The quickened pseudo-opcodes `LOADK_FAST = 100`, `MOVE_FAST = 101`, `ADD_NUM = 102` are retained outside the 0–84 range as optional specialization extensions. Their existence does not affect base semantics.

### Removed opcodes

`GETGLOBAL` and `SETGLOBAL` are fully removed. There are no compatibility shims. Bytecode from a 5.1 compiler must be re-compiled for 5.5; the VM does not accept mixed versions.

`LOADBOOL` is removed and replaced by `LOADFALSE`, `LFALSESKIP`, and `LOADTRUE`.

### New opcode regions — complete signatures

What follows is the region signature for every opcode not present in the 5.1 README. Existing opcodes whose signatures change are also included.

#### 4.1 Immediate load opcodes

```moonlift
region op_loadi(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
-- R[A] = make_integer(as(i64, sbx))
```

```moonlift
region op_loadf(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
-- R[A] = make_float(as(f64, sbx))
```

`LOADK` and `LOADKX` are unchanged in protocol shape; the constant referenced may now be a `TAG_INTEGER` or `TAG_NUM` value.

#### 4.2 Boolean opcodes — LOADBOOL replaced

`LOADBOOL` is gone. Replace with three concrete opcodes:

```moonlift
region op_loadfalse(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
-- R[A] = false

region op_loadtrue(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
-- R[A] = true

region op_lfalseskip(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index))
-- R[A] = false; jump next(pc = pc + 2)   [skips the following LOADTRUE]
```

`LFALSESKIP` is used to compile `(not cond ? false : true)` patterns. It loads false and skips one instruction (the LOADTRUE that follows it).

#### 4.3 Specialized table access — GETI, GETFIELD, SETTI, SETFIELD

These four opcodes share the same protocol shape as `GETTABLE` / `SETTABLE` with the key operand specialized:

```moonlift
region op_geti(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- R[A] = R[B][C]  where C is integer immediate key
```

```moonlift
region op_getfield(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- R[A] = R[B][K[C]:shortstring]
```

```moonlift
region op_setti(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- R[A][B] = RK(C)  where B is integer immediate key; C resolved via resolve_rk
```

```moonlift
region op_setfield(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- R[A][K[B]:shortstring] = RK(C);  C resolved via resolve_rk
```

#### 4.4 GETTABUP and SETTABUP — replace GETGLOBAL/SETGLOBAL

```moonlift
region op_gettabup(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- R[A] = UpValue[B][K[C]:shortstring]
-- Semantically: load upvalue B (which is a table), then key K[C] from it.
-- The _ENV upvalue at index 0 is the global table.
```

```moonlift
region op_settabup(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- UpValue[A][K[B]:shortstring] = RK(C)
-- C resolved via resolve_rk (k-bit controls R vs K for value operand)
```

#### 4.5 Register-op-immediate and register-op-constant arithmetic

These opcodes follow the MMBIN skip pattern (§5). Each has an integer fast path and a float fast path. The signature shape is the same as `op_add` / `op_sub` etc. from §5; only the operand sourcing changes.

```text
ADDI:  R[A] = R[B] + sC
ADDK:  R[A] = R[B] + K[C]:number
SUBK:  R[A] = R[B] - K[C]:number
MULK:  R[A] = R[B] * K[C]:number
MODK:  R[A] = R[B] % K[C]:number
POWK:  R[A] = R[B] ^ K[C]:number   (result is always float)
DIVK:  R[A] = R[B] / K[C]:number   (result is always float)
IDIVK: R[A] = R[B] // K[C]:number  (floor division)
BANDK: R[A] = R[B] & K[C]:integer
BORK:  R[A] = R[B] | K[C]:integer
BXORK: R[A] = R[B] ~ K[C]:integer
SHLI:  R[A] = sC << R[B]            (operand order reversed vs SHRI)
SHRI:  R[A] = R[B] >> sC
```

All share the same continuation protocol as `op_add` (see §5). Each is a concrete generated region; the constant or immediate is inlined at generation time.

**SHLI operand reversal**: `SHLI` computes `sC << R[B]`, not `R[B] << sC`. This is the PUC 5.5 canonical encoding. The Lua generator must emit the operands in the correct order.

**Integer-only operations**: `BAND`, `BOR`, `BXOR`, `SHL`, `SHR`, and their `*K`/`*I` variants require both operands to be `TAG_INTEGER`. If either operand is `TAG_NUM` (float), the MMBIN slow path is taken immediately — there is no float fast path for bitwise ops.

**Division semantics**: `DIV` and `DIVK` always produce a float. `IDIV` / `IDIVK` use floor division (toward −∞), not truncation toward zero.

#### 4.6 Comparison-with-immediate and comparison-with-constant

```moonlift
region op_eqk(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32),
    oom: cont())
-- if ((R[A] == K[B]) ~= k) then pc++

region op_eqi(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32),
    oom: cont())
-- if ((R[A] == sB) ~= k) then pc++
-- sB is signed immediate from B field

region op_lti(...)   -- if ((R[A] <  sB) ~= k) then pc++
region op_lei(...)   -- if ((R[A] <= sB) ~= k) then pc++
region op_gti(...)   -- if ((R[A] >  sB) ~= k) then pc++
region op_gei(...)   -- if ((R[A] >= sB) ~= k) then pc++
```

All six share the same protocol shape. There is no metamethod path in the numeric fast case; `enter_lua` / `enter_native` / `yielded` are absent from these signatures.

The `k` field inverts the skip condition, same as `EQ` / `LT` / `LE`.

#### 4.7 RETURN0 and RETURN1

These are specializations of `RETURN` for the common zero-result and single-result cases.

```moonlift
region op_return0(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    finished: cont(nres: i32),
    resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32),
    oom: cont())
-- return (no values)

region op_return1(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    finished: cont(nres: i32),
    resume_parent: cont(parent: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32),
    oom: cont())
-- return R[A]
```

When `k == 1`, the function builds upvalues needing closing. Before returning, emit `tbc_close_chain(level = frame.base)`.

#### 4.8 MMBIN, MMBINI, MMBINK

```moonlift
region op_mmbin(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- A is source register (original LHS), B is source register (original RHS)
-- C is TM event number (e.g. TM_ADD)
-- result destination = frame.resume_a (stored by preceding arithmetic handler)
-- frame.resume_mode = RESUME_BINOP_MM
```

```moonlift
region op_mmbini(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- A is source register, sB is signed immediate operand
-- C is TM event number
-- k == 1: arguments were flipped (sB is first operand, R[A] is second)
-- frame.resume_mode = RESUME_BINOP_MM

region op_mmbink(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- A is source register, K[B] is constant operand
-- C is TM event number
-- k == 1: arguments were flipped (K[B] is first operand, R[A] is second)
-- frame.resume_mode = RESUME_BINOP_MM
```

The destination register for the MMBIN result is the `A` field of the *preceding* arithmetic instruction, not the MMBIN instruction itself. The arithmetic handler must store this into `frame.resume_a` before jumping `next(pc = pc + 1)`.

#### 4.9 TBC

```moonlift
region op_tbc(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32),
    oom: cont())
-- Marks R[A] as a to-be-closed local.
-- Does not modify the value in R[A].
-- Tags the stack slot in the TBC chain.
-- Emits error if R[A] does not have a __close metamethod and is not false/nil.
```

See §7 for full TBC architecture.

#### 4.10 VARARGPREP

```moonlift
region op_varargprep(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    oom: cont())
-- Adjusts the vararg frame at function entry (pc = 0 for vararg functions).
-- Moves fixed parameters, sets up vararg region on stack.
-- Replaces the call-site vararg adjustment removed from prepare_call (see §6).
```

#### 4.11 ERRNNIL

```moonlift
region op_errnnil(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32))
-- if R[A] ~= nil then raise error(K[Bx - 1]) end
-- Bx == 0: global name index does not fit; error message omits the name.
```

#### 4.12 TFORPREP, TFORCALL, TFORLOOP

The generic for-loop is split into three cooperating opcodes in 5.5:

```moonlift
region op_tforprep(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
-- Creates an upvalue for R[A + 3] (the iterator state).
-- Jumps forward by Bx (to TFORLOOP at the end of the loop body).

region op_tforcall(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    enter_lua: cont(child: ptr(Frame)),
    enter_native: cont(cl: ptr(CClosure)),
    yielded: cont(nres: i32),
    error: cont(code: i32),
    oom: cont())
-- R[A+4], ..., R[A+3+C] = R[A](R[A+1], R[A+2])
-- Calls the iterator function. frame.resume_mode = RESUME_TFORLOOP_CALL.

region op_tforloop(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    do_jump: cont(frame: ptr(Frame), pc: index, base: index, top: index))
-- if R[A+2] ~= nil then { R[A] = R[A+2]; pc -= Bx }
-- Continues loop if iterator returned a non-nil first result.
```

Loop structure: `TFORPREP` → body → `TFORCALL` → `TFORLOOP` → back to body or exit.

#### 4.13 GETVARG

```moonlift
region op_getvarg(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32))
-- R[A] = R[B][R[C]]  where R[B] is the vararg parameter table.
-- Only valid when proto.flag & PF_VATAB is set.
```

---

## 5. MMBIN dispatch pattern — the key invariant

### Decision

In PUC 5.5, every arithmetic and bitwise opcode is followed in the bytecode stream by a `MMBIN` / `MMBINI` / `MMBINK` instruction. The arithmetic handler either succeeds and skips the `MMBIN` (jumping `pc + 2`), or fails and falls through to it (jumping `pc + 1`). This is not optional; the bytecode always contains the MMBIN successor, and the VM relies on this pairing.

This changes the protocol shape of **all arithmetic and bitwise opcode handlers**. They no longer carry `enter_lua`, `enter_native`, or `yielded` continuations. Those exits live exclusively on `op_mmbin` / `op_mmbini` / `op_mmbink`.

### Canonical arithmetic handler shape

```moonlift
region op_add(
    L: ptr(LuaThread), frame: ptr(Frame), pc: index, base: index, top: index,
    a: u16, b: u16, c: u16, k: u8, bx: u32, sbx: i32;
    next: cont(frame: ptr(Frame), pc: index, base: index, top: index),
    error: cont(code: i32))
entry start()
    let lhs: Value = L.stack[base + as(index, b)]
    let rhs: Value = L.stack[base + as(index, c)]
    if lhs.tag == TAG_INTEGER and rhs.tag == TAG_INTEGER then
        L.stack[base + as(index, a)] = make_integer(as(i64, lhs.bits) + as(i64, rhs.bits))
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    if lhs.tag == TAG_NUM and rhs.tag == TAG_NUM then
        L.stack[base + as(index, a)] = make_float(as(f64, lhs.bits) + as(f64, rhs.bits))
        jump next(frame = frame, pc = pc + 2, base = base, top = top)
    end
    -- store destination register into frame for MMBIN to find
    frame.resume_a = a
    jump next(frame = frame, pc = pc + 1, base = base, top = top)
end
```

### Affected opcode families

This pattern applies to every handler in the following list:

- **register–register**: `ADD`, `SUB`, `MUL`, `MOD`, `POW`, `DIV`, `IDIV`, `BAND`, `BOR`, `BXOR`, `SHL`, `SHR`
- **register–immediate**: `ADDI`, `SHLI`, `SHRI`
- **register–constant**: `ADDK`, `SUBK`, `MULK`, `MODK`, `POWK`, `DIVK`, `IDIVK`, `BANDK`, `BORK`, `BXORK`
- **unary**: `UNM`, `BNOT` (also followed by MMBIN; success jump is still `pc + 2`)

**Integer-only operations**: `BAND`, `BOR`, `BXOR`, `SHL`, `SHR`, and their `*K`/`*I` variants jump `pc + 1` immediately if either operand is not `TAG_INTEGER` — there is no float fast path.

### Invariant summary

| outcome | pc jump | who handles metamethod |
|---|---|---|
| Fast path succeeded | `pc + 2` (skips MMBIN) | nobody; MMBIN never executes |
| Fast path failed | `pc + 1` (enters MMBIN) | `op_mmbin` / `op_mmbini` / `op_mmbink` |

The arithmetic handler must write `frame.resume_a = a` (the destination register) **before** jumping `pc + 1`, so that `op_mmbin` knows where to store the result.

### Removed from arithmetic handler signatures

`enter_lua`, `enter_native`, and `yielded` are **removed** from the signatures of all arithmetic and bitwise handlers. They appear only on `op_mmbin`, `op_mmbini`, `op_mmbink`.

---

## 6. VARARGPREP replaces call-site vararg adjustment

### Current state

`prepare_call` / `frame_push` / `adjust_varargs` handle vararg frame adjustment at the call site.

### Decision

PUC 5.5 moves this responsibility into the bytecode. The compiler guarantees `VARARGPREP` is at `pc = 0` for every vararg function. `VARARGPREP` performs the stack adjustment.

**`prepare_call` / `frame_push` must NOT perform vararg adjustment for 5.5 bytecode.** The `adjust_varargs` call inside `frame_push` is removed.

The existing `adjust_varargs` region signature is retained — it is now called by `op_varargprep` at dispatch time, not by `frame_push`.

### Consequence for non-vararg functions

`VARARGPREP` only appears in functions where `proto_is_vararg(proto)` is true. `frame_push` for non-vararg functions is unchanged.

---

## 7. TBC: to-be-closed locals and raise_error

### Overview

PUC 5.5 introduces to-be-closed variables (`<close>` attribute). The `TBC` opcode marks a stack slot as requiring its `__close` metamethod on scope exit. This interacts with `raise_error`, `RETURN`, and `CLOSE`.

### LuaThread — new field

```moonlift
struct LuaThread
    ...
    tbc_head: index    -- NEW: index of topmost TBC slot; 0 if none
end
```

### TBC chain encoding

A stack slot `i` is a TBC slot if `Value.aux` at that slot contains a nonzero backward delta `d`, meaning the previous TBC slot is at `i - d`. `L.tbc_head` points to the topmost slot in the chain.

### New region — `tbc_close_chain`

```moonlift
region tbc_close_chain(
    L: ptr(LuaThread),
    level: index;
    done: cont(),
    error: cont(code: i32),
    oom: cont())
-- Walks the TBC chain from L.tbc_head down to slots >= level.
-- For each TBC slot, calls its __close metamethod.
-- Updates L.tbc_head as slots are closed.
-- If __close raises, that error propagates via error().
```

### `raise_error` — TBC drain before unwind

Signature unchanged:

```moonlift
region raise_error(
    L: ptr(LuaThread),
    err: Value;
    caught: cont(frame: ptr(Frame), handler: ptr(ProtectedFrame)),
    uncaught: cont(code: i32))
```

Implementation gains a mandatory step: before reaching `caught` or `uncaught`, emit `tbc_close_chain` for all TBC slots down to the target protected frame's stack level. If the chain drain raises a new error, that error replaces the original.

### RETURN opcodes — TBC close on exit

When `k == 1` in `RETURN`, `RETURN0`, or `RETURN1`, emit `tbc_close_chain(level = frame.base)` before copying results and popping the frame.

### New Resume constant

```lua
Resume.TBC_CLOSE = 16   -- NEW: resuming after a __close metamethod call during TBC drain
```

---

## 8. Loader contract — EXTRAARG folding

### Decision

`LOADKX`, `NEWTABLE` (with `k=1`), and `SETLIST` (with `k=1`) use a trailing `EXTRAARG` instruction. The Moonlift VM invariant is: **every instruction is self-contained**. The loader folds EXTRAARG information into its predecessor before handing `Instr[]` to the VM.

### Folding rules

| Pair | Folded result |
|---|---|
| `LOADKX` + `EXTRAARG Ax` | `LOADKX.bx = Ax`; EXTRAARG slot → NOP |
| `NEWTABLE (k=1)` + `EXTRAARG Ax` | array size = `(Ax << SIZE_vC) \| vC`; EXTRAARG → NOP |
| `SETLIST (k=1)` + `EXTRAARG Ax` | list offset = `(Ax << SIZE_vC) \| vC`; EXTRAARG → NOP |

After folding, `EXTRAARG` in isolation is a NOP. `dispatch_instruction` must treat it as such.

### validate_proto responsibility

`validate_proto` must verify EXTRAARG folding was applied. An unfolded `NEWTABLE`/`SETLIST`/`LOADKX` with `k=1` and a non-NOP successor is rejected as invalid.

---

## 9. Lua generator schema update

The opcode spec table in Part VIII gains new per-row fields:

```lua
{
  name            = "ADD",
  mode            = "ABC",
  handler         = "op_add",
  effects         = {"next", "error"},   -- enter_lua/enter_native/yielded removed

  -- NEW fields:
  mmbin_follows   = true,    -- handler uses pc+2/pc+1 skip; frame.resume_a written on slow path
  arith_types     = "both",  -- "integer" | "float" | "both" | nil
  k_semantics     = nil,     -- "RKC" if C goes through resolve_rk, else nil
  immediate       = nil,     -- "sC" | "sBx" | nil
  tbc_aware       = false,   -- whether this opcode interacts with the TBC chain
  vararg_adjust   = false,   -- true only for VARARGPREP
}
```

Field semantics:

| Field | Meaning |
|---|---|
| `mmbin_follows` | Emit two-arm `next`: `pc+2` on fast path, `pc+1` on fallthrough. Gate removal of `enter_lua`/`enter_native`/`yielded` from signature. |
| `arith_types` | `"both"`: integer check first, then float. `"integer"`: bitwise only. `"float"`: always-float ops (POW, DIV). `nil`: no numeric fast path. |
| `k_semantics` | `"RKC"`: emit `resolve_rk` for C operand. |
| `immediate` | `"sC"`: C field is signed immediate. `"sBx"`: Bx field is signed immediate value (LOADI/LOADF). |
| `tbc_aware` | Emit `tbc_close_chain` at appropriate point. True for `TBC`, `RETURN`, `RETURN0`, `RETURN1`, `CLOSE`. |
| `vararg_adjust` | Emit `adjust_varargs` call instead of standard opcode body. True for `VARARGPREP` only. |

### Updated TM constants

```lua
-- src/constants.lua — additions to TM block
TM.IDIV  = 17
TM.BAND  = 18
TM.BOR   = 19
TM.BXOR  = 20
TM.SHL   = 21
TM.SHR   = 22
TM.CLOSE = 23
TM.N     = 24   -- updated sentinel
```

---

## 10. What does NOT change

The following are fully preserved from the current README. No modifications required.

| Element | Status |
|---|---|
| `Frame` struct and all `resume_*` fields | Unchanged (new `RESUME_TBC_CLOSE = 16` constant added) |
| `ProtectedFrame` struct | Unchanged |
| VM loop hot state (`frame, pc, base, top` block params) | Unchanged |
| `table_raw_get/set`, `table_get/set` region family | Unchanged |
| `prepare_call` / `frame_push` / `return_from_lua` signatures | Unchanged (frame_push loses internal vararg-adjust call) |
| `commit_vm_state` safepoint discipline | Unchanged |
| `find_upvalue`, `close_upvalues`, `make_lclosure` | Unchanged |
| `enter_protected`, `leave_protected`, `protected_call` | Unchanged |
| `coroutine_resume`, `coroutine_yield` | Unchanged |
| All GC regions | Unchanged |
| All sealed API functions | Unchanged |
| Optional specialization (`InlineCache`, `QuickInstr`, `probe_gettable_cache`, quickened pseudo-opcodes 100–102) | Unchanged |

---

## Appendix A — Full delta summary table

| Area | Current (5.1-based) | Target (5.5) |
|---|---|---|
| Number tags | `TAG_NUM = 4` (f64 only) | `TAG_INTEGER = 4` (i64), `TAG_NUM = 5` (f64) |
| All tags ≥ 4 | `STR=5 TABLE=6 …` | `STR=6 TABLE=7 …` (all shifted +1) |
| `Instr` struct | 6 fields | 7 fields (adds `k: u8`) |
| `Proto` struct | `is_vararg: u8` | `flag: u8` with `PF_VAHID/PF_VATAB/PF_FIXED` |
| Opcode count | 38 base (+ 3 quickened) | 85 base (+ 3 quickened) |
| `GETGLOBAL` / `SETGLOBAL` | present | removed; use `GETTABUP` / `SETTABUP` |
| `LOADBOOL` | present | removed; use `LOADFALSE` / `LFALSESKIP` / `LOADTRUE` |
| `TFORLOOP` (single) | present | split into `TFORPREP` / `TFORCALL` / `TFORLOOP` |
| Arithmetic handler continuations | `enter_lua` / `enter_native` / `yielded` on each | removed; moved to `op_mmbin` family only |
| MMBIN skip | absent | fast path → `pc+2`; slow path → `pc+1` → MMBIN |
| Vararg adjustment | `adjust_varargs` in `frame_push` | `op_varargprep` at `pc=0` |
| TBC | absent | `op_tbc`, `tbc_close_chain`, `L.tbc_head`, `RESUME_TBC_CLOSE` |
| EXTRAARG handling | runtime peek | folded by loader; EXTRAARG becomes NOP |
| TM events | 17 (`TM_N = 17`) | 24 (`TM_N = 24`; adds IDIV/BAND/BOR/BXOR/SHL/SHR/CLOSE) |
| Generator schema fields | 4 per row | 10 per row |
| `value_as_number` | single region | replaced by `value_as_integer` + `value_as_float` + `value_to_number` |
| `binop_dispatch` | `fast_number(f64, f64)` | `fast_integer(i64, i64)` + `fast_float(f64, f64)` |
| `LuaThread` fields | no TBC field | adds `tbc_head: index` |

---

*End of delta document. Read alongside `experiments/lua_interpreter_vm/README.md`. Reference source: `.vendor/Lua` (PUC Lua 5.5.0, tag `v5.5.0`).*
