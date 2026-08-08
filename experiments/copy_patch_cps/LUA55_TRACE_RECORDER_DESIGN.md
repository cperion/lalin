# Lua 5.5 one-shot CPS trace recorder

Status: design draft. This is the proposed next integration target for the isolated copy-and-patch experiment.
It does not alter Lalin's production emitted-C/GCC backend.

## 1. Purpose

A learner with no memory is only a selector. The new machine executes one loop iteration while remembering the exact
semantic path. At the first completed backedge it seals that recording as native code and enters a direct recurrence.

```text
Lua 5.5 Proto
→ static exotype residualization
→ first loop initialization
→ bounded CPS recording of one complete iteration
→ direct stencil emission into an inactive RW arena
→ publish offsets and bind the backedge
→ RX publication
→ native recurrence
```

There is no hot counter, profiling tier, generic IR, SSA, snapshot system, trace tree, or general deoptimizer.

## 2. Scope boundary

The recorder lives under `experiments/copy_patch_cps/`. Production Lalin continues to use:

```text
CBackendUnit → emit_c → gcc -O3 -fPIC -shared
```

The existing `experiments/lua55/cps_exotype_codegen.lua` remains the semantic oracle and static residual baseline.
A native trace path does not become canonical until it has exact frame ownership and broader Lua 5.5 differential tests.

The numerical stencil vocabularies remain mechanical and ownership proofs. They are not expanded into a universal
specialization runtime.

## 3. Two kinds of late work

### Runtime compilation

A loaded prototype reveals immutable facts late:

```text
opcode leaves
register operands
constant operands
jump targets
basic-block topology
frame size
nested prototype identities
```

These facts are specialized immediately when the prototype is linked. This is runtime compilation, not learning.

### Runtime recording

A loop activation can reveal semantic alternatives that do not exist until execution, such as the normalized integer
or floating numeric-for mode. The recorder remembers the concrete semantic path established by that initialization.

A value merely passed from Lua to C is not learned. A first-iteration observation is not an invariant unless the trace
contains a guard or the language semantics prove it stable.

## 4. Frozen V1 trace domain

V1 records numeric-for loops only. It supports the closed semantic subset:

```text
Move
LoadInteger
LoadFloat
LoadNumericConstant
IntegerAdd
IntegerSubtract
IntegerMultiply
FloatAdd
FloatSubtract
FloatMultiply
IntegerForPrepare
FloatForPrepare
IntegerForLoop
FloatForLoop
FixedReturn
```

The first version rejects:

```text
internal data-dependent branches
tables
global lookup
general calls
metamethods
captured upvalues
varargs consumed by the loop
yield or coroutine transitions
to-be-closed values
unsupported numeric conversions
trace capacity overflow
```

Calls, errors, metamethods, and suspension are terminal side exits when their exact frame protocol exists. Until then
their presence rejects publication and execution continues through the residual Lua path.

## 5. Deterministic trigger

There are no hotness counters.

```text
FORPREP establishes IntegerFor or FloatFor
→ select the corresponding closed trace site
→ if the site is Empty, start recording at the loop body
→ execute and record the first iteration
→ when FORLOOP takes the matching backedge, close and publish
→ execute the second and later iterations through the native trace
```

Integer and floating numeric-for modes have separate named sites. The first observed mode does not prevent the other
mode from receiving its own trace. There is no open-ended version list.

A structurally unsupported loop site becomes permanently `Rejected`. A runtime guard exit does not reject or rewrite
an already published trace.

## 6. Domain exotype vocabulary

The loaded bytecode is already the stable structural plan. The trace path does not build an ASDL mirror or a second
instruction graph.

### Owners

```text
PrototypeOwner
InstructionOwner(proto, pc, concrete opcode leaf)
ForPrepOwner(proto, pc, body, forloop, exit)
IntegerAddForLoopOwner(forprep owner, accumulator register)
```

Owners retain staging facts and memoized properties. They do not contain activation values.

### Properties

```text
TracePlan       Which exact trace quotation can this loop produce?
RecordLoop      How does the first activation execute and emit it?
MachineListing  What deterministic readable projection describes the emitted artifact?
```

Concrete opcode and fused-loop owner classes implement these properties directly. Property lookup disappears after
materialization.

### Numeric-for alternatives

```text
IntegerForMode
FloatForMode
NumericForZeroTrip
NumericForRejected
```

These are exact local Lua classes with different behavior. They are not string tags or one optional record.

