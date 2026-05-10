# LuaJIT VM Architecture Audit

Date: 2026-05-09

This audit records places where the current Moonlift LuaJIT VM bring-up diverges from the intended architecture in `docs/MOONLIFT_LUAJIT_VM_ARCHITECTURE.md`.  It is intentionally conservative: passing smoke tests are not treated as proof of architectural correctness.

## Current Remediation Status

The first cleanup pass fixed the highest-risk interpreter architecture issues:

- dispatch now stores/currently threads bytecode base + pc in `ThreadState` extension fields;
- `BC_CALL` switches to callee bytecode instead of reusing the initial dispatch `bc`;
- `RET/RET0/RET1` restore caller bytecode/base from an explicit CallInfo stack;
- `TNEW.need_alloc` is a typed top-level interpreter suspension, not a runtime error;
- table-store barrier edges now mark black tables gray;
- recorder SLOAD now reads the canonical TValue tag offset;
- upvalue current-function lookup now reads the function slot below `base`.

Remaining sections below describe the original findings and any still-open work.

## Executive Summary

The current interpreter started as a useful opcode smoke-test harness, but was not yet a coherent LuaJIT VM runtime model.  The largest architectural fault was exactly the suspected one: `runtime/dispatch.mlua` treated the bytecode array as a fixed `bc: ptr(u32)` parameter, while the architecture says dispatch should load from `L->pc` / current frame state.  This blocked correct Lua calls, returns, trace entry, snapshot restore, and any execution that switches bytecode streams.

A second class of faults comes from local simplifications that bypass the canonical object/state layouts and protocols: table allocation turns into an error in top-level dispatch, write barriers are acknowledged but not executed, metamethod protocol exits are converted to errors, globals use integer D indices instead of string constants, and recorder/snapshot paths use incompatible TValue assumptions.

## P0: Must Fix Before Implementing CALL / JIT Integration

### A1. Dispatch owns a fixed bytecode pointer instead of VM state owning current PC/BC — FIXED for interpreter dispatch/CALL/RET

**Files:** `mlua/luajitvm/runtime/dispatch.mlua`, `mlua/luajitvm/core/state.mlua`

Current:

```moonlift
region vm_loop(L: ptr(u8), bc: ptr(u32), pc: i32, status: i32) -> proto.InterpResult
...
let ins: u32 = bc[ip]
```

Architecture expects dispatch to load from thread/frame state:

```moonlift
let bc = load(L.pc)
```

Consequences:

- `BC_CALL` cannot switch to callee bytecode without re-entering the entire exported function or inventing an ad-hoc continuation.
- `RET` cannot restore caller bytecode stream.
- `TS_OFF_PC` currently stores only an `i32` instruction offset, not a `ptr(BCIns)` as the architecture text describes.
- Snapshot restore cannot resume into an arbitrary trace/source PC because there is no single canonical current-PC pointer.
- Hot-loop recording gets only integer offsets, not stable bytecode pointers.

Required direction:

- Make the dispatch state carry a current bytecode pointer and PC together, either:
  - `L->pc: ptr(u32)` plus dispatch reads `L->pc[0]`, advances/stores pointer; or
  - explicit typed dispatch state `(bc: ptr(u32), ip: i32)` threaded through `next`, `call`, `return`, and snapshot restore continuations.
- Do not implement CALL as `error(code)` or by assuming the initial `bc` remains valid.

### A2. Return handling is top-level only; no frame protocol exists — FIXED for explicit CallInfo frames

**Files:** `runtime/call.mlua`, `runtime/dispatch.mlua`, `core/state.mlua`, `core/func.mlua`, `core/proto.mlua`

Current `RET/RET0/RET1` immediately jump to `returned(...)`. That works for single top-level test programs but cannot resume callers.

Consequences:

