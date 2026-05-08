# TRACE_LAYOUT.md — Moonlift VM Trace and Snapshot Layout

Status: canonical trace/snapshot design reference. Based on deep-dive of
lj_jit.h, lj_trace.c, lj_snap.c, lj_asm.c, lj_record.c.
Audience: VM implementors.

---

## 1. Trace Object (GCtrace)

A trace is a GC object that owns the compiled machine code, IR, and snapshots.

```
GCtrace:
  [0:8]    GCHeader                — nextgc + marked + gct (gct = GCT_TRACE)

  // IR buffer
  [8:10]   nsnap: u16              — number of snapshots
  [10:14]  nins: u32               — next IR instruction index (biased: last ins + 1)
  [14:22]  ir: ptr(IRIns)          — pointer to IR instructions/constants array
  [22:26]  nk: u32                 — lowest constant index (biased with REF_BIAS)

  // Snapshots
  [26:30]  nsnapmap: u32           — number of snapshot map entries
  [30:38]  snap: ptr(SnapShot)     — snapshot array
  [38:46]  snapmap: ptr(SnapEntry) — snapshot map (compressed entries)

  // Source location
  [46:54]  startpt: GCRef(GCproto) — prototype where trace started
  [54:62]  startpc: ptr(BCIns)     — bytecode PC where trace started
  [62:66]  startins: BCIns         — original bytecode at startpc (may be patched)

  // Machine code
  [66:70]  szmcode: u32            — size of machine code in bytes
  [70:78]  mcode: ptr(MCode)       — pointer to machine code
  [78:80]  mcloop: u16             — offset of loop start in machine code

  // Trace linkage
  [80:82]  nchild: u16             — number of child side traces
  [82:84]  spadjust: u16           — stack pointer adjustment (in bytes)
  [84:86]  traceno: u16            — trace number (TraceNo1)
  [86:88]  link: u16               — linked trace number (self for loops)
```

**Key constraint:** `traceno` and `link` are `u16` (TraceNo1) for storage
efficiency. The trace table itself is indexed by `u32` TraceNo.

---

## 2. Trace Lifecycle State Machine

```
IDLE → START → RECORD → STOP → OPTIMIZE → ASSEMBLE → COMMIT → IDLE
  ^                                                         |
  |_______ ABORT <___________________________________________|
```

### 2.1 State transition triggers

| State | Trigger | Next |
|---|---|---|
| IDLE | hotcount underflow at LOOP/CALL | START |
| IDLE | hot side exit (snap->count >= hotexit) | START |
| START | `lj_trace_ins()` called with first bytecode | RECORD |
| RECORD | loop backedge detected | STOP |
| RECORD | unsupported bytecode / guard fails | ABORT |
| STOP | IR is valid | OPTIMIZE |
| OPTIMIZE | DCE+FOLD+LOOP+NARROW+SINK done | ASSEMBLE |
| ASSEMBLE | mcode emitted (or mcode full) | COMMIT / ABORT |
| COMMIT | trace table updated, JLOOP patched | IDLE |

### 2.2 Root trace detection

A root trace forms when:
1. `J->parent == 0 && J->exitno == 0` (no parent trace)
2. The recorded bytecode reaches the starting PC (`pc == J->startpc`)
3. Frame depth returns to 0 (`framedepth == 0 && retdepth == 0`)
4. The loop event is `LOOPEV_ENTER` (not `LOOPEV_LEAVE`)

If the loop is left (LOOPEV_LEAVE), the trace is aborted with `LJ_TRERR_LLEAVE`
— the loop must actually loop back to be a valid root trace.

### 2.3 Inner loop detection

When a root trace encounters a different loop (inner loop), it normally
aborts with `LJ_TRERR_LINNER` — the strategy is "let the inner loop trace
first." But if the inner loop has been repeatedly failing to form a trace
(`innerloopleft()` returns true, meaning low trip count), the root trace
instead UNROLLS the inner loop body (up to `loopunroll` limit).

### 2.4 Side trace creation

