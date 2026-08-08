# Native CPS Frame V2 Design

Status: design freeze candidate. This document precedes implementation.

This design applies only to `experiments/copy_patch_cps/lua55_trace/`. It does not change the production Lalin emitted-C/GCC backend and does not introduce a generic runtime framework.

## 1. Decision

Replace the poly runner's `alloca`/C-call frame protocol with one invocation-owned, nonmoving RW frame region.

```text
outer LuaJIT FFI entry
  -> NativeInvocationV2 owner
  -> one bounded nonmoving frame region
  -> current NativeFrameV2
  -> copied opcode arenas connected by proper-tail native jumps
  -> one terminal ret at the true outer boundary
```

A normal guest `CALL` bump-allocates one exact frame, stores the exact continuation entry, and jumps to the callee. `RETURN` copies results, closes upvalues, pops the frame, and jumps to the stored continuation. `TAILCALL` closes/reuses the current top frame, preserves its return link, and jumps to the callee.

No recurring guest call uses the C call stack.

## 2. Why V1 must be replaced

The current native-call stencil performs this physical sequence:

```asm
call *callee_entry
...
call next_residual
```

It also obtains the callee frame with `alloca`. This has four defects:

1. Guest continuations are represented by native C return addresses rather than named machine edges.
2. The callee frame lifetime is tied to the C call. It cannot survive a proper-tail jump.
3. Every call initializes a large generic header and copies upvalue cells.
4. `TAILCALL` grows the C stack and is not a proper tail call.

The destination chain solves result placement only. It does not solve continuation ownership.

## 3. Non-negotiable invariants

1. The outer FFI entry and explicit host/library boundaries are the only native `ret` paths.
2. Native `CALL`, `TAILCALL`, and `RETURN` contain no guest-control `call` instruction.
3. A native frame address and every register address remain stable for the complete activation.
4. No frame pointer refers to LuaJIT GC-owned memory.
5. Frame data is RW and never executable. Copied code remains separately RW-to-RX.
6. Frame allocation is bounded. Overflow publishes a typed boundary outcome.
7. Normal return pops exactly one frame. Tail call does not increase frame-region usage.
8. A continuation is an immutable RX entry address stored only because the join is genuinely variable.
9. Bytecode remains the structural plan. There is no trace IR, scheduler, dispatch loop, snapshot system, or generic frame runtime.
10. Upvalue cells have shared identity and outlive frames when captured.

## 4. Durable staging vocabulary

The bytecode prototype remains the plan. The native projection adds only precise facets aligned to that plan:

```text
NativeFrameShapeV2
  maxstacksize
  numparams
  is_vararg
  upvalue_count

NativeFunctionArtifactV2
  global_proto_index
  frame_shape
  immutable arena owner
  native entry

NativeCallContinuationV2
  call occurrence
  exact continuation PC
  continuation entry hole
  result destination shape

NativeInvocationCapacityV2
  frame_region_bytes
  result_capacity

NativeBoundaryOutcomeV2 =
    NativeExecutingV2
  | NativeReturnedV2
  | NativeHostCallV2
  | NativeHostTailCallV2
  | NativeStackOverflowV2
  | NativeRejectedV2
```

These are staging facts and sealed-boundary alternatives. They are not an operational instruction mirror. Concrete opcode leaves continue to own stencil behavior.

The physical C encoding can use a discriminant plus a union for `NativeBoundaryOutcomeV2`; the alternatives above remain the semantic vocabulary. It must not become one product with nullable payload fields.

## 5. Physical ownership graph

```text
NativeInvocationOwnerV2 (Lua outer owner)
  owns one mmap RW data allocation
    NativeInvocationV2
    NativeFunctionDescriptorV2[]
    root result storage
    bounded frame region
  owns all RX function arenas
  owns the guest heap
  remains alive across an explicit host/library suspension

NativeInvocationV2
  frame_begin/frame_next/frame_end
  current_frame
  function descriptors
  guest heap
  root result sink
  boundary outcome

NativeFrameV2 (inside the frame region)
  invocation
  caller topology
  immutable return link
  exact result sink
  upvalue references
  frame-owned open-upvalue list
  register count/top/vararg facts
  inline register and vararg storage
```