### Trace site phases

```text
EmptyTraceSite
RecordingTraceSite
InstalledTraceSite
RejectedTraceSite
ReleasedTraceSite
```

Each phase class owns its operations. The site changes its stable phase reference at publication; recurring execution
does not branch on a phase string.

### Artifact and outcomes

```text
TraceArtifact
├── immutable RX owner
├── typed entry
├── code size
├── frame contract
├── exact terminal exits
└── deterministic listing

TraceLoopCompleted(resume_pc)
TraceGuardFailed(resume_pc, failed_assumption)
TraceUnsupported(resume_pc, diagnostic)
TraceCapacityRejected(resume_pc, required, capacity)
TraceGuestReturned(result)
```

These are domain-local exotype values and boundary classes. The native boundary has an exact physical encoding for the
same alternatives. `nil`, zero, or an undocumented status does not encode an outcome.

## 7. The recording machine

`Lua55TraceRecorder` is one named running computation. It owns exactly:

```text
prototype projection
loop spine
numeric-for mode
activation frame
trace-site owner
inactive code arena
current code cursor
published root offset
bounded exit builder
bounded projection builder
bounded projection builder
current plan identity
recording generation
```

Its named control graph is:

```text
begin_plan_recording
→ IntegerAddForLoopPlan:record
→ append_integer_add_forloop_plan
→ on_plan_backedge
→ seal_complete
→ publish_trace
→ enter_trace
→ enter_trace

peer exits:
peer exits:
  on_completed (TraceLoopCompleted)
  on_rejected (TraceRecordingRejected)

Opcode and semantic leaves receive this machine and stable unbound peer exits. The leaf method is the dispatch. No
opcode handler table, visitor, switch over class names, or capturing continuation is introduced.

## 8. Recording by compilation

The recorder does not first build a generic trace IR and lower it later.

Each concrete semantic leaf does three things while the first iteration executes:

1. execute the exact guest semantics against the canonical frame;
2. append its exact native stencil bytes to the inactive arena;
3. append its deterministic typed projection for diagnostics and differential tests.

Executable bytes and projection derive from the same leaf method. The projection is not consumed to regenerate code.

Straight-line successors use validated jump stripping and fallthrough. Control leaves retain typed branch holes.

## 9. Recorder memory

The learner's memory is physical and bounded:

```text
TraceArena
├── one page-isolated RW allocation
├── fixed capacity, initially 4 KiB
├── emitted code cursor
├── root offset published before the cycle is closed
├── local terminal-exit stubs
└── no executable borrow while writable
```

The arena state is monotonic:

```text
RW Recording → RX Installed → Released
RW Recording → Released on rejection
```

An installed trace is never changed back to RW. A new generation receives a new arena. This removes mutable-slot sharing
from the steady-state architecture.

## 10. Stencil vocabulary

V1 stencils are semantic leaves, not raw opcode cases:

```text
TraceEntry
GuardPrototype
GuardFrameGeneration
GuardIntegerRegister
GuardFloatRegister
MoveValue
LoadIntegerImmediate
LoadFloatImmediate
LoadNumericConstant
AddInteger
SubtractInteger
MultiplyInteger
AddFloat
SubtractFloat
MultiplyFloat
IntegerForStepPositive
IntegerForStepNegative
FloatForStepPositive
FloatForStepNegative
TraceBackedge
TraceLoopCompletedExit
TraceGuardFailedExit
TraceUnsupportedExit
TraceReturnExit
```

Positive and negative numeric-for step alternatives are selected once by `FORPREP`; no step-sign dispatch remains on
the recurrence backedge.

Each stencil bank record has exact typed hole fields. V1 requires only holes that are exercised and validated:

```text
FrameDisplacement32
Immediate32
Immediate64
SuccessorRel32
GuardExitRel32
BackedgeRel32
```

There is no untyped list of patches and no byte-pattern search at runtime. The bank extractor validates every machine
encoding and relocation before producing the bank.

## 11. Native ABI

The public trace entry obeys x86-64 SysV:

```c
Lua55TraceExitCode trace(Lua55TraceFrame *frame);
```

`rdi` carries the frame. The entry establishes any internal register protocol. Internal snippets use only the declared
protocol and validated caller-saved registers. A terminal stub writes the exact resume PC and exit payload before `ret`.

No native trace calls Lua. Calls, metamethods, errors, and suspension are terminal returns across the FFI boundary.

## 12. Canonical V1 frame

Native tracing requires an exact frame; the current arbitrary Lua register table cannot be borrowed by native code.
V1 introduces only the representation it can own correctly:

```text
Lua55NumericValue
├── NilValue
├── BooleanValue
├── IntegerValue(int64)
└── FloatValue(double)

