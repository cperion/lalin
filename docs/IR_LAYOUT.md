# IR_LAYOUT.md — Moonlift VM SSA IR Layout

Status: canonical IR design reference. Based on deep-dive of lj_ir.h, lj_opt_fold.c, lj_record.c.
Audience: VM implementors.

---

## 1. The Core Insight: Two-Phase Field Sharing

The IR instruction is 64 bits. During recording, the `r` and `s` fields overlap
the CSE chain pointer `prev`. After recording, `prev` is no longer needed and
`r`/`s` store register/spill allocation.

```
IRIns (64 bits):

During recording:
  [15:0]  op1: u16     — first operand (IRRef1)
  [31:16] op2: u16     — second operand (IRRef1)
  [39:32] t: u8        — IR type
  [47:40] o: u8        — IR opcode
  [63:48] prev: u16    — CSE chain link

During assembly:
  [15:0]  op1: u16     — same
  [31:16] op2: u16     — same
  [39:32] t: u8        — same
  [47:40] o: u8        — same
  [55:48] s: u8        — spill slot
  [63:56] r: u8        — register allocation
```

Alternative views (union):
```
  op12: u32            — op1+op2 as single word
  ot: u16              — opcode+type packed
  i: i32               — constant overlay of op12 (KINT)
  gcr: GCRef           — GC constant overlay
  tv: TValue           — TValue constant (uses 2 IRIns slots for 64-bit)
```

This field-sharing saves 2 bytes per IR instruction compared to a naive layout.

---

## 2. REF_BIAS — The Constant/Instruction Divide

```
REF_BIAS     = 0x8000

Constants grow downward:
  REF_NIL     = REF_BIAS - 1   = 0x7FFF
  REF_FALSE   = REF_BIAS - 2   = 0x7FFE
  REF_TRUE    = REF_BIAS - 3   = 0x7FFD
  ...user constants below...

Instructions grow upward:
  REF_BASE    = REF_BIAS       = 0x8000   (first real instruction)
  REF_FIRST   = REF_BIAS + 1   = 0x8001
  ...
```

**Why this matters:** `ref < REF_BIAS` is a CONSTANT, `ref >= REF_BIAS` is an
INSTRUCTION. A single unsigned comparison answers "is this a constant?".

Every IR pass exploits this:
- **CSE:** computes `max(ref1, ref2)` for dominance — works for both constants
  and instructions because REF_BIAS is the boundary.
- **DCE:** marks used instructions by checking `operand >= REF_BIAS`.
- **LOOP:** substitutes instruction operands (>= REF_BIAS) with loop-variant
  equivalents. Constant operands (< REF_BIAS) are never modified.

---

## 3. TRef — Type-Tagged References

```
TRef = u32
  [31:24] irt:  u8   — IR type (IRT_*), bit-copy of IRIns.t
  [23:16] flags: u8  — TREF_FRAME, TREF_CONT, TREF_KEYINDEX
  [15:0]  ref:  u16  — IR reference (IRRef1)

TREF(ref, type) = ref + (type << 24)
```

**Why copy the type into the reference?** The recorder checks types constantly.
Chasing the IRIns pointer to read `.t` would be a cache miss on every check.
`TRef` carries the type inline: `tref_isnum(tr)` compiles to a register
comparison against an immediate.

```c
tref_istype(tr, t)     = ((tr) & (IRT_TYPE<<24)) == ((t)<<24)    // exact match
tref_typerange(tr, f,l)= (((tr>>24) & IRT_TYPE) - f <= l-f)      // range check
tref_isnum(tr)         = tref_istype(tr, IRT_NUM)
tref_isinteger(tr)     = tref_typerange(tr, IRT_I8, IRT_INT)
tref_isnumber(tr)      = tref_typerange(tr, IRT_NUM, IRT_INT)
tref_isk(tr)           = irref_isk(tref_ref(tr))
```

The `IRT_TYPE` ordering is deliberately arranged for range checks:
`IRT_NIL < IRT_FALSE < IRT_TRUE < IRT_LIGHTUD < IRT_NUM < IRT_I8 < ...`

---

## 4. IR Opcode Taxonomy

### 4.1 Guard ordering (flip opposites with XOR)

```
IR_LT  ^ 1 == IR_GE    // flip comparison direction
IR_LE  ^ 1 == IR_GT
IR_ULT ^ 1 == IR_UGE
IR_ULE ^ 1 == IR_UGT
IR_EQ  ^ 1 == IR_NE
IR_LT  ^ 3 == IR_GT    // flip both direction and signedness
IR_LT  ^ 4 == IR_ULT   // flip signedness only
```

The optimizer flips guard directions with a single XOR — no lookup table.

### 4.2 Load/Store delta

```
IR_ASTORE - IR_ALOAD == IRDELTA_L2S  (same for H, U, F, X)
```

The optimizer converts loads to stores by adding IRDELTA_L2S to the opcode.

### 4.3 Operand modes

```
IRM_N  — normal (ref, ref)
IRM_C  — commutative (ref, ref) — operand order doesn't matter
IRM_L  — load (ref, none-or-lit)
IRM_S  — store (ref, ref) — has side effects
IRM_A  — allocation (ref, ref) — may trigger GC
IRM_W  — wide (weak guard) — can be eliminated
```

`ir_sideeff()` checks: `(ir->t.irt | ~IRT_GUARD) & mode >= IRM_S`