The Lua owner holds pointers to `mmap` allocations. Native guest frames never contain pointers into Lua tables, Lua strings, or LuaJIT GC allocations.

## 6. Exact runtime products

Illustrative C shape; final field order is frozen only after offset and alignment tests:

```c
typedef struct Lua55NativeInvocationV2 Lua55NativeInvocationV2;
typedef struct Lua55NativeFrameV2 Lua55NativeFrameV2;
typedef struct Lua55UpvalueCellV2 Lua55UpvalueCellV2;

typedef void (*Lua55NativeEntryV2)(Lua55NativeFrameV2 *);

typedef struct Lua55NativeReturnLinkV2 {
    Lua55NativeEntryV2 entry;
    Lua55NativeFrameV2 *subject;
} Lua55NativeReturnLinkV2;

typedef struct Lua55NativeResultSinkV2 {
    Lua55ValueV1 *values;
    uint32_t *top;
    uint32_t base;
    int32_t count;          /* -1 means all actual results */
} Lua55NativeResultSinkV2;

struct Lua55NativeFrameV2 {
    Lua55NativeInvocationV2 *invocation;
    Lua55NativeFrameV2 *caller;          /* real root-topology absence is local */
    Lua55NativeReturnLinkV2 return_link;
    Lua55NativeResultSinkV2 result_sink;
    Lua55UpvalueCellV2 **upvalues;
    Lua55UpvalueCellV2 *open_upvalues;
    uint32_t value_count;
    uint32_t top;
    uint32_t numparams;
    uint32_t vararg_count;
    Lua55ValueV1 values[];                /* varargs follow fixed registers */
};

typedef struct Lua55NativeFunctionDescriptorV2 {
    Lua55NativeEntryV2 entry;
    uint32_t maxstacksize;
    uint32_t numparams;
    uint32_t is_vararg;
    uint32_t upvalue_count;
} Lua55NativeFunctionDescriptorV2;

struct Lua55NativeInvocationV2 {
    uint8_t *frame_begin;
    uint8_t *frame_next;
    uint8_t *frame_end;
    Lua55NativeFrameV2 *current_frame;
    Lua55NativeFunctionDescriptorV2 *functions;
    uint32_t function_count;
    Lua55GuestHeapV1 *heap;
    Lua55ValueV1 *result_values;
    uint32_t result_capacity;
    uint32_t result_count;
    Lua55NativeBoundaryOutcomePhysicalV2 outcome;
};
```

`Lua55NativeReturnLinkV2` is the exact variable join. It is not a generic continuation object: its only values are immutable entries in the current program's function arenas or a declared terminal stub.

`Lua55NativeResultSinkV2` names one precise capability: where this activation must publish return values and which stable `top` field it must update. For a normal call it targets the caller. For the root activation it targets invocation-owned result storage.

## 7. Frame-region layout

Each frame is one aligned variable-sized record:

```text
align16(
  sizeof(NativeFrameV2)
  + maxstacksize * sizeof(Lua55ValueV1)
  + vararg_count * sizeof(Lua55ValueV1)
)
```

The invocation uses a monotonic top pointer:

```text
CALL      frame = frame_next; frame_next += frame_bytes
RETURN    frame_next = address_of(returning_frame)
TAILCALL  frame_next = address_of(current_frame) + replacement_frame_bytes
```

The mapping never moves or grows. Capacity is selected at the outer boundary. Exceeding it produces `NativeStackOverflowV2(required, available, pc)` and returns to the host visibly.

A large fixed virtual mapping can be demand-paged; committed memory follows actual recursion. There is no per-call `malloc`, `mmap`, Lua allocation, or C `alloca`.

## 8. Native control protocol

### 8.1 Normal CALL

The call occurrence knows its exact continuation PC during function-arena linking.