Lua55TraceFrame
├── numeric register storage owner
├── register count
├── top
├── resume PC
├── prototype identity
├── frame generation
└── terminal exit storage
```

V1 does not put raw Lua GC pointers in CDEF memory. Strings, tables, closures, userdata, threads, and collectable values
remain outside the native trace subset until their ownership model is explicitly designed.

Integer arithmetic is exact Lua 5.5 wrapping `int64` behavior. Floating arithmetic preserves the declared operation
sequence and does not contract without an explicit semantic leaf.

## 13. Frame coherence and guard exits

Every recorded effect commits its result to the canonical frame. The fused integer recurrence is the single
recorded boundary: it materializes `sum` and `index` before returning, so no native temporaries survive.

Therefore a guard failure needs no SSA snapshot reconstruction:

```text
guard fails
→ frame already contains all preceding guest effects
→ terminal stub writes the failing instruction PC
→ return TraceGuardFailed
→ residual Lua machine resumes at that PC
```

This deliberate materialization rule trades some peak performance for a smaller and auditable first architecture.
Register caching can be considered only as a later exact stencil vocabulary with explicit exit materialization
contracts.

## 14. Cycle publication

The body root offset is published when the first body stencil is appended. The backedge is unresolved until the matching
`FORLOOP` completes the first iteration.

```text
append root stencil
→ publish root offset inside the inactive arena
→ append remaining semantic stencils
→ append FORLOOP branch
→ patch taken branch to root offset
→ patch loop-completed branch to local exit stub
→ validate complete image
→ mprotect RX
→ publish entry owner
```

This is publish-before-bind for native code.

## 15. Concurrency and suspension

A trace site has at most one recording owner. While it is `TraceRecording`:

- the owning activation can continue or suspend with its recorder retained;
- another activation executes the residual Lua loop;
- no activation executes the RW arena;
- successful publication replaces the site publication atomically at the Lua owner boundary.

Published RX traces are immutable and can be shared by activations whose entry guards accept them. Activation-specific
facts remain in the frame and are never patched into a shared trace without guards.

Native multi-threaded publication is out of V1. It requires a separate atomic publication contract; no lock-free scheme
is implied by this design.

## 16. What is and is not a guard

A guard protects an exact semantic assumption required by emitted instructions:

```text
prototype identity
frame generation contract
numeric value tag
normalized numeric-for mode
```

These are not branch-frequency profiles. V1 has no hotness, ranking, replacement, or probabilistic policy.

An ordinary guest conditional is not automatically a guard. V1 rejects loops with internal data-dependent control.
A later branching-trace vocabulary would need explicit taken/not-taken guard leaves and terminal side exits.

## 17. Failure visibility

Recording can end only through named alternatives:

```text
Published
LoopCompletedBeforeBackedge
UnsupportedOpcode
UnsupportedValue
InternalBranchRejected
CapacityRejected
ObjectShapeRejected
MachineCodeValidationRejected
OwnershipRejected
```

A rejected structural site remains rejected with its typed diagnostic. A guard failure during execution is a normal
terminal outcome and does not mutate the trace artifact.

## 18. Minimum correctness matrix

V1 validation is deliberately focused:

```text
integer positive-step loop
integer negative-step loop
floating positive-step loop
zero-trip loop
integer overflow
fixed return
unsupported opcode rejection
unsupported value rejection
capacity rejection
guard exit with exact resume PC
published code is RX and never RWX
released entry rejection
two activations while one recorder is suspended
JIT and -joff semantic equality
deterministic machine-code and projection identity
```

No broad closure matrix or benchmark expansion occurs before these pass.

## 19. Success criterion

The experiment succeeds only if a recorded loop has this steady state:

```text
one FFI entry
→ exact native numeric recurrence
→ direct rel32 backedge
→ terminal loop-completed or guard exit
```

The backedge must contain no opcode fetch, property query, recorder call, Lua callback, specialization selection, or
mutable-code operation.

The trace must beat or explain its relationship to the existing generated-Lua exotype baseline. A slower but correct
trace remains research evidence; it does not replace the baseline automatically.
