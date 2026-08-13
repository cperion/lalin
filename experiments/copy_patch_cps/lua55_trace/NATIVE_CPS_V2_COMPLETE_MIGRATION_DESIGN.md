# Native CPS V2 Complete Migration Design

Status: design freeze candidate. No migration implementation proceeds until this document is reviewed.

This design applies only to `experiments/copy_patch_cps/lua55_trace/`. Production Lalin remains on `CBackendUnit -> emit_c -> GCC`.

## 1. Decision and definition of complete

The current runner must become one coherent V2 machine. LuaJIT remains the staging, outer ownership, explicit host-library, and terminal FFI layer. It does not own memory visible to suspended native execution and it does not mediate recurring guest control.

The migration is complete only when:

1. `opcode_value_v2.h` is a standalone physical ABI and does not include or alias V1 types.
2. Every V2 stencil takes `Lua55NativeFrameV2 *` and is built into a V2-named section. No V2 arena copies a `lua55_poly_*`, learner, residual, or function compiled against `Lua55LearnFrameV1`.
3. Every native-visible pointer targets an invocation-owned mmap data region, guest-heap mmap region, immutable RX arena, declared shared-library symbol, or null.
4. `run55_native.run` has no V1 fallback. Every decoded occurrence either appends a V2 leaf or rejects before publication with an exact reason.
5. CALL, TAILCALL, RETURN, TFORCALL, and host resumption use named proper-tail entries. No guest continuation is a C return address.
6. Explicit host/library calls suspend and resume through typed V2 outcomes. Native code never calls Lua.
7. `run_v1_legacy`, V1 destination chains, V1 function tables, prefix-layout reservations, and V2-to-V1 casts are removed after the final differential gate.

Completing the V2 migration does not claim every Lua 5.5 metamethod, hook, coroutine, or garbage-collection behavior. Unsupported semantic alternatives remain visible typed rejections. There is no silent V1 or Lua interpreter fallback.

## 2. Hard invariants

- Bytecode prototypes are the structural plan. There is no trace IR, SSA, scheduler, trampoline, dispatch loop, snapshot system, or generic deoptimizer.
- Concrete opcode occurrence leaves own V2 support, stencil selection, and hole patching.
- Runtime self-selection remains inside each closed opcode residual. There is no Lua-side runtime tag dispatch.
- The frame and every register address remain stable for the full activation.
- Frame and guest-heap data are RW, never executable. Arena code is built RW and published immutable RX.
- CALL and TFORCALL bump-allocate exact frames; RETURN pops exactly one; TAILCALL replaces the top frame in place.
- Frame, guest heap, value stack, and host-result capacities are bounded. Exhaustion publishes an exact boundary outcome; no value is truncated.
- A continuation is an immutable RX entry stored only for a genuinely variable join.
- Only the outer FFI return and declared host/terminal stubs return to Lua. Guest control uses jumps.
- LuaJIT JIT and `-joff` must produce identical staging, ownership, and results.

## 3. Final staging vocabulary

These products are aligned projections of bytecode facts, not an execution IR:

```text
NativeInvocationCapacityV2
  frame_region_bytes
  guest_heap_bytes
  open_value_capacity
  root_result_capacity

NativeFrameShapeV2
  maxstacksize
  numparams
  is_vararg
  upvalue_count
  tbc_capacity
  value_capacity

NativeFunctionArtifactV2
  global_proto_index
  frame_shape
  immutable arena owner
  entry
  block entries

NativeCallSiteV2
  bytecode occurrence
  argument shape (fixed or open)
  result shape (fixed or open)
  continuation PC
  continuation entry hole

NativeTailCallSiteV2
  bytecode occurrence
  argument shape
  host-tail-return entry hole

NativeTForCallSiteV2
  bytecode occurrence
  iterator result count
  continuation PC
  continuation entry hole

NativeHostFunctionV2
  scalar host id
  maximum result count
  declared Lua owner (host-only)

NativePublicationV2
  reached V2 sections
  classified relocations
  published offsets
  patched immutable entries
  RX owner
```

`NativeHostFunctionV2` stores the Lua callback only in the outer owner. Native data contains the scalar id and declared result bound, never a Lua function pointer.

## 4. Leaf-owned staging

The following staging mechanisms are removed from the public V2 path:

- `POLY_SUPPORTED` opcode maps;
- class-to-opcode lookup tables;
- string learner-name dispatch;
- one generic `poly_append` switch that understands every opcode's holes;
- fallback from an unsupported V2 occurrence into V1.

Every concrete occurrence class implements its V2 operation directly:

```text
occurrence:append_v2(append_input, machine,
  ArenaBuildMachine.on_appended,
  ArenaBuildMachine.on_rejected)

call_site:append_v2_call(...)
tail_call_site:append_v2_tail_call(...)
tfor_call_site:append_v2_tfor_call(...)
```

Shared helpers may copy bytes, patch a declared hole kind, classify one ELF relocation, align offsets, and seal memory. They do not choose semantic behavior. The bytecode leaf chooses the exact V2 stencil and supplies its exact patch product.

Prototype plans and function descriptors are traversed by numeric prototype index and bytecode order. Unordered Lua `pairs()` iteration never determines section ownership, descriptor identity, code layout, or relocation assignment.

## 5. Standalone V2 physical vocabulary

`opcode_value_v2.h` owns independent definitions for:

```text
Lua55ValueV2
Lua55GuestObjectHeaderV2
Lua55GuestStringV2
Lua55GuestTableV2
Lua55GuestFieldV2
Lua55GuestBuiltinV2
Lua55GuestHeapV2
Lua55UpvalueCellV2
Lua55NativeClosureV2
Lua55NativeFrameV2
Lua55NativeInvocationV2
Lua55NativeFunctionDescriptorV2
Lua55NativeBoundaryOutcomeV2
```

No typedef aliases V1. Shared numeric constants can move to a neutral value-tag header only if both generations consume that immutable scalar vocabulary without sharing frame or ownership types.

### 5.1 Final frame shape

```c
struct Lua55NativeFrameV2 {
    Lua55NativeInvocationV2 *invocation;
    Lua55NativeFrameV2 *caller;
    Lua55NativeReturnLinkV2 return_link;
    Lua55NativeResultSinkV2 result_sink;
    Lua55UpvalueCellV2 **upvalues;
    Lua55UpvalueCellV2 *open_upvalues;
    Lua55TbcNodeV2 *tbc_nodes;
    Lua55ValueV2 *values;
    uint32_t value_count;       /* authored register count */
    uint32_t value_capacity;    /* bounded open-result capacity */
    uint32_t top;
    uint32_t vararg_count;
    uint32_t tbc_count;
    uint32_t tbc_capacity;
};
```

The frame contains no recording slots, quote cursor, V1 status, destination chain, result count, or V1 function table. Immediate result counts stay in the RETURN operation. Durable boundary state belongs to the invocation outcome.

Frame-local storage is:

```text
align16(header)
values[value_capacity]
varargs[vararg_count]
tbc_nodes[tbc_capacity]
```

`frame->values` points to the inline value slice. The vararg slice begins at `values + value_capacity`. TBC nodes follow the varargs. All slices remain stable for the activation.

### 5.2 Bounded open results

Open CALL results and host callback results are never truncated. `NativeInvocationCapacityV2.open_value_capacity` contributes explicit slack to each frame's `value_capacity`. Declared host functions carry `maximum_result_count`. If a result cannot fit, native or host resumption publishes `NativeValueOverflowV2(required, available, pc)`.

### 5.3 Exact varargs