---

## 5. IR Type System (IRT_*)

Types are ordered for range-check efficiency:

```
IRT_NIL     = 0    IRT_FALSE   = 1    IRT_TRUE    = 2
IRT_LIGHTUD = 3    IRT_NUM     = 4
IRT_I8      = 5    IRT_U8      = 6    IRT_I16     = 7    IRT_U16     = 8
IRT_INT     = 9    IRT_U32     = 10   IRT_I64     = 11   IRT_U64     = 12
IRT_FLOAT   = 13
IRT_STR     = 14   IRT_TAB     = 15   IRT_FUNC    = 16
IRT_CDATA   = 17   IRT_UDATA   = 18   IRT_THREAD  = 19   IRT_PROTO   = 20
IRT_P32     = 21   IRT_P64     = 22   IRT_PGC     = 23

IRT_GUARD   = 0x80 — guard bit (ORed with type)
```

---

## 6. FOLD Engine — The Precomputed Hash Table

### 6.1 Design

The FOLD engine receives one instruction at a time during recording. It builds
a 24-bit key from the opcode and operand opcodes, then looks up a precomputed
hash table to find the matching fold function.

**This is NOT a runtime rule engine.** All 500+ fold rules are compiled into
a semi-perfect hash table at build time by `buildvm_fold.c`. The runtime is
just hash lookup + function call.

### 6.2 Key construction

```
key = (uint32_t)fins->o << 17
if fins->op1 >= J->cur.nk:  key += IR(fins->op1)->o << 10  // instruction operand
if fins->op2 >= J->cur.nk:  key += IR(fins->op2)->o         // instruction operand
else:                       key += fins->op2 & 0x3ff        // literal operand
```

24-bit key: `| ins_op (8 bits) | left_op (7 bits) | right_op (10 bits) |`

### 6.3 Wildcard matching (4 attempts)

```
1. any = 0x000000 → key = ins | left  | right
2. any = 0x0ffc00 → key = ins | any   | right
3. any = 0x0ffc3f → key = ins | left  | any
4. any = 0x0fffff → key = ins | any   | any
```

After 4 failed probes, the instruction passes to CSE and is emitted.

### 6.4 Fold return values

```
RETRYFOLD  — instruction modified in-place; retry from scratch
NEXTFOLD   — no match; try less specific wildcard
EMITFOLD   — emit directly (bypass CSE)
CSEFOLD    — pass to CSE
INTFOLD(i) — return integer constant TRef
LEFTFOLD   — return left operand TRef
RIGHTFOLD  — return right operand TRef
FAILFOLD   — guard would always fail; abort trace
DROPFOLD   — guard is always true; eliminate it
CONDFOLD   — drop if true, fail otherwise
```

### 6.5 Why this is fast

1. No branch tree — direct hash lookup, compute key, probe
2. Precomputed at build time — `lj_folddef.h` contains the hash table
3. Fewer than 4 probes per instruction on average
4. Fold functions are tiny — each handles exactly one opcode pattern
5. RETRYFOLD for rewrites — no recursive fold stack

---

## 7. CSE — Common Subexpression Elimination

CSE uses a simple hash chain: instructions with the same opcode+mode are
linked via `prev`. For each new instruction:

1. Hash opcode → find chain head
2. Walk chain, compare operands
3. Match found → return existing ref (CSE hit)
4. No match → link to chain head

`prev` is only needed during RECORDING. After recording stops, `r` and `s`
overwrite it for register allocation.

---

## 8. SLOAD and Slot Map

During recording, `J->slot[stack_slot] = TRef` tracks which TRef corresponds
to each Lua stack slot.

First access: emit SLOAD(slot) with type guard; store ref.
Subsequent: read J->slot[s] — no new IR needed.

**SLOAD flags (op2):**
```
IRSLOAD_TYPECHECK  — runtime type check (guard)
IRSLOAD_READONLY   — slot never written (no snapshot restore needed)
IRSLOAD_INHERIT    — inherited by side traces
IRSLOAD_PARENT     — coalesced with parent trace SLOAD
IRSLOAD_CONVERT    — number-to-integer conversion
IRSLOAD_FRAME      — load frame type/size (32 bits)
```

---

## 9. IR Buffer Layout

```
[low addresses]
... user constants (KINT, KGC, KNUM...) ...
REF_NIL, REF_FALSE, REF_TRUE     <-- REF_BIAS - 3
                REF_BIAS = 0x8000
IR_BASE (NOP)                     <-- REF_BASE (first instruction)
... instructions (ADD, MUL...) ...
[high addresses]                  <-- J->cur.nins (next emit position)
```

REF_NIL, REF_FALSE, REF_TRUE are always available — no emission needed.

---

## 10. 64-bit Constants

Constants that don't fit in two u16 operands (KNUM, KINT64, GC64-pointers)
use TWO consecutive IRIns slots:
```c
ir_knum(ir)   -> &(ir)[1].tv   // double in second slot
ir_kint64(ir) -> &(ir)[1].tv   // int64 in second slot
```
`nins` skips by 2 for 64-bit constants.

---

## Build-Time Generation Note

The fold hash table (`lj_folddef.h`) and IR metadata (`lj_ir_mode[]`) are
generated by `buildvm_fold.c` and `buildvm_asm.c` at build time. In Moonlift,
these will be Lua scripts producing `.mlua` modules with the equivalent tables.