- No caller/callee frame marker.
- No return-PC/return-BC restoration.
- No result shuffling for function calls.
- `ReturnResult` protocol (`resume_caller`, `final_return`, `close_upvalues`) exists but is not used by dispatch.

Required direction:

- Define one canonical frame representation before CALL.
- `RET` opcode bodies must return typed `ReturnResult`-style edges or equivalent typed continuations: `resume_caller(bc, ip)`, `final_return(nresults)`, `close_upvalues(from, then_bc, then_ip)`, `error(code)`.

### A3. Function/proto relationship is underspecified and internally inconsistent — PARTIAL

**Files:** `core/func.mlua`, `core/proto.mlua`, `runtime/upvalue.mlua`

Current `core/func.mlua` says `GCfuncL` has `pc` at offset 32, while `core/proto.mlua` defines bytecode as following `GCproto`. The code has no canonical helper for `func -> proto -> bytecode`.

`runtime/upvalue.mlua` says current function lives at `L->base - 1`, but implementation reads payload at current `base`:

```moonlift
let fn_payload: i64 = as(ptr(i64), base)[1]
```

That is slot 0 payload, not the slot below base.

Required direction:

- Define and test canonical helpers:
  - current frame's function pointer,
  - function's proto pointer,
  - proto bytecode pointer,
  - proto constants/KGC/KN.
- Fix upvalue lookup to use the frame representation, not slot 0 by accident.

## P1: Runtime Protocols Currently Bypassed

### B1. Table allocation protocol exits become top-level errors — FIXED as typed interpreter suspension

**Files:** `runtime/table.mlua`, `runtime/dispatch.mlua`, `gc/alloc.mlua`

`vmop_tnew` correctly exposes `TableNew.need_alloc`, but dispatch maps it to `error(code = 8)`.

This is acceptable only as a smoke-test signal, not as VM architecture. A VM dispatcher must integrate allocation protocol edges with `gc_alloc` / GC stepping / retry.

### B2. Write barrier protocol is ignored at table stores — FIXED for table back-barrier marking

**Files:** `runtime/table.mlua`, `gc/barrier.mlua`

`table_set` exposes `need_barrier(...)`, but `vmop_tsetv` and `vmop_tsetb` handle it as `next(ip+1)` without emitting a barrier region.

This can corrupt incremental GC invariants once real GC marking exists.

### B3. Metamethod exits become errors or are never reached

**Files:** `runtime/table.mlua`, `runtime/meta.mlua`, `runtime/arith.mlua`, `runtime/compare.mlua`

`runtime/meta.mlua` implements lookup/negative cache, but table get/set never call it; `TableGet.meta`/`TableSet.meta` are converted to `error(code = 3)`. Arithmetic and comparison fast paths do not check tags or route to metamethods.

### B4. Global access uses D as an integer key, not a string constant

**File:** `runtime/global.mlua`

Comment says `GGET/GSET use the string constant at index D`, but implementation treats `D` itself as an integer key into env array. This avoids proto constants and string interning, so it will not execute real LuaJIT bytecode semantics.

## P1: Bytecode Coverage / Decoder Issues

### C1. Dispatch constants are hand-duplicated and incomplete

**Files:** `core/bytecode.mlua`, `runtime/dispatch.mlua`, `generated/opcodes.mlua`

`core/bytecode.mlua` defines opcodes through `FUNCCW=96`. Dispatch handles only a subset and hardcodes numeric `case` labels. `generated/opcodes.mlua` is also incomplete relative to `core/bytecode.mlua`.

Missing from dispatch include: `KSTR`, `KNUM`, `FNEW`, `TDUP`, `TGETS`, `TSETS`, `CALLM`, `CALL`, `CALLMT`, `CALLT`, `ITERC`, `ITERN`, `VARG`, `ISNEXT`, `RETM`, `JFORI`, `IFORL`, `JFORL`, `ITERL`, `JLOOP`, `FUNCF/FUNCV/FUNCC`, etc.

