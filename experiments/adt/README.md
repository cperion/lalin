# ADT arena vertical-slice experiment

This is an intentionally hardcoded M1 experiment for the architecture in
[`docs/ADT_ARCHITECTURE.md`](../../docs/ADT_ARCHITECTURE.md). It tests whether the
runtime representation has useful LuaJIT trace and memory behavior before any
schema dialect, layout IR, or generator is built.

Compared representations:

- `table_graph`: ordinary Lua table nodes retained through child references.
- `table_bucket`: the same nodes plus per-constructor arrays, giving tables the
  strongest reasonable baseline for constructor-local sweeps.
- `arena`: 8/24 packed handles and separate 65,536-element, `malloc`-backed FFI
  chunks for `Num` and `Binop`. Chunk directories are cdata arrays.

The experiment uses a two-constructor expression sum. It measures construction,
a forced full GC, direct variant sweeps, recursive mixed-tag evaluation, and a
recursive mixed-tag walk. `eval_scalar` additionally loads both child handles
before recursing, so no interior cdata pointer remains live across a call. This
directly tests the interior-pointer rule. Arena bytes are reported separately
because LuaJIT's `collectgarbage("count")` does not account for `malloc` memory.

Run:

```sh
experiments/adt/run.sh
N=3000001 REPS=10 experiments/adt/run.sh
experiments/adt/trace.sh
experiments/adt/profile.sh
```

See [`RESULTS.md`](RESULTS.md) for the first measured run and its design
implications.

Trace logs are written under `target/adt-traces/`. Population construction is
performed with the JIT disabled in `trace.lua`, then traces are flushed and only
the requested operation is recorded. This prevents a clean sweep from looking
megamorphic merely because the setup loop was mixed. `profile.sh` uses the
in-process `jit.p` API so sampling equivalent to `-jp=vf` begins only after
setup and one unmeasured warmup.

Read the results as shape evidence, not universal speed claims. `os.clock()` is
used, each command is a fresh process, and CPU frequency is not pinned. Repeat
runs and use an external benchmark harness before treating small differences as
meaningful. The recursive comparison is deliberately included because packed
storage should not be expected to cure mixed recursive dispatch.
