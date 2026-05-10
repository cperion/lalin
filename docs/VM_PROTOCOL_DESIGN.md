# Moonlift VM Protocol Design

> Protocol-first design for the Moonlift LuaJIT-grade VM.
>
> Every implicit control contract in LuaJIT C becomes an explicit named protocol type.
> Every implicit flag, error code, mutable state, and longjmp boundary becomes a
> typed region exit. The protocol catalog below is the architectural contract —
> not the implementation, but the shape every implementation must satisfy.

---

## 1. The Core Insight

LuaJIT C encodes multi-outcome control as:

```c
TraceError e = LJ_TRERR_RECERR;
// or
J->state = LJ_TRACE_ERR;
// or
lj_err_throw(L, LUA_ERRRUN);
// or
return 1; /* "handled" */
```

None of these are visible in a function signature. The reader must understand
the global protocol to know what `return 1` means in a given context.

In Moonlift VM, every such boundary is a protocol type:

```moonlift
type TraceRecord = compiled(tr: TraceNo) | interpret() | abort(reason: TraceAbort)

region trace_record_root(J: ptr(JitState), L: ptr(ThreadState), pc: ptr(BCIns)) -> TraceRecord
```

The signature IS the contract. The compiler checks every exit.

---

## 2. Primitive Types

These are not protocol exit types — they are the scalar/struct types that
fields and payloads are built from.

```moonlift
-- Bytecode instruction: 32-bit packed (op:u8, A:u8, B:u8, C:u8) or (op:u8, A:u8, D:u16)
-- Represented as u32. Decoded by helper regions.

-- IR reference: biased index into IR buffer.
-- ref < REF_BIAS => constant; ref >= REF_BIAS => instruction
-- Represented as u16 during recording, u32 in full IR.

-- Typed reference: (IRType:8 | IRRef:24) packed into u32

-- Trace number: u32 index into global trace table
-- Snapshot number: u32 index into trace snapshot array
-- Exit number: u32 identifying a guard exit stub
-- Register: u8 physical register number
-- Bytecode register: u8 stack slot relative to base

-- TValue: explicit-tag representation for bring-up.
-- Designed so NaN-boxing can replace it behind helper regions.
struct TValue
    tag: i32
    pad: i32
    payload: i64    -- integer, float bits, or GC pointer as i64
end

-- GC object header shared by all collectable objects
struct GCHeader
    next: ptr(GCobj)
    marked: u8
    gct: u8
end
```

---

## 3. Error and Abort Types

These are **data types** (not protocol exit types). They carry the reason for an
outcome through protocol exit parameters.

```moonlift
-- Trace abort reasons, matching lj_traceerr.h TREDEF table exactly.
type TraceAbort
    = recerr()          -- error thrown or hook called during recording
    | traceov()         -- trace too long
    | stackov()         -- trace too deep
    | snapov()          -- too many snapshots
    | blackl()          -- blacklisted
    | retry()           -- retry recording
    | nyibc(bc: i32)    -- NYI: bytecode
    | lleave()          -- leaving loop in root trace
    | linner()          -- inner loop in root trace
    | lunroll()         -- loop unroll limit reached
    | badtype()         -- bad argument type
    | cjitoff()         -- JIT disabled for function
    | cunroll()         -- call unroll limit reached
    | downrec()         -- down-recursion, restarting
    | nyiffu(id: i32)   -- NYI: FastFunc variant
    | nyiretl()         -- NYI: return to lower frame
    | storenn()         -- store with nil or NaN key
    | nomm()            -- missing metamethod
    | idxloop()         -- looping index lookup
    | nyitmix()         -- NYI: mixed sparse/dense table
    | nocache()         -- symbol not in cache
    | nyiconv()         -- NYI: C type conversion
    | nyicall()         -- NYI: C function type
    | gfail()           -- guard would always fail
    | phiov()           -- too many PHIs
    | typeins()         -- persistent type instability
    | mcodeal()         -- failed to allocate mcode memory
    | mcodeov()         -- machine code too long
    | mcodelm()         -- hit mcode limit (retrying)
    | spillov()         -- too many spill slots
    | badra()           -- inconsistent register allocation
    | nyiir(op: i32)    -- NYI: IR instruction
    | nyiphi()          -- PHI shuffling too complex
    | nyicoal()         -- register coalescing too complex
end

-- Runtime error kind
type RuntimeErrorKind
    = lua_error(msg: ptr(GCobj))
    | type_error(got: i32, expected: i32)
    | arith_error(op: i32)
    | oom()
    | stack_overflow()
end

-- Trace link kind (how a trace exits to the next trace or interpreter)
type TraceLink
    = loop()                        -- loops back to trace head
    | root(tr: i32)                 -- links to another root trace
    | side(tr: i32, exitno: i32)    -- enters a side trace
    | interp()                      -- falls back to interpreter
    | return_trace()                -- return from inlined call
end
```