Side traces start from a hot guard exit:
1. Guard fails in compiled mcode → exit stub calls `lj_trace_exit`
2. `snap_restore()` rebuilds interpreter state from snapshot
3. `trace_hotside()` increments `snap->count` in the PARENT trace's snapshot
4. When `snap->count >= JIT_P_hotexit` (= 10), recording starts at that PC
5. `J->parent` is set to the parent trace number, `J->exitno` to the exit number

---

## 3. Hot Side Exit Traversal

```
MCode guard fails
  → exit stub saves registers to ExitState
  → calls lj_trace_exit(J, ex)
    → snap_restore(L, T, exitno, ex)  — rebuild Lua stack from snapshot
    → trace_hotside(J, pc)            — check if this exit is hot
      → if hot: lj_trace_ins(J, pc)   — start recording side trace
      → else: return (interp continues)
```

### 3.1 Exit counters

Each snapshot has a `count: u8` field that tracks how many times its
associated guard has been taken as an exit. The counter is incremented
on EVERY exit (not just recording attempts). When `count >= JIT_P_hotexit`,
a side trace is started.

The counter is capped at `SNAPCOUNT_DONE = 255` — once a side trace has been
compiled and linked, the counter is frozen.

---

## 4. Snapshot System — The Brilliant Part

### 4.1 SnapShot entries

```
SnapShot: 16 bytes
  [0:4]   mapofs: u32    — offset into snapshot map (start of entries)
  [4:6]   ref: u16       — IR reference this snapshot is attached to
  [6:8]   mcofs: u16     — offset into machine code for this guard
  [8:9]   nslots: u8     — number of valid stack slots
  [9:10]  topslot: u8    — maximum frame extent (highest slot)
  [10:11] nent: u8       — number of compressed entries
  [11:12] count: u8      — number of times this exit has been taken
```

### 4.2 SnapEntry — Compressed Stack Slots

```
SnapEntry = u32
  [31:24] slot: u8     — stack slot number (BCReg)
  [23:0]  ref+flags    — IR reference + flags

  SNAP_FRAME     = 0x010000  — this entry is a frame boundary marker
  SNAP_CONT      = 0x020000  — this entry is a continuation slot
  SNAP_NORESTORE = 0x040000  — this slot does not need to be restored
  SNAP_SOFTFPNUM = 0x080000  — soft-float number encoding
  SNAP_KEYINDEX  = 0x100000  — traversal key index

#define SNAP(slot, flags, ref)  (((SnapEntry)(slot) << 24) + (flags) + (ref))
```

### 4.3 What gets snapshotted

**Only modified slots are recorded.** When a snapshot is taken, the system
compares each slot against its SLOAD:

```
if (slot has IR ref) {
    if (ref is SLOAD and SLOAD.slot == current_slot and !IRSLOAD_INHERIT) {
        // Slot is unmodified since it was loaded. SKIP.
        continue;
    }
    emit SnapEntry(slot, flags, ref);
}
```

This is critically important: a snapshot of 100 slots might only need 5 entries
if only 5 slots have been modified. The `snapmap` is shared across ALL snapshots
in the trace, so slots that don't change between snapshots take no space.

### 4.4 Frame links in snapshots

Frame boundaries are encoded as special entries:
- `SNAP_MKPC(pc)` — encodes the bytecode PC of a Lua frame
- `SNAP_MKFTSZ(ftsz)` — encodes frame type and size
- FR2 mode: PC and baseslot are packed into a single 64-bit entry

The snapshot restore walks these frame links backwards to rebuild the
full call stack.

### 4.5 Snapshot merging

If two guards are adjacent (no IR instructions between them), their
snapshots can be MERGED into one. This is handled by `lj_snap_add()`:

```c
if (nsnap > 0 && snap[nsnap-1].ref == cur.nins) {
    // Previous snapshot is at the same IR position. Merge.
    nsnapmap = snap[--nsnap].mapofs;
}
```

### 4.6 Snapshot usedef analysis

`snap_usedef()` performs a bytecode dataflow analysis at snapshot time to
determine which slots are actually USED after the guard. This allows the
restore to skip unused slots, reducing deoptimization cost.