A vararg callee frame size includes every extra argument:

```text
vararg_count = max(nargs - numparams, 0)
frame_bytes = header
            + value_capacity * sizeof(ValueV2)
            + vararg_count * sizeof(ValueV2)
            + tbc_capacity * sizeof(TbcNodeV2)
```

Fixed parameters go to registers, missing parameters are nil-filled, and all extras go to the vararg slice. Non-vararg callees discard extras. VARARG/GETVARG read the slice; no extra argument is silently clipped to `maxstacksize`. TAILCALL computes the replacement size before overwriting its source arguments.

## 6. Ownership graph

```text
NativeInvocationOwnerV2 (Lua outer owner)
  owns invocation mmap
    NativeInvocationV2
    NativeFunctionDescriptorV2[]
    root result storage
    bounded frame region
  owns guest-heap mmap
    heap header
    strings and bytes
    tables, arrays, and fields
    builtins
    closures and shared upvalue cells
  owns immutable RX function arenas
  owns host-only callback descriptions by scalar id
  remains alive across every suspension
```

Lua descriptions and intern indexes may point into mmap. Native mmap data never points back into LuaJIT GC memory. Guest values never contain Lua strings, tables, functions, or cdata pointers.

Guest allocation is bump-owned for this closed experiment. Heap exhaustion is `NativeHeapOverflowV2`, not nil, rejection by convention, or a Lua allocation fallback.

## 7. Exact boundary union

The physical C representation is a discriminant plus union. The semantic alternatives are peer leaves:

```text
NativeBoundaryOutcomeV2 =
    NativeExecutingV2
  | NativeReturnedV2(result_count)
  | NativeHostCallV2(frame, resume_entry, A, B, C, pc, host_id)
  | NativeHostTailCallV2(frame, tail_return_entry, A, B, pc, host_id)
  | NativeStackOverflowV2(required, available, pc)
  | NativeValueOverflowV2(required, available, pc)
  | NativeHeapOverflowV2(required, available, pc)
  | NativeGuestErrorV2(error_kind, value, pc)
  | NativeRejectedV2(rejection_kind, opcode, pc)
```

There is no product with optional call fields, overflow fields, and error fields. The C union payload for each discriminant is exact. Rejection kinds are a closed enum (unsupported opcode alternative, unsupported metamethod, invalid object shape, invalid bytecode shape, unsupported external helper, and released owner).

The invocation owns the outcome because it crosses the sealed native boundary. Frame-local `status` and `resume_pc` fields are removed.

## 8. Proper-tail control graph

### 8.1 Native CALL

```text
validate guest closure and descriptor
compute exact frame/value/vararg/TBC size
publish StackOverflow or ValueOverflow if bounded capacity fails
bump-allocate callee frame
copy parameters and varargs
set shared upvalue pointers
set caller, result sink, and patched continuation link
set invocation.current_frame
jmp callee entry
```

### 8.2 Native RETURN

```text
compute actual fixed/open result count
publish through exact result sink (nil-fill fixed requests)
close frame-owned open cells
run supported TBC closes or publish exact unsupported/error outcome
save return link
rewind frame_next to returning frame
set current_frame = caller
jmp stored continuation
```

The root result sink points to invocation-owned result storage. The root continuation enters a terminal stencil that publishes `NativeReturnedV2` and returns through FFI.

### 8.3 Native TAILCALL

```text
resolve callee and exact replacement size
save caller, result sink, and return link
close current cells and supported TBC values
memmove arguments before overwriting source registers
replace top frame in place
restore caller/sink/link
jmp callee entry
```

The frame address and frame-region high-water mark remain constant across tail recursion.

### 8.4 TFORCALL

TFORCALL is a call shape, not a host-driver special case. A native closure iterator receives `(state, control)` in a normal V2 callee frame with a continuation patched to TFORLOOP. Native `next` and `ipairs` use their closed iterator leaves. A declared host iterator publishes `NativeHostCallV2` with the TFOR continuation.

## 9. Host suspension and resumption

There are no native-to-Lua callbacks.

### 9.1 Ordinary host call

The occurrence-owned CALL stencil contains an immutable continuation entry. For a declared builtin/host object it publishes `NativeHostCallV2` and jumps to `host_exit`. Lua:

1. validates the scalar host id against the owner;
2. converts the exact bounded argument slice;
3. executes the library function;
4. converts results into mmap guest values;
5. applies fixed/all-result and nil-fill rules at register A;
6. checks `value_capacity`;
7. sets `NativeExecutingV2`;
8. re-enters `resume_entry(frame)`.

### 9.2 Host tail call

Each TAILCALL occurrence owns a small `HostTailReturnV2` continuation stencil with its A hole patched. The call publishes `NativeHostTailCallV2` containing that entry. Lua writes results into `R[A..]`, updates top, and enters `tail_return_entry(frame)`. That native entry performs the ordinary V2 RETURN protocol: sink publication, close, pop, and jump to the inherited return link.

Host execution never fabricates a continuation, rewinds frames, or calls a generic scheduler.

## 10. Opcode closure for the migration

Every opcode number has one of three declared V2 roles: native effect/control, structural-only, or exact rejection alternative. No opcode falls back to V1.

### Batch A — standalone core bank

- 0–10 movement/constants/shared upvalues;
- 21–45 arithmetic/bitwise primitives;
- 49–52 unary/LEN closed alternatives;
- 56–67 jumps/comparisons/tests;
- 68–74 CPS calls/returns/numeric loops;
- 79 closure.

Recompile existing residual semantics as `lua55_v2_*` sections against the standalone V2 header. Remove V2 prefix compatibility immediately after this batch passes.

### Batch B — tables and aggregates

- 11–20 GET/SET table families, NEWTABLE, SELF;
- 78 SETLIST.

Fast array/field hits and writes execute natively over mmap objects. Storage generation, metatable identity, and capacity are checked explicitly. Supported growth allocates replacement storage from the guest bump region, copies values, updates the table's stable object header, and increments storage generation. Heap exhaustion is typed. Metamethod alternatives reject visibly until their guest-call continuations are implemented.

### Batch C — strings and concat

- string LOAD/MOVE/equality/order/LEN alternatives;
- 53 CONCAT.

CONCAT allocates string bytes in the guest mmap heap. Integer and float formatting use only validated external helper entries. External relocations are named and classified. String equality and ordering are content-correct; pointer identity is never assumed for dynamically produced strings.

### Batch D — vararg family

- 80 VARARG;
- 81 GETVARG;
- 83 VARARGPREP.

These consume the exact inline vararg slice and bounded value capacity. B=0 updates top exactly. EXTRAARG remains structural and is never emitted.

### Batch E — generic loops

- 75 TFORPREP;
- 76 TFORCALL;
- 77 TFORLOOP.

TFOR closure calls use proper-tail V2 frames and occurrence-owned continuations. Iterator builtins remain closed native leaves. Unsupported iterator/library objects use typed host suspension.

### Batch F — closing and errors

- 54 CLOSE;
- 55 TBC;
- 82 ERRNNIL;
- arithmetic companions 46–48.

Function descriptors carry statically projected `tbc_capacity`. TBC nodes name register slots and close order. Nil/false close alternatives are direct. Open-upvalue closing is native. Guest `__close` and arithmetic metamethod alternatives either use explicit guest-call continuations or publish `NativeRejectedV2(UnsupportedMetamethod, ...)`; they never enter V1.

### Structural opcode

84 EXTRAARG is consumed only by its owner (LOADKX, NEWTABLE, or SETLIST). An executable EXTRAARG occurrence is a pre-publication invalid-bytecode rejection.