```text
validate closure and function descriptor
compute fixed-register and vararg counts
check frame-region capacity
bump-allocate callee frame
copy arguments into the callee's register/vararg slices
set callee.upvalues = closure.cells
set callee.caller = caller
set callee.return_link = (patched continuation entry, caller)
set callee.result_sink = caller result slice/top
invocation.current_frame = callee
jmp callee function entry
```

The CALL stencil has a `ContinuationEntry64` hole patched to the exact block after that CALL. It has no `lua55_residual_next` relocation and no C return address representing guest control.

### 8.2 RETURN

```text
compute actual result count (including B=0/top)
publish results through frame.result_sink:
  fixed count -> copy min(actual, requested), nil-fill the remainder, set top to base+requested
  all results -> copy actual results, set top to base+actual
close every open upvalue owned by this frame
save frame.return_link
rewind invocation.frame_next to this frame
set invocation.current_frame = frame.caller
jmp frame.return_link.entry(frame.return_link.subject)
```

For an ordinary call, the subject is the caller frame. For the root activation, the return link targets a terminal stub; the root frame remains mapped long enough for that stub to read its invocation owner. The result itself already resides in invocation-owned result storage.

### 8.3 TAILCALL

```text
resolve callee closure and descriptor
check replacement size against frame_end
save current return_link, caller, and result_sink
close current frame's open upvalues
memmove arguments down within the top frame
resize the top frame in place
initialize replacement parameters/varargs/upvalue references
restore the saved return_link, caller, and result_sink
invocation.current_frame remains this frame
jmp callee function entry
```

Frame depth and used frame-region bytes do not grow across a tail call. A million-iteration tail recursion must use the same top-frame address.

### 8.4 Terminal and host boundaries

A root terminal stub publishes `NativeReturnedV2` and executes the outer `ret`.

An unsupported builtin/library call publishes either `NativeHostCallV2` or `NativeHostTailCallV2`, including the exact suspended frame and immutable resume entry, then returns to Lua. The Lua driver performs the library operation and re-enters that named resume entry. There is no callback from native code into Lua.

A host tail-call result resumes through a dedicated native tail-return entry so frame closing, popping, and continuation transfer still use the same native RETURN contract.

## 9. Upvalue identity and frame lifetime

The current inline/copied closure-cell model is not sufficient for reusable frames. It also fails shared-capture semantics for sibling closures.

V2 uses heap-owned shared cells:

```c
struct Lua55UpvalueCellV2 {
    Lua55ValueV1 *open_slot;
    Lua55ValueV1 closed_value;
    Lua55UpvalueCellV2 *next_open;
    uint32_t state;
    uint32_t generation;
};

typedef struct Lua55NativeClosureV2 {
    Lua55GuestObjectHeaderV1 header;
    uint32_t proto_index;
    uint32_t upvalue_count;
    Lua55UpvalueCellV2 *cells[];
} Lua55NativeClosureV2;
```

Concrete CLOSURE behavior:

- `instack` capture asks the current frame for the unique open cell for that register; it reuses an existing cell or heap-allocates and links one.
- outer-upvalue capture stores the existing parent cell pointer directly.
- `GETUPVAL` and `SETUPVAL` dereference the shared cell.
- RETURN and TAILCALL close every frame-owned open cell before frame storage is reused.
- closing copies the slot value into the persistent cell and changes the cell to the closed leaf.

This makes escaped closures and sibling captures coherent without a side table keyed by frame/register.

## 10. Static facts belong in function descriptors

`maxstacksize`, `numparams`, `is_vararg`, and prototype upvalue count are prototype facts. V2 stores them once in `NativeFunctionDescriptorV2`, not in every closure instance.

A closure retains only identity (`proto_index`) and its shared cell references. CALL resolves the immutable function descriptor through the invocation-owned descriptor array.

## 11. Argument and vararg rules

On entry:

1. Copy `min(nargs, numparams)` fixed arguments.
2. Fill missing fixed parameters with canonical nil values.
3. For a vararg function, copy arguments after `numparams` into the vararg slice after fixed registers.
4. Ignore excess arguments for a non-vararg function.
5. Initialize the frame top according to the exact Lua 5.5 call convention.