The analysis scans forward through bytecode, tracking USEs and DEFs:
- USE_SLOT(s): mark slot as needed for restore
- DEF_SLOT(s): mark slot as no longer needed (multiplying by 3 creates gaps)
- At jump boundaries: only keep slots up to `minslot`

---

## 5. Trace Commit — Bytecode Patching

When a root trace is committed, the original `BC_LOOP` instruction at the
trace's start PC is patched to `BC_JLOOP`:

```c
setbc_op(startpc, BC_JLOOP);  // Patch the original bytecode
```

The patched instruction now points to the compiled trace's dispatch table
entry. On the next interpreter iteration, it jumps directly to the trace's
machine code instead of executing the interpreted loop.

For side traces, the parent trace's exit stub is patched to jump to the
side trace instead of falling back to the interpreter.

---

## 6. jit_State — The Recording Context

```
jit_State (simplified):
  state: u32              — current trace state (IDLE, START, RECORD, etc.)
  parent: TraceNo         — parent trace number (0 for root)
  exitno: ExitNo          — exit number in parent (0 for root)
  pt: ptr(GCproto)        — current prototype being recorded
  pc: ptr(BCIns)          — current bytecode PC
  startpc: ptr(BCIns)     — starting bytecode PC
  framedepth: i32         — current call frame depth
  retdepth: i32           — nested return depth
  baseslot: BCReg         — stack slot offset of frame base
  maxslot: BCReg          — maximum stack slot accessed

  // IR buffer
  irbuf: ptr(IRIns)       — IR instruction buffer
  irbuf_size: u32         — allocated size
  cur: GCtrace            — current trace being built (on stack)

  // Slot map
  slot: [LJ_MAX_JSLOTS]TRef  — stack slot → TRef mapping

  // Snapshot buffer
  snapbuf: ptr(SnapShot)      — snapshot array
  snapsize: u32               — allocated size
  snapmapbuf: ptr(SnapEntry)  — snapshot map
  snapmapsize: u32            — allocated size

  // FOLD state
  fold: { ins: IRIns, left: IRIns[2], right: IRIns[2] }  — current fold context

  // Optimization flags
  flags: u32              — JIT_F_OPT_FOLD | JIT_F_OPT_CSE | ...
  mergesnap: u8           — merge next snapshot?
  needsnap: u8            — need a snapshot at next guard?
  guardemit: IRType1      — guard type emitted at last guard
  bcskip: u8              — skip this many bytecodes on next iteration
  loopref: IRRef          — ref of last loop entry point
  loopunroll: i32         — remaining loop unroll budget
  retryrec: u8            — retry recording flag

  // Trace table
  trace: [MAX_TRACE]GCRef(GCtrace)  — global trace table

  // Penalty cache
  penalty: [PENALTY_SLOTS]HotPenalty  — penalty slots (64 entries)

  // Parameters
  param: [JIT_P__MAX]i32  — copiable JIT parameters
```

### 6.1 Penalty mechanism

When a trace aborts, the abort reason and PC are stored in a penalty slot
(64-entry cache, hashed by PC). If the same PC+reason combination is hit
repeatedly, the penalty value increases. When it exceeds a threshold,
the PC is blacklisted or given a long delay before retry.

```c
PENALTY_SLOTS = 64      — must be power of 2
PENALTY_MIN   = 72      — minimum penalty
PENALTY_MAX   = 60000   — maximum penalty
```

The penalty value decays over time (halved on each full GC cycle), allowing
blacklisted code to be retried eventually if the runtime situation changes.

---

## 7. TraceLink — How Traces Connect

```c
LJ_TRLINK_NONE     — incomplete trace (still recording)
LJ_TRLINK_ROOT     — links to another root trace
LJ_TRLINK_LOOP     — loops to self (same trace)
LJ_TRLINK_TAILREC  — tail-recursion link
LJ_TRLINK_UPREC    — up-recursion
LJ_TRLINK_DOWNREC  — down-recursion
LJ_TRLINK_INTERP   — fallback to interpreter
LJ_TRLINK_RETURN   — return to interpreter
LJ_TRLINK_STITCH   — stitch to another trace
```