---

## 4. Protocol Catalog

### 4.1 Interpreter Protocols

```moonlift
-- Top-level interpreter result: what vm_resume returns to the embedder.
type InterpResult
    = returned(nresults: i32)
    | yielded(code: i32)
    | need_table_alloc(asize: i32, hmask: i32, ins: u32, ip: i32)
    | need_func_alloc(pt: ptr(GCproto), nupvalues: i32, ins: u32, ip: i32)
    | need_string_concat(a: i32, b: i32, c: i32, ins: u32, ip: i32)
    | need_iterator(kind: i32, a: i32, ins: u32, ip: i32)
    | metamethod_call(mm: TValue, ins: u32, ip: i32)
    | hot(pc: ptr(BCIns))
    | error(kind: RuntimeErrorKind)

-- Result of a single opcode handler.
-- hot: this PC is now hot enough to enter the recorder.
type OpcodeResult
    = next()
    | hot(pc: ptr(BCIns))
    | yield(code: i32)
    | error(kind: RuntimeErrorKind)

-- Result of a call sequence.
type CallResult
    = lua_call(fn: ptr(GCfuncL))
    | native_call(fn: ptr(GCfuncC))
    | metamethod(mm: TValue)
    | error(kind: RuntimeErrorKind)

-- Result of a return sequence.
type ReturnResult
    = resume_caller()
    | final_return()
    | close_upvalues(from: ptr(TValue))
    | error(kind: RuntimeErrorKind)
```

### 4.2 Table and Metamethod Protocols

```moonlift
-- Result of a table key lookup.
-- nil_no_meta: key missing and no __index.
-- meta: key missing, __index present, mm is the metamethod value.
type TableGet
    = hit(val: TValue)
    | nil_no_meta()
    | meta(mm: TValue)
    | error(kind: RuntimeErrorKind)

-- Result of a table key store.
-- need_barrier: store succeeded but requires GC write barrier.
-- new_key: new key inserted (may trigger rehash on next call).
-- meta: __newindex triggered.
type TableSet
    = done()
    | need_barrier(parent: ptr(GCobj), child: TValue)
    | new_key()
    | meta(mm: TValue)
    | error(kind: RuntimeErrorKind)

-- Result of a metamethod dispatch lookup.
type MetamethodResult
    = found(fn: TValue, lhs: TValue, rhs: TValue)
    | not_found()
    | error(kind: RuntimeErrorKind)
```

### 4.3 GC Protocols

```moonlift
-- Result of allocating a new GC object.
-- step: allocation succeeded but GC step is due (budget: bytes requested).
-- oom: allocation failed.
type AllocResult
    = ok(obj: ptr(GCobj))
    | step(budget: usize)
    | oom()

-- Result of a single incremental GC step.
type GCStepResult
    = done(used: i32)
    | need_finalize()
    | oom()
    | error(kind: RuntimeErrorKind)

-- Result of a GC write barrier check.
-- always done() — but the call site is explicit and compiler-visible.
type BarrierResult
    = done()
```