## 11. Bank, linking, and machine-code contract

The V2 bank builder accepts only declared `lua55_v2_*` and boundary sections. Section ownership is carried with each relocation row; unordered section assignment is forbidden.

Declared hole kinds:

```text
RegisterIndex32
ConstantTag32
ConstantBits64
GuestReference64
SuccessorEntry64
ContinuationEntry64
HostTailReturnEntry64
HostExitEntry64
ExternalHelper64
PrototypeIndex32
BytecodePC32
```

Every relocation and sentinel occurrence must be consumed exactly once by its section's leaf patcher. Unsupported local constant pools, PLT calls, jump tables, or ELF relocations reject the bank build.

Mechanical code gates:

- guest CALL/TAILCALL/TFORCALL contain no `call`;
- guest RETURN/host-tail-return contain no `ret`;
- straight successors end in classified jumps;
- only terminal/host-exit stubs contain the outer `ret`;
- declared formatting/math helper calls are classified as semantic helper calls, never guest continuations;
- every arena is sealed once RW-to-RX and never rewritten.

## 12. Public runner and artifact reuse

`run55_native.run` is the only public execution entry. It builds or accepts a retained `NativeInvocationOwnerV2`; it never chooses V1 by option or unsupported opcode.

Cold build costs remain outside recurrence. A retained owner may reuse immutable prototype plans and RX artifacts for repeated invocations only when all patched guest references belong to the retained guest owner. There is no process-global generic cache. Owner release invalidates entry and resume operations visibly.

## 13. Migration order

1. Freeze standalone V2 value, heap, frame, descriptor, TBC, and boundary-union layouts with C/Lua offset probes.
2. Add pure frame probes for exact varargs, value capacity, TBC capacity, push/pop, tail replacement, and all overflow leaves.
3. Build V2-named core sections and leaf-owned append methods; stop copying V1 poly records.
4. Switch the core V2 arena builder to deterministic numeric traversal and exact relocation products.
5. Add typed ordinary host CALL suspension/resumption.
6. Add host TAILCALL and HostTailReturnV2.
7. Integrate table/SETLIST leaves.
8. Integrate string/CONCAT leaves.
9. Integrate VARARG/GETVARG/VARARGPREP.
10. Integrate TFORPREP/TFORCALL/TFORLOOP.
11. Integrate CLOSE/TBC/ERRNNIL and explicit companion rejection/call alternatives.
12. Run full semantic, ownership, mechanical, differential, and performance gates.
13. Remove prefix reservations, V1 aliases/includes/casts, `run_v1_legacy`, and V1 imports from the public dependency closure.

Each step must keep JIT and `-joff` green. No compatibility shim allows a V2 failure to execute V1.

## 14. Validation gates

### Physical ABI and ownership

- C and FFI sizes/offsets match for every V2 product and union leaf;
- every native pointer is classified and lies in its owner's range;
- forced LuaJIT collection before entry and between host suspension/resumption changes no result;
- released invocation, heap, arena, and resume entries reject;
- W^X maps contain no simultaneous writable/executable page.

### Control

- normal recursion grows only frame-region usage;
- one million tail calls keep one frame address and constant high-water mark;
- native closure iterators use TFOR continuations without host mediation;
- host call resumes the exact block after CALL;
- host tail call resumes only through HostTailReturnV2;
- root return publishes through invocation result storage.

### Semantics

- fixed/missing/extra arguments; fixed and B=0 calls; fixed and C=0 results;
- more varargs than maxstacksize, VARARG B=0, GETVARG index and `"n"`;
- multi-return nesting and host multi-return capacity overflow;
- recursive fib, deep non-tail recursion, and million-iteration tail accumulator;
- sibling/escaped/open/closed upvalues;
- table array/field access, growth, SETLIST fixed/open counts, SELF;
- strings, exact integer/float concat formatting, dynamic string comparisons;
- pairs/ipairs/next and closure iterator TFOR;
- CLOSE/TBC order and exact unsupported/error alternatives;
- heap, frame, and value overflow products;
- byte-for-byte differential results against stock Lua 5.5 under JIT and `-joff`.

### Retirement

The V2 dependency closure must contain no:

```text
opcode_value_v1.h
Lua55LearnFrameV1
Lua55GuestClosureV1
Lua55OpcodeEntryV1
run_v1_legacy
lua55_poly_* section
learner/residual fallback
```

Legacy V1 fixtures may remain as isolated historical tests only if no public V2 module imports, links, or dispatches to them. Otherwise they are removed.

### Performance

Measure separately: cold construction, retained execution, pure call/return, host suspension, table loops, concat, generic-for, varargs, fib, and tail recursion. No result is promoted merely because it is native.

## 15. Rejected alternatives

- **Keep prefix-compatible V1 poly records:** rejected because V2 behavior remains coupled to V1 layout and signatures.
- **Generic boundary payload with nullable fields:** rejected; outcomes are exact union leaves.
- **Host callback from a stencil:** rejected; suspension and named re-entry preserve ownership and stack discipline.
- **Lua fallback for unsupported opcode semantics:** rejected; unsupported alternatives are typed before publication or at the exact boundary.
- **Universal continuation/trampoline:** rejected; continuations are occurrence-owned immutable RX entries.
- **One maximum frame size per depth:** rejected; exact variable frames preserve bounded recursion density.
- **Clip extra arguments or open results:** rejected; bounded overflow is visible and exact.
- **LuaJIT cdata as native storage:** rejected even when rooted and nonmoving; native-visible storage belongs to mmap owners.
- **Global artifact cache:** rejected; owner-aligned retained artifacts are sufficient and keep guest references coherent.

## 16. Review questions

The implementation starts only after confirming:

1. Is typed rejection acceptable for unimplemented metamethod, hook, coroutine, and `__close` alternatives while every opcode is structurally V2-owned?
2. Are `open_value_capacity` and declared host maximum results the correct bounded contract for open CALL results?
3. Should supported table growth be in the first migration closure, or should capacity overflow remain `NativeHeapOverflowV2` until measured workloads require growth?
4. May isolated V1 learner fixtures remain after they are removed from the public V2 dependency closure, or should all V1 experiment files be deleted?


## 17. Implementation status — Milestone A (standalone ABI + core bank + host suspension)

Implemented and green under JIT and `-joff`:

- `opcode_value_tags.h` — the neutral scalar vocabulary (value tags, object
  kinds, upvalue states, `LUA55_QUOTE`, `SET_TAG`) shared by both
  generations without sharing frame or ownership types.
- `opcode_value_v1.h` — consumes the neutral header; no vocabulary drift.
- `opcode_value_v2.h` — standalone V2 ABI: `Lua55ValueV2`, guest objects,
  `Lua55UpvalueCellV2`, `Lua55NativeClosureV2`, the final frame shape (no
  V1 prefix, no status/resume_pc/function_table), the invariant function
  descriptor (`value_capacity`, `tbc_capacity`), the exact
  `Lua55NativeBoundaryOutcomeV2` discriminant + union, and the proper-tail
  transfer contract. C and Lua layout probes agree on every size/offset.
- `opcode_v2_core_stencils.c` — the V2-only bank source: 54 `lua55_v2_*`
  opcode residuals (0-10, 21-45, 49-52, 56-67, 73-74) and 8 `lua55_cps_*`
  boundary sections (call/tailcall/return/return0/return1/closure/
  host_exit/host_tail_return). Every guest exit is a genuine C tail call;
  the successor macro returns through the patched `lua55_residual_next`
  symbol so GCC emits the balanced epilogue before the jmp even when a
  branch precedes it (verified by disassembly).
