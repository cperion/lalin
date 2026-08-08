# Tail transfer, host frames, and explicit machine frames

This experiment distinguishes three call shapes that are easy to conflate when authoring machine
syntax.

## Shapes

### Direct tail transfer

```lua
return NEXT(self)
```

LuaJIT emits `CALLT`. The current activation is consumed. Cyclic control becomes a proper-tail CPS
graph and must fit the recorder's measured trace-unroll capacity.

### Ordinary host-framed call

```lua
local result = CHILD(self)
self.unwinds = self.unwinds + 1
return result
```

LuaJIT emits `CALL`, not `CALLT`. The Lua host stack preserves the caller until the child returns.
This is useful only for synchronous, bounded invocation. The frame cannot become durable machine
state and cannot represent suspension or re-entry.

### Explicit-frame CPS call

```lua
self.frames[self.sp] = RESUME_ID
self.sp = self.sp + 1
return CHILD(self)

-- later, possibly after suspension
self.sp = self.sp - 1
return RESUME(self)
```

Entry and resume edges both emit `CALLT`. The semantic stack is exact CDEF state. It survives a public
return and later resume without retaining a Lua activation or allocating a capturing continuation.
The experiment uses fixed direct resume functions, so the hot path has no generic frame dispatcher.

## Run

```sh
luajit experiments/cdef_schema/call_conventions_test.lua
luajit -joff experiments/cdef_schema/call_conventions_test.lua

luajit experiments/cdef_schema/call_conventions_bench.lua tail      8 10000 5 1000
luajit experiments/cdef_schema/call_conventions_bench.lua host      8 10000 5 1000
luajit experiments/cdef_schema/call_conventions_bench.lua explicit  8 10000 5 1000
luajit experiments/cdef_schema/call_conventions_bench.lua suspended 8 10000 5 1000
```

Arguments are shape, nesting depth, operation count, sample count, and `loopunroll`. Run benchmark
shapes in separate processes.

## Measured trace boundaries

Fresh-process sweeps produced these structural thresholds:

```text
shape                    setting           largest closed depth   next observed failure
tail cycle               loopunroll=15     15                     16: unroll limit
host-framed synchronous  loopunroll=15     72                     80: trace too deep
explicit-frame cycle     loopunroll=1000   40                     48: snapshots
```

The non-tail host convention really does avoid the tail-cycle `loopunroll` threshold. It eventually
hits the separate recorder call-depth limit. The explicit-frame convention preserves durable semantics
but does not make trace capacity disappear: its entry-plus-resume cycle is approximately twice its
semantic nesting depth. Returning at suspension boundaries segments that cycle and remained bounded in
the measured depth-64 suspended run.

At depth eight with `loopunroll=1000`, all four shapes traced without aborts and stopped-GC growth was
small and bounded. Synthetic nanoseconds per transition are not application results because LuaJIT can
collapse repeated counter updates. Trace closure, abort reasons, suspension, and allocation are the
evidence from this probe.

## Architectural convention

The useful split is not simply 'inline' versus 'do not inline'. It is:

```text
cold staging invocation
  ordinary Lua calls and metatable/ASDL leaf methods

hot residual transfer
  direct proper-tail CPS edges

semantic non-tail call
  exact explicit frame plus direct tail-called entry/resume edges
```

A syntax layer must preserve this distinction deliberately. It must not depend on whether a generated
Lua expression happens to remain in lexical tail position. Ordinary host frames are allowed only for
bounded synchronous work that cannot suspend. Durable guest/application calls own explicit frames.