### 4.4 Trace Lifecycle Protocols

```moonlift
-- Result of recording a root trace.
type TraceRecord
    = compiled(tr: i32)
    | interpret()
    | abort(reason: TraceAbort)

-- Result of recording a side trace (from a hot guard exit).
type TraceRecordSide
    = compiled(tr: i32)
    | stitch(tr: i32)   -- new side trace stitched to parent
    | interpret()
    | abort(reason: TraceAbort)

-- Result of committing a compiled trace to the runtime.
type TraceCommit
    = root_patched(tr: i32)
    | side_patched(tr: i32)
    | abort(reason: TraceAbort)

-- What happens at a hot side exit.
type HotExit
    = resume_interp()
    | start_side(parent: i32, exitno: i32)
    | blacklist()
    | error(kind: RuntimeErrorKind)
```

### 4.5 IR Builder Protocols

```moonlift
-- Result of emitting one IR instruction through the FOLD/CSE pipeline.
-- retry: FOLD rule requests re-emission with different op/operands.
-- need_snapshot: instruction is a guard and requires a snapshot.
-- overflow: IR buffer exhausted.
type IREmit
    = result(ref: i32)
    | retry(ot: i32, a: i32, b: i32)
    | need_snapshot(guard: i32)
    | overflow()
    | abort(reason: TraceAbort)

-- Result of applying FOLD rules to one instruction.
-- replace: rule produces a replacement TRef (no new instruction emitted).
-- emit: rule passes through, instruction should be emitted.
-- retry: rule rewrote the instruction, run fold again.
type FoldResult
    = replace(ref: i32)
    | emit(ot: i32, a: i32, b: i32)
    | retry(ot: i32, a: i32, b: i32)
    | abort(reason: TraceAbort)

-- Result of a slot map access during recording.
-- have: slot already has a TRef.
-- need_sload: first access, must emit SLOAD with type guard.
type SlotGet
    = have(ref: i32)
    | need_sload(slot: i32, val: TValue)
    | abort(reason: TraceAbort)
```

### 4.6 Snapshot Protocols

```moonlift
-- Result of adding a snapshot to the snapshot buffer.
-- merge: existing snapshot at this IR ref was reused.
-- overflow: snapshot buffer exhausted.
type SnapAdd
    = done(snapno: i32)
    | merge(snapno: i32)
    | overflow()
    | abort(reason: TraceAbort)

-- Result of restoring interpreter state from a snapshot after a guard exit.
type SnapRestore
    = restored(pc: ptr(BCIns))
    | unsupported(code: i32)
    | error(kind: RuntimeErrorKind)
```

### 4.7 Optimizer Protocols

```moonlift
-- Overall optimizer pipeline result.
type OptResult
    = optimized()
    | retry_recording(reason: i32)
    | abort(reason: TraceAbort)

-- Dead-code elimination pass result.
type DCEResult
    = done()
    | abort(reason: TraceAbort)

-- Loop optimization pass result.
-- not_loop: trace is not a loop trace, skip.
-- overflow: PHI insertion exceeded limits.
type LoopOptResult
    = done()
    | not_loop()
    | overflow()
    | abort(reason: TraceAbort)

-- Allocation sinking pass result.
-- disabled: sinking not applicable (no eligible allocations).
type SinkResult
    = done()
    | disabled()
    | abort(reason: TraceAbort)

-- Narrowing pass result.
type NarrowResult
    = done()
    | abort(reason: TraceAbort)
```

### 4.8 Register Allocator Protocols