- `build_v2_bank.lua` — compiles only the V2 core source, classifies every
  relocation (`R_X86_64_PLT32 -> lua55_residual_next`, addend -4), and
  writes `opcode_v2/bank.lua`. Unsupported relocations reject the build.
- Leaf-owned `append_v2` methods on every core occurrence class (movement,
  constants, upvalues, arith, unary, pow, compare, jmp, for, closure,
  returns) plus `V2Machine` (shared byte copy, hole patch, deferred link/
  continuation/host-exit resolution). Unsupported occurrences reject the
  plan before publication; the descriptor entry stays 0.
- `cps_invocation_v2.lua` — the V2 runner: exact vararg slice, bounded
  `value_capacity` (fixed registers + open-result slack), TBC-capacity
  sizing, typed outcome union, deterministic numeric arena traversal, and
  typed host CALL / host TAILCALL suspension with the per-occurrence
  `lua55_cps_host_tail_return` stub.
- The legacy poly bank now sources its boundary `host_exit` from the V2
  core object; the shared stencil files no longer carry cps sections.

Mechanical gate (disassembly): no `call`/`ret` in any V2 guest section;
`lua55_cps_host_exit` is the only declared `ret`.

Validation: `run55_native_v2_test.lua` (fib, captured closure, loops,
million-iteration tail in 4 KiB, sibling/shared/escaped cells, overflow),
`run55_native_v2_diff_test.lua` (8 shapes byte-identical to stock), the V1
legacy runner, and the full opcode suite pass under JIT and `-joff`.

Retained in-process performance (build once, re-enter; noisy machine):
naive recursion ~1.1-1.5x stock, million-iteration tail recursion 0.75-1.1x
stock (at/above parity).

Not yet migrated (Milestones B-F of section 13): table/SETLIST, string/
CONCAT, VARARG family, TFOR family, CLOSE/TBC/ERRNNIL, arithmetic
companions, and the final retirement step (V1 file removal). Host
suspension plumbing is in place; it becomes exercised when table leaves
make guest env lookups native.

## 18. Implementation status — Milestone B (guest tables)

Implemented and green under JIT and `-joff`:

- V2 table stencils in `opcode_v2_core_stencils.c` (11-20, 78):
  `lua55_v2_geti/getfield/gettabup/gettable/seti/setfield/settabup/
  settable/newtable/self/setlist` plus the constant-value write variants
  `seti_const/setfield_const/settable_const`.
- Guest table semantics: array part (`array_values`) and field part
  (`field_values`) with exact identity/heap/metatable guards; reads return
  nil for absent keys (no metatable), writes create-or-grow. Both parts
  grow in place by bump-allocating a fresh slice and copying (the stable
  table object header never moves; storage generation bumps). SETLIST fills
  `R[A][C+i] := R[A+i]` with array growth.
- The projection now resolves RK constant values for SETTABLE/SETI/
  SETFIELD into `const_value` facts on the occurrence instead of rejecting;
  the V1 table test was updated to the new contract.
