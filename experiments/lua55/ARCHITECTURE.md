# Exotyped CPS residualization for Lua 5.5 bytecode

Status: binding implementation contract for `cps_exotype_codegen.lua`.

For the general design and introductory terminology, read:

```text
exotyped_cps_machines.md
```

## One sentence

Runtime-loaded bytecode constructs first-class prototype, instruction, and block owners whose lazy properties
produce fused direct CPS functions; only those functions and their frame execute afterward.

## Staging and runtime boundary

Staging performs:

```text
undump
link constants and control edges
construct owners
query properties
compose quotations
compile block source
publish function identities
bind successors
record projections
```

Runtime performs:

```text
read/write frame values
choose direct CPS successors
return guest results
```

Recurring runtime must not perform property lookup, opcode classification, program-counter dispatch, instruction
lookup, source generation, or successor binding.

## First-class properties

The canonical implementation defines three property identities:

```text
FrameLayout
EmitInstruction
ExecuteBlock
```

A property query is keyed by owner and property identity. Results are memoized. Active re-entry reports a query
cycle. Property results are checked against their exact result class.

## Owner families

### Prototype owner

Owns the frame-layout property for one loaded Lua prototype.

### Instruction owner

Owns one decoded occurrence and delegates `EmitInstruction` to its concrete opcode leaf method.

### Block owner

Owns one block start PC. Its `ExecuteBlock` property queries instruction quotations and composes them until control
must transfer or terminate.

Owners contain staging facts. They are not runtime VM objects.

## Concrete opcode leaves

Cold linking assigns each instruction one concrete opcode leaf. The leaf method owns semantics:

```lua
function FORLOOP:emit(instruction)
    return ForLoopQuote(...)
end
```

The recurring path never checks `instruction.op`, `instruction.name`, or a handler map.

Unsupported leaves return `RejectQuote`, making missing behavior visible.

## Quotation sum

Instruction properties return one exact alternative:

```text
EffectQuote
JumpQuote
ForPrepQuote
ForLoopQuote
ReturnQuote
ClosureQuote
RejectQuote
```

Each alternative implements block composition directly. The compiler does not branch on a quotation kind.

A completed block property returns `BlockQuote`, which owns:

```text
start and end instruction identities
ordered source lines
fused instruction projection
control dependencies
child prototype dependencies
```

## Fusion rule

`EffectQuote` can continue composing with its static successor only when the successor has exactly one predecessor.
This forms maximal local straight-line regions without crossing joins.

The following remain boundaries:

- branch targets with multiple predecessors;
- jumps;
- numerical loop control;
- returns;
- closure creation;
- unsupported behavior.

Fusion is a staging decision over exact CFG topology. Runtime has no fusion machinery.

## Demand rule

`Compiler:entry(instruction)` is the only block-entry materializer:

```text
lookup block closure by start PC
→ return it when already published
→ query block owner ExecuteBlock
→ compile source into a private closure
→ publish closure before recursion
→ record deterministic projection
→ materialize successor entries
→ bind successor and child upvalues
→ return closure
```

Only reached blocks are materialized.

## Publish before bind

Publishing before recursive successor materialization closes runtime cycles. A loop backedge finds its already
published header or body closure.

A runtime control cycle is valid. A property function recursively requiring its own unfinished property is an error.


## Residual shape

```lua
local EDGE_1, EDGE_2
return function(self)
    local r = self.r
    r[1] = r[1] + r[4]
    ...
    if repeated then
        return EDGE_1(self)
    end
    return EDGE_2(self)
end
```

`EDGE_1` and `EDGE_2` are private upvalues bound during staging. Proper-tail calls are the residual graph edges.

## Private prototype rule

Every generated block is compiled from its own `loadstring` source chunk. LuaJIT associates traces with function
prototypes, so separate generated blocks and separate loaded modules must not accidentally share one prototype.

The multi-module benchmark alternates 40 generated child functions and validates stable trace isolation.

## Frame layout

The frame-layout property currently produces:

```text
LuaFrame
├── register table
└── top index
```

A Lua table is intentional because registers retain arbitrary collectable Lua values. CDEF is not required by the
exotype pattern and must not be introduced without an exact ownership design for those values.

The current compiler reuses one frame per generated function. Recursive and concurrent calls require explicit
frame ownership and are not yet claimed.

## Projection

Every generated block records:

```text
stable owner key
block start and end PC
ordered instruction PCs and opcodes
literal operands
named successor roles and PCs
readable generated source
```

Executable behavior and projection derive from the same quotation. Do not add a separate renderer with independent
semantics.

Demand order is diagnostic. Deterministic artifacts must use stable prototype and PC identity.

## Lifecycle

Default public entry is lazy:

```text
load bytes
→ create compiler and public entry wrapper
→ no block functions yet
→ first call queries FrameLayout and root ExecuteBlock
→ reached graph materializes and binds
→ subsequent calls enter direct residual root
```

`Program:prepare()` explicitly moves frame and root materialization before execution when first-hit allocation is
not acceptable.


## Frozen rules

1. Keep one canonical exotype/block materializer.
2. Keep one concrete semantic leaf per supported opcode.
3. Use first-class property identities.
4. Memoize each owner-property result.
5. Reject true property recursion with a trace.
6. Fuse only through exact single-predecessor straight-line edges.
7. Publish block identities before binding control dependencies.
8. Keep `self` as persistent guest state.
9. Bind known edges once and execute them as proper-tail calls.
10. Derive executable source and projections from the same quotation.
11. Keep staging state out of recurring execution.
12. Make unsupported semantics fail visibly.
13. Preserve correctness under JIT and `-joff`.
14. Keep generated block prototypes private.
15. Do not add another dispatcher, template backend, generic IR, or residual materializer.

## Opcode extension checklist

1. Validate exact undump operands.
2. Resolve exact static successors.
3. Add or extend the concrete opcode leaf method.
4. Return the correct exact quotation class.
5. Verify fused source and successor projections.
6. Compare with the linked oracle under JIT and `-joff`.
7. Inspect proper-tail bytecode and trace shape.
8. Benchmark only after correctness passes.

Calls, upvalues, full varargs, metamethod fallback, errors, suspension, and to-be-closed values extend the owner and
quotation vocabulary. They do not justify another runtime architecture.

## Measured validation

```text
integer loop    1.013 ns/guest iteration
mixed loop      0.870 ns/guest iteration
```

With JIT disabled, the exotyped blocks measure approximately 22.1 ns and 26.6 ns per guest iteration. Setup is
approximately 21 us per module; setup plus first reach is approximately 152 us for the current fixture.


These measurements validate one narrow numerical slice, not complete Lua 5.5 semantics.