```moonlift
-- Result of allocating a register for an IR ref (as a source operand).
-- remat: ref was rematerialized from a constant/invariant (no spill reload needed).
-- spill_and_retry: a victim was evicted to a spill slot; caller must retry.
type RAAlloc
    = reg(r: i32)
    | remat(r: i32)
    | spill_and_retry(victim: i32)
    | fail(code: i32)

-- Result of allocating a destination register for a definition.
-- spill: a victim register was spilled to make room.
type RADest
    = reg(r: i32)
    | spill(victim: i32)
    | fail(code: i32)

-- Result of coalescing a PHI pair.
type RACoalesce
    = coalesced(r: i32)
    | conflict()
    | abort(reason: TraceAbort)
```

### 4.9 Assembler Protocols

```moonlift
-- Top-level trace assembler result.
-- retry_realign: mcode pointer misaligned, retry with aligned base.
-- retry_ir_grew: IR buffer was reallocated during assembly, retry from scratch.
-- mcode_full: no mcode arena space left for this trace.
type AsmResult
    = mcode(entry: ptr(u8), size: usize)
    | retry_realign()
    | retry_ir_grew()
    | mcode_full()
    | abort(reason: TraceAbort)

-- Result of assembling one IR instruction (tile dispatch).
-- need_snapshot: instruction is a guard, attach snapshot exit stub.
-- unsupported: IR opcode has no tile implementation yet.
type TileResult
    = done()
    | need_snapshot(snapno: i32)
    | mcode_full()
    | unsupported(op: i32)
    | abort(reason: TraceAbort)

-- Result of emitting an exit stub for one guard.
type ExitStubResult
    = done(addr: ptr(u8))
    | mcode_full()
```

### 4.10 MCode Arena Protocols

```moonlift
-- Result of reserving space in the mcode arena.
-- grow: arena needs a new linked chunk allocated.
-- full: cannot grow further (hard limit reached).
type MCodeReserve
    = ok(top: ptr(u8))
    | grow()
    | full()

-- Result of patching a branch in already-emitted mcode.
-- out_of_range: target is too far for a direct branch encoding.
type PatchBranch
    = direct()
    | indirect()
    | out_of_range()
    | error(code: i32)
```

### 4.11 Recorder Opcode Protocols

```moonlift
-- Result of recording one bytecode instruction into the IR.
-- next: continue recording at next PC.
-- stop: recording is complete (loop backedge, return, call boundary).
-- metamethod: recording hit a metamethod dispatch; recorder must handle.
type RecOpcodeResult
    = next(pc: ptr(BCIns))
    | stop(link: TraceLink)
    | metamethod(mm: i32)
    | abort(reason: TraceAbort)

-- Result of recording a table access.
-- guard_meta: emitted a guard against __index/__newindex; mm is the assumed nil.
type RecTableGet
    = next(pc: ptr(BCIns))
    | guard_meta(mm: TValue)
    | abort(reason: TraceAbort)

-- Result of recording a call boundary.
-- inline_lua: Lua function inlined into current trace.
-- link_call: call recorded as a trace link.
-- stop: recording must stop at this call.
type RecCallResult
    = inline_lua(fn: ptr(u8))
    | link_call()
    | stop(link: TraceLink)
    | abort(reason: TraceAbort)
```

### 4.12 FFI Protocols

```moonlift
-- Result of preparing a C function call for FFI execution.
-- need_conversion: argument at argno requires type conversion first.
-- unsupported_abi: ABI not supported (e.g., struct by value, varargs).
type FFIPrepCall
    = call_direct(argv: ptr(u8))
    | need_conversion(argno: i32)
    | unsupported_abi(code: i32)
    | error(kind: RuntimeErrorKind)

-- Result of emitting a C call in the assembler.
type FFIEmitCall
    = done()
    | spill_regs()
    | unsupported_abi(code: i32)
    | mcode_full()

-- Result of a cdata field index operation.
type CDataIndex
    = field(addr: ptr(u8), ctype: i32)
    | method(fn: TValue)
    | error(kind: RuntimeErrorKind)
```

### 4.13 Parse Exit Protocol (grammar library)