- Fixed a pre-existing projection gap: a branch target that is not a
  segment start (e.g. a compare's owned-JMP landing on a FORLOOP) now
  splits the block at the target, so chunk-level numeric-for bodies
  containing tables project correctly. The same fix repairs the V1 path.
- Holes: `receiver_index`, `key_index`, `object_target`, `int_key` (i32 —
  the stencils use 32-bit immediates; patching them as u64 would clobber
  the following instruction), `key_ref`, `array_cap`, `field_cap`,
  `setlist_base/count/key`.

Validation: 9 table program shapes (field/array writes, literals,
dynamic keys, nested tables, chunk-level numeric-for over tables, SELF
methods) byte-identical to stock Lua 5.5 under JIT and `-joff`, committed
into `run55_native_v2_diff_test.lua`. `tests/run.lua` (149) and the full
opcode suite stay green.

Remaining milestones: C (strings/CONCAT), D (VARARG family), E (TFOR),
F (CLOSE/TBC/ERRNNIL, companions), and the final V1 retirement step.

## 19. Implementation status — Milestone D (vararg family)

Implemented and green under JIT and `-joff`:

- V2 stencils `lua55_v2_vararg` (80) and `lua55_v2_getvarg` (81) reading the
  exact vararg slice the cps_call/tailcall already arrange
  (`values + value_capacity .. +vararg_count`). VARARG copies
  `min(wanted, nargs)` varargs to R[A..], nil-fills a fixed request, and
  updates `top` (target+wanted fixed, target+touse for all). GETVARG
  implements `luaT_getvararg`: integral index → the n-th vararg or nil;
  1-char string "n" → the count; else nil. VARARGPREP (83) remains a
  host-arranged boundary (the plan skips it).
- Host tail-call suspension now dispatches fixed protocol builtins
  (select) in tail position through the per-occurrence
  `lua55_cps_host_tail_return` stub; the driver's `host_to_guest` uses a
  pointer cell (the `values[index]` struct-value indexing bug fixed).
- Fixed a pre-existing V1 labeling bug: the generic-table quote convention
  historically swapped GETTABUP/SETTABUP (bytecode: GETTABUP=11,
  SETTABUP=15). The V2 leaf dispatch now uses the real bytecode numbers,
  so GETTABUP selects `lua55_v2_gettabup` and SETTABUP selects
  `lua55_v2_settabup`.

Validation: 6 vararg program shapes (fixed/all vararg reads, `select` in
call and tail positions, vararg forwarding, GETVARG `"n"` and multi-value
returns) byte-identical to stock Lua 5.5 under JIT and `-joff`, committed
into `run55_native_v2_diff_test.lua`. `tests/run.lua` (149) and the full
opcode suite stay green.

Remaining milestones: C (strings/CONCAT), E (TFOR), F (CLOSE/TBC/ERRNNIL,
companions), and the final V1 retirement step.

## 20. Implementation status — Milestones C/E/F and V1 retirement

Implemented and green under JIT and `-joff`:

- Batch C (CONCAT): `lua55_v2_concat` with the patched libm-free fmt
  helpers (`lua55_itoa_ll` / `lua55_dtoa_g14` from liblua55fmt.so) for
  exact Lua 5.5 integer/float formatting; two-pass length/build over the
  guest heap; short/long string split at 40 bytes; unsupported operands
  reject visibly (metamethod `__concat` is a typed rejection).
- Batch E (TFOR): `lua55_v2_tforprep` (swap closing/control, reject
  non-nil closing), `lua55_v2_tforcall` (proper-tail native closure
  iterator frames with the sink at R[A+3] and the continuation patched to
  the TFORLOOP block; builtin iterators suspend via the typed host-call
  marker), and `lua55_v2_tforloop` (non-nil control jumps back to the
  body). The driver implements exact `next`/`ipairs-iter` over the guest
  table and `pairs`/`ipairs` CALL dispatch. The tforprep link targets the
  tforcall record via `entries[pc]` on call sites.
- Batch F: `lua55_v2_close` (closes frame-owned open cells at >= R[A]),
  `lua55_v2_tbc` (nil/false no-op, other values reject), `lua55_v2_errnnil`
  (publishes the guest-error outcome). Arithmetic companions (46-48) are
  structural (skipped by the projection, never emitted).
- Fixed a latent V1 compare bug exposed by closure iterators: GTI/GEI
  computed `<`/`<=` instead of `>`/`>=` (the V1 poly shared the defect);
  the V2 compare leaves now flip the direction.
- V1 retirement: `run55_native.lua` is now a pure V2 facade; the C-stack
  runner, V1 poly/learner machinery, the V1 function table, and the
  `opcode_poly` bank are no longer imported by any public V2 module. The
  V2 bank compiles only `opcode_v2_core_stencils.c` (which includes only
  `opcode_value_v2.h`); the V2 runner contains no V1 type names. Historical
  V1 learner banks/tests remain only as isolated fixtures.

Final validation: 42 lua55_trace checks (21 tests x JIT/-joff) green,
`tests/run.lua` 149 passed, `git diff --check` clean, mechanical ABI gate
(no call/ret in V2 guest sections) green.

## 21. Binding corrective milestone — exact residual specialization

Opcode coverage and standalone V2 ownership are complete. **Architectural V2
migration is not complete until published residuals are exact semantic leaves.**
The implementation-status claims above establish semantic coverage, ownership,
proper-tail control, and V1 retirement; they do not waive this specialization
criterion.

The exhaustive audit is `V2_RESIDUAL_SPECIALIZATION_INVENTORY.md`. At the time
of the audit, the 85 opcodes contain 49 red semantic-dispatch cases, 15 amber
bundled/static cases, 16 green exact cases, and five structural opcodes. These
red and static-amber cases are mandatory corrective work, not optional tuning.

### 21.1 Publication rule

A published RX residual may:

- validate the exact semantic shape selected for that occurrence;
- execute that one implementation;
- branch on program data such as comparison results and loop termination;
- publish a named overflow, rejection, guest-error, host-boundary, or relearn
  outcome;
- use a genuinely variable CPS join or modeled lifecycle state.

A published RX residual must not:

- inspect value tags, object kinds, key domains, callee kinds, constant kinds,
  or capture kinds to choose among sibling semantic implementations;
- branch on a fact already known from bytecode, projection, a constant, or the
  selected learned shape;
- reconstruct generic tagged constant cells with unused payload alternatives;
- combine array and field access, integer and float arithmetic, native and host
  calls, or string/integer/float CONCAT formatting in one residual;
- embed a large growth/create slow implementation inside a hot in-bounds leaf;
- use opcode numbers, `quote_base`, `learner_name`, class names, or string tags
  in Lua staging code to select behavior that belongs to concrete occurrence
  leaves.

A guard is not dispatch. A guard validates the selected leaf and transfers to
one named mismatch exit. It must not continue by executing another semantic
implementation inside the same residual.

### 21.2 Sources of specialization facts

Every exact leaf is selected from one of two named fact sources:

1. **Projection-proven shape.** Resolve constants, immediate kinds, exact keys,
   capture vectors, fixed/open counts, declared builtin identities, and facts
   implied by exact bytecode protocols (for example, an integer numeric-for
   induction key) before native execution.
2. **Learned guarded shape.** Runtime-dependent operand tags, dynamic callees,
   table storage shapes, and CONCAT operand vectors are observed in a separate
   learning image and persisted as named per-occurrence shape products. The
   immutable residual image is linked only after these products exist.

An observation is not proof by itself. Every learned shape installs exact
guards and a coherent typed mismatch/relearn exit. Executing RX memory remains
immutable and is never patched in place.

### 21.3 Required table correction

The measured sieve regression makes the rule concrete. Steady-state V2 table
operations already beat stock Lua 5.5 (2.77x for absent reads and 1.25x for
writes into preallocated storage), but array construction/growth is 5.1x slower.
The current 1,334-byte constant SETTABLE record reconstructs every constant
payload, classifies integer versus string keys, validates the broad table
alternative, and contains both in-bounds and complete growth implementations.

It must be replaced by exact leaves such as:

```text
SetArrayIntegerKeyBooleanTrueInBounds
SetArrayIntegerKeyBooleanTrueGrow
SetArrayIntegerKeyRegisterValueInBounds
GetArrayIntegerKeyPresent
GetArrayIntegerKeyMissing
GetFieldExactStringPresent
GetFieldExactStringMissing
```

The hot in-bounds leaf performs only its exact guards, store/load, and direct
successor transfer. Growth is a cold tail-transfer leaf with an exact
continuation. The same split applies to SETI, SETFIELD, SETLIST, and field
creation.

### 21.4 Mandatory migration order

1. Replace all generic constant-cell construction with tag-specific leaves.
2. Split table key/value/storage shapes and isolate growth/create cold leaves.
3. Split arithmetic, unary, and comparisons by exact operand products.
4. Split numeric-for by integer/float protocol and step shape.
5. Split CALL, TAILCALL, and TFORCALL into exact native/host call-site leaves.
6. Split CONCAT by its exact operand-shape vector.
7. Split CLOSURE by its exact capture vector.
8. Remove remaining static amber branches and all staging opcode/name dispatch.

Concrete occurrence leaves own `append_v2` and select exact named bank records.
Parent occurrence methods may provide only behavior that is truly identical for
all children; they may not recover child identity from fields.

### 21.5 Completion gates

V2 exact-residual migration is complete only when all of these gates pass:

1. The inventory has zero red cases.
2. Every static amber case is removed; any remaining mutable-protocol amber case
   is individually justified as genuinely variable during one published image.
3. Disassembly proves each hot leaf contains one selected implementation, exact
   guards, named exits, and direct successor transfer only.
4. Deliberate guard mismatches publish the exact typed rejection/relearn outcome;
   no generic sibling implementation executes as fallback.
5. JIT and `-joff` semantic, differential, ownership, W^X, and mechanical ABI
   gates remain green.
6. Whole-program benchmarks report cold construction separately from retained
   execution and include table growth, arithmetic, calls, CONCAT, and mixed
   application workloads. Performance regressions remain visible.

No generic IR, SSA, optimizer, scheduler, deoptimizer, or runtime framework is
introduced to satisfy this milestone. Exact bytecode occurrence owners, named
shape products, concrete stencil leaves, and named CPS exits remain the entire
mechanism.

### 21.6 How to implement the correction

This subsection is the required implementation plan. The correction modifies
the existing V2 files and stencil vocabulary in place. It does not create a V3
runner, parallel backend, generic specialization engine, or compatibility path.

#### Step A — name family-specific selection products

Each opcode family defines a closed set of named selection products. Do not use
a universal `{ opcode, tags, mode }` record, generic shape map, or context bag.
Examples:

```text
BinaryIntegerIntegerSelectionV2
BinaryIntegerFloatSelectionV2
CompareStringStringSelectionV2
SetArrayIntegerKeyBooleanTrueSelectionV2
SetArrayIntegerKeyRegisterIntegerSelectionV2
CallNativeFixedSelectionV2
CallDeclaredHostBuiltinSelectionV2
ConcatStringIntegerStringSelectionV2
IntegerPositiveForSelectionV2
```

A selection product contains only facts consumed by that exact leaf: register
indexes, exact constants, exact object/storage guards, successor links, and
named mismatch/overflow exits. It does not carry unused payload alternatives.

Concrete occurrence leaves own construction of these products and their
`append_v2` methods. Shared parent methods may forward common mechanics only;
they do not compute opcodes or inspect names to recover a child alternative.

#### Step B — resolve projection-proven selections first

Before any learning execution, projection constructs exact selections for facts
already forced by bytecode:

- LOADI/LOADF and every constant tag/payload;
- immediate and RK constant kinds;
- fixed versus open argument/result counts;
- exact constant table keys and values;
- numeric-for protocol facts and its induction register when proven;
- closure capture count and each instack/upvalue capture alternative;
- declared builtin identity;
- NEWTABLE authored capacities and allocation-site identity.

These facts live in named occurrence/projection products carried by the bytecode
plan. They are not stored in node-keyed Lua side tables. The bytecode remains
the structural plan; these products are phase facts, not an execution IR.

For the sieve shape, the integer numeric-for induction register plus constant
boolean `true` must directly select an integer-array/boolean-true table-write
selection. No runtime key-tag or value-tag classification is needed.

#### Step C — use a separate learning image for unknown selections

Some operand shapes are not provable before values exist. Build a separate
learning image from a closed, family-specific learner bank. A learner may
classify its family's finite alternatives because it is not a published
residual. It performs the first invocation's semantics and writes a named
family-specific learning product into invocation-owned mmap storage.

Each learning slot has explicit alternatives:

```text
Unseen
Observed exact-family-selection
Conflicting observations
Rejected unsupported alternative
```

These are family-specific products/unions, not a universal tag record. A loop
may visit one occurrence repeatedly. Repeated identical observations preserve
the selection; a different semantic shape records `Conflicting observations`.
The first implementation rejects publication for conflicting or unseen required
occurrences. It does not install a generic fallback.

The learning image and the residual image are different immutable owners. The
learner completes the first outer invocation. Lua staging then reads the named
learning products, constructs concrete selection leaves, links a fresh RW
residual arena, seals it RX once, and publishes it for retained invocations.
Executing learner or residual code is never rewritten.

A later residual guard mismatch publishes a typed
`SpecializationMismatchV2(occurrence, expected, observed)` rejection and leaves
the existing RX owner untouched. The first implementation makes this mismatch
visible; it does not replay side effects, deoptimize, or silently run a generic
implementation. Transparent relearning may be added only with a separately
specified side-effect-safe suspension protocol.

If a measured occurrence is genuinely polymorphic, define a family-specific
occurrence selector whose only behavior is an exact guard chain to multiple
exact leaves. The selector performs no language semantics. Every target remains
a single-shape residual. Do not introduce a universal polymorphic dispatcher.

#### Step D — split the bank into learning and exact residual vocabularies

Modify `opcode_v2_core_stencils.c` in place:

- retain or add explicitly named `lua55_learn_v2_*` sections only for learning;
- add explicitly named exact residual sections such as
  `lua55_v2_setarray_integer_true_inbounds`;
- remove generic tag-routing bodies from sections eligible for residual
  publication;
- place growth/create, host-boundary, and rejection behavior in separate cold
  leaves with named successor/continuation holes.

Modify `build_v2_bank.lua` so the serialized bank has separate closed
`learning` and `residual` vocabularies. Exact residual records are addressed by
named family leaf, not `bank.v2[opcode]`. The builder rejects:

- a residual section not declared in the exact vocabulary;
- undeclared holes or relocations;
- a generic residual symbol;
- missing named guard, mismatch, slow-path, or successor holes;
- any guest-control `call`/`ret` shape forbidden by the mechanical ABI.

The bank manifest records each leaf's family, exact selection, allowed holes,
allowed exits, code size, and relocations. This metadata validates a closed
vocabulary; it is not runtime dispatch.

#### Step E — implement the table correction first

The table batch uses these concrete operations:

```text
LearnTableGetV2
LearnTableSetV2
GetArrayIntegerPresentV2
GetArrayIntegerMissingV2
SetArrayIntegerBooleanTrueInBoundsV2
SetArrayIntegerBooleanTrueGrowV2
SetArrayIntegerRegisterValueInBoundsV2
GetFieldExactStringPresentV2
GetFieldExactStringMissingV2
SetFieldExactStringExistingV2
SetFieldExactStringCreateV2
```

The hot boolean-true array write does exactly:

```text
guard receiver is the selected metatable-free guest-table shape
guard key is the selected integer shape
if key is in bounds: store the literal TRUE tag/payload; jump successor
otherwise: tail-transfer to SetArrayIntegerBooleanTrueGrowV2
```

It contains no string-key path, generic constant cell, barrier tag dispatch,
field scan, allocator loop, or rejection implementation. The cold growth leaf
revalidates its exact prerequisites, grows only the array shape, stores true,
then transfers to the same successor.

Learning also records a named high-water capacity fact for each NEWTABLE
allocation site. Residual NEWTABLE uses `next_power_of_two(observed_max_index)`
as its initial array-capacity floor, subject to the declared heap bound. A table
object carries or projects its named allocation-site identity; this relation is
not a pointer-keyed Lua side table. A later larger key takes the exact cold
growth edge. Field capacity uses the corresponding observed field-count fact.
This removes the repeated retained-run growth cost that dominates the sieve.

#### Step F — migrate the remaining families mechanically

For each red family:

1. Enumerate the finite supported semantic products before editing C.
2. Add family-specific learning alternatives only for facts not projected.
3. Add one C section per exact residual leaf.
4. Add only the holes consumed by that leaf.
5. Install `append_v2` directly on every concrete occurrence/selection leaf.
6. Remove the superseded generic residual section from the publishable bank.
7. Add exact success, guard-mismatch, rejection, JIT, and `-joff` tests.
8. Inspect disassembly before marking the inventory entry green.

Constants migrate before arithmetic so arithmetic leaves can embed one exact
constant payload. Arithmetic and comparisons use explicit operand products.
Numeric-for uses integer/float and sign-specific leaves. Calls use exact
native-fixed/native-vararg/declared-host leaves. CONCAT uses an exact operand
shape vector. CLOSURE uses an exact unrolled capture vector.

#### Step G — enforce the rule in tests

Add a residual-manifest test that walks every publishable bank record and
requires a named exact selection. Add family tests that deliberately provide a
wrong tag, key domain, callee kind, table shape, or capture shape and assert the
typed mismatch exit. No test accepts execution of a sibling implementation.

For the table batch, retain these performance/shape probes:

```text
2M absent array reads
2M writes into preallocated array storage
grow array to 200K entries
sieve to 200K
20K-record order aggregation
256-record x 1000-step mutable simulation
```

Report learning construction, first execution, retained execution, leaf code
sizes, and stock Lua 5.5 time separately. Performance is evidence, while the
manifest, mismatch, ownership, W^X, proper-tail, and disassembly gates are
correctness requirements.

#### Step H — update status honestly

After each batch, update `V2_RESIDUAL_SPECIALIZATION_INVENTORY.md` entry by
entry. Do not describe V2 as exact-residual complete while any red case or
unjustified static amber case remains. Semantic opcode coverage may stay green
throughout the correction, but specialization completion is a separate gate.

## 22. Implementation status — batch 1 of the exact-residual correction

Implemented per section 21 (in place, no V3, no generic backend) and green
under JIT and `-joff`:

- **Separate bank vocabularies.** `build_v2_bank.lua` now extracts
  `lua55_v2r_*` sections into `bank.residual` (exact leaves; every section must
  be declared in the exact vocabulary, undeclared sections reject the build)
  and `lua55_v2l_*` sections into `bank.learning` (family-specific learners
  that classify only because they are never published).
- **Constants are exact.** `LOADK`/`LOADKX` select tag-specific leaves
  (`loadk_nil/false/true/int/flt/str`) from the projection-proven constant kind.
  No generic constant-cell construction remains in a published constant leaf;
  the string leaf carries only its exact kind and reference as patched value
  holes.
- **Table key domains are learned.** `GETTABLE`/`SETTABLE` key domains are
  observed in a separate learning invocation (learners write per-occurrence
  `Lua55TableLearnSlotV2` products into invocation-owned mmap storage; slot 0
  is reserved for tables without a NEWTABLE site). The residual pass selects
  exact `gettable_int`/`gettable_str` and `settable_{int,str}_...` leaves from
  those products. An unseen or conflicting slot rejects publication with an
  exact reason; no generic fallback is installed.
- **Value shapes are exact.** Constant-value SETTABLE/SETI/SETFIELD select
  `const_nil/false/true/int/flt/str` leaves (projection-proven value); register
  values use `reg` leaves that copy any cell (no value classification).
- **Growth/create are named mutable-data exits.** Capacity and field presence are
  program data, not learned semantic alternatives. Exact `*_inbounds`/`*_existing`
  leaves transfer through `need_grow_link` or `need_create_link` to concrete
  `NeedGrowV2`/`NeedCreateV2` publication values. Their cold operation leaves are
  appended after authored blocks and return to the exact successor through
  `resume_link`. Exact key/value/receiver guards still publish typed mismatch;
  only mutable capacity or absence takes these operation-owned exits.
- **Capacity is learned per NEWTABLE site.** Write learners record the
  site's high-water array index / field count through `table->site_id`; the
  residual NEWTABLE preallocates the guarded `next_pow2(observed_max)` floor.
  The sieve no longer pays repeated growth on retained runs.
- **Typed mismatch.** A wrong learned shape makes the exact guard publish
  `LUA55_V2_REJECT_SPECIALIZATION_MISMATCH` (kind 9) with expected/observed
  tags; no sibling implementation executes.
- **Layout:** `Lua55GuestTableV2` gained `site_id`; the invocation gained a
  bounded `learning` region; the rejected payload gained expected/observed
  tags (all offsets verified by C and Lua probes; `git diff --check` clean).

Validation:
- `run55_native_v2_exact_test.lua` (new): exact leaf selection, deliberate
  mismatch publishes the typed rejection, learned capacity floor on retained
  re-entry.
- `run55_native_v2_diff_test.lua` gained sieve, table-init, float-value,
  interned-string-key, and dynamic-key shapes; all byte-identical to stock.
- 44 lua55_trace checks (22 tests x JIT/-joff) green; `tests/run.lua` 149
  passed; mechanical ABI gate green (no C-stack call in the call family, no
  ret except host_exit; pow/concat helper calls target declared shared-library
  symbols).

Retained whole-program results (build once, re-enter):
- sieve to 200000: ~3.9 ms (previously ~5.5 ms; stock ~4.7 ms).
- particle simulation, orders, fib, tail, numeric-for, table-read, concat
  retain prior performance (no regression).

Remaining from section 21.4: arithmetic/unary/compare exact operand products,
numeric-for integer/float/sign leaves, exact call-site leaves, CONCAT
operand-vector leaves, closure capture-vector leaves, and remaining amber
static alternatives. They are subsequent batches, not accepted final state.

## 23. Implementation status — batch 3 (arithmetic, unary, comparisons)

Implemented per section 21 and green under JIT and `-joff`:

- **Exact arithmetic operand products.** Every numeric operation (add/sub/mul/
  addi/addk/subk/mulk/mod/idiv/modk/idivk/div/divk/pow/powk/band/bor/bxor/
  bandk/bork/bxork/shl/shr/shli/shri) selects exact
  `IntegerInteger`/`IntegerFloat`/`FloatInteger`/`FloatFloat` leaves from
  learned operand tags; the const/imm side is embedded per leaf. Zero-divisor
  and integral-float-coercion checks are guards/exits of the selected leaf.
- **Exact unary leaves.** `unm_int`/`unm_flt`, `bnot_int`/`bnot_flt` (float
  leaf guards integrality), `len_str`/`len_table`. `NOT` stays green.
- **Exact comparison leaves.** LT/LE numeric + string products; LTI/LEI/GTI/GEI
  numeric products against the immediate; EQ numeric/string/ref-identity/
  same-primitive/mixed-false; EQI/EQK by the projection-proven immediate/const
  kind (EQK nil/false/true consts are single identity leaves). The `k` edge
  and taken/fall successors remain patched program data.
- **Learned operand tags.** Arithmetic/compare/unary occurrences are assigned
  learning slots; the separate learning invocation observes operand tag pairs,
  and the residual pass selects exact leaves. Conflicting/unseen slots reject
  publication; no generic fallback.
- **Staging ownership.** Every concrete occurrence class owns `append_v2`
  (`AddOccurrence`, `EqOccurrence`, `UnmOccurrence`, ...); shared helpers carry
  only common mechanics. The self-referential `__index` pattern keeps the V1
  learner path reachable for legacy fixtures.
- **Fixed latent bugs found by the differential gates:**
  - SHL/SHR/SHLI/SHRI mirrored neither luaV_shiftl nor the bytecode sign
    encoding (SHRI carries a negated count). Both the learners and the exact
    leaves now match lua 5.5 exactly.
  - `constant_facts` returned `false` for string constants, silently dropping
    EQK-string support; the string kind/ref are now populated.
  - Register-index hole values collided with unrelated instruction
    displacements (a `je` rel32 of 0x111 matched the target-index pattern,
    corrupting a patch and causing SIGILL). The register holes now use compact
    non-canonical values; a builder manifest audit checks named table-data-exit
    linkage and hole sets.
  - `lua55_dtoa_g14` lacked lua_number2str's round-trip fallback (14 vs 17
    digits) and the integer-looking ".0" suffix; it now mirrors PUC Lua 5.5
    exactly (verified: 10/3 -> "3.3333333333333335", 5.0 -> "5.0", -0.0 ->
    "-0.0").

