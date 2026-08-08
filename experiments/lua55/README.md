# Lua 5.5 bytecode → proper exotypes → residual CPS → LuaJIT

This experiment loads real Lua 5.5 bytecode at runtime and turns it into specialized Lua functions. It is the
canonical behavior-focused example of the Exotyped CPS Machines pattern described in:

```text
exotyped_cps_machines.md
```

The implementation is intentionally partial. Its purpose is to make staging, exotype properties, block fusion,
cycle binding, and direct CPS execution physical and measurable.

## Short explanation

A loaded bytecode function contains stable structure: opcodes, operands, constants, and control-flow edges. A
normal interpreter repeatedly decodes that structure. This experiment instead creates first-class owners for the
prototype, instruction occurrences, and basic blocks.

The compiler asks those owners lazy properties:

```text
FrameLayout       What runtime frame does this prototype need?
EmitInstruction   What exact quotation implements this instruction?
ExecuteBlock      What fused function implements this basic block?
```

Property evaluation happens only during initial staging. Runtime executes the bound functions directly.

## Pipeline

```text
Lua 5.5 chunk bytes
  → undump prototype
  → cold-link constants and CFG edges
  → create prototype, instruction, and block exotype owners
  → query reached block properties lazily
      → query concrete opcode leaf properties
      → compose straight-line instruction quotations
      → generate one residual block function
      → publish the block identity
    → bind direct successor upvalues
  → execute proper-tail CPS blocks
  → LuaJIT traces recurring control
```

## Why this is a proper exotype example

The generated type is created after the chunk is loaded. Its behavior depends on runtime-provided bytecode, but
that bytecode does not remain a runtime dispatch structure.

The implementation includes:

- first-class owner identities;
- first-class property identities;
- memoized property results;
- active-query cycle traces;
- concrete opcode leaf methods;
- exact quotation alternatives;
- lazy property demand;
- publish-before-bind control cycles;
- deterministic source and control projections;
- a frame-layout property;
- no property lookup in recurring execution.

## Exact quotation leaves

Concrete opcode leaves produce one of these staging values:

```text
EffectQuote       straight-line register mutation
JumpQuote         unconditional CPS transfer
ForPrepQuote      loop preparation and body/exit choice
ForLoopQuote      loop backedge and exit choice
ReturnQuote       terminal return values
ClosureQuote      child prototype plus next edge
RejectQuote       visible unsupported behavior
```

A block property composes these leaves into a `BlockQuote`. Quotation classes own their composition behavior; the
compiler does not switch on quotation tags.

## Block fusion

An effect instruction is fused with its successor when that successor has exactly one predecessor. Join points,
branches, returns, and loop control remain CPS boundaries.

The integer loop residual includes this fused block:

```lua
local EDGE_1, EDGE_2
return function(self)
  local r = self.r
  r[1] = r[1] + r[4]

  local step = r[3]
  local index = r[4] + step
  r[4] = index

  if step > 0 and index <= r[2]
      or step < 0 and index >= r[2] then
    return EDGE_1(self)
  end
  return EDGE_2(self)
end
```

`EDGE_1` and `EDGE_2` are bound once during staging. The hot path does not look up a program counter or opcode.

## Cycles

A loop creates a cyclic control graph. The compiler handles it by publishing a generated block function before
recursively materializing and binding its successors:

```text
create block closure
→ cache closure by start PC
→ follow successors
→ loop backedge finds cached closure
→ bind successor upvalues
```

`debug.setupvalue` is used only during cold binding. Runtime uses ordinary direct closure references.


## Frame representation

Lua registers can contain numbers, strings, tables, closures, and other garbage-collected values. The frame-layout
property therefore selects a Lua-owned register table rather than forcing registers into CDEF memory.

```lua
state = {
    r = {},
    top = 0,
}
```

The exotype pattern determines representation late; it does not require every representation to be CDEF.

## One semantic source

The quotation query owns executable behavior, successor dependencies, operands, and readable source. There is no
separate executable implementation and diagnostic renderer that can silently diverge.

## Files

```text
undump55.lua                    Lua 5.5 chunk reader
undump_test.lua                 decoder validation
cps_exotype_codegen.lua         canonical exotype/block residualizer
cps_exotype_codegen_test.lua    baseline exotype, fusion, projection, and runtime checks
bench.lua                       canonical exotype runtime benchmark
codegen_bench.lua               setup and first-reach measurements
prototype_bench.lua             private multi-module block proof
sample_5.5.lua/.luac            matched source and real bytecode
```

## Current semantic slice

The residualizer supports the bundled main function and its two numerical children:

- moves;
- integer and floating loads;
- constant loads;
- numerical add, subtract, multiply, and divide;
- constant numerical arithmetic;
- numerical loops;
- closures without captured locals;
- vararg preparation;
- fixed returns.

Unsupported behavior fails visibly. Complete Lua 5.5 semantics are not claimed. Missing work includes exact int64
behavior, captured upvalues, general calls, full varargs, metamethod fallbacks, errors, coroutines, and to-be-closed
values.

## Run

```sh
luajit experiments/lua55/undump_test.lua

luajit experiments/lua55/cps_exotype_codegen_test.lua
luajit -joff experiments/lua55/cps_exotype_codegen_test.lua

luajit experiments/lua55/bench.lua sum 5000 1000 7
luajit experiments/lua55/bench.lua mixed 5000 1000 7
luajit -joff experiments/lua55/bench.lua sum 100 1000 3

luajit experiments/lua55/codegen_bench.lua 100 5
luajit experiments/lua55/prototype_bench.lua 20 200 1000 5
```

## Current measurements

For 5,000 calls of 1,000 guest iterations:

```text
integer loop    1.013 ns/guest iteration
mixed loop      0.870 ns/guest iteration
```

With LuaJIT disabled:

```text
exotyped integer loop    22.090 ns/guest iteration
exotyped mixed loop      26.590 ns/guest iteration
```

Staging measurements for 100 modules:

```text
setup                    21.340 us/module
setup plus first reach  151.730 us/module
```

Twenty modules with 40 alternating generated functions measure approximately 0.975 ns per guest iteration. Each
generated block comes from a separate `loadstring` chunk and therefore has a private Lua prototype.

This is the only Lua 5.5 residual execution path. Measurements report its runtime behavior and staging costs.


## Extension rule

Extend the existing exotype vocabulary rather than adding another residual architecture:

```text
new opcode semantics
→ concrete opcode leaf method
→ exact quotation result
→ block composition
→ projection checks
→ JIT and -joff correctness
→ trace and benchmark inspection
```