```moonlift
-- Standard parser protocol used by grammar.mlua and all parser combinators.
-- ok: matched, next is the new position.
-- fail: did not match, at is the position where it failed.
type ParseExit
    = ok(next: i32)
    | fail(at: i32)

-- Infallible parser (star, opt, pred, empty — cannot fail).
type ParseNoFail
    = ok(next: i32)
```

---

## 5. Region Signatures

With the protocol catalog defined, every region signature reduces to a type name.

### 5.1 Interpreter

```moonlift
-- Sealed entry point. Called by embedding API and C stack entry.
func vm_resume(L: ptr(ThreadState), resume_status: i32) -> i32
    emit vm_loop(L, resume_status;
        returned = ret_returned,
        yielded  = ret_yielded,
        error    = ret_error)
end

-- Main interpreter dispatch loop.
region vm_loop(L: ptr(ThreadState), status: i32) -> InterpResult
entry dispatch()
    let bc: i32 = load(L.pc)
    let op: i32 = bc & 0xFF
    switch op
    case BC_ISLT then
        emit vm_bc_islt(L, bc; next=dispatch, hot=enter_trace, error=error)
    end
    case BC_ADD then
        emit vm_bc_add(L, bc; next=dispatch, hot=enter_trace, error=error)
    end
    case BC_TGETV then
        emit vm_bc_tgetv(L, bc; next=dispatch, hot=enter_trace, error=error)
    end
    case BC_CALL then
        emit vm_bc_call(L, bc; next=dispatch, hot=enter_trace, yield=yielded, error=error)
    end
    case BC_RET then
        emit vm_bc_ret(L, bc; resume_caller=dispatch, final_return=returned, close_upvalues=close_upvals, error=error)
    end
    case BC_LOOP then
        emit vm_bc_loop(L, bc; next=dispatch, hot=enter_trace, error=error)
    end
    case BC_JLOOP then
        emit vm_bc_jloop(L, bc; next=dispatch, hot=enter_trace, error=error)
    end
    default then
        jump error(kind = type_error(0, 0))
    end
block enter_trace(pc: ptr(BCIns))
    emit trace_enter(L, pc;
        next     = dispatch,
        returned = returned,
        error    = error)
end
block close_upvals(from: ptr(TValue))
    emit upvalue_close(L, from; done = dispatch, error = error)
end
end

-- Arithmetic opcode handler.
region vm_bc_add(L: ptr(ThreadState), bc: i32) -> OpcodeResult

-- Table get opcode handler.
region vm_bc_tgetv(L: ptr(ThreadState), bc: i32) -> OpcodeResult

-- Table set opcode handler.
region vm_bc_tsetv(L: ptr(ThreadState), bc: i32) -> OpcodeResult

-- Call opcode handler.
region vm_bc_call(L: ptr(ThreadState), bc: i32) -> OpcodeResult
```

### 5.2 Table

```moonlift
region table_get(G: ptr(GlobalState), tab: ptr(GCtab), key: TValue) -> TableGet

region table_set(G: ptr(GlobalState), tab: ptr(GCtab), key: TValue, val: TValue) -> TableSet

region metamethod_binop(L: ptr(ThreadState), mm: i32, lhs: TValue, rhs: TValue) -> MetamethodResult
```

### 5.3 GC

```moonlift
region gc_alloc(G: ptr(GlobalState), size: usize, gct: i32) -> AllocResult

region gc_step(G: ptr(GlobalState), budget: i32) -> GCStepResult

-- Forward barrier: parent is black, child is white.
region gc_barrier_fwd(G: ptr(GlobalState), parent: ptr(GCobj), child: TValue) -> BarrierResult

-- Backward barrier: re-gray a black table on new-key write.
region gc_barrier_back(G: ptr(GlobalState), tab: ptr(GCtab)) -> BarrierResult
```

### 5.4 Trace lifecycle

