# Generated CPS Specialization

## Exotype owners producing direct residual control on a tracing host

### Concept paper and experimental report

General pattern: [`exotyped_cps_machines.md`](exotyped_cps_machines.md).

Broader architecture: [`composed_state_machines_whitepaper.md`](composed_state_machines_whitepaper.md).

## Abstract

Generated CPS Specialization (GCPS) executes a fixed foreign instruction graph by making known control concrete
before recurring execution. Runtime-loaded structure creates first-class exotype owners. Lazy property queries
produce exact instruction quotations, fused basic-block functions, and aligned source/control/operand projections.
Generated functions are published before cyclic successors are bound. Runtime then consists only of direct
proper-tail calls over guest state.

LuaJIT performs a second specialization over runtime values, guards, branch frequencies, and hot paths. The foreign
frontend therefore does not require a generic optimizer, register allocator, or native emitter.

For the bundled Lua 5.5 numerical loops, exotyped block CPS measures approximately 1.013 and 0.870 ns per guest
iteration. The semantic slice is deliberately incomplete.

## 1. Problem

A generic interpreter repeatedly rediscovers facts already fixed by a loaded program:

1. opcode identity;
2. operand locations;
3. constants;
4. fallthrough and branch targets;
5. loop backedges;
6. paired fallback instructions.

A tracing JIT can optimize some dispatch, but shared handlers and generic instruction records still affect trace
shape. A conventional compiler removes dispatch by introducing a much larger backend.

GCPS asks:

> What is the smallest residual program that exposes fixed foreign control to the host JIT without reimplementing
> the host JIT?

## 2. Chosen pattern

```text
fixed foreign bytecode
  → decode and link
  → create prototype, instruction, and block exotype owners
  → query reached block properties
      → query concrete instruction quotations
      → compose straight-line effects
      → generate one block function
      → publish function identity
      → bind successor functions
  → execute direct residual CPS
  → host tracing specializes runtime values
```

This separates two kinds of knowledge:

```text
fixed program and control facts → exotype property residualization
dynamic value and path facts    → host tracing
```

Foreign loops remain direct CPS cycles. Structured source reconstruction is unnecessary.

## 3. Exotype owner model

A decoded prototype, instruction occurrence, or basic block is a staging entity with stable identity and lazy
properties.

The Lua 5.5 implementation defines:

```text
FrameLayout
EmitInstruction
ExecuteBlock
```

A property query is memoized by owner and property identity. Active recursive evaluation reports a query cycle.
Property results are checked against exact result classes.

The property protocol is absent from recurring execution.

## 4. Concrete instruction quotations

Each supported opcode has one concrete semantic leaf. Its `emit` method returns an exact quotation alternative:

```text
EffectQuote
JumpQuote
ForPrepQuote
ForLoopQuote
ReturnQuote
ClosureQuote
RejectQuote
```

Each quotation owns its block-composition behavior. The block compiler does not inspect a quotation tag or choose a
handler from a runtime table.

An effect quotation can fuse through a successor with one predecessor. Control quotations terminate the block and
name direct successors.

Executable source, control dependencies, operands, and readable projection all derive from the same quotation.

## 5. Residual execution

The core correspondence is:

```text
persistent guest state       → generated `self`
prototype structure          → prototype exotype owner
instruction occurrence       → concrete instruction owner and quotation
straight-line region         → fused block owner and function
known edge                   → bound proper-tail successor
conditional edge             → direct choice between successors
foreign terminal             → return or visible rejection
readable residual            → block listing projection
runtime specialization       → host JIT
```

No recurring edge reads an opcode, dispatch table, program counter, instruction record, or owner property.

## 6. Publish before bind

Control cycles must not become property-evaluation cycles.

For each reached block:

```text
compile closure
→ publish closure by block start PC
→ recursively materialize successors
→ bind successor upvalues
```

A loop backedge therefore finds an already published closure.

`debug.setupvalue` is a cold binding mechanism in the current Lua probe. Generated execution uses ordinary private
upvalues.

## 7. Private block prototypes

LuaJIT associates traces with function prototypes. Every generated block is compiled from its own source chunk, so
separate blocks and separately loaded modules do not accidentally share one trace identity.

The multi-module benchmark alternates 40 generated child functions at approximately 0.975 ns per guest iteration.

## 8. Lua 5.5 evaluation

The real Lua 5.5 fixture contains an integer summation loop and a mixed-number multiply/add loop.

```text
integer loop    1.013 ns/guest iteration
mixed loop      0.870 ns/guest iteration
```

With LuaJIT disabled, the exotyped blocks measure approximately 22.1 and 26.6 ns per guest iteration.

The sample reaches 23 instructions and residualizes them as nine blocks. Setup is approximately 21 us per module.
Setup plus first reach is approximately 152 us in the active 100-module benchmark.

The exotyped residual passes with JIT enabled and disabled. Unsupported behavior fails visibly.

Complete Lua 5.5 semantics are not claimed. Missing work includes exact 64-bit integer behavior, captured upvalues,
general calls, recursion, complete varargs, metamethod fallbacks, errors, coroutines, and to-be-closed values.

## 9. WebAssembly evidence

The WebAssembly experiment uses a related lazy occurrence-owner lifecycle. Concrete opcode owners analyze stack
shape, publish identities before cyclic binding, and produce source/control/operand facets.

Wasm-specific specialization flattens validated operand-stack topology into CPS arguments. Its mixed loop has
measured near native V8 WebAssembly, while exact wrapping-i32 recurrence remains trace-sensitive.

The Lua and Wasm implementations intentionally do not share a generic runtime or universal quotation IR. They share
the design rule that fixed structure belongs to cold semantic owners and direct residual artifacts belong to hot
consumers.

## 10. Relationship to established techniques

GCPS draws from partial evaluation, Futamura projections, CPS, threaded interpretation, tracing compilation, staged
metaprogramming, and Terra exotypes. The combination is the useful design pattern; it is not a priority claim.

The key boundary is:

```text
dynamic semantic protocol during staging
  → memoized direct residual artifacts
  → no generic semantic dispatch during execution
```

## 11. Threats and research questions

Current evidence is limited to narrow numerical loops, one LuaJIT environment, incomplete guest semantics, and
small programs.

Open questions include:

1. What exact frame convention supports calls, recursion, and suspension?
2. How should large reachable graphs be prepared incrementally?
3. Which quotation boundaries produce the best LuaJIT traces?
4. How should a failed cyclic materialization roll back?
5. When does staging cost amortize on realistic workloads?
6. Which inferred type facts safely select specialized quotations?
7. Which additional guests can use the pattern without creating a generic framework?

## 12. Conclusion

```text
exotype owners make fixed structure and control concrete
host tracing makes runtime values and hot paths concrete
```

The chosen Lua 5.5 architecture has one exotype/block materializer, one readable projection, and one direct
residual graph.

The carry-forward rule is:

> Let concrete staging owners lazily produce executable and projection artifacts; let runtime consumers use only
> those direct residual artifacts.
