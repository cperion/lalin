# Exotyped CPS Machines

This is the generalized staging kernel for exotype-generated CDEF+CPS machines. It has no generic runtime.
A host compiler resolves lazy type properties, emits exact physical CDEF types, computes the demanded operation
closure, generates one mutually-bound set of direct Lua functions, and then disappears from execution.

## Architecture

```text
Exotype constructor(runtime structural facts)
  → first-class owner
  → lazy layout and first-class operation properties
  → physical CDEF materialization
  → demanded quotation closure
  → direct mutually-bound CPS functions
  → concrete cdata instances
```

The runtime receives only cdata and stable functions. There are no generic machine nodes, boxed messages,
operation-name dispatch, property queries, generated closures per transition, or compiler context arguments.

## Exact quotation alternatives

Operations declare one required result kind:

```text
ExpressionQuote  composable scalar expression
EffectQuote      composable ordered statements
CpsQuote         function body plus explicit stable dependencies
```

These are separate classes rather than an optional expression/statements/compile record. Operation identities
are first-class objects and are used as property keys; runtime strings do not select behavior.

## Physical and behavioral sealing

Physical CDEF layout is materialized and sealed once. Behavior is compiled into standalone stable functions,
so a later program can request a new operation without patching the FFI metatype. Each compiled program captures
its demanded functions directly. Calls inside generated functions refer to mutually-bound lexical locals.

This permits cyclic residual control graphs without permitting cyclic property evaluation. The pipeline example
generates a cycle from its loop continuation back to its first stage using publish-before-bind locals.

## Workloads

`test.lua` validates two independent constructor families:

1. `Record(fields)` and `Array(T, N)` compose expression/effect quotations. Array sum and scale fuse into direct
   field accesses and assignments over by-value records.
2. `Pipeline(stages)` creates a physical machine and a cyclic CPS graph from a runtime stage description. The
   generated graph has entry, concrete stages, loop, completed, and rejected exits.

Both workloads validate exact sizes, constructor interning, query memoization, lazy demand, physical reuse across
compiler instances and behavioral programs, deterministic listings, fusion, direct `CALLT` edges, cyclic residual
control, rejection of true property recursion, and less than 4 KB growth across 10,000 warmed machine turns.

## Run

```sh
luajit experiments/exotyped_cps/test.lua
luajit -joff experiments/exotyped_cps/test.lua
luajit experiments/exotyped_cps/bench.lua 1000000
luajit -joff experiments/exotyped_cps/bench.lua 100000
```

Representative output on the development machine:

```text
ok exotyped cps point=24 batch=104 pipeline=20 operations=7 result=105
exotyped-cps iterations=1000000 ns_per_run=24.182 operations=6 type_bytes=20
```

The benchmark turn executes four rounds through three generated stages and the generated loop continuation.