```moonlift
region trace_record_root(J: ptr(JitState), L: ptr(ThreadState), pc: ptr(BCIns)) -> TraceRecord

region trace_record_side(J: ptr(JitState), L: ptr(ThreadState), parent: i32, exitno: i32) -> TraceRecordSide

region trace_commit(J: ptr(JitState), tr: i32, mcode_entry: ptr(u8)) -> TraceCommit

region hot_side_exit(J: ptr(JitState), L: ptr(ThreadState), parent: i32, exitno: i32) -> HotExit
```

### 5.5 IR builder

```moonlift
region ir_emit(J: ptr(JitState), ot: i32, a: i32, b: i32) -> IREmit

region ir_fold(J: ptr(JitState), ot: i32, a: i32, b: i32) -> FoldResult

region rec_getslot(J: ptr(JitState), L: ptr(ThreadState), slot: i32) -> SlotGet
```

### 5.6 Snapshots

```moonlift
region snap_add(J: ptr(JitState), guard: i32) -> SnapAdd

region snap_restore(L: ptr(ThreadState), tr: i32, exitno: i32, ex: ptr(ExitState)) -> SnapRestore
```

### 5.7 Optimizer pipeline

```moonlift
region optimize_trace(J: ptr(JitState), tr: i32) -> OptResult
entry start()
    emit opt_dce(J, tr; done=after_dce, abort=abort)
block after_dce()
    emit opt_loop(J, tr; done=after_loop, not_loop=after_loop, overflow=abort_overflow, abort=abort)
block after_loop()
    emit opt_narrow(J, tr; done=after_narrow, abort=abort)
block after_narrow()
    emit opt_sink(J, tr; done=optimized, disabled=optimized, abort=abort)
block abort_overflow()
    jump abort(reason = phiov())
end
end

region opt_dce(J: ptr(JitState), tr: i32) -> DCEResult

region opt_loop(J: ptr(JitState), tr: i32) -> LoopOptResult

region opt_narrow(J: ptr(JitState), tr: i32) -> NarrowResult

region opt_sink(J: ptr(JitState), tr: i32) -> SinkResult
```

### 5.8 Assembler

```moonlift
region asm_trace(J: ptr(JitState), tr: i32) -> AsmResult

-- Target-specific tile dispatch (x64 implementation).
region x64_asm_one_ir(A: ptr(AsmState), ref: i32) -> TileResult
entry start()
    let op: i32 = ir_op(A, ref)
    switch op
    case IR_ADD then
        emit x64_ir_add(A, ref; done=done, mcode_full=mcode_full, abort=abort)
    end
    case IR_SLOAD then
        emit x64_ir_sload(A, ref; done=done, need_snapshot=need_snapshot, mcode_full=mcode_full, abort=abort)
    end
    case IR_EQ then
        emit x64_ir_guard_eq(A, ref; done=done, need_snapshot=need_snapshot, mcode_full=mcode_full, abort=abort)
    end
    default then
        jump unsupported(op = op)
    end
end

region ra_alloc(A: ptr(AsmState), ref: i32, allow: i32) -> RAAlloc

region ra_dest(A: ptr(AsmState), ref: i32, allow: i32) -> RADest
```

### 5.9 Grammar / parser combinators

The grammar library (`lib/grammar.mlua`) currently uses inline continuation
declarations. With protocol types it becomes:

