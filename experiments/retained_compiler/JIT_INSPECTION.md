# LuaJIT inspection of the retained compiler

This note records the trace and machine-code shape of the physical symbol, resolution, type, lowering, and
emission paths. Addresses and trace numbers vary between processes; source methods and operations are the
stable identities.

## Commands

```sh
luajit -jv experiments/retained_compiler/oneshot_bench.lua cdef 800
luajit -jdump=im experiments/retained_compiler/oneshot_bench.lua cdef 800
```

The inspected workload is one fresh 800-binding compilation. No warm compilation precedes it.

## Trace graph

A representative run created 40 traces. The listing included:

```text
symbol hash loop
symbol-chain and text-equality loops
parser expression recurrence
binding-index construction loop
NameExpr resolution tail recurrence
ExprRef typecheck tail recurrence and concrete leaf side traces
ExprRef lowering tail recurrence and concrete leaf side traces
instruction emission tail recurrence and leaf side traces
```

The number varies by side-trace timing, normally around 35–48 for this workload. All of these traces are
created and used during the first compilation.

## Binding-index construction

`Resolver:run` iterates concrete bindings and fills the generation-stamped symbol lookup facet:

```lua
for index = 0, cc.program.binding_count - 1 do
    local binding = cc.program.bindings[index]
    local lookup = cc.resolutions.by_symbol[binding.symbol]
    if lookup.generation == cc.generation then ... end
    lookup.binding, lookup.generation = index, cc.generation
end
```

Representative loop IR has this shape:

```text
BSHL   binding_index, +5       ; 32-byte Binding
ADD    root, binding_offset
XLOAD  binding.symbol
BSHL   symbol_id, +3           ; 8-byte SymbolBindingEntry
ADD    root, lookup_offset
XLOAD  lookup.generation
NE     root.generation, lookup.generation
XSTORE lookup.generation, root.generation
XSTORE lookup.binding, binding_index
ADD    binding_index, +1
LE     binding_index, binding_count
PHI    binding_index
```

Reference-cdata wrappers are sunk in this loop. The emitted x64 loop is direct loads, shifts, adds, one
generation comparison, two stores, increment, and backedge. The inspected trace contained 55 IR operations
and 275 bytes of machine code. There is no Lua table access, schema operation, hash lookup, allocation, or
helper call in the loop body.

## Name resolution

`NameExpr:resolve` performs:

```text
SymbolId → generation-stamped BindingId
BindingId → binding.value.id
name expression id > binding value id
expression id → ResolutionEntry
store BindingId and generation
tail-call resolver completion
```

The recurring tail trace contains typed `XLOAD`/`XSTORE` operations and constant physical offsets. It does
not compare strings or source bytes.

## Remaining allocation boundary

The typecheck and lowering tail cycles trace successfully, but the dump still contains some unsunk `CNEWI`
reference-cdata values at cross-trace leaf boundaries. Their machine code calls `lj_mem_newgco`. This agrees
with the stopped-GC measurement of approximately 1.25 KB growth per small compilation.

This is not semantic allocation: all retained compiler facts remain in the root. It is LuaJIT materializing
temporary references between trace roots. Possible experiments are:

1. move recurrence onto the owning store and pass integer indices;
2. coarsen typecheck/lowering into source-order store loops;
3. compare leaf-specific index recurrences with the current `ExprRef` router;
4. retain the current shape if the allocation and readability tradeoff is acceptable.

The dump therefore supports both conclusions: CDEF field access lowers to compact native memory operations,
and overly fragmented trace boundaries can still materialize temporary cdata references.
