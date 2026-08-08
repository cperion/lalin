# Retained physical compiler experiment

This experiment tests one narrow proposition: a compiler can be authored directly as a fixed hierarchical
retained machine without ASDL and without a native-code backend.

It compiles a small expression language into a deterministic textual register artifact. It does not call
GCC, emit machine code, or modify Lalin's current compiler.

## Physical compiler root

`state.lua` declares the complete persistent compiler before any behavior is installed:

```text
RetainedCompilerV1_Compiler
├── Source
├── SymbolStore → interned text + entries + generation buckets
├── ExpressionStore
│   ├── IntegerExpr[4096]
│   ├── NameExpr[4096]
│   ├── BinaryExpr[4096]
│   └── source-order ExprRef[4096]
├── Program → Binding[1024] + returned expression
├── ResolutionFacet[expression identity]
├── TypeFacet[expression identity]
├── LowerFacet[expression identity]
├── InstructionStore[8192]
├── Artifact[262144 bytes]
├── Diagnostic
├── Scanner
├── Parser
├── Resolver
├── Typechecker
├── Lowerer
└── Emitter
```

One concrete root cdata owns all retained bytes, entities, phase machines, projections, diagnostics, and
the final artifact. Program cardinality varies inside explicit capacities; runtime ownership topology does
not vary.

## Replacing the ASDL vocabulary

The experiment uses these direct physical equivalents:

```text
product               → named C struct
closed expression sum → ExprRef tag + segregated concrete leaf stores
unique entity         → source-order expression id
many [T]              → counted fixed-capacity array
projection            → parallel facet indexed by expression id
leaf semantic method  → metatype method on IntegerExpr, NameExpr, or BinaryExpr
immediate alternative → named proper-tail compiler exit
durable failure       → exact Diagnostic product
phase                 → child machine embedded in Compiler
```

`ExprRef` is the sole owner of physical expression-alternative decoding. It validates the tag and typed
index, then tail-calls the concrete leaf method. Variant methods own typechecking and lowering. There is no
class lookup, visitor, handler map, AST object allocation, pass registry, generic compiler context, or
semantic side table.

## Fixed control hierarchy

```text
Compiler:compile
  → Parser:run
  → Compiler:parsed
  → Resolver:run
  → Compiler:resolved
  → Typechecker:run
  → Compiler:typed
  → Lowerer:run
  → Compiler:lowered
  → Emitter:run
  → Compiler:completed | Compiler:rejected
```

Container cursors are exact child-machine fields. Stable unbound methods form phase and leaf-completion
edges. Bounded token scanning and shunting-yard arithmetic remain ordinary local work inside the parser.

The lower facet is not stored on source expressions. Resolution, type, and register decisions remain
parallel retained projections aligned by stable expression identity.

## Example

Input:

```text
let x = 40;
let y = x + 2 * 3;
return y - 1;
```

Artifact:

```text
r0 = const 40
r1 = const 2
r2 = const 3
r3 = mul r1, r2
r4 = add r0, r3
r5 = const 1
r6 = sub r4, r5
return r6
```

## Current evidence

The 1,215,232-byte root contains 100 bytecode `CALLT` edges, including the optional concrete libgccjit
instruction-projection operation. The differential implementation uses the repository's GC-backed ASDL runtime
for the same products, sums, leaf methods, phase facts, diagnostics, and textual artifact. Sixty-nine valid
and four rejected programs agree under JIT and `-joff`.

Seven isolated-process medians for the initial small program were:

```text
mode   workload       CDEF       ASDL
JIT    same source    2.326 us   10.093 us
JIT    64 programs    2.842 us   11.039 us
-joff  same source   91.520 us   28.067 us
-joff  64 programs   94.380 us   29.173 us
```

With GC stopped after warmup, 1,000 same-source compilations grew the Lua heap by approximately 1.250 KB
per CDEF compile and 8.712 KB per ASDL compile. The CDEF path still allocates temporary references and
emission strings; only retained compiler state is allocation-free.

The result is conditional. CDEF is 3.9–4.3 times faster when LuaJIT closes the physical compiler trace and
allocates about one seventh as much Lua heap. With the JIT disabled, the recursive plain-Lua ASDL frontend
is about three times faster than the FFI-heavy physical frontend. The parsers are semantically equivalent
but not algorithmically identical: CDEF uses a retained shunting-yard parser while ASDL uses recursive
descent. This is architecture evidence, not yet a storage-only microbenchmark.

### One-shot tracing

A fresh process can trace during its first and only compilation because scanner, parser, resolver,
typechecker, lowerer, and emitter blocks recur over many tokens and expressions. Phase entry executes once,
but phase recurrence does not.

A linear expression workload removes binding lookup as a variable. Seven fresh-process medians, excluding
module/schema loading and root allocation, were:

```text
terms   CDEF JIT   ASDL JIT   CDEF -joff   ASDL -joff
20       0.506 ms   1.109 ms     0.304 ms      0.119 ms
100      1.981 ms   2.638 ms     1.482 ms      0.472 ms
500      1.661 ms   3.786 ms     8.242 ms      2.739 ms
1000     1.693 ms   5.297 ms    16.302 ms      5.500 ms
2000     2.383 ms   7.887 ms    30.212 ms     11.155 ms
```

For 20 and 100 terms, ASDL with the JIT disabled is the fastest one-shot configuration. Between 100 and
500 terms, the physical trace amortizes its construction and becomes the fastest configuration. At 2,000
terms, the one-shot CDEF compile creates about 19–25 traces and is 3.3 times faster than ASDL JIT and 4.7
times faster than ASDL `-joff`. Lowering `hotloop` to one remains counterproductive because it traces too
many cold paths.

When module/schema construction and the 1 MB CDEF root allocation are included, but process startup and
source generation remain excluded, seven fresh-process medians are:

```text
terms   CDEF JIT   ASDL JIT   CDEF -joff   ASDL -joff
20       2.006 ms   5.258 ms     1.637 ms      3.137 ms
500      2.803 ms   7.346 ms     9.417 ms      5.985 ms
2000     3.287 ms  11.101 ms    32.311 ms     14.483 ms
```

Under default LuaJIT operation, the complete physical path wins even for the small input because CDEF
declaration, sealing, and root construction cost less than building the GC-backed ASDL context and generated
constructors. This setup result is specific to the current runtimes and must not be conflated with the
compile-only crossover.

### Physical symbol and binding stores

The parser now interns each identifier once into an exact symbol store containing text bytes, hash entries,
and generation-stamped buckets. Expressions and bindings retain `SymbolId`, not source spans. Resolution
builds a generation-stamped `SymbolId → BindingId` facet in one binding pass, then resolves every name by
direct indexed lookup. No large array is cleared between root generations.

Seven fresh-process medians show the result:

```text
bindings   CDEF JIT   ASDL JIT   CDEF -joff   ASDL -joff
20          2.573 ms   3.042 ms     0.950 ms      0.310 ms
100         3.070 ms   4.896 ms     5.051 ms      1.575 ms
400         3.414 ms   6.085 ms    19.448 ms      8.633 ms
800         3.797 ms  11.166 ms    39.148 ms     24.046 ms
```

The previous quadratic byte-span resolver took about 34 ms at 800 bindings. The physical symbol/index
design reduces this to 3.8 ms and is 2.9 times faster than ASDL JIT on the first compilation. With the JIT
disabled, FFI field traffic remains slower than plain Lua.

### LuaJIT emitted-code inspection

`-jv` reports a bounded graph of approximately 35–48 traces for the fresh 800-binding compile. The symbol
hash, symbol equality, binding-index build, name resolution, typecheck, lowering, and emission recurrences
all trace during that one invocation.

The binding-index trace lowers to direct address arithmetic and typed memory operations: binding index is
scaled by the 32-byte binding size, `SymbolId` is scaled by the 8-byte lookup-entry size, generation is
guarded, and binding/generation fields are written with `XSTORE`. Its 55-op IR loop emits 275 bytes of x64
machine code with no helper call inside the hot loop.

The name-resolution tail cycle likewise becomes direct loads, generation guards, source-order comparison,
and stores into the aligned resolution facet. One remaining cost is visible in typecheck/lowering traces:
some nested reference-cdata values cross trace boundaries and call `lj_mem_newgco`. This corresponds to the
remaining approximately 1.25 KB of stopped-GC growth per small compile and identifies the next physical
optimization boundary.

See [`JIT_INSPECTION.md`](JIT_INSPECTION.md) for commands and representative IR/machine-code shapes.

Therefore a one-shot compiler can benefit from tracing when concrete recurring paths process enough
entities after trace construction. Exact symbol identity and indexed facets are part of the physical
algorithm, not optional storage details.

## Scope

This is a physical-design experiment, not a proposal to rewrite Lalin immediately. Its core compile path
does not load GCC or produce executable code. The isolated [`../gccjit_driver/`](../gccjit_driver/) adapter
uses concrete instruction leaf methods to test executable cooking without changing the canonical artifact
or making libgccjit a dependency. The next questions are physical:

1. Do tagged references plus segregated leaf stores remain clear with richer closed alternatives?
2. Can scopes, functions, control flow, and diagnostics remain exact without a generic context?
3. Should capacities be configuration envelopes or separately owned typed stores?
4. Does direct physical routing remain efficient under realistic compiler workloads?
5. Which compiler facts require durable facets, and which should remain named control exits?

Run:

```sh
luajit experiments/retained_compiler/test.lua
luajit -joff experiments/retained_compiler/test.lua
luajit experiments/retained_compiler/compare_test.lua
luajit -joff experiments/retained_compiler/compare_test.lua
luajit experiments/retained_compiler/compare_bench.lua cdef corpus 50000
luajit experiments/retained_compiler/compare_bench.lua asdl corpus 50000
luajit -joff experiments/retained_compiler/compare_bench.lua cdef corpus 3000
luajit -joff experiments/retained_compiler/compare_bench.lua asdl corpus 3000
luajit experiments/retained_compiler/allocation_bench.lua cdef 1000
luajit experiments/retained_compiler/allocation_bench.lua asdl 1000
luajit experiments/retained_compiler/oneshot_bench.lua cdef 20
luajit experiments/retained_compiler/oneshot_bench.lua asdl 20
luajit -joff experiments/retained_compiler/oneshot_bench.lua cdef 20
luajit -joff experiments/retained_compiler/oneshot_bench.lua asdl 20
luajit experiments/retained_compiler/oneshot_bench.lua cdef 2000 default expression
luajit -jv experiments/retained_compiler/oneshot_bench.lua cdef 800
luajit -jdump=im experiments/retained_compiler/oneshot_bench.lua cdef 800
luajit experiments/gccjit_driver/compiler_test.lua
luajit experiments/gccjit_driver/retained_bench.lua gccjit 2000 7 3
luajit experiments/retained_compiler/oneshot_bench.lua asdl 2000 default expression
luajit -joff experiments/retained_compiler/oneshot_bench.lua cdef 2000 default expression
luajit -joff experiments/retained_compiler/oneshot_bench.lua asdl 2000 default expression
luajit experiments/retained_compiler/end_to_end_bench.lua cdef 2000
luajit experiments/retained_compiler/end_to_end_bench.lua asdl 2000
luajit -joff experiments/retained_compiler/end_to_end_bench.lua cdef 2000
luajit -joff experiments/retained_compiler/end_to_end_bench.lua asdl 2000
```