```moonlift
-- Every generated rule satisfies ParseExit or ParseNoFail.

-- Byte equality check
region r_byte_eq(p: ptr(u8), n: i32, pos: i32, val: i32) -> ParseExit
entry start()
    if pos >= n then jump fail(at = pos) end
    if as(i32, p[pos]) == val then jump ok(next = pos + 1) end
    jump fail(at = pos)
end
end

-- Sequence: a then b.
region r_seq(p: ptr(u8), n: i32, pos: i32) -> ParseExit
entry start()
    emit @{a}(p, n, pos; ok = after_a, fail = fail)
end
block after_a(next: i32)
    emit @{b}(p, n, next; ok = ok, fail = fail)
end
end

-- Alternative: a or b.
region r_alt(p: ptr(u8), n: i32, pos: i32) -> ParseExit
entry start()
    emit @{a}(p, n, pos; ok = ok, fail = try_b)
end
block try_b(at: i32)
    emit @{b}(p, n, pos; ok = ok, fail = fail)
end
end

-- Star: zero or more repetitions of a (infallible).
region r_star(p: ptr(u8), n: i32, pos: i32) -> ParseNoFail
entry loop(cur: i32 = pos)
    emit @{a}(p, n, cur; ok = loop, fail = ok)
end
block ok(next: i32)
    -- note: fail exit from 'a' maps here, not to our ok exit
    -- this is handled by cont_fills at emit site; no renamed block needed
end
end
```

The factory functions in Lua no longer need to thread `ok: cont(next: i32),
fail: cont(at: i32)` everywhere. They just produce regions satisfying
`ParseExit` or `ParseNoFail`.

---

## 6. Composition Model

### 6.1 Protocol satisfier

A region satisfies protocol `P` when its `-> P` result type is declared and its
body exits only through `P`'s named variants.

The compiler checks:
- every `jump exit(fields...)` names an exit from `P`;
- every exit field matches the declared type;
- inline continuation declarations (`; ok: cont(next: i32)`) are
  **illegal** when `-> P` is declared.

### 6.2 Emit wiring

`emit` connects two regions at their protocol boundary:

```moonlift
emit table_get(G, tab, key;
    hit          = found_value,
    nil_no_meta  = not_found,
    meta         = do_metamethod,
    error        = error)
```

Every exit from the callee must be wired. Missing wires are compile errors.

### 6.3 Protocol subsetting

A region may satisfy a protocol that only uses a subset of possible exits.
Example: `opt_loop` has `not_loop` exit for easy caller handling:

```moonlift
emit opt_loop(J, tr;
    done     = after_loop,
    not_loop = after_loop,   -- same destination: both are OK
    overflow = abort_overflow,
    abort    = abort)
```

### 6.4 Protocol reuse across tiers

The same protocol type `ParseExit` is used by:
- the bytecode-level parser combinator library;
- the SSA IR validator;
- the mcode verifier;
- any future test harness that verifies a parse rule.

The type declaration is the only shared contract.

---

## 7. Protocol Hierarchy Diagram

```
InterpResult
  └── vm_loop
        ├── OpcodeResult (each vm_bc_*)
        │     ├── TableGet (table_get)
        │     │     └── MetamethodResult (metamethod_binop)
        │     ├── TableSet (table_set)
        │     │     ├── BarrierResult (gc_barrier_fwd / gc_barrier_back)
        │     │     └── MetamethodResult
        │     ├── CallResult (prepare_call)
        │     │     └── AllocResult (gc_alloc)
        │     └── ReturnResult (return_from_lua)
        └── TraceRecord (trace_record_root)
              ├── IREmit (ir_emit)
              │     └── FoldResult (ir_fold)
              ├── SnapAdd (snap_add)
              ├── SlotGet (rec_getslot)
              └── RecOpcodeResult (rec_bc_*)

AsmResult
  └── asm_trace
        ├── TileResult (x64_asm_one_ir per IR_*)
        │     ├── RAAlloc (ra_alloc)
        │     └── RADest (ra_dest)
        ├── ExitStubResult (emit_exit_stub)
        └── MCodeReserve (mcode_reserve)

OptResult
  └── optimize_trace
        ├── DCEResult (opt_dce)
        ├── LoopOptResult (opt_loop)
        ├── NarrowResult (opt_narrow)
        └── SinkResult (opt_sink)

SnapRestore
  └── hot_side_exit
        └── HotExit
              ├── TraceRecordSide (trace_record_side)
              └── resume_interp → InterpResult
```