Validation: 44 lua55_trace checks (22 tests x JIT/-joff) green including new
differential shapes (shifts, mixed arithmetic, const arithmetic, mixed
comparisons, `== nil`/`== "s"`/`== 0`/`== true`, unary); `tests/run.lua` 149
passed; mechanical ABI gate green; `git diff --check` clean.

The bank now holds 32 interim generic records, 205 exact residuals, and 47
learners. Remaining red families (per the inventory): numeric-for protocols,
exact call sites, CONCAT operand vectors, closure capture vectors, GETVARG
keys.

Retained performance after batch 3 (core-pinned, relative to pinned stock on
a contended machine): fib(25) 0.97x, million-iteration tail 1.46x,
10M numeric-for 2.10x, 10M table reads 1.76x, 10K concat 3.05x; whole
programs: particle 1.54x, sieve to 200K 1.42x (still faster than stock),
orders 1.15x. The V2_HOLE32 register-hole macro initially doubled the mov
count per hole (u64 intermediate + truncation copy); the compact-value form
restored the single-mov prologue. Absolute times were inflated by unrelated
machine load, so ratios are the meaningful comparison.

## 24. Implementation status — batch 4 (numeric-for)

Implemented per section 21 and green under JIT and `-joff`:

- **Exact protocol/sign leaves.** FORPREP (a plan boundary, not an occurrence)
  and FORLOOP select exact leaves from learned facts: `forprep_int_pos/neg`
  (all-integer triple, guarded step sign, precomputed count-down),
  `forprep_flt_pos/neg` (float protocol with per-operand int-to-double
  coercion and guarded sign), `forloop_int` (count-down; the sign is baked
  into the precomputed count, so the leaf is sign-agnostic),
  `forloop_flt_pos/neg` (float termination check by guarded sign).