### C2. Some signed D decoding remains ambiguous

Several modules use `(as(i32, ins) >> 16) & 0xFFFF`; this is safe only with the mask. For signed jumps, every opcode must use a single canonical `s16(bc_d(ins))` helper. Previous FORL failure came from signed shifting without proper masking.

Required direction:

- Use `core/bytecode.mlua` decoders everywhere instead of per-module copies, or generate per-module-prefixed wrappers from one source.

## P1: TValue/Layout Inconsistencies

### D1. Recorder reads TValue tag from the wrong offset — FIXED

**File:** `jit/record.mlua`

Core layout is `[tag:i32@0][pad:i32@4][payload:i64@8]`, but `rec_sload` comments and code read tag at offset `slot*16 + 8`:

```moonlift
let tag_off: i32 = slot * 4 + 2
let tag: i32 = tv_base[tag_off]
```

That reads payload low bits as tag. The value is then ignored and `IRT_INT|GUARD` is emitted unconditionally. This means recorder tests do not validate runtime TValue typing.

### D2. Multiple local copies of TValue constants and layout helpers

Runtime modules define their own `LUA_T*` constants and stack helpers. This already caused `LUA_TINT` drift earlier. It will recur unless runtime modules import `core.value` and `core.state` consistently.

## P2: JIT / Snapshot / Exit Integration Gaps

### E1. Hotcount path is not wired

`LOOP` just jumps; there is no `OpcodeResult.hot(pc)` edge from interpreter to recorder.

### E2. Trace recording entry is disconnected

`trace_record_root` and `trace_record_side` return `interpret()` unconditionally. Recorder opcode regions exist mostly as low-level test helpers.

### E3. Snapshot restore is unsupported

`snap_restore` returns `unsupported(code=0)`. Exit stubs cannot restore interpreter state.

### E4. Exit stub uses sentinel-style deopt

`asm/asm_state.mlua` emits a shared `DEOPT_SENTINEL`; `asm/x64_exit.mlua` returns `mcode_full()`. This is explicitly not a real snapshot/deopt protocol.

## P2: Remaining Stub/Error Smells

Examples:

- `runtime/call.mlua`: `vm_bc_call` jumps `error(code=0)`.
- `runtime/arith.mlua`: catalog protocol regions jump `error(code=0)`.
- `jit/record.mlua`: canonical recorder opcode regions jump `abort(reason=0)`.
- `ffi/*`: FFI regions jump `error(code=0)` / `mcode_full()`.
- `gc/gc.mlua`, `gc/mark.mlua`, `gc/sweep.mlua`: phase stubs.
- `jit/snap.mlua`: `snap_restore` unsupported.
- `asm/regalloc.mlua`: exported `regalloc_get` uses `return -1` for not assigned; not in hot region path, but still violates the no-sentinel style for public helpers.

## Recommended Fix Order

1. **Define canonical interpreter execution state**: current bytecode pointer, current pc/ip, base/top, frame marker, current function/proto.
2. **Refactor dispatch around mutable/threaded current BC/PC**, not fixed initial `bc`.
3. **Refactor RET into typed frame-unwind protocol** before CALL.
4. **Implement CALL using that protocol**, including callee bytecode switch.
5. **Fix current function/upvalue lookup** to use frame state.
6. **Route table allocation/barrier/metamethod protocol edges** instead of converting them to `error`/`next`.
7. **Fix recorder TValue layout and connect hotcount → trace_record_root**.
8. **Only then implement snapshot restore / exit stubs**, since they depend on canonical frame/PC state.

## Current Test Status

After restoring the accidental bad CALL rewrite, these pass:

- `luajit tests/test_luajitvm_skeleton.lua`
- `luajit tests/test_interpreter_run.lua`

Passing status means the smoke-test subset works; it does not validate CALL, frame switching, constants/protos, real globals, metamethod calls, allocation integration, recorder correctness, or deopt.