---

## 8. What Changes vs. the Original Architecture Doc

The original `MOONLIFT_LUAJIT_VM_ARCHITECTURE.md` expressed every region
signature with inline continuation lists:

```moonlift
region rec_bc_add(J: ptr(JitState), L: ptr(ThreadState), bc: BCIns;
    next: cont(pc: ptr(BCIns)),
    metamethod: cont(mm: MMS),
    abort: cont(code: TraceAbort))
```

With protocol types, the same contract is:

```moonlift
type RecOpcodeResult
    = next(pc: ptr(BCIns))
    | metamethod(mm: i32)
    | abort(reason: TraceAbort)

region rec_bc_add(J: ptr(JitState), L: ptr(ThreadState), bc: i32) -> RecOpcodeResult
```

Differences:

| Before | After |
|---|---|
| exits declared per-region inline | declared once as a type |
| type-checked per-region only | type-checked everywhere the type appears |
| no named contract for a family | `RecOpcodeResult` names the whole family |
| changing one exit modifies all signatures | change the type, all signatures update |
| Lua factory threads cont types explicitly | factory just returns `-> ParseExit` |
| reader must understand each signature | reader looks up the protocol type |

---

## 9. Implementation Order

Protocol types are just type declarations. They cost nothing until a region
implements them. Implementation order follows milestones:

| Milestone | Protocol types needed |
|---|---|
| M0 | all types declared, none implemented |
| M1 (value/object/state layouts) | `AllocResult`, `BarrierResult` |
| M2 (interpreter core) | `InterpResult`, `OpcodeResult`, `CallResult`, `ReturnResult` |
| M3 (tables/metamethods) | `TableGet`, `TableSet`, `MetamethodResult` |
| M4 (GC) | `AllocResult`, `GCStepResult`, `BarrierResult` |
| M5 (IR builder) | `IREmit`, `FoldResult`, `SlotGet` |
| M6 (snapshots) | `SnapAdd`, `SnapRestore` |
| M7 (trace record/commit) | `TraceRecord`, `TraceRecordSide`, `TraceCommit`, `RecOpcodeResult` |
| M8 (optimizer) | `OptResult`, `DCEResult`, `LoopOptResult`, `NarrowResult`, `SinkResult` |
| M9 (assembler) | `AsmResult`, `TileResult`, `RAAlloc`, `RADest`, `MCodeReserve` |
| M10 (exit/side traces) | `HotExit`, `ExitStubResult`, `PatchBranch` |
| M11 (FFI) | `FFIPrepCall`, `FFIEmitCall`, `CDataIndex` |
| M12 (bootstrap) | all protocols stable |

**M0 is a single `.mlua` file** declaring all protocol types in §4 above.
Nothing compiles or runs. Every region in M1–M12 references these types.
Changing the types in M0 propagates errors to every incorrect implementation
immediately.

---

## 10. Non-Negotiable Protocol Rules

1. **Every region that can fail has an `abort` or `error` exit.** No hidden
   exceptions, no `J->state = LJ_TRACE_ERR` globals.

2. **Every guard in a compiled trace has an attached snapshot.** The `SnapAdd`
   region is called before any region that emits a guard IR instruction.
   Proof that a guard cannot exit is the only alternative.

3. **Every GC object store routes through a barrier-aware region.**
   `BarrierResult` from `gc_barrier_fwd` or `gc_barrier_back` is not optional.

4. **MCode retry exits are explicit.** `retry_realign`, `retry_ir_grew`, and
   `mcode_full` are typed exits, never silent fallbacks.

5. **Protocol types are declared in M0 and never made "toy".** A narrowed version
   of a protocol for early testing is a separate named type, not a mutation of
   the production type.

6. **`abort(reason: TraceAbort)` is typed.** The `TraceAbort` data type carries
   the exact reason. No `abort(code: i32)` with magic integers.