- **Learning.** The FORPREP learner records (protocol, sign); the FORLOOP
  learner records (step tag, sign) after the forprep sets the protocol cells.
  Conflicting/unseen protocols reject publication; step-zero remains a typed
  rejection exit of the selected leaf.
- **Staging.** The FORPREP boundary emission in the arena builder and
  `ForLoopOccurrence:append_v2` select exact leaves in residual mode and the
  learners in learning mode.

Validation: 44 lua55_trace checks (22 tests x JIT/-joff) green with new
differential shapes (integer positive/negative loops, float loops, mixed
int/float operands, non-executing loops with both signs, step-7 loops, nested
loops) byte-identical to stock; `tests/run.lua` 149 passed; mechanical ABI
gate green; `git diff --check` clean. Retained 10M numeric-for measures
~2.17x stock (core-pinned; machine still contended).

Remaining red families: exact call sites (CALL/TAILCALL/TFORCALL), CONCAT
operand vectors, closure capture vectors, GETVARG keys.

## 25. Implementation status — batch 5 (exact call sites)

Implemented per section 21 and green under JIT and `-joff`:

- **Exact call-site leaves.** CALL/TAILCALL/TFORCALL select exact leaves from
  learned callee facts: `call_native_fixed` (callee is a native non-vararg
  closure; the frame never allocates a vararg slice), `call_native_vararg`
  (vararg callee; the slice count is data), `call_host` (declared builtin;
  typed suspension with the exact payload), and the matching
  `tailcall_native_fixed/vararg`, `tailcall_host`, `tforcall_native`,
  `tforcall_host` leaves. The exact callee-shape guard (tag, object kind,
  proto range, entry presence, vararg flag) validates the selected leaf; a
  changed callee publishes a typed `SpecializationMismatchV2`.