No argument loop may write beyond `maxstacksize`; V1 currently permits that when `nargs > maxstacksize`.

## 12. Linking changes

Each normal CALL becomes a terminal control stencil with:

```text
callee descriptor lookup
ContinuationEntry64 hole
HostCallBoundary alternative
StackOverflow alternative
```

The function-arena builder publishes an offset for the block immediately after each CALL and patches that absolute continuation before sealing RX.

TAILCALL has no continuation hole. It forwards the current frame's existing return link.

RETURN has no successor relocation. It jumps through the frame's return link.

Straight-line opcode successors, compares, JMP, FORPREP, and FORLOOP remain direct native edges. Bytecode PCs and operands remain patch payloads, not specialization axes.

## 13. Rejected alternatives

### C `alloca` frames

Rejected because their lifetime requires C call/return and makes proper-tail transfer impossible.

### `malloc` or `mmap` per guest call

Rejected because it adds allocation/runtime ownership overhead to every call and makes tail reuse harder.

### One maximum-sized frame slot per depth

Rejected because it multiplies the largest prototype frame by maximum recursion depth.

### A trampoline or scheduler loop

Rejected because it introduces recurring generic dispatch and a universal control runtime.

### C return addresses as continuations

Rejected because guest control disappears into the platform call stack and tail recursion still grows it.

### Copying closure upvalue cells into each callee

Rejected because it is slower and breaks identity for closed/shared upvalues.

## 14. Implementation sequence

1. Add V2 structs and mmap owner alongside V1. Do not alter legacy learner/residual tests.
2. Implement frame-size, push, return-pop, and in-place tail-replacement probes without opcode execution.
3. Add V2 shared closure/upvalue cells and close-on-pop tests.
4. Change poly entry signatures from `Lua55LearnFrameV1 *` to `Lua55NativeFrameV2 *`; legacy stencil sections remain V1.
5. Replace poly CALL/TAILCALL/RETURN with the jump protocol and add exact continuation holes.
6. Teach the function-arena builder to publish and patch each call continuation entry.
7. Add typed host-call suspension/resume outcomes.
8. Move the native runner's function descriptors and frame region out of LuaJIT GC memory into the invocation mmap owner.
9. Remove the V1 dest-chain fields from the poly path after all V2 tests pass; retain them only where legacy tests still require them.
10. Re-run the complete JIT/`-joff` and differential gates before measuring performance.

## 15. Validation gates

### Mechanical ABI

- CALL contains no `call` instruction and ends in `jmp *callee`.
- TAILCALL contains no `call` instruction and ends in `jmp *callee`.
- RETURN contains no `ret` and ends in `jmp *continuation`.
- Only declared terminal/host-boundary stubs contain `ret`.
- Every continuation, callee, branch, and external relocation is classified and validated.

### Frame ownership

- normal recursion grows only the explicit frame region; typed overflow is deterministic;
- tail recursion keeps a constant frame address and constant frame-region high-water mark;
- released mappings reject entry;
- no guest pointer targets LuaJIT GC memory.

### Semantic matrix

- fixed arguments, missing arguments, extra arguments, B=0, and C=0;
- ordinary nested calls and multiple return values;
- recursive fib;
- at least one million tail-recursive iterations without C-stack growth;
- sibling closures sharing one captured local;
- an escaped closure after its defining frame returns;
- mutation through open and closed upvalues;
- RETURN and TAILCALL close all frame-owned open cells;
- explicit host call and host tail-call suspension/resumption;
- stack overflow outcome;
- JIT and `-joff` equality.

### Performance

Measure separately:

- outer build/compile cost;
- native execution-only cost with a retained invocation/artifact;
- ordinary recursive fib;
- tail-recursive accumulator loop;
- call/return microbenchmark with zero and one upvalue.

## 16. Implementation status

Implemented in `experiments/copy_patch_cps/lua55_trace/`:

- `opcode_value_v2.h` — V2 frame/invocation/closure/descriptor types.
- `opcode_call_stencils.c` — `lua55_cps_call/tailcall/return*/host_exit`:
  bump-allocate, continuation-hole, sink publish, pop, in-place tail
  replacement. Every exit is a C tail call so GCC emits the balanced
  callee-saved epilogue before the jmp (an inline-asm `jmp` corrupted the
  C stack by skipping the epilogue).
- `opcode_closure_stencils.c` — `lua55_cps_closure` with heap-owned shared
  cells (find-or-create open cell, direct parent-cell reference).
- `opcode_00_08_stencils.c` — `lua55_cps_getupval/setupval` over the
  shared cell pointers.
- Poly reject paths across arith/compare/unary/pow/for/closure route
  through the per-arena `host_exit` stub (a `HOST_EXIT_HOLE` 64-bit
  absolute hole, never a symbol relocation: the small code model would
  truncate it to R_X86_64_32).
- `cps_invocation_v2.lua` — the invocation owner: one mmap data region
  holding the invocation struct, the immutable function descriptors, and
  the bounded nonmoving frame region; the V2 arena builder (stub-first,
  continuation holes patched to the absolute block-after-call); the
  driver that roots the main frame and reads results.

Physical-encoding refinements vs. the freeze (all within the documented
"final field order" latitude):

- `values` is a pointer into the frame region, not a flexible array, so
  the existing poly records compiled against V1 layout stay valid.
- The root terminal reuses the per-arena `host_exit` stub (`ret` to the
  outer FFI entry) rather than a dedicated terminal stub.
- `maxstacksize` covers the vararg slots; extra args beyond it are
  truncated (stock `luaD_precall` behavior), so frames need no separate
  vararg term.
- The guest-heap header, strings, string bytes, tables, arrays, fields,
  builtins, closures, and shared cells are all allocated from a nonmoving
  mmap guest region. Lua wrappers retain only staging descriptions and
  interning indexes; native frames contain no LuaJIT-GC pointer. Forced-GC
  ownership tests run before native entry under JIT and `-joff`.
- The public `run55_native.run` entry now delegates to V2. The C-stack runner
  is available only as the explicitly named `run_v1_legacy` boundary.
- V2 reserves the old prefix bytes needed by already-built poly records but
  no longer exposes V1 recording slots, destination-chain fields, or a V1
  function table. Function descriptors belong to the invocation.

Latent bugs fixed en route (V1 poly path shared the records):

- The `-k` constant arith/compare/pow records had no const holes: GCC
  constant-folded the tag test (no asm guard). All const cells are now
  runtime-guarded and fill the union payload by tag.
- `modk`/`idivk` used a POLY_DIVMOD without `right_init`; they now take
  `CONST_RIGHT` like the other -k variants.
- The poly call-family reject paths in V1 silently swallowed nested
  rejects; V2 routes every reject through the host-exit stub.

Validation:

- `run55_native_v2_test.lua` — fib, captured closure, function-level
  loops, one-million-iteration tail recursion in a 4 KiB frame region
  (proves bounded frame reuse), sibling closures sharing one cell,
  open-cell mutation, bounded overflow, tail fib. Green under JIT and
  `-joff`.
- `run55_native_v2_diff_test.lua` — eight program shapes (multi-return,
  B=0, nested calls, numeric-for + calls, escaped/shared closures, swap,
  500K tail accumulator) byte-identical to stock Lua 5.5 under JIT and
  `-joff`.
- `tests/run.lua` — 149 passed, 0 failed.

Retained in-process measurements (build once, re-enter):

```text
fib(25) x100   stock 0.284s   v2 0.292s   (parity)
fib(30) x20    stock ~0.30s   v2 0.640s   (parity)
tail 1e6 x30   stock 0.551s   v2 0.218s   (1.5x faster)
```

Proper-tail recursion no longer grows the C stack, normal recursion
executes at stock-Lua speed, and the 4 KiB frame-region tail test proves
one frame is reused across a million tail calls.
