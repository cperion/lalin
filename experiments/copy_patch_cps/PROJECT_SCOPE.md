# Copy-and-patch research scope after one-shot trace recording

Status: design draft.

## Central question

The project is no longer primarily asking whether fixed numerical stencils can be copied safely. That question has
already been answered by the scalar, SIMD, negative-space, U64 learned-loop, W^X, and ownership experiments.

The new central question is:

> Can a closed Lua 5.5 semantic machine execute one loop iteration, remember the exact path with a bounded CPS recorder,
> seal that memory as a native copy-patched recurrence, and resume safely through coherent-frame terminal exits?

## What remains foundational

The following existing results are retained as mechanical contracts:

```text
ELF section and relocation extraction
validated rel32 successor patching
validated Immediate8 patching
straight-line jump stripping
publish-before-bind native cycles
page-isolated RW → RX publication
typed LuaJIT FFI entry
stable executable ownership
borrow and release rejection
deterministic machine-code projection
JIT-independent host correctness
```

`F64MapPipelineV1`, `F32MapPipelineV1`, the negative-space terminal suite, and `U64BulkV1` remain closed benchmarks and
differential fixtures. They do not become a generic vector framework.

## What changes role

### U64 native learner

The current U64 learner is reclassified as a native installation and ownership proof. Its facts are passed by Lua, so
it is not evidence of genuine runtime discovery. Its useful contributions are:

```text
one-shot publication
prepatched variants
exact-tail macro generation
stable direct recurring entry
separate learner and mutable-slot pages
W^X and generation tests
```

The canonical recorder will allocate a fresh arena and publish it immutably rather than repeatedly rewriting a slot.

### StencilFun

`StencilFunV1` remains a closed authored algebra and differential surface for the numerical vocabularies. It is not the
front end for Lua 5.5 traces and receives no universal operation or terminal protocol.

### Existing Lua 5.5 exotypes

`experiments/lua55/cps_exotype_codegen.lua` remains:

```text
the static residual baseline
the semantic differential oracle
the owner/property model for immutable prototype structure
the proof that opcode and PC dispatch can disappear before recurring execution
```

The trace recorder extends the same concrete opcode-leaf doctrine. It does not introduce a competing opcode handler
table or a second generic bytecode IR.

## New project layers

### Layer 1: exact Lua 5.5 semantics

Owns:

```text
decoded prototype plus concrete opcode and instruction owners
exact numeric values
frame ownership
numeric-for normalization
guest diagnostics and terminal outcomes
```

This layer is backend-independent.

### Layer 2: static exotype projection

Owns immutable facts available when a prototype is loaded:

```text
instruction identities
CFG topology
block ownership
constant references
static successor roles
supported/rejected semantic leaves
```

It continues to produce the generated-Lua residual baseline.

### Layer 3: one-shot recording machine

Owns the first dynamic iteration:

```text
numeric-for mode
current semantic instruction
bounded RW arena
typed exits
deterministic recording projection
publication state
```

It emits exact bytes directly from concrete semantic leaf methods. It is not an optimizer pass manager.

### Layer 4: closed Lua 5.5 stencil bank

Owns physical machine-code vocabulary and ABI:

```text
entry and terminal stubs
numeric guards
numeric effects
numeric-for control
backedge
typed holes
object-shape validation
```

This bank is domain-specific. Numerical array stencils are not reused as generic machine nodes.

### Layer 5: immutable trace artifact

Owns:

```text
RX memory
typed entry
prototype and frame contracts
guard assumptions
terminal exits
deterministic projection
release lifecycle
```

### Layer 6: residual host boundary

Owns terminal transitions only:

```text
loop completed
guest returned
guard failed
unsupported behavior
guest error
future call/metamethod/suspension exits
```

Native-to-Lua callbacks never occur in the middle of a trace.

## Revised implementation order

### Milestone A — owner vocabulary and ABI freeze

1. Declare the exact owner identities, properties, quotation leaves, failures, and artifacts.
2. Freeze `Lua55NumericValue`, `Lua55TraceFrame`, and terminal exit encodings.
3. Freeze the SysV public entry and internal stencil register protocol.
4. Freeze the V1 opcode and semantic leaf subset.

No machine-code work proceeds until these contracts are reviewed.

### Milestone B — recording without native execution

1. Extend concrete Lua 5.5 opcode leaves with recording methods.
2. Record one numeric-for iteration into a deterministic typed projection.
3. Validate integer, floating, negative-step, zero-trip, and rejection behavior against the residual baseline.
4. Prove named-machine control and absence of handler dispatch.

This validates semantics before executable-memory mechanics are involved.

### Milestone C — direct stencil emission

1. Build the closed Lua 5.5 trace stencil bank with GCC.
2. Validate every section, relocation, terminal jump, and hole.
3. Let the same opcode leaf methods append executable bytes and projection entries.
4. Close the first backedge using publish-before-bind.

### Milestone D — W^X trace execution

1. Allocate a fresh page-isolated arena per recording.
2. Record only while RW and inactive.
3. Seal once as RX.
4. Enter through one SysV FFI boundary.
5. Return through exact terminal exit stubs.
6. Never rewrite an installed trace.

### Milestone E — coherent side exits

1. Add exact type and generation guards.
2. Commit every instruction effect to the canonical frame.
3. Return the exact resume PC on guard failure.
4. Resume through the residual Lua machine without snapshots or deoptimization machinery.

### Milestone F — ownership expansion

In this order:

```text
recursive numeric calls
concurrent activations
suspended coroutines
upvalue cells
collectable value ownership
general calls and returns
varargs
metamethod terminal exits
errors
to-be-closed values
```

Each addition requires an exact owner, quotation, frame, and lifetime contract. None is represented by a generic object
pointer or optional context fields.

## Work explicitly stopped

Until the Lua 5.5 trace milestones are evaluated, stop expanding:

```text
general numerical stencil leaves
new StencilFun domains
alignment variant matrices
speculative alias variants
unmeasured small-count variants
generic specialization helpers
per-domain native learners
trace trees
hotness counters
profile databases
SSA or generic native IR
snapshot/deoptimization frameworks
```

## Relationship to production Lalin

This scope change applies to the isolated research path only.

Production remains:

```text
LalinTree ASDL
→ typed compiler facts
→ CBackendUnit
→ emit_c
→ GCC shared object or AOT artifact
```

No production module imports the copy-and-patch experiment. Promoting any result requires a separate architecture
decision and an explicit update to the production prohibition in `AGENTS.md`.

## Decision gates

### Gate 1: semantic validity

Does the recorder reproduce exact Lua 5.5 numeric-loop behavior and exact terminal PCs?

### Gate 2: architectural validity

Does concrete leaf ownership remain visible, with no generic IR, handler map, side table, or context bag?

### Gate 3: ownership validity

Are frame values, recording arenas, RX artifacts, suspension, and release owned exactly?

### Gate 4: runtime validity

Does the installed backedge contain no recorder or dispatch, and do all exits return through a coherent frame?

### Gate 5: performance relevance

Does the native trace improve a workload where generated Lua residual blocks are insufficient, especially under `-joff`
or for exact int64 semantics? If not, retain it as evidence rather than architecture.

## Intended final shape

```text
runtime-loaded Lua 5.5 prototype
→ immutable exotype owners and static projection
→ residual Lua execution
→ first numeric-loop initialization
→ bounded one-shot CPS recording
→ immutable native trace artifact
→ direct recurrence
→ coherent terminal return to residual Lua
```

The project remains a collection of exact domain machines. The trace recorder is the Lua 5.5 machine's learning
mechanism, not a universal runtime service.