`lj_record_stop(J, linktype, lnk)` terminates recording with a specific link:
- `LJ_TRLINK_LOOP` + `J->cur.traceno` → self-looping trace
- `LJ_TRLINK_ROOT` + `other_trace` → chain to another root trace
- `LJ_TRLINK_INTERP` → compiled code falls back to interpreter after trace

---

## 8. MCode Arena — Machine Code Memory

```
MCodeArea:
  next: ptr(MCodeArea)    — linked list of arena chunks
  size: u32               — size of this chunk
  top: ptr(MCode)         — current allocation pointer (grows down)
  bot: ptr(MCode)         — bottom of usable memory
  limit: ptr(MCode)       — hard limit (with red zone)
```

MCode grows DOWNWARD from the top of each arena chunk. When a trace is
assembled, the assembler writes code from `top` downward, checking against
`limit` (which includes a small red zone for overflow detection).

If an arena chunk fills up, a new chunk is allocated and linked. Traces
never span arena boundaries.

### 8.1 Exit stubs

Each guard in the mcode has an associated exit stub — a small piece of code
that:
1. Stores all live registers to the ExitState structure
2. Computes the exit number
3. Calls `lj_trace_exit` with the exit state

Exit stubs are emitted at the end of the mcode (growing upward from
`bot`), while the main trace code grows downward from `top`. This reduces
fragmentation.

---

## 9. Snapshot Restore — Deoptimization

When a guard fails and a side trace is NOT being compiled:

1. `lj_trace_exit()` calls `lj_snap_restore()`
2. The snapshot is looked up by exit number
3. The snapshot map is walked entry by entry:
   - Each SnapEntry provides `slot` and `ref`
   - `ref` identifies the IR instruction that produced the slot's value
   - The IR instruction is evaluated (or its spilled register is restored)
   - The value is written back to `L->stack[slot]`
4. Frame boundaries rebuild the call chain
5. The PC is extracted from the first frame link
6. Control returns to the interpreter at the restored PC

**The restore is lazy:** only slots that actually differ from their SLOAD
are restored. Unmodified slots are left as-is on the stack.

**Soft-float special case:** On ARM soft-float targets, numbers are stored
as two 32-bit words. `SNAP_SOFTFPNUM` marks these entries.

---

## 10. Trace Stitching

When a trace finishes and another trace immediately follows (e.g., call→return),
the traces can be "stitched" — the first trace's exit branches directly to
the second trace's entry point without passing through the interpreter.

`cont_stitch` (in vm_x64.dasc) handles the glue:
1. Copies return values down the stack
2. Checks if more results are needed (fills with nil)
3. Jumps to the stitched trace (JLOOP) or falls back to interpreter

---

## 11. Constant Summary

| Constant | Value | Meaning |
|---|---|---|
| `REF_BIAS` | 0x8000 | Constant/instruction boundary |
| `LJ_MAX_JSLOTS` | 250 | Max stack slots per trace |
| `JIT_P_hotloop` | 56 | Hot loop threshold (in ITERATIONS) |
| `JIT_P_hotexit` | 10 | Hot side exit threshold |
| `HOTCOUNT_LOOP` | 2 | Decrement per loop iter |
| `HOTCOUNT_CALL` | 1 | Decrement per call |
| `PENALTY_SLOTS` | 64 | Penalty cache entries |
| `PENALTY_MIN` | 72 | Min penalty value |
| `PENALTY_MAX` | 60000 | Max penalty value |
| `SNAPCOUNT_DONE` | 255 | Side trace compiled marker |
| `HOTCOUNT_SIZE` | 64 | Hotcount hash buckets |
| `LJ_TRLINK_LOOP` | 2 | Self-looping trace link |
| `LJ_TRLINK_ROOT` | 1 | Link to other root trace |
| `LJ_TRLINK_INTERP` | 6 | Fallback to interpreter |