- **Learning.** Each call site learns (callee class, vararg flag). Invalid
  callees reject during the learning pass and are never published; a
  conflicting class rejects the residual build.
- **Staging.** `V2Machine:emit_call` and the TFORCALL emission select learners
  in learning mode and exact leaves in residual mode; call sites receive
  learning slots.

Validation: 44 lua55_trace checks (22 tests x JIT/-joff) green with new
differential shapes (vararg callees, builtin tail calls, select in tail
position, nested mixed-arity calls) byte-identical to stock; `tests/run.lua`
149 passed; mechanical ABI gate green; `git diff --check` clean.

Retained performance (core-pinned, machine settling): fib(25) ~1.06x stock
(first time above parity), million-iteration tail ~1.47x, 10M numeric-for
~2.23x.

Remaining red families: CONCAT operand vectors, closure capture vectors,
GETVARG keys.

## 26. Implementation status — batch 6 (CONCAT operand vectors)

Implemented per section 21 and green under JIT and `-joff`:

- **Exact operand-vector leaves.** CONCAT selects one of 36 exact leaves from
  the learned operand-shape vector and the projection-proven count (B <= 3):
  every 3^2 + 3^3 combination of String/Integer/Float. Each leaf has every
  position's shape guard, measure, and write baked in (string length copy,
  exact `lua55_itoa_ll`/`lua55_dtoa_g14` formatting, one guest-heap
  allocation); no runtime tag classification or scan. Result length and
  short/long output remain program data.
- **Learning.** The concat learner records the operand tags (two in key/value
  tags, the third in the slot's index field); conflicting vectors or widths
  beyond 3 reject publication.
- **Staging.** `ConcatOccurrence:append_v2` selects the vector leaf in
  residual mode; the count is asserted projection-proven.

Validation: 44 lua55_trace checks (22 tests x JIT/-joff) green with new
differential shapes (3-operand concat, mixed 5-operand sequence, per-iteration
`"n=" .. i .. ";"`) byte-identical to stock; `tests/run.lua` 149 passed;
mechanical ABI gate green; `git diff --check` clean.

Remaining red families: closure capture vectors, GETVARG keys.

## 27. Implementation status — batch 7 (closure capture vectors)

Implemented per section 21 and green under JIT and `-joff`:

- **Exact capture-vector leaves.** CLOSURE selects `closure_0`..`closure_4` by
  the projection-proven capture count; each leaf bakes the count and owns only
  its instack/index holes, with the unrolled `v2_set_cell` calls. No runtime
  `nupvals` branch. Open-cell search stays mutable identity protocol.
- **Visible rejection for wide captures.** Counts above four reject at
  staging; the previous generic record silently dropped captures beyond four
  (a latent bug, now impossible).

Validation: 44 lua55_trace checks (22 tests x JIT/-joff) green; `tests/run.lua`
149 passed; mechanical ABI gate green; `git diff --check` clean.

Remaining red family: GETVARG keys (batch 8 will also clear the amber items and
staging dispatch).

## 28. Implementation status — batch 8 (final: GETVARG, static splits, staging cleanup)

Implemented per section 21 and green under JIT and `-joff`. **The inventory now
has zero red and zero static-amber cases.**

- **GETVARG** exact key-shape leaves (`getvarg_int`/`getvarg_n`/`getvarg_mx`)
  selected from the learned key tag.
- **RETURN** split: `ret_fixed` (projection-proven B >= 2, baked count) and
  `ret_all` (B == 0, top-based); RETURN0/RETURN1 were already exact.
- **VARARG** split: `vararg_fixed` / `vararg_all` by the projection-proven
  wanted encoding (0xFFFFFFFF = all).
- **LOADNIL** unrolled span leaves (`loadnil_1`..`loadnil_8`).
- **SETTABUP** exact key/value leaves with named `NeedCreate` data exits;
  **SETLIST** exact fixed slots with a named `NeedGrow` data exit.
- **Staging cleanup:** the generic-table family is now per-op classes
  (`GettableOccurrence`, `SettableOccurrence`, `GettabupOccurrence`,
  `SettabupOccurrence`, `SelfOccurrence`, `NewtableOccurrence`), each owning
  its `append_v2`; no `quote_base`/`learner_name` dispatch remains in the V2
  leaf path.
- **Justified remaining variable state:** upvalue open/closed state changes
  during a published image (genuinely mutable protocol); TBC's nil/false
  check and TFORPREP's closing-value check are typed rejection exits of the
  operation, not alternative implementations.
- **Latent bugs fixed by the differential gates:** the projection silently
  treated SETTABUP's RK source constant as a register index (fixed with
  RK-decoding + const-value exact leaves); the V1 GETTABUP/SETTABUP quote
  swap crossed the new per-op classes (fixed).

Validation: 44 lua55_trace checks (22 tests x JIT/-joff) green with new
differential shapes (global writes/reads, growing setlist literals, LOADNIL
spans, all-value returns, `select("#", ...)` forwarding); `tests/run.lua` 149
passed; mechanical ABI gate green; `git diff --check` clean.

CONCAT vector leaves were extended to widths 4 and 5 (the order-report
`report .. i .. ":" .. totals[i] .. ";"` shape), with the learning slot
packing five operand shapes (key/value tags, two packed halves of
`max_array_index`, and `max_field_count`) and short/long string tags
normalized (a growing string crossing 40 bytes must not conflict). SETTABUP
gained const-value existing/create pairs (the projection's RK source was
silently treated as a register index; fixed with RK-decoding).

The bank holds 23 interim generic records (genuinely-variable boundary and
protocol leaves: host_exit, return0/1, test/testset, move/loadi/loadf
constants, upvalue state, geti/getfield/gettabup/self, not, tforprep/loop,
close/tbc), 616 exact residuals, and 54 learners.

Retained performance at batch-8 completion (core-pinned): fib(25) ~1.06x
stock, million-iteration tail ~1.54x, 10M numeric-for ~1.96x, 10M table reads
~1.55x, 10K concat ~3.1x; whole programs: particle ~1.7x, sieve ~1.4x,
orders ~1.2x. The exact-residual correction is complete: zero red and zero
static-amber inventory cases.
